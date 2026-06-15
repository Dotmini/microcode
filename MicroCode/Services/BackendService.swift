//
//  BackendService.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2024 AIPRENEUR. All rights reserved.
//

import Combine
import Foundation

class BackendService {
    static let shared = BackendService()

    private let baseURL = "http://127.0.0.1:3000"
    private var backendProcess: Process?
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // Extended for long AI tasks
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Backend Process Management

    func startBackend() async throws {
        print("📍 BackendService.startBackend() called")
        
        // Locate backend binary in App Bundle (Contents/MacOS/microcode-backend)
        guard let mainExecutable = Bundle.main.executableURL else { 
            print("❌ Could not get main executable URL")
            throw BackendError.invalidResponse
        }
        let backendURL = mainExecutable.deletingLastPathComponent().appendingPathComponent("microcode-backend")
        
        print("📂 Looking for backend at: \(backendURL.path)")
        
        guard FileManager.default.fileExists(atPath: backendURL.path) else {
            print("⚠️ Backend binary not found at \(backendURL.path).")
            print("   Checking if backend is already running...")
            // Backend might be running manually - try health check
            try? await healthCheck()
            print("   Backend appears to be running externally")
            return
        }
        
        // Reap any backend left spinning by a previous crash / force-quit
        // (re-parented to launchd) before we bind port 3000 again.
        killStaleBackends()

        print("🚀 Launching backend from bundle: \(backendURL.path)")

        let process = Process()
        process.executableURL = backendURL
        process.arguments = []
        var env = ProcessInfo.processInfo.environment
        env["RUST_LOG"] = "info"
        // Hand the backend our PID so it can self-exit if we die (the Rust
        // side also watches for re-parenting to launchd as a backstop).
        env["MICROCODE_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        
        // Fix: Ensure HOME and PATH are set correctly for the backend to find runtimes (rustc, node, etc.)
        // When running as an App Bundle, PATH might be stripped.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["HOME"] = home
        
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let extraPaths = [
            "\(home)/.cargo/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.nvm/versions/node/v22.0.0/bin", // Common Node path
            "\(home)/.nvm/versions/node/v20.0.0/bin",
            "\(home)/.nvm/versions/node/v18.0.0/bin"
        ]
        let newPath = extraPaths.joined(separator: ":") + ":" + currentPath
        env["PATH"] = newPath
        
        process.environment = env
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            self.backendProcess = process
            print("✅ Backend process started (PID: \(process.processIdentifier))")
            
            // Log output
            Task.detached {
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    print("[Backend] \(line)")
                }
            }
            
            // Wait and health check
            print("⏳ Waiting for backend to be ready...")
            
            // Fast polling: check every 50ms up to 2 seconds
            var isReady = false
            for i in 0..<40 {
                if (try? await self.healthCheck()) != nil {
                    isReady = true
                    print("⚡ Backend became ready in \((i + 1) * 50)ms")
                    break
                }
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
            
            if !isReady {
                // Final check if loop finishes without success
                try await self.healthCheck()
            }
            
            print("✅ Backend started successfully on port 3000")
        } catch {
            print("❌ Failed to start backend: \(error.localizedDescription)")
            throw error
        }
    }

    func stopBackend() {
        guard let p = backendProcess else { return }
        backendProcess = nil
        guard p.isRunning else { return }
        p.terminate() // SIGTERM — let it flush/clean up first
        // Then hard-kill so it can NEVER linger as a CPU-spinning orphan.
        let deadline = Date().addingTimeInterval(2)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
    }

