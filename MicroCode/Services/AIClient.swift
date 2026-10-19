//
//  AIClient.swift
//  MicroCode
//
//  Created and Designed by Dotmini Software
//  Founder & CEO: Tirawat Nantamas
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//
//  Description:
//  Production AI API Client with streaming, tool calling / function execution,
//  multi-provider dispatch (BYOK Direct API, Dotmini Cloud, Subscription OAuth, and Local LLM),
//  robust token handling, and multi-modal attachment support.
//

import Foundation
import Combine
import AppKit
import PDFKit

// MARK: - AI Provider

enum StreamableAIProvider: String, CaseIterable {
    case omni = "omni"
    case anthropic = "anthropic"
    case openai = "openai"
    case gemini = "gemini"
    case deepseek = "deepseek"
    case qwen = "qwen"
    case grok = "grok"
    case glm = "glm"
    case copilot = "copilot"
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
        case .omni: return "https://api.dotmini.net/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .grok: return "https://api.x.ai/v1"
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .glm: return "https://open.bigmodel.cn/api/paas/v4"
        case .copilot: return "https://api.githubcopilot.com"
        case .local: return LocalLLMService.cachedEndpoint
        }
    }
    
    var defaultModel: String {
        if Thread.isMainThread {
            if let liveFirst = MainActor.assumeIsolated({ AIModelCatalog.shared.provider(self.rawValue)?.models.first?.id }),
               !liveFirst.isEmpty {
                return liveFirst
            }
        }
        switch self {
        case .local: return LocalLLMService.cachedModel
        case .copilot: return "auto"
        default: return ""
        }
    }
    
    /// Whether this provider uses OpenAI-compatible chat/completions API format
    var usesOpenAIFormat: Bool {
        switch self {
        case .omni, .openai, .deepseek, .grok, .qwen, .glm, .copilot, .local: return true
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
        let m = model.lowercased()
        if m.contains("omni") || m.contains("dotmini") || m.contains("typhoon") { return .omni }
        if m.contains("claude") { return .anthropic }
        if m.contains("gpt") || m.contains("codex") || m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4") { return .openai }
        if m.contains("gemini") || m.contains("gemma") { return .gemini }
        if m.contains("deepseek") { return .deepseek }
        if m.contains("qwen") { return .qwen }
        if m.contains("grok") { return .grok }
        if m.contains("glm") { return .glm }
        return .omni
    }
}

// MARK: - Attachments

struct AIAttachment: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
    let type: AttachmentType
    
    enum AttachmentType: Equatable {
        case image(format: String)
        case text
        case pdf
    }
    
    var base64String: String { data.base64EncodedString() }
    var textContent: String? { String(data: data, encoding: .utf8) }
    
    /// Cached or dynamically generated NSImage for visual thumbnails
    var nsImage: NSImage? {
        if case .image = type {
            return NSImage(data: data)
        }
        return nil
    }
    
    /// Human-friendly formatted file size (e.g. "42 KB", "1.4 MB")
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
    
    /// Page count if attachment is a PDF
    var pdfPageCount: Int {
        guard case .pdf = type, let doc = PDFDocument(data: data) else { return 0 }
        return doc.pageCount
    }
    
    /// Extracted plain text across all pages if attachment is a PDF
    var pdfExtractedText: String {
        guard case .pdf = type, let doc = PDFDocument(data: data) else { return "" }
        var result = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let pageText = page.string {
                result += pageText + "\n"
            }
        }
        return result
    }
}

// MARK: - AI Tool Calling

struct AIToolCall: Identifiable {
    let id: String
    let name: String
    let arguments: [String: Any]
    var thoughtSignature: String? = nil
}

struct AIStructuredToolResult {
    let toolCallId: String
    let name: String
    let output: String
    let success: Bool
}

enum AIStructuredTurn {
    case assistantToolCalls(text: String, toolCalls: [AIToolCall])
    case toolResults(results: [AIStructuredToolResult], directive: String)
}

enum AIStructuredTurnCodec {
    static let markerKey = "_mc_structured_turn"

    static func stripThoughtTags(_ text: String) -> String {
        guard text.contains("<thought>") else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let cleaned = text.replacingOccurrences(
            of: "<thought>[\\s\\S]*?</thought>",
            with: "",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func encodeAssistantTurn(text: String, toolCalls: [AIToolCall]) -> String {
        let tcPayload: [[String: Any]] = toolCalls.map { tc in
            var dict: [String: Any] = [
                "id": tc.id,
                "name": tc.name,
                "arguments": tc.arguments
            ]
            if let sig = tc.thoughtSignature, !sig.isEmpty {
                dict["thoughtSignature"] = sig
            }
            return dict
        }
        let payload: [String: Any] = [
            markerKey: true,
            "kind": "assistant_tool_calls",
            "text": text,
            "tool_calls": tcPayload
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return text
        }
        return json
    }

    static func encodeToolResultsTurn(results: [AIStructuredToolResult], directive: String) -> String {
        let resPayload: [[String: Any]] = results.map { r in
            [
                "tool_call_id": r.toolCallId,
                "name": r.name,
                "output": r.output,
                "success": r.success
            ]
        }
        let payload: [String: Any] = [
            markerKey: true,
            "kind": "tool_results",
            "results": resPayload,
            "directive": directive
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return directive
        }
        return json
    }

    static func decode(_ content: String) -> AIStructuredTurn? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.contains("\"\(markerKey)\""),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json[markerKey] as? Bool) == true,
              let kind = json["kind"] as? String else {
            return nil
        }

        if kind == "assistant_tool_calls" {
            let text = json["text"] as? String ?? ""
            let rawCalls = json["tool_calls"] as? [[String: Any]] ?? []
            let calls: [AIToolCall] = rawCalls.compactMap { item in
                guard let name = item["name"] as? String, !name.isEmpty else { return nil }
                let id = item["id"] as? String ?? UUID().uuidString
                let args = item["arguments"] as? [String: Any] ?? [:]
                let sig = item["thoughtSignature"] as? String
                return AIToolCall(id: id, name: name, arguments: args, thoughtSignature: sig)
            }
            return .assistantToolCalls(text: text, toolCalls: calls)
        } else if kind == "tool_results" {
            let rawResults = json["results"] as? [[String: Any]] ?? []
            let results: [AIStructuredToolResult] = rawResults.compactMap { item in
                guard let name = item["name"] as? String else { return nil }
                let id = item["tool_call_id"] as? String ?? UUID().uuidString
                let output = item["output"] as? String ?? ""
                let success = item["success"] as? Bool ?? true
                return AIStructuredToolResult(toolCallId: id, name: name, output: output, success: success)
            }
            let directive = json["directive"] as? String ?? ""
            return .toolResults(results: results, directive: directive)
        }
        return nil
    }

    /// Compacts oversized tool output inside a structured turn without breaking its JSON envelope.
    static func compactToolOutputsIfNeeded(_ content: String, maxCharsPerOutput: Int) -> String {
        guard case .toolResults(let results, let directive) = decode(content) else {
            return content
        }
        var changed = false
        let compactedResults: [AIStructuredToolResult] = results.map { r in
            guard r.output.count > maxCharsPerOutput else { return r }
            changed = true
            let headCount = max(500, (maxCharsPerOutput * 2) / 3)
            let tailCount = max(250, maxCharsPerOutput / 3)
            let head = String(r.output.prefix(headCount))
            let tail = String(r.output.suffix(tailCount))
            let compacted = head + "\n... [Earlier tool output compacted] ...\n" + tail
            return AIStructuredToolResult(toolCallId: r.toolCallId, name: r.name, output: compacted, success: r.success)
        }
        guard changed else { return content }
        return encodeToolResultsTurn(results: compactedResults, directive: directive)
    }
}


// MARK: - Streaming Client

@MainActor
final class AIClient: ObservableObject {
    static let shared = AIClient()
    
    @Published var isStreaming: Bool = false
    @Published var currentStreamedText: String = ""
    
    private var streamTask: Task<Void, Never>?
    private let requestTimeout: TimeInterval = 60
    private var pendingStreamTokens: String = ""
    private var lastStreamDeliveryUptime: TimeInterval = 0
    private let streamFlushInterval: TimeInterval = 0.016 // ~60fps target for smooth text render
    
    private func appendStreamToken(_ token: String, onToken: @escaping (String) -> Void) {
        pendingStreamTokens += token
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastStreamDeliveryUptime >= streamFlushInterval || token.contains("\n") {
            flushPendingStreamTokens(onToken: onToken)
        }
    }
    
    private func flushPendingStreamTokens(onToken: @escaping (String) -> Void) {
        guard !pendingStreamTokens.isEmpty else { return }
        let chunk = pendingStreamTokens
        pendingStreamTokens = ""
        lastStreamDeliveryUptime = ProcessInfo.processInfo.systemUptime
        currentStreamedText += chunk
        onToken(chunk)
    }
    
    private func detectStreamRepetitionLoop(_ fullText: String) -> Bool {
        let lines = fullText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 8 }
        
        let count = lines.count
        guard count >= 3 else { return false }
        
        // 1. Triple repetition of identical line: A, A, A
        if lines[count - 1] == lines[count - 2] && lines[count - 2] == lines[count - 3] {
            return true
        }
        
        // 2. Alternating 2-line cycle: A, B, A, B, A, B
        if count >= 6 {
            let n = count
            if lines[n-1] == lines[n-3] && lines[n-3] == lines[n-5] &&
               lines[n-2] == lines[n-4] && lines[n-4] == lines[n-6] {
                return true
            }
        }
        
