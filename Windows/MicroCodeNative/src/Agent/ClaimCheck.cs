// P1 harness policy (mirror of MicroCode/Services/AgentCore/AgentClaimCheck.swift): the model decides when it is done.
// The harness only checks, once, that the final answer does not report a run / file change / PDF export that this turn
// has no tool evidence for. It never forces the agent to keep working and never edits files on the model's behalf.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace MicroCode.Views
{
    /// <summary>One tool step of the current turn, reduced to what the claim check needs.</summary>
    public class ClaimEvidence
    {
        public bool Executed, Mutated, ExportedPdf, Ok;
    }

    public static class ClaimCheck
    {
        public const string RanOrPassed = "ran", ChangedFiles = "changed", ExportedPdf = "pdf";

        public const string EmptyAnswerPrompt = "You ran tools but wrote no answer. Reply to the user now with what you found or did, quoting the relevant real output.";

        static readonly string[] Ran = {
            "tests passed", "test passed", "all tests pass", "passed successfully", "ran successfully",
            "executed successfully", "build succeeded", "build successful", "build passed", "compiled successfully",
            "runs successfully", "run succeeded",
            "รันผ่าน", "รันสำเร็จ", "เทสผ่าน", "ทดสอบผ่าน", "ผ่านทั้งหมด", "build ผ่าน", "build สำเร็จ", "คอมไพล์ผ่าน", "รันได้แล้ว" };
        static readonly string[] Changed = {
            "i updated", "i've updated", "i have updated", "i modified", "i've modified", "i edited", "i've edited",
            "i created", "i've created", "i fixed", "i've fixed", "i wrote", "have been updated", "has been updated",
            "has been created", "have been created", "has been fixed", "file has been",
            "แก้ไขไฟล์", "แก้ไฟล์", "สร้างไฟล์", "เขียนไฟล์", "อัปเดตไฟล์", "ได้ทำการแก้ไข", "แก้ไขเรียบร้อย", "แก้ไขแล้ว", "สร้างเรียบร้อย" };
        static readonly string[] Exported = { "exported the pdf", "pdf has been", "pdf exported", "export pdf สำเร็จ", "ส่งออก pdf", "สร้าง pdf", "export เป็น pdf" };

        /// <summary>Answer text without reasoning blocks.</summary>
        public static string Visible(string text)
        {
            if (string.IsNullOrEmpty(text)) return "";
            string t = Regex.Replace(text, "<(?:thought|thinking|think)>[\\s\\S]*?</(?:thought|thinking|think)>", "");
            t = Regex.Replace(t, "<(?:thought|thinking|think)>[\\s\\S]*$", "");
            return t.Trim();
        }

        /// <summary>Empty reasoning pairs some models emit carry nothing and leak into answers; non-empty ones are kept.</summary>
        public static string StripEmptyThought(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;
            string c = Regex.Replace(text, "<(thought|thinking|think)>\\s*</\\1>", "");
            return c == text ? text : c.Trim();
        }

        static bool Has(string lower, string[] words) { return words.Any(w => lower.Contains(w)); }

        /// <summary>The reason of the first claim with no supporting evidence, or null when the answer is consistent with the turn.</summary>
        public static string Mismatch(string answer, IList<ClaimEvidence> evidence)
        {
            string lower = Visible(answer).ToLowerInvariant();
            if (lower.Length == 0) return null;
            if (Has(lower, Ran))
            {
                var runs = evidence.Where(e => e.Executed).ToList();
                if (runs.Count == 0) return "the answer reports a run/test/build result, but no command was executed in this turn";
                if (!runs[runs.Count - 1].Ok) return "the answer reports a passing run, but the most recent command in this turn failed";
            }
            if (Has(lower, Changed) && !evidence.Any(e => e.Mutated && e.Ok))
                return "the answer says files were changed, but no file was written or edited in this turn";
            if (Has(lower, Exported) && !evidence.Any(e => e.ExportedPdf && e.Ok))
                return "the answer says a PDF was exported, but export_pdf did not succeed in this turn";
            return null;
        }

        /// <summary>Neutral, single prompt: no "CRITICAL", no instruction to keep editing.</summary>
        public static string Prompt(string reason)
        {
            return "Check before finishing: " + reason + ". If it did happen, run the command or tool now and report its real output; "
                + "otherwise rewrite the answer so it states only what this turn actually did and observed. "
                + "Do not change files just to make the claim true unless the user asked for that change.";
        }
    }
}
