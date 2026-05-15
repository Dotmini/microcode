//! Application state management for MicroCode Backend

use crate::models::AIConfig;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

/// Global application state
#[derive(Debug, Clone)]
pub struct AppState {
    /// AI configuration
    pub ai_config: AIConfig,

    /// Active code executions
    pub executions: Arc<RwLock<HashMap<String, ExecutionInfo>>>,

    /// File watchers
    pub watchers: Arc<RwLock<HashMap<String, WatcherInfo>>>,

    /// Configuration settings
    pub config: Arc<RwLock<AppConfig>>,
    
    /// Remote Connections Manager
    pub remote_manager: crate::remote::RemoteConnectionManager,

    /// Node.js Settings
    pub node_settings: Arc<RwLock<crate::nodejs::NodeSettings>>,

    /// Fast Tier Hybrid AI Engine
    pub fast_tier: Arc<tokio::sync::Mutex<Option<crate::ai_engine::fast_tier::FastTierEngine>>>,
    
    /// Smart Tier (Vector Store)
    pub smart_tier: Arc<tokio::sync::Mutex<Option<crate::ai_engine::smart_tier::SmartTierEngine>>>,
    
    /// AI Agent RAG Engine
    pub rag_engine: Arc<tokio::sync::Mutex<Option<crate::rag::RagEngine>>>,
    
    /// DataFrames Manager
    pub data_frames: crate::data::dataframe::DataFrameManager,
    pub terminal_manager: std::sync::Arc<crate::terminal::TerminalManager>,
    
    /// Pipeline Engine (Local CI/CD)
    pub pipeline_engine: crate::pipeline::PipelineEngine,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            ai_config: AIConfig::default(),
            executions: Arc::new(RwLock::new(HashMap::new())),
            watchers: Arc::new(RwLock::new(HashMap::new())),
            config: Arc::new(RwLock::new(AppConfig::default())),
            remote_manager: crate::remote::RemoteConnectionManager::new(),
            node_settings: Arc::new(RwLock::new(crate::nodejs::NodeSettings::default())),
            fast_tier: Arc::new(tokio::sync::Mutex::new(None)),
            smart_tier: Arc::new(tokio::sync::Mutex::new(None)),
            rag_engine: Arc::new(tokio::sync::Mutex::new(None)),
            data_frames: crate::data::dataframe::DataFrameManager::new(),
            terminal_manager: std::sync::Arc::new(crate::terminal::TerminalManager::new()),
            pipeline_engine: crate::pipeline::PipelineEngine::new(),
        }
    }

    /// Register a new code execution
    pub async fn register_execution(&self, info: ExecutionInfo) -> String {
        let id = Uuid::new_v4().to_string();
        let mut executions = self.executions.write().await;
        executions.insert(id.clone(), info);
        id
    }

    /// Remove an execution by ID
    pub async fn remove_execution(&self, id: &str) -> Option<ExecutionInfo> {
        let mut executions = self.executions.write().await;
        executions.remove(id)
    }

    /// Get execution info by ID
    pub async fn get_execution(&self, id: &str) -> Option<ExecutionInfo> {
        let executions = self.executions.read().await;
        executions.get(id).cloned()
    }

    /// Register a file watcher
    pub async fn register_watcher(&self, path: String, info: WatcherInfo) {
        let mut watchers = self.watchers.write().await;
        watchers.insert(path, info);
    }

    /// Remove a file watcher
    pub async fn remove_watcher(&self, path: &str) -> Option<WatcherInfo> {
        let mut watchers = self.watchers.write().await;
        watchers.remove(path)
    }
}

impl Default for AppState {
    fn default() -> Self {
        Self::new()
    }
}

/// Information about an active code execution
#[derive(Debug, Clone)]
pub struct ExecutionInfo {
    pub language: String,
    pub code: String,
    pub started_at: chrono::DateTime<chrono::Utc>,
    pub process_id: Option<u32>,
}

impl ExecutionInfo {
    pub fn new(language: String, code: String) -> Self {
        Self {
            language,
            code,
            started_at: chrono::Utc::now(),
            process_id: None,
        }
    }
}

/// Information about a file watcher
#[derive(Debug, Clone)]
pub struct WatcherInfo {
    pub path: String,
    pub recursive: bool,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

impl WatcherInfo {
    pub fn new(path: String, recursive: bool) -> Self {
        Self {
            path,
            recursive,
            created_at: chrono::Utc::now(),
        }
    }
}

/// Application configuration
#[derive(Debug, Clone)]
pub struct AppConfig {
    pub editor: EditorConfig,
    pub ai: AIProviderConfig,
    pub git: GitConfig,
    pub execution: ExecutionConfig,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            editor: EditorConfig::default(),
            ai: AIProviderConfig::default(),
            git: GitConfig::default(),
            execution: ExecutionConfig::default(),
        }
    }
}

/// Editor configuration
#[derive(Debug, Clone)]
pub struct EditorConfig {
    pub tab_size: usize,
    pub use_spaces: bool,
    pub auto_save: bool,
    pub auto_save_delay: u64,
    pub line_wrap: bool,
    pub show_line_numbers: bool,
    pub highlight_current_line: bool,
    pub font_family: String,
    pub font_size: u32,
    pub theme: String,
}

impl Default for EditorConfig {
    fn default() -> Self {
        Self {
            tab_size: 4,
            use_spaces: true,
            auto_save: false,
            auto_save_delay: 1000,
            line_wrap: false,
            show_line_numbers: true,
            highlight_current_line: true,
            font_family: "SF Mono".to_string(),
            font_size: 13,
            theme: "default".to_string(),
        }
    }
}

/// AI provider configuration
#[derive(Debug, Clone)]
pub struct AIProviderConfig {
    pub providers: Vec<AIProviderInfo>,
    pub default_provider: String,
}

impl Default for AIProviderConfig {
    fn default() -> Self {
        Self {
            providers: vec![],
            default_provider: "gemini".to_string(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct AIProviderInfo {
    pub name: String,
    pub api_key: Option<String>,
    pub enabled: bool,
}

/// Git configuration
#[derive(Debug, Clone)]
pub struct GitConfig {
    pub auto_fetch: bool,
    pub fetch_interval: u64,
    pub default_remote: String,
    pub user_name: Option<String>,
    pub user_email: Option<String>,
}

impl Default for GitConfig {
    fn default() -> Self {
        Self {
            auto_fetch: false,
            fetch_interval: 300,
            default_remote: "origin".to_string(),
            user_name: None,
            user_email: None,
        }
    }
}

/// Execution configuration
#[derive(Debug, Clone)]
pub struct ExecutionConfig {
    pub timeout: u64,
    pub max_memory: Option<u64>,
    pub python_path: Option<String>,
    pub node_path: Option<String>,
    pub rust_path: Option<String>,
}

impl Default for ExecutionConfig {
    fn default() -> Self {
        Self {
            timeout: 30000, // 30 seconds
            max_memory: None,
            python_path: None,
            node_path: None,
            rust_path: None,
        }
    }
}

impl Default for AIConfig {
    fn default() -> Self {
        Self {
            provider: "gemini".to_string(),
            model: "gemini-3-pro-preview".to_string(),
            api_key: std::env::var("GEMINI_API_KEY").unwrap_or_default(),
            temperature: 0.7,
            max_tokens: 2048,
            microrent_token: None,
            use_microrent_proxy: false,
        }
    }
}
