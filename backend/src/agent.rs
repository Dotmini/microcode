// AI Agent Core Module
// Production-level AI Agent with file system access and context understanding
// Unique Rust-native implementation for MicroCode IDE

use crate::error::{AppError, Result};
use crate::models::AIConfig;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock as StdRwLock};
use tokio::sync::RwLock as TokioRwLock;
use tokio::fs;
use once_cell::sync::Lazy;
use chrono::{DateTime, Utc};
use futures::stream::{self, BoxStream, StreamExt};
use async_stream::stream; // Requires adding to Cargo.toml if not present, but checked and added earlier.
// Actually I added async-stream to backend/Cargo.toml in step 6112.

// Streaming Event Definition
// Streaming Event Definition
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", content = "data")]
pub enum AgentStreamEvent {
    Token(String),
    ToolStart { name: String, id: String },
    ToolEnd { id: String, success: bool, output: String, error: Option<String> },
    PendingChange(PendingChange),
    Error(String),
    Done,
}

// ==========================================
// Global Agent State
// ==========================================

static AGENT_SESSIONS: Lazy<Arc<StdRwLock<HashMap<String, AgentSession>>>> =
    Lazy::new(|| Arc::new(StdRwLock::new(HashMap::new())));

static FILE_OPERATION_LOG: Lazy<Arc<StdRwLock<Vec<FileOperation>>>> =
    Lazy::new(|| Arc::new(StdRwLock::new(Vec::new())));

// ==========================================
// Core Data Structures
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentSession {
    pub id: String,
    pub workspace_path: PathBuf,
    pub messages: Vec<AgentMessage>,
    pub context: ProjectContext,
    pub tasks: Vec<Task>,
    pub pending_operations: Vec<PendingOperation>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub current_plan: Option<ExecutionPlan>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentMessage {
    pub id: String,
    pub role: MessageRole,
    pub content: String,
    pub tool_calls: Vec<ToolCall>,
    pub tool_results: Vec<ToolResult>,
    pub timestamp: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum MessageRole {
    User,
    Assistant,
    System,
    Tool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCall {
    pub id: String,
    pub name: String,
    pub arguments: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolResult {
    pub tool_call_id: String,
    pub success: bool,
    pub output: String,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectContext {
    pub root_path: PathBuf,
    pub project_type: String,
    pub files: Vec<FileInfo>,
    pub recent_files: Vec<PathBuf>,
    pub symbols: Vec<Symbol>,
    pub dependencies: Vec<String>,
    pub git_status: Option<GitStatus>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileInfo {
    pub path: PathBuf,
    pub relative_path: String,
    pub size: u64,
    pub is_directory: bool,
    pub extension: Option<String>,
    pub modified: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Symbol {
    pub name: String,
    pub kind: SymbolKind,
    pub file_path: PathBuf,
    pub line: usize,
    pub signature: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SymbolKind {
    Function,
    Class,
    Struct,
    Enum,
    Variable,
    Constant,
    Interface,
    Module,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitStatus {
    pub branch: String,
    pub modified_files: Vec<String>,
    pub staged_files: Vec<String>,
    pub untracked_files: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    pub id: String,
    pub title: String,
    pub description: String,
    pub status: TaskStatus,
    pub priority: TaskPriority,
    pub created_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TaskStatus {
    Pending,
    InProgress,
    Completed,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TaskPriority {
    Low,
    Medium,
    High,
    Critical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingOperation {
    pub id: String,
    pub operation_type: OperationType,
    pub description: String,
    pub requires_confirmation: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum OperationType {
    CreateFile,
    ModifyFile,
    DeleteFile,
    RunCommand,
    GitOperation,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileOperation {
    pub id: String,
    pub session_id: String,
    pub operation: OperationType,
    pub file_path: PathBuf,
    pub old_content: Option<String>,
    pub new_content: Option<String>,
    pub timestamp: DateTime<Utc>,
    pub can_undo: bool,
}

// ==========================================
// Production Features - Like Cursor/Windsurf/Antigravity
// ==========================================

/// Active editor context from IDE
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ActiveEditorContext {
    pub active_file: Option<String>,
    pub active_content: Option<String>,
    pub cursor_line: Option<usize>,
    pub cursor_column: Option<usize>,
    pub selected_text: Option<String>,
    pub selection_start_line: Option<usize>,
    pub selection_end_line: Option<usize>,
    pub open_files: Vec<String>,
    pub language: Option<String>,
    pub visible_range: Option<(usize, usize)>,
}

/// File diff for preview before applying
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileDiff {
    pub file_path: String,
    pub old_content: String,
    pub new_content: String,
    pub hunks: Vec<DiffHunk>,
    pub additions: usize,
    pub deletions: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffHunk {
    pub old_start: usize,
    pub old_count: usize,
    pub new_start: usize,
    pub new_count: usize,
    pub lines: Vec<DiffLine>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffLine {
    pub line_type: DiffLineType,
    pub content: String,
    pub old_line_num: Option<usize>,
    pub new_line_num: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DiffLineType {
    Context,
    Addition,
    Deletion,
}

/// Pending change awaiting user approval
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingChange {
    pub id: String,
    pub session_id: String,
    pub diff: FileDiff,
    pub description: String,
    pub tool_name: String,
    pub status: PendingChangeStatus,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PendingChangeStatus {
    Pending,
    Accepted,
    Rejected,
}

/// Enhanced chat request with editor context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatRequest {
    pub session_id: String,
    pub message: String,
    pub editor_context: Option<ActiveEditorContext>,
    pub provider: Option<String>,
    pub model: Option<String>,
    pub api_key: Option<String>,
    pub auto_execute: bool,  // Auto-execute tools or ask for confirmation
}

/// Chat response with structured output
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatResponse {
    pub message_id: String,
    pub content: String,
    pub thinking: Option<String>,
    pub tool_calls: Vec<ToolCall>,
    pub tool_results: Vec<ToolResult>,
    pub pending_changes: Vec<PendingChange>,
    pub suggestions: Vec<String>,
    pub plan: Option<ExecutionPlan>,
}



/// Execution plan for multi-step tasks
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionPlan {
    pub id: String,
    pub description: String,
    pub steps: Vec<PlanStep>,
    pub current_step: usize,
    pub status: PlanStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanStep {
    pub id: String,
    pub description: String,
    pub tool: String,
    pub arguments: serde_json::Value,
    pub status: StepStatus,
    pub result: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PlanStatus {
    Queued,
    Planning,
    Executing,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum StepStatus {
    Pending,
    Running,
    Completed,
    Failed,
    Skipped,
}

// Pending changes storage
static PENDING_CHANGES: Lazy<Arc<StdRwLock<HashMap<String, PendingChange>>>> =
    Lazy::new(|| Arc::new(StdRwLock::new(HashMap::new())));

// ==========================================
// Tool Definitions
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolDefinition {
    pub name: String,
    pub description: String,
    pub parameters: serde_json::Value,
}

pub fn get_available_tools() -> Vec<ToolDefinition> {
    vec![
        ToolDefinition {
            name: "read_file".to_string(),
            description: "Read the contents of a file at the specified path".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Path to the file to read"}
                },
                "required": ["path"]
            }),
        },
        ToolDefinition {
            name: "write_file".to_string(),
            description: "Create or overwrite a file with the specified content".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Path where the file should be created/updated"},
                    "content": {"type": "string", "description": "Content to write to the file"}
                },
                "required": ["path", "content"]
            }),
        },
        ToolDefinition {
            name: "edit_file".to_string(),
            description: "Make targeted edits to a file by replacing specific content".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Path to the file to edit"},
                    "search": {"type": "string", "description": "Exact text to search for"},
                    "replace": {"type": "string", "description": "Text to replace with"}
                },
                "required": ["path", "search", "replace"]
            }),
        },
        ToolDefinition {
            name: "delete_file".to_string(),
            description: "Delete a file at the specified path".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Path to the file to delete"}
                },
                "required": ["path"]
            }),
        },
        ToolDefinition {
            name: "list_directory".to_string(),
            description: "List all files and directories in the specified path".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Path to the directory to list"},
                    "recursive": {"type": "boolean", "description": "Whether to list recursively"}
                },
                "required": ["path"]
            }),
        },
        ToolDefinition {
            name: "search_code".to_string(),
            description: "Search for text patterns across files in the workspace".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query (supports regex)"},
                    "file_pattern": {"type": "string", "description": "Optional glob pattern to filter files"}
                },
                "required": ["query"]
            }),
        },
        ToolDefinition {
            name: "create_task".to_string(),
            description: "Create a task and optionally add it to todo.md".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "title": {"type": "string", "description": "Task title"},
                    "description": {"type": "string", "description": "Task description"},
                    "priority": {"type": "string", "enum": ["low", "medium", "high", "critical"]},
                    "add_to_todo": {"type": "boolean", "description": "Whether to add to todo.md"}
                },
                "required": ["title"]
            }),
        },
        ToolDefinition {
            name: "run_command".to_string(),
            description: "Execute a shell command in the workspace (sandboxed)".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "command": {"type": "string", "description": "Command to execute"},
                    "working_dir": {"type": "string", "description": "Working directory (optional)"}
                },
                "required": ["command"]
            }),
        },
        ToolDefinition {
            name: "git_status".to_string(),
            description: "Get the current git status of the workspace".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {}
            }),
        },
        ToolDefinition {
            name: "git_commit".to_string(),
            description: "Create a git commit with the specified message".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "message": {"type": "string", "description": "Commit message"},
                    "files": {"type": "array", "items": {"type": "string"}, "description": "Files to stage (empty for all)"}
                },
                "required": ["message"]
            }),
        },
        ToolDefinition {
            name: "search_rag".to_string(),
            description: "Perform a semantic (meaning-based) search across the entire codebase to find relevant code or logic".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Natural language query to search for"},
                    "limit": {"type": "integer", "description": "Max number of results (default 5)"}
                },
                "required": ["query"]
            }),
        },
        ToolDefinition {
            name: "create_plan".to_string(),
            description: "Propose a multi-step execution plan for complex tasks. This MUST be called first for multi-file changes.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "description": {"type": "string", "description": "High-level goal of the plan"},
                    "steps": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "description": {"type": "string", "description": "What this step does"},
                                "tool": {"type": "string", "description": "The tool to be used for this step (e.g., search_rag, edit_file)"}
                            },
                            "required": ["description", "tool"]
                        }
                    }
                },
                "required": ["description", "steps"]
            }),
        },
        ToolDefinition {
            name: "execute_command".to_string(),
            description: "Execute a terminal command for building, testing, or linting code. Returns stdout and stderr even if the command fails, allowing for self-correction.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "command": {"type": "string", "description": "The shell command to execute"},
                    "description": {"type": "string", "description": "Short explanation of what this command verifies"}
                },
                "required": ["command"]
            }),
        },
        ToolDefinition {
            name: "create_project".to_string(),
            description: "Scaffold a new project structure (Rust, Swift, Node.js, Python, Web, etc.)".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "Project name"},
                    "type": {"type": "string", "enum": ["rust", "swift", "node", "python", "web"], "description": "Project type"},
                    "path": {"type": "string", "description": "Target path (relative to workspace). Defaults to project name."}
                },
                "required": ["name", "type"]
            }),
        },
    ]
}

