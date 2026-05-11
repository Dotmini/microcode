//! MicroCode AI Core - The Brain of MicroCode IDE
//! 
//! This crate provides:
//! - Terminal command execution (The Hands)
//! - File editing with search/replace (The Tools)
//! - RAG engine for semantic code search (The Memory)
//!
//! Copyright © 2026 Dotmini Software. All rights reserved.

use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::Arc;
use anyhow::Result;
use thiserror::Error;
use tokio::sync::RwLock;

mod fs_editor;
mod rag_engine;
mod llm_client;

pub use fs_editor::FileEditor;
pub use rag_engine::RagEngine;

// ============================================================================
// Error Types
// ============================================================================

#[derive(Error, Debug, uniffi::Error)]
pub enum CoreError {
    #[error("I/O error: {msg}")]
    Io { msg: String },
    
    #[error("PTY error: {msg}")]
    Pty { msg: String },
    
    #[error("Embedding error: {msg}")]
    Embedding { msg: String },
    
    #[error("Database error: {msg}")]
    Database { msg: String },
    
    #[error("Parse error: {msg}")]
    ParseError { msg: String },
    
    #[error("Edit validation error: {msg}")]
    EditValidation { msg: String },
    
    #[error("Not initialized")]
    NotInitialized,
}

impl From<std::io::Error> for CoreError {
    fn from(e: std::io::Error) -> Self {
        CoreError::Io { msg: e.to_string() }
    }
}

// ============================================================================
// Configuration
// ============================================================================

#[derive(Debug, Clone, uniffi::Record)]
pub struct AgentConfig {
    pub workspace_path: String,
    pub vector_db_path: Option<String>,
    pub shell: Option<String>,
}

// ============================================================================
// Result Types
// ============================================================================

#[derive(Debug, Clone, uniffi::Record)]
pub struct SearchResult {
    pub file_path: String,
    pub content: String,
    pub score: f32,
    pub start_line: u32,
    pub end_line: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct EditResult {
    pub success: bool,
    pub message: String,
    pub replacements: u32,
}

// ============================================================================
// MicroCore - Main Interface
// ============================================================================

#[derive(uniffi::Object)]
pub struct MicroCore {
    config: AgentConfig,
    file_editor: FileEditor,
    rag_engine: Arc<RwLock<RagEngine>>,
}

#[uniffi::export]
impl MicroCore {
    /// Create a new MicroCore instance
    #[uniffi::constructor]
    pub fn new(config: AgentConfig) -> Result<Self, CoreError> {
        let workspace = PathBuf::from(&config.workspace_path);
        
        // Validate workspace exists
        if !workspace.exists() {
            return Err(CoreError::Io {
                msg: format!("Workspace path does not exist: {}", config.workspace_path)
            });
        }
        
        // Initialize file editor
        let file_editor = FileEditor::new(workspace.clone());
        
        // Determine vector DB path
        let vector_db_path = config.vector_db_path.clone()
            .unwrap_or_else(|| {
                workspace.join(".microcode").join("vectors")
                    .to_string_lossy().to_string()
            });
        
        // Initialize RAG engine
        let rag_engine = RagEngine::new(&vector_db_path);
        
        Ok(Self {
            config,
            file_editor,
            rag_engine: Arc::new(RwLock::new(rag_engine)),
        })
    }
    
    // ========================================================================
    // Terminal (The Hands) - Synchronous for MVP
    // ========================================================================
    
    /// Execute a command and return output
    pub fn execute_command(&self, cmd: String) -> Result<String, CoreError> {
        let shell = self.config.shell.clone()
            .unwrap_or_else(|| "/bin/zsh".to_string());
        
        let output = Command::new(&shell)
            .arg("-c")
            .arg(&cmd)
            .current_dir(&self.config.workspace_path)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .map_err(|e| CoreError::Pty { msg: e.to_string() })?;
        
        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        
        if output.status.success() {
            Ok(stdout.to_string())
        } else {
            Ok(format!("{}\n{}", stdout, stderr))
        }
    }
    
    // ========================================================================
    // File Editing (The Tools)
    // ========================================================================
    
    /// Apply a search-and-replace edit to a file
    pub fn apply_edit(
        &self,
        file_path: String,
        search_block: String,
        replace_block: String,
    ) -> Result<EditResult, CoreError> {
        self.file_editor.apply_edit(&file_path, &search_block, &replace_block)
    }
    
    /// Read file contents
    pub fn read_file(&self, file_path: String) -> Result<String, CoreError> {
        self.file_editor.read_file(&file_path)
    }
    
    /// Write file contents
    pub fn write_file(&self, file_path: String, content: String) -> Result<(), CoreError> {
        self.file_editor.write_file(&file_path, &content)
    }
    
    // ========================================================================
    // RAG (The Memory)
    // ========================================================================
    
    /// Index a project directory for semantic search
    pub fn index_project(&self, path: String) -> Result<u32, CoreError> {
        let rt = tokio::runtime::Runtime::new()
            .map_err(|e| CoreError::Io { msg: e.to_string() })?;
        
        rt.block_on(async {
            let mut rag = self.rag_engine.write().await;
            rag.index_directory(&path).await
                .map_err(|e| CoreError::Database { msg: e.to_string() })
        })
    }
    
    /// Perform semantic search on indexed codebase
    pub fn semantic_search(&self, query: String, limit: u32) -> Result<Vec<SearchResult>, CoreError> {
        let rt = tokio::runtime::Runtime::new()
            .map_err(|e| CoreError::Io { msg: e.to_string() })?;
        
        rt.block_on(async {
            let rag = self.rag_engine.read().await;
            rag.search(&query, limit as usize).await
                .map_err(|e| CoreError::Database { msg: e.to_string() })
        })
    }
    
    /// Clear the vector database
    pub fn clear_index(&self) -> Result<(), CoreError> {
        let rt = tokio::runtime::Runtime::new()
            .map_err(|e| CoreError::Io { msg: e.to_string() })?;
        
        rt.block_on(async {
            let mut rag = self.rag_engine.write().await;
            rag.clear().await
                .map_err(|e| CoreError::Database { msg: e.to_string() })
        })
    }
    
    /// Get indexing statistics as JSON
    pub fn get_index_stats(&self) -> Result<String, CoreError> {
        let rt = tokio::runtime::Runtime::new()
            .map_err(|e| CoreError::Io { msg: e.to_string() })?;
        
        rt.block_on(async {
            let rag = self.rag_engine.read().await;
            rag.stats().await
                .map_err(|e| CoreError::Database { msg: e.to_string() })
        })
    }
}

// ============================================================================
// System Kernel - Hardware & OS Level Controls via FFI
// ============================================================================

/// Change the power profile mode directly without IPC overhead
#[uniffi::export]
pub fn set_kernel_power_mode(mode: String) -> Result<(), CoreError> {
    println!("[Rust FFI] Setting kernel power mode to: {}", mode);
    // Implementation for setting CPU governor or scheduling priorities
    Ok(())
}

/// Trigger a kernel panic to test crash handlers
#[uniffi::export]
pub fn trigger_kernel_panic() {
    println!("[Rust FFI] 🚨 Testing Kernel Panic from FFI!");
}

/// Get low-level network status
#[uniffi::export]
pub fn get_kernel_network_status() -> String {
    "Online (FFI)".to_string()
}

// ============================================================================
// UniFFI Scaffolding
// ============================================================================

uniffi::setup_scaffolding!();
