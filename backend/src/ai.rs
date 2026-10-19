//! AI operations module
//!
//! Provides AI-powered code refactoring, explanation, and completion
//! Supports multiple AI providers: Gemini, OpenAI, Claude

use crate::error::{AppError, Result};
use crate::models::{AIConfig, AIModel};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::env;

// ==========================================
// AI Provider Trait
// ==========================================

#[async_trait]
pub trait AIProvider: Send + Sync {
    async fn generate(&self, prompt: &str, config: &AIConfig) -> Result<String>;
    async fn generate_stream(
        &self,
        prompt: &str,
        config: &AIConfig,
    ) -> Result<futures::stream::BoxStream<'static, Result<String>>>;
    fn name(&self) -> &str;
    fn models(&self) -> Vec<AIModel>;
}

// ==========================================
// Gemini Provider
// ==========================================

pub struct GeminiProvider {
    client: reqwest::Client,
}

impl GeminiProvider {
    pub fn new() -> Self {
        Self {
            client: reqwest::Client::new(),
        }
    }
}

#[async_trait]
impl AIProvider for GeminiProvider {
    async fn generate(&self, prompt: &str, config: &AIConfig) -> Result<String> {
        let (url, auth_header) = if let Some(ref base) = config.proxy_base_url {
            if base.contains("aiplatform.googleapis.com") {
                let clean_model = config.model.strip_prefix("models/").unwrap_or(&config.model);
                let vertex_url = format!("{}/publishers/google/models/{}:generateContent", base.trim_end_matches('/'), clean_model);
                let bearer = if config.api_key.starts_with("Bearer ") {
                    config.api_key.clone()
                } else {
                    format!("Bearer {}", config.api_key)
                };
                (vertex_url, bearer)
            } else {
                let token = config.microrent_token.clone().unwrap_or_else(|| config.api_key.clone());
                (base.clone(), format!("Bearer {}", token))
            }
        } else if config.use_microrent_proxy
            || env::var("USE_DOTMINI_PROXY").unwrap_or_else(|_| "0".to_string()) == "1"
        {
            let proxy_url = env::var("DOTMINI_API_BASE_URL").map_err(|_| {
                AppError::AIProviderError("DOTMINI_API_BASE_URL not configured".to_string())
            })?;
            let token = config
                .microrent_token
                .clone()
                .or_else(|| env::var("DOTMINI_API_TOKEN").ok())
                .ok_or_else(|| {
                    AppError::AIProviderError("DOTMINI_API_TOKEN not found for Gateway".to_string())
                })?;
            (proxy_url, format!("Bearer {}", token))
        } else if let Ok(vertex_project) = env::var("VERTEX_PROJECT_ID") {
            let loc = env::var("VERTEX_LOCATION").unwrap_or_else(|_| "asia-southeast1".to_string());
            let clean_model = config.model.strip_prefix("models/").unwrap_or(&config.model);
            let host = if loc == "global" {
                "https://aiplatform.googleapis.com".to_string()
            } else {
                format!("https://{}-aiplatform.googleapis.com", loc)
            };
            let vertex_url = format!(
                "{}/v1/projects/{}/locations/{}/publishers/google/models/{}:generateContent",
                host, vertex_project, loc, clean_model
            );
            (vertex_url, format!("Bearer {}", config.api_key))
        } else {
            let api_key = if config.api_key.is_empty() {
                env::var("GEMINI_API_KEY").map_err(|_| {
                    AppError::AIProviderError("GEMINI_API_KEY not found".to_string())
                })?
            } else {
                config.api_key.clone()
            };
            let clean_model = config.model.strip_prefix("models/").unwrap_or(&config.model);
            let direct_url = format!(
                "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent?key={}",
                clean_model, api_key
            );
            (direct_url, String::new())
        };

        #[derive(Serialize)]
        struct GeminiRequest {
            contents: Vec<Content>,
            generation_config: GenerationConfig,
        }

        #[derive(Serialize)]
        struct Content {
            parts: Vec<Part>,
        }

        #[derive(Serialize)]
        struct Part {
            text: String,
        }

        #[derive(Serialize)]
        #[serde(rename_all = "camelCase")]
        struct GenerationConfig {
            temperature: f32,
            max_output_tokens: usize,
        }

        #[derive(Deserialize)]
        struct GeminiResponse {
            #[serde(default)]
            candidates: Vec<Candidate>,
        }

        #[derive(Deserialize)]
        struct Candidate {
            content: ResponseContent,
        }

        #[derive(Deserialize)]
        struct ResponseContent {
            #[serde(default)]
            parts: Vec<ResponsePart>,
        }

        #[derive(Deserialize)]
        struct ResponsePart {
            #[serde(default)]
            text: Option<String>,
            #[serde(default)]
            thought: Option<bool>,
        }

        let request = GeminiRequest {
            contents: vec![Content {
                parts: vec![Part {
                    text: prompt.to_string(),
                }],
            }],
            generation_config: GenerationConfig {
                temperature: config.temperature,
                max_output_tokens: config.max_tokens,
            },
        };

        let mut request_builder = self.client.post(&url).json(&request);

        if !auth_header.is_empty() {
            request_builder = request_builder
                .header("Authorization", &auth_header)
                .header("x-microrent-provider", "gemini")
                .header("x-microrent-model", &config.model)
                .header("x-microrent-stream", "false");
            if auth_header.contains("sk-dotmini-ent-") {
                request_builder = request_builder
                    .header("X-Dotmini-Enterprise", "true")
                    .header("X-Dotmini-ZDR", "true");
            }
        }

        let response = request_builder
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::AIRequestFailed(format!(
                "Gemini API error: {}",
                error_text
            )));
        }

        let result: GeminiResponse = response
            .json()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        let candidate = result
            .candidates
            .first()
            .ok_or_else(|| AppError::AIRequestFailed("No response from Gemini".to_string()))?;

        let mut combined = String::new();
        for part in &candidate.content.parts {
            if let Some(ref text) = part.text {
                if part.thought.unwrap_or(false) {
                    combined.push_str(&format!("<thought>{}</thought>\n", text));
                } else {
                    combined.push_str(text);
                }
            }
        }

        if combined.is_empty() {
            Err(AppError::AIRequestFailed("Empty response from Gemini".to_string()))
        } else {
            Ok(combined)
        }
    }

    async fn generate_stream(
        &self,
        prompt: &str,
        config: &AIConfig,
    ) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
        let (url, auth_header) = if config.use_microrent_proxy
            || env::var("USE_DOTMINI_PROXY").unwrap_or_else(|_| "0".to_string()) == "1"
        {
            let proxy_url = env::var("DOTMINI_API_BASE_URL").map_err(|_| {
                AppError::AIProviderError("DOTMINI_API_BASE_URL not configured".to_string())
            })?;
            let token = config
                .microrent_token
                .clone()
                .or_else(|| env::var("DOTMINI_API_TOKEN").ok())
                .ok_or_else(|| {
                    AppError::AIProviderError("DOTMINI_API_TOKEN not found for Gateway".to_string())
                })?;
            (proxy_url, format!("Bearer {}", token))
        } else {
            let api_key = if config.api_key.is_empty() {
                env::var("GEMINI_API_KEY").map_err(|_| {
                    AppError::AIProviderError("GEMINI_API_KEY not found".to_string())
                })?
            } else {
                config.api_key.clone()
            };
            let clean_model = config.model.strip_prefix("models/").unwrap_or(&config.model);
            let direct_url = format!(
                "https://generativelanguage.googleapis.com/v1beta/models/{}:streamGenerateContent?alt=sse&key={}",
                clean_model, api_key
            );
            (direct_url, String::new())
        };

        #[derive(Serialize)]
        struct GeminiRequest {
            contents: Vec<Content>,
            generation_config: GenerationConfig,
        }

        #[derive(Serialize)]
        struct Content {
            parts: Vec<Part>,
        }

        #[derive(Serialize)]
        struct Part {
            text: String,
        }

        #[derive(Serialize)]
        #[serde(rename_all = "camelCase")]
        struct GenerationConfig {
            temperature: f32,
            max_output_tokens: usize,
        }

        let request = GeminiRequest {
            contents: vec![Content {
                parts: vec![Part {
                    text: prompt.to_string(),
                }],
            }],
            generation_config: GenerationConfig {
                temperature: config.temperature,
                max_output_tokens: config.max_tokens,
            },
        };

        let mut request_builder = self.client.post(&url).json(&request);

        if !auth_header.is_empty() {
            request_builder = request_builder
                .header("Authorization", &auth_header)
                .header("x-microrent-provider", "gemini")
                .header("x-microrent-model", &config.model)
                .header("x-microrent-stream", "true");
        }

        let response = request_builder
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::AIRequestFailed(format!(
                "Gemini API error: {}",
                error_text
            )));
        }

        use eventsource_stream::Eventsource;
        use futures::StreamExt;

        let stream = response
            .bytes_stream()
            .eventsource()
            .map(|event| match event {
                Ok(event) => {
                    let trimmed = event.data.trim();
                    if trimmed.is_empty() || trimmed == "[DONE]" {
                        return Ok("".to_string());
                    }
                    let json: serde_json::Value = serde_json::from_str(trimmed)
                        .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

                    if let Some(candidates) = json.get("candidates") {
                        if let Some(candidate) = candidates.get(0) {
                            if let Some(content) = candidate.get("content") {
                                if let Some(parts) = content.get("parts") {
                                    let mut result = String::new();
                                    if let Some(parts_array) = parts.as_array() {
                                        for part in parts_array {
                                            if part.get("thought").and_then(|t| t.as_bool()).unwrap_or(false) {
                                                if let Some(text) = part.get("text").and_then(|t| t.as_str()) {
                                                    result.push_str(&format!("<thought>{}</thought>", text));
                                                }
                                            } else if let Some(text) = part.get("text").and_then(|t| t.as_str()) {
                                                result.push_str(text);
                                            }
                                        }
                                    }
                                    return Ok(result);
                                }
                            }
                        }
                    }
                    Ok("".to_string())
                }
                Err(e) => Err(AppError::AIRequestFailed(e.to_string())),
            })
            .boxed();

        Ok(stream)
    }

    fn name(&self) -> &str {
        "gemini"
    }

    fn models(&self) -> Vec<AIModel> {
        Vec::new()
    }
}