    /// Kill backends a previous run leaked. After a crash / force-quit /
    /// SIGKILL of the app, our child backend is re-parented to launchd (PID 1)
    /// and keeps running — pegging a CPU core and holding port 3000 so the
    /// next launch can't bind. Reap by exact binary name and by :3000 owner.
    private func killStaleBackends() {
        for name in ["microcode-backend", "codetunner-backend"] {
            let pk = Process()
            pk.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            pk.arguments = ["-9", "-x", name]
            pk.standardOutput = FileHandle.nullDevice
            pk.standardError = FileHandle.nullDevice
            try? pk.run(); pk.waitUntilExit()
        }
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-c", "pids=$(lsof -ti tcp:3000); [ -n \"$pids\" ] && kill -9 $pids"]
        sh.standardOutput = FileHandle.nullDevice
        sh.standardError = FileHandle.nullDevice
        try? sh.run(); sh.waitUntilExit()
    }

    // MARK: - Health Check

    func healthCheck() async throws -> [String: Any] {
        let url = URL(string: "\(baseURL)/health")!
        let (data, _) = try await session.data(from: url)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    // MARK: - File Operations

    func listFiles(path: String, recursive: Bool = false) async throws -> [FileInfo] {
        let url = URL(string: "\(baseURL)/api/files/list")!
        let request = ListFilesRequest(path: path, recursive: recursive, includeHidden: false)
        let response: ListFilesResponse = try await post(url: url, body: request)
        return response.files
    }

    func readFile(path: String) async throws -> String {
        let url = URL(string: "\(baseURL)/api/files/read")!
        let request = ReadFileRequest(path: path)
        let response: ReadFileResponse = try await post(url: url, body: request)
        return response.content
    }

    func writeFile(path: String, content: String) async throws {
        let url = URL(string: "\(baseURL)/api/files/write")!
        let request = WriteFileRequest(path: path, content: content, createDirs: true)
        let _: StatusResponse = try await post(url: url, body: request)
    }

    func deleteFile(path: String) async throws {
        let url = URL(string: "\(baseURL)/api/files/delete")!
        let request = DeleteFileRequest(path: path)
        let _: StatusResponse = try await post(url: url, body: request)
    }

    // MARK: - Code Operations

    func analyzeCode(code: String, language: String) async throws -> CodeAnalysis {
        let url = URL(string: "\(baseURL)/api/code/analyze")!
        let request = AnalyzeCodeRequest(code: code, language: language)
        let response: AnalyzeCodeResponse = try await post(url: url, body: request)
        return response.analysis
    }

    func formatCode(code: String, language: String) async throws -> String {
        let url = URL(string: "\(baseURL)/api/code/format")!
        let request = FormatCodeRequest(code: code, language: language, options: [:])
        let response: FormatCodeResponse = try await post(url: url, body: request)
        return response.code
    }
    
    func formatCodeAI(code: String, language: String, instructions: String) async throws -> String {
        let url = URL(string: "\(baseURL)/api/ai/format")!
        let request = AIFormatRequest(code: code, language: language, instructions: instructions)
        let response: FormatCodeResponse = try await post(url: url, body: request)
        return response.code
    }

    func highlightCode(code: String, language: String) async throws -> [HighlightToken] {
        let url = URL(string: "\(baseURL)/api/code/highlight")!
        let request = HighlightCodeRequest(code: code, language: language, theme: "default")
        let response: HighlightCodeResponse = try await post(url: url, body: request)
        return response.tokens
    }

    // MARK: - AI Operations

    func refactorCode(code: String, instructions: String, provider: String, model: String, apiKey: String)
        async throws -> String
    {
        let url = URL(string: "\(baseURL)/api/ai/refactor")!
        let request = AIRefactorRequest(code: code, instructions: instructions, language: "", provider: provider, model: model, api_key: apiKey)
        let response: AIRefactorResponse = try await post(url: url, body: request)
        return response.code
    }

    func refactorCodeStream(code: String, instructions: String, provider: String, model: String, apiKey: String) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = URL(string: "\(baseURL)/api/ai/refactor/stream")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    
                    let payload = AIRefactorRequest(code: code, instructions: instructions, language: "", provider: provider, model: model, api_key: apiKey)
                    request.httpBody = try JSONEncoder().encode(payload)
                    
                    let (bytes, response) = try await session.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: BackendError.invalidResponse)
                        return
                    }
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let content = String(line.dropFirst(6))
                            continuation.yield(content)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    func refactorCodeUltra(files: [FileContent], instructions: String, targetLanguage: String?, provider: String?, model: String?, apiKey: String?) async throws -> AIRefactorUltraResponse {
        let url = URL(string: "\(baseURL)/api/ai/refactor/ultra")!
        let request = AIRefactorUltraRequest(files: files, instructions: instructions, target_language: targetLanguage, provider: provider, model: model, api_key: apiKey)
        return try await post(url: url, body: request)
    }

    func generateRefactorReport(request: AIRefactorReportRequest) async throws -> Data {
        let url = URL(string: "\(baseURL)/api/ai/refactor/report")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BackendError.invalidResponse
        }
        return data
    }

    func explainCode(code: String, provider: String, model: String, apiKey: String) async throws -> String {
        let url = URL(string: "\(baseURL)/api/ai/explain")!
        let request = AIExplainRequest(code: code, language: "", provider: provider, model: model, api_key: apiKey)
        let response: AIExplainResponse = try await post(url: url, body: request)
        return response.explanation
    }

    func completeCode(code: String, context: String, provider: String, model: String, apiKey: String) async throws
        -> String
    {
        let url = URL(string: "\(baseURL)/api/ai/complete")!
        let request = AICompleteRequest(code: code, context: context, language: "", provider: provider, model: model, api_key: apiKey)
        let response: AICompleteResponse = try await post(url: url, body: request)
        return response.completion
    }

    func transpileCode(code: String, targetLanguage: String, instructions: String, provider: String? = nil, model: String? = nil, apiKey: String? = nil) async throws -> String {
        let url = URL(string: "\(baseURL)/api/ai/transpile")!
        let request = AITranspileRequest(code: code, target_language: targetLanguage, instructions: instructions, provider: provider, model: model, api_key: apiKey)
        let response: AITranspileResponse = try await post(url: url, body: request)
        return response.code
    }

    func listAIModels() async throws -> [AIModel] {
        let url = URL(string: "\(baseURL)/api/ai/models")!
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(AIModelsResponse.self, from: data)
        return response.models
    }

    func agentEnhancedChat(request: AgentChatRequest) async throws -> AgentChatResponse {
        let url = URL(string: "\(baseURL)/api/agent/enhanced-chat")!
        return try await post(url: url, body: request)
    }

    func agentEnhancedChatStream(request: AgentChatRequest) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = URL(string: "\(baseURL)/api/agent/enhanced-chat/stream")!
                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    
                    urlRequest.httpBody = try JSONEncoder().encode(request)
                    
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: BackendError.invalidResponse)
                        return
                    }
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if let data = jsonString.data(using: .utf8) {
                                do {
                                    let event = try JSONDecoder().decode(AgentStreamEvent.self, from: data)
                                    continuation.yield(event)
                                } catch {
                                    print("❌ Agent Stream Decoding Error: \(error)")
                                    print("   Raw JSON: \(jsonString)")
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    func startIndexing(path: String) async throws -> StatusResponse {
        let url = URL(string: "\(baseURL)/api/agent/index/start")!
        let request = ["path": path]
        return try await post(url: url, body: request)
    }

    // MARK: - Git Operations

    func getGitStatus(repoPath: String) async throws -> GitStatus {
        let url = URL(string: "\(baseURL)/api/git/status")!
        let request = GitStatusRequest(repoPath: repoPath)
        let response: GitStatusResponse = try await post(url: url, body: request)
        return response.status
    }

    func gitCommit(repoPath: String, message: String) async throws {
        let url = URL(string: "\(baseURL)/api/git/commit")!
        let request = GitCommitRequest(repoPath: repoPath, message: message, files: [])
        let _: StatusResponse = try await post(url: url, body: request)
    }

    func gitPush(repoPath: String) async throws {
        let url = URL(string: "\(baseURL)/api/git/push")!
        let request = GitPushRequest(repoPath: repoPath, remote: "origin", branch: "")
        let _: StatusResponse = try await post(url: url, body: request)
    }

    func gitPull(repoPath: String) async throws {
        let url = URL(string: "\(baseURL)/api/git/pull")!
        let request = GitPullRequest(repoPath: repoPath, remote: "origin", branch: "")
        let _: StatusResponse = try await post(url: url, body: request)
    }

    func getGitLog(repoPath: String, limit: Int) async throws -> [GitCommit] {
        let url = URL(string: "\(baseURL)/api/git/log")!
        let request = GitLogRequest(repoPath: repoPath, limit: limit)
        let response: GitLogResponse = try await post(url: url, body: request)
        return response.commits
    }

    func getGitDiff(repoPath: String) async throws -> String {
        let url = URL(string: "\(baseURL)/api/git/diff")!
        let request = GitDiffRequest(repoPath: repoPath, filePath: nil)
        let response: GitDiffResponse = try await post(url: url, body: request)
        return response.diff
    }

    // MARK: - Code Execution

    func executeCode(code: String, language: String) async throws -> ExecutionOutput {
        let url = URL(string: "\(baseURL)/api/run/execute")!
        let request = ExecuteCodeRequest(code: code, language: language, args: [], env: [:])
        let response: ExecuteCodeResponse = try await post(url: url, body: request)
        return response.output
    }
    
    func streamExecuteCode(code: String, language: String) -> AsyncThrowingStream<StreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = URL(string: "\(baseURL)/api/run/stream")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 300
                    
                    let payload = ExecuteCodeRequest(code: code, language: language, args: [], env: [:])
                    request.httpBody = try JSONEncoder().encode(payload)
                    
                    let (bytes, response) = try await session.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: BackendError.invalidResponse)
                        return
                    }
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                             let jsonString = String(line.dropFirst(6))
                             if let data = jsonString.data(using: .utf8) {
                                 do {
                                     let event = try JSONDecoder().decode(StreamEvent.self, from: data)
                                     continuation.yield(event)
                                 } catch {
                                     print("❌ Stream Decoding Error: \(error)")
                                     print("   Raw JSON: \(jsonString)")
                                 }
                             }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    enum ConnectionType: String, Codable, CaseIterable {
        case ssh = "ssh"
        case sftp = "sftp"
        case ftp = "ftp"
        case ftps = "ftps"
        
        var displayName: String {
            switch self {
            case .ssh: return "SSH"
            case .sftp: return "SFTP"
            case .ftp: return "FTP"
            case .ftps: return "FTPS"
            }
        }
        
        var icon: String {
            switch self {
            case .ssh: return "terminal.fill"
            case .sftp: return "externaldrive.connected.to.line.below.fill"
            case .ftp: return "folder.badge.gearshape"
            case .ftps: return "lock.icloud.fill"
            }
        }
        
        var defaultPort: UInt16 {
            switch self {
            case .ssh, .sftp: return 22
            case .ftp, .ftps: return 21
            }
        }
    }

    func stopExecution(executionId: String) async throws {
        let url = URL(string: "\(baseURL)/api/run/stop")!
        let request = StopExecutionRequest(executionId: executionId)
        let _: StatusResponse = try await post(url: url, body: request)
    }
    // MARK: - Remote X Operations

    func connectRemote(config: RemoteConnectionConfig) async throws -> StatusResponse {
        let url = URL(string: "\(baseURL)/api/remote/connect")!
        let request = RemoteConnectRequest(
            id: config.id.uuidString,
            host: config.host,
            port: config.port,
            username: config.username,
            auth_type: config.authType.rawValue,
            password: config.password,
            key_path: config.keyPath,
            connection_type: config.connectionType.rawValue
        )
        return try await post(url: url, body: request)
    }
    
    func pingRemote(host: String, port: UInt16) async throws -> Bool {
        let url = URL(string: "\(baseURL)/api/remote/ping")!
        let request = PingRequest(host: host, port: port)
        let response: StatusResponse = try await post(url: url, body: request)
        return response.success
    }

    func executeRemoteCommand(id: String, command: String) async throws -> String {
        let url = URL(string: "\(baseURL)/api/remote/exec")!
        let request = RemoteExecRequest(id: id, command: command)
        let response: RemoteExecResponse = try await post(url: url, body: request)
        return response.output
    }

    func listRemoteFiles(id: String, path: String) async throws -> [FileInfo] {
        let url = URL(string: "\(baseURL)/api/remote/files")!
        let request = RemoteListFilesRequest(id: id, path: path)
        let response: ListFilesResponse = try await post(url: url, body: request)
        return response.files
    }

    func uploadRemoteFile(id: String, path: String, content: Data) async throws {
        let url = URL(string: "\(baseURL)/api/remote/upload")!
        let base64 = content.base64EncodedString()
        let request = RemoteUploadRequest(id: id, path: path, content_base64: base64)
        let _: StatusResponse = try await post(url: url, body: request)
    }

    func downloadRemoteFile(id: String, path: String) async throws -> Data {
        let url = URL(string: "\(baseURL)/api/remote/download")!
        let request = RemoteDownloadRequest(id: id, path: path)
        let response: RemoteDownloadResponse = try await post(url: url, body: request)
        
        guard let data = Data(base64Encoded: response.content) else {
            throw BackendError.invalidResponse
        }
        return data
    }
    
    func remoteMkdir(id: String, path: String) async throws {
        let url = URL(string: "\(baseURL)/api/remote/mkdir")!
        let request = RemoteMkdirRequest(id: id, path: path)
        let _: StatusResponse = try await post(url: url, body: request)
    }
    
    func remoteRemove(id: String, path: String, isDirectory: Bool) async throws {
        let url = URL(string: "\(baseURL)/api/remote/remove")!
        let request = RemoteRemoveRequest(id: id, path: path, is_directory: isDirectory)
        let _: StatusResponse = try await post(url: url, body: request)
    }
    
    func remoteRename(id: String, source: String, destination: String) async throws {
        let url = URL(string: "\(baseURL)/api/remote/rename")!
        let request = RemoteRenameRequest(id: id, source: source, destination: destination)
        let _: StatusResponse = try await post(url: url, body: request)
    }
    
    func remoteShellWebSocketURL(id: String) -> URL? {
        return URL(string: "\(baseURL)/api/remote/shell/\(id)")!
            .replacingScheme(from: "http", to: "ws")!
            .replacingScheme(from: "https", to: "wss")!
    }

    // MARK: - Node.js Operations

    func listNodeVersions() async throws -> [NodeVersion] {
        let url = URL(string: "\(baseURL)/api/node/versions")!
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(ListNodeVersionsResponse.self, from: data)
        return response.versions
    }

    func selectNodeVersion(_ version: String) async throws {
        let url = URL(string: "\(baseURL)/api/node/select")!
        let request = SelectNodeVersionRequest(version: version)
        let _: StatusResponse = try await post(url: url, body: request)
    }

    // MARK: - Cache Operations

    func getDerivedDataInfo() async throws -> DerivedDataInfo {
        let url = URL(string: "\(baseURL)/api/cache/derived_data")!
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorData = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw BackendError.serverError(errorData.error)
            }
            throw BackendError.httpError(httpResponse.statusCode)
        }
        
        let res = try JSONDecoder().decode(DerivedDataResponse.self, from: data)
        if res.success, let info = res.info {
            return info
        } else {
            throw BackendError.serverError(res.error ?? "Failed to fetch derived data info")
        }
    }

    func clearDerivedData(projectPattern: String? = nil) async throws -> DerivedDataInfo {
        let url = URL(string: "\(baseURL)/api/cache/derived_data/clear")!
        let request = ClearDerivedDataRequest(project_pattern: projectPattern)
        let res: DerivedDataResponse = try await post(url: url, body: request)
        if res.success, let info = res.info {
            return info
        } else {
            throw BackendError.serverError(res.error ?? "Failed to clear derived data")
        }
    }

    // MARK: - HTTP Helpers

    private func post<T: Encodable, R: Decodable>(url: URL, body: T) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorData = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                 // Try to parse as simple string error if complex fails, or just wrap
                throw BackendError.serverError(errorData.error)
            }
             // Fallback for plain text error
            if let textError = String(data: data, encoding: .utf8) {
                throw BackendError.serverError(textError)
            }
            throw BackendError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(R.self, from: data)
    }
    // MARK: - Vector Search
    
    func indexWorkspace(path: String) async throws -> StatusResponse {
        let url = URL(string: "\(baseURL)/api/ai/vector/index")!
        let request = VectorIndexRequest(workspace_path: path)
        return try await post(url: url, body: request)
    }
    
    func searchVectors(query: String, limit: Int = 5) async throws -> SearchResponse {
        let url = URL(string: "\(baseURL)/api/ai/vector/search")!
        let request = SearchRequest(query: query, limit: limit)
        return try await post(url: url, body: request)
    }
}

