// Self-checking tests for Team Collaboration (src/Collab), compiled against out-dev\MicroCode.exe by run-tests.cmd.
// A real host and a real peer run in this process on loopback: the host's embedded HTTP + WebSocket server, the peer's
// HTTP join / workspace-bundle mirror / ClientWebSocket. Each side gets its own temp workspace and data folder; the IDE side
// is a small in-memory stand-in for AppState (open buffers + what the service pushed into them).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using MicroCode.Core;
using MicroCode.Views;

class TestIde : ICollabIde
{
    readonly object _l = new object();
    public string Workspace, Current, MountedRoot, MountedActive, OpenedPath;
    public readonly Dictionary<string, string> Open = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    public readonly List<string> Applied = new List<string>();
    public int TreeRefreshes;
    public string WorkspaceFolder { get { lock (_l) return Workspace; } }
    public string CurrentFilePath { get { lock (_l) return Current; } }
    public List<CollabOpenFile> OpenFiles() { lock (_l) return Open.Select(kv => new CollabOpenFile { FullPath = kv.Key, Name = Path.GetFileName(kv.Key), Language = Path.GetExtension(kv.Key).TrimStart('.'), Content = kv.Value }).ToList(); }
    public void ApplyRemoteContent(string full, string content) { lock (_l) { Applied.Add(full); if (Open.ContainsKey(full)) Open[full] = content; } }
    public void MountWorkspace(string root, string active) { lock (_l) { MountedRoot = root; MountedActive = active; Workspace = root; } }
    public void OpenFile(string full, int line) { lock (_l) OpenedPath = full + ":" + line; }
    public void RefreshTree() { Interlocked.Increment(ref TreeRefreshes); }
    public readonly List<string> Moved = new List<string>();
    public bool HasMoved(Func<string, bool> f) { lock (_l) return Moved.Any(f); }
    public void PathMoved(string oldFull, string newFull)
    {
        lock (_l)
        {
            Moved.Add(oldFull + ">" + newFull);
            string c; if (Open.TryGetValue(oldFull, out c)) { Open.Remove(oldFull); Open[newFull] = c; }
        }
    }
    public void SetOpen(string full, string content) { lock (_l) Open[full] = content; }

    // ot1 editor patches. DeferApplies queues them like the UI dispatcher does, so a test can type "between" a commit and
    // its patch (the race the editor bridge has to survive); FlushApplies then runs them with the same rebase as the app.
    public bool DeferApplies;
    readonly List<Action> _deferred = new List<Action>();
    public int PatchedOps;
    public void ApplyRemoteOp(string full, TextOperation op, string previous, string resulting, Action<string> applied)
    {
        Action run = () =>
        {
            string after = null;
            lock (_l)
            {
                string current;
                if (Open.TryGetValue(full, out current))
                {
                    after = OTEditorPatch.Rebase(previous, current.Replace("\r\n", "\n"), op).Apply(current.Replace("\r\n", "\n"));
                    Open[full] = after;
                    PatchedOps++;
                }
            }
            applied(after);
        };
        if (DeferApplies) { lock (_l) _deferred.Add(run); return; }
        _ui.Add(run);   // like Dispatcher.BeginInvoke: patched later on the "UI" thread, never inside the caller's lock
    }
    public void FlushApplies()
    {
        List<Action> todo;
        lock (_l) { todo = _deferred.ToList(); _deferred.Clear(); }
        foreach (var a in todo) _ui.Add(a);
        OnUi(() => { });
    }

    // a single "UI thread": editor patches and typing are serialized on it, exactly as in the app
    readonly System.Collections.Concurrent.BlockingCollection<Action> _ui = new System.Collections.Concurrent.BlockingCollection<Action>();
    public TestIde()
    {
        var t = new Thread(() => { foreach (var a in _ui.GetConsumingEnumerable()) { try { a(); } catch (Exception ex) { Console.WriteLine("      ui: " + ex.Message); } } }) { IsBackground = true, Name = "test-ui" };
        t.Start();
    }
    public void OnUi(Action a)
    {
        using (var done = new ManualResetEventSlim())
        {
            _ui.Add(() => { try { a(); } finally { done.Set(); } });
            done.Wait(10000);
        }
    }
    /// <summary>Types into the editor on the UI thread and reports it like the editor's TextEdited hook does.</summary>
    public void Type(CollabService svc, string full, Func<string, string> edit)
    {
        OnUi(() => { string t = edit(Get(full) ?? ""); SetOpen(full, t); svc.NotifyLocalFileEdited(full, t); });
    }

    // @ai requests: the test plugs in a real AgentRunner run (against a scripted loopback model)
    public Func<string, Tuple<string, string>> Agent;
    public readonly List<string> Prompts = new List<string>();
    public void RunAgentPrompt(string prompt, Action<string, string> done)
    {
        lock (_l) Prompts.Add(prompt);
        var agent = Agent;
        System.Threading.Tasks.Task.Run(() => { var r = agent != null ? agent(prompt) : Tuple.Create<string, string>(null, "no agent"); done(r.Item1, r.Item2); });
    }
    public string Get(string full) { lock (_l) { string s; return Open.TryGetValue(full, out s) ? s : null; } }
}

static class CollabTests
{
    static int _pass, _fail;
    static CollabService _traceHost, _tracePeer;
    static void Check(bool ok, string name)
    {
        Console.WriteLine((ok ? "PASS  " : "FAIL  ") + name); if (ok) _pass++; else _fail++;
        if (ok) return;
        // transport diagnostics for a failed check: the last events on both sides
        if (_traceHost != null) foreach (var l in _traceHost.TraceLog.Skip(Math.Max(0, _traceHost.TraceLog.Count - 12))) Console.WriteLine("      host " + l);
        if (_tracePeer != null) foreach (var l in _tracePeer.TraceLog.Skip(Math.Max(0, _tracePeer.TraceLog.Count - 12))) Console.WriteLine("      peer " + l);
    }
    static void W(string path, string text) { Directory.CreateDirectory(Path.GetDirectoryName(path)); File.WriteAllText(path, text); }
    static bool Until(Func<bool> cond, int ms = 6000) { var end = DateTime.UtcNow.AddMilliseconds(ms); while (DateTime.UtcNow < end) { try { if (cond()) return true; } catch (IOException) { } Thread.Sleep(50); } return cond(); }
    static readonly JavaScriptSerializer Js = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
    static readonly HttpClient Http = new HttpClient();
    static bool PortOpen(int port) { try { using (var c = new TcpClient()) { c.Connect("127.0.0.1", port); return true; } } catch (SocketException) { return false; } }
    static string Esc(string t) { return t == null ? "null" : t.Replace("\n", "\\n"); }
    static string ReadText(string p) { try { return File.ReadAllText(p).Replace("\r\n", "\n"); } catch (IOException) { return null; } }

    static Tuple<int, string, string> Get(string url, string cookie = null)
    {
        var req = new HttpRequestMessage(HttpMethod.Get, url);
        if (cookie != null) req.Headers.TryAddWithoutValidation("Cookie", cookie);
        var r = Http.SendAsync(req).Result;
        IEnumerable<string> sc; string setCookie = r.Headers.TryGetValues("Set-Cookie", out sc) ? string.Join(";", sc) : "";
        return Tuple.Create((int)r.StatusCode, r.Content.ReadAsStringAsync().Result, setCookie);
    }

    static Tuple<int, Dictionary<string, object>> Post(string url, object body)
    {
        var r = Http.PostAsync(url, new StringContent(Js.Serialize(body), Encoding.UTF8, "application/json")).Result;
        return Tuple.Create((int)r.StatusCode, Js.DeserializeObject(r.Content.ReadAsStringAsync().Result) as Dictionary<string, object>);
    }

    static string RawUpgrade(int port, string code)
    {
        using (var c = new TcpClient("127.0.0.1", port))
        {
            var s = c.GetStream();
            var req = "GET /ws/collab?code=" + code + " HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n";
            var b = Encoding.ASCII.GetBytes(req); s.Write(b, 0, b.Length);
            s.ReadTimeout = 4000;
            var buf = new byte[512]; int n = s.Read(buf, 0, buf.Length);
            return Encoding.ASCII.GetString(buf, 0, n).Split('\n')[0].Trim();
        }
    }

    static void MergeTests()
    {
        string b = "a\nb\nc\nd\ne";
        var m = CollabMerge.Merge(b, "A\nb\nc\nd\ne", "a\nb\nc\nd\nE");
        Check(m.Merged == "A\nb\nc\nd\nE" && m.DidAutoMerge, "merge: edits on different lines are both kept");
        m = CollabMerge.Merge(b, "a\nB\nc\nd\ne", "a\nB\nc\nd\ne");
        Check(m.Merged == "a\nB\nc\nd\ne", "merge: identical edits are not duplicated");
        m = CollabMerge.Merge(b, "a\nX\nc\nd\ne", "a\nY\nc\nd\ne");
        Check(m.Merged == "a\nY\nc\nd\ne" && !m.Merged.Contains("<<<"), "merge: an overlapping edit resolves to the incoming side, no conflict markers");
        m = CollabMerge.Merge(b, "a\nb\nP\nc\nd\ne", "a\nb\nQ\nc\nd\ne");
        Check(m.Merged == "a\nb\nP\nQ\nc\nd\ne", "merge: two insertions at the same place are both kept");
        m = CollabMerge.Merge(b, b, "z\n" + b);
        Check(m.Merged == "z\n" + b && !m.DidAutoMerge, "merge: unchanged current takes the incoming text as is");
        m = CollabMerge.Merge(b, "a\nb\nc\nd", b);
        Check(m.Merged == "a\nb\nc\nd", "merge: unchanged incoming keeps the current text");
    }