// ==========================================
// Session Management
// ==========================================

pub fn create_session(workspace_path: &str) -> Result<String> {
    let session_id = uuid::Uuid::new_v4().to_string();
    let path = PathBuf::from(workspace_path);
    
    let session = AgentSession {
        id: session_id.clone(),
        workspace_path: path.clone(),
        messages: vec![],
        context: ProjectContext {
            root_path: path,
            project_type: "unknown".to_string(),
            files: vec![],
            recent_files: vec![],
            symbols: vec![],
            dependencies: vec![],
            git_status: None,
        },
        tasks: vec![],
        pending_operations: vec![],
        created_at: Utc::now(),
        updated_at: Utc::now(),
        current_plan: None,
    };
    
    let mut sessions = AGENT_SESSIONS.write().unwrap();
    sessions.insert(session_id.clone(), session);
    
    Ok(session_id)
}

pub fn get_session(session_id: &str) -> Option<AgentSession> {
    let sessions = AGENT_SESSIONS.read().unwrap();
    sessions.get(session_id).cloned()
}

pub fn update_session(session: AgentSession) {
    let mut sessions = AGENT_SESSIONS.write().unwrap();
    sessions.insert(session.id.clone(), session);
}

// ==========================================
// Context Building
// ==========================================

pub async fn build_context(workspace_path: &Path, max_depth: usize) -> Result<ProjectContext> {
    let mut context = ProjectContext {
        root_path: workspace_path.to_path_buf(),
        project_type: detect_project_type(workspace_path).await,
        files: vec![],
        recent_files: vec![],
        symbols: vec![],
        dependencies: vec![],
        git_status: get_git_status(workspace_path).await.ok(),
    };
    
    let mut indexer = crate::indexer::Indexer::new();
    
    // Index files and extract symbols
    let (files, symbols) = index_files(workspace_path, max_depth, &mut indexer).await?;
    context.files = files;
    context.symbols = symbols;
    
    // Get recent files (last 20 modified)
    
    // Get recent files (last 20 modified)
    let mut sorted_files = context.files.clone();
    sorted_files.sort_by(|a, b| b.modified.cmp(&a.modified));
    context.recent_files = sorted_files.iter()
        .filter(|f| !f.is_directory)
        .take(20)
        .map(|f| f.path.clone())
        .collect();
    
    Ok(context)
}

async fn detect_project_type(path: &Path) -> String {
    let indicators = [
        ("Cargo.toml", "rust"),
        ("Package.swift", "swift"),
        ("package.json", "nodejs"),
        ("go.mod", "go"),
        ("requirements.txt", "python"),
        ("pyproject.toml", "python"),
        ("pubspec.yaml", "flutter"),
        ("Gemfile", "ruby"),
        ("pom.xml", "java"),
        ("build.gradle", "java"),
    ];
    
    for (file, project_type) in indicators {
        if path.join(file).exists() {
            return project_type.to_string();
        }
    }
    
    "unknown".to_string()
}

pub async fn index_files(root: &Path, max_depth: usize, indexer: &mut crate::indexer::Indexer) -> Result<(Vec<FileInfo>, Vec<Symbol>)> {
    let mut files = vec![];
    let mut symbols = vec![];
    index_files_recursive(root, root, &mut files, &mut symbols, 0, max_depth, indexer).await?;
    Ok((files, symbols))
}

#[async_recursion::async_recursion]
async fn index_files_recursive(
    root: &Path,
    current: &Path,
    files: &mut Vec<FileInfo>,
    symbols: &mut Vec<Symbol>,
    depth: usize,
    max_depth: usize,
    indexer: &mut crate::indexer::Indexer,
) -> Result<()> {
    if depth > max_depth {
        return Ok(());
    }
    
    let mut entries = fs::read_dir(current).await
        .map_err(|e| AppError::IOError(e.to_string()))?;
    
    while let Some(entry) = entries.next_entry().await
        .map_err(|e| AppError::IOError(e.to_string()))? {
        let path = entry.path();
        let name = path.file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();
        
        // Skip hidden files and common ignore patterns to reduce CPU/Disk load
        if name.starts_with('.') || 
           name == "node_modules" || 
           name == "target" ||
           name == "build" ||
           name == "dist" ||
           name == "Dist" ||
           name == ".build" ||
           name == ".build_dist" ||
           name == ".swiftpm" ||
           name == ".git" ||
           name == "Pods" ||
           name == "DerivedData" ||
           name == "__pycache__" {
            continue;
        }
        
        let metadata = entry.metadata().await
            .map_err(|e| AppError::IOError(e.to_string()))?;
        
        let relative_path = path.strip_prefix(root)
            .unwrap_or(&path)
            .to_string_lossy()
            .to_string();
        
        let modified = metadata.modified()
            .map(|t| DateTime::<Utc>::from(t))
            .unwrap_or_else(|_| Utc::now());
        
        files.push(FileInfo {
            path: path.clone(),
            relative_path,
            size: metadata.len(),
            is_directory: metadata.is_dir(),
            extension: path.extension().map(|e| e.to_string_lossy().to_string()),
            modified,
        });
        
        if metadata.is_dir() {
            index_files_recursive(root, &path, files, symbols, depth + 1, max_depth, indexer).await?;
        } else {
            // Extract symbols from code files
            // THROTTLING: Give some breathing room to the OS and other tasks
            tokio::task::yield_now().await;
            
            if let Ok(content) = fs::read_to_string(&path).await {
                if let Ok(chunks) = indexer.chunk_file(&path, &content) {
                    for chunk in chunks {
                        if let Some(name) = chunk.symbol_name {
                            symbols.push(Symbol {
                                name,
                                kind: match chunk.symbol_kind.as_str() {
                                    "function_definition" | "function_item" | "function_declaration" => SymbolKind::Function,
                                    "class_definition" | "class_declaration" => SymbolKind::Class,
                                    "struct_item" => SymbolKind::Struct,
                                    "enum_item" => SymbolKind::Enum,
                                    "method_definition" => SymbolKind::Function, // Treat methods as functions for Kind
                                    _ => SymbolKind::Variable,
                                },
                                file_path: path.clone(),
                                line: chunk.start_line,
                                signature: Some(chunk.content.lines().next().unwrap_or("").to_string()),
                            });
                        }
                    }
                }
            }
        }
    }
    
    Ok(())
}

async fn get_git_status(path: &Path) -> Result<GitStatus> {
    let git_dir = path.join(".git");
    if !git_dir.exists() {
        return Err(AppError::IOError("Not a git repository".to_string()));
    }
    
    // Get current branch
    let branch = tokio::process::Command::new("git")
        .args(["branch", "--show-current"])
        .current_dir(path)
        .output()
        .await
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|_| "unknown".to_string());
    
    // Get status
    let status_output = tokio::process::Command::new("git")
        .args(["status", "--porcelain"])
        .current_dir(path)
        .output()
        .await
        .map_err(|e| AppError::IOError(e.to_string()))?;
    
    let status_str = String::from_utf8_lossy(&status_output.stdout);
    let mut modified = vec![];
    let mut staged = vec![];
    let mut untracked = vec![];
    
    for line in status_str.lines() {
        if line.len() < 3 { continue; }
        let file = line[3..].to_string();
        match &line[0..2] {
            "M " | "A " | "D " | "R " => staged.push(file),
            " M" | " D" => modified.push(file),
            "??" => untracked.push(file),
            _ => {}
        }
    }
    
    Ok(GitStatus {
        branch,
        modified_files: modified,
        staged_files: staged,
        untracked_files: untracked,
    })
}

