//! MicroCode CLI — Interactive TUI (Alt-screen mode)
//!
//! Ratatui-powered terminal interface with:
//! - Chat panel (user messages + AI streaming)
//! - Tool execution panel (live tool calls)
//! - File diff viewer (inline unified diffs)
//! - Status bar (tokens, cost, model, iteration)

use std::path::Path;
use std::io::{self, Stdout};
use std::time::{Duration, Instant};

use anyhow::Result;
use crossterm::{
    event::{self, Event, KeyCode, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span, Text},
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap, Scrollbar, ScrollbarOrientation, ScrollbarState},
    Frame, Terminal,
};
use tokio::sync::mpsc;

use super::agent_loop::{AgentEvent, AgentHandle};
use super::theme::Theme;

// ─── App State ──────────────────────────────────────────────────────────────

struct App {
    /// User input buffer
    input: String,
    /// Cursor position in input
    cursor: usize,
    /// Chat messages (role, content)
    messages: Vec<(String, String)>,
    /// Current streaming buffer
    stream_buffer: String,
    /// Tool call log
    tool_log: Vec<ToolLogEntry>,
    /// Is agent currently running?
    agent_running: bool,
    /// Chat scroll offset
    chat_scroll: u16,
    /// Total tokens used
    total_tokens: u64,
    /// Estimated cost (USD)
    total_cost: f64,
    /// Current model name
    model: String,
    /// Current iteration
    iteration: u32,
    /// Active panel focus
    focus: PanelFocus,
    /// Theme colors
    theme: Theme,
    /// Should quit
    should_quit: bool,
    /// Workspace path
    workspace: String,
    /// Shadow verification enabled
    verify_mode: bool,
    /// Input history for up/down arrow
    input_history: Vec<String>,
    history_index: Option<usize>,
}

#[derive(Debug, Clone, PartialEq)]
enum PanelFocus {
    Input,
    Chat,
    Tools,
}

#[derive(Debug, Clone)]
struct ToolLogEntry {
    name: String,
    args_summary: String,
    status: ToolStatus,
    duration_ms: u64,
    output_preview: String,
}

#[derive(Debug, Clone, PartialEq)]
enum ToolStatus {
    Running,
    Success,
    Error,
}

impl App {
    fn new(workspace: &str, model: &str, verify: bool) -> Self {
        Self {
            input: String::new(),
            cursor: 0,
            messages: vec![
                ("system".into(), format!(
                    "🔮 MicroCode CLI v{} — The Verifiable AI Coding Agent\n\
                     📂 Workspace: {}\n\
                     🤖 Model: {}\n\
                     {}\n\
                     Type your request or /help for commands.",
                    env!("CARGO_PKG_VERSION"),
                    workspace,
                    model,
                    if verify { "🛡️ Shadow Verification: ON" } else { "" }
                )),
            ],
            stream_buffer: String::new(),
            tool_log: Vec::new(),
            agent_running: false,
            chat_scroll: 0,
            total_tokens: 0,
            total_cost: 0.0,
            model: model.to_string(),
            iteration: 0,
            focus: PanelFocus::Input,
            theme: Theme::default(),
            should_quit: false,
            workspace: workspace.to_string(),
            verify_mode: verify,
            input_history: Vec::new(),
            history_index: None,
        }
    }
}

// ─── TUI Entry Point ────────────────────────────────────────────────────────

