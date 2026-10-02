//! RAG Engine Module - The Memory of MicroCode
//!
//! Provides local-first semantic code search using:
//! - Simple bag-of-words embeddings (MVP)
//! - In-memory vector storage
//!
//! This enables "Chat with Codebase" functionality.

use std::path::{Path, PathBuf};
use std::time::Instant;
use anyhow::{Result, Context};
use walkdir::WalkDir;
use ignore::gitignore::GitignoreBuilder;

use crate::SearchResult;

/// Chunk of code with metadata
#[derive(Debug, Clone)]
struct CodeChunk {
    file_path: String,
    content: String,
    start_line: u32,
    end_line: u32,
    embedding: Vec<f32>,
}

/// RAG Engine for semantic code search
pub struct RagEngine {
    db_path: PathBuf,
    chunks: Vec<CodeChunk>,
}

impl RagEngine {
    /// Create a new RAG engine
    pub fn new(db_path: &str) -> Self {
        Self {
            db_path: PathBuf::from(db_path),
            chunks: Vec::new(),
        }
    }
    
    /// Index a directory for semantic search
    pub async fn index_directory(&mut self, path: &str) -> Result<u32> {
        let start_time = Instant::now();
        let root = PathBuf::from(path);
        
        // Build gitignore matcher
        let gitignore_path = root.join(".gitignore");
        let mut gitignore_builder = GitignoreBuilder::new(&root);
        if gitignore_path.exists() {
            let _ = gitignore_builder.add(&gitignore_path);
        }
        // Always ignore common directories
        let _ = gitignore_builder.add_line(None, "node_modules/");
        let _ = gitignore_builder.add_line(None, ".git/");
        let _ = gitignore_builder.add_line(None, "target/");
        let _ = gitignore_builder.add_line(None, ".build/");
        let _ = gitignore_builder.add_line(None, "*.lock");
        
        let gitignore = gitignore_builder.build().ok();
        
        // Clear existing chunks
        self.chunks.clear();
        
        // Collect and process files
        for entry in WalkDir::new(&root)
            .follow_links(false)
            .into_iter()
            .filter_map(|e| e.ok())
        {
            let file_path = entry.path();
            
            // Skip directories
            if file_path.is_dir() {
                continue;
            }
            
            // Skip if ignored
            if let Some(ref gi) = gitignore {
                if gi.matched(file_path, false).is_ignore() {
                    continue;
                }
            }
            
            // Only index code files
            if !is_code_file(file_path) {
                continue;
            }

            // Enterprise guard: Skip files larger than 2MB to prevent OOM
            if let Ok(meta) = entry.metadata() {
                if meta.len() > 2 * 1024 * 1024 {
                    continue;
                }
            }
            
            let relative_path = file_path.strip_prefix(&root)
                .unwrap_or(file_path)
                .to_string_lossy()
                .to_string();
            
            // Read and chunk file
            if let Ok(content) = std::fs::read_to_string(file_path) {
                let new_chunks = chunk_code(&relative_path, &content);
                self.chunks.extend(new_chunks);

                // Enterprise guard: Limit total in-memory chunks to prevent OOM
                if self.chunks.len() >= 100_000 {
                    println!("Reached maximum indexing capacity (100,000 chunks) for memory stability.");
                    break;
                }
            }
        }
        
        let duration = start_time.elapsed();
        println!("Indexed {} chunks in {:.2}s", self.chunks.len(), duration.as_secs_f64());
        
        Ok(self.chunks.len() as u32)
    }
    
