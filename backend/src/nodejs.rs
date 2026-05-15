use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use tokio::fs;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeVersion {
    pub version: String,
    pub path: String,
    pub source: String, // "system", "nvm", "nvm-windows", etc.
    pub is_current: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct NodeSettings {
    pub selected_version: Option<String>,
}

pub struct NodeManager;

impl NodeManager {
    /// List all available Node.js versions from NVM and system
    pub async fn list_versions() -> Vec<NodeVersion> {
        let mut versions = Vec::new();

        // 1. Check System Node
        if let Ok(path) = which::which("node") {
            if let Ok(output) = std::process::Command::new(&path).arg("--version").output() {
                let version = String::from_utf8_lossy(&output.stdout).trim().to_string();
                versions.push(NodeVersion {
                    version: version.clone(),
                    path: path.to_string_lossy().to_string(),
                    source: "system".to_string(),
                    is_current: false, // Will be updated by state
                });
            }
        }

        // 2. Check NVM versions
        if let Some(home) = dirs::home_dir() {
            let nvm_versions_dir = home.join(".nvm/versions/node");
            if nvm_versions_dir.exists() {
                if let Ok(mut entries) = fs::read_dir(nvm_versions_dir).await {
                    while let Ok(Some(entry)) = entries.next_entry().await {
                        let path = entry.path();
                        if path.is_dir() {
                            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                                let bin_path = path.join("bin/node");
                                if bin_path.exists() {
                                    versions.push(NodeVersion {
                                        version: name.to_string(),
                                        path: bin_path.to_string_lossy().to_string(),
                                        source: "nvm".to_string(),
                                        is_current: false,
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }

        // Sort versions (naive string sort for now, semver sort preferred later)
        versions.sort_by(|a, b| b.version.cmp(&a.version));

        versions
    }

    /// Resolve path for a specific version string
    pub async fn resolve_path(version: &str) -> Option<String> {
        // Direct path check
        if Path::new(version).exists() {
            return Some(version.to_string());
        }

        // Check list
        let versions = Self::list_versions().await;
        versions
            .into_iter()
            .find(|v| v.version == version)
            .map(|v| v.path)
    }
}

// API Handlers
use crate::state::AppState;
use axum::{
    extract::{Json, State},
    response::IntoResponse,
};
use std::sync::Arc;
use tokio::sync::RwLock;

#[derive(Serialize)]
pub struct ListVersionsResponse {
    versions: Vec<NodeVersion>,
}

pub async fn list_versions(State(state): State<Arc<RwLock<AppState>>>) -> impl IntoResponse {
    let mut versions = NodeManager::list_versions().await;

    // Mark current
    let st = state.read().await;
    {
        let settings = st.node_settings.read().await;
        if let Some(selected) = &settings.selected_version {
            for v in &mut versions {
                if &v.version == selected {
                    v.is_current = true;
                }
            }
        }
    }

    Json(ListVersionsResponse { versions })
}

#[derive(Deserialize)]
pub struct SelectVersionRequest {
    pub version: String,
}

pub async fn select_version(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<SelectVersionRequest>,
) -> impl IntoResponse {
    let st = state.read().await;
    {
        let mut settings = st.node_settings.write().await;
        settings.selected_version = Some(req.version);
    }
    Json(serde_json::json!({ "success": true }))
}
