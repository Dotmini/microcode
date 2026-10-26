//
//  AIProviderAuthService.swift
//  MicroCode
//
//  Production AI Provider Authentication & Key Management
//  Supports: OpenAI, Anthropic (Claude), DeepSeek, Gemini, Grok, Qwen, GLM, Codex
//  Secure Keychain storage with live connection validation and dynamic model discovery.
//
//  Created & Designed by Dotmini Software
//  Founder & CEO: Tirawat Nantamas
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation
import Security
import CryptoKit
import SwiftUI

// MARK: - Provider Configuration

struct AIProviderConfig: Identifiable, Codable, Equatable {
    let id: String
    let provider: String
    var apiKey: String
    var organizationId: String?
    var selectedModel: String
    var isActive: Bool
    var lastValidated: Date?
    var isValid: Bool
    var availableModels: [String]
    var displayName: String
    var usageQuota: UsageQuota?
    
    struct UsageQuota: Codable, Equatable {
        var totalTokens: Int
        var usedTokens: Int
        var remainingTokens: Int
        var resetDate: Date?
    }
}

// MARK: - Provider Metadata

enum AIProviderMeta: String, CaseIterable, Identifiable {
    case openai, anthropic, deepseek, gemini, openrouter, groq, mistral, kimi, perplexity, perch, typhoon, cerebras, together, fireworks, minimax, nvidia, grok, codex, qwen, glm
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Claude (Anthropic)"
        case .deepseek: return "DeepSeek"
        case .gemini: return "Google Gemini"
        case .openrouter: return "OpenRouter"
        case .groq: return "Groq (LPU Inference)"
        case .mistral: return "Mistral AI & Codestral"
        case .kimi: return "Moonshot AI (Kimi)"
        case .perplexity: return "Perplexity Sonar"
        case .perch: return "Perch AI"
        case .typhoon: return "SCB 10X Typhoon"
        case .cerebras: return "Cerebras Inference"
        case .together: return "Together AI"
        case .fireworks: return "Fireworks AI"
        case .minimax: return "MiniMax"
        case .nvidia: return "NVIDIA NIM"
        case .grok: return "Grok (xAI)"
        case .qwen: return "Qwen (Alibaba)"
        case .glm: return "GLM (Zhipu AI)"
        case .codex: return "Codex (OpenAI)"
        }
    }
    
    var icon: String {
        switch self {
        case .openai: return "brain.head.profile"
        case .anthropic: return "bubble.left.and.text.bubble.right"
        case .deepseek: return "water.waves"
        case .gemini: return "sparkles"
        case .openrouter: return "point.3.connected.trianglepath.dotted"
        case .groq: return "bolt.horizontal.fill"
        case .mistral: return "wind"
        case .kimi: return "moon.stars.fill"
        case .perplexity: return "magnifyingglass.circle.fill"
        case .perch: return "bird.fill"
        case .typhoon: return "hurricane"
        case .cerebras: return "memorychip.fill"
        case .together: return "square.stack.3d.up.fill"
        case .fireworks: return "flame.fill"
        case .minimax: return "waveform.path.ecg"
        case .nvidia: return "cpu.fill"
        case .grok: return "bolt.fill"
        case .qwen: return "cloud.fill"
        case .glm: return "globe.asia.australia"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }
    
    var color: Color {
        switch self {
        case .openai: return .green
        case .anthropic: return .orange
        case .deepseek: return .blue
        case .gemini: return .purple
        case .openrouter: return .indigo
        case .groq: return .orange
        case .mistral: return .orange
        case .kimi: return .cyan
        case .perplexity: return .teal
        case .perch: return .mint
        case .typhoon: return .purple
        case .cerebras: return .pink
        case .together: return .blue
        case .fireworks: return .orange
        case .minimax: return .pink
        case .nvidia: return .green
        case .grok: return .purple
        case .qwen: return .indigo
        case .glm: return .red
        case .codex: return .cyan
        }
    }
    
    var keyPrefix: String {
        switch self {
        case .openai, .codex: return "sk-"
        case .anthropic: return "sk-ant-"
        case .deepseek: return "sk-"
        case .gemini: return "AI"
        case .openrouter: return "sk-or-"
        case .groq: return "gsk_"
        case .mistral: return ""
        case .kimi: return "sk-"
        case .perplexity: return "pplx-"
        case .perch: return "perch-"
        case .typhoon: return "sk-"
        case .cerebras: return "csk-"
        case .together: return ""
        case .fireworks: return "fw_"
        case .minimax: return ""
        case .nvidia: return "nvapi-"
        case .grok: return "xai-"
        case .qwen: return "sk-"
        case .glm: return ""
        }
    }
    
    var baseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .mistral: return "https://api.mistral.ai/v1"
        case .kimi: return "https://api.moonshot.ai/v1"
        case .perplexity: return "https://api.perplexity.ai"
        case .perch: return UserDefaults.standard.string(forKey: "perch_base_url") ?? "https://api.perchai.app/v1"
        case .typhoon: return "https://api.opentyphoon.ai/v1"
        case .cerebras: return "https://api.cerebras.ai/v1"
        case .together: return "https://api.together.xyz/v1"
        case .fireworks: return "https://api.fireworks.ai/inference/v1"
        case .minimax: return "https://api.minimax.io/v1"
        case .nvidia: return "https://integrate.api.nvidia.com/v1"
        case .grok: return "https://api.x.ai/v1"
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .glm: return "https://open.bigmodel.cn/api/paas/v4"
        case .codex: return "https://api.openai.com/v1"
        }
    }
    
    var defaultModels: [String] {
        switch self {
        case .openai: return ["gpt-6.1-sol", "gpt-6-sol", "gpt-6-luna", "gpt-6-astra", "gpt-5.6-sol", "gpt-5.4", "gpt-5.3-codex", "o3", "o4-mini", "gpt-4.1", "gpt-4o"]
        case .anthropic: return ["claude-sonnet-5-5", "claude-opus-5-5", "claude-haiku-5-5", "claude-sonnet-5", "claude-opus-5", "claude-opus-4-8", "claude-sonnet-4-6", "claude-opus-4-6"]
        case .deepseek: return ["deepseek-flash", "deepseek-v4-pro", "deepseek-chat", "deepseek-reasoner"]
        case .gemini: return ["gemini-4-argon", "gemini-3.8-pro", "gemini-3.8-flash-tiered", "gemini-3.8-flash", "gemini-3.6-pro", "gemini-3.5-flash", "gemini-3.5-flash-lite", "gemini-2.5-pro", "gemini-2.5-flash"]
        case .openrouter: return ["anthropic/claude-sonnet-4", "google/gemini-2.5-pro", "deepseek/deepseek-r1-0528", "qwen/qwen3-coder"]
        case .groq: return ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "deepseek-r1-distill-llama-70b", "qwen/qwen3-32b"]
        case .mistral: return ["codestral-latest", "devstral-small-latest", "mistral-large-latest", "mistral-small-latest"]
        case .kimi: return ["Kimi-K2.7-Code", "kimi-k2-0711-preview", "kimi-latest", "moonshot-v1-128k"]
        case .perplexity: return ["sonar-reasoning-pro", "sonar-pro", "sonar-reasoning", "sonar"]
        case .perch: return ["perch-1-pro", "perch-coder-v2", "perch-1-fast", "perch-reasoning-r1"]
        case .typhoon: return ["typhoon-v2.5-30b-a3b-instruct", "typhoon-v2.1-12b-instruct", "typhoon-v2-70b-instruct", "typhoon-v2-r1-70b-preview"]
        case .cerebras: return ["qwen-3-coder-480b", "llama-3.3-70b", "qwen-3-32b", "llama3.1-8b"]
        case .together: return ["Qwen/Qwen3-235B-A22B-fp8-tput", "deepseek-ai/DeepSeek-R1", "meta-llama/Llama-3.3-70B-Instruct-Turbo"]
        case .fireworks: return ["accounts/fireworks/models/deepseek-v3", "accounts/fireworks/models/deepseek-r1", "accounts/fireworks/models/qwen3-235b-a22b"]
        case .minimax: return ["MiniMax-M2.7", "MiniMax-M1", "MiniMax-Text-01"]
        case .nvidia: return ["nvidia/llama-3.1-nemotron-ultra-253b-v1", "deepseek-ai/deepseek-r1", "qwen/qwen2.5-coder-32b-instruct"]
        case .grok: return ["grok-4.6", "grok-4", "grok-3", "grok-3-mini"]
        case .qwen: return ["qwen3-coder-plus", "qwen-max", "qwen-plus", "qwq-plus"]
        case .glm: return ["glm-5.3-flash", "glm-5.3", "glm-5.2", "glm-5.1", "glm-5-turbo", "glm-5", "glm-4.7"]
        case .codex: return ["gpt-6.1-sol", "gpt-6-luna", "gpt-5.3-codex", "o3", "o4-mini"]
        }
    }
    
    var authHeader: String {
        switch self {
        case .anthropic: return "x-api-key"
        default: return "Authorization"
        }
    }
    
    func formatAuthValue(_ key: String) -> String {
        switch self {
        case .anthropic: return key
        default: return "Bearer \(key)"
        }
    }
    
    /// Map to StreamableAIProvider for AIClient compatibility
    var streamProvider: StreamableAIProvider {
        switch self {
        case .openai, .codex: return .openai
        case .anthropic: return .anthropic
        case .deepseek: return .deepseek
        case .gemini: return .gemini
        case .openrouter: return .openrouter
        case .groq: return .groq
        case .mistral: return .mistral
        case .kimi: return .kimi
        case .perplexity: return .perplexity
        case .perch: return .perch
        case .typhoon: return .typhoon
        case .cerebras: return .cerebras
        case .together: return .together
        case .fireworks: return .fireworks
        case .minimax: return .minimax
        case .nvidia: return .nvidia
        case .grok: return .grok
        case .qwen: return .qwen
        case .glm: return .glm
        }
    }
}

