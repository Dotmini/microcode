import Foundation

var failures = 0
func expect(_ cond: Bool, _ msg: String) {
    if cond { print("  ✓ \(msg)") } else { print("  ✗ \(msg)"); failures += 1 }
}
let run = ClaimEvidenceItem(executed: true, mutated: false, exportedPDF: false, success: true)
let failedRun = ClaimEvidenceItem(executed: true, mutated: false, exportedPDF: false, success: false)
let edit = ClaimEvidenceItem(executed: false, mutated: true, exportedPDF: false, success: true)
let read = ClaimEvidenceItem(executed: false, mutated: false, exportedPDF: false, success: true)

print("claim check")
expect(AgentClaimCheck.mismatch(answer: "All tests passed ✅", evidence: [read])?.claim == .ranOrPassed, "pass claim with no command → mismatch")
expect(AgentClaimCheck.mismatch(answer: "เทสผ่านทั้งหมดครับ", evidence: [failedRun])?.claim == .ranOrPassed, "Thai pass claim after failing run → mismatch")
expect(AgentClaimCheck.mismatch(answer: "Tests passed.\n```\n2 passed\n```", evidence: [failedRun, run]) == nil, "pass claim after a later passing run → ok")
expect(AgentClaimCheck.mismatch(answer: "ผลรันเทส: ไม่ผ่าน 1 ข้อ (test_discount)\n```\nAssertionError\n```", evidence: [failedRun]) == nil, "honest failure report → ok")
expect(AgentClaimCheck.mismatch(answer: "I updated calc.py to fix the bug.", evidence: [run])?.claim == .changedFiles, "edit claim without edit → mismatch")
expect(AgentClaimCheck.mismatch(answer: "แก้ไฟล์ calc.py แล้วครับ", evidence: [edit, run]) == nil, "edit claim with edit → ok")
expect(AgentClaimCheck.mismatch(answer: "The PDF has been exported to report.pdf", evidence: [edit])?.claim == .exportedPDF, "PDF claim without export → mismatch")
expect(AgentClaimCheck.mismatch(answer: "This function computes a discount.", evidence: []) == nil, "plain explanation → no claim")
expect(AgentClaimCheck.mismatch(answer: "<thought>tests passed</thought>The file defines one class.", evidence: []) == nil, "claims inside thought blocks are ignored")
expect(AgentClaimCheck.prompt(for: .init(claim: .ranOrPassed, reason: "x")).contains("CRITICAL") == false, "prompt is neutral")

print("policy")
let defaults = UserDefaults(suiteName: "claim-check-test-\(UUID().uuidString)")!
expect(AgentHarnessPolicy.legacyInterventionsEnabled(environment: [:], defaults: defaults) == false, "legacy off by default")
defaults.set(true, forKey: AgentHarnessPolicy.defaultsKey)
expect(AgentHarnessPolicy.legacyInterventionsEnabled(environment: [:], defaults: defaults), "user default turns legacy on")
expect(AgentHarnessPolicy.legacyInterventionsEnabled(environment: ["MICROCODE_AGENT_LEGACY_HARNESS": "0"], defaults: defaults) == false, "env overrides user default")
expect(AgentHarnessPolicy.stripEmptyThoughtTags("<thought></thought>\n\nDone.") == "Done.", "empty thought stripped")
expect(AgentHarnessPolicy.stripEmptyThoughtTags("<thought>plan</thought>\nDone.") == "<thought>plan</thought>\nDone.", "non-empty thought kept")

print(failures == 0 ? "PASS" : "FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
