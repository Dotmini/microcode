// Autonomous agent loop (AgentService + AgentToolBox + ToolApprovalManager): streams OpenAI-compatible chat/completions or
// Anthropic Messages with native tool calls (an XML <tool_call> bridge for models without function calling), runs the
// workspace-sandboxed tools, asks for approval per mode (Safe / Smart / Full Auto), honours Scope Lock and keeps a
// checkpoint of every file it edits so a turn can be reverted.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using MicroCode.Core;

namespace MicroCode.Views
{
    public class ToolStep
    {
        public string Name, Target, Result, Path;
        public bool Ok = true;
        /// <summary>Offset into the reply text where the call happened (-1: show before the text).</summary>
        public int At = -1;
        public int Added, Removed, Lines;
        /// <summary>File holding the pre-edit content; Existed=false when the agent created the file.</summary>
        public string Checkpoint;
        public bool Existed = true;
        /// <summary>Snapshot of the file right after this edit (for the diff card and Restore).</summary>
        public string After;
        public bool Reverted;
        public DateTime Time = DateTime.Now;
        /// <summary>How the call was allowed: auto (mode / always-allow), approved, rejected, timeout, blocked.</summary>
        public string Approval = "auto";
    }

    public class AgentCallbacks
    {
        public Action<string> OnText, OnThinking, OnActivity;
        public Action<ToolStep> OnStepStart, OnStep;
        public Func<ToolStep, Dictionary<string, object>, Task<bool>> Approve;
    }

    public class AgentResult
    {
        public string Text = "", Thinking = "", Model;
        public List<ToolStep> Steps = new List<ToolStep>();
        /// <summary>Token usage summed over every model call of the turn; Estimated when the API did not report usage.</summary>
        public int InputTokens, OutputTokens, Requests;
        public bool Estimated;
    }

    public static class AgentRunner
    {
        static readonly HttpClient Http = new HttpClient { Timeout = TimeSpan.FromMinutes(15) };
        static JavaScriptSerializer Js { get { return DJ.S; } }

        public static bool AgentModeEnabled { get { return Defaults.Bool("agentMode", true); } }

        // ── isolated runs (Consensus sandbox, PNS worktrees) ────────────────────
        class Isolation { public string Root, Workspace; }
        /// <summary>Set for the duration of an isolated run: tools resolve paths against the isolated copy instead of the open workspace.</summary>
        static readonly AsyncLocal<Isolation> Isolated = new AsyncLocal<Isolation>();
        static bool InIsolation { get { return Isolated.Value != null; } }

        /// <summary>Runs an agent turn whose tools work in <paramref name="root"/> — a sandbox or worktree copy of <paramref name="workspace"/>.
        /// Paths cannot leave the copy, .microcode/*.md stay inside it, no checkpoints are written to the data folder, and Scope Lock
        /// is checked against the real workspace file the copy mirrors.</summary>
        public static async Task<AgentResult> RunIsolated(string root, string workspace, List<ChatMessage> history, string system, bool readOnly, AgentCallbacks cb, CancellationToken ct)
        {
            Isolated.Value = new Isolation { Root = System.IO.Path.GetFullPath(root).TrimEnd('\\'), Workspace = workspace };
            return await Run(history, system, true, readOnly, null, cb, ct);
        }

        /// <summary>Runs one tool inside an isolated copy (engine-run commands: Auditor tests, PNS verification). Errors come back as "Error: …".</summary>
        public static string ExecuteIsolated(string root, string workspace, string tool, Dictionary<string, object> args, ToolStep step, CancellationToken ct)
        {
            var prev = Isolated.Value;
            Isolated.Value = new Isolation { Root = System.IO.Path.GetFullPath(root).TrimEnd('\\'), Workspace = workspace };
            try
            {
                string name = Normalize(tool);
                step.Name = name; step.Target = Target(name, args);
                return Execute(name, args, step, null, ct);
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex) { return "Error: " + ex.Message; }
            finally { Isolated.Value = prev; }
        }

        // ── tool schemas (AgentToolBox canonical names) ─────────────────────────
        static Dictionary<string, object> P(string type, string desc) { return new Dictionary<string, object> { { "type", type }, { "description", desc } }; }
        static Dictionary<string, object> Tool(string name, string desc, Dictionary<string, object> props, params string[] required)
        {
            return new Dictionary<string, object> { { "name", name }, { "description", desc }, { "parameters", new Dictionary<string, object> { { "type", "object" }, { "properties", props }, { "required", required } } } };
        }

        public static List<Dictionary<string, object>> ToolSchemas(bool readOnly)
        {
            var list = new List<Dictionary<string, object>>
            {
                Tool("list_directory_tree", "List files and folders under a workspace directory (recursively, up to `depth` levels, default 2).",
                    new Dictionary<string, object> { { "path", P("string", "Directory relative to the workspace root ('.' for the root).") }, { "depth", P("integer", "How many levels to descend (1-5).") } }, "path"),
                Tool("file_read", "Read a text file from the workspace. For large files pass 1-based start_line / end_line.",
                    new Dictionary<string, object> { { "path", P("string", "File path relative to the workspace root.") }, { "start_line", P("integer", "First line to read (1-based).") }, { "end_line", P("integer", "Last line to read (inclusive).") } }, "path"),
                Tool("grep_search", "Search file contents in the workspace with a regular expression (case-insensitive). Returns path:line: text matches.",
                    new Dictionary<string, object> { { "query", P("string", "Regular expression to search for.") }, { "path", P("string", "Optional sub-directory to search in.") }, { "include", P("string", "Optional file glob filter such as *.py or *.cs.") } }, "query"),
                Tool("file_search", "Find files by name with a glob pattern such as *.json, **/test_*.py or *config*.",
                    new Dictionary<string, object> { { "pattern", P("string", "Glob pattern matched against workspace-relative paths.") } }, "pattern"),
                Tool("read_skill", "Load the full instructions of an available skill by name.",
                    new Dictionary<string, object> { { "name", P("string", "Exact skill name from the Available skills list.") } }, "name")
            };
            if (!readOnly)
            {
                list.Add(Tool("file_write", "Create a new file or overwrite an existing one with the complete new content.",
                    new Dictionary<string, object> { { "path", P("string", "File path relative to the workspace root.") }, { "content", P("string", "Complete file content.") } }, "path", "content"));
                list.Add(Tool("replace_in_file", "Edit a file by replacing an exact snippet. old_string must match the file exactly (whitespace included) and be unique unless replace_all is true. Prefer this over file_write for small edits to existing files.",
                    new Dictionary<string, object> { { "path", P("string", "File path relative to the workspace root.") }, { "old_string", P("string", "Exact text to replace.") }, { "new_string", P("string", "Replacement text.") }, { "replace_all", P("boolean", "Replace every occurrence.") } }, "path", "old_string", "new_string"));
                list.Add(Tool("shell", "Run a command in the workspace on Windows (cmd.exe /c). Returns the exit code and output. Use it for builds, tests, git and package managers; never for interactive programs.",
                    new Dictionary<string, object> { { "command", P("string", "Command line to execute.") }, { "timeout_seconds", P("integer", "Kill the command after this many seconds (default 120, max 600).") } }, "command"));
            }
            return list;
        }

