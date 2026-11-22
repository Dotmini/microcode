// Self-checking tests for ot1 Operational Transformation (CollabTextOperation, CollabOTClient, CollabOTServerDocument),
// ot1 protocol wiring in CollabService + CollabServer, and MicroCode-only microcode://collab deep-links.
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

class OTTestIde : ICollabIde
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
    public void PathMoved(string oldFull, string newFull) { }
    public void RunAgentPrompt(string prompt, Action<string, string> done) { done(null, "not used"); }
    public void SetOpen(string full, string content) { lock (_l) Open[full] = content; }
    public string Get(string full) { lock (_l) { string s; return Open.TryGetValue(full, out s) ? s : null; } }
}

static class CollabOTTests
{
    static int _pass, _fail;
    static readonly JavaScriptSerializer Js = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
    static readonly HttpClient Http = new HttpClient();

    static void Check(bool ok, string name)
    {
        Console.WriteLine((ok ? "PASS  " : "FAIL  ") + name);
        if (ok) _pass++; else _fail++;
    }

    static bool Until(Func<bool> cond, int ms = 6000)
    {
        var end = DateTime.UtcNow.AddMilliseconds(ms);
        while (DateTime.UtcNow < end)
        {
            try { if (cond()) return true; } catch (IOException) { }
            Thread.Sleep(40);
        }
        return cond();
    }

    static Tuple<int, Dictionary<string, object>> Post(string url, object body)
    {
        var r = Http.PostAsync(url, new StringContent(Js.Serialize(body), Encoding.UTF8, "application/json")).Result;
        return Tuple.Create((int)r.StatusCode, Js.DeserializeObject(r.Content.ReadAsStringAsync().Result) as Dictionary<string, object>);
    }

    static Tuple<int, Dictionary<string, object>> GetJson(string url)
    {
        var r = Http.GetAsync(url).Result;
        return Tuple.Create((int)r.StatusCode, Js.DeserializeObject(r.Content.ReadAsStringAsync().Result) as Dictionary<string, object>);
    }

    static void TestCanonicalBuildersAndApply()
    {
        var op = new CollabTextOperation()
            .Retain(0).Retain(2).Retain(3)
            .Delete(1).Delete(2)
            .Insert("ab").Insert("cd")
            .Insert("")
            .Retain(4);

        // Canonical: adjacent merged + insert before delete -> [5, "abcd", -3, 4]
        Check(op.Components.Count == 4, "canonical: merges adjacent ops and places insert before delete");
        Check(op.Components[0].Kind == CollabOTComponentKind.Retain && op.Components[0].Count == 5, "canonical: retain merged to 5");
        Check(op.Components[1].Kind == CollabOTComponentKind.Insert && op.Components[1].Text == "abcd", "canonical: insert merged to 'abcd' before delete");
        Check(op.Components[2].Kind == CollabOTComponentKind.Delete && op.Components[2].Count == 3, "canonical: delete merged to 3");
        Check(op.Components[3].Kind == CollabOTComponentKind.Retain && op.Components[3].Count == 4, "canonical: trailing retain 4");
        Check(op.BaseLength == 12 && op.TargetLength == 13, "canonical: baseLength=12, targetLength=13");
        Check(!op.IsNoop, "canonical: non-trivial op is not noop");
        Check(new CollabTextOperation().Retain(5).IsNoop && new CollabTextOperation().IsNoop, "canonical: empty and retain-only ops are noop");

        string applied = op.Apply("01234XXX6789");
        Check(applied == "01234abcd6789", "apply: produces expected text");

        bool threwMismatch = false;
        try { op.Apply("short"); }
        catch (CollabOTException ex) { threwMismatch = ex.Kind == CollabOTErrorKind.BaseLengthMismatch; }
        Check(threwMismatch, "apply: throws BaseLengthMismatch on wrong document length");
    }

