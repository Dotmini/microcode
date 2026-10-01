use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::path::{Path, PathBuf};


fn canonical_destination(path: &Path) -> Option<PathBuf> {
    if !path.is_absolute() { return None; }
    let mut parent = path.to_path_buf();
    let mut suffix = Vec::new();
    loop {
        if let Ok(mut resolved) = parent.canonicalize() {
            for part in suffix.iter().rev() { resolved.push(part); }
            return Some(resolved);
        }
        if std::fs::symlink_metadata(&parent).map(|m| m.file_type().is_symlink()).unwrap_or(false) { return None; }
        suffix.push(parent.file_name()?.to_os_string());
        if !parent.pop() { return None; }
    }
}

/// Represents a decision made by the policy engine for a tool call.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum PolicyDecision {
    Allow,
    Deny(String),
    AskUser(String),
}

/// Defines the scope of a policy rule.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum PolicyScope {
    Specific(String),
    Prefix(String),
    Global,
}

impl PolicyScope {
    /// Checks if this scope matches a given tool name.
    pub fn matches(&self, tool_name: &str) -> bool {
        match self {
            PolicyScope::Specific(name) => name == tool_name,
            PolicyScope::Prefix(prefix) => tool_name.starts_with(prefix),
            PolicyScope::Global => true,
        }
    }
}

/// A rule condition that must be met for the rule to apply.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum RuleCondition {
    Always,
    /// Checks if the tool arguments contain a path that falls within any of the provided roots.
    /// This assumes the path is provided in common arguments like "path", "file_path", "target_file".
    PathInRoots(Vec<PathBuf>),
}

/// A policy rule defining a decision for a specific scope.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PolicyRule {
    pub name: String,
    pub scope: PolicyScope,
    pub decision: PolicyDecision,
    pub priority: u8,
    #[serde(default = "default_condition")]
    pub condition: RuleCondition,
}

fn default_condition() -> RuleCondition {
    RuleCondition::Always
}

impl PolicyRule {
    pub fn new(name: impl Into<String>, priority: u8, scope: PolicyScope, decision: PolicyDecision) -> Self {
        Self {
            name: name.into(),
            scope,
            decision,
            priority,
            condition: RuleCondition::Always,
        }
    }

    pub fn with_condition(mut self, condition: RuleCondition) -> Self {
        self.condition = condition;
        self
    }
}

/// A priority-based tool execution safety policy engine.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolicyEngine {
    pub rules: Vec<PolicyRule>,
}

impl PolicyEngine {
    /// Creates a new, empty policy engine.
    pub fn new() -> Self {
        Self { rules: Vec::new() }
    }

    /// Adds a rule to the engine. Uses builder pattern.
    pub fn add_rule(&mut self, rule: PolicyRule) -> &mut Self {
        self.rules.push(rule);
        self
    }

    /// Evaluates a tool call against all rules.
    /// Rules are sorted by priority (1=highest, 9=lowest). First match wins.
    /// Returns Allow if no rules match.
    pub fn evaluate(&self, tool_name: &str, args: &Value) -> PolicyDecision {
        let mut sorted_rules = self.rules.clone();
        // Stable sort by priority (1 is highest priority, so sort ascending)
        sorted_rules.sort_by_key(|r| r.priority);

        for rule in sorted_rules {
            if rule.scope.matches(tool_name) {
                let mut condition_applies = true;
                
                match &rule.condition {
                    RuleCondition::Always => {}
                    RuleCondition::PathInRoots(roots) => {
                        let path_str = args.get("path")
                            .or_else(|| args.get("file_path"))
                            .or_else(|| args.get("target_file"))
                            .or_else(|| args.get("TargetFile"))
                            .or_else(|| args.get("AbsolutePath"))
                            .or_else(|| args.get("SearchDirectory"))
                            .or_else(|| args.get("SearchPath"))
                            .or_else(|| args.get("DirectoryPath"))
                            .and_then(|v| v.as_str());

                        if let Some(p) = path_str {
                            let path = Path::new(p);
                            if path.components().any(|c| matches!(c, std::path::Component::ParentDir))
                                || !roots.iter().any(|root| {
                                    match (canonical_destination(path), canonical_destination(root)) {
                                        (Some(candidate), Some(root)) => candidate.starts_with(root),
                                        _ => false,
                                    }
                                }) {
                                condition_applies = false;
                            }
                        } else {
                            // If we require path in roots but there's no path arg,
                            // we'll say the condition doesn't apply to be safe.
                            condition_applies = false;
                        }
                    }
                }

                if condition_applies {
                    return rule.decision.clone();
                }
            }
        }

        PolicyDecision::Allow
    }

