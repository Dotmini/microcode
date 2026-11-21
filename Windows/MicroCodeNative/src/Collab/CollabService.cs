// Port of CollaborationService.swift (Team Collaboration): one instance is either the HOST of a room (embedded HTTP +
// WebSocket server on 8490-8515, workspace index, revisioned file buffers with 3-way merge, chat, activity, presence) or a
// PEER (join by room code / LAN token / invite link, mirrored workspace, WebSocket realtime with 1.2 s HTTP sync as backup).
// The wire protocol is the Mac's, so Windows and Mac hosts/peers and the browser portal can share one room. Online mode
// registers the host with the Dotmini relay (wss://cloudai.dotmini.net/api/v2/mobile-relay/uplink).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using MicroCode.Core;

namespace MicroCode.Views
{
    // ── models (CollaborationSession & friends) ─────────────────────────────

    public class CollabCursor
    {
        public string FilePath = ""; public int Line = 1, Column = 1; public int? EndLine, EndColumn; public bool? IsTyping;
        public CollabCursor Clone() { return (CollabCursor)MemberwiseClone(); }
    }

    public class CollabMouse
    {
        public double X = 0.5, Y = 0.5; public string Surface = "editor", ActiveFile; public int? ActiveLine; public bool IsPressing; public DateTime UpdatedAt = DateTime.UtcNow;
    }

    public class CollabParticipant
    {
        public string Id, UserId, DisplayName, Role = "Editor", Color, ActiveTaskTitle, AiStatusText;
        public CollabCursor Cursor; public CollabMouse Mouse;
        public bool IsAIActive, IsOnline = true;
        public DateTime JoinedAt = DateTime.UtcNow, LastSeenAt = DateTime.UtcNow;

        /// <summary>liveActivitySummary (Thai, as on the Mac).</summary>
        public string LiveActivitySummary
        {
            get
            {
                if (Cursor != null && Cursor.FilePath.Length > 0)
                {
                    string shortFile = Cursor.FilePath.Split('/').Last();
                    if (Cursor.IsTyping == true) return "กำลังแก้ " + shortFile + ":" + Cursor.Line;
                    if (Cursor.EndLine.HasValue && Cursor.EndColumn.HasValue && (Cursor.EndLine != Cursor.Line || Cursor.EndColumn != Cursor.Column)) return "เลือกโค้ด " + shortFile + ":" + Cursor.Line + "-" + Cursor.EndLine;
                    return shortFile + ":Ln " + Cursor.Line;
                }
                if (IsAIActive && !string.IsNullOrEmpty(AiStatusText)) return "AI: " + AiStatusText;
                if (Mouse != null)
                {
                    if (!string.IsNullOrEmpty(Mouse.ActiveFile)) return Mouse.ActiveFile.Split('/').Last();
                    return Mouse.Surface == "agent" ? "หน้า AI Agent" : "กำลังดู Workspace";
                }
                return "กำลังดู Workspace";
            }
        }
    }

    public class CollabSharedFile { public string RelativePath, Name, Language, ActiveEditorName, ActiveEditorColor; public bool IsOpenOnHost; }
    public class CollabChat { public string Id = Guid.NewGuid().ToString().ToUpperInvariant(), UserId, DisplayName, UserColor = "#3B82F6", Message; public DateTime Timestamp = DateTime.UtcNow; }
    public class CollabActivity { public string Id = Guid.NewGuid().ToString().ToUpperInvariant(), ActorName, ActorColor, Action, Target; public DateTime Timestamp = DateTime.UtcNow; }

    public class CollabSession
    {
        public string Id, ProjectId, WorkspaceName = "Workspace", WorkspaceLang = "code", HostUserId, HostDisplayName = "Host", ShareCode, RemoteEndpoint = "";
        public bool IsHostingLocally = true, IsActive = true;
        public DateTime CreatedAt = DateTime.UtcNow;
    }

    public class CollabOpenFile { public string FullPath, Name, Language, Content; }

    /// <summary>What the service needs from the IDE (AppState on the real app, an in-memory stand-in in tests).</summary>
    public interface ICollabIde
    {
        string WorkspaceFolder { get; }
        List<CollabOpenFile> OpenFiles();
        string CurrentFilePath { get; }
        /// <summary>A remote edit landed: refresh the open buffer of this file (if open) without marking it unsaved.</summary>
        void ApplyRemoteContent(string fullPath, string content);
        /// <summary>Peer joined: open the mirrored workspace and the host's active file.</summary>
        void MountWorkspace(string root, string activeFileFullPath);
        void OpenFile(string fullPath, int line);
        void RefreshTree();
        /// <summary>A collaborator renamed a file or folder: open buffers under the old path follow it.</summary>
        void PathMoved(string oldFullPath, string newFullPath);
        /// <summary>A teammate's @ai request: run it in the host's workspace agent and call done(reply, error) once, for this
        /// request, when its turn ends (on any thread).</summary>
        void RunAgentPrompt(string prompt, Action<string, string> done);
    }

    public enum CollabStatus { Disconnected, Connecting, Connected, Reconnecting, Error }