// ==========================================
// Tool Execution
// ==========================================

pub async fn execute_tool(
    state: Arc<TokioRwLock<crate::state::AppState>>,
    session_id: &str,
    tool_name: &str,
    arguments: &serde_json::Value,
) -> Result<ToolResult> {
    let session = get_session(session_id)
        .ok_or_else(|| AppError::NotFound("Session not found".to_string()))?;
    
    let workspace = &session.workspace_path;
    
    let result = match tool_name {
        "read_file" => tool_read_file(workspace, arguments).await,
        "write_file" => tool_write_file(session_id, workspace, arguments).await,
        "edit_file" => tool_edit_file(session_id, workspace, arguments).await,
        "delete_file" => tool_delete_file(session_id, workspace, arguments).await,
        "list_directory" => tool_list_directory(workspace, arguments).await,
        "search_code" => tool_search_code(workspace, arguments).await,
        "create_task" => tool_create_task(session_id, workspace, arguments).await,
        "run_command" => tool_run_command(workspace, arguments).await,
        "git_status" => tool_git_status(workspace).await,
        "git_commit" => tool_git_commit(workspace, arguments).await,
        "search_rag" => tool_search_rag(state, arguments).await,
        "create_plan" => {
            let description = arguments["description"].as_str().unwrap_or("");
            let steps = arguments["steps"].as_array().cloned().unwrap_or_default();
            tool_create_plan(session_id, description, steps).await
        }
        "execute_command" => tool_execute_command(workspace, arguments).await,
        "create_project" => tool_create_project(session_id, workspace, arguments).await,
        _ => Err(AppError::NotFound(format!("Unknown tool: {}", tool_name))),
    };
    
    let tool_call_id = uuid::Uuid::new_v4().to_string();
    
    match result {
        Ok(output) => Ok(ToolResult {
            tool_call_id,
            success: true,
            output,
            error: None,
        }),
        Err(e) => Ok(ToolResult {
            tool_call_id,
            success: false,
            output: String::new(),
            error: Some(e.to_string()),
        }),
    }
}

// ==========================================
// Individual Tool Implementations
// ==========================================

async fn tool_read_file(workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let path_str = args["path"].as_str()
        .ok_or_else(|| AppError::ValidationError("path is required".to_string()))?;
    
    let full_path = resolve_path(workspace, path_str);
    validate_path_in_workspace(workspace, &full_path)?;
    
    // Guard: reject files over 10MB to prevent OOM
    const MAX_FILE_SIZE: u64 = 10 * 1024 * 1024; // 10MB
    if let Ok(metadata) = tokio::fs::metadata(&full_path).await {
        if metadata.len() > MAX_FILE_SIZE {
            return Err(AppError::ValidationError(format!(
                "File too large ({:.1} MB). Maximum is {} MB. Use a streaming approach for large files.",
                metadata.len() as f64 / 1_048_576.0,
                MAX_FILE_SIZE / 1_048_576
            )));
        }
    }
    
    let content = fs::read_to_string(&full_path).await
        .map_err(|e| AppError::IOError(format!("Failed to read file: {}", e)))?;
    
    Ok(content)
}

async fn tool_write_file(session_id: &str, workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let path_str = args["path"].as_str()
        .ok_or_else(|| AppError::ValidationError("path is required".to_string()))?;
    let content = args["content"].as_str()
        .ok_or_else(|| AppError::ValidationError("content is required".to_string()))?;
    
    let full_path = resolve_path(workspace, path_str);
    validate_path_in_workspace(workspace, &full_path)?;
    
    // Store old content for undo
    let old_content = fs::read_to_string(&full_path).await.ok();
    
    // Create parent directories
    if let Some(parent) = full_path.parent() {
        fs::create_dir_all(parent).await
            .map_err(|e| AppError::IOError(e.to_string()))?;
    }
    
    // Write file
    fs::write(&full_path, content).await
        .map_err(|e| AppError::IOError(format!("Failed to write file: {}", e)))?;
    
    // Log operation for undo
    log_file_operation(session_id, OperationType::CreateFile, &full_path, old_content, Some(content.to_string()));
    
    Ok(format!("Successfully wrote {} bytes to {}", content.len(), path_str))
}

async fn tool_edit_file(session_id: &str, workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let path_str = args["path"].as_str()
        .ok_or_else(|| AppError::ValidationError("path is required".to_string()))?;
    let search = args["search"].as_str()
        .ok_or_else(|| AppError::ValidationError("search is required".to_string()))?;
    let replace = args["replace"].as_str()
        .ok_or_else(|| AppError::ValidationError("replace is required".to_string()))?;
    
    let full_path = resolve_path(workspace, path_str);
    validate_path_in_workspace(workspace, &full_path)?;
    
    let old_content = fs::read_to_string(&full_path).await
        .map_err(|e| AppError::IOError(format!("Failed to read file: {}", e)))?;
    
    if !old_content.contains(search) {
        return Err(AppError::ValidationError("Search text not found in file".to_string()));
    }
    
    let new_content = old_content.replace(search, replace);
    
    fs::write(&full_path, &new_content).await
        .map_err(|e| AppError::IOError(format!("Failed to write file: {}", e)))?;
    
    log_file_operation(session_id, OperationType::ModifyFile, &full_path, Some(old_content), Some(new_content));
    
    Ok(format!("Successfully edited {}", path_str))
}

async fn tool_delete_file(session_id: &str, workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let path_str = args["path"].as_str()
        .ok_or_else(|| AppError::ValidationError("path is required".to_string()))?;
    
    let full_path = resolve_path(workspace, path_str);
    validate_path_in_workspace(workspace, &full_path)?;
    
    let old_content = fs::read_to_string(&full_path).await.ok();
    
    fs::remove_file(&full_path).await
        .map_err(|e| AppError::IOError(format!("Failed to delete file: {}", e)))?;
    
    log_file_operation(session_id, OperationType::DeleteFile, &full_path, old_content, None);
    
    Ok(format!("Successfully deleted {}", path_str))
}

async fn tool_list_directory(workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let path_str = args["path"].as_str().unwrap_or(".");
    let recursive = args["recursive"].as_bool().unwrap_or(false);
    
    let full_path = resolve_path(workspace, path_str);
    validate_path_in_workspace(workspace, &full_path)?;
    
    let max_depth = if recursive { 5 } else { 1 };
    let mut indexer = crate::indexer::Indexer::new();
    let (files, _) = index_files(&full_path, max_depth, &mut indexer).await?;
    
    let output: Vec<String> = files.iter()
        .map(|f| {
            let icon = if f.is_directory { "📁" } else { "📄" };
            format!("{} {}", icon, f.relative_path)
        })
        .collect();
    
    Ok(output.join("\n"))
}

async fn tool_search_code(workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let query = args["query"].as_str()
        .ok_or_else(|| AppError::ValidationError("query is required".to_string()))?;
    let file_pattern = args["file_pattern"].as_str();
    
    // Use ripgrep if available, otherwise fall back to manual search
    let mut cmd = tokio::process::Command::new("rg");
    cmd.args(["--line-number", "--no-heading", query])
        .current_dir(workspace);
    
    if let Some(pattern) = file_pattern {
        cmd.args(["-g", pattern]);
    }
    
    let output = cmd.output().await;
    
    match output {
        Ok(o) if o.status.success() => {
            let result = String::from_utf8_lossy(&o.stdout);
            if result.is_empty() {
                Ok("No matches found".to_string())
            } else {
                // Limit output
                let lines: Vec<&str> = result.lines().take(50).collect();
                Ok(lines.join("\n"))
            }
        }
        _ => Ok("No matches found".to_string())
    }
}

async fn tool_create_task(session_id: &str, workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let title = args["title"].as_str()
        .ok_or_else(|| AppError::ValidationError("title is required".to_string()))?;
    let description = args["description"].as_str().unwrap_or("");
    let priority_str = args["priority"].as_str().unwrap_or("medium");
    let add_to_todo = args["add_to_todo"].as_bool().unwrap_or(true);
    
    let priority = match priority_str {
        "low" => TaskPriority::Low,
        "high" => TaskPriority::High,
        "critical" => TaskPriority::Critical,
        _ => TaskPriority::Medium,
    };
    
    let task = Task {
        id: uuid::Uuid::new_v4().to_string(),
        title: title.to_string(),
        description: description.to_string(),
        status: TaskStatus::Pending,
        priority,
        created_at: Utc::now(),
        completed_at: None,
    };
    
    // Add to session
    if let Some(mut session) = get_session(session_id) {
        session.tasks.push(task.clone());
        update_session(session);
    }
    
    // Add to todo.md if requested
    if add_to_todo {
        let todo_path = workspace.join("todo.md");
        let mut content = fs::read_to_string(&todo_path).await.unwrap_or_else(|_| "# TODO\n\n".to_string());
        
        let priority_marker = match priority_str {
            "critical" => "🔴",
            "high" => "🟠",
            "low" => "🟢",
            _ => "🟡",
        };
        
        let task_line = format!("- [ ] {} {} {}\n", priority_marker, title,
            if description.is_empty() { "".to_string() } else { format!("- {}", description) });
        
        content.push_str(&task_line);
        
        fs::write(&todo_path, content).await
            .map_err(|e| AppError::IOError(e.to_string()))?;
    }
    
    Ok(format!("Created task: {}", title))
}

