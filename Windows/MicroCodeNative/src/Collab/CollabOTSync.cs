// Co-editing protocol "ot1" in the room (CollaborationService.swift: hostCommitContent / hostReceiveOperation /
// hostPublishCommit / peerSubmitLocalContent / peerHandleCommit / peerResync; docs/windows-port/README.md §5.5).
//
// Host: one authoritative OTServerDocument per file. EVERY content change — host typing, peers' ops, legacy full-text edits,
// disk changes, the AI teammate — goes through HostCommitContent / HostReceiveOperation → HostPublishCommit, which updates
// the room's records, patches the host editor in place, and broadcasts "op" to ot1 clients (the author's own copy is its
// ack) and "fileBuffer" to legacy clients.
// Peer: one OTClient per file (one op in flight + composed buffer). Remote ops are transformed against what is pending and
// patched into the editor; gaps and rejections reload the file (resync) and replay what arrived meanwhile.
// Editor race: a remote op is patched on the UI thread after it was committed here, so keystrokes typed in between are
// transformed on the UI side, and local notifications are held back while a patch is pending (EditorApplied re-sends them).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace MicroCode.Views
{
    public partial class CollabService
    {
        public const string OTCapability = "ot1";
        const int OTMaxTarget = 8000000;

        readonly Dictionary<string, OTServerDocument> _otDocs = new Dictionary<string, OTServerDocument>(StringComparer.Ordinal);
        readonly Dictionary<string, DateTime> _lastEditActivity = new Dictionary<string, DateTime>(StringComparer.Ordinal);
        readonly Dictionary<string, int> _editorPending = new Dictionary<string, int>(StringComparer.Ordinal);

        class PeerOTFile { public OTClient Client; public string Shadow; public string OutstandingOpId; }
        readonly Dictionary<string, PeerOTFile> _peerOT = new Dictionary<string, PeerOTFile>(StringComparer.Ordinal);
        readonly Dictionary<string, List<Dictionary<string, object>>> _peerResyncQueue = new Dictionary<string, List<Dictionary<string, object>>>(StringComparer.Ordinal);
        /// <summary>The host we joined speaks ot1 (from the join reply's or assignedIdentity's caps).</summary>
        public bool HostSupportsOT { get; private set; }
        bool PeerUsesOT { get { return HostSupportsOT && Session != null && !Session.IsHostingLocally; } }

        static List<object> Caps() { return new List<object> { OTCapability }; }
        static bool HasOT(Dictionary<string, object> d)
        {
            object v;
            if (d == null || !d.TryGetValue("caps", out v) || v == null) return false;
            var e = v as System.Collections.IEnumerable;
            return e != null && !(v is string) && e.Cast<object>().Any(x => (x as string) == OTCapability);
        }

        string NewOperationId() { return LocalUserId + "-" + Guid.NewGuid().ToString("N").Substring(0, 12); }

        // ── editor bridge ──

        string EditorLiveText(string rel)
        {
            string full = FullPathOf(rel);
            if (full == null) return null;
            var f = _ide.OpenFiles().FirstOrDefault(o => string.Equals(o.FullPath, full, StringComparison.OrdinalIgnoreCase));
            return f != null ? (f.Content ?? "").Replace("\r\n", "\n") : null;
        }

        int Pending(string rel) { int n; return _editorPending.TryGetValue(rel, out n) ? n : 0; }

        /// <summary>applyCommittedOperationToLocalEditor: patch the open editor with op (base = previous).</summary>
        void PushOpToEditor(string rel, TextOperation op, string previous, string resulting)
        {
            string full = FullPathOf(rel);
            _lastSynced[rel] = resulting;
            if (full == null || !_ide.OpenFiles().Any(o => string.Equals(o.FullPath, full, StringComparison.OrdinalIgnoreCase))) return;
            _editorPending[rel] = Pending(rel) + 1;
            _ide.ApplyRemoteOp(full, op, previous, resulting, text => EditorApplied(rel, text));
        }

        /// <summary>The editor finished patching an op. Keystrokes typed meanwhile were transformed by the editor; once nothing
        /// is pending they go to the room like any local edit.</summary>
        void EditorApplied(string rel, string editorText)
        {
            bool resend = false;
            lock (_gate)
            {
                int n = Pending(rel) - 1;
                if (n <= 0) _editorPending.Remove(rel); else _editorPending[rel] = n;
                if (n <= 0 && editorText != null && Session != null)
                {
                    string known = Session.IsHostingLocally ? HostDoc(rel).Content : (_peerOT.ContainsKey(rel) ? _peerOT[rel].Shadow : null);
                    resend = known != null && known != editorText.Replace("\r\n", "\n");
                }
            }
            if (resend) NotifyLocalFileEdited(FullPathOf(rel), editorText);
        }

        // ── host ──

        OTServerDocument HostDoc(string rel)
        {
            OTServerDocument doc;
            if (_otDocs.TryGetValue(rel, out doc)) return doc;
            doc = new OTServerDocument(ResolveFileContent(rel), Rev(rel));
            _otDocs[rel] = doc;
            return doc;
        }

        /// <summary>hostFlushLiveEditor: keystrokes the host typed but the debounced notify has not sent yet are committed
        /// first, so a remote op never lands on (and overwrites) unsent local text.</summary>
        void HostFlushLiveEditor(string rel)
        {
            if (Session == null || !Session.IsHostingLocally || Pending(rel) > 0) return;
            string live = EditorLiveText(rel);
            if (live == null || live == HostDoc(rel).Content) return;
            HostCommitContent(rel, live, LocalUserId, LocalDisplayName, LocalColor, false, false, false);
        }

        /// <summary>hostCommitContent: a full-text change (host editor, disk, AI teammate, legacy client) as one ot1 commit.</summary>
        OTServerDocument.Commit HostCommitContent(string rel, string content, string authorId, string authorName, string authorColor, bool writeToDisk, bool updateEditor, bool legacyEchoToAuthor)
        {
            var doc = HostDoc(rel);
            string previous = doc.Content;
            var commit = doc.ReplaceContent(content.Replace("\r\n", "\n"), authorId);
            if (commit == null) return null;
            HostPublishCommit(rel, doc, commit, previous, authorName, authorColor, writeToDisk, updateEditor, legacyEchoToAuthor);
            return commit;
        }

        enum OTOutcome { Committed, Duplicate, Rejected }

        /// <summary>hostReceiveOperation: a client's op against baseRevision, transformed over later commits.</summary>
        OTOutcome HostReceiveOperation(string rel, TextOperation op, int baseRevision, string authorId, string authorName, string authorColor, string opId, out OTServerDocument.Commit commit, out string reason)
        {
            commit = null; reason = null;
            if (op.TargetLength > OTMaxTarget) { reason = "too_large"; return OTOutcome.Rejected; }
            // a file the room cannot read as text (binary, not UTF-8) is never edited — an op on it would overwrite it
            string full = FullPathOf(rel);
            if (full == null || (!_otDocs.ContainsKey(rel) && !_contents.ContainsKey(rel) && File.Exists(full) && ReadTextFile(full) == null)) { reason = "invalid"; return OTOutcome.Rejected; }
            HostFlushLiveEditor(rel);
            var doc = HostDoc(rel);
            string previous = doc.Content;
            int previousRevision = doc.Revision;
            OTServerDocument.ReceiveError err;
            commit = doc.Receive(op, baseRevision, authorId, opId, out err);
            if (commit == null) { reason = err == OTServerDocument.ReceiveError.StaleBase ? "stale" : "invalid"; return OTOutcome.Rejected; }
            if (commit.Revision <= previousRevision) return OTOutcome.Duplicate;
            HostPublishCommit(rel, doc, commit, previous, authorName, authorColor, true, true, false);
            return OTOutcome.Committed;
        }

        void HostPublishCommit(string rel, OTServerDocument doc, OTServerDocument.Commit commit, string previous, string authorName, string authorColor, bool writeToDisk, bool updateEditor, bool legacyEchoToAuthor)
        {
            string content = doc.Content;
            _contents[rel] = content;
            _revisions[rel] = commit.Revision;
            RecordSnapshot(rel, commit.Revision, content);
            if (writeToDisk) WriteRelative(rel, content);
            if (updateEditor) PushOpToEditor(rel, commit.Operation, previous, content);
            else _lastSynced[rel] = content;

            string opMsg = Json(HostCommitPayload(rel, commit, authorName, authorColor));
            string legacyMsg = Json(FileBufferMessage(rel, content, commit.Revision, commit.AuthorId, authorName, authorColor));
            foreach (var client in Server.Clients)
            {
                // the author receives its own commit too: that is its acknowledgement
                if (client.SupportsOT) client.SendText(opMsg);
                else if (legacyEchoToAuthor || client.UserId != commit.AuthorId) client.SendText(legacyMsg);
            }
            string key = commit.AuthorId + "|" + rel;
            DateTime last;
            if (commit.AuthorId != LocalUserId && (!_lastEditActivity.TryGetValue(key, out last) || (DateTime.UtcNow - last).TotalSeconds > 20))
            {
                _lastEditActivity[key] = DateTime.UtcNow;
                RecordActivity(authorName, authorColor, "edited", rel);
            }
            if (!_sharedFiles.Any(f => f.RelativePath == rel)) { IndexLocalWorkspaceFiles(true); _ide.RefreshTree(); }
        }

        Dictionary<string, object> HostCommitPayload(string rel, OTServerDocument.Commit commit, string authorName = null, string authorColor = null)
        {
            var p = Find(commit.AuthorId);
            var payload = new Dictionary<string, object>
            {
                { "type", "op" }, { "path", rel }, { "revision", commit.Revision }, { "op", commit.Operation.ToJson() }, { "authorId", commit.AuthorId },
                { "authorName", authorName ?? (p != null ? p.DisplayName : commit.AuthorId == LocalUserId ? LocalDisplayName : "Collaborator") },
                { "authorColor", authorColor ?? (p != null ? p.Color : commit.AuthorId == LocalUserId ? LocalColor : "#3B82F6") }
            };
            if (commit.OpId != null) payload["opId"] = commit.OpId;
            OTServerDocument doc;
            if (_otDocs.TryGetValue(rel, out doc) && commit.Revision == doc.Revision) payload["length"] = doc.Content.Length;
            return payload;
        }

        /// <summary>An error reply that doubles as a snapshot, so the client reloads the file without another round trip.</summary>
        Dictionary<string, object> HostOTErrorPayload(string rel, string opId, string reason)
        {
            var payload = new Dictionary<string, object> { { "type", "opError" }, { "ok", false }, { "path", rel }, { "reason", reason } };
            if (opId != null) payload["opId"] = opId;
            if (rel.Length > 0)
            {
                var doc = HostDoc(rel);
                payload["revision"] = doc.Revision; payload["content"] = doc.Content; payload["resync"] = true;
            }
            return payload;
        }

        /// <summary>WS "op" from a client.</summary>
        void HostHandleOpMessage(CollabWsClient client, Dictionary<string, object> msg, string uid)
        {
            string rel = NormalizeRelativePath(S(msg, "path") ?? ""), opId = S(msg, "opId");
            int? baseRev = I(msg, "baseRevision");
            TextOperation op = null;
            try { op = TextOperation.FromJson(msg.ContainsKey("op") ? msg["op"] : null); } catch (OTException) { op = null; }
            if (rel.Length == 0 || uid.Length == 0 || !baseRev.HasValue || op == null) { client.SendText(Json(HostOTErrorPayload(rel, opId, "invalid"))); return; }
            var p = Find(uid);
            string name = S(msg, "displayName") ?? (p != null ? p.DisplayName : "Collaborator"), color = p != null ? p.Color : (S(msg, "color") ?? "#3B82F6");
            OTServerDocument.Commit commit; string reason;
            switch (HostReceiveOperation(rel, op, baseRev.Value, uid, name, color, opId, out commit, out reason))
            {
                case OTOutcome.Duplicate: client.SendText(Json(HostCommitPayload(rel, commit, name, color))); break;
                case OTOutcome.Rejected: client.SendText(Json(HostOTErrorPayload(rel, opId, reason))); break;
            }
        }

        /// <summary>WS "opSync {path, since}": the commits a client missed, as op messages (or a stale snapshot).</summary>
        void HostHandleOpSync(CollabWsClient client, Dictionary<string, object> msg)
        {
            string rel = NormalizeRelativePath(S(msg, "path") ?? "");
            if (rel.Length == 0) return;
            var commits = HostDoc(rel).OperationsSince(I(msg, "since") ?? 0);
            if (commits == null) { client.SendText(Json(HostOTErrorPayload(rel, null, "stale"))); return; }
            foreach (var c in commits) client.SendText(Json(HostCommitPayload(rel, c)));
        }

        /// <summary>POST /api/collab/op (relay clients and browsers without WebSocket): the reply carries every commit after
        /// the client's base revision — its own included — to be processed in order exactly as over WebSocket.</summary>
        Dictionary<string, object> HostHandleOpHttp(Dictionary<string, object> body)
        {
            body = body ?? new Dictionary<string, object>();
            string rel = NormalizeRelativePath(S(body, "path") ?? ""), uid = S(body, "userId") ?? "", opId = S(body, "opId");
            int? baseRev = I(body, "baseRevision");
            TextOperation op = null;
            try { op = TextOperation.FromJson(body.ContainsKey("op") ? body["op"] : null); } catch (OTException) { op = null; }
            if (rel.Length == 0 || uid.Length == 0 || !baseRev.HasValue || op == null) return HostOTErrorPayload(rel, opId, "invalid");
            var p = Find(uid);
            string name = S(body, "displayName") ?? "Collaborator", color = p != null ? p.Color : (S(body, "color") ?? "#3B82F6");
            OTServerDocument.Commit commit; string reason;
            if (HostReceiveOperation(rel, op, baseRev.Value, uid, name, color, opId, out commit, out reason) == OTOutcome.Rejected) return HostOTErrorPayload(rel, opId, reason);
            var commits = HostDoc(rel).OperationsSince(baseRev.Value) ?? new List<OTServerDocument.Commit>();
            return new Dictionary<string, object> { { "ok", true }, { "path", rel }, { "commits", commits.Select(c => HostCommitPayload(rel, c)).ToList() } };
        }

        /// <summary>GET /api/collab/ops?path=&amp;since=</summary>
        Dictionary<string, object> HostHandleOpsHttp(string relRaw, int since)
        {
            string rel = NormalizeRelativePath(relRaw ?? "");
            if (rel.Length == 0) return HostOTErrorPayload(rel, null, "invalid");
            var doc = HostDoc(rel);
            var commits = doc.OperationsSince(since);
            if (commits == null) return HostOTErrorPayload(rel, null, "stale");
            return new Dictionary<string, object> { { "ok", true }, { "path", rel }, { "revision", doc.Revision }, { "commits", commits.Select(c => HostCommitPayload(rel, c)).ToList() } };
        }

        // ── peer ──

        PeerOTFile PeerState(string rel)
        {
            PeerOTFile st;
            if (_peerOT.TryGetValue(rel, out st)) return st;
            // the same default as the gap check in PeerHandleCommit (the Mac uses 0 there and 1 here, and then drops revision 1)
            string content; _contents.TryGetValue(rel, out content);
            int known; _revisions.TryGetValue(rel, out known);
            st = new PeerOTFile { Client = new OTClient(known), Shadow = content ?? "" };
            _peerOT[rel] = st;
            return st;
        }

        /// <summary>peerSubmitLocalContent: the latest local text as an op (sent now, or composed while one is in flight).</summary>
        void PeerSubmitLocalContent(string rel, string content)
        {
            if (_peerResyncQueue.ContainsKey(rel)) { _contents[rel] = content; return; } // the reload will rebase onto the host copy
            var st = PeerState(rel);
            if (content == st.Shadow) return;
            var op = TextOperation.FromDiff(st.Shadow, content);
            st.Shadow = content;
            TextOperation outgoing;
            try { outgoing = st.Client.ApplyLocal(op); }
            catch (OTException) { PeerResync(rel); return; }
            if (outgoing != null)
            {
                st.OutstandingOpId = NewOperationId();
                PeerSendOperation(rel, outgoing, st.Client.Revision, st.OutstandingOpId);
            }
            _contents[rel] = content;
            _lastSynced[rel] = content;
            WriteRelative(rel, content);
        }

        void PeerFlushLiveEditor(string rel)
        {
            if (Pending(rel) > 0) return;
            string live = EditorLiveText(rel);
            PeerOTFile st;
            string known = _peerOT.TryGetValue(rel, out st) ? st.Shadow : null;
            if (known == null) _contents.TryGetValue(rel, out known);
            if (live != null && known != null && live != known) PeerSubmitLocalContent(rel, live);
        }

        void PeerSendOperation(string rel, TextOperation op, int baseRevision, string opId)
        {
            var payload = new Dictionary<string, object> { { "type", "op" }, { "path", rel }, { "baseRevision", baseRevision }, { "op", op.ToJson() }, { "opId", opId }, { "userId", LocalUserId }, { "displayName", LocalDisplayName }, { "color", LocalColor } };
            if (IsWebSocketRealtimeActive && _peerWs != null) { SendPeerFireAndForget(payload); return; }
            var s = Session;
            if (s == null) return;
            var _ = Task.Run(async () =>
            {
                var j = await PostJson(s.RemoteEndpoint + "/api/collab/op", payload, 8);
                if (j != null) { lock (_gate) PeerHandleOTReply(j); Fire(); }
            });
        }

        /// <summary>An HTTP reply (commits list) or an opError snapshot.</summary>
        void PeerHandleOTReply(Dictionary<string, object> json)
        {
            if (B(json, "ok") == false || S(json, "type") == "opError") { PeerHandleOTError(json); return; }
            var commits = Arr(json, "commits");
            if (commits != null) foreach (var c in commits.OfType<Dictionary<string, object>>()) PeerHandleCommit(c);
        }

        /// <summary>peerHandleCommit: one committed op from the host (WS broadcast, HTTP reply or catch-up).</summary>
        void PeerHandleCommit(Dictionary<string, object> msg)
        {
            string rel = NormalizeRelativePath(S(msg, "path") ?? "");
            int? revision = I(msg, "revision");
            if (rel.Length == 0 || !revision.HasValue) return;
            List<Dictionary<string, object>> queue;
            if (_peerResyncQueue.TryGetValue(rel, out queue)) { queue.Add(msg); return; }
            TextOperation op;
            try { op = TextOperation.FromJson(msg.ContainsKey("op") ? msg["op"] : null); } catch (OTException) { PeerResync(rel); return; }
            if (!_peerOT.ContainsKey(rel))
            {
                int known; _revisions.TryGetValue(rel, out known);
                if (revision.Value <= known) return;
                if (revision.Value != known + 1 || (!_contents.ContainsKey(rel) && op.BaseLength != 0)) { PeerResync(rel); return; }
            }
            PeerFlushLiveEditor(rel);
            if (_peerResyncQueue.TryGetValue(rel, out queue)) { queue.Add(msg); return; }
            var st = PeerState(rel);
            if (revision.Value <= st.Client.Revision) return;
            if (revision.Value != st.Client.Revision + 1) { PeerResync(rel); return; }

            string opId = S(msg, "opId");
            if (opId != null && opId == st.OutstandingOpId)
            {
                var next = st.Client.Acknowledge(revision.Value);
                if (next != null) { st.OutstandingOpId = NewOperationId(); PeerSendOperation(rel, next, revision.Value, st.OutstandingOpId); }
                else st.OutstandingOpId = null;
                _revisions[rel] = revision.Value; _peerBaseRevisions[rel] = revision.Value;
                RecordSnapshot(rel, revision.Value, st.Shadow);
                return;
            }
            try
            {
                var local = st.Client.ApplyRemote(op, revision.Value);
                string previous = st.Shadow;
                st.Shadow = local.Apply(previous);
                _revisions[rel] = revision.Value; _peerBaseRevisions[rel] = revision.Value;
                _contents[rel] = st.Shadow;
                RecordSnapshot(rel, revision.Value, st.Shadow);
                int? length = I(msg, "length");
                if (st.Client.IsSynchronized && length.HasValue && length.Value != st.Shadow.Length) { PeerResync(rel); return; }
                WriteRelative(rel, st.Shadow);
                PushOpToEditor(rel, local, previous, st.Shadow);
                if (!_sharedFiles.Any(f => f.RelativePath == rel)) _ide.RefreshTree();
            }
            catch (OTException) { PeerResync(rel); }
        }

        void PeerHandleOTError(Dictionary<string, object> msg)
        {
            string rel = NormalizeRelativePath(S(msg, "path") ?? "");
            if (rel.Length == 0) return;
            string content = S(msg, "content"); int? revision = I(msg, "revision");
            if (content != null && revision.HasValue) PeerApplySnapshot(rel, content, revision.Value);
            else PeerResync(rel);
        }

        /// <summary>peerResync: reload a file from the host after a gap or rejection; commits arriving meanwhile are queued.</summary>
        void PeerResync(string rel)
        {
            var s = Session;
            if (s == null || _peerResyncQueue.ContainsKey(rel)) return;
            _peerResyncQueue[rel] = new List<Dictionary<string, object>>();
            Trace("ot resync " + rel);
            var _ = Task.Run(async () =>
            {
                var j = await GetJson(s.RemoteEndpoint + "/api/collab/file?path=" + Uri.EscapeDataString(rel));
                lock (_gate)
                {
                    string content = S(j, "content");
                    if (content == null) { _peerResyncQueue.Remove(rel); _peerOT.Remove(rel); return; }
                    PeerApplySnapshot(rel, content, I(j, "revision") ?? 1);
                }
                Fire();
            });
        }

        void PeerApplySnapshot(string rel, string content, int revision)
        {
            List<Dictionary<string, object>> queued;
            if (!_peerResyncQueue.TryGetValue(rel, out queued)) queued = new List<Dictionary<string, object>>();
            _peerResyncQueue.Remove(rel);
            PeerOTFile lost;
            if (_peerOT.TryGetValue(rel, out lost) && !lost.Client.IsSynchronized) Trace("ot: reloaded " + rel + " from host; unsent local edits were replaced");
            _peerOT[rel] = new PeerOTFile { Client = new OTClient(revision), Shadow = content };
            string previous; _contents.TryGetValue(rel, out previous);
            _contents[rel] = content; _revisions[rel] = revision; _peerBaseRevisions[rel] = revision;
            RecordSnapshot(rel, revision, content);
            WriteRelative(rel, content);
            PushToEditor(rel, content);
            foreach (var m in queued.OrderBy(x => I(x, "revision") ?? 0)) PeerHandleCommit(m);
        }

        /// <summary>After (re)connecting over WebSocket: fetch commits missed while offline, then resend the in-flight op.</summary>
        void PeerCatchUpAfterConnect()
        {
            List<Dictionary<string, object>> msgs = new List<Dictionary<string, object>>();
            lock (_gate)
            {
                if (!PeerUsesOT) return;
                foreach (var kv in _peerOT)
                {
                    msgs.Add(new Dictionary<string, object> { { "type", "opSync" }, { "path", kv.Key }, { "since", kv.Value.Client.Revision } });
                    if (kv.Value.Client.Outstanding != null && kv.Value.OutstandingOpId != null)
                        msgs.Add(new Dictionary<string, object> { { "type", "op" }, { "path", kv.Key }, { "baseRevision", kv.Value.Client.Revision }, { "op", kv.Value.Client.Outstanding.ToJson() }, { "opId", kv.Value.OutstandingOpId }, { "userId", LocalUserId }, { "displayName", LocalDisplayName }, { "color", LocalColor } });
                }
            }
            foreach (var m in msgs) SendPeerFireAndForget(m);
        }

        /// <summary>Without WebSocket (cloud relay): poll commits for the files we track (~700 ms).</summary>
        async Task PeerPollOperations(string endpoint)
        {
            List<Tuple<string, int>> files;
            lock (_gate)
            {
                if (!PeerUsesOT || IsWebSocketRealtimeActive) return;
                files = _peerOT.Where(kv => !_peerResyncQueue.ContainsKey(kv.Key)).Select(kv => Tuple.Create(kv.Key, kv.Value.Client.Revision)).ToList();
            }
            foreach (var f in files)
            {
                var j = await GetJson(endpoint + "/api/collab/ops?path=" + Uri.EscapeDataString(f.Item1) + "&since=" + f.Item2);
                if (j != null) lock (_gate) PeerHandleOTReply(j);
            }
        }

        /// <summary>POST with the room credential header; null on failure.</summary>
        async Task<Dictionary<string, object>> PostJson(string url, Dictionary<string, object> body, int timeoutSeconds)
        {
            try
            {
                using (var req = new HttpRequestMessage(HttpMethod.Post, url) { Content = new StringContent(Json(body), Encoding.UTF8, "application/json") })
                using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds)))
                {
                    AddRoomCredential(req);
                    using (var resp = await Http.SendAsync(req, cts.Token)) return Parse(await resp.Content.ReadAsStringAsync());
                }
            }
            catch (Exception ex) { if (!(ex is HttpRequestException || ex is TaskCanceledException)) throw; return null; }
        }

        void AddRoomCredential(HttpRequestMessage req)
        {
            var s = Session;
            string code = s != null ? s.ShareCode : _joiningCode;
            if (!string.IsNullOrEmpty(code)) req.Headers.TryAddWithoutValidation("X-Collab-Code", code);
        }
    }
}
