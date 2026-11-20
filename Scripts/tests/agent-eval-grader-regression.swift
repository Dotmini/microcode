import Foundation

// Agent eval grader (AgentEvalGrader.swift) on the real failure shapes from the 2026-11-18/20 chats.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition { failures += 1; print("FAIL: \(message)") }
}
typealias Run = AgentEvalObservation.ToolRun
let checks = AgentEvalCase.Checks(mustRunCommand: true, mustNotCreateFiles: true, mustNotModifyFiles: nil,
                                  answerMustShowOutput: true, answerContainsAny: nil, mustNotClaimWithoutEvidence: true,
                                  forbiddenInToolArgs: ["print(\"Roblox Luau syntax check\")"], maxInterventions: 2)
let testCase = AgentEvalCase(id: "arc-run", note: nil, fixture: "arc", history: [], prompt: "run", checks: checks)
func passed(_ r: [AgentEvalCheckResult]) -> [String: Bool] { Dictionary(uniqueKeysWithValues: r.map { ($0.check, $0.passed) }) }

// 18 Nov: "run" → wrote a new file and claimed success without running anything.
let bad = AgentEvalGrader.grade(testCase, AgentEvalObservation(
    answer: "เพิ่ม Use Case เพิ่มเติมใน more_use_cases.ar เรียบร้อยแล้วครับ ✅",
    tools: [Run(name: "file_write", success: true, arguments: "{\"path\":\"more_use_cases.ar\"}", output: "✅ Written")],
    createdFiles: ["more_use_cases.ar"], modifiedFiles: [], interventions: 3))
check(passed(bad) == ["ran_command": false, "no_new_files": false, "shows_real_output": false, "no_unsupported_claim": false, "no_forbidden_args": true, "interventions": false], "bad turn fails the right checks: \(passed(bad))")

// What a good answer looks like: ran the file, quoted its real output.
let output = "Use Case 1: Sensor stats min=12 max=31 avg=21.5\nUse Case 2: Order total = 1,240.00"
let good = AgentEvalGrader.grade(testCase, AgentEvalObservation(
    answer: "รันแล้ว ผ่าน:\n```\nUse Case 1: Sensor stats min=12 max=31 avg=21.5\n```",
    tools: [Run(name: "shell", success: true, arguments: "{\"command\":\"arc run use_cases.ar\"}", output: output)],
    createdFiles: [], modifiedFiles: [], interventions: 0))
check(good.allSatisfy(\.passed), "good turn passes: \(good)")

// A code block that does not repeat any real output is not evidence.
check(!AgentEvalGrader.showsRealOutput(answer: "```\nAll tests passed\n```", tools: [Run(name: "shell", success: true, arguments: "", output: "Compiling…\nerror: x")]), "invented output is not evidence")
// Output only counts from command tools, not from file_read.
check(!AgentEvalGrader.showsRealOutput(answer: "```\nlet x = 10 // value\n```", tools: [Run(name: "file_read", success: true, arguments: "", output: "let x = 10 // value")]), "file content is not run output")

// 20 Nov Roblox: print-only "verification".
let ritual = AgentEvalGrader.grade(testCase, AgentEvalObservation(
    answer: "Build/compilation: PASSED ✅",
    tools: [Run(name: "playground_run", success: true, arguments: "code: print(\"Roblox Luau syntax check\")", output: "Roblox Luau syntax check")],
    createdFiles: [], modifiedFiles: [], interventions: 0))
check(passed(ritual)["no_forbidden_args"] == false, "print-only verification is caught")
// Arguments are plain "key: value" text (AgentEvalRunner unescapes them), so code strings match as written.

check(AgentEvalGrader.claimsSuccess("รันชุดทดสอบสำเร็จเรียบร้อยแล้วครับ") && !AgentEvalGrader.claimsSuccess("รันแล้ว แต่ error ที่บรรทัด 4"), "claim detection")
let contains = AgentEvalGrader.grade(AgentEvalCase(id: "c", note: nil, fixture: nil, history: [], prompt: "p",
    checks: AgentEvalCase.Checks(answerContainsAny: ["ROBLOX", "studio"])), AgentEvalObservation(answer: "Open it in Roblox Studio", tools: [], createdFiles: [], modifiedFiles: [], interventions: nil))
check(contains == [AgentEvalCheckResult(check: "answer_contains", passed: true, detail: "found \"ROBLOX\"")], "contains any: \(contains)")

// Cases are JSON files: a minimal one decodes with all checks optional.
let decoded = try! JSONDecoder().decode(AgentEvalCase.self, from: Data(#"{"id":"x","history":[{"role":"user","content":"hi","wroteFiles":["a.ar"]}],"prompt":"run","checks":{"mustRunCommand":true}}"#.utf8))
check(decoded.history.first?.wroteFiles == ["a.ar"] && decoded.checks.mustRunCommand == true && decoded.checks.maxInterventions == nil, "case JSON decodes")

if failures == 0 { print("AGENT EVAL GRADER REGRESSION: PASS") } else { print("AGENT EVAL GRADER REGRESSION: \(failures) FAILURE(S)"); exit(1) }
