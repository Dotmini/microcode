// The "MicroCode AI" teammate (CollaborationService.swift: aiTeammate*, notifyAIAgentTurnState / notifyAIAgentActivity,
// handleCollabChatAIMentionIfApplicable; AgentToolBox broadcastCollabAgentPreTool / PostTool; AgentService isLoading hooks).
//
// On the host the workspace agent appears as one participant with its own cursor, which follows the files the agent reads and
// edits; its file edits go to the room as fileBuffer messages authored by the AI; and any collaborator can ask it for work
// with "@ai …" in the session chat — the request runs in the host's agent chat under the host's tool-approval mode, and the
// reply is posted back to the chat. Differences from the Mac, on purpose:
//   • a PEER's own agent shows on that peer's row (isAIActive / aiStatusText) and its edits travel as that peer's edits —
//     the Mac sends them as "ai-agent-teammate" too, which makes two agents fight over one row on the host;
//   • the reply posted for an @ai request is that request's own reply (the Mac takes "the last assistant message");
//   • a request that cannot run (no model, previous run failed) gets an explicit chat answer instead of silence.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;

namespace MicroCode.Views
{
    public partial class CollabService
    {
        public const string AITeammateUserId = "ai-agent-teammate", AITeammateDisplayName = "MicroCode AI", AITeammateColor = "#94A3B8", AITeammateRole = "AI Agent";
        const string AIReady = "Ready in Collab";
        const int AIReplyLimit = 700;

        bool _aiEnabled = true; // not persisted: on for every launch, like the Mac
        CollabCursor _aiCursor;
        CollabMouse _aiMouse;
        string _aiStatus = AIReady;
        bool _aiWorking;
        Timer _aiTypingTimer;
        // this machine's own agent (AgentService.isLoading / agentPhase), shown on our own participant row
        volatile bool _agentRunActive;
        string _agentPhaseText = "Ready";
        bool _agentEventsAttached;

        public bool IsAITeammateEnabled { get { return _aiEnabled; } }

        public static bool IsAIParticipant(CollabParticipant p) { return p != null && (p.UserId == AITeammateUserId || p.Role == AITeammateRole); }

        public void AttachAgentEvents()
        {
            if (_agentEventsAttached) return;
            _agentEventsAttached = true;
            AgentRunner.RunStateChanged += OnAgentRunState;
            AgentRunner.ToolStarting += OnAgentToolStarting;
            AgentRunner.ToolFinished += OnAgentToolFinished;
        }

        public void DetachAgentEvents()
        {
            if (!_agentEventsAttached) return;
            _agentEventsAttached = false;
            AgentRunner.RunStateChanged -= OnAgentRunState;
            AgentRunner.ToolStarting -= OnAgentToolStarting;
            AgentRunner.ToolFinished -= OnAgentToolFinished;
        }

        bool Live { get { return Session != null && Status == CollabStatus.Connected; } }

        /// <summary>Our own row: cursor, task title, and whether our agent is working (the Mac sends isLoading + phase).</summary>
        void UpsertSelf()
        {
            if (Session == null) return;
            Upsert(LocalUserId, LocalDisplayName, Session.IsHostingLocally ? "Host" : LocalRole, LocalColor, CurrentLocalCursor(), _localMouse, SelectedTaskTitle ?? "", _agentRunActive, _agentPhaseText);
        }

        void ResetAITeammate()
        {
            if (_aiTypingTimer != null) { _aiTypingTimer.Dispose(); _aiTypingTimer = null; }
            _aiCursor = null; _aiMouse = null; _aiWorking = false; _aiStatus = AIReady;
        }

        /// <summary>ensureAITeammateInParticipants (host only; peers get the row from the host's participant list).</summary>
        void EnsureAITeammate()
        {
            if (Session == null || !Session.IsHostingLocally || !_aiEnabled) return;
            if (_aiCursor == null)
            {
                var cur = CurrentLocalCursor();
                if (cur != null && cur.FilePath.Length > 0) _aiCursor = cur.Clone();
                else if (_sharedFiles.Count > 0) _aiCursor = new CollabCursor { FilePath = _sharedFiles[0].RelativePath, Line = 1, Column = 1 };
            }
            Upsert(AITeammateUserId, AITeammateDisplayName, AITeammateRole, AITeammateColor, _aiCursor, _aiMouse, SelectedTaskTitle ?? "", _aiWorking || _agentRunActive, _aiStatus);
        }

