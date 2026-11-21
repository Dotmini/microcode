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
        p = svc.ParseJoinInput("k7m2pq");
        Check(p.Item2 == "K7M2PQ" && p.Item1.StartsWith("http://") && p.Item1.Contains(":849"), "join input: bare room code tries the local LAN host");
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
            Check(host.GetJoinToken().EndsWith(":" + port + "#" + code) && host.GetShareLink().EndsWith(":" + port + "/?code=" + code), "host: IDE token host:port#CODE and invite link /?code=CODE");

            // ── browser portal and gate ──
            var g = Get(baseUrl + "/");
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
            var post = new Dictionary<string, object> { { "id", "r2" }, { "method", "POST" }, { "target", "/api/collab/chat" }, { "headers", new Dictionary<string, object> { { "Content-Type", "application/json" } } }, { "body_b64", Convert.ToBase64String(Encoding.UTF8.GetBytes(Js.Serialize(new Dictionary<string, object> { { "userId", "web-111" }, { "displayName", "Browser Bo" }, { "message", "via relay" } }))) } };
            var rp = Js.DeserializeObject(host.RelayResponseFor(post, port).Result) as Dictionary<string, object>;
            Check(Convert.ToInt32(rp["status"]) == 200 && Until(() => host.Chat.Any(c => c.Message == "via relay")), "relay: a relayed POST with a body reaches the host");
            var l = new TcpListener(IPAddress.Loopback, 0); l.Start(); int dead = ((IPEndPoint)l.LocalEndpoint).Port; l.Stop();
            var rd = Js.DeserializeObject(host.RelayResponseFor(new Dictionary<string, object> { { "id", "r3" }, { "method", "GET" }, { "target", "/" } }, dead).Result) as Dictionary<string, object>;
            Check(Convert.ToInt32(rd["status"]) == 502 && Encoding.UTF8.GetString(Convert.FromBase64String((string)rd["body_b64"])) == "Local collaboration host unreachable", "relay: an unreachable local host answers 502");

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

    static int Finish(string root)
    {
        try { Directory.Delete(root, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        Console.WriteLine();
        Console.WriteLine(_pass + " passed, " + _fail + " failed");
        return _fail == 0 ? 0 : 1;
    }
}