        /// <summary>AgentToolBox.normalizeToolName: map the names other agents use onto ours.</summary>
        public static string Normalize(string raw)
        {
            string l = (raw ?? "").Trim().ToLowerInvariant();
            switch (l)
            {
                case "read_file": case "view_file": case "read": case "cat": case "open_file_content": case "get_file_contents": return "file_read";
                case "write_file": case "write_to_file": case "create_file": case "write": case "save_file": case "overwrite_file": return "file_write";
                case "edit_file": case "str_replace": case "str_replace_editor": case "str_replace_based_edit_tool": case "edit": case "replace": case "modify_file": return "replace_in_file";
                case "bash": case "run_terminal_cmd": case "execute_command": case "run_command": case "terminal": case "exec": case "cmd": case "sh": case "run_shell": case "shell_command": case "powershell": return "shell";
                case "list_dir": case "list_directory": case "ls": case "list_files": case "dir": case "tree": return "list_directory_tree";
                case "grep": case "ripgrep": case "rg": case "search_files": case "search_in_files": case "code_search": case "grep_files": case "search_text": case "codebase_search": return "grep_search";
                case "glob": case "find_by_name": case "find_files": case "search_by_name": case "glob_search": return "file_search";
                default: return (raw ?? "").Trim();
            }
        }

        static bool IsEdit(string n) { return n == "file_write" || n == "replace_in_file"; }

        // ── run ────────────────────────────────────────────────────────────────
        class Call { public string Id, Name; public Dictionary<string, object> Args; }
        class Turn { public string Text = "", Thinking = ""; public List<Call> Calls = new List<Call>(); public object Assistant; public bool Xml; public int InTok = -1, OutTok = -1; }

        /// <summary>Runs one agent turn (with the tool loop when tools are enabled) and returns the final reply.</summary>
        public static async Task<AgentResult> Run(List<ChatMessage> history, string system, bool tools, bool readOnly, string sessionId, AgentCallbacks cb, CancellationToken ct)
        {
            var ep = await AIEndpoint.Resolve(false);
            var res = new AgentResult { Model = ep.Model };
            bool anthropic = ep.Format == "anthropic";
            bool xml = XmlBridge.Contains(ep.BaseUrl + "::" + ep.Model);
            var msgs = BuildMessages(history, anthropic, ep);
            var schemas = tools ? ToolSchemas(readOnly) : null;
            int maxIter = (int)Defaults.Num("agentMaxIterations", 0); if (maxIter <= 0) maxIter = 500;
            bool refreshed = false;
            for (int iter = 0; iter < maxIter; iter++)
            {
                ct.ThrowIfCancellationRequested();
                Say(cb.OnActivity, iter == 0 ? "Thinking…" : "Working…");
                Turn turn = null;
                AIException fail = null;
                try { turn = await StreamTurn(ep, system, msgs, schemas, xml, cb, ct); }
                catch (AIException ex) { fail = ex; }
                if (fail != null)
                {
                    // expired Dotmini session: refresh the token once and retry the same step
                    if ((fail.Status == 401 || fail.Status == 403) && ep.IsCloud && !refreshed) { refreshed = true; ep = await AIEndpoint.Resolve(true); iter--; continue; }
                    // model without function calling: retry over the XML tool bridge
                    bool toolsRejected = fail.Status == 400 && schemas != null && !xml && Regex.IsMatch(fail.Detail ?? fail.Message, "tool|function", RegexOptions.IgnoreCase);
                    if (toolsRejected) { xml = true; XmlBridge.Add(ep.BaseUrl + "::" + ep.Model); iter--; continue; }
                    throw fail;
                }
                // usage: what the API reported, or a chars/4 estimate when it reported nothing
                res.Requests++;
                if (turn.InTok >= 0 || turn.OutTok >= 0) { res.InputTokens += Math.Max(0, turn.InTok); res.OutputTokens += Math.Max(0, turn.OutTok); }
                else
                {
                    res.Estimated = true;
                    try { res.InputTokens += (system.Length + Js.Serialize(msgs).Length) / 4; } catch { }
                    res.OutputTokens += (turn.Text.Length + turn.Thinking.Length + turn.Calls.Sum(c => Js.Serialize(c.Args).Length)) / 4;
                }
                if (turn.Thinking.Length > 0) res.Thinking += (res.Thinking.Length > 0 ? "\n\n" : "") + turn.Thinking;
                if (turn.Text.Trim().Length > 0)
                {
                    if (res.Text.Length > 0) { res.Text += "\n\n"; Say(cb.OnText, "\n\n"); }
                    res.Text += turn.Xml ? XmlStrip(turn.Text) : turn.Text;
                }
                if (turn.Calls.Count == 0 || schemas == null) return res;

                if (turn.Xml)
                {
                    msgs.Add(new Dictionary<string, object> { { "role", "assistant" }, { "content", turn.Text } });
                }
                else msgs.Add(turn.Assistant);
                var anthropicResults = new List<object>();
                var xmlResults = new StringBuilder();
                foreach (var call in turn.Calls)
                {
                    ct.ThrowIfCancellationRequested();
                    string name = Normalize(call.Name);
                    var step = new ToolStep { Name = name, Target = Target(name, call.Args), Path = Arg(call.Args, "path"), At = res.Text.Length };
                    string result;
                    if (readOnly && (IsEdit(name) || name == "shell")) { result = "Error: Plan mode is read-only. Describe this change in the plan instead of making it."; step.Ok = false; step.Approval = "blocked"; }
                    else if (!await Approve(step, call.Args, cb, ct)) { result = "User denied this tool call."; step.Ok = false; }
                    else
                    {
                        Say(cb.OnActivity, Headline(step) + "…");
                        if (cb.OnStepStart != null) cb.OnStepStart(step);
                        var args = call.Args;
                        try { result = await Task.Run(() => Execute(name, args, step, sessionId, ct), ct); }
                        catch (OperationCanceledException) { throw; }
                        catch (Exception ex) { result = "Error: " + ex.Message; }
                        if (result.StartsWith("Error:")) step.Ok = false;
                    }
                    step.Result = result.Length > 6000 ? result.Substring(0, 6000) + "\n…" : result;
                    res.Steps.Add(step);
                    if (cb.OnStep != null) cb.OnStep(step);
                    string forModel = result.Length > 60000 ? result.Substring(0, 60000) + "\n[truncated]" : result;
                    if (turn.Xml) xmlResults.Append("<tool_response name=\"" + name + "\">\n" + forModel + "\n</tool_response>\n\n");
                    else if (anthropic) anthropicResults.Add(new Dictionary<string, object> { { "type", "tool_result" }, { "tool_use_id", call.Id }, { "content", forModel }, { "is_error", !step.Ok } });
                    else msgs.Add(new Dictionary<string, object> { { "role", "tool" }, { "tool_call_id", call.Id }, { "content", forModel } });
                }
                if (turn.Xml) msgs.Add(new Dictionary<string, object> { { "role", "user" }, { "content", xmlResults.ToString().Trim() + "\n\nContinue the task." } });
                else if (anthropic) msgs.Add(new Dictionary<string, object> { { "role", "user" }, { "content", anthropicResults } });
            }
            res.Text += (res.Text.Length > 0 ? "\n\n" : "") + "Reached the maximum tool iteration safety limit (" + maxIter + "). Ask me to continue to keep going.";
            return res;
        }

        static void Say(Action<string> a, string s) { if (a != null) a(s); }

        // ── approval (ToolApprovalManager) ─────────────────────────────────────
        static readonly HashSet<string> AlwaysAllowed = new HashSet<string> { "file_read", "list_directory_tree" };
        public static void AlwaysAllow(string tool) { lock (AlwaysAllowed) AlwaysAllowed.Add(tool); }

        public static string Risk(ToolStep s)
        {
            switch (s.Name)
            {
                case "shell":
                    string c = (s.Target ?? "").ToLowerInvariant();
                    if (Regex.IsMatch(c, @"rm\s+-rf|rmdir\s+/s|rd\s+/s|del\s+/s|del\s+/q|format\s+[a-z]:|drop\s+(table|database)|git\s+push\s+.*--force|reg\s+delete|shutdown")) return "critical";
                    return "dangerous";
                case "file_write": case "replace_in_file": return "moderate";
                default: return "safe";
            }
        }