// ==========================================
// OpenAI Provider
// ==========================================

pub struct OpenAIProvider {
    client: reqwest::Client,
}

impl OpenAIProvider {
    pub fn new() -> Self {
        Self {
            client: reqwest::Client::new(),
        }
    }
}

#[async_trait]
impl AIProvider for OpenAIProvider {
    async fn generate(&self, prompt: &str, config: &AIConfig) -> Result<String> {
        let (url, auth_header) = if config.use_microrent_proxy
            || env::var("USE_DOTMINI_PROXY").unwrap_or_else(|_| "0".to_string()) == "1"
        {
            let proxy_url = cloud_chat_endpoint(config)?;
            let token = config
                .microrent_token
                .clone()
                .or_else(|| env::var("DOTMINI_API_TOKEN").ok())
                .ok_or_else(|| {
                    AppError::AIProviderError("DOTMINI_API_TOKEN not found for Gateway".to_string())
                })?;
            (proxy_url, format!("Bearer {}", token))
        } else {
            let api_key = if config.api_key.is_empty() {
                env::var("OPENAI_API_KEY").map_err(|_| {
                    AppError::AIProviderError("OPENAI_API_KEY not found".to_string())
                })?
            } else {
                config.api_key.clone()
            };
            (
                "https://api.openai.com/v1/chat/completions".to_string(),
                format!("Bearer {}", api_key),
            )
        };

        #[derive(Serialize)]
        struct OpenAIRequest {
            model: String,
            messages: Vec<Message>,
            temperature: f32,
            max_tokens: usize,
        }

        #[derive(Serialize)]
        struct Message {
            role: String,
            content: String,
        }

        #[derive(Deserialize)]
        struct OpenAIResponse {
            choices: Vec<Choice>,
        }

        #[derive(Deserialize)]
        struct Choice {
            message: ResponseMessage,
        }

        #[derive(Deserialize)]
        struct ResponseMessage {
            #[serde(default)]
            content: Option<String>,
            #[serde(default)]
            reasoning_content: Option<String>,
        }

        let request = OpenAIRequest {
            model: config.model.clone(),
            messages: vec![Message {
                role: "user".to_string(),
                content: prompt.to_string(),
            }],
            temperature: config.temperature,
            max_tokens: config.max_tokens,
        };

        let mut request_builder = self
            .client
            .post(url)
            .header("Authorization", auth_header)
            .header("Content-Type", "application/json")
            .json(&request);

        if config.use_microrent_proxy
            || env::var("USE_DOTMINI_PROXY").unwrap_or_else(|_| "0".to_string()) == "1"
        {
            request_builder = request_builder
                .header("x-microrent-provider", "openai")
                .header("x-microrent-model", &config.model)
                .header("x-microrent-stream", "false");
        }

        let response = request_builder
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::AIRequestFailed(format!(
                "OpenAI API error: {}",
                error_text
            )));
        }

        let result: OpenAIResponse = response
            .json()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        result
            .choices
            .first()
            .map(|c| {
                let mut out = String::new();
                if let Some(ref reasoning) = c.message.reasoning_content {
                    if !reasoning.is_empty() {
                        out.push_str(&format!("<thought>{}</thought>\n", reasoning));
                    }
                }
                if let Some(ref text) = c.message.content {
                    out.push_str(text);
                }
                out
            })
            .ok_or_else(|| AppError::AIRequestFailed("No response from OpenAI".to_string()))
    }

    async fn generate_stream(
        &self,
        prompt: &str,
        config: &AIConfig,
    ) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
        let (url, auth_header) = if config.use_microrent_proxy
            || env::var("USE_DOTMINI_PROXY").unwrap_or_else(|_| "0".to_string()) == "1"
        {
            let proxy_url = cloud_chat_endpoint(config)?;
            let token = config
                .microrent_token
                .clone()
                .or_else(|| env::var("DOTMINI_API_TOKEN").ok())
                .ok_or_else(|| {
                    AppError::AIProviderError("DOTMINI_API_TOKEN not found for Gateway".to_string())
                })?;
            (proxy_url, format!("Bearer {}", token))
        } else {
            let api_key = if config.api_key.is_empty() {
                env::var("OPENAI_API_KEY").map_err(|_| {
                    AppError::AIProviderError("OPENAI_API_KEY not found".to_string())
                })?
            } else {
                config.api_key.clone()
            };
            (
                "https://api.openai.com/v1/chat/completions".to_string(),
                format!("Bearer {}", api_key),
            )
        };

        #[derive(Serialize)]
        struct OpenAIRequest {
            model: String,
            messages: Vec<Message>,
            temperature: f32,
            max_tokens: usize,
            stream: bool,
        }

        #[derive(Serialize)]
        struct Message {
            role: String,
            content: String,
        }

        let request = OpenAIRequest {
            model: config.model.clone(),
            messages: vec![Message {
                role: "user".to_string(),
                content: prompt.to_string(),
            }],
            temperature: config.temperature,
            max_tokens: config.max_tokens,
            stream: true,
        };

        let mut request_builder = self
            .client
            .post(url)
            .header("Authorization", auth_header)
            .header("Content-Type", "application/json")
            .json(&request);

        if config.use_microrent_proxy
            || env::var("USE_DOTMINI_PROXY").unwrap_or_else(|_| "0".to_string()) == "1"
        {
            request_builder = request_builder
                .header("x-microrent-provider", "openai")
                .header("x-microrent-model", &config.model)
                .header("x-microrent-stream", "true");
        }

        let response = request_builder
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::AIRequestFailed(format!(
                "OpenAI API error: {}",
                error_text
            )));
        }

        use eventsource_stream::Eventsource;
        use futures::StreamExt;

        let stream = response
            .bytes_stream()
            .eventsource()
            .map(|event| match event {
                Ok(event) => {
                    let trimmed = event.data.trim();
                    if trimmed.is_empty() || trimmed == "[DONE]" {
                        return Ok("".to_string());
                    }
                    let json: serde_json::Value = serde_json::from_str(trimmed)
                        .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

                    let delta = &json["choices"][0]["delta"];
                    let content = delta["content"]
                        .as_str()
                        .unwrap_or("")
                        .to_string();
                    Ok(content)
                }
                Err(e) => Err(AppError::AIRequestFailed(e.to_string())),
            })
            .boxed();

        Ok(stream)
    }

    fn name(&self) -> &str {
        "openai"
    }

    fn models(&self) -> Vec<AIModel> {
        Vec::new()
    }
}

