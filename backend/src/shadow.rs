use crate::error::{AppError, Result};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use tokio::fs;
use tokio::process::Command;
use tokio::time::{timeout, Duration};

/// Strategy used to create the shadow workspace.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum ShadowStrategy {
    GitWorktree,
    TempCopy,
}

/// Represents a change to a single file.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileChange {
    /// Path relative to the workspace root, or absolute path within the workspace.
    pub path: PathBuf,
    /// The new content of the file.
    pub content: String,
}

/// Severity of a diagnostic message.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DiagnosticSeverity {
    Error,
    Warning,
    Info,
}

/// A diagnostic message from the verification process.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Diagnostic {
    pub file: String,
    pub line: Option<usize>,
    pub severity: DiagnosticSeverity,
    pub message: String,
}

/// The result of running verification on the shadow workspace.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationResult {
    pub passed: bool,
    pub diagnostics: Vec<Diagnostic>,
    pub stdout: String,
    pub stderr: String,
    pub exit_code: i32,
}

/// A shadow workspace for speculative verification of changes.
pub struct ShadowWorkspace {
    pub original_root: PathBuf,
    pub shadow_root: PathBuf,
    pub strategy: ShadowStrategy,
}

impl ShadowWorkspace {
    /// Creates a new shadow workspace.
    /// Tries to use `git worktree` first, and falls back to a temporary copy if git fails.
    pub async fn create(workspace: &Path) -> Result<Self> {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let temp_dir = std::env::temp_dir().join(format!("shadow_{}_{}", std::process::id(), timestamp));
        
        fs::create_dir_all(&temp_dir)
            .await
            .map_err(|e| AppError::InternalError(format!("Failed to create temp dir: {}", e)))?;

        // 1. Try Git worktree
        let git_output = Command::new("git")
            .current_dir(workspace)
            .args(["worktree", "add", temp_dir.to_str().unwrap(), "--detach"])
            .output()
            .await;

        if let Ok(out) = git_output {
            if out.status.success() {
                return Ok(Self {
                    original_root: workspace.to_path_buf(),
                    shadow_root: temp_dir,
                    strategy: ShadowStrategy::GitWorktree,
                });
            }
        }

        // 2. Fallback to TempCopy (using rsync to copy relevant files efficiently)
        // Ensure destination string ends with / for rsync behavior
        let dest_str = format!("{}/", temp_dir.display());
        let src_str = format!("{}/", workspace.display());
        
        let rsync_output = Command::new("rsync")
            .arg("-a")
            .arg("--exclude=.git")
            .arg("--exclude=node_modules")
            .arg("--exclude=target")
            .arg("--exclude=.build")
            .arg(&src_str)
            .arg(&dest_str)
            .output()
            .await;

        if let Ok(out) = rsync_output {
            if out.status.success() {
                return Ok(Self {
                    original_root: workspace.to_path_buf(),
                    shadow_root: temp_dir,
                    strategy: ShadowStrategy::TempCopy,
                });
            }
        }

        // 3. Fallback to `cp` if rsync fails
        let cp_output = Command::new("cp")
            .arg("-R")
            .arg(format!("{}/.", workspace.display()))
            .arg(&temp_dir)
            .output()
            .await
            .map_err(|e| AppError::InternalError(format!("Failed to execute cp: {}", e)))?;
            
        if !cp_output.status.success() {
            return Err(AppError::InternalError("Failed to copy workspace for shadow environment".into()));
        }

        Ok(Self {
            original_root: workspace.to_path_buf(),
            shadow_root: temp_dir,
            strategy: ShadowStrategy::TempCopy,
        })
    }

