import Foundation

// ==========================================
// GitHub Actions Models (unchanged)
// ==========================================

struct WorkflowRun: Codable, Identifiable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let html_url: String
    let created_at: String
    let display_title: String
    let run_number: Int
    
    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion, html_url, created_at, display_title, run_number
    }
}

struct WorkflowRunsResponse: Codable {
    let workflow_runs: [WorkflowRun]
    let total_count: Int
}

struct Step: Codable, Identifiable {
    var id: String { name + String(number) }
    let name: String
    let status: String
    let conclusion: String?
    let number: Int
    
    enum CodingKeys: String, CodingKey {
        case name, status, conclusion, number
    }
}

struct Job: Codable, Identifiable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let html_url: String
    let steps: [Step]?
}

struct JobsResponse: Codable {
    let jobs: [Job]
}

// ==========================================
// Local Pipeline Models
// ==========================================

struct PipelineWorkflowInfo: Codable, Identifiable {
    var id: String { filename }
    let filename: String
    let name: String
    let trigger: String
    let job_count: Int
}

struct PipelineRun: Codable, Identifiable {
    let id: String
    let workflow_file: String
    let workflow_name: String
    let status: String  // "queued", "running", "success", "failed", "cancelled"
    let started_at: String
    let finished_at: String?
    let duration_ms: Int?
    let jobs: [PipelineJobRun]
    let trigger: String
}

struct PipelineJobRun: Codable, Identifiable {
    let id: String
    let name: String
    let status: String
    let started_at: String?
    let finished_at: String?
    let steps: [PipelineStepRun]
}

struct PipelineStepRun: Codable, Identifiable {
    var id: String { name }
    let name: String
    let status: String
    let started_at: String?
    let finished_at: String?
    let exit_code: Int?
    let logs: [String]
}

struct PipelineLogEvent: Codable {
    let run_id: String
    let job_id: String
    let step_name: String
    let line: String
    let timestamp: String
    let type_name: String
    
    enum CodingKeys: String, CodingKey {
        case run_id, job_id, step_name, line, timestamp
        case type_name = "type"
    }
}

// ==========================================
// CI/CD Service
// ==========================================

class CICDService: ObservableObject {
    static let shared = CICDService()
    private let baseURL = "http://127.0.0.1:3000/api"
    
    // MARK: - GitHub Actions API (existing)
    
    func fetchWorkflowRuns(owner: String, repo: String, token: String, completion: @escaping (Result<[WorkflowRun], Error>) -> Void) {
        let url = URL(string: "\(baseURL)/cicd/runs")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "owner": owner,
            "repo": repo,
            "token": token
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else { return }
            
            do {
                let response = try JSONDecoder().decode(WorkflowRunsResponse.self, from: data)
                completion(.success(response.workflow_runs))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func fetchJobs(owner: String, repo: String, token: String, runId: Int, completion: @escaping (Result<[Job], Error>) -> Void) {
        let url = URL(string: "\(baseURL)/cicd/jobs")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "owner": owner,
            "repo": repo,
            "token": token,
            "run_id": runId
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else { return }
            
            do {
                let response = try JSONDecoder().decode(JobsResponse.self, from: data)
                completion(.success(response.jobs))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func triggerWorkflow(owner: String, repo: String, token: String, workflowId: String, ref: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/cicd/trigger")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "owner": owner,
            "repo": repo,
            "token": token,
            "workflow_id": workflowId,
            "ref_name": ref
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                completion(.success(true))
            } else {
                completion(.success(false))
            }
        }.resume()
    }
    
    func getJobLogs(owner: String, repo: String, token: String, jobId: Int, completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/cicd/logs")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "owner": owner,
            "repo": repo,
            "token": token,
            "job_id": jobId
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let logs = json["logs"] as? String {
                    completion(.success(logs))
                } else {
                    completion(.failure(NSError(domain: "CICD", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid format"])))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    // MARK: - Local Pipeline API
    
    func pipelineListWorkflows(projectPath: String, completion: @escaping (Result<[PipelineWorkflowInfo], Error>) -> Void) {
        let url = URL(string: "\(baseURL)/pipeline/list")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["project_path": projectPath])
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { return }
            do {
                let json = try JSONDecoder().decode([String: [PipelineWorkflowInfo]].self, from: data)
                completion(.success(json["workflows"] ?? []))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func pipelineSaveWorkflow(projectPath: String, filename: String, content: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/pipeline/save")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["project_path": projectPath, "filename": filename, "content": content]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            completion(.success(true))
        }.resume()
    }
    
    func pipelineDeleteWorkflow(projectPath: String, filename: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/pipeline/delete")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["project_path": projectPath, "filename": filename]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            completion(.success(true))
        }.resume()
    }
    
    func pipelineGetContent(projectPath: String, filename: String, completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/pipeline/content")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["project_path": projectPath, "filename": filename]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? String {
                completion(.success(content))
            }
        }.resume()
    }
    
    func pipelineTrigger(projectPath: String, workflowFile: String, envOverrides: [String: String] = [:], completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/pipeline/trigger")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["project_path": projectPath, "workflow_file": workflowFile, "env_overrides": envOverrides]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let runId = json["run_id"] as? String {
                completion(.success(runId))
            }
        }.resume()
    }
    
    func pipelineListRuns(projectPath: String, completion: @escaping (Result<[PipelineRun], Error>) -> Void) {
        let url = URL(string: "\(baseURL)/pipeline/runs")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["project_path": projectPath])
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { return }
            do {
                let json = try JSONDecoder().decode([String: [PipelineRun]].self, from: data)
                completion(.success(json["runs"] ?? []))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func pipelineGetRun(runId: String, completion: @escaping (Result<PipelineRun, Error>) -> Void) {
        let url = URL(string: "\(baseURL)/pipeline/run")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["run_id": runId])
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { return }
            do {
                let run = try JSONDecoder().decode(PipelineRun.self, from: data)
                completion(.success(run))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    // MARK: - WebSocket Log Streaming
    
    func connectPipelineLogs(onEvent: @escaping (PipelineLogEvent) -> Void) -> URLSessionWebSocketTask? {
        guard let url = URL(string: "ws://127.0.0.1:3000/ws/pipeline/logs") else { return nil }
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        receiveLogMessage(task: task, onEvent: onEvent)
        return task
    }
    
    private func receiveLogMessage(task: URLSessionWebSocketTask, onEvent: @escaping (PipelineLogEvent) -> Void) {
        task.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let event = try? JSONDecoder().decode(PipelineLogEvent.self, from: data) {
                        DispatchQueue.main.async {
                            onEvent(event)
                        }
                    }
                default:
                    break
                }
                self?.receiveLogMessage(task: task, onEvent: onEvent)
            case .failure:
                break
            }
        }
    }
}

