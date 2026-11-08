// AI Agent Core Module
// Production-level AI Agent with file system access and context understanding
// Unique Rust-native implementation for MicroCode IDE
// Enhanced with AGY SDK-inspired policy engine, lifecycle hooks, and multi-provider subagent routing

use crate::error::{AppError, Result};
use crate::hooks::{HookPipeline, HookResult as AgentHookResult, AuditLogHook, BudgetEnforcementHook};
use crate::models::{AIConfig, BudgetConfig, StopReason, SubAgentConfig, ModelRecommendation};
use crate::policy::{PolicyEngine, PolicyDecision};
use async_stream::stream;
use chrono::{DateTime, Utc};
use futures::stream::{self, BoxStream, StreamExt};
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock as StdRwLock};
use tokio::fs;
use tokio::sync::RwLock as TokioRwLock;

// Streaming Event Definition
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", content = "data")]
pub enum AgentStreamEvent {
    Token(String),
    ToolStart {
        name: String,
        id: String,
    },
    ToolEnd {
        id: String,
        success: bool,
        output: String,
        error: Option<String>,
    },
    PendingChange(PendingChange),
    Error(String),
    BudgetAlert {
        total_tokens: usize,
        estimated_cost_usd: f64,
        message: String,
    },
    Done,
}

// ==========================================
// Global Agent State & Harness Hygiene Trackers
// ==========================================

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileReadStamp {
    pub size: u64,
    pub modified_nanos: u128,
    pub sha256: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SessionTokenAudit {
    pub session_id: String,
    pub total_tool_calls: usize,
    pub total_tool_output_tokens: usize,
    pub unique_tool_outputs: usize,
    pub repeat_read_count: usize,
    pub repeat_read_tokens_wasted: usize,
    pub micro_compactions: usize,
    pub micro_compacted_tokens_saved: usize,
    pub first_call_guidances_injected: usize,
    pub stale_write_blocks: usize,
    pub security_findings_flagged: usize,
    pub design_findings_flagged: usize,
    pub window_clamps_applied: usize,
    pub tool_output_hashes: HashMap<String, usize>,
}

impl SessionTokenAudit {
    /// Prompt cache stability ratio (0.0 to 1.0): measures how clean the context
    /// remains against repeat reads and turn-by-turn churn.
    pub fn cache_efficiency_score(&self) -> f64 {
        if self.total_tool_output_tokens == 0 {
            return 1.0;
        }
        let waste = self.repeat_read_tokens_wasted.min(self.total_tool_output_tokens);
        1.0 - (waste as f64 / self.total_tool_output_tokens as f64)
    }
}

static AGENT_SESSIONS: Lazy<Arc<StdRwLock<HashMap<String, AgentSession>>>> =
    Lazy::new(|| Arc::new(StdRwLock::new(HashMap::new())));

static FILE_OPERATION_LOG: Lazy<Arc<StdRwLock<Vec<FileOperation>>>> =
    Lazy::new(|| Arc::new(StdRwLock::new(Vec::new())));

/// Tracks which tools have already received their First-Call Guidance in each session.
static GUIDED_TOOLS_BY_SESSION: Lazy<Arc<StdRwLock<HashMap<String, HashSet<String>>>>> =
    Lazy::new(|| Arc::new(StdRwLock::new(HashMap::new())));

/// Tracks file `(size, mtime, sha256)` stamps per `(session_id, canonical_path)` for the Stale-File Write Guard.
static SESSION_FILE_STAMPS: Lazy<Arc<StdRwLock<HashMap<(String, PathBuf), FileReadStamp>>>> =
    Lazy::new(|| Arc::new(StdRwLock::new(HashMap::new())));

/// Tracks `(session_id, read_key) -> sha256` for SHA-256 Repeat-Read Deduplication.
static SESSION_READ_HASHES: Lazy<Arc<StdRwLock<HashMap<(String, String), String>>>> =
    Lazy::new(|| Arc::new(StdRwLock::new(HashMap::new())));

/// Tracks ordered list of relative file paths modified per session for the Session Edit Receipt.
static SESSION_EDITED_FILES: Lazy<Arc<StdRwLock<HashMap<String, Vec<String>>>>> =
    Lazy::new(|| Arc::new(StdRwLock::new(HashMap::new())));

/// Tracks per-session token waste, repeat reads, micro-compactions, and guard interventions.
static SESSION_TOKEN_AUDIT: Lazy<Arc<StdRwLock<HashMap<String, SessionTokenAudit>>>> =
    Lazy::new(|| Arc::new(StdRwLock::new(HashMap::new())));

/// Compute lowercase hex SHA-256 digest of `data`.
pub fn compute_sha256_hex(data: &[u8]) -> String {
    let digest = openssl::sha::sha256(data);
    let mut hex = String::with_capacity(64);
    for b in digest {
        use std::fmt::Write;
        let _ = write!(&mut hex, "{:02x}", b);
    }
    hex
}

pub fn get_session_token_audit(session_id: &str) -> SessionTokenAudit {
    let audits = SESSION_TOKEN_AUDIT.read().unwrap();
    audits.get(session_id).cloned().unwrap_or_else(|| SessionTokenAudit {
        session_id: session_id.to_string(),
        ..Default::default()
    })
}

fn update_token_audit<F: FnOnce(&mut SessionTokenAudit)>(session_id: &str, f: F) {
    if let Ok(mut audits) = SESSION_TOKEN_AUDIT.write() {
        let entry = audits
            .entry(session_id.to_string())
            .or_insert_with(|| SessionTokenAudit {
                session_id: session_id.to_string(),
                ..Default::default()
            });
        f(entry);
    }
}

/// Global safety policy engine (default: deny destructive tools, allow all others).
/// Can be reconfigured at runtime via API.
static POLICY_ENGINE: Lazy<Arc<StdRwLock<PolicyEngine>>> =
    Lazy::new(|| Arc::new(StdRwLock::new(PolicyEngine::default_safe())));

/// Global lifecycle hook pipeline with audit logging.
static HOOK_PIPELINE: Lazy<Arc<tokio::sync::RwLock<HookPipeline>>> =
    Lazy::new(|| {
        let mut pipeline = HookPipeline::new();
        pipeline.add_hook(Arc::new(AuditLogHook));
        Arc::new(tokio::sync::RwLock::new(pipeline))
    });

// ==========================================
// SubAgent Routing Helpers
// ==========================================

/// Resolve a SubAgentConfig into a concrete AIConfig by inheriting from parent
/// where the subagent doesn't specify its own values.
pub fn resolve_subagent_config(subagent: &SubAgentConfig, parent: &AIConfig) -> AIConfig {
    AIConfig {
        provider: subagent.provider.clone().unwrap_or_else(|| parent.provider.clone()),
        model: subagent.model.clone().unwrap_or_else(|| parent.model.clone()),
        api_key: subagent.api_key.clone().unwrap_or_else(|| parent.api_key.clone()),
        temperature: parent.temperature,
        max_tokens: parent.max_tokens,
        use_microrent_proxy: parent.use_microrent_proxy,
        microrent_token: parent.microrent_token.clone(),
        proxy_base_url: parent.proxy_base_url.clone(),
    }
}

/// Evaluate the global policy engine for a tool call.
/// Returns Ok(()) if allowed, or creates a PendingChange / returns error if denied.
fn evaluate_tool_policy(tool_name: &str, args: &serde_json::Value) -> PolicyDecision {
    let engine = POLICY_ENGINE.read().unwrap();
    engine.evaluate(tool_name, args)
}

// Keep agent state bounded while allowing deep, long-running autonomous tasks (24/7).
// Large repositories are discovered and queried incrementally.
const MAX_AGENT_TURNS: usize = 1000;
const MAX_AGENT_MESSAGE_CHARS: usize = 8_000_000;
const MAX_AGENT_TOOL_OUTPUT_CHARS: usize = 4_000_000;
const MAX_AGENT_LOOPS: usize = 1000;
const MAX_PROJECT_ENTRIES: usize = 100_000;
const MAX_PROJECT_SYMBOLS: usize = 200_000;
const MAX_INDEXABLE_FILE_BYTES: u64 = 2 * 1024 * 1024;

/// Default operational circuit breaker limits for 24/7 loops (prevent runaway costs & billing shocks)
pub const DEFAULT_MAX_BUDGET_TOKENS: usize = 1_000_000; // 1,000,000 tokens ceiling
pub const DEFAULT_MAX_BUDGET_USD: f64 = 10.0; // $10.00 USD ceiling

/// Multilingual-aware token estimator:
/// - ASCII characters average ~4 characters per token
/// - Non-ASCII characters (Thai, CJK, symbols) average ~1.8-2 characters per token
pub fn estimate_tokens(text: &str) -> usize {
    if text.is_empty() {
        return 0;
    }
    let mut ascii_chars = 0usize;
    let mut non_ascii_chars = 0usize;
    for ch in text.chars() {
        if ch.is_ascii() {
            ascii_chars += 1;
        } else {
            non_ascii_chars += 1;
        }
    }
    let ascii_tokens = (ascii_chars + 3) / 4;
    let non_ascii_tokens = (non_ascii_chars + 1) / 2;
    ascii_tokens + non_ascii_tokens
}

/// Return the effective context window size (in tokens) for a model.
pub fn model_context_window(model: &str) -> usize {
    let m = model.to_ascii_lowercase();
    if m.contains("gemini-1.5") || m.contains("gemini-2.5") || m.contains("gemini-2.0") || m.contains("gemini-3") {
        200_000
    } else if m.contains("claude") {
        200_000
    } else if m.contains("gpt-4.1") || m.contains("gpt-4o") || m.contains("o1") || m.contains("o3") {
        128_000
    } else if m.contains("deepseek") || m.contains("qwen") {
        64_000
    } else if m.contains("ollama") || m.contains("local") || m.contains("omni") {
        32_768
    } else {
        128_000
    }
}

/// Dynamically clamp `max_tokens` each turn so `prompt_tokens + max_tokens` never overflows
/// the model's context window (preventing HTTP 400 errors near context limits).
pub fn clamp_max_tokens_to_window(
    session_id: &str,
    model: &str,
    prompt_tokens: usize,
    requested_max_tokens: Option<u32>,
) -> u32 {
    let window = model_context_window(model);
    let safety_margin = 1_024usize;
    let default_max = requested_max_tokens.unwrap_or(8_192) as usize;
    let available = window.saturating_sub(prompt_tokens.saturating_add(safety_margin));
    let clamped = available.min(default_max).clamp(256, 32_768) as u32;
    if (clamped as usize) < default_max {
        update_token_audit(session_id, |audit| {
            audit.window_clamps_applied += 1;
        });
    }
    clamped
}

/// Batch Micro-Compaction at 60% context fill:
/// Keeps turn records untouched on normal turns to preserve the prefix prompt cache,
/// and compacts all older re-obtainable tool outputs (outside the last 3 turns) in a single
/// batch once estimated context reaches 60% of the working budget.
pub fn micro_compact_turn_records(
    session_id: &str,
    turn_records: &mut [String],
    base_prompt_tokens: usize,
    working_window_tokens: usize,
) -> usize {
    if turn_records.len() <= 3 {
        return 0;
    }
    let turns_tokens: usize = turn_records.iter().map(|r| estimate_tokens(r)).sum();
    let total_tokens = base_prompt_tokens + turns_tokens;
    let threshold = (working_window_tokens * 60) / 100;
    if total_tokens < threshold {
        return 0;
    }

    let older_end = turn_records.len().saturating_sub(3);
    let mut total_saved_tokens = 0usize;

    for rec in &mut turn_records[..older_end] {
        if rec.contains("[Micro-compacted tool output") || rec.len() <= 800 {
            continue;
        }
        let before_tokens = estimate_tokens(rec);
        let mut compacted = String::new();
        let mut in_tool_body = false;
        let mut current_tool_header = String::new();
        let mut body_chars = 0usize;
        let mut body_preview = String::new();

        for line in rec.lines() {
            if line.starts_with("[Tool ") && line.ends_with("]:") {
                if in_tool_body && body_chars > 400 {
                    compacted.push_str(&format!(
                        "{}\n[Micro-compacted tool output ({} chars) — preview: {}]\n",
                        current_tool_header,
                        body_chars,
                        body_preview.trim()
                    ));
                } else if in_tool_body {
                    compacted.push_str(&current_tool_header);
                    compacted.push('\n');
                    compacted.push_str(&body_preview);
                    compacted.push('\n');
                }
                in_tool_body = true;
                current_tool_header = line.to_string();
                body_chars = 0;
                body_preview.clear();
            } else if in_tool_body {
                body_chars += line.len() + 1;
                if body_preview.len() < 180 {
                    if !body_preview.is_empty() {
                        body_preview.push_str(" | ");
                    }
                    body_preview.push_str(line.trim());
                }
            } else {
                compacted.push_str(line);
                compacted.push('\n');
            }
        }

        if in_tool_body {
            if body_chars > 400 {
                compacted.push_str(&format!(
                    "{}\n[Micro-compacted tool output ({} chars) — preview: {}]\n",
                    current_tool_header,
                    body_chars,
                    body_preview.trim()
                ));
            } else {
                compacted.push_str(&current_tool_header);
                compacted.push('\n');
                compacted.push_str(&body_preview);
                compacted.push('\n');
            }
        }

        let after_tokens = estimate_tokens(&compacted);
        if after_tokens < before_tokens {
            total_saved_tokens += before_tokens - after_tokens;
            *rec = compacted;
        }
    }

    if total_saved_tokens > 0 {
        update_token_audit(session_id, |audit| {
            audit.micro_compactions += 1;
            audit.micro_compacted_tokens_saved += total_saved_tokens;
        });
    }

    total_saved_tokens
}

/// Estimate USD cost for tokens based on provider and model
pub fn estimate_cost_usd(provider: &str, model: &str, prompt_tokens: usize, completion_tokens: usize) -> f64 {
    let p = provider.to_lowercase();
    let m = model.to_lowercase();

    // Rates in USD per million tokens: (input, output)
    let (input_rate, output_rate) = if m.contains("o1-pro") {
        (150.0, 600.0)
    } else if m.contains("o1") {
        (15.0, 60.0)
    } else if m.contains("o3") || m.contains("gpt-4.1") {
        (10.0, 40.0)
    } else if m.contains("gpt-4o-mini") || m.contains("o3-mini") {
        (0.15, 0.60)
    } else if m.contains("gpt-4o") {
        (2.50, 10.0)
    } else if m.contains("claude-3-opus") {
        (15.0, 75.0)
    } else if m.contains("claude-3-7-sonnet") || m.contains("claude-3-5-sonnet") {
        (3.0, 15.0)
    } else if m.contains("claude-3-5-haiku") {
        (0.80, 4.0)
    } else if m.contains("gemini-1.5-pro") || m.contains("gemini-2.5-pro") {
        (1.25, 5.0)
    } else if m.contains("gemini") {
        (0.10, 0.40)
    } else if m.contains("deepseek-reasoner") {
        (0.55, 2.19)
    } else if m.contains("deepseek") {
        (0.27, 1.10)
    } else if p.contains("ollama") || p.contains("local") {
        (0.0, 0.0)
    } else {
        (2.0, 8.0)
    };

    let in_cost = (prompt_tokens as f64) * input_rate / 1_000_000.0;
    let out_cost = (completion_tokens as f64) * output_rate / 1_000_000.0;
    in_cost + out_cost
}

fn compact_prompt_text(text: &str, limit: usize) -> String {
    if text.len() <= limit {
        return text.to_string();
    }

    let mut head_end = (limit * 3) / 5;
    while head_end > 0 && !text.is_char_boundary(head_end) {
        head_end -= 1;
    }
    let mut tail_start = text.len().saturating_sub(limit / 3);
    while tail_start < text.len() && !text.is_char_boundary(tail_start) {
        tail_start += 1;
    }

    let middle = if head_end < tail_start {
        &text[head_end..tail_start]
    } else {
        ""
    };
    let diag_lines: Vec<&str> = middle
        .lines()
        .filter(|line| {
            let l = line.to_ascii_lowercase();
            l.contains("error:")
                || l.contains("error[")
                || l.contains("warning:")
                || l.contains("fatal")
                || l.contains("panicked at")
                || l.contains("traceback")
                || l.contains("exception")
                || l.contains("failed")
        })
        .take(20)
        .collect();

    if !diag_lines.is_empty() {
        let diag_budget = (limit / 6).max(512);
        let mut diag_joined = diag_lines.join("\n");
        if diag_joined.len() > diag_budget {
            let mut end = diag_budget;
            while end > 0 && !diag_joined.is_char_boundary(end) {
                end -= 1;
            }
            diag_joined.truncate(end);
        }
        format!(
            "{}\n…[middle diagnostics preserved]…\n{}\n…[truncated by MicroCode harness]…\n{}",
            &text[..head_end],
            diag_joined,
            &text[tail_start..]
        )
    } else {
        format!(
            "{}\n…[truncated by MicroCode harness]…\n{}",
            &text[..head_end],
            &text[tail_start..]
        )
    }
}

fn trim_session_messages(messages: &mut Vec<AgentMessage>) {
    if messages.len() > MAX_AGENT_TURNS {
        let remove_count = messages.len() - MAX_AGENT_TURNS;
        // Always keep messages[0] if it is the initial user prompt
        if messages.len() > remove_count + 1 {
            messages.drain(1..=remove_count);
        } else {
            messages.drain(..remove_count);
        }
    }

    for message in messages.iter_mut() {
        message.content = compact_prompt_text(&message.content, MAX_AGENT_MESSAGE_CHARS);
        for result in message.tool_results.iter_mut() {
            result.output = compact_prompt_text(&result.output, MAX_AGENT_TOOL_OUTPUT_CHARS);
            if let Some(error) = result.error.as_mut() {
                *error = compact_prompt_text(error, MAX_AGENT_TOOL_OUTPUT_CHARS);
            }
        }
    }
}

fn format_session_history(messages: &[AgentMessage], max_chars: usize) -> String {
    if messages.is_empty() {
        return String::new();
    }
    let total = messages.len();
    let recent_start = total.saturating_sub(12);
    let mut history_blocks = Vec::new();

    for (idx, msg) in messages[recent_start..].iter().enumerate() {
        let is_very_recent = idx + 4 >= total - recent_start;
        let msg_limit = if is_very_recent { 16_000 } else { 4_000 };
        let tool_limit = if is_very_recent { 12_000 } else { 2_500 };

        match msg.role {
            MessageRole::User => {
                history_blocks.push(format!(
                    "User: {}",
                    compact_prompt_text(&msg.content, msg_limit)
                ));
            }
            MessageRole::Assistant => {
                let mut block = format!(
                    "Assistant: {}",
                    compact_prompt_text(&msg.content, msg_limit)
                );
                for tc in &msg.tool_calls {
                    block.push_str(&format!(
                        "\n[Called tool: {}({})]",
                        tc.name,
                        compact_prompt_text(&tc.arguments.to_string(), 1_200)
                    ));
                }
                for res in &msg.tool_results {
                    let out = if res.success {
                        &res.output
                    } else {
                        res.error.as_deref().unwrap_or("tool failed")
                    };
                    block.push_str(&format!(
                        "\n[Tool Result ({})]: {}",
                        if res.success { "OK" } else { "ERROR" },
                        compact_prompt_text(out, tool_limit)
                    ));
                }
                history_blocks.push(block);
            }
            _ => {}
        }
    }

    let joined = history_blocks.join("\n\n");
    compact_prompt_text(&joined, max_chars)
}

fn format_turn_record(
    turn_idx: usize,
    assistant_text: &str,
    calls: &[ToolCall],
    results: &[ToolResult],
) -> String {
    let mut record = format!("=== Turn {} ===\n", turn_idx);
    if !assistant_text.trim().is_empty() {
        record.push_str("Assistant:\n");
        record.push_str(&compact_prompt_text(assistant_text.trim(), 16_000));
        record.push('\n');
    }
    for (idx, result) in results.iter().take(16).enumerate() {
        let call_label = calls
            .get(idx)
            .map(|tc| {
                format!(
                    "{}({})",
                    tc.name,
                    compact_prompt_text(&tc.arguments.to_string(), 800)
                )
            })
            .unwrap_or_else(|| result.tool_call_id.clone());
        let status = if result.success { "SUCCESS" } else { "ERROR" };
        let output = if result.success {
            &result.output
        } else {
            result.error.as_deref().unwrap_or("tool failed")
        };
        record.push_str(&format!(
            "\n[Tool {} - {}]:\n{}\n",
            call_label,
            status,
            compact_prompt_text(output, 24_000)
        ));
    }
    record
}

fn build_agent_turn_prompt(
    base_prompt: &str,
    turn_records: &[String],
    loop_warning: Option<&str>,
) -> String {
    let mut prompt = String::with_capacity(base_prompt.len().min(96_000) + 64_000);
    prompt.push_str(&compact_prompt_text(base_prompt, 96_000));
    prompt.push_str("\n\n=== Execution History (Current Task) ===\n");

    let total = turn_records.len();
    let start = total.saturating_sub(12);
    if start > 0 {
        prompt.push_str(&format!(
            "... [{} earlier turns omitted; keep building on the recent turns below] ...\n\n",
            start
        ));
    }
    for (offset, rec) in turn_records[start..].iter().enumerate() {
        let is_recent = offset + 3 >= total - start;
        let per_turn_budget = if is_recent { 32_000 } else { 6_000 };
        prompt.push_str(&compact_prompt_text(rec, per_turn_budget));
        prompt.push('\n');
    }

    if let Some(warning) = loop_warning {
        prompt.push_str("\n⚠️ SYSTEM LOOP GUARD: ");
        prompt.push_str(warning);
        prompt.push('\n');
    }

    prompt.push_str(
        "\nReview the tool outputs above carefully. Do NOT repeat identical tool calls that already succeeded. Use another tool call only if further action or verification is required; otherwise provide the complete final answer.",
    );
    prompt
}

fn next_agent_turn_prompt(
    base_prompt: &str,
    assistant_text: &str,
    results: &[ToolResult],
) -> String {
    let rec = format_turn_record(1, assistant_text, &[], results);
    build_agent_turn_prompt(base_prompt, &[rec], None)
}

// ==========================================
// Core Data Structures
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentSession {
    pub id: String,
    pub workspace_path: PathBuf,
    pub messages: Vec<AgentMessage>,
    pub context: ProjectContext,
    pub tasks: Vec<Task>,
    pub pending_operations: Vec<PendingOperation>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub current_plan: Option<ExecutionPlan>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentMessage {
    pub id: String,
    pub role: MessageRole,
    pub content: String,
    pub tool_calls: Vec<ToolCall>,
    pub tool_results: Vec<ToolResult>,
    pub timestamp: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum MessageRole {
    User,
    Assistant,
    System,
    Tool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCall {
    pub id: String,
    pub name: String,
    pub arguments: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolResult {
    pub tool_call_id: String,
    pub success: bool,
    pub output: String,
    pub error: Option<String>,
}

fn parse_json_value_into_tool_calls(val: &serde_json::Value) -> Vec<ToolCall> {
    let mut out = Vec::new();
    match val {
        serde_json::Value::Array(items) => {
            for item in items {
                out.extend(parse_json_value_into_tool_calls(item));
            }
        }
        serde_json::Value::Object(map) => {
            if let Some(func) = map.get("function").and_then(|f| f.as_object()) {
                if let Some(name) = func.get("name").and_then(|n| n.as_str()) {
                    let args_val = func
                        .get("arguments")
                        .cloned()
                        .unwrap_or_else(|| serde_json::json!({}));
                    let parsed_args = if let Some(s) = args_val.as_str() {
                        serde_json::from_str(s).unwrap_or_else(|_| serde_json::json!({}))
                    } else {
                        args_val
                    };
                    out.push(ToolCall {
                        id: map
                            .get("id")
                            .and_then(|v| v.as_str())
                            .map(|s| s.to_string())
                            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string()),
                        name: name.to_string(),
                        arguments: parsed_args,
                    });
                }
            } else if let Some(name) = map
                .get("name")
                .or_else(|| map.get("tool"))
                .and_then(|n| n.as_str())
            {
                if let Some(args_raw) = map
                    .get("arguments")
                    .or_else(|| map.get("input"))
                    .or_else(|| map.get("parameters"))
                    .or_else(|| map.get("args"))
                {
                    let parsed_args = if let Some(s) = args_raw.as_str() {
                        serde_json::from_str(s).unwrap_or_else(|_| serde_json::json!({}))
                    } else {
                        args_raw.clone()
                    };
                    if parsed_args.is_object() {
                        out.push(ToolCall {
                            id: map
                                .get("id")
                                .and_then(|v| v.as_str())
                                .map(|s| s.to_string())
                                .unwrap_or_else(|| uuid::Uuid::new_v4().to_string()),
                            name: name.to_string(),
                            arguments: parsed_args,
                        });
                    }
                }
            }
        }
        _ => {}
    }
    out
}

/// Scans `text` for top-level balanced JSON `[...]` or `{...}` spans, properly
/// ignoring brackets/braces inside JSON string literals (`"..."` with `\"` escapes).
fn scan_balanced_json_spans(text: &str) -> Vec<(usize, usize)> {
    let bytes = text.as_bytes();
    let mut spans = Vec::new();
    let mut i = 0;

    while i < bytes.len() {
        let b = bytes[i];
        if b == b'[' || b == b'{' {
            let start = i;
            let mut stack = vec![if b == b'[' { b']' } else { b'}' }];
            let mut in_string = false;
            let mut escaped = false;
            i += 1;

            while i < bytes.len() && !stack.is_empty() {
                let c = bytes[i];
                if in_string {
                    if escaped {
                        escaped = false;
                    } else if c == b'\\' {
                        escaped = true;
                    } else if c == b'"' {
                        in_string = false;
                    }
                } else {
                    match c {
                        b'"' => in_string = true,
                        b'[' => stack.push(b']'),
                        b'{' => stack.push(b'}'),
                        b']' | b'}' => {
                            if stack.last() == Some(&c) {
                                stack.pop();
                            } else {
                                break;
                            }
                        }
                        _ => {}
                    }
                }
                i += 1;
            }

            if stack.is_empty() {
                spans.push((start, i));
                continue;
            } else {
                i = start + 1;
                continue;
            }
        }
        i += 1;
    }

    spans
}

/// Robust Multi-Format Tool Call Extractor for enterprise-grade AI models:
/// Uses a balanced string-literal-aware JSON scanner so nested `{}` braces or
/// embedded markdown fences ` ``` ` inside file content never truncate tool calls.
pub fn extract_tool_calls(ai_response: &str) -> (Vec<ToolCall>, String) {
    let mut tool_calls = Vec::new();
    let mut remove_ranges: Vec<(usize, usize)> = Vec::new();

    for (start, end) in scan_balanced_json_spans(ai_response) {
        let candidate = &ai_response[start..end];
        if !candidate.contains("\"name\"") && !candidate.contains("\"tool\"") {
            continue;
        }
        if let Ok(val) = serde_json::from_str::<serde_json::Value>(candidate) {
            let extracted = parse_json_value_into_tool_calls(&val);
            if !extracted.is_empty() {
                tool_calls.extend(extracted);
                // Expand range to include surrounding ```json ... ``` fence if present
                let mut r_start = start;
                let mut r_end = end;
                let before = &ai_response[..start];
                let after = &ai_response[end..];
                if let Some(fence_pos) = before.rfind("```") {
                    let between = &before[fence_pos + 3..];
                    if between
                        .trim_start_matches(|c: char| c.is_ascii_alphabetic())
                        .trim()
                        .is_empty()
                    {
                        r_start = fence_pos;
                        if let Some(close_rel) = after.find("```") {
                            if after[..close_rel].trim().is_empty() {
                                r_end = end + close_rel + 3;
                            }
                        }
                    }
                }
                remove_ranges.push((r_start, r_end));
            }
        }
    }

    if remove_ranges.is_empty() {
        return (tool_calls, ai_response.trim().to_string());
    }

    let mut cleaned = String::with_capacity(ai_response.len());
    let mut cursor = 0;
    for (r_start, r_end) in remove_ranges {
        if r_start >= cursor && r_start <= ai_response.len() && r_end <= ai_response.len() {
            cleaned.push_str(&ai_response[cursor..r_start]);
            cursor = r_end;
        }
    }
    if cursor < ai_response.len() {
        cleaned.push_str(&ai_response[cursor..]);
    }

    (tool_calls, cleaned.trim().to_string())
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectContext {
    pub root_path: PathBuf,
    pub project_type: String,
    pub files: Vec<FileInfo>,
    pub recent_files: Vec<PathBuf>,
    pub symbols: Vec<Symbol>,
    pub dependencies: Vec<String>,
    pub git_status: Option<GitStatus>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileInfo {
    pub path: PathBuf,
    pub relative_path: String,
    pub size: u64,
    pub is_directory: bool,
    pub extension: Option<String>,
    pub modified: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Symbol {
    pub name: String,
    pub kind: SymbolKind,
    pub file_path: PathBuf,
    pub line: usize,
    pub signature: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SymbolKind {
    Function,
    Class,
    Struct,
    Enum,
    Variable,
    Constant,
    Interface,
    Module,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitStatus {
    pub branch: String,
    pub modified_files: Vec<String>,
    pub staged_files: Vec<String>,
    pub untracked_files: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    pub id: String,
    pub title: String,
    pub description: String,
    pub status: TaskStatus,
    pub priority: TaskPriority,
    pub created_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TaskStatus {
    Pending,
    InProgress,
    Completed,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TaskPriority {
    Low,
    Medium,
    High,
    Critical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingOperation {
    pub id: String,
    pub operation_type: OperationType,
    pub description: String,
    pub requires_confirmation: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum OperationType {
    CreateFile,
    ModifyFile,
    DeleteFile,
    RunCommand,
    GitOperation,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileOperation {
    pub id: String,
    pub session_id: String,
    pub operation: OperationType,
    pub file_path: PathBuf,
    pub old_content: Option<String>,
    pub new_content: Option<String>,
    pub timestamp: DateTime<Utc>,
    pub can_undo: bool,
}

// ==========================================
// Production Features - Like Cursor/Windsurf/Antigravity
// ==========================================

/// Active editor context from IDE
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ActiveEditorContext {
    pub active_file: Option<String>,
    pub active_content: Option<String>,
    pub cursor_line: Option<usize>,
    pub cursor_column: Option<usize>,
    pub selected_text: Option<String>,
    pub selection_start_line: Option<usize>,
    pub selection_end_line: Option<usize>,
    pub open_files: Vec<String>,
    pub language: Option<String>,
    pub visible_range: Option<(usize, usize)>,
}

/// File diff for preview before applying
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileDiff {
    pub file_path: String,
    pub old_content: String,
    pub new_content: String,
    pub hunks: Vec<DiffHunk>,
    pub additions: usize,
    pub deletions: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffHunk {
    pub old_start: usize,
    pub old_count: usize,
    pub new_start: usize,
    pub new_count: usize,
    pub lines: Vec<DiffLine>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffLine {
    pub line_type: DiffLineType,
    pub content: String,
    pub old_line_num: Option<usize>,
    pub new_line_num: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DiffLineType {
    Context,
    Addition,
    Deletion,
}

/// Pending change awaiting user approval
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingChange {
    pub id: String,
    pub session_id: String,
    pub diff: FileDiff,
    pub description: String,
    pub tool_name: String,
    pub status: PendingChangeStatus,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PendingChangeStatus {
    Pending,
    Accepted,
    Rejected,
}

/// Enhanced chat request with editor context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatRequest {
    pub session_id: String,
    pub message: String,
    pub editor_context: Option<ActiveEditorContext>,
    pub provider: Option<String>,
    pub model: Option<String>,
    pub api_key: Option<String>,
    #[serde(default)]
    pub cloud_base_url: Option<String>,
    pub auto_execute: bool, // Auto-execute tools or ask for confirmation
    #[serde(default)]
    pub budget: Option<crate::models::BudgetConfig>,
}

/// Chat response with structured output
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatResponse {
    pub message_id: String,
    pub content: String,
    pub thinking: Option<String>,
    pub tool_calls: Vec<ToolCall>,
    pub tool_results: Vec<ToolResult>,
    pub pending_changes: Vec<PendingChange>,
    pub suggestions: Vec<String>,
    pub plan: Option<ExecutionPlan>,
    /// Why the agent stopped executing (completed, budget, policy, etc.)
    #[serde(default)]
    pub stop_reason: Option<StopReason>,
}

/// Execution plan for multi-step tasks
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionPlan {
    pub id: String,
    pub description: String,
    pub steps: Vec<PlanStep>,
    pub current_step: usize,
    pub status: PlanStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanStep {
    pub id: String,
    pub description: String,
    pub tool: String,
    pub arguments: serde_json::Value,
    pub status: StepStatus,
    pub result: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PlanStatus {
    Queued,
    Planning,
    Executing,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum StepStatus {
    Pending,
    Running,
    Completed,
    Failed,
    Skipped,
}

// Pending changes storage
static PENDING_CHANGES: Lazy<Arc<StdRwLock<HashMap<String, PendingChange>>>> =
    Lazy::new(|| Arc::new(StdRwLock::new(HashMap::new())));

// ==========================================
// Tool Definitions
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolDefinition {
    pub name: String,
    pub description: String,
    pub parameters: serde_json::Value,
}

pub fn get_available_tools() -> Vec<ToolDefinition> {
    vec![
        ToolDefinition {
            name: "read_file".to_string(),
            description: "Read file contents (supports optional start_line/end_line slice).".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Relative or workspace file path"},
                    "start_line": {"type": "integer", "description": "1-based start line (optional)"},
                    "end_line": {"type": "integer", "description": "1-based inclusive end line (optional)"}
                },
                "required": ["path"]
            }),
        },
        ToolDefinition {
            name: "write_file".to_string(),
            description: "Create a new file or overwrite an existing file (guarded against stale external edits).".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Target file path"},
                    "content": {"type": "string", "description": "Full file content"}
                },
                "required": ["path", "content"]
            }),
        },
        ToolDefinition {
            name: "edit_file".to_string(),
            description: "Replace a targeted block in a file (guarded against stale external edits).".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Target file path"},
                    "search": {"type": "string", "description": "Exact block to replace"},
                    "replace": {"type": "string", "description": "Replacement block"},
                    "allow_multiple": {"type": "boolean", "description": "Replace all occurrences if true"}
                },
                "required": ["path", "search", "replace"]
            }),
        },
        ToolDefinition {
            name: "batch_edit".to_string(),
            description: "Apply atomic search/replace edits across one or more files with rollback on error.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "edits": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "path": {"type": "string"},
                                "search": {"type": "string"},
                                "replace": {"type": "string"},
                                "allow_multiple": {"type": "boolean"}
                            },
                            "required": ["path", "search", "replace"]
                        }
                    }
                },
                "required": ["edits"]
            }),
        },
        ToolDefinition {
            name: "delete_file".to_string(),
            description: "Delete a file in the workspace.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "File path to delete"}
                },
                "required": ["path"]
            }),
        },
        ToolDefinition {
            name: "list_directory".to_string(),
            description: "List files and directories at path.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Directory path"},
                    "recursive": {"type": "boolean", "description": "Recurse up to depth 5"}
                },
                "required": ["path"]
            }),
        },
        ToolDefinition {
            name: "repo_map".to_string(),
            description: "Build a Tree-sitter reference-ranked map of workspace files and symbols.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "max_tokens": {"type": "integer", "description": "Token budget (default 1000)"}
                }
            }),
        },
        ToolDefinition {
            name: "search_code".to_string(),
            description: "Regex/text search across workspace files via ripgrep.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Regex or literal pattern"},
                    "file_pattern": {"type": "string", "description": "Optional glob filter (e.g. '*.rs')"}
                },
                "required": ["query"]
            }),
        },
        ToolDefinition {
            name: "design_check".to_string(),
            description: "Run static UI anti-slop linter on Web (CSS/HTML/TSX/Svelte) or SwiftUI (.swift) files.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "File or directory to lint (defaults to '.')"}
                }
            }),
        },
        ToolDefinition {
            name: "security_audit".to_string(),
            description: "Scan file or directory for CWE security vulnerabilities (injection, traversal, secrets, weak crypto).".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "File or directory to scan (defaults to '.')"}
                }
            }),
        },
        ToolDefinition {
            name: "create_task".to_string(),
            description: "Record a task item and optionally append to todo.md.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "title": {"type": "string"},
                    "description": {"type": "string"},
                    "priority": {"type": "string", "enum": ["low", "medium", "high", "critical"]},
                    "add_to_todo": {"type": "boolean"}
                },
                "required": ["title"]
            }),
        },
        ToolDefinition {
            name: "run_command".to_string(),
            description: "Run a sandboxed shell command in the workspace.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "command": {"type": "string"},
                    "working_dir": {"type": "string"}
                },
                "required": ["command"]
            }),
        },
        ToolDefinition {
            name: "git_status".to_string(),
            description: "Get git branch, staged, modified, and untracked files.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {}
            }),
        },
        ToolDefinition {
            name: "git_commit".to_string(),
            description: "Stage files and create a git commit.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "message": {"type": "string"},
                    "files": {"type": "array", "items": {"type": "string"}}
                },
                "required": ["message"]
            }),
        },
        ToolDefinition {
            name: "search_rag".to_string(),
            description: "Semantic vector search across indexed code chunks.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "query": {"type": "string"},
                    "limit": {"type": "integer"}
                },
                "required": ["query"]
            }),
        },
        ToolDefinition {
            name: "create_plan".to_string(),
            description: "Create a structured multi-step execution plan before multi-file changes.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "description": {"type": "string"},
                    "steps": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "description": {"type": "string"},
                                "tool": {"type": "string"}
                            },
                            "required": ["description", "tool"]
                        }
                    }
                },
                "required": ["description", "steps"]
            }),
        },
        ToolDefinition {
            name: "execute_command".to_string(),
            description: "Run build, test, or lint command and return stdout/stderr for verification.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "command": {"type": "string"},
                    "description": {"type": "string"}
                },
                "required": ["command"]
            }),
        },
        ToolDefinition {
            name: "create_project".to_string(),
            description: "Scaffold a new project (rust, swift, node, python, web).".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "type": {"type": "string", "enum": ["rust", "swift", "node", "python", "web"]},
                    "path": {"type": "string"}
                },
                "required": ["name", "type"]
            }),
        },
    ]
}

