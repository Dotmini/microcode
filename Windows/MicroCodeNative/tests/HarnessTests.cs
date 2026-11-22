// Self-checking tests for the agent harness (src/Agent/RulesEngine.cs + the new AgentRunner tools), compiled against
// out-dev\MicroCode.exe by run-tests.cmd: multi-platform rules, glob matching, lifecycle hooks + workspace trust, and
// multi_file_read / patch_file / multi_replace_in_file / apply_patch / create_directory / rename_file / git_status /
// find_symbol / web_fetch run for real in a temp workspace. Data dir and ~/.microcode are isolated.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using MicroCode.Core;
using MicroCode.Views;

static class HarnessTests
{
    static int _pass, _fail;
    static void Check(bool ok, string name) { Console.WriteLine((ok ? "PASS  " : "FAIL  ") + name); if (ok) _pass++; else _fail++; }
    static void W(string path, string text) { Directory.CreateDirectory(Path.GetDirectoryName(path)); File.WriteAllText(path, text); }

    [STAThread]
    static int Main()
    {
        string root = Path.Combine(Path.GetTempPath(), "mc-harness-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        Directory.CreateDirectory(root);
        Defaults.UseDir(Path.Combine(root, "data"));
        TaskFiles.HomeOverride = Path.Combine(root, "home", ".microcode");
        try { RulesTests(root); GlobTests(); HookTests(root); ToolTests(root); LoopTests(root); }
        catch (Exception ex) { Check(false, "unexpected exception: " + ex); }
        finally { try { Directory.Delete(root, true); } catch (Exception ex) { Console.WriteLine("cleanup: " + ex.Message); } }
        Console.WriteLine();
        Console.WriteLine(_pass + " passed, " + _fail + " failed");
        return _fail == 0 ? 0 : 1;
    }

    static void RulesTests(string root)
    {
        string ws = Path.Combine(root, "rules-ws");
        W(Path.Combine(ws, "AGENTS.md"), "Root agents rule\n@docs/style.md\n@../outside.md\n");
        W(Path.Combine(ws, "docs", "style.md"), "Use tabs.");
        W(Path.Combine(root, "outside.md"), "SECRET OUTSIDE");
        W(Path.Combine(ws, "api", "AGENTS.md"), "API only rule");
        W(Path.Combine(ws, "node_modules", "AGENTS.md"), "ignored");
        W(Path.Combine(ws, "CLAUDE.md"), "Claude rule");
        W(Path.Combine(ws, ".claude", "CLAUDE.md"), "Nested claude rule");
        W(Path.Combine(ws, ".cursorrules"), "Cursor legacy");
        W(Path.Combine(ws, ".cursor", "rules", "react.mdc"), "---\ndescription: React components\nglobs: \"*.tsx, src/**/*.ts\"\nalwaysApply: false\n---\nUse hooks.");
        W(Path.Combine(ws, ".windsurfrules"), "Windsurf rule");
        W(Path.Combine(ws, ".clinerules"), "Cline rule");
        W(Path.Combine(ws, ".github", "copilot-instructions.md"), "Copilot rule");
        W(Path.Combine(ws, ".copilot-instructions.md"), "second copilot (ignored)");
        W(Path.Combine(ws, ".zed", "settings.json"), "{\"assistant\":{\"system_prompt\":\"Zed rule\"}}");
        W(Path.Combine(ws, ".microcode", "rules.md"), "- learned rule");
        W(Path.Combine(ws, ".microcode", "rules", "db.md"), "---\nglobs: [\"*.sql\"]\n---\nUse migrations.");
        W(Path.Combine(TaskFiles.HomeOverride, "rules.md"), "Global user rule");

        var rules = RulesEngine.ScanRules(ws);
        var badges = rules.Select(r => r.Badge + ":" + r.RelativePath).ToList();
        Check(badges.Take(4).SequenceEqual(new[] { "AGENTS.MD:AGENTS.md", "AGENTS.MD:api/AGENTS.md", "CLAUDE:CLAUDE.md", "CLAUDE:.claude/CLAUDE.md" }), "Rules: AGENTS.md (root + scoped subfolder) then CLAUDE.md and .claude/CLAUDE.md, in the Mac order (" + string.Join(", ", badges) + ")");
        var root0 = rules[0];
        Check(root0.Content.Contains("<!-- Imported from docs/style.md -->\nUse tabs.") && !root0.Content.Contains("SECRET OUTSIDE") && root0.Content.Contains("@../outside.md"), "Rules: @imports inside the workspace are expanded, imports outside it are left as text");
        var api = rules.First(r => r.RelativePath == "api/AGENTS.md");
        Check(!api.AlwaysApply && api.Globs.SequenceEqual(new[] { "api/*", "api/**/*" }) && !badges.Any(b => b.Contains("node_modules")), "Rules: nested AGENTS.md is scoped to its folder; node_modules is skipped");
        Check(badges.Contains("CURSOR:.cursorrules") && badges.Contains("CURSOR:.cursor/rules/react.mdc") && badges.Contains("WINDSURF:.windsurfrules") && badges.Contains("CLINE:.clinerules")
            && badges.Contains("COPILOT:.github/copilot-instructions.md") && !badges.Contains("COPILOT:.copilot-instructions.md") && badges.Contains("ZED:.zed/settings.json"), "Rules: Cursor, Windsurf, Cline, Copilot (first file only) and Zed are discovered");
        var mdc = rules.First(r => r.FileName == "react.mdc");
        Check(mdc.Description == "React components" && mdc.Globs.SequenceEqual(new[] { "*.tsx", "src/**/*.ts" }) && !mdc.AlwaysApply && mdc.Content == "Use hooks.", "Rules: .mdc front matter (description, globs, alwaysApply) is parsed");
        Check(badges.Contains("MICROCODE:.microcode/rules.md") && badges.Contains("MICROCODE:~/.microcode/rules.md") && rules.Any(r => r.FileName == "db.md" && r.Globs.SequenceEqual(new[] { "*.sql" })), "Rules: MicroCode repository, global and rules/*.md files are included");

        var none = RulesEngine.ActiveRules(rules, new List<string>());
        var tsx = RulesEngine.ActiveRules(rules, new List<string> { "src/App.tsx" });
        var apiFile = RulesEngine.ActiveRules(rules, new List<string> { "api/server.py" });
        Check(!none.Contains(mdc) && tsx.Contains(mdc) && !tsx.Contains(api) && apiFile.Contains(api), "Rules: glob-scoped rules apply only when a matching file is active");
        string section = RulesEngine.FormatPromptSection(rules, new List<string>(), 100);
        Check(section.StartsWith("\n\n## Multi-Platform Rules & Guidelines (Cursor, Zed, Copilot)") && section.Contains("### [AGENTS.MD] AGENTS.md (Workspace Root AGENTS.md Instructions)") && section.Contains("more rules omitted for token budget"), "Rules: prompt section in the Mac format, cut at the token budget");
        var big = new List<PlatformRule> { new PlatformRule { Badge = "CLAUDE", FileName = "CLAUDE.md", Description = "d", Content = new string('x', 5000) } };
        Check(RulesEngine.FormatPromptSection(big, null, 800).Contains(new string('x', 2000) + "\n```"), "Rules: each rule is capped at 2,000 characters");
    }

    static void GlobTests()
    {
        Check(RulesEngine.MatchGlob("*.ts", "src/a.ts") && RulesEngine.MatchGlob("**/*.py", "a/b/c.py") && RulesEngine.MatchGlob("src/*.cs", "src/A.cs") && !RulesEngine.MatchGlob("src/*.cs", "src/x/A.cs")
            && RulesEngine.MatchGlob("api/**/*", "api/v1/x.py") && RulesEngine.MatchGlob("*.cs", "src\\Win.cs") && !RulesEngine.MatchGlob("*.ts", "a.tsx"), "Glob: extension, **, single-segment * and Windows separators");
        Check(!RulesEngine.MatchGlob("src/*", "src/.env") && RulesEngine.MatchGlob("src/.*", "src/.env") && RulesEngine.MatchGlob("**/Dockerfile", "deploy/Dockerfile"), "Glob: leading dots need an explicit dot (FNM_PERIOD); **/ falls back to the file name");
    }

    static void HookTests(string root)
    {
        string ws = Path.Combine(root, "hooks-ws");
        Directory.CreateDirectory(ws);
        W(Path.Combine(ws, ".microcode", "hooks.json"), "{\"hooks\":{\"pre_tool\":[{\"name\":\"no env\",\"matcher\":\"*.env\",\"command\":\"echo blocked env file & exit /b 3\"}],\"post_tool\":[{\"name\":\"fmt\",\"matcher\":\"*.py\",\"command\":\"echo formatted %MICROCODE_TOOL% %FILE%\",\"blockOnFailure\":false}]}}");
        W(Path.Combine(ws, ".claude", "settings.json"), "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"exit /b 0\"}]}],\"Stop\":[{\"matcher\":\"*\",\"hooks\":[{\"type\":\"command\",\"command\":\"echo tests failing & exit /b 1\"}]}]}}");
        var files = new List<string>();
        var hooks = RulesEngine.ScanHooks(ws, files);
        Check(hooks.Count == 4 && hooks.Count(h => h.Stage == AgentHook.PreTool) == 2 && hooks.Any(h => h.Stage == AgentHook.PreFinish && h.SourceFile == ".claude/settings.json") && hooks.Any(h => h.Name == "fmt" && !h.BlockOnFailure) && files.Count == 2,
            "Hooks: MicroCode hooks.json and Claude Code settings.json (nested hooks, PreToolUse / Stop) are discovered");
        var bash = hooks.First(h => h.Matcher == "Bash");
        Check(RulesEngine.HookMatches(bash, "shell", null) && !RulesEngine.HookMatches(bash, "file_read", null) && RulesEngine.HookMatches(hooks.First(h => h.Name == "fmt"), "file_write", "src/app.py"), "Hooks: Claude tool names (Bash, Edit …) and file globs match MicroCode tools");

        int prompts = 0; bool answer = false;
        WorkspaceTrust.Prompt = (w, items) => { prompts++; return answer; };
        var r0 = RulesEngine.RunHooks(AgentHook.PreTool, "file_read", Path.Combine(ws, "x.env"), ws, ws);
        Check(r0.Allowed && r0.Feedback == "" && prompts == 1, "Trust: an untrusted workspace's hooks never run (asked once)");
        RulesEngine.RunHooks(AgentHook.PreTool, "file_read", Path.Combine(ws, "x.env"), ws, ws);
        Check(prompts == 1, "Trust: a declined workspace is not asked again this session");
        // a changed config is a new fingerprint and asks again
        W(Path.Combine(ws, ".microcode", "hooks.json"), File.ReadAllText(Path.Combine(ws, ".microcode", "hooks.json")) + " ");
        answer = true;
        var r1 = RulesEngine.RunHooks(AgentHook.PreTool, "file_read", Path.Combine(ws, "x.env"), ws, ws);
        Check(prompts == 2 && !r1.Allowed && r1.Feedback.Contains("[Hook PRE_TOOL Failed — no env") && r1.Feedback.Contains("exited with 3") && r1.Feedback.Contains("blocked env file"), "Hooks: a failing blocking pre_tool hook vetoes the call with its output");
        var r2 = RulesEngine.RunHooks(AgentHook.PreTool, "file_read", Path.Combine(ws, "x.txt"), ws, ws);
        Check(r2.Allowed && r2.Feedback == "" && prompts == 2, "Hooks: non-matching files pass; a trusted fingerprint is remembered");
        var r3 = RulesEngine.RunHooks(AgentHook.PostTool, "file_write", Path.Combine(ws, "src", "a.py"), ws, ws);
        Check(r3.Allowed && r3.Feedback.Contains("ℹ️ [Hook POST_TOOL — fmt]: formatted file_write " + Path.Combine(ws, "src", "a.py")), "Hooks: post_tool output comes back as info with MICROCODE_TOOL / FILE set");
        var r4 = RulesEngine.RunHooks(AgentHook.PreFinish, null, Path.Combine(ws, "a.py"), ws, ws);
        Check(!r4.Allowed && r4.Feedback.Contains("[Hook PRE_FINISH Failed") && r4.Feedback.Contains("tests failing"), "Hooks: a failing Stop / pre_finish hook blocks completion");
        WorkspaceTrust.Revoke(ws, "exec-config");
        answer = false;
        Check(RulesEngine.RunHooks(AgentHook.PreFinish, null, null, ws, ws).Allowed && prompts == 3, "Trust: revoking asks again");
        W(Path.Combine(ws, ".microcode", "hooks.json"), "{\"pre_finish\":\"ping -n 30 127.0.0.1 > nul\"}");
        File.Delete(Path.Combine(ws, ".claude", "settings.json"));
        answer = true;
        var sw = Stopwatch.StartNew();
        var r5 = RulesEngine.RunHooks(AgentHook.PreFinish, null, null, ws, ws);
        Check(!r5.Allowed && r5.Feedback.Contains("Hook timed out after 15s") && sw.Elapsed.TotalSeconds < 25, "Hooks: a hook that hangs is killed after 15 s (" + (int)sw.Elapsed.TotalSeconds + " s)");
        WorkspaceTrust.Prompt = null;
    }

    static string Run(string ws, string tool, Dictionary<string, object> args, out ToolStep step)
    {
        step = new ToolStep();
        return AgentRunner.ExecuteIsolated(ws, ws, tool, args, step, CancellationToken.None);
    }
    static string Run(string ws, string tool, Dictionary<string, object> args) { ToolStep s; return Run(ws, tool, args, out s); }
    static Dictionary<string, object> A(params object[] kv) { var d = new Dictionary<string, object>(); for (int i = 0; i + 1 < kv.Length; i += 2) d[(string)kv[i]] = kv[i + 1]; return d; }

    static void ToolTests(string root)
    {
        string ws = Path.Combine(root, "tools-ws");
        W(Path.Combine(ws, "a.txt"), "one\ntwo\nthree\n");
        W(Path.Combine(ws, "src", "b.py"), string.Join("\n", Enumerable.Range(1, 150).Select(i => "line " + i)));
        string multi = Run(ws, "multi_file_read", A("paths", "a.txt, src/b.py, missing.txt"));
        Check(multi.Contains("═══ a.txt ═══\none\ntwo") && multi.Contains("═══ b.py ═══") && multi.Contains("... (50 more lines)") && multi.Contains("═══ missing.txt ═══\n⚠️ Error:"), "multi_file_read: headers, 100-line default cap, per-file errors");
        Check(Run(ws, "read_many_files", A("paths", "a.txt")).Contains("═══ a.txt ═══"), "Tool aliases: read_many_files → multi_file_read");

        W(Path.Combine(ws, "c.cs"), "class A {\r\n    void F() {\r\n        int x = 1;\r\n    }\r\n}\r\n");
        string bad = Run(ws, "patch_file", A("path", "c.cs", "edits", "[{\"old\":\"int x = 1;\",\"new\":\"int x = 2;\"},{\"old\":\"nope\",\"new\":\"y\"}]"));
        Check(bad.StartsWith("Error: Atomic patch_file aborted on c.cs (1/2 edit(s) failed; file was NOT modified)") && File.ReadAllText(Path.Combine(ws, "c.cs")).Contains("int x = 1;"), "patch_file: one failing edit aborts and the file stays untouched");
        ToolStep ps;
        string ok = Run(ws, "patch_file", A("path", "c.cs", "edits", new object[] { A("old", "int x = 1;", "new", "int x = 2;"), A("old", "void F()", "new", "void G()") }), out ps);
        string c = File.ReadAllText(Path.Combine(ws, "c.cs"));
        Check(ok.StartsWith("✅ Applied all 2 edit(s) atomically to c.cs") && c.Contains("int x = 2;") && c.Contains("void G()") && c.Contains("\r\n") && !c.Replace("\r\n", "").Contains("\n") && ps.Added == 2 && ps.Removed == 2, "patch_file: edits as JSON string or array, CRLF kept, +/- stats");
        // indentation-insensitive match re-indents the replacement
        Run(ws, "patch_file", A("path", "c.cs", "edits", "[{\"old\":\"int x = 2;\\nreturn;\",\"new\":\"int x = 3;\"}]"));
        string ind = Run(ws, "replace_in_file", A("path", "c.cs", "old_string", "void G() {\nint x = 2;", "new_string", "void G() {\nint x = 9;\nint y = 0;"));
        Check(ind.StartsWith("Error:"), "replace_in_file keeps exact matching (only the new patch tools use smart matching)");
        var sm = AgentRunner.SmartReplace("class A {\n    void G() {\n        int x = 2;\n    }\n}", "void G() {\n    int x = 2;", "void G() {\n    int x = 9;\n    int y = 0;");
        Check(sm.Count == 1 && sm.Content.Contains("    void G() {\n        int x = 9;\n        int y = 0;\n    }"), "Smart match: indentation-insensitive lines, replacement re-indented to the target");
        Check(AgentRunner.SmartReplace("a  \nb\n", "a\nb", "z").Content == "z\n" && AgentRunner.SmartReplace("x\nx\n", "x", "y").Count == 2 && AgentRunner.SmartReplace("q", "12: q", "13: r").Content == "r", "Smart match: trailing whitespace, ambiguity count, copied line-number prefixes");

        W(Path.Combine(ws, "d.py"), "def a():\n    return 1\n\ndef b():\n    return 1\n");
        string mr = Run(ws, "multi_replace_in_file", A("path", "d.py", "edits", "[{\"old_text\":\"return 1\",\"new_text\":\"return 2\",\"start_line\":4,\"end_line\":5}]"));
        Check(mr.StartsWith("✅ Applied 1 chunk(s)") && File.ReadAllText(Path.Combine(ws, "d.py")) == "def a():\n    return 1\n\ndef b():\n    return 2\n", "multi_replace_in_file: start_line/end_line scope an otherwise ambiguous chunk");
        string amb = Run(ws, "multi_replace_in_file", A("path", "d.py", "edits", "[{\"old_text\":\"    return\",\"new_text\":\"x\"}]"));
        Check(amb.Contains("matched 2 places (specify start_line/end_line)"), "multi_replace_in_file: ambiguous chunks are reported");

        ToolStep aps;
        string v4a = Run(ws, "apply_patch", A("patch", "*** Begin Patch\n*** Update File: d.py\n@@\n def a():\n-    return 1\n+    return 10\n*** Add File: new/e.txt\n+hello\n+world\n*** Delete File: a.txt\n*** End Patch"), out aps);
        Check(v4a == "✅ apply_patch succeeded (Updated: d.py | Added: e.txt | Deleted: a.txt)" && File.ReadAllText(Path.Combine(ws, "d.py")).Contains("return 10") && File.ReadAllText(Path.Combine(ws, "new", "e.txt")) == "hello\nworld" && !File.Exists(Path.Combine(ws, "a.txt"))
            && aps.Children != null && aps.Children.Count == 2 && aps.Children.All(ch => ch.Result != null), "apply_patch (V4A): update, add and delete, one row per file");
        string v4bad = Run(ws, "apply_patch", A("patch", "*** Begin Patch\n*** Update File: d.py\n-nothing like this\n+x\n*** Add File: should-not-exist.txt\n+x\n*** End Patch"));
        Check(v4bad.StartsWith("Error: apply_patch hunk not found in d.py") && !File.Exists(Path.Combine(ws, "should-not-exist.txt")), "apply_patch (V4A): a failed hunk writes nothing");
        string outside = Run(ws, "apply_patch", A("patch", "*** Begin Patch\n*** Add File: ../escape.txt\n+x\n*** End Patch"));
        Check(outside.StartsWith("Error:") && outside.Contains("outside the workspace") && !File.Exists(Path.Combine(root, "escape.txt")), "apply_patch: paths outside the workspace are refused");

        bool hasGit = false;
        try { using (var p = Process.Start(new ProcessStartInfo("git", "--version") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true })) { p.WaitForExit(10000); hasGit = p.ExitCode == 0; } } catch (System.ComponentModel.Win32Exception) { }
        if (hasGit)
        {
            W(Path.Combine(ws, "u.txt"), "alpha\nbeta\ngamma\n");
            string diff = "--- a/u.txt\n+++ b/u.txt\n@@ -1,3 +1,3 @@\n alpha\n-beta\n+BETA\n gamma\n";
            ToolStep us;
            string ud = Run(ws, "apply_patch", A("patch", diff), out us);
            Check(ud.StartsWith("✅ Applied unified diff cleanly") && File.ReadAllText(Path.Combine(ws, "u.txt")) == "alpha\nBETA\ngamma\n" && us.Added == 1 && us.Removed == 1, "apply_patch (unified diff): applied, LF file stays LF, +/- stats");
            Check(Run(ws, "apply_patch", A("patch", diff)).StartsWith("Error: apply_patch hunk not found in u.txt"), "apply_patch (unified diff): a patch that no longer applies is an error");
            File.WriteAllText(Path.Combine(ws, "w.txt"), "one\r\ntwo\r\nthree\r\n");
            string crlf = Run(ws, "apply_patch", A("patch", "diff --git a/w.txt b/w.txt\n--- a/w.txt\n+++ b/w.txt\n@@ -1,3 +1,3 @@\n one\n-two\n+TWO\n three\n--- /dev/null\n+++ b/fresh/n.txt\n@@ -0,0 +1,2 @@\n+n1\n+n2\n"));
            Check(crlf.StartsWith("✅") && File.ReadAllText(Path.Combine(ws, "w.txt")) == "one\r\nTWO\r\nthree\r\n" && File.ReadAllText(Path.Combine(ws, "fresh", "n.txt")) == "n1\nn2\n", "apply_patch (unified diff): a CRLF file keeps CRLF; /dev/null creates a new file");
            File.WriteAllText(Path.Combine(ws, "r1.txt"), "same\n");
            string ren = Run(ws, "apply_patch", A("patch", "diff --git a/r1.txt b/r2.txt\nsimilarity index 100%\nrename from r1.txt\nrename to r2.txt\n"));
            Check(ren.StartsWith("✅") && File.Exists(Path.Combine(ws, "r2.txt")) && !File.Exists(Path.Combine(ws, "r1.txt")), "apply_patch (git rename diff): falls back to git apply (" + ren + ")");
            string gws = Path.Combine(root, "git-ws");
            W(Path.Combine(gws, "f.txt"), "x");
            int code; RunGit(gws, "init -q", out code);
            Check(Run(gws, "git_status", A()).Contains("?? f.txt"), "git_status: short status of the workspace repository");
            Check(Run(ws, "git_status", A()).StartsWith("Error:"), "git_status: outside a repository is an error, not silence");
        }
        else Console.WriteLine("SKIP  git not installed: unified diff + git_status checks");

        Check(Run(ws, "create_directory", A("path", "x/y/z")).StartsWith("✅ Created directory: z") && Directory.Exists(Path.Combine(ws, "x", "y", "z")), "create_directory: nested folders");
        Check(Run(ws, "rename_file", A("old_path", "d.py", "new_path", "lib/d2.py")).StartsWith("✅ Renamed: d.py → d2.py") && File.Exists(Path.Combine(ws, "lib", "d2.py")) && !File.Exists(Path.Combine(ws, "d.py")), "rename_file: moves into a new folder");
        Check(Run(ws, "rename_file", A("old_path", "lib/d2.py", "new_path", "new/e.txt")).Contains("already exists"), "rename_file: never overwrites an existing file");

        W(Path.Combine(ws, "sym", "s.ts"), "export function computeTotal(a: number) {\n  return a;\n}\nconst v = computeTotal(3);\n");
        W(Path.Combine(ws, "sym", "s.cs"), "class Cart {\n    public int ComputeTotal(int a) { return a; }\n}\n");
        W(Path.Combine(ws, "sym", "u.py"), "from s import computeTotal\nprint(computeTotal(1))\n");
        string fs = Run(ws, "find_symbol", A("symbol", "computeTotal"));
        Check(fs.Contains("## Definitions of `computeTotal` (1)\nsym/s.ts:1: export function computeTotal") && fs.Contains("sym/s.ts:4: const v = computeTotal(3);") && fs.Contains("sym/u.py:2:"), "find_symbol: declarations ranked above references");
        string fc = Run(ws, "find_symbol", A("symbol", "Cart", "type", "class"));
        Check(fc.Contains("sym/s.cs:1: class Cart"), "find_symbol: type filter (class)");

        Check(AgentRunner.FetchRejection(new Uri("file:///C:/Windows/win.ini")) == "only http(s) URLs are allowed" && AgentRunner.FetchRejection(new Uri("http://169.254.169.254/latest")) != null
            && AgentRunner.FetchRejection(new Uri("http://metadata.google.internal/")) != null && AgentRunner.FetchRejection(new Uri("http://127.0.0.1:18888/v1/auth/sync")) != null && AgentRunner.FetchRejection(new Uri("http://127.0.0.1:5173/")) == null,
            "web_fetch: file://, link-local, cloud metadata and MicroCode's 18888 bridge are refused");
        var tcp = new TcpListener(IPAddress.Loopback, 0); tcp.Start();
        int port = ((IPEndPoint)tcp.LocalEndpoint).Port;
        var serve = Task.Run(() =>
        {
            for (int i = 0; i < 2; i++)
                using (var client = tcp.AcceptTcpClient())
                {
                    var s = client.GetStream();
                    var buf = new byte[4096]; int n = s.Read(buf, 0, buf.Length);
                    string req = Encoding.ASCII.GetString(buf, 0, n);
                    string resp = req.StartsWith("GET /start") ? "HTTP/1.1 302 Found\r\nLocation: /final\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                        : "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: 11\r\nConnection: close\r\n\r\nhello fetch";
                    byte[] b = Encoding.ASCII.GetBytes(resp); s.Write(b, 0, b.Length);
                }
        });
        string fetched = Run(ws, "web_fetch", A("url", "http://127.0.0.1:" + port + "/start"));
        serve.Wait(5000); tcp.Stop();
        Check(fetched == "hello fetch", "web_fetch: follows a redirect and returns the body (" + fetched + ")");
        Check(Run(ws, "web_fetch", A("url", "ftp://x")).StartsWith("Error: web_fetch refused"), "web_fetch: refusals are tool errors");

        Check(AgentRunner.PatchTargets("--- a/x.c\n+++ b/x.c\n--- a/old.c\n+++ /dev/null\n").SequenceEqual(new[] { "x.c", "old.c" }), "Patch targets: unified diff files, deletions via the --- line");
        Check(AgentRunner.Normalize("MultiEdit") == "multi_replace_in_file" && AgentRunner.Normalize("mkdir") == "create_directory" && AgentRunner.Normalize("webfetch") == "web_fetch", "Tool aliases: MultiEdit, mkdir, webfetch");
        var schemas = AgentRunner.ToolSchemas(true).Select(s => (string)s["name"]).ToList();
        var all = AgentRunner.ToolSchemas(false).Select(s => (string)s["name"]).ToList();
        Check(schemas.Contains("multi_file_read") && schemas.Contains("find_symbol") && schemas.Contains("git_status") && schemas.Contains("web_fetch")
            && schemas.Contains("repo_map") && schemas.Contains("lsp_hover") && !schemas.Contains("apply_patch") && !schemas.Contains("rename_file") && !schemas.Contains("computer_use")
            && all.Contains("apply_patch") && all.Contains("patch_file") && all.Contains("multi_replace_in_file") && all.Contains("create_directory") && all.Contains("rename_file") && all.Contains("computer_use")
            && all.Count >= 35 && all.Count > schemas.Count, "Schemas: >= 35 tools; plan mode keeps only the read-only ones (" + all.Count + ")");
    }

