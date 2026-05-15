//! Code runner module
//!
//! Provides code execution capabilities for multiple languages
//!
//! Tirawat Nantamas | Dotmini Software | SPU AI CLUB

use crate::error::{AppError, Result};
use crate::models::ExecutionOutput;
use futures::stream::{Stream, StreamExt};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Instant;
use tokio::fs;
use tokio::io::{AsyncBufReadExt, AsyncRead, BufReader};
use tokio::process::Command;
use tokio_util::codec::{FramedRead, LinesCodec};
use uuid::Uuid;

#[derive(Debug, serde::Serialize)]
pub struct ExecutionResult {
    pub stdout: String,
    pub stderr: String,
    pub exit_code: i32,
}

#[derive(Debug, Clone, serde::Serialize)]
pub enum StreamEvent {
    Output(String),
    Error(String),
}

use std::pin::Pin;
use std::task::{Context, Poll};
use tokio::process::Child;

// A stream that holds the Child process handle to prevent it from being dropped (and killed)
// until the stream itself is dropped.
pub struct ProcessStream<S> {
    stream: S,
    _child: Child,
}

impl<S: Stream + Unpin> Stream for ProcessStream<S> {
    type Item = S::Item;

    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        Pin::new(&mut self.stream).poll_next(cx)
    }
}

pub async fn execute_stream(
    code: &str,
    language: &str,
    _node_path: Option<String>,
) -> Result<Pin<Box<dyn Stream<Item = std::result::Result<StreamEvent, AppError>> + Send>>> {
    let lang_id = language.to_lowercase().trim().to_string();
    let extension = match lang_id.as_str() {
        "python" => "py",
        "javascript" | "js" => "js",
        "swift" => "swift",
        "rust" => "rs",
        "go" => "go",
        "d" | "dlang" => "d",
        "typescript" | "ts" => "ts",
        "r" => "R",
        "objective-c" | "objc" => "m",
        "objective-cpp" | "objcpp" => "mm",
        "ardium" | "ar" => "ar",
        _ => {
            return Err(AppError::ExecutionError(format!(
                "Unsupported language: {}",
                language
            )))
        }
    };

    let temp_file = create_temp_file(extension, code).await?;

    // Handle Ardium separately to avoid lifetime issues
    if lang_id == "ardium" || lang_id == "ar" {
        let ardium_bin =
            std::env::var("ARDIUM_BIN").unwrap_or_else(|_| "/usr/local/bin/arc".to_string());

        let mut child = Command::new(&ardium_bin)
            .arg("run")
            .arg(&temp_file)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .map_err(|e| AppError::ExecutionError(format!("Failed to spawn Ardium: {}", e)))?;

        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| AppError::ExecutionError("Failed to capture stdout".into()))?;
        let stderr = child
            .stderr
            .take()
            .ok_or_else(|| AppError::ExecutionError("Failed to capture stderr".into()))?;

        let stdout_stream = FramedRead::new(stdout, LinesCodec::new()).map(|line| {
            line.map(StreamEvent::Output)
                .map_err(|e| AppError::ExecutionError(e.to_string()))
        });

        let stderr_stream = FramedRead::new(stderr, LinesCodec::new()).map(|line| {
            line.map(StreamEvent::Error)
                .map_err(|e| AppError::ExecutionError(e.to_string()))
        });

        let merged_stream = futures::stream::select(stdout_stream, stderr_stream);

        return Ok(Box::pin(ProcessStream {
            stream: merged_stream,
            _child: child,
        }));
    }

    let (program, args) = match lang_id.as_str() {
        "python" => ("python3", vec!["-u".to_string(), temp_file.clone()]), // -u for unbuffered
        "javascript" | "js" => ("node", vec![temp_file.clone()]),
        "typescript" | "ts" => ("ts-node", vec![temp_file.clone()]),
        "swift" => ("swift", vec![temp_file.clone()]),
        "rust" => ("cargo", vec!["script".to_string(), temp_file.clone()]),
        "go" => ("go", vec!["run".to_string(), temp_file.clone()]),
        "d" | "dlang" => ("rdmd", vec![temp_file.clone()]),
        "r" => {
            // Special handling for R with proper library paths
            return streaming_execute_r(&temp_file).await;
        }
        "objective-c" | "objc" | "objective-cpp" | "objcpp" => {
            // Special handling for compilation-based streaming
            return streaming_execute_compilation_lang(lang_id.as_str(), &temp_file).await;
        }
        _ => {
            return Err(AppError::ExecutionError(format!(
                "Unsupported language: {}",
                language
            )))
        }
    };

    let mut child = Command::new(program)
        .args(&args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .map_err(|e| AppError::ExecutionError(format!("Failed to spawn process: {}", e)))?;

    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| AppError::ExecutionError("Failed to capture stdout".into()))?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| AppError::ExecutionError("Failed to capture stderr".into()))?;

    let stdout_stream = FramedRead::new(stdout, LinesCodec::new()).map(|line| {
        line.map(StreamEvent::Output)
            .map_err(|e| AppError::ExecutionError(e.to_string()))
    });

    let stderr_stream = FramedRead::new(stderr, LinesCodec::new()).map(|line| {
        line.map(StreamEvent::Error)
            .map_err(|e| AppError::ExecutionError(e.to_string()))
    });

    let merged_stream = futures::stream::select(stdout_stream, stderr_stream);

    // Wrap the stream with the child handle to keep the process alive
    Ok(Box::pin(ProcessStream {
        stream: merged_stream,
        _child: child,
    }))
}

