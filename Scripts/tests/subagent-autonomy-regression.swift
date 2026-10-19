import Foundation
import Combine

// Scripted model boundary; the production harness and completion checks run
// unchanged against a real temporary workspace and real test subprocesses.
struct AIToolCall {
    let id = UUID().uuidString
    let name: String
    let arguments: [String: Any]
}
enum StreamableAIProvider: String {
    case omni, gemini, anthropic
    var defaultModel: String { "fixture-model" }
    static func detect(from: String) -> Self { .omni }
}
@MainActor final class AIModelCatalog {
    static let shared = AIModelCatalog()
    func normalizedSelection(provider: String, model: String) -> (provider: String, model: String) { (provider, model) }
}
@MainActor final class MCPClient {
    static let shared = MCPClient()
    let isConnected = false
    func ensureConnected(workspacePath: String?) async {}
}
@MainActor final class AgentSkillsStore {
    static let shared = AgentSkillsStore()
    func enabledSkillIds() -> [String] { [] }
}
@MainActor final class AgentService {
    static let shared = AgentService()
    let currentKernelRunID: String? = nil
}
struct FixtureDirective {
    let action = "continue"
    let suggestedPrompt: String? = nil
    let retryAfterMs: UInt64? = nil
    let reason: String? = nil
}
struct FixtureKernelResponse { let directive = FixtureDirective() }
@MainActor final class AgentKernelClient {
    static let shared = AgentKernelClient()
    func createOrResume(runID: String, parentRunID: String?, objective: String, workspace: String, provider: String, model: String, tools: [String], skills: [String], mcpServers: [String]) async -> FixtureKernelResponse? { nil }
    func observe(runID: String, kind: String, toolName: String? = nil, arguments: [String: Any]? = nil, success: Bool? = nil, output: String? = nil, error: String? = nil, transient: Bool = false, madeProgress: Bool = false) async -> FixtureKernelResponse? { nil }
    func cancel(runID: String) async {}
}
struct SubAgentEvent {
    enum EventType { case invoked, completed, errored, killed }
    init(type: EventType, subagentId: String, role: String, typeName: String, detail: String?) {}
}
enum ToolBoxError: LocalizedError {
    case executionFailed(String)
    var errorDescription: String? { if case .executionFailed(let value) = self { return value }; return nil }
}
@MainActor final class AIClient {
    static let shared = AIClient()
    typealias Reply = (text: String, toolCalls: [AIToolCall])
    var replies: [Reply] = []
    var callCount = 0
    var seenTools: [String] = []
    var delay: UInt64 = 0
    func reset(_ replies: [Reply], delay: UInt64 = 0) { self.replies = replies; callCount = 0; seenTools = []; self.delay = delay }
    func sendSync(messages: [[(String, Any)]], systemPrompt: String?, provider: StreamableAIProvider, model: String, apiKey: String, tools: [[String: Any]]) async throws -> Reply {
        callCount += 1
        seenTools = tools.compactMap { $0["name"] as? String }
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        return replies.isEmpty ? ("Done", []) : replies.removeFirst()
    }
}
@MainActor final class AgentToolBox {
    static let shared = AgentToolBox()
    var workspaceRoot: String?
    var executed: [String] = []
    func toolSchemas() -> [[String: Any]] {
        ["file_read", "file_write", "shell", "delete_file", "mcp__local__fixture"].map { ["name": $0] }
    }
    func execute(_ name: String, params: [String: Any]) async throws -> String {
        try Task.checkCancellation()
        executed.append(name)
        let root = URL(fileURLWithPath: workspaceRoot!)
        if name == "file_read" { return try String(contentsOf: root.appendingPathComponent(params["path"] as! String), encoding: .utf8) }
        if name == "file_write" {
            try (params["content"] as! String).write(to: root.appendingPathComponent(params["path"] as! String), atomically: true, encoding: .utf8)
            return "File written"
        }
        if name == "shell" {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", params["command"] as! String]
            process.currentDirectoryURL = root
            process.standardOutput = pipe; process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            if process.terminationStatus != 0 { throw ToolBoxError.executionFailed(output) }
            return output
        }
        throw ToolBoxError.executionFailed("Unexpected fixture tool")
    }
}

