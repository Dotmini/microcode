//! CodeTunner Backend
//!
//! A Rust-based backend server for the CodeTunner IDE
//! Provides AI integration, code analysis, and file operations

use axum::{
    extract::{State, WebSocketUpgrade},
    response::{IntoResponse, sse::{Event, Sse, KeepAlive}},
    routing::{get, post},
    Json, Router,
};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::RwLock;
use tower_http::cors::{Any, CorsLayer};
use tracing::{info, Level};
use tracing_subscriber;
use futures::SinkExt;
use futures::StreamExt;
use std::convert::Infallible;

mod ai;
mod code;
mod error;
mod data;
mod terminal;
mod git;
mod models;
mod tasks;
mod runner;
mod state;
mod kernel;
mod dotnet;
mod ml;
mod project;
mod agent;
mod scenario;
mod network;
mod rosetta;
mod live_preview;
mod hot_reload;
mod preview_v2;
mod remote;
mod nodejs;
mod database;
mod cicd;
mod ai_report;
mod indexer;
mod rag;
mod ai_ultra;
mod ftp;
pub mod ai_engine; /// Hybrid AI Engine (Fast + Smart Tier)
pub mod device_manager;
pub mod crash_decoder;

use crate::error::Result;
use crate::state::AppState;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_max_level(Level::INFO)
        .init();

    // Load environment variables
    dotenv::dotenv().ok();

    info!("Starting CodeTunner Backend v2.0.0");

    // Initialize    let terminal_manager = Arc::new(crate::terminal::TerminalManager::new());
    
    // Create shared state
    let state = Arc::new(RwLock::new(AppState::new()));
    
    // Inject terminal manager into state (need to update AppState first)
    // For now, let's create a separate state extension or just use a global for this specific feature if AppState refactor is too large.
    // Actually, let's update AppState in state.rs next.
    
    let app = Router::new()
        // ... routes
        .route("/ws/terminal", get(handlers::terminal_ws))
        // Health check
        .route("/health", get(health_check))

        // File operations
        .route("/api/files/list", post(handlers::list_files))
        .route("/api/files/read", post(handlers::read_file))
        .route("/api/files/write", post(handlers::write_file))
        .route("/api/files/delete", post(handlers::delete_file))
        .route("/api/files/mkdir", post(handlers::create_directory))
        
        // Data Sharing
        .route("/api/data/list", get(handlers::data_list))
        .route("/api/data/get/:name", get(handlers::data_get))
        .route("/api/data/store/:name", post(handlers::data_store))
        // IPC / Shared Memory Optimized Routes
        .route("/api/data/shm/get/:name", get(handlers::data_get_shm))
        .route("/api/data/shm/store/:name", post(handlers::data_store_shm))

        // Code operations
        .route("/api/code/analyze", post(handlers::analyze_code))
        .route("/api/code/format", post(handlers::format_code))
        .route("/api/ai/format", post(handlers::ai_format)) // AI Formatter Endpoint
        .route("/api/code/highlight", post(handlers::highlight_code))

        // AI operations
        .route("/api/ai/refactor", post(handlers::ai_refactor))
        .route("/api/ai/transpile", post(handlers::ai_transpile))
        .route("/api/ai/refactor/ultra", post(handlers::ai_refactor_ultra))
        .route("/api/ai/refactor/stream", post(handlers::ai_refactor_stream))
        .route("/api/ai/refactor/report", post(handlers::ai_refactor_report))
        .route("/api/ai/explain", post(handlers::ai_explain))
        .route("/api/ai/models", get(handlers::list_ai_models))

        // Git operations
        .route("/api/git/status", post(handlers::git_status))
        .route("/api/git/commit", post(handlers::git_commit))
        .route("/api/git/push", post(handlers::git_push))
        .route("/api/git/pull", post(handlers::git_pull))
        .route("/api/git/log", post(handlers::git_log))
        .route("/api/git/diff", post(handlers::git_diff))

        // DataFrame operations
        .route("/api/dataframe/load", post(handlers::load_dataframe))
        .route("/api/dataframe/slice", post(handlers::get_dataframe_slice))
        .route("/api/dataframe/schema", post(handlers::get_dataframe_schema))
        
        // Task Management (Phase 10)
        .route("/api/tasks/list", get(crate::tasks::list_tasks))
        .route("/api/tasks/create", post(crate::tasks::create_task))
        .route("/api/tasks/update/:id", post(crate::tasks::update_status))
        .route("/api/tasks/:id/branch", post(crate::tasks::create_branch_for_task))
        .route("/api/git/webhook", post(crate::tasks::handle_git_webhook));

    // Initialize Hybrid AI Engine (Background)
    let ai_state = state.clone();
    tokio::spawn(async move {
        info!("Initializing Hybrid AI Engine (Fast Tier)...");
        let result = tokio::task::spawn_blocking(|| {
            crate::ai_engine::fast_tier::FastTierEngine::new()
        }).await;

        match result {
             Ok(Ok(engine)) => {
                 let st = ai_state.read().await;
                 let mut guard = st.fast_tier.lock().await;
                 *guard = Some(engine);
                 info!("Hybrid AI Engine (Fast Tier) READY.");
             },
             Ok(Err(e)) => {
                 info!("Hybrid AI Engine initialization failed (likely download error): {}", e);
             },
             Err(e) => {
                 info!("Hybrid AI Engine task join error: {}", e);
             }
        }
    });

    // Pre-warm Syntax Highlighter (Background)
    tokio::spawn(async move {
        info!("Pre-warming Syntax Highlighter...");
        let start = std::time::Instant::now();
        tokio::task::spawn_blocking(|| {
            crate::code::highlighter::init();
        }).await.ok();
        info!("Syntax Highlighter READY (took {:?})", start.elapsed());
    });

    // Handle WebSocket connections
    let ws_handler = |ws: WebSocketUpgrade, State(state): State<Arc<RwLock<AppState>>>| async move {
        ws.on_upgrade(|socket| handle_socket(socket, state))
    };

    let app = app // Continue chain from the first definition
        // Code execution
        .route("/api/run/execute", post(handlers::execute_code))
        .route("/api/run/stream", post(handlers::execute_code_stream))
        .route("/api/run/stop/:id", post(handlers::stop_execution))

        // .NET endpoints
        .route("/api/dotnet/version", get(handlers::dotnet_version))
        .route("/api/dotnet/new", post(handlers::dotnet_new_project))
        .route("/api/dotnet/build", post(handlers::dotnet_build))
        .route("/api/dotnet/run", post(handlers::dotnet_run))
        .route("/api/dotnet/restore", post(handlers::dotnet_restore))
        .route("/api/dotnet/add-package", post(handlers::dotnet_add_package))
        .route("/api/dotnet/clean", post(handlers::dotnet_clean))
        .route("/api/dotnet/templates", get(handlers::dotnet_templates))
        
        // ML Training routes
        .route("/api/ml/dataset/scan", post(handlers::ml_scan_dataset))
        .route("/api/ml/training/start", post(handlers::ml_start_training))
        .route("/api/ml/training/progress/:session_id", get(handlers::ml_training_progress))
        .route("/api/ml/training/stop/:session_id", post(handlers::ml_stop_training))
        .route("/api/ml/export", post(handlers::ml_export_model))
        
        // Project Build routes
        .route("/api/project/detect", post(handlers::project_detect))
        .route("/api/project/build", post(handlers::project_build))
        .route("/api/project/run", post(handlers::project_run))
        .route("/api/project/test", post(handlers::project_test))
        .route("/api/project/clean", post(handlers::project_clean))
        
        // AI Agent routes
        .route("/api/agent/session/create", post(handlers::agent_create_session))
        .route("/api/agent/session/:session_id", get(handlers::agent_get_session))
        .route("/api/agent/context/:session_id", get(handlers::agent_get_context))
        .route("/api/agent/tool/execute", post(handlers::agent_execute_tool))
        .route("/api/agent/tools", get(handlers::agent_list_tools))
        // Production AI Agent - Like Cursor/Windsurf
        .route("/api/agent/enhanced-chat", post(handlers::agent_enhanced_chat))
        .route("/api/agent/enhanced-chat/stream", post(handlers::agent_enhanced_chat_stream))
        .route("/api/agent/index/start", post(handlers::agent_index_start))
        .route("/api/agent/pending-changes/:session_id", get(handlers::agent_get_pending_changes))
        .route("/api/agent/apply-change/:change_id", post(handlers::agent_apply_change))
        .route("/api/agent/reject-change/:change_id", post(handlers::agent_reject_change))
        
        // Scenario Automation routes
        .route("/api/scenario/execute", post(handlers::scenario_execute))
        .route("/api/scenario/node/execute", post(handlers::scenario_execute_node))
        
        // Live Preview (Hot Reload) routes
        .route("/api/preview/reload", post(handlers::preview_reload))
        .route("/api/preview/status", get(handlers::preview_status))
        .route("/api/preview/agent/start", post(handlers::preview_start_agent))
        .route("/api/preview/agent/stop", post(handlers::preview_stop_agent))
        
        // Hot Reload Engine routes (Thunk Table + State)
        .route("/api/hotreload/thunk/list", get(handlers::hotreload_list_thunks))
        .route("/api/hotreload/thunk/register", post(handlers::hotreload_register_thunk))
        .route("/api/hotreload/state/snapshot", get(handlers::hotreload_state_snapshot))
        .route("/api/hotreload/state/clear", post(handlers::hotreload_state_clear))
        .route("/api/hotreload/rollback", post(handlers::hotreload_rollback))
        .route("/api/hotreload/version", get(handlers::hotreload_version))

        // Remote X Support
        .route("/api/remote/connect", post(remote::remote_connect))
        .route("/api/remote/ping", post(remote::remote_ping))
        .route("/api/remote/shell/:id", get(remote::remote_shell_ws))
        .route("/api/remote/exec", post(remote::remote_exec)) 
        .route("/api/remote/files", post(remote::remote_list_files))
        .route("/api/remote/upload", post(remote::remote_upload))
        .route("/api/remote/download", post(remote::remote_download))
        .route("/api/remote/mkdir", post(remote::remote_mkdir))
        .route("/api/remote/remove", post(remote::remote_remove))
        .route("/api/remote/rename", post(remote::remote_rename))

        // Node.js Version Manager
        .route("/api/node/versions", get(nodejs::list_versions))
        .route("/api/node/select", post(nodejs::select_version))

        // Database
        // Database
        .route("/api/db/connect", post(handlers::db_connect))
        .route("/api/db/query", post(handlers::db_query))

        // Hybrid AI (Fast Tier)
        .route("/api/ai/complete", post(ai_engine::handlers::handle_completion))

        // Network Proxy
        .route("/api/network/proxy", post(handlers::proxy_request))
        
        // CI/CD
        .route("/api/cicd/runs", post(handlers::cicd_list_runs))
        .route("/api/cicd/jobs", post(handlers::cicd_run_jobs))
        .route("/api/cicd/trigger", post(handlers::cicd_trigger))
        .route("/api/cicd/logs", post(handlers::cicd_get_logs))

        // WebSocket for real-time updates
        .route("/ws", get(ws_handler))

        // CORS layer
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any),
        )
        .with_state(state);

    // Start server on port 3000 (matches Swift services)
    let addr = SocketAddr::from(([127, 0, 0, 1], 3000));
    info!("Backend listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

async fn health_check() -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "ok",
        "version": "2.0.0",
        "timestamp": chrono::Utc::now().to_rfc3339()
    }))
}

