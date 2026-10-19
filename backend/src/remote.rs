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
    pub otp: Option<String>,
}

#[derive(Clone)]
pub struct SshSession {
    session: Arc<client::Handle<Client>>,
    sftp: Option<Arc<SftpSession>>,
}

impl std::fmt::Debug for SshSession {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SshSession")
            .field("has_sftp", &self.sftp.is_some())
            .finish()
    }
}

// Client Handler with TOFU (Trust-On-First-Use) Host Key Verification
#[derive(Clone)]
struct Client {
    host: String,
    port: u16,
}

#[async_trait]
impl client::Handler for Client {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        server_public_key: &russh_keys::key::PublicKey,
    ) -> Result<bool, Self::Error> {
        let fingerprint = server_public_key.fingerprint();
        let safe_host: String = self
            .host
            .to_lowercase()
            .chars()
            .filter(|c| !c.is_whitespace())
            .collect();
        let host_id = format!("{}:{}", safe_host, self.port);

        if let Some(home) = dirs::home_dir() {
            let ssh_dir = home.join(".microcode");
            let _ = std::fs::create_dir_all(&ssh_dir);
            let known_hosts_file = ssh_dir.join("ssh_known_hosts");

            if let Ok(existing) = std::fs::read_to_string(&known_hosts_file) {
                for line in existing.lines() {
                    let line = line.trim();
                    if line.is_empty() || line.starts_with('#') {
                        continue;
                    }
                    if let Some((saved_host, saved_fp)) = line.split_once(' ') {
                        if saved_host == host_id {
                            if saved_fp.trim() == fingerprint {
                                return Ok(true);
                            } else {
                                tracing::error!(
                                    "SSH HOST KEY MISMATCH for {}! Expected {}, got {}. Rejecting potential MITM connection.",
                                    host_id,
                                    saved_fp.trim(),
                                    fingerprint
                                );
                                return Ok(false);
                            }
                        }
                    }
                }
            }

            use std::io::Write;
            if let Ok(mut file) = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(&known_hosts_file)
            {
                let _ = writeln!(file, "{} {}", host_id, fingerprint);
            }
        }

        Ok(true)
    }
}

// Connection Manager
#[derive(Debug, Clone)]
pub struct RemoteConnectionManager {
    sessions: Arc<Mutex<HashMap<String, SshSession>>>,
    configs: Arc<Mutex<HashMap<String, RemoteConnectionConfig>>>,
    pub ftp_manager: crate::ftp::FtpManager,
}

