use crate::state::AppState;
use async_trait::async_trait;
use axum::{
    extract::{
        ws::{Message, WebSocket},
        Json, State, WebSocketUpgrade,
    },
    response::IntoResponse,
};
use futures::{SinkExt, StreamExt};
use russh::*;
use russh_keys::*;
use russh_sftp::client::SftpSession;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::{Mutex, RwLock};

// Models
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct RemoteConnectionConfig {
    pub id: String,
    pub name: String,
    pub host: String,
    pub port: u16,
    pub username: String,
    pub auth_type: String, // "password" or "key"
    pub password: Option<String>,
    pub key_path: Option<String>,
    pub connection_type: String, // "ssh", "sftp", "ftp", "ftps"
}

pub struct SshSession {
    session: Arc<client::Handle<Client>>,
    sftp: Option<SftpSession>,
}

impl std::fmt::Debug for SshSession {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SshSession")
            .field("has_sftp", &self.sftp.is_some())
            .finish()
    }
}

// Client Handler
#[derive(Clone)]
struct Client {}

#[async_trait]
impl client::Handler for Client {
    type Error = russh::Error;
    // Using default check_server_key
}

// Connection Manager
#[derive(Debug, Clone)]
pub struct RemoteConnectionManager {
    sessions: Arc<Mutex<HashMap<String, SshSession>>>,
    pub ftp_manager: crate::ftp::FtpManager,
}

impl RemoteConnectionManager {
    pub fn new() -> Self {
        Self {
            sessions: Arc::new(Mutex::new(HashMap::new())),
            ftp_manager: crate::ftp::FtpManager::new(),
        }
    }

    fn expand_tilde(path: &str) -> String {
        if path.starts_with("~/") {
            if let Some(home) = dirs::home_dir() {
                return path.replacen("~", &home.to_string_lossy(), 1);
            }
        }
        path.to_string()
    }

    pub async fn connect(&self, config: RemoteConnectionConfig) -> Result<(), String> {
        // Protocol Router
        if config.connection_type == "ftp" || config.connection_type == "ftps" {
            return self
                .ftp_manager
                .connect(
                    &config.id,
                    &config.host,
                    config.port,
                    &config.username,
                    config.password.as_deref().unwrap_or(""),
                    config.connection_type == "ftps",
                )
                .await;
        }

        let mut ssh_config = client::Config::default();

        // Compatibility: Enable a wide range of algorithms to support older and newer servers
        // This solves "No common key algorithm" errors.
        ssh_config.preferred = Preferred {
            kex: std::borrow::Cow::Borrowed(&[
                russh::kex::CURVE25519,
                russh::kex::DH_G14_SHA256,
                russh::kex::DH_G14_SHA1,
                russh::kex::DH_G1_SHA1,
            ]),
            cipher: std::borrow::Cow::Borrowed(&[
                russh::cipher::CHACHA20_POLY1305,
                russh::cipher::AES_256_GCM,
                russh::cipher::AES_256_CTR,
                russh::cipher::AES_192_CTR,
                russh::cipher::AES_128_CTR,
            ]),
            key: std::borrow::Cow::Borrowed(&[
                russh_keys::key::ED25519,
                russh_keys::key::ECDSA_SHA2_NISTP256,
                russh_keys::key::RSA_SHA2_512,
                russh_keys::key::RSA_SHA2_256,
                russh_keys::key::SSH_RSA,
            ]),
            compression: std::borrow::Cow::Borrowed(&[
                russh::compression::NONE,
                russh::compression::ZLIB,
            ]),
            ..Default::default()
        };

        // Stability: Add KeepAlive to prevent timeouts
        ssh_config.keepalive_interval = Some(std::time::Duration::from_secs(10));

        let config_arc = Arc::new(ssh_config);
        let sh = Client {};

        // Increase initial connection timeout slightly to account for slow handshakes
        let mut session = match tokio::time::timeout(
            tokio::time::Duration::from_secs(45),
            client::connect(config_arc, (config.host.as_str(), config.port), sh),
        )
        .await
        {
            Ok(res) => res.map_err(|e| format!("Connection failed: {}", e))?,
            Err(_) => return Err("Connection timed out (45s)".to_string()),
        };

        let auth_res = if let Some(key_path) = config.key_path {
            let expanded_path = Self::expand_tilde(&key_path);

            // Check if file exists
            if !std::path::Path::new(&expanded_path).exists() {
                return Err(format!("SSH Key not found: {}", expanded_path));
            }

            let key_pair = load_secret_key(&expanded_path, None)
                .map_err(|e| format!("Failed to load SSH Key ({}): {}", expanded_path, e))?;

            session
                .authenticate_publickey(config.username, Arc::new(key_pair))
                .await
        } else if let Some(password) = config.password {
            session
                .authenticate_password(config.username, password)
                .await
        } else {
            return Err("No auth credentials provided".to_string());
        };

        if auth_res.map_err(|e| e.to_string())? {
            // Init SFTP
            let sftp = if let Ok(channel) = session.channel_open_session().await {
                if channel.request_subsystem(true, "sftp").await.is_ok() {
                    SftpSession::new(channel.into_stream()).await.ok()
                } else {
                    None
                }
            } else {
                None
            };

            let ssh_session = SshSession {
                session: Arc::new(session), // Wrap in Arc
                sftp,
            };

            let id = if config.id.is_empty() {
                "default".to_string()
            } else {
                config.id
            };
            self.sessions.lock().await.insert(id, ssh_session);
            Ok(())
        } else {
            Err("Authentication failed".to_string())
        }
    }

