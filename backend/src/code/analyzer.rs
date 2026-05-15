//! Code analyzer module
//!
//! Provides static code analysis for multiple languages

use crate::error::Result;
use crate::models::{ClassInfo, CodeAnalysis, CodeIssue, FunctionInfo};

/// Analyze code and return analysis results
pub async fn analyze(code: &str, language: &str) -> Result<CodeAnalysis> {
    match language.to_lowercase().as_str() {
        "python" => analyze_python(code).await,
        "javascript" | "js" => analyze_javascript(code).await,
        "rust" => analyze_rust(code).await,
        "swift" => analyze_swift(code).await,
        _ => {
            // Return basic analysis for unsupported languages
            Ok(CodeAnalysis {
                language: language.to_string(),
                lines: code.lines().count(),
                functions: vec![],
                classes: vec![],
                imports: vec![],
                complexity: None,
                issues: vec![],
            })
        }
    }
}

async fn analyze_python(code: &str) -> Result<CodeAnalysis> {
    let lines = code.lines().count();
    let mut functions = Vec::new();
    let mut classes = Vec::new();
    let mut imports = Vec::new();
    let mut issues = Vec::new();

    // Simple regex-based parsing (in production, use a proper parser)
    for (line_num, line) in code.lines().enumerate() {
        let trimmed = line.trim();

        // Find imports
        if trimmed.starts_with("import ") || trimmed.starts_with("from ") {
            imports.push(trimmed.to_string());
        }

        // Find function definitions
        if trimmed.starts_with("def ") {
            if let Some(func_name) = extract_function_name(trimmed) {
                functions.push(FunctionInfo {
                    name: func_name,
                    line: line_num + 1,
                    parameters: extract_parameters(trimmed),
                    return_type: extract_return_type(trimmed),
                });
            }
        }

        // Find class definitions
        if trimmed.starts_with("class ") {
            if let Some(class_name) = extract_class_name(trimmed) {
                classes.push(ClassInfo {
                    name: class_name,
                    line: line_num + 1,
                    methods: vec![],
                    properties: vec![],
                });
            }
        }

        // Simple linting checks
        if line.len() > 120 {
            issues.push(CodeIssue {
                severity: "warning".to_string(),
                message: "Line exceeds 120 characters".to_string(),
                line: line_num + 1,
                column: Some(120),
            });
        }
    }

    Ok(CodeAnalysis {
        language: "python".to_string(),
        lines,
        functions,
        classes,
        imports,
        complexity: Some(calculate_complexity(code)),
        issues,
    })
}

async fn analyze_javascript(code: &str) -> Result<CodeAnalysis> {
    let lines = code.lines().count();
    let mut functions = Vec::new();
    let mut classes = Vec::new();
    let mut imports = Vec::new();
    let mut issues = Vec::new();

    for (line_num, line) in code.lines().enumerate() {
        let trimmed = line.trim();

        // Find imports
        if trimmed.starts_with("import ") || trimmed.starts_with("require(") {
            imports.push(trimmed.to_string());
        }

        // Find function definitions
        if trimmed.starts_with("function ")
            || trimmed.contains("=> ")
            || trimmed.contains("async function")
        {
            if let Some(func_name) = extract_js_function_name(trimmed) {
                functions.push(FunctionInfo {
                    name: func_name,
                    line: line_num + 1,
                    parameters: vec![],
                    return_type: None,
                });
            }
        }

        // Find class definitions
        if trimmed.starts_with("class ") {
            if let Some(class_name) = extract_class_name(trimmed) {
                classes.push(ClassInfo {
                    name: class_name,
                    line: line_num + 1,
                    methods: vec![],
                    properties: vec![],
                });
            }
        }

        // Simple linting
        if trimmed.contains("var ") {
            issues.push(CodeIssue {
                severity: "warning".to_string(),
                message: "Use 'const' or 'let' instead of 'var'".to_string(),
                line: line_num + 1,
                column: None,
            });
        }
    }

    Ok(CodeAnalysis {
        language: "javascript".to_string(),
        lines,
        functions,
        classes,
        imports,
        complexity: Some(calculate_complexity(code)),
        issues,
    })
}

