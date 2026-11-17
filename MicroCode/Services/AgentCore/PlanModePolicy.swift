import Foundation

/// Plan mode is a promise to the user: research only, no changes until they click Approve on the plan.
/// Previously only the prompt said so and every editing tool stayed callable. The gate is bound per run as a
/// task-local (so sub-agents spawned while planning inherit it) and opened when `create_plan` is approved.
final class PlanModeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var locked = true

    var isLocked: Bool {
        lock.lock(); defer { lock.unlock() }
        return locked
    }

    func unlock() {
        lock.lock(); locked = false; lock.unlock()
    }
}

enum PlanModePolicy {
    /// Marker inserted by the `/plan` slash command (SlashCommandService).
    static func isPlanModePrompt(_ content: String) -> Bool {
        content.contains("[PLAN MODE")
    }

    /// Tools that only read, search, or present the plan.
    static let readOnlyTools: Set<String> = [
        "file_read", "multi_file_read", "attachment_read", "list_directory_tree", "grep_search", "file_search",
        "find_symbol", "codebase_search", "repo_map", "get_diagnostics", "git_status", "git_diff", "git_log",
        "lsp_hover", "lsp_definition", "lsp_completions", "lsp_diagnostics", "lsp_status", "lsp_intelligence",
        "inspect_image", "extract_pdf", "openthai_ocr", "slop_check", "web_fetch", "web_search",
        "create_plan", "agent_plan", "send_message", "manage_subagents"
    ]

    /// Multi-action tools: only their read-only actions are allowed while the plan is unapproved.
    static let readOnlyActions: [String: Set<String>] = [
        "skill_engine": ["match", "read", "distill", "activate"],
        "mcp_orchestrator": ["status", "list", "discover", "search_tools"],
        "swarm_orchestrator": ["post_fact", "read_facts", "blackboard", "status"]
    ]

    /// External MCP tools have no local side-effect metadata here: allow only clearly read-style names.
    private static let readStyleVerbs = ["get", "list", "search", "read", "fetch", "query", "find", "describe", "view", "lookup"]

    static func isAllowedWhileLocked(toolName: String, arguments: [String: Any], isReadOnlyShell: (String) -> Bool) -> Bool {
        if readOnlyTools.contains(toolName) { return true }
        if let actions = readOnlyActions[toolName] {
            let action = (arguments["action"] as? String ?? "").lowercased()
            return actions.contains(action)
        }
        if toolName == "shell" {
            guard let command = arguments["command"] as? String else { return false }
            return isReadOnlyShell(command)
        }
        if toolName.hasPrefix("mcp__") {
            let leaf = toolName.split(separator: "_").last.map(String.init)?.lowercased() ?? ""
            let fullLeaf = toolName.components(separatedBy: "__").last?.lowercased() ?? leaf
            return readStyleVerbs.contains { fullLeaf.hasPrefix($0) || fullLeaf.hasPrefix($0 + "_") }
        }
        return false
    }

    static func lockedMessage(toolName: String) -> String {
        "Plan mode: `\(toolName)` can change the workspace or external systems and is blocked until the user approves the plan. Research with read-only tools, then present the plan with `create_plan` and wait for approval."
    }
}
