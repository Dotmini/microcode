import Foundation

// Phase 2b-2: ACP v1 session lifecycle (list / load replay / resume / close / delete), usage_update,
// session_info_update. Compiled with the real ACPProtocol.swift and ACPSessionStore.swift.

@main struct Phase2bACPRegression {
    static func main() throws {
        try sessionStore()
        replayAndTitle()
        clientParsing()
        capabilities()
        print("PHASE2B ACP REGRESSION: PASS")
    }

    static func record(_ id: String, cwd: String, minutesAgo: Double, transcript: [ACPTranscriptEntry] = []) -> ACPSessionRecord {
        let t = Date(timeIntervalSinceNow: -minutesAgo * 60)
        return ACPSessionRecord(sessionId: id, cwd: cwd, title: "t-\(id)", createdAt: t, updatedAt: t,
                                modeId: "agent", modelId: nil, transcript: transcript)
    }

    static func sessionStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("acp-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ACPSessionStore(directory: dir, redact: { $0.replacingOccurrences(of: "sk-SECRET", with: "[REDACTED]") })

        store.save(record("sess_a", cwd: "/w/one", minutesAgo: 30, transcript: [.init(role: .user, text: "key sk-SECRET")]))
        store.save(record("sess_b", cwd: "/w/one", minutesAgo: 1))
        store.save(record("sess_c", cwd: "/w/two", minutesAgo: 10))

        // Round trip + redaction on disk.
        let loaded = store.load("sess_a")
        precondition(loaded?.transcript.first?.text == "key [REDACTED]", "transcripts must be redacted before persisting")
        let raw = try String(contentsOf: dir.appendingPathComponent("sess_a.json"), encoding: .utf8)
        precondition(!raw.contains("sk-SECRET"))
        let perms = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("sess_a.json").path)[.posixPermissions] as? Int
        precondition(perms == 0o600, "session files must be owner-only")

        // Newest first, cwd filter, opaque cursor pagination.
        precondition(store.list(cwd: nil, cursor: nil).sessions.map(\.sessionId) == ["sess_b", "sess_c", "sess_a"])
        precondition(store.list(cwd: "/w/one", cursor: nil).sessions.map(\.sessionId) == ["sess_b", "sess_a"])
        let first = store.list(cwd: nil, cursor: nil, pageSize: 2)
        precondition(first.sessions.count == 2 && first.nextCursor != nil)
        let second = store.list(cwd: nil, cursor: first.nextCursor, pageSize: 2)
        precondition(second.sessions.map(\.sessionId) == ["sess_a"] && second.nextCursor == nil)
        precondition(store.list(cwd: nil, cursor: "garbage").sessions.count == 3, "unknown cursor starts from the top")

        // Client-supplied ids never escape the store directory.
        precondition(!ACPSessionStore.isValidSessionId("../../etc/passwd"))
        precondition(!ACPSessionStore.isValidSessionId("a/b"))
        precondition(store.load("../sess_a") == nil)
        store.delete("../sess_a")
        precondition(store.load("sess_a") != nil)

        store.delete("sess_a")
        precondition(store.load("sess_a") == nil)
        store.delete("sess_missing") // idempotent

        let info = ACPSessionStore.sessionInfo(record("sess_x", cwd: "/w", minutesAgo: 0))
        precondition(info["sessionId"] as? String == "sess_x" && info["cwd"] as? String == "/w" && info["updatedAt"] is String)
    }

    static func replayAndTitle() {
        let rec = record("sess_r", cwd: "/w", minutesAgo: 0, transcript: [
            .init(role: .user, text: "hello"), .init(role: .agent, text: "hi there")
        ])
        let replay = ACPSessionStore.replayNotifications(rec)
        precondition(replay.count == 2)
        func update(_ n: [String: Any]) -> [String: Any] { ((n["params"] as? [String: Any])?["update"] as? [String: Any]) ?? [:] }
        precondition(replay[0]["method"] as? String == "session/update")
        precondition(update(replay[0])["sessionUpdate"] as? String == "user_message_chunk")
        precondition(update(replay[1])["sessionUpdate"] as? String == "agent_message_chunk")
        precondition((update(replay[1])["content"] as? [String: Any])?["text"] as? String == "hi there")
        precondition(update(replay[0])["messageId"] as? String != update(replay[1])["messageId"] as? String)

        precondition(ACPSessionStore.title(fromPrompt: "Fix the login bug\nmore details") == "Fix the login bug")
        precondition(ACPSessionStore.title(fromPrompt: String(repeating: "x", count: 200)).count == 78)
    }

    static func clientParsing() {
        func events(_ update: [String: Any]) -> [ACPStreamEvent] {
            ACPStandardJsonRpcParser.parseEvents(["jsonrpc": "2.0", "method": "session/update",
                                                  "params": ["sessionId": "s", "update": update]])
        }
        guard case .systemInfo(let usageInfo)? = events([
            "sessionUpdate": "usage_update", "used": 53000, "size": 200000, "cost": ["amount": 0.045, "currency": "USD"]
        ]).first else { preconditionFailure("usage_update not parsed") }
        precondition(usageInfo.usage == ACPUsage(used: 53000, size: 200000, costAmount: 0.045, costCurrency: "USD"))
        precondition(abs((usageInfo.usage?.fractionUsed ?? 0) - 0.265) < 0.0001)
        precondition(events(["sessionUpdate": "usage_update", "used": 10, "size": 0]).isEmpty, "no size => ignored")

        guard case .systemInfo(let titleInfo)? = events(["sessionUpdate": "session_info_update", "title": "Refactor auth"]).first
        else { preconditionFailure("session_info_update not parsed") }
        precondition(titleInfo.sessionTitle == "Refactor auth")

        let resume = ACPStandardJsonRpcParser.buildSessionResumeRequest(id: 5, sessionId: "s1", cwd: "/w", mcpServers: [])
        precondition(resume["method"] as? String == "session/resume")
        precondition((resume["params"] as? [String: Any])?["sessionId"] as? String == "s1")
        let close = ACPStandardJsonRpcParser.buildSessionCloseRequest(id: 6, sessionId: "s1")
        precondition(close["method"] as? String == "session/close")
    }

    static func capabilities() {
        let caps: [String: Any] = ["loadSession": true, "sessionCapabilities": ["resume": [String: Any](), "close": NSNull()]]
        precondition(ACPSessionCapabilities.supports(caps, "resume"))
        precondition(!ACPSessionCapabilities.supports(caps, "close"), "null means unsupported")
        precondition(!ACPSessionCapabilities.supports(caps, "list"))
        precondition(ACPSessionCapabilities.supportsLoad(caps))
        precondition(ACPSessionCapabilities.bootstrapMethod(agentCapabilities: caps, previousSessionId: "s1") == "session/resume")
        precondition(ACPSessionCapabilities.bootstrapMethod(agentCapabilities: caps, previousSessionId: nil) == "session/new")
        precondition(ACPSessionCapabilities.bootstrapMethod(agentCapabilities: [:], previousSessionId: "s1") == "session/new")
    }
}
