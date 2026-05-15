//! Error handling for MicroCode Backend

use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::json;
use std::fmt;

pub type Result<T> = std::result::Result<T, AppError>;

#[derive(Debug)]
pub enum AppError {
    // IO errors
    IoError(std::io::Error),
    IOError(String), // String-based IO error for agent

    // File system errors
    FileNotFound(String),
    FileReadError(String),
    FileWriteError(String),

    // Git errors
    GitError(String),
    GitRepositoryNotFound(String),

    // AI errors
    AIProviderError(String),
    AIModelNotFound(String),
    AIRequestFailed(String),

    // Code execution errors
    ExecutionError(String),
    CompilationError(String),

    // DataFrame errors
    DataFrameError(String),
    SerializationError(String),

    // Syntax highlighting errors
    HighlightError(String),

    // JSON errors
    JsonError(serde_json::Error),

    // HTTP errors
    HttpError(reqwest::Error),

    // General errors
    InternalError(String),
    BadRequest(String),
    NotImplemented(String),

    // Agent-specific errors
    ValidationError(String),
    NotFound(String),
}

impl fmt::Display for AppError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AppError::IoError(e) => write!(f, "IO error: {}", e),
            AppError::IOError(msg) => write!(f, "IO error: {}", msg),
            AppError::FileNotFound(path) => write!(f, "File not found: {}", path),
            AppError::FileReadError(msg) => write!(f, "File read error: {}", msg),
            AppError::FileWriteError(msg) => write!(f, "File write error: {}", msg),
            AppError::GitError(msg) => write!(f, "Git error: {}", msg),
            AppError::GitRepositoryNotFound(path) => {
                write!(f, "Git repository not found: {}", path)
            }
            AppError::AIProviderError(msg) => write!(f, "AI provider error: {}", msg),
            AppError::AIModelNotFound(model) => write!(f, "AI model not found: {}", model),
            AppError::AIRequestFailed(msg) => write!(f, "AI request failed: {}", msg),
            AppError::ExecutionError(msg) => write!(f, "Execution error: {}", msg),
            AppError::CompilationError(msg) => write!(f, "Compilation error: {}", msg),
            AppError::DataFrameError(msg) => write!(f, "DataFrame error: {}", msg),
            AppError::SerializationError(msg) => write!(f, "Serialization error: {}", msg),
            AppError::HighlightError(msg) => write!(f, "Highlight error: {}", msg),
            AppError::JsonError(e) => write!(f, "JSON error: {}", e),
            AppError::HttpError(e) => write!(f, "HTTP error: {}", e),
            AppError::InternalError(msg) => write!(f, "Internal error: {}", msg),
            AppError::BadRequest(msg) => write!(f, "Bad request: {}", msg),
            AppError::NotImplemented(feature) => write!(f, "Not implemented: {}", feature),
            AppError::ValidationError(msg) => write!(f, "Validation error: {}", msg),
            AppError::NotFound(msg) => write!(f, "Not found: {}", msg),
        }
    }
}

impl std::error::Error for AppError {}

// Convert from std::io::Error
impl From<std::io::Error> for AppError {
    fn from(err: std::io::Error) -> Self {
        AppError::IoError(err)
    }
}

// Convert from serde_json::Error
impl From<serde_json::Error> for AppError {
    fn from(err: serde_json::Error) -> Self {
        AppError::JsonError(err)
    }
}

// Convert from reqwest::Error
impl From<reqwest::Error> for AppError {
    fn from(err: reqwest::Error) -> Self {
        AppError::HttpError(err)
    }
}

// Convert from git2::Error
impl From<git2::Error> for AppError {
    fn from(err: git2::Error) -> Self {
        AppError::GitError(err.to_string())
    }
}

// Convert from candle_core::Error
impl From<candle_core::Error> for AppError {
    fn from(err: candle_core::Error) -> Self {
        AppError::InternalError(format!("Candle error: {}", err))
    }
}

// Implement IntoResponse for Axum
impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, error_message) = match &self {
            AppError::FileNotFound(_) => (StatusCode::NOT_FOUND, self.to_string()),
            AppError::GitRepositoryNotFound(_) => (StatusCode::NOT_FOUND, self.to_string()),
            AppError::AIModelNotFound(_) => (StatusCode::NOT_FOUND, self.to_string()),
            AppError::BadRequest(_) => (StatusCode::BAD_REQUEST, self.to_string()),
            AppError::NotImplemented(_) => (StatusCode::NOT_IMPLEMENTED, self.to_string()),
            _ => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()),
        };

        let body = Json(json!({
            "error": error_message,
            "status": status.as_u16()
        }));

        (status, body).into_response()
    }
}