    static void JoinParseTests(CollabService svc)
    {
        var p = svc.ParseJoinInput("http://192.168.1.5:8491/index.html?code=abc234");
        Check(p.Item1 == "http://192.168.1.5:8491" && p.Item2 == "ABC234", "join input: invite link (index.html stripped, code upper-cased)");
        p = svc.ParseJoinInput("https://cloudai.dotmini.net/r/xyz/?code=QWE789");
        Check(p.Item1 == "https://cloudai.dotmini.net/r/xyz" && p.Item2 == "QWE789", "join input: relay link keeps its path prefix");
        p = svc.ParseJoinInput("10.0.0.2:8490#zzz222");
        Check(p.Item1 == "http://10.0.0.2:8490" && p.Item2 == "ZZZ222", "join input: IDE token host:port#CODE");
        p = svc.ParseJoinInput("10.0.0.2:8495");
        Check(p.Item1 == "http://10.0.0.2:8495" && p.Item2 == "", "join input: bare host:port");
        p = svc.ParseJoinInput("http://192.168.1.5:8491/join?code=abc234");
        Check(p.Item1 == "http://192.168.1.5:8491" && p.Item2 == "ABC234", "join input: /join invite link");
        p = svc.ParseJoinInput("https://cloudai.dotmini.net/r/xyz/join/?code=QWE789");
        Check(p.Item1 == "https://cloudai.dotmini.net/r/xyz" && p.Item2 == "QWE789", "join input: relay /join/ link keeps its prefix");
        p = svc.ParseJoinInput("microcode://collab?token=" + Uri.EscapeDataString("https://cloudai.dotmini.net/r/xyz/?code=QWE789"));
        Check(p.Item1 == "https://cloudai.dotmini.net/r/xyz" && p.Item2 == "QWE789", "join input: a pasted microcode://collab?token= link is unwrapped");
        p = svc.ParseJoinInput("CodeTuner://team-collab?CODE=10.0.0.2%3A8490%23zzz222");
        Check(p.Item1 == "http://10.0.0.2:8490" && p.Item2 == "ZZZ222", "join input: codetuner:// with a code= LAN token");
        p = svc.ParseJoinInput("k7m2pq");
        Check(p.Item2 == "K7M2PQ" && p.Item1.StartsWith("http://") && p.Item1.Contains(":849"), "join input: bare room code tries the local LAN host");
    }

