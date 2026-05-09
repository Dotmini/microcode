//
//  AIClient.swift
//  CodeTunner
//
//  Production AI API Client with Streaming + Function Calling
//  Supports: Gemini, OpenAI, Anthropic, DeepSeek
//

import Foundation
import Combine

// MARK: - AI Provider

enum StreamableAIProvider: String, CaseIterable {
    case gemini = "gemini"
    case openai = "openai"
    case anthropic = "anthropic"
    case deepseek = "deepseek"
    case grok = "grok"
    case qwen = "qwen"
    case glm = "glm"
    case local = "local"
    
    /// Dotmini Cloud proxy URL (license key route — hides real API keys)
    static var cloudProxyURL: String {
        UserDefaults.standard.string(forKey: "dotminiProxyURL")
            ?? "https://api.dotmini.net/v1"
    }
    
    /// Base URL when routing through Dotmini Cloud proxy
    var cloudBaseURL: String {
        switch self {
        case .local: return LocalLLMService.cachedEndpoint
        default: return Self.cloudProxyURL
        }
    }
    
    /// Base URL when user provides their own API key (direct to provider)
    var directBaseURL: String {
        switch self {
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .grok: return "https://api.x.ai/v1"
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .glm: return "https://open.bigmodel.cn/api/paas/v4"
        case .local: return LocalLLMService.cachedEndpoint
        }
    }
    
    var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.5-flash"
        case .openai: return "gpt-4o"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .deepseek: return "deepseek-chat"
        case .grok: return "grok-3"
        case .qwen: return "qwen-max"
        case .glm: return "glm-4-plus"
        case .local: return LocalLLMService.cachedModel
        }
    }
    
    /// Whether this provider uses OpenAI-compatible chat/completions API format
    var usesOpenAIFormat: Bool {
        switch self {
        case .openai, .deepseek, .grok, .qwen, .glm, .local: return true
        case .gemini, .anthropic: return false
        }
    }
    
    /// Whether this provider requires an API key
    var requiresAPIKey: Bool {
        switch self {
        case .local: return false
        default: return true
        }
    }
    
    static func detect(from model: String) -> StreamableAIProvider {
        if model.contains("gemini") || model.contains("gemma") { return .gemini }
        if model.contains("gpt") || model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4") { return .openai }
        if model.contains("claude") { return .anthropic }
        if model.contains("deepseek") { return .deepseek }
        if model.contains("grok") { return .grok }
        if model.contains("qwen") { return .qwen }
        if model.contains("glm") { return .glm }
        return .gemini
    }
}

// MARK: - Attachments

struct AIAttachment {
    let name: String
    let data: Data
    let type: AttachmentType
    
    enum AttachmentType {
        case image(format: String)
        case text
        case pdf
    }
    
    var base64String: String { data.base64EncodedString() }
    var textContent: String? { String(data: data, encoding: .utf8) }
}

// MARK: - Tool Call Model

struct AIToolCall: Identifiable {
    let id: String
    let name: String
    let arguments: [String: Any]
}

// MARK: - Stream Response

enum AIStreamEvent {
    case text(String)
    case toolCall(AIToolCall)
    case done
    case error(String)
}

// MARK: - AI Client

@MainActor
class AIClient: ObservableObject {
    static let shared = AIClient()
    
    @Published var isStreaming = false
    @Published var currentStreamedText = ""
    
    private var streamTask: Task<Void, Never>?
    private let maxHistoryMessages = 20
    private let requestTimeout: TimeInterval = 120
    
    // MARK: - Send Message (Streaming, Text-only response)
    
    func sendMessage(
        prompt: String,
        attachments: [AIAttachment] = [],
        systemPrompt: String? = nil,
        conversationHistory: [(role: String, content: String)] = [],
        provider: StreamableAIProvider,
        model: String,
        apiKey: String,
        tools: [[String: Any]]? = nil,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)? = nil,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        // Determine key mode: "cloud" (Dotmini proxy) vs "direct" (user's own key)
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "cloud"
        let actualKey: String
        let baseURL: String
        
        if provider == .local {
            actualKey = ""
            baseURL = provider.directBaseURL
        } else if keyMode == "direct" {
            // User's own API key → hit provider directly
            actualKey = UserDefaults.standard.string(forKey: "\(provider.rawValue)_api_key") ?? apiKey
            baseURL = provider.directBaseURL
        } else {
            // Dotmini Cloud → Secure Internal Developer Keys (Obfuscated)
            actualKey = CloudKeyManager.getKey(for: provider)
            baseURL = provider.directBaseURL
        }
        
