//
//  AgentToolBox.swift
//  MicroCode
//
//  Production-Grade AI Agent ToolBox
//  Unified tool execution with sandbox validation + JSON Schema export
//

import Foundation
import AppKit
import PDFKit

// MARK: - Agent Tool Protocol

protocol AgentTool {
    var name: String { get }
    var description: String { get }
    var parameters: [ToolParameter] { get }
    
    func execute(params: [String: Any]) async throws -> String
}

struct ToolParameter {
    let name: String
    let type: String // "string", "integer", "boolean"
    let description: String
    let required: Bool
}

// MARK: - Agent ToolBox

@MainActor
class AgentToolBox: ObservableObject {
    static let shared = AgentToolBox()
    
    @Published var tools: [String: any AgentTool] = [:]
    @Published var executionHistory: [ToolExecution] = []
    private var readCache: [String: (value: String, date: Date)] = [:]
    private let readCacheTTL: TimeInterval = 3
    private let defaultToolTimeout: UInt64 = 45_000_000_000
    
    /// Workspace root — all file operations are sandboxed to this path
    var workspaceRoot: String? = nil
    
    init() {
        registerBuiltinTools()
    }
    
    private func registerBuiltinTools() {
        register(FileReadTool())
        register(FileWriteTool())
        register(FileSearchTool())
        register(GrepSearchTool())
        register(ReplaceInFileTool())
        register(ListDirectoryTreeTool())
        register(ShellCommandTool())
        register(GitStatusTool())
        register(WebFetchTool())
        register(CreateDirectoryTool())
        register(RenameFileTool())
        register(FindSymbolTool())
        register(PatchFileTool())
        register(MultiFileReadTool())
        register(GetDiagnosticsTool())
        register(ScienceInspectTool())
        register(AlphaFoldInputValidateTool())
        register(ArdiumRunTool())
        register(PlaygroundRunTool())
        register(CellRunTool())
        register(InspectImageTool())
        register(ExtractPDFTool())
        register(DefineSubagentTool())
        register(InvokeSubagentTool())
        register(ManageSubagentsTool())
        register(SendMessageTool())
    }
    
    func register(_ tool: any AgentTool) {
        tools[tool.name] = tool
    }
    
    func execute(_ toolName: String, params: [String: Any]) async throws -> String {
        guard let tool = tools[toolName] else {
            throw ToolBoxError.toolNotFound(toolName)
        }
        
        var resolvedParams = params
        
        // Auto-resolve relative paths
        if let root = workspaceRoot {
            let resolvePath = { (p: String) -> String in
                if p.hasPrefix("/") { return p }
                if p.hasPrefix("~") { return (p as NSString).expandingTildeInPath }
                return (root as NSString).appendingPathComponent(p)
            }
            
            if let path = params["path"] as? String {
                resolvedParams["path"] = resolvePath(path)
            }
            if let directory = params["directory"] as? String {
                resolvedParams["directory"] = resolvePath(directory)
            }
            if let pathsStr = params["paths"] as? String {
                let paths = pathsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                resolvedParams["paths"] = paths.map { resolvePath($0) }.joined(separator: ",")
            }
        }
        
        // Sandbox validation for file operations
        if ["file_read", "file_write", "replace_in_file", "grep_search", "list_directory_tree", "patch_file", "multi_file_read", "science_inspect", "alphafold_input_validate"].contains(toolName) {
            if let path = resolvedParams["path"] as? String ?? resolvedParams["directory"] as? String {
                try validateSandbox(path)
            }
        }
        
        let startTime = Date()
        let cacheKey = executionCacheKey(toolName: toolName, params: resolvedParams)
        let cacheable = ["file_read", "grep_search", "list_directory_tree", "git_status", "find_symbol", "multi_file_read", "get_diagnostics", "science_inspect", "alphafold_input_validate"].contains(toolName)
        if cacheable, let cached = readCache[cacheKey], Date().timeIntervalSince(cached.date) < readCacheTTL {
            TokenOptimizer.shared.recordContextCache(hit: true, tokens: TokenOptimizer.shared.estimateTokens(cached.value))
            return cached.value
        }
        if cacheable { TokenOptimizer.shared.recordContextCache(hit: false, tokens: 0) }
        
        do {
            let result = try await executeWithTimeout(tool: tool, params: resolvedParams)
            let execution = ToolExecution(toolName: toolName, params: resolvedParams, result: result, success: true, duration: Date().timeIntervalSince(startTime))
            executionHistory.append(execution)
            if executionHistory.count > 300 { executionHistory.removeFirst(executionHistory.count - 300) }
            if cacheable { readCache[cacheKey] = (result, Date()) }
            if ["file_write", "replace_in_file", "patch_file", "rename_file", "create_directory", "shell"].contains(toolName) {
                readCache.removeAll(keepingCapacity: true)
            }
            
            // Truncate very large outputs
            if result.count > 15000 {
                return String(result.prefix(15000)) + "\n\n... (output truncated at 15K chars)"
            }
            return result
        } catch {
            let execution = ToolExecution(toolName: toolName, params: params, result: error.localizedDescription, success: false, duration: Date().timeIntervalSince(startTime))
            executionHistory.append(execution)
            throw error
        }
    }