    static void TestUtf16SurrogatePairsAndThai()
    {
        // Emoji "😀" is U+1F600 -> 2 UTF-16 code units; "😎" is U+1F60E -> 2 UTF-16 code units.
        // Thai "สวัสดีน้ำ" has combining marks (each BMP char = 1 UTF-16 code unit).
        string s1 = "a😀b";
        string s2 = "a😎b";
        Check(s1.Length == 4 && s2.Length == 4, "utf16: emoji surrogate pair has length 2");
        var diffEmoji = CollabTextOperation.FromDiff(s1, s2);
        Check(diffEmoji.Apply(s1) == s2, "fromDiff(emoji): applies cleanly");
        bool validSurrogates = true;
        foreach (var c in diffEmoji.Components)
        {
            if (c.Kind == CollabOTComponentKind.Insert && c.Text.Length > 0)
            {
                if (char.IsLowSurrogate(c.Text[0]) || char.IsHighSurrogate(c.Text[c.Text.Length - 1])) validSurrogates = false;
            }
        }
        Check(validSurrogates, "fromDiff(emoji): never splits a surrogate pair across prefix/insert boundary");

        // Same high surrogate (\uD83D\uDE00 vs \uD83D\uDE0E) and same low surrogate (\uD83D\uDC00 vs \uD83E\uDC00)
        string hiSame1 = "x\uD83D\uDE00y", hiSame2 = "x\uD83D\uDE0Ey";
        var dHi = CollabTextOperation.FromDiff(hiSame1, hiSame2);
        Check(dHi.Apply(hiSame1) == hiSame2 && dHi.Components[1].Text == "\uD83D\uDE0E", "fromDiff: keeps whole surrogate pair when high surrogate matches");

        string loSame1 = "x\uD83D\uDC00y", loSame2 = "x\uD83E\uDC00y";
        var dLo = CollabTextOperation.FromDiff(loSame1, loSame2);
        Check(dLo.Apply(loSame1) == loSame2 && dLo.Components[1].Text == "\uD83E\uDC00", "fromDiff: keeps whole surrogate pair when low surrogate matches");

        string thai1 = "สวัสดีครับ น้ำใส";
        string thai2 = "สวัสดีค่ะ น้ำใส😀";
        var dThai = CollabTextOperation.FromDiff(thai1, thai2);
        Check(dThai.Apply(thai1) == thai2, "fromDiff(thai + emoji): applies cleanly");

        // TransformIndex with surrogate pairs and stickToInsertEnd
        var insAt2 = new CollabTextOperation().Retain(2).Insert("😀").Retain(3);
        Check(insAt2.TransformIndex(2, false) == 2, "transformIndex: at insert offset stays before insert when stickToInsertEnd=false");
        Check(insAt2.TransformIndex(2, true) == 4, "transformIndex: at insert offset moves by 2 UTF-16 units when stickToInsertEnd=true");
        Check(insAt2.TransformIndex(4, false) == 6, "transformIndex: after insert shifts by 2 UTF-16 units");
        var delRange = new CollabTextOperation().Retain(1).Delete(3).Retain(2);
        Check(delRange.TransformIndex(3, false) == 1 && delRange.TransformIndex(5, false) == 2, "transformIndex: inside and after delete map properly");
    }

