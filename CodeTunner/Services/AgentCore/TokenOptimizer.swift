//
//  TokenOptimizer.swift
//  CodeTunner
//
//  Advanced Token Optimizer — LLMLingua-inspired context compression
//  Techniques: Extractive summarization, sliding window, stop-word pruning,
//  semantic deduplication, budget-aware truncation.
//  Open-source inspiration: LLMLingua, LongLLMLingua, AutoCompressor
//

import Foundation
import NaturalLanguage

// MARK: - Token Budget Configuration

struct TokenBudget {
    var maxSystemTokens: Int = 4000
    var maxHistoryTokens: Int = 8000
    var maxContextTokens: Int = 6000
    var maxUserTokens: Int = 4000
    var totalBudget: Int = 24000
    
    /// Dynamic budget allocation based on task complexity
    static func forTask(_ complexity: TaskComplexity) -> TokenBudget {
        switch complexity {
        case .simple:
            return TokenBudget(maxSystemTokens: 2000, maxHistoryTokens: 3000, maxContextTokens: 2000, maxUserTokens: 2000, totalBudget: 10000)
        case .moderate:
            return TokenBudget(maxSystemTokens: 3000, maxHistoryTokens: 6000, maxContextTokens: 5000, maxUserTokens: 3000, totalBudget: 18000)
        case .complex:
            return TokenBudget(maxSystemTokens: 4000, maxHistoryTokens: 10000, maxContextTokens: 8000, maxUserTokens: 4000, totalBudget: 28000)
        case .chat:
            // Casual conversation needs much less context
            return TokenBudget(maxSystemTokens: 800, maxHistoryTokens: 3000, maxContextTokens: 500, maxUserTokens: 2000, totalBudget: 6500)
        }
    }
    
    enum TaskComplexity {
        case simple, moderate, complex, chat
    }
}

// MARK: - Token Usage Stats

struct TokenUsageStats {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var savedTokens: Int = 0
    var compressionRatio: Double = 1.0
    var totalRequests: Int = 0
    var totalCost: Double = 0.0  // Estimated cost in USD
    
    var formattedSavings: String {
        let pct = savedTokens > 0 ? Double(savedTokens) / Double(inputTokens + savedTokens) * 100 : 0
        return String(format: "%.0f%% saved", pct)
    }
}

// MARK: - Token Optimizer

@MainActor
class TokenOptimizer: ObservableObject {
    static let shared = TokenOptimizer()
    
    @Published var stats = TokenUsageStats()
    @Published var isOptimizing = false
    
