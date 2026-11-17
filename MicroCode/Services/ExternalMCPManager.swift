//
//  ExternalMCPManager.swift
//  MicroCode
//
//  Multi-server MCP Client Manager — auto-launches discovered external MCP servers
//  from .cursor/mcp.json, .mcp.json, or ~/.cursor/mcp.json and registers their
//  tools into AgentToolBox for seamless AI agent use.
//

import Foundation

// MARK: - External MCP Server Connection

@MainActor
class ExternalMCPConnection: ObservableObject, Identifiable {
    let id: String
    let serverName: String
    let command: String
    let args: [String]
    let env: [String: String]
    let source: String
    let remoteURL: String?
    var customHeaders: [String: String]
    /// Declared by a config file inside the workspace (repo-controlled): never receives ambient credentials.
    let isWorkspaceScoped: Bool
    private var mcpSessionId: String? = nil
    /// Protocol revision agreed in `initialize`; sent as `MCP-Protocol-Version` on later HTTP requests.
    private(set) var negotiatedProtocolVersion: String?
    /// Incremented per spawned process so a dying process's termination handler can't tear down its successor.
    private var processGeneration = 0
    
    @Published var isConnected = false
    @Published private(set) var isHandshakeReady = false
    @Published var availableTools: [MCPClient.MCPToolSchema] = []
    @Published var error: String? = nil
    @Published var callCount: Int = 0
    @Published var errorCount: Int = 0
    @Published var avgLatencyMs: Int = 0
    @Published var autoRestartCount: Int = 0
    
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stdoutBuffer = Data()
    private var pendingRequests: [Int: (Result<Any, Error>) -> Void] = [:]
    private var requestIdCounter = 1
    private var manuallyStopped = false
    private var isStarting = false
    private var readCache: [String: (output: String, timestamp: Date)] = [:]
    
    init(server: DiscoveredMCPServer) {
        self.id = server.id
        self.serverName = server.name
        self.command = server.command
        self.args = server.args
        self.env = server.env
        self.source = server.sourcePlatform
        self.remoteURL = server.url ?? ((server.command.hasPrefix("http://") || server.command.hasPrefix("https://")) ? server.command : nil)
        self.customHeaders = server.headers
        self.isWorkspaceScoped = server.isWorkspaceScoped
    }

    /// `initialize` params shared by stdio and HTTP transports.
    private static let initializeParams: [String: Any] = [
        "protocolVersion": MCPProtocolSupport.latestHandshakeVersion,
        "capabilities": ["roots": ["listChanged": false]],
        "clientInfo": ["name": "MicroCode-HyperMesh", "version": MCPProtocolSupport.serverVersion]
    ]

    private func recordNegotiatedVersion(_ result: Any) {
        let version = (result as? [String: Any])?["protocolVersion"] as? String
        negotiatedProtocolVersion = version
        if let version, !MCPProtocolSupport.supportedVersions.contains(version) {
            print("[ExternalMCP:\(serverName)] ⚠️ server negotiated unsupported protocol version \(version); continuing best-effort")
        }
    }
    
    // MARK: - Lifecycle
    