        return false
    }
    
    private func boundedHistory(_ history: [(role: String, content: String)]) -> [(role: String, content: String)] {
        // Scaled for modern 1M-2M+ token architectures (no artificial message or char caps)
        let maxMessages = 1000
        let maxCharsPerMessage = 4_000_000
        let recent = Array(history.suffix(maxMessages))
        return recent.map { (role: $0.role, content: boundedText($0.content, limit: maxCharsPerMessage)) }
    }
    
    private func normalizeModelName(_ model: String, provider: StreamableAIProvider, baseURL: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return provider.defaultModel
        }
        let lower = trimmed.lowercased()
        if provider == .deepseek && lower == "deepseek" {
            return provider.defaultModel
        } else if provider == .gemini && lower == "gemini" {
            return provider.defaultModel
        } else if provider == .openai && lower == "openai" {
            return provider.defaultModel
        }
        return trimmed
    }
    
    /// Sanitize a tool schema for Gemini API compatibility.
    /// Gemini's function calling requires every `type: "array"` property
    /// to have an `items` field and doesn't support OpenAI-only keys like
    /// `additionalProperties` or `default`.
    private func sanitizeToolSchemaForGemini(_ tool: [String: Any]) -> [String: Any] {
        var result = tool
        if var parameters = result["parameters"] as? [String: Any] {
            parameters = sanitizeSchemaObject(parameters)
            result["parameters"] = parameters
        }
        return result
    }
    
    private func sanitizeSchemaObject(_ schema: [String: Any]) -> [String: Any] {
        var s = schema
        // Remove keys not supported by Gemini's schema
        s.removeValue(forKey: "additionalProperties")
        s.removeValue(forKey: "default")
        
        // Fix array types missing "items"
        if let type = s["type"] as? String, type == "array" {
            if s["items"] == nil {
                s["items"] = ["type": "string"]
            } else if var items = s["items"] as? [String: Any] {
                items = sanitizeSchemaObject(items)
                s["items"] = items
            }
        }
        
        // Recursively fix properties
        if var properties = s["properties"] as? [String: Any] {
            for (key, value) in properties {
                if var prop = value as? [String: Any] {
                    prop = sanitizeSchemaObject(prop)
                    properties[key] = prop
                }
            }
            s["properties"] = properties
        }
        
        return s
    }


    private func boundedText(_ text: String, limit: Int) -> String {
        guard text.count > limit, limit > 64 else { return String(text.prefix(max(0, limit))) }
        let headCount = (limit * 2) / 3
        return String(text.prefix(headCount)) + "\n…[context truncated]…\n" + String(text.suffix(limit - headCount))
    }
    
    private func resolveSubscriptionToken(for provider: StreamableAIProvider) -> String {
        let explicitSubName = UserDefaults.standard.string(forKey: "subscriptionActiveProvider")
        let subType: SubscriptionProviderType
        if let explicitSubName, let explicit = SubscriptionProviderType(rawValue: explicitSubName),
           SubscriptionAuthManager.shared.isConnected(explicit) {
            if (provider == .openai && (explicit == .chatgpt || explicit == .copilot)) ||
               (provider == .anthropic && (explicit == .claude || explicit == .copilot)) ||
               (provider == .gemini && explicit == .gemini) ||
               (provider == .deepseek && explicit == .deepseek) ||
               (provider == .glm && explicit == .glm) ||
               (provider == .copilot && explicit == .copilot) {
                subType = explicit
            } else {
                switch provider {
                case .anthropic: subType = .claude
                case .glm: subType = .glm
                case .gemini: subType = .gemini
                case .deepseek: subType = .deepseek
                case .copilot: subType = .copilot
                default: subType = explicit == .copilot ? .copilot : .chatgpt
                }
            }
        } else {
            switch provider {
            case .anthropic: subType = .claude
            case .glm: subType = .glm
            case .gemini: subType = .gemini
            case .deepseek: subType = .deepseek
            case .copilot: subType = .copilot
            default:
                if SubscriptionAuthManager.shared.isConnected(.chatgpt) {
                    subType = .chatgpt
                } else if SubscriptionAuthManager.shared.isConnected(.copilot) {
                    subType = .copilot
                } else {
                    subType = .chatgpt
                }
            }
        }
        return SubscriptionAuthManager.shared.getAccount(subType)?.sessionToken ?? ""
    }
    
    /// Returns the full SubscriptionAccount for a given provider (mirrors resolveSubscriptionToken logic)
    private func resolveSubscriptionAccount(for provider: StreamableAIProvider) -> SubscriptionAccount? {
        let explicitSubName = UserDefaults.standard.string(forKey: "subscriptionActiveProvider")
        let subType: SubscriptionProviderType
        if let explicitSubName, let explicit = SubscriptionProviderType(rawValue: explicitSubName),
           SubscriptionAuthManager.shared.isConnected(explicit) {
            if (provider == .openai && (explicit == .chatgpt || explicit == .copilot)) ||
               (provider == .anthropic && (explicit == .claude || explicit == .copilot)) ||
               (provider == .gemini && explicit == .gemini) ||
               (provider == .deepseek && explicit == .deepseek) ||
               (provider == .glm && explicit == .glm) ||
               (provider == .copilot && explicit == .copilot) {
                subType = explicit
            } else {
                switch provider {
                case .anthropic: subType = .claude
                case .glm: subType = .glm
                case .gemini: subType = .gemini
                case .deepseek: subType = .deepseek
                case .copilot: subType = .copilot
                default: subType = explicit == .copilot ? .copilot : .chatgpt
                }
            }
        } else {
            switch provider {
            case .anthropic: subType = .claude
            case .glm: subType = .glm
            case .gemini: subType = .gemini
            case .deepseek: subType = .deepseek
            case .copilot: subType = .copilot
            default:
                if SubscriptionAuthManager.shared.isConnected(.chatgpt) {
                    subType = .chatgpt
                } else if SubscriptionAuthManager.shared.isConnected(.copilot) {
                    subType = .copilot
                } else {
                    subType = .chatgpt
                }
            }
        }
        return SubscriptionAuthManager.shared.getAccount(subType)
    }
    
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
        let ent = EnterpriseAIAuthService.shared
        let safePrompt = ent.redactPromptIfNeeded(prompt)
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "cloud"
        var actualKey: String = ""
        var baseURL: String = provider.directBaseURL
        let useVertexGemini = (ent.mode == .geminiVertex && provider == .gemini)
        let useDotminiEnterprise = (ent.mode == .dotminiEnterprise)
        let useCustomGateway = (ent.mode == .customGateway && !ent.customGatewayBaseURL.isEmpty)
        
        if provider == .local || keyMode == "local" {
            actualKey = "local"
            baseURL = LocalLLMService.cachedEndpoint
        } else if useVertexGemini {
            actualKey = "vertex_enterprise"
            baseURL = "vertex://\(ent.vertexLocation)/\(ent.vertexProjectId)"
        } else if useDotminiEnterprise {
            actualKey = !ent.dotminiEnterpriseKey.isEmpty
                ? ent.dotminiEnterpriseKey
                : (DotminiPlatformKeyService.shared.authorizationToken ?? SupabaseAuthService.shared.accessToken ?? "")
            baseURL = ent.dotminiEnterpriseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if useCustomGateway {
            actualKey = ent.customGatewayAPIKey
            baseURL = ent.customGatewayBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if apiKey == "codex_oauth", let codexCreds = Self.loadCodexOAuthCredentials(fallbackToken: "") {
            actualKey = codexCreds.accessToken
            baseURL = "https://chatgpt.com/backend-api/codex"
        } else if keyMode == "subscription" {
            let resolvedByokKey = AIModelCatalog.resolveKey(provider.rawValue)
            let passedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let account = resolveSubscriptionAccount(for: provider)
            let subToken = account?.sessionToken.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            if let account, account.provider == .copilot, SubscriptionAuthManager.shared.isConnected(.copilot) {
                actualKey = subToken
                baseURL = StreamableAIProvider.copilot.directBaseURL
            } else if provider == .openai,
                      let codexCreds = Self.loadCodexOAuthCredentials(fallbackToken: subToken),
                      !(resolvedByokKey.hasPrefix("sk-") && !resolvedByokKey.hasPrefix("sk-ant-")) {
                actualKey = codexCreds.accessToken
                baseURL = "https://chatgpt.com/backend-api/codex"
            } else if !subToken.isEmpty && !subToken.hasPrefix("cli-oauth:") {
                actualKey = subToken
                baseURL = provider.directBaseURL
            } else if !resolvedByokKey.isEmpty {
                actualKey = resolvedByokKey
                baseURL = provider.directBaseURL
            } else if !passedKey.isEmpty && !passedKey.hasPrefix("cli-oauth:") {
                actualKey = passedKey
                baseURL = provider.directBaseURL
            } else if provider == .openai, let codexCreds = Self.loadCodexOAuthCredentials(fallbackToken: "") {
                actualKey = codexCreds.accessToken
                baseURL = "https://chatgpt.com/backend-api/codex"
            } else {
                let message = "No active subscription or API key found for \(provider.rawValue). Connect in Settings → AI Provider → Subscription, or add a Direct API Key."
                onError(message)
                return
            }
        } else if keyMode == "direct" {
            // ━━━ BYOK (DIRECT) MODE ━━━
            // Uses ONLY user's own API keys — no cloud proxy, no subscription
            let passedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedKey = AIModelCatalog.resolveKey(provider.rawValue)
            
            if !passedKey.isEmpty {
                actualKey = passedKey
            } else if !resolvedKey.isEmpty {
                actualKey = resolvedKey
            } else if provider == .openai, let codexCreds = Self.loadCodexOAuthCredentials(fallbackToken: "") {
                actualKey = codexCreds.accessToken
                baseURL = "https://chatgpt.com/backend-api/codex"
            } else {
                actualKey = ""
            }
            if baseURL != "https://chatgpt.com/backend-api/codex" {
                baseURL = provider.directBaseURL
            }
            
        } else {
            // ━━━ CLOUD MODE (Dotmini) ━━━
            // Uses ONLY Dotmini platform credentials — no BYOK, no subscription
            let microToken = DotminiPlatformKeyService.shared.authorizationToken
                ?? SupabaseAuthService.shared.accessToken ?? ""
            actualKey = microToken
            baseURL = provider.cloudBaseURL
        }
        
        if actualKey.isEmpty && provider != .local && provider != .omni && !useVertexGemini && !useCustomGateway {
            switch keyMode {
            case "subscription":
                onError("No subscription session found for \(provider.rawValue). Go to Settings → AI Provider → Subscription to connect.")
                return
            case "direct":
                onError("API key missing for \(provider.rawValue). Go to Settings → AI Provider → BYOK to add your key.")
                return
            default:
                // In cloud mode, requests route to Dotmini Cloud via X-Dotmini-Product and X-Dotmini-License
                break
            }
        }

        isStreaming = true
        currentStreamedText = ""
        pendingStreamTokens = ""
        lastStreamDeliveryUptime = 0
        
        let trimmedHistory = boundedHistory(conversationHistory)
        let resolvedModel = normalizeModelName(model, provider: provider, baseURL: baseURL)
        
        streamTask = Task {
            let requestKey: String
            if useDotminiEnterprise {
                if !ent.dotminiEnterpriseKey.isEmpty {
                    requestKey = ent.dotminiEnterpriseKey
                } else if let platformKey = DotminiPlatformKeyService.shared.authorizationToken {
                    requestKey = platformKey
                } else {
                    requestKey = actualKey
                }
            } else if keyMode == "cloud" && baseURL == provider.cloudBaseURL && provider != .local {
                if let platformKey = DotminiPlatformKeyService.shared.authorizationToken {
                    requestKey = platformKey
                } else if SupabaseAuthService.shared.session != nil {
                    guard let refreshed = await SupabaseAuthService.shared.refreshAccessTokenIfNeeded() else {
                        onError("Could not refresh your Dotmini session. Check your connection or sign in again.")
                        self.isStreaming = false
                        return
                    }
                    requestKey = refreshed
                } else {
                    requestKey = actualKey
                }
            } else {
                requestKey = actualKey
            }
            var retryCount = 0
            let maxRetries = 3
            
            while retryCount <= maxRetries {
                if retryCount > 0 {
                    self.currentStreamedText = ""
                    self.pendingStreamTokens = ""
                }
                do {
                    if useVertexGemini {
                        try await streamGemini(prompt: safePrompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, apiKey: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                    } else if baseURL == "https://chatgpt.com/backend-api/codex" {
                        try await streamCodexResponses(prompt: safePrompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, accessToken: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                    } else if useDotminiEnterprise || useCustomGateway || baseURL == provider.cloudBaseURL || baseURL == StreamableAIProvider.copilot.directBaseURL {
                        // Cloud-routed requests (Dotmini Cloud Enterprise, Dotmini Cloud, Custom Gateway, or GitHub Copilot) use OpenAI-compatible gateway
                        try await streamOpenAI(prompt: safePrompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, apiKey: requestKey, baseURL: baseURL, tools: tools, onToken: onToken, onToolCall: onToolCall)
                    } else {
                        // Direct / Subscription mode with native provider endpoints
                        switch provider {
                        case .gemini:
                            let lower = resolvedModel.lowercased()
                            if !lower.contains("gemini") && !lower.contains("gemma") {
                                let fallback = StreamableAIProvider.detect(from: resolvedModel)
                                if fallback != .gemini {
                                    try await streamOpenAI(prompt: safePrompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, apiKey: requestKey, baseURL: fallback.directBaseURL, tools: tools, onToken: onToken, onToolCall: onToolCall)
                                } else {
                                    try await streamGemini(prompt: safePrompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, apiKey: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                                }
                            } else {
                                try await streamGemini(prompt: safePrompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, apiKey: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                            }
                        case .anthropic:
                            try await streamAnthropic(prompt: safePrompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, apiKey: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                        case .omni, .openai, .deepseek, .grok, .qwen, .glm, .copilot, .local:
                            try await streamOpenAI(prompt: safePrompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, apiKey: requestKey, baseURL: baseURL, tools: tools, onToken: onToken, onToolCall: onToolCall)
                        }
                    }
                    
                    self.flushPendingStreamTokens(onToken: onToken)
                    onComplete(self.currentStreamedText)
                    self.isStreaming = false
                    return // Success
                    
                } catch let error as NSError {
                    // Retry on transient errors
                    let transientCodes: Set<Int> = [429, 503, -1001, -1004, -1005, -1009]
                    if transientCodes.contains(error.code) && retryCount < maxRetries {
                        retryCount += 1
                        let delay = UInt64(pow(2.0, Double(retryCount))) * 1_000_000_000
                        try? await Task.sleep(nanoseconds: delay)
                        continue
                    }
                    
                    onError(self.parseErrorMessage(error))
                    self.isStreaming = false
                    return
                }
            }
        }
    }
    
    func cancelStream() {
        streamTask?.cancel()
        pendingStreamTokens = ""
        isStreaming = false
    }
    
    // MARK: - Codex ChatGPT Subscription OAuth Support
    
    static func loadCodexOAuthCredentials(fallbackToken: String) -> (accessToken: String, accountId: String, defaultModel: String)? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let authURL = home.appendingPathComponent(".codex/auth.json")
        var accessToken = ""
        var accountId = ""
        if let data = try? Data(contentsOf: authURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let tokens = json["tokens"] as? [String: Any] {
                accessToken = (tokens["access_token"] as? String) ?? ""
                accountId = (tokens["account_id"] as? String) ?? ""
            }
            if accessToken.isEmpty {
                accessToken = (json["access_token"] as? String) ?? ""
            }
        }
        if accessToken.isEmpty && !fallbackToken.isEmpty && !fallbackToken.hasPrefix("sk-") && !fallbackToken.hasPrefix("cli-oauth:") {
            accessToken = fallbackToken
        }
        guard !accessToken.isEmpty else { return nil }
        
        var defaultModel = "gpt-6-luna"
        let configURL = home.appendingPathComponent(".codex/config.toml")
        if let configStr = try? String(contentsOf: configURL, encoding: .utf8) {
            for line in configStr.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("model =") || trimmed.hasPrefix("model=") {
                    let parts = trimmed.split(separator: "=", maxSplits: 1)
                    if parts.count > 1 {
                        let m = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                        if !m.isEmpty { defaultModel = m }
                    }
                }
            }
        }
        return (accessToken, accountId, defaultModel)
    }
    
    private func streamCodexResponses(
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        model: String,
        accessToken: String,
        tools: [[String: Any]]?,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws {
        let creds = Self.loadCodexOAuthCredentials(fallbackToken: accessToken)
        let token = creds?.accessToken ?? accessToken
        let accountId = creds?.accountId ?? ""
        let fallbackModel = creds?.defaultModel ?? "gpt-6-luna"
        
        var candidateModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidateModel.isEmpty || candidateModel == "gpt-4o" || candidateModel == "gpt-4o-mini" || candidateModel == "gpt-5.4" || candidateModel == "gpt-5.4-mini" {
            candidateModel = fallbackModel
        }
        
        try await executeCodexResponsesStream(
            prompt: prompt,
            attachments: attachments,
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            model: candidateModel,
            fallbackModel: fallbackModel,
            token: token,
            accountId: accountId,
            tools: tools,
            onToken: onToken,
            onToolCall: onToolCall
        )
    }
    
    private func executeCodexResponsesStream(
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        model: String,
        fallbackModel: String,
        token: String,
        accountId: String,
        tools: [[String: Any]]?,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws {
        guard let url = URL(string: "https://chatgpt.com/backend-api/codex/responses") else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Codex Responses URL"])
        }
        
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("codex_cli_rs/0.1.0", forHTTPHeaderField: "User-Agent")
        
        var inputItems: [[String: Any]] = []
        var activeCallIds: Set<String> = []
        
        func appendTurn(role: String, content: String) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if let structured = AIStructuredTurnCodec.decode(trimmed) {
                switch structured {
                case .assistantToolCalls(let text, let toolCalls):
                    let cleanText = AIStructuredTurnCodec.stripThoughtTags(text)
                    if !cleanText.isEmpty {
                        inputItems.append([
                            "type": "message",
                            "role": "assistant",
                            "content": [["type": "output_text", "text": cleanText]]
                        ])
                    }
                    activeCallIds.removeAll()
                    for tc in toolCalls {
                        let argsData = (try? JSONSerialization.data(withJSONObject: tc.arguments)) ?? Data("{}".utf8)
                        let argsStr = String(data: argsData, encoding: .utf8) ?? "{}"
                        inputItems.append([
                            "type": "function_call",
                            "call_id": tc.id,
                            "name": tc.name,
                            "arguments": argsStr
                        ])
                        activeCallIds.insert(tc.id)
                    }
                case .toolResults(let results, let directive):
                    var unmatched: [String] = []
                    for res in results {
                        if activeCallIds.contains(res.toolCallId) {
                            inputItems.append([
                                "type": "function_call_output",
                                "call_id": res.toolCallId,
                                "output": res.output
                            ])
                        } else {
                            unmatched.append("[\(res.name)]: \(res.output)")
                        }
                    }
                    activeCallIds.removeAll()
                    let combined = (unmatched + (directive.isEmpty ? [] : [directive])).joined(separator: "\n\n")
                    if !combined.isEmpty {
                        inputItems.append([
                            "type": "message",
                            "role": "user",
                            "content": [["type": "input_text", "text": combined]]
                        ])
                    }
                }
            } else {
                activeCallIds.removeAll()
                let cleanText = role == "assistant" ? AIStructuredTurnCodec.stripThoughtTags(trimmed) : trimmed
                guard !cleanText.isEmpty else { return }
                let contentType = role == "assistant" ? "output_text" : "input_text"
                inputItems.append([
                    "type": "message",
                    "role": role == "assistant" ? "assistant" : "user",
                    "content": [["type": contentType, "text": cleanText]]
                ])
            }
        }
        
        for msg in conversationHistory {
            appendTurn(role: msg.role, content: msg.content)
        }
        
        var finalUserPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        for attachment in attachments {
            switch attachment.type {
            case .text:
                if let t = attachment.textContent {
                    finalUserPrompt += "\n\n[File: \(attachment.name)]\n\(t)\n[/File]"
                }
            case .pdf:
                let pdfText = attachment.pdfExtractedText
                finalUserPrompt += "\n\n[Document: \(attachment.name)]\n\(pdfText)\n[/Document]"
            case .image:
                let visionResult = await AppleVisionEngine.shared.analyzeImage(data: attachment.data, filename: attachment.name)
                finalUserPrompt += "\n\n\(visionResult.formattedSummary)"
            }
        }
        if finalUserPrompt.isEmpty { finalUserPrompt = "Continue." }
        appendTurn(role: "user", content: finalUserPrompt)
        
        let instructions = (systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? systemPrompt!
            : "You are MicroCode AI, an expert software engineering assistant."
        
        var body: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": inputItems,
            "stream": true,
            "store": false
        ]
        
        if let tools = tools, !tools.isEmpty {
            let formattedTools: [[String: Any]] = tools.compactMap { t in
                guard let name = t["name"] as? String else { return nil }
                var item: [String: Any] = [
                    "type": "function",
                    "name": name,
                    "description": (t["description"] as? String) ?? ""
                ]
                if let params = t["parameters"] as? [String: Any] {
                    item["parameters"] = params
                }
                return item
            }
            if !formattedTools.isEmpty {
                body["tools"] = formattedTools
            }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from ChatGPT Codex"])
        }
        
        if http.statusCode != 200 {
            var errBody = ""
            for try await line in bytes.lines {
                errBody += line
                if errBody.count > 600 { break }
            }
            if http.statusCode == 400 && model != fallbackModel && (errBody.contains("not supported") || errBody.contains("model")) {
                try await executeCodexResponsesStream(
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: fallbackModel,
                    fallbackModel: fallbackModel,
                    token: token,
                    accountId: accountId,
                    tools: tools,
                    onToken: onToken,
                    onToolCall: onToolCall
                )
                return
            }
            throw NSError(domain: "AIClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "ChatGPT Codex error (\(http.statusCode)): \(errBody.prefix(240))"])
        }
        
        var isStreamingReasoning = false
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            if jsonStr == "[DONE]" || jsonStr.isEmpty { continue }
            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }
            
            switch type {
            case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
                if let delta = json["delta"] as? String, !delta.isEmpty {
                    if !isStreamingReasoning {
                        isStreamingReasoning = true
                        appendStreamToken("<thought>", onToken: onToken)
                    }
                    appendStreamToken(delta, onToken: onToken)
                }
            case "response.output_text.delta":
                if let delta = json["delta"] as? String, !delta.isEmpty {
                    if isStreamingReasoning {
                        isStreamingReasoning = false
                        appendStreamToken("</thought>\n\n", onToken: onToken)
                    }
                    appendStreamToken(delta, onToken: onToken)
                }
            case "response.output_item.done":
                if isStreamingReasoning {
                    isStreamingReasoning = false
                    appendStreamToken("</thought>\n\n", onToken: onToken)
                }
                if let item = json["item"] as? [String: Any],
                   (item["type"] as? String) == "function_call",
                   let name = item["name"] as? String {
                    let callId = (item["call_id"] as? String) ?? (item["id"] as? String) ?? UUID().uuidString
                    let argsStr = (item["arguments"] as? String) ?? "{}"
                    let args = (argsStr.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
                    onToolCall?(AIToolCall(id: callId, name: name, arguments: args))
                }
            default:
                break
            }
        }
        
        if isStreamingReasoning {
            appendStreamToken("</thought>\n\n", onToken: onToken)
        }
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
        let ent = EnterpriseAIAuthService.shared
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "cloud"
        let actualKey: String
        let baseURL: String
        let useVertexGemini = (ent.mode == .geminiVertex && provider == .gemini)
        let useDotminiEnterprise = (ent.mode == .dotminiEnterprise)
        let useCustomGateway = (ent.mode == .customGateway && !ent.customGatewayBaseURL.isEmpty)
        
        if provider == .local {
            actualKey = ""
            baseURL = provider.directBaseURL
        } else if useVertexGemini {
            actualKey = "vertex_enterprise"
            baseURL = "vertex://\(ent.vertexLocation)/\(ent.vertexProjectId)"
        } else if useDotminiEnterprise {
            let sessionToken = await SupabaseAuthService.shared.refreshAccessTokenIfNeeded()
            actualKey = !ent.dotminiEnterpriseKey.isEmpty
                ? ent.dotminiEnterpriseKey
                : (DotminiPlatformKeyService.shared.authorizationToken ?? sessionToken ?? "")
            baseURL = ent.dotminiEnterpriseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if useCustomGateway {
            actualKey = ent.customGatewayAPIKey
            baseURL = ent.customGatewayBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if keyMode == "subscription" {
            let resolvedByokKey = AIModelCatalog.resolveKey(provider.rawValue)
            let passedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let account = resolveSubscriptionAccount(for: provider)
            let subToken = account?.sessionToken.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            if let account, account.provider == .copilot, SubscriptionAuthManager.shared.isConnected(.copilot) {
                actualKey = subToken
                baseURL = StreamableAIProvider.copilot.directBaseURL
            } else if !subToken.isEmpty && !subToken.hasPrefix("cli-oauth:") {
                actualKey = subToken
                baseURL = provider.directBaseURL
            } else if !resolvedByokKey.isEmpty {
                actualKey = resolvedByokKey
                baseURL = provider.directBaseURL
            } else if !passedKey.isEmpty && !passedKey.hasPrefix("cli-oauth:") {
                actualKey = passedKey
                baseURL = provider.directBaseURL
            } else {
                throw NSError(domain: "AIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "No active subscription or API key found for \(provider.rawValue)."])
            }
        } else if keyMode == "direct" {
            // ━━━ BYOK (DIRECT) MODE ━━━
            let specificKey = AIModelCatalog.resolveKey(provider.rawValue)
            let legacyKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
            let passedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !specificKey.isEmpty {
                actualKey = specificKey
            } else if !passedKey.isEmpty {
                actualKey = passedKey
            } else if !legacyKey.isEmpty {
                actualKey = legacyKey
            } else {
                actualKey = ""
            }
            baseURL = provider.directBaseURL
            
        } else {
            // ━━━ CLOUD MODE (Dotmini) ━━━
            let sessionToken = await SupabaseAuthService.shared.refreshAccessTokenIfNeeded()
            let microToken = DotminiPlatformKeyService.shared.authorizationToken ?? sessionToken ?? ""
            actualKey = microToken
            baseURL = provider.cloudBaseURL
        }
        
        if useVertexGemini {
            return try await syncGemini(messages: messages, systemPrompt: systemPrompt, model: model, apiKey: actualKey, tools: tools)
        } else if useDotminiEnterprise || useCustomGateway || baseURL == provider.cloudBaseURL || baseURL == StreamableAIProvider.copilot.directBaseURL {
            // Cloud, Dotmini Enterprise, Custom Gateway, and Copilot use OpenAI-compatible transport
            return try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: model, apiKey: actualKey, baseURL: baseURL, tools: tools)
        } else {
            // Direct/Subscription mode → use native protocols
            switch provider {
            case .gemini:
                let lower = model.lowercased()
                if !lower.contains("gemini") && !lower.contains("gemma") {
                    let fallback = StreamableAIProvider.detect(from: model)
                    if fallback != .gemini {
                        return try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: model, apiKey: actualKey, baseURL: fallback.directBaseURL, tools: tools)
                    }
                }
                return try await syncGemini(messages: messages, systemPrompt: systemPrompt, model: model, apiKey: actualKey, tools: tools)
            case .anthropic:
                return try await syncAnthropic(messages: messages, systemPrompt: systemPrompt, model: model, apiKey: actualKey, tools: tools)
            case .omni, .openai, .deepseek, .grok, .qwen, .glm, .copilot, .local:
                return try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: model, apiKey: actualKey, baseURL: baseURL, tools: tools)
            }
        }
    }
    
    // MARK: - Error Parsing
    
    private func parseErrorMessage(_ error: NSError) -> String {
        if error.domain == NSURLErrorDomain || error.code == -1004 || error.code == -1001 || error.code == -1003 {
            return "Cannot connect to Dotmini Cloud AI. Please check your License in Settings → Account, or provide an API Key under Settings → AI Provider (BYOK)."
        }
        switch error.code {
        case 402: return "Payment required: Your credit balance is insufficient or requires top-up. Check Settings → Wallet."
        case 429: return "Rate limited by provider (HTTP 429: Requests/Tokens Per Minute quota exceeded on your API key). Please wait 1-2 minutes for the provider quota window to reset, or check your quota in Google AI Studio / provider console."
        case 401, 403: return "API Key or License is invalid/expired (401). If using BYOK, verify your key in Settings → AI Provider; if using Dotmini Cloud, check your License in Settings → Account."
        case 503, 500: return "AI service temporarily unavailable (500/503). Try again in a moment."
        default: return error.localizedDescription
        }
    }
    
    // MARK: - Token Limit Configuration
    
    private func maxOutputTokens(for model: String) -> Int {
        let lower = model.lowercased()
        if lower.contains("gemini") {
            return 65536
        } else if lower.contains("claude-3-7") || lower.contains("claude-3-opus") {
            return 64000
        } else if lower.contains("claude-3-5") {
            return 8192
        } else if lower.contains("o1") || lower.contains("o3") {
            return 65536
        } else if lower.contains("gpt-4o") || lower.contains("gpt-4") {
            return 16384
        } else if lower.contains("deepseek-reasoner") {
            return 64000
        } else if lower.contains("deepseek") {
            return 16384
        } else {
            return 16384
        }
    }
    
    // MARK: - Gemini Streaming
    
    private func streamGemini(prompt: String, attachments: [AIAttachment], systemPrompt: String?, conversationHistory: [(role: String, content: String)], model: String, apiKey: String, tools: [[String: Any]]?, onToken: @escaping (String) -> Void, onToolCall: ((AIToolCall) -> Void)?) async throws {
        let baseURL = StreamableAIProvider.gemini.directBaseURL
        let cleanModel = model.hasPrefix("models/") ? String(model.dropFirst(7)) : model
        let isVertexEnterprise = EnterpriseAIAuthService.shared.mode == .geminiVertex
        
        let url: URL
        if isVertexEnterprise, let vertexURL = EnterpriseAIAuthService.shared.buildVertexGeminiURL(model: cleanModel, streaming: true) {
            url = vertexURL
        } else if let directURL = URL(string: "\(baseURL)/models/\(cleanModel):streamGenerateContent?alt=sse&key=\(apiKey)") {
            url = directURL
        } else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL configuration for gemini"])
        }
        
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if isVertexEnterprise {
            if let authHeader = try await EnterpriseAIAuthService.shared.resolveVertexAuthorizationHeader() {
                request.setValue(authHeader, forHTTPHeaderField: "Authorization")
            }
            if !EnterpriseAIAuthService.shared.vertexProjectId.isEmpty {
                request.setValue(EnterpriseAIAuthService.shared.vertexProjectId, forHTTPHeaderField: "x-goog-user-project")
            }
        } else if baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == StreamableAIProvider.cloudProxyURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
            request.setValue("microcode", forHTTPHeaderField: "X-Dotmini-Product")
        }
        EnterpriseAIAuthService.shared.applyEnterpriseHeaders(to: &request)
        
        var body: [String: Any] = [
            "generationConfig": ["temperature": 0.7, "maxOutputTokens": maxOutputTokens(for: cleanModel)]
        ]
        
        if let sys = systemPrompt, !sys.isEmpty {
            body["systemInstruction"] = ["parts": [["text": sys]]]
        }
        
        var rawContents: [[String: Any]] = []
        
        func appendGeminiTurn(role: String, content: String) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if let structured = AIStructuredTurnCodec.decode(trimmed) {
                switch structured {
                case .assistantToolCalls(let text, let toolCalls):
                    var parts: [[String: Any]] = []
                    let cleanText = AIStructuredTurnCodec.stripThoughtTags(text)
                    if !cleanText.isEmpty {
                        parts.append(["text": cleanText])
                    }
                    for tc in toolCalls {
                        var part: [String: Any] = [
                            "functionCall": [
                                "name": tc.name,
                                "args": tc.arguments
                            ]
                        ]
                        if let sig = tc.thoughtSignature, !sig.isEmpty {
                            part["thoughtSignature"] = sig
                        }
                        parts.append(part)
                    }
                    if !parts.isEmpty {
                        rawContents.append(["role": "model", "parts": parts])
                    }
                case .toolResults(let results, let directive):
                    var parts: [[String: Any]] = []
                    for res in results {
                        parts.append([
                            "functionResponse": [
                                "name": res.name,
                                "response": [
                                    "result": res.output,
                                    "success": res.success
                                ]
                            ]
                        ])
                    }
                    if !directive.isEmpty {
                        parts.append(["text": directive])
                    }
                    if !parts.isEmpty {
                        rawContents.append(["role": "user", "parts": parts])
                    }
                }
            } else {
                let geminiRole = role == "assistant" ? "model" : "user"
                let cleanText = role == "assistant" ? AIStructuredTurnCodec.stripThoughtTags(trimmed) : trimmed
                guard !cleanText.isEmpty else { return }
                rawContents.append(["role": geminiRole, "parts": [["text": cleanText]]])
            }
        }
        
        for msg in conversationHistory {
            appendGeminiTurn(role: msg.role, content: msg.content)
        }
        
        var userParts: [[String: Any]] = []
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            if case .toolResults(let results, let directive) = AIStructuredTurnCodec.decode(trimmedPrompt) {
                for res in results {
                    userParts.append([
                        "functionResponse": [
                            "name": res.name,
                            "response": [
                                "result": res.output,
                                "success": res.success
                            ]
                        ]
                    ])
                }
                if !directive.isEmpty {
                    userParts.append(["text": directive])
                }
            } else {
                userParts.append(["text": trimmedPrompt])
            }
        }
        
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
        
        if userParts.isEmpty {
            userParts.append(["text": "Please continue."])
        }
        rawContents.append(["role": "user", "parts": userParts])
        
        // Coalesce consecutive messages with same role
        var coalesced: [[String: Any]] = []
        for item in rawContents {
            if let last = coalesced.last, (last["role"] as? String) == (item["role"] as? String) {
                var newLast = last
                var parts = (newLast["parts"] as? [[String: Any]]) ?? []
                let itemParts = (item["parts"] as? [[String: Any]]) ?? []
                parts.append(contentsOf: itemParts)
                newLast["parts"] = parts
                coalesced[coalesced.count - 1] = newLast
            } else {
                coalesced.append(item)
            }
        }
        
        if coalesced.first?["role"] as? String == "model" {
            coalesced.insert(["role": "user", "parts": [["text": "Begin."]]], at: 0)
        }
        
        body["contents"] = coalesced
        
        // Add tools for function calling (sanitize for Gemini API compatibility)
        if let tools = tools, !tools.isEmpty {
            let sanitized = tools.map { sanitizeToolSchemaForGemini($0) }
            body["tools"] = [["functionDeclarations": sanitized]]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let code = httpResponse.statusCode
            // Read error response body for detailed diagnostics
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 500 { break }
            }
            // Log to debug file
#if DEBUG
            let errDebug = "[\(Date())] AI ERROR \(code): \(errorBody.prefix(300))\n"
            print(errDebug)
#endif
            // Extract message from JSON error if possible
            var detailedMsg = "Gemini API error (\(code))"
            if let data = errorBody.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                detailedMsg = "(\(code)): \(message)"
            }
            NSLog("❌ [streamGemini] Error %d: %@ body=%@", code, detailedMsg, String(errorBody.prefix(300)))
            throw NSError(domain: "AIClient", code: code, userInfo: [NSLocalizedDescriptionKey: detailedMsg])
        }
        
        var isStreamingReasoning = false
        var latestUsageMetadata: [String: Any]?
        
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            
            // Capture latest token usage from Gemini usageMetadata (record once after stream completes)
            if let usage = json["usageMetadata"] as? [String: Any] {
                latestUsageMetadata = usage
            }
            
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { continue }
            
            for part in parts {
                let isThought = (part["thought"] as? Bool) ?? false
                if let text = part["text"] as? String {
                    if isThought {
                        if !isStreamingReasoning {
                            isStreamingReasoning = true
                            appendStreamToken("<thought>", onToken: onToken)
                        }
                        appendStreamToken(text, onToken: onToken)
                    } else {
                        if isStreamingReasoning {
                            isStreamingReasoning = false
                            appendStreamToken("</thought>\n\n", onToken: onToken)
                        }
                        appendStreamToken(text, onToken: onToken)
                    }
                    if detectStreamRepetitionLoop(currentStreamedText) {
                        NSLog("⚠️ [AIClient] Streaming repetition loop detected in streamGemini. Breaking stream.")
                        break
                    }
                } else if let fc = part["functionCall"] as? [String: Any],
                          let name = fc["name"] as? String {
                    if isStreamingReasoning {
                        isStreamingReasoning = false
                        appendStreamToken("</thought>\n\n", onToken: onToken)
                    }
                    let args = fc["args"] as? [String: Any] ?? [:]
                    let thoughtSig = part["thoughtSignature"] as? String
                    let toolCall = AIToolCall(id: UUID().uuidString, name: name, arguments: args, thoughtSignature: thoughtSig)
                    onToolCall?(toolCall)
                }
            }
        }
        
        if isStreamingReasoning {
            isStreamingReasoning = false
            appendStreamToken("</thought>\n\n", onToken: onToken)
        }
        
        // Record token usage once per stream to prevent multi-counting
        if let usage = latestUsageMetadata {
            let promptTok = usage["promptTokenCount"] as? Int ?? 0
            let completionTok = usage["candidatesTokenCount"] as? Int ?? 0
            let cachedTok = usage["cachedContentTokenCount"] as? Int ?? 0
            Task { @MainActor in
                AIUsageTracker.shared.record(
                    provider: "gemini",
                    model: model,
                    promptTokens: promptTok,
                    completionTokens: completionTok,
                    cachedTokens: cachedTok,
                    taskLabel: "Chat"
                )
            }
        }
    }
    
    // MARK: - Vision Model Detection
    
    private func isVisionCapableModel(_ model: String) -> Bool {
        let m = model.lowercased()
        if m.contains("gpt-4o") || m.contains("gpt-4-turbo") || m.contains("vision") ||
           m.contains("gemini") || m.contains("claude-3") || m.contains("omni") ||
           m.contains("llava") || m.contains("vl") || m.contains("4o") {
            return true
        }
        return false
    }
    
    // MARK: - OpenAI/DeepSeek Streaming
    
    private func streamOpenAI(prompt: String, attachments: [AIAttachment], systemPrompt: String?, conversationHistory: [(role: String, content: String)], model: String, apiKey: String, baseURL: String, tools: [[String: Any]]?, onToken: @escaping (String) -> Void, onToolCall: ((AIToolCall) -> Void)?) async throws {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL configuration for openai"])
        }
        
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let isCloudProxy = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == StreamableAIProvider.cloudProxyURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let isCopilot = baseURL.contains("githubcopilot.com")
        if isCloudProxy {
            request.setValue("microcode", forHTTPHeaderField: "X-Dotmini-Product")
            let dotminiLicense = UserDefaults.standard.string(forKey: "dotminiLicenseKey") ?? ""
            if !dotminiLicense.isEmpty {
                request.setValue(dotminiLicense, forHTTPHeaderField: "X-Dotmini-License")
            }
            let isJWT = apiKey.components(separatedBy: ".").count >= 3
            let isPlatformKey = apiKey.hasPrefix("sk-dotmini-") || apiKey.hasPrefix("mci-live-") || EnterpriseAIAuthService.shared.mode == .dotminiEnterprise
            if (isJWT || isPlatformKey) && !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        } else if isCopilot {
            let copilotToken = try await SubscriptionAuthManager.shared.getCopilotSessionToken(githubToken: apiKey)
            request.setValue("Bearer \(copilotToken)", forHTTPHeaderField: "Authorization")
            request.setValue("vscode/1.95.0", forHTTPHeaderField: "Editor-Version")
            request.setValue("copilot-chat/0.22.4", forHTTPHeaderField: "Editor-Plugin-Version")
            request.setValue("vscode-chat", forHTTPHeaderField: "Copilot-Integration-Id")
            request.setValue("github-copilot", forHTTPHeaderField: "Openai-Organization")
        } else {
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
        EnterpriseAIAuthService.shared.applyEnterpriseHeaders(to: &request)
        
        var messages: [[String: Any]] = []
        if let sys = systemPrompt, !sys.isEmpty { messages.append(["role": "system", "content": sys]) }
        
        var activeAssistantToolCallIds: Set<String> = []
        func appendOpenAITurn(role: String, content: String) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if let structured = AIStructuredTurnCodec.decode(trimmed) {
                switch structured {
                case .assistantToolCalls(let text, let toolCalls):
                    let cleanText = AIStructuredTurnCodec.stripThoughtTags(text)
                    var msgDict: [String: Any] = ["role": "assistant"]
                    if !cleanText.isEmpty {
                        msgDict["content"] = cleanText
                    } else {
                        msgDict["content"] = NSNull()
                    }
                    let tcArray: [[String: Any]] = toolCalls.map { tc in
                        let argsData = (try? JSONSerialization.data(withJSONObject: tc.arguments)) ?? Data("{}".utf8)
                        let argsStr = String(data: argsData, encoding: .utf8) ?? "{}"
                        return [
                            "id": tc.id,
                            "type": "function",
                            "function": [
                                "name": tc.name,
                                "arguments": argsStr
                            ]
                        ]
                    }
                    if !tcArray.isEmpty {
                        msgDict["tool_calls"] = tcArray
                    }
                    messages.append(msgDict)
                    activeAssistantToolCallIds = Set(toolCalls.map { $0.id })
                case .toolResults(let results, let directive):
                    var unmatchedOutputs: [String] = []
                    for res in results {
                        if activeAssistantToolCallIds.contains(res.toolCallId) {
                            messages.append([
                                "role": "tool",
                                "tool_call_id": res.toolCallId,
                                "content": res.output
                            ])
                        } else {
                            unmatchedOutputs.append("[\(res.name)]: \(res.output)")
                        }
                    }
                    activeAssistantToolCallIds.removeAll()
                    let combinedDirective = (unmatchedOutputs + (directive.isEmpty ? [] : [directive])).joined(separator: "\n\n")
                    if !combinedDirective.isEmpty {
                        messages.append(["role": "user", "content": combinedDirective])
                    }
                }
            } else {
                activeAssistantToolCallIds.removeAll()
                let cleanText = role == "assistant" ? AIStructuredTurnCodec.stripThoughtTags(trimmed) : trimmed
                guard !cleanText.isEmpty else { return }
                messages.append(["role": role, "content": cleanText])
            }
        }
        
        for msg in conversationHistory {
            appendOpenAITurn(role: msg.role, content: msg.content)
        }
        
        if attachments.isEmpty {
            let safePrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Continue." : prompt
            appendOpenAITurn(role: "user", content: safePrompt)
        } else {
            activeAssistantToolCallIds.removeAll()
            var contentArray: [[String: Any]] = [["type": "text", "text": prompt.isEmpty ? "Analyze attachment." : prompt]]
            let isVision = isVisionCapableModel(model)
            
            for attachment in attachments {
                switch attachment.type {
                case .image(let format):
                    // 1. Run local Apple Neural Engine OCR & Vision extraction
                    let visionResult = await AppleVisionEngine.shared.analyzeImage(data: attachment.data, filename: attachment.name)
                    
                    if isVision {
                        // Send native image_url to vision-capable models
                        contentArray.append(["type": "image_url", "image_url": ["url": "data:image/\(format);base64,\(attachment.base64String)"]])
                        if !visionResult.extractedText.isEmpty {
                            contentArray.append(["type": "text", "text": "\n[Apple Neural Vision OCR Aid]:\n\(visionResult.extractedText)\n"])
                        }
                    } else {
                        // Text-only LLM bridge: Provide full structural vision & OCR breakdown
                        contentArray.append(["type": "text", "text": "\n\(visionResult.formattedSummary)\n"])
                    }
                case .text:
                    if let text = attachment.textContent { contentArray.append(["type": "text", "text": "\n[File: \(attachment.name)]\n\(text)\n"]) }
                case .pdf:
                    let pdfText = attachment.pdfExtractedText
                    let preview = pdfText.isEmpty ? "[Empty or Scanned PDF]" : pdfText
                    contentArray.append(["type": "text", "text": "\n[Document: \(attachment.name) (\(attachment.pdfPageCount) pages)]\n\(preview)\n[/Document]\n"])
                }
            }
            messages.append(["role": "user", "content": contentArray])
        }
        
        let effectiveModel = normalizeModelName(model, provider: StreamableAIProvider.detect(from: model), baseURL: baseURL)
        let isReasoning = effectiveModel.hasPrefix("o1") || effectiveModel.hasPrefix("o3") || effectiveModel.hasPrefix("o4")
        var body: [String: Any] = [
            "model": effectiveModel,
            "messages": messages,
            "stream": true
        ]
        if isReasoning {
            body["max_completion_tokens"] = maxOutputTokens(for: effectiveModel)
        } else {
            body["temperature"] = 0.7
            body["max_tokens"] = maxOutputTokens(for: effectiveModel)
        }
        
        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools.map { ["type": "function", "function": $0] as [String: Any] }
        }
        
        // Enable usage reporting in stream responses
        body["stream_options"] = ["include_usage": true]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            var errText = ""
            for try await l in bytes.lines {
                errText += l
                if errText.count > 500 { break }
            }
            var parsedMsg: String? = nil
            if let data = errText.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let msg = err["message"] as? String {
                parsedMsg = msg
            }
            let customMsg = parseErrorMessage(NSError(domain: "AIClient", code: code, userInfo: nil))
            let finalMsg = parsedMsg ?? customMsg
            print("[AIClient] HTTP \(code) error from \(url.absoluteString): \(finalMsg)")
            throw NSError(domain: "AIClient", code: code, userInfo: [NSLocalizedDescriptionKey: finalMsg])
        }
        
        // Buffer for streaming tool calls (keyed by integer index for deterministic order)
        var toolCallBuffers: [Int: (id: String, name: String, args: String)] = [:]
        var isStreamingReasoning = false
        
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: "), line != "data: [DONE]" else { continue }
            let jsonString = String(line.dropFirst(6))
            
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            
            // Capture token usage from final stream chunk (OpenAI/DeepSeek/Grok/Qwen/GLM)
            if let usage = json["usage"] as? [String: Any] {
                let promptTok = usage["prompt_tokens"] as? Int ?? 0
                let completionTok = usage["completion_tokens"] as? Int ?? 0
                let cachedTok = (usage["prompt_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int ?? 0
                Task { @MainActor in
                    AIUsageTracker.shared.record(
                        provider: StreamableAIProvider.detect(from: model).rawValue,
                        model: model,
                        promptTokens: promptTok,
                        completionTokens: completionTok,
                        cachedTokens: cachedTok,
                        taskLabel: "Chat"
                    )
                }
            }
            
            guard let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else { continue }
            
            // Reasoning tokens (DeepSeek R1 / thinking models / GLM)
            if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                if !isStreamingReasoning {
                    isStreamingReasoning = true
                    appendStreamToken("<thought>", onToken: onToken)
                }
                appendStreamToken(reasoning, onToken: onToken)
            } else if let content = delta["content"] as? String {
                if isStreamingReasoning {
                    isStreamingReasoning = false
                    appendStreamToken("</thought>\n\n", onToken: onToken)
                }
                appendStreamToken(content, onToken: onToken)
            }
            
            if detectStreamRepetitionLoop(currentStreamedText) {
                NSLog("⚠️ [AIClient] Streaming repetition loop detected in streamOpenAI. Breaking stream.")
                break
            }
            
            // Tool calls (streamed incrementally)
            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                for tc in toolCalls {
                    let idx = tc["index"] as? Int ?? 0
                    var entry = toolCallBuffers[idx] ?? (id: UUID().uuidString, name: "", args: "")
                    if let tcId = tc["id"] as? String, !tcId.isEmpty {
                        entry.id = tcId
                    }
                    if let function = tc["function"] as? [String: Any] {
                        if let name = function["name"] as? String, !name.isEmpty {
                            entry.name = name
                        }
                        if let argChunk = function["arguments"] as? String, !argChunk.isEmpty {
                            entry.args.append(argChunk)
                        }
                    }
                    toolCallBuffers[idx] = entry
                }
            }
            
            // Check finish reason
            if let finishReason = choices.first?["finish_reason"] as? String, finishReason == "tool_calls" {
                for idx in toolCallBuffers.keys.sorted() {
                    guard let buffer = toolCallBuffers[idx], !buffer.name.isEmpty else { continue }
                    let args = (try? JSONSerialization.jsonObject(with: Data(buffer.args.utf8))) as? [String: Any] ?? [:]
                    let toolCall = AIToolCall(id: buffer.id, name: buffer.name, arguments: args)
                    onToolCall?(toolCall)
                }
                toolCallBuffers.removeAll()
            }
        }
        
        if isStreamingReasoning {
            isStreamingReasoning = false
            appendStreamToken("</thought>\n\n", onToken: onToken)
        }
        
        // Flush any remaining buffered tool calls (e.g. if provider sent finish_reason: "stop" or nil)
        if !toolCallBuffers.isEmpty {
            for idx in toolCallBuffers.keys.sorted() {
                guard let buffer = toolCallBuffers[idx], !buffer.name.isEmpty else { continue }
                let args = (try? JSONSerialization.jsonObject(with: Data(buffer.args.utf8))) as? [String: Any] ?? [:]
                let toolCall = AIToolCall(id: buffer.id, name: buffer.name, arguments: args)
                onToolCall?(toolCall)
            }
            toolCallBuffers.removeAll()
        }
    }
    
    // MARK: - Anthropic Streaming
    
    private func streamAnthropic(prompt: String, attachments: [AIAttachment], systemPrompt: String?, conversationHistory: [(role: String, content: String)], model: String, apiKey: String, tools: [[String: Any]]?, onToken: @escaping (String) -> Void, onToolCall: ((AIToolCall) -> Void)?) async throws {
        let baseURL = StreamableAIProvider.anthropic.directBaseURL
        guard let url = URL(string: "\(baseURL)/messages") else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL configuration for anthropic"])
        }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") // Required for Dotmini Proxy Auth
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        var allMessages: [[String: Any]] = []
        var activeAnthropicToolUseIds: Set<String> = []
        
        func appendAnthropicBlocks(role: String, blocks: [[String: Any]]) {
            guard !blocks.isEmpty else { return }
            if let last = allMessages.last, (last["role"] as? String) == role {
                var existingBlocks: [[String: Any]] = []
                if let lastArr = last["content"] as? [[String: Any]] {
                    existingBlocks = lastArr
                } else if let lastStr = last["content"] as? String, !lastStr.isEmpty {
                    existingBlocks = [["type": "text", "text": lastStr]]
                }
                existingBlocks.append(contentsOf: blocks)
                allMessages[allMessages.count - 1] = ["role": role, "content": existingBlocks]
            } else {
                allMessages.append(["role": role, "content": blocks])
            }
        }
        
        func appendAnthropicTurn(role: String, content: String) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let normalizedRole = role == "assistant" ? "assistant" : "user"
            if let structured = AIStructuredTurnCodec.decode(trimmed) {
                switch structured {
                case .assistantToolCalls(let text, let toolCalls):
                    var blocks: [[String: Any]] = []
                    let cleanText = AIStructuredTurnCodec.stripThoughtTags(text)
                    if !cleanText.isEmpty {
                        blocks.append(["type": "text", "text": cleanText])
                    }
                    for tc in toolCalls {
                        blocks.append([
                            "type": "tool_use",
                            "id": tc.id,
                            "name": tc.name,
                            "input": tc.arguments
                        ])
                    }
                    appendAnthropicBlocks(role: "assistant", blocks: blocks)
                    activeAnthropicToolUseIds = Set(toolCalls.map { $0.id })
                case .toolResults(let results, let directive):
                    var blocks: [[String: Any]] = []
                    for res in results {
                        if activeAnthropicToolUseIds.contains(res.toolCallId) {
                            blocks.append([
                                "type": "tool_result",
                                "tool_use_id": res.toolCallId,
                                "content": res.output,
                                "is_error": !res.success
                            ])
                        } else {
                            blocks.append([
                                "type": "text",
                                "text": "[\(res.name) result]:\n\(res.output)"
                            ])
                        }
                    }
                    activeAnthropicToolUseIds.removeAll()
                    if !directive.isEmpty {
                        blocks.append(["type": "text", "text": directive])
                    }
                    appendAnthropicBlocks(role: "user", blocks: blocks)
                }
            } else {
                activeAnthropicToolUseIds.removeAll()
                let cleanText = normalizedRole == "assistant" ? AIStructuredTurnCodec.stripThoughtTags(trimmed) : trimmed
                guard !cleanText.isEmpty else { return }
                appendAnthropicBlocks(role: normalizedRole, blocks: [["type": "text", "text": cleanText]])
            }
        }
        
        for msg in conversationHistory {
            appendAnthropicTurn(role: msg.role, content: msg.content)
        }
        if allMessages.first?["role"] as? String == "assistant" {
            allMessages.insert(["role": "user", "content": [["type": "text", "text": "Please begin."]]], at: 0)
        }
        
        var messageContent: [[String: Any]] = []
        let isVision = isVisionCapableModel(model)
        
        for attachment in attachments {
            if case .image(let format) = attachment.type {
                let visionResult = await AppleVisionEngine.shared.analyzeImage(data: attachment.data, filename: attachment.name)
                if isVision {
                    messageContent.append(["type": "image", "source": ["type": "base64", "media_type": "image/\(format)", "data": attachment.base64String]])
                    if !visionResult.extractedText.isEmpty {
                        messageContent.append(["type": "text", "text": "[Apple Neural Vision OCR Aid]:\n\(visionResult.extractedText)"])
                    }
                } else {
                    messageContent.append(["type": "text", "text": visionResult.formattedSummary])
                }
            } else if case .pdf = attachment.type {
                let pdfText = attachment.pdfExtractedText
                let preview = pdfText.isEmpty ? "[Empty or Scanned PDF]" : pdfText
                messageContent.append(["type": "text", "text": "Document: \(attachment.name) (\(attachment.pdfPageCount) pages)\n\(preview)\n"])
            } else if case .text = attachment.type, let text = attachment.textContent {
                messageContent.append(["type": "text", "text": "File: \(attachment.name)\n\(text)"])
            }
        }
        let safePrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Continue." : prompt
        if !messageContent.isEmpty {
            appendAnthropicBlocks(role: "user", blocks: messageContent)
        }
        appendAnthropicTurn(role: "user", content: safePrompt)
        
        // Anthropic Multi-Turn Prompt Caching: mark the last block of the latest user turn as ephemeral
        if let lastUserIdx = allMessages.lastIndex(where: { ($0["role"] as? String) == "user" }),
           var userBlocks = allMessages[lastUserIdx]["content"] as? [[String: Any]],
           !userBlocks.isEmpty {
            var lastBlock = userBlocks[userBlocks.count - 1]
            lastBlock["cache_control"] = ["type": "ephemeral"]
            userBlocks[userBlocks.count - 1] = lastBlock
            allMessages[lastUserIdx]["content"] = userBlocks
        }
        
        var body: [String: Any] = ["model": model, "max_tokens": maxOutputTokens(for: model), "stream": true, "messages": allMessages]
        
        // Anthropic Prompt Caching on System Prompt
        if let sys = systemPrompt, !sys.isEmpty {
            body["system"] = [
                [
                    "type": "text",
                    "text": sys,
                    "cache_control": ["type": "ephemeral"]
                ]
            ]
        }
        
        // Anthropic Tools with Prompt Caching on last tool
        if let tools = tools, !tools.isEmpty {
            var formattedTools: [[String: Any]] = []
            for (idx, tool) in tools.enumerated() {
                var toolDict: [String: Any] = [
                    "name": tool["name"] ?? "",
                    "description": tool["description"] ?? "",
                    "input_schema": tool["parameters"] ?? [:]
                ]
                if idx == tools.count - 1 {
                    toolDict["cache_control"] = ["type": "ephemeral"]
                }
                formattedTools.append(toolDict)
            }
            body["tools"] = formattedTools
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let customMsg = parseErrorMessage(NSError(domain: "AIClient", code: code, userInfo: nil))
            let finalMsg = customMsg == "The operation couldn’t be completed. (AIClient error \(code).)" ? "Anthropic API error (\(code))" : customMsg
            throw NSError(domain: "AIClient", code: code, userInfo: [NSLocalizedDescriptionKey: finalMsg])
        }
        
        var currentToolName = ""
        var currentToolArgs = ""
        var currentToolId = ""
        var anthropicInputTokens = 0
        var anthropicCachedTokens = 0
        
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
                        appendStreamToken(text, onToken: onToken)
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
                    onToolCall?(toolCall)
                    currentToolName = ""
                    currentToolArgs = ""
                }
            case "message_start":
                // Capture input token usage from Anthropic
                if let message = json["message"] as? [String: Any],
                   let usage = message["usage"] as? [String: Any] {
                    let inputTok = usage["input_tokens"] as? Int ?? 0
                    let cachedTok = usage["cache_read_input_tokens"] as? Int ?? 0
                    // Store for later combination with output tokens
                    anthropicInputTokens = inputTok
                    anthropicCachedTokens = cachedTok
                }
            case "message_delta":
                // Capture output token usage from Anthropic
                if let usage = json["usage"] as? [String: Any] {
                    let outputTok = usage["output_tokens"] as? Int ?? 0
                    Task { @MainActor in
                        AIUsageTracker.shared.record(
                            provider: "anthropic",
                            model: model,
                            promptTokens: anthropicInputTokens,
                            completionTokens: outputTok,
                            cachedTokens: anthropicCachedTokens,
                            taskLabel: "Chat"
                        )
                    }
                }
            default:
                break
            }
        }
    }
    
    // MARK: - Sync Helpers (Non-streaming for Agent loops)
    
    private func syncGemini(messages: [[(String, Any)]], systemPrompt: String?, model: String, apiKey: String, tools: [[String: Any]]?) async throws -> (text: String, toolCalls: [AIToolCall]) {
        let baseURL = StreamableAIProvider.gemini.directBaseURL
        let normalizedModel = normalizeModelName(model, provider: .gemini, baseURL: baseURL)
        let cleanModel = normalizedModel.hasPrefix("models/") ? String(normalizedModel.dropFirst(7)) : normalizedModel
        let isVertexEnterprise = EnterpriseAIAuthService.shared.mode == .geminiVertex
        
        let url: URL
        if isVertexEnterprise, let vertexURL = EnterpriseAIAuthService.shared.buildVertexGeminiURL(model: cleanModel, streaming: false) {
            url = vertexURL
        } else if let directURL = URL(string: "\(baseURL)/models/\(cleanModel):generateContent?key=\(apiKey)") {
            url = directURL
        } else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL configuration for gemini"])
        }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if isVertexEnterprise {
            if let authHeader = try await EnterpriseAIAuthService.shared.resolveVertexAuthorizationHeader() {
                request.setValue(authHeader, forHTTPHeaderField: "Authorization")
            }
            if !EnterpriseAIAuthService.shared.vertexProjectId.isEmpty {
                request.setValue(EnterpriseAIAuthService.shared.vertexProjectId, forHTTPHeaderField: "x-goog-user-project")
            }
        }
        EnterpriseAIAuthService.shared.applyEnterpriseHeaders(to: &request)
        
        var body: [String: Any] = [
            "generationConfig": ["temperature": 0.7, "maxOutputTokens": maxOutputTokens(for: cleanModel)]
        ]
        
        // Native system instruction
        if let sys = systemPrompt, !sys.isEmpty {
            body["systemInstruction"] = ["parts": [["text": sys]]]
        }
        
        // Build contents properly from messages array
        var rawContents: [[String: Any]] = []
        for msg in messages {
            let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
            let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let geminiRole = role == "assistant" ? "model" : "user"
            rawContents.append(["role": geminiRole, "parts": [["text": trimmed]]])
        }
        
        // Coalesce consecutive messages with the same role (Gemini strict requirement)
        var coalesced: [[String: Any]] = []
        for item in rawContents {
            if let last = coalesced.last, (last["role"] as? String) == (item["role"] as? String) {
                var newLast = last
                var parts = (newLast["parts"] as? [[String: Any]]) ?? []
                let itemParts = (item["parts"] as? [[String: Any]]) ?? []
                parts.append(contentsOf: itemParts)
                newLast["parts"] = parts
                coalesced[coalesced.count - 1] = newLast
            } else {
                coalesced.append(item)
            }
        }
        
        // Ensure at least one message and first message is user
        if coalesced.isEmpty {
            coalesced.append(["role": "user", "parts": [["text": "Continue with the task."]]])
        } else if coalesced.first?["role"] as? String == "model" {
            coalesced.insert(["role": "user", "parts": [["text": "Please begin."]]], at: 0)
        }
        body["contents"] = coalesced
        
        if let tools = tools, !tools.isEmpty {
            let sanitized = tools.map { sanitizeToolSchemaForGemini($0) }
            body["tools"] = [["functionDeclarations": sanitized]]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            var detailedMsg = "Gemini API error (\(code))"
            if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errObj = errJson["error"] as? [String: Any],
               let msg = errObj["message"] as? String {
                detailedMsg = "(\(code)): \(msg)"
            }
            NSLog("❌ [syncGemini] Error %d: %@", code, detailedMsg)
            throw NSError(domain: "AIClient", code: code, userInfo: [NSLocalizedDescriptionKey: detailedMsg])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (text: "", toolCalls: [])
        }
        
        if let usage = json["usageMetadata"] as? [String: Any] {
            let promptTok = usage["promptTokenCount"] as? Int ?? 0
            let completionTok = usage["candidatesTokenCount"] as? Int ?? 0
            let cachedTok = usage["cachedContentTokenCount"] as? Int ?? 0
            Task { @MainActor in
                AIUsageTracker.shared.record(
                    provider: "gemini",
                    model: model,
                    promptTokens: promptTok,
                    completionTokens: completionTok,
                    cachedTokens: cachedTok,
                    taskLabel: "Chat"
                )
            }
        }
        
        guard let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return (text: "", toolCalls: [])
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
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL configuration for openai"])
        }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let isCloudProxy = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == StreamableAIProvider.cloudProxyURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let isCopilot = baseURL.contains("githubcopilot.com")
        if isCloudProxy {
            request.setValue("microcode", forHTTPHeaderField: "X-Dotmini-Product")
            let dotminiLicense = UserDefaults.standard.string(forKey: "dotminiLicenseKey") ?? ""
            if !dotminiLicense.isEmpty {
                request.setValue(dotminiLicense, forHTTPHeaderField: "X-Dotmini-License")
            }
            let isJWT = apiKey.components(separatedBy: ".").count >= 3
            let isPlatformKey = apiKey.hasPrefix("sk-dotmini-") || apiKey.hasPrefix("mci-live-") || EnterpriseAIAuthService.shared.mode == .dotminiEnterprise
            if (isJWT || isPlatformKey) && !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        } else if isCopilot {
            let copilotToken = try await SubscriptionAuthManager.shared.getCopilotSessionToken(githubToken: apiKey)
            request.setValue("Bearer \(copilotToken)", forHTTPHeaderField: "Authorization")
            request.setValue("vscode/1.95.0", forHTTPHeaderField: "Editor-Version")
            request.setValue("copilot-chat/0.22.4", forHTTPHeaderField: "Editor-Plugin-Version")
            request.setValue("vscode-chat", forHTTPHeaderField: "Copilot-Integration-Id")
            request.setValue("github-copilot", forHTTPHeaderField: "Openai-Organization")
        } else {
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
        EnterpriseAIAuthService.shared.applyEnterpriseHeaders(to: &request)
        
        var apiMessages: [[String: Any]] = []
        if let sys = systemPrompt, !sys.isEmpty { apiMessages.append(["role": "system", "content": sys]) }
        for msg in messages {
            let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
            let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            apiMessages.append(["role": role, "content": trimmed])
        }
        if apiMessages.isEmpty || (apiMessages.count == 1 && (apiMessages.first?["role"] as? String) == "system") {
            apiMessages.append(["role": "user", "content": "Continue with the task."])
        }
        
        let isReasoning = model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4")
        var body: [String: Any] = [
            "model": model,
            "messages": apiMessages
        ]
        if isReasoning {
            body["max_completion_tokens"] = maxOutputTokens(for: model)
        } else {
            body["temperature"] = 0.7
            body["max_tokens"] = maxOutputTokens(for: model)
        }
        if let tools = tools, !tools.isEmpty { body["tools"] = tools.map { ["type": "function", "function": $0] as [String: Any] } }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response from server"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText: String
            if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errObj = errJson["error"] as? [String: Any],
               let msg = errObj["message"] as? String {
                errorText = msg
            } else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                errorText = raw.isEmpty ? "HTTP status \(httpResponse.statusCode)" : raw
            }
            throw NSError(domain: "AIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API error (\(httpResponse.statusCode)): \(errorText)"])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            return (text: "Error: Unable to parse response from \(baseURL) (\(raw.prefix(200)))", toolCalls: [])
        }
        
        if let usage = json["usage"] as? [String: Any] {
            let promptTok = usage["prompt_tokens"] as? Int ?? 0
            let completionTok = usage["completion_tokens"] as? Int ?? 0
            let cachedTok = (usage["prompt_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int ?? 0
            Task { @MainActor in
                AIUsageTracker.shared.record(
                    provider: StreamableAIProvider.detect(from: model).rawValue,
                    model: model,
                    promptTokens: promptTok,
                    completionTokens: completionTok,
                    cachedTokens: cachedTok,
                    taskLabel: "Chat"
                )
            }
        }
        
        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            return (text: "Error: Unable to parse response from \(baseURL) (\(raw.prefix(200)))", toolCalls: [])
        }
        
        let content = message["content"] as? String ?? ""
        let reasoning = message["reasoning_content"] as? String ?? ""
        let text: String
        if !reasoning.isEmpty && !content.isEmpty {
            text = "<thought>\(reasoning)</thought>\n\n\(content)"
        } else if !reasoning.isEmpty {
            text = "<thought>\(reasoning)</thought>"
        } else {
            text = content
        }
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
        let baseURL = StreamableAIProvider.anthropic.directBaseURL
        guard let url = URL(string: "\(baseURL)/messages") else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL configuration for anthropic"])
        }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") // Required for Dotmini Proxy Auth
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        var apiMessages: [[String: Any]] = []
        for msg in messages {
            let rawRole = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
            let role = rawRole == "assistant" ? "assistant" : "user"
            let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let last = apiMessages.last, (last["role"] as? String) == role, let lastText = last["content"] as? String {
                apiMessages[apiMessages.count - 1] = ["role": role, "content": lastText + "\n\n" + trimmed]
            } else {
                apiMessages.append(["role": role, "content": trimmed])
            }
        }
        if apiMessages.isEmpty {
            apiMessages.append(["role": "user", "content": "Continue with the task."])
        } else if apiMessages.first?["role"] as? String == "assistant" {
            apiMessages.insert(["role": "user", "content": "Please begin."], at: 0)
        }
        
        var body: [String: Any] = ["model": model, "max_tokens": maxOutputTokens(for: model), "messages": apiMessages]
        
        // Anthropic Prompt Caching on System Prompt
        if let sys = systemPrompt, !sys.isEmpty {
            body["system"] = [
                [
                    "type": "text",
                    "text": sys,
                    "cache_control": ["type": "ephemeral"]
                ]
            ]
        }
        
        // Inject tools with Prompt Caching on the last tool
        if let tools = tools, !tools.isEmpty {
            var formattedTools: [[String: Any]] = []
            for (idx, tool) in tools.enumerated() {
                var toolDict: [String: Any] = [
                    "name": tool["name"] ?? "",
                    "description": tool["description"] ?? "",
                    "input_schema": tool["parameters"] ?? [:]
                ]
                if idx == tools.count - 1 {
                    toolDict["cache_control"] = ["type": "ephemeral"]
                }
                formattedTools.append(toolDict)
            }
            body["tools"] = formattedTools
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response from server"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText: String
            if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errObj = errJson["error"] as? [String: Any],
               let msg = errObj["message"] as? String {
                errorText = msg
            } else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                errorText = raw.isEmpty ? "HTTP status \(httpResponse.statusCode)" : raw
            }
            throw NSError(domain: "AIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API error (\(httpResponse.statusCode)): \(errorText)"])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            return (text: "Error: Unable to parse response (\(raw.prefix(200)))", toolCalls: [])
        }
        
        if let usage = json["usage"] as? [String: Any] {
            let inputTok = usage["input_tokens"] as? Int ?? 0
            let outputTok = usage["output_tokens"] as? Int ?? 0
            let cachedTok = usage["cache_read_input_tokens"] as? Int ?? 0
            Task { @MainActor in
                AIUsageTracker.shared.record(
                    provider: "anthropic",
                    model: model,
                    promptTokens: inputTok,
                    completionTokens: outputTok,
                    cachedTokens: cachedTok,
                    taskLabel: "Chat"
                )
            }
        }
        
        guard let content = json["content"] as? [[String: Any]] else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            return (text: "Error: Unable to parse response (\(raw.prefix(200)))", toolCalls: [])
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

