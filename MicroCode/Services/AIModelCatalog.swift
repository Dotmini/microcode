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

    private let cacheKey = "microcode.aiModelCatalog.v17"
    private let refreshDateKey = "microcode.aiModelCatalogRefreshDate.v17"
    private let refreshInterval: TimeInterval = 15 * 60 // 15-minute live model refresh TTL

    private init() {
        providers = Self.fallbackProviders
        loadCachedCatalog()
        // Auto-integrate cached local ecosystem models; only hit live provider APIs if cache is expired
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.integrateEcosystemEngines(LocalEcosystemDiscovery.shared.engines)
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await self.refreshIfNeeded(force: false)
        }
    }

    func provider(_ id: String) -> AIProviderDefinition? {
        providers.first { $0.id == id }
    }

    func models(for provider: String) -> [AIModelDefinition] {
        self.provider(provider)?.models ?? []
    }

    func model(id: String) -> AIModelDefinition? {
        if let match = providers.lazy.filter({ $0.id != "omni" }).flatMap(\.models).first(where: { $0.id == id }) {
            return match
        }
        return providers.lazy.flatMap(\.models).first { $0.id == id }
    }

    private static let legacyStaleModelIDs: Set<String> = [
        "gemini-2.0-flash",
        "gemini-1.5-flash",
        "gemini-1.5-pro",
        "claude-3-5-sonnet",
        "claude-3-7-sonnet",
        "claude-3-5-sonnet-20241022",
        "claude-3-7-sonnet-20250219"
    ]

    private static let acpProviderIDs: Set<String> = [
        "agy", "codex", "claude_code", "opencode", "zed",
        "gemini_cli", "cursor", "goose", "cline", "aider"
    ]

    func normalizedSelection(provider: String, model: String) -> (provider: String, model: String) {
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "direct"
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        var effectiveProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Never let "omni" claim third-party models (Gemini, OpenAI, Claude, DeepSeek, GLM, etc.)
        if effectiveProvider == "omni" {
            let detected = StreamableAIProvider.detect(from: trimmed).rawValue
            if detected != "omni" {
                effectiveProvider = detected
            } else if keyMode != "cloud" {
                if keyMode == "subscription",
                   let subStr = UserDefaults.standard.string(forKey: "subscriptionActiveProvider"),
                   let subType = SubscriptionProviderType(rawValue: subStr) {
                    effectiveProvider = subType.aiProviderID
                } else {
                    effectiveProvider = "gemini"
                }
            }
        }
        
        if trimmed.isEmpty {
            let fallbackProvider = self.provider(effectiveProvider) ?? providers.first(where: { $0.id != "omni" }) ?? providers.first!
            return (fallbackProvider.id, fallbackProvider.models.first?.id ?? "")
        }
        
        let lower = trimmed.lowercased()
        // Only resolve bare provider name aliases ("gemini", "openai", "anthropic", "deepseek", "glm", "aipass")
        if lower == "gemini" || lower == "openai" || lower == "anthropic" || lower == "deepseek" || lower == "glm" || lower == "aipass" {
            let candidateModels = self.provider(effectiveProvider)?.models ?? self.provider(lower)?.models ?? []
            if let firstLive = candidateModels.first?.id {
                return (effectiveProvider, firstLive)
            }
        }
        
        if Self.legacyStaleModelIDs.contains(lower),
           let prov = self.provider(effectiveProvider),
           let firstLive = prov.models.first?.id,
           !Self.legacyStaleModelIDs.contains(firstLive.lowercased()) {
            return (prov.id, firstLive)
        }
        
        if self.provider(effectiveProvider)?.models.contains(where: { $0.id == trimmed }) == true {
            return (effectiveProvider, trimmed)
        }
        // If caller already specified a concrete provider (Subscription / BYOK / ACP / Local), respect it directly
        // and NEVER let "omni" (Dotmini Cloud) hijack the provider!
        let knownDirectProviders: Set<String> = [
            "gemini", "openai", "anthropic", "deepseek", "glm", "copilot", "aipass",
            "9router", "openrouter", "groq", "mistral", "kimi", "perplexity", "perch", "typhoon",
            "cerebras", "together", "fireworks", "minimax", "nvidia",
            "qwen", "grok", "local"
        ]
        if knownDirectProviders.contains(effectiveProvider) || Self.acpProviderIDs.contains(effectiveProvider) {
            return (effectiveProvider, trimmed)
        }
        
        let isCallerACP = Self.acpProviderIDs.contains(effectiveProvider)
        if let matchedProvider = providers.first(where: {
            $0.id != "omni" &&
            (isCallerACP || !Self.acpProviderIDs.contains($0.id)) &&
            $0.models.contains(where: { $0.id == trimmed })
        }) {
            return (matchedProvider.id, trimmed)
        }
        // Direct pass-through of any live model returned by API or subscription
        return (effectiveProvider, trimmed)
    }

    func refreshIfNeeded(force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < refreshInterval { return }

        isRefreshing = true
        defer { isRefreshing = false }

        await refreshLiveProviderModels()
    }

    /// Dynamically fetches models directly from active provider APIs (OpenAI, Gemini, Anthropic, DeepSeek, Groq, Grok, GLM, Qwen, Copilot, TH-AI Passport)
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
        async let aipassTask: Void = fetchLiveAiPassModels()
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
            aipassTask,
            ecosystemTask
        )
        await fetchLiveAdditionalProviderModels()
        integrateLocalModels()
        rebuildOmniCloudCatalog()
        syncAllSubscriptionModels()
        syncActiveAppStateSelection()
        lastUpdated = Date()
        source = "Live API & CLI Discovery (\(providers.flatMap(\.models).count) models)"
        saveCachedCatalog()
        IdleStateCompactor.relieveAllMallocZones()
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
                // Append ACP engines at the end so they never shadow standard Subscription/BYOK providers
                providers.append(newProvider)
            }
        }
        
        rebuildOmniCloudCatalog()
        syncAllSubscriptionModels()
        syncActiveAppStateSelection()
        saveCachedCatalog()
    }

    private func rebuildOmniCloudCatalog() {
        guard let omniIdx = providers.firstIndex(where: { $0.id == "omni" }) else { return }
        // Only keep native Dotmini Sovereign AI (Omni O1X) models inside "omni";
        // never copy or claim third-party models (Gemini, OpenAI, Claude, DeepSeek, GLM) under Dotmini.
        let omniOnly = providers[omniIdx].models.filter { $0.id.lowercased().hasPrefix("omni") }
        if !omniOnly.isEmpty {
            providers[omniIdx].models = omniOnly
        } else {
            providers[omniIdx].models = [
                AIModelDefinition(id: "omni-o1x-pro", name: "Omni O1X Pro (3B MoE)", provider: "omni", badge: "SOVEREIGN"),
                AIModelDefinition(id: "omni-o1x-lite", name: "Omni O1X Lite (0.8B)", provider: "omni", badge: "FAST")
            ]
        }
    }

    private func syncActiveAppStateSelection() {
        guard let appState = AppState.shared else { return }
        let mode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? ""
        if mode == "subscription" {
            // Never overwrite Subscription mode's provider/model selection during catalog refresh
            return
        }
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
            SubscriptionAuthManager.shared.syncLiveModelsFromCatalog(for: subProv)
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
        
        var liveModelsWithDate: [(model: AIModelDefinition, score: Int, created: Int)] = []
        for item in list {
            guard let mid = item["id"] as? String else { continue }
            let lower = mid.lowercased()
            // Filter out non-chat/utility/image/realtime endpoints that cannot be called on /v1/chat/completions
            if lower.contains("whisper") || lower.contains("tts") || lower.contains("dall-e") ||
               lower.contains("embedding") || lower.contains("moderation") || lower.contains("babbage") ||
               lower.contains("davinci") || lower.hasPrefix("ft:") || lower.contains("transcribe") ||
               lower.contains("audio") || lower.contains("realtime") || lower.contains("search") ||
               lower.contains("image") || lower.contains("gpt-live") || lower.contains("sora") ||
               lower.contains("computer-use") {
                continue
            }
            
            let created = item["created"] as? Int ?? 0
            let badge: String
            if lower.contains("reason") || lower.range(of: #"^o[0-9]"#, options: .regularExpression) != nil {
                badge = "REASONING"
            } else if lower.contains("codex") {
                badge = "AGENT"
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
                Self.openAIModelSortScore(mid),
                created
            ))
        }
        
        // Sort newest generation models first (canonical aliases before dated snapshots), then by `created` timestamp
        liveModelsWithDate.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.created != b.created { return a.created > b.created }
            return a.model.id.localizedStandardCompare(b.model.id) == .orderedDescending
        }
        var liveModels = liveModelsWithDate.map(\.model)
        
        // Preserve any Codex models discovered locally and built-in flagship fallback models at the top
        if let codexModels = LocalEcosystemDiscovery.shared.engines.first(where: { $0.id == "codex" })?.models {
            for cm in codexModels.reversed() {
                if !liveModels.contains(where: { $0.id == cm.id }) {
                    liveModels.insert(AIModelDefinition(id: cm.id, name: cm.name, provider: "openai", badge: cm.badge), at: 0)
                }
            }
        }
        if let fallbackModels = Self.fallbackProviders.first(where: { $0.id == "openai" })?.models {
            for fm in fallbackModels.reversed() {
                if !liveModels.contains(where: { $0.id == fm.id }) {
                    liveModels.insert(fm, at: 0)
                }
            }
        }
        
        if !liveModels.isEmpty, let idx = providers.firstIndex(where: { $0.id == "openai" }) {
            providers[idx].models = liveModels
        }
    }

    private static let microcodeDefaults = UserDefaults(suiteName: "com.dotmini.microcode")
    private static let codetunnerDefaults = UserDefaults(suiteName: "com.dotmini.codetunner")
    private static var checkedOpenCodeConfig: Set<String> = []

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
        for suiteDefaults in [microcodeDefaults, codetunnerDefaults] {
            if let val = suiteDefaults?.string(forKey: directKey), !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return val.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if provider == "openai" {
            if let val = UserDefaults.standard.string(forKey: "apiKey"), !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return val.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let val = codetunnerDefaults?.string(forKey: "api_key_ChatGPT"), !val.isEmpty {
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
        if (provider == "glm" || provider == "deepseek") && !checkedOpenCodeConfig.contains(provider) {
            checkedOpenCodeConfig.insert(provider)
            let opencodeURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/opencode/opencode.json")
            if let data = try? Data(contentsOf: opencodeURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let provDict = json["provider"] as? [String: Any] {
                let targetKeys = provider == "glm" ? ["zai", "glm", "zhipu"] : ["deepseek"]
                for tk in targetKeys {
                    if let p = provDict[tk] as? [String: Any],
                       let opts = p["options"] as? [String: Any],
                       let k = opts["apiKey"] as? String, !k.isEmpty {
                        UserDefaults.standard.set(k, forKey: directKey)
                        return k
                    }
                }
            }
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
                if seenIds.insert(m.id).inserted {
                    liveModels.append(AIModelDefinition(id: m.id, name: m.name, provider: "gemini", badge: m.badge))
                }
            }
        }
        // Always include built-in Gemini flagship/pro/flash fallback models
        if let fallbackModels = Self.fallbackProviders.first(where: { $0.id == "gemini" })?.models {
            for fm in fallbackModels {
                if seenIds.insert(fm.id).inserted {
                    liveModels.append(fm)
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
                       lower.contains("veo") || lower.contains("learnlm") || lower.contains("image") ||
                       lower.contains("banana") || lower.contains("lyria") || lower.contains("robotics") ||
                       lower.contains("computer-use") || lower.contains("deep-research") || lower.contains("antigravity") {
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

    nonisolated public static func openAIModelSortScore(_ id: String) -> Int {
        let lower = id.lowercased()
        var score = 0
        if lower.contains("gpt-6.1") || lower.contains("gpt-6-1") { score += 6100 }
        else if lower.contains("gpt-6") { score += 6000 }
        else if lower.contains("gpt-5.6") { score += 5600 }
        else if lower.contains("gpt-5.5") { score += 5500 }
        else if lower.contains("gpt-5.4") { score += 5400 }
        else if lower.contains("gpt-5.3") { score += 5300 }
        else if lower.contains("gpt-5.2") { score += 5200 }
        else if lower.contains("gpt-5.1") { score += 5100 }
        else if lower.contains("gpt-5") { score += 5000 }
        else if lower.hasPrefix("o4") { score += 4800 }
        else if lower.hasPrefix("o3") { score += 4700 }
        else if lower.contains("gpt-4.5") { score += 4500 }
        else if lower.contains("gpt-4.1") { score += 4400 }
        else if lower.contains("gpt-4o") || lower.contains("chatgpt-4o") { score += 4200 }
        else if lower.hasPrefix("o1") { score += 4000 }
        else if lower.contains("gpt-4") { score += 3500 }
        else { score += 2000 }

        if lower.contains("sol") || lower.contains("pro") || lower.contains("max") { score += 80 }
        else if lower.contains("astra") || lower.contains("codex") { score += 60 }
        else if lower.contains("luna") || lower.contains("mini") { score += 40 }
        else if lower.contains("nano") { score += 20 }
        else { score += 50 }

        // Put dated snapshots (e.g. -2025-08-07) below canonical model aliases
        if lower.range(of: #"-\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil {
            score -= 300
        }
        return score
    }

    nonisolated private static func geminiModelSortScore(_ id: String) -> Int {
        let lower = id.lowercased()
        var score = 0
        if lower.contains("gemini-5") { score += 6000 }
        else if lower.contains("gemini-4") { score += 5000 }
        else if lower.contains("gemini-3.8") || lower.contains("gemini-3-8") { score += 4800 }
        else if lower.contains("gemini-3.7") || lower.contains("gemini-3-7") { score += 4700 }
        else if lower.contains("gemini-3.6") || lower.contains("gemini-3-6") { score += 4600 }
        else if lower.contains("gemini-3.5") || lower.contains("gemini-3-5") { score += 4500 }
        else if lower.contains("gemini-3.1") || lower.contains("gemini-3-1") { score += 4100 }
        else if lower.contains("gemini-3") { score += 4000 }
        else if lower.contains("gemini-2.5") || lower.contains("gemini-2-5") { score += 2500 }
        else if lower.contains("gemini-2.0") || lower.contains("gemini-2-0") { score += 2000 }
        else if lower.contains("gemini-1.5") { score += 1500 }
        
        if lower.contains("argon") && !lower.contains("low") && !lower.contains("medium") && !lower.contains("high") { score += 400 }
        else if lower.contains("pro") { score += 350 }
        else if lower.contains("tiered") || lower.contains("high") { score += 320 }
        else if lower.contains("flash") && !lower.contains("lite") { score += 280 }
        else if lower.contains("lite") { score += 220 }
        else if lower.contains("argon") { score += 200 }
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
        
        // Merge any Claude models discovered from Antigravity CLI and built-in flagship fallback models
        if let agyModels = LocalEcosystemDiscovery.shared.engines.first(where: { $0.id == "agy" })?.models {
            for m in agyModels where m.id.lowercased().contains("claude") {
                if !liveModels.contains(where: { $0.id == m.id }) {
                    liveModels.append(AIModelDefinition(id: m.id, name: m.name, provider: "anthropic", badge: m.badge))
                }
            }
        }
        if let fallbackModels = Self.fallbackProviders.first(where: { $0.id == "anthropic" })?.models {
            for fm in fallbackModels {
                if !liveModels.contains(where: { $0.id == fm.id }) {
                    liveModels.append(fm)
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
        var seen = Set<String>()
        for item in list {
            guard let mid = item["id"] as? String, seen.insert(mid).inserted else { continue }
            let lower = mid.lowercased()
            let rawName = (item["name"] as? String)?.replacingOccurrences(of: "-", with: " ")
            let displayName = (rawName?.isEmpty == false) ? rawName! : Self.formatModelName(mid)
            let badge: String
            if lower.contains("reasoner") || lower.contains("r1") {
                badge = "REASONING"
            } else if lower.contains("pro") {
                badge = "FLAGSHIP"
            } else if lower.contains("flash") {
                badge = "FAST"
            } else {
                badge = "CHAT"
            }
            liveModels.append(AIModelDefinition(id: mid, name: displayName, provider: "deepseek", badge: badge))
        }
        // Always include standard DeepSeek V4 / V3.2 Chat & R1 Reasoner models
        if let fallbackModels = Self.fallbackProviders.first(where: { $0.id == "deepseek" })?.models {
            for fallback in fallbackModels where seen.insert(fallback.id).inserted {
                liveModels.append(fallback)
            }
        }
        
        if !liveModels.isEmpty, let idx = providers.firstIndex(where: { $0.id == "deepseek" }) {
            providers[idx].models = liveModels
        }
    }

    nonisolated private static func glmModelSortScore(_ id: String) -> Int {
        let lower = id.lowercased()
        if lower == "glm-5.3-flash" { return 5350 }
        if lower.contains("glm-5.3") { return 5300 }
        if lower.contains("glm-5.2") { return 5200 }
        if lower.contains("glm-5.1") { return 5100 }
        if lower.contains("glm-5-turbo") { return 5050 }
        if lower.contains("glm-5") { return 5000 }
        if lower.contains("glm-4.7") { return 4700 }
        if lower.contains("glm-4.6") { return 4600 }
        if lower.contains("glm-4.5-air") { return 4520 }
        if lower.contains("glm-4.5") { return 4500 }
        return 3000
    }

    /// Fetches live Zhipu GLM / Z.AI models using user's API key
    private func fetchLiveGLMModels() async {
        let key = resolveKey("glm")
        guard !key.isEmpty else { return }
        let endpoints = [
            "https://api.z.ai/api/paas/v4/models",
            "https://open.bigmodel.cn/api/paas/v4/models"
        ]
        var list: [[String: Any]] = []
        for ep in endpoints {
            guard let url = URL(string: ep) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["data"] as? [[String: Any]], !items.isEmpty {
                list = items
                break
            }
        }
        guard !list.isEmpty else { return }
        
        var liveModels: [AIModelDefinition] = []
        var seen = Set<String>()
        // Include GLM-5.3-Flash at the top (supported on Z.AI chat/completions even if omitted from /models list)
        let topFlash = AIModelDefinition(id: "glm-5.3-flash", name: "GLM 5.3 Flash", provider: "glm", badge: "FAST")
        seen.insert(topFlash.id)
        liveModels.append(topFlash)
        
        for item in list {
            guard let mid = item["id"] as? String, seen.insert(mid).inserted else { continue }
            let lower = mid.lowercased()
            let badge = (lower.contains("5.3") || lower.contains("5.2") || lower.contains("5.1") || lower.contains("plus")) ? "FLAGSHIP" : (lower.contains("codegeex") ? "CODE" : (lower.contains("air") || lower.contains("turbo") ? "FAST" : "CHAT"))
            liveModels.append(AIModelDefinition(id: mid, name: Self.formatModelName(mid), provider: "glm", badge: badge))
        }
        if let fallbackModels = Self.fallbackProviders.first(where: { $0.id == "glm" })?.models {
            for fallback in fallbackModels where seen.insert(fallback.id).inserted {
                liveModels.append(fallback)
            }
        }
        liveModels.sort { Self.glmModelSortScore($0.id) > Self.glmModelSortScore($1.id) }
        
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

    /// Fetches live authorized models from TH-AI Passport (`https://de.aipass.net/loaders/list-models`)
    public func fetchLiveAiPassModels() async {
        let rawToken = SubscriptionAuthManager.shared.token(for: .aipass) ?? resolveKey("aipass")
        let cookieHeader = SubscriptionAuthManager.normalizeAiPassToken(rawToken)
        guard !cookieHeader.isEmpty, let url = URL(string: "https://de.aipass.net/loaders/list-models") else { return }
        
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        req.setValue("https://de.aipass.net/chat", forHTTPHeaderField: "Referer")
        req.setValue("https://de.aipass.net", forHTTPHeaderField: "Origin")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("th-TH,th;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        req.setValue("empty", forHTTPHeaderField: "sec-fetch-dest")
        req.setValue("cors", forHTTPHeaderField: "sec-fetch-mode")
        req.setValue("same-origin", forHTTPHeaderField: "sec-fetch-site")
        
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return }
        
        var liveModels: [AIModelDefinition] = []
        var subModels: [SubscriptionModelInfo] = []
        var seen = Set<String>()
        
        for item in list {
            guard let mid = item["id"] as? String else { continue }
            let ready = (item["ready"] as? Bool) ?? true
            guard ready else { continue }
            let lower = mid.lowercased()
            guard seen.insert(mid).inserted else { continue }
            let isFree = (item["isFreeCredit"] as? Bool) ?? false
            let hasThinking = (item["thinkingConfig"] as? [String: Any]) != nil
            let badge: String
            if lower.contains("lyria") || lower.contains("music") || lower.contains("audio-gen") {
                badge = "MUSIC"
            } else if lower.contains("veo") || lower.contains("seedance") || lower.contains("sora") || lower.hasPrefix("wan") {
                badge = "VIDEO"
            } else if lower.contains("image") || lower.contains("imagen") || lower.contains("flux") || lower.contains("seedream") || lower.contains("banana") {
                badge = "IMAGE"
            } else if isFree {
                badge = "FREE"
            } else if lower.contains("opus") || lower.contains("sol") || lower.contains("argon") || lower.contains("pro") {
                badge = "FLAGSHIP"
            } else if hasThinking || lower.contains("reason") {
                badge = "REASONING"
            } else if lower.contains("sonnet") || lower.contains("code") {
                badge = "AGENT"
            } else {
                badge = "FAST"
            }
            let displayName = "\(Self.formatModelName(mid))\(isFree ? " (Free)" : " (AiPASS)")"
            liveModels.append(AIModelDefinition(id: mid, name: displayName, provider: "aipass", badge: badge))
            subModels.append(SubscriptionModelInfo(
                modelID: mid,
                name: displayName,
                provider: .aipass,
                badge: badge,
                description: isFree ? "TH-AI Passport free unlimited credit model" : "TH-AI Passport live model (\(mid))",
                aiProviderID: "aipass"
            ))
        }

        // Ensure all official TH-AI Passport Image, Video, and Music generation models are always selectable
        let guaranteedMediaModels: [(id: String, name: String, badge: String, desc: String)] = [
            ("gemini-2.5-flash-image", "Nano Banana — Gemini 2.5 Flash Image (Free)", "IMAGE", "Google Nano Banana fast image generation"),
            ("gemini-3.1-flash-lite-image", "Nano Banana 2 Lite — Gemini 3.1 Image (Free)", "IMAGE", "Google Nano Banana 2 Lite image generation"),
            ("gemini-3.1-flash-image", "Nano Banana 2 — Gemini 3.1 Flash Image (AiPASS)", "IMAGE", "Google Nano Banana 2 high-fidelity image generation"),
            ("gemini-nano-banana-2.1", "Nano Banana 2.1 — Gemini Image (AiPASS)", "IMAGE", "Google Nano Banana 2.1 studio image generation"),
            ("gemini-3-pro-image", "Nano Banana Pro — Gemini 3 Pro Image (AiPASS)", "IMAGE", "Google Nano Banana Pro photorealistic image generation"),
            ("FLUX.2-pro", "Flux 2 Pro — Studio Image (AiPASS)", "IMAGE", "Black Forest Labs Flux 2 Pro image generation"),
            ("flux2-klein-4b@jts", "Flux 2 Klein 4B — Image (AiPASS)", "IMAGE", "Flux 2 Klein 4B JTS image generation"),
            ("gpt-image-2", "GPT-Image-2 (AiPASS)", "IMAGE", "OpenAI GPT-Image-2 high-precision image generation"),
            ("gpt-image-2.5-flare", "GPT-Image-2.5 Flare (AiPASS)", "IMAGE", "OpenAI GPT-Image-2.5 Flare studio image generation"),
            ("gpt-image-2.5-sunburst", "GPT-Image-2.5 Sunburst (AiPASS)", "IMAGE", "OpenAI GPT-Image-2.5 Sunburst flagship image generation"),
            ("seedream-5.0-flash", "Seedream 5.0 Flash — Image (AiPASS)", "IMAGE", "ByteDance Seedream 5.0 Flash image generation"),
            ("seedream-5.0-pro", "Seedream 5.0 Pro — Image (AiPASS)", "IMAGE", "ByteDance Seedream 5.0 Pro flagship image generation"),
            ("seedream-4.5", "Seedream 4.5 — Image (AiPASS)", "IMAGE", "ByteDance Seedream 4.5 image generation"),
            ("veo-3.1-fast-generate-001", "Veo 3.1 Fast — Video Gen (AiPASS)", "VIDEO", "Google Veo 3.1 Fast AI Video Generation"),
            ("veo-3.1-generate-001", "Veo 3.1 — Cinema Video Gen (AiPASS)", "VIDEO", "Google Veo 3.1 Flagship AI Video Generation"),
            ("veo-3.0-generate-001", "Veo 3.0 — Video Gen (AiPASS)", "VIDEO", "Google Veo 3.0 AI Video Generation"),
            ("seedance-2.0-fast", "Seedance 2.0 Fast — Video Gen (AiPASS)", "VIDEO", "ByteDance Seedance 2.0 Fast AI Video Generation"),
            ("seedance-2.0", "Seedance 2.0 — Video Gen (AiPASS)", "VIDEO", "ByteDance Seedance 2.0 AI Video Generation"),
            ("wan2.2@jts", "Wan 2.2 — Video Gen (AiPASS)", "VIDEO", "Alibaba Wan 2.2 AI Video Generation"),
            ("sora-2", "Sora 2 — Video Gen (AiPASS)", "VIDEO", "OpenAI Sora 2 AI Video Generation"),
            ("lyria-3-clip-preview", "Lyria 3 Clip — 30s Music Gen (AiPASS)", "MUSIC", "Google DeepMind Lyria 3 Clip (30s AI Music Generation)"),
            ("lyria-3-pro-preview", "Lyria 3 Pro — Full Song + Vocals (AiPASS)", "MUSIC", "Google DeepMind Lyria 3 Pro (Full-length AI Song Generation)")
        ]
        for media in guaranteedMediaModels where seen.insert(media.id).inserted {
            liveModels.append(AIModelDefinition(id: media.id, name: media.name, provider: "aipass", badge: media.badge))
            subModels.append(SubscriptionModelInfo(
                modelID: media.id,
                name: media.name,
                provider: .aipass,
                badge: media.badge,
                description: media.desc,
                aiProviderID: "aipass"
            ))
        }

        // Sort so general-purpose fast free model (`gemini-3.5-flash-lite`) and top frontier models appear first,
        // specialized domain/@jts models after, followed by IMAGE / VIDEO / MUSIC models
        func groupRank(_ modelId: String, badge: String) -> Int {
            let lower = modelId.lowercased()
            if lower == "gemini-3.5-flash-lite" { return 0 }
            if badge == "IMAGE" || badge == "VIDEO" || badge == "MUSIC" { return 3 }
            if lower.contains("@jts") || lower.contains("legal") || lower.contains("pathumma") { return 2 }
            if badge == "FREE" { return 0 }
            return 1
        }
        liveModels.sort { a, b in
            let ga = groupRank(a.id, badge: a.badge)
            let gb = groupRank(b.id, badge: b.badge)
            if ga != gb { return ga < gb }
            return Self.universalModelPriorityScore(a.id) > Self.universalModelPriorityScore(b.id)
        }
        subModels.sort { a, b in
            let ga = groupRank(a.modelID, badge: a.badge)
            let gb = groupRank(b.modelID, badge: b.badge)
            if ga != gb { return ga < gb }
            return Self.universalModelPriorityScore(a.modelID) > Self.universalModelPriorityScore(b.modelID)
        }
        
        if !liveModels.isEmpty {
            if let idx = providers.firstIndex(where: { $0.id == "aipass" }) {
                providers[idx].models = liveModels
            } else {
                providers.append(AIProviderDefinition(
                    id: "aipass",
                    name: "TH-AI Passport",
                    icon: "aipass",
                    endpoint: "https://de.aipass.net",
                    models: liveModels
                ))
            }
            SubscriptionAuthManager.setLiveModels(for: .aipass, models: subModels)
        }
    }

    /// Fetches live models for 9Router, OpenRouter, Mistral, Kimi, Typhoon, Cerebras, Together, Fireworks, MiniMax, and NVIDIA NIM.
    private func fetchLiveAdditionalProviderModels() async {
        let nineRouterBase = UserDefaults.standard.string(forKey: "9router_base_url") ?? "http://127.0.0.1:20128/v1"
        let perchBase = UserDefaults.standard.string(forKey: "perch_base_url") ?? "https://api.perchai.app/v1"
        let targets: [(id: String, endpoint: String)] = [
            ("9router", "\(nineRouterBase)/models"),
            ("openrouter", "https://openrouter.ai/api/v1/models"),
            ("mistral", "https://api.mistral.ai/v1/models"),
            ("kimi", "https://api.moonshot.ai/v1/models"),
            ("perch", "\(perchBase)/models"),
            ("typhoon", "https://api.opentyphoon.ai/v1/models"),
            ("cerebras", "https://api.cerebras.ai/v1/models"),
            ("together", "https://api.together.xyz/v1/models"),
            ("fireworks", "https://api.fireworks.ai/inference/v1/models"),
            ("nvidia", "https://integrate.api.nvidia.com/v1/models")
        ]
        await withTaskGroup(of: Void.self) { group in
            for t in targets {
                group.addTask { [weak self] in
                    await self?.fetchLiveOpenAICompatibleModels(providerId: t.id, endpoint: t.endpoint)
                }
            }
        }
    }

    private func fetchLiveOpenAICompatibleModels(providerId: String, endpoint: String) async {
        let key = resolveKey(providerId)
        let allowNoKey = (providerId == "9router")
        guard (!key.isEmpty || allowNoKey), let url = URL(string: endpoint) else { return }
        var req = URLRequest(url: url, timeoutInterval: providerId == "9router" ? 3.5 : 10)
        if !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if providerId == "openrouter" {
            req.setValue("https://dotmini.net", forHTTPHeaderField: "HTTP-Referer")
            req.setValue("MicroCode IDE", forHTTPHeaderField: "X-Title")
        }

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = (json["data"] as? [[String: Any]]) ?? (json["models"] as? [[String: Any]]) else { return }

        guard let idx = providers.firstIndex(where: { $0.id == providerId }) else { return }
        var merged = providers[idx].models
        var seen = Set(merged.map(\.id))

        for item in list.prefix(60) {
            guard let mid = item["id"] as? String, seen.insert(mid).inserted else { continue }
            let lower = mid.lowercased()
            if lower.contains("embed") || lower.contains("whisper") || lower.contains("tts") || lower.contains("moderation") || lower.contains("rerank") {
                continue
            }
            let displayName = (item["name"] as? String) ?? Self.formatModelName(mid)
            let badge: String
            if lower.contains("code") || lower.contains("devstral") {
                badge = "CODE"
            } else if lower.contains("reason") || lower.contains("r1") || lower.contains("thinking") {
                badge = "REASONING"
            } else if lower.contains("flash") || lower.contains("mini") || lower.contains("8b") || lower.contains("small") {
                badge = "FAST"
            } else {
                badge = providerId.uppercased()
            }
            merged.append(AIModelDefinition(id: mid, name: displayName, provider: providerId, badge: badge))
        }

        if !merged.isEmpty {
            providers[idx].models = merged
        }
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
        case "9router":
            let base = UserDefaults.standard.string(forKey: "9router_base_url") ?? "http://127.0.0.1:20128/v1"
            await fetchLiveOpenAICompatibleModels(providerId: "9router", endpoint: "\(base)/models")
        case "openrouter": await fetchLiveOpenAICompatibleModels(providerId: "openrouter", endpoint: "https://openrouter.ai/api/v1/models")
        case "mistral": await fetchLiveOpenAICompatibleModels(providerId: "mistral", endpoint: "https://api.mistral.ai/v1/models")
        case "kimi": await fetchLiveOpenAICompatibleModels(providerId: "kimi", endpoint: "https://api.moonshot.ai/v1/models")
        case "perch":
            let base = UserDefaults.standard.string(forKey: "perch_base_url") ?? "https://api.perchai.app/v1"
            await fetchLiveOpenAICompatibleModels(providerId: "perch", endpoint: "\(base)/models")
        case "typhoon": await fetchLiveOpenAICompatibleModels(providerId: "typhoon", endpoint: "https://api.opentyphoon.ai/v1/models")
        case "cerebras": await fetchLiveOpenAICompatibleModels(providerId: "cerebras", endpoint: "https://api.cerebras.ai/v1/models")
        case "together": await fetchLiveOpenAICompatibleModels(providerId: "together", endpoint: "https://api.together.xyz/v1/models")
        case "fireworks": await fetchLiveOpenAICompatibleModels(providerId: "fireworks", endpoint: "https://api.fireworks.ai/inference/v1/models")
        case "nvidia": await fetchLiveOpenAICompatibleModels(providerId: "nvidia", endpoint: "https://integrate.api.nvidia.com/v1/models")
        case "perplexity", "minimax": break
        case "copilot", "github": await fetchLiveCopilotModels()
        case "aipass": await fetchLiveAiPassModels()
        case "agy", "codex", "claude_code", "opencode", "zed", "gemini_cli", "cursor", "goose", "cline", "aider":
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
            let modelDef = known[rawID] ?? AIModelDefinition(id: rawID, name: formattedName, provider: providerID, badge: "LIVE")
            
            // Add strictly to its true provider (e.g. gemini, anthropic, openai, deepseek) — never rebrand under Dotmini
            if let providerIndex = result.firstIndex(where: { $0.id == providerID }) {
                if !result[providerIndex].models.contains(where: { $0.id == rawID }) {
                    result[providerIndex].models.append(modelDef)
                    touchedProviders.insert(providerIndex)
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
        case "gemini_cli": return "Google Gemini CLI"
        case "openai": return "OpenAI"
        case "claude_code", "claude": return "Claude Code"
        case "anthropic": return "Anthropic"
        case "opencode": return "OpenCode"
        case "codex": return "Codex"
        case "cursor", "cursor-agent": return "Cursor Agent"
        case "goose": return "Block Goose"
        case "cline": return "Cline"
        case "roo": return "Roo Code"
        case "windsurf": return "Windsurf"
        case "amp": return "Sourcegraph Amp"
        case "zed": return "Zed"
        case "aider": return "Aider"
        case "omni": return "Dotmini Cloud"
        case "deepseek": return "DeepSeek"
        case "9router": return "9Router Gateway"
        case "openrouter": return "OpenRouter"
        case "litellm": return "LiteLLM"
        case "vllm": return "vLLM"
        case "lmstudio": return "LM Studio"
        case "groq": return "Groq"
        case "mistral": return "Mistral AI"
        case "kimi", "moonshot": return "Moonshot Kimi"
        case "perplexity": return "Perplexity Sonar"
        case "perch": return "Perch AI"
        case "typhoon": return "SCB 10X Typhoon"
        case "cerebras": return "Cerebras"
        case "together": return "Together AI"
        case "fireworks": return "Fireworks AI"
        case "minimax": return "MiniMax"
        case "nvidia": return "NVIDIA NIM"
        case "qwen": return "Alibaba Qwen"
        case "grok": return "xAI Grok"
        case "glm": return "Zhipu GLM"
        case "copilot": return "GitHub Copilot"
        case "aipass": return "TH-AI Passport"
        case "local": return "Local LLM"
        default: return provider.isEmpty ? "AI" : provider.capitalized
        }
    }

    nonisolated public static func formatFullDisplayName(provider: String?, modelId: String, modelName: String? = nil) -> String {
        let inferred = inferProvider(modelId)
        let provId: String = {
            if let p = provider, !p.isEmpty {
                if p.lowercased() == "omni" && inferred != "omni" {
                    return inferred
                }
                return p
            }
            return inferred
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
            case "deepseek": formattedParts.append("DeepSeek")
            case "glm": formattedParts.append("GLM")
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
            if owner.contains("openrouter") { return "openrouter" }
            if owner.contains("mistral") { return "mistral" }
            if owner.contains("moonshot") || owner.contains("kimi") { return "kimi" }
            if owner.contains("perplexity") { return "perplexity" }
            if owner.contains("perch") { return "perch" }
            if owner.contains("typhoon") || owner.contains("scb") { return "typhoon" }
            if owner.contains("cerebras") { return "cerebras" }
            if owner.contains("together") { return "together" }
            if owner.contains("fireworks") { return "fireworks" }
            if owner.contains("minimax") { return "minimax" }
            if owner.contains("nvidia") { return "nvidia" }
            if owner.contains("qwen") || owner.contains("alibaba") { return "qwen" }
            if owner.contains("groq") { return "groq" }
            if owner.contains("zhipu") || owner.contains("glm") { return "glm" }
        }
        let value = model.lowercased()
        if value.hasPrefix("accounts/fireworks/") { return "fireworks" }
        if value.hasPrefix("nvidia/") || value.contains("nemotron") { return "nvidia" }
        if value.contains("codestral") || value.contains("devstral") || value.contains("mistral") || value.contains("pixtral") { return "mistral" }
        if value.contains("moonshot") || value.hasPrefix("kimi-") { return "kimi" }
        if value.hasPrefix("sonar") { return "perplexity" }
        if value.hasPrefix("perch") { return "perch" }
        if value.hasPrefix("typhoon-") { return "typhoon" }
        if value.hasPrefix("minimax") || value.contains("abab") { return "minimax" }
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
        AIProviderDefinition(id: "gemini", name: "Google Gemini", icon: "sparkles", endpoint: "generativelanguage.googleapis.com", models: [
            AIModelDefinition(id: "gemini-4-argon", name: "Gemini 4 Argon (Pro / Ultra)", provider: "gemini", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gemini-4-argon-high", name: "Gemini 4 Argon (High Thinking)", provider: "gemini", badge: "THINKING"),
            AIModelDefinition(id: "gemini-4-argon-medium", name: "Gemini 4 Argon (Medium Thinking)", provider: "gemini", badge: "THINKING"),
            AIModelDefinition(id: "gemini-4-argon-low", name: "Gemini 4 Argon (Low Thinking)", provider: "gemini", badge: "FAST"),
            AIModelDefinition(id: "gemini-3.8-pro", name: "Gemini 3.8 Pro", provider: "gemini", badge: "PRO"),
            AIModelDefinition(id: "gemini-3.8-flash-tiered", name: "Gemini 3.8 Flash (Ultra)", provider: "gemini", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gemini-3.8-flash-high", name: "Gemini 3.8 Flash (High Thinking)", provider: "gemini", badge: "THINKING"),
            AIModelDefinition(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash", provider: "gemini", badge: "FAST"),
            AIModelDefinition(id: "gemini-3.7-pro", name: "Gemini 3.7 Pro", provider: "gemini", badge: "PRO"),
            AIModelDefinition(id: "gemini-3.7-flash", name: "Gemini 3.7 Flash", provider: "gemini", badge: "FAST"),
            AIModelDefinition(id: "gemini-3.6-pro", name: "Gemini 3.6 Pro", provider: "gemini", badge: "PRO"),
            AIModelDefinition(id: "gemini-3.6-flash", name: "Gemini 3.6 Flash", provider: "gemini", badge: "FAST"),
            AIModelDefinition(id: "gemini-3.5-pro", name: "Gemini 3.5 Pro", provider: "gemini", badge: "PRO"),
            AIModelDefinition(id: "gemini-3.5-flash", name: "Gemini 3.5 Flash", provider: "gemini", badge: "FAST"),
            AIModelDefinition(id: "gemini-3.5-flash-lite", name: "Gemini 3.5 Flash Lite", provider: "gemini", badge: "FAST"),
            AIModelDefinition(id: "gemini-3.1-pro-preview", name: "Gemini 3.1 Pro Preview", provider: "gemini", badge: "PRO"),
            AIModelDefinition(id: "gemini-3.1-flash-lite", name: "Gemini 3.1 Flash Lite", provider: "gemini", badge: "FAST"),
            AIModelDefinition(id: "gemini-3-flash-preview", name: "Gemini 3 Flash Preview", provider: "gemini", badge: "FAST"),
            AIModelDefinition(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", provider: "gemini", badge: "PRO"),
            AIModelDefinition(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", provider: "gemini", badge: "FAST"),
            AIModelDefinition(id: "gemini-2.5-flash-lite", name: "Gemini 2.5 Flash Lite", provider: "gemini", badge: "FAST")
        ]),
        AIProviderDefinition(id: "anthropic", name: "Anthropic Claude", icon: "bubble.left.and.text.bubble.right", endpoint: "api.anthropic.com", models: [
            AIModelDefinition(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", provider: "anthropic", badge: "AGENT"),
            AIModelDefinition(id: "claude-opus-5-5", name: "Claude Opus 5.5", provider: "anthropic", badge: "REASONING"),
            AIModelDefinition(id: "claude-sonnet-5-5-high", name: "Claude Sonnet 5.5 (High Thinking)", provider: "anthropic", badge: "THINKING"),
            AIModelDefinition(id: "claude-opus-5-5-high", name: "Claude Opus 5.5 (High Thinking)", provider: "anthropic", badge: "THINKING"),
            AIModelDefinition(id: "claude-haiku-5-5", name: "Claude Haiku 5.5", provider: "anthropic", badge: "FAST"),
            AIModelDefinition(id: "claude-sonnet-5", name: "Claude Sonnet 5", provider: "anthropic", badge: "AGENT"),
            AIModelDefinition(id: "claude-opus-5", name: "Claude Opus 5", provider: "anthropic", badge: "REASONING"),
            AIModelDefinition(id: "claude-opus-4-8", name: "Claude Opus 4.8", provider: "anthropic", badge: "REASONING"),
            AIModelDefinition(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", provider: "anthropic", badge: "AGENT"),
            AIModelDefinition(id: "claude-opus-4-6", name: "Claude Opus 4.6", provider: "anthropic", badge: "REASONING"),
            AIModelDefinition(id: "claude-sonnet-4-5", name: "Claude Sonnet 4.5", provider: "anthropic", badge: "AGENT"),
            AIModelDefinition(id: "claude-haiku-4-5", name: "Claude Haiku 4.5", provider: "anthropic", badge: "FAST")
        ]),
        AIProviderDefinition(id: "openai", name: "OpenAI", icon: "brain.head.profile", endpoint: "api.openai.com", models: [
            AIModelDefinition(id: "gpt-6.1-sol", name: "GPT-6.1 Sol", provider: "openai", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gpt-6-sol", name: "GPT-6 Sol", provider: "openai", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gpt-6-luna", name: "GPT-6 Luna", provider: "openai", badge: "FAST"),
            AIModelDefinition(id: "gpt-6-astra", name: "GPT-6 Astra", provider: "openai", badge: "REASONING"),
            AIModelDefinition(id: "gpt-5.6-sol", name: "GPT-5.6 Sol", provider: "openai", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", provider: "openai", badge: "FAST"),
            AIModelDefinition(id: "gpt-5.5", name: "GPT-5.5", provider: "openai", badge: "CHAT"),
            AIModelDefinition(id: "gpt-5.4", name: "GPT-5.4", provider: "openai", badge: "CHAT"),
            AIModelDefinition(id: "gpt-5.4-mini", name: "GPT-5.4 Mini", provider: "openai", badge: "FAST"),
            AIModelDefinition(id: "gpt-5.3-codex", name: "GPT-5.3 Codex", provider: "openai", badge: "AGENT"),
            AIModelDefinition(id: "o3", name: "OpenAI o3", provider: "openai", badge: "REASONING"),
            AIModelDefinition(id: "o4-mini", name: "OpenAI o4-mini", provider: "openai", badge: "REASONING"),
            AIModelDefinition(id: "gpt-4.1", name: "GPT-4.1", provider: "openai", badge: "CODE"),
            AIModelDefinition(id: "gpt-4o", name: "GPT-4o", provider: "openai", badge: "FAST")
        ]),
        AIProviderDefinition(id: "deepseek", name: "DeepSeek", icon: "water.waves", endpoint: "api.deepseek.com", models: [
            AIModelDefinition(id: "deepseek-flash", name: "DeepSeek V4.1 Flash", provider: "deepseek", badge: "FAST"),
            AIModelDefinition(id: "deepseek-v4-pro", name: "DeepSeek V4 Pro", provider: "deepseek", badge: "FLAGSHIP"),
            AIModelDefinition(id: "deepseek-v3.2", name: "DeepSeek V3.2", provider: "deepseek", badge: "CHAT"),
            AIModelDefinition(id: "deepseek-chat", name: "DeepSeek V3.2 Chat", provider: "deepseek", badge: "CHAT"),
            AIModelDefinition(id: "deepseek-reasoner", name: "DeepSeek R1 Reasoner", provider: "deepseek", badge: "REASONING")
        ]),
        AIProviderDefinition(id: "omni", name: "Dotmini Sovereign AI", icon: "sparkles", endpoint: "api.dotmini.net/v1", models: [
            AIModelDefinition(id: "omni-o1x-pro", name: "Omni O1X Pro (3B MoE)", provider: "omni", badge: "SOVEREIGN"),
            AIModelDefinition(id: "omni-o1x-lite", name: "Omni O1X Lite (0.8B)", provider: "omni", badge: "FAST")
        ]),
        AIProviderDefinition(id: "copilot", name: "GitHub Copilot", icon: "github", endpoint: "api.githubcopilot.com", models: [
            AIModelDefinition(id: "auto", name: "Copilot Auto", provider: "copilot", badge: "AUTO"),
            AIModelDefinition(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5 (Copilot)", provider: "copilot", badge: "AGENT"),
            AIModelDefinition(id: "claude-opus-5-5", name: "Claude Opus 5.5 (Copilot)", provider: "copilot", badge: "FLAGSHIP"),
            AIModelDefinition(id: "claude-sonnet-4.5", name: "Claude Sonnet 4.5 (Copilot)", provider: "copilot", badge: "AGENT"),
            AIModelDefinition(id: "gpt-6.1-sol", name: "GPT-6.1 Sol (Copilot)", provider: "copilot", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gpt-5.4", name: "GPT-5.4 (Copilot)", provider: "copilot", badge: "COPILOT"),
            AIModelDefinition(id: "gpt-5", name: "GPT-5 (Copilot)", provider: "copilot", badge: "COPILOT"),
            AIModelDefinition(id: "gpt-4.1", name: "GPT-4.1 (Copilot)", provider: "copilot", badge: "COPILOT"),
            AIModelDefinition(id: "gpt-4o", name: "GPT-4o (Copilot)", provider: "copilot", badge: "COPILOT"),
            AIModelDefinition(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro (Copilot)", provider: "copilot", badge: "PRO")
        ]),
        AIProviderDefinition(id: "aipass", name: "TH-AI Passport", icon: "aipass", endpoint: "de.aipass.net", models: [
            AIModelDefinition(id: "gemini-3.5-flash-lite", name: "Gemini 3.5 Flash Lite (Free)", provider: "aipass", badge: "FREE"),
            AIModelDefinition(id: "claude-sonnet-5-5@azure", name: "Claude Sonnet 5.5 (AiPASS)", provider: "aipass", badge: "AGENT"),
            AIModelDefinition(id: "claude-opus-5-5@azure", name: "Claude Opus 5.5 (AiPASS)", provider: "aipass", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gpt-6.1-sol", name: "GPT 6.1 Sol (AiPASS)", provider: "aipass", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gpt-6-astra", name: "GPT 6 Astra (AiPASS)", provider: "aipass", badge: "REASONING"),
            AIModelDefinition(id: "gpt-5.6-terra", name: "GPT 5.6 Terra (AiPASS)", provider: "aipass", badge: "FAST"),
            AIModelDefinition(id: "gemini-4-argon", name: "Gemini 4 Argon (AiPASS)", provider: "aipass", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash (AiPASS)", provider: "aipass", badge: "FAST"),
            AIModelDefinition(id: "DeepSeek-V4-Flash", name: "DeepSeek V4 Flash (AiPASS)", provider: "aipass", badge: "FAST"),
            AIModelDefinition(id: "glm-5.3", name: "GLM 5.3 (AiPASS)", provider: "aipass", badge: "FLAGSHIP"),
            AIModelDefinition(id: "Kimi-K2.7-Code", name: "Kimi K2.7 Code (AiPASS)", provider: "aipass", badge: "CODE"),
            AIModelDefinition(id: "grok-4.6", name: "Grok 4.6 (AiPASS)", provider: "aipass", badge: "FLAGSHIP"),
            AIModelDefinition(id: "typhoon2.5-qwen3-30b", name: "Typhoon 2.5 30B (AiPASS)", provider: "aipass", badge: "THAI"),
            // Image Generation Models
            AIModelDefinition(id: "gemini-2.5-flash-image", name: "Nano Banana — Gemini 2.5 Flash Image (Free)", provider: "aipass", badge: "IMAGE"),
            AIModelDefinition(id: "gemini-3.1-flash-lite-image", name: "Nano Banana 2 Lite — Gemini 3.1 Image (Free)", provider: "aipass", badge: "IMAGE"),
            AIModelDefinition(id: "gemini-3.1-flash-image", name: "Nano Banana 2 — Gemini 3.1 Flash Image (AiPASS)", provider: "aipass", badge: "IMAGE"),
            AIModelDefinition(id: "gemini-nano-banana-2.1", name: "Nano Banana 2.1 — Gemini Image (AiPASS)", provider: "aipass", badge: "IMAGE"),
            AIModelDefinition(id: "gemini-3-pro-image", name: "Nano Banana Pro — Gemini 3 Pro Image (AiPASS)", provider: "aipass", badge: "IMAGE"),
            AIModelDefinition(id: "FLUX.2-pro", name: "Flux 2 Pro — Studio Image (AiPASS)", provider: "aipass", badge: "IMAGE"),
            AIModelDefinition(id: "gpt-image-2", name: "GPT-Image-2 (AiPASS)", provider: "aipass", badge: "IMAGE"),
            AIModelDefinition(id: "gpt-image-2.5-flare", name: "GPT-Image-2.5 Flare (AiPASS)", provider: "aipass", badge: "IMAGE"),
            AIModelDefinition(id: "seedream-5.0-flash", name: "Seedream 5.0 Flash — Image (AiPASS)", provider: "aipass", badge: "IMAGE"),
            AIModelDefinition(id: "seedream-5.0-pro", name: "Seedream 5.0 Pro — Image (AiPASS)", provider: "aipass", badge: "IMAGE"),
            // Video Generation Models
            AIModelDefinition(id: "veo-3.1-fast-generate-001", name: "Veo 3.1 Fast — Video Gen (AiPASS)", provider: "aipass", badge: "VIDEO"),
            AIModelDefinition(id: "veo-3.1-generate-001", name: "Veo 3.1 — Cinema Video Gen (AiPASS)", provider: "aipass", badge: "VIDEO"),
            AIModelDefinition(id: "veo-3.0-generate-001", name: "Veo 3.0 — Video Gen (AiPASS)", provider: "aipass", badge: "VIDEO"),
            AIModelDefinition(id: "seedance-2.0-fast", name: "Seedance 2.0 Fast — Video Gen (AiPASS)", provider: "aipass", badge: "VIDEO"),
            AIModelDefinition(id: "seedance-2.0", name: "Seedance 2.0 — Video Gen (AiPASS)", provider: "aipass", badge: "VIDEO"),
            AIModelDefinition(id: "wan2.2@jts", name: "Wan 2.2 — Video Gen (AiPASS)", provider: "aipass", badge: "VIDEO"),
            AIModelDefinition(id: "sora-2", name: "Sora 2 — Video Gen (AiPASS)", provider: "aipass", badge: "VIDEO"),
            // Music & Audio Generation Models
            AIModelDefinition(id: "lyria-3-clip-preview", name: "Lyria 3 Clip — 30s Music Gen (AiPASS)", provider: "aipass", badge: "MUSIC"),
            AIModelDefinition(id: "lyria-3-pro-preview", name: "Lyria 3 Pro — Full Song + Vocals (AiPASS)", provider: "aipass", badge: "MUSIC")
        ]),
        AIProviderDefinition(id: "9router", name: "9Router Smart Gateway", icon: "9router", endpoint: "localhost:20128/v1", models: [
            AIModelDefinition(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6 (9Router Tier 1)", provider: "9router", badge: "3-TIER AUTO"),
            AIModelDefinition(id: "claude-opus-4-6", name: "Claude Opus 4.6 (9Router Tier 1)", provider: "9router", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gpt-5.4", name: "GPT-5.4 (9Router Tier 1)", provider: "9router", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro (9Router Tier 1)", provider: "9router", badge: "PRO"),
            AIModelDefinition(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash (9Router Tier 3 Free)", provider: "9router", badge: "FREE TIER"),
            AIModelDefinition(id: "glm-4.7", name: "GLM-4.7 (9Router Tier 2 Cheap)", provider: "9router", badge: "CHEAP TIER"),
            AIModelDefinition(id: "kimi-k2", name: "Kimi K2 (9Router Tier 2 Cheap)", provider: "9router", badge: "CHEAP TIER"),
            AIModelDefinition(id: "qwen3-coder-plus", name: "Qwen3 Coder Plus (9Router Tier 3 Free)", provider: "9router", badge: "FREE TIER"),
            AIModelDefinition(id: "deepseek-r1", name: "DeepSeek R1 (9Router Smart Fallback)", provider: "9router", badge: "REASONING")
        ]),
        AIProviderDefinition(id: "openrouter", name: "OpenRouter", icon: "point.3.connected.trianglepath.dotted", endpoint: "openrouter.ai/api/v1", models: [
            AIModelDefinition(id: "anthropic/claude-sonnet-4", name: "Claude Sonnet 4 (OpenRouter)", provider: "openrouter", badge: "AGENT"),
            AIModelDefinition(id: "anthropic/claude-opus-4", name: "Claude Opus 4 (OpenRouter)", provider: "openrouter", badge: "FLAGSHIP"),
            AIModelDefinition(id: "google/gemini-2.5-pro", name: "Gemini 2.5 Pro (OpenRouter)", provider: "openrouter", badge: "FLAGSHIP"),
            AIModelDefinition(id: "google/gemini-2.5-flash", name: "Gemini 2.5 Flash (OpenRouter)", provider: "openrouter", badge: "FAST"),
            AIModelDefinition(id: "openai/gpt-4.1", name: "GPT-4.1 (OpenRouter)", provider: "openrouter", badge: "CODE"),
            AIModelDefinition(id: "openai/o3", name: "OpenAI o3 (OpenRouter)", provider: "openrouter", badge: "REASONING"),
            AIModelDefinition(id: "deepseek/deepseek-r1-0528", name: "DeepSeek R1 0528 (OpenRouter)", provider: "openrouter", badge: "REASONING"),
            AIModelDefinition(id: "deepseek/deepseek-chat-v3-0324", name: "DeepSeek V3 0324 (OpenRouter)", provider: "openrouter", badge: "CHAT"),
            AIModelDefinition(id: "qwen/qwen3-coder", name: "Qwen3 Coder (OpenRouter)", provider: "openrouter", badge: "CODE"),
            AIModelDefinition(id: "moonshotai/kimi-k2", name: "Kimi K2 (OpenRouter)", provider: "openrouter", badge: "AGENT"),
            AIModelDefinition(id: "mistralai/codestral-2501", name: "Codestral 2501 (OpenRouter)", provider: "openrouter", badge: "CODE"),
            AIModelDefinition(id: "x-ai/grok-3", name: "Grok 3 (OpenRouter)", provider: "openrouter", badge: "FLAGSHIP")
        ]),
        AIProviderDefinition(id: "groq", name: "Groq (LPU Inference)", icon: "bolt.horizontal.fill", endpoint: "api.groq.com/openai/v1", models: [
            AIModelDefinition(id: "llama-3.3-70b-versatile", name: "Llama 3.3 70B Versatile", provider: "groq", badge: "LPU FAST"),
            AIModelDefinition(id: "llama-3.1-8b-instant", name: "Llama 3.1 8B Instant", provider: "groq", badge: "ULTRA FAST"),
            AIModelDefinition(id: "deepseek-r1-distill-llama-70b", name: "DeepSeek R1 Distill Llama 70B", provider: "groq", badge: "REASONING"),
            AIModelDefinition(id: "qwen/qwen3-32b", name: "Qwen 3 32B (Groq LPU)", provider: "groq", badge: "CODE"),
            AIModelDefinition(id: "meta-llama/llama-4-scout-17b-16e-instruct", name: "Llama 4 Scout 17B", provider: "groq", badge: "FAST"),
            AIModelDefinition(id: "meta-llama/llama-4-maverick-17b-128e-instruct", name: "Llama 4 Maverick 17B", provider: "groq", badge: "FLAGSHIP")
        ]),
        AIProviderDefinition(id: "mistral", name: "Mistral AI & Codestral", icon: "wind", endpoint: "api.mistral.ai/v1", models: [
            AIModelDefinition(id: "codestral-latest", name: "Codestral Latest", provider: "mistral", badge: "CODE"),
            AIModelDefinition(id: "devstral-small-latest", name: "Devstral Small (SWE Agent)", provider: "mistral", badge: "AGENT"),
            AIModelDefinition(id: "mistral-large-latest", name: "Mistral Large", provider: "mistral", badge: "FLAGSHIP"),
            AIModelDefinition(id: "mistral-medium-latest", name: "Mistral Medium 3", provider: "mistral", badge: "CHAT"),
            AIModelDefinition(id: "mistral-small-latest", name: "Mistral Small 3.1", provider: "mistral", badge: "FAST"),
            AIModelDefinition(id: "magistral-medium-latest", name: "Magistral Medium (Reasoning)", provider: "mistral", badge: "REASONING"),
            AIModelDefinition(id: "pixtral-large-latest", name: "Pixtral Large (Vision)", provider: "mistral", badge: "VISION")
        ]),
        AIProviderDefinition(id: "kimi", name: "Moonshot AI (Kimi)", icon: "moon.stars.fill", endpoint: "api.moonshot.ai/v1", models: [
            AIModelDefinition(id: "kimi-k2-0711-preview", name: "Kimi K2 (1T MoE Coding & Agent)", provider: "kimi", badge: "AGENT"),
            AIModelDefinition(id: "kimi-latest", name: "Kimi Latest (Auto Context)", provider: "kimi", badge: "FLAGSHIP"),
            AIModelDefinition(id: "kimi-thinking-preview", name: "Kimi Thinking Preview", provider: "kimi", badge: "REASONING"),
            AIModelDefinition(id: "moonshot-v1-128k", name: "Moonshot V1 128K", provider: "kimi", badge: "128K"),
            AIModelDefinition(id: "moonshot-v1-32k", name: "Moonshot V1 32K", provider: "kimi", badge: "FAST")
        ]),
        AIProviderDefinition(id: "perplexity", name: "Perplexity Sonar", icon: "magnifyingglass.circle.fill", endpoint: "api.perplexity.ai", models: [
            AIModelDefinition(id: "sonar-reasoning-pro", name: "Sonar Reasoning Pro (Live Web)", provider: "perplexity", badge: "SEARCH+REASON"),
            AIModelDefinition(id: "sonar-pro", name: "Sonar Pro (Live Citations)", provider: "perplexity", badge: "SEARCH PRO"),
            AIModelDefinition(id: "sonar-reasoning", name: "Sonar Reasoning", provider: "perplexity", badge: "REASONING"),
            AIModelDefinition(id: "sonar", name: "Sonar (Fast Web Search)", provider: "perplexity", badge: "FAST"),
            AIModelDefinition(id: "sonar-deep-research", name: "Sonar Deep Research", provider: "perplexity", badge: "RESEARCH")
        ]),
        AIProviderDefinition(id: "perch", name: "Perch AI", icon: "bird.fill", endpoint: "api.perchai.app/v1", models: [
            AIModelDefinition(id: "perch-1-pro", name: "Perch 1 Pro Flagship", provider: "perch", badge: "FLAGSHIP"),
            AIModelDefinition(id: "perch-coder-v2", name: "Perch Coder v2 (Autonomous SWE)", provider: "perch", badge: "CODE"),
            AIModelDefinition(id: "perch-1-fast", name: "Perch 1 Fast (Low-Latency)", provider: "perch", badge: "FAST"),
            AIModelDefinition(id: "perch-reasoning-r1", name: "Perch Reasoning R1", provider: "perch", badge: "REASONING")
        ]),
        AIProviderDefinition(id: "typhoon", name: "SCB 10X Typhoon", icon: "hurricane", endpoint: "api.opentyphoon.ai/v1", models: [
            AIModelDefinition(id: "typhoon-v2.1-12b-instruct", name: "Typhoon v2.1 12B Instruct", provider: "typhoon", badge: "THAI"),
            AIModelDefinition(id: "typhoon-v2-70b-instruct", name: "Typhoon v2 70B Instruct", provider: "typhoon", badge: "FLAGSHIP"),
            AIModelDefinition(id: "typhoon-v2-r1-70b-preview", name: "Typhoon v2 R1 70B Reasoning", provider: "typhoon", badge: "REASONING"),
            AIModelDefinition(id: "typhoon-v2-8b-instruct", name: "Typhoon v2 8B Instruct", provider: "typhoon", badge: "FAST")
        ]),
        AIProviderDefinition(id: "cerebras", name: "Cerebras Inference", icon: "memorychip.fill", endpoint: "api.cerebras.ai/v1", models: [
            AIModelDefinition(id: "llama-3.3-70b", name: "Llama 3.3 70B (Wafer-Scale 2000+ tok/s)", provider: "cerebras", badge: "WAFER FAST"),
            AIModelDefinition(id: "qwen-3-32b", name: "Qwen 3 32B (Cerebras)", provider: "cerebras", badge: "CODE"),
            AIModelDefinition(id: "llama-4-scout-17b-16e-instruct", name: "Llama 4 Scout 17B (Cerebras)", provider: "cerebras", badge: "FAST"),
            AIModelDefinition(id: "deepseek-r1-distill-llama-70b", name: "DeepSeek R1 Distill 70B (Cerebras)", provider: "cerebras", badge: "REASONING"),
            AIModelDefinition(id: "llama3.1-8b", name: "Llama 3.1 8B (Cerebras)", provider: "cerebras", badge: "ULTRA FAST")
        ]),
        AIProviderDefinition(id: "together", name: "Together AI", icon: "square.stack.3d.up.fill", endpoint: "api.together.xyz/v1", models: [
            AIModelDefinition(id: "Qwen/Qwen2.5-Coder-32B-Instruct", name: "Qwen 2.5 Coder 32B Instruct", provider: "together", badge: "CODE"),
            AIModelDefinition(id: "Qwen/Qwen3-235B-A22B-fp8-tput", name: "Qwen 3 235B A22B MoE", provider: "together", badge: "FLAGSHIP"),
            AIModelDefinition(id: "deepseek-ai/DeepSeek-R1", name: "DeepSeek R1 (Together)", provider: "together", badge: "REASONING"),
            AIModelDefinition(id: "deepseek-ai/DeepSeek-V3", name: "DeepSeek V3 (Together)", provider: "together", badge: "CHAT"),
            AIModelDefinition(id: "meta-llama/Llama-3.3-70B-Instruct-Turbo", name: "Llama 3.3 70B Instruct Turbo", provider: "together", badge: "FAST"),
            AIModelDefinition(id: "meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8", name: "Llama 4 Maverick 17B", provider: "together", badge: "FLAGSHIP")
        ]),
        AIProviderDefinition(id: "fireworks", name: "Fireworks AI", icon: "flame.fill", endpoint: "api.fireworks.ai/inference/v1", models: [
            AIModelDefinition(id: "accounts/fireworks/models/deepseek-v3", name: "DeepSeek V3 (Fireworks)", provider: "fireworks", badge: "FLAGSHIP"),
            AIModelDefinition(id: "accounts/fireworks/models/deepseek-r1", name: "DeepSeek R1 (Fireworks)", provider: "fireworks", badge: "REASONING"),
            AIModelDefinition(id: "accounts/fireworks/models/qwen3-235b-a22b", name: "Qwen 3 235B A22B (Fireworks)", provider: "fireworks", badge: "FLAGSHIP"),
            AIModelDefinition(id: "accounts/fireworks/models/qwen2p5-coder-32b-instruct", name: "Qwen 2.5 Coder 32B (Fireworks)", provider: "fireworks", badge: "CODE"),
            AIModelDefinition(id: "accounts/fireworks/models/llama-v3p3-70b-instruct", name: "Llama 3.3 70B Instruct (Fireworks)", provider: "fireworks", badge: "FAST")
        ]),
        AIProviderDefinition(id: "minimax", name: "MiniMax", icon: "waveform.path.ecg", endpoint: "api.minimax.io/v1", models: [
            AIModelDefinition(id: "MiniMax-M1", name: "MiniMax M1 (1M Context Reasoning)", provider: "minimax", badge: "REASONING"),
            AIModelDefinition(id: "MiniMax-Text-01", name: "MiniMax Text 01 (4M Context)", provider: "minimax", badge: "4M CTX"),
            AIModelDefinition(id: "abab6.5s-chat", name: "ABAB 6.5s Chat", provider: "minimax", badge: "FAST")
        ]),
        AIProviderDefinition(id: "nvidia", name: "NVIDIA NIM", icon: "cpu.fill", endpoint: "integrate.api.nvidia.com/v1", models: [
            AIModelDefinition(id: "nvidia/llama-3.1-nemotron-ultra-253b-v1", name: "Llama 3.1 Nemotron Ultra 253B", provider: "nvidia", badge: "FLAGSHIP"),
            AIModelDefinition(id: "nvidia/llama-3.3-nemotron-super-49b-v1", name: "Llama 3.3 Nemotron Super 49B", provider: "nvidia", badge: "REASONING"),
            AIModelDefinition(id: "deepseek-ai/deepseek-r1", name: "DeepSeek R1 (NVIDIA NIM)", provider: "nvidia", badge: "REASONING"),
            AIModelDefinition(id: "qwen/qwen2.5-coder-32b-instruct", name: "Qwen 2.5 Coder 32B (NVIDIA NIM)", provider: "nvidia", badge: "CODE"),
            AIModelDefinition(id: "meta/llama-3.3-70b-instruct", name: "Llama 3.3 70B Instruct (NVIDIA NIM)", provider: "nvidia", badge: "FAST")
        ]),
        AIProviderDefinition(id: "qwen", name: "Alibaba Qwen (DashScope)", icon: "cloud.fill", endpoint: "dashscope.aliyuncs.com", models: [
            AIModelDefinition(id: "qwen-max", name: "Qwen Max (Flagship)", provider: "qwen", badge: "FLAGSHIP"),
            AIModelDefinition(id: "qwen-plus", name: "Qwen Plus", provider: "qwen", badge: "CHAT"),
            AIModelDefinition(id: "qwen-turbo", name: "Qwen Turbo", provider: "qwen", badge: "FAST"),
            AIModelDefinition(id: "qwen3-coder-plus", name: "Qwen3 Coder Plus", provider: "qwen", badge: "CODE"),
            AIModelDefinition(id: "qwen2.5-coder-32b-instruct", name: "Qwen 2.5 Coder 32B Instruct", provider: "qwen", badge: "CODE"),
            AIModelDefinition(id: "qwq-plus", name: "QwQ Plus (Reasoning)", provider: "qwen", badge: "REASONING")
        ]),
        AIProviderDefinition(id: "grok", name: "xAI Grok", icon: "bolt.fill", endpoint: "api.x.ai", models: [
            AIModelDefinition(id: "grok-3", name: "Grok 3 Flagship", provider: "grok", badge: "FLAGSHIP"),
            AIModelDefinition(id: "grok-3-mini", name: "Grok 3 Mini (Reasoning)", provider: "grok", badge: "REASONING"),
            AIModelDefinition(id: "grok-3-fast", name: "Grok 3 Fast", provider: "grok", badge: "FAST"),
            AIModelDefinition(id: "grok-2-vision-1212", name: "Grok 2 Vision", provider: "grok", badge: "VISION")
        ]),
        AIProviderDefinition(id: "glm", name: "Zhipu GLM", icon: "globe.asia.australia", endpoint: "api.z.ai", models: [
            AIModelDefinition(id: "glm-5.3-flash", name: "GLM-5.3 Flash", provider: "glm", badge: "FAST"),
            AIModelDefinition(id: "glm-5.3", name: "GLM-5.3 Flagship", provider: "glm", badge: "FLAGSHIP"),
            AIModelDefinition(id: "glm-5.2", name: "GLM-5.2", provider: "glm", badge: "CHAT"),
            AIModelDefinition(id: "glm-4.7", name: "GLM-4.7 Coding", provider: "glm", badge: "CODE")
        ]),
        AIProviderDefinition(id: "local", name: "Local LLM", icon: "desktopcomputer", endpoint: "http://127.0.0.1:11434/v1", models: [])
    ]
}