// ==========================================
// Claude Provider
// ==========================================

pub struct ClaudeProvider {
    client: reqwest::Client,
}

impl ClaudeProvider {
    pub fn new() -> Self {
        Self {
            client: reqwest::Client::new(),
        }
    }
}

#[async_trait]
impl AIProvider for ClaudeProvider {
    async fn generate(&self, prompt: &str, config: &AIConfig) -> Result<String> {
        let (url, auth_header) = if config.use_microrent_proxy
            || env::var("USE_DOTMINI_PROXY").unwrap_or_else(|_| "0".to_string()) == "1"
        {
            let proxy_url = env::var("DOTMINI_API_BASE_URL").map_err(|_| {
                AppError::AIProviderError("DOTMINI_API_BASE_URL not configured".to_string())
            })?;
            let token = config
                .microrent_token
                .clone()
                .or_else(|| env::var("DOTMINI_API_TOKEN").ok())
                .ok_or_else(|| {
                    AppError::AIProviderError("DOTMINI_API_TOKEN not found for Gateway".to_string())
                })?;
            (proxy_url, format!("Bearer {}", token))
        } else {
            let api_key = if config.api_key.is_empty() {
                env::var("ANTHROPIC_API_KEY").map_err(|_| {
                    AppError::AIProviderError("ANTHROPIC_API_KEY not found".to_string())
                })?
            } else {
                config.api_key.clone()
            };
            ("https://api.anthropic.com/v1/messages".to_string(), api_key)
        };

        #[derive(Serialize)]
        struct ClaudeRequest {
            model: String,
            messages: Vec<Message>,
            max_tokens: usize,
            temperature: f32,
        }

        #[derive(Serialize)]
        struct Message {
            role: String,
            content: String,
        }

        #[derive(Deserialize)]
        struct ClaudeResponse {
            #[serde(default)]
            content: Vec<ContentBlock>,
        }

        #[derive(Deserialize)]
        struct ContentBlock {
            #[serde(default)]
            text: Option<String>,
            #[serde(default)]
            thinking: Option<String>,
        }

        let request = ClaudeRequest {
            model: config.model.clone(),
            messages: vec![Message {
                role: "user".to_string(),
                content: prompt.to_string(),
            }],
            max_tokens: config.max_tokens,
            temperature: config.temperature,
        };

        let mut request_builder = self.client.post(url);

        if config.use_microrent_proxy
            || env::var("USE_DOTMINI_PROXY").unwrap_or_else(|_| "0".to_string()) == "1"
        {
            request_builder = request_builder
                .header("Authorization", auth_header)
                .header("x-microrent-provider", "anthropic")
                .header("x-microrent-model", &config.model)
                .header("x-microrent-stream", "false");
        } else {
            request_builder = request_builder
                .header("x-api-key", auth_header)
                .header("anthropic-version", "2023-06-01");
        }

        let response = request_builder
            .header("Content-Type", "application/json")
            .json(&request)
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::AIRequestFailed(format!(
                "Claude API error: {}",
                error_text
            )));
        }

        let result: ClaudeResponse = response
            .json()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        let mut combined = String::new();
        for block in &result.content {
            if let Some(ref thinking) = block.thinking {
                if !thinking.is_empty() {
                    combined.push_str(&format!("<thought>{}</thought>\n", thinking));
                }
            }
            if let Some(ref text) = block.text {
                combined.push_str(text);
            }
        }

        if combined.is_empty() {
            Err(AppError::AIRequestFailed("No response from Claude".to_string()))
        } else {
            Ok(combined)
        }
    }

    async fn generate_stream(
        &self,
        prompt: &str,
        config: &AIConfig,
    ) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
        let (url, auth_header) = if config.use_microrent_proxy
            || env::var("USE_DOTMINI_PROXY").unwrap_or_else(|_| "0".to_string()) == "1"
        {
            let proxy_url = env::var("DOTMINI_API_BASE_URL").map_err(|_| {
                AppError::AIProviderError("DOTMINI_API_BASE_URL not configured".to_string())
            })?;
            let token = config
                .microrent_token
                .clone()
                .or_else(|| env::var("DOTMINI_API_TOKEN").ok())
                .ok_or_else(|| {
                    AppError::AIProviderError("DOTMINI_API_TOKEN not found for Gateway".to_string())
                })?;
            (proxy_url, format!("Bearer {}", token))
        } else {
            let api_key = if config.api_key.is_empty() {
                env::var("ANTHROPIC_API_KEY").map_err(|_| {
                    AppError::AIProviderError("ANTHROPIC_API_KEY not found".to_string())
                })?
            } else {
                config.api_key.clone()
            };
            ("https://api.anthropic.com/v1/messages".to_string(), api_key)
        };

        #[derive(Serialize)]
        struct ClaudeRequest {
            model: String,
            messages: Vec<Message>,
            max_tokens: usize,
            temperature: f32,
            stream: bool,
        }

        #[derive(Serialize)]
        struct Message {
            role: String,
            content: String,
        }

        let request = ClaudeRequest {
            model: config.model.clone(),
            messages: vec![Message {
                role: "user".to_string(),
                content: prompt.to_string(),
            }],
            max_tokens: config.max_tokens,
            temperature: config.temperature,
            stream: true,
        };

        let mut request_builder = self.client.post(url);

        if config.use_microrent_proxy
            || env::var("USE_DOTMINI_PROXY").unwrap_or_else(|_| "0".to_string()) == "1"
        {
            request_builder = request_builder
                .header("Authorization", auth_header)
                .header("x-microrent-provider", "anthropic")
                .header("x-microrent-model", &config.model)
                .header("x-microrent-stream", "true");
        } else {
            request_builder = request_builder
                .header("x-api-key", auth_header)
                .header("anthropic-version", "2023-06-01");
        }

        let response = request_builder
            .header("Content-Type", "application/json")
            .json(&request)
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::AIRequestFailed(format!(
                "Claude API error: {}",
                error_text
            )));
        }

        use eventsource_stream::Eventsource;
        use futures::StreamExt;

        let stream = response
            .bytes_stream()
            .eventsource()
            .map(|event| match event {
                Ok(event) => {
                    let trimmed = event.data.trim();
                    if trimmed.is_empty() || trimmed == "[DONE]" {
                        return Ok("".to_string());
                    }
                    let json: serde_json::Value = serde_json::from_str(trimmed)
                        .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

                    if json["type"] == "content_block_delta" {
                        let content = json["delta"]["text"].as_str().unwrap_or("").to_string();
                        Ok(content)
                    } else {
                        Ok("".to_string())
                    }
                }
                Err(e) => Err(AppError::AIRequestFailed(e.to_string())),
            })
            .boxed();

        Ok(stream)
    }

    fn name(&self) -> &str {
        "anthropic"
    }

    fn models(&self) -> Vec<AIModel> {
        Vec::new()
    }
}