        guard !actualKey.isEmpty || !provider.requiresAPIKey else {
            if keyMode == "direct" {
                onError("API key missing for \(provider.rawValue). Add your key in Settings → AI.")
            } else {
                onError("Cloud Dotmini API Key is not configured for \(provider.rawValue). Please use Bring Your Own Key.")
            }
            return
        }
        
        isStreaming = true
        currentStreamedText = ""
        
        let trimmedHistory = Array(conversationHistory.suffix(maxHistoryMessages))
        
        streamTask = Task {
            var retryCount = 0
            let maxRetries = 2
            
            while retryCount <= maxRetries {
                do {
                    // Use native protocols for both direct and cloud modes since proxy is bypassed for security
                    switch provider {
                    case .gemini:
                        try await streamGemini(prompt: prompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: model, apiKey: actualKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                    case .anthropic:
                        try await streamAnthropic(prompt: prompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: model, apiKey: actualKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                    case .openai, .deepseek, .grok, .qwen, .glm, .local:
                        try await streamOpenAI(prompt: prompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: model, apiKey: actualKey, baseURL: baseURL, tools: tools, onToken: onToken, onToolCall: onToolCall)
                    }
                    
                    await MainActor.run {
                        onComplete(self.currentStreamedText)
                        self.isStreaming = false
                    }
                    return // Success
                    
                } catch let error as NSError {
                    // Retry on transient errors (429, 503)
                    if (error.code == 429 || error.code == 503) && retryCount < maxRetries {
                        retryCount += 1
                        let delay = UInt64(pow(2.0, Double(retryCount))) * 1_000_000_000
                        try? await Task.sleep(nanoseconds: delay)
                        continue
                    }
                    
                    await MainActor.run {
                        onError(self.parseErrorMessage(error))
                        self.isStreaming = false
                    }
                    return
                }
            }
        }
    }
    
    func cancelStream() {
        streamTask?.cancel()
        isStreaming = false
    }
    
    // MARK: - Non-Streaming (for Agent tool loops)
    
    func sendSync(
        messages: [[(String, Any)]],
        systemPrompt: String?,
        provider: StreamableAIProvider,
        model: String,
        apiKey: String,
        tools: [[String: Any]]? = nil
    ) async throws -> (text: String, toolCalls: [AIToolCall]) {
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "cloud"
        let actualKey: String
        let baseURL: String
        
        if provider == .local {
            actualKey = ""
            baseURL = provider.directBaseURL
        } else if keyMode == "direct" {
            actualKey = UserDefaults.standard.string(forKey: "\(provider.rawValue)_api_key") ?? apiKey
            baseURL = provider.directBaseURL
        } else {
            actualKey = CloudKeyManager.getKey(for: provider)
            baseURL = provider.directBaseURL
        }
        
        switch provider {
        case .gemini:
            return try await syncGemini(messages: messages, systemPrompt: systemPrompt, model: model, apiKey: actualKey, tools: tools)
        case .anthropic:
            return try await syncAnthropic(messages: messages, systemPrompt: systemPrompt, model: model, apiKey: actualKey, tools: tools)
        case .openai, .deepseek, .grok, .qwen, .glm, .local:
            return try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: model, apiKey: actualKey, baseURL: baseURL, tools: tools)
        }
    }
    
    // MARK: - Error Parsing
    
    private func parseErrorMessage(_ error: NSError) -> String {
        switch error.code {
        case 429: return "Rate limited — please wait a moment and try again."
        case 401, 403: return "Invalid or expired API key. Check Settings."
        case 503, 500: return "AI service temporarily unavailable. Try again."
        default: return error.localizedDescription
        }
    }
    
    // MARK: - Gemini Streaming
    