    static void TestComposeTransformAndJson()
    {
        string doc = "hello world";
        var a = new CollabTextOperation().Retain(5).Insert(",").Retain(6);         // "hello, world"
        var b = new CollabTextOperation().Retain(7).Delete(5).Insert("Thai!").Retain(0); // "hello, Thai!"
        var ab = a.Compose(b);
        Check(ab.Apply(doc) == b.Apply(a.Apply(doc)), "compose: apply(compose(a,b), S) == apply(b, apply(a, S))");

        // Tie-break: lhs insert comes before rhs insert at same offset
        var insA = new CollabTextOperation().Retain(5).Insert("A").Retain(6);
        var insB = new CollabTextOperation().Retain(5).Insert("B").Retain(6);
        var t = CollabTextOperation.Transform(insA, insB);
        string r1 = t.Item2.Apply(insA.Apply(doc));
        string r2 = t.Item1.Apply(insB.Apply(doc));
        Check(r1 == r2 && r1 == "helloAB world", "transform: tie-break places lhs before rhs and converges (" + r1 + ")");

        // JSON round-trip
        var orig = new CollabTextOperation().Retain(4).Insert("สวัสดี😀").Delete(2).Retain(3);
        string jsonStr = orig.ToJsonString();
        var round = CollabTextOperation.FromJsonString(jsonStr);
        Check(orig.Equals(round) && jsonStr.Contains("-2"), "json: ToJsonString/FromJsonString round-trip with Thai & emoji");

        int badRejected = 0;
        foreach (var bad in new[] { "{}", "123", "[0]", "[1.5]", "[true]", "null" })
        {
            try { CollabTextOperation.FromJsonString(bad); }
            catch (CollabOTException ex) { if (ex.Kind == CollabOTErrorKind.InvalidJson) badRejected++; }
        }
        Check(badRejected == 6, "json: invalid payloads rejected with InvalidJson");
    }

    static CollabTextOperation RandomOp(Random rng, string doc)
    {
        var op = new CollabTextOperation();
        int pos = 0;
        string[] tokens = { "x", "ab", "ก", "น้ำ", "😀", "!" };
        while (pos < doc.Length)
        {
            int choice = rng.Next(4);
            if (choice == 0)
            {
                int len = rng.Next(1, Math.Min(4, doc.Length - pos) + 1);
                if (pos + len < doc.Length && char.IsHighSurrogate(doc[pos + len - 1])) len++;
                op.Retain(len);
                pos += len;
            }
            else if (choice == 1)
            {
                op.Insert(tokens[rng.Next(tokens.Length)]);
            }
            else if (choice == 2)
            {
                int len = rng.Next(1, Math.Min(3, doc.Length - pos) + 1);
                if (pos + len < doc.Length && char.IsHighSurrogate(doc[pos + len - 1])) len++;
                op.Delete(len);
                pos += len;
            }
            else
            {
                int rem = doc.Length - pos;
                op.Retain(rem);
                pos += rem;
            }
        }
        if (rng.Next(3) == 0) op.Insert(tokens[rng.Next(tokens.Length)]);
        return op;
    }

