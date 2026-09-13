//
//  ACPHostService.swift
//  MicroCode
//
//  ACP Host Service — Spawns and manages external coding agents (Claude Code, AGY, Aider)
//  via subprocess stdio communication. Follows the MCPClient Process+Pipe pattern.
//

import Foundation
import SwiftUI
import Combine

// MARK: - ACP Agent Session

/// Represents an active connection to an external coding agent
@MainActor
class ACPAgentSession: ObservableObject, Identifiable {
    let id: UUID
    let config: ACPAgentConfig
    
    @Published var state: ACPConnectionState = .disconnected
    @Published var events: [ACPStreamEvent] = []
    @Published var streamingText: String = ""
    @Published var pendingPermissions: [ACPPermissionRequest] = []
    @Published var sessionId: String?
    @Published var model: String?
    @Published var elapsedSeconds: Int = 0
    
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var ndjsonParser = ACPNDJSONParser()
    private var timer: Timer?
    private var taskStartTime: Date?
    
    /// Continuation for streaming events to async consumers
    private var eventContinuation: AsyncStream<ACPStreamEvent>.Continuation?
    
    init(config: ACPAgentConfig) {
        self.id = config.id
        self.config = config
    }
    
    /// Async stream of events from the agent
    var eventStream: AsyncStream<ACPStreamEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }
    
    // MARK: - Lifecycle
    
    /// Terminate background process resources without closing the async continuation
    private func terminateCurrentProcess() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        ndjsonParser.reset()
        stopTimer()
    }
    
    /// Spawn the agent process and send a task
    func start(task: String, workspacePath: String, model: String? = nil) {
        // Always clean up any existing process first
        terminateCurrentProcess()
        
        state = .connecting
        self.model = model
        
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        
        // Configure process based on agent type
        configureProcess(process, task: task, workspacePath: workspacePath)
        
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        
        self.process = process
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.ndjsonParser.reset()
        self.streamingText = ""
        self.events = []
        self.pendingPermissions = []
        
        // Handle stdout — NDJSON stream
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async {
                self?.handleStdout(data)
            }
        }
        
        // Handle stderr — debug/error output
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    print("[ACP/\(self?.config.type.rawValue ?? "?")] stderr: \(text)")
                }
            }
        }
        
        // Handle process termination
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let exitCode = proc.terminationStatus
                if exitCode == 0 {
                    if case .running = self.state {
                        self.state = .ready
                    }
                    self.eventContinuation?.yield(.complete(ACPTaskResult(
                        sessionId: self.sessionId ?? "completed",
                        result: self.streamingText,
                        totalCostUSD: nil,
                        tokensUsed: nil,
                        model: self.model
                    )))
                } else {
                    let errMsg = "Process exited with code \(exitCode)"
                    self.state = .error(errMsg)
                    self.eventContinuation?.yield(.error(errMsg))
                }
                self.stopTimer()
                self.eventContinuation?.finish()
            }
        }
        
        do {
            try process.run()
            state = .running(taskId: UUID().uuidString)
            taskStartTime = Date()
            startTimer()
            print("[ACP] Started \(config.type.displayName) agent")
            
            // For non-interactive CLI tools, close stdin write end immediately so they receive EOF and don't block
            if config.type == .openCode || config.type == .claudeCode || config.type == .agy || config.type == .codexEngine {
                try? stdin.fileHandleForWriting.close()
            }
        } catch {
            let errMsg = "Failed to start \(config.type.displayName): \(error.localizedDescription)"
            state = .error(errMsg)
            print("[ACP] \(errMsg)")
            eventContinuation?.yield(.error(errMsg))
            eventContinuation?.finish()
        }
    }
    
    /// Stop the agent process
    func stop() {
        terminateCurrentProcess()
        state = .disconnected
        eventContinuation?.finish()
        eventContinuation = nil
    }
    
    /// Send a follow-up message to an ongoing AGY session via stdin
    func sendInput(_ message: String) {
        guard let pipe = stdinPipe,
              config.type == .agy else { return }
        
        // AGY uses NDJSON with event field on stdin
        let msg: [String: Any] = ["event": "user_message", "user_message": ["content": message]]
        if let data = try? JSONSerialization.data(withJSONObject: msg) {
            var d = data
            d.append("\n".data(using: .utf8)!)
            try? pipe.fileHandleForWriting.write(contentsOf: d)
        }
    }
    
    /// Respond to a permission request
    func respondToPermission(_ requestId: String, approved: Bool) {
        if let idx = pendingPermissions.firstIndex(where: { $0.id == requestId }) {
            pendingPermissions[idx].isApproved = approved
        }
        // For agents that use stdin for permission responses
        if config.type == .agy, let pipe = stdinPipe {
            let response: [String: Any] = [
                "type": "permission_response",
                "request_id": requestId,
                "approved": approved
            ]
            if let data = try? JSONSerialization.data(withJSONObject: response) {
                var d = data
                d.append("\n".data(using: .utf8)!)
                try? pipe.fileHandleForWriting.write(contentsOf: d)
            }
        }
    }
    
    // MARK: - Process Configuration
    
    private func configureProcess(_ process: Process, task: String, workspacePath: String) {
        // Resolve executable path
        let resolvedCommand = resolveCommand(config.command)
        process.executableURL = URL(fileURLWithPath: resolvedCommand)
        process.currentDirectoryURL = URL(fileURLWithPath: workspacePath)
        
        // Build environment
        var env = ProcessInfo.processInfo.environment
        env["MICROCODE_WORKSPACE"] = workspacePath
        for (key, value) in config.environment {
            env[key] = value
        }
        process.environment = env
        
        // Build arguments based on agent type
        switch config.type {
        case .claudeCode:
            process.arguments = buildClaudeCodeArgs(task: task, model: self.model)
        case .agy:
            process.arguments = buildAGYArgs(task: task, model: self.model)
        case .openCode:
            process.arguments = buildOpenCodeArgs(task: task, model: self.model)
        case .aider:
            process.arguments = buildAiderArgs(task: task)
        case .custom:
            process.arguments = config.arguments + [task]
        case .codexEngine:
            var args = config.arguments
            if let model = self.model, !model.isEmpty {
                args += ["--model", model]
            }
            args += [task]
            process.arguments = args
        case .zedEngine:
            var args = config.arguments
            if let model = self.model, !model.isEmpty {
                args += ["--model", model]
            }
            args += [task]
            process.arguments = args
        }
    }
    
    /// Build Claude Code CLI arguments
    private func buildClaudeCodeArgs(task: String, model: String? = nil) -> [String] {
        var args = [
            "-p", task,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages"
        ]
        
        if let model = model, !model.isEmpty {
            args += ["--model", model]
        }
        
        // Permission mode
        args += ["--permission-mode", config.permissionMode.claudeFlag]
        
        // Allowed tools
        let allowed = config.permissionMode.claudeAllowedTools
        if !allowed.isEmpty {
            args += ["--allowedTools"] + allowed
        }
        
        // Resume session if available
        if let sid = sessionId {
            args += ["--resume", sid]
        }
        
        // Extra user-defined arguments
        args += config.arguments
        
        return args
    }
    
    /// Build AGY CLI arguments (print mode with stream-json output)
    private func buildAGYArgs(task: String, model: String? = nil) -> [String] {
        var args = [
            "--output-format", "stream-json",
            "--dangerously-skip-permissions",
            "--print", task
        ]
        
        if let model = model, !model.isEmpty {
            args += ["--model", model]
        }
        
        // Ensure reasoning effort is set (defaults to high for real-time thinking stream)
        if !config.arguments.contains("--effort") {
            args += ["--effort", "high"]
        }
        
        // Extra user-defined arguments
        args += config.arguments
        
        return args
    }
    
    /// Build OpenCode CLI arguments
    private func buildOpenCodeArgs(task: String, model: String? = nil) -> [String] {
        var args = [
            "run",
            "--format", "json",
            "--auto"
        ]
        
        if let model = model, !model.isEmpty {
            args += ["-m", model]
        }
        
        args += [task]
        args += config.arguments
        
        return args
    }
    
    /// Build Aider CLI arguments
    private func buildAiderArgs(task: String) -> [String] {
        var args = [
            "--no-auto-commits",
            "--no-git",
            "--yes",
            "--message", task
        ]
        
        // Extra user-defined arguments
        args += config.arguments
        
        return args
    }
    
    /// Resolve command name to full path
    private func resolveCommand(_ command: String) -> String {
        // If already an absolute path, use it
        if command.hasPrefix("/") { return command }
        
        // Try common locations
        let searchPaths = [
            "/opt/homebrew/bin/",
            "/usr/local/bin/",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.opencode/bin/",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.cargo/bin/",
            "/usr/bin/"
        ]
        
        for path in searchPaths {
            let full = path + command
            if FileManager.default.isExecutableFile(atPath: full) {
                return full
            }
        }
        
        // Fallback: try `which` via shell
        return command
    }
    
    // MARK: - Stream Processing
    
    private func handleStdout(_ data: Data) {
        let jsonLines = ndjsonParser.feed(data)
        
        for json in jsonLines {
            let event: ACPStreamEvent?
            
            switch config.type {
            case .claudeCode:
                event = ClaudeCodeStreamParser.parse(json)
            case .agy:
                event = AGYStreamParser.parse(json)
            case .openCode:
                event = OpenCodeStreamParser.parse(json)
            default:
                // Generic parser — try Claude format first, then AGY, then OpenCode
                event = ClaudeCodeStreamParser.parse(json) ?? AGYStreamParser.parse(json) ?? OpenCodeStreamParser.parse(json)
            }
            
            guard let parsedEvent = event else { continue }
            
            // Process the event
            processEvent(parsedEvent)
        }
    }
    
    private func processEvent(_ event: ACPStreamEvent) {
        events.append(event)
        eventContinuation?.yield(event)
        
        switch event {
        case .text(let text):
            streamingText += text
            
        case .thinking:
            break // Collected in events array
            
        case .toolCall:
            break // Displayed as cards
            
        case .toolResult:
            break // Displayed as result cards
            
        case .permissionRequest(let req):
            pendingPermissions.append(req)
            
        case .error(let msg):
            print("[ACP/\(config.type.rawValue)] Error: \(msg)")
            
        case .complete(let result):
            sessionId = result.sessionId
            state = .ready
            stopTimer()
            
        case .sessionInit(let init_):
            sessionId = init_.sessionId
            model = init_.model
            state = .running(taskId: init_.sessionId)
            
        case .systemInfo, .progress:
            break
        }
    }
    
    // MARK: - Timer
    
    private func startTimer() {
        elapsedSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.elapsedSeconds += 1
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - ACP Host Service

/// Central service managing all external coding agent connections
@MainActor
class ACPHostService: ObservableObject {
    static let shared = ACPHostService()
    
    @Published var sessions: [UUID: ACPAgentSession] = [:]
    @Published var registeredConfigs: [ACPAgentConfig] = []
    @Published var activeAgentId: UUID?
    @Published var detectedAgents: [ACPAgentType: String] = [:] // type -> path
    
    private let configKey = "ACPAgentConfigs"
    
    init() {
        loadConfigs()
    }
    
    /// The currently active agent session, if any
    var activeSession: ACPAgentSession? {
        guard let id = activeAgentId else { return nil }
        return sessions[id]
    }
    
    // MARK: - Agent Detection
    
    /// Scan PATH and standard user locations for known agent binaries
    func detectInstalledAgents() {
        let agentTypes: [ACPAgentType] = [.claudeCode, .agy, .openCode, .aider, .codexEngine, .zedEngine]
        
        for type in agentTypes {
            detectAgent(type)
        }
    }
    
    /// Detect a single agent type
    private func detectAgent(_ type: ACPAgentType) {
        let command = type.defaultCommand
        guard !command.isEmpty else { return }
        
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let checkPaths = [
            "\(home)/.local/bin/\(command)",
            "\(home)/.opencode/bin/\(command)",
            "/opt/homebrew/bin/\(command)",
            "/usr/local/bin/\(command)",
            "\(home)/.cargo/bin/\(command)",
            "/usr/bin/\(command)"
        ]
        
        var resolvedPath: String? = nil
        for p in checkPaths {
            if FileManager.default.isExecutableFile(atPath: p) {
                resolvedPath = p
                break
            }
        }
        
        if resolvedPath == nil {
            // Use /usr/bin/which to find the binary
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = [command]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                        resolvedPath = path
                    }
                }
            } catch {}
        }
        
        if let path = resolvedPath {
            detectedAgents[type] = path
            print("[ACP] Detected \(type.displayName) at \(path)")
            if !registeredConfigs.contains(where: { $0.type == type }) {
                let cfg = ACPAgentConfig.defaultConfig(for: type, command: path)
                registeredConfigs.append(cfg)
                saveConfigs()
            }
        }
    }
    
    // MARK: - Agent Management
    
    /// Register a new agent configuration (1-click connect)
    func registerAgent(_ config: ACPAgentConfig) {
        if let idx = registeredConfigs.firstIndex(where: { $0.id == config.id }) {
            registeredConfigs[idx] = config
        } else {
            registeredConfigs.append(config)
        }
        saveConfigs()
    }
    
    /// Remove an agent configuration
    func removeAgent(_ id: UUID) {
        sessions[id]?.stop()
        sessions.removeValue(forKey: id)
        registeredConfigs.removeAll { $0.id == id }
        if activeAgentId == id { activeAgentId = nil }
        saveConfigs()
    }
    
    /// Quick-connect: detect + register + set active in one click
    func quickConnect(_ type: ACPAgentType, effort: String? = nil) -> ACPAgentConfig? {
        guard let path = detectedAgents[type] else {
            // Try detecting now
            detectAgent(type)
            guard let path = detectedAgents[type] else { return nil }
            return quickConnect(type, path: path, effort: effort)
        }
        return quickConnect(type, path: path, effort: effort)
    }
    
    private func quickConnect(_ type: ACPAgentType, path: String, effort: String? = nil) -> ACPAgentConfig {
        // Check if already registered
        if let existing = registeredConfigs.first(where: { $0.type == type }) {
            var updated = existing
            if let effort = effort, !effort.isEmpty, effort.lowercased() != "agent default" {
                var args = updated.arguments.filter { $0 != "--effort" && $0 != "low" && $0 != "medium" && $0 != "high" }
                args += ["--effort", effort.lowercased()]
                updated.arguments = args
                registerAgent(updated)
            }
            activeAgentId = updated.id
            return updated
        }
        
        // Create new config
        var config = ACPAgentConfig.defaultConfig(for: type, command: path)
        if let effort = effort, !effort.isEmpty, effort.lowercased() != "agent default" {
            config.arguments += ["--effort", effort.lowercased()]
        }
        registerAgent(config)
        activeAgentId = config.id
        return config
    }
    
    // MARK: - Task Execution
    
    /// Send a task to the active external agent
    func getOrCreateSession(for config: ACPAgentConfig) -> ACPAgentSession {
        if let existing = sessions[config.id] {
            return existing
        }
        let session = ACPAgentSession(config: config)
        sessions[config.id] = session
        return session
    }
    
    /// Send a task to the active external agent
    func sendTask(_ task: String, workspacePath: String) {
        guard let agentId = activeAgentId,
              let config = registeredConfigs.first(where: { $0.id == agentId })
        else { return }
        
        // Get or create session
        let session = getOrCreateSession(for: config)
        
        // Start the task
        session.start(task: task, workspacePath: workspacePath)
    }
    
    /// Send a follow-up message to the active agent
    func sendFollowUp(_ message: String) {
        activeSession?.sendInput(message)
    }
    
    /// Stop the active agent and all running sessions
    func stopActiveAgent() {
        activeSession?.stop()
        for session in sessions.values {
            session.stop()
        }
    }
    
    /// Respond to a permission request
    func respondToPermission(_ requestId: String, approved: Bool) {
        activeSession?.respondToPermission(requestId, approved: approved)
    }
    
    // MARK: - Persistence
    
    private func saveConfigs() {
        if let data = try? JSONEncoder().encode(registeredConfigs) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }
    
    private func loadConfigs() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let configs = try? JSONDecoder().decode([ACPAgentConfig].self, from: data) {
            registeredConfigs = configs
        }
    }
}