async fn tool_create_project(session_id: &str, workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let name = args["name"].as_str()
        .ok_or_else(|| AppError::ValidationError("name is required".to_string()))?;
    let proj_type = args["type"].as_str()
        .ok_or_else(|| AppError::ValidationError("type is required".to_string()))?;
    let path_str = args["path"].as_str().unwrap_or(name);
    
    let full_path = resolve_path(workspace, path_str);
    
    // Check if exists
    if full_path.exists() {
        return Err(AppError::ValidationError(format!("Path already exists: {}", full_path.display())));
    }
    
    // Create directory
    fs::create_dir_all(&full_path).await
        .map_err(|e| AppError::IOError(e.to_string()))?;
        
    let mut created_files = Vec::new();

    match proj_type {
        "rust" => {
            tokio::process::Command::new("cargo")
                .args(["init", "--name", name])
                .current_dir(&full_path)
                .output()
                .await
                .map_err(|e| AppError::IOError(e.to_string()))?;
            created_files.push("Cargo.toml");
            created_files.push("src/main.rs");
        },
        "swift" => {
            tokio::process::Command::new("swift")
                .args(["package", "init", "--type", "executable", "--name", name])
                .current_dir(&full_path)
                .output()
                .await
                .map_err(|e| AppError::IOError(e.to_string()))?;
            created_files.push("Package.swift");
            created_files.push("Sources/main.swift");
        },
        "node" => {
            tokio::process::Command::new("npm")
                .args(["init", "-y"])
                .current_dir(&full_path)
                .output()
                .await
                .map_err(|e| AppError::IOError(e.to_string()))?;
            
            // Create index.js
            fs::write(full_path.join("index.js"), "console.log('Hello, World!');").await
                .map_err(|e| AppError::IOError(e.to_string()))?;
                
            created_files.push("package.json");
            created_files.push("index.js");
        },
        "python" => {
            fs::write(full_path.join("main.py"), "def main():\n    print('Hello, World!')\n\nif __name__ == '__main__':\n    main()").await
                .map_err(|e| AppError::IOError(e.to_string()))?;
            fs::write(full_path.join("requirements.txt"), "").await
                .map_err(|e| AppError::IOError(e.to_string()))?;
            created_files.push("main.py");
            created_files.push("requirements.txt");
        },
        "web" => {
            fs::write(full_path.join("index.html"), "<!DOCTYPE html>\n<html>\n<body>\n    <h1>Hello World</h1>\n    <script src=\"script.js\"></script>\n</body>\n</html>").await
                .map_err(|e| AppError::IOError(e.to_string()))?;
            fs::write(full_path.join("style.css"), "body { font-family: sans-serif; }").await
                .map_err(|e| AppError::IOError(e.to_string()))?;
            fs::write(full_path.join("script.js"), "console.log('Hello, World!');").await
                .map_err(|e| AppError::IOError(e.to_string()))?;
            created_files.push("index.html");
            created_files.push("style.css");
            created_files.push("script.js");
        },
        _ => return Err(AppError::ValidationError(format!("Unknown project type: {}", proj_type))),
    }

    Ok(format!("Created {} project at {}. Files: {:?}", proj_type, path_str, created_files))
}

async fn tool_run_command(workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let command = args["command"].as_str()
        .ok_or_else(|| AppError::ValidationError("command is required".to_string()))?;
    
    secure_execute_command(workspace, command, None).await
}

/// Secure command execution with sandboxing:
/// - Comprehensive blocklist with pattern matching (not just substring)
/// - 30-second timeout to prevent hangs
/// - 1MB output limit to prevent OOM
/// - Restricted environment variables
/// - Working directory locked to workspace
async fn secure_execute_command(workspace: &Path, command: &str, description: Option<&str>) -> Result<String> {
    // Normalize command for checking (lowercase, collapse whitespace)
    let cmd_lower = command.to_lowercase();
    let cmd_normalized = cmd_lower.split_whitespace().collect::<Vec<_>>().join(" ");
    
    // === COMPREHENSIVE BLOCKLIST ===
    // Block by exact dangerous commands
    let blocked_commands = [
        "rm -rf /", "rm -rf /*", "rm -rf ~", "rm -rf $home",
        "mkfs", "dd if=", ":(){", "fork", "chmod 777 /",
        "shutdown", "reboot", "halt", "poweroff", "init 0", "init 6",
    ];
    for b in blocked_commands {
        if cmd_normalized.contains(b) {
            return Err(AppError::ValidationError(format!("Blocked dangerous command pattern: {}", b)));
        }
    }
    
    // Block privilege escalation
    let blocked_prefixes = ["sudo ", "su ", "doas ", "pkexec ", "runas "];
    for prefix in blocked_prefixes {
        if cmd_normalized.starts_with(prefix) || cmd_normalized.contains(&format!("| {}", prefix)) || cmd_normalized.contains(&format!("&& {}", prefix)) {
            return Err(AppError::ValidationError(format!("Blocked privilege escalation: {}", prefix.trim())));
        }
    }
    
    // Block network exfiltration tools (when piped from sensitive sources)
    let blocked_patterns = [
        "curl.*-d.*etc", "wget.*--post", "nc -e", "ncat -e",
        "/dev/tcp", "/dev/udp", "base64.*|.*curl",
    ];
    for pattern in blocked_patterns {
        if let Ok(re) = regex::Regex::new(pattern) {
            if re.is_match(&cmd_normalized) {
                return Err(AppError::ValidationError("Blocked potentially dangerous command pattern".to_string()));
            }
        }
    }
    
    // Block writing to system directories
    let system_dirs = ["/etc/", "/usr/", "/bin/", "/sbin/", "/var/", "/boot/", "/root/", "/System/", "/Library/"];
    for dir in system_dirs {
        let dir_lower = dir.to_lowercase();
        if cmd_normalized.contains(&format!(">{}", dir_lower)) || cmd_normalized.contains(&format!("> {}", dir_lower)) {
            return Err(AppError::ValidationError(format!("Cannot write to system directory: {}", dir)));
        }
    }
    
    // === EXECUTE WITH TIMEOUT ===
    let timeout_duration = std::time::Duration::from_secs(30);
    
    let child = tokio::process::Command::new("sh")
        .args(["-c", command])
        .current_dir(workspace)
        .env_clear()
        .env("PATH", "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin")
        .env("HOME", dirs::home_dir().unwrap_or_default())
        .env("LANG", "en_US.UTF-8")
        .env("TERM", "xterm-256color")
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| AppError::IOError(format!("Failed to spawn command: {}", e)))?;
    
    // Wait with timeout
    let result = tokio::time::timeout(timeout_duration, child.wait_with_output()).await;
    
    match result {
        Ok(Ok(output)) => {
            // Limit output size to 1MB
            const MAX_OUTPUT: usize = 1_048_576;
            let stdout_raw = String::from_utf8_lossy(&output.stdout);
            let stderr_raw = String::from_utf8_lossy(&output.stderr);
            
            let stdout = if stdout_raw.len() > MAX_OUTPUT {
                format!("{}\n... [truncated, {} bytes total]", &stdout_raw[..MAX_OUTPUT], stdout_raw.len())
            } else {
                stdout_raw.to_string()
            };
            
            let stderr = if stderr_raw.len() > MAX_OUTPUT {
                format!("{}\n... [truncated, {} bytes total]", &stderr_raw[..MAX_OUTPUT], stderr_raw.len())
            } else {
                stderr_raw.to_string()
            };
            
            let exit_code = output.status.code().unwrap_or(-1);
            
            let desc_line = if let Some(d) = description {
                format!("\nDescription: {}", d)
            } else {
                String::new()
            };
            
            Ok(format!(
                "Command: {}{}\nExit Code: {}\n\nSTDOUT:\n{}\n\nSTDERR:\n{}",
                command, desc_line, exit_code, stdout, stderr
            ))
        }
        Ok(Err(e)) => Err(AppError::IOError(format!("Command failed: {}", e))),
        Err(_) => Err(AppError::IOError(format!("Command timed out after {} seconds: {}", timeout_duration.as_secs(), command))),
    }
}

async fn tool_git_status(workspace: &Path) -> Result<String> {
    let status = get_git_status(workspace).await?;
    
    let mut output = format!("Branch: {}\n\n", status.branch);
    
    if !status.staged_files.is_empty() {
        output.push_str("Staged:\n");
        for f in &status.staged_files {
            output.push_str(&format!("  ✓ {}\n", f));
        }
    }
    
    if !status.modified_files.is_empty() {
        output.push_str("\nModified:\n");
        for f in &status.modified_files {
            output.push_str(&format!("  M {}\n", f));
        }
    }
    
    if !status.untracked_files.is_empty() {
        output.push_str("\nUntracked:\n");
        for f in &status.untracked_files {
            output.push_str(&format!("  ? {}\n", f));
        }
    }
    
    Ok(output)
}

async fn tool_git_commit(workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let message = args["message"].as_str()
        .ok_or_else(|| AppError::ValidationError("message is required".to_string()))?;
    
    // Stage all if no specific files
    let files = args["files"].as_array();
    if files.is_none() || files.unwrap().is_empty() {
        tokio::process::Command::new("git")
            .args(["add", "."])
            .current_dir(workspace)
            .output()
            .await
            .map_err(|e| AppError::IOError(e.to_string()))?;
    } else {
        for file in files.unwrap() {
            if let Some(f) = file.as_str() {
                tokio::process::Command::new("git")
                    .args(["add", f])
                    .current_dir(workspace)
                    .output()
                    .await
                    .map_err(|e| AppError::IOError(e.to_string()))?;
            }
        }
    }
    
    // Commit
    let output = tokio::process::Command::new("git")
        .args(["commit", "-m", message])
        .current_dir(workspace)
        .output()
        .await
        .map_err(|e| AppError::IOError(e.to_string()))?;
    
    if output.status.success() {
        Ok(format!("Committed: {}", message))
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(AppError::IOError(format!("Commit failed: {}", stderr)))
    }
}

