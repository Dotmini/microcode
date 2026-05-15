//! Preview Host - Dynamic Library Hot Reload
//!
//! Watches source files, compiles to .dylib, and hot-swaps at runtime.
//! Uses dlopen/dlsym for dynamic loading on macOS/Linux.

use crate::error::{AppError, Result};
use std::ffi::{CStr, CString};
use std::os::raw::c_void;
use std::path::Path;
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tokio::sync::broadcast;

// Dynamic library handle type
type DylibHandle = *mut c_void;

// Render function signature - returns JSON string pointer
type RenderFn = extern "C" fn() -> *const i8;

// FFI declarations for dynamic loading
#[cfg(target_os = "macos")]
extern "C" {
    fn dlopen(filename: *const i8, flags: i32) -> DylibHandle;
    fn dlclose(handle: DylibHandle) -> i32;
    fn dlsym(handle: DylibHandle, symbol: *const i8) -> *mut c_void;
    fn dlerror() -> *const i8;
}

// RTLD flags
const RTLD_NOW: i32 = 0x2;
const RTLD_LOCAL: i32 = 0x4;

/// Global version counter for unique dylib names
static VERSION_COUNTER: AtomicU64 = AtomicU64::new(0);

/// Result of a preview render
#[derive(Debug, Clone, serde::Serialize)]
pub struct RenderResult {
    pub success: bool,
    pub output: String,
    pub error: Option<String>,
    pub compile_time_ms: u64,
    pub render_time_ms: u64,
}

/// Preview Host manages hot-reloading of user code
pub struct PreviewHost {
    /// Currently loaded library handle
    current_handle: Option<DylibHandle>,
    /// Currently loaded library path (for cleanup)
    current_dylib_path: Option<String>,
    /// Output directory for compiled dylibs
    output_dir: String,
    /// Broadcast channel for reload events
    reload_tx: broadcast::Sender<RenderResult>,
}

// NOTE: DylibHandle is a raw pointer, but we manage it carefully
// and ensure it's only accessed from one thread
unsafe impl Send for PreviewHost {}
unsafe impl Sync for PreviewHost {}

impl PreviewHost {
    /// Create a new PreviewHost
    pub fn new() -> Self {
        let output_dir = std::env::temp_dir()
            .join("microcode_live_preview")
            .to_string_lossy()
            .to_string();

        // Create output directory
        std::fs::create_dir_all(&output_dir).ok();

        let (reload_tx, _) = broadcast::channel(16);

        Self {
            current_handle: None,
            current_dylib_path: None,
            output_dir,
            reload_tx,
        }
    }

    /// Get a receiver for reload events
    pub fn subscribe(&self) -> broadcast::Receiver<RenderResult> {
        self.reload_tx.subscribe()
    }

    /// Compile source code to a dynamic library
    pub fn compile(&self, source_code: &str, language: &str) -> Result<String> {
        let version = VERSION_COUNTER.fetch_add(1, Ordering::SeqCst);
        
        let output_path = Path::new(&self.output_dir);
        if !output_path.exists() {
            std::fs::create_dir_all(output_path).ok();
        }

        match language {
            "swift" => {
                // Write source to file
                let source_path = output_path.join(format!("preview_v{}.swift", version));
                std::fs::write(&source_path, source_code)
                    .map_err(|e| AppError::ExecutionError(format!("Failed to write source: {}", e)))?;
                
                // Use v2 builder
                use crate::preview_v2::builder::{compile_swift_to_dylib, BuildResult};
                
                match compile_swift_to_dylib(&source_path, output_path) {
                    BuildResult::Success(dylib_path) => {
                        Ok(dylib_path.to_string_lossy().to_string())
                    },
                    BuildResult::Failure(errors) => {
                        // Format errors into string
                        let error_msg = errors.iter()
                            .map(|e| format!("{}:{}:{}: {} - {}", e.file, e.line, e.column, e.severity, e.message))
                            .collect::<Vec<_>>()
                            .join("\n");
                        Err(AppError::CompilationError(error_msg))
                    }
                }
            }
            "rust" => {
                // Keep legacy rust support for now
                let source_path = output_path.join(format!("preview_v{}.rs", version));
                let dylib_path = output_path.join(format!("preview_v{}.dylib", version)); // macOS assumption
                
                std::fs::write(&source_path, source_code)
                    .map_err(|e| AppError::ExecutionError(format!("Failed to write source: {}", e)))?;
                    
                let output = Command::new("rustc")
                    .args([
                        "--crate-type=cdylib",
                        "-O",
                        &source_path.to_string_lossy(),
                        "-o", &dylib_path.to_string_lossy()
                    ])
                    .output()
                    .map_err(|e| AppError::ExecutionError(format!("Failed to run rustc: {}", e)))?;
                    
                if output.status.success() {
                    Ok(dylib_path.to_string_lossy().to_string())
                } else {
                    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
                    Err(AppError::CompilationError(stderr))
                }
            }
            _ => Err(AppError::ExecutionError(format!("Unsupported language: {}", language)))
        }
    }

