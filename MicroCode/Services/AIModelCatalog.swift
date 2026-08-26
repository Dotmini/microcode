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
        if self.provider(provider)?.models.contains(where: { $0.id == model }) == true {
            return (provider, model)
        }
        if let matchedProvider = providers.first(where: { $0.models.contains(where: { $0.id == model }) }) {
            return (matchedProvider.id, model)
        }
        let fallbackProvider = self.provider(provider) ?? providers.first!
        return (fallbackProvider.id, fallbackProvider.models.first?.id ?? "gemini-3.6-flash")
    }

    func refreshIfNeeded(force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < refreshInterval { return }

        isRefreshing = true
        defer { isRefreshing = false }

        let base = StreamableAIProvider.cloudProxyURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/models") else { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        
        let license = UserDefaults.standard.string(forKey: "dotminiLicenseKey") ?? ""
        let token = UserDefaults.standard.string(forKey: "microRentToken") ?? ""
        let authorization = license.isEmpty ? token : license
        if !authorization.isEmpty {
            request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let entries = try Self.decodeRemoteModels(data)
            guard !entries.isEmpty else { return }
            providers = Self.mergeLive(remoteEntries: entries, fallback: Self.fallbackProviders)
            lastUpdated = Date()
            source = "Dotmini Cloud (\(entries.count) models live)"
            saveCachedCatalog()
        } catch {
            // Cached/fallback models remain available
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

    private static func formatModelName(_ id: String) -> String {
        return id
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
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
            AIModelDefinition(id: "stealth/ox-alpha", name: "Ox Alpha (Stealth Ox-Alpha)", provider: "omni", badge: "OX ALPHA"),
            AIModelDefinition(id: "omni-max", name: "Omni Max (High Performance)", provider: "omni", badge: "OMNI MAX"),
            AIModelDefinition(id: "omni-mini", name: "Omni Mini (Fast Low-Latency)", provider: "omni", badge: "OMNI MINI"),
            AIModelDefinition(id: "gemini-omni-flash", name: "Gemini Omni Flash", provider: "omni", badge: "OMNI FLASH"),
            AIModelDefinition(id: "antigravity-preview-05-2026", name: "Antigravity Preview", provider: "omni", badge: "ANTIGRAVITY"),
            AIModelDefinition(id: "deep-research-max-preview-04-2026", name: "Deep Research Max Preview", provider: "omni", badge: "RESEARCH"),
            AIModelDefinition(id: "gemini-3.7-flash", name: "Gemini 3.7 Flash", provider: "omni", badge: "GEMINI 3.7"),
            AIModelDefinition(id: "gemini-3.6-flash", name: "Gemini 3.6 Flash", provider: "omni", badge: "RECOMMENDED"),
            AIModelDefinition(id: "deepseek-v4-flash", name: "DeepSeek V4 Flash", provider: "omni", badge: "V4 FLASH"),
            AIModelDefinition(id: "deepseek-v4-pro", name: "DeepSeek V4 Pro", provider: "omni", badge: "V4 PRO"),
            AIModelDefinition(id: "gpt-5.6-terra", name: "GPT-5.6 Terra", provider: "omni", badge: "TERRA"),
            AIModelDefinition(id: "gpt-5.6-sol", name: "GPT-5.6 Sol", provider: "omni", badge: "SOL"),
            AIModelDefinition(id: "claude-sonnet-5", name: "Claude Sonnet 5", provider: "omni", badge: "CLAUDE 5"),
            AIModelDefinition(id: "claude-opus-5", name: "Claude Opus 5", provider: "omni", badge: "OPUS 5"),
            AIModelDefinition(id: "claude-3-7-sonnet", name: "Claude 3.7 Sonnet", provider: "omni", badge: "HYBRID"),
            AIModelDefinition(id: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", provider: "omni", badge: "AGENT"),
            AIModelDefinition(id: "o3-mini", name: "OpenAI o3-mini", provider: "omni", badge: "REASONER"),
            AIModelDefinition(id: "o4-mini", name: "OpenAI o4-mini", provider: "omni", badge: "O4"),
            AIModelDefinition(id: "grok-3", name: "xAI Grok 3", provider: "omni", badge: "GROK 3"),
            AIModelDefinition(id: "typhoon-v2.5-30b-a3b-instruct", name: "Typhoon v2.5 30B (Thai AI)", provider: "omni", badge: "THAI"),
            AIModelDefinition(id: "typhoon-v2-70b-instruct", name: "Typhoon v2 70B (High Precision Thai)", provider: "omni", badge: "THAI 70B"),
            AIModelDefinition(id: "qwen/qwen-2.5-coder-32b-instruct", name: "Qwen 2.5 Coder 32B", provider: "omni", badge: "CODE"),
            AIModelDefinition(id: "glm-5.2", name: "GLM 5.2", provider: "omni", badge: "GLM 5"),
            AIModelDefinition(id: "medgemma-pro", name: "MedGemma Pro (Medical / STEM)", provider: "omni", badge: "MED/STEM"),
            AIModelDefinition(id: "meta-llama/llama-3.3-70b-instruct", name: "Llama 3.3 70B Instruct", provider: "omni", badge: "LLAMA 3.3")
        ]),
        AIProviderDefinition(id: "anthropic", name: "Anthropic Claude", icon: "bubble.left.and.text.bubble.right", endpoint: "api.anthropic.com", models: [
            AIModelDefinition(id: "claude-opus-5", name: "Claude Opus 5", provider: "anthropic", badge: "OPUS 5"),
            AIModelDefinition(id: "claude-sonnet-5", name: "Claude Sonnet 5", provider: "anthropic", badge: "SONNET 5"),
            AIModelDefinition(id: "claude-3-7-sonnet", name: "Claude 3.7 Sonnet", provider: "anthropic", badge: "LATEST"),
            AIModelDefinition(id: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", provider: "anthropic", badge: "AGENT"),
            AIModelDefinition(id: "claude-3-5-haiku", name: "Claude 3.5 Haiku", provider: "anthropic", badge: "FAST")
        ]),
        AIProviderDefinition(id: "openai", name: "OpenAI", icon: "brain.head.profile", endpoint: "api.openai.com", models: [
            AIModelDefinition(id: "gpt-5.6-terra", name: "GPT-5.6 Terra", provider: "openai", badge: "TERRA"),
            AIModelDefinition(id: "gpt-5.6-sol", name: "GPT-5.6 Sol", provider: "openai", badge: "SOL"),
            AIModelDefinition(id: "o3-mini", name: "o3-mini Reasoning", provider: "openai", badge: "REASONING"),
            AIModelDefinition(id: "o4-mini", name: "o4-mini", provider: "openai", badge: "O4"),
            AIModelDefinition(id: "gpt-4.5-preview", name: "GPT-4.5 Preview", provider: "openai", badge: "PREVIEW"),
            AIModelDefinition(id: "gpt-4o", name: "GPT-4o (Omni)", provider: "openai", badge: "LATEST"),
            AIModelDefinition(id: "gpt-4o-mini", name: "GPT-4o mini", provider: "openai", badge: "FAST")
        ]),
        AIProviderDefinition(id: "gemini", name: "Google Gemini", icon: "sparkles", endpoint: "generativelanguage.googleapis.com", models: [
            AIModelDefinition(id: "gemini-3.7-flash", name: "Gemini 3.7 Flash", provider: "gemini", badge: "LATEST"),
            AIModelDefinition(id: "gemini-3.6-flash", name: "Gemini 3.6 Flash", provider: "gemini", badge: "FAST"),
            AIModelDefinition(id: "gemini-2.0-flash-thinking-exp", name: "Gemini 2.0 Flash Thinking", provider: "gemini", badge: "THINKING"),
            AIModelDefinition(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", provider: "gemini", badge: "FAST")
        ]),
        AIProviderDefinition(id: "deepseek", name: "DeepSeek", icon: "water.waves", endpoint: "api.deepseek.com", models: [
            AIModelDefinition(id: "deepseek-v4-pro", name: "DeepSeek V4 Pro", provider: "deepseek", badge: "V4 PRO"),
            AIModelDefinition(id: "deepseek-v4-flash", name: "DeepSeek V4 Flash", provider: "deepseek", badge: "V4 FLASH"),
            AIModelDefinition(id: "deepseek-reasoner", name: "DeepSeek R1 Reasoner", provider: "deepseek", badge: "REASONING"),
            AIModelDefinition(id: "deepseek-chat", name: "DeepSeek V3 Chat", provider: "deepseek", badge: "FAST")
        ]),
        AIProviderDefinition(id: "qwen", name: "Qwen / Alibaba", icon: "cloud.fill", endpoint: "dashscope.aliyuncs.com", models: [
            AIModelDefinition(id: "qwen/qwen-2.5-coder-32b-instruct", name: "Qwen 2.5 Coder 32B", provider: "qwen", badge: "CODE"),
            AIModelDefinition(id: "qwen/qwen-2.5-72b-instruct", name: "Qwen 2.5 72B Instruct", provider: "qwen", badge: "LATEST"),
            AIModelDefinition(id: "qwen/qwq-32b-preview", name: "QwQ 32B Preview", provider: "qwen", badge: "REASONING")
        ]),
        AIProviderDefinition(id: "grok", name: "xAI Grok", icon: "bolt.fill", endpoint: "api.x.ai", models: [
            AIModelDefinition(id: "grok-3", name: "Grok 3", provider: "grok", badge: "LATEST"),
            AIModelDefinition(id: "grok-3-mini", name: "Grok 3 mini", provider: "grok", badge: "FAST"),
            AIModelDefinition(id: "grok-2", name: "Grok 2", provider: "grok")
        ]),
        AIProviderDefinition(id: "glm", name: "Zhipu GLM", icon: "globe.asia.australia", endpoint: "open.bigmodel.cn", models: [
            AIModelDefinition(id: "glm-5.2", name: "GLM 5.2", provider: "glm", badge: "LATEST"),
            AIModelDefinition(id: "glm-5", name: "GLM 5", provider: "glm", badge: "GLM 5"),
            AIModelDefinition(id: "glm-4.7-flash", name: "GLM 4.7 Flash", provider: "glm", badge: "FAST")
        ])
    ]
}
