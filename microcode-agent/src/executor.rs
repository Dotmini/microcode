use serde::{Deserialize, Serialize};
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::{Child, Command};
use tokio::sync::mpsc;
use futures_util::stream::{SplitSink, StreamExt};
use futures_util::SinkExt;
use tokio_tungstenite::WebSocketStream;
use tokio_tungstenite::tungstenite::Message;
use tokio::net::TcpStream;

#[derive(Deserialize, Debug)]
pub struct ExecPayload {
    pub language: String,
    pub code: String,
}

#[derive(Serialize, Debug)]
pub struct OutputPayload {
    pub r#type: String,
    pub data: String,
}

pub async fn handle_execution(
    ws_sender: mpsc::Sender<Message>,
    payload: ExecPayload,
    mut cancel_rx: mpsc::Receiver<bool>,
) {
    let mut command = match payload.language.to_lowercase().as_str() {
        "python" => {
            let mut cmd = Command::new("python3");
            cmd.arg("-c").arg(&payload.code);
            cmd
        }
        "r" => {
            let mut cmd = Command::new("Rscript");
            cmd.arg("-e").arg(&payload.code);
            cmd
        }
        "julia" => {
            let mut cmd = Command::new("julia");
            cmd.arg("-e").arg(&payload.code);
            cmd
        }
        _ => {
            let error_msg = serde_json::to_string(&OutputPayload {
                r#type: "error".to_string(),
                data: format!("Unsupported language: {}", payload.language),
            }).unwrap();
            let _ = ws_sender.send(Message::Text(error_msg)).await;
            return;
        }
    };
    
    command.stdout(Stdio::piped());
    command.stderr(Stdio::piped());

    let mut child = match command.spawn() {
        Ok(c) => c,
        Err(e) => {
            let error_msg = serde_json::to_string(&OutputPayload {
                r#type: "error".to_string(),
                data: format!("Failed to spawn process: {}", e),
            }).unwrap();
            let _ = ws_sender.send(Message::Text(error_msg)).await;
            return;
        }
    };

    let stdout = child.stdout.take().expect("Failed to open stdout");
    let stderr = child.stderr.take().expect("Failed to open stderr");

    let mut stdout_reader = BufReader::new(stdout).lines();
    let mut stderr_reader = BufReader::new(stderr).lines();

    let (tx, mut rx) = mpsc::channel::<String>(100);

    let tx_out = tx.clone();
    tokio::spawn(async move {
        while let Ok(Some(line)) = stdout_reader.next_line().await {
            let _ = tx_out.send(line).await;
        }
    });

    let tx_err = tx.clone();
    tokio::spawn(async move {
        while let Ok(Some(line)) = stderr_reader.next_line().await {
            let _ = tx_err.send(format!("ERROR: {}", line)).await;
        }
    });

    loop {
        tokio::select! {
            Some(line) = rx.recv() => {
                let msg = serde_json::to_string(&OutputPayload {
                    r#type: "output".to_string(),
                    data: line,
                }).unwrap();
                let _ = ws_sender.send(Message::Text(msg)).await;
            }
            _ = cancel_rx.recv() => {
                let _ = child.kill().await;
                let cancel_msg = serde_json::to_string(&OutputPayload {
                    r#type: "error".to_string(),
                    data: "Process was cancelled by client (SIGKILL).".to_string(),
                }).unwrap();
                let _ = ws_sender.send(Message::Text(cancel_msg)).await;
                break;
            }
            status = child.wait() => {
                let status_str = match status {
                    Ok(s) => format!("Exited with code: {}", s.code().unwrap_or(0)),
                    Err(e) => format!("Wait error: {}", e),
                };
                let done_msg = serde_json::to_string(&OutputPayload {
                    r#type: "completed".to_string(),
                    data: status_str,
                }).unwrap();
                let _ = ws_sender.send(Message::Text(done_msg)).await;
                break;
            }
        }
    }
}
