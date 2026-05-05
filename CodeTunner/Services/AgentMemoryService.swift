//
//  AgentMemoryService.swift
//  CodeTunner
//
//  Advanced AI Agent Memory — Persistent semantic memory with:
//  - 512-dim embeddings with n-gram features
//  - Topic clustering for grouping related memories
//  - Time-decay weighted relevance scoring
//  - Cross-chat context retrieval
//  - Conversation summarization for old chats
//  - Token-efficient memory recall
//

import Foundation

// MARK: - Memory Entry

struct MemoryEntry: Codable, Identifiable {
    let id: String
    let content: String
    let embedding: [Float]
    let timestamp: Date
    let chatId: String
    let role: String  // "user" or "assistant"
    let topic: String?
    let importance: Float  // 0.0 - 1.0
    let keywords: [String]
    
    init(content: String, chatId: String, role: String, topic: String? = nil, importance: Float = 0.5) {
        self.id = UUID().uuidString
        self.content = content
        self.embedding = AgentMemoryService.textToEmbedding(content)
        self.timestamp = Date()
        self.chatId = chatId
        self.role = role
        self.topic = topic ?? AgentMemoryService.detectTopic(content)
        self.importance = importance
        self.keywords = AgentMemoryService.extractKeywords(content)
    }
}

// MARK: - Conversation Summary

struct ConversationSummary: Codable, Identifiable {
    let id: String
    let chatId: String
    let summary: String
    let topics: [String]
    let keyDecisions: [String]
    let filesDiscussed: [String]
    let createdAt: Date
    let messageCount: Int
}

// MARK: - Topic Cluster

struct TopicCluster: Codable, Identifiable {
    let id: String
    var topic: String
    var memoryIds: [String]
    var centroid: [Float]
    var lastUpdated: Date
    var frequency: Int
}

// MARK: - Agent Memory Service

@MainActor
class AgentMemoryService: ObservableObject {
    static let shared = AgentMemoryService()
    
    @Published private(set) var memories: [MemoryEntry] = []
    @Published private(set) var summaries: [ConversationSummary] = []
    @Published private(set) var topicClusters: [TopicCluster] = []
    @Published private(set) var isLoaded = false
    
    private let embeddingDim = 512
    private let maxMemories = 2000
    private let maxSummaries = 100
    private let similarityThreshold: Float = 0.12
    private let decayHalfLifeDays: Double = 7.0  // Memory relevance halves every 7 days
    
    // N-gram configuration
    private let bigramWeight: Float = 1.5
    private let trigramWeight: Float = 2.0
    
    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("MicroCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("agent_memory_v2.json")
    }
    
