// Self-checking tests for the MCP client (src/Agent/Mcp.cs), compiled against out-dev\MicroCode.exe by run-tests.cmd.
// Talks to real servers: a Python stdio MCP server written into the temp folder, and a Streamable HTTP MCP server on a
// loopback TcpListener (session id, SSE replies, bearer auth, 401). Config discovery reads only an isolated fake home.
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
using System.Web.Script.Serialization;
using MicroCode.Core;
using MicroCode.Views;

static class McpTests
{
    static int _pass, _fail;
    static void Check(bool ok, string name) { Console.WriteLine((ok ? "PASS  " : "FAIL  ") + name); if (ok) _pass++; else _fail++; }
    static void W(string path, string text) { Directory.CreateDirectory(Path.GetDirectoryName(path)); File.WriteAllText(path, text); }
    static readonly JavaScriptSerializer Js = new JavaScriptSerializer();
    static Dictionary<string, object> A(params object[] kv) { var d = new Dictionary<string, object>(); for (int i = 0; i + 1 < kv.Length; i += 2) d[(string)kv[i]] = kv[i + 1]; return d; }

    const string PyServer = @"import sys, json, os
roots = None
calls = 0
def send(o):
    sys.stdout.write(json.dumps(o) + '\n'); sys.stdout.flush()
TOOLS = [
  {'name': 'echo', 'description': 'Echo the given text back', 'inputSchema': {'type': 'object', 'properties': {'text': {'type': 'string'}}, 'required': ['text']}},
  {'name': 'add', 'description': 'Add two numbers', 'inputSchema': {'type': 'object', 'properties': {'a': {'type': 'number'}, 'b': {'type': 'number'}}}},
  {'name': 'boom', 'description': 'Always fails'},
  {'name': 'roots', 'description': 'Show the client roots'},
  {'name': 'env_get', 'description': 'Read an environment variable', 'inputSchema': {'type': 'object', 'properties': {'name': {'type': 'string'}}}},
  {'name': 'image', 'description': 'Returns an image and a caption'},
  {'name': 'list_calls', 'description': 'How many tool calls ran'},
  {'name': 'crash', 'description': 'Exits the server'}]
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    m = json.loads(line)
    meth = m.get('method'); mid = m.get('id')
    if meth is None:
        if mid == 900: roots = m.get('result')
        continue
    if meth == 'initialize':
        send({'jsonrpc': '2.0', 'id': mid, 'result': {'protocolVersion': '2025-06-18', 'capabilities': {'tools': {}}, 'serverInfo': {'name': 'py', 'version': '1'}}})
    elif meth == 'notifications/initialized':
        send({'jsonrpc': '2.0', 'id': 900, 'method': 'roots/list', 'params': {}})
    elif meth == 'tools/list':
        send({'jsonrpc': '2.0', 'id': mid, 'result': {'tools': TOOLS}})
    elif meth == 'tools/call':
        calls += 1
        n = m['params']['name']; a = m['params'].get('arguments') or {}
        content = None; err = False
        if n == 'echo': content = [{'type': 'text', 'text': 'echo: ' + a.get('text', '')}]
        elif n == 'add': content = [{'type': 'text', 'text': str(a.get('a', 0) + a.get('b', 0))}]
        elif n == 'boom': content = [{'type': 'text', 'text': 'boom failed'}]; err = True
        elif n == 'roots': content = [{'type': 'text', 'text': json.dumps(roots)}]
        elif n == 'env_get': content = [{'type': 'text', 'text': os.environ.get(a.get('name', ''), '<unset>')}]
        elif n == 'image': content = [{'type': 'image', 'data': 'iVBORw0KGgo=', 'mimeType': 'image/png'}, {'type': 'text', 'text': 'caption'}]
        elif n == 'list_calls': content = [{'type': 'text', 'text': str(calls)}]
        elif n == 'crash': sys.exit(3)
        send({'jsonrpc': '2.0', 'id': mid, 'result': {'content': content, 'isError': err}})
    elif mid is not None:
        send({'jsonrpc': '2.0', 'id': mid, 'error': {'code': -32601, 'message': 'no ' + meth}})
";

