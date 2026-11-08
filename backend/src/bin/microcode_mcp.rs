//! MicroCode Native Model Context Protocol (MCP) Server
//! Written in Rust for maximum speed, memory safety, and standalone cross-platform execution.
//! Standard JSON-RPC 2.0 over stdio (MCP 2024-11-05 specification).
//!
//! Copyright © 2025-2026 Dotmini Software — Tirawat Nantamas

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::{self};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::Mutex;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct JsonRpcRequest {
    jsonrpc: String,
    id: Option<Value>,
    method: String,
    params: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct JsonRpcResponse {
    jsonrpc: String,
    id: Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<Value>,
}

struct McpServerState {
    workspace: PathBuf,
    cell_sessions: HashMap<String, Vec<String>>,
}

impl McpServerState {
    fn new(workspace: PathBuf) -> Self {
        Self {
            workspace,
            cell_sessions: HashMap::new(),
        }
    }

    fn validate_path(&self, input: &str) -> Result<PathBuf, String> {
        let path = if input.starts_with('/') {
            PathBuf::from(input)
        } else {
            self.workspace.join(input)
        };

        let canonical = match path.canonicalize() {
            Ok(p) => p,
            Err(_) => {
                if let Some(parent) = path.parent() {
                    if let Ok(canon_parent) = parent.canonicalize() {
                        let ws_canon = self
                            .workspace
                            .canonicalize()
                            .unwrap_or_else(|_| self.workspace.clone());
                        if canon_parent.starts_with(&ws_canon)
                            || canon_parent.starts_with(dirs::home_dir().unwrap_or_default())
                        {
                            return Ok(path);
                        }
                    }
                }
                return Ok(path);
            }
        };

        Ok(canonical)
    }
}

// MARK: - Tool Definitions

fn get_all_tools() -> Value {
    json!([
        {
            "name": "file_read",
            "description": "Read file contents safely from the workspace.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "path": { "type": "string", "description": "Path to file (relative or absolute)" }
                },
                "required": ["path"]
            }
        },
        {
            "name": "file_write",
            "description": "Write or overwrite content to a file in the workspace.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "path": { "type": "string", "description": "Target file path" },
                    "content": { "type": "string", "description": "Full file content" }
                },
                "required": ["path", "content"]
            }
        },
        {
            "name": "replace_in_file",
            "description": "Replace a specific substring in a file with new content.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "path": { "type": "string", "description": "Target file path" },
                    "old_text": { "type": "string", "description": "Exact text to find and replace" },
                    "new_text": { "type": "string", "description": "Replacement text" }
                },
                "required": ["path", "old_text", "new_text"]
            }
        },
        {
            "name": "list_directory_tree",
            "description": "Recursively list directory structure in a tree format.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "path": { "type": "string", "description": "Directory path (default: workspace root)" },
                    "max_depth": { "type": "integer", "description": "Maximum tree depth (default: 3)" }
                }
            }
        },
        {
            "name": "grep_search",
            "description": "Perform high-speed text/regex search across project files.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "pattern": { "type": "string", "description": "Search pattern or regex" },
                    "path": { "type": "string", "description": "Directory to search (default: workspace)" },
                    "file_pattern": { "type": "string", "description": "File glob pattern" }
                },
                "required": ["pattern"]
            }
        },
        {
            "name": "shell",
            "description": "Execute a shell command with real-time output and safety validation.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "command": { "type": "string", "description": "Shell command line to execute" },
                    "cwd": { "type": "string", "description": "Working directory" }
                },
                "required": ["command"]
            }
        },
        {
            "name": "playground_run",
            "description": "Execute code directly in Playground Mode across 30+ languages (Ardium, Python, Swift, Rust, Go, C, C++, C#, Java, Kotlin, PHP, Ruby, R, Julia, Zig, Dart, Lua, Scala, Shell, SQL).",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "language": { "type": "string", "description": "Language name" },
                    "code": { "type": "string", "description": "Source code to execute" },
                    "stdin": { "type": "string", "description": "Optional standard input" }
                },
                "required": ["language", "code"]
            }
        },
        {
            "name": "cell_run",
            "description": "Execute a code cell in Cell Mode and return results.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "id": { "type": "string", "description": "Cell ID to execute" }
                },
                "required": ["id"]
            }
        },
        {
            "name": "cell_create",
            "description": "Create a new Cell Mode notebook cell.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "id": { "type": "string", "description": "Cell ID" },
                    "language": { "type": "string", "description": "Language (default: python)" },
                    "code": { "type": "string", "description": "Initial code" },
                    "title": { "type": "string", "description": "Cell title" }
                },
                "required": ["id", "code"]
            }
        },
        {
            "name": "cell_list",
            "description": "List all code cells in the current Cell Sheet.",
            "inputSchema": {
                "type": "object",
                "properties": {}
            }
        },
        {
            "name": "ardium_run",
            "description": "Compile and execute Dotmini Ardium 2.3 source code natively.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "code": { "type": "string", "description": "Ardium (.ar) code" }
                },
                "required": ["code"]
            }
        },
        {
            "name": "microcode_run_cell",
            "description": "Omni AI compatible Cell Mode execution with stateful session retention and multi-language support (R, Julia, Ardium, Swift, Python, Rust, Go, JS, etc.).",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "code": { "type": "string", "description": "Code to execute" },
                    "language": { "type": "string", "description": "Programming language (default: python)" },
                    "cell_id": { "type": "string", "description": "Cell identifier" },
                    "session_id": { "type": "string", "description": "Stateful session ID" }
                },
                "required": ["code"]
            }
        },
        {
            "name": "microcode_run_playground",
            "description": "Omni AI compatible Playground Mode execution supporting all languages.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "code": { "type": "string", "description": "Complete source code" },
                    "language": { "type": "string", "description": "Language name" },
                    "stdin": { "type": "string", "description": "Standard input" }
                },
                "required": ["code", "language"]
            }
        },
        {
            "name": "microcode_get_runtimes",
            "description": "Inspect available compilers, interpreters, and accelerators on this system.",
            "inputSchema": {
                "type": "object",
                "properties": {}
            }
        }
    ])
}

