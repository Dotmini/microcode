// AI Agent Indexer - Tree-sitter based semantic chunking

use crate::error::{AppError, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;
use tree_sitter::{Language, Node, Parser};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CodeChunk {
    pub file_path: String,
    pub start_line: usize,
    pub end_line: usize,
    pub content: String,
    pub symbol_name: Option<String>,
    pub symbol_kind: String, // "function", "class", "method", "module"
}

pub struct Indexer {
    parser: Parser,
}

impl Indexer {
    pub fn new() -> Self {
        Self {
            parser: Parser::new(),
        }
    }

    pub fn chunk_file(&mut self, path: &Path, content: &str) -> Result<Vec<CodeChunk>> {
        let extension = path.extension().and_then(|e| e.to_str()).unwrap_or("");

        let language = match extension {
            "py" => Some(tree_sitter_python::language()),
            "rs" => Some(tree_sitter_rust::language()),
            "js" => Some(tree_sitter_javascript::language()),
            _ => None,
        };

        if let Some(lang) = language {
            self.parser.set_language(lang).map_err(|e| {
                AppError::InternalError(format!("Failed to set TS language: {}", e))
            })?;

            let tree = self
                .parser
                .parse(content, None)
                .ok_or_else(|| AppError::InternalError("Failed to parse code".to_string()))?;

            let mut chunks = Vec::new();
            self.extract_chunks(path, content, tree.root_node(), &mut chunks);

            // If no semantic chunks found, fallback to line-based chunking
            if chunks.is_empty() {
                chunks.push(CodeChunk {
                    file_path: path.to_string_lossy().to_string(),
                    start_line: 1,
                    end_line: content.lines().count(),
                    content: content.to_string(),
                    symbol_name: None,
                    symbol_kind: "module".to_string(),
                });
            }

            Ok(chunks)
        } else {
            // Non-supported language: just treat as one big chunk or skip
            Ok(vec![CodeChunk {
                file_path: path.to_string_lossy().to_string(),
                start_line: 1,
                end_line: content.lines().count(),
                content: content.to_string(),
                symbol_name: None,
                symbol_kind: "file".to_string(),
            }])
        }
    }

    fn extract_chunks(&self, path: &Path, content: &str, node: Node, chunks: &mut Vec<CodeChunk>) {
        let kind = node.kind();

        let should_chunk = match kind {
            "function_definition" | "decorated_definition" | "class_definition" => true, // Python
            "function_item" | "struct_item" | "enum_item" | "impl_item" | "trait_item" => true, // Rust
            "function_declaration" | "class_declaration" | "method_definition" => true, // JS
            _ => false,
        };

        if should_chunk {
            let start = node.start_position().row + 1;
            let end = node.end_position().row + 1;
            let chunk_content = &content[node.byte_range()];

            // Try to find identifier
            let name = node
                .child_by_field_name("name")
                .map(|n| &content[n.byte_range()])
                .map(|s| s.to_string());

            chunks.push(CodeChunk {
                file_path: path.to_string_lossy().to_string(),
                start_line: start,
                end_line: end,
                content: chunk_content.to_string(),
                symbol_name: name,
                symbol_kind: kind.to_string(),
            });
        }

        // Recurse into children
        let mut cursor = node.walk();
        for child in node.children(&mut cursor) {
            self.extract_chunks(path, content, child, chunks);
        }
    }
}
