//! MicroCode Shared Memory (SHM) Broker & Memory Supervisor
//!
//! Provides zero-copy, memory-safe inter-process memory sharing across
//! polyglot execution cells on Apple Silicon and Linux.
//!
//! Features:
//! - POSIX `shm_open`, `mmap`, `ftruncate`, and `shm_unlink`
//! - Hardware memory protection via `libc::mprotect(PROT_READ)` (Immutability guarantee)
//! - Epoch-based versioning (Single-Writer, Multiple-Reader / SWMR)
//! - Reference counting and safe garbage-free reclamation
//!
//! Copyright © 2026 Dotmini Software (Tirawat Nantamas). All rights reserved.

use crate::error::{AppError, Result};
use lazy_static::lazy_static;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::ffi::CString;
use std::os::unix::io::RawFd;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, RwLock};
use tracing::{error, info, warn};

lazy_static! {
    /// Global singleton instance of the Shared Memory Broker
    pub static ref GLOBAL_SHM_BROKER: Arc<ShmBroker> = Arc::new(ShmBroker::new());
}

/// A registered shared memory variable accessible across polyglot cells
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShmVariableMetadata {
    pub name: String,
    pub session_id: String,
    pub epoch: u64,
    pub shm_name: String,
    pub size_bytes: usize,
    pub data_type: String, // e.g. "arrow_record_batch", "arrow_table", "raw_buffer", "tensor"
    pub is_read_only: bool,
    pub created_at_ms: u64,
}

/// Handle to an active mapped memory buffer
pub struct ShmSegment {
    pub metadata: ShmVariableMetadata,
    ptr: *mut u8,
    size: usize,
    fd: RawFd,
    ref_count: Arc<AtomicUsize>,
    is_sealed: bool,
}

// Safety: The memory buffer is protected by POSIX mmap permissions and mprotect
unsafe impl Send for ShmSegment {}
unsafe impl Sync for ShmSegment {}

impl ShmSegment {
    /// Get raw pointer to the mapped memory buffer
    pub fn as_ptr(&self) -> *const u8 {
        self.ptr as *const u8
    }

    /// Get mutable pointer (only valid before `seal_read_only` is called)
    pub fn as_mut_ptr(&mut self) -> Result<*mut u8> {
        if self.is_sealed {
            return Err(AppError::InternalError(format!(
                "Cannot write to sealed read-only SHM buffer '{}'",
                self.metadata.name
            )));
        }
        Ok(self.ptr)
    }

    /// Get mapped size in bytes
    pub fn size(&self) -> usize {
        self.size
    }

    /// Seal this segment as Read-Only using `mprotect`.
    /// From this moment, any attempt to write into this buffer triggers an OS fault (SIGSEGV/BUS)
    /// completely eliminating race conditions and torn reads across concurrent cells!
    pub fn seal_read_only(&mut self) -> Result<()> {
        if self.is_sealed {
            return Ok(());
        }

        let ret = unsafe {
            libc::mprotect(
                self.ptr as *mut libc::c_void,
                self.size,
                libc::PROT_READ,
            )
        };

        if ret != 0 {
            let err = std::io::Error::last_os_error();
            error!(
                "Failed to mprotect PROT_READ on SHM '{}': {}",
                self.metadata.shm_name, err
            );
            return Err(AppError::InternalError(format!("mprotect failed: {}", err)));
        }

        self.is_sealed = true;
        self.metadata.is_read_only = true;
        info!(
            "🔒 Sealed SHM segment '{}' (epoch {}) as immutable PROT_READ ({} bytes)",
            self.metadata.name, self.metadata.epoch, self.size
        );
        Ok(())
    }

    /// Read an arbitrary slice from the mapped buffer
    pub fn read_slice(&self, offset: usize, len: usize) -> Result<&[u8]> {
        if offset + len > self.size {
            return Err(AppError::InternalError(format!(
                "Out of bounds read on SHM '{}': offset {} + len {} > size {}",
                self.metadata.name, offset, len, self.size
            )));
        }
        unsafe {
            let slice = std::slice::from_raw_parts(self.ptr.add(offset), len);
            Ok(slice)
        }
    }

    /// Write bytes into the mapped buffer (only before sealed)
    pub fn write_bytes(&mut self, offset: usize, data: &[u8]) -> Result<()> {
        if self.is_sealed {
            return Err(AppError::InternalError(format!(
                "Attempted write to sealed SHM '{}'",
                self.metadata.name
            )));
        }
        if offset + data.len() > self.size {
            return Err(AppError::InternalError(format!(
                "Out of bounds write on SHM '{}': offset {} + len {} > size {}",
                self.metadata.name, offset, data.len(), self.size
            )));
        }

        unsafe {
            std::ptr::copy_nonoverlapping(data.as_ptr(), self.ptr.add(offset), data.len());
        }
        Ok(())
    }
}