    private func streamGemini(prompt: String, attachments: [AIAttachment], systemPrompt: String?, conversationHistory: [(role: String, content: String)], model: String, apiKey: String, tools: [[String: Any]]?, onToken: @escaping (String) -> Void, onToolCall: ((AIToolCall) -> Void)?) async throws {
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "cloud"
        let baseURL = keyMode == "direct" ? StreamableAIProvider.gemini.directBaseURL : StreamableAIProvider.gemini.cloudBaseURL
        let url = URL(string: "\(baseURL)/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)")!
        
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var contents: [[String: Any]] = []
        
        if let sys = systemPrompt {
            contents.append(["role": "user", "parts": [["text": sys]]])
            contents.append(["role": "model", "parts": [["text": "Understood. I'll follow these instructions."]]])
        }
        
        for msg in conversationHistory {
            let geminiRole = msg.role == "assistant" ? "model" : "user"
            contents.append(["role": geminiRole, "parts": [["text": msg.content]]])
        }
        
        var userParts: [[String: Any]] = [["text": prompt]]
        
        for attachment in attachments {
            switch attachment.type {
            case .image(let format):
                userParts.append(["inlineData": ["mimeType": "image/\(format)", "data": attachment.base64String]])
            case .text:
                if let text = attachment.textContent {
                    userParts.append(["text": "\n[File: \(attachment.name)]\n\(text)\n[/File]\n"])
                }
            case .pdf:
                userParts.append(["inlineData": ["mimeType": "application/pdf", "data": attachment.base64String]])
            }
        }
        
        contents.append(["role": "user", "parts": userParts])
        
        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": ["temperature": 0.7, "maxOutputTokens": 16384]
        ]
        
