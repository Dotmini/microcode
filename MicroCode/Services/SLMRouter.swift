//
//  SLMRouter.swift
//  MicroCode
//
//  Intelligent Cost-Optimal Hybrid Model Router & Task Classifier.
//  Routes tasks based on complexity: local SLMs (3B-8B) for trivial syntax,
//  Gemini Flash for rapid tool iteration, and Claude Sonnet for complex refactoring.
//  Tirawat Nantamas Founder and CEO of Dotmini Software.
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation

// MARK: - Local SLM Router (Phase 2)
// Routes trivial tasks to local Small Language Models (3B-8B via Ollama/NPU)
// saving 80% on cloud API costs. Only complex reasoning goes to frontier models.

// MARK: - Task Classification

enum TaskComplexity: Int, Comparable, CaseIterable {
    case trivial = 0           // Formatting, typo fix, rename → Local SLM
    case simple = 1             // Unit test template, doc comment → Local SLM
    case moderate = 2         // Small feature, bug fix → Fast cloud (Flash)
    case complex = 3           // Architecture, multi-file refactor → Frontier (Pro)
    case reasoning = 4       // Mathematical proof, algorithm design → Thinking model
    
    static func < (lhs: TaskComplexity, rhs: TaskComplexity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    var shouldRouteLocal: Bool {
        self == .trivial || self == .simple
    }
    
    var suggestedModelTier: String {
        switch self {
        case .trivial: return "local-3b"       // Qwen-Coder 3B, DeepSeek-Coder 1.5B
        case .simple: return "local-8b"        // Qwen2.5-Coder 7B, CodeLlama 7B
        case .moderate: return "cloud-flash"   // Gemini Flash, GPT-4o-mini, Haiku
        case .complex: return "cloud-pro"      // Gemini Pro, GPT-4o, Sonnet
        case .reasoning: return "cloud-think"  // o3, Gemini Deep Think, Opus
        }
    }
    
    var name: String {
        switch self {
        case .trivial: return "Trivial"
        case .simple: return "Simple"
        case .moderate: return "Moderate"
        case .complex: return "Complex"
        case .reasoning: return "Reasoning"
        }
    }
}

// MARK: - Local Model Registry

struct LocalModelInfo: Identifiable, Equatable {
    let id: String          // Ollama model name: "qwen2.5-coder:3b"
    let name: String
    let parameterSize: String // "3B", "7B", "8B"
    let quantization: String  // "Q4_K_M", "Q8_0", "FP16"
    let vramRequiredMB: Int
    let speedToksPerSec: Double // Measured throughput
    let capabilities: Set<LocalModelCapability>
    
    enum LocalModelCapability: String {
        case codeCompletion = "code_completion"
        case codeGeneration = "code_generation"
        case refactoring = "refactoring"
        case documentation = "documentation"
        case testGeneration = "test_generation"
        case formatting = "formatting"
        case typoFix = "typo_fix"
        case astParsing = "ast_parsing"
    }
}

// MARK: - SLM Router Service

@MainActor
final class SLMRouter: ObservableObject {
    static let shared = SLMRouter()
    
    // MARK: - Published State
    @Published private(set) var localModels: [LocalModelInfo] = []
    @Published private(set) var isLocalAvailable = false
    @Published private(set) var localRequestsHandled: Int = 0
    @Published private(set) var cloudRequestsSaved: Int = 0
    @Published private(set) var estimatedSavingsUSD: Double = 0.0
    @Published var routingEnabled: Bool = true {
        didSet { UserDefaults.standard.set(routingEnabled, forKey: "slm_routing_enabled") }
    }
    @Published var preferLocalForTrivial: Bool = true {
        didSet { UserDefaults.standard.set(preferLocalForTrivial, forKey: "slm_prefer_local") }
    }
    
    // MARK: - Classification Rules & Task Classification
    
