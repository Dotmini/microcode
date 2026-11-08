use crate::error::Result;
use glob::Pattern;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use tokio::fs;

/// Deterministic 64-bit FNV-1a `~/.microcode/workspaces/<name>-<12hex>` resolver
/// matching Swift `WorkspaceStoragePaths.workspaceStateDirectory` and `microcode_core` FFI.
pub fn isolated_workspace_state_dir(workspace: &Path) -> PathBuf {
    let home_base = dirs::home_dir()
        .or_else(|| std::env::var_os("HOME").map(PathBuf::from))
        .unwrap_or_else(std::env::temp_dir);
    let workspaces_root = home_base.join(".microcode").join("workspaces");

    let canonical = workspace.canonicalize().unwrap_or_else(|_| workspace.to_path_buf());
    let canonical_str = canonical.to_string_lossy();
    let clean_str = if canonical_str.len() > 1 && canonical_str.ends_with('/') {
        &canonical_str[..canonical_str.len() - 1]
    } else {
        &canonical_str
    };

    let mut hash: u64 = 14695981039346656037;
    for b in clean_str.as_bytes() {
        hash ^= *b as u64;
        hash = hash.wrapping_mul(1099511628211);
    }

    let raw_name = canonical
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("workspace");
    let replaced: String = raw_name
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '.' || c == '_' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect();
    let trimmed = replaced.trim_matches(|c| c == '.' || c == '_' || c == '-');
    let prefix: String = if trimmed.is_empty() {
        "workspace".to_string()
    } else {
        trimmed.chars().take(40).collect()
    };

    let slug = format!("{}-{:012x}", prefix, hash >> 16);
    workspaces_root.join(slug)
}

/// Global `~/.microcode` root directory.
pub fn global_microcode_dir() -> PathBuf {
    dirs::home_dir()
        .or_else(|| std::env::var_os("HOME").map(PathBuf::from))
        .unwrap_or_else(std::env::temp_dir)
        .join(".microcode")
}

/// A rule scoped to specific file globs or globally active.
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ScopedRule {
    pub name: String,
    pub globs: Vec<String>,
    pub content: String,
    pub always_active: bool,
    pub description: Option<String>,
}

/// Engine to manage and inject scoped rules based on active files.
#[derive(Debug, Default, Clone)]
pub struct RuleEngine {
    rules: Vec<ScopedRule>,
}

