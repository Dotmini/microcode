import Foundation

/// P1 harness policy: the model decides when its turn is done. The legacy interventions
/// (inspect/build/launch/inferred-action fallbacks, "CRITICAL …" follow-through nags and the
/// "Kernel directive / Instruction" text after every tool batch) stay available behind a flag.
///
/// Off by default. Turn on with the `agent.harness.legacyInterventions` user default, or for one
/// process with `MICROCODE_AGENT_LEGACY_HARNESS=1` (used by the replay eval to compare).
enum AgentHarnessPolicy {
    static let defaultsKey = "agent.harness.legacyInterventions"
    static let environmentKey = "MICROCODE_AGENT_LEGACY_HARNESS"

    static func legacyInterventionsEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if let raw = environment[environmentKey]?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty {
            return ["1", "true", "yes", "on"].contains(raw)
        }
        return defaults.bool(forKey: defaultsKey)
    }

    /// Empty `<thought></thought>` pairs some models emit carry nothing and leak into answers.
    /// Non-empty thought blocks are kept: the chat view renders them as collapsible reasoning.
    static func stripEmptyThoughtTags(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(
            of: "<(thought|thinking|think)>\\s*</\\1>",
            with: "",
            options: .regularExpression
        )
        return cleaned == text ? text : cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One tool result of the current turn, reduced to what the claim check needs.
struct ClaimEvidenceItem: Equatable {
    var executed: Bool      // build / test / run / shell-like execution
    var mutated: Bool       // wrote or edited a workspace file
    var exportedPDF: Bool
    var success: Bool
}

/// Compares what the final answer says happened with what the tools of this turn actually did.
/// It never decides that the task is finished — it only catches an answer that reports results
/// the turn has no evidence for, and asks once, neutrally, to either produce the evidence or
/// correct the answer.
enum AgentClaimCheck {
    enum Claim: String, CaseIterable, Equatable {
        case ranOrPassed     // "tests passed", "ran successfully", "build succeeded"
        case changedFiles    // "I updated calc.py", "แก้ไฟล์แล้ว"
        case exportedPDF     // "exported the PDF"
    }

    struct Mismatch: Equatable {
        var claim: Claim
        var reason: String
    }

    static func claims(in answer: String) -> Set<Claim> {
        let text = AIClaimText.visible(answer).lowercased()
        guard !text.isEmpty else { return [] }
        var found = Set<Claim>()
        let ran = [
            "tests passed", "test passed", "all tests pass", "passed successfully", "ran successfully",
            "executed successfully", "build succeeded", "build successful", "build passed", "compiled successfully",
            "runs successfully", "run succeeded",
            "รันผ่าน", "รันสำเร็จ", "เทสผ่าน", "ทดสอบผ่าน", "ผ่านทั้งหมด", "build ผ่าน", "build สำเร็จ", "คอมไพล์ผ่าน",
            "รันได้แล้ว"
        ]
        if ran.contains(where: text.contains) { found.insert(.ranOrPassed) }
        let changed = [
            "i updated", "i've updated", "i have updated", "i modified", "i've modified", "i edited", "i've edited",
            "i created", "i've created", "i fixed", "i've fixed", "i wrote", "have been updated", "has been updated",
            "has been created", "have been created", "has been fixed", "file has been",
            "แก้ไขไฟล์", "แก้ไฟล์", "สร้างไฟล์", "เขียนไฟล์", "อัปเดตไฟล์", "ได้ทำการแก้ไข", "แก้ไขเรียบร้อย", "แก้ไขแล้ว", "สร้างเรียบร้อย"
        ]
        if changed.contains(where: text.contains) { found.insert(.changedFiles) }
        let exported = ["exported the pdf", "pdf has been", "pdf exported", "export pdf สำเร็จ", "ส่งออก pdf", "สร้าง pdf", "export เป็น pdf"]
        if exported.contains(where: text.contains) { found.insert(.exportedPDF) }
        return found
    }

    /// The first claim with no supporting evidence in this turn, or nil.
    static func mismatch(answer: String, evidence: [ClaimEvidenceItem]) -> Mismatch? {
        let found = claims(in: answer)
        if found.contains(.ranOrPassed) {
            let runs = evidence.filter(\.executed)
            if runs.isEmpty {
                return Mismatch(claim: .ranOrPassed, reason: "the answer reports a run/test/build result, but no command was executed in this turn")
            }
            if let last = runs.last, !last.success {
                return Mismatch(claim: .ranOrPassed, reason: "the answer reports a passing run, but the most recent command in this turn failed")
            }
        }
        if found.contains(.changedFiles), !evidence.contains(where: { $0.mutated && $0.success }) {
            return Mismatch(claim: .changedFiles, reason: "the answer says files were changed, but no file was written or edited in this turn")
        }
        if found.contains(.exportedPDF), !evidence.contains(where: { $0.exportedPDF && $0.success }) {
            return Mismatch(claim: .exportedPDF, reason: "the answer says a PDF was exported, but export_pdf did not succeed in this turn")
        }
        return nil
    }

    /// Neutral, single prompt: no "CRITICAL", no instruction to keep editing.
    static func prompt(for mismatch: Mismatch) -> String {
        """
        Check before finishing: \(mismatch.reason). \
        If it did happen, run the command or tool now and report its real output; \
        otherwise rewrite the answer so it states only what this turn actually did and observed. \
        Do not change files just to make the claim true unless the user asked for that change.
        """
    }

    /// Tools ran but the model wrote nothing for the user.
    static let emptyAnswerPrompt = """
    You ran tools but wrote no answer. Reply to the user now with what you found or did, \
    quoting the relevant real output.
    """
}

/// Visible answer text (thought blocks and tool-call artifacts removed) without depending on AIClient.
enum AIClaimText {
    static func visible(_ text: String) -> String {
        var cleaned = text.replacingOccurrences(
            of: "<(?:thought|thinking|think)>[\\s\\S]*?</(?:thought|thinking|think)>",
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(of: "<(?:thought|thinking|think)>[\\s\\S]*$", with: "", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
