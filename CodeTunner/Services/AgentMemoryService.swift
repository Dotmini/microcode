//
//  AgentMemoryService.swift
//  CodeTunner
//
//  AI Agent Memory - Persistent semantic memory using vector embeddings
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
    
    init(content: String, chatId: String, role: String) {
        self.id = UUID().uuidString
        self.content = content
        self.embedding = AgentMemoryService.textToEmbedding(content)
        self.timestamp = Date()
        self.chatId = chatId
        self.role = role
    }
}

// MARK: - Agent Memory Service

@MainActor
class AgentMemoryService: ObservableObject {
    static let shared = AgentMemoryService()
    
    @Published private(set) var memories: [MemoryEntry] = []
    @Published private(set) var isLoaded = false
    
    private let embeddingDim = 128
    private let maxMemories = 1000  // Limit total memories
    private let similarityThreshold: Float = 0.15  // Minimum similarity to recall
    
    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("MicroCode", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        
        return appDir.appendingPathComponent("agent_memory.json")
    }
    
    init() {
        loadMemories()
    }
    
    // MARK: - Store Memory
    
    /// Store a message as a memory entry
    func storeMemory(content: String, chatId: String, role: String) {
        // Don't store very short or empty content
        guard content.trimmingCharacters(in: .whitespacesAndNewlines).count > 10 else { return }
        
        let entry = MemoryEntry(content: content, chatId: chatId, role: role)
        memories.append(entry)
        
        // Prune if exceeding max
        if memories.count > maxMemories {
            memories.removeFirst(memories.count - maxMemories)
        }
        
        // Save asynchronously
        Task.detached { [weak self] in
            await self?.saveMemories()
        }
    }
    
    // MARK: - Recall Memories
    
    /// Recall relevant memories based on semantic similarity
    func recallMemories(query: String, limit: Int = 5, excludeChatId: String? = nil) -> [MemoryEntry] {
        guard !memories.isEmpty else { return [] }
        
        let queryEmbedding = Self.textToEmbedding(query)
        
        // Calculate similarities
        var scored: [(MemoryEntry, Float)] = memories.compactMap { entry in
            // Optionally exclude current chat
            if let excludeId = excludeChatId, entry.chatId == excludeId {
                return nil
            }
            
            let similarity = Self.cosineSimilarity(queryEmbedding, entry.embedding)
            return similarity > similarityThreshold ? (entry, similarity) : nil
        }
        
        // Sort by similarity descending
        scored.sort { $0.1 > $1.1 }
        
        // Take top results
        return Array(scored.prefix(limit).map { $0.0 })
    }
    
    /// Format memories for LLM context
    func formatMemoriesForContext(_ memories: [MemoryEntry]) -> String {
        guard !memories.isEmpty else { return "" }
        
        var context = "Relevant memories from previous conversations:\n"
        
        for (i, memory) in memories.enumerated() {
            let role = memory.role == "user" ? "User" : "Assistant"
            let dateStr = memory.timestamp.formatted(date: .abbreviated, time: .shortened)
            context += "\n[\(i + 1)] (\(dateStr)) \(role): \(memory.content.prefix(300))..."
        }
        
        return context
    }
    
    // MARK: - Embedding Generation
    
    /// Convert text to embedding vector (bag-of-words with TF-IDF-like weighting)
    nonisolated static func textToEmbedding(_ text: String) -> [Float] {
        let dim = 128
        var embedding = [Float](repeating: 0.0, count: dim)
        
        // Tokenize and process
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }  // Skip very short words
        
        // Weight by word importance
        let wordCounts = Dictionary(grouping: words, by: { $0 })
            .mapValues { Float($0.count) }
        
        for (word, count) in wordCounts {
            let hash = simpleHash(word)
            let idx = Int(hash % UInt64(dim))
            
            // TF-like weighting: log(1 + count)
            let weight = log(1.0 + count)
            embedding[idx] += weight
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
    
    // MARK: - Persistence
    
    private func loadMemories() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            isLoaded = true
            return
        }
        
        do {
            let data = try Data(contentsOf: storageURL)
            memories = try JSONDecoder().decode([MemoryEntry].self, from: data)
            isLoaded = true
            print("[Memory] Loaded \(memories.count) memories")
        } catch {
            print("[Memory] Failed to load: \(error)")
            isLoaded = true
        }
    }
    
    private func saveMemories() async {
        do {
            let data = try JSONEncoder().encode(memories)
            try data.write(to: storageURL, options: .atomic)
            print("[Memory] Saved \(memories.count) memories")
        } catch {
            print("[Memory] Failed to save: \(error)")
        }
    }
    
    /// Clear all memories
    func clearAllMemories() {
        memories.removeAll()
        try? FileManager.default.removeItem(at: storageURL)
    }
    
    /// Get memory statistics
    var stats: String {
        let totalChars = memories.reduce(0) { $0 + $1.content.count }
        return "Memories: \(memories.count), Total chars: \(totalChars)"
    }
}
