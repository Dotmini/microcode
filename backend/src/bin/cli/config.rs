//! MicroCode CLI — Unified Configuration Management
//!
//! Stores workspace configuration inside `~/.microcode/workspaces/<slug>/` by default
//! (Zero Repo Pollution, matching Swift `WorkspaceStoragePaths`), while honoring an
//! existing `<workspace>/.microcode/config.toml` if a repository explicitly committed one.

use anyhow::{Context, Result};
use microcode_embedded::rules::isolated_workspace_state_dir;
use std::path::{Path, PathBuf};

/// Resolves the active `.microcode` state directory for a workspace:
/// - Uses `<workspace>/.microcode/` ONLY if `<workspace>/.microcode/config.toml` already exists.
/// - Otherwise uses `~/.microcode/workspaces/<slug>/` so Git repositories stay clean.
pub fn resolve_workspace_config_dir(workspace: &Path) -> PathBuf {
    let legacy_repo_dir = workspace.join(".microcode");
    if legacy_repo_dir.join("config.toml").exists() {
        return legacy_repo_dir;
    }
    isolated_workspace_state_dir(workspace)
}

fn lock_owner_only_permissions(path: &Path, is_dir: bool) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = if is_dir { 0o700 } else { 0o600 };
        let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode));
    }
}

/// Initialize workspace configuration inside isolated `~/.microcode/workspaces/<slug>/`
pub fn init_workspace(workspace: &Path) -> Result<()> {
    let config_dir = resolve_workspace_config_dir(workspace);
    std::fs::create_dir_all(&config_dir)?;
    lock_owner_only_permissions(&config_dir, true);

    let config_path = config_dir.join("config.toml");
    if !config_path.exists() {
        std::fs::write(&config_path, DEFAULT_CONFIG)?;
    }

    let rules_path = config_dir.join("rules.md");
    if !rules_path.exists() {
        std::fs::write(&rules_path, DEFAULT_RULES)?;
    }

    let env_path = config_dir.join(".env");
    if !env_path.exists() {
        std::fs::write(&env_path, DEFAULT_ENV)?;
    }
    lock_owner_only_permissions(&env_path, false);

    println!("Initialized MicroCode workspace state at {}", config_dir.display());
    Ok(())
}

/// Handle `microcode config` `--list`, `--get <section.key>`, and `--set <section.key=value>`
pub fn handle_config(
    workspace: &Path,
    set: Option<String>,
    get: Option<String>,
    list: bool,
) -> Result<()> {
    let config_dir = resolve_workspace_config_dir(workspace);
    let config_path = config_dir.join("config.toml");

    if list {
        if config_path.exists() {
            let content = std::fs::read_to_string(&config_path)?;
            println!("{}", content);
        } else {
            println!(
                "No configuration found at {}. Run 'microcode init' first.",
                config_path.display()
            );
        }
        return Ok(());
    }

    if let Some(key_value) = set {
        let parts: Vec<&str> = key_value.splitn(2, '=').collect();
        if parts.len() != 2 {
            anyhow::bail!("Invalid format. Use: --set section.key=value (e.g. --set ai.provider=anthropic)");
        }
        let raw_key = parts[0].trim();
        let raw_val = parts[1].trim();
        if raw_key.is_empty() {
            anyhow::bail!("Configuration key cannot be empty");
        }

        std::fs::create_dir_all(&config_dir)?;
        lock_owner_only_permissions(&config_dir, true);
        let existing = if config_path.exists() {
            std::fs::read_to_string(&config_path)?
        } else {
            DEFAULT_CONFIG.to_string()
        };

        let updated = upsert_toml_value(&existing, raw_key, raw_val);
        std::fs::write(&config_path, &updated)
            .with_context(|| format!("Failed to write {}", config_path.display()))?;
        let formatted_val = read_toml_value(&updated, raw_key).unwrap_or_else(|| raw_val.to_string());
        println!("Updated {} = {} ({})", raw_key, formatted_val, config_path.display());
    }

    if let Some(key) = get {
        let lookup_key = key.trim();
        if !config_path.exists() {
            if let Some(default_val) = read_toml_value(DEFAULT_CONFIG, lookup_key) {
                println!("{} = {} (default)", lookup_key, default_val);
            } else {
                anyhow::bail!(
                    "Key '{}' not found (and no config file at {})",
                    lookup_key,
                    config_path.display()
                );
            }
            return Ok(());
        }
        let content = std::fs::read_to_string(&config_path)?;
        if let Some(val) = read_toml_value(&content, lookup_key) {
            println!("{}", val);
        } else {
            anyhow::bail!("Key '{}' not found in {}", lookup_key, config_path.display());
        }
    }

    Ok(())
}