// ==========================================
// DeepSeek Provider
// ==========================================

pub struct DeepSeekProvider {
    client: reqwest::Client,
}

impl DeepSeekProvider {
    pub fn new() -> Self {
        Self {
            client: reqwest::Client::new(),
        }
    }
}

#[async_trait]
impl AIProvider for DeepSeekProvider {
    async fn generate(&self, prompt: &str, config: &AIConfig) -> Result<String> {
        let (url, auth_header) = if config.use_microrent_proxy
            || env::var("USE_DOTMINI_PROXY").unwrap_or_else(|_| "0".to_string()) == "1"
        {
            let proxy_url = env::var("DOTMINI_API_BASE_URL").map_err(|_| {
                AppError::AIProviderError("DOTMINI_API_BASE_URL not configured".to_string())
            })?;
            let token = config
                .microrent_token
                .clone()
                .or_else(|| env::var("DOTMINI_API_TOKEN").ok())
                .ok_or_else(|| {
                    AppError::AIProviderError("DOTMINI_API_TOKEN not found for Gateway".to_string())
                })?;
            (proxy_url, format!("Bearer {}", token))
        } else {
            let api_key = if config.api_key.is_empty() {
                env::var("DEEPSEEK_API_KEY").map_err(|_| {
                    AppError::AIProviderError("DEEPSEEK_API_KEY not found".to_string())
                })?
            } else {
                config.api_key.clone()
            };
            (
                "https://api.deepseek.com/chat/completions".to_string(),
                format!("Bearer {}", api_key),
            )
        };

        #[derive(Serialize)]
        struct DeepSeekRequest {
            model: String,
            messages: Vec<Message>,
            temperature: f32,
            max_tokens: usize,
        }

        #[derive(Serialize)]
        struct Message {
            role: String,
            content: String,
        }

        #[derive(Deserialize)]
        struct DeepSeekResponse {
            choices: Vec<Choice>,
        }

        #[derive(Deserialize)]
        struct Choice {
            message: ResponseMessage,
        }

        #[derive(Deserialize)]
        struct ResponseMessage {
            #[serde(default)]
            content: Option<String>,
            #[serde(default)]
            reasoning_content: Option<String>,
        }

        let request = DeepSeekRequest {
            model: config.model.clone(),
            messages: vec![Message {
                role: "user".to_string(),
                content: prompt.to_string(),
            }],
            temperature: config.temperature,
            max_tokens: config.max_tokens,
        };

        let mut request_builder = self
            .client
            .post(url)
            .header("Authorization", auth_header)
            .header("Content-Type", "application/json")
            .json(&request);

        if config.use_microrent_proxy
            || env::var("USE_DOTMINI_PROXY").unwrap_or_else(|_| "0".to_string()) == "1"
        {
            request_builder = request_builder
                .header("x-microrent-provider", "openai") // DeepSeek uses OpenAI format
                .header("x-microrent-model", &config.model)
                .header("x-microrent-stream", "false");
        }

        let response = request_builder
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::AIRequestFailed(format!(
                "DeepSeek API error: {}",
                error_text
            )));
        }

        let result: DeepSeekResponse = response
            .json()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        result
            .choices
            .first()
            .map(|c| {
                let mut out = String::new();
                if let Some(ref reasoning) = c.message.reasoning_content {
                    if !reasoning.is_empty() {
                        out.push_str(&format!("<thought>{}</thought>\n", reasoning));
                    }
                }
                if let Some(ref text) = c.message.content {
                    out.push_str(text);
                }
                out
            })
            .ok_or_else(|| AppError::AIRequestFailed("No response from DeepSeek".to_string()))
    }

    async fn generate_stream(
        &self,
        prompt: &str,
        config: &AIConfig,
    ) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
        let (url, auth_header) = if config.use_microrent_proxy
            || env::var("USE_DOTMINI_PROXY").unwrap_or_else(|_| "0".to_string()) == "1"
        {
            let proxy_url = env::var("DOTMINI_API_BASE_URL").map_err(|_| {
                AppError::AIProviderError("DOTMINI_API_BASE_URL not configured".to_string())
            })?;
            let token = config
                .microrent_token
                .clone()
                .or_else(|| env::var("DOTMINI_API_TOKEN").ok())
                .ok_or_else(|| {
                    AppError::AIProviderError("DOTMINI_API_TOKEN not found for Gateway".to_string())
                })?;
            (proxy_url, format!("Bearer {}", token))
        } else {
            let api_key = if config.api_key.is_empty() {
                env::var("DEEPSEEK_API_KEY").map_err(|_| {
                    AppError::AIProviderError("DEEPSEEK_API_KEY not found".to_string())
                })?
            } else {
                config.api_key.clone()
            };
            (
                "https://api.deepseek.com/chat/completions".to_string(),
                format!("Bearer {}", api_key),
            )
        };

        #[derive(Serialize)]
        struct DeepSeekRequest {
            model: String,
            messages: Vec<Message>,
            temperature: f32,
            max_tokens: usize,
            stream: bool,
        }

        #[derive(Serialize)]
        struct Message {
            role: String,
            content: String,
        }

        let request = DeepSeekRequest {
            model: config.model.clone(),
            messages: vec![Message {
                role: "user".to_string(),
                content: prompt.to_string(),
            }],
            temperature: config.temperature,
            max_tokens: config.max_tokens,
            stream: true,
        };

        let mut request_builder = self
            .client
            .post(url)
            .header("Authorization", auth_header)
            .header("Content-Type", "application/json")
            .json(&request);

        if config.use_microrent_proxy
            || env::var("USE_DOTMINI_PROXY").unwrap_or_else(|_| "0".to_string()) == "1"
        {
            request_builder = request_builder
                .header("x-microrent-provider", "openai") // DeepSeek uses OpenAI format
                .header("x-microrent-model", &config.model)
                .header("x-microrent-stream", "true");
        }

        let response = request_builder
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::AIRequestFailed(format!(
                "DeepSeek API error: {}",
                error_text
            )));
        }

        use eventsource_stream::Eventsource;
        use futures::StreamExt;

        let stream = response
            .bytes_stream()
            .eventsource()
            .map(|event| match event {
                Ok(event) => {
                    let trimmed = event.data.trim();
                    if trimmed.is_empty() || trimmed == "[DONE]" {
                        return Ok("".to_string());
                    }
                    let json: serde_json::Value = serde_json::from_str(trimmed)
                        .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

                    let delta = &json["choices"][0]["delta"];
                    let content = delta["content"]
                        .as_str()
                        .unwrap_or("")
                        .to_string();
                    Ok(content)
                }
                Err(e) => Err(AppError::AIRequestFailed(e.to_string())),
            })
            .boxed();

        Ok(stream)
    }

    fn name(&self) -> &str {
        "deepseek"
    }

    fn models(&self) -> Vec<AIModel> {
        vec![
            AIModel {
                id: "deepseek-chat-v4".to_string(),
                name: "DeepSeek V4".to_string(),
                provider: "deepseek".to_string(),
                context_length: 128000,
            },
            AIModel {
                id: "deepseek-chat".to_string(),
                name: "DeepSeek Chat".to_string(),
                provider: "deepseek".to_string(),
                context_length: 128000,
            },
            AIModel {
                id: "deepseek-coder".to_string(),
                name: "DeepSeek Coder".to_string(),
                provider: "deepseek".to_string(),
                context_length: 128000,
            },
            AIModel {
                id: "deepseek-reasoner".to_string(),
                name: "DeepSeek Reasoner".to_string(),
                provider: "deepseek".to_string(),
                context_length: 128000,
            },
        ]
    }
}