    // Interactive Shell via WebSocket
    pub async fn start_shell(&self, id: &str, mut ws: WebSocket) {
        let mut session = {
            let sessions = self.sessions.lock().await;
            if let Some(s) = sessions.get(id) {
                s.session.clone()
            } else {
                let _ = ws
                    .send(Message::Text("Session not found".to_string()))
                    .await;
                return;
            }
        };

        match session.channel_open_session().await {
            Ok(mut channel) => {
                // Request PTY for interactive shell
                let pty_res: Result<(), russh::Error> =
                    channel.request_pty(true, "xterm", 80, 24, 0, 0, &[]).await;
                if let Err(e) = pty_res {
                    let _ = ws
                        .send(Message::Text(format!("Failed to request PTY: {}", e)))
                        .await;
                    return;
                }

                if let Err(e) = channel.request_shell(true).await {
                    let _ = ws
                        .send(Message::Text(format!("Failed to request shell: {}", e)))
                        .await;
                    return;
                }

                let mut ws_sender = ws;
                // Split WebSocket? No, axum WebSocket is Stream + Sink.
                // We need to split it to handle read/write concurrently.
                let (mut ws_tx, mut ws_rx) = ws_sender.split();

                // Read from SSH Channel -> Send to WebSocket
                let mut channel_stream = channel.into_stream();
                let (mut ssh_read, mut ssh_write) = tokio::io::split(channel_stream);

                // Task 1: SSH -> WebSocket
                let ssh_to_ws = tokio::spawn(async move {
                    let mut buf = [0u8; 1024];
                    loop {
                        match ssh_read.read(&mut buf).await {
                            Ok(0) => break, // EOF
                            Ok(n) => {
                                if ws_tx
                                    .send(Message::Binary(buf[..n].to_vec()))
                                    .await
                                    .is_err()
                                {
                                    break;
                                }
                            }
                            Err(_) => break,
                        }
                    }
                });

                // Task 2: WebSocket -> SSH
                let ws_to_ssh = tokio::spawn(async move {
                    while let Some(Ok(msg)) = ws_rx.next().await {
                        match msg {
                            Message::Text(text) => {
                                // Handle special resize command: "RESIZE:cols:rows"
                                if text.starts_with("RESIZE:") {
                                    // In a real implementation, we'd parse this and call channel.request_pty_size
                                }
                                if let Err(_) = ssh_write.write_all(text.as_bytes()).await {
                                    break;
                                }
                            }
                            Message::Binary(data) => {
                                if let Err(_) = ssh_write.write_all(&data).await {
                                    break;
                                }
                            }
                            Message::Close(_) => break,
                            _ => {}
                        }
                    }
                });

                let _ = tokio::join!(ssh_to_ws, ws_to_ssh);
            }
            Err(e) => {
                let _ = ws
                    .send(Message::Text(format!("Failed to open channel: {}", e)))
                    .await;
            }
        }
    }

