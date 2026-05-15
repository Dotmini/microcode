//! .NET/dotnet CLI integration module
//!
//! Provides native .NET support for creating, building, and running .NET projects

use crate::error::{AppError, Result};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::Stdio;
use tokio::process::Command;

/// .NET Manager for dotnet CLI operations
pub struct DotnetManager {
    dotnet_path: String,
}

impl DotnetManager {
    /// Create a new DotnetManager, detecting the dotnet CLI path
    pub fn new() -> Self {
        let dotnet_path = Self::find_dotnet_path();
        tracing::info!("DotnetManager using dotnet at: {}", dotnet_path);
        Self { dotnet_path }
    }

    /// Find the dotnet CLI path
    fn find_dotnet_path() -> String {
        // Common dotnet installation paths on macOS
        let paths = vec![
            "/opt/homebrew/bin/dotnet",       // Homebrew ARM64
            "/usr/local/bin/dotnet",          // Homebrew x86_64
            "/usr/local/share/dotnet/dotnet", // Official installer
            "/usr/share/dotnet/dotnet",       // Linux
            "dotnet",                         // In PATH
        ];

        for path in paths {
            if std::path::Path::new(path).exists() {
                return path.to_string();
            }
        }

        // Try to find via `which dotnet`
        if let Ok(output) = std::process::Command::new("which").arg("dotnet").output() {
            if output.status.success() {
                let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !path.is_empty() {
                    return path;
                }
            }
        }

        // Fallback
        "dotnet".to_string()
    }

    /// Get .NET SDK version
    pub async fn version(&self) -> Result<String> {
        let output = Command::new(&self.dotnet_path)
            .arg("--version")
            .output()
            .await
            .map_err(|e| AppError::ExecutionError(format!("Failed to get .NET version: {}", e)))?;

        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    }

    /// Create a new .NET project
    pub async fn new_project(
        &self,
        template: &str,
        name: &str,
        output_dir: &str,
    ) -> Result<DotnetOutput> {
        // Create the full output path
        let full_output_path = std::path::PathBuf::from(output_dir).join(name);
        let output_path_str = full_output_path.to_string_lossy().to_string();

        tracing::info!(
            "Creating .NET project: template={}, name={}, output={}",
            template,
            name,
            output_path_str
        );

        let output = Command::new(&self.dotnet_path)
            .arg("new")
            .arg(template)
            .arg("-n")
            .arg(name)
            .arg("-o")
            .arg(&output_path_str)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await
            .map_err(|e| AppError::ExecutionError(format!("Failed to create project: {}", e)))?;

        let result = DotnetOutput {
            success: output.status.success(),
            stdout: String::from_utf8_lossy(&output.stdout).to_string(),
            stderr: String::from_utf8_lossy(&output.stderr).to_string(),
            exit_code: output.status.code().unwrap_or(-1),
        };

        tracing::info!(
            "dotnet new result: success={}, stdout={}, stderr={}",
            result.success,
            result.stdout,
            result.stderr
        );

        Ok(result)
    }

    /// Build a .NET project
    pub async fn build(&self, project_path: &str, configuration: &str) -> Result<DotnetOutput> {
        let output = Command::new(&self.dotnet_path)
            .arg("build")
            .arg(project_path)
            .arg("-c")
            .arg(configuration)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await
            .map_err(|e| AppError::ExecutionError(format!("Failed to build project: {}", e)))?;

        Ok(DotnetOutput {
            success: output.status.success(),
            stdout: String::from_utf8_lossy(&output.stdout).to_string(),
            stderr: String::from_utf8_lossy(&output.stderr).to_string(),
            exit_code: output.status.code().unwrap_or(-1),
        })
    }

    /// Run a .NET project
    pub async fn run(&self, project_path: &str, args: Vec<String>) -> Result<DotnetOutput> {
        let mut cmd = Command::new(&self.dotnet_path);
        cmd.arg("run").arg("--project").arg(project_path);

        for arg in args {
            cmd.arg(arg);
        }

        let output = cmd
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await
            .map_err(|e| AppError::ExecutionError(format!("Failed to run project: {}", e)))?;

        Ok(DotnetOutput {
            success: output.status.success(),
            stdout: String::from_utf8_lossy(&output.stdout).to_string(),
            stderr: String::from_utf8_lossy(&output.stderr).to_string(),
            exit_code: output.status.code().unwrap_or(-1),
        })
    }