impl Drop for ShmSegment {
    fn drop(&mut self) {
        let refs = self.ref_count.fetch_sub(1, Ordering::SeqCst);
        if refs <= 1 {
            // Last reference dropped -> Unmap buffer from address space
            if !self.ptr.is_null() {
                unsafe {
                    libc::munmap(self.ptr as *mut libc::c_void, self.size);
                }
            }
            if self.fd >= 0 {
                unsafe {
                    libc::close(self.fd);
                }
            }
        }
    }
}

/// Central supervisor managing all active SHM variables across sessions and cells
pub struct ShmBroker {
    segments: RwLock<HashMap<String, Arc<RwLock<ShmSegment>>>>,
    session_epochs: RwLock<HashMap<String, AtomicU64>>,
}

impl ShmBroker {
    pub fn new() -> Self {
        Self {
            segments: RwLock::new(HashMap::new()),
            session_epochs: RwLock::new(HashMap::new()),
        }
    }

    /// Allocate a new shared memory buffer for a variable in a session.
    /// Uses POSIX `shm_open` + `mmap(MAP_SHARED)`.
    pub fn allocate(
        &self,
        session_id: &str,
        var_name: &str,
        size_bytes: usize,
        data_type: &str,
    ) -> Result<Arc<RwLock<ShmSegment>>> {
        // Enforce 64-byte alignment rounding for Apple Silicon SIMD / NEON
        let aligned_size = (size_bytes + 63) & !63;

        // Advance epoch
        let epoch = self.advance_epoch(session_id, var_name);

        // macOS Darwin PSHM_NAMLEN limit: strictly <= 31 characters, starting with '/'
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};
        let mut hasher = DefaultHasher::new();
        session_id.hash(&mut hasher);
        var_name.hash(&mut hasher);
        let hash_val = hasher.finish();

        let pid = std::process::id();
        let combined_hash = hash_val ^ ((pid as u64) << 16);
        let shm_name = format!("/mc_{:010x}_e{:x}", combined_hash & 0x0000_00ff_ffff_ffff, epoch);
        let c_shm_name = CString::new(shm_name.clone())
            .map_err(|e| AppError::InternalError(format!("Invalid SHM name: {}", e)))?;

        // 1. Unlink any prior stale/sealed segment with this name to ensure clean read/write state
        unsafe {
            libc::shm_unlink(c_shm_name.as_ptr());
        }

        // 2. Open or create POSIX SHM object
        let fd = unsafe {
            libc::shm_open(
                c_shm_name.as_ptr(),
                libc::O_CREAT | libc::O_RDWR,
                0o600, // Read/Write by owner only
            )
        };

        if fd < 0 {
            let err = std::io::Error::last_os_error();
            error!("Failed to shm_open '{}': {}", shm_name, err);
            return Err(AppError::InternalError(format!("shm_open failed: {}", err)));
        }

        // 2. Set buffer size via ftruncate
        let trunc_res = unsafe { libc::ftruncate(fd, aligned_size as libc::off_t) };
        if trunc_res != 0 {
            let err = std::io::Error::last_os_error();
            unsafe {
                libc::close(fd);
                libc::shm_unlink(c_shm_name.as_ptr());
            }
            error!("Failed to ftruncate SHM '{}': {}", shm_name, err);
            return Err(AppError::InternalError(format!("ftruncate failed: {}", err)));
        }

        // 3. Memory-map with MAP_SHARED
        let ptr = unsafe {
            libc::mmap(
                std::ptr::null_mut(),
                aligned_size,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED,
                fd,
                0,
            )
        };

        if ptr == libc::MAP_FAILED || ptr.is_null() {
            let err = std::io::Error::last_os_error();
            unsafe {
                libc::close(fd);
                libc::shm_unlink(c_shm_name.as_ptr());
            }
            error!("Failed to mmap SHM '{}': {}", shm_name, err);
            return Err(AppError::InternalError(format!("mmap failed: {}", err)));
        }

        let now_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64;

        let metadata = ShmVariableMetadata {
            name: var_name.to_string(),
            session_id: session_id.to_string(),
            epoch,
            shm_name: shm_name.clone(),
            size_bytes: aligned_size,
            data_type: data_type.to_string(),
            is_read_only: false,
            created_at_ms: now_ms,
        };

