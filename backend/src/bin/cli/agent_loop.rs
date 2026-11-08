//! Agent execution loop for the CLI — reuses backend AI + tool modules

use std::path::Path;
use std::time::Instant;

use anyhow::Result;
use tokio::sync::mpsc;
use serde_json::Value;

// ─── Agent Events ───────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub enum AgentEvent {
    /// Streaming token from AI
    Token(String),
    /// Tool execution started
    ToolStart { name: String, args: String },
    /// Tool execution completed
    ToolEnd { name: String, success: bool, output: String, duration_ms: u64 },
    /// Agent iteration number
    Iteration(u32),
    /// Token usage update
    Usage { tokens: u64, cost: f64 },
    /// Agent completed successfully
    Complete,
    /// Agent encountered an error
    Error(String),
}

// ─── Agent Handle ───────────────────────────────────────────────────────────

pub struct AgentHandle {
    tx: mpsc::UnboundedSender<AgentEvent>,
}

impl AgentHandle {
    pub fn new(tx: mpsc::UnboundedSender<AgentEvent>) -> Self {
        Self { tx }
    }
    
    fn emit(&self, event: AgentEvent) {
        let _ = self.tx.send(event);
    }
}

// ─── Agent Loop ─────────────────────────────────────────────────────────────

/// Run the agent loop, emitting events for the TUI to render.
/// This function reuses the backend's AI and tool modules directly.
pub async fn run_agent(
    workspace: &Path,
    prompt: &str,
    provider: &str,
    model: &str,
    tx: mpsc::UnboundedSender<AgentEvent>,
) -> Result<()> {
    let handle = AgentHandle::new(tx);
    let mut iteration: u32 = 0;
    let max_iterations: u32 = 25;
    
    // Build system prompt with workspace context
    let system_prompt = build_system_prompt(workspace).await;
    
    // Initialize message history
    let mut messages: Vec<Value> = vec![
        serde_json::json!({
            "role": "system",
            "content": system_prompt
        }),
        serde_json::json!({
            "role": "user", 
            "content": prompt
        }),
    ];
    
    // Load tool definitions
    let tools = build_tool_definitions();
    
    // Agent loop
    loop {
        iteration += 1;
        if iteration > max_iterations {
            handle.emit(AgentEvent::Error(format!(
                "Reached maximum iterations ({})", max_iterations
            )));
            break;
        }
        
        handle.emit(AgentEvent::Iteration(iteration));
        
        // Call AI provider with streaming
        let api_key = get_api_key(provider);
        let response = call_ai_streaming(
            provider, model, &api_key, &messages, &tools, &handle
        ).await;
        
        match response {
            Ok(ai_response) => {
                // Check if there are tool calls
                if let Some(tool_calls) = ai_response.get("tool_calls").and_then(|v| v.as_array()) {
                    if tool_calls.is_empty() {
                        // No more tool calls — agent is done
                        handle.emit(AgentEvent::Complete);
                        break;
                    }
                    
                    // Add assistant message to history
                    messages.push(ai_response.clone());
                    
                    // Execute each tool call
                    for tool_call in tool_calls {
                        let tool_name = tool_call["name"].as_str().unwrap_or("unknown");
                        let tool_args = tool_call["arguments"].clone();
                        let tool_id = tool_call["id"].as_str().unwrap_or("");
                        
                        handle.emit(AgentEvent::ToolStart {
                            name: tool_name.to_string(),
                            args: truncate_args(&tool_args),
                        });
                        
                        let start = Instant::now();
                        let result = execute_tool(workspace, tool_name, &tool_args).await;
                        let duration = start.elapsed().as_millis() as u64;
                        
                        let (output, success) = match result {
                            Ok(out) => (out, true),
                            Err(e) => (e.to_string(), false),
                        };
                        
                        handle.emit(AgentEvent::ToolEnd {
                            name: tool_name.to_string(),
                            success,
                            output: output.chars().take(500).collect(),
                            duration_ms: duration,
                        });
                        
                        // Add tool result to message history
                        messages.push(serde_json::json!({
                            "role": "tool",
                            "tool_call_id": tool_id,
                            "content": output
                        }));
                    }
                } else {
                    // No tool calls — agent responded with text only
                    handle.emit(AgentEvent::Complete);
                    break;
                }
                
                // Track usage
                if let Some(usage) = ai_response.get("usage") {
                    let tokens = usage["total_tokens"].as_u64().unwrap_or(0);
                    let cost = estimate_cost(provider, model, tokens);
                    handle.emit(AgentEvent::Usage { tokens, cost });
                }
            }
            Err(e) => {
                handle.emit(AgentEvent::Error(format!("AI request failed: {}", e)));
                break;
            }
        }
    }
    
    Ok(())
}