async fn analyze_rust(code: &str) -> Result<CodeAnalysis> {
    let lines = code.lines().count();
    let mut functions = Vec::new();
    let mut classes = Vec::new();
    let mut imports = Vec::new();
    let mut issues = Vec::new();

    for (line_num, line) in code.lines().enumerate() {
        let trimmed = line.trim();

        // Find imports
        if trimmed.starts_with("use ") {
            imports.push(trimmed.to_string());
        }

        // Find function definitions
        if trimmed.starts_with("fn ") || trimmed.starts_with("pub fn ") {
            if let Some(func_name) = extract_rust_function_name(trimmed) {
                functions.push(FunctionInfo {
                    name: func_name,
                    line: line_num + 1,
                    parameters: vec![],
                    return_type: extract_rust_return_type(trimmed),
                });
            }
        }

        // Find struct definitions (closest to classes)
        if trimmed.starts_with("struct ") || trimmed.starts_with("pub struct ") {
            if let Some(struct_name) = extract_rust_struct_name(trimmed) {
                classes.push(ClassInfo {
                    name: struct_name,
                    line: line_num + 1,
                    methods: vec![],
                    properties: vec![],
                });
            }
        }
    }

    Ok(CodeAnalysis {
        language: "rust".to_string(),
        lines,
        functions,
        classes,
        imports,
        complexity: Some(calculate_complexity(code)),
        issues,
    })
}

async fn analyze_swift(code: &str) -> Result<CodeAnalysis> {
    let lines = code.lines().count();
    let mut functions = Vec::new();
    let mut classes = Vec::new();
    let mut imports = Vec::new();
    let mut issues = Vec::new();

    for (line_num, line) in code.lines().enumerate() {
        let trimmed = line.trim();

        // Find imports
        if trimmed.starts_with("import ") {
            imports.push(trimmed.to_string());
        }

        // Find function definitions
        if trimmed.starts_with("func ") {
            if let Some(func_name) = extract_swift_function_name(trimmed) {
                functions.push(FunctionInfo {
                    name: func_name,
                    line: line_num + 1,
                    parameters: vec![],
                    return_type: extract_swift_return_type(trimmed),
                });
            }
        }

        // Find class/struct definitions
        if trimmed.starts_with("class ")
            || trimmed.starts_with("struct ")
            || trimmed.starts_with("enum ")
        {
            if let Some(name) = extract_swift_type_name(trimmed) {
                classes.push(ClassInfo {
                    name,
                    line: line_num + 1,
                    methods: vec![],
                    properties: vec![],
                });
            }
        }
    }

    Ok(CodeAnalysis {
        language: "swift".to_string(),
        lines,
        functions,
        classes,
        imports,
        complexity: Some(calculate_complexity(code)),
        issues,
    })
}

// Helper functions

fn extract_function_name(line: &str) -> Option<String> {
    let parts: Vec<&str> = line.split_whitespace().collect();
    if parts.len() >= 2 && parts[0] == "def" {
        let name = parts[1].split('(').next()?;
        return Some(name.to_string());
    }
    None
}

fn extract_class_name(line: &str) -> Option<String> {
    let parts: Vec<&str> = line.split_whitespace().collect();
    if parts.len() >= 2 && parts[0] == "class" {
        let name = parts[1].split('(').next()?.split(':').next()?;
        return Some(name.to_string());
    }
    None
}

fn extract_parameters(line: &str) -> Vec<String> {
    if let Some(start) = line.find('(') {
        if let Some(end) = line.find(')') {
            let params = &line[start + 1..end];
            return params
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect();
        }
    }
    vec![]
}