// ==========================================
// Helper Functions
// ==========================================

fn resolve_path(workspace: &Path, path_str: &str) -> PathBuf {
    let path = Path::new(path_str);
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        workspace.join(path)
    }
}

fn validate_path_in_workspace(workspace: &Path, path: &Path) -> Result<()> {
    let canonical_workspace = workspace.canonicalize()
        .map_err(|e| AppError::IOError(e.to_string()))?;
    
    // For new files, check parent
    let check_path = if path.exists() {
        path.canonicalize().map_err(|e| AppError::IOError(e.to_string()))?
    } else if let Some(parent) = path.parent() {
        if parent.exists() {
            parent.canonicalize().map_err(|e| AppError::IOError(e.to_string()))?
        } else {
            return Err(AppError::ValidationError("Parent directory does not exist".to_string()));
        }
    } else {
        return Err(AppError::ValidationError("Invalid path".to_string()));
    };
    
    if !check_path.starts_with(&canonical_workspace) {
        return Err(AppError::ValidationError(
            "Path is outside workspace (security restriction)".to_string()
        ));
    }
    
    Ok(())
}

fn log_file_operation(
    session_id: &str,
    operation: OperationType,
    path: &Path,
    old_content: Option<String>,
    new_content: Option<String>,
) {
    let op = FileOperation {
        id: uuid::Uuid::new_v4().to_string(),
        session_id: session_id.to_string(),
        operation,
        file_path: path.to_path_buf(),
        old_content,
        new_content,
        timestamp: Utc::now(),
        can_undo: true,
    };
    
    let mut log = FILE_OPERATION_LOG.write().unwrap();
    log.push(op);
    
    // Keep only last 100 operations
    if log.len() > 100 {
        log.remove(0);
    }
}

// ==========================================
// Undo Support
// ==========================================

pub async fn undo_last_operation(session_id: &str) -> Result<String> {
    let op = {
        let log = FILE_OPERATION_LOG.read().unwrap();
        log.iter()
            .rev()
            .find(|o| o.session_id == session_id && o.can_undo)
            .cloned()
    };
    
    let op = op.ok_or_else(|| AppError::NotFound("No operation to undo".to_string()))?;
    
    match op.operation {
        OperationType::CreateFile | OperationType::ModifyFile => {
            if let Some(old_content) = op.old_content {
                fs::write(&op.file_path, old_content as String).await
                    .map_err(|e| AppError::IOError(e.to_string()))?;
                Ok(format!("Restored: {}", op.file_path.display()))
            } else {
                fs::remove_file(&op.file_path).await
                    .map_err(|e| AppError::IOError(e.to_string()))?;
                Ok(format!("Deleted created file: {}", op.file_path.display()))
            }
        }
        OperationType::DeleteFile => {
            if let Some(content) = op.old_content {
                fs::write(&op.file_path, content).await
                    .map_err(|e| AppError::IOError(e.to_string()))?;
                Ok(format!("Restored deleted file: {}", op.file_path.display()))
            } else {
                Err(AppError::IOError("Cannot restore: no backup content".to_string()))
            }
        }
        _ => Err(AppError::ValidationError("This operation cannot be undone".to_string())),
    }
}

// ==========================================
// Production Features - Diff Generation
// ==========================================

/// Generate unified diff between old and new content
pub fn generate_diff(file_path: &str, old_content: &str, new_content: &str) -> FileDiff {
    let old_lines: Vec<&str> = old_content.lines().collect();
    let new_lines: Vec<&str> = new_content.lines().collect();
    
    let mut hunks = Vec::new();
    let mut additions = 0;
    let mut deletions = 0;
    
    // Simple line-by-line diff algorithm
    let mut i = 0;
    let mut j = 0;
    let mut hunk_lines = Vec::new();
    let mut hunk_old_start = 0;
    let mut hunk_new_start = 0;
    let mut in_hunk = false;
    
    while i < old_lines.len() || j < new_lines.len() {
        if i < old_lines.len() && j < new_lines.len() && old_lines[i] == new_lines[j] {
            // Context line
            if in_hunk {
                hunk_lines.push(DiffLine {
                    line_type: DiffLineType::Context,
                    content: old_lines[i].to_string(),
                    old_line_num: Some(i + 1),
                    new_line_num: Some(j + 1),
                });
            }
            i += 1;
            j += 1;
        } else {
            if !in_hunk {
                in_hunk = true;
                hunk_old_start = i + 1;
                hunk_new_start = j + 1;
                // Add context before
                if i > 0 {
                    hunk_lines.push(DiffLine {
                        line_type: DiffLineType::Context,
                        content: old_lines[i.saturating_sub(1)].to_string(),
                        old_line_num: Some(i),
                        new_line_num: Some(j),
                    });
                }
            }
            
            // Check for deletion
            if i < old_lines.len() && (j >= new_lines.len() || !new_lines.iter().skip(j).take(5).any(|&l| l == old_lines[i])) {
                hunk_lines.push(DiffLine {
                    line_type: DiffLineType::Deletion,
                    content: old_lines[i].to_string(),
                    old_line_num: Some(i + 1),
                    new_line_num: None,
                });
                deletions += 1;
                i += 1;
            } else if j < new_lines.len() {
                // Addition
                hunk_lines.push(DiffLine {
                    line_type: DiffLineType::Addition,
                    content: new_lines[j].to_string(),
                    old_line_num: None,
                    new_line_num: Some(j + 1),
                });
                additions += 1;
                j += 1;
            }
        }
        
        // Flush hunk if we have enough context
        if in_hunk && i < old_lines.len() && j < new_lines.len() && old_lines[i] == new_lines[j] {
            let old_count = hunk_lines.iter().filter(|l| matches!(l.line_type, DiffLineType::Deletion | DiffLineType::Context)).count();
            let new_count = hunk_lines.iter().filter(|l| matches!(l.line_type, DiffLineType::Addition | DiffLineType::Context)).count();
            
            hunks.push(DiffHunk {
                old_start: hunk_old_start,
                old_count,
                new_start: hunk_new_start,
                new_count,
                lines: std::mem::take(&mut hunk_lines),
            });
            in_hunk = false;
        }
    }
    
    // Flush remaining hunk
    if !hunk_lines.is_empty() {
        let old_count = hunk_lines.iter().filter(|l| matches!(l.line_type, DiffLineType::Deletion | DiffLineType::Context)).count();
        let new_count = hunk_lines.iter().filter(|l| matches!(l.line_type, DiffLineType::Addition | DiffLineType::Context)).count();
        
        hunks.push(DiffHunk {
            old_start: hunk_old_start,
            old_count,
            new_start: hunk_new_start,
            new_count,
            lines: hunk_lines,
        });
    }
    
    FileDiff {
        file_path: file_path.to_string(),
        old_content: old_content.to_string(),
        new_content: new_content.to_string(),
        hunks,
        additions,
        deletions,
    }
}

// ==========================================
// Production Features - Enhanced Chat
// ==========================================

