//! Anthropic (Claude) LLM Provider
//!
//! Handles Messages API and Anthropic's specific SSE format
//! Supports: Claude Sonnet 4, Claude 3.5 Sonnet/Haiku/Opus
//!
//! Copyright © 2025 SPU AI CLUB — Dotmini Software

use super::{ChatMessage, LlmError, LlmProvider, McpContext};
use async_trait::async_trait;
use futures::Stream;
use std::pin::Pin;

pub struct AnthropicProvider {
    api_key: String,
    client: reqwest::Client,
}

impl AnthropicProvider {
    pub fn new(api_key: String) -> Self {
        Self {
            api_key,
            client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(300))
                .build()
                .unwrap_or_default(),
        }
    }
}

#[async_trait]
impl LlmProvider for AnthropicProvider {
    fn name(&self) -> &str {
        "Anthropic"
    }

    async fn stream_completion(
        &self,
        messages: &[ChatMessage],
        system_prompt: &str,
        context: &McpContext,
        model: &str,
        max_tokens: u32,
    ) -> Result<Pin<Box<dyn Stream<Item = Result<String, LlmError>> + Send>>, LlmError> {
        // Build enhanced system prompt with MCP context
        let ctx_str = context.to_context_string();
        let full_system = if ctx_str.is_empty() {
            system_prompt.to_string()
        } else {
            format!("{}\n\n{}", system_prompt, ctx_str)
        };

        // Build Anthropic messages (filter out system role)
        let api_messages: Vec<serde_json::Value> = messages
            .iter()
            .filter(|m| m.role != "system")
            .map(|m| {
                serde_json::json!({
                    "role": if m.role == "user" { "user" } else { "assistant" },
                    "content": m.content
                })
            })
            .collect();

        let body = serde_json::json!({
            "model": model,
            "max_tokens": max_tokens,
            "system": full_system,
            "messages": api_messages,
            "stream": true
        });

        let response = self
            .client
            .post("https://api.anthropic.com/v1/messages")
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", "2023-06-01")
            .header("content-type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| LlmError::Http(e.to_string()))?;

        if !response.status().is_success() {
            let status = response.status().as_u16();
            let text = response.text().await.unwrap_or_default();
            if status == 429 {
                return Err(LlmError::RateLimited {
                    retry_after_ms: 5000,
                });
            }
            return Err(LlmError::Api {
                code: status,
                message: text,
            });
        }

        // Parse Anthropic SSE stream
        let byte_stream = response.bytes_stream();
        let stream = async_stream::stream! {
            use futures::StreamExt;
            let mut byte_stream = byte_stream;
            let mut buffer = String::new();

            while let Some(chunk) = byte_stream.next().await {
                match chunk {
                    Ok(bytes) => {
                        buffer.push_str(&String::from_utf8_lossy(&bytes));

                        // Process complete SSE events
                        while let Some(pos) = buffer.find("\n\n") {
                            let event_str = buffer[..pos].to_string();
                            buffer = buffer[pos + 2..].to_string();

                            // Parse event type and data
                            for line in event_str.lines() {
                                if line.starts_with("data: ") {
                                    let data = &line[6..];
                                    if data == "[DONE]" { break; }

                                    if let Ok(json) = serde_json::from_str::<serde_json::Value>(data) {
                                        // content_block_delta
                                        if json["type"] == "content_block_delta" {
                                            if let Some(text) = json["delta"]["text"].as_str() {
                                                yield Ok(text.to_string());
                                            }
                                        }
                                        // Error event
                                        if json["type"] == "error" {
                                            let msg = json["error"]["message"].as_str().unwrap_or("Unknown error");
                                            yield Err(LlmError::Api { code: 500, message: msg.to_string() });
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
        let body = serde_json::json!({
            "model": "claude-3-5-haiku-20241022",
            "max_tokens": 1,
            "messages": [{"role": "user", "content": "hi"}]
        });

        let response = self
            .client
            .post("https://api.anthropic.com/v1/messages")
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", "2023-06-01")
            .header("content-type", "application/json")
            .json(&body)
            .send()
            .await?;

        Ok(response.status().is_success())
    }
}
