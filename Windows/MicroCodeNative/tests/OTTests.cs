// ot1 co-editing regression for the Windows port: the same checks as Scripts/tests/collab-ot-regression.swift, run against
// src/Collab/CollabOT.cs (operation algebra, client state machine, host log, randomized 3-client + host convergence).
using System;
using System.Collections.Generic;
using System.Linq;
using System.Web.Script.Serialization;
using MicroCode.Views;

static class OTTests
{
    static int _pass, _fail;
    static void Check(bool ok, string name) { Console.WriteLine((ok ? "PASS  " : "FAIL  ") + name); if (ok) _pass++; else _fail++; }
    static readonly JavaScriptSerializer Js = new JavaScriptSerializer();

    static string TryApply(TextOperation op, string s) { try { return op.Apply(s); } catch (OTException) { return null; } }
    static TextOperation TryJson(string json) { try { return TextOperation.FromJson(Js.DeserializeObject(json)); } catch (OTException) { return null; } }

    class SimClient { public string Id, Text; public OTClient Ot; public List<OTServerDocument.Commit> Inbox = new List<OTServerDocument.Commit>(); public int Sent; }

    static bool ValidUtf16(string s)
    {
        for (int i = 0; i < s.Length; i++)
        {
            if (char.IsHighSurrogate(s[i])) { if (i + 1 >= s.Length || !char.IsLowSurrogate(s[i + 1])) return false; i++; }
            else if (char.IsLowSurrogate(s[i])) return false;
        }
        return true;
    }

