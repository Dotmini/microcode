import Foundation

/// What a short follow-up message ("run", "ไหน", "ต่อ") asks of the work already in the conversation.
///
/// Before this existed every such nudge was treated as "continue the earlier request". When that earlier
/// request had asked for file changes, a plain "run" inherited the requirement, and the harness kept telling
/// the model "filesModified is STILL EMPTY — call file_write now" until it wrote new files instead of running
/// the existing ones (2026-11-18 Arc chat: "run" → more_use_cases.ar, "run Benchmark" → benchmark.ar, …).
enum FollowUpKind: Equatable {
    /// Not a nudge: a request of its own ("ทดสอบ เขียน WebApp ด้วย Arc", "build a REST API").
    case newRequest
    /// "ต่อ", "continue", "ทำเลย": carry on with the earlier request.
    case resume
    /// "run", "รันสิ", "run Benchmark", "test", "build", "preview": act on the work that already exists.
    case operate
    /// "ไหน", "ไม่เห็นมี", "ผลลัพธ์ล่ะ": the user cannot see a result the agent claimed.
    case showResult
}

enum FollowUpIntent {
    private static let operateMarkers = [
        "run", "รัน", "build", "บิลด์", "บิวด์", "คอมไพล์", "compile", "test", "ทดสอบ", "benchmark", "เบนช์",
        "preview", "พรีวิว", "launch", "open", "เปิด", "execute", "start", "สตาร์ท"
    ]
    private static let showResultMarkers = [
        "ไหน", "ไม่เห็น", "ผลลัพธ์", "ผลลัพฑ์", "ผลลัพท์", "output", "result", "where", "show me", "ขอดู"
    ]
    /// Words that turn a nudge into a request for new work: "ทดสอบ เขียน WebApp", "build a todo app".
    private static let newWorkMarkers = [
        "เขียน", "สร้าง", "เพิ่ม", "ออกแบบ", "ทำใหม่", "แก้ไข", "แก้โค้ด",
        "write", "create", "add", "make", "implement", "generate", "design", "a", "an", "new"
    ]

    /// Classifies a message that `AgentService.isContinuationRequest` already accepted as a short nudge.
    static func classify(nudge content: String) -> FollowUpKind {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return .resume }
        let words = Set(text.split(whereSeparator: { $0 == " " || $0.isPunctuation }).map(String.init))
        if newWorkMarkers.contains(where: { marker in
            marker.unicodeScalars.allSatisfy(\.isASCII) ? words.contains(marker) : text.contains(marker)
        }) {
            return .newRequest
        }
        if operateMarkers.contains(where: { contains(text, words, $0) }) { return .operate }
        if showResultMarkers.contains(where: { contains(text, words, $0) }) { return .showResult }
        return .resume
    }

    /// Latin markers match whole words ("run" in "run สิ", not "running" or "rerun"); Thai has no spaces.
    private static func contains(_ text: String, _ words: Set<String>, _ marker: String) -> Bool {
        guard marker.unicodeScalars.allSatisfy(\.isASCII) else { return text.contains(marker) }
        if marker.contains(" ") { return text.contains(marker) }
        return words.contains(marker) || words.contains { $0.hasPrefix(marker) && $0.dropFirst(marker.count).allSatisfy { !$0.isASCII } }
    }

    /// The earlier request's "you must change files" requirement carries over only when the user asks to carry on
    /// (or asks where the result is) and nothing has been written since that request. Running, building, testing or
    /// previewing never requires new edits.
    static func inheritsMutation(_ kind: FollowUpKind, objectiveRequiredMutation: Bool, workspaceChangedSinceObjective: Bool) -> Bool {
        switch kind {
        case .resume, .showResult:
            return objectiveRequiredMutation && !workspaceChangedSinceObjective
        case .operate, .newRequest:
            return false
        }
    }

    /// The objective the harness pins for this turn (complexity, tool selection, history folding).
    static func objective(kind: FollowUpKind, content: String, earlierRequest: String?) -> String {
        guard let earlier = earlierRequest?.trimmingCharacters(in: .whitespacesAndNewlines), !earlier.isEmpty else {
            return content
        }
        switch kind {
        case .newRequest:
            return content
        case .resume:
            return earlier
        case .operate, .showResult:
            return content + "\n\n(Follow-up to the earlier request: " + String(earlier.prefix(1_500)) + ")"
        }
    }

    /// A one-line instruction added to the model's copy of the user turn (the chat shows the user's own words).
    static func turnNote(kind: FollowUpKind, earlierRequest: String?) -> String? {
        let earlier = earlierRequest.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)) } ?? ""
        let about = earlier.isEmpty ? "" : " (earlier request: \"\(earlier)\")"
        switch kind {
        case .newRequest:
            return nil
        case .operate:
            return "[MicroCode follow-up: this message refers to the work already done in this conversation\(about). Run, build, test or open that existing work now and reply with the real output (trimmed, in a code block) and whether it passed. Do not create new files or rewrite working code unless the run fails and needs a fix.]"
        case .showResult:
            return "[MicroCode follow-up: the user cannot see the result you described\(about). Check what actually exists (read the files or re-run the command) and show it: clickable file links and the real output. If something you said was done was not actually done, say so plainly and do it now.]"
        case .resume:
            return earlier.isEmpty ? nil : "[MicroCode follow-up: continue the earlier request\(about) from where it stopped. Do not redo completed steps.]"
        }
    }

    /// A short digest of what a past assistant turn actually ran, for the conversation history. History used to keep
    /// only tool names ("shell(ok)"), so a later "ไหน" or "run ผลลัพธ์มา" had no real output to point to.
    static func evidenceDigest(_ runs: [(name: String, success: Bool, output: String)], maxRuns: Int = 3, maxChars: Int = 600) -> String? {
        let recent = runs.suffix(maxRuns)
        guard !recent.isEmpty else { return nil }
        let perRun = max(120, maxChars / recent.count)
        let lines = recent.map { run -> String in
            let output = run.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let excerpt: String
            if output.isEmpty {
                excerpt = "(no output)"
            } else if output.count <= perRun {
                excerpt = output
            } else {
                excerpt = "…" + String(output.suffix(perRun))
            }
            return "\(run.name)(\(run.success ? "ok" : "error")): \(excerpt.replacingOccurrences(of: "\n", with: " ⏎ "))"
        }
        return "[Real output of commands run in this turn]\n" + lines.joined(separator: "\n")
    }
}