/// Execute code in the specified language
pub async fn execute(
    code: &str,
    language: &str,
    node_path: Option<String>,
) -> Result<ExecutionOutput> {
    let start = Instant::now();
    let lang_id = language.to_lowercase().trim().to_string();

    tracing::info!("Backend execution request: language='{}'", lang_id);

    let result = match lang_id.as_str() {
        "python" => execute_python(code).await?,
        "javascript" | "js" => execute_javascript(code, node_path).await?,
        "typescript" | "ts" => execute_typescript(code, node_path).await?,
        "rust" => execute_rust(code).await?,
        "go" => execute_go(code).await?,
        "d" | "dlang" => execute_d(code).await?,
        "ruby" | "rb" => execute_ruby(code).await?,
        "swift" => execute_swift(code).await?,
        "ardium" | "ar" => execute_ardium(code).await?,
        "r" => execute_r(code).await?,

        "c" => execute_c(code).await?,
        "c++" | "cpp" => execute_cpp(code).await?,
        "objective-c" | "objc" => execute_objc(code).await?,
        "objective-cpp" | "objcpp" => execute_objcpp(code).await?,

        // JVM Languages
        "java" => execute_java(code).await?,
        "kotlin" | "kt" => execute_kotlin(code).await?,

        // Scripting Languages
        "lua" => execute_lua(code).await?,
        "perl" | "pl" => execute_perl(code).await?,
        "php" => execute_php(code).await?,

        // Shell/SQL
        "shell" | "bash" | "sh" => execute_shell(code).await?,
        "sql" => execute_sql(code).await?,

        _ => {
            return Err(AppError::ExecutionError(format!(
                "Unsupported language: {}",
                language
            )))
        }
    };

    let execution_time = start.elapsed().as_secs_f64();

    Ok(ExecutionOutput {
        stdout: result.stdout,
        stderr: result.stderr,
        exit_code: result.exit_code,
        execution_time,
    })
}

/// Stop a running execution by ID
pub async fn stop(_execution_id: &str) -> Result<()> {
    // In a production system, you would maintain a registry of running processes
    // and be able to kill them by ID
    Err(AppError::NotImplemented("stop execution".to_string()))
}

// Language-specific execution functions

async fn execute_python(code: &str) -> Result<ExecutionResult> {
    // Wrap code with matplotlib plot capture
    let wrapped_code = format!(
        r#"
import sys
import io

# Capture matplotlib plots if imported
try:
    import matplotlib
    matplotlib.use('Agg')  # Non-interactive backend
    import matplotlib.pyplot as plt
    from io import BytesIO
    import base64
    
    _plot_capture_enabled = True
except ImportError:
    _plot_capture_enabled = False

# User code
{}

# Capture plots if matplotlib was used
if _plot_capture_enabled and plt.get_fignums():
    buf = BytesIO()
    plt.savefig(buf, format='png', dpi=150, bbox_inches='tight')
    buf.seek(0)
    plot_data = base64.b64encode(buf.read()).decode('utf-8')
    print(f"\n__PLOT_DATA__:{{plot_data}}")
    plt.close('all')
"#,
        code
    );

    let temp_file = create_temp_file("py", &wrapped_code).await?;

    let mut child = Command::new(find_executable("python3"))
        .arg("-u") // Unbuffered output for realtime execution
        .arg(&temp_file)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| AppError::ExecutionError(format!("Failed to spawn python: {}", e)))?;

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    let stdout_reader = BufReader::new(stdout);
    let stderr_reader = BufReader::new(stderr);

    let mut stdout_lines = stdout_reader.lines();
    let mut stderr_lines = stderr_reader.lines();

    let mut stdout_output = String::new();
    let mut stderr_output = String::new();

    // Read stdout
    while let Ok(Some(line)) = stdout_lines.next_line().await {
        stdout_output.push_str(&line);
        stdout_output.push('\n');
    }

    // Read stderr
    while let Ok(Some(line)) = stderr_lines.next_line().await {
        stderr_output.push_str(&line);
        stderr_output.push('\n');
    }

    let timeout_duration = std::time::Duration::from_secs(30);

    let status_result = tokio::time::timeout(timeout_duration, child.wait()).await;

    let status = match status_result {
        Ok(Ok(s)) => s,
        Ok(Err(e)) => {
            return Err(AppError::ExecutionError(format!(
                "Failed to wait for python: {}",
                e
            )));
        }
        Err(_) => {
            let _ = child.kill().await;
            return Err(AppError::ExecutionError(
                "Execution timed out (30s limit)".to_string(),
            ));
        }
    };

    cleanup_temp_file(&temp_file).await;

    Ok(ExecutionResult {
        stdout: stdout_output,
        stderr: stderr_output,
        exit_code: status.code().unwrap_or(-1),
    })
}

async fn execute_javascript(code: &str, node_path: Option<String>) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("js", code).await?;

    let binary = node_path.unwrap_or_else(|| find_executable("node"));
    let mut child = Command::new(binary)
        .arg(&temp_file)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| AppError::ExecutionError(format!("Failed to spawn node: {}", e)))?;

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    let stdout_reader = BufReader::new(stdout);
    let stderr_reader = BufReader::new(stderr);

    let mut stdout_lines = stdout_reader.lines();
    let mut stderr_lines = stderr_reader.lines();

    let mut stdout_output = String::new();
    let mut stderr_output = String::new();

    while let Ok(Some(line)) = stdout_lines.next_line().await {
        stdout_output.push_str(&line);
        stdout_output.push('\n');
    }

    while let Ok(Some(line)) = stderr_lines.next_line().await {
        stderr_output.push_str(&line);
        stderr_output.push('\n');
    }

    let timeout_duration = std::time::Duration::from_secs(30);

    let status_result = tokio::time::timeout(timeout_duration, child.wait()).await;

    let status = match status_result {
        Ok(Ok(s)) => s,
        Ok(Err(e)) => {
            return Err(AppError::ExecutionError(format!(
                "Failed to wait for node: {}",
                e
            )));
        }
        Err(_) => {
            let _ = child.kill().await;
            return Err(AppError::ExecutionError(
                "Execution timed out (30s limit)".to_string(),
            ));
        }
    };

    cleanup_temp_file(&temp_file).await;

    Ok(ExecutionResult {
        stdout: stdout_output,
        stderr: stderr_output,
        exit_code: status.code().unwrap_or(-1),
    })
}