    struct AgentContext {
        var mentionedFiles: [String] = []
        var hasErrorDiagnostics: Bool = false
    }
    
    // MARK: - Escalation State
    @Published private(set) var taskFailures: [String: Int] = [:]
    
    private init() {
        routingEnabled = UserDefaults.standard.object(forKey: "slm_routing_enabled") as? Bool ?? true
        preferLocalForTrivial = UserDefaults.standard.object(forKey: "slm_prefer_local") as? Bool ?? true
        
        let stats = UserDefaults.standard.dictionary(forKey: "SLMRouter_Stats") as? [String: Double] ?? [:]
        localRequestsHandled = Int(stats["localRequests"] ?? 0)
        cloudRequestsSaved = Int(stats["localRequests"] ?? 0)
        estimatedSavingsUSD = stats["totalSavings"] ?? 0.0
        
        discoverLocalModels()
    }
    
    func recordFailure(for taskId: String) {
        taskFailures[taskId, default: 0] += 1
    }
    
    /// Classify a prompt into a complexity tier
    func classifyTask(_ prompt: String, context: AgentContext? = nil) -> TaskComplexity {
        var score: Double = 0.0
        let lowered = prompt.lowercased()
        
        // Length-based signal
        if prompt.count > 500 { score += 1.5 }
        else if prompt.count > 200 { score += 0.8 }
        
        // Complexity indicators (weighted)
        let complexIndicators: [(pattern: String, weight: Double)] = [
            ("refactor", 2.0), ("architect", 2.5), ("redesign", 2.5),
            ("security audit", 3.0), ("vulnerability", 2.5), ("performance", 1.5),
            ("debug", 1.5), ("why", 1.0), ("investigate", 1.5),
            ("multi-file", 2.0), ("across", 1.0), ("all files", 1.5),
            ("migration", 2.0), ("upgrade", 1.5)
        ]
        
        let simpleIndicators: [(pattern: String, weight: Double)] = [
            ("format", -1.5), ("lint", -1.5), ("typo", -2.0),
            ("rename", -1.0), ("comment", -1.0), ("fix import", -1.5),
            ("add comma", -2.0), ("spacing", -2.0)
        ]
        
        for (pattern, weight) in complexIndicators {
            if lowered.contains(pattern) { score += weight }
        }
        for (pattern, weight) in simpleIndicators {
            if lowered.contains(pattern) { score += weight }
        }
        
        // Context signals
        if let ctx = context {
            if ctx.mentionedFiles.count > 3 { score += 1.5 }
            if ctx.hasErrorDiagnostics { score += 0.5 }
        }
        
        switch score {
        case ...(-1.0): return .trivial
        case (-1.0)..<1.0: return .simple  
        case 1.0..<3.0: return .moderate
        case 3.0..<5.0: return .complex
        default: return .reasoning
        }
    }
    
    // MARK: - Route Decision
    
    struct RouteDecision {
        let complexity: TaskComplexity
        let useLocal: Bool
        let suggestedModel: String
        let reason: String
        let estimatedCostCloud: Double  // What it would cost on cloud
        let estimatedCostLocal: Double  // What it costs locally (effectively $0)
    }
    
