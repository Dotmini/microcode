use std::sync::Arc;

#[derive(uniffi::Record)]
pub struct AgentConfig {
    pub workspace_path: String,
    pub vector_db_path: Option<String>,
    pub shell: Option<String>,
}

#[derive(uniffi::Record)]
pub struct EditResult {
    pub success: bool,
    pub message: String,
    pub replacements: u32,
}

#[derive(uniffi::Record)]
pub struct MicroSearchResult {
    pub file_path: String,
    pub content: String,
    pub score: f32,
    pub start_line: u32,
    pub end_line: u32,
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
    #[error("IO Error: {msg}")]
    Io { msg: String },
    #[error("PTY Error: {msg}")]
    Pty { msg: String },
    #[error("Embedding Error: {msg}")]
    Embedding { msg: String },
    #[error("Database Error: {msg}")]
    Database { msg: String },
    #[error("Parse Error: {msg}")]
    ParseError { msg: String },
    #[error("Edit Validation Error: {msg}")]
    EditValidation { msg: String },
    #[error("Not Initialized")]
    NotInitialized,
}

#[derive(uniffi::Object)]
pub struct MicroCore {
    config: AgentConfig,
}

#[uniffi::export]
impl MicroCore {
    #[uniffi::constructor]
    pub fn new(config: AgentConfig) -> Result<Arc<Self>, CoreError> {
        Ok(Arc::new(Self { config }))
    }

    pub fn apply_edit(
        &self,
        file_path: String,
        search_block: String,
        replace_block: String,
    ) -> Result<EditResult, CoreError> {
        // Stub
        Ok(EditResult {
            success: false,
            message: "Not implemented".to_string(),
            replacements: 0,
        })
    }

    pub fn clear_index(&self) -> Result<(), CoreError> {
        Ok(())
    }

    pub fn execute_command(&self, cmd: String) -> Result<String, CoreError> {
        Ok(format!("Stub: Executed '{}'", cmd))
    }

    pub fn get_index_stats(&self) -> Result<String, CoreError> {
        Ok("{}".to_string())
    }

    pub fn index_project(&self, path: String) -> Result<u32, CoreError> {
        Ok(0)
    }

    pub fn read_file(&self, file_path: String) -> Result<String, CoreError> {
        Ok("".to_string())
    }

    pub fn semantic_search(
        &self,
        query: String,
        limit: u32,
    ) -> Result<Vec<MicroSearchResult>, CoreError> {
        Ok(vec![])
    }

    pub fn write_file(&self, file_path: String, content: String) -> Result<(), CoreError> {
        Ok(())
    }
}

// MARK: - LLM Provider FFI Bridge

#[derive(Debug, Clone, uniffi::Enum)]
pub enum LlmProviderType {
    OpenAi,
    Anthropic,
    DeepSeek,
    Gemini,
    Grok,
    Codex,
}

/// FFI record for LLM initialization result
#[derive(uniffi::Record)]
pub struct LlmInitResult {
    pub success: bool,
    pub provider: String,
    pub message: String,
}

/// Initialize an LLM client with provider and token from Swift Keychain
/// Swift calls this after retrieving the key from Keychain
#[uniffi::export]
pub fn init_llm_client(provider: LlmProviderType, token: String) -> Result<LlmInitResult, CoreError> {
    if token.is_empty() {
        return Err(CoreError::Io { msg: "Token is empty".to_string() });
    }

    let provider_name = match provider {
        LlmProviderType::OpenAi => "openai",
        LlmProviderType::Anthropic => "anthropic",
        LlmProviderType::DeepSeek => "deepseek",
        LlmProviderType::Gemini => "gemini",
        LlmProviderType::Grok => "grok",
        LlmProviderType::Codex => "codex",
    };

    // Store in environment for backend HTTP server to pick up
    std::env::set_var(
        &format!("{}_API_KEY", provider_name.to_uppercase()),
        &token
    );

    Ok(LlmInitResult {
        success: true,
        provider: provider_name.to_string(),
        message: format!("{} client initialized with key {}...{}", 
            provider_name,
            &token[..token.len().min(4)],
            &token[token.len().saturating_sub(4)..]),
    })
}

/// Get available models for a provider
#[uniffi::export]
pub fn get_provider_models(provider: LlmProviderType) -> Vec<String> {
    match provider {
        LlmProviderType::OpenAi => vec![
            "gpt-4o".to_string(),
            "gpt-4o-mini".to_string(),
            "gpt-4.1".to_string(),
            "gpt-4.1-mini".to_string(),
            "o4-mini".to_string(),
        ],
        LlmProviderType::Anthropic => vec![
            "claude-sonnet-4-20250514".to_string(),
            "claude-3-5-sonnet-20241022".to_string(),
            "claude-3-5-haiku-20241022".to_string(),
        ],
        LlmProviderType::DeepSeek => vec![
            "deepseek-chat".to_string(),
            "deepseek-reasoner".to_string(),
        ],
        LlmProviderType::Gemini => vec![
            "gemini-2.5-flash".to_string(),
            "gemini-2.5-pro".to_string(),
            "gemini-2.0-flash".to_string(),
        ],
        LlmProviderType::Grok => vec![
            "grok-3".to_string(),
            "grok-3-mini".to_string(),
        ],
        LlmProviderType::Codex => vec![
            "codex-mini-latest".to_string(),
            "o4-mini".to_string(),
        ],
    }
}
