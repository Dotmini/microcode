import Foundation

/// Nesting depth of the code currently running: 0 = main agent, 1 = a sub-agent it spawned, …
/// Task-local, so every task a sub-agent starts (tool calls, swarm dispatch) inherits its depth.
enum SubAgentContext {
    @TaskLocal static var depth: Int = 0
}

/// Bounds on sub-agent fan-out. Without them an unknown sub-agent type received every tool and any
/// sub-agent could spawn up to 6 more per swarm call with no depth or global limit (runaway cost/recursion).
enum SubAgentSpawnPolicy {
    /// Main agent → sub-agent (depth 1) → one more level of delegation (depth 2). Depth-2 agents cannot spawn.
    static let maxDepth = 2
    /// Sub-agents running at the same time across the whole app.
    static let maxConcurrent = 8

    enum Decision: Equatable {
        case allow
        case tooDeep(depth: Int)
        case tooManyRunning(running: Int)

        var rejectionReason: String? {
            switch self {
            case .allow:
                return nil
            case .tooDeep(let depth):
                return "Sub-agent not started: delegation depth limit reached (depth \(depth), max \(SubAgentSpawnPolicy.maxDepth)). Do this work yourself instead of spawning another sub-agent."
            case .tooManyRunning(let running):
                return "Sub-agent not started: \(running) sub-agents are already running (max \(SubAgentSpawnPolicy.maxConcurrent)). Wait for some to finish (manage_subagents) or do the work yourself."
            }
        }
    }

    /// `spawnerDepth` is the depth of the agent asking to spawn (SubAgentContext.depth).
    static func decide(spawnerDepth: Int, runningCount: Int) -> Decision {
        if spawnerDepth >= maxDepth { return .tooDeep(depth: spawnerDepth) }
        if runningCount >= maxConcurrent { return .tooManyRunning(running: runningCount) }
        return .allow
    }

    /// Tools for a sub-agent type the model made up (not registered via define_subagent): read & search only,
    /// plus MCP tools. Registered archetypes keep their own explicit tool lists.
    static let unknownTypeTools: [String] = [
        "file_read", "multi_file_read", "list_directory_tree", "grep_search", "file_search",
        "find_symbol", "codebase_search", "get_diagnostics", "git_status", "inspect_image", "extract_pdf", "mcp"
    ]
}