        /// <summary>setAITeammateEnabled (the participants card's "Agent · ON / OFF").</summary>
        public void SetAITeammateEnabled(bool enabled)
        {
            lock (_gate)
            {
                _aiEnabled = enabled;
                if (Session != null)
                {
                    if (enabled) EnsureAITeammate();
                    else
                    {
                        _participants.RemoveAll(p => p.UserId == AITeammateUserId);
                        if (FollowingUserId == AITeammateUserId) FollowingUserId = null;
                        RebuildLocks();
                    }
                    if (Session.IsHostingLocally) BroadcastParticipants();
                }
            }
            Fire();
        }

        // ── this machine's agent → presence ──

        void OnAgentRunState(bool active)
        {
            _agentRunActive = active;
            _agentPhaseText = active ? "Thinking & executing in workspace…" : "Ready";
            NotifyAIAgentTurnState(active, active ? "Thinking & executing in workspace…" : AIReady);
        }

        /// <summary>notifyAIAgentTurnState: the agent started or finished a turn.</summary>
        public void NotifyAIAgentTurnState(bool isActive, string statusText)
        {
            if (!Live) return;
            lock (_gate)
            {
                UpsertSelf();
                if (Session.IsHostingLocally && _aiEnabled)
                {
                    _aiWorking = isActive;
                    if (!string.IsNullOrEmpty(statusText)) _aiStatus = statusText;
                    else if (!isActive) _aiStatus = AIReady;
                    if (!isActive && _aiCursor != null) _aiCursor.IsTyping = false;
                    EnsureAITeammate();
                }
                if (Session.IsHostingLocally) BroadcastParticipants();
            }
            Fire();
        }

        static readonly HashSet<string> EditTools = new HashSet<string> { "file_write", "replace_in_file", "patch_file", "multi_replace_in_file", "apply_patch" };
        static readonly Regex ReadOnlyShell = new Regex(@"^\s*(git\s+(status|log|diff|show|branch|remote)\b|dir\b|ls\b|type\b|cat\b|echo\b|findstr\b|where\b|whoami\b|ver\b|tree\b|more\b|head\b|tail\b|pwd\b|cd\s*$)", RegexOptions.IgnoreCase);

        static string Arg(Dictionary<string, object> a, string k) { object v; return a != null && a.TryGetValue(k, out v) && v != null ? Convert.ToString(v, CultureInfo.InvariantCulture) : null; }
        static int? IntArg(Dictionary<string, object> a, string k)
        {
            object v; if (a == null || !a.TryGetValue(k, out v) || v == null) return null;
            int n; return int.TryParse(Convert.ToString(v, CultureInfo.InvariantCulture), NumberStyles.Integer, CultureInfo.InvariantCulture, out n) ? (int?)n : null;
        }
        static string Short(string path) { return string.IsNullOrEmpty(path) ? "workspace" : path.Replace('\\', '/').Split('/').Last(); }
        static string Prefix(string s, int n) { s = s ?? ""; return s.Length > n ? s.Substring(0, n) : s; }

        /// <summary>broadcastCollabAgentPreTool: where the agent is about to look or write.</summary>
        void OnAgentToolStarting(ToolStep step, Dictionary<string, object> args)
        {
            if (!Live) return;
            string name = step.Name, path = Arg(args, "path");
            if (name == "file_read")
            {
                if (string.IsNullOrEmpty(path)) return;
                int start = Math.Max(1, IntArg(args, "start_line") ?? 1);
                NotifyAIAgentActivity(path, start, 1, IntArg(args, "end_line"), false, "Reading " + Short(path) + ":" + start, null);
            }
            else if (name == "multi_file_read")
            {
                object pv; args.TryGetValue("paths", out pv);
                var paths = pv is string ? ((string)pv).Split(',').Select(x => x.Trim()).Where(x => x.Length > 0).ToList()
                    : pv is System.Collections.IEnumerable ? ((System.Collections.IEnumerable)pv).Cast<object>().Select(o => Convert.ToString(o, CultureInfo.InvariantCulture)).Where(x => !string.IsNullOrEmpty(x)).ToList() : new List<string>();
                if (paths.Count == 0) return;
                NotifyAIAgentActivity(paths[0], 1, 1, 30, false, "Reading " + Short(paths[0]) + (paths.Count > 1 ? " (+" + (paths.Count - 1) + ")" : ""), null);
            }
            else if (EditTools.Contains(name))
            {
                var r = LineRange(args, path, false);
                NotifyAIAgentActivity(string.IsNullOrEmpty(path) ? null : path, r.Item1, 1, r.Item2, true, "Editing " + Short(path) + ":" + r.Item1, null);
            }
            else if (name == "grep_search" || name == "find_symbol" || name == "codebase_search" || name == "file_search")
            {
                string q = Arg(args, "query") ?? Arg(args, "pattern") ?? Arg(args, "symbol") ?? "";
                NotifyAIAgentActivity(null, 1, 1, null, false, "Searching '" + Prefix(q, 22) + "'", null);
            }
            else if (name == "shell")
            {
                string cmd = Arg(args, "command") ?? "";
                NotifyAIAgentActivity(null, 1, 1, null, !ReadOnlyShell.IsMatch(cmd), "Running " + Prefix(cmd, 24), null);
            }
        }

