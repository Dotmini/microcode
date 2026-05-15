//! Rosetta 2 Support Module
//!
//! Handles detection and execution of x86-64 binaries on Apple Silicon
//! using Apple's Rosetta 2 translation layer.

use crate::error::{AppError, Result};
use serde::{Deserialize, Serialize};
use std::process::Command;

// MARK: - Architecture Detection

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum Architecture {
    Arm64,  // Apple Silicon (M1, M2, M3, etc.)
    X86_64, // Intel
    Unknown,
}

impl std::fmt::Display for Architecture {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Architecture::Arm64 => write!(f, "arm64"),
            Architecture::X86_64 => write!(f, "x86_64"),
            Architecture::Unknown => write!(f, "unknown"),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemInfo {
    pub native_arch: Architecture,
    pub running_under_rosetta: bool,
    pub rosetta_installed: bool,
    pub rosetta_version: Option<String>,
    pub macos_version: String,
    pub chip_name: String,
}

// MARK: - Rosetta Manager

pub struct RosettaManager;

impl RosettaManager {
    /// Get current system architecture
    pub fn get_native_architecture() -> Architecture {
        let output = Command::new("uname").arg("-m").output();

        match output {
            Ok(out) => {
                let arch = String::from_utf8_lossy(&out.stdout).trim().to_lowercase();

                match arch.as_str() {
                    "arm64" | "aarch64" => Architecture::Arm64,
                    "x86_64" | "i386" | "i686" => Architecture::X86_64,
                    _ => Architecture::Unknown,
                }
            }
            Err(_) => Architecture::Unknown,
        }
    }

    /// Check if currently running under Rosetta 2
    pub fn is_running_under_rosetta() -> bool {
        // sysctl.proc_translated returns 1 if running under Rosetta
        let output = Command::new("sysctl")
            .args(["-n", "sysctl.proc_translated"])
            .output();

        match output {
            Ok(out) => {
                let result = String::from_utf8_lossy(&out.stdout).trim().to_string();
                result == "1"
            }
            Err(_) => false,
        }
    }

    /// Check if Rosetta 2 is installed on the system
    pub fn is_rosetta_installed() -> bool {
        // Check if oahd (Rosetta daemon) is present
        let oahd_path = std::path::Path::new("/Library/Apple/usr/libexec/oah/oahd");
        if oahd_path.exists() {
            return true;
        }

        // Alternative check using arch command
        let output = Command::new("arch").args(["-x86_64", "true"]).output();

        match output {
            Ok(out) => out.status.success(),
            Err(_) => false,
        }
    }

    /// Install Rosetta 2 if not present (requires user approval)
    pub async fn install_rosetta() -> Result<bool> {
        if Self::is_rosetta_installed() {
            return Ok(true);
        }

        // Rosetta installation command
        let output = tokio::process::Command::new("softwareupdate")
            .args(["--install-rosetta", "--agree-to-license"])
            .output()
            .await
            .map_err(|e| AppError::InternalError(format!("Failed to install Rosetta: {}", e)))?;

        if output.status.success() {
            Ok(true)
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr);
            Err(AppError::InternalError(format!(
                "Rosetta installation failed: {}",
                stderr
            )))
        }
    }

    /// Get comprehensive system information
    pub fn get_system_info() -> SystemInfo {
        let native_arch = Self::get_native_architecture();
        let running_under_rosetta = Self::is_running_under_rosetta();
        let rosetta_installed = Self::is_rosetta_installed();

        // Get macOS version
        let macos_version = Command::new("sw_vers")
            .arg("-productVersion")
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .unwrap_or_else(|_| "Unknown".to_string());

        // Get chip name
        let chip_name = Command::new("sysctl")
            .args(["-n", "machdep.cpu.brand_string"])
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .unwrap_or_else(|_| "Unknown".to_string());

        // Get Rosetta version (if available)
        let rosetta_version = if rosetta_installed {
            Command::new("/Library/Apple/usr/libexec/oah/oahd")
                .arg("-v")
                .output()
                .ok()
                .and_then(|o| {
                    let v = String::from_utf8_lossy(&o.stdout).trim().to_string();
                    if v.is_empty() {
                        None
                    } else {
                        Some(v)
                    }
                })
        } else {
            None
        };

        SystemInfo {
            native_arch,
            running_under_rosetta,
            rosetta_installed,
            rosetta_version,
            macos_version,
            chip_name,
        }
    }