/// First-Call Tool Guidance: rich operational judgment kept out of the system prompt
/// and injected only the first time a session invokes each tool.
pub fn tool_first_call_guidance(tool_name: &str) -> Option<&'static str> {
    match tool_name {
        "read_file" => Some(
            "Prefer `start_line`/`end_line` for large files. Avoid re-reading unchanged files already in context; SHA-256 repeat-read deduplication is active.",
        ),
        "write_file" => Some(
            "Use `write_file` for new files or intentional full rewrites. Existing files are protected by the Stale-File Write Guard: if modified externally since your last read, call `read_file` first.",
        ),
        "edit_file" | "batch_edit" => Some(
            "Include 2-3 unchanged context lines in `search` so target blocks match uniquely. Use `batch_edit` when updating multiple files atomically. Check the appended Session Edit Receipt instead of running `git status`.",
        ),
        "search_code" | "search_rag" => Some(
            "Narrow `search_code` with `file_pattern` (e.g. `*.rs`, `*.swift`) to reduce noise, or use `repo_map` first to locate high-centrality modules.",
        ),
        "repo_map" => Some(
            "Files are ranked by cross-file AST symbol references (`refs * 10 + symbols`). Start exploration from top-ranked hub files.",
        ),
        "run_command" | "execute_command" => Some(
            "Prefer targeted verification commands (`cargo check`, `cargo test <name>`, `swift test`) over broad rebuilds. Inspect the first compiler error before retrying.",
        ),
        "design_check" => Some(
            "Fix flagged AI-slop patterns: replace gradient text, neon purple glows, and bounce springs with clean typographic hierarchy, tinted neutral surfaces, and `tabular-nums` / `.monospacedDigit()`.",
        ),
        "security_audit" => Some(
            "Remediate all CWE findings: parameterize SQL queries (CWE-89), avoid shell string interpolation (CWE-78), canonicalize paths (CWE-22), and remove hardcoded secrets (CWE-798).",
        ),
        _ => None,
    }
}