    private func executeWithTimeout(tool: any AgentTool, params: [String: Any]) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await tool.execute(params: params) }
            group.addTask {
                try await Task.sleep(nanoseconds: self.defaultToolTimeout)
                throw ToolBoxError.executionFailed("Tool timed out after 45 seconds")
            }
            guard let first = try await group.next() else {
                throw ToolBoxError.executionFailed("Tool returned no result")
            }
            group.cancelAll()
            return first
        }
    }

    private func executionCacheKey(toolName: String, params: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: params, options: [.sortedKeys])
        return toolName + ":" + (data.flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: params))
    }
    
    // MARK: - Sandbox Validation
    
    private func validateSandbox(_ path: String) throws {
        guard let root = workspaceRoot else { return } // No workspace = no restriction
        let resolved = (path as NSString).standardizingPath
        let rootResolved = (root as NSString).standardizingPath
        guard resolved.hasPrefix(rootResolved) || resolved.hasPrefix("/tmp") else {
            throw ToolBoxError.executionFailed("Path '\(path)' is outside the workspace. Access denied.")
        }
    }
    
    // MARK: - Tool Descriptions (for prompt injection)
    
    var toolDescriptions: String {
        tools.values.sorted(by: { $0.name < $1.name }).map { tool in
            let params = tool.parameters.map { "\($0.name): \($0.type)\($0.required ? " (required)" : "")" }.joined(separator: ", ")
            return "- \(tool.name)(\(params)): \(tool.description)"
        }.joined(separator: "\n")
    }
    
    // MARK: - JSON Schema Export (for native function calling)
    
    func toolSchemas() -> [[String: Any]] {
        tools.values.sorted(by: { $0.name < $1.name }).map { tool in
            var properties: [String: Any] = [:]
            var requiredParams: [String] = []
            
            for param in tool.parameters {
                properties[param.name] = [
                    "type": param.type,
                    "description": param.description
                ] as [String: Any]
                if param.required { requiredParams.append(param.name) }
            }
            
            return [
                "name": tool.name,
                "description": tool.description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": requiredParams
                ] as [String: Any]
            ] as [String: Any]
        }
    }
    
    var toolList: [any AgentTool] { Array(tools.values) }
}

struct ToolExecution: Identifiable {
    let id = UUID()
    let toolName: String
    let params: [String: Any]
    let result: String
    let success: Bool
    let duration: TimeInterval
    let timestamp = Date()
}

enum ToolBoxError: LocalizedError {
    case toolNotFound(String)
    case invalidParams(String)
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .toolNotFound(let name): return "Tool not found: \(name)"
        case .invalidParams(let msg): return "Invalid parameters: \(msg)"
        case .executionFailed(let msg): return "Execution failed: \(msg)"
        }
    }
}

// MARK: - Built-in Tools

struct FileReadTool: AgentTool {
    let name = "file_read"
    let description = "Read the contents of a file at the given path (supports code, text, Markdown, PDF, and image metadata)"
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Absolute or relative file path to read", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String else {
            throw ToolBoxError.invalidParams("path is required")
        }
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        
        // Specialized handler for PDF files
        if ext == "pdf" {
            guard let doc = PDFDocument(url: url) else {
                return "Error: Unable to open PDF document at '\(url.lastPathComponent)'"
            }
            var text = ""
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i), let pageString = page.string {
                    text += "--- [Page \(i + 1)] ---\n\(pageString)\n\n"
                }
            }
            if text.isEmpty {
                return "[PDF: \(url.lastPathComponent) (\(doc.pageCount) pages)] (No selectable text found, document may be scanned images)"
            }
            if text.count > 12000 {
                return String(text.prefix(12000)) + "\n\n... (PDF text truncated at 12K chars, total pages: \(doc.pageCount))"
            }
            return "[PDF: \(url.lastPathComponent) (\(doc.pageCount) pages)]\n\n\(text)"
        }
        
        // Specialized handler for Image files
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "bmp", "tiff"]
        if imageExtensions.contains(ext) {
            guard let data = try? Data(contentsOf: url), let img = NSImage(data: data) else {
                return "Error: Unable to decode image at '\(url.lastPathComponent)'"
            }
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            return """
            [Image Metadata]
            Filename: \(url.lastPathComponent)
            Format: \(ext.uppercased())
            Dimensions: \(Int(img.size.width)) × \(Int(img.size.height)) px
            File Size: \(sizeStr)
            Note: Use 'inspect_image' tool to run visual inspection or extract OCR.
            """
        }
        
        // Other non-text binary files
        let binaryExtensions = ["class", "zip", "tar", "gz", "mp3", "mp4", "exe", "dll", "dylib", "so", "bin", "dmg", "pkg"]
        if binaryExtensions.contains(ext) {
            return "Error: File '\(url.lastPathComponent)' is a binary archive/media file and cannot be read as text."
        }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            // Truncate only ridiculously massive files (>250K chars / ~6000 lines)
            if content.count > 250000 {
                return String(content.prefix(250000)) + "\n\n... (file truncated at 250K chars, total: \(content.count) chars)"
            }
            return content
        } catch {
            // Fallback for different encodings
            if let content = try? String(contentsOf: url, encoding: .isoLatin1) {
                if content.count > 250000 {
                    return String(content.prefix(250000)) + "\n\n... (file truncated at 250K chars, total: \(content.count) chars)"
                }
                return content
            }
            throw error
        }
    }
}

// MARK: - Vision & Multimodal Tools

struct InspectImageTool: AgentTool {
    let name = "inspect_image"
    let description = "Inspect and analyze an image file (PNG, JPG, WebP, SVG, HEIC). Uses Apple Neural Engine OCR & Vision to extract all text, UI code, layout boxes, and scene elements for any AI model."
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Absolute or relative file path to the image", required: true),
        ToolParameter(name: "query", type: "string", description: "Optional specific question or visual focus to inspect (e.g. 'check UI alignment', 'extract text', 'find error message')", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String else {
            throw ToolBoxError.invalidParams("path is required")
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return "Error: Image file not found at '\(path)'"
        }
        
        guard let data = try? Data(contentsOf: url) else {
            return "Error: Unable to read image data at '\(url.lastPathComponent)'"
        }
        
        let query = params["query"] as? String
        let visionResult = await AppleVisionEngine.shared.analyzeImage(data: data, filename: url.lastPathComponent)
        
        var output = visionResult.formattedSummary
        if let q = query, !q.isEmpty {
            output += "\n\n[Query Focus]: \(q)"
        }
        return output
    }
}