    static void TestFuzzConvergence()
    {
        var rng = new Random(20261122);
        bool allConverged = true;
        for (int i = 0; i < 200; i++)
        {
            string s = "alpha beta 😀 สวัสดี gamma delta";
            var a = RandomOp(rng, s);
            var b = RandomOp(rng, s);
            var t = CollabTextOperation.Transform(a, b);
            string s1 = t.Item2.Apply(a.Apply(s));
            string s2 = t.Item1.Apply(b.Apply(s));
            if (s1 != s2) { allConverged = false; break; }
        }
        Check(allConverged, "fuzz: 200 concurrent overlapping edit pairs converge (apply(apply(S,a),b') == apply(apply(S,b),a'))");

        // Multi-step 2-client + server fuzz with buffered ops and out-of-order commits
        var srv = new CollabOTServerDocument("start line 😀 ไทย", 1, 1000);
        var c1 = new CollabOTClient(1);
        var c2 = new CollabOTClient(1);
        string doc1 = srv.Content, doc2 = srv.Content;
        var inFlight1 = new Queue<Tuple<string, CollabTextOperation, int>>();
        var inFlight2 = new Queue<Tuple<string, CollabTextOperation, int>>();
        var pending1 = new Queue<CollabOTServerDocument.Commit>();
        var pending2 = new Queue<CollabOTServerDocument.Commit>();
        int seq = 0;

        for (int step = 0; step < 120; step++)
        {
            int act = rng.Next(4);
            if (act == 0)
            {
                var op = RandomOp(rng, doc1);
                if (!op.IsNoop)
                {
                    doc1 = op.Apply(doc1);
                    var send = c1.ApplyLocal(op);
                    if (send != null) inFlight1.Enqueue(Tuple.Create("c1-" + (++seq), send, c1.Revision));
                }
            }
            else if (act == 1)
            {
                var op = RandomOp(rng, doc2);
                if (!op.IsNoop)
                {
                    doc2 = op.Apply(doc2);
                    var send = c2.ApplyLocal(op);
                    if (send != null) inFlight2.Enqueue(Tuple.Create("c2-" + (++seq), send, c2.Revision));
                }
            }
            else if (act == 2 && inFlight1.Count > 0)
            {
                var item = inFlight1.Dequeue();
                var commit = srv.Receive(item.Item2, item.Item3, "c1", item.Item1);
                pending1.Enqueue(commit);
                pending2.Enqueue(commit);
            }
            else if (inFlight2.Count > 0)
            {
                var item = inFlight2.Dequeue();
                var commit = srv.Receive(item.Item2, item.Item3, "c2", item.Item1);
                pending1.Enqueue(commit);
                pending2.Enqueue(commit);
            }

            // Deliver some server commits to c1 / c2
            while (pending1.Count > 0 && rng.Next(2) == 0)
            {
                var cm = pending1.Dequeue();
                if (cm.AuthorId == "c1")
                {
                    var next = c1.Acknowledge(cm.Revision);
                    if (next != null) inFlight1.Enqueue(Tuple.Create("c1-" + (++seq), next, cm.Revision));
                }
                else
                {
                    doc1 = c1.ApplyRemote(cm.Operation, cm.Revision).Apply(doc1);
                }
            }
            while (pending2.Count > 0 && rng.Next(2) == 0)
            {
                var cm = pending2.Dequeue();
                if (cm.AuthorId == "c2")
                {
                    var next = c2.Acknowledge(cm.Revision);
                    if (next != null) inFlight2.Enqueue(Tuple.Create("c2-" + (++seq), next, cm.Revision));
                }
                else
                {
                    doc2 = c2.ApplyRemote(cm.Operation, cm.Revision).Apply(doc2);
                }
            }
        }
        // Drain remaining in-flight & pending commits
        while (inFlight1.Count > 0 || inFlight2.Count > 0 || pending1.Count > 0 || pending2.Count > 0)
        {
            while (inFlight1.Count > 0)
            {
                var item = inFlight1.Dequeue();
                var cm = srv.Receive(item.Item2, item.Item3, "c1", item.Item1);
                pending1.Enqueue(cm); pending2.Enqueue(cm);
            }
            while (inFlight2.Count > 0)
            {
                var item = inFlight2.Dequeue();
                var cm = srv.Receive(item.Item2, item.Item3, "c2", item.Item1);
                pending1.Enqueue(cm); pending2.Enqueue(cm);
            }
            while (pending1.Count > 0)
            {
                var cm = pending1.Dequeue();
                if (cm.AuthorId == "c1")
                {
                    var next = c1.Acknowledge(cm.Revision);
                    if (next != null) inFlight1.Enqueue(Tuple.Create("c1-" + (++seq), next, cm.Revision));
                }
                else doc1 = c1.ApplyRemote(cm.Operation, cm.Revision).Apply(doc1);
            }
            while (pending2.Count > 0)
            {
                var cm = pending2.Dequeue();
                if (cm.AuthorId == "c2")
                {
                    var next = c2.Acknowledge(cm.Revision);
                    if (next != null) inFlight2.Enqueue(Tuple.Create("c2-" + (++seq), next, cm.Revision));
                }
                else doc2 = c2.ApplyRemote(cm.Operation, cm.Revision).Apply(doc2);
            }
        }
        Check(doc1 == srv.Content && doc2 == srv.Content && c1.IsSynchronized && c2.IsSynchronized && c1.Revision == srv.Revision && c2.Revision == srv.Revision,
            "fuzz(client+server): 2 clients + server converge cleanly at rev " + srv.Revision);
    }