// ─── AI Provider Integration ────────────────────────────────────────────────

async fn call_ai_streaming(
    provider: &str,
    model: &str,
    api_key: &str,
    messages: &[Value],
    tools: &[Value],
    handle: &AgentHandle,
) -> Result<Value> {
    let client = reqwest::Client::new();
    
    let (url, body) = match provider {
        "gemini" => {
            let url = format!(
                "https://generativelanguage.googleapis.com/v1beta/models/{}:streamGenerateContent?key={}&alt=sse",
                model, api_key
            );
            let body = build_gemini_request(messages, tools);
            (url, body)
        }
        "openai" => {
            let url = "https://api.openai.com/v1/chat/completions".to_string();
            let mut body = build_openai_request(model, messages, tools);
            body["stream"] = serde_json::json!(true);
            (url, body)
        }
        "anthropic" => {
            let url = "https://api.anthropic.com/v1/messages".to_string();
            let mut body = build_anthropic_request(model, messages, tools);
            body["stream"] = serde_json::json!(true);
            (url, body)
        }
        _ => {
            anyhow::bail!("Unsupported provider: {}", provider);
        }
    };
    
    let mut request = client.post(&url).json(&body);
    
    match provider {
        "openai" => {
            request = request.header("Authorization", format!("Bearer {}", api_key));
        }
        "anthropic" => {
            request = request
                .header("x-api-key", api_key)
                .header("anthropic-version", "2023-06-01");
        }
        _ => {}
    }
    
    let response = request.send().await?;
    
    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await?;
        anyhow::bail!("API error {}: {}", status, body);
    }
    
    // Parse SSE stream
    let mut full_text = String::new();
    let mut tool_calls: Vec<Value> = Vec::new();
    let mut usage = serde_json::json!({});
    
    let text = response.text().await?;
    for line in text.lines() {
        if let Some(data) = line.strip_prefix("data: ") {
            if data == "[DONE]" { break; }
            if let Ok(chunk) = serde_json::from_str::<Value>(data) {
                // Extract text tokens
                if let Some(token) = extract_token(&chunk, provider) {
                    full_text.push_str(&token);
                    handle.emit(AgentEvent::Token(token));
                }
                // Extract tool calls
                if let Some(calls) = extract_tool_calls(&chunk, provider) {
                    tool_calls.extend(calls);
                }
                // Extract usage
                if let Some(u) = chunk.get("usageMetadata").or_else(|| chunk.get("usage")) {
                    usage = u.clone();
                }
            }
        }
    }
    
    let mut result = serde_json::json!({
        "content": full_text,
        "usage": usage,
    });
    
    if !tool_calls.is_empty() {
        result["tool_calls"] = serde_json::json!(tool_calls);
    }
    
    Ok(result)
}

