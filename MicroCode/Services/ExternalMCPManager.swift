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
    
    @Published var isConnected = false
    @Published var availableTools: [MCPClient.MCPToolSchema] = []
    @Published var error: String? = nil
    
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stdoutBuffer = ""
    private var pendingRequests: [Int: (Result<Any, Error>) -> Void] = [:]
    private var requestIdCounter = 1
    
    init(server: DiscoveredMCPServer) {
        self.id = server.id
        self.serverName = server.name
        self.command = server.command
        self.args = server.args
        self.env = server.env
    }
    
    // MARK: - Lifecycle
    
    func start() {
        guard !isConnected else { return }
        
        let process = Process()
        
        // Resolve command path
        let commandPath = resolveCommand(command)
        guard let execPath = commandPath else {
            error = "Command not found: \(command)"
            print("[ExternalMCP:\(serverName)] Command not found: \(command)")
            return
        }
        
        process.executableURL = URL(fileURLWithPath: execPath)
        process.arguments = args
        
        // Merge environment
        var processEnv = ProcessInfo.processInfo.environment
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
        self.stdoutBuffer = ""
        
        // Handle stdout (JSON-RPC responses)
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async {
                self?.handleOutput(data)
            }
        }
        
        // Handle stderr (debug/error logs)
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                print("[ExternalMCP:\(self?.serverName ?? "?")] stderr: \(str.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        
        // Handle process termination
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isConnected = false
                self?.availableTools = []
                print("[ExternalMCP:\(self?.serverName ?? "?")] Process terminated")
            }
        }
        
        do {
            try process.run()
            isConnected = true
            error = nil
            print("[ExternalMCP:\(serverName)] Started: \(command) \(args.joined(separator: " "))")
            
            // Initialize MCP protocol
            sendRequest(method: "initialize", params: [
                "protocolVersion": "2024-11-05",
                "capabilities": [:],
                "clientInfo": ["name": "MicroCode", "version": "1.0"]
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
        stdoutBuffer = ""
    }
    
    // MARK: - Tool Calling
    
    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
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
    }
    
    // MARK: - Private JSON-RPC
    
    private func handleOutput(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        stdoutBuffer += string
        let components = stdoutBuffer.components(separatedBy: "\n")
        stdoutBuffer = components.last ?? ""
        let lines = components.dropLast().filter { !$0.isEmpty }
        
        for line in lines {
            guard let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }
            
            if let id = json["id"] as? Int {
                if let callback = pendingRequests.removeValue(forKey: id) {
                    if let error = json["error"] as? [String: Any] {
                        let msg = error["message"] as? String ?? "Unknown error"
                        callback(.failure(NSError(domain: "ExternalMCP", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])))
                    } else if let result = json["result"] {
                        callback(.success(result))
                    }
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
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let pipe = stdinPipe else { return }
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
            if AgentToolBox.shared.tools[namespacedName] == nil {
                let proxyTool = ExternalMCPTool(connection: self, schema: schema, serverName: serverName)
                AgentToolBox.shared.register(proxyTool)
                print("[ExternalMCP:\(serverName)] Registered tool: \(namespacedName)")
            }
        }
    }
    
    // MARK: - Command Resolution
    
    private func resolveCommand(_ cmd: String) -> String? {
        // Absolute path
        if cmd.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: cmd) {
            return cmd
        }
        
        // Common command names to resolve
        let searchPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.nvm/versions/node",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.bun/bin"
        ]
        
        // Check if it's npx, node, python3, etc.
        if cmd == "npx" || cmd == "node" || cmd == "python3" || cmd == "python" || cmd == "bun" || cmd == "deno" {
            for dir in searchPaths {
                let path = (dir as NSString).appendingPathComponent(cmd)
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
            
            // Try nvm node directories
            if cmd == "npx" || cmd == "node" {
                let nvmDir = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.nvm/versions/node"
                if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
                    for version in versions.sorted().reversed() {
                        let path = "\(nvmDir)/\(version)/bin/\(cmd)"
                        if FileManager.default.isExecutableFile(atPath: path) {
                            return path
                        }
                    }
                }
            }
        }
        
        // Use `which` as fallback
        let whichProcess = Process()
        let whichPipe = Pipe()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = [cmd]
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

// MARK: - External MCP Manager (Multi-server orchestrator)

@MainActor
class ExternalMCPManager: ObservableObject {
    static let shared = ExternalMCPManager()
    
    @Published var connections: [String: ExternalMCPConnection] = [:]
    @Published var totalToolCount: Int = 0
    
    private init() {}
    
    /// Auto-discover and launch all MCP servers from workspace config files
    func syncWithDiscoveredServers(_ servers: [DiscoveredMCPServer]) {
        // Stop connections that no longer exist in config
        let currentNames = Set(servers.map(\.name))
        for (name, conn) in connections where !currentNames.contains(name) {
            conn.stop()
            connections.removeValue(forKey: name)
        }
        
        // Start new connections
        for server in servers {
            if connections[server.name] == nil {
                let connection = ExternalMCPConnection(server: server)
                connections[server.name] = connection
                connection.start()
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
    
    private func updateToolCount() {
        // Delayed update to allow tools to be fetched
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
            totalToolCount = connections.values.reduce(0) { $0 + $1.availableTools.count }
        }
    }
}