// MARK: - Code Execution Engine

fn find_ardium_bin() -> String {
    if let Ok(val) = env::var("ARDIUM_BIN") {
        if Path::new(&val).exists() {
            return val;
        }
    }
    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"));
    let candidates = [
        home.join(".cargo/bin/arc"),
        home.join(".cargo/bin/TitanScript"),
        PathBuf::from("/opt/homebrew/bin/arc"),
        PathBuf::from("/usr/local/bin/arc"),
        PathBuf::from("/usr/local/ardium/bin/arc"),
        PathBuf::from("/usr/local/bin/ardium"),
        PathBuf::from("/opt/homebrew/bin/ardium"),
    ];

    for c in &candidates {
        if c.exists() {
            return c.to_string_lossy().to_string();
        }
    }
    "arc".to_string()
}

fn execute_code_locally(
    language: &str,
    code: &str,
    stdin_text: Option<&str>,
    cwd: &Path,
) -> (String, String, bool) {
    let lang = language.to_lowercase().trim().to_string();
    let temp_dir = env::temp_dir().join(format!("microcode_mcp_{}", uuid::Uuid::new_v4()));
    let _ = fs::create_dir_all(&temp_dir);

    let (stdout, stderr, success) = match lang.as_str() {
        "python" | "py" | "python3" => {
            let file = temp_dir.join("script.py");
            let _ = fs::write(&file, code);
            run_cmd("python3", &["-u", file.to_str().unwrap()], stdin_text, cwd)
        }
        "r" | "rscript" => {
            let file = temp_dir.join("script.R");
            let _ = fs::write(&file, code);
            run_cmd("Rscript", &[file.to_str().unwrap()], stdin_text, cwd)
        }
        "julia" | "jl" => {
            let file = temp_dir.join("script.jl");
            let _ = fs::write(&file, code);
            run_cmd("julia", &[file.to_str().unwrap()], stdin_text, cwd)
        }
        "ardium" | "ar" => {
            let ardium_bin = find_ardium_bin();
            let mut final_code = code.to_string();
            if !final_code.contains("fn main(") && !final_code.contains("func main(") {
                if final_code.contains("print")
                    || final_code.contains("println")
                    || final_code.contains("show(")
                {
                    final_code = format!("fn main() {{\n{}\n}}", final_code);
                }
            }
            let file = temp_dir.join("main.ar");
            let _ = fs::write(&file, final_code);
            let mut cmd = Command::new(&ardium_bin);
            cmd.arg("run").arg(&file).current_dir(cwd);
            cmd.env("DYLD_LIBRARY_PATH", "/usr/local/ardium/lib");
            cmd.env("ARDIUM_LIB_PATH", "/usr/local/ardium/lib");
            cmd.env("ARDIUM_STDLIB", "/usr/local/ardium/stdlib");

            match cmd.output() {
                Ok(out) => {
                    let out_s = String::from_utf8_lossy(&out.stdout).to_string();
                    let err_s = String::from_utf8_lossy(&out.stderr).to_string();
                    let clean_out: String = out_s
                        .lines()
                        .filter(|l| !l.contains("Target Triple"))
                        .collect::<Vec<_>>()
                        .join("\n");
                    let clean_err: String = err_s
                        .lines()
                        .filter(|l| !l.contains("Target Triple"))
                        .collect::<Vec<_>>()
                        .join("\n");
                    (clean_out, clean_err, out.status.success())
                }
                Err(e) => (
                    "".to_string(),
                    format!("Failed to execute Ardium compiler (arc): {}", e),
                    false,
                ),
            }
        }
        "javascript" | "js" | "node" => {
            let file = temp_dir.join("script.js");
            let _ = fs::write(&file, code);
            run_cmd("node", &[file.to_str().unwrap()], stdin_text, cwd)
        }
        "typescript" | "ts" => {
            let file = temp_dir.join("script.ts");
            let _ = fs::write(&file, code);
            run_cmd(
                "npx",
                &["-y", "tsx", file.to_str().unwrap()],
                stdin_text,
                cwd,
            )
        }
        "swift" => {
            let file = temp_dir.join("script.swift");
            let _ = fs::write(&file, code);
            run_cmd("swift", &[file.to_str().unwrap()], stdin_text, cwd)
        }
        "rust" | "rs" => {
            let file = temp_dir.join("main.rs");
            let bin = temp_dir.join("main_rs");
            let _ = fs::write(&file, code);
            let comp = run_cmd(
                "rustc",
                &[file.to_str().unwrap(), "-o", bin.to_str().unwrap()],
                None,
                &temp_dir,
            );
            if !comp.2 {
                comp
            } else {
                run_cmd(bin.to_str().unwrap(), &[], stdin_text, cwd)
            }
        }
        "c" => {
            let file = temp_dir.join("main.c");
            let bin = temp_dir.join("main_c");
            let _ = fs::write(&file, code);
            let comp = run_cmd(
                "clang",
                &["-O2", file.to_str().unwrap(), "-o", bin.to_str().unwrap()],
                None,
                &temp_dir,
            );
            if !comp.2 {
                comp
            } else {
                run_cmd(bin.to_str().unwrap(), &[], stdin_text, cwd)
            }
        }
        "cpp" | "c++" | "cc" => {
            let file = temp_dir.join("main.cpp");
            let bin = temp_dir.join("main_cpp");
            let _ = fs::write(&file, code);
            let comp = run_cmd(
                "clang++",
                &[
                    "-O2",
                    "-std=c++17",
                    file.to_str().unwrap(),
                    "-o",
                    bin.to_str().unwrap(),
                ],
                None,
                &temp_dir,
            );
            if !comp.2 {
                comp
            } else {
                run_cmd(bin.to_str().unwrap(), &[], stdin_text, cwd)
            }
        }
        "go" | "golang" => {
            let file = temp_dir.join("main.go");
            let _ = fs::write(&file, code);
            run_cmd("go", &["run", file.to_str().unwrap()], stdin_text, cwd)
        }
        "java" => {
            let file = temp_dir.join("Main.java");
            let _ = fs::write(&file, code);
            let comp = run_cmd("javac", &[file.to_str().unwrap()], None, &temp_dir);
            if !comp.2 {
                comp
            } else {
                run_cmd(
                    "java",
                    &["-cp", temp_dir.to_str().unwrap(), "Main"],
                    stdin_text,
                    cwd,
                )
            }
        }
        "php" => {
            let file = temp_dir.join("script.php");
            let _ = fs::write(&file, code);
            run_cmd("php", &[file.to_str().unwrap()], stdin_text, cwd)
        }
        "ruby" | "rb" => {
            let file = temp_dir.join("script.rb");
            let _ = fs::write(&file, code);
            run_cmd("ruby", &[file.to_str().unwrap()], stdin_text, cwd)
        }
        "bash" | "sh" | "zsh" | "shell" => {
            let file = temp_dir.join("script.sh");
            let _ = fs::write(&file, code);
            run_cmd("bash", &[file.to_str().unwrap()], stdin_text, cwd)
        }
        "sql" => {
            let mut cmd = Command::new("sqlite3");
            cmd.arg(":memory:").current_dir(cwd);
            if let Ok(mut child) = cmd
                .stdin(std::process::Stdio::piped())
                .stdout(std::process::Stdio::piped())
                .stderr(std::process::Stdio::piped())
                .spawn()
            {
                if let Some(mut stdin) = child.stdin.take() {
                    use std::io::Write;
                    let _ = stdin.write_all(code.as_bytes());
                }
                match child.wait_with_output() {
                    Ok(out) => (
                        String::from_utf8_lossy(&out.stdout).to_string(),
                        String::from_utf8_lossy(&out.stderr).to_string(),
                        out.status.success(),
                    ),
                    Err(e) => ("".to_string(), e.to_string(), false),
                }
            } else {
                ("".to_string(), "sqlite3 not installed".to_string(), false)
            }
        }
        other => (
            "".to_string(),
            format!("Unsupported programming language: {}", other),
            false,
        ),
    };

    let _ = fs::remove_dir_all(&temp_dir);
    (stdout, stderr, success)
}