async fn execute_typescript(code: &str, _node_path: Option<String>) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("ts", code).await?;

    let binary = find_executable("ts-node");

    let mut child = Command::new(&binary)
        .arg(&temp_file)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| {
            AppError::ExecutionError(format!(
                "Failed to spawn ts-node (ensure it is installed): {}",
                e
            ))
        })?;

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    let stdout_reader = BufReader::new(stdout);
    let stderr_reader = BufReader::new(stderr);

    let mut stdout_lines = stdout_reader.lines();
    let mut stderr_lines = stderr_reader.lines();

    let mut stdout_output = String::new();
    let mut stderr_output = String::new();

    while let Ok(Some(line)) = stdout_lines.next_line().await {
        stdout_output.push_str(&line);
        stdout_output.push('\n');
    }

    while let Ok(Some(line)) = stderr_lines.next_line().await {
        stderr_output.push_str(&line);
        stderr_output.push('\n');
    }

    let timeout_duration = std::time::Duration::from_secs(30);
    let status_result = tokio::time::timeout(timeout_duration, child.wait()).await;

    let status = match status_result {
        Ok(Ok(s)) => s,
        Ok(Err(e)) => {
            return Err(AppError::ExecutionError(format!(
                "Failed to wait for ts-node: {}",
                e
            )))
        }
        Err(_) => {
            let _ = child.kill().await;
            return Err(AppError::ExecutionError(
                "Execution timed out (30s limit)".to_string(),
            ));
        }
    };

    cleanup_temp_file(&temp_file).await;

    Ok(ExecutionResult {
        stdout: stdout_output,
        stderr: stderr_output,
        exit_code: status.code().unwrap_or(-1),
    })
}

async fn execute_d(code: &str) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("d", code).await?;

    // Use rdmd for script-like execution (compiles and runs in one go)
    let binary = find_executable("rdmd");

    let mut child = Command::new(&binary)
        .arg(&temp_file)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| AppError::ExecutionError(format!("Failed to spawn rdmd: {}", e)))?;

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    let stdout_reader = BufReader::new(stdout);
    let stderr_reader = BufReader::new(stderr);

    let mut stdout_lines = stdout_reader.lines();
    let mut stderr_lines = stderr_reader.lines();

    let mut stdout_output = String::new();
    let mut stderr_output = String::new();

    while let Ok(Some(line)) = stdout_lines.next_line().await {
        stdout_output.push_str(&line);
        stdout_output.push('\n');
    }

    while let Ok(Some(line)) = stderr_lines.next_line().await {
        stderr_output.push_str(&line);
        stderr_output.push('\n');
    }

    let timeout_duration = std::time::Duration::from_secs(30);
    let status_result = tokio::time::timeout(timeout_duration, child.wait()).await;

    let status = match status_result {
        Ok(Ok(s)) => s,
        Ok(Err(e)) => {
            return Err(AppError::ExecutionError(format!(
                "Failed to wait for rdmd: {}",
                e
            )))
        }
        Err(_) => {
            let _ = child.kill().await;
            return Err(AppError::ExecutionError(
                "Execution timed out (30s limit)".to_string(),
            ));
        }
    };

    cleanup_temp_file(&temp_file).await;

    Ok(ExecutionResult {
        stdout: stdout_output,
        stderr: stderr_output,
        exit_code: status.code().unwrap_or(-1),
    })
}

async fn execute_rust(code: &str) -> Result<ExecutionResult> {
    // Create a temporary Rust project
    let temp_dir = std::env::temp_dir().join(format!("microcode_rust_{}", uuid::Uuid::new_v4()));
    tokio::fs::create_dir_all(&temp_dir)
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to create temp dir: {}", e)))?;

    // Write main.rs
    let main_rs = temp_dir.join("main.rs");
    tokio::fs::write(&main_rs, code)
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to write main.rs: {}", e)))?;

    // Find rustc - check common paths
    let home = std::env::var("HOME").unwrap_or_else(|_| "/Users".to_string());
    let rustc_paths = [
        format!("{}/.cargo/bin/rustc", home),
        "/opt/homebrew/bin/rustc".to_string(),
        "/usr/local/bin/rustc".to_string(),
        "rustc".to_string(), // fallback to PATH
    ];

    let rustc = rustc_paths
        .iter()
        .find(|p| std::path::Path::new(p).exists() || *p == "rustc")
        .map(|s| s.as_str())
        .unwrap_or("rustc");

    // Compile with PATH including cargo bin
    let mut compile_child = Command::new(rustc)
        .arg(&main_rs)
        .arg("-o")
        .arg(temp_dir.join("program"))
        .current_dir(&temp_dir)
        .env(
            "PATH",
            format!(
                "{}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
                home
            ),
        )
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| {
            AppError::ExecutionError(format!(
                "Failed to spawn rustc: {}. Ensure Rust is installed (rustup.rs)",
                e
            ))
        })?;

    let compile_status = compile_child
        .wait()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to compile: {}", e)))?;

    if !compile_status.success() {
        let stderr = compile_child.stderr.take().unwrap();
        let stderr_reader = BufReader::new(stderr);
        let mut stderr_lines = stderr_reader.lines();
        let mut stderr_output = String::new();
        while let Ok(Some(line)) = stderr_lines.next_line().await {
            stderr_output.push_str(&line);
            stderr_output.push('\n');
        }
        cleanup_temp_dir(&temp_dir).await;
        return Err(AppError::CompilationError(stderr_output));
    }

    // Execute
    let mut child = Command::new(temp_dir.join("program"))
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| AppError::ExecutionError(format!("Failed to execute program: {}", e)))?;

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    let stdout_reader = BufReader::new(stdout);
    let stderr_reader = BufReader::new(stderr);

    let mut stdout_lines = stdout_reader.lines();
    let mut stderr_lines = stderr_reader.lines();

    let mut stdout_output = String::new();
    let mut stderr_output = String::new();

    while let Ok(Some(line)) = stdout_lines.next_line().await {
        stdout_output.push_str(&line);
        stdout_output.push('\n');
    }

    while let Ok(Some(line)) = stderr_lines.next_line().await {
        stderr_output.push_str(&line);
        stderr_output.push('\n');
    }

    let status = child
        .wait()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to wait for program: {}", e)))?;

    cleanup_temp_dir(&temp_dir).await;

    Ok(ExecutionResult {
        stdout: stdout_output,
        stderr: stderr_output,
        exit_code: status.code().unwrap_or(-1),
    })
}

