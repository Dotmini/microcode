// AI Agent RAG - Native Vector Search for CodeChunks

use crate::error::{AppError, Result};
use crate::indexer::CodeChunk;
use candle_core::{Device, Tensor};
use candle_transformers::models::bert::{BertModel, Config, DTYPE};
use hf_hub::{api::sync::Api, Repo, RepoType};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use tokenizers::Tokenizer;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VectorIndex {
    pub chunks: Vec<CodeChunk>,
    pub embeddings: Vec<Vec<f32>>,
}

pub struct RagEngine {
    model: BertModel,
    tokenizer: Tokenizer,
    device: Device,
    index: Option<VectorIndex>,
}

impl std::fmt::Debug for RagEngine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RagEngine")
            .field("device", &self.device)
            .field("index", &self.index)
            .finish()
    }
}

impl RagEngine {
    pub fn new() -> Result<Self> {
        let device = if candle_core::utils::metal_is_available() {
            Device::new_metal(0)?
        } else {
            Device::Cpu
        };

        let api = Api::new().map_err(|e| AppError::InternalError(e.to_string()))?;
        let repo = api.repo(Repo::new(
            "sentence-transformers/all-MiniLM-L6-v2".to_string(),
            RepoType::Model,
        ));

        let config_filename = repo
            .get("config.json")
            .map_err(|e| AppError::InternalError(e.to_string()))?;
        let tokenizer_filename = repo
            .get("tokenizer.json")
            .map_err(|e| AppError::InternalError(e.to_string()))?;
        let weights_filename = repo
            .get("model.safetensors")
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        let config: Config = serde_json::from_str(
            &fs::read_to_string(config_filename)
                .map_err(|e| AppError::InternalError(e.to_string()))?,
        )
        .map_err(|e| AppError::InternalError(e.to_string()))?;
        let tokenizer = Tokenizer::from_file(tokenizer_filename)
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        let vb = unsafe {
            candle_nn::VarBuilder::from_mmaped_safetensors(&[weights_filename], DTYPE, &device)
                .map_err(|e| AppError::InternalError(e.to_string()))?
        };
        let model =
            BertModel::load(vb, &config).map_err(|e| AppError::InternalError(e.to_string()))?;

        Ok(Self {
            model,
            tokenizer,
            device,
            index: None,
        })
    }

    pub fn get_embeddings(&self, text: &str) -> Result<Vec<f32>> {
        let tokens = self
            .tokenizer
            .encode(text, true)
            .map_err(|e| AppError::InternalError(e.to_string()))?;
        let token_ids = tokens.get_ids();
        let token_ids = Tensor::new(token_ids, &self.device)?.unsqueeze(0)?;
        let token_type_ids = token_ids.zeros_like()?;

        let embeddings = self
            .model
            .forward(&token_ids, &token_type_ids)
            .map_err(|e| AppError::InternalError(e.to_string()))?;

        // Mean pooling
        let (_n_batch, n_tokens, _hidden_size) = embeddings.dims3()?;
        let embeddings = (embeddings.sum(1)? / (n_tokens as f64))?;
        let embeddings = embeddings.get(0)?;

        // Normalize
        let norm = embeddings.sqr()?.sum_all()?.sqrt()?;
        let embeddings = (embeddings / norm)?;

        Ok(embeddings.to_vec1()?)
    }

    pub fn build_index(&mut self, chunks: Vec<CodeChunk>) -> Result<()> {
        let mut embeddings = Vec::new();
        for chunk in &chunks {
            // Include symbol name/kind in the text for better search
            let text = format!(
                "File: {}\nSymbol: {} ({})\nContent: {}",
                chunk.file_path,
                chunk.symbol_name.as_deref().unwrap_or("none"),
                chunk.symbol_kind,
                chunk.content
            );
            embeddings.push(self.get_embeddings(&text)?);
        }

        self.index = Some(VectorIndex { chunks, embeddings });
        Ok(())
    }

    pub fn search(&self, query: &str, limit: usize) -> Result<Vec<(CodeChunk, f32)>> {
        let index = self
            .index
            .as_ref()
            .ok_or_else(|| AppError::InternalError("Index not built".to_string()))?;
        let query_vec = self.get_embeddings(query)?;

        let mut results = Vec::new();
        for (i, chunk_vec) in index.embeddings.iter().enumerate() {
            let score = self.cosine_similarity(&query_vec, chunk_vec);
            results.push((index.chunks[i].clone(), score));
        }

        results.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        Ok(results.into_iter().take(limit).collect())
    }

    pub fn extract_dependencies(&self, content: &str, file_path: &str) -> Vec<String> {
        let mut deps = Vec::new();
        let extension = Path::new(file_path)
            .extension()
            .and_then(|s| s.to_str())
            .unwrap_or("");

        match extension {
            "rs" => {
                // simple rust use/mod regex
                let re = regex::Regex::new(r"(?:use|mod)\s+([^;{\s:]+)").unwrap();
                for cap in re.captures_iter(content) {
                    deps.push(cap[1].to_string());
                }
            }
            "py" => {
                // python import regex
                let re = regex::Regex::new(r"(?:from|import)\s+([^\s.]+)").unwrap();
                for cap in re.captures_iter(content) {
                    deps.push(cap[1].to_string());
                }
            }
            "swift" => {
                // swift import regex
                let re = regex::Regex::new(r"import\s+([^\s]+)").unwrap();
                for cap in re.captures_iter(content) {
                    deps.push(cap[1].to_string());
                }
            }
            _ => {}
        }
        deps
    }

    pub fn search_with_expansion(
        &self,
        query: &str,
        limit: usize,
    ) -> Result<Vec<(CodeChunk, f32)>> {
        let base_results = self.search(query, limit)?;
        let mut expanded_results = base_results.clone();

        let index = self
            .index
            .as_ref()
            .ok_or_else(|| AppError::InternalError("Index not built".to_string()))?;

        // For each top result, find chunks from dependencies if they mention similar terms
        for (chunk, _score) in base_results.iter().take(2) {
            let deps = self.extract_dependencies(&chunk.content, &chunk.file_path);
            for dep in deps {
                // Find chunks from files that match the dependency name
                for c in &index.chunks {
                    if c.file_path.contains(&dep)
                        && !expanded_results.iter().any(|(r, _)| {
                            r.file_path == c.file_path && r.start_line == c.start_line
                        })
                    {
                        // Add with a lower synthetic score to keep them below direct matches but present in context
                        expanded_results.push((c.clone(), 0.5));
                    }
                }
            }
        }

        Ok(expanded_results)
    }

    fn cosine_similarity(&self, a: &[f32], b: &[f32]) -> f32 {
        let mut dot = 0.0;
        for i in 0..a.len() {
            dot += a[i] * b[i];
        }
        dot
    }

    pub fn save_index(&self, path: &Path) -> Result<()> {
        if let Some(index) = &self.index {
            let data =
                serde_json::to_string(index).map_err(|e| AppError::InternalError(e.to_string()))?;
            fs::write(path, data).map_err(|e| AppError::IOError(e.to_string()))?;
        }
        Ok(())
    }

    pub fn load_index(&mut self, path: &Path) -> Result<()> {
        if path.exists() {
            let data = fs::read_to_string(path).map_err(|e| AppError::IOError(e.to_string()))?;
            let index: VectorIndex =
                serde_json::from_str(&data).map_err(|e| AppError::InternalError(e.to_string()))?;
            self.index = Some(index);
        }
        Ok(())
    }
}
