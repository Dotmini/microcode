import Foundation

/// Persistent, append-only JSONL trace of agent tool calls (`~/Library/Logs/MicroCode/agent-tool-trace.jsonl`).
/// Tool history used to live only in memory (last 300 calls), so "what did the agent run?" was lost on quit.
/// Arguments and errors pass through the secret redactor; large values are truncated; the file rotates at a size cap.
final class AgentToolTrace: @unchecked Sendable {
    static let shared = AgentToolTrace(
        directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MicroCode", isDirectory: true),
        redact: { AgentPrivacyGuard.sanitize($0) }
    )

    let fileURL: URL
    private let maxBytes: Int
    private let redact: (String) -> String
    private let queue = DispatchQueue(label: "microcode.agent.tool-trace", qos: .utility)

    init(directory: URL, maxBytes: Int = 10_000_000, redact: @escaping (String) -> String = { $0 }) {
        self.fileURL = directory.appendingPathComponent("agent-tool-trace.jsonl")
        self.maxBytes = maxBytes
        self.redact = redact
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func entry(
        tool: String,
        arguments: [String: Any],
        success: Bool,
        durationMs: Int,
        error: String?,
        workspace: String?,
        chatId: String?,
        subAgentDepth: Int,
        redact: (String) -> String,
        date: Date = Date()
    ) -> [String: Any] {
        func clip(_ text: String, _ limit: Int) -> String {
            let clean = redact(text)
            return clean.count > limit ? String(clean.prefix(limit)) + "…" : clean
        }
        var args: [String: String] = [:]
        for (key, value) in arguments where !key.hasPrefix("__") {
            args[key] = clip("\(value)", 500)
        }
        var record: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: date),
            "tool": tool,
            "ok": success,
            "ms": durationMs,
            "args": args,
            "depth": subAgentDepth
        ]
        if let error { record["error"] = clip(error, 1_000) }
        if let workspace { record["workspace"] = workspace }
        if let chatId { record["chat"] = chatId }
        return record
    }

    func record(tool: String, arguments: [String: Any], success: Bool, duration: TimeInterval, error: String?) {
        let entry = Self.entry(
            tool: tool,
            arguments: arguments,
            success: success,
            durationMs: Int(duration * 1000),
            error: error,
            workspace: AgentExecutionContext.workspaceRoot,
            chatId: AgentExecutionContext.chatId,
            subAgentDepth: SubAgentContext.depth,
            redact: redact
        )
        guard JSONSerialization.isValidJSONObject(entry),
              var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        queue.async { [fileURL, maxBytes] in
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber, size.intValue > maxBytes {
                let rotated = fileURL.appendingPathExtension("1")
                try? fm.removeItem(at: rotated)
                try? fm.moveItem(at: fileURL, to: rotated)
            }
            if !fm.fileExists(atPath: fileURL.path) {
                fm.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }

    /// Blocks until queued writes are on disk (tests / shutdown).
    func flush() {
        queue.sync {}
    }
}
