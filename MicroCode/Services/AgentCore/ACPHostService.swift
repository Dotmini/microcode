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
    private(set) var config: ACPAgentConfig
    
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
    private var codexCompletion: ACPTaskResult?
    private var processGeneration = UUID()
    private var jsonRpcIdCounter: Int = 1
    private var pendingAcpPromptText: String?
    private var activeWorkspacePath: String = ""
    private var initializeReqId: Int?
    private var sessionNewReqId: Int?
    
    /// Returns true if this agent configuration uses standard JSON-RPC 2.0 Agent Client Protocol (ACP v1)
    var isStandardACPProtocol: Bool {
        let cmdLower = config.command.lowercased()
        let argsLower = config.arguments.map { $0.lowercased() }
        return cmdLower.contains("-acp")
            || cmdLower.hasSuffix("/acp")
            || argsLower.contains("acp")
            || argsLower.contains("--acp")
            || argsLower.contains("--acp-server")
            || argsLower.contains("--experimental-acp")
    }
    
    init(config: ACPAgentConfig) {
        self.id = config.id
        self.config = config
    }

    func updatePermissionMode(_ mode: ACPPermissionMode) {
        config.permissionMode = mode // applies to the next invocation; keep the thread ID
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
        processGeneration = UUID()
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        if let proc = process, proc.isRunning {
            let pid = proc.processIdentifier
            proc.terminationHandler = nil
            proc.terminate()
            // Also terminate child process group if spawned via node/bun shim
            if pid > 0 {
                kill(-pid, SIGTERM)
            }
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        recentStderr = ""
        ndjsonParser.reset()
        stopTimer()
    }
    
    /// Write a JSON-RPC 2.0 message to the agent's stdin pipe
    private func writeJsonRpc(_ payload: [String: Any]) {
        guard let pipe = stdinPipe,
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var lineData = data
        lineData.append(0x0A)
        try? pipe.fileHandleForWriting.write(contentsOf: lineData)
    }
    
    /// Spawn the agent process and send a task
    func start(task: String, workspacePath: String, model: String? = nil) {
        self.activeWorkspacePath = workspacePath
        self.model = model
        TelemetryService.shared.recordAIUsage(
            provider: "ACP · \(config.type.displayName)",
            model: model ?? "",
            taskLabel: "ACP Agent (\(config.type.displayName))"
        )
        
        // If already running a persistent JSON-RPC 2.0 ACP session with an established sessionId, send session/prompt directly!
        if isStandardACPProtocol,
           let proc = process, proc.isRunning,
           let sid = sessionId, !sid.isEmpty {
            streamingText = ""
            state = .running(taskId: sid)
            taskStartTime = Date()
            startTimer()
            let reqId = jsonRpcIdCounter
            jsonRpcIdCounter += 1
            writeJsonRpc(ACPStandardJsonRpcParser.buildSessionPromptRequest(id: reqId, sessionId: sid, text: task))
            return
        }
        
        // Clean up any existing one-shot process first
        terminateCurrentProcess()
        let generation = processGeneration
        
        state = .connecting
        self.recentStderr = ""
        self.codexCompletion = nil
        self.pendingAcpPromptText = isStandardACPProtocol ? task : nil
        
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
        
        // Non-ACP CLI tools (`claude -p`, `agy --print`, `opencode run`, `codex exec`, `aider --message`)
        // expect stdin EOF immediately when the prompt is passed via CLI arguments.
        process.standardInput = isStandardACPProtocol ? stdin : FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        
        self.process = process
        self.stdinPipe = isStandardACPProtocol ? stdin : nil
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
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async {
                guard self?.processGeneration == generation else { return }
                self?.handleStdout(data)
            }
        }
        
        // Handle stderr — debug/error output
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                guard self?.processGeneration == generation else { return }
                self?.recentStderr += text
                if let cur = self?.recentStderr, cur.count > 4000 {
                    self?.recentStderr = String(cur.suffix(4000))
                }
                print("[ACP/\(self?.config.type.rawValue ?? "?")] stderr: \(text)")
            }
        }
        
        // Handle process termination
        process.terminationHandler = { [weak self] proc in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            let remainingOut = stdout.fileHandleForReading.availableData
            let remainingErr = stderr.fileHandleForReading.availableData
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.processGeneration == generation else { return }
                if !remainingOut.isEmpty {
                    self.handleStdout(remainingOut)
                }
                for trailingJson in self.ndjsonParser.flushRemaining() {
                    self.handleParsedJsonLine(trailingJson)
                }
                if !remainingErr.isEmpty {
                    let errText = String(decoding: remainingErr, as: UTF8.self)
                    self.recentStderr += errText
                }
                let exitCode = proc.terminationStatus
                if exitCode == 0 {
                    if case .error = self.state {
                        self.stopTimer()
                        self.eventContinuation?.finish()
                        return
                    }
                    if case .running = self.state {
                        self.state = .ready
                    }
                    self.eventContinuation?.yield(.complete(ACPTaskResult(
                        sessionId: self.sessionId ?? "completed",
                        result: self.streamingText,
                        totalCostUSD: nil,
                        tokensUsed: self.codexCompletion?.tokensUsed,
                        model: self.model
                    )))
                } else {
                    let snippet = self.recentStderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    let errMsg: String
                    if !snippet.isEmpty {
                        errMsg = "Process exited with code \(exitCode):\n\(snippet)"
                    } else if !self.streamingText.isEmpty {
                        // Emit partial streaming text if exit was non-zero but content was already produced
                        self.state = .ready
                        self.eventContinuation?.yield(.complete(ACPTaskResult(
                            sessionId: self.sessionId ?? "completed",
                            result: self.streamingText,
                            totalCostUSD: nil,
                            tokensUsed: nil,
                            model: self.model
                        )))
                        self.stopTimer()
                        self.eventContinuation?.finish()
                        return
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
            state = isStandardACPProtocol ? .initializing : .running(taskId: UUID().uuidString)
            taskStartTime = Date()
            startTimer()
            print("[ACP] Started \(config.type.displayName) agent (ACP v1 JSON-RPC: \(isStandardACPProtocol))")
            
            if isStandardACPProtocol {
                let initId = jsonRpcIdCounter
                jsonRpcIdCounter += 1
                initializeReqId = initId
                writeJsonRpc(ACPStandardJsonRpcParser.buildInitializeRequest(id: initId))
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
        if isStandardACPProtocol, let sid = sessionId {
            writeJsonRpc(ACPStandardJsonRpcParser.buildSessionCancelNotification(sessionId: sid))
        }
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
    
    /// Send a follow-up message to an ongoing ACP or AGY session via stdin
    func sendInput(_ message: String) {
        if isStandardACPProtocol, let sid = sessionId {
            let reqId = jsonRpcIdCounter
            jsonRpcIdCounter += 1
            writeJsonRpc(ACPStandardJsonRpcParser.buildSessionPromptRequest(id: reqId, sessionId: sid, text: message))
            return
        }
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
    
    /// Respond to a permission request (supports both ACP v1 `session/request_permission` and legacy AGY)
    func respondToPermission(_ requestId: String, approved: Bool) {
        if let idx = pendingPermissions.firstIndex(where: { $0.id == requestId }) {
            pendingPermissions[idx].isApproved = approved
        }
        if isStandardACPProtocol {
            let rpcId: Any = Int(requestId) ?? requestId
            let optionId = approved ? "allow_once" : "reject_once"
            writeJsonRpc(ACPStandardJsonRpcParser.buildPermissionResponse(requestId: rpcId, optionId: optionId))
            return
        }
        // For legacy AGY agents that use stdin for permission responses
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
        
        // Build isolated environment: purge session IDs and internal backend tokens
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "MICROCODE_LOCAL_API_TOKEN")
        
        // Purge session/conversation tracking IDs to prevent crosstalk, keep API keys & auth intact!
        let keysToRemove = env.keys.filter { key in
            key.contains("CONVERSATION_ID") ||
            key.contains("TRAJECTORY_ID") ||
            key.contains("SESSION_ID") ||
            key == "CLAUDECODE" ||
            key == "CLAUDE_CODE_ENTRYPOINT" ||
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
            "\(home)/.codex/plugins/.plugin-appserver/codex-cli/bin",
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
        
        // If launched in standard ACP 1.0 JSON-RPC mode, pass only the ACP flags (prompt is sent over JSON-RPC stdio)
        if isStandardACPProtocol {
            process.arguments = config.arguments
            return
        }
        
        // Build arguments based on agent type (CLI fallback mode)
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
            process.arguments = CodexProcessArguments.build(
                task: task, model: self.model, sessionID: sessionId,
                permissionMode: config.permissionMode, extra: config.arguments
            )
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
            "--include-partial-messages",
            "--verbose"
        ]
        
        if let rawModel = model, !rawModel.isEmpty {
            let lower = rawModel.lowercased()
            let sanitizedModel: String?
            if lower.contains("5-5") || lower.contains("argon") || lower.contains("gemini") || lower.contains("gpt") || lower.contains("/") {
                // Non-Anthropic or AGY-exclusive model IDs are mapped to standard Claude CLI aliases
                sanitizedModel = lower.contains("opus") ? "opus" : "sonnet"
            } else {
                sanitizedModel = rawModel
            }
            if let m = sanitizedModel {
                args += ["--model", m]
            }
        }
        
        // Non-interactive `-p` mode requires permission bypass or full tool allowance so it does not stall on TTY approval prompts
        args += ["--dangerously-skip-permissions"]
        
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
            "--disable-slash-commands",
            "--dangerously-skip-permissions"
        ]
        
        let resolvedModel: String = {
            guard let raw = model?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  !raw.contains("/"),
                  raw != "gemini-3-flash-agent" else {
                return "gemini-3.8-flash-low"
            }
            return raw
        }()
        args += ["--model", resolvedModel]
        
        // Fast reasoning effort by default: match model tier suffix (low/medium/high)
        if !config.arguments.contains("--effort") {
            if resolvedModel.contains("high") {
                args += ["--effort", "high"]
            } else if resolvedModel.contains("medium") {
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
        
        args.append("--print=\(task)")
        
        return args
    }
    
    /// Build OpenCode CLI arguments
    private func buildOpenCodeArgs(task: String, model: String? = nil) -> [String] {
        var args = [
            "run",
            "--format", "json"
        ]
        
        let resolvedModel: String
        if let model = model, !model.isEmpty, model.contains("/"), !model.contains("nemotron-3.5-lightning-free") {
            resolvedModel = model
        } else {
            resolvedModel = "opencode/glm-5.3-flash-free"
        }
        args += ["-m", resolvedModel]
        
        // If continuing an established MicroCode ACP session, resume it:
        if let sid = sessionId, !sid.isEmpty, sid != "opencode", sid != "completed", sid != "unknown" {
            args += ["-s", sid]
        }
        
        args += [task]
        args += config.arguments.filter { $0 != "--auto" }
        
        return args
    }
    
    /// Build Aider CLI arguments
    private func buildAiderArgs(task: String) -> [String] {
        var args = [
            "--no-auto-commits",
            "--no-git"
        ]
        if config.permissionMode == .fullAuto {
            args.append("--yes")
        }
        args += ["--message", task]
        
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
            handleParsedJsonLine(json)
        }
    }
    
    private func handleParsedJsonLine(_ json: [String: Any]) {
        // 1. Check if this is a standard ACP 1.0 JSON-RPC 2.0 frame
        if (json["jsonrpc"] as? String) == "2.0" {
            handleAcpJsonRpcFrame(json)
            return
        }
        
        // 2. Vendor-specific CLI NDJSON stream parsers
        var parsedEvents: [ACPStreamEvent] = []
        switch config.type {
        case .claudeCode:
            parsedEvents = ClaudeCodeStreamParser.parseAll(json)
        case .agy:
            if let ev = AGYStreamParser.parse(json) { parsedEvents = [ev] }
        case .openCode:
            if let ev = OpenCodeStreamParser.parse(json) { parsedEvents = [ev] }
        case .codexEngine:
            if let ev = CodexStreamParser.parse(json) { parsedEvents = [ev] }
        default:
            let claudeEvs = ClaudeCodeStreamParser.parseAll(json)
            if !claudeEvs.isEmpty {
                parsedEvents = claudeEvs
            } else if let ev = AGYStreamParser.parse(json) ?? OpenCodeStreamParser.parse(json) {
                parsedEvents = [ev]
            }
        }
        
        for parsedEvent in parsedEvents {
            processEvent(parsedEvent)
        }
    }
    
    /// Handles bidirectional JSON-RPC 2.0 Agent Client Protocol (ACP v1) messages
    private func handleAcpJsonRpcFrame(_ json: [String: Any]) {
        // Handle incoming agent -> client requests (`fs/read_text_file`, `fs/write_text_file`, `session/request_permission`)
        if let method = json["method"] as? String, let reqId = json["id"] {
            let params = json["params"] as? [String: Any] ?? [:]
            switch method {
            case "fs/read_text_file":
                guard let path = params["path"] as? String else {
                    writeJsonRpc(["jsonrpc": "2.0", "id": reqId, "error": ["code": -32602, "message": "Missing path"]])
                    return
                }
                let resolved = resolveWorkspacePath(path)
                guard isPathInsideWorkspace(resolved) else {
                    writeJsonRpc(["jsonrpc": "2.0", "id": reqId, "error": ["code": -32602, "message": "Path outside workspace"]])
                    return
                }
                do {
                    let content = try String(contentsOfFile: resolved, encoding: .utf8)
                    writeJsonRpc(["jsonrpc": "2.0", "id": reqId, "result": ["content": content]])
                } catch {
                    writeJsonRpc(["jsonrpc": "2.0", "id": reqId, "error": ["code": -32000, "message": error.localizedDescription]])
                }
                return
                
            case "fs/write_text_file":
                guard let path = params["path"] as? String,
                      let content = params["content"] as? String else {
                    writeJsonRpc(["jsonrpc": "2.0", "id": reqId, "error": ["code": -32602, "message": "Missing path or content"]])
                    return
                }
                let resolved = resolveWorkspacePath(path)
                guard isPathInsideWorkspace(resolved) else {
                    writeJsonRpc(["jsonrpc": "2.0", "id": reqId, "error": ["code": -32602, "message": "Path outside workspace"]])
                    return
                }
                do {
                    let url = URL(fileURLWithPath: resolved)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try content.write(to: url, atomically: true, encoding: .utf8)
                    writeJsonRpc(["jsonrpc": "2.0", "id": reqId, "result": [:] as [String: Any]])
                } catch {
                    writeJsonRpc(["jsonrpc": "2.0", "id": reqId, "error": ["code": -32000, "message": error.localizedDescription]])
                }
                return
                
            case "session/request_permission":
                if config.permissionMode == .fullAuto {
                    let options = (params["options"] as? [[String: Any]]) ?? []
                    let allowId = options.first(where: { ($0["kind"] as? String)?.hasPrefix("allow") == true })?["optionId"] as? String ?? "allow_once"
                    writeJsonRpc(ACPStandardJsonRpcParser.buildPermissionResponse(requestId: reqId, optionId: allowId))
                    return
                }
            default:
                break
            }
        }
        
        // Progress handshake state machine (`initialize` -> `session/new` -> `session/prompt`)
        if let respId = json["id"] as? Int, let result = json["result"] as? [String: Any] {
            if respId == initializeReqId {
                let newSessId = jsonRpcIdCounter
                jsonRpcIdCounter += 1
                sessionNewReqId = newSessId
                let cwd = activeWorkspacePath.isEmpty ? FileManager.default.currentDirectoryPath : activeWorkspacePath
                writeJsonRpc(ACPStandardJsonRpcParser.buildSessionNewRequest(id: newSessId, cwd: cwd))
                return
            } else if respId == sessionNewReqId, let sid = result["sessionId"] as? String {
                self.sessionId = sid
                self.state = .running(taskId: sid)
                processEvent(.sessionInit(ACPSessionInit(sessionId: sid, model: self.model, tools: [], capabilities: ["acp-v1"])))
                if let prompt = pendingAcpPromptText {
                    pendingAcpPromptText = nil
                    let promptId = jsonRpcIdCounter
                    jsonRpcIdCounter += 1
                    writeJsonRpc(ACPStandardJsonRpcParser.buildSessionPromptRequest(id: promptId, sessionId: sid, text: prompt))
                }
                return
            }
        }
        
        for ev in ACPStandardJsonRpcParser.parseEvents(json) {
            processEvent(ev)
        }
    }
    
    private func resolveWorkspacePath(_ path: String) -> String {
        if path.hasPrefix("/") { return path }
        let base = activeWorkspacePath.isEmpty ? FileManager.default.currentDirectoryPath : activeWorkspacePath
        return URL(fileURLWithPath: base).appendingPathComponent(path).standardizedFileURL.path
    }
    
    private func isPathInsideWorkspace(_ targetPath: String) -> Bool {
        guard !activeWorkspacePath.isEmpty else { return true }
        let wsURL = URL(fileURLWithPath: activeWorkspacePath).standardizedFileURL.resolvingSymlinksInPath()
        let targetURL = URL(fileURLWithPath: targetPath).standardizedFileURL.resolvingSymlinksInPath()
        return targetURL.path == wsURL.path || targetURL.path.hasPrefix(wsURL.path + "/")
    }
    
    private func processEvent(_ event: ACPStreamEvent) {
        if config.type == .codexEngine, case .complete(let result) = event {
            codexCompletion = result
            return // emit completion once, after the process actually exits
        }
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
            state = .error(msg)
            print("[ACP/\(config.type.rawValue)] Error: \(msg)")
            
        case .complete(let result):
            if !result.sessionId.hasPrefix("acp_turn_") && result.sessionId != "completed" && result.sessionId != "unknown" {
                sessionId = result.sessionId
            }
            state = .ready
            stopTimer()
            
        case .sessionInit(let init_):
            sessionId = init_.sessionId
            if let reportedModel = init_.model {
                model = reportedModel
                TelemetryService.shared.recordAIConfiguration(
                    provider: "ACP · \(config.type.displayName)",
                    model: reportedModel
                )
            }
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
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopActiveAgent()
            }
        }
        Task { @MainActor in
            self.detectInstalledAgents()
        }
    }
    
    /// The currently active agent session, if any
    var activeSession: ACPAgentSession? {
        guard let id = activeAgentId else { return nil }
        return sessions[id]
    }
    
    /// Whether any ACP external agent session is currently executing
    var isAnySessionRunning: Bool {
        sessions.values.contains { $0.state.isActive }
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
    nonisolated static func resolveExecutablePath(_ command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // If already an absolute path, verify it is an executable file; if stale, fallback to basename lookup
        if trimmed.hasPrefix("/") {
            if trimmed.contains(".plugin-appserver/codex-cli") {
                let localCodex = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/codex"
                if FileManager.default.isExecutableFile(atPath: localCodex) {
                    return localCodex
                }
            }
            if FileManager.default.isExecutableFile(atPath: trimmed) {
                return trimmed
            }
            let basename = URL(fileURLWithPath: trimmed).lastPathComponent
            if !basename.isEmpty, basename != trimmed {
                return resolveExecutablePath(basename)
            }
            return nil
        }
        
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let checkPaths = [
            "\(home)/.local/bin/\(trimmed)",
            "\(home)/.opencode/bin/\(trimmed)",
            "\(home)/.codex/plugins/.plugin-appserver/codex-cli/bin/\(trimmed)",
            "\(home)/.codex/plugins/.plugin-appserver/codex-cli/CodexCLI.app/Contents/MacOS/\(trimmed)",
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
            if let existingIdx = registeredConfigs.firstIndex(where: { $0.type == type }) {
                let existingCmd = registeredConfigs[existingIdx].command
                if !FileManager.default.isExecutableFile(atPath: existingCmd) || existingCmd.contains(".plugin-appserver/codex-cli") {
                    registeredConfigs[existingIdx].command = path
                    saveConfigs()
                }
            } else {
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

    func setPermissionMode(_ mode: ACPPermissionMode, for id: UUID) {
        guard let index = registeredConfigs.firstIndex(where: { $0.id == id }) else { return }
        guard registeredConfigs[index].permissionMode != mode else { return }
        registeredConfigs[index].permissionMode = mode
        sessions[id]?.updatePermissionMode(mode)
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
            if !FileManager.default.isExecutableFile(atPath: updated.command) {
                updated.command = path
            }
            if let effort = effort, !effort.isEmpty, effort.lowercased() != "agent default" {
                var args = updated.arguments.filter { $0 != "--effort" && $0 != "low" && $0 != "medium" && $0 != "high" }
                args += ["--effort", effort.lowercased()]
                updated.arguments = args
            }
            registerAgent(updated)
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
           var configs = try? JSONDecoder().decode([ACPAgentConfig].self, from: data) {
            for i in configs.indices {
                if (!FileManager.default.isExecutableFile(atPath: configs[i].command) || configs[i].command.contains(".plugin-appserver/codex-cli")),
                   let healed = Self.resolveExecutablePath(configs[i].type.defaultCommand) {
                    configs[i].command = healed
                }
            }
            registeredConfigs = configs
        }
    }
}