async fn execute_go(code: &str) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("go", code).await?;

    let mut child = Command::new(find_executable("go"))
        .arg("run")
        .arg(&temp_file)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| AppError::ExecutionError(format!("Failed to spawn go: {}", e)))?;

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    let stdout_reader = BufReader::new(stdout);
    let stderr_reader = BufReader::new(stderr);

    let mut stdout_lines = stdout_reader.lines();
    let mut stderr_lines = stderr_reader.lines();

    let mut stdout_output = String::new();
    let mut stderr_output = String::new();

    while let Ok(Some(line)) = stdout_lines.next_line().await {
        stdout_output.push_str(&line);
        stdout_output.push('\n');
    }

    while let Ok(Some(line)) = stderr_lines.next_line().await {
        stderr_output.push_str(&line);
        stderr_output.push('\n');
    }

    let status = child
        .wait()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to wait for go: {}", e)))?;

    cleanup_temp_file(&temp_file).await;

    Ok(ExecutionResult {
        stdout: stdout_output,
        stderr: stderr_output,
        exit_code: status.code().unwrap_or(-1),
    })
}

async fn execute_ruby(code: &str) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("rb", code).await?;

    let mut child = Command::new(find_executable("ruby"))
        .arg(&temp_file)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| AppError::ExecutionError(format!("Failed to spawn ruby: {}", e)))?;

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    let stdout_reader = BufReader::new(stdout);
    let stderr_reader = BufReader::new(stderr);

    let mut stdout_lines = stdout_reader.lines();
    let mut stderr_lines = stderr_reader.lines();

    let mut stdout_output = String::new();
    let mut stderr_output = String::new();

    while let Ok(Some(line)) = stdout_lines.next_line().await {
        stdout_output.push_str(&line);
        stdout_output.push('\n');
    }

    while let Ok(Some(line)) = stderr_lines.next_line().await {
        stderr_output.push_str(&line);
        stderr_output.push('\n');
    }

    let status = child
        .wait()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to wait for ruby: {}", e)))?;

    cleanup_temp_file(&temp_file).await;

    Ok(ExecutionResult {
        stdout: stdout_output,
        stderr: stderr_output,
        exit_code: status.code().unwrap_or(-1),
    })
}

async fn execute_swift(code: &str) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("swift", code).await?;

    let mut child = Command::new(find_executable("swift"))
        .arg(&temp_file)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| AppError::ExecutionError(format!("Failed to spawn swift: {}", e)))?;

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    let stdout_reader = BufReader::new(stdout);
    let stderr_reader = BufReader::new(stderr);

    let mut stdout_lines = stdout_reader.lines();
    let mut stderr_lines = stderr_reader.lines();

    let mut stdout_output = String::new();
    let mut stderr_output = String::new();

    while let Ok(Some(line)) = stdout_lines.next_line().await {
        stdout_output.push_str(&line);
        stdout_output.push('\n');
    }

    while let Ok(Some(line)) = stderr_lines.next_line().await {
        stderr_output.push_str(&line);
        stderr_output.push('\n');
    }

    let status = child
        .wait()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to wait for swift: {}", e)))?;

    cleanup_temp_file(&temp_file).await;

    Ok(ExecutionResult {
        stdout: stdout_output,
        stderr: stderr_output,
        exit_code: status.code().unwrap_or(-1),
    })
}

async fn execute_ardium(code: &str) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("ar", code).await?;

    // Use full path to avoid conflict with system 'ar' archiver
    let ardium_binary =
        std::env::var("ARDIUM_BIN").unwrap_or_else(|_| "/usr/local/bin/arc".to_string());

    let mut child = Command::new(&ardium_binary)
        .arg("run")
        .arg(&temp_file)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| AppError::ExecutionError(format!("Failed to spawn arc (Ardium): {}", e)))?;

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    let stdout_reader = BufReader::new(stdout);
    let stderr_reader = BufReader::new(stderr);

    let mut stdout_lines = stdout_reader.lines();
    let mut stderr_lines = stderr_reader.lines();

    let mut stdout_output = String::new();
    let mut stderr_output = String::new();

    while let Ok(Some(line)) = stdout_lines.next_line().await {
        stdout_output.push_str(&line);
        stdout_output.push('\n');
    }

    while let Ok(Some(line)) = stderr_lines.next_line().await {
        stderr_output.push_str(&line);
        stderr_output.push('\n');
    }

    let timeout_duration = std::time::Duration::from_secs(30);
    let status_result = tokio::time::timeout(timeout_duration, child.wait()).await;

    let status = match status_result {
        Ok(Ok(s)) => s,
        Ok(Err(e)) => {
            return Err(AppError::ExecutionError(format!(
                "Failed to wait for arc: {}",
                e
            )))
        }
        Err(_) => {
            let _ = child.kill().await;
            return Err(AppError::ExecutionError(
                "Execution timed out (30s limit)".to_string(),
            ));
        }
    };

    cleanup_temp_file(&temp_file).await;

    Ok(ExecutionResult {
        stdout: stdout_output,
        stderr: stderr_output,
        exit_code: status.code().unwrap_or(-1),
    })
}