pub async fn run_tui(
    workspace: &Path,
    provider: &str,
    model: Option<&str>,
    verify: bool,
) -> Result<()> {
    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let model_name = model.unwrap_or("gemini-2.5-flash");
    let mut app = App::new(
        &workspace.display().to_string(),
        model_name,
        verify,
    );

    // Agent communication channel
    let (event_tx, mut event_rx) = mpsc::unbounded_channel::<AgentEvent>();

    // Main event loop
    let tick_rate = Duration::from_millis(16); // ~60 FPS
    let mut last_tick = Instant::now();

    loop {
        // Draw UI
        terminal.draw(|f| draw_ui(f, &app))?;

        // Poll for events
        let timeout = tick_rate.saturating_sub(last_tick.elapsed());
        if event::poll(timeout)? {
            if let Event::Key(key) = event::read()? {
                match key.code {
                    // Quit
                    KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                        app.should_quit = true;
                    }
                    KeyCode::Char('d') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                        app.should_quit = true;
                    }
                    // Submit input
                    KeyCode::Enter if !app.input.is_empty() && !app.agent_running => {
                        let input = app.input.clone();
                        app.input_history.push(input.clone());
                        app.history_index = None;
                        
                        // Handle slash commands
                        if input.starts_with('/') {
                            handle_slash_command(&mut app, &input);
                        } else {
                            app.messages.push(("user".into(), input.clone()));
                            app.input.clear();
                            app.cursor = 0;
                            app.agent_running = true;
                            app.stream_buffer.clear();
                            
                            // Spawn agent task
                            let tx = event_tx.clone();
                            let ws = workspace.to_path_buf();
                            let prov = provider.to_string();
                            let mdl = model_name.to_string();
                            tokio::spawn(async move {
                                if let Err(e) = super::agent_loop::run_agent(
                                    &ws, &input, &prov, &mdl, tx
                                ).await {
                                    tracing::error!("Agent error: {}", e);
                                }
                            });
                        }
                    }
                    // Text input
                    KeyCode::Char(c) if app.focus == PanelFocus::Input => {
                        app.input.insert(app.cursor, c);
                        app.cursor += 1;
                    }
                    KeyCode::Backspace if app.cursor > 0 => {
                        app.cursor -= 1;
                        app.input.remove(app.cursor);
                    }
                    KeyCode::Left if app.cursor > 0 => app.cursor -= 1,
                    KeyCode::Right if app.cursor < app.input.len() => app.cursor += 1,
                    KeyCode::Home => app.cursor = 0,
                    KeyCode::End => app.cursor = app.input.len(),
                    // History navigation
                    KeyCode::Up => {
                        if !app.input_history.is_empty() {
                            let idx = match app.history_index {
                                Some(i) if i > 0 => i - 1,
                                Some(i) => i,
                                None => app.input_history.len() - 1,
                            };
                            app.history_index = Some(idx);
                            app.input = app.input_history[idx].clone();
                            app.cursor = app.input.len();
                        }
                    }
                    KeyCode::Down => {
                        if let Some(idx) = app.history_index {
                            if idx + 1 < app.input_history.len() {
                                let new_idx = idx + 1;
                                app.history_index = Some(new_idx);
                                app.input = app.input_history[new_idx].clone();
                                app.cursor = app.input.len();
                            } else {
                                app.history_index = None;
                                app.input.clear();
                                app.cursor = 0;
                            }
                        }
                    }
                    // Scroll chat
                    KeyCode::PageUp => {
                        app.chat_scroll = app.chat_scroll.saturating_add(5);
                    }
                    KeyCode::PageDown => {
                        app.chat_scroll = app.chat_scroll.saturating_sub(5);
                    }
                    // Tab to switch focus
                    KeyCode::Tab => {
                        app.focus = match app.focus {
                            PanelFocus::Input => PanelFocus::Chat,
                            PanelFocus::Chat => PanelFocus::Tools,
                            PanelFocus::Tools => PanelFocus::Input,
                        };
                    }
                    // Escape to cancel or return to input
                    KeyCode::Esc => {
                        if app.agent_running {
                            // TODO: Cancel agent
                            app.agent_running = false;
                            app.messages.push(("system".into(), "⚠️ Agent cancelled".into()));
                        } else {
                            app.focus = PanelFocus::Input;
                        }
                    }
                    _ => {}
                }
            }
        }

        // Process agent events
        while let Ok(event) = event_rx.try_recv() {
            match event {
                AgentEvent::Token(tok) => {
                    app.stream_buffer.push_str(&tok);
                }
                AgentEvent::ToolStart { name, args } => {
                    app.tool_log.push(ToolLogEntry {
                        name,
                        args_summary: args,
                        status: ToolStatus::Running,
                        duration_ms: 0,
                        output_preview: String::new(),
                    });
                }
                AgentEvent::ToolEnd { name, success, output, duration_ms } => {
                    if let Some(entry) = app.tool_log.iter_mut().rev().find(|e| e.name == name && e.status == ToolStatus::Running) {
                        entry.status = if success { ToolStatus::Success } else { ToolStatus::Error };
                        entry.duration_ms = duration_ms;
                        entry.output_preview = output.chars().take(200).collect();
                    }
                }
                AgentEvent::Iteration(n) => {
                    app.iteration = n;
                }
                AgentEvent::Usage { tokens, cost } => {
                    app.total_tokens += tokens;
                    app.total_cost += cost;
                }
                AgentEvent::Complete => {
                    if !app.stream_buffer.is_empty() {
                        app.messages.push(("assistant".into(), app.stream_buffer.clone()));
                        app.stream_buffer.clear();
                    }
                    app.agent_running = false;
                    app.chat_scroll = 0;
                }
                AgentEvent::Error(msg) => {
                    app.messages.push(("error".into(), msg));
                    app.agent_running = false;
                }
            }
        }

        if last_tick.elapsed() >= tick_rate {
            last_tick = Instant::now();
        }

        if app.should_quit {
            break;
        }
    }

    // Restore terminal
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;

    Ok(())
}

