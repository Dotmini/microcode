//
//  TokenOptimizer.swift
//  MicroCode
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
    var maxSystemTokens: Int = 64_000
    var maxHistoryTokens: Int = 1_000_000
    var maxContextTokens: Int = 1_500_000
    var maxUserTokens: Int = 250_000
    var totalBudget: Int = 2_500_000
    
    /// Dynamic budget allocation based on task complexity (supporting modern 1M–2M+ context models)
    static func forTask(_ complexity: TaskComplexity) -> TokenBudget {
        switch complexity {
        case .simple:
            return TokenBudget(maxSystemTokens: 32_000, maxHistoryTokens: 250_000, maxContextTokens: 250_000, maxUserTokens: 64_000, totalBudget: 500_000)
        case .moderate:
            return TokenBudget(maxSystemTokens: 64_000, maxHistoryTokens: 500_000, maxContextTokens: 750_000, maxUserTokens: 128_000, totalBudget: 1_200_000)
        case .complex:
            return TokenBudget(maxSystemTokens: 128_000, maxHistoryTokens: 1_200_000, maxContextTokens: 1_800_000, maxUserTokens: 500_000, totalBudget: 2_500_000)
        case .chat:
            return TokenBudget(maxSystemTokens: 16_000, maxHistoryTokens: 150_000, maxContextTokens: 64_000, maxUserTokens: 32_000, totalBudget: 300_000)
        }
    }
    
    enum TaskComplexity {
        case simple, moderate, complex, chat
    }
}

// MARK: - TokenMem Optimization Mode

enum TokenMemMode: String, CaseIterable, Codable, Identifiable {
    case balanced = "Balanced"
    case ultraSave = "Ultra-Save"
    case maxRecall = "Max Recall"
    
    var id: String { rawValue }
    
    var subtitle: String {
        switch self {
        case .balanced:
            return "AST folding, file-read dedup, and cache-aligned 6-turn epochs"
        case .ultraSave:
            return "Aggressive AST skeleton windowing and tight tool output budgets"
        case .maxRecall:
            return "Full file slices with KV-prefix caching and schema deduplication"
        }
    }
    
    var maxUnwindowedFileLines: Int {
        switch self {
        case .ultraSave: return 360
        case .balanced: return 600
        case .maxRecall: return 1400
        }
    }
    
    var iterativeBudgetMultiplier: Double {
        switch self {
        case .ultraSave: return 0.55
        case .balanced: return 1.0
        case .maxRecall: return 1.6
        }
    }
}

// MARK: - Token Usage Stats

struct TokenUsageStats: Codable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var savedTokens: Int = 0
    var compressionRatio: Double = 1.0
    var totalRequests: Int = 0
    var totalCost: Double = 0.0  // Estimated cost in USD
    var cacheHits: Int = 0
    var cacheMisses: Int = 0
    var cachedTokens: Int = 0
    var activeProvider: String = ""
    var activeModel: String = ""
    
    // Per-Layer TokenMem v3 Breakdown
    var savedBySchemaDedup: Int = 0
    var savedByFileReadDedup: Int = 0
    var savedByToolFolding: Int = 0
    var savedByEpochCompaction: Int = 0
    
    var effectiveSavingsPercent: Double {
        let totalSavedAndCached = savedTokens + cachedTokens
        let baseline = max(1, inputTokens + savedTokens)
        return min(99.0, (Double(totalSavedAndCached) / Double(baseline)) * 100.0)
    }
    
    var formattedSavings: String {
        return String(format: "%.0f%% saved", effectiveSavingsPercent)
    }
}

// MARK: - Token Optimizer (TokenMem v3 Engine)

@MainActor
class TokenOptimizer: ObservableObject {
    static let shared = TokenOptimizer()
    
