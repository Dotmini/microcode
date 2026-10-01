use std::sync::{atomic::{AtomicUsize, Ordering}, Arc};
use async_trait::async_trait;
use serde_json::Value;
use tracing::{info, error as log_error};
use crate::error::Result;

/// Represents the outcome of a pre-hook evaluation.
#[derive(Debug, Clone, PartialEq)]
pub enum HookResult {
    /// Proceed with the default action.
    Allow,
    /// Block the action and return the provided reason.
    Deny(String),
    /// Proceed with modified arguments.
    Modify(Value),
}

/// A hook that can intercept and augment the agent's lifecycle events.
#[async_trait]
pub trait AgentHook: Send + Sync {
    /// Returns the name of the hook.
    fn name(&self) -> &str;

    /// Called when a new session starts.
    async fn on_session_start(&self, _session_id: &str) -> Result<()> { Ok(()) }
    
    /// Called when a session ends.
    async fn on_session_end(&self, _session_id: &str) -> Result<()> { Ok(()) }
    
    /// Called before the agent takes a turn (processes a user prompt).
    async fn pre_turn(&self, _prompt: &str) -> HookResult { HookResult::Allow }
    
    /// Called after the agent finishes a turn.
    async fn post_turn(&self, _response: &str) -> Result<()> { Ok(()) }
    
    /// Called before the agent executes a tool. Can block or modify arguments.
    async fn pre_tool_call(&self, _tool_name: &str, _args: &Value) -> HookResult { HookResult::Allow }
    
    /// Called after a tool completes execution.
    async fn post_tool_call(&self, _tool_name: &str, _args: &Value, _result: &str, _success: bool) -> Result<()> { Ok(()) }
    
    /// Called if a tool execution encounters an error. Can return a recovery string.
    async fn on_tool_error(&self, _tool_name: &str, _error: &str) -> Option<String> { None }
}

/// Manages a collection of hooks and executes them in sequence.
#[derive(Default)]
pub struct HookPipeline {
    hooks: Vec<Arc<dyn AgentHook>>,
}

impl HookPipeline {
    /// Creates a new, empty hook pipeline.
    pub fn new() -> Self {
        Self { hooks: Vec::new() }
    }

    /// Adds a hook to the pipeline.
    pub fn add_hook(&mut self, hook: Arc<dyn AgentHook>) -> &mut Self {
        self.hooks.push(hook);
        self
    }

    /// Runs all `pre_tool_call` hooks in sequence. 
    /// Short-circuits on the first `Deny`. 
    /// Returns `Modify` if any hook modified the arguments.
    pub async fn run_pre_tool_call(&self, tool_name: &str, args: &Value) -> HookResult {
        let mut current_args = args.clone();
        for hook in &self.hooks {
            match hook.pre_tool_call(tool_name, &current_args).await {
                HookResult::Allow => {}
                HookResult::Deny(reason) => return HookResult::Deny(reason),
                HookResult::Modify(new_args) => {
                    current_args = new_args.clone();
                }
            }
        }
        if current_args != *args {
            HookResult::Modify(current_args)
        } else {
            HookResult::Allow
        }
    }

    /// Runs all `post_tool_call` hooks. Logs errors instead of propagating them.
    pub async fn run_post_tool_call(&self, tool_name: &str, args: &Value, result: &str, success: bool) {
        for hook in &self.hooks {
            if let Err(e) = hook.post_tool_call(tool_name, args, result, success).await {
                log_error!("Hook {} failed in post_tool_call: {}", hook.name(), e);
            }
        }
    }

    /// Runs all `on_session_start` hooks.
    pub async fn run_session_start(&self, session_id: &str) {
        for hook in &self.hooks {
            if let Err(e) = hook.on_session_start(session_id).await {
                log_error!("Hook {} failed in on_session_start: {}", hook.name(), e);
            }
        }
    }

    /// Runs all `on_session_end` hooks.
    pub async fn run_session_end(&self, session_id: &str) {
        for hook in &self.hooks {
            if let Err(e) = hook.on_session_end(session_id).await {
                log_error!("Hook {} failed in on_session_end: {}", hook.name(), e);
            }
        }
    }

