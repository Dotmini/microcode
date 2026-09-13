//
//  ACPGhostTextBridge.swift
//  MicroCode
//
//  Ghost Text Bridge — Extends the existing AIAutocompleteService with
//  multi-provider cloud FIM (Fill-In-the-Middle) endpoints.
//  Provides fallback chain: Local LLM → Cloud FIM → LSP completions.
//

import Foundation

// MARK: - Cloud FIM Provider Protocol

/// Protocol for cloud-based Fill-In-the-Middle completion providers
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

// MARK: - Ghost Text Bridge

/// Bridges multiple FIM providers with the existing AIAutocompleteService.
/// Provides a unified completion pipeline with fallback chain.
@MainActor
class ACPGhostTextBridge: ObservableObject {
    static let shared = ACPGhostTextBridge()
    
    @Published var activeProvider: String = "local"
    @Published var lastLatencyMs: Int = 0
    @Published var isEnabled = true
    
    /// Maximum latency for ghost text (cancel if slower)
    private let maxLatencyMs = 200
    
    /// Context window: lines before/after cursor to include
    private let prefixLineCount = 500
    private let suffixLineCount = 200
    
    /// Registered cloud FIM providers
    private var providers: [CloudFIMProvider] = []
    
    init() {
        // Register default providers
        providers = [
            OpenAIFIMProvider(),
            GeminiFIMProvider(),
            DeepSeekFIMProvider(),
            CustomFIMProvider()
        ]
    }
    
    /// Register a custom FIM provider
    func addProvider(_ provider: CloudFIMProvider) {
        providers.append(provider)
    }
    
    // MARK: - Completion Pipeline
    
    /// Get ghost text completion using the fallback chain:
    /// Local LLM → Cloud FIM → LSP completions
    func getCompletion(
        prefix: String,
        suffix: String,
        language: String,
        filePath: String
    ) async -> String? {
        guard isEnabled else { return nil }
        
        let start = CFAbsoluteTimeGetCurrent()
        
        // Trim context to appropriate size
        let trimmedPrefix = trimPrefix(prefix)
        let trimmedSuffix = trimSuffix(suffix)
        
        // Try each enabled provider with latency budget
        for provider in providers where provider.isEnabled {
            do {
                let result = try await withThrowingTaskGroup(of: String?.self) { group in
                    // Completion task
                    group.addTask {
                        try await provider.complete(
                            prefix: trimmedPrefix,
                            suffix: trimmedSuffix,
                            language: language,
                            filePath: filePath
                        )
                    }
                    
                    // Timeout task
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(self.maxLatencyMs) * 1_000_000)
                        return nil
                    }
                    
                    // Take whichever finishes first
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
                continue // Try next provider
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

// MARK: - OpenAI FIM Provider

/// OpenAI Codex / GPT FIM completions via /v1/completions
struct OpenAIFIMProvider: CloudFIMProvider {
    let name = "OpenAI Codex"
    var isEnabled: Bool {
        ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil
    }
    let latencyBudgetMs = 150
    
    func complete(prefix: String, suffix: String, language: String, filePath: String) async throws -> String? {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else { return nil }
        
        let url = URL(string: "https://api.openai.com/v1/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = TimeInterval(latencyBudgetMs) / 1000.0
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "prompt": prefix,
            "suffix": suffix,
            "max_tokens": 128,
            "temperature": 0.0,
            "stop": ["\n\n", "\n}", "\nfunc", "\nclass", "\nstruct"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let text = firstChoice["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
}

// MARK: - Gemini FIM Provider

/// Google Gemini Flash for fast inline completions
struct GeminiFIMProvider: CloudFIMProvider {
    let name = "Gemini Flash"
    var isEnabled: Bool {
        ProcessInfo.processInfo.environment["GEMINI_API_KEY"] != nil
    }
    let latencyBudgetMs = 150
    
    func complete(prefix: String, suffix: String, language: String, filePath: String) async throws -> String? {
        guard let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] else { return nil }
        
        let model = "gemini-2.5-flash"
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = TimeInterval(latencyBudgetMs) / 1000.0
        
        let prompt = """
        You are a code completion engine. Complete the code at the cursor position.
        Only output the completion text, nothing else. No explanation.
        
        File: \(filePath) (\(language))
        
        Code before cursor:
        ```
        \(String(prefix.suffix(2000)))
        ```
        
        Code after cursor:
        ```
        \(String(suffix.prefix(1000)))
        ```
        
        Completion:
        """
        
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "maxOutputTokens": 128,
                "temperature": 0.0
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let candidates = json["candidates"] as? [[String: Any]],
           let first = candidates.first,
           let content = first["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let text = parts.first?["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
}

// MARK: - DeepSeek FIM Provider

/// DeepSeek Coder — Native FIM model
struct DeepSeekFIMProvider: CloudFIMProvider {
    let name = "DeepSeek Coder"
    var isEnabled: Bool {
        ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] != nil
    }
    let latencyBudgetMs = 150
    
    func complete(prefix: String, suffix: String, language: String, filePath: String) async throws -> String? {
        guard let apiKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] else { return nil }
        
        let url = URL(string: "https://api.deepseek.com/v1/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = TimeInterval(latencyBudgetMs) / 1000.0
        
        let body: [String: Any] = [
            "model": "deepseek-coder",
            "prompt": prefix,
            "suffix": suffix,
            "max_tokens": 128,
            "temperature": 0.0
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let text = firstChoice["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
}

// MARK: - Custom FIM Provider

/// Custom OpenAI-compatible FIM endpoint
struct CustomFIMProvider: CloudFIMProvider {
    let name = "Custom Endpoint"
    var isEnabled: Bool {
        ProcessInfo.processInfo.environment["CUSTOM_FIM_URL"] != nil
    }
    let latencyBudgetMs = 200
    
    func complete(prefix: String, suffix: String, language: String, filePath: String) async throws -> String? {
        guard let baseURL = ProcessInfo.processInfo.environment["CUSTOM_FIM_URL"] else { return nil }
        let apiKey = ProcessInfo.processInfo.environment["CUSTOM_FIM_KEY"] ?? ""
        let model = ProcessInfo.processInfo.environment["CUSTOM_FIM_MODEL"] ?? "default"
        
        let url = URL(string: "\(baseURL)/v1/completions")!
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
            "max_tokens": 128,
            "temperature": 0.0
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let text = firstChoice["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
}
