//! IPC Protocol - High-performance communication between IDE and Preview Agent
//!
//! Uses Unix Domain Sockets for control messages
//! and Shared Memory for large data (rendered images)

use serde::{Deserialize, Serialize};
use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::sync::Arc;
use tokio::sync::broadcast;

/// IPC Message types
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "data")]
pub enum IPCMessage {
    // IDE → Agent
    Reload {
        dylib_path: String,
        source_hash: u64,
    },
    Invalidate {
        file_path: String,
    },
    RequestState,
    RequestUITree,
    Ping,
    Shutdown,

    // Agent → IDE
    ReloadComplete {
        success: bool,
        version: u64,
        render_time_ms: u64,
        error: Option<String>,
    },
    StateSnapshot {
        json: String,
    },
    UITree {
        json: String,
    },
    ImageReady {
        shm_name: String,
        offset: usize,
        width: u32,
        height: u32,
        format: String,
    },
    CrashReport {
        error: String,
        backtrace: Vec<String>,
    },
    Pong,
}

/// IPC Server (runs in Preview Agent)
pub struct IPCServer {
    socket_path: String,
    listener: Option<UnixListener>,
    shutdown_tx: Option<broadcast::Sender<()>>,
}

impl IPCServer {
    pub fn new(socket_path: &str) -> std::io::Result<Self> {
        // Remove existing socket
        if Path::new(socket_path).exists() {
            std::fs::remove_file(socket_path)?;
        }

        let listener = UnixListener::bind(socket_path)?;

        let (shutdown_tx, _) = broadcast::channel(1);

        Ok(Self {
            socket_path: socket_path.to_string(),
            listener: Some(listener),
            shutdown_tx: Some(shutdown_tx),
        })
    }

    /// Accept a connection and handle messages
    pub fn accept(&self) -> std::io::Result<IPCConnection> {
        let listener = self.listener.as_ref().ok_or_else(|| {
            std::io::Error::new(std::io::ErrorKind::NotConnected, "Server not initialized")
        })?;

        let (stream, _addr) = listener.accept()?;
        Ok(IPCConnection::new(stream))
    }

    /// Get shutdown receiver for graceful termination
    pub fn subscribe_shutdown(&self) -> Option<broadcast::Receiver<()>> {
        self.shutdown_tx.as_ref().map(|tx| tx.subscribe())
    }

    /// Signal shutdown
    pub fn shutdown(&self) {
        if let Some(tx) = &self.shutdown_tx {
            let _ = tx.send(());
        }
    }
}

impl Drop for IPCServer {
    fn drop(&mut self) {
        // Clean up socket file
        let _ = std::fs::remove_file(&self.socket_path);
    }
}

/// IPC Client (runs in IDE)
pub struct IPCClient {
    stream: UnixStream,
}

impl IPCClient {
    pub fn connect(socket_path: &str) -> std::io::Result<Self> {
        let stream = UnixStream::connect(socket_path)?;
        Ok(Self { stream })
    }

    pub fn send(&mut self, msg: &IPCMessage) -> std::io::Result<()> {
        let json = serde_json::to_string(msg)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string()))?;

        let len = json.len() as u32;
        self.stream.write_all(&len.to_le_bytes())?;
        self.stream.write_all(json.as_bytes())?;
        self.stream.flush()?;

        Ok(())
    }

    pub fn receive(&mut self) -> std::io::Result<IPCMessage> {
        let mut len_buf = [0u8; 4];
        self.stream.read_exact(&mut len_buf)?;
        let len = u32::from_le_bytes(len_buf) as usize;

        let mut buf = vec![0u8; len];
        self.stream.read_exact(&mut buf)?;

        serde_json::from_slice(&buf)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string()))
    }
}

/// Bidirectional IPC connection
pub struct IPCConnection {
    stream: UnixStream,
}

impl IPCConnection {
    pub fn new(stream: UnixStream) -> Self {
        Self { stream }
    }

    pub fn send(&mut self, msg: &IPCMessage) -> std::io::Result<()> {
        let json = serde_json::to_string(msg)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string()))?;

        let len = json.len() as u32;
        self.stream.write_all(&len.to_le_bytes())?;
        self.stream.write_all(json.as_bytes())?;
        self.stream.flush()?;

        Ok(())
    }

    pub fn receive(&mut self) -> std::io::Result<IPCMessage> {
        let mut len_buf = [0u8; 4];
        self.stream.read_exact(&mut len_buf)?;
        let len = u32::from_le_bytes(len_buf) as usize;

        let mut buf = vec![0u8; len];
        self.stream.read_exact(&mut buf)?;

        serde_json::from_slice(&buf)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string()))
    }

    /// Set read timeout
    pub fn set_read_timeout(&self, duration: Option<std::time::Duration>) -> std::io::Result<()> {
        self.stream.set_read_timeout(duration)
    }
}

/// Shared Memory Buffer for large data transfer
#[cfg(feature = "shm")]
pub struct SharedMemoryBuffer {
    name: String,
    size: usize,
    ptr: *mut u8,
}

#[cfg(feature = "shm")]
impl SharedMemoryBuffer {
    pub fn create(name: &str, size: usize) -> std::io::Result<Self> {
        use std::fs::OpenOptions;

        let path = format!("/tmp/{}.shm", name);
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .open(&path)?;
        file.set_len(size as u64)?;

        // mmap the file
        let ptr = unsafe {
            libc::mmap(
                std::ptr::null_mut(),
                size,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED,
                std::os::unix::io::AsRawFd::as_raw_fd(&file),
                0,
            ) as *mut u8
        };

        if ptr.is_null() {
            return Err(std::io::Error::last_os_error());
        }

        Ok(Self {
            name: path,
            size,
            ptr,
        })
    }

    pub fn write(&mut self, offset: usize, data: &[u8]) {
        if offset + data.len() <= self.size {
            unsafe {
                std::ptr::copy_nonoverlapping(data.as_ptr(), self.ptr.add(offset), data.len());
            }
        }
    }

    pub fn read(&self, offset: usize, len: usize) -> Vec<u8> {
        let mut buf = vec![0u8; len];
        if offset + len <= self.size {
            unsafe {
                std::ptr::copy_nonoverlapping(self.ptr.add(offset), buf.as_mut_ptr(), len);
            }
        }
        buf
    }

    pub fn name(&self) -> &str {
        &self.name
    }
}

#[cfg(feature = "shm")]
impl Drop for SharedMemoryBuffer {
    fn drop(&mut self) {
        unsafe {
            libc::munmap(self.ptr as *mut libc::c_void, self.size);
        }
        let _ = std::fs::remove_file(&self.name);
    }
}
