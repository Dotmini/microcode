//
//  ACPProtocol.swift
//  MicroCode
//
//  Agent Client Protocol — Core definitions for external coding agent integration.
//  Supports Claude Code CLI, AGY CLI, Aider, and custom agents.
//

import Foundation

// MARK: - Agent Type

/// Supported external coding agent types
enum ACPAgentType: String, Codable, CaseIterable, Identifiable {
    case claudeCode     // Anthropic Claude Code CLI
    case agy            // Google Antigravity CLI
    case openCode       // OpenCode CLI & ACP Server
    case codexEngine    // OpenAI Codex CLI
    case geminiCLI      // Google Gemini CLI (@google/gemini-cli)
    case cursorAgent    // Cursor Background / CLI Agent
    case githubCopilot  // GitHub Copilot CLI (@github/copilot-cli)
    case goose          // Block Goose ACP Agent (goose acp)
    case cline          // Cline CLI Agent
    case qwenCode       // Alibaba Qwen Code CLI (@qwen-code/qwen-code)
    case aider          // Aider CLI
    case zedEngine      // Zed / ZCode Assistant
    case custom         // Custom agent binary
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .agy: return "Antigravity (AGY)"
        case .openCode: return "OpenCode"
        case .codexEngine: return "OpenAI Codex"
        case .geminiCLI: return "Google Gemini CLI"
        case .cursorAgent: return "Cursor Agent"
        case .githubCopilot: return "GitHub Copilot CLI"
        case .goose: return "Block Goose"
        case .cline: return "Cline CLI"
        case .qwenCode: return "Qwen Code"
        case .aider: return "Aider"
        case .zedEngine: return "Zed / ZCode"
        case .custom: return "Custom Agent"
        }
    }
    
    /// Canonical engine ID used in LocalEcosystemDiscovery and AIModelCatalog
    var engineId: String {
        switch self {
        case .claudeCode: return "claude_code"
        case .agy: return "agy"
        case .openCode: return "opencode"
        case .codexEngine: return "codex"
        case .geminiCLI: return "gemini_cli"
        case .cursorAgent: return "cursor"
        case .githubCopilot: return "copilot"
        case .goose: return "goose"
        case .cline: return "cline"
        case .qwenCode: return "qwen"
        case .aider: return "aider"
        case .zedEngine: return "zed"
        case .custom: return "custom"
        }
    }
    
    /// Key for AIProviderBrandIcon (100% official brand logo)
    var brandIconKey: String {
        return engineId
    }
    
    var iconName: String {
        switch self {
        case .claudeCode: return "brain.head.profile"
        case .agy: return "sparkles"
        case .openCode: return "laptopcomputer"
        case .codexEngine: return "cpu"
        case .geminiCLI: return "terminal.fill"
        case .cursorAgent: return "cube.fill"
        case .githubCopilot: return "chevron.left.forwardslash.chevron.right"
        case .goose: return "bird.fill"
        case .cline: return "bolt.horizontal.fill"
        case .qwenCode: return "sparkles.rectangle.stack"
        case .aider: return "terminal"
        case .zedEngine: return "chevron.left.forwardslash.chevron.right"
        case .custom: return "plus.circle"
        }
    }
    
    var defaultCommand: String {
        switch self {
        case .claudeCode: return "claude"
        case .agy: return "agy"
        case .openCode: return "opencode"
        case .codexEngine: return "codex"
        case .geminiCLI: return "gemini"
        case .cursorAgent: return "cursor-agent"
        case .githubCopilot: return "copilot"
        case .goose: return "goose"
        case .cline: return "cline"
        case .qwenCode: return "qwen"
        case .aider: return "aider"
        case .zedEngine: return "zed"
        case .custom: return ""
        }
    }
    
    var brandColor: String {
        switch self {
        case .claudeCode: return "#D97757"
        case .agy: return "#4285F4"
        case .openCode: return "#E05A47"
        case .codexEngine: return "#10A37F"
        case .geminiCLI: return "#4796E3"
        case .cursorAgent: return "#F5F5F7"
        case .githubCopilot: return "#6E40C9"
        case .goose: return "#FF6B00"
        case .cline: return "#9B72CB"
        case .qwenCode: return "#615CED"
        case .aider: return "#00D084"
        case .zedEngine: return "#007ACC"
        case .custom: return "#8E8E93"
        }
    }
}

// MARK: - Connection State