    public partial class CollabService
    {
        public static readonly string[] Palette = { "#64748B", "#5B8DEF", "#4E9F86", "#C28E5C", "#7C8EA6", "#8C7A6B", "#5F9EA0", "#94A3B8" };
        const string RoomAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        const int InlineFileLimit = 262144, InlineBudget = 12 * 1024 * 1024, MaxIndexedFiles = 800, MaxIndexedDirs = 600;
        static readonly HashSet<string> IgnoredDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".git", "node_modules", ".build", "target", "dist", "build", ".next", ".nuxt", ".cache", ".turbo", "pods", "deriveddata", ".codetuner-build", "__pycache__", ".venv", "venv", ".gradle", ".idea", "bin", "obj", ".vs" };
        static readonly HashSet<string> IgnoredFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".ds_store", "thumbs.db", "desktop.ini" };

        static CollabService _shared;
        /// <summary>The app's service, bound to AppState.</summary>
        public static CollabService Shared { get { if (_shared == null) { _shared = new CollabService(new AppCollabIde(), null); _shared.AttachAgentEvents(); } return _shared; } }
        public static bool HasShared { get { return _shared != null; } }

        readonly ICollabIde _ide;
        readonly object _gate = new object();
        readonly JavaScriptSerializer _js = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
        readonly string _dataDir;

        // published state
        public CollabSession Session;
        List<CollabParticipant> _participants = new List<CollabParticipant>();
        /// <summary>A copy taken under the service lock: network threads change the live list.</summary>
        public List<CollabParticipant> Participants { get { lock (_gate) return _participants.ToList(); } }
        List<CollabChat> _chat = new List<CollabChat>();
        /// <summary>A copy taken under the service lock: network threads change the live list.</summary>
        public List<CollabChat> Chat { get { lock (_gate) return _chat.ToList(); } }
        List<CollabActivity> _activity = new List<CollabActivity>();
        /// <summary>A copy taken under the service lock: network threads change the live list.</summary>
        public List<CollabActivity> Activity { get { lock (_gate) return _activity.ToList(); } }
        List<CollabSharedFile> _sharedFiles = new List<CollabSharedFile>();
        /// <summary>A copy taken under the service lock: network threads change the live list.</summary>
        public List<CollabSharedFile> SharedFiles { get { lock (_gate) return _sharedFiles.ToList(); } }
        List<string> _sharedDirs = new List<string>();
        /// <summary>A copy taken under the service lock: network threads change the live list.</summary>
        public List<string> SharedDirectories { get { lock (_gate) return _sharedDirs.ToList(); } }
        public CollabStatus Status = CollabStatus.Disconnected;
        public string StatusError;
        public bool IsWebSocketRealtimeActive;
        public string FollowingUserId;
        public string LocalUserId, LocalDisplayName, LocalRole, LocalColor;
        public string SharedRoot;
        public string SelectedLanAddress = "127.0.0.1";
        public List<string> LanAddresses = new List<string>();
        public bool OnlineMode;
        public string TunnelStatus = "idle", PublicTunnelUrl, TunnelProvider = "cloudai.dotmini.net", TunnelError;
        public bool IsOfficialRelayActive;
        public event Action Changed;

        readonly System.Collections.Concurrent.ConcurrentQueue<string> _trace = new System.Collections.Concurrent.ConcurrentQueue<string>();
        /// <summary>Connection diagnostics (last 200 transport events: socket up/down, sync results, presence sources).
        /// Never message bodies, file contents or room codes.</summary>
        public List<string> TraceLog { get { return _trace.ToList(); } }
        void Trace(string what)
        {
            _trace.Enqueue(DateTime.Now.ToString("HH:mm:ss.fff", CultureInfo.InvariantCulture) + " " + what);
            string drop; while (_trace.Count > 200 && _trace.TryDequeue(out drop)) { }
        }

        // file state
        readonly Dictionary<string, string> _contents = new Dictionary<string, string>(StringComparer.Ordinal);
        readonly Dictionary<string, int> _revisions = new Dictionary<string, int>(StringComparer.Ordinal);
        readonly Dictionary<string, SortedDictionary<int, string>> _snapshots = new Dictionary<string, SortedDictionary<int, string>>(StringComparer.Ordinal);
        readonly Dictionary<string, int> _peerBaseRevisions = new Dictionary<string, int>(StringComparer.Ordinal);
        readonly Dictionary<string, string> _lastSynced = new Dictionary<string, string>(StringComparer.Ordinal);
        readonly Dictionary<string, DateTime> _diskMod = new Dictionary<string, DateTime>(StringComparer.Ordinal);
        DateTime _lastDiskScan = DateTime.MinValue;
        volatile bool _applyingRemote;
        CollabCursor _localCursor;
        CollabMouse _localMouse;
        DateTime _lastCursorSent = DateTime.MinValue, _lastMouseSent = DateTime.MinValue;

        // transport
        public readonly CollabServer Server = new CollabServer();
        static readonly HttpClient Http = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        ClientWebSocket _peerWs;
        CancellationTokenSource _peerCts;
        readonly SemaphoreSlim _peerSend = new SemaphoreSlim(1, 1);
        Timer _hostTimer, _peerTimer, _typingTimer;
        int _peerSyncBusy;
        ClientWebSocket _relayWs;
        CancellationTokenSource _relayCts;
        Process _tunnelProcess;

        public CollabService(ICollabIde ide, string dataDir)
        {
            _ide = ide;
            _dataDir = dataDir ?? Defaults.Dir;
            LocalUserId = Defaults.Str("collabUserId", null);
            if (string.IsNullOrEmpty(LocalUserId)) { LocalUserId = "usr-" + Guid.NewGuid().ToString("N").Substring(0, 8); Defaults.Set("collabUserId", LocalUserId); }
            LocalColor = Defaults.Str("collabUserColor", null);
            if (!Palette.Contains(LocalColor)) { LocalColor = Palette[Math.Abs(LocalUserId.GetHashCode()) % Palette.Length]; Defaults.Set("collabUserColor", LocalColor); }
            LocalRole = Defaults.Str("collabUserRole", "Editor");
            LocalDisplayName = Defaults.Str("collabDisplayName", null);
            if (string.IsNullOrWhiteSpace(LocalDisplayName))
            {
                var s = DotminiAuth.Session;
                LocalDisplayName = s != null && !string.IsNullOrWhiteSpace(s.DisplayName) ? s.DisplayName : Environment.UserName;
            }
            RefreshNetworkAddresses();
            Integrations = new TeamIntegrations();
            Tasks = new TeamTaskStore(() => LocalDisplayName, Integrations);
            Tasks.LocalChange += BroadcastTeamTasksIfActive;
            Tasks.Changed += Fire;
        }

        // ── Team Tasks (TeamTaskService / TeamIntegrationService) ──

        /// <summary>The workspace's shared task board. In a room the host's list is the room's list (whole-list replace,
        /// as on the Mac).</summary>
        public readonly TeamTaskStore Tasks;
        public readonly TeamIntegrations Integrations;
        DateTime _tasksPushedAt = DateTime.MinValue;

        string SelectedTaskTitle { get { var t = Tasks.SelectedTask; return t != null ? t.Title : null; } }

        /// <summary>broadcastTeamTasksIfActive. A peer POSTs its whole list to /api/collab/sync (what a Mac host understands);
        /// a Windows host also pushes the list over WebSocket as {"type":"teamTasks"} so Windows peers update at once — Mac
        /// peers ignore the unknown type and keep polling.</summary>
        void BroadcastTeamTasksIfActive(List<TeamTask> tasks)
        {
            var s = Session;
            if (s == null) return;
            string json = TeamTaskJson.ArrayJson(tasks);
            if (s.IsHostingLocally)
            {
                Server.Broadcast(Json(new Dictionary<string, object> { { "type", "teamTasks" }, { "teamTasksJSON", json } }), null);
                return;
            }
            _tasksPushedAt = DateTime.UtcNow;
            var body = new Dictionary<string, object> { { "userId", LocalUserId }, { "displayName", LocalDisplayName }, { "role", LocalRole }, { "color", LocalColor }, { "teamTasksJSON", json } };
            var _ = Task.Run(async () =>
            {
                try
                {
                    using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(8)))
                    using (var resp = await Http.PostAsync(s.RemoteEndpoint + "/api/collab/sync", new StringContent(Json(body), Encoding.UTF8, "application/json"), cts.Token))
                        Trace("tasks pushed " + (int)resp.StatusCode);
                }
                catch (Exception ex) { if (!(ex is HttpRequestException || ex is TaskCanceledException)) throw; Trace("tasks push failed: " + ex.Message); }
            });
        }

        /// <summary>A list from the room (sync payload or the teamTasks WebSocket message). Swift decodes the array all-or-nothing:
        /// one invalid task drops the whole list, and so does this.</summary>
        void ApplyRoomTasks(string json, bool authoritative)
        {
            if (json == null) return;
            var list = TeamTaskJson.ParseArray(json);
            if (list == null) { Trace("tasks: invalid list ignored"); return; }
            // a poll answer that left the host before our own push landed must not undo it (the WS echo is authoritative)
            if (!authoritative && (DateTime.UtcNow - _tasksPushedAt).TotalMilliseconds < 1500) return;
            Tasks.ApplyRemoteTasks(list);
        }

        /// <summary>POST /api/collab/task (web portal and API clients): create / status / claim / decision, applied by the host
        /// exactly as the Mac does — the host is the actor, "claim" = hand off to the author + set In progress.</summary>
        void HandleTaskAction(Dictionary<string, object> body)
        {
            Integrations.SetTeamTasksEnabled(true);
            if (Tasks.WorkspacePath == null) Tasks.Load(SharedRoot ?? _ide.WorkspaceFolder);
            string action = S(body, "action") ?? "", taskId = S(body, "taskId");
            switch (action)
            {
                case "create":
                {
                    var t = Tasks.CreateTask(S(body, "title") ?? "", S(body, "objective") ?? "", S(body, "scope") ?? "");
                    if (t != null) RecordActivity(S(body, "author") ?? "Team", "#10B981", "created task", t.Title);
                    break;
                }
                case "status":
                {
                    string raw = S(body, "status");
                    if (taskId != null && TeamTaskStatusInfo.All.Any(x => TeamTaskStatusInfo.Raw(x) == raw)) Tasks.UpdateStatus(TeamTaskStatusInfo.Parse(raw), taskId);
                    break;
                }
                case "claim":
                {
                    string author = S(body, "author");
                    if (taskId != null && !string.IsNullOrEmpty(author)) { Tasks.Handoff(taskId, author); Tasks.UpdateStatus(TeamTaskStatus.Active, taskId); }
                    break;
                }
                case "decision":
                    if (taskId != null && S(body, "text") != null) Tasks.AddDecision(S(body, "text"), taskId);
                    break;
            }
        }

        /// <summary>For tests: a separate identity per instance (two collaborators in one process).</summary>
        public void SetIdentity(string userId, string name, string role, string color) { LocalUserId = userId; LocalDisplayName = name; LocalRole = role; LocalColor = color; }

        public void SetDisplayName(string name) { LocalDisplayName = name; Defaults.Set("collabDisplayName", name); UpdateSelfInParticipants(); Fire(); }
        public void SetRole(string role) { LocalRole = role; Defaults.Set("collabUserRole", role); UpdateSelfInParticipants(); Fire(); }

        void Fire() { var c = Changed; if (c != null) { try { c(); } catch (Exception ex) { Debug.WriteLine("collab changed: " + ex); } } }

        public ICollabIde Ide { get { return _ide; } }
        public bool IsActive { get { return Session != null && Status == CollabStatus.Connected; } }
        public bool IsHosting { get { return Session != null && Session.IsHostingLocally; } }

        // ── JSON helpers ──

        static string S(Dictionary<string, object> d, string k) { object v; return d != null && d.TryGetValue(k, out v) && v != null ? (v as string ?? Convert.ToString(v, CultureInfo.InvariantCulture)) : null; }
        static int? I(Dictionary<string, object> d, string k) { object v; if (d == null || !d.TryGetValue(k, out v) || v == null || v is string || v is bool) return null; try { return Convert.ToInt32(v, CultureInfo.InvariantCulture); } catch (OverflowException) { return null; } catch (InvalidCastException) { return null; } }
        static double? Dbl(Dictionary<string, object> d, string k) { object v; if (d == null || !d.TryGetValue(k, out v) || v == null || v is string || v is bool) return null; try { return Convert.ToDouble(v, CultureInfo.InvariantCulture); } catch (InvalidCastException) { return null; } }
        static bool? B(Dictionary<string, object> d, string k) { object v; return d != null && d.TryGetValue(k, out v) && v is bool ? (bool?)(bool)v : null; }
        static Dictionary<string, object> Obj(Dictionary<string, object> d, string k) { object v; return d != null && d.TryGetValue(k, out v) ? v as Dictionary<string, object> : null; }
        static List<object> Arr(Dictionary<string, object> d, string k)
        {
            object v; if (d == null || !d.TryGetValue(k, out v) || v == null) return null;
            var a = v as object[]; if (a != null) return a.ToList();
            var l = v as System.Collections.ArrayList; return l != null ? l.Cast<object>().ToList() : null;
        }
        Dictionary<string, object> Parse(string json)
        {
            try { return _js.DeserializeObject(json) as Dictionary<string, object>; }
            catch (ArgumentException) { return null; } catch (InvalidOperationException) { return null; }
        }
        string Json(object o) { return _js.Serialize(o); }
        static string Iso(DateTime t) { return t.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture); }
        static DateTime ParseIso(string s) { DateTime t; return s != null && DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out t) ? t : DateTime.UtcNow; }

        // ── network addresses ──

        public void RefreshNetworkAddresses()
        {
            var list = new List<string>();
            try
            {
                foreach (var ni in NetworkInterface.GetAllNetworkInterfaces().Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback)
                    .OrderByDescending(n => n.GetIPProperties().GatewayAddresses.Any(g => g.Address.AddressFamily == AddressFamily.InterNetwork && !g.Address.Equals(IPAddress.Any))))
                    foreach (var ua in ni.GetIPProperties().UnicastAddresses)
                        if (ua.Address.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(ua.Address) && !ua.Address.ToString().StartsWith("169.254.")) list.Add(ua.Address.ToString());
            }
            catch (NetworkInformationException ex) { Debug.WriteLine("collab nics: " + ex.Message); }
            LanAddresses = list.Distinct().ToList();
            if (!LanAddresses.Contains(SelectedLanAddress)) SelectedLanAddress = LanAddresses.FirstOrDefault() ?? "127.0.0.1";
        }

        // ── paths ──

        public static string SanitizeRelativePath(string raw)
        {
            string u = (raw ?? "").Replace('\\', '/').Trim();
            return string.Join("/", u.Split('/').Where(p => p.Length > 0 && p != "." && p != ".."));
        }

        /// <summary>normalizeRelativePath: absolute paths inside the shared root (or open workspace) become root-relative.</summary>
        public string NormalizeRelativePath(string raw)
        {
            string t = (raw ?? "").Trim();
            if (t.Length == 0) return "";
            bool absolute = t.StartsWith("/") || (t.Length > 2 && t[1] == ':' && (t[2] == '\\' || t[2] == '/'));
            if (absolute)
            {
                string full; try { full = Path.GetFullPath(t.Replace('/', '\\')); } catch (ArgumentException) { return Path.GetFileName(t); } catch (NotSupportedException) { return Path.GetFileName(t); }
                foreach (var root in new[] { SharedRoot, _ide.WorkspaceFolder })
                {
                    if (string.IsNullOrEmpty(root)) continue;
                    string r = Path.GetFullPath(root).TrimEnd('\\') + "\\";
                    if (full.StartsWith(r, StringComparison.OrdinalIgnoreCase)) return SanitizeRelativePath(full.Substring(r.Length));
                }
                return Path.GetFileName(full);
            }
            return SanitizeRelativePath(t);
        }

        string FullPathOf(string rel)
        {
            string root = SharedRoot ?? _ide.WorkspaceFolder;
            if (string.IsNullOrEmpty(root) || string.IsNullOrEmpty(rel)) return null;
            string r = Path.GetFullPath(root).TrimEnd('\\');
            string full = Path.GetFullPath(Path.Combine(r, rel.Replace('/', '\\')));
            return full.StartsWith(r + "\\", StringComparison.OrdinalIgnoreCase) ? full : null;
        }

        void RecordSnapshot(string rel, int rev, string content)
        {
            SortedDictionary<int, string> map;
            if (!_snapshots.TryGetValue(rel, out map)) { map = new SortedDictionary<int, string>(); _snapshots[rel] = map; }
            map[rev] = content;
            while (map.Count > 32) map.Remove(map.Keys.First());
        }

        string Snapshot(string rel, int rev) { SortedDictionary<int, string> map; string s; return _snapshots.TryGetValue(rel, out map) && map.TryGetValue(rev, out s) ? s : null; }

        int Rev(string rel) { int r; return _revisions.TryGetValue(rel, out r) ? r : 1; }

        /// <summary>Files whose latest room text could not be written yet (held open by an antivirus scan, an indexer or another
        /// editor): retried on every maintenance / sync tick until the disk matches the room again.</summary>
        readonly Dictionary<string, string> _pendingDisk = new Dictionary<string, string>(StringComparer.Ordinal);

        void WriteRelative(string rel, string content)
        {
            rel = SanitizeRelativePath(rel);
            string full = FullPathOf(rel);
            if (full == null) return;
            if (TryWrite(rel, full, content)) { _pendingDisk.Remove(rel); return; }
            _pendingDisk[rel] = content;
            Trace("write deferred (file busy): " + rel);
        }

        /// <summary>A few quick attempts (0 / 25 / 50 ms): a file opened without write sharing is usually released at once.</summary>
        bool TryWrite(string rel, string full, string content)
        {
            for (int attempt = 0; attempt < 3; attempt++)
            {
                if (attempt > 0) Thread.Sleep(attempt * 25);
                try
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(full));
                    // keep the file's own line endings on disk
                    bool crlf = File.Exists(full) && File.ReadAllText(full).Contains("\r\n");
                    File.WriteAllText(full, crlf ? content.Replace("\r\n", "\n").Replace("\n", "\r\n") : content, new UTF8Encoding(false));
                    _diskMod[rel] = File.GetLastWriteTimeUtc(full);
                    return true;
                }
                catch (IOException ex) { if (attempt == 2) Trace("write failed: " + rel + ": " + ex.Message); }
                catch (UnauthorizedAccessException ex) { Trace("write refused: " + rel + ": " + ex.Message); return false; }
            }
            return false;
        }

        /// <summary>Writes deferred room text that is still current (a newer write replaces the pending entry).</summary>
        void FlushPendingWrites()
        {
            foreach (var kv in _pendingDisk.ToList())
            {
                string cur;
                if (!_contents.TryGetValue(kv.Key, out cur) || cur != kv.Value) { _pendingDisk.Remove(kv.Key); continue; }
                string full = FullPathOf(kv.Key);
                if (full == null || TryWrite(kv.Key, full, kv.Value)) { _pendingDisk.Remove(kv.Key); if (full != null) Trace("deferred write done: " + kv.Key); }
            }
        }

        void PushToEditor(string rel, string content)
        {
            string full = FullPathOf(rel);
            if (full == null) return;
            _lastSynced[rel] = content;
            _applyingRemote = true;
            try { _ide.ApplyRemoteContent(full, content); }
            finally { _applyingRemote = false; }
        }

        void RecordActivity(string actor, string color, string action, string target)
        {
            _activity.Add(new CollabActivity { ActorName = actor, ActorColor = color, Action = action, Target = target });
            if (_activity.Count > 60) _activity.RemoveRange(0, _activity.Count - 60);
        }

        static string GenerateShareCode()
        {
            var bytes = new byte[6];
            using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(bytes);
            return new string(bytes.Select(b => RoomAlphabet[b % RoomAlphabet.Length]).ToArray());
        }

        // ── participants ──

        CollabParticipant Find(string uid) { return _participants.FirstOrDefault(p => p.UserId == uid); }

        void Upsert(string uid, string name, string role, string color, CollabCursor cursor, CollabMouse mouse = null, string taskTitle = null, bool? aiActive = null, string aiText = null)
        {
            var p = Find(uid);
            if (p == null) { p = new CollabParticipant { Id = uid, UserId = uid }; _participants.Add(p); }
            p.DisplayName = name; p.Role = role; p.Color = color;
            if (cursor != null) p.Cursor = cursor;
            if (mouse != null) p.Mouse = mouse;
            if (taskTitle != null) p.ActiveTaskTitle = taskTitle;
            if (aiActive.HasValue) p.IsAIActive = aiActive.Value;
            if (aiText != null) p.AiStatusText = aiText;
            p.IsOnline = true; p.LastSeenAt = DateTime.UtcNow;
            RebuildLocks();
        }

        void UpdateSelfInParticipants()
        {
            if (Session == null) return;
            lock (_gate) UpsertSelf();
        }

        CollabCursor CurrentLocalCursor()
        {
            string cur = _ide.CurrentFilePath;
            if (cur == null) return _localCursor;
            string rel = NormalizeRelativePath(cur);
            if (_localCursor != null && _localCursor.FilePath == rel) return _localCursor;
            return new CollabCursor { FilePath = rel, Line = 1, Column = 1 };
        }

        string AssignDistinctColor(string preferred, string uid)
        {
            var existing = Find(uid);
            if (existing != null) return existing.Color;
            var used = new HashSet<string>(_participants.Where(p => p.IsOnline && p.UserId != uid).Select(p => (p.Color ?? "").ToUpperInvariant()));
            string pref = (preferred ?? "").ToUpperInvariant();
            if (Palette.Any(c => c.ToUpperInvariant() == pref) && !used.Contains(pref)) return pref;
            foreach (var c in Palette) if (!used.Contains(c.ToUpperInvariant())) return c;
            return Palette[_participants.Count % Palette.Length];
        }

        void RebuildLocks()
        {
            var locks = new Dictionary<string, CollabParticipant>(StringComparer.Ordinal);
            foreach (var p in _participants.Where(x => x.IsOnline && x.UserId != LocalUserId && x.Cursor != null && x.Cursor.FilePath.Length > 0)) locks[NormalizeRelativePath(p.Cursor.FilePath)] = p;
            foreach (var p in _participants.Where(x => x.IsOnline && x.UserId == LocalUserId && x.Cursor != null && x.Cursor.FilePath.Length > 0)) { string r = NormalizeRelativePath(p.Cursor.FilePath); if (!locks.ContainsKey(r)) locks[r] = p; }
            foreach (var f in _sharedFiles)
            {
                CollabParticipant l;
                if (locks.TryGetValue(f.RelativePath, out l)) { f.ActiveEditorName = l.DisplayName; f.ActiveEditorColor = l.Color; }
                else { f.ActiveEditorName = null; f.ActiveEditorColor = null; }
            }
        }

        List<Dictionary<string, object>> SerializeParticipants()
        {
            return _participants.Select(p =>
            {
                var d = new Dictionary<string, object> { { "id", p.Id }, { "userId", p.UserId }, { "displayName", p.DisplayName }, { "role", p.Role }, { "color", p.Color }, { "isOnline", p.IsOnline }, { "isAIActive", p.IsAIActive }, { "aiStatusText", p.AiStatusText ?? "" }, { "activeTaskTitle", p.ActiveTaskTitle ?? "" } };
                if (p.Cursor != null) d["cursor"] = CursorDict(p.Cursor);
                if (p.Mouse != null && (DateTime.UtcNow - p.Mouse.UpdatedAt).TotalSeconds < 20) d["mouse"] = MouseDict(p.Mouse);
                return d;
            }).ToList();
        }

        static Dictionary<string, object> CursorDict(CollabCursor c)
        {
            return new Dictionary<string, object> { { "filePath", c.FilePath }, { "line", c.Line }, { "column", c.Column }, { "endLine", c.EndLine ?? c.Line }, { "endColumn", c.EndColumn ?? c.Column }, { "isTyping", c.IsTyping ?? false } };
        }

        static Dictionary<string, object> MouseDict(CollabMouse m)
        {
            return new Dictionary<string, object> { { "x", m.X }, { "y", m.Y }, { "surface", m.Surface }, { "activeFile", m.ActiveFile ?? "" }, { "activeLine", m.ActiveLine ?? 0 }, { "isPressing", m.IsPressing } };
        }

        CollabCursor ParseCursor(Dictionary<string, object> c)
        {
            if (c == null || S(c, "filePath") == null) return null;
            return new CollabCursor { FilePath = NormalizeRelativePath(S(c, "filePath")), Line = Math.Max(1, I(c, "line") ?? 1), Column = Math.Max(1, I(c, "column") ?? 1), EndLine = I(c, "endLine"), EndColumn = I(c, "endColumn"), IsTyping = B(c, "isTyping") };
        }

        CollabMouse ParseMouse(Dictionary<string, object> m)
        {
            if (m == null || !Dbl(m, "x").HasValue || !Dbl(m, "y").HasValue) return null;
            string af = S(m, "activeFile"); int? al = I(m, "activeLine");
            return new CollabMouse { X = Math.Max(0, Math.Min(1, Dbl(m, "x").Value)), Y = Math.Max(0, Math.Min(1, Dbl(m, "y").Value)), Surface = S(m, "surface") ?? "editor", ActiveFile = string.IsNullOrEmpty(af) ? null : NormalizeRelativePath(af), ActiveLine = al.HasValue && al.Value > 0 ? al : null, IsPressing = B(m, "isPressing") ?? false };
        }

        void ApplyParticipantsArray(List<object> arr)
        {
            var existing = _participants.ToDictionary(p => p.UserId, p => p);
            var list = new List<CollabParticipant>();
            foreach (var o in arr.OfType<Dictionary<string, object>>())
            {
                string uid = S(o, "userId") ?? Guid.NewGuid().ToString();
                string color = S(o, "color") ?? "#3B82F6";
                if (uid == LocalUserId && color.Length > 0) LocalColor = color;
                CollabParticipant prev; existing.TryGetValue(uid, out prev);
                var cur = ParseCursor(Obj(o, "cursor"));
                if (cur == null) cur = uid == LocalUserId ? (_localCursor ?? CurrentLocalCursor()) : (prev != null && IsWebSocketRealtimeActive ? prev.Cursor : null);
                CollabMouse mouse = null;
                if (uid == LocalUserId) mouse = _localMouse;
                else if (prev != null && prev.Mouse != null && IsWebSocketRealtimeActive && (DateTime.UtcNow - prev.Mouse.UpdatedAt).TotalSeconds < 3) mouse = prev.Mouse;
                else { mouse = ParseMouse(Obj(o, "mouse")); if (mouse != null && prev != null && prev.Mouse != null) mouse.UpdatedAt = prev.Mouse.UpdatedAt; }
                list.Add(new CollabParticipant { Id = uid, UserId = uid, DisplayName = S(o, "displayName") ?? "Collaborator", Role = S(o, "role") ?? "Editor", Color = color, IsOnline = B(o, "isOnline") ?? true, IsAIActive = B(o, "isAIActive") ?? false, AiStatusText = S(o, "aiStatusText"), ActiveTaskTitle = S(o, "activeTaskTitle"), Cursor = cur, Mouse = mouse, JoinedAt = prev != null ? prev.JoinedAt : DateTime.UtcNow });
            }
            _participants = list;
            RebuildLocks();
        }

        // ── host: create / index / payloads ──

        /// <summary>createSession: starts the embedded host on 8490-8515 and shares the open workspace.</summary>
        public CollabSession CreateSession()
        {
            RefreshNetworkAddresses();
            string code = GenerateShareCode();
            string ws = _ide.WorkspaceFolder;
            string wsName = ws != null ? Path.GetFileName(Path.GetFullPath(ws).TrimEnd('\\')) : "Workspace";
            Integrations.SetTeamTasksEnabled(true);
            Tasks.Load(ws);
            lock (_gate)
            {
                SharedRoot = ws != null ? Path.GetFullPath(ws).TrimEnd('\\') : null;
                Server.OnRequest = HandleHttp;
                Server.OnUpgrade = r => r.Path == "/ws/collab" && Session != null && QueryCode(r).Length > 0 && QueryCode(r) != Session.ShareCode ? CollabResponse.Text("403 Forbidden", "text/plain", "Invalid code") : (r.Path == "/ws/collab" ? null : CollabResponse.Text("404 Not Found", "application/json", "{\"error\":\"Not found\"}"));
                Server.OnWsOpen = c => c.SendText(Json(new Dictionary<string, object> { { "type", "welcome" }, { "shareCode", Session != null ? Session.ShareCode : "" }, { "workspaceName", Session != null ? Session.WorkspaceName : "Workspace" }, { "participants", WithGate(SerializeParticipants) } }));
                Server.OnWsText = HandleHostWsText;
                if (!Server.Start()) { Status = CollabStatus.Error; StatusError = "No free port in 8490-8515"; Fire(); return null; }
                Session = new CollabSession { Id = code, ShareCode = code, ProjectId = wsName, WorkspaceName = wsName, WorkspaceLang = DetectWorkspaceLang(ws), HostUserId = LocalUserId, HostDisplayName = LocalDisplayName, IsHostingLocally = true, RemoteEndpoint = "http://" + SelectedLanAddress + ":" + Server.Port };
                _participants = new List<CollabParticipant>();
                UpsertSelf(); EnsureAITeammate();
                _chat.Clear(); _activity.Clear();
                Status = CollabStatus.Connected; StatusError = null; IsWebSocketRealtimeActive = true;
                IndexLocalWorkspaceFiles(true);
                RecordActivity(LocalDisplayName, LocalColor, "started host session", wsName);
            }
            _hostTimer = new Timer(_ => HostMaintenance(), null, 1500, 1500);
            if (OnlineMode) StartOnlineTunnel();
            Fire();
            return Session;
        }

        T WithGate<T>(Func<T> f) { lock (_gate) return f(); }

        static string QueryCode(CollabRequest r) { string c; return r.Query.TryGetValue("code", out c) ? (c ?? "").Trim().ToUpperInvariant() : ""; }

        static string DetectWorkspaceLang(string ws)
        {
            if (string.IsNullOrEmpty(ws) || !Directory.Exists(ws)) return "code";
            var counts = new Dictionary<string, int>();
            try
            {
                foreach (var f in Directory.EnumerateFiles(ws, "*", SearchOption.TopDirectoryOnly).Concat(Directory.GetDirectories(ws).Where(d => !IgnoredDirs.Contains(Path.GetFileName(d)) && !Path.GetFileName(d).StartsWith(".")).Take(12).SelectMany(d => { try { return Directory.EnumerateFiles(d).Take(200).ToList(); } catch (Exception) { return new List<string>(); } })))
                {
                    string e = Path.GetExtension(f).TrimStart('.').ToLowerInvariant();
                    if (new[] { "swift", "py", "ts", "tsx", "js", "jsx", "rs", "go", "java", "kt", "cs", "cpp", "c", "rb", "php", "dart" }.Contains(e)) { int n; counts.TryGetValue(e, out n); counts[e] = n + 1; }
                }
            }
            catch (IOException) { } catch (UnauthorizedAccessException) { }
            return counts.Count == 0 ? "code" : counts.OrderByDescending(kv => kv.Value).First().Key;
        }

        /// <summary>indexLocalWorkspaceFiles (host only): open buffers become revisioned contents; the disk walk (≤8 levels,
        /// ≤800 files, skips 2 MB+, ignored folders, symlinks) finds new files and broadcasts external edits to closed files.</summary>
        public void IndexLocalWorkspaceFiles(bool forceDiskScan)
        {
            if (Session != null && !Session.IsHostingLocally) return;
            var open = _ide.OpenFiles();
            var openSet = new HashSet<string>(StringComparer.Ordinal);
            foreach (var f in open)
            {
                string rel = NormalizeRelativePath(f.FullPath);
                if (rel.Length == 0 || f.Content == null) continue;
                openSet.Add(rel);
                string prev; bool had = _contents.TryGetValue(rel, out prev);
                _contents[rel] = f.Content;
                int rev;
                if (_revisions.TryGetValue(rel, out rev))
                {
                    if (had && prev != f.Content) { _revisions[rel] = rev + 1; RecordSnapshot(rel, rev + 1, f.Content); }
                    else if (Snapshot(rel, rev) == null) RecordSnapshot(rel, rev, f.Content);
                }
                else { _revisions[rel] = 1; RecordSnapshot(rel, 1, f.Content); }
            }
            if (!forceDiskScan && _sharedFiles.Count > 0 && (DateTime.UtcNow - _lastDiskScan).TotalSeconds < 2.5)
            {
                foreach (var f in _sharedFiles) f.IsOpenOnHost = openSet.Contains(f.RelativePath);
                RebuildLocks();
                return;
            }
            _lastDiskScan = DateTime.UtcNow;
            var files = new List<CollabSharedFile>(); var dirs = new List<string>(); var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var f in open)
            {
                string rel = NormalizeRelativePath(f.FullPath);
                if (rel.Length == 0 || !seen.Add(rel)) continue;
                files.Add(new CollabSharedFile { RelativePath = rel, Name = f.Name, Language = f.Language ?? "code", IsOpenOnHost = true });
            }
            string root = SharedRoot ?? _ide.WorkspaceFolder;
            Action<string, string, int> scan = null;
            scan = (dir, prefix, depth) =>
            {
                if (depth > 8 || files.Count >= MaxIndexedFiles || dirs.Count >= MaxIndexedDirs) return;
                FileSystemInfo[] items;
                try { items = new DirectoryInfo(dir).GetFileSystemInfos(); } catch (IOException) { return; } catch (UnauthorizedAccessException) { return; }
                foreach (var it in items.OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase))
                {
                    if (IgnoredFiles.Contains(it.Name) || (it.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                    string rel = prefix.Length == 0 ? it.Name : prefix + "/" + it.Name;
                    if ((it.Attributes & FileAttributes.Directory) != 0)
                    {
                        if (IgnoredDirs.Contains(it.Name)) continue;
                        if (dirs.Count < MaxIndexedDirs) dirs.Add(rel);
                        scan(it.FullName, rel, depth + 1);
                        continue;
                    }
                    if (files.Count >= MaxIndexedFiles) break;
                    var fi = (FileInfo)it;
                    if (fi.Length > 2 * 1024 * 1024) continue;
                    DateTime prevMod;
                    if (_diskMod.TryGetValue(rel, out prevMod) && fi.LastWriteTimeUtc > prevMod && !openSet.Contains(rel) && fi.Length <= InlineFileLimit)
                    {
                        // an external / agent edit on disk: read it and broadcast
                        string text = ReadTextFile(fi.FullName);
                        string old;
                        if (text != null && (!_contents.TryGetValue(rel, out old) || old != text))
                        {
                            int next = Rev(rel) + 1;
                            _contents[rel] = text; _revisions[rel] = next; RecordSnapshot(rel, next, text);
                            Server.Broadcast(Json(new Dictionary<string, object> { { "type", "fileBuffer" }, { "path", rel }, { "content", text }, { "revision", next }, { "authorId", LocalUserId }, { "authorName", LocalDisplayName }, { "authorColor", LocalColor } }), null);
                        }
                    }
                    _diskMod[rel] = fi.LastWriteTimeUtc;
                    if (!seen.Add(rel)) continue;
                    string ext = Path.GetExtension(it.Name).TrimStart('.').ToLowerInvariant();
                    files.Add(new CollabSharedFile { RelativePath = rel, Name = it.Name, Language = ext.Length == 0 ? "code" : ext, IsOpenOnHost = openSet.Contains(rel) });
                }
            };
            if (!string.IsNullOrEmpty(root) && Directory.Exists(root)) scan(root, "", 0);
            if (Session != null && Session.IsHostingLocally && !string.IsNullOrEmpty(root) && Directory.Exists(root) && files.Count < MaxIndexedFiles && dirs.Count < MaxIndexedDirs)
                BroadcastDiskDeletions(new HashSet<string>(files.Select(f => f.RelativePath)), new HashSet<string>(dirs));
            _sharedDirs = dirs;
            _sharedFiles = files;
            RebuildLocks();
        }

        /// <summary>Files or folders that vanished from the host's disk outside the IDE (Explorer, git, the agent) are deleted
        /// on every peer too, as an fsEvent delete. Only after a complete scan, so the 800-file cap never looks like a delete.</summary>
        void BroadcastDiskDeletions(HashSet<string> nowFiles, HashSet<string> nowDirs)
        {
            var gone = new List<string>();
            foreach (var d in _sharedDirs.OrderBy(x => x.Length))
            {
                if (nowDirs.Contains(d) || gone.Any(g => d.StartsWith(g + "/"))) continue;
                string full = FullPathOf(d);
                if (full != null && !Directory.Exists(full)) gone.Add(d);
            }
            foreach (var f in _sharedFiles.Select(x => x.RelativePath).ToList())
            {
                if (nowFiles.Contains(f) || gone.Any(g => f.StartsWith(g + "/"))) continue;
                string full = FullPathOf(f);
                if (full != null && !File.Exists(full) && !Directory.Exists(full) && !_ide.OpenFiles().Any(o => NormalizeRelativePath(o.FullPath) == f)) gone.Add(f);
            }
            foreach (var rel in gone)
            {
                foreach (var k in _contents.Keys.Where(k => k == rel || k.StartsWith(rel + "/")).ToList()) { _contents.Remove(k); _revisions.Remove(k); _snapshots.Remove(k); _diskMod.Remove(k); }
                Server.Broadcast(Json(new Dictionary<string, object> { { "type", "fsEvent" }, { "op", "delete" }, { "path", rel }, { "userId", LocalUserId }, { "displayName", LocalDisplayName } }), LocalUserId);
                RecordActivity(LocalDisplayName, LocalColor, "deleted", rel);
            }
        }

        /// <summary>UTF-8 text without NUL bytes in the first 4 KB (the Mac's binary test), else null.</summary>
        static string ReadTextFile(string full)
        {
            try
            {
                var data = File.ReadAllBytes(full);
                for (int i = 0; i < Math.Min(4096, data.Length); i++) if (data[i] == 0) return null;
                return new UTF8Encoding(false, true).GetString(data).Replace("\r\n", "\n");
            }
            catch (IOException) { return null; } catch (UnauthorizedAccessException) { return null; } catch (DecoderFallbackException) { return null; }
        }

        string ResolveFileContent(string relRaw)
        {
            string rel = NormalizeRelativePath(relRaw);
            if (rel.Length == 0) return "";
            string cached;
            if (_contents.TryGetValue(rel, out cached))
            {
                int rev = Rev(rel); _revisions[rel] = rev;
                if (Snapshot(rel, rev) == null) RecordSnapshot(rel, rev, cached);
                return cached;
            }
            var open = _ide.OpenFiles().FirstOrDefault(f => NormalizeRelativePath(f.FullPath) == rel);
            string text = open != null ? open.Content : null;
            if (text == null) { string full = FullPathOf(rel); if (full != null && File.Exists(full)) text = ReadTextFile(full); }
            if (text == null) return "";
            _contents[rel] = text;
            int r2 = Rev(rel); _revisions[rel] = r2;
            RecordSnapshot(rel, r2, text);
            return text;
        }

        /// <summary>applyIncomingFileContent: a collaborator's full buffer, 3-way merged when it was edited from an older revision.</summary>
        Tuple<string, int, bool> ApplyIncomingFileContent(string relRaw, string content, int? baseRevision, string authorId, string authorName, string authorColor)
        {
            string rel = NormalizeRelativePath(relRaw);
            if (rel.Length == 0) return Tuple.Create(content, 1, false);
            content = content.Replace("\r\n", "\n");
            string current = ResolveFileContent(rel);
            int currentRev = Rev(rel);
            if (current == content) return Tuple.Create(current, currentRev, false);
            string merged = content; bool didMerge = false;
            string baseSnap = baseRevision.HasValue && baseRevision.Value < currentRev ? Snapshot(rel, baseRevision.Value) : null;
            if (baseSnap != null) { var m = CollabMerge.Merge(baseSnap, current, content); merged = m.Merged; didMerge = m.DidAutoMerge; }
            if (merged == current) return Tuple.Create(current, currentRev, didMerge);
            _contents[rel] = merged;
            int next = currentRev + 1;
            _revisions[rel] = next;
            RecordSnapshot(rel, next, merged);
            WriteRelative(rel, merged);
            PushToEditor(rel, merged);
            if (!_sharedFiles.Any(f => f.RelativePath == rel)) { IndexLocalWorkspaceFiles(true); _ide.RefreshTree(); }
            RecordActivity(authorName, authorColor, didMerge ? "merged edit" : "edited", rel);
            return Tuple.Create(merged, next, didMerge);
        }

        /// <summary>Moves every per-file record of a file, or of everything under a folder, to its new relative path.</summary>
        void MoveKeys(string rel, string newRel)
        {
            Func<string, string> map = k => k == rel ? newRel : (k.StartsWith(rel + "/") ? newRel + k.Substring(rel.Length) : null);
            foreach (var k in _contents.Keys.ToList()) { string n = map(k); if (n != null) { _contents[n] = _contents[k]; _contents.Remove(k); } }
            foreach (var k in _revisions.Keys.ToList()) { string n = map(k); if (n != null) { _revisions[n] = _revisions[k]; _revisions.Remove(k); } }
            foreach (var k in _snapshots.Keys.ToList()) { string n = map(k); if (n != null) { _snapshots[n] = _snapshots[k]; _snapshots.Remove(k); } }
            foreach (var k in _peerBaseRevisions.Keys.ToList()) { string n = map(k); if (n != null) { _peerBaseRevisions[n] = _peerBaseRevisions[k]; _peerBaseRevisions.Remove(k); } }
            foreach (var k in _lastSynced.Keys.ToList()) { string n = map(k); if (n != null) { _lastSynced[n] = _lastSynced[k]; _lastSynced.Remove(k); } }
            foreach (var k in _diskMod.Keys.ToList()) { string n = map(k); if (n != null) { _diskMod[n] = _diskMod[k]; _diskMod.Remove(k); } }
            foreach (var f in _sharedFiles) { string n = map(f.RelativePath); if (n != null) { f.RelativePath = n; f.Name = n.Split('/').Last(); } }
            _sharedDirs = _sharedDirs.Select(d => map(d) ?? d).ToList();
        }

        void DropKeys(string rel)
        {
            Func<string, bool> hit = k => k == rel || k.StartsWith(rel + "/");
            foreach (var k in _contents.Keys.Where(hit).ToList()) _contents.Remove(k);
            foreach (var k in _revisions.Keys.Where(hit).ToList()) _revisions.Remove(k);
            foreach (var k in _snapshots.Keys.Where(hit).ToList()) _snapshots.Remove(k);
            foreach (var k in _peerBaseRevisions.Keys.Where(hit).ToList()) _peerBaseRevisions.Remove(k);
            foreach (var k in _lastSynced.Keys.Where(hit).ToList()) _lastSynced.Remove(k);
            foreach (var k in _diskMod.Keys.Where(hit).ToList()) _diskMod.Remove(k);
            _sharedDirs.RemoveAll(d => hit(d));
            _sharedFiles.RemoveAll(f => hit(f.RelativePath));
        }

        /// <summary>A file-system change from another collaborator (fsEvent over WebSocket, or POST /api/collab/fs-event).
        /// The host applies it to the shared folder and relays it; a peer applies it to its mirror. A host-side "write" to a
        /// file the room already tracks, sent with the writer's baseRevision, goes through the 3-way merge like an edit.</summary>
        void ApplyFileSystemEvent(Dictionary<string, object> ev, bool broadcastToOthers, string senderUserId)
        {
            string op = S(ev, "op"), rel = SanitizeRelativePath(S(ev, "path"));
            if (op == null || rel.Length == 0) return;
            string target = FullPathOf(rel);
            if (target == null) return;
            bool hosting = Session != null && Session.IsHostingLocally;
            var relay = new Dictionary<string, object>(ev); relay["type"] = "fsEvent"; relay["path"] = rel;
            try
            {
                switch (op)
                {
                    case "mkdir": Directory.CreateDirectory(target); if (!_sharedDirs.Contains(rel)) _sharedDirs.Add(rel); break;
                    case "write":
                    {
                        string content = (S(ev, "content") ?? "").Replace("\r\n", "\n");
                        int? baseRev = I(ev, "baseRevision");
                        if (hosting && baseRev.HasValue && _contents.ContainsKey(rel))
                        {
                            string uid = S(ev, "userId") ?? senderUserId ?? "peer", name = S(ev, "displayName") ?? "Collaborator";
                            var known = Find(uid);
                            string color = known != null ? known.Color : (S(ev, "color") ?? "#3B82F6");
                            var o = ApplyIncomingFileContent(rel, content, baseRev, uid, name, color);
                            // the writer gets the merged text back only when the merge changed it
                            Server.Broadcast(Json(FileBufferMessage(rel, o.Item1, o.Item2, uid, name, color)), o.Item3 ? null : uid);
                            IndexLocalWorkspaceFiles(true);
                            _ide.RefreshTree();
                            return;
                        }
                        string prev;
                        bool same = _contents.TryGetValue(rel, out prev) && prev == content && File.Exists(target);
                        if (!same)
                        {
                            int? sentRev = I(ev, "revision");
                            int next = !hosting && sentRev.HasValue ? sentRev.Value : (_revisions.ContainsKey(rel) ? Rev(rel) + 1 : 1);
                            _contents[rel] = content; _revisions[rel] = next; RecordSnapshot(rel, next, content);
                            if (!hosting) _peerBaseRevisions[rel] = next;
                            WriteRelative(rel, content);
                            PushToEditor(rel, content);
                        }
                        relay["content"] = content; relay["revision"] = Rev(rel);
                        break;
                    }
                    case "rename":
                    {
                        string newRel = SanitizeRelativePath(S(ev, "newPath"));
                        string newFull = FullPathOf(newRel);
                        if (newRel.Length == 0 || newFull == null || newRel == rel) return;
                        Directory.CreateDirectory(Path.GetDirectoryName(newFull));
                        if (Directory.Exists(target) && !Directory.Exists(newFull)) Directory.Move(target, newFull);
                        else if (File.Exists(target) && !File.Exists(newFull)) File.Move(target, newFull);
                        MoveKeys(rel, newRel);
                        relay["newPath"] = newRel;
                        _ide.PathMoved(target, newFull);
                        break;
                    }
                    case "delete":
                        if (Directory.Exists(target)) Directory.Delete(target, true); else if (File.Exists(target)) File.Delete(target);
                        DropKeys(rel);
                        break;
                    default: return;
                }
            }
            catch (IOException ex) { Debug.WriteLine("collab fs-event: " + ex.Message); }
            catch (UnauthorizedAccessException ex) { Debug.WriteLine("collab fs-event: " + ex.Message); }
            var actor = Find(S(ev, "userId") ?? "");
            RecordActivity(S(ev, "displayName") ?? "Collaborator", actor != null ? actor.Color : "#3B82F6", FsActionLabel(op), op == "rename" ? rel + " → " + SanitizeRelativePath(S(ev, "newPath")) : rel);
            if (hosting)
            {
                IndexLocalWorkspaceFiles(true);
                if (broadcastToOthers) Server.Broadcast(Json(relay), senderUserId);
            }
            _ide.RefreshTree();
        }

        static string FsActionLabel(string op)
        {
            switch (op) { case "mkdir": return "created folder"; case "write": return "saved"; case "rename": return "renamed"; case "delete": return "deleted"; default: return op; }
        }

        bool IsInsideShared(string path)
        {
            string root = SharedRoot ?? _ide.WorkspaceFolder;
            if (string.IsNullOrEmpty(root) || string.IsNullOrEmpty(path)) return false;
            try
            {
                string full = Path.GetFullPath(path), r = Path.GetFullPath(root).TrimEnd('\\') + "\\";
                return full.StartsWith(r, StringComparison.OrdinalIgnoreCase);
            }
            catch (ArgumentException) { return false; } catch (NotSupportedException) { return false; } catch (PathTooLongException) { return false; }
        }

        /// <summary>notifyLocalFileSystemEvent: this IDE saved, created, renamed or deleted something inside the shared folder.
        /// The host updates its records and broadcasts an fsEvent; a peer sends it to the host (WebSocket, else HTTP).</summary>
        public void NotifyLocalFileSystemEvent(string op, string path, string newPath = null, string content = null)
        {
            var s = Session;
            if (s == null || _applyingRemote || !IsInsideShared(path) || (newPath != null && !IsInsideShared(newPath))) return;
            string rel = NormalizeRelativePath(path), newRel = newPath != null ? NormalizeRelativePath(newPath) : null;
            if (rel.Length == 0 || (newPath != null && newRel.Length == 0)) return;
            if (content != null) content = content.Replace("\r\n", "\n");
            var payload = new Dictionary<string, object> { { "type", "fsEvent" }, { "op", op }, { "path", rel }, { "userId", LocalUserId }, { "displayName", LocalDisplayName }, { "color", LocalColor } };
            if (newRel != null) payload["newPath"] = newRel;
            if (content != null) payload["content"] = content;
            lock (_gate)
            {
                switch (op)
                {
                    case "write":
                        if (content == null) return;
                        if (s.IsHostingLocally)
                        {
                            string prev;
                            if (!_contents.TryGetValue(rel, out prev) || prev != content)
                            {
                                int next = _revisions.ContainsKey(rel) ? Rev(rel) + 1 : 1;
                                _contents[rel] = content; _revisions[rel] = next; RecordSnapshot(rel, next, content);
                            }
                            payload["revision"] = Rev(rel);
                            try { _diskMod[rel] = File.GetLastWriteTimeUtc(Path.GetFullPath(path)); } catch (IOException) { } catch (UnauthorizedAccessException) { }
                        }
                        else
                        {
                            int pb;
                            if (_peerBaseRevisions.TryGetValue(rel, out pb)) payload["baseRevision"] = pb;
                            _contents[rel] = content;
                        }
                        _lastSynced[rel] = content;
                        break;
                    case "rename": MoveKeys(rel, newRel); break;
                    case "delete": DropKeys(rel); break;
                    case "mkdir": if (!_sharedDirs.Contains(rel)) _sharedDirs.Add(rel); break;
                    default: return;
                }
                RecordActivity(LocalDisplayName, LocalColor, FsActionLabel(op), op == "rename" ? rel + " → " + newRel : rel);
                if (s.IsHostingLocally)
                {
                    IndexLocalWorkspaceFiles(true);
                    Server.Broadcast(Json(payload), LocalUserId);
                }
            }
            if (!s.IsHostingLocally)
            {
                if (IsWebSocketRealtimeActive) SendPeerFireAndForget(payload);
                else
                {
                    var _ = Task.Run(async () =>
                    {
                        try { using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(8))) (await Http.PostAsync(s.RemoteEndpoint + "/api/collab/fs-event", new StringContent(Json(payload), Encoding.UTF8, "application/json"), cts.Token)).Dispose(); }
                        catch (Exception ex) { if (!(ex is HttpRequestException || ex is TaskCanceledException)) throw; Debug.WriteLine("collab fs-event: " + ex.Message); }
                    });
                }
            }
            Fire();
        }

        string BuildWorkspaceBundle()
        {
            IndexLocalWorkspaceFiles(true);
            string root = SharedRoot ?? _ide.WorkspaceFolder;
            string hostActive = _ide.CurrentFilePath != null ? NormalizeRelativePath(_ide.CurrentFilePath) : "";
            int budget = InlineBudget;
            var files = new List<Dictionary<string, object>>();
            foreach (var f in _sharedFiles)
            {
                string rel = f.RelativePath;
                var item = new Dictionary<string, object> { { "path", rel }, { "name", f.Name }, { "language", f.Language }, { "revision", Rev(rel) } };
                string mem; int len;
                if (_contents.TryGetValue(rel, out mem) && (len = Encoding.UTF8.GetByteCount(mem)) <= InlineFileLimit && len <= budget) { item["hasInlineContent"] = true; item["content"] = mem; budget -= len; }
                else
                {
                    string full = FullPathOf(rel);
                    var fi = full != null ? new FileInfo(full) : null;
                    if (fi != null && fi.Exists)
                    {
                        item["size"] = fi.Length;
                        string text = fi.Length <= InlineFileLimit && fi.Length <= budget ? ReadTextFile(full) : null;
                        if (text != null)
                        {
                            item["hasInlineContent"] = true; item["content"] = text; budget -= (int)fi.Length;
                            _contents[rel] = text; int rev = Rev(rel); _revisions[rel] = rev;
                            if (Snapshot(rel, rev) == null) RecordSnapshot(rel, rev, text);
                        }
                        else item["hasInlineContent"] = false;
                    }
                    else item["hasInlineContent"] = false;
                }
                files.Add(item);
            }
            return Json(new Dictionary<string, object> { { "shareCode", Session.ShareCode }, { "workspaceName", Session.WorkspaceName }, { "workspaceLang", Session.WorkspaceLang }, { "hostUserId", Session.HostUserId }, { "hostDisplayName", Session.HostDisplayName }, { "hostActiveFile", hostActive }, { "directories", _sharedDirs }, { "files", files } });
        }

        string BuildSyncPayload(string assignedColor)
        {
            UpsertSelf(); EnsureAITeammate();
            IndexLocalWorkspaceFiles(false);
            var buffers = new Dictionary<string, object>(); var bufferRevs = new Dictionary<string, object>();
            foreach (var f in _ide.OpenFiles().Take(24))
            {
                string rel = NormalizeRelativePath(f.FullPath);
                if (rel.Length == 0 || f.Content == null || Encoding.UTF8.GetByteCount(f.Content) > InlineFileLimit) continue;
                buffers[rel] = f.Content; int rev = Rev(rel); bufferRevs[rel] = rev;
                if (Snapshot(rel, rev) == null) RecordSnapshot(rel, rev, f.Content);
            }
            foreach (var kv in _contents)
            {
                if (buffers.Count >= 32) break;
                if (buffers.ContainsKey(kv.Key) || Encoding.UTF8.GetByteCount(kv.Value) > InlineFileLimit) continue;
                buffers[kv.Key] = kv.Value; int rev = Rev(kv.Key); bufferRevs[kv.Key] = rev;
                if (Snapshot(kv.Key, rev) == null) RecordSnapshot(kv.Key, rev, kv.Value);
            }
            var payload = new Dictionary<string, object>
            {
                { "shareCode", Session.ShareCode }, { "shareLink", GetShareLink() ?? "" }, { "publicTunnelURL", PublicTunnelUrl ?? "" }, { "tunnelProvider", TunnelProvider },
                { "workspaceName", Session.WorkspaceName }, { "workspaceLang", Session.WorkspaceLang }, { "hostUserId", Session.HostUserId }, { "hostDisplayName", Session.HostDisplayName },
                { "participants", SerializeParticipants() }, { "sharedDirectories", _sharedDirs },
                { "sharedFiles", _sharedFiles.Select(f => new Dictionary<string, object> { { "relativePath", f.RelativePath }, { "name", f.Name }, { "language", f.Language }, { "isOpenOnHost", f.IsOpenOnHost }, { "activeEditorName", f.ActiveEditorName ?? "" }, { "activeEditorColor", f.ActiveEditorColor ?? "" }, { "revision", Rev(f.RelativePath) } }).ToList() },
                { "openBuffers", buffers }, { "fileRevisions", bufferRevs },
                { "chatMessages", _chat.Skip(Math.Max(0, _chat.Count - 50)).Select(m => new Dictionary<string, object> { { "id", m.Id }, { "userId", m.UserId }, { "displayName", m.DisplayName }, { "userColor", m.UserColor }, { "message", m.Message }, { "timestamp", Iso(m.Timestamp) } }).ToList() },
                { "activityLog", _activity.Skip(Math.Max(0, _activity.Count - 30)).Select(a => new Dictionary<string, object> { { "id", a.Id }, { "actorName", a.ActorName }, { "actorColor", a.ActorColor }, { "action", a.Action }, { "target", a.Target }, { "timestamp", Iso(a.Timestamp) } }).ToList() },
                // the whole board as a JSON string (Codable [TeamTask], ISO-8601 dates), like the Mac host
                { "teamTasksJSON", TeamTaskJson.ArrayJson(Tasks.Tasks) }
            };
            if (assignedColor != null) payload["assignedColor"] = assignedColor;
            return Json(payload);
        }

        Dictionary<string, object> FileBufferMessage(string rel, string content, int rev, string uid, string name, string color)
        {
            return new Dictionary<string, object> { { "type", "fileBuffer" }, { "path", rel }, { "content", content }, { "revision", rev }, { "authorId", uid }, { "authorName", name }, { "authorColor", color } };
        }

        // ── host: HTTP ──

        CollabResponse HandleHttp(CollabRequest r)
        {
            if (r.Method == "GET" && (r.Path == "/" || r.Path == "/index.html")) return PortalPage(r);
            var body = r.Method == "POST" ? Parse(r.BodyText) : null;
            lock (_gate)
            {
                if (Session == null) return CollabResponse.Text("404 Not Found", "application/json", "{\"error\":\"No active session\"}");
                switch (r.Method + " " + r.Path)
                {
                    case "POST /api/collab/join":
                    {
                        body = body ?? new Dictionary<string, object>();
                        string reqCode = (S(body, "code") ?? "").ToUpperInvariant();
                        if (reqCode.Length > 0 && reqCode != Session.ShareCode) return new CollabResponse { Status = "403 Forbidden", ContentType = "application/json", Body = Encoding.UTF8.GetBytes("{\"error\":\"Invalid room code\"}") };
                        string uid = S(body, "userId") ?? ("web-" + Guid.NewGuid().ToString("N").Substring(0, 6)), name = S(body, "displayName") ?? "Collaborator", role = S(body, "role") ?? "Editor";
                        string color = AssignDistinctColor(S(body, "color"), uid);
                        Upsert(uid, name, role, color, null);
                        RecordActivity(name, color, "joined session", role);
                        BroadcastParticipants();
                        var resp = CollabResponse.Json(BuildSyncPayload(color));
                        FireAsync();
                        return resp;
                    }
                    case "GET /api/collab/workspace-bundle": return CollabResponse.Json(BuildWorkspaceBundle());
                    case "POST /api/collab/sync": case "GET /api/collab/sync":
                        if (body != null) ProcessPeerSync(body);
                        FireAsync();
                        return CollabResponse.Json(BuildSyncPayload(null));
                    case "GET /api/collab/file":
                    {
                        string q; r.Query.TryGetValue("path", out q);
                        string rel = SanitizeRelativePath(q ?? "");
                        string content = ResolveFileContent(rel);
                        return CollabResponse.Json(Json(new Dictionary<string, object> { { "path", rel }, { "content", content }, { "revision", Rev(rel) } }));
                    }
                    case "POST /api/collab/edit":
                    {
                        var resp = new Dictionary<string, object> { { "ok", true } };
                        string path = S(body, "path"), content = S(body, "content");
                        if (path != null && content != null)
                        {
                            string uid = S(body, "userId") ?? "peer", name = S(body, "displayName") ?? "Collaborator", color = S(body, "color") ?? "#3B82F6";
                            var o = ApplyIncomingFileContent(path, content, I(body, "baseRevision"), uid, name, color);
                            resp["revision"] = o.Item2; resp["merged"] = o.Item3;
                            if (o.Item3) resp["content"] = o.Item1;
                            Server.Broadcast(Json(FileBufferMessage(NormalizeRelativePath(path), o.Item1, o.Item2, uid, name, color)), o.Item3 ? null : uid);
                            FireAsync();
                        }
                        return CollabResponse.Json(Json(resp));
                    }
                    case "POST /api/collab/fs-event":
                        if (body != null) ApplyFileSystemEvent(body, true, S(body, "userId"));
                        FireAsync();
                        return CollabResponse.Json("{\"ok\":true}");
                    case "POST /api/collab/chat":
                    {
                        string text = S(body, "message");
                        if (text != null && text.Trim().Length > 0) { AddChat(S(body, "userId") ?? "peer", S(body, "displayName") ?? "Collaborator", S(body, "color") ?? "#3B82F6", text, null); HandleChatAIMention(S(body, "userId") ?? "peer", S(body, "displayName") ?? "Collaborator", text); FireAsync(); }
                        return CollabResponse.Json("{\"ok\":true}");
                    }
                    case "POST /api/collab/task":
                        // always 200 with the full payload (even for bad JSON or an unknown action), as on the Mac
                        if (body != null) HandleTaskAction(body);
                        FireAsync();
                        return new CollabResponse { ContentType = "application/json", Body = Encoding.UTF8.GetBytes(BuildSyncPayload(null)) };
                    case "POST /api/collab/leave":
                    {
                        string uid = S(body, "userId");
                        var p = uid != null ? Find(uid) : null;
                        if (p != null) RecordActivity(p.DisplayName, p.Color, "left session", "");
                        if (uid != null) { _participants.RemoveAll(x => x.UserId == uid); RebuildLocks(); BroadcastParticipants(); FireAsync(); }
                        return CollabResponse.Json("{\"ok\":true}");
                    }
                }
            }
            return null;
        }

        void FireAsync() { ThreadPool.QueueUserWorkItem(_ => Fire()); }

        /// <summary>The browser portal (room code in the query or the mc_collab_code cookie), else the room-code gate page.</summary>
        CollabResponse PortalPage(CollabRequest r)
        {
            CollabSession s = Session;
            string expected = s != null ? s.ShareCode.ToUpperInvariant() : "";
            string q = QueryCode(r), cookie = "";
            string raw = r.Header("Cookie");
            if (raw != null) foreach (var pair in raw.Split(';')) { var kv = pair.Trim().Split('='); if (kv.Length >= 2 && kv[0] == "mc_collab_code") cookie = kv[1].Trim().ToUpperInvariant(); }
            string wsName = s != null ? s.WorkspaceName : "Workspace";
            if (expected.Length == 0 || q == expected || (q.Length == 0 && cookie == expected))
            {
                var resp = CollabResponse.Text("200 OK", "text/html; charset=utf-8", CollabPortal.Portal.Replace("{{WS_NAME}}", wsName).Replace("{{CODE}}", expected));
                if (expected.Length > 0) resp.Extra["Set-Cookie"] = "mc_collab_code=" + expected + "; Path=/; Max-Age=86400; SameSite=Lax";
                return resp;
            }
            string esc = wsName.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");
            string err = q.Length > 0 ? "<div class=\"err\">Room Code does not match the active session. Check the 6-character Room Code shown in MicroCode → Team Collaboration on the host computer.</div>" : "";
            return CollabResponse.Text("200 OK", "text/html; charset=utf-8", CollabPortal.Gate.Replace("{{WS_NAME}}", esc).Replace("{{ERROR_HTML}}", err));
        }

        void ProcessPeerSync(Dictionary<string, object> body)
        {
            string uid = S(body, "userId");
            if (uid == null) return;
            string name = S(body, "displayName") ?? "Collaborator", role = S(body, "role") ?? "Editor";
            string color = AssignDistinctColor(S(body, "color"), uid);
            var mouse = ParseMouse(Obj(body, "mouse"));
            Upsert(uid, name, role, color, ParseCursor(Obj(body, "cursor")), mouse, S(body, "activeTaskTitle"), B(body, "isAIActive") ?? false, S(body, "aiStatusText"));
            // a peer's whole task board (sent after every local task change): replaces the room's list
            string tasksJson = S(body, "teamTasksJSON");
            if (tasksJson != null)
            {
                var list = TeamTaskJson.ParseArray(tasksJson);
                if (list != null) { Tasks.ApplyRemoteTasks(list); BroadcastTeamTasksIfActive(Tasks.Tasks); }
            }
            var edits = Arr(body, "fileEdits");
            if (edits != null)
                foreach (var e in edits.OfType<Dictionary<string, object>>())
                {
                    string path = S(e, "path"), content = S(e, "content");
                    if (path == null || content == null) continue;
                    var o = ApplyIncomingFileContent(path, content, I(e, "baseRevision"), uid, name, color);
                    Server.Broadcast(Json(FileBufferMessage(NormalizeRelativePath(path), o.Item1, o.Item2, uid, name, color)), o.Item3 ? null : uid);
                }
        }

        void BroadcastParticipants()
        {
            if (Session == null || !Session.IsHostingLocally) return;
            Server.Broadcast(Json(new Dictionary<string, object> { { "type", "participants" }, { "participants", SerializeParticipants() } }), null);
        }

        void AddChat(string uid, string name, string color, string text, string id)
        {
            var msg = new CollabChat { UserId = uid, DisplayName = name, UserColor = color, Message = text };
            if (id != null) msg.Id = id;
            _chat.Add(msg);
            // the AI's replies are not "posted message" activity on the Mac either
            if (uid != AITeammateUserId) RecordActivity(name, color, "posted message", text.Length > 40 ? text.Substring(0, 40) : text);
            Server.Broadcast(Json(new Dictionary<string, object> { { "type", "chat" }, { "id", msg.Id }, { "userId", uid }, { "displayName", name }, { "userColor", color }, { "message", text } }), null);
        }

        // ── host: WebSocket ──

        void HandleHostWsText(CollabWsClient client, string text)
        {
            var msg = Parse(text);
            string type = S(msg, "type");
            if (type == null) return;
            if (type != "mouse" && type != "cursor") Trace("ws in " + type + (S(msg, "path") != null ? " " + S(msg, "path") : "") + (I(msg, "baseRevision").HasValue ? " base " + I(msg, "baseRevision") : ""));
            lock (_gate)
            {
                string uid = S(msg, "userId") ?? client.UserId ?? "";
                // a socket keeps the identity it said hello with: a Mac peer's local agent sends frames as "ai-agent-teammate",
                // and rebinding the socket to that id (as the Mac host does) makes later echoes skip the wrong client
                if (uid.Length > 0 && uid != AITeammateUserId && (client.UserId == null || type == "hello")) client.UserId = uid;
                var known = uid.Length > 0 ? Find(uid) : null;
                switch (type)
                {
                    case "hello":
                    {
                        if (uid.Length == 0) return;
                        string assigned = AssignDistinctColor(S(msg, "color"), uid);
                        Upsert(uid, S(msg, "displayName") ?? "Collaborator", S(msg, "role") ?? "Editor", assigned, null);
                        client.SendText(Json(new Dictionary<string, object> { { "type", "assignedIdentity" }, { "userId", uid }, { "color", assigned } }));
                        BroadcastParticipants();
                        break;
                    }
                    case "mouse":
                    {
                        if (uid.Length == 0) return;
                        var m = new CollabMouse { X = Math.Max(0, Math.Min(1, Dbl(msg, "x") ?? 0.5)), Y = Math.Max(0, Math.Min(1, Dbl(msg, "y") ?? 0.5)), Surface = S(msg, "surface") ?? "editor", ActiveFile = S(msg, "activeFile") != null ? NormalizeRelativePath(S(msg, "activeFile")) : null, ActiveLine = I(msg, "activeLine"), IsPressing = B(msg, "isPressing") ?? false };
                        string name = S(msg, "displayName") ?? (known != null ? known.DisplayName : "Collaborator"), role = S(msg, "role") ?? (known != null ? known.Role : "Editor");
                        string color = known != null ? known.Color : AssignDistinctColor(S(msg, "color"), uid);
                        Upsert(uid, name, role, color, null, m);
                        Server.Broadcast(Json(new Dictionary<string, object> { { "type", "mouse" }, { "userId", uid }, { "displayName", name }, { "role", role }, { "color", color }, { "x", m.X }, { "y", m.Y }, { "surface", m.Surface }, { "activeFile", m.ActiveFile ?? "" }, { "activeLine", m.ActiveLine ?? 0 }, { "isPressing", m.IsPressing } }), uid);
                        break;
                    }
                    case "cursor":
                    {
                        if (uid.Length == 0) return;
                        var c = new CollabCursor { FilePath = NormalizeRelativePath(S(msg, "filePath") ?? ""), Line = Math.Max(1, I(msg, "line") ?? 1), Column = Math.Max(1, I(msg, "column") ?? 1), EndLine = I(msg, "endLine"), EndColumn = I(msg, "endColumn"), IsTyping = B(msg, "isTyping") };
                        string name = S(msg, "displayName") ?? (known != null ? known.DisplayName : "Collaborator"), role = S(msg, "role") ?? (known != null ? known.Role : "Editor");
                        string color = known != null ? known.Color : AssignDistinctColor(S(msg, "color"), uid);
                        Upsert(uid, name, role, color, c);
                        Server.Broadcast(Json(new Dictionary<string, object> { { "type", "cursor" }, { "userId", uid }, { "displayName", name }, { "role", role }, { "color", color }, { "filePath", c.FilePath }, { "line", c.Line }, { "column", c.Column }, { "endLine", c.EndLine ?? c.Line }, { "endColumn", c.EndColumn ?? c.Column }, { "isTyping", c.IsTyping ?? false } }), uid);
                        break;
                    }
                    case "edit":
                    {
                        string path = S(msg, "path"), content = S(msg, "content");
                        if (path == null || content == null) return;
                        string name = S(msg, "displayName") ?? "Collaborator", color = known != null ? known.Color : (S(msg, "color") ?? "#3B82F6");
                        var o = ApplyIncomingFileContent(path, content, I(msg, "baseRevision"), uid, name, color);
                        string rel = NormalizeRelativePath(path);
                        var ack = new Dictionary<string, object> { { "type", "editAck" }, { "path", rel }, { "revision", o.Item2 }, { "merged", o.Item3 } };
                        if (o.Item3) ack["content"] = o.Item1;
                        client.SendText(Json(ack));
                        Server.Broadcast(Json(FileBufferMessage(rel, o.Item1, o.Item2, uid, name, color)), o.Item3 ? null : uid);
                        break;
                    }
                    case "fsEvent": ApplyFileSystemEvent(msg, true, uid); break;
                    case "chat":
                    {
                        string t = S(msg, "message");
                        if (t == null || t.Trim().Length == 0) return;
                        AddChat(uid, S(msg, "displayName") ?? "Collaborator", known != null ? known.Color : (S(msg, "color") ?? "#3B82F6"), t, null);
                        HandleChatAIMention(uid, S(msg, "displayName") ?? "Collaborator", t);
                        break;
                    }
                    default: return;
                }
            }
            Fire();
        }

        void HostMaintenance()
        {
            if (!IsHosting) return;
            bool changed = false;
            lock (_gate)
            {
                FlushPendingWrites();
                UpsertSelf(); EnsureAITeammate();
                IndexLocalWorkspaceFiles(true);
                var cutoff = DateTime.UtcNow.AddSeconds(-15);
                foreach (var p in _participants.Where(x => x.UserId != LocalUserId && x.UserId != AITeammateUserId && x.IsOnline && x.LastSeenAt < cutoff)) { p.IsOnline = false; changed = true; }
                if (changed) BroadcastParticipants();
            }
            Fire();
        }

        // ── peer: join ──

        /// <summary>Parses a full invite URL (http(s)://host[:port][/relay-prefix]/?code=X), a LAN token (host:port#CODE),
        /// host:port, or a bare 6-character room code (tried against this machine's own LAN host).</summary>
        public Tuple<string, string> ParseJoinInput(string raw)
        {
            string t = (raw ?? "").Trim(), baseEndpoint = "", code = "";
            if (t.StartsWith("http://") || t.StartsWith("https://"))
            {
                Uri u;
                if (Uri.TryCreate(t, UriKind.Absolute, out u))
                {
                    string path = System.Text.RegularExpressions.Regex.Replace(System.Text.RegularExpressions.Regex.Replace(u.AbsolutePath, "/index\\.html$", ""), "/+$", "");
                    baseEndpoint = u.Scheme + "://" + u.Host + (u.IsDefaultPort ? "" : ":" + u.Port) + path;
                    foreach (var pair in u.Query.TrimStart('?').Split('&')) { var kv = pair.Split(new[] { '=' }, 2); if (kv.Length == 2 && kv[0] == "code") code = Uri.UnescapeDataString(kv[1]).ToUpperInvariant(); }
                }
            }
            else if (t.Contains("#"))
            {
                var parts = t.Split('#');
                string host = System.Text.RegularExpressions.Regex.Replace(parts[0].Trim(), "/+$", "");
                code = (parts.Length > 1 ? parts[1] : "").Trim().ToUpperInvariant();
                baseEndpoint = host.StartsWith("http") ? host : "http://" + host;
            }
            else if (t.Contains(":") && !t.Contains(" ")) baseEndpoint = "http://" + t;
            else { code = t.ToUpperInvariant(); baseEndpoint = "http://" + SelectedLanAddress + ":" + (Server.IsRunning ? Server.Port : CollabServer.FirstPort); }
            return Tuple.Create(baseEndpoint, code);
        }

        public async Task<CollabSession> JoinSession(string input, bool mount = true)
        {
            var parsed = ParseJoinInput(input);
            string baseEndpoint = parsed.Item1, code = parsed.Item2;
            if (baseEndpoint.Length == 0) { Status = CollabStatus.Error; StatusError = "Invalid address"; Fire(); return null; }
            Status = CollabStatus.Connecting; StatusError = null; Fire();
            Dictionary<string, object> json;
            try
            {
                var body = Json(new Dictionary<string, object> { { "code", code }, { "userId", LocalUserId }, { "displayName", LocalDisplayName }, { "role", LocalRole }, { "color", LocalColor } });
                using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(8)))
                using (var resp = await Http.PostAsync(baseEndpoint + "/api/collab/join", new StringContent(body, Encoding.UTF8, "application/json"), cts.Token))
                {
                    if (resp.StatusCode != HttpStatusCode.OK) { Status = CollabStatus.Error; StatusError = "Session not found or rejected"; Fire(); return null; }
                    json = Parse(await resp.Content.ReadAsStringAsync());
                }
            }
            catch (Exception ex)
            { if (!(ex is HttpRequestException || ex is TaskCanceledException)) throw;
                Status = CollabStatus.Error; StatusError = "Cannot reach host (" + baseEndpoint + ")"; Fire(); return null;
            }
            if (json == null) { Status = CollabStatus.Error; StatusError = "Session not found or rejected"; Fire(); return null; }
            string resolved = S(json, "shareCode") ?? code, wsName = S(json, "workspaceName") ?? "Shared Workspace";
            lock (_gate)
            {
                if (!string.IsNullOrEmpty(S(json, "assignedColor"))) LocalColor = S(json, "assignedColor");
                Session = new CollabSession { Id = resolved, ShareCode = resolved, ProjectId = wsName, WorkspaceName = wsName, WorkspaceLang = S(json, "workspaceLang") ?? "code", HostUserId = S(json, "hostUserId") ?? "host", HostDisplayName = S(json, "hostDisplayName") ?? "Host", IsHostingLocally = false, RemoteEndpoint = baseEndpoint };
                Status = CollabStatus.Connected;
            }
            await MountWorkspaceBundle(baseEndpoint, resolved, wsName, mount);
            lock (_gate) ApplySyncPayload(json);
            ConnectPeerWebSocket(baseEndpoint, resolved);
            _peerTimer = new Timer(_ => PeerSyncTick(), null, 1200, 1200);
            Fire();
            return Session;
        }

        async Task MountWorkspaceBundle(string baseEndpoint, string code, string wsName, bool mount)
        {
            string safe = string.Join("-", (wsName ?? "").Split(Path.GetInvalidFileNameChars())).Trim();
            if (safe.Length == 0) safe = "SharedWorkspace";
            string root = Path.Combine(_dataDir, "CollabWorkspaces", code, safe);
            Directory.CreateDirectory(root);
            string hostActive = "";
            var lazy = new List<string>();
            lock (_gate) SharedRoot = Path.GetFullPath(root).TrimEnd('\\');
            try
            {
                string text;
                using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15))) text = await (await Http.GetAsync(baseEndpoint + "/api/collab/workspace-bundle", cts.Token)).Content.ReadAsStringAsync();
                var bundle = Parse(text);
                lock (_gate)
                {
                    hostActive = S(bundle, "hostActiveFile") ?? "";
                    var dirs = Arr(bundle, "directories");
                    if (dirs != null)
                    {
                        _sharedDirs = dirs.OfType<string>().ToList();
                        foreach (var d in _sharedDirs) { string full = FullPathOf(SanitizeRelativePath(d)); if (full != null) Directory.CreateDirectory(full); }
                    }
                    var files = Arr(bundle, "files");
                    if (files != null)
                        foreach (var f in files.OfType<Dictionary<string, object>>())
                        {
                            string rel = SanitizeRelativePath(S(f, "path"));
                            string full = FullPathOf(rel);
                            if (rel.Length == 0 || full == null) continue;
                            int rev = I(f, "revision") ?? 1;
                            string content = S(f, "content");
                            bool inline = B(f, "hasInlineContent") ?? content != null;
                            Directory.CreateDirectory(Path.GetDirectoryName(full));
                            if (inline && content != null)
                            {
                                File.WriteAllText(full, content, new UTF8Encoding(false));
                                _contents[rel] = content; _revisions[rel] = rev; _peerBaseRevisions[rel] = rev; _lastSynced[rel] = content; RecordSnapshot(rel, rev, content);
                            }
                            else { if (!File.Exists(full)) File.WriteAllText(full, ""); lazy.Add(rel); }
                        }
                }
            }
            catch (Exception ex) { if (!(ex is HttpRequestException || ex is TaskCanceledException || ex is IOException)) throw; Debug.WriteLine("collab bundle: " + ex.Message); }
            if (mount)
            {
                // the room's board lives in the mirrored workspace's task file (TeamTaskService.load(mirrorRoot))
                Integrations.SetTeamTasksEnabled(true);
                Tasks.Load(SharedRoot);
                string activeFull = hostActive.Length > 0 ? FullPathOf(SanitizeRelativePath(hostActive)) : null;
                _ide.MountWorkspace(SharedRoot, activeFull != null && File.Exists(activeFull) ? activeFull : null);
            }
            // hydrate large files that were left out of the bundle, in the background
            if (lazy.Count > 0)
            {
                var todo = lazy.Take(120).ToList();
                var _ = Task.Run(async () =>
                {
                    foreach (var rel in todo)
                    {
                        if (Session == null || Session.ShareCode != code) return;
                        var j = await GetJson(baseEndpoint + "/api/collab/file?path=" + Uri.EscapeDataString(rel));
                        string content = S(j, "content");
                        if (content == null) continue;
                        lock (_gate)
                        {
                            int rev = I(j, "revision") ?? 1;
                            _contents[rel] = content; _revisions[rel] = rev; _peerBaseRevisions[rel] = rev; RecordSnapshot(rel, rev, content);
                            WriteRelative(rel, content);
                            PushToEditor(rel, content);
                        }
                    }
                });
            }
        }

        async Task<Dictionary<string, object>> GetJson(string url)
        {
            try { using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10))) return Parse(await (await Http.GetAsync(url, cts.Token)).Content.ReadAsStringAsync()); }
            catch (Exception ex) { if (!(ex is HttpRequestException || ex is TaskCanceledException)) throw; return null; }
        }

        /// <summary>applySyncPayload (peer): participants, tree, revisioned open buffers (3-way merged with unsent local edits), chat, activity.</summary>
        void ApplySyncPayload(Dictionary<string, object> json)
        {
            if (Session == null) return;
            if (S(json, "workspaceName") != null) Session.WorkspaceName = S(json, "workspaceName");
            if (S(json, "workspaceLang") != null) Session.WorkspaceLang = S(json, "workspaceLang");
            ApplyRoomTasks(S(json, "teamTasksJSON"), false);
            var parr = Arr(json, "participants");
            if (parr != null) ApplyParticipantsArray(parr);
            bool treeChanged = false;
            var dirs = Arr(json, "sharedDirectories");
            if (dirs != null)
            {
                var list = dirs.OfType<string>().ToList();
                if (!list.SequenceEqual(_sharedDirs))
                {
                    _sharedDirs = list;
                    foreach (var d in list) { string full = FullPathOf(SanitizeRelativePath(d)); if (full != null && !Directory.Exists(full)) { try { Directory.CreateDirectory(full); treeChanged = true; } catch (IOException) { } } }
                }
            }
            var farr = Arr(json, "sharedFiles");
            if (farr != null)
            {
                var oldPaths = new HashSet<string>(_sharedFiles.Select(f => f.RelativePath));
                _sharedFiles = farr.OfType<Dictionary<string, object>>().Where(o => S(o, "relativePath") != null && S(o, "name") != null && SanitizeRelativePath(S(o, "relativePath")).Length > 0)
                    .Select(o => new CollabSharedFile { RelativePath = SanitizeRelativePath(S(o, "relativePath")), Name = S(o, "name"), Language = S(o, "language") ?? "code", IsOpenOnHost = B(o, "isOpenOnHost") ?? false, ActiveEditorName = string.IsNullOrEmpty(S(o, "activeEditorName")) ? null : S(o, "activeEditorName"), ActiveEditorColor = string.IsNullOrEmpty(S(o, "activeEditorColor")) ? null : S(o, "activeEditorColor") }).ToList();
                var added = _sharedFiles.Select(f => f.RelativePath).Where(p => !oldPaths.Contains(p)).ToList();
                if (added.Count > 0 || _sharedFiles.Count != oldPaths.Count) treeChanged = true;
                if (added.Count > 0 && !Session.IsHostingLocally && SharedRoot != null)
                {
                    string endpoint = Session.RemoteEndpoint;
                    var _ = Task.Run(async () =>
                    {
                        foreach (var rel in added)
                        {
                            var j = await GetJson(endpoint + "/api/collab/file?path=" + Uri.EscapeDataString(rel));
                            string content = S(j, "content");
                            if (content == null) continue;
                            lock (_gate)
                            {
                                if (_contents.ContainsKey(rel)) continue;
                                int rev = I(j, "revision") ?? 1;
                                _contents[rel] = content; _revisions[rel] = rev; _peerBaseRevisions[rel] = rev; RecordSnapshot(rel, rev, content);
                                WriteRelative(rel, content);
                            }
                        }
                        _ide.RefreshTree();
                    });
                }
            }
            var revs = Obj(json, "fileRevisions") ?? new Dictionary<string, object>();
            var buffers = Obj(json, "openBuffers");
            if (buffers != null)
                foreach (var kv in buffers)
                {
                    string rel = SanitizeRelativePath(kv.Key), remote = kv.Value as string;
                    if (rel.Length == 0 || remote == null) continue;
                    int remoteRev = I(revs, kv.Key) ?? I(revs, rel) ?? Rev(rel);
                    int knownBase; _peerBaseRevisions.TryGetValue(rel, out knownBase);
                    if (knownBase > 0 && remoteRev <= knownBase) continue;
                    string resolved = ResolveAgainstLocal(rel, remote, knownBase);
                    RecordSnapshot(rel, remoteRev, remote);
                    _peerBaseRevisions[rel] = remoteRev; _revisions[rel] = remoteRev;
                    string cur;
                    if (!_contents.TryGetValue(rel, out cur) || cur != resolved) { _contents[rel] = resolved; WriteRelative(rel, resolved); PushToEditor(rel, resolved); }
                }
            if (treeChanged) _ide.RefreshTree();
            var carr = Arr(json, "chatMessages");
            if (carr != null) _chat = carr.OfType<Dictionary<string, object>>().Where(o => S(o, "message") != null).Select(o => new CollabChat { Id = S(o, "id") ?? Guid.NewGuid().ToString(), UserId = S(o, "userId") ?? "", DisplayName = S(o, "displayName") ?? "Collaborator", UserColor = S(o, "userColor") ?? "#3B82F6", Message = S(o, "message"), Timestamp = ParseIso(S(o, "timestamp")) }).ToList();
            var aarr = Arr(json, "activityLog");
            if (aarr != null) _activity = aarr.OfType<Dictionary<string, object>>().Where(o => S(o, "action") != null).Select(o => new CollabActivity { Id = S(o, "id") ?? Guid.NewGuid().ToString(), ActorName = S(o, "actorName") ?? "Team", ActorColor = S(o, "actorColor") ?? "#3B82F6", Action = S(o, "action"), Target = S(o, "target") ?? "", Timestamp = ParseIso(S(o, "timestamp")) }).ToList();
            ApplyFollowIfNeeded();
        }

        /// <summary>A remote buffer against the peer's own unsent edit: 3-way merge from the last confirmed base revision.</summary>
        string ResolveAgainstLocal(string rel, string remote, int knownBase)
        {
            string local, baseSnap;
            if (_contents.TryGetValue(rel, out local) && local != remote && knownBase > 0 && (baseSnap = Snapshot(rel, knownBase)) != null && local != baseSnap)
                return CollabMerge.Merge(baseSnap, remote, local).Merged;
            return remote;
        }

        // ── peer: WebSocket + sync loop ──

        void ConnectPeerWebSocket(string baseEndpoint, string code)
        {
            DisconnectPeerWebSocket();
            string ws = baseEndpoint.StartsWith("https://") ? "wss://" + baseEndpoint.Substring(8) : baseEndpoint.StartsWith("http://") ? "ws://" + baseEndpoint.Substring(7) : "ws://" + baseEndpoint;
            var cts = new CancellationTokenSource();
            _peerCts = cts;
            var _ = Task.Run(() => PeerWsLoop(new Uri(ws + "/ws/collab?code=" + Uri.EscapeDataString(code)), baseEndpoint, code, cts.Token));
        }

        void DisconnectPeerWebSocket()
        {
            if (_peerCts != null) { _peerCts.Cancel(); _peerCts = null; }
            var ws = _peerWs; _peerWs = null;
            if (ws != null) { try { ws.Abort(); ws.Dispose(); } catch (ObjectDisposedException) { } }
            IsWebSocketRealtimeActive = false;
        }

        async Task PeerWsLoop(Uri uri, string baseEndpoint, string code, CancellationToken ct)
        {
            while (!ct.IsCancellationRequested && Session != null && !Session.IsHostingLocally && Session.ShareCode == code)
            {
                var ws = new ClientWebSocket();
                bool connected = false;
                try
                {
                    await ws.ConnectAsync(uri, ct);
                    connected = true;
                    _peerWs = ws; IsWebSocketRealtimeActive = true; Trace("ws connected");
                    await SendPeer(new Dictionary<string, object> { { "type", "hello" }, { "userId", LocalUserId }, { "displayName", LocalDisplayName }, { "role", LocalRole }, { "color", LocalColor } });
                    Fire();
                    var buf = new byte[65536]; var msg = new MemoryStream();
                    while (ws.State == WebSocketState.Open && !ct.IsCancellationRequested)
                    {
                        var r = await ws.ReceiveAsync(new ArraySegment<byte>(buf), ct);
                        if (r.MessageType == WebSocketMessageType.Close) break;
                        msg.Write(buf, 0, r.Count);
                        if (!r.EndOfMessage) continue;
                        string text = Encoding.UTF8.GetString(msg.ToArray()); msg.SetLength(0);
                        HandlePeerWsText(text);
                    }
                }
                catch (WebSocketException ex) { Trace("ws error: " + ex.Message); } catch (OperationCanceledException) { Trace("ws cancelled"); return; } catch (ObjectDisposedException) { Trace("ws disposed"); } catch (IOException ex) { Trace("ws io: " + ex.Message); }
                finally { if (_peerWs == ws) { _peerWs = null; IsWebSocketRealtimeActive = false; } try { ws.Dispose(); } catch (ObjectDisposedException) { } }
                // the realtime socket dropped and the host refuses a new one: it is gone or unreachable — say so now
                // instead of waiting for HTTP sync timeouts
                if (!connected && !ct.IsCancellationRequested) MarkHostUnreachable();
                Fire();
                try { await Task.Delay(1500, ct); } catch (OperationCanceledException) { return; }
            }
        }

        async Task SendPeer(Dictionary<string, object> obj)
        {
            var ws = _peerWs;
            if (ws == null || ws.State != WebSocketState.Open) return;
            var bytes = Encoding.UTF8.GetBytes(Json(obj));
            await _peerSend.WaitAsync();
            try { await ws.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, CancellationToken.None); }
            catch (WebSocketException) { IsWebSocketRealtimeActive = false; } catch (ObjectDisposedException) { IsWebSocketRealtimeActive = false; } catch (InvalidOperationException) { IsWebSocketRealtimeActive = false; }
            finally { _peerSend.Release(); }
        }

        void SendPeerFireAndForget(Dictionary<string, object> obj) { var _ = SendPeer(obj); }

        void HandlePeerWsText(string text)
        {
            var msg = Parse(text);
            string type = S(msg, "type");
            if (type == null) return;
            if (type != "mouse" && type != "cursor") Trace("ws in " + type + (S(msg, "path") != null ? " " + S(msg, "path") : "") + (I(msg, "revision").HasValue ? " rev " + I(msg, "revision") : ""));
            lock (_gate)
            {
                switch (type)
                {
                    case "welcome": case "participants": { var arr = Arr(msg, "participants"); Trace("ws " + type + " (" + (arr != null ? arr.Count : -1) + " people)"); if (arr != null) ApplyParticipantsArray(arr); break; }
                    case "assignedIdentity": if (!string.IsNullOrEmpty(S(msg, "color"))) { LocalColor = S(msg, "color"); Upsert(LocalUserId, LocalDisplayName, LocalRole, LocalColor, null); } break;
                    case "mouse":
                    {
                        string uid = S(msg, "userId");
                        if (uid == null || uid == LocalUserId) return;
                        int? al = I(msg, "activeLine"); string af = S(msg, "activeFile");
                        var m = new CollabMouse { X = Math.Max(0, Math.Min(1, Dbl(msg, "x") ?? 0.5)), Y = Math.Max(0, Math.Min(1, Dbl(msg, "y") ?? 0.5)), Surface = S(msg, "surface") ?? "editor", ActiveFile = string.IsNullOrEmpty(af) ? null : NormalizeRelativePath(af), ActiveLine = al.HasValue && al.Value > 0 ? al : null, IsPressing = B(msg, "isPressing") ?? false };
                        Upsert(uid, S(msg, "displayName") ?? "Collaborator", S(msg, "role") ?? "Editor", S(msg, "color") ?? "#3B82F6", null, m);
                        break;
                    }
                    case "cursor":
                    {
                        string uid = S(msg, "userId");
                        if (uid == null || uid == LocalUserId) return;
                        var c = new CollabCursor { FilePath = NormalizeRelativePath(S(msg, "filePath") ?? ""), Line = Math.Max(1, I(msg, "line") ?? 1), Column = Math.Max(1, I(msg, "column") ?? 1), EndLine = I(msg, "endLine"), EndColumn = I(msg, "endColumn"), IsTyping = B(msg, "isTyping") };
                        Upsert(uid, S(msg, "displayName") ?? "Collaborator", S(msg, "role") ?? "Editor", S(msg, "color") ?? "#3B82F6", c);
                        ApplyFollowIfNeeded();
                        break;
                    }
                    case "editAck":
                    {
                        string rel = NormalizeRelativePath(S(msg, "path") ?? "");
                        if (rel.Length == 0) return;
                        int? rev = I(msg, "revision");
                        string mergedContent = S(msg, "content");
                        if (rev.HasValue)
                        {
                            string cur; _contents.TryGetValue(rel, out cur);
                            RecordSnapshot(rel, rev.Value, mergedContent ?? cur ?? "");
                            _peerBaseRevisions[rel] = rev.Value; _revisions[rel] = rev.Value;
                        }
                        if (B(msg, "merged") == true && mergedContent != null) { _contents[rel] = mergedContent; WriteRelative(rel, mergedContent); PushToEditor(rel, mergedContent); }
                        break;
                    }
                    case "fileBuffer":
                    {
                        string raw = S(msg, "path"), remote = S(msg, "content");
                        if (raw == null || remote == null) return;
                        if (S(msg, "authorId") == LocalUserId && B(msg, "merged") != true) return;
                        string rel = NormalizeRelativePath(raw);
                        int remoteRev = I(msg, "revision") ?? Rev(rel) + 1;
                        int knownBase; _peerBaseRevisions.TryGetValue(rel, out knownBase);
                        string resolved = ResolveAgainstLocal(rel, remote, knownBase);
                        RecordSnapshot(rel, remoteRev, remote);
                        _peerBaseRevisions[rel] = remoteRev; _revisions[rel] = remoteRev;
                        _contents[rel] = resolved;
                        WriteRelative(rel, resolved);
                        PushToEditor(rel, resolved);
                        break;
                    }
                    case "fsEvent": ApplyFileSystemEvent(msg, false, null); break;
                    case "teamTasks": ApplyRoomTasks(S(msg, "teamTasksJSON"), true); break;
                    case "chat":
                    {
                        string t = S(msg, "message");
                        if (t == null) return;
                        string id = S(msg, "id") ?? Guid.NewGuid().ToString();
                        if (!_chat.Any(c => c.Id == id)) _chat.Add(new CollabChat { Id = id, UserId = S(msg, "userId") ?? "", DisplayName = S(msg, "displayName") ?? "Collaborator", UserColor = S(msg, "userColor") ?? "#3B82F6", Message = t });
                        break;
                    }
                    default: return;
                }
            }
            Fire();
        }

        void PeerSyncTick()
        {
            if (Session == null || Session.IsHostingLocally || Interlocked.Exchange(ref _peerSyncBusy, 1) == 1) return;
            string endpoint = Session.RemoteEndpoint;
            var _ = Task.Run(async () =>
            {
                try
                {
                    var body = new Dictionary<string, object> { { "userId", LocalUserId }, { "displayName", LocalDisplayName }, { "role", LocalRole }, { "color", LocalColor }, { "isAIActive", false }, { "aiStatusText", "" }, { "activeTaskTitle", SelectedTaskTitle ?? "" } };
                    var cur = CurrentLocalCursor();
                    if (cur != null) body["cursor"] = CursorDict(cur);
                    if (_localMouse != null) body["mouse"] = MouseDict(_localMouse);
                    using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(4)))
                    using (var resp = await Http.PostAsync(endpoint + "/api/collab/sync", new StringContent(Json(body), Encoding.UTF8, "application/json"), cts.Token))
                    {
                        var json = resp.StatusCode == HttpStatusCode.OK ? Parse(await resp.Content.ReadAsStringAsync()) : null;
                        Trace("sync " + (int)resp.StatusCode + (json == null ? " (unusable)" : ""));
                        if (json != null)
                        {
                            Interlocked.Exchange(ref _syncFailures, 0);
                            lock (_gate) { if (Session == null || Session.IsHostingLocally) return; Status = CollabStatus.Connected; ApplySyncPayload(json); FlushPendingWrites(); }
                            Fire();
                        }
                        else SyncFailed();
                    }
                }
                catch (Exception ex)
                {
                    if (!(ex is HttpRequestException || ex is TaskCanceledException)) throw;
                    Trace("sync failed: " + ex.GetType().Name + " " + (ex.InnerException != null ? ex.InnerException.Message : ex.Message));
                    SyncFailed();
                }
                finally { Interlocked.Exchange(ref _peerSyncBusy, 0); }
            });
        }

        /// <summary>The host stopped answering (HTTP sync failed and the WebSocket is down): show it as it is — reconnecting,
        /// with everyone else offline — instead of a room that still looks live. The next good sync restores the list.</summary>
        int _syncFailures;

        /// <summary>One HTTP sync to the host failed. Without a live WebSocket that already means the host is unreachable.
        /// With one, three failures in a row (~3.6 s) mean the socket is half-open (Wi-Fi dropped, host asleep or gone):
        /// it is aborted so the realtime loop reconnects for real, and the room shows as reconnecting meanwhile.</summary>
        void SyncFailed()
        {
            int n = Interlocked.Increment(ref _syncFailures);
            if (IsWebSocketRealtimeActive)
            {
                if (n < 3) return;
                var ws = _peerWs;
                if (ws != null) { try { ws.Abort(); } catch (ObjectDisposedException) { } }
                IsWebSocketRealtimeActive = false;
            }
            MarkHostUnreachable();
        }

        void MarkHostUnreachable()
        {
            lock (_gate)
            {
                if (Session == null || Session.IsHostingLocally) return;
                Status = CollabStatus.Reconnecting;
                foreach (var p in _participants) if (p.UserId != LocalUserId) p.IsOnline = false;
                RebuildLocks();
            }
            Fire();
        }

        // ── leave ──

        public async Task LeaveSession()
        {
            var s = Session;
            DisconnectPeerWebSocket();
            if (_peerTimer != null) { _peerTimer.Dispose(); _peerTimer = null; }
            if (_hostTimer != null) { _hostTimer.Dispose(); _hostTimer = null; }
            if (s != null)
            {
                if (s.IsHostingLocally) { Server.Stop(); StopOnlineTunnel(); }
                else if (s.RemoteEndpoint.Length > 0)
                {
                    try { using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(4))) (await Http.PostAsync(s.RemoteEndpoint + "/api/collab/leave", new StringContent(Json(new Dictionary<string, object> { { "userId", LocalUserId } }), Encoding.UTF8, "application/json"), cts.Token)).Dispose(); }
                    catch (Exception ex) { if (!(ex is HttpRequestException || ex is TaskCanceledException)) throw; Debug.WriteLine("collab leave: " + ex.Message); }
                }
            }
            lock (_gate)
            {
                Session = null; _participants = new List<CollabParticipant>(); _sharedFiles = new List<CollabSharedFile>(); _sharedDirs = new List<string>();
                _contents.Clear(); _revisions.Clear(); _snapshots.Clear(); _peerBaseRevisions.Clear(); _lastSynced.Clear(); _diskMod.Clear();
                FollowingUserId = null; _localCursor = null; _localMouse = null; SharedRoot = null; _syncFailures = 0; _pendingDisk.Clear(); ResetAITeammate();
                Status = CollabStatus.Disconnected; IsWebSocketRealtimeActive = false;
            }
            Fire();
        }

        // ── local events (editor → room) ──

        /// <summary>notifyLocalFileEdited: the host bumps the revision, saves and broadcasts; a peer sends an edit against its base revision.</summary>
        public void NotifyLocalFileEdited(string path, string content)
        {
            var s = Session;
            if (s == null || _applyingRemote || content == null) return;
            content = content.Replace("\r\n", "\n");
            string rel = NormalizeRelativePath(path);
            if (rel.Length == 0) return;
            Dictionary<string, object> peerMsg = null;
            lock (_gate)
            {
                string last;
                if (_lastSynced.TryGetValue(rel, out last) && last == content) return;
                _lastSynced[rel] = content;
                if (s.IsHostingLocally)
                {
                    string prev;
                    if (_contents.TryGetValue(rel, out prev) && !_snapshots.ContainsKey(rel)) { int r0 = Rev(rel); _revisions[rel] = r0; RecordSnapshot(rel, r0, prev); }
                    int next = Rev(rel) + 1;
                    // the host's own unsaved typing stays unsaved (its Save writes the file); peers get the buffer live
                    _contents[rel] = content; _revisions[rel] = next; RecordSnapshot(rel, next, content);
                    Server.Broadcast(Json(FileBufferMessage(rel, content, next, LocalUserId, LocalDisplayName, LocalColor)), LocalUserId);
                    return;
                }
                int pb; int baseRev = _peerBaseRevisions.TryGetValue(rel, out pb) ? pb : Rev(rel);
                _contents[rel] = content;
                WriteRelative(rel, content);
                peerMsg = new Dictionary<string, object> { { "type", "edit" }, { "path", rel }, { "content", content }, { "baseRevision", baseRev }, { "userId", LocalUserId }, { "displayName", LocalDisplayName }, { "color", LocalColor } };
            }
            if (IsWebSocketRealtimeActive) { SendPeerFireAndForget(peerMsg); return; }
            var _ = Task.Run(async () =>
            {
                try
                {
                    peerMsg.Remove("type");
                    using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(8)))
                    using (var resp = await Http.PostAsync(s.RemoteEndpoint + "/api/collab/edit", new StringContent(Json(peerMsg), Encoding.UTF8, "application/json"), cts.Token))
                    {
                        var j = Parse(await resp.Content.ReadAsStringAsync());
                        lock (_gate)
                        {
                            int? rev = I(j, "revision");
                            if (rev.HasValue) { RecordSnapshot(rel, rev.Value, S(j, "content") ?? content); _peerBaseRevisions[rel] = rev.Value; _revisions[rel] = rev.Value; }
                            string cur;
                            if (B(j, "merged") == true && S(j, "content") != null && _contents.TryGetValue(rel, out cur) && cur == content) { _contents[rel] = S(j, "content"); WriteRelative(rel, S(j, "content")); PushToEditor(rel, S(j, "content")); }
                        }
                    }
                }
                catch (Exception ex) { if (!(ex is HttpRequestException || ex is TaskCanceledException)) throw; Debug.WriteLine("collab edit: " + ex.Message); }
            });
        }

        /// <summary>updateLocalEditorSelection: caret / selection presence, sent at most every 30 ms (typing always goes out).</summary>
        public void UpdateLocalEditorSelection(string path, int line, int column, int? endLine, int? endColumn, bool isTyping)
        {
            var s = Session;
            if (s == null) return;
            string rel = NormalizeRelativePath(path);
            if (rel.Length == 0) return;
            var pos = new CollabCursor { FilePath = rel, Line = Math.Max(1, line), Column = Math.Max(1, column), EndLine = endLine.HasValue ? Math.Max(1, endLine.Value) : (int?)null, EndColumn = endColumn.HasValue ? Math.Max(1, endColumn.Value) : (int?)null, IsTyping = isTyping };
            Dictionary<string, object> payload;
            lock (_gate)
            {
                _localCursor = pos;
                Upsert(LocalUserId, LocalDisplayName, s.IsHostingLocally ? "Host" : LocalRole, LocalColor, pos);
                if (!isTyping && (DateTime.UtcNow - _lastCursorSent).TotalMilliseconds < 30) return;
                _lastCursorSent = DateTime.UtcNow;
                payload = new Dictionary<string, object> { { "type", "cursor" }, { "userId", LocalUserId }, { "displayName", LocalDisplayName }, { "role", s.IsHostingLocally ? "Host" : LocalRole }, { "color", LocalColor }, { "filePath", rel }, { "line", pos.Line }, { "column", pos.Column }, { "endLine", pos.EndLine ?? pos.Line }, { "endColumn", pos.EndColumn ?? pos.Column }, { "isTyping", isTyping } };
                if (s.IsHostingLocally) Server.Broadcast(Json(payload), LocalUserId);
            }
            if (!s.IsHostingLocally && IsWebSocketRealtimeActive) SendPeerFireAndForget(payload);
            if (isTyping)
            {
                if (_typingTimer != null) _typingTimer.Dispose();
                _typingTimer = new Timer(_ =>
                {
                    var c = _localCursor;
                    if (c != null && c.IsTyping == true) UpdateLocalEditorSelection(c.FilePath, c.Line, c.Column, c.EndLine, c.EndColumn, false);
                }, null, 1200, Timeout.Infinite);
            }
            Fire();
        }

        public async Task SendChatMessage(string message)
        {
            string clean = (message ?? "").Trim();
            var s = Session;
            if (clean.Length == 0 || s == null) return;
            if (s.IsHostingLocally) { lock (_gate) { AddChat(LocalUserId, LocalDisplayName, LocalColor, clean, null); HandleChatAIMention(LocalUserId, LocalDisplayName, clean); } Fire(); return; }
            if (IsWebSocketRealtimeActive) { await SendPeer(new Dictionary<string, object> { { "type", "chat" }, { "userId", LocalUserId }, { "displayName", LocalDisplayName }, { "color", LocalColor }, { "message", clean } }); return; }
            try { using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(8))) (await Http.PostAsync(s.RemoteEndpoint + "/api/collab/chat", new StringContent(Json(new Dictionary<string, object> { { "userId", LocalUserId }, { "displayName", LocalDisplayName }, { "color", LocalColor }, { "message", clean } }), Encoding.UTF8, "application/json"), cts.Token)).Dispose(); }
            catch (Exception ex) { if (!(ex is HttpRequestException || ex is TaskCanceledException)) throw; Debug.WriteLine("collab chat: " + ex.Message); }
            PeerSyncTick();
        }

        // ── follow & open ──

        public void ToggleFollow(string userId)
        {
            if (Session == null) return;
            FollowingUserId = FollowingUserId == userId ? null : userId;
            if (FollowingUserId != null) JumpTo(Find(userId));
            Fire();
        }

        void ApplyFollowIfNeeded()
        {
            if (Session == null || FollowingUserId == null) return;
            var target = Find(FollowingUserId);
            if (target != null && target.Cursor != null && target.Cursor.FilePath.Length > 0) JumpTo(target);
        }

        public void JumpTo(CollabParticipant p)
        {
            if (p == null || p.Cursor == null || p.Cursor.FilePath.Length == 0) return;
            OpenShared(p.Cursor.FilePath, p.Cursor.Line);
        }

        /// <summary>openSharedFileInEditor: opens the local (mirrored) copy, fetching it from the host first if it is missing.</summary>
        public void OpenShared(string relRaw, int line)
        {
            string rel = SanitizeRelativePath(relRaw);
            string full = FullPathOf(rel);
            if (full == null) return;
            if (File.Exists(full)) { _ide.OpenFile(full, line); return; }
            var s = Session;
            if (s == null || s.IsHostingLocally) return;
            var _ = Task.Run(async () =>
            {
                var j = await GetJson(s.RemoteEndpoint + "/api/collab/file?path=" + Uri.EscapeDataString(rel));
                string content = S(j, "content");
                if (content == null) return;
                lock (_gate) { int rev = I(j, "revision") ?? 1; _contents[rel] = content; _revisions[rel] = rev; _peerBaseRevisions[rel] = rev; RecordSnapshot(rel, rev, content); WriteRelative(rel, content); }
                _ide.OpenFile(full, line);
            });
        }

        public List<CollabParticipant> RemoteCollaboratorsIn(string path)
        {
            string rel = NormalizeRelativePath(path);
            lock (_gate) return _participants.Where(p => p.IsOnline && p.UserId != LocalUserId && ((p.Cursor != null && p.Cursor.FilePath == rel) || (p.Cursor == null && p.Mouse != null && p.Mouse.ActiveFile == rel))).ToList();
        }

        // ── share link / token ──

        public string GetShareLink()
        {
            var s = Session;
            if (s == null) return null;
            if (OnlineMode && !string.IsNullOrEmpty(PublicTunnelUrl)) return PublicTunnelUrl.TrimEnd('/') + "/?code=" + s.ShareCode;
            if (s.IsHostingLocally) return "http://" + SelectedLanAddress + ":" + Server.Port + "/?code=" + s.ShareCode;
            return s.RemoteEndpoint.TrimEnd('/') + "/?code=" + s.ShareCode;
        }

        public string GetJoinToken()
        {
            var s = Session;
            if (s == null) return "";
            if (OnlineMode && !string.IsNullOrEmpty(PublicTunnelUrl)) return PublicTunnelUrl.TrimEnd('/') + "/?code=" + s.ShareCode;
            if (s.IsHostingLocally) return SelectedLanAddress + ":" + Server.Port + "#" + s.ShareCode;
            return s.RemoteEndpoint + "#" + s.ShareCode;
        }

        // ── online relay (Dotmini official HTTPS relay, cloudflared fallback) ──

        public void SetOnlineMode(bool online)
        {
            OnlineMode = online;
            if (online) { if (IsHosting) StartOnlineTunnel(); }
            else StopOnlineTunnel();
            Fire();
        }

        static string Hex(byte[] b) { return BitConverter.ToString(b).Replace("-", "").ToLowerInvariant(); }

        /// <summary>loadOrCreateCollabRelayNodeProof: a per-install secret (never sent) hashed with the app path.</summary>
        string NodeProof()
        {
            string path = Path.Combine(_dataDir, "collab_relay_node.secret");
            string secret = null;
            try { if (File.Exists(path)) { string raw = File.ReadAllText(path).Trim(); if (raw.Length >= 32) secret = raw; } } catch (IOException) { }
            if (secret == null)
            {
                var bytes = new byte[32];
                using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(bytes);
                secret = Hex(bytes);
                Directory.CreateDirectory(_dataDir);
                File.WriteAllText(path, secret);
            }
            string scope = System.Reflection.Assembly.GetEntryAssembly() != null ? System.Reflection.Assembly.GetEntryAssembly().Location : AppDomain.CurrentDomain.BaseDirectory;
            using (var sha = SHA256.Create()) return Hex(sha.ComputeHash(Encoding.UTF8.GetBytes("dotmini-collab-relay-node-v2:" + secret + "|" + scope)));
        }

        string UserHint()
        {
            var s = DotminiAuth.Session;
            string ident = s != null && !string.IsNullOrEmpty(s.UserId) ? "collab:" + s.UserId + "|" + (s.Email ?? "").ToLowerInvariant() : "collab:" + Environment.UserName + "|" + LocalUserId;
            using (var sha = SHA256.Create()) return Hex(sha.ComputeHash(Encoding.UTF8.GetBytes("dotmini-collab-user-hint-v2:" + ident)).Take(16).ToArray());
        }

        public void StartOnlineTunnel()
        {
            StopOnlineTunnel();
            TunnelStatus = "starting"; TunnelError = null; Fire();
            var cts = new CancellationTokenSource();
            _relayCts = cts;
            int port = Server.Port;
            var _ = Task.Run(() => RelayLoop(port, cts.Token));
        }

        async Task RelayLoop(int port, CancellationToken ct)
        {
            string proof = NodeProof(), hint = UserHint(), epoch = ((int)Defaults.Num("microcode.collab.relayPatternEpoch", 0)).ToString(CultureInfo.InvariantCulture);
            var session = DotminiAuth.Session;
            foreach (var host in new[] { "cloudai.dotmini.net", "api.dotmini.net" })
            {
                if (ct.IsCancellationRequested) return;
                var ws = new ClientWebSocket();
                ws.Options.SetRequestHeader("X-Relay-Node-Proof", proof);
                ws.Options.SetRequestHeader("X-Relay-Epoch", epoch);
                ws.Options.SetRequestHeader("X-Relay-User-Hint", hint);
                if (session != null && !string.IsNullOrEmpty(session.AccessToken)) ws.Options.SetRequestHeader("Authorization", "Bearer " + session.AccessToken);
                try
                {
                    using (var connectCts = CancellationTokenSource.CreateLinkedTokenSource(ct)) { connectCts.CancelAfter(8000); await ws.ConnectAsync(new Uri("wss://" + host + "/api/v2/mobile-relay/uplink"), connectCts.Token); }
                    var first = Parse(await ReceiveText(ws, ct));
                    string prefix = S(first, "poly_prefix");
                    if (S(first, "type") != "registered" || string.IsNullOrEmpty(prefix)) { ws.Abort(); continue; }
                    _relayWs = ws;
                    PublicTunnelUrl = "https://" + host + prefix.TrimEnd('/'); TunnelProvider = host; IsOfficialRelayActive = true; TunnelStatus = "active"; Fire();
                    var ping = new Timer(_ => { var w = _relayWs; if (w == ws) { var __ = SendRelay(ws, "{\"type\":\"ping\"}"); } }, null, 20000, 20000);
                    try
                    {
                        while (ws.State == WebSocketState.Open && !ct.IsCancellationRequested)
                        {
                            var m = Parse(await ReceiveText(ws, ct));
                            if (S(m, "type") == "http_request") { var req = m; var __ = Task.Run(() => ForwardRelayRequest(req, port, ws)); }
                        }
                    }
                    finally { ping.Dispose(); }
                }
                catch (WebSocketException ex) { TunnelError = ex.Message; } catch (OperationCanceledException) { return; } catch (IOException ex) { TunnelError = ex.Message; }
                finally { if (_relayWs == ws) { _relayWs = null; IsOfficialRelayActive = false; } try { ws.Dispose(); } catch (ObjectDisposedException) { } }
                if (PublicTunnelUrl != null && !ct.IsCancellationRequested && IsHosting && OnlineMode)
                {
                    // the relay dropped after registering: reconnect like the Mac does
                    PublicTunnelUrl = null; TunnelStatus = "starting"; Fire();
                    try { await Task.Delay(2000, ct); } catch (OperationCanceledException) { return; }
                    var again = Task.Run(() => RelayLoop(port, ct));
                    return;
                }
            }
            if (ct.IsCancellationRequested || !OnlineMode) return;
            LaunchCloudflaredFallback(port);
        }

        static async Task<string> ReceiveText(ClientWebSocket ws, CancellationToken ct)
        {
            var buf = new byte[65536]; var ms = new MemoryStream();
            while (true)
            {
                var r = await ws.ReceiveAsync(new ArraySegment<byte>(buf), ct);
                if (r.MessageType == WebSocketMessageType.Close) throw new WebSocketException("relay closed");
                ms.Write(buf, 0, r.Count);
                if (r.EndOfMessage) return Encoding.UTF8.GetString(ms.ToArray());
            }
        }

        readonly SemaphoreSlim _relaySend = new SemaphoreSlim(1, 1);
        async Task SendRelay(ClientWebSocket ws, string text)
        {
            await _relaySend.WaitAsync();
            try { await ws.SendAsync(new ArraySegment<byte>(Encoding.UTF8.GetBytes(text)), WebSocketMessageType.Text, true, CancellationToken.None); }
            catch (WebSocketException) { } catch (ObjectDisposedException) { } catch (InvalidOperationException) { }
            finally { _relaySend.Release(); }
        }

        /// <summary>forwardCollabRelayHTTPRequest: replays a relayed request against the local host and answers with status,
        /// headers (Set-Cookie separately) and a base64 body.</summary>
        public async Task<string> RelayResponseFor(Dictionary<string, object> payload, int port)
        {
            string id = S(payload, "id");
            if (string.IsNullOrEmpty(id)) return null;
            string method = (S(payload, "method") ?? "GET").ToUpperInvariant(), target = S(payload, "target") ?? "/";
            if (!target.StartsWith("/")) target = "/" + target;
            try
            {
                using (var req = new HttpRequestMessage(new HttpMethod(method), "http://127.0.0.1:" + port + target))
                {
                    var hdrs = Obj(payload, "headers");
                    string ctype = null;
                    if (hdrs != null)
                        foreach (var kv in hdrs)
                        {
                            string lk = kv.Key.ToLowerInvariant();
                            if (lk == "host" || lk == "content-length" || lk == "connection") continue;
                            if (lk == "content-type") { ctype = kv.Value as string; continue; }
                            req.Headers.TryAddWithoutValidation(kv.Key, Convert.ToString(kv.Value, CultureInfo.InvariantCulture));
                        }
                    req.Headers.TryAddWithoutValidation("X-Dotmini-Relay", "1");
                    string b64 = S(payload, "body_b64");
                    if (!string.IsNullOrEmpty(b64)) { req.Content = new ByteArrayContent(Convert.FromBase64String(b64)); if (ctype != null) req.Content.Headers.TryAddWithoutValidation("Content-Type", ctype); }
                    using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(35)))
                    using (var resp = await Http.SendAsync(req, cts.Token))
                    {
                        var body = await resp.Content.ReadAsByteArrayAsync();
                        var headers = new Dictionary<string, object>(); var cookies = new List<string>();
                        foreach (var h in resp.Headers.Concat(resp.Content.Headers))
                        {
                            string lk = h.Key.ToLowerInvariant();
                            if (lk == "set-cookie") cookies.AddRange(h.Value);
                            else if (lk != "content-length" && lk != "connection" && lk != "transfer-encoding") headers[h.Key] = string.Join(", ", h.Value);
                        }
                        var obj = new Dictionary<string, object> { { "type", "http_response" }, { "id", id }, { "status", (int)resp.StatusCode }, { "headers", headers } };
                        if (cookies.Count > 0) obj["set_cookies"] = cookies;
                        if (body.Length > 0) obj["body_b64"] = Convert.ToBase64String(body);
                        return Json(obj);
                    }
                }
            }
            catch (Exception ex)
            { if (!(ex is HttpRequestException || ex is TaskCanceledException || ex is FormatException)) throw;
                return Json(new Dictionary<string, object> { { "type", "http_response" }, { "id", id }, { "status", 502 }, { "headers", new Dictionary<string, object> { { "Content-Type", "text/plain; charset=utf-8" } } }, { "body_b64", Convert.ToBase64String(Encoding.UTF8.GetBytes("Local collaboration host unreachable")) } });
            }
        }

        async Task ForwardRelayRequest(Dictionary<string, object> payload, int port, ClientWebSocket ws)
        {
            string resp = await RelayResponseFor(payload, port);
            if (resp != null) await SendRelay(ws, resp);
        }

        /// <summary>cloudflared quick tunnel when the Dotmini relay is unreachable (the Mac's SSH localhost.run fallback is not
        /// used: its host key cannot be pinned here).</summary>
        void LaunchCloudflaredFallback(int port)
        {
            string exe = McpConnection.ResolveCommand("cloudflared");
            if (exe == null)
            {
                TunnelStatus = "failed"; TunnelError = "Could not establish online collaboration relay. Check your internet connection or use LAN / P2P mode."; Fire();
                return;
            }
            try
            {
                var p = new Process { StartInfo = new ProcessStartInfo(exe, "tunnel --url http://127.0.0.1:" + port + " --no-autoupdate") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true }, EnableRaisingEvents = true };
                DataReceivedEventHandler h = (s, e) =>
                {
                    if (e.Data == null) return;
                    var m = System.Text.RegularExpressions.Regex.Match(e.Data, @"https://[a-zA-Z0-9.-]+\.trycloudflare\.com");
                    if (m.Success && PublicTunnelUrl != m.Value) { PublicTunnelUrl = m.Value; TunnelProvider = "cloudflare"; TunnelStatus = "active"; Fire(); }
                };
                p.OutputDataReceived += h; p.ErrorDataReceived += h;
                p.Exited += delegate { if (_tunnelProcess == p) { _tunnelProcess = null; if (TunnelStatus == "starting") { TunnelStatus = "failed"; TunnelError = "cloudflared exited"; } else if (OnlineMode) { PublicTunnelUrl = null; TunnelStatus = "idle"; } Fire(); } };
                p.Start(); p.BeginOutputReadLine(); p.BeginErrorReadLine();
                _tunnelProcess = p;
            }
            catch (System.ComponentModel.Win32Exception ex) { TunnelStatus = "failed"; TunnelError = ex.Message; Fire(); }
        }

        public void StopOnlineTunnel()
        {
            if (_relayCts != null) { _relayCts.Cancel(); _relayCts = null; }
            var ws = _relayWs; _relayWs = null;
            if (ws != null) { try { ws.Abort(); } catch (ObjectDisposedException) { } }
            IsOfficialRelayActive = false;
            var p = _tunnelProcess; _tunnelProcess = null;
            if (p != null) { try { if (!p.HasExited) p.Kill(); } catch (InvalidOperationException) { } catch (System.ComponentModel.Win32Exception) { } }
            PublicTunnelUrl = null; TunnelStatus = "idle";
        }
    }
}
