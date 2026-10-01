//! Dotmini Cloud MCP Gateway & Gemini Spark Relay
//!
//! Exposes Model Context Protocol (MCP 2024-11-05) over HTTP & SSE
//! Compatible with Google Gemini Spark, Claude Desktop/Web, and Remote AI Agents.
//! Supports live tunneling to local MicroCode desktop IDE via WebSocket.
//!
//! Copyright © 2025-2026 Dotmini Software — Tirawat Nantamas

use axum::{
    extract::{
        ws::{Message, WebSocket},
        Query, State, WebSocketUpgrade,
    },
    response::{
        sse::{Event, KeepAlive, Sse},
        IntoResponse, Response,
    },
    Json,
};
use futures::{SinkExt, StreamExt};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::convert::Infallible;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{mpsc, oneshot, RwLock};
use tokio_stream::wrappers::ReceiverStream;
use tracing::{error, info, warn};
use uuid::Uuid;

pub struct McpGatewayState {
    /// Active SSE client sessions: sessionId -> sender
    pub sse_sessions: Arc<RwLock<HashMap<String, mpsc::Sender<Event>>>>,
    /// Connected MicroCode desktop IDE tunnels: token -> sender
    pub desktop_tunnels: Arc<RwLock<HashMap<String, mpsc::Sender<Value>>>>,
    /// Pending response waiting for desktop reply: call_id -> sender
    pub pending_calls: Arc<RwLock<HashMap<u64, (String, oneshot::Sender<Value>)>>>,
    /// Monotonic call ID generator
    pub next_call_id: AtomicU64,
}

impl McpGatewayState {
    pub fn new() -> Self {
        Self {
            sse_sessions: Arc::new(RwLock::new(HashMap::new())),
            desktop_tunnels: Arc::new(RwLock::new(HashMap::new())),
            pending_calls: Arc::new(RwLock::new(HashMap::new())),
            next_call_id: AtomicU64::new(1),
        }
    }

    pub fn get_tools_manifest() -> Value {
        json!({
            "tools": [
                {
                    "name": "run_cell",
                    "description": "Execute code (Python, R, Ardium, Bash, Rust, C++) inside MicroCode runner and return pure stdout/stderr output.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "code": { "type": "string", "description": "The source code to execute" },
                            "language": { "type": "string", "description": "Language: python, r, ardium, bash, rust, cpp", "default": "python" }
                        },
                        "required": ["code"]
                    }
                },
                {
                    "name": "ardium_run",
                    "description": "Run Ardium (v2.3) programming language source code natively via Dotmini Ardium toolchain.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "code": { "type": "string", "description": "Ardium source code (.ar)" }
                        },
                        "required": ["code"]
                    }
                },
                {
                    "name": "ardium_compile",
                    "description": "Compile Ardium source code and return syntax diagnostics or AST.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "code": { "type": "string", "description": "Ardium source code (.ar)" }
                        },
                        "required": ["code"]
                    }
                },
                {
                    "name": "file_read",
                    "description": "Read file content from the active MicroCode project workspace.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "path": { "type": "string", "description": "Relative file path within workspace" }
                        },
                        "required": ["path"]
                    }
                },
                {
                    "name": "file_write",
                    "description": "Write or modify a file inside the MicroCode workspace.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "path": { "type": "string", "description": "Relative file path within workspace" },
                            "content": { "type": "string", "description": "Full file content to write" }
                        },
                        "required": ["path", "content"]
                    }
                },
                {
                    "name": "list_directory",
                    "description": "List files and directories in the workspace.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "path": { "type": "string", "description": "Subdirectory path, or '.' for root", "default": "." }
                        }
                    }
                },
                {
                    "name": "git_status",
                    "description": "Get git working tree status for the current workspace.",
                    "inputSchema": { "type": "object", "properties": {} }
                },
                {
                    "name": "cloud_gpu_status",
                    "description": "Inspect active Dotmini Cloud GPU cluster and RunPod instances.",
                    "inputSchema": { "type": "object", "properties": {} }
                }
            ]
        })
    }
}

// MARK: - Handlers

/// GET /v1/mcp/sse or GET /v1/mcp
/// Establishes Server-Sent Events stream for Gemini Spark / Claude
pub async fn mcp_sse_handler(
    State(gateway): State<Arc<McpGatewayState>>,
    Query(params): Query<HashMap<String, String>>,
) -> Sse<impl futures::Stream<Item = Result<Event, Infallible>>> {
    let session_id = Uuid::new_v4().to_string();
    let token = params.get("token").cloned().unwrap_or_else(|| "default".to_string());
    let (tx, rx) = mpsc::channel(32);

    gateway.sse_sessions.write().await.insert(session_id.clone(), tx.clone());

    // 1. Send endpoint event required by MCP SSE specification
    let endpoint_url = format!("/v1/mcp/message?sessionId={}&token={}", session_id, token);
    let init_event = Event::default().event("endpoint").data(endpoint_url);
    let _ = tx.send(init_event).await;

    info!("[MCP Gateway] SSE connection established");

    let stream = ReceiverStream::new(rx).map(Ok);
    Sse::new(stream).keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("ping"))
}