    pub async fn execute_command(&self, id: &str, command: String) -> Result<String, String> {
        let mut sessions = self.sessions.lock().await;
        if let Some(ssh_session) = sessions.get_mut(id) {
            let mut channel = ssh_session
                .session
                .channel_open_session()
                .await
                .map_err(|e| e.to_string())?;
            channel
                .exec(true, command)
                .await
                .map_err(|e| e.to_string())?;

            let mut output = String::new();
            while let Some(msg) = channel.wait().await {
                match msg {
                    russh::ChannelMsg::Data { ref data } => {
                        output.push_str(&String::from_utf8_lossy(data));
                    }
                    _ => {}
                }
            }
            Ok(output)
        } else {
            Err("Session not found".to_string())
        }
    }

    // Unified List Files (routes to SFTP or FTP)
    pub async fn list_files(
        &self,
        id: &str,
        path: String,
    ) -> Result<Vec<crate::models::FileInfo>, String> {
        // Try FTP first if ID matches an FTP session
        if let Ok(files) = self.ftp_manager.list_files(id, &path).await {
            return Ok(files);
        }

        let sessions = self.sessions.lock().await;
        if let Some(ssh_session) = sessions.get(id) {
            if let Some(sftp) = &ssh_session.sftp {
                let mut readdir = sftp.read_dir(&path).await.map_err(|e| e.to_string())?;
                let mut files = Vec::new();

                while let Some(entry) = readdir.next() {
                    let name = entry.file_name();
                    let stat = entry.metadata();

                    files.push(crate::models::FileInfo {
                        name: name.clone(),
                        path: format!("{}/{}", path.trim_end_matches('/'), name),
                        is_directory: stat.is_dir(),
                        extension: std::path::Path::new(&name)
                            .extension()
                            .map(|s| s.to_string_lossy().to_string()),
                        modified: Some(
                            chrono::DateTime::from_timestamp(stat.mtime.unwrap_or(0) as i64, 0)
                                .unwrap_or_default()
                                .to_rfc3339(),
                        ),
                        size: stat.size.unwrap_or(0),
                    });
                }

                Ok(files)
            } else {
                Err("SFTP not initialized".to_string())
            }
        } else {
            Err("Session not found".to_string())
        }
    }

    // Unified Upload (routes to SFTP or FTP)
    pub async fn upload_file(
        &self,
        id: &str,
        remote_path: String,
        content: Vec<u8>,
    ) -> Result<(), String> {
        if let Ok(_) = self
            .ftp_manager
            .upload_file(id, &remote_path, &content)
            .await
        {
            return Ok(());
        }

        let sessions = self.sessions.lock().await;
        if let Some(ssh_session) = sessions.get(id) {
            if let Some(sftp) = &ssh_session.sftp {
                let mut file = sftp.create(&remote_path).await.map_err(|e| e.to_string())?;
                file.write_all(&content).await.map_err(|e| e.to_string())?;
                Ok(())
            } else {
                Err("SFTP not initialized".to_string())
            }
        } else {
            Err("Session not found".to_string())
        }
    }

    // Unified Download (routes to SFTP or FTP)
    pub async fn download_file(&self, id: &str, remote_path: String) -> Result<Vec<u8>, String> {
        if let Ok(data) = self.ftp_manager.download_file(id, &remote_path).await {
            return Ok(data);
        }

        let sessions = self.sessions.lock().await;
        if let Some(ssh_session) = sessions.get(id) {
            if let Some(sftp) = &ssh_session.sftp {
                let mut file = sftp.open(&remote_path).await.map_err(|e| e.to_string())?;
                let mut content = Vec::new();
                file.read_to_end(&mut content)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(content)
            } else {
                Err("SFTP not initialized".to_string())
            }
        } else {
            Err("Session not found".to_string())
        }
    }

