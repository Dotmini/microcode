//! Runtime Swizzling - Low-level Memory Patching
//!
//! Provides unsafe memory operations for:
//! - Function pointer patching
//! - JMP trampoline installation
//! - Memory protection manipulation

use std::ffi::c_void;
use std::ptr;

#[cfg(target_os = "macos")]
extern "C" {
    fn mprotect(addr: *mut c_void, len: usize, prot: i32) -> i32;
}

#[cfg(target_os = "linux")]
extern "C" {
    fn mprotect(addr: *mut c_void, len: usize, prot: i32) -> i32;
}

const PROT_READ: i32 = 0x1;
const PROT_WRITE: i32 = 0x2;
const PROT_EXEC: i32 = 0x4;

/// Memory swizzler for runtime patching
pub struct Swizzler {
    /// Patched locations for cleanup
    patches: Vec<PatchRecord>,
    /// Page size for mprotect alignment
    page_size: usize,
}

/// Record of a memory patch (for restoration)
#[derive(Clone)]
struct PatchRecord {
    address: *mut u8,
    original_bytes: Vec<u8>,
    size: usize,
}

unsafe impl Send for PatchRecord {}
unsafe impl Sync for PatchRecord {}

impl Swizzler {
    pub fn new() -> Self {
        Self {
            patches: Vec::new(),
            page_size: 4096, // Standard page size
        }
    }

    /// Patch a function pointer in memory
    ///
    /// # Safety
    /// This directly modifies memory. Incorrect usage will crash.
    pub unsafe fn patch_pointer(
        &mut self,
        target: *mut *const c_void,
        new_fn: *const c_void,
    ) -> Result<*const c_void, SwizzleError> {
        // Calculate page-aligned address
        let target_addr = target as usize;
        let page_start = (target_addr & !(self.page_size - 1)) as *mut c_void;

        // Make memory writable
        if mprotect(
            page_start,
            self.page_size,
            PROT_READ | PROT_WRITE | PROT_EXEC,
        ) != 0
        {
            return Err(SwizzleError::MprotectFailed);
        }

        // Save old pointer
        let old_fn = ptr::read_volatile(target);

        // Record for restoration
        let mut old_bytes = vec![0u8; std::mem::size_of::<*const c_void>()];
        ptr::copy_nonoverlapping(target as *const u8, old_bytes.as_mut_ptr(), old_bytes.len());
        self.patches.push(PatchRecord {
            address: target as *mut u8,
            original_bytes: old_bytes,
            size: std::mem::size_of::<*const c_void>(),
        });

        // Write new pointer
        ptr::write_volatile(target, new_fn);

        // Restore memory protection
        mprotect(page_start, self.page_size, PROT_READ | PROT_EXEC);

        Ok(old_fn)
    }

    /// Install a JMP trampoline at function entry
    ///
    /// x86_64: 14 bytes - movabs rax, <addr>; jmp rax
    /// arm64:  16 bytes - ldr x16, #8; br x16; <addr>
    ///
    /// # Safety
    /// Overwrites function bytes. Function must be at least 14/16 bytes.
    #[cfg(target_arch = "x86_64")]
    pub unsafe fn install_trampoline(
        &mut self,
        target_fn: *mut u8,
        new_fn: *const c_void,
    ) -> Result<(), SwizzleError> {
        const TRAMPOLINE_SIZE: usize = 14;

        // Page alignment
        let page_start = ((target_fn as usize) & !(self.page_size - 1)) as *mut c_void;

        // Make writable (may span two pages)
        if mprotect(
            page_start,
            self.page_size * 2,
            PROT_READ | PROT_WRITE | PROT_EXEC,
        ) != 0
        {
            return Err(SwizzleError::MprotectFailed);
        }

        // Save original bytes
        let mut original = vec![0u8; TRAMPOLINE_SIZE];
        ptr::copy_nonoverlapping(target_fn, original.as_mut_ptr(), TRAMPOLINE_SIZE);
        self.patches.push(PatchRecord {
            address: target_fn,
            original_bytes: original,
            size: TRAMPOLINE_SIZE,
        });

        // Write trampoline: movabs rax, imm64; jmp rax
        let trampoline: [u8; 14] = [
            0x48, 0xB8, // movabs rax, imm64
            0, 0, 0, 0, 0, 0, 0, 0, // 8-byte address placeholder
            0xFF, 0xE0, // jmp rax
            0x90, 0x90, // nop padding
        ];

        ptr::copy_nonoverlapping(trampoline.as_ptr(), target_fn, 14);

        // Write the actual address
        let addr_ptr = target_fn.add(2) as *mut u64;
        *addr_ptr = new_fn as u64;

        // Restore protection
        mprotect(page_start, self.page_size * 2, PROT_READ | PROT_EXEC);

        Ok(())
    }