        /// <summary>broadcastCollabAgentPostTool: a finished edit goes to the room with the file's new text. Renames and new
        /// folders go as file-system events (the Mac leaves those to the next scan; a Windows peer has no scan).</summary>
        void OnAgentToolFinished(ToolStep step, Dictionary<string, object> args)
        {
            if (!Live || !step.Ok) return;
            if (step.Name == "rename_file" && !string.IsNullOrEmpty(step.Path))
            {
                string from = Arg(args, "path") ?? Arg(args, "old_path") ?? Arg(args, "from");
                string root = SharedRoot ?? _ide.WorkspaceFolder;
                if (from != null && root != null) NotifyLocalFileSystemEvent("rename", Path.IsPathRooted(from) ? from : Path.Combine(root, from.Replace('/', '\\')), step.Path);
                return;
            }
            if (step.Name == "create_directory")
            {
                string dir = Arg(args, "path");
                string root = SharedRoot ?? _ide.WorkspaceFolder;
                if (dir != null && root != null) NotifyLocalFileSystemEvent("mkdir", Path.IsPathRooted(dir) ? dir : Path.Combine(root, dir.Replace('/', '\\')));
                return;
            }
            if (!EditTools.Contains(step.Name)) return;
            var targets = step.Children != null && step.Children.Count > 0 ? step.Children.Where(c => c.Ok && !string.IsNullOrEmpty(c.Path)).Select(c => c.Path).ToList() : new List<string> { step.Path };
            foreach (var p in targets.Where(x => !string.IsNullOrEmpty(x)).Distinct())
            {
                string full = Path.IsPathRooted(p) ? p : Path.Combine(SharedRoot ?? _ide.WorkspaceFolder ?? "", p.Replace('/', '\\'));
                string text = ReadTextFile(full);
                if (text == null) continue;
                var r = LineRange(args, full, true);
                NotifyAIAgentActivity(full, r.Item1, 1, r.Item2, true, "Updated " + Short(full) + ":" + r.Item1, text);
            }
        }

