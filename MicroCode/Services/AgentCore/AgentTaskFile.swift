import Foundation

/// The MicroCode-managed `.microcode/task.md`.
///
/// It used to be a fixed 12-step checklist ("1.2 Check compiler diagnostics…", "4.2 PRIVACY CHECK…") written for
/// every request, and the next-step button sent "Continue working on the next pending task: 1.2 …". Agents then
/// performed the checklist instead of the user's task: on 2026-11-20 a Roblox chat ran `print("Roblox Luau syntax
/// check")` as "verification" and overwrote task.md four times with "COMPLETED ✅" reports. Now the file only holds
/// the objective; concrete steps appear only when the agent writes a plan for genuinely multi-step work.
enum AgentTaskFile {
    static let managedMarker = "<!-- microcode:managed-task -->"

    static func managedMarkdown(objective: String, timestamp: String) -> String {
        let trimmed = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeObjective = trimmed.isEmpty ? "<!-- Describe the objective here -->" : String(trimmed.prefix(8_000))
        return """
        # Current Task
        \(managedMarker)

        - **Objective**: \(safeObjective)
        - **Last Updated**: \(timestamp)

        ## Plan
        <!-- Only for multi-step work: write the concrete steps for THIS objective as `- [ ]` items and check one off only after a tool result proves it. Leave empty for single-step requests. -->
        """
    }

    /// The step texts of the old generic template (without the "**1.2**" numbering).
    private static let legacyGenericSteps: [String] = [
        "Inspect workspace files, dependencies, and existing architectural patterns.",
        "Check compiler diagnostics, LSP errors, and current git status.",
        "Formulate atomic changes and verify preconditions.",
        "Implement core changes surgically using targeted edit tools.",
        "Ensure full backward compatibility and adhere to project code style.",
        "Preserve all existing functionality and comments.",
        "Run build/compilation tool and ensure zero errors.",
        "Run test suite to verify no regressions.",
        "Verify live app behavior or inspect UI elements.",
        "Verify git diff to ensure no unexpected files were touched.",
        "Confirm ZERO API keys, tokens, credentials, or PII are present in `.microcode/` or project files.",
        "Mark task as COMPLETED and report verified results."
    ]

    static func isLegacyGenericStep(_ item: String) -> Bool {
        legacyGenericSteps.contains { item.contains($0) }
    }

    /// True when the file is (still) the old generic template: nothing in it is specific to the task.
    static func isLegacyGenericTemplate(_ markdown: String) -> Bool {
        markdown.contains(managedMarker) && markdown.contains("Execution Phases & Structured TODOs")
    }

    /// Unchecked `- [ ]` items the agent or the user wrote; the old template's generic steps are skipped.
    static func pendingItems(in markdown: String) -> [String] {
        markdown.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- [ ]") else { return nil }
            let item = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            return item.isEmpty || isLegacyGenericStep(item) ? nil : item
        }
    }

    static func completedCount(in markdown: String) -> Int {
        markdown.components(separatedBy: .newlines).filter {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]")
        }.count
    }

    /// What the system prompt may include from task.md: nothing for the old generic template.
    static func promptContext(_ markdown: String) -> String? {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLegacyGenericTemplate(trimmed) else { return nil }
        return trimmed
    }
}