/// Returns `Some(guidance)` only on the first call to `tool_name` within `session_id`.
pub fn take_first_call_guidance(session_id: &str, tool_name: &str) -> Option<&'static str> {
    let guidance = tool_first_call_guidance(tool_name)?;
    let mut map = GUIDED_TOOLS_BY_SESSION.write().unwrap();
    let seen = map.entry(session_id.to_string()).or_default();
    if seen.insert(tool_name.to_string()) {
        update_token_audit(session_id, |audit| {
            audit.first_call_guidances_injected += 1;
        });
        Some(guidance)
    } else {
        None
    }
}

// ==========================================
// Session Management
// ==========================================

pub fn create_session(workspace_path: &str) -> Result<String> {
    let session_id = uuid::Uuid::new_v4().to_string();
    let path = PathBuf::from(workspace_path);

    let session = AgentSession {
        id: session_id.clone(),
        workspace_path: path.clone(),
        messages: vec![],
        context: ProjectContext {
            root_path: path,
            project_type: "unknown".to_string(),
            files: vec![],
            recent_files: vec![],
            symbols: vec![],
            dependencies: vec![],
            git_status: None,
        },
        tasks: vec![],
        pending_operations: vec![],
        created_at: Utc::now(),
        updated_at: Utc::now(),
        current_plan: None,
    };

    let mut sessions = AGENT_SESSIONS.write().unwrap();
    sessions.insert(session_id.clone(), session);

    Ok(session_id)
}

pub fn get_session(session_id: &str) -> Option<AgentSession> {
    let sessions = AGENT_SESSIONS.read().unwrap();
    sessions.get(session_id).cloned()
}

pub fn update_session(session: AgentSession) {
    let mut sessions = AGENT_SESSIONS.write().unwrap();
    sessions.insert(session.id.clone(), session);
}

// ==========================================
// Context Building
// ==========================================

pub async fn build_context(workspace_path: &Path, max_depth: usize) -> Result<ProjectContext> {
    let mut context = ProjectContext {
        root_path: workspace_path.to_path_buf(),
        project_type: detect_project_type(workspace_path).await,
        files: vec![],
        recent_files: vec![],
        symbols: vec![],
        dependencies: vec![],
        git_status: get_git_status(workspace_path).await.ok(),
    };

    let mut indexer = crate::indexer::Indexer::new();

    // Index files and extract symbols
    let (files, symbols) = index_files(workspace_path, max_depth, &mut indexer).await?;
    context.files = files;
    context.symbols = symbols;

    // Get recent files (last 20 modified)

    // Get recent files (last 20 modified)
    let mut sorted_files = context.files.clone();
    sorted_files.sort_by(|a, b| b.modified.cmp(&a.modified));
    context.recent_files = sorted_files
        .iter()
        .filter(|f| !f.is_directory)
        .take(20)
        .map(|f| f.path.clone())
        .collect();

    Ok(context)
}

async fn detect_project_type(path: &Path) -> String {
    let indicators = [
        ("Cargo.toml", "rust"),
        ("Package.swift", "swift"),
        ("package.json", "nodejs"),
        ("go.mod", "go"),
        ("requirements.txt", "python"),
        ("pyproject.toml", "python"),
        ("pubspec.yaml", "flutter"),
        ("Gemfile", "ruby"),
        ("pom.xml", "java"),
        ("build.gradle", "java"),
    ];

    for (file, project_type) in indicators {
        if path.join(file).exists() {
            return project_type.to_string();
        }
    }

    "unknown".to_string()
}

pub async fn index_files(
    root: &Path,
    max_depth: usize,
    indexer: &mut crate::indexer::Indexer,
) -> Result<(Vec<FileInfo>, Vec<Symbol>)> {
    let mut files = vec![];
    let mut symbols = vec![];
    index_files_recursive(root, root, &mut files, &mut symbols, 0, max_depth, indexer).await?;
    Ok((files, symbols))
}

fn is_indexable_source(path: &Path) -> bool {
    matches!(
        path.extension().and_then(|extension| extension.to_str()),
        Some(
            "rs" | "swift"
                | "m"
                | "mm"
                | "c"
                | "cc"
                | "cpp"
                | "h"
                | "hpp"
                | "py"
                | "js"
                | "jsx"
                | "ts"
                | "tsx"
                | "java"
                | "kt"
                | "kts"
                | "go"
                | "rb"
                | "php"
                | "cs"
                | "scala"
                | "sql"
                | "sh"
                | "zsh"
                | "fish"
                | "r"
                | "jl"
        )
    )
}

#[async_recursion::async_recursion]
async fn index_files_recursive(
    root: &Path,
    current: &Path,
    files: &mut Vec<FileInfo>,
    symbols: &mut Vec<Symbol>,
    depth: usize,
    max_depth: usize,
    indexer: &mut crate::indexer::Indexer,
) -> Result<()> {
    if depth > max_depth || files.len() >= MAX_PROJECT_ENTRIES {
        return Ok(());
    }

    let mut entries = fs::read_dir(current)
        .await
        .map_err(|e| AppError::IOError(e.to_string()))?;

    while let Some(entry) = entries
        .next_entry()
        .await
        .map_err(|e| AppError::IOError(e.to_string()))?
    {
        if files.len() >= MAX_PROJECT_ENTRIES {
            break;
        }
        let path = entry.path();
        let name = path
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();

        // Skip hidden files and common ignore patterns to reduce CPU/Disk load
        if name.starts_with('.')
            || name == "node_modules"
            || name == "target"
            || name == "build"
            || name == "dist"
            || name == "Dist"
            || name == ".build"
            || name == ".build_dist"
            || name == ".swiftpm"
            || name == ".git"
            || name == "Pods"
            || name == "DerivedData"
            || name == "__pycache__"
        {
            continue;
        }

        let metadata = entry
            .metadata()
            .await
            .map_err(|e| AppError::IOError(e.to_string()))?;

        let relative_path = path
            .strip_prefix(root)
            .unwrap_or(&path)
            .to_string_lossy()
            .to_string();

        let modified = metadata
            .modified()
            .map(|t| DateTime::<Utc>::from(t))
            .unwrap_or_else(|_| Utc::now());

        files.push(FileInfo {
            path: path.clone(),
            relative_path,
            size: metadata.len(),
            is_directory: metadata.is_dir(),
            extension: path.extension().map(|e| e.to_string_lossy().to_string()),
            modified,
        });

        if metadata.is_dir() {
            index_files_recursive(root, &path, files, symbols, depth + 1, max_depth, indexer)
                .await?;
        } else if metadata.len() <= MAX_INDEXABLE_FILE_BYTES
            && symbols.len() < MAX_PROJECT_SYMBOLS
            && is_indexable_source(&path)
        {
            // Extract symbols from code files
            // Yield before parsing so indexing cannot monopolize the runtime.
            tokio::task::yield_now().await;

            if let Ok(content) = fs::read_to_string(&path).await {
                if let Ok(chunks) = indexer.chunk_file(&path, &content) {
                    for chunk in chunks {
                        if symbols.len() >= MAX_PROJECT_SYMBOLS {
                            break;
                        }
                        if let Some(name) = chunk.symbol_name {
                            symbols.push(Symbol {
                                name,
                                kind: match chunk.symbol_kind.as_str() {
                                    "function_definition"
                                    | "function_item"
                                    | "function_declaration" => SymbolKind::Function,
                                    "class_definition" | "class_declaration" => SymbolKind::Class,
                                    "struct_item" => SymbolKind::Struct,
                                    "enum_item" => SymbolKind::Enum,
                                    "method_definition" => SymbolKind::Function, // Treat methods as functions for Kind
                                    _ => SymbolKind::Variable,
                                },
                                file_path: path.clone(),
                                line: chunk.start_line,
                                signature: Some(
                                    chunk.content.lines().next().unwrap_or("").to_string(),
                                ),
                            });
                        }
                    }
                }
            }
        }
    }

    Ok(())
}

async fn get_git_status(path: &Path) -> Result<GitStatus> {
    let git_dir = path.join(".git");
    if !git_dir.exists() {
        return Err(AppError::IOError("Not a git repository".to_string()));
    }

    // Get current branch
    let branch = tokio::process::Command::new("git")
        .args(["branch", "--show-current"])
        .current_dir(path)
        .output()
        .await
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|_| "unknown".to_string());

    // Get status
    let status_output = tokio::process::Command::new("git")
        .args(["status", "--porcelain"])
        .current_dir(path)
        .output()
        .await
        .map_err(|e| AppError::IOError(e.to_string()))?;

    let status_str = String::from_utf8_lossy(&status_output.stdout);
    let mut modified = vec![];
    let mut staged = vec![];
    let mut untracked = vec![];

    for line in status_str.lines() {
        if line.len() < 3 {
            continue;
        }
        let file = line[3..].to_string();
        match &line[0..2] {
            "M " | "A " | "D " | "R " => staged.push(file),
            " M" | " D" => modified.push(file),
            "??" => untracked.push(file),
            _ => {}
        }
    }

    Ok(GitStatus {
        branch,
        modified_files: modified,
        staged_files: staged,
        untracked_files: untracked,
    })
}

// ==========================================
// Tool Execution
// ==========================================

pub async fn execute_tool(
    state: Arc<TokioRwLock<crate::state::AppState>>,
    session_id: &str,
    tool_name: &str,
    arguments: &serde_json::Value,
) -> Result<ToolResult> {
    execute_tool_with_mode(state, session_id, tool_name, arguments, false).await
}

pub async fn execute_tool_with_mode(
    state: Arc<TokioRwLock<crate::state::AppState>>,
    session_id: &str,
    tool_name: &str,
    arguments: &serde_json::Value,
    auto_execute: bool,
) -> Result<ToolResult> {
    let effective_arguments = match HOOK_PIPELINE.read().await.run_pre_tool_call(tool_name, arguments).await {
        AgentHookResult::Allow => arguments.clone(),
        AgentHookResult::Modify(arguments) => arguments,
        AgentHookResult::Deny(reason) => return Err(AppError::ValidationError(reason)),
    };
    let arguments = &effective_arguments;
    match evaluate_tool_policy(tool_name, arguments) {
        PolicyDecision::Allow => {}
        PolicyDecision::AskUser(reason) => {
            if !auto_execute {
                return Err(AppError::ValidationError(reason));
            }
        }
        PolicyDecision::Deny(reason) => {
            let is_default_gated_tool = matches!(
                tool_name,
                "run_command" | "execute_command" | "delete_file" | "git_commit"
            ) && reason.contains("not in the allow list");
            if !(auto_execute && is_default_gated_tool) {
                return Err(AppError::ValidationError(reason));
            }
        }
    }
    let session = get_session(session_id)
        .ok_or_else(|| AppError::NotFound("Session not found".to_string()))?;

    let workspace = &session.workspace_path;

    let result = match tool_name {
        "read_file" => tool_read_file(session_id, workspace, arguments).await,
        "write_file" => tool_write_file(session_id, workspace, arguments).await,
        "edit_file" => tool_edit_file(session_id, workspace, arguments).await,
        "batch_edit" => tool_batch_edit(session_id, workspace, arguments).await,
        "delete_file" => tool_delete_file(session_id, workspace, arguments).await,
        "list_directory" => tool_list_directory(workspace, arguments).await,
        "repo_map" => tool_repo_map(workspace, arguments).await,
        "search_code" => tool_search_code(workspace, arguments).await,
        "design_check" => tool_design_check(session_id, workspace, arguments).await,
        "security_audit" => tool_security_audit(session_id, workspace, arguments).await,
        "create_task" => tool_create_task(session_id, workspace, arguments).await,
        "run_command" => tool_run_command(workspace, arguments).await,
        "git_status" => tool_git_status(workspace).await,
        "git_commit" => tool_git_commit(workspace, arguments).await,
        "search_rag" => tool_search_rag(state, arguments).await,
        "create_plan" => {
            let description = arguments["description"].as_str().unwrap_or("");
            let steps = arguments["steps"].as_array().cloned().unwrap_or_default();
            tool_create_plan(session_id, description, steps).await
        }
        "execute_command" => tool_execute_command(workspace, arguments).await,
        "create_project" => tool_create_project(session_id, workspace, arguments).await,
        _ => Err(AppError::NotFound(format!("Unknown tool: {}", tool_name))),
    };

    HOOK_PIPELINE.read().await.run_post_tool_call(tool_name, arguments, "", result.is_ok()).await;
    let tool_call_id = uuid::Uuid::new_v4().to_string();

    match result {
        Ok(mut output) => {
            let out_hash = compute_sha256_hex(output.as_bytes());
            let out_tokens = estimate_tokens(&output);
            update_token_audit(session_id, |audit| {
                audit.total_tool_calls += 1;
                audit.total_tool_output_tokens += out_tokens;
                let count = audit.tool_output_hashes.entry(out_hash).or_insert(0);
                if *count == 0 {
                    audit.unique_tool_outputs += 1;
                }
                *count += 1;
            });

            if let Some(guidance) = take_first_call_guidance(session_id, tool_name) {
                output.push_str(&format!(
                    "\n\n💡 [Tool Guidance — {}]: {}",
                    tool_name, guidance
                ));
            }

            Ok(ToolResult {
                tool_call_id,
                success: true,
                output,
                error: None,
            })
        }
        Err(e) => {
            update_token_audit(session_id, |audit| {
                audit.total_tool_calls += 1;
            });
            Ok(ToolResult {
                tool_call_id,
                success: false,
                output: String::new(),
                error: Some(e.to_string()),
            })
        }
    }
}

// ==========================================
// Stale-Write Guard, Session Receipts & Guards
// ==========================================

fn read_disk_stamp(path: &Path, content_bytes: &[u8]) -> FileReadStamp {
    let meta = std::fs::metadata(path).ok();
    let size = meta.as_ref().map(|m| m.len()).unwrap_or(content_bytes.len() as u64);
    let modified_nanos = meta
        .and_then(|m| m.modified().ok())
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    FileReadStamp {
        size,
        modified_nanos,
        sha256: compute_sha256_hex(content_bytes),
    }
}

pub fn record_file_stamp(session_id: &str, path: &Path, content_bytes: &[u8]) {
    let canonical = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
    let stamp = read_disk_stamp(&canonical, content_bytes);
    if let Ok(mut stamps) = SESSION_FILE_STAMPS.write() {
        stamps.insert((session_id.to_string(), canonical), stamp);
    }
}

/// Checks if `path` has been modified externally on disk since the session last read or wrote it.
pub fn verify_not_stale_on_disk(session_id: &str, path: &Path, display_path: &str) -> Result<()> {
    if !path.exists() {
        return Ok(());
    }
    let canonical = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
    let recorded = {
        let stamps = SESSION_FILE_STAMPS.read().unwrap();
        stamps.get(&(session_id.to_string(), canonical.clone())).cloned()
    };

    if let Some(prev) = recorded {
        if let Ok(current_bytes) = std::fs::read(&canonical) {
            let current_sha = compute_sha256_hex(&current_bytes);
            if current_sha != prev.sha256 {
                update_token_audit(session_id, |audit| {
                    audit.stale_write_blocks += 1;
                });
                return Err(AppError::ValidationError(format!(
                    "Stale-file write guard: '{}' was modified externally since your last read/write in this session. Call read_file first to inspect the latest changes before overwriting.",
                    display_path
                )));
            }
        }
    }
    Ok(())
}

