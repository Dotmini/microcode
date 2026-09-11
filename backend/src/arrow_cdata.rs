//! MicroCode Apache Arrow C Data Interface Engine
//!
//! Provides ABI-stable, zero-copy memory representation for polyglot cells
//! following the official Apache Arrow C Data Interface specification.
//!
//! Languages supported via this C ABI:
//! - Python (pyarrow / polars)
//! - Go (apache/arrow/go/cdata)
//! - Rust (arrow-rs / polars)
//! - C / C++ (arrow/c/abi.h)
//! - Ardium v2.3 (@extern "C" struct binding)
//! - Objective-C / Swift (C ABI Bridging)
//! - Julia (Arrow.jl)
//! - R (arrow package)
//! - SQL (DuckDB in-process Arrow registration)
//!
//! Copyright © 2026 Dotmini Software (Tirawat Nantamas). All rights reserved.

use crate::error::{AppError, Result};
use polars::prelude::*;
use serde::{Deserialize, Serialize};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::sync::Arc;
use tracing::{debug, error, info};

/// Magic bytes for MicroCode Arrow Shared Memory blocks
pub const MC_ARROW_MAGIC: &[u8; 4] = b"MCAR";
pub const MC_ARROW_VERSION: u32 = 1;

/// 64-byte alignment required for Apple Silicon ARM64 NEON vector instructions
pub const SIMD_ALIGNMENT_BYTES: usize = 64;

/// Standard Arrow C Data Interface Schema struct
/// Matching `struct ArrowSchema` from arrow/c/abi.h
#[repr(C)]
#[derive(Debug)]
pub struct FFI_ArrowSchema {
    pub format: *const c_char,
    pub name: *const c_char,
    pub metadata: *const c_char,
    pub flags: i64,
    pub n_children: i64,
    pub children: *mut *mut FFI_ArrowSchema,
    pub dictionary: *mut FFI_ArrowSchema,
    pub release: Option<unsafe extern "C" fn(*mut FFI_ArrowSchema)>,
    pub private_data: *mut c_void,
}

// Safety: Pointer lifecycle is supervised by Rust SHM Broker
unsafe impl Send for FFI_ArrowSchema {}
unsafe impl Sync for FFI_ArrowSchema {}

/// Standard Arrow C Data Interface Array struct
/// Matching `struct ArrowArray` from arrow/c/abi.h
#[repr(C)]
#[derive(Debug)]
pub struct FFI_ArrowArray {
    pub length: i64,
    pub null_count: i64,
    pub offset: i64,
    pub n_buffers: i64,
    pub n_children: i64,
    pub buffers: *mut *const c_void,
    pub children: *mut *mut FFI_ArrowArray,
    pub dictionary: *mut FFI_ArrowArray,
    pub release: Option<unsafe extern "C" fn(*mut FFI_ArrowArray)>,
    pub private_data: *mut c_void,
}

unsafe impl Send for FFI_ArrowArray {}
unsafe impl Sync for FFI_ArrowArray {}

/// Header written at the beginning of an Arrow SHM block
#[repr(C)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McArrowShmHeader {
    pub magic: [u8; 4],
    pub version: u32,
    pub num_rows: u64,
    pub num_cols: u64,
    pub ipc_buffer_offset: u64,
    pub ipc_buffer_length: u64,
    pub schema_summary: String,
    pub created_at_ms: u64,
}

impl McArrowShmHeader {
    pub fn new(num_rows: u64, num_cols: u64, offset: u64, length: u64, summary: &str) -> Self {
        let now_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64;

        Self {
            magic: *MC_ARROW_MAGIC,
            version: MC_ARROW_VERSION,
            num_rows,
            num_cols,
            ipc_buffer_offset: offset,
            ipc_buffer_length: length,
            schema_summary: summary.to_string(),
            created_at_ms: now_ms,
        }
    }

    pub fn validate(&self) -> Result<()> {
        if &self.magic != MC_ARROW_MAGIC {
            return Err(AppError::InternalError(
                "Invalid MicroCode Arrow SHM magic bytes".to_string(),
            ));
        }
        if self.version != MC_ARROW_VERSION {
            return Err(AppError::InternalError(format!(
                "Unsupported Arrow SHM version: {}",
                self.version
            )));
        }
        Ok(())
    }
}

/// Helper to serialize a Polars DataFrame directly into an Arrow IPC stream inside SHM
pub fn serialize_df_to_arrow_ipc(df: &mut DataFrame) -> Result<Vec<u8>> {
    let mut buffer = Vec::new();
    let mut cursor = std::io::Cursor::new(&mut buffer);

    IpcWriter::new(&mut cursor)
        .finish(df)
        .map_err(|e| AppError::InternalError(format!("Failed to serialize DataFrame to Arrow IPC: {}", e)))?;

    Ok(buffer)
}

/// Helper to deserialize a Polars DataFrame directly from an Arrow IPC buffer (Zero-copy where possible)
pub fn deserialize_df_from_arrow_ipc(slice: &[u8]) -> Result<DataFrame> {
    let cursor = std::io::Cursor::new(slice);
    let df = IpcReader::new(cursor)
        .finish()
        .map_err(|e| AppError::InternalError(format!("Failed to read Arrow IPC buffer: {}", e)))?;

    Ok(df)
}

/// Verifies whether an address satisfies Apple Silicon NEON 64-byte alignment
pub fn is_simd_aligned(ptr: *const u8) -> bool {
    (ptr as usize) % SIMD_ALIGNMENT_BYTES == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_df_to_arrow_ipc_roundtrip() {
        let s0 = Series::new("id", &[1i32, 2, 3, 4, 5]);
        let s1 = Series::new("score", &[98.5f64, 87.0, 92.3, 100.0, 76.5]);
        let s2 = Series::new("language", &["Python", "Go", "Rust", "Ardium", "SQL"]);
        let mut df = DataFrame::new(vec![s0, s1, s2]).unwrap();

        let ipc_bytes = serialize_df_to_arrow_ipc(&mut df).expect("serialize failed");
        assert!(!ipc_bytes.is_empty());

        let restored_df = deserialize_df_from_arrow_ipc(&ipc_bytes).expect("deserialize failed");
        assert_eq!(restored_df.shape(), (5, 3));
        assert_eq!(restored_df.get_column_names(), vec!["id", "score", "language"]);
    }

    #[test]
    fn test_header_validation() {
        let header = McArrowShmHeader::new(100, 4, 128, 4096, "id:int64,val:float64");
        assert!(header.validate().is_ok());

        let mut invalid = header.clone();
        invalid.magic = *b"XXXX";
        assert!(invalid.validate().is_err());
    }
}
