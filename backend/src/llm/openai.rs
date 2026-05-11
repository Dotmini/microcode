//! OpenAI LLM Provider
//!
//! Handles /v1/chat/completions for GPT-4o, Codex, o-series
//!
//! Copyright © 2025 SPU AI CLUB — Dotmini Software

use async_trait::async_trait;
use futures::Stream;
use std::pin::Pin;
use super::{LlmProvider, LlmError, ChatMessage, McpContext};

pub struct OpenAIProvider {
    api_key: String,
    client: reqwest::Client,
    base_url: String,
}

impl OpenAIProvider {
    pub fn new(api_key: String) -> Self {
        Self {
            api_key,
            client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(300))
                .build()
                .unwrap_or_default(),
            base_url: "https://api.openai.com/v1".to_string(),
        }
    }

    /// Create with custom base URL (for DeepSeek, Grok, etc.)
    pub fn with_base_url(api_key: String, base_url: String) -> Self {
        Self {
            api_key,
            client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(300))
                .build()
                .unwrap_or_default(),
            base_url,
        }
    }
}

#[async_trait]
impl LlmProvider for OpenAIProvider {
    fn name(&self) -> &str { "OpenAI" }

    async fn stream_completion(
        &self,
        messages: &[ChatMessage],
        system_prompt: &str,
        context: &McpContext,
        model: &str,
        max_tokens: u32,
    ) -> Result<Pin<Box<dyn Stream<Item = Result<String, LlmError>> + Send>>, LlmError> {
        let ctx_str = context.to_context_string();
        let full_system = if ctx_str.is_empty() {
            system_prompt.to_string()
        } else {
            format!("{}\n\n{}", system_prompt, ctx_str)
        };

        // Build OpenAI messages format
        let mut api_messages = vec![
            serde_json::json!({"role": "system", "content": full_system})
        ];
        for msg in messages {
            if msg.role == "system" { continue; }
            api_messages.push(serde_json::json!({
                "role": msg.role,
                "content": msg.content
            }));
        }

        let body = serde_json::json!({
            "model": model,
            "messages": api_messages,
            "max_tokens": max_tokens,
            "stream": true,
            "temperature": 0.7,
        });

        let url = format!("{}/chat/completions", self.base_url);

        let response = self.client
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("content-type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| LlmError::Http(e.to_string()))?;

        if !response.status().is_success() {
            let status = response.status().as_u16();
            let text = response.text().await.unwrap_or_default();
            if status == 429 {
                return Err(LlmError::RateLimited { retry_after_ms: 5000 });
            }
            return Err(LlmError::Api { code: status, message: text });
        }

        let byte_stream = response.bytes_stream();
        let stream = async_stream::stream! {
            use futures::StreamExt;
            let mut byte_stream = byte_stream;
            let mut buffer = String::new();

            while let Some(chunk) = byte_stream.next().await {
                match chunk {
                    Ok(bytes) => {
                        buffer.push_str(&String::from_utf8_lossy(&bytes));
                        
                        // Process SSE lines
                        while let Some(pos) = buffer.find("\n") {
                            let line = buffer[..pos].to_string();
                            buffer = buffer[pos + 1..].to_string();
                            
                            let line = line.trim();
                            if line.is_empty() { continue; }
                            
                            if line.starts_with("data: ") {
                                let data = &line[6..];
                                if data == "[DONE]" { break; }
                                
                                if let Ok(json) = serde_json::from_str::<serde_json::Value>(data) {
                                    if let Some(choices) = json["choices"].as_array() {
                                        for choice in choices {
                                            if let Some(text) = choice["delta"]["content"].as_str() {
                                                yield Ok(text.to_string());
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Err(e) => {
                        yield Err(LlmError::Stream(e.to_string()));
                        break;
                    }
                }
            }
        };

        Ok(Box::pin(stream))
    }

    async fn validate_key(&self) -> Result<bool, LlmError> {
        let url = format!("{}/models", self.base_url);
        let response = self.client
            .get(&url)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .send()
            .await?;
        Ok(response.status().is_success())
    }
}