fn record_session_file_edit(session_id: &str, path_str: &str) -> String {
    let mut files_map = SESSION_EDITED_FILES.write().unwrap();
    let list = files_map.entry(session_id.to_string()).or_default();
    let normalized = path_str.trim_start_matches("./").to_string();
    if !list.contains(&normalized) {
        list.push(normalized);
    }
    let count = list.len();
    let joined = list.join(", ");
    let mut receipt = format!(
        "\n[Session Edit Receipt: {} file(s) touched in session: {}]",
        count, joined
    );
    if count >= 2 {
        receipt.push_str(
            "\n[Cross-File Review Note: Multiple files modified in this session — verify cross-file imports, type signatures, and callers.]",
        );
    }
    receipt
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DesignFinding {
    pub rule_id: String,
    pub severity: String,
    pub file_path: String,
    pub line: usize,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SecurityFinding {
    pub cwe_id: String,
    pub severity: String,
    pub file_path: String,
    pub line: usize,
    pub message: String,
}

fn is_ui_source_file(path: &Path) -> bool {
    matches!(
        path.extension().and_then(|e| e.to_str()),
        Some("html" | "css" | "scss" | "svelte" | "vue" | "jsx" | "tsx" | "swift")
    )
}

/// Static UI Anti-Slop Linter (supports Web CSS/HTML/TSX/Svelte and Native SwiftUI `.swift`).
pub fn lint_ui_design(path: &Path, content: &str) -> Vec<DesignFinding> {
    let mut findings = Vec::new();
    if !is_ui_source_file(path) {
        return findings;
    }
    let file_path = path.to_string_lossy().to_string();
    let lower_full = content.to_ascii_lowercase();

    // 1. Purple-to-Blue AI Cliché Palette check
    let mut purple_hits = 0usize;
    let mut first_purple_line = 1usize;
    for (idx, line) in content.lines().enumerate() {
        let l = line.to_ascii_lowercase();
        let mut line_hits = 0usize;
        for token in ["#6366f1", "#8b5cf6", "#a855f7", "#7c3aed"] {
            if l.contains(token) {
                line_hits += 1;
            }
        }
        if l.contains("lineargradient") && l.contains("purple") && l.contains("blue") {
            line_hits += 2;
        }
        if line_hits > 0 {
            if purple_hits == 0 {
                first_purple_line = idx + 1;
            }
            purple_hits += line_hits;
        }
    }
    if purple_hits >= 2 {
        findings.push(DesignFinding {
            rule_id: "purple-blue-ai-palette".to_string(),
            severity: "warning".to_string(),
            file_path: file_path.clone(),
            line: first_purple_line,
            message: "Overused AI-default indigo/violet gradient palette (#6366f1/#8b5cf6/#a855f7). Prefer intentional brand or neutral surface tokens.".to_string(),
        });
    }

    for (idx, raw_line) in content.lines().enumerate() {
        let line_num = idx + 1;
        let l = raw_line.to_ascii_lowercase();

        // 2. Gradient text (`background-clip: text` + `text-fill-color: transparent`)
        if l.contains("background-clip: text")
            || l.contains("-webkit-background-clip: text")
            || l.contains("-webkit-text-fill-color: transparent")
        {
            findings.push(DesignFinding {
                rule_id: "ai-gradient-text".to_string(),
                severity: "warning".to_string(),
                file_path: file_path.clone(),
                line: line_num,
                message: "Gradient-clipped text is a common AI UI slop pattern that reduces legibility. Use solid high-contrast typography.".to_string(),
            });
        }

        // 3. Exaggerated bounce spring easing
        if l.contains("cubic-bezier(0.34, 1.56")
            || l.contains("cubic-bezier(0.68, -0.55")
            || (l.contains("dampingfraction: 0.4") && l.contains("spring"))
        {
            findings.push(DesignFinding {
                rule_id: "bounce-spring-overuse".to_string(),
                severity: "info".to_string(),
                file_path: file_path.clone(),
                line: line_num,
                message: "Overshooting bounce easing feels synthetic on standard controls. Prefer critically damped easing (`cubic-bezier(0.22, 1, 0.36, 1)` or `.snappy`).".to_string(),
            });
        }

        // 4. Generic AI marketing copy
        for phrase in [
            "revolutionize your",
            "unleash the power of",
            "supercharge your workflow",
            "seamless ai integration",
            "next-generation ai-powered",
        ] {
            if l.contains(phrase) {
                findings.push(DesignFinding {
                    rule_id: "generic-ai-copy".to_string(),
                    severity: "warning".to_string(),
                    file_path: file_path.clone(),
                    line: line_num,
                    message: format!(
                        "Generic AI filler copy detected ('{}'). State concrete product capabilities instead.",
                        phrase
                    ),
                });
                break;
            }
        }

        // 5. Side-tab accent stripe on rounded card
        if (l.contains("border-left: 3px solid") || l.contains("border-left: 4px solid"))
            && lower_full.contains("border-radius")
        {
            findings.push(DesignFinding {
                rule_id: "side-tab-accent-stripe".to_string(),
                severity: "info".to_string(),
                file_path: file_path.clone(),
                line: line_num,
                message: "Thick `border-left` accent stripe on rounded cards is a repetitive AI card trope. Consider a subtle status dot or badge.".to_string(),
            });
        }
    }

    findings
}

/// Built-in CWEval Security Scanner for source code files.
pub fn scan_code_security(path: &Path, content: &str) -> Vec<SecurityFinding> {
    let mut findings = Vec::new();
    let file_path = path.to_string_lossy().to_string();

    for (idx, raw_line) in content.lines().enumerate() {
        let line_num = idx + 1;
        let trimmed = raw_line.trim();
        if trimmed.starts_with("//") || trimmed.starts_with('#') || trimmed.starts_with('*') {
            continue;
        }
        let lower = trimmed.to_ascii_lowercase();

        // CWE-89: SQL Injection via string formatting/interpolation
        let has_sql_verb = lower.contains("select ")
            && lower.contains(" from ")
            || (lower.contains("insert into ") && lower.contains("values"))
            || (lower.contains("update ") && lower.contains(" set "))
            || (lower.contains("delete from ") && lower.contains(" where "));
        let has_interpolation = (trimmed.contains("format!(") && trimmed.contains("{}"))
            || (trimmed.starts_with("f\"") || trimmed.contains("= f\"") || trimmed.contains("(f\""))
            || (trimmed.contains('`') && trimmed.contains("${"));
        if has_sql_verb && has_interpolation {
            findings.push(SecurityFinding {
                cwe_id: "CWE-89".to_string(),
                severity: "high".to_string(),
                file_path: file_path.clone(),
                line: line_num,
                message: "Potential SQL Injection: SQL query constructed via string interpolation. Use parameterized queries (`?` or `$1`).".to_string(),
            });
        }

        // CWE-78: OS Command Injection
        if (lower.contains("shell=true") && (trimmed.contains("f\"") || trimmed.contains(".format(") || trimmed.contains('+')))
            || (lower.contains("os.system(") && (trimmed.contains("f\"") || trimmed.contains('+')))
            || (lower.contains("child_process.exec(") && trimmed.contains("${"))
        {
            findings.push(SecurityFinding {
                cwe_id: "CWE-78".to_string(),
                severity: "high".to_string(),
                file_path: file_path.clone(),
                line: line_num,
                message: "Potential OS Command Injection: shell execution with interpolated input. Pass argument arrays without shell invocation.".to_string(),
            });
        }

        // CWE-798: Hardcoded API Keys / Secrets
        for prefix in ["sk-proj-", "sk-ant-api", "ghp_", "akia"] {
            if lower.contains(prefix) && !lower.contains("example") && !lower.contains("placeholder") && !lower.contains("prefix") {
                findings.push(SecurityFinding {
                    cwe_id: "CWE-798".to_string(),
                    severity: "high".to_string(),
                    file_path: file_path.clone(),
                    line: line_num,
                    message: "Potential hardcoded credential or API token detected. Load secrets from environment variables or Keychain.".to_string(),
                });
                break;
            }
        }

        // CWE-79 / CWE-95 / CWE-502: XSS, eval, or unsafe deserialization
        if trimmed.contains("dangerouslySetInnerHTML")
            || trimmed.contains(".innerHTML =")
            || trimmed.contains("pickle.loads(")
            || (trimmed.contains("yaml.load(") && !trimmed.contains("Loader") && !trimmed.contains("safe_load"))
        {
            findings.push(SecurityFinding {
                cwe_id: "CWE-79/502".to_string(),
                severity: "medium".to_string(),
                file_path: file_path.clone(),
                line: line_num,
                message: "Unsafe DOM injection or untrusted deserialization detected. Sanitize HTML or use safe loaders.".to_string(),
            });
        }
    }

    findings
}

fn run_post_write_guards(session_id: &str, path: &Path, content: &str) -> String {
    let mut notes = String::new();
    let sec_findings = scan_code_security(path, content);
    if !sec_findings.is_empty() {
        update_token_audit(session_id, |audit| {
            audit.security_findings_flagged += sec_findings.len();
        });
        notes.push_str(&format!(
            "\n⚠️ [Security Guard — {} CWE finding(s)]:",
            sec_findings.len()
        ));
        for f in sec_findings.iter().take(5) {
            notes.push_str(&format!("\n  - L{} [{}] {}", f.line, f.cwe_id, f.message));
        }
    }

    let design_findings = lint_ui_design(path, content);
    if !design_findings.is_empty() {
        update_token_audit(session_id, |audit| {
            audit.design_findings_flagged += design_findings.len();
        });
        notes.push_str(&format!(
            "\n🎨 [Design Check — {} UI anti-slop finding(s)]:",
            design_findings.len()
        ));
        for f in design_findings.iter().take(5) {
            notes.push_str(&format!("\n  - L{} [{}] {}", f.line, f.rule_id, f.message));
        }
    }

    notes
}

// ==========================================
// Individual Tool Implementations
// ==========================================

async fn tool_read_file(
    session_id: &str,
    workspace: &Path,
    args: &serde_json::Value,
) -> Result<String> {
    let path_str = args["path"]
        .as_str()
        .ok_or_else(|| AppError::ValidationError("path is required".to_string()))?;

    let full_path = resolve_path(workspace, path_str);
    validate_path_in_workspace(workspace, &full_path)?;

    // Guard: reject files over 10MB to prevent OOM
    const MAX_FILE_SIZE: u64 = 10 * 1024 * 1024; // 10MB
    if let Ok(metadata) = tokio::fs::metadata(&full_path).await {
        if metadata.len() > MAX_FILE_SIZE {
            return Err(AppError::ValidationError(format!(
                "File too large ({:.1} MB). Maximum is {} MB. Use a streaming approach for large files.",
                metadata.len() as f64 / 1_048_576.0,
                MAX_FILE_SIZE / 1_048_576
            )));
        }
    }

    let content = fs::read_to_string(&full_path)
        .await
        .map_err(|e| AppError::IOError(format!("Failed to read file: {}", e)))?;

    // Record full-file stamp so write_file / edit_file can detect external edits
    record_file_stamp(session_id, &full_path, content.as_bytes());

    let start_line = args.get("start_line").and_then(|v| v.as_u64()).map(|v| v as usize);
    let end_line = args.get("end_line").and_then(|v| v.as_u64()).map(|v| v as usize);

    let rendered = if start_line.is_some() || end_line.is_some() {
        let lines: Vec<&str> = content.lines().collect();
        let total = lines.len();
        if total == 0 {
            String::new()
        } else {
            let s = start_line.unwrap_or(1).max(1).min(total);
            let e = end_line.unwrap_or(total).max(s).min(total);
            let slice = &lines[(s - 1)..e];
            let numbered: Vec<String> = slice
                .iter()
                .enumerate()
                .map(|(idx, line)| format!("{}: {}", s + idx, line))
                .collect();
            format!(
                "[File: {} | Lines {}-{} of {}]\n{}",
                path_str,
                s,
                e,
                total,
                numbered.join("\n")
            )
        }
    } else {
        content
    };

    // SHA-256 Repeat-Read Deduplication check
    let canonical = full_path.canonicalize().unwrap_or_else(|_| full_path.clone());
    let read_key = format!("{}:{:?}:{:?}", canonical.display(), start_line, end_line);
    let content_sha = compute_sha256_hex(rendered.as_bytes());
    let is_repeat = {
        let mut hashes = SESSION_READ_HASHES.write().unwrap();
        let prev = hashes.insert((session_id.to_string(), read_key), content_sha.clone());
        prev.as_deref() == Some(content_sha.as_str())
    };

    if is_repeat {
        let wasted_tokens = estimate_tokens(&rendered);
        update_token_audit(session_id, |audit| {
            audit.repeat_read_count += 1;
            audit.repeat_read_tokens_wasted += wasted_tokens;
        });
        return Ok(format!(
            "[Repeat-Read Notice: sha256={} unchanged since earlier read in this session — avoid redundant reads]\n{}",
            &content_sha[..12],
            rendered
        ));
    }

    Ok(rendered)
}

async fn tool_write_file(
    session_id: &str,
    workspace: &Path,
    args: &serde_json::Value,
) -> Result<String> {
    let path_str = args["path"]
        .as_str()
        .ok_or_else(|| AppError::ValidationError("path is required".to_string()))?;
    let content = args["content"]
        .as_str()
        .ok_or_else(|| AppError::ValidationError("content is required".to_string()))?;

    let full_path = resolve_path(workspace, path_str);
    validate_path_in_workspace(workspace, &full_path)?;
    verify_not_stale_on_disk(session_id, &full_path, path_str)?;

    // Store old content for undo
    let old_content = fs::read_to_string(&full_path).await.ok();

    // Create parent directories
    if let Some(parent) = full_path.parent() {
        fs::create_dir_all(parent)
            .await
            .map_err(|e| AppError::IOError(e.to_string()))?;
    }

    // Write file
    fs::write(&full_path, content)
        .await
        .map_err(|e| AppError::IOError(format!("Failed to write file: {}", e)))?;

    record_file_stamp(session_id, &full_path, content.as_bytes());

    // Log operation for undo
    log_file_operation(
        session_id,
        OperationType::CreateFile,
        &full_path,
        old_content,
        Some(content.to_string()),
    );

    let receipt = record_session_file_edit(session_id, path_str);
    let guard_notes = run_post_write_guards(session_id, &full_path, content);

    Ok(format!(
        "Successfully wrote {} bytes to {}{}{}",
        content.len(),
        path_str,
        receipt,
        guard_notes
    ))
}

fn strip_line_number_prefixes(text: &str) -> String {
    let re = regex::Regex::new(r"(?m)^\s*\d+\s*[:|]\s?").unwrap();
    re.replace_all(text, "").to_string()
}

pub(crate) fn smart_replace_in_content(
    old_content: &str,
    search: &str,
    replace: &str,
    allow_multiple: bool,
) -> std::result::Result<String, String> {
    if search.is_empty() {
        return Err("Search text cannot be empty".to_string());
    }

    // 1. Exact match
    let exact_count = old_content.matches(search).count();
    if exact_count == 1 || (exact_count > 1 && allow_multiple) {
        return Ok(if allow_multiple {
            old_content.replace(search, replace)
        } else {
            old_content.replacen(search, replace, 1)
        });
    }
    if exact_count > 1 && !allow_multiple {
        return Err(format!(
            "Search text was found {} times. To prevent unintended mutations, please provide more surrounding context lines to uniquely target the intended block, or specify allow_multiple: true.",
            exact_count
        ));
    }

    // 2. Strip accidental line-number prefixes (e.g. "42: fn foo()")
    let stripped_search = strip_line_number_prefixes(search);
    if stripped_search != search && !stripped_search.trim().is_empty() {
        let stripped_replace = strip_line_number_prefixes(replace);
        let stripped_count = old_content.matches(&stripped_search).count();
        if stripped_count == 1 || (stripped_count > 1 && allow_multiple) {
            return Ok(if allow_multiple {
                old_content.replace(&stripped_search, &stripped_replace)
            } else {
                old_content.replacen(&stripped_search, &stripped_replace, 1)
            });
        }
    }

    // 3. CRLF normalized match
    let norm_content = old_content.replace("\r\n", "\n");
    let norm_search = stripped_search.replace("\r\n", "\n");
    let norm_replace = strip_line_number_prefixes(replace).replace("\r\n", "\n");
    let norm_count = norm_content.matches(&norm_search).count();
    if norm_count == 1 || (norm_count > 1 && allow_multiple) {
        return Ok(if allow_multiple {
            norm_content.replace(&norm_search, &norm_replace)
        } else {
            norm_content.replacen(&norm_search, &norm_replace, 1)
        });
    }
    if norm_count > 1 && !allow_multiple {
        return Err(format!(
            "Search text was found {} times. Please provide more surrounding context lines to uniquely target the intended block.",
            norm_count
        ));
    }

    // 4. Line-by-line trimmed whitespace fallback
    let content_lines: Vec<&str> = norm_content.split('\n').collect();
    let search_lines: Vec<&str> = norm_search.split('\n').collect();
    let has_non_empty = search_lines.iter().any(|l| !l.trim().is_empty());
    if !search_lines.is_empty() && has_non_empty && search_lines.len() <= content_lines.len() {
        let mut match_indices = Vec::new();
        let window = search_lines.len();
        for i in 0..=(content_lines.len() - window) {
            let matches_all = (0..window).all(|k| content_lines[i + k].trim() == search_lines[k].trim());
            if matches_all {
                match_indices.push(i);
            }
        }

        if match_indices.len() == 1 {
            let idx = match_indices[0];
            let mut result_lines: Vec<String> = Vec::with_capacity(content_lines.len());
            for line in &content_lines[..idx] {
                result_lines.push((*line).to_string());
            }
            for line in norm_replace.split('\n') {
                result_lines.push(line.to_string());
            }
            for line in &content_lines[(idx + window)..] {
                result_lines.push((*line).to_string());
            }
            return Ok(result_lines.join("\n"));
        } else if match_indices.len() > 1 {
            return Err(format!(
                "Search text matched {} locations when ignoring indentation. Please provide more surrounding context lines.",
                match_indices.len()
            ));
        }
    }

    Err("Search text not found in file. Read the target lines with read_file first to verify exact contents.".to_string())
}

async fn tool_edit_file(
    session_id: &str,
    workspace: &Path,
    args: &serde_json::Value,
) -> Result<String> {
    let path_str = args["path"]
        .as_str()
        .ok_or_else(|| AppError::ValidationError("path is required".to_string()))?;
    let search = args["search"]
        .as_str()
        .ok_or_else(|| AppError::ValidationError("search is required".to_string()))?;
    let replace = args["replace"]
        .as_str()
        .ok_or_else(|| AppError::ValidationError("replace is required".to_string()))?;

    let full_path = resolve_path(workspace, path_str);
    validate_path_in_workspace(workspace, &full_path)?;
    verify_not_stale_on_disk(session_id, &full_path, path_str)?;

    let old_content = fs::read_to_string(&full_path)
        .await
        .map_err(|e| AppError::IOError(format!("Failed to read file: {}", e)))?;

    let allow_multiple = args.get("allow_multiple").and_then(|v| v.as_bool()).unwrap_or(false);
    let new_content = smart_replace_in_content(&old_content, search, replace, allow_multiple)
        .map_err(AppError::ValidationError)?;

    fs::write(&full_path, &new_content)
        .await
        .map_err(|e| AppError::IOError(format!("Failed to write file: {}", e)))?;

    record_file_stamp(session_id, &full_path, new_content.as_bytes());

    log_file_operation(
        session_id,
        OperationType::ModifyFile,
        &full_path,
        Some(old_content),
        Some(new_content.clone()),
    );

    let receipt = record_session_file_edit(session_id, path_str);
    let guard_notes = run_post_write_guards(session_id, &full_path, &new_content);

    Ok(format!("Successfully edited {}{}{}", path_str, receipt, guard_notes))
}

async fn tool_batch_edit(
    session_id: &str,
    workspace: &Path,
    args: &serde_json::Value,
) -> Result<String> {
    let edits = args["edits"]
        .as_array()
        .ok_or_else(|| AppError::ValidationError("edits array is required".to_string()))?;
    if edits.is_empty() {
        return Err(AppError::ValidationError("edits array cannot be empty".to_string()));
    }

    // Stage all edits in memory first so we can apply atomically without partial state on failure
    let mut staged_contents: HashMap<PathBuf, (String, String, String)> = HashMap::new(); // full_path -> (display_path, original, current)
    let mut ordered_paths: Vec<PathBuf> = Vec::new();

    for (idx, item) in edits.iter().enumerate() {
        let path_str = item["path"].as_str().ok_or_else(|| {
            AppError::ValidationError(format!("edits[{}].path is required", idx))
        })?;
        let search = item["search"].as_str().ok_or_else(|| {
            AppError::ValidationError(format!("edits[{}].search is required", idx))
        })?;
        let replace = item["replace"].as_str().ok_or_else(|| {
            AppError::ValidationError(format!("edits[{}].replace is required", idx))
        })?;
        let allow_multiple = item.get("allow_multiple").and_then(|v| v.as_bool()).unwrap_or(false);

        let full_path = resolve_path(workspace, path_str);
        validate_path_in_workspace(workspace, &full_path)?;
        verify_not_stale_on_disk(session_id, &full_path, path_str)?;

        if !staged_contents.contains_key(&full_path) {
            let disk_text = fs::read_to_string(&full_path).await.map_err(|e| {
                AppError::IOError(format!("Failed to read '{}': {}", path_str, e))
            })?;
            ordered_paths.push(full_path.clone());
            staged_contents.insert(
                full_path.clone(),
                (path_str.to_string(), disk_text.clone(), disk_text),
            );
        }

        let entry = staged_contents.get_mut(&full_path).unwrap();
        let updated = smart_replace_in_content(&entry.2, search, replace, allow_multiple)
            .map_err(|err| {
                AppError::ValidationError(format!(
                    "Atomic batch_edit aborted at edits[{}] ({}): {}",
                    idx, path_str, err
                ))
            })?;
        entry.2 = updated;
    }

    // Commit all staged file updates
    let mut touched_display = Vec::new();
    let mut guard_notes = String::new();
    let mut last_receipt = String::new();

    for full_path in &ordered_paths {
        if let Some((display_path, old_content, new_content)) = staged_contents.remove(full_path) {
            fs::write(full_path, &new_content)
                .await
                .map_err(|e| AppError::IOError(format!("Failed to write '{}': {}", display_path, e)))?;
            record_file_stamp(session_id, full_path, new_content.as_bytes());
            log_file_operation(
                session_id,
                OperationType::ModifyFile,
                full_path,
                Some(old_content),
                Some(new_content.clone()),
            );
            last_receipt = record_session_file_edit(session_id, &display_path);
            guard_notes.push_str(&run_post_write_guards(session_id, full_path, &new_content));
            touched_display.push(display_path);
        }
    }

    Ok(format!(
        "Successfully applied {} edit(s) across {} file(s): {}{}{}",
        edits.len(),
        touched_display.len(),
        touched_display.join(", "),
        last_receipt,
        guard_notes
    ))
}

async fn tool_repo_map(workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let max_tokens = args
        .get("max_tokens")
        .and_then(|v| v.as_u64())
        .map(|v| v as usize)
        .unwrap_or(crate::indexer::DEFAULT_REPO_MAP_TOKENS);
    let ws = workspace.to_path_buf();
    let report = tokio::task::spawn_blocking(move || {
        let mut indexer = crate::indexer::Indexer::new();
        indexer.build_repo_map(&ws, max_tokens)
    })
    .await
    .map_err(|e| AppError::InternalError(format!("RepoMap task join error: {}", e)))??;

    Ok(report.formatted)
}

async fn tool_design_check(
    session_id: &str,
    workspace: &Path,
    args: &serde_json::Value,
) -> Result<String> {
    let path_str = args.get("path").and_then(|v| v.as_str()).unwrap_or(".");
    let target = resolve_path(workspace, path_str);
    validate_path_in_workspace(workspace, &target)?;

    let mut all_findings = Vec::new();
    if target.is_file() {
        if let Ok(content) = fs::read_to_string(&target).await {
            all_findings.extend(lint_ui_design(&target, &content));
        }
    } else {
        for entry in walkdir::WalkDir::new(&target)
            .max_depth(6)
            .into_iter()
            .filter_map(|e| e.ok())
        {
            let p = entry.path();
            if p.is_file() && is_ui_source_file(p) {
                if let Ok(content) = std::fs::read_to_string(p) {
                    all_findings.extend(lint_ui_design(p, &content));
                }
            }
        }
    }

    if all_findings.is_empty() {
        return Ok(format!("Design check passed for '{}': 0 UI anti-slop findings.", path_str));
    }

    update_token_audit(session_id, |audit| {
        audit.design_findings_flagged += all_findings.len();
    });

    let mut out = format!(
        "Design check found {} UI anti-slop issue(s) in '{}':\n",
        all_findings.len(),
        path_str
    );
    for f in all_findings.iter().take(40) {
        out.push_str(&format!(
            "- {}:{} [{}] ({}) {}\n",
            f.file_path, f.line, f.rule_id, f.severity, f.message
        ));
    }
    Ok(out)
}

async fn tool_security_audit(
    session_id: &str,
    workspace: &Path,
    args: &serde_json::Value,
) -> Result<String> {
    let path_str = args.get("path").and_then(|v| v.as_str()).unwrap_or(".");
    let target = resolve_path(workspace, path_str);
    validate_path_in_workspace(workspace, &target)?;

    let mut all_findings = Vec::new();
    if target.is_file() {
        if let Ok(content) = fs::read_to_string(&target).await {
            all_findings.extend(scan_code_security(&target, &content));
        }
    } else {
        for entry in walkdir::WalkDir::new(&target)
            .max_depth(6)
            .into_iter()
            .filter_map(|e| e.ok())
        {
            let p = entry.path();
            if p.is_file() && is_indexable_source(p) {
                if let Ok(content) = std::fs::read_to_string(p) {
                    all_findings.extend(scan_code_security(p, &content));
                }
            }
        }
    }

    if all_findings.is_empty() {
        return Ok(format!("Security audit passed for '{}': 0 CWE findings.", path_str));
    }

    update_token_audit(session_id, |audit| {
        audit.security_findings_flagged += all_findings.len();
    });

    let mut out = format!(
        "Security audit found {} CWE issue(s) in '{}':\n",
        all_findings.len(),
        path_str
    );
    for f in all_findings.iter().take(40) {
        out.push_str(&format!(
            "- {}:{} [{}] ({}) {}\n",
            f.file_path, f.line, f.cwe_id, f.severity, f.message
        ));
    }
    Ok(out)
}

async fn tool_delete_file(
    session_id: &str,
    workspace: &Path,
    args: &serde_json::Value,
) -> Result<String> {
    let path_str = args["path"]
        .as_str()
        .ok_or_else(|| AppError::ValidationError("path is required".to_string()))?;

    let full_path = resolve_path(workspace, path_str);
    validate_path_in_workspace(workspace, &full_path)?;

    let old_content = fs::read_to_string(&full_path).await.ok();

    fs::remove_file(&full_path)
        .await
        .map_err(|e| AppError::IOError(format!("Failed to delete file: {}", e)))?;

    log_file_operation(
        session_id,
        OperationType::DeleteFile,
        &full_path,
        old_content,
        None,
    );

    let receipt = record_session_file_edit(session_id, path_str);
    Ok(format!("Successfully deleted {}{}", path_str, receipt))
}

async fn tool_list_directory(workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let path_str = args["path"].as_str().unwrap_or(".");
    let recursive = args["recursive"].as_bool().unwrap_or(false);

    let full_path = resolve_path(workspace, path_str);
    validate_path_in_workspace(workspace, &full_path)?;

    let max_depth = if recursive { 5 } else { 1 };
    let mut indexer = crate::indexer::Indexer::new();
    let (files, _) = index_files(&full_path, max_depth, &mut indexer).await?;

    let output: Vec<String> = files
        .iter()
        .map(|f| {
            let icon = if f.is_directory { "📁" } else { "📄" };
            format!("{} {}", icon, f.relative_path)
        })
        .collect();

    Ok(output.join("\n"))
}

async fn tool_search_code(workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let query = args["query"]
        .as_str()
        .ok_or_else(|| AppError::ValidationError("query is required".to_string()))?;
    let file_pattern = args["file_pattern"].as_str();

    // Use ripgrep with sensible ignore globs if available, otherwise fall back to grep -rn
    let mut cmd = tokio::process::Command::new("rg");
    cmd.args([
        "--line-number",
        "--no-heading",
        "--color",
        "never",
        "-g",
        "!.git",
        "-g",
        "!node_modules",
        "-g",
        "!target",
        "-g",
        "!.build",
        "-g",
        "!DerivedData",
        "-g",
        "!.codetuner-build",
        "-g",
        "!dist",
        "-g",
        "!build",
    ])
    .current_dir(workspace);

    if let Some(pattern) = file_pattern {
        if !pattern.trim().is_empty() {
            cmd.args(["-g", pattern]);
        }
    }
    cmd.arg(query);

    if let Ok(o) = cmd.output().await {
        if o.status.success() {
            let result = String::from_utf8_lossy(&o.stdout);
            if result.trim().is_empty() {
                return Ok("No matches found".to_string());
            }
            let lines: Vec<&str> = result.lines().take(80).collect();
            return Ok(lines.join("\n"));
        } else if o.status.code() == Some(1) {
            // Exit code 1 in rg means 0 matches found
            return Ok("No matches found".to_string());
        }
    }

    // Fallback to grep -rn if rg is not installed
    let mut grep_cmd = tokio::process::Command::new("grep");
    grep_cmd
        .args([
            "-rn",
            "-I",
            "-E",
            "--exclude-dir=.git",
            "--exclude-dir=node_modules",
            "--exclude-dir=target",
            "--exclude-dir=.build",
            "--exclude-dir=DerivedData",
            "--exclude-dir=.codetuner-build",
            query,
            ".",
        ])
        .current_dir(workspace);

    match grep_cmd.output().await {
        Ok(o) if o.status.success() => {
            let result = String::from_utf8_lossy(&o.stdout);
            if result.trim().is_empty() {
                Ok("No matches found".to_string())
            } else {
                let lines: Vec<&str> = result.lines().take(80).collect();
                Ok(lines.join("\n"))
            }
        }
        _ => Ok("No matches found".to_string()),
    }
}

async fn tool_create_task(
    session_id: &str,
    workspace: &Path,
    args: &serde_json::Value,
) -> Result<String> {
    let title = args["title"]
        .as_str()
        .ok_or_else(|| AppError::ValidationError("title is required".to_string()))?;
    let description = args["description"].as_str().unwrap_or("");
    let priority_str = args["priority"].as_str().unwrap_or("medium");
    let add_to_todo = args["add_to_todo"].as_bool().unwrap_or(true);

    let priority = match priority_str {
        "low" => TaskPriority::Low,
        "high" => TaskPriority::High,
        "critical" => TaskPriority::Critical,
        _ => TaskPriority::Medium,
    };

    let task = Task {
        id: uuid::Uuid::new_v4().to_string(),
        title: title.to_string(),
        description: description.to_string(),
        status: TaskStatus::Pending,
        priority,
        created_at: Utc::now(),
        completed_at: None,
    };

    // Add to session
    if let Some(mut session) = get_session(session_id) {
        session.tasks.push(task.clone());
        update_session(session);
    }

    // Add to todo.md if requested
    if add_to_todo {
        let todo_path = workspace.join("todo.md");
        let mut content = fs::read_to_string(&todo_path)
            .await
            .unwrap_or_else(|_| "# TODO\n\n".to_string());

        let priority_marker = match priority_str {
            "critical" => "🔴",
            "high" => "🟠",
            "low" => "🟢",
            _ => "🟡",
        };

        let task_line = format!(
            "- [ ] {} {} {}\n",
            priority_marker,
            title,
            if description.is_empty() {
                "".to_string()
            } else {
                format!("- {}", description)
            }
        );

        content.push_str(&task_line);

        fs::write(&todo_path, content)
            .await
            .map_err(|e| AppError::IOError(e.to_string()))?;
    }

    Ok(format!("Created task: {}", title))
}

async fn tool_create_project(
    session_id: &str,
    workspace: &Path,
    args: &serde_json::Value,
) -> Result<String> {
    let name = args["name"]
        .as_str()
        .ok_or_else(|| AppError::ValidationError("name is required".to_string()))?;
    let proj_type = args["type"]
        .as_str()
        .ok_or_else(|| AppError::ValidationError("type is required".to_string()))?;
    let path_str = args["path"].as_str().unwrap_or(name);

    let full_path = resolve_path(workspace, path_str);

    // Check if exists
    if full_path.exists() {
        return Err(AppError::ValidationError(format!(
            "Path already exists: {}",
            full_path.display()
        )));
    }

    // Create directory
    fs::create_dir_all(&full_path)
        .await
        .map_err(|e| AppError::IOError(e.to_string()))?;

    let mut created_files = Vec::new();

    match proj_type {
        "rust" => {
            tokio::process::Command::new("cargo")
                .args(["init", "--name", name])
                .current_dir(&full_path)
                .output()
                .await
                .map_err(|e| AppError::IOError(e.to_string()))?;
            created_files.push("Cargo.toml");
            created_files.push("src/main.rs");
        }
        "swift" => {
            tokio::process::Command::new("swift")
                .args(["package", "init", "--type", "executable", "--name", name])
                .current_dir(&full_path)
                .output()
                .await
                .map_err(|e| AppError::IOError(e.to_string()))?;
            created_files.push("Package.swift");
            created_files.push("Sources/main.swift");
        }
        "node" => {
            tokio::process::Command::new("npm")
                .args(["init", "-y"])
                .current_dir(&full_path)
                .output()
                .await
                .map_err(|e| AppError::IOError(e.to_string()))?;

            // Create index.js
            fs::write(full_path.join("index.js"), "console.log('Hello, World!');")
                .await
                .map_err(|e| AppError::IOError(e.to_string()))?;

            created_files.push("package.json");
            created_files.push("index.js");
        }
        "python" => {
            fs::write(
                full_path.join("main.py"),
                "def main():\n    print('Hello, World!')\n\nif __name__ == '__main__':\n    main()",
            )
            .await
            .map_err(|e| AppError::IOError(e.to_string()))?;
            fs::write(full_path.join("requirements.txt"), "")
                .await
                .map_err(|e| AppError::IOError(e.to_string()))?;
            created_files.push("main.py");
            created_files.push("requirements.txt");
        }
        "web" => {
            fs::write(full_path.join("index.html"), "<!DOCTYPE html>\n<html>\n<body>\n    <h1>Hello World</h1>\n    <script src=\"script.js\"></script>\n</body>\n</html>").await
                .map_err(|e| AppError::IOError(e.to_string()))?;
            fs::write(
                full_path.join("style.css"),
                "body { font-family: sans-serif; }",
            )
            .await
            .map_err(|e| AppError::IOError(e.to_string()))?;
            fs::write(full_path.join("script.js"), "console.log('Hello, World!');")
                .await
                .map_err(|e| AppError::IOError(e.to_string()))?;
            created_files.push("index.html");
            created_files.push("style.css");
            created_files.push("script.js");
        }
        _ => {
            return Err(AppError::ValidationError(format!(
                "Unknown project type: {}",
                proj_type
            )))
        }
    }

    Ok(format!(
        "Created {} project at {}. Files: {:?}",
        proj_type, path_str, created_files
    ))
}

async fn tool_run_command(workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let command = args["command"]
        .as_str()
        .ok_or_else(|| AppError::ValidationError("command is required".to_string()))?;
    let timeout_secs = args["timeout_seconds"]
        .as_u64()
        .or_else(|| args["timeout"].as_u64());

    secure_execute_command(workspace, command, None, timeout_secs).await
}

/// Secure command execution with sandboxing:
/// - Comprehensive blocklist with pattern matching (not just substring)
/// - Adaptive enterprise timeout (default 300s, up to 1800s) for heavy builds & tests
/// - 1MB output limit to prevent OOM
/// - Preserves developer toolchain paths ($HOME/.cargo/bin, $HOME/go/bin, Homebrew)
/// - Working directory locked to workspace
async fn secure_execute_command(
    workspace: &Path,
    command: &str,
    description: Option<&str>,
    custom_timeout_secs: Option<u64>,
) -> Result<String> {
    // Normalize command for checking (lowercase, collapse whitespace)
    let cmd_lower = command.to_lowercase();
    let cmd_normalized = cmd_lower.split_whitespace().collect::<Vec<_>>().join(" ");

    // === COMPREHENSIVE BLOCKLIST ===
    // Block by exact dangerous commands
    let blocked_commands = [
        "rm -rf /",
        "rm -rf /*",
        "rm -rf ~",
        "rm -rf $home",
        "mkfs",
        "dd if=",
        ":(){",
        "fork",
        "chmod 777 /",
        "shutdown",
        "reboot",
        "halt",
        "poweroff",
        "init 0",
        "init 6",
    ];
    for b in blocked_commands {
        if cmd_normalized.contains(b) {
            return Err(AppError::ValidationError(format!(
                "Blocked dangerous command pattern: {}",
                b
            )));
        }
    }

    // Block privilege escalation
    let blocked_prefixes = ["sudo ", "su ", "doas ", "pkexec ", "runas "];
    for prefix in blocked_prefixes {
        if cmd_normalized.starts_with(prefix)
            || cmd_normalized.contains(&format!("| {}", prefix))
            || cmd_normalized.contains(&format!("&& {}", prefix))
        {
            return Err(AppError::ValidationError(format!(
                "Blocked privilege escalation: {}",
                prefix.trim()
            )));
        }
    }

    // Block network exfiltration tools (when piped from sensitive sources)
    let blocked_patterns = [
        "curl.*-d.*etc",
        "wget.*--post",
        "nc -e",
        "ncat -e",
        "/dev/tcp",
        "/dev/udp",
        "base64.*|.*curl",
    ];
    for pattern in blocked_patterns {
        if let Ok(re) = regex::Regex::new(pattern) {
            if re.is_match(&cmd_normalized) {
                return Err(AppError::ValidationError(
                    "Blocked potentially dangerous command pattern".to_string(),
                ));
            }
        }
    }

    // Block writing to system directories
    let system_dirs = [
        "/etc/",
        "/usr/",
        "/bin/",
        "/sbin/",
        "/var/",
        "/boot/",
        "/root/",
        "/System/",
        "/Library/",
    ];
    for dir in system_dirs {
        let dir_lower = dir.to_lowercase();
        if cmd_normalized.contains(&format!(">{}", dir_lower))
            || cmd_normalized.contains(&format!("> {}", dir_lower))
        {
            return Err(AppError::ValidationError(format!(
                "Cannot write to system directory: {}",
                dir
            )));
        }
    }

    // === EXECUTE WITH TIMEOUT ===
    // Enterprise default: 300 seconds (5 minutes) for compilation, tests, and heavy tasks
    // Configurable via `timeout_seconds` or `timeout` argument up to 1800s (30 mins)
    let timeout_secs = custom_timeout_secs.unwrap_or(300).max(10).min(1800);
    let timeout_duration = std::time::Duration::from_secs(timeout_secs);

    let home = dirs::home_dir().unwrap_or_default();
    let home_str = home.to_string_lossy();
    let mut custom_path = format!(
        "{}/.cargo/bin:{}/go/bin:{}/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        home_str, home_str, home_str
    );
    if let Ok(sys_path) = std::env::var("PATH") {
        for p in sys_path.split(':') {
            if !custom_path.contains(p) {
                custom_path.push(':');
                custom_path.push_str(p);
            }
        }
    }

    let mut cmd = tokio::process::Command::new("sh");
    cmd.args(["-c", command])
        .current_dir(workspace)
        .kill_on_drop(true)
        .env_clear()
        .env("PATH", custom_path)
        .env("HOME", home)
        .env("LANG", "en_US.UTF-8")
        .env("TERM", "xterm-256color");

    // Inherit build offloading & developer tempdirs if present
    if Path::new("/Volumes/MAC/CodeTunerBuild/tmp").is_dir() {
        cmd.env("TMPDIR", "/Volumes/MAC/CodeTunerBuild/tmp");
        cmd.env("CARGO_TARGET_DIR", "/Volumes/MAC/CodeTunerBuild/cargo-target");
        cmd.env("CARGO_HOME", "/Volumes/MAC/CodeTunerBuild/cargo-home");
    } else if Path::new("/Volumes/MicroCodeBuild/tmp").is_dir() {
        cmd.env("TMPDIR", "/Volumes/MicroCodeBuild/tmp");
        cmd.env("CARGO_TARGET_DIR", "/Volumes/MicroCodeBuild/cargo-target");
        cmd.env("CARGO_HOME", "/Volumes/MicroCodeBuild/cargo-home");
    } else if let Ok(t) = std::env::var("TMPDIR") {
        cmd.env("TMPDIR", t);
    }

    let child = cmd
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| AppError::IOError(format!("Failed to spawn command: {}", e)))?;

    // Wait with timeout
    let result = tokio::time::timeout(timeout_duration, child.wait_with_output()).await;

    match result {
        Ok(Ok(output)) => {
            // Limit output size to 1MB
            const MAX_OUTPUT: usize = 1_048_576;
            let stdout_raw = String::from_utf8_lossy(&output.stdout);
            let stderr_raw = String::from_utf8_lossy(&output.stderr);

            let stdout = if stdout_raw.len() > MAX_OUTPUT {
                format!(
                    "{}\n... [truncated, {} bytes total]",
                    compact_prompt_text(&stdout_raw, MAX_OUTPUT),
                    stdout_raw.len()
                )
            } else {
                stdout_raw.to_string()
            };

            let stderr = if stderr_raw.len() > MAX_OUTPUT {
                format!(
                    "{}\n... [truncated, {} bytes total]",
                    compact_prompt_text(&stderr_raw, MAX_OUTPUT),
                    stderr_raw.len()
                )
            } else {
                stderr_raw.to_string()
            };

            let exit_code = output.status.code().unwrap_or(-1);

            let desc_line = if let Some(d) = description {
                format!("\nDescription: {}", d)
            } else {
                String::new()
            };

            Ok(format!(
                "Command: {}{}\nExit Code: {}\n\nSTDOUT:\n{}\n\nSTDERR:\n{}",
                command, desc_line, exit_code, stdout, stderr
            ))
        }
        Ok(Err(e)) => Err(AppError::IOError(format!("Command failed: {}", e))),
        Err(_) => Err(AppError::IOError(format!(
            "Command timed out after {} seconds: {}",
            timeout_duration.as_secs(),
            command
        ))),
    }
}

async fn tool_git_status(workspace: &Path) -> Result<String> {
    let status = get_git_status(workspace).await?;

    let mut output = format!("Branch: {}\n\n", status.branch);

    if !status.staged_files.is_empty() {
        output.push_str("Staged:\n");
        for f in &status.staged_files {
            output.push_str(&format!("  ✓ {}\n", f));
        }
    }

    if !status.modified_files.is_empty() {
        output.push_str("\nModified:\n");
        for f in &status.modified_files {
            output.push_str(&format!("  M {}\n", f));
        }
    }

    if !status.untracked_files.is_empty() {
        output.push_str("\nUntracked:\n");
        for f in &status.untracked_files {
            output.push_str(&format!("  ? {}\n", f));
        }
    }

    Ok(output)
}

async fn tool_git_commit(workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let message = args["message"]
        .as_str()
        .ok_or_else(|| AppError::ValidationError("message is required".to_string()))?;

    // Stage all if no specific files
    let files = args["files"].as_array();
    if files.is_none() || files.unwrap().is_empty() {
        tokio::process::Command::new("git")
            .args(["add", "."])
            .current_dir(workspace)
            .output()
            .await
            .map_err(|e| AppError::IOError(e.to_string()))?;
    } else {
        for file in files.unwrap() {
            if let Some(f) = file.as_str() {
                tokio::process::Command::new("git")
                    .args(["add", f])
                    .current_dir(workspace)
                    .output()
                    .await
                    .map_err(|e| AppError::IOError(e.to_string()))?;
            }
        }
    }

    // Commit
    let output = tokio::process::Command::new("git")
        .args(["commit", "-m", message])
        .current_dir(workspace)
        .output()
        .await
        .map_err(|e| AppError::IOError(e.to_string()))?;

    if output.status.success() {
        Ok(format!("Committed: {}", message))
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(AppError::IOError(format!("Commit failed: {}", stderr)))
    }
}

// ==========================================
// Helper Functions
// ==========================================

fn resolve_path(workspace: &Path, path_str: &str) -> PathBuf {
    let path = Path::new(path_str);
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        workspace.join(path)
    }
}

