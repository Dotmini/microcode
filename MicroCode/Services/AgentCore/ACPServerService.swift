//
//  ACPServerService.swift
//  MicroCode
//
//  ACP Server Service — Exposes MicroCode as a standards-compliant Agent Client Protocol (ACP v1)
//  JSON-RPC 2.0 agent for external IDEs (Zed, JetBrains, Neovim, VS Code).
//  Launched via CLI flag: `MicroCode --acp-server [--workspace /path]`
//

import Foundation

// MARK: - ACP Server Service

/// Allows external IDEs to use MicroCode’s AI capabilities as an ACP v1 agent over stdio.
@MainActor
class ACPServerService: ObservableObject {
    static let shared = ACPServerService()
    
    @Published var isServing = false
    @Published var clientName: String?
    @Published var requestCount = 0
    
    private var ndjsonParser = ACPNDJSONParser()
    private var sessions: [String: String] = [:] // sessionId -> cwd
    private var sessionModels: [String: String] = [:] // sessionId -> optional model override
    private var sessionModes: [String: String] = [:] // sessionId -> agent/plan/ask
    private var sessionHistory: [String: [[(String, Any)]]] = [:]
    private var activePromptTasks: [String: Task<Void, Never>] = [:]
    private var cancelledSessions: Set<String> = []
    private var supportsClientReadTextFile = false
    private var supportsClientWriteTextFile = false
    private var supportsClientTerminal = false
    
    // MARK: - Server Lifecycle
    
    /// Start serving as an ACP 1.0 JSON-RPC 2.0 agent on stdin/stdout
    func startServing(workspacePath: String) {
        guard !isServing else { return }
        isServing = true
        ndjsonParser.reset()
        readStdinLoop(workspacePath: workspacePath)
    }
    
    /// Stop the ACP server
    func stopServing() {
        isServing = false
        for task in activePromptTasks.values {
            task.cancel()
        }
        activePromptTasks.removeAll()
    }
    
    // MARK: - Stdin Processing
    
