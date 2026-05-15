//! State Preservation - Maintain global state across hot reloads
//!
//! Captures and restores registered state variables so that
//! a counter doesn't reset to 0 when code is updated.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{LazyLock, RwLock};

/// Global state registry - variables register here to be preserved
pub static STATE_REGISTRY: LazyLock<RwLock<HashMap<String, StateEntry>>> =
    LazyLock::new(|| RwLock::new(HashMap::new()));

/// A registered state entry
#[derive(Clone)]
pub struct StateEntry {
    /// Serialized state data
    pub data: Vec<u8>,
    /// Type name for validation
    pub type_name: String,
    /// Last update timestamp
    pub updated_at: std::time::Instant,
}

/// State storage for capture/restore cycle
pub struct StateStorage {
    /// Captured state snapshot
    snapshot: HashMap<String, StateEntry>,
    /// Capture timestamp
    captured_at: Option<std::time::Instant>,
}

impl StateStorage {
    pub fn new() -> Self {
        Self {
            snapshot: HashMap::new(),
            captured_at: None,
        }
    }

    /// Capture all registered state
    pub fn capture(&mut self) {
        if let Ok(registry) = STATE_REGISTRY.read() {
            self.snapshot = (*registry).clone();
            self.captured_at = Some(std::time::Instant::now());
        }
    }

    /// Restore captured state
    pub fn restore(&self) {
        if let Ok(mut registry) = STATE_REGISTRY.write() {
            for (key, entry) in &self.snapshot {
                (*registry).insert(key.clone(), entry.clone());
            }
        }
    }

    /// Get snapshot as JSON
    pub fn to_json(&self) -> String {
        let map: HashMap<String, String> = self
            .snapshot
            .iter()
            .filter_map(|(k, v)| {
                // Try to decode as UTF-8 string for display
                String::from_utf8(v.data.clone())
                    .ok()
                    .map(|s| (k.clone(), s))
            })
            .collect();

        serde_json::to_string_pretty(&map).unwrap_or_default()
    }

    /// Check if state was captured
    pub fn has_snapshot(&self) -> bool {
        self.captured_at.is_some()
    }
}

/// Register a state value (call from FFI)
pub fn register_state(name: &str, data: Vec<u8>, type_name: &str) {
    if let Ok(mut registry) = STATE_REGISTRY.write() {
        (*registry).insert(
            name.to_string(),
            StateEntry {
                data,
                type_name: type_name.to_string(),
                updated_at: std::time::Instant::now(),
            },
        );
    }
}

/// Get a state value
pub fn get_state(name: &str) -> Option<Vec<u8>> {
    if let Ok(registry) = STATE_REGISTRY.read() {
        (*registry).get(name).map(|e| e.data.clone())
    } else {
        None
    }
}

/// FFI exports

/// Register state from C/Swift
#[no_mangle]
pub unsafe extern "C" fn state_register(
    name: *const std::os::raw::c_char,
    data: *const u8,
    data_len: usize,
    type_name: *const std::os::raw::c_char,
) {
    if name.is_null() || data.is_null() || type_name.is_null() {
        return;
    }

    let name = std::ffi::CStr::from_ptr(name).to_string_lossy().to_string();
    let type_name = std::ffi::CStr::from_ptr(type_name)
        .to_string_lossy()
        .to_string();
    let data = std::slice::from_raw_parts(data, data_len).to_vec();

    register_state(&name, data, &type_name);
}

/// Get state from C/Swift
/// Returns data length, copies to provided buffer
#[no_mangle]
pub unsafe extern "C" fn state_get(
    name: *const std::os::raw::c_char,
    buffer: *mut u8,
    buffer_len: usize,
) -> usize {
    if name.is_null() || buffer.is_null() {
        return 0;
    }

    let name = std::ffi::CStr::from_ptr(name).to_string_lossy().to_string();

    if let Some(data) = get_state(&name) {
        let copy_len = data.len().min(buffer_len);
        std::ptr::copy_nonoverlapping(data.as_ptr(), buffer, copy_len);
        copy_len
    } else {
        0
    }
}

/// Clear all state
#[no_mangle]
pub extern "C" fn state_clear() {
    if let Ok(mut registry) = STATE_REGISTRY.write() {
        (*registry).clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_state_roundtrip() {
        let name = "test_counter";
        let data = vec![42u8, 0, 0, 0]; // int32 = 42

        register_state(name, data.clone(), "i32");

        let retrieved = get_state(name).unwrap();
        assert_eq!(retrieved, data);
    }

    #[test]
    fn test_capture_restore() {
        register_state("var1", vec![1, 2, 3], "bytes");
        register_state("var2", vec![4, 5, 6], "bytes");

        let mut storage = StateStorage::new();
        storage.capture();

        // Modify state
        register_state("var1", vec![9, 9, 9], "bytes");

        // Restore
        storage.restore();

        let v1 = get_state("var1").unwrap();
        assert_eq!(v1, vec![1, 2, 3]);
    }
}
