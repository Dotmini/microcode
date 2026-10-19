import Foundation

@main struct AgentAutonomyRegression {
    @MainActor static func main() async {
        let suite = "microcode.autonomy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let manager = ToolApprovalManager(defaults: defaults)
        precondition(manager.mode == .smart)
        let pending = Task { await manager.requestApproval(toolName: "shell", arguments: ["command": "swift test"], description: "Run tests") }
        while manager.pendingRequest == nil { await Task.yield() }
        manager.mode = .yolo
        let approved = await pending.value
        precondition(approved)
        precondition(ToolApprovalManager(defaults: defaults).mode == .yolo)

        let initial = CodexProcessArguments.build(task: "Fix and test", model: "gpt-6.1-sol", sessionID: nil,
                                                   permissionMode: .reviewEach, extra: [])
        precondition(Array(initial.prefix(2)) == ["exec", "--json"])
        precondition(initial.contains("--sandbox") && initial.last == "Fix and test")
        let resumed = CodexProcessArguments.build(task: "Continue", model: nil, sessionID: "thread-123",
                                                   permissionMode: .fullAuto, extra: [])
        precondition(Array(resumed.prefix(2)) == ["exec", "resume"])
        precondition(resumed.contains("--dangerously-bypass-approvals-and-sandbox"))
        precondition(Array(resumed.suffix(2)) == ["thread-123", "Continue"])

        let start = CodexStreamParser.parse(["type": "thread.started", "thread_id": "thread-123"])
        if case .some(.sessionInit(let event)) = start { precondition(event.sessionId == "thread-123") }
        else { preconditionFailure("Missing Codex thread event") }
        let call = CodexStreamParser.parse(["type": "item.started", "item": ["id": "item_1", "type": "command_execution", "command": "swift test"]])
        if case .some(.toolCall(let event)) = call { precondition(event.id == "item_1" && event.name == "Bash") }
        else { preconditionFailure("Missing Codex command event") }
        let result = CodexStreamParser.parse(["type": "item.completed", "item": ["id": "item_1", "type": "command_execution", "exit_code": 0, "aggregated_output": "passed"]])
        if case .some(.toolResult(let event)) = result { precondition(event.toolCallId == "item_1" && !event.isError) }
        else { preconditionFailure("Missing Codex tool result") }
        let answer = CodexStreamParser.parse(["type": "item.completed", "item": ["type": "agent_message", "text": "Done"]])
        if case .some(.text(let value)) = answer { precondition(value == "Done") }
        else { preconditionFailure("Missing Codex final answer") }

        var evidence = AgentExecutionEvidence()
        evidence.record(name: "shell", arguments: ["command": "swift test"], success: true)
        evidence.record(name: "file_write", arguments: [:], success: true)
        precondition(!evidence.satisfies(requiresMutation: true, requiresExecution: true))
        evidence.record(name: "shell", arguments: ["command": "pwd"], success: true)
        precondition(!evidence.hasVerifiedMutation)
        evidence.record(name: "shell", arguments: ["command": "swift test"], success: false)
        precondition(!evidence.hasVerifiedMutation)
        evidence.record(name: "shell", arguments: ["command": "swift test"], success: true)
        precondition(evidence.satisfies(requiresMutation: true, requiresExecution: true))
        evidence.record(name: "patch_file", arguments: [:], success: true)
        precondition(!evidence.satisfies(requiresMutation: true))
        precondition(!AgentExecutionEvidence.shellVerifies("echo 'cargo test'"))
        precondition(!AgentExecutionEvidence.shellVerifies("npm install"))
        precondition(AgentExecutionEvidence.shellVerifies("cd app && npm run build"))
        precondition(AgentExecutionEvidence.shellVerifies("CARGO_TARGET_DIR=/tmp/cache cargo test"))
        precondition(AgentExecutionEvidence.shellMutates("python3 -c \"Path('a.swift').write_text('new')\""))
        precondition(!AgentExecutionEvidence.taskRequiresMutation("Inspect how to fix it, do not modify files"))
        var background = AgentExecutionEvidence()
        background.record(name: "invoke_subagent", arguments: [:], success: true, output: "started in background")
        precondition(!background.satisfies(requiresMutation: false))
        print("PASS: persisted autonomy, Codex exec/resume events, post-change verification and background task evidence")
    }
}
