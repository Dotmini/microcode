//! Data models for MicroCode Backend
//!
//! Request and response types for the API

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// ==========================================
// Common Types
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatusResponse {
    pub success: bool,
    pub message: String,
}

// ==========================================
// File Operations
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ListFilesRequest {
    pub path: String,
    #[serde(default)]
    pub recursive: bool,
    #[serde(default)]
    pub include_hidden: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileInfo {
    pub name: String,
    pub path: String,
    pub is_directory: bool,
    pub size: u64,
    pub modified: Option<String>,
    pub extension: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ListFilesResponse {
    pub files: Vec<FileInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReadFileRequest {
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReadFileResponse {
    pub content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WriteFileRequest {
    pub path: String,
    pub content: String,
    #[serde(default)]
    pub create_dirs: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeleteFileRequest {
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateDirectoryRequest {
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateDirectoryResponse {
    pub success: bool,
    pub message: String,
}

// ==========================================
// Code Operations
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalyzeCodeRequest {
    pub code: String,
    pub language: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CodeAnalysis {
    pub language: String,
    pub lines: usize,
    pub functions: Vec<FunctionInfo>,
    pub classes: Vec<ClassInfo>,
    pub imports: Vec<String>,
    pub complexity: Option<usize>,
    pub issues: Vec<CodeIssue>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FunctionInfo {
    pub name: String,
    pub line: usize,
    pub parameters: Vec<String>,
    pub return_type: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClassInfo {
    pub name: String,
    pub line: usize,
    pub methods: Vec<String>,
    pub properties: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CodeIssue {
    pub severity: String,
    pub message: String,
    pub line: usize,
    pub column: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalyzeCodeResponse {
    pub analysis: CodeAnalysis,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FormatCodeRequest {
    pub code: String,
    pub language: String,
    #[serde(default)]
    pub options: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FormatCodeResponse {
    pub code: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HighlightCodeRequest {
    pub code: String,
    pub language: String,
    #[serde(default)]
    pub theme: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HighlightToken {
    pub text: String,
    pub token_type: String,
    pub start: usize,
    pub end: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HighlightCodeResponse {
    pub tokens: Vec<HighlightToken>,
}

// ==========================================
// AI Operations
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIConfig {
    pub provider: String, // "gemini", "openai", "anthropic"
    pub model: String,
    pub api_key: String,
    #[serde(default)]
    pub temperature: f32,
    #[serde(default)]
    pub max_tokens: usize,
    #[serde(default)]
    pub use_microrent_proxy: bool,
    #[serde(default)]
    pub microrent_token: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIRefactorRequest {
    pub code: String,
    pub instructions: String,
    #[serde(default)]
    pub language: String,
    #[serde(default)]
    pub provider: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub api_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIRefactorResponse {
    pub code: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIRefactorUltraRequest {
    pub files: Vec<FileContent>,
    pub instructions: String,
    pub target_language: Option<String>,
    pub provider: Option<String>,
    pub model: Option<String>,
    pub api_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileContent {
    pub path: String,
    pub content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIRefactorUltraResponse {
    pub refactored_files: Vec<FileContent>,
    pub report_summary: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIRefactorReportRequest {
    pub source_code: String,
    pub refactored_code: String,
    pub source_language: String,
    pub target_language: String,
    pub changes: Vec<String>,
    pub recommendations: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIExplainRequest {
    pub code: String,
    #[serde(default)]
    pub language: String,
    #[serde(default)]
    pub provider: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub api_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIExplainResponse {
    pub explanation: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AICompleteRequest {
    pub code: String,
    pub context: String,
    #[serde(default)]
    pub language: String,
    #[serde(default)]
    pub provider: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub api_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AICompleteResponse {
    pub completion: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AITranspileRequest {
    pub code: String,
    pub target_language: String,
    pub instructions: String,
    #[serde(default)]
    pub provider: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub api_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AITranspileResponse {
    pub code: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIModel {
    pub id: String,
    pub name: String,
    pub provider: String,
    pub context_length: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIModelsResponse {
    pub models: Vec<AIModel>,
}

// ==========================================
// Git Operations
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitStatusRequest {
    pub repo_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitFileStatus {
    pub path: String,
    pub status: String, // "modified", "added", "deleted", "untracked"
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitStatus {
    pub branch: String,
    pub files: Vec<GitFileStatus>,
    pub ahead: usize,
    pub behind: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitStatusResponse {
    pub status: GitStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitCommitRequest {
    pub repo_path: String,
    pub message: String,
    #[serde(default)]
    pub files: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitPushRequest {
    pub repo_path: String,
    #[serde(default)]
    pub remote: String,
    #[serde(default)]
    pub branch: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitPullRequest {
    pub repo_path: String,
    #[serde(default)]
    pub remote: String,
    #[serde(default)]
    pub branch: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitLogRequest {
    pub repo_path: String,
    #[serde(default = "default_log_limit")]
    pub limit: usize,
}

fn default_log_limit() -> usize {
    50
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitCommit {
    pub hash: String,
    pub author: String,
    pub email: String,
    pub message: String,
    pub timestamp: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitLogResponse {
    pub commits: Vec<GitCommit>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitDiffRequest {
    pub repo_path: String,
    #[serde(default)]
    pub file_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitDiffResponse {
    pub diff: String,
}

// ==========================================
// Code Execution
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecuteCodeRequest {
    pub code: String,
    pub language: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub env: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionOutput {
    pub stdout: String,
    pub stderr: String,
    pub exit_code: i32,
    pub execution_time: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecuteCodeResponse {
    pub output: ExecutionOutput,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StopExecutionRequest {
    pub execution_id: String,
}

// ==========================================
// WebSocket Messages
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum WsMessage {
    #[serde(rename = "connected")]
    Connected { message: String },

    #[serde(rename = "file_changed")]
    FileChanged { path: String, event: String },

    #[serde(rename = "execution_output")]
    ExecutionOutput { id: String, output: String },

    #[serde(rename = "error")]
    Error { message: String },

    #[serde(rename = "ping")]
    Ping,

    #[serde(rename = "pong")]
    Pong,
}

// ==========================================
// DataFrame Operations
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataFrameLoadRequest {
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataFrameLoadResponse {
    pub id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataFrameSliceRequest {
    pub id: String,
    pub offset: i64,
    pub limit: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataFrameSliceResponse {
    pub data: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataFrameSchemaRequest {
    pub id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataFrameSchemaResponse {
    pub schema: HashMap<String, String>,
}