fn validate_path_in_workspace(workspace: &Path, path: &Path) -> Result<()> {
    let canonical_workspace = workspace
        .canonicalize()
        .map_err(|e| AppError::IOError(e.to_string()))?;

    // Reject any explicit ParentDir ("..") component in the target path after workspace resolution
    if let Ok(rel) = path.strip_prefix(workspace) {
        for comp in rel.components() {
            if matches!(comp, std::path::Component::ParentDir) {
                return Err(AppError::ValidationError(
                    "Path traversal ('..') is not allowed".to_string(),
                ));
            }
        }
    } else {
        for comp in path.components() {
            if matches!(comp, std::path::Component::ParentDir) {
                return Err(AppError::ValidationError(
                    "Path traversal ('..') is not allowed".to_string(),
                ));
            }
        }
    }

    // Walk up ancestors until we find an existing directory to canonicalize
    // (allows write_file to create files inside new nested directories like `src/new_dir/file.rs`)
    let mut current = Some(path);
    let mut canonical_ancestor = None;
    while let Some(candidate) = current {
        if candidate.exists() {
            canonical_ancestor = Some(
                candidate
                    .canonicalize()
                    .map_err(|e| AppError::IOError(e.to_string()))?,
            );
            break;
        }
        current = candidate.parent();
    }

    let check_path = canonical_ancestor
        .ok_or_else(|| AppError::ValidationError("Invalid path: no existing ancestor directory".to_string()))?;

    if !check_path.starts_with(&canonical_workspace) {
        return Err(AppError::ValidationError(
            "Path is outside workspace (security restriction)".to_string(),
        ));
    }

    Ok(())
}

