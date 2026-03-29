import Foundation
import SwiftUI

// MARK: - Tool Definitions

struct AgentExecutorTool: Codable, Identifiable {
    var id: String { name }
    let name: String
    let description: String
    let parameters: [String: String] // Simple description of params
}

enum ToolExecutionResult {
    case success(String, [String: Any]? = nil)
    case failure(String)
}

// MARK: - Agent Tool Executor

class AgentToolExecutor: ObservableObject {
    static let shared = AgentToolExecutor()
    
    // Whitelisted tools that can be executed
    let availableTools: [AgentExecutorTool] = [
        AgentExecutorTool(
            name: "create_file",
            description: "Create a new file with content. Overwrites if exists.",
            parameters: ["path": "Absolute path", "content": "File content"]
        ),
        AgentExecutorTool(
            name: "edit_file",
            description: "Edit an existing file. Use for modifying code.",
            parameters: ["path": "Absolute path", "old_content": "Content to replace", "new_content": "Replacement content"]
        ),
        AgentExecutorTool(
            name: "delete_file",
            description: "Delete a file.",
            parameters: ["path": "Absolute path"]
        ),
        AgentExecutorTool(
            name: "read_file",
            description: "Read the contents of a file.",
            parameters: ["path": "Absolute path"]
        ),
        AgentExecutorTool(
            name: "list_directory",
            description: "List files and folders in a directory.",
            parameters: ["path": "Directory path"]
        ),
        AgentExecutorTool(
            name: "run_terminal",
            description: "Execute a command in the terminal.",
            parameters: ["command": "Command string", "cwd": "Current working directory (optional)"]
        ),
        AgentExecutorTool(
            name: "create_project",
            description: "Scaffold a new project structure.",
            parameters: ["name": "Project name", "type": "Project type (swift, python, node, etc.)", "path": "Parent directory"]
        )
    ]
    
    // MARK: - Execution
    
    func execute(toolName: String, params: [String: Any]) async -> ToolExecutionResult {
        print("🔧 Agent Executing: \(toolName) with \(params)")
        
        do {
            switch toolName {
            case "create_file":
                guard let path = params["path"] as? String,
                      let content = params["content"] as? String else {
                    return .failure("Missing path or content")
                }
                return try await createFile(path: path, content: content)
                
            case "edit_file":
                guard let path = params["path"] as? String,
                      let newContent = params["new_content"] as? String else {
                    return .failure("Missing path or new_content")
                }
                // Optional: Validate old_content if provided for strict checking
                return try await editFile(path: path, content: newContent)
                
            case "delete_file":
                guard let path = params["path"] as? String else { return .failure("Missing path") }
                return try await deleteFile(path: path)
                
            case "read_file":
                guard let path = params["path"] as? String else { return .failure("Missing path") }
                return try await readFile(path: path)
                
            case "list_directory":
                guard let path = params["path"] as? String else { return .failure("Missing path") }
                return try await listDirectory(path: path)
                
            case "run_terminal":
                guard let command = params["command"] as? String else { return .failure("Missing command") }
                let cwd = params["cwd"] as? String
                return try await runTerminal(command: command, cwd: cwd)
                
            case "create_project":
                guard let name = params["name"] as? String,
                      let type = params["type"] as? String,
                      let path = params["path"] as? String else {
                    return .failure("Missing project details (name, type, path)")
                }
                return try await createProject(name: name, type: type, path: path)
                
            default:
                return .failure("Unknown tool: \(toolName)")
            }
        } catch {
            return .failure("Execution error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - File Operations
    
    private func createFile(path: String, content: String) async throws -> ToolExecutionResult {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        
        // Notify file system watchers if any
        DispatchQueue.main.async {
            // Trigger UI refresh if needed
        }
        
        return .success("File created successfully: \(path)")
    }
    
    private func editFile(path: String, content: String) async throws -> ToolExecutionResult {
        let url = URL(fileURLWithPath: path)
        
        guard FileManager.default.fileExists(atPath: path) else {
            return .failure("File does not exist: \(path). Use create_file instead.")
        }
        
        // Read old content for diff
        let oldContent = try String(contentsOf: url, encoding: .utf8)
        
        try content.write(to: url, atomically: true, encoding: .utf8)
        
        return .success(
            "File updated successfully: \(path)",
            [
                "type": "edit_file",
                "path": path,
                "old_content": oldContent,
                "new_content": content
            ]
        )
    }
    
    private func deleteFile(path: String) async throws -> ToolExecutionResult {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(at: url)
            return .success("File deleted: \(path)")
        } else {
            return .failure("File not found: \(path)")
        }
    }
    
    private func readFile(path: String) async throws -> ToolExecutionResult {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            let content = try String(contentsOf: url, encoding: .utf8)
            // Truncate if too long to save context window
            if content.count > 10000 {
                let truncated = content.prefix(10000)
                return .success("\(truncated)\n... (truncated, file too large)")
            }
            return .success(content)
        } else {
            return .failure("File not found: \(path)")
        }
    }
    
    private func listDirectory(path: String) async throws -> ToolExecutionResult {
        let url = URL(fileURLWithPath: path)
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        
        let listing = contents.map { $0.lastPathComponent }.joined(separator: "\n")
        return .success("Contents of \(path):\n\(listing)")
    }
    
    // MARK: - Terminal Operations
    
    private func runTerminal(command: String, cwd: String?) async throws -> ToolExecutionResult {
        // Use local process execution
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        
        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        if process.terminationStatus == 0 {
            return .success(output.isEmpty ? "Command executed successfully (no output)" : output)
        } else {
            return .failure("Command failed with exit code \(process.terminationStatus):\n\(output)")
        }
    }
    
    // MARK: - Project Operations
    
    private func createProject(name: String, type: String, path: String) async throws -> ToolExecutionResult {
        let projectPath = (path as NSString).appendingPathComponent(name)
        let projectURL = URL(fileURLWithPath: projectPath)
        
        // Ensure directory doesn't exist
        if FileManager.default.fileExists(atPath: projectPath) {
            return .failure("Directory already exists: \(projectPath)")
        }
        
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        
        var message = "Project '\(name)' created at \(projectPath).\n"
        
        // Basic scaffolding based on type
        switch type.lowercased() {
        case "python":
            try await createFile(path: projectURL.appendingPathComponent("main.py").path, content: "print('Hello from \(name)!')\n")
            try await createFile(path: projectURL.appendingPathComponent("README.md").path, content: "# \(name)\n\nA Python project.")
            message += "Initialized with main.py and README.md"
            
        case "swift":
            try await createFile(path: projectURL.appendingPathComponent("main.swift").path, content: "print(\"Hello from \(name)!\")\n")
            try await createFile(path: projectURL.appendingPathComponent("README.md").path, content: "# \(name)\n\nA Swift project.")
             message += "Initialized with main.swift and README.md"
            
        case "node", "javascript":
            try await createFile(path: projectURL.appendingPathComponent("index.js").path, content: "console.log('Hello from \(name)!');\n")
            try await createFile(path: projectURL.appendingPathComponent("package.json").path, content: "{\n  \"name\": \"\(name)\",\n  \"version\": \"1.0.0\",\n  \"main\": \"index.js\"\n}")
             message += "Initialized with index.js and package.json"
            
        default:
            try await createFile(path: projectURL.appendingPathComponent("README.md").path, content: "# \(name)\n\nA generic project.")
            message += "Initialized with README.md (unknown type '\(type)')"
        }
        
        return .success(message)
    }
}