struct ExtractPDFTool: AgentTool {
    let name = "extract_pdf"
    let description = "Extract full text, page count, and document metadata from a PDF document."
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Absolute or relative file path to the PDF", required: true),
        ToolParameter(name: "page", type: "integer", description: "Optional 1-based page number to extract (default is all pages)", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String else {
            throw ToolBoxError.invalidParams("path is required")
        }
        let url = URL(fileURLWithPath: path)
        guard let doc = PDFDocument(url: url) else {
            return "Error: Unable to open PDF document at '\(path)'"
        }
        
        let totalPages = doc.pageCount
        var extracted = ""
        
        if let specificPage = params["page"] as? Int, specificPage >= 1 && specificPage <= totalPages {
            if let page = doc.page(at: specificPage - 1), let text = page.string {
                extracted = "--- [Page \(specificPage) of \(totalPages)] ---\n\(text)"
            }
        } else {
            for i in 0..<totalPages {
                if let page = doc.page(at: i), let text = page.string {
                    extracted += "--- [Page \(i + 1) of \(totalPages)] ---\n\(text)\n\n"
                }
            }
        }
        
        if extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "[PDF: \(url.lastPathComponent)] Document has \(totalPages) page(s), but contains no extractable text (it may be scanned/rasterized)."
        }
        
        if extracted.count > 15000 {
            return String(extracted.prefix(15000)) + "\n\n... (Output truncated at 15K chars, total pages: \(totalPages))"
        }
        
        return "[PDF: \(url.lastPathComponent) (\(totalPages) pages)]\n\n\(extracted)"
    }
}

struct FileWriteTool: AgentTool {
    let name = "file_write"
    let description = "Write content to a file, creating it if it doesn't exist"
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Absolute file path to write", required: true),
        ToolParameter(name: "content", type: "string", description: "Full content to write to the file", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String,
              let content = params["content"] as? String else {
            throw ToolBoxError.invalidParams("path and content are required")
        }
        let url = URL(fileURLWithPath: path)
        // Create parent directories if needed
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return "✅ Written \(content.count) chars to \(url.lastPathComponent)"
    }
}

struct ReplaceInFileTool: AgentTool {
    let name = "replace_in_file"
    let description = "Find and replace text in a file. Use this instead of file_write for targeted edits."
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Absolute file path", required: true),
        ToolParameter(name: "old_text", type: "string", description: "Exact text to find (must match exactly)", required: true),
        ToolParameter(name: "new_text", type: "string", description: "Replacement text", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String,
              let oldText = params["old_text"] as? String,
              let newText = params["new_text"] as? String else {
            throw ToolBoxError.invalidParams("path, old_text, and new_text are required")
        }
        
        let url = URL(fileURLWithPath: path)
        var content = try String(contentsOf: url, encoding: .utf8)
        
        guard content.contains(oldText) else {
            throw ToolBoxError.executionFailed("Could not find the specified text in \(url.lastPathComponent). Make sure old_text matches exactly.")
        }
        
        content = content.replacingOccurrences(of: oldText, with: newText)
        try content.write(to: url, atomically: true, encoding: .utf8)
        
        return "✅ Replaced text in \(url.lastPathComponent)"
    }
}