    @Published var stats = TokenUsageStats()
    @Published var isOptimizing = false
    @Published var mode: TokenMemMode = {
        let raw = UserDefaults.standard.string(forKey: "microcode.tokenMemMode") ?? TokenMemMode.balanced.rawValue
        return TokenMemMode(rawValue: raw) ?? .balanced
    }() {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "microcode.tokenMemMode")
        }
    }
    
    struct FileReadCacheEntry {
        let contentHash: Int
        let lineCount: Int
        let timestamp: Date
        var hitCount: Int
    }
    
    /// Session-scoped file slice deduplication registry (`path#start-end` -> entry)
    private var fileReadRegistry: [String: FileReadCacheEntry] = [:]
    
    // Stop words for light prose pruning (NEVER include negations, modals, or directional prepositions)
    private let stopWords: Set<String> = [
        "the", "a", "an", "been", "being",
        "very", "just", "too", "also", "that", "this", "these", "those"
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
        "fix", "bug", "feature", "refactor", "optimize", "debug",
        "not", "no", "never", "always", "must", "should", "only"
    ]

    private let statsKey = "microcode.agentUsage.v2"

    private init() {
        if let data = UserDefaults.standard.data(forKey: statsKey),
           let saved = try? JSONDecoder().decode(TokenUsageStats.self, from: data) {
            stats = saved
        }
    }
    
    // MARK: - Estimate Token Count (fast approximation)
    
    nonisolated func estimateTokens(_ text: String) -> Int {
        // GPT-style tokenization: ~4 chars per token for English, ~3 for code
        let hasCode = text.contains("{") || text.contains("func ") || text.contains("def ")
        let ratio: Double = hasCode ? 3.0 : 4.0
        return max(1, Int(ceil(Double(text.count) / ratio)))
    }
    
    // MARK: - Compress System Prompt
    
    /// Compress system prompt by removing redundant formatting while strictly preserving negative constraints
    func compressSystemPrompt(_ prompt: String, budget: Int) -> String {
        let tokens = estimateTokens(prompt)
        if tokens <= budget { return prompt }
        
        // Strategy 1: Remove markdown formatting overhead without stripping semantic modals (NEVER/ALWAYS/MUST)
        var compressed = prompt
            .replacingOccurrences(of: "### ", with: "# ")
            .replacingOccurrences(of: "## ", with: "# ")
            .replacingOccurrences(of: "---\n", with: "\n")
        
        // Strategy 2: Remove only filler politeness phrases that never alter constraints
        let verbosePatterns = [
            "Please ensure that ", "It is important to note that ",
            "Keep in mind that "
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
        
        stats.savedTokens += max(0, tokens - estimateTokens(compressed))
        return compressed
    }
    
    // MARK: - Compress Conversation History
    
    /// Compress conversation history using summarization and deduplication
    func compressHistory(_ messages: [(role: String, content: String)], budget: Int) -> [(role: String, content: String)] {
        guard !messages.isEmpty else { return [] }
        
        // Strategy 0: Compact only very old, massive tool dumps (> 40,000 chars) outside the recent window
        var sanitizedMessages: [(role: String, content: String)] = []
        let recentProtectedCount = 6
        for (idx, msg) in messages.enumerated() {
            if idx < messages.count - recentProtectedCount && msg.content.count > 40_000 {
                if msg.content.contains(AIStructuredTurnCodec.markerKey) {
                    let compacted = AIStructuredTurnCodec.compactToolOutputsIfNeeded(msg.content, maxCharsPerOutput: 6_000)
                    sanitizedMessages.append((role: msg.role, content: compacted))
                } else if msg.content.contains("Tool execution results:") {
                    let head = String(msg.content.prefix(4_000))
                    let tail = String(msg.content.suffix(2_000))
                    let summary = head + "\n\n... [Older bulky tool output compacted] ...\n\n" + tail
                    sanitizedMessages.append((role: msg.role, content: summary))
                } else {
                    sanitizedMessages.append(msg)
                }
            } else {
                sanitizedMessages.append(msg)
            }
        }
        
        let totalTokens = sanitizedMessages.reduce(0) { $0 + estimateTokens($1.content) }
        let effectiveBudget = max(40_000, min(budget, 160_000))
        if totalTokens <= effectiveBudget { return sanitizedMessages }
        
        var result: [(role: String, content: String)] = []
        let originalTokens = totalTokens
        
        // Strategy 1: Keep recent messages intact, summarize older ones
        let keepCount = min(8, sanitizedMessages.count) // Keep last 8 messages verbatim
        let toSummarize = Array(sanitizedMessages.dropLast(keepCount))
        let recentMessages = Array(sanitizedMessages.suffix(keepCount))
        
        // Summarize older messages
        if !toSummarize.isEmpty {
            let summary = summarizeMessages(toSummarize)
            if !summary.isEmpty {
                result.append((role: "user", content: "[Previous conversation summary: \(summary)]"))
            }
        }
        
        // Add recent messages with per-message compression only if over budget
        let remainingBudget = effectiveBudget - result.reduce(0) { $0 + estimateTokens($1.content) }
        let perMessageBudget = max(2_000, remainingBudget / max(1, recentMessages.count))
        
        for msg in recentMessages {
            let msgTokens = estimateTokens(msg.content)
            if msgTokens > perMessageBudget {
                if msg.content.contains(AIStructuredTurnCodec.markerKey) {
                    let compacted = AIStructuredTurnCodec.compactToolOutputsIfNeeded(msg.content, maxCharsPerOutput: perMessageBudget * 4)
                    result.append((role: msg.role, content: compacted))
                } else {
                    let compressed = compressText(msg.content, targetTokens: perMessageBudget)
                    result.append((role: msg.role, content: compressed))
                }
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
    func compressFileContent(_ content: String, query: String? = nil, budget: Int = 150_000) -> String {
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
    
    /// Compress tool execution output while preserving compiler errors, stack traces, and code context
    func compressToolOutput(_ output: String, toolName: String, budget: Int = 24_000) -> String {
        let tokens = estimateTokens(output)
        if tokens <= budget { return output }
        
        switch toolName {
        case "grep_search":
            // Keep unique file matches, up to 15 matches per file
            let lines = output.components(separatedBy: "\n")
            var fileGroups: [String: [String]] = [:]
            var fileOrder: [String] = []
            for line in lines {
                if let colonIdx = line.firstIndex(of: ":") {
                    let file = String(line[..<colonIdx])
                    if fileGroups[file] == nil {
                        fileGroups[file] = []
                        fileOrder.append(file)
                    }
                    if (fileGroups[file]?.count ?? 0) < 15 {
                        fileGroups[file]?.append(line)
                    }
                }
            }
            let compressed = fileOrder.flatMap { fileGroups[$0] ?? [] }.joined(separator: "\n")
            stats.savedTokens += max(0, tokens - estimateTokens(compressed))
            return compressed + "\n(results compressed: \(lines.count) → \(fileGroups.values.reduce(0) { $0 + $1.count }) lines)"
            
        case "list_directory_tree":
            // Allow up to 250 lines so full module trees remain visible
            let lines = output.components(separatedBy: "\n")
            let limit = 250
            let limited = Array(lines.prefix(limit))
            let result = limited.joined(separator: "\n") + (lines.count > limit ? "\n... (\(lines.count - limit) more entries)" : "")
            stats.savedTokens += max(0, tokens - estimateTokens(result))
            return result
            
        case "shell":
            // Preserve head, tail, AND any middle compiler/test error & warning lines with surrounding context
            let lines = output.components(separatedBy: "\n")
            if lines.count > 220 {
                let headCount = 50
                let tailCount = 90
                let head = Array(lines.prefix(headCount)).joined(separator: "\n")
                let tail = Array(lines.suffix(tailCount)).joined(separator: "\n")
                
                let middleStart = headCount
                let middleEnd = max(middleStart, lines.count - tailCount)
                var diagnosticIndices = Set<Int>()
                let errorPatterns = ["error:", "error[", "warning:", "failed", "fatal", "panic", "exception", "traceback", "undefined", "cannot find", "❌"]
                if middleStart < middleEnd {
                    for idx in middleStart..<middleEnd {
                        let lower = lines[idx].lowercased()
                        if errorPatterns.contains(where: { lower.contains($0) }) {
                            for ctx in max(middleStart, idx - 2)...min(middleEnd - 1, idx + 3) {
                                diagnosticIndices.insert(ctx)
                            }
                        }
                    }
                }
                
                var middleDiagnostics = ""
                if !diagnosticIndices.isEmpty {
                    let sortedIndices = diagnosticIndices.sorted().prefix(120)
                    let extracted = sortedIndices.map { "L\($0 + 1): \(lines[$0])" }.joined(separator: "\n")
                    middleDiagnostics = "\n\n--- [Extracted Diagnostics from lines \(middleStart + 1)-\(middleEnd)] ---\n\(extracted)\n"
                }
                
                let omittedCount = max(0, (middleEnd - middleStart) - diagnosticIndices.count)
                let result = head + middleDiagnostics + "\n\n... (\(omittedCount) non-diagnostic lines omitted) ...\n\n" + tail
                stats.savedTokens += max(0, tokens - estimateTokens(result))
                return result
            }
            let maxChars = max(16_000, budget * 4)
            return output.count > maxChars ? String(output.prefix(maxChars)) : output
            
        default:
            // Generic truncation with generous head + tail strategy
            let maxChars = max(16_000, budget * 4)
            if output.count > maxChars {
                let headChars = (maxChars * 2) / 3
                let tailChars = maxChars / 3
                let result = String(output.prefix(headChars)) + "\n\n... (truncated \(output.count - maxChars) chars) ...\n\n" + String(output.suffix(tailChars))
                stats.savedTokens += max(0, tokens - estimateTokens(result))
                return result
            }
            return output
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
            "joke", "story", "fun", "interesting", "cool",
            "ไหน", "เป็นไง", "ทำไม", "ยังไง", "ไม่ได้", "ใช้ได้ไหม", "ตอบหน่อย", "คุยหน่อย"
        ]
        let isChat = chatIndicators.contains(where: { lower.contains($0) }) &&
            !lower.contains("code") && !lower.contains("file") && !lower.contains("project") &&
            !lower.contains("build") && !lower.contains("fix") && !lower.contains("create") &&
            !lower.contains("แก้") && !lower.contains("สร้าง") && !lower.contains("รัน")
        
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
        
        // Preserve head and tail cleanly without mangling grammar via aggressive word deletion
        let ratio = Double(targetTokens) / Double(max(1, currentTokens))
        let targetChars = max(500, Int(Double(text.count) * ratio))
        if text.count > targetChars {
            let headChars = (targetChars * 2) / 3
            let tailChars = targetChars / 3
            return String(text.prefix(headChars)) + "\n... (compressed) ...\n" + String(text.suffix(tailChars))
        }
        return text
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
    
    // MARK: - Reset Stats & Session Deduplication Registry
    
    func resetStats() {
        stats = TokenUsageStats()
        fileReadRegistry.removeAll()
        persistStats()
    }
    
    /// Called at the start of each new user prompt turn so intra-loop re-reads of unchanged files are deduplicated
    func beginTurnLoop() {
        fileReadRegistry.removeAll()
    }
    
    /// Invalidates cached file-read fingerprints whenever a file is modified on disk
    func invalidateFileRead(path: String) {
        let stdPath = (path as NSString).standardizingPath
        fileReadRegistry = fileReadRegistry.filter { !$0.key.hasPrefix(stdPath + "#") }
    }
    
    /// Checks if the exact file slice was already read in the current agent loop with identical content hash.
    /// Returns a compact reference stub if unchanged, saving thousands of redundant tokens.
    func checkDuplicateFileRead(
        path: String,
        startLine: Int?,
        endLine: Int?,
        contentHash: Int,
        lineCount: Int,
        fullTokenEstimate: Int
    ) -> String? {
        guard mode != .maxRecall, fullTokenEstimate > 120 else { return nil }
        let stdPath = (path as NSString).standardizingPath
        let sliceKey = "\(stdPath)#\(startLine ?? 1)-\(endLine ?? lineCount)"
        
        if var existing = fileReadRegistry[sliceKey], existing.contentHash == contentHash {
            existing.hitCount += 1
            fileReadRegistry[sliceKey] = existing
            let stub = "[TokenMem File Cache Hit: \((stdPath as NSString).lastPathComponent) (lines \(startLine ?? 1)-\(endLine ?? lineCount), \(lineCount) total lines) is unchanged since earlier read in this run. Refer to the file content already in context above.]"
            let saved = max(0, fullTokenEstimate - estimateTokens(stub))
            stats.savedTokens += saved
            stats.savedByFileReadDedup += saved
            updateCompressionRatio()
            persistStats()
            return stub
        }
        
        fileReadRegistry[sliceKey] = FileReadCacheEntry(
            contentHash: contentHash,
            lineCount: lineCount,
            timestamp: Date(),
            hitCount: 0
        )
        return nil
    }
    
    /// Records token savings from AST skeleton windowing or tool output folding
    func recordToolFoldingSavings(savedTokens: Int) {
        guard savedTokens > 0 else { return }
        stats.savedTokens += savedTokens
        stats.savedByToolFolding += savedTokens
        updateCompressionRatio()
        persistStats()
    }
    
    /// Records token savings from deduplicating MCP schemas and adaptive ToolScope pruning
    func recordSchemaOptimization(totalSchemasCount: Int, activeSchemasCount: Int) {
        let prunedCount = max(0, totalSchemasCount - activeSchemasCount)
        guard prunedCount > 0 else { return }
        // Each tool schema averages ~145 tokens across JSON schema declarations
        let saved = prunedCount * 145
        stats.savedTokens += saved
        stats.savedBySchemaDedup += saved
        updateCompressionRatio()
        persistStats()
    }

    func recordUsage(provider: String, model: String, inputTokens: Int, outputTokens: Int, costOverride: Double? = nil) {
        stats.inputTokens += max(0, inputTokens)
        stats.outputTokens += max(0, outputTokens)
        stats.totalRequests += 1
        stats.totalCost += costOverride ?? estimateCost(inputTokens: inputTokens, outputTokens: outputTokens, model: model)
        updateCompressionRatio()
        stats.activeProvider = provider
        stats.activeModel = model
        persistStats()
    }

    func recordContextCache(hit: Bool, tokens: Int) {
        if hit && tokens > 0 {
            stats.cacheHits += 1
            stats.cachedTokens += max(0, tokens)
        } else {
            stats.cacheMisses += 1
        }
        updateCompressionRatio()
        persistStats()
    }
    
    private func updateCompressionRatio() {
        let totalSavedAndCached = stats.savedTokens + stats.cachedTokens
        let baseline = max(1, stats.inputTokens + stats.savedTokens)
        stats.compressionRatio = min(0.99, Double(totalSavedAndCached) / Double(baseline))
    }

    private func persistStats() {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        UserDefaults.standard.set(data, forKey: statsKey)
    }
    
    // MARK: - Cache-Aligned Epoch Context Compaction for Agent Loops
    
    /// Compresses tool history dynamically during long-running multi-turn loops.
    /// Uses Cache-Aligned Epoch Compaction (quantized in blocks of 6 messages) so earlier
    /// compacted messages stay 100% byte-identical across consecutive turns, preserving
    /// provider KV-prefix caches (Anthropic, OpenAI, Gemini, DeepSeek).
    func compressIterativeToolHistory(
        _ history: [(role: String, content: String)],
        budget: Int = 120_000
    ) -> [(role: String, content: String)] {
        guard history.count > 8 else { return history }
        
        let scaledBudget = Int(Double(budget) * mode.iterativeBudgetMultiplier)
        let effectiveBudget = max(40_000, min(scaledBudget, 200_000))
        let totalTokens = history.reduce(0) { $0 + estimateTokens($1.content) }
        if totalTokens <= effectiveBudget { return history }
        
        var optimized: [(role: String, content: String)] = []
        
        // 1. Keep the first user prompt intact (the primary goal)
        if let first = history.first {
            optimized.append(first)
        }
        
        // 2. Cache-Aligned Epoch Tail: Quantize the uncompacted recent tail in blocks of 6 messages
        // so the boundary between compacted middle turns and verbatim recent turns only advances every 6 messages!
        let remainingCount = history.count - 1
        let epochAlignedRecentCount = min(remainingCount, 6 + (remainingCount % 6))
        let middleTurns = history.dropFirst().dropLast(epochAlignedRecentCount)
        let recentTurns = history.suffix(epochAlignedRecentCount)
        
        // 3. Compact older middle turns deterministically while keeping file headers, errors, and code excerpts
        for item in middleTurns {
            if item.content.contains(AIStructuredTurnCodec.markerKey) {
                if item.role == "user" {
                    let compacted = AIStructuredTurnCodec.compactToolOutputsIfNeeded(item.content, maxCharsPerOutput: 3_500)
                    optimized.append((role: "user", content: compacted))
                } else if item.role == "assistant",
                          case .assistantToolCalls(let text, let toolCalls) = AIStructuredTurnCodec.decode(item.content),
                          text.count > 1_500 {
                    let trimmedText = String(text.prefix(1_500)) + "... [earlier response compacted]"
                    let reencoded = AIStructuredTurnCodec.encodeAssistantTurn(text: trimmedText, toolCalls: toolCalls)
                    optimized.append((role: "assistant", content: reencoded))
                } else {
                    optimized.append(item)
                }
            } else if item.role == "user" && item.content.contains("Tool execution results:") {
                if item.content.count > 4_000 {
                    let head = String(item.content.prefix(2_500))
                    let tail = String(item.content.suffix(1_000))
                    let summaryContent = head + "\n... [Earlier tool output compacted] ...\n" + tail
                    optimized.append((role: "user", content: summaryContent))
                } else {
                    optimized.append(item)
                }
            } else if item.role == "assistant" {
                if item.content.count > 1_500 {
                    let trimmed = item.content.prefix(1_500)
                    optimized.append((role: "assistant", content: String(trimmed) + "... [earlier response compacted]"))
                } else {
                    optimized.append(item)
                }
            } else {
                optimized.append(item)
            }
        }
        
        // 4. Append recent turns with 100% verbatim fidelity
        for recent in recentTurns {
            optimized.append(recent)
        }
        
        let finalTokens = optimized.reduce(0) { $0 + estimateTokens($1.content) }
        let saved = max(0, totalTokens - finalTokens)
        stats.savedTokens += saved
        stats.savedByEpochCompaction += saved
        updateCompressionRatio()
        persistStats()
        return optimized
    }

    nonisolated func estimateCost(inputTokens: Int, outputTokens: Int, model: String) -> Double {
        // Approximate pricing per 1M tokens (input/output)
        let pricing: (input: Double, output: Double) = {
            switch model {
            case _ where model.contains("gpt-4o"):
                return (2.50, 10.0)
            case _ where model.contains("gpt-4o-mini"):
                return (0.15, 0.60)
            case _ where model.contains("claude-3-7-sonnet") || model.contains("claude-3-5-sonnet"):
                return (3.0, 15.0)
            case _ where model.contains("claude-3-5-haiku"):
                return (0.80, 4.00)
            case _ where model.contains("gemini-2.5-pro") || model.contains("gemini-1.5-pro") || model.contains("gemini-2.0-pro"):
                return (1.25, 5.0)
            case _ where model.contains("gemini"):
                return (0.10, 0.40)
            case _ where model.contains("deepseek-r1") || model.contains("deepseek-reasoner"):
                return (0.55, 2.19)
            case _ where model.contains("deepseek"):
                return (0.14, 0.28)
            case _ where model.contains("qwen"):
                return (0.80, 3.20)
            default:
                return (0.50, 2.00) // Realistic default
            }
        }()
        
        return (Double(inputTokens) / 1_000_000 * pricing.input) +
               (Double(outputTokens) / 1_000_000 * pricing.output)
    }
}