    func start() {
        guard !isConnected && !isStarting else { return }
        manuallyStopped = false
        isStarting = true
        isHandshakeReady = false
        
        if let httpURL = remoteURL, !httpURL.isEmpty {
            error = nil
            sendRequest(method: "initialize", params: Self.initializeParams) { [weak self] result in
                switch result {
                case .success(let initResult):
                    self?.recordNegotiatedVersion(initResult)
                    self?.isStarting = false
                    self?.isConnected = true
                    self?.isHandshakeReady = true
                    self?.sendNotification(method: "notifications/initialized")
                    self?.fetchTools()
                    print("[ExternalMCP:\(self?.serverName ?? "?")] HTTP Initialized (\(httpURL))")
                case .failure(let err):
                    self?.isStarting = false
                    self?.error = "HTTP Init failed: \(err.localizedDescription)"
                    self?.isConnected = false
                    self?.isHandshakeReady = false
                }
            }
            return
        }
        
        let process = Process()
        
        // Resolve command path (prioritizing MicroCode Portable Runtimes)
        let commandPath = resolveCommand(command)
        guard let execPath = commandPath else {
            isStarting = false
            error = "Command not found: \(command)"
            print("[ExternalMCP:\(serverName)] Command not found: \(command)")
            return
        }
        
        process.executableURL = URL(fileURLWithPath: execPath)
        process.arguments = args
        
        // Merge environment + MicroCode Portable Runtime PATH
        var processEnv = ProcessInfo.processInfo.environment
        processEnv.removeValue(forKey: "MICROCODE_LOCAL_API_TOKEN")
        processEnv.removeValue(forKey: "MICROCODE_BRIDGE_TOKEN")
        let runtimeBins = RuntimeManager.shared.allRuntimeBinDirectories()
        let currentPath = processEnv["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        processEnv["PATH"] = (runtimeBins + ["/opt/homebrew/bin", "/usr/local/bin", currentPath]).joined(separator: ":")
        for (key, value) in env {
            processEnv[key] = value
        }
        process.environment = processEnv
        
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        
        self.process = process
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stdoutBuffer.removeAll(keepingCapacity: true)
        
        // Handle stdout (JSON-RPC responses)
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async {
                self?.handleOutput(data)
            }
        }
        
        // Handle stderr (debug/error logs)
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let str = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                print("[ExternalMCP:\(self?.serverName ?? "?")] stderr: \(str.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        
        // Handle process termination + Autonomous Self-Healing Restart
        processGeneration += 1
        let generation = processGeneration
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                // A restart already spawned a newer process: this stale exit must not clear its state,
                // fail its pending initialize, or trigger another auto-restart.
                guard let self, generation == self.processGeneration else { return }
                self.isStarting = false
                self.isConnected = false
                self.isHandshakeReady = false
                self.availableTools = []
                let crashErr = NSError(
                    domain: "ExternalMCP",
                    code: Int(proc.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "MCP server '\(self.serverName)' terminated (exit \(proc.terminationStatus))"]
                )
                let callbacks = self.pendingRequests.values
                self.pendingRequests.removeAll()
                callbacks.forEach { $0(.failure(crashErr)) }
                print("[ExternalMCP:\(self.serverName)] Process terminated (code \(proc.terminationStatus))")
                
                // Auto-heal if unexpected termination (up to 3 retries with exponential backoff)
                if !self.manuallyStopped && proc.terminationStatus != 0 && self.autoRestartCount < 3 {
                    self.autoRestartCount += 1
                    let backoffSeconds = Double(1 << self.autoRestartCount)
                    self.error = "Self-healing restart #\(self.autoRestartCount) in \(Int(backoffSeconds))s..."
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                        guard let self, !self.manuallyStopped else { return }
                        self.start()
                    }
                }
            }
        }
        
        do {
            try process.run()
            error = nil
            print("[ExternalMCP:\(serverName)] Started: \(execPath) \(args.joined(separator: " "))")
            
            // Initialize MCP protocol (offers 2025-11-25; accepts any revision the server negotiates down to)
            sendRequest(method: "initialize", params: Self.initializeParams) { [weak self] result in
                switch result {
                case .success(let initResult):
                    self?.recordNegotiatedVersion(initResult)
                    self?.isStarting = false
                    self?.isConnected = true
                    self?.isHandshakeReady = true
                    self?.sendNotification(method: "notifications/initialized")
                    self?.fetchTools()
                    print("[ExternalMCP:\(self?.serverName ?? "?")] Initialized")
                case .failure(let err):
                    self?.isStarting = false
                    self?.isConnected = false
                    self?.isHandshakeReady = false
                    self?.error = "Init failed: \(err.localizedDescription)"
                    print("[ExternalMCP:\(self?.serverName ?? "?")] Init error: \(err)")
                }
            }
        } catch {
            self.isStarting = false
            self.error = "Failed to start: \(error.localizedDescription)"
            self.isConnected = false
            self.isHandshakeReady = false
            print("[ExternalMCP:\(serverName)] Failed to start: \(error)")
        }
    }
    
    func stop() {
        manuallyStopped = true
        isStarting = false
        isHandshakeReady = false
        let shutdownError = NSError(domain: "ExternalMCP", code: -2, userInfo: [NSLocalizedDescriptionKey: "Connection closed"])
        let callbacks = pendingRequests.values
        pendingRequests.removeAll()
        callbacks.forEach { $0(.failure(shutdownError)) }
        
        // Graceful stdio shutdown: close stdin (servers exit on EOF), SIGTERM, then SIGKILL if still alive,
        // so `npx`-launched servers do not linger. Bumping the generation makes the exit handler a no-op.
        processGeneration += 1
        try? stdinPipe?.fileHandleForWriting.close()
        if let running = process, running.isRunning {
            running.terminate()
            let pid = running.processIdentifier
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
                if running.isRunning { kill(pid, SIGKILL) }
            }
        }
        isConnected = false
        process = nil
        stdinPipe = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        availableTools = []
        stdoutBuffer.removeAll(keepingCapacity: false)
    }

    /// Wakes a dormant/hibernated MCP server on demand and awaits full JSON-RPC `initialize` handshake completion.
    func ensureReadyForCall(timeoutSeconds: TimeInterval = 12.0) async throws {
        if isHandshakeReady && isConnected { return }
        if !isStarting && !isConnected {
            start()
        }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if isHandshakeReady && isConnected { return }
            if !isStarting && !isConnected, let err = error {
                throw NSError(domain: "ExternalMCP", code: -4, userInfo: [NSLocalizedDescriptionKey: "MCP server '\(serverName)' failed to initialize: \(err)"])
            }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        if !isHandshakeReady {
            throw NSError(domain: "ExternalMCP", code: -5, userInfo: [NSLocalizedDescriptionKey: "MCP server '\(serverName)' handshake timed out after \(Int(timeoutSeconds))s"])
        }
    }
    
    // MARK: - Tool Calling (with Telemetry & Read Cache)
    
    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        try await ensureReadyForCall(timeoutSeconds: 12.0)
        
        // Check 3s read-only cache for idempotent inspection calls
        let lower = name.lowercased()
        let isReadOnly = lower.hasPrefix("get_") || lower.hasPrefix("list_") || lower.hasPrefix("read_") || lower.hasPrefix("search_")
        let cacheKey: String? = isReadOnly ? "\(name):\(String(describing: arguments))" : nil
        if let key = cacheKey, let cached = readCache[key], Date().timeIntervalSince(cached.timestamp) < 3.0 {
            return cached.output
        }
        
        let startedAt = Date()
        callCount += 1
        
        do {
            let output: String = try await withCheckedThrowingContinuation { continuation in
                let params: [String: Any] = [
                    "name": name,
                    "arguments": arguments
                ]
                
                sendRequest(method: "tools/call", params: params, timeout: 60) { result in
                    switch result {
                    case .success(let res):
                        if let dict = res as? [String: Any],
                           let isError = dict["isError"] as? Bool, isError {
                            let content = (dict["content"] as? [[String: Any]])?.first?["text"] as? String ?? "Unknown error"
                            continuation.resume(throwing: NSError(domain: "ExternalMCP", code: -1, userInfo: [NSLocalizedDescriptionKey: content]))
                        } else if let dict = res as? [String: Any],
                                  let contentArray = dict["content"] as? [[String: Any]] {
                            let texts = contentArray.compactMap { $0["text"] as? String }
                            continuation.resume(returning: texts.isEmpty ? "Success" : texts.joined(separator: "\n"))
                        } else {
                            continuation.resume(returning: "Success")
                        }
                    case .failure(let err):
                        continuation.resume(throwing: err)
                    }
                }
            }
            
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            avgLatencyMs = avgLatencyMs == 0 ? elapsedMs : ((avgLatencyMs * 3 + elapsedMs) / 4)
            if let key = cacheKey {
                readCache[key] = (output, Date())
            }
            let tract = PNSGanglionRouter.classifyMCPTract(serverName: serverName, toolName: name)
            PNSGanglionRouter.shared.recordMCPImpulse(serverName: serverName, tract: tract)
            PNSOrchestrator.shared.recordSynapticFeedback(
                taskPrompt: "\(serverName) \(name)",
                tract: tract,
                targetNodeId: "mcp__\(serverName)__\(name)",
                projectPath: AgentToolBox.shared.effectiveWorkspaceRoot,
                succeeded: true,
                tokensUsed: max(60, output.count / 4),
                latencyMs: elapsedMs
            )
            return output
        } catch {
            errorCount += 1
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let tract = PNSGanglionRouter.classifyMCPTract(serverName: serverName, toolName: name)
            PNSOrchestrator.shared.recordSynapticFeedback(
                taskPrompt: "\(serverName) \(name)",
                tract: tract,
                targetNodeId: "mcp__\(serverName)__\(name)",
                projectPath: AgentToolBox.shared.effectiveWorkspaceRoot,
                succeeded: false,
                tokensUsed: 80,
                latencyMs: elapsedMs,
                regressionPenalty: 1.2
            )
            _ = PNSGanglionRouter.shared.evaluateSpinalReflex(
                toolOrProviderName: "mcp__\(serverName)__\(name)",
                targetHint: serverName,
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }
    
    // MARK: - Private JSON-RPC
    
    private func handleOutput(_ data: Data) {
        stdoutBuffer.append(data)
        
        while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer.subdata(in: 0..<newlineIndex)
            stdoutBuffer.removeSubrange(0...newlineIndex)
            
            var line = String(decoding: lineData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("data:") {
                line = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !line.isEmpty,
                  line != "[DONE]",
                  let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }
            
            // Server-to-client messages: requests carry an id and MUST be answered; notifications carry none.
            if let method = json["method"] as? String {
                if let reqId = json["id"] {
                    switch method {
                    case "ping":
                        sendRaw(["jsonrpc": "2.0", "id": reqId, "result": [:] as [String: Any]])
                    case "roots/list":
                        let ws = AppState.shared?.workspaceFolder?.path ?? AppState.shared?.activeTerminalDirectory ?? FileManager.default.currentDirectoryPath
                        let rootURI = URL(fileURLWithPath: ws).absoluteString
                        sendRaw([
                            "jsonrpc": "2.0",
                            "id": reqId,
                            "result": ["roots": [["uri": rootURI, "name": URL(fileURLWithPath: ws).lastPathComponent]]]
                        ])
                    default:
                        // sampling/createMessage, elicitation/create, ...: not supported. Answer instead of
                        // leaving the server blocked until its own timeout.
                        sendRaw([
                            "jsonrpc": "2.0",
                            "id": reqId,
                            "error": ["code": -32601, "message": "Method not supported by MicroCode client: \(method)"]
                        ])
                    }
                } else if method == "notifications/tools/list_changed" {
                    fetchTools()
                }
                continue
            }
            
            let resolvedId: Int? = (json["id"] as? Int) ?? (json["id"] as? String).flatMap { Int($0) }
            if let id = resolvedId, let callback = pendingRequests.removeValue(forKey: id) {
                if let error = json["error"] as? [String: Any] {
                    let msg = error["message"] as? String ?? "Unknown error"
                    callback(.failure(NSError(domain: "ExternalMCP", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])))
                } else if let result = json["result"] {
                    callback(.success(result))
                } else {
                    callback(.success([:] as [String: Any]))
                }
            }
        }
    }
    
    private func sendRequest(method: String, params: [String: Any] = [:], timeout: TimeInterval = 30, completion: @escaping (Result<Any, Error>) -> Void) {
        let reqId = requestIdCounter
        requestIdCounter += 1
        pendingRequests[reqId] = completion
        
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": reqId,
            "method": method,
            "params": params
        ]
        sendRaw(request, timeout: timeout + 5)
        
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard let self, let callback = self.pendingRequests.removeValue(forKey: reqId) else { return }
            callback(.failure(NSError(
                domain: "ExternalMCP",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Request '\(method)' timed out after \(Int(timeout))s"]
            )))
        }
    }
    
    private func sendNotification(method: String, params: [String: Any] = [:]) {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        sendRaw(request)
    }
    
    private func resolvedAuthHeaderValue() -> String? {
        if let h = customHeaders.first(where: { $0.key.caseInsensitiveCompare("Authorization") == .orderedSame })?.value, !h.isEmpty {
            return h
        }
        let savedToken = UserDefaults.standard.string(forKey: "microcode.mcp.bearer.\(serverName.lowercased())") ?? ""
        if !savedToken.isEmpty {
            return savedToken.lowercased().hasPrefix("bearer ") ? savedToken : "Bearer \(savedToken)"
        }
        let upperName = serverName.uppercased().replacingOccurrences(of: "-", with: "_")
        // Generic names come only from this server's own declared env: MicroCode's process-wide
        // AUTHORIZATION / BEARER_TOKEN / MCP_TOKEN must never be sent to every remote server.
        let genericKeys = ["AUTHORIZATION", "MCP_BEARER_TOKEN", "BEARER_TOKEN", "MCP_TOKEN"]
        let namedKeys = ["\(upperName)_ACCESS_TOKEN", "\(upperName)_API_KEY", "\(upperName)_TOKEN"]
        for k in genericKeys + namedKeys {
            // Ambient (process) env only for name-specific keys of user-level servers, never repo-declared ones.
            let ambient = (namedKeys.contains(k) && !isWorkspaceScoped) ? ProcessInfo.processInfo.environment[k] : nil
            if let v = env[k] ?? ambient, !v.isEmpty, !v.hasPrefix("YOUR_") {
                return v.lowercased().hasPrefix("bearer ") ? v : "Bearer \(v)"
            }
        }
        return nil
    }

    private func sendRaw(_ obj: [String: Any], timeout: TimeInterval = 35) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        if let httpURL = remoteURL, let url = URL(string: httpURL) {
            // Matches the JSON-RPC request timeout (a fixed 12 s cut off slow tools/call requests allowed 60 s).
            var req = URLRequest(url: url, timeoutInterval: timeout)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            if let sid = mcpSessionId, !sid.isEmpty {
                req.setValue(sid, forHTTPHeaderField: "Mcp-Session-Id")
            }
            if let version = negotiatedProtocolVersion {
                req.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version")
            }
            for (hk, hv) in customHeaders where hk.caseInsensitiveCompare("Authorization") != .orderedSame {
                req.setValue(hv, forHTTPHeaderField: hk)
            }
            if let authVal = resolvedAuthHeaderValue() {
                req.setValue(authVal, forHTTPHeaderField: "Authorization")
            }
            req.httpBody = data
            URLSession.shared.dataTask(with: req) { [weak self] respData, urlResp, err in
                guard let self else { return }
                if let httpResp = urlResp as? HTTPURLResponse {
                    if let newSid = httpResp.value(forHTTPHeaderField: "Mcp-Session-Id") ?? httpResp.value(forHTTPHeaderField: "mcp-session-id"), !newSid.isEmpty {
                        DispatchQueue.main.async { self.mcpSessionId = newSid }
                    }
                    if httpResp.statusCode == 401 || httpResp.statusCode == 403 {
                        let wwwAuth = httpResp.value(forHTTPHeaderField: "WWW-Authenticate") ?? "OAuth 2.1 / Bearer token"
                        let authErr = NSError(
                            domain: "ExternalMCP",
                            code: httpResp.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "AUTH_REQUIRED (HTTP \(httpResp.statusCode) at \(httpURL) — \(wwwAuth)). Provide a Bearer token via `mcp_orchestrator(action: \"connect\", server_name: \"\(self.serverName)\", bearer_token: \"...\")` or Settings → MCP Servers."]
                        )
                        DispatchQueue.main.async {
                            self.error = authErr.localizedDescription
                            if let reqId = obj["id"] as? Int, let cb = self.pendingRequests.removeValue(forKey: reqId) {
                                cb(.failure(authErr))
                            }
                        }
                        return
                    }
                    if httpResp.statusCode >= 400 {
                        let preview = respData.flatMap { String(data: $0, encoding: .utf8) }?.prefix(200) ?? ""
                        let httpErr = NSError(
                            domain: "ExternalMCP",
                            code: httpResp.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResp.statusCode) from \(httpURL): \(preview)"]
                        )
                        DispatchQueue.main.async {
                            if let reqId = obj["id"] as? Int, let cb = self.pendingRequests.removeValue(forKey: reqId) {
                                cb(.failure(httpErr))
                            }
                        }
                        return
                    }
                }
                if let respData = respData, !respData.isEmpty {
                    var newlineData = respData
                    if newlineData.last != 0x0A { newlineData.append(0x0A) }
                    DispatchQueue.main.async {
                        self.handleOutput(newlineData)
                    }
                } else if let err = err, let reqId = obj["id"] as? Int {
                    DispatchQueue.main.async {
                        if let cb = self.pendingRequests.removeValue(forKey: reqId) {
                            cb(.failure(err))
                        }
                    }
                } else if let reqId = obj["id"] as? Int {
                    // Empty 202/204 response
                    DispatchQueue.main.async {
                        if let cb = self.pendingRequests.removeValue(forKey: reqId) {
                            cb(.success([:] as [String: Any]))
                        }
                    }
                }
            }.resume()
            return
        }
        guard let pipe = stdinPipe else { return }
        var d = data
        d.append("\n".data(using: .utf8)!)
        try? pipe.fileHandleForWriting.write(contentsOf: d)
    }
    
    private func fetchTools() {
        sendRequest(method: "tools/list") { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let res):
                if let dict = res as? [String: Any],
                   let toolsList = dict["tools"] as? [[String: Any]] {
                    var parsedTools: [MCPClient.MCPToolSchema] = []
                    for t in toolsList {
                        if let name = t["name"] as? String {
                            let desc = t["description"] as? String ?? ""
                            let schema = t["inputSchema"] as? [String: Any] ?? ["type": "object", "properties": [:]]
                            if let schemaData = try? JSONSerialization.data(withJSONObject: schema),
                               let parsedSchema = try? JSONDecoder().decode([String: AnyCodable].self, from: schemaData) {
                                parsedTools.append(MCPClient.MCPToolSchema(name: name, description: desc, inputSchema: parsedSchema))
                            }
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.availableTools = parsedTools
                        self.registerToolsWithAgent()
                        ExternalMCPManager.shared.refreshToolCountNow()
                        PNSGanglionRouter.shared.syncManifestsFromExternalMCP()
                    }
                }
            case .failure(let err):
                print("[ExternalMCP:\(self.serverName)] Fetch tools error: \(err)")
            }
        }
    }
    
    private func registerToolsWithAgent() {
        registerToolSchemas(availableTools)
    }

    func registerCachedToolsIfNeeded(_ schemas: [MCPClient.MCPToolSchema]) {
        registerToolSchemas(schemas)
    }

    private func registerToolSchemas(_ schemas: [MCPClient.MCPToolSchema]) {
        for schema in schemas {
            let namespacedName = "mcp__\(serverName)__\(schema.name)"
            let proxyTool = ExternalMCPTool(connection: self, schema: schema, serverName: serverName)
            AgentToolBox.shared.register(proxyTool)
            _ = namespacedName
        }
    }
    
    // MARK: - Command Resolution (MicroCode Portable Runtime First)
    
    private func resolveCommand(_ cmd: String) -> String? {
        if cmd.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: cmd) {
            return cmd
        }
        
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let runtimesRoot = RuntimeManager.shared.runtimesDir.path
        
        // Search MicroCode Portable Runtimes first, then standard system & version manager paths
        let searchPaths = [
            "\(runtimesRoot)/node/bin",
            "\(runtimesRoot)/python/bin",
            "\(runtimesRoot)/go/bin",
            "\(runtimesRoot)/rust/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.cargo/bin"
        ]
        
        for dir in searchPaths {
            let path = (dir as NSString).appendingPathComponent(cmd)
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        // Try nvm node directories
        if cmd == "npx" || cmd == "node" {
            let nvmDir = "\(home)/.nvm/versions/node"
            if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
                for version in versions.sorted().reversed() {
                    let path = "\(nvmDir)/\(version)/bin/\(cmd)"
                    if FileManager.default.isExecutableFile(atPath: path) {
                        return path
                    }
                }
            }
        }
        
        // Use `which` with augmented PATH as fallback
        let whichProcess = Process()
        let whichPipe = Pipe()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = [cmd]
        var env = ProcessInfo.processInfo.environment
        let runtimeBins = RuntimeManager.shared.allRuntimeBinDirectories()
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (runtimeBins + ["/opt/homebrew/bin", "/usr/local/bin", currentPath]).joined(separator: ":")
        whichProcess.environment = env
        whichProcess.standardOutput = whichPipe
        whichProcess.standardError = Pipe()
        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            if whichProcess.terminationStatus == 0 {
                let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                    return path
                }
            }
        } catch {}
        
        return nil
    }
}

