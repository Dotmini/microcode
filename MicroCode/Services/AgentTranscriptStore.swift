//
//  AgentTranscriptStore.swift
//  MicroCode
//
//  Durable, disk-backed chat transcripts.  The active chat UI only retains a
//  small working window; the complete transcript remains available on disk.
//

import Foundation

struct TranscriptManifest: Codable {
    struct Entry: Codable, Hashable {
        let id: String
        let timestamp: Date
    }

    var version: Int = 1
    var entries: [Entry] = []
    var updatedAt: Date = Date()
}

/// A deliberately small local store rather than another server dependency.
/// Each message is addressable independently, so saving a new assistant reply
/// never needs to decode an entire historic task into memory.
final class AgentTranscriptStore {
    static let shared = AgentTranscriptStore()

    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.dotmini.microcode.transcript-io", qos: .utility)
    private let lock = NSLock()
    private var manifestCache: [String: TranscriptManifest] = [:]
    private var messageDigestCache: [String: Int] = [:]

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    private init() {}

    private func cacheKey(chatID: String, scope: AgentSessionScope) -> String {
        "\(scope.rawValue):\(chatID)"
    }

    private func messageDigest(_ message: AgentMessageData) -> Int {
        var hasher = Hasher()
        hasher.combine(message.id)
        hasher.combine(message.role)
        hasher.combine(message.content.count)
        hasher.combine(String(message.content.suffix(256)))
        hasher.combine(message.toolResults?.count ?? 0)
        return hasher.finalize()
    }

    func bootstrap(_ chat: ChatSession, scope: AgentSessionScope) -> Int {
        if cachedOrDiskManifest(chatID: chat.id, scope: scope) == nil, !chat.messages.isEmpty {
            return upsert(chat.messages, chatID: chat.id, scope: scope)
        }
        return cachedOrDiskManifest(chatID: chat.id, scope: scope)?.entries.count ?? chat.messages.count
    }