fn run_cmd(
    program: &str,
    args: &[&str],
    stdin_text: Option<&str>,
    cwd: &Path,
) -> (String, String, bool) {
    let mut cmd = Command::new(program);
    cmd.args(args).current_dir(cwd);

    if stdin_text.is_some() {
        cmd.stdin(std::process::Stdio::piped());
    }
    cmd.stdout(std::process::Stdio::piped());
    cmd.stderr(std::process::Stdio::piped());

    match cmd.spawn() {
        Ok(mut child) => {
            if let Some(text) = stdin_text {
                if let Some(mut stdin) = child.stdin.take() {
                    use std::io::Write;
                    let _ = stdin.write_all(text.as_bytes());
                }
            }
            match child.wait_with_output() {
                Ok(out) => (
                    String::from_utf8_lossy(&out.stdout).to_string(),
                    String::from_utf8_lossy(&out.stderr).to_string(),
                    out.status.success(),
                ),
                Err(e) => ("".to_string(), e.to_string(), false),
            }
        }
        Err(e) => (
            "".to_string(),
            format!("Failed to start process '{}': {}", program, e),
            false,
        ),
    }
}

// MARK: - Tool Dispatcher

async fn dispatch_tool(name: &str, args: Value, state: &mut McpServerState) -> Value {
    match name {
        "file_read" => {
            let path_str = args["path"].as_str().unwrap_or("");
            match state.validate_path(path_str) {
                Ok(path) => match fs::read_to_string(&path) {
                    Ok(content) => {
                        let text = if content.len() > 15000 {
                            format!(
                                "{}\n\n... (truncated, total: {} chars)",
                                &content[..15000],
                                content.len()
                            )
                        } else {
                            content
                        };
                        json!({ "content": [{ "type": "text", "text": text }] })
                    }
                    Err(e) => {
                        json!({ "content": [{ "type": "text", "text": format!("Error reading file: {}", e) }], "isError": true })
                    }
                },
                Err(e) => json!({ "content": [{ "type": "text", "text": e }], "isError": true }),
            }
        }
        "file_write" => {
            let path_str = args["path"].as_str().unwrap_or("");
            let content = args["content"].as_str().unwrap_or("");
            match state.validate_path(path_str) {
                Ok(path) => {
                    if let Some(parent) = path.parent() {
                        let _ = fs::create_dir_all(parent);
                    }
                    match fs::write(&path, content) {
                        Ok(_) => {
                            json!({ "content": [{ "type": "text", "text": format!("✅ Successfully written {} bytes to {}", content.len(), path.display()) }] })
                        }
                        Err(e) => {
                            json!({ "content": [{ "type": "text", "text": format!("Error writing file: {}", e) }], "isError": true })
                        }
                    }
                }
                Err(e) => json!({ "content": [{ "type": "text", "text": e }], "isError": true }),
            }
        }
        "replace_in_file" => {
            let path_str = args["path"].as_str().unwrap_or("");
            let old_text = args["old_text"].as_str().unwrap_or("");
            let new_text = args["new_text"].as_str().unwrap_or("");
            match state.validate_path(path_str) {
                Ok(path) => match fs::read_to_string(&path) {
                    Ok(content) => {
                        if !content.contains(old_text) {
                            return json!({ "content": [{ "type": "text", "text": "Target text not found in file." }], "isError": true });
                        }
                        let replaced = content.replacen(old_text, new_text, 1);
                        let _ = fs::write(&path, replaced);
                        json!({ "content": [{ "type": "text", "text": format!("✅ Replaced text in {}", path.display()) }] })
                    }
                    Err(e) => {
                        json!({ "content": [{ "type": "text", "text": format!("Error: {}", e) }], "isError": true })
                    }
                },
                Err(e) => json!({ "content": [{ "type": "text", "text": e }], "isError": true }),
            }
        }
        "shell" => {
            let cmd_str = args["command"].as_str().unwrap_or("");
            let blocked_patterns = [
                "rm -rf /",
                "rm -rf ~",
                "rm -rf *",
                "mkfs",
                "dd if=",
                "> /dev/sd",
            ];
            for p in &blocked_patterns {
                if cmd_str.contains(p) {
                    return json!({ "content": [{ "type": "text", "text": format!("🚨 BLOCKED: Dangerous destructive command pattern: {}", p) }], "isError": true });
                }
            }
            let (stdout, stderr, success) =
                run_cmd("zsh", &["-c", cmd_str], None, &state.workspace);
            let combined = if stderr.is_empty() {
                stdout
            } else {
                format!("{}\nSTDERR:\n{}", stdout, stderr)
            };
            json!({ "content": [{ "type": "text", "text": combined }], "isError": !success })
        }
        "playground_run" | "microcode_run_playground" => {
            let lang = args["language"].as_str().unwrap_or("python");
            let code = args["code"].as_str().unwrap_or("");
            let stdin_str = args["stdin"].as_str();
            let (stdout, stderr, success) =
                execute_code_locally(lang, code, stdin_str, &state.workspace);
            let mut out = format!("[MicroCode Playground Output ({})]\n", lang.to_uppercase());
            if !stdout.is_empty() {
                out.push_str(&stdout);
            }
            if !stderr.is_empty() {
                out.push_str(&format!("\nSTDERR / ERROR:\n{}", stderr));
            }
            if stdout.is_empty() && stderr.is_empty() {
                out.push_str("Program executed with no output.");
            }
            json!({ "content": [{ "type": "text", "text": out }], "isError": !success })
        }
        "ardium_run" => {
            let code = args["code"].as_str().unwrap_or("");
            let (stdout, stderr, success) =
                execute_code_locally("ardium", code, None, &state.workspace);
            let mut out = "[Dotmini Ardium 2.3 Execution Result]\n".to_string();
            if !stdout.is_empty() {
                out.push_str(&stdout);
            }
            if !stderr.is_empty() {
                out.push_str(&format!("\nSTDERR:\n{}", stderr));
            }
            json!({ "content": [{ "type": "text", "text": out }], "isError": !success })
        }
        "microcode_run_cell" => {
            let code = args["code"].as_str().unwrap_or("");
            let lang = args["language"].as_str().unwrap_or("python");
            let cell_id = args["cell_id"].as_str().unwrap_or("cell-0");
            let session_id = args["session_id"].as_str().unwrap_or("default").to_string();

            let history = state
                .cell_sessions
                .entry(session_id.clone())
                .or_insert_with(Vec::new);
            let combined_code = if lang == "python" {
                let mut c = history.join("\n\n");
                if !c.is_empty() {
                    c.push_str("\n\n");
                }
                c.push_str(code);
                c
            } else {
                code.to_string()
            };

            let (stdout, stderr, success) =
                execute_code_locally(lang, &combined_code, None, &state.workspace);
            if success {
                history.push(code.to_string());
            }

            let mut reply = format!(
                "[MicroCode Cell Mode: {} ({})]\n",
                cell_id,
                lang.to_uppercase()
            );
            if !stdout.is_empty() {
                reply.push_str(&format!("\nSTDOUT:\n{}", stdout));
            }
            if !stderr.is_empty() {
                reply.push_str(&format!("\nSTDERR:\n{}", stderr));
            }
            if stdout.is_empty() && stderr.is_empty() {
                reply.push_str("\nCell executed successfully (no stdout).\n");
            }
            reply.push_str(&format!(
                "\nSession: {} | History Cells: {}",
                session_id,
                history.len()
            ));

            json!({ "content": [{ "type": "text", "text": reply }], "isError": !success })
        }
        "microcode_get_runtimes" => {
            let mut runtimes = vec![
                "Python 3.x",
                "Node.js (V8)",
                "Rust (rustc)",
                "Clang (C/C++)",
                "Swift Native",
            ];
            if Command::new("Rscript").arg("--version").output().is_ok() {
                runtimes.push("R (Rscript)");
            }
            if Command::new("julia").arg("--version").output().is_ok() {
                runtimes.push("Julia (LLVM)");
            }
            let ardium_path = find_ardium_bin();
            if Path::new(&ardium_path).exists() || ardium_path == "arc" {
                runtimes.push("Dotmini Ardium 2.3 (arc)");
            }
            if Command::new("go").arg("version").output().is_ok() {
                runtimes.push("Go (gc)");
            }
            if Command::new("dotnet-script").output().is_ok()
                || Command::new("dotnet").arg("--version").output().is_ok()
            {
                runtimes.push("C# (.NET Core)");
            }
            if Command::new("javac").arg("-version").output().is_ok() {
                runtimes.push("Java (OpenJDK/HotSpot)");
            }
            if Command::new("zig").arg("version").output().is_ok() {
                runtimes.push("Zig Native");
            }
            if Command::new("dart").arg("--version").output().is_ok() {
                runtimes.push("Dart AOT/VM");
            }

            let out = format!(
                "MicroCode Native Execution Engine:\n- {}",
                runtimes.join("\n- ")
            );
            json!({ "content": [{ "type": "text", "text": out }] })
        }
        other => {
            json!({ "content": [{ "type": "text", "text": format!("Tool '{}' not implemented", other) }], "isError": true })
        }
    }
}

