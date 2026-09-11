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
            MCPClient.shared.start(workspacePath: initialWs)
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
        register(DefineSubagentTool())
        register(InvokeSubagentTool())
        register(ManageSubagentsTool())
        register(SendMessageTool())
        register(DeviceRuntimeTool())
        register(PreviewControlTool())
    }
    
    func register(_ tool: any AgentTool) {
        tools[tool.name] = tool
    }
    
    func execute(_ toolName: String, params: [String: Any]) async throws -> String {
        var targetTool = tools[toolName]
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

    private func executeWithTimeout(tool: any AgentTool, params: [String: Any]) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await tool.execute(params: params) }
            group.addTask {
                try await Task.sleep(nanoseconds: self.defaultToolTimeout)
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
    
    private func validateSandbox(_ path: String) throws {
        guard let root = workspaceRoot else { return } // No workspace = no restriction
        let resolved = URL(fileURLWithPath: (path as NSString).standardizingPath).resolvingSymlinksInPath().path
        let rootResolved = URL(fileURLWithPath: (root as NSString).standardizingPath).resolvingSymlinksInPath().path
        
        // 1. Within workspace root
        if resolved.hasPrefix(rootResolved) { return }
        
        // 2. Temp and cache directories
        if resolved.hasPrefix("/tmp") || resolved.hasPrefix("/private/tmp") || resolved.hasPrefix("/var/folders") || resolved.hasPrefix(NSTemporaryDirectory()) {
            return
        }
        
        // 3. External SSD / mounted volumes (e.g. /Volumes/MAC, /Volumes/MicroCodeBuild, /Volumes/MicroCodeScratch)
        if resolved.hasPrefix("/Volumes/") {
            return
        }
        
        // 4. Global agent skills, Antigravity configs, and toolchain caches
        let home = NSHomeDirectory()
        let allowedAgentPaths = [
            "\(home)/.gemini",
            "\(home)/.agents",
            "\(home)/.codex",
            "\(home)/.cargo",
            "\(home)/.gradle"
        ]
        for allowed in allowedAgentPaths {
            if resolved.hasPrefix(allowed) { return }
        }
        
        throw ToolBoxError.executionFailed("Path '\(path)' is outside the authorized workspace and volumes. Access denied.")
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
        guard let runID = await MainActor.run(body: { AgentService.shared.currentKernelRunID }) else {
            throw ToolBoxError.executionFailed("No durable agent run is active")
        }
        let action = (params["action"] as? String ?? "").lowercased()
        switch action {
        case "set":
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
        let lines = nodes.map { node -> String in
            let dependencies = node.dependencies.isEmpty ? "" : " — after: \(node.dependencies.joined(separator: ", "))"
            let verification = node.verification.isEmpty ? "" : "\n  - Verify: \(node.verification)"
            let owner = node.owner.map { "\n  - Owner: \($0)" } ?? ""
            return "- [ ] **\(node.id)** \(node.title)\(dependencies)\(verification)\(owner)"
        }
        let markdown = "# Agent Task\n\n" + lines.joined(separator: "\n") + "\n"
        let target = directory.appendingPathComponent("task.md")
        let temporary = directory.appendingPathComponent(".task.md.tmp")
        try markdown.write(to: temporary, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: target)
        }
    }

    @MainActor
    private func markTaskNodeComplete(_ nodeID: String) throws {
        guard let workspace = AgentToolBox.shared.workspaceRoot else { return }
        let target = URL(fileURLWithPath: workspace, isDirectory: true)
            .appendingPathComponent(".microcode/task.md")
        guard var markdown = try? String(contentsOf: target, encoding: .utf8) else { return }
        markdown = markdown.replacingOccurrences(of: "- [ ] **\(nodeID)**", with: "- [x] **\(nodeID)**")
        try markdown.write(to: target, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: NSNotification.Name("MicroCodeAgentWorkspaceFilesChanged"), object: nil)
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

// MARK: - Native Preview Control Tool

struct PreviewControlTool: AgentTool {
    let name = "preview_control"
    let description = "Directly control and inspect the IDE's live Embedded Preview Dock (WebApp, Apple Simulator, Android Device). Supports opening URLs (e.g. http://localhost:3000, Vite, Next.js), reloading pages, changing viewports (Desktop, Tablet, Mobile, Responsive), and toggling between Web, iOS, and Android modes."
    let parameters = [
        ToolParameter(name: "action", type: "string", description: "Action to perform: 'open', 'close', 'reload', 'set_url', 'switch_mode', 'set_viewport', 'status'", required: true),
        ToolParameter(name: "url", type: "string", description: "Target URL for WebApp preview (e.g. http://localhost:3000, http://127.0.0.1:5173)", required: false),
        ToolParameter(name: "mode", type: "string", description: "Dock mode: 'web', 'ios', or 'android'", required: false),
        ToolParameter(name: "viewport", type: "string", description: "Viewport size: 'responsive', 'desktop', 'tablet', or 'mobile'", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        guard let action = (params["action"] as? String)?.lowercased() else {
            throw ToolBoxError.invalidParams("action is required")
        }
        let url = params["url"] as? String
        let mode = (params["mode"] as? String)?.lowercased()
        let viewport = (params["viewport"] as? String)?.lowercased()

        return try await MainActor.run {
            let runtime = DeviceRuntimeService.shared

            switch action {
            case "open":
                runtime.showingEmbeddedDeviceDock = true
                if let mode = mode {
                    if mode == "web" { runtime.embeddedDockMode = .web }
                    else if mode == "ios" { runtime.embeddedDockMode = .ios }
                    else if mode == "android" { runtime.embeddedDockMode = .android }
                } else if runtime.embeddedDockMode != .web && url != nil {
                    runtime.embeddedDockMode = .web
                }
                if let urlString = url, let parsedURL = URL(string: urlString.hasPrefix("http") ? urlString : "http://\(urlString)") {
                    runtime.targetWebURL = parsedURL
                }
                if let viewport = viewport {
                    runtime.targetViewport = viewport
                }
                return "✅ Live Preview Dock opened in \(runtime.embeddedDockMode.rawValue) mode\(url != nil ? " with URL: \(url!)" : "")."

            case "close":
                runtime.showingEmbeddedDeviceDock = false
                return "✅ Live Preview Dock closed."

            case "reload", "refresh":
                runtime.showingEmbeddedDeviceDock = true
                runtime.webRefreshTrigger.toggle()
                return "✅ Live Preview reload triggered."

            case "set_url":
                runtime.showingEmbeddedDeviceDock = true
                runtime.embeddedDockMode = .web
                guard let urlString = url, !urlString.isEmpty else {
                    throw ToolBoxError.invalidParams("url is required for set_url action")
                }
                let full = urlString.hasPrefix("http") ? urlString : "http://\(urlString)"
                guard let target = URL(string: full) else {
                    throw ToolBoxError.invalidParams("Invalid URL format: \(urlString)")
                }
                runtime.targetWebURL = target
                return "✅ WebApp Preview URL navigated to: \(target.absoluteString)"

            case "switch_mode":
                runtime.showingEmbeddedDeviceDock = true
                guard let mode = mode else {
                    throw ToolBoxError.invalidParams("mode is required ('web', 'ios', or 'android')")
                }
                switch mode {
                case "web": runtime.embeddedDockMode = .web
                case "ios": runtime.embeddedDockMode = .ios
                case "android": runtime.embeddedDockMode = .android
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
                let visible = runtime.showingEmbeddedDeviceDock ? "Visible" : "Hidden"
                let currentMode = runtime.embeddedDockMode.rawValue
                let currentURL = runtime.targetWebURL?.absoluteString ?? "http://localhost:3000"
                return "Live Preview Dock: \(visible) | Mode: \(currentMode) | URL: \(currentURL) | Viewport: \(runtime.targetViewport)"

            default:
                throw ToolBoxError.invalidParams("Unknown action '\(action)'. Supported: open, close, reload, set_url, switch_mode, set_viewport, status")
            }
        }
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
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            // Scaled for 2M token context (up to 2,000,000 chars)
            if content.count > 2_000_000 {
                return String(content.prefix(2_000_000)) + "\n\n... (file truncated at 2M chars, total: \(content.count) chars)"
            }
            return content
        } catch {
            // Fallback for different encodings
            if let content = try? String(contentsOf: url, encoding: .isoLatin1) {
                if content.count > 2_000_000 {
                    return String(content.prefix(2_000_000)) + "\n\n... (file truncated at 2M chars, total: \(content.count) chars)"
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
        if output.count > 500_000 {
            return String(output.prefix(500_000)) + "\n... (results truncated at 500K chars)"
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
        
        let target = await MainActor.run { AgentToolBox.shared.executionTarget }
        
        // If a remote SSH server is selected, route execution to the cloud/SSH server
        if case .remote(let server) = target {
            return try await executeRemote(command: command, server: server, params: params)
        }
        
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
        // caches to the external drive so the internal SSD is never exhausted (0 bytes free).
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
        }
        
        process.environment = env
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        try process.run()

        // Mirror the native macOS command to both the IDE Console and its
        // interactive Terminal immediately. The command is still executed
        // by this Process, not simulated in the UI.
        NotificationCenter.default.post(
            name: NSNotification.Name("MicroCodeAgentTerminalCommand"),
            object: nil,
            userInfo: [
                "phase": "started",
                "command": command,
                "cwd": targetCwd
            ]
        )
        
        // Builds and first dependency installs may take several minutes.
        // Match AgentToolBox's bounded timeout rather than killing a healthy
        // native process after 45 seconds.
        let deadline = DispatchTime.now() + .seconds(600)
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            if process.isRunning { process.terminate() }
        }
        
        process.waitUntilExit()
        
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        
        var output = stdout
        if !stderr.isEmpty { output += "\n[stderr]\n\(stderr)" }
        let didSucceed = process.terminationStatus == 0
        if !didSucceed { output = "[exit code: \(process.terminationStatus)]\n\(output)" }
        
        // Broadcast to IDE Terminal & Console
        NotificationCenter.default.post(
            name: NSNotification.Name("MicroCodeAgentTerminalCommand"),
            object: nil,
            userInfo: [
                "command": command,
                "output": output,
                "cwd": targetCwd,
                "exitCode": Int(process.terminationStatus),
                "phase": "completed"
            ]
        )
        
        // A non-zero command must be a failed tool result.  Previously this
        // returned ordinary text, so the agent recorded a failed xcodebuild
        // as success and later tried to complete from prose alone.
        let boundedOutput = output.count > 1_000_000
            ? String(output.suffix(1_000_000)).trimmingCharacters(in: .whitespacesAndNewlines) + "\n... (leading output truncated at 1M chars)"
            : output
        guard didSucceed else {
            throw ToolBoxError.executionFailed(boundedOutput.isEmpty
                ? "Command exited with status \(process.terminationStatus)."
                : boundedOutput)
        }
        return boundedOutput
    }
    
    /// Remote execution over OpenSSH when a remote server / VPS / RunPod target is active
    private func executeRemote(command: String, server: RemoteConnectionConfig, params: [String: Any]) async throws -> String {
        let targetCwd = (params["cwd"] as? String) ?? ""
        let remoteCommand = targetCwd.isEmpty ? command : "cd \(targetCwd) && \(command)"
        
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
        
        // Unlock SSH key in macOS Keychain if present
        let keychainTask = Process()
        keychainTask.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-add")
        keychainTask.arguments = ["--apple-load-keychain"]
        try? keychainTask.run()
        keychainTask.waitUntilExit()
        
        var effectivePassword = server.password
        if effectivePassword.isEmpty {
            if let saved = UserDefaults.standard.dictionary(forKey: "ssh_saved_passwords")?[server.host] as? String {
                effectivePassword = saved
            }
        }
        
        let scriptFeed = """
        \(remoteCommand)
        exit $?
        """
        
        let rawOutput: String
        let exitCode: Int32
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        
        var args = [
            "-tt",
            "-o", "ServerAliveInterval=15",
            "-o", "TCPKeepAlive=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=15",
            "-p", "\(server.port)"
        ]
        if !server.keyPath.isEmpty {
            let expanded = (server.keyPath as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                args.append(contentsOf: ["-i", expanded])
            }
        }
        args.append("\(server.username)@\(server.host)")
        process.arguments = args
        
        var env = ProcessInfo.processInfo.environment
        var tempAskPass: String? = nil
        var tempPassFile: String? = nil
        
        if !effectivePassword.isEmpty {
            let unique = ProcessInfo.processInfo.globallyUniqueString
            let passPath = "/tmp/mc_pass_\(unique).txt"
            let askPath = "/tmp/mc_ask_\(unique).sh"
            
            try? (effectivePassword + "\n").write(toFile: passPath, atomically: true, encoding: .utf8)
            let chmodP = Process()
            chmodP.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodP.arguments = ["600", passPath]
            try? chmodP.run()
            chmodP.waitUntilExit()
            
            let askScript = "#!/bin/sh\ncat \"\(passPath)\"\n"
            try? askScript.write(toFile: askPath, atomically: true, encoding: .utf8)
            let chmodA = Process()
            chmodA.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodA.arguments = ["700", askPath]
            try? chmodA.run()
            chmodA.waitUntilExit()
            
            env["SSH_ASKPASS"] = askPath
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env["DISPLAY"] = ":0"
            tempAskPass = askPath
            tempPassFile = passPath
        }
        process.environment = env
        
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        do {
            try process.run()
            
            if let data = scriptFeed.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
                try? stdinPipe.fileHandleForWriting.close()
            }
            
            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            if let tempAskPass = tempAskPass { try? FileManager.default.removeItem(atPath: tempAskPass) }
            if let tempPassFile = tempPassFile { try? FileManager.default.removeItem(atPath: tempPassFile) }
            
            var combined = String(data: outData, encoding: .utf8) ?? ""
            if let errStr = String(data: errData, encoding: .utf8), !errStr.isEmpty {
                combined += "\n" + errStr
            }
            rawOutput = combined
            exitCode = process.terminationStatus
        } catch {
            if let tempAskPass = tempAskPass { try? FileManager.default.removeItem(atPath: tempAskPass) }
            if let tempPassFile = tempPassFile { try? FileManager.default.removeItem(atPath: tempPassFile) }
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
        if scriptPath == nil || !FileManager.default.fileExists(atPath: scriptPath!) {
            let devCandidate = "/Users/dotmini/Documents/SX/codetunner-native/mcp-server.py"
            if FileManager.default.fileExists(atPath: devCandidate) {
                scriptPath = devCandidate
            }
        }
        
        guard let path = scriptPath, FileManager.default.fileExists(atPath: path) else {
            print("[MCPClient] Error: mcp-server.py not found across bundle, workspace, CWD, or repo root")
            return
        }
        
        // Safely check for a real Python binary before attempting to spawn
        let safePython = [
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