// ==========================================
// GLM (Zhipu) Provider
// ==========================================

pub struct GLMProvider {
    client: reqwest::Client,
}

impl GLMProvider {
    pub fn new() -> Self {
        Self {
            client: reqwest::Client::new(),
        }
    }
}

#[async_trait]
impl AIProvider for GLMProvider {
    async fn generate(&self, prompt: &str, config: &AIConfig) -> Result<String> {
        let api_key = if config.api_key.is_empty() {
            env::var("GLM_API_KEY")
                .map_err(|_| AppError::AIProviderError("GLM_API_KEY not found".to_string()))?
        } else {
            config.api_key.clone()
        };

        let url = "https://open.bigmodel.cn/api/paas/v4/chat/completions";

        #[derive(Serialize)]
        struct GLMRequest {
            model: String,
            messages: Vec<Message>,
            temperature: f32,
            max_tokens: usize,
        }

        #[derive(Serialize)]
        struct Message {
            role: String,
            content: String,
        }

        #[derive(Deserialize)]
        struct GLMResponse {
            choices: Vec<Choice>,
        }

        #[derive(Deserialize)]
        struct Choice {
            message: ResponseMessage,
        }

        #[derive(Deserialize)]
        struct ResponseMessage {
            content: String,
        }

        let request = GLMRequest {
            model: config.model.clone(),
            messages: vec![Message {
                role: "user".to_string(),
                content: prompt.to_string(),
            }],
            temperature: config.temperature,
            max_tokens: config.max_tokens,
        };

        let response = self
            .client
            .post(url)
            .header("Authorization", format!("Bearer {}", api_key))
            .header("Content-Type", "application/json")
            .json(&request)
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::AIRequestFailed(format!(
                "GLM API error: {}",
                error_text
            )));
        }

        let result: GLMResponse = response
            .json()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        result
            .choices
            .first()
            .map(|c| c.message.content.clone())
            .ok_or_else(|| AppError::AIRequestFailed("No response from GLM".to_string()))
    }

    async fn generate_stream(
        &self,
        prompt: &str,
        config: &AIConfig,
    ) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
        let api_key = if config.api_key.is_empty() {
            env::var("GLM_API_KEY")
                .map_err(|_| AppError::AIProviderError("GLM_API_KEY not found".to_string()))?
        } else {
            config.api_key.clone()
        };

        let url = "https://open.bigmodel.cn/api/paas/v4/chat/completions";

        #[derive(Serialize)]
        struct GLMRequest {
            model: String,
            messages: Vec<Message>,
            temperature: f32,
            max_tokens: usize,
            stream: bool,
        }

        #[derive(Serialize)]
        struct Message {
            role: String,
            content: String,
        }

        let request = GLMRequest {
            model: config.model.clone(),
            messages: vec![Message {
                role: "user".to_string(),
                content: prompt.to_string(),
            }],
            temperature: config.temperature,
            max_tokens: config.max_tokens,
            stream: true,
        };

        let response = self
            .client
            .post(url)
            .header("Authorization", format!("Bearer {}", api_key))
            .header("Content-Type", "application/json")
            .json(&request)
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::AIRequestFailed(format!(
                "GLM API error: {}",
                error_text
            )));
        }

        use eventsource_stream::Eventsource;
        use futures::StreamExt;

        let stream = response
            .bytes_stream()
            .eventsource()
            .map(|event| match event {
                Ok(event) => {
                    if event.data == "[DONE]" {
                        return Ok("".to_string());
                    }
                    let json: serde_json::Value = serde_json::from_str(&event.data)
                        .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

                    let content = json["choices"][0]["delta"]["content"]
                        .as_str()
                        .unwrap_or("")
                        .to_string();
                    Ok(content)
                }
                Err(e) => Err(AppError::AIRequestFailed(e.to_string())),
            })
            .boxed();

        Ok(stream)
    }

    fn name(&self) -> &str {
        "glm"
    }

    fn models(&self) -> Vec<AIModel> {
        vec![
            AIModel {
                id: "glm-4.6".to_string(),
                name: "GLM-4.6".to_string(),
                provider: "glm".to_string(),
                context_length: 128000,
            },
            AIModel {
                id: "glm-4-plus".to_string(),
                name: "GLM-4 Plus".to_string(),
                provider: "glm".to_string(),
                context_length: 128000,
            },
            AIModel {
                id: "glm-4-flash".to_string(),
                name: "GLM-4 Flash".to_string(),
                provider: "glm".to_string(),
                context_length: 128000,
            },
        ]
    }
}

// ==========================================
// Grok (xAI) Provider
// ==========================================

pub struct GrokProvider {
    client: reqwest::Client,
}

impl GrokProvider {
    pub fn new() -> Self {
        Self {
            client: reqwest::Client::new(),
        }
    }
}

