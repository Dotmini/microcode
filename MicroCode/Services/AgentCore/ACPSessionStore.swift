import Foundation

// Durable sessions for MicroCode's ACP agent (`--acp-server`): what `session/list`, `session/load`
// (with history replay), `session/resume`, `session/close` and `session/delete` operate on.
// Dependency-free so it is covered by Scripts/tests/run-phase2b-acp.sh.

struct ACPTranscriptEntry: Codable, Equatable {
    enum Role: String, Codable { case user, agent }
    let role: Role
    let text: String
}

struct ACPSessionRecord: Codable, Equatable {
    let sessionId: String
    var cwd: String
    var title: String?
    let createdAt: Date
    var updatedAt: Date
    var modeId: String
    var modelId: String?
    var transcript: [ACPTranscriptEntry]
}

final class ACPSessionStore {
    let directory: URL
    /// Applied to transcript text before it touches disk (the app passes its secret redactor).
    private let redact: (String) -> String
    private let fileManager = FileManager.default

    init(directory: URL, redact: @escaping (String) -> String = { $0 }) {
        self.directory = directory
        self.redact = redact
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("MicroCode/acp-sessions", isDirectory: true)
    }

    /// Session ids come from clients on load/resume/delete: only accept our own safe format as a file name.
    static func isValidSessionId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" }
    }

    private func fileURL(_ sessionId: String) -> URL? {
        guard Self.isValidSessionId(sessionId) else { return nil }
        return directory.appendingPathComponent("\(sessionId).json")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func save(_ record: ACPSessionRecord) {
        guard let url = fileURL(record.sessionId) else { return }
        var redacted = record
        redacted.transcript = record.transcript.map { ACPTranscriptEntry(role: $0.role, text: redact($0.text)) }
        guard let data = try? Self.encoder.encode(redacted) else { return }
        try? data.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func load(_ sessionId: String) -> ACPSessionRecord? {
        guard let url = fileURL(sessionId), let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(ACPSessionRecord.self, from: data)
    }

    func delete(_ sessionId: String) {
        guard let url = fileURL(sessionId) else { return }
        try? fileManager.removeItem(at: url)
    }

    /// `session/list`: newest first, optional exact `cwd` filter, opaque cursor = offset.
    func list(cwd: String?, cursor: String?, pageSize: Int = 50) -> (sessions: [ACPSessionRecord], nextCursor: String?) {
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var records = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(ACPSessionRecord.self, from: Data(contentsOf: $0)) }
        if let cwd { records = records.filter { $0.cwd == cwd } }
        records.sort { $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.sessionId < $1.sessionId }
        let offset = cursor.flatMap { Data(base64Encoded: $0) }.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
        guard offset >= 0, offset < records.count else { return ([], nil) }
        let end = min(records.count, offset + pageSize)
        let next = end < records.count ? Data(String(end).utf8).base64EncodedString() : nil
        return (Array(records[offset..<end]), next)
    }

    // MARK: - Wire formats

    /// `SessionInfo` for `session/list`.
    static func sessionInfo(_ record: ACPSessionRecord) -> [String: Any] {
        var info: [String: Any] = [
            "sessionId": record.sessionId,
            "cwd": record.cwd,
            "updatedAt": ISO8601DateFormatter().string(from: record.updatedAt)
        ]
        if let title = record.title { info["title"] = title }
        return info
    }

    /// `session/load` history replay: one `user_message_chunk` / `agent_message_chunk` per transcript entry.
    static func replayNotifications(_ record: ACPSessionRecord) -> [[String: Any]] {
        record.transcript.enumerated().map { index, entry in
            [
                "jsonrpc": "2.0",
                "method": "session/update",
                "params": [
                    "sessionId": record.sessionId,
                    "update": [
                        "sessionUpdate": entry.role == .user ? "user_message_chunk" : "agent_message_chunk",
                        "messageId": "\(record.sessionId)-\(index)",
                        "content": ["type": "text", "text": entry.text]
                    ] as [String: Any]
                ] as [String: Any]
            ]
        }
    }

    /// Title auto-generated from the first prompt (single line, bounded).
    static func title(fromPrompt prompt: String) -> String {
        let firstLine = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 80 ? String(trimmed.prefix(77)) + "…" : trimmed
    }
}
