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

    private let cacheKey = "microcode.aiModelCatalog.v2"
    private let refreshDateKey = "microcode.aiModelCatalogRefreshDate.v2"
    private let refreshInterval: TimeInterval = 6 * 60 * 60

    private init() {
        providers = Self.fallbackProviders
        loadCachedCatalog()
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

        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "cloud"
        guard keyMode == "cloud" else { return }
        let license = UserDefaults.standard.string(forKey: "dotminiLicenseKey") ?? ""
        let token = UserDefaults.standard.string(forKey: "microRentToken") ?? ""
        let authorization = license.isEmpty ? token : license
        guard !authorization.isEmpty else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        let base = StreamableAIProvider.cloudProxyURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/models") else { return }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let ids = try Self.decodeModelIDs(data)
            guard !ids.isEmpty else { return }
            providers = Self.merge(remoteIDs: ids, fallback: Self.fallbackProviders)
            lastUpdated = Date()
            source = "Dotmini Cloud"
            saveCachedCatalog()
        } catch {
            // Cached/fallback models remain available; refresh failures must not
            // block opening Settings or sending a prompt.
        }
    }

    private static func decodeModelIDs(_ data: Data) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: data)
        if let dictionary = object as? [String: Any], let rows = dictionary["data"] as? [[String: Any]] {
            return rows.compactMap { $0["id"] as? String }
        }
        if let dictionary = object as? [String: Any], let rows = dictionary["models"] as? [[String: Any]] {
            return rows.compactMap { ($0["id"] as? String) ?? ($0["name"] as? String) }
        }
        if let rows = object as? [[String: Any]] {
            return rows.compactMap { ($0["id"] as? String) ?? ($0["name"] as? String) }
        }
        return []
    }

    private static func merge(remoteIDs: [String], fallback: [AIProviderDefinition]) -> [AIProviderDefinition] {
        var result = fallback.map {
            AIProviderDefinition(id: $0.id, name: $0.name, icon: $0.icon, endpoint: $0.endpoint, models: [])
        }
        let known = Dictionary(uniqueKeysWithValues: fallback.flatMap(\.models).map { ($0.id, $0) })
        for rawID in Set(remoteIDs) {
            let id = rawID.replacingOccurrences(of: "models/", with: "")
            guard isChatModel(id), let providerID = inferProvider(id) else { continue }
            let model = known[id] ?? AIModelDefinition(id: id, provider: providerID, badge: "CLOUD")
            guard let providerIndex = result.firstIndex(where: { $0.id == providerID }) else { continue }
            result[providerIndex].models.append(model)
        }
        for index in result.indices {
            if result[index].models.isEmpty,
               let offlineModels = fallback.first(where: { $0.id == result[index].id })?.models {
                result[index].models = offlineModels
            }
            let remote = Set(remoteIDs.map { $0.replacingOccurrences(of: "models/", with: "") })
            result[index].models.sort {
                let lhsRemote = remote.contains($0.id)
                let rhsRemote = remote.contains($1.id)
                return lhsRemote == rhsRemote ? $0.id > $1.id : lhsRemote
            }
        }
        return result
    }

    private static func inferProvider(_ model: String) -> String? {
        let value = model.lowercased()
        if value.contains("gemini") || value.contains("gemma") { return "gemini" }
        if value.contains("claude") { return "anthropic" }
        if value.contains("deepseek") { return "deepseek" }
        if value.contains("grok") { return "grok" }
        if value.contains("qwen") { return "qwen" }
        if value.contains("glm") { return "glm" }
        if value.contains("gpt") || value.contains("codex") || value.range(of: #"^o[1-9]"#, options: .regularExpression) != nil { return "openai" }
        return nil
    }

    private static func isChatModel(_ id: String) -> Bool {
        let excluded = ["embedding", "image", "audio", "tts", "transcribe", "moderation", "realtime", "whisper", "dall-e", "veo", "imagen", "sora"]
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
        AIProviderDefinition(id: "gemini", name: "Google Gemini", icon: "sparkles", endpoint: "generativelanguage.googleapis.com", models: [
            AIModelDefinition(id: "gemini-3.6-flash", name: "Gemini 3.6 Flash", provider: "gemini", badge: "LATEST"),
            AIModelDefinition(id: "gemini-3.5-flash", name: "Gemini 3.5 Flash", provider: "gemini", badge: "AGENT"),
            AIModelDefinition(id: "gemini-3.5-flash-lite", name: "Gemini 3.5 Flash-Lite", provider: "gemini", badge: "FAST"),
            AIModelDefinition(id: "gemini-3.1-pro-preview", name: "Gemini 3.1 Pro Preview", provider: "gemini", badge: "PREVIEW"),
            AIModelDefinition(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", provider: "gemini")
        ]),
        AIProviderDefinition(id: "openai", name: "OpenAI", icon: "brain.head.profile", endpoint: "api.openai.com", models: [
            AIModelDefinition(id: "gpt-5.1-codex", name: "GPT-5.1 Codex", provider: "openai", badge: "AGENT"),
            AIModelDefinition(id: "gpt-5.1", name: "GPT-5.1", provider: "openai", badge: "LATEST"),
            AIModelDefinition(id: "gpt-5-mini", name: "GPT-5 mini", provider: "openai", badge: "FAST"),
            AIModelDefinition(id: "gpt-4.1", name: "GPT-4.1", provider: "openai")
        ]),
        AIProviderDefinition(id: "anthropic", name: "Anthropic Claude", icon: "bubble.left.and.text.bubble.right", endpoint: "api.anthropic.com", models: [
            AIModelDefinition(id: "claude-opus-5", name: "Claude Opus 5", provider: "anthropic", badge: "AGENT"),
            AIModelDefinition(id: "claude-sonnet-5", name: "Claude Sonnet 5", provider: "anthropic", badge: "FAST"),
            AIModelDefinition(id: "claude-fable-5", name: "Claude Fable 5", provider: "anthropic", badge: "LONG"),
            AIModelDefinition(id: "claude-haiku-4-5", name: "Claude Haiku 4.5", provider: "anthropic", badge: "FAST")
        ]),
        AIProviderDefinition(id: "deepseek", name: "DeepSeek", icon: "water.waves", endpoint: "api.deepseek.com", models: [
            AIModelDefinition(id: "deepseek-v4-pro", name: "DeepSeek V4 Pro", provider: "deepseek", badge: "AGENT"),
            AIModelDefinition(id: "deepseek-v4-flash", name: "DeepSeek V4 Flash", provider: "deepseek", badge: "FAST")
        ]),
        AIProviderDefinition(id: "grok", name: "xAI Grok", icon: "bolt.fill", endpoint: "api.x.ai", models: [
            AIModelDefinition(id: "grok-4.5", name: "Grok 4.5", provider: "grok", badge: "LATEST")
        ]),
        AIProviderDefinition(id: "qwen", name: "Qwen", icon: "cloud.fill", endpoint: "dashscope.aliyuncs.com", models: [
            AIModelDefinition(id: "qwen3.7-plus", name: "Qwen 3.7 Plus", provider: "qwen", badge: "AGENT"),
            AIModelDefinition(id: "qwen3.7-max", name: "Qwen 3.7 Max", provider: "qwen", badge: "LATEST")
        ]),
        AIProviderDefinition(id: "glm", name: "GLM", icon: "globe.asia.australia", endpoint: "open.bigmodel.cn", models: [
            AIModelDefinition(id: "glm-5", name: "GLM 5", provider: "glm", badge: "LATEST"),
            AIModelDefinition(id: "glm-4.7", name: "GLM 4.7", provider: "glm")
        ])
    ]
}
