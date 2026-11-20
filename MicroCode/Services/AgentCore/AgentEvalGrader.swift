import Foundation

/// Replay eval for the real agent loop (docs/research/2026-11-21-agent-intelligence.md, P0-0).
/// A case = fixture workspace + earlier chat + one user message + deterministic checks on what the agent did.
struct AgentEvalCase: Codable {
    struct Turn: Codable {
        var role: String            // "user" | "assistant"
        var content: String
        /// Files an earlier assistant turn wrote (seeded as successful `file_write` results).
        var wroteFiles: [String]?
    }
    struct Checks: Codable {
        /// A command/run tool (shell, playground_run, ardium_run, device_runtime, cell_run…) must run.
        var mustRunCommand: Bool?
        /// No new files may appear in the workspace.
        var mustNotCreateFiles: Bool?
        /// Existing files may not change.
        var mustNotModifyFiles: Bool?
        /// The answer must contain a code block with text that also appears in a real command output.
        var answerMustShowOutput: Bool?
        /// The answer must contain at least one of these (case-insensitive).
        var answerContainsAny: [String]?
        /// Never claim success ("สำเร็จ", "passed", "✅" …) in a turn that ran no command.
        var mustNotClaimWithoutEvidence: Bool?
        /// No tool argument may contain these strings (e.g. a print-only "verification").
        var forbiddenInToolArgs: [String]?
        /// Upper bound on harness interventions recorded in the turn trace.
        var maxInterventions: Int?
    }
    var id: String
    var note: String?
    /// Directory under the cases folder copied to a temporary workspace (nil = empty workspace).
    var fixture: String?
    var history: [Turn]
    var prompt: String
    var checks: Checks
}

struct AgentEvalObservation {
    struct ToolRun {
        var name: String
        var success: Bool
        /// Argument values as plain `key: value` lines (not JSON), so forbidden code strings match as written.
        var arguments: String
        var output: String
    }
    var answer: String
    var tools: [ToolRun]
    var createdFiles: [String]
    var modifiedFiles: [String]
    var interventions: Int?
}

struct AgentEvalCheckResult: Codable, Equatable {
    var check: String
    var passed: Bool
    var detail: String
}

enum AgentEvalGrader {
    static let commandTools: Set<String> = [
        "shell", "playground_run", "ardium_run", "ardium_compile", "ardium_test", "cell_run",
        "device_runtime", "run_tests", "mcp__local__ardium_compile", "mcp__local__ardium_test"
    ]
    private static let successClaim = try! NSRegularExpression(
        pattern: #"(สำเร็จ|เรียบร้อยแล้ว|ผ่านทั้งหมด|successfully|all tests pass|passed|✅)"#,
        options: [.caseInsensitive]
    )

    static func isCommand(_ tool: AgentEvalObservation.ToolRun) -> Bool {
        commandTools.contains(tool.name)
    }

    static func claimsSuccess(_ text: String) -> Bool {
        successClaim.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// True when a fenced block in the answer repeats a real line (≥ 8 chars) of some command output.
    static func showsRealOutput(answer: String, tools: [AgentEvalObservation.ToolRun]) -> Bool {
        let blocks = answer.components(separatedBy: "```").enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        guard !blocks.isEmpty else { return false }
        let outputLines = Set(tools.filter(isCommand).flatMap { $0.output.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 8 })
        guard !outputLines.isEmpty else { return false }
        return blocks.contains { block in
            block.components(separatedBy: .newlines).contains { outputLines.contains($0.trimmingCharacters(in: .whitespaces)) }
        }
    }

    static func grade(_ testCase: AgentEvalCase, _ observed: AgentEvalObservation) -> [AgentEvalCheckResult] {
        let checks = testCase.checks
        let ranCommand = observed.tools.contains(where: isCommand)
        var results: [AgentEvalCheckResult] = []
        func add(_ name: String, _ passed: Bool, _ detail: String) {
            results.append(AgentEvalCheckResult(check: name, passed: passed, detail: detail))
        }
        if checks.mustRunCommand == true {
            add("ran_command", ranCommand, ranCommand ? "ran \(observed.tools.filter(isCommand).map(\.name))" : "no command tool ran")
        }
        if checks.mustNotCreateFiles == true {
            add("no_new_files", observed.createdFiles.isEmpty, observed.createdFiles.isEmpty ? "none" : "created \(observed.createdFiles)")
        }
        if checks.mustNotModifyFiles == true {
            add("no_modified_files", observed.modifiedFiles.isEmpty, observed.modifiedFiles.isEmpty ? "none" : "modified \(observed.modifiedFiles)")
        }
        if checks.answerMustShowOutput == true {
            let shows = showsRealOutput(answer: observed.answer, tools: observed.tools)
            add("shows_real_output", shows, shows ? "answer quotes command output" : "no code block repeating real command output")
        }
        if let wanted = checks.answerContainsAny, !wanted.isEmpty {
            let lower = observed.answer.lowercased()
            let hit = wanted.first { lower.contains($0.lowercased()) }
            add("answer_contains", hit != nil, hit.map { "found \"\($0)\"" } ?? "none of \(wanted)")
        }
        if checks.mustNotClaimWithoutEvidence == true {
            let unsupported = claimsSuccess(observed.answer) && !ranCommand
            add("no_unsupported_claim", !unsupported, unsupported ? "claims success but ran no command" : "ok")
        }
        if let forbidden = checks.forbiddenInToolArgs, !forbidden.isEmpty {
            let hits = observed.tools.flatMap { tool in forbidden.filter { tool.arguments.contains($0) }.map { "\(tool.name): \($0)" } }
            add("no_forbidden_args", hits.isEmpty, hits.isEmpty ? "ok" : hits.joined(separator: "; "))
        }
        if let limit = checks.maxInterventions {
            let count = observed.interventions ?? 0
            add("interventions", count <= limit, "\(count) (limit \(limit))")
        }
        return results
    }
}