// MARK: - Vector Search Models

struct VectorIndexRequest: Codable {
    let workspace_path: String
}

struct SearchRequest: Codable {
    let query: String
    let limit: Int?
}

struct BackendSearchResult: Codable {
    let file_path: String
    let snippet: String
    let score: Float
}

struct SearchResponse: Codable {
    let results: [BackendSearchResult]
}

// MARK: - Remote X Models

struct PingRequest: Codable {
    let host: String
    let port: UInt16
}

struct RemoteConnectRequest: Codable {
    let id: String
    let host: String
    let port: UInt16
    let username: String
    let auth_type: String
    let password: String
    let key_path: String
    let connection_type: String
}

struct RemoteExecRequest: Codable {
    let id: String
    let command: String
}

struct RemoteExecResponse: Codable {
    let output: String
}

struct RemoteListFilesRequest: Codable {
    let id: String
    let path: String
}

struct RemoteUploadRequest: Codable {
    let id: String
    let path: String
    let content_base64: String
}

struct RemoteDownloadRequest: Codable {
    let id: String
    let path: String
}

struct RemoteDownloadResponse: Codable {
    let content: String // base64
}

struct RemoteMkdirRequest: Codable {
    let id: String
    let path: String
}

struct RemoteRemoveRequest: Codable {
    let id: String
    let path: String
    let is_directory: Bool
}