/// Agent connection lifecycle state
enum ACPConnectionState: Equatable {
    case disconnected
    case connecting
    case initializing
    case ready
    case running(taskId: String)
    case error(String)
    
    var isActive: Bool {
        switch self {
        case .ready, .running: return true
        default: return false
        }
    }
    
    var statusLabel: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .initializing: return "Initializing…"
        case .ready: return "Ready"
        case .running: return "Running"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Stream Events (Unified across all agents)

/// Unified stream events from any external agent
enum ACPStreamEvent: Identifiable {
    case text(String)
    case thinking(String)
    case toolCall(ACPToolCall)
    case toolResult(ACPToolResult)
    case permissionRequest(ACPPermissionRequest)
    case systemInfo(ACPSystemInfo)
    case progress(ACPProgress)
    case error(String)
    case complete(ACPTaskResult)
    case sessionInit(ACPSessionInit)
    
    var id: String {
        switch self {
        case .text(let t): return "text_\(t.hashValue)"
        case .thinking(let t): return "think_\(t.hashValue)"
        case .toolCall(let tc): return "tc_\(tc.id)"
        case .toolResult(let tr): return "tr_\(tr.toolCallId)"
        case .permissionRequest(let pr): return "perm_\(pr.id)"
        case .systemInfo(let si): return "sys_\(si.message.hashValue)"
        case .progress(let p): return "prog_\(p.id)"
        case .error(let e): return "err_\(e.hashValue)"
        case .complete(let r): return "done_\(r.sessionId)"
        case .sessionInit(let s): return "init_\(s.sessionId)"
        }
    }
}

/// Tool call event from external agent
struct ACPToolCall: Identifiable {
    let id: String
    let name: String               // "Read", "Edit", "Bash", "Write", etc.
    let input: [String: Any]       // Tool arguments
    var displaySummary: String {    // Human-readable summary
        switch name.lowercased() {
        case "read", "read_file":
            return "Reading \(input["file_path"] as? String ?? input["path"] as? String ?? "file")"
        case "edit", "edit_file":
            return "Editing \(input["file_path"] as? String ?? input["path"] as? String ?? "file")"
        case "write", "write_file":
            return "Writing \(input["file_path"] as? String ?? input["path"] as? String ?? "file")"
        case "bash":
            let cmd = input["command"] as? String ?? ""
            let short = cmd.count > 60 ? String(cmd.prefix(57)) + "..." : cmd
            return "Running: \(short)"
        default:
            return "\(name)"
        }
    }
}

/// Tool result from external agent
struct ACPToolResult {
    let toolCallId: String
    let content: String
    let isError: Bool
    var toolName: String? = nil
}

/// Permission request from agent needing user approval
struct ACPPermissionRequest: Identifiable {
    let id: String
    let tool: String               // "Edit", "Bash", "Write"
    let filePath: String?
    let oldContent: String?        // For diff display
    let newContent: String?        // For diff display
    let command: String?           // For bash commands
    let description: String
    var isApproved: Bool? = nil    // nil = pending, true = approved, false = rejected
}

/// System info event (metadata, retry, status)
struct ACPSystemInfo {
    let message: String
    let subtype: String?           // "init", "api_retry", "plugin_install"
}

/// Progress tracking for long-running tasks
struct ACPProgress: Identifiable {
    let id: String
    let step: Int
    let total: Int?
    let message: String
}

/// Task completion result
struct ACPTaskResult {
    let sessionId: String
    let result: String
    let totalCostUSD: Double?
    let tokensUsed: Int?
    let model: String?
}

/// Session initialization metadata
struct ACPSessionInit {
    let sessionId: String
    let model: String?
    let tools: [String]
    let capabilities: [String]
}

// MARK: - Agent Configuration

/// Persistent agent configuration (saved to UserDefaults)
struct ACPAgentConfig: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var type: ACPAgentType
    var command: String            // Binary path or name
    var arguments: [String]        // Extra CLI arguments
    var environment: [String: String]  // Env vars
    var permissionMode: ACPPermissionMode
    var isEnabled: Bool
    var autoDetected: Bool         // Found via `which`
    var lastConnected: Date?
    
    static func defaultConfig(for type: ACPAgentType, command: String) -> ACPAgentConfig {
        ACPAgentConfig(
            id: UUID(),
            name: type.displayName,
            type: type,
            command: command,
            arguments: [],
            environment: [:],
            permissionMode: .reviewEach,
            isEnabled: true,
            autoDetected: true,
            lastConnected: nil
        )
    }
}

