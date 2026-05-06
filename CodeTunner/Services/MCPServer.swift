//
//  MCPServer.swift
//  CodeTunner
//
//  MicroCode MCP (Model Context Protocol) Server
//  JSON-RPC 2.0 compliant, secure, workspace-sandboxed
//
//  Supports: read_file, write_file, edit_file, search_files,
//            list_files, run_terminal, git_status, get_diagnostics
//
//  Copyright © 2025 SPU AI CLUB — Dotmini Software
//

import Foundation
import Combine

// MARK: - MCP Protocol Types

struct MCPRequest: Codable {
    let jsonrpc: String
    let id: Int?
    let method: String
    let params: MCPParams?
}

struct MCPParams: Codable {
    // For tools/call
    let name: String?
    let arguments: [String: MCPAnyCodable]?
    
    // For resources/read
    let uri: String?
    
    // For initialize
    let protocolVersion: String?
    let capabilities: MCPClientCapabilities?
    let clientInfo: MCPClientInfo?
}

struct MCPClientCapabilities: Codable {
    let roots: MCPRootsCapability?
    let sampling: [String: MCPAnyCodable]?
}

struct MCPRootsCapability: Codable {
    let listChanged: Bool?
}

struct MCPClientInfo: Codable {
    let name: String?
    let version: String?
}

struct MCPResponse: Encodable {
    let jsonrpc: String
    let id: Int?
    let result: MCPAnyCodable?
    let error: MCPError?
    
    init(id: Int?, result: Any?) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result != nil ? MCPAnyCodable(result!) : nil
        self.error = nil
    }
    
    init(id: Int?, error: MCPError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

struct MCPError: Codable {
    let code: Int
    let message: String
    let data: String?
    
    static let parseError = MCPError(code: -32700, message: "Parse error", data: nil)
    static let methodNotFound = MCPError(code: -32601, message: "Method not found", data: nil)
    static let invalidParams = MCPError(code: -32602, message: "Invalid params", data: nil)
    static let internalError = MCPError(code: -32603, message: "Internal error", data: nil)
    static func custom(_ msg: String) -> MCPError { MCPError(code: -32000, message: msg, data: nil) }
}

// MARK: - AnyCodable Helper

struct MCPAnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) { self.value = value }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { value = NSNull() }
        else if let b = try? container.decode(Bool.self) { value = b }
        else if let i = try? container.decode(Int.self) { value = i }
        else if let d = try? container.decode(Double.self) { value = d }
        else if let s = try? container.decode(String.self) { value = s }
        else if let a = try? container.decode([MCPAnyCodable].self) { value = a.map { $0.value } }
        else if let o = try? container.decode([String: MCPAnyCodable].self) { value = o.mapValues { $0.value } }
        else { value = NSNull() }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull: try container.encodeNil()
        case let b as Bool: try container.encode(b)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let s as String: try container.encode(s)
        case let a as [Any]: try container.encode(a.map { MCPAnyCodable($0) })
        case let o as [String: Any]: try container.encode(o.mapValues { MCPAnyCodable($0) })
        default: try container.encodeNil()
        }
    }
}

// MARK: - MCP Security Sandbox

class MCPSecuritySandbox {
    let workspacePath: String
    
    // Blocked commands for safety
    private let blockedCommands = [
        "rm -rf /", "rm -rf ~", "sudo rm", "mkfs", "dd if=",
        ":(){ :|:& };:", "chmod -R 777 /", "curl | sh",
        "wget -O- | sh", "> /dev/sda", "mv / ", "shutdown",
        "reboot", "halt", "init 0", "init 6"
    ]
    
    // Allowed file extensions for write
    private let allowedExtensions = Set([
        "swift", "rs", "py", "js", "ts", "jsx", "tsx", "java", "kt",
        "go", "c", "cpp", "h", "hpp", "cs", "rb", "php", "html", "css",
        "json", "yaml", "yml", "toml", "xml", "md", "txt", "sh", "bash",
        "sql", "graphql", "proto", "dockerfile", "makefile", "gitignore",
        "env", "cfg", "ini", "conf", "lock", "svg"
    ])
    
    init(workspace: String) {
        self.workspacePath = workspace
    }
    