struct RemoteRenameRequest: Codable {
    let id: String
    let source: String
    let destination: String
}

// MARK: - Node.js Models

struct NodeVersion: Codable, Identifiable, Hashable {
    var id: String { version }
    let version: String
    let path: String
    let source: String
    let is_current: Bool
}

struct ListNodeVersionsResponse: Codable {
    let versions: [NodeVersion]
}

struct SelectNodeVersionRequest: Codable {
    let version: String
}

// MARK: - Request/Response Models

struct DerivedDataInfo: Codable {
    let path: String
    let size_bytes: UInt64
    let folder_count: Int
    let files_cleaned: Int?
}

struct DerivedDataResponse: Codable {
    let success: Bool
    let info: DerivedDataInfo?
    let error: String?
}

struct ClearDerivedDataRequest: Codable {
    let project_pattern: String?
}

struct StatusResponse: Codable {
    let success: Bool
    let message: String
}

struct ErrorResponse: Codable {
    let error: String
    let status: Int
}

struct ListFilesRequest: Codable {
    let path: String
    let recursive: Bool
    let includeHidden: Bool
}

struct ListFilesResponse: Codable {
    let files: [FileInfo]
}

struct ReadFileRequest: Codable {
    let path: String
}

struct ReadFileResponse: Codable {
    let content: String
}