    /// Runs all `pre_turn` hooks. Short-circuits on non-Allow results.
    pub async fn run_pre_turn(&self, prompt: &str) -> HookResult {
        for hook in &self.hooks {
            match hook.pre_turn(prompt).await {
                HookResult::Allow => {}
                result => return result,
            }
        }
        HookResult::Allow
    }

    /// Runs all `post_turn` hooks.
    pub async fn run_post_turn(&self, response: &str) {
        for hook in &self.hooks {
            if let Err(e) = hook.post_turn(response).await {
                log_error!("Hook {} failed in post_turn: {}", hook.name(), e);
            }
        }
    }

    /// Runs `on_tool_error` hooks. Returns the first `Some` recovery string.
    pub async fn run_on_tool_error(&self, tool_name: &str, error: &str) -> Option<String> {
        for hook in &self.hooks {
            if let Some(recovery) = hook.on_tool_error(tool_name, error).await {
                return Some(recovery);
            }
        }
        None
    }
}

/// A hook that logs every tool call execution.
pub struct AuditLogHook;

#[async_trait]
impl AgentHook for AuditLogHook {
    fn name(&self) -> &str {
        "AuditLogHook"
    }

    async fn post_tool_call(&self, tool_name: &str, _args: &Value, _result: &str, success: bool) -> Result<()> {
        info!(
            tool_name = tool_name,
            success = success,
            "Tool call completed"
        );
        Ok(())
    }
}

/// Configuration for budget enforcement.
pub struct BudgetConfig {
    pub max_model_calls: Option<usize>,
    pub max_tool_calls: Option<usize>,
}

/// A hook that enforces limits on model and tool calls per session.
pub struct BudgetEnforcementHook {
    config: BudgetConfig,
    model_calls: AtomicUsize,
    tool_calls: AtomicUsize,
}

impl BudgetEnforcementHook {
    pub fn new(config: BudgetConfig) -> Self {
        Self {
            config,
            model_calls: AtomicUsize::new(0),
            tool_calls: AtomicUsize::new(0),
        }
    }
}

#[async_trait]
impl AgentHook for BudgetEnforcementHook {
    fn name(&self) -> &str {
        "BudgetEnforcementHook"
    }

    async fn pre_turn(&self, _prompt: &str) -> HookResult {
        let current_calls = self.model_calls.fetch_add(1, Ordering::SeqCst) + 1;
        if let Some(max) = self.config.max_model_calls {
            if current_calls > max {
                return HookResult::Deny(format!("Model call budget exceeded ({} / {})", current_calls, max));
            }
        }
        HookResult::Allow
    }

    async fn pre_tool_call(&self, _tool_name: &str, _args: &Value) -> HookResult {
        let current_calls = self.tool_calls.fetch_add(1, Ordering::SeqCst) + 1;
        if let Some(max) = self.config.max_tool_calls {
            if current_calls > max {
                return HookResult::Deny(format!("Tool call budget exceeded ({} / {})", current_calls, max));
            }
        }
        HookResult::Allow
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[tokio::test]
    async fn test_budget_hook_tool_calls() {
        let hook = BudgetEnforcementHook::new(BudgetConfig {
            max_model_calls: None,
            max_tool_calls: Some(2),
        });

        let args = json!({});
        assert_eq!(hook.pre_tool_call("test_tool", &args).await, HookResult::Allow); // Call 1
        assert_eq!(hook.pre_tool_call("test_tool", &args).await, HookResult::Allow); // Call 2
        
        let result = hook.pre_tool_call("test_tool", &args).await; // Call 3
        assert!(matches!(result, HookResult::Deny(_)));
    }

    #[tokio::test]
    async fn test_pipeline_pre_tool_call() {
        let hook = Arc::new(BudgetEnforcementHook::new(BudgetConfig {
            max_model_calls: None,
            max_tool_calls: Some(1),
        }));

        let mut pipeline = HookPipeline::new();
        pipeline.add_hook(hook);

        let args = json!({});
        assert_eq!(pipeline.run_pre_tool_call("test", &args).await, HookResult::Allow);
        assert!(matches!(pipeline.run_pre_tool_call("test", &args).await, HookResult::Deny(_)));
    }
}
