//
//  JupyterClient.swift
//  MicroCode
//
//  Handles communication with Jupyter Notebook Servers via REST API and WebSockets.
//

import Foundation

enum JupyterError: Error {
    case invalidURL
    case connectionFailed(String)
    case kernelCreationFailed(String)
    case invalidResponse
    case executionTimeout
}

struct JupyterKernelInfo: Codable {
    let id: String
    let name: String
}

class JupyterClient {
    private let baseURL: String
    private let token: String
    private let sessionID = UUID().uuidString
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    private var activeKernelID: String?
    
    // Callback handlers
    private var onOutput: ((String) -> Void)?
    private var onComplete: ((String) -> Void)?
    private var onError: ((Error) -> Void)?
    
    private var currentExecutionMsgID: String?
    
    init(endpoint: String, token: String) {
        // Ensure endpoint does not end with a slash
        var url = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix("/") {
            url.removeLast()
        }
        self.baseURL = url
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - REST API
    
    private func makeRequest(path: String, method: String, body: [String: Any]? = nil) -> URLRequest? {
        guard let url = URL(string: "\(baseURL)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if !token.isEmpty {
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }
    
    func startKernel(name: String = "python3") async throws -> String {
        guard let request = makeRequest(path: "/api/kernels", method: "POST", body: ["name": name]) else {
            throw JupyterError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JupyterError.invalidResponse
        }
        
        if (200...299).contains(httpResponse.statusCode) {
            let decoder = JSONDecoder()
            let kernelInfo = try decoder.decode(JupyterKernelInfo.self, from: data)
            self.activeKernelID = kernelInfo.id
            return kernelInfo.id
        } else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown HTTP Error \(httpResponse.statusCode)"
            throw JupyterError.kernelCreationFailed(errorMsg)
        }
    }
    
    func stopKernel() async {
        guard let kernelID = activeKernelID, let request = makeRequest(path: "/api/kernels/\(kernelID)", method: "DELETE") else { return }
        _ = try? await URLSession.shared.data(for: request)
        self.activeKernelID = nil
        disconnectWebSocket()
    }
    
    // MARK: - WebSocket Protocol
    
    func connectWebSocket(kernelID: String) throws {
        // Convert http:// to ws:// and https:// to wss://
        var wsBaseURL = baseURL
        if wsBaseURL.hasPrefix("http://") {
            wsBaseURL = wsBaseURL.replacingOccurrences(of: "http://", with: "ws://")
        } else if wsBaseURL.hasPrefix("https://") {
            wsBaseURL = wsBaseURL.replacingOccurrences(of: "https://", with: "wss://")
        }
        
        var urlString = "\(wsBaseURL)/api/kernels/\(kernelID)/channels"
        if !token.isEmpty {
            urlString += "?token=\(token)"
        }
        
        guard let url = URL(string: urlString) else {
            throw JupyterError.invalidURL
        }
        
        var request = URLRequest(url: url)
        if !token.isEmpty {
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        }
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        isConnected = true
        
        listenForMessages()
    }
    
    func disconnectWebSocket() {
        isConnected = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }
    
    func executeCode(code: String, onOutput: @escaping (String) -> Void, onComplete: @escaping (String) -> Void, onError: @escaping (Error) -> Void) async throws {
        guard let task = webSocketTask, isConnected else {
            throw JupyterError.connectionFailed("WebSocket is not connected.")
        }
        
        self.onOutput = onOutput
        self.onComplete = onComplete
        self.onError = onError
        
        let msgID = UUID().uuidString
        self.currentExecutionMsgID = msgID
        
        let payload: [String: Any] = [
            "header": [
                "msg_id": msgID,
                "username": "microcode",
                "session": sessionID,
                "msg_type": "execute_request",
                "version": "5.3"
            ],
            "parent_header": [:],
            "metadata": [:],
            "content": [
                "code": code,
                "silent": false,
                "store_history": false,
                "user_expressions": [:],
                "allow_stdin": false
            ],
            "channel": "shell"
        ]
        
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw JupyterError.invalidResponse
        }
        
        try await task.send(.string(jsonString))
    }
    
    private func listenForMessages() {
        guard let task = webSocketTask, isConnected else { return }
        
        task.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleJupyterMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleJupyterMessage(text)
                    }
                @unknown default:
                    break
                }
                
                if self.isConnected {
                    self.listenForMessages()
                }
                
            case .failure(let error):
                if (error as NSError).code == -999 { return } // Normal closure
                self.onError?(error)
                self.disconnectWebSocket()
            }
        }
    }
    
    private func handleJupyterMessage(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msgType = (json["msg_type"] as? String) ?? (json["header"] as? [String: Any])?["msg_type"] as? String else {
            return
        }
        
        let content = json["content"] as? [String: Any] ?? [:]
        
        // We only care about messages related to our current execution request
        let parentHeader = json["parent_header"] as? [String: Any]
        let parentMsgID = parentHeader?["msg_id"] as? String
        
        // Ignore status messages that aren't related to our execution unless we are waiting for idle
        if msgType == "status" {
            if let executionState = content["execution_state"] as? String, executionState == "idle", parentMsgID == currentExecutionMsgID {
                self.onComplete?("Execution complete.")
                self.currentExecutionMsgID = nil
            }
            return
        }
        
        guard parentMsgID == currentExecutionMsgID else { return }
        
        switch msgType {
        case "stream":
            if let text = content["text"] as? String {
                onOutput?(text)
            }
        case "execute_result", "display_data":
            if let dataContent = content["data"] as? [String: Any] {
                if let text = dataContent["text/plain"] as? String {
                    onOutput?(text + "\n")
                }
                // Handle image data if present
                if let base64Image = dataContent["image/png"] as? String {
                    onOutput?("[Image Output Received: \(base64Image.count) bytes]\n")
                }
            }
        case "error":
            if let ename = content["ename"] as? String,
               let evalue = content["evalue"] as? String {
                onOutput?("❌ \(ename): \(evalue)\n")
                if let traceback = content["traceback"] as? [String] {
                    // Clean up ANSI escape sequences in traceback if needed, but often terminal handles it
                    onOutput?(traceback.joined(separator: "\n") + "\n")
                }
            }
        case "execute_reply":
            if let status = content["status"] as? String, status == "error" {
                // Usually handled by 'error' message on iopub, but just in case
            }
        default:
            break
        }
    }
}
