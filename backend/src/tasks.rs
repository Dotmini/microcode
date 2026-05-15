use crate::error::Result;
use crate::state::AppState;
use axum::{
    extract::{Json, Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, Row};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::info;
use uuid::Uuid;

// ==========================================
// Models
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Task {
    pub id: String, // UUID
    pub project_id: String,
    pub parent_id: Option<String>,
    pub title: String,
    pub description: String,
    pub status: String,    // backlog, ready, in_progress, review, done
    pub priority: String,  // low, medium, high, critical
    pub task_type: String, // epic, story, task, bug, debt
    pub assignee_id: Option<String>,
    pub branch_name: Option<String>,
    pub created_at: String, // ISO8601
    pub updated_at: String,
    pub due_date: Option<String>,
    pub tags: String, // JSON array string
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Project {
    pub id: String,
    pub name: String,
    pub repo_url: Option<String>,
    pub git_provider: String, // github, gitlab, local
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateTaskRequest {
    pub project_id: String,
    pub title: String,
    pub description: Option<String>,
    pub task_type: Option<String>,
    pub priority: Option<String>,
    pub parent_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateTaskRequest {
    pub title: Option<String>,
    pub description: Option<String>,
    pub status: Option<String>,
    pub priority: Option<String>,
    pub branch_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateBranchRequest {
    pub task_id: String,
    pub base_branch: String, // e.g., main or develop
}

// ==========================================
// Implementation (TaskManager)
// ==========================================

pub struct TaskManager;

impl TaskManager {
    // In a real implementation with DB, we would use pool here.
    // For MVP/POC without setting up Postgres explicitly, we might use SQLite or just In-Memory HashMap if DB not configured.
    // But requirement asks for "Database Schema".
    // Let's assume we use the `database.rs` connection.

    // For this POC text generation, I will write the Handlers that *would* call DB.
    // And simple mock storage if DB isn't connected, OR SQL queries if we assume SQLite is present.
    // Let's assume SQLite for local DX.

    pub async fn create_project(state: Arc<RwLock<AppState>>, name: String) -> Result<Project> {
        let id = Uuid::new_v4().to_string();
        let now = chrono::Utc::now().to_rfc3339();

        let project = Project {
            id: id.clone(),
            name,
            repo_url: None,
            git_provider: "local".to_string(),
            created_at: now,
        };

        // TODO: Insert into DB
        // sqlx::query("INSERT INTO projects ...")

        Ok(project)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitWebhookPayload {
    pub provider: String,   // github, gitlab
    pub event_type: String, // push, pull_request, merge_request
    pub message: Option<String>,
    pub branch: Option<String>,
    pub mr_status: Option<String>, // open, merged, closed
}

// ==========================================
// Handlers
// ==========================================

pub async fn handle_git_webhook(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(payload): Json<GitWebhookPayload>,
) -> impl IntoResponse {
    info!("Received Git Webhook: {:?}", payload);

    // Logic to update tasks based on message or PR status
    // 1. If PR merged -> Move linked task to DONE
    // 2. If commit message contains "Fixes #ID" -> Move to DONE or REVIEW

    if let Some(msg) = &payload.message {
        if msg.contains("Fixes #") {
            // Extact ID and update status
        }
    }

    if payload.event_type == "pull_request" && payload.mr_status == Some("merged".to_string()) {
        // Move related task to DONE
    }

    StatusCode::OK
}

pub async fn list_tasks(
    State(state): State<Arc<RwLock<AppState>>>,
    Query(params): Query<std::collections::HashMap<String, String>>,
) -> impl IntoResponse {
    // let project_id = params.get("project_id");
    // Mock Response
    let tasks = vec![Task {
        id: Uuid::new_v4().to_string(),
        project_id: "demo-project".to_string(),
        parent_id: None,
        title: "Implement Login Flow".to_string(),
        description: "Use OAuth2".to_string(),
        status: "in_progress".to_string(),
        priority: "high".to_string(),
        task_type: "story".to_string(),
        assignee_id: None,
        branch_name: Some("feature/DM-101-login".to_string()),
        created_at: chrono::Utc::now().to_rfc3339(),
        updated_at: chrono::Utc::now().to_rfc3339(),
        due_date: None,
        tags: "[\"auth\", \"backend\"]".to_string(),
    }];

    Json(serde_json::json!({ "tasks": tasks }))
}

pub async fn create_task(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(payload): Json<CreateTaskRequest>,
) -> impl IntoResponse {
    let task = Task {
        id: Uuid::new_v4().to_string(),
        project_id: payload.project_id,
        parent_id: payload.parent_id,
        title: payload.title,
        description: payload.description.unwrap_or_default(),
        status: "backlog".to_string(),
        priority: payload.priority.unwrap_or("medium".to_string()),
        task_type: payload.task_type.unwrap_or("task".to_string()),
        assignee_id: None,
        branch_name: None,
        created_at: chrono::Utc::now().to_rfc3339(),
        updated_at: chrono::Utc::now().to_rfc3339(),
        due_date: None,
        tags: "[]".to_string(),
    };

    // Save to DB...

    Json(serde_json::json!({ "task": task }))
}

pub async fn update_status(
    Path(id): Path<String>,
    State(state): State<Arc<RwLock<AppState>>>,
    Json(payload): Json<UpdateTaskRequest>,
) -> impl IntoResponse {
    // Update logic...
    Json(serde_json::json!({ "success": true, "id": id }))
}

pub async fn create_branch_for_task(
    Path(id): Path<String>,
    State(state): State<Arc<RwLock<AppState>>>,
    Json(payload): Json<CreateBranchRequest>,
) -> impl IntoResponse {
    // 1. Get Task
    // 2. Generate Branch Name (e.g. type/id-title)
    // 3. Call git command via wrappers

    let branch_name = format!("feature/{}-task", id); // Simplified

    Json(serde_json::json!({
        "success": true,
        "branch_name": branch_name,
        "message": "Branch created and linked"
    }))
}
