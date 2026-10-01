//
//  AIModelCatalog.swift
//  MicroCode
//
//  Unified Real-Time Model Catalog & Dynamic Provider Discovery
//  Provides verified live frontier model fetching for BYOK (OpenAI, Gemini, Anthropic, DeepSeek, Groq, GLM),
//  Dotmini Cloud Sovereign AI, Local LLM engines (Ollama, LM Studio, MLX), and ACP Agent protocols.
//
//  Created & Designed by Dotmini Software
//  Founder & CEO: Tirawat Nantamas
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation
import Combine

struct AIModelDefinition: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let provider: String
    let badge: String
    let inputPricePerMillion: Double
    let outputPricePerMillion: Double

    init(
        id: String,
        name: String? = nil,
        provider: String,
        badge: String = "",
        inputPricePerMillion: Double = 0,
        outputPricePerMillion: Double = 0
    ) {
        self.id = id
        self.name = name ?? id
        self.provider = provider
        self.badge = badge
        self.inputPricePerMillion = inputPricePerMillion
        self.outputPricePerMillion = outputPricePerMillion
    }

    var fullDisplayName: String {
        AIModelCatalog.formatFullDisplayName(provider: provider, modelId: id, modelName: name)
    }
}

struct AIProviderDefinition: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let icon: String
    let endpoint: String
    var models: [AIModelDefinition]
}

/// The single source of truth for every model picker and usage record.
/// Dotmini's OpenAI-compatible `/models` response is preferred; a versioned
/// built-in catalog keeps the IDE usable offline and before sign-in.
@MainActor
final class AIModelCatalog: ObservableObject {
    static let shared = AIModelCatalog()

    @Published private(set) var providers: [AIProviderDefinition]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var source = "Built-in catalog"

    private let cacheKey = "microcode.aiModelCatalog.v7"
    private let refreshDateKey = "microcode.aiModelCatalogRefreshDate.v7"
    private let refreshInterval: TimeInterval = 10 * 60 // 10 minutes