/// Find Rscript binary
fn find_rscript() -> String {
    let r_paths = [
        "/opt/homebrew/bin/Rscript",
        "/usr/local/bin/Rscript",
        "/usr/bin/Rscript",
        "/Library/Frameworks/R.framework/Resources/bin/Rscript",
    ];

    for path in &r_paths {
        if std::path::Path::new(path).exists() {
            return path.to_string();
        }
    }

    // Fallback to PATH
    "Rscript".to_string()
}

/// Get R library paths for Tidyverse and other packages
fn get_r_lib_paths() -> Vec<String> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/Users".to_string());
    vec![
        format!("{}/Library/R/arm64/4.4/library", home), // macOS ARM
        format!("{}/Library/R/x86_64/4.4/library", home), // macOS Intel
        format!("{}/R/lib", home),
        "/opt/homebrew/lib/R/4.4/site-library".to_string(),
        "/usr/local/lib/R/site-library".to_string(),
        "/Library/Frameworks/R.framework/Versions/4.4-arm64/Resources/library".to_string(),
        "/Library/Frameworks/R.framework/Resources/library".to_string(),
    ]
}

async fn execute_r(code: &str) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("R", code).await?;

    let rscript = find_rscript();
    let lib_paths = get_r_lib_paths();
    let r_libs = lib_paths.join(":");

    let mut child = Command::new(&rscript)
        .arg("--vanilla") // Clean session
        .arg(&temp_file)
        .env("R_LIBS_USER", &r_libs)
        .env("R_LIBS", &r_libs)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| {
            AppError::ExecutionError(format!(
                "Failed to spawn Rscript: {}. Ensure R is installed.",
                e
            ))
        })?;

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    let stdout_reader = BufReader::new(stdout);
    let stderr_reader = BufReader::new(stderr);

    let mut stdout_lines = stdout_reader.lines();
    let mut stderr_lines = stderr_reader.lines();

    let mut stdout_output = String::new();
    let mut stderr_output = String::new();

    while let Ok(Some(line)) = stdout_lines.next_line().await {
        stdout_output.push_str(&line);
        stdout_output.push('\n');
    }

    while let Ok(Some(line)) = stderr_lines.next_line().await {
        stderr_output.push_str(&line);
        stderr_output.push('\n');
    }

    let timeout_duration = std::time::Duration::from_secs(60); // R can be slow with Tidyverse
    let status_result = tokio::time::timeout(timeout_duration, child.wait()).await;

    let status = match status_result {
        Ok(Ok(s)) => s,
        Ok(Err(e)) => {
            return Err(AppError::ExecutionError(format!(
                "Failed to wait for Rscript: {}",
                e
            )))
        }
        Err(_) => {
            let _ = child.kill().await;
            return Err(AppError::ExecutionError(
                "R execution timed out (60s limit)".to_string(),
            ));
        }
    };

    cleanup_temp_file(&temp_file).await;

    Ok(ExecutionResult {
        stdout: stdout_output,
        stderr: stderr_output,
        exit_code: status.code().unwrap_or(-1),
    })
}

/// Streaming execution for R (for Cell Mode)
async fn streaming_execute_r(
    temp_file: &str,
) -> Result<Pin<Box<dyn Stream<Item = std::result::Result<StreamEvent, AppError>> + Send>>> {
    let rscript = find_rscript();
    let lib_paths = get_r_lib_paths();
    let r_libs = lib_paths.join(":");

    let mut child = Command::new(&rscript)
        .arg("--vanilla")
        .arg(temp_file)
        .env("R_LIBS_USER", &r_libs)
        .env("R_LIBS", &r_libs)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .map_err(|e| AppError::ExecutionError(format!("Failed to spawn Rscript: {}", e)))?;

    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| AppError::ExecutionError("Failed to capture stdout".into()))?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| AppError::ExecutionError("Failed to capture stderr".into()))?;

    let stdout_stream = FramedRead::new(stdout, LinesCodec::new()).map(|line| {
        line.map(StreamEvent::Output)
            .map_err(|e| AppError::ExecutionError(e.to_string()))
    });

    let stderr_stream = FramedRead::new(stderr, LinesCodec::new()).map(|line| {
        line.map(StreamEvent::Error)
            .map_err(|e| AppError::ExecutionError(e.to_string()))
    });

    let merged_stream = futures::stream::select(stdout_stream, stderr_stream);

    Ok(Box::pin(ProcessStream {
        stream: merged_stream,
        _child: child,
    }))
}