struct GrepSearchTool: AgentTool {
    let name = "grep_search"
    let description = "Search for a text pattern across files in a directory using grep"
    let parameters = [
        ToolParameter(name: "pattern", type: "string", description: "Search pattern (regex supported)", required: true),
        ToolParameter(name: "directory", type: "string", description: "Directory to search in", required: true),
        ToolParameter(name: "include", type: "string", description: "File glob pattern e.g. '*.swift'", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let pattern = params["pattern"] as? String,
              let directory = params["directory"] as? String else {
            throw ToolBoxError.invalidParams("pattern and directory are required")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        var args = ["-rn", "--color=never", "-I"] // recursive, line numbers, no color, skip binary
        if let include = params["include"] as? String {
            args.append(contentsOf: ["--include", include])
        }
        // Limit output
        args.append(contentsOf: ["-m", "50"]) // max 50 matches per file
        args.append(pattern)
        args.append(directory)
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // discard stderr
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        if output.isEmpty {
            return "No matches found for '\(pattern)' in \(directory)"
        }
        
        // Truncate if too many results
        if output.count > 8000 {
            return String(output.prefix(8000)) + "\n... (results truncated)"
        }
        return output
    }
}

struct ListDirectoryTreeTool: AgentTool {
    let name = "list_directory_tree"
    let description = "List the directory structure as a tree, showing files and folders"
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Directory path to list", required: true),
        ToolParameter(name: "max_depth", type: "integer", description: "Maximum depth (default: 3)", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String else {
            throw ToolBoxError.invalidParams("path is required")
        }
        
        let maxDepth = params["max_depth"] as? Int ?? 3
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        
        guard fm.fileExists(atPath: path) else {
            throw ToolBoxError.executionFailed("Path does not exist: \(path)")
        }
        
        var result = "\(url.lastPathComponent)/\n"
        result += buildTree(at: url, prefix: "", depth: 0, maxDepth: maxDepth, fm: fm)
        return result
    }
    
    private func buildTree(at url: URL, prefix: String, depth: Int, maxDepth: Int, fm: FileManager) -> String {
        guard depth < maxDepth else { return "" }
        
        guard let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return "" }
        
        let sorted = items.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result = ""
        
        for (i, item) in sorted.enumerated() {
            let isLast = i == sorted.count - 1
            let connector = isLast ? "└── " : "├── "
            let childPrefix = isLast ? "    " : "│   "
            
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            result += "\(prefix)\(connector)\(item.lastPathComponent)\(isDir ? "/" : "")\n"
            
            if isDir {
                result += buildTree(at: item, prefix: prefix + childPrefix, depth: depth + 1, maxDepth: maxDepth, fm: fm)
            }
        }
        return result
    }
}

struct FileSearchTool: AgentTool {
    let name = "file_search"
    let description = "Search for files matching a name pattern in a directory"
    let parameters = [
        ToolParameter(name: "directory", type: "string", description: "Directory to search", required: true),
        ToolParameter(name: "pattern", type: "string", description: "File name pattern (e.g. '*.swift')", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let directory = params["directory"] as? String,
              let pattern = params["pattern"] as? String else {
            throw ToolBoxError.invalidParams("directory and pattern are required")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        process.arguments = [directory, "-name", pattern, "-type", "f", "-maxdepth", "5"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

struct GetDiagnosticsTool: AgentTool {
    let name = "get_diagnostics"
    let description = "Get current editor diagnostics (errors, warnings) for a file via LSP."
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Absolute path to the file", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String else {
            throw ToolBoxError.invalidParams("Missing 'path'")
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
}

struct ShellCommandTool: AgentTool {
    let name = "shell"
    let description = "Execute a shell command in macOS Terminal and the IDE console. Use for building, testing, running CLI commands, or checking project state."
    let parameters = [
        ToolParameter(name: "command", type: "string", description: "Shell command to execute", required: true),
        ToolParameter(name: "cwd", type: "string", description: "Working directory (optional, defaults to active workspace folder)", required: false)
    ]
    
    /// Strict Safety Guard: Block blind/destructive commands from deleting user files
    static func validateSafety(_ command: String) throws {
        let dangerousPatterns = [
            #"rm\s+-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*\s+[/~*.]"#,
            #"rm\s+-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*\s+[/~*.]"#,
            #"rm\s+-[a-zA-Z]*r\s+[/~*.]"#,
            #"rm\s+-rf\s+\$HOME"#,
            #"rm\s+-rf\s+\*"#,
            #"rm\s+-rf\s+\.\*"#,
            #"rm\s+-rf\s+/\s*"#,
            #"find\s+.*\s+-delete"#,
            #">\s*/dev/sda"#,
            #"mkfs"#,
            #"dd\s+if=.*of=/dev"#,
            #"git\s+clean\s+-[a-zA-Z]*f[a-zA-Z]*d[a-zA-Z]*x"#,
            #"git\s+reset\s+--hard\s+head~[0-9]+"#
        ]
        
        for pattern in dangerousPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: command.utf16.count)
                if regex.firstMatch(in: command, options: [], range: range) != nil {
                    throw ToolBoxError.executionFailed("🛑 Safety Guard Blocked: Destructive command detected ('\(command)'). Blindly deleting user files, directories, or resetting git history is strictly prohibited.")
                }
            }
        }
    }
    
    func execute(params: [String: Any]) async throws -> String {
        guard let command = params["command"] as? String else {
            throw ToolBoxError.invalidParams("command is required")
        }
        
        // Enforce safety validation
        try Self.validateSafety(command)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        
        // Full macOS development toolchain PATH environment
        var env = ProcessInfo.processInfo.environment
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let extraPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(homeDir)/.cargo/bin",
            "\(homeDir)/.dotnet/tools",
            "\(homeDir)/.local/bin",
            "\(homeDir)/.nvm/current/bin"
        ].joined(separator: ":")
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = "\(extraPaths):\(currentPath)"
        env["TERM"] = "xterm-256color"
        env["LANG"] = "en_US.UTF-8"
        process.environment = env
        
        let targetCwd = (params["cwd"] as? String) ?? FileManager.default.currentDirectoryPath
        process.currentDirectoryURL = URL(fileURLWithPath: targetCwd)
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        try process.run()
        
        // Timeout: 45 seconds
        let deadline = DispatchTime.now() + .seconds(45)
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            if process.isRunning { process.terminate() }
        }
        
        process.waitUntilExit()
        
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        
        var output = stdout
        if !stderr.isEmpty { output += "\n[stderr]\n\(stderr)" }
        if process.terminationStatus != 0 { output = "[exit code: \(process.terminationStatus)]\n\(output)" }
        
        // Broadcast to IDE Terminal & Console
        NotificationCenter.default.post(
            name: NSNotification.Name("MicroCodeAgentTerminalCommand"),
            object: nil,
            userInfo: [
                "command": command,
                "output": output,
                "cwd": targetCwd,
                "exitCode": Int(process.terminationStatus)
            ]
        )
        
        // Truncate
        if output.count > 15000 { return String(output.prefix(15000)) + "\n... (truncated)" }
        return output
    }
}

struct GitStatusTool: AgentTool {
    let name = "git_status"
    let description = "Get git status of the current repository"
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Repository path", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String else {
            throw ToolBoxError.invalidParams("path is required")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["status", "--short"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? "No git status available"
    }
}

struct WebFetchTool: AgentTool {
    let name = "web_fetch"
    let description = "Fetch content from a URL"
    let parameters = [
        ToolParameter(name: "url", type: "string", description: "URL to fetch", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let urlStr = params["url"] as? String,
              let url = URL(string: urlStr) else {
            throw ToolBoxError.invalidParams("valid url is required")
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let content = String(data: data, encoding: .utf8) ?? ""
        
        if content.count > 5000 {
            return String(content.prefix(5000)) + "\n... (truncated)"
        }
        return content
    }
}

// MARK: - Enhanced Tools for Project Operations

struct CreateDirectoryTool: AgentTool {
    let name = "create_directory"
    let description = "Create a directory (and parent directories if needed)"
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Absolute path of the directory to create", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String else {
            throw ToolBoxError.invalidParams("path is required")
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return "✅ Created directory: \(url.lastPathComponent)"
    }
}

struct RenameFileTool: AgentTool {
    let name = "rename_file"
    let description = "Rename or move a file from one path to another"
    let parameters = [
        ToolParameter(name: "old_path", type: "string", description: "Current file path", required: true),
        ToolParameter(name: "new_path", type: "string", description: "New file path", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let oldPath = params["old_path"] as? String,
              let newPath = params["new_path"] as? String else {
            throw ToolBoxError.invalidParams("old_path and new_path are required")
        }
        
        let oldURL = URL(fileURLWithPath: oldPath)
        let newURL = URL(fileURLWithPath: newPath)
        
        // Create parent directory if needed
        try FileManager.default.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: oldURL, to: newURL)
        return "✅ Renamed: \(oldURL.lastPathComponent) → \(newURL.lastPathComponent)"
    }
}

struct FindSymbolTool: AgentTool {
    let name = "find_symbol"
    let description = "Find function, class, struct, or other symbol definitions in the workspace. Uses grep to search for common code patterns."
    let parameters = [
        ToolParameter(name: "symbol", type: "string", description: "Symbol name to find (function, class, struct name)", required: true),
        ToolParameter(name: "directory", type: "string", description: "Directory to search in", required: true),
        ToolParameter(name: "type", type: "string", description: "Symbol type: function, class, struct, enum, or all (default: all)", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let symbol = params["symbol"] as? String,
              let directory = params["directory"] as? String else {
            throw ToolBoxError.invalidParams("symbol and directory are required")
        }
        
        let symbolType = params["type"] as? String ?? "all"
        
        // Build pattern based on symbol type
        let patterns: [String]
        switch symbolType {
        case "function":
            patterns = ["func \\b\(symbol)\\b", "fn \\b\(symbol)\\b", "def \\b\(symbol)\\b", "function \\b\(symbol)\\b"]
        case "class":
            patterns = ["class \\b\(symbol)\\b", "interface \\b\(symbol)\\b"]
        case "struct":
            patterns = ["struct \\b\(symbol)\\b"]
        case "enum":
            patterns = ["enum \\b\(symbol)\\b"]
        default:
            patterns = ["\\b\(symbol)\\b"]
        }
        
        var allResults = ""
        for pattern in patterns {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
            process.arguments = ["-rn", "--color=never", "-I", "-E", "-m", "20", pattern, directory]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                allResults += output
            }
        }
        
        return allResults.isEmpty ? "No symbols matching '\(symbol)' found in \(directory)" : allResults
    }
}

struct PatchFileTool: AgentTool {
    let name = "patch_file"
    let description = "Apply multiple find-and-replace edits to a file in a single operation. More efficient than multiple replace_in_file calls."
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Absolute file path", required: true),
        ToolParameter(name: "edits", type: "string", description: "JSON array of edits: [{\"old\": \"text to find\", \"new\": \"replacement text\"}, ...]", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String,
              let editsStr = params["edits"] as? String else {
            throw ToolBoxError.invalidParams("path and edits are required")
        }
        
        let url = URL(fileURLWithPath: path)
        var content = try String(contentsOf: url, encoding: .utf8)
        
        // Parse edits JSON
        guard let editsData = editsStr.data(using: .utf8),
              let edits = try? JSONSerialization.jsonObject(with: editsData) as? [[String: String]] else {
            throw ToolBoxError.invalidParams("edits must be a valid JSON array of {old, new} objects")
        }
        
        var appliedCount = 0
        var failedEdits: [String] = []
        
        for edit in edits {
            guard let old = edit["old"], let new = edit["new"] else { continue }
            if content.contains(old) {
                content = content.replacingOccurrences(of: old, with: new)
                appliedCount += 1
            } else {
                failedEdits.append("Could not find: \(old.prefix(60))...")
            }
        }
        
        try content.write(to: url, atomically: true, encoding: .utf8)
        
        var result = "✅ Applied \(appliedCount)/\(edits.count) edits to \(url.lastPathComponent)"
        if !failedEdits.isEmpty {
            result += "\n⚠️ Failed edits:\n" + failedEdits.joined(separator: "\n")
        }
        return result
    }
}

struct MultiFileReadTool: AgentTool {
    let name = "multi_file_read"
    let description = "Read multiple files at once. More efficient than multiple file_read calls. Returns combined content with file headers."
    let parameters = [
        ToolParameter(name: "paths", type: "string", description: "Comma-separated list of absolute file paths to read", required: true),
        ToolParameter(name: "max_lines", type: "integer", description: "Maximum lines per file (default: 100)", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let pathsStr = params["paths"] as? String else {
            throw ToolBoxError.invalidParams("paths is required")
        }
        
        let maxLines = params["max_lines"] as? Int ?? 100
        let paths = pathsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        var result = ""
        var totalChars = 0
        let charBudget = 12000 // Total budget across all files
        
        for path in paths {
            guard totalChars < charBudget else {
                result += "\n--- (remaining files skipped - token budget reached) ---"
                break
            }
            
            let url = URL(fileURLWithPath: path)
            
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let lines = content.components(separatedBy: "\n")
                let limited = Array(lines.prefix(maxLines))
                let fileContent = limited.joined(separator: "\n")
                let truncated = lines.count > maxLines
                
                result += "\n═══ \(url.lastPathComponent) ═══\n"
                result += fileContent
                if truncated { result += "\n... (\(lines.count - maxLines) more lines)" }
                result += "\n"
                
                totalChars += fileContent.count
            } catch {
                result += "\n═══ \(url.lastPathComponent) ═══\n⚠️ Error: \(error.localizedDescription)\n"
            }
        }
        
        return result
    }
}

// MARK: - MCP Client for External Tools (Python MCP Server)

@MainActor
class MCPClient: ObservableObject {
    static let shared = MCPClient()
    
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stdoutBuffer = ""
    private var activeWorkspacePath: String?
    