/// Permission mode for external agent actions
enum ACPPermissionMode: String, Codable, CaseIterable {
    case reviewEach        // Show approval UI for each write/bash action
    case autoApproveReads  // Auto-approve reads, ask for writes/bash
    case fullAuto          // Auto-approve everything (--dangerously-skip-permissions)
    
    var displayName: String {
        switch self {
        case .reviewEach: return "Review Each Action"
        case .autoApproveReads: return "Auto-Approve Reads"
        case .fullAuto: return "Full Auto (Trusted)"
        }
    }
    
    var claudeFlag: String {
        switch self {
        case .reviewEach: return "auto"
        case .autoApproveReads: return "auto"
        case .fullAuto: return "auto"
        }
    }
    
    var claudeAllowedTools: [String] {
        switch self {
        case .reviewEach: return ["Read", "Grep", "Glob", "LS", "Edit", "Write", "Bash"]
        case .autoApproveReads: return ["Read", "Grep", "Glob", "LS", "Edit", "Write", "Bash"]
        case .fullAuto: return ["Read", "Grep", "Glob", "LS", "Edit", "Write", "Bash"]
        }
    }
}

// MARK: - NDJSON Parser (Byte-Level UTF-8 Safe)

/// High-performance NDJSON line parser for agent stdio streams.
/// Buffers raw bytes and splits on 0x0A ('\n') BEFORE decoding UTF-8 so multibyte
/// characters (Thai, CJK, Emoji) split across OS pipe chunks are never dropped.
struct ACPNDJSONParser {
    private var rawBuffer = Data()
    
    /// Feed raw data from stdout pipe and return complete JSON lines
    mutating func feed(_ data: Data) -> [[String: Any]] {
        rawBuffer.append(data)
        
        var results: [[String: Any]] = []
        while let newlineIdx = rawBuffer.firstIndex(of: 0x0A) {
            let lineData = rawBuffer.subdata(in: 0..<newlineIdx)
            rawBuffer.removeSubrange(0...newlineIdx)
            
            let line = String(decoding: lineData, as: UTF8.self)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            if let jsonData = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                results.append(json)
            } else {
                // Plain-text line fallback so stdout from non-JSON CLI agents (or errors) is never dropped
                results.append(["type": "text", "text": trimmed + "\n", "_raw": true])
            }
        }
        return results
    }
    
    /// Flush any remaining buffered bytes on EOF
    mutating func flushRemaining() -> [[String: Any]] {
        guard !rawBuffer.isEmpty else { return [] }
        let line = String(decoding: rawBuffer, as: UTF8.self)
        rawBuffer.removeAll(keepingCapacity: false)
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let jsonData = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            return [json]
        } else {
            return [["type": "text", "text": trimmed + "\n", "_raw": true]]
        }
    }
    
    /// Reset the buffer
    mutating func reset() {
        rawBuffer.removeAll(keepingCapacity: false)
    }
}

// MARK: - Standard ACP 1.0 JSON-RPC 2.0 Codec (https://agentclientprotocol.com)

/// Implements the official Agent Client Protocol (ACP v1) JSON-RPC 2.0 framing,
/// methods (`initialize`, `session/new`, `session/prompt`, `session/cancel`),
/// notifications (`session/update`), and bidirectional client capabilities
/// (`session/request_permission`, `fs/read_text_file`, `fs/write_text_file`).
struct ACPStandardJsonRpcParser {
    static let protocolVersion: Int = 1
    