    /// Load a dynamic library and get the render function
    #[cfg(target_os = "macos")]
    pub unsafe fn load(&mut self, dylib_path: &str) -> Result<RenderFn> {
        // Unload previous library
        self.unload();

        // Load new library
        let path_cstr = CString::new(dylib_path)
            .map_err(|_| AppError::ExecutionError("Invalid path".into()))?;

        let handle = dlopen(path_cstr.as_ptr(), RTLD_NOW | RTLD_LOCAL);

        if handle.is_null() {
            let err_ptr = dlerror();
            let err_msg = if err_ptr.is_null() {
                "Unknown dlopen error".to_string()
            } else {
                CStr::from_ptr(err_ptr).to_string_lossy().to_string()
            };
            return Err(AppError::ExecutionError(format!(
                "Failed to load library: {}", err_msg
            )));
        }

        // Get render symbol
        let symbol = CString::new("preview_render").unwrap();
        let func_ptr = dlsym(handle, symbol.as_ptr());

        if func_ptr.is_null() {
            dlclose(handle);
            return Err(AppError::ExecutionError(
                "Symbol 'preview_render' not found. Export with @_cdecl(\"preview_render\")".into()
            ));
        }

        self.current_handle = Some(handle);
        self.current_dylib_path = Some(dylib_path.to_string());

        // Transmute to function pointer
        Ok(std::mem::transmute(func_ptr))
    }

    /// Unload the current library
    #[cfg(target_os = "macos")]
    pub fn unload(&mut self) {
        if let Some(handle) = self.current_handle.take() {
            unsafe {
                dlclose(handle);
            }
        }

        // Clean up old dylib file
        if let Some(path) = self.current_dylib_path.take() {
            std::fs::remove_file(&path).ok();
        }
    }

    /// Compile and reload code, returning render result
    pub fn hot_reload(&mut self, source_code: &str, language: &str) -> RenderResult {
        let compile_start = std::time::Instant::now();

        // Compile
        let dylib_path = match self.compile(source_code, language) {
            Ok(path) => path,
            Err(e) => {
                let result = RenderResult {
                    success: false,
                    output: String::new(),
                    error: Some(e.to_string()),
                    compile_time_ms: compile_start.elapsed().as_millis() as u64,
                    render_time_ms: 0,
                };
                self.reload_tx.send(result.clone()).ok();
                return result;
            }
        };

        let compile_time = compile_start.elapsed().as_millis() as u64;
        let render_start = std::time::Instant::now();

        // Load and render
        let result = unsafe {
            match self.load(&dylib_path) {
                Ok(render_fn) => {
                    // Call render function
                    let output_ptr = render_fn();
                    let output = if output_ptr.is_null() {
                        String::new()
                    } else {
                        CStr::from_ptr(output_ptr).to_string_lossy().to_string()
                    };

                    RenderResult {
                        success: true,
                        output,
                        error: None,
                        compile_time_ms: compile_time,
                        render_time_ms: render_start.elapsed().as_millis() as u64,
                    }
                }
                Err(e) => RenderResult {
                    success: false,
                    output: String::new(),
                    error: Some(e.to_string()),
                    compile_time_ms: compile_time,
                    render_time_ms: 0,
                },
            }
        };

        // Broadcast result
        self.reload_tx.send(result.clone()).ok();

        result
    }

    /// Clean up all temporary files
    pub fn cleanup(&mut self) {
        self.unload();
        
        // Remove entire output directory
        std::fs::remove_dir_all(&self.output_dir).ok();
    }
}

impl Drop for PreviewHost {
    fn drop(&mut self) {
        self.cleanup();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version_counter() {
        let v1 = VERSION_COUNTER.fetch_add(1, Ordering::SeqCst);
        let v2 = VERSION_COUNTER.fetch_add(1, Ordering::SeqCst);
        assert!(v2 > v1);
    }
}
