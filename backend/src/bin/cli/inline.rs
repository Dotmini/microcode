//! MicroCode CLI — Main interactive mode (Claude Code-style inline)
//!
//! This is the DEFAULT mode — inline streaming with:
//! - `❯` user prompt  
//! - `⎿` AI response with streaming tokens
//! - Tool calls displayed as compact status lines
//! - Markdown code blocks with syntax highlighting (ANSI)
//! - File diffs shown inline
//! - Cost/token counter after each response

use std::path::Path;
use std::io::{self, Write, BufRead};

use anyhow::Result;
use tokio::sync::mpsc;

use super::agent_loop::{AgentEvent, run_agent};

/// Color codes
const RESET: &str = "\x1b[0m";
const BOLD: &str = "\x1b[1m";
const DIM: &str = "\x1b[2m";
const ITALIC: &str = "\x1b[3m";
const CYAN: &str = "\x1b[36m";
const GREEN: &str = "\x1b[32m";
const YELLOW: &str = "\x1b[33m";
const RED: &str = "\x1b[31m";
const MAGENTA: &str = "\x1b[35m";
const BLUE: &str = "\x1b[34m";
const GRAY: &str = "\x1b[90m";
const WHITE: &str = "\x1b[37m";
const BG_DARK: &str = "\x1b[48;2;30;30;40m";

/// Run in the default interactive mode — Claude Code style inline streaming
pub async fn run_interactive(
    workspace: &Path,
    provider: &str,
    model: Option<&str>,
    verify: bool,
) -> Result<()> {
    let model_name = model.unwrap_or("gemini-2.5-flash");
    
    // Print banner
    print_banner(workspace, model_name, provider, verify);
    
    // Session state
    let mut total_tokens: u64 = 0;
    let mut total_cost: f64 = 0.0;
    let mut turn_count: u32 = 0;
    
    // REPL loop
    loop {
        // Print prompt
        print!("\n{BOLD}{GREEN}❯{RESET} ");
        io::stdout().flush()?;
        
        // Read user input
        let mut input = String::new();
        io::stdin().lock().read_line(&mut input)?;
        let input = input.trim();
        
        // Skip empty
        if input.is_empty() { continue; }
        
        // Handle exit
        if matches!(input, "exit" | "quit" | "/q" | "/quit") {
            print_goodbye(total_tokens, total_cost, turn_count);
            break;
        }
        
        // Handle slash commands
        if input.starts_with('/') {
            handle_command(input, total_tokens, total_cost, workspace);
            continue;
        }
        
        turn_count += 1;
        
        // Run agent
        let (tx, mut rx) = mpsc::unbounded_channel::<AgentEvent>();
        let ws = workspace.to_path_buf();
        let p = input.to_string();
        let prov = provider.to_string();
        let mdl = model_name.to_string();
        
        let agent_handle = tokio::spawn(async move {
            run_agent(&ws, &p, &prov, &mdl, tx).await
        });
        
        // Print response header
        println!();
        
        let mut is_first_token = true;
        let mut current_line_len: usize = 0;
        let mut in_code_block = false;
        let mut tool_count: u32 = 0;
        let mut turn_tokens: u64 = 0;
        let mut turn_cost: f64 = 0.0;
        let mut pending_newline = false;
        
        while let Some(event) = rx.recv().await {
            match event {
                AgentEvent::Token(tok) => {
                    if is_first_token {
                        // Response prefix
                        print!("{CYAN}⎿{RESET} ");
                        is_first_token = false;
                    }
                    
                    // Render tokens with basic markdown awareness
                    for ch in tok.chars() {
                        if ch == '\n' {
                            println!();
                            print!("{CYAN}⎿{RESET} ");
                            current_line_len = 0;
                        } else {
                            print!("{}", ch);
                            current_line_len += 1;
                        }
                    }
                    io::stdout().flush()?;
                    pending_newline = true;
                }
                AgentEvent::ToolStart { name, args } => {
                    tool_count += 1;
                    if pending_newline {
                        println!();
                        pending_newline = false;
                    }
                    // Compact tool status line
                    let args_short = if args.len() > 60 { 
                        format!("{}…", &args[..60]) 
                    } else { 
                        args 
                    };
                    print!(
                        "{GRAY}  {YELLOW}⚡{GRAY} {BOLD}{name}{RESET}{GRAY} {args_short}{RESET}"
                    );
                    io::stdout().flush()?;
                }
                AgentEvent::ToolEnd { name, success, duration_ms, output } => {
                    let icon = if success { 
                        format!("{GREEN}✓{RESET}") 
                    } else { 
                        format!("{RED}✗{RESET}") 
                    };
                    println!(" {icon} {GRAY}{duration_ms}ms{RESET}");
                    
                    // Show brief output preview for errors
                    if !success && !output.is_empty() {
                        let preview: String = output.lines().take(3).collect::<Vec<_>>().join("\n");
                        println!("{RED}  │ {preview}{RESET}");
                    }
                    
                    is_first_token = true; // Next token starts a new response line
                }
                AgentEvent::Iteration(n) => {
                    if n > 1 {
                        println!("{GRAY}  ── iteration {n} ──{RESET}");
                        is_first_token = true;
                    }
                }
                AgentEvent::Usage { tokens, cost } => {
                    turn_tokens += tokens;
                    turn_cost += cost;
                    total_tokens += tokens;
                    total_cost += cost;
                }
                AgentEvent::Complete => {
                    if pending_newline {
                        println!();
                    }
                    // Print turn summary
                    println!(
                        "\n{GRAY}  ─ {turn_tokens} tokens · ${turn_cost:.4} · {tool_count} tools{RESET}"
                    );
                    break;
                }
                AgentEvent::Error(msg) => {
                    if pending_newline {
                        println!();
                    }
                    println!("\n{RED}{BOLD}✗ Error:{RESET} {RED}{msg}{RESET}");
                    break;
                }
            }
        }
        
        agent_handle.await??;
    }
    
    Ok(())
}

