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
    private var recentStderr: String = ""
    
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
        recentStderr = ""
        ndjsonParser.reset()
        stopTimer()
    }
    
    /// Spawn the agent process and send a task
    func start(task: String, workspacePath: String, model: String? = nil) {
        // Always clean up any existing process first
        terminateCurrentProcess()
        
        state = .connecting
        self.model = model
        self.recentStderr = ""
        
        // Resolve and validate executable path before spawning
        guard let resolvedExecutable = ACPHostService.resolveExecutablePath(config.command) else {
            let errMsg: String
            switch config.type {
            case .codexEngine:
                errMsg = "OpenAI Codex CLI is not installed on this Mac (executable '\(config.command)' not found). To use Codex, install it via 'npm install -g @openai/codex' or select Antigravity (AGY), OpenCode, or Claude Code."
            case .claudeCode:
                errMsg = "Anthropic Claude Code CLI is not installed (executable '\(config.command)' not found). Install it via 'npm install -g @anthropic-ai/claude-code' or select another agent."
            case .agy:
                errMsg = "Antigravity CLI is not installed (executable '\(config.command)' not found). Install via 'curl -fsSL https://antigravity.google/install.sh | bash'."
            case .openCode:
                errMsg = "OpenCode CLI is not installed (executable '\(config.command)' not found). Install via 'curl -fsSL https://opencode.ai/install | bash'."
            default:
                errMsg = "CLI executable '\(config.command)' for \(config.type.displayName) was not found in PATH or standard system directories. Please ensure it is installed and executable."
            }
            state = .error(errMsg)
            print("[ACP] \(errMsg)")
            eventContinuation?.yield(.error(errMsg))
            eventContinuation?.finish()
            return
        }
        
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        
        // Configure process based on agent type
        configureProcess(process, executablePath: resolvedExecutable, task: task, workspacePath: workspacePath)
        
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
        
        // Immediate progress event so UI is never blank
        eventContinuation?.yield(.progress(ACPProgress(id: UUID().uuidString, step: 1, total: nil, message: "⚡ Connecting to \(config.name)...")))
        
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
                    self?.recentStderr += text
                    if let cur = self?.recentStderr, cur.count > 4000 {
                        self?.recentStderr = String(cur.suffix(4000))
                    }
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
                    let snippet = self.recentStderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    let errMsg: String
                    if !snippet.isEmpty {
                        errMsg = "Process exited with code \(exitCode):\n\(snippet)"
                    } else {
                        errMsg = "Process exited with code \(exitCode)"
                    }
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
            print("[ACP] Started \(config.type.displayName) agent (stdin pipe active)")
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
    
    /// Reset session state so subsequent commands start a fresh, isolated conversation
    func resetSession() {
        terminateCurrentProcess()
        sessionId = nil
        streamingText = ""
        events = []
        pendingPermissions = []
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
    
    private func configureProcess(_ process: Process, executablePath: String, task: String, workspacePath: String) {
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.currentDirectoryURL = URL(fileURLWithPath: workspacePath)
        
        // Build isolated environment: purge only session IDs, preserving API keys and auth
        var env = ProcessInfo.processInfo.environment
        
        // Only purge session/conversation tracking IDs to prevent crosstalk, keep API keys & auth intact!
        let keysToRemove = env.keys.filter { key in
            key.contains("CONVERSATION_ID") ||
            key.contains("TRAJECTORY_ID") ||
            key.contains("SESSION_ID") ||
            key == "CHROME_DEVTOOLS_MCP_JS" ||
            key == "__CFBundleIdentifier"
        }
        for k in keysToRemove {
            env.removeValue(forKey: k)
        }
        
        // Ensure robust standard Unix & developer tool PATH for macOS GUI apps
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let standardPaths = [
            "\(home)/.local/bin",
            "\(home)/.opencode/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.cargo/bin",
            "\(home)/.bun/bin",
            "\(home)/.npm-global/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        var pathComponents = currentPath.components(separatedBy: ":")
        for p in standardPaths.reversed() {
            if !pathComponents.contains(p) {
                pathComponents.insert(p, at: 0)
            }
        }
        env["PATH"] = pathComponents.joined(separator: ":")
        
        // Forward configured API keys from MicroCode settings if not already in env
        let geminiKey = UserDefaults.standard.string(forKey: "gemini_api_key") ?? ""
        let openaiKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
        let anthropicKey = UserDefaults.standard.string(forKey: "anthropic_api_key") ?? ""
        let deepseekKey = UserDefaults.standard.string(forKey: "deepseek_api_key") ?? ""
        
        if !geminiKey.isEmpty {
            if env["GEMINI_API_KEY"] == nil { env["GEMINI_API_KEY"] = geminiKey }
            if env["GOOGLE_API_KEY"] == nil { env["GOOGLE_API_KEY"] = geminiKey }
        }
        if !openaiKey.isEmpty && env["OPENAI_API_KEY"] == nil {
            env["OPENAI_API_KEY"] = openaiKey
        }
        if !anthropicKey.isEmpty && env["ANTHROPIC_API_KEY"] == nil {
            env["ANTHROPIC_API_KEY"] = anthropicKey
        }
        if !deepseekKey.isEmpty && env["DEEPSEEK_API_KEY"] == nil {
            env["DEEPSEEK_API_KEY"] = deepseekKey
        }
        
        env["MICROCODE_WORKSPACE"] = workspacePath
        env["MICROCODE_ACP"] = "1"
        
        // If continuing an ongoing AGY session within MicroCode, inject our dedicated conversation ID
        if config.type == .agy, let sid = self.sessionId {
            env["ANTIGRAVITY_CONVERSATION_ID"] = sid
        }
        
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
            "--verbose"
        ]
        
        if let model = model, !model.isEmpty {
            args += ["--model", model]
        }
        
        // Dangerously skip permissions if fullAuto
        if config.permissionMode == .fullAuto {
            args += ["--dangerously-skip-permissions"]
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
            "--disable-slash-commands"
        ]
        
        if let model = model, !model.isEmpty {
            args += ["--model", model]
        }
        
        // Fast reasoning effort by default: low/medium starts emitting tokens immediately without 30s delay
        if !config.arguments.contains("--effort") {
            if let model = model, model.contains("high") {
                args += ["--effort", "high"]
            } else if let model = model, model.contains("medium") {
                args += ["--effort", "medium"]
            } else {
                args += ["--effort", "low"]
            }
        }
        
        // If continuing an established MicroCode ACP conversation, resume it:
        if let sid = sessionId {
            args += ["--conversation", sid]
        }
        
        // Extra user-defined arguments
        args += config.arguments
        
        args += ["--print", task]
        
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
        
        // If continuing an established MicroCode ACP session, resume it:
        if let sid = sessionId {
            args += ["-s", sid]
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
    private func resolveCommand(_ command: String) -> String? {
        return ACPHostService.resolveExecutablePath(command)
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
        Task { @MainActor in
            self.detectInstalledAgents()
        }
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
    
    /// Resolve command name or path to a verified executable path on disk
    static func resolveExecutablePath(_ command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // If already an absolute path, verify it is an executable file
        if trimmed.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: trimmed) ? trimmed : nil
        }
        
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let checkPaths = [
            "\(home)/.local/bin/\(trimmed)",
            "\(home)/.opencode/bin/\(trimmed)",
            "/opt/homebrew/bin/\(trimmed)",
            "/usr/local/bin/\(trimmed)",
            "\(home)/.cargo/bin/\(trimmed)",
            "\(home)/.bun/bin/\(trimmed)",
            "\(home)/.npm-global/bin/\(trimmed)",
            "/usr/bin/\(trimmed)",
            "/bin/\(trimmed)",
            "/usr/sbin/\(trimmed)",
            "/sbin/\(trimmed)",
            "/Applications/Zed.app/Contents/MacOS/cli/\(trimmed)",
            "/Applications/Zed.app/Contents/MacOS/\(trimmed)"
        ]
        
        for p in checkPaths {
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
        
        // Search environment PATH directly without spawning subprocesses or pumping runloops
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            let dirs = envPath.split(separator: ":").map(String.init)
            for dir in dirs {
                let candidate = "\(dir)/\(trimmed)"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        
        return nil
    }
    
    /// Detect a single agent type
    private func detectAgent(_ type: ACPAgentType) {
        let command = type.defaultCommand
        guard !command.isEmpty else { return }
        
        if let path = Self.resolveExecutablePath(command) {
            detectedAgents[type] = path
            print("[ACP] Detected \(type.displayName) at \(path)")
            if !registeredConfigs.contains(where: { $0.type == type }) {
                let cfg = ACPAgentConfig.defaultConfig(for: type, command: path)
                registeredConfigs.append(cfg)
                saveConfigs()
            }
        } else {
            detectedAgents.removeValue(forKey: type)
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
    
    /// Reset all active ACP agent sessions to ensure complete isolation on new chat or clear chat
    func resetAllSessions() {
        for session in sessions.values {
            session.resetSession()
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