    private init() {
        providers = Self.fallbackProviders
        loadCachedCatalog()
        // Auto-refresh live models from provider APIs and local engines on launch
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000) // delay for keys and credentials to load
            await self?.refreshIfNeeded(force: true)
        }
    }

    func provider(_ id: String) -> AIProviderDefinition? {
        providers.first { $0.id == id }
    }

    func models(for provider: String) -> [AIModelDefinition] {
        self.provider(provider)?.models ?? []
    }

    func model(id: String) -> AIModelDefinition? {
        providers.lazy.flatMap(\.models).first { $0.id == id }
    }

    func normalizedSelection(provider: String, model: String) -> (provider: String, model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let fallbackProvider = self.provider(provider) ?? providers.first!
            return (fallbackProvider.id, fallbackProvider.models.first?.id ?? "gemini-2.5-flash")
        }
        
        let lower = trimmed.lowercased()
        var targetModel = trimmed
        if lower == "gemini" || lower == "gemini-flash" {
            targetModel = "gemini-2.5-flash"
        } else if lower == "gemini-pro" {
            targetModel = "gemini-2.5-pro"
        } else if lower == "deepseek" {
            targetModel = "deepseek-chat"
        }
        
        if self.provider(provider)?.models.contains(where: { $0.id == targetModel }) == true {
            return (provider, targetModel)
        }
        if let matchedProvider = providers.first(where: { $0.models.contains(where: { $0.id == targetModel }) }) {
            return (matchedProvider.id, targetModel)
        }
        // Direct pass-through of any live model returned by API or ecosystem
        return (provider, targetModel)
    }

    func refreshIfNeeded(force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < refreshInterval { return }

        isRefreshing = true
        defer { isRefreshing = false }

        await refreshLiveProviderModels()
    }

    /// Dynamically fetches models directly from active provider APIs (OpenAI, Gemini, Anthropic, DeepSeek, Groq, GLM, Qwen, Copilot)
    /// and local installed engines (Codex, AGY, Claude Code, Zed, Ollama, LM Studio).
    public func refreshLiveProviderModels() async {
        await refreshCloudProxyModels()
        await fetchLiveOpenAIModels()
        await fetchLiveGeminiModels()
        await fetchLiveAnthropicModels()
        await fetchLiveDeepSeekModels()
        await fetchLiveGLMModels()
        await fetchLiveGroqModels()
        await fetchLiveQwenModels()
        await fetchLiveCopilotModels()
        integrateLocalModels()
        await LocalEcosystemDiscovery.shared.refresh()
        lastUpdated = Date()
        saveCachedCatalog()
    }

    public func integrateEcosystemEngines(_ engines: [EcosystemEngineInfo]) {
        for engine in engines {
            guard !engine.models.isEmpty else { continue }
            if let idx = providers.firstIndex(where: { $0.id == engine.id }) {
                providers[idx].models = engine.models
            } else {
                let newProvider = AIProviderDefinition(
                    id: engine.id,
                    name: engine.name,
                    icon: engine.icon,
                    endpoint: "local://\(engine.id)",
                    models: engine.models
                )
                // Insert right after omni or at the top
                if providers.count > 1 {
                    providers.insert(newProvider, at: 1)
                } else {
                    providers.append(newProvider)
                }
            }
        }
    }

    private func refreshCloudProxyModels() async {
        let base = StreamableAIProvider.cloudProxyURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/models") else { return }
        var request = URLRequest(url: url, timeoutInterval: 8)
        
        let sessionToken = await SupabaseAuthService.shared.refreshAccessTokenIfNeeded()
        let authorization = DotminiPlatformKeyService.shared.authorizationToken
            ?? sessionToken
            ?? ""
        if !authorization.isEmpty {
            request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let entries = try Self.decodeRemoteModels(data)
            guard !entries.isEmpty else { return }
            providers = Self.mergeLive(remoteEntries: entries, fallback: providers)
            source = "Dotmini Cloud (\(entries.count) models live)"
        } catch {}
    }

    /// Fetches the latest live models directly from OpenAI using the user's active API key
    private func fetchLiveOpenAIModels() async {
        let key = resolveKey("openai")
        guard !key.isEmpty, let url = URL(string: "https://api.openai.com/v1/models") else { return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return }
        
        var liveModelsWithDate: [(model: AIModelDefinition, created: Int)] = []
        for item in list {
            guard let mid = item["id"] as? String else { continue }
            let lower = mid.lowercased()
            // Filter out non-text/utility models
            if lower.contains("whisper") || lower.contains("tts") || lower.contains("dall-e") ||
               lower.contains("embedding") || lower.contains("moderation") || lower.contains("babbage") ||
               lower.contains("davinci") || lower.hasPrefix("ft:") || lower.contains("transcribe") ||
               lower.contains("audio") || lower.contains("realtime") {
                continue
            }
            
            let created = item["created"] as? Int ?? 0
            let badge: String
            if lower.contains("reason") || lower.range(of: #"^o[0-9]"#, options: .regularExpression) != nil {
                badge = "REASONING"
            } else if lower.contains("mini") || lower.contains("flash") || lower.contains("nano") {
                badge = "FAST"
            } else if lower.contains("astra") || lower.contains("sol") || lower.contains("pro") || lower.contains("plus") || lower.contains("max") {
                badge = "FLAGSHIP"
            } else if lower.contains("preview") || lower.contains("exp") {
                badge = "PREVIEW"
            } else {
                badge = "CHAT"
            }
            
            liveModelsWithDate.append((
                AIModelDefinition(id: mid, name: Self.formatModelName(mid), provider: "openai", badge: badge),
                created
            ))
        }
        
        // Sort newest models first based on real API `created` timestamp returned by OpenAI
        liveModelsWithDate.sort { a, b in
            if a.created != b.created { return a.created > b.created }
            return a.model.id.localizedStandardCompare(b.model.id) == .orderedDescending
        }
        let liveModels = liveModelsWithDate.map(\.model)
        
        if !liveModels.isEmpty, let idx = providers.firstIndex(where: { $0.id == "openai" }) {
            providers[idx].models = liveModels
        }
    }

    public static func resolveKey(_ provider: String) -> String {
        let directKey = "\(provider)_api_key"
        if let val = UserDefaults.standard.string(forKey: directKey), !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return val.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let val = UserDefaults.standard.string(forKey: "microcode_cached_key_\(provider)"), !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return val.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let val = UserDefaults.standard.string(forKey: "km_cached_\(provider.uppercased())_API_KEY"), !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return val.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let authServiceKey = AIProviderAuthService.shared.getKey(for: provider)
        if !authServiceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return authServiceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for suite in ["com.dotmini.microcode", "com.dotmini.codetunner"] {
            if let val = UserDefaults(suiteName: suite)?.string(forKey: directKey), !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return val.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if provider == "openai" {
            if let val = UserDefaults.standard.string(forKey: "apiKey"), !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return val.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let val = UserDefaults(suiteName: "com.dotmini.codetunner")?.string(forKey: "api_key_ChatGPT"), !val.isEmpty {
                return val
            }
        }
        let envKey = "\(provider.uppercased())_API_KEY"
        if let val = ProcessInfo.processInfo.environment[envKey], !val.isEmpty {
            return val
        }
        if let pk = KeychainManager.ProviderKey(rawValue: "\(provider.uppercased())_API_KEY"),
           let val = KeychainManager.shared.read(for: pk), !val.isEmpty {
            return val
        }
        return ""
    }

    public func resolveKey(_ provider: String) -> String {
        Self.resolveKey(provider)
    }

    /// Fetches the latest live models directly from Google Gemini API using user's active key
    private func fetchLiveGeminiModels() async {
        let key = resolveKey("gemini")
        guard !key.isEmpty, let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(key)") else { return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["models"] as? [[String: Any]] else { return }
        
        var liveModels: [AIModelDefinition] = []
        for item in list {
            guard let rawName = item["name"] as? String else { continue }
            let mid = rawName.replacingOccurrences(of: "models/", with: "")
            let lower = mid.lowercased()
            
            // Only generative chat/content models
            if let methods = item["supportedGenerationMethods"] as? [String], !methods.contains("generateContent") {
                continue
            }
            if lower.contains("tts") || lower.contains("embed") || lower.contains("transcribe") || lower.contains("audio") {
                continue
            }
            
            // Use API's own displayName if provided by Google, otherwise algorithmic formatter
            let displayName = (item["displayName"] as? String) ?? Self.formatModelName(mid)
            let badge: String
            if lower.contains("thinking") {
                badge = "THINKING"
            } else if lower.contains("pro") {
                badge = "PRO"
            } else if lower.contains("flash") {
                badge = "FAST"
            } else {
                badge = "GEMINI"
            }
            liveModels.append(AIModelDefinition(id: mid, name: displayName, provider: "gemini", badge: badge))
        }
        
        liveModels.sort { a, b in a.id.localizedStandardCompare(b.id) == .orderedDescending }
        
        if !liveModels.isEmpty, let idx = providers.firstIndex(where: { $0.id == "gemini" }) {
            providers[idx].models = liveModels
        }
    }

    /// Fetches live Anthropic Claude models using user's API key
    private func fetchLiveAnthropicModels() async {
        let key = resolveKey("anthropic")
        guard !key.isEmpty, let url = URL(string: "https://api.anthropic.com/v1/models") else { return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return }
        
        var liveModelsWithDate: [(model: AIModelDefinition, created: String)] = []
        for item in list {
            guard let mid = item["id"] as? String else { continue }
            let lower = mid.lowercased()
            // Use API's own display_name directly from Anthropic API
            let displayName = (item["display_name"] as? String) ?? Self.formatModelName(mid)
            let createdAt = (item["created_at"] as? String) ?? ""
            
            let badge: String
            if lower.contains("opus") {
                badge = "REASONING"
            } else if lower.contains("sonnet") {
                badge = "AGENT"
            } else if lower.contains("haiku") {
                badge = "FAST"
            } else {
                badge = "CLAUDE"
            }
            
            liveModelsWithDate.append((
                AIModelDefinition(id: mid, name: displayName, provider: "anthropic", badge: badge),
                createdAt
            ))
        }
        
        // Sort newest models first using Anthropic's official `created_at` timestamp!
        liveModelsWithDate.sort { a, b in
            if !a.created.isEmpty && !b.created.isEmpty {
                return a.created > b.created
            }
            return a.model.id.localizedStandardCompare(b.model.id) == .orderedDescending
        }
        let liveModels = liveModelsWithDate.map(\.model)
        
        if !liveModels.isEmpty, let idx = providers.firstIndex(where: { $0.id == "anthropic" }) {
            providers[idx].models = liveModels
        }
    }

    /// Fetches live DeepSeek models using user's API key
    private func fetchLiveDeepSeekModels() async {
        let key = resolveKey("deepseek")
        guard !key.isEmpty, let url = URL(string: "https://api.deepseek.com/models") else { return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return }
        
        var liveModels: [AIModelDefinition] = []
        for item in list {
            guard let mid = item["id"] as? String else { continue }
            let lower = mid.lowercased()
            let badge: String
            if lower.contains("reasoner") || lower.contains("r1") {
                badge = "REASONING"
            } else if lower.contains("flash") {
                badge = "FAST"
            } else {
                badge = "CHAT"
            }
            liveModels.append(AIModelDefinition(id: mid, name: Self.formatModelName(mid), provider: "deepseek", badge: badge))
        }
        
        liveModels.sort { a, b in a.id.localizedStandardCompare(b.id) == .orderedDescending }
        
        if !liveModels.isEmpty, let idx = providers.firstIndex(where: { $0.id == "deepseek" }) {
            providers[idx].models = liveModels
        }
    }

    /// Fetches live Zhipu GLM models using user's API key
    private func fetchLiveGLMModels() async {
        let key = resolveKey("glm")
        guard !key.isEmpty, let url = URL(string: "https://open.bigmodel.cn/api/paas/v4/models") else { return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return }
        
        var liveModels: [AIModelDefinition] = []
        for item in list {
            guard let mid = item["id"] as? String else { continue }
            let lower = mid.lowercased()
            let badge = lower.contains("plus") ? "FLAGSHIP" : (lower.contains("codegeex") ? "CODE" : (lower.contains("air") ? "BALANCED" : "FAST"))
            liveModels.append(AIModelDefinition(id: mid, name: Self.formatModelName(mid), provider: "glm", badge: badge))
        }
        
        liveModels.sort { a, b in a.id.localizedStandardCompare(b.id) == .orderedDescending }
        
        if !liveModels.isEmpty, let idx = providers.firstIndex(where: { $0.id == "glm" }) {
            providers[idx].models = liveModels
        }
    }

    /// Fetches live Groq models using user's API key
    private func fetchLiveGroqModels() async {
        let key = resolveKey("groq")
        guard !key.isEmpty, let url = URL(string: "https://api.groq.com/openai/v1/models") else { return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return }
        
        var liveModels: [AIModelDefinition] = []
        for item in list {
            guard let mid = item["id"] as? String else { continue }
            let lower = mid.lowercased()
            if lower.contains("whisper") || lower.contains("tts") || lower.contains("embed") { continue }
            let badge = lower.contains("deepseek") ? "REASONING" : (lower.contains("llama") ? "LLAMA" : "FAST")
            liveModels.append(AIModelDefinition(id: mid, name: Self.formatModelName(mid), provider: "groq", badge: badge))
        }
        
        liveModels.sort { a, b in a.id.localizedStandardCompare(b.id) == .orderedDescending }
        
        if !liveModels.isEmpty {
            if let idx = providers.firstIndex(where: { $0.id == "groq" }) {
                providers[idx].models = liveModels
            } else {
                providers.append(AIProviderDefinition(
                    id: "groq",
                    name: "Groq (Ultra-Fast)",
                    icon: "bolt.fill",
                    endpoint: "https://api.groq.com/openai/v1",
                    models: liveModels
                ))
            }
        }
    }

    /// Fetches live Qwen models using user's API key
    private func fetchLiveQwenModels() async {
        let key = resolveKey("qwen")
        guard !key.isEmpty, let url = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/models") else { return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return }
        
        var liveModels: [AIModelDefinition] = []
        for item in list {
            guard let mid = item["id"] as? String else { continue }
            let lower = mid.lowercased()
            if lower.contains("embedding") || lower.contains("audio") || lower.contains("tts") { continue }
            let badge = lower.contains("coder") ? "CODE" : "QWEN"
            liveModels.append(AIModelDefinition(id: mid, name: Self.formatModelName(mid), provider: "qwen", badge: badge))
        }
        
        liveModels.sort { a, b in a.id.localizedStandardCompare(b.id) == .orderedDescending }
        
        if !liveModels.isEmpty, let idx = providers.firstIndex(where: { $0.id == "qwen" }) {
            providers[idx].models = liveModels
        }
    }

    /// Fetches live authorized models from user's GitHub Copilot subscription
    public func fetchLiveCopilotModels() async {
        guard let token = SubscriptionAuthManager.shared.token(for: .copilot), !token.isEmpty else { return }
        let sessionToken: String
        do {
            sessionToken = try await SubscriptionAuthManager.shared.getCopilotSessionToken(githubToken: token)
        } catch {
            return
        }
        guard let url = URL(string: "https://api.githubcopilot.com/models") else { return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        req.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        req.setValue("copilot-chat/0.24.0", forHTTPHeaderField: "Editor-Plugin-Version")
        req.setValue("GitHubCopilot/1.250.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return }
        
        var liveModels: [AIModelDefinition] = [
            AIModelDefinition(id: "auto", name: "Copilot Auto", provider: "copilot", badge: "AUTO")
        ]
        var subModels: [SubscriptionModelInfo] = [
            SubscriptionModelInfo(modelID: "auto", name: "Copilot Auto", provider: .copilot, badge: "AUTO", description: "GitHub Copilot dynamic routing", aiProviderID: "copilot")
        ]
        
        for item in list {
            guard let mid = item["id"] as? String else { continue }
            let name = (item["name"] as? String) ?? Self.formatModelName(mid)
            let lower = mid.lowercased()
            let badge = lower.contains("sonnet") ? "AGENT" : (lower.contains("o3") || lower.contains("o1") ? "REASONING" : "COPILOT")
            liveModels.append(AIModelDefinition(id: mid, name: name, provider: "copilot", badge: badge))
            subModels.append(SubscriptionModelInfo(modelID: mid, name: name, provider: .copilot, badge: badge, description: "GitHub Copilot live subscription model", aiProviderID: "copilot"))
        }
        
        if !liveModels.isEmpty, let idx = providers.firstIndex(where: { $0.id == "copilot" }) {
            providers[idx].models = liveModels
        }
        SubscriptionAuthManager.setLiveModels(for: .copilot, models: subModels)
    }

    /// Fetches live models dynamically for a specific provider via direct HTTP API calls
    public func fetchLiveModelsForProvider(_ providerId: String) async {
        switch providerId.lowercased() {
        case "openai": await fetchLiveOpenAIModels()
        case "gemini": await fetchLiveGeminiModels()
        case "anthropic": await fetchLiveAnthropicModels()
        case "deepseek": await fetchLiveDeepSeekModels()
        case "glm": await fetchLiveGLMModels()
        case "groq": await fetchLiveGroqModels()
        case "qwen": await fetchLiveQwenModels()
        case "copilot", "github": await fetchLiveCopilotModels()
        case "local":
            await LocalLLMService.shared.scanForServers()
            integrateLocalModels()
        default:
            await refreshCloudProxyModels()
        }
        lastUpdated = Date()
        saveCachedCatalog()
    }

    /// Allows users to register any custom or newly released model ID dynamically
    public func registerCustomModel(provider: String, modelId: String) {
        let cleanId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return }
        
        let customKey = "microcode_custom_models_\(provider)"
        var saved = UserDefaults.standard.stringArray(forKey: customKey) ?? []
        if !saved.contains(cleanId) {
            saved.append(cleanId)
            UserDefaults.standard.set(saved, forKey: customKey)
        }
        
        let newModel = AIModelDefinition(id: cleanId, name: Self.formatModelName(cleanId), provider: provider, badge: "CUSTOM")
        if let idx = providers.firstIndex(where: { $0.id == provider }) {
            if !providers[idx].models.contains(where: { $0.id == cleanId }) {
                providers[idx].models.insert(newModel, at: 0)
            }
        } else {
            providers.append(AIProviderDefinition(
                id: provider,
                name: Self.friendlyProviderName(provider),
                icon: "sparkles",
                endpoint: "custom",
                models: [newModel]
            ))
        }
        saveCachedCatalog()
    }

    /// Integrates detected local engines (Ollama, LM Studio, MLX) into the catalog
    public func integrateLocalModels() {
        let detected = LocalLLMService.shared.detectedServers.filter { $0.isOnline }
        var localModels: [AIModelDefinition] = []
        for server in detected {
            for m in server.models {
                localModels.append(AIModelDefinition(
                    id: m.id,
                    name: "\(m.displayName) (\(server.type.rawValue))",
                    provider: "local",
                    badge: server.type.rawValue.uppercased()
                ))
            }
        }
        if localModels.isEmpty {
            localModels = [
                AIModelDefinition(id: "local-model", name: "Default Local Model (Ollama / LM Studio)", provider: "local", badge: "LOCAL")
            ]
        }
        if let idx = providers.firstIndex(where: { $0.id == "local" }) {
            providers[idx].models = localModels
        } else {
            providers.append(AIProviderDefinition(
                id: "local",
                name: "Local LLM",
                icon: "desktopcomputer",
                endpoint: LocalLLMService.cachedEndpoint,
                models: localModels
            ))
        }
    }

    private struct RemoteModelItem {
        let id: String
        let ownedBy: String?
    }

    private static func decodeRemoteModels(_ data: Data) throws -> [RemoteModelItem] {
        let object = try JSONSerialization.jsonObject(with: data)
        if let dictionary = object as? [String: Any], let rows = dictionary["data"] as? [[String: Any]] {
            return rows.compactMap { dict in
                guard let id = dict["id"] as? String else { return nil }
                return RemoteModelItem(id: id, ownedBy: dict["owned_by"] as? String)
            }
        }
        if let dictionary = object as? [String: Any], let rows = dictionary["models"] as? [[String: Any]] {
            return rows.compactMap { dict in
                guard let id = (dict["id"] as? String) ?? (dict["name"] as? String) else { return nil }
                return RemoteModelItem(id: id, ownedBy: dict["owned_by"] as? String)
            }
        }
        return []
    }

    private static func mergeLive(remoteEntries: [RemoteModelItem], fallback: [AIProviderDefinition]) -> [AIProviderDefinition] {
        var result = fallback
        var known: [String: AIModelDefinition] = [:]
        for provider in fallback {
            for m in provider.models {
                if known[m.id] == nil {
                    known[m.id] = m
                }
            }
        }
        for item in remoteEntries {
            let rawID = item.id.replacingOccurrences(of: "models/", with: "")
            guard isChatModel(rawID) else { continue }
            
            let providerID = inferProvider(rawID, ownedBy: item.ownedBy)
            let formattedName = formatModelName(rawID)
            let modelDef = known[rawID] ?? AIModelDefinition(id: rawID, name: formattedName, provider: providerID, badge: "DOTMINI LIVE")
            
            // Add to specific provider (e.g. deepseek, gemini)
            if let providerIndex = result.firstIndex(where: { $0.id == providerID }) {
                if !result[providerIndex].models.contains(where: { $0.id == rawID }) {
                    result[providerIndex].models.insert(modelDef, at: 0)
                }
            }
            
            // Also register in Dotmini Omni AI provider list so users can pick all Dotmini Cloud models directly
            if let omniIndex = result.firstIndex(where: { $0.id == "omni" }) {
                let omniDef = AIModelDefinition(id: rawID, name: formattedName, provider: "omni", badge: item.ownedBy?.uppercased() ?? "DOTMINI")
                if !result[omniIndex].models.contains(where: { $0.id == rawID }) {
                    result[omniIndex].models.append(omniDef)
                }
            }
        }
        return result
    }

    nonisolated public static func friendlyProviderName(_ provider: String) -> String {
        switch provider.lowercased() {
        case "agy", "antigravity": return "Antigravity"
        case "gemini", "google": return "Google Gemini"
        case "openai": return "OpenAI"
        case "claude_code", "claude": return "Claude Code"
        case "anthropic": return "Anthropic"
        case "opencode": return "OpenCode"
        case "codex": return "Codex"
        case "zed": return "Zed"
        case "aider": return "Aider"
        case "omni": return "Dotmini Cloud"
        case "deepseek": return "DeepSeek"
        case "qwen": return "Qwen"
        case "grok": return "xAI Grok"
        case "glm": return "GLM"
        case "copilot": return "GitHub Copilot"
        case "local": return "Local LLM"
        default: return provider.isEmpty ? "AI" : provider.capitalized
        }
    }

    nonisolated public static func formatFullDisplayName(provider: String?, modelId: String, modelName: String? = nil) -> String {
        let provId: String = {
            if let p = provider, !p.isEmpty { return p }
            return inferProvider(modelId)
        }()
        let prov = friendlyProviderName(provId)
        let model = modelName ?? formatModelName(modelId)
        return "\(prov) : \(model)"
    }

    nonisolated public static func formatModelName(_ id: String) -> String {
        var clean = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("models/") {
            clean = String(clean.dropFirst(7))
        }
        
        // Preserve org prefix if any (e.g. "meta-llama/llama-3.3-70b-instruct" -> "Meta-Llama / ...")
        let prefix: String
        if let slashIndex = clean.firstIndex(of: "/") {
            let org = String(clean[..<slashIndex])
            prefix = org.capitalized + " / "
            clean = String(clean[clean.index(after: slashIndex)...])
        } else {
            prefix = ""
        }
        
        // Split by hyphens or underscores
        let parts = clean.components(separatedBy: CharacterSet(charactersIn: "-_"))
        var formattedParts: [String] = []
        
        for part in parts {
            let lower = part.lowercased()
            if lower.isEmpty { continue }
            
            // Check if it's a date stamp like 20250219 or 20241022
            if lower.count == 8, let dateNum = Int(lower), dateNum > 20200000 {
                let year = lower.prefix(4)
                let month = lower.dropFirst(4).prefix(2)
                let day = lower.suffix(2)
                formattedParts.append("(\(year)-\(month)-\(day))")
                continue
            }
            
            // Acronyms and specific technical casing
            switch lower {
            case "gpt": formattedParts.append("GPT")
            case "ai": formattedParts.append("AI")
            case "llm": formattedParts.append("LLM")
            case "moe": formattedParts.append("MoE")
            case "oss": formattedParts.append("OSS")
            case "api": formattedParts.append("API")
            case "tts": formattedParts.append("TTS")
            case "exp": formattedParts.append("Experimental")
            case "r1": formattedParts.append("R1")
            case "r2": formattedParts.append("R2")
            case "r3": formattedParts.append("R3")
            case "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9":
                formattedParts.append(lower.uppercased())
            default:
                if lower.hasSuffix("b"), let _ = Double(lower.dropLast()) {
                    formattedParts.append(lower.uppercased()) // e.g. 70B, 32B, 8B
                } else if lower.range(of: #"^o[0-9]"#, options: .regularExpression) != nil {
                    formattedParts.append(lower) // e.g. o1, o3, o4
                } else if lower.hasPrefix("gpt") {
                    formattedParts.append("GPT-" + lower.dropFirst(3))
                } else {
                    formattedParts.append(part.capitalized)
                }
            }
        }
        
        let result = prefix + formattedParts.joined(separator: " ")
        return result.isEmpty ? id : result
    }

    nonisolated private static func inferProvider(_ model: String, ownedBy: String? = nil) -> String {
        if let owner = ownedBy?.lowercased() {
            if owner.contains("deepseek") { return "deepseek" }
            if owner.contains("gemini") || owner.contains("google") { return "gemini" }
            if owner.contains("anthropic") || owner.contains("claude") { return "anthropic" }
            if owner.contains("openai") { return "openai" }
            if owner.contains("qwen") || owner.contains("alibaba") { return "qwen" }
            if owner.contains("groq") { return "groq" }
            if owner.contains("zhipu") || owner.contains("glm") { return "glm" }
        }
        let value = model.lowercased()
        if value.contains("gemini") || value.contains("gemma") { return "gemini" }
        if value.contains("claude") { return "anthropic" }
        if value.contains("deepseek") { return "deepseek" }
        if value.contains("gpt") || value.contains("chatgpt") || value.range(of: #"^o[0-9]"#, options: .regularExpression) != nil { return "openai" }
        if value.contains("grok") { return "grok" }
        if value.contains("qwen") { return "qwen" }
        if value.contains("glm") || value.contains("codegeex") { return "glm" }
        if value.contains("local") || value.contains("ollama") { return "local" }
        return "omni"
    }

    private static func isChatModel(_ id: String) -> Bool {
        let excluded = ["embedding", "moderation", "tts", "whisper", "audio", "transcribe", "dall-e"]
        let lower = id.lowercased()
        return !excluded.contains { lower.contains($0) }
    }

    private func loadCachedCatalog() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([AIProviderDefinition].self, from: data),
           !cached.isEmpty {
            providers = cached
            lastUpdated = UserDefaults.standard.object(forKey: refreshDateKey) as? Date
            source = "Persistent Cache (\(cached.flatMap(\.models).count) models)"
        }
        
        // Restore user registered custom models for each provider
        for provider in providers {
            let customKey = "microcode_custom_models_\(provider.id)"
            if let customs = UserDefaults.standard.stringArray(forKey: customKey) {
                if let idx = providers.firstIndex(where: { $0.id == provider.id }) {
                    for cid in customs {
                        if !providers[idx].models.contains(where: { $0.id == cid }) {
                            providers[idx].models.insert(AIModelDefinition(id: cid, name: Self.formatModelName(cid), provider: provider.id, badge: "CUSTOM"), at: 0)
                        }
                    }
                }
            }
        }
    }

    private func saveCachedCatalog() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(lastUpdated, forKey: refreshDateKey)
    }

    static let fallbackProviders: [AIProviderDefinition] = [
        AIProviderDefinition(id: "omni", name: "Dotmini Cloud", icon: "sparkles", endpoint: "api.dotmini.net/v1", models: [
            AIModelDefinition(id: "gpt-4o", name: "GPT-4o", provider: "omni", badge: "CLOUD")
        ]),
        AIProviderDefinition(id: "openai", name: "OpenAI", icon: "brain.head.profile", endpoint: "api.openai.com", models: [
            AIModelDefinition(id: "gpt-4o", name: "GPT-4o", provider: "openai", badge: "DEFAULT")
        ]),
        AIProviderDefinition(id: "anthropic", name: "Anthropic Claude", icon: "bubble.left.and.text.bubble.right", endpoint: "api.anthropic.com", models: [
            AIModelDefinition(id: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", provider: "anthropic", badge: "DEFAULT")
        ]),
        AIProviderDefinition(id: "gemini", name: "Google Gemini", icon: "sparkles", endpoint: "generativelanguage.googleapis.com", models: [
            AIModelDefinition(id: "gemini-1.5-flash", name: "Gemini 1.5 Flash", provider: "gemini", badge: "DEFAULT")
        ]),
        AIProviderDefinition(id: "deepseek", name: "DeepSeek", icon: "water.waves", endpoint: "api.deepseek.com", models: [
            AIModelDefinition(id: "deepseek-chat", name: "DeepSeek V3 Chat", provider: "deepseek", badge: "DEFAULT")
        ]),
        AIProviderDefinition(id: "copilot", name: "GitHub Copilot", icon: "github", endpoint: "api.githubcopilot.com", models: [
            AIModelDefinition(id: "auto", name: "Copilot Auto", provider: "copilot", badge: "AUTO")
        ]),
        AIProviderDefinition(id: "qwen", name: "Qwen / Alibaba", icon: "cloud.fill", endpoint: "dashscope.aliyuncs.com", models: [
            AIModelDefinition(id: "qwen-plus", name: "Qwen Plus", provider: "qwen", badge: "DEFAULT")
        ]),
        AIProviderDefinition(id: "grok", name: "xAI Grok", icon: "bolt.fill", endpoint: "api.x.ai", models: [
            AIModelDefinition(id: "grok-2", name: "xAI Grok 2", provider: "grok", badge: "DEFAULT")
        ]),
        AIProviderDefinition(id: "glm", name: "Zhipu GLM", icon: "globe.asia.australia", endpoint: "open.bigmodel.cn", models: [
            AIModelDefinition(id: "glm-4-flash", name: "GLM-4 Flash", provider: "glm", badge: "DEFAULT")
        ]),
        AIProviderDefinition(id: "local", name: "Local LLM", icon: "desktopcomputer", endpoint: "http://127.0.0.1:11434/v1", models: [
            AIModelDefinition(id: "local-model", name: "Default Local Model", provider: "local", badge: "LOCAL")
        ])
    ]
}
