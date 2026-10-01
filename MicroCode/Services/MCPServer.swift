//
//  MCPServer.swift
//  MicroCode
//
//  MicroCode MCP (Model Context Protocol) Server
//  JSON-RPC 2.0 compliant, secure, workspace-sandboxed
//
//  Supports: read_file, write_file, edit_file, search_files,
//            list_files, run_terminal, git_status, get_diagnostics
//
//  Copyright © 2025 Dotmini Company Limited
//

import Foundation
import Combine
import Network
import AppKit

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

struct MCPError: Codable, Error {
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
    
    // Allowed file extensions for write
    private let allowedExtensions = Set([
        "swift", "rs", "py", "js", "ts", "jsx", "tsx", "java", "kt",
        "go", "c", "cpp", "h", "hpp", "cs", "rb", "php", "html", "css",
        "json", "yaml", "yml", "toml", "xml", "md", "txt", "sh", "bash",
        "sql", "graphql", "proto", "dockerfile", "makefile", "gitignore",
        "env", "cfg", "ini", "conf", "lock", "svg"
    ])
    
    init(workspace: String) {
        self.workspacePath = URL(fileURLWithPath: workspace)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
    
    /// Validate path is within workspace
    func validatePath(_ path: String) -> Result<String, MCPError> {
        let expanded = (path as NSString).expandingTildeInPath
        let candidate = expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : URL(fileURLWithPath: workspacePath).appendingPathComponent(expanded)
        let canonical = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        let workspaceCanonical = workspacePath

        // Do not use a plain prefix test: `/workspace-evil` is not inside
        // `/workspace`. Existing symlinks are resolved before testing.
        guard canonical == workspaceCanonical || canonical.hasPrefix(workspaceCanonical + "/") else {
            return .failure(.custom("Access denied: path '\(path)' is outside workspace"))
        }
        return .success(canonical)
    }
    
    /// Autonomous MCP terminal requests are deliberately limited to simple,
    /// read-only workspace inspection. A substring blacklist is not a sandbox.
    func validateCommand(_ command: String) -> Result<Void, MCPError> {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.invalidParams) }
        let unsafeSyntax = [";", "|", "&", ">", "<", "`", "$", "\n", "\r"]
        guard !unsafeSyntax.contains(where: { trimmed.contains($0) }) else {
            return .failure(.custom("Shell composition, redirection, and substitution require explicit user approval"))
        }
        let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let executable = parts.first else { return .failure(.invalidParams) }
        let allowedExecutables: Set<String> = ["git", "rg", "grep", "find", "ls", "pwd", "head", "tail", "sed", "wc", "stat"]
        guard allowedExecutables.contains(String(executable)) else {
            return .failure(.custom("Only read-only workspace inspection commands are available through MCP"))
        }
        let arguments = parts.dropFirst()
        guard !arguments.contains(where: { $0.hasPrefix("/") || $0.contains("..") }) else {
            return .failure(.custom("Absolute paths and parent traversal are not allowed in MCP terminal commands"))
        }
        if executable == "git", let operation = arguments.first,
           !["status", "diff", "log", "branch", "show", "rev-parse"].contains(String(operation)) {
            return .failure(.custom("Only read-only git operations are available through MCP"))
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
            ],
            [
                "name": "microcode_run_playground",
                "description": "Run code in interactive Playground mode with instant profiling and stdin support on native macOS.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "code": ["type": "string", "description": "Source code to execute"],
                        "language": ["type": "string", "description": "Programming language (e.g. swift, python, go, rust, javascript)"],
                        "stdin": ["type": "string", "description": "Standard input to pipe into program"]
                    ],
                    "required": ["code", "language"]
                ]
            ],
            [
                "name": "microcode_run_cell",
                "description": "Run a specific notebook cell or code section in MicroCode Cell Mode.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "cell_id": ["type": "string", "description": "Identifier for the cell"],
                        "code": ["type": "string", "description": "Cell code content"],
                        "language": ["type": "string", "description": "Language of the cell"]
                    ],
                    "required": ["code", "language"]
                ]
            ],
            [
                "name": "execute_code",
                "description": "Execute code directly in Python, Bash, Swift, or other languages and return execution output.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "code": ["type": "string", "description": "Code content to execute"],
                        "language": ["type": "string", "description": "Language of code: python, bash, swift, etc."],
                        "stdin": ["type": "string", "description": "Optional standard input"]
                    ],
                    "required": ["code"]
                ]
            ],
            [
                "name": "microcode_open_snippet",
                "description": "Open a code snippet from Omni AI directly in the MicroCode IDE editor and optionally execute it.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "code": ["type": "string", "description": "Code snippet to open"],
                        "language": ["type": "string", "description": "Language of snippet"],
                        "action": ["type": "string", "description": "Action to perform: 'open' or 'open_and_run'"]
                    ],
                    "required": ["code", "language"]
                ]
            ],
            [
                "name": "microcode_sync_account",
                "description": "Sync user Google / Dotmini account credentials between Web and MicroCode Native IDE.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "email": ["type": "string", "description": "User email address"],
                        "token": ["type": "string", "description": "Session token or JWT"],
                        "display_name": ["type": "string", "description": "Display name"]
                    ],
                    "required": ["email"]
                ]
            ],
            [
                "name": "device_runtime",
                "description": "Inspect, control, and automate Android devices (physical & emulator via ADB) and iOS Simulators (via simctl). Operations: status, list_devices, start, run, stop, tap, swipe, type_text, key_event, screenshot, launch_app, install_app, adb_shell.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "operation": ["type": "string", "description": "Operation: status, list_devices, start, run, stop, tap, swipe, type_text, key_event, screenshot, launch_app, install_app, adb_shell"],
                        "device_id": ["type": "string", "description": "Target device serial or UDID"],
                        "x": ["type": "integer", "description": "X coordinate for tap or swipe start"],
                        "y": ["type": "integer", "description": "Y coordinate for tap or swipe start"],
                        "x2": ["type": "integer", "description": "X2 coordinate for swipe end"],
                        "y2": ["type": "integer", "description": "Y2 coordinate for swipe end"],
                        "duration": ["type": "integer", "description": "Swipe duration in ms"],
                        "text": ["type": "string", "description": "Text to type or fallback payload"],
                        "key": ["type": "string", "description": "Key code or name (HOME, BACK, ENTER, POWER, RECENT)"],
                        "package_name": ["type": "string", "description": "App package name or bundle ID"],
                        "file_path": ["type": "string", "description": "Screenshot destination path or APK/app path to install"],
                        "command": ["type": "string", "description": "ADB shell command to execute"]
                    ],
                    "required": ["operation"]
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
        
        // Fast-path tools that don't strictly require sandbox directory
        if name == "microcode_run_playground" {
            do {
                let res = try await executeRunPlayground(args)
                return MCPResponse(id: request.id, result: ["content": [["type": "text", "text": "\(res)"]]])
            } catch {
                return MCPResponse(id: request.id, result: ["content": [["type": "text", "text": "Error: \(error.localizedDescription)"]], "isError": true])
            }
        }
        if name == "microcode_open_snippet" {
            let res = await executeOpenSnippet(args)
            return MCPResponse(id: request.id, result: ["content": [["type": "text", "text": "\(res)"]]])
        }
        if name == "microcode_sync_account" {
            let res = executeSyncAccount(args)
            return MCPResponse(id: request.id, result: ["content": [["type": "text", "text": "\(res)"]]])
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
                result = try await executeGetDiagnostics(args)
            case "microcode_run_cell", "cell_run":
                result = try await executeRunCell(args, sandbox: sandbox)
            case "execute_code", "playground_run", "microcode_run_playground":
                result = try await executeRunPlayground(args)
            case "device_runtime":
                let op = args["operation"] as? String ?? "status"
                let devId = args["device_id"] as? String
                let x = (args["x"] as? NSNumber)?.intValue
                let y = (args["y"] as? NSNumber)?.intValue
                let x2 = (args["x2"] as? NSNumber)?.intValue
                let y2 = (args["y2"] as? NSNumber)?.intValue
                let dur = (args["duration"] as? NSNumber)?.intValue
                let txt = args["text"] as? String
                let key = args["key"] as? String
                let pkg = args["package_name"] as? String
                let path = args["file_path"] as? String
                let cmd = args["command"] as? String
                result = try await DeviceRuntimeService.shared.executeForAgent(
                    operation: op,
                    workspacePath: workspacePath,
                    deviceID: devId,
                    x: x, y: y, x2: x2, y2: y2, duration: dur,
                    text: txt, key: key, packageName: pkg, filePath: path, command: cmd
                )
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
    
    private func executeGetDiagnostics(_ args: [String: Any]) async throws -> String {
        guard let path = args["path"] as? String else {
            throw MCPError.custom("Missing 'path' argument")
        }
        
        let url = URL(fileURLWithPath: path)
        let uri = url.absoluteString
        
        return await MainActor.run {
            if let diagnostics = LSPManager.shared.fileDiagnostics[uri], !diagnostics.isEmpty {
                var output = "Diagnostics for \(url.lastPathComponent):\n\n"
                for diag in diagnostics {
                    let severityStr: String
                    switch diag.severity {
                    case 1: severityStr = "ERROR"
                    case 2: severityStr = "WARNING"
                    case 3: severityStr = "INFO"
                    case 4: severityStr = "HINT"
                    default: severityStr = "ISSUE"
                    }
                    
                    let line = diag.range.start.line + 1
                    let char = diag.range.start.character + 1
                    output += "[\(severityStr)] Line \(line):\(char) - \(diag.message)\n"
                }
                return output
            } else {
                return "No diagnostics or issues found for \(url.lastPathComponent)."
            }
        }
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
            let outputLock = NSLock()
            let completionLock = NSLock()
            var stdout = Data()
            var stderr = Data()
            var didTimeout = false
            var didResume = false
            let readers = DispatchGroup()

            func finish(_ result: Result<String, Error>) {
                completionLock.lock()
                defer { completionLock.unlock() }
                guard !didResume else { return }
                didResume = true
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }

            let timer = DispatchSource.makeTimerSource()
            timer.schedule(deadline: .now() + .seconds(timeout))
            timer.setEventHandler {
                outputLock.lock()
                didTimeout = true
                outputLock.unlock()
                process.terminate()
            }
            process.terminationHandler = { completedProcess in
                timer.cancel()
                readers.notify(queue: .global(qos: .utility)) {
                    outputLock.lock()
                    let outData = stdout
                    let errData = stderr
                    let timedOut = didTimeout
                    outputLock.unlock()

                    var output = String(data: outData, encoding: .utf8) ?? ""
                    let errorOutput = String(data: errData, encoding: .utf8) ?? ""
                    if !errorOutput.isEmpty {
                        output += output.isEmpty ? errorOutput : "\n" + errorOutput
                    }
                    if timedOut {
                        output += output.isEmpty ? "Command timed out after \(timeout) seconds" : "\nCommand timed out after \(timeout) seconds"
                    } else if completedProcess.terminationStatus != 0 && output.isEmpty {
                        output = "Command exited with code \(completedProcess.terminationStatus)"
                    }
                    if output.count > 50000 {
                        output = String(output.prefix(50000)) + "\n...[truncated]"
                    }
                    finish(.success(output))
                }
            }

            timer.resume()
            do {
                try process.run()
                for (handle, isStdout) in [(pipe.fileHandleForReading, true), (errPipe.fileHandleForReading, false)] {
                    readers.enter()
                    DispatchQueue.global(qos: .utility).async {
                        let data = handle.readDataToEndOfFile()
                        outputLock.lock()
                        if isStdout { stdout.append(data) } else { stderr.append(data) }
                        outputLock.unlock()
                        readers.leave()
                    }
                }
            } catch {
                timer.cancel()
                finish(.failure(error))
            }
        }
    }
    
    // MARK: - Omni AI & Playground Direct Execution

    private func executeRunPlayground(_ args: [String: Any]) async throws -> String {
        guard let code = args["code"] as? String, !code.isEmpty else {
            throw MCPToolError.missingParam("code")
        }
        let language = (args["language"] as? String ?? "python").lowercased()
        let stdin = args["stdin"] as? String ?? ""
        
        // Native Ardium execution
        if language == "ardium" || language == "ar" {
            var finalCode = code
            if !finalCode.contains("fn main(") && !finalCode.contains("func main(") {
                let trimmed = finalCode.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains("print") || trimmed.contains("println") || trimmed.contains("show(") {
                    finalCode = "fn main() {\n" + finalCode + "\n}"
                }
            }
            let res = await ArdiumRunner.execute(code: finalCode)
            var out = res.stdout
            if !res.stderr.isEmpty { out += (out.isEmpty ? "" : "\n") + res.stderr }
            let cleanPattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
            let cleanOut = out.replacingOccurrences(of: cleanPattern, with: "", options: .regularExpression)
            return cleanOut.isEmpty ? "(Executed with no output)" : cleanOut
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let ext: String
        switch language {
        case "swift": ext = "swift"
        case "python", "py", "python3": ext = "py"
        case "javascript", "js", "node": ext = "js"
        case "typescript", "ts": ext = "ts"
        case "go", "golang": ext = "go"
        case "rust", "rs": ext = "rs"
        case "cpp", "c++", "cc": ext = "cpp"
        case "c": ext = "c"
        case "objc", "objective-c", "m": ext = "m"
        case "objc++", "objective-cpp", "mm": ext = "mm"
        case "java": ext = "java"
        case "kotlin", "kt": ext = "kt"
        case "csharp", "cs", "dotnet": ext = "cs"
        case "php": ext = "php"
        case "ruby", "rb": ext = "rb"
        case "r", "rscript": ext = "R"
        case "julia", "jl": ext = "jl"
        case "zig": ext = "zig"
        case "dart": ext = "dart"
        case "lua": ext = "lua"
        case "scala": ext = "scala"
        case "perl", "pl": ext = "pl"
        case "haskell", "hs": ext = "hs"
        case "sh", "bash", "zsh": ext = "sh"
        case "sql": ext = "sql"
        default: ext = "txt"
        }
        
        let sourceFile = tempDir.appendingPathComponent("playground_exec_\(UUID().uuidString.prefix(8)).\(ext)")
        try code.write(to: sourceFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sourceFile) }
        
        var command = ""
        switch language {
        case "swift":
            command = "swift \(sourceFile.path.shellEscaped())"
        case "python", "py", "python3":
            command = "python3 \(sourceFile.path.shellEscaped())"
        case "javascript", "js", "node":
            command = "node \(sourceFile.path.shellEscaped())"
        case "typescript", "ts":
            command = "npx -y ts-node \(sourceFile.path.shellEscaped())"
        case "go", "golang":
            command = "go run \(sourceFile.path.shellEscaped())"
        case "rust", "rs":
            let bin = tempDir.appendingPathComponent("rust_bin_\(UUID().uuidString.prefix(8))").path
            command = "rustc \(sourceFile.path.shellEscaped()) -o \(bin.shellEscaped()) && \(bin.shellEscaped())"
        case "cpp", "c++", "cc":
            let bin = tempDir.appendingPathComponent("cpp_bin_\(UUID().uuidString.prefix(8))").path
            command = "clang++ -O2 -std=c++17 \(sourceFile.path.shellEscaped()) -o \(bin.shellEscaped()) && \(bin.shellEscaped())"
        case "c":
            let bin = tempDir.appendingPathComponent("c_bin_\(UUID().uuidString.prefix(8))").path
            command = "clang -O2 \(sourceFile.path.shellEscaped()) -o \(bin.shellEscaped()) && \(bin.shellEscaped())"
        case "objc", "objective-c", "m", "objc++", "objective-cpp", "mm":
            let bin = tempDir.appendingPathComponent("objc_bin_\(UUID().uuidString.prefix(8))").path
            command = "clang -framework Foundation \(sourceFile.path.shellEscaped()) -o \(bin.shellEscaped()) && \(bin.shellEscaped())"
        case "java":
            command = "java \(sourceFile.path.shellEscaped())"
        case "kotlin", "kt":
            let jar = tempDir.appendingPathComponent("kt_\(UUID().uuidString.prefix(8)).jar").path
            command = "kotlinc \(sourceFile.path.shellEscaped()) -include-runtime -d \(jar.shellEscaped()) && java -jar \(jar.shellEscaped())"
        case "csharp", "cs", "dotnet":
            command = "dotnet-script \(sourceFile.path.shellEscaped()) 2>/dev/null || csc \(sourceFile.path.shellEscaped()) -out:\(tempDir.path)/cs.exe && mono \(tempDir.path)/cs.exe 2>/dev/null || dotnet run"
        case "php":
            command = "php \(sourceFile.path.shellEscaped())"
        case "ruby", "rb":
            command = "ruby \(sourceFile.path.shellEscaped())"
        case "r", "rscript":
            command = "Rscript \(sourceFile.path.shellEscaped())"
        case "julia", "jl":
            command = "julia \(sourceFile.path.shellEscaped())"
        case "zig":
            command = "zig run \(sourceFile.path.shellEscaped())"
        case "dart":
            command = "dart run \(sourceFile.path.shellEscaped())"
        case "lua":
            command = "lua \(sourceFile.path.shellEscaped())"
        case "scala":
            command = "scala \(sourceFile.path.shellEscaped())"
        case "perl", "pl":
            command = "perl \(sourceFile.path.shellEscaped())"
        case "haskell", "hs":
            command = "runghc \(sourceFile.path.shellEscaped())"
        case "sh", "bash", "zsh":
            command = "bash \(sourceFile.path.shellEscaped())"
        case "sql":
            command = "sqlite3 :memory: < \(sourceFile.path.shellEscaped())"
        default:
            command = "bash \(sourceFile.path.shellEscaped())"
        }
        
        if !stdin.isEmpty {
            let stdinFile = tempDir.appendingPathComponent("stdin_\(UUID().uuidString.prefix(8)).txt")
            try stdin.write(to: stdinFile, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: stdinFile) }
            command += " < \(stdinFile.path.shellEscaped())"
        }
        
        return try await runShellCommand(command, cwd: tempDir.path, timeout: 30)
    }

    private func executeRunCell(_ args: [String: Any], sandbox: MCPSecuritySandbox) async throws -> String {
        return try await executeRunPlayground(args)
    }

    private func executeOpenSnippet(_ args: [String: Any]) async -> String {
        guard let code = args["code"] as? String else { return "Missing code" }
        let language = args["language"] as? String ?? "swift"
        let action = args["action"] as? String ?? "open_and_run"
        let shouldRun = (action == "open_and_run" || action == "run")
        
        // Post notification or run on main actor
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("MicroCodeOpenOmniAISnippet"),
                object: nil,
                userInfo: [
                    "code": code,
                    "language": language,
                    "shouldRun": shouldRun
                ]
            )
            NSApp.activate(ignoringOtherApps: true)
        }
        return "Opened snippet in MicroCode IDE (Language: \(language), AutoRun: \(shouldRun))"
    }

    private func executeSyncAccount(_ args: [String: Any]) -> String {
        guard let email = args["email"] as? String, !email.isEmpty else { return "Missing email" }
        let token = args["token"] as? String ?? ""
        let displayName = args["display_name"] as? String ?? ""
        
        AuthService.shared.syncWithWebSession(email: email, token: token, displayName: displayName)
        return "Account synced as \(email)"
    }

    // MARK: - Local HTTP Daemon Bridge for Omni AI & Web Apps

    private var httpListener: NWListener?

    func startLocalHttpBridge(port: UInt16 = 18888) {
        guard httpListener == nil else { return }
        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port) ?? 18888)
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }
            
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("⚡ MicroCode Local Daemon Bridge running on http://127.0.0.1:\(port)")
                case .failed(let err):
                    print("⚠️ MicroCode Local Bridge error: \(err)")
                default:
                    break
                }
            }
            
            listener.start(queue: DispatchQueue.global(qos: .userInitiated))
            self.httpListener = listener
        } catch {
            print("⚠️ Failed to start MicroCode HTTP Bridge: \(error)")
        }
    }

    func stopLocalHttpBridge() {
        httpListener?.cancel()
        httpListener = nil
    }

    nonisolated private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, _ in
            guard let self = self, let content = content, let requestString = String(data: content, encoding: .utf8) else {
                connection.cancel()
                return
            }
            
            Task { @MainActor in
                let responseData = await self.processHttpRequest(requestString)
                connection.send(content: responseData, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            }
        }
    }

    private func processHttpRequest(_ rawRequest: String) async -> Data {
        let lines = rawRequest.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return Data() }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return Data() }
        
        let method = parts[0].uppercased()
        let path = parts[1]
        
        let corsHeaders = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type, Authorization\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n"
        
        if method == "OPTIONS" {
            return corsHeaders.data(using: .utf8) ?? Data()
        }
        
        // Extract Body
        var bodyString = ""
        if let bodyIndex = rawRequest.range(of: "\r\n\r\n") {
            bodyString = String(rawRequest[bodyIndex.upperBound...])
        }
        
        if path.hasPrefix("/v1/run") && method == "POST" {
            if let bodyData = bodyString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                let code = json["code"] as? String ?? ""
                let lang = json["language"] as? String ?? "swift"
                
                // Account sync if provided
                if let email = json["email"] as? String, !email.isEmpty {
                    let token = json["token"] as? String ?? ""
                    let name = json["display_name"] as? String ?? ""
                    AuthService.shared.syncWithWebSession(email: email, token: token, displayName: name)
                }
                
                // Open and run in app
                _ = await self.executeOpenSnippet(["code": code, "language": lang, "action": "open_and_run"])
                
                let resp = ["success": true, "status": "executed_on_mac", "message": "Loaded and running on MicroCode IDE"] as [String : Any]
                let respBody = (try? JSONSerialization.data(withJSONObject: resp)) ?? Data()
                let httpResp = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\nContent-Length: \(respBody.count)\r\nConnection: close\r\n\r\n"
                var data = httpResp.data(using: .utf8) ?? Data()
                data.append(respBody)
                return data
            }
        }
        
        if path.hasPrefix("/v1/auth/sync") && method == "POST" {
            if let bodyData = bodyString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
               let email = json["email"] as? String {
                let token = json["token"] as? String ?? ""
                let name = json["display_name"] as? String ?? ""
                AuthService.shared.syncWithWebSession(email: email, token: token, displayName: name)
                
                let resp = ["success": true, "synced_email": email] as [String : Any]
                let respBody = (try? JSONSerialization.data(withJSONObject: resp)) ?? Data()
                let httpResp = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\nContent-Length: \(respBody.count)\r\nConnection: close\r\n\r\n"
                var data = httpResp.data(using: .utf8) ?? Data()
                data.append(respBody)
                return data
            }
        }
        
        if path.hasPrefix("/v1/status") || path == "/v1/health" {
            let user = AuthService.shared.currentUser?.email ?? "Guest (Unified Mode)"
            let resp = [
                "status": "ok",
                "app": "MicroCode Native IDE (macOS)",
                "user": user,
                "mcp_version": "2024-11-05"
            ]
            let respBody = (try? JSONSerialization.data(withJSONObject: resp)) ?? Data()
            let httpResp = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\nContent-Length: \(respBody.count)\r\nConnection: close\r\n\r\n"
            var data = httpResp.data(using: .utf8) ?? Data()
            data.append(respBody)
            return data
        }
        
        // Handle MCP SSE Handshake for Google Gemini Spark & Claude Web
        if (path.hasPrefix("/v1/mcp/sse") || path == "/v1/mcp" || path.hasPrefix("/v1/mcp?")) && method == "GET" {
            let sessionId = UUID().uuidString
            let endpointPayload = "event: endpoint\r\ndata: /v1/mcp/message?sessionId=\(sessionId)\r\n\r\n"
            let httpResp = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\nContent-Length: \(endpointPayload.utf8.count)\r\n\r\n\(endpointPayload)"
            return httpResp.data(using: .utf8) ?? Data()
        }
        
        // Handle MCP SSE Message Dispatch
        if path.hasPrefix("/v1/mcp/message") && method == "POST" {
            let mcpRespString = await self.handleRequest(bodyString)
            let ssePayload = "event: message\r\ndata: \(mcpRespString)\r\n\r\n"
            let httpResp = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\nContent-Length: \(ssePayload.utf8.count)\r\n\r\n\(ssePayload)"
            return httpResp.data(using: .utf8) ?? Data()
        }

        if path.hasPrefix("/v1/mcp") && method == "POST" {
            let mcpRespString = await self.handleRequest(bodyString)
            let respBody = mcpRespString.data(using: .utf8) ?? Data()
            let httpResp = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\nContent-Length: \(respBody.count)\r\nConnection: close\r\n\r\n"
            var data = httpResp.data(using: .utf8) ?? Data()
            data.append(respBody)
            return data
        }
        
        let notFound = "{\"error\": \"Not Found\"}"
        return ("HTTP/1.1 404 Not Found\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\nContent-Length: \(notFound.count)\r\nConnection: close\r\n\r\n" + notFound).data(using: .utf8) ?? Data()
    }
    
    private func log(_ detail: String, method: String, status: MCPLog.LogStatus) {
        let entry = MCPLog(method: method, status: status, detail: detail)
        logs.append(entry)
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
    }
    

    // MARK: - Gemini Spark & Dotmini Cloud MCP Helpers

    func getGeminiSparkURL() -> String {
        let token = UserDefaults.standard.string(forKey: "dotmini_cloud_token") ?? "mc_live_\(String(UUID().uuidString.prefix(8).lowercased()))"
        UserDefaults.standard.set(token, forKey: "dotmini_cloud_token")
        return "https://api.dotmini.net/v1/mcp?token=\(token)"
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
