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
    case openai, anthropic, deepseek, gemini, grok, codex, qwen, glm
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Claude (Anthropic)"
        case .deepseek: return "DeepSeek"
        case .gemini: return "Google Gemini"
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
        case .grok: return "https://api.x.ai/v1"
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .glm: return "https://open.bigmodel.cn/api/paas/v4"
        case .codex: return "https://api.openai.com/v1"
        }
    }
    
    var defaultModels: [String] {
        switch self {
        case .openai: return ["o3-mini", "o1", "o1-mini", "gpt-4o", "gpt-4o-mini", "chatgpt-4o-latest", "gpt-4-turbo"]
        case .anthropic: return ["claude-3-7-sonnet-20250219", "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]
        case .deepseek: return ["deepseek-chat", "deepseek-reasoner"]
        case .gemini: return ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash", "gemini-2.0-flash-thinking-exp-01-21", "gemini-1.5-pro", "gemini-1.5-flash"]
        case .grok: return ["grok-2-1212", "grok-2-vision-1212", "grok-beta"]
        case .qwen: return ["qwen-plus", "qwen-max", "qwen-turbo", "qwen/qwen-2.5-coder-32b-instruct", "qwen/qwen-2.5-72b-instruct"]
        case .glm: return ["glm-4-plus", "glm-4-0520", "glm-4-air", "codegeex-4", "glm-4-flash"]
        case .codex: return ["o3-mini", "o1", "gpt-4o", "gpt-4o-mini"]
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
            case .grok, .qwen, .glm:
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
            case .openai, .codex, .deepseek, .grok, .qwen, .glm:
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
        // 1. Cache in UserDefaults so recompiled ad-hoc builds never trigger Keychain ACL password prompts
        UserDefaults.standard.set(key, forKey: "microcode_cached_key_\(provider)")
        
        let data = Data(key.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "apikey_\(provider)",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var access: SecAccess?
        SecAccessCreate("MicroCode" as CFString, nil, &access)
        if let access = access {
            query[kSecAttrAccess as String] = access
        }
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func loadKeyFromKeychain(_ provider: String) -> String? {
        // Fast path: cached locally (0ms, zero OS password dialogs on newly compiled builds)
        if let cached = UserDefaults.standard.string(forKey: "microcode_cached_key_\(provider)"), !cached.isEmpty {
            return cached
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "apikey_\(provider)",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let str = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(str, forKey: "microcode_cached_key_\(provider)")
            return str
        }
        return nil
    }
    
    private func deleteKeyFromKeychain(_ provider: String) {
        UserDefaults.standard.removeObject(forKey: "microcode_cached_key_\(provider)")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "apikey_\(provider)"
        ]
        SecItemDelete(query as CFDictionary)
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