    static func buildInitializeRequest(id: Int) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "method": "initialize",
            "params": [
                "protocolVersion": protocolVersion,
                "clientInfo": [
                    "name": "MicroCode",
                    "title": "MicroCode Native AI IDE",
                    "version": "2.3.1"
                ],
                "clientCapabilities": [
                    "fs": [
                        "readTextFile": true,
                        "writeTextFile": true
                    ],
                    "terminal": true
                ]
            ]
        ]
    }
    
    static func buildSessionNewRequest(id: Int, cwd: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "method": "session/new",
            "params": [
                "cwd": cwd,
                "mcpServers": [] as [[String: Any]]
            ]
        ]
    }
    
    static func buildSessionPromptRequest(id: Int, sessionId: String, text: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "method": "session/prompt",
            "params": [
                "sessionId": sessionId,
                "prompt": [
                    [
                        "type": "text",
                        "text": text
                    ]
                ]
            ]
        ]
    }
    
    static func buildSessionCancelNotification(sessionId: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "method": "session/cancel",
            "params": [
                "sessionId": sessionId
            ]
        ]
    }
    
    static func buildPermissionResponse(requestId: Any, optionId: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": requestId,
            "result": [
                "outcome": [
                    "outcome": "selected",
                    "optionId": optionId
                ]
            ]
        ]
    }
    
    /// Parse an incoming JSON-RPC 2.0 ACP message into zero or more unified `ACPStreamEvent`s
    static func parseEvents(_ json: [String: Any]) -> [ACPStreamEvent] {
        guard (json["jsonrpc"] as? String) == "2.0" else { return [] }
        
        if let method = json["method"] as? String {
            let params = json["params"] as? [String: Any] ?? [:]
            switch method {
            case "session/update":
                guard let update = params["update"] as? [String: Any] else { return [] }
                let sessionUpdate = update["sessionUpdate"] as? String ?? ""
                switch sessionUpdate {
                case "agent_message_chunk":
                    if let content = update["content"] as? [String: Any],
                       let text = content["text"] as? String, !text.isEmpty {
                        return [.text(text)]
                    }
                    if let text = update["text"] as? String, !text.isEmpty {
                        return [.text(text)]
                    }
                case "agent_thought_chunk":
                    if let content = update["content"] as? [String: Any],
                       let text = content["text"] as? String, !text.isEmpty {
                        return [.thinking(text)]
                    }
                    if let text = update["text"] as? String, !text.isEmpty {
                        return [.thinking(text)]
                    }
                case "tool_call":
                    let tcId = update["toolCallId"] as? String ?? update["id"] as? String ?? UUID().uuidString
                    let title = update["title"] as? String ?? update["name"] as? String ?? "tool"
                    let rawInput = update["rawInput"] as? [String: Any] ?? update["input"] as? [String: Any] ?? [:]
                    return [.toolCall(ACPToolCall(id: tcId, name: title, input: rawInput))]
                case "tool_call_update":
                    let tcId = update["toolCallId"] as? String ?? update["id"] as? String ?? UUID().uuidString
                    let status = update["status"] as? String ?? ""
                    let isError = (status == "failed" || status == "error")
                    var textOut = ""
                    if let contentArr = update["content"] as? [[String: Any]] {
                        for item in contentArr {
                            if let inner = item["content"] as? [String: Any], let t = inner["text"] as? String {
                                textOut += t
                            } else if let t = item["text"] as? String {
                                textOut += t
                            }
                        }
                    } else if let rawOutput = update["rawOutput"] as? String {
                        textOut = rawOutput
                    }
                    if !textOut.isEmpty || status == "completed" || isError {
                        return [.toolResult(ACPToolResult(
                            toolCallId: tcId,
                            content: textOut.isEmpty ? status : textOut,
                            isError: isError,
                            toolName: update["title"] as? String
                        ))]
                    }
                case "plan":
                    if let entries = update["entries"] as? [[String: Any]], !entries.isEmpty {
                        let summary = entries.compactMap { $0["content"] as? String }.joined(separator: " → ")
                        return [.progress(ACPProgress(id: UUID().uuidString, step: 1, total: entries.count, message: summary))]
                    }
                default:
                    break
                }
            case "session/request_permission":
                let reqIdStr: String
                if let intId = json["id"] as? Int {
                    reqIdStr = String(intId)
                } else if let strId = json["id"] as? String {
                    reqIdStr = strId
                } else {
                    reqIdStr = UUID().uuidString
                }
                let toolCall = params["toolCall"] as? [String: Any] ?? [:]
                let title = toolCall["title"] as? String ?? toolCall["kind"] as? String ?? "Tool Execution"
                let rawInput = toolCall["rawInput"] as? [String: Any] ?? [:]
                let path = (toolCall["locations"] as? [[String: Any]])?.first?["path"] as? String
                    ?? rawInput["path"] as? String
                    ?? rawInput["file_path"] as? String
                let cmd = rawInput["command"] as? String
                return [.permissionRequest(ACPPermissionRequest(
                    id: reqIdStr,
                    tool: title,
                    filePath: path,
                    oldContent: rawInput["old_string"] as? String,
                    newContent: rawInput["new_string"] as? String ?? rawInput["content"] as? String,
                    command: cmd,
                    description: title
                ))]
            default:
                break
            }
            return []
        }
        
        if let error = json["error"] as? [String: Any] {
            let msg = error["message"] as? String ?? "ACP JSON-RPC error"
            return [.error(msg)]
        }
        
        if let result = json["result"] as? [String: Any] {
            if let sessionId = result["sessionId"] as? String {
                return [.sessionInit(ACPSessionInit(sessionId: sessionId, model: nil, tools: [], capabilities: ["acp-v1"]))]
            }
            if let stopReason = result["stopReason"] as? String {
                return [.complete(ACPTaskResult(
                    sessionId: "acp_turn_\(stopReason)",
                    result: "",
                    totalCostUSD: nil,
                    tokensUsed: nil,
                    model: nil
                ))]
            }
        }
        return []
    }
}

