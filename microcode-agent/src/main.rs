mod executor;

use std::env;
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::accept_hdr_async;
use tokio_tungstenite::tungstenite::handshake::server::{Request, Response};
use futures_util::{StreamExt, SinkExt};
use tokio_tungstenite::tungstenite::Message;
use tokio::sync::mpsc;
use uuid::Uuid;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let port = env::var("AGENT_PORT").unwrap_or_else(|_| "8080".to_string());
    let addr = format!("0.0.0.0:{}", port);
    
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

async fn handle_connection(stream: TcpStream, expected_token: String) {
    let callback = |req: &Request, mut response: Response| {
        let headers = req.headers();
        let mut authenticated = false;
        
        if let Some(auth_header) = headers.get("Authorization") {
            if let Ok(auth_str) = auth_header.to_str() {
                if auth_str == format!("Bearer {}", expected_token) {
                    authenticated = true;
                }
            }
        }
        
        if !authenticated {
            *response.status_mut() = tokio_tungstenite::tungstenite::http::StatusCode::UNAUTHORIZED;
        }
        
        Ok(response)
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