    /// Perform semantic search
    pub async fn search(&self, query: &str, limit: usize) -> Result<Vec<SearchResult>> {
        if self.chunks.is_empty() {
            return Ok(Vec::new());
        }
        
        // Generate query embedding
        let query_emb = text_to_embedding(query);
        
        // Calculate similarities
        let mut scores: Vec<(usize, f32)> = self.chunks
            .iter()
            .enumerate()
            .map(|(i, chunk)| (i, cosine_similarity(&query_emb, &chunk.embedding)))
            .collect();
        
        // Sort by score descending
        scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        
        // Take top results
        let results: Vec<SearchResult> = scores
            .into_iter()
            .take(limit)
            .filter(|(_, score)| *score > 0.1) // Minimum threshold
            .map(|(idx, score)| {
                let chunk = &self.chunks[idx];
                SearchResult {
                    file_path: chunk.file_path.clone(),
                    content: chunk.content.clone(),
                    score,
                    start_line: chunk.start_line,
                    end_line: chunk.end_line,
                }
            })
            .collect();
        
        Ok(results)
    }
    
    /// Clear the index
    pub async fn clear(&mut self) -> Result<()> {
        self.chunks.clear();
        Ok(())
    }
    
    /// Get statistics
    pub async fn stats(&self) -> Result<String> {
        Ok(format!(
            "{{\"total_chunks\": {}, \"db_path\": \"{}\"}}",
            self.chunks.len(),
            self.db_path.display()
        ))
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Check if a file is a code file worth indexing
fn is_code_file(path: &Path) -> bool {
    let extensions = [
        "rs", "py", "js", "ts", "jsx", "tsx", "swift", "kt", "java",
        "go", "c", "cpp", "h", "hpp", "m", "mm", "rb", "php", "lua",
        "sql", "sh", "bash", "zsh", "toml", "yaml", "yml", "json",
        "md", "txt", "html", "css", "scss", "less",
    ];
    
    path.extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| extensions.contains(&ext.to_lowercase().as_str()))
        .unwrap_or(false)
}

/// Chunk code into smaller pieces for embedding
fn chunk_code(file_path: &str, content: &str) -> Vec<CodeChunk> {
    const CHUNK_SIZE: usize = 50; // Lines per chunk
    const OVERLAP: usize = 10;    // Overlapping lines
    
    let lines: Vec<&str> = content.lines().collect();
    let mut chunks = Vec::new();
    
    if lines.is_empty() {
        return chunks;
    }
    
    let mut start = 0;
    while start < lines.len() {
        let end = (start + CHUNK_SIZE).min(lines.len());
        let chunk_content = lines[start..end].join("\n");
        let embedding = text_to_embedding(&chunk_content);
        
        chunks.push(CodeChunk {
            file_path: file_path.to_string(),
            content: chunk_content,
            start_line: (start + 1) as u32,
            end_line: end as u32,
            embedding,
        });
        
        start += CHUNK_SIZE - OVERLAP;
        if start + OVERLAP >= lines.len() {
            break;
        }
    }
    
    chunks
}

/// Convert text to embedding vector (MVP: simple hash-based)
fn text_to_embedding(text: &str) -> Vec<f32> {
    const DIM: usize = 128;
    let mut embedding = vec![0.0f32; DIM];
    
    // Simple word-based embedding
    for word in text.split_whitespace() {
        let word_lower = word.to_lowercase();
        let hash = simple_hash(&word_lower);
        let idx = (hash as usize) % DIM;
        embedding[idx] += 1.0;
    }
    
    // Normalize
    let norm: f32 = embedding.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm > 0.0 {
        for x in &mut embedding {
            *x /= norm;
        }
    }
    
    embedding
}

/// Simple string hash
fn simple_hash(s: &str) -> u64 {
    let mut hash: u64 = 5381;
    for c in s.chars() {
        hash = hash.wrapping_mul(33).wrapping_add(c as u64);
    }
    hash
}

/// Cosine similarity between two vectors
fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
    if a.len() != b.len() {
        return 0.0;
    }
    
    let dot: f32 = a.iter().zip(b.iter()).map(|(x, y)| x * y).sum();
    let norm_a: f32 = a.iter().map(|x| x * x).sum::<f32>().sqrt();
    let norm_b: f32 = b.iter().map(|x| x * x).sum::<f32>().sqrt();
    
    if norm_a > 0.0 && norm_b > 0.0 {
        dot / (norm_a * norm_b)
    } else {
        0.0
    }
}