    /// Decide whether to route a task locally or to the cloud
    func route(prompt: String, currentProvider: String, currentModel: String, taskId: String? = nil) -> RouteDecision {
        var complexity = classifyTask(prompt)
        
        if let taskId = taskId, taskFailures[taskId, default: 0] >= 2 {
            if complexity == .trivial { complexity = .simple }
            else if complexity == .simple { complexity = .moderate }
            else if complexity == .moderate { complexity = .complex }
            else if complexity == .complex { complexity = .reasoning }
        }
        
        // Check if local routing is enabled and available
        let canRouteLocal = routingEnabled && isLocalAvailable && preferLocalForTrivial && complexity.shouldRouteLocal
        
        let localModel = bestLocalModel(for: complexity)
        
        // Estimate cloud cost (rough: ~$0.001 per 1K tokens for flash, ~$0.01 for pro)
        let estimatedTokens = Double(prompt.count) / 4.0 * 3.0 // rough input+output
        let cloudCostPer1K: Double
        switch complexity {
        case .trivial, .simple: cloudCostPer1K = 0.00015  // Flash pricing
        case .moderate: cloudCostPer1K = 0.001
        case .complex: cloudCostPer1K = 0.01
        case .reasoning: cloudCostPer1K = 0.06
        }
        let cloudCost = (estimatedTokens / 1000.0) * cloudCostPer1K
        
        if canRouteLocal, let model = localModel {
            return RouteDecision(
                complexity: complexity,
                useLocal: true,
                suggestedModel: model.id,
                reason: "Routing to local \(model.name) — \(complexity.name) task",
                estimatedCostCloud: cloudCost,
                estimatedCostLocal: 0.0
            )
        } else {
            return RouteDecision(
                complexity: complexity,
                useLocal: false,
                suggestedModel: currentModel,
                reason: "\(complexity.name) task → cloud \(currentModel)",
                estimatedCostCloud: cloudCost,
                estimatedCostLocal: 0.0
            )
        }
    }
    
    // MARK: - Best-of-Breed Tool Calling Recommendations
    
    /// Recommends the optimal tool calling AI provider based on task requirements
    func recommendedProvider(
        for complexity: TaskComplexity,
        requiresVision: Bool = false,
        requiresStrictSchema: Bool = false
    ) -> (provider: String, model: String, rationale: String) {
        if requiresVision {
            return (
                provider: "gemini",
                model: "gemini-2.5-flash",
                rationale: "Google Gemini is optimal for multimodal UI inspection and visual regression screenshots."
            )
        }
        if requiresStrictSchema {
            return (
                provider: "openai",
                model: "gpt-4o",
                rationale: "OpenAI GPT-4o provides strict constrained schema decoding for structural data integrity."
            )
        }
        switch complexity {
        case .trivial, .simple:
            if isLocalAvailable {
                return (
                    provider: "local",
                    model: bestLocalModel(for: complexity)?.id ?? "qwen2.5-coder:7b",
                    rationale: "Local SLM executes trivial syntax and formatting edits without cloud API latency or cost."
                )
            } else {
                return (
                    provider: "gemini",
                    model: "gemini-2.5-flash",
                    rationale: "Gemini 2.5 Flash executes high-frequency search and read-only operations with sub-second latency."
                )
            }
        case .moderate:
            return (
                provider: "gemini",
                model: "gemini-2.5-flash",
                rationale: "Gemini 2.5 Flash offers the fastest turnaround and massive context window for standard coding loops."
            )
        case .complex, .reasoning:
            return (
                provider: "anthropic",
                model: "claude-3-7-sonnet",
                rationale: "Anthropic Claude 3.5/3.7 Sonnet achieves the highest tool calling accuracy and surgical multi-file refactoring precision."
            )
        }
    }
    
    // MARK: - Record Routing
    
    func recordRouting(complexity: TaskComplexity, model: String, estimatedSavings: Double) {
        let isLocal = isLocalModel(model)
        
        // Update published state
        localRequestsHandled += isLocal ? 1 : 0
        cloudRequestsSaved += isLocal ? 1 : 0
        estimatedSavingsUSD += estimatedSavings
        
        // Save persistently
        let key = "SLMRouter_Stats"
        var stats = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        stats["totalRequests"] = (stats["totalRequests"] ?? 0) + 1
        stats["localRequests"] = (stats["localRequests"] ?? 0) + (isLocal ? 1 : 0)
        stats["totalSavings"] = (stats["totalSavings"] ?? 0) + estimatedSavings
        UserDefaults.standard.set(stats, forKey: key)
    }
    
