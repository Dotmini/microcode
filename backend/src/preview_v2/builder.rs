use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Serialize, Deserialize)]
pub struct CompilationError {
    pub file: String,
    pub line: usize,
    pub column: usize,
    pub message: String,
    pub severity: String, // "error" | "warning"
}

#[derive(Debug, Serialize)]
pub enum BuildResult {
    Success(PathBuf),
    Failure(Vec<CompilationError>),
}

pub fn compile_swift_to_dylib(source_path: &Path, output_dir: &Path) -> BuildResult {
    // 1. Generate Unique Hash (Timestamp + Random) to bypass OS caching
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let file_stem = source_path.file_stem().unwrap().to_string_lossy();
    let unique_name = format!("{}_{}", file_stem, timestamp);
    let dylib_path = output_dir.join(format!("lib{}.dylib", unique_name));

    // Ensure output directory exists // turbo
    if !output_dir.exists() {
        let _ = std::fs::create_dir_all(output_dir);
    }

    // 2. Construct swiftc command
    // Note: -emit-library produces a dylib.
    // We link against SwiftUI and necessary frameworks.
    // Assuming macOS SDK path - in production code this should be dynamic or env var
    let sdk_path = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";

    let mut command = Command::new("swiftc");
    command
        .arg("-emit-library")
        .arg("-o")
        .arg(&dylib_path)
        .arg(source_path)
        .arg("-sdk")
        .arg(sdk_path)
        .arg("-target")
        .arg("arm64-apple-macosx14.0") // Match target OS - make sure this matches user machine or use host target
        .arg("-Xfrontend")
        .arg("-enable-implicit-dynamic") // Enable hot swapping features
        .arg("-parseable-output"); // JSON output for errors

    // Add search paths if necessary, e.g. -I /path/to/modules

    let output = command.output();

    match output {
        Ok(out) => {
            if out.status.success() {
                return BuildResult::Success(dylib_path);
            } else {
                // Parse Errors
                let stderr = String::from_utf8_lossy(&out.stderr);
                let stdout = String::from_utf8_lossy(&out.stdout); // parseable output mostly goes to stdout
                let errors = parse_swiftc_errors(&stdout, &stderr);
                return BuildResult::Failure(errors);
            }
        }
        Err(e) => {
            return BuildResult::Failure(vec![CompilationError {
                file: source_path.to_string_lossy().to_string(),
                line: 0,
                column: 0,
                message: format!("Failed to spawn swiftc: {}", e),
                severity: "fatal".to_string(),
            }]);
        }
    }
}

// Helper to parse JSON output from swiftc
fn parse_swiftc_errors(stdout: &str, stderr: &str) -> Vec<CompilationError> {
    let mut errors = Vec::new();

    // Attempt parseable output format
    for line in stdout.lines() {
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(line) {
            // Filter out "finished" kind
            if let Some(kind) = json["kind"].as_str() {
                if kind == "finished" || kind == "began" || kind == "skipped" {
                    continue;
                }
            }

            // Look for error/warning messages
            // The JSON structure depends on swiftc version, usually:
            // { "kind": "interrupted" | "skipped" | "began" | "finished", ... }
            // OR diagnostics:
            // { "kind": "diagnostic", "message": "...", "severity": "error", "location": {...} }

            // Simple heuristic for now based on 'message' presence or 'kind' == 'diagnostic'
            // Real swiftc JSON output is complex.
            // We'll try to extract "message", "severity"

            if let Some(msg) = json["message"].as_str() {
                let severity = json["severity"].as_str().unwrap_or("error").to_string();

                // Try to get location
                let mut line_num = 0;
                let mut col_num = 0;
                // Location format might vary.
                // e.g. location: { "filename": "...", "line": 1, "column": 1 }

                errors.push(CompilationError {
                    file: "".to_string(), // Need to extract from msg struct or location
                    line: line_num,
                    column: col_num,
                    message: msg.to_string(),
                    severity,
                });
            }
        }
    }

    // Fallback if empty (some errors go to stderr mostly in older versions or linker errors)
    if errors.is_empty() && (!stderr.is_empty() || !stdout.is_empty()) {
        let combined = format!("{}\n{}", stdout, stderr);
        // Clean up empty lines
        let msg = combined.trim().to_string();
        if !msg.is_empty() {
            errors.push(CompilationError {
                file: "unknown".to_string(),
                line: 0,
                column: 0,
                message: msg,
                severity: "error".to_string(),
            });
        }
    }

    errors
}