        static async Task<bool> Approve(ToolStep step, Dictionary<string, object> args, AgentCallbacks cb, CancellationToken ct)
        {
            string mode = Defaults.Bool("agentAutoApproveTools", false) ? "yolo" : Defaults.Str("toolApprovalMode", "smart");
            if (mode == "yolo") { step.Approval = "auto"; return true; }
            string risk = Risk(step);
            bool allowed; lock (AlwaysAllowed) allowed = AlwaysAllowed.Contains(step.Name);
            if (mode != "safe" && (allowed || (mode == "smart" && risk == "safe"))) { step.Approval = "auto"; return true; }
            if (cb.Approve == null) { step.Approval = "rejected"; return false; }
            var decision = cb.Approve(step, args);
            var timeout = Task.Delay(TimeSpan.FromSeconds(60), ct);
            var done = await Task.WhenAny(decision, timeout);
            ct.ThrowIfCancellationRequested();
            bool ok = done == decision && decision.Result;
            step.Approval = done != decision ? "timeout" : ok ? "approved" : "rejected";
            return ok;
        }

        // ── messages ───────────────────────────────────────────────────────────
        static readonly HashSet<string> ImageExt = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp" };
        public static bool IsImage(string path) { return ImageExt.Contains(System.IO.Path.GetExtension(path ?? "")); }

        static string Mime(string path)
        {
            switch (System.IO.Path.GetExtension(path).ToLowerInvariant()) { case ".jpg": case ".jpeg": return "image/jpeg"; case ".gif": return "image/gif"; case ".webp": return "image/webp"; case ".bmp": return "image/bmp"; default: return "image/png"; }
        }

        /// <summary>User text plus attached files: text files are inlined (bounded), images become vision parts.</summary>
        static List<object> BuildMessages(List<ChatMessage> history, bool anthropic, AIEndpoint ep)
        {
            var msgs = new List<object>();
            int lastUser = history.FindLastIndex(m => m.Role == "user");
            for (int i = 0; i < history.Count; i++)
            {
                var m = history[i];
                if (m.Role != "user" && m.Role != "assistant") continue;
                if (m.Role == "assistant")
                {
                    string text = AgentBlocks.StripThoughts(m.Content ?? "").Trim();
                    if (text.Length == 0) text = m.Steps.Count > 0 ? "(used tools: " + string.Join(", ", m.Steps.Select(s => Headline(s))) + ")" : "(no reply)";
                    msgs.Add(new Dictionary<string, object> { { "role", "assistant" }, { "content", text } });
                    continue;
                }
                var sb = new StringBuilder(m.Content ?? "");
                var images = new List<string>();
                if (m.Attachments != null)
                    foreach (var f in m.Attachments)
                    {
                        try
                        {
                            if (!File.Exists(f)) continue;
                            if (IsImage(f)) { if (i == lastUser || history.Count - i < 6) images.Add(f); else sb.Append("\n\n[Image attached earlier: " + System.IO.Path.GetFileName(f) + "]"); continue; }
                            var info = new FileInfo(f);
                            string body = info.Length > 400 * 1024 ? "(file is " + (info.Length / 1024) + " KB — too large to inline; use file_read with line ranges if it is in the workspace)" : File.ReadAllText(f);
                            if (body.Length > 120000) body = body.Substring(0, 120000) + "\n[truncated]";
                            sb.Append("\n\n[ATTACHED FILE: " + f + "]\n```" + LangTag(f) + "\n" + body + "\n```");
                        }
                        catch { }
                    }
                if (images.Count == 0) { msgs.Add(new Dictionary<string, object> { { "role", "user" }, { "content", sb.ToString() } }); continue; }
                var parts = new List<object>();
                foreach (var img in images)
                {
                    string b64 = Convert.ToBase64String(File.ReadAllBytes(img));
                    if (anthropic) parts.Add(new Dictionary<string, object> { { "type", "image" }, { "source", new Dictionary<string, object> { { "type", "base64" }, { "media_type", Mime(img) }, { "data", b64 } } } });
                    else parts.Add(new Dictionary<string, object> { { "type", "image_url" }, { "image_url", new Dictionary<string, object> { { "url", "data:" + Mime(img) + ";base64," + b64 } } } });
                }
                parts.Add(new Dictionary<string, object> { { "type", "text" }, { "text", sb.Length > 0 ? sb.ToString() : "(see attached image)" } });
                msgs.Add(new Dictionary<string, object> { { "role", "user" }, { "content", parts } });
            }
            return msgs;
        }

        static string LangTag(string f)
        {
            string e = System.IO.Path.GetExtension(f).TrimStart('.').ToLowerInvariant();
            return e == "py" ? "python" : e == "js" ? "javascript" : e == "ts" ? "typescript" : e == "cs" ? "csharp" : e == "md" ? "markdown" : e;
        }

        // ── streaming one model turn ───────────────────────────────────────────
        static async Task<Turn> StreamTurn(AIEndpoint ep, string system, List<object> msgs, List<Dictionary<string, object>> schemas, bool xml, AgentCallbacks cb, CancellationToken ct)
        {
            bool anthropic = ep.Format == "anthropic";
            string sys = xml && schemas != null ? system + "\n\n" + XmlInstructions(schemas) : system;
            HttpRequestMessage req;
            if (anthropic)
            {
                var body = new Dictionary<string, object> { { "model", ep.Model }, { "max_tokens", MaxTokens(ep.Model) }, { "system", sys }, { "messages", msgs }, { "stream", true } };
                if (schemas != null && !xml) body["tools"] = schemas.Select(s => new Dictionary<string, object> { { "name", s["name"] }, { "description", s["description"] }, { "input_schema", s["parameters"] } }).ToList();
                req = new HttpRequestMessage(HttpMethod.Post, ep.BaseUrl + "/messages") { Content = DJ.Body(body) };
            }
            else
            {
                var all = new List<object> { new Dictionary<string, object> { { "role", "system" }, { "content", sys } } };
                all.AddRange(msgs);
                var body = new Dictionary<string, object> { { "model", ep.Model }, { "messages", all }, { "stream", true } };
                if (schemas != null && !xml) body["tools"] = schemas.Select(s => new Dictionary<string, object> { { "type", "function" }, { "function", s } }).ToList();
                req = new HttpRequestMessage(HttpMethod.Post, ep.BaseUrl + "/chat/completions") { Content = DJ.Body(body) };
            }
            ep.Authorize(req, "Agent");
            using (var resp = await Http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, ct))
            {
                if (!resp.IsSuccessStatusCode) throw AIException.FromHttp((int)resp.StatusCode, await resp.Content.ReadAsStringAsync(), ep);
                var mediaType = resp.Content.Headers.ContentType != null ? resp.Content.Headers.ContentType.MediaType : "";
                if (mediaType == "application/json") return FromJson(await resp.Content.ReadAsStringAsync(), anthropic, xml, schemas, cb, ep);
                using (var s = await resp.Content.ReadAsStreamAsync())
                using (var r = new StreamReader(s, Encoding.UTF8))
                {
                    var turn = anthropic ? await ReadAnthropic(r, cb, ct, ep) : await ReadOpenAI(r, cb, ct, ep);
                    if (schemas != null && turn.Calls.Count == 0 && turn.Text.Contains("<tool_call>")) { turn.Calls = XmlCalls(turn.Text); turn.Xml = turn.Calls.Count > 0; }
                    return turn;
                }
            }
        }

        static int MaxTokens(string model)
        {
            // AIClient.maxOutputTokens: Claude 3.x caps at 8K output; newer Claude models take the 16K default.
            return (model ?? "").ToLowerInvariant().Contains("claude-3") ? 8192 : 16384;
        }

        class Acc { public string Id = "", Name = "", Type = ""; public StringBuilder Args = new StringBuilder(), Text = new StringBuilder(); }