// MARK: - External MCP Tool (Agent Tool proxy)

struct ExternalMCPTool: AgentTool {
    let connection: ExternalMCPConnection
    let schema: MCPClient.MCPToolSchema
    let serverName: String
    
    var name: String { "mcp__\(serverName)__\(schema.name)" }
    var description: String { "[\(serverName)] \(schema.description)" }
    
    var parameters: [ToolParameter] {
        var params: [ToolParameter] = []
        if let properties = schema.inputSchema["properties"]?.value as? [String: Any] {
            let required = schema.inputSchema["required"]?.value as? [String] ?? []
            for (key, val) in properties.sorted(by: { $0.key < $1.key }) {
                if let propDict = val as? [String: Any] {
                    let type = propDict["type"] as? String ?? "string"
                    let desc = propDict["description"] as? String ?? ""
                    params.append(ToolParameter(name: key, type: type, description: desc, required: required.contains(key)))
                }
            }
        }
        return params
    }

    var rawParametersSchema: [String: Any]? {
        var unwrapped = AnyCodable.unwrapJSONObject(schema.inputSchema)
        if unwrapped["type"] == nil {
            unwrapped["type"] = "object"
        }
        if (unwrapped["type"] as? String) == "object" && unwrapped["properties"] == nil {
            unwrapped["properties"] = [String: Any]()
        }
        return unwrapped
    }
    
