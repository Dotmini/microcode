import Foundation

// Phase 3a harness regression: sub-agent fan-out bounds, enforced plan mode, stale-edit guard,
// untracked-file checkpoints, persistent tool trace. Compiled with the real sources by run-phase3a-harness.sh.

@main struct Phase3aHarnessRegression {
    static func main() async throws {
        await subAgentBounds()
        planMode()
        freshness()
        try untrackedSnapshot()
        try toolTrace()
        print("PHASE3A HARNESS REGRESSION: PASS")
    }

    static func subAgentBounds() async {
        precondition(SubAgentSpawnPolicy.decide(spawnerDepth: 0, runningCount: 0) == .allow)
        precondition(SubAgentSpawnPolicy.decide(spawnerDepth: 1, runningCount: 7) == .allow)
        precondition(SubAgentSpawnPolicy.decide(spawnerDepth: 2, runningCount: 0) == .tooDeep(depth: 2))
        precondition(SubAgentSpawnPolicy.decide(spawnerDepth: 0, runningCount: 8) == .tooManyRunning(running: 8))
        precondition(SubAgentSpawnPolicy.Decision.allow.rejectionReason == nil)
        precondition(!SubAgentSpawnPolicy.unknownTypeTools.contains("shell"))
        precondition(!SubAgentSpawnPolicy.unknownTypeTools.contains("file_write"))
        precondition(!SubAgentSpawnPolicy.unknownTypeTools.contains("*"))
        // Depth is inherited by tasks a sub-agent starts (its tool calls / nested spawns).
        precondition(SubAgentContext.depth == 0)
        let inherited = await SubAgentContext.$depth.withValue(1) {
            await Task { SubAgentContext.depth }.value
        }
        precondition(inherited == 1)
    }

    static func planMode() {
        let readOnlyShell: (String) -> Bool = { command in ["ls", "cat", "git status", "rg"].contains { command.hasPrefix($0) } }
        func allowed(_ tool: String, _ args: [String: Any] = [:]) -> Bool {
            PlanModePolicy.isAllowedWhileLocked(toolName: tool, arguments: args, isReadOnlyShell: readOnlyShell)
        }
        precondition(PlanModePolicy.isPlanModePrompt("[PLAN MODE — MANDATORY DEEP ANALYSIS]\nObjective: x"))
        precondition(!PlanModePolicy.isPlanModePrompt("fix the bug"))
        for tool in ["file_read", "grep_search", "list_directory_tree", "create_plan", "web_fetch"] {
            precondition(allowed(tool), "\(tool) must stay available while planning")
        }
        for tool in ["file_write", "replace_in_file", "apply_patch", "rename_file", "delete_file", "computer_use", "agent_desktop", "export_pdf"] {
            precondition(!allowed(tool), "\(tool) must be blocked until the plan is approved")
        }
        precondition(allowed("shell", ["command": "ls -la"]))
        precondition(!allowed("shell", ["command": "rm -rf build"]))
        precondition(allowed("skill_engine", ["action": "read"]))
        precondition(!allowed("skill_engine", ["action": "run_script"]))
        precondition(allowed("swarm_orchestrator", ["action": "post_fact"]))
        precondition(!allowed("swarm_orchestrator", ["action": "ceo_squad"]))
        precondition(allowed("mcp__github__get_issue"))
        precondition(allowed("mcp__docs__search"))
        precondition(!allowed("mcp__github__create_issue"))
        precondition(!allowed("mcp__slack__post_message"))

        let gate = PlanModeGate()
        precondition(gate.isLocked)
        gate.unlock()
        precondition(!gate.isLocked)
    }

    static func freshness() {
        var disk: [String: FileStamp] = ["/w/a.swift": FileStamp(modified: 100, size: 10)]
        let registry = FileFreshnessRegistry(stat: { disk[$0] })
        precondition(registry.staleReason(forEditing: "/w/a.swift") == nil, "never-read files are not guarded")
        registry.noteObserved("/w/a.swift")
        precondition(registry.staleReason(forEditing: "/w/a.swift") == nil)
        disk["/w/a.swift"] = FileStamp(modified: 105, size: 12) // user typed in the IDE
        precondition(registry.staleReason(forEditing: "/w/a.swift") != nil, "edit from an outdated read must be refused")
        precondition(registry.staleReason(forEditing: "/w/./a.swift") != nil, "paths are normalized")
        registry.noteObserved("/w/a.swift") // agent re-read
        precondition(registry.staleReason(forEditing: "/w/a.swift") == nil)
        disk["/w/a.swift"] = nil // deleted: let the tool itself report it
        precondition(registry.staleReason(forEditing: "/w/a.swift") == nil)
    }

