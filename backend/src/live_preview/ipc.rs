//! IPC Protocol for Live Preview
//!
//! Communication between IDE and Preview process via Unix sockets.

use crate::error::{AppError, Result};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::mpsc;

/// Message types for IPC communication
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum PreviewMessage {
    /// Request to reload code
    Reload {
        source_code: String,
        language: String,
        file_path: Option<String>,
    },

    /// Render result from previewer
    RenderResult {
        success: bool,
        output: String,
        error: Option<String>,
        compile_time_ms: u64,
        render_time_ms: u64,
    },

    /// Source-to-UI mapping
    SourceMap {
        mappings: Vec<SourceMapping>,
    },

    /// Element selected in preview
    ElementSelected {
        element_id: String,
        line: u32,
        column: u32,
    },

    /// Ping/pong for health check
    Ping,
    Pong,

    /// Stop the preview server
    Shutdown,
}

/// Maps a source location to a UI element
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SourceMapping {
    pub element_id: String,
    pub line: u32,
    pub column: u32,
    pub end_line: u32,
    pub end_column: u32,
}

/// Socket path for IPC
pub fn get_socket_path() -> PathBuf {
    std::env::temp_dir().join("microcode_live_preview.sock")
}

/// Preview IPC Server
pub struct PreviewServer {
    socket_path: PathBuf,
    listener: Option<UnixListener>,
}

impl PreviewServer {
    /// Create a new preview server
    pub fn new() -> Self {
        Self {
            socket_path: get_socket_path(),
            listener: None,
        }
    }

    /// Start listening on the socket
    pub async fn start(&mut self) -> Result<()> {
        // Remove existing socket
        if self.socket_path.exists() {
            std::fs::remove_file(&self.socket_path)
                .map_err(|e| AppError::ExecutionError(e.to_string()))?;
        }

        let listener = UnixListener::bind(&self.socket_path)
            .map_err(|e| AppError::ExecutionError(format!("Failed to bind socket: {}", e)))?;

        self.listener = Some(listener);

        println!("🔌 Preview server listening on {:?}", self.socket_path);

        Ok(())
    }

    /// Accept a client connection and process messages
    pub async fn accept_and_handle<F>(&self, mut message_handler: F) -> Result<()>
    where
        F: FnMut(PreviewMessage) -> Option<PreviewMessage>,
    {
        let listener = self
            .listener
            .as_ref()
            .ok_or_else(|| AppError::ExecutionError("Server not started".into()))?;

        loop {
            match listener.accept().await {
                Ok((stream, _)) => {
                    println!("📥 Client connected");

                    if let Err(e) = self.handle_client(stream, &mut message_handler).await {
                        eprintln!("Client error: {}", e);
                    }
                }
                Err(e) => {
                    eprintln!("Accept error: {}", e);
                }
            }
        }
    }

    async fn handle_client<F>(&self, stream: UnixStream, handler: &mut F) -> Result<()>
    where
        F: FnMut(PreviewMessage) -> Option<PreviewMessage>,
    {
        let (read_half, mut write_half) = stream.into_split();
        let mut reader = BufReader::new(read_half);
        let mut line = String::new();

        loop {
            line.clear();

            let bytes_read = reader
                .read_line(&mut line)
                .await
                .map_err(|e| AppError::ExecutionError(e.to_string()))?;

            if bytes_read == 0 {
                // Connection closed
                break;
            }

            // Parse message
            match serde_json::from_str::<PreviewMessage>(&line) {
                Ok(msg) => {
                    // Handle shutdown
                    if matches!(msg, PreviewMessage::Shutdown) {
                        println!("🛑 Shutdown requested");
                        return Ok(());
                    }

                    // Process message and get response
                    if let Some(response) = handler(msg) {
                        let response_json = serde_json::to_string(&response)
                            .map_err(|e| AppError::ExecutionError(e.to_string()))?;

                        write_half
                            .write_all(response_json.as_bytes())
                            .await
                            .map_err(|e| AppError::ExecutionError(e.to_string()))?;
                        write_half
                            .write_all(b"\n")
                            .await
                            .map_err(|e| AppError::ExecutionError(e.to_string()))?;
                    }
                }
                Err(e) => {
                    eprintln!("Failed to parse message: {}", e);
                }
            }
        }

        Ok(())
    }

    /// Stop the server
    pub fn stop(&mut self) {
        self.listener = None;

        // Remove socket file
        if self.socket_path.exists() {
            std::fs::remove_file(&self.socket_path).ok();
        }
    }
}

impl Drop for PreviewServer {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Preview IPC Client (used by IDE)
pub struct PreviewClient {
    stream: Option<UnixStream>,
}

impl PreviewClient {
    pub fn new() -> Self {
        Self { stream: None }
    }

    /// Connect to the preview server
    pub async fn connect(&mut self) -> Result<()> {
        let socket_path = get_socket_path();

        let stream = UnixStream::connect(&socket_path).await.map_err(|e| {
            AppError::ExecutionError(format!("Failed to connect to preview server: {}", e))
        })?;

        self.stream = Some(stream);
        Ok(())
    }

    /// Send a message and receive response
    pub async fn send(&mut self, message: PreviewMessage) -> Result<PreviewMessage> {
        let stream = self
            .stream
            .as_mut()
            .ok_or_else(|| AppError::ExecutionError("Not connected".into()))?;

        // Send message
        let msg_json =
            serde_json::to_string(&message).map_err(|e| AppError::ExecutionError(e.to_string()))?;

        stream
            .write_all(msg_json.as_bytes())
            .await
            .map_err(|e| AppError::ExecutionError(e.to_string()))?;
        stream
            .write_all(b"\n")
            .await
            .map_err(|e| AppError::ExecutionError(e.to_string()))?;

        // Read response
        let (read_half, _) = stream.split();
        let mut reader = BufReader::new(read_half);
        let mut line = String::new();

        reader
            .read_line(&mut line)
            .await
            .map_err(|e| AppError::ExecutionError(e.to_string()))?;

        serde_json::from_str(&line).map_err(|e| AppError::ExecutionError(e.to_string()))
    }

    /// Close the connection
    pub fn disconnect(&mut self) {
        self.stream = None;
    }
}