    func execute(params: [String: Any]) async throws -> String {
        try await connection.callTool(name: schema.name, arguments: params)
    }
}

// MARK: - External MCP Manager (Hyper-Mesh Multi-Server Orchestrator)

@MainActor
class ExternalMCPManager: ObservableObject {
    static let shared = ExternalMCPManager()
    
    @Published var connections: [String: ExternalMCPConnection] = [:]
    @Published var totalToolCount: Int = 0
    @Published var explicitlyMountedTools: Set<String> = []
    private var failedProbeServers: Set<String> = []
    private var activeProbeTask: Task<Void, Never>?
    
    private init() {}
    
    /// Discover MCP servers from workspace & IDE config files.
    /// Cached manifests are mounted instantaneously at 0 MB RAM cost; newly discovered servers
    /// without a cached manifest are probed in a bounded background queue (max 2 concurrent) and cached permanently.
    func syncWithDiscoveredServers(_ servers: [DiscoveredMCPServer], autoStart: Bool = false) {
        let currentNames = Set(servers.map(\.name))
        for (name, conn) in connections where !currentNames.contains(name) && conn.source != "Synthesized" {
            conn.stop()
            connections.removeValue(forKey: name)
        }
        
        var uncachedServerNames: [String] = []
        let router = PNSGanglionRouter.shared
        
        for server in servers {
            let conn: ExternalMCPConnection
            if let existing = connections[server.name] {
                conn = existing
            } else {
                let created = ExternalMCPConnection(server: server)
                connections[server.name] = created
                conn = created
            }
            
            if let cached = router.cachedServerManifests[server.name], !cached.isEmpty {
                conn.registerCachedToolsIfNeeded(cached)
                if autoStart {
                    conn.start()
                }
            } else if autoStart {
                conn.start()
            } else if !failedProbeServers.contains(server.name) {
                uncachedServerNames.append(server.name)
            }
        }
        
        router.syncManifestsFromExternalMCP()
        refreshToolCountNow()
        
        if !uncachedServerNames.isEmpty {
            scheduleBackgroundManifestProbe(serverNames: uncachedServerNames, hibernateAfterProbe: !autoStart)
        }
    }

