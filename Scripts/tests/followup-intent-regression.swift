import Foundation

// Follow-up intent (FollowUpIntent.swift). Cases are the real messages from the 2026-11-17/18/19 agent chats
// where "run" produced new files instead of output and "ไหน" got another success claim.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("FAIL: \(message)")
    }
}
func expect(_ text: String, _ kind: FollowUpKind) {
    let got = FollowUpIntent.classify(nudge: text)
    check(got == kind, "\"\(text)\" → \(got), expected \(kind)")
}

// MARK: act on existing work
for text in ["run", "run ", "Run สิ", "run ผลลัพธ์มา", "run Benchmark ", "ไหน Run สิ", "ไหน RUn ", "Run. it ",
             "รัน", "รันสิ", "run หน่อย", "ไหน preview", "build สิ", "test it", "ลองรัน", "คอมไพล์",
             "ไหน ทำให้สิ เปิด อยู่  ROblox studio"] {
    expect(text, .operate)
}
// MARK: the user cannot see the claimed result
for text in ["ไหน", "ไหนวะ", "ไหนครับ", "ไม่เห็นมี", "ไหนผลลัพฑ์export PDF มา"] {
    expect(text, .showResult)
}
// MARK: carry on
for text in ["ต่อ", "ต่อสิ", "continue", "ทำเลย", "แก้สิ", "ยังไม่แก้", "keep going"] {
    expect(text, .resume)
}
// MARK: new work that merely starts with a nudge word
for text in ["ทดสอบ เขียน WebApp ด้วย Arc 100%'", "build a rest api", "test สร้างหน้า login", "run and add logging"] {
    expect(text, .newRequest)
}
// Whole-word Latin matching: "rerun"/"running" are not "run", "testing" is not "test" either.
check(FollowUpIntent.classify(nudge: "ต่อ running") == .resume, "\"running\" is not the run command")

// MARK: the earlier "change files" requirement
check(!FollowUpIntent.inheritsMutation(.operate, objectiveRequiredMutation: true, workspaceChangedSinceObjective: false),
      "run never inherits the requirement to write files")
check(!FollowUpIntent.inheritsMutation(.resume, objectiveRequiredMutation: true, workspaceChangedSinceObjective: true),
      "continue after files were written does not force more edits")
check(FollowUpIntent.inheritsMutation(.resume, objectiveRequiredMutation: true, workspaceChangedSinceObjective: false),
      "continue before anything was written still requires the edits")
check(FollowUpIntent.inheritsMutation(.showResult, objectiveRequiredMutation: true, workspaceChangedSinceObjective: false),
      "\"ไหน\" after a false claim (nothing written) requires the edits")
check(!FollowUpIntent.inheritsMutation(.showResult, objectiveRequiredMutation: true, workspaceChangedSinceObjective: true),
      "\"ไหน\" after real edits only needs evidence")
check(!FollowUpIntent.inheritsMutation(.resume, objectiveRequiredMutation: false, workspaceChangedSinceObjective: false),
      "nothing to inherit from a read-only request")

// MARK: pinned objective
let earlier = "เขียน Arc อีก หลายๆ Use Case"
check(FollowUpIntent.objective(kind: .resume, content: "ต่อ", earlierRequest: earlier) == earlier, "resume pins the earlier request")
let runObjective = FollowUpIntent.objective(kind: .operate, content: "run Benchmark", earlierRequest: earlier)
check(runObjective.hasPrefix("run Benchmark") && runObjective.contains(earlier), "run pins itself, with the earlier request as context")
check(FollowUpIntent.objective(kind: .newRequest, content: "build a rest api", earlierRequest: earlier) == "build a rest api", "a new request pins only itself")
check(FollowUpIntent.objective(kind: .operate, content: "run", earlierRequest: nil) == "run", "no earlier request")

// MARK: turn notes
let runNote = FollowUpIntent.turnNote(kind: .operate, earlierRequest: earlier) ?? ""
check(runNote.contains("real output") && runNote.contains("Do not create new files") && runNote.contains(earlier), "run note: \(runNote)")
let whereNote = FollowUpIntent.turnNote(kind: .showResult, earlierRequest: earlier) ?? ""
check(whereNote.contains("was not actually done"), "where note asks for honesty: \(whereNote)")
check(FollowUpIntent.turnNote(kind: .newRequest, earlierRequest: earlier) == nil, "no note for a new request")
check(FollowUpIntent.turnNote(kind: .resume, earlierRequest: nil) == nil, "no resume note without an earlier request")

// MARK: run evidence kept in history
check(FollowUpIntent.evidenceDigest([]) == nil, "no runs, no digest")
let long = String(repeating: "x", count: 5_000) + "\nBenchmark: 42 ms"
let digest = FollowUpIntent.evidenceDigest([
    (name: "file_read", success: true, output: "ignored older"),
    (name: "shell", success: true, output: "Hello Ardium!\n"),
    (name: "shell", success: false, output: "error: could not find `Cargo.toml`"),
    (name: "shell", success: true, output: long)
]) ?? ""
check(!digest.contains("ignored older"), "only the last 3 runs")
check(digest.contains("shell(ok): Hello Ardium!") && digest.contains("shell(error): error: could not find"), "status and output: \(digest)")
check(digest.contains("Benchmark: 42 ms") && digest.count < 900, "long output keeps its tail and stays bounded (\(digest.count))")

if failures == 0 {
    print("FOLLOW-UP INTENT REGRESSION: PASS")
} else {
    print("FOLLOW-UP INTENT REGRESSION: \(failures) FAILURE(S)")
    exit(1)
}
