// Consensus Engine — port of Services/ConsensusEngine.swift + Views/AI/ConsensusEngineView.swift: Builder vs. Auditor verified
// code generation. The Builder agent edits a sandbox copy of the workspace; the adversarial Auditor agent writes tests into the
// sandbox's .consensus/ folder and names one command per test; MicroCode runs those commands itself (the verdict comes from exit
// codes, not from the model's opinion), adds the macOS static security scans, votes, and only then applies the Builder's change
// to the real workspace — automatically with "Auto-apply on pass", otherwise when the user clicks Apply.
// Also holds the helpers shared with PNS 24/7: isolated copies (WorkspaceCopy), git (GitCli) and approvals for isolated runs.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Ellipse = System.Windows.Shapes.Ellipse;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    // ── shared: isolated copies, git, approvals ─────────────────────────────

    /// <summary>A failure preparing or joining an isolated copy (shown to the user as is).</summary>
    public class IsolationException : Exception
    {
        public IsolationException(string message) : base(message) { }
    }

    /// <summary>Copies a project into an isolated folder (the Consensus sandbox, PNS fibers for folders without git).</summary>
    public static class WorkspaceCopy
    {
        /// <summary>Never copied: version control data, dependency caches, build outputs and agent state (regenerated in the copy when needed).</summary>
        public static readonly HashSet<string> SkipDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            ".git", ".hg", ".svn", "node_modules", ".venv", "venv", "__pycache__", ".pytest_cache", ".mypy_cache", ".vs", ".idea", "DerivedData", "Pods",
            ".next", ".gradle", "target", "bin", "obj", "out", "out-dev", "dist", "build", ".build", ".codetuner-build", "coverage", ".microcode", ".consensus"
        };
        public const long MaxFileBytes = 20L << 20, MaxTotalBytes = 400L << 20;
        public const int MaxFiles = 30000;

        /// <summary>Workspace-relative paths (forward slashes) of the files under <paramref name="root"/>, without SkipDirs, links or .git files.</summary>
        public static IEnumerable<string> Files(string root)
        {
            root = Path.GetFullPath(root).TrimEnd('\\');
            var stack = new Stack<string>();
            stack.Push(root);
            while (stack.Count > 0)
            {
                string dir = stack.Pop();
                string[] files, dirs;
                try { files = Directory.GetFiles(dir); dirs = Directory.GetDirectories(dir); }
                catch (IOException) { continue; } // vanished or unreadable folder: nothing to copy from it
                catch (UnauthorizedAccessException) { continue; }
                foreach (var f in files)
                {
                    if (string.Equals(Path.GetFileName(f), ".git", StringComparison.OrdinalIgnoreCase)) continue; // a worktree's .git file points at the real repo
                    yield return f.Substring(root.Length + 1).Replace('\\', '/');
                }
                foreach (var d in dirs)
                {
                    if (SkipDirs.Contains(Path.GetFileName(d))) continue;
                    try { if ((File.GetAttributes(d) & FileAttributes.ReparsePoint) != 0) continue; } catch (IOException) { continue; }
                    stack.Push(d);
                }
            }
        }

        /// <summary>Copies src into dst and returns relative path → SHA-256 of every copied file.</summary>
        public static Dictionary<string, string> Copy(string src, string dst)
        {
            var hashes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            long total = 0;
            int count = 0;
            Directory.CreateDirectory(dst);
            foreach (var rel in Files(src))
            {
                string from = System.IO.Path.Combine(src, rel.Replace('/', '\\'));
                byte[] bytes = TryRead(from, MaxFileBytes);
                if (bytes == null) continue; // too large or locked by another program: not part of the copy
                if (++count > MaxFiles || (total += bytes.Length) > MaxTotalBytes)
                    throw new IsolationException("The project is too large for an isolated copy (over " + MaxFiles + " files or " + (MaxTotalBytes >> 20) + " MB outside dependency and build folders).");
                string to = System.IO.Path.Combine(dst, rel.Replace('/', '\\'));
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(to));
                File.WriteAllBytes(to, bytes);
                hashes[rel] = Sha(bytes);
            }
            return hashes;
        }

        public static byte[] TryRead(string path, long maxBytes)
        {
            try
            {
                var fi = new FileInfo(path);
                if (!fi.Exists || fi.Length > maxBytes) return null;
                return File.ReadAllBytes(path);
            }
            catch (IOException) { return null; }
            catch (UnauthorizedAccessException) { return null; }
        }

        public static string Sha(byte[] bytes)
        {
            using (var sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant();
        }

        public static bool IsBinary(byte[] b)
        {
            if (b.Length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) return false; // UTF-16 text
            int n = Math.Min(b.Length, 8000);
            for (int i = 0; i < n; i++) if (b[i] == 0) return true;
            return false;
        }

        public static string Decode(byte[] b)
        {
            using (var r = new StreamReader(new MemoryStream(b), Encoding.UTF8, true)) return r.ReadToEnd();
        }

        /// <summary>Deletes a folder tree, clearing read-only flags (git objects) and retrying while another process lets go.</summary>
        public static void DeleteTree(string dir)
        {
            for (int attempt = 0; attempt < 5 && dir != null && Directory.Exists(dir); attempt++)
            {
                try
                {
                    foreach (var f in Directory.GetFiles(dir, "*", SearchOption.AllDirectories)) File.SetAttributes(f, FileAttributes.Normal);
                    Directory.Delete(dir, true);
                }
                catch (IOException) { Thread.Sleep(150 * (attempt + 1)); }
                catch (UnauthorizedAccessException) { Thread.Sleep(150 * (attempt + 1)); }
            }
        }
    }

    /// <summary>git on PATH, run without a console or credential prompts.</summary>
    public static class GitCli
    {
        public class Result { public int Code = -1; public string Out = "", Err = ""; public bool Ok { get { return Code == 0; } } }

        public static Result Run(string cwd, string args, string stdin, int timeoutMs)
        {
            var r = new Result();
            var psi = new ProcessStartInfo("git", args)
            {
                WorkingDirectory = cwd, UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, RedirectStandardInput = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
            };
            psi.EnvironmentVariables["GIT_TERMINAL_PROMPT"] = "0";
            try
            {
                using (var p = Process.Start(psi))
                {
                    var o = p.StandardOutput.ReadToEndAsync(); var e = p.StandardError.ReadToEndAsync();
                    try
                    {
                        if (stdin != null) { var w = new StreamWriter(p.StandardInput.BaseStream, new UTF8Encoding(false)); w.Write(stdin); w.Flush(); }
                        p.StandardInput.Close();
                    }
                    catch (IOException) { } // git exited before reading its input; its exit code says what happened
                    if (!p.WaitForExit(timeoutMs))
                    {
                        KillTree(p.Id);
                        r.Err = "git " + args + " timed out after " + (timeoutMs / 1000) + "s";
                        return r;
                    }
                    p.WaitForExit();
                    r.Code = p.ExitCode; r.Out = o.Result; r.Err = e.Result;
                }
            }
            catch (System.ComponentModel.Win32Exception ex) { r.Err = "git is not available: " + ex.Message; }
            return r;
        }

        public static void KillTree(int pid)
        {
            try { using (var k = Process.Start(new ProcessStartInfo("taskkill", "/T /F /PID " + pid) { CreateNoWindow = true, UseShellExecute = false })) k.WaitForExit(5000); }
            catch (System.ComponentModel.Win32Exception) { } // taskkill missing: the process is left to finish on its own
        }

        /// <summary>The repository root that contains <paramref name="dir"/>, or null.</summary>
        public static string TopLevel(string dir)
        {
            var r = Run(dir, "rev-parse --show-toplevel", null, 8000);
            if (!r.Ok || r.Out.Trim().Length == 0) return null;
            try { return System.IO.Path.GetFullPath(r.Out.Trim()).TrimEnd('\\'); } catch (ArgumentException) { return null; }
        }

        /// <summary>One argument quoted for the Windows command line (CommandLineToArgvW rules).</summary>
        public static string Q(string s)
        {
            s = s ?? "";
            if (s.Length > 0 && s.IndexOfAny(new[] { ' ', '\t', '"' }) < 0) return s;
            var sb = new StringBuilder("\"");
            int bs = 0;
            foreach (char c in s)
            {
                if (c == '\\') { bs++; continue; }
                if (c == '"') { sb.Append('\\', bs * 2 + 1).Append('"'); bs = 0; continue; }
                sb.Append('\\', bs).Append(c); bs = 0;
            }
            sb.Append('\\', bs * 2).Append('"');
            return sb.ToString();
        }

        public static string FirstLine(string s)
        {
            var l = (s ?? "").Replace("\r", "").Split('\n').Select(x => x.Trim()).FirstOrDefault(x => x.Length > 0);
            return l ?? "";
        }
    }

    /// <summary>A command an isolated run wants to execute, waiting for the user in the Consensus or PNS tab.</summary>
    public class IsolatedApproval
    {
        public string Id = Guid.NewGuid().ToString("N"), Source, Actor, Request, Detail;
        public DateTime Created = DateTime.Now;
        public readonly TaskCompletionSource<bool> Tcs = new TaskCompletionSource<bool>();
    }

    /// <summary>Tool approval for isolated runs. Reads and edits stay inside the sandbox / worktree (the real workspace only changes
    /// through Apply or the PNS join), so they pass; a shell command can reach the rest of the machine, so it follows the user's
    /// approval mode — Full Auto runs it, otherwise the owning tab asks (and the request expires like a chat approval).</summary>
    public static class IsolatedApprovals
    {
        static readonly List<IsolatedApproval> Pending = new List<IsolatedApproval>();
        public static event Action Changed;
        /// <summary>Set in the headless pnsd daemon: nobody can answer there, so anything that needs approval is denied at once.</summary>
        public static bool Headless;

        public static bool AutoApproveShell { get { return Defaults.Bool("agentAutoApproveTools", false) || Defaults.Str("toolApprovalMode", "smart") == "yolo"; } }

        public static List<IsolatedApproval> PendingFor(string source) { lock (Pending) return Pending.Where(a => a.Source == source).ToList(); }

        public static Func<ToolStep, Dictionary<string, object>, Task<bool>> Approver(string source, string actor)
        {
            return (step, args) =>
            {
                if (step.Name != "shell" || AutoApproveShell) return Task.FromResult(true);
                return Ask(source, actor, AgentRunner.RequestText(step), step.Target ?? "", 65);
            };
        }

        public static Task<bool> Ask(string source, string actor, string request, string detail, int timeoutSeconds)
        {
            if (Headless) return Task.FromResult(false);
            var a = new IsolatedApproval { Source = source, Actor = actor, Request = request, Detail = detail };
            lock (Pending) Pending.Add(a);
            Raise();
            Task.Delay(TimeSpan.FromSeconds(timeoutSeconds)).ContinueWith(t => Resolve(a, false));
            return a.Tcs.Task;
        }

        public static void Resolve(IsolatedApproval a, bool ok)
        {
            bool had;
            lock (Pending) had = Pending.Remove(a);
            a.Tcs.TrySetResult(ok);
            if (had) Raise();
        }

        public static void CancelAll(string source) { foreach (var a in PendingFor(source)) Resolve(a, false); }

        static void Raise()
        {
            var h = Changed;
            if (h == null) return;
            var app = Application.Current;
            if (app != null && !app.Dispatcher.CheckAccess()) app.Dispatcher.BeginInvoke(h); else h();
        }
    }

    // ── Consensus model ─────────────────────────────────────────────────────

    public enum ConsensusVerdict { Approved, Rejected, Override, Timeout, Error }
    public enum ConsensusPhase { Idle, Sandboxing, Building, Auditing, Testing, Voting, Applying, Complete, Blocked }
    public enum SandboxChangeType { Create, Modify, Delete }
    public enum AuditorTestCategory { Property, Edge, Security, TypeSafety, Performance, Regression }
    public enum AuditorTestStatus { Passed, Failed, Error, Skipped }
    public enum FindingSeverity { Info, Low, Medium, High, Critical }

    /// <summary>The macOS rawValue strings.</summary>
    public static class ConsensusText
    {
        public static string Verdict(ConsensusVerdict v)
        {
            switch (v) { case ConsensusVerdict.Approved: return "Approved"; case ConsensusVerdict.Rejected: return "Rejected"; case ConsensusVerdict.Override: return "User Override"; case ConsensusVerdict.Timeout: return "Timeout"; default: return "Error"; }
        }
        public static string Phase(ConsensusPhase p)
        {
            switch (p)
            {
                case ConsensusPhase.Sandboxing: return "Creating Sandbox"; case ConsensusPhase.Building: return "Builder Agent Working"; case ConsensusPhase.Auditing: return "Auditor Agent Verifying";
                case ConsensusPhase.Testing: return "Running Tests"; case ConsensusPhase.Voting: return "Consensus Vote"; case ConsensusPhase.Applying: return "Applying Changes";
                case ConsensusPhase.Complete: return "Complete"; case ConsensusPhase.Blocked: return "Blocked"; default: return "Idle";
            }
        }
        public static string Category(AuditorTestCategory c)
        {
            switch (c) { case AuditorTestCategory.Property: return "Property-Based"; case AuditorTestCategory.Edge: return "Edge Case"; case AuditorTestCategory.Security: return "Security"; case AuditorTestCategory.TypeSafety: return "Type Safety"; case AuditorTestCategory.Performance: return "Performance"; default: return "Regression"; }
        }
        public static string Severity(FindingSeverity s)
        {
            switch (s) { case FindingSeverity.Critical: return "Critical"; case FindingSeverity.High: return "High"; case FindingSeverity.Medium: return "Medium"; case FindingSeverity.Low: return "Low"; default: return "Info"; }
        }
        public static string Change(SandboxChangeType t) { return t == SandboxChangeType.Create ? "Created" : t == SandboxChangeType.Delete ? "Deleted" : "Modified"; }
    }

    public class SandboxFileChange
    {
        /// <summary>Workspace-relative, forward slashes.</summary>
        public string FilePath;
        public SandboxChangeType ChangeType;
        /// <summary>Text before / after (null for a binary file or the missing side).</summary>
        public string OldContent, NewContent;
        /// <summary>Exact bytes to write on Apply (Create / Modify).</summary>
        public byte[] NewBytes;
        /// <summary>SHA-256 of the workspace file when the sandbox was made (null for Create) — Apply refuses to overwrite a file that changed since.</summary>
        public string BaseHash;
        public bool IsBinary;
        public int Added, Removed;
        /// <summary>Unified diff (text files).</summary>
        public string Diff = "";
        public string TypeLabel { get { return ConsensusText.Change(ChangeType); } }
    }

    public class AuditorTestCase
    {
        public string Name = "", Command = "", TestCode = "", Rationale = "", Output = "";
        public AuditorTestCategory Category = AuditorTestCategory.Regression;
        public AuditorTestStatus Status = AuditorTestStatus.Skipped;
        public int ExecutionTimeMs;
        /// <summary>Decided by MicroCode's own static scan — nothing to execute.</summary>
        public bool Static;
    }

    public class SecurityFinding
    {
        public FindingSeverity Severity;
        public string Title = "", Description = "", FilePath = "";
        /// <summary>1-based; 0 when unknown.</summary>
        public int Line;
    }

    public class ConsensusResult
    {
        public string Id = Guid.NewGuid().ToString("N"), Request = "", Workspace, BuilderSummary, Note, ApplyReport;
        public ConsensusVerdict Verdict;
        public List<SandboxFileChange> BuilderChanges = new List<SandboxFileChange>();
        public List<AuditorTestCase> AuditorTests = new List<AuditorTestCase>();
        public List<SecurityFinding> SecurityIssues = new List<SecurityFinding>();
        public int PassedTests, FailedTests, TotalTests, ExecutionTimeMs;
        public DateTime Timestamp = DateTime.Now;
        public bool Applied;

        public double PassRate { get { return TotalTests > 0 ? (double)PassedTests / TotalTests * 100.0 : 0.0; } }
        public string Summary { get { return ConsensusText.Verdict(Verdict) + ": " + PassedTests + "/" + TotalTests + " tests passed (" + PassRate.ToString("0", CultureInfo.InvariantCulture) + "%)"; } }

        /// <summary>Counts from AuditorTests (a test error counts as a failure).</summary>
        public void Tally()
        {
            PassedTests = AuditorTests.Count(t => t.Status == AuditorTestStatus.Passed);
            FailedTests = AuditorTests.Count(t => t.Status == AuditorTestStatus.Failed || t.Status == AuditorTestStatus.Error);
            TotalTests = AuditorTests.Count;
        }
    }

    public class ApplyReport
    {
        public readonly List<string> Applied = new List<string>();
        /// <summary>"path — reason".</summary>
        public readonly List<string> Skipped = new List<string>();
        public string Text
        {
            get
            {
                string s = "Applied " + Applied.Count + " file" + (Applied.Count == 1 ? "" : "s");
                if (Skipped.Count > 0) s += "; skipped " + Skipped.Count + ": " + string.Join("; ", Skipped);
                return s + ".";
            }
        }
    }

    // ── Sandbox (SandboxManager) ────────────────────────────────────────────

    /// <summary>An isolated copy of the workspace for the Builder and the Auditor (%TEMP%\MicroCode-Sandbox\&lt;id&gt;).</summary>
    public class ConsensusSandbox : IDisposable
    {
        public const string TestDir = ".consensus";
        static readonly HashSet<string> ArtifactExt = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        { ".exe", ".dll", ".pdb", ".obj", ".o", ".a", ".lib", ".so", ".dylib", ".class", ".pyc", ".pyo", ".ilk", ".exp", ".idb", ".cache" };

        public readonly string WorkspaceRoot, Root;
        readonly Dictionary<string, string> _baseline;
        /// <summary>Files the Auditor changed that could not be restored exactly (the original changed meanwhile).</summary>
        public readonly List<string> IntegrityFailures = new List<string>();

        ConsensusSandbox(string ws, string root, Dictionary<string, string> baseline) { WorkspaceRoot = ws; Root = root; _baseline = baseline; }

        public static ConsensusSandbox Create(string workspace, string parent)
        {
            string ws = System.IO.Path.GetFullPath(workspace).TrimEnd('\\');
            string root = System.IO.Path.Combine(parent ?? System.IO.Path.Combine(System.IO.Path.GetTempPath(), "MicroCode-Sandbox"), Guid.NewGuid().ToString("N").Substring(0, 12));
            try { return new ConsensusSandbox(ws, root, WorkspaceCopy.Copy(ws, root)); }
            catch { WorkspaceCopy.DeleteTree(root); throw; }
        }

        string InSandbox(string rel) { return System.IO.Path.Combine(Root, rel.Replace('/', '\\')); }
        string InWorkspace(string rel) { return System.IO.Path.Combine(WorkspaceRoot, rel.Replace('/', '\\')); }

        /// <summary>Paths git ignores in the workspace (build outputs and caches the Builder's commands may have produced).</summary>
        HashSet<string> GitIgnored(IEnumerable<string> rels)
        {
            var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (!Directory.Exists(System.IO.Path.Combine(WorkspaceRoot, ".git")) && !File.Exists(System.IO.Path.Combine(WorkspaceRoot, ".git"))) return set;
            var list = rels.ToList();
            if (list.Count == 0) return set;
            var r = GitCli.Run(WorkspaceRoot, "check-ignore -z --stdin", string.Join("\0", list) + "\0", 20000);
            if (r.Code == 0) foreach (var p in r.Out.Split('\0')) if (p.Length > 0) set.Add(p);
            return set;
        }

        static bool Countable(string rel, HashSet<string> ignored)
        {
            return !ArtifactExt.Contains(System.IO.Path.GetExtension(rel)) && !ignored.Contains(rel);
        }

        /// <summary>What the Builder created, modified or deleted relative to the workspace at sandbox time. Agent state (.microcode/),
        /// the Auditor's .consensus/, dependency/build folders, gitignored paths and compiled binaries are not part of a change.</summary>
        public List<SandboxFileChange> CollectChanges()
        {
            var files = WorkspaceCopy.Files(Root).ToList();
            var ignored = GitIgnored(files.Concat(_baseline.Keys).Distinct(StringComparer.OrdinalIgnoreCase));
            var changes = new List<SandboxFileChange>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var rel in files)
            {
                if (!Countable(rel, ignored)) continue;
                seen.Add(rel);
                byte[] bytes = WorkspaceCopy.TryRead(InSandbox(rel), long.MaxValue);
                if (bytes == null) continue;
                string hash = WorkspaceCopy.Sha(bytes), baseHash;
                bool existed = _baseline.TryGetValue(rel, out baseHash);
                if (existed && baseHash == hash) continue;
                var c = new SandboxFileChange { FilePath = rel, ChangeType = existed ? SandboxChangeType.Modify : SandboxChangeType.Create, NewBytes = bytes, BaseHash = existed ? baseHash : null, IsBinary = WorkspaceCopy.IsBinary(bytes) };
                if (!c.IsBinary)
                {
                    c.NewContent = WorkspaceCopy.Decode(bytes);
                    if (existed) { var old = WorkspaceCopy.TryRead(InWorkspace(rel), long.MaxValue); c.OldContent = old == null ? "" : WorkspaceCopy.Decode(old); }
                }
                Stats(c);
                changes.Add(c);
            }
            foreach (var kv in _baseline)
            {
                if (seen.Contains(kv.Key) || !Countable(kv.Key, ignored) || File.Exists(InSandbox(kv.Key))) continue;
                var c = new SandboxFileChange { FilePath = kv.Key, ChangeType = SandboxChangeType.Delete, BaseHash = kv.Value };
                var old = WorkspaceCopy.TryRead(InWorkspace(kv.Key), long.MaxValue);
                c.IsBinary = old != null && WorkspaceCopy.IsBinary(old);
                if (old != null && !c.IsBinary) c.OldContent = WorkspaceCopy.Decode(old);
                Stats(c);
                changes.Add(c);
            }
            return changes.OrderBy(c => c.FilePath, StringComparer.OrdinalIgnoreCase).ToList();
        }

        static void Stats(SandboxFileChange c)
        {
            if (c.IsBinary) { c.Diff = "Binary file " + c.TypeLabel.ToLowerInvariant(); return; }
            var d = Differ.Compute(c.OldContent ?? "", c.NewContent ?? "", 3);
            c.Added = d.Added; c.Removed = d.Removed;
            var lines = d.Lines.Take(600).Select(l => l.Kind == DiffKind.Hunk ? l.Text : (l.Kind == DiffKind.Add ? "+" : l.Kind == DiffKind.Del ? "-" : " ") + l.Text);
            c.Diff = string.Join("\n", lines) + (d.Lines.Count > 600 ? "\n… (diff truncated)" : "");
        }

        /// <summary>Puts the sandbox back to exactly the Builder's result outside .consensus/ before the tests run, so the Auditor
        /// cannot "fix" the code it is supposed to break. Returns the files that had to be reverted.</summary>
        public List<string> RestoreBuilderState(List<SandboxFileChange> builderChanges)
        {
            var expected = new Dictionary<string, string>(_baseline, StringComparer.OrdinalIgnoreCase);
            var builderBytes = new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);
            foreach (var c in builderChanges)
            {
                if (c.ChangeType == SandboxChangeType.Delete) expected.Remove(c.FilePath);
                else { expected[c.FilePath] = WorkspaceCopy.Sha(c.NewBytes); builderBytes[c.FilePath] = c.NewBytes; }
            }
            var files = WorkspaceCopy.Files(Root).ToList();
            var ignored = GitIgnored(files.Concat(expected.Keys).Distinct(StringComparer.OrdinalIgnoreCase));
            var reverted = new List<string>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var rel in files)
            {
                if (!Countable(rel, ignored)) continue;
                seen.Add(rel);
                string want;
                if (!expected.TryGetValue(rel, out want)) { File.Delete(InSandbox(rel)); reverted.Add(rel); continue; }
                var now = WorkspaceCopy.TryRead(InSandbox(rel), long.MaxValue);
                if (now != null && WorkspaceCopy.Sha(now) == want) continue;
                if (Restore(rel, want, builderBytes)) reverted.Add(rel); else IntegrityFailures.Add(rel);
            }
            foreach (var kv in expected)
            {
                if (seen.Contains(kv.Key) || !Countable(kv.Key, ignored)) continue;
                if (Restore(kv.Key, kv.Value, builderBytes)) reverted.Add(kv.Key); else IntegrityFailures.Add(kv.Key);
            }
            return reverted;
        }

        bool Restore(string rel, string hash, Dictionary<string, byte[]> builderBytes)
        {
            byte[] b;
            if (!builderBytes.TryGetValue(rel, out b))
            {
                b = WorkspaceCopy.TryRead(InWorkspace(rel), long.MaxValue);
                if (b == null || WorkspaceCopy.Sha(b) != hash) return false;
            }
            string full = InSandbox(rel);
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(full));
            File.WriteAllBytes(full, b);
            return true;
        }

        public void Dispose() { WorkspaceCopy.DeleteTree(Root); }
    }

    // ── Auditor (AuditorAgent) ──────────────────────────────────────────────

    public static class ConsensusAuditor
    {
        public const int MaxTests = 12, TestTimeoutSeconds = 120;

        /// <summary>AuditorAgent.systemPrompt, plus how tests run on Windows.</summary>
        public static string SystemPrompt(string sandboxRoot)
        {
            return "You are a Senior Security Auditor and QA Engineer. Your job is to BREAK the code that was just written.\n\n" +
                "Your responsibilities:\n1. Generate property-based tests that exercise edge cases, boundary values, and error paths\n2. Check for security vulnerabilities: injection, buffer overflow, race conditions, data leaks\n3. Verify type safety and null handling\n4. Test performance characteristics (no O(n²) when O(n) is possible)\n5. Ensure the code actually solves the original requirement\n\n" +
                "Rules:\n- Be ADVERSARIAL. Your tests should be HARD to pass, not rubber stamps.\n- Focus on what could go WRONG, not what goes right.\n- For each test, explain WHY it matters.\n- Categorize tests as: property, edge_case, security, type_safety, performance, regression\n\n" +
                "## How your tests run (MicroCode for Windows)\n" +
                "- You work in the Builder's sandbox (root: `" + sandboxRoot + "`). Write test files ONLY under `.consensus/` — any other edit is reverted before the tests run.\n" +
                "- Use the project's language and test tooling when it exists; otherwise write small standalone scripts. You may run them with `shell` while writing them, but never change the Builder's code to make a test pass.\n" +
                "- Each test must be ONE Windows command (cmd.exe, working directory = sandbox root) that exits 0 when the code behaves correctly and non-zero when it does not. Include the project's own test command as a `regression` test when one exists. At most " + MaxTests + " tests.\n" +
                "- MicroCode runs every command itself and decides the verdict from the exit codes — your opinion of the result does not count.\n\n" +
                "Finish your reply with exactly one JSON block:\n```json\n{\"tests\": [{\"name\": \"test_empty_input_returns_default\", \"category\": \"edge_case\", \"command\": \"python .consensus\\\\test_calc.py empty\", \"rationale\": \"Empty input should not crash or return undefined\"}],\n \"security_findings\": [{\"severity\": \"high\", \"title\": \"SQL Injection in query builder\", \"description\": \"User input is concatenated directly into SQL string at line 45\", \"file\": \"database.py\", \"line\": 45}]}\n```";
        }

        public static string BuildPrompt(string request, List<SandboxFileChange> changes)
        {
            var sb = new StringBuilder("Analyze the following code changes and generate adversarial tests.\n\n## Original User Request\n" + request + "\n\n## Code Changes\n");
            foreach (var c in changes)
            {
                string diff = c.Diff ?? "";
                if (sb.Length + diff.Length > 60000) { sb.Append("\n### " + c.TypeLabel + ": " + c.FilePath + "\n(diff omitted — read the file in the sandbox)\n"); continue; }
                sb.Append("\n### " + c.TypeLabel + ": " + c.FilePath + "\n```diff\n" + diff + "\n```\n");
            }
            sb.Append("\nGenerate tests that could BREAK this code. Be thorough and adversarial.\nFocus on edge cases, security issues, and correctness verification.");
            return sb.ToString();
        }

        /// <summary>Reads the Auditor's JSON plan (```json fence or a bare object; the macOS `findings` shape is accepted too).</summary>
        public static void ParseReply(string reply, List<AuditorTestCase> tests, List<SecurityFinding> findings)
        {
            string text = reply ?? "";
            Dictionary<string, object> plan = null;
            foreach (Match m in Regex.Matches(text, "```(?:json)?\\s*([\\s\\S]*?)```").Cast<Match>().Reverse())
            {
                var o = DJ.Obj(m.Groups[1].Value.Trim());
                if (IsPlan(o)) { plan = o; break; }
            }
            int tries = 0;
            for (int i = text.LastIndexOf('{'); plan == null && i >= 0 && tries < 300; i = i > 0 ? text.LastIndexOf('{', i - 1) : -1, tries++)
            {
                string cand = Balanced(text, i);
                if (cand == null) continue;
                var o = DJ.Obj(cand);
                if (IsPlan(o)) plan = o;
            }
            if (plan == null) return;
            var arr = DJ.Arr(plan, "tests");
            int n = 0;
            if (arr != null)
                foreach (var item in arr)
                {
                    var t = item as Dictionary<string, object>;
                    if (t == null) continue;
                    if (++n > MaxTests) break;
                    tests.Add(new AuditorTestCase
                    {
                        Name = DJ.Str(t, "name") ?? ("test_" + n), Category = Category(DJ.Str(t, "category")), Command = (DJ.Str(t, "command") ?? "").Trim(),
                        TestCode = DJ.Str(t, "test_code") ?? "", Rationale = DJ.Str(t, "rationale") ?? ""
                    });
                }
            foreach (var key in new[] { "security_findings", "findings" })
            {
                var fa = DJ.Arr(plan, key);
                if (fa == null) continue;
                foreach (var item in fa)
                {
                    var f = item as Dictionary<string, object>;
                    if (f == null) continue;
                    var line = DJ.Num(f, "line");
                    findings.Add(new SecurityFinding
                    {
                        Severity = Severity(DJ.Str(f, "severity")), Title = DJ.Str(f, "title") ?? "AI Audit Finding", Description = DJ.Str(f, "description") ?? "Unknown issue",
                        FilePath = DJ.Str(f, "file") ?? "", Line = line.HasValue ? (int)line.Value : 0
                    });
                }
            }
        }

        static bool IsPlan(Dictionary<string, object> o) { return o != null && (o.ContainsKey("tests") || o.ContainsKey("security_findings") || o.ContainsKey("findings")); }

        static string Balanced(string text, int start)
        {
            int depth = 0;
            bool inStr = false, esc = false;
            for (int j = start; j < text.Length; j++)
            {
                char c = text[j];
                if (inStr) { if (esc) esc = false; else if (c == '\\') esc = true; else if (c == '"') inStr = false; continue; }
                if (c == '"') inStr = true;
                else if (c == '{') depth++;
                else if (c == '}' && --depth == 0) return text.Substring(start, j - start + 1);
            }
            return null;
        }

        static AuditorTestCategory Category(string s)
        {
            switch ((s ?? "").Trim().ToLowerInvariant().Replace('-', '_').Replace(' ', '_'))
            {
                case "property": case "property_based": return AuditorTestCategory.Property;
                case "edge": case "edge_case": return AuditorTestCategory.Edge;
                case "security": return AuditorTestCategory.Security;
                case "type": case "type_safety": return AuditorTestCategory.TypeSafety;
                case "performance": case "perf": return AuditorTestCategory.Performance;
                default: return AuditorTestCategory.Regression;
            }
        }

        static FindingSeverity Severity(string s)
        {
            switch ((s ?? "").Trim().ToLowerInvariant())
            {
                case "critical": return FindingSeverity.Critical;
                case "high": return FindingSeverity.High;
                case "warning": case "medium": case "moderate": return FindingSeverity.Medium;
                case "low": return FindingSeverity.Low;
                default: return FindingSeverity.Info;
            }
        }

        static readonly Regex SecretAssign = new Regex(@"\b[\w.-]*(api[_-]?key|apikey|secret|passw(?:or)?d|pwd|token|private[_-]?key|access[_-]?key)[\w-]*\s*[:=]\s*[""'][^""'\s]{6,}[""']", RegexOptions.IgnoreCase);
        static readonly Regex SecretFormat = new Regex(@"(sk-[A-Za-z0-9_\-]{16,}|AIza[0-9A-Za-z_\-]{30,}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|xox[baprs]-[A-Za-z0-9\-]{10,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)");
        static readonly Regex EnvLookup = new Regex(@"environ|getenv|process\.env|GetEnvironmentVariable|ProcessInfo|UserDefaults|System\.getenv|ENV\[", RegexOptions.IgnoreCase);
        static readonly Regex SqlStatement = new Regex(@"\b(SELECT\s.+?\sFROM|INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM)\b", RegexOptions.IgnoreCase);
        static readonly Regex Interpolation = new Regex(@"\\\(|\$\{|\$@?""|\bf[""']|\.format\(|[""']\s*\+|\+\s*[""']|[""']\s*%\s*[\(\w]|String\.Format|sprintf", RegexOptions.IgnoreCase);
        static readonly Regex StringLiteral = new Regex("\"(?:[^\"\\\\]|\\\\.)*\"");
        static readonly Regex ForceUnwrap = new Regex(@"\bas!|\btry!|[\w\)\]]!(?!=)");

        /// <summary>The macOS static checks, run on the Builder's new content: hardcoded secrets (High), SQL built by string
        /// interpolation (Critical), and Swift force unwraps (a failed check + a Medium finding).</summary>
        public static void StaticScan(List<SandboxFileChange> changes, List<AuditorTestCase> tests, List<SecurityFinding> findings)
        {
            foreach (var c in changes)
            {
                if (c.ChangeType == SandboxChangeType.Delete || c.IsBinary || c.NewContent == null) continue;
                var lines = c.NewContent.Replace("\r\n", "\n").Split('\n');
                string name = System.IO.Path.GetFileName(c.FilePath);
                int secret = 0, sql = 0, unwrap = 0;
                string keyword = null;
                for (int i = 0; i < lines.Length; i++)
                {
                    string l = lines[i];
                    if (secret == 0 && !EnvLookup.IsMatch(l))
                    {
                        var m = SecretAssign.Match(l);
                        if (m.Success) { secret = i + 1; keyword = m.Groups[1].Value; }
                        else if (SecretFormat.IsMatch(l)) { secret = i + 1; keyword = "credential"; }
                    }
                    if (sql == 0 && SqlStatement.IsMatch(l) && Interpolation.IsMatch(l)) sql = i + 1;
                    if (unwrap == 0 && c.FilePath.EndsWith(".swift", StringComparison.OrdinalIgnoreCase))
                    {
                        string code = StringLiteral.Replace(l, "\"\"");
                        int cm = code.IndexOf("//", StringComparison.Ordinal);
                        if (cm >= 0) code = code.Substring(0, cm);
                        if (ForceUnwrap.IsMatch(code)) unwrap = i + 1;
                    }
                }
                if (unwrap > 0)
                {
                    tests.Add(new AuditorTestCase { Name = "check_force_unwrap_" + name, Category = AuditorTestCategory.Security, TestCode = "// Detected force unwrap (!) — potential crash", Status = AuditorTestStatus.Failed, Output = "Force unwraps found in " + c.FilePath + " — these can crash at runtime", Static = true });
                    findings.Add(new SecurityFinding { Severity = FindingSeverity.Medium, Title = "Force Unwrap Detected", Description = "Force unwrap (!) found — could crash at runtime with nil value", FilePath = c.FilePath, Line = unwrap });
                }
                if (sql > 0) findings.Add(new SecurityFinding { Severity = FindingSeverity.Critical, Title = "Potential SQL Injection", Description = "String interpolation used in what appears to be SQL query construction", FilePath = c.FilePath, Line = sql });
                if (secret > 0) findings.Add(new SecurityFinding { Severity = FindingSeverity.High, Title = "Hardcoded Secret Detected", Description = "Potential hardcoded " + keyword + " found — should use environment variables", FilePath = c.FilePath, Line = secret });
            }
        }

        /// <summary>Runs each test's command in the sandbox through the agent's shell tool (cmd.exe, timeout, process-tree kill).
        /// Exit 0 → Passed, non-zero → Failed, timeout / launch failure / destructive command → Error, no command → Skipped.</summary>
        public static void RunTests(List<AuditorTestCase> tests, string root, string workspace, int timeoutSeconds, CancellationToken ct)
        {
            foreach (var t in tests)
            {
                ct.ThrowIfCancellationRequested();
                if (t.Static) continue;
                if (string.IsNullOrWhiteSpace(t.Command)) { t.Status = AuditorTestStatus.Skipped; t.Output = "No command — the Auditor did not say how to run this test."; continue; }
                if (AgentRunner.Risk(new ToolStep { Name = "shell", Target = t.Command }) == "critical") { t.Status = AuditorTestStatus.Error; t.Output = "Not run: blocked as a destructive command."; continue; }
                var sw = Stopwatch.StartNew();
                string res = AgentRunner.ExecuteIsolated(root, workspace, "shell", new Dictionary<string, object> { { "command", t.Command }, { "timeout_seconds", timeoutSeconds } }, new ToolStep(), ct);
                t.ExecutionTimeMs = (int)sw.ElapsedMilliseconds;
                var m = Regex.Match(res, @"^(?:Error: )?exit code (-?\d+)\n?");
                if (m.Success)
                {
                    int code = int.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
                    string body = res.Substring(m.Length).Trim();
                    t.Status = code == 0 ? AuditorTestStatus.Passed : AuditorTestStatus.Failed;
                    t.Output = code == 0 ? body : "exit " + code + (body.Length > 0 ? ": " + body : "");
                }
                else { t.Status = AuditorTestStatus.Error; t.Output = res.StartsWith("Error: ") ? res.Substring(7) : res; }
                if (t.Output.Length > 4000) t.Output = t.Output.Substring(0, 4000) + "…";
            }
        }
    }

    // ── ConsensusOrchestrator ───────────────────────────────────────────────

    public class ConsensusEngine
    {
        static ConsensusEngine _shared;
        public static ConsensusEngine Shared { get { return _shared ?? (_shared = new ConsensusEngine()); } }

        // same keys and defaults as the macOS UserDefaults
        public bool Enabled { get { return Defaults.Bool("consensus_engine_enabled", true); } set { Defaults.Set("consensus_engine_enabled", value); Raise(); } }
        public bool AutoApplyOnPass { get { return Defaults.Bool("consensus_auto_apply", false); } set { Defaults.Set("consensus_auto_apply", value); Raise(); } }
        /// <summary>Strict = every test must pass (and at least one must run); non-strict = only High/Critical findings block.</summary>
        public bool StrictMode { get { return Defaults.Bool("consensus_strict_mode", true); } set { Defaults.Set("consensus_strict_mode", value); Raise(); } }

        public bool IsActive { get; private set; }
        public ConsensusPhase Phase { get; private set; }
        public ConsensusResult Latest;
        public string Request = "", BuilderActivity = "", AuditorActivity = "", Error;
        public DateTime StartedAt;
        public event Action Changed;
        CancellationTokenSource _cts;

        public void Raise()
        {
            var h = Changed;
            if (h == null) return;
            var app = Application.Current;
            if (app != null && !app.Dispatcher.CheckAccess()) app.Dispatcher.BeginInvoke(h); else h();
        }

        void SetPhase(ConsensusPhase p) { Phase = p; Raise(); }

        public static ConsensusVerdict Vote(bool strict, List<AuditorTestCase> tests, List<SecurityFinding> findings)
        {
            bool blocking = findings.Any(f => f.Severity >= FindingSeverity.High);
            if (!strict) return blocking ? ConsensusVerdict.Rejected : ConsensusVerdict.Approved;
            bool allPassed = tests.Count > 0 && tests.All(t => t.Status == AuditorTestStatus.Passed);
            return allPassed && !blocking ? ConsensusVerdict.Approved : ConsensusVerdict.Rejected;
        }

        /// <summary>Writes the Builder's change into the workspace. A file is skipped when Scope Lock protects it or when it changed in
        /// the workspace after the sandbox was made (never overwrites the user's newer work).</summary>
        public static ApplyReport Apply(string workspace, List<SandboxFileChange> changes)
        {
            var rep = new ApplyReport();
            string root = System.IO.Path.GetFullPath(workspace).TrimEnd('\\');
            foreach (var c in changes)
            {
                string target = System.IO.Path.GetFullPath(System.IO.Path.Combine(root, c.FilePath.Replace('/', '\\')));
                if (!target.StartsWith(root + "\\", StringComparison.OrdinalIgnoreCase)) { rep.Skipped.Add(c.FilePath + " — outside the workspace"); continue; }
                string blocked = ScopeLock.BlockedIn(workspace, target);
                if (blocked != null) { rep.Skipped.Add(c.FilePath + " — " + blocked.Replace("Error: ", "")); continue; }
                var now = WorkspaceCopy.TryRead(target, long.MaxValue);
                bool conflict = c.ChangeType == SandboxChangeType.Create ? File.Exists(target) : now == null || WorkspaceCopy.Sha(now) != c.BaseHash;
                if (conflict) { rep.Skipped.Add(c.FilePath + " — " + (c.ChangeType == SandboxChangeType.Create ? "already exists in the workspace" : "changed in the workspace after the sandbox was made")); continue; }
                try
                {
                    if (c.ChangeType == SandboxChangeType.Delete) File.Delete(target);
                    else { Directory.CreateDirectory(System.IO.Path.GetDirectoryName(target)); File.WriteAllBytes(target, c.NewBytes); }
                    rep.Applied.Add(c.FilePath);
                }
                catch (IOException ex) { rep.Skipped.Add(c.FilePath + " — " + ex.Message); }
                catch (UnauthorizedAccessException ex) { rep.Skipped.Add(c.FilePath + " — " + ex.Message); }
            }
            return rep;
        }

        static List<ChatMessage> Ask(string text) { return new List<ChatMessage> { new ChatMessage { Role = "user", Content = text } }; }

        static string BuilderPrompt(string root, string workspace)
        {
            return "You are the Builder agent of MicroCode's Consensus Engine, running natively on Windows.\nImplement the user's request by editing files in an isolated sandbox copy of the project. Nothing reaches the real project until an adversarial Auditor's tests pass.\n\n" +
                "## Sandbox\n- Root: `" + root + "` — a copy of `" + workspace + "` (.git, dependency and build folders are not copied). All tool paths are relative to it.\n- OS: Windows. `shell` runs cmd.exe inside the sandbox.\n\n" +
                "## Rules\n1. Read files before changing them; make minimal, focused edits with `replace_in_file` (`file_write` for new files).\n2. Never create files under `.consensus/` — that folder belongs to the Auditor.\n3. You may run the project's build or tests with `shell` to check your work.\n4. Never write API keys, passwords or tokens into files.\n5. Finish with a short summary of what you changed and why." + AgentContext.Extra(workspace);
        }

        AgentCallbacks Callbacks(string actor)
        {
            return new AgentCallbacks
            {
                OnActivity = s => { if (actor == "Builder") BuilderActivity = s; else AuditorActivity = s; Raise(); },
                Approve = IsolatedApprovals.Approver("consensus", actor)
            };
        }

        /// <summary>evaluate(): Builder in a sandbox → Auditor tests → MicroCode runs them → vote → apply only on a pass.</summary>
        public async Task Run(string request, string workspace)
        {
            request = (request ?? "").Trim();
            if (IsActive || request.Length == 0) return;
            if (workspace == null) { Error = "Open a project folder first — the Builder works on a sandbox copy of it."; Raise(); return; }
            if (!Enabled) { Error = "The Consensus Engine is disabled — switch it to Active first."; Raise(); return; }
            if (!AIConfig.IsConfigured) { Error = AIClient.NotConnectedText(); Raise(); return; }
            var cts = new CancellationTokenSource();
            _cts = cts;
            var ct = cts.Token;
            IsActive = true; Error = null; Latest = null; Request = request; BuilderActivity = AuditorActivity = ""; StartedAt = DateTime.Now;
            var sw = Stopwatch.StartNew();
            var result = new ConsensusResult { Request = request, Workspace = workspace };
            ConsensusSandbox sandbox = null;
            try
            {
                SetPhase(ConsensusPhase.Sandboxing);
                sandbox = await Task.Run(() => ConsensusSandbox.Create(workspace, null), ct);
                var sb = sandbox;

                SetPhase(ConsensusPhase.Building);
                var builder = await Task.Run(() => AgentRunner.RunIsolated(sb.Root, workspace, Ask(request), BuilderPrompt(sb.Root, workspace), false, Callbacks("Builder"), ct), ct);
                result.BuilderSummary = builder.Text;
                result.BuilderChanges = await Task.Run(() => sb.CollectChanges(), ct);
                if (result.BuilderChanges.Count == 0)
                {
                    result.Verdict = ConsensusVerdict.Error;
                    result.Note = "The Builder finished without changing any file — nothing to verify or apply.";
                }
                else
                {
                    SetPhase(ConsensusPhase.Auditing);
                    var changes = result.BuilderChanges;
                    var auditor = await Task.Run(() => AgentRunner.RunIsolated(sb.Root, workspace, Ask(ConsensusAuditor.BuildPrompt(request, changes)), ConsensusAuditor.SystemPrompt(sb.Root), false, Callbacks("Auditor"), ct), ct);
                    ConsensusAuditor.ParseReply(auditor.Text, result.AuditorTests, result.SecurityIssues);
                    var reverted = await Task.Run(() => sb.RestoreBuilderState(changes), ct);
                    foreach (var r in reverted)
                        result.SecurityIssues.Add(new SecurityFinding { Severity = FindingSeverity.Info, Title = "Auditor Edit Reverted", Description = "The Auditor changed " + r + " outside .consensus/; it was restored to the Builder's version before the tests ran.", FilePath = r });
                    foreach (var r in sb.IntegrityFailures)
                        result.SecurityIssues.Add(new SecurityFinding { Severity = FindingSeverity.High, Title = "Sandbox Integrity", Description = "The Auditor changed " + r + " and the original could not be restored, so the tests may not reflect the Builder's code.", FilePath = r });
                    ConsensusAuditor.StaticScan(changes, result.AuditorTests, result.SecurityIssues);

                    SetPhase(ConsensusPhase.Testing);
                    var withCommand = result.AuditorTests.Where(t => !t.Static && !string.IsNullOrWhiteSpace(t.Command)).ToList();
                    bool approved = true;
                    if (withCommand.Count > 0 && !IsolatedApprovals.AutoApproveShell)
                    {
                        approved = await IsolatedApprovals.Ask("consensus", "Auditor", "Run " + withCommand.Count + " test command" + (withCommand.Count == 1 ? "" : "s") + " in the sandbox", string.Join("\n", withCommand.Select(t => t.Command)), 300);
                        ct.ThrowIfCancellationRequested();
                        if (!approved) foreach (var t in withCommand) { t.Status = AuditorTestStatus.Skipped; t.Output = "Not run — the test commands were not approved."; }
                    }
                    var toRun = result.AuditorTests.Where(t => !t.Static && (approved || string.IsNullOrWhiteSpace(t.Command))).ToList();
                    await Task.Run(() => ConsensusAuditor.RunTests(toRun, sb.Root, workspace, ConsensusAuditor.TestTimeoutSeconds, ct), ct);

                    SetPhase(ConsensusPhase.Voting);
                    result.Verdict = Vote(StrictMode, result.AuditorTests, result.SecurityIssues);
                    if (!result.AuditorTests.Any(t => !t.Static)) result.Note = "The Auditor named no runnable tests" + (StrictMode ? " — Strict Mode needs at least one passing test." : ".");
                }
            }
            catch (OperationCanceledException) { result.Verdict = ConsensusVerdict.Error; result.Note = ct.IsCancellationRequested ? "Stopped." : "The AI request timed out."; }
            catch (IsolationException ex) { result.Verdict = ConsensusVerdict.Error; result.Note = ex.Message; }
            catch (AIException ex) { result.Verdict = ConsensusVerdict.Error; result.Note = ex.Message; }
            catch (System.Net.Http.HttpRequestException ex) { result.Verdict = ConsensusVerdict.Error; result.Note = AIException.Describe(ex, AIConfig.Mode == "cloud"); }
            catch (IOException ex) { result.Verdict = ConsensusVerdict.Error; result.Note = "Sandbox error: " + ex.Message; }
            catch (UnauthorizedAccessException ex) { result.Verdict = ConsensusVerdict.Error; result.Note = "Sandbox error: " + ex.Message; }
            catch (Exception ex) { result.Verdict = ConsensusVerdict.Error; result.Note = "Unexpected error: " + ex.Message; } // reported in the result; the engine must not stay "running"
            finally
            {
                // the change itself is kept in memory (NewBytes); the copy is only scaffolding
                if (sandbox != null) { var dispose = sandbox; var cleanup = Task.Run(() => dispose.Dispose()); }
                IsolatedApprovals.CancelAll("consensus");
            }
            result.ExecutionTimeMs = (int)sw.ElapsedMilliseconds;
            result.Timestamp = DateTime.Now;
            result.Tally();
            Latest = result;
            IsActive = false;
            _cts = null;
            Phase = result.Verdict == ConsensusVerdict.Approved ? ConsensusPhase.Complete : ConsensusPhase.Blocked;
            if (result.Verdict == ConsensusVerdict.Approved && AutoApplyOnPass) ApplyLatest(false);
            Raise();
        }

        /// <summary>Apply an approved result, or force one that was not approved (macOS forceApply → "User Override").</summary>
        public void ApplyLatest(bool overrideVerdict)
        {
            var r = Latest;
            if (r == null || r.Applied || IsActive || r.BuilderChanges.Count == 0 || r.Workspace == null) return;
            if (r.Verdict != ConsensusVerdict.Approved && !overrideVerdict) return;
            Phase = ConsensusPhase.Applying;
            var rep = Apply(r.Workspace, r.BuilderChanges);
            r.Applied = rep.Applied.Count > 0;
            r.ApplyReport = rep.Text;
            if (overrideVerdict && r.Verdict != ConsensusVerdict.Approved) r.Verdict = ConsensusVerdict.Override;
            Phase = ConsensusPhase.Complete;
            AfterApply(r.Workspace, rep);
            Raise();
        }

        /// <summary>Open editor tabs pick up the applied content (unless they hold unsaved edits); the file tree refreshes.</summary>
        static void AfterApply(string workspace, ApplyReport rep)
        {
            if (Application.Current == null || rep.Applied.Count == 0) return;
            var st = AppState.Shared;
            foreach (var rel in rep.Applied)
            {
                string full = System.IO.Path.Combine(workspace, rel.Replace('/', '\\'));
                var open = st.OpenFiles.FirstOrDefault(o => string.Equals(o.Path, full, StringComparison.OrdinalIgnoreCase));
                if (open != null && !open.IsUnsaved && File.Exists(full)) open.Content = File.ReadAllText(full).Replace("\r\n", "\n");
            }
            st.Notify("files");
            st.RefreshFileTree();
        }

        public void Retry(string workspace)
        {
            var r = Latest;
            if (r == null || IsActive) return;
            string req = r.Request;
            Reset();
            Run(req, workspace ?? r.Workspace).ContinueWith(t => { if (t.IsFaulted) { Error = t.Exception.GetBaseException().Message; Raise(); } }, TaskScheduler.Default);
        }

        public void Reset()
        {
            if (IsActive) return;
            Latest = null; Error = null; Phase = ConsensusPhase.Idle;
            Raise();
        }

        public void Stop()
        {
            var c = _cts;
            if (c != null && !c.IsCancellationRequested) c.Cancel();
            IsolatedApprovals.CancelAll("consensus");
        }
    }

    // ── small shared views ──────────────────────────────────────────────────

    static class AgentUI
    {
        public static FrameworkElement Spinner(double size, Brush brush)
        {
            var arc = new System.Windows.Shapes.Path
            {
                Data = Geometry.Parse("M 8,1.5 A 6.5,6.5 0 1 1 1.5,8"), Stroke = brush, StrokeThickness = 2, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
                Stretch = Stretch.Uniform, Width = size, Height = size, RenderTransformOrigin = new Point(0.5, 0.5), VerticalAlignment = VerticalAlignment.Center
            };
            var rt = new RotateTransform();
            arc.RenderTransform = rt;
            rt.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360, TimeSpan.FromSeconds(0.9)) { RepeatBehavior = RepeatBehavior.Forever });
            return arc;
        }

        /// <summary>SwiftUI Toggle(.switch, .controlSize(.mini)).</summary>
        public static Btn Switch(bool on, bool enabled, Action<bool> changed)
        {
            var t = Theme.Current;
            var knob = new Ellipse { Width = 11, Height = 11, Fill = Brushes.White, HorizontalAlignment = on ? HorizontalAlignment.Right : HorizontalAlignment.Left, Margin = new Thickness(1.5) };
            var track = new Border { Width = 25, Height = 14, CornerRadius = new CornerRadius(7), Background = on ? t.Accent : t.P(0.2), Child = knob, Opacity = enabled ? 1 : 0.45 };
            var b = V.Button(track, null);
            if (enabled) b.Click += delegate { on = !on; knob.HorizontalAlignment = on ? HorizontalAlignment.Right : HorizontalAlignment.Left; track.Background = on ? t.Accent : t.P(0.2); changed(on); };
            return b;
        }

        public static FrameworkElement Progress(double ratio, Brush fill)
        {
            var t = Theme.Current;
            ratio = Math.Max(0, Math.Min(1, ratio));
            var bar = new Border { CornerRadius = new CornerRadius(2), Background = fill, HorizontalAlignment = HorizontalAlignment.Left };
            var g = new Grid { Height = 4 };
            g.Children.Add(new Border { CornerRadius = new CornerRadius(2), Background = t.P(0.08) });
            g.Children.Add(bar);
            g.SizeChanged += delegate { bar.Width = Math.Max(ratio > 0 ? 4 : 0, g.ActualWidth * ratio); };
            return g;
        }

        /// <summary>A text field framed like the macOS .roundedBorder style.</summary>
        public static Border Field(string placeholder, double size, bool mono, bool multiline, out TextBox box)
        {
            var t = Theme.Current;
            var g = Styles.Field(placeholder, size, t.Primary, t.Secondary, out box);
            if (mono) box.FontFamily = UIFonts.Mono;
            if (multiline)
            {
                box.AcceptsReturn = true; box.TextWrapping = TextWrapping.Wrap; box.MinHeight = 46; box.MaxHeight = 150;
                box.VerticalContentAlignment = VerticalAlignment.Top; box.VerticalAlignment = VerticalAlignment.Stretch;
                ((FrameworkElement)g.Children[0]).VerticalAlignment = VerticalAlignment.Top;
            }
            return V.Box(g, V.P(8, 5), t.Op(t.TextBackground, 0.8), 5, t.P(0.12), 1);
        }

        public static Btn Pill(string icon, string label, Brush fg, Brush bg, double size, FontWeight weight, Action a)
        {
            var row = V.H(4);
            if (icon != null) row.Children.Add(Sym.Icon(icon, size - 0.5, fg));
            row.Children.Add(V.T(label, size, weight, fg));
            return V.Button(V.Box(row, V.P(10, 5), bg, 6), a);
        }

        public static void Detach(FrameworkElement e)
        {
            var p = e.Parent;
            var panel = p as Panel;
            if (panel != null) { panel.Children.Remove(e); return; }
            var dec = p as Decorator;
            if (dec != null) dec.Child = null;
        }

        /// <summary>Commands from isolated runs that wait for the user (ToolApprovalView look).</summary>
        public static UIElement ApprovalCards(string source)
        {
            var t = Theme.Current;
            var pending = IsolatedApprovals.PendingFor(source);
            if (pending.Count == 0) return null;
            var col = V.VLead(8);
            col.Align = Cross.Stretch;
            foreach (var p in pending)
            {
                var a = p;
                var detail = V.Wrap(V.Mono(a.Detail, 10.5, FontWeights.Normal, t.P(0.85)), TextAlignment.Left);
                detail.MaxHeight = 110;
                var reject = V.Button(V.Box(V.H(4, Sym.Icon("xmark", 9, t.Op(t.SysRed, 0.9), FontWeights.Bold), V.T("Reject", 11, FontWeights.Medium, t.Op(t.SysRed, 0.9))), V.P(10, 5), t.Op(t.SysRed, 0.08), 6, t.Op(t.SysRed, 0.2), 0.5), () => IsolatedApprovals.Resolve(a, false));
                var approve = V.Button(V.Box(V.H(5, Sym.Icon("checkmark", 9, Brushes.White, FontWeights.Bold), V.T("Approve", 11, FontWeights.SemiBold, Brushes.White)), V.P(12, 5), t.Accent, 6), () => IsolatedApprovals.Resolve(a, true));
                var card = V.VLead(7,
                    V.Self(V.H(8, Sym.Icon("terminal", 12, t.SysOrange), V.Shrink(V.T(a.Actor + " wants to: " + a.Request, 11.5, FontWeights.SemiBold, t.Primary)), V.Sp(), V.Mono("waiting", 9.5, FontWeights.Medium, t.SysOrange)), Cross.Stretch),
                    V.Self(V.Box(detail, V.P(8, 6), t.P(0.04), 5), Cross.Stretch),
                    V.Self(V.H(8, V.Wrap(V.T("Runs on this PC with the isolated copy as its working folder.", 10, FontWeights.Normal, t.Secondary), TextAlignment.Left), V.Sp(), reject, approve), Cross.Stretch));
                card.Align = Cross.Stretch;
                col.Children.Add(V.Self(V.Box(card, V.P(12, 10), t.P(0.035), 9, t.Op(t.SysOrange, 0.35), 1), Cross.Stretch));
            }
            return col;
        }
    }

    // ── ConsensusEngineView ─────────────────────────────────────────────────

    public class ConsensusView : Border
    {
        readonly AppState _app;
        readonly ConsensusEngine _engine = ConsensusEngine.Shared;
        readonly Border _header = new Border(), _body = new Border();
        readonly Border _requestBox;
        readonly TextBox _request;
        readonly HashSet<string> _openOutputs = new HashSet<string>();
        DispatcherTimer _tick;
        bool _queued;

        public ConsensusView(AppState app)
        {
            _app = app;
            var t = Theme.Current;
            Background = t.WorkspaceBackground;
            _requestBox = AgentUI.Field("Describe the change for the Builder (e.g. validate the inputs of parse_age and handle empty strings)…", 12, false, true, out _request);
            _request.PreviewKeyDown += (s, e) => { if (e.Key == Key.Enter && (Keyboard.Modifiers & ModifierKeys.Control) != 0) { e.Handled = true; Start(); } };
            _request.TextChanged += delegate { if (_engine.Latest == null && !_engine.IsActive) Queue(); };
            var dock = new DockPanel();
            DockPanel.SetDock(_header, Dock.Top);
            dock.Children.Add(_header);
            var sep = new Border { Height = 1, Background = t.Separator };
            DockPanel.SetDock(sep, Dock.Top);
            dock.Children.Add(sep);
            dock.Children.Add(_body);
            Child = dock;
            Loaded += delegate
            {
                _engine.Changed -= Queue; _engine.Changed += Queue;
                IsolatedApprovals.Changed -= Queue; IsolatedApprovals.Changed += Queue;
                Render();
            };
            Unloaded += delegate { _engine.Changed -= Queue; IsolatedApprovals.Changed -= Queue; StopTick(); };
            Render();
        }

        void Queue()
        {
            if (_queued) return;
            _queued = true;
            Dispatcher.BeginInvoke(new Action(() => { _queued = false; Render(); }), DispatcherPriority.Background);
        }

        void StopTick() { if (_tick != null) { _tick.Stop(); _tick = null; } }

        void Start()
        {
            string ws = _app.WorkspaceFolder;
            string req = _request.Text;
            _engine.Run(req, ws).ContinueWith(t => { if (t.IsFaulted) { _engine.Error = t.Exception.GetBaseException().Message; _engine.Raise(); } }, TaskScheduler.FromCurrentSynchronizationContext());
        }

        public void Render()
        {
            var t = Theme.Current;
            // header: consensusHeader
            var row = V.H(12, Sym.Icon("shield.checkered", 14, t.Primary),
                V.Shrink(V.VLead(1, V.T("Consensus Engine", 13, FontWeights.SemiBold, t.Primary), V.T("Builder vs. Auditor — Verified Code Generation", 10, FontWeights.Normal, t.Secondary))), V.Sp());
            if (_engine.IsActive)
            {
                row.Children.Add(V.H(4, AgentUI.Spinner(10, t.SysOrange), V.T(ConsensusText.Phase(_engine.Phase), 10, FontWeights.Medium, t.SysOrange)));
                var stop = PanelUI.Small("stop.fill", "Stop", () => _engine.Stop());
                stop.ToolTip = "Stop the Builder / Auditor run (nothing is applied)";
                row.Children.Add(stop);
            }
            row.Children.Add(V.H(5, V.T("Active", 10, FontWeights.Normal, t.Primary), AgentUI.Switch(_engine.Enabled, true, v => _engine.Enabled = v)));
            var gear = V.Button(V.Box(Sym.Icon("gearshape", 11, t.Secondary), V.P(5, 3), Brushes.Transparent, 4), null);
            gear.Width = 24;
            gear.ToolTip = "Consensus settings";
            gear.MenuAlignRight = true;
            gear.MenuItems = () => new List<MenuItemSpec>
            {
                new MenuItemSpec { Title = "Strict Mode (all tests must pass)", Checked = _engine.StrictMode, Action = () => _engine.StrictMode = !_engine.StrictMode },
                new MenuItemSpec { Title = "Auto-apply on pass", Checked = _engine.AutoApplyOnPass, Action = () => _engine.AutoApplyOnPass = !_engine.AutoApplyOnPass },
                MenuItemSpec.Sep(),
                new MenuItemSpec { Title = "Reset", Disabled = _engine.IsActive, Action = () => _engine.Reset() }
            };
            row.Children.Add(gear);
            _header.Child = V.Box(row, V.P(14, 10), t.P(0.03), 0);

            AgentUI.Detach(_requestBox);
            var r = _engine.Latest;
            if (r != null) { StopTick(); _body.Child = ResultView(r); }
            else if (_engine.IsActive)
            {
                _body.Child = ActiveView();
                if (_tick == null) { _tick = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) }; _tick.Tick += delegate { Queue(); }; _tick.Start(); }
            }
            else { StopTick(); _body.Child = EmptyView(); }
        }

        // ── empty ──
        UIElement EmptyView()
        {
            var t = Theme.Current;
            Func<string, string, Color, UIElement> side = (icon, name, c) => V.Vs(6, Sym.Icon(icon, 28, Theme.B(Theme.WithAlpha(c, 0.3))), V.T(name, 11, FontWeights.Medium, t.Secondary));
            var col = V.Vs(12,
                V.H(30, side("hammer.fill", "Builder", t.SysBlue.Color), V.T("vs", 12, FontWeights.Bold, t.S(0.4)), side("shield.lefthalf.filled", "Auditor", t.SysRed.Color)),
                V.T("Consensus Engine will verify code changes before applying", 11, FontWeights.Normal, t.S(0.6)),
                V.T(_engine.Enabled ? "✓ Active" : "○ Disabled", 10, FontWeights.Medium, _engine.Enabled ? t.SysGreen : t.Secondary));
            // Windows: the Builder's request is entered here (macOS starts runs from the agent loop)
            string ws = _app.WorkspaceFolder;
            bool canRun = _engine.Enabled && ws != null && _request.Text.Trim().Length > 0;
            var run = V.Button(V.Box(V.H(5, Sym.Icon("play.fill", 9, canRun ? Brushes.White : t.Secondary), V.T("Run Consensus", 11, FontWeights.SemiBold, canRun ? Brushes.White : t.Secondary)), V.P(12, 6), canRun ? t.Accent : t.S(0.15), 6), () => { if (canRun) Start(); });
            run.ToolTip = canRun ? "Builder → Auditor → tests → apply only on a pass (Ctrl+Enter)" : ws == null ? "Open a project folder first" : !_engine.Enabled ? "Switch the Consensus Engine to Active first" : "Describe the change first";
            string mode = (_engine.StrictMode ? "Strict: every test must pass" : "Non-strict: only High/Critical findings block") + " · " + (_engine.AutoApplyOnPass ? "auto-apply on pass" : "you apply after the verdict");
            var info = V.Wrap(V.T("The Builder edits a sandbox copy of " + (ws != null ? System.IO.Path.GetFileName(ws) : "the project") + "; the Auditor's tests run there, and the change reaches the project only after they pass.", 10.5, FontWeights.Normal, t.S(0.75)), TextAlignment.Left);
            var card = V.VLead(8, V.Self(_requestBox, Cross.Stretch), V.Self(V.H(8, V.Shrink(V.T(mode, 10, FontWeights.Normal, t.Secondary)), V.Sp(), run), Cross.Stretch), info);
            card.Align = Cross.Stretch;
            if (!string.IsNullOrEmpty(_engine.Error)) card.Children.Add(V.Self(V.Box(V.H(6, V.Self(Sym.Icon("exclamationmark.triangle.fill", 11, t.SysOrange), Cross.Start), V.Flex(V.Wrap(V.T(_engine.Error, 11, FontWeights.Normal, t.Primary), TextAlignment.Left))), V.P(10, 7), t.Op(t.SysOrange, 0.1), 6), Cross.Stretch));
            var cardBox = V.Box(card, V.P(14, 12), t.P(0.03), 9, t.P(0.07), 1);
            cardBox.Width = 620;
            cardBox.Margin = new Thickness(0, 14, 0, 0);
            col.Children.Add(cardBox);
            col.Margin = new Thickness(16, 24, 16, 24);
            var g = new Grid();
            col.HorizontalAlignment = HorizontalAlignment.Center;
            col.VerticalAlignment = VerticalAlignment.Center;
            g.Children.Add(col);
            return new ScrollViewer { Content = g, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        }

        // ── active ──
        UIElement AgentCard(string name, string icon, Color color, bool active, string phase, string activity)
        {
            var t = Theme.Current;
            var circle = new Grid { Width = 56, Height = 56 };
            circle.Children.Add(new Ellipse { Fill = Theme.B(Theme.WithAlpha(color, active ? 0.15 : 0.05)) });
            var ic = Sym.Icon(icon, 22, Theme.B(Theme.WithAlpha(color, active ? 1.0 : 0.4)));
            ic.HorizontalAlignment = HorizontalAlignment.Center;
            circle.Children.Add(ic);
            if (active) circle.Children.Add(new Ellipse { Stroke = Theme.B(color), StrokeThickness = 2, Opacity = 0.5 });
            var s = V.Vs(8, circle, V.T(name, 12, FontWeights.SemiBold, active ? t.Primary : t.Secondary), V.T(phase, 10, FontWeights.Normal, t.Secondary));
            var act = V.Mono(active && !string.IsNullOrEmpty(activity) ? activity : " ", 9.5, FontWeights.Normal, t.S(0.7));
            act.MaxWidth = 200;
            s.Children.Add(act);
            s.Width = 210;
            return s;
        }

        UIElement ActiveView()
        {
            var t = Theme.Current;
            var p = _engine.Phase;
            string builderPhase = p == ConsensusPhase.Sandboxing ? "Preparing sandbox..." : p == ConsensusPhase.Building ? "Writing code..." : "Done";
            string auditorPhase = p == ConsensusPhase.Auditing ? "Generating tests..." : p == ConsensusPhase.Testing ? "Running tests..." : p == ConsensusPhase.Voting ? "Voting..." : "Waiting...";
            var cards = V.H(40,
                AgentCard("Builder", "hammer.fill", t.SysBlue.Color, p == ConsensusPhase.Building || p == ConsensusPhase.Sandboxing, builderPhase, _engine.BuilderActivity),
                V.Vs(4, Sym.Icon("arrow.right", 16, t.Secondary), V.T("vs", 10, FontWeights.Bold, t.Secondary)),
                AgentCard("Auditor", "shield.lefthalf.filled", t.SysRed.Color, p == ConsensusPhase.Auditing || p == ConsensusPhase.Testing, auditorPhase, _engine.AuditorActivity));
            var col = V.Vs(20, cards);
            var req = V.Wrap(V.T("“" + _engine.Request + "”", 11, FontWeights.Normal, t.S(0.75)), TextAlignment.Center);
            req.MaxWidth = 560; req.MaxHeight = 48;
            col.Children.Add(req);
            var secs = (int)(DateTime.Now - _engine.StartedAt).TotalSeconds;
            col.Children.Add(V.Mono(secs / 60 + ":" + (secs % 60).ToString("00") + " elapsed", 10, FontWeights.Normal, t.S(0.6)));
            var approvals = AgentUI.ApprovalCards("consensus");
            if (approvals != null) { var box = new Border { Child = approvals, Width = 600 }; col.Children.Add(box); }
            col.HorizontalAlignment = HorizontalAlignment.Center;
            col.VerticalAlignment = VerticalAlignment.Center;
            col.Margin = new Thickness(16, 24, 16, 24);
            var g = new Grid();
            g.Children.Add(col);
            return new ScrollViewer { Content = g, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        }

        // ── result ──
        static SolidColorBrush SeverityColor(FindingSeverity s)
        {
            var t = Theme.Current;
            switch (s) { case FindingSeverity.Critical: return t.SysRed; case FindingSeverity.High: return t.SysOrange; case FindingSeverity.Medium: return t.SysYellow; case FindingSeverity.Low: return t.SysBlue; default: return t.SysGray; }
        }

        static UIElement Divider() { var d = new Border { Height = 1, Background = Theme.Current.Separator, Margin = new Thickness(14, 0, 14, 0) }; return V.Self(d, Cross.Stretch); }

        static UIElement SectionTitle(string icon, Brush iconBrush, string title)
        {
            var t = Theme.Current;
            var h = V.H(4, Sym.Icon(icon, 11, iconBrush), V.T(title, 12, FontWeights.SemiBold, t.Primary));
            h.Margin = new Thickness(14, 0, 14, 0);
            return h;
        }

        static UIElement Stat(string label, string value, Brush color)
        {
            return V.Vs(2, V.Mono(value, 16, FontWeights.Bold, color), V.T(label, 9, FontWeights.Normal, Theme.Current.Secondary));
        }

        UIElement ResultView(ConsensusResult r)
        {
            var t = Theme.Current;
            bool ok = r.Verdict == ConsensusVerdict.Approved;
            var vc = ok ? t.SysGreen : t.SysRed;
            var col = V.VLead(12);
            col.Align = Cross.Stretch;
            // verdict banner
            var banner = V.H(12, Sym.Icon(ok ? "checkmark.shield.fill" : "xmark.circle.fill", 24, vc),
                V.Shrink(V.VLead(2, V.T(ConsensusText.Verdict(r.Verdict), 16, FontWeights.Bold, vc), V.T(r.Summary, 11, FontWeights.Normal, t.Secondary))), V.Sp(),
                V.Mono(r.ExecutionTimeMs + "ms", 10, FontWeights.Normal, t.Secondary));
            col.Children.Add(V.Self(V.Box(banner, V.P(14, 10), t.Op(vc, 0.05), 0), Cross.Stretch));
            var context = V.VLead(4);
            context.Margin = new Thickness(14, 0, 14, 0);
            if (!string.IsNullOrEmpty(r.Request)) { var q = V.Wrap(V.T("Request: " + r.Request, 11, FontWeights.Normal, t.S(0.8)), TextAlignment.Left); q.MaxHeight = 34; context.Children.Add(q); }
            if (!string.IsNullOrEmpty(r.Note)) context.Children.Add(V.H(5, Sym.Icon("info.circle", 10.5, t.Secondary), V.Wrap(V.T(r.Note, 11, FontWeights.Normal, t.Primary), TextAlignment.Left)));
            if (!string.IsNullOrEmpty(r.ApplyReport)) context.Children.Add(V.H(5, Sym.Icon(r.Applied ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", 10.5, r.Applied ? t.SysGreen : t.SysOrange), V.Wrap(V.T(r.ApplyReport, 11, FontWeights.Medium, t.Primary), TextAlignment.Left)));
            if (context.Children.Count > 0) col.Children.Add(context);
            // stats row
            var stats = V.H(20, Stat("Tests", r.TotalTests.ToString(), t.Primary), Stat("Passed", r.PassedTests.ToString(), t.SysGreen), Stat("Failed", r.FailedTests.ToString(), t.SysRed),
                Stat("Security", r.SecurityIssues.Count.ToString(), r.SecurityIssues.Count == 0 ? t.SysGreen : t.SysOrange), Stat("Files", r.BuilderChanges.Count.ToString(), t.SysBlue));
            stats.Margin = new Thickness(14, 0, 14, 0);
            col.Children.Add(stats);
            col.Children.Add(Divider());
            // security findings
            if (r.SecurityIssues.Count > 0)
            {
                var sec = V.VLead(6, SectionTitle("exclamationmark.triangle.fill", t.SysOrange, "Security Findings"));
                sec.Align = Cross.Stretch;
                foreach (var f in r.SecurityIssues.OrderByDescending(x => x.Severity))
                {
                    var sc = SeverityColor(f.Severity);
                    var badge = new Border { Width = 60, Child = V.Box(V.T(ConsensusText.Severity(f.Severity), 9, FontWeights.Bold, sc), V.P(6, 2), t.Op(sc, 0.1), 3) };
                    ((Border)badge.Child).HorizontalAlignment = HorizontalAlignment.Center;
                    var desc = V.T(f.Description, 10, FontWeights.Normal, t.Secondary);
                    desc.TextWrapping = TextWrapping.Wrap; desc.MaxHeight = 28;
                    string where = f.FilePath.Length == 0 ? "" : System.IO.Path.GetFileName(f.FilePath) + (f.Line > 0 ? ":" + f.Line : "");
                    var line = V.H(8, V.Self(badge, Cross.Start), V.Flex(V.VLead(1, V.T(f.Title, 11, FontWeights.Medium, t.Primary), desc)), V.Mono(where, 9, FontWeights.Normal, t.Secondary));
                    line.Margin = new Thickness(14, 4, 14, 4);
                    line.ToolTip = f.FilePath + (f.Line > 0 ? ":" + f.Line : "") + "\n" + f.Description;
                    sec.Children.Add(V.Self(line, Cross.Stretch));
                }
                col.Children.Add(sec);
                col.Children.Add(Divider());
            }
            // auditor tests
            var tests = V.VLead(6, SectionTitle("checklist", t.Primary, "Auditor Tests"));
            tests.Align = Cross.Stretch;
            if (r.AuditorTests.Count == 0) { var none = V.T("No tests were run.", 10.5, FontWeights.Normal, t.Secondary); none.Margin = new Thickness(14, 2, 14, 2); tests.Children.Add(none); }
            foreach (var test in r.AuditorTests)
            {
                var tc = test;
                bool pass = tc.Status == AuditorTestStatus.Passed, skip = tc.Status == AuditorTestStatus.Skipped;
                var catBadge = new Border { Width = 80, Child = V.Box(V.T(ConsensusText.Category(tc.Category), 9, FontWeights.Medium, t.Secondary), V.P(5, 1), t.P(0.05), 3) };
                ((Border)catBadge.Child).HorizontalAlignment = HorizontalAlignment.Center;
                var line = V.H(8, Sym.Icon(pass ? "checkmark.circle.fill" : skip ? "minus.circle" : "xmark.circle.fill", 12, pass ? t.SysGreen : skip ? t.SysGray : t.SysRed), catBadge, V.Shrink(V.Mono(tc.Name, 10, FontWeights.Normal, t.Primary)), V.Sp(8));
                if (!pass && tc.Output.Length > 0)
                {
                    string brief = tc.Output.Replace("\r", "").Replace("\n", " ");
                    var outT = V.T(brief.Length > 60 ? brief.Substring(0, 60) : brief, 9, FontWeights.Normal, skip ? t.Secondary : t.Op(t.SysRed, 0.7));
                    line.Children.Add(V.Shrink(outT));
                }
                var details = new StringBuilder();
                if (tc.Command.Length > 0) details.Append("$ " + tc.Command + "\n");
                if (tc.Rationale.Length > 0) details.Append("Why: " + tc.Rationale + "\n");
                if (tc.ExecutionTimeMs > 0) details.Append(tc.ExecutionTimeMs + " ms\n");
                if (tc.Output.Length > 0) details.Append("\n" + tc.Output);
                var outBox = V.Box(V.Wrap(V.Mono(details.ToString().TrimEnd(), 10.5, FontWeights.Normal, t.P(0.85)), TextAlignment.Left), V.P(10, 6), t.P(0.035), 6);
                outBox.Margin = new Thickness(36, 0, 14, 4);
                string key = tc.Name + "|" + tc.Command;
                outBox.Visibility = _openOutputs.Contains(key) ? Visibility.Visible : Visibility.Collapsed;
                var row = V.Button(V.Box(line, V.P(14, 3), Brushes.Transparent, 0), () =>
                {
                    if (_openOutputs.Contains(key)) _openOutputs.Remove(key); else _openOutputs.Add(key);
                    outBox.Visibility = _openOutputs.Contains(key) ? Visibility.Visible : Visibility.Collapsed;
                });
                row.OnState = b => ((Border)b.Child).Background = b.IsHover ? t.P(0.03) : Brushes.Transparent;
                row.ToolTip = "Show command and output";
                tests.Children.Add(V.Self(row, Cross.Stretch));
                tests.Children.Add(V.Self(outBox, Cross.Stretch));
            }
            col.Children.Add(tests);
            // builder changes
            if (r.BuilderChanges.Count > 0)
            {
                col.Children.Add(Divider());
                var ch = V.VLead(6, SectionTitle("doc.text.magnifyingglass", t.Primary, "Builder Changes"));
                ch.Align = Cross.Stretch;
                foreach (var c in r.BuilderChanges)
                {
                    var cc = c;
                    var icColor = cc.ChangeType == SandboxChangeType.Create ? t.SysGreen : cc.ChangeType == SandboxChangeType.Delete ? t.SysRed : t.SysBlue;
                    var line = V.H(8, Sym.Icon(cc.ChangeType == SandboxChangeType.Create ? "plus.circle.fill" : cc.ChangeType == SandboxChangeType.Delete ? "minus.circle.fill" : "pencil", 12, icColor),
                        V.Shrink(V.Mono(cc.FilePath, 10, FontWeights.Normal, t.Primary)), V.Sp(8));
                    if (!cc.IsBinary) line.Children.Add(V.Mono("+" + cc.Added + " −" + cc.Removed, 9, FontWeights.Normal, t.Secondary));
                    line.Children.Add(V.T(cc.TypeLabel, 9, FontWeights.Normal, t.Secondary));
                    var row = V.Button(V.Box(line, V.P(14, 3), Brushes.Transparent, 0), () => { if (!cc.IsBinary) DiffViews.ShowSplit(cc.FilePath, cc.OldContent ?? "", cc.NewContent ?? ""); });
                    row.OnState = b => ((Border)b.Child).Background = b.IsHover ? t.P(0.03) : Brushes.Transparent;
                    row.ToolTip = cc.IsBinary ? "Binary file" : "Open the Builder's change in Split Diff";
                    ch.Children.Add(V.Self(row, Cross.Stretch));
                }
                col.Children.Add(ch);
            }
            // actions
            var actions = V.H(12, V.Sp());
            actions.Margin = new Thickness(14, 8, 14, 8);
            string ws = _app.WorkspaceFolder;
            if (!r.Applied && r.BuilderChanges.Count > 0 && ok)
            {
                actions.Children.Add(Action(null, "Discard", t.Primary, t.P(0.07), () => _engine.Reset()));
                actions.Children.Add(Action("checkmark", "Apply Changes", Brushes.White, t.Accent, () => _engine.ApplyLatest(false)));
            }
            else if (!r.Applied && r.BuilderChanges.Count > 0 && r.Verdict != ConsensusVerdict.Override)
            {
                actions.Children.Add(Action(null, "Apply Anyway (Override)", t.SysOrange, t.Op(t.SysOrange, 0.1), () => _engine.ApplyLatest(true)));
                actions.Children.Add(Action(null, "Retry with Builder", t.Primary, t.P(0.07), () => _engine.Retry(ws)));
            }
            else if (!r.Applied && r.Verdict == ConsensusVerdict.Error)
                actions.Children.Add(Action(null, "Retry with Builder", t.Primary, t.P(0.07), () => _engine.Retry(ws)));
            actions.Children.Add(Action(null, "New Request", t.Primary, t.P(0.07), () => _engine.Reset()));
            col.Children.Add(V.Self(actions, Cross.Stretch));
            return new ScrollViewer { Content = new Border { Child = col, Padding = new Thickness(0, 8, 0, 8) }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        }

        static Btn Action(string icon, string label, Brush fg, Brush bg, Action a)
        {
            var row = V.H(4);
            if (icon != null) row.Children.Add(Sym.Icon(icon, 10, fg, FontWeights.Bold));
            row.Children.Add(V.T(label, 11, FontWeights.Medium, fg));
            return V.Button(V.Box(row, V.P(12, 6), bg, 5), a);
        }
    }
}