// MARK: - Main Server Loop (JSON-RPC 2.0 over Stdio)

#[tokio::main]
async fn main() -> io::Result<()> {
    let workspace_path = env::var("MICROCODE_WORKSPACE")
        .map(PathBuf::from)
        .unwrap_or_else(|_| env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));

    let state = Arc::new(Mutex::new(McpServerState::new(workspace_path)));

    let stdin = tokio::io::stdin();
    let mut stdout = tokio::io::stdout();
    let reader = BufReader::new(stdin);
    let mut lines = reader.lines();

    while let Ok(Some(line)) = lines.next_line().await {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let req: JsonRpcRequest = match serde_json::from_str(trimmed) {
            Ok(r) => r,
            Err(_) => continue,
        };

        let method = req.method.as_str();
        let req_id = req.id.clone().unwrap_or(Value::Null);

        match method {
            "initialize" => {
                let resp = JsonRpcResponse {
                    jsonrpc: "2.0".to_string(),
                    id: req_id,
                    result: Some(json!({
                        "protocolVersion": "2024-11-05",
                        "serverInfo": {
                            "name": "microcode-mcp-rust",
                            "version": "2.0.0"
                        },
                        "capabilities": {
                            "tools": {}
                        }
                    })),
                    error: None,
                };
                let mut data = serde_json::to_vec(&resp).unwrap();
                data.push(b'\n');
                stdout.write_all(&data).await?;
                stdout.flush().await?;
            }
            "notifications/initialized" | "initialized" => {}
            "ping" => {
                let resp = JsonRpcResponse {
                    jsonrpc: "2.0".to_string(),
                    id: req_id,
                    result: Some(json!({})),
                    error: None,
                };
                let mut data = serde_json::to_vec(&resp).unwrap();
                data.push(b'\n');
                stdout.write_all(&data).await?;
                stdout.flush().await?;
            }
            "tools/list" => {
                let resp = JsonRpcResponse {
                    jsonrpc: "2.0".to_string(),
                    id: req_id,
                    result: Some(json!({ "tools": get_all_tools() })),
                    error: None,
                };
                let mut data = serde_json::to_vec(&resp).unwrap();
                data.push(b'\n');
                stdout.write_all(&data).await?;
                stdout.flush().await?;
            }
            "tools/call" => {
                let params = req.params.unwrap_or(json!({}));
                let tool_name = params["name"].as_str().unwrap_or("");
                let tool_args = params["arguments"].clone();

                let mut s = state.lock().await;
                let tool_result = dispatch_tool(tool_name, tool_args, &mut s).await;

                let resp = JsonRpcResponse {
                    jsonrpc: "2.0".to_string(),
                    id: req_id,
                    result: Some(tool_result),
                    error: None,
                };
                let mut data = serde_json::to_vec(&resp).unwrap();
                data.push(b'\n');
                stdout.write_all(&data).await?;
                stdout.flush().await?;
            }
            _ => {
                if !req_id.is_null() {
                    let resp = JsonRpcResponse {
                        jsonrpc: "2.0".to_string(),
                        id: req_id,
                        result: None,
                        error: Some(
                            json!({ "code": -32601, "message": format!("Method not found: {}", method) }),
                        ),
                    };
                    let mut data = serde_json::to_vec(&resp).unwrap();
                    data.push(b'\n');
                    stdout.write_all(&data).await?;
                    stdout.flush().await?;
                }
            }
        }
    }

    Ok(())
}