// MARK: - Stream Completion Extension

extension AIClient {
    /// Stream completion using AsyncThrowingStream for modern async/await callers.
    /// Canonical implementation — used by all Phase 2 killer feature services.
    public func streamCompletion(
        messages: [(role: String, content: String)],
        model: String? = nil,
        provider: String? = nil,
        tools: [[String: Any]]? = nil,
        stream: Bool = true,
        onToolCall: ((AIToolCall) -> Void)? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        let configuredModel = UserDefaults.standard.string(forKey: "aiModel") ?? StreamableAIProvider.omni.defaultModel
        let requestedModel = model ?? configuredModel
        let configuredProvider = provider ?? UserDefaults.standard.string(forKey: "aiProvider") ?? "omni"

        let selection = AIModelCatalog.shared.normalizedSelection(provider: configuredProvider, model: requestedModel)
        let resolvedModel = selection.model
        let resolvedProvider = StreamableAIProvider(rawValue: selection.provider) ?? StreamableAIProvider.detect(from: resolvedModel)

        let apiKey = UserDefaults.standard.string(forKey: "\(resolvedProvider.rawValue)_api_key")
            ?? UserDefaults.standard.string(forKey: "apiKey") ?? ""

        let systemPrompt = messages.first(where: { $0.role == "system" })?.content
        let conversationMessages = messages.filter { $0.role != "system" }
        let prompt = conversationMessages.last?.content ?? "Proceed."
        let history = conversationMessages.dropLast().map { (role: $0.role, content: $0.content) }

        return AsyncThrowingStream<String, Error> { continuation in
            AIClient.shared.sendMessage(
                prompt: prompt,
                systemPrompt: systemPrompt,
                conversationHistory: Array(history),
                provider: resolvedProvider,
                model: resolvedModel,
                apiKey: apiKey,
                tools: tools,
                onToken: { token in
                    continuation.yield(token)
                },
                onToolCall: { toolCall in
                    onToolCall?(toolCall)
                },
                onComplete: { _ in
                    continuation.finish()
                },
                onError: { err in
                    continuation.finish(throwing: NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: err]))
                }
            )
        }
    }

    /// Convenience text generation helper for prompt-response queries
    public func generateText(prompt: String, systemPrompt: String? = nil) async throws -> String {
        let stream = try await streamCompletion(
            messages: [
                (role: "system", content: systemPrompt ?? "You are an expert programming assistant."),
                (role: "user", content: prompt)
            ],
            stream: false
        )
        var result = ""
        for try await chunk in stream {
            result += chunk
        }
        return result
    }
}