    /// Validate path is within workspace
    func validatePath(_ path: String) -> Result<String, MCPError> {
        let resolved = (path as NSString).expandingTildeInPath
        let absolute: String
        
        if resolved.hasPrefix("/") {
            absolute = resolved
        } else {
            absolute = (workspacePath as NSString).appendingPathComponent(resolved)
        }
        
        let canonical = (absolute as NSString).standardizingPath
        let workspaceCanonical = (workspacePath as NSString).standardizingPath
        
        guard canonical.hasPrefix(workspaceCanonical) else {
            return .failure(.custom("Access denied: path '\(path)' is outside workspace"))
        }
        
        // Block dotfile traversal attacks
        if canonical.contains("../") || canonical.contains("/..") {
            return .failure(.custom("Access denied: path traversal detected"))
        }
        
        return .success(canonical)
    }
    
    /// Validate command is safe to execute
    func validateCommand(_ command: String) -> Result<Void, MCPError> {
        let lower = command.lowercased()
        
        for blocked in blockedCommands {
            if lower.contains(blocked.lowercased()) {
                return .failure(.custom("Command blocked for safety: contains '\(blocked)'"))
            }
        }
        
        // Block network exfiltration
        if lower.contains("curl") && (lower.contains("| sh") || lower.contains("| bash")) {
            return .failure(.custom("Command blocked: pipe to shell detected"))
        }
        
        return .success(())
    }
    
    /// Check if file extension is allowed for write
    func canWrite(to path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        if ext.isEmpty { return true } // Allow extensionless files (Makefile, Dockerfile, etc)
        return allowedExtensions.contains(ext)
    }
}

// MARK: - MCP Server

@MainActor
class MCPServer: ObservableObject {
    static let shared = MCPServer()
    
    @Published var isRunning = false
    @Published var connectedClients: Int = 0
    @Published var requestCount: Int = 0
    @Published var lastActivity: Date?
    @Published var logs: [MCPLog] = []
    
    private var sandbox: MCPSecuritySandbox?
    private var workspacePath: String = ""
    
    struct MCPLog: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let method: String
        let status: LogStatus
        let detail: String
        