        /// <summary>computeCollabLineRange: the lines an edit touches, from start_line or from where its snippet sits in the file.</summary>
        static Tuple<int, int> LineRange(Dictionary<string, object> args, string path, bool useReplacement)
        {
            int? s = IntArg(args, "start_line");
            if (s.HasValue) { int a = Math.Max(1, s.Value); return Tuple.Create(a, Math.Max(a, IntArg(args, "end_line") ?? a)); }
            string text = null;
            if (!string.IsNullOrEmpty(path)) { try { if (File.Exists(path)) text = File.ReadAllText(path).Replace("\r\n", "\n"); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
            if (text == null)
            {
                string content = Arg(args, "content");
                return content != null ? Tuple.Create(1, Math.Max(1, Math.Min(60, content.Split('\n').Length))) : Tuple.Create(1, 1);
            }
            string[] newKeys = { "new_text", "replace", "replacement", "new_string" }, oldKeys = { "old_text", "search", "target", "old_string" };
            Func<Dictionary<string, object>, string[], string> pick = (d, keys) => keys.Select(k => Arg(d, k)).FirstOrDefault(v => !string.IsNullOrEmpty(v));
            string snippet = useReplacement ? pick(args, newKeys) : null;
            if (string.IsNullOrEmpty(snippet)) snippet = pick(args, oldKeys);
            if (string.IsNullOrEmpty(snippet))
            {
                foreach (var listKey in new[] { "edits", "replacements" })
                {
                    object lv; if (args == null || !args.TryGetValue(listKey, out lv)) continue;
                    var first = (lv as System.Collections.IEnumerable) != null && !(lv is string) ? ((System.Collections.IEnumerable)lv).Cast<object>().OfType<Dictionary<string, object>>().FirstOrDefault() : null;
                    if (first == null) continue;
                    snippet = (useReplacement ? pick(first, newKeys) : null) ?? pick(first, oldKeys);
                    if (!string.IsNullOrEmpty(snippet)) break;
                }
            }
            int total = text.Split('\n').Length;
            if (string.IsNullOrEmpty(snippet)) return Tuple.Create(1, Math.Max(1, Math.Min(25, total)));
            snippet = snippet.Replace("\r\n", "\n");
            int at = text.IndexOf(snippet, StringComparison.Ordinal);
            if (at < 0) return Tuple.Create(1, 1);
            int line = text.Substring(0, at).Count(c => c == '\n') + 1;
            return Tuple.Create(line, line + snippet.Split('\n').Length - 1);
        }

        /// <summary>notifyAIAgentActivity. Host: moves the AI teammate's cursor / mouse, broadcasts them, and for an edit
        /// broadcasts the new text as the AI's fileBuffer. Peer: our row shows the activity and the edit goes to the host as ours.</summary>
        public void NotifyAIAgentActivity(string filePath, int line, int column, int? endLine, bool isEditing, string statusText, string updatedContent)
        {
            if (!Live) return;
            var s = Session;
            if (!s.IsHostingLocally)
            {
                lock (_gate) { if (!string.IsNullOrEmpty(statusText)) _agentPhaseText = statusText; UpsertSelf(); }
                if (updatedContent != null && filePath != null && IsInsideShared(filePath)) NotifyLocalFileEdited(filePath, updatedContent);
                Fire();
                return;
            }
            if (!_aiEnabled) return;
            lock (_gate)
            {
                string rel = filePath != null ? NormalizeRelativePath(filePath) : "";
                if (rel.StartsWith(".microcode") || rel.StartsWith(".gemini")) rel = "";
                if (rel.Length == 0 && _aiCursor != null) rel = _aiCursor.FilePath;
                int safeLine = Math.Max(1, line), safeCol = Math.Max(1, column);
                int? safeEnd = endLine.HasValue ? Math.Max(safeLine, endLine.Value) : (int?)null;
                if (rel.Length > 0)
                {
                    _aiCursor = new CollabCursor { FilePath = rel, Line = safeLine, Column = safeCol, EndLine = safeEnd, EndColumn = safeEnd.HasValue ? 80 : (int?)null, IsTyping = isEditing };
                    double y = Math.Max(0.14, Math.Min(0.86, 0.16 + ((safeLine - 1) % 38) * 0.018));
                    double x = Math.Max(0.36, Math.Min(0.76, 0.42 + ((safeLine * 7) % 25) * 0.012));
                    _aiMouse = new CollabMouse { X = x, Y = y, Surface = "editor", ActiveFile = rel, ActiveLine = safeLine, IsPressing = isEditing };
                }
                _aiWorking = isEditing || _agentRunActive;
                if (!string.IsNullOrEmpty(statusText)) _aiStatus = statusText;
                if (isEditing) RestartAITypingTimer();
                EnsureAITeammate();
                if (_aiCursor != null)
                {
                    var c = _aiCursor;
                    Server.Broadcast(Json(new Dictionary<string, object> { { "type", "cursor" }, { "userId", AITeammateUserId }, { "displayName", AITeammateDisplayName }, { "role", AITeammateRole }, { "color", AITeammateColor }, { "filePath", c.FilePath }, { "line", c.Line }, { "column", c.Column }, { "endLine", c.EndLine ?? c.Line }, { "endColumn", c.EndColumn ?? c.Column }, { "isTyping", c.IsTyping ?? false }, { "isAIActive", _aiWorking }, { "aiStatusText", _aiStatus } }), null);
                }
                if (_aiMouse != null)
                {
                    var m = _aiMouse;
                    Server.Broadcast(Json(new Dictionary<string, object> { { "type", "mouse" }, { "userId", AITeammateUserId }, { "displayName", AITeammateDisplayName }, { "role", AITeammateRole }, { "color", AITeammateColor }, { "x", m.X }, { "y", m.Y }, { "surface", m.Surface }, { "activeFile", m.ActiveFile ?? "" }, { "activeLine", m.ActiveLine ?? 0 }, { "isPressing", m.IsPressing } }), null);
                }
                if (updatedContent != null && rel.Length > 0 && filePath != null && IsInsideShared(filePath))
                {
                    string text = updatedContent.Replace("\r\n", "\n");
                    string prev;
                    if (!_contents.TryGetValue(rel, out prev) || prev != text)
                    {
                        try { string full = FullPathOf(rel); if (full != null && File.Exists(full)) _diskMod[rel] = File.GetLastWriteTimeUtc(full); } catch (IOException) { } catch (UnauthorizedAccessException) { }
                        RecordActivity(AITeammateDisplayName, AITeammateColor, "AI edited", rel + ":" + safeLine);
                        HostCommitContent(rel, text, AITeammateUserId, AITeammateDisplayName, AITeammateColor, false, true, true, false);
                    }
                }
                BroadcastParticipants();
                ApplyFollowIfNeeded();
            }
            Fire();
        }

        void RestartAITypingTimer()
        {
            if (_aiTypingTimer != null) _aiTypingTimer.Dispose();
            _aiTypingTimer = new Timer(_ =>
            {
                bool changed = false;
                lock (_gate)
                {
                    if (Session == null || !Session.IsHostingLocally || _aiCursor == null || _aiCursor.IsTyping != true) return;
                    _aiCursor.IsTyping = false;
                    EnsureAITeammate();
                    var c = _aiCursor;
                    Server.Broadcast(Json(new Dictionary<string, object> { { "type", "cursor" }, { "userId", AITeammateUserId }, { "displayName", AITeammateDisplayName }, { "role", AITeammateRole }, { "color", AITeammateColor }, { "filePath", c.FilePath }, { "line", c.Line }, { "column", c.Column }, { "endLine", c.EndLine ?? c.Line }, { "endColumn", c.EndColumn ?? c.Column }, { "isTyping", false }, { "isAIActive", _aiWorking }, { "aiStatusText", _aiStatus } }), null);
                    changed = true;
                }
                if (changed) Fire();
            }, null, 1800, Timeout.Infinite);
        }

        // ── @ai in the session chat ──

        /// <summary>The prompt of an "@ai …" / "@agent …" / "/ai …" message, or null when the message is not for the AI.</summary>
        public static string ExtractAIPrompt(string message)
        {
            string t = (message ?? "").Trim(), lower = t.ToLowerInvariant();
            bool triggered = lower.StartsWith("@ai") || lower.StartsWith("@agent") || lower.StartsWith("/ai") || lower.Contains("@ai ") || lower.Contains("@agent ");
            if (!triggered) return null;
            string prompt = t;
            foreach (var prefix in new[] { "@agent", "@ai", "/ai" })
                if (lower.StartsWith(prefix)) { prompt = t.Substring(prefix.Length); break; }
            return prompt.Trim(' ', ':', ',', '-', '\t', '\n', '\r');
        }

        /// <summary>handleCollabChatAIMentionIfApplicable (host only, called under the room lock after the message is posted).</summary>
        void HandleChatAIMention(string senderId, string senderName, string message)
        {
            var s = Session;
            if (s == null || !s.IsHostingLocally || Status != CollabStatus.Connected || !_aiEnabled || senderId == AITeammateUserId) return;
            string prompt = ExtractAIPrompt(message);
            if (string.IsNullOrEmpty(prompt)) return;
            string current = _ide.CurrentFilePath;
            string hint = current != null && IsInsideShared(current) ? " (Current file: " + NormalizeRelativePath(current) + ")" : "";
            string full = "[Collab Session Request from teammate '" + senderName + "'" + hint + "]: " + prompt;
            _aiWorking = true; _aiStatus = "Working on " + senderName + "'s request…";
            EnsureAITeammate();
            BroadcastParticipants();
            RecordActivity(AITeammateDisplayName, AITeammateColor, "started task for " + senderName, Prefix(prompt, 40));
            string code = s.ShareCode;
            _ide.RunAgentPrompt(full, (reply, error) =>
            {
                string text = (reply ?? "").Trim();
                if (text.Length == 0 && !string.IsNullOrEmpty(error)) text = "I couldn't run this request: " + error.Trim();
                if (text.Length > AIReplyLimit) text = text.Substring(0, AIReplyLimit) + "…";
                lock (_gate)
                {
                    if (Session == null || Session.ShareCode != code) return;
                    if (text.Length > 0) AddChat(AITeammateUserId, AITeammateDisplayName, AITeammateColor, text, null);
                }
                NotifyAIAgentTurnState(false, AIReady);
            });
        }
    }
}