    static void TestClientAndServerDocumentUnits()
    {
        // Client state machine: Outstanding + Buffer + Reset
        var client = new CollabOTClient(1);
        var op1 = new CollabTextOperation().Insert("A").Retain(3);
        var op2 = new CollabTextOperation().Retain(1).Insert("B").Retain(3);
        var op3 = new CollabTextOperation().Retain(2).Insert("C").Retain(3);
        var out1 = client.ApplyLocal(op1);
        var out2 = client.ApplyLocal(op2);
        var out3 = client.ApplyLocal(op3);
        Check(out1 != null && out2 == null && out3 == null && !client.IsSynchronized && client.Buffer != null, "client: first op sent, subsequent ops compose into Buffer");
        var nextOut = client.Acknowledge(2);
        Check(client.Revision == 2 && nextOut != null && nextOut.Apply("Axyz") == "ABCxyz" && client.Buffer == null, "client: Acknowledge advances revision and promotes Buffer to Outstanding");
        client.Reset(10);
        Check(client.Revision == 10 && client.IsSynchronized && client.Buffer == null, "client: Reset clears pending state");

        // Server document: dedup, ReplaceContent, OperationsSince, StaleBase
        var doc = new CollabOTServerDocument("abc", 1, 16);
        var addZ = new CollabTextOperation().Retain(3).Insert("z");
        var c1 = doc.Receive(addZ, 1, "u1", "op-dup-1");
        var c1Dup = doc.Receive(addZ, 1, "u1", "op-dup-1");
        Check(c1.Revision == 2 && c1Dup.Revision == 2 && doc.Content == "abcz" && doc.Revision == 2, "serverDoc: duplicate opId returns original commit without re-applying");

        Check(doc.ReplaceContent("abcz", "host") == null, "serverDoc: ReplaceContent with identical text returns null");
        var rep = doc.ReplaceContent("abcz!", "host");
        Check(rep != null && rep.Revision == 3 && doc.Content == "abcz!", "serverDoc: ReplaceContent diffs and commits");

        // Push 20 more commits so history (max 16) evicts earlier revisions
        for (int i = 0; i < 20; i++)
        {
            doc.Receive(new CollabTextOperation().Retain(doc.Content.Length).Insert("x"), doc.Revision, "u1", "op-" + i);
        }
        Check(doc.History.Count == 16 && doc.Revision == 23, "serverDoc: history bounded to maxHistory=16");
        var since20 = doc.OperationsSince(20);
        Check(since20 != null && since20.Count == 3 && since20[0].Revision == 21, "serverDoc: OperationsSince returns commits > baseRevision");
        Check(doc.OperationsSince(1) == null, "serverDoc: OperationsSince returns null when base fell out of history");

        bool staleThrew = false;
        try { doc.Receive(new CollabTextOperation().Retain(doc.Content.Length).Insert("y"), 1, "u2", "op-stale"); }
        catch (CollabOTException ex) { staleThrew = ex.Kind == CollabOTErrorKind.StaleBase && ex.CurrentRevision == 23; }
        Check(staleThrew, "serverDoc: StaleBase exception thrown with current revision when base fell out of history");
    }