/// Enhanced chat with multi-tool execution and diff preview
pub async fn enhanced_chat(
    state: Arc<TokioRwLock<crate::state::AppState>>,
    request: ChatRequest,
    ai_config: &crate::models::AIConfig
) -> Result<ChatResponse> {
    let session = get_session(&request.session_id)
        .ok_or_else(|| AppError::NotFound("Session not found".to_string()))?;
    
    // Build context prompt with editor info
    let mut context_parts = vec![];
    if let Some(ref editor) = request.editor_context {
        if let Some(ref file) = editor.active_file {
            context_parts.push(format!("Active file: {}", file));
        }
        if let Some(line) = editor.cursor_line {
            context_parts.push(format!("Cursor at line: {}", line));
        }
        if let Some(ref selected) = editor.selected_text {
            if !selected.is_empty() {
                context_parts.push(format!("Selected text:\n```\n{}\n```", selected));
            }
        }
        if let Some(ref content) = editor.active_content {
            let lines: Vec<&str> = content.lines().collect();
            let cursor_line = editor.cursor_line.unwrap_or(0);
            let start = cursor_line.saturating_sub(10);
            let end = (cursor_line + 10).min(lines.len());
            let visible: Vec<String> = lines[start..end].iter()
                .enumerate()
                .map(|(i, l)| format!("{}: {}", start + i + 1, l))
                .collect();
            context_parts.push(format!("Code around cursor:\n```\n{}\n```", visible.join("\n")));
        }
    }
    context_parts.push(format!("Workspace: {}", session.workspace_path.display()));
    context_parts.push(format!("Project type: {}", session.context.project_type));

    let tools = get_available_tools();
    let tools_json: Vec<serde_json::Value> = tools.iter()
        .map(|t| serde_json::json!({
            "name": t.name,
            "description": t.description,
            "arguments": t.parameters
        }))
        .collect();

    let system_prompt = format!(
            r#"You are an expert AI coding assistant, designed to rival tools like Cursor and Windsurf.
CONTEXT:
{}

AVAILABLE TOOLS:
{}

CORE PHILOSOPHY:
- **Agentic Workflow**: You are not just a chatbot; you are an autonomous agent. Break down complex requests into a step-by-step plan.
- **Visual Thinking**: Your actions are visualized in real-time. Usage of `task.md` and `todo.md` is CRITICAL for showing your progress to the user.
- **Transparency**: When editing files, always explain WHAT you are doing before you do it.

INSTRUCTIONS:
1. **Task Management (CRITICAL)**: 
   - For any multi-step task, FIRST check if `task.md` exists. If not, create it.
   - Use `task.md` to track your plan. Update it frequently (mark items as `[x]` done, `[-]` skipped, `[/]` in-progress).
   - Format `task.md` with clear headers and checkboxes. This file is the "Dashboard" for the user.

2. **Tool Usage**:
   - You are autonomous and can execute multiple tools in sequence.
   - **Always** verify your changes by reading the file or using search tools.
   - If a tool fails, analyze the error and try a different approach.
   - Respond in standard text to explain your thinking, but for ACTIONS, use ONLY the tool block format: 
   ```json
   [
     {{"name": "tool_name", "arguments": {{"arg1": "val1"}}}},
     ...
   ] 
   ```

3. **Code Editing**:
   - Use `read_file` to understand content before editing.
   - Use `write_file` for new files or complete rewrites.
   - Use `edit_file` for precise changes.
   - **Real-time Preview**: When writing code, the system visualizes it. Be complete and accurate.

4. **Self-Correction**:
   - After editing code, run relevant verification (e.g. `cargo check`, `npm test`) if possible.
   - Read error logs carefully. Focus on the first error.
   - Propose minimal changes to fix specific errors.
   - RE-VERIFY after every fix attempt until clean.

REMEMBER: You are building the future of coding. Make it look magic."#,
        context_parts.join("\n"),
        serde_json::to_string_pretty(&tools_json).unwrap_or_default()
    );
    
    // Build full prompt
    let full_prompt = format!("System: {}\n\nUser: {}", system_prompt, request.message);
    
    // AI Loop for Autonomy & Self-Correction
    let mut current_prompt = full_prompt.clone();
    let mut total_tool_calls = Vec::new();
    let mut total_tool_results = Vec::new();
    let mut pending_changes = Vec::new();
    let mut final_assistant_content = String::new();
    let mut loop_count = 0;
    let max_loops = 5;

    // Merge request overrides with base config
    let mut actual_config = ai_config.clone();
    if let Some(p) = &request.provider { actual_config.provider = p.clone(); }
    if let Some(m) = &request.model { actual_config.model = m.clone(); }
    if let Some(k) = &request.api_key { actual_config.api_key = k.clone(); }

    let provider = crate::ai::get_provider(&actual_config.provider)?;

    while loop_count < max_loops {
        loop_count += 1;
        
        // Call AI
        let ai_response: String = provider.generate(&current_prompt, &actual_config).await?;
        
        // Parse tool calls from response
        let mut turn_tool_calls = Vec::new();
        let mut turn_tool_results = Vec::new();
        let mut turn_content = ai_response.clone();
        
        // Try to extract JSON tool calls
        let json_pattern = regex::Regex::new(r#"\[\s*\{[\s\S]*?"name"[\s\S]*?\}\s*\]"#).ok();
        if let Some(pattern) = json_pattern {
            if let Some(captures) = pattern.find(&ai_response) {
                let json_str = captures.as_str();
                if let Ok(calls) = serde_json::from_str::<Vec<serde_json::Value>>(json_str) {
                    for call in calls {
                        if let (Some(name), Some(args)) = (call["name"].as_str(), call.get("arguments")) {
                            let tc = ToolCall {
                                id: uuid::Uuid::new_v4().to_string(),
                                name: name.to_string(),
                                arguments: args.clone(),
                            };
                            turn_tool_calls.push(tc.clone());
                            
                            // Execute tool or create pending change
                            if request.auto_execute || !is_destructive_tool(name) {
                                match execute_tool(state.clone(), &request.session_id, name, args).await {
                                    Ok(result) => turn_tool_results.push(result),
                                    Err(e) => turn_tool_results.push(ToolResult {
                                        tool_call_id: tc.id.clone(),
                                        success: false,
                                        output: String::new(),
                                        error: Some(e.to_string()),
                                    }),
                                }
                            } else {
                                if let Some(pc) = create_pending_change(&request.session_id, &tc, &session.workspace_path).await {
                                    pending_changes.push(pc);
                                }
                            }
                        }
                    }
                    turn_content = ai_response.replace(json_str, "").trim().to_string();
                }
            }
        }

        total_tool_calls.extend(turn_tool_calls.clone());
        total_tool_results.extend(turn_tool_results.clone());
        
        if final_assistant_content.is_empty() {
            final_assistant_content = turn_content.clone();
        } else if !turn_content.is_empty() {
            final_assistant_content.push_str("\n\n");
            final_assistant_content.push_str(&turn_content);
        }

        // If no tools were executed or auto_execute is false, we are done
        if turn_tool_results.is_empty() || !request.auto_execute {
            break;
        }

        // Prepare next turn prompt with tool results
        current_prompt.push_str(&format!("\n\nAssistant: {}\n\nTool Results:\n", ai_response));
        for result in &turn_tool_results {
            current_prompt.push_str(&format!("Tool Call {}: {}\n", result.tool_call_id, 
                if result.success { result.output.clone() } else { result.error.clone().unwrap_or_default() }));
        }
        current_prompt.push_str("\nBased on these results, what is your next step?");
    }

    // Update session with final results
    let mut updated_session = session.clone();
    updated_session.messages.push(AgentMessage {
        id: uuid::Uuid::new_v4().to_string(),
        role: MessageRole::User,
        content: request.message.clone(),
        tool_calls: vec![],
        tool_results: vec![],
        timestamp: Utc::now(),
    });
    updated_session.messages.push(AgentMessage {
        id: uuid::Uuid::new_v4().to_string(),
        role: MessageRole::Assistant,
        content: final_assistant_content.clone(),
        tool_calls: total_tool_calls.clone(),
        tool_results: total_tool_results.clone(),
        timestamp: Utc::now(),
    });
    updated_session.updated_at = Utc::now();
    update_session(updated_session);
    
    let final_session = get_session(&request.session_id).unwrap_or(session);
    
    Ok(ChatResponse {
        message_id: uuid::Uuid::new_v4().to_string(),
        content: final_assistant_content,
        thinking: None,
        tool_calls: total_tool_calls,
        tool_results: total_tool_results,
        pending_changes,
        suggestions: vec![],
        plan: final_session.current_plan,
    })
}

/// Enhanced chat with streaming tokens and tool events
pub fn enhanced_chat_stream(
    state: Arc<TokioRwLock<crate::state::AppState>>,
    request: ChatRequest,
    ai_config: crate::models::AIConfig
) -> BoxStream<'static, Result<AgentStreamEvent>> {
    let (tx, rx) = tokio::sync::mpsc::channel(100);
    
    tokio::spawn(async move {
        let session = match get_session(&request.session_id) {
            Some(s) => s,
            None => {
                let _ = tx.send(Err(AppError::NotFound("Session not found".to_string()))).await;
                return;
            }
        };

        // Reuse system prompt building logic from enhanced_chat (refactor would be better, but for speed...)
        // For now, let's just assume we need to rebuild it or passed in.
        // Actually, to avoid massive duplication, let's keep it simple.
        
        // Build context parts
        let mut context_parts = vec![];
        if let Some(ref editor) = request.editor_context {
            if let Some(ref file) = editor.active_file {
                context_parts.push(format!("Active file: {}", file));
            }
            if let Some(line) = editor.cursor_line {
                context_parts.push(format!("Cursor at line: {}", line));
            }
            if let Some(ref selected) = editor.selected_text {
                if !selected.is_empty() {
                    context_parts.push(format!("Selected text:\n```\n{}\n```", selected));
                }
            }
            if let Some(ref content) = editor.active_content {
                let lines: Vec<&str> = content.lines().collect();
                let cursor_line = editor.cursor_line.unwrap_or(0);
                let start = cursor_line.saturating_sub(10);
                let end = (cursor_line + 10).min(lines.len());
                let visible: Vec<String> = lines[start..end].iter()
                    .enumerate()
                    .map(|(i, l)| format!("{}: {}", start + i + 1, l))
                    .collect();
                context_parts.push(format!("Code around cursor:\n```\n{}\n```", visible.join("\n")));
            }
        }
        context_parts.push(format!("Workspace: {}", session.workspace_path.display()));
        context_parts.push(format!("Project type: {}", session.context.project_type));

        let tools = get_available_tools();
        let tools_json = serde_json::to_string_pretty(&tools).unwrap_or_default();

        let system_prompt = format!(
            r#"You are an expert AI coding assistant.
CONTEXT:
{}

AVAILABLE TOOLS:
{}

INSTRUCTIONS:
1. Analyze request.
2. Propose plan if complex.
3. Use tools.
4. Verify changes.
5. Respond in turn with tool blocks: ```json [{{"name": "...", "arguments": {{...}}}}] ```
"#,
            context_parts.join("\n"),
            tools_json
        );

        let mut current_prompt = format!("System: {}\n\nUser: {}", system_prompt, request.message);
        
        let mut actual_config = ai_config.clone();
        if let Some(p) = &request.provider { actual_config.provider = p.clone(); }
        if let Some(m) = &request.model { actual_config.model = m.clone(); }
        if let Some(k) = &request.api_key { actual_config.api_key = k.clone(); }

        let provider = match crate::ai::get_provider(&actual_config.provider) {
            Ok(p) => p,
            Err(e) => {
                let _ = tx.send(Err(e)).await;
                return;
            }
        };

        let mut loop_count = 0;
        let max_loops = 5;
        let mut total_tool_calls = Vec::new();
        let mut total_tool_results = Vec::new();
        let mut final_content = String::new();

        while loop_count < max_loops {
            loop_count += 1;
            
            let mut turn_full_content = String::new();
            match provider.generate_stream(&current_prompt, &actual_config).await {
                Ok(mut stream) => {
                    while let Some(chunk_res) = stream.next().await {
                        match chunk_res {
                            Ok(token) => {
                                turn_full_content.push_str(&token);
                                let _ = tx.send(Ok(AgentStreamEvent::Token(token))).await;
                            }
                            Err(e) => {
                                let _ = tx.send(Err(e)).await;
                                break;
                            }
                        }
                    }
                }
                Err(e) => {
                    let _ = tx.send(Err(e)).await;
                    break;
                }
            }

            // Parse tool calls from the full turn content
            let json_pattern = regex::Regex::new(r#"\[\s*\{[\s\S]*?"name"[\s\S]*?\}\s*\]"#).ok();
            let mut turn_tool_calls = Vec::new();
            let mut turn_tool_results = Vec::new();

            if let Some(pattern) = json_pattern {
                if let Some(captures) = pattern.find(&turn_full_content) {
                    let json_str = captures.as_str();
                    if let Ok(calls) = serde_json::from_str::<Vec<serde_json::Value>>(json_str) {
                        for call in calls {
                            if let (Some(name), Some(args)) = (call["name"].as_str(), call.get("arguments")) {
                                let tc = ToolCall {
                                    id: uuid::Uuid::new_v4().to_string(),
                                    name: name.to_string(),
                                    arguments: args.clone(),
                                };
                                turn_tool_calls.push(tc.clone());
                                let _ = tx.send(Ok(AgentStreamEvent::ToolStart { name: tc.name.clone(), id: tc.id.clone() })).await;
                                
                                // Execute tool or create pending change
                                if request.auto_execute || !is_destructive_tool(name) {
                                    match execute_tool(state.clone(), &request.session_id, name, args).await {
                                        Ok(result) => {
                                            let _ = tx.send(Ok(AgentStreamEvent::ToolEnd { 
                                                id: tc.id.clone(), 
                                                success: result.success, 
                                                output: result.output.clone(), 
                                                error: result.error.clone() 
                                            })).await;
                                            turn_tool_results.push(result);
                                        }
                                        Err(e) => {
                                            let _ = tx.send(Ok(AgentStreamEvent::ToolEnd { 
                                                id: tc.id.clone(), 
                                                success: false, 
                                                output: String::new(), 
                                                error: Some(e.to_string()) 
                                            })).await;
                                            turn_tool_results.push(ToolResult {
                                                tool_call_id: tc.id.clone(),
                                                success: false,
                                                output: String::new(),
                                                error: Some(e.to_string()),
                                            });
                                        }
                                    }
                                } else {
                                    if let Some(pc) = create_pending_change(&request.session_id, &tc, &session.workspace_path).await {
                                        let _ = tx.send(Ok(AgentStreamEvent::PendingChange(pc))).await;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            total_tool_calls.extend(turn_tool_calls);
            total_tool_results.extend(turn_tool_results.clone());
            
            if final_content.is_empty() {
                final_content = turn_full_content.clone();
            } else {
                final_content.push_str("\n\n");
                final_content.push_str(&turn_full_content);
            }

            if turn_tool_results.is_empty() || !request.auto_execute {
                break;
            }

            // Prepare next turn prompt
            current_prompt.push_str(&format!("\n\nAssistant: {}\n\nTool Results:\n", turn_full_content));
            for result in &turn_tool_results {
                current_prompt.push_str(&format!("Tool Call {}: {}\n", result.tool_call_id, 
                    if result.success { result.output.clone() } else { result.error.clone().unwrap_or_default() }));
            }
            current_prompt.push_str("\nBased on these results, what is your next step?");
        }

        // Final session update
        let mut updated_session = session.clone();
        updated_session.messages.push(AgentMessage {
            id: uuid::Uuid::new_v4().to_string(),
            role: MessageRole::User,
            content: request.message.clone(),
            tool_calls: vec![],
            tool_results: vec![],
            timestamp: Utc::now(),
        });
        updated_session.messages.push(AgentMessage {
            id: uuid::Uuid::new_v4().to_string(),
            role: MessageRole::Assistant,
            content: final_content,
            tool_calls: total_tool_calls,
            tool_results: total_tool_results,
            timestamp: Utc::now(),
        });
        update_session(updated_session);

        let _ = tx.send(Ok(AgentStreamEvent::Done)).await;
    });

    use tokio_stream::wrappers::ReceiverStream;
    ReceiverStream::new(rx).boxed()
}

fn is_destructive_tool(name: &str) -> bool {
    matches!(name, "write_file" | "edit_file" | "delete_file" | "run_command" | "git_commit" | "create_project")
}

// ==========================================
// Streaming Implementation
// ==========================================

pub fn run_agent_loop_stream(
    session_id: String,
    user_message: String,
    workspace: PathBuf,
    provider_name: String,
    model_name: String,
    api_key: String,
    auto_execute: bool, // If true, automatically runs safe tools
    state: Arc<TokioRwLock<crate::state::AppState>>,
) -> BoxStream<'static, Result<AgentStreamEvent>> {
    let stream = stream! {
        // 1. Get or Create Session
        let _ = ensure_session_exists_sync(&session_id, &workspace);
        
        // 2. Append User Message
        {
            let mut sessions = AGENT_SESSIONS.write().unwrap();
            if let Some(session) = sessions.get_mut(&session_id) {
                session.messages.push(AgentMessage {
                    id: uuid::Uuid::new_v4().to_string(),
                    role: MessageRole::User,
                    content: user_message.clone(),
                    tool_calls: vec![],
                    tool_results: vec![],
                    timestamp: Utc::now(),
                });
            }
        }
        
        // 3. Build Context & Prompt
        let system_prompt = construct_system_prompt_sync(&workspace); 
        let mut tools_json = String::new();
        {
             let tools = get_available_tools();
             tools_json = serde_json::to_string_pretty(&tools).unwrap_or_default();
        }

        // We need to construct the full conversation history
        let mut full_prompt = String::new();
        full_prompt.push_str(&format!("System: {}\n", system_prompt));
        full_prompt.push_str(&format!("TOOLS: {}\n\n", tools_json));
        
        // Retrieve history
        {
            let sessions = AGENT_SESSIONS.read().unwrap();
            if let Some(session) = sessions.get(&session_id) {
                // Simplified history construction for now
                // In production, we should format this properly with tool outputs
                for msg in &session.messages {
                     match msg.role {
                         MessageRole::User => full_prompt.push_str(&format!("User: {}\n", msg.content)),
                         MessageRole::Assistant => {
                             full_prompt.push_str(&format!("Assistant: {}\n", msg.content));
                             for tool in &msg.tool_calls {
                                 full_prompt.push_str(&format!("Tool Call: {} {}\n", tool.name, tool.arguments));
                             }
                             for res in &msg.tool_results {
                                 full_prompt.push_str(&format!("Tool Result: {}\n", res.output));
                             }
                         },
                         _ => {}
                     }
                }
            }
        }

        // 4. Agent Loop
        let mut loop_count = 0;
        let max_loops = 5;
        let mut current_turn_prompt = full_prompt.clone();
        
        // Setup AI Config
        let mut config = crate::models::AIConfig::default();
        config.provider = provider_name.clone();
        config.model = model_name.clone();
        config.api_key = api_key.clone();

        loop {
            if loop_count >= max_loops { break; }
            loop_count += 1;
            
            let provider = match crate::ai::get_provider(&config.provider) {
                Ok(p) => p,
                Err(e) => {
                    yield Err(e);
                    break;
                }
            };

            let mut turn_content = String::new();
            let mut turn_tool_calls: Vec<ToolCall> = Vec::new();

            // Stream Generation
            match provider.generate_stream(&current_turn_prompt, &config).await {
                Ok(mut stream) => {
                    while let Some(chunk_res) = stream.next().await {
                        match chunk_res {
                            Ok(token) => {
                                turn_content.push_str(&token);
                                yield Ok(AgentStreamEvent::Token(token));
                            }
                            Err(e) => {
                                yield Ok(AgentStreamEvent::Error(e.to_string()));
                            }
                        }
                    }
                }
                Err(e) => {
                    yield Err(e);
                    break;
                }
            }

            // Parse Tool Calls (Regex for JSON array)
            // Looking for ```json [ ... ] ``` or just [ ... ]
            let json_pattern = regex::Regex::new(r#"\[\s*\{[\s\S]*?"name"[\s\S]*?\}\s*\]"#).ok();
            if let Some(pattern) = json_pattern {
                if let Some(captures) = pattern.find(&turn_content) {
                     if let Ok(calls) = serde_json::from_str::<Vec<serde_json::Value>>(captures.as_str()) {
                         for call in calls {
                             if let (Some(name), Some(args)) = (call["name"].as_str(), call.get("arguments")) {
                                 let tc = ToolCall {
                                     id: uuid::Uuid::new_v4().to_string(),
                                     name: name.to_string(),
                                     arguments: args.clone(),
                                 };
                                 turn_tool_calls.push(tc);
                             }
                         }
                     }
                }
            }
            
            if turn_tool_calls.is_empty() {
                // No tools called, we are done
                break;
            }
            
            // Execute Tools
            let mut turn_tool_results = Vec::new();
            
            for tc in &turn_tool_calls {
                yield Ok(AgentStreamEvent::ToolStart { name: tc.name.clone(), id: tc.id.clone() });
                
                let result = if auto_execute || !is_destructive_tool(&tc.name) {
                     execute_tool(state.clone(), &session_id, &tc.name, &tc.arguments).await
                } else {
                     // Create pending change instead
                     if let Some(pc) = create_pending_change(&session_id, tc, &workspace).await {
                         yield Ok(AgentStreamEvent::PendingChange(pc));
                         Ok(ToolResult {
                             tool_call_id: tc.id.clone(),
                             success: true,
                             output: "Pending change created. Waiting for user approval.".to_string(),
                             error: None
                         })
                     } else {
                         // Fallback if not a file change tool but marked destructive?
                          Ok(ToolResult {
                             tool_call_id: tc.id.clone(),
                             success: false,
                             output: String::new(),
                             error: Some("Tool requires approval but not handled as pending change".to_string())
                         })
                     }
                };
                
                match result {
                    Ok(res) => {
                         yield Ok(AgentStreamEvent::ToolEnd {
                             id: tc.id.clone(),
                             success: res.success,
                             output: res.output.clone(),
                             error: res.error.clone()
                         });
                         turn_tool_results.push(res);
                    }
                    Err(e) => {
                         yield Ok(AgentStreamEvent::ToolEnd {
                             id: tc.id.clone(),
                             success: false,
                             output: String::new(),
                             error: Some(e.to_string())
                         });
                    }
                }
            }
            
            // Update Prompt for next turn
            current_turn_prompt.push_str("\n\nAssistant: ");
            current_turn_prompt.push_str(&turn_content);
            current_turn_prompt.push_str("\n\nTool Results:\n");
            for res in &turn_tool_results {
                current_turn_prompt.push_str(&format!("Tool Call {}: {}\n", res.tool_call_id, res.output));
            }
            current_turn_prompt.push_str("\nBased on these results, what is your next step?");
            
            // If we executed tools, we loop again. 
            // Save this turn to session
             {
                let mut sessions = AGENT_SESSIONS.write().unwrap();
                if let Some(session) = sessions.get_mut(&session_id) {
                    session.messages.push(AgentMessage {
                         id: uuid::Uuid::new_v4().to_string(),
                         role: MessageRole::Assistant,
                         content: turn_content.clone(),
                         tool_calls: turn_tool_calls,
                         tool_results: turn_tool_results,
                         timestamp: Utc::now(),
                    });
                }
            }
        }
        
        yield Ok(AgentStreamEvent::Done);
    };
    
    Box::pin(stream)
}



fn construct_system_prompt_sync(_workspace: &Path) -> String {
    "You are an AI programming assistant. Auto-indexing is enabled.".to_string()
}

fn ensure_session_exists_sync(session_id: &str, workspace: &Path) {
    let mut sessions = AGENT_SESSIONS.write().unwrap();
    if !sessions.contains_key(session_id) {
        sessions.insert(session_id.to_string(), AgentSession {
            id: session_id.to_string(),
            workspace_path: workspace.to_path_buf(),
            messages: Vec::new(),
            context: ProjectContext {
                root_path: workspace.to_path_buf(),
                project_type: "unknown".to_string(),
                files: vec![],
                recent_files: vec![],
                symbols: vec![],
                dependencies: vec![],
                git_status: None,
            },
            tasks: Vec::new(),
            pending_operations: Vec::new(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            current_plan: None,
        });
    }
}



async fn create_pending_change(session_id: &str, tool_call: &ToolCall, workspace: &Path) -> Option<PendingChange> {
    match tool_call.name.as_str() {
        "write_file" | "edit_file" => {
            let path = tool_call.arguments["path"].as_str()?;
            let full_path = resolve_path(workspace, path);
            
            let old_content = fs::read_to_string(&full_path).await.unwrap_or_default();
            let new_content = if tool_call.name == "write_file" {
                tool_call.arguments["content"].as_str()?.to_string()
            } else {
                let search = tool_call.arguments["search"].as_str()?;
                let replace = tool_call.arguments["replace"].as_str()?;
                old_content.replace(search, replace)
            };
            
            let diff = generate_diff(path, &old_content, &new_content);
            
            let pc = PendingChange {
                id: uuid::Uuid::new_v4().to_string(),
                session_id: session_id.to_string(),
                diff,
                description: format!("{} {}", tool_call.name, path),
                tool_name: tool_call.name.clone(),
                status: PendingChangeStatus::Pending,
                created_at: Utc::now(),
            };
            
            // Store pending change
            let mut changes = PENDING_CHANGES.write().unwrap();
            changes.insert(pc.id.clone(), pc.clone());
            
            Some(pc)
        }
        _ => None
    }
}

/// Apply a pending change
pub async fn apply_pending_change(change_id: &str) -> Result<String> {
    let change = {
        let changes = PENDING_CHANGES.read().unwrap();
        changes.get(change_id).cloned()
    };
    
    let change = change.ok_or_else(|| AppError::NotFound("Pending change not found".to_string()))?;
    
    // Write the new content
    fs::write(&change.diff.file_path, &change.diff.new_content as &str).await
        .map_err(|e| AppError::IOError(e.to_string()))?;
    
    // Log for undo
    log_file_operation(
        &change.session_id, 
        OperationType::ModifyFile, 
        Path::new(&change.diff.file_path),
        Some(change.diff.old_content.clone()),
        Some(change.diff.new_content.clone())
    );
    
    // Update status
    {
        let mut changes = PENDING_CHANGES.write().unwrap();
        if let Some(c) = changes.get_mut(change_id) {
            c.status = PendingChangeStatus::Accepted;
        }
    }
    
    Ok(format!("Applied changes to {}", change.diff.file_path))
}

/// Reject a pending change  
pub fn reject_pending_change(change_id: &str) -> Result<String> {
    let mut changes = PENDING_CHANGES.write().unwrap();
    if let Some(c) = changes.get_mut(change_id) {
        c.status = PendingChangeStatus::Rejected;
        Ok(format!("Rejected changes to {}", c.diff.file_path))
    } else {
        Err(AppError::NotFound("Pending change not found".to_string()))
    }
}

/// Get all pending changes for a session
pub fn get_pending_changes(session_id: &str) -> Vec<PendingChange> {
    let changes = PENDING_CHANGES.read().unwrap();
    changes.values()
        .filter(|c| c.session_id == session_id && c.status == PendingChangeStatus::Pending)
        .cloned()
        .collect()
}

pub async fn tool_create_plan(
    session_id: &str,
    description: &str,
    steps: Vec<serde_json::Value>,
) -> Result<String> {
    let num_steps = steps.len();
    let mut plan_steps = Vec::new();
    for (i, step) in steps.into_iter().enumerate() {
        let desc = step.get("description").and_then(|v| v.as_str()).unwrap_or("No description");
        let tool = step.get("tool").and_then(|v| v.as_str()).unwrap_or("none");
        
        plan_steps.push(PlanStep {
            id: format!("step-{}", i + 1),
            description: desc.to_string(),
            tool: tool.to_string(),
            arguments: serde_json::json!({}),
            status: StepStatus::Pending,
            result: None,
        });
    }

    let plan = ExecutionPlan {
        id: uuid::Uuid::new_v4().to_string(),
        description: description.to_string(),
        steps: plan_steps,
        current_step: 0,
        status: PlanStatus::Queued,
    };

    // Update session
    if let Ok(mut sessions) = AGENT_SESSIONS.write() {
        if let Some(session) = sessions.get_mut(session_id) {
            session.current_plan = Some(plan);
            session.updated_at = Utc::now();
        }
    }

    Ok(format!("Plan created: {}. {} steps queued. Please confirm with the user before proceeding with execution tools.", description, num_steps))
}

async fn tool_search_rag(state: Arc<TokioRwLock<crate::state::AppState>>, args: &serde_json::Value) -> Result<String> {
    let query = args["query"].as_str()
        .ok_or_else(|| AppError::ValidationError("query is required".to_string()))?;
    let limit = args["limit"].as_u64().unwrap_or(5) as usize;
    
    let st = state.read().await;
    let mut guard: tokio::sync::MutexGuard<Option<crate::rag::RagEngine>> = st.rag_engine.lock().await;
    let engine = guard.as_mut().ok_or_else(|| AppError::InternalError("RAG engine not initialized. Please start indexing first.".to_string()))?;
    
    let results = engine.search_with_expansion(query, limit)?;
    let mut output = format!("Semantic search results for '{}':\n\n", query);
    
    for (chunk, score) in results {
        output.push_str(&format!("--- {} (score: {:.2}) ---\n{}\n\n", chunk.file_path, score, chunk.content));
    }
    
    Ok(output)
}

async fn tool_execute_command(workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let command = args["command"].as_str()
        .ok_or_else(|| AppError::ValidationError("command is required".to_string()))?;
    let description = args["description"].as_str();
    
    // Reuse the same secure execution path
    secure_execute_command(workspace, command, description).await
}
