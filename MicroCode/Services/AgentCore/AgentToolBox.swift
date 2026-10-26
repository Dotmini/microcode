//
//  AgentToolBox.swift
//  MicroCode
//
//  Production-Grade AI Agent ToolBox & Unified Tool Registry.
//  Provides autonomous execution for file management, visual regression,
//  runtime devices, AST inspection, LSP intelligence, and shell operations.
//  Tirawat Nantamas Founder and CEO of Dotmini Software.
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
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

// MARK: - Agent Execution Target

enum AgentExecutionTarget: Equatable {
    case local
    case remote(RemoteConnectionConfig)
    
    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }
    
    var remoteServer: RemoteConnectionConfig? {
        if case .remote(let config) = self { return config }
        return nil
    }
}

// MARK: - Agent ToolBox

@MainActor
class AgentToolBox: ObservableObject {
    static let shared = AgentToolBox()
    
    @Published var tools: [String: any AgentTool] = [:]
    @Published var executionHistory: [ToolExecution] = []
    @Published var executionTarget: AgentExecutionTarget = .local
    private var readCache: [String: (value: String, date: Date)] = [:]
    private let readCacheTTL: TimeInterval = 3
    // A compile, dependency install, or first Android build legitimately
    // outlives the old 45 second limit.  The runner reports its state instead
    // of silently cancelling it mid-build; individual shell calls still have
    // a bounded 10 minute ceiling to avoid an abandoned process lasting
    // forever.
    private let defaultToolTimeout: UInt64 = 600_000_000_000
    
    /// Workspace root — all file operations are sandboxed to this path
    var workspaceRoot: String? = nil
    
    init() {
        registerBuiltinTools()
        Task { @MainActor in
            let initialWs = self.workspaceRoot ?? UserDefaults.standard.string(forKey: "MicroCode.WorkspacePath") ?? FileManager.default.currentDirectoryPath
            MCPClient.shared.configure(workspacePath: initialWs)
        }
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
        register(ApplyPatchTool())
        register(MultiReplaceInFileTool())
        register(MultiFileReadTool())
        register(GetDiagnosticsTool())
        register(ScienceInspectTool())
        register(AlphaFoldInputValidateTool())
        register(ArdiumRunTool())
        register(PlaygroundRunTool())
        register(CellRunTool())
        register(InspectImageTool())
        register(ExtractPDFTool())
        register(AgentPlanTool())
        register(CreatePlanTool())
        register(DefineSubagentTool())
        register(InvokeSubagentTool())
        register(ManageSubagentsTool())
        register(SendMessageTool())
        register(DeviceRuntimeTool())
        register(PreviewControlTool())
        register(IDEBrowserTool())
        register(EditorControlTool())
        register(APIStudioTool())
        register(DatabaseStudioTool())
        register(VisualRegressionTool())
        register(RepoMapTool())
        // Feature 8: LSP Agent Bridge
        register(LSPHoverTool())
        register(LSPDefinitionTool())
        register(LSPCompletionsTool())
        register(LSPActiveDiagnosticsTool())
        register(LSPStatusTool())
        // Feature 9: Background Agent
        register(BackgroundAgentControlTool())
        // Feature 10: Voice Coding
        register(VoiceCodingTool())
        // Feature 11: Autonomous Skill Engine 2.0, Hyper-Mesh MCP 2.0 & SubAgent Swarm 2.0
        register(SkillEngineTool())
        register(MCPOrchestratorTool())
        register(SwarmOrchestratorTool())
        // Feature 12: TH-AI Passport Multimodal Generation (Image, Video, Music/Audio)
        register(GenerateImageTool())
        register(GenerateVideoTool())
        register(GenerateMusicTool())
    }
    
    func register(_ tool: any AgentTool) {
        tools[tool.name] = tool
    }
    
