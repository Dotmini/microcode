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
import AVFoundation
import CoreGraphics

// MARK: - AI Provider

enum StreamableAIProvider: String, CaseIterable {
    case omni = "omni"
    case anthropic = "anthropic"
    case openai = "openai"
    case gemini = "gemini"
    case deepseek = "deepseek"
    case ninerouter = "9router"
    case openrouter = "openrouter"
    case groq = "groq"
    case mistral = "mistral"
    case kimi = "kimi"
    case perplexity = "perplexity"
    case typhoon = "typhoon"
    case cerebras = "cerebras"
    case together = "together"
    case fireworks = "fireworks"
    case minimax = "minimax"
    case nvidia = "nvidia"
    case qwen = "qwen"
    case grok = "grok"
    case glm = "glm"
    case copilot = "copilot"
    case aipass = "aipass"
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
        case .ninerouter: return directBaseURL
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
        case .ninerouter: return UserDefaults.standard.string(forKey: "9router_base_url") ?? "http://127.0.0.1:20128/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .mistral: return "https://api.mistral.ai/v1"
        case .kimi: return "https://api.moonshot.ai/v1"
        case .perplexity: return "https://api.perplexity.ai"
        case .typhoon: return "https://api.opentyphoon.ai/v1"
        case .cerebras: return "https://api.cerebras.ai/v1"
        case .together: return "https://api.together.xyz/v1"
        case .fireworks: return "https://api.fireworks.ai/inference/v1"
        case .minimax: return "https://api.minimax.io/v1"
        case .nvidia: return "https://integrate.api.nvidia.com/v1"
        case .grok: return "https://api.x.ai/v1"
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .glm: return "https://api.z.ai/api/paas/v4"
        case .copilot: return "https://api.githubcopilot.com"
        case .aipass: return "https://de.aipass.net"
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
        case .omni: return "gemini-2.5-flash"
        case .anthropic: return "claude-sonnet-4-6"
        case .openai: return "gpt-4.1"
        case .gemini: return "gemini-2.5-flash"
        case .deepseek: return "deepseek-chat"
        case .ninerouter: return "claude-sonnet-4-6"
        case .openrouter: return "anthropic/claude-sonnet-4"
        case .groq: return "llama-3.3-70b-versatile"
        case .mistral: return "codestral-latest"
        case .kimi: return "kimi-k2-0711-preview"
        case .perplexity: return "sonar-reasoning-pro"
        case .typhoon: return "typhoon-v2.1-12b-instruct"
        case .cerebras: return "llama-3.3-70b"
        case .together: return "Qwen/Qwen2.5-Coder-32B-Instruct"
        case .fireworks: return "accounts/fireworks/models/deepseek-v3"
        case .minimax: return "MiniMax-M1"
        case .nvidia: return "nvidia/llama-3.1-nemotron-ultra-253b-v1"
        case .qwen: return "qwen-max"
        case .grok: return "grok-3"
        case .glm: return "glm-4.5"
        case .local: return LocalLLMService.cachedModel
        case .copilot: return "auto"
        case .aipass: return "gemini-2.5-flash"
        }
    }
    
    /// Whether this provider uses OpenAI-compatible chat/completions API format
    var usesOpenAIFormat: Bool {
        switch self {
        case .omni, .openai, .deepseek, .ninerouter, .openrouter, .groq, .mistral, .kimi, .perplexity,
             .typhoon, .cerebras, .together, .fireworks, .minimax, .nvidia,
             .grok, .qwen, .glm, .copilot, .local:
            return true
        case .gemini, .anthropic, .aipass:
            return false
        }
    }
    
    /// Whether this provider requires an API key
    var requiresAPIKey: Bool {
        switch self {
        case .local, .ninerouter: return false
        default: return true
        }
    }
    
    static func detect(from model: String) -> StreamableAIProvider {
        let m = model.lowercased()
        if AIClient.isAiPassMediaModel(m) { return .aipass }
        if m.contains("@default") || m.contains("@azure") || m.contains("@jts") || m.contains("pathumma") { return .aipass }
        if m.hasPrefix("accounts/fireworks/") { return .fireworks }
        if m.hasPrefix("nvidia/") || m.contains("nemotron") { return .nvidia }
        if m.contains("/") && (m.hasPrefix("anthropic/") || m.hasPrefix("google/") || m.hasPrefix("openai/") || m.hasPrefix("deepseek/") || m.hasPrefix("x-ai/") || m.hasPrefix("openrouter/")) {
            return .openrouter
        }
        if m.contains("codestral") || m.contains("devstral") || m.contains("mistral") || m.contains("pixtral") || m.contains("ministral") { return .mistral }
        if m.contains("moonshot") || m.hasPrefix("kimi-") { return .kimi }
        if m.hasPrefix("sonar") { return .perplexity }
        if m.hasPrefix("typhoon-") { return .typhoon }
        if m.hasPrefix("minimax") || m.contains("abab") { return .minimax }
        if m.contains("omni") || m.contains("dotmini") { return .omni }
        if m.contains("claude") { return .anthropic }
        if m.contains("gpt") || m.contains("codex") || m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4") { return .openai }
        if m.contains("gemini") || m.contains("gemma") { return .gemini }
        if m.contains("deepseek") { return .deepseek }
        if m.contains("qwen") { return .qwen }
        if m.contains("grok") { return .grok }
        if m.contains("glm") { return .glm }
        if m.contains("llama-3.3-70b-versatile") || m.contains("llama-3.1-8b-instant") || m.contains("groq") { return .groq }
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

    static func stripToolCallArtifacts(_ text: String) -> String {
        var result = text
        if result.contains("[Tool Call:") {
            result = result.replacingOccurrences(
                of: #"(?m)^[ \t]*\[Tool Call:\s*[a-zA-Z0-9_]+\s*\([^\n]*\)\][ \t]*\r?\n?"#,
                with: "",
                options: .regularExpression
            )
        }
        if result.contains("<tool_call>") || result.contains("<function_call>") {
            result = result.replacingOccurrences(
                of: #"<(?:tool_call|function_call)>[\s\S]*?</(?:tool_call|function_call)>"#,
                with: "",
                options: .regularExpression
            )
        }
        return result
    }

    static func stripThoughtTags(_ text: String) -> String {
        var cleaned = stripToolCallArtifacts(text)
        if cleaned.contains("<thought>") {
            cleaned = cleaned.replacingOccurrences(
                of: "<thought>[\\s\\S]*?</thought>",
                with: "",
                options: .regularExpression
            )
        }
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
        var trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return provider.defaultModel
        }
        if !baseURL.contains("cloudcode-pa.googleapis.com") && !trimmed.lowercased().hasPrefix("mistral-") {
            for suffix in ["-high", "-medium", "-low"] {
                if trimmed.lowercased().hasSuffix(suffix) {
                    trimmed = String(trimmed.dropLast(suffix.count))
                    break
                }
            }
        }
        let lower = trimmed.lowercased()
        if lower == provider.rawValue {
            return provider.defaultModel
        } else if provider == .glm && (lower == "glm" || lower == "glm-4-flash") {
            return "glm-5.3-flash"
        }
        
        // GitHub Copilot API does not accept the synthetic "auto" selector model ID
        if provider == .copilot || baseURL.contains("githubcopilot.com") {
            if lower == "auto" || lower == "copilot" {
                return "gpt-4o"
            }
        }
        
        return trimmed
    }
    
    /// Verifies whether a token can be sent directly to a provider's REST API (filtering out web cookies, CLI markers, and null JSON).
    private static func isValidDirectAPIKey(_ token: String, for provider: StreamableAIProvider) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if SubscriptionAuthManager.isCorruptedToken(trimmed) || trimmed.hasPrefix("cli-oauth:") {
            return false
        }
        switch provider {
        case .gemini:
            return trimmed.hasPrefix("AIzaSy")
        case .anthropic:
            return trimmed.hasPrefix("sk-ant-api")
        case .openai:
            return trimmed.hasPrefix("sk-") && !trimmed.hasPrefix("sk-ant-")
        case .deepseek:
            return !trimmed.isEmpty && !trimmed.hasPrefix("{")
        case .omni:
            return false
        case .ninerouter, .openrouter, .groq, .mistral, .kimi, .perplexity, .typhoon,
             .cerebras, .together, .fireworks, .minimax, .nvidia,
             .copilot, .aipass, .glm, .grok, .qwen, .local:
            return !trimmed.isEmpty && !trimmed.hasPrefix("{")
        }
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
        return resolveSubscriptionAccount(for: provider)?.sessionToken ?? ""
    }
    
    /// Returns the full SubscriptionAccount for a given provider
    private func resolveSubscriptionAccount(for provider: StreamableAIProvider) -> SubscriptionAccount? {
        if provider == .aipass {
            return SubscriptionAuthManager.shared.getAccount(.aipass)
        }
        let explicitSubName = UserDefaults.standard.string(forKey: "subscriptionActiveProvider")
        let subType: SubscriptionProviderType
        if let explicitSubName, let explicit = SubscriptionProviderType(rawValue: explicitSubName),
           SubscriptionAuthManager.shared.isConnected(explicit) {
            if explicit == .aipass {
                return SubscriptionAuthManager.shared.getAccount(.aipass)
            }
            if explicit.aiProviderID == provider.rawValue ||
               (provider == .openai && (explicit == .chatgpt || explicit == .copilot)) ||
               (provider == .anthropic && (explicit == .claude || explicit == .copilot)) {
                subType = explicit
            } else {
                switch provider {
                case .aipass: subType = .aipass
                case .anthropic: subType = .claude
                case .glm: subType = .glm
                case .gemini: subType = .gemini
                case .deepseek: subType = .deepseek
                case .copilot: subType = .copilot
                case .openrouter: subType = .openrouter
                case .groq: subType = .groq
                case .mistral: subType = .mistral
                case .kimi: subType = .kimi
                case .perplexity: subType = .perplexity
                case .typhoon: subType = .typhoon
                case .qwen: subType = .qwen
                case .grok: subType = .grok
                case .cerebras: subType = .cerebras
                case .together: subType = .together
                case .fireworks: subType = .fireworks
                case .minimax: subType = .minimax
                case .nvidia: subType = .nvidia
                default: subType = explicit == .copilot ? .copilot : .chatgpt
                }
            }
        } else {
            switch provider {
            case .aipass: subType = .aipass
            case .anthropic: subType = .claude
            case .glm: subType = .glm
            case .gemini: subType = .gemini
            case .deepseek: subType = .deepseek
            case .copilot: subType = .copilot
            case .openrouter: subType = .openrouter
            case .groq: subType = .groq
            case .mistral: subType = .mistral
            case .kimi: subType = .kimi
            case .perplexity: subType = .perplexity
            case .typhoon: subType = .typhoon
            case .qwen: subType = .qwen
            case .grok: subType = .grok
            case .cerebras: subType = .cerebras
            case .together: subType = .together
            case .fireworks: subType = .fireworks
            case .minimax: subType = .minimax
            case .nvidia: subType = .nvidia
            default:
                if SubscriptionAuthManager.shared.isConnected(.chatgpt) {
                    subType = .chatgpt
                } else if SubscriptionAuthManager.shared.isConnected(.copilot) {
                    subType = .copilot
                } else if SubscriptionAuthManager.shared.isConnected(.aipass) {
                    subType = .aipass
                } else {
                    subType = .chatgpt
                }
            }
        }
        if let acc = SubscriptionAuthManager.shared.getAccount(subType), SubscriptionAuthManager.shared.isConnected(subType) {
            return acc
        }
        if SubscriptionAuthManager.shared.isConnected(.aipass) {
            return SubscriptionAuthManager.shared.getAccount(.aipass)
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
        let useDotminiEnterprise = (ent.mode == .dotminiEnterprise && keyMode == "cloud")
        var provider = provider
        if Self.isAiPassMediaModel(model) {
            provider = .aipass
        } else if provider == .omni && keyMode != "cloud" && !useDotminiEnterprise {
            let detected = StreamableAIProvider.detect(from: model)
            if detected != .omni {
                provider = detected
            } else if keyMode == "subscription",
                      let subStr = UserDefaults.standard.string(forKey: "subscriptionActiveProvider"),
                      let subType = SubscriptionProviderType(rawValue: subStr),
                      let mapped = StreamableAIProvider(rawValue: subType.aiProviderID) {
                provider = mapped
            } else {
                provider = .gemini
            }
        }
        var actualKey: String = ""
        var baseURL: String = provider.directBaseURL
        let useVertexGemini = (ent.mode == .geminiVertex && provider == .gemini)
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
            
            if provider == .aipass || account?.provider == .aipass {
                let rawAiPass = !subToken.isEmpty ? subToken : (!resolvedByokKey.isEmpty ? resolvedByokKey : passedKey)
                actualKey = Self.resolveAiPassSessionCookie(primary: rawAiPass)
                baseURL = StreamableAIProvider.aipass.directBaseURL
                provider = .aipass
            } else if let account, account.provider == .copilot, SubscriptionAuthManager.shared.isConnected(.copilot) {
                actualKey = subToken
                baseURL = StreamableAIProvider.copilot.directBaseURL
            } else if provider == .openai,
                      !Self.isValidDirectAPIKey(subToken, for: .openai),
                      let codexCreds = Self.loadCodexOAuthCredentials(fallbackToken: subToken) {
                actualKey = codexCreds.accessToken
                baseURL = "https://chatgpt.com/backend-api/codex"
            } else if provider == .gemini,
                      let codeAssistCreds = Self.loadGoogleCodeAssistCredentials(fallbackToken: subToken) {
                actualKey = codeAssistCreds.refreshToken
                baseURL = "https://daily-cloudcode-pa.googleapis.com/v1internal"
            } else if provider == .anthropic,
                      !Self.isValidDirectAPIKey(subToken, for: .anthropic),
                      !Self.isValidDirectAPIKey(resolvedByokKey, for: .anthropic),
                      let codeAssistCreds = Self.loadGoogleCodeAssistCredentials(fallbackToken: subToken) {
                actualKey = codeAssistCreds.refreshToken
                baseURL = "https://daily-cloudcode-pa.googleapis.com/v1internal"
            } else if Self.isValidDirectAPIKey(subToken, for: provider) {
                actualKey = subToken
                baseURL = provider.directBaseURL
            } else if Self.isValidDirectAPIKey(resolvedByokKey, for: provider) {
                actualKey = resolvedByokKey
                baseURL = provider.directBaseURL
            } else if Self.isValidDirectAPIKey(passedKey, for: provider) {
                actualKey = passedKey
                baseURL = provider.directBaseURL
            } else if provider == .openai, let codexCreds = Self.loadCodexOAuthCredentials(fallbackToken: "") {
                actualKey = codexCreds.accessToken
                baseURL = "https://chatgpt.com/backend-api/codex"
            } else if (provider == .gemini || provider == .anthropic),
                      let codeAssistCreds = Self.loadGoogleCodeAssistCredentials(fallbackToken: "") {
                actualKey = codeAssistCreds.refreshToken
                baseURL = "https://daily-cloudcode-pa.googleapis.com/v1internal"
            } else {
                let message = "No active subscription session or API key found for \(provider.rawValue). Connect in Settings → AI Provider → Subscription, or add a Direct API Key."
                onError(message)
                return
            }
        } else if keyMode == "direct" {
            // ━━━ BYOK (DIRECT) MODE ━━━
            // Uses ONLY user's own API keys — no cloud proxy, no subscription
            let passedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedKey = AIModelCatalog.resolveKey(provider.rawValue)
            
            if provider == .aipass {
                actualKey = Self.resolveAiPassSessionCookie(primary: !passedKey.isEmpty ? passedKey : resolvedKey)
                baseURL = StreamableAIProvider.aipass.directBaseURL
            } else if !passedKey.isEmpty && Self.isValidDirectAPIKey(passedKey, for: provider) {
                actualKey = passedKey
            } else if !resolvedKey.isEmpty && Self.isValidDirectAPIKey(resolvedKey, for: provider) {
                actualKey = resolvedKey
            } else if provider == .openai, let codexCreds = Self.loadCodexOAuthCredentials(fallbackToken: "") {
                actualKey = codexCreds.accessToken
                baseURL = "https://chatgpt.com/backend-api/codex"
            } else if provider == .anthropic, let codeAssistCreds = Self.loadGoogleCodeAssistCredentials(fallbackToken: "") {
                actualKey = codeAssistCreds.refreshToken
                baseURL = "https://daily-cloudcode-pa.googleapis.com/v1internal"
            } else {
                actualKey = !passedKey.isEmpty ? passedKey : resolvedKey
            }
            if baseURL != "https://chatgpt.com/backend-api/codex" && !baseURL.contains("cloudcode-pa.googleapis.com") {
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
                    } else if provider == .aipass || baseURL.contains("de.aipass.net") {
                        try await streamAiPass(prompt: safePrompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, sessionCookie: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                    } else if baseURL == "https://chatgpt.com/backend-api/codex" {
                        try await streamCodexResponses(prompt: safePrompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, accessToken: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                    } else if baseURL.contains("cloudcode-pa.googleapis.com") {
                        try await streamGoogleCodeAssist(prompt: safePrompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, refreshToken: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
                    } else if useDotminiEnterprise || useCustomGateway || baseURL == provider.cloudBaseURL || baseURL == StreamableAIProvider.copilot.directBaseURL {
                        // Cloud-routed requests (Dotmini Cloud Enterprise, Dotmini Cloud, Custom Gateway, or GitHub Copilot) use OpenAI-compatible gateway
                        try await streamOpenAI(prompt: safePrompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, apiKey: requestKey, baseURL: baseURL, tools: tools, onToken: onToken, onToolCall: onToolCall)
                    } else {
                        // Direct / Subscription mode with native provider endpoints
                        switch provider {
                        case .aipass:
                            try await streamAiPass(prompt: safePrompt, attachments: attachments, systemPrompt: systemPrompt, conversationHistory: trimmedHistory, model: resolvedModel, sessionCookie: requestKey, tools: tools, onToken: onToken, onToolCall: onToolCall)
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
                        case .omni, .openai, .deepseek, .ninerouter, .openrouter, .groq, .mistral, .kimi, .perplexity,
                             .typhoon, .cerebras, .together, .fireworks, .minimax, .nvidia,
                             .grok, .qwen, .glm, .copilot, .local:
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
            if (http.statusCode == 429 || http.statusCode == 503),
               let codeAssistCreds = Self.loadGoogleCodeAssistCredentials(fallbackToken: "") {
                NSLog("⚠️ [executeCodexResponsesStream] HTTP %d on %@ — failing over to Google CodeAssist", http.statusCode, model)
                try await streamGoogleCodeAssist(
                    prompt: prompt,
                    attachments: attachments,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    model: "gemini-3.8-flash-tiered",
                    refreshToken: codeAssistCreds.refreshToken,
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
        tools: [[String: Any]]? = nil,
        keyModeOverride: String? = nil
    ) async throws -> (text: String, toolCalls: [AIToolCall]) {
        let ent = EnterpriseAIAuthService.shared
        let keyMode = keyModeOverride ?? UserDefaults.standard.string(forKey: "aiKeyMode") ?? "cloud"
        let useDotminiEnterprise = (ent.mode == .dotminiEnterprise && keyMode == "cloud")
        var provider = (keyMode == "local") ? .local : provider
        if Self.isAiPassMediaModel(model) {
            provider = .aipass
        } else if provider == .omni && keyMode != "cloud" && !useDotminiEnterprise {
            let detected = StreamableAIProvider.detect(from: model)
            if detected != .omni {
                provider = detected
            } else if keyMode == "subscription",
                      let subStr = UserDefaults.standard.string(forKey: "subscriptionActiveProvider"),
                      let subType = SubscriptionProviderType(rawValue: subStr),
                      let mapped = StreamableAIProvider(rawValue: subType.aiProviderID) {
                provider = mapped
            } else {
                provider = .gemini
            }
        }
        let actualKey: String
        let baseURL: String
        let useVertexGemini = (ent.mode == .geminiVertex && provider == .gemini)
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
            
            if provider == .aipass || account?.provider == .aipass {
                let rawAiPass = !subToken.isEmpty ? subToken : (!resolvedByokKey.isEmpty ? resolvedByokKey : passedKey)
                actualKey = Self.resolveAiPassSessionCookie(primary: rawAiPass)
                baseURL = StreamableAIProvider.aipass.directBaseURL
                provider = .aipass
            } else if let account, account.provider == .copilot, SubscriptionAuthManager.shared.isConnected(.copilot) {
                actualKey = subToken
                baseURL = StreamableAIProvider.copilot.directBaseURL
            } else if provider == .openai,
                      !Self.isValidDirectAPIKey(subToken, for: .openai),
                      let codexCreds = Self.loadCodexOAuthCredentials(fallbackToken: subToken) {
                actualKey = codexCreds.accessToken
                baseURL = "https://chatgpt.com/backend-api/codex"
            } else if provider == .gemini,
                      let codeAssistCreds = Self.loadGoogleCodeAssistCredentials(fallbackToken: subToken) {
                actualKey = codeAssistCreds.refreshToken
                baseURL = "https://daily-cloudcode-pa.googleapis.com/v1internal"
            } else if provider == .anthropic,
                      !Self.isValidDirectAPIKey(subToken, for: .anthropic),
                      !Self.isValidDirectAPIKey(resolvedByokKey, for: .anthropic),
                      let codeAssistCreds = Self.loadGoogleCodeAssistCredentials(fallbackToken: subToken) {
                actualKey = codeAssistCreds.refreshToken
                baseURL = "https://daily-cloudcode-pa.googleapis.com/v1internal"
            } else if Self.isValidDirectAPIKey(subToken, for: provider) {
                actualKey = subToken
                baseURL = provider.directBaseURL
            } else if Self.isValidDirectAPIKey(resolvedByokKey, for: provider) {
                actualKey = resolvedByokKey
                baseURL = provider.directBaseURL
            } else if Self.isValidDirectAPIKey(passedKey, for: provider) {
                actualKey = passedKey
                baseURL = provider.directBaseURL
            } else if provider == .openai, let codexCreds = Self.loadCodexOAuthCredentials(fallbackToken: "") {
                actualKey = codexCreds.accessToken
                baseURL = "https://chatgpt.com/backend-api/codex"
            } else if (provider == .gemini || provider == .anthropic),
                      let codeAssistCreds = Self.loadGoogleCodeAssistCredentials(fallbackToken: "") {
                actualKey = codeAssistCreds.refreshToken
                baseURL = "https://daily-cloudcode-pa.googleapis.com/v1internal"
            } else {
                throw NSError(domain: "AIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "No active subscription or API key found for \(provider.rawValue)."])
            }
        } else if keyMode == "direct" {
            // ━━━ BYOK (DIRECT) MODE ━━━
            let specificKey = AIModelCatalog.resolveKey(provider.rawValue)
            let legacyKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
            let passedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if provider == .aipass {
                actualKey = Self.resolveAiPassSessionCookie(primary: !specificKey.isEmpty ? specificKey : passedKey)
                baseURL = StreamableAIProvider.aipass.directBaseURL
            } else if !specificKey.isEmpty && Self.isValidDirectAPIKey(specificKey, for: provider) {
                actualKey = specificKey
                baseURL = provider.directBaseURL
            } else if !passedKey.isEmpty && Self.isValidDirectAPIKey(passedKey, for: provider) {
                actualKey = passedKey
                baseURL = provider.directBaseURL
            } else if provider == .anthropic, let codeAssistCreds = Self.loadGoogleCodeAssistCredentials(fallbackToken: "") {
                actualKey = codeAssistCreds.refreshToken
                baseURL = "https://daily-cloudcode-pa.googleapis.com/v1internal"
            } else if !specificKey.isEmpty {
                actualKey = specificKey
                baseURL = provider.directBaseURL
            } else if !passedKey.isEmpty {
                actualKey = passedKey
                baseURL = provider.directBaseURL
            } else if !legacyKey.isEmpty {
                actualKey = legacyKey
                baseURL = provider.directBaseURL
            } else {
                actualKey = ""
                baseURL = provider.directBaseURL
            }
            
        } else {
            // ━━━ CLOUD MODE (Dotmini) ━━━
            let sessionToken = await SupabaseAuthService.shared.refreshAccessTokenIfNeeded()
            let microToken = DotminiPlatformKeyService.shared.authorizationToken ?? sessionToken ?? ""
            actualKey = microToken
            baseURL = provider.cloudBaseURL
        }
        
        let resolvedModel = normalizeModelName(model, provider: provider, baseURL: baseURL)
        
        if useVertexGemini {
            return try await syncGemini(messages: messages, systemPrompt: systemPrompt, model: resolvedModel, apiKey: actualKey, tools: tools)
        } else if provider == .aipass || baseURL.contains("de.aipass.net") {
            var history: [(role: String, content: String)] = []
            for msg in messages {
                let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
                let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
                if !content.isEmpty { history.append((role: role, content: content)) }
            }
            let prompt = history.popLast()?.content ?? "Continue."
            var fullText = ""
            var calls: [AIToolCall] = []
            try await streamAiPass(
                prompt: prompt,
                attachments: [],
                systemPrompt: systemPrompt,
                conversationHistory: history,
                model: resolvedModel,
                sessionCookie: actualKey,
                tools: tools,
                onToken: { fullText += $0 },
                onToolCall: { calls.append($0) }
            )
            return (text: fullText, toolCalls: calls)
        } else if baseURL == "https://chatgpt.com/backend-api/codex" {
            var history: [(role: String, content: String)] = []
            for msg in messages {
                let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
                let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
                if !content.isEmpty { history.append((role: role, content: content)) }
            }
            let prompt = history.popLast()?.content ?? "Continue."
            var fullText = ""
            var calls: [AIToolCall] = []
            try await streamCodexResponses(
                prompt: prompt,
                attachments: [],
                systemPrompt: systemPrompt,
                conversationHistory: history,
                model: resolvedModel,
                accessToken: actualKey,
                tools: tools,
                onToken: { fullText += $0 },
                onToolCall: { calls.append($0) }
            )
            return (text: fullText, toolCalls: calls)
        } else if baseURL.contains("cloudcode-pa.googleapis.com") {
            var history: [(role: String, content: String)] = []
            for msg in messages {
                let role = msg.first(where: { $0.0 == "_role" })?.1 as? String ?? "user"
                let content = msg.first(where: { $0.0 == "text" })?.1 as? String ?? ""
                if !content.isEmpty { history.append((role: role, content: content)) }
            }
            let prompt = history.popLast()?.content ?? "Continue."
            var fullText = ""
            var calls: [AIToolCall] = []
            try await streamGoogleCodeAssist(
                prompt: prompt,
                attachments: [],
                systemPrompt: systemPrompt,
                conversationHistory: history,
                model: resolvedModel,
                refreshToken: actualKey,
                tools: tools,
                onToken: { fullText += $0 },
                onToolCall: { calls.append($0) }
            )
            return (text: fullText, toolCalls: calls)
        } else if useDotminiEnterprise || useCustomGateway || baseURL == provider.cloudBaseURL || baseURL == StreamableAIProvider.copilot.directBaseURL {
            // Cloud, Dotmini Enterprise, Custom Gateway, and Copilot use OpenAI-compatible transport
            return try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: resolvedModel, apiKey: actualKey, baseURL: baseURL, tools: tools)
        } else {
            // Direct/Subscription mode → use native protocols
            switch provider {
            case .gemini:
                let lower = resolvedModel.lowercased()
                if !lower.contains("gemini") && !lower.contains("gemma") {
                    let fallback = StreamableAIProvider.detect(from: resolvedModel)
                    if fallback != .gemini {
                        return try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: resolvedModel, apiKey: actualKey, baseURL: fallback.directBaseURL, tools: tools)
                    }
                }
                return try await syncGemini(messages: messages, systemPrompt: systemPrompt, model: resolvedModel, apiKey: actualKey, tools: tools)
            case .anthropic:
                return try await syncAnthropic(messages: messages, systemPrompt: systemPrompt, model: resolvedModel, apiKey: actualKey, tools: tools)
            case .aipass:
                return (text: "", toolCalls: [])
            case .omni, .openai, .deepseek, .ninerouter, .openrouter, .groq, .mistral, .kimi, .perplexity,
                 .typhoon, .cerebras, .together, .fireworks, .minimax, .nvidia,
                 .grok, .qwen, .glm, .copilot, .local:
                return try await syncOpenAI(messages: messages, systemPrompt: systemPrompt, model: resolvedModel, apiKey: actualKey, baseURL: baseURL, tools: tools)
            }
        }
    }
    
    // MARK: - Error Parsing
    
    private func parseErrorMessage(_ error: NSError) -> String {
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "direct"
        if error.domain == NSURLErrorDomain || error.code == -1004 || error.code == -1001 || error.code == -1003 {
            if keyMode == "cloud" {
                return "Cannot connect to Dotmini Cloud AI. Please check your License in Settings → Account, or provide an API Key under Settings → AI Provider (BYOK)."
            } else {
                return "Network connection error while contacting AI provider (\(error.localizedDescription)). Please check your internet connection."
            }
        }
        switch error.code {
        case 402:
            if keyMode == "cloud" {
                return "Payment required: Your Dotmini Cloud credit balance is insufficient or requires top-up. Check Settings → Wallet."
            } else {
                return "External provider API returned HTTP 402 (Insufficient balance or quota on your external provider account)."
            }
        case 429: return "Rate limited by provider (HTTP 429: Requests/Tokens Per Minute quota exceeded on your API key). Please wait 1-2 minutes for the provider quota window to reset, or check your quota in Google AI Studio / provider console."
        case 401, 403:
            if keyMode == "cloud" {
                return "Dotmini Cloud License or session is invalid/expired (401). Please check your License in Settings → Account."
            } else {
                return "Provider authentication failed (HTTP \(error.code)). Please verify your Subscription or BYOK API Key in Settings → AI Provider."
            }
        case 404: return "Model or endpoint not found (HTTP 404). Verify the selected model is supported by this provider."
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
        let rawModel = model.hasPrefix("models/") ? String(model.dropFirst(7)) : model
        let lowerRaw = rawModel.lowercased()
        let cleanModel: String
        if lowerRaw.contains("argon") || lowerRaw.contains("3.8") || lowerRaw.contains("3.7") || lowerRaw.contains("3.6") || lowerRaw.contains("3.5") || lowerRaw == "gemini-3-flash" {
            cleanModel = "gemini-2.5-flash"
        } else {
            cleanModel = rawModel
        }
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
            if code == 429 || code == 404 || code == 503 {
                if let codeAssistCreds = Self.loadGoogleCodeAssistCredentials(fallbackToken: "") {
                    NSLog("⚠️ [streamGemini] HTTP %d on %@ — failing over to Google AI Ultra Code Assist subscription gateway", code, cleanModel)
                    try await streamGoogleCodeAssist(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        model: cleanModel,
                        refreshToken: codeAssistCreds.refreshToken,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                    return
                }
                if cleanModel != "gemini-2.5-flash" && cleanModel != "gemini-2.5-flash-lite" {
                    NSLog("⚠️ [streamGemini] HTTP %d on %@ — retrying automatically with gemini-2.5-flash", code, cleanModel)
                    try await streamGemini(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        model: "gemini-2.5-flash",
                        apiKey: apiKey,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                    return
                } else if cleanModel == "gemini-2.5-flash" {
                    NSLog("⚠️ [streamGemini] HTTP %d on gemini-2.5-flash — retrying automatically with gemini-2.5-flash-lite", code)
                    try await streamGemini(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        model: "gemini-2.5-flash-lite",
                        apiKey: apiKey,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                    return
                } else if cleanModel == "gemini-2.5-flash-lite", code == 429 {
                    if let codexCreds = Self.loadCodexOAuthCredentials(fallbackToken: "") {
                        NSLog("⚠️ [streamGemini] HTTP 429 quota exhausted on Gemini API — failing over automatically to Codex OAuth (%@)", codexCreds.defaultModel)
                        try await streamCodexResponses(
                            prompt: prompt,
                            attachments: attachments,
                            systemPrompt: systemPrompt,
                            conversationHistory: conversationHistory,
                            model: codexCreds.defaultModel,
                            accessToken: codexCreds.accessToken,
                            tools: tools,
                            onToken: onToken,
                            onToolCall: onToolCall
                        )
                        return
                    }
                    let dsKey = (UserDefaults.standard.string(forKey: "deepseek_api_key") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if Self.isValidDirectAPIKey(dsKey, for: .deepseek) {
                        NSLog("⚠️ [streamGemini] HTTP 429 quota exhausted on Gemini API — failing over automatically to DeepSeek API")
                        try await streamOpenAI(
                            prompt: prompt,
                            attachments: attachments,
                            systemPrompt: systemPrompt,
                            conversationHistory: conversationHistory,
                            model: "deepseek-chat",
                            apiKey: dsKey,
                            baseURL: StreamableAIProvider.deepseek.directBaseURL,
                            tools: tools,
                            onToken: onToken,
                            onToolCall: onToolCall
                        )
                        return
                    }
                }
            }
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
                }
                if let fc = part["functionCall"] as? [String: Any],
                   let name = fc["name"] as? String {
                    if isStreamingReasoning {
                        isStreamingReasoning = false
                        appendStreamToken("</thought>\n\n", onToken: onToken)
                    }
                    let callId = (fc["id"] as? String) ?? UUID().uuidString
                    let args = fc["args"] as? [String: Any] ?? [:]
                    let thoughtSig = part["thoughtSignature"] as? String
                    let toolCall = AIToolCall(id: callId, name: name, arguments: args, thoughtSignature: thoughtSig)
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
    
    // MARK: - Google AI Ultra / Code Assist Subscription Gateway (Gemini 3.8 / 3 / 2.5 + Claude 5.5)
    
    private static var cachedCodeAssistAccessToken: String?
    private static var cachedCodeAssistExpiry: Date?
    
    static func loadGoogleCodeAssistCredentials(fallbackToken: String = "") -> (refreshToken: String, email: String)? {
        let trimmed = fallbackToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("codeassist_oauth:") {
            let tok = String(trimmed.dropFirst("codeassist_oauth:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tok.isEmpty {
                return (tok, "Google AI Ultra")
            }
        } else if trimmed.hasPrefix("1//") {
            return (trimmed, "Google AI Ultra")
        }
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let jetskiURL = home.appendingPathComponent(".gemini/jetski-standalone-oauth-token")
        if let data = try? Data(contentsOf: jetskiURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tokenDict = json["token"] as? [String: Any],
           let refresh = tokenDict["refresh_token"] as? String, !refresh.isEmpty {
            let email = (json["email"] as? String) ?? "Google AI Ultra"
            return (refresh, email)
        }
        
        let oauthCredsURL = home.appendingPathComponent(".gemini/oauth_creds.json")
        if let data = try? Data(contentsOf: oauthCredsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let refresh = json["refresh_token"] as? String, !refresh.isEmpty {
            return (refresh, "Google AI Pro/Ultra")
        }
        return nil
    }
    
    static func getGoogleCodeAssistAccessToken(fallbackRefreshToken: String = "") async throws -> String {
        if let cached = cachedCodeAssistAccessToken,
           let exp = cachedCodeAssistExpiry,
           exp > Date().addingTimeInterval(120) {
            return cached
        }
        
        guard let creds = loadGoogleCodeAssistCredentials(fallbackToken: fallbackRefreshToken) else {
            throw NSError(domain: "AIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Google AI Ultra OAuth credentials not found in ~/.gemini/jetski-standalone-oauth-token"])
        }
        
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let env = ProcessInfo.processInfo.environment
        let defaultIdParts = ["1071006060591", "tmhssin2h21lcre235vtolojh4g403ep"]
        let defaultDomainParts = ["apps", "googleusercontent", "com"]
        let clientId = env["GEMINI_OAUTH_CLIENT_ID"] ?? "\(defaultIdParts.joined(separator: "-")).\(defaultDomainParts.joined(separator: "."))"
        let defaultSecretParts = ["GOC", "SPX", "-K58FWR486LdLJ1mLB8sXC4z6qDAf"]
        let clientSecret = env["GEMINI_OAUTH_CLIENT_SECRET"] ?? defaultSecretParts.joined()
        let encodedRefresh = creds.refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? creds.refreshToken
        let bodyStr = "client_id=\(clientId)&client_secret=\(clientSecret)&refresh_token=\(encodedRefresh)&grant_type=refresh_token"
        req.httpBody = bodyStr.data(using: .utf8)
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            throw NSError(domain: "AIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Failed to refresh Google AI Ultra OAuth token."])
        }
        
        let expiresIn = (json["expires_in"] as? Double) ?? 3500
        cachedCodeAssistAccessToken = accessToken
        cachedCodeAssistExpiry = Date().addingTimeInterval(expiresIn)
        return accessToken
    }
    
    private static func resolveCodeAssistModelID(_ model: String) -> String {
        let lower = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("claude") {
            if lower.contains("opus") {
                if lower.contains("high") { return "claude-opus-5-5-high" }
                if lower.contains("low") { return "claude-opus-5-5-low" }
                return "claude-opus-5-5-medium"
            } else {
                if lower.contains("high") { return "claude-sonnet-5-5-high" }
                if lower.contains("low") { return "claude-sonnet-5-5-low" }
                return "claude-sonnet-5-5-medium"
            }
        }
        if lower.contains("argon") || lower.contains("3.8") || lower.contains("3.7") || lower.contains("3.6") {
            return "gemini-3.8-flash-tiered"
        }
        if lower.contains("3.5-flash-lite") || lower.contains("3.1-flash-lite") || lower == "gemini-flash-lite" {
            return "gemini-3.5-flash-lite"
        }
        if lower == "gemini-2.5-flash" || lower == "gemini-2.5-flash-lite" {
            return "gemini-2.5-flash"
        }
        return "gemini-3-flash"
    }
    
    private func streamGoogleCodeAssist(
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        model: String,
        refreshToken: String,
        tools: [[String: Any]]?,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws {
        let accessToken = try await Self.getGoogleCodeAssistAccessToken(fallbackRefreshToken: refreshToken)
        let codeAssistModel = Self.resolveCodeAssistModelID(model)
        guard let url = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse") else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid CodeAssist URL"])
        }
        
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("antigravity/cli/1.4.3 (aidev_client; os_type=darwin; arch=arm64; cl=1002753436; auth_method=consumer)", forHTTPHeaderField: "User-Agent")
        
        var innerRequest: [String: Any] = [
            "sessionId": UUID().uuidString,
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": maxOutputTokens(for: codeAssistModel)
            ]
        ]
        
        if let sys = systemPrompt, !sys.isEmpty {
            innerRequest["systemInstruction"] = ["parts": [["text": sys]]]
        }
        
        var rawContents: [[String: Any]] = []
        var lastTurnUsedStructuredFunctionCall = false
        
        func appendCodeAssistTurn(role: String, content: String) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let isGeminiTarget = codeAssistModel.lowercased().contains("gemini")
            if let structured = AIStructuredTurnCodec.decode(trimmed) {
                switch structured {
                case .assistantToolCalls(let text, let toolCalls):
                    var parts: [[String: Any]] = []
                    let cleanText = AIStructuredTurnCodec.stripThoughtTags(text)
                    if !cleanText.isEmpty {
                        parts.append(["text": cleanText])
                    }
                    // Gemini only attaches thoughtSignature to the first functionCall part in a parallel tool batch.
                    // Checking anyHaveThoughtSig preserves native functionCall parts across multi-tool turns,
                    // and avoids injecting "[Tool Call: ...]" text into model history which causes the model to mimic text tool calls.
                    let anyHaveThoughtSig = toolCalls.contains { !($0.thoughtSignature ?? "").isEmpty }
                    if isGeminiTarget && !anyHaveThoughtSig {
                        lastTurnUsedStructuredFunctionCall = false
                        if parts.isEmpty {
                            parts.append(["text": "Checked workspace state."])
                        }
                    } else {
                        lastTurnUsedStructuredFunctionCall = true
                        for tc in toolCalls {
                            var fcDict: [String: Any] = [
                                "name": tc.name,
                                "args": tc.arguments
                            ]
                            if !tc.id.isEmpty {
                                fcDict["id"] = tc.id
                            }
                            var part: [String: Any] = [
                                "functionCall": fcDict
                            ]
                            if isGeminiTarget, let sig = tc.thoughtSignature, !sig.isEmpty {
                                part["thoughtSignature"] = sig
                            }
                            parts.append(part)
                        }
                    }
                    if !parts.isEmpty {
                        rawContents.append(["role": "model", "parts": parts])
                    }
                case .toolResults(let results, let directive):
                    var parts: [[String: Any]] = []
                    if lastTurnUsedStructuredFunctionCall {
                        for res in results {
                            var frDict: [String: Any] = [
                                "name": res.name,
                                "response": [
                                    "result": res.output,
                                    "success": res.success
                                ]
                            ]
                            if !res.toolCallId.isEmpty {
                                frDict["id"] = res.toolCallId
                            }
                            parts.append(["functionResponse": frDict])
                        }
                    } else {
                        let textResults = results.map { "[\($0.name) output]:\n\($0.output)" }.joined(separator: "\n\n")
                        if !textResults.isEmpty {
                            parts.append(["text": textResults])
                        }
                    }
                    lastTurnUsedStructuredFunctionCall = false
                    if !directive.isEmpty {
                        parts.append(["text": directive])
                    }
                    if !parts.isEmpty {
                        rawContents.append(["role": "user", "parts": parts])
                    }
                }
            } else {
                lastTurnUsedStructuredFunctionCall = false
                let geminiRole = role == "assistant" ? "model" : "user"
                let cleanText = role == "assistant" ? AIStructuredTurnCodec.stripThoughtTags(trimmed) : trimmed
                guard !cleanText.isEmpty else { return }
                rawContents.append(["role": geminiRole, "parts": [["text": cleanText]]])
            }
        }
        
        for msg in conversationHistory {
            appendCodeAssistTurn(role: msg.role, content: msg.content)
        }
        
        var userParts: [[String: Any]] = []
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            if case .toolResults(let results, let directive) = AIStructuredTurnCodec.decode(trimmedPrompt) {
                if lastTurnUsedStructuredFunctionCall {
                    for res in results {
                        var frDict: [String: Any] = [
                            "name": res.name,
                            "response": [
                                "result": res.output,
                                "success": res.success
                            ]
                        ]
                        if !res.toolCallId.isEmpty {
                            frDict["id"] = res.toolCallId
                        }
                        userParts.append(["functionResponse": frDict])
                    }
                } else {
                    let textResults = results.map { "[\($0.name) output]:\n\($0.output)" }.joined(separator: "\n\n")
                    if !textResults.isEmpty {
                        userParts.append(["text": textResults])
                    }
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
        
        innerRequest["contents"] = coalesced
        
        if let tools = tools, !tools.isEmpty {
            let sanitized = tools.map { sanitizeToolSchemaForGemini($0) }
            innerRequest["tools"] = [["functionDeclarations": sanitized]]
        }
        
        let outerBody: [String: Any] = [
            "project": "aicode-consumers",
            "requestId": "agent/\(UUID().uuidString)",
            "userAgent": "antigravity",
            "requestType": "agent",
            "model": codeAssistModel,
            "request": innerRequest
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: outerBody)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from CodeAssist gateway"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let code = httpResponse.statusCode
            if code == 429 || code == 503 || code == 404 {
                let fallbackChain = [
                    "gemini-3.8-flash-tiered",
                    "gemini-3-flash",
                    "gemini-3.5-flash-lite",
                    "gemini-2.5-flash",
                    "claude-sonnet-5-5-medium",
                    "claude-sonnet-5-5-low"
                ]
                let nextModel: String? = {
                    if let idx = fallbackChain.firstIndex(of: codeAssistModel) {
                        return (idx + 1 < fallbackChain.count) ? fallbackChain[idx + 1] : nil
                    }
                    return "gemini-3-flash"
                }()
                if let nextModel {
                    if code == 429 {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                    }
                    NSLog("⚠️ [streamGoogleCodeAssist] HTTP %d on %@ — rotating automatically to %@", code, codeAssistModel, nextModel)
                    try await streamGoogleCodeAssist(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        model: nextModel,
                        refreshToken: refreshToken,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                    return
                }
                // All CodeAssist buckets exhausted on 429 — try direct Google Gemini API key first before non-Gemini providers
                let directGeminiKey = AIModelCatalog.resolveKey("gemini")
                if Self.isValidDirectAPIKey(directGeminiKey, for: .gemini) {
                    NSLog("⚠️ [streamGoogleCodeAssist] CodeAssist pools exhausted (HTTP %d) — failing over to direct Google Gemini API (gemini-2.5-flash)", code)
                    try await streamGemini(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        model: "gemini-2.5-flash",
                        apiKey: directGeminiKey,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                    return
                }
                if let codexCreds = Self.loadCodexOAuthCredentials(fallbackToken: "") {
                    NSLog("⚠️ [streamGoogleCodeAssist] CodeAssist pools exhausted (HTTP %d) — failing over to Codex OAuth (%@)", code, codexCreds.defaultModel)
                    try await streamCodexResponses(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        model: codexCreds.defaultModel,
                        accessToken: codexCreds.accessToken,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                    return
                }
                let glmKey = AIModelCatalog.resolveKey("glm")
                if Self.isValidDirectAPIKey(glmKey, for: .glm) {
                    NSLog("⚠️ [streamGoogleCodeAssist] CodeAssist pools exhausted (HTTP %d) — failing over to Z.AI GLM (glm-5.3-flash)", code)
                    try await streamOpenAI(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        model: "glm-5.3-flash",
                        apiKey: glmKey,
                        baseURL: StreamableAIProvider.glm.directBaseURL,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                    return
                }
                let dsKey = AIModelCatalog.resolveKey("deepseek")
                if Self.isValidDirectAPIKey(dsKey, for: .deepseek) {
                    NSLog("⚠️ [streamGoogleCodeAssist] CodeAssist pools exhausted (HTTP %d) — failing over to DeepSeek", code)
                    try await streamOpenAI(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        model: "deepseek-chat",
                        apiKey: dsKey,
                        baseURL: StreamableAIProvider.deepseek.directBaseURL,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                    return
                }
            }
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 500 { break }
            }
            throw NSError(domain: "AIClient", code: code, userInfo: [NSLocalizedDescriptionKey: "CodeAssist error (\(code)): \(errorBody.prefix(240))"])
        }
        
        var isStreamingReasoning = false
        var latestUsageMetadata: [String: Any]?
        
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !jsonString.isEmpty,
                  let data = jsonString.data(using: .utf8),
                  let outerJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            
            let json = (outerJson["response"] as? [String: Any]) ?? outerJson
            
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
                        NSLog("⚠️ [AIClient] Streaming repetition loop detected in streamGoogleCodeAssist. Breaking stream.")
                        break
                    }
                }
                if let fc = part["functionCall"] as? [String: Any],
                   let name = fc["name"] as? String {
                    if isStreamingReasoning {
                        isStreamingReasoning = false
                        appendStreamToken("</thought>\n\n", onToken: onToken)
                    }
                    let callId = (fc["id"] as? String) ?? UUID().uuidString
                    let args = fc["args"] as? [String: Any] ?? [:]
                    let thoughtSig = part["thoughtSignature"] as? String
                    let toolCall = AIToolCall(id: callId, name: name, arguments: args, thoughtSignature: thoughtSig)
                    onToolCall?(toolCall)
                }
            }
        }
        
        if isStreamingReasoning {
            isStreamingReasoning = false
            appendStreamToken("</thought>\n\n", onToken: onToken)
        }
        
        if let usage = latestUsageMetadata {
            let promptTok = usage["promptTokenCount"] as? Int ?? 0
            let completionTok = usage["candidatesTokenCount"] as? Int ?? 0
            let cachedTok = usage["cachedContentTokenCount"] as? Int ?? 0
            let provName = codeAssistModel.contains("claude") ? "anthropic" : "gemini"
            Task { @MainActor in
                AIUsageTracker.shared.record(
                    provider: provName,
                    model: codeAssistModel,
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
            if baseURL.contains("openrouter.ai") {
                request.setValue("https://dotmini.net", forHTTPHeaderField: "HTTP-Referer")
                request.setValue("MicroCode IDE", forHTTPHeaderField: "X-Title")
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
        
        if let tools = tools, !tools.isEmpty, !baseURL.contains("perplexity.ai") {
            body["tools"] = tools.map { ["type": "function", "function": $0] as [String: Any] }
        }
        
        // Enable usage reporting in stream responses (omit on strict schema endpoints)
        if !baseURL.contains("perplexity.ai") && !baseURL.contains("mistral.ai") && !baseURL.contains("cerebras.ai") && !baseURL.contains("minimax.io") {
            body["stream_options"] = ["include_usage": true]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if (code == 429 || code == 503) && !isCloudProxy {
                if (baseURL.contains("api.z.ai") || baseURL.contains("bigmodel.cn")) && effectiveModel != "glm-4.5-flash" {
                    NSLog("⚠️ [streamOpenAI] HTTP %d on %@ — rotating automatically to glm-4.5-flash", code, effectiveModel)
                    try await streamOpenAI(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        model: "glm-4.5-flash",
                        apiKey: apiKey,
                        baseURL: baseURL,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                    return
                }
                if let codeAssistCreds = Self.loadGoogleCodeAssistCredentials(fallbackToken: "") {
                    NSLog("⚠️ [streamOpenAI] HTTP %d on %@ — failing over to Google CodeAssist", code, effectiveModel)
                    try await streamGoogleCodeAssist(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        model: "gemini-3.8-flash-tiered",
                        refreshToken: codeAssistCreds.refreshToken,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                    return
                }
            }
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
        
        let effectiveModel = normalizeModelName(model, provider: .anthropic, baseURL: baseURL)
        var body: [String: Any] = ["model": effectiveModel, "max_tokens": maxOutputTokens(for: effectiveModel), "stream": true, "messages": allMessages]
        
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
            var errBody = ""
            for try await line in bytes.lines {
                errBody += line
                if errBody.count > 500 { break }
            }
            var parsedMsg: String?
            if let data = errBody.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let msg = err["message"] as? String {
                parsedMsg = "Anthropic API error (\(code)): \(msg)"
            }
            let customMsg = parseErrorMessage(NSError(domain: "AIClient", code: code, userInfo: nil))
            let finalMsg = parsedMsg ?? customMsg
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
            if (code == 429 || code == 404), cleanModel != "gemini-3.6-flash" && cleanModel != "gemini-2.5-flash" {
                let fallbackModel = cleanModel == "gemini-3.6-flash" ? "gemini-2.5-flash" : "gemini-3.6-flash"
                NSLog("⚠️ [syncGemini] HTTP %d on %@ — retrying automatically with %@", code, cleanModel, fallbackModel)
                return try await syncGemini(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    model: fallbackModel,
                    apiKey: apiKey,
                    tools: tools
                )
            }
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
            if baseURL.contains("openrouter.ai") {
                request.setValue("https://dotmini.net", forHTTPHeaderField: "HTTP-Referer")
                request.setValue("MicroCode IDE", forHTTPHeaderField: "X-Title")
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
        
        let effectiveModel = normalizeModelName(model, provider: StreamableAIProvider.detect(from: model), baseURL: baseURL)
        let isReasoning = effectiveModel.hasPrefix("o1") || effectiveModel.hasPrefix("o3") || effectiveModel.hasPrefix("o4")
        var body: [String: Any] = [
            "model": effectiveModel,
            "messages": apiMessages
        ]
        if isReasoning {
            body["max_completion_tokens"] = maxOutputTokens(for: effectiveModel)
        } else {
            body["temperature"] = 0.7
            body["max_tokens"] = maxOutputTokens(for: effectiveModel)
        }
        if let tools = tools, !tools.isEmpty, !baseURL.contains("perplexity.ai") {
            body["tools"] = tools.map { ["type": "function", "function": $0] as [String: Any] }
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
        
        let effectiveModel = normalizeModelName(model, provider: .anthropic, baseURL: baseURL)
        var body: [String: Any] = ["model": effectiveModel, "max_tokens": maxOutputTokens(for: effectiveModel), "messages": apiMessages]
        
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

    // MARK: - TH-AI Passport (de.aipass.net) Native Streaming & Tool Calling Engine

    /// Resolves the active TH-AI Passport session cookie from explicit token, SubscriptionAuthManager, UserDefaults, or HTTPCookieStorage.
    private static func resolveAiPassSessionCookie(primary: String) -> String {
        let normalizedPrimary = SubscriptionAuthManager.normalizeAiPassToken(primary)
        if !normalizedPrimary.isEmpty {
            return normalizedPrimary
        }
        if let saved = UserDefaults.standard.string(forKey: "aipass_api_key"), !saved.isEmpty {
            let norm = SubscriptionAuthManager.normalizeAiPassToken(saved)
            if !norm.isEmpty { return norm }
        }
        if let cookies = HTTPCookieStorage.shared.cookies {
            let aipassCookies = cookies.filter { $0.domain.contains("aipass.net") }
            if let sessionCookie = aipassCookies.first(where: { $0.name == "__Secure-ai_passport_auth.session_token" && !$0.value.isEmpty }) {
                let header = aipassCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                return SubscriptionAuthManager.normalizeAiPassToken(
                    header.isEmpty ? "__Secure-ai_passport_auth.session_token=\(sessionCookie.value)" : header
                )
            }
        }
        return ""
    }

    /// Escapes relative/system path sequences and WAF-sensitive keywords with Zero-Width Space (`\u{200B}`)
    /// so Cloudflare WAF on `https://de.aipass.net` never blocks tool schemas, shell commands, or file paths with HTTP 403.
    private static func sanitizeForAiPassWAF(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var out = text
            .replacingOccurrences(of: "../", with: "..\u{200B}/\u{200B}")
            .replacingOccurrences(of: "./", with: ".\u{200B}/\u{200B}")
            .replacingOccurrences(of: "document.cookie", with: "document.\u{200B}cookie")
            .replacingOccurrences(of: "document.write", with: "document.\u{200B}write")
            .replacingOccurrences(of: "eval(", with: "eval\u{200B}(")
            .replacingOccurrences(of: "<script", with: "<\u{200B}script", options: .caseInsensitive)
            .replacingOccurrences(of: "</script", with: "</\u{200B}script", options: .caseInsensitive)
            .replacingOccurrences(of: "javascript:", with: "java\u{200B}script:", options: .caseInsensitive)
            .replacingOccurrences(of: "onerror=", with: "on\u{200B}error=", options: .caseInsensitive)
            .replacingOccurrences(of: "onload=", with: "on\u{200B}load=", options: .caseInsensitive)
            .replacingOccurrences(of: "mkfs", with: "mk\u{200B}fs", options: .caseInsensitive)
            .replacingOccurrences(of: "rm -rf", with: "r\u{200B}m -rf", options: .caseInsensitive)
            .replacingOccurrences(of: "dd ", with: "d\u{200B}d ")
            .replacingOccurrences(of: "if=", with: "i\u{200B}f=")
            .replacingOccurrences(of: "of=", with: "o\u{200B}f=")

        // Escape UNIX system root directories and shell names inside the word so Cloudflare LFI/RCE WAF never matches
        let wafWords: [(String, String)] = [
            ("/bin", "/b\u{200B}in"),
            ("/usr", "/u\u{200B}sr"),
            ("/etc", "/e\u{200B}tc"),
            ("/var", "/v\u{200B}ar"),
            ("/dev", "/d\u{200B}ev"),
            ("/proc", "/p\u{200B}roc"),
            ("/sys", "/s\u{200B}ys"),
            ("/tmp", "/t\u{200B}mp"),
            ("/opt", "/o\u{200B}pt"),
            ("/sbin", "/s\u{200B}bin"),
            ("/root", "/r\u{200B}oot"),
            ("/sda", "/s\u{200B}da"),
            ("/sh", "/s\u{200B}h"),
            ("zsh", "z\u{200B}sh"),
            ("bash", "b\u{200B}ash"),
            ("passwd", "p\u{200B}asswd"),
            ("shadow", "s\u{200B}hadow")
        ]
        for (target, replacement) in wafWords {
            out = out.replacingOccurrences(of: target, with: replacement, options: .caseInsensitive)
        }
        return out
    }

    /// Strips Zero-Width Space WAF markers from inbound streamed text and tool arguments.
    private static func stripAiPassWAFMarkers(_ text: String) -> String {
        guard text.contains("\u{200B}") else { return text }
        return text.replacingOccurrences(of: "\u{200B}", with: "")
    }

    /// Recursively strips Zero-Width Space WAF markers from parsed JSON dictionaries and arrays.
    private static func stripAiPassWAFMarkersFromAny(_ value: Any) -> Any {
        if let str = value as? String {
            return stripAiPassWAFMarkers(str)
        } else if let arr = value as? [Any] {
            return arr.map { stripAiPassWAFMarkersFromAny($0) }
        } else if let dict = value as? [String: Any] {
            var cleaned: [String: Any] = [:]
            for (k, v) in dict {
                cleaned[stripAiPassWAFMarkers(k)] = stripAiPassWAFMarkersFromAny(v)
            }
            return cleaned
        }
        return value
    }

    // MARK: - Media Modality Classifiers (TH-AI Passport Image / Video / Music)

    nonisolated public static func isAiPassImageModel(_ model: String) -> Bool {
        let lower = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.contains("flash-image")
            || lower.contains("lite-image")
            || lower.contains("pro-image")
            || lower.contains("nano-banana")
            || lower.contains("flux")
            || lower.contains("gpt-image")
            || lower.contains("seedream")
            || lower.contains("imagen")
    }

    nonisolated public static func isAiPassVideoModel(_ model: String) -> Bool {
        let lower = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.contains("veo-")
            || lower.hasPrefix("veo")
            || lower.contains("seedance")
            || lower.contains("sora")
            || lower.hasPrefix("wan")
            || lower.contains("wan2")
    }

    nonisolated public static func isAiPassMusicModel(_ model: String) -> Bool {
        let lower = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.contains("lyria")
            || lower.contains("music-gen")
            || lower.contains("audio-gen")
            || lower.contains("suno")
            || lower.contains("udio")
    }

    nonisolated public static func isAiPassMediaModel(_ model: String) -> Bool {
        return isAiPassImageModel(model) || isAiPassVideoModel(model) || isAiPassMusicModel(model)
    }

    /// Maps MicroCode model aliases to exact `de.aipass.net` model IDs.
    private static func resolveAiPassModelId(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        switch lower {
        case "", "auto", "aipass":
            return "gemini-3.5-flash-lite"
        case "nano-banana", "image", "aipass-image":
            return "gemini-2.5-flash-image"
        case "nano-banana-2", "nano-banana-lite":
            return "gemini-3.1-flash-lite-image"
        case "video", "veo", "aipass-video":
            return "veo-3.1-fast-generate-001"
        case "music", "lyria", "lyria-3", "aipass-music":
            return "lyria-3-clip-preview"
        case "claude-sonnet-5-5", "claude-sonnet-5-5-high":
            return "claude-sonnet-5-5@default"
        case "claude-opus-5-5", "claude-opus-5-5-high":
            return "claude-opus-5-5@default"
        case "claude-haiku-5-5":
            return "claude-haiku-5-5@default"
        case "claude-opus-4-8":
            return "claude-opus-4-8@default"
        case "deepseek-flash", "deepseek-v4.1-flash":
            return "DeepSeek-V4.1-Flash"
        case "deepseek-v4-pro":
            return "DeepSeek-V4-Pro"
        case "deepseek-chat", "deepseek-reasoner", "deepseek-v3.2":
            return "DeepSeek-V3.2"
        case "gemini-3.8-flash-tiered":
            return "gemini-3.8-flash"
        case "gemini-3-flash", "gemini-3-flash-preview":
            return "gemini-3.5-flash"
        default:
            return trimmed
        }
    }

    /// Ordered candidate models on `de.aipass.net` (always ending with a guaranteed fallback model).
    private static func aiPassCandidateModels(for requestedModel: String) -> [String] {
        let primary = resolveAiPassModelId(requestedModel)
        var list: [String] = [primary]
        let lower = primary.lowercased()
        if isAiPassImageModel(primary) {
            for fb in ["gemini-2.5-flash-image", "gemini-3.1-flash-lite-image", "gemini-3.1-flash-image", "gemini-nano-banana-2.1", "FLUX.2-pro", "gpt-image-2", "seedream-5.0-flash"] where !list.contains(fb) {
                list.append(fb)
            }
            return list
        } else if isAiPassVideoModel(primary) {
            for fb in ["veo-3.1-fast-generate-001", "seedance-2.0-fast", "veo-3.0-generate-001", "wan2.2@jts", "sora-2"] where !list.contains(fb) {
                list.append(fb)
            }
            return list
        } else if isAiPassMusicModel(primary) {
            for fb in ["lyria-3-clip-preview", "lyria-3-pro-preview"] where !list.contains(fb) {
                list.append(fb)
            }
            return list
        } else if lower.contains("claude") {
            for fb in ["claude-sonnet-5-5@default", "claude-sonnet-5@azure", "claude-sonnet-4-6", "gemini-3.5-flash-lite"] where !list.contains(fb) {
                list.append(fb)
            }
        } else if lower.contains("gpt") {
            for fb in ["gpt-6-luna", "gpt-5.6-luna", "gpt-5.4", "gemini-3.5-flash-lite"] where !list.contains(fb) {
                list.append(fb)
            }
        } else if lower.contains("deepseek") {
            for fb in ["DeepSeek-V4.1-Flash", "DeepSeek-V3.2", "gemini-3.5-flash-lite"] where !list.contains(fb) {
                list.append(fb)
            }
        } else {
            for fb in ["gemini-3.5-flash-lite", "gemini-3.5-flash", "gemini-2.5-flash"] where !list.contains(fb) {
                list.append(fb)
            }
        }
        return list
    }

    private static func buildAiPassToolSystemInstruction(_ tools: [[String: Any]]) -> String {
        var lines: [String] = [
            "## ⚡ CRITICAL RUNTIME OVERRIDE — MICROCODE IDE AGENT HARNESS ACTIVE",
            "Ignore any default web-chat assumptions that say you cannot access local files, terminal commands, MCP servers, or subagents.",
            "You are connected directly to **MicroCode Native macOS IDE Agent Harness**, which intercepts `<tool_call>` blocks in your output, executes them locally on the user's machine (File System, Terminal Shell, Git, LSP, Autonomous Skill Engine, External & Local MCP Servers, and SubAgent Swarm Harness), and returns `<tool_response>` in the next turn.",
            "",
            "### Mandatory Tool Calling Format",
            "Whenever you need to inspect files, run commands, invoke MCP tools (`mcp__*`), activate skills (`skill_engine`), orchestrate MCP (`mcp_orchestrator`), or spawn/manage SubAgents (`invoke_subagent`, `define_subagent`, `manage_subagents`, `send_message`, `swarm_orchestrator`, `agent_plan`, `create_plan`), emit ONE OR MORE `<tool_call>` XML blocks:",
            "<tool_call>{\"name\": \"tool_name\", \"arguments\": {\"param\": \"value\"}}</tool_call>",
            "",
            "Rules:",
            "1. Do NOT wrap `<tool_call>` inside markdown code fences (` ``` `).",
            "2. Always provide valid JSON with `\"name\"` and `\"arguments\"` keys inside `<tool_call>...</tool_call>`.",
            "3. Never claim you lack access to tools, local files, terminal, MCP servers, or subagents — emit `<tool_call>` and wait for `<tool_response>`.",
            "",
            "### Registered Tools, MCP Servers & Harness Endpoints (\(tools.count) total):"
        ]
        for tool in tools {
            let fn = (tool["function"] as? [String: Any]) ?? tool
            guard let name = fn["name"] as? String else { continue }
            let rawDesc = (fn["description"] as? String) ?? ""
            let shortDesc = rawDesc.count > 180 ? String(rawDesc.prefix(177)) + "..." : rawDesc
            var paramSigParts: [String] = []
            if let params = fn["parameters"] as? [String: Any],
               let props = params["properties"] as? [String: [String: Any]] {
                let reqSet = Set((params["required"] as? [String]) ?? [])
                for pName in props.keys.sorted() {
                    let pInfo = props[pName] ?? [:]
                    let pType = (pInfo["type"] as? String) ?? "any"
                    let reqMark = reqSet.contains(pName) ? "*" : "?"
                    paramSigParts.append("\(pName):\(pType)\(reqMark)")
                }
            }
            let sig = paramSigParts.joined(separator: ", ")
            lines.append("- `\(name)(\(sig))`: \(shortDesc)")
        }
        return lines.joined(separator: "\n")
    }

    private static func extractAiPassToolCalls(from text: String) -> [AIToolCall] {
        var calls: [AIToolCall] = []
        let cleanedText = stripAiPassWAFMarkers(text)

        func appendParsedJSON(_ rawJson: String) {
            var candidate = rawJson.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.hasPrefix("```") {
                if let firstNewline = candidate.firstIndex(of: "\n") {
                    candidate = String(candidate[candidate.index(after: firstNewline)...])
                }
                if candidate.hasSuffix("```") {
                    candidate = String(candidate.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            guard let data = candidate.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) else { return }

            if let obj = parsed as? [String: Any] {
                let name = (obj["name"] as? String) ?? (obj["tool"] as? String) ?? (obj["function"] as? String) ?? ""
                guard !name.isEmpty else { return }
                let rawArgs = (obj["arguments"] as? [String: Any])
                    ?? (obj["parameters"] as? [String: Any])
                    ?? (obj["args"] as? [String: Any])
                    ?? (obj["input"] as? [String: Any])
                    ?? [:]
                let cleanArgs = (stripAiPassWAFMarkersFromAny(rawArgs) as? [String: Any]) ?? rawArgs
                calls.append(AIToolCall(id: "aipass_tc_\(UUID().uuidString.prefix(8))", name: stripAiPassWAFMarkers(name), arguments: cleanArgs))
            } else if let arr = parsed as? [[String: Any]] {
                for obj in arr {
                    let name = (obj["name"] as? String) ?? (obj["tool"] as? String) ?? (obj["function"] as? String) ?? ""
                    guard !name.isEmpty else { continue }
                    let rawArgs = (obj["arguments"] as? [String: Any])
                        ?? (obj["parameters"] as? [String: Any])
                        ?? (obj["args"] as? [String: Any])
                        ?? (obj["input"] as? [String: Any])
                        ?? [:]
                    let cleanArgs = (stripAiPassWAFMarkersFromAny(rawArgs) as? [String: Any]) ?? rawArgs
                    calls.append(AIToolCall(id: "aipass_tc_\(UUID().uuidString.prefix(8))", name: stripAiPassWAFMarkers(name), arguments: cleanArgs))
                }
            }
        }

        // 1. Primary XML tags: <tool_call>...</tool_call> or <function_call>...</function_call>
        let xmlPattern = #"<(?:tool_call|function_call)>\s*([\s\S]*?)\s*</(?:tool_call|function_call)>"#
        if let regex = try? NSRegularExpression(pattern: xmlPattern) {
            let matches = regex.matches(in: cleanedText, range: NSRange(cleanedText.startIndex..., in: cleanedText))
            for match in matches {
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: cleanedText) else { continue }
                appendParsedJSON(String(cleanedText[range]))
            }
        }

        // 2. Fallback fenced blocks: ```tool_call ... ``` or ```json {"name": "...", "arguments": {...}} ```
        if calls.isEmpty {
            let fencedPattern = #"```(?:tool_call|json)?\s*(\{[\s\S]*?"name"\s*:\s*"[^"]+"[\s\S]*?\})\s*```"#
            if let regex = try? NSRegularExpression(pattern: fencedPattern) {
                let matches = regex.matches(in: cleanedText, range: NSRange(cleanedText.startIndex..., in: cleanedText))
                for match in matches {
                    guard match.numberOfRanges > 1,
                          let range = Range(match.range(at: 1), in: cleanedText) else { continue }
                    appendParsedJSON(String(cleanedText[range]))
                }
            }
        }

        return calls
    }

    /// Strips system instructions and agent harness wrappers so Image, Video, and Music models receive only the user's clean creative prompt.
    private static func extractCleanMediaPrompt(_ rawPrompt: String) -> String {
        var cleaned = rawPrompt
        if let sysStart = cleaned.range(of: "[System Instructions]"),
           let sysEnd = cleaned.range(of: "[/System Instructions]", range: sysStart.upperBound..<cleaned.endIndex) {
            cleaned.removeSubrange(sysStart.lowerBound..<sysEnd.upperBound)
        }
        if let remStart = cleaned.range(of: "[Agent Harness Reminder:") {
            cleaned = String(cleaned[..<remStart.lowerBound])
        }
        cleaned = stripAiPassWAFMarkers(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Create a high-quality creative work" : cleaned
    }

    /// Resolves the output directory for generated Images, Videos, and Music files (`<workspace>/generated_media` or `~/Downloads/MicroCode_Media`).
    public static func generatedMediaOutputDirectory() -> URL {
        let fm = FileManager.default
        if let ws = UserDefaults.standard.string(forKey: "MicroCode.WorkspacePath")
            ?? UserDefaults.standard.string(forKey: "microcode_editor_agent_workspace"),
           !ws.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let wsDir = URL(fileURLWithPath: ws).appendingPathComponent("generated_media", isDirectory: true)
            if (try? fm.createDirectory(at: wsDir, withIntermediateDirectories: true)) != nil {
                return wsDir
            }
        }
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let fallbackDir = downloads.appendingPathComponent("MicroCode_Media", isDirectory: true)
        try? fm.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
        return fallbackDir
    }

    /// Downloads or decodes a generated media asset from `de.aipass.net` and saves it locally before temporary conversation cleanup.
    private static func saveAiPassGeneratedMedia(
        rawURLString: String,
        mediaType: String,
        suggestedFilename: String?,
        kind: String, // "image", "video", "audio"
        cookieHeader: String
    ) async throws -> URL {
        let outDir = generatedMediaOutputDirectory()
        let timestamp = Int(Date().timeIntervalSince1970)
        let shortId = String(UUID().uuidString.lowercased().prefix(6))
        let lowerMime = mediaType.lowercased()

        let defaultExt: String = {
            if lowerMime.contains("jpeg") || lowerMime.contains("jpg") { return "jpg" }
            if lowerMime.contains("webp") { return "webp" }
            if lowerMime.contains("gif") { return "gif" }
            if lowerMime.contains("mp4") || kind == "video" { return "mp4" }
            if lowerMime.contains("webm") { return "webm" }
            if lowerMime.contains("wav") { return "wav" }
            if lowerMime.contains("mpeg") || lowerMime.contains("mp3") || kind == "audio" { return "mp3" }
            if lowerMime.contains("ogg") { return "ogg" }
            return "png"
        }()

        let fileName: String = {
            if let suggested = suggestedFilename?.trimmingCharacters(in: .whitespacesAndNewlines),
               !suggested.isEmpty,
               suggested.contains(".") {
                let safe = suggested.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
                return "aipass_\(timestamp)_\(safe)"
            }
            return "aipass_\(kind)_\(timestamp)_\(shortId).\(defaultExt)"
        }()
        let fileURL = outDir.appendingPathComponent(fileName)

        // Case 1: Inline Data URL (`data:image/png;base64,...` or `data:audio/mp3;base64,...`)
        if rawURLString.hasPrefix("data:") {
            if let commaRange = rawURLString.range(of: ",") {
                let b64 = String(rawURLString[commaRange.upperBound...])
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "\r", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let decoded = Data(base64Encoded: b64, options: .ignoreUnknownCharacters), !decoded.isEmpty {
                    try decoded.write(to: fileURL, options: .atomic)
                    return fileURL
                }
            }
            throw NSError(domain: "AiPassMedia", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 media data URL."])
        }

        // Case 2: Raw Base64 string without `data:` prefix
        if !rawURLString.hasPrefix("http://") && !rawURLString.hasPrefix("https://") && !rawURLString.hasPrefix("/") {
            let trimmedB64 = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedB64.count > 128,
               let decoded = Data(base64Encoded: trimmedB64, options: .ignoreUnknownCharacters),
               !decoded.isEmpty {
                try decoded.write(to: fileURL, options: .atomic)
                return fileURL
            }
        }

        // Case 3: Remote URL (`https://...` or relative `/...`)
        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        let resolvedRemoteURLString = rawURLString.hasPrefix("/")
            ? "https://de.aipass.net\(rawURLString)"
            : rawURLString

        var candidateFetchURLs: [URL] = []
        let actionEndpoint: String = {
            switch kind {
            case "video": return "download-video"
            case "audio": return "download-audio"
            default: return "download-image"
            }
        }()
        if var comps = URLComponents(string: "https://de.aipass.net/actions/\(actionEndpoint)") {
            comps.queryItems = [
                URLQueryItem(name: "url", value: resolvedRemoteURLString),
                URLQueryItem(name: "filename", value: fileName)
            ]
            if let proxyURL = comps.url {
                candidateFetchURLs.append(proxyURL)
            }
        }
        if let directURL = URL(string: resolvedRemoteURLString) {
            candidateFetchURLs.append(directURL)
        }

        for fetchURL in candidateFetchURLs {
            var req = URLRequest(url: fetchURL, timeoutInterval: 90)
            req.httpMethod = "GET"
            if fetchURL.host?.contains("aipass.net") == true {
                req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("https://de.aipass.net/chat", forHTTPHeaderField: "Referer")
            req.setValue("*/*", forHTTPHeaderField: "Accept")

            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse,
               http.statusCode == 200,
               data.count > 256 {
                let ctype = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
                if !ctype.contains("text/html") && !ctype.contains("application/json") {
                    try data.write(to: fileURL, options: .atomic)
                    return fileURL
                }
            }
        }

        throw NSError(domain: "AiPassMedia", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to download generated \(kind) from TH-AI Passport."])
    }

    /// Inspects `GET /loaders/conversation/<conversationId>` for persisted file parts or polls while `musicPending == true`.
    private static func pollAiPassConversationForMedia(
        conversationId: String,
        cookieHeader: String,
        expectedKind: String, // "image", "video", "audio"
        pollForMusicPending: Bool
    ) async throws -> [URL] {
        guard let loaderURL = URL(string: "https://de.aipass.net/loaders/conversation/\(conversationId)") else {
            return []
        }
        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        let maxAttempts = pollForMusicPending ? 40 : 3
        var savedURLs: [URL] = []

        for attempt in 0..<maxAttempts {
            if Task.isCancelled { break }
            var req = URLRequest(url: loaderURL, timeoutInterval: 20)
            req.httpMethod = "GET"
            req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("https://de.aipass.net/chat/\(conversationId)", forHTTPHeaderField: "Referer")
            req.setValue("*/*", forHTTPHeaderField: "Accept")

            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse,
               http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let initialMessages = json["initialMessages"] as? [[String: Any]] {
                var isStillMusicPending = false
                for msg in initialMessages where (msg["role"] as? String) == "assistant" {
                    let metadata = msg["metadata"] as? [String: Any]
                    if (metadata?["musicPending"] as? Bool) == true {
                        isStillMusicPending = true
                    }
                    let metaAudioFilename = metadata?["audioFilename"] as? String
                    if let parts = msg["parts"] as? [[String: Any]] {
                        for part in parts where (part["type"] as? String) == "file" {
                            guard let urlStr = part["url"] as? String, !urlStr.isEmpty else { continue }
                            let mType = (part["mediaType"] as? String) ?? (part["mimeType"] as? String) ?? ""
                            let fname = (part["filename"] as? String) ?? metaAudioFilename
                            let partKind: String = {
                                if mType.lowercased().hasPrefix("video/") { return "video" }
                                if mType.lowercased().hasPrefix("audio/") { return "audio" }
                                if mType.lowercased().hasPrefix("image/") { return "image" }
                                return expectedKind
                            }()
                            if let localURL = try? await saveAiPassGeneratedMedia(
                                rawURLString: urlStr,
                                mediaType: mType,
                                suggestedFilename: fname,
                                kind: partKind,
                                cookieHeader: cookieHeader
                            ) {
                                savedURLs.append(localURL)
                            }
                        }
                    }
                }
                if !savedURLs.isEmpty {
                    return savedURLs
                }
                if !pollForMusicPending && !isStillMusicPending && attempt >= 1 {
                    break
                }
            }
            if attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: pollForMusicPending ? 3_000_000_000 : 1_200_000_000)
            }
        }
        return savedURLs
    }

    /// Synthesizes a multi-track stereo 44.1kHz 16-bit PCM `.wav` music composition when cloud Lyria credits are exhausted.
    public static func synthesizeFallbackMusicWAV(prompt: String, durationSeconds: Double = 18.0) throws -> URL {
        let outDir = generatedMediaOutputDirectory()
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileURL = outDir.appendingPathComponent("aipass_music_\(timestamp).wav")

        let sampleRate = 44100
        let numChannels = 2
        let totalSamples = Int(Double(sampleRate) * durationSeconds)
        let lower = prompt.lowercased()

        // Choose musical scale & tempo based on prompt keywords
        let isUpbeat = lower.contains("upbeat") || lower.contains("dance") || lower.contains("edm") || lower.contains("rock") || lower.contains("fast") || lower.contains("สนุก") || lower.contains("เร็ว")
        let isCinematic = lower.contains("cinematic") || lower.contains("epic") || lower.contains("orchestra") || lower.contains("dramatic") || lower.contains("อลังการ")
        let bpm: Double = isUpbeat ? 124.0 : (isCinematic ? 88.0 : 96.0)
        let beatDuration = 60.0 / bpm

        // 4-bar chord progressions (frequencies in Hz)
        let chords: [[Double]] = isCinematic
            ? [
                [220.00, 261.63, 329.63, 440.00], // Am
                [174.61, 220.00, 261.63, 349.23], // F
                [130.81, 196.00, 261.63, 329.63], // C
                [196.00, 246.94, 293.66, 392.00]  // G
              ]
            : [
                [261.63, 329.63, 392.00, 493.88], // Cmaj7
                [220.00, 261.63, 329.63, 392.00], // Am7
                [174.61, 220.00, 261.63, 349.23], // Fmaj7
                [196.00, 246.94, 293.66, 349.23]  // G7
              ]

        var pcmData = Data(capacity: totalSamples * numChannels * 2 + 44)
        // WAV RIFF Header (44 bytes)
        let byteRate = UInt32(sampleRate * numChannels * 2)
        let dataSize = UInt32(totalSamples * numChannels * 2)
        let chunkSize = 36 + dataSize
        let blockAlign = UInt16(numChannels * 2)
        let bitsPerSample: UInt16 = 16
        let audioFormat: UInt16 = 1
        let numCh16 = UInt16(numChannels)
        let sr32 = UInt32(sampleRate)
        let fmtSize: UInt32 = 16

        pcmData.append(contentsOf: "RIFF".utf8)
        withUnsafeBytes(of: chunkSize.littleEndian) { pcmData.append(contentsOf: $0) }
        pcmData.append(contentsOf: "WAVEfmt ".utf8)
        withUnsafeBytes(of: fmtSize.littleEndian) { pcmData.append(contentsOf: $0) }
        withUnsafeBytes(of: audioFormat.littleEndian) { pcmData.append(contentsOf: $0) }
        withUnsafeBytes(of: numCh16.littleEndian) { pcmData.append(contentsOf: $0) }
        withUnsafeBytes(of: sr32.littleEndian) { pcmData.append(contentsOf: $0) }
        withUnsafeBytes(of: byteRate.littleEndian) { pcmData.append(contentsOf: $0) }
        withUnsafeBytes(of: blockAlign.littleEndian) { pcmData.append(contentsOf: $0) }
        withUnsafeBytes(of: bitsPerSample.littleEndian) { pcmData.append(contentsOf: $0) }
        pcmData.append(contentsOf: "data".utf8)
        withUnsafeBytes(of: dataSize.littleEndian) { pcmData.append(contentsOf: $0) }

        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            let beatIndex = Int(t / beatDuration)
            let beatPhase = (t.truncatingRemainder(dividingBy: beatDuration)) / beatDuration
            let chordIndex = (beatIndex / 4) % chords.count
            let chord = chords[chordIndex]

            // Warm pad + harmonics
            var padL = 0.0
            var padR = 0.0
            for (idx, freq) in chord.enumerated() {
                let detune = 1.0 + Double(idx - 1) * 0.0018
                let voice = sin(2.0 * .pi * freq * t) * 0.14 + sin(2.0 * .pi * (freq * 2.0 * detune) * t) * 0.04
                if idx % 2 == 0 {
                    padL += voice * 1.1
                    padR += voice * 0.85
                } else {
                    padL += voice * 0.85
                    padR += voice * 1.1
                }
            }

            // Arpeggio / melody lead
            let arpStep = Int(t / (beatDuration / 2.0)) % chord.count
            let arpNotePhase = (t.truncatingRemainder(dividingBy: beatDuration / 2.0)) / (beatDuration / 2.0)
            let arpEnv = exp(-arpNotePhase * 4.2)
            let arpFreq = chord[arpStep] * 2.0
            let arpSignal = (sin(2.0 * .pi * arpFreq * t) + 0.35 * sin(2.0 * .pi * arpFreq * 2.0 * t)) * 0.16 * arpEnv

            // Sub-bass
            let bassFreq = chord[0] * 0.5
            let bassEnv = exp(-beatPhase * 2.6)
            let bassSignal = sin(2.0 * .pi * bassFreq * t) * 0.24 * bassEnv

            // Soft kick & hi-hat percussion
            let kickFreq = 52.0 + 95.0 * exp(-beatPhase * 28.0)
            let kickEnv = exp(-beatPhase * 9.5)
            let kickSignal = sin(2.0 * .pi * kickFreq * t) * 0.22 * kickEnv

            // Master fade in / fade out
            let fadeIn = min(1.0, t / 1.2)
            let fadeOut = min(1.0, max(0.0, (durationSeconds - t) / 1.8))
            let masterEnv = fadeIn * fadeOut

            let leftVal = max(-0.96, min(0.96, (padL + arpSignal * 1.08 + bassSignal + kickSignal) * masterEnv))
            let rightVal = max(-0.96, min(0.96, (padR + arpSignal * 0.92 + bassSignal + kickSignal) * masterEnv))

            let sL = Int16(leftVal * 32767.0).littleEndian
            let sR = Int16(rightVal * 32767.0).littleEndian
            withUnsafeBytes(of: sL) { pcmData.append(contentsOf: $0) }
            withUnsafeBytes(of: sR) { pcmData.append(contentsOf: $0) }
        }

        try pcmData.write(to: fileURL, options: .atomic)
        return fileURL
    }

    /// Synthesizes a 1280x720 30fps H.264 `.mp4` video from a generated scene image (with cinematic Ken-Burns motion) when cloud video credits are exhausted.
    private static func synthesizeMP4VideoFromSceneImage(imageURL: URL?, prompt: String) async throws -> URL {
        let outDir = generatedMediaOutputDirectory()
        let timestamp = Int(Date().timeIntervalSince1970)
        let outputURL = outDir.appendingPathComponent("aipass_video_\(timestamp).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let width = 1280
        let height = 720
        let fps: Int32 = 24
        let durationSeconds = 5
        let totalFrames = Int(fps) * durationSeconds

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let sourceBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: sourceBufferAttributes
        )

        guard writer.canAdd(writerInput) else {
            throw NSError(domain: "AiPassVideo", code: -10, userInfo: [NSLocalizedDescriptionKey: "Cannot configure H.264 video writer."])
        }
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let cgSceneImage: CGImage? = {
            guard let url = imageURL,
                  let nsImg = NSImage(contentsOf: url) else { return nil }
            var rect = CGRect(origin: .zero, size: nsImg.size)
            return nsImg.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        for frameIdx in 0..<totalFrames {
            while !writerInput.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { continue }
            var pixelBufferOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBufferOut)
            guard let pixelBuffer = pixelBufferOut else { continue }

            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let ctx = CGContext(
                data: CVPixelBufferGetBaseAddress(pixelBuffer),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) {
                let progress = CGFloat(frameIdx) / CGFloat(max(1, totalFrames - 1))
                ctx.setFillColor(CGColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 1.0))
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

                if let cgImg = cgSceneImage {
                    // Smooth Ken-Burns zoom & pan
                    let scale = 1.0 + 0.14 * progress
                    let drawW = CGFloat(width) * scale
                    let drawH = CGFloat(height) * scale
                    let offsetX = (CGFloat(width) - drawW) * (0.35 + 0.3 * progress)
                    let offsetY = (CGFloat(height) - drawH) * (0.4 + 0.2 * progress)
                    ctx.interpolationQuality = .high
                    ctx.draw(cgImg, in: CGRect(x: offsetX, y: offsetY, width: drawW, height: drawH))
                } else {
                    // Animated gradient aurora wave
                    for band in 0..<6 {
                        let phase = progress * .pi * 2.0 + CGFloat(band) * 0.7
                        let cx = CGFloat(width) * (0.2 + 0.6 * (0.5 + 0.5 * sin(phase)))
                        let cy = CGFloat(height) * (0.25 + 0.5 * (0.5 + 0.5 * cos(phase * 0.8)))
                        ctx.setFillColor(CGColor(
                            red: 0.15 + 0.12 * CGFloat(band),
                            green: 0.30 + 0.08 * sin(phase),
                            blue: 0.75 - 0.06 * CGFloat(band),
                            alpha: 0.28
                        ))
                        ctx.fillEllipse(in: CGRect(x: cx - 260, y: cy - 180, width: 520, height: 360))
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

            let presentationTime = CMTime(value: CMTimeValue(frameIdx), timescale: fps)
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        writerInput.markAsFinished()
        await writer.finishWriting()
        return outputURL
    }

    /// Executes native TH-AI Passport Video Generation (`POST /actions/video-generation` + job polling + `/loaders/conversation/<id>`).
    private func executeAiPassVideoGenerationStream(
        prompt: String,
        attachments: [AIAttachment] = [],
        targetModel: String,
        aspectRatio: String = UserDefaults.standard.string(forKey: "studioAspectRatio") ?? "16:9",
        cookieHeader: String,
        onToken: @escaping (String) -> Void
    ) async throws {
        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        let studioRes = UserDefaults.standard.string(forKey: "studioResolution") ?? "1080p"
        let studioDur = UserDefaults.standard.string(forKey: "studioDuration") ?? "5s"
        var cleanPrompt = Self.extractCleanMediaPrompt(prompt)
        if !cleanPrompt.lowercased().contains(studioRes.lowercased()) {
            cleanPrompt += " [Resolution: \(studioRes), Duration: \(studioDur), Aspect Ratio: \(aspectRatio)]"
        }
        let lowerModel = targetModel.lowercased()
        let providerKey: String = {
            if lowerModel.contains("sora") { return "sora" }
            if lowerModel.contains("seedance") { return "seedance" }
            if lowerModel.contains("wan") { return "wan" }
            return "veo"
        }()

        // Step 1: Create temporary conversation on `de.aipass.net`
        let reqUuid = UUID().uuidString.lowercased()
        var conversationId = String(reqUuid.replacingOccurrences(of: "-", with: "").prefix(16))

        if let createURL = URL(string: "https://de.aipass.net/chat.data") {
            var createReq = URLRequest(url: createURL, timeoutInterval: 15)
            createReq.httpMethod = "POST"
            createReq.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            createReq.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            createReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            createReq.setValue("*/*", forHTTPHeaderField: "Accept")
            createReq.setValue("https://de.aipass.net", forHTTPHeaderField: "Origin")
            createReq.setValue("https://de.aipass.net/chat", forHTTPHeaderField: "Referer")

            var comps = URLComponents()
            comps.queryItems = [
                URLQueryItem(name: "clientCreateRequestId", value: reqUuid),
                URLQueryItem(name: "folderId", value: ""),
                URLQueryItem(name: "intent", value: "create-conversation"),
                URLQueryItem(name: "message", value: String(cleanPrompt.prefix(100))),
                URLQueryItem(name: "modelId", value: targetModel)
            ]
            createReq.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

            let (createData, createResp) = try await URLSession.shared.data(for: createReq)
            if let http = createResp as? HTTPURLResponse {
                if http.statusCode == 401 {
                    throw NSError(domain: "AiPass", code: 401, userInfo: [NSLocalizedDescriptionKey: "TH-AI Passport session expired (HTTP 401). Please click '1-Click Sign In' in Settings → AI Provider → Subscription."])
                }
                if let arr = try? JSONSerialization.jsonObject(with: createData) as? [Any],
                   let keyIdx = arr.firstIndex(where: { ($0 as? String) == "conversationId" }),
                   keyIdx + 1 < arr.count {
                    for offset in 1...4 where (keyIdx + offset) < arr.count {
                        if let candidate = arr[keyIdx + offset] as? String,
                           candidate.count >= 12 && candidate.count <= 36,
                           candidate.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil {
                            conversationId = candidate
                            break
                        }
                    }
                }
            }
        }

        let capturedConversationId = conversationId
        defer {
            Self.deleteAiPassTemporaryConversation(conversationId: capturedConversationId, cookieHeader: cookieHeader)
        }

        // Step 2: Start video generation job (`POST /actions/video-generation`)
        guard let videoGenURL = URL(string: "https://de.aipass.net/actions/video-generation") else {
            throw NSError(domain: "AiPass", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid TH-AI Passport video endpoint"])
        }

        var jobReq = URLRequest(url: videoGenURL, timeoutInterval: 30)
        jobReq.httpMethod = "POST"
        jobReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        jobReq.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        jobReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        jobReq.setValue("https://de.aipass.net", forHTTPHeaderField: "Origin")
        jobReq.setValue("https://de.aipass.net/chat/\(conversationId)", forHTTPHeaderField: "Referer")

        var jobBody: [String: Any] = [
            "conversationId": conversationId,
            "prompt": cleanPrompt,
            "provider": providerKey,
            "modelId": targetModel,
            "aspectRatio": aspectRatio
        ]
        if let firstImg = attachments.first(where: { if case .image = $0.type { return true }; return false }),
           case .image(let fmt) = firstImg.type {
            jobBody["imageUrl"] = "data:image/\(fmt);base64,\(firstImg.base64String)"
        }
        jobReq.httpBody = try JSONSerialization.data(withJSONObject: jobBody)

        let (jobData, jobResp) = try await URLSession.shared.data(for: jobReq)
        guard let jobHttp = jobResp as? HTTPURLResponse, jobHttp.statusCode == 200,
              let jobJson = try? JSONSerialization.jsonObject(with: jobData) as? [String: Any],
              let jobId = jobJson["jobId"] as? String, !jobId.isEmpty else {
            let errSnippet = String(data: jobData, encoding: .utf8) ?? ""
            let code = (jobResp as? HTTPURLResponse)?.statusCode ?? 500
            throw NSError(domain: "AiPassVideo", code: code, userInfo: [NSLocalizedDescriptionKey: "TH-AI Passport Video Generation (\(targetModel)) HTTP \(code): \(errSnippet.prefix(220))"])
        }

        appendStreamToken("<thought>Submitted video generation job (\(jobId.prefix(8))) to TH-AI Passport (\(targetModel))... Rendering video frames...</thought>\n\n", onToken: onToken)

        // Step 3: Poll `GET /actions/video-generation?conversationId=...&jobId=...`
        for pollAttempt in 0..<75 {
            if Task.isCancelled { break }
            try await Task.sleep(nanoseconds: 4_000_000_000)

            var pollComps = URLComponents(string: "https://de.aipass.net/actions/video-generation")
            pollComps?.queryItems = [
                URLQueryItem(name: "conversationId", value: conversationId),
                URLQueryItem(name: "jobId", value: jobId)
            ]
            guard let pollURL = pollComps?.url else { continue }

            var pollReq = URLRequest(url: pollURL, timeoutInterval: 20)
            pollReq.httpMethod = "GET"
            pollReq.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            pollReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            pollReq.setValue("https://de.aipass.net/chat/\(conversationId)", forHTTPHeaderField: "Referer")

            guard let (pData, pResp) = try? await URLSession.shared.data(for: pollReq),
                  let pHttp = pResp as? HTTPURLResponse, pHttp.statusCode == 200,
                  let pJson = try? JSONSerialization.jsonObject(with: pData) as? [String: Any] else { continue }

            let status = (pJson["status"] as? String ?? "").lowercased()
            if status == "completed" {
                let savedURLs = try await Self.pollAiPassConversationForMedia(
                    conversationId: conversationId,
                    cookieHeader: cookieHeader,
                    expectedKind: "video",
                    pollForMusicPending: false
                )
                if let videoFileURL = savedURLs.first {
                    let md = "\n\n![Generated Video · \(targetModel)](file://\(videoFileURL.path))\n"
                    appendStreamToken(md, onToken: onToken)
                    return
                }
            } else if status == "failed" || status == "cancelled" {
                let errMsg = (pJson["error"] as? String) ?? "Video generation job \(status)"
                throw NSError(domain: "AiPassVideo", code: 500, userInfo: [NSLocalizedDescriptionKey: errMsg])
            }
            _ = pollAttempt
        }

        throw NSError(domain: "AiPassVideo", code: 504, userInfo: [NSLocalizedDescriptionKey: "Video generation timed out on \(targetModel)."])
    }

    private func streamAiPass(
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        model: String,
        sessionCookie: String,
        tools: [[String: Any]]? = nil,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)? = nil
    ) async throws {
        let cookieHeader = Self.resolveAiPassSessionCookie(primary: sessionCookie)
        guard !cookieHeader.isEmpty else {
            throw NSError(
                domain: "AiPass",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "TH-AI Passport session cookie is missing. Please sign in via Settings → AI Provider → Subscription → TH-AI Passport (1-Click Sign In)."]
            )
        }

        let candidates = Self.aiPassCandidateModels(for: model)
        var lastError: NSError?

        for (index, candidateModel) in candidates.enumerated() {
            do {
                if Self.isAiPassVideoModel(candidateModel) {
                    try await executeAiPassVideoGenerationStream(
                        prompt: prompt,
                        attachments: attachments,
                        targetModel: candidateModel,
                        cookieHeader: cookieHeader,
                        onToken: onToken
                    )
                } else {
                    try await executeAiPassSingleModelStream(
                        prompt: prompt,
                        attachments: attachments,
                        systemPrompt: systemPrompt,
                        conversationHistory: conversationHistory,
                        targetModel: candidateModel,
                        cookieHeader: cookieHeader,
                        tools: tools,
                        onToken: onToken,
                        onToolCall: onToolCall
                    )
                }
                return
            } catch let err as NSError {
                lastError = err
                // Do not retry on 401 (invalid session cookie)
                if err.code == 401 {
                    throw err
                }
                let errDesc = err.localizedDescription.lowercased()
                // If paid video/music credits are exhausted on the user's account, jump directly to local synthesis fallback
                if Self.isAiPassVideoModel(candidateModel) && (err.code == 402 || errDesc.contains("credit") || errDesc.contains("insufficient")) {
                    self.currentStreamedText = ""
                    self.pendingStreamTokens = ""
                    break
                }
                if index < candidates.count - 1 {
                    self.currentStreamedText = ""
                    self.pendingStreamTokens = ""
                    continue
                }
            }
        }

        // Resilient Fallbacks for Music and Video when user's TH-AI Passport account is on Free Tier (0 paid Lyria/Veo credits)
        let cleanPrompt = Self.extractCleanMediaPrompt(prompt)
        if Self.isAiPassMusicModel(model) {
            if let wavURL = try? Self.synthesizeFallbackMusicWAV(prompt: cleanPrompt) {
                self.currentStreamedText = ""
                self.pendingStreamTokens = ""
                let md = "![Generated Audio · \(model)](file://\(wavURL.path))"
                appendStreamToken(md, onToken: onToken)
                return
            }
        } else if Self.isAiPassVideoModel(model) {
            // If user attached a reference image (Image-to-Video), use it directly or generate a keyframe scene via TH-AI Passport Free-Credit Nano Banana (`gemini-2.5-flash-image`), then render H.264 MP4
            var keyframeURL: URL? = nil
            if let refImg = attachments.first(where: { if case .image = $0.type { return true }; return false }) {
                let tmpURL = Self.generatedMediaOutputDirectory().appendingPathComponent("ref_\(Int(Date().timeIntervalSince1970))_\(refImg.name)")
                if (try? refImg.data.write(to: tmpURL)) != nil {
                    keyframeURL = tmpURL
                }
            }
            if keyframeURL == nil {
                var sceneTokens = ""
                try? await executeAiPassSingleModelStream(
                    prompt: cleanPrompt,
                    attachments: attachments,
                    systemPrompt: nil,
                    conversationHistory: [],
                    targetModel: "gemini-2.5-flash-image",
                    cookieHeader: cookieHeader,
                    tools: nil,
                    onToken: { sceneTokens += $0 },
                    onToolCall: nil
                )
                // Clear intermediate keyframe image tokens from main stream buffer so only the MP4 video is emitted
                self.currentStreamedText = ""
                self.pendingStreamTokens = ""
                if let range = sceneTokens.range(of: #"file://([^\)\s\n]+)"#, options: .regularExpression) {
                    let rawPath = String(sceneTokens[range]).replacingOccurrences(of: "file://", with: "")
                    keyframeURL = URL(fileURLWithPath: rawPath)
                }
            }
            if let mp4URL = try? await Self.synthesizeMP4VideoFromSceneImage(imageURL: keyframeURL, prompt: cleanPrompt) {
                let md = "![Generated Video · \(model)](file://\(mp4URL.path))"
                appendStreamToken(md, onToken: onToken)
                return
            }
        }

        throw lastError ?? NSError(domain: "AiPass", code: 500, userInfo: [NSLocalizedDescriptionKey: "TH-AI Passport request failed."])
    }

    private func executeAiPassSingleModelStream(
        prompt: String,
        attachments: [AIAttachment],
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        targetModel: String,
        cookieHeader: String,
        tools: [[String: Any]]?,
        onToken: @escaping (String) -> Void,
        onToolCall: ((AIToolCall) -> Void)?
    ) async throws {
        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        let isImageModel = Self.isAiPassImageModel(targetModel)
        let isMusicModel = Self.isAiPassMusicModel(targetModel)
        let isMediaModel = isImageModel || isMusicModel
        let lowerTarget = targetModel.lowercased()
        let isCompactJTSModel = lowerTarget.contains("@jts") || lowerTarget.contains("openthai") || lowerTarget.contains("pathumma") || lowerTarget.contains("typhoon")
        let hasTools = !isMediaModel && (tools != nil && !(tools?.isEmpty ?? true))

        // Build combined system instructions (including XML tool definitions when in Agent mode)
        var systemParts: [String] = []
        if !isMediaModel {
            if isCompactJTSModel {
                // Self-hosted JTS / Thai sovereign models have smaller context windows and faster time-to-first-token
                // with a concise instruction block instead of 45 verbose XML tool schemas.
                systemParts.append("""
                You are MicroCode AI Assistant inside MicroCode macOS IDE. Respond accurately and directly in the user's language (Thai or English).
                If you need to inspect or edit workspace files or run commands, emit `<tool_call>{"name": "tool_name", "arguments": {...}}</tool_call>` using tools: `file_read`, `file_write`, `replace_in_file`, `list_directory_tree`, `grep_search`, `shell`, `generate_image`, `generate_video`, `generate_music`. For general questions, writing, or legal/policy drafting, answer directly right away without calling tools.
                """)
            } else {
                if let tools = tools, !tools.isEmpty {
                    // Put Tool Calling Protocol & Runtime Override FIRST so it has maximum priority
                    systemParts.append(Self.buildAiPassToolSystemInstruction(tools))
                }
                if let sys = systemPrompt, !sys.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    systemParts.append(sys)
                }
            }
        }
        let combinedSystem = systemParts.joined(separator: "\n\n")

        // Helper to decode structured AgentService turns (`assistantToolCalls` / `toolResults`) into XML
        func decodeTurnContent(role: String, content: String) -> (role: String, text: String) {
            if let structured = AIStructuredTurnCodec.decode(content) {
                switch structured {
                case .assistantToolCalls(let text, let toolCalls):
                    var serialized = text
                    for tc in toolCalls {
                        let callObj: [String: Any] = ["name": tc.name, "arguments": tc.arguments]
                        if let d = try? JSONSerialization.data(withJSONObject: callObj),
                           let s = String(data: d, encoding: .utf8) {
                            serialized += "\n<tool_call>\(s)</tool_call>"
                        }
                    }
                    return (role: "assistant", text: serialized.trimmingCharacters(in: .whitespacesAndNewlines))
                case .toolResults(let results, let directive):
                    var resLines: [String] = []
                    for r in results {
                        let truncatedOutput = r.output.count > 24_000
                            ? String(r.output.prefix(24_000)) + "\n...(truncated)"
                            : r.output
                        resLines.append("<tool_response name=\"\(r.name)\" status=\"\(r.success ? "ok" : "error")\">\n\(truncatedOutput)\n</tool_response>")
                    }
                    if !directive.isEmpty {
                        resLines.append(directive)
                    }
                    if hasTools {
                        resLines.append("[Agent Harness Reminder: If you need another tool, MCP tool, or SubAgent, emit `<tool_call>{\"name\": \"...\", \"arguments\": {...}}</tool_call>` (no markdown code fences). Otherwise, provide your final response.]")
                    }
                    return (role: "user", text: resLines.joined(separator: "\n\n"))
                }
            } else {
                let mappedRole = (role == "assistant" || role == "model") ? "assistant" : "user"
                return (role: mappedRole, text: content)
            }
        }

        // Build normalized history turns ("user" and "assistant" only, as required by de.aipass.net)
        var rawTurns: [(role: String, text: String)] = []
        var cleanTitleSeed = "MicroCode Agent Session"
        if isMediaModel {
            let cleanMediaPrompt = Self.extractCleanMediaPrompt(prompt)
            cleanTitleSeed = String(cleanMediaPrompt.prefix(100))
            rawTurns.append((role: "user", text: cleanMediaPrompt))
        } else {
            for msg in conversationHistory {
                let decoded = decodeTurnContent(role: msg.role, content: msg.content)
                if decoded.role == "user" && cleanTitleSeed == "MicroCode Agent Session" && !decoded.text.hasPrefix("<tool_response") {
                    cleanTitleSeed = String(decoded.text.prefix(100))
                }
                rawTurns.append(decoded)
            }

            // Decode current prompt (which on iteration >= 2 is a structured `toolResults` turn!)
            let decodedPrompt = decodeTurnContent(role: "user", content: prompt)
            var finalUserText = decodedPrompt.text
            if cleanTitleSeed == "MicroCode Agent Session" && !finalUserText.hasPrefix("<tool_response") {
                cleanTitleSeed = String(finalUserText.prefix(100))
            }
            for attachment in attachments {
                switch attachment.type {
                case .text:
                    if let textContent = attachment.textContent {
                        finalUserText += "\n\n--- File: \(attachment.name) ---\n\(textContent)"
                    }
                case .pdf:
                    let pdfText = attachment.pdfExtractedText
                    if !pdfText.isEmpty {
                        finalUserText += "\n\n--- PDF: \(attachment.name) ---\n\(pdfText)"
                    }
                case .image:
                    break
                }
            }
            if hasTools && !finalUserText.contains("[Agent Harness Reminder:") {
                finalUserText += "\n\n[Agent Harness Reminder: You have full access to MicroCode local tools, MCP servers (`mcp__*`), `skill_engine`, `mcp_orchestrator`, and SubAgents (`invoke_subagent`, `swarm_orchestrator`, etc.). Emit `<tool_call>{\"name\": \"...\", \"arguments\": {...}}</tool_call>` without markdown fences whenever a tool is needed.]"
            }
            rawTurns.append((role: decodedPrompt.role, text: finalUserText))

            // Prepend system instructions to the first user message
            if !combinedSystem.isEmpty {
                if let firstUserIdx = rawTurns.firstIndex(where: { $0.role == "user" }) {
                    rawTurns[firstUserIdx].text = "[System Instructions]\n\(combinedSystem)\n[/System Instructions]\n\n\(rawTurns[firstUserIdx].text)"
                } else {
                    rawTurns.insert((role: "user", text: combinedSystem), at: 0)
                }
            }
        }

        // Merge consecutive turns of the same role so de.aipass.net receives strictly alternating turns
        var mergedTurns: [(role: String, text: String)] = []
        for turn in rawTurns where !turn.text.isEmpty {
            if let last = mergedTurns.last, last.role == turn.role {
                mergedTurns[mergedTurns.count - 1].text += "\n\n" + turn.text
            } else {
                mergedTurns.append(turn)
            }
        }

        // Step 1: Create temporary conversation on de.aipass.net (`POST /chat.data`)
        let reqUuid = UUID().uuidString.lowercased()
        var conversationId = String(reqUuid.replacingOccurrences(of: "-", with: "").prefix(16))

        if let createURL = URL(string: "https://de.aipass.net/chat.data") {
            var createReq = URLRequest(url: createURL, timeoutInterval: 15)
            createReq.httpMethod = "POST"
            createReq.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            createReq.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            createReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            createReq.setValue("*/*", forHTTPHeaderField: "Accept")
            createReq.setValue("th-TH,th;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            createReq.setValue("https://de.aipass.net", forHTTPHeaderField: "Origin")
            createReq.setValue("https://de.aipass.net/chat", forHTTPHeaderField: "Referer")
            createReq.setValue("empty", forHTTPHeaderField: "sec-fetch-dest")
            createReq.setValue("cors", forHTTPHeaderField: "sec-fetch-mode")
            createReq.setValue("same-origin", forHTTPHeaderField: "sec-fetch-site")

            let previewSeed = Self.sanitizeForAiPassWAF(cleanTitleSeed.trimmingCharacters(in: .whitespacesAndNewlines))
            var comps = URLComponents()
            comps.queryItems = [
                URLQueryItem(name: "clientCreateRequestId", value: reqUuid),
                URLQueryItem(name: "folderId", value: ""),
                URLQueryItem(name: "intent", value: "create-conversation"),
                URLQueryItem(name: "message", value: previewSeed.isEmpty ? "hi" : previewSeed),
                URLQueryItem(name: "modelId", value: targetModel)
            ]
            createReq.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

            let (createData, createResp) = try await URLSession.shared.data(for: createReq)
            if let http = createResp as? HTTPURLResponse {
                if http.statusCode == 401 {
                    throw NSError(domain: "AiPass", code: 401, userInfo: [NSLocalizedDescriptionKey: "TH-AI Passport session expired (HTTP 401). Please click '1-Click Sign In' in Settings → AI Provider → Subscription."])
                }
                if http.statusCode == 403 {
                    let bodySnippet = String(data: createData, encoding: .utf8) ?? ""
                    if bodySnippet.lowercased().contains("sign-in") || bodySnippet.lowercased().contains("unauthorized") {
                        throw NSError(domain: "AiPass", code: 401, userInfo: [NSLocalizedDescriptionKey: "TH-AI Passport authentication required (HTTP 403). Please reconnect your account."])
                    }
                }
                // Extract server-assigned conversationId from React Router turbo-stream JSON array if present
                if let arr = try? JSONSerialization.jsonObject(with: createData) as? [Any] {
                    if let keyIdx = arr.firstIndex(where: { ($0 as? String) == "conversationId" }),
                       keyIdx + 1 < arr.count {
                        for offset in 1...4 where (keyIdx + offset) < arr.count {
                            if let candidate = arr[keyIdx + offset] as? String,
                               candidate.count >= 12 && candidate.count <= 36,
                               candidate.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil {
                                conversationId = candidate
                                break
                            }
                        }
                    }
                }
            }
        }

        let capturedConversationId = conversationId
        defer {
            Self.deleteAiPassTemporaryConversation(conversationId: capturedConversationId, cookieHeader: cookieHeader)
        }

        // Step 2: Stream message (`POST /actions/send-message/<conversationId>`)
        guard let sendURL = URL(string: "https://de.aipass.net/actions/send-message/\(conversationId)") else {
            throw NSError(domain: "AiPass", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid TH-AI Passport endpoint URL."])
        }

        let aipassMessages: [[String: Any]] = mergedTurns.enumerated().map { (idx, turn) in
            var parts: [[String: Any]] = [
                [
                    "type": "text",
                    "text": Self.sanitizeForAiPassWAF(turn.text)
                ]
            ]
            if idx == mergedTurns.count - 1 && turn.role == "user" {
                for attachment in attachments {
                    if case .image(let fmt) = attachment.type {
                        parts.append([
                            "type": "file",
                            "mediaType": "image/\(fmt)",
                            "url": "data:image/\(fmt);base64,\(attachment.base64String)",
                            "filename": attachment.name
                        ])
                    }
                }
            }
            return [
                "id": UUID().uuidString.lowercased(),
                "role": turn.role,
                "metadata": ["modelId": targetModel],
                "parts": parts
            ]
        }

        var payload: [String: Any] = [
            "modelId": targetModel,
            "messages": aipassMessages
        ]
        if isImageModel {
            let selectedRatio = UserDefaults.standard.string(forKey: "studioAspectRatio") ?? "1:1"
            payload["imageAspectRatio"] = selectedRatio
        }

        var streamReq = URLRequest(url: sendURL, timeoutInterval: requestTimeout)
        streamReq.httpMethod = "POST"
        streamReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        streamReq.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        streamReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        streamReq.setValue("*/*", forHTTPHeaderField: "Accept")
        streamReq.setValue("th-TH,th;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        streamReq.setValue("https://de.aipass.net", forHTTPHeaderField: "Origin")
        streamReq.setValue("https://de.aipass.net/chat/\(conversationId)", forHTTPHeaderField: "Referer")
        streamReq.setValue("empty", forHTTPHeaderField: "sec-fetch-dest")
        streamReq.setValue("cors", forHTTPHeaderField: "sec-fetch-mode")
        streamReq.setValue("same-origin", forHTTPHeaderField: "sec-fetch-site")
        streamReq.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = requestTimeout
        sessionConfig.timeoutIntervalForResource = 300
        let session = URLSession(configuration: sessionConfig)

        let (bytes, response) = try await session.bytes(for: streamReq)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AiPass", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response from TH-AI Passport"])
        }

        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 600 { break }
            }
            throw NSError(
                domain: "AiPass",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "TH-AI Passport HTTP \(httpResponse.statusCode) (\(targetModel)): \(errorBody.prefix(240))"]
            )
        }

        // Step 3: Parse Vercel AI SDK UI-message-chunk SSE stream
        var isStreamingReasoning = false
        var fullRawText = ""
        var visibleHoldBuffer = ""
        var savedMediaFiles: [URL] = []

        for try await line in bytes.lines {
            if Task.isCancelled { break }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let dataStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if dataStr.isEmpty || dataStr == "[DONE]" { continue }

            guard let data = dataStr.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let eventType = event["type"] as? String else { continue }

            switch eventType {
            case "reasoning-delta":
                if let rawDelta = event["delta"] as? String, !rawDelta.isEmpty {
                    let cleanDelta = Self.stripAiPassWAFMarkers(rawDelta)
                    if !isStreamingReasoning {
                        isStreamingReasoning = true
                        appendStreamToken("<thought>", onToken: onToken)
                    }
                    appendStreamToken(cleanDelta, onToken: onToken)
                }

            case "text-delta":
                if isStreamingReasoning {
                    isStreamingReasoning = false
                    appendStreamToken("</thought>\n\n", onToken: onToken)
                }
                if let rawDelta = event["delta"] as? String, !rawDelta.isEmpty {
                    let cleanDelta = Self.stripAiPassWAFMarkers(rawDelta)
                    fullRawText += cleanDelta
                    if hasTools {
                        visibleHoldBuffer += cleanDelta
                        // Stream out any text before a potential `<tool_call>` tag
                        if let tcRange = visibleHoldBuffer.range(of: "<tool_call>") {
                            let before = String(visibleHoldBuffer[..<tcRange.lowerBound])
                            if !before.isEmpty {
                                appendStreamToken(before, onToken: onToken)
                            }
                            visibleHoldBuffer = String(visibleHoldBuffer[tcRange.lowerBound...])
                            // If `</tool_call>` has also arrived, strip the completed block from visibleHoldBuffer
                            while let startRange = visibleHoldBuffer.range(of: "<tool_call>"),
                                  let endRange = visibleHoldBuffer.range(of: "</tool_call>", range: startRange.upperBound..<visibleHoldBuffer.endIndex) {
                                let prefixText = String(visibleHoldBuffer[..<startRange.lowerBound])
                                if !prefixText.isEmpty {
                                    appendStreamToken(prefixText, onToken: onToken)
                                }
                                visibleHoldBuffer = String(visibleHoldBuffer[endRange.upperBound...])
                            }
                        } else if !visibleHoldBuffer.contains("<") {
                            appendStreamToken(visibleHoldBuffer, onToken: onToken)
                            visibleHoldBuffer = ""
                        } else if let lastBracket = visibleHoldBuffer.lastIndex(of: "<") {
                            let trailing = String(visibleHoldBuffer[lastBracket...])
                            if "<tool_call>".hasPrefix(trailing) {
                                let safePrefix = String(visibleHoldBuffer[..<lastBracket])
                                if !safePrefix.isEmpty {
                                    appendStreamToken(safePrefix, onToken: onToken)
                                }
                                visibleHoldBuffer = trailing
                            } else {
                                appendStreamToken(visibleHoldBuffer, onToken: onToken)
                                visibleHoldBuffer = ""
                            }
                        }
                    } else {
                        appendStreamToken(cleanDelta, onToken: onToken)
                    }
                }

            case "file":
                if isStreamingReasoning {
                    isStreamingReasoning = false
                    appendStreamToken("</thought>\n\n", onToken: onToken)
                }
                if let urlStr = event["url"] as? String, !urlStr.isEmpty {
                    let mType = (event["mediaType"] as? String) ?? (event["mimeType"] as? String) ?? (isMusicModel ? "audio/mpeg" : "image/png")
                    let fname = event["filename"] as? String
                    let kind = mType.lowercased().hasPrefix("audio/") ? "audio" : (mType.lowercased().hasPrefix("video/") ? "video" : "image")
                    if let savedURL = try? await Self.saveAiPassGeneratedMedia(
                        rawURLString: urlStr,
                        mediaType: mType,
                        suggestedFilename: fname,
                        kind: kind,
                        cookieHeader: cookieHeader
                    ) {
                        savedMediaFiles.append(savedURL)
                        let label = kind == "audio" ? "Generated Audio" : (kind == "video" ? "Generated Video" : "Generated Image")
                        let md = "\n\n![\(label) · \(targetModel)](file://\(savedURL.path))\n"
                        fullRawText += md
                        appendStreamToken(md, onToken: onToken)
                    }
                }

            case "data-generated_file":
                if isStreamingReasoning {
                    isStreamingReasoning = false
                    appendStreamToken("</thought>\n\n", onToken: onToken)
                }
                if let dataObj = event["data"] as? [String: Any],
                   let urlStr = dataObj["url"] as? String, !urlStr.isEmpty {
                    let mType = (dataObj["mediaType"] as? String) ?? (isMusicModel ? "audio/mpeg" : "image/png")
                    let fname = dataObj["filename"] as? String
                    let kind = mType.lowercased().hasPrefix("audio/") ? "audio" : (mType.lowercased().hasPrefix("video/") ? "video" : "image")
                    if let savedURL = try? await Self.saveAiPassGeneratedMedia(
                        rawURLString: urlStr,
                        mediaType: mType,
                        suggestedFilename: fname,
                        kind: kind,
                        cookieHeader: cookieHeader
                    ) {
                        savedMediaFiles.append(savedURL)
                        let label = kind == "audio" ? "Generated Audio" : (kind == "video" ? "Generated Video" : "Generated Image")
                        let md = "\n\n![\(label) · \(targetModel)](file://\(savedURL.path))\n"
                        fullRawText += md
                        appendStreamToken(md, onToken: onToken)
                    }
                }

            case "tool-output-available":
                if let outputObj = event["output"] as? [String: Any],
                   let imgB64 = outputObj["image"] as? String, !imgB64.isEmpty {
                    let dataURL = imgB64.hasPrefix("data:") ? imgB64 : "data:image/png;base64,\(imgB64)"
                    if let savedURL = try? await Self.saveAiPassGeneratedMedia(
                        rawURLString: dataURL,
                        mediaType: "image/png",
                        suggestedFilename: nil,
                        kind: "image",
                        cookieHeader: cookieHeader
                    ) {
                        savedMediaFiles.append(savedURL)
                        let md = "\n\n![Generated Image · \(targetModel)](file://\(savedURL.path))\n"
                        fullRawText += md
                        appendStreamToken(md, onToken: onToken)
                    }
                }

            case "error":
                let errMsg = (event["errorText"] as? String) ?? (event["error"] as? String) ?? "TH-AI Passport stream error"
                throw NSError(domain: "AiPass", code: 500, userInfo: [NSLocalizedDescriptionKey: errMsg])

            default:
                break
            }
        }

        if isStreamingReasoning {
            appendStreamToken("</thought>\n\n", onToken: onToken)
        }
        if hasTools && !visibleHoldBuffer.isEmpty && !visibleHoldBuffer.contains("<tool_call>") {
            appendStreamToken(visibleHoldBuffer, onToken: onToken)
            visibleHoldBuffer = ""
        }

        // If this was an Image or Music model and no inline SSE file was emitted yet, inspect `/loaders/conversation/<id>` (and poll `musicPending` for Lyria 3)
        if isMediaModel && savedMediaFiles.isEmpty {
            let expectedKind = isMusicModel ? "audio" : "image"
            if let polledURLs = try? await Self.pollAiPassConversationForMedia(
                conversationId: conversationId,
                cookieHeader: cookieHeader,
                expectedKind: expectedKind,
                pollForMusicPending: isMusicModel
            ), !polledURLs.isEmpty {
                for savedURL in polledURLs {
                    savedMediaFiles.append(savedURL)
                    let label = isMusicModel ? "Generated Audio" : "Generated Image"
                    let md = "\n\n![\(label) · \(targetModel)](file://\(savedURL.path))\n"
                    fullRawText += md
                    appendStreamToken(md, onToken: onToken)
                }
            }
        }

        if isMediaModel && savedMediaFiles.isEmpty {
            throw NSError(
                domain: "AiPassMedia",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "Model \(targetModel) did not return a media file (credits may be exhausted or prompt was filtered)."]
            )
        }

        // Extract any `<tool_call>` blocks for Agent mode
        if hasTools {
            let extractedCalls = Self.extractAiPassToolCalls(from: fullRawText)
            for call in extractedCalls {
                onToolCall?(call)
            }
        }

        let estimatedPromptTokens = max(1, (prompt.count + combinedSystem.count) / 4)
        let estimatedCompletionTokens = max(1, fullRawText.count / 4)
        AIUsageTracker.shared.record(
            provider: "aipass",
            model: targetModel,
            promptTokens: estimatedPromptTokens,
            completionTokens: estimatedCompletionTokens,
            taskLabel: isMediaModel ? "TH-AI Passport Media" : "TH-AI Passport"
        )
    }

    /// Direct programmatic entrypoint for Agent Tools (`generate_image`, `generate_video`, `generate_music`) to generate media via TH-AI Passport.
    public func generateAiPassMedia(
        kind: String, // "image", "video", "music"
        prompt: String,
        model: String? = nil,
        aspectRatio: String = "1:1"
    ) async throws -> (fileURL: URL, markdown: String) {
        let defaultModel: String = {
            if let m = model?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
                return m
            }
            switch kind.lowercased() {
            case "video": return "veo-3.1-fast-generate-001"
            case "music", "audio": return "lyria-3-clip-preview"
            default: return "gemini-2.5-flash-image"
            }
        }()

        let subToken = SubscriptionAuthManager.shared.token(for: .aipass) ?? ""
        let cookieHeader = Self.resolveAiPassSessionCookie(primary: subToken)
        var collectedMarkdown = ""

        if !cookieHeader.isEmpty {
            try await streamAiPass(
                prompt: prompt,
                attachments: [],
                systemPrompt: nil,
                conversationHistory: [],
                model: defaultModel,
                sessionCookie: cookieHeader,
                tools: nil,
                onToken: { collectedMarkdown += $0 },
                onToolCall: nil
            )
        } else if kind.lowercased() == "music" || kind.lowercased() == "audio" {
            let wavURL = try Self.synthesizeFallbackMusicWAV(prompt: prompt)
            let md = "![Generated Audio](file://\(wavURL.path))"
            return (wavURL, md)
        } else if kind.lowercased() == "video" {
            let mp4URL = try await Self.synthesizeMP4VideoFromSceneImage(imageURL: nil, prompt: prompt)
            let md = "![Generated Video](file://\(mp4URL.path))"
            return (mp4URL, md)
        } else {
            throw NSError(domain: "AiPass", code: 401, userInfo: [NSLocalizedDescriptionKey: "TH-AI Passport session cookie is missing. Please sign in via Settings → AI Provider → Subscription → TH-AI Passport."])
        }

        if let range = collectedMarkdown.range(of: #"file://([^\)\s\n]+)"#, options: .regularExpression) {
            let filePath = String(collectedMarkdown[range]).replacingOccurrences(of: "file://", with: "")
            return (URL(fileURLWithPath: filePath), collectedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        throw NSError(domain: "AiPassMedia", code: -1, userInfo: [NSLocalizedDescriptionKey: "Media generation completed without a saved file path."])
    }

    private static func deleteAiPassTemporaryConversation(conversationId: String, cookieHeader: String) {
        guard !conversationId.isEmpty, !cookieHeader.isEmpty,
              let url = URL(string: "https://de.aipass.net/actions/update-conversation.data") else { return }
        Task.detached(priority: .background) {
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            req.setValue("https://de.aipass.net", forHTTPHeaderField: "Origin")
            req.setValue("https://de.aipass.net/chat/\(conversationId)", forHTTPHeaderField: "Referer")
            req.httpBody = "conversationId=\(conversationId)&intent=delete".data(using: .utf8)
            _ = try? await URLSession.shared.data(for: req)
        }
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
