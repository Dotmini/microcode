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

    private let cacheKey = "microcode.aiModelCatalog.v6"
    private let refreshDateKey = "microcode.aiModelCatalogRefreshDate.v6"
    private let refreshInterval: TimeInterval = 10 * 60 // 10 minutes

    private init() {
        providers = Self.fallbackProviders
        loadCachedCatalog()
        Task {
            await refreshIfNeeded(force: true)
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
            return (fallbackProvider.id, fallbackProvider.models.first?.id ?? "gemini-3.7-flash")
        }
        
        let lower = trimmed.lowercased()
        var targetModel = trimmed
        if lower == "gemini" || lower == "gemini-flash" {
            targetModel = "gemini-3.7-flash"
        } else if lower == "gemini-pro" {
            targetModel = "gemini-2.5-pro"
        } else if lower == "deepseek" {
            targetModel = "deepseek-v4-flash"
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

    /// Dynamically fetches models directly from active provider APIs (OpenAI, Gemini, Anthropic, DeepSeek)
    /// and local installed engines (Codex, AGY, Claude Code, Zed).
    public func refreshLiveProviderModels() async {
        await refreshCloudProxyModels()
        await fetchLiveOpenAIModels()
        await fetchLiveGeminiModels()
        await fetchLiveAnthropicModels()
        await fetchLiveDeepSeekModels()
        await fetchLiveGLMModels()
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
        let key = UserDefaults.standard.string(forKey: "openai_api_key") ?? UserDefaults.standard.string(forKey: "apiKey") ?? ""
        guard !key.isEmpty, let url = URL(string: "https://api.openai.com/v1/models") else { return }
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
            guard lower.hasPrefix("gpt-6") || lower.hasPrefix("gpt-5") || lower.hasPrefix("gpt-4.5") || lower.hasPrefix("gpt-4o") || lower.hasPrefix("o3") || lower.hasPrefix("o1") || lower.hasPrefix("chatgpt") else { continue }
            guard !lower.contains("transcribe") && !lower.contains("audio") && !lower.contains("realtime") && !lower.contains("tts") && !lower.contains("search") && !lower.contains("embedding") && !lower.hasPrefix("ft:") else { continue }
            
            let badge: String
            if lower.contains("gpt-6") {
                badge = "FLAGSHIP"
            } else if lower.contains("gpt-5") {
                badge = "HIGH PERF"
            } else if lower.contains("o3") || lower.contains("o1") {
                badge = "REASONING"
            } else if lower.contains("gpt-4.5") {
                badge = "CREATIVE"
            } else {
                badge = "LATEST"
            }
            liveModels.append(AIModelDefinition(id: mid, name: Self.formatModelName(mid), provider: "openai", badge: badge))
        }
        
        liveModels.sort { a, b in
            let rank: (String) -> Int = { id in
                if id == "gpt-6-astra" { return 130 }
                if id.hasPrefix("gpt-6") { return 125 }
                if id == "gpt-5.6-sol" { return 120 }
                if id.hasPrefix("gpt-5.6") { return 115 }
                if id.hasPrefix("gpt-5") { return 110 }
                if id == "o3" { return 105 }
                if id == "o3-mini" { return 100 }
                if id == "o1-pro" { return 95 }
                if id == "o1" { return 90 }
                if id.hasPrefix("gpt-4.5") { return 85 }
                if id == "chatgpt-4o-latest" { return 80 }
                if id == "gpt-4o" { return 70 }
                if id == "gpt-4o-mini" { return 65 }
                return 10
            }
            return rank(a.id) > rank(b.id)
        }
        
        if !liveModels.isEmpty, let idx = providers.firstIndex(where: { $0.id == "openai" }) {
            providers[idx].models = liveModels
        }
    }

    private func resolveKey(_ provider: String) -> String {
        let directKey = "\(provider)_api_key"
        if let val = UserDefaults.standard.string(forKey: directKey), !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return val.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for suite in ["com.aipreneur.MicroCode", "com.dotmini.codetunner", "com.dotmini.microcode", "com.arsenal.codetunner"] {
            if let val = UserDefaults(suiteName: suite)?.string(forKey: directKey), !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return val.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if provider == "gemini", let val = UserDefaults(suiteName: "com.arsenal.codetunner")?.string(forKey: "api_key_Gemini"), !val.isEmpty {
            return val
        }
        if provider == "openai", let val = UserDefaults(suiteName: "com.dotmini.codetunner")?.string(forKey: "api_key_ChatGPT"), !val.isEmpty {
            return val
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
            guard lower.hasPrefix("gemini-") || lower.hasPrefix("gemma-") else { continue }
            guard !lower.contains("tts") && !lower.contains("embed") && !lower.contains("transcribe") && !lower.contains("audio") else { continue }
            
            if let methods = item["supportedGenerationMethods"] as? [String], !methods.contains("generateContent") {
                continue
            }
            
            let badge = (lower.contains("3.") || lower.contains("2.5")) ? "LATEST" : "FAST"
            liveModels.append(AIModelDefinition(id: mid, name: Self.formatModelName(mid), provider: "gemini", badge: badge))
        }
        
        liveModels.sort { a, b in
            let rank: (String) -> Int = { id in
                if id == "gemini-3.8-flash" || id.hasPrefix("gemini-3.8") { return 130 }
                if id == "gemini-3.7-flash" || id.hasPrefix("gemini-3.7") { return 125 }
                if id == "gemini-3.6-flash" || id.hasPrefix("gemini-3.6") { return 120 }
                if id == "gemini-3.5-flash" || id.hasPrefix("gemini-3.5") { return 115 }
                if id == "gemini-3.1-pro-preview" || id.hasPrefix("gemini-3.1") { return 110 }
                if id.hasPrefix("gemini-3") { return 105 }
                if id == "gemini-2.5-pro" { return 100 }
                if id == "gemini-2.5-flash" { return 95 }
                if id == "gemini-2.0-flash" { return 90 }
                if id == "gemini-flash-latest" { return 85 }
                if id == "gemini-pro-latest" { return 80 }
                if id.contains("2.5") { return 70 }
                if id.contains("2.0") { return 65 }
                return 10
            }
            return rank(a.id) > rank(b.id)
        }
        
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
        
        var liveModels: [AIModelDefinition] = []
        for item in list {
            guard let mid = item["id"] as? String else { continue }
            let lower = mid.lowercased()
            guard lower.contains("claude") else { continue }
            let displayName = (item["display_name"] as? String) ?? Self.formatModelName(mid)
            let badge = lower.contains("sonnet") ? "AGENT" : (lower.contains("opus") ? "REASONING" : "FAST")
            liveModels.append(AIModelDefinition(id: mid, name: displayName, provider: "anthropic", badge: badge))
        }
        
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
            let badge = mid.contains("reasoner") ? "REASONING" : "CHAT"
            let name = mid == "deepseek-reasoner" ? "DeepSeek R1 Reasoner" : (mid == "deepseek-chat" ? "DeepSeek V3 Chat" : Self.formatModelName(mid))
            liveModels.append(AIModelDefinition(id: mid, name: name, provider: "deepseek", badge: badge))
        }
        
        liveModels.sort { a, b in
            let rank: (String) -> Int = { id in
                if id == "deepseek-chat" { return 100 }
                if id == "deepseek-reasoner" { return 95 }
                return 10
            }
            return rank(a.id) > rank(b.id)
        }
        
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
            guard lower.contains("glm") || lower.contains("codegeex") else { continue }
            let badge = lower.contains("plus") ? "FLAGSHIP" : (lower.contains("codegeex") ? "CODE" : (lower.contains("air") ? "BALANCED" : "FAST"))
            let name = Self.formatModelName(mid)
            liveModels.append(AIModelDefinition(id: mid, name: name, provider: "glm", badge: badge))
        }
        
        if !liveModels.isEmpty, let idx = providers.firstIndex(where: { $0.id == "glm" }) {
            providers[idx].models = liveModels
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

    public static func formatModelName(_ id: String) -> String {
        let clean = id.replacingOccurrences(of: "models/", with: "")
        if clean == "gemini-2.5-pro" { return "Gemini 2.5 Pro" }
        if clean == "gemini-2.5-flash" { return "Gemini 2.5 Flash" }
        if clean == "gemini-3.7-flash" { return "Gemini 3.7 Flash" }
        if clean == "gemini-3.6-flash" { return "Gemini 3.6 Flash" }
        if clean == "gemini-2.0-flash" { return "Gemini 2.0 Flash" }
        if clean == "gemini-1.5-pro" { return "Gemini 1.5 Pro" }
        if clean == "gemini-1.5-flash" { return "Gemini 1.5 Flash" }
        if clean == "deepseek-reasoner" { return "DeepSeek R1 Reasoner" }
        if clean == "deepseek-chat" || clean == "deepseek-flash" { return "DeepSeek V3 Chat" }
        if clean == "claude-3-7-sonnet" { return "Claude 3.7 Sonnet" }
        if clean == "claude-3-5-sonnet" { return "Claude 3.5 Sonnet" }
        if clean == "claude-3-5-haiku" { return "Claude 3.5 Haiku" }
        if clean == "claude-3-opus" { return "Claude 3 Opus" }
        if clean == "o3-mini" { return "o3-mini" }
        if clean == "o1" { return "o1" }
        if clean == "o1-pro" { return "o1 Pro" }
        if clean == "gpt-4o" { return "GPT-4o" }
        if clean == "gpt-4o-mini" { return "GPT-4o mini" }
        if clean == "gpt-4.5-preview" { return "GPT-4.5 Preview" }
        if clean == "glm-4-plus" { return "GLM-4 Plus" }
        if clean == "glm-4-0520" { return "GLM-4 0520" }
        if clean == "glm-4-air" { return "GLM-4 Air" }
        if clean == "glm-4-airx" { return "GLM-4 AirX" }
        if clean == "glm-4-flash" { return "GLM-4 Flash" }
        if clean == "glm-4-flashx" { return "GLM-4 FlashX" }
        if clean == "codegeex-4" { return "CodeGeeX-4 (Code Specialist)" }
        if clean == "glm-4v-plus" { return "GLM-4V Plus (Multimodal)" }

        if clean == "gpt-6-astra" { return "GPT-6-Astra" }
        if clean == "gpt-5.6-sol" { return "GPT-5.6-Sol" }
        if clean == "gpt-5.6-terra" { return "GPT-5.6-Terra" }
        if clean == "gpt-5.6-luna" { return "GPT-5.6-Luna" }
        if clean == "gpt-5.5" { return "GPT-5.5" }
        if clean == "gemini-3.8-flash-high" { return "Gemini 3.8 Flash (High)" }
        if clean == "gemini-3.8-flash-medium" { return "Gemini 3.8 Flash (Medium)" }
        if clean == "gemini-3.8-flash-low" { return "Gemini 3.8 Flash (Low)" }
        if clean == "gemini-3.7-flash-high" { return "Gemini 3.7 Flash (High)" }
        if clean == "gemini-3.7-flash-medium" { return "Gemini 3.7 Flash (Medium)" }
        if clean == "gemini-3.7-flash-low" { return "Gemini 3.7 Flash (Low)" }
        if clean == "gemini-3.6-flash-high" { return "Gemini 3.6 Flash (High)" }
        if clean == "gemini-3.6-flash-medium" { return "Gemini 3.6 Flash (Medium)" }
        if clean == "gemini-3.6-flash-low" { return "Gemini 3.6 Flash (Low)" }
        if clean == "gemini-3.1-pro-high" { return "Gemini 3.1 Pro (High)" }
        if clean == "gemini-3.1-pro-low" { return "Gemini 3.1 Pro (Low)" }
        if clean == "claude-sonnet-4-6" { return "Claude Sonnet 4.6 (Thinking)" }
        if clean == "claude-opus-4-6-thinking" { return "Claude Opus 4.6 (Thinking)" }
        if clean == "gpt-oss-120b-medium" { return "GPT-OSS 120B (Medium)" }
        if clean == "deepseek-v4-flash" { return "DeepSeek V4 Flash" }
        if clean == "gpt-5.2" { return "GPT-5.2" }

        return clean
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
            .replacingOccurrences(of: "Gpt", with: "GPT")
            .replacingOccurrences(of: "Exp", with: "Experimental")
            .replacingOccurrences(of: "Tts", with: "TTS")
    }

    private static func inferProvider(_ model: String, ownedBy: String? = nil) -> String {
        if let owner = ownedBy?.lowercased() {
            if owner.contains("deepseek") { return "deepseek" }
            if owner.contains("gemini") { return "gemini" }
            if owner.contains("anthropic") || owner.contains("claude") { return "anthropic" }
            if owner.contains("openai") { return "openai" }
            if owner.contains("qwen") { return "qwen" }
        }
        let value = model.lowercased()
        if value.contains("astra") || value.contains("gpt-5.6") || value.contains("gpt-5.5") { return "codex" }
        if value.contains("3.8-flash") || value.contains("3.7-flash") || value.contains("sonnet-4-6") || value.contains("opus-4-6") || value.contains("gpt-oss-120b") { return "agy" }
        if value == "haiku" || value == "sonnet" || value == "opus" { return "claude_code" }
        if value.contains("deepseek-v4") || value == "gpt-5.2" { return "zed" }
        if value.contains("deepseek") { return "deepseek" }
        if value.contains("gemini") || value.contains("gemma") { return "gemini" }
        if value.contains("claude") { return "anthropic" }
        if value.contains("grok") { return "grok" }
        if value.contains("qwen") { return "qwen" }
        if value.contains("glm") { return "glm" }
        if value.contains("gpt") || value.contains("codex") || value.range(of: #"^o[1-9]"#, options: .regularExpression) != nil { return "openai" }
        return "omni"
    }

    private static func isChatModel(_ id: String) -> Bool {
        let excluded = ["embedding", "moderation"]
        return !excluded.contains { id.lowercased().contains($0) }
    }

    private func loadCachedCatalog() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([AIProviderDefinition].self, from: data),
              !cached.isEmpty else { return }
        providers = cached
        lastUpdated = UserDefaults.standard.object(forKey: refreshDateKey) as? Date
        source = "Dotmini cache"
    }

    private func saveCachedCatalog() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(lastUpdated, forKey: refreshDateKey)
    }

    static let fallbackProviders: [AIProviderDefinition] = [
        AIProviderDefinition(id: "agy", name: "Google Antigravity (AGY CLI)", icon: "sparkles", endpoint: "local://agy", models: [
            AIModelDefinition(id: "gemini-3.8-flash-high", name: "Gemini 3.8 Flash (High)", provider: "agy", badge: "HIGH REASONING"),
            AIModelDefinition(id: "gemini-3.8-flash-medium", name: "Gemini 3.8 Flash (Medium)", provider: "agy", badge: "MEDIUM"),
            AIModelDefinition(id: "gemini-3.8-flash-low", name: "Gemini 3.8 Flash (Low)", provider: "agy", badge: "FAST"),
            AIModelDefinition(id: "gemini-3.7-flash-high", name: "Gemini 3.7 Flash (High)", provider: "agy", badge: "HIGH"),
            AIModelDefinition(id: "gemini-3.7-flash-medium", name: "Gemini 3.7 Flash (Medium)", provider: "agy", badge: "BALANCED"),
            AIModelDefinition(id: "gemini-3.7-flash-low", name: "Gemini 3.7 Flash (Low)", provider: "agy", badge: "FAST"),
            AIModelDefinition(id: "gemini-3.6-flash-high", name: "Gemini 3.6 Flash (High)", provider: "agy", badge: "HIGH"),
            AIModelDefinition(id: "gemini-3.6-flash-medium", name: "Gemini 3.6 Flash (Medium)", provider: "agy", badge: "BALANCED"),
            AIModelDefinition(id: "gemini-3.6-flash-low", name: "Gemini 3.6 Flash (Low)", provider: "agy", badge: "FAST"),
            AIModelDefinition(id: "gemini-3.1-pro-high", name: "Gemini 3.1 Pro (High)", provider: "agy", badge: "PRO HIGH"),
            AIModelDefinition(id: "gemini-3.1-pro-low", name: "Gemini 3.1 Pro (Low)", provider: "agy", badge: "PRO"),
            AIModelDefinition(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6 (Thinking)", provider: "agy", badge: "SONNET 4.6"),
            AIModelDefinition(id: "claude-opus-4-6-thinking", name: "Claude Opus 4.6 (Thinking)", provider: "agy", badge: "OPUS 4.6"),
            AIModelDefinition(id: "gpt-oss-120b-medium", name: "GPT-OSS 120B (Medium)", provider: "agy", badge: "OPEN SOURCE")
        ]),
        AIProviderDefinition(id: "codex", name: "OpenAI Codex (~/.codex)", icon: "terminal.fill", endpoint: "local://codex", models: [
            AIModelDefinition(id: "gpt-6-astra", name: "GPT-6-Astra (Flagship)", provider: "codex", badge: "ACTIVE • CODEX"),
            AIModelDefinition(id: "gpt-5.6-sol", name: "GPT-5.6-Sol", provider: "codex", badge: "HIGH PERF"),
            AIModelDefinition(id: "gpt-5.6-terra", name: "GPT-5.6-Terra", provider: "codex", badge: "BALANCED"),
            AIModelDefinition(id: "gpt-5.6-luna", name: "GPT-5.6-Luna", provider: "codex", badge: "FAST"),
            AIModelDefinition(id: "gpt-5.5", name: "GPT-5.5", provider: "codex", badge: "STABLE")
        ]),
        AIProviderDefinition(id: "claude_code", name: "Claude Code CLI (~/.claude)", icon: "command.square.fill", endpoint: "local://claude", models: [
            AIModelDefinition(id: "haiku", name: "Claude 3.5 Haiku", provider: "claude_code", badge: "ACTIVE • FAST"),
            AIModelDefinition(id: "sonnet", name: "Claude 3.7 Sonnet (Hybrid)", provider: "claude_code", badge: "HYBRID"),
            AIModelDefinition(id: "opus", name: "Claude 3.5 Opus", provider: "claude_code", badge: "REASONING"),
            AIModelDefinition(id: "auto", name: "Claude Code Auto", provider: "claude_code", badge: "DYNAMIC")
        ]),
        AIProviderDefinition(id: "zed", name: "Zed / ZCode (~/.config/zed)", icon: "chevron.left.forwardslash.chevron.right", endpoint: "local://zed", models: [
            AIModelDefinition(id: "deepseek-v4-flash", name: "DeepSeek V4 Flash (Thinking)", provider: "zed", badge: "ZED DEFAULT"),
            AIModelDefinition(id: "gpt-5.2", name: "GPT-5.2 (Inline)", provider: "zed", badge: "ZED INLINE")
        ]),
        AIProviderDefinition(id: "omni", name: "Dotmini Cloud (All Live Models)", icon: "sparkles", endpoint: "api.dotmini.net/v1", models: [
            AIModelDefinition(id: "gpt-6-astra", name: "GPT-6-Astra (Flagship)", provider: "omni", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gpt-5.6-sol", name: "GPT-5.6-Sol", provider: "omni", badge: "HIGH PERF"),
            AIModelDefinition(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6 (Thinking)", provider: "omni", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gemini-3.8-flash-high", name: "Gemini 3.8 Flash (High)", provider: "omni", badge: "HIGH REASONING"),
            AIModelDefinition(id: "deepseek-v4-flash", name: "DeepSeek V4 Flash", provider: "omni", badge: "FLASH THINK"),
            AIModelDefinition(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", provider: "omni", badge: "PRO"),
            AIModelDefinition(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", provider: "omni", badge: "FAST"),
            AIModelDefinition(id: "o3-mini", name: "OpenAI o3-mini", provider: "omni", badge: "REASONING"),
            AIModelDefinition(id: "o1", name: "OpenAI o1", provider: "omni", badge: "REASONING PRO"),
            AIModelDefinition(id: "claude-3-7-sonnet", name: "Claude 3.7 Sonnet", provider: "omni", badge: "HYBRID"),
            AIModelDefinition(id: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", provider: "omni", badge: "AGENT"),
            AIModelDefinition(id: "deepseek-reasoner", name: "DeepSeek R1 Reasoner", provider: "omni", badge: "REASONER"),
            AIModelDefinition(id: "deepseek-chat", name: "DeepSeek V3 Chat", provider: "omni", badge: "FAST"),
            AIModelDefinition(id: "gpt-4o", name: "OpenAI GPT-4o (Legacy)", provider: "omni", badge: "LEGACY"),
            AIModelDefinition(id: "gpt-4o-mini", name: "OpenAI GPT-4o mini", provider: "omni", badge: "FAST"),
            AIModelDefinition(id: "typhoon-v2-70b-instruct", name: "Typhoon v2 70B (Thai AI)", provider: "omni", badge: "THAI"),
            AIModelDefinition(id: "qwen/qwen-2.5-coder-32b-instruct", name: "Qwen 2.5 Coder 32B", provider: "omni", badge: "CODE"),
            AIModelDefinition(id: "meta-llama/llama-3.3-70b-instruct", name: "Llama 3.3 70B Instruct", provider: "omni", badge: "LLAMA 3.3")
        ]),
        AIProviderDefinition(id: "openai", name: "OpenAI", icon: "brain.head.profile", endpoint: "api.openai.com", models: [
            AIModelDefinition(id: "gpt-6-astra", name: "GPT-6-Astra (Flagship)", provider: "openai", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gpt-5.6-sol", name: "GPT-5.6-Sol (Autonomous)", provider: "openai", badge: "HIGH PERF"),
            AIModelDefinition(id: "gpt-5.5", name: "GPT-5.5 (Frontier)", provider: "openai", badge: "FRONTIER"),
            AIModelDefinition(id: "o3", name: "o3 (Frontier Reasoning)", provider: "openai", badge: "REASONING PRO"),
            AIModelDefinition(id: "o3-mini", name: "o3-mini (Reasoning)", provider: "openai", badge: "REASONING"),
            AIModelDefinition(id: "o1-pro", name: "o1 Pro (Deep Reasoning)", provider: "openai", badge: "PRO"),
            AIModelDefinition(id: "o1", name: "o1 (Reasoning Flagship)", provider: "openai", badge: "REASONING"),
            AIModelDefinition(id: "gpt-4.5-preview", name: "GPT-4.5 Preview", provider: "openai", badge: "CREATIVE"),
            AIModelDefinition(id: "chatgpt-4o-latest", name: "ChatGPT-4o Latest", provider: "openai", badge: "DYNAMIC WEB"),
            AIModelDefinition(id: "gpt-4o", name: "GPT-4o (Legacy Omni)", provider: "openai", badge: "LEGACY"),
            AIModelDefinition(id: "gpt-4o-mini", name: "GPT-4o mini (High Speed)", provider: "openai", badge: "FAST")
        ]),
        AIProviderDefinition(id: "gemini", name: "Google Gemini", icon: "sparkles", endpoint: "generativelanguage.googleapis.com", models: [
            AIModelDefinition(id: "gemini-3.8-flash-high", name: "Gemini 3.8 Flash (High)", provider: "gemini", badge: "HIGH REASONING"),
            AIModelDefinition(id: "gemini-3.7-flash-high", name: "Gemini 3.7 Flash", provider: "gemini", badge: "HIGH SPEED"),
            AIModelDefinition(id: "gemini-3.1-pro-high", name: "Gemini 3.1 Pro", provider: "gemini", badge: "ADVANCED PRO"),
            AIModelDefinition(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", provider: "gemini", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", provider: "gemini", badge: "FAST"),
            AIModelDefinition(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", provider: "gemini", badge: "STABLE")
        ]),
        AIProviderDefinition(id: "anthropic", name: "Anthropic Claude", icon: "bubble.left.and.text.bubble.right", endpoint: "api.anthropic.com", models: [
            AIModelDefinition(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6 (Thinking)", provider: "anthropic", badge: "FLAGSHIP"),
            AIModelDefinition(id: "claude-opus-4-6-thinking", name: "Claude Opus 4.6 (Thinking)", provider: "anthropic", badge: "DEEP THINK"),
            AIModelDefinition(id: "claude-3-7-sonnet", name: "Claude 3.7 Sonnet (Hybrid Thinking)", provider: "anthropic", badge: "HYBRID"),
            AIModelDefinition(id: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", provider: "anthropic", badge: "WORKHORSE"),
            AIModelDefinition(id: "claude-3-5-haiku", name: "Claude 3.5 Haiku", provider: "anthropic", badge: "FAST"),
            AIModelDefinition(id: "claude-3-opus", name: "Claude 3 Opus", provider: "anthropic", badge: "REASONING")
        ]),
        AIProviderDefinition(id: "deepseek", name: "DeepSeek", icon: "water.waves", endpoint: "api.deepseek.com", models: [
            AIModelDefinition(id: "deepseek-v4-flash", name: "DeepSeek V4 Flash (Thinking)", provider: "deepseek", badge: "FLASH THINK"),
            AIModelDefinition(id: "deepseek-v4", name: "DeepSeek V4 (Flagship)", provider: "deepseek", badge: "FLAGSHIP"),
            AIModelDefinition(id: "deepseek-reasoner", name: "DeepSeek R1 Reasoner", provider: "deepseek", badge: "REASONING"),
            AIModelDefinition(id: "deepseek-chat", name: "DeepSeek V3 Chat", provider: "deepseek", badge: "CHAT")
        ]),
        AIProviderDefinition(id: "qwen", name: "Qwen / Alibaba", icon: "cloud.fill", endpoint: "dashscope.aliyuncs.com", models: [
            AIModelDefinition(id: "qwen/qwen-2.5-coder-32b-instruct", name: "Qwen 2.5 Coder 32B", provider: "qwen", badge: "CODE"),
            AIModelDefinition(id: "qwen/qwen-2.5-72b-instruct", name: "Qwen 2.5 72B Instruct", provider: "qwen", badge: "LATEST")
        ]),
        AIProviderDefinition(id: "grok", name: "xAI Grok", icon: "bolt.fill", endpoint: "api.x.ai", models: [
            AIModelDefinition(id: "grok-3", name: "Grok 3", provider: "grok", badge: "LATEST"),
            AIModelDefinition(id: "grok-3-mini", name: "Grok 3 mini", provider: "grok", badge: "FAST"),
            AIModelDefinition(id: "grok-2", name: "Grok 2", provider: "grok")
        ]),
        AIProviderDefinition(id: "glm", name: "Zhipu GLM (BigModel)", icon: "globe.asia.australia", endpoint: "open.bigmodel.cn", models: [
            AIModelDefinition(id: "glm-4-plus", name: "GLM-4 Plus (Flagship)", provider: "glm", badge: "FLAGSHIP"),
            AIModelDefinition(id: "codegeex-4", name: "CodeGeeX-4 (Code Specialist)", provider: "glm", badge: "CODE"),
            AIModelDefinition(id: "glm-4-0520", name: "GLM-4 0520 (Stable Code)", provider: "glm", badge: "CODE"),
            AIModelDefinition(id: "glm-4-air", name: "GLM-4 Air (Ultra-Fast)", provider: "glm", badge: "FAST"),
            AIModelDefinition(id: "glm-4-flash", name: "GLM-4 Flash (High Speed)", provider: "glm", badge: "FAST"),
            AIModelDefinition(id: "glm-4v-plus", name: "GLM-4V Plus (Vision & Code)", provider: "glm", badge: "VISION")
        ])
    ]
}