// MARK: - Claude Code Stream Event Parser

/// Parses Claude Code `--output-format stream-json` NDJSON events into ACPStreamEvents
struct ClaudeCodeStreamParser {
    
    static func parse(_ json: [String: Any]) -> ACPStreamEvent? {
        return parseAll(json).first
    }
    
    /// Parses all events contained in a single Claude Code stream-json line
    /// (e.g. an assistant message containing both text and tool_use blocks).
    static func parseAll(_ json: [String: Any]) -> [ACPStreamEvent] {
        let type = json["type"] as? String ?? ""
        
        switch type {
        case "system":
            if let ev = parseSystemEvent(json) { return [ev] }
            return []
            
        case "assistant":
            return parseAssistantMessages(json)
            
        case "user":
            // Tool results from Claude's own tool execution (supports both top-level and nested message.content)
            let content: [[String: Any]]? = {
                if let c = json["content"] as? [[String: Any]] { return c }
                if let msg = json["message"] as? [String: Any], let c = msg["content"] as? [[String: Any]] { return c }
                return nil
            }()
            if let content = content {
                var results: [ACPStreamEvent] = []
                for block in content {
                    if block["type"] as? String == "tool_result" {
                        let toolCallId = block["tool_use_id"] as? String ?? UUID().uuidString
                        let resultContent = extractTextContent(block["content"])
                        let isError = block["is_error"] as? Bool ?? false
                        results.append(.toolResult(ACPToolResult(
                            toolCallId: toolCallId,
                            content: resultContent,
                            isError: isError
                        )))
                    }
                }
                return results
            }
            return []
            
        case "stream_event":
            if let ev = parseStreamDelta(json) { return [ev] }
            return []
            
        case "result":
            let sessionId = json["session_id"] as? String ?? "unknown"
            let result = json["result"] as? String ?? ""
            let cost = json["total_cost_usd"] as? Double
            return [.complete(ACPTaskResult(
                sessionId: sessionId,
                result: result,
                totalCostUSD: cost,
                tokensUsed: nil,
                model: nil
            ))]
            
        case "text":
            let text = json["text"] as? String ?? ""
            return text.isEmpty ? [] : [.text(text)]
            
        default:
            return []
        }
    }
    
    private static func parseSystemEvent(_ json: [String: Any]) -> ACPStreamEvent? {
        let subtype = json["subtype"] as? String ?? ""
        
        switch subtype {
        case "init":
            let sessionId = json["session_id"] as? String ?? UUID().uuidString
            let model = json["model"] as? String
            let tools = json["tools"] as? [String] ?? []
            let capabilities = json["capabilities"] as? [String] ?? []
            return .sessionInit(ACPSessionInit(
                sessionId: sessionId,
                model: model,
                tools: tools,
                capabilities: capabilities
            ))
            
        case "api_retry":
            let attempt = json["attempt"] as? Int ?? 0
            let error = json["error"] as? String ?? "unknown"
            let delay = json["retry_delay_ms"] as? Int ?? 0
            return .systemInfo(ACPSystemInfo(
                message: "API retry attempt \(attempt) (\(error)), waiting \(delay)ms",
                subtype: "api_retry"
            ))
            
        default:
            return .systemInfo(ACPSystemInfo(
                message: json["message"] as? String ?? subtype,
                subtype: subtype
            ))
        }
    }
    