    static void TestDeepLinksAndLoopbackOT()
    {
        // 1. MicroCode-only invite deep-link parsing
        var i1 = CollabService.ParseInviteUri("microcode://collab?token=192.168.1.50:8490%23ABCD12");
        Check(i1.IsValid && i1.Action == "join" && i1.Endpoint == "http://192.168.1.50:8490" && i1.Code == "ABCD12", "deeplink: parses microcode://collab?token=host:port%23CODE");

        var i2 = CollabService.ParseInviteUri("microcode://collab?token=" + Uri.EscapeDataString("https://cloudai.dotmini.net/r/xyz/?code=qwe789"));
        Check(i2.IsValid && i2.Action == "join" && i2.Endpoint == "https://cloudai.dotmini.net/r/xyz" && i2.Code == "QWE789", "deeplink: parses microcode://collab?token=https://.../?code=...");

        var i3 = CollabService.ParseInviteUri("microcode://collab?endpoint=" + Uri.EscapeDataString("http://10.0.0.5:8491") + "&code=xy12ab");
        Check(i3.IsValid && i3.Action == "join" && i3.Endpoint == "http://10.0.0.5:8491" && i3.Code == "XY12AB", "deeplink: parses separate endpoint & code query params");

        var i4 = CollabService.ParseInviteUri("microcode://collab?action=host&mode=online");
        Check(i4.IsValid && i4.Action == "host" && i4.Mode == "online", "deeplink: parses action=host&mode=online");

        var i5 = CollabService.ParseInviteUri("microcode://collab?action=leave");
        Check(i5.IsValid && i5.Action == "leave", "deeplink: parses action=leave");

        var bad1 = CollabService.ParseInviteUri("vscode://collab?token=127.0.0.1:8490%23ABCD12");
        var bad2 = CollabService.ParseInviteUri("https://127.0.0.1:8490/?code=ABCD12");
        Check(!bad1.IsValid && !bad2.IsValid, "deeplink: MicroCode-only — rejects non-microcode:// schemes");

        // 2. Real Host + Peer loopback OT session + HTTP /api/collab/op & /api/collab/ops + JoinFromDeepLink
        string root = Path.Combine(Path.GetTempPath(), "mc-ot-tests-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        Defaults.UseDir(Path.Combine(root, "data"));
        CollabService host = null, peer = null;
        try
        {
            string ws = Path.Combine(root, "OTApp");
            Directory.CreateDirectory(ws);
            string aPath = Path.Combine(ws, "main.txt");
            File.WriteAllText(aPath, "hello world\n", new UTF8Encoding(false));

            var hostIde = new OTTestIde { Workspace = ws, Current = aPath };
            hostIde.SetOpen(aPath, "hello world\n");
            host = new CollabService(hostIde, Path.Combine(root, "host-data"));
            host.SetIdentity("usr-host1", "Host", "Host", "#5B8DEF");
            var session = host.CreateSession();
            Check(session != null && host.Server.IsRunning, "loopback: host session started");
            if (session == null) return;

            int port = host.Server.Port;
            string code = session.ShareCode;
            string baseUrl = "http://127.0.0.1:" + port;
            string deepLink = "microcode://collab?token=" + Uri.EscapeDataString("http://127.0.0.1:" + port + "/?code=" + code);

            var peerIde = new OTTestIde();
            peer = new CollabService(peerIde, Path.Combine(root, "peer-data"));
            peer.SetIdentity("usr-peer1", "Peer", "Editor", "#4E9F86");
            var ps = peer.JoinFromDeepLink(deepLink).Result;
            Check(ps != null && ps.ShareCode == code && peer.HostSupportsOT, "loopback: peer joined via microcode://collab deep-link and negotiated ot1");
            Check(Until(() => peer.IsWebSocketRealtimeActive && host.Server.Clients.Any(c => c.SupportsOT)), "loopback: WebSocket hello advertised ot1 on host");

            string mirrorA = Path.Combine(peerIde.MountedRoot, "main.txt");
            peerIde.SetOpen(mirrorA, "hello world\n");

            // Peer edits end, Host edits start -> both converge!
            peer.NotifyLocalFileEdited(mirrorA, "hello world! 😀\n");
            Check(Until(() => hostIde.Get(aPath) == "hello world! 😀\n"), "loopback ot1: peer edit reached host via op");

            hostIde.SetOpen(aPath, "สวัสดี hello world! 😀\n");
            host.NotifyLocalFileEdited(aPath, "สวัสดี hello world! 😀\n");
            Check(Until(() => peerIde.Get(mirrorA) == "สวัสดี hello world! 😀\n"), "loopback ot1: host edit reached peer via op");

            // HTTP fallback: POST /api/collab/op (with opId dedup) and GET /api/collab/ops
            var opsBefore = GetJson(baseUrl + "/api/collab/ops?path=main.txt&since=1");
            Check(opsBefore.Item1 == 200 && (bool)opsBefore.Item2["ok"], "http /api/collab/ops: returns commits since rev 1");
            int curRev = Convert.ToInt32(opsBefore.Item2["revision"]);
            string curText = hostIde.Get(aPath);
            var httpOp = new CollabTextOperation().Retain(curText.Length).Insert("// via http\n");
            var opReply = Post(baseUrl + "/api/collab/op", new Dictionary<string, object>
            {
                { "path", "main.txt" },
                { "baseRevision", curRev },
                { "op", httpOp.ToJson() },
                { "opId", "http-op-1" },
                { "userId", "web-http" },
                { "displayName", "Relay Peer" }
            });
            Check(opReply.Item1 == 200 && (bool)opReply.Item2["ok"] && Until(() => peerIde.Get(mirrorA) == curText + "// via http\n"), "http /api/collab/op: commits op and broadcasts to ot1 peer");

            // Dedup retry of http-op-1 does not duplicate "// via http\n"
            var dupReply = Post(baseUrl + "/api/collab/op", new Dictionary<string, object>
            {
                { "path", "main.txt" },
                { "baseRevision", curRev },
                { "op", httpOp.ToJson() },
                { "opId", "http-op-1" },
                { "userId", "web-http" },
                { "displayName", "Relay Peer" }
            });
            Check(dupReply.Item1 == 200 && (bool)dupReply.Item2["ok"] && hostIde.Get(aPath) == curText + "// via http\n", "http /api/collab/op: opId deduplication prevents double-apply");

            // Stale / invalid baseRevision -> opError resync payload
            var errReply = Post(baseUrl + "/api/collab/op", new Dictionary<string, object>
            {
                { "path", "main.txt" },
                { "baseRevision", -5 },
                { "op", new List<object> { 1 } },
                { "opId", "bad-op" },
                { "userId", "web-http" }
            });
            Check(errReply.Item1 == 200 && (string)errReply.Item2["type"] == "opError" && (bool)errReply.Item2["resync"] && (string)errReply.Item2["content"] == hostIde.Get(aPath), "http /api/collab/op: stale base returns opError with resync snapshot");

            // Backward-compatible legacy POST /api/collab/edit still works and reaches ot1 peer
            string beforeLegacy = hostIde.Get(aPath);
            var legacyReply = Post(baseUrl + "/api/collab/edit", new Dictionary<string, object>
            {
                { "path", "main.txt" },
                { "content", beforeLegacy + "// legacy\n" },
                { "baseRevision", curRev + 1 },
                { "userId", "legacy-client" },
                { "displayName", "Legacy" }
            });
            Check(legacyReply.Item1 == 200 && (bool)legacyReply.Item2["ok"] && Until(() => peerIde.Get(mirrorA) == beforeLegacy + "// legacy\n"), "compat: legacy /api/collab/edit commits into ot1 and reaches ot1 peer");

            // Concurrent 2-peer loopback WebSocket editing + opSync catch-up
            var peer2Ide = new OTTestIde();
            var peer2 = new CollabService(peer2Ide, Path.Combine(root, "peer2-data"));
            peer2.SetIdentity("usr-peer2", "Peer2", "Editor", "#C28E5C");
            try
            {
                var ps2 = peer2.JoinFromDeepLink(deepLink).Result;
                Check(ps2 != null && peer2.HostSupportsOT && Until(() => peer2.IsWebSocketRealtimeActive), "loopback ot1: second peer joins and connects via ot1 WebSocket");
                string mirror2A = Path.Combine(peer2Ide.MountedRoot, "main.txt");
                string sharedNow = hostIde.Get(aPath);
                peer2Ide.SetOpen(mirror2A, sharedNow);

                // Peer1 prepends, Peer2 appends concurrently
                peer.NotifyLocalFileEdited(mirrorA, "[P1] " + sharedNow);
                peer2.NotifyLocalFileEdited(mirror2A, sharedNow + "[P2]\n");
                string expectedConverged = "[P1] " + sharedNow + "[P2]\n";
                Check(Until(() => hostIde.Get(aPath) == expectedConverged && peerIde.Get(mirrorA) == expectedConverged && peer2Ide.Get(mirror2A) == expectedConverged, 6000),
                    "loopback ot1: 2 concurrent WebSocket peers + host converge to identical text");

                // Raw ClientWebSocket opSync catch-up
                using (var rawWs = new System.Net.WebSockets.ClientWebSocket())
                {
                    var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                    rawWs.ConnectAsync(new Uri("ws://127.0.0.1:" + port + "/ws/collab?code=" + code), cts.Token).Wait();
                    var helloBytes = Encoding.UTF8.GetBytes(Js.Serialize(new Dictionary<string, object> { { "type", "hello" }, { "userId", "raw-ot" }, { "displayName", "RawOT" }, { "protocol", "ot1" } }));
                    rawWs.SendAsync(new ArraySegment<byte>(helloBytes), System.Net.WebSockets.WebSocketMessageType.Text, true, cts.Token).Wait();
                    var syncBytes = Encoding.UTF8.GetBytes(Js.Serialize(new Dictionary<string, object> { { "type", "opSync" }, { "path", "main.txt" }, { "since", 1 } }));
                    rawWs.SendAsync(new ArraySegment<byte>(syncBytes), System.Net.WebSockets.WebSocketMessageType.Text, true, cts.Token).Wait();
                    int opCount = 0;
                    var buf = new byte[8192];
                    var sw = System.Diagnostics.Stopwatch.StartNew();
                    while (sw.ElapsedMilliseconds < 2000 && opCount < 2)
                    {
                        var recvTask = rawWs.ReceiveAsync(new ArraySegment<byte>(buf), cts.Token);
                        if (!recvTask.Wait(1000)) break;
                        string frameText = Encoding.UTF8.GetString(buf, 0, recvTask.Result.Count);
                        var fmsg = Js.DeserializeObject(frameText) as Dictionary<string, object>;
                        if (fmsg != null && (string)fmsg["type"] == "op") opCount++;
                    }
                    Check(opCount >= 2, "ws opSync: raw ot1 WebSocket receives historical op commits since rev 1");
                }
            }
            finally
            {
                if (peer2.Session != null) peer2.LeaveSession().Wait();
            }

            // GET /join serves deep-link landing page
            var joinResp = Http.GetAsync(baseUrl + "/join?code=" + code).Result;
            string joinHtml = joinResp.Content.ReadAsStringAsync().Result;
            Check((int)joinResp.StatusCode == 200 && joinHtml.Contains("microcode://collab?token="), "http /join: serves microcode://collab invite landing page");
        }
        finally
        {
            if (peer != null && peer.Session != null) peer.LeaveSession().Wait();
            if (host != null && host.Session != null) host.LeaveSession().Wait();
            try { Directory.Delete(root, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }

    static int Main()
    {
        TestCanonicalBuildersAndApply();
        TestUtf16SurrogatePairsAndThai();
        TestComposeTransformAndJson();
        TestFuzzConvergence();
        TestClientAndServerDocumentUnits();
        TestDeepLinksAndLoopbackOT();

        Console.WriteLine();
        Console.WriteLine(_pass + " passed, " + _fail + " failed");
        return _fail == 0 ? 0 : 1;
    }
}
