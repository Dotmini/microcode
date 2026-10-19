import Foundation

@main struct CodexProcessRegression {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("microcode-codex-process-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("codex-fixture.py")
        let script = #"""
        #!/usr/bin/env python3
        import json, sys, time
        assert sys.argv[1] == 'exec' and '--json' in sys.argv
        assert '--skip-git-repo-check' in sys.argv
        assert sys.stdin.read() == ''  # parent must supply EOF
        task = sys.argv[-1]
        if task == 'slow': time.sleep(1)
        def event(value): print(json.dumps(value), flush=True)
        event({'type':'thread.started','thread_id':'fixture-thread'})
        if task == 'fail':
            event({'type':'turn.failed','error':{'message':'fixture failure'}})
        else:
            event({'type':'item.started','item':{'id':'call-1','type':'command_execution','command':'python3 -m unittest'}})
            event({'type':'item.completed','item':{'id':'call-1','type':'command_execution','exit_code':0,'aggregated_output':'tests passed'}})
            event({'type':'item.completed','item':{'id':'answer-1','type':'agent_message','text':task}})
            event({'type':'turn.completed','usage':{'input_tokens':10,'output_tokens':2}})
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        var config = ACPAgentConfig.defaultConfig(for: .codexEngine, command: executable.path)
        config.permissionMode = .fullAuto
        let session = ACPAgentSession(config: config)
        func run(_ prompt: String) async -> [ACPStreamEvent] {
            let stream = session.eventStream
            let watchdog = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if !Task.isCancelled { session.stop() }
            }
            defer { watchdog.cancel() }
            session.start(task: prompt, workspacePath: root.path)
            var result: [ACPStreamEvent] = []
            for await event in stream { result.append(event) }
            return result
        }
        for prompt in ["initial", "resume"] {
            let events = await run(prompt)
            let completions = events.filter { if case .complete = $0 { return true }; return false }
            precondition(completions.count == 1 && session.streamingText == prompt)
            precondition(session.sessionId == "fixture-thread")
            precondition(events.contains { if case .toolResult(let result) = $0 { return !result.isError && result.content == "tests passed" }; return false })
        }
        let failed = await run("fail")
        precondition(!failed.contains { if case .complete = $0 { return true }; return false })
        precondition(failed.contains { if case .error = $0 { return true }; return false })
        let oldStream = session.eventStream
        session.start(task: "slow", workspacePath: root.path)
        session.stop()
        _ = oldStream
        let restarted = await run("new task")
        precondition(session.streamingText == "new task" && restarted.contains { if case .complete = $0 { return true }; return false })
        print("PASS: Codex subprocess stdin EOF, command/results, one completion, resume ID, failed turn and stop/restart")
    }
}