        enum LogStatus { case success, error, info }
    }
    
    // MARK: - Server Lifecycle
    
    func start(workspace: String) {
        workspacePath = workspace
        sandbox = MCPSecuritySandbox(workspace: workspace)
        isRunning = true
        log("MCP Server started", method: "lifecycle", status: .info)
    }
    
    func stop() {
        isRunning = false
        connectedClients = 0
        log("MCP Server stopped", method: "lifecycle", status: .info)
    }
    
    // MARK: - Handle Request
    
    func handleRequest(_ jsonString: String) async -> String {
        requestCount += 1
        lastActivity = Date()
        
        guard let data = jsonString.data(using: String.Encoding.utf8),
              let request = try? JSONDecoder().decode(MCPRequest.self, from: data) else {
            return encodeResponse(MCPResponse(id: nil, error: .parseError))
        }
        
        let response = await processRequest(request)
        return encodeResponse(response)
    }
    
    func handleRequestData(_ data: Data) async -> Data {
        let jsonString = String(data: data, encoding: String.Encoding.utf8) ?? ""
        let responseString = await handleRequest(jsonString)
        return responseString.data(using: String.Encoding.utf8) ?? Data()
    }
    
    // MARK: - Process Methods
    
    private func processRequest(_ request: MCPRequest) async -> MCPResponse {
        switch request.method {
        case "initialize":
            return handleInitialize(request)
        case "initialized":
            return MCPResponse(id: request.id, result: nil)
        case "tools/list":
            return handleToolsList(request)
        case "tools/call":
            return await handleToolCall(request)
        case "resources/list":
            return handleResourcesList(request)
        case "resources/read":
            return await handleResourceRead(request)
        case "prompts/list":
            return handlePromptsList(request)
        case "ping":
            return MCPResponse(id: request.id, result: ["status": "pong"])
        default:
            log("Unknown method: \(request.method)", method: request.method, status: .error)
            return MCPResponse(id: request.id, error: .methodNotFound)
        }
    }
    
    // MARK: - Initialize
    
    private func handleInitialize(_ request: MCPRequest) -> MCPResponse {
        connectedClients += 1
        log("Client connected", method: "initialize", status: .info)
        
        let result: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": ["listChanged": true],
                "resources": ["subscribe": false, "listChanged": true],
                "prompts": ["listChanged": false],
                "logging": [:]
            ],
            "serverInfo": [
                "name": "MicroCode MCP",
                "version": "1.0.0"
            ]
        ]
        return MCPResponse(id: request.id, result: result)
    }
    
    // MARK: - Tools List
    
    private func handleToolsList(_ request: MCPRequest) -> MCPResponse {
        let tools: [[String: Any]] = [
            [
                "name": "read_file",
                "description": "Read the contents of a file in the workspace.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Relative or absolute path to the file"]
                    ],
                    "required": ["path"]
                ]
            ],
            [
                "name": "write_file",
                "description": "Write content to a file. Creates the file if it doesn't exist.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Path to write to"],
                        "content": ["type": "string", "description": "File content to write"]
                    ],
                    "required": ["path", "content"]
                ]
            ],
            [
                "name": "edit_file",
                "description": "Make surgical edits to a file by replacing specific text.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "File path"],
                        "old_text": ["type": "string", "description": "Text to find and replace"],
                        "new_text": ["type": "string", "description": "Replacement text"]
                    ],
                    "required": ["path", "old_text", "new_text"]
                ]
            ],
            [
                "name": "search_files",
                "description": "Search for text patterns across workspace files using grep.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search query or regex"],
                        "path": ["type": "string", "description": "Directory to search in (default: workspace root)"],
                        "include": ["type": "string", "description": "File glob pattern to include (e.g. *.swift)"]
                    ],
                    "required": ["query"]
                ]
            ],
            [
                "name": "list_files",
                "description": "List files and directories in a path.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Directory path (default: workspace root)"],
                        "recursive": ["type": "boolean", "description": "List recursively (default: false)"]
                    ]
                ]
            ],
            [
                "name": "run_terminal",
                "description": "Execute a shell command in the workspace directory.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "command": ["type": "string", "description": "Shell command to execute"],
                        "timeout": ["type": "integer", "description": "Timeout in seconds (default: 30, max: 120)"]
                    ],
                    "required": ["command"]
                ]
            ],
            [
                "name": "git_status",
                "description": "Get Git repository status, diff, or log.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "operation": ["type": "string", "enum": ["status", "diff", "log", "branch"], "description": "Git operation"]
                    ],
                    "required": ["operation"]
                ]
            ],
            [
                "name": "get_diagnostics",
                "description": "Get current editor diagnostics (errors, warnings) for a file.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "File path to get diagnostics for"]
                    ]
                ]
            ]
        ]
        
        return MCPResponse(id: request.id, result: ["tools": tools])
    }
    
    // MARK: - Tool Execution
    
    private func handleToolCall(_ request: MCPRequest) async -> MCPResponse {
        guard let name = request.params?.name,
              let args = request.params?.arguments?.mapValues({ $0.value }) else {
            return MCPResponse(id: request.id, error: .invalidParams)
        }
        
        guard let sandbox = sandbox else {
            return MCPResponse(id: request.id, error: .custom("MCP Server not initialized — no workspace set"))
        }
        
        do {
            let result: Any
            switch name {
            case "read_file":
                result = try await executeReadFile(args, sandbox: sandbox)
            case "write_file":
                result = try await executeWriteFile(args, sandbox: sandbox)
            case "edit_file":
                result = try await executeEditFile(args, sandbox: sandbox)
            case "search_files":
                result = try await executeSearchFiles(args, sandbox: sandbox)
            case "list_files":
                result = try await executeListFiles(args, sandbox: sandbox)
            case "run_terminal":
                result = try await executeTerminal(args, sandbox: sandbox)
            case "git_status":
                result = try await executeGitStatus(args, sandbox: sandbox)
            case "get_diagnostics":
                result = try executeGetDiagnostics(args)
            default:
                return MCPResponse(id: request.id, error: .custom("Unknown tool: \(name)"))
            }
            
            log("Tool: \(name)", method: "tools/call", status: .success)
            return MCPResponse(id: request.id, result: [
                "content": [["type": "text", "text": "\(result)"]]
            ])
        } catch {
            log("Tool error: \(name) — \(error.localizedDescription)", method: "tools/call", status: .error)
            return MCPResponse(id: request.id, result: [
                "content": [["type": "text", "text": "Error: \(error.localizedDescription)"]],
                "isError": true
            ])
        }
    }
    
    // MARK: - Tool Implementations
    
    private func executeReadFile(_ args: [String: Any], sandbox: MCPSecuritySandbox) async throws -> String {
        guard let path = args["path"] as? String else { throw MCPToolError.missingParam("path") }
        
        switch sandbox.validatePath(path) {
        case .success(let resolved):
            guard FileManager.default.fileExists(atPath: resolved) else {
                throw MCPToolError.fileNotFound(path)
            }
            return try String(contentsOfFile: resolved, encoding: String.Encoding.utf8)
        case .failure(let error):
            throw MCPToolError.securityViolation(error.message)
        }
    }
    
    private func executeWriteFile(_ args: [String: Any], sandbox: MCPSecuritySandbox) async throws -> String {
        guard let path = args["path"] as? String,
              let content = args["content"] as? String else { throw MCPToolError.missingParam("path, content") }
        
        switch sandbox.validatePath(path) {
        case .success(let resolved):
            guard sandbox.canWrite(to: resolved) else {
                throw MCPToolError.securityViolation("File type not allowed for write")
            }
            let dir = (resolved as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try content.write(toFile: resolved, atomically: true, encoding: String.Encoding.utf8)
            return "Written \(content.count) bytes to \(path)"
        case .failure(let error):
            throw MCPToolError.securityViolation(error.message)
        }
    }
    
    private func executeEditFile(_ args: [String: Any], sandbox: MCPSecuritySandbox) async throws -> String {
        guard let path = args["path"] as? String,
              let oldText = args["old_text"] as? String,
              let newText = args["new_text"] as? String else { throw MCPToolError.missingParam("path, old_text, new_text") }
        
        switch sandbox.validatePath(path) {
        case .success(let resolved):
            var content = try String(contentsOfFile: resolved, encoding: String.Encoding.utf8)
            guard content.contains(oldText) else {
                throw MCPToolError.editFailed("Target text not found in file")
            }
            content = content.replacingOccurrences(of: oldText, with: newText)
            try content.write(toFile: resolved, atomically: true, encoding: String.Encoding.utf8)
            return "Edited \(path): replaced \(oldText.count) chars with \(newText.count) chars"
        case .failure(let error):
            throw MCPToolError.securityViolation(error.message)
        }
    }
    
    private func executeSearchFiles(_ args: [String: Any], sandbox: MCPSecuritySandbox) async throws -> String {
        guard let query = args["query"] as? String else { throw MCPToolError.missingParam("query") }
        let searchPath = args["path"] as? String ?? "."
        let include = args["include"] as? String
        
        switch sandbox.validatePath(searchPath) {
        case .success(let resolved):
            var cmd = "grep -rn --max-count=50 \(query.shellEscaped()) \(resolved.shellEscaped())"
            if let include = include {
                cmd = "grep -rn --max-count=50 --include=\(include.shellEscaped()) \(query.shellEscaped()) \(resolved.shellEscaped())"
            }
            return try await runShellCommand(cmd, cwd: workspacePath, timeout: 15)
        case .failure(let error):
            throw MCPToolError.securityViolation(error.message)
        }
    }
    
    private func executeListFiles(_ args: [String: Any], sandbox: MCPSecuritySandbox) async throws -> String {
        let path = args["path"] as? String ?? "."
        let recursive = args["recursive"] as? Bool ?? false
        
        switch sandbox.validatePath(path) {
        case .success(let resolved):
            let fm = FileManager.default
            var items: [String] = []
            
            if recursive {
                if let enumerator = fm.enumerator(atPath: resolved) {
                    var count = 0
                    while let item = enumerator.nextObject() as? String, count < 500 {
                        items.append(item)
                        count += 1
                    }
                }
            } else {
                items = (try? fm.contentsOfDirectory(atPath: resolved)) ?? []
            }
            
            return items.joined(separator: "\n")
        case .failure(let error):
            throw MCPToolError.securityViolation(error.message)
        }
    }
    
    private func executeTerminal(_ args: [String: Any], sandbox: MCPSecuritySandbox) async throws -> String {
        guard let command = args["command"] as? String else { throw MCPToolError.missingParam("command") }
        let timeout = min(args["timeout"] as? Int ?? 30, 120)
        
        switch sandbox.validateCommand(command) {
        case .success:
            return try await runShellCommand(command, cwd: workspacePath, timeout: timeout)
        case .failure(let error):
            throw MCPToolError.securityViolation(error.message)
        }
    }
    
    private func executeGitStatus(_ args: [String: Any], sandbox: MCPSecuritySandbox) async throws -> String {
        guard let operation = args["operation"] as? String else { throw MCPToolError.missingParam("operation") }
        
        let cmd: String
        switch operation {
        case "status": cmd = "git status --porcelain"
        case "diff": cmd = "git diff --stat HEAD"
        case "log": cmd = "git log --oneline -20"
        case "branch": cmd = "git branch -a"
        default: throw MCPToolError.invalidParam("Unknown git operation: \(operation)")
        }
        
        return try await runShellCommand(cmd, cwd: workspacePath, timeout: 10)
    }
    
    private func executeGetDiagnostics(_ args: [String: Any]) throws -> String {
        // Return current LSP diagnostics if available
        return "No diagnostics available (LSP integration pending)"
    }
    
    // MARK: - Resources
    
    private func handleResourcesList(_ request: MCPRequest) -> MCPResponse {
        let resources: [[String: Any]] = [
            [
                "uri": "workspace://project",
                "name": "Project Structure",
                "description": "Current workspace file tree",
                "mimeType": "text/plain"
            ],
            [
                "uri": "workspace://active-file",
                "name": "Active File",
                "description": "Currently open file in editor",
                "mimeType": "text/plain"
            ]
        ]
        return MCPResponse(id: request.id, result: ["resources": resources])
    }
    
    private func handleResourceRead(_ request: MCPRequest) async -> MCPResponse {
        guard let uri = request.params?.uri else {
            return MCPResponse(id: request.id, error: .invalidParams)
        }
        
        switch uri {
        case "workspace://project":
            let tree = try? await runShellCommand("find . -maxdepth 3 -not -path './.git/*' -not -path './node_modules/*' -not -path './.build/*' | head -200", cwd: workspacePath, timeout: 5)
            return MCPResponse(id: request.id, result: [
                "contents": [["uri": uri, "mimeType": "text/plain", "text": tree ?? "No workspace"]]
            ])
        case "workspace://active-file":
            return MCPResponse(id: request.id, result: [
                "contents": [["uri": uri, "mimeType": "text/plain", "text": "Active file context from editor"]]
            ])
        default:
            return MCPResponse(id: request.id, error: .custom("Unknown resource: \(uri)"))
        }
    }
    
    // MARK: - Prompts
    
    private func handlePromptsList(_ request: MCPRequest) -> MCPResponse {
        let prompts: [[String: Any]] = [
            ["name": "explain-code", "description": "Explain what a piece of code does"],
            ["name": "refactor-code", "description": "Suggest refactoring improvements"],
            ["name": "fix-bug", "description": "Help debug and fix an issue"],
            ["name": "write-tests", "description": "Generate unit tests for code"]
        ]
        return MCPResponse(id: request.id, result: ["prompts": prompts])
    }
    
    // MARK: - Shell Execution
    
    private func runShellCommand(_ command: String, cwd: String, timeout: Int) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
            
            let pipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errPipe
            
            // Timeout
            let timer = DispatchSource.makeTimerSource()
            timer.schedule(deadline: .now() + .seconds(timeout))
            timer.setEventHandler {
                process.terminate()
            }
            timer.resume()
            
            do {
                try process.run()
                process.waitUntilExit()
                timer.cancel()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                
                var output = String(data: data, encoding: .utf8) ?? ""
                if output.isEmpty {
                    output = String(data: errData, encoding: .utf8) ?? ""
                }
                
                if process.terminationStatus != 0 && output.isEmpty {
                    output = "Command exited with code \(process.terminationStatus)"
                }
                
                // Limit output size
                if output.count > 50000 {
                    output = String(output.prefix(50000)) + "\n...[truncated]"
                }
                
                continuation.resume(returning: output)
            } catch {
                timer.cancel()
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Logging
    
    private func log(_ detail: String, method: String, status: MCPLog.LogStatus) {
        let entry = MCPLog(method: method, status: status, detail: detail)
        logs.append(entry)
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
    }
    
    // MARK: - Encode Response
    
    private func encodeResponse(_ response: MCPResponse) -> String {
        guard let data = try? JSONEncoder().encode(response) else { return "{}" }
        return String(data: data, encoding: String.Encoding.utf8) ?? "{}"
    }
}

// MARK: - MCP Tool Errors

enum MCPToolError: LocalizedError {
    case missingParam(String)
    case invalidParam(String)
    case fileNotFound(String)
    case editFailed(String)
    case securityViolation(String)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .missingParam(let p): return "Missing required parameter: \(p)"
        case .invalidParam(let p): return "Invalid parameter: \(p)"
        case .fileNotFound(let p): return "File not found: \(p)"
        case .editFailed(let m): return "Edit failed: \(m)"
        case .securityViolation(let m): return "Security: \(m)"
        case .timeout: return "Command timed out"
        }
    }
}

// MARK: - String Extension

extension String {
    func shellEscaped() -> String {
        return "'" + self.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
