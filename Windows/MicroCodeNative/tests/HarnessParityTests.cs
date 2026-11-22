// Parity tests for ConPty, Lsp, AcpHostService, SubAgentHarness, AgentMemoryService, RepoMapService,
// ArxCapsuleService, ExecutionEvidenceGuard, and ComputerUseService. Compatible with both Windows .NET 4.8 and Mono C# 5.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using MicroCode.Core;
using MicroCode.Views;

static class HarnessParityTests
{
    static int _pass, _fail;

    static void Check(bool ok, string name)
    {
        Console.WriteLine((ok ? "PASS  " : "FAIL  ") + name);
        if (ok) _pass++; else _fail++;
    }

    static void WriteText(string path, string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        File.WriteAllText(path, text, new UTF8Encoding(false));
    }

    [STAThread]
    static int Main()
    {
        string root = Path.Combine(Path.GetTempPath(), "mc-parity-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        Directory.CreateDirectory(root);
        Defaults.UseDir(Path.Combine(root, "data"));

        try
        {
            TestConPty(root);
            TestLspJsonRpcAndStdioServer(root);
            TestSubAgentHarnessAndSquad(root);
            TestAcpHostService(root);
            TestAgentMemoryService(root);
            TestRepoMapService(root);
            TestArxCapsuleService(root);
            TestExecutionEvidenceGuard();
            TestComputerUseGuard();
        }
        catch (Exception ex)
        {
            Check(false, "unexpected exception: " + ex);
        }
        finally
        {
            try { Directory.Delete(root, true); } catch { }
        }

        Console.WriteLine();
        Console.WriteLine(_pass + " passed, " + _fail + " failed");
        return _fail == 0 ? 0 : 1;
    }

    static void TestConPty(string root)
    {
        string ansi = "\x1B]0;WindowTitle\x07\x1B[31;1mHello\x1B[0m \x1B[32mWorld\x1B[0m!\x1B[K";
        string stripped = ConPty.StripAnsi(ansi);
        Check(stripped == "Hello World!", "ConPty.StripAnsi removes CSI and OSC sequences (" + stripped + ")");

        string ws = Path.Combine(root, "term-ws");
        Directory.CreateDirectory(ws);

        bool isWin = Environment.OSVersion.Platform == PlatformID.Win32NT;
        string shell = isWin ? "cmd.exe" : "/bin/sh";
        var sb = new StringBuilder();
        var done = new ManualResetEventSlim(false);
        int exitCode = -999;

        using (var term = new TerminalSession())
        {
            term.OutputReceived += delegate(string chunk)
            {
                lock (sb) { sb.Append(chunk); }
            };
            term.Exited += delegate(int code)
            {
                exitCode = code;
                done.Set();
            };

            bool started = term.Start(shell, ws, 100, 24);
            Check(started, "TerminalSession.Start succeeds with " + shell);
            term.Resize(120, 40);
            Check(term.Cols == 120 && term.Rows == 40, "TerminalSession.Resize updates Cols/Rows");

            if (isWin) Thread.Sleep(300);
            term.WriteInput(isWin ? "echo conpty_parity_ok\r\n" : "echo conpty_parity_ok\n");
            if (isWin) Thread.Sleep(400);
            term.WriteInput(isWin ? "exit\r\n" : "exit\n");
            bool finished = done.Wait(8000);
            Thread.Sleep(100);
            string output;
            lock (sb) { output = ConPty.StripAnsi(sb.ToString()); }

            Check(finished && exitCode == 0, "TerminalSession exits cleanly with code 0 (finished=" + finished + ", code=" + exitCode + ")");
            string sample = output.Replace("\r", "\\r").Replace("\n", "\\n");
            if (sample.Length > 140) sample = sample.Substring(0, 140);
            Check(output.Contains("conpty_parity_ok"), "TerminalSession captures shell output (conpty=" + term.UsingConPty + ", len=" + output.Length + ", out=" + sample + ")");
        }
    }

    static void TestLspJsonRpcAndStdioServer(string root)
    {
        // 1. Test LspJsonRpc.Encode + TryReadMessage (Stream and byte[] overloads)
        var sample = new Dictionary<string, object>
        {
            { "jsonrpc", "2.0" },
            { "id", 42 },
            { "method", "textDocument/hover" }
        };
        byte[] encoded = LspJsonRpc.Encode(sample);
        string headerPreview = Encoding.ASCII.GetString(encoded, 0, Math.Min(32, encoded.Length));
        Check(headerPreview.StartsWith("Content-Length: "), "LspJsonRpc.Encode writes Content-Length header");

        using (var ms = new MemoryStream(encoded))
        {
            Dictionary<string, object> decoded;
            bool ok = LspJsonRpc.TryReadMessage(ms, out decoded);
            Check(ok && decoded != null && DJ.Str(decoded, "method") == "textDocument/hover", "LspJsonRpc.TryReadMessage(Stream) parses framed JSON-RPC message");
        }

        int offset = 0;
        Dictionary<string, object> bufMsg;
        bool bufOk = LspJsonRpc.TryReadMessage(encoded, ref offset, encoded.Length, out bufMsg);
        Check(bufOk && offset == encoded.Length && DJ.Num(bufMsg, "id") == 42, "LspJsonRpc.TryReadMessage(byte[]) parses frame and advances offset");

        // 2. Real stdio Python mock LSP server test
        string python = FindPython();
        if (string.IsNullOrEmpty(python))
        {
            Check(true, "LSP mock stdio test skipped (python3/python not on PATH)");
            return;
        }

        string lspDir = Path.Combine(root, "lsp-ws");
        string samplePy = Path.Combine(lspDir, "app.py");
        WriteText(samplePy, "def greet(name):\n    return 'hi ' + name\n");

        string mockScript = Path.Combine(root, "mock_lsp.py");
        string pyCode = string.Join("\n", new[]
        {
            "import sys, json",
            "def read_msg():",
            "    headers = {}",
            "    while True:",
            "        line = sys.stdin.buffer.readline()",
            "        if not line:",
            "            return None",
            "        s = line.decode('ascii', 'ignore').strip()",
            "        if s == '':",
            "            break",
            "        if ':' in s:",
            "            k, v = s.split(':', 1)",
            "            headers[k.strip().lower()] = v.strip()",
            "    n = int(headers.get('content-length', '0'))",
            "    if n <= 0:",
            "        return None",
            "    body = sys.stdin.buffer.read(n)",
            "    return json.loads(body.decode('utf-8'))",
            "def send_msg(obj):",
            "    raw = json.dumps(obj).encode('utf-8')",
            "    hdr = ('Content-Length: %d\\r\\n\\r\\n' % len(raw)).encode('ascii')",
            "    sys.stdout.buffer.write(hdr + raw)",
            "    sys.stdout.buffer.flush()",
            "while True:",
            "    msg = read_msg()",
            "    if msg is None:",
            "        break",
            "    m = msg.get('method')",
            "    mid = msg.get('id')",
            "    if m == 'initialize':",
            "        send_msg({'jsonrpc': '2.0', 'id': mid, 'result': {'capabilities': {'hoverProvider': True, 'definitionProvider': True, 'completionProvider': {}}}})",
            "    elif m == 'textDocument/didOpen':",
            "        uri = msg['params']['textDocument']['uri']",
            "        send_msg({'jsonrpc': '2.0', 'method': 'textDocument/publishDiagnostics', 'params': {'uri': uri, 'diagnostics': [{'range': {'start': {'line': 0, 'character': 0}, 'end': {'line': 0, 'character': 3}}, 'severity': 2, 'code': 'W001', 'source': 'mocklsp', 'message': 'Mock warning'}]}})",
            "    elif m == 'textDocument/didChange':",
            "        uri = msg['params']['textDocument']['uri']",
            "        send_msg({'jsonrpc': '2.0', 'method': 'textDocument/publishDiagnostics', 'params': {'uri': uri, 'diagnostics': []}})",
            "    elif m == 'textDocument/hover':",
            "        send_msg({'jsonrpc': '2.0', 'id': mid, 'result': {'contents': {'kind': 'markdown', 'value': 'def greet(name: str) -> str'}}})",
            "    elif m == 'textDocument/definition':",
            "        uri = msg['params']['textDocument']['uri']",
            "        send_msg({'jsonrpc': '2.0', 'id': mid, 'result': [{'uri': uri, 'range': {'start': {'line': 0, 'character': 4}, 'end': {'line': 0, 'character': 9}}}]})",
            "    elif m == 'textDocument/completion':",
            "        send_msg({'jsonrpc': '2.0', 'id': mid, 'result': {'isIncomplete': False, 'items': [{'label': 'greet', 'kind': 3, 'detail': 'function'}] }})",
            "    elif m == 'shutdown':",
            "        send_msg({'jsonrpc': '2.0', 'id': mid, 'result': None})",
            "    elif m == 'exit':",
            "        break"
        });
        WriteText(mockScript, pyCode);

        using (var mgr = new LspManager())
        {
            mgr.RegisterServer("python", "mock-python-lsp", python, "-u", mockScript);
            var proc = mgr.EnsureStarted("python", lspDir);
            Check(proc != null && proc.IsRunning && proc.Initialized, "LspManager.EnsureStarted launches and initializes stdio Python mock LSP");

            mgr.NotifyOpen(samplePy, "def greet(name):\n    return 'hi ' + name\n");
            Thread.Sleep(200);
            var diags1 = mgr.GetDiagnostics(samplePy);
            Check(diags1.Count == 1 && diags1[0].Message == "Mock warning" && diags1[0].Severity == "warning", "LspManager.GetDiagnostics captures publishDiagnostics after didOpen");

            string hover = mgr.Hover(samplePy, 0, 5);
            Check(hover != null && hover.Contains("def greet"), "LspManager.Hover returns server hover text");

            var defs = mgr.Definition(samplePy, 1, 10);
            Check(defs.Count == 1 && defs[0].StartLine == 0 && defs[0].StartColumn == 4, "LspManager.Definition returns location");

            var comp = mgr.Completion(samplePy, 1, 4);
            Check(comp.Count == 1 && comp[0].Label == "greet", "LspManager.Completion returns completion items");

            mgr.NotifyChange(samplePy, "def greet(name):\n    return name\n");
            Thread.Sleep(200);
            var diags2 = mgr.GetDiagnostics(samplePy);
            Check(diags2.Count == 0, "LspManager.NotifyChange updates diagnostics");

            string summary = mgr.StatusSummary();
            Check(summary.Contains("Active LSP servers: 1") && summary.Contains("mock-python-lsp"), "LspManager.StatusSummary reports running server");
        }
    }

    static void TestSubAgentHarnessAndSquad(string root)
    {
        string ws = Path.Combine(root, "sub-ws");
        WriteText(Path.Combine(ws, "Core.cs"), "public class CoreWidget { public void Run() {} }\n");

        var def = SubAgentHarness.DefineSubagent("qa-auditor", "Checks code", "Audit carefully.", false);
        Check(def != null && def.Name == "qa-auditor" && !def.AllowWrite, "SubAgentHarness.DefineSubagent registers custom type");

        var gate = new ManualResetEventSlim(false);
        SubAgentHarness.CustomExecutor = delegate(SubagentInvocationContext ctx)
        {
            if (ctx.Definition.Name == "qa-auditor")
            {
                gate.Wait(3000);
            }
            return "Ran " + ctx.Definition.Name + " for " + ctx.Instance.Role;
        };

        try
        {
            var inst = SubAgentHarness.InvokeSubagent("qa-auditor", "QA Lead", "Audit Core.cs", "inherit", ws);
            Check(inst != null && !string.IsNullOrEmpty(inst.Id), "SubAgentHarness.InvokeSubagent returns instance");

            bool sent = SubAgentHarness.SendMessage(inst.Id, "Focus on null checks");
            Check(sent && inst.Inbox.Any(m => m.Contains("Focus on null checks")), "SubAgentHarness.SendMessage delivers message to inbox");

            string listText = SubAgentHarness.ManageSubagents("list");
            Check(listText.Contains(inst.Id) && listText.Contains("qa-auditor"), "SubAgentHarness.ManageSubagents(list) includes running subagent");

            string killText = SubAgentHarness.ManageSubagents("kill", inst.Id);
            gate.Set();
            SubAgentHarness.WaitSubagent(inst.Id, 2000);
            Check(killText.Contains("Killed") && SubAgentHarness.GetSubagent(inst.Id).Status == "killed", "SubAgentHarness.ManageSubagents(kill) cancels subagent");

            var squad = SubAgentHarness.RunSquad("Add validation to CoreWidget", ws);
            Check(squad.Success && squad.SubagentIds.Count == 4 && squad.ArchitectOutput.Contains("architect") && squad.ImplementerOutput.Contains("implementer") && squad.ReviewerOutput.Contains("reviewer"),
                "SubAgentHarness.RunSquad runs 3-role Architect/Implementer/Reviewer pipeline");

            string killAll = SubAgentHarness.ManageSubagents("kill_all");
            Check(killAll.Contains("Killed"), "SubAgentHarness.ManageSubagents(kill_all) succeeds");
        }
        finally
        {
            SubAgentHarness.CustomExecutor = null;
        }
    }

    static void TestAcpHostService(string root)
    {
        var known = AcpHostService.ListKnown();
        Check(known.Any(a => a.Id == "claude") && known.Any(a => a.Id == "codex") && known.Any(a => a.Id == "gemini") && known.Any(a => a.Id == "agy") && known.Any(a => a.Id == "goose") && known.Any(a => a.Id == "opencode") && known.Any(a => a.Id == "aider"),
            "AcpHostService lists claude/codex/gemini/agy/goose/opencode/aider adapters");

        string python = FindPython();
        if (!string.IsNullOrEmpty(python))
        {
            string mockCli = Path.Combine(root, "mock_acp.py");
            WriteText(mockCli, "import sys\nprint('ACP_OK:' + ' '.join(sys.argv[1:]))\n");
            AcpHostService.RegisterAdapter("mock-cli", "Mock CLI", python, "\"" + mockCli + "\" {prompt}", false);
            var res = AcpHostService.RunPrompt("mock-cli", "hello_world", root, 5000);
            Check(res.Success && res.Output.Contains("ACP_OK:hello_world"), "AcpHostService.RunPrompt executes external CLI adapter");
        }
    }

    static void TestAgentMemoryService(string root)
    {
        AgentMemoryService.Clear();
        string wsA = Path.Combine(root, "ws-alpha");
        string wsB = Path.Combine(root, "ws-beta");

        var m1 = AgentMemoryService.Remember("ConPTY Fallback", "Use redirected Process when Windows build is below 1809 or under Mono.", wsA);
        var m2 = AgentMemoryService.Remember("LSP Framing", "LSP stdio uses Content-Length headers before UTF-8 JSON.", wsA);
        var m3 = AgentMemoryService.Remember("SQL Migrations", "Always run migrations inside a transaction.", wsB);

        Check(m1 != null && File.Exists(AgentMemoryService.FilePath), "AgentMemoryService persists to agent_memory_v2.json in Defaults.Dir");

        var recalled = AgentMemoryService.Recall("ConPTY Mono fallback", wsA, 3);
        Check(recalled.Count >= 1 && recalled[0].Topic == "ConPTY Fallback", "AgentMemoryService.Recall ranks workspace + keyword match first");

        // Verify disk persistence across fresh read
        var all = AgentMemoryService.ListAll();
        Check(all.Count == 3 && m2 != null && m3 != null, "AgentMemoryService stores and reloads all entries");
    }

    static void TestRepoMapService(string root)
    {
        string ws = Path.Combine(root, "repo-ws");
        WriteText(Path.Combine(ws, "src", "Engine.cs"), "namespace Demo {\n  public class QuantumEngine {\n    public int ComputeOrbit(int x) { return x * 2; }\n  }\n}\n");
        WriteText(Path.Combine(ws, "scripts", "helper.py"), "class DataLoader:\n    pass\n\ndef load_tokens(path):\n    return []\n");
        WriteText(Path.Combine(ws, "node_modules", "ignored.js"), "function ShouldBeIgnored() {}\n");

        string map = RepoMapService.BuildRepoMap(ws, 4000);
        Check(map.Contains("src/Engine.cs") && map.Contains("QuantumEngine") && map.Contains("ComputeOrbit") && map.Contains("load_tokens") && !map.Contains("ShouldBeIgnored"),
            "RepoMapService.BuildRepoMap indexes C# and Python symbols and skips node_modules");

        var hits = RepoMapService.CodebaseSearch(ws, "ComputeOrbit", 10);
        Check(hits.Count >= 1 && hits[0].FilePath == "src/Engine.cs" && hits[0].Symbol == "ComputeOrbit" && hits[0].Line == 3,
            "RepoMapService.CodebaseSearch locates exact symbol declaration");
    }

    static void TestArxCapsuleService(string root)
    {
        string ws = Path.Combine(root, "arx-ws");
        WriteText(Path.Combine(ws, "AGENTS.md"), "Always run parity tests before finishing.");

        var session = new ChatSession
        {
            Id = "sess-123",
            Name = "Parity Implementation",
            ProjectPath = ws,
            ProjectName = "arx-ws"
        };
        var msg = new ChatMessage
        {
            Role = "assistant",
            Content = "Implemented ConPTY and LSP.",
            Model = "gpt-5"
        };
        msg.Steps.Add(new ToolStep { Name = "file_write", Target = "ConPty.cs", Ok = true, Added = 50 });
        session.Messages.Add(msg);

        string arxPath = Path.Combine(root, "exports", "session.arx");
        string exported = ArxCapsuleService.ExportCapsule(session, arxPath);
        Check(File.Exists(exported), "ArxCapsuleService.ExportCapsule writes .arx file");

        var imported = ArxCapsuleService.ImportCapsule(exported);
        Check(imported != null && imported.Session != null && imported.Session.Id == "sess-123"
            && imported.Session.Messages.Count == 1 && imported.Session.Messages[0].Steps.Count == 1
            && imported.Rules.Any(r => r.RelativePath == "AGENTS.md" && r.Content.Contains("parity tests")),
            "ArxCapsuleService.ImportCapsule round-trips session, tool steps, and workspace rules");
    }

    static void TestExecutionEvidenceGuard()
    {
        var readOnlySteps = new List<ToolStep>
        {
            new ToolStep { Name = "file_read", Target = "App.cs", Ok = true }
        };
        var bad = ExecutionEvidenceGuard.CheckCompletion(readOnlySteps, "I have created ConPty.cs and all tests passed.");
        Check(!bad.Passed && bad.Warnings.Count == 2, "ExecutionEvidenceGuard flags read-only hallucinations claiming edits and passing tests");

        var validSteps = new List<ToolStep>
        {
            new ToolStep { Name = "file_write", Target = "ConPty.cs", Ok = true, Approval = "auto" },
            new ToolStep { Name = "shell", Target = "run-tests.cmd", Ok = true, Approval = "auto" }
        };
        var good = ExecutionEvidenceGuard.CheckCompletion(validSteps, "I have created ConPty.cs and all tests passed.");
        Check(good.Passed && good.SuccessfulEdits == 1 && good.SuccessfulShellChecks == 1, "ExecutionEvidenceGuard passes when write and shell evidence exist");
    }

    static void TestComputerUseGuard()
    {
        bool isWin = Environment.OSVersion.Platform == PlatformID.Win32NT && Type.GetType("Mono.Runtime") == null;
        Check(ComputerUseService.IsSupported == isWin, "ComputerUseService.IsSupported reflects Windows vs Mono runtime");
        if (!isWin)
        {
            bool shot = ComputerUseService.Screenshot("/tmp/ignored.bmp");
            bool clk = ComputerUseService.Click(10, 10, "left", 1);
            Check(!shot && !clk, "ComputerUseService gracefully returns false outside Windows");
        }
    }

    static string FindPython()
    {
        string p3 = LspManager.FindExecutable("python3");
        if (!string.IsNullOrEmpty(p3)) return p3;
        return LspManager.FindExecutable("python");
    }
}