#[async_trait]
impl AIProvider for GrokProvider {
    async fn generate(&self, prompt: &str, config: &AIConfig) -> Result<String> {
        let api_key = if config.api_key.is_empty() {
            env::var("GROK_API_KEY")
                .map_err(|_| AppError::AIProviderError("GROK_API_KEY not found".to_string()))?
        } else {
            config.api_key.clone()
        };

        let request = serde_json::json!({
            "model": config.model,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": config.temperature,
            "max_tokens": config.max_tokens,
        });

        let response = self
            .client
            .post("https://api.x.ai/v1/chat/completions")
            .header("Authorization", format!("Bearer {}", api_key))
            .json(&request)
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        if !response.status().is_success() {
            return Err(AppError::AIRequestFailed(format!(
                "Grok API error: {}",
                response.text().await.unwrap_or_default()
            )));
        }

        let result: serde_json::Value = response
            .json()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;
        Ok(result["choices"][0]["message"]["content"]
            .as_str()
            .unwrap_or("")
            .to_string())
    }

    async fn generate_stream(
        &self,
        prompt: &str,
        config: &AIConfig,
    ) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
        let api_key = if config.api_key.is_empty() {
            env::var("GROK_API_KEY")
                .map_err(|_| AppError::AIProviderError("GROK_API_KEY not found".to_string()))?
        } else {
            config.api_key.clone()
        };

        let request = serde_json::json!({
            "model": config.model,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": config.temperature,
            "max_tokens": config.max_tokens,
            "stream": true,
        });

        let response = self
            .client
            .post("https://api.x.ai/v1/chat/completions")
            .header("Authorization", format!("Bearer {}", api_key))
            .json(&request)
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        use eventsource_stream::Eventsource;
        use futures::StreamExt;

        Ok(response
            .bytes_stream()
            .eventsource()
            .map(|event| match event {
                Ok(event) => {
                    if event.data == "[DONE]" {
                        return Ok("".to_string());
                    }
                    let json: serde_json::Value = serde_json::from_str(&event.data)
                        .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;
                    Ok(json["choices"][0]["delta"]["content"]
                        .as_str()
                        .unwrap_or("")
                        .to_string())
                }
                Err(e) => Err(AppError::AIRequestFailed(e.to_string())),
            })
            .boxed())
    }

    fn name(&self) -> &str {
        "grok"
    }
    fn models(&self) -> Vec<AIModel> {
        vec![
            AIModel {
                id: "grok-3".to_string(),
                name: "Grok 3".to_string(),
                provider: "grok".to_string(),
                context_length: 131072,
            },
            AIModel {
                id: "grok-3-mini".to_string(),
                name: "Grok 3 Mini".to_string(),
                provider: "grok".to_string(),
                context_length: 131072,
            },
        ]
    }
}

// ==========================================
// Qwen (Alibaba) Provider
// ==========================================

pub struct QwenProvider {
    client: reqwest::Client,
}

impl QwenProvider {
    pub fn new() -> Self {
        Self {
            client: reqwest::Client::new(),
        }
    }
}

#[async_trait]
impl AIProvider for QwenProvider {
    async fn generate(&self, prompt: &str, config: &AIConfig) -> Result<String> {
        let api_key = if config.api_key.is_empty() {
            env::var("QWEN_API_KEY")
                .map_err(|_| AppError::AIProviderError("QWEN_API_KEY not found".to_string()))?
        } else {
            config.api_key.clone()
        };

        let request = serde_json::json!({
            "model": config.model,
            "input": { "messages": [{"role": "user", "content": prompt}] },
            "parameters": { "temperature": config.temperature, "max_tokens": config.max_tokens }
        });

        // DashScope API
        let response = self
            .client
            .post("https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation")
            .header("Authorization", format!("Bearer {}", api_key))
            .header("Content-Type", "application/json")
            .json(&request)
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        if !response.status().is_success() {
            return Err(AppError::AIRequestFailed(format!(
                "Qwen API error: {}",
                response.text().await.unwrap_or_default()
            )));
        }

        let result: serde_json::Value = response
            .json()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;
        Ok(result["output"]["text"].as_str().unwrap_or("").to_string())
    }

    async fn generate_stream(
        &self,
        prompt: &str,
        config: &AIConfig,
    ) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
        let api_key = if config.api_key.is_empty() {
            env::var("QWEN_API_KEY")
                .map_err(|_| AppError::AIProviderError("QWEN_API_KEY not found".to_string()))?
        } else {
            config.api_key.clone()
        };

        let request = serde_json::json!({
            "model": config.model,
            "input": { "messages": [{"role": "user", "content": prompt}] },
            "parameters": { "temperature": config.temperature, "max_tokens": config.max_tokens, "incremental_output": true }
        });

        let response = self
            .client
            .post("https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation")
            .header("Authorization", format!("Bearer {}", api_key))
            .header("X-DashScope-SSE", "enable")
            .header("Content-Type", "application/json")
            .json(&request)
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        use futures::StreamExt;
        Ok(response
            .bytes_stream()
            .map(|result| match result {
                Ok(bytes) => {
                    let s = String::from_utf8_lossy(&bytes);
                    if s.contains("output") {
                        let json: serde_json::Value = serde_json::from_str(&s.replace("data:", ""))
                            .unwrap_or(serde_json::json!({}));
                        Ok(json["output"]["text"].as_str().unwrap_or("").to_string())
                    } else {
                        Ok("".to_string())
                    }
                }
                Err(e) => Err(AppError::AIRequestFailed(e.to_string())),
            })
            .boxed())
    }

    fn name(&self) -> &str {
        "qwen"
    }
    fn models(&self) -> Vec<AIModel> {
        vec![
            AIModel {
                id: "qwen3-235b-a22b".to_string(),
                name: "Qwen3 235B-A22B".to_string(),
                provider: "qwen".to_string(),
                context_length: 128000,
            },
            AIModel {
                id: "qwen-max".to_string(),
                name: "Qwen Max".to_string(),
                provider: "qwen".to_string(),
                context_length: 30000,
            },
            AIModel {
                id: "qwen-plus".to_string(),
                name: "Qwen Plus".to_string(),
                provider: "qwen".to_string(),
                context_length: 30000,
            },
        ]
    }
}

// ==========================================
// Ollama (Local OSS) Provider
// ==========================================

pub struct OllamaProvider {
    client: reqwest::Client,
}

impl OllamaProvider {
    pub fn new() -> Self {
        Self {
            client: reqwest::Client::new(),
        }
    }
}

#[async_trait]
impl AIProvider for OllamaProvider {
    async fn generate(&self, prompt: &str, config: &AIConfig) -> Result<String> {
        let request = serde_json::json!({
            "model": config.model,
            "prompt": prompt,
            "stream": false,
            "options": {
                "temperature": config.temperature,
                "num_predict": config.max_tokens,
            }
        });

        let url = env::var("OLLAMA_HOST").unwrap_or_else(|_| "http://127.0.0.1:11434".to_string());

        let response = self
            .client
            .post(format!("{}/api/generate", url))
            .json(&request)
            .send()
            .await
            .map_err(|e| {
                AppError::AIRequestFailed(format!(
                    "Ollama connection failed (Is it running?): {}",
                    e
                ))
            })?;

        if !response.status().is_success() {
            return Err(AppError::AIRequestFailed(format!(
                "Ollama API error: {}",
                response.text().await.unwrap_or_default()
            )));
        }

        let result: serde_json::Value = response
            .json()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;
        Ok(result["response"].as_str().unwrap_or("").to_string())
    }