fn extract_token(chunk: &Value, provider: &str) -> Option<String> {
    match provider {
        "gemini" => {
            chunk.get("candidates")?
                .get(0)?
                .get("content")?
                .get("parts")?
                .get(0)?
                .get("text")?
                .as_str()
                .map(String::from)
        }
        "openai" => {
            chunk.get("choices")?
                .get(0)?
                .get("delta")?
                .get("content")?
                .as_str()
                .map(String::from)
        }
        "anthropic" => {
            chunk.get("delta")?
                .get("text")?
                .as_str()
                .map(String::from)
        }
        _ => None,
    }
}

fn extract_tool_calls(chunk: &Value, provider: &str) -> Option<Vec<Value>> {
    match provider {
        "gemini" => {
            let parts = chunk.get("candidates")?
                .get(0)?
                .get("content")?
                .get("parts")?
                .as_array()?;
            let calls: Vec<Value> = parts.iter()
                .filter_map(|p| p.get("functionCall"))
                .map(|fc| serde_json::json!({
                    "id": uuid::Uuid::new_v4().to_string(),
                    "name": fc["name"],
                    "arguments": fc["args"],
                }))
                .collect();
            if calls.is_empty() { None } else { Some(calls) }
        }
        "openai" => {
            let choices = chunk.get("choices")?.as_array()?;
            let calls: Vec<Value> = choices.iter()
                .filter_map(|c| c.get("delta")?.get("tool_calls")?.as_array())
                .flatten()
                .cloned()
                .collect();
            if calls.is_empty() { None } else { Some(calls) }
        }
        _ => None,
    }
}

// ─── Tool Execution ─────────────────────────────────────────────────────────

async fn execute_tool(workspace: &Path, name: &str, args: &Value) -> Result<String> {
    match name {
        "file_read" => {
            let path = resolve_path(workspace, args["path"].as_str().unwrap_or(""));
            let content = tokio::fs::read_to_string(&path).await?;
            Ok(content)
        }
        "file_write" => {
            let path = resolve_path(workspace, args["path"].as_str().unwrap_or(""));
            let content = args["content"].as_str().unwrap_or("");
            if let Some(parent) = path.parent() {
                tokio::fs::create_dir_all(parent).await?;
            }
            tokio::fs::write(&path, content).await?;
            Ok(format!("✓ Written {} bytes to {}", content.len(), path.display()))
        }
        "replace_in_file" => {
            let path = resolve_path(workspace, args["path"].as_str().unwrap_or(""));
            let old_text = args["old_text"].as_str().unwrap_or("");
            let new_text = args["new_text"].as_str().unwrap_or("");
            let content = tokio::fs::read_to_string(&path).await?;
            
            // Single-occurrence safety (matches Phase 0 fix)
            let count = content.matches(old_text).count();
            if count == 0 {
                anyhow::bail!("Text not found in file");
            } else if count > 1 {
                anyhow::bail!("Found {} occurrences. Add more context for unique match.", count);
            }
            
            let new_content = content.replacen(old_text, new_text, 1);
            tokio::fs::write(&path, &new_content).await?;
            Ok(format!("✓ Replaced in {}", path.display()))
        }
        "grep_search" => {
            let pattern = args["pattern"].as_str().unwrap_or("");
            let path = args["path"].as_str().map(|p| resolve_path(workspace, p));
            let search_dir = path.as_deref().unwrap_or(workspace);
            
            let output = tokio::process::Command::new("grep")
                .args(["-rn", "--include=*.rs", "--include=*.swift", "--include=*.ts", 
                       "--include=*.js", "--include=*.py", "--include=*.go",
                       pattern])
                .current_dir(search_dir)
                .output()
                .await?;
            
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        }
        "shell" => {
            let command = args["command"].as_str().unwrap_or("");
            let timeout = args["timeout"].as_u64().unwrap_or(120);
            
            let output = tokio::time::timeout(
                std::time::Duration::from_secs(timeout),
                tokio::process::Command::new("sh")
                    .args(["-c", command])
                    .current_dir(workspace)
                    .output()
            ).await??;
            
            let stdout = String::from_utf8_lossy(&output.stdout);
            let stderr = String::from_utf8_lossy(&output.stderr);
            
            Ok(format!("{}{}", stdout, if stderr.is_empty() { "".into() } else { format!("\nSTDERR: {}", stderr) }))
        }
        "list_directory_tree" => {
            let path = args["path"].as_str().map(|p| resolve_path(workspace, p));
            let dir = path.as_deref().unwrap_or(workspace);
            let depth = args["depth"].as_u64().unwrap_or(3);
            
            let output = tokio::process::Command::new("find")
                .args([dir.to_str().unwrap_or("."), "-maxdepth", &depth.to_string(), "-type", "f"])
                .output()
                .await?;
            
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        }
        "git_status" => {
            let output = tokio::process::Command::new("git")
                .args(["status", "--porcelain"])
                .current_dir(workspace)
                .output()
                .await?;
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        }
        "git_diff" => {
            let output = tokio::process::Command::new("git")
                .args(["diff", "--stat"])
                .current_dir(workspace)
                .output()
                .await?;
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        }
        _ => {
            Ok(format!("Tool '{}' not yet implemented in CLI mode", name))
        }
    }
}

