// Self-checking tests for the Consensus Engine and PNS 24/7 ports, compiled against out-dev\MicroCode.exe by run-tests.cmd.
// Everything happens in a fresh temp folder with an isolated data dir: the git repos are created there, the pnsd daemon is
// spawned from out-dev with --data-dir pointing into that folder and stopped at the end (only the PID this test started).
// No AI model is involved: where a Builder / Auditor / fiber agent would edit files the test writes those files itself,
// and the daemon mission runs against an unreachable endpoint so its fibers fail for real.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using MicroCode.Core;
using MicroCode.UI;
using MicroCode.Views;

static class AgentPlatformTests
{
    static int _pass, _fail;
    static readonly CancellationToken CT = CancellationToken.None;

    static void Check(bool ok, string name)
    {
        Console.WriteLine((ok ? "PASS  " : "FAIL  ") + name);
        if (ok) _pass++; else _fail++;
    }

    static Dictionary<string, object> A(params object[] kv)
    {
        var d = new Dictionary<string, object>();
        for (int i = 0; i + 1 < kv.Length; i += 2) d[(string)kv[i]] = kv[i + 1];
        return d;
    }

    static string Run(string exe, string args, string cwd, out int code)
    {
        var psi = new ProcessStartInfo(exe, args) { WorkingDirectory = cwd, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
        using (var p = Process.Start(psi))
        {
            var o = p.StandardOutput.ReadToEndAsync(); var e = p.StandardError.ReadToEndAsync();
            p.WaitForExit();
            code = p.ExitCode;
            return o.Result + e.Result;
        }
    }

    static string Git(string cwd, string args)
    {
        int c;
        string r = Run("git", args, cwd, out c);
        if (c != 0) throw new Exception("git " + args + " failed (" + c + "): " + r);
        return r;
    }

    static void MakeRepo(string dir, params string[] files)
    {
        Directory.CreateDirectory(dir);
        Git(dir, "init -q -b main");
        Git(dir, "config user.email pns-test@example.invalid");
        Git(dir, "config user.name \"PNS Test\"");
        Git(dir, "config core.autocrlf false");
        Git(dir, "config commit.gpgsign false");
        for (int i = 0; i + 1 < files.Length; i += 2) { string p = Path.Combine(dir, files[i]); Directory.CreateDirectory(Path.GetDirectoryName(p)); File.WriteAllText(p, files[i + 1]); }
        Git(dir, "add -A");
        Git(dir, "commit -q -m init");
    }

    static void DeleteTree(string dir)
    {
        for (int attempt = 0; attempt < 4 && Directory.Exists(dir); attempt++)
        {
            try
            {
                foreach (var f in Directory.GetFiles(dir, "*", SearchOption.AllDirectories)) File.SetAttributes(f, FileAttributes.Normal);
                Directory.Delete(dir, true);
            }
            catch (IOException) { Thread.Sleep(300); }
            catch (UnauthorizedAccessException) { Thread.Sleep(300); }
        }
    }

    static SandboxFileChange Change(string path, string content)
    {
        return new SandboxFileChange { FilePath = path, ChangeType = SandboxChangeType.Create, NewContent = content, NewBytes = Encoding.UTF8.GetBytes(content) };
    }

    static bool Same(IEnumerable<string> a, params string[] b) { return a.OrderBy(x => x).SequenceEqual(b.OrderBy(x => x)); }

    [STAThread]
    static int Main()
    {
        string root = Path.Combine(Path.GetTempPath(), "MicroCode-agent-tests-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        Directory.CreateDirectory(root);
        Defaults.UseDir(Path.Combine(root, "data"));
        TaskFiles.HomeOverride = Path.Combine(root, "data", ".microcode");
        ConsensusResult rendered = null;
        PnsOrchestrator brain = null;
        try
        {
            rendered = ConsensusTests(root);
            brain = PnsCoreTests(root);
            PlexusTests(root);
            DaemonTests(root);
            RenderTests(root, rendered, brain);
        }
        catch (Exception ex)
        {
            Console.WriteLine("FAIL  unexpected: " + ex);
            _fail++;
        }
        finally
        {
            DeleteTree(root);
        }
        Console.WriteLine();
        Console.WriteLine(_pass + " passed, " + _fail + " failed");
        return _fail == 0 ? 0 : 1;
    }

    // ── Consensus Engine ────────────────────────────────────────────────────
    static ConsensusResult ConsensusTests(string root)
    {
        string ws = Path.Combine(root, "cws");
        Directory.CreateDirectory(Path.Combine(ws, "src"));
        Directory.CreateDirectory(Path.Combine(ws, "node_modules", "lib"));
        Directory.CreateDirectory(Path.Combine(ws, ".git"));
        File.WriteAllText(Path.Combine(ws, "src", "calc.py"), "def add(a, b):\n    return a + b\n");
        File.WriteAllText(Path.Combine(ws, "src", "old.py"), "x = 1\n");
        File.WriteAllText(Path.Combine(ws, "README.md"), "# Demo\n");
        File.WriteAllText(Path.Combine(ws, "node_modules", "lib", "index.js"), "module.exports = 1;\n");
        File.WriteAllText(Path.Combine(ws, ".git", "HEAD"), "ref: refs/heads/main\n");
        AppState.Shared.OpenWorkspace(ws);

        var engine = ConsensusEngine.Shared;
        Check(engine.Enabled && engine.StrictMode && !engine.AutoApplyOnPass, "Consensus defaults: Active, Strict Mode on, Auto-apply off (macOS defaults)");
        engine.StrictMode = false;
        Check(!Defaults.Bool("consensus_strict_mode", true), "Consensus settings persist under the macOS keys");
        engine.StrictMode = true;

        string sandboxParent = Path.Combine(root, "sandboxes");
        string sandboxRoot;
        List<SandboxFileChange> changes;
        var tests = new List<AuditorTestCase>();
        var findings = new List<SecurityFinding>();
        using (var sb = ConsensusSandbox.Create(ws, sandboxParent))
        {
            sandboxRoot = sb.Root;
            Check(File.Exists(Path.Combine(sb.Root, "src", "calc.py")) && File.Exists(Path.Combine(sb.Root, "README.md")), "Sandbox: copies the project sources");
            Check(!Directory.Exists(Path.Combine(sb.Root, "node_modules")) && !Directory.Exists(Path.Combine(sb.Root, ".git")), "Sandbox: leaves .git and node_modules out");
            Check(sb.CollectChanges().Count == 0, "Sandbox: a fresh copy has no changes");

            // tools of an isolated run write into the sandbox, never into the open workspace
            string fixedCalc = "def add(a, b):\n    if a is None or b is None:\n        raise ValueError('missing operand')\n    return a + b\n";
            string w = AgentRunner.ExecuteIsolated(sb.Root, ws, "file_write", A("path", "src/calc.py", "content", fixedCalc), new ToolStep(), CT);
            Check(!w.StartsWith("Error") && File.ReadAllText(Path.Combine(sb.Root, "src", "calc.py")).Contains("ValueError") && !File.ReadAllText(Path.Combine(ws, "src", "calc.py")).Contains("ValueError"), "Isolated run: file_write lands in the sandbox, not in the workspace");
            string esc = AgentRunner.ExecuteIsolated(sb.Root, ws, "file_write", A("path", "..\\escape.txt", "content", "x"), new ToolStep(), CT);
            Check(esc.StartsWith("Error") && esc.Contains("outside") && !File.Exists(Path.Combine(sandboxParent, "escape.txt")), "Isolated run: paths cannot escape the sandbox");
            AgentRunner.ExecuteIsolated(sb.Root, ws, "file_write", A("path", ".microcode/task.md", "content", "# t\n"), new ToolStep(), CT);
            Check(File.Exists(Path.Combine(sb.Root, ".microcode", "task.md")), "Isolated run: .microcode/task.md stays inside the sandbox");
            string cd = AgentRunner.ExecuteIsolated(sb.Root, ws, "shell", A("command", "cd"), new ToolStep(), CT);
            Check(cd.IndexOf(sb.Root, StringComparison.OrdinalIgnoreCase) >= 0, "Isolated run: shell runs in the sandbox");
            Check(!Directory.Exists(Path.Combine(Defaults.Dir, "checkpoints")), "Isolated run: no checkpoints written to the user data folder");

            // what a Builder agent leaves behind
            File.WriteAllText(Path.Combine(sb.Root, "src", "util.py"), "API_TOKEN = \"ghp_abcdefghijklmnopqrstuvwxyz0123456789\"\n\n\ndef clamp(v, lo, hi):\n    return max(lo, min(v, hi))\n");
            File.Delete(Path.Combine(sb.Root, "src", "old.py"));
            Directory.CreateDirectory(Path.Combine(sb.Root, ".consensus"));
            File.WriteAllText(Path.Combine(sb.Root, ".consensus", "test_calc.py"), "print('t')\n");
            Directory.CreateDirectory(Path.Combine(sb.Root, "node_modules"));
            File.WriteAllText(Path.Combine(sb.Root, "node_modules", "x.js"), "1\n");
            File.WriteAllBytes(Path.Combine(sb.Root, "src", "tool.exe"), new byte[] { 77, 90, 0, 1, 2 });
            changes = sb.CollectChanges();
            Check(Same(changes.Select(c => c.FilePath), "src/calc.py", "src/util.py", "src/old.py"), "CollectChanges: modified + created + deleted; .consensus/, .microcode/, node_modules and build artifacts left out (got " + string.Join(", ", changes.Select(c => c.FilePath)) + ")");
            var calc = changes.FirstOrDefault(c => c.FilePath == "src/calc.py");
            Check(calc != null && calc.ChangeType == SandboxChangeType.Modify && calc.Added == 2 && calc.Removed == 0 && calc.BaseHash != null && calc.Diff.Contains("+        raise ValueError"), "CollectChanges: a modification carries its diff, +/- counts and the base hash");
            var gone = changes.FirstOrDefault(c => c.FilePath == "src/old.py");
            Check(gone != null && gone.ChangeType == SandboxChangeType.Delete && gone.OldContent == "x = 1\n", "CollectChanges: a deletion keeps the old content");

            // the Auditor must not 'fix' the Builder's code
            File.WriteAllText(Path.Combine(sb.Root, "src", "calc.py"), "def add(a, b):\n    return 0\n");
            File.WriteAllText(Path.Combine(sb.Root, "src", "sneaky.py"), "print(1)\n");
            var reverted = sb.RestoreBuilderState(changes);
            Check(Same(reverted, "src/calc.py", "src/sneaky.py") && File.ReadAllText(Path.Combine(sb.Root, "src", "calc.py")).Contains("ValueError") && !File.Exists(Path.Combine(sb.Root, "src", "sneaky.py")) && File.Exists(Path.Combine(sb.Root, ".consensus", "test_calc.py")), "RestoreBuilderState: Auditor edits outside .consensus/ are reverted before the tests run");

            // real commands, run by the engine in the sandbox
            var run = new List<AuditorTestCase>
            {
                new AuditorTestCase { Name = "exits_zero", Category = AuditorTestCategory.Regression, Command = "cmd /c exit 0" },
                new AuditorTestCase { Name = "exits_three", Category = AuditorTestCategory.Edge, Command = "echo boom 1>&2 & exit 3" },
                new AuditorTestCase { Name = "sees_builder_code", Category = AuditorTestCategory.Property, Command = "findstr /c:\"ValueError\" src\\calc.py" },
                new AuditorTestCase { Name = "hangs", Category = AuditorTestCategory.Performance, Command = "ping -n 9 127.0.0.1 >nul" },
                new AuditorTestCase { Name = "destructive", Category = AuditorTestCategory.Security, Command = "del /s /q *" },
                new AuditorTestCase { Name = "no_command", Category = AuditorTestCategory.TypeSafety, Command = "" }
            };
            ConsensusAuditor.RunTests(run, sb.Root, ws, 5, CT);
            Check(run[0].Status == AuditorTestStatus.Passed && run[0].ExecutionTimeMs >= 0, "RunTests: exit code 0 passes");
            Check(run[1].Status == AuditorTestStatus.Failed && run[1].Output.Contains("boom"), "RunTests: a non-zero exit fails and keeps the output");
            Check(run[2].Status == AuditorTestStatus.Passed, "RunTests: commands run in the sandbox root against the Builder's code");
            Check(run[3].Status == AuditorTestStatus.Error && run[3].Output.Contains("timed out"), "RunTests: a hung test is stopped");
            Check(run[4].Status == AuditorTestStatus.Error && run[4].Output.Contains("blocked") && File.Exists(Path.Combine(sb.Root, "src", "calc.py")), "RunTests: a destructive command is never executed");
            Check(run[5].Status == AuditorTestStatus.Skipped, "RunTests: a test without a command is skipped");
            tests.AddRange(run.Take(3));
            ConsensusAuditor.StaticScan(changes, tests, findings);
        }
        Check(!Directory.Exists(sandboxRoot), "Sandbox: Dispose deletes the copy");

        // static scans
        var scan = new List<SandboxFileChange>
        {
            Change("config.py", "API_KEY = \"sk-live-1234567890abcdef\"\n"),
            Change("db.swift", "let q = \"SELECT * FROM users WHERE id = \\(id)\"\nlet v = value!\nlet c = x as! Int\nif a != b { print(\"hi!\") }\n"),
            Change("query.py", "cur.execute(f\"SELECT * FROM t WHERE name = '{name}'\")\n"),
            Change("clean.py", "import os\n\ndef key():\n    return os.environ['API_KEY']\n")
        };
        var st = new List<AuditorTestCase>(); var sf = new List<SecurityFinding>();
        ConsensusAuditor.StaticScan(scan, st, sf);
        Check(sf.Any(f => f.Severity == FindingSeverity.High && f.Title == "Hardcoded Secret Detected" && f.FilePath == "config.py" && f.Line == 1), "StaticScan: hardcoded API key → High, with its line");
        Check(sf.Any(f => f.Severity == FindingSeverity.Critical && f.Title == "Potential SQL Injection" && f.FilePath == "db.swift" && f.Line == 1), "StaticScan: Swift string interpolation in SQL → Critical");
        Check(sf.Any(f => f.Severity == FindingSeverity.Critical && f.FilePath == "query.py"), "StaticScan: Python f-string SQL → Critical");
        Check(st.Any(x => x.Name == "check_force_unwrap_db.swift" && x.Status == AuditorTestStatus.Failed) && sf.Any(f => f.Title == "Force Unwrap Detected" && f.Severity == FindingSeverity.Medium && f.FilePath == "db.swift" && f.Line == 2), "StaticScan: Swift force unwrap → failed check + Medium finding (string literals and != ignored)");
        Check(!sf.Any(f => f.FilePath == "clean.py"), "StaticScan: environment lookups are not secrets");

        // Auditor replies
        string reply = "Audit done.\n```json\n{\"tests\":[{\"name\":\"test_none\",\"category\":\"edge_case\",\"command\":\"python -m pytest .consensus -q\",\"test_code\":\"assert add(None, 1)\",\"rationale\":\"None must raise\"},{\"name\":\"t2\",\"category\":\"type_safety\",\"command\":\"echo ok\"}],\"security_findings\":[{\"severity\":\"high\",\"title\":\"Injection\",\"description\":\"user input\",\"file\":\"src/db.py\",\"line\":45}]}\n```";
        var pt = new List<AuditorTestCase>(); var pf = new List<SecurityFinding>();
        ConsensusAuditor.ParseReply(reply, pt, pf);
        Check(pt.Count == 2 && pt[0].Category == AuditorTestCategory.Edge && pt[0].Command == "python -m pytest .consensus -q" && pt[0].Rationale == "None must raise" && pt[1].Category == AuditorTestCategory.TypeSafety, "ParseReply: tests with categories, commands and rationale");
        Check(pf.Count == 1 && pf[0].Severity == FindingSeverity.High && pf[0].Line == 45 && pf[0].FilePath == "src/db.py", "ParseReply: security findings");
        var pt2 = new List<AuditorTestCase>(); var pf2 = new List<SecurityFinding>();
        ConsensusAuditor.ParseReply("{\"findings\":[{\"severity\":\"warning\",\"file\":\"a.py\",\"line\":3,\"description\":\"risky\"}],\"verdict\":\"rejected\",\"summary\":\"x\"}", pt2, pf2);
        Check(pt2.Count == 0 && pf2.Count == 1 && pf2[0].Severity == FindingSeverity.Medium && pf2[0].Description == "risky", "ParseReply: the macOS `findings` format (warning → Medium)");
        var pt3 = new List<AuditorTestCase>(); var pf3 = new List<SecurityFinding>();
        ConsensusAuditor.ParseReply("I could not find anything {to test}.", pt3, pf3);
        Check(pt3.Count == 0 && pf3.Count == 0, "ParseReply: prose without a JSON plan adds nothing");

        // the vote
        Func<AuditorTestStatus[], List<AuditorTestCase>> T = s => s.Select((x, i) => new AuditorTestCase { Name = "t" + i, Status = x }).ToList();
        var none = new List<SecurityFinding>();
        Func<FindingSeverity, List<SecurityFinding>> F = s => new List<SecurityFinding> { new SecurityFinding { Severity = s, Title = "x" } };
        Check(ConsensusEngine.Vote(true, T(new[] { AuditorTestStatus.Passed, AuditorTestStatus.Passed }), none) == ConsensusVerdict.Approved, "Vote (strict): every test passed → Approved");
        Check(ConsensusEngine.Vote(true, T(new[] { AuditorTestStatus.Passed, AuditorTestStatus.Failed }), none) == ConsensusVerdict.Rejected, "Vote (strict): one failed test → Rejected");
        Check(ConsensusEngine.Vote(true, T(new[] { AuditorTestStatus.Passed, AuditorTestStatus.Error }), none) == ConsensusVerdict.Rejected, "Vote (strict): a test error → Rejected");
        Check(ConsensusEngine.Vote(true, T(new[] { AuditorTestStatus.Passed, AuditorTestStatus.Skipped }), none) == ConsensusVerdict.Rejected, "Vote (strict): a skipped test → Rejected");
        Check(ConsensusEngine.Vote(true, T(new AuditorTestStatus[0]), none) == ConsensusVerdict.Rejected, "Vote (strict): no test executed → Rejected (nothing verified)");
        Check(ConsensusEngine.Vote(true, T(new[] { AuditorTestStatus.Passed }), F(FindingSeverity.High)) == ConsensusVerdict.Rejected, "Vote (strict): a High finding → Rejected");
        Check(ConsensusEngine.Vote(true, T(new[] { AuditorTestStatus.Passed }), F(FindingSeverity.Medium)) == ConsensusVerdict.Approved, "Vote (strict): a Medium finding does not block");
        Check(ConsensusEngine.Vote(false, T(new[] { AuditorTestStatus.Failed }), none) == ConsensusVerdict.Approved, "Vote (non-strict): failed tests do not block");
        Check(ConsensusEngine.Vote(false, T(new AuditorTestStatus[0]), F(FindingSeverity.Critical)) == ConsensusVerdict.Rejected, "Vote (non-strict): a Critical finding blocks");

        var summary = new ConsensusResult { Verdict = ConsensusVerdict.Approved, PassedTests = 2, TotalTests = 3 };
        Check(summary.Summary == "Approved: 2/3 tests passed (67%)", "ConsensusResult.Summary uses the macOS wording (" + summary.Summary + ")");

        // applying to the workspace
        string aws = Path.Combine(root, "aws");
        Directory.CreateDirectory(aws);
        foreach (var kv in new[] { "a.txt=one", "b.txt=two", "locked.txt=lock", "gone.txt=bye" }) { var p = kv.Split('='); File.WriteAllText(Path.Combine(aws, p[0]), p[1] + "\n"); }
        using (var sb = ConsensusSandbox.Create(aws, sandboxParent))
        {
            File.WriteAllText(Path.Combine(sb.Root, "a.txt"), "ONE\n");
            File.WriteAllText(Path.Combine(sb.Root, "b.txt"), "TWO\n");
            File.WriteAllText(Path.Combine(sb.Root, "locked.txt"), "changed\n");
            File.WriteAllText(Path.Combine(sb.Root, "c.txt"), "new\n");
            File.Delete(Path.Combine(sb.Root, "gone.txt"));
            var ch = sb.CollectChanges();
            File.WriteAllText(Path.Combine(aws, "b.txt"), "two (edited by the user meanwhile)\n");
            Defaults.Set("scope_locked_" + aws.ToLowerInvariant(), new ArrayList { Path.Combine(aws, "locked.txt") });
            var rep = ConsensusEngine.Apply(aws, ch);
            Check(File.ReadAllText(Path.Combine(aws, "a.txt")) == "ONE\n" && File.ReadAllText(Path.Combine(aws, "c.txt")) == "new\n" && !File.Exists(Path.Combine(aws, "gone.txt")) && Same(rep.Applied, "a.txt", "c.txt", "gone.txt"), "Apply: writes modified and created files and removes deleted ones");
            Check(File.ReadAllText(Path.Combine(aws, "b.txt")).Contains("edited by the user") && rep.Skipped.Any(s => s.StartsWith("b.txt")), "Apply: never overwrites a file the user changed after the sandbox was made");
            Check(File.ReadAllText(Path.Combine(aws, "locked.txt")) == "lock\n" && rep.Skipped.Any(s => s.StartsWith("locked.txt")), "Apply: honours Scope Lock");
        }

        // isolated-run approvals: edits pass, shell asks the user
        var approve = IsolatedApprovals.Approver("consensus", "Builder");
        Check(approve(new ToolStep { Name = "file_write", Target = "a.py" }, new Dictionary<string, object>()).Result, "Approvals: edits inside the isolated copy pass");
        var ask = approve(new ToolStep { Name = "shell", Target = "pytest -q" }, new Dictionary<string, object>());
        var pending = IsolatedApprovals.PendingFor("consensus").FirstOrDefault();
        Check(!ask.IsCompleted && pending != null && pending.Actor == "Builder" && pending.Detail == "pytest -q", "Approvals: a shell command waits for the user");
        IsolatedApprovals.Resolve(pending, true);
        Check(ask.IsCompleted && ask.Result && IsolatedApprovals.PendingFor("consensus").Count == 0, "Approvals: approving releases the command");

        var result = new ConsensusResult
        {
            Request = "Validate operands in add()", BuilderChanges = changes, AuditorTests = tests, SecurityIssues = findings,
            Verdict = ConsensusEngine.Vote(true, tests, findings), ExecutionTimeMs = 4210, Timestamp = DateTime.Now
        };
        result.Tally();
        Check(result.Verdict == ConsensusVerdict.Rejected && result.FailedTests == 1 && result.TotalTests == 3 && findings.Any(x => x.FilePath == "src/util.py" && x.Severity == FindingSeverity.High), "Pipeline: a failed test plus a hardcoded token in the Builder's change → Rejected");
        return result;
    }

    // ── PNS core ────────────────────────────────────────────────────────────
    static PnsOrchestrator PnsCoreTests(string root)
    {
        var e = new PnsSynapse("code_implementation", Pns.MotorImplementation, "agent:backend_engineer", "C:\\proj");
        Check(Math.Abs(e.Weight - 0.5) < 1e-12, "Synapse: starts at W = 0.50");
        e.ApplyHebbianImpulse(true, 1.0, 250, 500, 1.0);
        Check(Math.Abs(e.Weight - 0.6325) < 1e-9 && e.SuccessCount == 1 && e.AvgLatencyMs == 500 && e.AvgTokensUsed == 250, "Hebbian: one verified success W 0.50 → 0.6325 (" + e.Weight + ")");
        e.ApplyHebbianImpulse(true, 1.0, 250, 500, 1.0);
        Check(e.Weight >= 0.75 && !e.IsMyelinated, "Hebbian: W ≥ 0.75 after two wins is not myelinated yet");
        e.ApplyHebbianImpulse(true, 1.0, 250, 1500, 1.0);
        Check(e.IsMyelinated && e.AvgLatencyMs == 750, "Hebbian: the third verified win myelinates; latency is a 3:1 moving average");
        var f = new PnsSynapse("debug_verification", Pns.MotorVerification, "agent:test_runner", "C:\\proj");
        f.ApplyHebbianImpulse(false, 0, 800, 900, 1.0);
        Check(Math.Abs(f.Weight - 0.2925) < 1e-9 && f.FailureCount == 1, "LTD: one failure W 0.50 → 0.2925");
        f.ApplyHebbianImpulse(false, 0, 800, 900, 1.0);
        Check(f.IsInhibited, "LTD: two failures inhibit the pathway");
        f.ApplyHebbianImpulse(false, 0, 800, 900, 1.0);
        Check(Math.Abs(f.Weight - 0.01) < 1e-12, "LTD: weight floor is 0.01");
        string id1 = PnsSynapse.MakeId("c", Pns.MotorImplementation, "agent:x", "C:\\p");
        Check(id1 == PnsSynapse.MakeId("c", Pns.MotorImplementation, "agent:x", "C:\\p") && id1 != PnsSynapse.MakeId("c", Pns.MotorImplementation, "agent:x", "C:\\q") && Regex.IsMatch(id1, "^[0-9a-f]{12}::c::motor_implementation::agent:x$"), "Synapse ids: deterministic and project-scoped (" + id1 + ")");

        Check(Pns.ClassifyTaskCategory("Fix the crash in the parser") == "debug_verification", "Task category: fix/crash → debug_verification");
        Check(Pns.ClassifyTaskCategory("Add a postgres migration for orders") == "data_engineering", "Task category: postgres → data_engineering");
        Check(Pns.ClassifyTaskCategory("แก้บั๊กหน้า login") == "debug_verification", "Task category: Thai แก้บั๊ก → debug_verification");
        Check(Pns.ClassifyTaskCategory("Refactor the module architecture") == "architecture_refactor", "Task category: architecture → architecture_refactor");
        Check(Pns.ClassifyTaskCategory("Write a greeting function") == "code_implementation", "Task category: default → code_implementation");
        Check(Pns.MotorTractFor("architect") == Pns.MotorArchitecture && Pns.MotorTractFor("test_runner") == Pns.MotorVerification && Pns.MotorTractFor("security_auditor") == Pns.MotorVerification && Pns.MotorTractFor("frontend_engineer") == Pns.MotorImplementation, "Motor tracts: architect / verifiers / builders");

        var quiet = Pns.ThalamicFilter("all good\n3 passed\n", "t", 2400);
        Check(quiet.Item1 == "all good\n3 passed\n" && Math.Abs(quiet.Item2 - 0.18) < 1e-12, "Thalamus: short clean output passes through (salience 0.18)");
        var gate = Pns.ThalamicFilter("\u001b[31mCompiling foo v1\u001b[0m\nsrc/a.rs:3: error: mismatched types\nsrc/a.rs:3: error: mismatched types\nwarning: unused\nok\n", "MotorVerify:test_runner", 2400);
        Check(gate.Item1.StartsWith("[Thalamus Gate • MotorVerify:test_runner • 6 lines -> Salience 0.78 • Errors: 2, Warnings: 1]\nsrc/a.rs:3: error: mismatched types\nwarning: unused\n--- Tail ---\nCompiling foo v1") && Math.Abs(gate.Item2 - 0.776) < 1e-9 && !gate.Item1.Contains("\u001b"), "Thalamus: errors deduplicated, ANSI stripped, tail kept (" + gate.Item1.Split('\n')[0] + ")");
        var big = Pns.ThalamicFilter(string.Join("\n", Enumerable.Range(0, 400).Select(i => "error: failure number " + i + " " + new string('x', 150))), "x", 2400);
        Check(big.Item1.EndsWith("\n…[thalamic truncation]") && big.Item1.Length == 2400 + "\n…[thalamic truncation]".Length && Math.Abs(big.Item2 - 1.0) < 1e-9, "Thalamus: long error streams are truncated at maxChars");

        var cord = new PnsSpinalCord();
        var r1 = cord.Evaluate("cortex_planner", "plan", "HTTP 429 Too Many Requests: rate limit exceeded");
        Check(r1.Action == PnsReflexAction.SwitchProviderEndpoint && r1.CooldownMs == 2000 && cord.SavesCount == 1, "Spinal reflex: 429 → provider failover with 2 s cool-down");
        var r2 = cord.Evaluate("agent:x", "t", "RESOURCE_EXHAUSTED: quota exceeded");
        Check(r2.Action == PnsReflexAction.SwitchProviderEndpoint && r2.CooldownMs == 8000, "Spinal reflex: quota → 8 s cool-down");
        var r3 = cord.Evaluate("shell", "npm start", "Error: listen EADDRINUSE: address already in use :::3000");
        Check(r3.Action == PnsReflexAction.RemapCollidedPort && r3.DetectedPort == 3000 && r3.SuggestedPort > 0 && r3.SuggestedPort != 3000, "Spinal reflex: EADDRINUSE → a free local port (" + r3.SuggestedPort + ")");
        var cord2 = new PnsSpinalCord();
        var a1 = cord2.Evaluate("agent:test_runner", "Run tests", "exit code 1: 3 tests failed");
        var a2 = cord2.Evaluate("agent:test_runner", "Run tests", "exit code 1: 4 tests failed");
        var a3 = cord2.Evaluate("agent:test_runner", "Run tests", "exit code 1: 5 tests failed");
        Check(a1.Action == PnsReflexAction.None && a1.Summary == "Escalated to Cortex" && a2.Action == PnsReflexAction.None && a3.Action == PnsReflexAction.CircuitBreakBehavioralFixation && a3.InhibitionRule.Contains("Repeatedly failed (3x)") && cord2.SavesCount == 1, "Spinal reflex: three identical failures (numbers normalised) trip the fixation breaker");

        var v1 = Pns.Homeostasis(1.0, "Nominal", false, Pns.AutoHomeostasis, 0);
        Check(Math.Abs(v1.Index - 1.0) < 1e-12 && v1.Effective == Pns.Sympathetic && Pns.MaxConcurrentFibers(v1.Effective, v1.Index) == 3, "Homeostasis: AC power → sympathetic, 3 parallel fibers");
        var v2 = Pns.Homeostasis(1.0, "Nominal", false, Pns.AutoHomeostasis, 0.5);
        Check(Math.Abs(v2.Index - 0.5) < 1e-12 && v2.Effective == Pns.Parasympathetic && Pns.MaxConcurrentFibers(v2.Effective, v2.Index) == 1, "Homeostasis: rate-limit pressure → parasympathetic, 1 fiber");
        Check(Pns.Homeostasis(0.84, "Fair (On Battery)", false, Pns.AutoHomeostasis, 0).Effective == Pns.Sympathetic && Pns.MaxConcurrentFibers(Pns.Sympathetic, 0.84) == 3 && Pns.MaxConcurrentFibers(Pns.Sympathetic, 0.7) == 2, "Homeostasis: index > 0.80 allows 3 fibers, otherwise 2");
        Check(Pns.Homeostasis(0.22, "Critical (Low Battery)", true, Pns.Sympathetic, 0).Effective == Pns.Parasympathetic, "Homeostasis: critical power forces parasympathetic even in sympathetic mode");
        Check(Math.Abs(Pns.Homeostasis(1.0, "Nominal", false, Pns.AutoHomeostasis, 0.9).Index - 0.35) < 1e-12 && Math.Abs(Pns.Homeostasis(0.22, "x", true, Pns.AutoHomeostasis, 0.9).Index - 0.10) < 1e-12, "Homeostasis: pressure capped at 0.65, index floor 0.10");
        var power = Pns.ReadPower();
        Check(power.Factor > 0 && power.Factor <= 1 && !string.IsNullOrEmpty(power.Label), "Homeostasis: reads this PC's power state (" + power.Label + ")");

        var plan = PnsOrchestrator.ParsePlan("Here is the plan:\n[{\"id\":\"s1\",\"title\":\"Design API\",\"description\":\"d1\",\"archetype\":\"architect\",\"owned_paths\":[\"docs/\"],\"dependencies\":[]},{\"id\":\"s2\",\"title\":\"Build it\",\"description\":\"d2\",\"archetype\":\"backend_engineer\",\"dependencies\":[\"s1\",\"ghost\",\"s2\"]},{\"title\":\"Test\",\"archetype\":\"test_runner\",\"dependencies\":[\"s2\"]}]", "the objective");
        Check(plan.Count == 3 && plan[0].Tract == Pns.MotorArchitecture && plan[0].OwnedPaths.SequenceEqual(new[] { "docs/" }) && plan[2].Id == "step_3" && plan[2].Tract == Pns.MotorVerification && plan[2].Description == "the objective" && plan.All(s => s.Status == Pns.Queued), "Cortex plan: JSON array → queued subtasks with motor tracts");
        Check(plan[1].Dependencies.SequenceEqual(new[] { "s1" }), "Cortex plan: unknown and self dependencies are dropped so a mission cannot deadlock");
        Check(PnsOrchestrator.ParsePlan("I cannot plan this.", "o").Count == 0, "Cortex plan: prose → no subtasks (caller falls back)");
        var fb = PnsOrchestrator.FallbackPlan("Ship it");
        Check(fb.Count == 3 && fb[0].AssignedArchetype == "architect" && fb[1].Dependencies.SequenceEqual(new[] { "step_1" }) && fb[2].AssignedArchetype == "test_runner" && fb[2].Description.Contains("Ship it"), "Cortex plan: macOS 3-fiber fallback (architect → build → verify)");

        string pdir = Path.Combine(root, "pns-state");
        var o = new PnsOrchestrator(pdir);
        o.RecordSpike(Pns.SpikeFiberMerge, Pns.MotorImplementation, "m1", "C:\\proj", "Motor Fiber [backend_engineer] verified (2 file(s), merged=False, branch=pns/auto-a).", 0.85, 1200, true);
        o.RecordSpike(Pns.SpikeFiberMerge, Pns.MotorImplementation, "m1", "C:\\proj", "Motor Fiber [backend_engineer] verified (1 file(s), merged=False, branch=pns/auto-b).", 0.85, 900, true);
        o.RecordSpike(Pns.SpikePain, Pns.MotorVerification, "m1", "C:\\proj", "Verification failed: npm test exited 1", 0.9, 300, false);
        Check(File.ReadAllLines(Path.Combine(pdir, "synaptic_wal.jsonl")).Length == 3, "Episodic WAL: every spike is appended to synaptic_wal.jsonl");
        string rem = o.RunRemConsolidation("C:\\proj", null);
        Check(rem.StartsWith("REM Consolidation Cycle #1 (") && rem.EndsWith("+1 Procedural Playbooks, +1 Inhibition Guards, active episodic buffer pruned."), "REM: distils a playbook and an inhibition guard (" + rem + ")");
        Check(o.Playbooks.Count == 1 && o.Playbooks[0].Tract == Pns.MotorImplementation && o.Playbooks[0].ProjectPath == "C:\\proj" && o.Invariants.Count == 1 && o.Invariants[0].IsInhibitionWarning, "REM: playbook + inhibition are project-scoped");
        string rem2 = o.RunRemConsolidation("C:\\proj", null);
        Check(rem2.StartsWith("REM Consolidation Cycle #2") && o.Playbooks.Count == 1 && o.Playbooks[0].ExecutionWins == 2 && Math.Abs(o.Playbooks[0].ConfidenceWeight - 0.82) < 1e-9 && o.Invariants.Count == 1, "REM: a repeat strengthens the playbook instead of duplicating it");
        string mem = o.PromptMemoryAugmentation("next task", "C:\\proj");
        Check(mem.Contains("## PNS (Pseudo Neural System — Active Cognitive Architecture)") && mem.Contains("### PNS Myelinated Procedural Playbooks (Verified Fast-Paths)") && mem.Contains("⛔ INHIBITED"), "Memory augmentation: playbooks and inhibitions for the project");
        Check(o.PromptMemoryAugmentation("x", "C:\\other") == "", "Memory augmentation: nothing leaks to other projects");
        for (int i = 0; i < 3; i++) o.RecordSynapticFeedback("Fix failing tests", Pns.MotorVerification, "agent:test_runner", "C:\\proj", true, 250, 500, 0.8);
        Check(o.Synapses.Values.Count(x => x.IsMyelinated) == 1 && o.RecentSpikes.Any(s => s.Summary.StartsWith("Synapse MYELINATED (W_e=")), "Synaptic feedback: three wins myelinate and emit a spike");
        o.Mode = Pns.Parasympathetic;
        var mission = PnsOrchestrator.NewMission("Add tests\nfor the parser", "C:\\proj", Pns.PolicyIsolated, "npm test");
        Check(mission.Title == "Add tests" && mission.Status == Pns.Queued && mission.DistilledWorkingMemory == "GOAL ANCHOR: Add tests\nfor the parser" && mission.Progress == 0, "Mission: title from the first line, goal anchor in working memory");
        mission.Status = Pns.Running;
        o.Missions.Insert(0, mission);
        o.SaveNow();
        var o2 = new PnsOrchestrator(pdir);
        Check(o2.Missions.Count == 1 && o2.Missions[0].Title == "Add tests" && o2.Synapses.Count == 1 && o2.Playbooks.Count == 1 && o2.Invariants.Count == 1 && o2.RecentSpikes.Count >= 6 && o2.Mode == Pns.Parasympathetic, "Persistence: synapses, playbooks, invariants, missions, WAL and mode reload from ~/.microcode/pns");
        o2.RecoverInterruptedMissions();
        Check(o2.Missions[0].Status == Pns.Paused && (o2.Missions[0].LastError ?? "").Contains("Interrupted"), "Recovery: a mission left running by a closed app is paused, not silently stuck");
        var snap = o.BuildStatusSnapshot();
        Check(snap.Tracts.Count == 8 && snap.Tracts.Count(t => Pns.IsMcp(t.Tract)) == 5 && snap.MyelinatedSynapsesCount == 1 && snap.ProceduralPlaybooksCount == 1 && snap.RemConsolidationCycles == 2 && snap.AutonomicMode == Pns.Parasympathetic && snap.Missions.Count == 1, "Status snapshot: tracts, counts and missions");
        return o;
    }

    // ── PNS motor plexus (real git worktrees) ───────────────────────────────
    static void PlexusTests(string root)
    {
        string repo = Path.Combine(root, "repo");
        MakeRepo(repo, "app.py", "def add(a, b):\n    return a + b\n\n\ndef sub(a, b):\n    return a - b\n", "notes.md", "# Notes\n");
        var plexus = new PnsMotorPlexus(Path.Combine(root, "worktrees"));

        var lease = plexus.AllocateFiber("abcdef123456", "backend_engineer", "Add mul", repo, new List<string>());
        string wt = lease.IsolatedWorktreePath;
        Check(lease.IsGit && Directory.Exists(wt) && File.Exists(Path.Combine(wt, "app.py")) && lease.BranchName.StartsWith("pns/auto-abcdef-backend_engineer-") && lease.Tract == Pns.MotorImplementation && lease.State == "active", "Motor fiber: isolated git worktree on a pns/auto-* branch (" + lease.BranchName + ")");
        Check(Git(repo, "branch --list pns/auto-*").Contains(lease.BranchName), "Motor fiber: the branch exists in the user's repo");
        File.AppendAllText(Path.Combine(wt, "app.py"), "\n\ndef mul(a, b):\n    return a * b\n");
        var join = plexus.VerifyAndJoin(lease.Id, Pns.PolicyIsolated, "findstr /c:\"def mul\" app.py", "Added mul()\nand more detail");
        Check(join.VerificationPassed && join.ModifiedFiles.SequenceEqual(new[] { "app.py" }) && join.CommittedBranch == lease.BranchName && !join.MergedToTrunk, "VerifyAndJoin: verified work is committed on its branch");
        Check(!Directory.Exists(wt) && !File.ReadAllText(Path.Combine(repo, "app.py")).Contains("def mul") && !Git(repo, "worktree list").Contains("worktrees"), "VerifyAndJoin: worktree released and the trunk untouched under the safe policy");
        Check(Git(repo, "log -1 --format=%s " + lease.BranchName).Trim() == "PNS [backend_engineer]: Added mul()", "VerifyAndJoin: commit subject names the fiber");

        var l2 = plexus.AllocateFiber("abcdef123456", "test_runner", "Break it", repo, new List<string>());
        File.WriteAllText(Path.Combine(l2.IsolatedWorktreePath, "app.py"), "broken\n");
        var j2 = plexus.VerifyAndJoin(l2.Id, Pns.PolicyAutoMerge, "cmd /c exit 4", "broke it");
        Check(!j2.VerificationPassed && j2.CommittedBranch == null && !j2.MergedToTrunk && File.ReadAllText(Path.Combine(repo, "app.py")).Contains("def add") && !Directory.Exists(l2.IsolatedWorktreePath), "VerifyAndJoin: failed verification never commits or merges");
        Check(Git(repo, "branch --list " + l2.BranchName).Trim().Length == 0 && Git(repo, "branch --list " + lease.BranchName).Trim().Length > 0, "Release: a fiber that never committed leaves no empty pns/auto-* branch; committed branches stay");

        var l3 = plexus.AllocateFiber("abcdef123456", "backend_engineer", "Doc", repo, new List<string>());
        File.WriteAllText(Path.Combine(repo, "app.py"), File.ReadAllText(Path.Combine(repo, "app.py")).Replace("def add(a, b):", "def add(a, b):  # user edit"));
        File.WriteAllText(Path.Combine(l3.IsolatedWorktreePath, "app.py"), File.ReadAllText(Path.Combine(l3.IsolatedWorktreePath, "app.py")).Replace("    return a - b", "    return a - b  # fiber edit"));
        File.WriteAllText(Path.Combine(l3.IsolatedWorktreePath, "NEW.md"), "new file\n");
        var j3 = plexus.VerifyAndJoin(l3.Id, Pns.PolicyAutoMerge, null, "doc tweak");
        string merged = File.ReadAllText(Path.Combine(repo, "app.py"));
        Check(j3.VerificationPassed && j3.MergedToTrunk && merged.Contains("# user edit") && merged.Contains("# fiber edit") && !merged.Contains("<<<<<<<") && File.Exists(Path.Combine(repo, "NEW.md")), "Auto 3-way merge: keeps the user's uncommitted edit and the fiber's edit");

        var l4 = plexus.AllocateFiber("abcdef123456", "backend_engineer", "Overlap", repo, new List<string>());
        File.WriteAllText(Path.Combine(repo, "app.py"), File.ReadAllText(Path.Combine(repo, "app.py")).Replace("return a + b", "return b + a"));
        File.WriteAllText(Path.Combine(l4.IsolatedWorktreePath, "app.py"), File.ReadAllText(Path.Combine(l4.IsolatedWorktreePath, "app.py")).Replace("return a + b", "return int(a) + int(b)"));
        plexus.VerifyAndJoin(l4.Id, Pns.PolicyAutoMerge, null, "overlap");
        string m4 = File.ReadAllText(Path.Combine(repo, "app.py"));
        Check(m4.Contains("int(a) + int(b)") && !m4.Contains("return b + a") && !m4.Contains("<<<<<<<"), "Auto 3-way merge: overlapping lines resolve to the verified fiber without conflict markers (macOS rule)");

        var l5 = plexus.AllocateFiber("abcdef123456", "frontend_engineer", "Docs only", repo, new List<string> { "notes.md" });
        File.WriteAllText(Path.Combine(l5.IsolatedWorktreePath, "notes.md"), "# Notes\nmore\n");
        File.WriteAllText(Path.Combine(l5.IsolatedWorktreePath, "app.py"), "def x():\n    pass\n");
        var j5 = plexus.VerifyAndJoin(l5.Id, Pns.PolicyIsolated, null, "notes");
        Check(j5.ModifiedFiles.SequenceEqual(new[] { "notes.md" }), "Ownership lease: edits outside the owned paths are not joined");
        Check(Git(repo, "show --name-only --format= " + l5.BranchName).Trim() == "notes.md", "Ownership lease: only owned files are committed on the branch");

        string plain = Path.Combine(root, "plain");
        Directory.CreateDirectory(plain);
        File.WriteAllText(Path.Combine(plain, "main.py"), "print('hi')\n");
        var l6 = plexus.AllocateFiber("fedcba987654", "backend_engineer", "Plain", plain, new List<string>());
        Check(!l6.IsGit && File.Exists(Path.Combine(l6.IsolatedWorktreePath, "main.py")), "Motor fiber: a folder without git gets an isolated copy");
        File.WriteAllText(Path.Combine(l6.IsolatedWorktreePath, "main.py"), "print('changed')\n");
        var j6 = plexus.VerifyAndJoin(l6.Id, Pns.PolicyAutoMerge, null, "plain");
        Check(j6.MergedToTrunk && j6.CommittedBranch == null && File.ReadAllText(Path.Combine(plain, "main.py")) == "print('changed')\n" && !Directory.Exists(l6.IsolatedWorktreePath), "VerifyAndJoin: the copy merges back and is removed");

        string unborn = Path.Combine(root, "unborn");
        Directory.CreateDirectory(unborn);
        Git(unborn, "init -q");
        File.WriteAllText(Path.Combine(unborn, "x.txt"), "x\n");
        var l7 = plexus.AllocateFiber("0123456789ab", "architect", "Unborn", unborn, new List<string>());
        Check(!l7.IsGit && File.Exists(Path.Combine(l7.IsolatedWorktreePath, "x.txt")), "Motor fiber: a repo without commits falls back to a copy");
        plexus.VerifyAndJoin(l7.Id, Pns.PolicyIsolated, null, "nothing");

        var tel = plexus.BuildMotorTelemetry(new List<PnsSynapse>());
        Check(tel.Count == 3 && tel.All(t => t.AttachedNodes.Count > 0) && tel.Sum(t => t.TotalImpulses) == 7, "Motor telemetry: three motor tracts with archetypes and impulse counts");
    }

    // ── pnsd: the out-of-process 24/7 daemon ────────────────────────────────
    static void DaemonTests(string root)
    {
        string exe = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "MicroCode.exe");
        string data = Path.Combine(root, "daemon-data");
        Directory.CreateDirectory(data);
        // local mode against a closed port: every model call fails fast and for real, without touching the network
        File.WriteAllText(Path.Combine(data, "settings.json"), "{\"ai_key_mode\":\"local\",\"ai_base_local\":\"http://127.0.0.1:9/v1\"}");
        string pnsDir = Path.Combine(data, ".microcode", "pns");
        int port = PnsSpinalCord.AllocateFreeLocalPort();
        var proc = Process.Start(new ProcessStartInfo(exe, "--pns-daemon --pns-port " + port + " --data-dir \"" + data + "\"") { UseShellExecute = false, CreateNoWindow = true });
        try
        {
            var client = new PnsDaemonClient(pnsDir, port);
            PnsStatusSnapshot snap = null;
            var sw = Stopwatch.StartNew();
            while (snap == null && sw.Elapsed.TotalSeconds < 20 && !proc.HasExited) { Thread.Sleep(250); snap = PnsStatusSnapshot.Parse(client.Send("GET", "/pns/status", null).Result); }
            Check(snap != null && snap.DaemonPID == proc.Id && snap.IsOutOfProcessDaemon, "pnsd: boots headless and answers /pns/status with its own PID");
            Check(File.Exists(Path.Combine(pnsDir, "daemon.token")) && File.ReadAllText(Path.Combine(pnsDir, "daemon.port")).Trim() == port.ToString(), "pnsd: writes its token and port next to the PNS state");
            using (var http = new HttpClient { Timeout = TimeSpan.FromSeconds(3) })
                Check((int)http.GetAsync("http://127.0.0.1:" + port + "/pns/status").Result.StatusCode == 401, "pnsd: requests without the X-PNS-Token are refused (401)");
            client.Send("POST", "/pns/mode", A("mode", Pns.Parasympathetic)).Wait();
            snap = PnsStatusSnapshot.Parse(client.Send("GET", "/pns/status", null).Result);
            Check(snap != null && snap.AutonomicMode == Pns.Parasympathetic && snap.EffectiveMode == Pns.Parasympathetic, "pnsd: /pns/mode switches the autonomic mode");
            string remReply = client.Send("POST", "/pns/consolidate", A()).Result ?? "";
            Check(remReply.Contains("REM Consolidation Cycle #1"), "pnsd: /pns/consolidate runs a REM cycle");

            string mrepo = Path.Combine(root, "mission-repo");
            MakeRepo(mrepo, "server.py", "def handler(path):\n    return 404\n");
            string started = client.Send("POST", "/pns/missions/start", A("objective", "Add a /health endpoint", "workspace_path", mrepo, "branch_policy", Pns.PolicyIsolated)).Result;
            var m0 = PnsJson.Read<PnsMarathonMission>(started);
            Check(m0 != null && !string.IsNullOrEmpty(m0.Id) && m0.Title == "Add a /health endpoint", "pnsd: /pns/missions/start accepts a marathon mission");
            PnsMarathonMission m = null;
            sw.Restart();
            while (sw.Elapsed.TotalSeconds < 120)
            {
                Thread.Sleep(500);
                snap = PnsStatusSnapshot.Parse(client.Send("GET", "/pns/status", null).Result);
                m = snap == null || m0 == null ? null : snap.Missions.FirstOrDefault(x => x.Id == m0.Id);
                if (m != null && (m.Status == Pns.Failed || m.Status == Pns.Completed)) break;
            }
            Check(m != null && m.Status == Pns.Failed && m.Subtasks.Count == 3 && m.Subtasks[0].Attempts == 2 && m.Subtasks[0].Status == Pns.Failed && m.Subtasks[1].Status == Pns.Queued, "pnsd mission: unreachable model → fallback plan, fiber retried once, mission failed (" + (m == null ? "none" : m.Status + " " + string.Join(",", m.Subtasks.Select(s => s.Status + "/" + s.Attempts))) + ")");
            Check(m != null && (m.Subtasks[0].ResultSummary ?? "").Length > 0 && !string.IsNullOrEmpty(m.LastError), "pnsd mission: the fiber reports the real error (" + (m == null ? "" : m.Subtasks[0].ResultSummary) + ")");
            Check(snap != null && snap.RecentSpikes.Any(s => s.Kind == Pns.SpikeFiberSpawn) && snap.RecentSpikes.Any(s => s.Kind == Pns.SpikeRem && s.MissionId == m0.Id), "pnsd mission: fiber spawns and the closing REM cycle are on the spike feed");
            string worktrees = Path.Combine(pnsDir, "worktrees");
            Check((!Directory.Exists(worktrees) || Directory.GetDirectories(worktrees, "*", SearchOption.AllDirectories).All(d => !File.Exists(Path.Combine(d, "server.py")))) && Git(mrepo, "worktree list").Trim().Split('\n').Length == 1, "pnsd mission: failed fibers release their worktrees");
            Check(Git(mrepo, "branch --list pns/*").Trim().Length == 0 && Git(mrepo, "status --porcelain").Trim().Length == 0, "pnsd mission: failed fibers leave no branches and an untouched working tree");
            Check(File.Exists(Path.Combine(pnsDir, "missions.json")) && File.ReadAllText(Path.Combine(pnsDir, "missions.json")).Contains(m0.Id), "pnsd mission: state is checkpointed to missions.json");

            client.Send("POST", "/pns/shutdown", A()).Wait();
            Check(proc.WaitForExit(10000), "pnsd: /pns/shutdown stops the daemon");
        }
        finally
        {
            if (!proc.HasExited) { try { proc.Kill(); } catch (InvalidOperationException) { } }
        }

        // the GUI path: boot pnsd from an orchestrator, poll it, stop it
        Defaults.Set("ai_key_mode", "local");
        Defaults.Flush();
        var gui = new PnsOrchestrator(Path.Combine(TaskFiles.Home, "pns"));
        bool online = gui.EnsureDaemonRunning().Result;
        int pid = gui.RemotePid;
        Check(online && gui.RemoteOnline && pid > 0 && pid != Process.GetCurrentProcess().Id, "GUI: Boot 24/7 pnsd spawns a detached daemon and attaches to it (PID " + pid + ")");
        gui.StopDaemon().Wait();
        bool exited = false;
        try { exited = Process.GetProcessById(pid).WaitForExit(10000); } catch (ArgumentException) { exited = true; }
        Check(exited && !gui.RemoteOnline, "GUI: Stop pnsd shuts the daemon down");
    }

    // ── views ───────────────────────────────────────────────────────────────
    static List<string> Texts(DependencyObject d)
    {
        var list = new List<string>();
        var tb = d as TextBlock;
        if (tb != null && !string.IsNullOrEmpty(tb.Text)) list.Add(tb.Text);
        int n = VisualTreeHelper.GetChildrenCount(d);
        for (int i = 0; i < n; i++) list.AddRange(Texts(VisualTreeHelper.GetChild(d, i)));
        return list;
    }

    static List<string> Render(FrameworkElement e, double w, double h, string png)
    {
        e.Measure(new Size(w, h));
        e.Arrange(new Rect(0, 0, w, h));
        e.UpdateLayout();
        var bmp = new RenderTargetBitmap((int)(w * 2), (int)(h * 2), 192, 192, PixelFormats.Pbgra32);
        var dv = new DrawingVisual();
        using (var dc = dv.RenderOpen())
        {
            dc.DrawRectangle(Theme.Current.WorkspaceBackground, null, new Rect(0, 0, w, h));
            dc.DrawRectangle(new VisualBrush(e), null, new Rect(0, 0, w, h));
        }
        bmp.Render(dv);
        var enc = new PngBitmapEncoder();
        enc.Frames.Add(BitmapFrame.Create(bmp));
        using (var fs = File.Create(png)) enc.Save(fs);
        return Texts(e);
    }

    static void RenderTests(string root, ConsensusResult result, PnsOrchestrator brain)
    {
        var app = new Application();
        Styles.Install(app);
        string outDir = AppDomain.CurrentDomain.BaseDirectory;

        ConsensusEngine.Shared.Reset();
        var empty = Render(new ConsensusView(AppState.Shared), 1000, 640, Path.Combine(outDir, "test-consensus-empty.png"));
        Check(empty.Contains("Consensus Engine") && empty.Contains("Builder vs. Auditor — Verified Code Generation") && empty.Contains("Consensus Engine will verify code changes before applying") && empty.Contains("✓ Active") && empty.Contains("Run Consensus"), "ConsensusView: empty state (macOS header + Builder vs Auditor + request box)");

        ConsensusEngine.Shared.Latest = result;
        var full = Render(new ConsensusView(AppState.Shared), 1000, 900, Path.Combine(outDir, "test-consensus-result.png"));
        Check(full.Contains(ConsensusText.Verdict(result.Verdict)) && full.Contains(result.Summary) && full.Contains("Security Findings") && full.Contains("Auditor Tests") && full.Contains("Builder Changes") && full.Contains("src/calc.py"), "ConsensusView: result (verdict banner, stats, findings, tests, changes)");
        Check(result.Verdict != ConsensusVerdict.Rejected || (full.Contains("Apply Anyway (Override)") && full.Contains("Retry with Builder")), "ConsensusView: a rejected run offers Override / Retry");
        ConsensusEngine.Shared.Reset();

        var dash = Render(new PnsView(AppState.Shared, brain), 1200, 1500, Path.Combine(outDir, "test-pns-dashboard.png"));
        Check(dash.Contains("PNS — Pseudo Neural System") && dash.Contains("In-Process Standby") && dash.Contains("Dispatch 24/7 Autonomous Marathon Mission") && dash.Contains("24/7 Marathon Missions Ledger"), "PnsView: header, daemon state, launcher and mission ledger");
        Check(dash.Contains("Efferent MCP Nerve Tracts (MCP_1 ... MCP_xx)") && dash.Contains("Somatic Motor Agent Tracts (Agent_1 ... Agent_n)") && dash.Contains("Hebbian Synaptic Weights & Myelination (W_e)") && dash.Contains("MYELIN") && dash.Contains("Thalamic & Autonomic Spike Feed (WAL)"), "PnsView: tract topology, synapse table and spike feed");
    }
}
