//
//  AIModelRouter.swift
//  MicroCode
//
//  Created and Designed by Dotmini Software
//  Founder & CEO: Tirawat Nantamas
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//
//  Description:
//  Intelligent model routing engine that selects the optimal model
//  based on task type, budget, speed, and provider availability across BYOK,
//  subscription sessions, and local LLM engines.
//

import Foundation

// MARK: - AI Model Router

/// Intelligent model routing engine that selects the optimal model
/// based on task type, budget, and provider availability.
///
/// Routing Strategies:
/// - .costOptimized: Pick the cheapest model that can handle the task
/// - .speedOptimized: Pick the fastest model available
/// - .qualityOptimized: Pick the most capable model available
/// - .smart: Analyze prompt to auto-select the best strategy
@MainActor
final class AIModelRouter: ObservableObject {
    static let shared = AIModelRouter()
    
    // MARK: - Types
    
    enum RoutingStrategy: String, CaseIterable, Codable {
        case smart = "Smart (Auto)"
        case costOptimized = "Cost Optimized"
        case speedOptimized = "Speed Optimized"
        case qualityOptimized = "Quality Optimized"
        case manual = "Manual (No Routing)"
    }
    
    enum TaskComplexity: String {
        case trivial     // Simple completion, boilerplate
        case moderate    // Standard code generation, explanation
        case complex     // Multi-file refactor, architecture decisions
        case reasoning   // Deep analysis, debugging, math
    }
    
    struct ModelTier: Equatable {
        let modelId: String
        let provider: String
        let tier: TaskComplexity
        let inputPricePerMillion: Double
        let outputPricePerMillion: Double
    }
    
    struct RoutingDecision: Equatable {
        let selectedModel: String
        let selectedProvider: String
        let reason: String
        let strategy: RoutingStrategy
        let estimatedCostPerKToken: Double
    }
    
    // MARK: - State
    
    @Published var activeStrategy: RoutingStrategy = .manual {
        didSet {
            UserDefaults.standard.set(activeStrategy.rawValue, forKey: "ai_routing_strategy")
        }
    }
    
    // MARK: - Model Tiering
    