async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<Arc<RwLock<AppState>>>,
) -> impl IntoResponse {
    ws.on_upgrade(|socket| handle_socket(socket, state))
}

async fn handle_socket(
    mut socket: axum::extract::ws::WebSocket,
    state: Arc<RwLock<AppState>>,
) {
    use axum::extract::ws::Message;

    // Send welcome message
    let welcome = serde_json::json!({
        "type": "connected",
        "message": "Connected to CodeTunner Backend"
    });

    if socket
        .send(Message::Text(welcome.to_string()))
        .await
        .is_err()
    {
        return;
    }

    // Handle incoming messages
    while let Some(msg) = socket.recv().await {
        match msg {
            Ok(Message::Text(text)) => {
                // Handle text messages
                if let Ok(response) = handle_ws_message(&text, &state).await {
                    let _ = socket.send(Message::Text(response)).await;
                }
            }
            Ok(Message::Close(_)) => break,
            Err(_) => break,
            _ => {}
        }
    }
}

async fn handle_ws_message(
    message: &str,
    state: &Arc<RwLock<AppState>>,
) -> Result<String> {
    let request: serde_json::Value = serde_json::from_str(message)?;

    let response = serde_json::json!({
        "type": "response",
        "data": "Message received"
    });

    Err(crate::error::AppError::NotImplemented("WebSocket handling".to_string()))
}

// Handler module
mod handlers {
    use super::*;
    use crate::models::*;
    use crate::dotnet::DotnetManager;
    use crate::state::AppState;
    use tokio::sync::RwLock;
    use axum::{extract::{Path, State, Json}, response::IntoResponse, http::StatusCode};
    use serde::{Deserialize, Serialize};
    use serde_json::json;
    use std::sync::Arc;
    use axum::response::sse::{Event, Sse, KeepAlive};
    use futures_util::StreamExt;
    use std::convert::Infallible;
    use crate::database::{DatabaseManager, DatabaseType};

