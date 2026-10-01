//! Durable control plane for every MicroCode agent model.
//!
//! The kernel deliberately does not call an LLM or execute a tool. It owns the
//! lifecycle around those fallible operations: durable checkpoints, bounded
//! history, retries, progress/cycle detection, plan scheduling and explicit
//! terminal states. Swift, MCP and model providers all speak this protocol.

use axum::{
    extract::Path as AxumPath,
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use chrono::{DateTime, Utc};
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    collections::{HashMap, VecDeque},
    path::PathBuf,
    sync::Arc,
};
use tokio::sync::RwLock;
use uuid::Uuid;

const MAX_RESIDENT_RUNS: usize = 64;
const MAX_RECENT_EVENTS: usize = 64;
const MAX_RECENT_FINGERPRINTS: usize = 24;
const MAX_TEXT_CHARS: usize = 8_000;
const REPEAT_REPLAN_THRESHOLD: usize = 3;
// A no-tool response is recoverable model behaviour, not a user-facing
// terminal condition. The foreground runner and background resume service
// own retries; only explicit user cancellation or an authority requirement
// may make a run terminal.
const MAX_REPLANS_WITHOUT_PROGRESS: u32 = 8;
const MAX_RETRY_DELAY_MS: u64 = 30_000;

static AGENT_KERNEL: Lazy<AgentKernel> = Lazy::new(AgentKernel::default);

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum RunState {
    Queued,
    Planning,
    Ready,
    WaitingModel,
    Executing,
    Observing,
    Verifying,
    Replanning,
    WaitingRetry,
    Blocked,
    Completed,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PlanNodeState {
    Pending,
    Ready,
    Running,
    Verifying,
    Completed,
    Failed,
    Blocked,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanNode {
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub dependencies: Vec<String>,
    #[serde(default)]
    pub verification: String,
    #[serde(default)]
    pub required_tools: Vec<String>,
    #[serde(default)]
    pub owner: Option<String>,
    pub state: PlanNodeState,
    #[serde(default)]
    pub attempts: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KernelEvent {
    pub sequence: u64,
    pub at: DateTime<Utc>,
    pub kind: String,
    #[serde(default)]
    pub node_id: Option<String>,
    #[serde(default)]
    pub tool_name: Option<String>,
    #[serde(default)]
    pub summary: String,
    #[serde(default)]
    pub success: Option<bool>,
    #[serde(default)]
    pub made_progress: bool,
    #[serde(default)]
    pub fingerprint: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentRun {
    pub id: String,
    #[serde(default)]
    pub parent_run_id: Option<String>,
    pub objective: String,
    pub workspace: String,
    pub provider: String,
    pub model: String,
    pub state: RunState,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    #[serde(default)]
    pub tools: Vec<String>,
    #[serde(default)]
    pub skills: Vec<String>,
    #[serde(default)]
    pub mcp_servers: Vec<String>,
    #[serde(default)]
    pub plan: Vec<PlanNode>,
    #[serde(default)]
    pub recent_events: VecDeque<KernelEvent>,
    #[serde(default)]
    pub recent_fingerprints: VecDeque<String>,
    #[serde(default)]
    pub sequence: u64,
    #[serde(default)]
    pub retry_attempt: u32,
    #[serde(default)]
    pub no_progress_streak: u32,
    #[serde(default)]
    pub error_streak: u32,
    #[serde(default)]
    pub replans_without_progress: u32,
    #[serde(default)]
    pub last_error: Option<String>,
    #[serde(default)]
    pub terminal_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateRunRequest {
    #[serde(default)]
    pub run_id: Option<String>,
    #[serde(default)]
    pub parent_run_id: Option<String>,
    pub objective: String,
    #[serde(default)]
    pub workspace: String,
    #[serde(default)]
    pub provider: String,
    #[serde(default)]
    pub model: String,
    #[serde(default)]
    pub tools: Vec<String>,
    #[serde(default)]
    pub skills: Vec<String>,
    #[serde(default)]
    pub mcp_servers: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObserveRequest {
    pub kind: String,
    #[serde(default)]
    pub node_id: Option<String>,
    #[serde(default)]
    pub tool_name: Option<String>,
    #[serde(default)]
    pub arguments: Value,
    #[serde(default)]
    pub success: Option<bool>,
    #[serde(default)]
    pub output: String,
    #[serde(default)]
    pub error: String,
    #[serde(default)]
    pub made_progress: bool,
    #[serde(default)]
    pub transient: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SetPlanRequest {
    pub nodes: Vec<PlanNode>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KernelDirective {
    pub action: String,
    pub reason: String,
    pub state: RunState,
    #[serde(default)]
    pub retry_after_ms: Option<u64>,
    #[serde(default)]
    pub ready_nodes: Vec<String>,
    #[serde(default)]
    pub suggested_prompt: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KernelResponse {
    pub run: AgentRun,
    pub directive: KernelDirective,
}

#[derive(Clone)]
pub struct AgentKernel {
    root: PathBuf,
    runs: Arc<RwLock<HashMap<String, AgentRun>>>,
}

impl Default for AgentKernel {
    fn default() -> Self {
        let root = std::env::var_os("MICROCODE_AGENT_KERNEL_DIR")
            .map(PathBuf::from)
            .or_else(|| dirs::data_dir().map(|p| p.join("MicroCode").join("agent-kernel")))
            .unwrap_or_else(|| std::env::temp_dir().join("microcode-agent-kernel"));
        Self::new(root)
    }
}

impl AgentKernel {
    pub fn new(root: PathBuf) -> Self {
        Self {
            root,
            runs: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub async fn create_or_resume(
        &self,
        request: CreateRunRequest,
    ) -> Result<KernelResponse, KernelError> {
        let id = sanitize_id(
            request
                .run_id
                .unwrap_or_else(|| Uuid::new_v4().to_string())
                .as_str(),
        )?;
        if let Some(existing) = self.load_run(&id).await? {
            return Ok(KernelResponse {
                directive: directive_for(&existing, "resume", "Recovered durable agent checkpoint"),
                run: existing,
            });
        }

        let now = Utc::now();
        let run = AgentRun {
            id: id.clone(),
            parent_run_id: request.parent_run_id.map(|v| compact(&v)),
            objective: compact(&request.objective),
            workspace: compact(&request.workspace),
            provider: compact(&request.provider),
            model: compact(&request.model),
            state: RunState::Planning,
            created_at: now,
            updated_at: now,
            tools: bounded_unique(request.tools, 512),
            skills: bounded_unique(request.skills, 128),
            mcp_servers: bounded_unique(request.mcp_servers, 128),
            plan: Vec::new(),
            recent_events: VecDeque::new(),
            recent_fingerprints: VecDeque::new(),
            sequence: 0,
            retry_attempt: 0,
            no_progress_streak: 0,
            error_streak: 0,
            replans_without_progress: 0,
            last_error: None,
            terminal_reason: None,
        };
        self.persist(&run, None).await?;
        self.cache(run.clone()).await;
        Ok(KernelResponse {
            directive: directive_for(
                &run,
                "plan",
                "Create or load a verifiable plan before execution",
            ),
            run,
        })
    }

    pub async fn set_plan(
        &self,
        id: &str,
        mut nodes: Vec<PlanNode>,
    ) -> Result<KernelResponse, KernelError> {
        validate_plan(&nodes)?;
        let mut run = self.require_run(id).await?;
        for node in &mut nodes {
            node.title = compact(&node.title);
            node.description = compact(&node.description);
            node.verification = compact(&node.verification);
            if node.owner.as_deref().unwrap_or("").trim().is_empty() {
                node.owner = recommend_owner(node);
            }
            if node.dependencies.is_empty() {
                node.state = PlanNodeState::Ready;
            } else {
                node.state = PlanNodeState::Pending;
            }
        }
        run.plan = nodes;
        run.state = RunState::Ready;
        run.updated_at = Utc::now();
        let event = run.push_event(
            "plan_set",
            None,
            None,
            "Plan accepted",
            Some(true),
            true,
            None,
        );
        let ready = ready_node_ids(&run.plan);
        self.persist_and_cache(&run, Some(&event)).await?;
        Ok(KernelResponse {
            directive: KernelDirective {
                action: "continue".into(),
                reason: "Plan is valid; dependency-free work is ready".into(),
                state: run.state.clone(),
                retry_after_ms: None,
                ready_nodes: ready,
                suggested_prompt: None,
            },
            run,
        })
    }

    pub async fn observe(
        &self,
        id: &str,
        request: ObserveRequest,
    ) -> Result<KernelResponse, KernelError> {
        let mut run = self.require_run(id).await?;
        if matches!(run.state, RunState::Cancelled | RunState::Completed) {
            let action = if run.state == RunState::Completed {
                "complete"
            } else {
                "cancelled"
            };
            return Ok(KernelResponse {
                directive: directive_for(&run, action, "Run is already terminal"),
                run,
            });
        }

        let kind = request.kind.trim().to_ascii_lowercase();
        let summary = if !request.error.is_empty() {
            compact(&request.error)
        } else {
            compact(&request.output)
        };
        let fingerprint = request
            .tool_name
            .as_ref()
            .map(|name| tool_fingerprint(name, &request.arguments));
        let progress =
            request.made_progress || inferred_progress(&kind, request.success, &request.output);

        if progress {
            run.no_progress_streak = 0;
            run.error_streak = 0;
            run.retry_attempt = 0;
            run.replans_without_progress = 0;
        } else {
            run.no_progress_streak = run.no_progress_streak.saturating_add(1);
        }
        if request.success == Some(false) || !request.error.is_empty() {
            run.error_streak = run.error_streak.saturating_add(1);
            run.last_error = Some(summary.clone());
        }
        if let Some(fp) = fingerprint.clone() {
            push_bounded(&mut run.recent_fingerprints, fp, MAX_RECENT_FINGERPRINTS);
        }

        update_plan_node(
            &mut run.plan,
            request.node_id.as_deref(),
            &kind,
            request.success,
        );
        run.state = state_for_event(&kind, request.success, request.transient);
        run.updated_at = Utc::now();
        let event = run.push_event(
            &kind,
            request.node_id.clone(),
            request.tool_name.clone(),
            &summary,
            request.success,
            progress,
            fingerprint,
        );

        let directive = evaluate(&mut run, &request);
        self.persist_and_cache(&run, Some(&event)).await?;
        Ok(KernelResponse { run, directive })
    }

    pub async fn get(&self, id: &str) -> Result<KernelResponse, KernelError> {
        let run = self.require_run(id).await?;
        let directive = if run.state == RunState::Blocked {
            directive_for(
                &run,
                "blocked",
                run.terminal_reason
                    .as_deref()
                    .unwrap_or("Run needs attention"),
            )
        } else if run.state == RunState::Completed {
            directive_for(&run, "complete", "Objective was verified")
        } else {
            directive_for(&run, "resume", "Continue from the durable checkpoint")
        };
        Ok(KernelResponse { run, directive })
    }

    pub async fn cancel(&self, id: &str) -> Result<KernelResponse, KernelError> {
        let mut run = self.require_run(id).await?;
        run.state = RunState::Cancelled;
        run.terminal_reason = Some("Cancelled by user".into());
        let event = run.push_event(
            "cancelled",
            None,
            None,
            "Cancelled by user",
            Some(true),
            false,
            None,
        );
        self.persist_and_cache(&run, Some(&event)).await?;
        Ok(KernelResponse {
            directive: directive_for(&run, "cancelled", "Cancelled by user"),
            run,
        })
    }

    async fn require_run(&self, id: &str) -> Result<AgentRun, KernelError> {
        let id = sanitize_id(id)?;
        if let Some(run) = self.runs.read().await.get(&id).cloned() {
            return Ok(run);
        }
        self.load_run(&id).await?.ok_or(KernelError::NotFound(id))
    }

    async fn load_run(&self, id: &str) -> Result<Option<AgentRun>, KernelError> {
        let path = self.snapshot_path(id);
        let data = match tokio::fs::read(&path).await {
            Ok(data) => data,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error.into()),
        };
        let run: AgentRun = serde_json::from_slice(&data)?;
        self.cache(run.clone()).await;
        Ok(Some(run))
    }

    async fn persist_and_cache(
        &self,
        run: &AgentRun,
        event: Option<&KernelEvent>,
    ) -> Result<(), KernelError> {
        self.persist(run, event).await?;
        self.cache(run.clone()).await;
        Ok(())
    }

    async fn persist(
        &self,
        run: &AgentRun,
        event: Option<&KernelEvent>,
    ) -> Result<(), KernelError> {
        tokio::fs::create_dir_all(&self.root).await?;
        if let Some(event) = event {
            let mut line = serde_json::to_vec(event)?;
            line.push(b'\n');
            use tokio::io::AsyncWriteExt;
            let mut file = tokio::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(self.event_path(&run.id))
                .await?;
            file.write_all(&line).await?;
            file.flush().await?;
        }

        let bytes = serde_json::to_vec(run)?;
        let target = self.snapshot_path(&run.id);
        let temp = self.root.join(format!(".{}.snapshot.tmp", run.id));
        tokio::fs::write(&temp, bytes).await?;
        tokio::fs::rename(&temp, &target).await?;
        Ok(())
    }

    async fn cache(&self, run: AgentRun) {
        let mut runs = self.runs.write().await;
        runs.insert(run.id.clone(), run);
        if runs.len() > MAX_RESIDENT_RUNS {
            if let Some(oldest) = runs
                .values()
                .min_by_key(|run| run.updated_at)
                .map(|run| run.id.clone())
            {
                runs.remove(&oldest);
            }
        }
    }

    fn snapshot_path(&self, id: &str) -> PathBuf {
        self.root.join(format!("{}.snapshot.json", id))
    }
    fn event_path(&self, id: &str) -> PathBuf {
        self.root.join(format!("{}.events.jsonl", id))
    }
}

fn recommend_owner(node: &PlanNode) -> Option<String> {
    let haystack = format!(
        "{} {} {} {}",
        node.title,
        node.description,
        node.verification,
        node.required_tools.join(" ")
    )
    .to_ascii_lowercase();

    let owner = if contains_any(
        &haystack,
        &[
            "security",
            "permission",
            "auth",
            "secret",
            "performance",
            "memory",
            "benchmark",
        ],
    ) {
        "security_auditor"
    } else if contains_any(
        &haystack,
        &[
            "test",
            "verify",
            "build",
            "compiler",
            "coverage",
            "benchmark",
        ],
    ) {
        "test_runner"
    } else if contains_any(
        &haystack,
        &[
            "bug",
            "crash",
            "error",
            "diagnose",
            "root cause",
            "loop",
            "deadlock",
        ],
    ) {
        "bug_hunter"
    } else if contains_any(
        &haystack,
        &[
            "swiftui",
            "frontend",
            "interface",
            "layout",
            "view",
            "css",
            "react",
        ],
    ) {
        "frontend_engineer"
    } else if contains_any(
        &haystack,
        &[
            "backend",
            "database",
            "api",
            "rust",
            "server",
            "storage",
            "websocket",
        ],
    ) {
        "backend_engineer"
    } else if contains_any(
        &haystack,
        &[
            "architecture",
            "design",
            "contract",
            "research",
            "inspect",
            "plan",
        ],
    ) {
        "architect"
    } else {
        return None;
    };
    Some(owner.to_string())
}

fn contains_any(haystack: &str, needles: &[&str]) -> bool {
    needles.iter().any(|needle| haystack.contains(needle))
}

impl AgentRun {
    fn push_event(
        &mut self,
        kind: &str,
        node_id: Option<String>,
        tool_name: Option<String>,
        summary: &str,
        success: Option<bool>,
        made_progress: bool,
        fingerprint: Option<String>,
    ) -> KernelEvent {
        self.sequence = self.sequence.saturating_add(1);
        let event = KernelEvent {
            sequence: self.sequence,
            at: Utc::now(),
            kind: compact(kind),
            node_id: node_id.map(|value| compact(&value)),
            tool_name: tool_name.map(|value| compact(&value)),
            summary: compact(summary),
            success,
            made_progress,
            fingerprint,
        };
        push_bounded(&mut self.recent_events, event.clone(), MAX_RECENT_EVENTS);
        event
    }
}

fn evaluate(run: &mut AgentRun, request: &ObserveRequest) -> KernelDirective {
    if request.kind == "cancelled" {
        run.state = RunState::Cancelled;
        return directive_for(run, "cancelled", "Cancelled by user");
    }

    if request.kind == "verification"
        && request.success == Some(true)
        && plan_is_complete_or_empty(&run.plan)
    {
        run.state = RunState::Completed;
        run.terminal_reason = Some("Objective and verification criteria passed".into());
        return directive_for(
            run,
            "complete",
            "Objective and verification criteria passed",
        );
    }

    if request.kind == "model_no_tool" && run.no_progress_streak >= 3 {
        run.replans_without_progress = run.replans_without_progress.saturating_add(1);
        if run.replans_without_progress >= MAX_REPLANS_WITHOUT_PROGRESS {
            run.replans_without_progress = 0;
            run.retry_attempt = run.retry_attempt.saturating_add(1);
            run.state = RunState::WaitingRetry;
            let delay = retry_delay(run.retry_attempt);
            return KernelDirective {
                action: "retry".into(),
                reason: "The model did not issue an executable action; retrying from the durable checkpoint with a fresh strategy".into(),
                state: run.state.clone(),
                retry_after_ms: Some(delay),
                ready_nodes: ready_node_ids(&run.plan),
                suggested_prompt: Some("Resume from the durable plan. Inspect the latest real tool evidence, choose a different executable action, and do not return a progress-only answer.".into()),
            };
        }
        run.state = RunState::Replanning;
        return KernelDirective {
            action: "replan".into(),
            reason: "The model stopped without completion evidence".into(),
            state: run.state.clone(),
            retry_after_ms: None,
            ready_nodes: ready_node_ids(&run.plan),
            suggested_prompt: Some(
                "The last responses contained no executable action. Change strategy, call the required tool, or report the exact external blocker."
                    .into(),
            ),
        };
    }

    if request.transient && (request.success == Some(false) || !request.error.is_empty()) {
        run.retry_attempt = run.retry_attempt.saturating_add(1);
        run.state = RunState::WaitingRetry;
        let delay = retry_delay(run.retry_attempt);
        return KernelDirective {
            action: "retry".into(),
            reason: "Transient provider or tool failure; durable state was preserved".into(),
            state: run.state.clone(),
            retry_after_ms: Some(delay),
            ready_nodes: ready_node_ids(&run.plan),
            suggested_prompt: Some(format!(
                "Retry the interrupted operation after {} ms. Do not repeat completed work.",
                delay
            )),
        };
    }

    if is_auth_or_authority_error(&request.error) {
        run.state = RunState::Blocked;
        run.terminal_reason = Some(compact(&request.error));
        return directive_for(
            run,
            "blocked",
            "Authentication or user authority is required",
        );
    }

    if detects_cycle(&run.recent_fingerprints)
        || repeated_tail(&run.recent_fingerprints) >= REPEAT_REPLAN_THRESHOLD
    {
        run.replans_without_progress = run.replans_without_progress.saturating_add(1);
        run.recent_fingerprints.clear();
        if run.replans_without_progress >= MAX_REPLANS_WITHOUT_PROGRESS {
            run.replans_without_progress = 0;
            run.retry_attempt = run.retry_attempt.saturating_add(1);
            run.state = RunState::WaitingRetry;
            let delay = retry_delay(run.retry_attempt);
            return KernelDirective {
                action: "retry".into(),
                reason: "Repeated action cycle detected; waiting before resuming from the durable checkpoint".into(),
                state: run.state.clone(),
                retry_after_ms: Some(delay),
                ready_nodes: ready_node_ids(&run.plan),
                suggested_prompt: Some("Do not repeat an earlier command. Re-read its observed result, select a different diagnostic or repair action, then verify it.".into()),
            };
        }
        run.state = RunState::Replanning;
        let reason = "Repeated action cycle detected; completed actions must not be repeated";
        return KernelDirective {
            action: "replan".into(),
            reason: reason.into(),
            state: run.state.clone(),
            retry_after_ms: None,
            ready_nodes: ready_node_ids(&run.plan),
            suggested_prompt: Some(format!("Kernel loop guard: {}. Inspect the latest evidence, change strategy, and update the plan before another tool call.", reason)),
        };
    }

    if request.kind == "final_candidate" || request.kind == "model_no_tool" {
        if plan_is_complete_or_empty(&run.plan) || has_observed_work(run) || run.no_progress_streak == 0 {
            run.state = RunState::Completed;
            run.terminal_reason = Some("Objective completed successfully".into());
            return directive_for(
                run,
                "complete",
                "Objective completed successfully",
            );
        }

        run.state = RunState::Verifying;
        return KernelDirective {
            action: "verify".into(),
            reason: "A natural-language answer is not completion evidence".into(),
            state: run.state.clone(),
            retry_after_ms: None,
            ready_nodes: ready_node_ids(&run.plan),
            suggested_prompt: Some("Run the deterministic verification criteria for the objective. Mark complete only when they pass.".into()),
        };
    }

    if request.success == Some(false) && run.error_streak >= 2 {
        run.replans_without_progress = run.replans_without_progress.saturating_add(1);
        if run.replans_without_progress >= MAX_REPLANS_WITHOUT_PROGRESS {
            run.replans_without_progress = 0;
            run.retry_attempt = run.retry_attempt.saturating_add(1);
            run.state = RunState::WaitingRetry;
            let delay = retry_delay(run.retry_attempt);
            return KernelDirective {
                action: "retry".into(),
                reason: "The operation failed repeatedly; retaining evidence and retrying with a new strategy".into(),
                state: run.state.clone(),
                retry_after_ms: Some(delay),
                ready_nodes: ready_node_ids(&run.plan),
                suggested_prompt: Some("Use the latest failing output as the source of truth. Diagnose the first actionable error, apply one scoped repair, then execute verification.".into()),
            };
        }
        run.state = RunState::Replanning;
        return KernelDirective {
            action: "replan".into(),
            reason: "The current operation failed repeatedly".into(),
            state: run.state.clone(),
            retry_after_ms: None,
            ready_nodes: ready_node_ids(&run.plan),
            suggested_prompt: Some("Do not call the same failing operation again. Diagnose the first error and choose an alternative.".into()),
        };
    }

    run.state = RunState::Ready;
    KernelDirective {
        action: "continue".into(),
        reason: if request.made_progress {
            "Progress checkpointed"
        } else {
            "Awaiting the next necessary action"
        }
        .into(),
        state: run.state.clone(),
        retry_after_ms: None,
        ready_nodes: ready_node_ids(&run.plan),
        suggested_prompt: None,
    }
}

fn directive_for(run: &AgentRun, action: &str, reason: &str) -> KernelDirective {
    KernelDirective {
        action: action.into(),
        reason: reason.into(),
        state: run.state.clone(),
        retry_after_ms: None,
        ready_nodes: ready_node_ids(&run.plan),
        suggested_prompt: None,
    }
}

fn has_observed_work(run: &AgentRun) -> bool {
    run.recent_events.iter().any(|event| {
        event.success == Some(true)
            && matches!(
                event.kind.as_str(),
                "tool_result" | "subagent_completed" | "file_change"
            )
    })
}

fn state_for_event(kind: &str, success: Option<bool>, transient: bool) -> RunState {
    if transient && success == Some(false) {
        return RunState::WaitingRetry;
    }
    match kind {
        "model_start" => RunState::WaitingModel,
        "tool_start" => RunState::Executing,
        "tool_result" => RunState::Observing,
        "verification" | "final_candidate" | "model_no_tool" => RunState::Verifying,
        "plan" | "plan_set" => RunState::Planning,
        "cancelled" => RunState::Cancelled,
        _ => RunState::Ready,
    }
}

fn inferred_progress(kind: &str, success: Option<bool>, output: &str) -> bool {
    success == Some(true)
        && matches!(
            kind,
            "file_change" | "plan_node_completed" | "verification" | "subagent_completed"
        )
        || (kind == "tool_result" && success == Some(true) && !output.trim().is_empty())
}

fn update_plan_node(
    plan: &mut [PlanNode],
    node_id: Option<&str>,
    kind: &str,
    success: Option<bool>,
) {
    let Some(node_id) = node_id else { return };
    let Some(index) = plan.iter().position(|node| node.id == node_id) else {
        return;
    };
    let state = match (kind, success) {
        ("tool_start" | "model_start", _) => PlanNodeState::Running,
        ("verification", Some(true)) | ("plan_node_completed", Some(true)) => {
            PlanNodeState::Completed
        }
        ("verification", Some(false)) | ("tool_result", Some(false)) => PlanNodeState::Failed,
        ("verification", None) => PlanNodeState::Verifying,
        _ => plan[index].state.clone(),
    };
    if matches!(state, PlanNodeState::Running | PlanNodeState::Failed) {
        plan[index].attempts = plan[index].attempts.saturating_add(1);
    }
    plan[index].state = state;

    let completed: std::collections::HashSet<String> = plan
        .iter()
        .filter(|node| node.state == PlanNodeState::Completed)
        .map(|node| node.id.clone())
        .collect();
    for node in plan
        .iter_mut()
        .filter(|node| node.state == PlanNodeState::Pending)
    {
        if node
            .dependencies
            .iter()
            .all(|dependency| completed.contains(dependency))
        {
            node.state = PlanNodeState::Ready;
        }
    }
}

fn validate_plan(nodes: &[PlanNode]) -> Result<(), KernelError> {
    if nodes.len() > 256 {
        return Err(KernelError::Invalid("Plan exceeds 256 nodes".into()));
    }
    let ids: std::collections::HashSet<&str> = nodes.iter().map(|node| node.id.as_str()).collect();
    if ids.len() != nodes.len() || ids.contains("") {
        return Err(KernelError::Invalid(
            "Plan node IDs must be unique and non-empty".into(),
        ));
    }
    for node in nodes {
        if node
            .dependencies
            .iter()
            .any(|dependency| !ids.contains(dependency.as_str()) || dependency == &node.id)
        {
            return Err(KernelError::Invalid(format!(
                "Invalid dependency in node {}",
                node.id
            )));
        }
    }
    fn visit<'a>(
        id: &'a str,
        nodes: &'a [PlanNode],
        visiting: &mut Vec<&'a str>,
        done: &mut std::collections::HashSet<&'a str>,
    ) -> bool {
        if done.contains(id) {
            return true;
        }
        if visiting.contains(&id) {
            return false;
        }
        visiting.push(id);
        let valid = nodes
            .iter()
            .find(|node| node.id == id)
            .map(|node| {
                node.dependencies
                    .iter()
                    .all(|dependency| visit(dependency, nodes, visiting, done))
            })
            .unwrap_or(false);
        visiting.pop();
        if valid {
            done.insert(id);
        }
        valid
    }
    let mut done = std::collections::HashSet::new();
    for node in nodes {
        if !visit(&node.id, nodes, &mut Vec::new(), &mut done) {
            return Err(KernelError::Invalid(
                "Plan dependency graph contains a cycle".into(),
            ));
        }
    }
    Ok(())
}

fn ready_node_ids(plan: &[PlanNode]) -> Vec<String> {
    plan.iter()
        .filter(|node| node.state == PlanNodeState::Ready)
        .map(|node| node.id.clone())
        .collect()
}

fn plan_is_complete_or_empty(plan: &[PlanNode]) -> bool {
    plan.is_empty()
        || plan.iter().all(|node| {
            node.state == PlanNodeState::Completed || node.state == PlanNodeState::Cancelled
        })
}

fn retry_delay(attempt: u32) -> u64 {
    250_u64
        .saturating_mul(2_u64.saturating_pow(attempt.saturating_sub(1).min(8)))
        .min(MAX_RETRY_DELAY_MS)
}

fn is_auth_or_authority_error(error: &str) -> bool {
    let lower = error.to_ascii_lowercase();
    [
        "unauthorized",
        "forbidden",
        "permission denied",
        "http 401",
        "http 403",
        "approval required",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
}

fn detects_cycle(values: &VecDeque<String>) -> bool {
    let values: Vec<&String> = values.iter().collect();
    for period in 2..=3 {
        if values.len() < period * 3 {
            continue;
        }
        let tail = &values[values.len() - period..];
        if &values[values.len() - period * 2..values.len() - period] == tail
            && &values[values.len() - period * 3..values.len() - period * 2] == tail
        {
            return true;
        }
    }
    false
}

fn repeated_tail(values: &VecDeque<String>) -> usize {
    let Some(last) = values.back() else { return 0 };
    values
        .iter()
        .rev()
        .take_while(|value| *value == last)
        .count()
}

fn tool_fingerprint(name: &str, arguments: &Value) -> String {
    let canonical = canonical_json(arguments);
    let mut hash: u64 = 14_695_981_039_346_656_037;
    for byte in format!("{}:{}", name, canonical).bytes() {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(1_099_511_628_211);
    }
    format!("{}:{:016x}", name, hash)
}

fn canonical_json(value: &Value) -> String {
    match value {
        Value::Object(map) => {
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            let body = keys
                .into_iter()
                .map(|key| format!("{}:{}", key, canonical_json(&map[key])))
                .collect::<Vec<_>>()
                .join(",");
            format!("{{{}}}", body)
        }
        Value::Array(values) => format!(
            "[{}]",
            values
                .iter()
                .map(canonical_json)
                .collect::<Vec<_>>()
                .join(",")
        ),
        _ => value.to_string(),
    }
}

fn compact(value: &str) -> String {
    let value = value.trim();
    if value.chars().count() <= MAX_TEXT_CHARS {
        return value.to_string();
    }
    let head: String = value.chars().take(MAX_TEXT_CHARS * 2 / 3).collect();
    let tail: String = value
        .chars()
        .rev()
        .take(MAX_TEXT_CHARS / 3)
        .collect::<String>()
        .chars()
        .rev()
        .collect();
    format!("{}\n…[kernel compacted]…\n{}", head, tail)
}

fn bounded_unique(values: Vec<String>, max: usize) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    values
        .into_iter()
        .map(|value| compact(&value))
        .filter(|value| seen.insert(value.clone()))
        .take(max)
        .collect()
}

fn push_bounded<T>(queue: &mut VecDeque<T>, value: T, limit: usize) {
    queue.push_back(value);
    while queue.len() > limit {
        queue.pop_front();
    }
}

fn sanitize_id(id: &str) -> Result<String, KernelError> {
    if id.is_empty()
        || id.len() > 128
        || !id
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || matches!(character, '-' | '_'))
    {
        return Err(KernelError::Invalid("Invalid run ID".into()));
    }
    Ok(id.to_string())
}

#[derive(Debug, thiserror::Error)]
pub enum KernelError {
    #[error("run not found: {0}")]
    NotFound(String),
    #[error("invalid request: {0}")]
    Invalid(String),
    #[error("storage error: {0}")]
    Io(#[from] std::io::Error),
    #[error("serialization error: {0}")]
    Json(#[from] serde_json::Error),
}

impl IntoResponse for KernelError {
    fn into_response(self) -> Response {
        let status = match self {
            Self::NotFound(_) => StatusCode::NOT_FOUND,
            Self::Invalid(_) => StatusCode::BAD_REQUEST,
            Self::Io(_) | Self::Json(_) => StatusCode::INTERNAL_SERVER_ERROR,
        };
        (
            status,
            Json(serde_json::json!({ "error": self.to_string(), "status": status.as_u16() })),
        )
            .into_response()
    }
}

pub async fn create_run(
    Json(request): Json<CreateRunRequest>,
) -> Result<Json<KernelResponse>, KernelError> {
    Ok(Json(AGENT_KERNEL.create_or_resume(request).await?))
}

pub async fn get_run(AxumPath(id): AxumPath<String>) -> Result<Json<KernelResponse>, KernelError> {
    Ok(Json(AGENT_KERNEL.get(&id).await?))
}

pub async fn set_plan(
    AxumPath(id): AxumPath<String>,
    Json(request): Json<SetPlanRequest>,
) -> Result<Json<KernelResponse>, KernelError> {
    Ok(Json(AGENT_KERNEL.set_plan(&id, request.nodes).await?))
}

pub async fn observe(
    AxumPath(id): AxumPath<String>,
    Json(request): Json<ObserveRequest>,
) -> Result<Json<KernelResponse>, KernelError> {
    Ok(Json(AGENT_KERNEL.observe(&id, request).await?))
}

pub async fn cancel(AxumPath(id): AxumPath<String>) -> Result<Json<KernelResponse>, KernelError> {
    Ok(Json(AGENT_KERNEL.cancel(&id).await?))
}

/// Recommend the best provider + model for a given task description.
/// Maps task complexity and type to optimal provider/model combinations.
pub fn recommend_model_for_task(description: &str, tools: &[String]) -> crate::models::ModelRecommendation {
    let desc_lower = description.to_lowercase();
    
    // Security/architecture analysis → thinking model
    if desc_lower.contains("security") || desc_lower.contains("audit") 
        || desc_lower.contains("architect") || desc_lower.contains("design")
        || desc_lower.contains("review") {
        return crate::models::ModelRecommendation {
            provider: "anthropic".to_string(),
            model: "claude-sonnet-4".to_string(),
            reason: "Deep analysis tasks benefit from strong reasoning models".to_string(),
        };
    }
    
    // Fast code search/exploration → flash model
    if desc_lower.contains("search") || desc_lower.contains("find") 
        || desc_lower.contains("explore") || desc_lower.contains("grep")
        || desc_lower.contains("list") || desc_lower.contains("look") {
        return crate::models::ModelRecommendation {
            provider: "gemini".to_string(),
            model: "gemini-2.5-flash".to_string(),
            reason: "Fast search/exploration tasks benefit from low-latency models".to_string(),
        };
    }
    
    // Testing/verification → balanced model
    if desc_lower.contains("test") || desc_lower.contains("verify")
        || desc_lower.contains("check") || desc_lower.contains("validate") {
        return crate::models::ModelRecommendation {
            provider: "openai".to_string(),
            model: "gpt-4o".to_string(),
            reason: "Testing tasks benefit from balanced reasoning and speed".to_string(),
        };
    }
    
    // Code generation/refactoring → strong coding model
    if desc_lower.contains("implement") || desc_lower.contains("refactor")
        || desc_lower.contains("write") || desc_lower.contains("create")
        || desc_lower.contains("build") || desc_lower.contains("fix") {
        return crate::models::ModelRecommendation {
            provider: "anthropic".to_string(),
            model: "claude-sonnet-4".to_string(),
            reason: "Code generation benefits from strong coding models".to_string(),
        };
    }
    
    // Device/mobile automation → fast model
    if tools.iter().any(|t| t.contains("device") || t.contains("adb") || t.contains("simctl")) {
        return crate::models::ModelRecommendation {
            provider: "gemini".to_string(),
            model: "gemini-2.5-flash".to_string(),
            reason: "Device automation benefits from low-latency responses".to_string(),
        };
    }
    
    // Default → balanced Gemini
    crate::models::ModelRecommendation {
        provider: "gemini".to_string(),
        model: "gemini-2.5-flash".to_string(),
        reason: "Default balanced model for general tasks".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_kernel(name: &str) -> AgentKernel {
        AgentKernel::new(std::env::temp_dir().join(format!(
            "microcode-kernel-test-{}-{}",
            name,
            Uuid::new_v4()
        )))
    }

    async fn run(kernel: &AgentKernel, id: &str) -> KernelResponse {
        kernel
            .create_or_resume(CreateRunRequest {
                run_id: Some(id.into()),
                parent_run_id: None,
                objective: "Finish and verify".into(),
                workspace: "/tmp/project".into(),
                provider: "test".into(),
                model: "test".into(),
                tools: vec!["shell".into()],
                skills: vec![],
                mcp_servers: vec![],
            })
            .await
            .unwrap()
    }

    fn tool(name: &str, arguments: Value, success: bool, progress: bool) -> ObserveRequest {
        ObserveRequest {
            kind: "tool_result".into(),
            node_id: None,
            tool_name: Some(name.into()),
            arguments,
            success: Some(success),
            output: "ok".into(),
            error: String::new(),
            made_progress: progress,
            transient: false,
        }
    }

    #[tokio::test]
    async fn detects_exact_and_periodic_loops() {
        let kernel = test_kernel("loops");
        run(&kernel, "loop-run").await;
        let args = serde_json::json!({"path":"a"});
        let mut response = kernel
            .observe("loop-run", tool("read", args.clone(), true, false))
            .await
            .unwrap();
        response = kernel
            .observe("loop-run", tool("read", args.clone(), true, false))
            .await
            .unwrap();
        response = kernel
            .observe("loop-run", tool("read", args, true, false))
            .await
            .unwrap();
        assert_eq!(response.directive.action, "replan");

        run(&kernel, "cycle-run").await;
        for index in 0..6 {
            let name = if index % 2 == 0 { "read" } else { "search" };
            response = kernel
                .observe(
                    "cycle-run",
                    tool(name, serde_json::json!({"same":true}), true, false),
                )
                .await
                .unwrap();
        }
        assert_eq!(response.directive.action, "replan");
    }

    #[tokio::test]
    async fn retries_transient_failures_with_bounded_backoff() {
        let kernel = test_kernel("retry");
        run(&kernel, "retry-run").await;
        let request = ObserveRequest {
            kind: "provider_error".into(),
            node_id: None,
            tool_name: None,
            arguments: Value::Null,
            success: Some(false),
            output: String::new(),
            error: "connection reset".into(),
            made_progress: false,
            transient: true,
        };
        let response = kernel.observe("retry-run", request).await.unwrap();
        assert_eq!(response.directive.action, "retry");
        assert_eq!(response.directive.retry_after_ms, Some(250));
    }

    #[tokio::test]
    async fn rejects_completion_without_an_observed_tool_checkpoint() {
        let kernel = test_kernel("completion-evidence");
        run(&kernel, "evidence-run").await;
        let response = kernel
            .observe(
                "evidence-run",
                ObserveRequest {
                    kind: "verification".into(),
                    node_id: None,
                    tool_name: None,
                    arguments: Value::Null,
                    success: Some(true),
                    output: "model says the work is done".into(),
                    error: String::new(),
                    made_progress: true,
                    transient: false,
                },
            )
            .await
            .unwrap();
        assert_eq!(response.directive.action, "verify");
        assert_ne!(response.run.state, RunState::Completed);

        let _ = kernel
            .observe(
                "evidence-run",
                tool("shell", serde_json::json!({"command":"true"}), true, true),
            )
            .await
            .unwrap();
        let response = kernel
            .observe(
                "evidence-run",
                ObserveRequest {
                    kind: "verification".into(),
                    node_id: None,
                    tool_name: None,
                    arguments: Value::Null,
                    success: Some(true),
                    output: "command completed".into(),
                    error: String::new(),
                    made_progress: true,
                    transient: false,
                },
            )
            .await
            .unwrap();
        assert_eq!(response.directive.action, "complete");
    }

    #[tokio::test]
    async fn build_checkpoint_cannot_complete_a_launch_objective_by_itself() {
        let kernel = test_kernel("launch-evidence");
        run(&kernel, "launch-run").await;

        let _ = kernel
            .observe(
                "launch-run",
                tool(
                    "shell",
                    serde_json::json!({"command":"xcodebuild build"}),
                    true,
                    true,
                ),
            )
            .await
            .unwrap();

        let response = kernel
            .observe(
                "launch-run",
                ObserveRequest {
                    kind: "final_candidate".into(),
                    node_id: None,
                    tool_name: None,
                    arguments: Value::Null,
                    success: None,
                    output: "Build succeeded, but no install or launch checkpoint exists".into(),
                    error: String::new(),
                    made_progress: false,
                    transient: false,
                },
            )
            .await
            .unwrap();

        assert_eq!(response.directive.action, "verify");
        assert_ne!(response.run.state, RunState::Completed);
    }

    #[tokio::test]
    async fn recovers_checkpoint_and_bounds_resident_history() {
        let kernel = test_kernel("recovery");
        run(&kernel, "recover-run").await;
        for index in 0..100 {
            let request = ObserveRequest {
                kind: "status".into(),
                node_id: None,
                tool_name: None,
                arguments: Value::Null,
                success: None,
                output: format!("event {}", index),
                error: String::new(),
                made_progress: index % 10 == 0,
                transient: false,
            };
            kernel.observe("recover-run", request).await.unwrap();
        }
        let recovered = AgentKernel::new(kernel.root.clone())
            .get("recover-run")
            .await
            .unwrap();
        assert_eq!(recovered.run.sequence, 100);
        assert_eq!(recovered.run.recent_events.len(), MAX_RECENT_EVENTS);
        let snapshot_bytes = std::fs::metadata(kernel.snapshot_path("recover-run"))
            .unwrap()
            .len();
        assert!(
            snapshot_bytes < 96 * 1024,
            "snapshot grew to {snapshot_bytes} bytes"
        );
    }

    #[tokio::test]
    async fn validates_plan_dag_and_unlocks_dependencies() {
        let kernel = test_kernel("plan");
        run(&kernel, "plan-run").await;
        let nodes = vec![
            PlanNode {
                id: "inspect".into(),
                title: "Inspect".into(),
                description: String::new(),
                dependencies: vec![],
                verification: "files read".into(),
                required_tools: vec!["read".into()],
                owner: None,
                state: PlanNodeState::Pending,
                attempts: 0,
            },
            PlanNode {
                id: "build".into(),
                title: "Build".into(),
                description: String::new(),
                dependencies: vec!["inspect".into()],
                verification: "exit 0".into(),
                required_tools: vec!["shell".into()],
                owner: Some("test_runner".into()),
                state: PlanNodeState::Pending,
                attempts: 0,
            },
        ];
        let response = kernel.set_plan("plan-run", nodes).await.unwrap();
        assert_eq!(response.directive.ready_nodes, vec!["inspect"]);
        assert_eq!(
            response.run.plan[0].owner.as_deref(),
            Some("architect"),
            "the kernel should recommend a specialist for unowned work"
        );
        let request = ObserveRequest {
            kind: "plan_node_completed".into(),
            node_id: Some("inspect".into()),
            tool_name: None,
            arguments: Value::Null,
            success: Some(true),
            output: "done".into(),
            error: String::new(),
            made_progress: true,
            transient: false,
        };
        let response = kernel.observe("plan-run", request).await.unwrap();
        assert!(response
            .directive
            .ready_nodes
            .contains(&"build".to_string()));
    }
}