    private static func parseAssistantMessages(_ json: [String: Any]) -> [ACPStreamEvent] {
        let content: [[String: Any]]? = {
            if let c = json["content"] as? [[String: Any]] { return c }
            if let msg = json["message"] as? [String: Any], let c = msg["content"] as? [[String: Any]] { return c }
            return nil
        }()
        guard let content = content else { return [] }
        
        var events: [ACPStreamEvent] = []
        for block in content {
            let blockType = block["type"] as? String ?? ""
            
            switch blockType {
            case "text":
                let text = block["text"] as? String ?? ""
                if !text.isEmpty { events.append(.text(text)) }
                
            case "thinking":
                let thinking = block["thinking"] as? String ?? ""
                if !thinking.isEmpty { events.append(.thinking(thinking)) }
                
            case "tool_use":
                let toolId = block["id"] as? String ?? UUID().uuidString
                let toolName = block["name"] as? String ?? "unknown"
                let input = block["input"] as? [String: Any] ?? [:]
                events.append(.toolCall(ACPToolCall(
                    id: toolId,
                    name: toolName,
                    input: input
                )))
                
            default:
                continue
            }
        }
        return events
    }
    
    private static func parseStreamDelta(_ json: [String: Any]) -> ACPStreamEvent? {
        guard let event = json["event"] as? [String: Any],
              let delta = event["delta"] as? [String: Any] else { return nil }
        
        let deltaType = delta["type"] as? String ?? ""
        
        switch deltaType {
        case "text_delta":
            let text = delta["text"] as? String ?? ""
            return .text(text)
            
        case "thinking_delta":
            let thinking = delta["thinking"] as? String ?? ""
            return .thinking(thinking)
            
        case "input_json_delta":
            // Partial tool input — can be accumulated for display
            return nil
            
        default:
            return nil
        }
    }
    
    private static func extractTextContent(_ content: Any?) -> String {
        if let text = content as? String { return text }
        if let blocks = content as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }
}

// MARK: - AGY Stream Event Parser

/// Parses AGY `--output-format stream-json` NDJSON events
struct AGYStreamParser {
    