    private func scheduleBackgroundManifestProbe(serverNames: [String], hibernateAfterProbe: Bool) {
        activeProbeTask?.cancel()
        activeProbeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let batchSize = 2
            var idx = 0
            while idx < serverNames.count {
                if Task.isCancelled { return }
                let end = min(idx + batchSize, serverNames.count)
                let slice = Array(serverNames[idx..<end])
                await withTaskGroup(of: Void.self) { group in
                    for name in slice {
                        group.addTask { @MainActor [weak self] in
                            guard let self else { return }
                            await self.probeSingleServer(name: name, hibernateAfterProbe: hibernateAfterProbe, timeoutSeconds: 6.5)
                        }
                    }
                }
                idx = end
            }
            self.refreshToolCountNow()
        }
    }

    private func probeSingleServer(name: String, hibernateAfterProbe: Bool, timeoutSeconds: TimeInterval) async {
        guard let conn = connections[name] else { return }
        if let cached = PNSGanglionRouter.shared.cachedServerManifests[name], !cached.isEmpty {
            conn.registerCachedToolsIfNeeded(cached)
            return
        }
        conn.start()
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled { return }
            if !conn.availableTools.isEmpty { break }
            if !conn.isConnected && conn.error != nil { break }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        if !conn.availableTools.isEmpty {
            let discoveredTools = conn.availableTools
            conn.registerCachedToolsIfNeeded(discoveredTools)
            let shouldHibernate = hibernateAfterProbe && conn.remoteURL == nil && conn.callCount == 0
            if shouldHibernate {
                conn.stop()
            }
            PNSGanglionRouter.shared.cacheManifest(
                serverName: name,
                tools: discoveredTools,
                isHibernated: shouldHibernate
            )
            refreshToolCountNow()
        } else {
            failedProbeServers.insert(name)
            if hibernateAfterProbe && conn.remoteURL == nil && conn.callCount == 0 {
                conn.stop()
            }
        }
    }

    /// Ensures uncached MCP servers (optionally matching a keyword) are probed immediately before `search_tools`.
    func probeServersNowIfNeeded(matching query: String = "") async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidates = connections.keys.filter { name in
            let hasLive = !(connections[name]?.availableTools.isEmpty ?? true)
            let hasCached = !(PNSGanglionRouter.shared.cachedServerManifests[name]?.isEmpty ?? true)
            if hasLive || hasCached || failedProbeServers.contains(name) { return false }
            if q.isEmpty { return true }
            return name.lowercased().contains(q) || true
        }.sorted()
        guard !candidates.isEmpty else { return }
        for name in candidates.prefix(4) {
            await probeSingleServer(name: name, hibernateAfterProbe: true, timeoutSeconds: 4.0)
        }
        refreshToolCountNow()
    }
    
    /// Get all connected server names
    var connectedServerNames: [String] {
        connections.filter(\.value.isConnected).map(\.key).sorted()
    }
    
    /// Get all available tools across both live connected servers and hibernated cached-manifest servers
    var allTools: [(serverName: String, tool: MCPClient.MCPToolSchema)] {
        var tools: [(String, MCPClient.MCPToolSchema)] = []
        let router = PNSGanglionRouter.shared
        for (name, conn) in connections.sorted(by: { $0.key < $1.key }) {
            let effectiveTools = !conn.availableTools.isEmpty
                ? conn.availableTools
                : (router.cachedServerManifests[name] ?? [])
            for tool in effectiveTools {
                tools.append((name, tool))
            }
        }
        return tools
    }
    
    /// PNS Two-Stage Hierarchical Ganglion MCP Router:
    /// Always keeps `mcp__local__*` eager, and routes `MCP_1 ... MCP_xx` through specialized Nerve Tracts
    /// modulated by Hebbian Synaptic Myelination weights (`W_e`) + lazy awakening of hibernated MCP processes.
    func eagerExternalToolNames(forPrompt prompt: String, maxExternalTools: Int = 12) -> Set<String> {
        let ws = AgentToolBox.shared.effectiveWorkspaceRoot
        return PNSGanglionRouter.shared.selectActiveSynapticTools(
            forPrompt: prompt,
            workspacePath: ws,
            allowedTracts: nil,
            maxTools: maxExternalTools,
            synapseLookup: { category, tract, nodeId, proj in
                PNSOrchestrator.shared.lookupSynapse(
                    taskCategory: category,
                    tract: tract,
                    targetNodeId: nodeId,
                    projectPath: proj
                )
            }
        )
    }
    
    /// Autonomous On-The-Fly MCP Server Synthesis:
    /// Generates a standalone Python JSON-RPC 2.0 stdio MCP server in `.microcode/mcp/<name>.py`,
    /// registers it in `.microcode/mcp.json`, hot-spawns it, and exposes its tools in <1.5 seconds.
    func synthesizeServer(
        name: String,
        description: String,
        toolsSpecJSON: String,
        pythonHandlerBody: String,
        workspacePath: String?
    ) async throws -> String {
        let slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        guard !slug.isEmpty else {
            throw NSError(domain: "ExternalMCP", code: -10, userInfo: [NSLocalizedDescriptionKey: "Invalid server name"])
        }
        
        let rootDir: URL
        if let ws = workspacePath, !ws.isEmpty {
            rootDir = WorkspaceStoragePaths.managedStateFile(named: "mcp", workspacePath: ws)
        } else {
            rootDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".microcode/mcp", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        
        let scriptURL = rootDir.appendingPathComponent("\(slug).py")
        let indentedBody = pythonHandlerBody
            .components(separatedBy: "\n")
            .map { "    " + $0 }
            .joined(separator: "\n")
        
        let serverCode = """
        #!/usr/bin/env python3
        # Auto-synthesized by MicroCode Hyper-Mesh MCP Engine 2.0
        # Server: \(slug) — \(description)
        import sys, json, os, subprocess, urllib.request, urllib.parse

        TOOLS = \(toolsSpecJSON)

        def handle_tool_call(name, args):
        \(indentedBody)

        def main():
            for raw in sys.stdin:
                line = raw.strip()
                if not line:
                    continue
                try:
                    req = json.loads(line)
                except Exception:
                    continue
                req_id = req.get("id")
                method = req.get("method", "")
                params = req.get("params") or {}
                if method == "initialize":
                    resp = {
                        "jsonrpc": "2.0",
                        "id": req_id,
                        "result": {
                            "protocolVersion": "2024-11-05",
                            "capabilities": {"tools": {}},
                            "serverInfo": {"name": "\(slug)", "version": "1.0.0"}
                        }
                    }
                    sys.stdout.write(json.dumps(resp) + "\\n")
                    sys.stdout.flush()
                elif method == "tools/list":
                    resp = {"jsonrpc": "2.0", "id": req_id, "result": {"tools": TOOLS}}
                    sys.stdout.write(json.dumps(resp) + "\\n")
                    sys.stdout.flush()
                elif method == "tools/call":
                    tname = params.get("name", "")
                    targs = params.get("arguments") or {}
                    try:
                        out = handle_tool_call(tname, targs)
                        resp = {"jsonrpc": "2.0", "id": req_id, "result": {"content": [{"type": "text", "text": str(out)}]}}
                    except Exception as e:
                        resp = {"jsonrpc": "2.0", "id": req_id, "result": {"content": [{"type": "text", "text": f"Error: {e}"}], "isError": True}}
                    sys.stdout.write(json.dumps(resp) + "\\n")
                    sys.stdout.flush()

        if __name__ == "__main__":
            main()
        """
        
        try serverCode.write(to: scriptURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        
        // Persist into .microcode/mcp.json so future sessions auto-discover it
        let configURL = rootDir.deletingLastPathComponent().appendingPathComponent("mcp.json")
        var configRoot: [String: Any] = [:]
        if let existingData = try? Data(contentsOf: configURL),
           let parsed = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            configRoot = parsed
        }
        var serversDict = configRoot["mcpServers"] as? [String: Any] ?? [:]
        serversDict[slug] = [
            "command": "python3",
            "args": [scriptURL.path]
        ]
        configRoot["mcpServers"] = serversDict
        if let updatedData = try? JSONSerialization.data(withJSONObject: configRoot, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: configURL)
        }
        
        // Hot-spawn connection immediately
        connections[slug]?.stop()
        let discovered = DiscoveredMCPServer(
            name: slug,
            sourcePlatform: "Synthesized",
            command: "python3",
            args: [scriptURL.path],
            env: [:]
        )
        let conn = ExternalMCPConnection(server: discovered)
        connections[slug] = conn
        conn.start()
        
        // Wait up to 1.5s for handshake & tools/list registration
        for _ in 0..<15 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !conn.availableTools.isEmpty { break }
        }
        refreshToolCountNow()
        
        let registeredNames = conn.availableTools.map { "mcp__\(slug)__\($0.name)" }
        for name in registeredNames {
            explicitlyMountedTools.insert(name)
        }
        return """
        ✅ Synthesized & Hot-Mounted MCP Server '\(slug)'
        Script: \(scriptURL.path)
        Config: \(configURL.path)
        Status: \(conn.isConnected ? "Connected" : (conn.error ?? "Starting"))
        Registered Tools (\(registeredNames.count)): \(registeredNames.joined(separator: ", "))
        """
    }
    
    /// Connects or registers a remote Streamable HTTP or local stdio MCP server, saves optional Bearer credentials,
    /// persists to `~/.microcode/mcp.json`, probes tools immediately, and reports companion skills/CLIs.
    func connectOrConfigureServer(
        name rawName: String,
        remoteURL: String? = nil,
        command: String? = nil,
        args: [String] = [],
        bearerToken: String? = nil,
        workspacePath: String? = nil
    ) async -> String {
        let cleanName = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanName.isEmpty else {
            return "Error: `server_name` is required (e.g. 'canva', 'github', 'figma')."
        }

        if let tok = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines), !tok.isEmpty {
            UserDefaults.standard.set(tok, forKey: "microcode.mcp.bearer.\(cleanName)")
        }

        // Trigger fresh plugin/IDE config discovery if server isn't loaded yet
        if connections[cleanName] == nil && (remoteURL ?? "").isEmpty && (command ?? "").isEmpty {
            MultiPlatformRulesEngine.shared.refresh(workspaceRoot: workspacePath ?? AgentToolBox.shared.effectiveWorkspaceRoot ?? NSHomeDirectory())
            try? await Task.sleep(nanoseconds: 350_000_000)
        }

        // Known official Streamable HTTP endpoints for zero-guess 1-click setup when user says "เชื่อม Canva MCP"
        var effectiveURL = remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        if (effectiveURL == nil || effectiveURL!.isEmpty), connections[cleanName] == nil, (command ?? "").isEmpty {
            let officialEndpoints: [String: String] = [
                "canva": "https://mcp.canva.com/mcp",
                "figma": "https://mcp.figma.com/mcp",
                "linear": "https://mcp.linear.app/mcp"
            ]
            effectiveURL = officialEndpoints[cleanName]
        }

        if let urlStr = effectiveURL, !urlStr.isEmpty {
            let globalMCP = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".microcode/mcp.json")
            try? FileManager.default.createDirectory(at: globalMCP.deletingLastPathComponent(), withIntermediateDirectories: true)
            var rootObj: [String: Any] = [:]
            if let d = try? Data(contentsOf: globalMCP),
               let parsed = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                rootObj = parsed
            }
            var servers = rootObj["mcpServers"] as? [String: Any] ?? [:]
            var entry: [String: Any] = ["serverUrl": urlStr]
            if let tok = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines), !tok.isEmpty {
                let authHeader = tok.lowercased().hasPrefix("bearer ") ? tok : "Bearer \(tok)"
                entry["headers"] = ["Authorization": authHeader]
            }
            servers[cleanName] = entry
            rootObj["mcpServers"] = servers
            if let out = try? JSONSerialization.data(withJSONObject: rootObj, options: [.prettyPrinted, .sortedKeys]) {
                try? out.write(to: globalMCP)
            }

            connections[cleanName]?.stop()
            let spec = DiscoveredMCPServer(
                name: cleanName,
                sourcePlatform: "MicroCode Global (~/.microcode/mcp.json)",
                command: urlStr,
                args: [],
                env: [:],
                url: urlStr,
                headers: (entry["headers"] as? [String: String]) ?? [:]
            )
            let conn = ExternalMCPConnection(server: spec)
            connections[cleanName] = conn
        } else if let cmd = command?.trimmingCharacters(in: .whitespacesAndNewlines), !cmd.isEmpty {
            connections[cleanName]?.stop()
            let spec = DiscoveredMCPServer(
                name: cleanName,
                sourcePlatform: "MicroCode Connected",
                command: cmd,
                args: args,
                env: [:]
            )
            connections[cleanName] = ExternalMCPConnection(server: spec)
        }

        guard let conn = connections[cleanName] else {
            return "MCP server '\(cleanName)' was not found in local configs (`~/.gemini/config/plugins`, `~/.microcode/mcp.json`, `~/.cursor/mcp.json`). Pass `url` (for remote HTTP MCP) or `command` + `args` (for local stdio MCP) to register it."
        }

        failedProbeServers.remove(cleanName)
        conn.stop()
        conn.start()
        let deadline = Date().addingTimeInterval(5.0)
        while Date() < deadline {
            if !conn.availableTools.isEmpty { break }
            if !conn.isConnected && conn.error != nil { break }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        refreshToolCountNow()

        let matchingSkills = AgentSkillsStore.shared.skills.filter {
            $0.id.lowercased().contains(cleanName) || $0.filePath.lowercased().contains("/\(cleanName)/")
        }
        let skillsSummary = matchingSkills.isEmpty
            ? "None"
            : matchingSkills.map { "`\($0.id)` (\($0.description.prefix(80)))" }.joined(separator: ", ")

        if !conn.availableTools.isEmpty {
            for t in conn.availableTools {
                explicitlyMountedTools.insert("mcp__\(cleanName)__\(t.name)")
            }
            let toolNames = conn.availableTools.map { "`mcp__\(cleanName)__\($0.name)`" }.joined(separator: ", ")
            return """
            ✅ Connected MCP Server '\(cleanName)' (\(conn.source))
            Endpoint/Command: \(conn.remoteURL ?? conn.command)
            Exposed Tools (\(conn.availableTools.count)): \(toolNames)
            Companion Installed Skills (\(matchingSkills.count)): \(skillsSummary)
            """
        } else {
            let errDetail = conn.error ?? "Waiting for server response"
            // Check if local companion CLI exists (e.g., `canva` CLI)
            let hasCLI = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/\(cleanName)")
                || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/\(cleanName)")
                || FileManager.default.isExecutableFile(atPath: "\(NSHomeDirectory())/.local/bin/\(cleanName)")
            return """
            ⚠️ MCP Server '\(cleanName)' Registered (\(conn.remoteURL ?? conn.command)) — Handshake Status: \(errDetail)
            Companion Installed Skills (\(matchingSkills.count)): \(skillsSummary)
            Local '\(cleanName)' CLI Binary Found: \(hasCLI ? "Yes (can authenticate/use via CLI skill)" : "No")
            Next Step: To complete live tool mounting for an OAuth-protected remote MCP endpoint, sign in via `\(cleanName) login` (if CLI is supported) or pass an access token via `mcp_orchestrator(action: "connect", server_name: "\(cleanName)", bearer_token: "<token>")` / Settings → MCP Servers. Meanwhile, companion skills above are active and ready to read via `skill_engine(action: "read", query: "...")`.
            """
        }
    }

    /// Compact 1-screen catalog for `buildSystemPrompt` so Turn 1 always knows real MCP status without guessing.
    func compactPromptSummary() -> String {
        guard !connections.isEmpty else { return "" }
        let router = PNSGanglionRouter.shared
        var lines: [String] = ["## Discovered External MCP Servers (Use `mcp_orchestrator` to inspect/search/connect)"]
        for (name, conn) in connections.sorted(by: { $0.key < $1.key }).prefix(16) {
            let tools = !conn.availableTools.isEmpty ? conn.availableTools : (router.cachedServerManifests[name] ?? [])
            let state: String
            if conn.isConnected {
                state = "ONLINE (\(tools.count) tools)"
            } else if !tools.isEmpty {
                state = "READY (\(tools.count) cached tools)"
            } else if let err = conn.error, err.contains("AUTH_REQUIRED") {
                state = "AUTH_REQUIRED (\(conn.remoteURL ?? conn.source))"
            } else if let err = conn.error, !err.isEmpty {
                state = "OFFLINE (\(err.prefix(60)))"
            } else {
                state = "DISCOVERED (\(conn.source))"
            }
            lines.append("- `\(name)`: \(state)")
        }
        return "\n\n" + lines.joined(separator: "\n")
    }

    /// Formatted mesh status report for Agent & UI
    func meshStatusSummary() -> String {
        if connections.isEmpty {
            return "No external MCP servers configured. Use `mcp_orchestrator` with action='synthesize' to create a custom MCP server on the fly."
        }
        refreshToolCountNow()
        let router = PNSGanglionRouter.shared
        var lines: [String] = ["Hyper-Mesh MCP Status (\(connections.count) servers, \(totalToolCount) external tools):"]
        for (name, conn) in connections.sorted(by: { $0.key < $1.key }) {
            let effectiveTools = !conn.availableTools.isEmpty
                ? conn.availableTools
                : (router.cachedServerManifests[name] ?? [])
            let state: String
            if conn.isConnected {
                state = "ONLINE"
            } else if !effectiveTools.isEmpty {
                state = "READY (HIBERNATED)"
            } else if let err = conn.error, !err.isEmpty {
                state = "ERROR: \(err)"
            } else {
                state = "STANDBY"
            }
            let toolsList = effectiveTools.map(\.name).joined(separator: ", ")
            lines.append("- [\(state)] \(name) (source: \(conn.source), calls: \(conn.callCount), avg: \(conn.avgLatencyMs)ms, heals: \(conn.autoRestartCount)) -> tools (\(effectiveTools.count)): [\(toolsList)]")
        }
        return lines.joined(separator: "\n")
    }
    
    /// Stop all connections
    func stopAll() {
        activeProbeTask?.cancel()
        for (_, conn) in connections {
            conn.stop()
        }
        connections.removeAll()
        totalToolCount = 0
    }
    
    /// Restart a specific server
    func restartServer(_ name: String) {
        failedProbeServers.remove(name)
        if let conn = connections[name] {
            conn.stop()
            conn.autoRestartCount = 0
            conn.start()
        }
    }
    
    func refreshToolCountNow() {
        let router = PNSGanglionRouter.shared
        totalToolCount = connections.reduce(0) { sum, entry in
            let liveCount = entry.value.availableTools.count
            if liveCount > 0 { return sum + liveCount }
            return sum + (router.cachedServerManifests[entry.key]?.count ?? 0)
        }
    }
    
    private func updateToolCount() {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            refreshToolCountNow()
        }
    }
}
