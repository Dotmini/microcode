//
//  ACPGhostTextBridge.swift
//  MicroCode
//
//  Ultra-Fast Subscription & BYOK Ghost Text FIM Bridge (<80ms–250ms target).
//  Connects inline editor Ghost Text directly to MicroCode's 3-Tier Unified Subscription Pool:
//  Local LLM → Cerebras Wafer-Scale → Groq LPU → GitHub Copilot → Codestral → AiPass/TokenMe/Gemini → DeepSeek → OpenAI.
//

import Foundation

// MARK: - Cloud FIM Provider Protocol

/// Protocol for cloud-based Fill-In-the-Middle completion providers
@MainActor
protocol CloudFIMProvider {
    var name: String { get }
    var isEnabled: Bool { get }
    var latencyBudgetMs: Int { get }
    
    /// Perform a FIM completion request
    func complete(
        prefix: String,
        suffix: String,
        language: String,
        filePath: String
    ) async throws -> String?
}

// MARK: - Shared FIM Prompt & Cleanup Helper

enum GhostTextFIMHelper {
    static func buildChatFIMMessages(
        prefix: String,
        suffix: String,
        language: String,
        filePath: String
    ) -> [[String: String]] {
        let pre = String(prefix.suffix(1800))
        let suf = String(suffix.prefix(700))
        return [
            [
                "role": "system",
                "content": "You are an ultra-low-latency Fill-In-The-Middle (FIM) code completion engine inside MicroCode IDE. Output ONLY the exact code to insert at `<CURSOR>`. Never repeat code before `<CURSOR>` or after `<CURSOR>`. Never wrap in markdown backticks or add explanations."
            ],
            [
                "role": "user",
                "content": "File: \(filePath) (\(language))\n\(pre)<CURSOR>\(suf)"
            ]
        ]
    }

