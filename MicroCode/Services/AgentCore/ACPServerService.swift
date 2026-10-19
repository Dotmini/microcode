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
    private var sessionHistory: [String: [(role: String, content: String)]] = [:]
    private var activePromptTasks: [String: Task<Void, Never>] = [:]
    private var cancelledSessions: Set<String> = []
    
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
            guard let id = reqId else { return }
            writeNDJSON([
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "protocolVersion": 1,
                    "agentInfo": [
                        "name": "microcode",
                        "title": "MicroCode Native AI Agent",
                        "version": "2.3.1"
                    ],
                    "agentCapabilities": [
                        "loadSession": true,
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
            sessionHistory[sid] = []
            writeNDJSON([
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "sessionId": sid
                ]
            ])
            
        case "session/load":
            guard let id = reqId else { return }
            let sid = params["sessionId"] as? String ?? ("sess_" + UUID().uuidString.prefix(8))
            let cwd = params["cwd"] as? String ?? defaultWorkspace
            sessions[sid] = cwd
            if sessionHistory[sid] == nil { sessionHistory[sid] = [] }
            writeNDJSON(["jsonrpc": "2.0", "id": id, "result": [:] as [String: Any]])
            
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
        let sysPrompt = "You are MicroCode Sovereign AI Agent operating in workspace \(workspacePath). Provide accurate, concise code and engineering solutions."
        
        let task = Task { @MainActor in
            var fullResponse = ""
            do {
                var messages = [(role: "system", content: sysPrompt)]
                messages.append(contentsOf: history)
                messages.append((role: "user", content: promptText))
                
                let stream = try await AIClient.shared.streamCompletion(messages: messages)
                for try await chunk in stream {
                    if Task.isCancelled || self.cancelledSessions.contains(sessionId) {
                        break
                    }
                    fullResponse += chunk
                    self.writeNDJSON([
                        "jsonrpc": "2.0",
                        "method": "session/update",
                        "params": [
                            "sessionId": sessionId,
                            "update": [
                                "sessionUpdate": "agent_message_chunk",
                                "content": [
                                    "type": "text",
                                    "text": chunk
                                ]
                            ]
                        ]
                    ])
                }
                
                let wasCancelled = Task.isCancelled || self.cancelledSessions.contains(sessionId)
                if !wasCancelled {
                    history.append((role: "user", content: promptText))
                    history.append((role: "assistant", content: fullResponse))
                    self.sessionHistory[sessionId] = history
                }
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
        FileHandle.standardOutput.write(outputData)
    }
}