    @Published var isConnected = false
    @Published var availableTools: [MCPToolSchema] = []
    
    private var pendingRequests: [Int: (Result<Any, Error>) -> Void] = [:]
    private var requestIdCounter = 1
    
    struct MCPToolSchema: Codable {
        let name: String
        let description: String
        let inputSchema: [String: AnyCodable]
    }
    
    func start(workspacePath: String) {
        if isConnected, activeWorkspacePath == workspacePath { return }
        if isConnected { stop() }
        
        let process = Process()
        
        var scriptPath = Bundle.main.path(forResource: "mcp-server", ofType: "py")
        if scriptPath == nil {
            scriptPath = FileManager.default.currentDirectoryPath + "/mcp-server.py"
        }
        
        guard let path = scriptPath, FileManager.default.fileExists(atPath: path) else {
            print("[MCPClient] Error: mcp-server.py not found")
            return
        }
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-u", path]
        
        var env = ProcessInfo.processInfo.environment
        env["MICROCODE_WORKSPACE"] = workspacePath
        process.environment = env
        
        let stdin = Pipe()
        let stdout = Pipe()
        
        process.standardInput = stdin
        process.standardOutput = stdout
        
        self.process = process
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.activeWorkspacePath = workspacePath
        self.stdoutBuffer = ""
        
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async {
                self?.handleOutput(data)
            }
        }
        
