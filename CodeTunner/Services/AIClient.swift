//
//  AIClient.swift
//  CodeTunner
//
//  Direct AI API Client with Streaming Support
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
    
    var baseURL: String {
        switch self {
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        }
    }
    
    var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.0-flash"
        case .openai: return "gpt-4o"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .deepseek: return "deepseek-chat"
        }
    }
}

// MARK: - AI Client

// MARK: - Attachments

struct AIAttachment {
    let name: String
    let data: Data // Raw data
    let type: AttachmentType
    
    enum AttachmentType {
        case image(format: String) // png, jpeg
        case text // code, txt, md
        case pdf  // requires extraction
    }
    
    var base64String: String {
        return data.base64EncodedString()
    }
    
    var textContent: String? {
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - AI Client

@MainActor
class AIClient: ObservableObject {
    static let shared = AIClient()
    
    @Published var isStreaming = false
    @Published var currentStreamedText = ""
    
    private var streamTask: Task<Void, Never>?
    
    // MARK: - Send Message with Streaming
    
    /// Maximum number of history messages to include (sliding window)
    private let maxHistoryMessages = 20
    
    func sendMessage(
        prompt: String,
        attachments: [AIAttachment] = [],
        systemPrompt: String? = nil,
        conversationHistory: [(role: String, content: String)] = [],
        provider: StreamableAIProvider,
        model: String,
        apiKey: String,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard !apiKey.isEmpty else {
            onError("API Key is missing. Please set it in Settings.")
            return
        }
        
        isStreaming = true
        currentStreamedText = ""
        
        // Apply sliding window to history
        let trimmedHistory = Array(conversationHistory.suffix(maxHistoryMessages))
        
        streamTask = Task {
            do {
                switch provider {
                case .gemini:
                    try await streamGemini(prompt: prompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: model, apiKey: apiKey, onToken: onToken)
                case .openai, .deepseek:
                    try await streamOpenAI(prompt: prompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: model, apiKey: apiKey, baseURL: provider.baseURL, onToken: onToken)
                case .anthropic:
                    try await streamAnthropic(prompt: prompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: model, apiKey: apiKey, onToken: onToken)
                }
                
                await MainActor.run {
                    onComplete(self.currentStreamedText)
                    self.isStreaming = false
                }
            } catch {
                await MainActor.run {
                    onError(error.localizedDescription)
                    self.isStreaming = false
                }
            }
        }
    }
    
    func cancelStream() {
        streamTask?.cancel()
        isStreaming = false
    }
    
    // MARK: - Gemini Streaming
    
    private func streamGemini(prompt: String, attachments: [AIAttachment], systemPrompt: String?, conversationHistory: [(role: String, content: String)], model: String, apiKey: String, onToken: @escaping (String) -> Void) async throws {
        let url = URL(string: "\(StreamableAIProvider.gemini.baseURL)/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var contents: [[String: Any]] = []
        
        if let sys = systemPrompt {
            contents.append(["role": "user", "parts": [["text": sys]]])
            contents.append(["role": "model", "parts": [["text": "Understood. I'll follow these instructions."]]])
        }
        
        // Add conversation history
        for msg in conversationHistory {
            let geminiRole = msg.role == "assistant" ? "model" : "user"
            contents.append(["role": geminiRole, "parts": [["text": msg.content]]])
        }
        
        var userParts: [[String: Any]] = []
        
        // Add text prompt
        userParts.append(["text": prompt])
        
        // Add attachments
        for attachment in attachments {
            switch attachment.type {
            case .image(let format):
                userParts.append([
                    "inlineData": [
                        "mimeType": "image/\(format)",
                        "data": attachment.base64String
                    ]
                ])
            case .text:
                if let text = attachment.textContent {
                    userParts.append(["text": "\n[File: \(attachment.name)]\n\(text)\n[/File]\n"])
                }
            case .pdf:
                userParts.append([
                    "inlineData": [
                        "mimeType": "application/pdf",
                        "data": attachment.base64String
                    ]
                ])
            }
        }
        
        contents.append(["role": "user", "parts": userParts])
        
        let body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 8192
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Try to read error body
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Gemini API failed"])
        }
        
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else { continue }
            
            await MainActor.run {
                self.currentStreamedText += text
                onToken(text)
            }
        }
    }
    
    // MARK: - OpenAI/DeepSeek Streaming
    
    private func streamOpenAI(prompt: String, attachments: [AIAttachment], systemPrompt: String?, conversationHistory: [(role: String, content: String)], model: String, apiKey: String, baseURL: String, onToken: @escaping (String) -> Void) async throws {
        let url = URL(string: "\(baseURL)/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        var messages: [[String: Any]] = []
        
        if let sys = systemPrompt {
            messages.append(["role": "system", "content": sys])
        }
        
        // Add conversation history
        for msg in conversationHistory {
            messages.append(["role": msg.role, "content": msg.content])
        }
        
        // Current message with attachments
        var contentArray: [[String: Any]] = []
        contentArray.append(["type": "text", "text": prompt])
        
        for attachment in attachments {
            switch attachment.type {
            case .image(let format):
                contentArray.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/\(format);base64,\(attachment.base64String)"
                    ]
                ])
            case .text:
                if let text = attachment.textContent {
                    contentArray.append(["type": "text", "text": "\n[File: \(attachment.name)]\n\(text)\n"])
                }
            case .pdf:
                 contentArray.append(["type": "text", "text": "\n[System: PDF '\(attachment.name)' ignored. Please extract text.]\n"])
            }
        }
        
        messages.append(["role": "user", "content": contentArray])
        
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true,
            "temperature": 0.7
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
             throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "OpenAI API failed"])
        }
        
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: "), line != "data: [DONE]" else { continue }
            let jsonString = String(line.dropFirst(6))
            
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { continue }
            
            await MainActor.run {
                self.currentStreamedText += content
                onToken(content)
            }
        }
    }
    
    // MARK: - Anthropic Streaming
    
    private func streamAnthropic(prompt: String, attachments: [AIAttachment], systemPrompt: String?, conversationHistory: [(role: String, content: String)], model: String, apiKey: String, onToken: @escaping (String) -> Void) async throws {
        let url = URL(string: "\(StreamableAIProvider.anthropic.baseURL)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        // Build messages array with history
        var allMessages: [[String: Any]] = []
        
        // Add conversation history
        for msg in conversationHistory {
            allMessages.append(["role": msg.role, "content": msg.content])
        }
        
        // Current message with attachments
        var messageContent: [[String: Any]] = []
        
        for attachment in attachments {
            if case .image(let format) = attachment.type {
                messageContent.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/\(format)",
                        "data": attachment.base64String
                    ]
                ])
            } else if case .text = attachment.type, let text = attachment.textContent {
                messageContent.append(["type": "text", "text": "File: \(attachment.name)\n\(text)"])
            }
        }
        
        messageContent.append(["type": "text", "text": prompt])
        allMessages.append(["role": "user", "content": messageContent])
        
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "stream": true,
            "messages": allMessages
        ]
         if let sys = systemPrompt { body["system"] = sys }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // ... Reuse generic stream handling ...
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
             throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Anthropic API failed"])
        }
        
        for try await line in bytes.lines {
             if Task.isCancelled { break }
             guard line.hasPrefix("data: ") else { continue }
             let jsonString = String(line.dropFirst(6))
             
             guard let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["type"] as? String == "content_block_delta",
                   let delta = json["delta"] as? [String: Any],
                   let text = delta["text"] as? String else { continue }
                   
             await MainActor.run {
                 self.currentStreamedText += text
                 onToken(text)
             }
        }
    }

}