impl RemoteConnectionManager {
    pub fn new() -> Self {
        Self {
            sessions: Arc::new(Mutex::new(HashMap::new())),
            configs: Arc::new(Mutex::new(HashMap::new())),
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

    async fn try_ssh_agent_auth(
        session: &mut client::Handle<Client>,
        username: &str,
    ) -> Result<bool, String> {
        #[cfg(unix)]
        {
            if let Ok(sock_path) = std::env::var("SSH_AUTH_SOCK") {
                if !sock_path.is_empty() && std::path::Path::new(&sock_path).exists() {
                    if let Ok(stream) = tokio::net::UnixStream::connect(&sock_path).await {
                        let mut agent = russh_keys::agent::client::AgentClient::connect(stream);
                        if let Ok(identities) = agent.request_identities().await {
                            for pubkey in identities {
                                let res = session
                                    .authenticate_future(username, pubkey, agent)
                                    .await;
                                agent = res.0;
                                if let Ok(true) = res.1 {
                                    return Ok(true);
                                }
                            }
                        }
                    }
                }
            }
        }
        Ok(false)
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

        // Modern KEX and Ciphers (DH_G1_SHA1 removed to prevent Logjam downgrade)
        ssh_config.preferred = Preferred {
            kex: std::borrow::Cow::Borrowed(&[
                russh::kex::CURVE25519,
                russh::kex::DH_G14_SHA256,
                russh::kex::DH_G14_SHA1,
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

        ssh_config.keepalive_interval = Some(std::time::Duration::from_secs(10));
        ssh_config.keepalive_max = 6;

        let config_arc = Arc::new(ssh_config);
        let sh = Client {
            host: config.host.clone(),
            port: config.port,
        };

        let mut session = match tokio::time::timeout(
            tokio::time::Duration::from_secs(45),
            client::connect(config_arc, (config.host.as_str(), config.port), sh),
        )
        .await
        {
            Ok(res) => res.map_err(|e| format!("Connection failed: {}", e))?,
            Err(_) => return Err("Connection timed out (45s)".to_string()),
        };

        let auth_res: Result<bool, String> = if let Some(key_path) = config.key_path.as_ref().filter(|s| !s.is_empty()) {
            let expanded_path = Self::expand_tilde(key_path);

            if !std::path::Path::new(&expanded_path).exists() {
                // Try SSH agent fallback before failing
                if Self::try_ssh_agent_auth(&mut session, &config.username).await.unwrap_or(false) {
                    Ok(true)
                } else {
                    Err(format!("SSH Key not found: {}", expanded_path))
                }
            } else {
                let passphrase = config.password.as_deref().filter(|s| !s.is_empty());
                match load_secret_key(&expanded_path, passphrase) {
                    Ok(key_pair) => session
                        .authenticate_publickey(config.username.clone(), Arc::new(key_pair))
                        .await
                        .map_err(|e| e.to_string()),
                    Err(e) => {
                        if Self::try_ssh_agent_auth(&mut session, &config.username).await.unwrap_or(false) {
                            Ok(true)
                        } else {
                            let err_str = e.to_string();
                            if err_str.contains("encrypted") {
                                Err(format!("Failed to load SSH Key ({}): The key is encrypted with a passphrase. Please enter your Key Passphrase in Server Settings (Edit).", expanded_path))
                            } else {
                                Err(format!("Failed to load SSH Key ({}): {}", expanded_path, e))
                            }
                        }
                    }
                }
            }
        } else if let Some(password) = config.password.as_ref().filter(|s| !s.is_empty()) {
            let pass_res = session
                .authenticate_password(config.username.clone(), password.clone())
                .await;

            match pass_res {
                Ok(true) => Ok(true),
                _ => {
                    match session
                        .authenticate_keyboard_interactive_start(config.username.clone(), None)
                        .await
                    {
                        Ok(russh::client::KeyboardInteractiveAuthResponse::Success) => Ok(true),
                        Ok(russh::client::KeyboardInteractiveAuthResponse::InfoRequest { prompts, .. }) => {
                            let mut responses = Vec::new();
                            for p in &prompts {
                                let lower = p.prompt.to_lowercase();
                                if lower.contains("verification")
                                    || lower.contains("code")
                                    || lower.contains("otp")
                                    || lower.contains("token")
                                {
                                    responses.push(config.otp.clone().unwrap_or_default());
                                } else {
                                    responses.push(password.clone());
                                }
                            }
                            match session
                                .authenticate_keyboard_interactive_respond(responses)
                                .await
                            {
                                Ok(russh::client::KeyboardInteractiveAuthResponse::Success) => {
                                    Ok(true)
                                }
                                Ok(russh::client::KeyboardInteractiveAuthResponse::InfoRequest {
                                    prompts: next_prompts,
                                    ..
                                }) => {
                                    let mut next_resp = Vec::new();
                                    for p in &next_prompts {
                                        let lower = p.prompt.to_lowercase();
                                        if lower.contains("verification")
                                            || lower.contains("code")
                                            || lower.contains("otp")
                                            || lower.contains("token")
                                        {
                                            next_resp.push(config.otp.clone().unwrap_or_default());
                                        } else {
                                            next_resp.push(password.clone());
                                        }
                                    }
                                    match session
                                        .authenticate_keyboard_interactive_respond(next_resp)
                                        .await
                                    {
                                        Ok(russh::client::KeyboardInteractiveAuthResponse::Success) => {
                                            Ok(true)
                                        }
                                        _ => Err(
                                            "Keyboard-interactive (2FA) failed. Please verify Password and OTP."
                                                .to_string(),
                                        ),
                                    }
                                }
                                _ => Err("Keyboard-interactive authentication failed".to_string()),
                            }
                        }
                        _ => Err("Authentication failed: Server rejected password and keyboard-interactive auth".to_string()),
                    }
                }
            }
        } else {
            // Try SSH Agent first, then default SSH keys (~/.ssh/id_ed25519, ~/.ssh/id_ecdsa, ~/.ssh/id_rsa)
            if Self::try_ssh_agent_auth(&mut session, &config.username).await.unwrap_or(false) {
                Ok(true)
            } else {
                let mut authed = false;
                for default_key in &["~/.ssh/id_ed25519", "~/.ssh/id_ecdsa", "~/.ssh/id_rsa"] {
                    let expanded = Self::expand_tilde(default_key);
                    if std::path::Path::new(&expanded).exists() {
                        if let Ok(kp) = load_secret_key(&expanded, None) {
                            if let Ok(true) = session
                                .authenticate_publickey(config.username.clone(), Arc::new(kp))
                                .await
                            {
                                authed = true;
                                break;
                            }
                        }
                    }
                }
                if authed {
                    Ok(true)
                } else {
                    Err("No valid authentication credentials or SSH agent keys found".to_string())
                }
            }
        };

        if auth_res? {
            let sftp = if let Ok(channel) = session.channel_open_session().await {
                if channel.request_subsystem(true, "sftp").await.is_ok() {
                    SftpSession::new(channel.into_stream())
                        .await
                        .ok()
                        .map(Arc::new)
                } else {
                    None
                }
            } else {
                None
            };

            let ssh_session = SshSession {
                session: Arc::new(session),
                sftp,
            };

            let id = if config.id.is_empty() {
                "default".to_string()
            } else {
                config.id.clone()
            };
            let mut config_to_save = config;
            config_to_save.id = id.clone();
            self.configs.lock().await.insert(id.clone(), config_to_save);

            let previous = self.sessions.lock().await.insert(id, ssh_session);
            if let Some(old_session) = previous {
                let _ = old_session
                    .session
                    .disconnect(russh::Disconnect::ByApplication, "Reconnected", "en")
                    .await;
            }
            Ok(())
        } else {
            Err("Authentication failed".to_string())
        }
    }

    pub async fn disconnect(&self, id: &str) -> Result<(), String> {
        self.configs.lock().await.remove(id);
        let removed = self.sessions.lock().await.remove(id);
        if let Some(ssh_session) = removed {
            let _ = ssh_session
                .session
                .disconnect(russh::Disconnect::ByApplication, "User disconnected", "en")
                .await;
        }
        Ok(())
    }

    // Interactive Shell via WebSocket with live PTY window resize
    pub async fn start_shell(&self, id: &str, mut ws: WebSocket) {
        let session = {
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
                let pty_res: Result<(), russh::Error> =
                    channel.request_pty(true, "xterm-256color", 120, 32, 0, 0, &[]).await;
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

                let (mut ws_tx, mut ws_rx) = ws.split();

                loop {
                    tokio::select! {
                        msg = channel.wait() => {
                            match msg {
                                Some(russh::ChannelMsg::Data { ref data })
                                | Some(russh::ChannelMsg::ExtendedData { ref data, .. }) => {
                                    if ws_tx.send(Message::Binary(data.to_vec())).await.is_err() {
                                        break;
                                    }
                                }
                                Some(russh::ChannelMsg::Eof) | Some(russh::ChannelMsg::Close) | None => break,
                                _ => {}
                            }
                        }
                        ws_msg = ws_rx.next() => {
                            match ws_msg {
                                Some(Ok(Message::Text(text))) => {
                                    if let Some(rest) = text.strip_prefix("RESIZE:") {
                                        let parts: Vec<&str> = rest.trim().split(':').collect();
                                        if parts.len() >= 2 {
                                            if let (Ok(cols), Ok(rows)) = (parts[0].parse::<u32>(), parts[1].parse::<u32>()) {
                                                let _ = channel.window_change(cols.max(20), rows.max(5), 0, 0).await;
                                            }
                                        }
                                        continue;
                                    }
                                    if let Some(rest) = text.strip_prefix("R:") {
                                        let parts: Vec<&str> = rest.trim().split(',').collect();
                                        if parts.len() >= 2 {
                                            if let (Ok(cols), Ok(rows)) = (parts[0].parse::<u32>(), parts[1].parse::<u32>()) {
                                                let _ = channel.window_change(cols.max(20), rows.max(5), 0, 0).await;
                                            }
                                        }
                                        continue;
                                    }
                                    if channel.data(&text.as_bytes()[..]).await.is_err() {
                                        break;
                                    }
                                }
                                Some(Ok(Message::Binary(data))) => {
                                    if channel.data(&data[..]).await.is_err() {
                                        break;
                                    }
                                }
                                Some(Ok(Message::Close(_))) | None => break,
                                _ => {}
                            }
                        }
                    }
                }
            }
            Err(e) => {
                let _ = ws
                    .send(Message::Text(format!("Failed to open channel: {}", e)))
                    .await;
            }
        }
    }

    pub async fn execute_command_with_status(
        &self,
        id: &str,
        command: String,
    ) -> Result<(String, u32), String> {
        let session = {
            let sessions = self.sessions.lock().await;
            sessions
                .get(id)
                .map(|s| s.session.clone())
                .ok_or_else(|| "Session not found".to_string())?
        };

        let mut channel = match session.channel_open_session().await {
            Ok(ch) => ch,
            Err(_) => {
                // Attempt transparent 1-time reconnect if pooled config exists
                let saved_cfg = self.configs.lock().await.get(id).cloned();
                if let Some(cfg) = saved_cfg {
                    self.connect(cfg).await?;
                    let refreshed = {
                        let sessions = self.sessions.lock().await;
                        sessions
                            .get(id)
                            .map(|s| s.session.clone())
                            .ok_or_else(|| "Session not found after reconnect".to_string())?
                    };
                    refreshed
                        .channel_open_session()
                        .await
                        .map_err(|e| e.to_string())?
                } else {
                    return Err("SSH channel closed and no reconnect configuration available".to_string());
                }
            }
        };
        channel
            .exec(true, command)
            .await
            .map_err(|e| e.to_string())?;

        let mut output = String::new();
        let mut exit_code: u32 = 0;
        while let Some(msg) = channel.wait().await {
            match msg {
                russh::ChannelMsg::Data { ref data } => {
                    output.push_str(&String::from_utf8_lossy(data));
                }
                russh::ChannelMsg::ExtendedData { ref data, .. } => {
                    output.push_str(&String::from_utf8_lossy(data));
                }
                russh::ChannelMsg::ExitStatus { exit_status } => {
                    exit_code = exit_status;
                }
                _ => {}
            }
        }
        Ok((output, exit_code))
    }

    pub async fn execute_command(&self, id: &str, command: String) -> Result<String, String> {
        let (output, _) = self.execute_command_with_status(id, command).await?;
        Ok(output)
    }

    // Unified List Files (routes to SFTP or FTP without holding global lock across I/O)
    pub async fn list_files(
        &self,
        id: &str,
        path: String,
    ) -> Result<Vec<crate::models::FileInfo>, String> {
        if let Ok(files) = self.ftp_manager.list_files(id, &path).await {
            return Ok(files);
        }

        let sftp = {
            let sessions = self.sessions.lock().await;
            let ssh_session = sessions
                .get(id)
                .ok_or_else(|| "Session not found".to_string())?;
            ssh_session
                .sftp
                .clone()
                .ok_or_else(|| "SFTP not initialized".to_string())?
        };

        let mut readdir = sftp.read_dir(&path).await.map_err(|e| e.to_string())?;
        let mut files = Vec::new();

        while let Some(entry) = readdir.next() {
            let name = entry.file_name();
            if name == "." || name == ".." {
                continue;
            }
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
    }

    // Unified Upload (routes to SFTP or FTP without holding global lock across I/O)
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

        let sftp = {
            let sessions = self.sessions.lock().await;
            let ssh_session = sessions
                .get(id)
                .ok_or_else(|| "Session not found".to_string())?;
            ssh_session
                .sftp
                .clone()
                .ok_or_else(|| "SFTP not initialized".to_string())?
        };

        let mut file = sftp.create(&remote_path).await.map_err(|e| e.to_string())?;
        file.write_all(&content).await.map_err(|e| e.to_string())?;
        file.flush().await.map_err(|e| e.to_string())?;
        Ok(())
    }

    // Unified Download (routes to SFTP or FTP without holding global lock across I/O)
    pub async fn download_file(&self, id: &str, remote_path: String) -> Result<Vec<u8>, String> {
        if let Ok(data) = self.ftp_manager.download_file(id, &remote_path).await {
            return Ok(data);
        }

        let sftp = {
            let sessions = self.sessions.lock().await;
            let ssh_session = sessions
                .get(id)
                .ok_or_else(|| "Session not found".to_string())?;
            ssh_session
                .sftp
                .clone()
                .ok_or_else(|| "SFTP not initialized".to_string())?
        };

        let mut file = sftp.open(&remote_path).await.map_err(|e| e.to_string())?;
        let mut content = Vec::new();
        file.read_to_end(&mut content)
            .await
            .map_err(|e| e.to_string())?;
        Ok(content)
    }

    pub async fn mkdir(&self, id: &str, path: String) -> Result<(), String> {
        if let Ok(_) = self.ftp_manager.mkdir(id, &path).await {
            return Ok(());
        }

        let sftp = {
            let sessions = self.sessions.lock().await;
            let ssh_session = sessions
                .get(id)
                .ok_or_else(|| "Session not found".to_string())?;
            ssh_session
                .sftp
                .clone()
                .ok_or_else(|| "SFTP not initialized".to_string())?
        };

        sftp.create_dir(&path).await.map_err(|e| e.to_string())?;
        Ok(())
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

        let sftp = {
            let sessions = self.sessions.lock().await;
            let ssh_session = sessions
                .get(id)
                .ok_or_else(|| "Session not found".to_string())?;
            ssh_session
                .sftp
                .clone()
                .ok_or_else(|| "SFTP not initialized".to_string())?
        };

        if is_directory {
            sftp.remove_dir(&path).await.map_err(|e| e.to_string())?;
        } else {
            sftp.remove_file(&path).await.map_err(|e| e.to_string())?;
        }
        Ok(())
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

        let sftp = {
            let sessions = self.sessions.lock().await;
            let ssh_session = sessions
                .get(id)
                .ok_or_else(|| "Session not found".to_string())?;
            ssh_session
                .sftp
                .clone()
                .ok_or_else(|| "SFTP not initialized".to_string())?
        };

        sftp.rename(&source, &destination)
            .await
            .map_err(|e| e.to_string())?;
        Ok(())
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
    pub otp: Option<String>,
}

#[derive(Deserialize)]
pub struct DisconnectRequest {
    pub id: String,
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
        otp: req.otp.filter(|s| !s.trim().is_empty()),
    };

    let st = state.read().await;
    match st.remote_manager.connect(config).await {
        Ok(_) => Json(serde_json::json!({ "success": true, "message": "Connected" })),
        Err(e) => Json(serde_json::json!({ "success": false, "message": e })),
    }
}

pub async fn remote_disconnect(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<DisconnectRequest>,
) -> impl IntoResponse {
    let st = state.read().await;
    match st.remote_manager.disconnect(&req.id).await {
        Ok(_) => Json(serde_json::json!({ "success": true })),
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
        .execute_command_with_status(&req.id, req.command)
        .await
    {
        Ok((output, exit_code)) => Json(serde_json::json!({
            "output": output,
            "exit_code": exit_code,
            "success": exit_code == 0
        })),
        Err(e) => Json(serde_json::json!({
            "output": format!("Error: {}", e),
            "exit_code": 1,
            "success": false
        })),
    }
}

pub async fn remote_list_files(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<ListFilesRequest>,
) -> impl IntoResponse {
    let st = state.read().await;
    match st.remote_manager.list_files(&req.id, req.path).await {
        Ok(files) => Json(serde_json::json!({ "files": files })),
        Err(e) => Json(serde_json::json!({ "files": [], "error": e })),
    }
}

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
