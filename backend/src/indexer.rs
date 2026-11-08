// AI Agent Indexer - Tree-sitter based semantic chunking & Reference-Ranked RepoMap

use crate::error::{AppError, Result};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::path::Path;
use tree_sitter::{Node, Parser};
use walkdir::WalkDir;

const MAX_CHUNK_BYTES: usize = 8 * 1024;
pub const DEFAULT_REPO_MAP_TOKENS: usize = 1_000;
const MAX_REPO_MAP_FILES: usize = 2_500;
const MAX_REPO_MAP_FILE_BYTES: u64 = 512 * 1024;

fn compact_chunk_content(content: &str) -> String {
    if content.len() <= MAX_CHUNK_BYTES {
        return content.to_string();
    }

    let mut end = MAX_CHUNK_BYTES;
    while end > 0 && !content.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}\n…[symbol body truncated]…", &content[..end])
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CodeChunk {
    pub file_path: String,
    pub start_line: usize,
    pub end_line: usize,
    pub content: String,
    pub symbol_name: Option<String>,
    pub symbol_kind: String, // "function", "class", "method", "module"
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepoSymbol {
    pub name: String,
    pub kind: String,
    pub line: usize,
    pub signature: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepoMapEntry {
    pub relative_path: String,
    pub symbols: Vec<RepoSymbol>,
    pub cross_file_refs: usize,
    pub score: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepoMapReport {
    pub formatted: String,
    pub total_files: usize,
    pub total_symbols: usize,
    pub estimated_tokens: usize,
    pub entries: Vec<RepoMapEntry>,
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
            "js" | "jsx" => Some(tree_sitter_javascript::language()),
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
                    content: compact_chunk_content(content),
                    symbol_name: None,
                    symbol_kind: "module".to_string(),
                });
            }

            Ok(chunks)
        } else {
            // Non-Tree-sitter language: try structural declaration chunking (Swift, TS, Go, C/C++)
            let decls = extract_fallback_declarations(extension, content);
            if !decls.is_empty() {
                let total_lines = content.lines().count().max(1);
                let mut chunks = Vec::with_capacity(decls.len());
                for (idx, sym) in decls.iter().enumerate() {
                    let end_line = decls
                        .get(idx + 1)
                        .map(|next| next.line.saturating_sub(1).max(sym.line))
                        .unwrap_or(total_lines);
                    chunks.push(CodeChunk {
                        file_path: path.to_string_lossy().to_string(),
                        start_line: sym.line,
                        end_line,
                        content: sym.signature.clone(),
                        symbol_name: Some(sym.name.clone()),
                        symbol_kind: sym.kind.clone(),
                    });
                }
                return Ok(chunks);
            }

            Ok(vec![CodeChunk {
                file_path: path.to_string_lossy().to_string(),
                start_line: 1,
                end_line: content.lines().count(),
                content: compact_chunk_content(content),
                symbol_name: None,
                symbol_kind: "file".to_string(),
            }])
        }
    }

    fn extract_chunks(&self, path: &Path, content: &str, node: Node, chunks: &mut Vec<CodeChunk>) {
        let kind = node.kind();

        let should_chunk = matches!(
            kind,
            "function_definition"
                | "decorated_definition"
                | "class_definition"
                | "function_item"
                | "struct_item"
                | "enum_item"
                | "impl_item"
                | "trait_item"
                | "function_declaration"
                | "class_declaration"
                | "method_definition"
        );

        if should_chunk {
            let start = node.start_position().row + 1;
            let end = node.end_position().row + 1;
            let chunk_content = &content[node.byte_range()];

            // Try to find identifier
            let name = node
                .child_by_field_name("name")
                .or_else(|| node.child_by_field_name("type"))
                .map(|n| &content[n.byte_range()])
                .map(|s| s.trim().to_string());

            chunks.push(CodeChunk {
                file_path: path.to_string_lossy().to_string(),
                start_line: start,
                end_line: end,
                content: compact_chunk_content(chunk_content),
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

    /// Extract defined symbols and referenced identifiers from a source file using
    /// Tree-sitter AST where available, or structural lexical scanning for Swift/TS/Go/C++.
    pub fn analyze_file_symbols_and_refs(
        &mut self,
        path: &Path,
        content: &str,
    ) -> (Vec<RepoSymbol>, HashSet<String>) {
        let extension = path.extension().and_then(|e| e.to_str()).unwrap_or("");
        let language = match extension {
            "py" => Some(tree_sitter_python::language()),
            "rs" => Some(tree_sitter_rust::language()),
            "js" | "jsx" => Some(tree_sitter_javascript::language()),
            _ => None,
        };

        if let Some(lang) = language {
            if self.parser.set_language(lang).is_ok() {
                if let Some(tree) = self.parser.parse(content, None) {
                    let mut symbols = Vec::new();
                    let mut refs = HashSet::new();
                    Self::walk_ast_symbols_and_refs(content, tree.root_node(), &mut symbols, &mut refs);
                    return (symbols, refs);
                }
            }
        }

        let symbols = extract_fallback_declarations(extension, content);
        let refs = extract_lexical_identifiers(content);
        (symbols, refs)
    }

    fn walk_ast_symbols_and_refs(
        content: &str,
        node: Node,
        symbols: &mut Vec<RepoSymbol>,
        refs: &mut HashSet<String>,
    ) {
        let kind = node.kind();

        let is_symbol_decl = matches!(
            kind,
            "function_definition"
                | "class_definition"
                | "function_item"
                | "struct_item"
                | "enum_item"
                | "trait_item"
                | "function_declaration"
                | "class_declaration"
                | "method_definition"
        );

        if is_symbol_decl {
            if let Some(name_node) = node
                .child_by_field_name("name")
                .or_else(|| node.child_by_field_name("type"))
            {
                let name = content[name_node.byte_range()].trim().to_string();
                if !name.is_empty() {
                    let line = node.start_position().row + 1;
                    let raw_first_line = content[node.byte_range()]
                        .lines()
                        .next()
                        .unwrap_or("")
                        .trim();
                    let sig = compact_signature(raw_first_line);
                    symbols.push(RepoSymbol {
                        name,
                        kind: normalize_symbol_kind(kind).to_string(),
                        line,
                        signature: sig,
                    });
                }
            }
        }

        if matches!(
            kind,
            "identifier" | "type_identifier" | "field_identifier" | "property_identifier"
        ) {
            let ident = content[node.byte_range()].trim();
            if ident.len() >= 3 && !is_common_noise_ident(ident) {
                refs.insert(ident.to_string());
            }
        }

        let mut cursor = node.walk();
        for child in node.children(&mut cursor) {
            Self::walk_ast_symbols_and_refs(content, child, symbols, refs);
        }
    }

    /// Build a reference-ranked, token-budgeted Repository Map (~1,000 tokens default).
    /// Files are ranked by cross-file symbol reference centrality (`cross_file_refs * 10 + symbols.len()`).
    pub fn build_repo_map(&mut self, root: &Path, max_tokens: usize) -> Result<RepoMapReport> {
        let token_budget = if max_tokens == 0 {
            DEFAULT_REPO_MAP_TOKENS
        } else {
            max_tokens.clamp(200, 8_000)
        };
        let char_budget = token_budget * 4;

        let mut file_symbols: Vec<(String, Vec<RepoSymbol>, HashSet<String>)> = Vec::new();
        let mut symbol_to_def_files: HashMap<String, Vec<usize>> = HashMap::new();

        let walker = WalkDir::new(root)
            .max_depth(8)
            .follow_links(false)
            .into_iter()
            .filter_entry(|e| !should_skip_entry(e.file_name().to_string_lossy().as_ref()));

        for entry in walker.flatten() {
            if file_symbols.len() >= MAX_REPO_MAP_FILES {
                break;
            }
            let path = entry.path();
            if !path.is_file() || !is_repo_map_source(path) {
                continue;
            }
            let Ok(meta) = entry.metadata() else {
                continue;
            };
            if meta.len() == 0 || meta.len() > MAX_REPO_MAP_FILE_BYTES {
                continue;
            }
            let Ok(content) = std::fs::read_to_string(path) else {
                continue;
            };

            let rel_path = path
                .strip_prefix(root)
                .unwrap_or(path)
                .to_string_lossy()
                .replace('\\', "/");

            let (symbols, refs) = self.analyze_file_symbols_and_refs(path, &content);
            let file_idx = file_symbols.len();
            for sym in &symbols {
                if sym.name.len() >= 3 && !is_common_noise_ident(&sym.name) {
                    symbol_to_def_files
                        .entry(sym.name.clone())
                        .or_default()
                        .push(file_idx);
                }
            }
            file_symbols.push((rel_path, symbols, refs));
        }

        // Compute cross-file reference counts for each file
        let mut inbound_refs = vec![0usize; file_symbols.len()];
        for (caller_idx, (_path, _syms, refs)) in file_symbols.iter().enumerate() {
            let mut touched_files = HashSet::new();
            for ident in refs {
                if let Some(def_indices) = symbol_to_def_files.get(ident) {
                    // Skip overly generic symbols defined in > 8 files
                    if def_indices.len() <= 8 {
                        for &def_idx in def_indices {
                            if def_idx != caller_idx {
                                touched_files.insert(def_idx);
                            }
                        }
                    }
                }
            }
            for def_idx in touched_files {
                inbound_refs[def_idx] += 1;
            }
        }

        let mut total_symbols = 0usize;
        let mut entries: Vec<RepoMapEntry> = file_symbols
            .into_iter()
            .enumerate()
            .map(|(idx, (relative_path, symbols, _refs))| {
                total_symbols += symbols.len();
                let cross_file_refs = inbound_refs[idx];
                let score = cross_file_refs * 10 + symbols.len();
                RepoMapEntry {
                    relative_path,
                    symbols,
                    cross_file_refs,
                    score,
                }
            })
            .collect();

        entries.sort_by(|a, b| {
            b.score
                .cmp(&a.score)
                .then_with(|| b.symbols.len().cmp(&a.symbols.len()))
                .then_with(|| a.relative_path.cmp(&b.relative_path))
        });

        let total_files = entries.len();
        let mut formatted = String::with_capacity(char_budget.min(16_384));
        formatted.push_str(&format!(
            "# Repository Map ({} files, {} symbols, ranked by cross-file references)\n",
            total_files, total_symbols
        ));

        let detailed_budget = (char_budget * 3) / 4;
        let mut omitted_files = 0usize;

        for entry in &entries {
            if formatted.len() >= char_budget {
                omitted_files += 1;
                continue;
            }

            if formatted.len() < detailed_budget && !entry.symbols.is_empty() {
                let header = format!(
                    "\n## {} (refs: {}, symbols: {})\n",
                    entry.relative_path,
                    entry.cross_file_refs,
                    entry.symbols.len()
                );
                if formatted.len() + header.len() > char_budget {
                    omitted_files += 1;
                    continue;
                }
                formatted.push_str(&header);

                for sym in entry.symbols.iter().take(12) {
                    let sym_line = format!("  L{:<4} [{}] {}\n", sym.line, sym.kind, sym.signature);
                    if formatted.len() + sym_line.len() > detailed_budget {
                        break;
                    }
                    formatted.push_str(&sym_line);
                }
            } else {
                let summary_line = format!(
                    "- {} (refs: {}, symbols: {})\n",
                    entry.relative_path,
                    entry.cross_file_refs,
                    entry.symbols.len()
                );
                if formatted.len() + summary_line.len() > char_budget {
                    omitted_files += 1;
                    continue;
                }
                formatted.push_str(&summary_line);
            }
        }

        if omitted_files > 0 {
            formatted.push_str(&format!(
                "... (+{} lower-ranked files omitted to fit {} token budget)\n",
                omitted_files, token_budget
            ));
        }

        let estimated_tokens = (formatted.chars().count() + 3) / 4;
        Ok(RepoMapReport {
            formatted,
            total_files,
            total_symbols,
            estimated_tokens,
            entries,
        })
    }
}

fn should_skip_entry(name: &str) -> bool {
    if name.is_empty() {
        return false;
    }
    (name.starts_with('.') && name != ".")
        || matches!(
            name,
            "node_modules"
                | "target"
                | "build"
                | "dist"
                | "Dist"
                | "Pods"
                | "DerivedData"
                | "__pycache__"
                | "vendor"
                | ".codetuner-build"
        )
}

fn is_repo_map_source(path: &Path) -> bool {
    matches!(
        path.extension().and_then(|e| e.to_str()),
        Some(
            "rs" | "swift"
                | "py"
                | "js"
                | "jsx"
                | "ts"
                | "tsx"
                | "go"
                | "c"
                | "cc"
                | "cpp"
                | "h"
                | "hpp"
                | "m"
                | "mm"
                | "java"
                | "kt"
        )
    )
}

fn normalize_symbol_kind(kind: &str) -> &'static str {
    match kind {
        "function_definition" | "function_item" | "function_declaration" => "fn",
        "method_definition" => "method",
        "class_definition" | "class_declaration" => "class",
        "struct_item" => "struct",
        "enum_item" => "enum",
        "trait_item" => "trait",
        "impl_item" => "impl",
        _ => "symbol",
    }
}

fn compact_signature(line: &str) -> String {
    let trimmed = line
        .trim_end_matches('{')
        .trim_end_matches(':')
        .trim();
    if trimmed.len() <= 96 {
        trimmed.to_string()
    } else {
        let mut end = 96;
        while end > 0 && !trimmed.is_char_boundary(end) {
            end -= 1;
        }
        format!("{}…", &trimmed[..end])
    }
}

fn is_common_noise_ident(ident: &str) -> bool {
    matches!(
        ident,
        "self"
            | "Self"
            | "super"
            | "new"
            | "default"
            | "clone"
            | "from"
            | "into"
            | "Some"
            | "None"
            | "Ok"
            | "Err"
            | "Result"
            | "Option"
            | "String"
            | "Vec"
            | "Box"
            | "Arc"
            | "true"
            | "false"
            | "null"
            | "undefined"
            | "return"
            | "async"
            | "await"
            | "const"
            | "let"
            | "var"
            | "func"
            | "function"
            | "class"
            | "struct"
            | "enum"
            | "impl"
            | "pub"
            | "private"
            | "public"
            | "internal"
            | "import"
            | "export"
            | "main"
            | "test"
            | "tests"
            | "err"
            | "error"
            | "ctx"
            | "req"
            | "res"
            | "val"
            | "value"
            | "data"
            | "item"
            | "items"
    )
}

fn extract_fallback_declarations(extension: &str, content: &str) -> Vec<RepoSymbol> {
    let mut symbols = Vec::new();
    for (idx, raw_line) in content.lines().enumerate() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with("//") || line.starts_with('#') || line.starts_with('*') {
            continue;
        }
        let line_num = idx + 1;
        match extension {
            "swift" => {
                for kw in ["func ", "struct ", "class ", "enum ", "protocol ", "actor "] {
                    if let Some(pos) = line.find(kw) {
                        if pos == 0 || line[..pos].split_whitespace().all(|w| {
                            matches!(
                                w,
                                "public" | "private" | "internal" | "fileprivate" | "open" | "static" | "final" | "override" | "@MainActor"
                            )
                        }) {
                            let rest = &line[pos + kw.len()..];
                            let name: String = rest
                                .chars()
                                .take_while(|c| c.is_alphanumeric() || *c == '_')
                                .collect();
                            if !name.is_empty() {
                                symbols.push(RepoSymbol {
                                    name,
                                    kind: kw.trim().to_string(),
                                    line: line_num,
                                    signature: compact_signature(line),
                                });
                            }
                            break;
                        }
                    }
                }
            }
            "ts" | "tsx" | "go" | "java" | "kt" | "c" | "cc" | "cpp" | "h" | "hpp" => {
                for kw in ["function ", "interface ", "class ", "type ", "func ", "struct ", "enum "] {
                    if let Some(pos) = line.find(kw) {
                        if pos == 0 || line[..pos].split_whitespace().all(|w| {
                            matches!(w, "export" | "default" | "async" | "public" | "private" | "protected" | "abstract" | "static" | "readonly")
                        }) {
                            let rest = line[pos + kw.len()..].trim_start();
                            // Handle Go receiver methods: `func (s *Server) Handle()`
                            let target = if kw == "func " && rest.starts_with('(') {
                                rest.find(')').map(|close| rest[close + 1..].trim_start()).unwrap_or(rest)
                            } else {
                                rest
                            };
                            let name: String = target
                                .chars()
                                .take_while(|c| c.is_alphanumeric() || *c == '_')
                                .collect();
                            if !name.is_empty() {
                                symbols.push(RepoSymbol {
                                    name,
                                    kind: kw.trim().to_string(),
                                    line: line_num,
                                    signature: compact_signature(line),
                                });
                            }
                            break;
                        }
                    }
                }
            }
            _ => {}
        }
    }
    symbols
}

fn extract_lexical_identifiers(content: &str) -> HashSet<String> {
    let mut refs = HashSet::new();
    for raw_line in content.lines() {
        let line = raw_line.trim();
        if line.starts_with("//") || line.starts_with('#') {
            continue;
        }
        let mut current = String::new();
        for ch in line.chars() {
            if ch.is_ascii_alphanumeric() || ch == '_' {
                current.push(ch);
            } else {
                if current.len() >= 3
                    && !current.chars().next().unwrap().is_ascii_digit()
                    && !is_common_noise_ident(&current)
                {
                    refs.insert(std::mem::take(&mut current));
                } else {
                    current.clear();
                }
            }
        }
        if current.len() >= 3
            && !current.chars().next().unwrap().is_ascii_digit()
            && !is_common_noise_ident(&current)
        {
            refs.insert(current);
        }
    }
    refs
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn repo_map_ranks_hub_file_highest_and_respects_token_budget() {
        let temp_dir = std::env::temp_dir().join(format!("mc_repomap_{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(temp_dir.join("src")).unwrap();

        // Hub file defined in `src/core_engine.rs`
        std::fs::write(
            temp_dir.join("src/core_engine.rs"),
            "pub struct CoreEngine {\n    pub id: usize,\n}\npub fn execute_pipeline(engine: &CoreEngine) -> bool {\n    true\n}\n",
        )
        .unwrap();

        // Caller 1 references `CoreEngine` and `execute_pipeline`
        std::fs::write(
            temp_dir.join("src/api_handler.rs"),
            "use crate::core_engine::{CoreEngine, execute_pipeline};\npub fn handle_request() {\n    let eng = CoreEngine { id: 1 };\n    execute_pipeline(&eng);\n}\n",
        )
        .unwrap();

        // Caller 2 also references `CoreEngine` and add a Swift file
        std::fs::write(
            temp_dir.join("src/Bridge.swift"),
            "public struct NativeBridge {\n    public func invokeCore() {\n        let _ = CoreEngine()\n    }\n}\n",
        )
        .unwrap();

        // Unreferenced leaf file
        std::fs::write(
            temp_dir.join("src/leaf_utils.rs"),
            "pub fn isolated_helper() -> usize { 42 }\n",
        )
        .unwrap();

        let mut indexer = Indexer::new();
        let report = indexer.build_repo_map(&temp_dir, 500).unwrap();

        assert_eq!(report.total_files, 4);
        assert!(report.total_symbols >= 5);
        assert!(report.estimated_tokens <= 500);
        // `src/core_engine.rs` should rank #1 because 2 other files reference `CoreEngine`
        assert_eq!(report.entries[0].relative_path, "src/core_engine.rs");
        assert!(report.entries[0].cross_file_refs >= 2);
        assert!(report.formatted.contains("src/core_engine.rs"));
        assert!(report.formatted.contains("execute_pipeline"));

        let _ = std::fs::remove_dir_all(&temp_dir);
    }
}