    /// Run a binary with specific architecture
    pub async fn run_with_arch(
        binary: &str,
        args: &[&str],
        arch: Architecture,
    ) -> Result<(String, String, i32)> {
        let output = match arch {
            Architecture::X86_64 => {
                // Use arch command to force x86_64 (Rosetta)
                tokio::process::Command::new("arch")
                    .arg("-x86_64")
                    .arg(binary)
                    .args(args)
                    .output()
                    .await
            }
            Architecture::Arm64 => {
                // Use arch command to force arm64 (native)
                tokio::process::Command::new("arch")
                    .arg("-arm64")
                    .arg(binary)
                    .args(args)
                    .output()
                    .await
            }
            Architecture::Unknown => {
                // Run normally
                tokio::process::Command::new(binary)
                    .args(args)
                    .output()
                    .await
            }
        };

        match output {
            Ok(out) => {
                let stdout = String::from_utf8_lossy(&out.stdout).to_string();
                let stderr = String::from_utf8_lossy(&out.stderr).to_string();
                let exit_code = out.status.code().unwrap_or(-1);
                Ok((stdout, stderr, exit_code))
            }
            Err(e) => Err(AppError::InternalError(format!(
                "Failed to run binary: {}",
                e
            ))),
        }
    }

    /// Check binary architecture
    pub fn get_binary_architecture(binary_path: &str) -> Vec<Architecture> {
        let output = Command::new("file").arg(binary_path).output();

        match output {
            Ok(out) => {
                let info = String::from_utf8_lossy(&out.stdout).to_lowercase();
                let mut archs = Vec::new();

                if info.contains("arm64") || info.contains("arm_v8") {
                    archs.push(Architecture::Arm64);
                }
                if info.contains("x86_64") || info.contains("64-bit") {
                    archs.push(Architecture::X86_64);
                }

                archs
            }
            Err(_) => Vec::new(),
        }
    }

    /// Check if a binary can run on this system
    pub fn can_run_binary(binary_path: &str) -> bool {
        let binary_archs = Self::get_binary_architecture(binary_path);
        let native_arch = Self::get_native_architecture();

        // Can run if:
        // 1. Binary has native architecture
        if binary_archs.contains(&native_arch) {
            return true;
        }

        // 2. On Apple Silicon with Rosetta, can run x86_64
        if native_arch == Architecture::Arm64
            && binary_archs.contains(&Architecture::X86_64)
            && Self::is_rosetta_installed()
        {
            return true;
        }

        false
    }

    /// Create universal binary from arm64 and x86_64 binaries
    pub async fn create_universal_binary(
        arm64_path: &str,
        x86_64_path: &str,
        output_path: &str,
    ) -> Result<()> {
        let output = tokio::process::Command::new("lipo")
            .args(["-create", arm64_path, x86_64_path, "-output", output_path])
            .output()
            .await
            .map_err(|e| AppError::InternalError(format!("lipo failed: {}", e)))?;

        if output.status.success() {
            Ok(())
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr);
            Err(AppError::InternalError(format!("lipo failed: {}", stderr)))
        }
    }

    /// Extract architecture-specific binary from universal binary
    pub async fn extract_architecture(
        universal_path: &str,
        arch: Architecture,
        output_path: &str,
    ) -> Result<()> {
        let arch_str = match arch {
            Architecture::Arm64 => "arm64",
            Architecture::X86_64 => "x86_64",
            Architecture::Unknown => {
                return Err(AppError::BadRequest("Unknown architecture".into()))
            }
        };

        let output = tokio::process::Command::new("lipo")
            .args([universal_path, "-thin", arch_str, "-output", output_path])
            .output()
            .await
            .map_err(|e| AppError::InternalError(format!("lipo extract failed: {}", e)))?;

        if output.status.success() {
            Ok(())
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr);
            Err(AppError::InternalError(format!(
                "lipo extract failed: {}",
                stderr
            )))
        }
    }
}

// MARK: - API Handlers

pub fn get_rosetta_status() -> SystemInfo {
    RosettaManager::get_system_info()
}

pub async fn ensure_rosetta() -> Result<bool> {
    if RosettaManager::is_rosetta_installed() {
        Ok(true)
    } else {
        RosettaManager::install_rosetta().await
    }
}

pub async fn run_x86_binary(binary: &str, args: &[&str]) -> Result<(String, String, i32)> {
    // Ensure Rosetta is installed
    if !RosettaManager::is_rosetta_installed() {
        return Err(AppError::BadRequest(
            "Rosetta 2 not installed. Please install it first.".into(),
        ));
    }

    RosettaManager::run_with_arch(binary, args, Architecture::X86_64).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_architecture_detection() {
        let arch = RosettaManager::get_native_architecture();
        println!("Native architecture: {:?}", arch);
        assert!(arch != Architecture::Unknown);
    }

    #[test]
    fn test_system_info() {
        let info = RosettaManager::get_system_info();
        println!("System info: {:?}", info);
        assert!(!info.macos_version.is_empty());
    }
}
