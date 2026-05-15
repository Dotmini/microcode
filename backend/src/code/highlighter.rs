//! Syntax highlighter module
//!
//! Provides syntax highlighting using syntect library

use crate::error::{AppError, Result};
use crate::models::HighlightToken;
use lazy_static::lazy_static;
use std::borrow::Cow;
use syntect::easy::HighlightLines;
use syntect::highlighting::{Style, ThemeSet};
use syntect::parsing::SyntaxSet;
use syntect::util::LinesWithEndings;

lazy_static! {
    static ref SYNTAX_SET: SyntaxSet = SyntaxSet::load_defaults_newlines();
    static ref THEME_SET: ThemeSet = ThemeSet::load_defaults();
}

/// Initialize the highlighter (warm up caches)
pub fn init() {
    lazy_static::initialize(&SYNTAX_SET);
    lazy_static::initialize(&THEME_SET);
}

/// Highlight code and return tokens
pub async fn highlight(code: &str, language: &str) -> Result<Vec<HighlightToken>> {
    // strict caching: use static sets
    let ps = &SYNTAX_SET;
    let ts = &THEME_SET;

    let language = normalize_language(language);

    // Find syntax definition
    let syntax = ps
        .find_syntax_by_extension(language.as_ref())
        .or_else(|| ps.find_syntax_by_name(language.as_ref()))
        .or_else(|| Some(ps.find_syntax_plain_text()));

    let syntax = syntax.ok_or_else(|| {
        AppError::HighlightError(format!("No syntax found for language: {}", language))
    })?;

    // Use a default theme
    // Check if the requested theme exists, otherwise fallback
    let theme = ts
        .themes
        .get("base16-ocean.dark")
        .or_else(|| ts.themes.values().next()) // Fallback to any available
        .ok_or_else(|| AppError::HighlightError("No themes available".to_string()))?;

    let mut highlighter = HighlightLines::new(syntax, theme);
    let mut tokens = Vec::new();
    // AppKit uses UTF-16 based NSRange offsets. Returning byte offsets corrupts
    // ranges for non-ASCII source and can crash clients when they apply tokens.
    let mut utf16_offset = 0;

    for line in LinesWithEndings::from(code) {
        let ranges = highlighter
            .highlight_line(line, ps)
            .map_err(|e| AppError::HighlightError(e.to_string()))?;

        for (style, text) in ranges {
            let token_type = style_to_token_type(style);
            let start = utf16_offset;
            let end = utf16_offset + text.encode_utf16().count();

            tokens.push(HighlightToken {
                text: text.to_string(),
                token_type,
                start,
                end,
            });

            utf16_offset = end;
        }
    }

    Ok(tokens)
}

fn normalize_language(language: &str) -> Cow<'_, str> {
    let trimmed = language.trim();
    match trimmed.to_ascii_lowercase().as_str() {
        "objective-c++" | "objc++" => Cow::Borrowed("mm"),
        "objective-c" | "objc" => Cow::Borrowed("m"),
        "c++" => Cow::Borrowed("cpp"),
        "javascript" => Cow::Borrowed("js"),
        "typescript" => Cow::Borrowed("ts"),
        "python" => Cow::Borrowed("py"),
        "shell" => Cow::Borrowed("sh"),
        "markdown" => Cow::Borrowed("md"),
        _ => Cow::Borrowed(trimmed),
    }
}

/// Convert syntect Style to a token type string
fn style_to_token_type(style: Style) -> String {
    // Map foreground colors to semantic token types
    let fg = style.foreground;

    // This is a simplified mapping - in production you'd want more sophisticated logic
    if fg.r > 200 && fg.g < 100 && fg.b < 100 {
        "keyword".to_string()
    } else if fg.r < 100 && fg.g > 200 && fg.b < 100 {
        "string".to_string()
    } else if fg.r < 100 && fg.g < 100 && fg.b > 200 {
        "function".to_string()
    } else if fg.r > 200 && fg.g > 200 && fg.b < 100 {
        "variable".to_string()
    } else if fg.r > 150 && fg.g > 150 && fg.b > 150 {
        "comment".to_string()
    } else {
        "text".to_string()
    }
}

/// Get available themes
pub fn get_available_themes() -> Vec<String> {
    THEME_SET.themes.keys().cloned().collect()
}

/// Get available languages
pub fn get_available_languages() -> Vec<String> {
    SYNTAX_SET
        .syntaxes()
        .iter()
        .map(|s| s.name.clone())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_highlight_rust() {
        let code = "fn main() {\n    println!(\"Hello, world!\");\n}";
        let result = highlight(code, "rust").await;
        assert!(result.is_ok());
        let tokens = result.unwrap();
        assert!(!tokens.is_empty());
    }

    #[tokio::test]
    async fn test_highlight_python() {
        let code = "def hello():\n    print('Hello')\n";
        let result = highlight(code, "python").await;
        assert!(result.is_ok());
        let tokens = result.unwrap();
        assert!(!tokens.is_empty());
    }

    #[tokio::test]
    async fn test_highlight_offsets_are_utf16() {
        let code = "print('สวัสดี')\nlet x = 1";
        let tokens = highlight(code, "python").await.unwrap();
        let last = tokens.last().unwrap();
        assert!(last.end <= code.encode_utf16().count());
        assert!(last.end > code.len() / 2);
    }

    #[test]
    fn test_get_themes() {
        let themes = get_available_themes();
        assert!(!themes.is_empty());
    }

    #[test]
    fn test_get_languages() {
        let languages = get_available_languages();
        assert!(!languages.is_empty());
    }
}