        static async Task<Turn> ReadOpenAI(StreamReader r, AgentCallbacks cb, CancellationToken ct, AIEndpoint ep)
        {
            var turn = new Turn();
            var text = new StringBuilder(); var think = new StringBuilder();
            var calls = new SortedDictionary<int, Acc>();
            string line;
            while ((line = await r.ReadLineAsync()) != null)
            {
                ct.ThrowIfCancellationRequested();
                if (!line.StartsWith("data:")) continue;
                string data = line.Substring(5).Trim();
                if (data == "[DONE]") break;
                var o = DJ.Obj(data);
                if (o == null) continue;
                var err = DJ.Child(o, "error");
                if (err != null) throw new AIException(0, "AI service error: " + (DJ.Str(err, "message") ?? DJ.Ser(err)), "ai") { Detail = DJ.Str(err, "message") };
                var usage = DJ.Child(o, "usage");
                if (usage != null)
                {
                    var pt = DJ.Num(usage, "prompt_tokens"); var ctk = DJ.Num(usage, "completion_tokens");
                    if (pt.HasValue) turn.InTok = (int)pt.Value;
                    if (ctk.HasValue) turn.OutTok = (int)ctk.Value;
                }
                var choices = DJ.Arr(o, "choices");
                if (choices == null || choices.Count == 0) continue;
                var ch = choices[0] as Dictionary<string, object>;
                var delta = DJ.Child(ch, "delta") ?? DJ.Child(ch, "message");
                if (delta == null) continue;
                string c = DJ.Str(delta, "content");
                if (!string.IsNullOrEmpty(c)) { text.Append(c); Say(cb.OnText, c); }
                string rc = DJ.Str(delta, "reasoning_content") ?? DJ.Str(delta, "reasoning");
                if (!string.IsNullOrEmpty(rc)) { think.Append(rc); Say(cb.OnThinking, rc); }
                var tcs = DJ.Arr(delta, "tool_calls");
                if (tcs == null) continue;
                foreach (var item in tcs)
                {
                    var tc = item as Dictionary<string, object>;
                    if (tc == null) continue;
                    int idx = (int)(DJ.Num(tc, "index") ?? calls.Count);
                    Acc acc;
                    if (!calls.TryGetValue(idx, out acc)) calls[idx] = acc = new Acc();
                    string id = DJ.Str(tc, "id"); if (!string.IsNullOrEmpty(id)) acc.Id = id;
                    var fn = DJ.Child(tc, "function");
                    string nm = DJ.Str(fn, "name"); if (!string.IsNullOrEmpty(nm) && acc.Name.Length == 0) acc.Name = nm;
                    object av; if (fn != null && fn.TryGetValue("arguments", out av) && av != null) acc.Args.Append(av is string ? (string)av : Js.Serialize(av));
                }
            }
            turn.Text = text.ToString(); turn.Thinking = think.ToString();
            var toolCalls = new List<object>();
            foreach (var kv in calls)
            {
                var a = kv.Value;
                if (a.Name.Length == 0) continue;
                if (a.Id.Length == 0) a.Id = "call_" + Guid.NewGuid().ToString("N").Substring(0, 12);
                string argText = a.Args.Length == 0 ? "{}" : a.Args.ToString();
                turn.Calls.Add(new Call { Id = a.Id, Name = a.Name, Args = ParseArgs(argText) });
                toolCalls.Add(new Dictionary<string, object> { { "id", a.Id }, { "type", "function" }, { "function", new Dictionary<string, object> { { "name", a.Name }, { "arguments", argText } } } });
            }
            var msg = new Dictionary<string, object> { { "role", "assistant" }, { "content", turn.Text.Length > 0 || toolCalls.Count == 0 ? (object)turn.Text : null } };
            if (toolCalls.Count > 0) msg["tool_calls"] = toolCalls;
            if (turn.Thinking.Length > 0 && ep.BaseUrl.Contains("deepseek")) msg["reasoning_content"] = turn.Thinking;
            turn.Assistant = msg;
            return turn;
        }

        static async Task<Turn> ReadAnthropic(StreamReader r, AgentCallbacks cb, CancellationToken ct, AIEndpoint ep)
        {
            var turn = new Turn();
            var blocks = new SortedDictionary<int, Acc>();
            var think = new StringBuilder();
            string line;
            while ((line = await r.ReadLineAsync()) != null)
            {
                ct.ThrowIfCancellationRequested();
                if (!line.StartsWith("data:")) continue;
                var o = DJ.Obj(line.Substring(5).Trim());
                if (o == null) continue;
                string type = DJ.Str(o, "type");
                int idx = (int)(DJ.Num(o, "index") ?? 0);
                if (type == "message_start")
                {
                    var u = DJ.Child(DJ.Child(o, "message"), "usage");
                    if (u != null) turn.InTok = (int)((DJ.Num(u, "input_tokens") ?? 0) + (DJ.Num(u, "cache_read_input_tokens") ?? 0) + (DJ.Num(u, "cache_creation_input_tokens") ?? 0));
                }
                else if (type == "message_delta")
                {
                    var u = DJ.Child(o, "usage");
                    if (u != null && DJ.Num(u, "output_tokens").HasValue) turn.OutTok = (int)DJ.Num(u, "output_tokens").Value;
                }
                if (type == "content_block_start")
                {
                    var b = DJ.Child(o, "content_block");
                    var acc = new Acc { Type = DJ.Str(b, "type") ?? "text", Id = DJ.Str(b, "id") ?? "", Name = DJ.Str(b, "name") ?? "" };
                    string t0 = DJ.Str(b, "text"); if (!string.IsNullOrEmpty(t0)) { acc.Text.Append(t0); Say(cb.OnText, t0); }
                    blocks[idx] = acc;
                }
                else if (type == "content_block_delta")
                {
                    var d = DJ.Child(o, "delta");
                    Acc acc; if (!blocks.TryGetValue(idx, out acc)) blocks[idx] = acc = new Acc { Type = "text" };
                    string dt = DJ.Str(d, "type");
                    if (dt == "text_delta") { string tx = DJ.Str(d, "text") ?? ""; acc.Text.Append(tx); Say(cb.OnText, tx); }
                    else if (dt == "input_json_delta") acc.Args.Append(DJ.Str(d, "partial_json") ?? "");
                    else if (dt == "thinking_delta") { string th = DJ.Str(d, "thinking") ?? ""; think.Append(th); Say(cb.OnThinking, th); }
                }
                else if (type == "error")
                {
                    var e = DJ.Child(o, "error");
                    string m = DJ.Str(e, "message") ?? "stream error";
                    throw new AIException(DJ.Str(e, "type") == "overloaded_error" ? 529 : 0, "AI service error: " + m, "ai") { Detail = m };
                }
                else if (type == "message_stop") break;
            }
            var content = new List<object>();
            var text = new StringBuilder();
            foreach (var kv in blocks)
            {
                var a = kv.Value;
                if (a.Type == "tool_use")
                {
                    var args = ParseArgs(a.Args.Length == 0 ? "{}" : a.Args.ToString());
                    turn.Calls.Add(new Call { Id = a.Id, Name = a.Name, Args = args });
                    content.Add(new Dictionary<string, object> { { "type", "tool_use" }, { "id", a.Id }, { "name", a.Name }, { "input", args } });
                }
                else if (a.Type == "text" && a.Text.Length > 0)
                {
                    text.Append(a.Text);
                    content.Add(new Dictionary<string, object> { { "type", "text" }, { "text", a.Text.ToString() } });
                }
            }
            turn.Text = text.ToString(); turn.Thinking = think.ToString();
            if (content.Count == 0) content.Add(new Dictionary<string, object> { { "type", "text" }, { "text", "(no output)" } });
            turn.Assistant = new Dictionary<string, object> { { "role", "assistant" }, { "content", content } };
            return turn;
        }