        // Add tools for function calling
        if let tools = tools, !tools.isEmpty {
            body["tools"] = [["functionDeclarations": tools]]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "AIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Gemini API error (\(httpResponse.statusCode))"])
        }
        
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { continue }
            
            for part in parts {
                if let text = part["text"] as? String {
                    await MainActor.run {
                        self.currentStreamedText += text
                        onToken(text)
                    }
                } else if let fc = part["functionCall"] as? [String: Any],
                          let name = fc["name"] as? String {
                    let args = fc["args"] as? [String: Any] ?? [:]
                    let toolCall = AIToolCall(id: UUID().uuidString, name: name, arguments: args)
                    await MainActor.run { onToolCall?(toolCall) }
                }
            }
        }
    }
    
    // MARK: - OpenAI/DeepSeek Streaming
    
    private func streamOpenAI(prompt: String, attachments: [AIAttachment], systemPrompt: String?, conversationHistory: [(role: String, content: String)], model: String, apiKey: String, baseURL: String, tools: [[String: Any]]?, onToken: @escaping (String) -> Void, onToolCall: ((AIToolCall) -> Void)?) async throws {
        let url = URL(string: "\(baseURL)/chat/completions")!
        
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        var messages: [[String: Any]] = []
        if let sys = systemPrompt { messages.append(["role": "system", "content": sys]) }
        for msg in conversationHistory { messages.append(["role": msg.role, "content": msg.content]) }
        
        var contentArray: [[String: Any]] = [["type": "text", "text": prompt]]
        for attachment in attachments {
            switch attachment.type {
            case .image(let format):
                contentArray.append(["type": "image_url", "image_url": ["url": "data:image/\(format);base64,\(attachment.base64String)"]])
            case .text:
                if let text = attachment.textContent { contentArray.append(["type": "text", "text": "\n[File: \(attachment.name)]\n\(text)\n"]) }
            case .pdf:
                contentArray.append(["type": "text", "text": "\n[System: PDF '\(attachment.name)' — extract text to use.]\n"])
            }
        }
        messages.append(["role": "user", "content": contentArray])
        
        var body: [String: Any] = ["model": model, "messages": messages, "stream": true, "temperature": 0.7, "max_tokens": 16384]
        
        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools.map { ["type": "function", "function": $0] as [String: Any] }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "AIClient", code: code, userInfo: [NSLocalizedDescriptionKey: "OpenAI API error (\(code))"])
        }
        
        // Buffer for streaming tool calls
        var toolCallBuffers: [String: (name: String, args: String)] = [:]
        
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: "), line != "data: [DONE]" else { continue }
            let jsonString = String(line.dropFirst(6))
            
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else { continue }
            
            // Text content
            if let content = delta["content"] as? String {
                await MainActor.run {
                    self.currentStreamedText += content
                    onToken(content)
                }
            }
            
            // Tool calls (streamed incrementally)
            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                for tc in toolCalls {
                    let idx = "\(tc["index"] as? Int ?? 0)"
                    if let function = tc["function"] as? [String: Any] {
                        if let name = function["name"] as? String {
                            toolCallBuffers[idx] = (name: name, args: "")
                        }
                        if let argChunk = function["arguments"] as? String {
                            toolCallBuffers[idx]?.args.append(argChunk)
                        }
                    }
                }
            }
            
            // Check finish reason
            if let finishReason = choices.first?["finish_reason"] as? String, finishReason == "tool_calls" {
                for (_, buffer) in toolCallBuffers {
                    let args = (try? JSONSerialization.jsonObject(with: Data(buffer.args.utf8))) as? [String: Any] ?? [:]
                    let toolCall = AIToolCall(id: UUID().uuidString, name: buffer.name, arguments: args)
                    await MainActor.run { onToolCall?(toolCall) }
                }
            }
        }
    }
    
    // MARK: - Anthropic Streaming
    
    private func streamAnthropic(prompt: String, attachments: [AIAttachment], systemPrompt: String?, conversationHistory: [(role: String, content: String)], model: String, apiKey: String, tools: [[String: Any]]?, onToken: @escaping (String) -> Void, onToolCall: ((AIToolCall) -> Void)?) async throws {
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "cloud"
        let baseURL = keyMode == "direct" ? StreamableAIProvider.anthropic.directBaseURL : StreamableAIProvider.anthropic.cloudBaseURL
        let url = URL(string: "\(baseURL)/messages")!
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") // Required for Dotmini Proxy Auth
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        var allMessages: [[String: Any]] = []
        for msg in conversationHistory { allMessages.append(["role": msg.role, "content": msg.content]) }
        
        var messageContent: [[String: Any]] = []
        for attachment in attachments {
            if case .image(let format) = attachment.type {
                messageContent.append(["type": "image", "source": ["type": "base64", "media_type": "image/\(format)", "data": attachment.base64String]])
            } else if case .text = attachment.type, let text = attachment.textContent {
                messageContent.append(["type": "text", "text": "File: \(attachment.name)\n\(text)"])
            }
        }
        messageContent.append(["type": "text", "text": prompt])
        allMessages.append(["role": "user", "content": messageContent])
        
        var body: [String: Any] = ["model": model, "max_tokens": 16384, "stream": true, "messages": allMessages]
        if let sys = systemPrompt { body["system"] = sys }
        
        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools.map { tool -> [String: Any] in
                ["name": tool["name"] ?? "", "description": tool["description"] ?? "", "input_schema": tool["parameters"] ?? [:]]
            }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "AIClient", code: code, userInfo: [NSLocalizedDescriptionKey: "Anthropic API error (\(code))"])
        }
        
        var currentToolName = ""
        var currentToolArgs = ""
        var currentToolId = ""
        
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            
            let eventType = json["type"] as? String ?? ""
            
            switch eventType {
            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any] {
                    if let text = delta["text"] as? String {
                        await MainActor.run {
                            self.currentStreamedText += text
                            onToken(text)
                        }
                    }
                    if let partial = delta["partial_json"] as? String {
                        currentToolArgs += partial
                    }
                }
            case "content_block_start":
                if let block = json["content_block"] as? [String: Any], block["type"] as? String == "tool_use" {
                    currentToolName = block["name"] as? String ?? ""
                    currentToolId = block["id"] as? String ?? UUID().uuidString
                    currentToolArgs = ""
                }
            case "content_block_stop":
                if !currentToolName.isEmpty {
                    let args = (try? JSONSerialization.jsonObject(with: Data(currentToolArgs.utf8))) as? [String: Any] ?? [:]
                    let toolCall = AIToolCall(id: currentToolId, name: currentToolName, arguments: args)
                    await MainActor.run { onToolCall?(toolCall) }
                    currentToolName = ""
                    currentToolArgs = ""
                }
            default:
                break
            }
        }
    }
    
    // MARK: - Sync Helpers (Non-streaming for Agent loops)
    
    private func syncGemini(messages: [[(String, Any)]], systemPrompt: String?, model: String, apiKey: String, tools: [[String: Any]]?) async throws -> (text: String, toolCalls: [AIToolCall]) {
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "cloud"
        let baseURL = keyMode == "direct" ? StreamableAIProvider.gemini.directBaseURL : StreamableAIProvider.gemini.cloudBaseURL
        let url = URL(string: "\(baseURL)/models/\(model):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var contents: [[String: Any]] = []
        if let sys = systemPrompt {
            contents.append(["role": "user", "parts": [["text": sys]]])
            contents.append(["role": "model", "parts": [["text": "Understood."]]])
        }
        
        for msg in messages {
            var parts: [[String: Any]] = []
            for (key, val) in msg {
                if key == "text" { parts.append(["text": val]) }
                else if key == "functionResponse", let fr = val as? [String: Any] { parts.append(["functionResponse": fr]) }
            }
            let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
            contents.append(["role": role == "assistant" ? "model" : role, "parts": parts])
        }
        
        var body: [String: Any] = ["contents": contents, "generationConfig": ["temperature": 0.7, "maxOutputTokens": 16384]]
        if let tools = tools, !tools.isEmpty { body["tools"] = [["functionDeclarations": tools]] }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return (text: "Error: Unable to parse Gemini response", toolCalls: [])
        }
        
        var text = ""
        var toolCalls: [AIToolCall] = []
        for part in parts {
            if let t = part["text"] as? String { text += t }
            if let fc = part["functionCall"] as? [String: Any], let name = fc["name"] as? String {
                toolCalls.append(AIToolCall(id: UUID().uuidString, name: name, arguments: fc["args"] as? [String: Any] ?? [:]))
            }
        }
        return (text: text, toolCalls: toolCalls)
    }
    
    private func syncOpenAI(messages: [[(String, Any)]], systemPrompt: String?, model: String, apiKey: String, baseURL: String, tools: [[String: Any]]?) async throws -> (text: String, toolCalls: [AIToolCall]) {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        var apiMessages: [[String: Any]] = []
        if let sys = systemPrompt { apiMessages.append(["role": "system", "content": sys]) }
        for msg in messages {
            let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
            let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
            apiMessages.append(["role": role, "content": content])
        }
        
        var body: [String: Any] = ["model": model, "messages": apiMessages, "temperature": 0.7, "max_tokens": 16384]
        if let tools = tools, !tools.isEmpty { body["tools"] = tools.map { ["type": "function", "function": $0] as [String: Any] } }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            return (text: "Error: Unable to parse response", toolCalls: [])
        }
        
        let text = message["content"] as? String ?? ""
        var toolCalls: [AIToolCall] = []
        if let tcs = message["tool_calls"] as? [[String: Any]] {
            for tc in tcs {
                if let function = tc["function"] as? [String: Any], let name = function["name"] as? String {
                    let argsStr = function["arguments"] as? String ?? "{}"
                    let args = (try? JSONSerialization.jsonObject(with: Data(argsStr.utf8))) as? [String: Any] ?? [:]
                    toolCalls.append(AIToolCall(id: tc["id"] as? String ?? UUID().uuidString, name: name, arguments: args))
                }
            }
        }
        return (text: text, toolCalls: toolCalls)
    }
    
    private func syncAnthropic(messages: [[(String, Any)]], systemPrompt: String?, model: String, apiKey: String, tools: [[String: Any]]?) async throws -> (text: String, toolCalls: [AIToolCall]) {
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "cloud"
        let baseURL = keyMode == "direct" ? StreamableAIProvider.anthropic.directBaseURL : StreamableAIProvider.anthropic.cloudBaseURL
        let url = URL(string: "\(baseURL)/messages")!
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") // Required for Dotmini Proxy Auth
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        var apiMessages: [[String: Any]] = []
        for msg in messages {
            let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
            let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
            apiMessages.append(["role": role, "content": content])
        }
        
        var body: [String: Any] = ["model": model, "max_tokens": 16384, "messages": apiMessages]
        if let sys = systemPrompt { body["system"] = sys }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            return (text: "Error: Unable to parse response", toolCalls: [])
        }
        
        var text = ""
        var toolCalls: [AIToolCall] = []
        for block in content {
            if block["type"] as? String == "text" { text += block["text"] as? String ?? "" }
            if block["type"] as? String == "tool_use", let name = block["name"] as? String {
                toolCalls.append(AIToolCall(id: block["id"] as? String ?? UUID().uuidString, name: name, arguments: block["input"] as? [String: Any] ?? [:]))
            }
        }
        return (text: text, toolCalls: toolCalls)
    }
}