    async fn generate_stream(
        &self,
        prompt: &str,
        config: &AIConfig,
    ) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
        let request = serde_json::json!({
            "model": config.model,
            "prompt": prompt,
            "stream": true,
            "options": {
                "temperature": config.temperature,
                "num_predict": config.max_tokens,
            }
        });

        let url = env::var("OLLAMA_HOST").unwrap_or_else(|_| "http://127.0.0.1:11434".to_string());

        let response = self
            .client
            .post(format!("{}/api/generate", url))
            .json(&request)
            .send()
            .await
            .map_err(|e| {
                AppError::AIRequestFailed(format!(
                    "Ollama connection failed (Is it running?): {}",
                    e
                ))
            })?;

        use futures::StreamExt;

        Ok(response
            .bytes_stream()
            .map(|result| {
                match result {
                    Ok(bytes) => {
                        let s = String::from_utf8_lossy(&bytes);
                        let mut final_text = String::new();
                        // Ollama streams JSON-Lines. We might get multiple JSON objects in one chunk
                        for line in s.lines() {
                            if line.trim().is_empty() {
                                continue;
                            }
                            if let Ok(json) = serde_json::from_str::<serde_json::Value>(line) {
                                if let Some(text) = json["response"].as_str() {
                                    final_text.push_str(text);
                                }
                            }
                        }
                        Ok(final_text)
                    }
                    Err(e) => Err(AppError::AIRequestFailed(e.to_string())),
                }
            })
            .boxed())
    }

    fn name(&self) -> &str {
        "ollama"
    }
    fn models(&self) -> Vec<AIModel> {
        vec![]
    }
}

// ==========================================
// Provider Factory
// ==========================================

pub fn get_provider(provider_name: &str) -> Result<Box<dyn AIProvider>> {
    // The desktop app keeps file/tools execution in this local backend, while
    // model inference is routed through the Dotmini OpenAI-compatible proxy.
    // This also lets Gemini/Claude/etc. model IDs work through one protocol.
    let proxy_enabled = env::var("DOTMINI_API_BASE_URL")
        .map(|url| !url.trim().is_empty())
        .unwrap_or(false)
        && env::var("USE_DOTMINI_PROXY")
            .map(|v| v == "1")
            .unwrap_or(false);

    if proxy_enabled && !matches!(provider_name.to_lowercase().as_str(), "ollama" | "local") {
        return Ok(Box::new(OpenAIProvider::new()));
    }

    match provider_name.to_lowercase().as_str() {
        "gemini" => Ok(Box::new(GeminiProvider::new())),
        "openai" => Ok(Box::new(OpenAIProvider::new())),
        "anthropic" | "claude" => Ok(Box::new(ClaudeProvider::new())),
        "deepseek" => Ok(Box::new(DeepSeekProvider::new())),
        "glm" | "zhipu" => Ok(Box::new(GLMProvider::new())),
        "grok" | "xai" => Ok(Box::new(GrokProvider::new())),
        "qwen" | "alibaba" => Ok(Box::new(QwenProvider::new())),
        "ollama" | "local" => Ok(Box::new(OllamaProvider::new())),
        _ => Err(AppError::AIProviderError(format!(
            "Unknown provider: {}",
            provider_name
        ))),
    }
}

// ==========================================
// High-level AI Functions
// ==========================================

/// Refactor code using AI
pub async fn refactor(code: &str, instructions: &str, config: &AIConfig) -> Result<String> {
    let provider = get_provider(&config.provider)?;

    let prompt = format!(
        "You are an expert code refactoring assistant. Refactor the following code according to the instructions.\n\n\
        Instructions: {}\n\n\
        Code:\n```\n{}\n```\n\n\
        Please provide only the refactored code without explanations. Maintain the same functionality.",
        instructions, code
    );

    let response = provider.generate(&prompt, config).await?;

    // Extract code from markdown code blocks if present
    let code_block_pattern = regex::Regex::new(r"```(?:\w+)?\n([\s\S]*?)\n```").unwrap();
    if let Some(captures) = code_block_pattern.captures(&response) {
        Ok(captures[1].to_string())
    } else {
        Ok(response)
    }
}

/// Refactor code using AI with streaming
pub async fn refactor_stream(
    code: &str,
    instructions: &str,
    config: &AIConfig,
) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
    let provider = get_provider(&config.provider)?;

    let prompt = format!(
        "You are an expert code refactoring assistant. Refactor the following code according to the instructions.\n\n\
        Instructions: {}\n\n\
        Code:\n```\n{}\n```\n\n\
        Please provide only the refactored code without explanations. Maintain the same functionality.",
        instructions, code
    );

    provider.generate_stream(&prompt, config).await
}

/// Transpile code from one language to another (e.g., SAS to Python)
pub async fn transpile(
    code: &str,
    target_lang: &str,
    instructions: &str,
    config: &AIConfig,
) -> Result<String> {
    let provider = get_provider(&config.provider)?;

    let prompt = format!(
        "You are a master polyglot software architect and data engineer specializing in legacy system modernization.\n\
        Your mission: Transpile the provided code to {}.\n\n\
        Instructions: {}\n\n\
        Source Code:\n```\n{}\n```\n\n\
        CRITICAL REQUIREMENTS:\n\
        1. OPTIMIZATION: If transpiling to Python, use vectorized operations (Pandas/Polars) instead of loops wherever possible.\n\
        2. DATA SEMANTICS: Preserve all data logic, precision, and edge-case handling (e.g., missing values in SAS).\n\
        3. IDIOMATIC: Use {} code patterns and best practices.\n\
        4. CLEANLINESS: No boilerplate, no unnecessary comments, just clean executable code.\n\n\
        Output only the transpiled code within a single markdown code block.",
        target_lang, instructions, code, target_lang
    );

    let response = provider.generate(&prompt, config).await?;

    let code_block_pattern = regex::Regex::new(r"```(?:\w+)?\n([\s\S]*?)\n```").unwrap();
    if let Some(captures) = code_block_pattern.captures(&response) {
        Ok(captures[1].to_string())
    } else {
        Ok(response)
    }
}

/// Explain code using AI
pub async fn explain(code: &str, config: &AIConfig) -> Result<String> {
    let provider = get_provider(&config.provider)?;

    let prompt = format!(
        "You are an expert code explanation assistant. Explain what the following code does in a clear and concise way.\n\n\
        Code:\n```\n{}\n```\n\n\
        Provide a detailed explanation including:\n\
        1. Overall purpose\n\
        2. Key components and their roles\n\
        3. Important algorithms or patterns used\n\
        4. Potential improvements or concerns",
        code
    );

    provider.generate(&prompt, config).await
}

/// Generate code completion using AI
pub async fn complete(code: &str, context: &str, config: &AIConfig) -> Result<String> {
    let provider = get_provider(&config.provider)?;

    let prompt = format!(
        "You are an expert code completion assistant. Complete the following code based on the context.\n\n\
        Context: {}\n\n\
        Code to complete:\n```\n{}\n```\n\n\
        Provide only the completion without repeating the existing code.",
        context, code
    );

    let response = provider.generate(&prompt, config).await?;

    // Extract code from markdown code blocks if present
    let code_block_pattern = regex::Regex::new(r"```(?:\w+)?\n([\s\S]*?)\n```").unwrap();
    if let Some(captures) = code_block_pattern.captures(&response) {
        Ok(captures[1].to_string())
    } else {
        Ok(response)
    }
}

