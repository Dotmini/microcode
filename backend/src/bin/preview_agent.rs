//! Preview Agent - Standalone hot reload process
//!
//! This is a separate executable that:
//! 1. Listens for IPC messages from the IDE
//! 2. Loads dynamic libraries with dlopen
//! 3. Renders SwiftUI views via ImageRenderer
//! 4. Sends results back via shared memory

use std::io::{Read, Write};
use std::os::unix::net::UnixListener;
use std::path::Path;
use std::ffi::{c_void, CStr, CString};
use std::os::raw::c_char;

mod hot_reload_common {
    //! Shared types between main backend and preview agent
    
    use serde::{Deserialize, Serialize};
    
    #[derive(Debug, Clone, Serialize, Deserialize)]
    #[serde(tag = "type", content = "data")]
    pub enum IPCMessage {
        // IDE → Agent
        Reload { dylib_path: String, source_hash: u64 },
        Ping,
        Shutdown,
        
        // Agent → IDE
        ReloadComplete { success: bool, version: u64, render_time_ms: u64, error: Option<String> },
        ImageReady { shm_name: String, offset: usize, width: u32, height: u32 },
        Pong,
    }
}

use hot_reload_common::IPCMessage;

// FFI for dynamic loading
extern "C" {
    fn dlopen(filename: *const c_char, flags: i32) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn dlclose(handle: *mut c_void) -> i32;
    fn dlerror() -> *const c_char;
}

const RTLD_NOW: i32 = 0x2;
const RTLD_LOCAL: i32 = 0x4;

/// Loaded module handle
struct LoadedModule {
    handle: *mut c_void,
    version: u64,
}

impl Drop for LoadedModule {
    fn drop(&mut self) {
        if !self.handle.is_null() {
            unsafe { dlclose(self.handle); }
        }
    }
}

/// Preview Agent state
struct PreviewAgent {
    socket_path: String,
    modules: Vec<LoadedModule>,
    current_version: u64,
    render_output_path: String,
}

impl PreviewAgent {
    fn new(socket_path: &str) -> Self {
        Self {
            socket_path: socket_path.to_string(),
            modules: Vec::new(),
            current_version: 0,
            render_output_path: "/tmp/preview_render.png".to_string(),
        }
    }
    
    /// Hot reload a dylib
    unsafe fn reload(&mut self, dylib_path: &str) -> Result<(u64, u64), String> {
        let start = std::time::Instant::now();
        
        // Load the library
        let path_cstr = CString::new(dylib_path).map_err(|e| e.to_string())?;
        let handle = dlopen(path_cstr.as_ptr(), RTLD_NOW | RTLD_LOCAL);
        
        if handle.is_null() {
            let err = CStr::from_ptr(dlerror()).to_string_lossy().to_string();
            return Err(format!("dlopen failed: {}", err));
        }
        
        // Look for preview_render function
        let render_sym = CString::new("preview_render").unwrap();
        let render_fn = dlsym(handle, render_sym.as_ptr());
        
        if render_fn.is_null() {
            dlclose(handle);
            return Err("preview_render symbol not found".to_string());
        }
        
        // Call the render function
        // Expected signature: fn(output_path: *const c_char) -> i32
        let render: extern "C" fn(*const c_char) -> i32 = std::mem::transmute(render_fn);
        let output_path = CString::new(self.render_output_path.as_str()).unwrap();
        let result = render(output_path.as_ptr());
        
        if result != 0 {
            dlclose(handle);
            return Err(format!("preview_render returned error code: {}", result));
        }
        
        // Track module
        self.current_version += 1;
        self.modules.push(LoadedModule {
            handle,
            version: self.current_version,
        });
        
        // Cleanup old modules (keep last 3)
        while self.modules.len() > 3 {
            self.modules.remove(0);
        }
        
        let elapsed = start.elapsed().as_millis() as u64;
        Ok((self.current_version, elapsed))
    }
    
    /// Run the agent loop
    fn run(&mut self) -> std::io::Result<()> {
        // Remove existing socket
        if Path::new(&self.socket_path).exists() {
            std::fs::remove_file(&self.socket_path)?;
        }
        
        let listener = UnixListener::bind(&self.socket_path)?;
        println!("🚀 Preview Agent listening on {}", self.socket_path);
        
        for stream in listener.incoming() {
            match stream {
                Ok(mut stream) => {
                    println!("📱 Client connected");
                    
                    loop {
                        // Read message length
                        let mut len_buf = [0u8; 4];
                        if stream.read_exact(&mut len_buf).is_err() {
                            break;
                        }
                        let len = u32::from_le_bytes(len_buf) as usize;
                        
                        // Read message body
                        let mut buf = vec![0u8; len];
                        if stream.read_exact(&mut buf).is_err() {
                            break;
                        }
                        
                        // Parse message
                        let msg: IPCMessage = match serde_json::from_slice(&buf) {
                            Ok(m) => m,
                            Err(e) => {
                                eprintln!("Parse error: {}", e);
                                continue;
                            }
                        };
                        
                        // Handle message
                        let response = self.handle_message(msg);
                        
                        // Send response
                        let response_json = serde_json::to_string(&response).unwrap();
                        let response_len = response_json.len() as u32;
                        let _ = stream.write_all(&response_len.to_le_bytes());
                        let _ = stream.write_all(response_json.as_bytes());
                        let _ = stream.flush();
                        
                        // Check for shutdown
                        if matches!(response, IPCMessage::Shutdown) {
                            println!("👋 Shutting down");
                            return Ok(());
                        }
                    }
                    
                    println!("📴 Client disconnected");
                }
                Err(e) => {
                    eprintln!("Accept error: {}", e);
                }
            }
        }
        
        Ok(())
    }
    
    fn handle_message(&mut self, msg: IPCMessage) -> IPCMessage {
        match msg {
            IPCMessage::Ping => IPCMessage::Pong,
            
            IPCMessage::Shutdown => IPCMessage::Shutdown,
            
            IPCMessage::Reload { dylib_path, source_hash: _ } => {
                match unsafe { self.reload(&dylib_path) } {
                    Ok((version, render_time_ms)) => {
                        // Check if render output exists
                        if Path::new(&self.render_output_path).exists() {
                            IPCMessage::ImageReady {
                                shm_name: self.render_output_path.clone(),
                                offset: 0,
                                width: 375,
                                height: 812,
                            }
                        } else {
                            IPCMessage::ReloadComplete {
                                success: true,
                                version,
                                render_time_ms,
                                error: None,
                            }
                        }
                    }
                    Err(e) => IPCMessage::ReloadComplete {
                        success: false,
                        version: self.current_version,
                        render_time_ms: 0,
                        error: Some(e),
                    },
                }
            }
            
            // Ignore agent responses (shouldn't receive these)
            _ => IPCMessage::Pong,
        }
    }
}

fn main() {
    println!("🔥 MicroCode Preview Agent v1.0");
    println!("   Hot Reload Engine for SwiftUI Preview");
    println!();
    
    let socket_path = std::env::var("PREVIEW_SOCKET")
        .unwrap_or_else(|_| "/tmp/microcode_preview.sock".to_string());
    
    let mut agent = PreviewAgent::new(&socket_path);
    
    if let Err(e) = agent.run() {
        eprintln!("❌ Agent error: {}", e);
        std::process::exit(1);
    }
}