fn resolve_path(workspace: &Path, path: &str) -> std::path::PathBuf {
    let p = std::path::Path::new(path);
    if p.is_absolute() {
        p.to_path_buf()
    } else {
        workspace.join(path)
    }
}

// ─── Helper Functions ───────────────────────────────────────────────────────

async fn build_system_prompt(workspace: &Path) -> String {
    let mut prompt = String::from(
        "You are MicroCode AI, a powerful coding agent running in terminal mode.\n\
         You have access to tools for reading/writing files, searching code, \n\
         running shell commands, and managing git.\n\n\
         Rules:\n\
         - Always read files before modifying them\n\
         - Use replace_in_file for surgical edits (not file_write for existing files)\n\
         - Run tests after making changes\n\
         - Keep changes minimal and focused\n"
    );
    
    // Add workspace context
    if let Ok(entries) = std::fs::read_dir(workspace) {
        prompt.push_str("\nWorkspace contents:\n");
        for entry in entries.take(30).flatten() {
            prompt.push_str(&format!("  {}\n", entry.file_name().to_string_lossy()));
        }
    }
    
    // Load MICROCODE.md, AGENTS.md, and unified MicroCode rules (~/.microcode/workspaces/<id>/ + repo .microcode/)
    for config_file in ["MICROCODE.md", "AGENTS.md"] {
        let path = workspace.join(config_file);
        if path.exists() {
            if let Ok(content) = std::fs::read_to_string(&path) {
                prompt.push_str(&format!("\n--- {} ---\n{}\n", config_file, content));
            }
        }
    }

    let isolated_dir = microcode_embedded::rules::isolated_workspace_state_dir(workspace);
    let global_dir = microcode_embedded::rules::global_microcode_dir();
    let unified_rule_files = [
        (isolated_dir.join("rules.md"), "~/.microcode/workspaces/rules.md"),
        (isolated_dir.join("agent.md"), "~/.microcode/workspaces/agent.md"),
        (workspace.join(".microcode/rules.md"), ".microcode/rules.md"),
        (workspace.join(".microcode/agent.md"), ".microcode/agent.md"),
        (global_dir.join("rules.md"), "~/.microcode/rules.md"),
    ];
    for (rule_path, label) in unified_rule_files {
        if rule_path.exists() {
            if let Ok(content) = std::fs::read_to_string(&rule_path) {
                if !content.trim().is_empty() {
                    prompt.push_str(&format!("\n--- {} ---\n{}\n", label, content));
                }
            }
        }
    }
    
    prompt
}