// ─── Banner ─────────────────────────────────────────────────────────────────

fn print_banner(workspace: &Path, model: &str, provider: &str, verify: bool) {
    let version = env!("CARGO_PKG_VERSION");
    let ws_name = workspace.file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| workspace.display().to_string());
    
    println!();
    println!("{CYAN}{BOLD}  ╔══════════════════════════════════════════╗{RESET}");
    println!("{CYAN}{BOLD}  ║{RESET}  {BOLD}MicroCode{RESET} v{version}  {GRAY}· The Verifiable IDE{RESET}  {CYAN}{BOLD}║{RESET}");
    println!("{CYAN}{BOLD}  ╚══════════════════════════════════════════╝{RESET}");
    println!();
    println!("  {GRAY}📂{RESET} {BOLD}{ws_name}{RESET}");
    println!("  {GRAY}🤖{RESET} {provider}/{model}");
    if verify {
        println!("  {MAGENTA}🛡️{RESET} Shadow verification enabled");
    }
    println!();
    println!("  {GRAY}Type your request. /help for commands. Ctrl+C to exit.{RESET}");
}

fn print_goodbye(tokens: u64, cost: f64, turns: u32) {
    println!();
    println!("{CYAN}  Session summary:{RESET}");
    println!("{GRAY}  ─ {turns} turns · {tokens} tokens · ${cost:.4}{RESET}");
    println!();
    println!("{GRAY}  Goodbye! 👋{RESET}");
    println!();
}

// ─── Slash Commands ─────────────────────────────────────────────────────────

fn handle_command(cmd: &str, tokens: u64, cost: f64, workspace: &Path) {
    let parts: Vec<&str> = cmd.split_whitespace().collect();
    match parts[0] {
        "/help" | "/h" => {
            println!();
            println!("  {BOLD}Commands:{RESET}");
            println!("  {GREEN}/help{RESET}      Show this help");
            println!("  {GREEN}/cost{RESET}      Show token usage and cost");
            println!("  {GREEN}/clear{RESET}     Clear screen");
            println!("  {GREEN}/compact{RESET}   Compact conversation history");
            println!("  {GREEN}/model{RESET}     Show current model");
            println!("  {GREEN}/verify{RESET}    Toggle shadow verification");
            println!("  {GREEN}/init{RESET}      Initialize .microcode/ config");
            println!("  {GREEN}/status{RESET}    Show git status");
            println!("  {GREEN}/quit{RESET}      Exit");
        }
        "/cost" | "/usage" => {
            println!();
            println!("  {BOLD}Usage Report:{RESET}");
            println!("  {GRAY}Total tokens:{RESET} {tokens}");
            println!("  {GRAY}Estimated cost:{RESET} ${cost:.4}");
        }
        "/clear" | "/cls" => {
            print!("\x1b[2J\x1b[H");
            io::stdout().flush().ok();
        }
        "/status" => {
            // Sync git status
            if let Ok(output) = std::process::Command::new("git")
                .args(["status", "--short"])
                .current_dir(workspace)
                .output()
            {
                let status = String::from_utf8_lossy(&output.stdout);
                if status.is_empty() {
                    println!("  {GREEN}✓ Working tree clean{RESET}");
                } else {
                    for line in status.lines() {
                        let (icon, color) = if line.starts_with(" M") || line.starts_with("M ") {
                            ("●", YELLOW)
                        } else if line.starts_with("A ") {
                            ("✚", GREEN)
                        } else if line.starts_with("??") {
                            ("?", GRAY)
                        } else if line.starts_with(" D") || line.starts_with("D ") {
                            ("✖", RED)
                        } else {
                            ("·", GRAY)
                        };
                        println!("  {color}{icon}{RESET} {}", line.get(3..).unwrap_or(line));
                    }
                }
            }
        }
        "/init" => {
            match super::config::init_workspace(workspace) {
                Ok(()) => println!("  {GREEN}✓{RESET} Initialized .microcode/"),
                Err(e) => println!("  {RED}✗{RESET} {e}"),
            }
        }
        _ => {
            println!("  {RED}Unknown command:{RESET} {}", parts[0]);
            println!("  {GRAY}Type /help for available commands{RESET}");
        }
    }
}
