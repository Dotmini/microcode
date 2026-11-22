// Port of TeamTaskService.swift + TeamIntegrationService.swift: shared task contracts (title / objective / scope / status /
// owner / followers / decisions) kept per workspace in team-tasks.json (same JSON as the Mac: ISO-8601 dates, sorted keys),
// synced through the collaboration room, and optionally announced to Slack / Microsoft Teams webhooks. Contracts never carry
// chat prompts or transcripts — only this structured, attributable data is shared or given to an agent.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using MicroCode.Core;

namespace MicroCode.Views
{
    public enum TeamTaskStatus { Planned, Active, Blocked, Review, Done }

    public static class TeamTaskStatusInfo
    {
        public static readonly TeamTaskStatus[] All = { TeamTaskStatus.Planned, TeamTaskStatus.Active, TeamTaskStatus.Blocked, TeamTaskStatus.Review, TeamTaskStatus.Done };
        public static string Raw(TeamTaskStatus s) { return s.ToString().ToLowerInvariant(); }
        public static TeamTaskStatus Parse(string raw)
        {
            foreach (var s in All) if (Raw(s) == (raw ?? "")) return s;
            return TeamTaskStatus.Planned;
        }
        public static string Label(TeamTaskStatus s)
        {
            switch (s)
            {
                case TeamTaskStatus.Active: return "In progress";
                case TeamTaskStatus.Blocked: return "Blocked";
                case TeamTaskStatus.Review: return "Review";
                case TeamTaskStatus.Done: return "Done";
                default: return "Planned";
            }
        }
    }

    public class TeamTaskDecision
    {
        public string Id = Guid.NewGuid().ToString().ToUpperInvariant(), Text = "", Author = "";
        public DateTime CreatedAt = DateTime.UtcNow;
    }

    public class TeamTask
    {
        public string Id = Guid.NewGuid().ToString().ToUpperInvariant(), Title = "", Objective = "", Scope = "", Owner = "", UpdatedBy = "", SourceChatID;
        public TeamTaskStatus Status = TeamTaskStatus.Planned;
        public List<string> Followers = new List<string>();
        public List<TeamTaskDecision> Decisions = new List<TeamTaskDecision>();
        public DateTime CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow;

        public TeamTask Clone()
        {
            var c = (TeamTask)MemberwiseClone();
            c.Followers = Followers.ToList();
            c.Decisions = Decisions.Select(d => new TeamTaskDecision { Id = d.Id, Text = d.Text, Author = d.Author, CreatedAt = d.CreatedAt }).ToList();
            return c;
        }
    }

    /// <summary>TeamTaskEvent raw values (used in webhook text).</summary>
    public static class TeamTaskEvent
    {
        public const string Created = "created", StatusChanged = "changed status", Claimed = "claimed", HandedOff = "handed off", Updated = "updated";
    }

    /// <summary>The Codable wire / file form of tasks: the Mac's synthesized keys, ISO-8601 dates without fractions.</summary>
    public static class TeamTaskJson
    {
        static readonly JavaScriptSerializer Js = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };

        public static string Iso(DateTime t) { return t.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture); }

        public static DateTime? ParseIso(object v)
        {
            var s = v as string;
            DateTime t;
            if (s != null && DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out t)) return t;
            if (v is int || v is long || v is double || v is decimal)
            {
                // Swift's default (non-ISO) Date encoding is seconds since 2001-01-01
                try { return new DateTime(2001, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(Convert.ToDouble(v, CultureInfo.InvariantCulture)); }
                catch (ArgumentOutOfRangeException) { return null; }
            }
            return null;
        }

        public static Dictionary<string, object> ToDict(TeamTask t)
        {
            var d = new Dictionary<string, object>
            {
                { "id", t.Id }, { "title", t.Title }, { "objective", t.Objective }, { "scope", t.Scope }, { "status", TeamTaskStatusInfo.Raw(t.Status) },
                { "owner", t.Owner }, { "followers", t.Followers.ToList() },
                { "decisions", t.Decisions.Select(x => new Dictionary<string, object> { { "id", x.Id }, { "text", x.Text }, { "author", x.Author }, { "createdAt", Iso(x.CreatedAt) } }).ToList() },
                { "createdAt", Iso(t.CreatedAt) }, { "updatedAt", Iso(t.UpdatedAt) }, { "updatedBy", t.UpdatedBy }
            };
            if (t.SourceChatID != null) d["sourceChatID"] = t.SourceChatID;
            return d;
        }

        static string S(Dictionary<string, object> d, string k) { object v; return d.TryGetValue(k, out v) ? v as string : null; }
        static List<object> L(Dictionary<string, object> d, string k)
        {
            object v; if (!d.TryGetValue(k, out v) || v == null) return null;
            var a = v as object[]; if (a != null) return a.ToList();
            var al = v as System.Collections.ArrayList; return al != null ? al.Cast<object>().ToList() : null;
        }

        /// <summary>A task from JSON, or null when a required field (as Codable would require it) is missing or mistyped.</summary>
        public static TeamTask FromDict(Dictionary<string, object> d)
        {
            if (d == null) return null;
            string id = S(d, "id"), title = S(d, "title");
            object cv, uv;
            d.TryGetValue("createdAt", out cv); d.TryGetValue("updatedAt", out uv);
            var created = ParseIso(cv); var updated = ParseIso(uv);
            var followers = L(d, "followers"); var decisions = L(d, "decisions");
            if (id == null || title == null || S(d, "objective") == null || S(d, "scope") == null || S(d, "status") == null || S(d, "owner") == null
                || followers == null || decisions == null || !created.HasValue || !updated.HasValue || S(d, "updatedBy") == null) return null;
            var t = new TeamTask
            {
                Id = id, Title = title, Objective = S(d, "objective"), Scope = S(d, "scope"), Status = TeamTaskStatusInfo.Parse(S(d, "status")), Owner = S(d, "owner"),
                Followers = followers.OfType<string>().ToList(), CreatedAt = created.Value, UpdatedAt = updated.Value, UpdatedBy = S(d, "updatedBy"), SourceChatID = S(d, "sourceChatID")
            };
            foreach (var o in decisions.OfType<Dictionary<string, object>>())
            {
                object dc; o.TryGetValue("createdAt", out dc);
                var when = ParseIso(dc);
                if (S(o, "id") == null || S(o, "text") == null || S(o, "author") == null || !when.HasValue) return null;
                t.Decisions.Add(new TeamTaskDecision { Id = S(o, "id"), Text = S(o, "text"), Author = S(o, "author"), CreatedAt = when.Value });
            }
            return t;
        }

        /// <summary>JSON array of tasks (the teamTasksJSON string in sync payloads).</summary>
        public static string ArrayJson(IEnumerable<TeamTask> tasks) { return Js.Serialize(tasks.Select(ToDict).ToList()); }

        /// <summary>Tasks from a JSON array; null when the text is not a JSON array of valid tasks (all-or-nothing, like JSONDecoder).</summary>
        public static List<TeamTask> ParseArray(string json)
        {
            if (string.IsNullOrWhiteSpace(json)) return null;
            object root;
            try { root = Js.DeserializeObject(json); } catch (ArgumentException) { return null; } catch (InvalidOperationException) { return null; }
            var arr = root as object[];
            if (arr == null) { var al = root as System.Collections.ArrayList; if (al != null) arr = al.Cast<object>().ToArray(); }
            if (arr == null) return null;
            var list = new List<TeamTask>();
            foreach (var o in arr)
            {
                var t = FromDict(o as Dictionary<string, object>);
                if (t == null) return null;
                list.Add(t);
            }
            return list;
        }

        /// <summary>The document file: { schemaVersion, updatedAt, tasks } pretty-printed with sorted keys (as the Mac writes it).</summary>
        public static string Document(IEnumerable<TeamTask> tasks)
        {
            var doc = new Dictionary<string, object> { { "schemaVersion", 1 }, { "updatedAt", Iso(DateTime.UtcNow) }, { "tasks", tasks.Select(ToDict).ToList() } };
            var sb = new StringBuilder();
            Pretty(doc, sb, 0);
            return sb.ToString();
        }

        public static List<TeamTask> ParseDocument(string json, out string error)
        {
            error = null;
            Dictionary<string, object> root;
            try { root = Js.DeserializeObject(json) as Dictionary<string, object>; }
            catch (ArgumentException ex) { error = ex.Message; return null; }
            catch (InvalidOperationException ex) { error = ex.Message; return null; }
            if (root == null) { error = "not a JSON object"; return null; }
            object tv; root.TryGetValue("tasks", out tv);
            var list = ParseArray(tv == null ? null : Js.Serialize(tv));
            if (list == null) error = "the tasks list is missing or has an invalid task";
            return list;
        }

        static void Pretty(object v, StringBuilder sb, int depth)
        {
            string pad = new string(' ', (depth + 1) * 2), end = new string(' ', depth * 2);
            var d = v as Dictionary<string, object>;
            if (d != null)
            {
                if (d.Count == 0) { sb.Append("{\n\n").Append(end).Append('}'); return; }
                sb.Append("{\n");
                var keys = d.Keys.OrderBy(k => k, StringComparer.Ordinal).ToList();
                for (int i = 0; i < keys.Count; i++)
                {
                    sb.Append(pad).Append(Js.Serialize(keys[i])).Append(" : ");
                    Pretty(d[keys[i]], sb, depth + 1);
                    if (i < keys.Count - 1) sb.Append(',');
                    sb.Append('\n');
                }
                sb.Append(end).Append('}');
                return;
            }
            var e = v as System.Collections.IEnumerable;
            if (e != null && !(v is string))
            {
                var items = e.Cast<object>().ToList();
                if (items.Count == 0) { sb.Append("[\n\n").Append(end).Append(']'); return; }
                sb.Append("[\n");
                for (int i = 0; i < items.Count; i++)
                {
                    sb.Append(pad);
                    Pretty(items[i], sb, depth + 1);
                    if (i < items.Count - 1) sb.Append(',');
                    sb.Append('\n');
                }
                sb.Append(end).Append(']');
                return;
            }
            sb.Append(Js.Serialize(v));
        }

        public static bool SameTasks(List<TeamTask> a, List<TeamTask> b)
        {
            if (a.Count != b.Count) return false;
            return ArrayJson(a) == ArrayJson(b);
        }
    }

    /// <summary>TeamTaskService: the per-workspace task list. Thread-safe (the collaboration room applies remote lists from
    /// network threads); readers get copies. Changed fires on any thread.</summary>
    public class TeamTaskStore
    {
        const string FileName = "team-tasks.json";
        readonly object _lock = new object();
        readonly Func<string> _actor;
        List<TeamTask> _tasks = new List<TeamTask>();
        FileSystemWatcher _watcher;
        DateTime _persistedAt = DateTime.MinValue;

        public string SelectedTaskID;
        public string WorkspacePath { get; private set; }
        public string LastError { get; private set; }
        public TeamIntegrations Integrations;
        public event Action Changed;
        /// <summary>A local change to broadcast to the room (CollaborationService.broadcastTeamTasksIfActive).</summary>
        public event Action<List<TeamTask>> LocalChange;

        public TeamTaskStore(Func<string> actorName, TeamIntegrations integrations)
        {
            _actor = actorName;
            Integrations = integrations;
        }

        public List<TeamTask> Tasks { get { lock (_lock) return _tasks.Select(t => t.Clone()).ToList(); } }
        public int Count { get { lock (_lock) return _tasks.Count; } }
        public TeamTask SelectedTask { get { lock (_lock) { var t = _tasks.FirstOrDefault(x => x.Id == SelectedTaskID); return t != null ? t.Clone() : null; } } }

        string Actor { get { string a = _actor != null ? _actor() : null; return string.IsNullOrWhiteSpace(a) ? Environment.UserName : a.Trim(); } }

        void Fire() { var c = Changed; if (c != null) c(); }

        // ── load / watch ──

        public void Load(string workspacePath)
        {
            if (string.IsNullOrWhiteSpace(workspacePath))
            {
                StopWatching();
                lock (_lock) { WorkspacePath = null; _tasks = new List<TeamTask>(); SelectedTaskID = null; }
                Fire();
                return;
            }
            bool changed = WorkspacePath != workspacePath;
            lock (_lock) { WorkspacePath = workspacePath; LastError = null; }
            string path = TaskFiles.PathFor(workspacePath, FileName);
            if (changed || _watcher == null) StartWatching(path);
            if (!File.Exists(path))
            {
                lock (_lock) { _tasks = new List<TeamTask>(); SelectedTaskID = null; }
                Fire();
                return;
            }
            string err = null; List<TeamTask> list = null;
            try { list = TeamTaskJson.ParseDocument(File.ReadAllText(path), out err); }
            catch (IOException ex) { err = ex.Message; }
            catch (UnauthorizedAccessException ex) { err = ex.Message; }
            lock (_lock)
            {
                if (list == null) LastError = "Unable to read shared tasks: " + err;
                else
                {
                    _tasks = list.OrderByDescending(t => t.UpdatedAt).ToList();
                    if (SelectedTaskID == null || !_tasks.Any(t => t.Id == SelectedTaskID)) SelectedTaskID = _tasks.Count > 0 ? _tasks[0].Id : null;
                }
            }
            Fire();
        }

        public void Reload() { Load(WorkspacePath); }

        /// <summary>Loads only when the board is for another workspace. The Mac reloads on every sheet open and before every
        /// create, which wipes a room's in-memory board when its file was never written; the Windows board does not.</summary>
        public void EnsureLoaded(string workspacePath)
        {
            if (WorkspacePath != workspacePath || (_watcher == null && workspacePath != null)) Load(workspacePath);
        }

        void StopWatching()
        {
            var w = _watcher; _watcher = null;
            if (w != null) { w.EnableRaisingEvents = false; w.Dispose(); }
        }

        void StartWatching(string file)
        {
            StopWatching();
            string dir = Path.GetDirectoryName(file);
            try
            {
                Directory.CreateDirectory(dir);
                var w = new FileSystemWatcher(dir, Path.GetFileName(file)) { NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.Size };
                FileSystemEventHandler h = (s, e) =>
                {
                    // our own save echoes back here; the Mac ignores events for 0.15 s after persisting
                    if ((DateTime.UtcNow - _persistedAt).TotalMilliseconds < 400) return;
                    ThreadPool.QueueUserWorkItem(_ => { Thread.Sleep(80); Reload(); });
                };
                w.Changed += h; w.Created += h; w.Renamed += (s, e) => h(s, e);
                w.EnableRaisingEvents = true;
                _watcher = w;
            }
            catch (IOException) { _watcher = null; } catch (ArgumentException) { _watcher = null; } catch (UnauthorizedAccessException) { _watcher = null; }
        }

        // ── operations ──

        public TeamTask CreateTask(string title, string objective, string scope, string sourceChatID = null)
        {
            if (!Integrations.TeamTasksEnabled) return null;
            title = (title ?? "").Trim();
            if (title.Length == 0) return null;
            string actor = Actor;
            var t = new TeamTask { Title = title, Objective = (objective ?? "").Trim(), Scope = (scope ?? "").Trim(), Status = TeamTaskStatus.Planned, Owner = actor, Followers = new List<string> { actor }, SourceChatID = sourceChatID, UpdatedBy = actor };
            lock (_lock) { _tasks.Insert(0, t); SelectedTaskID = t.Id; }
            Persist(true);
            Notify(TeamTaskEvent.Created, t.Clone());
            return t.Clone();
        }

        public void UpdateStatus(TeamTaskStatus status, string taskID)
        {
            if (!Integrations.TeamTasksEnabled) return;
            Update(taskID, TeamTaskEvent.StatusChanged, t => t.Status = status);
        }

        public void Claim(string taskID)
        {
            if (!Integrations.TeamTasksEnabled) return;
            string me = Actor;
            Update(taskID, TeamTaskEvent.Claimed, t =>
            {
                t.Owner = me;
                if (!t.Followers.Contains(me)) t.Followers.Add(me);
                if (t.Status == TeamTaskStatus.Planned) t.Status = TeamTaskStatus.Active;
            });
        }

        public void Handoff(string taskID, string owner)
        {
            if (!Integrations.TeamTasksEnabled) return;
            owner = (owner ?? "").Trim();
            if (owner.Length == 0) return;
            string me = Actor;
            Update(taskID, TeamTaskEvent.HandedOff, t =>
            {
                t.Owner = owner;
                t.Decisions.Add(new TeamTaskDecision { Text = "Handed off to " + owner + ".", Author = me });
            });
        }

        public void ToggleFollowing(string taskID)
        {
            if (!Integrations.TeamTasksEnabled) return;
            string me = Actor;
            Update(taskID, null, t => { if (t.Followers.Contains(me)) t.Followers.Remove(me); else t.Followers.Add(me); });
        }

        public void AddDecision(string text, string taskID)
        {
            if (!Integrations.TeamTasksEnabled) return;
            text = (text ?? "").Trim();
            if (text.Length == 0) return;
            string me = Actor;
            Update(taskID, null, t =>
            {
                t.Decisions.Add(new TeamTaskDecision { Text = text, Author = me });
                if (t.Decisions.Count > 24) t.Decisions.RemoveRange(0, t.Decisions.Count - 24);
            });
        }

        public void Delete(string taskID)
        {
            if (!Integrations.TeamTasksEnabled) return;
            lock (_lock)
            {
                _tasks.RemoveAll(t => t.Id == taskID);
                if (SelectedTaskID == taskID) SelectedTaskID = _tasks.Count > 0 ? _tasks[0].Id : null;
            }
            Persist(true);
        }

        public void Select(string taskID) { lock (_lock) SelectedTaskID = taskID; Fire(); }

        /// <summary>contextForSelectedTask: the only task data an agent ever sees.</summary>
        public string ContextForSelectedTask()
        {
            if (!Integrations.TeamTasksEnabled || !Integrations.AgentContextEnabled) return null;
            var t = SelectedTask;
            if (t == null) return null;
            var sb = new StringBuilder();
            sb.Append("## Shared Team Task Contract\n");
            sb.Append("Task: ").Append(t.Title).Append('\n');
            sb.Append("Status: ").Append(TeamTaskStatusInfo.Label(t.Status)).Append('\n');
            sb.Append("Owner: ").Append(t.Owner).Append('\n');
            sb.Append("Objective: ").Append(t.Objective.Length == 0 ? "Not specified" : t.Objective).Append('\n');
            sb.Append("Scope: ").Append(t.Scope.Length == 0 ? "Not specified" : t.Scope);
            if (t.Decisions.Count > 0)
                sb.Append("\nRecent decisions:\n").Append(string.Join("\n", t.Decisions.Skip(Math.Max(0, t.Decisions.Count - 4)).Select(d => "- " + d.Text + " (" + d.Author + ")")));
            sb.Append("\nUse this contract as the collaboration boundary. Do not infer or reveal private prompts from other chats. Report blockers and validation evidence clearly.");
            return sb.ToString();
        }

        /// <summary>applyRemoteTasks: the room's list replaces ours (sorted newest first), saved without re-broadcasting.</summary>
        public void ApplyRemoteTasks(List<TeamTask> remote)
        {
            var sorted = remote.OrderByDescending(t => t.UpdatedAt).ToList();
            lock (_lock)
            {
                if (TeamTaskJson.SameTasks(sorted, _tasks)) return;
                _tasks = sorted;
                if (SelectedTaskID == null || !_tasks.Any(t => t.Id == SelectedTaskID)) SelectedTaskID = _tasks.Count > 0 ? _tasks[0].Id : null;
            }
            Persist(false);
        }

        void Update(string taskID, string ev, Action<TeamTask> mutation)
        {
            TeamTask changed = null;
            lock (_lock)
            {
                var t = _tasks.FirstOrDefault(x => x.Id == taskID);
                if (t == null) return;
                mutation(t);
                t.UpdatedAt = DateTime.UtcNow;
                t.UpdatedBy = Actor;
                _tasks = _tasks.OrderByDescending(x => x.UpdatedAt).ToList();
                changed = t.Clone();
            }
            Persist(true);
            if (ev != null) Notify(ev, changed);
        }

        void Notify(string ev, TeamTask task)
        {
            var integ = Integrations;
            Task.Run(() => integ.Publish(ev, task));
        }

        void Persist(bool broadcast)
        {
            List<TeamTask> snapshot;
            string ws;
            lock (_lock) { snapshot = _tasks.Select(t => t.Clone()).ToList(); ws = WorkspacePath; }
            if (broadcast) { var lc = LocalChange; if (lc != null) lc(snapshot); }
            if (ws != null)
            {
                try
                {
                    string path = TaskFiles.Managed(ws, FileName);
                    Directory.CreateDirectory(Path.GetDirectoryName(path));
                    _persistedAt = DateTime.UtcNow;
                    string tmp = path + ".tmp";
                    File.WriteAllText(tmp, TeamTaskJson.Document(snapshot), new UTF8Encoding(false));
                    if (File.Exists(path)) File.Replace(tmp, path, null, true); else File.Move(tmp, path);
                    _persistedAt = DateTime.UtcNow;
                    LastError = null;
                }
                catch (IOException ex) { LastError = "Unable to save shared tasks: " + ex.Message; }
                catch (UnauthorizedAccessException ex) { LastError = "Unable to save shared tasks: " + ex.Message; }
            }
            Fire();
        }
    }

    /// <summary>TeamIntegrationService: the Team Tasks / agent-context switches and the Slack / Microsoft Teams webhooks
    /// (https only, allow-listed hosts, DPAPI-sealed like the Mac's Keychain).</summary>
    public class TeamIntegrations
    {
        public static readonly string[] All = { "slack", "teams" };
        const string DefaultsKey = "microcode.team-integrations.v1";
        static readonly HttpClient Http = new HttpClient { Timeout = TimeSpan.FromSeconds(12) };
        static readonly JavaScriptSerializer Js = new JavaScriptSerializer();
        /// <summary>Tests point webhooks at a loopback server; the product never sets this.</summary>
        public static bool AllowLoopbackForTests;

        public bool TeamTasksEnabled = true, AgentContextEnabled = true;
        public Dictionary<string, bool> Enabled = new Dictionary<string, bool>();
        public string LastResult;
        public event Action Changed;

        public TeamIntegrations()
        {
            var raw = Defaults.Str(DefaultsKey, null);
            if (raw == null) return;
            try
            {
                var d = Js.DeserializeObject(raw) as Dictionary<string, object>;
                if (d == null) return;
                object v;
                if (d.TryGetValue("teamTasksEnabled", out v) && v is bool) TeamTasksEnabled = (bool)v;
                if (d.TryGetValue("agentContextEnabled", out v) && v is bool) AgentContextEnabled = (bool)v;
                var en = d.TryGetValue("enabled", out v) ? v as Dictionary<string, object> : null;
                if (en != null) foreach (var kv in en) if (kv.Value is bool) Enabled[kv.Key] = (bool)kv.Value;
            }
            catch (ArgumentException) { } catch (InvalidOperationException) { }
        }

        public static string Title(string integration) { return integration == "slack" ? "Slack" : "Microsoft Teams"; }
        static string SecretKey(string integration) { return "teamWebhook:TEAM_WEBHOOK_" + integration.ToUpperInvariant(); }
        string Secret(string integration) { return Dpapi.Unprotect(Defaults.Str(SecretKey(integration), null)); }

        void Persist()
        {
            Defaults.Set(DefaultsKey, Js.Serialize(new Dictionary<string, object> { { "teamTasksEnabled", TeamTasksEnabled }, { "agentContextEnabled", AgentContextEnabled }, { "enabled", Enabled.ToDictionary(k => k.Key, k => (object)k.Value) } }));
            var c = Changed; if (c != null) c();
        }

        public void SetTeamTasksEnabled(bool v) { TeamTasksEnabled = v; Persist(); }
        public void SetAgentContextEnabled(bool v) { AgentContextEnabled = v; Persist(); }
        public bool IsConfigured(string integration) { return Secret(integration) != null; }
        public bool IsEnabled(string integration) { bool e; return Enabled.TryGetValue(integration, out e) && e && IsConfigured(integration); }

        public bool SaveWebhook(string rawUrl, string integration)
        {
            rawUrl = (rawUrl ?? "").Trim();
            if (!Validate(rawUrl, integration)) { LastResult = "Invalid " + Title(integration) + " webhook URL."; Persist(); return false; }
            Defaults.Set(SecretKey(integration), Dpapi.Protect(rawUrl));
            Enabled[integration] = true;
            LastResult = Title(integration) + " is connected.";
            Persist();
            return true;
        }

        public void SetEnabled(bool value, string integration)
        {
            if (value && !IsConfigured(integration)) { LastResult = "Add a " + Title(integration) + " webhook first."; Persist(); return; }
            Enabled[integration] = value;
            Persist();
        }

        public void Remove(string integration)
        {
            Defaults.Remove(SecretKey(integration));
            Enabled[integration] = false;
            LastResult = Title(integration) + " disconnected.";
            Persist();
        }

        public async Task Test(string integration)
        {
            string url = Secret(integration);
            if (url == null) { LastResult = "Add a " + Title(integration) + " webhook first."; Persist(); return; }
            try { await Send("MicroCode connected. Team task notifications are ready.", url); LastResult = "Test delivered to " + Title(integration) + "."; }
            catch (Exception ex) { if (!(ex is HttpRequestException || ex is TaskCanceledException)) throw; LastResult = Title(integration) + " test failed: " + ex.Message; }
            Persist();
        }

        public async Task Publish(string ev, TeamTask task)
        {
            var targets = All.Where(IsEnabled).ToList();
            if (targets.Count == 0) return;
            string text = Summary(ev, task);
            foreach (var target in targets)
            {
                string url = Secret(target);
                if (url == null) continue;
                try { await Send(text, url); LastResult = "Task update sent to " + Title(target) + "."; }
                catch (Exception ex) { if (!(ex is HttpRequestException || ex is TaskCanceledException)) throw; LastResult = "Could not notify " + Title(target) + ": " + ex.Message; }
            }
            Persist();
        }

        static async Task Send(string text, string url)
        {
            using (var resp = await Http.PostAsync(url, new StringContent(Js.Serialize(new Dictionary<string, object> { { "text", text } }), Encoding.UTF8, "application/json")))
                if ((int)resp.StatusCode < 200 || (int)resp.StatusCode >= 300) throw new HttpRequestException("HTTP " + (int)resp.StatusCode);
        }

        public static bool Validate(string rawUrl, string integration)
        {
            Uri u;
            if (!Uri.TryCreate(rawUrl ?? "", UriKind.Absolute, out u)) return false;
            string host = u.Host.ToLowerInvariant();
            if (AllowLoopbackForTests && u.Scheme == "http" && host == "127.0.0.1") return true;
            if (u.Scheme != "https" || host.Length == 0) return false;
            if (host == "localhost" || host.StartsWith("127.") || host.StartsWith("10.") || host.StartsWith("192.168.") || host == "::1" || host == "[::1]") return false;
            if (integration == "slack") return host == "hooks.slack.com";
            return new[] { ".webhook.office.com", ".office.com", ".logic.azure.com", ".powerplatform.com", ".microsoft.com" }.Any(s => host.EndsWith(s));
        }

        public static string Summary(string ev, TeamTask task)
        {
            string objective = task.Objective.Length == 0 ? "No objective recorded" : (task.Objective.Length > 1200 ? task.Objective.Substring(0, 1200) : task.Objective);
            return "MicroCode team task " + ev + "\n• " + task.Title + "\nStatus: " + TeamTaskStatusInfo.Label(task.Status) + " · Owner: " + task.Owner + "\nObjective: " + objective;
        }
    }
}