fn split_section_and_key(dotted_key: &str) -> (Option<&str>, &str) {
    if let Some((sec, k)) = dotted_key.rsplit_once('.') {
        (Some(sec.trim()), k.trim())
    } else {
        (None, dotted_key.trim())
    }
}

fn format_toml_scalar(raw: &str) -> String {
    let trimmed = raw.trim();
    if (trimmed.starts_with('"') && trimmed.ends_with('"') && trimmed.len() >= 2)
        || (trimmed.starts_with('\'') && trimmed.ends_with('\'') && trimmed.len() >= 2)
    {
        return trimmed.to_string();
    }
    if trimmed.eq_ignore_ascii_case("true") || trimmed.eq_ignore_ascii_case("false") {
        return trimmed.to_ascii_lowercase();
    }
    if trimmed.parse::<i64>().is_ok() || trimmed.parse::<f64>().is_ok() {
        return trimmed.to_string();
    }
    if trimmed.starts_with('[') && trimmed.ends_with(']') {
        return trimmed.to_string();
    }
    let escaped = trimmed.replace('\\', "\\\\").replace('"', "\\\"");
    format!("\"{}\"", escaped)
}

fn strip_toml_quotes_and_comments(raw_rhs: &str) -> String {
    let trimmed = raw_rhs.trim();
    if let Some(rest) = trimmed.strip_prefix('"') {
        let mut out = String::new();
        let mut escaped = false;
        for ch in rest.chars() {
            if escaped {
                out.push(ch);
                escaped = false;
            } else if ch == '\\' {
                escaped = true;
            } else if ch == '"' {
                break;
            } else {
                out.push(ch);
            }
        }
        return out;
    }
    if let Some(rest) = trimmed.strip_prefix('\'') {
        if let Some(end_idx) = rest.find('\'') {
            return rest[..end_idx].to_string();
        }
    }
    let without_comment = trimmed.split('#').next().unwrap_or(trimmed).trim();
    without_comment.to_string()
}

/// Reads a `section.key` (or top-level `key`) from TOML text while ignoring comments.
pub fn read_toml_value(toml_text: &str, dotted_key: &str) -> Option<String> {
    let (target_sec, target_key) = split_section_and_key(dotted_key);
    let mut current_sec: Option<String> = None;

    for line in toml_text.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if trimmed.starts_with('[') && !trimmed.starts_with("[[") {
            if let Some(end) = trimmed.find(']') {
                current_sec = Some(trimmed[1..end].trim().to_string());
            }
            continue;
        }
        let sec_matches = match (&target_sec, &current_sec) {
            (Some(want), Some(cur)) => *want == cur.as_str(),
            (None, None) => true,
            _ => false,
        };
        if !sec_matches {
            continue;
        }
        if let Some((lhs, rhs)) = trimmed.split_once('=') {
            if lhs.trim() == target_key {
                return Some(strip_toml_quotes_and_comments(rhs));
            }
        }
    }
    None
}

