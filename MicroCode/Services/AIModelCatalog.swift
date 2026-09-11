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

    private let cacheKey = "microcode.aiModelCatalog.v5"
    private let refreshDateKey = "microcode.aiModelCatalogRefreshDate.v5"
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
        var targetModel = model
        let lower = model.lowercased()
        if lower == "deepseek-v4" || lower == "deepseek-chat-v4" || lower == "deepseek" || lower == "deepseek-v4-flash" || lower == "deepseek-flash" || lower == "deepseek flash" {
            targetModel = "deepseek-chat"
        } else if lower == "deepseek-v4-pro" || lower == "deepseek-r1" || lower == "deepseek reasoner" {
            targetModel = "deepseek-reasoner"
        } else if lower == "gemini-flash" || lower == "gemini" || lower == "gemini-3.7-flash" || lower == "gemini-3.6-flash" {
            targetModel = "gemini-2.5-flash"
        } else if lower == "gemini-pro" || lower == "gemini-3.7-pro" {
            targetModel = "gemini-2.5-pro"
        }
        
        if self.provider(provider)?.models.contains(where: { $0.id == targetModel }) == true {
            return (provider, targetModel)
        }
        if let matchedProvider = providers.first(where: { $0.models.contains(where: { $0.id == targetModel }) }) {
            return (matchedProvider.id, targetModel)
        }
        let fallbackProvider = self.provider(provider) ?? providers.first!
        return (fallbackProvider.id, fallbackProvider.models.first?.id ?? "gemini-2.5-flash")
    }

    func refreshIfNeeded(force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < refreshInterval { return }

        isRefreshing = true
        defer { isRefreshing = false }

        await refreshLiveProviderModels()
    }

    /// Dynamically fetches models directly from active provider APIs (OpenAI, Gemini, Anthropic, DeepSeek)
    /// ensuring users ALWAYS get the latest, real, unmocked models that update daily.
    public func refreshLiveProviderModels() async {
        await refreshCloudProxyModels()
        await fetchLiveOpenAIModels()
        await fetchLiveGeminiModels()
        await fetchLiveAnthropicModels()
        await fetchLiveDeepSeekModels()
        lastUpdated = Date()
        saveCachedCatalog()
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
            guard lower.hasPrefix("gpt-4o") || lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("gpt-4.5") || lower.hasPrefix("chatgpt-4o") else { continue }
            guard !lower.contains("transcribe") && !lower.contains("audio") && !lower.contains("realtime") && !lower.contains("tts") && !lower.contains("search") && !lower.contains("embedding") && !lower.hasPrefix("ft:") else { continue }
            
            let badge = (lower.contains("o3") || lower.contains("o1")) ? "REASONING" : "LATEST"
            liveModels.append(AIModelDefinition(id: mid, name: Self.formatModelName(mid), provider: "openai", badge: badge))
        }
        
        liveModels.sort { a, b in
            let rank: (String) -> Int = { id in
                if id == "o3-mini" { return 100 }
                if id == "o1" { return 95 }
                if id == "o1-pro" { return 90 }
                if id == "gpt-4o" { return 85 }
                if id == "gpt-4o-mini" { return 80 }
                if id.hasPrefix("o3") { return 75 }
                if id.hasPrefix("o1") { return 70 }
                if id.hasPrefix("gpt-4.5") { return 65 }
                if id.hasPrefix("gpt-4o") { return 60 }
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
            
            let badge = (lower.contains("2.5") || lower.contains("3.")) ? "LATEST" : "FAST"
            liveModels.append(AIModelDefinition(id: mid, name: Self.formatModelName(mid), provider: "gemini", badge: badge))
        }
        
        liveModels.sort { a, b in
            let rank: (String) -> Int = { id in
                if id == "gemini-2.5-pro" { return 100 }
                if id == "gemini-2.5-flash" { return 95 }
                if id == "gemini-2.0-flash" { return 90 }
                if id == "gemini-1.5-pro" { return 80 }
                if id == "gemini-1.5-flash" { return 75 }
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
        if clean == "gemini-2.5-flash" || clean == "gemini-3.7-flash" || clean == "gemini-3.6-flash" { return "Gemini 2.5 Flash" }
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
        AIProviderDefinition(id: "omni", name: "Dotmini Cloud (All Live Models)", icon: "sparkles", endpoint: "api.dotmini.net/v1", models: [
            AIModelDefinition(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", provider: "omni", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", provider: "omni", badge: "FAST"),
            AIModelDefinition(id: "o3-mini", name: "OpenAI o3-mini", provider: "omni", badge: "REASONING"),
            AIModelDefinition(id: "o1", name: "OpenAI o1", provider: "omni", badge: "REASONING PRO"),
            AIModelDefinition(id: "gpt-4o", name: "OpenAI GPT-4o", provider: "omni", badge: "OMNI"),
            AIModelDefinition(id: "gpt-4o-mini", name: "OpenAI GPT-4o mini", provider: "omni", badge: "FAST"),
            AIModelDefinition(id: "claude-3-7-sonnet", name: "Claude 3.7 Sonnet", provider: "omni", badge: "HYBRID"),
            AIModelDefinition(id: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", provider: "omni", badge: "AGENT"),
            AIModelDefinition(id: "deepseek-reasoner", name: "DeepSeek R1 Reasoner", provider: "omni", badge: "REASONER"),
            AIModelDefinition(id: "deepseek-chat", name: "DeepSeek V3 Chat", provider: "omni", badge: "FAST"),
            AIModelDefinition(id: "typhoon-v2-70b-instruct", name: "Typhoon v2 70B (Thai AI)", provider: "omni", badge: "THAI"),
            AIModelDefinition(id: "qwen/qwen-2.5-coder-32b-instruct", name: "Qwen 2.5 Coder 32B", provider: "omni", badge: "CODE"),
            AIModelDefinition(id: "meta-llama/llama-3.3-70b-instruct", name: "Llama 3.3 70B Instruct", provider: "omni", badge: "LLAMA 3.3")
        ]),
        AIProviderDefinition(id: "openai", name: "OpenAI", icon: "brain.head.profile", endpoint: "api.openai.com", models: [
            AIModelDefinition(id: "o3-mini", name: "o3-mini (Reasoning)", provider: "openai", badge: "REASONING"),
            AIModelDefinition(id: "o1-pro", name: "o1 Pro (Deep Reasoning)", provider: "openai", badge: "PRO"),
            AIModelDefinition(id: "o1", name: "o1 (Reasoning Flagship)", provider: "openai", badge: "REASONING"),
            AIModelDefinition(id: "gpt-4o", name: "GPT-4o (Omni Flagship)", provider: "openai", badge: "LATEST"),
            AIModelDefinition(id: "gpt-4o-mini", name: "GPT-4o mini (High Speed)", provider: "openai", badge: "FAST"),
            AIModelDefinition(id: "gpt-4.5-preview", name: "GPT-4.5 Preview", provider: "openai", badge: "PREVIEW"),
            AIModelDefinition(id: "chatgpt-4o-latest", name: "ChatGPT-4o Latest", provider: "openai", badge: "WEB")
        ]),
        AIProviderDefinition(id: "gemini", name: "Google Gemini", icon: "sparkles", endpoint: "generativelanguage.googleapis.com", models: [
            AIModelDefinition(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", provider: "gemini", badge: "FAST"),
            AIModelDefinition(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", provider: "gemini", badge: "FLAGSHIP"),
            AIModelDefinition(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", provider: "gemini", badge: "STABLE"),
            AIModelDefinition(id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", provider: "gemini", badge: "2M CONTEXT")
        ]),
        AIProviderDefinition(id: "anthropic", name: "Anthropic Claude", icon: "bubble.left.and.text.bubble.right", endpoint: "api.anthropic.com", models: [
            AIModelDefinition(id: "claude-3-7-sonnet", name: "Claude 3.7 Sonnet (Hybrid Thinking)", provider: "anthropic", badge: "HYBRID"),
            AIModelDefinition(id: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", provider: "anthropic", badge: "AGENT"),
            AIModelDefinition(id: "claude-3-5-haiku", name: "Claude 3.5 Haiku", provider: "anthropic", badge: "FAST"),
            AIModelDefinition(id: "claude-3-opus", name: "Claude 3 Opus", provider: "anthropic", badge: "REASONING")
        ]),
        AIProviderDefinition(id: "deepseek", name: "DeepSeek", icon: "water.waves", endpoint: "api.deepseek.com", models: [
            AIModelDefinition(id: "deepseek-chat", name: "DeepSeek V3 Chat", provider: "deepseek", badge: "CHAT"),
            AIModelDefinition(id: "deepseek-reasoner", name: "DeepSeek R1 Reasoner", provider: "deepseek", badge: "REASONING")
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
        AIProviderDefinition(id: "glm", name: "Zhipu GLM", icon: "globe.asia.australia", endpoint: "open.bigmodel.cn", models: [
            AIModelDefinition(id: "glm-4-plus", name: "GLM-4 Plus", provider: "glm", badge: "FLAGSHIP"),
            AIModelDefinition(id: "glm-4-flash", name: "GLM-4 Flash", provider: "glm", badge: "FAST")
        ])
    ]
}