async fn execute_cpp(code: &str) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("cpp", code).await?;
    let temp_path = std::path::Path::new(&temp_file);
    let output_bin = temp_path.with_extension("bin");

    // Compile
    let mut compile_child = Command::new(find_executable("clang++"))
        .arg(&temp_file)
        .arg("-o")
        .arg(&output_bin)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| AppError::ExecutionError(format!("Failed to spawn clang++: {}", e)))?;

    let compile_status = compile_child
        .wait()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to compile cpp: {}", e)))?;

    if !compile_status.success() {
        let stderr = compile_child.stderr.take().unwrap();
        let stderr_reader = BufReader::new(stderr);
        let mut stderr_lines = stderr_reader.lines();
        let mut stderr_output = String::new();
        while let Ok(Some(line)) = stderr_lines.next_line().await {
            stderr_output.push_str(&line);
            stderr_output.push('\n');
        }
        cleanup_temp_file(&temp_file).await;
        if output_bin.exists() {
            let _ = tokio::fs::remove_file(&output_bin).await;
        }
        return Err(AppError::CompilationError(stderr_output));
    }

    // Execute
    let mut child = Command::new(&output_bin)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| AppError::ExecutionError(format!("Failed to execute cpp program: {}", e)))?;

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    let stdout_reader = BufReader::new(stdout);
    let stderr_reader = BufReader::new(stderr);

    let mut stdout_lines = stdout_reader.lines();
    let mut stderr_lines = stderr_reader.lines();

    let mut stdout_output = String::new();
    let mut stderr_output = String::new();

    while let Ok(Some(line)) = stdout_lines.next_line().await {
        stdout_output.push_str(&line);
        stdout_output.push('\n');
    }

    while let Ok(Some(line)) = stderr_lines.next_line().await {
        stderr_output.push_str(&line);
        stderr_output.push('\n');
    }

    let status = child
        .wait()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to wait for cpp program: {}", e)))?;

    cleanup_temp_file(&temp_file).await;
    let _ = tokio::fs::remove_file(&output_bin).await;

    Ok(ExecutionResult {
        stdout: stdout_output,
        stderr: stderr_output,
        exit_code: status.code().unwrap_or(-1),
    })
}

async fn execute_objc(code: &str) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("m", code).await?;
    let temp_path = std::path::Path::new(&temp_file);
    let output_bin = temp_path.with_extension("bin");

    // Compile
    let mut compile_child = Command::new(find_executable("clang"))
        .arg("-framework")
        .arg("Foundation")
        .arg(&temp_file)
        .arg("-o")
        .arg(&output_bin)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| AppError::ExecutionError(format!("Failed to spawn clang (objc): {}", e)))?;

    let compile_status = compile_child
        .wait()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to compile objc: {}", e)))?;

    if !compile_status.success() {
        let stderr = compile_child.stderr.take().unwrap();
        let stderr_reader = BufReader::new(stderr);
        let mut stderr_lines = stderr_reader.lines();
        let mut stderr_output = String::new();
        while let Ok(Some(line)) = stderr_lines.next_line().await {
            stderr_output.push_str(&line);
            stderr_output.push('\n');
        }
        cleanup_temp_file(&temp_file).await;
        if output_bin.exists() {
            let _ = tokio::fs::remove_file(&output_bin).await;
        }
        return Err(AppError::CompilationError(stderr_output));
    }

    // Execute
    let mut child = Command::new(&output_bin)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| AppError::ExecutionError(format!("Failed to execute objc program: {}", e)))?;

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    let stdout_reader = BufReader::new(stdout);
    let stderr_reader = BufReader::new(stderr);

    let mut stdout_lines = stdout_reader.lines();
    let mut stderr_lines = stderr_reader.lines();

    let mut stdout_output = String::new();
    let mut stderr_output = String::new();

    while let Ok(Some(line)) = stdout_lines.next_line().await {
        stdout_output.push_str(&line);
        stdout_output.push('\n');
    }

    while let Ok(Some(line)) = stderr_lines.next_line().await {
        stderr_output.push_str(&line);
        stderr_output.push('\n');
    }

    let status = child
        .wait()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to wait for objc program: {}", e)))?;

    cleanup_temp_file(&temp_file).await;
    let _ = tokio::fs::remove_file(&output_bin).await;

    Ok(ExecutionResult {
        stdout: stdout_output,
        stderr: stderr_output,
        exit_code: status.code().unwrap_or(-1),
    })
}

// Helper functions

async fn create_temp_file(extension: &str, content: &str) -> Result<String> {
    let temp_dir = std::env::temp_dir();
    let filename = format!(
        "microcode_{}_{}.{}",
        uuid::Uuid::new_v4(),
        chrono::Utc::now().timestamp(),
        extension
    );
    let temp_file = temp_dir.join(filename);

    tokio::fs::write(&temp_file, content)
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to create temp file: {}", e)))?;

    Ok(temp_file.to_string_lossy().to_string())
}

async fn cleanup_temp_file(path: &str) {
    let _ = tokio::fs::remove_file(path).await;
}

async fn cleanup_temp_dir(path: &std::path::Path) {
    let _ = tokio::fs::remove_dir_all(path).await;
}

/// Find an executable in common macOS paths
/// macOS GUI apps don't inherit shell PATH, so we need to search manually
fn find_executable(name: &str) -> String {
    let search_paths = [
        format!("/opt/homebrew/bin/{}", name), // Apple Silicon Homebrew
        format!("/usr/local/bin/{}", name),    // Intel Homebrew
        format!("/usr/local/go/bin/{}", name), // Official Go install
        format!(
            "{}/go/bin/{}",
            std::env::var("HOME").unwrap_or_default(),
            name
        ), // Go user install
        format!("/usr/bin/{}", name),          // System
        format!("/bin/{}", name),              // System
        format!(
            "{}/.cargo/bin/{}",
            std::env::var("HOME").unwrap_or_default(),
            name
        ), // Rust
        format!(
            "{}/.nvm/versions/node/v22.0.0/bin/{}",
            std::env::var("HOME").unwrap_or_default(),
            name
        ), // Common NVM location (example)
        format!(
            "{}/.nvm/versions/node/v20.0.0/bin/{}",
            std::env::var("HOME").unwrap_or_default(),
            name
        ),
        format!(
            "{}/.nvm/versions/node/v18.0.0/bin/{}",
            std::env::var("HOME").unwrap_or_default(),
            name
        ),
        name.to_string(), // Fallback to PATH
    ];

    for path in &search_paths {
        if std::path::Path::new(path).exists() {
            return path.clone();
        }
    }

    // Fallback to just the name (will use PATH if available)
    name.to_string()
}