    /// Preset: deny run_command, delete_file, git_commit; allow all others.
    pub fn default_safe() -> Self {
        let mut engine = Self::new();
        engine.add_rule(PolicyRule::new(
            "Deny run_command",
            1, // Specific Deny
            PolicyScope::Specific("run_command".to_string()),
            PolicyDecision::Deny("run_command is denied in default_safe preset".to_string()),
        ));
        engine.add_rule(PolicyRule::new(
            "Deny execute_command",
            1,
            PolicyScope::Specific("execute_command".to_string()),
            PolicyDecision::Deny("execute_command is denied in default_safe preset".to_string()),
        ));
        engine.add_rule(PolicyRule::new(
            "Deny delete_file",
            1, // Specific Deny
            PolicyScope::Specific("delete_file".to_string()),
            PolicyDecision::Deny("delete_file is denied in default_safe preset".to_string()),
        ));
        engine.add_rule(PolicyRule::new(
            "Deny git_commit",
            1, // Specific Deny
            PolicyScope::Specific("git_commit".to_string()),
            PolicyDecision::Deny("git_commit is denied in default_safe preset".to_string()),
        ));
        engine.add_rule(PolicyRule::new(
            "Allow all others",
            9, // Global Allow
            PolicyScope::Global,
            PolicyDecision::Allow,
        ));
        engine
    }

    /// Preset: restricts file tools to workspace roots.
    pub fn workspace_only(roots: Vec<PathBuf>) -> Self {
        let mut engine = Self::new();
        let file_tools = vec![
            "read_file", "write_file", "delete_file", "view_file", "list_dir", "search_dir", "replace_file_content", "write_to_file", "find_by_name", "grep_search"
        ];

        for tool in &file_tools {
            engine.add_rule(
                PolicyRule::new(
                    format!("Allow {} in workspace", tool),
                    3,
                    PolicyScope::Specific(tool.to_string()),
                    PolicyDecision::Allow,
                ).with_condition(RuleCondition::PathInRoots(roots.clone()))
            );

            engine.add_rule(PolicyRule::new(
                format!("Deny {} outside workspace", tool),
                4, 
                PolicyScope::Specific(tool.to_string()),
                PolicyDecision::Deny(format!("{} is restricted to workspace roots", tool)),
            ));
        }

        engine.add_rule(PolicyRule::new(
            "Global Allow",
            9,
            PolicyScope::Global,
            PolicyDecision::Allow,
        ));

        engine
    }

    /// Preset: allow everything.
    pub fn allow_all() -> Self {
        let mut engine = Self::new();
        engine.add_rule(PolicyRule::new(
            "Global Allow",
            9,
            PolicyScope::Global,
            PolicyDecision::Allow,
        ));
        engine
    }