        /// <summary>Some gateways ignore stream=true and answer with one JSON body.</summary>
        static Turn FromJson(string raw, bool anthropic, bool xml, List<Dictionary<string, object>> schemas, AgentCallbacks cb, AIEndpoint ep)
        {
            var o = DJ.Obj(raw) ?? new Dictionary<string, object>();
            var turn = new Turn();
            var usage = DJ.Child(o, "usage");
            if (usage != null)
            {
                var i1 = DJ.Num(usage, "prompt_tokens") ?? DJ.Num(usage, "input_tokens");
                var o1 = DJ.Num(usage, "completion_tokens") ?? DJ.Num(usage, "output_tokens");
                if (i1.HasValue) turn.InTok = (int)i1.Value;
                if (o1.HasValue) turn.OutTok = (int)o1.Value;
            }
            if (anthropic)
            {
                var content = DJ.Arr(o, "content") ?? new System.Collections.ArrayList();
                foreach (var item in content)
                {
                    var b = item as Dictionary<string, object>;
                    string t = DJ.Str(b, "type");
                    if (t == "text") turn.Text += DJ.Str(b, "text");
                    else if (t == "tool_use") turn.Calls.Add(new Call { Id = DJ.Str(b, "id"), Name = DJ.Str(b, "name"), Args = DJ.Child(b, "input") ?? new Dictionary<string, object>() });
                }
                turn.Assistant = new Dictionary<string, object> { { "role", "assistant" }, { "content", content } };
            }
            else
            {
                var choices = DJ.Arr(o, "choices");
                var msg = choices != null && choices.Count > 0 ? DJ.Child(choices[0] as Dictionary<string, object>, "message") : null;
                if (msg == null) throw new AIException(0, "The AI service returned an unexpected response: " + DJ.ErrorText(raw), "ai");
                turn.Text = DJ.Str(msg, "content") ?? "";
                turn.Thinking = DJ.Str(msg, "reasoning_content") ?? "";
                var tcs = DJ.Arr(msg, "tool_calls");
                if (tcs != null)
                    foreach (var item in tcs)
                    {
                        var tc = item as Dictionary<string, object>;
                        var fn = DJ.Child(tc, "function");
                        object av = fn != null && fn.ContainsKey("arguments") ? fn["arguments"] : null;
                        turn.Calls.Add(new Call { Id = DJ.Str(tc, "id") ?? "call_" + Guid.NewGuid().ToString("N").Substring(0, 12), Name = DJ.Str(fn, "name"), Args = av is string ? ParseArgs((string)av) : av as Dictionary<string, object> ?? new Dictionary<string, object>() });
                    }
                turn.Assistant = msg;
            }
            if (turn.Thinking.Length > 0) Say(cb.OnThinking, turn.Thinking);
            if (turn.Text.Length > 0) Say(cb.OnText, turn.Text);
            if (schemas != null && turn.Calls.Count == 0 && turn.Text.Contains("<tool_call>")) { turn.Calls = XmlCalls(turn.Text); turn.Xml = turn.Calls.Count > 0; }
            return turn;
        }

        static Dictionary<string, object> ParseArgs(string s)
        {
            try { return Js.Deserialize<Dictionary<string, object>>(string.IsNullOrWhiteSpace(s) ? "{}" : s) ?? new Dictionary<string, object>(); }
            catch { return new Dictionary<string, object> { { "_raw", s } }; }
        }

        // ── XML tool bridge (models without native function calling) ───────────
        static readonly HashSet<string> XmlBridge = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        static string XmlInstructions(List<Dictionary<string, object>> schemas)
        {
            var sb = new StringBuilder("## Tools\nYou can call tools. To call one, write exactly one line per call in plain text (no code fences) and then STOP and wait for the result:\n<tool_call>{\"name\": \"tool_name\", \"arguments\": {...}}</tool_call>\nResults come back as <tool_response name=\"...\">…</tool_response>.\nAvailable tools:\n");
            foreach (var s in schemas) sb.Append("- " + s["name"] + ": " + s["description"] + " Parameters: " + Js.Serialize(((Dictionary<string, object>)s["parameters"])["properties"]) + "\n");
            return sb.ToString();
        }

        static List<Call> XmlCalls(string text)
        {
            var list = new List<Call>();
            foreach (Match m in Regex.Matches(text, @"<tool_call>\s*(\{[\s\S]*?\})\s*</tool_call>"))
            {
                var o = DJ.Obj(m.Groups[1].Value);
                if (o == null) continue;
                object args; o.TryGetValue("arguments", out args);
                var ad = args as Dictionary<string, object> ?? (args is string ? ParseArgs((string)args) : new Dictionary<string, object>());
                list.Add(new Call { Id = "xml_" + list.Count, Name = DJ.Str(o, "name") ?? "", Args = ad });
            }
            return list;
        }

        static string XmlStrip(string text) { return Regex.Replace(text, @"<tool_call>[\s\S]*?</tool_call>", "").Trim(); }

