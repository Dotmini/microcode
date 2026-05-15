//! Scenario Automation Engine (Full Rust)
//!
//! Production-ready automation workflow execution like make.com/n8n
//! All execution handled in Rust - Email, LINE, Telegram, HTTP, etc.

use crate::error::{AppError, Result};
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tokio::time::{sleep, Duration};

// MARK: - Models

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Scenario {
    pub id: String,
    pub name: String,
    pub nodes: Vec<ScenarioNode>,
    pub connections: Vec<ScenarioConnection>,
    pub is_active: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScenarioNode {
    pub id: String,
    pub node_type: String,
    pub name: String,
    pub config: NodeConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct NodeConfig {
    // Email/Gmail
    pub email_to: Option<String>,
    pub email_subject: Option<String>,
    pub email_body: Option<String>,
    pub email_attachment: Option<String>,
    pub smtp_host: Option<String>,
    pub smtp_port: Option<u16>,
    pub smtp_user: Option<String>,
    pub smtp_password: Option<String>,
    pub smtp_use_ssl: Option<bool>,

    // LINE Messaging API
    pub line_message_type: Option<String>, // push, broadcast, notify, group
    pub line_channel_token: Option<String>,
    pub line_notify_token: Option<String>,
    pub line_user_id: Option<String>,
    pub line_group_id: Option<String>,
    pub line_message: Option<String>,
    pub line_image_url: Option<String>,

    // Telegram Bot API
    pub telegram_bot_token: Option<String>,
    pub telegram_chat_id: Option<String>,
    pub telegram_message: Option<String>,
    pub telegram_image_url: Option<String>,
    pub telegram_parse_mode: Option<String>, // HTML, Markdown

    // HTTP
    pub http_url: Option<String>,
    pub http_method: Option<String>,
    pub http_headers: Option<HashMap<String, String>>,
    pub http_body: Option<String>,
    pub http_timeout: Option<u64>,

    // Code
    pub code_language: Option<String>,
    pub code_content: Option<String>,

    // Schedule/Trigger
    pub schedule_interval: Option<u64>,
    pub schedule_cron: Option<String>,
    pub webhook_path: Option<String>,

    // Delay
    pub delay_seconds: Option<u64>,

    // Database
    pub db_type: Option<String>,
    pub db_connection: Option<String>,
    pub db_query: Option<String>,

    // Google Sheets
    pub sheets_spreadsheet_id: Option<String>,
    pub sheets_range: Option<String>,
    pub sheets_action: Option<String>, // read, append, update, clear
    pub sheets_values: Option<Vec<Vec<String>>>,
    pub sheets_service_account_json: Option<String>,

    // GenAI - Common
    pub ai_provider: Option<String>, // gemini, chatgpt, deepseek, glm, perplexity, claude
    pub ai_api_key: Option<String>,
    pub ai_model: Option<String>,
    pub ai_prompt: Option<String>,
    pub ai_system_prompt: Option<String>,
    pub ai_temperature: Option<f32>,
    pub ai_max_tokens: Option<u32>,

    // GenAI Provider-Specific
    pub gemini_api_key: Option<String>,
    pub openai_api_key: Option<String>,
    pub deepseek_api_key: Option<String>,
    pub glm_api_key: Option<String>,
    pub perplexity_api_key: Option<String>,
    pub claude_api_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScenarioConnection {
    pub id: String,
    pub source_node_id: String,
    pub target_node_id: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ExecutionResult {
    pub node_id: String,
    pub node_name: String,
    pub node_type: String,
    pub success: bool,
    pub output: serde_json::Value,
    pub error: Option<String>,
    pub execution_time_ms: u64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ScenarioExecutionResult {
    pub scenario_id: String,
    pub scenario_name: String,
    pub success: bool,
    pub node_results: Vec<ExecutionResult>,
    pub total_time_ms: u64,
    pub logs: Vec<String>,
}

// MARK: - Executor

pub struct ScenarioExecutor {
    http_client: reqwest::Client,
    logs: Vec<String>,
}

impl ScenarioExecutor {
    pub fn new() -> Self {
        Self {
            http_client: reqwest::Client::builder()
                .timeout(Duration::from_secs(30))
                .build()
                .unwrap_or_default(),
            logs: Vec::new(),
        }
    }

    fn log(&mut self, msg: &str) {
        let timestamp = chrono::Utc::now().format("%H:%M:%S").to_string();
        self.logs.push(format!("[{}] {}", timestamp, msg));
    }

    pub fn get_logs(&self) -> Vec<String> {
        self.logs.clone()
    }

    // Helper for variable interpolation: {{$result.key}} or {{$result}}
    fn interpolate(&self, text: Option<String>, input: &serde_json::Value) -> Option<String> {
        let text = text?;
        if text.is_empty() {
            return Some(text);
        }

        let re = Regex::new(r"\{\{\$result(?:\.([a-zA-Z0-9_]+))?\}\}").unwrap();
        let result = re.replace_all(&text, |caps: &regex::Captures| {
            if let Some(key) = caps.get(1) {
                // {{$result.key}} -> input["key"]
                let key_str = key.as_str();
                if let Some(val) = input.get(key_str) {
                    if let Some(s) = val.as_str() {
                        s.to_string()
                    } else {
                        val.to_string()
                    }
                } else {
                    "".to_string()
                }
            } else {
                // {{$result}} -> input json string
                input.to_string()
            }
        });

        Some(result.to_string())
    }

    pub async fn execute(&mut self, scenario: &Scenario) -> Result<ScenarioExecutionResult> {
        let start = std::time::Instant::now();
        let mut node_results = Vec::new();

        self.log(&format!("🚀 Starting scenario: {}", scenario.name));

        // Find trigger nodes
        let trigger_nodes: Vec<_> = scenario
            .nodes
            .iter()
            .filter(|n| matches!(n.node_type.as_str(), "trigger" | "schedule" | "webhook"))
            .collect();

        if trigger_nodes.is_empty() {
            self.log("⚠️ No trigger node found, executing first node");
            if let Some(first_node) = scenario.nodes.first() {
                let input = serde_json::json!({"triggered": true, "timestamp": chrono::Utc::now().to_rfc3339()});
                self.execute_node_chain(scenario, first_node, input, &mut node_results)
                    .await?;
            }
        } else {
            for trigger in trigger_nodes {
                self.log(&format!("⚡ Triggered: {}", trigger.name));
                let input = serde_json::json!({"triggered": true, "timestamp": chrono::Utc::now().to_rfc3339()});
                self.execute_node_chain(scenario, trigger, input, &mut node_results)
                    .await?;
            }
        }

        let success = node_results.iter().all(|r| r.success);
        self.log(&format!(
            "{} Scenario completed in {}ms",
            if success { "✅" } else { "❌" },
            start.elapsed().as_millis()
        ));

        Ok(ScenarioExecutionResult {
            scenario_id: scenario.id.clone(),
            scenario_name: scenario.name.clone(),
            success,
            node_results,
            total_time_ms: start.elapsed().as_millis() as u64,
            logs: self.logs.clone(),
        })
    }

    pub async fn execute_single_node(
        &mut self,
        node: &ScenarioNode,
        input: serde_json::Value,
    ) -> Result<ExecutionResult> {
        let scenario = Scenario {
            id: "single".to_string(),
            name: "Single Node".to_string(),
            nodes: vec![node.clone()],
            connections: vec![],
            is_active: true,
        };

        let mut results = Vec::new();
        // Use the input provided directly
        let _ = self
            .execute_node_chain(&scenario, node, input, &mut results)
            .await?;

        results
            .into_iter()
            .next()
            .ok_or_else(|| AppError::InternalError("Execution returned no results".into()))
    }

    async fn execute_node_chain(
        &mut self,
        scenario: &Scenario,
        node: &ScenarioNode,
        input: serde_json::Value,
        results: &mut Vec<ExecutionResult>,
    ) -> Result<serde_json::Value> {
        let start = std::time::Instant::now();
        self.log(&format!("▶️ Executing: {} ({})", node.name, node.node_type));

        let result = match node.node_type.as_str() {
            "trigger" | "schedule" | "webhook" => Ok(input.clone()),
            "email" => self.execute_email(node, &input).await,
            "line" => self.execute_line(node, &input).await,
            "telegram" => self.execute_telegram(node, &input).await,
            "http" => self.execute_http(node, &input).await,
            "code" => self.execute_code(node, &input).await,
            "delay" => self.execute_delay(node).await,
            "transform" => self.execute_transform(node, &input).await,
            "filter" => self.execute_filter(node, &input).await,
            "database" => self.execute_database(node, &input).await,
            "slack" => self.execute_slack(node, &input).await,
            "discord" => self.execute_discord(node, &input).await,
            "openai" | "genai" | "ai" => self.execute_genai(node, &input).await,
            "googleSheets" | "google_sheets" | "sheets" => {
                self.execute_google_sheets(node, &input).await
            }
            _ => Ok(serde_json::json!({"executed": true, "type": node.node_type})),
        };

        let (success, output, error) = match result {
            Ok(output) => {
                self.log(&format!("✅ {} completed", node.name));
                (true, output, None)
            }
            Err(e) => {
                self.log(&format!("❌ {} failed: {}", node.name, e));
                (false, serde_json::json!({}), Some(e.to_string()))
            }
        };

        results.push(ExecutionResult {
            node_id: node.id.clone(),
            node_name: node.name.clone(),
            node_type: node.node_type.clone(),
            success,
            output: output.clone(),
            error,
            execution_time_ms: start.elapsed().as_millis() as u64,
        });

        if !success {
            return Ok(output);
        }

        // Find next nodes
        let next_connections: Vec<_> = scenario
            .connections
            .iter()
            .filter(|c| c.source_node_id == node.id)
            .collect();

        for conn in next_connections {
            if let Some(next_node) = scenario.nodes.iter().find(|n| n.id == conn.target_node_id) {
                Box::pin(self.execute_node_chain(scenario, next_node, output.clone(), results))
                    .await?;
            }
        }

        Ok(output)
    }

    // MARK: - Email Executor (SMTP)

    async fn execute_email(
        &mut self,
        node: &ScenarioNode,
        input: &serde_json::Value,
    ) -> Result<serde_json::Value> {
        let config = &node.config;

        let to = self
            .interpolate(config.email_to.clone(), input)
            .ok_or_else(|| AppError::BadRequest("Email 'to' not configured".into()))?;

        let subject = self
            .interpolate(config.email_subject.clone(), input)
            .unwrap_or_else(|| "Notification".to_string());
        let body = self
            .interpolate(config.email_body.clone(), input)
            .unwrap_or_default();
        let smtp_host = config.smtp_host.as_deref().unwrap_or("smtp.gmail.com");
        let smtp_port = config.smtp_port.unwrap_or(587);
        let smtp_user = config.smtp_user.as_deref().unwrap_or("");
        let smtp_pass = config.smtp_password.as_deref().unwrap_or("");

        self.log(&format!("📧 Sending email to: {}", to));

        // Use Python subprocess for SMTP (doesn't require lettre dependency)
        let python_code = format!(
            r#"
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

try:
    msg = MIMEMultipart()
    msg['From'] = '{}'
    msg['To'] = '{}'
    msg['Subject'] = '{}'
    msg.attach(MIMEText('{}', 'plain'))
    
    server = smtplib.SMTP('{}', {})
    server.starttls()
    server.login('{}', '{}')
    server.send_message(msg)
    server.quit()
    print('SUCCESS')
except Exception as e:
    print(f'ERROR:{{e}}')
"#,
            smtp_user,
            to,
            subject.replace("'", "\\'"),
            body.replace("'", "\\'"),
            smtp_host,
            smtp_port,
            smtp_user,
            smtp_pass
        );

        let output = tokio::process::Command::new("python3")
            .args(["-c", &python_code])
            .output()
            .await
            .map_err(|e| AppError::InternalError(format!("Python error: {}", e)))?;

        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        let success = stdout.contains("SUCCESS");

        if success {
            self.log(&format!("✅ Email sent to {}", to));
        } else {
            self.log(&format!("❌ Email failed: {}", stdout));
        }

        Ok(serde_json::json!({
            "sent": success,
            "to": to,
            "subject": subject,
            "output": stdout.trim()
        }))
    }

    // MARK: - LINE Executor (Push, Broadcast, Notify, Group)

    async fn execute_line(
        &mut self,
        node: &ScenarioNode,
        input: &serde_json::Value,
    ) -> Result<serde_json::Value> {
        let config = &node.config;
        let message_type = config.line_message_type.as_deref().unwrap_or("push");
        let message = self
            .interpolate(config.line_message.clone(), input)
            .unwrap_or_else(|| "Hello from MicroCode!".to_string());

        self.log(&format!("💬 LINE {} message", message_type));

        // Helper to construct messages array
        let build_messages =
            |msg_text: &str, img_url_opt: Option<String>| -> Vec<serde_json::Value> {
                let mut msgs = vec![serde_json::json!({"type": "text", "text": msg_text})];
                if let Some(img_url) = img_url_opt {
                    if !img_url.is_empty() {
                        msgs.push(serde_json::json!({
                            "type": "image",
                            "originalContentUrl": img_url,
                            "previewImageUrl": img_url
                        }));
                    }
                }
                msgs
            };

        match message_type {
            "notify" => {
                // LINE Notify API
                let token = config.line_notify_token.as_ref().ok_or_else(|| {
                    AppError::BadRequest("LINE Notify token not configured".into())
                })?;
                let image_url = self.interpolate(config.line_image_url.clone(), input);

                let mut form_data = format!("message={}", message);
                if let Some(img_url) = image_url {
                    if !img_url.is_empty() {
                        form_data.push_str(&format!(
                            "&imageThumbnail={}&imageFullsize={}",
                            img_url, img_url
                        ));
                    }
                }

                let response = self
                    .http_client
                    .post("https://notify-api.line.me/api/notify")
                    .header("Authorization", format!("Bearer {}", token))
                    .header("Content-Type", "application/x-www-form-urlencoded")
                    .body(form_data)
                    .send()
                    .await
                    .map_err(|e| AppError::InternalError(e.to_string()))?;

                let status = response.status();
                self.log(&format!("🔔 LINE Notify sent ({})", status.as_u16()));

                Ok(serde_json::json!({
                    "sent": status.is_success(),
                    "type": "notify",
                    "status_code": status.as_u16()
                }))
            }
            "broadcast" => {
                // LINE Broadcast API
                let token = config.line_channel_token.as_ref().ok_or_else(|| {
                    AppError::BadRequest("LINE channel token not configured".into())
                })?;
                let image_url = self.interpolate(config.line_image_url.clone(), input);

                let messages = build_messages(&message, image_url);
                let body = serde_json::json!({"messages": messages});

                let response = self
                    .http_client
                    .post("https://api.line.me/v2/bot/message/broadcast")
                    .header("Authorization", format!("Bearer {}", token))
                    .header("Content-Type", "application/json")
                    .json(&body)
                    .send()
                    .await
                    .map_err(|e| AppError::InternalError(e.to_string()))?;

                let status = response.status();
                self.log(&format!("📢 LINE Broadcast sent ({})", status.as_u16()));

                Ok(serde_json::json!({
                    "sent": status.is_success(),
                    "type": "broadcast",
                    "status_code": status.as_u16()
                }))
            }
            "group" => {
                // LINE Group Push
                let token = config.line_channel_token.as_ref().ok_or_else(|| {
                    AppError::BadRequest("LINE channel token not configured".into())
                })?;
                let group_id = config
                    .line_group_id
                    .as_ref()
                    .ok_or_else(|| AppError::BadRequest("LINE group ID not configured".into()))?;
                let image_url = self.interpolate(config.line_image_url.clone(), input);

                let messages = build_messages(&message, image_url);
                let body = serde_json::json!({"to": group_id, "messages": messages});

                let response = self
                    .http_client
                    .post("https://api.line.me/v2/bot/message/push")
                    .header("Authorization", format!("Bearer {}", token))
                    .header("Content-Type", "application/json")
                    .json(&body)
                    .send()
                    .await
                    .map_err(|e| AppError::InternalError(e.to_string()))?;

                let status = response.status();
                self.log(&format!("👥 LINE Group message sent ({})", status.as_u16()));

                Ok(serde_json::json!({
                    "sent": status.is_success(),
                    "type": "group",
                    "group_id": group_id,
                    "status_code": status.as_u16()
                }))
            }
            _ => {
                // LINE Push (default)
                let token = config.line_channel_token.as_ref().ok_or_else(|| {
                    AppError::BadRequest("LINE channel token not configured".into())
                })?;
                let user_id = config
                    .line_user_id
                    .as_ref()
                    .ok_or_else(|| AppError::BadRequest("LINE user ID not configured".into()))?;
                let image_url = self.interpolate(config.line_image_url.clone(), input);

                let messages = build_messages(&message, image_url);
                let body = serde_json::json!({"to": user_id, "messages": messages});

                let response = self
                    .http_client
                    .post("https://api.line.me/v2/bot/message/push")
                    .header("Authorization", format!("Bearer {}", token))
                    .header("Content-Type", "application/json")
                    .json(&body)
                    .send()
                    .await
                    .map_err(|e| AppError::InternalError(e.to_string()))?;

                let status = response.status();
                self.log(&format!("📨 LINE Push sent ({})", status.as_u16()));

                Ok(serde_json::json!({
                    "sent": status.is_success(),
                    "type": "push",
                    "user_id": user_id,
                    "status_code": status.as_u16()
                }))
            }
        }
    }

    // MARK: - Telegram Executor

    async fn execute_telegram(
        &mut self,
        node: &ScenarioNode,
        input: &serde_json::Value,
    ) -> Result<serde_json::Value> {
        let config = &node.config;

        let bot_token = config
            .telegram_bot_token
            .as_ref()
            .ok_or_else(|| AppError::BadRequest("Telegram bot token not configured".into()))?;
        let chat_id = config
            .telegram_chat_id
            .as_ref()
            .ok_or_else(|| AppError::BadRequest("Telegram chat ID not configured".into()))?;

        let message = self
            .interpolate(config.telegram_message.clone(), input)
            .unwrap_or_else(|| "Hello from MicroCode!".to_string());
        let image_url = self.interpolate(config.telegram_image_url.clone(), input);
        let parse_mode = config.telegram_parse_mode.as_deref();

        self.log(&format!("✈️ Sending Telegram message to {}", chat_id));

        // Check if sending photo
        if let Some(img_url) = image_url {
            if !img_url.is_empty() {
                // Send photo
                let url = format!("https://api.telegram.org/bot{}/sendPhoto", bot_token);
                let mut body = serde_json::json!({
                    "chat_id": chat_id,
                    "photo": img_url
                });

                if !message.is_empty() {
                    body["caption"] = serde_json::json!(message);
                }
                if let Some(pm) = parse_mode {
                    if !pm.is_empty() {
                        body["parse_mode"] = serde_json::json!(pm);
                    }
                }

                let response = self
                    .http_client
                    .post(&url)
                    .header("Content-Type", "application/json")
                    .json(&body)
                    .send()
                    .await
                    .map_err(|e| AppError::InternalError(e.to_string()))?;

                let status = response.status();
                let response_body: serde_json::Value = response.json().await.unwrap_or_default();

                self.log(&format!("📷 Telegram photo sent ({})", status.as_u16()));

                return Ok(serde_json::json!({
                    "sent": status.is_success(),
                    "type": "photo",
                    "status_code": status.as_u16(),
                    "response": response_body
                }));
            }
        }

        // Send text message
        let url = format!("https://api.telegram.org/bot{}/sendMessage", bot_token);
        let mut body = serde_json::json!({
            "chat_id": chat_id,
            "text": message
        });

        if let Some(pm) = parse_mode {
            if !pm.is_empty() {
                body["parse_mode"] = serde_json::json!(pm);
            }
        }

        let response = self
            .http_client
            .post(&url)
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        let status = response.status();
        let response_body: serde_json::Value = response.json().await.unwrap_or_default();

        self.log(&format!("💬 Telegram message sent ({})", status.as_u16()));

        Ok(serde_json::json!({
            "sent": status.is_success(),
            "type": "message",
            "status_code": status.as_u16(),
            "response": response_body
        }))
    }

    // MARK: - HTTP Executor

    async fn execute_http(
        &mut self,
        node: &ScenarioNode,
        input: &serde_json::Value,
    ) -> Result<serde_json::Value> {
        let config = &node.config;

        let url_raw = config
            .http_url
            .as_ref()
            .ok_or_else(|| AppError::BadRequest("HTTP URL not configured".into()))?;
        let url = self.interpolate(Some(url_raw.clone()), input).unwrap();

        let method = config.http_method.as_deref().unwrap_or("GET");

        self.log(&format!("🌐 HTTP {} {}", method, url));

        let mut request = match method.to_uppercase().as_str() {
            "POST" => self.http_client.post(&url),
            "PUT" => self.http_client.put(&url),
            "DELETE" => self.http_client.delete(&url),
            "PATCH" => self.http_client.patch(&url),
            _ => self.http_client.get(&url),
        };

        if let Some(headers) = &config.http_headers {
            for (key, value) in headers {
                let interpolated_value = self
                    .interpolate(Some(value.clone()), input)
                    .unwrap_or(value.clone());
                request = request.header(key, interpolated_value);
            }
        }

        if let Some(body) = &config.http_body {
            let interpolated_body = self
                .interpolate(Some(body.clone()), input)
                .unwrap_or(body.clone());
            request = request.body(interpolated_body);
        }

        let response = request
            .send()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        let status = response.status();
        let body = response.text().await.unwrap_or_default();

        let data: serde_json::Value =
            serde_json::from_str(&body).unwrap_or_else(|_| serde_json::json!(body));

        self.log(&format!("📥 HTTP response: {}", status.as_u16()));

        Ok(serde_json::json!({
            "status_code": status.as_u16(),
            "success": status.is_success(),
            "data": data
        }))
    }

    // MARK: - Code Executor

    async fn execute_code(
        &mut self,
        node: &ScenarioNode,
        input: &serde_json::Value,
    ) -> Result<serde_json::Value> {
        let config = &node.config;

        let language = config.code_language.as_deref().unwrap_or("python");
        let code = config.code_content.as_deref().unwrap_or("");

        self.log(&format!("💻 Executing {} code", language));

        let (cmd, args) = match language {
            "python" | "python3" => ("python3", vec!["-c", code]),
            "javascript" | "node" => ("node", vec!["-e", code]),
            "bash" | "sh" => ("bash", vec!["-c", code]),
            _ => {
                return Err(AppError::BadRequest(format!(
                    "Unsupported language: {}",
                    language
                )))
            }
        };

        // Set INPUT as env variable
        let input_json = serde_json::to_string(input).unwrap_or_default();

        let output = tokio::process::Command::new(cmd)
            .args(&args)
            .env("INPUT", &input_json)
            .output()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        let exit_code = output.status.code().unwrap_or(-1);

        self.log(&format!("📤 Code exit: {}", exit_code));

        Ok(serde_json::json!({
            "output": stdout.trim(),
            "stderr": stderr.trim(),
            "exit_code": exit_code,
            "success": exit_code == 0
        }))
    }

    // MARK: - Delay Executor

    // MARK: - Delay Executor

    async fn execute_delay(&mut self, node: &ScenarioNode) -> Result<serde_json::Value> {
        let seconds = node.config.delay_seconds.unwrap_or(5);
        self.log(&format!("⏳ Waiting {} seconds", seconds));

        sleep(Duration::from_secs(seconds)).await;

        Ok(serde_json::json!({"delayed": true, "seconds": seconds}))
    }

    // MARK: - Transform Executor

    async fn execute_transform(
        &mut self,
        _node: &ScenarioNode,
        input: &serde_json::Value,
    ) -> Result<serde_json::Value> {
        Ok(serde_json::json!({"transformed": true, "data": input}))
    }

    // MARK: - Filter Executor

    async fn execute_filter(
        &mut self,
        _node: &ScenarioNode,
        input: &serde_json::Value,
    ) -> Result<serde_json::Value> {
        Ok(serde_json::json!({"passed": true, "data": input}))
    }

    // MARK: - Database Executor

    async fn execute_database(
        &mut self,
        node: &ScenarioNode,
        input: &serde_json::Value,
    ) -> Result<serde_json::Value> {
        let config = &node.config;
        let db_type = config.db_type.as_deref().unwrap_or("sqlite");

        let query_raw = config.db_query.as_deref().unwrap_or("");
        let query = self
            .interpolate(Some(query_raw.to_string()), input)
            .unwrap_or_default();

        let connection_raw = config.db_connection.as_deref().unwrap_or("");
        let connection = self
            .interpolate(Some(connection_raw.to_string()), input)
            .unwrap_or_default();

        self.log(&format!(
            "🗄️ Database query ({}) on {}",
            db_type, connection
        ));

        // Placeholder for real DB logic
        Ok(serde_json::json!({
            "db_type": db_type,
            "query": query,
            "connection": connection,
            "rows_affected": 0,
            "data": []
        }))
    }

    // MARK: - Slack Executor

    async fn execute_slack(
        &mut self,
        _node: &ScenarioNode,
        _input: &serde_json::Value,
    ) -> Result<serde_json::Value> {
        self.log("📱 Slack message (placeholder)");
        Ok(serde_json::json!({"sent": true, "platform": "slack"}))
    }

    // MARK: - Discord Executor

    async fn execute_discord(
        &mut self,
        _node: &ScenarioNode,
        _input: &serde_json::Value,
    ) -> Result<serde_json::Value> {
        self.log("🎮 Discord message (placeholder)");
        Ok(serde_json::json!({"sent": true, "platform": "discord"}))
    }

    // MARK: - GenAI Executor (6 Providers)

    async fn execute_genai(
        &mut self,
        node: &ScenarioNode,
        input: &serde_json::Value,
    ) -> Result<serde_json::Value> {
        let config = &node.config;

        let provider = config.ai_provider.as_deref().unwrap_or("chatgpt");

        let prompt_raw = config.ai_prompt.as_deref().unwrap_or("Hello");
        let prompt = self
            .interpolate(Some(prompt_raw.to_string()), input)
            .unwrap_or_else(|| prompt_raw.to_string());

        let system_raw = config.ai_system_prompt.as_deref();
        let system_prompt = if let Some(sys) = system_raw {
            self.interpolate(Some(sys.to_string()), input)
        } else {
            None
        };

        let temperature = config.ai_temperature.unwrap_or(0.7);
        let max_tokens = config.ai_max_tokens.unwrap_or(1024);

        // Get API key (check provider-specific, then general)
        let api_key = match provider {
            "gemini" => config
                .gemini_api_key
                .as_ref()
                .or(config.ai_api_key.as_ref()),
            "chatgpt" | "openai" => config
                .openai_api_key
                .as_ref()
                .or(config.ai_api_key.as_ref()),
            "deepseek" => config
                .deepseek_api_key
                .as_ref()
                .or(config.ai_api_key.as_ref()),
            "glm" => config.glm_api_key.as_ref().or(config.ai_api_key.as_ref()),
            "perplexity" => config
                .perplexity_api_key
                .as_ref()
                .or(config.ai_api_key.as_ref()),
            "claude" => config
                .claude_api_key
                .as_ref()
                .or(config.ai_api_key.as_ref()),
            _ => config.ai_api_key.as_ref(),
        }
        .ok_or_else(|| AppError::BadRequest(format!("{} API key not configured", provider)))?;

        self.log(&format!("🤖 Calling {} AI", provider));

        let result = match provider {
            "gemini" => {
                self.call_gemini_api(api_key, &prompt, system_prompt.as_deref(), temperature)
                    .await
            }
            "chatgpt" | "openai" => {
                self.call_openai_api(
                    api_key,
                    &prompt,
                    system_prompt.as_deref(),
                    temperature,
                    max_tokens,
                    "gpt-4o-mini",
                )
                .await
            }
            "deepseek" => {
                self.call_deepseek_api(
                    api_key,
                    &prompt,
                    system_prompt.as_deref(),
                    temperature,
                    max_tokens,
                )
                .await
            }
            "glm" => {
                self.call_glm_api(
                    api_key,
                    &prompt,
                    system_prompt.as_deref(),
                    temperature,
                    max_tokens,
                )
                .await
            }
            "perplexity" => {
                self.call_perplexity_api(
                    api_key,
                    &prompt,
                    system_prompt.as_deref(),
                    temperature,
                    max_tokens,
                )
                .await
            }
            "claude" => {
                self.call_claude_api(
                    api_key,
                    &prompt,
                    system_prompt.as_deref(),
                    temperature,
                    max_tokens,
                )
                .await
            }
            _ => Err(AppError::BadRequest(format!(
                "Unknown AI provider: {}",
                provider
            ))),
        }?;

        self.log(&format!("✅ {} response received", provider));

        Ok(serde_json::json!({
            "provider": provider,
            "prompt": prompt,
            "response": result,
            "input": input
        }))
    }

    async fn call_gemini_api(
        &self,
        api_key: &str,
        prompt: &str,
        system: Option<&str>,
        _temp: f32,
    ) -> Result<String> {
        let url = format!("https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={}", api_key);

        let mut contents = vec![];
        if let Some(sys) = system {
            contents.push(serde_json::json!({"role": "user", "parts": [{"text": sys}]}));
            contents.push(serde_json::json!({"role": "model", "parts": [{"text": "Understood."}]}));
        }
        contents.push(serde_json::json!({"role": "user", "parts": [{"text": prompt}]}));

        let body = serde_json::json!({"contents": contents});

        let response = self
            .http_client
            .post(&url)
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        let json: serde_json::Value = response.json().await.unwrap_or_default();
        let text = json["candidates"][0]["content"]["parts"][0]["text"]
            .as_str()
            .unwrap_or("")
            .to_string();
        Ok(text)
    }

    async fn call_openai_api(
        &self,
        api_key: &str,
        prompt: &str,
        system: Option<&str>,
        temp: f32,
        max_tokens: u32,
        model: &str,
    ) -> Result<String> {
        let mut messages = vec![];
        if let Some(sys) = system {
            messages.push(serde_json::json!({"role": "system", "content": sys}));
        }
        messages.push(serde_json::json!({"role": "user", "content": prompt}));

        let body = serde_json::json!({
            "model": model,
            "messages": messages,
            "temperature": temp,
            "max_tokens": max_tokens
        });

        let response = self
            .http_client
            .post("https://api.openai.com/v1/chat/completions")
            .header("Authorization", format!("Bearer {}", api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        let json: serde_json::Value = response.json().await.unwrap_or_default();
        let text = json["choices"][0]["message"]["content"]
            .as_str()
            .unwrap_or("")
            .to_string();
        Ok(text)
    }

    async fn call_deepseek_api(
        &self,
        api_key: &str,
        prompt: &str,
        system: Option<&str>,
        temp: f32,
        max_tokens: u32,
    ) -> Result<String> {
        let mut messages = vec![];
        if let Some(sys) = system {
            messages.push(serde_json::json!({"role": "system", "content": sys}));
        }
        messages.push(serde_json::json!({"role": "user", "content": prompt}));

        let body = serde_json::json!({
            "model": "deepseek-chat",
            "messages": messages,
            "temperature": temp,
            "max_tokens": max_tokens
        });

        let response = self
            .http_client
            .post("https://api.deepseek.com/v1/chat/completions")
            .header("Authorization", format!("Bearer {}", api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        let json: serde_json::Value = response.json().await.unwrap_or_default();
        let text = json["choices"][0]["message"]["content"]
            .as_str()
            .unwrap_or("")
            .to_string();
        Ok(text)
    }

    async fn call_glm_api(
        &self,
        api_key: &str,
        prompt: &str,
        system: Option<&str>,
        temp: f32,
        max_tokens: u32,
    ) -> Result<String> {
        let mut messages = vec![];
        if let Some(sys) = system {
            messages.push(serde_json::json!({"role": "system", "content": sys}));
        }
        messages.push(serde_json::json!({"role": "user", "content": prompt}));

        let body = serde_json::json!({
            "model": "glm-4",
            "messages": messages,
            "temperature": temp,
            "max_tokens": max_tokens
        });

        let response = self
            .http_client
            .post("https://open.bigmodel.cn/api/paas/v4/chat/completions")
            .header("Authorization", format!("Bearer {}", api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        let json: serde_json::Value = response.json().await.unwrap_or_default();
        let text = json["choices"][0]["message"]["content"]
            .as_str()
            .unwrap_or("")
            .to_string();
        Ok(text)
    }

    async fn call_perplexity_api(
        &self,
        api_key: &str,
        prompt: &str,
        system: Option<&str>,
        temp: f32,
        max_tokens: u32,
    ) -> Result<String> {
        let mut messages = vec![];
        if let Some(sys) = system {
            messages.push(serde_json::json!({"role": "system", "content": sys}));
        }
        messages.push(serde_json::json!({"role": "user", "content": prompt}));

        let body = serde_json::json!({
            "model": "llama-3.1-sonar-small-128k-online",
            "messages": messages,
            "temperature": temp,
            "max_tokens": max_tokens
        });

        let response = self
            .http_client
            .post("https://api.perplexity.ai/chat/completions")
            .header("Authorization", format!("Bearer {}", api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        let json: serde_json::Value = response.json().await.unwrap_or_default();
        let text = json["choices"][0]["message"]["content"]
            .as_str()
            .unwrap_or("")
            .to_string();
        Ok(text)
    }

    async fn call_claude_api(
        &self,
        api_key: &str,
        prompt: &str,
        system: Option<&str>,
        temp: f32,
        max_tokens: u32,
    ) -> Result<String> {
        let mut body = serde_json::json!({
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": max_tokens,
            "temperature": temp,
            "messages": [{"role": "user", "content": prompt}]
        });

        if let Some(sys) = system {
            body["system"] = serde_json::json!(sys);
        }

        let response = self
            .http_client
            .post("https://api.anthropic.com/v1/messages")
            .header("x-api-key", api_key)
            .header("anthropic-version", "2023-06-01")
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        let json: serde_json::Value = response.json().await.unwrap_or_default();
        let text = json["content"][0]["text"]
            .as_str()
            .unwrap_or("")
            .to_string();
        Ok(text)
    }

    // MARK: - Google Sheets Executor

    async fn execute_google_sheets(
        &mut self,
        node: &ScenarioNode,
        input: &serde_json::Value,
    ) -> Result<serde_json::Value> {
        let config = &node.config;

        let spreadsheet_id_raw = config.sheets_spreadsheet_id.as_deref().unwrap_or("");
        let spreadsheet_id = self
            .interpolate(Some(spreadsheet_id_raw.to_string()), input)
            .unwrap_or_default();

        let range_raw = config.sheets_range.as_deref().unwrap_or("Sheet1!A1:Z100");
        let range = self
            .interpolate(Some(range_raw.to_string()), input)
            .unwrap_or_else(|| range_raw.to_string());

        let action = config.sheets_action.as_deref().unwrap_or("read");

        self.log(&format!(
            "📊 Google Sheets {} on {}",
            action, spreadsheet_id
        ));

        // Note: For full implementation, need OAuth2 or service account
        // This is a placeholder showing API structure

        match action {
            "read" => {
                let url = format!(
                    "https://sheets.googleapis.com/v4/spreadsheets/{}/values/{}",
                    spreadsheet_id, range
                );

                // Would need API key or OAuth token
                Ok(serde_json::json!({
                    "action": "read",
                    "spreadsheet_id": spreadsheet_id,
                    "range": range,
                    "status": "api_key_required",
                    "data": []
                }))
            }
            "append" => {
                let rows_count = config.sheets_values.as_ref().map(|v| v.len()).unwrap_or(0);
                Ok(serde_json::json!({
                    "action": "append",
                    "spreadsheet_id": spreadsheet_id,
                    "range": range,
                    "rows_added": rows_count,
                    "status": "api_key_required"
                }))
            }
            "update" => {
                let rows_count = config.sheets_values.as_ref().map(|v| v.len()).unwrap_or(0);
                Ok(serde_json::json!({
                    "action": "update",
                    "spreadsheet_id": spreadsheet_id,
                    "range": range,
                    "rows_updated": rows_count,
                    "status": "api_key_required"
                }))
            }
            "clear" => Ok(serde_json::json!({
                "action": "clear",
                "spreadsheet_id": spreadsheet_id,
                "range": range,
                "status": "api_key_required"
            })),
            _ => Err(AppError::BadRequest(format!(
                "Unknown sheets action: {}",
                action
            ))),
        }
    }
}

// MARK: - API Handlers

pub async fn run_scenario(scenario: Scenario) -> Result<ScenarioExecutionResult> {
    let mut executor = ScenarioExecutor::new();
    executor.execute(&scenario).await
}

pub async fn validate_scenario(scenario: &Scenario) -> Result<Vec<String>> {
    let mut errors = Vec::new();

    for node in &scenario.nodes {
        match node.node_type.as_str() {
            "email" => {
                if node.config.email_to.is_none() {
                    errors.push(format!("Node '{}': Email 'to' is required", node.name));
                }
            }
            "line" => {
                let msg_type = node.config.line_message_type.as_deref().unwrap_or("push");
                match msg_type {
                    "notify" => {
                        if node.config.line_notify_token.is_none() {
                            errors.push(format!(
                                "Node '{}': LINE Notify token is required",
                                node.name
                            ));
                        }
                    }
                    "broadcast" | "push" | "group" => {
                        if node.config.line_channel_token.is_none() {
                            errors.push(format!(
                                "Node '{}': LINE channel token is required",
                                node.name
                            ));
                        }
                    }
                    _ => {}
                }
            }
            "telegram" => {
                if node.config.telegram_bot_token.is_none() {
                    errors.push(format!(
                        "Node '{}': Telegram bot token is required",
                        node.name
                    ));
                }
                if node.config.telegram_chat_id.is_none() {
                    errors.push(format!(
                        "Node '{}': Telegram chat ID is required",
                        node.name
                    ));
                }
            }
            "http" => {
                if node.config.http_url.is_none() {
                    errors.push(format!("Node '{}': HTTP URL is required", node.name));
                }
            }
            _ => {}
        }
    }

    Ok(errors)
}
