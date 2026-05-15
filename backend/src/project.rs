//! Project Build System
//!
//! Universal project detection and build commands for multiple project types

use serde::{Deserialize, Serialize};
use std::path::Path;
use std::process::Stdio;
use tokio::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ProjectType {
    Swift,
    Xcode,
    NodeJS,
    Rust,
    Go,
    Python,
    Java,
    Kotlin,
    Android,
    Flutter,
    DotNet,
    Ruby,
    CMake,
    Makefile,
    Unknown,
}

impl ProjectType {
    pub fn as_str(&self) -> &'static str {
        match self {
            ProjectType::Swift => "Swift Package",
            ProjectType::Xcode => "Xcode",
            ProjectType::NodeJS => "Node.js",
            ProjectType::Rust => "Rust",
            ProjectType::Go => "Go",
            ProjectType::Python => "Python",
            ProjectType::Java => "Java",
            ProjectType::Kotlin => "Kotlin",
            ProjectType::Android => "Android",
            ProjectType::Flutter => "Flutter",
            ProjectType::DotNet => ".NET",
            ProjectType::Ruby => "Ruby",
            ProjectType::CMake => "CMake",
            ProjectType::Makefile => "Makefile",
            ProjectType::Unknown => "Unknown",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum BuildAction {
    Build,
    Run,
    Test,
    Clean,
    Install,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BuildConfig {
    pub is_debug: bool,
}

impl Default for BuildConfig {
    fn default() -> Self {
        Self { is_debug: true }
    }
}

#[derive(Debug, Serialize)]
pub struct BuildResult {
    pub success: bool,
    pub output: String,
    pub exit_code: i32,
    pub project_type: String,
}

pub struct ProjectBuilder;

impl ProjectBuilder {
    /// Detect project type from directory contents
    pub fn detect_project_type(path: &Path) -> ProjectType {
        let entries: Vec<String> = std::fs::read_dir(path)
            .map(|rd| {
                rd.filter_map(|e| e.ok())
                    .filter_map(|e| e.file_name().into_string().ok())
                    .collect()
            })
            .unwrap_or_default();

        for entry in &entries {
            let lower = entry.to_lowercase();

            // Swift Package
            if lower == "package.swift" {
                return ProjectType::Swift;
            }

            // Xcode
            if lower.ends_with(".xcodeproj") || lower.ends_with(".xcworkspace") {
                return ProjectType::Xcode;
            }

            // Rust
            if lower == "cargo.toml" {
                return ProjectType::Rust;
            }

            // Go
            if lower == "go.mod" {
                return ProjectType::Go;
            }

            // Node.js
            if lower == "package.json" {
                return ProjectType::NodeJS;
            }

            // Python
            if lower == "requirements.txt" || lower == "setup.py" || lower == "pyproject.toml" {
                return ProjectType::Python;
            }

            // Flutter
            if lower == "pubspec.yaml" {
                return ProjectType::Flutter;
            }

            // .NET
            if lower.ends_with(".csproj") || lower.ends_with(".sln") || lower.ends_with(".fsproj") {
                return ProjectType::DotNet;
            }

            // Java (Maven)
            if lower == "pom.xml" {
                return ProjectType::Java;
            }

            // Android/Kotlin (Gradle)
            if lower == "build.gradle" || lower == "build.gradle.kts" {
                if entries.contains(&"settings.gradle".to_string())
                    || entries.contains(&"settings.gradle.kts".to_string())
                {
                    if entries.iter().any(|e| e == "android" || e == "app") {
                        return ProjectType::Android;
                    }
                    return ProjectType::Kotlin;
                }
            }

            // Ruby
            if lower == "gemfile" || lower == "rakefile" {
                return ProjectType::Ruby;
            }

            // CMake
            if lower == "cmakelists.txt" {
                return ProjectType::CMake;
            }

            // Makefile
            if lower == "makefile" {
                return ProjectType::Makefile;
            }
        }

        ProjectType::Unknown
    }

    /// Get build command for project type
    pub fn get_command(
        project_type: &ProjectType,
        action: &BuildAction,
        config: &BuildConfig,
    ) -> Option<(String, Vec<String>)> {
        let is_debug = config.is_debug;

        match project_type {
            ProjectType::Swift => match action {
                BuildAction::Build => Some((
                    "swift".into(),
                    vec![
                        "build".into(),
                        "-c".into(),
                        if is_debug { "debug" } else { "release" }.into(),
                    ],
                )),
                BuildAction::Run => Some(("swift".into(), vec!["run".into()])),
                BuildAction::Test => Some(("swift".into(), vec!["test".into()])),
                BuildAction::Clean => {
                    Some(("swift".into(), vec!["package".into(), "clean".into()]))
                }
                _ => None,
            },

            ProjectType::Xcode => match action {
                BuildAction::Build => Some((
                    "xcodebuild".into(),
                    vec![
                        "-configuration".into(),
                        if is_debug { "Debug" } else { "Release" }.into(),
                    ],
                )),
                BuildAction::Clean => Some(("xcodebuild".into(), vec!["clean".into()])),
                BuildAction::Test => Some(("xcodebuild".into(), vec!["test".into()])),
                _ => None,
            },

            ProjectType::Rust => match action {
                BuildAction::Build => Some((
                    "cargo".into(),
                    if is_debug {
                        vec!["build".into()]
                    } else {
                        vec!["build".into(), "--release".into()]
                    },
                )),
                BuildAction::Run => Some((
                    "cargo".into(),
                    if is_debug {
                        vec!["run".into()]
                    } else {
                        vec!["run".into(), "--release".into()]
                    },
                )),
                BuildAction::Test => Some(("cargo".into(), vec!["test".into()])),
                BuildAction::Clean => Some(("cargo".into(), vec!["clean".into()])),
                _ => None,
            },

            ProjectType::Go => match action {
                BuildAction::Build => Some(("go".into(), vec!["build".into(), "./...".into()])),
                BuildAction::Run => Some(("go".into(), vec!["run".into(), ".".into()])),
                BuildAction::Test => Some(("go".into(), vec!["test".into(), "./...".into()])),
                BuildAction::Clean => Some(("go".into(), vec!["clean".into()])),
                _ => None,
            },

            ProjectType::NodeJS => match action {
                BuildAction::Build => Some(("npm".into(), vec!["run".into(), "build".into()])),
                BuildAction::Run => Some(("npm".into(), vec!["start".into()])),
                BuildAction::Test => Some(("npm".into(), vec!["test".into()])),
                BuildAction::Install => Some(("npm".into(), vec!["install".into()])),
                _ => None,
            },

            ProjectType::Python => match action {
                BuildAction::Run => Some(("python3".into(), vec!["main.py".into()])),
                BuildAction::Test => Some(("python3".into(), vec!["-m".into(), "pytest".into()])),
                BuildAction::Install => Some((
                    "pip3".into(),
                    vec!["install".into(), "-r".into(), "requirements.txt".into()],
                )),
                _ => None,
            },

            ProjectType::Flutter => match action {
                BuildAction::Build => Some((
                    "flutter".into(),
                    vec![
                        "build".into(),
                        "apk".into(),
                        if is_debug { "--debug" } else { "--release" }.into(),
                    ],
                )),
                BuildAction::Run => Some(("flutter".into(), vec!["run".into()])),
                BuildAction::Test => Some(("flutter".into(), vec!["test".into()])),
                BuildAction::Clean => Some(("flutter".into(), vec!["clean".into()])),
                BuildAction::Install => Some(("flutter".into(), vec!["pub".into(), "get".into()])),
            },

            ProjectType::DotNet => match action {
                BuildAction::Build => Some((
                    "dotnet".into(),
                    vec![
                        "build".into(),
                        "-c".into(),
                        if is_debug { "Debug" } else { "Release" }.into(),
                    ],
                )),
                BuildAction::Run => Some(("dotnet".into(), vec!["run".into()])),
                BuildAction::Test => Some(("dotnet".into(), vec!["test".into()])),
                BuildAction::Clean => Some(("dotnet".into(), vec!["clean".into()])),
                BuildAction::Install => Some(("dotnet".into(), vec!["restore".into()])),
            },

            ProjectType::Java => match action {
                BuildAction::Build => Some(("mvn".into(), vec!["compile".into()])),
                BuildAction::Run => Some(("mvn".into(), vec!["exec:java".into()])),
                BuildAction::Test => Some(("mvn".into(), vec!["test".into()])),
                BuildAction::Clean => Some(("mvn".into(), vec!["clean".into()])),
                BuildAction::Install => Some(("mvn".into(), vec!["install".into()])),
            },

            ProjectType::Android | ProjectType::Kotlin => match action {
                BuildAction::Build => Some((
                    "./gradlew".into(),
                    vec![if is_debug {
                        "assembleDebug"
                    } else {
                        "assembleRelease"
                    }
                    .into()],
                )),
                BuildAction::Run => Some(("./gradlew".into(), vec!["installDebug".into()])),
                BuildAction::Test => Some(("./gradlew".into(), vec!["test".into()])),
                BuildAction::Clean => Some(("./gradlew".into(), vec!["clean".into()])),
                _ => None,
            },

            ProjectType::Ruby => match action {
                BuildAction::Run => Some(("ruby".into(), vec!["main.rb".into()])),
                BuildAction::Test => Some(("rake".into(), vec!["test".into()])),
                BuildAction::Install => Some(("bundle".into(), vec!["install".into()])),
                _ => None,
            },

            ProjectType::CMake => match action {
                BuildAction::Build => Some((
                    "cmake".into(),
                    vec![
                        "--build".into(),
                        "build".into(),
                        "--config".into(),
                        if is_debug { "Debug" } else { "Release" }.into(),
                    ],
                )),
                BuildAction::Clean => Some((
                    "cmake".into(),
                    vec![
                        "--build".into(),
                        "build".into(),
                        "--target".into(),
                        "clean".into(),
                    ],
                )),
                _ => None,
            },

            ProjectType::Makefile => match action {
                BuildAction::Build => Some(("make".into(), vec![])),
                BuildAction::Run => Some(("make".into(), vec!["run".into()])),
                BuildAction::Clean => Some(("make".into(), vec!["clean".into()])),
                _ => None,
            },

            ProjectType::Unknown => None,
        }
    }

    /// Execute build action
    pub async fn execute(path: &Path, action: BuildAction, config: BuildConfig) -> BuildResult {
        let project_type = Self::detect_project_type(path);

        if matches!(project_type, ProjectType::Unknown) {
            return BuildResult {
                success: false,
                output: "No recognized project type found".into(),
                exit_code: -1,
                project_type: "Unknown".into(),
            };
        }

        let Some((cmd, args)) = Self::get_command(&project_type, &action, &config) else {
            return BuildResult {
                success: false,
                output: format!(
                    "Action {:?} not supported for {} projects",
                    action,
                    project_type.as_str()
                ),
                exit_code: -1,
                project_type: project_type.as_str().into(),
            };
        };

        // Find executable
        let executable = Self::find_executable(&cmd);

        let result = Command::new(&executable)
            .args(&args)
            .current_dir(path)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await;

        match result {
            Ok(output) => {
                let stdout = String::from_utf8_lossy(&output.stdout);
                let stderr = String::from_utf8_lossy(&output.stderr);
                let combined = format!("{}\n{}", stdout, stderr);

                BuildResult {
                    success: output.status.success(),
                    output: combined,
                    exit_code: output.status.code().unwrap_or(-1),
                    project_type: project_type.as_str().into(),
                }
            }
            Err(e) => BuildResult {
                success: false,
                output: format!("Failed to execute: {}", e),
                exit_code: -1,
                project_type: project_type.as_str().into(),
            },
        }
    }

    fn find_executable(name: &str) -> String {
        let paths = [
            format!("/opt/homebrew/bin/{}", name),
            format!("/usr/local/bin/{}", name),
            format!("/usr/bin/{}", name),
            format!("/bin/{}", name),
        ];

        for path in &paths {
            if std::path::Path::new(path).exists() {
                return path.clone();
            }
        }

        name.to_string()
    }
}

#[derive(Debug, Deserialize)]
pub struct BuildRequest {
    pub path: String,
    pub action: String,
    pub is_debug: bool,
}

#[derive(Debug, Deserialize)]
pub struct DetectRequest {
    pub path: String,
}

#[derive(Debug, Serialize)]
pub struct DetectResponse {
    pub project_type: String,
    pub icon: String,
    pub supported_actions: Vec<String>,
}