    pub async fn mkdir(&self, id: &str, path: String) -> Result<(), String> {
        if let Ok(_) = self.ftp_manager.mkdir(id, &path).await {
            return Ok(());
        }

        let sessions = self.sessions.lock().await;
        if let Some(ssh_session) = sessions.get(id) {
            if let Some(sftp) = &ssh_session.sftp {
                sftp.create_dir(&path).await.map_err(|e| e.to_string())?;
                Ok(())
            } else {
                Err("SFTP not initialized".to_string())
            }
        } else {
            Err("Session not found".to_string())
        }
    }

    pub async fn remove(&self, id: &str, path: String, is_directory: bool) -> Result<(), String> {
        if is_directory {
            if let Ok(_) = self.ftp_manager.remove_dir(id, &path).await {
                return Ok(());
            }
        } else {
            if let Ok(_) = self.ftp_manager.remove_file(id, &path).await {
                return Ok(());
            }
        }

        let sessions = self.sessions.lock().await;
        if let Some(ssh_session) = sessions.get(id) {
            if let Some(sftp) = &ssh_session.sftp {
                if is_directory {
                    sftp.remove_dir(&path).await.map_err(|e| e.to_string())?;
                } else {
                    sftp.remove_file(&path).await.map_err(|e| e.to_string())?;
                }
                Ok(())
            } else {
                Err("SFTP not initialized".to_string())
            }
        } else {
            Err("Session not found".to_string())
        }
    }

    pub async fn rename(
        &self,
        id: &str,
        source: String,
        destination: String,
    ) -> Result<(), String> {
        if let Ok(_) = self.ftp_manager.rename(id, &source, &destination).await {
            return Ok(());
        }

        let sessions = self.sessions.lock().await;
        if let Some(ssh_session) = sessions.get(id) {
            if let Some(sftp) = &ssh_session.sftp {
                sftp.rename(&source, &destination)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(())
            } else {
                Err("SFTP not initialized".to_string())
            }
        } else {
            Err("Session not found".to_string())
        }
    }

    pub async fn ping_host(host: &str, port: u16) -> bool {
        use tokio::net::TcpStream;
        use tokio::time::{timeout, Duration};

        let addr = format!("{}:{}", host, port);
        match timeout(Duration::from_secs(2), TcpStream::connect(&addr)).await {
            Ok(Ok(_)) => true,
            _ => false,
        }
    }
}

// API Handlers

#[derive(Deserialize)]
pub struct ConnectRequest {
    pub id: String,
    pub host: String,
    pub port: u16,
    pub username: String,
    pub auth_type: String,
    pub password: String,
    pub key_path: String,
    pub connection_type: Option<String>,
}

#[derive(Deserialize)]
pub struct ExecRequest {
    pub id: String,
    pub command: String,
}

#[derive(Deserialize)]
pub struct ListFilesRequest {
    pub id: String,
    pub path: String,
}

#[derive(Deserialize)]
pub struct MkdirRequest {
    pub id: String,
    pub path: String,
}

#[derive(Deserialize)]
pub struct RemoveRequest {
    pub id: String,
    pub path: String,
    pub is_directory: bool,
}

#[derive(Deserialize)]
pub struct RenameRequest {
    pub id: String,
    pub source: String,
    pub destination: String,
}

// Handlers
pub async fn remote_connect(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<ConnectRequest>,
) -> impl IntoResponse {
    let config = RemoteConnectionConfig {
        id: req.id.clone(),
        name: format!("{}:{}", req.host, req.port),
        host: req.host,
        port: req.port,
        username: req.username,
        auth_type: req.auth_type,
        password: if req.password.is_empty() {
            None
        } else {
            Some(req.password)
        },
        key_path: if req.key_path.is_empty() {
            None
        } else {
            Some(req.key_path)
        },
        connection_type: req.connection_type.unwrap_or_else(|| "ssh".to_string()),
    };

    let st = state.read().await;
    match st.remote_manager.connect(config).await {
        Ok(_) => Json(serde_json::json!({ "success": true, "message": "Connected" })),
        Err(e) => Json(serde_json::json!({ "success": false, "message": e })),
    }
}