    /// Categorize models into complexity tiers
    private let modelTiers: [String: TaskComplexity] = [
        // Trivial (fast, cheap autocomplete)
        "gpt-4o-mini": .trivial,
        "gemini-2.0-flash": .trivial,
        "gemini-2.5-flash": .trivial,
        "gemini-1.5-flash": .trivial,
        "claude-3-5-haiku": .trivial,
        "glm-4-flash": .trivial,
        "qwen-turbo": .trivial,
        
        // Moderate (standard coding tasks)
        "gpt-4o": .moderate,
        "gpt-4-turbo": .moderate,
        "chatgpt-4o-latest": .moderate,
        "claude-3-5-sonnet": .moderate,
        "claude-3-7-sonnet": .moderate,
        "gemini-2.5-pro": .moderate,
        "gemini-1.5-pro": .moderate,
        "deepseek-chat": .moderate,
        "qwen-plus": .moderate,
        "qwen-max": .moderate,
        "glm-4-plus": .moderate,
        
        // Complex (heavy multi-file agent work)
        "claude-3-opus": .complex,
        
        // Reasoning (deep thinking, math, debugging)
        "o1": .reasoning,
        "o1-mini": .reasoning,
        "o3-mini": .reasoning,
        "deepseek-reasoner": .reasoning,
    ]
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: "ai_routing_strategy"),
           let strategy = RoutingStrategy(rawValue: saved) {
            self.activeStrategy = strategy
        }
    }
    
    // MARK: - Task Complexity Detection
    
    /// Analyze a prompt to determine task complexity
    func analyzeComplexity(prompt: String, messageCount: Int = 0) -> TaskComplexity {
        let lowered = prompt.lowercased()
        let wordCount = prompt.split(separator: " ").count
        
        // Reasoning indicators
        let reasoningKeywords = ["debug", "why does", "explain why", "root cause", "prove", "analyze",
                                  "what's wrong", "error", "bug", "crash", "failing", "broken",
                                  "optimize", "performance", "complex algorithm"]
        if reasoningKeywords.contains(where: { lowered.contains($0) }) {
            return .reasoning
        }
        
        // Complex indicators
        let complexKeywords = ["refactor", "architecture", "redesign", "migrate", "implement entire",
                               "create a full", "build a complete", "multi-file", "system design",
                               "integration", "deployment", "CI/CD", "entire project"]
        if complexKeywords.contains(where: { lowered.contains($0) }) || wordCount > 200 {
            return .complex
        }
        
        // Trivial indicators
        let trivialKeywords = ["rename", "format", "typo", "comment", "import", "add a line",
                               "simple", "quick", "boilerplate", "template", "hello world",
                               "what is", "how to"]
        if trivialKeywords.contains(where: { lowered.contains($0) }) && wordCount < 30 {
            return .trivial
        }
        
        // Default: moderate
        return .moderate
    }
    
    // MARK: - Model Selection
    
    /// Route to the best model based on active strategy and task analysis
    func route(
        prompt: String,
        currentModel: String,
        currentProvider: String,
        availableKeys: [String: Bool],  // provider -> hasKey
        messageCount: Int = 0
    ) -> RoutingDecision {
        guard activeStrategy != .manual else {
            return RoutingDecision(
                selectedModel: currentModel,
                selectedProvider: currentProvider,
                reason: "Manual mode — using selected model",
                strategy: .manual,
                estimatedCostPerKToken: estimateCostPerKToken(model: currentModel)
            )
        }
        
        let complexity = activeStrategy == .smart
            ? analyzeComplexity(prompt: prompt, messageCount: messageCount)
            : nil
        
        let targetComplexity: TaskComplexity
        switch activeStrategy {
        case .costOptimized:
            targetComplexity = .trivial
        case .speedOptimized:
            targetComplexity = .trivial
        case .qualityOptimized:
            targetComplexity = .complex
        case .smart:
            targetComplexity = complexity ?? .moderate
        case .manual:
            targetComplexity = .moderate
        }
        
        // Find best available model for the target complexity
        let candidates = findCandidates(
            targetComplexity: targetComplexity,
            availableKeys: availableKeys,
            strategy: activeStrategy
        )
        
        if let best = candidates.first {
            return RoutingDecision(
                selectedModel: best.modelId,
                selectedProvider: best.provider,
                reason: "[\(activeStrategy.rawValue)] Task: \(targetComplexity.rawValue) → \(best.modelId)",
                strategy: activeStrategy,
                estimatedCostPerKToken: estimateCostPerKToken(model: best.modelId)
            )
        }
        
        // Fallback to current model
        return RoutingDecision(
            selectedModel: currentModel,
            selectedProvider: currentProvider,
            reason: "No better candidate found — keeping current model",
            strategy: activeStrategy,
            estimatedCostPerKToken: estimateCostPerKToken(model: currentModel)
        )
    }
    
    // MARK: - Candidate Selection
    
    private func findCandidates(
        targetComplexity: TaskComplexity,
        availableKeys: [String: Bool],
        strategy: RoutingStrategy
    ) -> [ModelTier] {
        var candidates: [ModelTier] = []
        
        for (modelId, tier) in modelTiers {
            // Match complexity level
            guard complexityLevel(tier) >= complexityLevel(targetComplexity) else { continue }
            
            let pricing = ModelPricing.lookup(modelId)
            let provider = inferProvider(modelId: modelId)
            
            // Check if provider key is available
            let hasAccess = availableKeys[provider] ?? false ||
                            provider == "local" ||
                            provider == "ollama"
            guard hasAccess else { continue }
            
            candidates.append(ModelTier(
                modelId: modelId,
                provider: provider,
                tier: tier,
                inputPricePerMillion: pricing.inputPerMillion,
                outputPricePerMillion: pricing.outputPerMillion
            ))
        }
        
        // Sort based on strategy
        switch strategy {
        case .costOptimized:
            candidates.sort { ($0.inputPricePerMillion + $0.outputPricePerMillion) < ($1.inputPricePerMillion + $1.outputPricePerMillion) }
        case .speedOptimized:
            // Prefer trivial-tier models (they're fastest), then by cost
            candidates.sort {
                if complexityLevel($0.tier) != complexityLevel($1.tier) {
                    return complexityLevel($0.tier) < complexityLevel($1.tier)
                }
                return ($0.inputPricePerMillion + $0.outputPricePerMillion) < ($1.inputPricePerMillion + $1.outputPricePerMillion)
            }
        case .qualityOptimized, .smart:
            // Prefer highest capability, then cheapest within that tier
            candidates.sort {
                if complexityLevel($0.tier) != complexityLevel($1.tier) {
                    return complexityLevel($0.tier) > complexityLevel($1.tier)
                }
                return ($0.inputPricePerMillion + $0.outputPricePerMillion) < ($1.inputPricePerMillion + $1.outputPricePerMillion)
            }
        case .manual:
            break
        }
        
        return candidates
    }
    
    private func complexityLevel(_ c: TaskComplexity) -> Int {
        switch c {
        case .trivial: return 0
        case .moderate: return 1
        case .complex: return 2
        case .reasoning: return 3
        }
    }
    
    private func inferProvider(modelId: String) -> String {
        let id = modelId.lowercased()
        if id.contains("gpt") || id.contains("o1") || id.contains("o3") || id.contains("o4") { return "openai" }
        if id.contains("claude") { return "anthropic" }
        if id.contains("gemini") { return "gemini" }
        if id.contains("deepseek") { return "deepseek" }
        if id.contains("qwen") { return "qwen" }
        if id.contains("grok") { return "grok" }
        if id.contains("glm") { return "glm" }
        if id.contains("ollama") || id.contains("local") { return "local" }
        return "openai" // default
    }
    
    private func estimateCostPerKToken(model: String) -> Double {
        let pricing = ModelPricing.lookup(model)
        return (pricing.inputPerMillion + pricing.outputPerMillion) / 2000.0  // avg cost per 1K tokens
    }
}
