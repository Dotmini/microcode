//! MCP Client — JSON-RPC 2.0 over stdio
//!
//! Spawns and communicates with local MCP servers
//! Implements: initialize, tools/list, tools/call, resources/list, resources/read
//!
//! Copyright © 2025 SPU AI CLUB — Dotmini Software

use super::*;
use crate::llm::McpContext;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::atomic::{AtomicU64, Ordering};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, Command};
use tokio::sync::Mutex;
use tracing::info;

// MARK: - MCP Client

pub struct McpClient {
    workspace: PathBuf,
    child: Option<Mutex<Child>>,
    stdin: Option<Mutex<tokio::process::ChildStdin>>,
    stdout_lines: Option<Mutex<tokio::io::Lines<BufReader<tokio::process::ChildStdout>>>>,
    request_id: AtomicU64,
    tools: Vec<McpTool>,
    resources: Vec<McpResourceInfo>,
    initialized: bool,
}

impl McpClient {
    pub fn new(workspace: &Path) -> Self {
        Self {
            workspace: workspace.to_path_buf(),
            child: None,
            stdin: None,
            stdout_lines: None,
            request_id: AtomicU64::new(1),
            tools: Vec::new(),
            resources: Vec::new(),
            initialized: false,
        }
    }

    /// Spawn an MCP server process and initialize the connection
    pub async fn connect(&mut self, command: &str, args: &[&str]) -> Result<(), String> {
        info!("MCP: Spawning server: {} {:?}", command, args);

        let mut child = Command::new(command)
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .current_dir(&self.workspace)
            .spawn()
            .map_err(|e| format!("Failed to spawn MCP server: {}", e))?;

        let stdin = child.stdin.take().ok_or("No stdin")?;
        let stdout = child.stdout.take().ok_or("No stdout")?;
        let reader = BufReader::new(stdout);

        self.stdin = Some(Mutex::new(stdin));
        self.stdout_lines = Some(Mutex::new(reader.lines()));
        self.child = Some(Mutex::new(child));

        // Initialize handshake
        self.initialize().await?;
        self.initialized = true;

        // Discover tools and resources
        self.discover().await?;

        info!(
            "MCP: Connected. Tools: {}, Resources: {}",
            self.tools.len(),
            self.resources.len()
        );
        Ok(())
    }

    /// Send JSON-RPC initialize request
    async fn initialize(&mut self) -> Result<(), String> {
        let params = serde_json::json!({
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "roots": { "listChanged": false }
            },
            "clientInfo": {
                "name": "MicroCode",
                "version": "2.0.0"
            }
        });

        let _response = self.send_request("initialize", Some(params)).await?;

        // Send initialized notification (no id, no response expected)
        self.send_notification("initialized", None).await?;