    private var summaryStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("MicroCode", isDirectory: true)
        return appDir.appendingPathComponent("agent_summaries.json")
    }
    
    init() {
        loadMemories()
        loadSummaries()
    }
    
    // MARK: - Store Memory
    
    func storeMemory(content: String, chatId: String, role: String) {
        guard content.trimmingCharacters(in: .whitespacesAndNewlines).count > 10 else { return }
        
        // Calculate importance based on content
        let importance = calculateImportance(content, role: role)
        let entry = MemoryEntry(content: content, chatId: chatId, role: role, importance: importance)
        
        // Deduplicate: check if highly similar memory already exists
        let embedding = entry.embedding
        let isDuplicate = memories.suffix(20).contains { existing in
            Self.cosineSimilarity(existing.embedding, embedding) > 0.85
        }
        
        guard !isDuplicate else { return }
        
        memories.append(entry)
        
        // Update topic clusters
        updateTopicClusters(entry)
        
        // Prune if exceeding max
        if memories.count > maxMemories {
            pruneMemories()
        }
        
        Task.detached { [weak self] in
            await self?.saveMemories()
        }
    }
    
    // MARK: - Recall Memories (Advanced)
    
    func recallMemories(query: String, limit: Int = 5, excludeChatId: String? = nil, includeCurrentChat: Bool = true) -> [MemoryEntry] {
        guard !memories.isEmpty else { return [] }
        
        let queryEmbedding = Self.textToEmbedding(query)
        let queryKeywords = Set(Self.extractKeywords(query))
        let now = Date()
        
        var scored: [(MemoryEntry, Float)] = memories.compactMap { entry in
            if let excludeId = excludeChatId, entry.chatId == excludeId && !includeCurrentChat {
                return nil
            }
            
            // 1. Semantic similarity (cosine)
            let semanticScore = Self.cosineSimilarity(queryEmbedding, entry.embedding)
            
            // 2. Keyword overlap boost
            let entryKeywords = Set(entry.keywords)
            let keywordOverlap = Float(queryKeywords.intersection(entryKeywords).count) / max(1, Float(queryKeywords.count))
            
            // 3. Time decay factor
            let daysSince = max(0, now.timeIntervalSince(entry.timestamp) / 86400.0)
            let decayFactor = Float(pow(0.5, daysSince / decayHalfLifeDays))
            
            // 4. Importance weight
            let importanceWeight = entry.importance
            
            // Combined score: semantic (40%) + keywords (25%) + decay (20%) + importance (15%)
            let combinedScore = semanticScore * 0.40 +
                                keywordOverlap * 0.25 +
                                decayFactor * 0.20 +
                                importanceWeight * 0.15
            
            return combinedScore > similarityThreshold ? (entry, combinedScore) : nil
        }
        
        scored.sort { $0.1 > $1.1 }
        return Array(scored.prefix(limit).map { $0.0 })
    }
    
    // MARK: - Cross-Chat Recall
    
    /// Recall memories from OTHER chats that might be relevant
    func recallCrossChatMemories(query: String, currentChatId: String, limit: Int = 3) -> [MemoryEntry] {
        return recallMemories(query: query, limit: limit, excludeChatId: currentChatId, includeCurrentChat: false)
    }
    
    /// Format memories for LLM context (token-efficient)
    func formatMemoriesForContext(_ memories: [MemoryEntry], maxTokens: Int = 1500) -> String {
        guard !memories.isEmpty else { return "" }
        
        var context = "Recalled context from memory:\n"
        var tokenCount = 10 // Header tokens
        
        for (i, memory) in memories.enumerated() {
            let role = memory.role == "user" ? "User" : "AI"
            let dateStr = formatRelativeDate(memory.timestamp)
            let topicStr = memory.topic.map { " [\($0)]" } ?? ""
            
            // Truncate content to save tokens
            let maxContentLen = maxTokens * 3 / max(1, memories.count) // Divide budget equally
            let truncatedContent = memory.content.count > maxContentLen
                ? String(memory.content.prefix(maxContentLen)) + "..."
                : memory.content
            
            let entry = "\n[\(i + 1)] (\(dateStr))\(topicStr) \(role): \(truncatedContent)"
            let entryTokens = entry.count / 4 // Rough estimate
            
            if tokenCount + entryTokens > maxTokens { break }
            context += entry
            tokenCount += entryTokens
        }
        
        return context
    }
    
    // MARK: - Conversation Summarization
    
    func summarizeChat(chatId: String, messages: [(role: String, content: String)]) {
        guard messages.count > 4 else { return }
        
        // Extract key information
        var topics = Set<String>()
        var decisions: [String] = []
        var files: [String] = []
        
        for msg in messages {
            // Detect topics
            if let topic = Self.detectTopic(msg.content) {
                topics.insert(topic)
            }
            
            // Detect file paths
            let filePattern = try? NSRegularExpression(pattern: #"[\w/]+\.\w{1,10}"#)
            let range = NSRange(msg.content.startIndex..., in: msg.content)
            filePattern?.enumerateMatches(in: msg.content, range: range) { match, _, _ in
                if let matchRange = match?.range, let r = Range(matchRange, in: msg.content) {
                    files.append(String(msg.content[r]))
                }
            }
            
            // Detect decisions (messages with action words)
            let actionWords = ["created", "fixed", "implemented", "added", "removed", "changed", "deployed", "configured"]
            if msg.role == "assistant" && actionWords.contains(where: { msg.content.lowercased().contains($0) }) {
                let firstSentence = msg.content.components(separatedBy: ".").first ?? msg.content
                if firstSentence.count < 200 {
                    decisions.append(firstSentence.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        
        // Build summary
        let summaryText = buildSummary(messages)
        
        let summary = ConversationSummary(
            id: UUID().uuidString,
            chatId: chatId,
            summary: summaryText,
            topics: Array(topics),
            keyDecisions: Array(decisions.prefix(5)),
            filesDiscussed: Array(Set(files)).sorted(),
            createdAt: Date(),
            messageCount: messages.count
        )
        
        summaries.append(summary)
        
        // Prune old summaries
        if summaries.count > maxSummaries {
            summaries.removeFirst(summaries.count - maxSummaries)
        }
        
        Task.detached { [weak self] in
            await self?.saveSummaries()
        }
    }
    
    // MARK: - Topic Detection
    
    nonisolated static func detectTopic(_ text: String) -> String? {
        let lower = text.lowercased()
        
        let topicMap: [(keywords: [String], topic: String)] = [
            (["swift", "swiftui", "uikit", "xcode", "ios", "macos"], "Swift/Apple"),
            (["rust", "cargo", "tokio", "async-std", "serde"], "Rust"),
            (["python", "pip", "django", "flask", "numpy", "pandas"], "Python"),
            (["javascript", "typescript", "node", "react", "vue", "angular", "npm"], "JavaScript/TypeScript"),
            (["html", "css", "tailwind", "sass", "scss", "frontend", "web"], "Web/Frontend"),
            (["docker", "kubernetes", "deploy", "ci/cd", "github actions", "aws", "gcp"], "DevOps"),
            (["database", "sql", "postgres", "mysql", "mongodb", "redis", "sqlite"], "Database"),
            (["api", "rest", "graphql", "endpoint", "http", "websocket"], "API"),
            (["git", "commit", "branch", "merge", "pull request"], "Git"),
            (["test", "unittest", "pytest", "jest", "spec", "coverage"], "Testing"),
            (["bug", "fix", "error", "crash", "debug", "issue"], "Debugging"),
            (["design", "ui", "ux", "layout", "component", "animation"], "UI/Design"),
            (["auth", "login", "session", "token", "jwt", "oauth"], "Authentication"),
            (["performance", "optimize", "memory", "cpu", "cache", "speed"], "Performance"),
        ]
        
        var bestTopic: String? = nil
        var bestScore = 0
        
        for (keywords, topic) in topicMap {
            let score = keywords.filter { lower.contains($0) }.count
            if score > bestScore {
                bestScore = score
                bestTopic = topic
            }
        }
        
        return bestScore > 0 ? bestTopic : nil
    }
    
    // MARK: - Keyword Extraction
    
    nonisolated static func extractKeywords(_ text: String, limit: Int = 10) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "shall",
            "should", "may", "might", "must", "can", "could", "to", "of", "in",
            "for", "on", "with", "at", "by", "from", "that", "this", "it", "its",
            "but", "or", "not", "so", "very", "just", "also", "then", "than",
            "i", "me", "my", "you", "your", "we", "our", "they", "them", "he",
            "she", "him", "her", "his", "and", "the", "if", "as", "up", "out"
        ]
        
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
        
        // Count word frequencies
        var counts: [String: Int] = [:]
        for word in words { counts[word, default: 0] += 1 }
        
        // Sort by frequency and return top keywords
        return counts.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }
    
    // MARK: - Embedding Generation (512-dim with n-grams)
    
    nonisolated static func textToEmbedding(_ text: String) -> [Float] {
        let dim = 512
        var embedding = [Float](repeating: 0.0, count: dim)
        
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
        
        guard !words.isEmpty else { return embedding }
        
        // Unigram features (first 256 dims)
        let wordCounts = Dictionary(grouping: words, by: { $0 }).mapValues { Float($0.count) }
        for (word, count) in wordCounts {
            let hash = simpleHash(word)
            let idx = Int(hash % UInt64(256))
            let weight = log(1.0 + count)
            embedding[idx] += weight
        }
        
        // Bigram features (dims 256-383)
        if words.count > 1 {
            for i in 0..<(words.count - 1) {
                let bigram = "\(words[i])_\(words[i+1])"
                let hash = simpleHash(bigram)
                let idx = 256 + Int(hash % 128)
                embedding[idx] += 1.5  // Bigram weight
            }
        }
        
        // Trigram features (dims 384-511)
        if words.count > 2 {
            for i in 0..<(words.count - 2) {
                let trigram = "\(words[i])_\(words[i+1])_\(words[i+2])"
                let hash = simpleHash(trigram)
                let idx = 384 + Int(hash % 128)
                embedding[idx] += 2.0  // Trigram weight
            }
        }
        
        // L2 normalize
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            embedding = embedding.map { $0 / norm }
        }
        
        return embedding
    }
    
    /// Simple string hash (DJB2)
    nonisolated private static func simpleHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 5381
        for char in text.unicodeScalars {
            hash = hash &* 33 &+ UInt64(char.value)
        }
        return hash
    }
    
    /// Cosine similarity between two vectors
    nonisolated static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dot / denominator : 0
    }
    
    // MARK: - Private Helpers
    
    private func calculateImportance(_ content: String, role: String) -> Float {
        var importance: Float = 0.5
        
        // Code-heavy content is more important
        if content.contains("```") || content.contains("func ") || content.contains("class ") {
            importance += 0.2
        }
        
        // Error/fix content is important
        let lower = content.lowercased()
        if lower.contains("error") || lower.contains("fix") || lower.contains("bug") {
            importance += 0.15
        }
        
        // Long, detailed responses are important
        if content.count > 500 { importance += 0.1 }
        
        // User instructions are important
        if role == "user" && (lower.contains("must") || lower.contains("always") || lower.contains("never")) {
            importance += 0.15
        }
        
        return min(1.0, importance)
    }
    
    private func updateTopicClusters(_ entry: MemoryEntry) {
        guard let topic = entry.topic else { return }
        
        if let idx = topicClusters.firstIndex(where: { $0.topic == topic }) {
            topicClusters[idx].memoryIds.append(entry.id)
            topicClusters[idx].frequency += 1
            topicClusters[idx].lastUpdated = Date()
            // Update centroid (running average)
            var centroid = topicClusters[idx].centroid
            let n = Float(topicClusters[idx].memoryIds.count)
            for i in 0..<min(centroid.count, entry.embedding.count) {
                centroid[i] = (centroid[i] * (n - 1) + entry.embedding[i]) / n
            }
            topicClusters[idx].centroid = centroid
        } else {
            let cluster = TopicCluster(
                id: UUID().uuidString,
                topic: topic,
                memoryIds: [entry.id],
                centroid: entry.embedding,
                lastUpdated: Date(),
                frequency: 1
            )
            topicClusters.append(cluster)
        }
    }
    
    private func pruneMemories() {
        // Remove lowest-importance, oldest memories
        let sorted = memories.sorted { a, b in
            let aScore = a.importance * Float(pow(0.5, Date().timeIntervalSince(a.timestamp) / (decayHalfLifeDays * 86400)))
            let bScore = b.importance * Float(pow(0.5, Date().timeIntervalSince(b.timestamp) / (decayHalfLifeDays * 86400)))
            return aScore > bScore
        }
        memories = Array(sorted.prefix(maxMemories))
    }
    
    private func buildSummary(_ messages: [(role: String, content: String)]) -> String {
        // Extractive summarization: pick key sentences
        var keyPoints: [String] = []
        
        for msg in messages {
            let sentences = msg.content
                .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count > 15 && $0.count < 200 }
            
            // Take first sentence that seems informative
            if let first = sentences.first {
                let role = msg.role == "user" ? "User asked" : "AI"
                keyPoints.append("\(role): \(first)")
            }
        }
        
        return keyPoints.prefix(8).joined(separator: ". ")
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604800 { return "\(Int(interval / 86400))d ago" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
    
    // MARK: - Persistence
    
    private func loadMemories() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            // Try loading from v1 format
            loadV1Memories()
            isLoaded = true
            return
        }
        
        do {
            let data = try Data(contentsOf: storageURL)
            memories = try JSONDecoder().decode([MemoryEntry].self, from: data)
            isLoaded = true
            print("[Memory] Loaded \(memories.count) memories (v2)")
        } catch {
            print("[Memory] Failed to load v2: \(error)")
            loadV1Memories()
            isLoaded = true
        }
    }
    
    private func loadV1Memories() {
        // Migration from v1 format
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let v1URL = appSupport.appendingPathComponent("MicroCode/agent_memory.json")
        
        guard FileManager.default.fileExists(atPath: v1URL.path) else { return }
        
        struct V1Entry: Codable {
            let id: String
            let content: String
            let embedding: [Float]
            let timestamp: Date
            let chatId: String
            let role: String
        }
        
        do {
            let data = try Data(contentsOf: v1URL)
            let v1Entries = try JSONDecoder().decode([V1Entry].self, from: data)
            
            // Convert to v2 format with re-computed embeddings
            for v1 in v1Entries {
                let entry = MemoryEntry(content: v1.content, chatId: v1.chatId, role: v1.role)
                memories.append(entry)
            }
            
            print("[Memory] Migrated \(v1Entries.count) v1 memories → v2")
            Task.detached { [weak self] in await self?.saveMemories() }
        } catch {
            print("[Memory] V1 migration failed: \(error)")
        }
    }
    
    private func saveMemories() async {
        do {
            let data = try JSONEncoder().encode(memories)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[Memory] Failed to save: \(error)")
        }
    }
    
    private func loadSummaries() {
        guard FileManager.default.fileExists(atPath: summaryStorageURL.path) else { return }
        do {
            let data = try Data(contentsOf: summaryStorageURL)
            summaries = try JSONDecoder().decode([ConversationSummary].self, from: data)
        } catch {
            print("[Memory] Failed to load summaries: \(error)")
        }
    }
    
    private func saveSummaries() async {
        do {
            let data = try JSONEncoder().encode(summaries)
            try data.write(to: summaryStorageURL, options: .atomic)
        } catch {
            print("[Memory] Failed to save summaries: \(error)")
        }
    }
    
    // MARK: - Clear / Stats
    
    func clearAllMemories() {
        memories.removeAll()
        summaries.removeAll()
        topicClusters.removeAll()
        try? FileManager.default.removeItem(at: storageURL)
        try? FileManager.default.removeItem(at: summaryStorageURL)
    }
    
    var stats: String {
        let totalChars = memories.reduce(0) { $0 + $1.content.count }
        let topics = Set(memories.compactMap { $0.topic }).sorted()
        return "Memories: \(memories.count) | Topics: \(topics.count) | Chars: \(totalChars) | Summaries: \(summaries.count)"
    }
    
    var topTopics: [(topic: String, count: Int)] {
        topicClusters
            .sorted { $0.frequency > $1.frequency }
            .prefix(5)
            .map { (topic: $0.topic, count: $0.frequency) }
    }
}
