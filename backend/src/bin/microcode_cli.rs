//! MicroCode CLI — Terminal-based AI Coding Agent
//! 
//! A Ratatui-powered TUI that reuses the MicroCode backend's AI engine,
//! agent tools, shadow workspace, and policy modules.
//!
//! Usage:
//!   microcode [path]              — Launch interactive TUI in workspace
//!   microcode -p "fix this bug"   — One-shot prompt mode
//!   microcode --inline "query"    — Inline stream mode (no alt-screen)
//!   microcode init                — Initialize .microcode/ config
//!   microcode config              — Manage configuration
//!
//! Architecture:
//!   This binary is part of the MicroCode workspace and depends on
//!   `microcode_embedded` (the backend library crate) for AI, tools,
//!   shadow workspace, and policy enforcement.

use std::io;
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::Result;
use clap::{Parser, Subcommand};
use tokio::sync::mpsc;

mod cli;

// ─── CLI Arguments ──────────────────────────────────────────────────────────

#[derive(Parser, Debug)]
#[command(
    name = "microcode",
    version = env!("CARGO_PKG_VERSION"),
    about = "MicroCode CLI — The Verifiable AI Coding Agent",
    long_about = "Terminal-based AI coding agent with shadow workspace verification.\n\
                  Shares the MicroCode backend engine for multi-provider AI, \n\
                  35+ tools, and the consensus verification pipeline."
)]
struct Args {
    /// Workspace directory (defaults to current directory)
    #[arg(default_value = ".")]
    workspace: PathBuf,

    /// One-shot prompt mode — execute and exit
    #[arg(short, long)]
    prompt: Option<String>,

    /// Full-screen TUI mode (default is inline Claude Code-style)
    #[arg(long)]
    tui: bool,

    /// AI provider to use (gemini, openai, anthropic, local)
    #[arg(long, default_value = "gemini")]
    provider: String,

    /// AI model to use
    #[arg(long)]
    model: Option<String>,

    /// Enable shadow workspace verification
    #[arg(long)]
    verify: bool,

    /// Maximum iterations for agent loop
    #[arg(long, default_value = "25")]
    max_iterations: usize,

    /// Enable verbose logging
    #[arg(short, long)]
    verbose: bool,

    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Initialize MicroCode configuration in current directory
    Init,
    /// Manage configuration
    Config {
        /// Set a configuration value
        #[arg(long)]
        set: Option<String>,
        /// Get a configuration value
        #[arg(long)]
        get: Option<String>,
        /// List all configuration
        #[arg(long)]
        list: bool,
    },
    /// Show cost and token usage report
    Cost,
    /// Compact conversation history
    Compact,
    /// Show git status with AI-generated summaries
    Status,
    /// Run agent in headless mode (CI/CD)
    Run {
        /// Prompt to execute
        prompt: String,
    },
}

// ─── Main Entry Point ───────────────────────────────────────────────────────

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    // Initialize tracing
    if args.verbose {
        tracing_subscriber::fmt()
            .with_env_filter("microcode=debug")
            .init();
    } else {
        tracing_subscriber::fmt()
            .with_env_filter("microcode=info")
            .init();
    }

    // Resolve workspace path
    let workspace = std::fs::canonicalize(&args.workspace)?;
    tracing::info!("Workspace: {}", workspace.display());

    // Load environment from .env files
    load_env(&workspace);

    // Handle subcommands
    match args.command {
        Some(Commands::Init) => {
            cli::config::init_workspace(&workspace)?;
            println!("✓ Initialized .microcode/ in {}", workspace.display());
            return Ok(());
        }
        Some(Commands::Config { set, get, list }) => {
            cli::config::handle_config(&workspace, set, get, list)?;
            return Ok(());
        }
        Some(Commands::Cost) => {
            cli::cost::show_cost_report(&workspace)?;
            return Ok(());
        }
        Some(Commands::Compact) => {
            cli::session::compact_history(&workspace)?;
            println!("✓ History compacted");
            return Ok(());
        }
        Some(Commands::Status) => {
            cli::status::show_status(&workspace).await?;
            return Ok(());
        }
        Some(Commands::Run { prompt }) => {
            return cli::headless::run_headless(&workspace, &prompt, &args.provider, args.model.as_deref()).await;
        }
        None => {}
    }

    // One-shot prompt mode
    if let Some(prompt) = &args.prompt {
        return cli::headless::run_headless(&workspace, prompt, &args.provider, args.model.as_deref()).await;
    }

    // Interactive mode
    if args.tui {
        // Full-screen Ratatui TUI (optional)
        cli::tui::run_tui(&workspace, &args.provider, args.model.as_deref(), args.verify).await
    } else {
        // Default: Claude Code-style inline streaming
        cli::inline::run_interactive(&workspace, &args.provider, args.model.as_deref(), args.verify).await
    }
}

/// Load environment variables from .env files (workspace → home → system)
fn load_env(workspace: &std::path::Path) {
    // Workspace .env
    let ws_env = workspace.join(".env");
    if ws_env.exists() {
        dotenv::from_path(&ws_env).ok();
    }

    // MicroCode config .env
    if let Some(home) = dirs::home_dir() {
        let mc_env = home.join(".microcode").join(".env");
        if mc_env.exists() {
            dotenv::from_path(&mc_env).ok();
        }
    }

    // Backend .env (for shared API keys)
    let backend_env = workspace.join("backend").join(".env");
    if backend_env.exists() {
        dotenv::from_path(&backend_env).ok();
    }
}