// MARK: - AI Provider Auth Service

@MainActor
class AIProviderAuthService: ObservableObject {
    static let shared = AIProviderAuthService()
    
    @Published var providers: [AIProviderConfig] = []
    @Published var activeProvider: AIProviderMeta = .gemini
    @Published var isValidating: Bool = false
    @Published var validationMessage: String = ""
    
    private let keychainService = "com.dotmini.microcode.ai-providers"
    private let configKey = "ai_provider_configs"
    
    init() {
        loadProviders()
    }
    
    // MARK: - Provider Management
    
    func addProvider(_ meta: AIProviderMeta, apiKey: String, orgId: String? = nil) async -> Bool {
        isValidating = true
        validationMessage = "Validating \(meta.displayName) API key..."
        defer { isValidating = false }
        
        // Validate key
        let isValid = await validateAPIKey(meta, apiKey: apiKey)
        
        // Fetch models
        var models = meta.defaultModels
        if isValid {
            if let fetched = await fetchModels(meta, apiKey: apiKey) {
                models = fetched
            }
        }
        
        let config = AIProviderConfig(
            id: meta.rawValue,
            provider: meta.rawValue,
            apiKey: apiKey,
            organizationId: orgId,
            selectedModel: meta.defaultModels.first ?? "",
            isActive: true,
            lastValidated: Date(),
            isValid: isValid,
            availableModels: models,
            displayName: meta.displayName,
            usageQuota: nil
        )
        
        // Update or add
        if let idx = providers.firstIndex(where: { $0.provider == meta.rawValue }) {
            providers[idx] = config
        } else {
            providers.append(config)
        }
        
        // Save securely
        saveProviders()
        saveKeyToKeychain(meta.rawValue, key: apiKey)
        
        // ── Bridge key to ALL consumers ──────────────────────────
        // 1. UserDefaults (read by AIClient.resolveKey, AIModelCatalog.resolveKey)
        UserDefaults.standard.set(apiKey, forKey: "\(meta.rawValue)_api_key")
        // Also write to shared app suites for legacy compatibility
        UserDefaults(suiteName: "com.dotmini.microcode")?.set(apiKey, forKey: "\(meta.rawValue)_api_key")
        UserDefaults(suiteName: "com.dotmini.codetunner")?.set(apiKey, forKey: "\(meta.rawValue)_api_key")
        
        // 2. KeychainManager (read by AIModelCatalog.resolveKey fallback)
        if let pk = KeychainManager.ProviderKey(rawValue: "\(meta.rawValue.uppercased())_API_KEY") {
            _ = KeychainManager.shared.save(key: apiKey, for: pk)
        }
        
        // 3. Trigger live model catalog refresh so models appear immediately
        Task { @MainActor in
            await AIModelCatalog.shared.refreshIfNeeded(force: true)
        }
        // ─────────────────────────────────────────────────────────
        
        validationMessage = isValid ? "\(meta.displayName) connected successfully!" : "Key saved but validation failed"
        return isValid
    }
    
