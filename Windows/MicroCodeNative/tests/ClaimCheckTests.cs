// P1 claim-vs-evidence check (mirror of Scripts/tests/agent-claim-check-regression.swift). Compiles standalone: src\Agent\ClaimCheck.cs only.
using System;
using System.Collections.Generic;
using MicroCode.Views;

static class ClaimCheckTests
{
    static int fail;
    static void Check(bool ok, string name) { Console.WriteLine((ok ? "PASS  " : "FAIL  ") + name); if (!ok) fail++; }
    static ClaimEvidence E(bool exec, bool mut, bool pdf, bool ok) { return new ClaimEvidence { Executed = exec, Mutated = mut, ExportedPdf = pdf, Ok = ok }; }

    static int Main()
    {
        var run = E(true, false, false, true); var bad = E(true, false, false, false); var edit = E(false, true, false, true); var read = E(false, false, false, true);
        Check(ClaimCheck.Mismatch("All tests passed ✅", new[] { read }) != null, "pass claim with no command -> mismatch");
        Check(ClaimCheck.Mismatch("เทสผ่านทั้งหมดครับ", new[] { bad }) != null, "Thai pass claim after failing run -> mismatch");
        Check(ClaimCheck.Mismatch("Tests passed.\n```\n2 passed\n```", new[] { bad, run }) == null, "pass claim after later passing run -> ok");
        Check(ClaimCheck.Mismatch("ผลรันเทส: ไม่ผ่าน 1 ข้อ (test_discount)", new[] { bad }) == null, "honest failure report -> ok");
        Check(ClaimCheck.Mismatch("I updated calc.py to fix the bug.", new[] { run }) != null, "edit claim without edit -> mismatch");
        Check(ClaimCheck.Mismatch("แก้ไฟล์ calc.py แล้วครับ", new[] { edit, run }) == null, "edit claim with edit -> ok");
        Check(ClaimCheck.Mismatch("The PDF has been exported to report.pdf", new[] { edit }) != null, "PDF claim without export -> mismatch");
        Check(ClaimCheck.Mismatch("This function computes a discount.", new ClaimEvidence[0]) == null, "plain explanation -> no claim");
        Check(ClaimCheck.Mismatch("<thought>tests passed</thought>The file defines one class.", new ClaimEvidence[0]) == null, "claims inside thought blocks ignored");
        Check(!ClaimCheck.Prompt("x").Contains("CRITICAL"), "prompt is neutral");
        Check(ClaimCheck.StripEmptyThought("<thought></thought>\n\nDone.") == "Done.", "empty thought stripped");
        Check(ClaimCheck.StripEmptyThought("<thought>plan</thought>\nDone.") == "<thought>plan</thought>\nDone.", "non-empty thought kept");
        Console.WriteLine(fail == 0 ? "ALL PASS" : "FAILED " + fail);
        return fail == 0 ? 0 : 1;
    }
}