    [STAThread]
    static int Main()
    {
        string root = Path.Combine(Path.GetTempPath(), "mc-mcptests-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        Directory.CreateDirectory(root);
        Defaults.UseDir(Path.Combine(root, "data"));
        TaskFiles.HomeOverride = Path.Combine(root, "home", ".microcode");
        bool python = false;
        try { using (var p = Process.Start(new ProcessStartInfo("python", "--version") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true })) { p.WaitForExit(15000); python = p.ExitCode == 0; } }
        catch (System.ComponentModel.Win32Exception) { }
        try
        {
            DiscoveryTests(root);
            if (python) { StdioTests(root); ManagerTests(root); LoopTests(root); }
            else Console.WriteLine("SKIP  python not installed: stdio server checks");
            HttpTests(root);
        }
        catch (Exception ex) { Check(false, "unexpected exception: " + ex); }
        finally
        {
            McpManager.StopAll();
            try { Directory.Delete(root, true); } catch (Exception ex) { Console.WriteLine("cleanup: " + ex.Message); }
        }
        Console.WriteLine();
        Console.WriteLine(_pass + " passed, " + _fail + " failed");
        return _fail == 0 ? 0 : 1;
    }

    static string Home(string root) { return Path.Combine(root, "home"); }

    static void DiscoveryTests(string root)
    {
        string home = Home(root), ws = Path.Combine(root, "disc-ws");
        W(Path.Combine(home, ".microcode", "mcp.json"), "{\"mcpServers\":{\"alpha\":{\"command\":\"node\",\"args\":[\"a.js\",\"--x\"],\"env\":{\"K\":\"v\"}},\"microcode\":{\"command\":\"self\"},\"off\":{\"command\":\"x\",\"disabled\":true}}}");
        W(Path.Combine(home, ".cursor", "mcp.json"), "{\"mcpServers\":{\"alpha\":{\"command\":\"shadow\"},\"slack\":{\"command\":\"npx\",\"env\":{\"SLACK_BOT_TOKEN\":\"YOUR_SLACK_BOT_TOKEN\"}},\"remote\":{\"serverUrl\":\"https://mcp.example.com/mcp\",\"headers\":{\"X-Team\":\"t1\"}}}}");
        W(Path.Combine(home, ".claude", "plugins", "gh", ".mcp.json"), "{\"mcpServers\":{\"github\":{\"url\":\"https://api.example.com/mcp\"}}}");
        W(Path.Combine(home, "AppData", "Roaming", "Claude", "claude_desktop_config.json"), "{\"mcpServers\":{\"desk\":{\"command\":\"uvx\",\"args\":[\"desk-mcp\"]}}}");
        W(Path.Combine(ws, ".vscode", "mcp.json"), "{\"servers\":{\"repo\":{\"type\":\"http\",\"url\":\"http://127.0.0.1:9/mcp\"},\"alpha\":{\"command\":\"evil\"}}}");
        W(Path.Combine(ws, ".mcp.json"), "{\"mcpServers\":{\"local\":{\"command\":\"python\",\"args\":[\"srv.py\"]}}}");
        var repoFiles = new List<string>();
        var specs = McpDiscovery.Scan(ws, repoFiles);
        var names = specs.Select(s => s.Name).ToList();
        var alpha = specs.First(s => s.Name == "alpha");
        Check(names.SequenceEqual(new[] { "alpha", "remote", "desk", "github", "local", "repo" }), "Discovery: user configs first, repo last, first name wins (" + string.Join(", ", names) + ")");
        Check(alpha.Command == "node" && alpha.Args.SequenceEqual(new[] { "a.js", "--x" }) && alpha.Env["K"] == "v" && !alpha.IsWorkspaceScoped && alpha.Source.StartsWith("MicroCode Global"), "Discovery: command, args and env are read; a repo file cannot shadow a user server");
        Check(!names.Contains("microcode") && !names.Contains("off") && !names.Contains("slack"), "Discovery: 'microcode', disabled servers and YOUR_ placeholder credentials are skipped");
        var remote = specs.First(s => s.Name == "remote");
        Check(remote.IsRemote && remote.Url == "https://mcp.example.com/mcp" && remote.Headers["X-Team"] == "t1" && specs.First(s => s.Name == "github").Source == "Claude Plugin (gh)" && specs.First(s => s.Name == "desk").Source == "Claude Desktop", "Discovery: serverUrl / url + headers, plugin folders and Claude Desktop");
        Check(specs.First(s => s.Name == "repo").IsWorkspaceScoped && specs.First(s => s.Name == "local").IsWorkspaceScoped && repoFiles.Count == 2, "Discovery: .vscode/mcp.json \"servers\" and .mcp.json are repo-declared (need trust)");

        WorkspaceTrust.Prompt = (w, items) => false;
        McpManager.Sync(ws, false);
        Check(McpManager.Get("local") == null && McpManager.Get("repo") == null && McpManager.Get("alpha") != null, "Trust: untrusted repo servers are not connected");
        WorkspaceTrust.Revoke(ws, "exec-config");
        WorkspaceTrust.Prompt = (w, items) => items.Any(i => i.Item1.Contains("MCP server `local`"));
        McpManager.Sync(ws, false);
        Check(McpManager.Get("local") != null && McpManager.Get("repo") != null, "Trust: once trusted, repo servers join (the prompt lists them)");
        WorkspaceTrust.Prompt = null;
        McpManager.StopAll();
        foreach (var f in new[] { Path.Combine(home, ".microcode", "mcp.json"), Path.Combine(home, ".cursor", "mcp.json"), Path.Combine(home, ".claude", "plugins", "gh", ".mcp.json"), Path.Combine(home, "AppData", "Roaming", "Claude", "claude_desktop_config.json") }) File.Delete(f);
        McpManager.Sync(null, false);
        Check(McpManager.Connections.Count == 0, "Sync: servers whose config disappeared are dropped");
    }

