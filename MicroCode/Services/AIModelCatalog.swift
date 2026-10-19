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

    private let cacheKey = "microcode.aiModelCatalog.v9"
    private let refreshDateKey = "microcode.aiModelCatalogRefreshDate.v9"
    private let refreshInterval: TimeInterval = 5 * 60 // 5 minutes

    private init() {
        providers = Self.fallbackProviders
        loadCachedCatalog()
        // Auto-integrate local ecosystem models and refresh live models from provider APIs on launch
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.integrateEcosystemEngines(LocalEcosystemDiscovery.shared.engines)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await self.refreshIfNeeded(force: true)
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

    private static let legacyStaleModelIDs: Set<String> = [
        "gemini-2.5-flash",
        "gemini-2.5-pro",
        "gemini-2.0-flash",
        "gemini-1.5-flash",
        "gemini-1.5-pro",
        "claude-3-5-sonnet",
        "claude-3-7-sonnet",
        "claude-3-5-sonnet-20241022",
        "claude-3-7-sonnet-20250219",
        "gpt-4o",
        "gpt-4o-mini"
    ]

    func normalizedSelection(provider: String, model: String) -> (provider: String, model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let fallbackProvider = self.provider(provider) ?? providers.first!
            return (fallbackProvider.id, fallbackProvider.models.first?.id ?? "")
        }
        
        let lower = trimmed.lowercased()
        // If a generic provider alias or family prefix (e.g. "gemini-4-argon") is passed and live models exist, pick the matching or top live model
        if lower == "gemini" || lower == "gemini-flash" || lower == "gemini-pro" || lower == "gemini-4-argon" {
            let candidateModels = self.provider(provider)?.models ?? self.provider("gemini")?.models ?? []
            if lower == "gemini-4-argon",
               let argonMatch = candidateModels.first(where: { $0.id.lowercased() == "gemini-4-argon-medium" })
                ?? candidateModels.first(where: { $0.id.lowercased().hasPrefix("gemini-4-argon") }) {
                return (provider, argonMatch.id)
            }
            if let firstLive = candidateModels.first?.id {
                return (provider, firstLive)
            }
        }
        
        if Self.legacyStaleModelIDs.contains(lower),
           let prov = self.provider(provider),
           let firstLive = prov.models.first?.id,
           !Self.legacyStaleModelIDs.contains(firstLive.lowercased()) {
            return (prov.id, firstLive)
        }
        
        if self.provider(provider)?.models.contains(where: { $0.id == trimmed }) == true {
            return (provider, trimmed)
        }
        // Prefix match within the active provider (e.g. "claude-opus-5-5" -> "claude-opus-5-5-high")
        if let prefixMatch = self.provider(provider)?.models.first(where: { $0.id.lowercased().hasPrefix(lower + "-") }) {
            return (provider, prefixMatch.id)
        }
        if let matchedProvider = providers.first(where: { $0.models.contains(where: { $0.id == trimmed }) }) {
            return (matchedProvider.id, trimmed)
        }
        // Direct pass-through of any live model returned by API or ecosystem
        return (provider, trimmed)
    }

    func refreshIfNeeded(force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < refreshInterval { return }

        isRefreshing = true
        defer { isRefreshing = false }

        await refreshLiveProviderModels()
    }

    /// Dynamically fetches models directly from active provider APIs (OpenAI, Gemini, Anthropic, DeepSeek, Groq, Grok, GLM, Qwen, Copilot)
    /// and local installed engines (Codex, AGY, Claude Code, OpenCode, Zed, Ollama, LM Studio) in parallel.
    public func refreshLiveProviderModels() async {
        async let cloudTask: Void = refreshCloudProxyModels()
        async let openAITask: Void = fetchLiveOpenAIModels()
        async let geminiTask: Void = fetchLiveGeminiModels()
        async let anthropicTask: Void = fetchLiveAnthropicModels()
        async let deepSeekTask: Void = fetchLiveDeepSeekModels()
        async let glmTask: Void = fetchLiveGLMModels()
        async let groqTask: Void = fetchLiveGroqModels()
        async let grokTask: Void = fetchLiveGrokModels()
        async let qwenTask: Void = fetchLiveQwenModels()
        async let copilotTask: Void = fetchLiveCopilotModels()
        async let ecosystemTask: Void = LocalEcosystemDiscovery.shared.refresh()

        _ = await (
            cloudTask,
            openAITask,
            geminiTask,
            anthropicTask,
            deepSeekTask,
            glmTask,
            groqTask,
            grokTask,
            qwenTask,
            copilotTask,
            ecosystemTask
        )
        integrateLocalModels()
        rebuildOmniCloudCatalog()
        syncAllSubscriptionModels()
        syncActiveAppStateSelection()
        lastUpdated = Date()
        source = "Live API & CLI Discovery (\(providers.flatMap(\.models).count) models)"
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
                if providers.count > 1 {
                    providers.insert(newProvider, at: 1)
                } else {
                    providers.append(newProvider)
                }
            }
        }
        
        // Bridge live discovered AGY models (e.g. Gemini 4 Argon, Gemini 3.8 Flash, Claude Opus 5.5, Claude Sonnet 5.5)
        // into the Gemini and Anthropic catalogs
        if let agyEngine = engines.first(where: { $0.id == "agy" }), !agyEngine.models.isEmpty {
            let agyGeminiModels = agyEngine.models
                .filter { $0.id.lowercased().contains("gemini") || $0.id.lowercased().contains("gemma") }
                .map { AIModelDefinition(id: $0.id, name: $0.name, provider: "gemini", badge: $0.badge) }
            if !agyGeminiModels.isEmpty, let gIdx = providers.firstIndex(where: { $0.id == "gemini" }) {
                var merged = agyGeminiModels
                for existing in providers[gIdx].models where existing.badge != "DEFAULT" && !merged.contains(where: { $0.id == existing.id }) {
                    merged.append(existing)
                }
                merged.sort { a, b in
                    let sa = Self.geminiModelSortScore(a.id)
                    let sb = Self.geminiModelSortScore(b.id)
                    if sa != sb { return sa > sb }
                    return a.id.localizedStandardCompare(b.id) == .orderedDescending
                }
                providers[gIdx].models = merged
            }
            
            let agyClaudeModels = agyEngine.models
                .filter { $0.id.lowercased().contains("claude") }
                .map { AIModelDefinition(id: $0.id, name: $0.name, provider: "anthropic", badge: $0.badge) }
            if !agyClaudeModels.isEmpty, let aIdx = providers.firstIndex(where: { $0.id == "anthropic" }) {
                var merged = agyClaudeModels
                for existing in providers[aIdx].models where existing.badge != "DEFAULT" && !merged.contains(where: { $0.id == existing.id }) {
                    merged.append(existing)
                }
                merged.sort { a, b in
                    let sa = Self.claudeModelSortScore(a.id)
                    let sb = Self.claudeModelSortScore(b.id)
                    if sa != sb { return sa > sb }
                    return a.id.localizedStandardCompare(b.id) == .orderedDescending
                }
                providers[aIdx].models = merged
            }
        }
        
        // Bridge live discovered Codex models (e.g. GPT-6.1-Sol, GPT-6-Astra, GPT-6-Luna) into OpenAI catalog
        if let codexEngine = engines.first(where: { $0.id == "codex" }), !codexEngine.models.isEmpty {
            let codexOpenAIModels = codexEngine.models
                .map { AIModelDefinition(id: $0.id, name: $0.name, provider: "openai", badge: $0.badge) }
            if let oIdx = providers.firstIndex(where: { $0.id == "openai" }) {
                var merged = codexOpenAIModels
                for existing in providers[oIdx].models where existing.badge != "DEFAULT" && !merged.contains(where: { $0.id == existing.id }) {
                    merged.append(existing)
                }
                providers[oIdx].models = merged
            }
        }
        
        rebuildOmniCloudCatalog()
        syncAllSubscriptionModels()
        syncActiveAppStateSelection()
        saveCachedCatalog()
    }

    private func rebuildOmniCloudCatalog() {
        guard let omniIdx = providers.firstIndex(where: { $0.id == "omni" }) else { return }
        var combined: [AIModelDefinition] = []
        var seen = Set<String>()
        
        // Preserve native Dotmini Omni models first, then top live models from Gemini, OpenAI, Anthropic, DeepSeek, GLM
        let priorityProviders = ["gemini", "openai", "anthropic", "deepseek", "glm", "qwen", "grok"]
        for pid in priorityProviders {
            guard let prov = self.provider(pid) else { continue }
            for m in prov.models.prefix(8) where m.badge != "DEFAULT" {
                guard !seen.contains(m.id) else { continue }
                seen.insert(m.id)
                combined.append(AIModelDefinition(id: m.id, name: m.name, provider: "omni", badge: m.badge))
            }
        }
        for existing in providers[omniIdx].models where existing.badge != "DEFAULT" && !seen.contains(existing.id) {
            seen.insert(existing.id)
            combined.append(existing)
        }
        combined.sort { a, b in
            let sa = Self.universalModelPriorityScore(a.id)
            let sb = Self.universalModelPriorityScore(b.id)
            if sa != sb { return sa > sb }
            return a.id.localizedStandardCompare(b.id) == .orderedDescending
        }
        if !combined.isEmpty {
            providers[omniIdx].models = combined
        }
    }

    private func syncActiveAppStateSelection() {
        guard let appState = AppState.shared else { return }
        let currentProv = appState.aiProvider
        let currentMod = appState.aiModel
        let normalized = normalizedSelection(provider: currentProv, model: currentMod)
        if normalized.provider != currentProv || normalized.model != currentMod {
            appState.aiProvider = normalized.provider
            appState.aiModel = normalized.model
            appState.saveSettings()
        }
    }

    public func syncAllSubscriptionModels() {
        for subProv in SubscriptionProviderType.allCases where subProv != .copilot {
            if let catalogProv = self.provider(subProv.aiProviderID), !catalogProv.models.isEmpty {
                let subModels = catalogProv.models.map { m in
                    SubscriptionModelInfo(
                        modelID: m.id,
                        name: m.name,
                        provider: subProv,
                        badge: m.badge,
                        description: "\(subProv.displayName) live model: \(m.id)",
                        aiProviderID: subProv.aiProviderID
                    )
                }
                SubscriptionAuthManager.setLiveModels(for: subProv, models: subModels)
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
        var req = URLRequest(url: url, timeoutInterval: 10)
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
               lower.contains("audio") || lower.contains("realtime") || lower.contains("search") {
                continue
            }
            
            let created = item["created"] as? Int ?? 0
            let badge: String
            if lower.contains("reason") || lower.range(of: #"^o[0-9]"#, options: .regularExpression) != nil {
                badge = "REASONING"
            } else if lower.contains("mini") || lower.contains("flash") || lower.contains("nano") || lower.contains("luna") {
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
        var liveModels = liveModelsWithDate.map(\.model)
        
        // Preserve any Codex models discovered locally at the top
        if let codexModels = LocalEcosystemDiscovery.shared.engines.first(where: { $0.id == "codex" })?.models {
            for cm in codexModels.reversed() {
                if !liveModels.contains(where: { $0.id == cm.id }) {
                    liveModels.insert(AIModelDefinition(id: cm.id, name: cm.name, provider: "openai", badge: cm.badge), at: 0)
                }
            }
        }
        
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
        if provider == "gemini", let val = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"], !val.isEmpty {
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

    /// Fetches the latest live models directly from Google Gemini API (both v1beta and v1alpha with pageSize=1000)
    private func fetchLiveGeminiModels() async {
        let key = resolveKey("gemini")
        var liveModels: [AIModelDefinition] = []
        var seenIds = Set<String>()
        
        // First include any Gemini models discovered from installed Antigravity (AGY) CLI (e.g. gemini-4-argon-*, gemini-3.8-flash-*)
        if let agyModels = LocalEcosystemDiscovery.shared.engines.first(where: { $0.id == "agy" })?.models {
            for m in agyModels where m.id.lowercased().contains("gemini") || m.id.lowercased().contains("gemma") {
                if !seenIds.contains(m.id) {
                    seenIds.insert(m.id)
                    liveModels.append(AIModelDefinition(id: m.id, name: m.name, provider: "gemini", badge: m.badge))
                }
            }
        }
        
        if !key.isEmpty {
            let endpoints = [
                "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000&key=\(key)",
                "https://generativelanguage.googleapis.com/v1alpha/models?pageSize=1000&key=\(key)"
            ]
            for endpoint in endpoints {
                guard let url = URL(string: endpoint) else { continue }
                var req = URLRequest(url: url, timeoutInterval: 10)
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                
                guard let (data, resp) = try? await URLSession.shared.data(for: req),
                      let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let list = json["models"] as? [[String: Any]] else { continue }
                
                for item in list {
                    guard let rawName = item["name"] as? String else { continue }
                    let mid = rawName.replacingOccurrences(of: "models/", with: "")
                    guard !seenIds.contains(mid) else { continue }
                    let lower = mid.lowercased()
                    
                    // Only generative chat/content models
                    if let methods = item["supportedGenerationMethods"] as? [String], !methods.contains("generateContent") {
                        continue
                    }
                    if lower.contains("tts") || lower.contains("embed") || lower.contains("transcribe") ||
                       lower.contains("audio") || lower.contains("aqa") || lower.contains("imagen") ||
                       lower.contains("veo") || lower.contains("learnlm") {
                        continue
                    }
                    
                    seenIds.insert(mid)
                    let displayName = (item["displayName"] as? String) ?? Self.formatModelName(mid)
                    let badge: String
                    if lower.contains("argon") {
                        badge = "FLAGSHIP"
                    } else if lower.contains("thinking") {
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
            }
        }
        
        liveModels.sort { a, b in
            let aScore = Self.geminiModelSortScore(a.id)
            let bScore = Self.geminiModelSortScore(b.id)
            if aScore != bScore { return aScore > bScore }
            return a.id.localizedStandardCompare(b.id) == .orderedDescending
        }
        
        if !liveModels.isEmpty, let idx = providers.firstIndex(where: { $0.id == "gemini" }) {
            providers[idx].models = liveModels
        }
    }

    nonisolated private static func geminiModelSortScore(_ id: String) -> Int {
        let lower = id.lowercased()
        var score = 0
        if lower.contains("gemini-5") { score += 5000 }
        else if lower.contains("gemini-4") { score += 4000 }
        else if lower.contains("gemini-3.8") || lower.contains("gemini-3-8") { score += 3800 }
        else if lower.contains("gemini-3.5") || lower.contains("gemini-3-5") { score += 3500 }
        else if lower.contains("gemini-3") { score += 3000 }
        else if lower.contains("gemini-2.5") || lower.contains("gemini-2-5") { score += 2500 }
        else if lower.contains("gemini-2.0") || lower.contains("gemini-2-0") { score += 2000 }
        else if lower.contains("gemini-1.5") { score += 1500 }
        
        if lower.contains("argon") { score += 400 }
        else if lower.contains("ultra") { score += 350 }
        else if lower.contains("pro") { score += 300 }
        else if lower.contains("flash") && !lower.contains("lite") { score += 200 }
        else if lower.contains("lite") { score += 100 }
        
        if lower.contains("high") { score += 30 }
        else if lower.contains("medium") { score += 20 }
        else if lower.contains("low") { score += 10 }
        return score
    }

    nonisolated public static func claudeModelSortScore(_ id: String) -> Int {
        let lower = id.lowercased()
        var score = 0
        if lower.contains("5-5") || lower.contains("5.5") { score += 5500 }
        else if lower.contains("5-1") || lower.contains("5.1") { score += 5100 }
        else if lower.contains("5-0") || lower.contains("5.0") || lower.contains("claude-5") { score += 5000 }
        else if lower.contains("4-7") || lower.contains("4.7") { score += 4700 }
        else if lower.contains("4-6") || lower.contains("4.6") { score += 4600 }
        else if lower.contains("4-5") || lower.contains("4.5") { score += 4500 }
        else if lower.contains("4-1") || lower.contains("4.1") { score += 4100 }
        else if lower.contains("4-0") || lower.contains("4.0") || lower.contains("claude-4") { score += 4000 }
        else if lower.contains("3-7") || lower.contains("3.7") { score += 3700 }
        else if lower.contains("3-5") || lower.contains("3.5") { score += 3500 }
        else if lower.contains("3-") { score += 3000 }

        if lower.contains("opus") { score += 400 }
        else if lower.contains("sonnet") { score += 300 }
        else if lower.contains("fable") { score += 250 }
        else if lower.contains("haiku") { score += 150 }

        if lower.contains("high") { score += 35 }
        else if lower.contains("medium") { score += 25 }
        else if lower.contains("low") { score += 10 }
        else { score += 30 }
        return score
    }

    nonisolated public static func universalModelPriorityScore(_ id: String) -> Int {
        let lower = id.lowercased()
        if lower.contains("gemini") || lower.contains("gemma") {
            return geminiModelSortScore(lower) + 100
        }
        if lower.contains("claude") {
            return claudeModelSortScore(lower)
        }
        if lower.contains("gpt-6.1") || lower.contains("gpt-6-1") { return 4450 }
        if lower.contains("gpt-6") { return 4400 }
        if lower.contains("gpt-5.6") { return 4200 }
        if lower.contains("gpt-5.4") { return 4100 }
        if lower.contains("gpt-5") { return 4000 }
        if lower.contains("deepseek-v4") { return 4350 }
        if lower.contains("deepseek-r") || lower.contains("deepseek-reasoner") { return 3900 }
        if lower.contains("deepseek") { return 3700 }
        if lower.contains("glm-5.3") { return 4150 }
        if lower.contains("glm-5") { return 3950 }
        if lower.contains("omni-o1x") { return 4300 }
        return 2000
    }

    /// Fetches live Anthropic Claude models using user's API key (plus any discovered AGY Claude models)
    private func fetchLiveAnthropicModels() async {
        let key = resolveKey("anthropic")
        var liveModelsWithDate: [(model: AIModelDefinition, created: String)] = []
        var seenIds = Set<String>()
        
        if !key.isEmpty, let url = URL(string: "https://api.anthropic.com/v1/models?limit=100") {
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let list = json["data"] as? [[String: Any]] {
                for item in list {
                    guard let mid = item["id"] as? String, !seenIds.contains(mid) else { continue }
                    seenIds.insert(mid)
                    let lower = mid.lowercased()
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
            }
        }
        
        var liveModels = liveModelsWithDate.map(\.model)
        
        // Merge any Claude models discovered from Antigravity CLI (e.g. claude-opus-5-5-*, claude-sonnet-5-5-*)
        if let agyModels = LocalEcosystemDiscovery.shared.engines.first(where: { $0.id == "agy" })?.models {
            for m in agyModels where m.id.lowercased().contains("claude") {
                if !liveModels.contains(where: { $0.id == m.id }) {
                    liveModels.append(AIModelDefinition(id: m.id, name: m.name, provider: "anthropic", badge: m.badge))
                }
            }
        }
        
        liveModels.sort { a, b in
            let sa = Self.claudeModelSortScore(a.id)
            let sb = Self.claudeModelSortScore(b.id)
            if sa != sb { return sa > sb }
            return a.id.localizedStandardCompare(b.id) == .orderedDescending
        }
        
        if !liveModels.isEmpty, let idx = providers.firstIndex(where: { $0.id == "anthropic" }) {
            providers[idx].models = liveModels
        }
    }

    /// Fetches live DeepSeek models using user's API key
    private func fetchLiveDeepSeekModels() async {
        let key = resolveKey("deepseek")
        guard !key.isEmpty, let url = URL(string: "https://api.deepseek.com/models") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
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
        var req = URLRequest(url: url, timeoutInterval: 10)
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

    /// Fetches live xAI Grok models using user's API key
    private func fetchLiveGrokModels() async {
        let key = resolveKey("grok")
        guard !key.isEmpty, let url = URL(string: "https://api.x.ai/v1/models") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
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
            if lower.contains("embed") || lower.contains("image") { continue }
            let created = item["created"] as? Int ?? 0
            let badge = lower.contains("mini") ? "FAST" : (lower.contains("reason") || lower.contains("think") ? "REASONING" : "GROK")
            liveModelsWithDate.append((
                AIModelDefinition(id: mid, name: Self.formatModelName(mid), provider: "grok", badge: badge),
                created
            ))
        }
        
        liveModelsWithDate.sort { a, b in
            if a.created != b.created { return a.created > b.created }
            return a.model.id.localizedStandardCompare(b.model.id) == .orderedDescending
        }
        let liveModels = liveModelsWithDate.map(\.model)
        
        if !liveModels.isEmpty, let idx = providers.firstIndex(where: { $0.id == "grok" }) {
            providers[idx].models = liveModels
        }
    }

    /// Fetches live Groq models using user's API key
    private func fetchLiveGroqModels() async {
        let key = resolveKey("groq")
        guard !key.isEmpty, let url = URL(string: "https://api.groq.com/openai/v1/models") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
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
        var req = URLRequest(url: url, timeoutInterval: 10)
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
        var req = URLRequest(url: url, timeoutInterval: 10)
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
        case "grok": await fetchLiveGrokModels()
        case "groq": await fetchLiveGroqModels()
        case "qwen": await fetchLiveQwenModels()
        case "copilot", "github": await fetchLiveCopilotModels()
        case "agy", "codex", "claude_code", "opencode", "zed":
            await LocalEcosystemDiscovery.shared.refresh()
        case "local":
            await LocalLLMService.shared.scanForServers()
            integrateLocalModels()
        default:
            await refreshCloudProxyModels()
        }
        syncAllSubscriptionModels()
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
        var touchedProviders = Set<Int>()
        for item in remoteEntries {
            let rawID = item.id.replacingOccurrences(of: "models/", with: "")
            guard isChatModel(rawID) else { continue }
            
            let providerID = inferProvider(rawID, ownedBy: item.ownedBy)
            let formattedName = formatModelName(rawID)
            let modelDef = known[rawID] ?? AIModelDefinition(id: rawID, name: formattedName, provider: providerID, badge: "DOTMINI LIVE")
            
            // Add to specific provider (e.g. deepseek, gemini)
            if let providerIndex = result.firstIndex(where: { $0.id == providerID }) {
                if !result[providerIndex].models.contains(where: { $0.id == rawID }) {
                    result[providerIndex].models.append(modelDef)
                    touchedProviders.insert(providerIndex)
                }
            }
            
            // Also register in Dotmini Omni AI provider list so users can pick all Dotmini Cloud models directly
            if let omniIndex = result.firstIndex(where: { $0.id == "omni" }) {
                let omniDef = AIModelDefinition(id: rawID, name: formattedName, provider: "omni", badge: item.ownedBy?.uppercased() ?? "DOTMINI")
                if !result[omniIndex].models.contains(where: { $0.id == rawID }) {
                    result[omniIndex].models.append(omniDef)
                    touchedProviders.insert(omniIndex)
                }
            }
        }
        for idx in touchedProviders {
            result[idx].models.sort { a, b in
                let sa = universalModelPriorityScore(a.id)
                let sb = universalModelPriorityScore(b.id)
                if sa != sb { return sa > sb }
                return a.id.localizedStandardCompare(b.id) == .orderedDescending
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
        AIProviderDefinition(id: "omni", name: "Dotmini Cloud", icon: "sparkles", endpoint: "api.dotmini.net/v1", models: []),
        AIProviderDefinition(id: "openai", name: "OpenAI", icon: "brain.head.profile", endpoint: "api.openai.com", models: []),
        AIProviderDefinition(id: "anthropic", name: "Anthropic Claude", icon: "bubble.left.and.text.bubble.right", endpoint: "api.anthropic.com", models: []),
        AIProviderDefinition(id: "gemini", name: "Google Gemini", icon: "sparkles", endpoint: "generativelanguage.googleapis.com", models: []),
        AIProviderDefinition(id: "deepseek", name: "DeepSeek", icon: "water.waves", endpoint: "api.deepseek.com", models: []),
        AIProviderDefinition(id: "copilot", name: "GitHub Copilot", icon: "github", endpoint: "api.githubcopilot.com", models: []),
        AIProviderDefinition(id: "qwen", name: "Qwen / Alibaba", icon: "cloud.fill", endpoint: "dashscope.aliyuncs.com", models: []),
        AIProviderDefinition(id: "grok", name: "xAI Grok", icon: "bolt.fill", endpoint: "api.x.ai", models: []),
        AIProviderDefinition(id: "glm", name: "Zhipu GLM", icon: "globe.asia.australia", endpoint: "open.bigmodel.cn", models: []),
        AIProviderDefinition(id: "local", name: "Local LLM", icon: "desktopcomputer", endpoint: "http://127.0.0.1:11434/v1", models: [])
    ]
}