impl RuleEngine {
    /// Loads all unified MicroCode rules across:
    /// 1. Isolated workspace state: `~/.microcode/workspaces/<id>/{rules.md, agent.md, rules/*.{md,mdc}}`
    /// 2. Explicit repo `.microcode`: `<workspace>/.microcode/{rules.md, agent.md, rules/*.{md,mdc}}`
    /// 3. Global user rules: `~/.microcode/{rules.md, rules/*.{md,mdc}}`
    pub async fn load_from_workspace(workspace: &Path) -> Result<Self> {
        let mut rules = Vec::new();
        let mut seen_paths = HashSet::new();

        let isolated_dir = isolated_workspace_state_dir(workspace);
        let repo_mc_dir = workspace.join(".microcode");
        let global_mc_dir = global_microcode_dir();

        let direct_files: [(PathBuf, &str, &str); 5] = [
            (
                isolated_dir.join("rules.md"),
                "Workspace Learned Rules (/learn)",
                "Persistent workspace rules (~/.microcode)",
            ),
            (
                isolated_dir.join("agent.md"),
                "Workspace Agent Instructions",
                "MicroCode workspace agent.md (~/.microcode)",
            ),
            (
                repo_mc_dir.join("rules.md"),
                "Repository Rules (.microcode/rules.md)",
                "Committed repository MicroCode rules",
            ),
            (
                repo_mc_dir.join("agent.md"),
                "Repository Agent Instructions (.microcode/agent.md)",
                "Committed repository agent instructions",
            ),
            (
                global_mc_dir.join("rules.md"),
                "Global MicroCode Rules (~/.microcode/rules.md)",
                "User-wide global MicroCode rules",
            ),
        ];

        for (file_path, title, desc) in direct_files {
            if !file_path.exists() {
                continue;
            }
            let canon = file_path.canonicalize().unwrap_or_else(|_| file_path.clone());
            if !seen_paths.insert(canon) {
                continue;
            }
            if let Ok(content) = fs::read_to_string(&file_path).await {
                if !content.trim().is_empty() {
                    let mut parsed = Self::parse_rule_file(title, &content)?;
                    if parsed.description.is_none() {
                        parsed.description = Some(desc.to_string());
                    }
                    rules.push(parsed);
                }
            }
        }

        let rule_dirs = [
            isolated_dir.join("rules"),
            repo_mc_dir.join("rules"),
            global_mc_dir.join("rules"),
        ];

        for rules_dir in rule_dirs {
            if !rules_dir.exists() {
                continue;
            }
            if let Ok(mut entries) = fs::read_dir(&rules_dir).await {
                while let Ok(Some(entry)) = entries.next_entry().await {
                    let path = entry.path();
                    let ext = path.extension().and_then(|s| s.to_str()).unwrap_or("");
                    if path.is_file() && (ext.eq_ignore_ascii_case("md") || ext.eq_ignore_ascii_case("mdc")) {
                        let canon = path.canonicalize().unwrap_or_else(|_| path.clone());
                        if !seen_paths.insert(canon) {
                            continue;
                        }
                        if let Ok(file_content) = fs::read_to_string(&path).await {
                            if !file_content.trim().is_empty() {
                                let file_stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("rule");
                                let rule = Self::parse_rule_file(file_stem, &file_content)?;
                                rules.push(rule);
                            }
                        }
                    }
                }
            }
        }

        Ok(Self { rules })
    }

    /// Parses a single rule file content, extracting optional frontmatter.
    fn parse_rule_file(default_name: &str, content: &str) -> Result<ScopedRule> {
        let content = content.trim_start();
        
        if !content.starts_with("---") {
            return Ok(ScopedRule {
                name: default_name.to_string(),
                globs: Vec::new(),
                content: content.to_string(),
                always_active: true,
                description: None,
            });
        }

        let parts: Vec<&str> = content.splitn(3, "---").collect();
        if parts.len() < 3 {
            return Ok(ScopedRule {
                name: default_name.to_string(),
                globs: Vec::new(),
                content: content.to_string(),
                always_active: true,
                description: None,
            });
        }

        let frontmatter = parts[1].trim();
        let markdown_content = parts[2].trim_start().to_string();

        let mut name = default_name.to_string();
        let mut globs = Vec::new();
        let mut always_active = false;
        let mut description = None;

        for line in frontmatter.lines() {
            let line = line.trim();
            if line.is_empty() {
                continue;
            }
            
            if let Some(idx) = line.find(':') {
                let key = line[..idx].trim();
                let value = line[idx + 1..].trim();
                
                match key {
                    "name" => {
                        let val = value.trim_matches(|c| c == '"' || c == '\'');
                        if !val.is_empty() {
                            name = val.to_string();
                        }
                    }
                    "always_active" => {
                        always_active = value.eq_ignore_ascii_case("true");
                    }
                    "description" => {
                        let val = value.trim_matches(|c| c == '"' || c == '\'');
                        if !val.is_empty() {
                            description = Some(val.to_string());
                        }
                    }
                    "globs" => {
                        if let Ok(parsed_globs) = serde_json::from_str::<Vec<String>>(value) {
                            globs = parsed_globs;
                        }
                    }
                    _ => {}
                }
            }
        }

        Ok(ScopedRule {
            name,
            globs,
            content: markdown_content,
            always_active,
            description,
        })
    }

    /// Returns rules whose globs match any of the active files, plus all `always_active` rules.
    pub fn get_active_rules(&self, active_files: &[&str]) -> Vec<&ScopedRule> {
        self.rules.iter().filter(|rule| {
            if rule.always_active {
                return true;
            }
            for active_file in active_files {
                for glob_str in &rule.globs {
                    if let Ok(pattern) = Pattern::new(glob_str) {
                        if pattern.matches(active_file) {
                            return true;
                        }
                    }
                }
            }
            false
        }).collect()
    }