struct WriteFileRequest: Codable {
    let path: String
    let content: String
    let createDirs: Bool
}

struct DeleteFileRequest: Codable {
    let path: String
}

struct AnalyzeCodeRequest: Codable {
    let code: String
    let language: String
}

struct CodeAnalysis: Codable {
    let language: String
    let lines: Int
    let functions: [FunctionInfo]
    let classes: [ClassInfo]
    let imports: [String]
    let complexity: Int?
    let issues: [CodeIssue]
}

struct FunctionInfo: Codable {
    let name: String
    let line: Int
    let parameters: [String]
    let returnType: String?
}

struct ClassInfo: Codable {
    let name: String
    let line: Int
    let methods: [String]
    let properties: [String]
}

struct CodeIssue: Codable {
    let severity: String
    let message: String
    let line: Int
    let column: Int?
}

struct AnalyzeCodeResponse: Codable {
    let analysis: CodeAnalysis
}

struct FormatCodeRequest: Codable {
    let code: String
    let language: String
    let options: [String: String]
}

struct AIFormatRequest: Codable {
    let code: String
    let language: String
    let instructions: String
}

struct FormatCodeResponse: Codable {
    let code: String
}

struct HighlightCodeRequest: Codable {
    let code: String
    let language: String
    let theme: String
}