@main struct SubagentAutonomyRegression {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("microcode-harness-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        AgentToolBox.shared.workspaceRoot = root.path
        try "def add(a,b): return a-b\n".write(to: root.appendingPathComponent("calc.py"), atomically: true, encoding: .utf8)
        try "import unittest\nfrom calc import add\nclass Tests(unittest.TestCase):\n def test_add(self): self.assertEqual(add(2,3),5)\n".write(to: root.appendingPathComponent("test_calc.py"), atomically: true, encoding: .utf8)
        let harness = SubAgentHarness.shared, model = AIClient.shared
        _ = harness.defineSubagent(name: "fixture", role: "Engineer", description: "Fixture", systemPrompt: "Work", allowedTools: ["file_read", "file_write", "shell"])
        func run(_ prompt: String, replies: [AIClient.Reply], type: String = "fixture") async throws -> SubAgentHarness.Outcome {
            model.reset(replies)
            let instance = harness.invokeSubagent(typeName: type, role: "Fixture", prompt: prompt, workspacePath: root.path)
            return try await harness.waitForSubagent(id: instance.id)!
        }
        let repaired = try await run("Fix calc.py and test", replies: [
            ("", [AIToolCall(name: "shell", arguments: ["command": "PYTHONDONTWRITEBYTECODE=1 python3 -m unittest"])]),
            ("", [AIToolCall(name: "file_write", arguments: ["path": "calc.py", "content": "def add(a,b): return a+b\n"])]),
            ("", [AIToolCall(name: "shell", arguments: ["command": "PYTHONDONTWRITEBYTECODE=1 python3 -m unittest"])]),
            ("Fixed; tests passed", [])
        ])
        if repaired.instance.state != .completed { print(repaired.instance.stateDetail ?? "", repaired.instance.logMessages) }
        precondition(repaired.instance.state == .completed && repaired.verifiedWorkspaceChange)
        let prose = try await run("Fix calc.py", replies: [("Fixed", [])])
        precondition(prose.instance.state == .waitingForInput && !prose.verifiedWorkspaceChange)
        let inventory = try await run("Fix calc.py", replies: [("", [AIToolCall(name: "file_read", arguments: ["path": "calc.py"])]), ("Fixed", [])])
        precondition(inventory.instance.state == .waitingForInput)
        let untested = try await run("Fix calc.py", replies: [
            ("", [AIToolCall(name: "file_write", arguments: ["path": "calc.py", "content": "def add(a,b): return a+b\n"])]),
            ("", [AIToolCall(name: "shell", arguments: ["command": "pwd"])]), ("Done", [])
        ])
        precondition(untested.instance.state == .waitingForInput)
        let readOnly = try await run("Inspect calc.py", replies: [("", [AIToolCall(name: "file_read", arguments: ["path": "calc.py"])]), ("Inspected", [])], type: "architect")
        precondition(readOnly.instance.state == .completed)
        precondition(!model.seenTools.contains("file_write") && model.seenTools.contains("mcp__local__fixture"))
        model.reset([], delay: 30_000_000_000)
        let cancelled = harness.invokeSubagent(typeName: "fixture", role: "Cancel fixture", prompt: "Fix calc.py", workspacePath: root.path)
        let waiting = Task { try await harness.waitForSubagent(id: cancelled.id) }
        while model.callCount == 0 { await Task.yield() }
        waiting.cancel()
        do { _ = try await waiting.value; preconditionFailure("Cancellation did not propagate") } catch is CancellationError {}
        precondition(harness.activeSubagents.first { $0.id == cancelled.id }?.state == .killed)
        print("PASS: real failing-test → change → passing-test loop; prose/inventory/pwd cannot complete; scoped tools and cancellation")
    }
}