/// POST /v1/mcp/message?sessionId=...
/// Handles incoming JSON-RPC 2.0 messages from Gemini Spark during an SSE session
pub async fn mcp_message_handler(
    State(gateway): State<Arc<McpGatewayState>>,
    Query(params): Query<HashMap<String, String>>,
    Json(payload): Json<Value>,
) -> impl IntoResponse {
    let session_id = params.get("sessionId").cloned().unwrap_or_default();
    let token = params.get("token").cloned().unwrap_or_else(|| "default".to_string());

    let response = process_jsonrpc_request(&gateway, &token, payload).await;

    // Send JSON-RPC response through SSE stream
    if let Some(tx) = gateway.sse_sessions.read().await.get(&session_id) {
        let resp_str = serde_json::to_string(&response).unwrap_or_default();
        let event = Event::default().event("message").data(resp_str);
        let _ = tx.send(event).await;
    }

    Json(json!({ "status": "accepted" }))
}

/// POST /v1/mcp
/// Stateless direct HTTP POST handler (supporting clients that do not use SSE)
pub async fn mcp_direct_post_handler(
    State(gateway): State<Arc<McpGatewayState>>,
    Query(params): Query<HashMap<String, String>>,
    Json(payload): Json<Value>,
) -> impl IntoResponse {
    let token = params.get("token").cloned().unwrap_or_else(|| "default".to_string());
    let response = process_jsonrpc_request(&gateway, &token, payload).await;
    Json(response)
}

/// GET /v1/mcp/tunnel
/// WebSocket endpoint for MicroCode Desktop IDE on macOS to connect outbound
pub async fn mcp_tunnel_ws_handler(
    ws: WebSocketUpgrade,
    State(gateway): State<Arc<McpGatewayState>>,
    Query(params): Query<HashMap<String, String>>,
) -> Response {
    let token = params.get("token").cloned().unwrap_or_else(|| "default".to_string());
    ws.on_upgrade(move |socket| handle_desktop_tunnel(socket, gateway, token))
}

async fn handle_desktop_tunnel(mut socket: WebSocket, gateway: Arc<McpGatewayState>, token: String) {
    info!("[MCP Gateway] Desktop tunnel connected");
    let (tx, mut rx) = mpsc::channel::<Value>(64);

    gateway.desktop_tunnels.write().await.insert(token.clone(), tx);

    let (mut sender, mut receiver) = socket.split();

    // Outbound writer task
    let mut write_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            let txt = serde_json::to_string(&msg).unwrap_or_default();
            if sender.send(Message::Text(txt)).await.is_err() {
                break;
            }
        }
    });

    // Inbound reader task
    let gateway_clone = gateway.clone();
    let token_clone = token.clone();
    let disconnect_token = token.clone();
    let mut read_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            if let Message::Text(txt) = msg {
                if let Ok(json_val) = serde_json::from_str::<Value>(&txt) {
                    // Check if this is a response to a pending tool call
                    if let Some(id) = json_val.get("id").and_then(|v| v.as_u64()) {
                        let mut pending = gateway_clone.pending_calls.write().await;
                        if pending.get(&id).map(|(owner, _)| owner == &token_clone).unwrap_or(false) {
                            if let Some((_, pending_tx)) = pending.remove(&id) { let _ = pending_tx.send(json_val); }
                        }
                    }
                }
            }
        }
    });

    tokio::select! {
        _ = (&mut write_task) => {},
        _ = (&mut read_task) => {},
    }

    write_task.abort();
    read_task.abort();
    gateway.desktop_tunnels.write().await.remove(&disconnect_token);
    info!("[MCP Gateway] Desktop tunnel disconnected");
}

// MARK: - JSON-RPC Dispatcher

