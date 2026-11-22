// Port of ExternalMCPManager.swift (+ the MCP half of MultiPlatformRulesEngine.refresh): MCP client for the agent.
// Servers come from the same config files the Mac reads (MicroCode, Cursor, Windsurf, Codex, Antigravity, Claude Code /
// Desktop, plugins, and the workspace's .mcp.json / .cursor / .vscode — repo-declared ones only after Workspace Trust).
// Transports: stdio (newline-delimited JSON-RPC) and Streamable HTTP (JSON or SSE replies, Mcp-Session-Id). Tool lists are
// probed in the background and cached; stdio servers hibernate after the probe and wake on the first call. The agent sees
// tools as mcp__<server>__<tool> (up to 12 picked for the prompt, more mounted through mcp_orchestrator).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using MicroCode.Core;

namespace MicroCode.Views
{
    public class McpServerSpec
    {
        public string Name, Source, Command = "", Url, WorkspaceConfigPath;
        public List<string> Args = new List<string>();
        public Dictionary<string, string> Env = new Dictionary<string, string>(), Headers = new Dictionary<string, string>();
        public bool IsRemote { get { return !string.IsNullOrEmpty(Url); } }
        public bool IsWorkspaceScoped { get { return WorkspaceConfigPath != null; } }
        /// <summary>Identity of what would run (a changed command or URL invalidates the cached tool list).</summary>
        public string Fingerprint { get { return (Url ?? Command) + "\u0001" + string.Join("\u0001", Args); } }
    }

    public class McpToolInfo
    {
        public string Name = "", Description = "";
        public Dictionary<string, object> InputSchema = new Dictionary<string, object>();
    }

    public class McpException : Exception { public McpException(string m) : base(m) { } }

    // ── discovery ────────────────────────────────────────────────────────────

    public static class McpDiscovery
    {
        static string Home { get { return Path.GetDirectoryName(TaskFiles.Home.TrimEnd('\\')); } }

        /// <summary>The Mac's candidate list, user-level first; repo-controlled configs last so they never shadow a user server name.</summary>
        public static List<Tuple<string, string, bool>> Candidates(string ws)
        {
            string home = Home;
            var list = new List<Tuple<string, string, bool>>();
            if (!string.IsNullOrEmpty(ws)) list.Add(Tuple.Create(TaskFiles.Managed(ws, "mcp.json"), "MicroCode Workspace State (~/.microcode/workspaces/.../mcp.json)", false));
            list.Add(Tuple.Create(Path.Combine(home, ".microcode", "mcp.json"), "MicroCode Global (~/.microcode/mcp.json)", false));
            list.Add(Tuple.Create(Path.Combine(home, ".cursor", "mcp.json"), "Cursor User (~/.cursor/mcp.json)", false));
            list.Add(Tuple.Create(Path.Combine(home, ".codeium", "windsurf", "mcp_config.json"), "Windsurf (~/.codeium/windsurf/mcp_config.json)", false));
            list.Add(Tuple.Create(Path.Combine(home, ".codex", "mcp.json"), "Codex (~/.codex/mcp.json)", false));
            list.Add(Tuple.Create(Path.Combine(home, ".gemini", "antigravity", "mcp_config.json"), "Antigravity (~/.gemini/antigravity/mcp_config.json)", false));
            list.Add(Tuple.Create(Path.Combine(home, ".gemini", "settings.json"), "Antigravity (~/.gemini/settings.json)", false));
            list.Add(Tuple.Create(Path.Combine(home, ".claude.json"), "Claude Code (~/.claude.json)", false));
            // Claude Desktop keeps its config in %APPDATA%\Claude on Windows
            string appData = TaskFiles.HomeOverride == null ? Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData) : Path.Combine(home, "AppData", "Roaming");
            list.Add(Tuple.Create(Path.Combine(appData, "Claude", "claude_desktop_config.json"), "Claude Desktop", false));
            foreach (var pr in new[] { Tuple.Create(Path.Combine(home, ".gemini", "config", "plugins"), "Antigravity Plugin"), Tuple.Create(Path.Combine(home, ".claude", "plugins"), "Claude Plugin") })
            {
                string[] dirs = new string[0];
                try { if (Directory.Exists(pr.Item1)) dirs = Directory.GetDirectories(pr.Item1); } catch (IOException) { } catch (UnauthorizedAccessException) { }
                foreach (var d in dirs.OrderBy(x => x, StringComparer.OrdinalIgnoreCase))
                {
                    if (Path.GetFileName(d).StartsWith(".")) continue;
                    foreach (var cfg in new[] { "mcp_config.json", ".mcp.json", "mcp.json" })
                        if (File.Exists(Path.Combine(d, cfg))) list.Add(Tuple.Create(Path.Combine(d, cfg), pr.Item2 + " (" + Path.GetFileName(d) + ")", false));
                }
            }
            if (!string.IsNullOrEmpty(ws))
            {
                list.Add(Tuple.Create(Path.Combine(ws, ".microcode", "mcp.json"), "MicroCode Workspace (.microcode/mcp.json)", true));
                list.Add(Tuple.Create(Path.Combine(ws, ".mcp.json"), "MCP Standard (.mcp.json)", true));
                list.Add(Tuple.Create(Path.Combine(ws, ".cursor", "mcp.json"), "Cursor (.cursor/mcp.json)", true));
                list.Add(Tuple.Create(Path.Combine(ws, ".vscode", "mcp.json"), "VS Code (.vscode/mcp.json)", true));
            }
            return list;
        }

        static string S(Dictionary<string, object> d, string k) { object v; return d != null && d.TryGetValue(k, out v) ? v as string : null; }

        static Dictionary<string, string> Map(Dictionary<string, object> d, string k)
        {
            var r = new Dictionary<string, string>();
            object v;
            var m = d != null && d.TryGetValue(k, out v) ? v as Dictionary<string, object> : null;
            if (m != null) foreach (var kv in m) if (kv.Value != null) r[kv.Key] = Convert.ToString(kv.Value, System.Globalization.CultureInfo.InvariantCulture);
            return r;
        }