pub async fn remote_shell_ws(
    axum::extract::Path(id): axum::extract::Path<String>,
    ws: WebSocketUpgrade,
    State(state): State<Arc<RwLock<AppState>>>,
) -> impl IntoResponse {
    let manager = state.read().await.remote_manager.clone();

    ws.on_upgrade(move |socket| async move {
        manager.start_shell(&id, socket).await;
    })
}

pub async fn remote_exec(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<ExecRequest>,
) -> impl IntoResponse {
    let st = state.read().await;
    match st
        .remote_manager
        .execute_command(&req.id, req.command)
        .await
    {
        Ok(output) => Json(serde_json::json!({ "output": output })),
        Err(e) => Json(serde_json::json!({ "output": format!("Error: {}", e) })),
    }
}

pub async fn remote_list_files(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<ListFilesRequest>,
) -> impl IntoResponse {
    let st = state.read().await;
    match st.remote_manager.list_files(&req.id, req.path).await {
        Ok(files) => Json(serde_json::json!({ "files": files })),
        Err(_e) => Json(serde_json::json!({ "files": [] })), // Return empty on error for now or handle better
    }
}

// Simple upload handler (JSON with base64 content for simplicity in this iteration)
#[derive(Deserialize)]
pub struct UploadRequest {
    pub id: String,
    pub path: String,
    pub content_base64: String,
}

pub async fn remote_upload(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<UploadRequest>,
) -> impl IntoResponse {
    use base64::{engine::general_purpose, Engine as _};

    let content = match general_purpose::STANDARD.decode(&req.content_base64) {
        Ok(c) => c,
        Err(_) => {
            return Json(serde_json::json!({ "success": false, "message": "Invalid base64" }))
        }
    };

    let st = state.read().await;
    match st
        .remote_manager
        .upload_file(&req.id, req.path, content)
        .await
    {
        Ok(_) => Json(serde_json::json!({ "success": true })),
        Err(e) => Json(serde_json::json!({ "success": false, "message": e })),
    }
}

#[derive(Deserialize)]
pub struct DownloadRequest {
    pub id: String,
    pub path: String,
}

#[derive(Deserialize)]
pub struct PingRequest {
    pub host: String,
    pub port: u16,
}

pub async fn remote_ping(Json(req): Json<PingRequest>) -> impl IntoResponse {
    let success = RemoteConnectionManager::ping_host(&req.host, req.port).await;
    Json(serde_json::json!({ "success": success }))
}

pub async fn remote_download(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<DownloadRequest>,
) -> impl IntoResponse {
    use base64::{engine::general_purpose, Engine as _};

    let st = state.read().await;
    match st.remote_manager.download_file(&req.id, req.path).await {
        Ok(content) => {
            let b64 = general_purpose::STANDARD.encode(&content);
            Json(serde_json::json!({ "success": true, "content": b64 }))
        }
        Err(e) => Json(serde_json::json!({ "success": false, "message": e })),
    }
}

pub async fn remote_mkdir(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<MkdirRequest>,
) -> impl IntoResponse {
    let st = state.read().await;
    match st.remote_manager.mkdir(&req.id, req.path).await {
        Ok(_) => Json(serde_json::json!({ "success": true })),
        Err(e) => Json(serde_json::json!({ "success": false, "message": e })),
    }
}

pub async fn remote_remove(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<RemoveRequest>,
) -> impl IntoResponse {
    let st = state.read().await;
    match st
        .remote_manager
        .remove(&req.id, req.path, req.is_directory)
        .await
    {
        Ok(_) => Json(serde_json::json!({ "success": true })),
        Err(e) => Json(serde_json::json!({ "success": false, "message": e })),
    }
}

pub async fn remote_rename(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<RenameRequest>,
) -> impl IntoResponse {
    let st = state.read().await;
    match st
        .remote_manager
        .rename(&req.id, req.source, req.destination)
        .await
    {
        Ok(_) => Json(serde_json::json!({ "success": true })),
        Err(e) => Json(serde_json::json!({ "success": false, "message": e })),
    }
}