    func removeProvider(_ providerId: String) {
        providers.removeAll { $0.provider == providerId }
        deleteKeyFromKeychain(providerId)
        saveProviders()
    }
    
    func getActiveKey() -> (provider: AIProviderMeta, key: String, model: String)? {
        guard let config = providers.first(where: { $0.provider == activeProvider.rawValue && $0.isActive }),
              !config.apiKey.isEmpty else {
            // Fallback: find any active provider
            if let fallback = providers.first(where: { $0.isActive && $0.isValid }) {
                if let meta = AIProviderMeta(rawValue: fallback.provider) {
                    return (meta, fallback.apiKey, fallback.selectedModel)
                }
            }
            return nil
        }
        return (activeProvider, config.apiKey, config.selectedModel)
    }
    
    func getKey(for provider: String) -> String {
        return providers.first(where: { $0.provider == provider })?.apiKey ?? ""
    }
    
    func setActiveModel(_ model: String, for provider: String) {
        if let idx = providers.firstIndex(where: { $0.provider == provider }) {
            providers[idx].selectedModel = model
            saveProviders()
        }
    }
    
    // MARK: - Validation
    
    func validateAPIKey(_ meta: AIProviderMeta, apiKey: String) async -> Bool {
        guard !apiKey.isEmpty else { return false }
        
        do {
            switch meta {
            case .openai, .codex:
                return try await validateOpenAI(apiKey: apiKey, baseURL: meta.baseURL)
            case .anthropic:
                return try await validateAnthropic(apiKey: apiKey)
            case .deepseek:
                return try await validateOpenAI(apiKey: apiKey, baseURL: meta.baseURL)
            case .gemini:
                return try await validateGemini(apiKey: apiKey)
            case .perplexity, .perch, .minimax:
                return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .openrouter, .groq, .mistral, .kimi, .typhoon, .cerebras, .together, .fireworks, .nvidia, .grok, .qwen, .glm:
                return try await validateOpenAI(apiKey: apiKey, baseURL: meta.baseURL)
            }
        } catch {
            print("Validation error for \(meta.rawValue): \(error)")
            return false
        }
    }
    