struct HighlightToken: Codable {
    let text: String
    let tokenType: String
    let start: Int
    let end: Int
}

struct HighlightCodeResponse: Codable {
    let tokens: [HighlightToken]
}

struct AIRefactorRequest: Codable {
    let code: String
    let instructions: String
    let language: String
    let provider: String?
    let model: String?
    let api_key: String?
}

struct AIRefactorResponse: Codable {
    let code: String
}

struct AIRefactorUltraRequest: Codable {
    let files: [FileContent]
    let instructions: String
    let target_language: String?
    let provider: String?
    let model: String?
    let api_key: String?
}

struct FileContent: Codable {
    let path: String
    let content: String
}

struct AIRefactorUltraResponse: Codable {
    let refactored_files: [FileContent]
    let report_summary: String
}

struct AIRefactorReportRequest: Codable {
    let source_code: String
    let refactored_code: String
    let source_language: String
    let target_language: String
    let changes: [String]
    let recommendations: [String]
}

struct AIExplainRequest: Codable {
    let code: String
    let language: String
    let provider: String?
    let model: String?
    let api_key: String?
}

struct AIExplainResponse: Codable {
    let explanation: String
}

struct AICompleteRequest: Codable {
    let code: String
    let context: String
    let language: String
    let provider: String?
    let model: String?
    let api_key: String?
}

