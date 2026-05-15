//! Thunk Table - Function Pointer Indirection for Hot Swapping
//!
//! Every hot-swappable function call goes through this table.
//! When a new version is loaded, we simply update the pointer.

use std::collections::HashMap;
use std::ffi::{c_void, CStr};
use std::os::raw::c_char;
use std::sync::{LazyLock, RwLock};

/// Global thunk table - maps function names to current implementation addresses
pub static THUNK_TABLE: LazyLock<RwLock<ThunkTable>> =
    LazyLock::new(|| RwLock::new(ThunkTable::new()));

/// Thread-safe function pointer table
pub struct ThunkTable {
    entries: HashMap<String, ThunkEntry>,
}

/// A single thunk entry with metadata
#[derive(Clone)]
pub struct ThunkEntry {
    /// Current function address
    pub address: *const c_void,
    /// Original function address (for rollback)
    pub original: *const c_void,
    /// Version number (incremented on each swap)
    pub version: u64,
    /// Symbol name in dynamic library
    pub symbol: String,
}

unsafe impl Send for ThunkEntry {}
unsafe impl Sync for ThunkEntry {}

impl ThunkTable {
    pub fn new() -> Self {
        Self {
            entries: HashMap::new(),
        }
    }

    /// Register a new function in the thunk table
    pub fn register(&mut self, name: &str, address: *const c_void) {
        let entry = ThunkEntry {
            address,
            original: address,
            version: 0,
            symbol: name.to_string(),
        };
        self.entries.insert(name.to_string(), entry);
    }

    /// Lookup current function address
    pub fn lookup(&self, name: &str) -> Option<*const c_void> {
        self.entries.get(name).map(|e| e.address)
    }

    /// Swap function to new implementation
    pub fn swap(&mut self, name: &str, new_address: *const c_void) -> Option<*const c_void> {
        if let Some(entry) = self.entries.get_mut(name) {
            let old = entry.address;
            entry.address = new_address;
            entry.version += 1;
            Some(old)
        } else {
            None
        }
    }

    /// Rollback to original implementation
    pub fn rollback(&mut self, name: &str) -> bool {
        if let Some(entry) = self.entries.get_mut(name) {
            entry.address = entry.original;
            entry.version += 1;
            true
        } else {
            false
        }
    }

    /// Get all registered function names
    pub fn list_functions(&self) -> Vec<String> {
        self.entries.keys().cloned().collect()
    }

    /// Get entry metadata
    pub fn get_entry(&self, name: &str) -> Option<ThunkEntry> {
        self.entries.get(name).cloned()
    }
}

// FFI exports for use from C/Swift code

/// Register a function in the thunk table (C ABI)
#[no_mangle]
pub unsafe extern "C" fn thunk_register(name: *const c_char, addr: *const c_void) {
    if name.is_null() {
        return;
    }
    let name = CStr::from_ptr(name).to_string_lossy().to_string();
    if let Ok(mut table) = THUNK_TABLE.write() {
        (*table).register(&name, addr);
    }
}

/// Lookup function address (C ABI)
#[no_mangle]
pub unsafe extern "C" fn thunk_lookup(name: *const c_char) -> *const c_void {
    if name.is_null() {
        return std::ptr::null();
    }
    let name = CStr::from_ptr(name).to_string_lossy().to_string();
    if let Ok(table) = THUNK_TABLE.read() {
        (*table).lookup(&name).unwrap_or(std::ptr::null())
    } else {
        std::ptr::null()
    }
}

/// Swap function to new address (C ABI)
#[no_mangle]
pub unsafe extern "C" fn thunk_swap(name: *const c_char, new_addr: *const c_void) -> bool {
    if name.is_null() {
        return false;
    }
    let name = CStr::from_ptr(name).to_string_lossy().to_string();
    if let Ok(mut table) = THUNK_TABLE.write() {
        (*table).swap(&name, new_addr).is_some()
    } else {
        false
    }
}

/// Rollback to original function (C ABI)
#[no_mangle]
pub unsafe extern "C" fn thunk_rollback(name: *const c_char) -> bool {
    if name.is_null() {
        return false;
    }
    let name = CStr::from_ptr(name).to_string_lossy().to_string();
    if let Ok(mut table) = THUNK_TABLE.write() {
        (*table).rollback(&name)
    } else {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_thunk_table() {
        let mut table = ThunkTable::new();

        // Register
        let addr1 = 0x1000 as *const c_void;
        table.register("my_func", addr1);

        // Lookup
        assert_eq!(table.lookup("my_func"), Some(addr1));

        // Swap
        let addr2 = 0x2000 as *const c_void;
        let old = table.swap("my_func", addr2);
        assert_eq!(old, Some(addr1));
        assert_eq!(table.lookup("my_func"), Some(addr2));

        // Rollback
        assert!(table.rollback("my_func"));
        assert_eq!(table.lookup("my_func"), Some(addr1));
    }
}