    static func parse(_ json: [String: Any]) -> ACPStreamEvent? {
        let eventName = json["event"] as? String ?? json["type"] as? String ?? ""
        
        switch eventName {
        case "init":
            let initData = json["init"] as? [String: Any] ?? [:]
            let sessionId = json["conversation_id"] as? String ?? UUID().uuidString
            let model = json["model"] as? String ?? "gemini-2.0-flash"
            return .sessionInit(ACPSessionInit(sessionId: sessionId, model: model, tools: [], capabilities: []))
            
        case "step_update":
            let step = json["step_update"] as? [String: Any] ?? [:]
            let stepType = step["step_type"] as? String ?? ""
            
            if stepType == "agent_response" {
                if let delta = step["text_delta"] as? String, !delta.isEmpty {
                    return .text(delta)
                }
                if let text = step["text"] as? String, !text.isEmpty {
                    return .text(text)
                }
                if let content = step["content"] as? String, !content.isEmpty {
                    return .text(content)
                }
            } else if stepType == "thought" || stepType == "thinking" || stepType == "reasoning" {
                let thinking = step["thinking_delta"] as? String
                    ?? step["thought_delta"] as? String
                    ?? step["thinking"] as? String
                    ?? step["thought"] as? String
                    ?? step["text_delta"] as? String
                    ?? step["text"] as? String
                    ?? ""
                if !thinking.isEmpty {
                    return .thinking(thinking)
                }
            } else if stepType == "tool_call" {
                let toolData = step["tool_call"] as? [String: Any] ?? [:]
                let id = toolData["id"] as? String ?? UUID().uuidString
                let name = toolData["name"] as? String ?? toolData["tool"] as? String ?? "tool"
                let input = toolData["input"] as? [String: Any] ?? toolData["arguments"] as? [String: Any] ?? [:]
                return .toolCall(ACPToolCall(id: id, name: name, input: input))
            } else if stepType == "tool_result" {
                let resData = step["tool_result"] as? [String: Any] ?? [:]
                let id = resData["tool_call_id"] as? String ?? resData["id"] as? String ?? ""
                let content = resData["content"] as? String ?? resData["output"] as? String ?? ""
                let isError = resData["is_error"] as? Bool ?? false
                return .toolResult(ACPToolResult(toolCallId: id, content: content, isError: isError))
            }
            
            // Check if step contains thinking delta even if step_type is generic
            if let thinking = step["thinking_delta"] as? String ?? step["thought_delta"] as? String, !thinking.isEmpty {
                return .thinking(thinking)
            }
            
            // Also check top-level text_delta in step_update
            if let delta = step["text_delta"] as? String, !delta.isEmpty {
                return .text(delta)
            }
            return nil
            
        case "result", "complete", "done":
            let res = json["result"] as? [String: Any] ?? [:]
            let sessionId = res["conversation_id"] as? String ?? json["conversation_id"] as? String ?? "unknown"
            let responseText = res["response"] as? String ?? res["output"] as? String ?? json["result"] as? String ?? ""
            let usage = res["usage"] as? [String: Any] ?? [:]
            let tokens = usage["total_tokens"] as? Int
            return .complete(ACPTaskResult(
                sessionId: sessionId,
                result: responseText,
                totalCostUSD: nil,
                tokensUsed: tokens,
                model: json["model"] as? String
            ))
            
        case "text", "content":
            let text = json["text"] as? String ?? json["content"] as? String ?? ""
            return .text(text)
            
        case "thinking", "thought", "reasoning":
            let thinking = json["text"] as? String
                ?? json["thinking"] as? String
                ?? json["thought"] as? String
                ?? json["delta"] as? String
                ?? json["content"] as? String
                ?? ""
            if !thinking.isEmpty {
                return .thinking(thinking)
            }
            return nil
            
        case "tool_call", "tool_use":
            let id = json["id"] as? String ?? UUID().uuidString
            let name = json["name"] as? String ?? json["tool"] as? String ?? "unknown"
            let input = json["input"] as? [String: Any] ?? json["arguments"] as? [String: Any] ?? [:]
            return .toolCall(ACPToolCall(id: id, name: name, input: input))
            
        case "tool_result":
            let id = json["tool_call_id"] as? String ?? json["id"] as? String ?? ""
            let content = json["content"] as? String ?? json["result"] as? String ?? ""
            let isError = json["is_error"] as? Bool ?? false
            return .toolResult(ACPToolResult(toolCallId: id, content: content, isError: isError))
            
        case "error":
            let res = json["result"] as? [String: Any]
            let msg = res?["error"] as? String ?? json["message"] as? String ?? json["error"] as? String ?? "Unknown error"
            return .error(msg)
            
        case "system", "info":
            let msg = json["message"] as? String ?? json["text"] as? String ?? ""
            return .systemInfo(ACPSystemInfo(message: msg, subtype: json["subtype"] as? String))
            
        default:
            if let text = json["text"] as? String, !text.isEmpty {
                return .text(text)
            }
            return nil
        }
    }
}

// MARK: - OpenCode Stream Event Parser

/// Parses `codex exec --json` JSONL. Codex uses thread/turn/item events,
/// which the Claude/AGY parsers cannot interpret.
struct CodexStreamParser {
    static func parse(_ json: [String: Any]) -> ACPStreamEvent? {
        let type = json["type"] as? String ?? ""
        let item = json["item"] as? [String: Any] ?? [:]
        let id = item["id"] as? String ?? UUID().uuidString
        let itemType = item["type"] as? String ?? ""

        switch type {
        case "thread.started":
            let threadID = json["thread_id"] as? String ?? UUID().uuidString
            return .sessionInit(ACPSessionInit(sessionId: threadID, model: nil, tools: [], capabilities: []))
        case "item.started":
            if itemType == "command_execution" {
                return .toolCall(ACPToolCall(id: id, name: "Bash", input: ["command": item["command"] as? String ?? ""]))
            }
            if itemType == "file_change" {
                return .toolCall(ACPToolCall(id: id, name: "Edit", input: ["path": item["path"] as? String ?? "workspace"]))
            }
            return nil
        case "item.completed":
            if itemType == "agent_message", let text = item["text"] as? String, !text.isEmpty {
                return .text(text)
            }
            if itemType == "command_execution" || itemType == "file_change" {
                let output = item["aggregated_output"] as? String
                    ?? item["output"] as? String
                    ?? item["status"] as? String
                    ?? "Completed"
                let failed = (item["exit_code"] as? Int).map { $0 != 0 } ?? (item["status"] as? String == "failed")
                return .toolResult(ACPToolResult(toolCallId: id, content: output, isError: failed, toolName: itemType == "command_execution" ? "Bash" : "Edit"))
            }
            return nil
        case "turn.failed", "error":
            let error = json["error"] as? [String: Any]
            return .error(error?["message"] as? String ?? json["message"] as? String ?? "Codex turn failed")
        case "turn.completed":
            let usage = json["usage"] as? [String: Any] ?? [:]
            let input = usage["input_tokens"] as? Int ?? 0
            let output = usage["output_tokens"] as? Int ?? 0
            return .complete(ACPTaskResult(sessionId: "completed", result: "", totalCostUSD: nil, tokensUsed: input + output, model: nil))
        default:
            return nil
        }
    }
}