async fn execute_objcpp(code: &str) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("mm", code).await?;
    let temp_path = std::path::Path::new(&temp_file);
    let output_bin = temp_path.with_extension("bin");

    // Compile
    let mut compile_child = Command::new(find_executable("clang++"))
        .arg("-framework")
        .arg("Foundation")
        .arg(&temp_file)
        .arg("-o")
        .arg(&output_bin)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| {
            AppError::ExecutionError(format!("Failed to spawn clang++ (objcpp): {}", e))
        })?;

    let compile_status = compile_child
        .wait()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to compile objcpp: {}", e)))?;

    if !compile_status.success() {
        let stderr = compile_child.stderr.take().unwrap();
        let stderr_reader = BufReader::new(stderr);
        let mut stderr_lines = stderr_reader.lines();
        let mut stderr_output = String::new();
        while let Ok(Some(line)) = stderr_lines.next_line().await {
            stderr_output.push_str(&line);
            stderr_output.push('\n');
        }
        cleanup_temp_file(&temp_file).await;
        if output_bin.exists() {
            let _ = tokio::fs::remove_file(&output_bin).await;
        }
        return Err(AppError::CompilationError(stderr_output));
    }

    // Execute
    let mut child = Command::new(&output_bin)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| {
            AppError::ExecutionError(format!("Failed to execute objcpp program: {}", e))
        })?;

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    let stdout_reader = BufReader::new(stdout);
    let stderr_reader = BufReader::new(stderr);

    let mut stdout_lines = stdout_reader.lines();
    let mut stderr_lines = stderr_reader.lines();

    let mut stdout_output = String::new();
    let mut stderr_output = String::new();

    while let Ok(Some(line)) = stdout_lines.next_line().await {
        stdout_output.push_str(&line);
        stdout_output.push('\n');
    }

    while let Ok(Some(line)) = stderr_lines.next_line().await {
        stderr_output.push_str(&line);
        stderr_output.push('\n');
    }

    let status = child.wait().await.map_err(|e| {
        AppError::ExecutionError(format!("Failed to wait for objcpp program: {}", e))
    })?;

    cleanup_temp_file(&temp_file).await;
    let _ = tokio::fs::remove_file(&output_bin).await;

    Ok(ExecutionResult {
        stdout: stdout_output,
        stderr: stderr_output,
        exit_code: status.code().unwrap_or(-1),
    })
}

async fn streaming_execute_compilation_lang(
    language: &str,
    temp_file: &str,
) -> Result<Pin<Box<dyn Stream<Item = std::result::Result<StreamEvent, AppError>> + Send>>> {
    let temp_path = std::path::Path::new(temp_file);
    let output_bin = temp_path.with_extension("bin");

    let compiler = match language {
        "objective-c" | "objc" => "clang",
        "objective-cpp" | "objcpp" => "clang++",
        _ => "clang",
    };

    // Compile
    let mut compile_child = Command::new(find_executable(compiler))
        .arg("-framework")
        .arg("Foundation")
        .arg(temp_file)
        .arg("-o")
        .arg(&output_bin)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| {
            AppError::ExecutionError(format!("Failed to spawn {} (compilation): {}", compiler, e))
        })?;

    let compile_status = compile_child
        .wait()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to compile (streaming): {}", e)))?;

    if !compile_status.success() {
        let stderr = compile_child.stderr.take().unwrap();
        let stderr_reader = BufReader::new(stderr);
        let mut stderr_lines = stderr_reader.lines();
        let mut stderr_output = String::new();
        while let Ok(Some(line)) = stderr_lines.next_line().await {
            stderr_output.push_str(&line);
            stderr_output.push('\n');
        }
        cleanup_temp_file(temp_file).await;
        if output_bin.exists() {
            let _ = tokio::fs::remove_file(&output_bin).await;
        }
        return Err(AppError::CompilationError(stderr_output));
    }

    // Execute
    let mut child = Command::new(&output_bin)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| {
            AppError::ExecutionError(format!("Failed to execute compiled program: {}", e))
        })?;

    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| AppError::ExecutionError("Failed to capture stdout".into()))?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| AppError::ExecutionError("Failed to capture stderr".into()))?;

    let stdout_stream = FramedRead::new(stdout, LinesCodec::new()).map(|line| {
        line.map(StreamEvent::Output)
            .map_err(|e| AppError::ExecutionError(e.to_string()))
    });

    let stderr_stream = FramedRead::new(stderr, LinesCodec::new()).map(|line| {
        line.map(StreamEvent::Error)
            .map_err(|e| AppError::ExecutionError(e.to_string()))
    });

    let merged_stream = futures::stream::select(stdout_stream, stderr_stream);

    Ok(Box::pin(ProcessStream {
        stream: merged_stream,
        _child: child,
    }))
}

// ============================================================================
// Additional Language Executors
// ============================================================================

