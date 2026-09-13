//
//  ACPServerService.swift
//  MicroCode
//
//  ACP Server Service — Exposes MicroCode as an agent for external IDEs.
//  Other tools (Cursor, Zed, VS Code) can spawn MicroCode as a subprocess
//  and communicate via stdin/stdout NDJSON protocol.
//

import Foundation

// MARK: - ACP Server Service

/// Allows external IDEs to use MicroCode’s AI capabilities as an agent.
/// Launched via CLI flag: `MicroCode --acp-server --workspace /path`
@MainActor
class ACPServerService: ObservableObject {
    static let shared = ACPServerService()
    
    @Published var isServing = false
    @Published var clientName: String?
    @Published var requestCount = 0
    
    private var ndjsonParser = ACPNDJSONParser()
    
    // MARK: - Server Lifecycle
    
    /// Start serving as an ACP agent on stdin/stdout
    func startServing(workspacePath: String) {
        isServing = true
        
        // Emit server init message
        let initMsg: [String: Any] = [
            "type": "system",
            "subtype": "init",
            "server": "MicroCode",
            "version": "1.0.0",
            "workspace": workspacePath,
            "capabilities": [
                "code_generation",
                "code_editing",
                "file_operations",
                "terminal_execution",
                "git_operations",
                "multi_model_ai"
            ],
            "supported_models": [
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gpt-4o",
                "claude-sonnet-4",
                "deepseek-r1"
            ]
        ]
        writeNDJSON(initMsg)
        
        // Start reading stdin for incoming requests
        readStdinLoop(workspacePath: workspacePath)
    }
    
    /// Stop the ACP server
    func stopServing() {
        isServing = false
        let doneMsg: [String: Any] = [
            "type": "system",
            "subtype": "shutdown",
            "message": "MicroCode ACP server shutting down"
        ]
        writeNDJSON(doneMsg)
    }
    
    // MARK: - Stdin Processing
    
    private func readStdinLoop(workspacePath: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let stdin = FileHandle.standardInput
            
            while self?.isServing == true {
                let data = stdin.availableData
                guard !data.isEmpty else {
                    // stdin closed — client disconnected
                    DispatchQueue.main.async {
                        self?.isServing = false
                    }
                    break
                }
                
                guard let self = self else { break }
                let messages = self.ndjsonParser.feed(data)
                
                for message in messages {
                    DispatchQueue.main.async {
                        self.handleRequest(message, workspacePath: workspacePath)
                    }
                }
            }
        }
    }
    
    // MARK: - Request Handling
    
    private func handleRequest(_ json: [String: Any], workspacePath: String) {
        requestCount += 1
        
        let type = json["type"] as? String ?? ""
        let requestId = json["id"] as? String ?? UUID().uuidString
        
        switch type {
        case "task", "user_message":
            let content = json["content"] as? String ?? json["message"] as? String ?? ""
            handleTask(requestId: requestId, content: content, workspacePath: workspacePath)
            
        case "cancel":
            handleCancel(requestId: requestId)
            
        case "ping":
            writeNDJSON(["type": "pong", "id": requestId])
            
        case "capabilities":
            let caps: [String: Any] = [
                "type": "capabilities_response",
                "id": requestId,
                "tools": ["read_file", "write_file", "edit_file", "run_terminal", "search_files", "git_status"]
            ]
            writeNDJSON(caps)
            
        default:
            writeNDJSON([
                "type": "error",
                "id": requestId,
                "message": "Unknown request type: \(type)"
            ])
        }
    }
    
    private func handleTask(requestId: String, content: String, workspacePath: String) {
        // Acknowledge task receipt
        writeNDJSON([
            "type": "task_started",
            "id": requestId,
            "message": "Processing task"
        ])
        
        // Route to AgentService for processing
        // This connects to MicroCode’s internal AI pipeline
        Task {
            // Stream progress events
            writeNDJSON([
                "type": "text",
                "id": requestId,
                "content": "[MicroCode] Received task: \(content)"
            ])
            
            // TODO: Connect to AgentService.sendMessage() for full AI processing
            // For now, acknowledge the task
            writeNDJSON([
                "type": "result",
                "id": requestId,
                "session_id": UUID().uuidString,
                "result": "Task received by MicroCode. Full AI routing coming soon."
            ])
        }
    }
    
    private func handleCancel(requestId: String) {
        writeNDJSON([
            "type": "cancelled",
            "id": requestId,
            "message": "Task cancelled"
        ])
    }
    
    // MARK: - NDJSON Output
    
    private func writeNDJSON(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              var outputData = String(data: data, encoding: .utf8)?.data(using: .utf8)
        else { return }
        
        outputData.append("\n".data(using: .utf8)!)
        FileHandle.standardOutput.write(outputData)
    }
}