/// Updates or inserts `section.key = value` while preserving comments and formatting in `config.toml`.
pub fn upsert_toml_value(toml_text: &str, dotted_key: &str, raw_value: &str) -> String {
    let (target_sec, target_key) = split_section_and_key(dotted_key);
    let formatted_val = format_toml_scalar(raw_value);
    let new_assignment = format!("{} = {}", target_key, formatted_val);

    let mut lines: Vec<String> = toml_text.lines().map(|l| l.to_string()).collect();
    let mut current_sec: Option<String> = None;
    let mut matched_line_idx: Option<usize> = None;
    let mut last_line_in_target_sec: Option<usize> = None;

    for (idx, line) in lines.iter().enumerate() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') && !trimmed.starts_with("[[") {
            if let Some(end) = trimmed.find(']') {
                current_sec = Some(trimmed[1..end].trim().to_string());
                if target_sec == current_sec.as_deref() {
                    last_line_in_target_sec = Some(idx);
                }
            }
            continue;
        }

        let sec_matches = match (&target_sec, &current_sec) {
            (Some(want), Some(cur)) => *want == cur.as_str(),
            (None, None) => true,
            _ => false,
        };
        if sec_matches {
            if !trimmed.is_empty() {
                last_line_in_target_sec = Some(idx);
            }
            if !trimmed.starts_with('#') {
                if let Some((lhs, _)) = trimmed.split_once('=') {
                    if lhs.trim() == target_key {
                        matched_line_idx = Some(idx);
                        break;
                    }
                }
            }
        }
    }

    if let Some(idx) = matched_line_idx {
        lines[idx] = new_assignment;
    } else if let Some(insert_after) = last_line_in_target_sec {
        lines.insert(insert_after + 1, new_assignment);
    } else if let Some(sec) = target_sec {
        if !lines.is_empty() && !lines.last().unwrap().trim().is_empty() {
            lines.push(String::new());
        }
        lines.push(format!("[{}]", sec));
        lines.push(new_assignment);
    } else {
        lines.insert(0, new_assignment);
    }

    let mut out = lines.join("\n");
    if !out.ends_with('\n') {
        out.push('\n');
    }
    out
}

const DEFAULT_CONFIG: &str = r#"# MicroCode CLI Configuration

[ai]
# Default AI provider: gemini, openai, anthropic, local
provider = "gemini"
# Default model (leave empty to use provider default)
model = ""
# Maximum agent iterations per request
max_iterations = 25
# Temperature for AI responses
temperature = 0.0

[verification]
# Enable shadow workspace verification by default
enabled = false
# Build command to run in shadow workspace
build_command = ""
# Test command to run in shadow workspace
test_command = ""

[editor]
# Preferred editor for opening files
editor = ""

[session]
# Auto-save session history
auto_save = true
# Maximum session history entries
max_history = 1000

[tools]
# Shell command timeout (seconds)
shell_timeout = 120
# Auto-approve read-only tools
auto_approve_reads = true
"#;

const DEFAULT_RULES: &str = r#"# MicroCode Project Rules

## Project Context
<!-- Describe your project here -->

## Coding Standards
<!-- Add your coding standards -->

## Important Notes
<!-- Add any important notes for the AI agent -->
"#;

const DEFAULT_ENV: &str = r#"# MicroCode API Keys
# Uncomment and fill in your API keys

# GEMINI_API_KEY=your-key-here
# OPENAI_API_KEY=your-key-here
# ANTHROPIC_API_KEY=your-key-here
"#;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_toml_read_and_upsert_preserves_comments() {
        assert_eq!(
            read_toml_value(DEFAULT_CONFIG, "ai.provider"),
            Some("gemini".to_string())
        );
        assert_eq!(
            read_toml_value(DEFAULT_CONFIG, "ai.max_iterations"),
            Some("25".to_string())
        );
        assert_eq!(
            read_toml_value(DEFAULT_CONFIG, "tools.auto_approve_reads"),
            Some("true".to_string())
        );

        let updated = upsert_toml_value(DEFAULT_CONFIG, "ai.provider", "anthropic");
        assert!(updated.contains("# Default AI provider: gemini, openai, anthropic, local"));
        assert_eq!(
            read_toml_value(&updated, "ai.provider"),
            Some("anthropic".to_string())
        );

        let updated2 = upsert_toml_value(&updated, "ai.max_iterations", "42");
        assert_eq!(
            read_toml_value(&updated2, "ai.max_iterations"),
            Some("42".to_string())
        );

        let updated3 = upsert_toml_value(&updated2, "custom.capsule_auto_export", "true");
        assert_eq!(
            read_toml_value(&updated3, "custom.capsule_auto_export"),
            Some("true".to_string())
        );
    }
}