    static func cleanFIMOutput(_ raw: String) -> String? {
        var text = raw
        if text.hasPrefix("```") {
            if let nl = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: nl)...])
            } else {
                text = text.replacingOccurrences(of: "```", with: "")
            }
            if let closing = text.range(of: "```", options: .backwards) {
                text = String(text[..<closing.lowerBound])
            }
        }
        text = text.replacingOccurrences(of: "<CURSOR>", with: "")
        // Trim trailing newlines/whitespace only (preserve meaningful leading space after tokens)
        while text.last?.isNewline == true {
            text.removeLast()
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    static func executeOpenAIChatFIM(
        endpoint: String,
        apiKey: String,
        model: String,
        extraHeaders: [String: String] = [:],
        timeoutMs: Int,
        prefix: String,
        suffix: String,
        language: String,
        filePath: String
    ) async throws -> String? {
        guard let url = URL(string: endpoint) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for (k, v) in extraHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.timeoutInterval = max(0.35, TimeInterval(timeoutMs) / 1000.0)

        let body: [String: Any] = [
            "model": model,
            "messages": buildChatFIMMessages(prefix: prefix, suffix: suffix, language: language, filePath: filePath),
            "max_tokens": 96,
            "temperature": 0.0,
            "stream": false,
            "stop": ["\n\n\n", "<CURSOR>", "```"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            return nil
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let msg = choices.first?["message"] as? [String: Any],
           let content = msg["content"] as? String {
            return cleanFIMOutput(content)
        }
        return nil
    }
}

// MARK: - Ghost Text Bridge

/// Bridges multiple Subscription & BYOK FIM providers with AIAutocompleteService.
@MainActor
class ACPGhostTextBridge: ObservableObject {
    static let shared = ACPGhostTextBridge()
    
    @Published var activeProvider: String = "local"
    @Published var lastLatencyMs: Int = 0
    @Published var isEnabled = true
    
    /// Maximum latency budget per provider attempt (keeps TLS + fast LPU/Flash completions snappy)
    private let maxLatencyMs = 650
    
    /// Context window: lines before/after cursor to include
    private let prefixLineCount = 250
    private let suffixLineCount = 100
    
    /// Registered cloud & subscription FIM providers in speed priority order
    private var providers: [CloudFIMProvider] = []
    
    init() {
        providers = [
            CerebrasSubscriptionFIMProvider(),
            GroqSubscriptionFIMProvider(),
            CopilotSubscriptionFIMProvider(),
            MistralCodestralFIMProvider(),
            GeminiAndAiPassFIMProvider(),
            DeepSeekFIMProvider(),
            OpenAIFIMProvider(),
            CustomFIMProvider()
        ]
    }
    
    /// Register a custom FIM provider
    func addProvider(_ provider: CloudFIMProvider) {
        providers.append(provider)
    }
    
    // MARK: - Completion Pipeline
    
    /// Get ghost text completion using the fallback chain:
    /// Cerebras → Groq → GitHub Copilot → Codestral → AiPass/TokenMe/Gemini → DeepSeek → OpenAI
    func getCompletion(
        prefix: String,
        suffix: String,
        language: String,
        filePath: String
    ) async -> String? {
        guard isEnabled else { return nil }
        
        let start = CFAbsoluteTimeGetCurrent()
        let trimmedPrefix = trimPrefix(prefix)
        let trimmedSuffix = trimSuffix(suffix)
        
        for provider in providers where provider.isEnabled {
            if Task.isCancelled { return nil }
            let budgetMs = min(maxLatencyMs, max(250, provider.latencyBudgetMs))
            do {
                let result = try await withThrowingTaskGroup(of: String?.self) { group in
                    group.addTask { @MainActor in
                        try await provider.complete(
                            prefix: trimmedPrefix,
                            suffix: trimmedSuffix,
                            language: language,
                            filePath: filePath
                        )
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(budgetMs) * 1_000_000)
                        return nil
                    }
                    if let first = try await group.next() {
                        group.cancelAll()
                        return first
                    }
                    return nil
                }
                
                if let completion = result, !completion.isEmpty {
                    let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                    self.lastLatencyMs = elapsed
                    self.activeProvider = provider.name
                    return completion
                }
            } catch {
                continue
            }
        }
        
        return nil
    }
    
    // MARK: - Context Trimming
    
    private func trimPrefix(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        if lines.count > prefixLineCount {
            return lines.suffix(prefixLineCount).joined(separator: "\n")
        }
        return text
    }
    
    private func trimSuffix(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        if lines.count > suffixLineCount {
            return lines.prefix(suffixLineCount).joined(separator: "\n")
        }
        return text
    }
}

// MARK: - 1. Cerebras Wafer-Scale FIM (~60-110ms, 2,000+ tok/s)

struct CerebrasSubscriptionFIMProvider: CloudFIMProvider {
    let name = "Cerebras Wafer-Scale"
    let latencyBudgetMs = 380

    private var resolvedKey: String {
        if let sub = SubscriptionAuthManager.shared.token(for: .cerebras), !sub.isEmpty { return sub }
        let byok = AIModelCatalog.resolveKey("cerebras")
        if !byok.isEmpty { return byok }
        return ProcessInfo.processInfo.environment["CEREBRAS_API_KEY"] ?? ""
    }

    var isEnabled: Bool { !resolvedKey.isEmpty }

    func complete(prefix: String, suffix: String, language: String, filePath: String) async throws -> String? {
        let key = resolvedKey
        guard !key.isEmpty else { return nil }
        return try await GhostTextFIMHelper.executeOpenAIChatFIM(
            endpoint: "https://api.cerebras.ai/v1/chat/completions",
            apiKey: key,
            model: "llama-3.3-70b",
            timeoutMs: latencyBudgetMs,
            prefix: prefix,
            suffix: suffix,
            language: language,
            filePath: filePath
        )
    }
}

// MARK: - 2. Groq LPU Ultra-Low-Latency FIM (~80-140ms)

struct GroqSubscriptionFIMProvider: CloudFIMProvider {
    let name = "Groq LPU"
    let latencyBudgetMs = 420

    private var resolvedKey: String {
        if let sub = SubscriptionAuthManager.shared.token(for: .groq), !sub.isEmpty { return sub }
        let byok = AIModelCatalog.resolveKey("groq")
        if !byok.isEmpty { return byok }
        return ProcessInfo.processInfo.environment["GROQ_API_KEY"] ?? ""
    }

    var isEnabled: Bool { !resolvedKey.isEmpty }

    func complete(prefix: String, suffix: String, language: String, filePath: String) async throws -> String? {
        let key = resolvedKey
        guard !key.isEmpty else { return nil }
        return try await GhostTextFIMHelper.executeOpenAIChatFIM(
            endpoint: "https://api.groq.com/openai/v1/chat/completions",
            apiKey: key,
            model: "llama-3.3-70b-versatile",
            timeoutMs: latencyBudgetMs,
            prefix: prefix,
            suffix: suffix,
            language: language,
            filePath: filePath
        )
    }
}

// MARK: - 3. GitHub Copilot Subscription FIM (Zero API Charge)

struct CopilotSubscriptionFIMProvider: CloudFIMProvider {
    let name = "GitHub Copilot"
    let latencyBudgetMs = 500

    private var githubToken: String {
        SubscriptionAuthManager.shared.token(for: .copilot) ?? ""
    }

    var isEnabled: Bool { !githubToken.isEmpty }

    func complete(prefix: String, suffix: String, language: String, filePath: String) async throws -> String? {
        let ghToken = githubToken
        guard !ghToken.isEmpty else { return nil }
        let sessionToken = try await SubscriptionAuthManager.shared.getCopilotSessionToken(githubToken: ghToken)
        return try await GhostTextFIMHelper.executeOpenAIChatFIM(
            endpoint: "https://api.githubcopilot.com/chat/completions",
            apiKey: sessionToken,
            model: "gpt-4o-mini",
            extraHeaders: [
                "Copilot-Integration-Id": "vscode-chat",
                "Editor-Version": "vscode/1.99.0"
            ],
            timeoutMs: latencyBudgetMs,
            prefix: prefix,
            suffix: suffix,
            language: language,
            filePath: filePath
        )
    }
}

// MARK: - 4. Mistral Codestral Native FIM

struct MistralCodestralFIMProvider: CloudFIMProvider {
    let name = "Mistral Codestral"
    let latencyBudgetMs = 500

    private var resolvedKey: String {
        if let sub = SubscriptionAuthManager.shared.token(for: .mistral), !sub.isEmpty { return sub }
        let byok = AIModelCatalog.resolveKey("mistral")
        if !byok.isEmpty { return byok }
        return ProcessInfo.processInfo.environment["MISTRAL_API_KEY"] ?? ""
    }

    var isEnabled: Bool { !resolvedKey.isEmpty }

    func complete(prefix: String, suffix: String, language: String, filePath: String) async throws -> String? {
        let key = resolvedKey
        guard !key.isEmpty else { return nil }
        let url = URL(string: "https://api.mistral.ai/v1/fim/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = TimeInterval(latencyBudgetMs) / 1000.0

        let body: [String: Any] = [
            "model": "codestral-latest",
            "prompt": String(prefix.suffix(2000)),
            "suffix": String(suffix.prefix(800)),
            "max_tokens": 96,
            "temperature": 0.0,
            "stop": ["\n\n\n"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let msg = choices.first?["message"] as? [String: Any],
           let content = msg["content"] as? String {
            return GhostTextFIMHelper.cleanFIMOutput(content)
        }
        return nil
    }
}

// MARK: - 5. TH-AI Passport / TokenMe / Gemini Flash FIM

struct GeminiAndAiPassFIMProvider: CloudFIMProvider {
    let name = "Gemini Flash"
    let latencyBudgetMs = 550

    private var aipassKey: String {
        SubscriptionAuthManager.shared.token(for: .aipass) ?? UserDefaults.standard.string(forKey: "aipass_api_key") ?? ""
    }

    private var tokenmeKey: String {
        SubscriptionAuthManager.shared.token(for: .tokenme) ?? UserDefaults.standard.string(forKey: "tokenme_api_key") ?? ""
    }

    private var geminiDirectKey: String {
        let byok = AIModelCatalog.resolveKey("gemini")
        if !byok.isEmpty { return byok }
        if let sub = SubscriptionAuthManager.shared.token(for: .gemini), sub.hasPrefix("AIza") { return sub }
        return ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
    }

    var isEnabled: Bool {
        !aipassKey.isEmpty || !tokenmeKey.isEmpty || !geminiDirectKey.isEmpty
    }

    func complete(prefix: String, suffix: String, language: String, filePath: String) async throws -> String? {
        if !aipassKey.isEmpty {
            if let out = try? await GhostTextFIMHelper.executeOpenAIChatFIM(
                endpoint: "https://api.aipass.in.th/v1/chat/completions",
                apiKey: aipassKey,
                model: "gemini-2.5-flash",
                timeoutMs: latencyBudgetMs,
                prefix: prefix,
                suffix: suffix,
                language: language,
                filePath: filePath
            ), !out.isEmpty {
                return out
            }
        }
        if !tokenmeKey.isEmpty {
            if let out = try? await GhostTextFIMHelper.executeOpenAIChatFIM(
                endpoint: "https://api.tokenme.net/v1/chat/completions",
                apiKey: tokenmeKey,
                model: "gemini-2.5-flash",
                timeoutMs: latencyBudgetMs,
                prefix: prefix,
                suffix: suffix,
                language: language,
                filePath: filePath
            ), !out.isEmpty {
                return out
            }
        }
        let apiKey = geminiDirectKey
        guard !apiKey.isEmpty else { return nil }
        let model = "gemini-2.5-flash"
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = TimeInterval(latencyBudgetMs) / 1000.0

        let prompt = """
        Complete ONLY the missing code at <CURSOR>. Output raw code only, no markdown fences, no explanation.
        File: \(filePath) (\(language))
        \(String(prefix.suffix(1800)))<CURSOR>\(String(suffix.prefix(700)))
        """
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "maxOutputTokens": 96,
                "temperature": 0.0
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let candidates = json["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let text = parts.first?["text"] as? String {
            return GhostTextFIMHelper.cleanFIMOutput(text)
        }
        return nil
    }
}

// MARK: - 6. DeepSeek Native Beta FIM Provider

struct DeepSeekFIMProvider: CloudFIMProvider {
    let name = "DeepSeek FIM"
    let latencyBudgetMs = 600

    private var resolvedKey: String {
        if let sub = SubscriptionAuthManager.shared.token(for: .deepseek), !sub.isEmpty { return sub }
        let byok = AIModelCatalog.resolveKey("deepseek")
        if !byok.isEmpty { return byok }
        return ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? ""
    }

    var isEnabled: Bool { !resolvedKey.isEmpty }

    func complete(prefix: String, suffix: String, language: String, filePath: String) async throws -> String? {
        let apiKey = resolvedKey
        guard !apiKey.isEmpty else { return nil }
        let url = URL(string: "https://api.deepseek.com/beta/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = TimeInterval(latencyBudgetMs) / 1000.0

        let body: [String: Any] = [
            "model": "deepseek-chat",
            "prompt": String(prefix.suffix(2000)),
            "suffix": String(suffix.prefix(800)),
            "max_tokens": 96,
            "temperature": 0.0,
            "stop": ["\n\n\n"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let text = choices.first?["text"] as? String {
            return GhostTextFIMHelper.cleanFIMOutput(text)
        }
        return nil
    }
}

// MARK: - 7. OpenAI / OpenRouter FIM Provider

struct OpenAIFIMProvider: CloudFIMProvider {
    let name = "OpenAI Fast FIM"
    let latencyBudgetMs = 550

    private var openAIKey: String {
        let byok = AIModelCatalog.resolveKey("openai")
        if !byok.isEmpty { return byok }
        if let sub = SubscriptionAuthManager.shared.token(for: .chatgpt), sub.hasPrefix("sk-") { return sub }
        return ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    }

    private var openRouterKey: String {
        if let sub = SubscriptionAuthManager.shared.token(for: .openrouter), !sub.isEmpty { return sub }
        return AIModelCatalog.resolveKey("openrouter")
    }

    var isEnabled: Bool { !openAIKey.isEmpty || !openRouterKey.isEmpty }

    func complete(prefix: String, suffix: String, language: String, filePath: String) async throws -> String? {
        if !openAIKey.isEmpty {
            return try await GhostTextFIMHelper.executeOpenAIChatFIM(
                endpoint: "https://api.openai.com/v1/chat/completions",
                apiKey: openAIKey,
                model: "gpt-4o-mini",
                timeoutMs: latencyBudgetMs,
                prefix: prefix,
                suffix: suffix,
                language: language,
                filePath: filePath
            )
        }
        guard !openRouterKey.isEmpty else { return nil }
        return try await GhostTextFIMHelper.executeOpenAIChatFIM(
            endpoint: "https://openrouter.ai/api/v1/chat/completions",
            apiKey: openRouterKey,
            model: "google/gemini-2.5-flash",
            timeoutMs: latencyBudgetMs,
            prefix: prefix,
            suffix: suffix,
            language: language,
            filePath: filePath
        )
    }
}

// MARK: - 8. Custom FIM Provider

struct CustomFIMProvider: CloudFIMProvider {
    let name = "Custom Endpoint"
    var isEnabled: Bool {
        ProcessInfo.processInfo.environment["CUSTOM_FIM_URL"] != nil
    }
    let latencyBudgetMs = 400
    
    func complete(prefix: String, suffix: String, language: String, filePath: String) async throws -> String? {
        guard let baseURL = ProcessInfo.processInfo.environment["CUSTOM_FIM_URL"] else { return nil }
        let apiKey = ProcessInfo.processInfo.environment["CUSTOM_FIM_KEY"] ?? ""
        let model = ProcessInfo.processInfo.environment["CUSTOM_FIM_MODEL"] ?? "default"
        
        guard let url = URL(string: "\(baseURL)/v1/completions") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = TimeInterval(latencyBudgetMs) / 1000.0
        
        let body: [String: Any] = [
            "model": model,
            "prompt": prefix,
            "suffix": suffix,
            "max_tokens": 96,
            "temperature": 0.0
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let text = firstChoice["text"] as? String {
            return GhostTextFIMHelper.cleanFIMOutput(text)
        }
        return nil
    }
}