    static McpServerSpec PySpec(string root, string name)
    {
        string script = Path.Combine(root, "py_mcp.py");
        if (!File.Exists(script)) File.WriteAllText(script, PyServer);
        return new McpServerSpec { Name = name, Source = "test", Command = "python", Args = new List<string> { script }, Env = new Dictionary<string, string> { { "MC_TEST_VAR", "from env" } } };
    }

    static void StdioTests(string root)
    {
        string ws = Path.Combine(root, "stdio ws");
        Directory.CreateDirectory(ws);
        var c = new McpConnection(PySpec(root, "py")) { Workspace = ws };
        bool ok = c.Start(30000);
        Check(ok && c.Connected && c.Tools.Count == 8 && c.NegotiatedVersion == "2025-06-18" && c.Tools.First(t => t.Name == "echo").Description == "Echo the given text back", "stdio: initialize, version negotiation and tools/list (" + c.Error + ")");
        Check(c.CallTool("echo", A("text", "สวัสดี hello")) == "echo: สวัสดี hello" && c.CallTool("add", A("a", 2, "b", 3)) == "5", "stdio: tools/call with UTF-8 text and numbers");
        Check(c.CallTool("boom", A()) == "Error: boom failed" && c.ErrorCount == 1, "stdio: isError results come back as tool errors");
        string roots = c.CallTool("roots", A());
        Check(roots.Contains("file:///") && roots.Contains("stdio%20ws") && roots.Contains("\"name\": \"stdio ws\""), "stdio: answers the server's roots/list request with the workspace (" + roots + ")");
        Check(c.CallTool("env_get", A("name", "MC_TEST_VAR")) == "from env" && c.CallTool("env_get", A("name", "MICROCODE_BRIDGE_TOKEN")) == "<unset>", "stdio: declared env is passed; MicroCode bridge tokens are not");
        Check(c.CallTool("image", A()) == "[image image/png]\ncaption", "stdio: non-text content is described, text kept");
        string n1 = c.CallTool("list_calls", A()), n2 = c.CallTool("list_calls", A());
        Check(n1 == n2, "stdio: read-only tool names are cached for 3 s (" + n1 + "/" + n2 + ")");
        c.Stop();
        Check(!c.Connected && McpManager.CachedTools(c.Spec).Count == 8, "stdio: stop; the tool manifest stays cached");
        Check(c.CallTool("echo", A("text", "again")) == "echo: again" && c.Connected, "stdio: a call wakes a stopped (hibernated) server");
        string crash = null;
        try { c.CallTool("crash", A()); } catch (McpException ex) { crash = ex.Message; }
        Check(crash != null && crash.Contains("terminated (exit 3)") && !c.Connected, "stdio: a crashing server fails the pending call with its exit code (" + crash + ")");
        c.Stop();
        var missing = new McpConnection(new McpServerSpec { Name = "nope", Source = "test", Command = "definitely-not-a-command-xyz" });
        Check(!missing.Start(5000) && missing.Error == "Command not found: definitely-not-a-command-xyz", "stdio: a missing command is reported");
        Check(McpConnection.Quote("a b") == "\"a b\"" && McpConnection.Quote("x\"y") == "\"x\\\"y\"" && McpConnection.Quote("C:\\p\\") == "C:\\p\\" && McpConnection.Quote("C:\\a b\\") == "\"C:\\a b\\\\\"", "stdio: Windows argument quoting");
    }