    /// Writes a set of file changes to the shadow workspace.
    pub async fn apply_changes(&self, changes: &[FileChange]) -> Result<()> {
        for change in changes {
            // Compute the destination path inside the shadow workspace
            let dest_path = if change.path.is_absolute() {
                if let Ok(rel_path) = change.path.strip_prefix(&self.original_root) {
                    self.shadow_root.join(rel_path)
                } else {
                    // fallback if absolute path isn't within original_root
                    self.shadow_root.join(change.path.file_name().unwrap_or_default())
                }
            } else {
                self.shadow_root.join(&change.path)
            };

            if let Some(parent) = dest_path.parent() {
                fs::create_dir_all(parent)
                    .await
                    .map_err(|e| AppError::InternalError(format!("Failed to create parent dir: {}", e)))?;
            }

            fs::write(&dest_path, &change.content)
                .await
                .map_err(|e| AppError::InternalError(format!("Failed to write file {}: {}", dest_path.display(), e)))?;
        }
        Ok(())
    }

    /// Runs the verification command (e.g. `cargo check`) in the shadow root.
    /// Captures output and applies a 60-second timeout.
    pub async fn verify(&self, command: &str) -> Result<VerificationResult> {
        let parts: Vec<&str> = command.split_whitespace().collect();
        if parts.is_empty() {
            return Err(AppError::InternalError("Empty verification command".into()));
        }

        let mut child = Command::new(parts[0]);
        child.args(&parts[1..]);
        child.current_dir(&self.shadow_root);

        let timeout_duration = Duration::from_secs(60);
        let output_future = child.output();

        let output = match timeout(timeout_duration, output_future).await {
            Ok(Ok(out)) => out,
            Ok(Err(e)) => return Err(AppError::InternalError(format!("Failed to execute command: {}", e))),
            Err(_) => return Err(AppError::InternalError("Verification command timed out after 60s".into())),
        };

        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        let exit_code = output.status.code().unwrap_or(-1);

        // TODO: parse stdout/stderr into `diagnostics` based on tool output formats
        let diagnostics = Vec::new();

        Ok(VerificationResult {
            passed: output.status.success(),
            diagnostics,
            stdout,
            stderr,
            exit_code,
        })
    }

    /// Performs a quick syntax validation using tree-sitter without full compilation.
    /// Returns Ok with passed=true as a stub implementation.
    pub async fn verify_with_treesitter(&self, _files: &[PathBuf]) -> Result<VerificationResult> {
        // Stub implementation
        Ok(VerificationResult {
            passed: true,
            diagnostics: Vec::new(),
            stdout: String::new(),
            stderr: String::new(),
            exit_code: 0,
        })
    }

    /// Cleans up the shadow workspace resources.
    pub async fn destroy(self) -> Result<()> {
        match self.strategy {
            ShadowStrategy::GitWorktree => {
                let output = Command::new("git")
                    .current_dir(&self.original_root)
                    .args(["worktree", "remove", "--force", self.shadow_root.to_str().unwrap()])
                    .output()
                    .await;
                
                // If git worktree remove fails, forcefully delete the directory anyway
                let should_cleanup = match output {
                    Ok(out) if out.status.success() => false,
                    _ => true,
                };
                if should_cleanup {
                    let _ = fs::remove_dir_all(&self.shadow_root).await;
                }
            }
            ShadowStrategy::TempCopy => {
                // Ignore errors during temp dir removal
                let _ = fs::remove_dir_all(&self.shadow_root).await;
            }
        }
        Ok(())
    }
}

/// Auto-detects the appropriate build check command for the given workspace.
pub fn detect_verify_command(workspace: &Path) -> Option<String> {
    if workspace.join("Cargo.toml").exists() {
        return Some("cargo check".to_string());
    }
    if workspace.join("Package.swift").exists() {
        return Some("swift build --skip-tests".to_string());
    }
    if workspace.join("tsconfig.json").exists() {
        return Some("npx tsc --noEmit".to_string());
    }
    if workspace.join("package.json").exists() {
        return Some("npm run build".to_string());
    }
    if workspace.join("Makefile").exists() {
        return Some("make -n".to_string());
    }
    None
}
