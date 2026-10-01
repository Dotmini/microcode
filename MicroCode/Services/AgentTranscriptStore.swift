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
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    private init() {}

    func bootstrap(_ chat: ChatSession, scope: AgentSessionScope) -> Int {
        if manifest(chatID: chat.id, scope: scope) == nil, !chat.messages.isEmpty {
            upsert(chat.messages, chatID: chat.id, scope: scope)
        }
        return manifest(chatID: chat.id, scope: scope)?.entries.count ?? chat.messages.count
    }

    @discardableResult
    func upsert(_ messages: [AgentMessageData], chatID: String, scope: AgentSessionScope) -> Int {
        guard !messages.isEmpty else { return manifest(chatID: chatID, scope: scope)?.entries.count ?? 0 }

        var current = manifest(chatID: chatID, scope: scope) ?? TranscriptManifest()
        var known = Dictionary(uniqueKeysWithValues: current.entries.map { ($0.id, $0) })

        for message in messages {
            guard let encoded = try? encoder.encode(message),
                  let data = try? AgentPrivacyGuard.sanitizeJSON(encoded) else { continue }
            let destination = messageURL(messageID: message.id, chatID: chatID, scope: scope)
            do {
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destination, options: .atomic)
                if known[message.id] == nil {
                    let entry = TranscriptManifest.Entry(id: message.id, timestamp: message.timestamp)
                    current.entries.append(entry)
                    known[message.id] = entry
                }
            } catch {
                // The UI remains usable if storage is temporarily unavailable.
                // Do not log message contents or paths from user workspaces.
                continue
            }
        }

        current.entries.sort {
            $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp
        }
        current.updatedAt = Date()
        saveManifest(current, chatID: chatID, scope: scope)
        return current.entries.count
    }

    func loadRecent(chatID: String, scope: AgentSessionScope, limit: Int) -> [AgentMessageData] {
        let entries = manifest(chatID: chatID, scope: scope)?.entries ?? []
        return load(entries: Array(entries.suffix(max(1, limit))), chatID: chatID, scope: scope)
    }

    func loadBefore(chatID: String, scope: AgentSessionScope, beforeMessageID: String, limit: Int) -> [AgentMessageData] {
        guard let entries = manifest(chatID: chatID, scope: scope)?.entries,
              let boundary = entries.firstIndex(where: { $0.id == beforeMessageID }) else { return [] }
        let start = max(0, boundary - max(1, limit))
        return load(entries: Array(entries[start..<boundary]), chatID: chatID, scope: scope)
    }

    func totalMessageCount(chatID: String, scope: AgentSessionScope) -> Int {
        manifest(chatID: chatID, scope: scope)?.entries.count ?? 0
    }

    func remove(chatID: String, scope: AgentSessionScope) {
        try? fileManager.removeItem(at: chatDirectory(chatID: chatID, scope: scope))
    }

    private func load(entries: [TranscriptManifest.Entry], chatID: String, scope: AgentSessionScope) -> [AgentMessageData] {
        entries.compactMap { entry in
            guard let data = try? Data(contentsOf: messageURL(messageID: entry.id, chatID: chatID, scope: scope)) else { return nil }
            return try? decoder.decode(AgentMessageData.self, from: data)
        }
    }

    private func manifest(chatID: String, scope: AgentSessionScope) -> TranscriptManifest? {
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