    static void DeepLinkTests(CollabService svcParse)
    {
        string lan = "microcode://collab?token=" + Uri.EscapeDataString("http://192.168.1.50:8490/?code=abcd12");
        var pl = CollabDeepLink.PlanFor(lan, null, "TeamApp");
        Check(pl.Kind == "join" && pl.Token == "http://192.168.1.50:8490/?code=abcd12" && pl.Title == "Join live session ABCD12?" && pl.Confirm == "Join Session"
            && pl.Detail == "Host: 192.168.1.50:8490\nMicroCode will open the shared workspace and sync your edits with everyone in the session in real time.", "deep link: join asks with the Mac's title, host and button");
        pl = CollabDeepLink.PlanFor(lan, "ZZZ999", "TeamApp");
        Check(pl.Kind == "join" && pl.Detail.EndsWith("\n\nYou will leave your current session first."), "deep link: joining from another session says it leaves first");
        Check(CollabDeepLink.PlanFor(lan, "abcd12", "TeamApp").Kind == "show", "deep link: the room you are already in just shows the panel");
        pl = CollabDeepLink.PlanFor("microcode://collab?token=192.168.1.50:8472%23ABCD12", null, "TeamApp");
        Check(pl.Kind == "join" && pl.Token == "192.168.1.50:8472#ABCD12" && pl.Title == "Join live session ABCD12?" && pl.Detail.StartsWith("Host: 192.168.1.50:8472\n"),"deep link: an IDE token host:port#CODE");
        pl = CollabDeepLink.PlanFor("codetuner://team-collab?Action=HOST&mode=online", null, "TeamApp");
        Check(pl.Kind == "host" && pl.Online && pl.Title == "Share “TeamApp” for live collaboration?" && pl.Confirm == "Share Workspace" && pl.Detail.Contains("over the internet"), "deep link: host online asks before sharing");
        pl = CollabDeepLink.PlanFor("microcode://collab?action=host&mode=lan", null, "TeamApp");
        Check(pl.Kind == "host" && !pl.Online && pl.Detail.Contains("on your local network"), "deep link: host LAN asks before sharing");
        Check(CollabDeepLink.PlanFor("microcode://collab?action=stop", "X", "w").Kind == "leave" && CollabDeepLink.PlanFor("microcode://collab", null, "w").Kind == "show", "deep link: stop leaves, a bare link shows the panel");
        Check(CollabDeepLink.PlanFor("https://evil.example/collab?token=x", null, "w").Kind == "ignore" && CollabDeepLink.PlanFor("microcode://colab?token=x", null, "w").Kind == "ignore"
            && CollabDeepLink.PlanFor("file://collab?token=x", null, "w").Kind == "ignore", "deep link: other schemes and hosts are ignored");
        Check(CollabDeepLink.IsAppUrl("MicroCode://collab") && !CollabDeepLink.IsAppUrl("microcode") && !CollabDeepLink.IsAppUrl("microcode://collab?token=" + new string('a', 9000)), "deep link: --open-url only takes short microcode: / codetuner: URLs");
        Check(UrlProtocol.CommandFor(@"C:\Apps\MicroCode\MicroCode.exe") == @"""C:\Apps\MicroCode\MicroCode.exe"" --open-url ""%1""", "deep link: the protocol command passes the URL as one --open-url argument");
        // a token that is itself a microcode:// link: the prompt must name what is actually joined
        string inner = "microcode://192.168.1.20:8472?x=&token=" + Uri.EscapeDataString("http://evil.example:8490/?code=abc123") + "#ROOM99";
        pl = CollabDeepLink.PlanFor("microcode://collab?url=" + Uri.EscapeDataString(inner), null, "TeamApp");
        var joined = svcParse.ParseJoinInput(pl.Token ?? "");
        Check(pl.Kind == "join" && pl.Title == "Join live session ABC123?" && pl.Detail.StartsWith("Host: evil.example:8490\n") && joined.Item1 == "http://evil.example:8490" && joined.Item2 == "ABC123",
            "deep link: a nested microcode:// token is unwrapped before the prompt, so it names the host and room that are joined");
        pl = CollabDeepLink.PlanFor("microcode://collab?action=host", "ROOM01", "TeamApp", true);
        Check(pl.Kind == "show", "deep link: a host link while already sharing just shows the room");
        pl = CollabDeepLink.PlanFor("microcode://collab?action=host", "ROOM01", "TeamApp", false);
        Check(pl.Kind == "host" && pl.Detail.EndsWith("\n\nYou will leave your current session first."), "deep link: a host link while joined as a peer says it leaves first");
        Check(CollabDeepLink.PlanFor("microcode:collab?token=x", null, "w").Kind == "ignore", "deep link: scheme:path without // has no host and is ignored (as on the Mac)");

        // a later launch hands its link to the running instance over the per-user pipe (temp data folder, no registry)
        string dir = Path.Combine(Path.GetTempPath(), "mc-single-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        using (var first = new SingleInstance(dir))
        {
            var got = new System.Collections.Concurrent.BlockingCollection<string>();
            first.Listen(u => got.Add(u));
            bool forwarded;
            string received;
            using (var second = new SingleInstance(dir))
            {
                forwarded = !second.IsFirst && second.Forward(lan);
                second.Forward("https://not-an-app-url.example/");
            }
            Check(first.IsFirst && forwarded && got.TryTake(out received, 5000) && received == lan, "deep link: a second launch forwards its link to the running instance");
            Check(!got.TryTake(out received, 1500), "deep link: the running instance ignores anything that is not a microcode: URL");
        }
        Check(SingleInstance.KeyFor(@"C:\Data\MicroCode\") ==SingleInstance.KeyFor(@"c:\data\microcode") && SingleInstance.KeyFor(@"C:\a") != SingleInstance.KeyFor(@"C:\b"), "deep link: one receiving instance per data folder");
    }

    static int Main()
    {
        string root = Path.Combine(Path.GetTempPath(), "mc-collab-tests-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        Defaults.UseDir(Path.Combine(root, "data"));
        TaskFiles.HomeOverride = Path.Combine(root, "home", ".microcode");
        CollabService host = null, peer = null;
        try
        {
            MergeTests();

            // ending a room while peers are connecting must never crash the app (an unhandled exception on a connection
            // thread ends the process — this check would not even print)
            int rounds = 0, attempts = 0;
            for (int round = 0; round < 25; round++)
            {
                var srv = new CollabServer { OnRequest = r => CollabResponse.Json("{}"), OnUpgrade = r => null };
                if (!srv.Start(8700, 8760)) break;
                int sport = srv.Port;
                var conns = Enumerable.Range(0, 10).Select(i => System.Threading.Tasks.Task.Run(() =>
                {
                    try
                    {
                        using (var c = new TcpClient())
                        {
                            c.Connect("127.0.0.1", sport);
                            Interlocked.Increment(ref attempts);
                            var req = Encoding.ASCII.GetBytes(i % 2 == 0 ? "GET /ws/collab HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n" : "GET /x HTTP/1.1\r\nHost: x\r\n\r\n");
                            c.GetStream().Write(req, 0, req.Length);
                            c.GetStream().ReadTimeout = 2000;
                            c.GetStream().Read(new byte[256], 0, 256);
                        }
                    }
                    catch (SocketException) { } catch (IOException) { } catch (ObjectDisposedException) { }
                })).ToArray();
                Thread.Sleep(round % 5);
                srv.Stop();
                System.Threading.Tasks.Task.WaitAll(conns, 5000);
                rounds++;
            }
            Check(rounds == 25 && attempts > 0, "server: ending a room while 10 peers connect, 25 times over, never crashes (" + attempts + " connections)");

            // ── host workspace ──
            string ws = Path.Combine(root, "TeamApp");
            W(Path.Combine(ws, "a.txt"), "line1\nline2\nline3\nline4\nline5\n");
            W(Path.Combine(ws, "src", "main.py"), "print('hi')\n");
            W(Path.Combine(ws, "notes.md"), "# notes\n");
            W(Path.Combine(ws, "node_modules", "dep", "index.js"), "module.exports = 1\n");
            W(Path.Combine(ws, ".git", "HEAD"), "ref: refs/heads/main\n");
            File.WriteAllBytes(Path.Combine(ws, "big.bin"), new byte[2 * 1024 * 1024 + 10]);
            var hostIde = new TestIde { Workspace = ws, Current = Path.Combine(ws, "a.txt") };
            hostIde.SetOpen(Path.Combine(ws, "a.txt"), "line1\nline2\nline3\nline4\nline5\n");
            host = new CollabService(hostIde, Path.Combine(root, "host-data"));
            host.SetIdentity("usr-host0001", "Hana (host)", "Editor", "#5B8DEF");
            _traceHost = host;
            JoinParseTests(host);
            DeepLinkTests(host);

            var session = host.CreateSession();
            Check(session != null && host.Server.IsRunning && host.Server.Port >= 8490 && host.Server.Port <= 8515, "host: session starts on a port in 8490-8515 (" + (host.Server.IsRunning ? host.Server.Port.ToString() : "none") + ")");
            if (session == null) return Finish(root);
            string code = session.ShareCode;
            Check(code.Length == 6 && code.All(ch => "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".IndexOf(ch) >= 0), "host: 6-character room code from the unambiguous alphabet (" + code + ")");
            var rels = host.SharedFiles.Select(f => f.RelativePath).ToList();
            Check(rels.Contains("a.txt") && rels.Contains("src/main.py") && rels.Contains("notes.md"), "host: workspace files are indexed with / paths");
            Check(!rels.Any(r => r.StartsWith("node_modules") || r.StartsWith(".git") || r == "big.bin"), "host: node_modules, .git and files over 2 MB are not shared");
            Check(host.SharedDirectories.Contains("src") && !host.SharedDirectories.Contains("node_modules"), "host: folders are shared, ignored ones are not");
            Check(host.SharedFiles.First(f => f.RelativePath == "a.txt").IsOpenOnHost, "host: an open buffer is marked open on host");
            int port = host.Server.Port;
            string baseUrl = "http://127.0.0.1:" + port;
            Check(host.GetJoinToken().EndsWith(":" + port + "#" + code) && host.GetShareLink().EndsWith(":" + port + "/join?code=" + code), "host: IDE token host:port#CODE and invite link /join?code=CODE");

            // ── invite page: links open MicroCode; the browser editor is opt-in ──
            Check(!host.AllowBrowserGuests, "invite: the browser editor is off by default");
            var g = Get(baseUrl + "/join?code=" + code.ToLowerInvariant());
            Check(g.Item1 == 200 && g.Item2.Contains("microcode://collab?token=") && g.Item2.Contains("[\"" + code + "\"][0]") && g.Item2.Contains("const BROWSER_ALLOWED = false;")
                && !g.Item2.Contains("{{") && !g.Item3.Contains("mc_collab_code"), "invite: /join serves the Open in MicroCode page (code upper-cased, no cookie, browser off)");
            g = Get(baseUrl + "/?code=" + code);
            Check(g.Item2.Contains("microcode://collab?token=") && !g.Item2.Contains("MicroCode Collaboration ·") && !g.Item3.Contains("mc_collab_code"), "invite: with the browser editor off, / is the invite page too (no portal, no cookie)");
            g = Get(baseUrl + "/join?code=%3C/script%3E%22x");
            Check(g.Item2.Contains("[\"SCRIPTX\"][0]") && !g.Item2.Contains("</script>\""), "invite: the code is reduced to letters and digits before it reaches the page");
            string realName = host.Session.WorkspaceName;
            host.Session.WorkspaceName = "{{DOWNLOAD_JSON}}";
            g = Get(baseUrl + "/join?code=" + code);
            Check(g.Item2.Contains("{{DOWNLOAD_JSON}}") && g.Item2.Split(new[] { CollabService.DownloadPageUrl }, StringSplitOptions.None).Length == 2, "invite: values are filled in one pass (a {{placeholder}} in the workspace name stays text)");
            host.Session.WorkspaceName = realName;
            host.AllowBrowserGuests = true;
            g = Get(baseUrl + "/join?code=" + code);
            Check(g.Item2.Contains("const BROWSER_ALLOWED = true;") && g.Item2.Contains("microcode://collab"), "invite: with the browser editor on, /join still opens MicroCode and offers the browser");

            // ── browser portal and gate (browser editor on) ──
            g = Get(baseUrl + "/");
            Check(g.Item1 == 200 && g.Item2.Contains("Join Collaboration · TeamApp") && !g.Item2.Contains("{{") && !g.Item2.Contains("class=\"err\""), "portal: no code shows the room-code gate");
            g = Get(baseUrl + "/?code=WRONG1");
            Check(g.Item2.Contains("Join Collaboration") && g.Item2.Contains("does not match") && g.Item2.Contains("host computer"), "portal: a wrong code shows the gate with the error");
            g = Get(baseUrl + "/?code=" + code.ToLowerInvariant());
            Check(g.Item1 == 200 && g.Item2.Contains("MicroCode Collaboration · TeamApp") && g.Item2.Contains(code) && g.Item3.Contains("mc_collab_code=" + code), "portal: the right code (any case) serves the portal and sets the cookie");
            g = Get(baseUrl + "/", "mc_collab_code=" + code);
            Check(g.Item2.Contains("MicroCode Collaboration"), "portal: the cookie alone opens the portal again");
            var nf = Http.GetAsync(baseUrl + "/nope").Result;
            Check((int)nf.StatusCode == 404, "http: unknown path is 404");
            var opt = Http.SendAsync(new HttpRequestMessage(HttpMethod.Options, baseUrl + "/api/collab/sync")).Result;
            IEnumerable<string> acao;
            Check((int)opt.StatusCode == 204 && opt.Headers.TryGetValues("Access-Control-Allow-Origin", out acao), "http: CORS preflight answers 204 with Allow-Origin");

            var bad = Post(baseUrl + "/api/collab/join", new Dictionary<string, object> { { "code", "AAAAAA" }, { "userId", "x" } });
            Check(bad.Item1 == 403 && (string)bad.Item2["error"] == "Invalid room code", "join: a wrong room code is refused with 403");
            Check(RawUpgrade(port, "AAAAAA").Contains("403"), "websocket: a wrong code is refused with 403");
            Check(RawUpgrade(port, code).Contains("101"), "websocket: the right code upgrades (101)");
            Check(RawUpgrade(port, "").Contains("403"), "websocket: no code at all is refused (403)");

            // every room route needs the room credential (Windows spec §5.5): query code, X-Collab-Code or the portal cookie
            using (var anon = new HttpClient(new HttpClientHandler { UseCookies = false }))
            {
                var noCred = new[] { "/api/collab/workspace-bundle", "/api/collab/file?path=a.txt", "/api/collab/sync", "/api/collab/ops?path=a.txt&since=0" }.Select(u => (int)anon.GetAsync(baseUrl + u).Result.StatusCode).ToList();
                Check(noCred.All(c => c == 403), "credential: room routes without the code are refused (" + string.Join(",", noCred) + ")");
                Check((int)anon.GetAsync(baseUrl + "/api/collab/file?path=a.txt&code=" + code).Result.StatusCode == 200, "credential: ?code= opens them");
                var withCookie = new HttpRequestMessage(HttpMethod.Get, baseUrl + "/api/collab/workspace-bundle");
                withCookie.Headers.TryAddWithoutValidation("Cookie", "mc_collab_code=" + code);
                Check((int)anon.SendAsync(withCookie).Result.StatusCode == 200, "credential: the portal cookie opens them");
            }
            Http.DefaultRequestHeaders.Add("X-Collab-Code", code);

            // ── a browser collaborator over plain HTTP ──
            var web = Post(baseUrl + "/api/collab/join", new Dictionary<string, object> { { "code", code }, { "userId", "web-111" }, { "displayName", "Browser Bo" }, { "role", "Reviewer" }, { "color", "#5B8DEF" } });
            Check(web.Item1 == 200 && (string)web.Item2["shareCode"] == code && (string)web.Item2["assignedColor"] != "#5B8DEF", "join (browser): sync payload back, and a colour the host is not using");
            var bufs = web.Item2["openBuffers"] as Dictionary<string, object>;
            Check(bufs != null && bufs.ContainsKey("a.txt") && (string)bufs["a.txt"] == "line1\nline2\nline3\nline4\nline5\n", "join (browser): open buffers carry the host's text");
            var bundle = Js.DeserializeObject(Get(baseUrl + "/api/collab/workspace-bundle").Item2) as Dictionary<string, object>;
            var bfiles = ((object[])bundle["files"]).Cast<Dictionary<string, object>>().ToList();
            Check(bfiles.Any(f => (string)f["path"] == "src/main.py" && (bool)f["hasInlineContent"] && (string)f["content"] == "print('hi')\n"), "workspace-bundle: files come inline with content");
            var file = Js.DeserializeObject(Get(baseUrl + "/api/collab/file?path=notes.md").Item2) as Dictionary<string, object>;
            Check((string)file["content"] == "# notes\n", "file: one file by path");
            var esc = Js.DeserializeObject(Get(baseUrl + "/api/collab/file?path=../../secret.txt").Item2) as Dictionary<string, object>;
            Check((string)esc["content"] == "" && (string)esc["path"] == "secret.txt", "file: ../ cannot leave the shared folder");
            int revA = Convert.ToInt32(((Dictionary<string, object>)web.Item2["fileRevisions"])["a.txt"]);

            // concurrent edit from an old revision: host changes line 5, browser changes line 1 against the old base
            string aPath = Path.Combine(ws, "a.txt");
            hostIde.SetOpen(aPath, "line1\nline2\nline3\nline4\nLINE5-host\n");
            host.NotifyLocalFileEdited(aPath, "line1\nline2\nline3\nline4\nLINE5-host\n");
            var ed = Post(baseUrl + "/api/collab/edit", new Dictionary<string, object> { { "path", "a.txt" }, { "content", "LINE1-web\nline2\nline3\nline4\nline5\n" }, { "baseRevision", revA }, { "userId", "web-111" }, { "displayName", "Browser Bo" } });
            string merged = ed.Item2.ContainsKey("content") ? (string)ed.Item2["content"] : "";
            Check(ed.Item1 == 200 && (bool)ed.Item2["merged"] && merged == "LINE1-web\nline2\nline3\nline4\nLINE5-host\n", "edit: a stale-base edit is 3-way merged and both changes survive");
            Check(ReadText(aPath) == merged && hostIde.Get(aPath) == merged, "edit: the merged text lands on the host's disk and open buffer");
            Check(host.Activity.Any(a => a.Action == "merged edit" && a.Target == "a.txt"), "activity: the merge is logged");

            // ── a MicroCode peer ──
            var peerIde = new TestIde();
            peer = new CollabService(peerIde, Path.Combine(root, "peer-data"));
            peer.SetIdentity("usr-peer0002", "Pim (peer)", "Editor", "#5B8DEF");
            _tracePeer = peer;
            var ps = peer.JoinSession("127.0.0.1:" + port + "#" + code.ToLowerInvariant()).Result;
            Check(ps != null && !ps.IsHostingLocally && ps.ShareCode == code && peer.Status == CollabStatus.Connected, "peer: joins with the IDE token");
            if (ps == null) return Finish(root);
            string mirror = peerIde.MountedRoot;
            Check(mirror != null && mirror.StartsWith(Path.Combine(root, "peer-data", "CollabWorkspaces", code)) && mirror.EndsWith("TeamApp"), "peer: the workspace is mirrored under CollabWorkspaces\\<code>\\<name>");
            Check(ReadText(Path.Combine(mirror, "src", "main.py")) == "print('hi')\n" && ReadText(Path.Combine(mirror, "a.txt")) == merged, "peer: mirrored files have the host's current text");
            Check(peerIde.MountedActive != null && peerIde.MountedActive.EndsWith("a.txt"), "peer: the host's active file is opened");
            Check(!File.Exists(Path.Combine(mirror, "node_modules", "dep", "index.js")), "peer: ignored folders are not mirrored");
            Check(peer.LocalColor != "#5B8DEF" && peer.LocalColor != host.LocalColor, "peer: gets a colour distinct from the host's (" + peer.LocalColor + ")");
            Check(Until(() => peer.IsWebSocketRealtimeActive), "peer: realtime WebSocket is up");
            Check(Until(() => host.Participants.Any(p => p.UserId == "usr-peer0002" && p.IsOnline)), "presence: the host sees the peer");
            Check(Until(() => peer.Participants.Any(p => p.UserId == "usr-host0001" && p.Role == "Host")), "presence: the peer sees the host as Host");

            // peer → host edit over WebSocket
            string mirrorA = Path.Combine(mirror, "a.txt");
            peerIde.SetOpen(mirrorA, merged);
            peerIde.Current = mirrorA;
            string peerText = merged.Replace("line3", "line3 edited by peer");
            peerIde.SetOpen(mirrorA, peerText);
            peer.NotifyLocalFileEdited(mirrorA, peerText);
            Check(Until(() => ReadText(aPath) == peerText && hostIde.Get(aPath) == peerText), "edit (ws): the peer's edit reaches the host's disk and editor [disk=" + Esc(ReadText(aPath)) + " editor=" + Esc(hostIde.Get(aPath)) + " want=" + Esc(peerText) + "]");

            // host → peer edit as a fileBuffer broadcast
            string hostText = peerText.Replace("line2", "line2 host typed");
            hostIde.SetOpen(aPath, hostText);
            host.NotifyLocalFileEdited(aPath, hostText);
            Check(Until(() => peerIde.Get(mirrorA) == hostText && ReadText(mirrorA) == hostText), "edit (ws): the host's typing reaches the peer's editor and mirror");

            // the host's file is held open without write sharing (antivirus scan, indexer, another editor) when a peer edit
            // lands: the editor updates at once, and the disk catches up once the file is released — the edit is never lost
            string busyText = hostText + "edited while the file was busy\n";
            string diskBefore = ReadText(aPath); // the host's own typing is unsaved, so the disk still has the last saved / remote text
            using (var busy = new FileStream(aPath, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                peerIde.SetOpen(mirrorA, busyText);
                peer.NotifyLocalFileEdited(mirrorA, busyText);
                Check(Until(() => hostIde.Get(aPath) == busyText, 3000), "busy file: the host's editor takes the peer's edit while the file is locked");
                Thread.Sleep(600);
                Check(File.ReadAllText(aPath).Replace("\r\n", "\n") == diskBefore, "busy file: the locked file is not written meanwhile");
            }
            Check(Until(() => ReadText(aPath) == busyText, 5000), "busy file: once released, the disk catches up with the room");
            Check(host.TraceLog.Any(tl => tl.Contains("write deferred (file busy): a.txt")) && host.TraceLog.Any(tl => tl.Contains("deferred write done: a.txt")), "busy file: the deferred write is traced");
            hostText = busyText;

            // an edit on disk to a file nobody has open (agent / git checkout) is picked up and pushed
            Thread.Sleep(1100);
            W(Path.Combine(ws, "notes.md"), "# notes\nchanged on disk\n");
            Check(Until(() => ReadText(Path.Combine(mirror, "notes.md")) == "# notes\nchanged on disk\n", 8000), "disk watch: a closed file changed on the host's disk reaches the peer");

            // a new file on the host shows up on the peer
            W(Path.Combine(ws, "src", "util.py"), "def f():\n    return 1\n");
            Check(Until(() => peer.SharedFiles.Any(f => f.RelativePath == "src/util.py") && ReadText(Path.Combine(mirror, "src", "util.py")) == "def f():\n    return 1\n", 8000), "sync: a new host file appears in the peer's tree and mirror");

            // presence: cursor + typing
            peer.UpdateLocalEditorSelection(mirrorA, 3, 7, 3, 12, true);
            Check(Until(() => { var p = host.Participants.FirstOrDefault(x => x.UserId == "usr-peer0002"); return p != null && p.Cursor != null && p.Cursor.FilePath == "a.txt" && p.Cursor.Line == 3 && p.Cursor.EndColumn == 12; }), "presence: the peer's selection shows on the host (a.txt:3)");
            Check(Until(() => host.SharedFiles.First(f => f.RelativePath == "a.txt").ActiveEditorName == "Pim (peer)"), "presence: a.txt shows the peer as its active editor");
            Check(host.RemoteCollaboratorsIn(aPath).Any(p => p.UserId == "usr-peer0002"), "presence: the host lists the peer in a.txt");
            host.UpdateLocalEditorSelection(aPath, 5, 1, null, null, false);
            Check(Until(() => { var p = peer.Participants.FirstOrDefault(x => x.UserId == "usr-host0001"); return p != null && p.Cursor != null && p.Cursor.Line == 5; }), "presence: the host's caret shows on the peer");
            peer.ToggleFollow("usr-host0001");
            Check(peer.FollowingUserId == "usr-host0001" && Until(() => peerIde.OpenedPath != null && peerIde.OpenedPath.EndsWith("a.txt:5")), "follow: following the host opens its file at its line");
            peer.ToggleFollow("usr-host0001");
            Check(peer.FollowingUserId == null, "follow: toggles off");

            // chat both ways
            peer.SendChatMessage("hello from the peer").Wait();
            Check(Until(() => host.Chat.Any(c => c.Message == "hello from the peer" && c.UserId == "usr-peer0002")), "chat: the peer's message reaches the host");
            host.SendChatMessage("hi peer").Wait();
            Check(Until(() => peer.Chat.Any(c => c.Message == "hi peer")), "chat: the host's message reaches the peer");
            Check(Until(() => peer.Chat.Count(c => c.Message == "hello from the peer") == 1), "chat: no duplicates on the peer after the sync tick");

            // file-system event: a folder made by the browser client
            Post(baseUrl + "/api/collab/fs-event", new Dictionary<string, object> { { "op", "mkdir" }, { "path", "docs/new" } });
            Check(Directory.Exists(Path.Combine(ws, "docs", "new")), "fs-event: mkdir creates the folder on the host");
            Post(baseUrl + "/api/collab/fs-event", new Dictionary<string, object> { { "op", "write" }, { "path", "../escape.txt" }, { "content", "x" } });
            Check(!File.Exists(Path.Combine(root, "escape.txt")) && File.Exists(Path.Combine(ws, "escape.txt")), "fs-event: ../ is stripped, writes stay inside the workspace");

            // ── realtime CRUD: every op must arrive over the WebSocket well inside the 1.2 s HTTP sync tick ──
            const int Live = 900;
            // host → peer
            string hNew = Path.Combine(ws, "src", "created_by_host.py");
            File.WriteAllText(hNew, "x = 1\n");
            host.NotifyLocalFileSystemEvent("write", hNew, null, "x = 1\n");
            Check(Until(() => ReadText(Path.Combine(mirror, "src", "created_by_host.py")) == "x = 1\n", Live), "crud host→peer: new file appears on the peer at once");
            Directory.CreateDirectory(Path.Combine(ws, "assets"));
            host.NotifyLocalFileSystemEvent("mkdir", Path.Combine(ws, "assets"));
            Check(Until(() => Directory.Exists(Path.Combine(mirror, "assets")), Live), "crud host→peer: new folder appears on the peer at once");
            File.WriteAllText(hNew, "x = 2\n");
            host.NotifyLocalFileSystemEvent("write", hNew, null, "x = 2\n");
            Check(Until(() => ReadText(Path.Combine(mirror, "src", "created_by_host.py")) == "x = 2\n", Live), "crud host→peer: a save updates the peer at once");
            string hRen = Path.Combine(ws, "src", "renamed_by_host.py");
            File.Move(hNew, hRen);
            string peerOld = Path.Combine(mirror, "src", "created_by_host.py");
            peerIde.SetOpen(peerOld, "x = 2\n");
            host.NotifyLocalFileSystemEvent("rename", hNew, hRen);
            Check(Until(() => ReadText(Path.Combine(mirror, "src", "renamed_by_host.py")) == "x = 2\n" && !File.Exists(peerOld), Live), "crud host→peer: a rename moves the peer's copy at once");
            Check(Until(() => peerIde.HasMoved(m => m == peerOld + ">" + Path.Combine(mirror, "src", "renamed_by_host.py")), Live), "crud host→peer: the peer's open tab follows the rename");
            File.Delete(hRen);
            host.NotifyLocalFileSystemEvent("delete", hRen);
            Check(Until(() => !File.Exists(Path.Combine(mirror, "src", "renamed_by_host.py")), Live), "crud host→peer: a delete removes the peer's copy at once");
            Check(!host.SharedFiles.Any(f => f.RelativePath == "src/renamed_by_host.py"), "crud host→peer: the host stops sharing the deleted file");

            // peer → host
            string pNew = Path.Combine(mirror, "docs", "from_peer.md");
            Directory.CreateDirectory(Path.GetDirectoryName(pNew));
            File.WriteAllText(pNew, "# from peer\n");
            peer.NotifyLocalFileSystemEvent("write", pNew, null, "# from peer\n");
            Check(Until(() => ReadText(Path.Combine(ws, "docs", "from_peer.md")) == "# from peer\n", Live), "crud peer→host: new file lands on the host at once");
            Check(Until(() => host.SharedFiles.Any(f => f.RelativePath == "docs/from_peer.md"), Live), "crud peer→host: the host shares it");
            Directory.CreateDirectory(Path.Combine(mirror, "lib"));
            peer.NotifyLocalFileSystemEvent("mkdir", Path.Combine(mirror, "lib"));
            Check(Until(() => Directory.Exists(Path.Combine(ws, "lib")), Live), "crud peer→host: new folder lands on the host at once");
            string pRen = Path.Combine(mirror, "docs", "renamed_by_peer.md");
            File.Move(pNew, pRen);
            hostIde.SetOpen(Path.Combine(ws, "docs", "from_peer.md"), "# from peer\n");
            peer.NotifyLocalFileSystemEvent("rename", pNew, pRen);
            Check(Until(() => File.Exists(Path.Combine(ws, "docs", "renamed_by_peer.md")) && !File.Exists(Path.Combine(ws, "docs", "from_peer.md")), Live), "crud peer→host: a rename moves the host's file at once");
            Check(Until(() => hostIde.HasMoved(m => m.EndsWith("renamed_by_peer.md")), Live), "crud peer→host: the host's open tab follows the rename");
            File.Delete(pRen);
            peer.NotifyLocalFileSystemEvent("delete", pRen);
            Check(Until(() => !File.Exists(Path.Combine(ws, "docs", "renamed_by_peer.md")), Live), "crud peer→host: a delete removes the host's file at once");

            // a peer's save made from an older revision while the host typed elsewhere in the file: both survive
            string mainPeer = Path.Combine(mirror, "src", "main.py"), mainHost = Path.Combine(ws, "src", "main.py");
            var before = Js.DeserializeObject(Get(baseUrl + "/api/collab/file?path=src/main.py").Item2) as Dictionary<string, object>;
            int mainBase = Convert.ToInt32(before["revision"]);
            hostIde.SetOpen(mainHost, "print('hi')\n");
            string hostMain = "# host header\nprint('hi')\n";
            hostIde.SetOpen(mainHost, hostMain);
            host.NotifyLocalFileSystemEvent("write", mainHost, null, hostMain);
            File.WriteAllText(mainHost, hostMain);
            // the peer's save, sent the way a peer sends it, but pinned to the revision it had before the host's change
            Post(baseUrl + "/api/collab/fs-event", new Dictionary<string, object> { { "type", "fsEvent" }, { "op", "write" }, { "path", "src/main.py" }, { "content", "print('hi')\nprint('peer')\n" }, { "baseRevision", mainBase }, { "userId", "usr-peer0002" }, { "displayName", "Pim (peer)" } });
            string both = "# host header\nprint('hi')\nprint('peer')\n";
            Check(Until(() => ReadText(mainHost) == both && ReadText(mainPeer) == both, 2500), "crud: a stale save is 3-way merged on the host and the result reaches the peer");

            // a file deleted on the host's disk outside the IDE (Explorer / git / agent) disappears for the peer too
            File.Delete(Path.Combine(ws, "src", "util.py"));
            Check(Until(() => !File.Exists(Path.Combine(mirror, "src", "util.py")), 5000), "crud: a file removed on the host's disk outside the IDE is removed on the peer");
            // a path outside the shared folder is never sent
            W(Path.Combine(ws, "outside.txt"), "keep");
            W(Path.Combine(root, "outside.txt"), "x");
            peer.NotifyLocalFileSystemEvent("delete", Path.Combine(root, "outside.txt"));
            Thread.Sleep(400);
            Check(File.Exists(Path.Combine(ws, "outside.txt")), "crud: a path outside the shared folder is ignored");

            // relay forwarder (the online relay's local half), against the live host and a dead port
            var relayReq = new Dictionary<string, object> { { "type", "http_request" }, { "id", "r1" }, { "method", "GET" }, { "target", "/?code=" + code }, { "headers", new Dictionary<string, object> { { "Host", "relay.example" } } } };
            var rr = Js.DeserializeObject(host.RelayResponseFor(relayReq, port).Result) as Dictionary<string, object>;
            var cookies = rr != null && rr.ContainsKey("set_cookies") ? ((object[])rr["set_cookies"]).Cast<string>().ToList() : new List<string>();
            Check(rr != null && (string)rr["type"] == "http_response" && (string)rr["id"] == "r1" && Convert.ToInt32(rr["status"]) == 200 && cookies.Any(c => c.StartsWith("mc_collab_code=" + code)), "relay: a relayed GET is answered with status, Set-Cookie list and body");
            Check(rr != null && Encoding.UTF8.GetString(Convert.FromBase64String((string)rr["body_b64"])).Contains("MicroCode Collaboration"), "relay: the body is the portal, base64");
            var post = new Dictionary<string, object> { { "id", "r2" }, { "method", "POST" }, { "target", "/api/collab/chat" }, { "headers", new Dictionary<string, object> { { "Content-Type", "application/json" }, { "X-Collab-Code", code } } }, { "body_b64", Convert.ToBase64String(Encoding.UTF8.GetBytes(Js.Serialize(new Dictionary<string, object> { { "userId", "web-111" }, { "displayName", "Browser Bo" }, { "message", "via relay" } }))) } };
            var rp = Js.DeserializeObject(host.RelayResponseFor(post, port).Result) as Dictionary<string, object>;
            Check(Convert.ToInt32(rp["status"]) == 200 && Until(() => host.Chat.Any(c => c.Message == "via relay")), "relay: a relayed POST with a body reaches the host");
            var l = new TcpListener(IPAddress.Loopback, 0); l.Start(); int dead = ((IPEndPoint)l.LocalEndpoint).Port; l.Stop();
            var rd = Js.DeserializeObject(host.RelayResponseFor(new Dictionary<string, object> { { "id", "r3" }, { "method", "GET" }, { "target", "/" } }, dead).Result) as Dictionary<string, object>;
            Check(Convert.ToInt32(rd["status"]) == 502 && Encoding.UTF8.GetString(Convert.FromBase64String((string)rd["body_b64"])) == "Local collaboration host unreachable", "relay: an unreachable local host answers 502");

            OTRoomTests(host, peer, hostIde, peerIde, ws, mirror, baseUrl, code, port);
            TeamTaskTests(host, peer, hostIde, peerIde, ws, mirror, baseUrl, root);
            AITeammateTests(host, peer, hostIde, peerIde, ws, mirror);

            var wsEvents = peer.TraceLog.Where(ev => ev.Contains(" ws connected") || ev.Contains(" ws error") || ev.Contains(" ws io") || ev.Contains("sync failed")).ToList();
            Console.WriteLine("      peer transport events: " + wsEvents.Count);
            foreach (var ev in wsEvents.Take(20)) Console.WriteLine("        " + ev);
            Check(wsEvents.Count(ev => ev.Contains(" ws connected")) == 1 && !wsEvents.Any(ev => ev.Contains("sync failed")), "transport: the peer's realtime socket stayed up and every sync succeeded for the whole session");

            // leave
            peer.LeaveSession().Wait();
            Check(peer.Session == null && peer.Status == CollabStatus.Disconnected, "leave: the peer is disconnected");
            Check(Until(() => !host.Participants.Any(p => p.UserId == "usr-peer0002")), "leave: the host drops the peer");

            // a peer that is still in the room when the host goes away must not keep showing a live host
            peer = new CollabService(new TestIde(), Path.Combine(root, "peer2-data"));
            peer.SetIdentity("usr-peer0003", "Kai (peer)", "Editor", "#8C7A6B");
            _tracePeer = peer;
            Check(peer.JoinSession("127.0.0.1:" + port + "#" + code).Result != null && Until(() => peer.Participants.Any(p => p.UserId == "usr-host0001" && p.IsOnline)), "host gone: a second peer joins and sees the host online");
            host.LeaveSession().Wait();
            bool refused = false;
            try { using (var c = new TcpClient()) c.Connect("127.0.0.1", port); } catch (SocketException) { refused = true; }
            Check(refused && host.Session == null, "end: ending the host session closes the port");
            Check(Until(() => peer.Status == CollabStatus.Reconnecting, 6000), "host gone: the peer's status turns to reconnecting [" + peer.Status + " ws=" + peer.IsWebSocketRealtimeActive + " " + string.Join(",", peer.Participants.Select(p => p.DisplayName + ":" + p.IsOnline)) + " endpoint=" + (peer.Session != null ? peer.Session.RemoteEndpoint : "-") + " hostRunning=" + host.Server.IsRunning + " portOpen=" + PortOpen(port) + "]" + Environment.NewLine + "      " + string.Join(Environment.NewLine + "      ", peer.TraceLog.Skip(Math.Max(0, peer.TraceLog.Count - 25))));
            Check(Until(() => !peer.Participants.Any(p => p.UserId != "usr-peer0003" && p.IsOnline), 6000), "host gone: the peer shows the host (and everyone else) offline");
            peer.LeaveSession().Wait();
            Check(peer.Session == null, "host gone: the peer can still leave cleanly");
        }
        catch (Exception ex) { Check(false, "unexpected: " + ex); }
        finally
        {
            if (peer != null && peer.Session != null) peer.LeaveSession().Wait();
            if (host != null && host.Session != null) host.LeaveSession().Wait();
        }
        return Finish(root);
    }

    // ── ot1 co-editing in the room ────────────────────────────────────────────

    static List<Dictionary<string, object>> Listen(int port, string code, string userId, bool ot1, Action whileListening, int ms)
    {
        var got = new List<Dictionary<string, object>>();
        using (var ws = new System.Net.WebSockets.ClientWebSocket())
        {
            ws.ConnectAsync(new Uri("ws://127.0.0.1:" + port + "/ws/collab?code=" + code), CancellationToken.None).Wait();
            var hello = new Dictionary<string, object> { { "type", "hello" }, { "userId", userId }, { "displayName", userId }, { "color", "#7C8EA6" } };
            if (ot1) hello["caps"] = new[] { "ot1" };
            var hb = Encoding.UTF8.GetBytes(Js.Serialize(hello));
            ws.SendAsync(new ArraySegment<byte>(hb), System.Net.WebSockets.WebSocketMessageType.Text, true, CancellationToken.None).Wait();
            var reader = System.Threading.Tasks.Task.Run(() =>
            {
                var buf = new byte[1 << 16];
                var ms2 = new MemoryStream();
                try
                {
                    while (ws.State == System.Net.WebSockets.WebSocketState.Open)
                    {
                        var r = ws.ReceiveAsync(new ArraySegment<byte>(buf), CancellationToken.None).Result;
                        if (r.MessageType == System.Net.WebSockets.WebSocketMessageType.Close) break;
                        ms2.Write(buf, 0, r.Count);
                        if (!r.EndOfMessage) continue;
                        var d = Js.DeserializeObject(Encoding.UTF8.GetString(ms2.ToArray())) as Dictionary<string, object>;
                        ms2.SetLength(0);
                        if (d != null) lock (got) got.Add(d);
                    }
                }
                catch (AggregateException) { }
            });
            Thread.Sleep(400);
            whileListening();
            Thread.Sleep(ms);
            try { ws.Abort(); } catch (ObjectDisposedException) { }
            reader.Wait(2000);
        }
        lock (got) return got.ToList();
    }

    static void OTRoomTests(CollabService host, CollabService peer, TestIde hostIde, TestIde peerIde, string ws, string mirror, string baseUrl, string code, int port)
    {
        Check(peer.HostSupportsOT, "ot1: the Windows peer and host agree on caps [\"ot1\"]");
        var joinCaps = Js.DeserializeObject(Get(baseUrl + "/api/collab/sync").Item2) as Dictionary<string, object>;
        Check(joinCaps != null && joinCaps.ContainsKey("caps") && ((object[])joinCaps["caps"]).Contains("ot1"), "ot1: the sync / join payload advertises caps");

        // a fresh shared file, open on both sides
        string hFile = Path.Combine(ws, "ot.txt"), pFile = Path.Combine(mirror, "ot.txt");
        File.WriteAllText(hFile, "line1\nline2\n");
        host.NotifyLocalFileSystemEvent("write", hFile, null, "line1\nline2\n");
        Check(Until(() => ReadText(pFile) == "line1\nline2\n", 1500), "ot1: the new file reaches the peer");
        hostIde.SetOpen(hFile, "line1\nline2\n"); peerIde.SetOpen(pFile, "line1\nline2\n");

        // both type on the same line at the same moment: both survive, nothing is duplicated (the old line merger's bug)
        var t1 = System.Threading.Tasks.Task.Run(() => hostIde.Type(host, hFile, t => t.Replace("line1", "line1foo")));
        var t2 = System.Threading.Tasks.Task.Run(() => peerIde.Type(peer, pFile, t => t.Replace("line1", "line1bar")));
        System.Threading.Tasks.Task.WaitAll(t1, t2);
        Func<string, bool> both = t => t != null && (t == "line1foobar\nline2\n" || t == "line1barfoo\nline2\n");
        Check(Until(() => both(hostIde.Get(hFile)) && hostIde.Get(hFile) == peerIde.Get(pFile), 3000), "ot1: same-line concurrent typing converges with both words once [" + Esc(hostIde.Get(hFile)) + " | " + Esc(peerIde.Get(pFile)) + "]");
        Check(Until(() => ReadText(pFile) == peerIde.Get(pFile)), "ot1: the peer's mirror matches its editor");

        // rapid interleaved typing on both sides without waiting for each other (each side types on its own UI thread)
        var typer = System.Threading.Tasks.Task.Run(() => { for (int i = 0; i < 20; i++) hostIde.Type(host, hFile, t => t + "h"); });
        for (int i = 0; i < 20; i++) peerIde.Type(peer, pFile, t => "p" + t);
        typer.Wait(20000);
        Check(Until(() => hostIde.Get(hFile) == peerIde.Get(pFile) && hostIde.Get(hFile).Count(ch => ch == 'h') == 20 && hostIde.Get(hFile).Count(ch => ch == 'p') == 20, 5000),
            "ot1: 20 + 20 interleaved keystrokes converge on both editors with none lost or doubled");

        // typing while a remote op is still being patched into the editor (the UI-thread race)
        string start = peerIde.Get(pFile);
        peerIde.DeferApplies = true;
        string hostNow = hostIde.Get(hFile) + "\nHOST";
        hostIde.SetOpen(hFile, hostNow); host.NotifyLocalFileEdited(hFile, hostNow);
        Thread.Sleep(400);                                     // the op reached the peer; its patch waits in the queue
        peerIde.Type(peer, pFile, t => "TYPED" + t);           // the peer's editor still shows the old text
        peerIde.DeferApplies = false;
        peerIde.FlushApplies();
        Check(Until(() => hostIde.Get(hFile) == peerIde.Get(pFile) && hostIde.Get(hFile).StartsWith("TYPED") && hostIde.Get(hFile).EndsWith("\nHOST"), 4000),
            "ot1: keystrokes typed while a remote op was pending are rebased, not lost or reverted");

        // HTTP ot1 for relay clients: commits in order, own one included; retransmits are idempotent; bad ops get a snapshot
        var ops0 = Js.DeserializeObject(Get(baseUrl + "/api/collab/ops?path=ot.txt&since=0").Item2) as Dictionary<string, object>;
        int rev = Convert.ToInt32(ops0["revision"]);
        string hostText = hostIde.Get(hFile);
        var webOp = new Dictionary<string, object> { { "path", "ot.txt" }, { "baseRevision", rev }, { "op", new object[] { hostText.Length, "!" } }, { "opId", "web-op-1" }, { "userId", "web-111" }, { "displayName", "Browser Bo" } };
        var r1 = Post(baseUrl + "/api/collab/op", webOp).Item2;
        var commits = r1 != null && r1.ContainsKey("commits") ? ((object[])r1["commits"]).Cast<Dictionary<string, object>>().ToList() : new List<Dictionary<string, object>>();
        Check(r1 != null && (bool)r1["ok"] && commits.Any(c => (c["opId"] as string) == "web-op-1" && Convert.ToInt32(c["revision"]) == rev + 1), "ot1 HTTP: POST /api/collab/op commits and returns the commits since its base, its own included");
        Check(Until(() => peerIde.Get(pFile) == hostText + "!" && hostIde.Get(hFile) == hostText + "!"), "ot1 HTTP: the relay client's op reaches both editors");
        var r2 = Post(baseUrl + "/api/collab/op", webOp).Item2;
        var ops1 = Js.DeserializeObject(Get(baseUrl + "/api/collab/ops?path=ot.txt&since=" + rev).Item2) as Dictionary<string, object>;
        Check(r2 != null && (bool)r2["ok"] && Convert.ToInt32(ops1["revision"]) == rev + 1 && hostIde.Get(hFile) == hostText + "!", "ot1 HTTP: a retransmitted opId is not applied twice");
        var bad = Post(baseUrl + "/api/collab/op", new Dictionary<string, object> { { "path", "ot.txt" }, { "baseRevision", rev + 1 }, { "op", new object[] { 1, "x" } }, { "opId", "web-op-2" }, { "userId", "web-111" } }).Item2;
        Check(bad != null && !(bool)bad["ok"] && (string)bad["type"] == "opError" && (string)bad["reason"] == "invalid" && (bool)bad["resync"] && (string)bad["content"] == hostText + "!" && Convert.ToInt32(bad["revision"]) == rev + 1,
            "ot1 HTTP: an op that does not fit gets opError 'invalid' with a snapshot to resync from");
        var since = Js.DeserializeObject(Get(baseUrl + "/api/collab/ops?path=ot.txt&since=" + (rev - 1)).Item2) as Dictionary<string, object>;
        Check(since != null && (bool)since["ok"] && ((object[])since["commits"]).Length == 2, "ot1 HTTP: GET /api/collab/ops returns the commits after 'since'");

        // a mixed room: an ot1 client gets ops, an old client gets whole buffers, for the same commit
        string before = hostIde.Get(hFile);
        Action hostEdit = () => { string t = hostIde.Get(hFile) + "~"; hostIde.SetOpen(hFile, t); host.NotifyLocalFileEdited(hFile, t); };
        var legacy = Listen(port, code, "legacy-client", false, hostEdit, 700);
        Check(legacy.Any(m => (m["type"] as string) == "fileBuffer" && (m["path"] as string) == "ot.txt" && (m["content"] as string) == before + "~") && !legacy.Any(m => (m["type"] as string) == "op"),
            "mixed room: a client without ot1 gets the whole buffer, never an op");
        var modern = Listen(port, code, "ot1-client", true, hostEdit, 700);
        Check(modern.Any(m => (m["type"] as string) == "assignedIdentity" && m.ContainsKey("caps")) && modern.Any(m => (m["type"] as string) == "op" && (m["path"] as string) == "ot.txt") && !modern.Any(m => (m["type"] as string) == "fileBuffer"),
            "mixed room: an ot1 client gets assignedIdentity caps and ops, never a whole buffer");
        Check(Until(() => peerIde.Get(pFile) == hostIde.Get(hFile)), "mixed room: the Windows peer stays in step through both edits");
    }

    // ── Team Tasks ────────────────────────────────────────────────────────────

    static void TeamTaskTests(CollabService host, CollabService peer, TestIde hostIde, TestIde peerIde, string ws, string mirror, string baseUrl, string root)
    {
        const int Live = 1500;
        Check(host.Tasks.WorkspacePath == ws && peer.Tasks.WorkspacePath == mirror, "tasks: the host's board is its workspace, the peer's is the mirror");

        // host → peer (whole list over the room, the Windows host also pushes it over WebSocket)
        var t1 = host.Tasks.CreateTask("Ship collaboration", "Port Team Tasks and the AI teammate", "src/Collab");
        Check(t1 != null && t1.Status == TeamTaskStatus.Planned && t1.Owner == "Hana (host)" && t1.Followers.SequenceEqual(new[] { "Hana (host)" }), "tasks: a new task is Planned, owned and followed by its creator");
        Check(Until(() => peer.Tasks.Tasks.Any(t => t.Id == t1.Id && t.Title == "Ship collaboration" && t.Scope == "src/Collab"), Live), "tasks host→peer: a new task reaches the peer at once");
        Check(Until(() => File.Exists(TaskFiles.Managed(mirror, "team-tasks.json")) && File.ReadAllText(TaskFiles.Managed(mirror, "team-tasks.json")).Contains("Ship collaboration"), Live), "tasks host→peer: the peer saves the room's board in the mirror's task file");
        string hostFile = File.ReadAllText(TaskFiles.Managed(ws, "team-tasks.json"));
        Check(hostFile.Contains("\"schemaVersion\" : 1") && hostFile.Contains("\"status\" : \"planned\"") && System.Text.RegularExpressions.Regex.IsMatch(hostFile, "\"createdAt\" : \"\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\dZ\""), "tasks: team-tasks.json is the Mac document (schemaVersion, raw status, whole-second ISO-8601 dates)");
        Check(!hostFile.Contains("sourceChatID"), "tasks: a missing sourceChatID is omitted, not null (Swift Codable)");

        // the sync payload carries the list as a JSON string the Mac decoder accepts
        var payload = Js.DeserializeObject(Get(baseUrl + "/api/collab/sync").Item2) as Dictionary<string, object>;
        string tj = payload["teamTasksJSON"] as string;
        var parsed = TeamTaskJson.ParseArray(tj);
        Check(tj != null && parsed != null && parsed.Any(t => t.Id == t1.Id) && !System.Text.RegularExpressions.Regex.IsMatch(tj, "\\d\\d:\\d\\d:\\d\\d\\.\\d"), "tasks: teamTasksJSON is a JSON string of the whole board without fractional seconds");

        // peer → host (the peer POSTs its whole list to /api/collab/sync, which a Mac host also understands)
        var t2 = peer.Tasks.CreateTask("Review merge rules", "", "");
        Check(Until(() => host.Tasks.Tasks.Any(t => t.Id == t2.Id && t.Owner == "Pim (peer)"), Live), "tasks peer→host: a task created on the peer reaches the host");
        peer.Tasks.Claim(t1.Id);
        Check(Until(() => host.Tasks.Tasks.Any(t => t.Id == t1.Id && t.Owner == "Pim (peer)" && t.Status == TeamTaskStatus.Active && t.Followers.Contains("Pim (peer)")), Live), "tasks peer→host: Claim makes the peer owner and moves Planned to In progress");
        peer.Tasks.AddDecision("  Keep whole-list sync for Mac interop  ", t1.Id);
        Check(Until(() => host.Tasks.Tasks.Any(t => t.Id == t1.Id && t.Decisions.Any(d => d.Text == "Keep whole-list sync for Mac interop" && d.Author == "Pim (peer)")), Live), "tasks peer→host: a decision (trimmed) reaches the host with its author");
        host.Tasks.Delete(t2.Id);
        Check(Until(() => !peer.Tasks.Tasks.Any(t => t.Id == t2.Id), Live), "tasks host→peer: a delete reaches the peer");
        for (int i = 0; i < 30; i++) host.Tasks.AddDecision("note " + i, t1.Id);
        Check(host.Tasks.Tasks.First(t => t.Id == t1.Id).Decisions.Count == 24, "tasks: the decision log keeps the last 24");
        Check(Until(() => peer.Tasks.Tasks.Any(t => t.Id == t1.Id && t.Decisions.Count == 24 && t.Decisions.Last().Text == "note 29"), Live), "tasks: the trimmed log reaches the peer");

        // activeTaskTitle: each side advertises its selected task
        peer.Tasks.Select(t1.Id);
        Check(Until(() => host.Participants.Any(p => p.UserId == "usr-peer0002" && p.ActiveTaskTitle == "Ship collaboration"), 4000), "tasks: the peer's selected task shows as its activeTaskTitle on the host");

        // the web portal / API route: the host is the actor, as on the Mac
        Post(baseUrl + "/api/collab/task", new Dictionary<string, object> { { "action", "create" }, { "title", "  Web task  " }, { "objective", "from the portal" }, { "scope", "a.txt" }, { "author", "Browser Bo" } });
        var web = host.Tasks.Tasks.FirstOrDefault(t => t.Title == "Web task");
        Check(web != null && web.Owner == "Hana (host)" && web.Objective == "from the portal", "task route create: the title is trimmed and the host owns the new task");
        Check(host.Activity.Any(a => a.Action == "created task" && a.ActorName == "Browser Bo" && a.ActorColor == "#10B981" && a.Target == "Web task"), "task route create: logged as 'created task' by the author");
        Post(baseUrl + "/api/collab/task", new Dictionary<string, object> { { "action", "status" }, { "taskId", web.Id }, { "status", "review" } });
        Check(host.Tasks.Tasks.First(t => t.Id == web.Id).Status == TeamTaskStatus.Review, "task route status: sets the status");
        Post(baseUrl + "/api/collab/task", new Dictionary<string, object> { { "action", "status" }, { "taskId", web.Id }, { "status", "bogus" } });
        Check(host.Tasks.Tasks.First(t => t.Id == web.Id).Status == TeamTaskStatus.Review, "task route status: an unknown status is ignored");
        Post(baseUrl + "/api/collab/task", new Dictionary<string, object> { { "action", "claim" }, { "taskId", web.Id }, { "author", "Browser Bo" } });
        var claimed = host.Tasks.Tasks.First(t => t.Id == web.Id);
        Check(claimed.Owner == "Browser Bo" && claimed.Status == TeamTaskStatus.Active && claimed.Decisions.Any(d => d.Text == "Handed off to Browser Bo." && d.Author == "Hana (host)"), "task route claim: hands off to the author and sets In progress (Mac semantics)");
        var bad = Http.PostAsync(baseUrl + "/api/collab/task", new StringContent("{not json", Encoding.UTF8, "application/json")).Result;
        Check((int)bad.StatusCode == 200 && bad.Content.ReadAsStringAsync().Result.Contains("teamTasksJSON"), "task route: bad JSON still answers 200 with the room state");
        Check(Until(() => peer.Tasks.Tasks.Any(t => t.Id == web.Id && t.Owner == "Browser Bo"), Live), "task route: the result reaches the peer");

        // an invalid task in a pushed list drops the whole list (Swift decodes all-or-nothing)
        int before = host.Tasks.Count;
        Post(baseUrl + "/api/collab/sync", new Dictionary<string, object> { { "userId", "web-111" }, { "teamTasksJSON", "[{\"id\":\"x\",\"title\":\"broken\"}]" } });
        Check(host.Tasks.Count == before, "tasks: a pushed list with an invalid task is ignored as a whole");

        // the agent sees only the selected contract
        host.Tasks.Select(t1.Id);
        string ctx = host.Tasks.ContextForSelectedTask();
        Check(ctx != null && ctx.StartsWith("## Shared Team Task Contract\nTask: Ship collaboration\nStatus: In progress\nOwner: Pim (peer)") && ctx.Contains("Recent decisions:\n- note 26") && ctx.EndsWith("Report blockers and validation evidence clearly."), "tasks: the agent context is the Mac's contract block with the last 4 decisions [" + Esc(ctx) + "]");
        host.Integrations.SetAgentContextEnabled(false);
        Check(host.Tasks.ContextForSelectedTask() == null, "tasks: no contract reaches the agent when 'Let the Agent use the selected task' is off");
        host.Integrations.SetAgentContextEnabled(true);

        // webhooks: validation, DPAPI storage, and the posted text
        Check(TeamIntegrations.Validate("https://hooks.slack.com/services/T/B/x", "slack") && !TeamIntegrations.Validate("https://evil.example/hook", "slack") && !TeamIntegrations.Validate("http://hooks.slack.com/x", "slack")
            && TeamIntegrations.Validate("https://prod-12.westus.logic.azure.com/workflows/x", "teams") && !TeamIntegrations.Validate("https://192.168.1.2/x", "teams") && !TeamIntegrations.Validate("https://hooks.slack.com/x", "teams"),
            "webhooks: https only, Slack host and Teams suffixes allow-listed, private hosts refused");
        var hook = new TcpListener(IPAddress.Loopback, 0); hook.Start();
        int hookPort = ((IPEndPoint)hook.LocalEndpoint).Port;
        string received = null;
        var hookTask = System.Threading.Tasks.Task.Run(() => { using (var c = hook.AcceptTcpClient()) received = ReadHttpBody(c.GetStream(), "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"); });
        TeamIntegrations.AllowLoopbackForTests = true;
        bool saved = host.Integrations.SaveWebhook("http://127.0.0.1:" + hookPort + "/hook", "slack");
        string stored = Defaults.Str("teamWebhook:TEAM_WEBHOOK_SLACK", "");
        Check(saved && host.Integrations.IsEnabled("slack") && stored.Length > 0 && !stored.Contains("127.0.0.1"), "webhooks: the URL is saved DPAPI-encrypted and the connector is enabled");
        var t3 = host.Tasks.CreateTask("Notify the channel", "Tell the team", "");
        hookTask.Wait(8000); hook.Stop();
        string hookText = null;
        try { var hj = received != null ? Js.DeserializeObject(received) as Dictionary<string, object> : null; hookText = hj != null ? hj["text"] as string : null; } catch (ArgumentException) { }
        Check(hookText == "MicroCode team task created\n• Notify the channel\nStatus: Planned · Owner: Hana (host)\nObjective: Tell the team", "webhooks: a created task posts exactly the Mac's summary text");
        host.Integrations.Remove("slack");
        TeamIntegrations.AllowLoopbackForTests = false;
        Check(!host.Integrations.IsConfigured("slack") && Defaults.Get("teamWebhook:TEAM_WEBHOOK_SLACK") == null, "webhooks: Remove deletes the stored URL");
        host.Tasks.Delete(t3.Id);
        Check(Until(() => peer.Tasks.Count == host.Tasks.Count, Live), "tasks: host and peer end with the same board");
    }

    static string ReadHttpBody(NetworkStream s, string reply)
    {
        var head = new List<byte>();
        while (true) { int b = s.ReadByte(); if (b < 0) break; head.Add((byte)b); int n = head.Count; if (n >= 4 && head[n - 4] == 13 && head[n - 3] == 10 && head[n - 2] == 13 && head[n - 1] == 10) break; }
        string h = Encoding.ASCII.GetString(head.ToArray());
        if (h.IndexOf("Expect: 100-continue", StringComparison.OrdinalIgnoreCase) >= 0) { var c = Encoding.ASCII.GetBytes("HTTP/1.1 100 Continue\r\n\r\n"); s.Write(c, 0, c.Length); }
        var m = System.Text.RegularExpressions.Regex.Match(h, @"Content-Length:\s*(\d+)", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        int len = m.Success ? int.Parse(m.Groups[1].Value) : 0; var body = new byte[len]; int got = 0;
        while (got < len) { int r = s.Read(body, got, len - got); if (r <= 0) break; got += r; }
        var rb = Encoding.UTF8.GetBytes(reply); s.Write(rb, 0, rb.Length);
        return Encoding.UTF8.GetString(body, 0, got);
    }

    // ── AI teammate ───────────────────────────────────────────────────────────

    /// <summary>A scripted OpenAI-compatible model on loopback: each request gets the next canned reply.</summary>
    static System.Threading.Tasks.Task ScriptedModel(string[] replies, List<string> bodies, out int port)
    {
        var tcp = new TcpListener(IPAddress.Loopback, 0); tcp.Start();
        port = ((IPEndPoint)tcp.LocalEndpoint).Port;
        return System.Threading.Tasks.Task.Run(() =>
        {
            try
            {
                foreach (var reply in replies)
                    using (var client = tcp.AcceptTcpClient())
                    {
                        client.ReceiveTimeout = 20000;
                        var payload = Encoding.UTF8.GetBytes(reply);
                        string body = ReadHttpBody(client.GetStream(), "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " + payload.Length + "\r\nConnection: close\r\n\r\n" + reply);
                        lock (bodies) bodies.Add(body);
                    }
            }
            finally { tcp.Stop(); }
        });
    }

    static string ToolCall(string id, string name, string argsJson) { return "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"\",\"tool_calls\":[{\"id\":\"" + id + "\",\"type\":\"function\",\"function\":{\"name\":\"" + name + "\",\"arguments\":" + Js.Serialize(argsJson) + "}}]}}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}"; }
    static string TextReply(string t) { return "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":" + Js.Serialize(t) + "}}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}"; }

    /// <summary>The real agent loop (AgentRunner.Run, main-agent mode) on the given workspace.</summary>
    static Tuple<string, string> RunAgent(string workspace, string prompt)
    {
        AppState.Shared.WorkspaceFolder = workspace;
        try
        {
            var res = AgentRunner.Run(new List<ChatMessage> { new ChatMessage { Role = "user", Content = prompt } }, "You are a test agent.", true, false, "collab-test", new AgentCallbacks(), CancellationToken.None).GetAwaiter().GetResult();
            return Tuple.Create(res.Text, (string)null);
        }
        catch (Exception ex) { return Tuple.Create((string)null, ex.GetBaseException().Message); }
    }

    static void AITeammateTests(CollabService host, CollabService peer, TestIde hostIde, TestIde peerIde, string ws, string mirror)
    {
        // @ai parsing (CollaborationService.handleCollabChatAIMentionIfApplicable)
        Check(CollabService.ExtractAIPrompt("@ai fix the build") == "fix the build" && CollabService.ExtractAIPrompt("/ai: add tests") == "add tests" && CollabService.ExtractAIPrompt("@Agent - go") == "go"
            && CollabService.ExtractAIPrompt("hey @ai please look") == "hey @ai please look" && CollabService.ExtractAIPrompt("hello team") == null && CollabService.ExtractAIPrompt("@ai") == "",
            "@ai: prefixes are stripped, a mention mid-message keeps the whole text, plain chat is not a request");

        // the AI teammate as a participant
        Check(host.Participants.Any(p => p.UserId == CollabService.AITeammateUserId && p.Role == "AI Agent" && p.DisplayName == "MicroCode AI" && p.Color == "#94A3B8" && p.IsOnline), "AI teammate: the host lists MicroCode AI (AI Agent, #94A3B8)");
        Check(Until(() => peer.Participants.Any(p => p.UserId == CollabService.AITeammateUserId && p.Role == "AI Agent")), "AI teammate: the peer sees it through the host's participant list");
        host.SetAITeammateEnabled(false);
        Check(!host.Participants.Any(p => p.UserId == CollabService.AITeammateUserId) && Until(() => !peer.Participants.Any(p => p.UserId == CollabService.AITeammateUserId)), "AI teammate: Agent · OFF removes it for everyone");
        Thread.Sleep(300);
        peer.SendChatMessage("@ai this must not run").Wait();
        Thread.Sleep(800);
        lock (hostIde.Prompts) Check(hostIde.Prompts.Count == 0, "@ai: ignored while the AI teammate is off");
        host.SetAITeammateEnabled(true);
        Check(Until(() => peer.Participants.Any(p => p.UserId == CollabService.AITeammateUserId)), "AI teammate: Agent · ON brings it back");

        // @ai from the peer → the host's real agent loop edits a file → the edit reaches the peer as the AI's fileBuffer
        host.AttachAgentEvents();
        Defaults.Set("toolApprovalMode", "yolo");
        var bodies = new List<string>();
        int modelPort;
        string notesHost = Path.Combine(ws, "notes.md"), notesPeer = Path.Combine(mirror, "notes.md");
        string greeting = "# notes\nchanged on disk\nHello from MicroCode AI\n";
        var model = ScriptedModel(new[] { ToolCall("c1", "file_write", Js.Serialize(new Dictionary<string, object> { { "path", "notes.md" }, { "content", greeting } })), TextReply("Added the greeting to notes.md.") }, bodies, out modelPort);
        Defaults.Set("ai_key_mode", "local"); Defaults.Set("ai_base_local", "http://127.0.0.1:" + modelPort + "/v1"); Defaults.Set("ai_model_local", "scripted");
        hostIde.Agent = prompt => RunAgent(ws, prompt);
        hostIde.Current = Path.Combine(ws, "a.txt");
        peer.SendChatMessage("@ai please add a greeting to notes.md").Wait();
        Check(Until(() => { lock (hostIde.Prompts) return hostIde.Prompts.Count == 1; }), "@ai: a peer's request reaches the host's agent");
        string sent; lock (hostIde.Prompts) sent = hostIde.Prompts[0];
        Check(sent == "[Collab Session Request from teammate 'Pim (peer)' (Current file: a.txt)]: please add a greeting to notes.md", "@ai: the agent gets the Mac's request line with the sender and the host's current file");
        Check(Until(() => ReadText(notesPeer) == greeting, 10000), "@ai: the agent's file edit reaches the peer's mirror");
        Check(Until(() => peer.Chat.Any(c => c.UserId == CollabService.AITeammateUserId && c.DisplayName == "MicroCode AI" && c.Message == "Added the greeting to notes.md.")), "@ai: the agent's reply is posted to the room's chat as MicroCode AI");
        Check(host.Activity.Any(a => a.ActorName == "MicroCode AI" && a.Action == "started task for Pim (peer)") && host.Activity.Any(a => a.ActorName == "MicroCode AI" && a.Action == "AI edited" && a.Target.StartsWith("notes.md:")), "@ai: activity shows the request and the AI's edit");
        Check(Until(() => peer.Participants.Any(p => p.UserId == CollabService.AITeammateUserId && p.Cursor != null && p.Cursor.FilePath == "notes.md")), "AI teammate: its cursor moved to the file it edited");
        Check(Until(() => peer.Participants.Any(p => p.UserId == CollabService.AITeammateUserId && !p.IsAIActive && p.AiStatusText == "Ready in Collab"), 4000), "AI teammate: back to 'Ready in Collab' when the turn ends");
        model.Wait(5000);
        Check(bodies.Count == 2 && bodies[0].Contains("[Collab Session Request from teammate"), "@ai: two model calls (tool call, then the reply)");

        // a model that is not configured: the requester gets an answer instead of silence
        Defaults.Set("ai_key_mode", "direct"); Defaults.Set("ai_provider", "openai"); Defaults.Remove("ai_base_local");
        host.SendChatMessage("@ai summarise the session").Wait();
        Check(Until(() => peer.Chat.Any(c => c.UserId == CollabService.AITeammateUserId && c.Message.StartsWith("I couldn't run this request:"))), "@ai: when no model is set up, the chat says the request could not run");
        Check(!peer.Chat.Any(c => c.UserId == CollabService.AITeammateUserId && c.Message == "@ai summarise the session"), "@ai: the AI never answers its own messages");

        // the peer's own agent: its edits reach the host as the peer's edits, not as a second "MicroCode AI"
        host.DetachAgentEvents();
        peer.AttachAgentEvents();
        bodies.Clear();
        string mainNew = "# host header\nprint('hi')\nprint('peer')\nprint('from the peer agent')\n";
        model = ScriptedModel(new[] { ToolCall("p1", "file_write", Js.Serialize(new Dictionary<string, object> { { "path", "src/main.py" }, { "content", mainNew } })), TextReply("done") }, bodies, out modelPort);
        Defaults.Set("ai_key_mode", "local"); Defaults.Set("ai_base_local", "http://127.0.0.1:" + modelPort + "/v1");
        var peerRun = RunAgent(mirror, "edit main.py");
        peer.DetachAgentEvents();
        Check(peerRun.Item2 == null, "peer agent: the run completes (" + (peerRun.Item2 ?? "ok") + ")");
        Check(Until(() => ReadText(Path.Combine(ws, "src", "main.py")) == mainNew, 6000), "peer agent: its file edit reaches the host's disk");
        Check(host.Activity.Any(a => a.ActorName == "Pim (peer)" && a.Target == "src/main.py") && !host.Activity.Any(a => a.ActorName == "MicroCode AI" && a.Target.StartsWith("src/main.py")), "peer agent: the edit is the peer's, not a second MicroCode AI");
        model.Wait(5000);
        hostIde.Agent = null;
    }

    static int Finish(string root)
    {
        try { Directory.Delete(root, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        Console.WriteLine();
        Console.WriteLine(_pass + " passed, " + _fail + " failed");
        return _fail == 0 ? 0 : 1;
    }
}