        do {
            try process.run()
            isConnected = true
            print("[MCPClient] Started mcp-server.py")
            
            sendRequest(method: "initialize", params: [:]) { result in
                switch result {
                case .success(let res):
                    print("[MCPClient] Initialized: \(res)")
                    self.sendNotification(method: "notifications/initialized")
                    self.fetchTools()
                case .failure(let err):
                    print("[MCPClient] Init Error: \(err)")
                }
            }
        } catch {
            print("[MCPClient] Failed to start process: \(error)")
        }
    }
    
    func stop() {
        let shutdownError = NSError(domain: "MCP", code: -2, userInfo: [NSLocalizedDescriptionKey: "MCP connection closed"])
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
        activeWorkspacePath = nil
        stdoutBuffer = ""
    }
    
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
                        callback(.failure(NSError(domain: "MCP", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])))
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
                domain: "MCP",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "MCP request '\(method)' timed out after \(Int(timeout)) seconds"]
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
            guard let self = self else { return }
            switch result {
            case .success(let res):
                if let dict = res as? [String: Any],
                   let toolsList = dict["tools"] as? [[String: Any]] {
                    
                    var parsedTools: [MCPToolSchema] = []
                    for t in toolsList {
                        if let name = t["name"] as? String,
                           let desc = t["description"] as? String,
                           let schema = t["inputSchema"] as? [String: Any],
                           let schemaData = try? JSONSerialization.data(withJSONObject: schema),
                           let parsedSchema = try? JSONDecoder().decode([String: AnyCodable].self, from: schemaData) {
                            parsedTools.append(MCPToolSchema(name: name, description: desc, inputSchema: parsedSchema))
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.availableTools = parsedTools
                        self.registerToolsWithAgent()
                    }
                }
            case .failure(let err):
                print("[MCPClient] Fetch Tools Error: \(err)")
            }
        }
    }
    
    private func registerToolsWithAgent() {
        for schema in availableTools {
            if AgentToolBox.shared.tools[schema.name] == nil {
                let proxyTool = DynamicMCPTool(mcpClient: self, schema: schema)
                AgentToolBox.shared.register(proxyTool)
                print("[MCPClient] Registered external MCP Tool: \(schema.name)")
            }
        }
    }
    
    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let params: [String: Any] = [
                "name": name,
                "arguments": arguments
            ]
            
            sendRequest(method: "tools/call", params: params, timeout: 45) { result in
                switch result {
                case .success(let res):
                    if let dict = res as? [String: Any],
                       let isError = dict["isError"] as? Bool, isError {
                        let content = (dict["content"] as? [[String: Any]])?.first?["text"] as? String ?? "Unknown error"
                        continuation.resume(throwing: NSError(domain: "MCP", code: -1, userInfo: [NSLocalizedDescriptionKey: content]))
                    } else if let dict = res as? [String: Any],
                              let contentArray = dict["content"] as? [[String: Any]],
                              let text = contentArray.first?["text"] as? String {
                        continuation.resume(returning: text)
                    } else {
                        continuation.resume(returning: "Success")
                    }
                case .failure(let err):
                    continuation.resume(throwing: err)
                }
            }
        }
    }
}

struct DynamicMCPTool: AgentTool {
    let mcpClient: MCPClient
    let schema: MCPClient.MCPToolSchema
    
    var name: String { schema.name }
    var description: String { schema.description }
    
