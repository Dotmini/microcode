//
//  AIClient.swift
//  MicroCode
//
//  Production AI API Client with Streaming + Function Calling
//  Supports: Gemini, OpenAI, Anthropic, DeepSeek
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
        switch self {
        case .omni: return "gpt-6-astra"
        case .anthropic: return "claude-3-7-sonnet"
        case .openai: return "gpt-6-astra"
        case .gemini: return "gemini-2.5-pro"
        case .deepseek: return "deepseek-v4-flash"
        case .qwen: return "qwen/qwen-2.5-coder-32b-instruct"
        case .grok: return "grok-3"
        case .glm: return "glm-4-plus"
        case .copilot: return "claude-3-7-sonnet"
        case .local: return LocalLLMService.cachedModel
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
        let candidate = trimmed.isEmpty ? provider.defaultModel : trimmed
        let lower = candidate.lowercased()
        
        if provider == .deepseek {
            if lower == "deepseek" || lower.isEmpty {
                return "deepseek-v4-flash"
            }
            if lower.contains("reasoner") || lower.contains("r1") {
                return "deepseek-reasoner"
            }
            return candidate
        } else if provider == .gemini {
            if lower == "gemini" || lower.isEmpty {
                return "gemini-2.5-pro"
            }
            return candidate
        }
        return candidate
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
        // Determine key mode: "cloud" (Dotmini proxy) vs "direct" (user's own key)
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "cloud"
        let actualKey: String
        let baseURL: String
        
        if provider == .local {
            actualKey = ""
            baseURL = provider.directBaseURL
            
        } else if keyMode == "subscription" {
            // ━━━ SUBSCRIPTION MODE ━━━
            // Uses ONLY tokens from SubscriptionAuthManager (CLI detection / manual input)
            // Routes directly to provider APIs — no cloud proxy, no BYOK mixing
            let subToken = resolveSubscriptionToken(for: provider)
            let account = resolveSubscriptionAccount(for: provider)
            
            if !subToken.isEmpty {
                actualKey = subToken
                // CLI tokens and manually entered keys go directly to the provider
                let isCLIToken = account?.source == "Manual"
                let isManualInput = account?.source == "Manual Input"
                let isRealAPIKey = subToken.hasPrefix("sk-") || subToken.hasPrefix("AIzaSy") || subToken.hasPrefix("gsk_")
                if isCLIToken || isManualInput || isRealAPIKey {
                    baseURL = provider.directBaseURL
                } else {
                    // Web session tokens → route through cloud proxy for translation
                    baseURL = provider.cloudBaseURL
                }
            } else {
                actualKey = ""
                baseURL = provider.directBaseURL
            }
            
        } else if keyMode == "direct" {
            // ━━━ BYOK (DIRECT) MODE ━━━
            // Uses ONLY user's own API keys — no cloud proxy, no subscription
            let specificKey = UserDefaults.standard.string(forKey: "\(provider.rawValue)_api_key") ?? ""
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
            // Uses ONLY Dotmini platform credentials — no BYOK, no subscription
            let microToken = DotminiPlatformKeyService.shared.authorizationToken
                ?? SupabaseAuthService.shared.accessToken ?? ""
            actualKey = microToken
            baseURL = provider.cloudBaseURL
        }
        
        // DEBUG: Log key resolution (remove after debugging)
        let keyPreview = actualKey.isEmpty ? "(empty)" : String(actualKey.prefix(12)) + "..."
        NSLog("🔑 [AIClient.sendMessage] mode=%@ provider=%@ key=%@ url=%@", keyMode, provider.rawValue, keyPreview, baseURL)
        
        if actualKey.isEmpty && provider != .local && provider != .omni {
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

        if keyMode == "subscription" && actualKey.hasPrefix("ghp_") && provider == .openai {
            onError("GitHub Personal Access Token (ghp_...) cannot be used directly as an OpenAI API key. Please switch to Direct API Key (BYOK) mode or configure an OpenAI API key in Settings.")
            return
        }
        
        isStreaming = true
        currentStreamedText = ""
        pendingStreamTokens = ""
        lastStreamDeliveryUptime = 0
        
        let trimmedHistory = boundedHistory(conversationHistory)
        let resolvedModel = normalizeModelName(model, provider: provider, baseURL: baseURL)
        
        streamTask = Task {
            let requestKey: String
            if keyMode == "cloud" && baseURL == provider.cloudBaseURL && provider != .local {
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
            let maxRetries = 2
            
            while retryCount <= maxRetries {
                do {
                    if baseURL == provider.cloudBaseURL {
                        // All cloud-routed requests (Dotmini Cloud or Web Subscriptions) use OpenAI-compatible gateway
                        try await streamOpenAI(prompt: prompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, apiKey: requestKey, baseURL: baseURL, tools: tools, onToken: onToken, onToolCall: onToolCall)
                    } else {
                        // Direct / BYOK mode: use native protocols where necessary
                        switch provider {
                        case .gemini:
                            let lower = resolvedModel.lowercased()
                            if !lower.contains("gemini") && !lower.contains("gemma") {
                                let fallback = StreamableAIProvider.detect(from: resolvedModel)
                                if fallback != .gemini {
                                    try await streamOpenAI(prompt: prompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, apiKey: actualKey, baseURL: fallback.directBaseURL, tools: tools, onToken: onToken, onToolCall: onToolCall)
                                } else {
                                    try await streamGemini(prompt: prompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, apiKey: actualKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                                }
                            } else {
                                try await streamGemini(prompt: prompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, apiKey: actualKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                            }
                        case .anthropic:
                            try await streamAnthropic(prompt: prompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, apiKey: actualKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                        case .omni, .openai, .deepseek, .grok, .qwen, .glm, .copilot, .local:
                            try await streamOpenAI(prompt: prompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, apiKey: actualKey, baseURL: baseURL, tools: tools, onToken: onToken, onToolCall: onToolCall)
                        }
                    }
                    
                    self.flushPendingStreamTokens(onToken: onToken)
                    onComplete(self.currentStreamedText)
                    self.isStreaming = false
                    return // Success
                    
                } catch let error as NSError {
                    // Retry on transient errors (429, 503)
                    if (error.code == 429 || error.code == 503) && retryCount < maxRetries {
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
            
        } else if keyMode == "subscription" {
            // ━━━ SUBSCRIPTION MODE ━━━
            let subToken = resolveSubscriptionToken(for: provider)
            let account = resolveSubscriptionAccount(for: provider)
            
            if !subToken.isEmpty {
                actualKey = subToken
                let isCLIToken = account?.source == "Manual"
                let isManualInput = account?.source == "Manual Input"
                let isRealAPIKey = subToken.hasPrefix("sk-") || subToken.hasPrefix("AIzaSy") || subToken.hasPrefix("gsk_")
                if isCLIToken || isManualInput || isRealAPIKey {
                    baseURL = provider.directBaseURL
                } else {
                    baseURL = provider.cloudBaseURL
                }
            } else {
                actualKey = ""
                baseURL = provider.directBaseURL
            }
            
        } else if keyMode == "direct" {
            // ━━━ BYOK (DIRECT) MODE ━━━
            let specificKey = UserDefaults.standard.string(forKey: "\(provider.rawValue)_api_key") ?? ""
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
        
        // DEBUG: Log key resolution (remove after debugging)
        let syncKeyPreview = actualKey.isEmpty ? "(empty)" : String(actualKey.prefix(12)) + "..."
        NSLog("🔑 [AIClient.sendSync] mode=%@ provider=%@ key=%@ url=%@", keyMode, provider.rawValue, syncKeyPreview, baseURL)
        
        if baseURL == provider.cloudBaseURL {
            // Cloud mode → all models via OpenAI protocol through Dotmini proxy
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
        case 429: return "Rate limited — please wait a moment and try again."
        case 401, 403: return "API Key or License is invalid/expired (401). If using BYOK, verify your key in Settings → AI Provider; if using Dotmini Cloud, check your License in Settings → Account."
        case 503, 500: return "AI service temporarily unavailable (500/503). Try again in a moment."
        default: return error.localizedDescription
        }
    }
    
    // MARK: - Token Limit Configuration
    
    private func maxOutputTokens(for model: String) -> Int {
        let lower = model.lowercased()
        if lower.contains("gemini-3") || lower.contains("gemini-2.5") || lower.contains("gemini-1.5") {
            return 65536
        } else if lower.contains("claude-sonnet-4") || lower.contains("claude-opus-4") || lower.contains("claude-3-7") {
            return 64000
        } else if lower.contains("claude-3-5") {
            return 8192
        } else if lower.contains("o1") || lower.contains("o3") || lower.contains("gpt-6") || lower.contains("gpt-5") {
            return 65536
        } else if lower.contains("gpt-4o") || lower.contains("gpt-4.5") {
            return 16384
        } else if lower.contains("deepseek-reasoner") || lower.contains("deepseek-v4") {
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
        let url = URL(string: "\(baseURL)/models/\(cleanModel):streamGenerateContent?alt=sse&key=\(apiKey)")!
        
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == StreamableAIProvider.cloudProxyURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
            request.setValue("microcode", forHTTPHeaderField: "X-Dotmini-Product")
        }
        
        var body: [String: Any] = [
            "generationConfig": ["temperature": 0.7, "maxOutputTokens": maxOutputTokens(for: cleanModel)]
        ]
        
        if let sys = systemPrompt, !sys.isEmpty {
            body["systemInstruction"] = ["parts": [["text": sys]]]
        }
        
        var rawContents: [[String: Any]] = []
        
        for msg in conversationHistory {
            let trimmed = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let geminiRole = msg.role == "assistant" ? "model" : "user"
            rawContents.append(["role": geminiRole, "parts": [["text": trimmed]]])
        }
        
        var userParts: [[String: Any]] = []
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            userParts.append(["text": trimmedPrompt])
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
            let errDebug = "[\(Date())] GEMINI ERROR \(code): \(errorBody.prefix(300))\n"
            if let d = errDebug.data(using: .utf8) {
                if let fh = FileHandle(forWritingAtPath: "/tmp/microcode_ai_debug.log") {
                    fh.seekToEndOfFile(); fh.write(d); fh.closeFile()
                }
            }
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
                    let toolCall = AIToolCall(id: UUID().uuidString, name: name, arguments: args)
                    onToolCall?(toolCall)
                }
            }
        }
        
        if isStreamingReasoning {
            isStreamingReasoning = false
            appendStreamToken("</thought>\n\n", onToken: onToken)
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
        let url = URL(string: "\(baseURL)/chat/completions")!
        
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
            let isPlatformKey = apiKey.hasPrefix("sk-dotmini-") || apiKey.hasPrefix("mci-live-")
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
        
        var messages: [[String: Any]] = []
        if let sys = systemPrompt { messages.append(["role": "system", "content": sys]) }
        for msg in conversationHistory { messages.append(["role": msg.role, "content": msg.content]) }
        
        var contentArray: [[String: Any]] = [["type": "text", "text": prompt]]
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
        
        // Buffer for streaming tool calls
        var toolCallBuffers: [String: (name: String, args: String)] = [:]
        var isStreamingReasoning = false
        
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: "), line != "data: [DONE]" else { continue }
            let jsonString = String(line.dropFirst(6))
            
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
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
            for (_, buffer) in toolCallBuffers {
                guard !buffer.name.isEmpty else { continue }
                let args = (try? JSONSerialization.jsonObject(with: Data(buffer.args.utf8))) as? [String: Any] ?? [:]
                let toolCall = AIToolCall(id: UUID().uuidString, name: buffer.name, arguments: args)
                onToolCall?(toolCall)
            }
            toolCallBuffers.removeAll()
        }
    }
    
    // MARK: - Anthropic Streaming
    
    private func streamAnthropic(prompt: String, attachments: [AIAttachment], systemPrompt: String?, conversationHistory: [(role: String, content: String)], model: String, apiKey: String, tools: [[String: Any]]?, onToken: @escaping (String) -> Void, onToolCall: ((AIToolCall) -> Void)?) async throws {
        let baseURL = StreamableAIProvider.anthropic.directBaseURL
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
        messageContent.append(["type": "text", "text": prompt])
        allMessages.append(["role": "user", "content": messageContent])
        
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
        let url = URL(string: "\(baseURL)/models/\(cleanModel):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
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
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
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
        let url = URL(string: "\(baseURL)/chat/completions")!
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
            let isPlatformKey = apiKey.hasPrefix("sk-dotmini-") || apiKey.hasPrefix("mci-live-")
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
        
        var apiMessages: [[String: Any]] = []
        if let sys = systemPrompt { apiMessages.append(["role": "system", "content": sys]) }
        for msg in messages {
            let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
            let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
            apiMessages.append(["role": role, "content": content])
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
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
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
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
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