    private func isLocalModel(_ id: String) -> Bool {
        return localModels.contains { $0.id == id }
    }
    
    // MARK: - Local Model Discovery
    
    /// Discover available Ollama models
    func discoverLocalModels() {
        Task {
            guard let url = URL(string: "http://localhost:11434/api/tags") else { return }
            
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    await MainActor.run { isLocalAvailable = false }
                    return
                }
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let jsonModels = json["models"] as? [[String: Any]] {
                    
                    var models: [LocalModelInfo] = []
                    for model in jsonModels {
                        let modelName = model["name"] as? String ?? ""
                        _ = model["size"] as? Int64 ?? 0
                        
                        var caps: Set<LocalModelInfo.LocalModelCapability> = [.codeCompletion]
                        let lower = modelName.lowercased()
                        if lower.contains("coder") || lower.contains("code") {
                            caps.formUnion([.codeGeneration, .refactoring, .testGeneration, .formatting, .typoFix])
                        }
                        if lower.contains("starcoder") || lower.contains("deepseek") {
                            caps.insert(.astParsing)
                        }
                        
                        let paramSize = extractParamSize(modelName)
                        let vram = estimateVRAM(paramSize)
                        
                        models.append(LocalModelInfo(
                            id: modelName,
                            name: modelName.components(separatedBy: ":").first ?? modelName,
                            parameterSize: paramSize,
                            quantization: lower.contains("q4") ? "Q4_K_M" : lower.contains("q8") ? "Q8_0" : "FP16",
                            vramRequiredMB: vram,
                            speedToksPerSec: 0,
                            capabilities: caps
                        ))
                    }
                    
                    await MainActor.run {
                        self.localModels = models
                        self.isLocalAvailable = !models.isEmpty
                    }
                }
            } catch {
                await MainActor.run { isLocalAvailable = false }
            }
            
            await discoverMLXModels()
        }
    }
    
    // Check for MLX models in common locations
    private func discoverMLXModels() async {
        let mlxPaths = [
            NSHomeDirectory() + "/.cache/huggingface/hub",
            NSHomeDirectory() + "/Models",
            "/opt/models"
        ]
        
        var foundMLX = false
        for path in mlxPaths {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                foundMLX = true
                break
            }
        }
        
        if foundMLX {
            await MainActor.run {
                self.isLocalAvailable = true
            }
        }
    }
    
    // MARK: - Helpers
    
    private func bestLocalModel(for complexity: TaskComplexity) -> LocalModelInfo? {
        // For trivial tasks, prefer smallest model
        // For simple tasks, prefer code-specialized model
        let candidates = localModels.sorted { a, b in
            // Prefer code-specialized models
            let aScore = a.capabilities.contains(.codeGeneration) ? 10 : 0
            let bScore = b.capabilities.contains(.codeGeneration) ? 10 : 0
            if aScore != bScore { return aScore > bScore }
            // For trivial, prefer smaller; for simple, prefer bigger
            if complexity == .trivial {
                return a.vramRequiredMB < b.vramRequiredMB
            }
            return a.vramRequiredMB > b.vramRequiredMB
        }
        return candidates.first
    }
    
    private func extractParamSize(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("1.5b") || lower.contains("1b") { return "1.5B" }
        if lower.contains("3b") { return "3B" }
        if lower.contains("7b") || lower.contains("8b") { return "7B" }
        if lower.contains("13b") || lower.contains("14b") { return "14B" }
        if lower.contains("32b") || lower.contains("34b") { return "32B" }
        if lower.contains("70b") || lower.contains("72b") { return "70B" }
        return "Unknown"
    }
    
    private func estimateVRAM(_ paramSize: String) -> Int {
        switch paramSize {
        case "1.5B": return 1500
        case "3B": return 2500
        case "7B": return 5000
        case "14B": return 10000
        case "32B": return 20000
        case "70B": return 42000
        default: return 4000
        }
    }
}
