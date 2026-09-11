//! Local iOS Simulator control plane.
//!
//! Video frames intentionally never cross this HTTP boundary: Swift renders
//! the SimulatorKit IOSurface in-process. Rust owns bounded, auditable simctl
//! operations for the app, agent, and future admin diagnostics.

use axum::{extract::Json, http::StatusCode, response::IntoResponse};
use serde::{Deserialize, Serialize};
use serde_json::json;
use tokio::process::Command;

#[derive(Debug, Deserialize)]
pub struct SimulatorControlRequest {
    pub device_id: String,
    /// Strict allow-list; arbitrary shell execution is never exposed here.
    pub action: SimulatorAction,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SimulatorAction {
    Boot,
    Shutdown,
    Home,
    Lock,
}

#[derive(Debug, Serialize)]
struct CommandResult {
    success: bool,
    stdout: String,
    stderr: String,
}

/// Read the same device inventory Swift presents in Device & Run. This lets
/// backend diagnostics report a real simulator state instead of stale cache.
pub async fn list_devices() -> impl IntoResponse {
    match simctl(&["list", "devices", "available", "-j"]).await {
        Ok(result) => (
            StatusCode::OK,
            Json(json!({ "success": true, "devices": result.stdout })),
        )
            .into_response(),
        Err(error) => (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({ "success": false, "error": error })),
        )
            .into_response(),
    }
}

pub async fn control(Json(request): Json<SimulatorControlRequest>) -> impl IntoResponse {
    if !is_simulator_udid(&request.device_id) {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "success": false, "error": "Invalid simulator device ID." })),
        )
            .into_response();
    }

    let arguments: Vec<&str> = match request.action {
        SimulatorAction::Boot => vec!["boot", request.device_id.as_str()],
        SimulatorAction::Shutdown => vec!["shutdown", request.device_id.as_str()],
        SimulatorAction::Home => vec!["ui", request.device_id.as_str(), "home"],
        SimulatorAction::Lock => vec!["ui", request.device_id.as_str(), "lock"],
    };
    match simctl(&arguments).await {
        Ok(result) if result.success => (StatusCode::OK, Json(json!(result))).into_response(),
        Ok(result) => (StatusCode::BAD_GATEWAY, Json(json!(result))).into_response(),
        Err(error) => (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({ "success": false, "error": error })),
        )
            .into_response(),
    }
}

async fn simctl(arguments: &[&str]) -> Result<CommandResult, String> {
    let output = Command::new("/usr/bin/xcrun")
        .arg("simctl")
        .args(arguments)
        .output()
        .await
        .map_err(|error| format!("Could not start xcrun simctl: {error}"))?;
    Ok(CommandResult {
        success: output.status.success(),
        stdout: String::from_utf8_lossy(&output.stdout).trim().to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).trim().to_string(),
    })
}

fn is_simulator_udid(value: &str) -> bool {
    // UUID-only prevents option injection and keeps simctl operations scoped
    // to a destination chosen by Device & Run.
    let bytes = value.as_bytes();
    bytes.len() == 36
        && bytes.iter().enumerate().all(|(index, byte)| match index {
            8 | 13 | 18 | 23 => *byte == b'-',
            _ => byte.is_ascii_hexdigit(),
        })
}

#[cfg(test)]
mod tests {
    use super::is_simulator_udid;

    #[test]
    fn accepts_only_uuid_device_ids() {
        assert!(is_simulator_udid("00000000-0000-0000-0000-000000000000"));
        assert!(!is_simulator_udid("booted; rm -rf /"));
        assert!(!is_simulator_udid("--set"));
    }
}