    @discardableResult
    func upsert(_ messages: [AgentMessageData], chatID: String, scope: AgentSessionScope) -> Int {
        let cKey = cacheKey(chatID: chatID, scope: scope)
        guard !messages.isEmpty else {
            return cachedOrDiskManifest(chatID: chatID, scope: scope)?.entries.count ?? 0
        }

        lock.lock()
        var current = manifestCache[cKey] ?? manifestFromDisk(chatID: chatID, scope: scope) ?? TranscriptManifest()
        var known = Dictionary(uniqueKeysWithValues: current.entries.map { ($0.id, $0) })
        var dirtyMessages: [AgentMessageData] = []
        var manifestChanged = false

        for message in messages {
            let mKey = "\(cKey):\(message.id)"
            let digest = messageDigest(message)
            if messageDigestCache[mKey] != digest || known[message.id] == nil {
                messageDigestCache[mKey] = digest
                dirtyMessages.append(message)
            }
            if let existing = known[message.id] {
                if existing.timestamp != message.timestamp {
                    let updated = TranscriptManifest.Entry(id: message.id, timestamp: message.timestamp)
                    known[message.id] = updated
                    if let idx = current.entries.firstIndex(where: { $0.id == message.id }) {
                        current.entries[idx] = updated
                    }
                    manifestChanged = true
                }
            } else {
                let entry = TranscriptManifest.Entry(id: message.id, timestamp: message.timestamp)
                current.entries.append(entry)
                known[message.id] = entry
                manifestChanged = true
            }
        }

        if manifestChanged || !dirtyMessages.isEmpty {
            current.entries.sort {
                if $0.id == "streaming" && $1.id != "streaming" { return false }
                if $1.id == "streaming" && $0.id != "streaming" { return true }
                return $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp
            }
            current.updatedAt = Date()
            manifestCache[cKey] = current
        }
        let snapshotManifest = current
        let totalCount = current.entries.count
        lock.unlock()

        guard !dirtyMessages.isEmpty || manifestChanged else {
            return totalCount
        }

        // Perform heavy JSON encoding, regex privacy sanitization, and atomic disk I/O
        // off the main thread so @MainActor UI interactions never stall or spin.
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            for message in dirtyMessages {
                guard let encoded = try? self.encoder.encode(message) else { continue }
                let data = (try? AgentPrivacyGuard.sanitizeJSON(encoded)) ?? encoded
                let destination = self.messageURL(messageID: message.id, chatID: chatID, scope: scope)
                do {
                    try self.fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: destination, options: .atomic)
                } catch {
                    continue
                }
            }
            self.saveManifest(snapshotManifest, chatID: chatID, scope: scope)
        }

        return totalCount
    }

    func loadRecent(chatID: String, scope: AgentSessionScope, limit: Int) -> [AgentMessageData] {
        ioQueue.sync {}
        let entries = cachedOrDiskManifest(chatID: chatID, scope: scope)?.entries ?? []
        return load(entries: Array(entries.suffix(max(1, limit))), chatID: chatID, scope: scope)
    }

    func loadBefore(chatID: String, scope: AgentSessionScope, beforeMessageID: String, limit: Int) -> [AgentMessageData] {
        ioQueue.sync {}
        guard let entries = cachedOrDiskManifest(chatID: chatID, scope: scope)?.entries,
              let boundary = entries.firstIndex(where: { $0.id == beforeMessageID }) else { return [] }
        let start = max(0, boundary - max(1, limit))
        return load(entries: Array(entries[start..<boundary]), chatID: chatID, scope: scope)
    }

    func totalMessageCount(chatID: String, scope: AgentSessionScope) -> Int {
        cachedOrDiskManifest(chatID: chatID, scope: scope)?.entries.count ?? 0
    }

    func remove(chatID: String, scope: AgentSessionScope) {
        let cKey = cacheKey(chatID: chatID, scope: scope)
        lock.lock()
        manifestCache.removeValue(forKey: cKey)
        lock.unlock()
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            try? self.fileManager.removeItem(at: self.chatDirectory(chatID: chatID, scope: scope))
        }
    }

    func deleteMessages(ids: [String], chatID: String, scope: AgentSessionScope) {
        guard !ids.isEmpty else { return }
        let cKey = cacheKey(chatID: chatID, scope: scope)
        let idSet = Set(ids)
        lock.lock()
        for id in idSet {
            messageDigestCache.removeValue(forKey: "\(cKey):\(id)")
        }
        var updatedManifest: TranscriptManifest?
        if var current = manifestCache[cKey] ?? manifestFromDisk(chatID: chatID, scope: scope) {
            current.entries.removeAll { idSet.contains($0.id) }
            current.updatedAt = Date()
            manifestCache[cKey] = current
            updatedManifest = current
        }
        lock.unlock()

        ioQueue.async { [weak self] in
            guard let self = self else { return }
            for id in idSet {
                try? self.fileManager.removeItem(at: self.messageURL(messageID: id, chatID: chatID, scope: scope))
            }
            if let manifest = updatedManifest {
                self.saveManifest(manifest, chatID: chatID, scope: scope)
            }
        }
    }

    private func load(entries: [TranscriptManifest.Entry], chatID: String, scope: AgentSessionScope) -> [AgentMessageData] {
        entries.compactMap { entry in
            guard let data = try? Data(contentsOf: messageURL(messageID: entry.id, chatID: chatID, scope: scope)) else { return nil }
            return try? decoder.decode(AgentMessageData.self, from: data)
        }
    }

    private func cachedOrDiskManifest(chatID: String, scope: AgentSessionScope) -> TranscriptManifest? {
        let cKey = cacheKey(chatID: chatID, scope: scope)
        lock.lock()
        if let cached = manifestCache[cKey] {
            lock.unlock()
            return cached
        }
        let disk = manifestFromDisk(chatID: chatID, scope: scope)
        if let disk = disk {
            manifestCache[cKey] = disk
        }
        lock.unlock()
        return disk
    }

    private func manifestFromDisk(chatID: String, scope: AgentSessionScope) -> TranscriptManifest? {
        let url = chatDirectory(chatID: chatID, scope: scope).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(TranscriptManifest.self, from: data)
    }

    private func saveManifest(_ manifest: TranscriptManifest, chatID: String, scope: AgentSessionScope) {
        let url = chatDirectory(chatID: chatID, scope: scope).appendingPathComponent("manifest.json")
        guard let data = try? encoder.encode(manifest) else { return }
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    private func chatDirectory(chatID: String, scope: AgentSessionScope) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return appSupport
            .appendingPathComponent("MicroCode", isDirectory: true)
            .appendingPathComponent("ChatTranscripts", isDirectory: true)
            .appendingPathComponent(scope.rawValue, isDirectory: true)
            .appendingPathComponent(safeFileComponent(chatID), isDirectory: true)
    }

    private func messageURL(messageID: String, chatID: String, scope: AgentSessionScope) -> URL {
        chatDirectory(chatID: chatID, scope: scope)
            .appendingPathComponent("messages", isDirectory: true)
            .appendingPathComponent("\(safeFileComponent(messageID)).json")
    }

    private func safeFileComponent(_ value: String) -> String {
        value.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? Character($0) : "_" }.map(String.init).joined()
    }
}
