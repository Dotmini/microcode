// use sse_codec::Sender; // Removed unused import
use crate::error::{AppError, Result};
use reqwest::header::{HeaderMap, HeaderValue, AUTHORIZATION, USER_AGENT, ACCEPT};
use serde::{Deserialize, Serialize};

// ==========================================
// Data Models
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkflowRun {
    pub id: u64,
    pub name: String,
    pub status: String,     // "queued", "in_progress", "completed"
    pub conclusion: Option<String>, // "success", "failure", "cancelled", etc.
    pub html_url: String,
    pub created_at: String,
    pub updated_at: String,
    pub display_title: String,
    pub run_number: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkflowRunsResponse {
    pub total_count: u64,
    pub workflow_runs: Vec<WorkflowRun>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Job {
    pub id: u64,
    pub run_id: u64,
    pub name: String,
    pub status: String,
    pub conclusion: Option<String>,
    pub started_at: String,
    pub completed_at: Option<String>,
    pub html_url: String,
    pub steps: Vec<Step>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Step {
    pub name: String,
    pub status: String,
    pub conclusion: Option<String>,
    pub number: u64,
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JobsResponse {
    pub total_count: u64,
    pub jobs: Vec<Job>,
}

// ==========================================
// Request/Response Structs
// ==========================================

#[derive(Debug, Deserialize)]
pub struct CICDBaseRequest {
    pub owner: String,
    pub repo: String,
    pub token: String,
}

#[derive(Debug, Deserialize)]
pub struct TriggerWorkflowRequest {
    pub owner: String,
    pub repo: String,
    pub token: String,
    pub workflow_id: String, // ID or filename (e.g. "main.yml")
    pub ref_name: String,    // branch or tag
}

#[derive(Debug, Deserialize)]
pub struct GetLogsRequest {
    pub owner: String,
    pub repo: String,
    pub token: String,
    pub job_id: u64,
}

// ==========================================
// GitHub Client
// ==========================================

pub struct GitHubClient {
    client: reqwest::Client,
    base_url: String,
}

impl GitHubClient {
    pub fn new() -> Self {
        Self {
            client: reqwest::Client::new(),
            base_url: "https://api.github.com".to_string(),
        }
    }

    fn headers(&self, token: &str) -> HeaderMap {
        let mut headers = HeaderMap::new();
        headers.insert(USER_AGENT, HeaderValue::from_static("MicroCode-Backend"));
        headers.insert(ACCEPT, HeaderValue::from_static("application/vnd.github.v3+json"));
        if let Ok(auth_val) = HeaderValue::from_str(&format!("Bearer {}", token)) {
            headers.insert(AUTHORIZATION, auth_val);
        }
        headers
    }

    pub async fn list_runs(&self, owner: &str, repo: &str, token: &str, limit: u32) -> Result<WorkflowRunsResponse> {
        let url = format!("{}/repos/{}/{}/actions/runs?per_page={}", self.base_url, owner, repo, limit);
        
        let response = self.client.get(&url)
            .headers(self.headers(token))
            .send()
            .await?;  // relying on From<reqwest::Error> for AppError

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::InternalError(format!("GitHub API Error: {}", error_text)));
        }

        let runs: WorkflowRunsResponse = response.json()
            .await?; // relying on From<reqwest::Error> for AppError (decoding error is also reqwest error or json?)
                     // Actually reqwest::Response::json returns reqwest::Error on failure.

        Ok(runs)
    }

    pub async fn list_jobs(&self, owner: &str, repo: &str, token: &str, run_id: u64) -> Result<JobsResponse> {
        let url = format!("{}/repos/{}/{}/actions/runs/{}/jobs", self.base_url, owner, repo, run_id);
        
        let response = self.client.get(&url)
            .headers(self.headers(token))
            .send()
            .await?;

        if !response.status().is_success() {
            return Err(AppError::InternalError(format!("GitHub API Error: {}", response.status())));
        }

        let jobs: JobsResponse = response.json()
            .await?;

        Ok(jobs)
    }

    pub async fn trigger_workflow(&self, req: &TriggerWorkflowRequest) -> Result<()> {
        let url = format!("{}/repos/{}/{}/actions/workflows/{}/dispatches", self.base_url, req.owner, req.repo, req.workflow_id);
        
        let body = serde_json::json!({
            "ref": req.ref_name
        });

        let response = self.client.post(&url)
            .headers(self.headers(&req.token))
            .json(&body)
            .send()
            .await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::InternalError(format!("Failed to trigger workflow: {}", error_text)));
        }

        Ok(())
    }
    
    pub async fn get_job_logs(&self, owner: &str, repo: &str, token: &str, job_id: u64) -> Result<String> {
         let url = format!("{}/repos/{}/{}/actions/jobs/{}/logs", self.base_url, owner, repo, job_id);
        
        let response = self.client.get(&url)
            .headers(self.headers(token))
            .send()
            .await?;
            
        // Note: This endpoint might redirect to a signed S3 URL. reqwest follows redirects by default.
        if !response.status().is_success() {
             return Err(AppError::InternalError(format!("Failed to get logs: {}", response.status())));
        }
        
        let logs = response.text()
            .await?;
            
        Ok(logs)
    }
}