struct AICompleteResponse: Codable {
    let completion: String
}

struct AITranspileRequest: Codable {
    let code: String
    let target_language: String
    let instructions: String
    let provider: String?
    let model: String?
    let api_key: String?
}

struct AITranspileResponse: Codable {
    let code: String
}

struct AIModel: Codable, Identifiable {
    var id: String { name }
    let name: String
    let provider: String
    let contextLength: Int
}

struct AIModelsResponse: Codable {
    let models: [AIModel]
}

struct GitStatusRequest: Codable {
    let repoPath: String
}

struct GitStatusResponse: Codable {
    let status: GitStatus
}

struct GitCommitRequest: Codable {
    let repoPath: String
    let message: String
    let files: [String]
}

struct GitPushRequest: Codable {
    let repoPath: String
    let remote: String
    let branch: String
}

struct GitPullRequest: Codable {
    let repoPath: String
    let remote: String
    let branch: String
}

struct GitLogRequest: Codable {
    let repoPath: String
    let limit: Int
}

struct GitLogResponse: Codable {
    let commits: [GitCommit]
}

struct GitDiffRequest: Codable {
    let repoPath: String
    let filePath: String?
}

struct GitDiffResponse: Codable {
    let diff: String
}

struct ExecuteCodeRequest: Codable {
    let code: String
    let language: String
    let args: [String]
    let env: [String: String]
}

struct ExecuteCodeResponse: Codable {
    let output: ExecutionOutput
}