    static int Main()
    {
        // ── algebra ──
        var op = new TextOperation().Retain(3).Insert("XY").Delete(2).Retain(1);
        Check(TryApply(op, "abcdef") == "abcXYf", "apply retain/insert/delete");
        Check(op.ToJson().Count == 4 && Js.Serialize(op.ToJson()) == "[3,\"XY\",-2,1]", "json shape [3,\"XY\",-2,1]");
        Check(op.Equals(TryJson(Js.Serialize(op.ToJson()))), "json round trip");
        Check(TryJson("[1,0]") == null, "zero component rejected");
        Check(TryJson("[true]") == null, "bool component rejected");
        Check(TryJson("[1.5]") == null && TryJson("{\"a\":1}") == null && TryJson("\"x\"") == null, "fractions, objects and bare strings rejected");
        Check(TryApply(op, "abc") == null, "base length mismatch rejected");
        Check(TryJson("[2147483647,2147483647,4]") == null && TryJson("[100000000000000000000]") == null && TryJson("[1e300]") == null && TryJson("[-9000000]") == null,
            "hostile lengths are rejected at parse time (no int wrap-around, no overflow exception)");
        bool threw = false;
        try { new TextOperation().Retain(TextOperation.MaxLength).Retain(1); } catch (OTException) { threw = true; }
        Check(threw, "builders refuse to grow past MaxLength");
        var canon = new TextOperation().Retain(1).Delete(2).Insert("a").Insert("b").Delete(1);
        Check(Js.Serialize(canon.ToJson()) == "[1,\"ab\",-3]", "canonical form: inserts merge before deletes");

        string thai = "สวัสดี 👋🏽 world", edited = "สวัสดีครับ 👋 world!";
        Check(TryApply(TextOperation.FromDiff(thai, edited), thai) == edited, "diff Thai + emoji");
        var swap = TextOperation.FromDiff("a😀b", "a😃b");
        var inserted = swap.Components.Where(c => c.Kind == TextOperation.Kind.Insert).Select(c => c.Text).FirstOrDefault();
        Check(inserted == "😃", "diff never splits a surrogate pair");
        Check(TryApply(swap, "a😀b") == "a😃b", "surrogate swap applies");

        // the old line merger duplicated a line being typed on two sides
        string b0 = "line1\nline2\n";
        var first = TextOperation.FromDiff(b0, "line1\nfoo\nline2\n");
        var second = TextOperation.FromDiff("line1\nfoo\nline2\n", "line1\nfoobar\nline2\n");
        var server = new OTServerDocument(b0, 1);
        OTServerDocument.ReceiveError err;
        server.Receive(first, 1, "web", "a", out err);
        server.Receive(second, 2, "web", "b", out err);
        Check(server.Content == "line1\nfoobar\nline2\n", "sequential typing never duplicates a line");
        server.Receive(second, 2, "web", "b", out err);
        Check(server.Content == "line1\nfoobar\nline2\n" && server.Revision == 3, "retransmitted opId is idempotent");

        var a = new TextOperation().Retain(2).Insert("A").Retain(3);
        var b = new TextOperation().Retain(2).Insert("B").Retain(3);
        var ab = TextOperation.Transform(a, b);
        string viaA = ab.Item2.Apply(a.Apply("hello")), viaB = ab.Item1.Apply(b.Apply("hello"));
        Check(viaA == viaB && viaA == "heABllo", "concurrent same-offset inserts converge, client first");
        var c1 = new TextOperation().Retain(1).Delete(3).Retain(1);
        var d1 = new TextOperation().Retain(2).Delete(2).Insert("Z").Retain(1);
        var cd = TextOperation.Transform(c1, d1);
        Check(cd.Item2.Apply(c1.Apply("hello")) == cd.Item1.Apply(d1.Apply("hello")), "overlapping deletes converge");
        Check(a.Compose(TextOperation.FromDiff("heAllo", "heAllo!")).Apply("hello") == "heAllo!", "compose");

        var ins = new TextOperation().Retain(2).Insert("XX").Retain(3);
        Check(ins.TransformIndex(1) == 1, "caret before insert stays");
        Check(ins.TransformIndex(4) == 6, "caret after insert shifts");
        Check(ins.TransformIndex(2) == 2, "caret at insert point stays before remote text");
        Check(ins.TransformIndex(2, true) == 4, "caret can stick to insert end");
        var del = new TextOperation().Retain(1).Delete(3).Retain(1);
        Check(del.TransformIndex(3) == 1, "caret inside deleted range collapses to start");

        var small = new OTServerDocument("x", 1, 16);
        for (int i = 0; i < 40; i++) small.ReplaceContent("x" + i, "host");
        var late = new TextOperation().Retain(1).Insert("y");
        Check(small.Receive(late, 1, "web", null, out err) == null && err == OTServerDocument.ReceiveError.StaleBase, "stale base asks for resync");
        Check(small.Receive(late, small.Revision + 1, "web", null, out err) == null && err == OTServerDocument.ReceiveError.Invalid, "a base from the future is invalid");
        Check(small.OperationsSince(small.Revision - 3).Count == 3 && small.OperationsSince(1) == null, "operations since a retained / dropped revision");

        // ── randomized convergence: host + 3 clients, random edits, random delivery order ──
        var rng = new Random(20261122);
        string alphabet = "ab\nก่ข😀 ";
        var symbols = new List<string>();
        for (int i = 0; i < alphabet.Length; i++) { if (char.IsHighSurrogate(alphabet[i])) { symbols.Add(alphabet.Substring(i, 2)); i++; } else symbols.Add(alphabet[i].ToString()); }
        Func<string, string> randomEdit = text =>
        {
            int roll = rng.Next(10), pos = text.Length == 0 ? 0 : rng.Next(text.Length + 1);
            string candidate;
            if (roll < 6 || text.Length == 0)
            {
                string s = string.Concat(Enumerable.Range(0, rng.Next(1, 4)).Select(_ => symbols[rng.Next(symbols.Count)]));
                candidate = text.Insert(pos, s);
            }
            else
            {
                int end = Math.Min(text.Length, pos + rng.Next(1, 5));
                candidate = pos < end ? text.Remove(pos, end - pos) : text;
            }
            return ValidUtf16(candidate) ? candidate : text + "q";
        };

        bool allConverged = true;
        for (int round = 0; round < 300 && allConverged; round++)
        {
            string start = "fn main() {\n  สวัสดี\n}\n";
            var srv = new OTServerDocument(start, 1);
            var clients = Enumerable.Range(0, 3).Select(i => new SimClient { Id = "c" + i, Text = start, Ot = new OTClient(1) }).ToList();
            var toHost = new List<Tuple<int, TextOperation, int, string>>();
            int hostEditEvery = rng.Next(3, 8);
            Action<int, TextOperation> send = (ci, o) => { clients[ci].Sent++; toHost.Add(Tuple.Create(ci, o, clients[ci].Ot.Revision, clients[ci].Id + "-" + clients[ci].Sent)); };
            Action<int> deliver = ci =>
            {
                var commit = clients[ci].Inbox[0]; clients[ci].Inbox.RemoveAt(0);
                if (commit.AuthorId == clients[ci].Id) { var next = clients[ci].Ot.Acknowledge(commit.Revision); if (next != null) send(ci, next); }
                else clients[ci].Text = clients[ci].Ot.ApplyRemote(commit.Operation, commit.Revision).Apply(clients[ci].Text);
            };
            Action hostReceive = () =>
            {
                var m = toHost[0]; toHost.RemoveAt(0);
                OTServerDocument.ReceiveError e;
                var commit = srv.Receive(m.Item2, m.Item3, clients[m.Item1].Id, m.Item4, out e);
                if (commit == null) throw new Exception("host rejected an op: " + e);
                foreach (var cl in clients) cl.Inbox.Add(commit);
            };
            try
            {
                for (int step = 0; step < 60; step++)
                {
                    int action = rng.Next(4);
                    if (action == 0 || (toHost.Count == 0 && clients.All(x => x.Inbox.Count == 0)))
                    {
                        int ci = rng.Next(3);
                        string next = randomEdit(clients[ci].Text);
                        var o = TextOperation.FromDiff(clients[ci].Text, next);
                        clients[ci].Text = next;
                        var outOp = clients[ci].Ot.ApplyLocal(o);
                        if (outOp != null) send(ci, outOp);
                    }
                    else if (action == 1 && toHost.Count > 0) hostReceive();
                    else { int ci = rng.Next(3); if (clients[ci].Inbox.Count > 0) deliver(ci); }
                    if (step % hostEditEvery == 0)
                    {
                        var commit = srv.ReplaceContent(randomEdit(srv.Content), "host");
                        if (commit != null) foreach (var cl in clients) cl.Inbox.Add(commit);
                        hostEditEvery = rng.Next(3, 8);
                    }
                }
                int guard = 0;
                while ((toHost.Count > 0 || clients.Any(x => x.Inbox.Count > 0)) && guard++ < 10000)
                {
                    if (toHost.Count > 0) hostReceive();
                    for (int ci = 0; ci < clients.Count; ci++) if (clients[ci].Inbox.Count > 0) deliver(ci);
                }
                if (!clients.All(x => x.Text == srv.Content && x.Ot.IsSynchronized)) { allConverged = false; Console.WriteLine("      diverged in round " + round); }
            }
            catch (Exception ex) { allConverged = false; Console.WriteLine("      round " + round + ": " + ex.Message); }
        }
        Check(allConverged, "300 random 3-client + host sessions converge");

        Console.WriteLine();
        Console.WriteLine(_pass + " passed, " + _fail + " failed");
        return _fail == 0 ? 0 : 1;
    }
}