    // .NET endpoint handlers
    pub async fn dotnet_version() -> impl IntoResponse {
        let manager = DotnetManager::new();
        match manager.version().await {
            Ok(version) => Json(json!({ "version": version })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to get .NET version: {}", e)).into_response(),
        }
    }

    #[derive(Debug, Deserialize)]
    pub struct NewProjectRequest {
        pub template: String,
        pub name: String,
        pub output_dir: String,
    }

    pub async fn dotnet_new_project(Json(payload): Json<NewProjectRequest>) -> impl IntoResponse {
        let manager = DotnetManager::new();
        match manager.new_project(&payload.template, &payload.name, &payload.output_dir).await {
            Ok(output) => Json(json!({
                "success": output.success,
                "stdout": output.stdout,
                "stderr": output.stderr,
            })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to create project: {}", e)).into_response(),
        }
    }

    #[derive(Debug, Deserialize)]
    pub struct BuildRequest {
        pub project_path: String,
        pub configuration: String,
    }

    pub async fn dotnet_build(Json(payload): Json<BuildRequest>) -> impl IntoResponse {
        let manager = DotnetManager::new();
        match manager.build(&payload.project_path, &payload.configuration).await {
            Ok(output) => Json(json!({
                "success": output.success,
                "stdout": output.stdout,
                "stderr": output.stderr,
                "exit_code": output.exit_code,
            })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to build: {}", e)).into_response(),
        }
    }

    #[derive(Debug, Deserialize)]
    pub struct RunRequest {
        pub project_path: String,
        pub args: Vec<String>,
    }

    pub async fn dotnet_run(Json(payload): Json<RunRequest>) -> impl IntoResponse {
        let manager = DotnetManager::new();
        match manager.run(&payload.project_path, payload.args).await {
            Ok(output) => Json(json!({
                "stdout": output.stdout,
                "stderr": output.stderr,
                "exit_code": output.exit_code,
            })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to run: {}", e)).into_response(),
        }
    }

    #[derive(Debug, Deserialize)]
    pub struct RestoreRequest {
        pub project_path: String,
    }

    pub async fn dotnet_restore(Json(payload): Json<RestoreRequest>) -> impl IntoResponse {
        let manager = DotnetManager::new();
        match manager.restore(&payload.project_path).await {
            Ok(output) => Json(json!({
                "success": output.success,
                "stdout": output.stdout,
            })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to restore: {}", e)).into_response(),
        }
    }

    #[derive(Debug, Deserialize)]
    pub struct AddPackageRequest {
        pub project_path: String,
        pub package_name: String,
        pub version: Option<String>,
    }

    pub async fn dotnet_add_package(Json(payload): Json<AddPackageRequest>) -> impl IntoResponse {
        let manager = DotnetManager::new();
        match manager.add_package(&payload.project_path, &payload.package_name, payload.version.as_deref()).await {
            Ok(output) => Json(json!({
                "success": output.success,
                "stdout": output.stdout,
            })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to add package: {}", e)).into_response(),
        }
    }

    #[derive(Debug, Deserialize)]
    pub struct CleanRequest {
        pub project_path: String,
    }

    pub async fn dotnet_clean(Json(payload): Json<CleanRequest>) -> impl IntoResponse {
        let manager = DotnetManager::new();
        match manager.clean(&payload.project_path).await {
            Ok(output) => Json(json!({
                "success": output.success,
                "stdout": output.stdout,
            })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to clean: {}", e)).into_response(),
        }
    }

    pub async fn dotnet_templates() -> impl IntoResponse {
        let manager = DotnetManager::new();
        match manager.list_templates().await {
            Ok(templates) => Json(json!({ "templates": templates })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to list templates: {}", e)).into_response(),
        }
    }
    
    // ML Training handlers
    #[derive(Debug, Deserialize)]
    pub struct ScanDatasetRequest {
        pub path: String,
    }
    
    pub async fn ml_scan_dataset(Json(payload): Json<ScanDatasetRequest>) -> impl IntoResponse {
        match crate::ml::scan_dataset(&payload.path).await {
            Ok(dataset) => Json(json!(dataset)).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e).into_response(),
        }
    }
    
    #[derive(Debug, Deserialize)]
    pub struct StartTrainingRequest {
        pub dataset: crate::ml::MLDataset,
        pub config: crate::ml::TrainingConfig,
        pub base_model: String,
    }
    
    pub async fn ml_start_training(Json(payload): Json<StartTrainingRequest>) -> impl IntoResponse {
        match crate::ml::start_training(payload.dataset, payload.config, &payload.base_model).await {
            Ok(session_id) => Json(json!({ "session_id": session_id })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e).into_response(),
        }
    }
    
    pub async fn ml_training_progress(Path(session_id): Path<String>) -> impl IntoResponse {
        match crate::ml::get_training_progress(&session_id) {
            Ok(progress) => Json(json!(progress)).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e).into_response(),
        }
    }
    
    pub async fn ml_stop_training(Path(session_id): Path<String>) -> impl IntoResponse {
        match crate::ml::stop_training(&session_id) {
            Ok(_) => Json(json!({ "success": true })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e).into_response(),
        }
    }
    
    #[derive(Debug, Deserialize)]
    pub struct ExportModelRequest {
        pub session_id: String,
        pub format: String,
        pub output_path: String,
    }
    
    pub async fn ml_export_model(Json(payload): Json<ExportModelRequest>) -> impl IntoResponse {
        match crate::ml::export_model(&payload.session_id, &payload.format, &payload.output_path).await {
            Ok(path) => Json(json!({ "path": path })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e).into_response(),
        }
    }
    
    
    #[derive(Debug, Deserialize)]
    pub struct AIFormatRequest {
        pub code: String,
        pub language: String,
        pub instructions: String,
    }

    
    pub async fn ai_format(Json(payload): Json<AIFormatRequest>) -> impl IntoResponse {
        match crate::code::formatter::format_with_ai(&payload.code, &payload.language, &payload.instructions).await {
            Ok(formatted) => Json(json!({ "code": formatted })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
        }
    }
    
    // Project Build handlers
    #[derive(Debug, Deserialize)]
    pub struct ProjectRequest {
        pub path: String,
        pub is_debug: Option<bool>,
    }
    
    pub async fn project_detect(Json(payload): Json<ProjectRequest>) -> impl IntoResponse {
        use crate::project::ProjectBuilder;
        use std::path::Path;
        
        let project_type = ProjectBuilder::detect_project_type(Path::new(&payload.path));
        let type_name = project_type.as_str();
        
        let supported: Vec<&str> = match project_type {
            crate::project::ProjectType::Swift => vec!["build", "run", "test", "clean"],
            crate::project::ProjectType::Xcode => vec!["build", "clean", "test"],
            crate::project::ProjectType::Rust => vec!["build", "run", "test", "clean"],
            crate::project::ProjectType::Go => vec!["build", "run", "test", "clean"],
            crate::project::ProjectType::NodeJS => vec!["build", "run", "test", "install"],
            crate::project::ProjectType::Python => vec!["run", "test", "install"],
            crate::project::ProjectType::Flutter => vec!["build", "run", "test", "clean", "install"],
            crate::project::ProjectType::DotNet => vec!["build", "run", "test", "clean", "install"],
            crate::project::ProjectType::Java => vec!["build", "run", "test", "clean", "install"],
            crate::project::ProjectType::Android | crate::project::ProjectType::Kotlin => vec!["build", "run", "test", "clean"],
            crate::project::ProjectType::Ruby => vec!["run", "test", "install"],
            crate::project::ProjectType::CMake => vec!["build", "clean"],
            crate::project::ProjectType::Makefile => vec!["build", "run", "clean"],
            crate::project::ProjectType::Unknown => vec![],
        };
        
        Json(json!({
            "project_type": type_name,
            "supported_actions": supported
        }))
    }
    
    pub async fn project_build(Json(payload): Json<ProjectRequest>) -> impl IntoResponse {
        use crate::project::{ProjectBuilder, BuildAction, BuildConfig};
        use std::path::Path;
        
        let config = BuildConfig { is_debug: payload.is_debug.unwrap_or(true) };
        let result = ProjectBuilder::execute(Path::new(&payload.path), BuildAction::Build, config).await;
        
        Json(json!({
            "success": result.success,
            "output": result.output,
            "exit_code": result.exit_code,
            "project_type": result.project_type
        }))
    }
    
    pub async fn project_run(Json(payload): Json<ProjectRequest>) -> impl IntoResponse {
        use crate::project::{ProjectBuilder, BuildAction, BuildConfig};
        use std::path::Path;
        
        let config = BuildConfig { is_debug: payload.is_debug.unwrap_or(true) };
        let result = ProjectBuilder::execute(Path::new(&payload.path), BuildAction::Run, config).await;
        
        Json(json!({
            "success": result.success,
            "output": result.output,
            "exit_code": result.exit_code,
            "project_type": result.project_type
        }))
    }
    
    pub async fn project_test(Json(payload): Json<ProjectRequest>) -> impl IntoResponse {
        use crate::project::{ProjectBuilder, BuildAction, BuildConfig};
        use std::path::Path;
        
        let config = BuildConfig { is_debug: true };
        let result = ProjectBuilder::execute(Path::new(&payload.path), BuildAction::Test, config).await;
        
        Json(json!({
            "success": result.success,
            "output": result.output,
            "exit_code": result.exit_code,
            "project_type": result.project_type
        }))
    }
    
    pub async fn project_clean(Json(payload): Json<ProjectRequest>) -> impl IntoResponse {
        use crate::project::{ProjectBuilder, BuildAction, BuildConfig};
        use std::path::Path;
        
        let config = BuildConfig { is_debug: true };
        let result = ProjectBuilder::execute(Path::new(&payload.path), BuildAction::Clean, config).await;
        
        Json(json!({
            "success": result.success,
            "output": result.output,
            "exit_code": result.exit_code,
            "project_type": result.project_type
        }))
    }
    
    // AI Agent handlers
    #[derive(Debug, Deserialize)]
    pub struct CreateSessionRequest {
        pub workspace_path: String,
    }
    
    pub async fn agent_create_session(Json(payload): Json<CreateSessionRequest>) -> impl IntoResponse {
        match crate::agent::create_session(&payload.workspace_path) {
            Ok(session_id) => Json(json!({ "session_id": session_id })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
        }
    }
    
    pub async fn agent_get_session(Path(session_id): Path<String>) -> impl IntoResponse {
        match crate::agent::get_session(&session_id) {
            Some(session) => Json(json!(session)).into_response(),
            None => (axum::http::StatusCode::NOT_FOUND, "Session not found").into_response(),
        }
    }
    
    pub async fn agent_get_context(Path(session_id): Path<String>) -> impl IntoResponse {
        let session = match crate::agent::get_session(&session_id) {
            Some(s) => s,
            None => return (axum::http::StatusCode::NOT_FOUND, "Session not found").into_response(),
        };
        
        match crate::agent::build_context(&session.workspace_path, 3).await {
            Ok(context) => Json(json!(context)).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
        }
    }
    
    #[derive(Debug, Deserialize)]
    pub struct ExecuteToolRequest {
        pub session_id: String,
        pub tool_name: String,
        pub arguments: serde_json::Value,
    }
    
    pub async fn agent_execute_tool(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(payload): Json<ExecuteToolRequest>
    ) -> impl IntoResponse {
        match crate::agent::execute_tool(state, &payload.session_id, &payload.tool_name, &payload.arguments).await {
            Ok(result) => Json(json!(result)).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
        }
    }
    
    pub async fn agent_list_tools() -> impl IntoResponse {
        Json(json!({ "tools": crate::agent::get_available_tools() }))
    }
    
    pub async fn agent_undo(Path(session_id): Path<String>) -> impl IntoResponse {
        match crate::agent::undo_last_operation(&session_id).await {
            Ok(msg) => Json(json!({ "success": true, "message": msg })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
        }
    }
    
    #[derive(Debug, Deserialize)]
    pub struct AgentChatRequest {
        pub session_id: String,
        pub message: String,
        pub provider: Option<String>,
        pub model: Option<String>,
        pub api_key: Option<String>,
        pub workspace_path: Option<String>,
    }
    
    pub async fn agent_chat(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(payload): Json<AgentChatRequest>,
    ) -> impl IntoResponse {
        (axum::http::StatusCode::NOT_IMPLEMENTED, "Use /api/agent/enhanced-chat").into_response()
    }

    #[derive(Debug, Deserialize)]
    pub struct IndexRequest {
        pub workspace_path: String,
    }

    pub async fn agent_index_start(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<IndexRequest>,
    ) -> Result<Json<serde_json::Value>> {
        let st = state.read().await;
        let rag_engine_ptr = st.rag_engine.clone();
        let path = std::path::PathBuf::from(req.workspace_path);
        
        tokio::spawn(async move {
            info!("Starting background indexing for {:?}", path);
            let mut indexer = crate::indexer::Indexer::new();
            
            // 1. Get all files and symbols
            if let Ok((_files, symbols)) = crate::agent::index_files(&path, 5, &mut indexer).await {
                // 2. Initialize RAG engine if not already
                let mut guard: tokio::sync::MutexGuard<Option<crate::rag::RagEngine>> = rag_engine_ptr.lock().await;
                if guard.is_none() {
                    if let Ok(engine) = crate::rag::RagEngine::new() {
                        *guard = Some(engine);
                    }
                }
                
                if let Some(engine) = guard.as_mut() {
                    // 3. Convert symbols to chunks for RAG
                    let mut chunks = Vec::new();
                    for sym in symbols {
                        if let Ok(content) = tokio::fs::read_to_string(&sym.file_path).await {
                            // Only chunk a reasonable window around the symbol if needed, 
                            // but for now the symbol extractor already gives us chunks.
                            // Actually crate::agent::index_files already used indexer.chunk_file.
                            // Let's just re-chunk specifically for RAG to be sure.
                            if let Ok(file_chunks) = indexer.chunk_file(&sym.file_path, &content) {
                                chunks.extend(file_chunks);
                            }
                        }
                    }
                    
                    let engine_ref: &mut crate::rag::RagEngine = guard.as_mut().unwrap();
                    let _ = engine_ref.build_index(chunks);
                    info!("Indexing complete. RAG engine READY.");
                }
            }
        });

        Ok(Json(serde_json::json!({ "success": true, "message": "Indexing started in background" })))
    }

    pub async fn agent_enhanced_chat(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(payload): Json<AgentChatRequest>,
    ) -> impl IntoResponse {
        let workspace = payload.workspace_path
            .as_ref()
            .map(std::path::PathBuf::from)
            .unwrap_or_else(|| std::env::current_dir().unwrap_or(std::path::PathBuf::from(".")));

        let stream = crate::agent::run_agent_loop_stream(
            payload.session_id,
            payload.message,
            workspace,
            payload.provider.unwrap_or("gemini".to_string()),
            payload.model.unwrap_or("gemini-2.5-flash".to_string()),
            payload.api_key.unwrap_or_default(),
            true, // Auto execute
            state,
        );

        let sse_stream = stream.map(|res| {
            match res {
                Ok(event) => {
                    let json = serde_json::to_string(&event).unwrap_or("{}".to_string());
                    Ok::<Event, axum::Error>(Event::default().data(json))
                }
                Err(e) => {
                     Ok(Event::default().event("error").data(e.to_string()))
                }
            }
        });

        Sse::new(sse_stream).keep_alive(KeepAlive::default())
    }


    pub async fn agent_enhanced_chat_stream(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(payload): Json<crate::agent::ChatRequest>,
    ) -> impl IntoResponse {
        let ai_config = state.read().await.ai_config.clone();
        let stream = crate::agent::enhanced_chat_stream(state, payload, ai_config);
        
        Sse::new(
            stream.map(|res| {
                match res {
                    Ok(event) => Event::default().json_data(event),
                    Err(e) => Event::default().json_data(serde_json::json!({"type": "error", "data": e.to_string()})),
                }
            })
        ).keep_alive(axum::response::sse::KeepAlive::default())
    }
    
    // Production AI Agent Handlers - Like Cursor/Windsurf
    
    
    pub async fn agent_get_pending_changes(Path(session_id): Path<String>) -> impl IntoResponse {
        let changes = crate::agent::get_pending_changes(&session_id);
        Json(json!({ "pending_changes": changes }))
    }
    
    pub async fn agent_apply_change(Path(change_id): Path<String>) -> impl IntoResponse {
        match crate::agent::apply_pending_change(&change_id).await {
            Ok(msg) => Json(json!({ "success": true, "message": msg })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
        }
    }
    
    pub async fn agent_reject_change(Path(change_id): Path<String>) -> impl IntoResponse {
        match crate::agent::reject_pending_change(&change_id) {
            Ok(msg) => Json(json!({ "success": true, "message": msg })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
        }
    }
    pub async fn list_files(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<ListFilesRequest>,
    ) -> Result<Json<ListFilesResponse>> {
        let files = crate::code::file_ops::list_directory(&req.path).await?;
        Ok(Json(ListFilesResponse { files }))
    }

    pub async fn read_file(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<ReadFileRequest>,
    ) -> Result<Json<ReadFileResponse>> {
        let content = crate::code::file_ops::read_file(&req.path).await?;
        Ok(Json(ReadFileResponse { content }))
    }

    pub async fn write_file(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<WriteFileRequest>,
    ) -> Result<Json<StatusResponse>> {
        crate::code::file_ops::write_file(&req.path, &req.content).await?;
        Ok(Json(StatusResponse {
            success: true,
            message: "File written successfully".to_string(),
        }))
    }

    pub async fn delete_file(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<DeleteFileRequest>,
    ) -> Result<Json<StatusResponse>> {
        crate::code::file_ops::delete_file(&req.path).await?;
        Ok(Json(StatusResponse {
            success: true,
            message: "File deleted successfully".to_string(),
        }))
    }

    pub async fn create_directory(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<CreateDirectoryRequest>,
    ) -> Result<Json<CreateDirectoryResponse>> {
        crate::code::file_ops::create_directory(&req.path).await?;
        Ok(Json(CreateDirectoryResponse {
            success: true,
            message: "Directory created successfully".to_string(),
        }))
    }

    // Code operations
    pub async fn analyze_code(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<AnalyzeCodeRequest>,
    ) -> Result<Json<AnalyzeCodeResponse>> {
        let analysis = crate::code::analyzer::analyze(&req.code, &req.language).await?;
        Ok(Json(AnalyzeCodeResponse { analysis }))
    }

    pub async fn format_code(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<FormatCodeRequest>,
    ) -> Result<Json<FormatCodeResponse>> {
        let formatted = crate::code::formatter::format(&req.code, &req.language).await?;
        Ok(Json(FormatCodeResponse { code: formatted }))
    }

    pub async fn highlight_code(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<HighlightCodeRequest>,
    ) -> Result<Json<HighlightCodeResponse>> {
        let highlighted = crate::code::highlighter::highlight(&req.code, &req.language).await?;
        Ok(Json(HighlightCodeResponse { tokens: highlighted }))
    }

    // Database handlers
    #[derive(Deserialize)]
    pub struct DbConnectRequest {
        pub db_type: String,
        pub connection_string: String,
    }

    lazy_static::lazy_static! {
        static ref DB_MANAGER: DatabaseManager = DatabaseManager::new();
    }

    pub async fn db_connect(Json(payload): Json<DbConnectRequest>) -> impl IntoResponse {
        let db_type = match payload.db_type.as_str() {
            "sqlite" => DatabaseType::SQLite,
            "postgres" => DatabaseType::PostgreSQL,
            "mysql" => DatabaseType::MySQL,
            _ => return (axum::http::StatusCode::BAD_REQUEST, "Invalid database type").into_response(),
        };

        match DB_MANAGER.connect(db_type, &payload.connection_string).await {
            Ok(id) => Json(json!({ "connection_id": id })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
        }
    }

    #[derive(Deserialize)]
    pub struct DbQueryRequest {
        pub connection_id: String,
        pub query: String,
    }

    pub async fn db_query(Json(payload): Json<DbQueryRequest>) -> impl IntoResponse {
        match DB_MANAGER.execute_query(&payload.connection_id, &payload.query).await {
            Ok(result) => Json(json!(result)).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
        }
    }

    // Network Proxy
    pub async fn proxy_request(Json(payload): Json<crate::network::ProxyRequest>) -> impl IntoResponse {
        match crate::network::execute_request(payload).await {
            Ok(response) => Json(json!(response)).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
        }
    }
    // AI operations
    pub async fn ai_refactor(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<AIRefactorRequest>,
    ) -> Result<Json<AIRefactorResponse>> {
        let st = state.read().await;
        // Create config prioritizing request overrides
        let mut config = st.ai_config.clone();
        if let Some(p) = &req.provider { config.provider = p.clone(); }
        if let Some(m) = &req.model { config.model = m.clone(); }
        if let Some(k) = &req.api_key { config.api_key = k.clone(); }
        
        let refactored = crate::ai::refactor(&req.code, &req.instructions, &config).await?;
        Ok(Json(AIRefactorResponse { code: refactored }))
    }

    pub async fn ai_transpile(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<AITranspileRequest>,
    ) -> Result<Json<AITranspileResponse>> {
        let st = state.read().await;
        let mut config = st.ai_config.clone();
        if let Some(p) = &req.provider { config.provider = p.clone(); }
        if let Some(m) = &req.model { config.model = m.clone(); }
        if let Some(k) = &req.api_key { config.api_key = k.clone(); }
        
        let transpiled = crate::ai::transpile(&req.code, &req.target_language, &req.instructions, &config).await?;
        Ok(Json(AITranspileResponse { code: transpiled }))
    }

    pub async fn ai_refactor_ultra(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<AIRefactorUltraRequest>,
    ) -> Result<Json<AIRefactorUltraResponse>> {
        let st = state.read().await;
        let mut config = st.ai_config.clone();
        if let Some(p) = &req.provider { config.provider = p.clone(); }
        if let Some(m) = &req.model { config.model = m.clone(); }
        if let Some(k) = &req.api_key { config.api_key = k.clone(); }
        
        let response = crate::ai_ultra::refactor_folder(req, &config).await?;
        Ok(Json(response))
    }

    pub async fn ai_refactor_stream(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<AIRefactorRequest>,
    ) -> impl IntoResponse {
        let st = state.read().await;
        let mut config = st.ai_config.clone();
        if let Some(p) = &req.provider { config.provider = p.clone(); }
        if let Some(m) = &req.model { config.model = m.clone(); }
        if let Some(k) = &req.api_key { config.api_key = k.clone(); }
        
        match crate::ai::refactor_stream(&req.code, &req.instructions, &config).await {
            Ok(stream) => {
                let stream = stream.map(|result| -> std::result::Result<Event, Infallible> {
                    match result {
                        Ok(text) => Ok(Event::default().data(text)),
                        Err(e) => Ok(Event::default().event("error").data(e.to_string())),
                    }
                });
                Sse::new(stream).keep_alive(KeepAlive::default()).into_response()
            }
            Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
        }
    }

    pub async fn ai_refactor_report(
        Json(req): Json<AIRefactorReportRequest>,
    ) -> impl IntoResponse {
        match crate::ai_report::generate_pdf_report(req).await {
            Ok(pdf_bytes) => {
                axum::response::Response::builder()
                    .header("Content-Type", "application/pdf")
                    .header("Content-Disposition", "attachment; filename=\"refactor_report.pdf\"")
                    .body(axum::body::Body::from(pdf_bytes))
                    .unwrap()
            }
            Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
        }
    }

    pub async fn ai_explain(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<AIExplainRequest>,
    ) -> Result<Json<AIExplainResponse>> {
        let st = state.read().await;
        // Create config prioritizing request overrides
        let mut config = st.ai_config.clone();
        if let Some(p) = &req.provider { config.provider = p.clone(); }
        if let Some(m) = &req.model { config.model = m.clone(); }
        if let Some(k) = &req.api_key { config.api_key = k.clone(); }
        
        let explanation = crate::ai::explain(&req.code, &config).await?;
        Ok(Json(AIExplainResponse { explanation }))
    }

    pub async fn ai_complete(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<AICompleteRequest>,
    ) -> Result<Json<AICompleteResponse>> {
        let st = state.read().await;
        // Create config prioritizing request overrides
        let mut config = st.ai_config.clone();
        if let Some(p) = &req.provider { config.provider = p.clone(); }
        if let Some(m) = &req.model { config.model = m.clone(); }
        if let Some(k) = &req.api_key { config.api_key = k.clone(); }

        let completion = crate::ai::complete(&req.code, &req.context, &config).await?;
        Ok(Json(AICompleteResponse { completion }))
    }

    pub async fn list_ai_models(
        State(state): State<Arc<RwLock<AppState>>>,
    ) -> Result<Json<AIModelsResponse>> {
        let models = crate::ai::list_models().await?;
        Ok(Json(AIModelsResponse { models }))
    }

    // Git operations
    pub async fn git_status(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<GitStatusRequest>,
    ) -> Result<Json<GitStatusResponse>> {
        let status = crate::git::status(&req.repo_path).await?;
        Ok(Json(GitStatusResponse { status }))
    }

    pub async fn git_commit(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<GitCommitRequest>,
    ) -> Result<Json<StatusResponse>> {
        crate::git::commit(&req.repo_path, &req.message).await?;
        Ok(Json(StatusResponse {
            success: true,
            message: "Committed successfully".to_string(),
        }))
    }

    pub async fn git_push(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<GitPushRequest>,
    ) -> Result<Json<StatusResponse>> {
        crate::git::push(&req.repo_path).await?;
        Ok(Json(StatusResponse {
            success: true,
            message: "Pushed successfully".to_string(),
        }))
    }

    pub async fn git_pull(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<GitPullRequest>,
    ) -> Result<Json<StatusResponse>> {
        crate::git::pull(&req.repo_path).await?;
        Ok(Json(StatusResponse {
            success: true,
            message: "Pulled successfully".to_string(),
        }))
    }

    pub async fn git_log(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<GitLogRequest>,
    ) -> Result<Json<GitLogResponse>> {
        let log = crate::git::log(&req.repo_path, req.limit).await?;
        Ok(Json(GitLogResponse { commits: log }))
    }

    pub async fn git_diff(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<GitDiffRequest>,
    ) -> Result<Json<GitDiffResponse>> {
        let diff = crate::git::diff(&req.repo_path).await?;
        Ok(Json(GitDiffResponse { diff }))
    }

    // Code execution
    pub async fn execute_code(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<ExecuteCodeRequest>,
    ) -> Result<Json<ExecuteCodeResponse>> {
        // Check for specific Node version override
        let node_path = if matches!(req.language.to_lowercase().as_str(), "javascript" | "js" | "typescript" | "ts") {
            let st = state.read().await;
            {
                let settings = st.node_settings.read().await;
                if let Some(version) = &settings.selected_version {
                     crate::nodejs::NodeManager::resolve_path(version).await
                } else {
                    None
                }
            }
        } else {
            None
        };

        let output = crate::runner::execute(&req.code, &req.language, node_path).await?;
        Ok(Json(ExecuteCodeResponse { output }))
    }

    // Stream Code execution
    pub async fn execute_code_stream(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<ExecuteCodeRequest>,
    ) -> impl IntoResponse {
        // Check for specific Node version override
        let node_path = if matches!(req.language.to_lowercase().as_str(), "javascript" | "js" | "typescript" | "ts") {
            let st = state.read().await;
            {
                let settings = st.node_settings.read().await;
                if let Some(version) = &settings.selected_version {
                     crate::nodejs::NodeManager::resolve_path(version).await
                } else {
                    None
                }
            }
        } else {
            None
        };

        match crate::runner::execute_stream(&req.code, &req.language, node_path).await {
            Ok(stream) => {
                let stream = stream.map(|result: std::result::Result<crate::runner::StreamEvent, crate::error::AppError>| -> std::result::Result<Event, Infallible> {
                     match result {
                         Ok(event) => {
                             Ok(Event::default().json_data(event).unwrap())
                         }
                         Err(e) => {
                             Ok(Event::default().event("error").data(e.to_string()))
                         }
                     }
                });
                
                Sse::new(stream)
                    .keep_alive(KeepAlive::default())
                    .into_response()
            }
            Err(e) => {
                (axum::http::StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to start execution: {}", e)).into_response()
            }
        }
    }

    pub async fn stop_execution(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<StopExecutionRequest>,
    ) -> Result<Json<StatusResponse>> {
        crate::runner::stop(&req.execution_id).await?;
        Ok(Json(StatusResponse {
            success: true,
            message: "Execution stopped".to_string(),
        }))
    }
    
    // Scenario Automation handlers
    
    #[derive(Debug, Deserialize)]
    pub struct ScenarioExecuteRequest {
        pub id: String,
        pub name: String,
        pub nodes: Vec<crate::scenario::ScenarioNode>,
        pub connections: Vec<crate::scenario::ScenarioConnection>,
    }
    
    #[derive(Debug, Deserialize)]
    pub struct NodeExecuteRequest {
        pub node: crate::scenario::ScenarioNode,
        pub input: serde_json::Value,
    }
    
    pub async fn scenario_execute(
        Json(req): Json<ScenarioExecuteRequest>,
    ) -> impl IntoResponse {
        let scenario = crate::scenario::Scenario {
            id: req.id,
            name: req.name,
            nodes: req.nodes,
            connections: req.connections,
            is_active: true,
        };
        
        let mut executor = crate::scenario::ScenarioExecutor::new();
        
        match executor.execute(&scenario).await {
            Ok(result) => {
                (StatusCode::OK, Json(serde_json::json!({
                    "success": result.success,
                    "scenario_id": result.scenario_id,
                    "scenario_name": result.scenario_name,
                    "node_results": result.node_results,
                    "total_time_ms": result.total_time_ms,
                    "logs": result.logs
                })))
            }
            Err(e) => {
                (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({
                    "success": false,
                    "error": e.to_string()
                })))
            }
        }
    }
    
    pub async fn scenario_execute_node(
        Json(req): Json<NodeExecuteRequest>,
    ) -> impl IntoResponse {
        let mut executor = crate::scenario::ScenarioExecutor::new();
        
        match executor.execute_single_node(&req.node, req.input).await {
            Ok(result) => {
                (StatusCode::OK, Json(serde_json::json!({
                    "success": result.success,
                    "output": result.output,
                    "error": result.error,
                    "execution_time_ms": result.execution_time_ms,
                    "logs": executor.get_logs()
                })))
            }
            Err(e) => {
                (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({
                    "success": false,
                    "error": e.to_string(),
                    "logs": executor.get_logs()
                })))
            }
        }
    }
    
    // Live Preview (Hot Reload) handlers
    
    #[derive(Debug, Deserialize)]
    pub struct PreviewReloadRequest {
        pub source_code: String,
        pub language: String,
        pub file_path: Option<String>,
    }
    
    pub async fn preview_reload(
        Json(req): Json<PreviewReloadRequest>,
    ) -> impl IntoResponse {
        use crate::live_preview::PreviewHost;
        
        let mut host = PreviewHost::new();
        let result = host.hot_reload(&req.source_code, &req.language);
        
        Json(serde_json::json!({
            "success": result.success,
            "output": result.output,
            "error": result.error,
            "compile_time_ms": result.compile_time_ms,
            "render_time_ms": result.render_time_ms
        }))
    }
    
    pub async fn preview_status() -> impl IntoResponse {
        let socket_path = crate::live_preview::ipc::get_socket_path();
        let server_running = socket_path.exists();
        
        Json(serde_json::json!({
            "server_running": server_running,
            "socket_path": socket_path.to_string_lossy()
        }))
    }
    
    /// Start the preview agent process
    pub async fn preview_start_agent() -> impl IntoResponse {
        use std::process::Command;
        
        // Check if already running
        let socket_path = "/tmp/codetunner_preview.sock";
        if std::path::Path::new(socket_path).exists() {
            return Json(serde_json::json!({
                "success": true,
                "message": "Agent already running"
            }));
        }
        
        // Spawn preview-agent process
        let result = Command::new("preview-agent")
            .env("PREVIEW_SOCKET", socket_path)
            .spawn();
        
        match result {
            Ok(child) => {
                // Give it a moment to start
                tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
                
                Json(serde_json::json!({
                    "success": true,
                    "pid": child.id(),
                    "socket_path": socket_path
                }))
            }
            Err(e) => Json(serde_json::json!({
                "success": false,
                "error": e.to_string()
            }))
        }
    }
    
    /// Stop the preview agent process
    pub async fn preview_stop_agent() -> impl IntoResponse {
        use std::os::unix::net::UnixStream;
        use std::io::Write;
        
        let socket_path = "/tmp/codetunner_preview.sock";
        
        // Send shutdown message
        if let Ok(mut stream) = UnixStream::connect(socket_path) {
            let msg = r#"{"type":"Shutdown"}"#;
            let len = msg.len() as u32;
            let _ = stream.write_all(&len.to_le_bytes());
            let _ = stream.write_all(msg.as_bytes());
        }
        
        // Remove socket file
        let _ = std::fs::remove_file(socket_path);
        
        Json(serde_json::json!({
            "success": true,
            "message": "Agent stopped"
        }))
    }
    
    // ========================================
    // Hot Reload Engine Handlers
    // ========================================
    
    /// List all registered thunks
    pub async fn hotreload_list_thunks() -> impl IntoResponse {
        use crate::hot_reload::thunk::THUNK_TABLE;
        
        let functions: Vec<String> = if let Ok(table) = THUNK_TABLE.read() {
            (*table).list_functions()
        } else {
            Vec::new()
        };
        
        Json(serde_json::json!({
            "thunks": functions,
            "count": functions.len()
        }))
    }
    
    /// Register a thunk (for testing/debugging)
    #[derive(Debug, Deserialize)]
    pub struct RegisterThunkRequest {
        pub name: String,
        pub address: u64,
    }
    
    pub async fn hotreload_register_thunk(
        Json(req): Json<RegisterThunkRequest>,
    ) -> impl IntoResponse {
        use crate::hot_reload::thunk::THUNK_TABLE;
        
        if let Ok(mut table) = THUNK_TABLE.write() {
            (*table).register(&req.name, req.address as *const std::ffi::c_void);
            Json(serde_json::json!({
                "success": true,
                "name": req.name
            }))
        } else {
            Json(serde_json::json!({
                "success": false,
                "error": "Failed to acquire lock"
            }))
        }
    }
    
    /// Get state snapshot as JSON
    pub async fn hotreload_state_snapshot() -> impl IntoResponse {
        use crate::hot_reload::state::STATE_REGISTRY;
        
        let snapshot: std::collections::HashMap<String, String> = if let Ok(registry) = STATE_REGISTRY.read() {
            (*registry)
                .iter()
                .filter_map(|(k, v)| {
                    String::from_utf8(v.data.clone())
                        .ok()
                        .map(|s| (k.clone(), s))
                })
                .collect()
        } else {
            std::collections::HashMap::new()
        };
        
        Json(serde_json::json!({
            "snapshot": snapshot,
            "count": snapshot.len()
        }))
    }
    
    /// Clear all state
    pub async fn hotreload_state_clear() -> impl IntoResponse {
        use crate::hot_reload::state::STATE_REGISTRY;
        
        if let Ok(mut registry) = STATE_REGISTRY.write() {
            (*registry).clear();
            Json(serde_json::json!({
                "success": true,
                "message": "State cleared"
            }))
        } else {
            Json(serde_json::json!({
                "success": false,
                "error": "Failed to acquire lock"
            }))
        }
    }
    
    /// Trigger rollback (placeholder - needs agent communication)
    pub async fn hotreload_rollback() -> impl IntoResponse {
        // In a full implementation, this would send a rollback message to the agent
        Json(serde_json::json!({
            "success": true,
            "message": "Rollback requested (agent will handle)"
        }))
    }
    
    /// Get hot reload engine version info
    pub async fn hotreload_version() -> impl IntoResponse {
        Json(serde_json::json!({
            "engine": "CodeTunner Hot Reload",
            "version": "1.0.0",
            "features": [
                "thunk_table",
                "dynamic_replacement",
                "state_preservation",
                "ipc_unix_socket",
                "arm64_trampoline",
                "x86_64_trampoline"
            ],
            "architecture": std::env::consts::ARCH
        }))
    }
    
    // CI/CD Handlers
    
    pub async fn cicd_list_runs(
        Json(payload): Json<crate::cicd::CICDBaseRequest>,
    ) -> impl IntoResponse {
        let client = crate::cicd::GitHubClient::new();
        match client.list_runs(&payload.owner, &payload.repo, &payload.token, 20).await {
            Ok(runs) => Json(json!(runs)).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
        }
    }
    
    #[derive(Debug, Deserialize)]
    pub struct RunJobsRequest {
        pub owner: String,
        pub repo: String,
        pub token: String,
        pub run_id: u64,
    }

    pub async fn cicd_run_jobs(
        Json(payload): Json<RunJobsRequest>,
    ) -> impl IntoResponse {
        let client = crate::cicd::GitHubClient::new();
        match client.list_jobs(&payload.owner, &payload.repo, &payload.token, payload.run_id).await {
            Ok(jobs) => Json(json!(jobs)).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
        }
    }

    pub async fn cicd_trigger(
        Json(payload): Json<crate::cicd::TriggerWorkflowRequest>,
    ) -> impl IntoResponse {
        let client = crate::cicd::GitHubClient::new();
        match client.trigger_workflow(&payload).await {
            Ok(_) => Json(json!({ "success": true, "message": "Workflow triggered" })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
        }
    }

    pub async fn cicd_get_logs(
        Json(payload): Json<crate::cicd::GetLogsRequest>,
    ) -> impl IntoResponse {
        let client = crate::cicd::GitHubClient::new();
        match client.get_job_logs(&payload.owner, &payload.repo, &payload.token, payload.job_id).await {
            Ok(logs) => Json(json!({ "logs": logs })).into_response(),
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
        }
    }

    // DataFrame Handlers
    pub async fn load_dataframe(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<DataFrameLoadRequest>,
    ) -> Result<Json<DataFrameLoadResponse>> {
        let st = state.read().await;
        let id = st.data_frames.load_file(&req.path)?;
        Ok(Json(DataFrameLoadResponse { id }))
    }

    pub async fn get_dataframe_slice(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<DataFrameSliceRequest>,
    ) -> Result<Json<DataFrameSliceResponse>> {
        let st = state.read().await;
        let data = st.data_frames.get_slice(&req.id, req.offset, req.limit)?;
        Ok(Json(DataFrameSliceResponse { data }))
    }

    pub async fn get_dataframe_schema(
        State(state): State<Arc<RwLock<AppState>>>,
        Json(req): Json<DataFrameSchemaRequest>,
    ) -> Result<Json<DataFrameSchemaResponse>> {
        let st = state.read().await;
        let schema = st.data_frames.get_schema(&req.id)?;
        Ok(Json(DataFrameSchemaResponse { schema }))
    }

    // Data Sharing Handlers (Polyglot Shared Memory)
    pub async fn data_list(
        State(state): State<Arc<RwLock<AppState>>>,
    ) -> impl IntoResponse {
        let st = state.read().await;
        let names = st.data_frames.list_named();
        Json(json!({ "names": names }))
    }

    pub async fn data_get(
        State(state): State<Arc<RwLock<AppState>>>,
        Path(name): Path<String>,
    ) -> impl IntoResponse {
        let st = state.read().await;
        match st.data_frames.get_named(&name) {
            Some(mut df) => {
                let mut buf = Vec::new();
                use polars::prelude::SerReader; // Added SerReader here
                match polars::prelude::ParquetWriter::new(&mut buf).finish(&mut df) {
                    Ok(_) => (axum::http::StatusCode::OK, buf).into_response(),
                    Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
                }
            }
            None => (axum::http::StatusCode::NOT_FOUND, "DataFrame not found").into_response(),
        }
    }

    pub async fn data_store(
        State(state): State<Arc<RwLock<AppState>>>,
        Path(name): Path<String>,
        body: axum::body::Bytes,
    ) -> impl IntoResponse {
        let st = state.read().await;
        let cursor = std::io::Cursor::new(body);
        use polars::prelude::SerReader;
        match polars::prelude::ParquetReader::new(cursor).finish() {
            Ok(df) => {
                st.data_frames.store_named(name, df);
                Json(json!({ "success": true })).into_response()
            }
            Err(e) => (axum::http::StatusCode::BAD_REQUEST, e.to_string()).into_response(),
        }
    }

    // IPC / Shared Memory Handlers (Apple Silicon Optimized)
    // Avoids HTTP body copy by using memory mapped files
    
    pub async fn data_get_shm(
        State(state): State<Arc<RwLock<AppState>>>,
        Path(name): Path<String>,
    ) -> impl IntoResponse {
        // Return the path to the SHM file so client can mmap it
        let st = state.read().await;
        // Ensure data exists in memory
        if st.data_frames.get_named(&name).is_some() {
             // In a real implementation we would ensure it's synced to disk/shm
             // For now, simply return the expected SHM path convention
             let path = format!("/tmp/{}.shm", name);
             Json(json!({ "path": path, "success": true })).into_response()
        } else {
             (axum::http::StatusCode::NOT_FOUND, "DataFrame not found").into_response()
        }
    }

    pub async fn data_store_shm(
        State(state): State<Arc<RwLock<AppState>>>,
        Path(name): Path<String>,
    ) -> impl IntoResponse {
        let st = state.read().await;
        // Client signaled they wrote to /tmp/{name}.shm
        let path_str = format!("/tmp/{}.shm", name);
        let path = std::path::Path::new(&path_str);
        
        if !path.exists() {
             return (axum::http::StatusCode::BAD_REQUEST, "SHM file not found").into_response();
        }
        
        // Use Polars to read directly from the file (mmap automatically used by ParquetReader if possible)
        match std::fs::File::open(path) {
            Ok(file) => {
                use polars::prelude::SerReader;
                match polars::prelude::ParquetReader::new(file).finish() {
                    Ok(df) => {
                        st.data_frames.store_named(name, df);
                        Json(json!({ "success": true, "mode": "shm" })).into_response()
                    },
                    Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response()
                }
            },
            Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response()
        }
    }

    // Terminal WebSocket
    pub async fn terminal_ws(
        ws: axum::extract::ws::WebSocketUpgrade,
        State(state): State<Arc<RwLock<AppState>>>,
    ) -> impl IntoResponse {
        ws.on_upgrade(|socket| handle_terminal_socket(socket, state))
    }

    async fn handle_terminal_socket(mut socket: axum::extract::ws::WebSocket, state: Arc<RwLock<AppState>>) {
        use axum::extract::ws::Message;
        
        // 1. Create a new PTY session
        let session_id = {
            let st = state.read().await;
            match st.terminal_manager.create_session(80, 24) {
                Ok(id) => id,
                Err(e) => {
                    let _ = socket.send(Message::Text(format!("Error: {}", e))).await;
                    return;
                }
            }
        };

        // 2. Subscribe to PTY output
        let mut rx = {
            let st = state.read().await;
            st.terminal_manager.subscribe(&session_id).unwrap()
        };

        // 3. Spawn output forwarder
        let (mut sender, mut receiver) = socket.split();
        let mut send_task = tokio::spawn(async move {
            while let Ok(data) = rx.recv().await {
                // Send as binary
                if let Err(_) = sender.send(Message::Binary(data)).await {
                    break;
                }
            }
        });

        // 4. Handle input from client
        let recv_state = state.clone();
        let recv_session_id = session_id.clone();
        
        let mut recv_task = tokio::spawn(async move {
            while let Some(Ok(msg)) = receiver.next().await {
                let st = recv_state.read().await;
                match msg {
                    Message::Text(text) => {
                        // Protocol: "R:cols,rows" for resize, otherwise input
                        if text.starts_with("R:") {
                            let parts: Vec<&str> = text[2..].split(',').collect();
                            if parts.len() == 2 {
                                if let (Ok(cols), Ok(rows)) = (parts[0].parse::<u16>(), parts[1].parse::<u16>()) {
                                    let _ = st.terminal_manager.resize(&recv_session_id, cols, rows);
                                }
                            }
                        } else {
                            let _ = st.terminal_manager.write(&recv_session_id, text.as_bytes());
                        }
                    },
                    Message::Binary(data) => {
                         let _ = st.terminal_manager.write(&recv_session_id, &data);
                    },
                    _ => {}
                }
            }
        });

        // Wait for either to finish
        tokio::select! {
            _ = (&mut send_task) => recv_task.abort(),
            _ = (&mut recv_task) => send_task.abort(),
        };
    }
}