    static void ManagerTests(string root)
    {
        string home = Home(root);
        string script = Path.Combine(root, "py_mcp.py");
        W(Path.Combine(home, ".microcode", "mcp.json"), Js.Serialize(A("mcpServers", A("py", A("command", "python", "args", new[] { script })))));
        McpManager.Sync(null, true);
        McpManager.WaitForProbes(30000);
        var py = McpManager.Get("py");
        Check(py != null && !py.Connected && McpManager.EffectiveTools(py).Count == 8, "Manager: background probe caches the tools, then the stdio server hibernates");
        var eager = McpManager.EagerToolNames("please echo this text back to me", 12);
        Check(eager.Contains("mcp__py__echo") && !eager.Contains("mcp__py__crash"), "Manager: tools relevant to the request are picked for the prompt (" + string.Join(", ", eager) + ")");
        var schema = McpManager.SchemasFor(new HashSet<string> { "mcp__py__boom" }).Single();
        var prm = (Dictionary<string, object>)schema["parameters"];
        Check((string)schema["description"] == "[py] Always fails" && (string)prm["type"] == "object" && prm.ContainsKey("properties"), "Manager: schema gets [server] prefix and a valid object schema even when the server sent none");
        Check(McpManager.PromptSummary() == "\n\n## Discovered External MCP Servers (Use `mcp_orchestrator` to inspect/search/connect)\n- `py`: READY (8 cached tools)", "Manager: prompt summary in the Mac format");
        Check(McpManager.Call("mcp__py__add", A("a", 40, "b", 2)) == "42" && McpManager.Get("py").Connected, "Manager: mcp__server__tool calls wake the server");
        Check(McpManager.Call("mcp__nobody__x", A()).StartsWith("Error: no MCP server"), "Manager: unknown servers are a tool error");
        string status = McpManager.Orchestrate(A("action", "status"));
        Check(status.StartsWith("Hyper-Mesh MCP Status (1 servers, 8 external tools):") && status.Contains("- [ONLINE] py (source: MicroCode Global"), "mcp_orchestrator status: mesh summary");
        string search = McpManager.Orchestrate(A("action", "search_tools", "query", "environment"));
        bool mounted; lock (McpManager.Mounted) mounted = McpManager.Mounted.Contains("mcp__py__env_get");
        Check(search == "- `mcp__py__env_get`: Read an environment variable" && mounted, "mcp_orchestrator search_tools: matches are listed and mounted for the next model call");
        string conn = McpManager.Orchestrate(A("action", "connect", "server_name", "Py2", "command", "python", "args", script));
        string saved = File.ReadAllText(Path.Combine(home, ".microcode", "mcp.json"));
        Check(conn.StartsWith("✅ Connected MCP Server 'py2'") && conn.Contains("`mcp__py2__echo`") && saved.Contains("\"py2\"") && McpManager.Get("py2").Connected, "mcp_orchestrator connect: registers in ~/.microcode/mcp.json and mounts the tools");
        Check(McpManager.Orchestrate(A("action", "authenticate", "server_name", "py2")).Contains("no remote URL registered"), "mcp_orchestrator authenticate: reports missing URL for stdio server (OAuth 2.1 supported for HTTP)");
        Check(McpManager.LooksReadOnlyTool("mcp__py__list_calls") && !McpManager.LooksReadOnlyTool("mcp__py__crash"), "Approval: read-looking MCP tool names are treated as safe");
        McpManager.StopAll();
    }