    /// Appends matching rules to the system prompt under a `## Project Rules` section.
    pub fn inject_into_prompt(&self, base_prompt: &str, active_files: &[&str]) -> String {
        let active_rules = self.get_active_rules(active_files);
        if active_rules.is_empty() {
            return base_prompt.to_string();
        }

        let mut prompt = String::from(base_prompt);
        prompt.push_str("\n\n## Project Rules\n\n");

        for rule in active_rules {
            prompt.push_str(&format!("### Rule: {}\n", rule.name));
            if let Some(desc) = &rule.description {
                prompt.push_str(&format!("Description: {}\n", desc));
            }
            prompt.push_str(&format!("{}\n\n", rule.content));
        }

        prompt.trim_end().to_string()
    }

    /// Accessor for all loaded rules.
    pub fn rules(&self) -> &[ScopedRule] {
        &self.rules
    }

    /// Returns whether the engine has any rules loaded.
    pub fn is_empty(&self) -> bool {
        self.rules.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_no_frontmatter() {
        let content = "# Hello World\nThis is a rule.";
        let rule = RuleEngine::parse_rule_file("default_rule", content).unwrap();
        assert_eq!(rule.name, "default_rule");
        assert!(rule.always_active);
        assert!(rule.globs.is_empty());
        assert_eq!(rule.content, content);
    }

    #[test]
    fn test_parse_frontmatter() {
        let content = r#"---
name: Custom Rule
always_active: false
description: "A very custom rule"
globs: ["**/*.rs", "*.swift"]
---
This is the content."#;
        let rule = RuleEngine::parse_rule_file("default", content).unwrap();
        assert_eq!(rule.name, "Custom Rule");
        assert!(!rule.always_active);
        assert_eq!(rule.description, Some("A very custom rule".to_string()));
        assert_eq!(rule.globs, vec!["**/*.rs".to_string(), "*.swift".to_string()]);
        assert_eq!(rule.content, "This is the content.");
    }

    #[test]
    fn test_glob_matching() {
        let engine = RuleEngine {
            rules: vec![
                ScopedRule {
                    name: "Rust Rule".to_string(),
                    globs: vec!["**/*.rs".to_string()],
                    content: "rust rules".to_string(),
                    always_active: false,
                    description: None,
                },
                ScopedRule {
                    name: "Global Rule".to_string(),
                    globs: vec![],
                    content: "global".to_string(),
                    always_active: true,
                    description: None,
                },
            ],
        };

        let active = engine.get_active_rules(&["backend/src/main.rs"]);
        assert_eq!(active.len(), 2);

        let active = engine.get_active_rules(&["frontend/app.swift"]);
        assert_eq!(active.len(), 1);
        assert_eq!(active[0].name, "Global Rule");
    }

    #[test]
    fn test_inject_into_prompt() {
        let engine = RuleEngine {
            rules: vec![
                ScopedRule {
                    name: "Rust Rule".to_string(),
                    globs: vec!["**/*.rs".to_string()],
                    content: "Format with rustfmt".to_string(),
                    always_active: false,
                    description: Some("Rust formatting".to_string()),
                },
            ],
        };

        let result = engine.inject_into_prompt("Base system prompt.", &["src/lib.rs"]);
        assert!(result.contains("Base system prompt."));
        assert!(result.contains("## Project Rules"));
        assert!(result.contains("### Rule: Rust Rule"));
        assert!(result.contains("Description: Rust formatting"));
        assert!(result.contains("Format with rustfmt"));
    }

    #[test]
    fn test_isolated_workspace_state_dir_fnv1a_parity() {
        let dir = isolated_workspace_state_dir(Path::new("/Users/dotmini/Documents/SX/codetunner-native"));
        let slug = dir.file_name().and_then(|s| s.to_str()).unwrap_or("");
        assert_eq!(slug, "codetunner-native-4f5150635371");
    }
}
