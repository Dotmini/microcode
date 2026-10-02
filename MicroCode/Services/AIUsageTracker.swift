//
//  AIUsageTracker.swift
//  MicroCode
//
//  Created and Designed by Dotmini Software
//  Founder & CEO: Tirawat Nantamas
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//
//  Description:
//  Tracks token consumption, prompt caching ratios, and estimated USD pricing across
//  multi-provider AI invocations for BYOK, subscriptions, and local LLM sessions.
//

import Foundation
import Combine

// MARK: - Token Usage Record

/// A single record of token usage from one AI API call
struct TokenUsageRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let provider: String
    let model: String
    let promptTokens: Int
    let completionTokens: Int
    let cachedTokens: Int
    let totalTokens: Int
    let estimatedCostUSD: Double
    let taskLabel: String  // e.g. "Agent Chat", "Autocomplete", "Refactor"
    
    init(
        provider: String,
        model: String,
        promptTokens: Int,
        completionTokens: Int,
        cachedTokens: Int = 0,
        taskLabel: String = "Chat",
        inputPricePerMillion: Double = 0.0,
        outputPricePerMillion: Double = 0.0
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.provider = provider
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.cachedTokens = cachedTokens
        self.totalTokens = promptTokens + completionTokens
        self.taskLabel = taskLabel
        
        // Calculate estimated cost
        let inputCost = Double(promptTokens - cachedTokens) * inputPricePerMillion / 1_000_000.0
        let cachedCost = Double(cachedTokens) * (inputPricePerMillion * 0.25) / 1_000_000.0 // Cached tokens typically 75% cheaper
        let outputCost = Double(completionTokens) * outputPricePerMillion / 1_000_000.0
        self.estimatedCostUSD = inputCost + cachedCost + outputCost
    }
}

// MARK: - Session Summary

/// Aggregated usage stats for a time period or session
struct UsageSessionSummary: Equatable {
    let totalRequests: Int
    let totalPromptTokens: Int
    let totalCompletionTokens: Int
    let totalTokens: Int
    let totalEstimatedCostUSD: Double
    let byProvider: [String: ProviderUsageSummary]
    let byModel: [String: ModelUsageSummary]
}

struct ProviderUsageSummary: Equatable {
    let provider: String
    let requests: Int
    let totalTokens: Int
    let estimatedCostUSD: Double
}

struct ModelUsageSummary: Equatable {
    let model: String
    let provider: String
    let requests: Int
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let estimatedCostUSD: Double
    let averageLatencyMs: Double
}

// MARK: - Model Pricing Catalog

/// Static pricing data for known models (USD per 1M tokens)
/// Prices as of September 2026
struct ModelPricing {
    let inputPerMillion: Double
    let outputPerMillion: Double
    let cachedInputPerMillion: Double
    
    init(input: Double, output: Double, cached: Double? = nil) {
        self.inputPerMillion = input
        self.outputPerMillion = output
        self.cachedInputPerMillion = cached ?? (input * 0.25)
    }
    