fn extract_return_type(line: &str) -> Option<String> {
    if let Some(pos) = line.find("->") {
        let return_type = line[pos + 2..].trim().trim_end_matches(':');
        return Some(return_type.to_string());
    }
    None
}

fn extract_js_function_name(line: &str) -> Option<String> {
    if line.contains("function ") {
        let parts: Vec<&str> = line.split_whitespace().collect();
        for (i, part) in parts.iter().enumerate() {
            if *part == "function" && i + 1 < parts.len() {
                let name = parts[i + 1].split('(').next()?;
                return Some(name.to_string());
            }
        }
    } else if line.contains("const ") || line.contains("let ") {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 2 {
            let name = parts[1].split('=').next()?.trim();
            return Some(name.to_string());
        }
    }
    None
}

fn extract_rust_function_name(line: &str) -> Option<String> {
    let parts: Vec<&str> = line.split_whitespace().collect();
    for (i, part) in parts.iter().enumerate() {
        if *part == "fn" && i + 1 < parts.len() {
            let name = parts[i + 1].split('(').next()?;
            return Some(name.to_string());
        }
    }
    None
}

fn extract_rust_return_type(line: &str) -> Option<String> {
    if let Some(pos) = line.find("->") {
        let return_type = line[pos + 2..].trim().trim_end_matches('{').trim();
        return Some(return_type.to_string());
    }
    None
}

fn extract_rust_struct_name(line: &str) -> Option<String> {
    let parts: Vec<&str> = line.split_whitespace().collect();
    for (i, part) in parts.iter().enumerate() {
        if *part == "struct" && i + 1 < parts.len() {
            let name = parts[i + 1].split('<').next()?.split('{').next()?.trim();
            return Some(name.to_string());
        }
    }
    None
}

fn extract_swift_function_name(line: &str) -> Option<String> {
    let parts: Vec<&str> = line.split_whitespace().collect();
    for (i, part) in parts.iter().enumerate() {
        if *part == "func" && i + 1 < parts.len() {
            let name = parts[i + 1].split('(').next()?.split('<').next()?;
            return Some(name.to_string());
        }
    }
    None
}

fn extract_swift_return_type(line: &str) -> Option<String> {
    if let Some(pos) = line.find("->") {
        let return_type = line[pos + 2..].trim().trim_end_matches('{').trim();
        return Some(return_type.to_string());
    }
    None
}

fn extract_swift_type_name(line: &str) -> Option<String> {
    let parts: Vec<&str> = line.split_whitespace().collect();
    if parts.len() >= 2 {
        let name = parts[1]
            .split(':')
            .next()?
            .split('{')
            .next()?
            .split('<')
            .next()?
            .trim();
        return Some(name.to_string());
    }
    None
}

fn calculate_complexity(code: &str) -> usize {
    let mut complexity = 1; // Base complexity

    // Count decision points
    for line in code.lines() {
        let line_lower = line.to_lowercase();
        if line_lower.contains("if ") {
            complexity += 1;
        }
        if line_lower.contains("else if ") || line_lower.contains("elif ") {
            complexity += 1;
        }
        if line_lower.contains("for ") || line_lower.contains("while ") {
            complexity += 1;
        }
        if line_lower.contains("case ") || line_lower.contains("when ") {
            complexity += 1;
        }
        if line_lower.contains("catch ") {
            complexity += 1;
        }
        if line_lower.contains("&&") || line_lower.contains("||") {
            complexity += 1;
        }
    }

    complexity
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_python_analysis() {
        let code = r#"
import os
import sys

def hello(name):
    print(f"Hello, {name}")

class MyClass:
    def __init__(self):
        pass
"#;

        let result = analyze(code, "python").await;
        assert!(result.is_ok());
        let analysis = result.unwrap();
        assert_eq!(analysis.language, "python");
        assert!(analysis.functions.len() > 0);
        assert!(analysis.classes.len() > 0);
        assert!(analysis.imports.len() > 0);
    }
}
