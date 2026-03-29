//! Code formatter module
//!
//! Provides code formatting for multiple languages

use crate::error::{AppError, Result};

/// Format code according to language-specific style guidelines
pub async fn format(code: &str, language: &str) -> Result<String> {
    match language.to_lowercase().as_str() {
        "python" => format_python(code).await,
        "javascript" | "js" => format_javascript(code).await,
        "rust" => format_rust(code).await,
        "swift" => format_swift(code).await,
        "go" => format_go(code).await,
        _ => {
            // Return code as-is for unsupported languages
            Ok(code.to_string())
        }
    }
}

async fn format_python(code: &str) -> Result<String> {
    // In production, you would use black, autopep8, or yapf
    // For now, return basic formatting

    // Try to use black if available
    match try_format_with_command("black", &["-"], code).await {
        Ok(formatted) => Ok(formatted),
        Err(_) => Ok(code.to_string()), // Fallback to original
    }
}

async fn format_javascript(code: &str) -> Result<String> {
    // In production, you would use prettier or eslint

    // Try to use prettier if available
    match try_format_with_command("prettier", &["--parser", "babel"], code).await {
        Ok(formatted) => Ok(formatted),
        Err(_) => Ok(code.to_string()), // Fallback to original
    }
}

async fn format_rust(code: &str) -> Result<String> {
    // Use rustfmt if available
    match try_format_with_command("rustfmt", &["--edition", "2021"], code).await {
        Ok(formatted) => Ok(formatted),
        Err(_) => Ok(code.to_string()), // Fallback to original
    }
}

async fn format_swift(code: &str) -> Result<String> {
    // Use swift-format if available
    match try_format_with_command("swift-format", &[], code).await {
        Ok(formatted) => Ok(formatted),
        Err(_) => Ok(code.to_string()), // Fallback to original
    }
}

async fn format_go(code: &str) -> Result<String> {
    // Use gofmt if available
    match try_format_with_command("gofmt", &[], code).await {
        Ok(formatted) => Ok(formatted),
        Err(_) => Ok(code.to_string()), // Fallback to original
    }
}

/// Format code using AI with custom instructions (AI Formatter Ultra)
pub async fn format_with_ai(code: &str, language: &str, instructions: &str) -> Result<String> {
    use crate::models::AIConfig;
    
    // Default to a capable model for formatting
    let config = AIConfig {
        provider: "gemini".to_string(), // Or make this configurable
        model: "gemini-2.5-flash".to_string(),
        api_key: "".to_string(), // Will use env var
        temperature: 0.1, // Low temperature for deterministic formatting
        max_tokens: 8192, // High token limit for long code
        microrent_token: None,
        use_microrent_proxy: false,
    };

    let prompt = format!(
        "You are an expert code formatter. Format the following {} code according to these instructions:\n\
        Instructions: {}\n\n\
        Code:\n```\n{}\n```\n\n\
        IMPORTANT: Return ONLY the formatted code. Do not wrap it in markdown code blocks. Do not explain your changes. Return the FULL code without truncation.",
        language, instructions, code
    );

    let formatted = crate::ai::get_provider(&config.provider)?
        .generate(&prompt, &config)
        .await?;
        
    // Clean up potential markdown if the model ignored instructions
    let clean_code = if formatted.starts_with("```") {
         let lines: Vec<&str> = formatted.lines().collect();
         if lines.len() >= 2 && lines[0].starts_with("```") && lines.last().unwrap_or(&"").starts_with("```") {
             lines[1..lines.len()-1].join("\n")
         } else {
             formatted
         }
    } else {
        formatted
    };

    Ok(clean_code)
}

/// Try to format code using an external command
async fn try_format_with_command(
    command: &str,
    args: &[&str],
    code: &str,
) -> Result<String> {
    use tokio::io::AsyncWriteExt;
    use tokio::process::Command;
    use std::process::Stdio;

    let mut child = Command::new(command)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| AppError::InternalError(format!("Failed to spawn {}: {}", command, e)))?;

    // Write code to stdin
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(code.as_bytes())
            .await
            .map_err(|e| AppError::InternalError(format!("Failed to write to stdin: {}", e)))?;
        stdin
            .shutdown()
            .await
            .map_err(|e| AppError::InternalError(format!("Failed to close stdin: {}", e)))?;
    }

    // Wait for process to complete
    let output = child
        .wait_with_output()
        .await
        .map_err(|e| AppError::InternalError(format!("Failed to wait for {}: {}", command, e)))?;

    if output.status.success() {
        String::from_utf8(output.stdout)
            .map_err(|e| AppError::InternalError(format!("Invalid UTF-8 output: {}", e)))
    } else {
        let error = String::from_utf8_lossy(&output.stderr);
        Err(AppError::InternalError(format!(
            "{} failed: {}",
            command, error
        )))
    }
}

/// Basic manual formatting (fallback when no formatter is available)
fn basic_format(code: &str) -> String {
    let mut result = String::new();
    let mut indent_level: usize = 0;
    const INDENT: &str = "    ";

    for line in code.lines() {
        let trimmed = line.trim();

        if trimmed.is_empty() {
            result.push('\n');
            continue;
        }

        // Decrease indent for closing braces
        if trimmed.starts_with('}') || trimmed.starts_with(']') || trimmed.starts_with(')') {
            indent_level = indent_level.saturating_sub(1);
        }

        // Add indentation
        for _ in 0..indent_level {
            result.push_str(INDENT);
        }
        result.push_str(trimmed);
        result.push('\n');

        // Increase indent for opening braces
        if trimmed.ends_with('{') || trimmed.ends_with('[') || trimmed.ends_with('(') {
            indent_level += 1;
        }
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_format_basic() {
        let code = "fn main() {\nprintln!(\"Hello\");\n}";
        let result = format(code, "rust").await;
        assert!(result.is_ok());
    }

    #[test]
    fn test_basic_format() {
        let code = "fn main() {\nprintln!(\"Hello\");\n}";
        let formatted = basic_format(code);
        assert!(formatted.contains("    "));
    }
}
