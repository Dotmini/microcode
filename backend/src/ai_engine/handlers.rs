use super::{CompletionRequest, CompletionResponse};
use crate::state::AppState;
use axum::{extract::State, Json};
use std::sync::Arc;
use tokio::sync::RwLock;

pub async fn handle_completion(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<CompletionRequest>,
) -> Json<Result<CompletionResponse, String>> {
    let start_time = std::time::Instant::now();

    // Access AppState -> fast_tier
    let fast_tier_arc = {
        let st = state.read().await;
        st.fast_tier.clone()
    };

    let mut guard = fast_tier_arc.lock().await;

    if let Some(engine) = guard.as_mut() {
        match engine.complete(&req.context_before) {
            Ok(completion) => {
                let latency = start_time.elapsed().as_millis() as u64;
                Json(Ok(CompletionResponse {
                    completion,
                    latency_ms: latency,
                }))
            }
            Err(e) => Json(Err(e.to_string())),
        }
    } else {
        Json(Err(
            "AI Engine not initialized yet. Downloading model...".to_string()
        ))
    }
}

pub async fn index_workspace(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<super::IndexRequest>,
) -> Json<Result<serde_json::Value, String>> {
    let smart_tier_arc = {
        let st = state.read().await;
        st.smart_tier.clone()
    };

    // Spawn background task for indexing
    tokio::spawn(async move {
        // Initialize if needed
        let mut guard = smart_tier_arc.lock().await;
        if guard.is_none() {
            // Create default DB in .microcode/vectors
            let home = dirs::home_dir().unwrap_or_default();
            let db_path = home.join(".microcode/vectors");
            if let Ok(path_str) = db_path.to_str().ok_or("Invalid path") {
                if let Ok(engine) =
                    crate::ai_engine::smart_tier::SmartTierEngine::new(path_str).await
                {
                    *guard = Some(engine);
                }
            }
        }

        if let Some(engine) = guard.as_ref() {
            let _ = engine.index_workspace(&req.workspace_path).await;
        }
    });

    Json(Ok(serde_json::json!({ "status": "indexing_started" })))
}

pub async fn search_vectors(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<super::SearchRequest>,
) -> Json<Result<super::SearchResponse, String>> {
    let smart_tier_arc = {
        let st = state.read().await;
        st.smart_tier.clone()
    };

    let guard = smart_tier_arc.lock().await;
    if let Some(engine) = guard.as_ref() {
        match engine.search(&req.query, req.limit.unwrap_or(5)).await {
            Ok(results) => {
                let search_results = results
                    .into_iter()
                    .map(|r| super::SearchResult {
                        file_path: "unknown".to_string(), // TODO: Parse logic
                        snippet: r,
                        score: 1.0,
                    })
                    .collect();
                Json(Ok(super::SearchResponse {
                    results: search_results,
                }))
            }
            Err(e) => Json(Err(e.to_string())),
        }
    } else {
        Json(Err(
            "Smart Tier Engine (Vector Store) not initialized. Run indexing first.".to_string(),
        ))
    }
}

#[derive(Debug, serde::Deserialize)]
pub struct EmbeddingRequest {
    pub text: String,
}

#[derive(Debug, serde::Serialize)]
pub struct EmbeddingResponse {
    pub embedding: Vec<f32>,
}

pub async fn get_embedding(
    State(state): State<Arc<RwLock<AppState>>>,
    Json(req): Json<EmbeddingRequest>,
) -> crate::error::Result<Json<EmbeddingResponse>> {
    let rag_engine_ptr = {
        let st = state.read().await;
        st.rag_engine.clone()
    };

    let mut guard = rag_engine_ptr.lock().await;
    if guard.is_none() {
        let engine = crate::rag::RagEngine::new()?;
        *guard = Some(engine);
    }

    let engine = guard.as_ref().unwrap();
    let embedding = engine.get_embeddings(&req.text)?;

    Ok(Json(EmbeddingResponse { embedding }))
}