    private func validateOpenAI(apiKey: String, baseURL: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
    
    private func validateAnthropic(apiKey: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": "claude-3-5-haiku-20241022", "max_tokens": 1, "messages": [["role": "user", "content": "hi"]]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10
        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return code == 200 || code == 201
    }
    
    private func validateGemini(apiKey: String) async throws -> Bool {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!
        let (_, response) = try await URLSession.shared.data(from: url)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
    
    // MARK: - Fetch Models
    
    func fetchModels(_ meta: AIProviderMeta, apiKey: String) async -> [String]? {
        do {
            switch meta {
            case .perplexity, .minimax:
                return meta.defaultModels
            case .openai, .codex, .deepseek, .openrouter, .groq, .mistral, .kimi, .perch, .typhoon, .cerebras, .together, .fireworks, .nvidia, .grok, .qwen, .glm:
                var request = URLRequest(url: URL(string: "\(meta.baseURL)/models")!)
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 10
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["data"] as? [[String: Any]] {
                    let ids = models.compactMap { $0["id"] as? String }
                        .filter { id in
                            switch meta {
                            case .openai, .codex:
                                let lower = id.lowercased()
                                return (lower.contains("gpt-4") || lower.contains("gpt-3.5") || lower.contains("o1") || lower.contains("o3") || lower.contains("chatgpt")) &&
                                    !lower.contains("transcribe") && !lower.contains("audio") && !lower.contains("tts") && !lower.contains("embed") && !lower.contains("moderation") && !lower.contains("realtime") && !lower.hasPrefix("ft:")
                            case .deepseek: return id.contains("deepseek")
                            case .grok: return id.contains("grok")
                            case .qwen: return id.contains("qwen")
                            case .glm: return id.contains("glm")
                            default: return true
                            }
                        }
                        .sorted()
                    return ids.isEmpty ? nil : ids
                }
                return nil
                
            case .gemini:
                let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["models"] as? [[String: Any]] {
                    return models.compactMap { ($0["name"] as? String)?.replacingOccurrences(of: "models/", with: "") }
                        .filter { $0.contains("gemini") && !$0.contains("embed") && !$0.contains("audio") }
                        .sorted()
                }
                return nil
                
            case .anthropic:
                var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 10
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return meta.defaultModels }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["data"] as? [[String: Any]] {
                    let ids = models.compactMap { $0["id"] as? String }
                        .filter { $0.contains("claude") }
                        .sorted()
                    return ids.isEmpty ? meta.defaultModels : ids
                }
                return meta.defaultModels
            }
        } catch {
            return nil
        }
    }
    
    // MARK: - Keychain Storage
    
    private func saveKeyToKeychain(_ provider: String, key: String) {
        // Hardware-Bound AES-256-GCM Sealed Store (0ms, zero OS Keychain password dialogs across rebuilds)
        UserDefaults.standard.removeObject(forKey: "microcode_cached_key_\(provider)")
        if let sealed = KeychainManager.sealSecret(key) {
            UserDefaults.standard.set(sealed, forKey: "km_sealed_aiprovider_\(provider)")
        }
    }
    
    private func loadKeyFromKeychain(_ provider: String) -> String? {
        if let sealed = UserDefaults.standard.data(forKey: "km_sealed_aiprovider_\(provider)"),
           let unsealed = KeychainManager.unsealSecret(sealed),
           !unsealed.isEmpty {
            return unsealed
        }
        // Migrate legacy cached key if present
        if let cached = UserDefaults.standard.string(forKey: "microcode_cached_key_\(provider)"), !cached.isEmpty {
            UserDefaults.standard.removeObject(forKey: "microcode_cached_key_\(provider)")
            if let sealed = KeychainManager.sealSecret(cached) {
                UserDefaults.standard.set(sealed, forKey: "km_sealed_aiprovider_\(provider)")
            }
            return cached
        }
        return nil
    }
    
    private func deleteKeyFromKeychain(_ provider: String) {
        UserDefaults.standard.removeObject(forKey: "microcode_cached_key_\(provider)")
        UserDefaults.standard.removeObject(forKey: "km_sealed_aiprovider_\(provider)")
    }
    
    // MARK: - Config Persistence
    
    private func saveProviders() {
        // Save config (without API keys) to UserDefaults
        // API keys stored separately in Keychain
        var safeConfigs = providers
        for i in safeConfigs.indices {
            safeConfigs[i].apiKey = "" // Don't store keys in UserDefaults
        }
        if let data = try? JSONEncoder().encode(safeConfigs) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }
    
    private func loadProviders() {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              var configs = try? JSONDecoder().decode([AIProviderConfig].self, from: data) else {
            return
        }
        
        // Restore API keys from Keychain
        for i in configs.indices {
            if let key = loadKeyFromKeychain(configs[i].provider) {
                configs[i].apiKey = key
            }
            // Fallback: try UserDefaults (set by other code paths)
            if configs[i].apiKey.isEmpty {
                if let udKey = UserDefaults.standard.string(forKey: "\(configs[i].provider)_api_key"),
                   !udKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    configs[i].apiKey = udKey.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            // Fallback: try KeychainManager
            if configs[i].apiKey.isEmpty {
                if let pk = KeychainManager.ProviderKey(rawValue: "\(configs[i].provider.uppercased())_API_KEY"),
                   let val = KeychainManager.shared.read(for: pk), !val.isEmpty {
                    configs[i].apiKey = val
                }
            }
        }
        
        self.providers = configs
    }
    
    // MARK: - Sync with AppState
    
    func syncToAppState(_ appState: AppState) {
        for config in providers where config.isActive && !config.apiKey.isEmpty {
            appState.apiKeys[config.provider] = config.apiKey
            
            // Bridge to UserDefaults so AIModelCatalog.resolveKey() and AIClient can find them
            UserDefaults.standard.set(config.apiKey, forKey: "\(config.provider)_api_key")
            
            // Bridge to KeychainManager
            if let pk = KeychainManager.ProviderKey(rawValue: "\(config.provider.uppercased())_API_KEY") {
                _ = KeychainManager.shared.save(key: config.apiKey, for: pk)
            }
        }
        if let active = getActiveKey() {
            appState.aiProvider = active.provider.streamProvider.rawValue
            appState.aiModel = active.model
        }
        
        // Trigger live model catalog refresh with bridged keys
        Task { @MainActor in
            await AIModelCatalog.shared.refreshIfNeeded(force: true)
        }
    }
}