    /// Preset: deny everything.
    pub fn deny_all() -> Self {
        let mut engine = Self::new();
        engine.add_rule(PolicyRule::new(
            "Global Deny",
            7, // Global Deny is priority 7
            PolicyScope::Global,
            PolicyDecision::Deny("All tools denied by deny_all preset".to_string()),
        ));
        engine
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_scope_matching() {
        let specific = PolicyScope::Specific("run_command".to_string());
        assert!(specific.matches("run_command"));
        assert!(!specific.matches("run_command2"));

        let prefix = PolicyScope::Prefix("mcp_server/".to_string());
        assert!(prefix.matches("mcp_server/fetch"));
        assert!(!prefix.matches("mcp/fetch"));

        let global = PolicyScope::Global;
        assert!(global.matches("anything"));
    }

    #[test]
    fn test_evaluate_priority() {
        let mut engine = PolicyEngine::new();
        engine.add_rule(PolicyRule::new(
            "Prefix Deny",
            4,
            PolicyScope::Prefix("mcp_server/".to_string()),
            PolicyDecision::Deny("Denied prefix".to_string()),
        ));
        engine.add_rule(PolicyRule::new(
            "Specific Allow",
            3,
            PolicyScope::Specific("mcp_server/safe_tool".to_string()),
            PolicyDecision::Allow,
        ));

        let args = json!({});

        // Specific allow (priority 3) should win over prefix deny (priority 4)
        assert_eq!(
            engine.evaluate("mcp_server/safe_tool", &args),
            PolicyDecision::Allow
        );

        // Prefix deny should apply to others
        assert_eq!(
            engine.evaluate("mcp_server/unsafe_tool", &args),
            PolicyDecision::Deny("Denied prefix".to_string())
        );

        // Global fallback to allow
        assert_eq!(
            engine.evaluate("other_tool", &args),
            PolicyDecision::Allow
        );
    }

    #[test]
    fn test_default_safe() {
        let engine = PolicyEngine::default_safe();
        let args = json!({});

        assert_eq!(
            engine.evaluate("run_command", &args),
            PolicyDecision::Deny("run_command is denied in default_safe preset".to_string())
        );
        assert_eq!(
            engine.evaluate("read_file", &args),
            PolicyDecision::Allow
        );
    }

    #[test]
    fn test_workspace_only() {
        let roots = vec![PathBuf::from("/workspace")];
        let engine = PolicyEngine::workspace_only(roots);

        // Inside workspace
        let args_in = json!({"TargetFile": "/workspace/src/main.rs"});
        assert_eq!(
            engine.evaluate("write_to_file", &args_in),
            PolicyDecision::Allow
        );

        // Outside workspace
        let args_out = json!({"TargetFile": "/etc/passwd"});
        assert_eq!(
            engine.evaluate("write_to_file", &args_out),
            PolicyDecision::Deny("write_to_file is restricted to workspace roots".to_string())
        );

        // Non-file tool
        let args_other = json!({});
        assert_eq!(
            engine.evaluate("search_web", &args_other),
            PolicyDecision::Allow
        );
    }

    #[test]
    fn traversal_and_command_alias_are_denied() {
        let engine = PolicyEngine::workspace_only(vec![PathBuf::from("/workspace")]);
        assert!(matches!(engine.evaluate("write_to_file", &json!({"TargetFile": "/workspace/../private/file"})), PolicyDecision::Deny(_)));
        assert!(matches!(engine.evaluate("write_to_file", &json!({"TargetFile": "/workspace-other/file"})), PolicyDecision::Deny(_)));
        assert!(matches!(PolicyEngine::default_safe().evaluate("execute_command", &json!({})), PolicyDecision::Deny(_)));
    }

    #[test]
    #[cfg(unix)]
    fn missing_leaf_cannot_escape_via_symlink() {
        let temp = std::env::temp_dir().join(format!("microcode-policy-{}", std::process::id()));
        let root = temp.join("workspace");
        let outside = temp.join("outside");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::create_dir_all(&outside).unwrap();
        std::os::unix::fs::symlink(&outside, root.join("escape")).unwrap();
        let engine = PolicyEngine::workspace_only(vec![root.clone()]);
        assert!(matches!(engine.evaluate("write_file", &json!({"path": root.join("escape/new.txt")})), PolicyDecision::Deny(_)));
        assert!(matches!(engine.evaluate("write_file", &json!({"path": root.join("new.txt")})), PolicyDecision::Allow));
        std::fs::remove_dir_all(temp).unwrap();
    }

    #[test]
    fn test_allow_all() {
        let engine = PolicyEngine::allow_all();
        assert_eq!(
            engine.evaluate("destructive_tool", &json!({})),
            PolicyDecision::Allow
        );
    }

    #[test]
    fn test_deny_all() {
        let engine = PolicyEngine::deny_all();
        assert_eq!(
            engine.evaluate("safe_tool", &json!({})),
            PolicyDecision::Deny("All tools denied by deny_all preset".to_string())
        );
    }
}
