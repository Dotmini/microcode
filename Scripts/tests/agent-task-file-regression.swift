import Foundation

// Managed task.md (AgentTaskFile.swift): no generic checklist, and old generic steps are never offered as work.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition { failures += 1; print("FAIL: \(message)") }
}

let fresh = AgentTaskFile.managedMarkdown(objective: "ทำแผนที่ Roblox ให้หน่อย", timestamp: "2026-11-21T00:00:00Z")
check(fresh.contains(AgentTaskFile.managedMarker), "managed marker kept (later turns may rewrite it)")
check(fresh.contains("ทำแผนที่ Roblox ให้หน่อย"), "objective recorded")
check(AgentTaskFile.pendingItems(in: fresh).isEmpty, "a fresh task has no pending steps")
check(!AgentTaskFile.isLegacyGenericTemplate(fresh), "new file is not the legacy template")
check(AgentTaskFile.promptContext(fresh) != nil, "new file may reach the prompt")
check(fresh.count < 600, "small: \(fresh.count) chars")
check(AgentTaskFile.managedMarkdown(objective: "  ", timestamp: "t").contains("<!-- Describe the objective here -->"), "empty objective placeholder")

// The file shipped until 2026-11-21 (excerpt with the real lines).
let legacy = """
# Workspace Autonomous Task
<!-- microcode:managed-task -->
## 🚀 Execution Phases & Structured TODOs
- [ ] **1.1** Inspect workspace files, dependencies, and existing architectural patterns.
- [ ] **1.2** Check compiler diagnostics, LSP errors, and current git status.
- [ ] **1.3** Formulate atomic changes and verify preconditions.
- [ ] **4.2** 🔒 **PRIVACY CHECK**: Confirm ZERO API keys, tokens, credentials, or PII are present in `.microcode/` or project files.
- [x] **4.3** Mark task as COMPLETED and report verified results.
"""
check(AgentTaskFile.isLegacyGenericTemplate(legacy), "legacy template recognised")
check(AgentTaskFile.pendingItems(in: legacy).isEmpty, "legacy generic steps are not 'next tasks': \(AgentTaskFile.pendingItems(in: legacy))")
check(AgentTaskFile.promptContext(legacy) == nil, "legacy template never reaches the system prompt")
check(AgentTaskFile.completedCount(in: legacy) == 1, "completed count")

// A plan the agent or user wrote for this task still works.
let real = fresh + "\n- [x] Add RelicSpawner.server.lua\n- [ ] Wire StealRelic RemoteEvent to BaseManager\n- [ ] Playtest in Roblox Studio\n"
check(AgentTaskFile.pendingItems(in: real) == ["Wire StealRelic RemoteEvent to BaseManager", "Playtest in Roblox Studio"], "real steps: \(AgentTaskFile.pendingItems(in: real))")
check(AgentTaskFile.completedCount(in: real) == 1, "real completed count")
// A user's own (unmanaged) task.md is never treated as the legacy template.
check(!AgentTaskFile.isLegacyGenericTemplate("# My plan\n- [ ] Execution Phases & Structured TODOs in my words"), "unmanaged file is not legacy")
check(AgentTaskFile.promptContext("   \n") == nil, "empty file adds nothing")

if failures == 0 { print("AGENT TASK FILE REGRESSION: PASS") } else { print("AGENT TASK FILE REGRESSION: \(failures) FAILURE(S)"); exit(1) }
