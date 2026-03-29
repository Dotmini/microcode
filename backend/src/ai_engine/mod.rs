pub mod fast_tier;
pub mod handlers;
pub mod smart_tier;

use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct CompletionRequest {
    pub context_before: String,
    pub context_after: String,
    pub file_path: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CompletionResponse {
    pub completion: String,
    pub latency_ms: u64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct IndexRequest {
    pub workspace_path: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SearchRequest {
    pub query: String,
    pub limit: Option<usize>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SearchResult {
    pub file_path: String,
    pub snippet: String,
    pub score: f32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SearchResponse {
    pub results: Vec<SearchResult>,
}
