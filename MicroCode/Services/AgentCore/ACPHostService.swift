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
    /// True when `.geminiCLI` transparently bridges personal OAuth / AGY-exclusive models (`gemini-4-argon*`) via `agy`.
    private var activeTurnUsesAGYBridge: Bool = false
    private var didRetryGeminiViaAGY: Bool = false
    /// Tracks whether `ClaudeCodeStreamParser` already emitted incremental `stream_event` text/thinking deltas in the current turn.
    private var didReceiveClaudeStreamDelta: Bool = false
    
    /// Returns true if this agent configuration uses standard JSON-RPC 2.0 Agent Client Protocol (ACP v1)
    var isStandardACPProtocol: Bool {
        if activeTurnUsesAGYBridge {
            return false
        }
        if config.type == .goose {
            return true // `goose acp` natively speaks ACP v1 JSON-RPC 2.0 over stdio
        }
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
        var sanitized = config
        if !sanitized.type.supportsEffortFlag {
            sanitized.arguments = ACPAgentConfig.stripEffortArguments(sanitized.arguments)
        }
        self.config = sanitized
    }

    func syncConfig(_ updated: ACPAgentConfig) {
        var sanitized = updated
        if !sanitized.type.supportsEffortFlag {
            sanitized.arguments = ACPAgentConfig.stripEffortArguments(sanitized.arguments)
        }
        self.config = sanitized
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
            // Terminate any child MCP / node / npx processes spawned by this ACP CLI first
            if pid > 0 {
                let reaper = Process()
                reaper.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                reaper.arguments = ["-TERM", "-P", "\(pid)"]
                reaper.standardOutput = FileHandle.nullDevice
                reaper.standardError = FileHandle.nullDevice
                try? reaper.run()
            }
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
        self.didRetryGeminiViaAGY = false
        self.activeTurnUsesAGYBridge = false
        
        // Pre-flight check for `@google/gemini-cli`:
        // Google deprecated personal OAuth (`oauth-personal` / `Gemini Code Assist for individuals`) in `@google/gemini-cli`
        // (`IneligibleTierError: migrate to Antigravity`) and AGY-exclusive models (`gemini-4-argon*`) are hosted on `agy`.
        // When no direct Gemini API / Vertex / Enterprise project credentials exist and `agy` is installed, bridge transparently.
        var useAGYBridge = false
        var resolvedExecutable: String?
        if config.type == .geminiCLI && !isStandardACPProtocol,
           let agyPath = Self.resolveAGYBridgePathIfNeeded(requestedModel: model, configEnv: config.environment) {
            useAGYBridge = true
            resolvedExecutable = agyPath
        } else {
            resolvedExecutable = ACPHostService.resolveExecutablePath(config.command)
        }
        
        // Resolve and validate executable path before spawning
        guard let executablePath = resolvedExecutable else {
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
            case .githubCopilot:
                errMsg = "GitHub Copilot CLI is not installed. Run 'npm install -g @github/copilot' or 'gh copilot' in Terminal once to install it."
            default:
                errMsg = "CLI executable '\(config.command)' for \(config.type.displayName) was not found in PATH or standard system directories. Please ensure it is installed and executable."
            }
            state = .error(errMsg)
            print("[ACP] \(errMsg)")
            eventContinuation?.yield(.error(errMsg))
            eventContinuation?.finish()
            return
        }
        
        if config.type == .zedEngine && !isStandardACPProtocol && URL(fileURLWithPath: executablePath).lastPathComponent == "zed" {
            let errMsg = "Zed CLI ('\(executablePath)') is a GUI editor launcher and does not execute headless AI prompts. Please select Antigravity (AGY), Claude Code, OpenAI Codex, Gemini CLI, or OpenCode."
            state = .error(errMsg)
            print("[ACP] \(errMsg)")
            eventContinuation?.yield(.error(errMsg))
            eventContinuation?.finish()
            return
        }
        
        launchSubprocess(executablePath: executablePath, task: task, workspacePath: workspacePath, useAGYBridge: useAGYBridge, isRetry: false)
    }
    
    private func launchSubprocess(executablePath: String, task: String, workspacePath: String, useAGYBridge: Bool, isRetry: Bool) {
        if isRetry {
            terminateCurrentProcess()
        }
        self.activeTurnUsesAGYBridge = useAGYBridge
        if config.type == .agy || useAGYBridge {
            Self.sanitizeAGYMCPConfigsIfNeeded()
        }
        let generation = processGeneration
        
        state = .connecting
        self.recentStderr = ""
        self.codexCompletion = nil
        self.didReceiveClaudeStreamDelta = false
        self.pendingAcpPromptText = isStandardACPProtocol ? task : nil
        
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        
        // Configure process based on agent type
        configureProcess(process, executablePath: executablePath, task: task, workspacePath: workspacePath)
        
        // Non-ACP CLI tools (`claude -p`, `agy --print`, `opencode run`, `codex exec`, `gemini -p`, `aider --message`)
        // expect stdin EOF immediately when the prompt is passed via CLI arguments.
        process.standardInput = isStandardACPProtocol ? stdin : FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        
        self.process = process
        self.stdinPipe = isStandardACPProtocol ? stdin : nil
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.ndjsonParser.reset()
        if !isRetry {
            self.streamingText = ""
            self.events = []
            self.pendingPermissions = []
            // Immediate progress event so UI is never blank
            eventContinuation?.yield(.progress(ACPProgress(id: UUID().uuidString, step: 1, total: nil, message: "⚡ Connecting to \(config.name)...")))
        }
        
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
                    
                    // Automatic runtime migration when `@google/gemini-cli` rejects deprecated personal OAuth (`IneligibleTierError`)
                    let isGeminiOAuthDeprecated = self.config.type == .geminiCLI
                        && !self.activeTurnUsesAGYBridge
                        && (snippet.contains("IneligibleTierError") || snippet.contains("no longer supported for Gemini Code Assist"))
                    if isGeminiOAuthDeprecated && !self.didRetryGeminiViaAGY,
                       let agyPath = ACPHostService.resolveExecutablePath("agy") {
                        self.didRetryGeminiViaAGY = true
                        self.eventContinuation?.yield(.progress(ACPProgress(
                            id: UUID().uuidString,
                            step: 1,
                            total: nil,
                            message: "↪ Migrating Gemini CLI OAuth session to Google Antigravity (AGY)..."
                        )))
                        self.launchSubprocess(
                            executablePath: agyPath,
                            task: task,
                            workspacePath: workspacePath,
                            useAGYBridge: true,
                            isRetry: true
                        )
                        return
                    }
                    
                    let errMsg: String
                    if isGeminiOAuthDeprecated {
                        errMsg = "Google deprecated personal OAuth in `@google/gemini-cli` (IneligibleTierError). Add a Gemini API Key in Settings → AI & Agent → Direct API Key, or install Google Antigravity CLI (`agy`)."
                    } else if !snippet.isEmpty {
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
            print("[ACP] Started \(config.type.displayName) agent (ACP v1 JSON-RPC: \(isStandardACPProtocol), AGY bridge: \(useAGYBridge))")
            
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
        if !(env["GEMINI_API_KEY"] ?? "").isEmpty && env["GEMINI_DEFAULT_AUTH_TYPE"] == nil {
            env["GEMINI_DEFAULT_AUTH_TYPE"] = "gemini-api-key"
        }
        if (env["TERM"] ?? "").isEmpty || env["TERM"] == "dumb" {
            env["TERM"] = "xterm-256color"
        }
        if env["COLORTERM"] == nil {
            env["COLORTERM"] = "truecolor"
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
        
        // 9Router Smart Gateway proxy injection for external CLI harnesses when enabled
        let routeHarnessesVia9Router = UserDefaults.standard.bool(forKey: "use9RouterForHarnesses")
        if routeHarnessesVia9Router {
            let routerBase = (UserDefaults.standard.string(forKey: "9router_base_url") ?? "http://127.0.0.1:20128/v1")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let routerRoot = routerBase.hasSuffix("/v1") ? String(routerBase.dropLast(3)) : routerBase
            let routerKey = UserDefaults.standard.string(forKey: "9router_api_key")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let effectiveKey = routerKey.isEmpty ? "sk-9router-local" : routerKey
            env["OPENAI_BASE_URL"] = routerBase
            env["ANTHROPIC_BASE_URL"] = routerRoot
            if env["OPENAI_API_KEY"] == nil || !routerKey.isEmpty {
                env["OPENAI_API_KEY"] = effectiveKey
            }
            if env["ANTHROPIC_API_KEY"] == nil || !routerKey.isEmpty {
                env["ANTHROPIC_API_KEY"] = effectiveKey
            }
        }
        
        let effectiveType: ACPAgentType = activeTurnUsesAGYBridge ? .agy : config.type
        
        // If continuing an ongoing AGY session within MicroCode, inject our dedicated conversation ID
        if effectiveType == .agy, let sid = self.sessionId {
            env["ANTIGRAVITY_CONVERSATION_ID"] = sid
        }
        
        for (key, value) in config.environment {
            env[key] = value
        }
        process.environment = env
        
        let safeExtraArgs = effectiveType.supportsEffortFlag
            ? config.arguments
            : ACPAgentConfig.stripEffortArguments(config.arguments)
        
        // If launched in standard ACP 1.0 JSON-RPC mode, pass only the ACP flags (prompt is sent over JSON-RPC stdio)
        if isStandardACPProtocol {
            if effectiveType == .goose && !safeExtraArgs.contains("acp") {
                process.arguments = ["acp"] + safeExtraArgs
            } else {
                process.arguments = safeExtraArgs
            }
            return
        }
        
        // Build arguments based on agent type (CLI fallback mode)
        switch effectiveType {
        case .claudeCode:
            process.arguments = buildClaudeCodeArgs(task: task, model: self.model)
        case .agy:
            process.arguments = buildAGYArgs(task: task, model: self.model, extraArgs: safeExtraArgs)
        case .openCode:
            process.arguments = buildOpenCodeArgs(task: task, model: self.model, extraArgs: safeExtraArgs)
        case .codexEngine:
            process.arguments = CodexProcessArguments.build(
                task: task, model: self.model, sessionID: sessionId,
                permissionMode: config.permissionMode, extra: safeExtraArgs
            )
        case .geminiCLI:
            var args = ["-p", task, "--output-format", "stream-json", "--yolo"]
            if let sanitizedModel = Self.sanitizeGeminiCLIModel(self.model) {
                args += ["-m", sanitizedModel]
            }
            args += safeExtraArgs
            process.arguments = args
        case .qwenCode:
            var args = ["-p", task, "--output-format", "stream-json", "--yolo"]
            if let model = self.model, !model.isEmpty, model.lowercased().contains("qwen") {
                args += ["-m", model]
            }
            args += safeExtraArgs
            process.arguments = args
        case .cursorAgent:
            var args = ["-p", task, "--output-format", "stream-json", "--force"]
            if let model = self.model, !model.isEmpty,
               !model.contains("/"), !model.lowercased().contains("argon"), !model.lowercased().contains("5-5") {
                args += ["--model", model]
            }
            args += safeExtraArgs
            process.arguments = args
        case .githubCopilot:
            var args: [String] = []
            if URL(fileURLWithPath: executablePath).lastPathComponent == "gh" {
                args.append("copilot")
            }
            args += ["-p", task, "--allow-all-tools"]
            if let model = self.model, !model.isEmpty,
               !model.contains("/"), !model.lowercased().contains("argon"), !model.lowercased().contains("5-5") {
                args += ["--model", model]
            }
            args += safeExtraArgs
            process.arguments = args
        case .goose:
            process.arguments = ["acp"] + safeExtraArgs
        case .cline:
            var args = [task]
            if config.permissionMode == .fullAuto {
                args.append("--auto-approve")
            }
            args += safeExtraArgs
            process.arguments = args
        case .aider:
            process.arguments = buildAiderArgs(task: task, extraArgs: safeExtraArgs)
        case .custom:
            process.arguments = safeExtraArgs + [task]
        case .zedEngine:
            var args = safeExtraArgs
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
        
        var resolvedModelAlias: String? = nil
        if let rawModel = model?.trimmingCharacters(in: .whitespacesAndNewlines), !rawModel.isEmpty {
            let lower = rawModel.lowercased()
            let sanitizedModel: String?
            if lower == "auto" || lower == "default" {
                sanitizedModel = nil
            } else if lower.contains("5-5")
                || lower.hasSuffix("-thinking")
                || lower.hasSuffix("-high")
                || lower.hasSuffix("-medium")
                || lower.hasSuffix("-low")
                || lower.contains("argon")
                || lower.contains("gemini")
                || lower.contains("gemma")
                || lower.contains("gpt")
                || lower.contains("deepseek")
                || lower.contains("qwen")
                || lower.contains("glm")
                || lower.contains("/") {
                // Non-Anthropic or AGY-exclusive tiered model IDs map to official Claude CLI aliases
                if lower.contains("opus") {
                    sanitizedModel = "opus"
                } else if lower.contains("haiku") {
                    sanitizedModel = "haiku"
                } else {
                    sanitizedModel = "sonnet"
                }
            } else {
                sanitizedModel = rawModel
            }
            resolvedModelAlias = sanitizedModel
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
        
        // Haiku models do not support `--effort` in Claude Code CLI
        if let m = resolvedModelAlias?.lowercased(), m.contains("haiku") {
            args += ACPAgentConfig.stripEffortArguments(config.arguments)
        } else {
            args += config.arguments
        }
        
        return args
    }
    
    /// Build AGY CLI arguments (print mode with stream-json output)
    /// Note: `agy` model slugs (`gemini-4-argon-low`, `claude-opus-5-5-high`, `gpt-oss-120b-medium`, etc.)
    /// already encode their reasoning effort tier directly. Passing `--effort` causes `agy` to exit with code 1
    /// (`conflicts with --effort` or `--effort is not supported for model`), so `--effort` must never be passed.
    private func buildAGYArgs(task: String, model: String? = nil, extraArgs: [String]? = nil) -> [String] {
        var args = [
            "--output-format", "stream-json",
            "--disable-slash-commands",
            "--dangerously-skip-permissions"
        ]
        
        let resolvedModel = Self.normalizeAGYModel(model)
        args += ["--model", resolvedModel]
        
        // If continuing an established MicroCode ACP conversation, resume it:
        if let sid = sessionId {
            args += ["--conversation", sid]
        }
        
        // Extra user-defined arguments (always stripped of `--effort` to prevent AGY tier conflicts)
        let userExtra = ACPAgentConfig.stripEffortArguments(extraArgs ?? config.arguments)
        args += userExtra
        
        args.append("--print=\(task)")
        
        return args
    }
    
    /// Normalizes MicroCode catalog model IDs into exact model slugs accepted by `agy --model`
    nonisolated static func normalizeAGYModel(_ rawModel: String?) -> String {
        guard let raw = rawModel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              !raw.contains("/"),
              raw != "gemini-3-flash-agent" else {
            return "gemini-3.8-flash-low"
        }
        let lower = raw.lowercased()
        
        // Exact live AGY model families (`agy models`)
        if lower.hasPrefix("gemini-4-argon-")
            && ["gemini-4-argon-low", "gemini-4-argon-medium", "gemini-4-argon-high"].contains(lower) {
            return lower
        }
        if lower.hasPrefix("gemini-3.8-flash-")
            && ["gemini-3.8-flash-low", "gemini-3.8-flash-medium", "gemini-3.8-flash-high"].contains(lower) {
            return lower
        }
        if lower.hasPrefix("claude-opus-5-5-")
            && ["claude-opus-5-5-low", "claude-opus-5-5-medium", "claude-opus-5-5-high"].contains(lower) {
            return lower
        }
        if lower.hasPrefix("claude-sonnet-5-5-")
            && ["claude-sonnet-5-5-low", "claude-sonnet-5-5-medium", "claude-sonnet-5-5-high"].contains(lower) {
            return lower
        }
        if lower.hasPrefix("gpt-oss-") {
            return lower
        }
        
        // Map any legacy/stale Claude model IDs (e.g. `claude-opus-4-6-thinking`, `claude-sonnet-4-6`, `opus`, `sonnet`)
        if lower.contains("claude") || lower == "opus" || lower == "sonnet" || lower == "haiku" {
            let tier: String
            if lower.hasSuffix("-low") {
                tier = "low"
            } else if lower.hasSuffix("-medium") {
                tier = "medium"
            } else {
                tier = "high"
            }
            if lower.contains("opus") {
                return "claude-opus-5-5-\(tier)"
            }
            if lower.contains("haiku") {
                return "claude-sonnet-5-5-low"
            }
            return "claude-sonnet-5-5-\(tier)"
        }
        
        switch lower {
        case "gemini-4-argon", "gemini-4-argon-pro", "gemini-4-argon-ultra":
            return "gemini-4-argon-high"
        case "gemini-3.8-pro", "gemini-3.7-pro", "gemini-3.6-pro", "gemini-3.5-pro",
             "gemini-3.1-pro", "gemini-3.1-pro-preview", "gemini-3-pro", "gemini-3-pro-preview", "gemini-2.5-pro":
            return "gemini-4-argon-medium"
        case "gemini-3.8-flash", "gemini-3.8-flash-tiered":
            return "gemini-3.8-flash-high"
        case "gemini-3.7-flash", "gemini-3.6-flash", "gemini-3.5-flash", "gemini-3-flash", "gemini-3-flash-preview", "gemini-2.5-flash":
            return "gemini-3.8-flash-medium"
        case "gemini-3.5-flash-lite", "gemini-3.1-flash-lite", "gemini-3.1-flash-lite-preview", "gemini-2.5-flash-lite":
            return "gemini-3.8-flash-low"
        default:
            if lower.contains("argon") || lower.contains("pro") {
                return "gemini-4-argon-medium"
            }
            return "gemini-3.8-flash-low"
        }
    }
    
    /// Sanitizes MicroCode catalog model IDs into valid `@google/gemini-cli` (`-m`) model aliases
    nonisolated static func sanitizeGeminiCLIModel(_ rawModel: String?) -> String? {
        guard let raw = rawModel?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        let exactSupported: Set<String> = [
            "gemini-2.5-pro",
            "gemini-2.5-flash",
            "gemini-2.5-flash-lite",
            "gemini-3-pro-preview",
            "gemini-3-flash-preview",
            "gemini-3.1-pro-preview",
            "gemini-3.1-pro-preview-customtools",
            "gemini-3.1-flash-lite",
            "gemini-3.1-flash-lite-preview",
            "gemini-3.5-flash",
            "gemini-3.5-flash-lite",
            "gemini-3.8-flash",
            "gemma-4-31b-it",
            "gemma-4-26b-a4b-it"
        ]
        if exactSupported.contains(lower) {
            return lower
        }
        if lower == "gemini-3.1-pro" {
            return "gemini-3.1-pro-preview"
        }
        if lower == "gemini-3-pro" {
            return "gemini-3-pro-preview"
        }
        if lower == "gemini-3-flash" {
            return "gemini-3-flash-preview"
        }
        if lower.hasPrefix("gemini-3.8-flash") {
            return "gemini-3.8-flash"
        }
        if lower.contains("flash-lite") {
            return "gemini-2.5-flash-lite"
        }
        if lower.contains("flash") {
            return "gemini-2.5-flash"
        }
        // Map AGY-exclusive (`gemini-4-argon*`) or non-Gemini leftover IDs to Gemini CLI's flagship default
        return "gemini-2.5-pro"
    }
    
    /// Disables broken or unauthenticated `mcp-remote` OAuth MCP entries in AGY's `mcp_config.json`
    /// before headless print-mode execution so `agy --print` never pops up surprise browser OAuth tabs
    /// (e.g. `canva.com` via `npx mcp-remote`) or stalls indefinitely at `Agent is preparing response...`.
    nonisolated static func sanitizeAGYMCPConfigsIfNeeded() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        
        // Check if `mcp-remote` has any completed OAuth token file (`*_tokens.json`) under `~/.mcp-auth`
        let hasMcpRemoteToken: Bool = {
            let authDir = home.appendingPathComponent(".mcp-auth")
            guard let enumerator = fm.enumerator(at: authDir, includingPropertiesForKeys: nil) else {
                return false
            }
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent.hasSuffix("_tokens.json") {
                    return true
                }
            }
            return false
        }()
        
        let configPaths = [
            home.appendingPathComponent(".gemini/config/mcp_config.json"),
            home.appendingPathComponent(".gemini/antigravity/mcp_config.json")
        ]
        
        for configURL in configPaths {
            guard let data = try? Data(contentsOf: configURL),
                  var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  var servers = root["mcpServers"] as? [String: [String: Any]] else {
                continue
            }
            var parked = (root["_disabledMcpServers"] as? [String: [String: Any]]) ?? [:]
            var mutated = false
            for (name, var entry) in Array(servers) {
                // Note: `agy mcp disable` sets `"disabled": true`, which `agy mcp list` shows as disabled,
                // but `agy --print`'s runtime MCP spawner ignores `"disabled": true` unless parked outside `"mcpServers"`.
                let explicitlyDisabled = (entry["disabled"] as? Bool) == true
                let cmd = (entry["command"] as? String) ?? ""
                let args = (entry["args"] as? [String]) ?? []
                let serverUrl = (entry["serverUrl"] as? String) ?? ""
                let envDict = (entry["env"] as? [String: String]) ?? [:]
                
                // 1. Unauthenticated `mcp-remote` entries trigger interactive browser OAuth popups and block headless stdio forever
                let usesMcpRemote = cmd.contains("mcp-remote") || args.contains(where: { $0.contains("mcp-remote") })
                let shouldDisableMcpRemote = usesMcpRemote && !hasMcpRemoteToken
                
                // 2. Placeholder template credentials (e.g. `xoxb-YOUR_SLACK_BOT_TOKEN`)
                let hasPlaceholderEnv = envDict.values.contains { val in
                    let upper = val.uppercased()
                    return upper.contains("YOUR_SLACK_")
                        || upper.contains("YOUR_API_KEY")
                        || upper.contains("YOUR_TOKEN")
                        || upper.hasPrefix("<YOUR_")
                }
                
                // 3. Unexpanded `${...}` URL template variables (e.g. `https://dataproc-${REGION}.googleapis.com/mcp`)
                let hasUnexpandedUrlVar = serverUrl.contains("${")
                
                // 4. Missing absolute script/executable paths on disk (e.g. removed IDE extension `mcp_proxy_bundle.js`)
                let hasMissingAbsoluteFile: Bool = {
                    if cmd.hasPrefix("/") && !fm.fileExists(atPath: cmd) {
                        return true
                    }
                    for arg in args where arg.hasPrefix("/") && !arg.contains("=") {
                        if !fm.fileExists(atPath: arg) {
                            return true
                        }
                    }
                    return false
                }()
                
                if explicitlyDisabled || shouldDisableMcpRemote || hasPlaceholderEnv || hasUnexpandedUrlVar || hasMissingAbsoluteFile {
                    entry["disabled"] = true
                    parked[name] = entry
                    servers.removeValue(forKey: name)
                    mutated = true
                    print("[ACP/AGY] Parked blocking/disabled MCP server '\(name)' into _disabledMcpServers in \(configURL.lastPathComponent)")
                }
            }
            
            if mutated {
                root["mcpServers"] = servers
                root["_disabledMcpServers"] = parked
                if let outData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
                    try? outData.write(to: configURL, options: .atomic)
                }
            }
        }
    }
    
    /// Returns the `agy` executable path when `.geminiCLI` would fail due to deprecated personal OAuth (`IneligibleTierError`)
    /// or when an AGY-exclusive model (`gemini-4-argon*`) is requested without direct Gemini API credentials.
    nonisolated static func resolveAGYBridgePathIfNeeded(requestedModel: String?, configEnv: [String: String]) -> String? {
        let procEnv = ProcessInfo.processInfo.environment
        let storedGeminiKey = (UserDefaults.standard.string(forKey: "gemini_api_key") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDirectGeminiCreds = !storedGeminiKey.isEmpty
            || !(configEnv["GEMINI_API_KEY"] ?? procEnv["GEMINI_API_KEY"] ?? "").isEmpty
            || !(configEnv["GOOGLE_API_KEY"] ?? procEnv["GOOGLE_API_KEY"] ?? "").isEmpty
            || !(configEnv["GOOGLE_CLOUD_PROJECT"] ?? procEnv["GOOGLE_CLOUD_PROJECT"] ?? "").isEmpty
            || !(configEnv["GOOGLE_CLOUD_PROJECT_ID"] ?? procEnv["GOOGLE_CLOUD_PROJECT_ID"] ?? "").isEmpty
            || (configEnv["GOOGLE_GENAI_USE_VERTEXAI"] ?? procEnv["GOOGLE_GENAI_USE_VERTEXAI"]) == "true"
            || (configEnv["GOOGLE_GENAI_USE_VERTEXAI"] ?? procEnv["GOOGLE_GENAI_USE_VERTEXAI"]) == "1"
            || UserDefaults.standard.bool(forKey: "use9RouterForHarnesses")
        
        guard !hasDirectGeminiCreds else {
            return nil
        }
        
        let selectedAuthType: String = {
            let settingsURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".gemini/settings.json")
            guard let data = try? Data(contentsOf: settingsURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ""
            }
            if let sec = json["security"] as? [String: Any],
               let auth = sec["auth"] as? [String: Any],
               let sel = auth["selectedType"] as? String {
                return sel
            }
            return (json["selectedAuthType"] as? String) ?? ""
        }()
        
        let modelLower = (requestedModel ?? "").lowercased()
        let isAGYExclusiveModel = modelLower.contains("argon")
            || modelLower.hasPrefix("gemini-3.8-flash-")
            || modelLower.hasPrefix("claude-")
            || modelLower.hasPrefix("gpt-oss-")
        
        // Only bridge pre-flight when personal OAuth (deprecated in `@google/gemini-cli`), unconfigured auth, or AGY-exclusive model is active
        if selectedAuthType == "oauth-personal" || selectedAuthType.isEmpty || isAGYExclusiveModel {
            return ACPHostService.resolveExecutablePath("agy")
        }
        return nil
    }
    
    /// Verified active free default model on OpenCode (`opencode run --format json`)
    nonisolated static let fallbackOpenCodeFreeModel = "opencode/mimo-v2.6-flash-free"
    
    /// Retired or broken OpenCode free model slugs that return `Unexpected server error`
    nonisolated static let retiredOpenCodeModels: Set<String> = [
        "opencode/glm-5.3-flash-free",
        "opencode/nemotron-3.5-lightning-free",
        "opencode/ling-3.1-flash-free",
        "opencode/step-5-preview-free",
        "opencode/nemotron-3-ultra-free"
    ]
    
    /// Resolves a valid OpenCode `provider/model` slug, preferring active free models when unauthenticated.
    nonisolated static func resolveOpenCodeModel(
        _ rawModel: String?,
        discoveredModels: [String] = [],
        isAuthenticated: Bool = true
    ) -> String {
        let validDiscovered = discoveredModels.filter { $0.contains("/") && !retiredOpenCodeModels.contains($0.lowercased()) }
        if let raw = rawModel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           raw.contains("/"),
           !retiredOpenCodeModels.contains(raw.lowercased()) {
            if !isAuthenticated && !raw.lowercased().contains("free") {
                if validDiscovered.contains(fallbackOpenCodeFreeModel) {
                    return fallbackOpenCodeFreeModel
                }
                return validDiscovered.first(where: { $0.lowercased().contains("free") }) ?? fallbackOpenCodeFreeModel
            }
            if validDiscovered.isEmpty || validDiscovered.contains(raw) {
                return raw
            }
        }
        if validDiscovered.contains(fallbackOpenCodeFreeModel) {
            return fallbackOpenCodeFreeModel
        }
        if let firstFree = validDiscovered.first(where: { $0.lowercased().contains("free") }) {
            return firstFree
        }
        return validDiscovered.first ?? fallbackOpenCodeFreeModel
    }
    
    /// Build OpenCode CLI arguments
    private func buildOpenCodeArgs(task: String, model: String? = nil, extraArgs: [String]? = nil) -> [String] {
        var args = [
            "run",
            "--format", "json"
        ]
        
        let resolvedModel = Self.resolveOpenCodeModel(model)
        args += ["-m", resolvedModel]
        
        // If continuing an established MicroCode ACP session, resume it:
        if let sid = sessionId, !sid.isEmpty, sid != "opencode", sid != "completed", sid != "unknown" {
            args += ["-s", sid]
        }
        
        let userExtra = extraArgs ?? ACPAgentConfig.stripEffortArguments(config.arguments)
        args += [task]
        args += userExtra.filter { $0 != "--auto" }
        
        return args
    }
    
    /// Build Aider CLI arguments
    private func buildAiderArgs(task: String, extraArgs: [String]? = nil) -> [String] {
        var args = [
            "--no-auto-commits",
            "--no-git"
        ]
        if config.permissionMode == .fullAuto {
            args.append("--yes")
        }
        args += ["--message", task]
        
        // Extra user-defined arguments
        args += (extraArgs ?? ACPAgentConfig.stripEffortArguments(config.arguments))
        
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
        let effectiveType: ACPAgentType = activeTurnUsesAGYBridge ? .agy : config.type
        let frameType = json["type"] as? String ?? ""
        var parsedEvents: [ACPStreamEvent] = []
        switch effectiveType {
        case .claudeCode:
            parsedEvents = ClaudeCodeStreamParser.parseAll(
                json,
                includeAssistantTextAndThinking: !didReceiveClaudeStreamDelta
            )
            if frameType == "stream_event" {
                for ev in parsedEvents {
                    if case .text(let t) = ev, !t.isEmpty { didReceiveClaudeStreamDelta = true }
                    if case .thinking(let th) = ev, !th.isEmpty { didReceiveClaudeStreamDelta = true }
                }
            } else if frameType == "assistant" || frameType == "user" {
                if parsedEvents.contains(where: {
                    if case .toolCall = $0 { return true }
                    if case .toolResult = $0 { return true }
                    return false
                }) {
                    didReceiveClaudeStreamDelta = false
                }
            }
        case .agy:
            if let ev = AGYStreamParser.parse(json) { parsedEvents = [ev] }
        case .geminiCLI:
            if let ev = GeminiCLIStreamParser.parse(json) ?? AGYStreamParser.parse(json) {
                parsedEvents = [ev]
            }
        case .openCode:
            if let ev = OpenCodeStreamParser.parse(json) { parsedEvents = [ev] }
        case .codexEngine:
            if let ev = CodexStreamParser.parse(json) { parsedEvents = [ev] }
        default:
            let claudeEvs = ClaudeCodeStreamParser.parseAll(
                json,
                includeAssistantTextAndThinking: !didReceiveClaudeStreamDelta
            )
            if !claudeEvs.isEmpty {
                parsedEvents = claudeEvs
                if frameType == "stream_event" {
                    for ev in claudeEvs {
                        if case .text(let t) = ev, !t.isEmpty { didReceiveClaudeStreamDelta = true }
                        if case .thinking(let th) = ev, !th.isEmpty { didReceiveClaudeStreamDelta = true }
                    }
                }
            } else if let ev = GeminiCLIStreamParser.parse(json) ?? AGYStreamParser.parse(json) ?? OpenCodeStreamParser.parse(json) {
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
        let agentTypes: [ACPAgentType] = [
            .claudeCode, .agy, .openCode, .codexEngine,
            .geminiCLI, .cursorAgent, .githubCopilot,
            .goose, .cline, .qwenCode, .aider, .zedEngine
        ]
        
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
    
    /// Resolves the genuine headless AI CLI binary for a given `ACPAgentType`,
    /// avoiding false positives like GUI editor launchers (`/Users/.../zed`) or bare `gh` without Copilot CLI installed.
    nonisolated static func resolveAgentBinary(for type: ACPAgentType) -> String? {
        switch type {
        case .githubCopilot:
            if let standalone = resolveExecutablePath("copilot") {
                return standalone
            }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            for ghManaged in [
                "\(home)/.local/share/gh/copilot/copilot",
                "\(home)/.local/share/gh/copilot"
            ] {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: ghManaged, isDirectory: &isDir),
                   !isDir.boolValue,
                   FileManager.default.isExecutableFile(atPath: ghManaged) {
                    return ghManaged
                }
            }
            return nil
        case .zedEngine:
            // Standard `zed` CLI only opens files in Zed.app GUI and rejects `--model`.
            // Only detect if a true ACP server binary is installed.
            return resolveExecutablePath("zed-acp")
        case .custom:
            return nil
        default:
            let command = type.defaultCommand
            guard !command.isEmpty else { return nil }
            return resolveExecutablePath(command)
        }
    }
    
    /// Detect a single agent type
    private func detectAgent(_ type: ACPAgentType) {
        if let path = Self.resolveAgentBinary(for: type) {
            detectedAgents[type] = path
            print("[ACP] Detected \(type.displayName) at \(path)")
            if let existingIdx = registeredConfigs.firstIndex(where: { $0.type == type }) {
                var didMutate = false
                let existingCmd = registeredConfigs[existingIdx].command
                if !FileManager.default.isExecutableFile(atPath: existingCmd) || existingCmd.contains(".plugin-appserver/codex-cli") {
                    registeredConfigs[existingIdx].command = path
                    didMutate = true
                }
                if !type.supportsEffortFlag {
                    let stripped = ACPAgentConfig.stripEffortArguments(registeredConfigs[existingIdx].arguments)
                    if stripped != registeredConfigs[existingIdx].arguments {
                        registeredConfigs[existingIdx].arguments = stripped
                        didMutate = true
                    }
                }
                if didMutate {
                    sessions[registeredConfigs[existingIdx].id]?.syncConfig(registeredConfigs[existingIdx])
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
        var sanitized = config
        if !sanitized.type.supportsEffortFlag {
            sanitized.arguments = ACPAgentConfig.stripEffortArguments(sanitized.arguments)
        }
        if let idx = registeredConfigs.firstIndex(where: { $0.id == sanitized.id }) {
            registeredConfigs[idx] = sanitized
        } else {
            registeredConfigs.append(sanitized)
        }
        sessions[sanitized.id]?.syncConfig(sanitized)
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
            var args = ACPAgentConfig.stripEffortArguments(updated.arguments)
            if type.supportsEffortFlag,
               let effort = effort, !effort.isEmpty, effort.lowercased() != "agent default" {
                args += ["--effort", effort.lowercased()]
            }
            updated.arguments = args
            registerAgent(updated)
            activeAgentId = updated.id
            return updated
        }
        
        // Create new config
        var config = ACPAgentConfig.defaultConfig(for: type, command: path)
        if type.supportsEffortFlag,
           let effort = effort, !effort.isEmpty, effort.lowercased() != "agent default" {
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
            existing.syncConfig(config)
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
            var didHeal = false
            let beforeCount = configs.count
            // Purge false-positive auto-detected GUI launchers (`zed`) or bare `gh` when Copilot CLI is absent
            configs.removeAll { cfg in
                let base = URL(fileURLWithPath: cfg.command).lastPathComponent
                if cfg.type == .zedEngine && base == "zed" {
                    return true
                }
                if cfg.type == .githubCopilot && base == "gh" && Self.resolveAgentBinary(for: .githubCopilot) == nil {
                    return true
                }
                return false
            }
            if configs.count != beforeCount {
                didHeal = true
            }
            for i in configs.indices {
                if (!FileManager.default.isExecutableFile(atPath: configs[i].command) || configs[i].command.contains(".plugin-appserver/codex-cli")),
                   let healed = Self.resolveAgentBinary(for: configs[i].type) {
                    configs[i].command = healed
                    didHeal = true
                }
                if !configs[i].type.supportsEffortFlag {
                    let stripped = ACPAgentConfig.stripEffortArguments(configs[i].arguments)
                    if stripped != configs[i].arguments {
                        configs[i].arguments = stripped
                        didHeal = true
                    }
                }
            }
            registeredConfigs = configs
            if didHeal {
                saveConfigs()
            }
        }
    }
}