    /// Known model pricing (September 2026)
    static let catalog: [String: ModelPricing] = [
        // OpenAI
        "gpt-4o": ModelPricing(input: 2.50, output: 10.00),
        "gpt-4o-mini": ModelPricing(input: 0.15, output: 0.60),
        "gpt-4.1": ModelPricing(input: 2.00, output: 8.00),
        "gpt-4.1-mini": ModelPricing(input: 0.40, output: 1.60),
        "gpt-4.1-nano": ModelPricing(input: 0.10, output: 0.40),
        "o1": ModelPricing(input: 15.00, output: 60.00),
        "o1-mini": ModelPricing(input: 1.10, output: 4.40),
        "o1-pro": ModelPricing(input: 150.00, output: 600.00),
        "o3": ModelPricing(input: 10.00, output: 40.00),
        "o3-mini": ModelPricing(input: 1.10, output: 4.40),
        "o4-mini": ModelPricing(input: 1.10, output: 4.40),
        // Anthropic
        "claude-3-5-sonnet": ModelPricing(input: 3.00, output: 15.00),
        "claude-3-5-haiku": ModelPricing(input: 0.80, output: 4.00),
        "claude-3-7-sonnet": ModelPricing(input: 3.00, output: 15.00),
        "claude-3-opus": ModelPricing(input: 15.00, output: 75.00),
        
        // Google Gemini
        "gemini-2.5-flash": ModelPricing(input: 0.10, output: 0.40, cached: 0.025),
        "gemini-2.5-pro": ModelPricing(input: 1.25, output: 5.00, cached: 0.3125),
        "gemini-2.0-flash": ModelPricing(input: 0.10, output: 0.40, cached: 0.025),
        "gemini-2.0-flash-thinking": ModelPricing(input: 0.10, output: 0.40, cached: 0.025),
        "gemini-2.0-pro": ModelPricing(input: 1.25, output: 5.00, cached: 0.3125),
        "gemini-1.5-pro": ModelPricing(input: 1.25, output: 5.00, cached: 0.3125),
        "gemini-1.5-flash": ModelPricing(input: 0.075, output: 0.30, cached: 0.01875),
        
        // DeepSeek
        "deepseek-chat": ModelPricing(input: 0.14, output: 0.28, cached: 0.014),
        "deepseek-coder": ModelPricing(input: 0.14, output: 0.28, cached: 0.014),
        "deepseek-reasoner": ModelPricing(input: 0.55, output: 2.19, cached: 0.14),
        "deepseek-r1": ModelPricing(input: 0.55, output: 2.19, cached: 0.14),
        "deepseek-v3": ModelPricing(input: 0.14, output: 0.28, cached: 0.014),
        
        // Qwen
        "qwen-max": ModelPricing(input: 1.60, output: 6.40),
        "qwen-plus": ModelPricing(input: 0.80, output: 3.20),
        "qwen-turbo": ModelPricing(input: 0.30, output: 0.60),
        "qwen3-235b": ModelPricing(input: 1.60, output: 6.40),
        
        // Grok
        "grok-3": ModelPricing(input: 3.00, output: 15.00),
        "grok-3-mini": ModelPricing(input: 0.30, output: 0.50),
        "grok-beta": ModelPricing(input: 5.00, output: 15.00),
        
        // GLM
        "glm-4-plus": ModelPricing(input: 0.70, output: 0.70),
        "glm-4-flash": ModelPricing(input: 0.00, output: 0.00), // Free tier
        
        // Local (Free)
        "ollama": ModelPricing(input: 0.00, output: 0.00),
        "local": ModelPricing(input: 0.00, output: 0.00),
    ]
    
    /// Fuzzy-match model name to pricing entry
    static func lookup(_ modelName: String) -> ModelPricing {
        let normalized = modelName.lowercased()
        
        // Exact match
        if let pricing = catalog[normalized] {
            return pricing
        }
        
        // Prefix match (e.g. "gpt-4o-2024-08-06" → "gpt-4o")
        for (key, pricing) in catalog {
            if normalized.hasPrefix(key) || normalized.contains(key) {
                return pricing
            }
        }
        
        // Provider-based fallback
        if normalized.contains("local") || normalized.contains("ollama") || normalized.contains("lmstudio") {
            return ModelPricing(input: 0.0, output: 0.0)
        }
        if normalized.contains("gemini") {
            if normalized.contains("pro") {
                return ModelPricing(input: 1.25, output: 5.00, cached: 0.3125)
            } else {
                return ModelPricing(input: 0.10, output: 0.40, cached: 0.025)
            }
        }
        if normalized.contains("claude") {
            if normalized.contains("haiku") {
                return ModelPricing(input: 0.80, output: 4.00, cached: 0.08)
            } else if normalized.contains("opus") {
                return ModelPricing(input: 15.00, output: 75.00, cached: 1.50)
            } else {
                return ModelPricing(input: 3.00, output: 15.00, cached: 0.30)
            }
        }
        if normalized.contains("deepseek") {
            if normalized.contains("r1") || normalized.contains("reasoner") {
                return ModelPricing(input: 0.55, output: 2.19, cached: 0.14)
            } else {
                return ModelPricing(input: 0.14, output: 0.28, cached: 0.014)
            }
        }
        if normalized.contains("qwen") {
            return ModelPricing(input: 0.80, output: 3.20)
        }
        
        // Unknown model — use conservative mid-range estimate
        return ModelPricing(input: 0.50, output: 2.0)
    }
}