async fn execute_c(code: &str) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("c", code).await?;
    let temp_path = std::path::Path::new(&temp_file);
    let output_bin = temp_path.with_extension("bin");

    let mut compile_child = Command::new(find_executable("clang"))
        .arg(&temp_file)
        .arg("-o")
        .arg(&output_bin)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| AppError::ExecutionError(format!("Failed to spawn clang: {}", e)))?;

    let compile_status = compile_child
        .wait()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to compile C: {}", e)))?;

    if !compile_status.success() {
        let stderr = compile_child.stderr.take().unwrap();
        let stderr_reader = BufReader::new(stderr);
        let mut stderr_lines = stderr_reader.lines();
        let mut stderr_output = String::new();
        while let Ok(Some(line)) = stderr_lines.next_line().await {
            stderr_output.push_str(&line);
            stderr_output.push('\n');
        }
        cleanup_temp_file(&temp_file).await;
        return Err(AppError::CompilationError(stderr_output));
    }

    run_compiled_binary(&output_bin.to_string_lossy(), &temp_file).await
}

async fn execute_java(code: &str) -> Result<ExecutionResult> {
    // Extract class name from code or use default
    let class_name = if code.contains("public class ") {
        code.split("public class ")
            .nth(1)
            .and_then(|s| s.split_whitespace().next())
            .unwrap_or("Main")
    } else {
        "Main"
    };

    let temp_dir = std::env::temp_dir().join(format!("microcode_java_{}", uuid::Uuid::new_v4()));
    tokio::fs::create_dir_all(&temp_dir)
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to create temp dir: {}", e)))?;

    let java_file = temp_dir.join(format!("{}.java", class_name));
    tokio::fs::write(&java_file, code)
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to write java file: {}", e)))?;

    // Compile
    let compile_output = Command::new("javac")
        .arg(&java_file)
        .current_dir(&temp_dir)
        .output()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to run javac: {}", e)))?;

    if !compile_output.status.success() {
        let stderr = String::from_utf8_lossy(&compile_output.stderr);
        cleanup_temp_dir(&temp_dir).await;
        return Err(AppError::CompilationError(stderr.to_string()));
    }

    // Run
    let run_output = Command::new("java")
        .arg(class_name)
        .current_dir(&temp_dir)
        .output()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to run java: {}", e)))?;

    cleanup_temp_dir(&temp_dir).await;

    Ok(ExecutionResult {
        stdout: String::from_utf8_lossy(&run_output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&run_output.stderr).to_string(),
        exit_code: run_output.status.code().unwrap_or(-1),
    })
}

async fn execute_kotlin(code: &str) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("kts", code).await?; // Kotlin script

    let output = Command::new("kotlinc")
        .arg("-script")
        .arg(&temp_file)
        .output()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to run kotlin: {}", e)))?;

    cleanup_temp_file(&temp_file).await;

    Ok(ExecutionResult {
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        exit_code: output.status.code().unwrap_or(-1),
    })
}

async fn execute_lua(code: &str) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("lua", code).await?;

    let output = Command::new(find_executable("lua"))
        .arg(&temp_file)
        .output()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to run lua: {}", e)))?;

    cleanup_temp_file(&temp_file).await;

    Ok(ExecutionResult {
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        exit_code: output.status.code().unwrap_or(-1),
    })
}

async fn execute_perl(code: &str) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("pl", code).await?;

    let output = Command::new(find_executable("perl"))
        .arg(&temp_file)
        .output()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to run perl: {}", e)))?;

    cleanup_temp_file(&temp_file).await;

    Ok(ExecutionResult {
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        exit_code: output.status.code().unwrap_or(-1),
    })
}

async fn execute_php(code: &str) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("php", code).await?;

    let output = Command::new(find_executable("php"))
        .arg(&temp_file)
        .output()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to run php: {}", e)))?;

    cleanup_temp_file(&temp_file).await;

    Ok(ExecutionResult {
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        exit_code: output.status.code().unwrap_or(-1),
    })
}

async fn execute_shell(code: &str) -> Result<ExecutionResult> {
    let temp_file = create_temp_file("sh", code).await?;

    // Make executable
    let _ = Command::new("chmod")
        .arg("+x")
        .arg(&temp_file)
        .output()
        .await;

    let output = Command::new("/bin/bash")
        .arg(&temp_file)
        .output()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to run bash: {}", e)))?;

    cleanup_temp_file(&temp_file).await;

    Ok(ExecutionResult {
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        exit_code: output.status.code().unwrap_or(-1),
    })
}

async fn execute_sql(code: &str) -> Result<ExecutionResult> {
    // Use SQLite for SQL execution
    let temp_file = create_temp_file("sql", code).await?;

    let output = Command::new(find_executable("sqlite3"))
        .arg(":memory:")
        .arg("-init")
        .arg(&temp_file)
        .arg(".quit")
        .output()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to run sqlite3: {}", e)))?;

    cleanup_temp_file(&temp_file).await;

    Ok(ExecutionResult {
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        exit_code: output.status.code().unwrap_or(-1),
    })
}

/// Helper to run a compiled binary and get result
async fn run_compiled_binary(bin_path: &str, source_file: &str) -> Result<ExecutionResult> {
    let output = Command::new(bin_path)
        .output()
        .await
        .map_err(|e| AppError::ExecutionError(format!("Failed to execute: {}", e)))?;

    cleanup_temp_file(source_file).await;
    let _ = tokio::fs::remove_file(bin_path).await;

    Ok(ExecutionResult {
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        exit_code: output.status.code().unwrap_or(-1),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_python_execution() {
        let code = "print('Hello, World!')";
        let result = execute(code, "python").await;
        assert!(result.is_ok());
        let output = result.unwrap();
        assert!(output.stdout.contains("Hello, World!"));
        assert_eq!(output.exit_code, 0);
    }

    #[tokio::test]
    async fn test_javascript_execution() {
        let code = "console.log('Hello, World!');";
        let result = execute(code, "javascript").await;
        assert!(result.is_ok());
        let output = result.unwrap();
        assert!(output.stdout.contains("Hello, World!"));
        assert_eq!(output.exit_code, 0);
    }
}