fn build_tool_definitions() -> Vec<Value> {
    vec![
        tool_def("file_read", "Read file contents", &[("path", "string", "File path")]),
        tool_def("file_write", "Write content to file", &[("path", "string", "File path"), ("content", "string", "File content")]),
        tool_def("replace_in_file", "Replace text in file (single occurrence)", &[("path", "string", "File path"), ("old_text", "string", "Text to replace"), ("new_text", "string", "Replacement text")]),
        tool_def("grep_search", "Search for pattern in files", &[("pattern", "string", "Search pattern"), ("path", "string", "Directory to search")]),
        tool_def("shell", "Execute shell command", &[("command", "string", "Shell command"), ("timeout", "number", "Timeout in seconds")]),
        tool_def("list_directory_tree", "List directory contents", &[("path", "string", "Directory path"), ("depth", "number", "Max depth")]),
        tool_def("git_status", "Show git status", &[]),
        tool_def("git_diff", "Show git diff", &[]),
    ]
}

fn tool_def(name: &str, desc: &str, params: &[(&str, &str, &str)]) -> Value {
    let mut properties = serde_json::Map::new();
    for (pname, ptype, pdesc) in params {
        properties.insert(pname.to_string(), serde_json::json!({
            "type": ptype,
            "description": pdesc
        }));
    }
    serde_json::json!({
        "type": "function",
        "function": {
            "name": name,
            "description": desc,
            "parameters": {
                "type": "object",
                "properties": properties
            }
        }
    })
}

fn build_gemini_request(messages: &[Value], tools: &[Value]) -> Value {
    let contents: Vec<Value> = messages.iter()
        .filter(|m| m["role"] != "system")
        .map(|m| {
            let role = match m["role"].as_str().unwrap_or("user") {
                "assistant" => "model",
                "tool" => "function",
                other => other,
            };
            serde_json::json!({
                "role": role,
                "parts": [{ "text": m["content"] }]
            })
        })
        .collect();
    
    let function_declarations: Vec<Value> = tools.iter()
        .filter_map(|t| t.get("function").cloned())
        .collect();
    
    serde_json::json!({
        "contents": contents,
        "tools": [{ "functionDeclarations": function_declarations }],
        "systemInstruction": {
            "parts": [{ "text": messages.first().and_then(|m| m["content"].as_str()).unwrap_or("") }]
        }
    })
}

fn build_openai_request(model: &str, messages: &[Value], tools: &[Value]) -> Value {
    serde_json::json!({
        "model": model,
        "messages": messages,
        "tools": tools,
        "temperature": 0.0
    })
}

fn build_anthropic_request(model: &str, messages: &[Value], tools: &[Value]) -> Value {
    let filtered: Vec<Value> = messages.iter()
        .filter(|m| m["role"] != "system")
        .cloned()
        .collect();
    
    serde_json::json!({
        "model": model,
        "messages": filtered,
        "system": messages.first().and_then(|m| m["content"].as_str()).unwrap_or(""),
        "max_tokens": 8192,
        "tools": tools
    })
}

fn get_api_key(provider: &str) -> String {
    match provider {
        "gemini" => std::env::var("GEMINI_API_KEY").unwrap_or_default(),
        "openai" => std::env::var("OPENAI_API_KEY").unwrap_or_default(),
        "anthropic" => std::env::var("ANTHROPIC_API_KEY").unwrap_or_default(),
        _ => String::new(),
    }
}

fn estimate_cost(provider: &str, model: &str, tokens: u64) -> f64 {
    let per_million = match (provider, model) {
        ("gemini", m) if m.contains("flash") => 0.075,
        ("gemini", _) => 1.25,
        ("openai", m) if m.contains("4o-mini") => 0.15,
        ("openai", _) => 2.50,
        ("anthropic", m) if m.contains("haiku") => 0.25,
        ("anthropic", _) => 3.00,
        _ => 0.0,
    };
    (tokens as f64 / 1_000_000.0) * per_million
}

fn truncate_args(args: &Value) -> String {
    let s = args.to_string();
    if s.len() > 80 {
        format!("{}...", &s[..80])
    } else {
        s
    }
}
