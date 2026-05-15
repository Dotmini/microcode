//! Network Module - OAuth, Auth, and Auto-Update
//!
//! Handles Gmail OAuth, scenario auth providers, and app auto-update
//! from spuhr.tech/api/v1/idx/autoupdate

use crate::error::{AppError, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Simple URL encoding function
fn url_encode(s: &str) -> String {
    let mut result = String::new();
    for c in s.chars() {
        match c {
            'A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '_' | '.' | '~' => result.push(c),
            ' ' => result.push_str("%20"),
            _ => {
                for byte in c.to_string().as_bytes() {
                    result.push_str(&format!("%{:02X}", byte));
                }
            }
        }
    }
    result
}

// MARK: - OAuth Models

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthConfig {
    pub provider: String,
    pub client_id: String,
    pub client_secret: String,
    pub redirect_uri: String,
    pub scopes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthToken {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub token_type: String,
    pub expires_in: Option<u64>,
    pub expires_at: Option<i64>,
    pub scope: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthProvider {
    pub name: String,
    pub auth_url: String,
    pub token_url: String,
    pub userinfo_url: Option<String>,
    pub scopes: Vec<String>,
}

// MARK: - OAuth Manager

pub struct OAuthManager {
    http_client: reqwest::Client,
    providers: HashMap<String, OAuthProvider>,
}

impl OAuthManager {
    pub fn new() -> Self {
        let mut providers = HashMap::new();

        // Gmail / Google OAuth
        providers.insert(
            "google".to_string(),
            OAuthProvider {
                name: "Google".to_string(),
                auth_url: "https://accounts.google.com/o/oauth2/v2/auth".to_string(),
                token_url: "https://oauth2.googleapis.com/token".to_string(),
                userinfo_url: Some("https://www.googleapis.com/oauth2/v2/userinfo".to_string()),
                scopes: vec![
                    "https://www.googleapis.com/auth/gmail.send".to_string(),
                    "https://www.googleapis.com/auth/gmail.readonly".to_string(),
                    "https://mail.google.com/".to_string(),
                ],
            },
        );

        // Slack OAuth
        providers.insert(
            "slack".to_string(),
            OAuthProvider {
                name: "Slack".to_string(),
                auth_url: "https://slack.com/oauth/v2/authorize".to_string(),
                token_url: "https://slack.com/api/oauth.v2.access".to_string(),
                userinfo_url: None,
                scopes: vec!["chat:write".to_string(), "channels:read".to_string()],
            },
        );

        // Discord OAuth
        providers.insert(
            "discord".to_string(),
            OAuthProvider {
                name: "Discord".to_string(),
                auth_url: "https://discord.com/api/oauth2/authorize".to_string(),
                token_url: "https://discord.com/api/oauth2/token".to_string(),
                userinfo_url: Some("https://discord.com/api/users/@me".to_string()),
                scopes: vec!["identify".to_string(), "guilds".to_string()],
            },
        );

        // Notion OAuth
        providers.insert(
            "notion".to_string(),
            OAuthProvider {
                name: "Notion".to_string(),
                auth_url: "https://api.notion.com/v1/oauth/authorize".to_string(),
                token_url: "https://api.notion.com/v1/oauth/token".to_string(),
                userinfo_url: None,
                scopes: vec![],
            },
        );

        // Airtable OAuth
        providers.insert(
            "airtable".to_string(),
            OAuthProvider {
                name: "Airtable".to_string(),
                auth_url: "https://airtable.com/oauth2/v1/authorize".to_string(),
                token_url: "https://airtable.com/oauth2/v1/token".to_string(),
                userinfo_url: None,
                scopes: vec![
                    "data.records:read".to_string(),
                    "data.records:write".to_string(),
                ],
            },
        );

        Self {
            http_client: reqwest::Client::new(),
            providers,
        }
    }

    /// Get OAuth authorization URL for a provider
    pub fn get_auth_url(
        &self,
        provider: &str,
        client_id: &str,
        redirect_uri: &str,
        state: &str,
    ) -> Result<String> {
        let provider_config = self
            .providers
            .get(provider)
            .ok_or_else(|| AppError::BadRequest(format!("Unknown OAuth provider: {}", provider)))?;

        let scopes = provider_config.scopes.join(" ");

        let url = format!(
            "{}?client_id={}&redirect_uri={}&response_type=code&scope={}&state={}&access_type=offline&prompt=consent",
            provider_config.auth_url,
            url_encode(client_id),
            url_encode(redirect_uri),
            url_encode(&scopes),
            url_encode(state)
        );

        Ok(url)
    }

    /// Exchange authorization code for access token
    pub async fn exchange_code(
        &self,
        provider: &str,
        code: &str,
        client_id: &str,
        client_secret: &str,
        redirect_uri: &str,
    ) -> Result<OAuthToken> {
        let provider_config = self
            .providers
            .get(provider)
            .ok_or_else(|| AppError::BadRequest(format!("Unknown OAuth provider: {}", provider)))?;

        let params = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("client_id", client_id),
            ("client_secret", client_secret),
            ("redirect_uri", redirect_uri),
        ];

        let response = self
            .http_client
            .post(&provider_config.token_url)
            .form(&params)
            .send()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::InternalError(format!(
                "OAuth error: {}",
                error_text
            )));
        }

        let token: OAuthToken = response
            .json()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        Ok(token)
    }

    /// Refresh access token
    pub async fn refresh_token(
        &self,
        provider: &str,
        refresh_token: &str,
        client_id: &str,
        client_secret: &str,
    ) -> Result<OAuthToken> {
        let provider_config = self
            .providers
            .get(provider)
            .ok_or_else(|| AppError::BadRequest(format!("Unknown OAuth provider: {}", provider)))?;

        let params = [
            ("grant_type", "refresh_token"),
            ("refresh_token", refresh_token),
            ("client_id", client_id),
            ("client_secret", client_secret),
        ];

        let response = self
            .http_client
            .post(&provider_config.token_url)
            .form(&params)
            .send()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::InternalError(format!(
                "OAuth refresh error: {}",
                error_text
            )));
        }

        let token: OAuthToken = response
            .json()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        Ok(token)
    }
}

