//! Google Gemini LLM Provider
//!
//! Handles generateContentStream for Gemini 2.5 Flash/Pro
//!
//! Copyright © 2025 SPU AI CLUB — Dotmini Software

use async_trait::async_trait;
use futures::Stream;
use std::pin::Pin;
use super::{LlmProvider, LlmError, ChatMessage, McpContext};

pub struct GeminiProvider {
    api_key: String,
    client: reqwest::Client,
}

impl GeminiProvider {
    pub fn new(api_key: String) -> Self {
        Self {
            api_key,
            client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(120))
                .build()
                .unwrap_or_default(),
        }
    }
}

#[async_trait]
impl LlmProvider for GeminiProvider {
    fn name(&self) -> &str { "Gemini" }

    async fn stream_completion(
        &self,
        messages: &[ChatMessage],
        system_prompt: &str,
        context: &McpContext,
        model: &str,
        _max_tokens: u32,
    ) -> Result<Pin<Box<dyn Stream<Item = Result<String, LlmError>> + Send>>, LlmError> {
        let ctx_str = context.to_context_string();
        let full_system = if ctx_str.is_empty() {
            system_prompt.to_string()
        } else {
            format!("{}\n\n{}", system_prompt, ctx_str)
        };

        // Build Gemini contents format
        let mut contents: Vec<serde_json::Value> = Vec::new();
        for msg in messages {
            if msg.role == "system" { continue; }
            let role = if msg.role == "user" { "user" } else { "model" };
            contents.push(serde_json::json!({
                "role": role,
                "parts": [{"text": msg.content}]
            }));
        }

        let body = serde_json::json!({
            "contents": contents,
            "systemInstruction": {
                "parts": [{"text": full_system}]
            },
            "generationConfig": {
                "temperature": 0.7,
                "topP": 0.95,
            }
        });

        let url = format!(
            "https://generativelanguage.googleapis.com/v1beta/models/{}:streamGenerateContent?alt=sse&key={}",
            model, self.api_key
        );

        let response = self.client
            .post(&url)
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
                        
                        while let Some(pos) = buffer.find("\n\n") {
                            let event_str = buffer[..pos].to_string();
                            buffer = buffer[pos + 2..].to_string();
                            
                            for line in event_str.lines() {
                                if line.starts_with("data: ") {
                                    let data = &line[6..];
                                    if let Ok(json) = serde_json::from_str::<serde_json::Value>(data) {
                                        if let Some(candidates) = json["candidates"].as_array() {
                                            for candidate in candidates {
                                                if let Some(parts) = candidate["content"]["parts"].as_array() {
                                                    for part in parts {
                                                        if let Some(text) = part["text"].as_str() {
                                                            yield Ok(text.to_string());
                                                        }
                                                    }
                                                }
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
        let url = format!(
            "https://generativelanguage.googleapis.com/v1beta/models?key={}",
            self.api_key
        );
        let response = self.client.get(&url).send().await?;
        Ok(response.status().is_success())
    }
}