// ─── UI Drawing ─────────────────────────────────────────────────────────────

fn draw_ui(f: &mut Frame, app: &App) {
    let size = f.area();

    // Main layout: [Chat + Tools | Status Bar | Input]
    let main_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Min(4),      // Chat + Tools area
            Constraint::Length(1),   // Status bar
            Constraint::Length(3),   // Input area
        ])
        .split(size);

    // Split top area: [Chat (70%) | Tools (30%)]
    let top_chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(70),
            Constraint::Percentage(30),
        ])
        .split(main_chunks[0]);

    // Draw chat panel
    draw_chat(f, app, top_chunks[0]);

    // Draw tools panel
    draw_tools(f, app, top_chunks[1]);

    // Draw status bar
    draw_status_bar(f, app, main_chunks[1]);

    // Draw input
    draw_input(f, app, main_chunks[2]);
}

fn draw_chat(f: &mut Frame, app: &App, area: Rect) {
    let border_style = if app.focus == PanelFocus::Chat {
        Style::default().fg(Color::Cyan)
    } else {
        Style::default().fg(Color::DarkGray)
    };

    let mut lines: Vec<Line> = Vec::new();

    for (role, content) in &app.messages {
        let (prefix, style) = match role.as_str() {
            "user" => ("▶ You", Style::default().fg(Color::Green).add_modifier(Modifier::BOLD)),
            "assistant" => ("◆ MicroCode", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
            "system" => ("● System", Style::default().fg(Color::Yellow)),
            "error" => ("✖ Error", Style::default().fg(Color::Red).add_modifier(Modifier::BOLD)),
            _ => ("", Style::default()),
        };

        lines.push(Line::from(Span::styled(prefix, style)));
        for line in content.lines() {
            lines.push(Line::from(Span::raw(format!("  {}", line))));
        }
        lines.push(Line::from(""));
    }

    // Show streaming buffer
    if !app.stream_buffer.is_empty() {
        lines.push(Line::from(Span::styled(
            "◆ MicroCode",
            Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
        )));
        for line in app.stream_buffer.lines() {
            lines.push(Line::from(Span::raw(format!("  {}", line))));
        }
        // Blinking cursor
        lines.push(Line::from(Span::styled("  ▌", Style::default().fg(Color::Cyan))));
    }

    let chat = Paragraph::new(Text::from(lines))
        .block(
            Block::default()
                .title(" 💬 Chat ")
                .borders(Borders::ALL)
                .border_style(border_style),
        )
        .wrap(Wrap { trim: false })
        .scroll((app.chat_scroll, 0));

    f.render_widget(chat, area);
}

fn draw_tools(f: &mut Frame, app: &App, area: Rect) {
    let border_style = if app.focus == PanelFocus::Tools {
        Style::default().fg(Color::Cyan)
    } else {
        Style::default().fg(Color::DarkGray)
    };

    let items: Vec<ListItem> = app
        .tool_log
        .iter()
        .rev()
        .take(area.height as usize)
        .map(|entry| {
            let (icon, style) = match entry.status {
                ToolStatus::Running => ("⏳", Style::default().fg(Color::Yellow)),
                ToolStatus::Success => ("✓", Style::default().fg(Color::Green)),
                ToolStatus::Error => ("✖", Style::default().fg(Color::Red)),
            };
            let duration = if entry.duration_ms > 0 {
                format!(" {}ms", entry.duration_ms)
            } else {
                String::new()
            };
            ListItem::new(Line::from(vec![
                Span::styled(format!("{} ", icon), style),
                Span::styled(&entry.name, Style::default().add_modifier(Modifier::BOLD)),
                Span::styled(duration, Style::default().fg(Color::DarkGray)),
            ]))
        })
        .collect();

    let tools = List::new(items).block(
        Block::default()
            .title(" 🔧 Tools ")
            .borders(Borders::ALL)
            .border_style(border_style),
    );

    f.render_widget(tools, area);
}

fn draw_status_bar(f: &mut Frame, app: &App, area: Rect) {
    let status = Line::from(vec![
        Span::styled(" 🤖 ", Style::default().fg(Color::Cyan)),
        Span::styled(&app.model, Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
        Span::raw("  "),
        Span::styled(
            format!("📊 {}tok", app.total_tokens),
            Style::default().fg(Color::Yellow),
        ),
        Span::raw("  "),
        Span::styled(
            format!("💰 ${:.4}", app.total_cost),
            Style::default().fg(Color::Green),
        ),
        Span::raw("  "),
        if app.agent_running {
            Span::styled(
                format!("⚡ Running (iter {})", app.iteration),
                Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
            )
        } else {
            Span::styled("● Ready", Style::default().fg(Color::Green))
        },
        Span::raw("  "),
        if app.verify_mode {
            Span::styled("🛡️ Verified", Style::default().fg(Color::Magenta))
        } else {
            Span::raw("")
        },
    ]);

    let bar = Paragraph::new(status)
        .style(Style::default().bg(Color::Rgb(30, 30, 40)));

    f.render_widget(bar, area);
}

fn draw_input(f: &mut Frame, app: &App, area: Rect) {
    let border_style = if app.focus == PanelFocus::Input {
        Style::default().fg(Color::Green)
    } else {
        Style::default().fg(Color::DarkGray)
    };

    let prompt_char = if app.agent_running { "⏳" } else { "❯" };

    let input = Paragraph::new(format!("{} {}", prompt_char, app.input))
        .block(
            Block::default()
                .title(" Input (Enter to send, Ctrl+C to quit) ")
                .borders(Borders::ALL)
                .border_style(border_style),
        );

    f.render_widget(input, area);

    // Set cursor position
    if app.focus == PanelFocus::Input {
        f.set_cursor_position((
            area.x + app.cursor as u16 + 3, // +3 for border + prompt char + space
            area.y + 1,
        ));
    }
}

// ─── Slash Commands ─────────────────────────────────────────────────────────

fn handle_slash_command(app: &mut App, cmd: &str) {
    match cmd.trim() {
        "/help" | "/h" => {
            app.messages.push(("system".into(), 
                "Available commands:\n\
                 /help      — Show this help\n\
                 /clear     — Clear chat history\n\
                 /cost      — Show token usage and cost\n\
                 /compact   — Compact conversation history\n\
                 /model     — Show/change current model\n\
                 /verify    — Toggle shadow verification\n\
                 /tools     — List available tools\n\
                 /quit      — Exit MicroCode CLI".into()
            ));
        }
        "/clear" => {
            app.messages.clear();
            app.tool_log.clear();
            app.messages.push(("system".into(), "Chat cleared.".into()));
        }
        "/cost" => {
            app.messages.push(("system".into(), format!(
                "Token Usage Report:\n  Total tokens: {}\n  Estimated cost: ${:.4}\n  Model: {}",
                app.total_tokens, app.total_cost, app.model
            )));
        }
        "/verify" => {
            app.verify_mode = !app.verify_mode;
            app.messages.push(("system".into(), format!(
                "Shadow verification: {}",
                if app.verify_mode { "ON 🛡️" } else { "OFF" }
            )));
        }
        "/quit" | "/q" => {
            app.should_quit = true;
        }
        _ => {
            app.messages.push(("error".into(), format!("Unknown command: {}", cmd)));
        }
    }
    app.input.clear();
    app.cursor = 0;
}