    /// <summary>The real agent loop (AgentRunner.RunIsolated) against a scripted OpenAI-compatible server on loopback:
    /// pre_tool vetoes a .env write, post_tool output reaches the model, and a failing pre_finish hook sends the agent back once.</summary>
    static void LoopTests(string root)
    {
        string ws = Path.Combine(root, "loop-ws");
        W(Path.Combine(ws, ".microcode", "hooks.json"), "{\"pre_tool\":[{\"name\":\"no env\",\"matcher\":\"*.env\",\"command\":\"exit /b 2\"}],\"post_tool\":[{\"name\":\"lint\",\"matcher\":\"*.py\",\"command\":\"echo lint ok for %MICROCODE_TOOL%\"}],\"pre_finish\":[{\"name\":\"tests\",\"command\":\"if exist fixed.txt (exit /b 0) else (echo 1 test failing & exit /b 1)\"}]}");
        WorkspaceTrust.Prompt = (w, items) => true;
        var tcp = new TcpListener(IPAddress.Loopback, 0); tcp.Start();
        int port = ((IPEndPoint)tcp.LocalEndpoint).Port;
        var bodies = new List<string>();
        Func<string, string, string, string> call = (id, name, args) => "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"\",\"tool_calls\":[{\"id\":\"" + id + "\",\"type\":\"function\",\"function\":{\"name\":\"" + name + "\",\"arguments\":" + new System.Web.Script.Serialization.JavaScriptSerializer().Serialize(args) + "}}]}}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}";
        Func<string, string> text = t => "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"" + t + "\"}}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}";
        var script = new[]
        {
            call("c1", "file_write", "{\"path\":\"secrets.env\",\"content\":\"KEY=1\"}"),
            call("c2", "file_write", "{\"path\":\"app.py\",\"content\":\"print(1)\\n\"}"),
            text("All done."),
            call("c3", "file_write", "{\"path\":\"fixed.txt\",\"content\":\"ok\"}"),
            text("Fixed the failing test.")
        };
        var serve = Task.Run(() =>
        {
            foreach (var reply in script)
                using (var client = tcp.AcceptTcpClient())
                {
                    client.ReceiveTimeout = 20000;
                    var s = client.GetStream();
                    var head = new List<byte>();
                    while (true) { int b = s.ReadByte(); if (b < 0) break; head.Add((byte)b); int n = head.Count; if (n >= 4 && head[n - 4] == 13 && head[n - 3] == 10 && head[n - 2] == 13 && head[n - 1] == 10) break; }
                    string h = Encoding.ASCII.GetString(head.ToArray());
                    var m = System.Text.RegularExpressions.Regex.Match(h, @"Content-Length:\s*(\d+)", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                    if (h.IndexOf("Expect: 100-continue", StringComparison.OrdinalIgnoreCase) >= 0) { var c = Encoding.ASCII.GetBytes("HTTP/1.1 100 Continue\r\n\r\n"); s.Write(c, 0, c.Length); }
                    int len = m.Success ? int.Parse(m.Groups[1].Value) : 0; var body = new byte[len]; int got = 0;
                    while (got < len) { int r = s.Read(body, got, len - got); if (r <= 0) break; got += r; }
                    lock (bodies) bodies.Add(Encoding.UTF8.GetString(body, 0, got));
                    byte[] payload = Encoding.UTF8.GetBytes(reply);
                    byte[] hdr = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " + payload.Length + "\r\nConnection: close\r\n\r\n");
                    s.Write(hdr, 0, hdr.Length); s.Write(payload, 0, payload.Length);
                }
        });
        Defaults.Set("ai_key_mode", "local");
        Defaults.Set("ai_base_local", "http://127.0.0.1:" + port + "/v1");
        Defaults.Set("ai_model_local", "scripted");
        Defaults.Set("toolApprovalMode", "yolo");
        AgentResult res = null;
        try
        {
            var history = new List<ChatMessage> { new ChatMessage { Role = "user", Content = "write the files" } };
            res = AgentRunner.RunIsolated(ws, ws, history, "You are a test agent.", false, new AgentCallbacks(), CancellationToken.None).GetAwaiter().GetResult();
        }
        catch (Exception ex) { Check(false, "Agent loop: run failed: " + ex.Message); }
        serve.Wait(10000); tcp.Stop();
        WorkspaceTrust.Prompt = null;
        if (res == null) return;
        var s1 = res.Steps.FirstOrDefault(x => x.Target == "secrets.env");
        Check(s1 != null && !s1.Ok && s1.Approval == "blocked" && !File.Exists(Path.Combine(ws, "secrets.env")) && bodies.Count > 1 && bodies[1].Contains("[Hook PRE_TOOL Failed") && bodies[1].Contains("no env"),
            "Agent loop: a pre_tool hook vetoes the .env write and the model sees why");
        Check(File.Exists(Path.Combine(ws, "app.py")) && bodies.Count > 2 && bodies[2].Contains("lint ok for file_write"), "Agent loop: post_tool hook output is appended to the tool result");
        Check(bodies.Count == 5 && bodies[3].Contains("1 test failing") && bodies[3].Contains("Please fix the issue reported by the `pre_finish` hook") && File.Exists(Path.Combine(ws, "fixed.txt")) && res.Text.EndsWith("Fixed the failing test."),
            "Agent loop: a failing pre_finish hook sends the agent back once, then the turn ends (" + bodies.Count + " model calls)");
    }

    static string RunGit(string cwd, string args, out int code)
    {
        using (var p = Process.Start(new ProcessStartInfo("git", args) { WorkingDirectory = cwd, UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true }))
        {
            string o = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
            p.WaitForExit(); code = p.ExitCode; return o;
        }
    }
}