async fn process_jsonrpc_request(gateway: &Arc<McpGatewayState>, token: &str, req: Value) -> Value {
    let id = req.get("id").cloned().unwrap_or(Value::Null);
    let method = req.get("method").and_then(|m| m.as_str()).unwrap_or("");

    match method {
        "initialize" => json!({
            "jsonrpc": "2.0",
            "id": id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {
                    "tools": { "listChanged": true },
                    "resources": { "subscribe": false, "listChanged": true }
                },
                "serverInfo": {
                    "name": "Dotmini MicroCode Cloud Gateway",
                    "version": "2.5.0",
                    "cloud": "api.dotmini.net"
                }
            }
        }),

        "initialized" => json!({
            "jsonrpc": "2.0",
            "id": id,
            "result": null
        }),

        "ping" => json!({
            "jsonrpc": "2.0",
            "id": id,
            "result": { "status": "pong" }
        }),

        "tools/list" => {
            let mut manifest = McpGatewayState::get_tools_manifest();
            json!({
                "jsonrpc": "2.0",
                "id": id,
                "result": manifest
            })
        },

        "tools/call" => {
            let params = req.get("params").cloned().unwrap_or_default();
            let tool_name = params.get("name").and_then(|n| n.as_str()).unwrap_or("");
            let arguments = params.get("arguments").cloned().unwrap_or(json!({}));

            // If desktop IDE is connected via tunnel, relay to local machine!
            let desktop_sender = gateway.desktop_tunnels.read().await.get(token).cloned();

            if let Some(desktop_tx) = desktop_sender {
                let call_id = gateway.next_call_id.fetch_add(1, Ordering::SeqCst);
                let (reply_tx, reply_rx) = oneshot::channel();

                gateway.pending_calls.write().await.insert(call_id, (token.to_string(), reply_tx));

                let forward_req = json!({
                    "jsonrpc": "2.0",
                    "id": call_id,
                    "method": "tools/call",
                    "params": {
                        "name": tool_name,
                        "arguments": arguments
                    }
                });

                if desktop_tx.send(forward_req).await.is_ok() {
                    // Await response with 60 second timeout
                    match tokio::time::timeout(Duration::from_secs(60), reply_rx).await {
                        Ok(Ok(response)) => {
                            if let Some(error) = response.get("error") {
                                return json!({"jsonrpc": "2.0", "id": id, "error": error});
                            }
                            if let Some(result) = response.get("result") {
                                return json!({"jsonrpc": "2.0", "id": id, "result": result});
                            }
                            return json!({"jsonrpc": "2.0", "id": id,
                                "error": {"code": -32603, "message": "Desktop returned an invalid tool response"}});
                        },
                        _ => {
                            gateway.pending_calls.write().await.remove(&call_id);
                            return json!({
                                "jsonrpc": "2.0",
                                "id": id,
                                "error": { "code": -32000, "message": "Desktop IDE execution timed out" }
                            });
                        }
                    }
                }
                gateway.pending_calls.write().await.remove(&call_id);
            }

            // No host execution is available when the desktop is disconnected.
            execute_cloud_fallback(id, tool_name, arguments).await
        },

        _ => json!({
            "jsonrpc": "2.0",
            "id": id,
            "error": { "code": -32601, "message": format!("Method not found: {}", method) }
        }),
    }
}

async fn execute_cloud_fallback(id: Value, tool_name: &str, _args: Value) -> Value {
    // This desktop gateway has no authenticated cloud execution/health adapter.
    // Never fabricate completion or run arbitrary code on the gateway host.
    json!({
        "jsonrpc": "2.0", "id": id,
        "error": { "code": -32601, "message": format!("Tool '{}' requires a connected desktop; cloud fallback is unavailable", tool_name) }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn disconnected_tools_never_report_success() {
        let gateway = Arc::new(McpGatewayState::new());
        let response = process_jsonrpc_request(&gateway, "test", json!({
            "id": 1, "method": "tools/call", "params": {"name": "cloud_gpu_status"}
        })).await;
        assert!(response.get("error").is_some());
        assert!(response.get("result").is_none());
    }

    #[tokio::test]
    async fn desktop_error_is_preserved_and_failed_send_is_cleaned_up() {
        let gateway = Arc::new(McpGatewayState::new());
        let (tx, mut rx) = mpsc::channel::<Value>(1);
        gateway.desktop_tunnels.write().await.insert("test".into(), tx);
        let responder = gateway.clone();
        let task = tokio::spawn(async move {
            let request = rx.recv().await.unwrap();
            let id = request["id"].as_u64().unwrap();
            let (_, reply) = responder.pending_calls.write().await.remove(&id).unwrap();
            reply.send(json!({"error": {"code": -32001, "message": "Permission denied"}})).unwrap();
        });
        let request = json!({"id": 7, "method": "tools/call", "params": {"name": "run_cell"}});
        let response = process_jsonrpc_request(&gateway, "test", request.clone()).await;
        task.await.unwrap();
        assert_eq!(response["error"]["code"], -32001);
        assert!(response.get("result").is_none());
        let response = process_jsonrpc_request(&gateway, "test", request).await;
        assert!(response.get("error").is_some());
        assert!(gateway.pending_calls.read().await.is_empty());
    }
}
