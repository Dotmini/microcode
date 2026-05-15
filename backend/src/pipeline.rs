// ==========================================
// Pipeline Engine — Local YAML CI/CD Runner
// ==========================================
// GitHub Actions-compatible YAML workflow parser
// with local shell, SSH deploy, and git sync execution.

use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::process::Command;
use tokio::sync::{broadcast, Mutex};
use uuid::Uuid;

// ==========================================
// YAML Workflow Models (GitHub Actions-compatible)
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Workflow {
    pub name: String,
    #[serde(default = "default_trigger")]
    pub on: WorkflowTrigger,
    #[serde(default)]
    pub env: HashMap<String, String>,
    pub jobs: HashMap<String, WorkflowJob>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum WorkflowTrigger {
    Single(String),
    Multiple(Vec<String>),
}

fn default_trigger() -> WorkflowTrigger {
    WorkflowTrigger::Single("manual".to_string())
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkflowJob {
    pub name: Option<String>,
    #[serde(default)]
    pub needs: JobNeeds,
    #[serde(default)]
    pub env: HashMap<String, String>,
    pub steps: Vec<WorkflowStep>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(untagged)]
pub enum JobNeeds {
    #[default]
    None,
    Single(String),
    Multiple(Vec<String>),
}

impl JobNeeds {
    pub fn as_vec(&self) -> Vec<String> {
        match self {
            JobNeeds::None => vec![],
            JobNeeds::Single(s) => vec![s.clone()],
            JobNeeds::Multiple(v) => v.clone(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkflowStep {
    pub name: String,
    #[serde(default)]
    pub run: Option<String>,
    #[serde(default)]
    pub uses: Option<String>,
    #[serde(default, rename = "with")]
    pub with_args: Option<HashMap<String, String>>,
    #[serde(default)]
    pub env: HashMap<String, String>,
}

// ==========================================
// Pipeline Run State
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum RunStatus {
    Queued,
    Running,
    Success,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PipelineRun {
    pub id: String,
    pub workflow_file: String,
    pub workflow_name: String,
    pub status: RunStatus,
    pub started_at: String,
    pub finished_at: Option<String>,
    pub duration_ms: Option<u64>,
    pub jobs: Vec<JobRun>,
    pub trigger: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JobRun {
    pub id: String,
    pub name: String,
    pub status: RunStatus,
    pub started_at: Option<String>,
    pub finished_at: Option<String>,
    pub steps: Vec<StepRun>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StepRun {
    pub name: String,
    pub status: RunStatus,
    pub started_at: Option<String>,
    pub finished_at: Option<String>,
    pub exit_code: Option<i32>,
    pub logs: Vec<String>,
}

// ==========================================
// Log Event for WebSocket streaming
// ==========================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogEvent {
    pub run_id: String,
    pub job_id: String,
    pub step_name: String,
    pub line: String,
    pub timestamp: String,
    #[serde(rename = "type")]
    pub event_type: String, // "stdout", "stderr", "status", "info"
}

// ==========================================
// API Request/Response
// ==========================================

#[derive(Debug, Deserialize)]
pub struct TriggerRequest {
    pub workflow_file: String,
    #[serde(default)]
    pub env_overrides: HashMap<String, String>,
}

#[derive(Debug, Deserialize)]
pub struct SaveWorkflowRequest {
    pub filename: String,
    pub content: String,
}

#[derive(Debug, Deserialize)]
pub struct DeleteWorkflowRequest {
    pub filename: String,
}

#[derive(Debug, Serialize)]
pub struct WorkflowInfo {
    pub filename: String,
    pub name: String,
    pub trigger: String,
    pub job_count: usize,
}

// ==========================================
// Pipeline Engine
// ==========================================

#[derive(Clone)]
pub struct PipelineEngine {
    project_dir: Arc<Mutex<Option<PathBuf>>>,
    runs: Arc<Mutex<Vec<PipelineRun>>>,
    log_tx: broadcast::Sender<LogEvent>,
}

impl std::fmt::Debug for PipelineEngine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("PipelineEngine").finish()
    }
}

impl PipelineEngine {
    pub fn new() -> Self {
        let (log_tx, _) = broadcast::channel(1000);
        Self {
            project_dir: Arc::new(Mutex::new(None)),
            runs: Arc::new(Mutex::new(Vec::new())),
            log_tx,
        }
    }

    pub fn subscribe_logs(&self) -> broadcast::Receiver<LogEvent> {
        self.log_tx.subscribe()
    }

    pub async fn set_project_dir(&self, path: PathBuf) {
        *self.project_dir.lock().await = Some(path);
    }

    fn workflows_dir(project_dir: &Path) -> PathBuf {
        project_dir.join(".microcode").join("workflows")
    }

    // ==========================================
    // Workflow CRUD
    // ==========================================

    pub async fn list_workflows(&self) -> Result<Vec<WorkflowInfo>, String> {
        let project_dir = self.project_dir.lock().await;
        let dir = project_dir.as_ref().ok_or("No project directory set")?;
        let workflows_dir = Self::workflows_dir(dir);

        if !workflows_dir.exists() {
            return Ok(vec![]);
        }

        let mut workflows = Vec::new();
        let entries = std::fs::read_dir(&workflows_dir).map_err(|e| e.to_string())?;

        for entry in entries {
            let entry = entry.map_err(|e| e.to_string())?;
            let path = entry.path();
            if path.extension().and_then(|s| s.to_str()) == Some("yml")
                || path.extension().and_then(|s| s.to_str()) == Some("yaml")
            {
                if let Ok(content) = std::fs::read_to_string(&path) {
                    if let Ok(wf) = serde_yaml::from_str::<Workflow>(&content) {
                        let trigger = match &wf.on {
                            WorkflowTrigger::Single(s) => s.clone(),
                            WorkflowTrigger::Multiple(v) => v.join(", "),
                        };
                        workflows.push(WorkflowInfo {
                            filename: entry.file_name().to_string_lossy().to_string(),
                            name: wf.name,
                            trigger,
                            job_count: wf.jobs.len(),
                        });
                    }
                }
            }
        }

        Ok(workflows)
    }

    pub async fn parse_workflow(&self, filename: &str) -> Result<Workflow, String> {
        let project_dir = self.project_dir.lock().await;
        let dir = project_dir.as_ref().ok_or("No project directory set")?;
        let path = Self::workflows_dir(dir).join(filename);

        let content = std::fs::read_to_string(&path)
            .map_err(|e| format!("Cannot read workflow file: {}", e))?;

        serde_yaml::from_str::<Workflow>(&content).map_err(|e| format!("YAML parse error: {}", e))
    }

    pub async fn save_workflow(&self, filename: &str, content: &str) -> Result<(), String> {
        let project_dir = self.project_dir.lock().await;
        let dir = project_dir.as_ref().ok_or("No project directory set")?;
        let workflows_dir = Self::workflows_dir(dir);

        std::fs::create_dir_all(&workflows_dir).map_err(|e| e.to_string())?;

        // Validate YAML before saving
        serde_yaml::from_str::<Workflow>(content)
            .map_err(|e| format!("Invalid workflow YAML: {}", e))?;

        let path = workflows_dir.join(filename);
        std::fs::write(&path, content).map_err(|e| e.to_string())?;
        Ok(())
    }

    pub async fn delete_workflow(&self, filename: &str) -> Result<(), String> {
        let project_dir = self.project_dir.lock().await;
        let dir = project_dir.as_ref().ok_or("No project directory set")?;
        let path = Self::workflows_dir(dir).join(filename);

        if path.exists() {
            std::fs::remove_file(&path).map_err(|e| e.to_string())?;
        }
        Ok(())
    }

    pub async fn get_workflow_content(&self, filename: &str) -> Result<String, String> {
        let project_dir = self.project_dir.lock().await;
        let dir = project_dir.as_ref().ok_or("No project directory set")?;
        let path = Self::workflows_dir(dir).join(filename);
        std::fs::read_to_string(&path).map_err(|e| e.to_string())
    }

    // ==========================================
    // Run History
    // ==========================================

    pub async fn list_runs(&self) -> Vec<PipelineRun> {
        let runs = self.runs.lock().await;
        runs.iter().rev().take(50).cloned().collect()
    }

    pub async fn get_run(&self, id: &str) -> Option<PipelineRun> {
        let runs = self.runs.lock().await;
        runs.iter().find(|r| r.id == id).cloned()
    }

    // ==========================================
    // Pipeline Execution
    // ==========================================

    pub async fn trigger(
        &self,
        workflow_file: &str,
        env_overrides: HashMap<String, String>,
    ) -> Result<String, String> {
        let workflow = self.parse_workflow(workflow_file).await?;
        let project_dir = {
            let pd = self.project_dir.lock().await;
            pd.clone().ok_or("No project directory set")?
        };

        let run_id = Uuid::new_v4().to_string()[..8].to_string();

        // Resolve job execution order via topological sort
        let job_order = Self::resolve_job_order(&workflow.jobs)?;

        // Initialize run state
        let mut job_runs: Vec<JobRun> = Vec::new();
        for job_key in &job_order {
            let job = &workflow.jobs[job_key];
            let step_runs: Vec<StepRun> = job
                .steps
                .iter()
                .map(|s| StepRun {
                    name: s.name.clone(),
                    status: RunStatus::Queued,
                    started_at: None,
                    finished_at: None,
                    exit_code: None,
                    logs: vec![],
                })
                .collect();

            job_runs.push(JobRun {
                id: format!("{}-{}", run_id, job_key),
                name: job.name.clone().unwrap_or_else(|| job_key.clone()),
                status: RunStatus::Queued,
                started_at: None,
                finished_at: None,
                steps: step_runs,
            });
        }

        let pipeline_run = PipelineRun {
            id: run_id.clone(),
            workflow_file: workflow_file.to_string(),
            workflow_name: workflow.name.clone(),
            status: RunStatus::Running,
            started_at: Utc::now().to_rfc3339(),
            finished_at: None,
            duration_ms: None,
            jobs: job_runs,
            trigger: "manual".to_string(),
        };

        {
            let mut runs = self.runs.lock().await;
            runs.push(pipeline_run);
        }

        // Spawn execution in background
        let engine = self.clone();
        let rid = run_id.clone();
        let wf = workflow.clone();

        tokio::spawn(async move {
            engine
                .execute_pipeline(&rid, &wf, &job_order, &project_dir, env_overrides)
                .await;
        });

        Ok(run_id)
    }

    async fn execute_pipeline(
        &self,
        run_id: &str,
        workflow: &Workflow,
        job_order: &[String],
        project_dir: &Path,
        env_overrides: HashMap<String, String>,
    ) {
        let start = std::time::Instant::now();
        let mut all_success = true;

        // Merge env: workflow.env + overrides
        let mut global_env = workflow.env.clone();
        global_env.extend(env_overrides);

        for (job_idx, job_key) in job_order.iter().enumerate() {
            let job = &workflow.jobs[job_key];
            let job_id = format!("{}-{}", run_id, job_key);

            // Merge job-level env
            let mut job_env = global_env.clone();
            job_env.extend(job.env.clone());

            self.emit_log(
                run_id,
                &job_id,
                &format!("Job: {}", job.name.as_deref().unwrap_or(job_key)),
                &format!("▶ Starting job: {}", job.name.as_deref().unwrap_or(job_key)),
                "info",
            )
            .await;

            self.update_job_status(run_id, job_idx, RunStatus::Running, true)
                .await;

            let mut job_success = true;

            for (step_idx, step) in job.steps.iter().enumerate() {
                // Merge step-level env
                let mut step_env = job_env.clone();
                step_env.extend(step.env.clone());

                self.emit_log(
                    run_id,
                    &job_id,
                    &step.name,
                    &format!("⏳ Step: {}", step.name),
                    "info",
                )
                .await;

                self.update_step_status(run_id, job_idx, step_idx, RunStatus::Running, true)
                    .await;

                let result = self
                    .execute_step(run_id, &job_id, step, project_dir, &step_env)
                    .await;

                match result {
                    Ok(code) => {
                        if code == 0 {
                            self.emit_log(
                                run_id,
                                &job_id,
                                &step.name,
                                &format!("✅ Step '{}' succeeded", step.name),
                                "info",
                            )
                            .await;
                            self.update_step_status(
                                run_id,
                                job_idx,
                                step_idx,
                                RunStatus::Success,
                                false,
                            )
                            .await;
                            self.update_step_exit_code(run_id, job_idx, step_idx, code)
                                .await;
                        } else {
                            self.emit_log(
                                run_id,
                                &job_id,
                                &step.name,
                                &format!("❌ Step '{}' failed (exit code: {})", step.name, code),
                                "info",
                            )
                            .await;
                            self.update_step_status(
                                run_id,
                                job_idx,
                                step_idx,
                                RunStatus::Failed,
                                false,
                            )
                            .await;
                            self.update_step_exit_code(run_id, job_idx, step_idx, code)
                                .await;
                            job_success = false;
                            break;
                        }
                    }
                    Err(e) => {
                        self.emit_log(
                            run_id,
                            &job_id,
                            &step.name,
                            &format!("❌ Step '{}' error: {}", step.name, e),
                            "stderr",
                        )
                        .await;
                        self.update_step_status(
                            run_id,
                            job_idx,
                            step_idx,
                            RunStatus::Failed,
                            false,
                        )
                        .await;
                        job_success = false;
                        break;
                    }
                }
            }

            let job_status = if job_success {
                RunStatus::Success
            } else {
                RunStatus::Failed
            };
            self.update_job_status(run_id, job_idx, job_status, false)
                .await;

            if !job_success {
                all_success = false;
                break;
            }
        }

        let elapsed = start.elapsed().as_millis() as u64;
        let final_status = if all_success {
            RunStatus::Success
        } else {
            RunStatus::Failed
        };

        {
            let mut runs = self.runs.lock().await;
            if let Some(run) = runs.iter_mut().find(|r| r.id == run_id) {
                run.status = final_status.clone();
                run.finished_at = Some(Utc::now().to_rfc3339());
                run.duration_ms = Some(elapsed);
            }
        }

        let status_str = if all_success {
            "✅ Pipeline succeeded"
        } else {
            "❌ Pipeline failed"
        };
        self.emit_log(
            run_id,
            "",
            "pipeline",
            &format!("{} in {:.1}s", status_str, elapsed as f64 / 1000.0),
            "info",
        )
        .await;
    }

    // ==========================================
    // Step Executors
    // ==========================================

    async fn execute_step(
        &self,
        run_id: &str,
        job_id: &str,
        step: &WorkflowStep,
        project_dir: &Path,
        env: &HashMap<String, String>,
    ) -> Result<i32, String> {
        if let Some(ref cmd) = step.run {
            // Local shell command
            let expanded = Self::expand_env(cmd, env);
            self.execute_shell(run_id, job_id, &step.name, &expanded, project_dir, env)
                .await
        } else if let Some(ref action) = step.uses {
            let args = step.with_args.clone().unwrap_or_default();
            let expanded_args: HashMap<String, String> = args
                .iter()
                .map(|(k, v)| (k.clone(), Self::expand_env(v, env)))
                .collect();

            match action.as_str() {
                "ssh-deploy" => {
                    self.execute_ssh_deploy(run_id, job_id, &step.name, &expanded_args, project_dir)
                        .await
                }
                "ssh-run" => {
                    self.execute_ssh_run(run_id, job_id, &step.name, &expanded_args)
                        .await
                }
                "git-sync" => {
                    self.execute_git_sync(run_id, job_id, &step.name, &expanded_args, project_dir)
                        .await
                }
                _ => Err(format!("Unknown action: {}", action)),
            }
        } else {
            Err("Step has no 'run' or 'uses' field".to_string())
        }
    }

    async fn execute_shell(
        &self,
        run_id: &str,
        job_id: &str,
        step_name: &str,
        command: &str,
        cwd: &Path,
        env: &HashMap<String, String>,
    ) -> Result<i32, String> {
        self.emit_log(
            run_id,
            job_id,
            step_name,
            &format!("$ {}", command),
            "stdout",
        )
        .await;

        let mut child = Command::new("sh")
            .arg("-c")
            .arg(command)
            .current_dir(cwd)
            .envs(env)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .map_err(|e| format!("Failed to spawn command: {}", e))?;

        // Stream stdout
        let stdout = child.stdout.take();
        let stderr = child.stderr.take();

        let engine_out = self.clone();
        let rid_out = run_id.to_string();
        let jid_out = job_id.to_string();
        let sn_out = step_name.to_string();

        let stdout_task = tokio::spawn(async move {
            if let Some(stdout) = stdout {
                use tokio::io::{AsyncBufReadExt, BufReader};
                let reader = BufReader::new(stdout);
                let mut lines = reader.lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    engine_out
                        .emit_log(&rid_out, &jid_out, &sn_out, &line, "stdout")
                        .await;
                }
            }
        });

        let engine_err = self.clone();
        let rid_err = run_id.to_string();
        let jid_err = job_id.to_string();
        let sn_err = step_name.to_string();

        let stderr_task = tokio::spawn(async move {
            if let Some(stderr) = stderr {
                use tokio::io::{AsyncBufReadExt, BufReader};
                let reader = BufReader::new(stderr);
                let mut lines = reader.lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    engine_err
                        .emit_log(&rid_err, &jid_err, &sn_err, &line, "stderr")
                        .await;
                }
            }
        });

        let _ = tokio::join!(stdout_task, stderr_task);

        let status = child.wait().await.map_err(|e| e.to_string())?;
        Ok(status.code().unwrap_or(-1))
    }

    async fn execute_ssh_deploy(
        &self,
        run_id: &str,
        job_id: &str,
        step_name: &str,
        args: &HashMap<String, String>,
        project_dir: &Path,
    ) -> Result<i32, String> {
        let host = args.get("host").ok_or("ssh-deploy: missing 'host'")?;
        let user = args.get("user").ok_or("ssh-deploy: missing 'user'")?;
        let source = args.get("source").ok_or("ssh-deploy: missing 'source'")?;
        let target = args.get("target").ok_or("ssh-deploy: missing 'target'")?;
        let key_path = args.get("key_path");
        let port = args
            .get("port")
            .map(|p| p.to_string())
            .unwrap_or_else(|| "22".to_string());

        let source_path = project_dir.join(source);
        let dest = format!("{}@{}:{}", user, host, target);

        let mut rsync_args = vec!["-avz".to_string(), "--delete".to_string(), "-e".to_string()];

        let ssh_cmd = if let Some(key) = key_path {
            let expanded_key = shellexpand::tilde(key).to_string();
            format!(
                "ssh -p {} -i {} -o StrictHostKeyChecking=no",
                port, expanded_key
            )
        } else {
            format!("ssh -p {} -o StrictHostKeyChecking=no", port)
        };

        rsync_args.push(ssh_cmd);
        rsync_args.push(source_path.to_string_lossy().to_string());
        rsync_args.push(dest);

        let cmd = format!("rsync {}", rsync_args.join(" "));
        self.emit_log(
            run_id,
            job_id,
            step_name,
            &format!("🚀 Deploying {} → {}@{}:{}", source, user, host, target),
            "info",
        )
        .await;

        self.execute_shell(
            run_id,
            job_id,
            step_name,
            &cmd,
            project_dir,
            &HashMap::new(),
        )
        .await
    }

    async fn execute_ssh_run(
        &self,
        run_id: &str,
        job_id: &str,
        step_name: &str,
        args: &HashMap<String, String>,
    ) -> Result<i32, String> {
        let host = args.get("host").ok_or("ssh-run: missing 'host'")?;
        let user = args.get("user").ok_or("ssh-run: missing 'user'")?;
        let command = args.get("command").ok_or("ssh-run: missing 'command'")?;
        let key_path = args.get("key_path");
        let port = args
            .get("port")
            .map(|p| p.to_string())
            .unwrap_or_else(|| "22".to_string());

        let mut ssh_args = vec![
            "-o".to_string(),
            "StrictHostKeyChecking=no".to_string(),
            "-p".to_string(),
            port,
        ];

        if let Some(key) = key_path {
            let expanded = shellexpand::tilde(key).to_string();
            ssh_args.push("-i".to_string());
            ssh_args.push(expanded);
        }

        let dest = format!("{}@{}", user, host);
        ssh_args.push(dest.clone());
        ssh_args.push(command.clone());

        let cmd = format!("ssh {}", ssh_args.join(" "));
        self.emit_log(
            run_id,
            job_id,
            step_name,
            &format!("🔌 SSH {}> {}", dest, command),
            "info",
        )
        .await;

        // Use a temp dir for cwd since this is remote
        let tmp = std::env::temp_dir();
        self.execute_shell(run_id, job_id, step_name, &cmd, &tmp, &HashMap::new())
            .await
    }

    async fn execute_git_sync(
        &self,
        run_id: &str,
        job_id: &str,
        step_name: &str,
        args: &HashMap<String, String>,
        project_dir: &Path,
    ) -> Result<i32, String> {
        let branch = args.get("branch").map(|s| s.as_str()).unwrap_or("main");
        let remote = args.get("remote").map(|s| s.as_str()).unwrap_or("origin");

        self.emit_log(
            run_id,
            job_id,
            step_name,
            &format!("🔄 Git sync: {} {}", remote, branch),
            "info",
        )
        .await;

        let cmd = format!("git pull {} {}", remote, branch);
        self.execute_shell(
            run_id,
            job_id,
            step_name,
            &cmd,
            project_dir,
            &HashMap::new(),
        )
        .await
    }

    // ==========================================
    // Helpers
    // ==========================================

    fn expand_env(input: &str, env: &HashMap<String, String>) -> String {
        let mut result = input.to_string();
        // Expand ${{ env.VAR }} syntax
        for (key, value) in env {
            let pattern = format!("${{{{ env.{} }}}}", key);
            result = result.replace(&pattern, value);
            // Also support $VAR and ${VAR}
            result = result.replace(&format!("${{{}}}", key), value);
            result = result.replace(&format!("${}", key), value);
        }
        result
    }

    fn resolve_job_order(jobs: &HashMap<String, WorkflowJob>) -> Result<Vec<String>, String> {
        let mut order: Vec<String> = Vec::new();
        let mut visited: HashMap<String, bool> = HashMap::new();

        fn visit(
            key: &str,
            jobs: &HashMap<String, WorkflowJob>,
            visited: &mut HashMap<String, bool>,
            order: &mut Vec<String>,
        ) -> Result<(), String> {
            if let Some(&in_progress) = visited.get(key) {
                if in_progress {
                    return Err(format!("Circular dependency detected at job: {}", key));
                }
                return Ok(()); // Already visited
            }

            visited.insert(key.to_string(), true);

            if let Some(job) = jobs.get(key) {
                for dep in job.needs.as_vec() {
                    visit(&dep, jobs, visited, order)?;
                }
            }

            visited.insert(key.to_string(), false);
            if !order.contains(&key.to_string()) {
                order.push(key.to_string());
            }
            Ok(())
        }

        for key in jobs.keys() {
            visit(key, jobs, &mut visited, &mut order)?;
        }

        Ok(order)
    }

    async fn emit_log(
        &self,
        run_id: &str,
        job_id: &str,
        step_name: &str,
        line: &str,
        event_type: &str,
    ) {
        let event = LogEvent {
            run_id: run_id.to_string(),
            job_id: job_id.to_string(),
            step_name: step_name.to_string(),
            line: line.to_string(),
            timestamp: Utc::now().to_rfc3339(),
            event_type: event_type.to_string(),
        };

        // Store in run state
        {
            let mut runs = self.runs.lock().await;
            if let Some(run) = runs.iter_mut().find(|r| r.id == run_id) {
                for job in run.jobs.iter_mut() {
                    if job.id == job_id {
                        for step in job.steps.iter_mut() {
                            if step.name == step_name {
                                step.logs.push(line.to_string());
                            }
                        }
                    }
                }
            }
        }

        // Broadcast to WebSocket listeners
        let _ = self.log_tx.send(event);
    }

    async fn update_job_status(
        &self,
        run_id: &str,
        job_idx: usize,
        status: RunStatus,
        is_start: bool,
    ) {
        let mut runs = self.runs.lock().await;
        if let Some(run) = runs.iter_mut().find(|r| r.id == run_id) {
            if let Some(job) = run.jobs.get_mut(job_idx) {
                job.status = status;
                if is_start {
                    job.started_at = Some(Utc::now().to_rfc3339());
                } else {
                    job.finished_at = Some(Utc::now().to_rfc3339());
                }
            }
        }
    }

    async fn update_step_status(
        &self,
        run_id: &str,
        job_idx: usize,
        step_idx: usize,
        status: RunStatus,
        is_start: bool,
    ) {
        let mut runs = self.runs.lock().await;
        if let Some(run) = runs.iter_mut().find(|r| r.id == run_id) {
            if let Some(job) = run.jobs.get_mut(job_idx) {
                if let Some(step) = job.steps.get_mut(step_idx) {
                    step.status = status;
                    if is_start {
                        step.started_at = Some(Utc::now().to_rfc3339());
                    } else {
                        step.finished_at = Some(Utc::now().to_rfc3339());
                    }
                }
            }
        }
    }

    async fn update_step_exit_code(
        &self,
        run_id: &str,
        job_idx: usize,
        step_idx: usize,
        code: i32,
    ) {
        let mut runs = self.runs.lock().await;
        if let Some(run) = runs.iter_mut().find(|r| r.id == run_id) {
            if let Some(job) = run.jobs.get_mut(job_idx) {
                if let Some(step) = job.steps.get_mut(step_idx) {
                    step.exit_code = Some(code);
                }
            }
        }
    }
}

// shellexpand-like tilde expansion
mod shellexpand {
    pub fn tilde(path: &str) -> std::borrow::Cow<str> {
        if path.starts_with("~/") {
            if let Ok(home) = std::env::var("HOME") {
                return std::borrow::Cow::Owned(path.replacen("~", &home, 1));
            }
        }
        std::borrow::Cow::Borrowed(path)
    }
}