    var parameters: [ToolParameter] {
        var params: [ToolParameter] = []
        if let properties = schema.inputSchema["properties"]?.value as? [String: Any] {
            let required = schema.inputSchema["required"]?.value as? [String] ?? []
            for (key, val) in properties {
                if let propDict = val as? [String: Any],
                   let type = propDict["type"] as? String,
                   let desc = propDict["description"] as? String {
                    params.append(ToolParameter(name: key, type: type, description: desc, required: required.contains(key)))
                }
            }
        }
        return params
    }
    
    func execute(params: [String: Any]) async throws -> String {
        return try await mcpClient.callTool(name: name, arguments: params)
    }
}

// MARK: - Native Ardium & Multi-Language Cell Tools

struct ArdiumRunTool: AgentTool {
    let name = "ardium_run"
    let description = "Execute Ardium source code (.ar) directly with native arc / ardium compiler and return standard output and errors."
    let parameters = [
        ToolParameter(name: "code", type: "string", description: "Ardium source code to execute", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let code = params["code"] as? String, !code.isEmpty else {
            throw ToolBoxError.invalidParams("code is required")
        }
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
}

struct PlaygroundRunTool: AgentTool {
    let name = "playground_run"
    let description = "Run code snippets directly in any language (Ardium, Swift, Python, JS, TS, Rust, Go, C++, C, ObjC, Java, C#, PHP, Ruby, R, Julia, Zig, Dart, Lua, Scala, Shell, SQL)."
    let parameters = [
        ToolParameter(name: "code", type: "string", description: "Source code to run", required: true),
        ToolParameter(name: "language", type: "string", description: "Programming language (e.g. 'ardium', 'python', 'swift', 'rust', 'go', 'cpp', 'csharp', 'r', 'julia', 'dart', 'zig', 'js', 'ts')", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let code = params["code"] as? String, !code.isEmpty else {
            throw ToolBoxError.invalidParams("code is required")
        }
        let language = (params["language"] as? String ?? "python").lowercased()
        if language == "ardium" || language == "ar" {
            return try await ArdiumRunTool().execute(params: ["code": code])
        }
        let shellTool = ShellCommandTool()
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
        case "objc", "m", "mm": ext = "m"
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
        
        let sourceFile = tempDir.appendingPathComponent("pg_run_\(UUID().uuidString.prefix(8)).\(ext)")
        try code.write(to: sourceFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sourceFile) }
        
        let cmd: String
        switch language {
        case "swift": cmd = "swift \(sourceFile.path.shellEscaped())"
        case "python", "py", "python3": cmd = "python3 \(sourceFile.path.shellEscaped())"
        case "javascript", "js", "node": cmd = "node \(sourceFile.path.shellEscaped())"
        case "typescript", "ts": cmd = "npx -y ts-node \(sourceFile.path.shellEscaped())"
        case "go", "golang": cmd = "go run \(sourceFile.path.shellEscaped())"
        case "rust", "rs":
            let bin = tempDir.appendingPathComponent("rs_\(UUID().uuidString.prefix(8))").path
            cmd = "rustc \(sourceFile.path.shellEscaped()) -o \(bin.shellEscaped()) && \(bin.shellEscaped())"
        case "cpp", "c++", "cc":
            let bin = tempDir.appendingPathComponent("cpp_\(UUID().uuidString.prefix(8))").path
            cmd = "clang++ -O2 -std=c++17 \(sourceFile.path.shellEscaped()) -o \(bin.shellEscaped()) && \(bin.shellEscaped())"
        case "c":
            let bin = tempDir.appendingPathComponent("c_\(UUID().uuidString.prefix(8))").path
            cmd = "clang -O2 \(sourceFile.path.shellEscaped()) -o \(bin.shellEscaped()) && \(bin.shellEscaped())"
        case "objc", "m", "mm":
            let bin = tempDir.appendingPathComponent("objc_\(UUID().uuidString.prefix(8))").path
            cmd = "clang -framework Foundation \(sourceFile.path.shellEscaped()) -o \(bin.shellEscaped()) && \(bin.shellEscaped())"
        case "java": cmd = "java \(sourceFile.path.shellEscaped())"
        case "csharp", "cs", "dotnet": cmd = "dotnet-script \(sourceFile.path.shellEscaped()) 2>/dev/null || dotnet run"
        case "php": cmd = "php \(sourceFile.path.shellEscaped())"
        case "ruby", "rb": cmd = "ruby \(sourceFile.path.shellEscaped())"
        case "r", "rscript": cmd = "Rscript \(sourceFile.path.shellEscaped())"
        case "julia", "jl": cmd = "julia \(sourceFile.path.shellEscaped())"
        case "zig": cmd = "zig run \(sourceFile.path.shellEscaped())"
        case "dart": cmd = "dart run \(sourceFile.path.shellEscaped())"
        case "lua": cmd = "lua \(sourceFile.path.shellEscaped())"
        case "scala": cmd = "scala \(sourceFile.path.shellEscaped())"
        case "perl", "pl": cmd = "perl \(sourceFile.path.shellEscaped())"
        case "haskell", "hs": cmd = "runghc \(sourceFile.path.shellEscaped())"
        case "sh", "bash", "zsh": cmd = "bash \(sourceFile.path.shellEscaped())"
        case "sql": cmd = "sqlite3 :memory: < \(sourceFile.path.shellEscaped())"
        default: cmd = "bash \(sourceFile.path.shellEscaped())"
        }
        return try await shellTool.execute(params: ["command": cmd, "cwd": tempDir.path])
    }
}

struct CellRunTool: AgentTool {
    let name = "cell_run"
    let description = "Run code within an interactive notebook cell or playground in any supported programming language."
    let parameters = [
        ToolParameter(name: "code", type: "string", description: "Source code to run in cell", required: true),
        ToolParameter(name: "language", type: "string", description: "Language of the cell", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        return try await PlaygroundRunTool().execute(params: params)
    }
}

// MARK: - SubAgent Harness Tools

struct DefineSubagentTool: AgentTool {
    let name = "define_subagent"
    let description = "Defines a new specialized SubAgent type/archetype with customized system prompt and restricted tool group."
    let parameters = [
        ToolParameter(name: "name", type: "string", description: "Unique identifier name for the subagent type (e.g. frontend_specialist)", required: true),
        ToolParameter(name: "role", type: "string", description: "Human-readable job role title (e.g. React UI Specialist)", required: true),
        ToolParameter(name: "description", type: "string", description: "Clear summary of when and how this subagent should be used", required: true),
        ToolParameter(name: "system_prompt", type: "string", description: "Specialized system instructions for this subagent", required: true),
        ToolParameter(name: "allowed_tools", type: "string", description: "Comma-separated list of allowed tool names (e.g. file_read,file_write,shell)", required: false),
        ToolParameter(name: "model", type: "string", description: "Model ID, or inherit to use the model selected in Settings", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let subName = params["name"] as? String, !subName.isEmpty else {
            throw ToolBoxError.invalidParams("name is required")
        }
        let role = params["role"] as? String ?? subName
        let desc = params["description"] as? String ?? ""
        let systemPrompt = params["system_prompt"] as? String ?? ""
        let toolsStr = params["allowed_tools"] as? String ?? ""
        let allowed = toolsStr.isEmpty ? [] : toolsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let model = params["model"] as? String ?? "inherit"
        
        let def = await MainActor.run {
            SubAgentHarness.shared.defineSubagent(
                name: subName,
                role: role,
                description: desc,
                systemPrompt: systemPrompt,
                allowedTools: allowed,
                model: model
            )
        }
        return "SubAgent archetype '\(def.name)' (\(def.role)) defined successfully."
    }
}

struct InvokeSubagentTool: AgentTool {
    let name = "invoke_subagent"
    let description = "Spawns a specialized SubAgent process in the background to execute a designated subtask concurrently."
    let parameters = [
        ToolParameter(name: "type_name", type: "string", description: "Name of the subagent archetype (e.g. architect, frontend_engineer, backend_engineer, bug_hunter, test_runner, security_auditor)", required: true),
        ToolParameter(name: "role", type: "string", description: "Brief role description for distinguishing this instance", required: true),
        ToolParameter(name: "prompt", type: "string", description: "Detailed subtask objective and instructions for the subagent", required: true),
        ToolParameter(name: "model", type: "string", description: "Optional model ID; defaults to the subagent definition or selected model", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let typeName = params["type_name"] as? String, !typeName.isEmpty else {
            throw ToolBoxError.invalidParams("type_name is required")
        }
        let role = params["role"] as? String ?? typeName
        let model = params["model"] as? String
        guard let prompt = params["prompt"] as? String, !prompt.isEmpty else {
            throw ToolBoxError.invalidParams("prompt is required")
        }
        
        let instance = await MainActor.run {
            let ws = AgentToolBox.shared.workspaceRoot
            return SubAgentHarness.shared.invokeSubagent(
                typeName: typeName,
                role: role,
                prompt: prompt,
                workspacePath: ws,
                preferredModel: model
            )
        }
        return "SubAgent #\(instance.id.prefix(6)) [\(role)] spawned in background with state: \(instance.state.displayName). Monitoring progress..."
    }
}

struct ManageSubagentsTool: AgentTool {
    let name = "manage_subagents"
    let description = "Monitors, checks status, or terminates running SubAgent processes (list, kill, kill_all)."
    let parameters = [
        ToolParameter(name: "action", type: "string", description: "Action to perform: 'list', 'kill', or 'kill_all'", required: true),
        ToolParameter(name: "target_id", type: "string", description: "ID of the subagent to kill (required when action is 'kill')", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        let action = (params["action"] as? String ?? "list").lowercased()
        let targetId = params["target_id"] as? String
        
        return await MainActor.run {
            switch action {
            case "list", "status":
                return SubAgentHarness.shared.getSubagentStatusSummary()
            case "kill":
                guard let id = targetId, !id.isEmpty else {
                    return "Error: target_id is required for 'kill' action."
                }
                SubAgentHarness.shared.killSubagent(id: id)
                return "SubAgent #\(id.prefix(6)) terminated."
            case "kill_all":
                SubAgentHarness.shared.killAllSubagents()
                return "All active SubAgents terminated."
            default:
                return "Unknown action: \(action). Available: list, kill, kill_all"
            }
        }
    }
}

struct SendMessageTool: AgentTool {
    let name = "send_message"
    let description = "Sends a message or directive to an active background SubAgent process."
    let parameters = [
        ToolParameter(name: "recipient_id", type: "string", description: "ID of the target SubAgent", required: true),
        ToolParameter(name: "message", type: "string", description: "Content of the instruction or update to send", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let recipientId = params["recipient_id"] as? String, !recipientId.isEmpty else {
            throw ToolBoxError.invalidParams("recipient_id is required")
        }
        guard let message = params["message"] as? String, !message.isEmpty else {
            throw ToolBoxError.invalidParams("message is required")
        }
        
        let success = await MainActor.run {
            SubAgentHarness.shared.sendMessage(recipientId: recipientId, message: message)
        }
        return success ? "Message delivered to SubAgent #\(recipientId.prefix(6))." : "SubAgent #\(recipientId.prefix(6)) not found."
    }
}
