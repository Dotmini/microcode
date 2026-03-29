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
