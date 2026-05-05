//! Unified LLM Provider Trait
//!
//! Async trait abstraction for multiple AI API providers
//! Supports: Anthropic (Claude), Google Gemini, OpenAI (GPT/Codex)
//!
//! Copyright © 2025 SPU AI CLUB — Dotmini Software

use async_trait::async_trait;
use futures::Stream;
use serde::{Deserialize, Serialize};
use std::pin::Pin;

pub mod anthropic;
pub mod gemini;
pub mod openai;

// MARK: - Error Types

#[derive(Debug, thiserror::Error)]
pub enum LlmError {
    #[error("HTTP error: {0}")]
    Http(String),
    #[error("API error: {code} - {message}")]
    Api { code: u16, message: String },
    #[error("Parse error: {0}")]
    Parse(String),
    #[error("Auth error: {0}")]
    Auth(String),
    #[error("Rate limited: retry after {retry_after_ms}ms")]
    RateLimited { retry_after_ms: u64 },
    #[error("Stream error: {0}")]
    Stream(String),
    #[error("Timeout")]
    Timeout,
    #[error("Provider not configured")]
    NotConfigured,
}

impl From<reqwest::Error> for LlmError {
    fn from(e: reqwest::Error) -> Self {
        LlmError::Http(e.to_string())
    }
}

// MARK: - MCP Context (injected into prompts)

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct McpContext {
    /// Workspace files read via MCP resources/read
    pub resources: Vec<McpResource>,
    /// Tool results from previous MCP tool calls
    pub tool_results: Vec<McpToolResult>,
    /// Active file path
    pub active_file: Option<String>,
    /// Active file content
    pub active_content: Option<String>,
    /// Workspace root
    pub workspace_root: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpResource {
    pub uri: String,
    pub content: String,
    pub mime_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpToolResult {
    pub tool_name: String,
    pub result: String,
    pub success: bool,
}

impl McpContext {
    /// Build context string for injection into LLM prompt
    pub fn to_context_string(&self) -> String {
        let mut parts = Vec::new();

        if let Some(ref file) = self.active_file {
            parts.push(format!("[Active File: {}]", file));
        }
        if let Some(ref content) = self.active_content {
            let truncated = if content.len() > 8000 {
                format!("{}...[truncated]", &content[..8000])
            } else {
                content.clone()
            };
            parts.push(format!("[File Content]\n{}", truncated));
        }

        for res in &self.resources {
            parts.push(format!("[MCP Resource: {}]\n{}", res.uri, res.content));
        }

        for tr in &self.tool_results {
            let status = if tr.success { "OK" } else { "FAIL" };
            parts.push(format!("[Tool: {} ({})] {}", tr.tool_name, status, tr.result));
        }

        parts.join("\n\n")
    }
}

// MARK: - Message Types

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub role: String,      // "system", "user", "assistant"
    pub content: String,
}

// MARK: - Provider Trait

#[async_trait]
pub trait LlmProvider: Send + Sync {
    /// Provider name for display
    fn name(&self) -> &str;

    /// Stream completion from the LLM
    async fn stream_completion(
        &self,
        messages: &[ChatMessage],
        system_prompt: &str,
        context: &McpContext,
        model: &str,
        max_tokens: u32,
    ) -> Result<Pin<Box<dyn Stream<Item = Result<String, LlmError>> + Send>>, LlmError>;

    /// Non-streaming completion (for tool loops)
    async fn completion(
        &self,
        messages: &[ChatMessage],
        system_prompt: &str,
        context: &McpContext,
        model: &str,
        max_tokens: u32,
    ) -> Result<String, LlmError> {
        use futures::StreamExt;
        let mut stream = self.stream_completion(messages, system_prompt, context, model, max_tokens).await?;
        let mut result = String::new();
        while let Some(chunk) = stream.next().await {
            match chunk {
                Ok(text) => result.push_str(&text),
                Err(e) => return Err(e),
            }
        }
        Ok(result)
    }

    /// Validate the API key
    async fn validate_key(&self) -> Result<bool, LlmError>;
}

// MARK: - Provider Registry

pub struct ProviderRegistry {
    providers: std::collections::HashMap<String, Box<dyn LlmProvider>>,
}

impl ProviderRegistry {
    pub fn new() -> Self {
        Self {
            providers: std::collections::HashMap::new(),
        }
    }

    pub fn register(&mut self, name: &str, provider: Box<dyn LlmProvider>) {
        self.providers.insert(name.to_string(), provider);
    }

    pub fn get(&self, name: &str) -> Option<&dyn LlmProvider> {
        self.providers.get(name).map(|p| p.as_ref())
    }

    pub fn list(&self) -> Vec<&str> {
        self.providers.keys().map(|k| k.as_str()).collect()
    }

    /// Initialize all providers from environment or passed keys
    pub fn init_from_keys(keys: std::collections::HashMap<String, String>) -> Self {
        let mut registry = Self::new();

        if let Some(key) = keys.get("anthropic") {
            if !key.is_empty() {
                registry.register("anthropic", Box::new(anthropic::AnthropicProvider::new(key.clone())));
            }
        }
        if let Some(key) = keys.get("gemini") {
            if !key.is_empty() {
                registry.register("gemini", Box::new(gemini::GeminiProvider::new(key.clone())));
            }
        }
        if let Some(key) = keys.get("openai") {
            if !key.is_empty() {
                registry.register("openai", Box::new(openai::OpenAIProvider::new(key.clone())));
            }
        }

        registry
    }
}