// MARK: - Gmail API

pub struct GmailClient {
    http_client: reqwest::Client,
    access_token: String,
}

impl GmailClient {
    pub fn new(access_token: String) -> Self {
        Self {
            http_client: reqwest::Client::new(),
            access_token,
        }
    }

    /// Send email via Gmail API
    pub async fn send_email(&self, to: &str, subject: &str, body: &str) -> Result<()> {
        let email_content = format!(
            "To: {}\r\nSubject: {}\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n{}",
            to, subject, body
        );

        let encoded = base64::Engine::encode(
            &base64::engine::general_purpose::URL_SAFE,
            email_content.as_bytes(),
        );

        let payload = serde_json::json!({
            "raw": encoded
        });

        let response = self
            .http_client
            .post("https://gmail.googleapis.com/gmail/v1/users/me/messages/send")
            .header("Authorization", format!("Bearer {}", self.access_token))
            .header("Content-Type", "application/json")
            .json(&payload)
            .send()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::InternalError(format!(
                "Gmail send error: {}",
                error_text
            )));
        }

        Ok(())
    }
}

// MARK: - Auto-Update

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateInfo {
    pub version: String,
    pub build_number: u32,
    pub release_notes: String,
    pub download_url: String,
    pub checksum: String,
    pub mandatory: bool,
    pub release_date: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateCheckResponse {
    pub update_available: bool,
    pub current_version: String,
    pub latest_version: String,
    pub update: Option<UpdateInfo>,
}

pub struct AutoUpdater {
    http_client: reqwest::Client,
    update_url: String,
    current_version: String,
    current_build: u32,
}

impl AutoUpdater {
    pub fn new(current_version: &str, current_build: u32) -> Self {
        Self {
            http_client: reqwest::Client::new(),
            update_url: std::env::var("AUTOUPDATE_URL").unwrap_or_else(|_| {
                "https://api.github.com/repos/Dotmini/microcode/releases/latest".to_string()
            }),
            current_version: current_version.to_string(),
            current_build,
        }
    }

    /// Check for updates
    pub async fn check_for_updates(&self) -> Result<UpdateCheckResponse> {
        let response = self
            .http_client
            .get(&self.update_url)
            .query(&[
                ("version", self.current_version.as_str()),
                ("build", &self.current_build.to_string()),
                ("platform", "macos"),
                ("arch", std::env::consts::ARCH),
            ])
            .send()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        if !response.status().is_success() {
            return Err(AppError::InternalError(
                "Failed to check for updates".into(),
            ));
        }

        let update_response: UpdateCheckResponse = response
            .json()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        Ok(update_response)
    }

    /// Download update
    pub async fn download_update(&self, update: &UpdateInfo) -> Result<Vec<u8>> {
        let response = self
            .http_client
            .get(&update.download_url)
            .send()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        if !response.status().is_success() {
            return Err(AppError::InternalError("Failed to download update".into()));
        }

        let bytes = response
            .bytes()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        // Checksum verification (skip for now - would need sha256 crate)
        // TODO: Implement checksum verification with a proper SHA256 library

        Ok(bytes.to_vec())
    }

    /// Install update (macOS)
    pub async fn install_update(&self, data: &[u8], app_path: &str) -> Result<()> {
        use std::io::Write;
        use std::process::Command;

        // Save to temp file
        let temp_path = "/tmp/microcode_update.zip";
        let mut file =
            std::fs::File::create(temp_path).map_err(|e| AppError::InternalError(e.to_string()))?;
        file.write_all(data)
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        // Unzip
        let extract_path = "/tmp/microcode_update";
        Command::new("unzip")
            .args(["-o", temp_path, "-d", extract_path])
            .output()
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        // Replace app
        let source = format!("{}/Project IDX.app", extract_path);
        Command::new("rm")
            .args(["-rf", app_path])
            .output()
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        Command::new("mv")
            .args([&source, app_path])
            .output()
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        // Cleanup
        std::fs::remove_file(temp_path).ok();
        std::fs::remove_dir_all(extract_path).ok();

        Ok(())
    }
}

// MARK: - SMTP Client

#[derive(Debug, Clone)]
pub struct SmtpConfig {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: String,
    pub use_tls: bool,
}

pub struct SmtpClient {
    config: SmtpConfig,
}

impl SmtpClient {
    pub fn new(config: SmtpConfig) -> Self {
        Self { config }
    }

    pub fn gmail(username: &str, app_password: &str) -> Self {
        Self::new(SmtpConfig {
            host: "smtp.gmail.com".to_string(),
            port: 587,
            username: username.to_string(),
            password: app_password.to_string(),
            use_tls: true,
        })
    }

    pub fn outlook(username: &str, password: &str) -> Self {
        Self::new(SmtpConfig {
            host: "smtp.office365.com".to_string(),
            port: 587,
            username: username.to_string(),
            password: password.to_string(),
            use_tls: true,
        })
    }

    /// Send email via SMTP (requires lettre crate)
    #[cfg(feature = "smtp")]
    pub fn send_email(&self, to: &str, subject: &str, body: &str) -> Result<()> {
        use lettre::transport::smtp::authentication::Credentials;
        use lettre::{Message, SmtpTransport, Transport};

        let email = Message::builder()
            .from(
                self.config
                    .username
                    .parse()
                    .map_err(|_| AppError::BadRequest("Invalid from address".into()))?,
            )
            .to(to
                .parse()
                .map_err(|_| AppError::BadRequest("Invalid to address".into()))?)
            .subject(subject)
            .body(body.to_string())
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        let creds = Credentials::new(self.config.username.clone(), self.config.password.clone());

        let mailer = SmtpTransport::relay(&self.config.host)
            .map_err(|e| AppError::InternalError(e.to_string()))?
            .credentials(creds)
            .port(self.config.port)
            .build();

        mailer
            .send(&email)
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        Ok(())
    }
}
// MARK: - HTTP Proxy

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProxyRequest {
    pub method: String,
    pub url: String,
    pub headers: HashMap<String, String>,
    pub body: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProxyResponse {
    pub status: u16,
    pub header_map: HashMap<String, String>, // Renamed from headers to avoid conflict/confusion
    pub body: String,
    pub duration_ms: u64,
}

pub async fn execute_request(req: ProxyRequest) -> Result<ProxyResponse> {
    let client = reqwest::Client::new();
    let method = reqwest::Method::from_bytes(req.method.as_bytes())
        .map_err(|e| AppError::BadRequest(format!("Invalid method: {}", e)))?;

    let mut request_builder = client.request(method, &req.url);

    for (k, v) in req.headers {
        request_builder = request_builder.header(k, v);
    }

    if let Some(body) = req.body {
        request_builder = request_builder.body(body);
    }

    let start = std::time::Instant::now();
    let response = request_builder
        .send()
        .await
        .map_err(|e| AppError::InternalError(format!("Request failed: {}", e)))?;
    let duration = start.elapsed().as_millis() as u64;

    let status = response.status().as_u16();
    let mut header_map = HashMap::new();
    for (k, v) in response.headers() {
        if let Ok(val) = v.to_str() {
            header_map.insert(k.to_string(), val.to_string());
        }
    }

    let body = response
        .text()
        .await
        .map_err(|e| AppError::InternalError(format!("Failed to read body: {}", e)))?;

    Ok(ProxyResponse {
        status,
        header_map,
        body,
        duration_ms: duration,
    })
}
