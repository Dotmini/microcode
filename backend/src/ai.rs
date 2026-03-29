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
    async fn generate_stream(&self, prompt: &str, config: &AIConfig) -> Result<futures::stream::BoxStream<'static, Result<String>>>;
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
        let (url, auth_header) = if config.use_microrent_proxy || env::var("USE_MICRORENT_PROXY").unwrap_or_else(|_| "0".to_string()) == "1" {
            let proxy_url = env::var("MICRORENT_PROXY_URL").unwrap_or_else(|_| "https://***REDACTED_PROXY_URL***".to_string());
            let token = config.microrent_token.clone()
                .or_else(|| env::var("MICRORENT_TOKEN").ok())
                .ok_or_else(|| AppError::AIProviderError("MICRORENT_TOKEN not found for Gateway".to_string()))?;
            (proxy_url, format!("Bearer {}", token))
        } else {
            let api_key = if config.api_key.is_empty() {
                env::var("GEMINI_API_KEY").map_err(|_| {
                    AppError::AIProviderError("GEMINI_API_KEY not found".to_string())
                })?
            } else {
                config.api_key.clone()
            };
            let direct_url = format!(
                "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent?key={}",
                config.model, api_key
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
            candidates: Vec<Candidate>,
        }

        #[derive(Deserialize)]
        struct Candidate {
            content: ResponseContent,
        }

        #[derive(Deserialize)]
        struct ResponseContent {
            parts: Vec<ResponsePart>,
        }

        #[derive(Deserialize)]
        struct ResponsePart {
            text: String,
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

        result
            .candidates
            .first()
            .and_then(|c| c.content.parts.first())
            .map(|p| p.text.clone())
            .ok_or_else(|| AppError::AIRequestFailed("No response from Gemini".to_string()))
    }

    async fn generate_stream(&self, prompt: &str, config: &AIConfig) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
        let (url, auth_header) = if config.use_microrent_proxy || env::var("USE_MICRORENT_PROXY").unwrap_or_else(|_| "0".to_string()) == "1" {
            let proxy_url = env::var("MICRORENT_PROXY_URL").unwrap_or_else(|_| "https://***REDACTED_PROXY_URL***".to_string());
            let token = config.microrent_token.clone()
                .or_else(|| env::var("MICRORENT_TOKEN").ok())
                .ok_or_else(|| AppError::AIProviderError("MICRORENT_TOKEN not found for Gateway".to_string()))?;
            (proxy_url, format!("Bearer {}", token))
        } else {
            let api_key = if config.api_key.is_empty() {
                env::var("GEMINI_API_KEY").map_err(|_| {
                    AppError::AIProviderError("GEMINI_API_KEY not found".to_string())
                })?
            } else {
                config.api_key.clone()
            };
            let direct_url = format!(
                "https://generativelanguage.googleapis.com/v1beta/models/{}:streamGenerateContent?key={}",
                config.model, api_key
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

        use futures::StreamExt;
        
        let mut stream = response.bytes_stream();
        let re = std::sync::OnceLock::new();
        
        // Manual stream implementation to allow buffering
        let stream = async_stream::stream! {
            let re = re.get_or_init(|| regex::Regex::new(r#""text":\s*"([^"]*)""#).unwrap());
            let mut buffer = String::new();
            
            while let Some(chunk_res) = stream.next().await {
                match chunk_res {
                    Ok(bytes) => {
                        let s = String::from_utf8_lossy(&bytes);
                        buffer.push_str(&s);

                        // If buffer gets too large, we might want to clear it, but for now we keep it simple.
                        // We slide through the buffer finding matches.
                        // A better approach for continuous stream:
                        // Find matches, yield them, then remove processed part from buffer.
                        // But since JSON structure is complex, we'll try a simpler heuristic:
                        // Append to buffer, run regex on NEW part (plus some lookbehind), or just run on whole buffer (inefficient)?
                        // 
                        // OPTIMIZATION: Just run on the specific chunk for now, but handle the "split" case by keeping 
                        // a small overlap or just hoping `reqwest` chunks align reasonably well (which they often do).
                        //
                        // ACUTALLY: The most robust way without full JSON parser is to just scan.
                        // Let's stick to the previous logic but move Regex OUT.
                        // And maybe use a lighter string search if possible.
                        
                        for cap in re.captures_iter(&s) {
                             let part = cap[1].replace("\\n", "\n").replace("\\\"", "\"").replace("\\\\", "\\");
                             yield Ok(part);
                        }
                    }
                    Err(e) => yield Err(AppError::AIRequestFailed(e.to_string())),
                }
            }
        };

        Ok(Box::pin(stream))
    }

    fn name(&self) -> &str {
        "gemini"
    }

    fn models(&self) -> Vec<AIModel> {
        vec![
            AIModel {
                id: "gemini-3.1-pro-latest".to_string(),
                name: "Gemini 3.1 Pro".to_string(),
                provider: "gemini".to_string(),
                context_length: 1048576,
            },
            AIModel {
                id: "gemini-3-flash-latest".to_string(),
                name: "Gemini 3 Flash".to_string(),
                provider: "gemini".to_string(),
                context_length: 1048576,
            },
        ]
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
        let (url, auth_header) = if config.use_microrent_proxy || env::var("USE_MICRORENT_PROXY").unwrap_or_else(|_| "0".to_string()) == "1" {
            let proxy_url = env::var("MICRORENT_PROXY_URL").unwrap_or_else(|_| "https://***REDACTED_PROXY_URL***".to_string());
            let token = config.microrent_token.clone()
                .or_else(|| env::var("MICRORENT_TOKEN").ok())
                .ok_or_else(|| AppError::AIProviderError("MICRORENT_TOKEN not found for Gateway".to_string()))?;
            (proxy_url, format!("Bearer {}", token))
        } else {
            let api_key = if config.api_key.is_empty() {
                env::var("OPENAI_API_KEY").map_err(|_| {
                    AppError::AIProviderError("OPENAI_API_KEY not found".to_string())
                })?
            } else {
                config.api_key.clone()
            };
            ("https://api.openai.com/v1/chat/completions".to_string(), format!("Bearer {}", api_key))
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
        };

        let mut request_builder = self
            .client
            .post(url)
            .header("Authorization", auth_header)
            .header("Content-Type", "application/json")
            .json(&request);

        if config.use_microrent_proxy || env::var("USE_MICRORENT_PROXY").unwrap_or_else(|_| "0".to_string()) == "1" {
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
            .map(|c| c.message.content.clone())
            .ok_or_else(|| AppError::AIRequestFailed("No response from OpenAI".to_string()))
    }

    async fn generate_stream(&self, prompt: &str, config: &AIConfig) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
        let (url, auth_header) = if config.use_microrent_proxy || env::var("USE_MICRORENT_PROXY").unwrap_or_else(|_| "0".to_string()) == "1" {
            let proxy_url = env::var("MICRORENT_PROXY_URL").unwrap_or_else(|_| "https://***REDACTED_PROXY_URL***".to_string());
            let token = config.microrent_token.clone()
                .or_else(|| env::var("MICRORENT_TOKEN").ok())
                .ok_or_else(|| AppError::AIProviderError("MICRORENT_TOKEN not found for Gateway".to_string()))?;
            (proxy_url, format!("Bearer {}", token))
        } else {
            let api_key = if config.api_key.is_empty() {
                env::var("OPENAI_API_KEY").map_err(|_| {
                    AppError::AIProviderError("OPENAI_API_KEY not found".to_string())
                })?
            } else {
                config.api_key.clone()
            };
            ("https://api.openai.com/v1/chat/completions".to_string(), format!("Bearer {}", api_key))
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
            
        if config.use_microrent_proxy || env::var("USE_MICRORENT_PROXY").unwrap_or_else(|_| "0".to_string()) == "1" {
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

        use futures::StreamExt;
        use eventsource_stream::Eventsource;

        let stream = response.bytes_stream()
            .eventsource()
            .map(|event| {
                match event {
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
                }
            })
            .boxed();

        Ok(stream)
    }

    fn name(&self) -> &str {
        "openai"
    }

    fn models(&self) -> Vec<AIModel> {
        vec![
            AIModel {
                id: "gpt-5.1".to_string(),
                name: "GPT-5.1".to_string(),
                provider: "openai".to_string(),
                context_length: 128000,
            },
            AIModel {
                id: "gpt-5.2".to_string(),
                name: "GPT-5.2".to_string(),
                provider: "openai".to_string(),
                context_length: 16385,
            },
        ]
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
        let (url, auth_header) = if config.use_microrent_proxy || env::var("USE_MICRORENT_PROXY").unwrap_or_else(|_| "0".to_string()) == "1" {
            let proxy_url = env::var("MICRORENT_PROXY_URL").unwrap_or_else(|_| "https://***REDACTED_PROXY_URL***".to_string());
            let token = config.microrent_token.clone()
                .or_else(|| env::var("MICRORENT_TOKEN").ok())
                .ok_or_else(|| AppError::AIProviderError("MICRORENT_TOKEN not found for Gateway".to_string()))?;
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
            content: Vec<ContentBlock>,
        }

        #[derive(Deserialize)]
        struct ContentBlock {
            text: String,
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

        let mut request_builder = self
            .client
            .post(url);
            
        if config.use_microrent_proxy || env::var("USE_MICRORENT_PROXY").unwrap_or_else(|_| "0".to_string()) == "1" {
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

        result
            .content
            .first()
            .map(|c| c.text.clone())
            .ok_or_else(|| AppError::AIRequestFailed("No response from Claude".to_string()))
    }

    async fn generate_stream(&self, prompt: &str, config: &AIConfig) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
        let (url, auth_header) = if config.use_microrent_proxy || env::var("USE_MICRORENT_PROXY").unwrap_or_else(|_| "0".to_string()) == "1" {
            let proxy_url = env::var("MICRORENT_PROXY_URL").unwrap_or_else(|_| "https://***REDACTED_PROXY_URL***".to_string());
            let token = config.microrent_token.clone()
                .or_else(|| env::var("MICRORENT_TOKEN").ok())
                .ok_or_else(|| AppError::AIProviderError("MICRORENT_TOKEN not found for Gateway".to_string()))?;
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

        let mut request_builder = self
            .client
            .post(url);
            
        if config.use_microrent_proxy || env::var("USE_MICRORENT_PROXY").unwrap_or_else(|_| "0".to_string()) == "1" {
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

        use futures::StreamExt;
        use eventsource_stream::Eventsource;

        let stream = response.bytes_stream()
            .eventsource()
            .map(|event| {
                match event {
                    Ok(event) => {
                        let json: serde_json::Value = serde_json::from_str(&event.data)
                            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;
                        
                        if json["type"] == "content_block_delta" {
                            let content = json["delta"]["text"]
                                .as_str()
                                .unwrap_or("")
                                .to_string();
                            Ok(content)
                        } else {
                            Ok("".to_string())
                        }
                    }
                    Err(e) => Err(AppError::AIRequestFailed(e.to_string())),
                }
            })
            .boxed();

        Ok(stream)
    }

    fn name(&self) -> &str {
        "anthropic"
    }

    fn models(&self) -> Vec<AIModel> {
        vec![
            AIModel {
                id: "claude-3-opus-20240229".to_string(),
                name: "Claude 3 Opus".to_string(),
                provider: "anthropic".to_string(),
                context_length: 200000,
            },
            AIModel {
                id: "claude-3-sonnet-20240229".to_string(),
                name: "Claude 3 Sonnet".to_string(),
                provider: "anthropic".to_string(),
                context_length: 200000,
            },
        ]
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
        let (url, auth_header) = if config.use_microrent_proxy || env::var("USE_MICRORENT_PROXY").unwrap_or_else(|_| "0".to_string()) == "1" {
            let proxy_url = env::var("MICRORENT_PROXY_URL").unwrap_or_else(|_| "https://***REDACTED_PROXY_URL***".to_string());
            let token = config.microrent_token.clone()
                .or_else(|| env::var("MICRORENT_TOKEN").ok())
                .ok_or_else(|| AppError::AIProviderError("MICRORENT_TOKEN not found for Gateway".to_string()))?;
            (proxy_url, format!("Bearer {}", token))
        } else {
            let api_key = if config.api_key.is_empty() {
                env::var("DEEPSEEK_API_KEY").map_err(|_| {
                    AppError::AIProviderError("DEEPSEEK_API_KEY not found".to_string())
                })?
            } else {
                config.api_key.clone()
            };
            ("https://api.deepseek.com/chat/completions".to_string(), format!("Bearer {}", api_key))
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
        };

        let mut request_builder = self
            .client
            .post(url)
            .header("Authorization", auth_header)
            .header("Content-Type", "application/json")
            .json(&request);
            
        if config.use_microrent_proxy || env::var("USE_MICRORENT_PROXY").unwrap_or_else(|_| "0".to_string()) == "1" {
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
            .map(|c| c.message.content.clone())
            .ok_or_else(|| AppError::AIRequestFailed("No response from DeepSeek".to_string()))
    }

    async fn generate_stream(&self, prompt: &str, config: &AIConfig) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
        let (url, auth_header) = if config.use_microrent_proxy || env::var("USE_MICRORENT_PROXY").unwrap_or_else(|_| "0".to_string()) == "1" {
            let proxy_url = env::var("MICRORENT_PROXY_URL").unwrap_or_else(|_| "https://***REDACTED_PROXY_URL***".to_string());
            let token = config.microrent_token.clone()
                .or_else(|| env::var("MICRORENT_TOKEN").ok())
                .ok_or_else(|| AppError::AIProviderError("MICRORENT_TOKEN not found for Gateway".to_string()))?;
            (proxy_url, format!("Bearer {}", token))
        } else {
            let api_key = if config.api_key.is_empty() {
                env::var("DEEPSEEK_API_KEY").map_err(|_| {
                    AppError::AIProviderError("DEEPSEEK_API_KEY not found".to_string())
                })?
            } else {
                config.api_key.clone()
            };
            ("https://api.deepseek.com/chat/completions".to_string(), format!("Bearer {}", api_key))
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
            
        if config.use_microrent_proxy || env::var("USE_MICRORENT_PROXY").unwrap_or_else(|_| "0".to_string()) == "1" {
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

        use futures::StreamExt;
        use eventsource_stream::Eventsource;

        let stream = response.bytes_stream()
            .eventsource()
            .map(|event| {
                match event {
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
                }
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
                id: "deepseek-coder".to_string(),
                name: "DeepSeek Coder".to_string(),
                provider: "deepseek".to_string(),
                context_length: 128000,
            },
            AIModel {
                id: "deepseek-chat".to_string(),
                name: "DeepSeek Chat".to_string(),
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
            env::var("GLM_API_KEY").map_err(|_| {
                AppError::AIProviderError("GLM_API_KEY not found".to_string())
            })?
        } else {
            config.api_key.clone()
        };

        let url = "https://api.z.ai/api/paas/v4/chat/completions";

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

    async fn generate_stream(&self, prompt: &str, config: &AIConfig) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
        let api_key = if config.api_key.is_empty() {
            env::var("GLM_API_KEY").map_err(|_| {
                AppError::AIProviderError("GLM_API_KEY not found".to_string())
            })?
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

        use futures::StreamExt;
        use eventsource_stream::Eventsource;

        let stream = response.bytes_stream()
            .eventsource()
            .map(|event| {
                match event {
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
                }
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
                id: "glm-4".to_string(),
                name: "GLM-4".to_string(),
                provider: "glm".to_string(),
                context_length: 128000,
            },
            AIModel {
                id: "glm-3-turbo".to_string(),
                name: "GLM-3 Turbo".to_string(),
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
            env::var("GROK_API_KEY").map_err(|_| AppError::AIProviderError("GROK_API_KEY not found".to_string()))?
        } else {
            config.api_key.clone()
        };

        let request = serde_json::json!({
            "model": config.model,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": config.temperature,
            "max_tokens": config.max_tokens,
        });

        let response = self.client.post("https://api.x.ai/v1/chat/completions")
            .header("Authorization", format!("Bearer {}", api_key))
            .json(&request)
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        if !response.status().is_success() {
            return Err(AppError::AIRequestFailed(format!("Grok API error: {}", response.text().await.unwrap_or_default())));
        }

        let result: serde_json::Value = response.json().await.map_err(|e| AppError::AIRequestFailed(e.to_string()))?;
        Ok(result["choices"][0]["message"]["content"].as_str().unwrap_or("").to_string())
    }

    async fn generate_stream(&self, prompt: &str, config: &AIConfig) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
        let api_key = if config.api_key.is_empty() {
            env::var("GROK_API_KEY").map_err(|_| AppError::AIProviderError("GROK_API_KEY not found".to_string()))?
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

        let response = self.client.post("https://api.x.ai/v1/chat/completions")
            .header("Authorization", format!("Bearer {}", api_key))
            .json(&request)
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        use futures::StreamExt;
        use eventsource_stream::Eventsource;

        Ok(response.bytes_stream().eventsource().map(|event| {
            match event {
                Ok(event) => {
                    if event.data == "[DONE]" { return Ok("".to_string()); }
                    let json: serde_json::Value = serde_json::from_str(&event.data).map_err(|e| AppError::AIRequestFailed(e.to_string()))?;
                    Ok(json["choices"][0]["delta"]["content"].as_str().unwrap_or("").to_string())
                }
                Err(e) => Err(AppError::AIRequestFailed(e.to_string())),
            }
        }).boxed())
    }

    fn name(&self) -> &str { "grok" }
    fn models(&self) -> Vec<AIModel> {
        vec![AIModel { id: "grok-beta".to_string(), name: "Grok Beta".to_string(), provider: "grok".to_string(), context_length: 131072 }]
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
            env::var("QWEN_API_KEY").map_err(|_| AppError::AIProviderError("QWEN_API_KEY not found".to_string()))?
        } else {
            config.api_key.clone()
        };

        let request = serde_json::json!({
            "model": config.model,
            "input": { "messages": [{"role": "user", "content": prompt}] },
            "parameters": { "temperature": config.temperature, "max_tokens": config.max_tokens }
        });

        // DashScope API
        let response = self.client.post("https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation")
            .header("Authorization", format!("Bearer {}", api_key))
            .header("Content-Type", "application/json")
            .json(&request)
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        if !response.status().is_success() {
            return Err(AppError::AIRequestFailed(format!("Qwen API error: {}", response.text().await.unwrap_or_default())));
        }

        let result: serde_json::Value = response.json().await.map_err(|e| AppError::AIRequestFailed(e.to_string()))?;
        Ok(result["output"]["text"].as_str().unwrap_or("").to_string())
    }

    async fn generate_stream(&self, prompt: &str, config: &AIConfig) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
        let api_key = if config.api_key.is_empty() {
            env::var("QWEN_API_KEY").map_err(|_| AppError::AIProviderError("QWEN_API_KEY not found".to_string()))?
        } else {
            config.api_key.clone()
        };

        let request = serde_json::json!({
            "model": config.model,
            "input": { "messages": [{"role": "user", "content": prompt}] },
            "parameters": { "temperature": config.temperature, "max_tokens": config.max_tokens, "incremental_output": true }
        });

        let response = self.client.post("https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation")
            .header("Authorization", format!("Bearer {}", api_key))
            .header("X-DashScope-SSE", "enable")
            .header("Content-Type", "application/json")
            .json(&request)
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(e.to_string()))?;

        use futures::StreamExt;
        Ok(response.bytes_stream().map(|result| {
            match result {
                Ok(bytes) => {
                    let s = String::from_utf8_lossy(&bytes);
                    if s.contains("output") {
                        let json: serde_json::Value = serde_json::from_str(&s.replace("data:", "")).unwrap_or(serde_json::json!({}));
                        Ok(json["output"]["text"].as_str().unwrap_or("").to_string())
                    } else {
                        Ok("".to_string())
                    }
                }
                Err(e) => Err(AppError::AIRequestFailed(e.to_string())),
            }
        }).boxed())
    }

    fn name(&self) -> &str { "qwen" }
    fn models(&self) -> Vec<AIModel> {
        vec![
            AIModel { id: "qwen-max".to_string(), name: "Qwen Max".to_string(), provider: "qwen".to_string(), context_length: 30000 },
            AIModel { id: "qwen-plus".to_string(), name: "Qwen Plus".to_string(), provider: "qwen".to_string(), context_length: 30000 },
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
        
        let response = self.client.post(format!("{}/api/generate", url))
            .json(&request)
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(format!("Ollama connection failed (Is it running?): {}", e)))?;

        if !response.status().is_success() {
            return Err(AppError::AIRequestFailed(format!("Ollama API error: {}", response.text().await.unwrap_or_default())));
        }

        let result: serde_json::Value = response.json().await.map_err(|e| AppError::AIRequestFailed(e.to_string()))?;
        Ok(result["response"].as_str().unwrap_or("").to_string())
    }

    async fn generate_stream(&self, prompt: &str, config: &AIConfig) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
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

        let response = self.client.post(format!("{}/api/generate", url))
            .json(&request)
            .send()
            .await
            .map_err(|e| AppError::AIRequestFailed(format!("Ollama connection failed (Is it running?): {}", e)))?;

        use futures::StreamExt;
        
        Ok(response.bytes_stream().map(|result| {
            match result {
                Ok(bytes) => {
                    let s = String::from_utf8_lossy(&bytes);
                    let mut final_text = String::new();
                    // Ollama streams JSON-Lines. We might get multiple JSON objects in one chunk
                    for line in s.lines() {
                        if line.trim().is_empty() { continue; }
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
        }).boxed())
    }

    fn name(&self) -> &str { "ollama" }
    fn models(&self) -> Vec<AIModel> {
        vec![]
    }
}

// ==========================================
// Provider Factory
// ==========================================

pub fn get_provider(provider_name: &str) -> Result<Box<dyn AIProvider>> {
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
pub async fn refactor_stream(code: &str, instructions: &str, config: &AIConfig) -> Result<futures::stream::BoxStream<'static, Result<String>>> {
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
pub async fn transpile(code: &str, target_lang: &str, instructions: &str, config: &AIConfig) -> Result<String> {
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

/// List all available AI models
pub async fn list_models() -> Result<Vec<AIModel>> {
    let mut models = Vec::new();

    let providers: Vec<Box<dyn AIProvider>> = vec![
        Box::new(GeminiProvider::new()),
        Box::new(OpenAIProvider::new()),
        Box::new(ClaudeProvider::new()),
        Box::new(DeepSeekProvider::new()),
        Box::new(GLMProvider::new()),
        Box::new(GrokProvider::new()),
        Box::new(QwenProvider::new()),
    ];

    for provider in providers {
        models.extend(provider.models());
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