        Ok(())
    }

    /// Discover available tools and resources
    async fn discover(&mut self) -> Result<(), String> {
        // List tools
        if let Ok(response) = self.send_request("tools/list", None).await {
            if let Some(tools) = response["tools"].as_array() {
                self.tools = tools
                    .iter()
                    .filter_map(|t| serde_json::from_value::<McpTool>(t.clone()).ok())
                    .collect();
            }
        }

        // List resources
        if let Ok(response) = self.send_request("resources/list", None).await {
            if let Some(resources) = response["resources"].as_array() {
                self.resources = resources
                    .iter()
                    .filter_map(|r| serde_json::from_value::<McpResourceInfo>(r.clone()).ok())
                    .collect();
            }
        }

        Ok(())
    }

    // MARK: - Public API

    /// Read an MCP resource by URI
    pub async fn read_resource(&self, uri: &str) -> Result<String, String> {
        let params = serde_json::json!({ "uri": uri });
        let response = self.send_request("resources/read", Some(params)).await?;

        if let Some(contents) = response["contents"].as_array() {
            if let Some(first) = contents.first() {
                return Ok(first["text"].as_str().unwrap_or("").to_string());
            }
        }

        Err("No content returned".to_string())
    }

    /// Call an MCP tool
    pub async fn call_tool(
        &self,
        name: &str,
        arguments: serde_json::Value,
    ) -> Result<String, String> {
        let params = serde_json::json!({
            "name": name,
            "arguments": arguments
        });

        let response = self.send_request("tools/call", Some(params)).await?;

        if let Some(content) = response["content"].as_array() {
            let texts: Vec<&str> = content.iter().filter_map(|c| c["text"].as_str()).collect();
            return Ok(texts.join("\n"));
        }

        // Check for error
        if let Some(true) = response["isError"].as_bool() {
            return Err(format!("Tool error: {}", response));
        }

        Ok(response.to_string())
    }

    /// Get list of available tools
    pub fn available_tools(&self) -> &[McpTool] {
        &self.tools
    }

    /// Get list of available resources
    pub fn available_resources(&self) -> &[McpResourceInfo] {
        &self.resources
    }

    /// Build MCP context for LLM prompt injection
    pub async fn build_context(&self, active_file: Option<&str>) -> McpContext {
        let mut ctx = McpContext {
            workspace_root: Some(self.workspace.to_string_lossy().to_string()),
            active_file: active_file.map(|f| f.to_string()),
            ..Default::default()
        };

        // Read active file content
        if let Some(file) = active_file {
            let file_path = if Path::new(file).is_absolute() {
                file.to_string()
            } else {
                self.workspace.join(file).to_string_lossy().to_string()
            };

            if let Ok(content) = tokio::fs::read_to_string(&file_path).await {
                ctx.active_content = Some(content);
            }
        }

        // Read workspace project structure
        if let Ok(tree) = self
            .call_tool("list_files", serde_json::json!({"path": "."}))
            .await
        {
            ctx.resources.push(crate::llm::McpResource {
                uri: "workspace://project-tree".to_string(),
                content: tree,
                mime_type: "text/plain".to_string(),
            });
        }

        ctx
    }

    // MARK: - Transport Layer

    /// Send a JSON-RPC request and wait for response
    async fn send_request(
        &self,
        method: &str,
        params: Option<serde_json::Value>,
    ) -> Result<serde_json::Value, String> {
        let id = self.request_id.fetch_add(1, Ordering::SeqCst);

        let request = JsonRpcRequest {
            jsonrpc: "2.0".to_string(),
            id,
            method: method.to_string(),
            params,
        };

        let msg = serde_json::to_string(&request).map_err(|e| format!("Serialize error: {}", e))?;

        // Write to stdin
        if let Some(stdin_mutex) = &self.stdin {
            let mut stdin = stdin_mutex.lock().await;
            stdin
                .write_all(msg.as_bytes())
                .await
                .map_err(|e| format!("Write error: {}", e))?;
            stdin
                .write_all(b"\n")
                .await
                .map_err(|e| format!("Write newline error: {}", e))?;
            stdin
                .flush()
                .await
                .map_err(|e| format!("Flush error: {}", e))?;
        } else {
            return Err("No stdin connection".to_string());
        }

        // Read response from stdout
        if let Some(lines_mutex) = &self.stdout_lines {
            let mut lines = lines_mutex.lock().await;

            // Read lines until we get a response with matching id
            let timeout = tokio::time::Duration::from_secs(30);
            match tokio::time::timeout(timeout, lines.next_line()).await {
                Ok(Ok(Some(line))) => {
                    let response: JsonRpcResponse = serde_json::from_str(&line).map_err(|e| {
                        format!(
                            "Parse error: {} (line: {})",
                            e,
                            &line[..line.len().min(200)]
                        )
                    })?;

                    if let Some(error) = response.error {
                        return Err(format!("MCP error {}: {}", error.code, error.message));
                    }

                    Ok(response.result.unwrap_or(serde_json::Value::Null))
                }
                Ok(Ok(None)) => Err("MCP server closed connection".to_string()),
                Ok(Err(e)) => Err(format!("Read error: {}", e)),
                Err(_) => Err("MCP request timed out (30s)".to_string()),
            }
        } else {
            Err("No stdout connection".to_string())
        }
    }

    /// Send a JSON-RPC notification (no id, no response)
    async fn send_notification(
        &self,
        method: &str,
        params: Option<serde_json::Value>,
    ) -> Result<(), String> {
        let notif = serde_json::json!({
            "jsonrpc": "2.0",
            "method": method,
            "params": params.unwrap_or(serde_json::Value::Null)
        });

        let msg = serde_json::to_string(&notif).map_err(|e| format!("Serialize error: {}", e))?;

        if let Some(stdin_mutex) = &self.stdin {
            let mut stdin = stdin_mutex.lock().await;
            stdin
                .write_all(msg.as_bytes())
                .await
                .map_err(|e| format!("Write error: {}", e))?;
            stdin
                .write_all(b"\n")
                .await
                .map_err(|e| format!("Write newline error: {}", e))?;
            stdin
                .flush()
                .await
                .map_err(|e| format!("Flush error: {}", e))?;
        }

        Ok(())
    }

    /// Shutdown the MCP server gracefully
    pub async fn shutdown(&mut self) -> Result<(), String> {
        if self.initialized {
            let _ = self.send_notification("shutdown", None).await;
        }

        if let Some(child_mutex) = &self.child {
            let mut child = child_mutex.lock().await;
            let _ = child.kill().await;
        }

        self.initialized = false;
        info!("MCP: Server shut down");
        Ok(())
    }
}

impl Drop for McpClient {
    fn drop(&mut self) {
        // Note: async drop not possible, but child will be killed when stdin closes
    }
}

// MARK: - Context Injector

/// Automatically inject MCP context into LLM prompts
pub struct ContextInjector {
    mcp_client: Option<McpClient>,
}

impl ContextInjector {
    pub fn new() -> Self {
        Self { mcp_client: None }
    }

    pub fn with_client(client: McpClient) -> Self {
        Self {
            mcp_client: Some(client),
        }
    }

    /// Build enriched context for LLM prompt
    pub async fn inject(&self, active_file: Option<&str>) -> McpContext {
        if let Some(client) = &self.mcp_client {
            client.build_context(active_file).await
        } else {
            // Fallback: read file directly without MCP
            let mut ctx = McpContext::default();
            if let Some(file) = active_file {
                ctx.active_file = Some(file.to_string());
                if let Ok(content) = tokio::fs::read_to_string(file).await {
                    ctx.active_content = Some(content);
                }
            }
            ctx
        }
    }
}