    // Stop words for pruning (extended set)
    private let stopWords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "shall",
        "should", "may", "might", "must", "can", "could", "to", "of", "in",
        "for", "on", "with", "at", "by", "from", "as", "into", "through",
        "during", "before", "after", "above", "below", "between", "same",
        "but", "or", "nor", "not", "so", "very", "just", "about", "up",
        "out", "if", "then", "than", "too", "also", "that", "this", "these",
        "those", "it", "its", "they", "them", "their", "we", "our", "he",
        "she", "him", "her", "his", "my", "your", "i", "me", "you"
    ]
    
    // Code-related keywords that should never be pruned
    private let codeKeywords: Set<String> = [
        "function", "class", "struct", "enum", "protocol", "extension", "import",
        "return", "throw", "try", "catch", "async", "await", "var", "let",
        "const", "static", "private", "public", "internal", "override", "init",
        "deinit", "guard", "switch", "case", "default", "break", "continue",
        "while", "for", "if", "else", "nil", "null", "true", "false",
        "self", "super", "type", "error", "file", "path", "url", "data",
        "string", "int", "float", "double", "bool", "array", "dict",
        "func", "fn", "def", "pub", "mod", "use", "impl", "trait",
        "interface", "abstract", "final", "sealed", "open", "package",
        "create", "read", "write", "delete", "update", "list", "search",
        "build", "run", "test", "deploy", "install", "remove", "add",
        "fix", "bug", "feature", "refactor", "optimize", "debug"
    ]
    
    // MARK: - Estimate Token Count (fast approximation)
    
    nonisolated func estimateTokens(_ text: String) -> Int {
        // GPT-style tokenization: ~4 chars per token for English, ~2 for code
        let hasCode = text.contains("{") || text.contains("func ") || text.contains("def ")
        let ratio: Double = hasCode ? 3.0 : 4.0
        return max(1, Int(ceil(Double(text.count) / ratio)))
    }
    
    // MARK: - Compress System Prompt
    
    /// Compress system prompt by removing redundant instructions and formatting
    func compressSystemPrompt(_ prompt: String, budget: Int) -> String {
        let tokens = estimateTokens(prompt)
        if tokens <= budget { return prompt }
        
        // Strategy 1: Remove markdown formatting overhead
        var compressed = prompt
            .replacingOccurrences(of: "## ", with: "# ")
            .replacingOccurrences(of: "### ", with: "# ")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "---\n", with: "\n")
        
        // Strategy 2: Remove verbose instruction phrases
        let verbosePatterns = [
            "You MUST ", "ALWAYS ", "NEVER ", "CRITICAL RULES\n",
            "Make sure to ", "Please ensure ", "It is important that ",
            "Note that ", "Remember to ", "Keep in mind that "
        ]
        for pattern in verbosePatterns {
            compressed = compressed.replacingOccurrences(of: pattern, with: "")
        }
        
        // Strategy 3: Truncate if still over budget
        let compressedTokens = estimateTokens(compressed)
        if compressedTokens > budget {
            let ratio = Double(budget) / Double(compressedTokens)
            let targetChars = Int(Double(compressed.count) * ratio)
            compressed = String(compressed.prefix(targetChars))
        }
        
        stats.savedTokens += tokens - estimateTokens(compressed)
        return compressed
    }
    
    // MARK: - Compress Conversation History
    
    /// Compress conversation history using summarization and deduplication
    func compressHistory(_ messages: [(role: String, content: String)], budget: Int) -> [(role: String, content: String)] {
        guard !messages.isEmpty else { return [] }
        
        let totalTokens = messages.reduce(0) { $0 + estimateTokens($1.content) }
        if totalTokens <= budget { return messages }
        
        var result: [(role: String, content: String)] = []
        let originalTokens = totalTokens
        
        // Strategy 1: Keep recent messages intact, summarize older ones
        let keepCount = min(6, messages.count) // Keep last 6 messages verbatim
        let toSummarize = Array(messages.dropLast(keepCount))
        let recentMessages = Array(messages.suffix(keepCount))
        
        // Summarize older messages
        if !toSummarize.isEmpty {
            let summary = summarizeMessages(toSummarize)
            if !summary.isEmpty {
                result.append((role: "user", content: "[Previous conversation summary: \(summary)]"))
            }
        }
        
        // Add recent messages with per-message compression
        let remainingBudget = budget - result.reduce(0) { $0 + estimateTokens($1.content) }
        let perMessageBudget = max(200, remainingBudget / max(1, recentMessages.count))
        
        for msg in recentMessages {
            let msgTokens = estimateTokens(msg.content)
            if msgTokens > perMessageBudget {
                let compressed = compressText(msg.content, targetTokens: perMessageBudget)
                result.append((role: msg.role, content: compressed))
            } else {
                result.append(msg)
            }
        }
        
        let finalTokens = result.reduce(0) { $0 + estimateTokens($1.content) }
        stats.savedTokens += max(0, originalTokens - finalTokens)
        
        return result
    }
    
    // MARK: - Compress File Content
    
    /// Compress file content by extracting relevant sections
    func compressFileContent(_ content: String, query: String? = nil, budget: Int = 3000) -> String {
        let tokens = estimateTokens(content)
        if tokens <= budget { return content }
        
        let lines = content.components(separatedBy: "\n")
        
        // Strategy 1: If we have a query, extract relevant sections
        if let query = query?.lowercased(), !query.isEmpty {
            let queryWords = Set(query.components(separatedBy: .whitespaces).filter { $0.count > 2 })
            var scored: [(index: Int, score: Double)] = []
            
            for (i, line) in lines.enumerated() {
                let lower = line.lowercased()
                var score: Double = 0
                
                // Keyword relevance
                for word in queryWords {
                    if lower.contains(word) { score += 2.0 }
                }
                
                // Structure relevance (function/class definitions)
                if isStructuralLine(line) { score += 1.5 }
                
                // Proximity boost (nearby lines inherit score)
                scored.append((index: i, score: score))
            }
            
            // Propagate scores to neighboring lines (context window)
            let contextWindow = 3
            var boosted = scored
            for (i, s) in scored.enumerated() {
                if s.score > 0 {
                    for j in max(0, i - contextWindow)...min(lines.count - 1, i + contextWindow) {
                        if i != j { boosted[j].score += s.score * 0.3 }
                    }
                }
            }
            
            // Select top-scoring lines within budget
            let sorted = boosted.sorted { $0.score > $1.score }
            var selectedIndices = Set<Int>()
            var currentTokens = 0
            
            for item in sorted {
                let lineTokens = estimateTokens(lines[item.index])
                if currentTokens + lineTokens > budget { break }
                selectedIndices.insert(item.index)
                currentTokens += lineTokens
            }
            
            // Rebuild in order with ellipsis markers
            var result = ""
            var lastIncluded = -2
            for i in 0..<lines.count {
                if selectedIndices.contains(i) {
                    if i - lastIncluded > 1 { result += "\n... (lines \(lastIncluded + 2)-\(i) omitted) ...\n" }
                    result += lines[i] + "\n"
                    lastIncluded = i
                }
            }
            
            stats.savedTokens += tokens - estimateTokens(result)
            return result
        }
        
        // Strategy 2: No query — smart structural extraction
        var result = ""
        var currentTokens = 0
        
        // Always include first 20 lines (imports, declarations)
        let headerLines = Array(lines.prefix(20))
        for line in headerLines {
            result += line + "\n"
            currentTokens += estimateTokens(line)
        }
        
        // Include structural lines (function/class definitions)
        for (i, line) in lines.enumerated() where i >= 20 {
            if currentTokens >= budget { break }
            if isStructuralLine(line) {
                result += line + "\n"
                currentTokens += estimateTokens(line)
                // Include next 2 lines for context
                for j in 1...2 {
                    if i + j < lines.count {
                        result += lines[i + j] + "\n"
                        currentTokens += estimateTokens(lines[i + j])
                    }
                }
            }
        }
        
        // Add last 10 lines
        if lines.count > 30 {
            result += "\n... (middle section omitted) ...\n"
            for line in lines.suffix(10) {
                result += line + "\n"
            }
        }
        
        stats.savedTokens += tokens - estimateTokens(result)
        return result
    }
    
    // MARK: - Compress Tool Output
    
    /// Compress tool execution output (grep results, directory listings, etc.)
    func compressToolOutput(_ output: String, toolName: String, budget: Int = 2000) -> String {
        let tokens = estimateTokens(output)
        if tokens <= budget { return output }
        
        switch toolName {
        case "grep_search":
            // Keep unique file matches, limit lines per file
            let lines = output.components(separatedBy: "\n")
            var fileGroups: [String: [String]] = [:]
            for line in lines {
                if let colonIdx = line.firstIndex(of: ":") {
                    let file = String(line[..<colonIdx])
                    if fileGroups[file] == nil { fileGroups[file] = [] }
                    if (fileGroups[file]?.count ?? 0) < 3 {  // Max 3 matches per file
                        fileGroups[file]?.append(line)
                    }
                }
            }
            let compressed = fileGroups.flatMap { $0.value }.joined(separator: "\n")
            stats.savedTokens += tokens - estimateTokens(compressed)
            return compressed + "\n(results compressed: \(lines.count) → \(fileGroups.values.reduce(0) { $0 + $1.count }) lines)"
            
        case "list_directory_tree":
            // Limit depth and file count
            let lines = output.components(separatedBy: "\n")
            let limited = Array(lines.prefix(50))
            let result = limited.joined(separator: "\n") + (lines.count > 50 ? "\n... (\(lines.count - 50) more entries)" : "")
            stats.savedTokens += tokens - estimateTokens(result)
            return result
            
        case "shell":
            // Keep first and last sections of command output
            let lines = output.components(separatedBy: "\n")
            if lines.count > 40 {
                let head = Array(lines.prefix(15)).joined(separator: "\n")
                let tail = Array(lines.suffix(15)).joined(separator: "\n")
                let result = head + "\n\n... (\(lines.count - 30) lines omitted) ...\n\n" + tail
                stats.savedTokens += tokens - estimateTokens(result)
                return result
            }
            return String(output.prefix(budget * 4)) // Rough char budget
            
        default:
            // Generic truncation with head + tail strategy
            if output.count > budget * 4 {
                let headChars = budget * 2
                let tailChars = budget
                let result = String(output.prefix(headChars)) + "\n\n... (truncated) ...\n\n" + String(output.suffix(tailChars))
                stats.savedTokens += tokens - estimateTokens(result)
                return result
            }
            return String(output.prefix(budget * 4))
        }
    }
    
    // MARK: - Detect Task Complexity
    
    func detectComplexity(_ message: String, hasToolCalls: Bool = false) -> TokenBudget.TaskComplexity {
        let lower = message.lowercased()
        
        // Check for casual conversation (no code-related intent)
        let chatIndicators = [
            "สวัสดี", "hello", "hi", "hey", "how are", "what's up", "ขอบคุณ", "thanks",
            "tell me about", "explain", "what is", "who is", "why",
            "ช่วยอธิบาย", "คืออะไร", "เล่าให้ฟัง", "คุยกัน", "ถาม",
            "opinion", "think about", "recommend", "suggest", "คิดยังไง",
            "joke", "story", "fun", "interesting", "cool"
        ]
        let isChat = chatIndicators.contains(where: { lower.contains($0) }) &&
            !lower.contains("code") && !lower.contains("file") && !lower.contains("project") &&
            !lower.contains("build") && !lower.contains("fix") && !lower.contains("create")
        
        if isChat { return .chat }
        
        // Code-related complexity detection
        let complexIndicators = [
            "refactor", "migrate", "redesign", "architecture", "full stack",
            "multiple files", "entire project", "database", "authentication",
            "deploy", "ci/cd", "pipeline", "ทำ project", "สร้างโปรเจค",
            "build the", "create a new", "implement", "integrate"
        ]
        let simpleIndicators = [
            "fix this", "one line", "typo", "rename", "small change",
            "what does this", "explain this", "single file"
        ]
        
        if complexIndicators.contains(where: { lower.contains($0) }) { return .complex }
        if simpleIndicators.contains(where: { lower.contains($0) }) { return .simple }
        
        return .moderate
    }
    
    // MARK: - Private Helpers
    
    private func summarizeMessages(_ messages: [(role: String, content: String)]) -> String {
        // Extractive summarization: pick key sentences from each message
        var summaryParts: [String] = []
        
        for msg in messages {
            let sentences = msg.content.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
                .filter { $0.trimmingCharacters(in: .whitespaces).count > 10 }
            
            // Score sentences by keyword density
            let scored = sentences.map { sentence -> (String, Double) in
                let words = sentence.lowercased().components(separatedBy: .whitespaces)
                let importantWords = words.filter { !stopWords.contains($0) && $0.count > 2 }
                let score = Double(importantWords.count) / max(1, Double(words.count))
                return (sentence.trimmingCharacters(in: .whitespaces), score)
            }.sorted { $0.1 > $1.1 }
            
            // Take top 1-2 sentences per message
            let topSentences = scored.prefix(2).map { $0.0 }
            if !topSentences.isEmpty {
                let role = msg.role == "user" ? "User" : "AI"
                summaryParts.append("\(role): \(topSentences.joined(separator: ". "))")
            }
        }
        
        return summaryParts.joined(separator: " | ")
    }
    
    func compressText(_ text: String, targetTokens: Int) -> String {
        let currentTokens = estimateTokens(text)
        if currentTokens <= targetTokens { return text }
        
        // Strategy: Remove stop words from non-code sections
        let lines = text.components(separatedBy: "\n")
        var compressed: [String] = []
        var inCodeBlock = false
        
        for line in lines {
            if line.contains("```") { inCodeBlock.toggle() }
            
            if inCodeBlock {
                compressed.append(line)  // Keep code blocks intact
            } else {
                // Prune stop words from prose
                let words = line.components(separatedBy: " ")
                let pruned = words.filter { word in
                    let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                    return !stopWords.contains(lower) || codeKeywords.contains(lower) || word.count <= 1
                }
                compressed.append(pruned.joined(separator: " "))
            }
        }
        
        var result = compressed.joined(separator: "\n")
        let resultTokens = estimateTokens(result)
        
        // If still over budget, hard truncate
        if resultTokens > targetTokens {
            let ratio = Double(targetTokens) / Double(resultTokens)
            let targetChars = Int(Double(result.count) * ratio)
            result = String(result.prefix(targetChars)) + "\n... (compressed)"
        }
        
        return result
    }
    
    nonisolated private func isStructuralLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let patterns = [
            "func ", "fn ", "def ", "function ", "async func ",
            "class ", "struct ", "enum ", "protocol ", "trait ",
            "extension ", "impl ", "interface ",
            "pub fn ", "pub struct ", "pub enum ",
            "private func ", "public func ", "internal func ",
            "override func ", "static func ",
            "// MARK:", "/// ", "# "
        ]
        return patterns.contains(where: { trimmed.hasPrefix($0) })
    }
    
    // MARK: - Reset Stats
    
    func resetStats() {
        stats = TokenUsageStats()
    }
    
    // MARK: - Token Cost Estimation
    
    nonisolated func estimateCost(inputTokens: Int, outputTokens: Int, model: String) -> Double {
        // Approximate pricing per 1M tokens (input/output)
        let pricing: (input: Double, output: Double) = {
            switch model {
            case _ where model.contains("gpt-4o"):
                return (2.50, 10.0)
            case _ where model.contains("gpt-4o-mini"):
                return (0.15, 0.60)
            case _ where model.contains("claude-sonnet-4"):
                return (3.0, 15.0)
            case _ where model.contains("claude-3-5-haiku"):
                return (0.25, 1.25)
            case _ where model.contains("gemini-2.5-flash"):
                return (0.15, 0.60)
            case _ where model.contains("gemini-2.5-pro"):
                return (1.25, 10.0)
            case _ where model.contains("deepseek"):
                return (0.14, 0.28)
            default:
                return (1.0, 3.0) // Conservative default
            }
        }()
        
        return (Double(inputTokens) / 1_000_000 * pricing.input) +
               (Double(outputTokens) / 1_000_000 * pricing.output)
    }
}