fn log_file_operation(
    session_id: &str,
    operation: OperationType,
    path: &Path,
    old_content: Option<String>,
    new_content: Option<String>,
) {
    let op = FileOperation {
        id: uuid::Uuid::new_v4().to_string(),
        session_id: session_id.to_string(),
        operation,
        file_path: path.to_path_buf(),
        old_content,
        new_content,
        timestamp: Utc::now(),
        can_undo: true,
    };

    let mut log = FILE_OPERATION_LOG.write().unwrap();
    log.push(op);

    // Keep only last 100 operations
    if log.len() > 100 {
        log.remove(0);
    }
}

// ==========================================
// Undo Support
// ==========================================

pub async fn undo_last_operation(session_id: &str) -> Result<String> {
    let op = {
        let log = FILE_OPERATION_LOG.read().unwrap();
        log.iter()
            .rev()
            .find(|o| o.session_id == session_id && o.can_undo)
            .cloned()
    };

    let op = op.ok_or_else(|| AppError::NotFound("No operation to undo".to_string()))?;

    match op.operation {
        OperationType::CreateFile | OperationType::ModifyFile => {
            if let Some(old_content) = op.old_content {
                fs::write(&op.file_path, old_content as String)
                    .await
                    .map_err(|e| AppError::IOError(e.to_string()))?;
                Ok(format!("Restored: {}", op.file_path.display()))
            } else {
                fs::remove_file(&op.file_path)
                    .await
                    .map_err(|e| AppError::IOError(e.to_string()))?;
                Ok(format!("Deleted created file: {}", op.file_path.display()))
            }
        }
        OperationType::DeleteFile => {
            if let Some(content) = op.old_content {
                fs::write(&op.file_path, content)
                    .await
                    .map_err(|e| AppError::IOError(e.to_string()))?;
                Ok(format!("Restored deleted file: {}", op.file_path.display()))
            } else {
                Err(AppError::IOError(
                    "Cannot restore: no backup content".to_string(),
                ))
            }
        }
        _ => Err(AppError::ValidationError(
            "This operation cannot be undone".to_string(),
        )),
    }
}

// ==========================================
// Production Features - Diff Generation
// ==========================================

/// Generate unified diff between old and new content
pub fn generate_diff(file_path: &str, old_content: &str, new_content: &str) -> FileDiff {
    let old_lines: Vec<&str> = old_content.lines().collect();
    let new_lines: Vec<&str> = new_content.lines().collect();

    let mut hunks = Vec::new();
    let mut additions = 0;
    let mut deletions = 0;

    // Simple line-by-line diff algorithm
    let mut i = 0;
    let mut j = 0;
    let mut hunk_lines = Vec::new();
    let mut hunk_old_start = 0;
    let mut hunk_new_start = 0;
    let mut in_hunk = false;

    while i < old_lines.len() || j < new_lines.len() {
        if i < old_lines.len() && j < new_lines.len() && old_lines[i] == new_lines[j] {
            // Context line
            if in_hunk {
                hunk_lines.push(DiffLine {
                    line_type: DiffLineType::Context,
                    content: old_lines[i].to_string(),
                    old_line_num: Some(i + 1),
                    new_line_num: Some(j + 1),
                });
            }
            i += 1;
            j += 1;
        } else {
            if !in_hunk {
                in_hunk = true;
                hunk_old_start = i + 1;
                hunk_new_start = j + 1;
                // Add context before
                if i > 0 {
                    hunk_lines.push(DiffLine {
                        line_type: DiffLineType::Context,
                        content: old_lines[i.saturating_sub(1)].to_string(),
                        old_line_num: Some(i),
                        new_line_num: Some(j),
                    });
                }
            }

            // Check for deletion
            if i < old_lines.len()
                && (j >= new_lines.len()
                    || !new_lines.iter().skip(j).take(5).any(|&l| l == old_lines[i]))
            {
                hunk_lines.push(DiffLine {
                    line_type: DiffLineType::Deletion,
                    content: old_lines[i].to_string(),
                    old_line_num: Some(i + 1),
                    new_line_num: None,
                });
                deletions += 1;
                i += 1;
            } else if j < new_lines.len() {
                // Addition
                hunk_lines.push(DiffLine {
                    line_type: DiffLineType::Addition,
                    content: new_lines[j].to_string(),
                    old_line_num: None,
                    new_line_num: Some(j + 1),
                });
                additions += 1;
                j += 1;
            }
        }

        // Flush hunk if we have enough context
        if in_hunk && i < old_lines.len() && j < new_lines.len() && old_lines[i] == new_lines[j] {
            let old_count = hunk_lines
                .iter()
                .filter(|l| matches!(l.line_type, DiffLineType::Deletion | DiffLineType::Context))
                .count();
            let new_count = hunk_lines
                .iter()
                .filter(|l| matches!(l.line_type, DiffLineType::Addition | DiffLineType::Context))
                .count();

            hunks.push(DiffHunk {
                old_start: hunk_old_start,
                old_count,
                new_start: hunk_new_start,
                new_count,
                lines: std::mem::take(&mut hunk_lines),
            });
            in_hunk = false;
        }
    }

    // Flush remaining hunk
    if !hunk_lines.is_empty() {
        let old_count = hunk_lines
            .iter()
            .filter(|l| matches!(l.line_type, DiffLineType::Deletion | DiffLineType::Context))
            .count();
        let new_count = hunk_lines
            .iter()
            .filter(|l| matches!(l.line_type, DiffLineType::Addition | DiffLineType::Context))
            .count();

        hunks.push(DiffHunk {
            old_start: hunk_old_start,
            old_count,
            new_start: hunk_new_start,
            new_count,
            lines: hunk_lines,
        });
    }

    FileDiff {
        file_path: file_path.to_string(),
        old_content: old_content.to_string(),
        new_content: new_content.to_string(),
        hunks,
        additions,
        deletions,
    }
}

// ==========================================
// Production Features - Enhanced Chat
// ==========================================