/// List all available AI models dynamically from live provider APIs and local CLI caches
pub async fn list_models() -> Result<Vec<AIModel>> {
    let mut models = Vec::new();
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .build()
        .unwrap_or_default();

    // 1. Live Google Gemini API (v1beta & v1alpha)
    if let Ok(key) = env::var("GEMINI_API_KEY").or_else(|_| env::var("GOOGLE_API_KEY")) {
        if !key.trim().is_empty() {
            for ver in ["v1beta", "v1alpha"] {
                let url = format!(
                    "https://generativelanguage.googleapis.com/{}/models?pageSize=1000&key={}",
                    ver,
                    key.trim()
                );
                if let Ok(resp) = client.get(&url).send().await {
                    if let Ok(json) = resp.json::<serde_json::Value>().await {
                        if let Some(items) = json["models"].as_array() {
                            for item in items {
                                let raw_name = item["name"].as_str().unwrap_or("");
                                let id = raw_name.strip_prefix("models/").unwrap_or(raw_name);
                                if id.is_empty() || models.iter().any(|m: &AIModel| m.id == id) {
                                    continue;
                                }
                                let display = item["displayName"].as_str().unwrap_or(id);
                                let ctx = item["inputTokenLimit"].as_u64().unwrap_or(1_048_576) as usize;
                                models.push(AIModel {
                                    id: id.to_string(),
                                    name: display.to_string(),
                                    provider: "gemini".to_string(),
                                    context_length: ctx,
                                });
                            }
                        }
                    }
                }
            }
        }
    }

    // 2. Local Codex cache (~/.codex/models_cache.json) for live OpenAI / Codex models
    if let Ok(home) = env::var("HOME") {
        let codex_cache = std::path::Path::new(&home).join(".codex/models_cache.json");
        if let Ok(raw) = std::fs::read_to_string(codex_cache) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&raw) {
                if let Some(items) = json["models"].as_array() {
                    for item in items {
                        if let Some(slug) = item["slug"].as_str() {
                            if !slug.is_empty() && !models.iter().any(|m: &AIModel| m.id == slug) {
                                let display = item["display_name"].as_str().unwrap_or(slug);
                                let ctx = item["context_window"].as_u64().unwrap_or(272_000) as usize;
                                models.push(AIModel {
                                    id: slug.to_string(),
                                    name: display.to_string(),
                                    provider: "openai".to_string(),
                                    context_length: ctx,
                                });
                            }
                        }
                    }
                }
            }
        }
    }

    // 3. Live OpenAI API (/v1/models)
    if let Ok(key) = env::var("OPENAI_API_KEY") {
        if !key.trim().is_empty() {
            if let Ok(resp) = client
                .get("https://api.openai.com/v1/models")
                .bearer_auth(key.trim())
                .send()
                .await
            {
                if let Ok(json) = resp.json::<serde_json::Value>().await {
                    if let Some(items) = json["data"].as_array() {
                        for item in items {
                            if let Some(id) = item["id"].as_str() {
                                if !id.is_empty() && !models.iter().any(|m: &AIModel| m.id == id) {
                                    models.push(AIModel {
                                        id: id.to_string(),
                                        name: id.to_string(),
                                        provider: "openai".to_string(),
                                        context_length: 128_000,
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 4. Live Anthropic API (/v1/models)
    if let Ok(key) = env::var("ANTHROPIC_API_KEY") {
        if !key.trim().is_empty() {
            if let Ok(resp) = client
                .get("https://api.anthropic.com/v1/models")
                .header("x-api-key", key.trim())
                .header("anthropic-version", "2023-06-01")
                .send()
                .await
            {
                if let Ok(json) = resp.json::<serde_json::Value>().await {
                    if let Some(items) = json["data"].as_array() {
                        for item in items {
                            if let Some(id) = item["id"].as_str() {
                                let display = item["display_name"].as_str().unwrap_or(id);
                                if !id.is_empty() && !models.iter().any(|m: &AIModel| m.id == id) {
                                    models.push(AIModel {
                                        id: id.to_string(),
                                        name: display.to_string(),
                                        provider: "anthropic".to_string(),
                                        context_length: 200_000,
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 5. Live DeepSeek API (/models)
    if let Ok(key) = env::var("DEEPSEEK_API_KEY") {
        if !key.trim().is_empty() {
            if let Ok(resp) = client
                .get("https://api.deepseek.com/models")
                .bearer_auth(key.trim())
                .send()
                .await
            {
                if let Ok(json) = resp.json::<serde_json::Value>().await {
                    if let Some(items) = json["data"].as_array() {
                        for item in items {
                            if let Some(id) = item["id"].as_str() {
                                if !id.is_empty() && !models.iter().any(|m: &AIModel| m.id == id) {
                                    models.push(AIModel {
                                        id: id.to_string(),
                                        name: id.to_string(),
                                        provider: "deepseek".to_string(),
                                        context_length: 128_000,
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 6. Live Ollama local tags
    let ollama_host = env::var("OLLAMA_HOST").unwrap_or_else(|_| "http://127.0.0.1:11434".to_string());
    if let Ok(resp) = client.get(format!("{}/api/tags", ollama_host)).send().await {
        if let Ok(json) = resp.json::<serde_json::Value>().await {
            if let Some(items) = json["models"].as_array() {
                for item in items {
                    if let Some(id) = item["name"].as_str() {
                        if !id.is_empty() && !models.iter().any(|m: &AIModel| m.id == id) {
                            models.push(AIModel {
                                id: id.to_string(),
                                name: id.to_string(),
                                provider: "ollama".to_string(),
                                context_length: 32_768,
                            });
                        }
                    }
                }
            }
        }
    }

    Ok(models)
}

// ==========================================
// Tests
// ==========================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_provider_factory() {
        assert!(get_provider("gemini").is_ok());
        assert!(get_provider("openai").is_ok());
        assert!(get_provider("anthropic").is_ok());
        assert!(get_provider("claude").is_ok());
        assert!(get_provider("invalid").is_err());
    }

    #[test]
    fn test_extract_code_from_markdown() {
        let text = "Here's the code:\n```rust\nfn main() {}\n```";
        let pattern = regex::Regex::new(r"```(?:\w+)?\n([\s\S]*?)\n```").unwrap();
        let captures = pattern.captures(text).unwrap();
        assert_eq!(captures[1].trim(), "fn main() {}");
    }
}

/// The desktop passes a base URL, while the provider needs a concrete endpoint.
fn cloud_chat_endpoint(config: &AIConfig) -> Result<String> {
    let base = config.proxy_base_url.clone().or_else(|| env::var("DOTMINI_API_BASE_URL").ok())
        .ok_or_else(|| AppError::AIProviderError("Cloud base URL is missing".into()))?;
    let url = reqwest::Url::parse(&base).map_err(|_| AppError::AIProviderError("Invalid cloud base URL".into()))?;
    if url.scheme() != "https" || !url.username().is_empty() || url.password().is_some() || url.query().is_some() || url.fragment().is_some() {
        return Err(AppError::AIProviderError("Cloud base URL must be an HTTPS endpoint without credentials or query".into()));
    }
    let base = base.trim_end_matches('/');
    Ok(if base.ends_with("/chat/completions") { base.to_string() } else { format!("{base}/chat/completions") })
}