    private func readStdinLoop(workspacePath: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let stdin = FileHandle.standardInput
            
            while true {
                let data = stdin.availableData
                guard !data.isEmpty else {
                    DispatchQueue.main.async {
                        self?.isServing = false
                    }
                    break
                }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.isServing else { return }
                    let messages = self.ndjsonParser.feed(data)
                    for message in messages {
                        self.handleRequest(message, workspacePath: workspacePath)
                    }
                }
            }
        }
    }
    
    // MARK: - Request Handling (ACP v1 JSON-RPC 2.0 + Legacy Fallback)
    
    private func handleRequest(_ json: [String: Any], workspacePath: String) {
        requestCount += 1
        
        // 1. Standard Agent Client Protocol (ACP 1.0) JSON-RPC 2.0
        if (json["jsonrpc"] as? String) == "2.0" {
            handleJsonRpcRequest(json, defaultWorkspace: workspacePath)
            return
        }
        
        // 2. Legacy custom NDJSON fallback
        let type = json["type"] as? String ?? ""
        let requestId = json["id"] as? String ?? UUID().uuidString
        
        switch type {
        case "task", "user_message":
            let content = json["content"] as? String ?? json["message"] as? String ?? ""
            handleLegacyTask(requestId: requestId, content: content, workspacePath: workspacePath)
            
        case "cancel":
            for sid in activePromptTasks.keys {
                cancelledSessions.insert(sid)
                activePromptTasks[sid]?.cancel()
            }
            writeNDJSON(["type": "cancelled", "id": requestId, "message": "Task cancelled"])
            
        case "ping":
            writeNDJSON(["type": "pong", "id": requestId])
            
        case "capabilities":
            writeNDJSON([
                "type": "capabilities_response",
                "id": requestId,
                "tools": ["read_file", "write_file", "edit_file", "run_terminal", "search_files", "git_status"]
            ])
            
        default:
            writeNDJSON([
                "type": "error",
                "id": requestId,
                "message": "Unknown request type: \(type)"
            ])
        }
    }
    
    private func handleJsonRpcRequest(_ json: [String: Any], defaultWorkspace: String) {
        let method = json["method"] as? String ?? ""
        let reqId = json["id"] // May be Int, String, or nil (for notifications)
        let params = json["params"] as? [String: Any] ?? [:]
        
        switch method {
        case "initialize":
            if let clientInfo = params["clientInfo"] as? [String: Any],
               let name = clientInfo["name"] as? String {
                self.clientName = name
            }
            if let clientCaps = params["clientCapabilities"] as? [String: Any] {
                if let fsCaps = clientCaps["fs"] as? [String: Any] {
                    supportsClientReadTextFile = (fsCaps["readTextFile"] as? Bool) ?? false
                    supportsClientWriteTextFile = (fsCaps["writeTextFile"] as? Bool) ?? false
                }
                supportsClientTerminal = (clientCaps["terminal"] as? Bool) ?? false
            }
            guard let id = reqId else { return }
            writeNDJSON([
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "protocolVersion": 1,
                    "agentInfo": [
                        "name": "microcode",
                        "title": "MicroCode Sovereign Agentic Harness",
                        "version": "2.4.0"
                    ],
                    "agentCapabilities": [
                        "loadSession": true,
                        "mcpCapabilities": [
                            "http": true,
                            "sse": true
                        ],
                        "promptCapabilities": [
                            "image": true,
                            "embeddedContext": true
                        ]
                    ],
                    "authMethods": [] as [[String: Any]]
                ]
            ])
            
        case "authenticate":
            guard let id = reqId else { return }
            writeNDJSON(["jsonrpc": "2.0", "id": id, "result": [:] as [String: Any]])
            
        case "session/new":
            guard let id = reqId else { return }
            let cwd = params["cwd"] as? String ?? defaultWorkspace
            let sid = "sess_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
            sessions[sid] = cwd
            sessionModes[sid] = "agent"
            sessionHistory[sid] = []
            writeNDJSON([
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "sessionId": sid,
                    "modes": [
                        "currentModeId": "agent",
                        "availableModes": [
                            ["id": "agent", "name": "Autonomous Agent", "description": "Full workspace read/edit/terminal/MCP agentic execution"],
                            ["id": "plan", "name": "Architect Plan", "description": "Read-only codebase research & architectural blueprint"],
                            ["id": "arena", "name": "Best-of-N Arena", "description": "Parallel cross-vendor Git Worktree Arena"]
                        ]
                    ]
                ]
            ])
            
        case "session/load":
            guard let id = reqId else { return }
            let sid = params["sessionId"] as? String ?? ("sess_" + UUID().uuidString.prefix(8))
            let cwd = params["cwd"] as? String ?? defaultWorkspace
            sessions[sid] = cwd
            if sessionHistory[sid] == nil { sessionHistory[sid] = [] }
            writeNDJSON(["jsonrpc": "2.0", "id": id, "result": [:] as [String: Any]])

        case "session/set_mode", "session/setMode":
            let sid = params["sessionId"] as? String ?? "default"
            if let modeId = params["modeId"] as? String {
                sessionModes[sid] = modeId
            }
            if let id = reqId {
                writeNDJSON(["jsonrpc": "2.0", "id": id, "result": [:] as [String: Any]])
            }

        case "session/set_model", "session/setModel":
            let sid = params["sessionId"] as? String ?? "default"
            if let modelId = params["modelId"] as? String {
                sessionModels[sid] = modelId
            }
            if let id = reqId {
                writeNDJSON(["jsonrpc": "2.0", "id": id, "result": [:] as [String: Any]])
            }
            
        case "session/cancel":
            if let sid = params["sessionId"] as? String {
                cancelledSessions.insert(sid)
                activePromptTasks[sid]?.cancel()
            }
            // `session/cancel` is a notification in ACP v1; only reply if client sent an id
            if let id = reqId {
                writeNDJSON(["jsonrpc": "2.0", "id": id, "result": [:] as [String: Any]])
            }
            
        case "session/prompt":
            guard let id = reqId else { return }
            let sid = params["sessionId"] as? String ?? "default"
            let promptBlocks = params["prompt"] as? [[String: Any]] ?? []
            var promptText = ""
            for block in promptBlocks {
                if let t = block["text"] as? String {
                    promptText += (promptText.isEmpty ? "" : "\n") + t
                } else if let res = block["resource"] as? [String: Any],
                          let t = res["text"] as? String {
                    let uri = res["uri"] as? String ?? "context"
                    promptText += "\n[File: \(uri)]\n\(t)\n"
                }
            }
            if promptText.isEmpty, let direct = params["text"] as? String {
                promptText = direct
            }
            handleAcpSessionPrompt(requestId: id, sessionId: sid, promptText: promptText, workspacePath: sessions[sid] ?? defaultWorkspace)
            
        default:
            // Never reply to unknown notifications (JSON-RPC 2.0 spec)
            guard let id = reqId else { return }
            writeNDJSON([
                "jsonrpc": "2.0",
                "id": id,
                "error": [
                    "code": -32601,
                    "message": "Method not found: \(method)"
                ]
            ])
        }
    }
    
    private func handleAcpSessionPrompt(requestId: Any, sessionId: String, promptText: String, workspacePath: String) {
        cancelledSessions.remove(sessionId)
        var history = sessionHistory[sessionId] ?? []
        let activeMode = sessionModes[sessionId] ?? "agent"
        let customModel = sessionModels[sessionId]

        let task = Task { @MainActor in
            do {
                // Special Mode: Best-of-N Arena directly inside Zed / JetBrains / Neovim via ACP!
                if activeMode == "arena" {
                    let arenaReport = await SubAgentHarness.shared.runBestOfNArena(
                        objective: promptText,
                        workspacePath: workspacePath
                    )
                    self.emitMessageChunk(sessionId: sessionId, text: arenaReport)
                    history.append([("_role", "user"), ("text", promptText)])
                    history.append([("_role", "assistant"), ("text", arenaReport)])
                    self.sessionHistory[sessionId] = history
                    self.activePromptTasks.removeValue(forKey: sessionId)
                    self.writeNDJSON([
                        "jsonrpc": "2.0",
                        "id": requestId,
                        "result": ["stopReason": "end_turn"]
                    ])
                    return
                }

                await MCPClient.shared.ensureConnected(workspacePath: workspacePath)
                let toolbox = AgentToolBox.shared
                let allSchemas = toolbox.toolSchemas()
                let filteredSchemas: [[String: Any]] = {
                    if activeMode == "plan" {
                        let readOnlyNames: Set<String> = [
                            "file_read", "multi_file_read", "grep_search", "list_directory_tree",
                            "find_symbol", "git_status", "git_diff", "get_diagnostics", "lsp_intelligence"
                        ]
                        return allSchemas.filter { readOnlyNames.contains($0["name"] as? String ?? "") }
                    }
                    return PNSGanglionRouter.shared.filterMCPToolsForSubAgent(
                        archetype: "autonomous_loop",
                        taskPrompt: promptText,
                        workspacePath: workspacePath,
                        allSchemas: allSchemas,
                        maxMCPTools: 12,
                        synapseLookup: { cat, tract, node, proj in
                            PNSOrchestrator.shared.lookupSynapse(taskCategory: cat, tract: tract, targetNodeId: node, projectPath: proj)
                        }
                    )
                }()

                let rulesSnippet = MultiPlatformRulesEngine.shared.formatPromptSection(maxTokens: 450)
                let sysPrompt = """
                You are MicroCode Sovereign AI Agent operating via Agent Client Protocol (ACP v1) in workspace: \(workspacePath).
                Mode: \(activeMode.uppercased()).
                \(rulesSnippet)
                Use workspace tools (`file_read`, `replace_in_file`, `file_write`, `shell`, `grep_search`, `get_diagnostics`, `swarm_orchestrator`, `mcp__*`) autonomously to inspect, edit, and verify code before presenting your final answer.
                """

                history.append([("_role", "user"), ("text", promptText)])
                let endpoint = AgentModelEndpoint(
                    authSource: .auto,
                    provider: "inherit",
                    model: customModel ?? "inherit"
                )

                let maxIterations = 12
                var iteration = 0

                while iteration < maxIterations {
                    if Task.isCancelled || self.cancelledSessions.contains(sessionId) {
                        break
                    }
                    iteration += 1

                    let rawTurn = try await SubAgentHarness.shared.dispatchModelTurnWithFailover(
                        messages: history,
                        systemPrompt: sysPrompt,
                        endpoint: endpoint,
                        tools: filteredSchemas
                    )
                    let parsedFallback = SubAgentHarness.shared.parseUniversalFallbackToolCalls(
                        from: rawTurn.text,
                        senderRole: "ACP Server",
                        senderBadge: "MicroCode ACP"
                    )
                    let toolCalls = rawTurn.toolCalls.isEmpty ? parsedFallback.toolCalls : rawTurn.toolCalls
                    let assistantText = AIStructuredTurnCodec.stripThoughtTags(parsedFallback.cleanedText)

                    if !assistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.emitMessageChunk(sessionId: sessionId, text: assistantText + (toolCalls.isEmpty ? "" : "\n\n"))
                    }

                    if toolCalls.isEmpty {
                        history.append([("_role", "assistant"), ("text", assistantText)])
                        break
                    }

                    var toolSummaryLines: [String] = []
                    var toolResultBlocks: [String] = []

                    for tc in toolCalls {
                        if Task.isCancelled || self.cancelledSessions.contains(sessionId) {
                            break
                        }
                        let tcId = tc.id.isEmpty ? ("tc_" + UUID().uuidString.prefix(10)) : tc.id
                        let kind = Self.acpToolKind(for: tc.name)
                        let title = Self.acpToolTitle(name: tc.name, args: tc.arguments)

                        self.writeNDJSON([
                            "jsonrpc": "2.0",
                            "method": "session/update",
                            "params": [
                                "sessionId": sessionId,
                                "update": [
                                    "sessionUpdate": "tool_call",
                                    "toolCallId": tcId,
                                    "title": title,
                                    "kind": kind,
                                    "status": "in_progress",
                                    "rawInput": Self.jsonSafeDictionary(tc.arguments)
                                ]
                            ]
                        ])

                        do {
                            let rawOut = try await AgentExecutionContext.$workspaceRoot.withValue(workspacePath) {
                                try await toolbox.execute(tc.name, params: tc.arguments)
                            }
                            let compressed = TokenOptimizer.shared.compressToolOutput(rawOut, toolName: tc.name, budget: 12_000)
                            self.writeNDJSON([
                                "jsonrpc": "2.0",
                                "method": "session/update",
                                "params": [
                                    "sessionId": sessionId,
                                    "update": [
                                        "sessionUpdate": "tool_call_update",
                                        "toolCallId": tcId,
                                        "status": "completed",
                                        "content": [
                                            [
                                                "type": "content",
                                                "content": [
                                                    "type": "text",
                                                    "text": String(compressed.prefix(4000))
                                                ]
                                            ]
                                        ]
                                    ]
                                ]
                            ])
                            toolSummaryLines.append("[Called tool: \(tc.name)]")
                            toolResultBlocks.append("✅ \(tc.name) output:\n\(compressed)")
                        } catch {
                            let errText = error.localizedDescription
                            self.writeNDJSON([
                                "jsonrpc": "2.0",
                                "method": "session/update",
                                "params": [
                                    "sessionId": sessionId,
                                    "update": [
                                        "sessionUpdate": "tool_call_update",
                                        "toolCallId": tcId,
                                        "status": "failed",
                                        "content": [
                                            [
                                                "type": "content",
                                                "content": [
                                                    "type": "text",
                                                    "text": "❌ \(tc.name) failed: \(errText)"
                                                ]
                                            ]
                                        ]
                                    ]
                                ]
                            ])
                            toolSummaryLines.append("[Called tool: \(tc.name) (failed)]")
                            toolResultBlocks.append("❌ \(tc.name) error: \(errText)")
                        }
                    }

                    let combinedAssistant = assistantText.isEmpty
                        ? toolSummaryLines.joined(separator: "\n")
                        : assistantText + "\n" + toolSummaryLines.joined(separator: "\n")
                    history.append([("_role", "assistant"), ("text", combinedAssistant)])
                    history.append([("_role", "user"), ("text", toolResultBlocks.joined(separator: "\n\n---\n\n"))])
                }

                let wasCancelled = Task.isCancelled || self.cancelledSessions.contains(sessionId)
                if history.count > 30, let first = history.first {
                    history = [first] + Array(history.suffix(26))
                }
                self.sessionHistory[sessionId] = history
                self.activePromptTasks.removeValue(forKey: sessionId)
                self.writeNDJSON([
                    "jsonrpc": "2.0",
                    "id": requestId,
                    "result": [
                        "stopReason": wasCancelled ? "cancelled" : "end_turn"
                    ]
                ])
            } catch {
                self.activePromptTasks.removeValue(forKey: sessionId)
                if Task.isCancelled || self.cancelledSessions.contains(sessionId) {
                    self.writeNDJSON([
                        "jsonrpc": "2.0",
                        "id": requestId,
                        "result": [
                            "stopReason": "cancelled"
                        ]
                    ])
                } else {
                    self.writeNDJSON([
                        "jsonrpc": "2.0",
                        "id": requestId,
                        "error": [
                            "code": -32000,
                            "message": error.localizedDescription
                        ]
                    ])
                }
            }
        }
        activePromptTasks[sessionId] = task
    }

    private func emitMessageChunk(sessionId: String, text: String) {
        guard !text.isEmpty else { return }
        writeNDJSON([
            "jsonrpc": "2.0",
            "method": "session/update",
            "params": [
                "sessionId": sessionId,
                "update": [
                    "sessionUpdate": "agent_message_chunk",
                    "content": [
                        "type": "text",
                        "text": text
                    ]
                ]
            ]
        ])
    }

    private static func acpToolKind(for toolName: String) -> String {
        let lower = toolName.lowercased()
        if lower.contains("read") || lower.contains("list") || lower.contains("status") || lower.contains("diff") {
            return "read"
        }
        if lower.contains("write") || lower.contains("replace") || lower.contains("patch") || lower.contains("edit") {
            return "edit"
        }
        if lower.contains("grep") || lower.contains("search") || lower.contains("find") {
            return "search"
        }
        if lower.contains("shell") || lower.contains("run") || lower.contains("test") || lower.contains("compile") {
            return "execute"
        }
        return "other"
    }

    private static func acpToolTitle(name: String, args: [String: Any]) -> String {
        if let path = (args["path"] as? String) ?? (args["file_path"] as? String) {
            return "\(name): \(path)"
        }
        if let cmd = args["command"] as? String {
            let short = cmd.count > 64 ? String(cmd.prefix(61)) + "..." : cmd
            return "\(name): \(short)"
        }
        if let query = (args["query"] as? String) ?? (args["pattern"] as? String) {
            return "\(name): \(query.prefix(50))"
        }
        return name
    }

    private static func jsonSafeDictionary(_ dict: [String: Any]) -> [String: Any] {
        if JSONSerialization.isValidJSONObject(dict) {
            return dict
        }
        var out: [String: Any] = [:]
        for (k, v) in dict {
            if let s = v as? String { out[k] = s }
            else if let n = v as? NSNumber { out[k] = n }
            else if let b = v as? Bool { out[k] = b }
            else { out[k] = String(describing: v) }
        }
        return out
    }
    
    private func handleLegacyTask(requestId: String, content: String, workspacePath: String) {
        writeNDJSON([
            "type": "task_started",
            "id": requestId,
            "message": "Processing task"
        ])
        
        Task { @MainActor in
            var fullResponse = ""
            do {
                let stream = try await AIClient.shared.streamCompletion(messages: [
                    (role: "system", content: "You are MicroCode AI Agent operating in \(workspacePath)."),
                    (role: "user", content: content)
                ])
                for try await chunk in stream {
                    fullResponse += chunk
                    self.writeNDJSON([
                        "type": "text",
                        "id": requestId,
                        "content": chunk
                    ])
                }
                self.writeNDJSON([
                    "type": "result",
                    "id": requestId,
                    "session_id": UUID().uuidString,
                    "result": fullResponse
                ])
            } catch {
                self.writeNDJSON([
                    "type": "error",
                    "id": requestId,
                    "message": error.localizedDescription
                ])
            }
        }
    }
    
    // MARK: - NDJSON Output
    
    private func writeNDJSON(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        var outputData = data
        outputData.append(0x0A)
        try? FileHandle.standardOutput.write(contentsOf: outputData)
    }
}
