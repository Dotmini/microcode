import Foundation

/// Headless replay eval of the real agent loop (`AgentService.sendMessage`), graded by AgentEvalGrader.
///
///     MICROCODE_AGENT_EVAL_CASES=<dir of *.json cases> MICROCODE_AGENT_EVAL_OUT=<results.jsonl> MicroCode
///     optional: MICROCODE_AGENT_EVAL_PROVIDER / _MODEL / _ONLY=<case id> / _TIMEOUT=<seconds, default 420>
///
/// Each case runs in a fresh chat on a temporary copy of its fixture. Tool approvals are granted only for that run
/// (the user's approval mode is not changed), and the eval chats are deleted afterwards. Uses the provider/model
/// the app is configured with unless overridden, so results reflect what the user actually gets.
/// Scripts/eval/run-agent-eval.sh refuses to start while the main MicroCode app is open (shared chat list).
@MainActor
enum AgentEvalRunner {
    struct Result: Codable {
        var id: String
        var provider: String
        var model: String
        var passed: Bool
        var checks: [AgentEvalCheckResult]
        var seconds: Int
        var answer: String
        var tools: [String]
        var createdFiles: [String]
        var modifiedFiles: [String]
        var trace: AgentTurnTrace?
    }

    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let casesDir = env["MICROCODE_AGENT_EVAL_CASES"], let outPath = env["MICROCODE_AGENT_EVAL_OUT"] else { return }
        Task { @MainActor in
            // AppState is created by the window scene; wait for it (it holds the configured provider/model/keys).
            var waited = 0
            while AppState.shared == nil && waited < 600 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
            // AppState.init queues loadSettings() on the main queue (saved provider/model/keys); a later main-queue
            // hop runs after it. Reading before that saw the built-in "gemini/gemini-2.5-flash" defaults.
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { done.resume() }
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let failures = await run(casesDir: casesDir, outPath: outPath, env: env)
            exit(failures == 0 ? 0 : 1)
        }
    }

    static func run(casesDir: String, outPath: String, env: [String: String]) async -> Int {
        let fm = FileManager.default
        let casesURL = URL(fileURLWithPath: casesDir, isDirectory: true)
        let files = ((try? fm.contentsOfDirectory(atPath: casesDir)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
        let decoder = JSONDecoder()
        var cases: [AgentEvalCase] = files.compactMap { name in
            guard let data = fm.contents(atPath: casesURL.appendingPathComponent(name).path) else { return nil }
            do { return try decoder.decode(AgentEvalCase.self, from: data) } catch {
                print("[agent-eval] skipping \(name): \(error)")
                return nil
            }
        }
        if let only = env["MICROCODE_AGENT_EVAL_ONLY"], !only.isEmpty { cases = cases.filter { $0.id == only } }
        let appState = AppState.shared
        let provider = env["MICROCODE_AGENT_EVAL_PROVIDER"] ?? appState?.aiProvider ?? "gemini"
        let model = env["MICROCODE_AGENT_EVAL_MODEL"] ?? appState?.aiModel ?? ""
        let apiKey = appState?.resolveApiKey(for: provider) ?? AIModelCatalog.resolveKey(provider)
        let timeout = Double(env["MICROCODE_AGENT_EVAL_TIMEOUT"] ?? "") ?? 420
        print("[agent-eval] \(cases.count) case(s) on \(provider)/\(model.isEmpty ? "(default)" : model) · key \(apiKey.isEmpty ? "missing" : "present") · saved setting \(UserDefaults.standard.string(forKey: "aiProvider") ?? "-")/\(UserDefaults.standard.string(forKey: "aiModel") ?? "-")")

        fm.createFile(atPath: outPath, contents: nil)
        let out = FileHandle(forWritingAtPath: outPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var failed = 0
        for testCase in cases {
            let result = await runCase(testCase, casesURL: casesURL, provider: provider, model: model, apiKey: apiKey, timeout: timeout)
            if !result.passed { failed += 1 }
            let marks = result.checks.map { "\($0.passed ? "✓" : "✗") \($0.check): \($0.detail)" }.joined(separator: "\n    ")
            print("[agent-eval] \(result.passed ? "PASS" : "FAIL") \(result.id) (\(result.seconds)s)\n    \(marks)")
            if let data = try? encoder.encode(result) {
                out?.write(data)
                out?.write(Data("\n".utf8))
            }
        }
        try? out?.close()
        print("[agent-eval] \(cases.count - failed)/\(cases.count) passed → \(outPath)")
        return failed
    }

    private static func snapshot(_ root: URL) -> [String: String] {
        var result: [String: String] = [:]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return result }
        // /var/folders is a symlink to /private/var/folders: compare resolved paths so `rel` is really relative.
        let rootPath = root.resolvingSymlinksInPath().path
        // Caches the test runner writes by itself are not files the agent created.
        let toolCaches = [".pytest_cache/", "__pycache__/", ".mypy_cache/", ".ruff_cache/", "node_modules/.cache/"]
        for case let url as URL in walker {
            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(rootPath + "/") else { continue }
            let rel = String(path.dropFirst(rootPath.count + 1))
            if rel.hasPrefix(".microcode") || rel.hasPrefix(".git/") { continue }
            if toolCaches.contains(where: { rel.hasPrefix($0) || rel.contains("/" + $0) }) { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let data = FileManager.default.contents(atPath: url.path) else { continue }
            result[rel] = "\(data.count):\(data.hashValue)"
        }
        return result
    }

    private static func runCase(_ testCase: AgentEvalCase, casesURL: URL, provider: String, model: String, apiKey: String, timeout: Double) async -> Result {
        let fm = FileManager.default
        let agent = AgentService.shared
        let workspace = fm.temporaryDirectory.appendingPathComponent("microcode-agent-eval-\(testCase.id)-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try? fm.removeItem(at: workspace)
        if let fixture = testCase.fixture {
            try? fm.copyItem(at: casesURL.appendingPathComponent(fixture, isDirectory: true), to: workspace)
        }
        try? fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        let before = snapshot(workspace)

        agent.setWorkspace(workspace.path)
        let chat = agent.createNewChat(name: "agent-eval \(testCase.id)", projectPath: workspace.path)
        agent.messages = testCase.history.map { turn in
            let wrote = (turn.wroteFiles ?? []).map { file in
                ToolResultModel(toolCallId: UUID().uuidString, toolName: "file_write",
                                toolParams: ["path": workspace.appendingPathComponent(file).path],
                                success: true, output: "✅ Written \(file)")
            }
            return AgentMessageModel(id: UUID().uuidString, role: turn.role == "user" ? .user : .assistant,
                                     content: turn.content, toolResults: wrote)
        }

        // Approve tool requests for this run only (the user's approval mode stays as it is), and only inside the
        // temporary workspace: critical-risk requests and arguments naming other home-folder paths are rejected.
        let home = fm.homeDirectoryForCurrentUser.path
        let approver = Task { @MainActor in
            while !Task.isCancelled {
                if let pending = ToolApprovalManager.shared.pendingRequest {
                    let touchesOtherUserPaths = pending.arguments.values.contains { value in
                        value.contains(home) && !value.contains(workspace.path)
                    }
                    if pending.riskLevel == .critical || touchesOtherUserPaths {
                        print("[agent-eval] rejected \(pending.toolName): outside the eval workspace")
                        ToolApprovalManager.shared.reject()
                    } else {
                        ToolApprovalManager.shared.approve()
                    }
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        let started = Date()
        let run = Task { @MainActor in
            await agent.sendMessage(testCase.prompt, provider: provider, model: model, apiKey: apiKey)
        }
        let watchdog = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if !Task.isCancelled { agent.stopGeneration(autoProcessQueue: false) }
        }
        await run.value
        watchdog.cancel()
        approver.cancel()

        let reply = agent.messages.last(where: { $0.role == .assistant && $0.id != "streaming" })
        let after = snapshot(workspace)
        let created = after.keys.filter { before[$0] == nil }.sorted()
        let modified = after.keys.filter { before[$0] != nil && before[$0] != after[$0] }.sorted()
        let tools = (reply?.toolResults ?? []).map { tr in
            AgentEvalObservation.ToolRun(
                name: tr.toolName, success: tr.success,
                arguments: (tr.toolParams ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"),
                output: tr.success ? tr.output : (tr.error ?? tr.output)
            )
        }
        let observation = AgentEvalObservation(answer: reply?.content ?? "", tools: tools, createdFiles: created,
                                               modifiedFiles: modified, interventions: reply?.harnessTrace?.totalInterventions)
        let checks = AgentEvalGrader.grade(testCase, observation)

        agent.deleteChat(chat.id)
        try? fm.removeItem(at: workspace)
        return Result(id: testCase.id, provider: reply?.harnessTrace?.provider ?? provider, model: reply?.harnessTrace?.model ?? model,
                      passed: !checks.isEmpty && checks.allSatisfy(\.passed), checks: checks,
                      seconds: Int(Date().timeIntervalSince(started)), answer: String(observation.answer.prefix(4_000)),
                      tools: tools.map { "\($0.name)(\($0.success ? "ok" : "error"))" }, createdFiles: created,
                      modifiedFiles: modified, trace: reply?.harnessTrace)
    }
}
