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
    case claudeCode   // Anthropic Claude Code CLI
    case agy          // Google Antigravity CLI
    case openCode     // OpenCode CLI & ACP Server
    case aider        // Aider CLI
    case codexEngine  // OpenAI Codex / inference engines
    case zedEngine    // Zed / ZCode Assistant
    case custom       // Custom agent binary
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .agy: return "Antigravity (AGY)"
        case .openCode: return "OpenCode"
        case .aider: return "Aider"
        case .codexEngine: return "OpenAI Codex"
        case .zedEngine: return "Zed / ZCode"
        case .custom: return "Custom Agent"
        }
    }
    
    var iconName: String {
        switch self {
        case .claudeCode: return "brain.head.profile"
        case .agy: return "sparkles"
        case .openCode: return "laptopcomputer"
        case .aider: return "terminal"
        case .codexEngine: return "cpu"
        case .zedEngine: return "chevron.left.forwardslash.chevron.right"
        case .custom: return "plus.circle"
        }
    }
    
    var defaultCommand: String {
        switch self {
        case .claudeCode: return "claude"
        case .agy: return "agy"
        case .openCode: return "opencode"
        case .aider: return "aider"
        case .codexEngine: return "codex"
        case .zedEngine: return "zed"
        case .custom: return ""
        }
    }
    
    var brandColor: String {
        switch self {
        case .claudeCode: return "#D97757"
        case .agy: return "#4285F4"
        case .openCode: return "#E05A47"
        case .aider: return "#00D084"
        case .codexEngine: return "#10A37F"
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
        case .reviewEach: return "plan"
        case .autoApproveReads: return "auto"
        case .fullAuto: return "auto"
        }
    }
    
    var claudeAllowedTools: [String] {
        switch self {
        case .reviewEach: return ["Read"]
        case .autoApproveReads: return ["Read"]
        case .fullAuto: return ["Read", "Edit", "Bash", "Write"]
        }
    }
}

// MARK: - NDJSON Parser

/// High-performance NDJSON line parser for agent stdio streams
struct ACPNDJSONParser {
    private var buffer = ""
    
    /// Feed raw data from stdout pipe and return complete JSON lines
    mutating func feed(_ data: Data) -> [[String: Any]] {
        guard let string = String(data: data, encoding: .utf8) else { return [] }
        buffer += string
        
        let components = buffer.components(separatedBy: "\n")
        buffer = components.last ?? ""
        
        var results: [[String: Any]] = []
        for line in components.dropLast() {
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
    
    /// Reset the buffer
    mutating func reset() {
        buffer = ""
    }
}

// MARK: - Claude Code Stream Event Parser

/// Parses Claude Code `--output-format stream-json` NDJSON events into ACPStreamEvents
struct ClaudeCodeStreamParser {
    
    static func parse(_ json: [String: Any]) -> ACPStreamEvent? {
        let type = json["type"] as? String ?? ""
        
        switch type {
        case "system":
            return parseSystemEvent(json)
            
        case "assistant":
            return parseAssistantMessage(json)
            
        case "user":
            // Tool results from Claude's own tool execution
            if let content = json["content"] as? [[String: Any]] {
                for block in content {
                    if block["type"] as? String == "tool_result" {
                        let toolCallId = block["tool_use_id"] as? String ?? UUID().uuidString
                        let resultContent = extractTextContent(block["content"])
                        let isError = block["is_error"] as? Bool ?? false
                        return .toolResult(ACPToolResult(
                            toolCallId: toolCallId,
                            content: resultContent,
                            isError: isError
                        ))
                    }
                }
            }
            return nil
            
        case "stream_event":
            return parseStreamDelta(json)
            
        case "result":
            let sessionId = json["session_id"] as? String ?? "unknown"
            let result = json["result"] as? String ?? ""
            let cost = json["total_cost_usd"] as? Double
            return .complete(ACPTaskResult(
                sessionId: sessionId,
                result: result,
                totalCostUSD: cost,
                tokensUsed: nil,
                model: nil
            ))
            
        case "text":
            let text = json["text"] as? String ?? ""
            return text.isEmpty ? nil : .text(text)
            
        default:
            return nil
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
    
    private static func parseAssistantMessage(_ json: [String: Any]) -> ACPStreamEvent? {
        let content: [[String: Any]]? = {
            if let c = json["content"] as? [[String: Any]] { return c }
            if let msg = json["message"] as? [String: Any], let c = msg["content"] as? [[String: Any]] { return c }
            return nil
        }()
        guard let content = content else { return nil }
        
        for block in content {
            let blockType = block["type"] as? String ?? ""
            
            switch blockType {
            case "text":
                let text = block["text"] as? String ?? ""
                if !text.isEmpty { return .text(text) }
                
            case "thinking":
                let thinking = block["thinking"] as? String ?? ""
                if !thinking.isEmpty { return .thinking(thinking) }
                
            case "tool_use":
                let toolId = block["id"] as? String ?? UUID().uuidString
                let toolName = block["name"] as? String ?? "unknown"
                let input = block["input"] as? [String: Any] ?? [:]
                return .toolCall(ACPToolCall(
                    id: toolId,
                    name: toolName,
                    input: input
                ))
                
            default:
                continue
            }
        }
        return nil
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
            let model = json["model"] as? String ?? "gemini-3.8-flash-high"
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