        /// <summary>Every enabled server across the candidate files (first name wins). <paramref name="repoFiles"/> gets the
        /// repo-controlled files that declared a server (they join the hooks in the workspace-trust fingerprint).</summary>
        public static List<McpServerSpec> Scan(string ws, List<string> repoFiles)
        {
            var servers = new List<McpServerSpec>();
            foreach (var c in Candidates(ws))
            {
                if (!File.Exists(c.Item1)) continue;
                Dictionary<string, object> json;
                try { json = new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.DeserializeObject(File.ReadAllText(c.Item1)) as Dictionary<string, object>; }
                catch (ArgumentException) { continue; } catch (InvalidOperationException) { continue; } catch (IOException) { continue; }
                if (json == null) continue;
                object sv;
                var dict = (json.TryGetValue("mcpServers", out sv) ? sv : json.TryGetValue("servers", out sv) ? sv : null) as Dictionary<string, object>;
                if (dict == null) continue;
                bool declared = false;
                foreach (var kv in dict)
                {
                    var spec = kv.Value as Dictionary<string, object>;
                    if (spec == null || kv.Key == "microcode") continue;
                    object b;
                    if (spec.TryGetValue("disabled", out b) && b is bool && (bool)b) continue;
                    if (spec.TryGetValue("enabled", out b) && b is bool && !(bool)b) continue;
                    var env = Map(spec, "env");
                    if (env.Values.Any(v => v.StartsWith("YOUR_"))) continue; // unconfigured placeholder credentials
                    string cmd = S(spec, "command") ?? "", url = S(spec, "url") ?? S(spec, "serverUrl") ?? S(spec, "httpUrl");
                    if (cmd.Length == 0 && string.IsNullOrEmpty(url)) continue;
                    if (servers.Any(x => x.Name == kv.Key)) continue;
                    var args = new List<string>();
                    object a;
                    if (spec.TryGetValue("args", out a))
                    {
                        var arr = a as object[]; if (arr == null && a is System.Collections.ArrayList) arr = ((System.Collections.ArrayList)a).ToArray();
                        if (arr != null) args = arr.Where(x => x != null).Select(x => Convert.ToString(x, System.Globalization.CultureInfo.InvariantCulture)).ToList();
                    }
                    servers.Add(new McpServerSpec { Name = kv.Key, Source = c.Item2, Command = cmd.Length == 0 ? url : cmd, Args = args, Env = env, Url = string.IsNullOrEmpty(url) ? (cmd.StartsWith("http://") || cmd.StartsWith("https://") ? cmd : null) : url, Headers = Map(spec, "headers"), WorkspaceConfigPath = c.Item3 ? c.Item1 : null });
                    declared = declared || c.Item3;
                }
                if (declared && repoFiles != null) repoFiles.Add(c.Item1);
            }
            return servers;
        }
    }

    // ── one server connection ────────────────────────────────────────────────

    public class McpConnection
    {
        public const string ProtocolVersion = "2025-11-25";
        public static readonly string[] SupportedVersions = { "2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05" };

        public readonly McpServerSpec Spec;
        public string Name { get { return Spec.Name; } }
        public volatile bool Connected, Starting;
        public string Error, NegotiatedVersion;
        public List<McpToolInfo> Tools = new List<McpToolInfo>();
        public int CallCount, ErrorCount, AvgLatencyMs;
        public string Workspace;
        public event Action Changed;

        static readonly JavaScriptSerializer Js = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
        static readonly HttpClient Http = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
        readonly object _gate = new object();
        readonly Dictionary<long, TaskCompletionSource<object>> _pending = new Dictionary<long, TaskCompletionSource<object>>();
        readonly Dictionary<string, Tuple<string, DateTime>> _readCache = new Dictionary<string, Tuple<string, DateTime>>();
        long _nextId = 1;
        Process _proc;
        StreamWriter _stdin;
        readonly StringBuilder _stderr = new StringBuilder();
        string _session;
        int _generation;

        public McpConnection(McpServerSpec spec) { Spec = spec; }

        void Notify() { var c = Changed; if (c != null) c(); }

        // ── lifecycle ──

        /// <summary>Starts the server and completes the initialize handshake and tools/list (blocks up to <paramref name="timeoutMs"/>).</summary>
        public bool Start(int timeoutMs)
        {
            lock (_gate)
            {
                if (Connected) return true;
                Starting = true; Error = null;
            }
            Notify();
            try
            {
                if (!Spec.IsRemote) SpawnProcess();
                var init = Request("initialize", new Dictionary<string, object>
                {
                    { "protocolVersion", ProtocolVersion },
                    { "capabilities", new Dictionary<string, object> { { "roots", new Dictionary<string, object> { { "listChanged", false } } } } },
                    { "clientInfo", new Dictionary<string, object> { { "name", "MicroCode-HyperMesh" }, { "version", "3.1.0" } } }
                }, timeoutMs) as Dictionary<string, object>;
                object v; NegotiatedVersion = init != null && init.TryGetValue("protocolVersion", out v) ? v as string : null;
                Connected = true;
                SendNotification("notifications/initialized");
                FetchTools(Math.Max(5000, timeoutMs / 2));
                return true;
            }
            catch (Exception ex)
            {
                Error = ex is McpException ? ex.Message : (Spec.IsRemote ? "HTTP Init failed: " : "Init failed: ") + ex.Message;
                Connected = false;
                if (!Spec.IsRemote) KillProcess();
                return false;
            }
            finally { Starting = false; Notify(); }
        }

        public void Stop()
        {
            Connected = false;
            FailAll("Connection closed");
            KillProcess();
            _session = null;
            Notify();
        }

        void FailAll(string why)
        {
            List<TaskCompletionSource<object>> all;
            lock (_gate) { all = _pending.Values.ToList(); _pending.Clear(); }
            foreach (var t in all) t.TrySetException(new McpException(why));
        }

        void KillProcess()
        {
            Process p; StreamWriter w;
            lock (_gate) { p = _proc; w = _stdin; _proc = null; _stdin = null; _generation++; }
            if (w != null) { try { w.Close(); } catch (IOException) { } catch (ObjectDisposedException) { } }
            if (p == null) return;
            try
            {
                // servers exit on stdin EOF; anything left (npx, uvx wrappers) is ended with its child processes
                if (!p.WaitForExit(1500))
                    using (var k = Process.Start(new ProcessStartInfo("taskkill", "/T /F /PID " + p.Id) { CreateNoWindow = true, UseShellExecute = false })) k.WaitForExit(3000);
            }
            catch (InvalidOperationException) { } catch (System.ComponentModel.Win32Exception) { }
            finally { p.Dispose(); }
        }

        /// <summary>Windows command resolution: absolute path, PATH × PATHEXT, then npm / bun / cargo / uv / pipx folders.
        /// .cmd / .bat shims (npx, uvx installers) run through cmd.exe.</summary>
        public static string ResolveCommand(string cmd)
        {
            if (string.IsNullOrWhiteSpace(cmd)) return null;
            if (Path.IsPathRooted(cmd)) return File.Exists(cmd) ? cmd : null;
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            var dirs = (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';').Where(d => d.Trim().Length > 0).ToList();
            dirs.AddRange(new[] { Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "npm"), Path.Combine(home, ".bun", "bin"), Path.Combine(home, ".cargo", "bin"), Path.Combine(home, ".local", "bin") });
            var exts = Path.HasExtension(cmd) ? new[] { "" } : new[] { ".exe", ".cmd", ".bat", ".com", "" };
            foreach (var d in dirs)
                foreach (var e in exts)
                {
                    try
                    {
                        string p = Path.Combine(d.Trim().Trim('"'), cmd + e);
                        if (File.Exists(p)) return p;
                    }
                    catch (ArgumentException) { }
                }
            return null;
        }

        /// <summary>Windows command-line quoting for one argument (CommandLineToArgvW rules).</summary>
        public static string Quote(string a)
        {
            if (a.Length > 0 && a.IndexOfAny(new[] { ' ', '\t', '"' }) < 0) return a;
            var sb = new StringBuilder("\"");
            int bs = 0;
            foreach (char c in a)
            {
                if (c == '\\') { bs++; continue; }
                if (c == '"') { sb.Append('\\', bs * 2 + 1).Append('"'); bs = 0; continue; }
                sb.Append('\\', bs).Append(c); bs = 0;
            }
            sb.Append('\\', bs * 2).Append('"');
            return sb.ToString();
        }

        /// <summary>Process creates StandardInput with Console.InputEncoding and AutoFlush, which writes a UTF-8 BOM into the pipe
        /// as soon as the process starts when the console code page is 65001 — strict JSON-RPC servers then fail on the first
        /// line. A BOM-less UTF-8 input encoding avoids it (no-op without a console: a GUI process gets ANSI, which has no BOM).</summary>
        static void AvoidStdinBom()
        {
            try
            {
                var enc = Console.InputEncoding;
                if (enc.CodePage == 65001 && enc.GetPreamble().Length > 0) Console.InputEncoding = new UTF8Encoding(false);
            }
            catch (IOException) { } catch (System.Security.SecurityException) { }
        }

        void SpawnProcess()
        {
            AvoidStdinBom();
            string exe = ResolveCommand(Spec.Command);
            if (exe == null) throw new McpException("Command not found: " + Spec.Command);
            string args = string.Join(" ", Spec.Args.Select(Quote));
            ProcessStartInfo psi;
            string ext = Path.GetExtension(exe).ToLowerInvariant();
            if (ext == ".cmd" || ext == ".bat") psi = new ProcessStartInfo("cmd.exe", "/d /s /c \"" + Quote(exe) + (args.Length > 0 ? " " + args : "") + "\"");
            else psi = new ProcessStartInfo(exe, args);
            psi.UseShellExecute = false; psi.CreateNoWindow = true;
            psi.RedirectStandardInput = true; psi.RedirectStandardOutput = true; psi.RedirectStandardError = true;
            psi.StandardOutputEncoding = new UTF8Encoding(false); psi.StandardErrorEncoding = new UTF8Encoding(false);
            string ws = Workspace;
            psi.WorkingDirectory = !string.IsNullOrEmpty(ws) && Directory.Exists(ws) ? ws : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            psi.EnvironmentVariables.Remove("MICROCODE_LOCAL_API_TOKEN");
            psi.EnvironmentVariables.Remove("MICROCODE_BRIDGE_TOKEN");
            psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
            foreach (var kv in Spec.Env) psi.EnvironmentVariables[kv.Key] = kv.Value;
            var p = new Process { StartInfo = psi, EnableRaisingEvents = true };
            p.Start();
            int gen;
            lock (_gate)
            {
                _proc = p;
                _stdin = new StreamWriter(p.StandardInput.BaseStream, new UTF8Encoding(false)) { AutoFlush = true, NewLine = "\n" };
                _stderr.Clear();
                gen = ++_generation;
            }
            p.ErrorDataReceived += (s, e) => { if (e.Data == null) return; lock (_stderr) { _stderr.AppendLine(e.Data); if (_stderr.Length > 4000) _stderr.Remove(0, _stderr.Length - 4000); } };
            p.BeginErrorReadLine();
            var reader = new Thread(() =>
            {
                try
                {
                    string line;
                    while ((line = p.StandardOutput.ReadLine()) != null) HandleLine(line);
                }
                catch (IOException) { } catch (ObjectDisposedException) { } catch (InvalidOperationException) { }
                int code = -1;
                try { p.WaitForExit(2000); code = p.HasExited ? p.ExitCode : -1; } catch (InvalidOperationException) { }
                bool current; lock (_gate) current = gen == _generation;
                if (!current) return;
                Connected = false;
                string tail; lock (_stderr) tail = _stderr.ToString().Trim();
                string why = "MCP server '" + Name + "' terminated (exit " + code + ")" + (tail.Length > 0 ? ": " + (tail.Length > 300 ? tail.Substring(tail.Length - 300) : tail) : "");
                if (Error == null) Error = why;
                FailAll(why);
                Notify();
            }) { IsBackground = true, Name = "mcp-" + Name };
            reader.Start();
        }

        // ── JSON-RPC ──

        void HandleLine(string raw)
        {
            string line = (raw ?? "").Trim();
            if (line.StartsWith("data:")) line = line.Substring(5).Trim();
            if (line.Length == 0 || line == "[DONE]" || !line.StartsWith("{")) return;
            Dictionary<string, object> msg;
            try { msg = Js.DeserializeObject(line) as Dictionary<string, object>; }
            catch (ArgumentException) { return; } catch (InvalidOperationException) { return; }
            if (msg != null) HandleMessage(msg);
        }

        void HandleMessage(Dictionary<string, object> msg)
        {
            object m, id;
            bool hasId = msg.TryGetValue("id", out id) && id != null;
            if (msg.TryGetValue("method", out m) && m is string)
            {
                string method = (string)m;
                if (hasId)
                {
                    // server-to-client requests must be answered, or the server blocks until its own timeout
                    if (method == "ping") SendRaw(new Dictionary<string, object> { { "jsonrpc", "2.0" }, { "id", id }, { "result", new Dictionary<string, object>() } });
                    else if (method == "roots/list")
                    {
                        string ws = !string.IsNullOrEmpty(Workspace) ? Workspace : Environment.CurrentDirectory;
                        var root = new Dictionary<string, object> { { "uri", new Uri(Path.GetFullPath(ws).TrimEnd('\\') + "\\").AbsoluteUri.TrimEnd('/') }, { "name", Path.GetFileName(Path.GetFullPath(ws).TrimEnd('\\')) } };
                        SendRaw(new Dictionary<string, object> { { "jsonrpc", "2.0" }, { "id", id }, { "result", new Dictionary<string, object> { { "roots", new object[] { root } } } } });
                    }
                    else SendRaw(new Dictionary<string, object> { { "jsonrpc", "2.0" }, { "id", id }, { "error", new Dictionary<string, object> { { "code", -32601 }, { "message", "Method not supported by MicroCode client: " + method } } } });
                }
                else if (method == "notifications/tools/list_changed") ThreadPool.QueueUserWorkItem(_ => { try { FetchTools(15000); } catch (Exception ex) { Debug.WriteLine("mcp list_changed: " + ex.Message); } });
                return;
            }
            if (!hasId) return;
            long key;
            try { key = Convert.ToInt64(id, System.Globalization.CultureInfo.InvariantCulture); } catch (FormatException) { return; } catch (InvalidCastException) { return; }
            TaskCompletionSource<object> tcs;
            lock (_gate) { if (!_pending.TryGetValue(key, out tcs)) return; _pending.Remove(key); }
            object err, result;
            if (msg.TryGetValue("error", out err) && err is Dictionary<string, object>)
            {
                object em; ((Dictionary<string, object>)err).TryGetValue("message", out em);
                tcs.TrySetException(new McpException(em as string ?? "Unknown error"));
            }
            else tcs.TrySetResult(msg.TryGetValue("result", out result) ? result : new Dictionary<string, object>());
        }

        object Request(string method, Dictionary<string, object> prms, int timeoutMs)
        {
            long id;
            var tcs = new TaskCompletionSource<object>();
            lock (_gate) { id = _nextId++; _pending[id] = tcs; }
            var req = new Dictionary<string, object> { { "jsonrpc", "2.0" }, { "id", id }, { "method", method }, { "params", prms ?? new Dictionary<string, object>() } };
            try { SendRaw(req, timeoutMs); }
            catch (Exception) { lock (_gate) _pending.Remove(id); throw; }
            bool done;
            try { done = tcs.Task.Wait(timeoutMs); }
            catch (AggregateException ae) { throw ae.InnerException is McpException ? (McpException)ae.InnerException : new McpException(ae.InnerException.Message); }
            if (!done)
            {
                lock (_gate) _pending.Remove(id);
                throw new McpException("Request '" + method + "' timed out after " + (timeoutMs / 1000) + "s");
            }
            return tcs.Task.Result;
        }

        void SendNotification(string method)
        {
            try { SendRaw(new Dictionary<string, object> { { "jsonrpc", "2.0" }, { "method", method }, { "params", new Dictionary<string, object>() } }); }
            catch (McpException ex) { Debug.WriteLine("mcp notify: " + ex.Message); }
        }

        void SendRaw(Dictionary<string, object> obj, int timeoutMs = 35000)
        {
            string json = Js.Serialize(obj);
            if (Spec.IsRemote) { SendHttp(obj, json, timeoutMs); return; }
            StreamWriter w; lock (_gate) w = _stdin;
            if (w == null) throw new McpException("MCP server '" + Name + "' is not running");
            try { lock (w) w.WriteLine(json); }
            catch (IOException ex) { throw new McpException("MCP server '" + Name + "' closed its input: " + ex.Message); }
            catch (ObjectDisposedException) { throw new McpException("MCP server '" + Name + "' is not running"); }
        }

        /// <summary>Authorization from the server's own config: an explicit header, or a token named in its declared env
        /// (name-specific keys may also come from the process env for user-level servers), then a stored bearer for this origin.</summary>
        string AuthHeader()
        {
            var h = Spec.Headers.FirstOrDefault(x => x.Key.Equals("Authorization", StringComparison.OrdinalIgnoreCase));
            if (!string.IsNullOrEmpty(h.Value)) return h.Value;
            string upper = Name.ToUpperInvariant().Replace("-", "_");
            var generic = new[] { "AUTHORIZATION", "MCP_BEARER_TOKEN", "BEARER_TOKEN", "MCP_TOKEN" };
            var named = new[] { upper + "_ACCESS_TOKEN", upper + "_API_KEY", upper + "_TOKEN" };
            foreach (var k in generic.Concat(named))
            {
                string v; Spec.Env.TryGetValue(k, out v);
                if (string.IsNullOrEmpty(v) && named.Contains(k) && !Spec.IsWorkspaceScoped) v = Environment.GetEnvironmentVariable(k);
                if (!string.IsNullOrEmpty(v) && !v.StartsWith("YOUR_")) return v.StartsWith("bearer ", StringComparison.OrdinalIgnoreCase) ? v : "Bearer " + v;
            }
            string stored = McpManager.StoredBearer(Spec.Url);
            return stored != null ? "Bearer " + stored : null;
        }

        void SendHttp(Dictionary<string, object> obj, string json, int timeoutMs)
        {
            object id; obj.TryGetValue("id", out id);
            using (var req = new HttpRequestMessage(HttpMethod.Post, Spec.Url))
            {
                req.Content = new StringContent(json, new UTF8Encoding(false), "application/json");
                req.Headers.TryAddWithoutValidation("Accept", "application/json, text/event-stream");
                if (!string.IsNullOrEmpty(_session)) req.Headers.TryAddWithoutValidation("Mcp-Session-Id", _session);
                if (NegotiatedVersion != null) req.Headers.TryAddWithoutValidation("MCP-Protocol-Version", NegotiatedVersion);
                foreach (var h in Spec.Headers) if (!h.Key.Equals("Authorization", StringComparison.OrdinalIgnoreCase)) req.Headers.TryAddWithoutValidation(h.Key, h.Value);
                string auth = AuthHeader();
                if (auth != null) req.Headers.TryAddWithoutValidation("Authorization", auth);
                HttpResponseMessage resp;
                using (var cts = new CancellationTokenSource(timeoutMs))
                {
                    try { resp = Http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, cts.Token).GetAwaiter().GetResult(); }
                    catch (TaskCanceledException) { throw new McpException("HTTP request to " + Spec.Url + " timed out"); }
                    catch (HttpRequestException ex) { throw new McpException(ex.InnerException != null ? ex.InnerException.Message : ex.Message); }
                    using (resp)
                    {
                        IEnumerable<string> sid;
                        if (resp.Headers.TryGetValues("Mcp-Session-Id", out sid)) { string s = sid.FirstOrDefault(); if (!string.IsNullOrEmpty(s)) _session = s; }
                        int st = (int)resp.StatusCode;
                        if (st == 401 || st == 403)
                            throw new McpException("AUTH_REQUIRED (HTTP " + st + " at " + Spec.Url + "). Run `mcp_orchestrator(action: \"authenticate\", server_name: \"" + Name + "\")` for OAuth 2.1 browser login, or pass `bearer_token: \"...\"` with action='connect'.");
                        if (st >= 400)
                        {
                            string body = resp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                            throw new McpException("HTTP " + st + " from " + Spec.Url + ": " + (body.Length > 200 ? body.Substring(0, 200) : body));
                        }
                        // JSON reply, or an SSE stream that carries the response (and possibly server requests) as data: lines
                        using (var stream = resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult())
                        using (var rd = new StreamReader(stream, Encoding.UTF8))
                        {
                            var data = new StringBuilder();
                            string line;
                            while ((line = rd.ReadLine()) != null)
                            {
                                if (cts.IsCancellationRequested) break;
                                if (line.StartsWith("data:")) { data.Append(line.Substring(5).Trim()); continue; }
                                if (line.Length == 0 && data.Length > 0) { HandleLine(data.ToString()); data.Clear(); if (IsAnswered(id)) break; continue; }
                                if (!line.StartsWith("event:") && !line.StartsWith("id:") && !line.StartsWith(":") && !line.StartsWith("retry:")) data.Append(line);
                            }
                            if (data.Length > 0) HandleLine(data.ToString());
                        }
                    }
                }
            }
            // a 202 / empty reply to a request leaves nothing to wait for
            if (id != null && !IsAnswered(id))
            {
                TaskCompletionSource<object> tcs;
                long key = Convert.ToInt64(id, System.Globalization.CultureInfo.InvariantCulture);
                lock (_gate) { if (_pending.TryGetValue(key, out tcs)) _pending.Remove(key); }
                if (tcs != null) tcs.TrySetResult(new Dictionary<string, object>());
            }
        }

        bool IsAnswered(object id)
        {
            if (id == null) return true;
            long key = Convert.ToInt64(id, System.Globalization.CultureInfo.InvariantCulture);
            lock (_gate) return !_pending.ContainsKey(key);
        }

        // ── tools ──

        public void FetchTools(int timeoutMs)
        {
            var res = Request("tools/list", null, timeoutMs) as Dictionary<string, object>;
            var list = new List<McpToolInfo>();
            object tv;
            var arr = res != null && res.TryGetValue("tools", out tv) ? tv as object[] : null;
            if (arr == null && res != null && res.TryGetValue("tools", out tv) && tv is System.Collections.ArrayList) arr = ((System.Collections.ArrayList)tv).ToArray();
            if (arr != null)
                foreach (var o in arr)
                {
                    var t = o as Dictionary<string, object>;
                    if (t == null) continue;
                    object n, d, s;
                    if (!t.TryGetValue("name", out n) || !(n is string)) continue;
                    list.Add(new McpToolInfo { Name = (string)n, Description = t.TryGetValue("description", out d) ? (d as string ?? "") : "", InputSchema = t.TryGetValue("inputSchema", out s) && s is Dictionary<string, object> ? (Dictionary<string, object>)s : new Dictionary<string, object> { { "type", "object" }, { "properties", new Dictionary<string, object>() } } });
                }
            Tools = list;
            McpManager.CacheManifest(Spec, list);
            Notify();
        }

        static bool LooksReadOnly(string name)
        {
            string l = name.ToLowerInvariant();
            return l.StartsWith("get_") || l.StartsWith("list_") || l.StartsWith("read_") || l.StartsWith("search_");
        }

        /// <summary>tools/call: wakes a hibernated server, 3 s cache for read-only names, text content joined; isError → "Error: …".</summary>
        public string CallTool(string tool, Dictionary<string, object> args)
        {
            if (!Connected && !Start(30000)) throw new McpException("MCP server '" + Name + "' failed to initialize: " + Error);
            string cacheKey = LooksReadOnly(tool) ? tool + ":" + Js.Serialize(args ?? new Dictionary<string, object>()) : null;
            lock (_readCache)
            {
                Tuple<string, DateTime> hit;
                if (cacheKey != null && _readCache.TryGetValue(cacheKey, out hit) && (DateTime.UtcNow - hit.Item2).TotalSeconds < 3) return hit.Item1;
            }
            var sw = Stopwatch.StartNew();
            Interlocked.Increment(ref CallCount);
            try
            {
                var res = Request("tools/call", new Dictionary<string, object> { { "name", tool }, { "arguments", args ?? new Dictionary<string, object>() } }, 60000) as Dictionary<string, object>;
                int ms = (int)sw.ElapsedMilliseconds;
                AvgLatencyMs = AvgLatencyMs == 0 ? ms : (AvgLatencyMs * 3 + ms) / 4;
                string text = ContentText(res);
                object ie;
                if (res != null && res.TryGetValue("isError", out ie) && ie is bool && (bool)ie) { Interlocked.Increment(ref ErrorCount); return "Error: " + (text.Length > 0 ? text : "Unknown error"); }
                string output = text.Length == 0 ? "Success" : text;
                if (cacheKey != null) lock (_readCache) _readCache[cacheKey] = Tuple.Create(output, DateTime.UtcNow);
                Notify();
                return output;
            }
            catch (McpException) { Interlocked.Increment(ref ErrorCount); Notify(); throw; }
        }

        /// <summary>Text parts joined; images and binary resources described instead of dropped silently.</summary>
        static string ContentText(Dictionary<string, object> res)
        {
            object cv;
            if (res == null || !res.TryGetValue("content", out cv)) return "";
            var arr = cv as object[]; if (arr == null && cv is System.Collections.ArrayList) arr = ((System.Collections.ArrayList)cv).ToArray();
            if (arr == null) return "";
            var parts = new List<string>();
            foreach (var o in arr)
            {
                var c = o as Dictionary<string, object>;
                if (c == null) continue;
                object type, text, mime, resource;
                c.TryGetValue("type", out type);
                if (c.TryGetValue("text", out text) && text is string) parts.Add((string)text);
                else if ((type as string) == "resource" && c.TryGetValue("resource", out resource) && resource is Dictionary<string, object>)
                {
                    var r = (Dictionary<string, object>)resource; object rt, uri;
                    if (r.TryGetValue("text", out rt) && rt is string) parts.Add((string)rt);
                    else parts.Add("[resource " + (r.TryGetValue("uri", out uri) ? uri : "") + "]");
                }
                else parts.Add("[" + (type ?? "content") + (c.TryGetValue("mimeType", out mime) ? " " + mime : "") + "]");
            }
            return string.Join("\n", parts);
        }
    }

    // ── manager ──────────────────────────────────────────────────────────────

    public static class McpManager
    {
        static readonly object Gate = new object();
        static readonly Dictionary<string, McpConnection> Conns = new Dictionary<string, McpConnection>(StringComparer.Ordinal);
        static readonly HashSet<string> Failed = new HashSet<string>(), Probing = new HashSet<string>();
        public static readonly HashSet<string> Mounted = new HashSet<string>();
        static readonly JavaScriptSerializer Js = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
        static string _workspace;
        /// <summary>Bumped whenever the visible tool set can change (schemas are rebuilt mid-run when it moves).</summary>
        public static int Version;
        public static event Action Changed;
        static void Bump() { Interlocked.Increment(ref Version); var c = Changed; if (c != null) c(); }

        public static List<McpConnection> Connections { get { lock (Gate) return Conns.Values.OrderBy(c => c.Name, StringComparer.Ordinal).ToList(); } }
        public static McpConnection Get(string name) { lock (Gate) { McpConnection c; return Conns.TryGetValue(name, out c) ? c : null; } }

        // manifest cache (PNSGanglionRouter.cachedServerManifests): tool lists survive restarts, keyed by what would run
        static string ManifestPath { get { return Path.Combine(Defaults.Dir, "mcp-manifests.json"); } }
        static Dictionary<string, object> _manifests;

        static Dictionary<string, object> Manifests()
        {
            if (_manifests != null) return _manifests;
            try { _manifests = File.Exists(ManifestPath) ? Js.DeserializeObject(File.ReadAllText(ManifestPath)) as Dictionary<string, object> : null; }
            catch (ArgumentException) { _manifests = null; } catch (InvalidOperationException) { _manifests = null; } catch (IOException) { _manifests = null; }
            if (_manifests == null) _manifests = new Dictionary<string, object>();
            return _manifests;
        }

        static string ManifestKey(McpServerSpec s)
        {
            using (var sha = SHA256.Create()) return s.Name + "#" + BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(s.Fingerprint))).Replace("-", "").Substring(0, 12).ToLowerInvariant();
        }

        public static void CacheManifest(McpServerSpec s, List<McpToolInfo> tools)
        {
            lock (Gate)
            {
                Manifests()[ManifestKey(s)] = tools.Select(t => new Dictionary<string, object> { { "name", t.Name }, { "description", t.Description }, { "inputSchema", t.InputSchema } }).ToArray();
                try { Directory.CreateDirectory(Defaults.Dir); Defaults.WriteAtomic(ManifestPath, Js.Serialize(Manifests())); }
                catch (IOException ex) { Debug.WriteLine("mcp manifest save: " + ex.Message); }
            }
            Bump();
        }

        public static List<McpToolInfo> CachedTools(McpServerSpec s)
        {
            lock (Gate)
            {
                object v;
                if (!Manifests().TryGetValue(ManifestKey(s), out v)) return new List<McpToolInfo>();
                var arr = v as object[]; if (arr == null && v is System.Collections.ArrayList) arr = ((System.Collections.ArrayList)v).ToArray();
                if (arr == null) return new List<McpToolInfo>();
                return arr.OfType<Dictionary<string, object>>().Select(d =>
                {
                    object n, ds, sc;
                    return new McpToolInfo { Name = d.TryGetValue("name", out n) ? n as string ?? "" : "", Description = d.TryGetValue("description", out ds) ? ds as string ?? "" : "", InputSchema = d.TryGetValue("inputSchema", out sc) && sc is Dictionary<string, object> ? (Dictionary<string, object>)sc : new Dictionary<string, object> { { "type", "object" } } };
                }).Where(t => t.Name.Length > 0).ToList();
            }
        }

        /// <summary>Live tools when the server is connected, else the cached manifest.</summary>
        public static List<McpToolInfo> EffectiveTools(McpConnection c) { return c.Tools.Count > 0 ? c.Tools : CachedTools(c.Spec); }

        // ── sync ──

        /// <summary>syncWithDiscoveredServers: discovery + workspace trust for repo-declared servers; changed specs restart,
        /// vanished ones stop. Uncached servers are probed in the background (2 at a time) and stdio ones hibernate afterwards.</summary>
        public static void Sync(string ws, bool probe)
        {
            var specs = McpDiscovery.Scan(ws, null);
            if (specs.Any(s => s.IsWorkspaceScoped) && !RulesEngine.ExecConfigTrusted(ws)) specs = specs.Where(s => !s.IsWorkspaceScoped).ToList();
            var toStop = new List<McpConnection>();
            lock (Gate)
            {
                _workspace = ws;
                foreach (var name in Conns.Keys.ToList())
                    if (!specs.Any(s => s.Name == name)) { toStop.Add(Conns[name]); Conns.Remove(name); }
                foreach (var s in specs)
                {
                    McpConnection existing;
                    if (Conns.TryGetValue(s.Name, out existing) && existing.Spec.Fingerprint == s.Fingerprint && existing.Spec.Source == s.Source) { existing.Workspace = ws; continue; }
                    if (existing != null) toStop.Add(existing);
                    var c = new McpConnection(s) { Workspace = ws };
                    c.Changed += Bump;
                    Conns[s.Name] = c;
                    Failed.Remove(s.Name);
                }
            }
            foreach (var c in toStop) ThreadPool.QueueUserWorkItem(_ => c.Stop());
            Bump();
            if (probe) ProbeUncached();
        }

        static string _syncedFor = "\u0000";
        static DateTime _syncedAt;

        /// <summary>Sync once per workspace (and again after 60 s, so edited config files are picked up), then probe in the background.</summary>
        public static void EnsureSynced(string ws)
        {
            string key = ws ?? "";
            lock (Gate) if (_syncedFor == key && (DateTime.UtcNow - _syncedAt).TotalSeconds < 60) return;
            Sync(ws, true);
            lock (Gate) { _syncedFor = key; _syncedAt = DateTime.UtcNow; }
        }

        public static void ProbeUncached()
        {
            List<McpConnection> todo;
            lock (Gate) todo = Conns.Values.Where(c => !c.Connected && !c.Starting && CachedTools(c.Spec).Count == 0 && !Failed.Contains(c.Name) && !Probing.Contains(c.Name)).OrderBy(c => c.Name).ToList();
            if (todo.Count == 0) return;
            lock (Gate) foreach (var c in todo) Probing.Add(c.Name);
            var queue = new Queue<McpConnection>(todo);
            for (int w = 0; w < Math.Min(2, todo.Count); w++)
                ThreadPool.QueueUserWorkItem(_ =>
                {
                    while (true)
                    {
                        McpConnection c;
                        lock (queue) { if (queue.Count == 0) return; c = queue.Dequeue(); }
                        try { Probe(c, 20000); }
                        finally { lock (Gate) Probing.Remove(c.Name); Bump(); }
                    }
                });
        }

        static void Probe(McpConnection c, int timeoutMs)
        {
            bool ok = c.Start(timeoutMs) && c.Tools.Count > 0;
            if (!ok) lock (Gate) Failed.Add(c.Name);
            // hibernate: a stdio server nobody has called yet stops again; its tools stay mounted from the cache
            if (!c.Spec.IsRemote && c.CallCount == 0) c.Stop();
        }

        /// <summary>Waits (bounded) until no background probe is running — before status / search answers.</summary>
        public static void WaitForProbes(int timeoutMs)
        {
            var sw = Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < timeoutMs) { lock (Gate) if (Probing.Count == 0) return; Thread.Sleep(80); }
        }

        public static void StopAll() { foreach (var c in Connections) c.Stop(); }

        // ── agent surface ──

        public static string ToolName(string server, string tool) { return "mcp__" + server + "__" + tool; }

        public static List<Tuple<string, McpToolInfo>> AllTools()
        {
            return Connections.SelectMany(c => EffectiveTools(c).Select(t => Tuple.Create(c.Name, t))).ToList();
        }

        static readonly HashSet<string> StopWords = new HashSet<string> { "the", "a", "an", "and", "or", "to", "of", "in", "on", "for", "with", "my", "me", "please", "this", "that", "is", "it", "from", "use", "using" };

        /// <summary>eagerExternalToolNames: the tools most relevant to the request (server, tool name and description words
        /// that occur in it), at most <paramref name="max"/>, plus everything mcp_orchestrator mounted.</summary>
        public static HashSet<string> EagerToolNames(string prompt, int max)
        {
            var words = new HashSet<string>(Regex.Matches((prompt ?? "").ToLowerInvariant(), @"[\p{L}\p{N}]+").Cast<Match>().Select(m => m.Value).Where(w => w.Length > 2 && !StopWords.Contains(w)));
            var scored = new List<Tuple<string, double>>();
            foreach (var t in AllTools())
            {
                string server = t.Item1.ToLowerInvariant();
                double score = 0;
                if (words.Contains(server) || words.Any(w => server.Contains(w) && w.Length > 3)) score += 3;
                foreach (var part in Regex.Split(t.Item2.Name.ToLowerInvariant(), @"[_\-\.]+")) if (part.Length > 2 && words.Contains(part)) score += 2;
                foreach (Match m in Regex.Matches(t.Item2.Description.ToLowerInvariant(), @"[\p{L}\p{N}]+")) if (m.Value.Length > 3 && words.Contains(m.Value)) score += 0.5;
                if (score > 0) scored.Add(Tuple.Create(ToolName(t.Item1, t.Item2.Name), score));
            }
            var set = new HashSet<string>(scored.OrderByDescending(s => s.Item2).ThenBy(s => s.Item1, StringComparer.Ordinal).Take(max).Select(s => s.Item1));
            lock (Gate) set.UnionWith(Mounted);
            return set;
        }

        /// <summary>The OpenAI-style function schema for one MCP tool (inputSchema with type / properties guaranteed).</summary>
        public static Dictionary<string, object> Schema(string server, McpToolInfo t)
        {
            var p = new Dictionary<string, object>(t.InputSchema ?? new Dictionary<string, object>());
            if (!p.ContainsKey("type")) p["type"] = "object";
            if ((p["type"] as string) == "object" && !p.ContainsKey("properties")) p["properties"] = new Dictionary<string, object>();
            p.Remove("$schema");
            string desc = "[" + server + "] " + t.Description;
            return new Dictionary<string, object> { { "name", ToolName(server, t.Name) }, { "description", desc.Length > 1000 ? desc.Substring(0, 1000) : desc }, { "parameters", p } };
        }

        public static List<Dictionary<string, object>> SchemasFor(HashSet<string> names)
        {
            return AllTools().Where(t => names.Contains(ToolName(t.Item1, t.Item2.Name))).Select(t => Schema(t.Item1, t.Item2)).ToList();
        }

        /// <summary>compactPromptSummary: one line per server so the first turn knows the real MCP status.</summary>
        public static string PromptSummary()
        {
            var conns = Connections;
            if (conns.Count == 0) return "";
            var lines = new List<string> { "## Discovered External MCP Servers (Use `mcp_orchestrator` to inspect/search/connect)" };
            foreach (var c in conns.Take(16))
            {
                var tools = EffectiveTools(c);
                string state;
                if (c.Connected) state = "ONLINE (" + tools.Count + " tools)";
                else if (tools.Count > 0) state = "READY (" + tools.Count + " cached tools)";
                else if (c.Error != null && c.Error.Contains("AUTH_REQUIRED")) state = "AUTH_REQUIRED (" + (c.Spec.Url ?? c.Spec.Source) + ")";
                else if (!string.IsNullOrEmpty(c.Error)) state = "OFFLINE (" + (c.Error.Length > 60 ? c.Error.Substring(0, 60) : c.Error) + ")";
                else state = "DISCOVERED (" + c.Spec.Source + ")";
                lines.Add("- `" + c.Name + "`: " + state);
            }
            return "\n\n" + string.Join("\n", lines);
        }

        /// <summary>meshStatusSummary for mcp_orchestrator status / discover.</summary>
        public static string StatusSummary()
        {
            var conns = Connections;
            if (conns.Count == 0) return "No external MCP servers configured. Add one with `mcp_orchestrator(action: \"connect\", server_name: \"...\", url: \"...\")` or `command` + `args`, or declare it in ~/.microcode/mcp.json or the workspace .mcp.json.";
            int total = conns.Sum(c => EffectiveTools(c).Count);
            var lines = new List<string> { "Hyper-Mesh MCP Status (" + conns.Count + " servers, " + total + " external tools):" };
            foreach (var c in conns)
            {
                var tools = EffectiveTools(c);
                string state = c.Connected ? "ONLINE" : tools.Count > 0 ? "READY (HIBERNATED)" : !string.IsNullOrEmpty(c.Error) ? "ERROR: " + c.Error : "STANDBY";
                lines.Add("- [" + state + "] " + c.Name + " (source: " + c.Spec.Source + ", calls: " + c.CallCount + ", avg: " + c.AvgLatencyMs + "ms, heals: 0) -> tools (" + tools.Count + "): [" + string.Join(", ", tools.Select(t => t.Name)) + "]");
            }
            return string.Join("\n", lines);
        }

        /// <summary>Classifies an external MCP server into a PNS tract (Cognitive / Reflex / Autonomic).</summary>
        public static string TractFor(string name, List<McpToolInfo> tools)
        {
            string s = ((name ?? "") + " " + string.Join(" ", (tools ?? new List<McpToolInfo>()).Select(t => t.Name))).ToLowerInvariant();
            if (s.Contains("browser") || s.Contains("playwright") || s.Contains("chrome") || s.Contains("dom")) return "Browser";
            if (s.Contains("sql") || s.Contains("bigquery") || s.Contains("spanner") || s.Contains("postgres") || s.Contains("firestore")) return "Data";
            if (s.Contains("git") || s.Contains("lsp") || s.Contains("file") || s.Contains("code")) return "Coding";
            if (s.Contains("cloud") || s.Contains("gcs") || s.Contains("deploy") || s.Contains("docker")) return "Cloud";
            return "General";
        }

        /// <summary>Runs mcp__server__tool with auto-restart recovery if the server died. Server names are matched longest-first.</summary>
        public static string Call(string fullName, Dictionary<string, object> args)
        {
            if (!fullName.StartsWith("mcp__")) return "Error: not an MCP tool: " + fullName;
            string rest = fullName.Substring(5);
            var conn = Connections.OrderByDescending(c => c.Name.Length).FirstOrDefault(c => rest.StartsWith(c.Name + "__"));
            if (conn == null) return "Error: no MCP server for " + fullName + ". Use mcp_orchestrator(action: \"status\") to see connected servers.";
            string tool = rest.Substring(conn.Name.Length + 2);
            try { return conn.CallTool(tool, args); }
            catch (McpException)
            {
                try
                {
                    conn.Stop();
                    conn.Start(20000);
                    return conn.CallTool(tool, args);
                }
                catch (McpException ex2) { return "Error: " + ex2.Message; }
            }
        }

        public static bool LooksReadOnlyTool(string fullName)
        {
            int i = fullName.LastIndexOf("__", StringComparison.Ordinal);
            string t = (i >= 0 ? fullName.Substring(i + 2) : fullName).ToLowerInvariant();
            return t.StartsWith("get_") || t.StartsWith("list_") || t.StartsWith("read_") || t.StartsWith("search_") || t.StartsWith("find_") || t.StartsWith("query_") || t.StartsWith("describe_");
        }

        // ── credentials (MCPAuthCenter.saveStaticBearer): never in mcp.json, DPAPI-sealed per origin ──

        static string Origin(string url) { Uri u; return url != null && Uri.TryCreate(url, UriKind.Absolute, out u) ? u.Scheme + "://" + u.Authority : null; }

        public static void SaveStaticBearer(string token, string url)
        {
            string o = Origin(url);
            if (o == null || string.IsNullOrWhiteSpace(token)) return;
            Defaults.Set("mcpBearer:" + o.ToLowerInvariant(), Dpapi.Protect(token.Trim()));
        }

        public static string StoredBearer(string url)
        {
            string o = Origin(url);
            return o == null ? null : Dpapi.Unprotect(Defaults.Str("mcpBearer:" + o.ToLowerInvariant(), null));
        }

        static string GlobalConfigPath { get { return Path.Combine(TaskFiles.Home, "mcp.json"); } }

        /// <summary>Adds or replaces a server in ~/.microcode/mcp.json (the Mac keeps stdio connects in memory only; here they persist
        /// so the next sync does not drop them).</summary>
        public static void SaveGlobalServer(string name, string url, string command, List<string> args)
        {
            Dictionary<string, object> root = null;
            try { if (File.Exists(GlobalConfigPath)) root = Js.DeserializeObject(File.ReadAllText(GlobalConfigPath)) as Dictionary<string, object>; }
            catch (ArgumentException) { } catch (InvalidOperationException) { }
            if (root == null) root = new Dictionary<string, object>();
            object sv;
            var servers = root.TryGetValue("mcpServers", out sv) && sv is Dictionary<string, object> ? (Dictionary<string, object>)sv : new Dictionary<string, object>();
            servers[name] = !string.IsNullOrEmpty(url) ? (object)new Dictionary<string, object> { { "serverUrl", url } } : new Dictionary<string, object> { { "command", command }, { "args", (args ?? new List<string>()).ToArray() } };
            root["mcpServers"] = servers;
            Directory.CreateDirectory(TaskFiles.Home);
            Defaults.WriteAtomic(GlobalConfigPath, Js.Serialize(root));
        }

        public static void RemoveGlobalServer(string name)
        {
            if (!File.Exists(GlobalConfigPath)) return;
            try
            {
                var root = Js.DeserializeObject(File.ReadAllText(GlobalConfigPath)) as Dictionary<string, object>;
                object sv;
                if (root == null || !root.TryGetValue("mcpServers", out sv) || !(sv is Dictionary<string, object>)) return;
                ((Dictionary<string, object>)sv).Remove(name);
                Defaults.WriteAtomic(GlobalConfigPath, Js.Serialize(root));
            }
            catch (ArgumentException) { } catch (InvalidOperationException) { }
        }

        static readonly Dictionary<string, string> OfficialEndpoints = new Dictionary<string, string> { { "canva", "https://mcp.canva.com/mcp" }, { "figma", "https://mcp.figma.com/mcp" }, { "linear", "https://mcp.linear.app/mcp" } };

        /// <summary>connectOrConfigureServer: registers a remote URL (known official endpoints for canva / figma / linear) or a
        /// local command, starts it and mounts its tools.</summary>
        public static string Connect(string rawName, string url, string command, List<string> args, string bearer)
        {
            string name = (rawName ?? "").Trim().ToLowerInvariant();
            if (name.Length == 0) return "Error: `server_name` is required (e.g. 'canva', 'github', 'figma').";
            string ws; lock (Gate) ws = _workspace;
            if (string.IsNullOrWhiteSpace(url) && string.IsNullOrWhiteSpace(command) && Get(name) == null)
            {
                string official; if (OfficialEndpoints.TryGetValue(name, out official)) url = official;
            }
            if (!string.IsNullOrWhiteSpace(url))
            {
                if (!string.IsNullOrWhiteSpace(bearer)) SaveStaticBearer(bearer, url.Trim());
                SaveGlobalServer(name, url.Trim(), null, null);
            }
            else if (!string.IsNullOrWhiteSpace(command)) SaveGlobalServer(name, null, command.Trim(), args);
            Sync(ws, false);
            var conn = Get(name);
            if (conn == null) return "MCP server '" + name + "' was not found in local configs (`~/.microcode/mcp.json`, `~/.cursor/mcp.json`, plugins). Pass `url` (for remote HTTP MCP) or `command` + `args` (for local stdio MCP) to register it.";
            lock (Gate) Failed.Remove(name);
            conn.Stop();
            conn.Start(30000);
            if (conn.Tools.Count > 0)
            {
                lock (Gate) foreach (var t in conn.Tools) Mounted.Add(ToolName(name, t.Name));
                Bump();
                return "✅ Connected MCP Server '" + name + "' (" + conn.Spec.Source + ")\nEndpoint/Command: " + (conn.Spec.Url ?? conn.Spec.Command + (conn.Spec.Args.Count > 0 ? " " + string.Join(" ", conn.Spec.Args) : "")) + "\nExposed Tools (" + conn.Tools.Count + "): " + string.Join(", ", conn.Tools.Select(t => "`" + ToolName(name, t.Name) + "`"));
            }
            return "⚠️ MCP Server '" + name + "' Registered (" + (conn.Spec.Url ?? conn.Spec.Command) + ") — Handshake Status: " + (conn.Error ?? "Waiting for server response") + "\nNext Step: for a token-protected remote endpoint pass `bearer_token` to `mcp_orchestrator(action: \"connect\", ...)` or add an Authorization header in ~/.microcode/mcp.json.";
        }

        /// <summary>The mcp_orchestrator agent tool.</summary>
        public static string Orchestrate(Dictionary<string, object> a)
        {
            Func<string, string> arg = k => { object v; return a != null && a.TryGetValue(k, out v) && v != null ? Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture) : ""; };
            string action = arg("action").ToLowerInvariant(); if (action.Length == 0) action = "status";
            string ws; lock (Gate) ws = _workspace;
            switch (action)
            {
                case "status": case "list": case "discover":
                    if (action == "discover") Sync(ws, false);
                    ProbeUncached(); WaitForProbes(25000);
                    return StatusSummary();
                case "connect": case "configure":
                    return Connect(arg("server_name").Length > 0 ? arg("server_name") : arg("query"), arg("url"), arg("command"), arg("args").Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries).ToList(), arg("bearer_token"));
                case "search_tools": case "search":
                {
                    string q = arg("query").ToLowerInvariant();
                    ProbeUncached(); WaitForProbes(25000);
                    var hits = AllTools().Where(t => q.Length == 0 || t.Item1.ToLowerInvariant().Contains(q) || t.Item2.Name.ToLowerInvariant().Contains(q) || t.Item2.Description.ToLowerInvariant().Contains(q)).ToList();
                    if (hits.Count == 0) return "No external MCP tools matched '" + q + "'.";
                    lock (Gate) foreach (var h in hits.Take(16)) Mounted.Add(ToolName(h.Item1, h.Item2.Name));
                    Bump();
                    return string.Join("\n", hits.Select(h => "- `" + ToolName(h.Item1, h.Item2.Name) + "`: " + h.Item2.Description));
                }
                case "authenticate": case "login": case "sign_in": case "signin":
                    return AuthenticateOAuth(arg("server_name").Length > 0 ? arg("server_name") : arg("query"), arg("url"), arg("bearer_token"));
                case "restart":
                {
                    var c = Get(arg("server_name"));
                    if (c == null) return "MCP server '" + arg("server_name") + "' not found in discovered servers.";
                    lock (Gate) Failed.Remove(c.Name);
                    c.Stop(); c.Start(30000);
                    lock (Gate) foreach (var t in c.Tools) Mounted.Add(ToolName(c.Name, t.Name));
                    Bump();
                    return "Restarted MCP server '" + c.Name + "' (" + (c.Connected ? "ONLINE" : "STARTING") + ", " + c.Tools.Count + " tools)." + (c.Error != null && !c.Connected ? " Error: " + c.Error : "");
                }
                case "synthesize": case "create":
                    return SynthesizePythonServer(arg("server_name").Length > 0 ? arg("server_name") : arg("query"), arg("description"), ws);
                default:
                    return "Unknown mcp_orchestrator action '" + action + "'. Supported: status, discover, connect, authenticate, search_tools, restart, synthesize.";
            }
        }

        /// <summary>MCP OAuth 2.1 (RFC 9728 Protected Resource + Authorization Server Metadata + PKCE S256 loopback callback).</summary>
        public static string AuthenticateOAuth(string rawName, string url, string explicitBearer)
        {
            string name = (rawName ?? "").Trim().ToLowerInvariant();
            if (name.Length == 0) return "Error: `server_name` is required for 'authenticate'.";
            var conn = Get(name);
            string targetUrl = !string.IsNullOrWhiteSpace(url) ? url.Trim() : (conn != null ? conn.Spec.Url : null);
            if (string.IsNullOrWhiteSpace(targetUrl))
            {
                string official;
                if (OfficialEndpoints.TryGetValue(name, out official)) targetUrl = official;
            }
            if (string.IsNullOrWhiteSpace(targetUrl)) return "Error: no remote URL registered for MCP server '" + name + "'.";
            if (!string.IsNullOrWhiteSpace(explicitBearer))
                return Connect(name, targetUrl, null, null, explicitBearer);

            try
            {
                DotminiNet.EnableTls();
                string origin = Origin(targetUrl);
                if (origin == null) return "Error: invalid MCP URL '" + targetUrl + "'.";

                // Step 1: Discover Authorization Server via RFC 9728
                string authServer = origin;
                try
                {
                    string prm = DotminiNet.Http.GetStringAsync(origin + "/.well-known/oauth-protected-resource").Result;
                    var prmObj = Js.DeserializeObject(prm) as Dictionary<string, object>;
                    object asArr;
                    if (prmObj != null && prmObj.TryGetValue("authorization_servers", out asArr) && asArr is object[] && ((object[])asArr).Length > 0)
                        authServer = Convert.ToString(((object[])asArr)[0]).TrimEnd('/');
                }
                catch { }

                string metaRaw = DotminiNet.Http.GetStringAsync(authServer + "/.well-known/oauth-authorization-server").Result;
                var meta = Js.DeserializeObject(metaRaw) as Dictionary<string, object>;
                if (meta == null) return "Error: server does not expose /.well-known/oauth-authorization-server metadata.";
                string authEndpoint = DJ.Str(meta, "authorization_endpoint");
                string tokenEndpoint = DJ.Str(meta, "token_endpoint");
                string regEndpoint = DJ.Str(meta, "registration_endpoint");
                if (string.IsNullOrEmpty(authEndpoint) || string.IsNullOrEmpty(tokenEndpoint))
                    return "Error: incomplete OAuth metadata from " + authServer + ". Pass `bearer_token` directly with action='connect'.";

                // Step 2: Start ephemeral loopback callback listener
                var cbListener = new TcpListener(IPAddress.Loopback, 0);
                cbListener.Start();
                int cbPort = ((IPEndPoint)cbListener.LocalEndpoint).Port;
                string redirectUri = "http://127.0.0.1:" + cbPort + "/callback";

                // Step 3: Dynamic Client Registration (RFC 7591) if supported
                string clientId = "microcode-windows";
                if (!string.IsNullOrEmpty(regEndpoint))
                {
                    try
                    {
                        var regBody = Js.Serialize(new Dictionary<string, object> {
                            { "client_name", "MicroCode Windows" },
                            { "redirect_uris", new[] { redirectUri } },
                            { "grant_types", new[] { "authorization_code" } },
                            { "response_types", new[] { "code" } },
                            { "token_endpoint_auth_method", "none" }
                        });
                        var regResp = DotminiNet.Http.PostAsync(regEndpoint, new StringContent(regBody, Encoding.UTF8, "application/json")).Result;
                        var regObj = Js.DeserializeObject(regResp.Content.ReadAsStringAsync().Result) as Dictionary<string, object>;
                        string cid = DJ.Str(regObj, "client_id");
                        if (!string.IsNullOrEmpty(cid)) clientId = cid;
                    }
                    catch { }
                }

                // Step 4: PKCE S256 verifier + challenge
                var rngBytes = new byte[32];
                using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(rngBytes);
                string verifier = Convert.ToBase64String(rngBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
                byte[] hash;
                using (var sha = SHA256.Create()) hash = sha.ComputeHash(Encoding.ASCII.GetBytes(verifier));
                string challenge = Convert.ToBase64String(hash).TrimEnd('=').Replace('+', '-').Replace('/', '_');
                string state = Guid.NewGuid().ToString("N");

                string fullAuthUrl = authEndpoint + (authEndpoint.Contains("?") ? "&" : "?")
                    + "response_type=code&client_id=" + Uri.EscapeDataString(clientId)
                    + "&redirect_uri=" + Uri.EscapeDataString(redirectUri)
                    + "&code_challenge=" + Uri.EscapeDataString(challenge)
                    + "&code_challenge_method=S256&state=" + Uri.EscapeDataString(state);

                DotminiNet.OpenExternalUrl(fullAuthUrl);

                // Wait up to 90s for browser callback
                string code = null;
                var deadline = DateTime.UtcNow.AddSeconds(90);
                while (DateTime.UtcNow < deadline && code == null)
                {
                    if (!cbListener.Pending()) { Thread.Sleep(100); continue; }
                    using (var client = cbListener.AcceptTcpClient())
                    {
                        var ns = client.GetStream();
                        var buf = new byte[4096];
                        int n = ns.Read(buf, 0, buf.Length);
                        string reqLine = Encoding.ASCII.GetString(buf, 0, n).Split('\n')[0];
                        int sp1 = reqLine.IndexOf(' '), sp2 = sp1 > 0 ? reqLine.IndexOf(' ', sp1 + 1) : -1;
                        if (sp2 > sp1)
                        {
                            string pathQ = reqLine.Substring(sp1 + 1, sp2 - sp1 - 1);
                            int qi = pathQ.IndexOf('?');
                            if (qi >= 0)
                            {
                                foreach (var kv in pathQ.Substring(qi + 1).Split('&'))
                                {
                                    int eq = kv.IndexOf('=');
                                    if (eq > 0 && kv.Substring(0, eq) == "code") code = Uri.UnescapeDataString(kv.Substring(eq + 1));
                                }
                            }
                        }
                        byte[] html = Encoding.UTF8.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n<html><body style='font-family:sans-serif;background:#141417;color:#fff;padding:40px;text-align:center'><h2>MicroCode MCP Authorized</h2><p>You can close this browser tab and return to MicroCode.</p></body></html>");
                        ns.Write(html, 0, html.Length);
                    }
                }
                cbListener.Stop();
                if (string.IsNullOrEmpty(code)) return "OAuth login timed out waiting for browser authorization on " + targetUrl + ".";

                var form = new FormUrlEncodedContent(new[] {
                    new KeyValuePair<string, string>("grant_type", "authorization_code"),
                    new KeyValuePair<string, string>("code", code),
                    new KeyValuePair<string, string>("redirect_uri", redirectUri),
                    new KeyValuePair<string, string>("client_id", clientId),
                    new KeyValuePair<string, string>("code_verifier", verifier)
                });
                var tokResp = DotminiNet.Http.PostAsync(tokenEndpoint, form).Result;
                var tokObj = Js.DeserializeObject(tokResp.Content.ReadAsStringAsync().Result) as Dictionary<string, object>;
                string access = DJ.Str(tokObj, "access_token");
                if (string.IsNullOrEmpty(access)) return "OAuth token exchange failed for '" + name + "': " + tokResp.StatusCode;
                return Connect(name, targetUrl, null, null, access);
            }
            catch (Exception ex)
            {
                return "OAuth 2.1 flow for '" + name + "' failed (" + ex.GetBaseException().Message + "). You can still pass `bearer_token` manually with action='connect'.";
            }
        }

        /// <summary>Synthesizes a ready-to-run stdio Python MCP server in .microcode/mcp/<name>.py and hot-spawns it.</summary>
        public static string SynthesizePythonServer(string rawName, string description, string ws)
        {
            string safe = Regex.Replace((rawName ?? "custom-mcp").ToLowerInvariant(), @"[^a-z0-9_-]+", "-").Trim('-');
            if (safe.Length == 0) safe = "custom-mcp";
            string dir = Path.Combine(!string.IsNullOrEmpty(ws) ? Path.Combine(ws, ".microcode") : TaskFiles.Home, "mcp");
            Directory.CreateDirectory(dir);
            string pyPath = Path.Combine(dir, safe + ".py");
            if (!File.Exists(pyPath))
            {
                string script = "#!/usr/bin/env python3\n"
                    + "import json, sys\n\n"
                    + "TOOLS = [{\"name\": \"ping\", \"description\": " + Js.Serialize(description ?? ("Custom tool for " + safe)) + ", \"inputSchema\": {\"type\": \"object\", \"properties\": {\"message\": {\"type\": \"string\"}}, \"required\": []}}]\n\n"
                    + "def handle(req):\n"
                    + "    mid = req.get(\"id\")\n"
                    + "    m = req.get(\"method\", \"\")\n"
                    + "    if m == \"initialize\":\n"
                    + "        return {\"jsonrpc\": \"2.0\", \"id\": mid, \"result\": {\"protocolVersion\": \"2025-11-25\", \"capabilities\": {\"tools\": {}}, \"serverInfo\": {\"name\": " + Js.Serialize(safe) + ", \"version\": \"1.0.0\"}}}\n"
                    + "    if m == \"tools/list\":\n"
                    + "        return {\"jsonrpc\": \"2.0\", \"id\": mid, \"result\": {\"tools\": TOOLS}}\n"
                    + "    if m == \"tools/call\":\n"
                    + "        params = req.get(\"params\") or {}\n"
                    + "        args = params.get(\"arguments\") or {}\n"
                    + "        return {\"jsonrpc\": \"2.0\", \"id\": mid, \"result\": {\"content\": [{\"type\": \"text\", \"text\": f\"pong from " + safe + ": {args.get('message', 'ok')}\"}]}}\n"
                    + "    return {\"jsonrpc\": \"2.0\", \"id\": mid, \"result\": {}}\n\n"
                    + "for line in sys.stdin:\n"
                    + "    line = line.strip()\n"
                    + "    if not line: continue\n"
                    + "    req = json.loads(line)\n"
                    + "    if \"id\" not in req: continue\n"
                    + "    sys.stdout.write(json.dumps(handle(req)) + \"\\n\")\n"
                    + "    sys.stdout.flush()\n";
                File.WriteAllText(pyPath, script, Encoding.UTF8);
            }
            string connOut = Connect(safe, null, "python", new List<string> { pyPath }, null);
            return "Synthesized Python MCP server at " + pyPath + "\n" + connOut;
        }

        public static Dictionary<string, object> OrchestratorSchema()
        {
            Func<string, string, Dictionary<string, object>> p = (type, d) => new Dictionary<string, object> { { "type", type }, { "description", d } };
            return new Dictionary<string, object>
            {
                { "name", "mcp_orchestrator" },
                { "description", "Hyper-Mesh MCP Engine 2.0: Discover & inspect external MCP servers across MicroCode, Antigravity plugins, Claude, Cursor & Codex ('status' / 'discover'), connect a remote HTTP or local stdio MCP server ('connect'), search external MCP tools ('search_tools'), or restart a server ('restart')." },
                { "parameters", new Dictionary<string, object> { { "type", "object" }, { "required", new[] { "action" } }, { "properties", new Dictionary<string, object>
                    {
                        { "action", p("string", "Action: 'status', 'discover', 'connect', 'authenticate', 'search_tools', 'restart', or 'synthesize'") },
                        { "server_name", p("string", "Target or new MCP server name (e.g. 'canva', 'github', 'figma')") },
                        { "url", p("string", "Remote Streamable HTTP MCP URL for 'connect' (e.g. 'https://mcp.canva.com/mcp')") },
                        { "command", p("string", "Local executable command for stdio 'connect' (e.g. 'npx')") },
                        { "args", p("string", "Space-separated arguments for stdio 'connect'") },
                        { "bearer_token", p("string", "Optional OAuth/Bearer access token for 'connect' on authenticated HTTP MCP endpoints") },
                        { "query", p("string", "Keyword query for 'search_tools'") }
                    } } } }
            };
        }
    }

    /// <summary>Port of MCPServer.swift: local HTTP JSON-RPC 2.0 MCP server exposed at 127.0.0.1:18888/mcp.</summary>
    public static class LocalMcpServer
    {
        static readonly JavaScriptSerializer Js = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
        public static Func<string, Dictionary<string, object>, string> IdeToolHandler;
        public static bool Enabled { get { return Defaults.Bool("mcpServerEnabled", true); } set { Defaults.Set("mcpServerEnabled", value); } }
        public static int RequestCount;
        public static string LastActivity = "No requests yet";

        static Dictionary<string, object> ToolDef(string name, string desc, Dictionary<string, object> props, string[] req)
        {
            return new Dictionary<string, object>
            {
                { "name", name },
                { "description", desc },
                { "inputSchema", new Dictionary<string, object> { { "type", "object" }, { "properties", props }, { "required", req ?? new string[0] } } }
            };
        }

        public static List<Dictionary<string, object>> ToolDefinitions()
        {
            Func<string, string, Dictionary<string, object>> sp = (tp, d) => new Dictionary<string, object> { { "type", tp }, { "description", d } };
            return new List<Dictionary<string, object>>
            {
                ToolDef("file_read", "Read a workspace file", new Dictionary<string, object> { { "path", sp("string", "Workspace-relative or absolute path") } }, new[] { "path" }),
                ToolDef("file_write", "Write or overwrite a file inside workspace", new Dictionary<string, object> { { "path", sp("string", "Target path") }, { "content", sp("string", "UTF-8 file content") } }, new[] { "path", "content" }),
                ToolDef("list_directory_tree", "List directory files", new Dictionary<string, object> { { "path", sp("string", "Directory path (optional)") } }, null),
                ToolDef("grep_search", "Search text inside workspace files", new Dictionary<string, object> { { "query", sp("string", "Text or pattern to search") } }, new[] { "query" }),
                ToolDef("git_status", "Show git status and branch in active workspace", new Dictionary<string, object>(), null),
                ToolDef("playground_run", "Execute code snippet in MicroCode Playground runtime", new Dictionary<string, object> { { "language", sp("string", "python|javascript|powershell|shell") }, { "code", sp("string", "Source code") } }, new[] { "language", "code" }),
                ToolDef("api_studio", "Send HTTP test request via API Studio", new Dictionary<string, object> { { "method", sp("string", "GET|POST|PUT|DELETE") }, { "url", sp("string", "Request URL") }, { "body", sp("string", "Optional JSON body") } }, new[] { "url" }),
                ToolDef("database_studio", "Execute SQL query via Database Studio engine", new Dictionary<string, object> { { "engine", sp("string", "sqlite|postgres|mysql") }, { "connection", sp("string", "DB file or connection string") }, { "sql", sp("string", "SQL query") } }, new[] { "sql" }),
                ToolDef("ide_browser", "Inspect or navigate URL in IDE Web Browser", new Dictionary<string, object> { { "action", sp("string", "navigate|status") }, { "url", sp("string", "URL") } }, null),
                ToolDef("computer_use", "Capture screen or inspect active Windows UI", new Dictionary<string, object> { { "action", sp("string", "screenshot|click|type") }, { "x", sp("integer", "Screen X") }, { "y", sp("integer", "Screen Y") }, { "text", sp("string", "Text to type") } }, new[] { "action" })
            };
        }

        public static string HandleJsonRpc(string rawBody)
        {
            if (!Enabled)
                return Js.Serialize(new Dictionary<string, object> { { "jsonrpc", "2.0" }, { "error", new Dictionary<string, object> { { "code", -32000 }, { "message", "MicroCode Local MCP Server is disabled in Settings." } } } });

            Dictionary<string, object> req;
            try { req = Js.DeserializeObject(rawBody ?? "") as Dictionary<string, object>; }
            catch { req = null; }
            if (req == null)
                return Js.Serialize(new Dictionary<string, object> { { "jsonrpc", "2.0" }, { "error", new Dictionary<string, object> { { "code", -32700 }, { "message", "Invalid JSON" } } } });

            object idVal; req.TryGetValue("id", out idVal);
            string method = DJ.Str(req, "method") ?? "";
            System.Threading.Interlocked.Increment(ref RequestCount);
            LastActivity = DateTime.Now.ToString("HH:mm:ss") + " · " + method;

            if (method == "initialize")
            {
                return Js.Serialize(new Dictionary<string, object>
                {
                    { "jsonrpc", "2.0" },
                    { "id", idVal },
                    { "result", new Dictionary<string, object> {
                        { "protocolVersion", "2025-11-25" },
                        { "capabilities", new Dictionary<string, object> { { "tools", new Dictionary<string, object>() } } },
                        { "serverInfo", new Dictionary<string, object> { { "name", "MicroCode Windows" }, { "version", DotminiNet.AppVersion } } }
                    } }
                });
            }
            if (method == "tools/list")
            {
                return Js.Serialize(new Dictionary<string, object>
                {
                    { "jsonrpc", "2.0" },
                    { "id", idVal },
                    { "result", new Dictionary<string, object> { { "tools", ToolDefinitions() } } }
                });
            }
            if (method == "tools/call")
            {
                var p = DJ.Child(req, "params") ?? new Dictionary<string, object>();
                string tName = DJ.Str(p, "name") ?? "";
                var tArgs = DJ.Child(p, "arguments") ?? new Dictionary<string, object>();
                string text = ExecuteTool(tName, tArgs);
                return Js.Serialize(new Dictionary<string, object>
                {
                    { "jsonrpc", "2.0" },
                    { "id", idVal },
                    { "result", new Dictionary<string, object> {
                        { "content", new[] { new Dictionary<string, object> { { "type", "text" }, { "text", text } } } }
                    } }
                });
            }
            return Js.Serialize(new Dictionary<string, object> { { "jsonrpc", "2.0" }, { "id", idVal }, { "result", new Dictionary<string, object>() } });
        }

        static string ResolveWsPath(string relOrAbs)
        {
            string ws = AppState.Shared.WorkspaceFolder;
            if (string.IsNullOrEmpty(relOrAbs)) return ws ?? Environment.CurrentDirectory;
            if (Path.IsPathRooted(relOrAbs)) return Path.GetFullPath(relOrAbs);
            string root = ws ?? Environment.CurrentDirectory;
            string combined = Path.GetFullPath(Path.Combine(root, relOrAbs.Replace('/', Path.DirectorySeparatorChar)));
            if (!combined.StartsWith(Path.GetFullPath(root), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Path escapes workspace root");
            return combined;
        }

        static string ExecuteTool(string name, Dictionary<string, object> args)
        {
            if (IdeToolHandler != null)
            {
                string custom = IdeToolHandler(name, args);
                if (custom != null) return custom;
            }
            try
            {
                string ws = AppState.Shared.WorkspaceFolder ?? Environment.CurrentDirectory;
                switch (name)
                {
                    case "file_read":
                    {
                        string p = ResolveWsPath(DJ.Str(args, "path"));
                        return File.Exists(p) ? File.ReadAllText(p, Encoding.UTF8) : "Error: file not found: " + p;
                    }
                    case "file_write":
                    {
                        string p = ResolveWsPath(DJ.Str(args, "path"));
                        string dir = Path.GetDirectoryName(p);
                        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
                        File.WriteAllText(p, DJ.Str(args, "content") ?? "", Encoding.UTF8);
                        return "Wrote " + p;
                    }
                    case "list_directory_tree":
                    {
                        string p = ResolveWsPath(DJ.Str(args, "path"));
                        if (!Directory.Exists(p)) return "Error: directory not found: " + p;
                        var items = Directory.GetFileSystemEntries(p).Take(200).Select(x => (Directory.Exists(x) ? "[D] " : "[F] ") + Path.GetFileName(x));
                        return string.Join("\n", items);
                    }
                    case "grep_search":
                    {
                        string q = DJ.Str(args, "query") ?? "";
                        if (q.Length == 0 || !Directory.Exists(ws)) return "No query or workspace.";
                        var hits = new List<string>();
                        foreach (var f in Directory.GetFiles(ws, "*", SearchOption.AllDirectories))
                        {
                            if (f.Contains(".git") || f.Contains("node_modules")) continue;
                            try
                            {
                                var lines = File.ReadAllLines(f);
                                for (int i = 0; i < lines.Length; i++)
                                    if (lines[i].IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0)
                                    {
                                        hits.Add(f + ":" + (i + 1) + ": " + lines[i].Trim());
                                        if (hits.Count >= 50) return string.Join("\n", hits);
                                    }
                            }
                            catch { }
                        }
                        return hits.Count == 0 ? "No matches." : string.Join("\n", hits);
                    }
                    case "git_status":
                    {
                        var psi = new ProcessStartInfo("git", "status -sb") { WorkingDirectory = ws, UseShellExecute = false, RedirectStandardOutput = true, CreateNoWindow = true };
                        var p = Process.Start(psi); string o = p.StandardOutput.ReadToEnd(); p.WaitForExit(5000); return o;
                    }
                    default:
                        return "Tool '" + name + "' requires IDE runtime handler or valid arguments.";
                }
            }
            catch (Exception ex) { return "Error: " + ex.Message; }
        }
    }
}
