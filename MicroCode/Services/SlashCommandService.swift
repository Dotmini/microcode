import Foundation
import Combine
import SwiftUI

enum SlashCommandType: String, CaseIterable, Identifiable {
    case file = "file"
    case compact = "compact"
    case clear = "clear"
    case model = "model"
    case explain = "explain"
    case fix = "fix"
    case test = "test"
    case refactor = "refactor"
    case search = "search"
    case terminal = "terminal"
    case help = "help"
    case plan = "plan"
    case task = "task"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .file: return "Include file content as context"
        case .compact: return "Compact and summarize chat history"
        case .clear: return "Clear chat history"
        case .model: return "Switch AI model"
        case .explain: return "Explain selected code"
        case .fix: return "Fix errors in selected code"
        case .test: return "Write unit tests for selected code"
        case .refactor: return "Refactor selected code"
        case .search: return "Search workspace for query"
        case .terminal: return "Include last terminal output"
        case .help: return "Show list of all slash commands"
        case .plan: return "Toggle plan mode"
        case .task: return "Show/manage tasks"
        }
    }
    
    var icon: String {
        switch self {
        case .file: return "doc"
        case .compact: return "arrow.down.right.and.arrow.up.left"
        case .clear: return "trash"
        case .model: return "cpu"
        case .explain: return "questionmark.circle"
        case .fix: return "wrench.and.screwdriver"
        case .test: return "checkmark.seal"
        case .refactor: return "hammer"
        case .search: return "magnifyingglass"
        case .terminal: return "terminal"
        case .help: return "info.circle"
        case .plan: return "list.bullet.clipboard"
        case .task: return "checklist"
        }
    }
    
    var requiresArgument: Bool {
        switch self {
        case .file, .model, .search: return true
        default: return false
        }
    }
}

class SlashCommandService: ObservableObject {
    static let shared = SlashCommandService()
    
    @Published var suggestions: [SlashCommandType] = []
    @Published var isShowingSuggestions: Bool = false
    
    func parseInput(_ text: String) -> (command: SlashCommandType, argument: String)? {
        guard text.starts(with: "/") else { return nil }
        let parts = text.dropFirst().split(separator: " ", maxSplits: 1)
        guard let commandName = parts.first,
              let command = SlashCommandType(rawValue: String(commandName)) else { return nil }
        
        let argument = parts.count > 1 ? String(parts[1]) : ""
        return (command, argument)
    }
    
    func getSuggestions(for prefix: String) -> [SlashCommandType] {
        guard prefix.starts(with: "/") else { return [] }
        let commandPrefix = prefix.dropFirst().lowercased()
        
        if commandPrefix.isEmpty {
            return SlashCommandType.allCases
        }
        
        return SlashCommandType.allCases.filter { $0.rawValue.lowercased().hasPrefix(commandPrefix) }
    }
    
    func updateSuggestions(for text: String) {
        if text.starts(with: "/") {
            let spaceIndex = text.firstIndex(of: " ")
            if spaceIndex == nil {
                suggestions = getSuggestions(for: text)
                isShowingSuggestions = !suggestions.isEmpty
            } else {
                isShowingSuggestions = false
            }
        } else {
            isShowingSuggestions = false
        }
    }
    
    // Note: Assuming dependencies are passed, this matches the requested signature
    // func executeCommand(_ command: SlashCommandType, argument: String, appState: AppState, agent: AgentService) -> String?
    
    func executeCommand(_ command: SlashCommandType, argument: String) -> String? {
        switch command {
        case .file:
            return "File content for \(argument)" // Placeholder for actual file reading
        case .compact:
            return nil
        case .clear:
            return nil
        case .model:
            return nil
        case .explain:
            return "Explain this code:\n"
        case .fix:
            return "Fix the errors in this code:\n"
        case .test:
            return "Write unit tests for:\n"
        case .refactor:
            return "Refactor this code:\n"
        case .search:
            return "Search results for: \(argument)\n"
        case .terminal:
            return "Terminal output context...\n"
        case .help:
            return "Available Commands:\n" + SlashCommandType.allCases.map { "/\($0.rawValue) - \($0.description)" }.joined(separator: "\n")
        case .plan:
            let trimmedArg = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            let objective = trimmedArg.isEmpty ? "the requested task" : trimmedArg
            return """
            [PLAN MODE — MANDATORY DEEP ANALYSIS BEFORE PLANNING (ห้ามมั่วเด็ดขาด)]:
            Objective: \(objective)

            EXECUTION INSTRUCTIONS:
            1. PHASE 1: THOROUGH RESEARCH & EXPLORATION FIRST:
               - You MUST inspect and read the actual workspace codebase using read tools (`list_directory_tree`, `file_read`, `grep_search`, `find_symbol`, `git_status`) to understand existing architecture, dependencies, data models, and logic flow.
               - NEVER invent file paths or write generic boilerplate steps (such as "Phase 1: Baseline Analysis", "1.1 Inspect files").
               - The plan MUST be grounded in REAL files, REAL functions, and REAL changes discovered during research.
            2. PHASE 2: STRUCTURED & CONCRETE IMPLEMENTATION PLAN:
               - Formulate a detailed plan referencing exact file paths with explicit tags: `[NEW]`, `[MODIFY]`, or `[DELETE]`.
               - Detail specific methods, structs, and logic changes.
               - Specify Open Questions & architectural risks.
               - Specify exact verification commands (e.g. `xcodebuild`, `cargo test`, `swift test`).
            3. PHASE 3: PRESENT FOR USER APPROVAL:
               - Present the plan using `create_plan(title: ..., markdown: ...)` and WAIT for user approval.
            4. ABSOLUTE ZERO CODE MUTATION:
               - STRICTLY DO NOT edit or modify any files until the user explicitly clicks Approve.
            """
        case .task:
            return nil
        }
    }
}
