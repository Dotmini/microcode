mod executor;

use std::env;
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::accept_hdr_async;
use tokio_tungstenite::tungstenite::handshake::server::{ErrorResponse, Request, Response};
use futures_util::{StreamExt, SinkExt};
use tokio_tungstenite::tungstenite::Message;
use tokio::sync::mpsc;
use uuid::Uuid;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let port = env::var("AGENT_PORT").unwrap_or_else(|_| "8080".to_string());
    // Remote/HPC deployments listen on all interfaces by default; set AGENT_BIND=127.0.0.1 for local-only use.
    let bind = env::var("AGENT_BIND").unwrap_or_else(|_| "0.0.0.0".to_string());
    let addr = format!("{}:{}", bind, port);
    
    let token = env::var("AGENT_TOKEN").unwrap_or_else(|_| {
        let generated = Uuid::new_v4().to_string();
        println!("⚠️ No AGENT_TOKEN provided in environment.");
        println!("🔑 Generated Temporary Auth Token: {}", generated);
        println!("Please copy this token to your MicroCode App's HPC Settings.");
        generated
    });

    let listener = TcpListener::bind(&addr).await?;
    println!("🚀 MicroCode Agent running on ws://{}", addr);

    while let Ok((stream, _)) = listener.accept().await {
        let token_clone = token.clone();
        tokio::spawn(handle_connection(stream, token_clone));
    }

    Ok(())
}

/// Constant-time byte comparison so the token cannot be recovered through response timing.
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.iter().zip(b.iter()).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

async fn handle_connection(stream: TcpStream, expected_token: String) {
    let callback = |req: &Request, response: Response| -> Result<Response, ErrorResponse> {
        let presented = req
            .headers()
            .get("Authorization")
            .and_then(|h| h.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .unwrap_or("");

        if constant_time_eq(presented.as_bytes(), expected_token.as_bytes()) {
            Ok(response)
        } else {
            // Returning Err aborts the handshake. (Setting a 401 status on an Ok response still upgraded the
            // socket, so unauthenticated clients could reach the code executor.)
            let mut reject = ErrorResponse::new(Some("Unauthorized".to_string()));
            *reject.status_mut() = tokio_tungstenite::tungstenite::http::StatusCode::UNAUTHORIZED;
            Err(reject)
        }
    };

    let ws_stream = match accept_hdr_async(stream, callback).await {
        Ok(ws) => ws,
        Err(e) => {
            println!("WebSocket handshake failed: {}", e);
            return;
        }
    };

    println!("🔌 New authenticated WebSocket connection established.");

    let (mut ws_sender, mut ws_receiver) = ws_stream.split();
    
    // Channel for the executor to send messages out to the WebSocket
    let (ws_tx, mut ws_rx) = mpsc::channel::<Message>(100);
    let (cancel_tx, cancel_rx) = mpsc::channel::<bool>(1);

    // Spawn task to forward ws_tx channel messages to the actual websocket
    tokio::spawn(async move {
        while let Some(msg) = ws_rx.recv().await {
            if ws_sender.send(msg).await.is_err() {
                break;
            }
        }
    });

    while let Some(msg) = ws_receiver.next().await {
        match msg {
            Ok(Message::Text(text)) => {
                // Check if it's a cancel request
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if let Some(msg_type) = json.get("type").and_then(|v| v.as_str()) {
                        if msg_type == "cancel" {
                            let _ = cancel_tx.send(true).await;
                            continue;
                        }
                    }
                    
                    // Otherwise try to parse as ExecPayload
                    if let Ok(payload) = serde_json::from_str::<executor::ExecPayload>(&text) {
                        println!("⚡️ Received execution payload for: {}", payload.language);
                        
                        let tx_clone = ws_tx.clone();
                        // Assuming executor::handle_execution is updated to take the mpsc::Sender instead of SplitSink
                        tokio::spawn(executor::handle_execution(tx_clone, payload, cancel_rx));
                        
                        // Note: Because we spawn this, a new cancel_rx must be made per execution if we want to support multiple concurrent executions per socket.
                        // For a simple single-tenant agent, this is sufficient.
                        break; // After one execution payload, we might break or continue. Let's just handle one execution per connection for simplicity, like Jupyter kernels often do.
                    }
                }
            }
            Ok(Message::Ping(data)) => {
                let _ = ws_tx.send(Message::Pong(data)).await;
            }
            Ok(Message::Close(_)) | Err(_) => {
                println!("🔌 Connection closed.");
                break;
            }
            _ => {}
        }
    }
}