    /// Restore NuGet packages
    pub async fn restore(&self, project_path: &str) -> Result<DotnetOutput> {
        let output = Command::new(&self.dotnet_path)
            .arg("restore")
            .arg(project_path)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await
            .map_err(|e| AppError::ExecutionError(format!("Failed to restore packages: {}", e)))?;

        Ok(DotnetOutput {
            success: output.status.success(),
            stdout: String::from_utf8_lossy(&output.stdout).to_string(),
            stderr: String::from_utf8_lossy(&output.stderr).to_string(),
            exit_code: output.status.code().unwrap_or(-1),
        })
    }

    /// Add a NuGet package
    pub async fn add_package(
        &self,
        project_path: &str,
        package_name: &str,
        version: Option<&str>,
    ) -> Result<DotnetOutput> {
        let mut cmd = Command::new(&self.dotnet_path);
        cmd.arg("add")
            .arg(project_path)
            .arg("package")
            .arg(package_name);

        if let Some(ver) = version {
            cmd.arg("-v").arg(ver);
        }

        let output = cmd
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await
            .map_err(|e| AppError::ExecutionError(format!("Failed to add package: {}", e)))?;

        Ok(DotnetOutput {
            success: output.status.success(),
            stdout: String::from_utf8_lossy(&output.stdout).to_string(),
            stderr: String::from_utf8_lossy(&output.stderr).to_string(),
            exit_code: output.status.code().unwrap_or(-1),
        })
    }

    /// Clean build outputs
    pub async fn clean(&self, project_path: &str) -> Result<DotnetOutput> {
        let output = Command::new(&self.dotnet_path)
            .arg("clean")
            .arg(project_path)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await
            .map_err(|e| AppError::ExecutionError(format!("Failed to clean project: {}", e)))?;

        Ok(DotnetOutput {
            success: output.status.success(),
            stdout: String::from_utf8_lossy(&output.stdout).to_string(),
            stderr: String::from_utf8_lossy(&output.stderr).to_string(),
            exit_code: output.status.code().unwrap_or(-1),
        })
    }

    /// List available .NET templates
    pub async fn list_templates(&self) -> Result<Vec<DotnetTemplate>> {
        let output = Command::new(&self.dotnet_path)
            .arg("new")
            .arg("list")
            .output()
            .await
            .map_err(|e| AppError::ExecutionError(format!("Failed to list templates: {}", e)))?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        Ok(parse_templates(&stdout))
    }
}

/// Parse dotnet new list output
fn parse_templates(output: &str) -> Vec<DotnetTemplate> {
    let mut templates = Vec::new();

    // Add common templates manually for now
    templates.push(DotnetTemplate {
        name: "Console App".to_string(),
        short_name: "console".to_string(),
        language: "C#".to_string(),
        tags: vec!["Common".to_string()],
    });

    templates.push(DotnetTemplate {
        name: "Class Library".to_string(),
        short_name: "classlib".to_string(),
        language: "C#".to_string(),
        tags: vec!["Common".to_string()],
    });

    templates.push(DotnetTemplate {
        name: "ASP.NET Core Web API".to_string(),
        short_name: "webapi".to_string(),
        language: "C#".to_string(),
        tags: vec!["Web".to_string(), "Cloud".to_string()],
    });

    templates.push(DotnetTemplate {
        name: "ASP.NET Core Web App (MVC)".to_string(),
        short_name: "mvc".to_string(),
        language: "C#".to_string(),
        tags: vec!["Web".to_string(), "MVC".to_string()],
    });

    templates.push(DotnetTemplate {
        name: "Blazor Server App".to_string(),
        short_name: "blazorserver".to_string(),
        language: "C#".to_string(),
        tags: vec!["Web".to_string(), "Blazor".to_string()],
    });

    templates.push(DotnetTemplate {
        name: "Blazor WebAssembly App".to_string(),
        short_name: "blazorwasm".to_string(),
        language: "C#".to_string(),
        tags: vec![
            "Web".to_string(),
            "Blazor".to_string(),
            "WebAssembly".to_string(),
        ],
    });

    templates.push(DotnetTemplate {
        name: "xUnit Test Project".to_string(),
        short_name: "xunit".to_string(),
        language: "C#".to_string(),
        tags: vec!["Test".to_string(), "xUnit".to_string()],
    });

    templates.push(DotnetTemplate {
        name: "NUnit Test Project".to_string(),
        short_name: "nunit".to_string(),
        language: "C#".to_string(),
        tags: vec!["Test".to_string(), "NUnit".to_string()],
    });

    templates
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DotnetOutput {
    pub success: bool,
    pub stdout: String,
    pub stderr: String,
    pub exit_code: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DotnetTemplate {
    pub name: String,
    pub short_name: String,
    pub language: String,
    pub tags: Vec<String>,
}