struct CodexProcessArguments {
    static func build(task: String, model: String?, sessionID: String?,
                      permissionMode: ACPPermissionMode, extra: [String]) -> [String] {
        var args = ["exec"]
        if sessionID != nil { args.append("resume") }
        args.append("--json")
        args.append("--skip-git-repo-check")
        if permissionMode == .fullAuto {
            args.append("--dangerously-bypass-approvals-and-sandbox")
        } else if sessionID == nil {
            args += ["--sandbox", "workspace-write"]
        }
        if let model, !model.isEmpty { args += ["--model", model] }
        args += extra
        if let sessionID { args.append(sessionID) }
        args.append(task)
        return args
    }
}

/// Parses OpenCode `run --format json` NDJSON events
struct OpenCodeStreamParser {
    static func parse(_ json: [String: Any]) -> ACPStreamEvent? {
        let type = json["type"] as? String ?? json["event"] as? String ?? ""
        let part = json["part"] as? [String: Any] ?? [:]
        
        switch type {
        case "text", "message", "delta":
            let text = part["text"] as? String ?? json["text"] as? String ?? json["delta"] as? String ?? json["content"] as? String ?? ""
            if !text.isEmpty { return .text(text) }
            return nil
            
        case "thought", "thinking":
            let thought = part["text"] as? String ?? json["thought"] as? String ?? json["thinking"] as? String ?? ""
            if !thought.isEmpty { return .thinking(thought) }
            return nil
            
        case "tool_use", "call", "tool_call":
            let id = part["callID"] as? String ?? json["id"] as? String ?? UUID().uuidString
            let name = part["tool"] as? String ?? json["name"] as? String ?? json["tool"] as? String ?? "tool"
            let state = part["state"] as? [String: Any] ?? [:]
            let input = state["input"] as? [String: Any] ?? part["input"] as? [String: Any] ?? json["input"] as? [String: Any] ?? [:]
            
            // If output is already available in completed state, emit toolResult
            if let output = state["output"] as? String, !output.isEmpty {
                return .toolResult(ACPToolResult(toolCallId: id, content: output, isError: state["status"] as? String == "error"))
            }
            return .toolCall(ACPToolCall(id: id, name: name, input: input))
            
        case "step_finish":
            let reason = part["reason"] as? String ?? ""
            let sid = json["sessionID"] as? String ?? "opencode"
            let tokens = part["tokens"] as? [String: Any] ?? [:]
            let totalTokens = tokens["total"] as? Int ?? 0
            let cost = part["cost"] as? Double
            
            if reason == "stop" {
                return .complete(ACPTaskResult(sessionId: sid, result: "", totalCostUSD: cost, tokensUsed: totalTokens, model: nil))
            } else if reason == "unknown" && totalTokens == 0 {
                return .error("Model provider error or unauthenticated provider. Please verify credentials or switch to a free model.")
            }
            return nil
            
        case "complete", "finish", "done":
            let sid = json["sessionID"] as? String ?? json["session_id"] as? String ?? "unknown"
            let res = part["text"] as? String ?? json["result"] as? String ?? json["text"] as? String ?? ""
            return .complete(ACPTaskResult(sessionId: sid, result: res, totalCostUSD: nil, tokensUsed: nil, model: nil))
            
        case "error":
            if let errDict = json["error"] as? [String: Any] {
                let dataDict = errDict["data"] as? [String: Any]
                let msg = dataDict?["message"] as? String
                    ?? errDict["message"] as? String
                    ?? errDict["name"] as? String
                    ?? "OpenCode error"
                return .error(msg)
            }
            let err = json["error"] as? String ?? part["error"] as? String ?? json["message"] as? String ?? "OpenCode error"
            return .error(err)
            
        default:
            if let text = part["text"] as? String ?? json["text"] as? String, !text.isEmpty {
                return .text(text)
            }
            return nil
        }
    }
}
