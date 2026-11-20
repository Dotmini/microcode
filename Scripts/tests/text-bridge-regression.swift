import Foundation

// Text-bridge context (AIStreamPrimitives.swift): TextBridgeContextBudget + TextBridgeTranscript.
// 2026-11-21: the Vertex AI Search bridge cut persona+context+tools at 14,000 chars, so the tool list and the
// workspace path never reached the model; headless CLIs got tool turns as raw `_mc_structured_turn` JSON.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("FAIL: \(message)")
    }
}

let intro = "You are MicroCode AI Assistant inside MicroCode macOS IDE.\nRespond in the user's language."
let persona = "You are MicroCode AI — a senior full-stack software engineer.\n## Rules\n"
    + (1...300).map { "- rule \($0): " + String(repeating: "x", count: 40) }.joined(separator: "\n")   // ≈14.3K
let dynamic = "## Active Project Workspace\nRoot: /Volumes/MAC/ROBLOXGAME\n\n## Memory\n"
    + (1...400).map { "memory line \($0) " + String(repeating: "m", count: 60) }.joined(separator: "\n")  // ≈31K
let system = persona + AISystemPromptLayout.dynamicBoundary + "\n\n" + dynamic
let catalog = "## TOOL BRIDGE\n### Available Client-Side MicroCode Tools (45 total):\n"
    + (1...45).map { "- `tool_\($0)(path:string*, start_line:integer?)`: Reads or edits things in the workspace quickly." }.joined(separator: "\n")
check(persona.count > 14_000, "fixture: persona alone exceeds the limit like the real one (\(persona.count))")

let out = TextBridgeContextBudget.compose(intro: intro, systemPrompt: system, toolCatalog: catalog, limit: 14_000)
check(out.count <= 14_000, "fits the hard limit: \(out.count)")
check((1...45).allSatisfy { out.contains("`tool_\($0)(") }, "every tool survives")
check(out.contains("Root: /Volumes/MAC/ROBLOXGAME"), "workspace path survives")
check(out.contains("You are MicroCode AI — a senior"), "persona head survives")
check(out.hasPrefix("You are MicroCode AI Assistant"), "intro first")
check(out.contains(TextBridgeContextBudget.trimNote), "trimming is marked")
check(!out.contains(AISystemPromptLayout.dynamicBoundary), "no internal boundary marker leaks")

// Old behavior for contrast: prefix(14_000) of intro+persona+dynamic+catalog has no tools and no workspace.
let old = String(([intro, system, catalog].joined(separator: "\n\n")).prefix(14_000))
check(!old.contains("`tool_1(") && !old.contains("ROBLOXGAME"), "fixture reproduces the 14K bug")

// Small prompts pass through untouched (no trim note, all parts present).
let small = TextBridgeContextBudget.compose(intro: "Hi", systemPrompt: "Rules" + AISystemPromptLayout.dynamicBoundary + "\nWS: /a", toolCatalog: "- `t()`", limit: 14_000)
check(small == "Hi\n\nRules\n\nWS: /a\n\n- `t()`", "small prompt unchanged: \(small.debugDescription)")
// No boundary, no tools.
let plain = TextBridgeContextBudget.compose(intro: "Hi", systemPrompt: String(repeating: "p\n", count: 20_000), toolCatalog: nil, limit: 5_000)
check(plain.count <= 5_000 && plain.hasPrefix("Hi\n\np"), "plain prompt fits: \(plain.count)")
// A huge catalog cannot starve everything else: at most 70% of the room.
let hugeCatalog = (1...2_000).map { "- `t\($0)()`: d" }.joined(separator: "\n")
let crowded = TextBridgeContextBudget.compose(intro: "Hi", systemPrompt: system, toolCatalog: hugeCatalog, limit: 14_000)
check(crowded.count <= 14_000 && crowded.contains("Root: /Volumes/MAC/ROBLOXGAME"), "huge catalog still leaves room for the workspace")
// fitLines keeps whole lines and never exceeds the limit.
let fitted = TextBridgeContextBudget.fitLines("aaa\nbbb\nccc\n" + String(repeating: "d", count: 200), limit: 60)
check(fitted.count <= 60 && fitted.hasPrefix("aaa\nbbb\nccc") && fitted.hasSuffix(TextBridgeContextBudget.trimNote), "fitLines: \(fitted.debugDescription)")
check(TextBridgeContextBudget.fitLines("abc", limit: 3) == "abc" && TextBridgeContextBudget.fitLines("abcdef", limit: 2).isEmpty, "fitLines edges")

// MARK: transcript rendering for text backends
let calls = TextBridgeTranscript.toolCalls(text: "Running it.", calls: [(name: "shell", argumentsJSON: "{\"command\":\"arc run a.ar\"}")])
check(calls == "Running it.\n<tool_call>{\"name\": \"shell\", \"arguments\": {\"command\":\"arc run a.ar\"}}</tool_call>", "tool calls: \(calls)")
let results = TextBridgeTranscript.toolResults([(name: "shell", success: false, output: "error: x")], directive: "Kernel directive: next")
check(results == "<tool_response name=\"shell\" status=\"error\">\nerror: x\n</tool_response>\n\nKernel directive: next", "tool results: \(results)")
let longResult = TextBridgeTranscript.toolResults([(name: "file_read", success: true, output: String(repeating: "z", count: 30_000))], directive: "")
check(longResult.contains("...(truncated)") && longResult.count < 24_200, "long output truncated")

if failures == 0 {
    print("TEXT BRIDGE REGRESSION: PASS")
} else {
    print("TEXT BRIDGE REGRESSION: \(failures) FAILURE(S)")
    exit(1)
}