/// Enhanced chat with multi-tool execution and diff preview
pub async fn enhanced_chat(
    state: Arc<TokioRwLock<crate::state::AppState>>,
    request: ChatRequest,
    ai_config: &crate::models::AIConfig,
) -> Result<ChatResponse> {
    let session = get_session(&request.session_id)
        .ok_or_else(|| AppError::NotFound("Session not found".to_string()))?;

    // Build context prompt with editor info
    let mut context_parts = vec![];
    if let Some(ref editor) = request.editor_context {
        if let Some(ref file) = editor.active_file {
            context_parts.push(format!("Active file: {}", file));
        }
        if let Some(line) = editor.cursor_line {
            context_parts.push(format!("Cursor at line: {}", line));
        }
        if let Some(ref selected) = editor.selected_text {
            if !selected.is_empty() {
                context_parts.push(format!("Selected text:\n```\n{}\n```", selected));
            }
        }
        if let Some(ref content) = editor.active_content {
            let lines: Vec<&str> = content.lines().collect();
            let cursor_line = editor.cursor_line.unwrap_or(0);
            let start = cursor_line.saturating_sub(10);
            let end = (cursor_line + 10).min(lines.len());
            let visible: Vec<String> = lines[start..end]
                .iter()
                .enumerate()
                .map(|(i, l)| format!("{}: {}", start + i + 1, l))
                .collect();
            context_parts.push(format!(
                "Code around cursor:\n```\n{}\n```",
                visible.join("\n")
            ));
        }
    }
    context_parts.push(format!("Workspace: {}", session.workspace_path.display()));
    context_parts.push(format!("Project type: {}", session.context.project_type));

    let tools = get_available_tools();
    let tools_json: Vec<serde_json::Value> = tools
        .iter()
        .map(|t| {
            serde_json::json!({
                "name": t.name,
                "description": t.description,
                "arguments": t.parameters
            })
        })
        .collect();

    let system_prompt = format!(
        r#"You are an expert AI coding assistant, designed to rival tools like Cursor and Windsurf.
CONTEXT:
{}

AVAILABLE TOOLS:
{}

CORE PHILOSOPHY:
- **Agentic Workflow**: You are not just a chatbot; you are an autonomous agent. Break down complex requests into a step-by-step plan.
- **Visual Thinking**: Your actions are visualized in real-time. Usage of `task.md` and `todo.md` is CRITICAL for showing your progress to the user.
- **Transparency**: When editing files, always explain WHAT you are doing before you do it.

INSTRUCTIONS:
1. **Task Management (CRITICAL)**: 
   - For any multi-step task, FIRST check if `task.md` exists. If not, create it.
   - Use `task.md` to track your plan. Update it frequently (mark items as `[x]` done, `[-]` skipped, `[/]` in-progress).
   - Format `task.md` with clear headers and checkboxes. This file is the "Dashboard" for the user.

2. **Tool Usage**:
   - You are autonomous and can execute multiple tools in sequence.
   - **Always** verify your changes by reading the file or using search tools.
   - If a tool fails, analyze the error and try a different approach.
   - Respond in standard text to explain your thinking, but for ACTIONS, use ONLY the tool block format: 
   ```json
   [
     {{"name": "tool_name", "arguments": {{"arg1": "val1"}}}},
     ...
   ] 
   ```

3. **Code Editing**:
   - Use `read_file` to understand content before editing.
   - Use `write_file` for new files or complete rewrites.
   - Use `edit_file` for precise changes.
   - **Real-time Preview**: When writing code, the system visualizes it. Be complete and accurate.

4. **Self-Correction**:
   - After editing code, run relevant verification (e.g. `cargo check`, `npm test`) if possible.
   - Read error logs carefully. Focus on the first error.
   - Propose minimal changes to fix specific errors.
   - RE-VERIFY after every fix attempt until clean.

REMEMBER: You are building the future of coding. Make it look magic."#,
        context_parts.join("\n"),
        serde_json::to_string_pretty(&tools_json).unwrap_or_default()
    );

    // Build full prompt including prior session conversation history
    let prior_history = format_session_history(&session.messages, 32_000);
    let full_prompt = if prior_history.is_empty() {
        format!("System: {}\n\nUser: {}", system_prompt, request.message)
    } else {
        format!(
            "System: {}\n\n=== CONVERSATION HISTORY ===\n{}\n\n=== CURRENT REQUEST ===\nUser: {}",
            system_prompt, prior_history, request.message
        )
    };

    // AI Loop for Autonomy & Self-Correction
    let mut current_prompt = full_prompt.clone();
    let base_prompt = full_prompt;
    let mut turn_records: Vec<String> = Vec::new();
    let mut last_tool_signature: Option<String> = None;
    let mut repeated_tool_streak: usize = 0;
    let mut total_tool_calls = Vec::new();
    let mut total_tool_results = Vec::new();
    let mut pending_changes = Vec::new();
    let mut final_assistant_content = String::new();
    let mut loop_count = 0;
    let max_loops = MAX_AGENT_LOOPS;

    // Merge request overrides with base config
    let mut actual_config = ai_config.clone();
    if let Some(p) = &request.provider {
        actual_config.provider = p.clone();
    }
    if let Some(m) = &request.model {
        actual_config.model = m.clone();
    }
    if let Some(k) = &request.api_key {
        actual_config.api_key = k.clone();
    }

    // When the desktop app has configured the Dotmini cloud proxy, use the
    // OpenAI-compatible gateway for the agent's model calls while keeping all
    // file and command tools local to this backend.
    actual_config.use_microrent_proxy = request.cloud_base_url.is_some();
        actual_config.proxy_base_url = request.cloud_base_url.clone();
        actual_config.microrent_token = request.cloud_base_url.as_ref().map(|_| actual_config.api_key.clone());
        if actual_config.use_microrent_proxy { actual_config.provider = "openai".into(); }

    let provider = crate::ai::get_provider(&actual_config.provider)?;

    let budget = request.budget.clone().unwrap_or_else(|| {
        let max_tokens = std::env::var("MICROCODE_MAX_BUDGET_TOKENS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(DEFAULT_MAX_BUDGET_TOKENS);
        let max_cost = std::env::var("MICROCODE_MAX_BUDGET_USD")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(DEFAULT_MAX_BUDGET_USD);
        crate::models::BudgetConfig {
            max_model_calls: None,
            max_tool_calls: None,
            max_total_tokens: Some(max_tokens),
            max_cost_usd: Some(max_cost),
        }
    });

    let mut accumulated_tokens = 0;
    let mut accumulated_cost_usd = 0.0;
    let mut circuit_breaker_reason: Option<String> = None;

    while loop_count < max_loops {
        loop_count += 1;

        let prompt_tokens = estimate_tokens(&current_prompt);
        actual_config.max_tokens = clamp_max_tokens_to_window(
            &request.session_id,
            &actual_config.model,
            prompt_tokens,
            Some(ai_config.max_tokens as u32),
        ) as usize;

        // Call AI
        let ai_response: String = provider.generate(&current_prompt, &actual_config).await?;
        let completion_tokens = estimate_tokens(&ai_response);
        let turn_tokens = prompt_tokens + completion_tokens;
        let turn_cost = estimate_cost_usd(&actual_config.provider, &actual_config.model, prompt_tokens, completion_tokens);

        accumulated_tokens += turn_tokens;
        accumulated_cost_usd += turn_cost;

        // Circuit breaker checks: Protect 24/7 loops from runaway expenses
        if budget.tokens_exceeded(accumulated_tokens) {
            let reason = format!(
                "Budget circuit breaker tripped: Token ceiling exceeded ({} >= {} tokens, ${:.3} USD). Paused to prevent runaway costs.",
                accumulated_tokens,
                budget.max_total_tokens.unwrap_or(0),
                accumulated_cost_usd
            );
            circuit_breaker_reason = Some(reason);
            break;
        }
        if budget.cost_exceeded(accumulated_cost_usd) {
            let reason = format!(
                "Budget circuit breaker tripped: Cost ceiling exceeded (${:.2} >= ${:.2} USD, {} tokens). Paused to prevent runaway costs.",
                accumulated_cost_usd,
                budget.max_cost_usd.unwrap_or(0.0),
                accumulated_tokens
            );
            circuit_breaker_reason = Some(reason);
            break;
        }

        // Parse tool calls from response (multi-format robust extractor)
        let (extracted_calls, turn_content) = extract_tool_calls(&ai_response);
        let mut turn_tool_calls = Vec::new();
        let mut turn_tool_results = Vec::new();

        for tc in extracted_calls {
            turn_tool_calls.push(tc.clone());

            // Execute tool or create pending change
            if request.auto_execute || !is_destructive_tool(&tc.name) {
                match execute_tool_with_mode(
                    state.clone(),
                    &request.session_id,
                    &tc.name,
                    &tc.arguments,
                    request.auto_execute,
                )
                .await
                {
                    Ok(mut result) => {
                        result.tool_call_id = tc.id.clone();
                        turn_tool_results.push(result);
                    }
                    Err(e) => turn_tool_results.push(ToolResult {
                        tool_call_id: tc.id.clone(),
                        success: false,
                        output: String::new(),
                        error: Some(e.to_string()),
                    }),
                }
            } else {
                if let Some(pc) = create_pending_change(
                    &request.session_id,
                    &tc,
                    &session.workspace_path,
                )
                .await
                {
                    pending_changes.push(pc);
                }
            }
        }

        total_tool_calls.extend(turn_tool_calls.clone());
        total_tool_results.extend(turn_tool_results.clone());

        if final_assistant_content.is_empty() {
            final_assistant_content = turn_content.clone();
        } else if !turn_content.is_empty() {
            final_assistant_content.push_str("\n\n");
            final_assistant_content.push_str(&turn_content);
        }

        // If no tools were executed or auto_execute is false, we are done
        if turn_tool_results.is_empty() || !request.auto_execute {
            break;
        }

        let current_sig = turn_tool_calls
            .iter()
            .map(|c| format!("{}:{}", c.name, c.arguments))
            .collect::<Vec<_>>()
            .join("|");
        if last_tool_signature.as_deref() == Some(&current_sig) {
            repeated_tool_streak += 1;
        } else {
            last_tool_signature = Some(current_sig);
            repeated_tool_streak = 0;
        }

        let loop_warning = if repeated_tool_streak >= 2 {
            Some("You have repeated the exact same tool call multiple times in a row. Stop repeating it: either inspect the error output carefully, try a different approach, or conclude your response.")
        } else {
            None
        };

        turn_records.push(format_turn_record(
            loop_count,
            &ai_response,
            &turn_tool_calls,
            &turn_tool_results,
        ));
        let base_prompt_tokens = estimate_tokens(&base_prompt);
        let window_tokens = model_context_window(&actual_config.model);
        let _ = micro_compact_turn_records(
            &request.session_id,
            &mut turn_records,
            base_prompt_tokens,
            window_tokens,
        );
        current_prompt = build_agent_turn_prompt(&base_prompt, &turn_records, loop_warning);
    }

    // Update session with final results
    let mut updated_session = session.clone();
    updated_session.messages.push(AgentMessage {
        id: uuid::Uuid::new_v4().to_string(),
        role: MessageRole::User,
        content: request.message.clone(),
        tool_calls: vec![],
        tool_results: vec![],
        timestamp: Utc::now(),
    });
    updated_session.messages.push(AgentMessage {
        id: uuid::Uuid::new_v4().to_string(),
        role: MessageRole::Assistant,
        content: final_assistant_content.clone(),
        tool_calls: total_tool_calls.clone(),
        tool_results: total_tool_results.clone(),
        timestamp: Utc::now(),
    });
    updated_session.updated_at = Utc::now();
    trim_session_messages(&mut updated_session.messages);
    update_session(updated_session);

    let final_session = get_session(&request.session_id).unwrap_or(session);

    let stop_reason = if let Some(reason) = circuit_breaker_reason {
        Some(StopReason::BudgetExhausted(reason))
    } else if loop_count >= max_loops {
        Some(StopReason::MaxLoopsReached)
    } else {
        Some(StopReason::Completed)
    };

    Ok(ChatResponse {
        message_id: uuid::Uuid::new_v4().to_string(),
        content: final_assistant_content,
        thinking: None,
        tool_calls: total_tool_calls,
        tool_results: total_tool_results,
        pending_changes,
        suggestions: vec![],
        plan: final_session.current_plan,
        stop_reason,
    })
}

/// Enhanced chat with streaming tokens and tool events
pub fn enhanced_chat_stream(
    state: Arc<TokioRwLock<crate::state::AppState>>,
    request: ChatRequest,
    ai_config: crate::models::AIConfig,
) -> BoxStream<'static, Result<AgentStreamEvent>> {
    let (tx, rx) = tokio::sync::mpsc::channel(100);

    tokio::spawn(async move {
        let session = match get_session(&request.session_id) {
            Some(s) => s,
            None => {
                let _ = tx
                    .send(Err(AppError::NotFound("Session not found".to_string())))
                    .await;
                return;
            }
        };

        // Build context parts
        let mut context_parts = vec![];
        if let Some(ref editor) = request.editor_context {
            if let Some(ref file) = editor.active_file {
                context_parts.push(format!("Active file: {}", file));
            }
            if let Some(line) = editor.cursor_line {
                context_parts.push(format!("Cursor at line: {}", line));
            }
            if let Some(ref selected) = editor.selected_text {
                if !selected.is_empty() {
                    context_parts.push(format!("Selected text:\n```\n{}\n```", selected));
                }
            }
            if let Some(ref content) = editor.active_content {
                let lines: Vec<&str> = content.lines().collect();
                let cursor_line = editor.cursor_line.unwrap_or(0);
                let start = cursor_line.saturating_sub(10);
                let end = (cursor_line + 10).min(lines.len());
                let visible: Vec<String> = lines[start..end]
                    .iter()
                    .enumerate()
                    .map(|(i, l)| format!("{}: {}", start + i + 1, l))
                    .collect();
                context_parts.push(format!(
                    "Code around cursor:\n```\n{}\n```",
                    visible.join("\n")
                ));
            }
        }
        context_parts.push(format!("Workspace: {}", session.workspace_path.display()));
        context_parts.push(format!("Project type: {}", session.context.project_type));

        let tools = get_available_tools();
        let tools_json: Vec<serde_json::Value> = tools
            .iter()
            .map(|t| {
                serde_json::json!({
                    "name": t.name,
                    "description": t.description,
                    "arguments": t.parameters
                })
            })
            .collect();

        let system_prompt = format!(
            r#"You are an expert AI coding assistant.
CONTEXT:
{}

AVAILABLE TOOLS:
{}

INSTRUCTIONS:
1. Analyze the request carefully and inspect files before modifying them.
2. Propose a clear plan if the task is multi-step.
3. Execute tools using ONLY JSON tool blocks:
```json
[
  {{"name": "tool_name", "arguments": {{"arg1": "val1"}}}}
]
```
4. Verify your changes after editing files (e.g., read_file or run_command).
5. If a tool fails, analyze the error output and adjust your approach instead of repeating the identical call.
"#,
            context_parts.join("\n"),
            serde_json::to_string_pretty(&tools_json).unwrap_or_default()
        );

        let prior_history = format_session_history(&session.messages, 32_000);
        let base_prompt = if prior_history.is_empty() {
            format!("System: {}\n\nUser: {}", system_prompt, request.message)
        } else {
            format!(
                "System: {}\n\n=== CONVERSATION HISTORY ===\n{}\n\n=== CURRENT REQUEST ===\nUser: {}",
                system_prompt, prior_history, request.message
            )
        };
        let mut current_prompt = base_prompt.clone();
        let mut turn_records: Vec<String> = Vec::new();
        let mut last_tool_signature: Option<String> = None;
        let mut repeated_tool_streak: usize = 0;

        let mut actual_config = ai_config.clone();
        if let Some(p) = &request.provider {
            actual_config.provider = p.clone();
        }
        if let Some(m) = &request.model {
            actual_config.model = m.clone();
        }
        if let Some(k) = &request.api_key {
            actual_config.api_key = k.clone();
        }

        actual_config.use_microrent_proxy = request.cloud_base_url.is_some();
        actual_config.proxy_base_url = request.cloud_base_url.clone();
        actual_config.microrent_token = request.cloud_base_url.as_ref().map(|_| actual_config.api_key.clone());
        if actual_config.use_microrent_proxy { actual_config.provider = "openai".into(); }

        let provider = match crate::ai::get_provider(&actual_config.provider) {
            Ok(p) => p,
            Err(e) => {
                let _ = tx.send(Err(e)).await;
                return;
            }
        };

        let mut loop_count = 0;
        let max_loops = MAX_AGENT_LOOPS;
        let mut total_tool_calls = Vec::new();
        let mut total_tool_results = Vec::new();
        let mut final_content = String::new();

        let budget = request.budget.clone().unwrap_or_else(|| {
            let max_tokens = std::env::var("MICROCODE_MAX_BUDGET_TOKENS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(DEFAULT_MAX_BUDGET_TOKENS);
            let max_cost = std::env::var("MICROCODE_MAX_BUDGET_USD")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(DEFAULT_MAX_BUDGET_USD);
            crate::models::BudgetConfig {
                max_model_calls: None,
                max_tool_calls: None,
                max_total_tokens: Some(max_tokens),
                max_cost_usd: Some(max_cost),
            }
        });

        let mut accumulated_tokens = 0;
        let mut accumulated_cost_usd = 0.0;

        while loop_count < max_loops {
            loop_count += 1;

            let prompt_tokens = estimate_tokens(&current_prompt);
            actual_config.max_tokens = clamp_max_tokens_to_window(
                &request.session_id,
                &actual_config.model,
                prompt_tokens,
                Some(ai_config.max_tokens as u32),
            ) as usize;

            let mut turn_full_content = String::new();
            match provider
                .generate_stream(&current_prompt, &actual_config)
                .await
            {
                Ok(mut stream) => {
                    while let Some(chunk_res) = stream.next().await {
                        match chunk_res {
                            Ok(token) => {
                                turn_full_content.push_str(&token);
                                let _ = tx.send(Ok(AgentStreamEvent::Token(token))).await;
                            }
                            Err(e) => {
                                let _ = tx.send(Err(e)).await;
                                break;
                            }
                        }
                    }
                }
                Err(e) => {
                    let _ = tx.send(Err(e)).await;
                    break;
                }
            }

            let prompt_tokens = estimate_tokens(&current_prompt);
            let completion_tokens = estimate_tokens(&turn_full_content);
            accumulated_tokens += prompt_tokens + completion_tokens;
            accumulated_cost_usd += estimate_cost_usd(&actual_config.provider, &actual_config.model, prompt_tokens, completion_tokens);

            if budget.tokens_exceeded(accumulated_tokens) {
                let reason = format!(
                    "Budget circuit breaker tripped: Token ceiling exceeded ({} >= {} tokens, ${:.3} USD). Runaway loop paused for safety.",
                    accumulated_tokens,
                    budget.max_total_tokens.unwrap_or(0),
                    accumulated_cost_usd
                );
                let _ = tx.send(Ok(AgentStreamEvent::BudgetAlert {
                    total_tokens: accumulated_tokens,
                    estimated_cost_usd: accumulated_cost_usd,
                    message: reason.clone(),
                })).await;
                let _ = tx.send(Ok(AgentStreamEvent::Error(reason))).await;
                break;
            }
            if budget.cost_exceeded(accumulated_cost_usd) {
                let reason = format!(
                    "Budget circuit breaker tripped: Cost ceiling exceeded (${:.2} >= ${:.2} USD, {} tokens). Runaway loop paused for safety.",
                    accumulated_cost_usd,
                    budget.max_cost_usd.unwrap_or(0.0),
                    accumulated_tokens
                );
                let _ = tx.send(Ok(AgentStreamEvent::BudgetAlert {
                    total_tokens: accumulated_tokens,
                    estimated_cost_usd: accumulated_cost_usd,
                    message: reason.clone(),
                })).await;
                let _ = tx.send(Ok(AgentStreamEvent::Error(reason))).await;
                break;
            }

            // Parse tool calls from the full turn content (multi-format robust extractor)
            let (extracted_calls, _cleaned_content) = extract_tool_calls(&turn_full_content);
            let mut turn_tool_calls = Vec::new();
            let mut turn_tool_results = Vec::new();

            for tc in extracted_calls {
                let name = &tc.name;
                let args = &tc.arguments;
                turn_tool_calls.push(tc.clone());
                let _ = tx
                    .send(Ok(AgentStreamEvent::ToolStart {
                        name: tc.name.clone(),
                        id: tc.id.clone(),
                    }))
                    .await;

                // Execute tool or create pending change
                if request.auto_execute || !is_destructive_tool(name) {
                    match execute_tool_with_mode(
                        state.clone(),
                        &request.session_id,
                        name,
                        args,
                        request.auto_execute,
                    )
                    .await
                    {
                        Ok(mut result) => {
                            result.tool_call_id = tc.id.clone();
                            let _ = tx
                                .send(Ok(AgentStreamEvent::ToolEnd {
                                    id: tc.id.clone(),
                                    success: result.success,
                                    output: result.output.clone(),
                                    error: result.error.clone(),
                                }))
                                .await;
                            turn_tool_results.push(result);
                        }
                        Err(e) => {
                            let _ = tx
                                .send(Ok(AgentStreamEvent::ToolEnd {
                                    id: tc.id.clone(),
                                    success: false,
                                    output: String::new(),
                                    error: Some(e.to_string()),
                                }))
                                .await;
                            turn_tool_results.push(ToolResult {
                                tool_call_id: tc.id.clone(),
                                success: false,
                                output: String::new(),
                                error: Some(e.to_string()),
                            });
                        }
                    }
                } else {
                    if let Some(pc) = create_pending_change(
                        &request.session_id,
                        &tc,
                        &session.workspace_path,
                    )
                    .await
                    {
                        let _ =
                            tx.send(Ok(AgentStreamEvent::PendingChange(pc))).await;
                    }
                }
            }

            let current_sig = turn_tool_calls
                .iter()
                .map(|c| format!("{}:{}", c.name, c.arguments))
                .collect::<Vec<_>>()
                .join("|");

            let turn_record = format_turn_record(
                loop_count,
                &turn_full_content,
                &turn_tool_calls,
                &turn_tool_results,
            );

            total_tool_calls.extend(turn_tool_calls);
            total_tool_results.extend(turn_tool_results.clone());

            if final_content.is_empty() {
                final_content = turn_full_content.clone();
            } else {
                final_content.push_str("\n\n");
                final_content.push_str(&turn_full_content);
            }

            if turn_tool_results.is_empty() || !request.auto_execute {
                break;
            }

            if last_tool_signature.as_deref() == Some(&current_sig) {
                repeated_tool_streak += 1;
            } else {
                last_tool_signature = Some(current_sig);
                repeated_tool_streak = 0;
            }

            let loop_warning = if repeated_tool_streak >= 2 {
                Some("You have repeated the exact same tool call multiple times in a row. Stop repeating it: either inspect the error output carefully, try a different approach, or conclude your response.")
            } else {
                None
            };

            turn_records.push(turn_record);
            let base_prompt_tokens = estimate_tokens(&base_prompt);
            let window_tokens = model_context_window(&actual_config.model);
            let _ = micro_compact_turn_records(
                &request.session_id,
                &mut turn_records,
                base_prompt_tokens,
                window_tokens,
            );
            current_prompt = build_agent_turn_prompt(&base_prompt, &turn_records, loop_warning);
        }

        // Final session update
        let mut updated_session = session.clone();
        updated_session.messages.push(AgentMessage {
            id: uuid::Uuid::new_v4().to_string(),
            role: MessageRole::User,
            content: request.message.clone(),
            tool_calls: vec![],
            tool_results: vec![],
            timestamp: Utc::now(),
        });
        updated_session.messages.push(AgentMessage {
            id: uuid::Uuid::new_v4().to_string(),
            role: MessageRole::Assistant,
            content: final_content,
            tool_calls: total_tool_calls,
            tool_results: total_tool_results,
            timestamp: Utc::now(),
        });
        trim_session_messages(&mut updated_session.messages);
        update_session(updated_session);

        let _ = tx.send(Ok(AgentStreamEvent::Done)).await;
    });

    use tokio_stream::wrappers::ReceiverStream;
    ReceiverStream::new(rx).boxed()
}

fn is_destructive_tool(name: &str) -> bool {
    // Use the policy engine for evaluation — if the policy denies or asks,
    // treat as destructive. This makes tool safety configurable.
    match evaluate_tool_policy(name, &serde_json::Value::Null) {
        PolicyDecision::Allow => false,
        PolicyDecision::Deny(_) | PolicyDecision::AskUser(_) => true,
    }
}

// ==========================================
// Streaming Implementation
// ==========================================

pub fn run_agent_loop_stream(
    session_id: String,
    user_message: String,
    workspace: PathBuf,
    provider_name: String,
    model_name: String,
    api_key: String,
    auto_execute: bool, // If true, automatically runs safe tools
    state: Arc<TokioRwLock<crate::state::AppState>>,
) -> BoxStream<'static, Result<AgentStreamEvent>> {
    let stream = stream! {
        // 1. Get or Create Session
        let _ = ensure_session_exists_sync(&session_id, &workspace);

        // 2. Append User Message
        {
            let mut sessions = AGENT_SESSIONS.write().unwrap();
            if let Some(session) = sessions.get_mut(&session_id) {
                session.messages.push(AgentMessage {
                    id: uuid::Uuid::new_v4().to_string(),
                    role: MessageRole::User,
                    content: user_message.clone(),
                    tool_calls: vec![],
                    tool_results: vec![],
                    timestamp: Utc::now(),
                });
                trim_session_messages(&mut session.messages);
            }
        }

        // 3. Build Context & Prompt
        let system_prompt = construct_system_prompt_sync(&workspace);
        let tools_json = {
            let tools = get_available_tools();
            serde_json::to_string_pretty(&tools).unwrap_or_default()
        };

        let mut full_prompt = String::new();
        full_prompt.push_str(&format!("System: {}\n", system_prompt));
        full_prompt.push_str(&format!("TOOLS: {}\n\n", tools_json));

        // Retrieve compacted history
        {
            let sessions = AGENT_SESSIONS.read().unwrap();
            if let Some(session) = sessions.get(&session_id) {
                let history_text = format_session_history(&session.messages, 32_000);
                if !history_text.is_empty() {
                    full_prompt.push_str(&history_text);
                    full_prompt.push('\n');
                }
            }
        }

        // 4. Agent Loop with Budget Circuit Breaker
        let mut loop_count = 0;
        let max_loops = MAX_AGENT_LOOPS;
        let mut current_turn_prompt = full_prompt.clone();
        let base_prompt = full_prompt;
        let mut turn_records: Vec<String> = Vec::new();
        let mut last_tool_signature: Option<String> = None;
        let mut repeated_tool_streak: usize = 0;

        let max_tokens = std::env::var("MICROCODE_MAX_BUDGET_TOKENS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(DEFAULT_MAX_BUDGET_TOKENS);
        let max_cost = std::env::var("MICROCODE_MAX_BUDGET_USD")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(DEFAULT_MAX_BUDGET_USD);
        let budget = crate::models::BudgetConfig {
            max_model_calls: None,
            max_tool_calls: None,
            max_total_tokens: Some(max_tokens),
            max_cost_usd: Some(max_cost),
        };
        let mut accumulated_tokens = 0;
        let mut accumulated_cost_usd = 0.0;

        // Setup AI Config
        let mut config = crate::models::AIConfig::default();
        config.provider = provider_name.clone();
        config.model = model_name.clone();
        config.api_key = api_key.clone();

        loop {
            if loop_count >= max_loops { break; }
            loop_count += 1;

            let provider = match crate::ai::get_provider(&config.provider) {
                Ok(p) => p,
                Err(e) => {
                    yield Err(e);
                    break;
                }
            };

            let mut turn_content = String::new();
            let mut turn_tool_calls: Vec<ToolCall> = Vec::new();

            let prompt_tokens = estimate_tokens(&current_turn_prompt);
            config.max_tokens = clamp_max_tokens_to_window(
                &session_id,
                &config.model,
                prompt_tokens,
                None,
            ) as usize;

            // Stream Generation
            match provider.generate_stream(&current_turn_prompt, &config).await {
                Ok(mut stream) => {
                    while let Some(chunk_res) = stream.next().await {
                        match chunk_res {
                            Ok(token) => {
                                turn_content.push_str(&token);
                                yield Ok(AgentStreamEvent::Token(token));
                            }
                            Err(e) => {
                                yield Ok(AgentStreamEvent::Error(e.to_string()));
                            }
                        }
                    }
                }
                Err(e) => {
                    yield Err(e);
                    break;
                }
            }

            let prompt_tokens = estimate_tokens(&current_turn_prompt);
            let completion_tokens = estimate_tokens(&turn_content);
            accumulated_tokens += prompt_tokens + completion_tokens;
            accumulated_cost_usd += estimate_cost_usd(&config.provider, &config.model, prompt_tokens, completion_tokens);

            if budget.tokens_exceeded(accumulated_tokens) {
                let reason = format!(
                    "Budget circuit breaker tripped: Token ceiling exceeded ({} >= {} tokens, ${:.3} USD). Paused to prevent runaway costs.",
                    accumulated_tokens,
                    budget.max_total_tokens.unwrap_or(0),
                    accumulated_cost_usd
                );
                yield Ok(AgentStreamEvent::BudgetAlert {
                    total_tokens: accumulated_tokens,
                    estimated_cost_usd: accumulated_cost_usd,
                    message: reason.clone(),
                });
                yield Ok(AgentStreamEvent::Error(reason));
                break;
            }
            if budget.cost_exceeded(accumulated_cost_usd) {
                let reason = format!(
                    "Budget circuit breaker tripped: Cost ceiling exceeded (${:.2} >= ${:.2} USD, {} tokens). Paused to prevent runaway costs.",
                    accumulated_cost_usd,
                    budget.max_cost_usd.unwrap_or(0.0),
                    accumulated_tokens
                );
                yield Ok(AgentStreamEvent::BudgetAlert {
                    total_tokens: accumulated_tokens,
                    estimated_cost_usd: accumulated_cost_usd,
                    message: reason.clone(),
                });
                yield Ok(AgentStreamEvent::Error(reason));
                break;
            }

            // Parse Tool Calls using robust multi-format extractor
            let (extracted_calls, _cleaned) = extract_tool_calls(&turn_content);
            turn_tool_calls = extracted_calls;

            if turn_tool_calls.is_empty() {
                // Save final assistant turn to session
                {
                    let mut sessions = AGENT_SESSIONS.write().unwrap();
                    if let Some(session) = sessions.get_mut(&session_id) {
                        session.messages.push(AgentMessage {
                            id: uuid::Uuid::new_v4().to_string(),
                            role: MessageRole::Assistant,
                            content: turn_content.clone(),
                            tool_calls: vec![],
                            tool_results: vec![],
                            timestamp: Utc::now(),
                        });
                        trim_session_messages(&mut session.messages);
                    }
                }
                break;
            }

            // Execute Tools
            let mut turn_tool_results = Vec::new();

            for tc in &turn_tool_calls {
                yield Ok(AgentStreamEvent::ToolStart { name: tc.name.clone(), id: tc.id.clone() });

                let result = if auto_execute || !is_destructive_tool(&tc.name) {
                     execute_tool_with_mode(state.clone(), &session_id, &tc.name, &tc.arguments, auto_execute).await
                } else {
                     // Create pending change instead
                     if let Some(pc) = create_pending_change(&session_id, tc, &workspace).await {
                         yield Ok(AgentStreamEvent::PendingChange(pc));
                         Ok(ToolResult {
                             tool_call_id: tc.id.clone(),
                             success: true,
                             output: "Pending change created. Waiting for user approval.".to_string(),
                             error: None
                         })
                     } else {
                         // Fallback if not a file change tool but marked destructive?
                          Ok(ToolResult {
                             tool_call_id: tc.id.clone(),
                             success: false,
                             output: String::new(),
                             error: Some("Tool requires approval but not handled as pending change".to_string())
                         })
                     }
                };

                match result {
                    Ok(mut res) => {
                         res.tool_call_id = tc.id.clone();
                         yield Ok(AgentStreamEvent::ToolEnd {
                             id: tc.id.clone(),
                             success: res.success,
                             output: res.output.clone(),
                             error: res.error.clone()
                         });
                         turn_tool_results.push(res);
                    }
                    Err(e) => {
                         yield Ok(AgentStreamEvent::ToolEnd {
                             id: tc.id.clone(),
                             success: false,
                             output: String::new(),
                             error: Some(e.to_string())
                         });
                         turn_tool_results.push(ToolResult {
                             tool_call_id: tc.id.clone(),
                             success: false,
                             output: String::new(),
                             error: Some(e.to_string()),
                         });
                    }
                }
            }

            let current_sig = turn_tool_calls
                .iter()
                .map(|c| format!("{}:{}", c.name, c.arguments))
                .collect::<Vec<_>>()
                .join("|");
            if last_tool_signature.as_deref() == Some(&current_sig) {
                repeated_tool_streak += 1;
            } else {
                last_tool_signature = Some(current_sig);
                repeated_tool_streak = 0;
            }

            let loop_warning = if repeated_tool_streak >= 2 {
                Some("You have repeated the exact same tool call multiple times in a row. Stop repeating it: either inspect the error output carefully, try a different approach, or conclude your response.")
            } else {
                None
            };

            turn_records.push(format_turn_record(
                loop_count,
                &turn_content,
                &turn_tool_calls,
                &turn_tool_results,
            ));
            let base_prompt_tokens = estimate_tokens(&base_prompt);
            let window_tokens = model_context_window(&config.model);
            let _ = micro_compact_turn_records(
                &session_id,
                &mut turn_records,
                base_prompt_tokens,
                window_tokens,
            );
            current_turn_prompt = build_agent_turn_prompt(&base_prompt, &turn_records, loop_warning);

            // Save this turn to session
            {
                let mut sessions = AGENT_SESSIONS.write().unwrap();
                if let Some(session) = sessions.get_mut(&session_id) {
                    session.messages.push(AgentMessage {
                         id: uuid::Uuid::new_v4().to_string(),
                         role: MessageRole::Assistant,
                         content: turn_content.clone(),
                         tool_calls: turn_tool_calls,
                         tool_results: turn_tool_results,
                         timestamp: Utc::now(),
                    });
                    trim_session_messages(&mut session.messages);
                }
            }
        }

        yield Ok(AgentStreamEvent::Done);
    };

    Box::pin(stream)
}

fn construct_system_prompt_sync(_workspace: &Path) -> String {
    "You are an AI programming assistant. Auto-indexing is enabled.".to_string()
}

fn ensure_session_exists_sync(session_id: &str, workspace: &Path) {
    let mut sessions = AGENT_SESSIONS.write().unwrap();
    if !sessions.contains_key(session_id) {
        sessions.insert(
            session_id.to_string(),
            AgentSession {
                id: session_id.to_string(),
                workspace_path: workspace.to_path_buf(),
                messages: Vec::new(),
                context: ProjectContext {
                    root_path: workspace.to_path_buf(),
                    project_type: "unknown".to_string(),
                    files: vec![],
                    recent_files: vec![],
                    symbols: vec![],
                    dependencies: vec![],
                    git_status: None,
                },
                tasks: Vec::new(),
                pending_operations: Vec::new(),
                created_at: Utc::now(),
                updated_at: Utc::now(),
                current_plan: None,
            },
        );
    }
}

async fn create_pending_change(
    session_id: &str,
    tool_call: &ToolCall,
    workspace: &Path,
) -> Option<PendingChange> {
    match tool_call.name.as_str() {
        "write_file" | "edit_file" => {
            let path = tool_call.arguments["path"].as_str()?;
            let full_path = resolve_path(workspace, path);

            let old_content = fs::read_to_string(&full_path).await.unwrap_or_default();
            let new_content = if tool_call.name == "write_file" {
                tool_call.arguments["content"].as_str()?.to_string()
            } else {
                let search = tool_call.arguments["search"].as_str()?;
                let replace = tool_call.arguments["replace"].as_str()?;
                let allow_multiple = tool_call.arguments.get("allow_multiple").and_then(|v| v.as_bool()).unwrap_or(false);
                smart_replace_in_content(&old_content, search, replace, allow_multiple)
                    .unwrap_or_else(|_| old_content.replace(search, replace))
            };

            let diff = generate_diff(path, &old_content, &new_content);

            let pc = PendingChange {
                id: uuid::Uuid::new_v4().to_string(),
                session_id: session_id.to_string(),
                diff,
                description: format!("{} {}", tool_call.name, path),
                tool_name: tool_call.name.clone(),
                status: PendingChangeStatus::Pending,
                created_at: Utc::now(),
            };

            // Store pending change
            let mut changes = PENDING_CHANGES.write().unwrap();
            changes.insert(pc.id.clone(), pc.clone());

            Some(pc)
        }
        _ => None,
    }
}

/// Apply a pending change
pub async fn apply_pending_change(change_id: &str) -> Result<String> {
    let change = {
        let changes = PENDING_CHANGES.read().unwrap();
        changes.get(change_id).cloned()
    };

    let change =
        change.ok_or_else(|| AppError::NotFound("Pending change not found".to_string()))?;

    let target_path = if let Some(session) = get_session(&change.session_id) {
        let resolved = resolve_path(&session.workspace_path, &change.diff.file_path);
        validate_path_in_workspace(&session.workspace_path, &resolved)?;
        resolved
    } else {
        PathBuf::from(&change.diff.file_path)
    };

    if let Some(parent) = target_path.parent() {
        fs::create_dir_all(parent)
            .await
            .map_err(|e| AppError::IOError(e.to_string()))?;
    }

    // Write the new content
    fs::write(&target_path, &change.diff.new_content as &str)
        .await
        .map_err(|e| AppError::IOError(e.to_string()))?;

    // Log for undo
    log_file_operation(
        &change.session_id,
        OperationType::ModifyFile,
        &target_path,
        Some(change.diff.old_content.clone()),
        Some(change.diff.new_content.clone()),
    );

    // Update status
    {
        let mut changes = PENDING_CHANGES.write().unwrap();
        if let Some(c) = changes.get_mut(change_id) {
            c.status = PendingChangeStatus::Accepted;
        }
    }

    Ok(format!("Applied changes to {}", change.diff.file_path))
}

/// Reject a pending change  
pub fn reject_pending_change(change_id: &str) -> Result<String> {
    let mut changes = PENDING_CHANGES.write().unwrap();
    if let Some(c) = changes.get_mut(change_id) {
        c.status = PendingChangeStatus::Rejected;
        Ok(format!("Rejected changes to {}", c.diff.file_path))
    } else {
        Err(AppError::NotFound("Pending change not found".to_string()))
    }
}

/// Get all pending changes for a session
pub fn get_pending_changes(session_id: &str) -> Vec<PendingChange> {
    let changes = PENDING_CHANGES.read().unwrap();
    changes
        .values()
        .filter(|c| c.session_id == session_id && c.status == PendingChangeStatus::Pending)
        .cloned()
        .collect()
}

pub async fn tool_create_plan(
    session_id: &str,
    description: &str,
    steps: Vec<serde_json::Value>,
) -> Result<String> {
    let num_steps = steps.len();
    let mut plan_steps = Vec::new();
    for (i, step) in steps.into_iter().enumerate() {
        let desc = step
            .get("description")
            .and_then(|v| v.as_str())
            .unwrap_or("No description");
        let tool = step.get("tool").and_then(|v| v.as_str()).unwrap_or("none");

        plan_steps.push(PlanStep {
            id: format!("step-{}", i + 1),
            description: desc.to_string(),
            tool: tool.to_string(),
            arguments: serde_json::json!({}),
            status: StepStatus::Pending,
            result: None,
        });
    }

    let plan = ExecutionPlan {
        id: uuid::Uuid::new_v4().to_string(),
        description: description.to_string(),
        steps: plan_steps,
        current_step: 0,
        status: PlanStatus::Queued,
    };

    // Update session
    if let Ok(mut sessions) = AGENT_SESSIONS.write() {
        if let Some(session) = sessions.get_mut(session_id) {
            session.current_plan = Some(plan);
            session.updated_at = Utc::now();
        }
    }

    Ok(format!("Plan created: {}. {} steps queued. Please confirm with the user before proceeding with execution tools.", description, num_steps))
}

async fn tool_search_rag(
    state: Arc<TokioRwLock<crate::state::AppState>>,
    args: &serde_json::Value,
) -> Result<String> {
    let query = args["query"]
        .as_str()
        .ok_or_else(|| AppError::ValidationError("query is required".to_string()))?;
    let limit = args["limit"].as_u64().unwrap_or(5) as usize;

    let st = state.read().await;
    let mut guard: tokio::sync::MutexGuard<Option<crate::rag::RagEngine>> =
        st.rag_engine.lock().await;
    let engine = guard.as_mut().ok_or_else(|| {
        AppError::InternalError(
            "RAG engine not initialized. Please start indexing first.".to_string(),
        )
    })?;

    let results = engine.search_with_expansion(query, limit)?;
    let mut output = format!("Semantic search results for '{}':\n\n", query);

    for (chunk, score) in results {
        output.push_str(&format!(
            "--- {} (score: {:.2}) ---\n{}\n\n",
            chunk.file_path, score, chunk.content
        ));
    }

    Ok(output)
}

async fn tool_execute_command(workspace: &Path, args: &serde_json::Value) -> Result<String> {
    let command = args["command"]
        .as_str()
        .ok_or_else(|| AppError::ValidationError("command is required".to_string()))?;
    let description = args["description"].as_str();
    let timeout_secs = args["timeout_seconds"]
        .as_u64()
        .or_else(|| args["timeout"].as_u64());

    // Reuse the same secure execution path
    secure_execute_command(workspace, command, description, timeout_secs).await
}

// ==========================================
// SubAgent Execution Engine
// ==========================================

/// Execute a subagent with its own provider/model/tool configuration.
/// Creates an isolated session, resolves the subagent's AI config (inheriting
/// from parent where not specified), and runs the agent loop.
pub async fn execute_subagent(
    state: Arc<TokioRwLock<crate::state::AppState>>,
    parent_session_id: &str,
    subagent_config: &SubAgentConfig,
    task: &str,
    parent_ai_config: &AIConfig,
) -> Result<ChatResponse> {
    // 1. Resolve the subagent's own AIConfig
    let subagent_ai_config = resolve_subagent_config(subagent_config, parent_ai_config);

    // 2. Get parent workspace
    let workspace = get_session(parent_session_id)
        .map(|s| s.workspace_path.clone())
        .ok_or_else(|| AppError::NotFound("Parent session not found".to_string()))?;

    // 3. Create isolated subagent session
    let subagent_session_id = format!("{}_sub_{}", parent_session_id, subagent_config.name);
    let _ = ensure_session_exists_sync(&subagent_session_id, &workspace);

    // 4. Build the subagent request with role-specific system prompt
    let system_prompt = subagent_config.system_prompt.clone()
        .unwrap_or_else(|| format!(
            "You are a specialized {} agent. Your role: {}. Execute the given task efficiently.",
            subagent_config.role, subagent_config.name
        ));
    let full_task = format!("{}\n\nTask: {}", system_prompt, task);

    let request = ChatRequest {
        session_id: subagent_session_id.clone(),
        message: full_task,
        editor_context: None,
        provider: Some(subagent_ai_config.provider.clone()),
        model: Some(subagent_ai_config.model.clone()),
        api_key: Some(subagent_ai_config.api_key.clone()),
        cloud_base_url: subagent_ai_config.proxy_base_url.clone(),
        auto_execute: true,
        budget: subagent_config.budget.clone(),
    };

    // 5. Run the agent loop with the subagent's resolved config
    let response = enhanced_chat(state, request, &subagent_ai_config).await?;

    tracing::info!(
        "SubAgent '{}' completed: provider={}, model={}, tools={}, stop={:?}",
        subagent_config.name,
        subagent_ai_config.provider,
        subagent_ai_config.model,
        response.tool_calls.len(),
        response.stop_reason,
    );

    Ok(response)
}

/// Update the global policy engine at runtime.
pub fn update_policy_engine(engine: PolicyEngine) {
    let mut global = POLICY_ENGINE.write().unwrap();
    *global = engine;
}

/// Get a model recommendation for a task description.
pub fn get_model_recommendation(description: &str, tools: &[String]) -> ModelRecommendation {
    crate::agent_kernel::recommend_model_for_task(description, tools)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extract_tool_calls_handles_embedded_backticks_and_nested_braces() {
        let response = r##"I will write the documentation file now.
```json
[
  {
    "name": "write_file",
    "arguments": {
      "path": "docs/README.md",
      "content": "# Example\n```rust\nfn main() { println!(\"{}\", 42); }\n```\nDone."
    }
  }
]
```
Let me know once written."##;

        let (calls, cleaned) = extract_tool_calls(response);
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].name, "write_file");
        assert_eq!(calls[0].arguments["path"], "docs/README.md");
        assert!(calls[0].arguments["content"]
            .as_str()
            .unwrap()
            .contains("```rust"));
        assert!(cleaned.contains("I will write the documentation file now."));
    }

    #[test]
    fn smart_replace_handles_line_numbers_and_indentation_drift() {
        let original = "fn calculate() {\n    let x = 10;\n    let y = 20;\n    return x + y;\n}\n";
        // Search has accidental line number prefixes and 2-space indentation instead of 4-space
        let search = "2:   let x = 10;\n3:   let y = 20;";
        let replace = "    let x = 100;\n    let y = 200;";
        let updated = smart_replace_in_content(original, search, replace, false).unwrap();
        assert!(updated.contains("let x = 100;"));
        assert!(updated.contains("let y = 200;"));
    }

    #[test]
    fn validate_path_allows_new_nested_dirs_and_blocks_traversal() {
        let temp_dir = std::env::temp_dir().join(format!("mc_ws_{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&temp_dir).unwrap();

        let nested_new = resolve_path(&temp_dir, "src/components/deep/NewWidget.tsx");
        assert!(validate_path_in_workspace(&temp_dir, &nested_new).is_ok());

        let traversal = resolve_path(&temp_dir, "../outside.txt");
        assert!(validate_path_in_workspace(&temp_dir, &traversal).is_err());

        let _ = std::fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn build_agent_turn_prompt_retains_multiple_turns() {
        let base = "System: Test\n\nUser: Fix bug";
        let t1 = format_turn_record(
            1,
            "Reading file",
            &[ToolCall {
                id: "1".to_string(),
                name: "read_file".to_string(),
                arguments: serde_json::json!({"path": "src/main.rs"}),
            }],
            &[ToolResult {
                tool_call_id: "1".to_string(),
                success: true,
                output: "fn main() {}".to_string(),
                error: None,
            }],
        );
        let t2 = format_turn_record(
            2,
            "Running cargo check",
            &[ToolCall {
                id: "2".to_string(),
                name: "run_command".to_string(),
                arguments: serde_json::json!({"command": "cargo check"}),
            }],
            &[ToolResult {
                tool_call_id: "2".to_string(),
                success: false,
                output: String::new(),
                error: Some("error[E0425]: cannot find value `x`".to_string()),
            }],
        );
        let prompt = build_agent_turn_prompt(base, &[t1, t2], Some("Avoid repeating tool"));
        assert!(prompt.contains("=== Turn 1 ==="));
        assert!(prompt.contains("=== Turn 2 ==="));
        assert!(prompt.contains("error[E0425]"));
        assert!(prompt.contains("Avoid repeating tool"));
    }

    #[test]
    fn first_call_tool_guidance_injects_once_per_session() {
        let session_id = format!("test_guid_{}", uuid::Uuid::new_v4());
        let g1 = take_first_call_guidance(&session_id, "read_file");
        assert!(g1.is_some());
        assert!(g1.unwrap().contains("SHA-256 repeat-read deduplication"));

        // Second call in the same session should return None
        let g2 = take_first_call_guidance(&session_id, "read_file");
        assert!(g2.is_none());

        // Different tool in the same session should still return guidance once
        let g3 = take_first_call_guidance(&session_id, "edit_file");
        assert!(g3.is_some());

        let audit = get_session_token_audit(&session_id);
        assert_eq!(audit.first_call_guidances_injected, 2);
    }

    #[test]
    fn thai_and_multilingual_token_estimation_and_window_clamping() {
        let session_id = format!("test_clamp_{}", uuid::Uuid::new_v4());
        let thai_text = "สวัสดีครับ ทดสอบการคำนวณโทเคนภาษาไทยสำหรับระบบเอเจนต์";
        let ascii_text = "hello world token estimation test for agent";
        // Thai characters should be weighted more densely (~1 token per 2 chars)
        assert!(estimate_tokens(thai_text) > thai_text.chars().count() / 3);
        assert!(estimate_tokens(ascii_text) <= (ascii_text.chars().count() + 3) / 4);

        // When prompt is near the 64k window of deepseek, max_tokens should clamp down safely
        let clamped = clamp_max_tokens_to_window(&session_id, "deepseek-chat", 61_500, Some(8_192));
        assert!(clamped <= 1_476 && clamped >= 256);
        let audit = get_session_token_audit(&session_id);
        assert_eq!(audit.window_clamps_applied, 1);
    }

    #[test]
    fn batch_micro_compaction_triggers_at_60_percent_and_preserves_recent_turns() {
        let session_id = format!("test_mc_{}", uuid::Uuid::new_v4());
        let big_output = "fn line_of_code() { println!(\"hello\"); }\n".repeat(40);
        let mut turns = vec![
            format_turn_record(
                1,
                "Old turn 1",
                &[ToolCall {
                    id: "1".to_string(),
                    name: "read_file".to_string(),
                    arguments: serde_json::json!({"path": "a.rs"}),
                }],
                &[ToolResult {
                    tool_call_id: "1".to_string(),
                    success: true,
                    output: big_output.clone(),
                    error: None,
                }],
            ),
            format_turn_record(2, "Turn 2", &[], &[]),
            format_turn_record(3, "Turn 3", &[], &[]),
            format_turn_record(
                4,
                "Recent turn 4",
                &[ToolCall {
                    id: "4".to_string(),
                    name: "read_file".to_string(),
                    arguments: serde_json::json!({"path": "b.rs"}),
                }],
                &[ToolResult {
                    tool_call_id: "4".to_string(),
                    success: true,
                    output: big_output.clone(),
                    error: None,
                }],
            ),
        ];

        // Below 60% of 100k window -> 0 tokens compacted
        let saved_below = micro_compact_turn_records(&session_id, &mut turns, 1_000, 100_000);
        assert_eq!(saved_below, 0);

        // Above 60% of 2k window -> Turn 1 is micro-compacted while Recent Turn 4 is preserved intact
        let saved_above = micro_compact_turn_records(&session_id, &mut turns, 1_200, 2_000);
        assert!(saved_above > 0);
        assert!(turns[0].contains("[Micro-compacted tool output"));
        assert!(!turns[3].contains("[Micro-compacted tool output"));
    }

    #[tokio::test]
    async fn stale_file_write_guard_and_repeat_read_dedup_and_session_receipt() {
        let temp_dir = std::env::temp_dir().join(format!("mc_guard_{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&temp_dir).unwrap();
        let session_id = create_session(&temp_dir.to_string_lossy()).unwrap();

        let file_path = temp_dir.join("lib.rs");
        std::fs::write(&file_path, "pub fn v1() -> i32 { 1 }\n").unwrap();

        // 1. First read records file stamp
        let r1 = tool_read_file(
            &session_id,
            &temp_dir,
            &serde_json::json!({"path": "lib.rs"}),
        )
        .await
        .unwrap();
        assert!(r1.contains("pub fn v1()"));
        assert!(!r1.contains("[Repeat-Read Notice"));

        // 2. Second identical read triggers SHA-256 Repeat-Read Notice
        let r2 = tool_read_file(
            &session_id,
            &temp_dir,
            &serde_json::json!({"path": "lib.rs"}),
        )
        .await
        .unwrap();
        assert!(r2.contains("[Repeat-Read Notice:"));

        // 3. Simulate external edit in the IDE editor without agent knowing
        std::fs::write(&file_path, "pub fn v2_user_edited() -> i32 { 2 }\n").unwrap();

        // 4. Agent attempting edit_file or write_file on stale file must be blocked!
        let stale_err = tool_write_file(
            &session_id,
            &temp_dir,
            &serde_json::json!({"path": "lib.rs", "content": "pub fn clobber() {}\n"}),
        )
        .await;
        assert!(stale_err.is_err());
        assert!(stale_err
            .unwrap_err()
            .to_string()
            .contains("Stale-file write guard"));

        // 5. Re-reading refreshes the stamp and allows write + emits Session Edit Receipt
        let _ = tool_read_file(
            &session_id,
            &temp_dir,
            &serde_json::json!({"path": "lib.rs"}),
        )
        .await
        .unwrap();
        let ok_write = tool_write_file(
            &session_id,
            &temp_dir,
            &serde_json::json!({"path": "lib.rs", "content": "pub fn v3_clean() -> i32 { 3 }\n"}),
        )
        .await
        .unwrap();
        assert!(ok_write.contains("[Session Edit Receipt: 1 file(s) touched in session: lib.rs]"));

        let audit = get_session_token_audit(&session_id);
        assert_eq!(audit.repeat_read_count, 1);
        assert_eq!(audit.stale_write_blocks, 1);

        let _ = std::fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn design_check_and_security_audit_detect_slop_and_cwe() {
        let ui_code = r#"
.hero-title {
    background: linear-gradient(90deg, #6366f1, #8b5cf6, #a855f7);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    transition: all 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
}
/* Supercharge your workflow with next-generation AI-powered tools */
"#;
        let design_issues = lint_ui_design(Path::new("src/App.css"), ui_code);
        assert!(design_issues.iter().any(|d| d.rule_id == "purple-blue-ai-palette"));
        assert!(design_issues.iter().any(|d| d.rule_id == "ai-gradient-text"));
        assert!(design_issues.iter().any(|d| d.rule_id == "bounce-spring-overuse"));
        assert!(design_issues.iter().any(|d| d.rule_id == "generic-ai-copy"));

        let vuln_code = r#"
fn query_user(db: &Db, name: &str) {
    let sql = format!("SELECT * FROM users WHERE username = '{}'", name);
    let api_key = "sk-proj-1234567890abcdef1234567890abcdef";
}
"#;
        let sec_issues = scan_code_security(Path::new("src/db.rs"), vuln_code);
        assert!(sec_issues.iter().any(|s| s.cwe_id == "CWE-89"));
        assert!(sec_issues.iter().any(|s| s.cwe_id == "CWE-798"));
    }
}