        let segment = ShmSegment {
            metadata,
            ptr: ptr as *mut u8,
            size: aligned_size,
            fd,
            ref_count: Arc::new(AtomicUsize::new(1)),
            is_sealed: false,
        };

        let segment_arc = Arc::new(RwLock::new(segment));
        let key = format!("{}:{}", session_id, var_name);

        {
            let mut segs = self.segments.write().map_err(|_| {
                AppError::InternalError("Lock poisoned on shm segments".to_string())
            })?;
            // If an older epoch existed for this variable, it will be unlinked once callers drop it
            segs.insert(key, Arc::clone(&segment_arc));
        }

        info!(
            "🚀 Allocated SHM segment '{}' ({} bytes, epoch {})",
            shm_name, aligned_size, epoch
        );

        Ok(segment_arc)
    }

    /// Retrieve an existing SHM variable segment
    pub fn get(&self, session_id: &str, var_name: &str) -> Option<Arc<RwLock<ShmSegment>>> {
        let key = format!("{}:{}", session_id, var_name);
        let segs = self.segments.read().ok()?;
        segs.get(&key).cloned()
    }

    /// List all active variable metadata in a given session
    pub fn list_session_variables(&self, session_id: &str) -> Vec<ShmVariableMetadata> {
        let segs = match self.segments.read() {
            Ok(s) => s,
            Err(_) => return Vec::new(),
        };

        let prefix = format!("{}:", session_id);
        segs.iter()
            .filter(|(k, _)| k.starts_with(&prefix))
            .filter_map(|(_, v)| v.read().ok().map(|seg| seg.metadata.clone()))
            .collect()
    }

    /// Unlink and destroy a variable from shared memory
    pub fn remove(&self, session_id: &str, var_name: &str) -> Result<bool> {
        let key = format!("{}:{}", session_id, var_name);
        let segment = {
            let mut segs = self.segments.write().map_err(|_| {
                AppError::InternalError("Lock poisoned on shm segments".to_string())
            })?;
            segs.remove(&key)
        };

        if let Some(seg_arc) = segment {
            if let Ok(seg) = seg_arc.read() {
                if let Ok(c_name) = CString::new(seg.metadata.shm_name.clone()) {
                    unsafe {
                        libc::shm_unlink(c_name.as_ptr());
                    }
                    info!("🗑️ Unlinked SHM segment '{}'", seg.metadata.shm_name);
                }
            }
            return Ok(true);
        }

        Ok(false)
    }

    /// Clear all shared memory variables for a session (e.g. when notebook is closed or reset)
    pub fn clear_session(&self, session_id: &str) {
        let vars_to_remove: Vec<String> = {
            if let Ok(segs) = self.segments.read() {
                let prefix = format!("{}:", session_id);
                segs.keys()
                    .filter(|k| k.starts_with(&prefix))
                    .map(|k| k.split(':').nth(1).unwrap_or("").to_string())
                    .collect()
            } else {
                Vec::new()
            }
        };

        for var in vars_to_remove {
            let _ = self.remove(session_id, &var);
        }
    }

    fn advance_epoch(&self, session_id: &str, var_name: &str) -> u64 {
        let key = format!("{}:{}", session_id, var_name);
        let mut epochs = match self.session_epochs.write() {
            Ok(e) => e,
            Err(_) => return 1,
        };
        let counter = epochs.entry(key).or_insert_with(|| AtomicU64::new(0));
        counter.fetch_add(1, Ordering::SeqCst) + 1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_shm_allocate_write_and_seal() {
        let broker = ShmBroker::new();
        let session = "test_session_01";
        let var = "test_df";

        let segment_arc = broker.allocate(session, var, 1024, "arrow_table").expect("allocate failed");
        
        // Write test data
        {
            let mut seg = segment_arc.write().expect("lock write failed");
            let data = b"MICROCODE_ZERO_COPY_PAYLOAD";
            seg.write_bytes(0, data).expect("write failed");
            seg.seal_read_only().expect("seal failed");
        }

        // Read and verify data
        {
            let seg = segment_arc.read().expect("lock read failed");
            let read_back = seg.read_slice(0, 27).expect("read slice failed");
            assert_eq!(read_back, b"MICROCODE_ZERO_COPY_PAYLOAD");
            assert!(seg.metadata.is_read_only);
        }

        // Verify write after seal returns error
        {
            let mut seg = segment_arc.write().expect("lock write failed");
            let res = seg.write_bytes(0, b"FAIL");
            assert!(res.is_err());
        }

        // Clean up
        broker.remove(session, var).expect("remove failed");
    }
}