    nonisolated static func normalizeToolName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        switch lower {
        case "read_file", "view_file", "read", "cat", "open_file_content", "get_file_contents":
            return "file_read"
        case "write_file", "write_to_file", "create_file", "write", "save_file", "overwrite_file":
            return "file_write"
        case "edit_file", "str_replace", "str_replace_editor", "str_replace_based_edit_tool", "edit", "replace", "modify_file":
            return "replace_in_file"
        case "bash", "run_terminal_cmd", "execute_command", "run_command", "terminal", "exec", "cmd", "sh", "zsh", "run_shell":
            return "shell"
        case "list_dir", "list_directory", "ls", "list_files", "dir", "tree":
            return "list_directory_tree"
        case "grep", "ripgrep", "rg", "search_files", "search_in_files", "code_search", "grep_files":
            return "grep_search"
        case "glob", "find_by_name", "find_files", "search_by_name", "glob_search":
            return "file_search"
        case "mkdir", "make_directory":
            return "create_directory"
        case "mv", "move_file":
            return "rename_file"
        default:
            return trimmed
        }
    }

    nonisolated static func normalizeToolParams(_ params: [String: Any]) -> [String: Any] {
        var normalized = params
        for (key, rawVal) in params {
            guard let strVal = rawVal as? String else { continue }
            let trimmed = strVal.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
                if let data = trimmed.data(using: .utf8),
                   let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    for (innerK, innerV) in jsonObj {
                        normalized[innerK] = innerV
                    }
                    if let sameKeyVal = jsonObj[key] {
                        normalized[key] = sameKeyVal
                    }
                    continue
                }
                // Fallback for JSON strings with unescaped inner quotes, e.g. {"command":"ls -la || echo "no""}
                if let regex = try? NSRegularExpression(pattern: #"^\{\s*"([a-zA-Z0-9_]+)"\s*:\s*"([\s\S]*)"\s*\}$"#),
                   let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                   let kRange = Range(match.range(at: 1), in: trimmed),
                   let vRange = Range(match.range(at: 2), in: trimmed) {
                    let innerKey = String(trimmed[kRange])
                    let innerVal = String(trimmed[vRange])
                        .replacingOccurrences(of: #"\""#, with: "\"")
                        .replacingOccurrences(of: #"\\"#, with: "\\")
                    normalized[innerKey] = innerVal
                    if innerKey == key {
                        normalized[key] = innerVal
                    }
                    continue
                }
            }
            if ["path", "directory", "TargetFile", "AbsolutePath", "file_path", "filepath", "Path", "Directory", "old_path", "new_path", "cwd"].contains(key) {
                var cleanPath = trimmed
                if cleanPath.hasSuffix("\"}") {
                    cleanPath = String(cleanPath.dropLast(2))
                } else if cleanPath.hasSuffix("'}") {
                    cleanPath = String(cleanPath.dropLast(2))
                }
                if let r = cleanPath.range(of: #"^\{\s*"[a-zA-Z0-9_]+"\s*:\s*""#, options: .regularExpression) {
                    cleanPath = String(cleanPath[r.upperBound...])
                }
                normalized[key] = cleanPath
            }
        }

        // Map cross-provider parameter aliases to MicroCode canonical parameter names
        let aliasMappings: [(canonical: String, aliases: [String])] = [
            ("path", ["file_path", "filepath", "TargetFile", "AbsolutePath", "Path", "target_file", "filename"]),
            ("directory", ["dir", "folder", "search_path", "SearchPath", "Directory", "root_path"]),
            ("command", ["cmd", "CommandLine", "command_line", "bash_command", "shell_command"]),
            ("cwd", ["workdir", "working_directory", "working_dir", "Cwd"]),
            ("old_text", ["old_str", "old_string", "Target", "target", "search", "find_text"]),
            ("new_text", ["new_str", "new_string", "Replacement", "replacement", "replace_text"]),
            ("content", ["file_text", "Content", "contents", "new_content"]),
            ("pattern", ["Query", "Pattern", "glob", "regex", "search_term"]),
            ("start_line", ["StartLine", "offset", "line_start", "from_line"]),
            ("end_line", ["EndLine", "limit", "line_end", "to_line"])
        ]
        for mapping in aliasMappings {
            if normalized[mapping.canonical] == nil {
                for alias in mapping.aliases {
                    if let val = normalized[alias] {
                        normalized[mapping.canonical] = val
                        break
                    }
                }
            }
        }

        // Coerce integer parameters that may arrive as strings (e.g. from XML/DSML tool calls)
        for intKey in ["max_depth", "start_line", "end_line", "timeout", "page"] {
            if let strVal = normalized[intKey] as? String,
               let parsedInt = Int(strVal.trimmingCharacters(in: .whitespacesAndNewlines)) {
                normalized[intKey] = parsedInt
            }
        }

        return normalized
    }

    func execute(_ rawToolName: String, params: [String: Any]) async throws -> String {
        let toolName = Self.normalizeToolName(rawToolName)
        var targetTool = tools[toolName] ?? tools[rawToolName]
        if targetTool == nil {
            if toolName.hasPrefix("mcp__") {
                let candidate = toolName.replacingOccurrences(of: "mcp__", with: "mcp__local__")
                targetTool = tools[candidate]
            }
            if targetTool == nil {
                targetTool = tools["mcp__local__\(toolName)"]
            }
        }
        guard let tool = targetTool else {
            throw ToolBoxError.toolNotFound(rawToolName)
        }
        
        let executionWorkspace = workspaceRoot
        var resolvedParams = Self.normalizeToolParams(params)
        // Default directory/path to workspaceRoot for workspace-wide inspection tools when omitted
        if let root = workspaceRoot, !root.isEmpty {
            if ["list_directory_tree", "git_status"].contains(toolName),
               resolvedParams["path"] == nil && resolvedParams["directory"] == nil {
                resolvedParams["path"] = root
            } else if ["grep_search", "file_search", "find_symbol"].contains(toolName),
                      resolvedParams["directory"] == nil && resolvedParams["path"] == nil {
                resolvedParams["directory"] = root
            }
        }
        let isRemoteTarget: Bool = {
            if case .remote = executionTarget { return true }
            return false
        }()
        
        if !isRemoteTarget {
            // Auto-resolve relative paths against local workspaceRoot
            if let root = workspaceRoot {
                let resolvePath = { (p: String) -> String in
                    let trimmedP = p.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedP.isEmpty || trimmedP == "." || trimmedP == "./" {
                        return root
                    }
                    for containerPrefix in ["/workspace/", "/workspace", "/project/", "/project", "/repo/", "/repo"] {
                        if trimmedP == containerPrefix {
                            return root
                        }
                        if containerPrefix.hasSuffix("/") && trimmedP.hasPrefix(containerPrefix) {
                            let rel = String(trimmedP.dropFirst(containerPrefix.count))
                            return rel.isEmpty ? root : (root as NSString).appendingPathComponent(rel)
                        }
                    }
                    if trimmedP.hasPrefix("/") { return trimmedP }
                    if trimmedP.hasPrefix("~") { return (trimmedP as NSString).expandingTildeInPath }
                    let cleanRel = trimmedP.hasPrefix("./") ? String(trimmedP.dropFirst(2)) : trimmedP
                    return (root as NSString).appendingPathComponent(cleanRel)
                }
                
                for key in ["path", "directory", "old_path", "new_path", "cwd"] {
                    if let path = resolvedParams[key] as? String { resolvedParams[key] = resolvePath(path) }
                }
                if let pathsStr = resolvedParams["paths"] as? String {
                    let paths = pathsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    resolvedParams["paths"] = paths.map { resolvePath($0) }.joined(separator: ",")
                }
            }
            
            // Validate every declared local path, including list and rename arguments.
            let isReadOnlyFS = ["file_read", "multi_file_read", "list_directory_tree", "grep_search", "file_search"].contains(toolName)
            for key in ["path", "directory", "old_path", "new_path", "cwd"] {
                if let path = resolvedParams[key] as? String { try validateSandbox(path, allowGlobalReadOnly: isReadOnlyFS) }
            }
            if let paths = resolvedParams["paths"] as? String {
                for path in paths.components(separatedBy: ",") {
                    try validateSandbox(path.trimmingCharacters(in: .whitespacesAndNewlines), allowGlobalReadOnly: isReadOnlyFS)
                }
            }
        } else if let remoteBase = RemoteWorkspaceManager.shared.currentWorkspace?.remotePath, !remoteBase.isEmpty {
            let cleanBase = remoteBase.hasSuffix("/") ? String(remoteBase.dropLast()) : remoteBase
            let resolveRemotePath = { (p: String) -> String in
                if p.isEmpty || p.hasPrefix("/") || p.hasPrefix("~") { return p }
                return "\(cleanBase)/\(p)"
            }
            for key in ["path", "directory", "old_path", "new_path", "cwd"] {
                if let path = params[key] as? String {
                    // Do not forward local macOS /Users/... workspace path to remote Linux server
                    if let localRoot = workspaceRoot, path.hasPrefix(localRoot) {
                        let rel = path.replacingOccurrences(of: localRoot, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        resolvedParams[key] = rel.isEmpty ? cleanBase : "\(cleanBase)/\(rel)"
                    } else {
                        resolvedParams[key] = resolveRemotePath(path)
                    }
                }
            }
        }

        // Check tool approval
        let stringArgs = resolvedParams.compactMapValues { "\($0)" }
        let approved = await ToolApprovalManager.shared.requestApproval(
            toolName: toolName,
            arguments: stringArgs,
            description: tool.description
        )
        if !approved {
            throw ToolBoxError.executionFailed("Tool execution rejected by user")
        }
        
        try Task.checkCancellation()
        guard workspaceRoot == executionWorkspace else {
            throw ToolBoxError.executionFailed("Workspace changed while awaiting tool approval")
        }

        // Auto-commit safety net: checkpoint before file-modifying tools (local only)
        let fileModifyingTools: Set<String> = ["file_write", "replace_in_file", "patch_file", "apply_patch", "multi_replace_in_file", "rename_file", "create_directory", "shell"]
        let isMutatingCall: Bool = {
            guard fileModifyingTools.contains(toolName) else { return false }
            if toolName == "shell", let cmd = resolvedParams["command"] as? String {
                return !Self.isReadOnlyShellCommand(cmd)
            }
            return true
        }()
        if !isRemoteTarget && isMutatingCall {
            // Feature #4: Scope Lock & Protected Files Guard enforcement
            for key in ["path", "old_path", "new_path"] {
                if let targetFile = resolvedParams[key] as? String,
                   let blockReason = WorkspaceScopeGuard.shared.validateMutationAllowed(path: targetFile, workspaceRoot: workspaceRoot) {
                    throw ToolBoxError.executionFailed(blockReason)
                }
            }
            if let patchText = resolvedParams["patch"] as? String, let root = workspaceRoot {
                for line in patchText.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    var relPath: String? = nil
                    if trimmed.hasPrefix("*** Update File:") {
                        relPath = String(trimmed.dropFirst("*** Update File:".count)).trimmingCharacters(in: .whitespaces)
                    } else if trimmed.hasPrefix("*** Delete File:") {
                        relPath = String(trimmed.dropFirst("*** Delete File:".count)).trimmingCharacters(in: .whitespaces)
                    } else if trimmed.hasPrefix("--- a/") {
                        relPath = String(trimmed.dropFirst("--- a/".count)).trimmingCharacters(in: .whitespaces)
                    }
                    if let rel = relPath, !rel.isEmpty {
                        let absPath = rel.hasPrefix("/") ? rel : (root as NSString).appendingPathComponent(rel)
                        if let blockReason = WorkspaceScopeGuard.shared.validateMutationAllowed(path: absPath, workspaceRoot: workspaceRoot) {
                            throw ToolBoxError.executionFailed(blockReason)
                        }
                    }
                }
            }
            AutoCommitService.shared.workspaceRoot = workspaceRoot
            let targetPath = resolvedParams["path"] as? String ?? resolvedParams["directory"] as? String
            await AutoCommitService.shared.createCheckpoint(toolName: toolName, targetPath: targetPath)
        }
        
        let startTime = Date()
        let cacheKey = executionCacheKey(toolName: toolName, params: resolvedParams) + (isRemoteTarget ? "::remote" : "::local")
        let cacheable = ["file_read", "grep_search", "list_directory_tree", "git_status", "find_symbol", "multi_file_read", "get_diagnostics", "science_inspect", "alphafold_input_validate"].contains(toolName)
        if cacheable, let cached = readCache[cacheKey], Date().timeIntervalSince(cached.date) < readCacheTTL {
            TokenOptimizer.shared.recordContextCache(hit: true, tokens: TokenOptimizer.shared.estimateTokens(cached.value))
            return cached.value
        }
        if cacheable { TokenOptimizer.shared.recordContextCache(hit: false, tokens: 0) }
        
        do {
            let timeoutNs = defaultToolTimeout
            let rawResult: String
            if let server = executionTarget.remoteServer,
               let remoteHandled = try await executeRemoteToolIfApplicable(toolName: toolName, server: server, params: resolvedParams) {
                rawResult = await Task.detached(priority: .userInitiated) {
                    AgentPrivacyGuard.sanitize(remoteHandled)
                }.value
            } else {
                rawResult = try await executeWithTimeout(tool: tool, params: resolvedParams, timeoutNs: timeoutNs)
            }
            var result = rawResult
            let execution = ToolExecution(toolName: toolName, params: resolvedParams, result: result, success: true, duration: Date().timeIntervalSince(startTime))
            executionHistory.append(execution)
            if executionHistory.count > 300 { executionHistory.removeFirst(executionHistory.count - 300) }
            if cacheable { readCache[cacheKey] = (result, Date()) }
            if isMutatingCall {
                readCache.removeAll(keepingCapacity: true)
                if let path = resolvedParams["path"] as? String {
                    TokenOptimizer.shared.invalidateFileRead(path: path)
                } else {
                    TokenOptimizer.shared.beginTurnLoop()
                }
                if !isRemoteTarget, let path = resolvedParams["path"] as? String {
                    AutoCommitService.shared.modifiedFiles.insert(path)
                    // Feature #7: 1-Click Secret & API Key Leak Shield audit on modified source files
                    if let updatedContent = try? String(contentsOfFile: path, encoding: .utf8),
                       let secretWarning = SecretShieldMonitor.shared.inspectFileWrite(content: updatedContent, filePath: path) {
                        result += secretWarning
                    }
                    if RemoteWorkspaceManager.shared.currentWorkspace != nil {
                        await RemoteWorkspaceManager.shared.syncFile(localURL: URL(fileURLWithPath: path))
                    }
                }
            }
            
            // Allow rich tool outputs up to 2M characters (~500k tokens)
            if result.count > 2_000_000 {
                return String(result.prefix(2_000_000)) + "\n\n... (output truncated at 2M chars)"
            }
            return result
        } catch {
            let execution = ToolExecution(toolName: toolName, params: params, result: error.localizedDescription, success: false, duration: Date().timeIntervalSince(startTime))
            executionHistory.append(execution)
            throw error
        }
    }

    nonisolated static func posixQuote(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func isReadOnlyShellCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        // Any redirection (> or >>), tee, sed -i, rm, mv, cp, mkdir, touch, chmod, git commit/push/checkout/reset/stash/apply is mutating
        if trimmed.contains(" >") || trimmed.contains(">>") || trimmed.contains("| tee ") || trimmed.contains("sed -i") {
            return false
        }
        let segments = trimmed
            .components(separatedBy: CharacterSet(charactersIn: ";&|"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let readOnlyPrefixes = [
            "cd ", "ls", "pwd", "wc", "cat ", "head ", "tail ", "grep ", "egrep ", "fgrep ", "rg ",
            "sed -n", "awk ", "find ", "which ", "whereis ", "type ", "file ", "stat ", "du ", "df ",
            "echo ", "printf ", "env", "printenv", "uname", "whoami", "date", "ps ", "pgrep ",
            "git status", "git diff", "git log", "git show", "git branch", "git rev-parse", "git ls-files", "git remote"
        ]
        for seg in segments {
            if seg == "cd" || seg == "ls" || seg == "pwd" || seg == "wc" || seg == "env" || seg == "true" {
                continue
            }
            if !readOnlyPrefixes.contains(where: { seg == $0 || seg.hasPrefix($0) }) {
                return false
            }
        }
        return true
    }

    /// Executes filesystem, search, and git tools directly on the active Remote Server when executionTarget == .remote
    private func executeRemoteToolIfApplicable(
        toolName: String,
        server: RemoteConnectionConfig,
        params: [String: Any]
    ) async throws -> String? {
        let serverId = server.id.uuidString
        let shellTool = ShellCommandTool()
        
        func runRemoteShell(_ cmd: String) async throws -> String {
            var p = params
            p["command"] = cmd
            return try await shellTool.execute(params: p)
        }
        
        switch toolName {
        case "file_read":
            guard let path = params["path"] as? String, !path.isEmpty else {
                throw ToolBoxError.invalidParams("Missing 'path' parameter")
            }
            let content: String
            if let data = try? await BackendService.shared.downloadRemoteFile(id: serverId, path: path),
               let str = String(data: data, encoding: .utf8) {
                content = str
            } else {
                content = try await runRemoteShell("cat -- \(Self.posixQuote(path))")
            }
            let lines = content.components(separatedBy: "\n")
            let start = max(1, (params["start_line"] as? Int) ?? 1)
            let end = min(lines.count, (params["end_line"] as? Int) ?? lines.count)
            guard start <= end, !lines.isEmpty else { return content }
            return (start...end).map { "\($0): \(lines[$0 - 1])" }.joined(separator: "\n")
            
        case "multi_file_read":
            guard let pathsStr = params["paths"] as? String else {
                throw ToolBoxError.invalidParams("Missing 'paths' parameter")
            }
            let paths = pathsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            var outputs: [String] = []
            for p in paths {
                let text = (try? await executeRemoteToolIfApplicable(toolName: "file_read", server: server, params: ["path": p])) ?? "(Failed to read \(p))"
                outputs.append("=== \(p) ===\n\(text)")
            }
            return outputs.joined(separator: "\n\n")
            
        case "file_write":
            guard let path = params["path"] as? String,
                  let content = params["content"] as? String else {
                throw ToolBoxError.invalidParams("Missing 'path' or 'content'")
            }
            let parentDir = (path as NSString).deletingLastPathComponent
            if !parentDir.isEmpty && parentDir != "." && parentDir != "/" {
                _ = try? await runRemoteShell("mkdir -p -- \(Self.posixQuote(parentDir))")
            }
            let data = Data(content.utf8)
            do {
                try await BackendService.shared.uploadRemoteFile(id: serverId, path: path, content: data)
            } catch {
                let b64 = data.base64EncodedString()
                _ = try await runRemoteShell("printf '%s' \(Self.posixQuote(b64)) | base64 -d > \(Self.posixQuote(path))")
            }
            return "Successfully wrote \(data.count) bytes to remote \(path) on \(server.name)"
            
        case "replace_in_file", "patch_file":
            guard let path = params["path"] as? String else {
                throw ToolBoxError.invalidParams("Missing 'path'")
            }
            let search = (params["old_text"] as? String) ?? (params["search"] as? String) ?? (params["target"] as? String) ?? ""
            let replace = (params["new_text"] as? String) ?? (params["replace"] as? String) ?? (params["replacement"] as? String) ?? ""
            guard !search.isEmpty else {
                throw ToolBoxError.invalidParams("Missing search/old_text parameter")
            }
            let original: String
            if let data = try? await BackendService.shared.downloadRemoteFile(id: serverId, path: path),
               let str = String(data: data, encoding: .utf8) {
                original = str
            } else {
                original = try await runRemoteShell("cat -- \(Self.posixQuote(path))")
            }
            guard original.contains(search) else {
                throw ToolBoxError.executionFailed("Target text not found in remote file \(path)")
            }
            let updated = original.replacingOccurrences(of: search, with: replace)
            _ = try await executeRemoteToolIfApplicable(toolName: "file_write", server: server, params: ["path": path, "content": updated])
            return "Updated remote file \(path) on \(server.name)"
            
        case "create_directory":
            guard let path = (params["path"] as? String) ?? (params["directory"] as? String) else {
                throw ToolBoxError.invalidParams("Missing 'path'")
            }
            _ = try await runRemoteShell("mkdir -p -- \(Self.posixQuote(path))")
            return "Created remote directory \(path)"
            
        case "rename_file":
            guard let oldPath = (params["old_path"] as? String) ?? (params["source"] as? String),
                  let newPath = (params["new_path"] as? String) ?? (params["destination"] as? String) else {
                throw ToolBoxError.invalidParams("Missing 'old_path' or 'new_path'")
            }
            if (try? await BackendService.shared.remoteRename(id: serverId, source: oldPath, destination: newPath)) == nil {
                _ = try await runRemoteShell("mv -- \(Self.posixQuote(oldPath)) \(Self.posixQuote(newPath))")
            }
            return "Renamed remote \(oldPath) -> \(newPath)"
            
        case "list_directory_tree":
            let dir = (params["directory"] as? String) ?? (params["path"] as? String) ?? "."
            if let files = try? await BackendService.shared.listRemoteFiles(id: serverId, path: dir), !files.isEmpty {
                return files.map { "\($0.isDirectory ? "[DIR] " : "      ")\($0.name)" }.joined(separator: "\n")
            }
            return try await runRemoteShell("find \(Self.posixQuote(dir)) -maxdepth 3 -not -path '*/.*' | head -n 500")
            
        case "grep_search":
            guard let query = (params["query"] as? String) ?? (params["pattern"] as? String) else {
                throw ToolBoxError.invalidParams("Missing 'query' or 'pattern'")
            }
            let dir = (params["path"] as? String) ?? (params["directory"] as? String) ?? "."
            return try await runRemoteShell("grep -rnI --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=target -- \(Self.posixQuote(query)) \(Self.posixQuote(dir)) | head -n 200 || true")
            
        case "file_search":
            let pattern = (params["pattern"] as? String) ?? (params["query"] as? String) ?? "*"
            let dir = (params["directory"] as? String) ?? (params["path"] as? String) ?? "."
            return try await runRemoteShell("find \(Self.posixQuote(dir)) -not -path '*/.*' -iname \(Self.posixQuote("*\(pattern)*")) | head -n 200")
            
        case "find_symbol":
            guard let symbol = (params["symbol"] as? String) ?? (params["name"] as? String) else {
                throw ToolBoxError.invalidParams("Missing 'symbol'")
            }
            let dir = (params["directory"] as? String) ?? (params["path"] as? String) ?? "."
            return try await runRemoteShell("grep -rnIE --exclude-dir=.git --exclude-dir=node_modules -- \(Self.posixQuote("(func|class|struct|enum|def|interface|type|fn|let|const)\\s+\(symbol)\\b")) \(Self.posixQuote(dir)) | head -n 100 || true")
            
        case "git_status":
            let dir = (params["directory"] as? String) ?? (params["path"] as? String) ?? "."
            return try await runRemoteShell("git -C \(Self.posixQuote(dir)) status --short --branch && git -C \(Self.posixQuote(dir)) diff --stat")

        case "git_diff":
            let dir = (params["directory"] as? String) ?? "."
            if let file = params["path"] as? String, !file.isEmpty {
                return try await runRemoteShell("git -C \(Self.posixQuote(dir)) diff -- \(Self.posixQuote(file))")
            }
            return try await runRemoteShell("git -C \(Self.posixQuote(dir)) diff")

        case "file_delete", "delete_file":
            guard let path = params["path"] as? String, !path.isEmpty else {
                throw ToolBoxError.invalidParams("Missing 'path'")
            }
            if (try? await BackendService.shared.remoteRemove(id: serverId, path: path, isDirectory: false)) == nil {
                _ = try await runRemoteShell("rm -rf -- \(Self.posixQuote(path))")
            }
            return "Deleted remote path \(path) on \(server.name)"
            
        default:
            return nil
        }
    }

    /// Nonisolated multi-core execution wrapper so concurrent tool calls (e.g. `withTaskGroup` in `AgentService`)
    /// execute truly in parallel across Apple Silicon P-Cores/E-Cores without serializing on `@MainActor`.
    nonisolated private func executeWithTimeout(tool: any AgentTool, params: [String: Any], timeoutNs: UInt64) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask(priority: .userInitiated) {
                let raw = try await tool.execute(params: params)
                return AgentPrivacyGuard.sanitize(raw)
            }
            group.addTask(priority: .utility) {
                try await Task.sleep(nanoseconds: timeoutNs)
                throw ToolBoxError.executionFailed("Tool timed out after 10 minutes")
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
    
    private func validateSandbox(_ path: String, allowGlobalReadOnly: Bool = false) throws {
        guard let root = workspaceRoot, !root.isEmpty else {
            throw ToolBoxError.executionFailed("Open a workspace before accessing files")
        }
        if allowGlobalReadOnly {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let globalAgentDirs = [
                "\(home)/.gemini",
                "\(home)/.microcode",
                "\(home)/.agents",
                "\(home)/.codex",
                "\(home)/.claude",
                "\(home)/.cursor"
            ]
            for allowedDir in globalAgentDirs {
                if WorkspacePathPolicy.contains(path, in: allowedDir) {
                    return
                }
            }
        }
        guard WorkspacePathPolicy.contains(path, in: root) else {
            let rootName = URL(fileURLWithPath: root).lastPathComponent
            throw ToolBoxError.executionFailed("Strict Project Isolation Error: Path '\(path)' is outside the active project workspace '\(rootName)' (\(root)). AI is prohibited from modifying or reading files across different projects.")
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
        // TokenMem Layer 1: Exclude duplicate `mcp__local__*` wrappers when native built-in tools are registered.
        // The `mcp__local__*` tools remain registered in `tools` for execution compatibility,
        // but omitting their redundant schemas saves ~6,500 prompt tokens on every turn.
        let deduplicatedTools = tools.values.filter { tool in
            guard tool.name.hasPrefix("mcp__local__") else { return true }
            let baseName = String(tool.name.dropFirst("mcp__local__".count))
            if tools[baseName] != nil { return false }
            let coveredPrefixes = ["computer_use_", "device_", "adb_", "ardium_", "cell_", "lsp_", "git_"]
            if coveredPrefixes.contains(where: { baseName.hasPrefix($0) }) { return false }
            return true
        }
        
        return deduplicatedTools.sorted(by: { $0.name < $1.name }).map { tool in
            var properties: [String: Any] = [:]
            var requiredParams: [String: Any] = [:]
            _ = requiredParams
            var reqList: [String] = []
            
            for param in tool.parameters.sorted(by: { $0.name < $1.name }) {
                properties[param.name] = [
                    "type": param.type,
                    "description": param.description
                ] as [String: Any]
                if param.required { reqList.append(param.name) }
            }
            
            return [
                "name": tool.name,
                "description": tool.description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": reqList
                ] as [String: Any]
            ] as [String: Any]
        }
    }
    
    var toolList: [any AgentTool] { Array(tools.values) }
}

// MARK: - Durable Agent Plan

struct AgentPlanTool: AgentTool {
    let name = "agent_plan"
    let description = "Creates or advances the durable Rust-kernel plan and mirrors it to .microcode/task.md. Use set before complex work and complete only after deterministic verification."
    let parameters = [
        ToolParameter(name: "action", type: "string", description: "set or complete", required: true),
        ToolParameter(name: "plan_json", type: "string", description: "For set: JSON array of {id,title,description,dependencies,verification,required_tools,owner}", required: false),
        ToolParameter(name: "node_id", type: "string", description: "For complete: exact node ID", required: false),
        ToolParameter(name: "evidence", type: "string", description: "For complete: concise deterministic verification evidence", required: false),
        ToolParameter(name: "success", type: "boolean", description: "Whether the node verification passed", required: false)
    ]

    private struct InputNode: Decodable {
        let id: String
        let title: String
        let description: String?
        let dependencies: [String]?
        let verification: String?
        let required_tools: [String]?
        let owner: String?

        enum CodingKeys: String, CodingKey {
            case id, title, name, task, step, description, desc, dependencies, deps, depends_on, after, verification, required_tools, owner
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let stringID = try? container.decode(String.self, forKey: .id) {
                self.id = stringID
            } else if let intID = try? container.decode(Int.self, forKey: .id) {
                self.id = String(intID)
            } else {
                self.id = UUID().uuidString
            }

            self.title = (try? container.decode(String.self, forKey: .title))
                ?? (try? container.decode(String.self, forKey: .name))
                ?? (try? container.decode(String.self, forKey: .task))
                ?? (try? container.decode(String.self, forKey: .step))
                ?? "Task"

            self.description = (try? container.decode(String.self, forKey: .description))
                ?? (try? container.decode(String.self, forKey: .desc))

            if let deps = try? container.decode([String].self, forKey: .dependencies) {
                self.dependencies = deps
            } else if let intDeps = try? container.decode([Int].self, forKey: .dependencies) {
                self.dependencies = intDeps.map { String($0) }
            } else if let deps = try? container.decode([String].self, forKey: .deps) {
                self.dependencies = deps
            } else if let intDeps = try? container.decode([Int].self, forKey: .deps) {
                self.dependencies = intDeps.map { String($0) }
            } else if let deps = try? container.decode([String].self, forKey: .depends_on) {
                self.dependencies = deps
            } else {
                self.dependencies = []
            }

            self.verification = try? container.decode(String.self, forKey: .verification)
            self.required_tools = try? container.decode([String].self, forKey: .required_tools)
            self.owner = try? container.decode(String.self, forKey: .owner)
        }
    }

    func execute(params: [String: Any]) async throws -> String {
        let activeRunID = await MainActor.run(body: { AgentService.shared.currentKernelRunID })
        let runID = activeRunID ?? UUID().uuidString
        let action = (params["action"] as? String ?? "").lowercased()
        switch action {
        case "set":
            // Support direct markdown in set action
            let directMarkdown = (params["markdown"] as? String)
                ?? (params["plan_markdown"] as? String)
            if let markdown = directMarkdown, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let approved = await ImplementationPlanManager.shared.presentMarkdownPlan(markdown, title: "Execution Plan")
                guard approved else {
                    return "Plan was rejected by the user. Please revise the plan based on user feedback and resubmit."
                }
                return "Implementation plan APPROVED by the user. You may now proceed with code edits and execution."
            }

            let rawInput = params["plan_json"] ?? params["plan"] ?? params["nodes"]
            let data: Data?
            if let str = rawInput as? String {
                data = str.data(using: .utf8)
            } else if let obj = rawInput {
                data = try? JSONSerialization.data(withJSONObject: obj)
            } else {
                data = nil
            }
            guard let validData = data,
                  let input = try? JSONDecoder().decode([InputNode].self, from: validData),
                  !input.isEmpty else {
                throw ToolBoxError.invalidParams("plan_json must be a non-empty array of plan nodes")
            }

            let allIDs = Set(input.map { $0.id })
            let nodes = input.map { node in
                let validDeps = (node.dependencies ?? []).filter { dep in
                    allIDs.contains(dep) && dep != node.id
                }
                return AgentKernelPlanNode(
                    id: node.id,
                    title: node.title,
                    description: node.description ?? "",
                    dependencies: validDeps,
                    verification: (node.verification?.isEmpty == false) ? node.verification! : "Deterministic verification",
                    requiredTools: node.required_tools ?? [],
                    owner: node.owner
                )
            }
            // Present the plan to the user for approval via ImplementationPlanManager
            let planMarkdown = nodes.map { node -> String in
                let deps = node.dependencies.isEmpty ? "" : " — after: \(node.dependencies.joined(separator: ", "))"
                let verify = node.verification.isEmpty ? "" : "\n  - Verify: \(node.verification)"
                let owner = node.owner.map { "\n  - Owner: \($0)" } ?? ""
                return "- \(node.title)\(deps)\(verify)\(owner)"
            }.joined(separator: "\n")

            let fullMarkdown = """
            # Execution Plan

            \(planMarkdown)
            """

            let approved = await ImplementationPlanManager.shared.presentMarkdownPlan(fullMarkdown, title: "Execution Plan")

            guard approved else {
                return "Plan was rejected by the user. Please revise the plan based on user feedback and resubmit."
            }

            if let response = await AgentKernelClient.shared.setPlan(runID: runID, nodes: nodes) {
                try await mirrorTaskMarkdown(response.run.plan)
                let assignments = response.run.plan.compactMap { node -> String? in
                    guard response.directive.readyNodes.contains(node.id),
                          let owner = node.owner,
                          owner != "main" else { return nil }
                    return "\(node.id)→\(owner)"
                }
                let delegation = assignments.isEmpty
                    ? ""
                    : ". Delegate independent ready work with invoke_subagent: \(assignments.joined(separator: ", "))"
                return "Durable plan accepted. Ready nodes: \(response.directive.readyNodes.joined(separator: ", "))\(delegation)"
            } else {
                try await mirrorTaskMarkdown(nodes)
                return "Plan accepted and mirrored to .microcode/task.md"
            }

        case "complete":
            let rawNodeID = params["node_id"] ?? params["id"]
            let nodeID = (rawNodeID as? String) ?? (rawNodeID != nil ? String(describing: rawNodeID!) : "")
            guard !nodeID.isEmpty else {
                throw ToolBoxError.invalidParams("node_id is required")
            }
            let success = params["success"] as? Bool ?? false
            let evidence = params["evidence"] as? String ?? ""
            guard !success || !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ToolBoxError.invalidParams("verification evidence is required before completion")
            }
            guard let response = await AgentKernelClient.shared.observe(
                runID: runID,
                kind: success ? "plan_node_completed" : "verification",
                nodeID: nodeID,
                success: success,
                output: evidence,
                error: success ? "" : evidence,
                madeProgress: success
            ) else {
                throw ToolBoxError.executionFailed("Rust agent kernel did not update the plan node")
            }
            if success { try await markTaskNodeComplete(nodeID) }
            return success
                ? "Plan node \(nodeID) verified. Ready nodes: \(response.directive.readyNodes.joined(separator: ", "))"
                : "Plan node \(nodeID) failed verification; kernel directive: \(response.directive.reason)"

        default:
            throw ToolBoxError.invalidParams("action must be set or complete")
        }
    }

    @MainActor
    private func mirrorTaskMarkdown(_ nodes: [AgentKernelPlanNode]) throws {
        guard let workspace = AgentToolBox.shared.workspaceRoot else { return }
        let directory = URL(fileURLWithPath: workspace, isDirectory: true).appendingPathComponent(".microcode", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let lines = nodes.map { node -> String in
            let dependencies = node.dependencies.isEmpty ? "" : " — after: \(node.dependencies.joined(separator: ", "))"
            let verification = node.verification.isEmpty ? "" : "\n  - Verify: \(node.verification)"
            let owner = node.owner.map { "\n  - Owner: \($0)" } ?? ""
            return "- [ ] **\(node.id)** \(node.title)\(dependencies)\(verification)\(owner)"
        }
        let nodesMarkdown = lines.joined(separator: "\n")
        let markdown = """
        # Workspace Autonomous Task
        <!-- microcode:managed-task -->

        ## 📋 Active Execution Plan
        - **Status**: 🟡 IN_PROGRESS
        - **Plan Nodes**: \(nodes.count)
        - **Last Updated**: \(timestamp)

        ---

        ## 🚀 Structured Tasks & Verification Targets
        \(nodesMarkdown)

        ---

        ## 🛡️ Active Constraints & Safety Guidelines
        1. **Zero Secret Storage**: Never write passwords, keys, or auth tokens to this plan.
        2. **Deterministic Verification**: Verify each node with actual tool output before calling `agent_plan(action: "complete")`.
        3. **Strict Privacy**: Sanitize all outputs with `[REDACTED_SECRET_FOR_PRIVACY]`.

        ---

        ## 🔒 Privacy & Security Audit
        - [ ] Confirm no API keys or private tokens persisted in task records
        """
        let target = directory.appendingPathComponent("task.md")
        try AgentPrivacyGuard.safeWrite(content: markdown, to: target)
        NotificationCenter.default.post(name: NSNotification.Name("MicroCodeAgentWorkspaceFilesChanged"), object: nil)
    }

    @MainActor
    private func markTaskNodeComplete(_ nodeID: String) throws {
        guard let workspace = AgentToolBox.shared.workspaceRoot else { return }
        let target = URL(fileURLWithPath: workspace, isDirectory: true)
            .appendingPathComponent(".microcode/task.md")
        guard var markdown = try? String(contentsOf: target, encoding: .utf8) else { return }
        markdown = markdown.replacingOccurrences(of: "- [ ] **\(nodeID)**", with: "- [x] **\(nodeID)**")
        try AgentPrivacyGuard.safeWrite(content: markdown, to: target)
    }
}

// MARK: - Create Implementation Plan Tool

struct CreatePlanTool: AgentTool {
    let name = "create_plan"
    let description = "Creates a structured Implementation Plan and presents it to the user for explicit review and approval before mutating codebase files. Returns user approval status."
    let parameters = [
        ToolParameter(name: "title", type: "string", description: "Title of the implementation plan", required: true),
        ToolParameter(name: "markdown", type: "string", description: "Full implementation plan in markdown format. Include ### Sections, list of changes with [NEW], [MODIFY], [DELETE], ## Open Questions, and ## Verification steps.", required: true),
        ToolParameter(name: "summary", type: "string", description: "Short summary of the proposed plan", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        let title = (params["title"] as? String) ?? "Implementation Plan"
        let rawMarkdown = (params["markdown"] as? String)
            ?? (params["plan_markdown"] as? String)
            ?? (params["plan"] as? String)
            ?? (params["content"] as? String)
            ?? ""
        
        guard !rawMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolBoxError.invalidParams("markdown content is required for create_plan")
        }
        
        let approved = await ImplementationPlanManager.shared.presentMarkdownPlan(rawMarkdown, title: title)
        
        if approved {
            return "Implementation plan APPROVED by user. You may now proceed with code edits and executing the proposed changes."
        } else {
            return "Implementation plan REJECTED by user. Do NOT modify any files. Ask the user for feedback or propose a revised approach."
        }
    }
}

struct DeviceRuntimeTool: AgentTool {
    let name = "device_runtime"
    let description = "Full control and inspection for Android Emulators, iOS Simulators, and Physical Devices (via ADB/simctl). Supports: status, list_devices, start, run, stop, tap (x, y), swipe (x, y, x2, y2, duration), type_text (text), key_event (key), screenshot (file_path), launch_app (package_name), install_app (file_path), adb_shell (command)."
    let parameters = [
        ToolParameter(name: "operation", type: "string", description: "One of: status, list_devices, start, run, stop, tap, swipe, type_text, key_event, screenshot, launch_app, install_app, adb_shell", required: true),
        ToolParameter(name: "device_id", type: "string", description: "Optional device ID/serial (e.g. emulator-5554, avd:Pixel_9, iOS UDID, or physical device serial). Defaults to selected/first device.", required: false),
        ToolParameter(name: "x", type: "integer", description: "X pixel coordinate for tap or swipe start", required: false),
        ToolParameter(name: "y", type: "integer", description: "Y pixel coordinate for tap or swipe start", required: false),
        ToolParameter(name: "x2", type: "integer", description: "X2 pixel coordinate for swipe end", required: false),
        ToolParameter(name: "y2", type: "integer", description: "Y2 pixel coordinate for swipe end", required: false),
        ToolParameter(name: "duration", type: "integer", description: "Swipe duration in milliseconds (default: 200ms)", required: false),
        ToolParameter(name: "text", type: "string", description: "Text to type into focused input or fallback command", required: false),
        ToolParameter(name: "key", type: "string", description: "Key event code or name (e.g. KEYCODE_HOME, BACK, ENTER, POWER, 3, 4)", required: false),
        ToolParameter(name: "package_name", type: "string", description: "Android package name (e.g. com.example.app) or iOS bundle identifier", required: false),
        ToolParameter(name: "file_path", type: "string", description: "Path for screenshot output or app package to install (.apk / .app)", required: false),
        ToolParameter(name: "command", type: "string", description: "ADB shell command string to execute on target device", required: false),
        ToolParameter(name: "workspace", type: "string", description: "Optional workspace path; defaults to the current workspace", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        guard let operation = params["operation"] as? String else {
            throw ToolBoxError.invalidParams("operation is required")
        }
        let defaultWorkspace = await MainActor.run { AgentToolBox.shared.workspaceRoot }
        let workspace = params["workspace"] as? String ?? defaultWorkspace
        
        let x = params["x"] as? Int ?? (params["x"] as? Double).map { Int($0) }
        let y = params["y"] as? Int ?? (params["y"] as? Double).map { Int($0) }
        let x2 = params["x2"] as? Int ?? (params["x2"] as? Double).map { Int($0) }
        let y2 = params["y2"] as? Int ?? (params["y2"] as? Double).map { Int($0) }
        let duration = params["duration"] as? Int ?? (params["duration"] as? Double).map { Int($0) }
        let text = params["text"] as? String
        let key = params["key"] as? String
        let packageName = params["package_name"] as? String
        let filePath = params["file_path"] as? String
        let command = params["command"] as? String
        
        return try await DeviceRuntimeService.shared.executeForAgent(
            operation: operation,
            workspacePath: workspace,
            deviceID: params["device_id"] as? String,
            x: x,
            y: y,
            x2: x2,
            y2: y2,
            duration: duration,
            text: text,
            key: key,
            packageName: packageName,
            filePath: filePath,
            command: command
        )
    }
}

// MARK: - Visual Regression Testing Tool

struct VisualRegressionTool: AgentTool {
    let name = "visual_regression"
    let description = "Autonomous visual regression testing and UI snapshot comparison for WebApp preview, iOS Simulators, and Android Devices. Supports: 'compare' (compare current screen against stored baseline), 'save_baseline' (record new golden master baseline), 'list_baselines', and 'compare_images'."
    let parameters = [
        ToolParameter(name: "action", type: "string", description: "One of: 'compare', 'save_baseline', 'list_baselines', 'compare_images'", required: true),
        ToolParameter(name: "name", type: "string", description: "Name of the baseline or screen (e.g. 'HomeScreen', 'LoginModal', 'Dashboard')", required: false),
        ToolParameter(name: "image_path", type: "string", description: "Optional path to the image to test or save. If omitted for compare/save_baseline, automatically captures screenshot from active simulator/device.", required: false),
        ToolParameter(name: "expected_path", type: "string", description: "Path to baseline/expected image for 'compare_images'", required: false),
        ToolParameter(name: "actual_path", type: "string", description: "Path to actual/current image for 'compare_images'", required: false),
        ToolParameter(name: "threshold", type: "number", description: "Acceptable mismatch percentage threshold (default: 0.5%)", required: false),
        ToolParameter(name: "device_type", type: "string", description: "Device descriptor (e.g. 'ios_simulator', 'android_emulator', 'webapp')", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let action = (params["action"] as? String)?.lowercased() else {
            throw ToolBoxError.invalidParams("action is required ('compare', 'save_baseline', 'list_baselines', 'compare_images')")
        }
        
        switch action {
        case "list_baselines":
            let baselines = await MainActor.run { VisualRegressionService.shared.baselines }
            if baselines.isEmpty {
                return "No visual regression baselines recorded yet. Use action: 'save_baseline' with a screen name to create one."
            }
            var output = "Stored Visual Regression Baselines (\(baselines.count)):\n"
            for b in baselines {
                output += "• [\(b.name)] Screen: '\(b.screenName)' | Device: \(b.deviceName) (\(b.deviceType)) | Path: \(b.baselineImagePath)\n"
            }
            return output
            
        case "save_baseline":
            guard let name = params["name"] as? String, !name.isEmpty else {
                throw ToolBoxError.invalidParams("name is required for save_baseline")
            }
            let deviceType = params["device_type"] as? String ?? "simulator"
            
            let imagePath: String
            if let path = params["image_path"] as? String, !path.isEmpty {
                imagePath = path
            } else {
                let tmpPath = "\(NSTemporaryDirectory())vr_baseline_\(Int(Date().timeIntervalSince1970)).png"
                _ = try await DeviceRuntimeService.shared.executeForAgent(
                    operation: "screenshot",
                    workspacePath: nil,
                    deviceID: nil,
                    x: nil, y: nil, x2: nil, y2: nil, duration: nil,
                    text: nil, key: nil, packageName: nil,
                    filePath: tmpPath, command: nil
                )
                imagePath = tmpPath
            }
            
            guard let img = NSImage(contentsOfFile: imagePath) else {
                return "Error: Could not load image from '\(imagePath)' to save as baseline."
            }
            
            let baseline = await MainActor.run {
                VisualRegressionService.shared.saveBaseline(
                    image: img,
                    name: name,
                    deviceType: deviceType,
                    deviceName: deviceType,
                    screenName: name
                )
            }
            if let b = baseline {
                return "✅ Saved golden baseline '\(b.name)' (\(Int(img.size.width))x\(Int(img.size.height))) at: \(b.baselineImagePath)"
            } else {
                return "Error: Failed to save baseline."
            }
            
        case "compare":
            guard let name = params["name"] as? String, !name.isEmpty else {
                throw ToolBoxError.invalidParams("name is required for compare")
            }
            let threshold = (params["threshold"] as? Double) ?? (params["threshold"] as? Int).map { Double($0) } ?? 0.5
            
            let baseline = await MainActor.run {
                VisualRegressionService.shared.baselines.first { $0.name.lowercased() == name.lowercased() }
            }
            guard let baseline = baseline else {
                return "Error: No baseline found with name '\(name)'. Call list_baselines to see available baselines or save_baseline first."
            }
            
            let imagePath: String
            if let path = params["image_path"] as? String, !path.isEmpty {
                imagePath = path
            } else {
                let tmpPath = "\(NSTemporaryDirectory())vr_actual_\(Int(Date().timeIntervalSince1970)).png"
                _ = try await DeviceRuntimeService.shared.executeForAgent(
                    operation: "screenshot",
                    workspacePath: nil,
                    deviceID: nil,
                    x: nil, y: nil, x2: nil, y2: nil, duration: nil,
                    text: nil, key: nil, packageName: nil,
                    filePath: tmpPath, command: nil
                )
                imagePath = tmpPath
            }
            
            guard let actualImg = NSImage(contentsOfFile: imagePath) else {
                return "Error: Could not load actual image at '\(imagePath)'."
            }
            
            await MainActor.run { VisualRegressionService.shared.mismatchThreshold = threshold }
            let comparison = await MainActor.run {
                VisualRegressionService.shared.compare(actualImage: actualImg, baseline: baseline)
            }
            
            guard let comp = comparison else {
                return "Error: Comparison failed."
            }
            
            let passStr = comp.passed ? "PASSED ✅" : "FAILED ❌"
            var res = "Visual Regression [\(name)]: \(passStr)\n"
            res += "• Mismatch: \(String(format: "%.2f", comp.mismatchPercentage))% (Tolerance: \(threshold)%)\n"
            res += "• Mismatch Pixels: \(comp.mismatchPixels) / \(comp.totalPixels)\n"
            res += "• Actual Image: \(comp.actualImagePath)\n"
            if let diff = comp.diffImagePath {
                res += "• Diff Highlight Image: \(diff)\n"
            }
            return res
            
        case "compare_images":
            guard let expectedPath = params["expected_path"] as? String,
                  let actualPath = params["actual_path"] as? String else {
                throw ToolBoxError.invalidParams("expected_path and actual_path are required for compare_images")
            }
            guard let expectedImg = NSImage(contentsOfFile: expectedPath),
                  let actualImg = NSImage(contentsOfFile: actualPath) else {
                return "Error: Unable to load one or both images from disk."
            }
            let threshold = (params["threshold"] as? Double) ?? 0.5
            let dummyBaseline = SnapshotBaseline(
                name: "adhoc_compare",
                deviceType: "file",
                deviceName: "file",
                resolution: expectedImg.size,
                baselineImagePath: expectedPath
            )
            await MainActor.run { VisualRegressionService.shared.mismatchThreshold = threshold }
            let comp = await MainActor.run {
                VisualRegressionService.shared.compare(actualImage: actualImg, baseline: dummyBaseline)
            }
            if let comp = comp {
                let passStr = comp.passed ? "PASSED ✅" : "FAILED ❌"
                return "Image Comparison: \(passStr)\n• Mismatch: \(String(format: "%.2f", comp.mismatchPercentage))%\n• Diff Image: \(comp.diffImagePath ?? "None")"
            } else {
                return "Error: Image comparison could not be computed."
            }
            
        default:
            throw ToolBoxError.invalidParams("Unknown action '\(action)'")
        }
    }
}

// MARK: - Native Preview Control Tool

struct PreviewControlTool: AgentTool {
    let name = "preview_control"
    let description = "Directly control and inspect the IDE's live Embedded Preview Dock (WebApp, Apple Simulator, Android Device). Supports opening URLs (e.g. http://localhost:3000, Vite, Next.js), reloading pages, changing viewports (Desktop, Tablet, Mobile, Responsive), reading live JS console.error/warn & network logs, and taking screenshots."
    let parameters = [
        ToolParameter(name: "action", type: "string", description: "Action to perform: 'open', 'close', 'reload', 'set_url', 'switch_mode', 'set_viewport', 'status', 'console_logs', 'network_logs', 'inspect', 'screenshot'", required: true),
        ToolParameter(name: "url", type: "string", description: "Target URL for WebApp preview (e.g. http://localhost:3000, http://127.0.0.1:5173)", required: false),
        ToolParameter(name: "mode", type: "string", description: "Dock mode: 'web', 'ios', or 'android'", required: false),
        ToolParameter(name: "viewport", type: "string", description: "Viewport size: 'responsive', 'desktop', 'tablet', or 'mobile'", required: false)
    ]

    @MainActor
    private func livePreviewDiagnosticsSuffix() -> String {
        let browser = IDEBrowserAutomationService.shared
        let errors = browser.consoleLogs.filter { $0.level == "error" || $0.level == "warn" }.suffix(8)
        let failedNet = browser.failedNetworkEntries.suffix(5)
        guard !errors.isEmpty || !failedNet.isEmpty else {
            return "\n[Preview Console: 0 runtime errors]"
        }
        var lines: [String] = ["\n⚠️ [Live Preview Console / Network Telemetry]:"]
        for entry in errors {
            lines.append("  • [console.\(entry.level)] \(entry.message.prefix(240))")
        }
        for req in failedNet {
            lines.append("  • [network \(req.status)] \(req.method) \(req.url)")
        }
        return lines.joined(separator: "\n")
    }

    func execute(params: [String: Any]) async throws -> String {
        guard let action = (params["action"] as? String)?.lowercased() else {
            throw ToolBoxError.invalidParams("action is required")
        }
        let url = params["url"] as? String
        let mode = (params["mode"] as? String)?.lowercased()
        let viewport = (params["viewport"] as? String)?.lowercased()

        // Delegate rich inspection/console/screenshot actions directly to IDEBrowserAutomationService targeting the Preview WebView
        if ["console_logs", "console", "network_logs", "network", "inspect", "inspect_elements", "screenshot", "get_dom"].contains(action) {
            var forwarded = params
            forwarded["target"] = "preview"
            if action == "console" { forwarded["action"] = "console_logs" }
            if action == "network" { forwarded["action"] = "network_logs" }
            if action == "inspect" { forwarded["action"] = "inspect_elements" }
            return try await IDEBrowserAutomationService.shared.executeAction(params: forwarded)
        }

        return try await MainActor.run {
            let runtime = DeviceRuntimeService.shared

            switch action {
            case "open":
                runtime.showingEmbeddedDeviceDock = true
                if let mode = mode {
                    if mode == "web" {
                        runtime.embeddedDockMode = .web
                        PreviewDockService.shared.selectTab(id: "web")
                    } else if mode == "ios" {
                        runtime.embeddedDockMode = .ios
                        PreviewDockService.shared.selectTab(id: "ios")
                    } else if mode == "android" {
                        runtime.embeddedDockMode = .android
                        PreviewDockService.shared.selectTab(id: "android")
                    }
                } else {
                    runtime.embeddedDockMode = .web
                    PreviewDockService.shared.selectTab(id: "web")
                }
                if let urlString = url {
                    var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("http://file://") { trimmed = String(trimmed.dropFirst(7)) }
                    let parsedURL: URL? = (trimmed.hasPrefix("file://") || trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
                        ? URL(string: trimmed)
                        : (trimmed.hasPrefix("/") ? URL(fileURLWithPath: trimmed) : URL(string: "http://\(trimmed)"))
                    if let parsedURL = parsedURL {
                        runtime.targetWebURL = parsedURL
                    }
                }
                if let viewport = viewport {
                    runtime.targetViewport = viewport
                }
                return "✅ Live Preview Dock opened in \(runtime.embeddedDockMode.rawValue) mode\(url != nil ? " with URL: \(url!)" : "").\(livePreviewDiagnosticsSuffix())"

            case "close":
                runtime.showingEmbeddedDeviceDock = false
                PreviewDockService.shared.hideDock()
                return "✅ Live Preview Dock closed."

            case "reload", "refresh":
                runtime.showingEmbeddedDeviceDock = true
                PreviewDockService.shared.ensureDefaultTabsIfEmpty()
                if PreviewDockService.shared.activeTab == nil {
                    PreviewDockService.shared.selectTab(id: "web")
                }
                IDEBrowserAutomationService.shared.scanActivePorts()
                runtime.webRefreshTrigger.toggle()
                return "✅ Live Preview reload triggered.\(livePreviewDiagnosticsSuffix())"

            case "set_url":
                runtime.showingEmbeddedDeviceDock = true
                runtime.embeddedDockMode = .web
                PreviewDockService.shared.selectTab(id: "web")
                guard let urlString = url, !urlString.isEmpty else {
                    throw ToolBoxError.invalidParams("url is required for set_url action")
                }
                var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("http://file://") { trimmed = String(trimmed.dropFirst(7)) }
                let target: URL? = (trimmed.hasPrefix("file://") || trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
                    ? URL(string: trimmed)
                    : (trimmed.hasPrefix("/") ? URL(fileURLWithPath: trimmed) : URL(string: "http://\(trimmed)"))
                guard let target = target else {
                    throw ToolBoxError.invalidParams("Invalid URL format: \(urlString)")
                }
                runtime.targetWebURL = target
                return "✅ WebApp Preview URL navigated to: \(target.absoluteString)\(livePreviewDiagnosticsSuffix())"

            case "switch_mode":
                runtime.showingEmbeddedDeviceDock = true
                guard let mode = mode else {
                    throw ToolBoxError.invalidParams("mode is required ('web', 'ios', or 'android')")
                }
                switch mode {
                case "web":
                    runtime.embeddedDockMode = .web
                    PreviewDockService.shared.selectTab(id: "web")
                case "ios":
                    runtime.embeddedDockMode = .ios
                    PreviewDockService.shared.selectTab(id: "ios")
                case "android":
                    runtime.embeddedDockMode = .android
                    PreviewDockService.shared.selectTab(id: "android")
                default:
                    throw ToolBoxError.invalidParams("Unknown mode '\(mode)'. Use 'web', 'ios', or 'android'.")
                }
                return "✅ Switched Live Preview Dock to \(runtime.embeddedDockMode.rawValue) mode."

            case "set_viewport":
                guard let vp = viewport else {
                    throw ToolBoxError.invalidParams("viewport is required ('responsive', 'desktop', 'tablet', 'mobile')")
                }
                runtime.targetViewport = vp
                return "✅ WebApp Preview viewport set to: \(vp)"

            case "status":
                PreviewDockService.shared.ensureDefaultTabsIfEmpty()
                IDEBrowserAutomationService.shared.scanActivePorts()
                let activePorts = IDEBrowserAutomationService.shared.activePortProcesses.map { "\($0.port) (\($0.processName))" }
                if runtime.showingEmbeddedDeviceDock && PreviewDockService.shared.activeTab == nil {
                    PreviewDockService.shared.selectTab(id: "web")
                }
                let visible = runtime.showingEmbeddedDeviceDock ? "Visible" : "Hidden"
                let currentMode = runtime.embeddedDockMode.rawValue
                let currentURL = runtime.targetWebURL?.absoluteString ?? "http://localhost:3000"
                let portsInfo = activePorts.isEmpty ? "None detected yet" : activePorts.joined(separator: ", ")
                return "Live Preview Dock: \(visible) | Mode: \(currentMode) | URL: \(currentURL) | Active Ports: [\(portsInfo)] | Viewport: \(runtime.targetViewport)\(livePreviewDiagnosticsSuffix())"

            default:
                throw ToolBoxError.invalidParams("Unknown action '\(action)'. Supported: open, close, reload, set_url, switch_mode, set_viewport, status, console_logs, network_logs, inspect, screenshot")
            }
        }
    }
}

// MARK: - Native IDE Browser & WebEngine Automation Tool

struct IDEBrowserTool: AgentTool {
    let name = "ide_browser"
    let description = "Control and inspect MicroCode's built-in IDE Browser and Live WebApp Preview (WebKit). Supports navigating to URLs, inspecting interactive DOM elements with selectors & bounding boxes, reading DOM text/HTML, clicking elements, typing into inputs (React/Vue compatible), evaluating JavaScript, reading live console.log/error & fetch/XHR network logs, and taking high-res PNG snapshots."
    let parameters = [
        ToolParameter(name: "action", type: "string", description: "Action: 'navigate', 'inspect_elements', 'get_dom', 'click', 'type', 'eval_js', 'console_logs', 'network_logs', 'screenshot', or 'status'", required: true),
        ToolParameter(name: "target", type: "string", description: "Target WebView: 'auto' (default), 'browser' (IDE Browser), or 'preview' (Live WebApp Preview Dock)", required: false),
        ToolParameter(name: "url", type: "string", description: "URL to open (for 'navigate')", required: false),
        ToolParameter(name: "selector", type: "string", description: "CSS selector or button text (for 'click', 'type', 'get_dom')", required: false),
        ToolParameter(name: "text", type: "string", description: "Text to type into input (for 'type')", required: false),
        ToolParameter(name: "submit", type: "boolean", description: "Submit form after typing (for 'type')", required: false),
        ToolParameter(name: "script", type: "string", description: "JavaScript expression to evaluate in page (for 'eval_js')", required: false),
        ToolParameter(name: "format", type: "string", description: "'text' or 'html' (for 'get_dom')", required: false),
        ToolParameter(name: "level", type: "string", description: "Console filter: 'error', 'warn', 'info', 'log' (for 'console_logs')", required: false),
        ToolParameter(name: "clear", type: "boolean", description: "Clear buffered logs after reading (for 'console_logs' / 'network_logs')", required: false),
        ToolParameter(name: "output_path", type: "string", description: "PNG file path (for 'screenshot')", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        return try await IDEBrowserAutomationService.shared.executeAction(params: params)
    }
}

struct EditorControlTool: AgentTool {
    let name = "editor_control"
    let description = "Inspect and control the active MicroCode IDE Editor tabs, active file, cursor state, first-launch onboarding, and workspace navigation."
    let parameters = [
        ToolParameter(name: "action", type: "string", description: "Action: 'status', 'open_file', 'list_tabs', 'switch_mode', 'simulate_first_launch', 'dismiss_welcome', 'open_connections', 'close_connections', 'restore_normal_state'", required: true),
        ToolParameter(name: "path", type: "string", description: "File path to open in editor (for 'open_file')", required: false),
        ToolParameter(name: "mode", type: "string", description: "IDE mode: 'editor', 'browser', 'notebook', 'playground', 'agent', 'science' (for 'switch_mode')", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        let action = (params["action"] as? String ?? "status").lowercased()
        return await MainActor.run {
            guard let appState = AppState.shared else {
                return "AppState not initialized."
            }
            switch action {
            case "status":
                let activeTab = appState.currentFile?.name ?? "None"
                let activePath = appState.currentFile?.path ?? "None"
                let openTabs = appState.openFiles.map { "\($0.name) (\($0.path))" }.joined(separator: ", ")
                return "Mode: \(appState.editorMode.displayName) | Active File: \(activeTab) (\(activePath)) | Open Files (\(appState.openFiles.count)): [\(openTabs)] | Workspace: \(appState.workspaceFolder?.path ?? "None") | AI Connected: \(appState.isCurrentAIConnected) | Welcome Overlay: \(appState.showingFirstLaunchWelcome)"
            case "list_tabs":
                if appState.openFiles.isEmpty { return "No open editor files." }
                return appState.openFiles.enumerated().map { idx, t in
                    "\(idx == appState.currentFileIndex ? "▶ " : "  ")[\(idx)] \(t.name) — \(t.path)\(t.isUnsaved ? " (unsaved)" : "")"
                }.joined(separator: "\n")
            case "open_file":
                guard let path = params["path"] as? String, !path.isEmpty else {
                    return "Error: 'path' is required for open_file"
                }
                let ws = appState.activeTerminalDirectory
                let fullPath = path.hasPrefix("/") ? path : (ws as NSString).appendingPathComponent(path)
                appState.showingWelcomeHome = false
                appState.switchToMode(.code)
                Task { @MainActor in
                    await appState.loadFile(url: URL(fileURLWithPath: fullPath))
                }
                return "✅ Opened file in MicroCode Editor: \(fullPath)"
            case "switch_mode":
                let mode = (params["mode"] as? String ?? "").lowercased()
                if mode == "welcome" || mode == "home" {
                    appState.switchToMode(.code)
                    appState.showingWelcomeHome = true
                    return "✅ Switched IDE to Welcome Home Screen."
                }
                appState.showingWelcomeHome = false
                if mode == "browser" {
                    appState.switchToMode(.browser)
                    return "✅ Switched IDE to Browser Mode."
                } else if mode == "editor" || mode == "code" {
                    appState.switchToMode(.code)
                    return "✅ Switched IDE to Code Editor Mode."
                } else if mode == "notebook" || mode == "cells" {
                    appState.switchToMode(.notebook)
                    return "✅ Switched IDE to Notebook Mode."
                } else if mode == "playground" {
                    appState.switchToMode(.playground)
                    return "✅ Switched IDE to Playground Mode."
                } else if mode == "agent" || mode == "ai" {
                    appState.switchToMode(.aiAgent)
                    return "✅ Switched IDE to AI Agent Mode."
                } else if mode == "science" {
                    appState.switchToMode(.science)
                    return "✅ Switched IDE to Science Mode."
                } else if mode == "api" || mode == "apistudio" || mode == "api_studio" {
                    appState.switchToMode(.apiClient)
                    return "✅ Switched IDE to API Studio Mode."
                }
                return "Unknown mode '\(mode)'."
            case "simulate_first_launch":
                if appState.savedChatIdBeforeSimulation == nil {
                    appState.savedChatIdBeforeSimulation = AgentService.shared.activeChatId
                }
                appState.simulateUnconnectedAI = true
                let newChat = AgentService.shared.createNewChat(projectPath: appState.workspaceFolder?.path)
                appState.tempSimulationChatId = newChat.id
                appState.hidePreviewInspector()
                PreviewDockService.shared.hideDock()
                DeviceRuntimeService.shared.showingEmbeddedDeviceDock = false
                appState.switchToMode(.code)
                appState.showingWelcomeHome = true
                appState.showingFirstLaunchWelcome = true
                return "✅ Simulated First-Launch Welcome with No AI Connected."
            case "dismiss_welcome":
                appState.showingFirstLaunchWelcome = false
                return "✅ Dismissed First-Launch Welcome ('Continue without signing in')."
            case "open_connections":
                if appState.editorMode != .aiAgent {
                    appState.showingWelcomeHome = false
                    appState.switchToMode(.aiAgent)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: NSNotification.Name("MicroCode.OpenAgentConnections"), object: nil)
                }
                return "✅ Opened Agent Connections Hub."
            case "close_connections":
                NotificationCenter.default.post(name: NSNotification.Name("MicroCode.CloseAgentConnections"), object: nil)
                return "✅ Closed Agent Connections Hub."
            case "restore_normal_state":
                appState.simulateUnconnectedAI = false
                appState.showingFirstLaunchWelcome = false
                appState.showingWelcomeHome = false
                NotificationCenter.default.post(name: NSNotification.Name("MicroCode.CloseAgentConnections"), object: nil)
                if let tempId = appState.tempSimulationChatId {
                    AgentService.shared.deleteChat(tempId)
                    appState.tempSimulationChatId = nil
                }
                if let prevId = appState.savedChatIdBeforeSimulation {
                    AgentService.shared.switchChat(to: prevId)
                    appState.savedChatIdBeforeSimulation = nil
                }
                appState.switchToMode(.aiAgent)
                return "✅ Restored normal connected AI state and chat session."
            default:
                return "Unknown editor_control action '\(action)'."
            }
        }
    }
}

// MARK: - API Studio MCP Tool (Postman-Grade HTTP Client & Route Scanner)

struct APIStudioTool: AgentTool {
    let name = "api_studio"
    let description = "Control MicroCode's built-in API Studio (Postman-level HTTP Client). Supports executing HTTP requests with AI Test Suite assertions, scanning the workspace for backend API routes (FastAPI, Express, Next.js, Rust Axum, Go), listing collections, importing .env variables, and generating multi-language SDK snippets (cURL, Swift, TypeScript, Python, Rust)."
    let parameters = [
        ToolParameter(name: "action", type: "string", description: "Action: 'execute', 'scan_routes', 'list_collections', 'load_env', or 'generate_snippet'", required: true),
        ToolParameter(name: "method", type: "string", description: "HTTP method: GET, POST, PUT, DELETE, PATCH (for 'execute' / 'generate_snippet')", required: false),
        ToolParameter(name: "url", type: "string", description: "Target URL (supports {{base_url}} environment variables)", required: false),
        ToolParameter(name: "headers", type: "string", description: "JSON object of HTTP headers (e.g. '{\"Authorization\":\"Bearer ...\"}')", required: false),
        ToolParameter(name: "body", type: "string", description: "Request body payload (JSON or text)", required: false),
        ToolParameter(name: "language", type: "string", description: "Target SDK language for 'generate_snippet': 'curl', 'swift', 'typescript', 'python', 'rust'", required: false),
        ToolParameter(name: "save", type: "boolean", description: "Save request to active API Studio collection", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        let action = (params["action"] as? String ?? "list_collections").lowercased()
        let service = await MainActor.run { APIClientService.shared }

        switch action {
        case "execute", "request", "send":
            guard let url = params["url"] as? String, !url.isEmpty else {
                return "Error: 'url' parameter is required for api_studio execute."
            }
            let method = (params["method"] as? String ?? "GET").uppercased()
            let body = params["body"] as? String
            var headers: [String: String] = ["Content-Type": "application/json"]
            if let hdrStr = params["headers"] as? String,
               let data = hdrStr.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                for (k, v) in parsed { headers[k] = v }
            } else if let hdrDict = params["headers"] as? [String: String] {
                for (k, v) in hdrDict { headers[k] = v }
            }
            let req = APIRequest(
                name: "\(method) \(url)",
                method: method,
                url: url,
                headers: headers,
                body: body
            )
            if (params["save"] as? Bool) == true {
                await MainActor.run { service.saveToCollection(req) }
            }
            let resp = try await service.execute(req)
            let assertions = await MainActor.run { service.activeTestAssertions }
            let assertionSummary = assertions.map { "  \($0.passed ? "✅" : "❌") \($0.name): \($0.details)" }.joined(separator: "\n")
            let bodyPreview = resp.formattedBody.count > 4000 ? String(resp.formattedBody.prefix(4000)) + "\n... (truncated)" : resp.formattedBody
            return """
            === API Studio Response ===
            HTTP \(resp.status) \(resp.statusText) • \(resp.duration_ms) ms • \(resp.bodySize) bytes
            AI Test Suite Assertions:
            \(assertionSummary)
            Body:
            \(bodyPreview)
            """

        case "scan_routes", "scan":
            let ws = await MainActor.run { AppState.shared?.activeTerminalDirectory }
            let routes = await service.scanWorkspaceRoutes(workspacePath: ws)
            if routes.isEmpty {
                return "No backend API routes detected in workspace (\(ws ?? "unknown"))."
            }
            let list = routes.prefix(50).map { "- [\($0.method)] \($0.url)" }.joined(separator: "\n")
            return "✅ Discovered \(routes.count) API endpoints and added to API Studio Collections:\n\(list)"

        case "load_env", "env":
            let ws = await MainActor.run { AppState.shared?.activeTerminalDirectory }
            let count = await MainActor.run { service.loadProjectDotEnv(workspacePath: ws) }
            return "✅ Loaded \(count) environment variables from project .env into API Studio."

        case "generate_snippet", "snippet":
            let url = params["url"] as? String ?? "http://localhost:3000/api/health"
            let method = (params["method"] as? String ?? "GET").uppercased()
            let body = params["body"] as? String
            let langRaw = (params["language"] as? String ?? "curl").lowercased()
            let lang: CodeSnippetLanguage = {
                switch langRaw {
                case "swift": return .swift
                case "ts", "typescript", "js", "javascript": return .typescript
                case "py", "python": return .python
                case "rs", "rust": return .rust
                default: return .curl
                }
            }()
            let req = APIRequest(name: "\(method) \(url)", method: method, url: url, headers: ["Content-Type": "application/json"], body: body)
            return await MainActor.run { service.generateCodeSnippet(for: req, language: lang) }

        case "list_collections", "status", "list":
            return await MainActor.run {
                let colSummary = service.collections.map { col in
                    let items = col.requests.prefix(15).map { "    • [\($0.method)] \($0.url) (\($0.name))" }.joined(separator: "\n")
                    return "📁 \(col.name) (\(col.requests.count) requests)\(items.isEmpty ? "" : "\n" + items)"
                }.joined(separator: "\n")
                return "API Studio Status:\n- Collections (\(service.collections.count)):\n\(colSummary)\n- History Entries: \(service.history.count)"
            }

        default:
            return "Unknown api_studio action '\(action)'. Supported: execute, scan_routes, list_collections, load_env, generate_snippet"
        }
    }
}

// MARK: - Database Studio MCP Tool (SQLite / Postgres / MySQL Schema & Query Engine)

struct DatabaseStudioTool: AgentTool {
    let name = "database_studio"
    let description = "Inspect and query databases in MicroCode Database Studio. Supports discovering database files (.sqlite, .db, .sqlite3, schema.prisma, migrations) in the workspace, listing tables, inspecting table DDL schemas, and executing SQL queries."
    let parameters = [
        ToolParameter(name: "action", type: "string", description: "Action: 'discover', 'list_tables', 'schema', or 'query'", required: true),
        ToolParameter(name: "path", type: "string", description: "Path to SQLite database file (or ':memory:'). Optional if using active DatabaseStudio connection.", required: false),
        ToolParameter(name: "query", type: "string", description: "SQL query to execute (for 'query' action)", required: false),
        ToolParameter(name: "table", type: "string", description: "Optional table name (for 'schema' action)", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        let action = (params["action"] as? String ?? "discover").lowercased()
        let ws = await MainActor.run { AppState.shared?.activeTerminalDirectory ?? FileManager.default.currentDirectoryPath }

        switch action {
        case "discover":
            var found: [String] = []
            if let enumerator = FileManager.default.enumerator(atPath: ws) {
                while let rel = enumerator.nextObject() as? String {
                    if rel.contains("node_modules/") || rel.contains(".git/") || rel.contains(".build/") || rel.contains("target/") {
                        enumerator.skipDescendants()
                        continue
                    }
                    let lower = rel.lowercased()
                    if lower.hasSuffix(".sqlite") || lower.hasSuffix(".sqlite3") || lower.hasSuffix(".db") || lower.hasSuffix("schema.prisma") || lower.hasSuffix(".sql") {
                        found.append(rel)
                    }
                    if found.count >= 40 { break }
                }
            }
            if found.isEmpty {
                return "No database files (.sqlite, .db, .sql, schema.prisma) found in \(ws)."
            }
            return "Discovered Database & Schema Files in \(ws):\n" + found.map { "- \($0)" }.joined(separator: "\n")

        case "list_tables":
            let dbPath = resolveDBPath(params["path"] as? String, workspace: ws)
            return try runSQLite(dbPath: dbPath, sql: "SELECT name, type FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY name;")

        case "schema":
            let dbPath = resolveDBPath(params["path"] as? String, workspace: ws)
            if let table = params["table"] as? String, !table.isEmpty {
                let safeTable = table.replacingOccurrences(of: "'", with: "''")
                return try runSQLite(dbPath: dbPath, sql: "SELECT sql FROM sqlite_master WHERE name = '\(safeTable)';")
            }
            return try runSQLite(dbPath: dbPath, sql: "SELECT name, sql FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY name;")

        case "query":
            guard let sql = params["query"] as? String, !sql.isEmpty else {
                return "Error: 'query' parameter is required for database_studio query."
            }
            if let rawPath = params["path"] as? String, !rawPath.isEmpty {
                let dbPath = resolveDBPath(rawPath, workspace: ws)
                return try runSQLite(dbPath: dbPath, sql: sql)
            }
            if DatabaseService.shared.activeConnectionId != nil {
                let res = try await DatabaseService.shared.executeQuery(sql)
                let header = res.columns.joined(separator: " | ")
                let rows = res.rows.prefix(100).map { r in r.map { "\($0.value)" }.joined(separator: " | ") }.joined(separator: "\n")
                return "Columns: \(header)\nAffected Rows: \(res.affectedRows)\n\(rows)"
            }
            let dbPath = resolveDBPath(nil, workspace: ws)
            return try runSQLite(dbPath: dbPath, sql: sql)

        default:
            return "Unknown database_studio action '\(action)'. Supported: discover, list_tables, schema, query"
        }
    }

    private func resolveDBPath(_ input: String?, workspace: String) -> String {
        guard let input = input, !input.isEmpty else { return ":memory:" }
        if input == ":memory:" || input.hasPrefix("/") { return input }
        return (workspace as NSString).appendingPathComponent(input)
    }

    private func runSQLite(dbPath: String, sql: String) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = ["-header", "-column", dbPath, sql]
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if proc.terminationStatus != 0 {
            throw NSError(domain: "DatabaseStudio", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: err.isEmpty ? "sqlite3 error" : err])
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "✅ Query executed successfully (0 rows returned)." : out
    }
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
    let description = "Read the contents of a file at the given path (supports code, text, Markdown, PDF, and image metadata). Supports optional start_line and end_line for targeted inspection."
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Absolute or relative file path to read", required: true),
        ToolParameter(name: "start_line", type: "integer", description: "Optional starting line number (1-based) to read a specific slice", required: false),
        ToolParameter(name: "end_line", type: "integer", description: "Optional ending line number (1-based) to read a specific slice", required: false)
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
            if text.count > 500000 {
                return String(text.prefix(500000)) + "\n\n... (PDF text truncated at 500K chars, total pages: \(doc.pageCount))"
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
        
        let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attr?[.size] as? NSNumber)?.int64Value ?? 0
        if fileSize > 20 * 1024 * 1024 {
            // Safe chunked reading: file is over 20MB, don't read entire string into memory
            if let handle = try? FileHandle(forReadingFrom: url) {
                defer { try? handle.close() }
                let data = handle.readData(ofLength: 2 * 1024 * 1024)
                let chunk = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
                let formatted = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
                return chunk + "\n\n... (file size is \(formatted). Truncated at 2MB preview to prevent memory exhaustion.)"
            }
        }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return await formatFileReadContent(content, params: params, fileName: url.lastPathComponent, fullPath: url.path)
        } catch {
            // Fallback for different encodings
            if let content = try? String(contentsOf: url, encoding: .isoLatin1) {
                return await formatFileReadContent(content, params: params, fileName: url.lastPathComponent, fullPath: url.path)
            }
            throw error
        }
    }
    
    @MainActor
    private func formatFileReadContent(_ content: String, params: [String: Any], fileName: String, fullPath: String) -> String {
        let lines = content.components(separatedBy: "\n")
        let totalLines = lines.count
        let contentHash = content.hashValue
        
        let startParam = (params["start_line"] as? Int) ?? (params["offset"] as? Int) ?? (params["StartLine"] as? Int)
        let endParam = (params["end_line"] as? Int) ?? (params["limit"] as? Int) ?? (params["EndLine"] as? Int)
        
        if let start = startParam {
            let startIdx = max(0, start - 1)
            let endIdx: Int
            if let end = endParam {
                endIdx = min(totalLines, max(startIdx, end))
            } else {
                endIdx = min(totalLines, startIdx + 400)
            }
            if startIdx < totalLines {
                let slice = lines[startIdx..<endIdx]
                let formatted = slice.enumerated().map { "\(startIdx + $0.offset + 1): \($0.element)" }.joined(separator: "\n")
                let fullOutput = "[File: \(fileName) | Lines \(startIdx + 1)-\(endIdx) of \(totalLines)]\n\n\(formatted)"
                let estTokens = TokenOptimizer.shared.estimateTokens(fullOutput)
                if let dedupStub = TokenOptimizer.shared.checkDuplicateFileRead(
                    path: fullPath,
                    startLine: startIdx + 1,
                    endLine: endIdx,
                    contentHash: contentHash,
                    lineCount: totalLines,
                    fullTokenEstimate: estTokens
                ) {
                    return dedupStub
                }
                return fullOutput
            }
        }
        
        // Check whole-file duplicate read within the active run
        let rawTokenEst = TokenOptimizer.shared.estimateTokens(content)
        if let dedupStub = TokenOptimizer.shared.checkDuplicateFileRead(
            path: fullPath,
            startLine: 1,
            endLine: totalLines,
            contentHash: contentHash,
            lineCount: totalLines,
            fullTokenEstimate: rawTokenEst
        ) {
            return dedupStub
        }
        
        // TokenMem Layer 4: AST Structural Skeleton Windowing for large files read without start_line/end_line
        let maxUnwindowed = TokenOptimizer.shared.mode.maxUnwindowedFileLines
        if totalLines > maxUnwindowed {
            let headCount = min(300, maxUnwindowed - 80)
            let tailCount = 80
            let headSlice = lines.prefix(headCount).enumerated().map { "\($0.offset + 1): \($0.element)" }.joined(separator: "\n")
            let tailSlice = lines.suffix(tailCount).enumerated().map { "\(totalLines - tailCount + $0.offset + 1): \($0.element)" }.joined(separator: "\n")
            
            // Extract structural declarations (struct/class/enum/func/MARK) with exact line numbers from the middle section
            let middleRange = headCount..<(totalLines - tailCount)
            var outlineLines: [String] = []
            for idx in middleRange {
                let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("func ") || trimmed.hasPrefix("private func ") || trimmed.hasPrefix("public func ") ||
                   trimmed.hasPrefix("internal func ") || trimmed.hasPrefix("static func ") || trimmed.hasPrefix("mutating func ") ||
                   trimmed.hasPrefix("struct ") || trimmed.hasPrefix("class ") || trimmed.hasPrefix("enum ") ||
                   trimmed.hasPrefix("protocol ") || trimmed.hasPrefix("extension ") || trimmed.hasPrefix("actor ") ||
                   trimmed.hasPrefix("// MARK:") || trimmed.hasPrefix("def ") || trimmed.hasPrefix("async def ") ||
                   trimmed.hasPrefix("fn ") || trimmed.hasPrefix("pub fn ") || trimmed.hasPrefix("pub struct ") ||
                   trimmed.hasPrefix("impl ") || trimmed.hasPrefix("export function ") || trimmed.hasPrefix("export class ") {
                    outlineLines.append("  L\(idx + 1): \(trimmed)")
                    if outlineLines.count >= 120 { break }
                }
            }
            let outlineBlock = outlineLines.isEmpty
                ? "... [\(totalLines - headCount - tailCount) lines omitted: lines \(headCount + 1)-\(totalLines - tailCount)] ..."
                : "[TokenMem AST Symbol Index for lines \(headCount + 1)-\(totalLines - tailCount) — pass start_line & end_line to file_read to inspect any symbol body]:\n" + outlineLines.joined(separator: "\n")
            
            let windowedOutput = """
            [File: \(fileName) | Total \(totalLines) lines. Showing lines 1-\(headCount), AST Symbol Index for lines \(headCount + 1)-\(totalLines - tailCount), and tail lines \(totalLines - tailCount + 1)-\(totalLines).]
            
            \(headSlice)
            
            \(outlineBlock)
            
            \(tailSlice)
            """
            let windowedTokens = TokenOptimizer.shared.estimateTokens(windowedOutput)
            TokenOptimizer.shared.recordToolFoldingSavings(savedTokens: max(0, rawTokenEst - windowedTokens))
            return windowedOutput
        }
        
        if content.count > 2_000_000 {
            return String(content.prefix(2_000_000)) + "\n\n... (file truncated at 2M chars, total: \(content.count) chars)"
        }
        return content
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
        await MainActor.run {
            PreviewHotReloadEngine.shared.notifyFileSaved(path: url.path, content: content, source: "Agent")
        }
        return "✅ Written \(content.count) chars to \(url.lastPathComponent)"
    }
}

enum FileEditMatchResult {
    case updated(String)
    case notFound
    case ambiguous(Int)
}

func smartReplaceInContent(_ content: String, oldText rawOld: String, newText rawNew: String) -> FileEditMatchResult {
    // Strip accidental line number prefixes (e.g. "123: ") if model copied from file_read
    func stripLineNumberPrefixes(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !nonEmpty.isEmpty else { return text }
        let allHaveLineNums = nonEmpty.allSatisfy {
            $0.range(of: #"^\s*\d+:\s?"#, options: .regularExpression) != nil
        }
        guard allHaveLineNums else { return text }
        return lines.map {
            $0.replacingOccurrences(of: #"^\s*\d+:\s?"#, with: "", options: .regularExpression)
        }.joined(separator: "\n")
    }
    
    let oldText = stripLineNumberPrefixes(rawOld.replacingOccurrences(of: "\r\n", with: "\n"))
    let newText = stripLineNumberPrefixes(rawNew.replacingOccurrences(of: "\r\n", with: "\n"))
    let normalizedContent = content.replacingOccurrences(of: "\r\n", with: "\n")
    
    // 1. Exact match
    var searchRange = normalizedContent.startIndex..<normalizedContent.endIndex
    var exactRanges: [Range<String.Index>] = []
    while let range = normalizedContent.range(of: oldText, range: searchRange) {
        exactRanges.append(range)
        searchRange = range.upperBound..<normalizedContent.endIndex
    }
    if exactRanges.count == 1, let range = exactRanges.first {
        var result = normalizedContent
        result.replaceSubrange(range, with: newText)
        return .updated(result)
    } else if exactRanges.count > 1 {
        return .ambiguous(exactRanges.count)
    }
    
    // 2. Line-by-line whitespace-tolerant matching
    let contentLines = normalizedContent.components(separatedBy: "\n")
    let oldLines = oldText.components(separatedBy: "\n")
    guard !oldLines.isEmpty, oldLines.count <= contentLines.count else {
        return .notFound
    }
    
    // First try trailing-whitespace-insensitive match
    let rtrimmedOld = oldLines.map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
    var matchedIndices: [Int] = []
    let maxStart = contentLines.count - oldLines.count
    for startIdx in 0...maxStart {
        var matches = true
        for offset in 0..<oldLines.count {
            let candidate = contentLines[startIdx + offset].replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            if candidate != rtrimmedOld[offset] {
                matches = false
                break
            }
        }
        if matches {
            matchedIndices.append(startIdx)
        }
    }
    
    // Second fallback: both leading and trailing whitespace normalized (trimmed non-empty lines)
    if matchedIndices.isEmpty {
        let trimmedOld = oldLines.map { $0.trimmingCharacters(in: .whitespaces) }
        // Require at least one non-empty line to avoid matching blank lines
        if trimmedOld.contains(where: { !$0.isEmpty }) {
            for startIdx in 0...maxStart {
                var matches = true
                for offset in 0..<oldLines.count {
                    let candidate = contentLines[startIdx + offset].trimmingCharacters(in: .whitespaces)
                    if candidate != trimmedOld[offset] {
                        matches = false
                        break
                    }
                }
                if matches {
                    matchedIndices.append(startIdx)
                }
            }
        }
    }
    
    if matchedIndices.count == 1, let matchStart = matchedIndices.first {
        var updatedLines = contentLines
        let replacementLines = newText.components(separatedBy: "\n")
        updatedLines.replaceSubrange(matchStart..<(matchStart + oldLines.count), with: replacementLines)
        return .updated(updatedLines.joined(separator: "\n"))
    } else if matchedIndices.count > 1 {
        return .ambiguous(matchedIndices.count)
    }
    
    return .notFound
}

struct ReplaceInFileTool: AgentTool {
    let name = "replace_in_file"
    let description = "Find and replace text in a file. Use this instead of file_write for targeted edits."
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Absolute file path", required: true),
        ToolParameter(name: "old_text", type: "string", description: "Exact text to find (must match uniquely)", required: true),
        ToolParameter(name: "new_text", type: "string", description: "Replacement text", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String,
              let oldText = params["old_text"] as? String,
              let newText = params["new_text"] as? String else {
            throw ToolBoxError.invalidParams("path, old_text, and new_text are required")
        }
        
        let url = URL(fileURLWithPath: path)
        let content = try String(contentsOf: url, encoding: .utf8)
        
        switch smartReplaceInContent(content, oldText: oldText, newText: newText) {
        case .updated(let updatedContent):
            try updatedContent.write(to: url, atomically: true, encoding: .utf8)
            await MainActor.run {
                PreviewHotReloadEngine.shared.notifyFileSaved(path: url.path, content: updatedContent, source: "Agent")
            }
            return "✅ Replaced text in \(url.lastPathComponent)"
        case .notFound:
            let totalLines = content.components(separatedBy: "\n").count
            throw ToolBoxError.executionFailed("Error: The specified old_text was not found in \(url.lastPathComponent) (\(totalLines) lines). Use `file_read` with `start_line` and `end_line` to verify the exact current lines before retrying.")
        case .ambiguous(let count):
            throw ToolBoxError.executionFailed("Error: Found \(count) occurrences of old_text in \(url.lastPathComponent). Include more surrounding lines in old_text to make the match unique.")
        }
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
    
    static let excludedDirs = [
        ".git", "node_modules", "target", ".build", "DerivedData",
        ".codetuner-build", "dist", "build", ".next", "__pycache__",
        ".venv", "venv", "Pods", ".swiftpm"
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        let patternOpt = (params["pattern"] as? String) ?? (params["query"] as? String)
        let defaultRoot = await MainActor.run { AgentToolBox.shared.workspaceRoot }
        let directoryOpt = (params["directory"] as? String) ?? (params["path"] as? String) ?? defaultRoot
        guard let pattern = patternOpt, !pattern.isEmpty,
              let directory = directoryOpt, !directory.isEmpty else {
            throw ToolBoxError.invalidParams("pattern and directory are required")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        var args = ["-rn", "--color=never", "-I", "-E"]
        for dir in Self.excludedDirs {
            args.append("--exclude-dir=\(dir)")
        }
        if let include = params["include"] as? String, !include.isEmpty {
            args.append(contentsOf: ["--include", include])
        }
        args.append(contentsOf: ["-m", "50", "-e", pattern, directory])
        process.arguments = args
        
        let pipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = stderrPipe
        
        try process.run()

        async let stdoutData = Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }.value
        async let stderrData = Task.detached { stderrPipe.fileHandleForReading.readDataToEndOfFile() }.value
        
        let data = await stdoutData
        _ = await stderrData
        
        while process.isRunning {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        
        let output = String(data: data, encoding: .utf8) ?? ""
        
        if output.isEmpty {
            return "No matches found for '\(pattern)' in \(directory)"
        }
        
        if output.count > 200_000 {
            return String(output.prefix(200_000)) + "\n... (results truncated at 200K chars)"
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
    
    private static let skippedDirs: Set<String> = [
        "node_modules", "target", ".build", "DerivedData", ".codetuner-build",
        "Pods", "__pycache__", "dist", "build", ".next", ".venv", "venv", ".swiftpm"
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        let defaultRoot = await MainActor.run { AgentToolBox.shared.workspaceRoot }
        guard let path = (params["path"] as? String) ?? (params["directory"] as? String) ?? defaultRoot else {
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
        
        let sorted = items
            .filter { !$0.lastPathComponent.hasPrefix("._") && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result = ""
        
        for (i, item) in sorted.enumerated() {
            let isLast = i == sorted.count - 1
            let connector = isLast ? "└── " : "├── "
            let childPrefix = isLast ? "    " : "│   "
            let name = item.lastPathComponent
            
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir && Self.skippedDirs.contains(name) {
                result += "\(prefix)\(connector)\(name)/ (build/deps skipped)\n"
                continue
            }
            result += "\(prefix)\(connector)\(name)\(isDir ? "/" : "")\n"
            
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
        let defaultRoot = await MainActor.run { AgentToolBox.shared.workspaceRoot }
        let directoryOpt = (params["directory"] as? String) ?? (params["path"] as? String) ?? defaultRoot
        let patternOpt = (params["pattern"] as? String) ?? (params["query"] as? String)
        guard let directory = directoryOpt, !directory.isEmpty,
              let pattern = patternOpt, !pattern.isEmpty else {
            throw ToolBoxError.invalidParams("directory and pattern are required")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        process.arguments = [
            directory,
            "-maxdepth", "6",
            "-not", "-path", "*/.*",
            "-not", "-name", "._*",
            "-not", "-path", "*/node_modules/*",
            "-not", "-path", "*/target/*",
            "-not", "-path", "*/DerivedData/*",
            "-not", "-path", "*/.build/*",
            "-not", "-path", "*/.codetuner-build/*",
            "-not", "-path", "*/Pods/*",
            "-type", "f",
            "-name", pattern
        ]
        
        let pipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = stderrPipe
        
        try process.run()
        
        async let stdoutData = Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }.value
        async let stderrData = Task.detached { stderrPipe.fileHandleForReading.readDataToEndOfFile() }.value
        
        let data = await stdoutData
        _ = await stderrData
        
        while process.isRunning {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        
        let out = String(data: data, encoding: .utf8) ?? ""
        return out.isEmpty ? "No files matching '\(pattern)' found in \(directory)" : out
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

/// Central registry to track and manage local development servers
/// (e.g. `npm run dev`, `vite`, `next dev`, `python -m http.server`)
/// spawned by the AI Agent or user tools in the background.
public final class DevServerRegistry: @unchecked Sendable {
    public static let shared = DevServerRegistry()
    private let lock = NSLock()
    private var processes: [Int32: (command: String, process: Process, startedAt: Date)] = [:]
    
    private init() {}
    
    public func register(process: Process, command: String) {
        lock.lock()
        defer { lock.unlock() }
        let pid = process.processIdentifier
        processes[pid] = (command: command, process: process, startedAt: Date())
    }
    
    public func hasRunningServer() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        processes = processes.filter { $0.value.process.isRunning }
        return !processes.isEmpty
    }
    
    public func activeServers() -> [(pid: Int32, command: String, uptime: TimeInterval)] {
        lock.lock()
        defer { lock.unlock() }
        processes = processes.filter { $0.value.process.isRunning }
        let now = Date()
        return processes.map { (pid: $0.key, command: $0.value.command, uptime: now.timeIntervalSince($0.value.startedAt)) }
    }
    
    public func terminate(pid: Int32) {
        lock.lock()
        let item = processes.removeValue(forKey: pid)
        lock.unlock()
        if let proc = item?.process, proc.isRunning {
            proc.terminate()
            kill(pid, SIGTERM)
        }
    }
    
    public func terminateAll() {
        lock.lock()
        let procs = Array(processes.values)
        processes.removeAll()
        lock.unlock()
        
        for item in procs {
            if item.process.isRunning {
                item.process.terminate()
                kill(item.process.processIdentifier, SIGTERM)
            }
        }
    }
}

private final class ProcessOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var textBuffer = ""
    private var dataBuffer = Data()
    private var isReady = false
    
    func appendText(_ chunk: String, readinessMarkers: [String] = []) {
        lock.lock()
        defer { lock.unlock() }
        textBuffer += chunk
        if !isReady && readinessMarkers.contains(where: { textBuffer.contains($0) }) {
            isReady = true
        }
    }
    
    func appendData(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        dataBuffer.append(chunk)
    }
    
    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return textBuffer
    }
    
    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return dataBuffer
    }
    
    var ready: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isReady
    }
}

struct ShellCommandTool: AgentTool {
    let name = "shell"
    let description = "Execute a shell command in macOS Terminal and the IDE console. Use for building, testing, running CLI commands, or checking project state."
    let parameters = [
        ToolParameter(name: "command", type: "string", description: "Shell command to execute", required: true),
        ToolParameter(name: "cwd", type: "string", description: "Working directory (optional, defaults to active workspace folder)", required: false),
        ToolParameter(name: "timeout", type: "integer", description: "Timeout in seconds (default 120)", required: false),
        ToolParameter(name: "is_daemon", type: "boolean", description: "Set to true for long-running servers or background daemons (e.g. dev server, file watcher)", required: false)
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
        
        let target = await MainActor.run { AgentToolBox.shared.executionTarget }
        
        // If a remote SSH server is selected, route execution to the cloud/SSH server
        if case .remote(let server) = target {
            return try await executeRemote(command: command, server: server, params: params)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        
        // Full macOS development toolchain + Portable MicroCode Runtimes PATH environment
        var env = ProcessInfo.processInfo.environment
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let portableBins = RuntimeManager.shared.allRuntimeBinDirectories()
        let extraPaths = (portableBins + [
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
        ]).joined(separator: ":")
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = "\(extraPaths):\(currentPath)"
        if env["JAVA_HOME"] == nil, let javaHome = RuntimeManager.shared.portableJavaHome() {
            env["JAVA_HOME"] = javaHome
        }
        if env["GOROOT"] == nil, let goRoot = RuntimeManager.shared.portableGoRoot() {
            env["GOROOT"] = goRoot
        }
        env["TERM"] = "xterm-256color"
        env["LANG"] = "en_US.UTF-8"
        env["COPYFILE_DISABLE"] = "1"
        // Auto-resolve working directory (cwd)
        let currentWorkspace = await MainActor.run { AgentToolBox.shared.workspaceRoot }
        let rawCwd = params["cwd"] as? String
        let resolvedCwd: String
        if let rawCwd = rawCwd, !rawCwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if rawCwd.hasPrefix("/") {
                resolvedCwd = rawCwd
            } else if rawCwd.hasPrefix("~") {
                resolvedCwd = (rawCwd as NSString).expandingTildeInPath
            } else if let root = currentWorkspace {
                resolvedCwd = (root as NSString).appendingPathComponent(rawCwd)
            } else {
                resolvedCwd = rawCwd
            }
        } else {
            resolvedCwd = currentWorkspace ?? FileManager.default.currentDirectoryPath
        }
        let standardizedCwd = URL(fileURLWithPath: (resolvedCwd as NSString).standardizingPath).resolvingSymlinksInPath().path
        let targetCwd = standardizedCwd
        process.currentDirectoryURL = URL(fileURLWithPath: targetCwd)
        
        // External SSD & Volume Scratch Acceleration:
        // When working on an external SSD volume (/Volumes/*), redirect Gradle/Cargo/TMPDIR
        // caches to the external drive so the internal SSD is never exhausted (0 bytes free),
        // and strip AppleDouble (._*) resource-fork files that break SwiftPM/codesign on ExFAT.
        var effectiveCommand = command
        if standardizedCwd.hasPrefix("/Volumes/") {
            let comps = (standardizedCwd as NSString).pathComponents
            if comps.count >= 3 {
                let volumeMount = "/" + comps[1] + "/" + comps[2]
                let extCacheDir = "\(volumeMount)/.microcode_cache"
                try? FileManager.default.createDirectory(atPath: "\(extCacheDir)/tmp", withIntermediateDirectories: true)
                try? FileManager.default.createDirectory(atPath: "\(extCacheDir)/gradle", withIntermediateDirectories: true)
                
                if env["GRADLE_USER_HOME"] == nil {
                    env["GRADLE_USER_HOME"] = "\(extCacheDir)/gradle"
                }
                if env["TMPDIR"] == nil || env["TMPDIR"]?.hasPrefix("/var") == true || env["TMPDIR"]?.hasPrefix("/tmp") == true {
                    env["TMPDIR"] = "\(extCacheDir)/tmp"
                }
            }
            let lowerCmd = command.lowercased()
            if lowerCmd.contains("swift ") || lowerCmd.contains("'swift'") || lowerCmd.contains("xcodebuild") || lowerCmd.contains("cargo ") {
                effectiveCommand = "/usr/sbin/dot_clean -m . 2>/dev/null || true; \(command)"
            }
        }
        process.arguments = ["-c", effectiveCommand]
        process.environment = env
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        if isDevServerOrDaemon(command: command, params: params) {
            return try await executeDevServer(process: process, command: command, targetCwd: targetCwd, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
        } else {
            let timeout = (params["timeout"] as? Int) ?? 120
            return try await executeStandardCommand(process: process, command: command, targetCwd: targetCwd, timeout: timeout, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
        }
    }
    
    private func isDevServerOrDaemon(command: String, params: [String: Any]) -> Bool {
        if params["is_daemon"] as? Bool == true || params["background"] as? Bool == true {
            return true
        }
        let lower = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = lower.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\"", with: "")
        if (normalized == "swift run" || normalized.hasPrefix("swift run ") || normalized.hasSuffix("&& swift run") || normalized.contains("&& swift run "))
            && !normalized.contains("--help") && !normalized.contains("--version") && !normalized.contains("--show-bin-path") {
            return true
        }
        let devPatterns = [
            "npm run dev", "npm start", "npm run start", "vite", "npx vite",
            "next dev", "next start", "npx next dev",
            "yarn dev", "yarn start",
            "pnpm dev", "pnpm start",
            "bun dev", "bun run dev",
            "python -m http.server", "python3 -m http.server",
            "webpack serve", "webpack-dev-server", "live-server", "http-server",
            "flutter run -d chrome", "cargo watch", "uvicorn"
        ]
        return devPatterns.contains { pattern in
            normalized == pattern || normalized.contains(pattern)
        }
    }
    
    private func executeDevServer(
        process: Process,
        command: String,
        targetCwd: String,
        stdoutPipe: Pipe,
        stderrPipe: Pipe
    ) async throws -> String {
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        
        let collector = ProcessOutputCollector()
        let readinessMarkers = [
            "http://localhost:",
            "http://127.0.0.1:",
            "http://0.0.0.0:",
            "Local:",
            "Network:",
            "ready in",
            "Ready on",
            "compiled successfully",
            "Serving HTTP",
            "Server running",
            "Listening on",
            "Started server",
            "press h + enter to show help",
            "webpack compiled",
            "Build complete!",
            "Build of product"
        ]
        
        stdoutHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            if let str = String(data: chunk, encoding: .utf8), !str.isEmpty {
                collector.appendText(str, readinessMarkers: readinessMarkers)
            }
        }
        
        stderrHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            if let str = String(data: chunk, encoding: .utf8), !str.isEmpty {
                collector.appendText(str, readinessMarkers: readinessMarkers)
            }
        }
        
        try process.run()
        let pid = process.processIdentifier
        
        NotificationCenter.default.post(
            name: NSNotification.Name("MicroCodeAgentTerminalCommand"),
            object: nil,
            userInfo: [
                "phase": "started",
                "command": command,
                "cwd": targetCwd
            ]
        )
        
        let isSwiftRun = command.lowercased().replacingOccurrences(of: "'", with: "").contains("swift run")
        let maxStartupWait: TimeInterval = isSwiftRun ? 30.0 : 3.5
        let startTime = Date()
        var readySince: Date? = nil
        while Date().timeIntervalSince(startTime) < maxStartupWait {
            if !process.isRunning {
                break
            }
            if collector.ready {
                if readySince == nil { readySince = Date() }
                if let rs = readySince, Date().timeIntervalSince(rs) >= (isSwiftRun ? 1.2 : 0.8) {
                    break
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        if !process.isRunning {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            
            let exitCode = process.terminationStatus
            let outText = collector.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if exitCode == 0 {
                NotificationCenter.default.post(
                    name: NSNotification.Name("MicroCodeAgentTerminalCommand"),
                    object: nil,
                    userInfo: [
                        "command": command,
                        "output": outText,
                        "cwd": targetCwd,
                        "exitCode": 0,
                        "phase": "completed"
                    ]
                )
                return outText.isEmpty ? "Command completed successfully (exit code 0)." : outText
            }
            let failOutput = "[exit code: \(exitCode)]\n\(collector.text)"
            NotificationCenter.default.post(
                name: NSNotification.Name("MicroCodeAgentTerminalCommand"),
                object: nil,
                userInfo: [
                    "command": command,
                    "output": failOutput,
                    "cwd": targetCwd,
                    "exitCode": Int(exitCode),
                    "phase": "completed"
                ]
            )
            throw ToolBoxError.executionFailed("Command exited with status \(exitCode):\n\(failOutput)")
        }
        
        // App or dev server is healthy and running in background
        DevServerRegistry.shared.register(process: process, command: command)
        
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        
        let cleanBanner = collector.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let resultMsg = """
        ✅ [Process running in background (PID: \(pid))]
        \(cleanBanner.isEmpty ? "Process active." : cleanBanner)
        
        The application/server has been launched in the background and is active.
        """
        
        NotificationCenter.default.post(
            name: NSNotification.Name("MicroCodeAgentTerminalCommand"),
            object: nil,
            userInfo: [
                "command": command,
                "output": resultMsg,
                "cwd": targetCwd,
                "exitCode": 0,
                "phase": "completed"
            ]
        )
        return resultMsg
    }
    
    private func executeStandardCommand(
        process: Process,
        command: String,
        targetCwd: String,
        timeout: Int,
        stdoutPipe: Pipe,
        stderrPipe: Pipe
    ) async throws -> String {
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        
        let stdoutCollector = ProcessOutputCollector()
        let stderrCollector = ProcessOutputCollector()
        
        stdoutHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stdoutCollector.appendData(chunk)
            }
        }
        
        stderrHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stderrCollector.appendData(chunk)
            }
        }
        
        try process.run()
        let pid = process.processIdentifier
        
        NotificationCenter.default.post(
            name: NSNotification.Name("MicroCodeAgentTerminalCommand"),
            object: nil,
            userInfo: [
                "phase": "started",
                "command": command,
                "cwd": targetCwd
            ]
        )
        
        let startTime = Date()
        var timedOut = false
        
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                kill(pid, SIGKILL)
                break
            }
            if Date().timeIntervalSince(startTime) > Double(timeout) {
                timedOut = true
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                    if process.isRunning {
                        kill(pid, SIGKILL)
                    }
                }
                break
            }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        
        // Immediately disarm readabilityHandlers before reading any remaining buffered bytes.
        // Never call process.waitUntilExit() on a Swift Concurrency cooperative thread,
        // as -[NSConcreteTask waitUntilExit] spins CFRunLoopInMode and deadlocks when no RunLoop is servicing it.
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        
        if !timedOut && !Task.isCancelled {
            if let remOut = try? stdoutHandle.readToEnd(), !remOut.isEmpty {
                stdoutCollector.appendData(remOut)
            }
            if let remErr = try? stderrHandle.readToEnd(), !remErr.isEmpty {
                stderrCollector.appendData(remErr)
            }
        }
        
        let stdout = String(data: stdoutCollector.data, encoding: .utf8) ?? ""
        let stderr = String(data: stderrCollector.data, encoding: .utf8) ?? ""
        
        try? stdoutHandle.close()
        try? stderrHandle.close()
        
        var output = stdout
        if !stderr.isEmpty { output += "\n[stderr]\n\(stderr)" }
        
        if timedOut {
            output = "⏱ [Command timed out after \(timeout)s]\n\(output)"
            NotificationCenter.default.post(
                name: NSNotification.Name("MicroCodeAgentTerminalCommand"),
                object: nil,
                userInfo: [
                    "command": command,
                    "output": output,
                    "cwd": targetCwd,
                    "exitCode": -1,
                    "phase": "completed"
                ]
            )
            throw ToolBoxError.executionFailed(output)
        }
        
        let exitCode = process.isRunning ? -1 : process.terminationStatus
        let didSucceed = exitCode == 0
        if !didSucceed { output = "[exit code: \(exitCode)]\n\(output)" }
        
        NotificationCenter.default.post(
            name: NSNotification.Name("MicroCodeAgentTerminalCommand"),
            object: nil,
            userInfo: [
                "command": command,
                "output": output,
                "cwd": targetCwd,
                "exitCode": Int(exitCode),
                "phase": "completed"
            ]
        )
        
        let boundedOutput = output.count > 1_000_000
            ? String(output.suffix(1_000_000)).trimmingCharacters(in: .whitespacesAndNewlines) + "\n... (leading output truncated at 1M chars)"
            : output
        guard didSucceed else {
            throw ToolBoxError.executionFailed(boundedOutput.isEmpty
                ? "Command exited with status \(exitCode)."
                : boundedOutput)
        }
        return boundedOutput
    }
    
    /// Remote execution over russh / OpenSSH when a remote server / VPS / RunPod target is active
    private func executeRemote(command: String, server: RemoteConnectionConfig, params: [String: Any]) async throws -> String {
        var rawCwd = (params["cwd"] as? String) ?? ""
        let (localRoot, remoteWsPath) = await MainActor.run {
            (AgentToolBox.shared.workspaceRoot, RemoteWorkspaceManager.shared.currentWorkspace?.remotePath)
        }
        if let localRoot = localRoot, rawCwd.hasPrefix(localRoot) {
            rawCwd = remoteWsPath ?? ""
        }
        let targetCwd = rawCwd.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteCommand = targetCwd.isEmpty
            ? command
            : "cd -- \(AgentToolBox.posixQuote(targetCwd)) && \(command)"
        
        // Notify start
        NotificationCenter.default.post(
            name: NSNotification.Name("MicroCodeAgentTerminalCommand"),
            object: nil,
            userInfo: [
                "phase": "started",
                "command": "[SSH: \(server.name)] \(remoteCommand)",
                "cwd": targetCwd
            ]
        )
        
        // Fast path: if the Rust russh session is active for this server, execute over existing SSH channel
        if let backendOut = try? await BackendService.shared.executeRemoteCommand(id: server.id.uuidString, command: remoteCommand),
           !backendOut.hasPrefix("Error: Session not found") {
            NotificationCenter.default.post(
                name: NSNotification.Name("MicroCodeAgentTerminalCommand"),
                object: nil,
                userInfo: [
                    "command": "[SSH: \(server.name)] \(remoteCommand)",
                    "output": backendOut,
                    "cwd": targetCwd,
                    "exitCode": 0,
                    "phase": "completed"
                ]
            )
            return backendOut
        }
        
        // Unlock SSH key in macOS Keychain if present
        let keychainTask = Process()
        keychainTask.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-add")
        keychainTask.arguments = ["--apple-load-keychain"]
        keychainTask.standardInput = FileHandle.nullDevice
        keychainTask.standardOutput = FileHandle.nullDevice
        keychainTask.standardError = FileHandle.nullDevice
        try? keychainTask.run()
        while keychainTask.isRunning {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        
        var effectivePassword = server.password
        if effectivePassword.isEmpty {
            let serverId = server.id.uuidString
            let serverHost = server.host
            effectivePassword = await MainActor.run {
                KeychainManager.shared.readIntegrationSecret(account: "ssh_pwd_\(serverId)")
                    ?? KeychainManager.shared.readIntegrationSecret(account: "ssh_host_pwd_\(serverHost)")
                    ?? ""
            }
        }
        
        let rawOutput: String
        let exitCode: Int32
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        
        var args = [
            "-T",
            "-o", "ServerAliveInterval=15",
            "-o", "TCPKeepAlive=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=15",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=/tmp/mc-ssh-%r@%h:%p",
            "-o", "ControlPersist=10m",
            "-p", "\(server.port)"
        ]
        if server.forwardAgent {
            args.append("-A")
        }
        if !server.proxyJump.isEmpty {
            args.append(contentsOf: ["-J", server.proxyJump])
        }
        if !server.keyPath.isEmpty {
            let expanded = (server.keyPath as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                args.append(contentsOf: ["-i", expanded, "-o", "IdentitiesOnly=yes"])
            }
        }
        args.append(contentsOf: ["--", "\(server.username)@\(server.host)", "sh -lc \(AgentToolBox.posixQuote(remoteCommand))"])
        process.arguments = args
        
        var env = ProcessInfo.processInfo.environment
        var tempAskPass: String? = nil
        
        if !effectivePassword.isEmpty {
            let unique = ProcessInfo.processInfo.globallyUniqueString
            let askPath = "/tmp/mc_ask_\(unique).sh"
            // Never write the password to disk; pass via in-memory environment variable MC_SSH_SECRET
            let askScript = "#!/bin/sh\nprintf '%s\\n' \"$MC_SSH_SECRET\"\n"
            FileManager.default.createFile(
                atPath: askPath,
                contents: Data(askScript.utf8),
                attributes: [.posixPermissions: 0o700]
            )
            env["MC_SSH_SECRET"] = effectivePassword
            env["SSH_ASKPASS"] = askPath
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env["DISPLAY"] = ":0"
            tempAskPass = askPath
        }
        process.environment = env
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        do {
            try process.run()
            
            let timeout = (params["timeout"] as? Int) ?? 120
            let deadline = DispatchTime.now() + .seconds(timeout)
            DispatchQueue.global().asyncAfter(deadline: deadline) {
                if process.isRunning { process.terminate() }
            }
            
            async let outDataTask = Task.detached { stdoutPipe.fileHandleForReading.readDataToEndOfFile() }.value
            async let errDataTask = Task.detached { stderrPipe.fileHandleForReading.readDataToEndOfFile() }.value
            
            let outData = await outDataTask
            let errData = await errDataTask
            while process.isRunning {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            
            if let tempAskPass = tempAskPass { try? FileManager.default.removeItem(atPath: tempAskPass) }
            
            var combined = String(data: outData, encoding: .utf8) ?? ""
            if let errStr = String(data: errData, encoding: .utf8), !errStr.isEmpty {
                combined += (combined.isEmpty ? "" : "\n") + errStr
            }
            rawOutput = combined
            exitCode = process.terminationStatus
        } catch {
            if let tempAskPass = tempAskPass { try? FileManager.default.removeItem(atPath: tempAskPass) }
            throw ToolBoxError.executionFailed("Failed to launch SSH remote process: \(error.localizedDescription)")
        }
        
        let didSucceed = (exitCode == 0)
        let output = didSucceed ? rawOutput : "[exit code: \(exitCode)]\n\(rawOutput)"
        
        NotificationCenter.default.post(
            name: NSNotification.Name("MicroCodeAgentTerminalCommand"),
            object: nil,
            userInfo: [
                "command": "[SSH: \(server.name)] \(remoteCommand)",
                "output": output,
                "cwd": targetCwd,
                "exitCode": Int(exitCode),
                "phase": "completed"
            ]
        )
        
        let boundedOutput = output.count > 1_000_000
            ? String(output.suffix(1_000_000)).trimmingCharacters(in: .whitespacesAndNewlines) + "\n... (leading output truncated at 1M chars)"
            : output
        guard didSucceed else {
            throw ToolBoxError.executionFailed(boundedOutput.isEmpty
                ? "Remote SSH command exited with status \(exitCode)."
                : boundedOutput)
        }
        return boundedOutput
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
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        
        let data = await Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }.value
        
        while process.isRunning {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        
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
        
        if content.count > 500_000 {
            return String(content.prefix(500_000)) + "\n... (truncated at 500K chars)"
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
        let symbolOpt = (params["symbol"] as? String) ?? (params["query"] as? String)
        let defaultRoot = await MainActor.run { AgentToolBox.shared.workspaceRoot }
        let directoryOpt = (params["directory"] as? String) ?? (params["path"] as? String) ?? defaultRoot
        guard let symbol = symbolOpt, !symbol.isEmpty,
              let directory = directoryOpt, !directory.isEmpty else {
            throw ToolBoxError.invalidParams("symbol and directory are required")
        }
        
        let symbolType = params["type"] as? String ?? "all"
        let combinedPattern: String
        switch symbolType {
        case "function":
            combinedPattern = "(func|fn|def|function)\\s+\\b\(symbol)\\b"
        case "class":
            combinedPattern = "(class|interface|actor)\\s+\\b\(symbol)\\b"
        case "struct":
            combinedPattern = "struct\\s+\\b\(symbol)\\b"
        case "enum":
            combinedPattern = "enum\\s+\\b\(symbol)\\b"
        default:
            combinedPattern = "\\b\(symbol)\\b"
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        var args = ["-rn", "--color=never", "-I", "-E"]
        for dir in GrepSearchTool.excludedDirs {
            args.append("--exclude-dir=\(dir)")
        }
        args.append(contentsOf: ["-m", "25", "-e", combinedPattern, directory])
        process.arguments = args
        
        let pipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = stderrPipe
        
        try process.run()
        
        async let stdoutData = Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }.value
        async let stderrData = Task.detached { stderrPipe.fileHandleForReading.readDataToEndOfFile() }.value
        let data = await stdoutData
        _ = await stderrData
        
        while process.isRunning {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        
        let output = String(data: data, encoding: .utf8) ?? ""
        if output.isEmpty {
            return "No symbols matching '\(symbol)' found in \(directory)"
        }
        return output.count > 100_000 ? String(output.prefix(100_000)) + "\n... (results truncated)" : output
    }
}

struct PatchFileTool: AgentTool {
    let name = "patch_file"
    let description = "Apply multiple find-and-replace edits to a file atomically in a single operation. More efficient than multiple replace_in_file calls."
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Absolute file path", required: true),
        ToolParameter(name: "edits", type: "string", description: "JSON array of edits: [{\"old\": \"text to find\", \"new\": \"replacement text\"}, ...]", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String else {
            throw ToolBoxError.invalidParams("path is required")
        }
        
        let url = URL(fileURLWithPath: path)
        var workingContent = try String(contentsOf: url, encoding: .utf8)
        
        var parsedEdits: [[String: Any]] = []
        if let editsArray = params["edits"] as? [[String: Any]] {
            parsedEdits = editsArray
        } else if let editsStr = params["edits"] as? String,
                  let editsData = editsStr.data(using: .utf8),
                  let jsonArr = try? JSONSerialization.jsonObject(with: editsData) as? [[String: Any]] {
            parsedEdits = jsonArr
        } else {
            throw ToolBoxError.invalidParams("edits must be a valid JSON array of {\"old\": ..., \"new\": ...} objects")
        }
        
        guard !parsedEdits.isEmpty else {
            throw ToolBoxError.invalidParams("edits array cannot be empty")
        }
        
        var appliedCount = 0
        var failedEdits: [String] = []
        
        for (idx, edit) in parsedEdits.enumerated() {
            let old = (edit["old"] as? String) ?? (edit["old_text"] as? String)
            let new = (edit["new"] as? String) ?? (edit["new_text"] as? String)
            guard let oldText = old, let newText = new else {
                failedEdits.append("Edit #\(idx + 1): missing 'old' or 'new' field")
                continue
            }
            
            switch smartReplaceInContent(workingContent, oldText: oldText, newText: newText) {
            case .updated(let nextContent):
                workingContent = nextContent
                appliedCount += 1
            case .notFound:
                let preview = oldText.prefix(80).replacingOccurrences(of: "\n", with: "\\n")
                failedEdits.append("Edit #\(idx + 1) not found: \"\(preview)...\"")
            case .ambiguous(let count):
                let preview = oldText.prefix(80).replacingOccurrences(of: "\n", with: "\\n")
                failedEdits.append("Edit #\(idx + 1) matched \(count) places (not unique): \"\(preview)...\"")
            }
        }
        
        // Atomic guarantee: never write a half-patched file to disk if any edit failed
        if !failedEdits.isEmpty {
            throw ToolBoxError.executionFailed("Atomic patch_file aborted on \(url.lastPathComponent) (\(failedEdits.count)/\(parsedEdits.count) edit(s) failed; file was NOT modified):\n" + failedEdits.joined(separator: "\n"))
        }
        
        try workingContent.write(to: url, atomically: true, encoding: .utf8)
        let savedPatchContent = workingContent
        await MainActor.run {
            PreviewHotReloadEngine.shared.notifyFileSaved(path: url.path, content: savedPatchContent, source: "Agent")
        }
        return "✅ Applied all \(appliedCount) edit(s) atomically to \(url.lastPathComponent)"
    }
}

/// AGY-style multi-chunk atomic replacement tool (`multi_replace_in_file`)
struct MultiReplaceInFileTool: AgentTool {
    let name = "multi_replace_in_file"
    let description = "Apply multiple non-adjacent replacements to a single file atomically (AGY-style). Supports optional start_line/end_line scoping per chunk so identical snippets in different functions never collide."
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Absolute file path (or TargetFile)", required: true),
        ToolParameter(name: "edits", type: "string", description: "JSON array of replacement chunks: [{\"old_text\": \"...\", \"new_text\": \"...\", \"start_line\": 10, \"end_line\": 25}, ...]", required: true)
    ]

    func execute(params: [String: Any]) async throws -> String {
        let rawPath = (params["path"] as? String) ?? (params["TargetFile"] as? String)
        guard let path = rawPath, !path.isEmpty else {
            throw ToolBoxError.invalidParams("path (or TargetFile) is required")
        }

        let url = URL(fileURLWithPath: path)
        var workingContent = try String(contentsOf: url, encoding: .utf8)

        let rawChunks: Any? = params["edits"] ?? params["replacement_chunks"] ?? params["ReplacementChunks"]
        var chunks: [[String: Any]] = []
        if let arr = rawChunks as? [[String: Any]] {
            chunks = arr
        } else if let jsonStr = rawChunks as? String,
                  let data = jsonStr.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            chunks = arr
        } else {
            throw ToolBoxError.invalidParams("edits / replacement_chunks must be a valid JSON array of chunk objects")
        }

        guard !chunks.isEmpty else {
            throw ToolBoxError.invalidParams("edits array cannot be empty")
        }

        var appliedCount = 0
        var failedChunks: [String] = []

        for (idx, chunk) in chunks.enumerated() {
            let oldOpt = (chunk["old_text"] as? String) ?? (chunk["old"] as? String) ?? (chunk["TargetContent"] as? String)
            let newOpt = (chunk["new_text"] as? String) ?? (chunk["new"] as? String) ?? (chunk["ReplacementContent"] as? String)
            guard let oldText = oldOpt, let newText = newOpt else {
                failedChunks.append("Chunk #\(idx + 1): missing old_text/TargetContent or new_text/ReplacementContent")
                continue
            }

            let startLine = (chunk["start_line"] as? Int) ?? (chunk["StartLine"] as? Int)
            let endLine = (chunk["end_line"] as? Int) ?? (chunk["EndLine"] as? Int)

            if let sLine = startLine, let eLine = endLine, sLine >= 1, eLine >= sLine {
                let allLines = workingContent.components(separatedBy: "\n")
                let clampedStart = max(1, min(sLine, allLines.count)) - 1
                let clampedEnd = max(clampedStart, min(eLine, allLines.count) - 1)
                let sliceLines = Array(allLines[clampedStart...clampedEnd])
                let sliceText = sliceLines.joined(separator: "\n")
                if case .updated(let updatedSlice) = smartReplaceInContent(sliceText, oldText: oldText, newText: newText) {
                    var newAllLines = allLines
                    newAllLines.replaceSubrange(clampedStart...clampedEnd, with: updatedSlice.components(separatedBy: "\n"))
                    workingContent = newAllLines.joined(separator: "\n")
                    appliedCount += 1
                    continue
                }
            }

            switch smartReplaceInContent(workingContent, oldText: oldText, newText: newText) {
            case .updated(let nextContent):
                workingContent = nextContent
                appliedCount += 1
            case .notFound:
                let preview = oldText.prefix(80).replacingOccurrences(of: "\n", with: "\\n")
                failedChunks.append("Chunk #\(idx + 1) not found: \"\(preview)...\"")
            case .ambiguous(let count):
                let preview = oldText.prefix(80).replacingOccurrences(of: "\n", with: "\\n")
                failedChunks.append("Chunk #\(idx + 1) matched \(count) places (specify start_line/end_line): \"\(preview)...\"")
            }
        }

        if !failedChunks.isEmpty {
            throw ToolBoxError.executionFailed("Atomic multi_replace_in_file aborted on \(url.lastPathComponent) (\(failedChunks.count)/\(chunks.count) failed):\n" + failedChunks.joined(separator: "\n"))
        }

        try workingContent.write(to: url, atomically: true, encoding: .utf8)
        let savedMultiContent = workingContent
        await MainActor.run {
            PreviewHotReloadEngine.shared.notifyFileSaved(path: url.path, content: savedMultiContent, source: "Agent")
        }
        return "✅ Applied \(appliedCount) chunk(s) atomically to \(url.lastPathComponent)"
    }
}

/// OpenAI Codex V4A & Unified Diff multi-file patch tool (`apply_patch`)
struct ApplyPatchTool: AgentTool {
    let name = "apply_patch"
    let description = "Apply a multi-file Codex V4A patch (*** Begin Patch ... *** Update/Add/Delete File: ...) or unified git diff across the workspace atomically."
    let parameters = [
        ToolParameter(name: "patch", type: "string", description: "The patch string in Codex V4A format (*** Begin Patch ... *** End Patch) or unified diff format", required: true)
    ]

    func execute(params: [String: Any]) async throws -> String {
        let rawPatch = (params["patch"] as? String) ?? (params["input"] as? String) ?? (params["diff"] as? String)
        guard let patchText = rawPatch, !patchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolBoxError.invalidParams("patch is required")
        }

        let defaultRoot = await MainActor.run { AgentToolBox.shared.workspaceRoot } ?? FileManager.default.currentDirectoryPath
        if patchText.contains("*** Begin Patch") || patchText.contains("*** Update File:") || patchText.contains("*** Add File:") {
            return try applyCodexV4APatch(patchText, workspaceRoot: defaultRoot)
        } else {
            return try await applyUnifiedGitDiff(patchText, workspaceRoot: defaultRoot)
        }
    }

    private func resolveFilePath(_ raw: String, workspaceRoot: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") { return trimmed }
        if trimmed.hasPrefix("~") { return (trimmed as NSString).expandingTildeInPath }
        return (workspaceRoot as NSString).appendingPathComponent(trimmed)
    }

    private func applyCodexV4APatch(_ patch: String, workspaceRoot: String) throws -> String {
        let lines = patch.components(separatedBy: "\n")
        var idx = 0
        var updatedFiles: [String] = []
        var addedFiles: [String] = []
        var deletedFiles: [String] = []

        while idx < lines.count {
            let line = lines[idx]
            if line.hasPrefix("*** Add File:") {
                let relPath = String(line.dropFirst("*** Add File:".count)).trimmingCharacters(in: .whitespaces)
                let fullPath = resolveFilePath(relPath, workspaceRoot: workspaceRoot)
                idx += 1
                var newLines: [String] = []
                while idx < lines.count && !lines[idx].hasPrefix("*** ") {
                    let l = lines[idx]
                    if l.hasPrefix("+") {
                        newLines.append(String(l.dropFirst()))
                    } else {
                        newLines.append(l)
                    }
                    idx += 1
                }
                let fileURL = URL(fileURLWithPath: fullPath)
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let joinedNew = newLines.joined(separator: "\n")
                try joinedNew.write(to: fileURL, atomically: true, encoding: .utf8)
                Task { @MainActor in
                    PreviewHotReloadEngine.shared.notifyFileSaved(path: fileURL.path, content: joinedNew, source: "Agent")
                }
                addedFiles.append((fullPath as NSString).lastPathComponent)
            } else if line.hasPrefix("*** Delete File:") {
                let relPath = String(line.dropFirst("*** Delete File:".count)).trimmingCharacters(in: .whitespaces)
                let fullPath = resolveFilePath(relPath, workspaceRoot: workspaceRoot)
                if FileManager.default.fileExists(atPath: fullPath) {
                    try FileManager.default.removeItem(atPath: fullPath)
                    deletedFiles.append((fullPath as NSString).lastPathComponent)
                }
                idx += 1
            } else if line.hasPrefix("*** Update File:") {
                let relPath = String(line.dropFirst("*** Update File:".count)).trimmingCharacters(in: .whitespaces)
                let fullPath = resolveFilePath(relPath, workspaceRoot: workspaceRoot)
                let fileURL = URL(fileURLWithPath: fullPath)
                var content = try String(contentsOf: fileURL, encoding: .utf8)
                idx += 1

                var oldHunkLines: [String] = []
                var newHunkLines: [String] = []

                func flushHunk() throws {
                    guard !oldHunkLines.isEmpty || !newHunkLines.isEmpty else { return }
                    let oldBlock = oldHunkLines.joined(separator: "\n")
                    let newBlock = newHunkLines.joined(separator: "\n")
                    oldHunkLines.removeAll()
                    newHunkLines.removeAll()
                    guard !oldBlock.isEmpty else { return }
                    switch smartReplaceInContent(content, oldText: oldBlock, newText: newBlock) {
                    case .updated(let next):
                        content = next
                    case .notFound:
                        throw ToolBoxError.executionFailed("apply_patch hunk not found in \((fullPath as NSString).lastPathComponent):\n\(oldBlock.prefix(160))")
                    case .ambiguous(let count):
                        throw ToolBoxError.executionFailed("apply_patch hunk matched \(count) locations in \((fullPath as NSString).lastPathComponent); add more context lines.")
                    }
                }

                while idx < lines.count && !lines[idx].hasPrefix("*** ") {
                    let hLine = lines[idx]
                    if hLine.hasPrefix("@@") {
                        try flushHunk()
                    } else if hLine.hasPrefix("-") {
                        oldHunkLines.append(String(hLine.dropFirst()))
                    } else if hLine.hasPrefix("+") {
                        newHunkLines.append(String(hLine.dropFirst()))
                    } else if hLine.hasPrefix(" ") {
                        let ctx = String(hLine.dropFirst())
                        oldHunkLines.append(ctx)
                        newHunkLines.append(ctx)
                    } else if !hLine.trimmingCharacters(in: .whitespaces).isEmpty {
                        oldHunkLines.append(hLine)
                        newHunkLines.append(hLine)
                    }
                    idx += 1
                }
                try flushHunk()
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                let savedSnapshot = content
                Task { @MainActor in
                    PreviewHotReloadEngine.shared.notifyFileSaved(path: fileURL.path, content: savedSnapshot, source: "Agent")
                }
                updatedFiles.append((fullPath as NSString).lastPathComponent)
            } else {
                idx += 1
            }
        }

        var summary: [String] = []
        if !updatedFiles.isEmpty { summary.append("Updated: \(updatedFiles.joined(separator: ", "))") }
        if !addedFiles.isEmpty { summary.append("Added: \(addedFiles.joined(separator: ", "))") }
        if !deletedFiles.isEmpty { summary.append("Deleted: \(deletedFiles.joined(separator: ", "))") }
        return "✅ apply_patch succeeded (\(summary.isEmpty ? "no file changes" : summary.joined(separator: " | ")))"
    }

    private func applyUnifiedGitDiff(_ diff: String, workspaceRoot: String) async throws -> String {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("microcode_patch_\(UUID().uuidString).diff")
        try diff.write(to: tmpURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["apply", "--whitespace=nowarn", tmpURL.path]
        proc.currentDirectoryURL = URL(fileURLWithPath: workspaceRoot)
        let pipe = Pipe()
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        while proc.isRunning {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        if proc.terminationStatus == 0 {
            return "✅ Applied unified diff cleanly in \(workspaceRoot)"
        }
        throw ToolBoxError.executionFailed("git apply failed (exit \(proc.terminationStatus)): \(out)")
    }
}

struct MultiFileReadTool: AgentTool {
    let name = "multi_file_read"
    let description = "Read multiple files at once in parallel across CPU cores. More efficient than multiple file_read calls. Returns combined content with file headers."
    let parameters = [
        ToolParameter(name: "paths", type: "string", description: "Comma-separated list of absolute file paths to read", required: true),
        ToolParameter(name: "max_lines", type: "integer", description: "Maximum lines per file (default: 100)", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let pathsStr = params["paths"] as? String else {
            throw ToolBoxError.invalidParams("paths is required")
        }
        
        let maxLines = params["max_lines"] as? Int ?? 100
        let paths = pathsStr
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !paths.isEmpty else { return "" }
        
        // Read & slice all files across all CPU cores simultaneously via PerformanceManager.parallelMap
        let perFileSections: [(section: String, charCount: Int)] = await Task.detached(priority: .userInitiated) {
            PerformanceManager.parallelMap(paths, minItemsPerCore: 1) { path in
                let url = URL(fileURLWithPath: path)
                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    let lines = content.components(separatedBy: "\n")
                    let limited = Array(lines.prefix(maxLines))
                    let fileContent = limited.joined(separator: "\n")
                    let truncated = lines.count > maxLines
                    var sec = "\n═══ \(url.lastPathComponent) ═══\n" + fileContent
                    if truncated { sec += "\n... (\(lines.count - maxLines) more lines)" }
                    sec += "\n"
                    return (sec, fileContent.count)
                } catch {
                    let sec = "\n═══ \(url.lastPathComponent) ═══\n⚠️ Error: \(error.localizedDescription)\n"
                    return (sec, 0)
                }
            }
        }.value
        
        var result = ""
        var totalChars = 0
        let charBudget = 12000 // Total budget across all files
        for item in perFileSections {
            guard totalChars < charBudget else {
                result += "\n--- (remaining files skipped - token budget reached) ---"
                break
            }
            result += item.section
            totalChars += item.charCount
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
    
    /// Records the workspace path lazily without spawning the Python MCP server until needed.
    func configure(workspacePath: String) {
        if isConnected, activeWorkspacePath != workspacePath {
            stop()
        }
        activeWorkspacePath = workspacePath
    }
    
    func start(workspacePath: String) {
        if isConnected, activeWorkspacePath == workspacePath { return }
        if isConnected { stop() }
        
        let process = Process()
        
        var scriptPath: String? = Bundle.main.path(forResource: "mcp-server", ofType: "py")
        if scriptPath == nil || !FileManager.default.fileExists(atPath: scriptPath!) {
            let bundleRes = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/mcp-server.py").path
            if FileManager.default.fileExists(atPath: bundleRes) {
                scriptPath = bundleRes
            }
        }
        if scriptPath == nil || !FileManager.default.fileExists(atPath: scriptPath!) {
            let wsCandidate = (workspacePath as NSString).appendingPathComponent("mcp-server.py")
            if FileManager.default.fileExists(atPath: wsCandidate) {
                scriptPath = wsCandidate
            }
        }
        if scriptPath == nil || !FileManager.default.fileExists(atPath: scriptPath!) {
            let cwdCandidate = FileManager.default.currentDirectoryPath + "/mcp-server.py"
            if FileManager.default.fileExists(atPath: cwdCandidate) {
                scriptPath = cwdCandidate
            }
        }
        
        guard let path = scriptPath, FileManager.default.fileExists(atPath: path) else {
            print("[MCPClient] Error: mcp-server.py not found across bundle, workspace, CWD, or repo root")
            return
        }
        
        // Safely check for a real Python binary (preferring MicroCode Portable Runtime first) before attempting to spawn
        let portablePython = RuntimeManager.shared.runtimesDir.appendingPathComponent("python/bin/python3").path
        let safePython = [
            portablePython,
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.pyenv/shims/python3"
        ].first(where: { DeveloperToolsGuard.isSafeToExecute($0) }) ?? (DeveloperToolsGuard.hasCommandLineTools && FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") ? "/usr/bin/python3" : nil)
        
        guard let pythonExe = safePython else {
            print("[MCPClient] Safe Python binary not found. Skipping external Python MCP server.")
            return
        }
        
        process.executableURL = URL(fileURLWithPath: pythonExe)
        process.arguments = ["-u", path]
        
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
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
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
    
    /// Ensures MCP Server process is booted and its tools are populated and registered
    /// before an Agent or SubAgent executes its tool schema extraction.
    func ensureConnected(workspacePath: String? = nil, timeoutSeconds: TimeInterval = 2.0) async {
        let ws = workspacePath ?? activeWorkspacePath ?? AgentToolBox.shared.workspaceRoot ?? FileManager.default.currentDirectoryPath
        if !isConnected || activeWorkspacePath != ws {
            start(workspacePath: ws)
        }
        
        let start = Date()
        while Date().timeIntervalSince(start) < timeoutSeconds {
            if !availableTools.isEmpty { break }
            try? await Task.sleep(nanoseconds: 60_000_000) // 60ms
        }
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
                        if let name = t["name"] as? String {
                            let desc = t["description"] as? String ?? t["desc"] as? String ?? ""
                            let schema = t["inputSchema"] as? [String: Any] ?? ["type": "object", "properties": [:]]
                            if let schemaData = try? JSONSerialization.data(withJSONObject: schema),
                               let parsedSchema = try? JSONDecoder().decode([String: AnyCodable].self, from: schemaData) {
                                parsedTools.append(MCPToolSchema(name: name, description: desc, inputSchema: parsedSchema))
                            }
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
            let namespacedName = "mcp__local__\(schema.name)"
            if AgentToolBox.shared.tools[namespacedName] == nil {
                let proxyTool = DynamicMCPTool(mcpClient: self, schema: schema)
                AgentToolBox.shared.register(proxyTool)
                print("[MCPClient] Registered external MCP Tool: \(namespacedName)")
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
                              let contentArray = dict["content"] as? [[String: Any]] {
                        let texts = contentArray.compactMap { $0["text"] as? String }
                        if !texts.isEmpty {
                            continuation.resume(returning: texts.joined(separator: "\n"))
                        } else {
                            continuation.resume(returning: "Success")
                        }
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
    
    /// MCP tools are namespaced at registration time so two servers cannot
    /// silently replace one another. The original server name is retained for
    /// the JSON-RPC tools/call request below.
    var name: String { "mcp__local__\(schema.name)" }
    var description: String { schema.description }
    
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
        return try await mcpClient.callTool(name: schema.name, arguments: params)
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
    let description = "Runs a specialized SubAgent (routing automatically to its assigned model/auth preset if active) and waits for verified completion by default."
    let parameters = [
        ToolParameter(name: "type_name", type: "string", description: "Name of the subagent archetype (e.g. architect, frontend_engineer, backend_engineer, bug_hunter, test_runner, security_auditor)", required: true),
        ToolParameter(name: "role", type: "string", description: "Brief role description for distinguishing this instance", required: true),
        ToolParameter(name: "prompt", type: "string", description: "Detailed subtask objective and instructions for the subagent", required: true),
        ToolParameter(name: "model", type: "string", description: "Optional model ID; defaults to the active Squad Preset or subagent definition", required: false),
        ToolParameter(name: "owned_paths", type: "string", description: "Optional comma-separated file paths/directories locked exclusively for this SubAgent", required: false),
        ToolParameter(name: "wait_for_completion", type: "boolean", description: "Wait for the SubAgent result before this tool succeeds (default true)", required: false)
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
        let ownedStr = params["owned_paths"] as? String ?? ""
        let ownedPaths = ownedStr.isEmpty ? [] : ownedStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        
        let instance = await MainActor.run {
            let ws = AgentToolBox.shared.workspaceRoot
            return SubAgentHarness.shared.invokeSubagent(
                typeName: typeName,
                role: role,
                prompt: prompt,
                workspacePath: ws,
                preferredModel: model,
                ownedPaths: ownedPaths
            )
        }
        if params["wait_for_completion"] as? Bool == false {
            return "SubAgent #\(instance.id.prefix(6)) [\(role)] started in background. It has not completed yet."
        }
        guard let outcome = try await SubAgentHarness.shared.waitForSubagent(id: instance.id) else {
            throw ToolBoxError.executionFailed("SubAgent result was lost")
        }
        let finished = outcome.instance
        guard finished.state == .completed else {
            throw ToolBoxError.executionFailed("SubAgent ended as \(finished.state.displayName): \(finished.stateDetail ?? "No verified result")")
        }
        let prefix = outcome.verifiedWorkspaceChange
            ? AgentExecutionEvidence.verifiedSubagentPrefix : AgentExecutionEvidence.completedSubagentPrefix
        return "\(prefix)SubAgent #\(instance.id.prefix(6)) [\(finished.endpointBadge ?? role)] completed: \(finished.finalReport ?? "No report")"
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

// MARK: - Feature 11: Autonomous Skill Engine 2.0, Hyper-Mesh MCP 2.0 & SubAgent Swarm 2.0

struct SkillEngineTool: AgentTool {
    let name = "skill_engine"
    let description = "Autonomous Skill Engine 2.0: Rank & discover skills ('match'), read distilled SKILL.md instructions without file_read ('read'), execute a skill's bundled helper script with MicroCode Portable Runtime ('run_script'), or crystallize a solved workflow into a reusable skill ('crystallize')."
    let parameters = [
        ToolParameter(name: "action", type: "string", description: "Action: 'match', 'read', 'run_script', or 'crystallize'", required: true),
        ToolParameter(name: "query", type: "string", description: "Search query, skill name, or skill ID", required: false),
        ToolParameter(name: "script", type: "string", description: "Script filename inside the skill's scripts/ directory (for 'run_script')", required: false),
        ToolParameter(name: "args", type: "string", description: "Space-separated arguments for 'run_script'", required: false),
        ToolParameter(name: "description", type: "string", description: "Skill description (for 'crystallize')", required: false),
        ToolParameter(name: "instructions", type: "string", description: "Markdown body of the skill (for 'crystallize')", required: false),
        ToolParameter(name: "helper_script_name", type: "string", description: "Optional helper script filename e.g. 'verify.py' (for 'crystallize')", required: false),
        ToolParameter(name: "helper_script_content", type: "string", description: "Optional helper script code (for 'crystallize')", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        let action = (params["action"] as? String ?? "match").lowercased()
        let query = params["query"] as? String ?? ""
        let ws = await MainActor.run { AgentToolBox.shared.workspaceRoot }
        
        switch action {
        case "match", "search", "list":
            return await MainActor.run {
                let ranked = Array(AgentSkillsStore.shared.rankSkills(forPrompt: query, workspacePath: ws).prefix(8))
                if ranked.isEmpty {
                    return "No matching skills found for '\(query)'."
                }
                return ranked.map { item in
                    let scripts = AgentSkillsStore.shared.availableScripts(forSkill: item.skill)
                    let scriptsInfo = scripts.isEmpty ? "" : " | scripts: [\(scripts.joined(separator: ", "))]"
                    return "- **\(item.skill.name)** (`\(item.skill.id)`, score: \(item.score)): \(item.skill.description)\(scriptsInfo)"
                }.joined(separator: "\n")
            }
        case "read", "distill", "activate":
            return await MainActor.run {
                let store = AgentSkillsStore.shared
                guard let skill = store.skills.first(where: {
                    $0.id.lowercased() == query.lowercased() ||
                    $0.name.lowercased() == query.lowercased() ||
                    $0.name.lowercased().contains(query.lowercased())
                }) else {
                    return "Skill '\(query)' not found. Use action='match' to search available skills."
                }
                let distilled = store.distilledInstructions(for: skill, maxChars: 4000)
                let scripts = store.availableScripts(forSkill: skill)
                return """
                # Skill: \(skill.name)
                Path: \(skill.filePath)
                Bundled Scripts: \(scripts.isEmpty ? "None" : scripts.joined(separator: ", "))
                
                \(distilled)
                """
            }
        case "run_script":
            let scriptName = params["script"] as? String ?? ""
            let rawArgs = params["args"] as? String ?? ""
            let argList = rawArgs.isEmpty ? [] : rawArgs.components(separatedBy: " ").filter { !$0.isEmpty }
            return try await AgentSkillsStore.shared.executeSkillScript(
                skillId: query,
                scriptName: scriptName,
                arguments: argList,
                workspacePath: ws
            )
        case "crystallize", "create":
            let desc = params["description"] as? String ?? "Autonomously crystallized MicroCode skill"
            let instructions = params["instructions"] as? String ?? ""
            let scriptName = params["helper_script_name"] as? String
            let scriptContent = params["helper_script_content"] as? String
            let rawName = query.isEmpty ? "custom-workflow" : query
            return try await MainActor.run {
                let created = try AgentSkillsStore.shared.crystallizeSkill(
                    id: rawName,
                    name: rawName,
                    description: desc,
                    instructions: instructions,
                    scriptName: scriptName,
                    scriptContent: scriptContent,
                    scope: ws != nil ? "workspace" : "global",
                    workspacePath: ws
                )
                return "✅ Crystallized new skill '\(created.name)' at \(created.filePath) (auto-enabled for JIT routing)."
            }
        default:
            return "Unknown skill_engine action '\(action)'. Supported: match, read, run_script, crystallize."
        }
    }
}

struct MCPOrchestratorTool: AgentTool {
    let name = "mcp_orchestrator"
    let description = "Hyper-Mesh MCP Engine 2.0: Inspect connected external MCP servers and telemetry ('status'), search all external MCP tools across 8 IDE ecosystems ('search_tools'), restart a server ('restart'), or autonomously synthesize & hot-mount a brand-new Python JSON-RPC 2.0 MCP server on the fly ('synthesize')."
    let parameters = [
        ToolParameter(name: "action", type: "string", description: "Action: 'status', 'search_tools', 'restart', or 'synthesize'", required: true),
        ToolParameter(name: "server_name", type: "string", description: "Target or new MCP server name", required: false),
        ToolParameter(name: "query", type: "string", description: "Keyword query for 'search_tools'", required: false),
        ToolParameter(name: "description", type: "string", description: "Description of the new MCP server (for 'synthesize')", required: false),
        ToolParameter(name: "tools_spec_json", type: "string", description: "JSON array of MCP tool definitions [{\"name\":\"...\",\"description\":\"...\",\"inputSchema\":{...}}] (for 'synthesize')", required: false),
        ToolParameter(name: "python_handler_body", type: "string", description: "Python body for `def handle_tool_call(name, args):` returning a string result (for 'synthesize')", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        let action = (params["action"] as? String ?? "status").lowercased()
        let ws = await MainActor.run { AgentToolBox.shared.workspaceRoot }
        
        switch action {
        case "status", "list":
            return await MainActor.run {
                ExternalMCPManager.shared.meshStatusSummary()
            }
        case "search_tools", "search":
            let q = (params["query"] as? String ?? "").lowercased()
            return await MainActor.run {
                let all = ExternalMCPManager.shared.allTools
                let filtered = q.isEmpty ? all : all.filter {
                    $0.serverName.lowercased().contains(q) ||
                    $0.tool.name.lowercased().contains(q) ||
                    $0.tool.description.lowercased().contains(q)
                }
                if filtered.isEmpty {
                    return "No external MCP tools matched '\(q)'."
                }
                return filtered.map {
                    "- `mcp__\($0.serverName)__\($0.tool.name)`: \($0.tool.description)"
                }.joined(separator: "\n")
            }
        case "restart":
            let name = params["server_name"] as? String ?? ""
            return await MainActor.run {
                ExternalMCPManager.shared.restartServer(name)
                return "Triggered restart for MCP server '\(name)'."
            }
        case "synthesize", "create":
            let serverName = params["server_name"] as? String ?? "custom_mcp"
            let desc = params["description"] as? String ?? "Synthesized MicroCode MCP Server"
            let specJSON = params["tools_spec_json"] as? String ?? "[]"
            let handlerBody = params["python_handler_body"] as? String ?? "return f'Executed {name} with {args}'"
            return try await ExternalMCPManager.shared.synthesizeServer(
                name: serverName,
                description: desc,
                toolsSpecJSON: specJSON,
                pythonHandlerBody: handlerBody,
                workspacePath: ws
            )
        default:
            return "Unknown mcp_orchestrator action '\(action)'. Supported: status, search_tools, restart, synthesize."
        }
    }
}

struct SwarmOrchestratorTool: AgentTool {
    let name = "swarm_orchestrator"
    let description = "SubAgent Swarm & CEO Executive Harness 3.0: Run a full CEO & Subordinate Executive Squad session ('ceo_squad'), dispatch multiple specialized SubAgents concurrently ('parallel_swarm'), run an adversarial Red-Team security & bug review ('adversarial_review'), or post/read shared architectural facts on the cross-agent Swarm Blackboard ('post_fact', 'read_blackboard')."
    let parameters = [
        ToolParameter(name: "action", type: "string", description: "Action: 'ceo_squad', 'parallel_swarm', 'adversarial_review', 'post_fact', 'read_blackboard', or 'status'", required: true),
        ToolParameter(name: "tasks_json", type: "string", description: "JSON array of parallel tasks: [{\"type_name\":\"frontend_engineer\",\"role\":\"UI Builder\",\"prompt\":\"...\"}] (for 'parallel_swarm')", required: false),
        ToolParameter(name: "focus", type: "string", description: "Objective for 'ceo_squad' or focus area/file list for 'adversarial_review'", required: false),
        ToolParameter(name: "key", type: "string", description: "Blackboard fact key (for 'post_fact')", required: false),
        ToolParameter(name: "value", type: "string", description: "Blackboard fact value (for 'post_fact')", required: false),
        ToolParameter(name: "author_role", type: "string", description: "Author role posting the fact (optional)", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        let action = (params["action"] as? String ?? "status").lowercased()
        let ws = await MainActor.run { AgentToolBox.shared.workspaceRoot }
        
        switch action {
        case "ceo_squad", "ceo", "executive_squad":
            let objective = (params["focus"] as? String) ?? (params["value"] as? String) ?? "Execute current workspace engineering task"
            return await SubAgentHarness.shared.runCEOSquadSession(objective: objective, workspacePath: ws)
        case "post_fact", "write_blackboard":
            let key = params["key"] as? String ?? ""
            let value = params["value"] as? String ?? ""
            let author = params["author_role"] as? String ?? "Agent"
            await MainActor.run {
                SubAgentHarness.shared.postFact(key: key, value: value, authorRole: author)
            }
            return "✅ Posted fact '\(key)' to Shared Swarm Blackboard."
        case "read_blackboard", "blackboard":
            return await MainActor.run {
                let summary = SubAgentHarness.shared.readBlackboardSummary()
                return summary.isEmpty ? "Swarm Blackboard is currently empty." : "## Shared Swarm Blackboard\n\(summary)"
            }
        case "adversarial_review", "red_team":
            let focus = params["focus"] as? String ?? "recent workspace modifications"
            return await SubAgentHarness.shared.runAdversarialReview(workspacePath: ws, focus: focus)
        case "parallel_swarm", "swarm":
            let rawJSON = params["tasks_json"] as? String ?? "[]"
            guard let data = rawJSON.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  !arr.isEmpty else {
                throw ToolBoxError.invalidParams("tasks_json must be a non-empty JSON array of {type_name, role, prompt}")
            }
            let tasks: [(typeName: String, role: String, prompt: String)] = arr.compactMap { item in
                guard let prompt = item["prompt"] as? String, !prompt.isEmpty else { return nil }
                let typeName = item["type_name"] as? String ?? "autonomous_loop"
                let role = item["role"] as? String ?? typeName
                return (typeName, role, prompt)
            }
            return await SubAgentHarness.shared.runParallelSwarm(tasks: tasks, workspacePath: ws)
        case "status":
            return await MainActor.run {
                let status = SubAgentHarness.shared.getSubagentStatusSummary()
                let bb = SubAgentHarness.shared.readBlackboardSummary()
                return status + (bb.isEmpty ? "" : "\n\n## Shared Swarm Blackboard\n\(bb)")
            }
        default:
            return "Unknown swarm_orchestrator action '\(action)'. Supported: parallel_swarm, adversarial_review, post_fact, read_blackboard, status."
        }
    }
}

// MARK: - Feature 12: TH-AI Passport Multimodal Generation Tools (Image, Video, Music)

struct GenerateImageTool: AgentTool {
    let name = "generate_image"
    let description = "Generate an AI image using TH-AI Passport models (e.g., gemini-3.1-flash-image, gemini-3-pro-image, FLUX.2-pro, gpt-image-2.5-sunburst, seedream-5.0-pro). Saves the image to the workspace and returns a markdown preview."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "prompt", type: "string", description: "Detailed visual prompt describing the image to generate", required: true),
        ToolParameter(name: "model", type: "string", description: "Optional TH-AI Passport image model ID (default: gemini-3.1-flash-image). Options: gemini-3.1-flash-image, gemini-3-pro-image, gemini-2.5-flash-image, gemini-nano-banana-2.1, FLUX.2-pro, gpt-image-2, gpt-image-2.5-sunburst, seedream-5.0-pro", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        guard let prompt = params["prompt"] as? String, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolBoxError.invalidParams("Missing required parameter: prompt")
        }
        let model = params["model"] as? String
        let result = try await AIClient.shared.generateAiPassMedia(
            kind: "image",
            prompt: prompt,
            model: model
        )
        return """
        Generated Image: `\(result.fileURL.path)`

        \(result.markdown)
        """
    }
}

struct GenerateVideoTool: AgentTool {
    let name = "generate_video"
    let description = "Generate an AI video (.mp4) using TH-AI Passport video models (e.g., veo-3.1-fast-generate-001, veo-3.1-generate-001, seedance-2.0-fast, sora-2, wan2.2@jts). Saves the video to the workspace and returns a markdown preview."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "prompt", type: "string", description: "Detailed cinematic prompt describing the video scene, motion, and camera movement", required: true),
        ToolParameter(name: "model", type: "string", description: "Optional TH-AI Passport video model ID (default: veo-3.1-fast-generate-001). Options: veo-3.1-fast-generate-001, veo-3.1-generate-001, veo-3.0-generate-001, seedance-2.0-fast, seedance-2.0, sora-2, wan2.2@jts", required: false),
        ToolParameter(name: "aspect_ratio", type: "string", description: "Optional aspect ratio: 16:9 or 9:16 (default: 16:9)", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        guard let prompt = params["prompt"] as? String, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolBoxError.invalidParams("Missing required parameter: prompt")
        }
        let model = params["model"] as? String
        let aspectRatio = (params["aspect_ratio"] as? String) ?? "16:9"
        let result = try await AIClient.shared.generateAiPassMedia(
            kind: "video",
            prompt: prompt,
            model: model,
            aspectRatio: aspectRatio
        )
        return """
        Generated Video: `\(result.fileURL.path)`

        \(result.markdown)
        """
    }
}

struct GenerateMusicTool: AgentTool {
    let name = "generate_music"
    let description = "Generate an AI music / audio track using TH-AI Passport Lyria 3 music models (lyria-3-clip-preview, lyria-3-pro-preview). Saves the audio file to the workspace and returns an interactive player link."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "prompt", type: "string", description: "Detailed musical prompt describing genre, instruments, tempo/BPM, mood, and vocals/lyrics", required: true),
        ToolParameter(name: "model", type: "string", description: "Optional TH-AI Passport music model ID (default: lyria-3-clip-preview). Options: lyria-3-clip-preview, lyria-3-pro-preview", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        guard let prompt = params["prompt"] as? String, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolBoxError.invalidParams("Missing required parameter: prompt")
        }
        let model = params["model"] as? String
        let result = try await AIClient.shared.generateAiPassMedia(
            kind: "music",
            prompt: prompt,
            model: model
        )
        return """
        Generated Audio: `\(result.fileURL.path)`

        \(result.markdown)
        """
    }
}