    static func untrackedSnapshot() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("mc-ckpt-\(UUID().uuidString)").path
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: root) }
        func write(_ name: String, _ text: String) throws {
            try text.write(toFile: (root as NSString).appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        func read(_ name: String) -> String? { try? String(contentsOfFile: (root as NSString).appendingPathComponent(name), encoding: .utf8) }
        let identity = ["GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"]
        GitUntrackedSnapshot.git(["init", "-q"], in: root)
        try write(".gitignore", "ignored.log\n")
        try write("tracked.txt", "committed")
        GitUntrackedSnapshot.git(["add", "."], in: root)
        GitUntrackedSnapshot.git(["commit", "-q", "-m", "init"], in: root, env: identity)

        try write("notes.md", "user notes v1")            // untracked, never committed
        try write("ignored.log", "noise")                 // ignored
        try write("big.bin", String(repeating: "x", count: 3_000_000)) // over the per-file cap
        let statusBefore = GitUntrackedSnapshot.git(["status", "--porcelain"], in: root).output

        guard let ref = GitUntrackedSnapshot.capture(root: root, checkpointId: "t1") else {
            preconditionFailure("untracked snapshot not captured")
        }
        precondition(GitUntrackedSnapshot.git(["status", "--porcelain"], in: root).output == statusBefore,
                     "capturing must not touch the real index or working tree")
        let captured = GitUntrackedSnapshot.git(["ls-tree", "-r", "--name-only", ref], in: root).output
        precondition(captured.contains("notes.md") && !captured.contains("ignored.log") && !captured.contains("big.bin"))

        // The agent overwrites the untracked file and deletes it later; rollback brings it back.
        try write("notes.md", "agent clobbered")
        precondition(GitUntrackedSnapshot.restore(root: root, ref: ref) == 1)
        precondition(read("notes.md") == "user notes v1")
        try fm.removeItem(atPath: (root as NSString).appendingPathComponent("notes.md"))
        GitUntrackedSnapshot.restore(root: root, ref: ref)
        precondition(read("notes.md") == "user notes v1")
        precondition(read("tracked.txt") == "committed", "tracked files are not affected")
        precondition(!GitUntrackedSnapshot.git(["diff", "--cached", "--name-only"], in: root).output.contains("notes.md"),
                     "restore must not stage files")
        GitUntrackedSnapshot.delete(root: root, ref: ref)
        precondition(GitUntrackedSnapshot.git(["rev-parse", "--verify", ref], in: root).code != 0)

        // Selection caps.
        let picked = GitUntrackedSnapshot.select(
            [("b", 10), ("a", 10), ("huge", 5_000_000), ("neg", -1)],
            limits: .init(maxFiles: 10, maxFileBytes: 1_000, maxTotalBytes: 15)
        )
        precondition(picked == ["a"], "sorted, per-file and total caps: \(picked)")
    }

    static func toolTrace() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mc-trace-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let trace = AgentToolTrace(directory: dir, maxBytes: 400, redact: { $0.replacingOccurrences(of: "sk-LIVE", with: "[REDACTED]") })
        trace.record(tool: "shell", arguments: ["command": "curl -H 'Authorization: sk-LIVE'", "__microcode_invalid_arguments": "x"],
                     success: false, duration: 0.25, error: "denied sk-LIVE")
        trace.flush()
        let text = try String(contentsOf: trace.fileURL, encoding: .utf8)
        precondition(!text.contains("sk-LIVE"), "secrets must be redacted in the trace")
        guard let line = text.split(separator: "\n").first,
              let json = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            preconditionFailure("trace line is not JSON")
        }
        precondition(json["tool"] as? String == "shell" && json["ok"] as? Bool == false && json["ms"] as? Int == 250)
        precondition((json["args"] as? [String: Any])?["__microcode_invalid_arguments"] == nil)
        for _ in 0..<10 { trace.record(tool: "file_read", arguments: ["path": "/w/a"], success: true, duration: 0, error: nil) }
        trace.flush()
        precondition(FileManager.default.fileExists(atPath: trace.fileURL.appendingPathExtension("1").path), "trace must rotate at the size cap")
    }
}