// MARK: - AI Usage Tracker (Singleton)

/// Centralized service that tracks all AI token usage and estimated costs.
/// Thread-safe, observable, and persists session data to disk.
@MainActor
final class AIUsageTracker: ObservableObject {
    static let shared = AIUsageTracker()
    
    // MARK: - Published State
    
    /// All usage records for the current session
    @Published private(set) var records: [TokenUsageRecord] = []
    
    /// Running totals for the current session
    @Published private(set) var sessionTokens: Int = 0
    @Published private(set) var sessionCostUSD: Double = 0.0
    @Published private(set) var sessionRequests: Int = 0
    
    /// Budget alert threshold (USD) — 0 = disabled
    @Published var budgetAlertThreshold: Double = 0.0
    @Published private(set) var budgetAlertTriggered: Bool = false
    
    // MARK: - Persistence
    
    private let maxRecordsInMemory = 5000
    private let persistenceURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MicroCode/UsageLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
        return dir.appendingPathComponent("usage_\(dateStr).jsonl")
    }()
    
    private init() {
        loadTodayRecords()
    }
    
    // MARK: - Recording
    
    /// Record token usage from an AI API call.
    /// Call this from AIClient after each streaming completion finishes.
    func record(
        provider: String,
        model: String,
        promptTokens: Int,
        completionTokens: Int,
        cachedTokens: Int = 0,
        taskLabel: String = "Chat"
    ) {
        let pricing = ModelPricing.lookup(model)
        
        let record = TokenUsageRecord(
            provider: provider,
            model: model,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            cachedTokens: cachedTokens,
            taskLabel: taskLabel,
            inputPricePerMillion: pricing.inputPerMillion,
            outputPricePerMillion: pricing.outputPerMillion
        )
        
        records.append(record)
        sessionTokens += record.totalTokens
        sessionCostUSD += record.estimatedCostUSD
        sessionRequests += 1
        
        // Budget alert check
        if budgetAlertThreshold > 0 && sessionCostUSD >= budgetAlertThreshold && !budgetAlertTriggered {
            budgetAlertTriggered = true
            NotificationCenter.default.post(name: .aiBudgetAlertTriggered, object: nil, userInfo: [
                "totalCost": sessionCostUSD,
                "threshold": budgetAlertThreshold
            ])
        }
        
        // Persist to disk (append JSONL)
        persistRecord(record)
        
        // Memory cap
        if records.count > maxRecordsInMemory {
            records.removeFirst(records.count - maxRecordsInMemory)
        }
    }
    
    // MARK: - Summaries
    
    /// Generate aggregated summary for current session
    func sessionSummary() -> UsageSessionSummary {
        var byProvider: [String: ProviderUsageSummary] = [:]
        var byModel: [String: ModelUsageSummary] = [:]
        
        for record in records {
            // Provider aggregation
            var prov = byProvider[record.provider] ?? ProviderUsageSummary(
                provider: record.provider, requests: 0, totalTokens: 0, estimatedCostUSD: 0
            )
            prov = ProviderUsageSummary(
                provider: record.provider,
                requests: prov.requests + 1,
                totalTokens: prov.totalTokens + record.totalTokens,
                estimatedCostUSD: prov.estimatedCostUSD + record.estimatedCostUSD
            )
            byProvider[record.provider] = prov
            
            // Model aggregation
            var mdl = byModel[record.model] ?? ModelUsageSummary(
                model: record.model, provider: record.provider,
                requests: 0, promptTokens: 0, completionTokens: 0,
                totalTokens: 0, estimatedCostUSD: 0, averageLatencyMs: 0
            )
            mdl = ModelUsageSummary(
                model: record.model, provider: record.provider,
                requests: mdl.requests + 1,
                promptTokens: mdl.promptTokens + record.promptTokens,
                completionTokens: mdl.completionTokens + record.completionTokens,
                totalTokens: mdl.totalTokens + record.totalTokens,
                estimatedCostUSD: mdl.estimatedCostUSD + record.estimatedCostUSD,
                averageLatencyMs: mdl.averageLatencyMs
            )
            byModel[record.model] = mdl
        }
        
        return UsageSessionSummary(
            totalRequests: sessionRequests,
            totalPromptTokens: records.reduce(0) { $0 + $1.promptTokens },
            totalCompletionTokens: records.reduce(0) { $0 + $1.completionTokens },
            totalTokens: sessionTokens,
            totalEstimatedCostUSD: sessionCostUSD,
            byProvider: byProvider,
            byModel: byModel
        )
    }
    
    /// Get formatted cost string
    func formattedSessionCost() -> String {
        if sessionCostUSD < 0.01 {
            return String(format: "$%.4f", sessionCostUSD)
        } else if sessionCostUSD < 1.00 {
            return String(format: "$%.3f", sessionCostUSD)
        } else {
            return String(format: "$%.2f", sessionCostUSD)
        }
    }
    
    /// Get formatted token count
    func formattedSessionTokens() -> String {
        if sessionTokens >= 1_000_000 {
            return String(format: "%.1fM", Double(sessionTokens) / 1_000_000.0)
        } else if sessionTokens >= 1_000 {
            return String(format: "%.1fK", Double(sessionTokens) / 1_000.0)
        } else {
            return "\(sessionTokens)"
        }
    }
    
    // MARK: - Reset
    
    func resetSession() {
        records.removeAll()
        sessionTokens = 0
        sessionCostUSD = 0.0
        sessionRequests = 0
        budgetAlertTriggered = false
    }
    
    // MARK: - Persistence (JSONL)
    
    private func persistRecord(_ record: TokenUsageRecord) {
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(record),
                  var jsonString = String(data: data, encoding: .utf8) else { return }
            jsonString += "\n"
            
            let url = await self.persistenceURL
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(jsonString.data(using: .utf8) ?? Data())
                    handle.closeFile()
                }
            } else {
                try? jsonString.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
    
    private func loadTodayRecords() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path),
              let content = try? String(contentsOf: persistenceURL, encoding: .utf8) else { return }
        
        let decoder = JSONDecoder()
        for line in content.components(separatedBy: "\n") where !line.isEmpty {
            if let data = line.data(using: .utf8),
               let record = try? decoder.decode(TokenUsageRecord.self, from: data) {
                records.append(record)
                sessionTokens += record.totalTokens
                sessionCostUSD += record.estimatedCostUSD
                sessionRequests += 1
            }
        }
    }
    
    // MARK: - Export
    
    func exportCSV() -> String {
        var csv = "timestamp,provider,model,prompt_tokens,completion_tokens,cached_tokens,total_tokens,estimated_cost_usd,task\n"
        let formatter = ISO8601DateFormatter()
        for r in records {
            csv += "\(formatter.string(from: r.timestamp)),\(r.provider),\(r.model),\(r.promptTokens),\(r.completionTokens),\(r.cachedTokens),\(r.totalTokens),\(String(format: "%.6f", r.estimatedCostUSD)),\(r.taskLabel)\n"
        }
        return csv
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let aiBudgetAlertTriggered = Notification.Name("aiBudgetAlertTriggered")
}
