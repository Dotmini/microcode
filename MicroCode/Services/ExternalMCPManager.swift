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
    
    @Published var isConnected = false
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
    private var readCache: [String: (output: String, timestamp: Date)] = [:]
    
    init(server: DiscoveredMCPServer) {
        self.id = server.id
        self.serverName = server.name
        self.command = server.command
        self.args = server.args
        self.env = server.env
        self.source = server.sourcePlatform
        self.remoteURL = server.url ?? ((server.command.hasPrefix("http://") || server.command.hasPrefix("https://")) ? server.command : nil)
    }
    
    // MARK: - Lifecycle
    
    func start() {
        guard !isConnected else { return }
        manuallyStopped = false
        
        if let httpURL = remoteURL, !httpURL.isEmpty {
            isConnected = true
            error = nil
            sendRequest(method: "initialize", params: [
                "protocolVersion": "2025-06-18",
                "capabilities": ["roots": ["listChanged": false]],
                "clientInfo": ["name": "MicroCode-HyperMesh", "version": "3.0.0"]
            ] as [String: Any]) { [weak self] result in
                switch result {
                case .success(_):
                    self?.sendNotification(method: "notifications/initialized")
                    self?.fetchTools()
                    print("[ExternalMCP:\(self?.serverName ?? "?")] HTTP Initialized (\(httpURL))")
                case .failure(let err):
                    self?.error = "HTTP Init failed: \(err.localizedDescription)"
                    self?.isConnected = false
                }
            }
            return
        }
        
        let process = Process()
        
        // Resolve command path (prioritizing MicroCode Portable Runtimes)
        let commandPath = resolveCommand(command)
        guard let execPath = commandPath else {
            error = "Command not found: \(command)"
            print("[ExternalMCP:\(serverName)] Command not found: \(command)")
            return
        }
        
        process.executableURL = URL(fileURLWithPath: execPath)
        process.arguments = args
        
        // Merge environment + MicroCode Portable Runtime PATH
        var processEnv = ProcessInfo.processInfo.environment
        processEnv.removeValue(forKey: "MICROCODE_LOCAL_API_TOKEN")
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
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isConnected = false
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
            isConnected = true
            error = nil
            print("[ExternalMCP:\(serverName)] Started: \(execPath) \(args.joined(separator: " "))")
            
            // Initialize MCP protocol (supports 2025-06-18 and 2024-11-05)
            sendRequest(method: "initialize", params: [
                "protocolVersion": "2025-06-18",
                "capabilities": ["roots": ["listChanged": false]],
                "clientInfo": ["name": "MicroCode-HyperMesh", "version": "2.3.1"]
            ] as [String: Any]) { [weak self] result in
                switch result {
                case .success(_):
                    self?.sendNotification(method: "notifications/initialized")
                    self?.fetchTools()
                    print("[ExternalMCP:\(self?.serverName ?? "?")] Initialized")
                case .failure(let err):
                    self?.error = "Init failed: \(err.localizedDescription)"
                    print("[ExternalMCP:\(self?.serverName ?? "?")] Init error: \(err)")
                }
            }
        } catch {
            self.error = "Failed to start: \(error.localizedDescription)"
            isConnected = false
            print("[ExternalMCP:\(serverName)] Failed to start: \(error)")
        }
    }
    
    func stop() {
        manuallyStopped = true
        let shutdownError = NSError(domain: "ExternalMCP", code: -2, userInfo: [NSLocalizedDescriptionKey: "Connection closed"])
        let callbacks = pendingRequests.values
        pendingRequests.removeAll()
        callbacks.forEach { $0(.failure(shutdownError)) }
        
        process?.terminate()
        isConnected = false
        process = nil
        stdinPipe = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        availableTools = []
        stdoutBuffer.removeAll(keepingCapacity: false)
    }
    
    // MARK: - Tool Calling (with Telemetry & Read Cache)
    
    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        if !isConnected {
            start()
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        
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
            return output
        } catch {
            errorCount += 1
            throw error
        }
    }
    
    // MARK: - Private JSON-RPC
    
    private func handleOutput(_ data: Data) {
        stdoutBuffer.append(data)
        
        while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer.subdata(in: 0..<newlineIndex)
            stdoutBuffer.removeSubrange(0...newlineIndex)
            
            let line = String(decoding: lineData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }
            
            // Handle server-to-client requests (e.g. ping, roots/list)
            if let method = json["method"] as? String, let reqId = json["id"] {
                if method == "ping" {
                    sendRaw(["jsonrpc": "2.0", "id": reqId, "result": [:] as [String: Any]])
                } else if method == "roots/list" {
                    let ws = AppState.shared?.workspaceFolder?.path ?? AppState.shared?.activeTerminalDirectory ?? FileManager.default.currentDirectoryPath
                    let rootURI = URL(fileURLWithPath: ws).absoluteString
                    sendRaw([
                        "jsonrpc": "2.0",
                        "id": reqId,
                        "result": ["roots": [["uri": rootURI, "name": URL(fileURLWithPath: ws).lastPathComponent]]]
                    ])
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
        sendRaw(request)
        
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
    
    private func sendRaw(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        if let httpURL = remoteURL, let url = URL(string: httpURL) {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            req.httpBody = data
            URLSession.shared.dataTask(with: req) { [weak self] respData, _, err in
                guard let self else { return }
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
                    }
                }
            case .failure(let err):
                print("[ExternalMCP:\(self.serverName)] Fetch tools error: \(err)")
            }
        }
    }
    
    private func registerToolsWithAgent() {
        for schema in availableTools {
            let namespacedName = "mcp__\(serverName)__\(schema.name)"
            let proxyTool = ExternalMCPTool(connection: self, schema: schema, serverName: serverName)
            AgentToolBox.shared.register(proxyTool)
            print("[ExternalMCP:\(serverName)] Registered tool: \(namespacedName)")
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
    
    private init() {}
    
    /// Discover MCP servers from workspace & IDE config files (lazy by default so opening a folder doesn't spawn 5+ Node/Python processes)
    func syncWithDiscoveredServers(_ servers: [DiscoveredMCPServer], autoStart: Bool = false) {
        let currentNames = Set(servers.map(\.name))
        for (name, conn) in connections where !currentNames.contains(name) && conn.source != "Synthesized" {
            conn.stop()
            connections.removeValue(forKey: name)
        }
        
        for server in servers {
            if connections[server.name] == nil {
                let connection = ExternalMCPConnection(server: server)
                connections[server.name] = connection
                if autoStart {
                    connection.start()
                }
            }
        }
        
        updateToolCount()
    }
    
    /// Get all connected server names
    var connectedServerNames: [String] {
        connections.filter(\.value.isConnected).map(\.key).sorted()
    }
    
    /// Get all available tools across all servers
    var allTools: [(serverName: String, tool: MCPClient.MCPToolSchema)] {
        var tools: [(String, MCPClient.MCPToolSchema)] = []
        for (name, conn) in connections where conn.isConnected {
            for tool in conn.availableTools {
                tools.append((name, tool))
            }
        }
        return tools
    }
    
    /// Semantic Eager/Lazy MCP Tool Router:
    /// Always keeps `mcp__local__*` eager, and if external MCP tools exceed 12,
    /// dynamically selects the Top-12 prompt-relevant external MCP tools so the context window never bloats.
    func eagerExternalToolNames(forPrompt prompt: String, maxExternalTools: Int = 12) -> Set<String> {
        let externalTools = allTools
        if externalTools.count <= maxExternalTools {
            return Set(externalTools.map { "mcp__\($0.serverName)__\($0.tool.name)" })
        }
        let tokens = prompt.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
        let scored: [(name: String, score: Int)] = externalTools.map { entry in
            let fullName = "mcp__\(entry.serverName)__\(entry.tool.name)"
            let hay = "\(entry.serverName) \(entry.tool.name) \(entry.tool.description)".lowercased()
            var s = 1
            for tok in tokens {
                if entry.serverName.lowercased().contains(tok) { s += 15 }
                if entry.tool.name.lowercased().contains(tok) { s += 12 }
                if hay.contains(tok) { s += 5 }
            }
            return (fullName, s)
        }.sorted { $0.score > $1.score }
        
        return Set(scored.prefix(maxExternalTools).map(\.name))
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
            rootDir = URL(fileURLWithPath: ws).appendingPathComponent(".microcode/mcp", isDirectory: true)
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
        return """
        ✅ Synthesized & Hot-Mounted MCP Server '\(slug)'
        Script: \(scriptURL.path)
        Config: \(configURL.path)
        Status: \(conn.isConnected ? "Connected" : (conn.error ?? "Starting"))
        Registered Tools (\(registeredNames.count)): \(registeredNames.joined(separator: ", "))
        """
    }
    
    /// Formatted mesh status report for Agent & UI
    func meshStatusSummary() -> String {
        if connections.isEmpty {
            return "No external MCP servers configured. Use `mcp_orchestrator` with action='synthesize' to create a custom MCP server on the fly."
        }
        var lines: [String] = ["Hyper-Mesh MCP Status (\(connections.count) servers, \(totalToolCount) external tools):"]
        for (name, conn) in connections.sorted(by: { $0.key < $1.key }) {
            let state = conn.isConnected ? "ONLINE" : "OFFLINE"
            let toolsList = conn.availableTools.map(\.name).joined(separator: ", ")
            lines.append("- [\(state)] \(name) (source: \(conn.source), calls: \(conn.callCount), avg: \(conn.avgLatencyMs)ms, heals: \(conn.autoRestartCount)) -> tools: [\(toolsList)]")
        }
        return lines.joined(separator: "\n")
    }
    
    /// Stop all connections
    func stopAll() {
        for (_, conn) in connections {
            conn.stop()
        }
        connections.removeAll()
        totalToolCount = 0
    }
    
    /// Restart a specific server
    func restartServer(_ name: String) {
        if let conn = connections[name] {
            conn.stop()
            conn.start()
        }
    }
    
    func refreshToolCountNow() {
        totalToolCount = connections.values.reduce(0) { $0 + $1.availableTools.count }
    }
    
    private func updateToolCount() {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            refreshToolCountNow()
        }
    }
}