    static void HttpTests(string root)
    {
        var seen = new List<Dictionary<string, string>>();
        var tcp = new TcpListener(IPAddress.Loopback, 0); tcp.Start();
        int port = ((IPEndPoint)tcp.LocalEndpoint).Port;
        bool running = true;
        var server = new Thread(() =>
        {
            while (running)
            {
                TcpClient client;
                try { client = tcp.AcceptTcpClient(); } catch (SocketException) { return; } catch (ObjectDisposedException) { return; }
                using (client)
                {
                    var s = client.GetStream();
                    var head = new List<byte>();
                    while (true) { int b = s.ReadByte(); if (b < 0) break; head.Add((byte)b); int n = head.Count; if (n >= 4 && head[n - 4] == 13 && head[n - 3] == 10 && head[n - 2] == 13 && head[n - 1] == 10) break; }
                    var lines = Encoding.ASCII.GetString(head.ToArray()).Split(new[] { "\r\n" }, StringSplitOptions.None);
                    var h = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase); h[":line"] = lines[0];
                    foreach (var l in lines.Skip(1)) { int c = l.IndexOf(':'); if (c > 0) h[l.Substring(0, c).Trim()] = l.Substring(c + 1).Trim(); }
                    if (h.ContainsKey("Expect")) { var cont = Encoding.ASCII.GetBytes("HTTP/1.1 100 Continue\r\n\r\n"); s.Write(cont, 0, cont.Length); }
                    int len = h.ContainsKey("Content-Length") ? int.Parse(h["Content-Length"]) : 0; var body = new byte[len]; int got = 0;
                    while (got < len) { int r = s.Read(body, got, len - got); if (r <= 0) break; got += r; }
                    h[":body"] = Encoding.UTF8.GetString(body, 0, got);
                    lock (seen) seen.Add(h);
                    var msg = Js.DeserializeObject(h[":body"]) as Dictionary<string, object>;
                    string method = msg != null && msg.ContainsKey("method") ? (string)msg["method"] : "";
                    object id = msg != null && msg.ContainsKey("id") ? msg["id"] : null;
                    string resp;
                    if (h[":line"].Contains("/locked")) resp = "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Bearer\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                    else if (method == "initialize")
                    {
                        string j = Js.Serialize(A("jsonrpc", "2.0", "id", id, "result", A("protocolVersion", "2025-06-18", "capabilities", A())));
                        resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nMcp-Session-Id: sess-1\r\nContent-Length: " + Encoding.UTF8.GetByteCount(j) + "\r\nConnection: close\r\n\r\n" + j;
                    }
                    else if (id == null) resp = "HTTP/1.1 202 Accepted\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                    else
                    {
                        object result = method == "tools/list" ? (object)A("tools", new object[] { A("name", "whoami", "description", "Who is calling") })
                            : A("content", new object[] { A("type", "text", "text", "auth=" + (h.ContainsKey("Authorization") ? h["Authorization"] : "-") + " sid=" + (h.ContainsKey("Mcp-Session-Id") ? h["Mcp-Session-Id"] : "-") + " v=" + (h.ContainsKey("MCP-Protocol-Version") ? h["MCP-Protocol-Version"] : "-") + " team=" + (h.ContainsKey("X-Team") ? h["X-Team"] : "-")) });
                        string sse = "event: message\ndata: " + Js.Serialize(A("jsonrpc", "2.0", "method", "notifications/progress", "params", A())) + "\n\nevent: message\ndata: " + Js.Serialize(A("jsonrpc", "2.0", "id", id, "result", result)) + "\n\n";
                        resp = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: " + Encoding.UTF8.GetByteCount(sse) + "\r\nConnection: close\r\n\r\n" + sse;
                    }
                    var bytes = Encoding.UTF8.GetBytes(resp); s.Write(bytes, 0, bytes.Length);
                }
            }
        }) { IsBackground = true };
        server.Start();
        string url = "http://127.0.0.1:" + port + "/mcp";
        McpManager.SaveStaticBearer("tok123", url);
        var web = new McpConnection(new McpServerSpec { Name = "web", Source = "test", Command = url, Url = url, Headers = new Dictionary<string, string> { { "X-Team", "t1" } } });
        bool ok = web.Start(15000);
        Check(ok && web.Connected && web.Tools.Count == 1 && web.Tools[0].Name == "whoami", "HTTP: initialize (JSON) + tools/list (SSE) over Streamable HTTP (" + web.Error + ")");
        string who = web.CallTool("whoami", A());
        Check(who == "auth=Bearer tok123 sid=sess-1 v=2025-06-18 team=t1", "HTTP: session id, negotiated protocol version, custom headers and the stored bearer are sent (" + who + ")");
        Check(seen.Any(x => x[":body"].Contains("notifications/initialized")) && seen.All(x => x.ContainsKey("Accept") && x["Accept"].Contains("text/event-stream")), "HTTP: initialized notification sent (202), Accept covers JSON + SSE");
        Check(!File.ReadAllText(Path.Combine(Defaults.Dir, "settings.json")).Contains("tok123"), "HTTP: the bearer is stored DPAPI-sealed, never in plain text");
        var locked = new McpConnection(new McpServerSpec { Name = "locked", Source = "test", Command = url, Url = "http://127.0.0.1:" + port + "/locked" });
        Check(!locked.Start(10000) && locked.Error.Contains("AUTH_REQUIRED (HTTP 401"), "HTTP: 401 is reported as AUTH_REQUIRED (" + locked.Error + ")");
        running = false; tcp.Stop();
    }

    /// <summary>The real agent loop calls an MCP tool chosen from the prompt; its result reaches the model.</summary>
    static void LoopTests(string root)
    {
        string home = Home(root), script = Path.Combine(root, "py_mcp.py");
        W(Path.Combine(home, ".microcode", "mcp.json"), Js.Serialize(A("mcpServers", A("py", A("command", "python", "args", new[] { script })))));
        McpManager.Sync(null, true);
        McpManager.WaitForProbes(30000);
        var tcp = new TcpListener(IPAddress.Loopback, 0); tcp.Start();
        int port = ((IPEndPoint)tcp.LocalEndpoint).Port;
        var bodies = new List<string>();
        var script2 = new[]
        {
            "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"\",\"tool_calls\":[{\"id\":\"m1\",\"type\":\"function\",\"function\":{\"name\":\"mcp__py__echo\",\"arguments\":\"{\\\"text\\\":\\\"from the agent\\\"}\"}}]}}]}",
            "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Done.\"}}]}"
        };
        var serve = Task.Run(() =>
        {
            foreach (var reply in script2)
                using (var client = tcp.AcceptTcpClient())
                {
                    var s = client.GetStream();
                    var head = new List<byte>();
                    while (true) { int b = s.ReadByte(); if (b < 0) break; head.Add((byte)b); int n = head.Count; if (n >= 4 && head[n - 4] == 13 && head[n - 3] == 10 && head[n - 2] == 13 && head[n - 1] == 10) break; }
                    string hs = Encoding.ASCII.GetString(head.ToArray());
                    if (hs.IndexOf("Expect: 100-continue", StringComparison.OrdinalIgnoreCase) >= 0) { var c = Encoding.ASCII.GetBytes("HTTP/1.1 100 Continue\r\n\r\n"); s.Write(c, 0, c.Length); }
                    var m = System.Text.RegularExpressions.Regex.Match(hs, @"Content-Length:\s*(\d+)", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
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
            var history = new List<ChatMessage> { new ChatMessage { Role = "user", Content = "echo the words from the agent" } };
            res = AgentRunner.Run(history, "test", true, false, null, new AgentCallbacks(), CancellationToken.None).GetAwaiter().GetResult();
        }
        catch (Exception ex) { Check(false, "MCP agent loop: run failed: " + ex.Message); }
        serve.Wait(10000); tcp.Stop();
        if (res == null) return;
        Check(bodies.Count == 2 && bodies[0].Contains("\"name\":\"mcp__py__echo\"") && bodies[0].Contains("\"name\":\"mcp_orchestrator\"") && !bodies[0].Contains("mcp__py__crash"), "MCP agent loop: relevant MCP tools and mcp_orchestrator are offered to the model");
        var step = res.Steps.FirstOrDefault(x => x.Name == "mcp__py__echo");
        Check(step != null && step.Ok && step.Result == "echo: from the agent" && bodies[1].Contains("echo: from the agent") && AgentRunner.Headline(step) == "Called py · echo", "MCP agent loop: the tool runs on the real server and its result reaches the model");
        McpManager.StopAll();
    }
}