        // ── labels (ToolResultRow.summaryHeadline / rowStyle) ──────────────────
        public static string Arg(Dictionary<string, object> a, string k)
        {
            object v;
            if (a == null || !a.TryGetValue(k, out v) || v == null) return "";
            return v is string ? (string)v : v is bool ? ((bool)v ? "true" : "false") : Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture);
        }

        static string Target(string name, Dictionary<string, object> a)
        {
            switch (name)
            {
                case "shell": return Arg(a, "command");
                case "grep_search": return Arg(a, "query");
                case "file_search": return Arg(a, "pattern");
                case "read_skill": return Arg(a, "name");
                default: { string p = Arg(a, "path"); return p.Length == 0 ? "." : p; }
            }
        }

        public static string FileName(ToolStep s)
        {
            string p = (s.Path ?? s.Target ?? "").Trim().Trim('"', '\'', '{', '}');
            if (p.Length == 0 || p == ".") return "workspace";
            try { return System.IO.Path.GetFileName(p.TrimEnd('/', '\\')); } catch { return p; }
        }

        /// <summary>summaryHeadline: "Analyzed main.py", "Edited app.cs", "Ran npm test", "Searched TODO".</summary>
        public static string Headline(ToolStep s)
        {
            switch (s.Name)
            {
                case "file_read": return "Analyzed " + FileName(s);
                case "file_write": case "replace_in_file": return "Edited " + FileName(s);
                case "shell": { string c = (s.Target ?? "").Trim(); int nl = c.IndexOf('\n'); if (nl >= 0) c = c.Substring(0, nl); return "Ran " + (c.Length > 64 ? c.Substring(0, 64) : c); }
                case "grep_search": case "file_search": { string q = s.Target ?? "codebase"; return "Searched " + (q.Length > 44 ? q.Substring(0, 44) : q); }
                case "list_directory_tree": return "Listed " + FileName(s);
                case "read_skill": return "Loaded skill " + (s.Target ?? "");
                default: return "Executed " + (s.Name ?? "tool").Replace('_', ' ');
            }
        }

        /// <summary>Short path for the UI: ".microcode/task.md" for agent state files, workspace-relative otherwise.</summary>
        public static string DisplayPath(string path)
        {
            if (string.IsNullOrEmpty(path)) return "";
            string ws = AppState.Shared.WorkspaceFolder;
            try
            {
                if (ws != null)
                {
                    string state = TaskFiles.StateDir(ws).TrimEnd('\\') + "\\";
                    if (path.StartsWith(state, StringComparison.OrdinalIgnoreCase)) return ".microcode/" + path.Substring(state.Length).Replace('\\', '/');
                    string root = System.IO.Path.GetFullPath(ws).TrimEnd('\\') + "\\";
                    if (path.StartsWith(root, StringComparison.OrdinalIgnoreCase)) return path.Substring(root.Length).Replace('\\', '/');
                }
            }
            catch { }
            return path;
        }

        /// <summary>What the agent is asking to do (approval card): "Edit main.py", "Run npm test".</summary>
        public static string RequestText(ToolStep s)
        {
            switch (s.Name)
            {
                case "file_write": return "Write " + FileName(s);
                case "replace_in_file": return "Edit " + FileName(s);
                case "shell": { string c = (s.Target ?? "").Trim(); int nl = c.IndexOf('\n'); if (nl >= 0) c = c.Substring(0, nl); return "Run " + (c.Length > 64 ? c.Substring(0, 64) + "…" : c); }
                default: return Headline(s);
            }
        }

        // ── tools ──────────────────────────────────────────────────────────────
        static string Resolve(string rel)
        {
            var iso = Isolated.Value;
            string ws = iso != null ? iso.Root : AppState.Shared.WorkspaceFolder;
            if (ws == null) throw new Exception("No workspace is open. Open a folder first.");
            string root = System.IO.Path.GetFullPath(ws).TrimEnd('\\') + "\\";
            string r = (rel ?? ".").Trim().Trim('"');
            if (r.Length == 0) r = ".";
            // .microcode/task.md · agent.md · walkthrough.md live in the per-workspace state folder (WorkspaceStoragePaths);
            // an isolated copy keeps them inside the copy so a sandboxed agent never edits the real workspace's state files
            string unix = r.Replace('\\', '/');
            if (unix.StartsWith("./")) unix = unix.Substring(2);
            var tm = Regex.Match(unix, @"^\.microcode/(task|agent|walkthrough)\.md$", RegexOptions.IgnoreCase);
            if (tm.Success && iso == null) return TaskFiles.PathFor(ws, tm.Groups[1].Value.ToLowerInvariant() + ".md");
            string full = System.IO.Path.IsPathRooted(r) ? System.IO.Path.GetFullPath(r) : System.IO.Path.GetFullPath(System.IO.Path.Combine(root, r.Replace('/', '\\')));
            if (!(full + "\\").StartsWith(root, StringComparison.OrdinalIgnoreCase)) throw new Exception("Path is outside the workspace sandbox: " + r);
            return full;
        }

        static string Rel(string full)
        {
            string ws = System.IO.Path.GetFullPath(InIsolation ? Isolated.Value.Root : AppState.Shared.WorkspaceFolder).TrimEnd('\\');
            return full.Length > ws.Length ? full.Substring(ws.Length).TrimStart('\\').Replace('\\', '/') : ".";
        }

        static readonly HashSet<string> SkipDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".git", "node_modules", "bin", "obj", "build", "target", "dist", ".venv", "venv", "__pycache__", ".idea", ".vs", "out", ".next", "Pods", "DerivedData" };

        static IEnumerable<string> WalkFiles(string dir, int limit)
        {
            var stack = new Stack<string>(); stack.Push(dir);
            int n = 0;
            while (stack.Count > 0 && n < limit)
            {
                string d = stack.Pop();
                string[] files = new string[0], dirs = new string[0];
                try { files = Directory.GetFiles(d); dirs = Directory.GetDirectories(d); } catch { }
                foreach (var f in files) { if (n++ >= limit) yield break; yield return f; }
                foreach (var sub in dirs.Reverse()) if (!SkipDirs.Contains(System.IO.Path.GetFileName(sub))) stack.Push(sub);
            }
        }

        static Regex Glob(string pattern)
        {
            string p = (pattern ?? "*").Replace('\\', '/').Trim();
            if (!p.Contains("/")) p = "**/" + p;
            string re = "^" + Regex.Escape(p).Replace(@"\*\*/", "(.*/)?").Replace(@"\*\*", ".*").Replace(@"\*", "[^/]*").Replace(@"\?", "[^/]") + "$";
            return new Regex(re, RegexOptions.IgnoreCase);
        }

        static string Execute(string name, Dictionary<string, object> a, ToolStep step, string sessionId, CancellationToken ct)
        {
            switch (name)
            {
                case "list_directory_tree":
                {
                    string d = Resolve(Arg(a, "path"));
                    if (!Directory.Exists(d)) return "Error: directory not found: " + Arg(a, "path");
                    int depth = 2; int.TryParse(Arg(a, "depth"), out depth); depth = Math.Max(1, Math.Min(5, depth == 0 ? 2 : depth));
                    var sb = new StringBuilder(); int count = 0;
                    Action<string, int> walk = null;
                    walk = (dir, level) =>
                    {
                        string[] dirs = new string[0], files = new string[0];
                        try { dirs = Directory.GetDirectories(dir); files = Directory.GetFiles(dir); } catch { }
                        foreach (var x in dirs.OrderBy(v => v))
                        {
                            if (count++ > 600) return;
                            string nm = System.IO.Path.GetFileName(x);
                            sb.AppendLine(new string(' ', level * 2) + nm + "/");
                            if (level + 1 < depth && !SkipDirs.Contains(nm)) walk(x, level + 1);
                        }
                        foreach (var x in files.OrderBy(v => v)) { if (count++ > 600) return; sb.AppendLine(new string(' ', level * 2) + System.IO.Path.GetFileName(x)); }
                    };
                    walk(d, 0);
                    if (count > 600) sb.AppendLine("… (truncated)");
                    return sb.Length == 0 ? "(empty directory)" : sb.ToString();
                }
                case "file_read":
                {
                    string f = Resolve(Arg(a, "path"));
                    if (!File.Exists(f)) return "Error: file not found: " + Arg(a, "path");
                    var lines = File.ReadAllLines(f);
                    int from = 1, to = lines.Length;
                    int v; if (int.TryParse(Arg(a, "start_line"), out v) && v > 0) from = v;
                    if (int.TryParse(Arg(a, "end_line"), out v) && v > 0) to = Math.Min(lines.Length, v);
                    if (from > Math.Max(1, lines.Length)) return "Error: start_line " + from + " is past the end of the file (" + lines.Length + " lines).";
                    var sb = new StringBuilder();
                    for (int i = from - 1; i < to && i < lines.Length; i++)
                    {
                        sb.Append(lines[i]).Append('\n');
                        if (sb.Length > 150000) { sb.Append("[truncated at line " + (i + 1) + " of " + lines.Length + " — read further with start_line]\n"); to = i + 1; break; }
                    }
                    step.Lines = Math.Max(0, to - from + 1);
                    step.Target = Arg(a, "path") + (from > 1 || to < lines.Length ? "#L" + from + "-" + to : "");
                    return sb.Length == 0 ? "(empty file)" : sb.ToString();
                }
                case "file_write":
                {
                    string f = Resolve(Arg(a, "path"));
                    Guard(f);
                    string content = Arg(a, "content");
                    string before = File.Exists(f) ? File.ReadAllText(f) : null;
                    Checkpoint(step, sessionId, f, before);
                    Directory.CreateDirectory(System.IO.Path.GetDirectoryName(f));
                    bool crlf = before != null && before.Contains("\r\n");
                    string toWrite = crlf ? content.Replace("\r\n", "\n").Replace("\n", "\r\n") : content;
                    File.WriteAllText(f, toWrite, new UTF8Encoding(false));
                    SaveAfter(step, sessionId, toWrite);
                    Diff(before ?? "", content, step);
                    Reload(f, content);
                    return (before == null ? "Created " : "Wrote ") + Arg(a, "path") + " (+" + step.Added + " -" + step.Removed + ", " + content.Split('\n').Length + " lines).";
                }
                case "replace_in_file":
                {
                    string f = Resolve(Arg(a, "path"));
                    Guard(f);
                    if (!File.Exists(f)) return "Error: file not found: " + Arg(a, "path") + ". Use file_write to create it.";
                    string before = File.ReadAllText(f);
                    bool crlf = before.Contains("\r\n");
                    string text = before.Replace("\r\n", "\n");
                    string oldS = Arg(a, "old_string").Replace("\r\n", "\n"), newS = Arg(a, "new_string").Replace("\r\n", "\n");
                    if (oldS.Length == 0) return "Error: old_string is empty.";
                    int count = Regex.Matches(text, Regex.Escape(oldS)).Count;
                    if (count == 0) return "Error: old_string was not found in " + Arg(a, "path") + ". Read the file again and copy the exact text (including indentation).";
                    bool all = Arg(a, "replace_all").ToLowerInvariant() == "true";
                    if (count > 1 && !all) return "Error: old_string matches " + count + " places in " + Arg(a, "path") + ". Include more surrounding lines to make it unique, or set replace_all.";
                    string after = all ? text.Replace(oldS, newS) : ReplaceFirst(text, oldS, newS);
                    Checkpoint(step, sessionId, f, before);
                    File.WriteAllText(f, crlf ? after.Replace("\n", "\r\n") : after, new UTF8Encoding(false));
                    SaveAfter(step, sessionId, crlf ? after.Replace("\n", "\r\n") : after);
                    Diff(oldS, newS, step);
                    Reload(f, after);
                    return "Edited " + Arg(a, "path") + " (+" + step.Added + " -" + step.Removed + (all && count > 1 ? ", " + count + " replacements" : "") + ").";
                }
                case "shell":
                {
                    string ws = Resolve(".");
                    int timeout = 120; int.TryParse(Arg(a, "timeout_seconds"), out timeout); timeout = Math.Max(5, Math.Min(600, timeout == 0 ? 120 : timeout));
                    var psi = new ProcessStartInfo("cmd.exe", "/d /s /c \"" + Arg(a, "command") + "\"") { WorkingDirectory = ws, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, RedirectStandardInput = true, CreateNoWindow = true, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
                    psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
                    psi.EnvironmentVariables["PYTHONUTF8"] = "1";
                    using (var proc = Process.Start(psi))
                    {
                        try { proc.StandardInput.Close(); } catch { }
                        var o = proc.StandardOutput.ReadToEndAsync(); var e = proc.StandardError.ReadToEndAsync();
                        var sw = Stopwatch.StartNew();
                        while (!proc.WaitForExit(200))
                        {
                            if (ct.IsCancellationRequested || sw.Elapsed.TotalSeconds > timeout)
                            {
                                try { Process.Start(new ProcessStartInfo("taskkill", "/T /F /PID " + proc.Id) { CreateNoWindow = true, UseShellExecute = false }).WaitForExit(3000); } catch { }
                                ct.ThrowIfCancellationRequested();
                                return "Error: command timed out after " + timeout + "s and was stopped.";
                            }
                        }
                        string res = (o.Result + (e.Result.Length > 0 ? (o.Result.Length > 0 ? "\n" : "") + "[stderr]\n" + e.Result : "")).Trim();
                        string body = "exit code " + proc.ExitCode + "\n" + (res.Length > 30000 ? "…\n" + res.Substring(res.Length - 30000) : res);
                        if (!InIsolation && Application.Current != null) Application.Current.Dispatcher.BeginInvoke(new Action(() => AppState.Shared.RefreshFileTree()));
                        return proc.ExitCode == 0 ? body : "Error: " + body;
                    }
                }
                case "grep_search":
                {
                    string root = Resolve(Arg(a, "path").Length > 0 ? Arg(a, "path") : ".");
                    Regex re;
                    try { re = new Regex(Arg(a, "query"), RegexOptions.IgnoreCase); } catch { re = new Regex(Regex.Escape(Arg(a, "query")), RegexOptions.IgnoreCase); }
                    var include = Arg(a, "include").Length > 0 ? Glob(Arg(a, "include")) : null;
                    var sb = new StringBuilder(); int n = 0;
                    foreach (var f in WalkFiles(Directory.Exists(root) ? root : System.IO.Path.GetDirectoryName(root), 20000))
                    {
                        if (n >= 200) break;
                        ct.ThrowIfCancellationRequested();
                        string rel = Rel(f);
                        if (include != null && !include.IsMatch(rel)) continue;
                        try
                        {
                            if (new FileInfo(f).Length > 1024 * 1024) continue;
                            var lines = File.ReadAllLines(f);
                            for (int i = 0; i < lines.Length && n < 200; i++)
                                if (re.IsMatch(lines[i])) { string t = lines[i].Trim(); sb.AppendLine(rel + ":" + (i + 1) + ": " + (t.Length > 220 ? t.Substring(0, 220) + "…" : t)); n++; }
                        }
                        catch { }
                    }
                    return n == 0 ? "No matches." : sb.ToString() + (n >= 200 ? "… (first 200 matches)" : "");
                }
                case "file_search":
                {
                    var g = Glob(Arg(a, "pattern"));
                    var hits = WalkFiles(Resolve("."), 50000).Select(Rel).Where(r => g.IsMatch(r) || g.IsMatch("/" + r)).Take(300).ToList();
                    return hits.Count == 0 ? "No files match " + Arg(a, "pattern") + "." : string.Join("\n", hits);
                }
                case "read_skill": return AgentContext.ReadSkill(Arg(a, "name"));
            }
            return "Error: unknown tool " + name + ". Available: list_directory_tree, file_read, grep_search, file_search, file_write, replace_in_file, shell, read_skill.";
        }

        static string ReplaceFirst(string text, string oldS, string newS) { int i = text.IndexOf(oldS, StringComparison.Ordinal); return text.Substring(0, i) + newS + text.Substring(i + oldS.Length); }

        /// <summary>Scope Lock & Protected Files Guard.</summary>
        static void Guard(string full)
        {
            var iso = Isolated.Value;
            string reason;
            if (iso != null)
            {
                // an isolated copy follows the Scope Lock of the real file it mirrors
                string rel = full.Length > iso.Root.Length ? full.Substring(iso.Root.Length).TrimStart('\\') : "";
                reason = iso.Workspace == null ? null : ScopeLock.BlockedIn(iso.Workspace, System.IO.Path.Combine(iso.Workspace, rel));
            }
            else reason = ScopeLock.Blocked(full);
            if (reason != null) throw new Exception(reason);
        }

        static void Reload(string f, string content)
        {
            if (InIsolation || Application.Current == null) return; // isolated copies are never open in the editor
            Application.Current.Dispatcher.BeginInvoke(new Action(() =>
            {
                var st = AppState.Shared;
                var open = st.OpenFiles.FirstOrDefault(o => string.Equals(o.Path, f, StringComparison.OrdinalIgnoreCase));
                if (open != null && !open.IsUnsaved) { open.Content = content.Replace("\r\n", "\n"); st.Notify("files"); }
                st.RefreshFileTree();
            }));
        }

        /// <summary>computeDiffLineStats: counted-set line diff → +added −removed.</summary>
        static void Diff(string before, string after, ToolStep step)
        {
            // same line model as Differ (a trailing newline does not make an extra line), so the row and the card agree
            string b0 = before.Replace("\r\n", "\n").TrimEnd('\n'), a0 = after.Replace("\r\n", "\n").TrimEnd('\n');
            var oldLines = b0.Length == 0 ? new string[0] : b0.Split('\n');
            var newLines = a0.Length == 0 ? new string[0] : a0.Split('\n');
            var bag = new Dictionary<string, int>();
            foreach (var l in oldLines) { int c; bag.TryGetValue(l, out c); bag[l] = c + 1; }
            int added = 0;
            foreach (var l in newLines) { int c; if (bag.TryGetValue(l, out c) && c > 0) bag[l] = c - 1; else added++; }
            int removed = bag.Values.Sum();
            if (added == 0 && removed == 0 && before != after) { added = Math.Max(1, newLines.Length); removed = Math.Max(1, oldLines.Length); }
            step.Added = added; step.Removed = removed;
        }

        // ── checkpoints (Restore Checkpoint) ───────────────────────────────────
        static string CheckpointDir(string sessionId) { return System.IO.Path.Combine(Defaults.Dir, "checkpoints", sessionId ?? "default"); }

        static void Checkpoint(ToolStep step, string sessionId, string file, string before)
        {
            step.Path = file;
            if (InIsolation) return; // a disposable copy needs no restore point
            try
            {
                string dir = CheckpointDir(sessionId);
                Directory.CreateDirectory(dir);
                string cp = System.IO.Path.Combine(dir, Guid.NewGuid().ToString("N") + ".txt");
                File.WriteAllText(cp, before ?? "", new UTF8Encoding(false));
                step.Checkpoint = cp;
                step.Existed = before != null;
            }
            catch { }
        }

        static void SaveAfter(ToolStep step, string sessionId, string written)
        {
            if (InIsolation) return;
            try
            {
                string dir = CheckpointDir(sessionId);
                Directory.CreateDirectory(dir);
                string cp = System.IO.Path.Combine(dir, Guid.NewGuid().ToString("N") + ".after.txt");
                File.WriteAllText(cp, written ?? "", new UTF8Encoding(false));
                step.After = cp;
            }
            catch { }
        }

        public static string ReadSnapshot(string path) { try { return path != null && File.Exists(path) ? File.ReadAllText(path) : null; } catch { return null; } }

        static void Touch(string path)
        {
            var open = AppState.Shared.OpenFiles.FirstOrDefault(o => string.Equals(o.Path, path, StringComparison.OrdinalIgnoreCase));
            if (open != null && File.Exists(path)) { open.Content = File.ReadAllText(path).Replace("\r\n", "\n"); open.IsUnsaved = false; }
        }

        /// <summary>Restores every file edited by these steps (newest first). Returns how many files were restored.</summary>
        public static int Revert(IEnumerable<ToolStep> steps)
        {
            int n = 0;
            foreach (var s in steps.Reverse())
            {
                if (s.Reverted || string.IsNullOrEmpty(s.Checkpoint) || string.IsNullOrEmpty(s.Path) || !File.Exists(s.Checkpoint)) continue;
                try
                {
                    if (!s.Existed) { if (File.Exists(s.Path)) File.Delete(s.Path); }
                    else File.WriteAllText(s.Path, File.ReadAllText(s.Checkpoint), new UTF8Encoding(false));
                    s.Reverted = true;
                    n++;
                    Touch(s.Path);
                }
                catch { }
            }
            if (n > 0) { AppState.Shared.Notify("files"); AppState.Shared.RefreshFileTree(); }
            return n;
        }

        /// <summary>Diff card Revert: put one file back to how it was before this turn's first edit to it.</summary>
        public static bool RevertFile(List<ToolStep> turnSteps, string path)
        {
            var edits = turnSteps.Where(s => string.Equals(s.Path, path, StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(s.Checkpoint)).ToList();
            if (edits.Count == 0) return false;
            var first = edits[0];
            try
            {
                if (!first.Existed) { if (File.Exists(path)) File.Delete(path); }
                else File.WriteAllText(path, File.ReadAllText(first.Checkpoint), new UTF8Encoding(false));
                foreach (var e in edits) e.Reverted = true;
                Touch(path);
                AppState.Shared.Notify("files"); AppState.Shared.RefreshFileTree();
                return true;
            }
            catch { return false; }
        }

        /// <summary>Diff card Restore: apply this turn's final version of the file again.</summary>
        public static bool ReapplyFile(List<ToolStep> turnSteps, string path)
        {
            var edits = turnSteps.Where(s => string.Equals(s.Path, path, StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(s.After)).ToList();
            if (edits.Count == 0) return false;
            string content = ReadSnapshot(edits[edits.Count - 1].After);
            if (content == null) return false;
            try
            {
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path));
                File.WriteAllText(path, content, new UTF8Encoding(false));
                foreach (var e in turnSteps.Where(s => string.Equals(s.Path, path, StringComparison.OrdinalIgnoreCase))) e.Reverted = false;
                Touch(path);
                AppState.Shared.Notify("files"); AppState.Shared.RefreshFileTree();
                return true;
            }
            catch { return false; }
        }
    }

    /// <summary>Scope Lock & Protected Files Guard (scopeLockMenuPill): locked files, strict @mention scope, core config protection.</summary>
    public static class ScopeLock
    {
        static string Ws { get { return AppState.Shared.WorkspaceFolder ?? ""; } }
        static string Key(string k) { return "scope_" + k + "_" + Ws.ToLowerInvariant(); }
        public static List<string> Locked { get { return Defaults.List(Key("locked")); } }
        public static bool IsLocked(string path) { return path != null && Locked.Any(p => string.Equals(p, path, StringComparison.OrdinalIgnoreCase)); }
        public static void Toggle(string path)
        {
            var l = Locked;
            if (IsLocked(path)) l.RemoveAll(p => string.Equals(p, path, StringComparison.OrdinalIgnoreCase)); else l.Add(path);
            Defaults.Set(Key("locked"), new System.Collections.ArrayList(l));
        }
        public static bool Strict { get { return Defaults.Bool(Key("strict"), false); } set { Defaults.Set(Key("strict"), value); } }
        public static bool CoreConfigs { get { return Defaults.Bool(Key("core"), false); } set { Defaults.Set(Key("core"), value); } }
        /// <summary>Files @mentioned in the current request (Strict Scope allows edits only to these).</summary>
        public static HashSet<string> Mentioned = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        static readonly string[] Core = { ".env", "package.json", "package-lock.json", "cargo.toml", "cargo.lock", "pyproject.toml", "requirements.txt", "go.mod", "pom.xml", "build.gradle", "dockerfile", ".gitignore" };
        public static int ActiveCount { get { return Locked.Count + (Strict ? 1 : 0) + (CoreConfigs ? 1 : 0); } }

        public static string Blocked(string full)
        {
            if (IsLocked(full)) return "Error: " + System.IO.Path.GetFileName(full) + " is locked by Scope Lock (protected from AI edits). Ask the user to unlock it.";
            string nm = System.IO.Path.GetFileName(full).ToLowerInvariant();
            if (CoreConfigs && (Core.Contains(nm) || nm.StartsWith(".env"))) return "Error: " + nm + " is a protected core config (Scope Lock → Lock Core Configs).";
            if (Strict && !Mentioned.Contains(full)) return "Error: Strict Scope is on — only @mentioned files may be edited. " + System.IO.Path.GetFileName(full) + " was not mentioned.";
            return null;
        }

        /// <summary>Scope Lock for a write into <paramref name="workspace"/> outside a chat turn (Consensus apply, PNS merges, isolated copies):
        /// locked files and core configs of that workspace. Strict Scope is about the @mentions of a chat request and does not apply here.</summary>
        public static string BlockedIn(string workspace, string full)
        {
            string key = (workspace ?? "").ToLowerInvariant();
            if (Defaults.List("scope_locked_" + key).Any(p => string.Equals(p, full, StringComparison.OrdinalIgnoreCase)))
                return "Error: " + System.IO.Path.GetFileName(full) + " is locked by Scope Lock (protected from AI edits). Ask the user to unlock it.";
            string nm = System.IO.Path.GetFileName(full).ToLowerInvariant();
            if (Defaults.Bool("scope_core_" + key, false) && (Core.Contains(nm) || nm.StartsWith(".env"))) return "Error: " + nm + " is a protected core config (Scope Lock → Lock Core Configs).";
            return null;
        }
    }
}
