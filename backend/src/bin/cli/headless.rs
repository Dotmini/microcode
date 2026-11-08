//! MicroCode CLI — Headless mode (one-shot prompt, CI/CD)

use std::path::Path;
use anyhow::Result;
use tokio::sync::mpsc;

use super::agent_loop::{AgentEvent, run_agent};

/// Run agent in headless mode — prints streaming output to stdout
pub async fn run_headless(
    workspace: &Path,
    prompt: &str,
    provider: &str,
    model: Option<&str>,
) -> Result<()> {
    let model = model.unwrap_or("gemini-2.5-flash");
    let (tx, mut rx) = mpsc::unbounded_channel::<AgentEvent>();
    
    // Spawn agent
    let ws = workspace.to_path_buf();
    let p = prompt.to_string();
    let prov = provider.to_string();
    let mdl = model.to_string();
    
    let agent_handle = tokio::spawn(async move {
        run_agent(&ws, &p, &prov, &mdl, tx).await
    });
    
    // Print events to stdout
    while let Some(event) = rx.recv().await {
        match event {
            AgentEvent::Token(tok) => {
                print!("{}", tok);
            }
            AgentEvent::ToolStart { name, args } => {
                eprintln!("\x1b[33m⚡ {}\x1b[0m {}", name, args);
            }
            AgentEvent::ToolEnd { name, success, duration_ms, .. } => {
                let icon = if success { "\x1b[32m✓\x1b[0m" } else { "\x1b[31m✖\x1b[0m" };
                eprintln!("{} {} ({}ms)", icon, name, duration_ms);
            }
            AgentEvent::Usage { tokens, cost } => {
                eprintln!("\x1b[36m📊 {}tok ${:.4}\x1b[0m", tokens, cost);
            }
            AgentEvent::Complete => {
                println!();
                break;
            }
            AgentEvent::Error(msg) => {
                eprintln!("\x1b[31m✖ Error: {}\x1b[0m", msg);
                break;
            }
            _ => {}
        }
    }
    
    agent_handle.await??;
    Ok(())
}