    /// Install a JMP trampoline for ARM64
    #[cfg(target_arch = "aarch64")]
    pub unsafe fn install_trampoline(
        &mut self,
        target_fn: *mut u8,
        new_fn: *const c_void,
    ) -> Result<(), SwizzleError> {
        const TRAMPOLINE_SIZE: usize = 16;

        let page_start = ((target_fn as usize) & !(self.page_size - 1)) as *mut c_void;

        if mprotect(
            page_start,
            self.page_size * 2,
            PROT_READ | PROT_WRITE | PROT_EXEC,
        ) != 0
        {
            return Err(SwizzleError::MprotectFailed);
        }

        // Save original bytes
        let mut original = vec![0u8; TRAMPOLINE_SIZE];
        ptr::copy_nonoverlapping(target_fn, original.as_mut_ptr(), TRAMPOLINE_SIZE);
        self.patches.push(PatchRecord {
            address: target_fn,
            original_bytes: original,
            size: TRAMPOLINE_SIZE,
        });

        // ARM64 trampoline:
        // LDR X16, #8     ; load address from PC+8
        // BR X16          ; branch to address
        // <8-byte address>
        let trampoline: [u8; 16] = [
            0x50, 0x00, 0x00, 0x58, // ldr x16, #8
            0x00, 0x02, 0x1F, 0xD6, // br x16
            0, 0, 0, 0, 0, 0, 0, 0, // 8-byte address placeholder
        ];

        ptr::copy_nonoverlapping(trampoline.as_ptr(), target_fn, 16);

        // Write the actual address
        let addr_ptr = target_fn.add(8) as *mut u64;
        *addr_ptr = new_fn as u64;

        mprotect(page_start, self.page_size * 2, PROT_READ | PROT_EXEC);

        Ok(())
    }

    /// Restore all patches to original state
    pub unsafe fn restore_all(&mut self) -> Result<(), SwizzleError> {
        for patch in self.patches.drain(..) {
            let page_start = ((patch.address as usize) & !(self.page_size - 1)) as *mut c_void;

            if mprotect(
                page_start,
                self.page_size * 2,
                PROT_READ | PROT_WRITE | PROT_EXEC,
            ) != 0
            {
                return Err(SwizzleError::MprotectFailed);
            }

            ptr::copy_nonoverlapping(patch.original_bytes.as_ptr(), patch.address, patch.size);

            mprotect(page_start, self.page_size * 2, PROT_READ | PROT_EXEC);
        }
        Ok(())
    }
}

/// Swizzle operation errors
#[derive(Debug, Clone)]
pub enum SwizzleError {
    MprotectFailed,
    InvalidAddress,
    PatchTooSmall,
}

impl std::fmt::Display for SwizzleError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SwizzleError::MprotectFailed => write!(f, "mprotect() failed - permission denied"),
            SwizzleError::InvalidAddress => write!(f, "Invalid memory address"),
            SwizzleError::PatchTooSmall => write!(f, "Target function too small for trampoline"),
        }
    }
}

impl std::error::Error for SwizzleError {}