struct StopExecutionRequest: Codable {
    let executionId: String
}

// MARK: - Errors

enum BackendError: LocalizedError {
    case invalidResponse
    case serverError(String)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let message):
            return message
        case .httpError(let code):
            return "HTTP error: \(code)"
        }
    }
}

// Support Structures
struct StreamEvent: Decodable {
    let Output: String?
    let Error: String?
    let Exit: Int?
    
    enum CodingKeys: String, CodingKey {
        case Output, Error, Exit
        case output, error, exit_code, exitCode
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let val = try? container.decode(String.self, forKey: .Output) {
            Output = val
        } else {
            Output = try? container.decodeIfPresent(String.self, forKey: .output)
        }
        
        if let val = try? container.decode(String.self, forKey: .Error) {
            Error = val
        } else {
            Error = try? container.decodeIfPresent(String.self, forKey: .error)
        }
        
        if let val = try? container.decode(Int.self, forKey: .Exit) {
            Exit = val
        } else if let val = try? container.decodeIfPresent(Int.self, forKey: .exit_code) {
             Exit = val
        } else {
             Exit = try? container.decodeIfPresent(Int.self, forKey: .exitCode)
        }
    }
}

// MARK: - Agent Models

struct AgentChatRequest: Codable {
    let session_id: String
    let message: String
    let editor_context: ActiveEditorContext?
    let provider: String?
    let model: String?
    let api_key: String?
    let auto_execute: Bool
}

struct ActiveEditorContext: Codable {
    let active_file: String?
    let active_content: String?
    let cursor_line: Int?
    let selected_text: String?
    let open_files: [String]
}

struct AgentChatResponse: Codable {
    let message_id: String
    let content: String
    let thinking: String?
    let tool_calls: [AgentToolCall]
    let tool_results: [AgentToolResult]
    let pending_changes: [PendingChange]
    let suggestions: [String]
    let plan: ExecutionPlan?
}

struct AgentToolCall: Codable {
    let id: String
    let name: String
    let arguments: String
}

struct AgentToolResult: Codable {
    let tool_call_id: String
    let success: Bool
    let output: String
    let error: String?
}

struct PendingChange: Codable {
    let id: String
    let file_path: String
    let original_content: String
    let modified_content: String
    let status: String
}

struct ExecutionPlan: Codable {
    let id: String
    let description: String
    let steps: [PlanStep]
    let current_step: Int
    let status: String
}

struct PlanStep: Codable, Identifiable {
    let id: String
    let description: String
    let tool: String
    let status: String
    let result: String?
}

// MARK: - Agent Stream Models

enum AgentStreamEvent: Decodable {
    case token(String)
    case toolStart(name: String, id: String)
    case toolEnd(toolCallId: String, success: Bool, output: String, error: String?)
    case pendingChange(PendingChange)
    case error(String)
    case done

    enum CodingKeys: String, CodingKey {
        case type, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "Token":
            let token = try container.decode(String.self, forKey: .data)
            self = .token(token)
        case "ToolStart":
            // Rust serializes as { "name": "...", "id": "..." }
            let data = try container.decode(ToolStartData.self, forKey: .data)
            self = .toolStart(name: data.name, id: data.id)
        case "ToolEnd":
            // Rust serializes as { "id": "...", ... }
            let data = try container.decode(ToolEndData.self, forKey: .data)
            self = .toolEnd(toolCallId: data.id, success: data.success, output: data.output, error: data.error)
        case "PendingChange":
            let change = try container.decode(PendingChange.self, forKey: .data)
            self = .pendingChange(change)
        case "Error":
            let err = try container.decode(String.self, forKey: .data)
            self = .error(err)
        case "Done":
            self = .done
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown event type: \(type)")
        }
    }

    struct ToolStartData: Decodable {
        let name: String
        let id: String
    }

    struct ToolEndData: Decodable {
        let id: String
        let success: Bool
        let output: String
        let error: String?
    }
}

// Helper for dynamic keys
struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
}
