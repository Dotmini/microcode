// Port of APIClientView.swift + Services/APIClientService.swift (API Studio): native HTTP client with history, collections,
// environments ({{var}}), auth, AI contract/SLA checks, workspace route scanner, project .env importer, code snippets and cURL.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public class ApiKV { public string Id = Guid.NewGuid().ToString(), Key = "", Value = ""; public bool IsEnabled = true; }

    public class ApiAuth
    {
        public string Type = "None", BearerToken = "", BasicUser = "", BasicPassword = "", ApiKeyName = "X-API-Key", ApiKeyValue = "", ApiKeyIn = "header";
        public ApiAuth Clone() { return (ApiAuth)MemberwiseClone(); }
    }

    public class ApiRequest
    {
        public string Id = Guid.NewGuid().ToString(), Name = "New Request", Method = "GET", Url = "", Body, ContentType = "application/json";
        public Dictionary<string, string> Headers = new Dictionary<string, string>();
        public ApiAuth Auth = new ApiAuth();
        public List<ApiKV> QueryParams = new List<ApiKV>();
        public int Timeout = 30;
        public bool FollowRedirects = true;
        public DateTime Timestamp = DateTime.Now;
    }

    public class ApiResponse
    {
        public int Status, DurationMs, BodySize;
        public string StatusText = "", Body = "";
        public Dictionary<string, string> Headers = new Dictionary<string, string>();
        public DateTime Date = DateTime.Now;
        public bool IsSuccess { get { return Status >= 200 && Status < 300; } }
        public string FormattedBody { get { return ApiService.PrettyJson(Body) ?? Body; } }
    }

    public class ApiCollection { public string Id = Guid.NewGuid().ToString(), Name = ""; public List<ApiRequest> Requests = new List<ApiRequest>(); public DateTime Timestamp = DateTime.Now; }
    public class ApiEnvironment { public string Id = Guid.NewGuid().ToString(), Name = ""; public List<ApiKV> Variables = new List<ApiKV>(); public bool IsActive; }
    public class ApiHistoryEntry { public string Id = Guid.NewGuid().ToString(); public ApiRequest Request; public int Status, Duration; public DateTime Timestamp = DateTime.Now; }
    public class ApiAssertion { public string Name = "", Details = ""; public bool Passed; }

    /// <summary>APIClientService.</summary>
    public class ApiService
    {
        public static readonly ApiService Shared = new ApiService();
        static readonly JavaScriptSerializer Js = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };

        public ApiResponse LastResponse;
        public bool IsLoading, IsScanning;
        public string Error, ScanMessage;
        public List<ApiHistoryEntry> History = new List<ApiHistoryEntry>();
        public List<ApiCollection> Collections = new List<ApiCollection>();
        public List<ApiEnvironment> Environments = new List<ApiEnvironment>();
        public string ActiveEnvironmentId;
        public List<ApiAssertion> Assertions = new List<ApiAssertion>();
        public event Action Changed;
        string _loadedFor;

        public void Notify() { var app = Application.Current; if (app != null) app.Dispatcher.BeginInvoke(new Action(() => { if (Changed != null) Changed(); })); }

        /// <summary>WorkspaceStoragePaths.managedStateFile(named: "api-client"): one store per open project (a global one without a project).</summary>
        static string StorageDir
        {
            get
            {
                string ws = AppState.Shared != null ? AppState.Shared.WorkspaceFolder : null;
                string key = "global";
                if (ws != null) using (var sha = SHA1.Create()) key = BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(ws.ToLowerInvariant()))).Replace("-", "").Substring(0, 12).ToLowerInvariant();
                return Path.Combine(Defaults.Dir, "api-client", key);
            }
        }

        public void EnsureLoaded()
        {
            string dir = StorageDir;
            if (_loadedFor == dir) return;
            _loadedFor = dir;
            History = Read<List<ApiHistoryEntry>>(Path.Combine(dir, "history.json")) ?? new List<ApiHistoryEntry>();
            Collections = Read<List<ApiCollection>>(Path.Combine(dir, "collections.json")) ?? new List<ApiCollection>();
            Environments = Read<List<ApiEnvironment>>(Path.Combine(dir, "environments.json")) ?? new List<ApiEnvironment>();
            if (Collections.Count == 0) Collections.Add(new ApiCollection { Name = "Default Collection" });
            if (Environments.Count == 0)
                Environments.Add(new ApiEnvironment { Name = "Development", Variables = new List<ApiKV> { new ApiKV { Key = "base_url", Value = "http://localhost:3000" }, new ApiKV { Key = "api_key", Value = "" } } });
            var active = Environments.FirstOrDefault(e => e.IsActive);
            ActiveEnvironmentId = active != null ? active.Id : null;
        }

        static T Read<T>(string path) where T : class
        {
            try { return File.Exists(path) ? Js.Deserialize<T>(File.ReadAllText(path)) : null; }
            catch (Exception ex) { Debug.WriteLine("api-client read " + path + ": " + ex.Message); return null; }
        }

        public void Save()
        {
            try
            {
                string dir = StorageDir;
                Directory.CreateDirectory(dir);
                foreach (var e in Environments) e.IsActive = e.Id == ActiveEnvironmentId;
                Defaults.WriteAtomic(Path.Combine(dir, "history.json"), Js.Serialize(History));
                Defaults.WriteAtomic(Path.Combine(dir, "collections.json"), Js.Serialize(Collections));
                Defaults.WriteAtomic(Path.Combine(dir, "environments.json"), Js.Serialize(Environments));
            }
            catch (Exception ex) { Debug.WriteLine("api-client save: " + ex.Message); }
        }

        public ApiEnvironment ActiveEnvironment { get { return Environments.FirstOrDefault(e => e.Id == ActiveEnvironmentId) ?? Environments.FirstOrDefault(); } }

        public string Resolve(string input)
        {
            var env = ActiveEnvironment;
            if (env == null || input == null) return input;
            string r = input;
            foreach (var v in env.Variables.Where(x => x.IsEnabled && x.Key.Length > 0)) r = r.Replace("{{" + v.Key + "}}", v.Value);
            return r;
        }

        public string BuildUrl(string url, List<ApiKV> query, ApiAuth auth)
        {
            var items = query.Where(p => p.IsEnabled && p.Key.Length > 0).Select(p => Uri.EscapeDataString(p.Key) + "=" + Uri.EscapeDataString(Resolve(p.Value))).ToList();
            if (auth != null && auth.Type == "API Key" && auth.ApiKeyIn == "query")
            {
                string k = Resolve(auth.ApiKeyName);
                if (k.Length > 0) items.Add(Uri.EscapeDataString(k) + "=" + Uri.EscapeDataString(Resolve(auth.ApiKeyValue)));
            }
            if (items.Count == 0) return url;
            return url + (url.Contains("?") ? "&" : "?") + string.Join("&", items);
        }

        /// <summary>HTTPURLResponse.localizedString(forStatusCode:), capitalised as the Mac shows it.</summary>
        static string StatusText(int code, string reason)
        {
            switch (code)
            {
                case 200: return "No Error"; case 201: return "Created"; case 202: return "Accepted"; case 204: return "No Content";
                case 301: return "Moved Permanently"; case 302: return "Found"; case 304: return "Not Modified"; case 307: return "Temporary Redirect"; case 308: return "Permanent Redirect";
                case 400: return "Bad Request"; case 401: return "Unauthorized"; case 403: return "Forbidden"; case 404: return "Not Found"; case 405: return "Method Not Allowed";
                case 409: return "Conflict"; case 413: return "Request Too Large"; case 415: return "Unsupported Media Type"; case 422: return "Unprocessable Entity"; case 429: return "Too Many Requests";
                case 500: return "Internal Server Error"; case 501: return "Unimplemented"; case 502: return "Bad Gateway"; case 503: return "Service Unavailable"; case 504: return "Gateway Timed Out";
                default: return System.Globalization.CultureInfo.InvariantCulture.TextInfo.ToTitleCase((reason ?? "").ToLowerInvariant());
            }
        }

        public async Task<ApiResponse> Execute(ApiRequest req)
        {
            IsLoading = true; Error = null; LastResponse = null; Notify();
            try
            {
                string url = BuildUrl(Resolve(req.Url), req.QueryParams, req.Auth);
                Uri uri;
                if (!Uri.TryCreate(url, UriKind.Absolute, out uri) || (uri.Scheme != "http" && uri.Scheme != "https")) { Error = "Invalid URL: " + url; return null; }
                using (var handler = new HttpClientHandler { AllowAutoRedirect = req.FollowRedirects, AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate, UseCookies = false })
                using (var http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(Math.Max(1, req.Timeout)) })
                {
                    var msg = new HttpRequestMessage(new HttpMethod(req.Method), uri);
                    string contentType = null;
                    foreach (var h in req.Headers)
                    {
                        if (h.Key.Equals("Content-Type", StringComparison.OrdinalIgnoreCase)) { contentType = Resolve(h.Value); continue; }
                        msg.Headers.TryAddWithoutValidation(h.Key, Resolve(h.Value));
                    }
                    switch (req.Auth.Type)
                    {
                        case "Bearer Token": { string tok = Resolve(req.Auth.BearerToken); if (tok.Length > 0) { msg.Headers.Remove("Authorization"); msg.Headers.TryAddWithoutValidation("Authorization", "Bearer " + tok); } break; }
                        case "Basic Auth": msg.Headers.Remove("Authorization"); msg.Headers.TryAddWithoutValidation("Authorization", "Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes(req.Auth.BasicUser + ":" + req.Auth.BasicPassword))); break;
                        case "API Key": { string k = Resolve(req.Auth.ApiKeyName); if (req.Auth.ApiKeyIn == "header" && k.Length > 0) msg.Headers.TryAddWithoutValidation(k, Resolve(req.Auth.ApiKeyValue)); break; }
                    }
                    if (req.Method != "GET" && req.Method != "HEAD" && !string.IsNullOrEmpty(req.Body))
                    {
                        var content = new ByteArrayContent(Encoding.UTF8.GetBytes(Resolve(req.Body)));
                        content.Headers.TryAddWithoutValidation("Content-Type", contentType ?? req.ContentType);
                        msg.Content = content;
                    }
                    var sw = Stopwatch.StartNew();
                    var resp = await http.SendAsync(msg);
                    var bytes = await resp.Content.ReadAsByteArrayAsync();
                    sw.Stop();
                    var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    foreach (var h in resp.Headers) map[h.Key] = string.Join(", ", h.Value);
                    foreach (var h in resp.Content.Headers) map[h.Key] = string.Join(", ", h.Value);
                    string body;
                    try { body = new UTF8Encoding(false, true).GetString(bytes); }
                    catch (DecoderFallbackException) { body = "(binary data: " + bytes.Length + " bytes)"; }
                    var r = new ApiResponse { Status = (int)resp.StatusCode, StatusText = StatusText((int)resp.StatusCode, resp.ReasonPhrase), Headers = map, Body = body, DurationMs = (int)sw.ElapsedMilliseconds, BodySize = bytes.Length };
                    LastResponse = r;
                    GenerateTests(r);
                    History.Insert(0, new ApiHistoryEntry { Request = req, Status = r.Status, Duration = r.DurationMs });
                    if (History.Count > 200) History.RemoveRange(200, History.Count - 200);
                    Save();
                    return r;
                }
            }
            catch (TaskCanceledException) { Error = "The request timed out."; return null; }
            catch (HttpRequestException ex) { Error = (ex.InnerException != null ? ex.InnerException.Message : ex.Message); return null; }
            catch (Exception ex) { Error = ex.Message; return null; }
            finally { IsLoading = false; Notify(); }
        }

        /// <summary>generateAITestSuite: status, latency SLA, body, JSON shape, Content-Type.</summary>
        public List<ApiAssertion> GenerateTests(ApiResponse r)
        {
            var tests = new List<ApiAssertion>
            {
                new ApiAssertion { Name = "Status Code 2xx OK", Passed = r.IsSuccess, Details = "Received HTTP " + r.Status + " (" + r.StatusText + ")" },
                new ApiAssertion { Name = "Latency SLA (< 1500ms)", Passed = r.DurationMs < 1500, Details = "Response finished in " + r.DurationMs + "ms" },
                new ApiAssertion { Name = "Response Body Not Empty", Passed = r.BodySize > 0, Details = "Payload size: " + r.BodySize + " bytes" }
            };
            object json = null;
            try { json = Js.DeserializeObject(r.Body); } catch (Exception) { json = null; }
            var dict = json as Dictionary<string, object>;
            if (dict != null) tests.Add(new ApiAssertion { Name = "Valid JSON Object", Passed = true, Details = "Root keys: [" + string.Join(", ", dict.Keys.OrderBy(k => k, StringComparer.Ordinal).Take(6)) + "]" });
            else if (json is object[] || json is System.Collections.ArrayList) tests.Add(new ApiAssertion { Name = "Valid JSON Array", Passed = true, Details = "Array with " + DJ.AsList(json).Count + " items" });
            else if (r.Headers.Any(h => h.Key.Equals("Content-Type", StringComparison.OrdinalIgnoreCase) && h.Value.Contains("json")))
                tests.Add(new ApiAssertion { Name = "Valid JSON Format", Passed = false, Details = "Content-Type is JSON but body failed parsing" });
            string ct = r.Headers.Where(h => h.Key.Equals("Content-Type", StringComparison.OrdinalIgnoreCase)).Select(h => h.Value).FirstOrDefault();
            tests.Add(new ApiAssertion { Name = "Content-Type Declared", Passed = ct != null, Details = ct ?? "Header missing" });
            Assertions = tests;
            return tests;
        }

        public static string PrettyJson(string s)
        {
            if (string.IsNullOrWhiteSpace(s)) return null;
            string t = s.Trim();
            if (!(t.StartsWith("{") || t.StartsWith("["))) return null;
            try { Js.DeserializeObject(t); } catch (Exception) { return null; }
            var sb = new StringBuilder(); int indent = 0; bool str = false, esc = false;
            foreach (char c in t)
            {
                if (str) { sb.Append(c); if (esc) esc = false; else if (c == '\\') esc = true; else if (c == '"') str = false; continue; }
                switch (c)
                {
                    case '"': str = true; sb.Append(c); break;
                    case '{': case '[': sb.Append(c).Append('\n').Append(new string(' ', (++indent) * 2)); break;
                    case '}': case ']': sb.Append('\n').Append(new string(' ', (--indent) * 2)).Append(c); break;
                    case ',': sb.Append(c).Append('\n').Append(new string(' ', indent * 2)); break;
                    case ':': sb.Append(": "); break;
                    default: if (!char.IsWhiteSpace(c)) sb.Append(c); break;
                }
            }
            return Regex.Replace(sb.ToString(), @"([\[{])\n\s*\n?\s*([\]}])", "$1$2");
        }

        public string ExportCurl(ApiRequest req)
        {
            var parts = new List<string> { "curl", "-X " + req.Method, "'" + BuildUrl(Resolve(req.Url), req.QueryParams, req.Auth) + "'" };
            foreach (var h in req.Headers) parts.Add("-H '" + h.Key + ": " + Resolve(h.Value) + "'");
            switch (req.Auth.Type)
            {
                case "Bearer Token": parts.Add("-H 'Authorization: Bearer " + Resolve(req.Auth.BearerToken) + "'"); break;
                case "Basic Auth": parts.Add("-u '" + req.Auth.BasicUser + ":" + req.Auth.BasicPassword + "'"); break;
                case "API Key": if (req.Auth.ApiKeyIn == "header") parts.Add("-H '" + req.Auth.ApiKeyName + ": " + Resolve(req.Auth.ApiKeyValue) + "'"); break;
            }
            if (!string.IsNullOrEmpty(req.Body) && req.Method != "GET") parts.Add("-d '" + req.Body.Replace("'", "'\\''") + "'");
            return string.Join(" \\\n  ", parts);
        }

        /// <summary>importCURL: -X, -H, -d/--data/--data-raw, -u and the URL (quoted values with spaces are kept together).</summary>
        public ApiRequest ImportCurl(string curl)
        {
            var req = new ApiRequest { Method = "" };
            var parts = new List<string>();
            foreach (Match m in Regex.Matches((curl ?? "").Replace("\\\r\n", " ").Replace("\\\n", " "), "'((?:[^'\\\\]|\\\\.|'\\\\'')*)'|\"((?:[^\"\\\\]|\\\\.)*)\"|(\\S+)"))
                parts.Add(m.Groups[1].Success ? m.Groups[1].Value.Replace("'\\''", "'") : m.Groups[2].Success ? m.Groups[2].Value : m.Groups[3].Value);
            for (int i = 0; i < parts.Count; i++)
            {
                string p = parts[i];
                switch (p)
                {
                    case "-X": case "--request": if (++i < parts.Count) req.Method = parts[i].ToUpperInvariant(); break;
                    case "-H": case "--header":
                        if (++i < parts.Count) { int c = parts[i].IndexOf(':'); if (c > 0) req.Headers[parts[i].Substring(0, c).Trim()] = parts[i].Substring(c + 1).Trim(); }
                        break;
                    case "-d": case "--data": case "--data-raw": case "--data-binary": if (++i < parts.Count) req.Body = parts[i]; break;
                    case "-u": case "--user":
                        if (++i < parts.Count) { var sp = parts[i].Split(new[] { ':' }, 2); req.Auth.Type = "Basic Auth"; req.Auth.BasicUser = sp[0]; req.Auth.BasicPassword = sp.Length > 1 ? sp[1] : ""; }
                        break;
                    default: if (p != "curl" && !p.StartsWith("-") && p.StartsWith("http")) req.Url = p; break;
                }
            }
            if (req.Method.Length == 0) req.Method = req.Body != null ? "POST" : "GET";
            return req.Url.Length == 0 ? null : req;
        }

        public void SaveToCollection(ApiRequest req)
        {
            if (Collections.Count == 0) Collections.Add(new ApiCollection { Name = "Default Collection" });
            Collections[0].Requests.Add(req);
            Save(); Notify();
        }

        public void ClearHistory() { History.Clear(); Save(); Notify(); }

        /// <summary>scanWorkspaceRoutes: FastAPI/Flask, Express/Next.js, Axum, Go routes → a "Scanned Project Routes" collection.</summary>
        public List<ApiRequest> ScanRoutes(string root)
        {
            var found = new List<ApiRequest>();
            if (root == null || !Directory.Exists(root)) { ScanMessage = "Could not read workspace directory"; return found; }
            var ignored = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".git", "node_modules", "target", ".build", "dist", ".next", ".cache", "venv", ".venv", "__pycache__", "Pods", "DerivedData", "bin", "obj" };
            var exts = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".py", ".js", ".ts", ".tsx", ".rs", ".go", ".php" };
            var py = new Regex(@"@(?:app|router|api)\.(get|post|put|delete|patch)\s*\(\s*[""']([^""']+)[""']", RegexOptions.IgnoreCase);
            var js = new Regex(@"(?:app|router)\.(get|post|put|delete|patch)\s*\(\s*[""']([^""']+)[""']", RegexOptions.IgnoreCase);
            var rs = new Regex(@"\.route\s*\(\s*[""']([^""']+)[""']\s*,\s*(get|post|put|delete|patch)\b", RegexOptions.IgnoreCase);
            var go = new Regex(@"\.(GET|POST|PUT|DELETE|PATCH)\s*\(\s*[""']([^""']+)[""']");
            Func<string, string, ApiRequest> mk = (m, path) => new ApiRequest { Name = m + " " + path, Method = m, Url = "{{base_url}}" + path, Headers = new Dictionary<string, string> { { "Content-Type", "application/json" } }, Body = m == "POST" || m == "PUT" || m == "PATCH" ? "{\n  \n}" : null };
            var stack = new Stack<string>(); stack.Push(root);
            int files = 0;
            while (stack.Count > 0 && files < 20000)
            {
                string dir = stack.Pop();
                string[] subs, list;
                try { subs = Directory.GetDirectories(dir); list = Directory.GetFiles(dir); } catch (Exception) { continue; }
                foreach (var s in subs) { string n = Path.GetFileName(s); if (!ignored.Contains(n) && !n.StartsWith(".")) stack.Push(s); }
                foreach (var f in list)
                {
                    string ext = Path.GetExtension(f);
                    if (!exts.Contains(ext)) continue;
                    files++;
                    string name = Path.GetFileName(f), rel = f.Substring(root.Length).Replace('\\', '/');
                    string content;
                    try { if (new FileInfo(f).Length > 500000) continue; content = File.ReadAllText(f); } catch (Exception) { continue; }
                    if ((name == "route.ts" || name == "route.js") && rel.Contains("/app/"))
                    {
                        string route = rel.Substring(rel.IndexOf("/app/", StringComparison.Ordinal) + 5).Replace("/route.ts", "").Replace("/route.js", "");
                        if (!route.StartsWith("/")) route = "/" + route;
                        foreach (var m in new[] { "GET", "POST", "PUT", "DELETE", "PATCH" })
                            if (content.Contains("export async function " + m) || content.Contains("export function " + m)) found.Add(mk(m, route));
                        continue;
                    }
                    if (ext == ".py") foreach (Match m in py.Matches(content)) found.Add(mk(m.Groups[1].Value.ToUpperInvariant(), m.Groups[2].Value));
                    else if (ext == ".js" || ext == ".ts" || ext == ".tsx") foreach (Match m in js.Matches(content)) found.Add(mk(m.Groups[1].Value.ToUpperInvariant(), m.Groups[2].Value));
                    else if (ext == ".rs") foreach (Match m in rs.Matches(content)) found.Add(mk(m.Groups[2].Value.ToUpperInvariant(), m.Groups[1].Value));
                    else if (ext == ".go") foreach (Match m in go.Matches(content)) found.Add(mk(m.Groups[1].Value.ToUpperInvariant(), m.Groups[2].Value));
                }
            }
            var unique = found.GroupBy(r => r.Method + ":" + r.Url).Select(g => g.First()).ToList();
            if (unique.Count > 0)
            {
                string colName = "Scanned Project Routes (" + unique.Count + ")";
                var existing = Collections.FirstOrDefault(c => c.Name.StartsWith("Scanned Project Routes"));
                if (existing != null) { existing.Requests = unique; existing.Name = colName; }
                else Collections.Insert(0, new ApiCollection { Name = colName, Requests = unique });
                Save();
                ScanMessage = "Discovered " + unique.Count + " endpoints from codebase!";
            }
            else ScanMessage = "No API routes detected in project files.";
            return unique;
        }

        /// <summary>loadProjectDotEnv: .env, .env.local, backend/.env, server/.env → the "Project (.env)" environment.</summary>
        public int LoadDotEnv(string root)
        {
            var items = new List<ApiKV>();
            if (root != null)
                foreach (var cand in new[] { ".env", ".env.local", "backend\\.env", "server\\.env" })
                {
                    string p = Path.Combine(root, cand);
                    if (!File.Exists(p)) continue;
                    string[] lines;
                    try { lines = File.ReadAllLines(p); } catch (Exception) { continue; }
                    foreach (var line in lines)
                    {
                        string t = line.Trim();
                        if (t.Length == 0 || t.StartsWith("#")) continue;
                        int eq = t.IndexOf('=');
                        if (eq <= 0) continue;
                        string k = t.Substring(0, eq).Trim(), v = t.Substring(eq + 1).Trim();
                        if ((v.StartsWith("\"") && v.EndsWith("\"") && v.Length >= 2) || (v.StartsWith("'") && v.EndsWith("'") && v.Length >= 2)) v = v.Substring(1, v.Length - 2);
                        if (k.Length > 0 && !items.Any(x => x.Key == k)) items.Add(new ApiKV { Key = k, Value = v });
                    }
                }
            if (!items.Any(x => x.Key == "base_url")) items.Insert(0, new ApiKV { Key = "base_url", Value = "http://localhost:3000" });
            var env = Environments.FirstOrDefault(e => e.Name == "Project (.env)");
            if (env != null) env.Variables = items;
            else { env = new ApiEnvironment { Name = "Project (.env)", Variables = items }; Environments.Insert(0, env); }
            ActiveEnvironmentId = env.Id;
            Save();
            return items.Count;
        }

        public static readonly string[] SnippetLanguages = { "cURL", "Swift (URLSession)", "TypeScript (fetch)", "Python (httpx)", "Rust (reqwest)" };

        public string Snippet(ApiRequest req, string language)
        {
            string url = Resolve(req.Url), m = req.Method;
            bool body = !string.IsNullOrEmpty(req.Body) && m != "GET";
            var sb = new StringBuilder();
            switch (language)
            {
                case "Swift (URLSession)":
                    sb.Append("import Foundation\n\nguard let url = URL(string: \"" + url + "\") else { return }\nvar request = URLRequest(url: url)\nrequest.httpMethod = \"" + m + "\"\n");
                    foreach (var h in req.Headers) sb.Append("request.setValue(\"" + Resolve(h.Value) + "\", forHTTPHeaderField: \"" + h.Key + "\")\n");
                    if (body) sb.Append("request.httpBody = \"" + req.Body.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\".data(using: .utf8)\n");
                    sb.Append("\nlet (data, response) = try await URLSession.shared.data(for: request)\nif let str = String(data: data, encoding: .utf8) {\n    print(\"Response: \\(str)\")\n}\n");
                    return sb.ToString();
                case "TypeScript (fetch)":
                    sb.Append("const response = await fetch(\"" + url + "\", {\n  method: \"" + m + "\",\n  headers: {\n");
                    foreach (var h in req.Headers) sb.Append("    \"" + h.Key + "\": \"" + Resolve(h.Value) + "\",\n");
                    sb.Append("  },\n");
                    if (body) sb.Append("  body: JSON.stringify(" + req.Body.Trim() + "),\n");
                    sb.Append("});\n\nconst data = await response.json();\nconsole.log(data);\n");
                    return sb.ToString();
                case "Python (httpx)":
                    sb.Append("import httpx\n\nurl = \"" + url + "\"\nheaders = {\n");
                    foreach (var h in req.Headers) sb.Append("    \"" + h.Key + "\": \"" + Resolve(h.Value) + "\",\n");
                    sb.Append("}\n");
                    if (body) sb.Append("data = " + req.Body.Trim() + "\n\nwith httpx.Client() as client:\n    response = client.request(\"" + m + "\", url, headers=headers, json=data)\n");
                    else sb.Append("\nwith httpx.Client() as client:\n    response = client.request(\"" + m + "\", url, headers=headers)\n");
                    sb.Append("    print(response.status_code, response.text)\n");
                    return sb.ToString();
                case "Rust (reqwest)":
                    sb.Append("use reqwest::Client;\n\nlet client = Client::new();\nlet response = client\n    ." + m.ToLowerInvariant() + "(\"" + url + "\")\n");
                    foreach (var h in req.Headers) sb.Append("    .header(\"" + h.Key + "\", \"" + Resolve(h.Value) + "\")\n");
                    if (body) sb.Append("    .body(\"" + req.Body.Replace("\"", "\\\"") + "\")\n");
                    sb.Append("    .send()\n    .await?;\n\nlet body = response.text().await?;\nprintln!(\"{}\", body);\n");
                    return sb.ToString();
                default: return ExportCurl(req);
            }
        }
    }

    /// <summary>APIClientView.</summary>
    public class ApiStudioView : Grid
    {
        readonly AppState _app;
        readonly ApiService _svc = ApiService.Shared;
        string _method = "POST", _url = "https://api.dotmini.net/v1/chat/completions", _name = "New Request", _search = "", _toast;
        string _body = "{\n  \"model\": \"gemini-2.5-flash\",\n  \"messages\": [\n    {\n      \"role\": \"user\",\n      \"content\": \"Hello\"\n    }\n  ]\n}";
        List<ApiKV> _headers = new List<ApiKV> { new ApiKV { Key = "Content-Type", Value = "application/json" }, new ApiKV { Key = "Authorization", Value = "Bearer " } };
        List<ApiKV> _query = new List<ApiKV>();
        ApiAuth _auth = new ApiAuth();
        int _reqTab, _respTab, _sideTab;
        readonly Border _header = new Border(), _sidebar = new Border(), _reqBar = new Border(), _reqPanel = new Border(), _respPanel = new Border();
        static readonly string[] Methods = { "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS" };
        public static string InitialUrl, InitialMethod;
        public static bool AutoSend;

        static Brush MethodColor(string m)
        {
            switch (m)
            {
                case "GET": return Theme.B(Theme.Rgb(71, 133, 217)); case "POST": return Theme.B(Theme.Rgb(56, 148, 112)); case "PUT": return Theme.B(Theme.Rgb(209, 140, 46));
                case "DELETE": return Theme.B(Theme.Rgb(209, 82, 82)); case "PATCH": return Theme.B(Theme.Rgb(140, 107, 199)); case "HEAD": return Theme.B(Theme.Rgb(89, 140, 166));
                default: return Theme.B(Theme.Rgb(140, 148, 158));
            }
        }
        static Brush StatusColor(int code)
        {
            if (code >= 200 && code < 300) return Theme.B(Theme.Rgb(56, 153, 112));
            if (code >= 300 && code < 400) return Theme.B(Theme.Rgb(71, 133, 217));
            if (code >= 400 && code < 500) return Theme.B(Theme.Rgb(217, 140, 51));
            return Theme.B(Theme.Rgb(209, 82, 82));
        }

        public ApiStudioView(AppState app)
        {
            _app = app;
            _svc.EnsureLoaded();
            var t = Theme.Current;
            Background = t.EditorBackground;
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1) });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            Children.Add(_header);
            var d1 = V.Line(t.Separator, true); SetRow(d1, 1); Children.Add(d1);
            var body = new Grid();
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(260), MinWidth = 240, MaxWidth = 320 });
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            body.Children.Add(_sidebar);
            var split1 = new GridSplitter { Width = 1, Background = t.Separator, HorizontalAlignment = HorizontalAlignment.Stretch, ResizeBehavior = GridResizeBehavior.PreviousAndNext };
            Grid.SetColumn(split1, 1); body.Children.Add(split1);
            var main = new Grid();
            main.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            main.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1) });
            main.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            main.Children.Add(_reqBar);
            var d2 = V.Line(t.Separator, true); SetRow(d2, 1); main.Children.Add(d2);
            var panels = new Grid();
            panels.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = 220 });
            panels.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            panels.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = 220 });
            panels.Children.Add(_reqPanel);
            var split2 = new GridSplitter { Width = 1, Background = t.Separator, HorizontalAlignment = HorizontalAlignment.Stretch, ResizeBehavior = GridResizeBehavior.PreviousAndNext };
            Grid.SetColumn(split2, 1); panels.Children.Add(split2);
            Grid.SetColumn(_respPanel, 2); panels.Children.Add(_respPanel);
            SetRow(panels, 2); main.Children.Add(panels);
            Grid.SetColumn(main, 2); body.Children.Add(main);
            SetRow(body, 2); Children.Add(body);
            if (InitialUrl != null) { _url = InitialUrl; _method = InitialMethod ?? "GET"; InitialUrl = null; }
            if (AutoSend) { AutoSend = false; Loaded += delegate { Dispatcher.BeginInvoke(new Action(Send), System.Windows.Threading.DispatcherPriority.ApplicationIdle); }; }
            _svc.Changed += OnServiceChanged;
            Unloaded += delegate { _svc.Changed -= OnServiceChanged; };
            Loaded += delegate { _svc.Changed -= OnServiceChanged; _svc.Changed += OnServiceChanged; };
            RenderAll();
        }

        void OnServiceChanged() { RenderHeader(); RenderSidebar(); RenderReqBar(); RenderResponse(); }
        void RenderAll() { RenderHeader(); RenderSidebar(); RenderReqBar(); RenderRequest(); RenderResponse(); }

        Btn Chip(UIElement content, Action a, string tip)
        {
            var t = Theme.Current;
            var b = V.Button(V.Box(content, V.P(9, 5), t.P(0.06), 6), a);
            if (tip != null) b.ToolTip = tip;
            return b;
        }

        void Toast(string msg)
        {
            _toast = msg; RenderHeader();
            var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
            timer.Tick += delegate { timer.Stop(); if (_toast == msg) { _toast = null; RenderHeader(); } };
            timer.Start();
        }

        // ── header bar ───────────────────────────────────────────────────────
        void RenderHeader()
        {
            var t = Theme.Current;
            var row = V.H(12, V.H(8, Sym.Icon("network", 14, t.Accent, FontWeights.SemiBold), V.T("API Studio", 13, FontWeights.Bold, t.Primary), V.Box(V.T("100% Native", 9, FontWeights.SemiBold, t.Accent), V.P(6, 2), t.A(0.12), 4)));
            string msg = _svc.ScanMessage ?? _toast;
            if (msg != null) row.Children.Add(V.Shrink(V.T(msg, 11, FontWeights.Normal, t.Secondary)));
            row.Children.Add(V.Sp());
            UIElement scanIcon = _svc.IsScanning ? (UIElement)new ThreeDots() : Sym.Icon("sparkles", 11, t.Primary);
            row.Children.Add(Chip(V.H(5, scanIcon, V.T("Scan Routes", 11, FontWeights.Medium, t.Primary)), ScanRoutes, "Scan FastAPI, Next.js, Express, Axum, Go routes in workspace"));
            row.Children.Add(Chip(V.H(5, Sym.Icon("key.fill", 10, t.Primary), V.T("Load .env", 11, FontWeights.Medium, t.Primary)), () =>
            {
                int n = _svc.LoadDotEnv(_app.WorkspaceFolder);
                Toast("Loaded " + n + " variables from .env");
                _sideTab = 2; RenderSidebar();
            }, "Load environment variables from project .env"));
            row.Children.Add(Chip(V.H(5, Sym.Icon("curlybraces", 11, t.Primary), V.T("Code Snippet", 11, FontWeights.Medium, t.Primary)), ShowSnippet, "Generate modern Swift, TypeScript, Python, Rust or cURL code"));
            row.Children.Add(V.Size(V.Line(t.Separator, false), 1, 14));
            row.Children.Add(Chip(V.H(4, Sym.Icon("chevron.left", 10, t.Primary, FontWeights.SemiBold), V.T("Exit to Code", 11, FontWeights.Medium, t.Primary)), () => _app.SwitchToMode(EditorMode.Code), "Return to Code Editor"));
            _header.Child = new Border { Child = row, Padding = new Thickness(14, 8, 14, 8), Background = t.PanelBackground };
        }

        void ScanRoutes()
        {
            _svc.IsScanning = true; _svc.ScanMessage = "Scanning project files for API endpoints..."; RenderHeader();
            string root = _app.WorkspaceFolder;
            Task.Run(() => _svc.ScanRoutes(root)).ContinueWith(tk => Dispatcher.BeginInvoke(new Action(() => { _svc.IsScanning = false; _sideTab = 1; RenderHeader(); RenderSidebar(); })));
        }

        // ── sidebar: history / collections / environments ────────────────────
        void RenderSidebar()
        {
            var t = Theme.Current;
            var seg = V.H(0);
            string[] icons = { "clock", "folder", "gearshape.2" };
            string[] tips = { "History", "Collections", "Environments" };
            for (int i = 0; i < 3; i++)
            {
                int idx = i; bool sel = _sideTab == i;
                var b = V.Button(V.Box(Sym.Icon(icons[i], 11, sel ? t.Primary : t.Secondary), V.P(0, 3), sel ? t.P(0.14) : Brushes.Transparent, 5), () => { _sideTab = idx; RenderSidebar(); });
                b.ToolTip = tips[i];
                seg.Children.Add(V.Flex(b));
            }
            var segBox = V.Box(seg, V.P(2), t.P(0.06), 6); segBox.Margin = new Thickness(10);
            TextBox search;
            var field = Styles.Field("Search history...", 11, t.Primary, t.Secondary, out search);
            search.Text = _search;
            search.TextChanged += delegate { _search = search.Text; RenderList(); };
            var searchBox = V.Box(V.H(6, Sym.Icon("magnifyingglass", 11, t.Secondary), V.Flex(field)), V.P(10, 6), t.P(0.04), 6); searchBox.Margin = new Thickness(10, 0, 10, 6);
            _listHost = new Border();
            var col = new DockPanel { Background = t.PanelBackground };
            DockPanel.SetDock(segBox, Dock.Top); col.Children.Add(segBox);
            DockPanel.SetDock(searchBox, Dock.Top); col.Children.Add(searchBox);
            var line = V.Line(t.Separator, true); DockPanel.SetDock(line, Dock.Top); col.Children.Add(line);
            col.Children.Add(_listHost);
            _sidebar.Child = col;
            RenderList();
        }

        Border _listHost;
        void RenderList()
        {
            if (_listHost == null) return;
            var t = Theme.Current;
            var list = V.VLead(2); list.Align = Cross.Stretch;
            if (_sideTab == 0)
            {
                var entries = _svc.History.Where(e => _search.Length == 0 || (e.Request.Url ?? "").IndexOf(_search, StringComparison.OrdinalIgnoreCase) >= 0).ToList();
                if (entries.Count == 0) list.Children.Add(V.Self(V.Box(V.T("No history yet", 11, FontWeights.Normal, t.Secondary), V.P(0, 24, 0, 0), null, 0), Cross.Center));
                foreach (var e in entries)
                {
                    var entry = e;
                    var m = V.Mono(e.Request.Method, 9, FontWeights.Bold, MethodColor(e.Request.Method)); m.Width = 38;
                    var info = V.VLead(2, V.T(ShortUrl(e.Request.Url), 11, FontWeights.Normal, t.Primary), V.H(4, V.Dot(6, StatusColor(e.Status)), V.T(e.Duration + "ms", 9, FontWeights.Normal, t.Secondary)));
                    var b = V.Button(V.Box(V.H(8, m, V.Flex(info)), V.P(10, 6), Brushes.Transparent, 0), () => LoadRequest(entry.Request, false));
                    b.OnState = x => ((Border)x.Child).Background = x.IsHover ? t.P(0.05) : Brushes.Transparent;
                    list.Children.Add(b);
                }
                var col = new DockPanel();
                if (_svc.History.Count > 0)
                {
                    var clear = V.Button(V.Box(V.T("Clear History", 10, FontWeights.Medium, t.Secondary), V.P(10, 4), t.P(0.06), 5), () => _svc.ClearHistory());
                    var foot = V.Box(V.H(0, V.Sp(), clear, V.Sp()), V.P(8), null, 0, t.Separator, 0); foot.BorderThickness = new Thickness(0, 1, 0, 0);
                    DockPanel.SetDock(foot, Dock.Bottom); col.Children.Add(foot);
                }
                col.Children.Add(new ScrollViewer { Content = V.Box(list, V.P(0, 4), null, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
                _listHost.Child = col;
                return;
            }
            if (_sideTab == 1)
            {
                foreach (var c in _svc.Collections)
                {
                    var colItem = c;
                    var kids = V.VLead(0); kids.Align = Cross.Stretch; kids.Visibility = Visibility.Visible;
                    foreach (var r in c.Requests.Where(r => _search.Length == 0 || r.Name.IndexOf(_search, StringComparison.OrdinalIgnoreCase) >= 0 || (r.Url ?? "").IndexOf(_search, StringComparison.OrdinalIgnoreCase) >= 0))
                    {
                        var req = r;
                        var b = V.Button(V.Box(V.H(6, V.Mono(r.Method, 9, FontWeights.Bold, MethodColor(r.Method)), V.Shrink(V.T(r.Name, 11, FontWeights.Normal, t.Primary))), V.P(22, 4, 8, 4), Brushes.Transparent, 0), () => LoadRequest(req, true));
                        b.OnState = x => ((Border)x.Child).Background = x.IsHover ? t.P(0.05) : Brushes.Transparent;
                        kids.Children.Add(b);
                    }
                    var chev = Sym.Icon("chevron.down", 9, t.Secondary, FontWeights.SemiBold);
                    var head = V.Button(V.Box(V.H(6, chev, V.Shrink(V.T(c.Name, 11, FontWeights.Medium, t.Primary)), V.Sp(), V.T(c.Requests.Count.ToString(), 10, FontWeights.Normal, t.Secondary)), V.P(8, 5), Brushes.Transparent, 0), null);
                    head.Click += delegate { bool open = kids.Visibility != Visibility.Visible; kids.Visibility = open ? Visibility.Visible : Visibility.Collapsed; if (chev.Glyph != null) chev.Glyph.Text = Sym.GlyphText(open ? "chevron.down" : "chevron.right"); };
                    list.Children.Add(head); list.Children.Add(kids);
                }
                list.Children.Add(V.Button(V.Box(V.H(6, Sym.Icon("plus", 11, t.Primary), V.T("New Collection", 11, FontWeights.Normal, t.Primary)), V.P(10, 6), Brushes.Transparent, 0), () =>
                {
                    string n = Prompt.Ask("New Collection", "Name:", "New Collection");
                    if (string.IsNullOrWhiteSpace(n)) return;
                    _svc.Collections.Add(new ApiCollection { Name = n.Trim() }); _svc.Save(); RenderList();
                }));
                _listHost.Child = new ScrollViewer { Content = V.Box(list, V.P(8), null, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
                return;
            }
            foreach (var e in _svc.Environments)
            {
                var env = e;
                bool active = _svc.ActiveEnvironment == e;
                var vars = V.VLead(3); vars.Align = Cross.Stretch;
                foreach (var v in e.Variables) vars.Children.Add(KvRow(v, () => e.Variables.Remove(v), () => _svc.Save(), 10));
                vars.Children.Add(V.Button(V.Box(V.H(5, Sym.Icon("plus", 10, t.Primary), V.T("Add Variable", 10, FontWeights.Normal, t.Primary)), V.P(4, 4), Brushes.Transparent, 0), () => { env.Variables.Add(new ApiKV()); _svc.Save(); RenderList(); }));
                var head = V.Button(V.Box(V.H(6, V.Shrink(V.T(e.Name, 11, FontWeights.Medium, t.Primary)), V.Sp(), active ? (UIElement)Sym.Icon("checkmark.circle.fill", 10, Theme.B(Theme.Rgb(56, 153, 112))) : new Border()), V.P(8, 5), Brushes.Transparent, 0), () => { _svc.ActiveEnvironmentId = env.Id; _svc.Save(); RenderList(); });
                head.ToolTip = "Use this environment for {{variables}}";
                list.Children.Add(head);
                list.Children.Add(V.Box(vars, V.P(8, 0, 8, 6), null, 0));
            }
            list.Children.Add(V.Button(V.Box(V.H(6, Sym.Icon("plus", 11, t.Primary), V.T("New Environment", 11, FontWeights.Normal, t.Primary)), V.P(10, 6), Brushes.Transparent, 0), () => { _svc.Environments.Add(new ApiEnvironment { Name = "New Env" }); _svc.Save(); RenderList(); }));
            _listHost.Child = new ScrollViewer { Content = V.Box(list, V.P(8), null, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        }

        static string ShortUrl(string u) { return (u ?? "").Replace("https://", "").Replace("http://", ""); }

        UIElement KvRow(ApiKV item, Action remove, Action changed, double size)
        {
            var t = Theme.Current;
            var check = new CheckBox { IsChecked = item.IsEnabled, VerticalAlignment = VerticalAlignment.Center };
            check.Checked += delegate { item.IsEnabled = true; changed(); };
            check.Unchecked += delegate { item.IsEnabled = false; changed(); };
            Func<string, string, Action<string>, UIElement> field = (ph, val, set) =>
            {
                TextBox tb;
                var g = Styles.Field(ph, size + 1, t.Primary, t.Secondary, out tb);
                tb.FontFamily = UIFonts.Mono; tb.Text = val;
                tb.TextChanged += delegate { set(tb.Text); changed(); };
                return V.Box(g, V.P(6, 3), t.TextBackground, 5, t.P(0.15), 1);
            };
            var row = new Grid();
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.Children.Add(check);
            var k = field("Key", item.Key, s => item.Key = s); Grid.SetColumn(k, 1); ((FrameworkElement)k).Margin = new Thickness(4, 0, 4, 0); row.Children.Add(k);
            var v = field("Value", item.Value, s => item.Value = s); Grid.SetColumn(v, 2); row.Children.Add(v);
            var x = V.Button(Sym.Icon("xmark.circle", 10, t.Secondary), () => { remove(); changed(); RenderRequest(); RenderList(); });
            x.Margin = new Thickness(6, 0, 0, 0); Grid.SetColumn(x, 3); row.Children.Add(x);
            return row;
        }

        // ── request bar ──────────────────────────────────────────────────────
        TextBox _urlBox;
        void RenderReqBar()
        {
            var t = Theme.Current;
            var method = V.Button(V.Size(V.Box(V.H(4, V.Mono(_method, 11, FontWeights.Bold, MethodColor(_method)), V.Sp(), Sym.Icon("chevron.up.chevron.down", 8, t.Secondary)), V.P(8, 0), t.P(0.06), 6), 90, 28), null);
            method.MenuItems = () => Methods.Select(m => { var mm = m; return new MenuItemSpec { Title = m, Checked = m == _method, Action = () => { _method = mm; RenderReqBar(); } }; }).ToList();
            var field = Styles.Field("Enter URL or paste cURL", 12, t.Primary, t.Secondary, out _urlBox);
            _urlBox.FontFamily = UIFonts.Mono; _urlBox.Text = _url;
            _urlBox.TextChanged += delegate
            {
                string v = _urlBox.Text;
                if (v.TrimStart().StartsWith("curl ", StringComparison.OrdinalIgnoreCase))
                {
                    var imported = _svc.ImportCurl(v);
                    if (imported != null) { Dispatcher.BeginInvoke(new Action(() => { LoadRequest(imported, false); Toast("Imported cURL"); })); return; }
                }
                _url = v;
            };
            _urlBox.KeyDown += (s, e) => { if (e.Key == Key.Enter) { Send(); e.Handled = true; } };
            var urlBox = V.Box(field, V.P(10, 6), t.P(0.04), 6, t.S(0.2), 1);
            UIElement sendIcon = _svc.IsLoading ? (UIElement)new ThreeDots() : Sym.Icon("paperplane.fill", 10, Brushes.White);
            var send = V.Button(V.Box(V.H(6, sendIcon, V.T("Send", 12, FontWeights.SemiBold, Brushes.White)), V.P(16, 6), t.Accent, 6), Send);
            send.IsEnabled = !_svc.IsLoading;
            var more = V.Button(V.Box(Sym.Icon("square.and.arrow.down", 11, t.Secondary), V.P(6), t.P(0.04), 6), null);
            more.MenuItems = () => new List<MenuItemSpec>
            {
                MenuItemSpec.Item("Save to Collection", null, () => { _svc.SaveToCollection(Build()); Toast("Saved to " + _svc.Collections[0].Name); }),
                MenuItemSpec.Item("Export cURL", null, () => CurlSheet(_svc.ExportCurl(Build()))),
                MenuItemSpec.Item("Import cURL", null, () => CurlSheet(""))
            };
            var row = V.H(8, method, V.Flex(urlBox), send, more);
            _reqBar.Child = new Border { Child = row, Padding = new Thickness(12, 8, 12, 8), Background = Theme.Current.PanelBackground };
        }

        // ── request panel ────────────────────────────────────────────────────
        Btn TabBtn(string title, bool sel, double alpha, Action a)
        {
            var t = Theme.Current;
            return V.Button(V.Box(V.T(title, 11, sel ? FontWeights.SemiBold : FontWeights.Normal, sel ? t.Accent : t.Secondary), V.P(10, 4), sel ? t.A(alpha) : Brushes.Transparent, 5), a);
        }

        void RenderRequest()
        {
            var t = Theme.Current;
            var tabs = V.H(4);
            string[] names = { "Body", "Headers", "Params", "Auth" };
            for (int i = 0; i < 4; i++) { int idx = i; tabs.Children.Add(TabBtn(names[i], _reqTab == i, 0.18, () => { _reqTab = idx; RenderRequest(); })); }
            UIElement body;
            if (_reqTab == 0)
            {
                string ct = _headers.Where(h => h.Key == "Content-Type").Select(h => h.Value).FirstOrDefault() ?? "application/json";
                string label = ct == "application/xml" ? "XML" : ct == "text/plain" ? "Text" : ct == "application/x-www-form-urlencoded" ? "Form" : "JSON";
                var picker = V.Button(V.Size(V.Box(V.H(4, V.T(label, 11, FontWeights.Medium, t.Primary), V.Sp(), Sym.Icon("chevron.up.chevron.down", 8, t.Secondary)), V.P(8, 0), t.P(0.06), 5), 100, 24), null);
                picker.MenuItems = () => new[] { "JSON|application/json", "XML|application/xml", "Text|text/plain", "Form|application/x-www-form-urlencoded" }.Select(s =>
                {
                    var p = s.Split('|');
                    return new MenuItemSpec { Title = p[0], Checked = p[1] == ct, Action = () => { var h = _headers.FirstOrDefault(x => x.Key == "Content-Type"); if (h != null) h.Value = p[1]; else _headers.Add(new ApiKV { Key = "Content-Type", Value = p[1] }); RenderRequest(); } };
                }).ToList();
                picker.Margin = new Thickness(6);
                var tb = new TextBox
                {
                    Text = _body, AcceptsReturn = true, AcceptsTab = true, FontFamily = UIFonts.Mono, FontSize = 11, Foreground = t.EditorText, Background = Brushes.Transparent, BorderThickness = new Thickness(0),
                    CaretBrush = t.Primary, Padding = new Thickness(6), VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, TextWrapping = TextWrapping.NoWrap
                };
                tb.TextChanged += delegate
                {
                    string fixedText = tb.Text.Replace('\u201C', '"').Replace('\u201D', '"').Replace('\u2018', '\'').Replace('\u2019', '\'');
                    if (fixedText != tb.Text) { int c = tb.CaretIndex; tb.Text = fixedText; tb.CaretIndex = c; return; }
                    _body = tb.Text;
                };
                var dock = new DockPanel();
                DockPanel.SetDock(picker, Dock.Top); picker.HorizontalAlignment = HorizontalAlignment.Left; dock.Children.Add(picker);
                dock.Children.Add(new Border { Child = tb, Background = t.EditorBackground });
                body = dock;
            }
            else if (_reqTab == 1 || _reqTab == 2)
            {
                var items = _reqTab == 1 ? _headers : _query;
                var list = V.VLead(4); list.Align = Cross.Stretch;
                foreach (var it in items) { var item = it; list.Children.Add(V.Box(KvRow(item, () => items.Remove(item), () => { }, 10), V.P(8, 0), null, 0)); }
                var add = V.Button(V.H(5, Sym.Icon("plus", 11, t.Primary), V.T(_reqTab == 1 ? "Add Header" : "Add Param", 11, FontWeights.Normal, t.Primary)), () => { items.Add(new ApiKV()); RenderRequest(); });
                var foot = V.Box(V.H(0, add, V.Sp()), V.P(8), null, 0, t.Separator, 0); foot.BorderThickness = new Thickness(0, 1, 0, 0);
                var dock = new DockPanel();
                DockPanel.SetDock(foot, Dock.Bottom); dock.Children.Add(foot);
                dock.Children.Add(new ScrollViewer { Content = V.Box(list, V.P(0, 6), null, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
                body = dock;
            }
            else body = AuthEditor();
            var col = new DockPanel();
            var tabBar = V.Box(V.H(0, tabs, V.Sp()), V.P(8, 6), t.Op(t.PanelBackground, 0.5), 0, t.Separator, 0); tabBar.BorderThickness = new Thickness(0, 0, 0, 1);
            DockPanel.SetDock(tabBar, Dock.Top); col.Children.Add(tabBar);
            col.Children.Add(body);
            _reqPanel.Child = col;
        }

        UIElement AuthEditor()
        {
            var t = Theme.Current;
            var col = V.VLead(12); col.Align = Cross.Start;
            var type = V.Button(V.Size(V.Box(V.H(6, V.T("Type", 11, FontWeights.Normal, t.Secondary), V.T(_auth.Type, 11, FontWeights.Medium, t.Primary), V.Sp(), Sym.Icon("chevron.up.chevron.down", 8, t.Secondary)), V.P(8, 0), t.P(0.06), 5), 220, 24), null);
            type.MenuItems = () => new[] { "None", "Bearer Token", "Basic Auth", "API Key" }.Select(s => { var v = s; return new MenuItemSpec { Title = s, Checked = s == _auth.Type, Action = () => { _auth.Type = v; RenderRequest(); } }; }).ToList();
            col.Children.Add(type);
            Func<string, string, string, Action<string>, bool, UIElement> row = (label, ph, val, set, secret) =>
            {
                UIElement input;
                if (secret)
                {
                    var pb = new PasswordBox { Password = val, FontSize = 11, Width = 260, BorderThickness = new Thickness(1), BorderBrush = t.P(0.15), Background = t.TextBackground, Foreground = t.Primary, Padding = new Thickness(4, 2, 4, 2) };
                    pb.PasswordChanged += delegate { set(pb.Password); };
                    input = pb;
                }
                else
                {
                    TextBox tb;
                    var g = Styles.Field(ph, 11, t.Primary, t.Secondary, out tb);
                    tb.Text = val; tb.TextChanged += delegate { set(tb.Text); };
                    var box = V.Box(g, V.P(6, 3), t.TextBackground, 5, t.P(0.15), 1); box.Width = 260;
                    input = box;
                }
                var l = V.T(label, 11, FontWeights.Normal, t.Primary); l.Width = 50;
                return V.H(6, l, input);
            };
            switch (_auth.Type)
            {
                case "Bearer Token": col.Children.Add(row("Token", "Bearer token", _auth.BearerToken, s => _auth.BearerToken = s, false)); break;
                case "Basic Auth": col.Children.Add(row("User", "Username", _auth.BasicUser, s => _auth.BasicUser = s, false)); col.Children.Add(row("Pass", "Password", _auth.BasicPassword, s => _auth.BasicPassword = s, true)); break;
                case "API Key":
                    col.Children.Add(row("Key", "Header name", _auth.ApiKeyName, s => _auth.ApiKeyName = s, false));
                    col.Children.Add(row("Value", "API key value", _auth.ApiKeyValue, s => _auth.ApiKeyValue = s, false));
                    var where = V.Button(V.Size(V.Box(V.H(6, V.T("In", 11, FontWeights.Normal, t.Secondary), V.T(_auth.ApiKeyIn == "query" ? "Query" : "Header", 11, FontWeights.Medium, t.Primary), V.Sp(), Sym.Icon("chevron.up.chevron.down", 8, t.Secondary)), V.P(8, 0), t.P(0.06), 5), 180, 24), null);
                    where.MenuItems = () => new List<MenuItemSpec> { new MenuItemSpec { Title = "Header", Checked = _auth.ApiKeyIn != "query", Action = () => { _auth.ApiKeyIn = "header"; RenderRequest(); } }, new MenuItemSpec { Title = "Query", Checked = _auth.ApiKeyIn == "query", Action = () => { _auth.ApiKeyIn = "query"; RenderRequest(); } } };
                    col.Children.Add(where);
                    break;
                default: col.Children.Add(V.T("No authentication required", 11, FontWeights.Normal, t.Secondary)); break;
            }
            return V.Box(col, V.P(12), null, 0);
        }

        // ── response panel ───────────────────────────────────────────────────
        void RenderResponse()
        {
            var t = Theme.Current;
            var r = _svc.LastResponse;
            var status = V.H(10, V.T("Response", 11, FontWeights.Bold, t.Primary), V.Sp());
            if (_svc.IsLoading) status.Children.Add(new ThreeDots());
            if (r != null)
            {
                status.Children.Add(V.Dot(8, StatusColor(r.Status)));
                status.Children.Add(V.T(r.Status + " " + r.StatusText, 11, FontWeights.SemiBold, StatusColor(r.Status)));
                status.Children.Add(V.Mono(r.DurationMs + "ms", 10, FontWeights.Normal, t.Secondary));
                status.Children.Add(V.T(r.BodySize < 1024 ? r.BodySize + " B" : r.BodySize < 1048576 ? (r.BodySize / 1024) + " KB" : (r.BodySize / 1048576) + " MB", 10, FontWeights.Normal, t.Secondary));
                var copy = V.Button(Sym.Icon("doc.on.doc", 10, t.Secondary), () => { try { Clipboard.SetText(r.Body); } catch (Exception ex) { Debug.WriteLine("copy body: " + ex.Message); } });
                copy.ToolTip = "Copy Body";
                status.Children.Add(copy);
            }
            var tabs = V.H(4);
            string[] names = { "Body", "Headers", "Raw", "AI Tests (" + _svc.Assertions.Count + ")" };
            for (int i = 0; i < 4; i++) { int idx = i; tabs.Children.Add(TabBtn(names[i], _respTab == i, 0.14, () => { _respTab = idx; RenderResponse(); })); }
            UIElement body;
            Func<string, UIElement> text = s => new TextBox { Text = s, IsReadOnly = true, FontFamily = UIFonts.Mono, FontSize = 11, Foreground = t.EditorText, Background = t.EditorBackground, BorderThickness = new Thickness(0), Padding = new Thickness(10), TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, CaretBrush = Brushes.Transparent };
            if (r != null)
            {
                if (_respTab == 0) body = text(r.FormattedBody);
                else if (_respTab == 2) body = text(r.Body);
                else if (_respTab == 1)
                {
                    var list = V.VLead(2); list.Align = Cross.Stretch;
                    foreach (var h in r.Headers.OrderBy(h => h.Key, StringComparer.Ordinal))
                    {
                        var v = V.Mono(h.Value, 10, FontWeights.Normal, t.Secondary); v.TextAlignment = TextAlignment.Right; v.TextWrapping = TextWrapping.Wrap; v.MaxHeight = 30;
                        var row = new Grid(); row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                        row.Children.Add(V.Mono(h.Key, 10, FontWeights.Medium, t.Accent)); Grid.SetColumn(v, 1); v.Margin = new Thickness(12, 0, 0, 0); row.Children.Add(v);
                        list.Children.Add(V.Box(row, V.P(8, 3), null, 0));
                    }
                    body = new ScrollViewer { Content = V.Box(list, V.P(6), null, 0), Background = t.EditorBackground, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
                }
                else body = TestsView(r);
            }
            else if (_svc.Error != null)
            {
                var red = Theme.B(Theme.Rgb(209, 82, 82));
                body = V.Vs(8, V.Sp(), Sym.Icon("exclamationmark.triangle", 24, red), V.Wrap(V.T(_svc.Error, 11, FontWeights.Normal, red), TextAlignment.Center), V.Sp());
            }
            else if (_respTab == 3)
                body = V.Vs(8, V.Sp(), Sym.Icon("sparkles", 28, t.A(0.4)), V.T("No tests executed yet", 12, FontWeights.SemiBold, t.Primary), V.T("Send any request to auto-verify status, SLA latency, schema & headers", 11, FontWeights.Normal, t.Secondary), V.Sp());
            else body = V.Vs(8, V.Sp(), Sym.Icon("arrow.up.message", 28, t.S(0.3)), V.T("Send a request to see the response", 11, FontWeights.Normal, t.Secondary), V.Sp());
            var col = new DockPanel();
            var top = V.Box(status, V.P(10, 6), t.Op(t.PanelBackground, 0.7), 0); DockPanel.SetDock(top, Dock.Top); col.Children.Add(top);
            var tabBar = V.Box(V.H(0, tabs, V.Sp()), V.P(8, 4), t.Op(t.PanelBackground, 0.3), 0, t.Separator, 0); tabBar.BorderThickness = new Thickness(0, 0, 0, 1);
            DockPanel.SetDock(tabBar, Dock.Top); col.Children.Add(tabBar);
            col.Children.Add(body);
            _respPanel.Child = col;
        }

        UIElement TestsView(ApiResponse r)
        {
            var t = Theme.Current;
            var green = Theme.B(Theme.Rgb(56, 153, 112)); var red = Theme.B(Theme.Rgb(209, 82, 82)); var amber = Theme.B(Theme.Rgb(217, 140, 51));
            int pass = _svc.Assertions.Count(a => a.Passed), total = _svc.Assertions.Count;
            var head = V.H(6, Sym.Icon(pass == total ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", 12, pass == total ? green : amber), V.T("AI Contract & SLA Verification: " + pass + "/" + total + " Passed", 12, FontWeights.Bold, t.Primary), V.Sp(),
                V.Button(V.Box(V.H(4, Sym.Icon("arrow.clockwise", 10, t.Primary), V.T("Re-run Tests", 10, FontWeights.Medium, t.Primary)), V.P(8, 4), t.P(0.06), 5), () => { _svc.GenerateTests(r); RenderResponse(); }));
            var list = V.VLead(8); list.Align = Cross.Stretch;
            foreach (var a in _svc.Assertions)
            {
                var row = V.H(10, Sym.Icon(a.Passed ? "checkmark.circle.fill" : "xmark.circle.fill", 13, a.Passed ? green : red),
                    V.Flex(V.VLead(3, V.T(a.Name, 11, FontWeights.SemiBold, t.Primary), V.Wrap(V.Mono(a.Details, 10, FontWeights.Normal, t.Secondary), TextAlignment.Left))),
                    V.Box(V.Mono(a.Passed ? "PASS" : "FAIL", 9, FontWeights.Bold, a.Passed ? green : red), V.P(6, 2), NbColor.Alpha((SolidColorBrush)(a.Passed ? green : red), 0.15), 4));
                row.Align = Cross.Start;
                list.Children.Add(V.Box(row, V.P(10), t.P(0.03), 6));
            }
            var col = new DockPanel { Background = t.EditorBackground };
            var top = V.Box(head, V.P(12, 10, 12, 10), null, 0, t.Separator, 0); top.BorderThickness = new Thickness(0, 0, 0, 1);
            DockPanel.SetDock(top, Dock.Top); col.Children.Add(top);
            col.Children.Add(new ScrollViewer { Content = V.Box(list, V.P(12, 6), null, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
            return col;
        }

        // ── actions ──────────────────────────────────────────────────────────
        ApiRequest Build()
        {
            var headers = new Dictionary<string, string>();
            foreach (var h in _headers.Where(h => h.IsEnabled && h.Key.Length > 0)) headers[h.Key] = h.Value;
            return new ApiRequest { Name = _name, Method = _method, Url = _url, Headers = headers, Body = _method == "GET" ? null : _body, Auth = _auth.Clone(), QueryParams = _query.Where(q => q.IsEnabled).Select(q => new ApiKV { Key = q.Key, Value = q.Value }).ToList() };
        }

        void Send()
        {
            if (_svc.IsLoading || _url.Trim().Length == 0) return;
            var req = Build();
            var task = _svc.Execute(req);
            RenderReqBar(); RenderResponse();
            task.ContinueWith(tk => Dispatcher.BeginInvoke(new Action(() => { RenderReqBar(); RenderResponse(); RenderList(); })));
        }

        void LoadRequest(ApiRequest req, bool withName)
        {
            _url = req.Url ?? ""; _method = Methods.Contains(req.Method) ? req.Method : "GET"; _body = req.Body ?? ""; _auth = (req.Auth ?? new ApiAuth()).Clone();
            if (req.Headers != null && req.Headers.Count > 0) _headers = req.Headers.Select(h => new ApiKV { Key = h.Key, Value = h.Value }).ToList();
            if (req.QueryParams != null) _query = req.QueryParams.Select(q => new ApiKV { Key = q.Key, Value = q.Value, IsEnabled = q.IsEnabled }).ToList();
            if (withName) _name = req.Name;
            RenderReqBar(); RenderRequest();
        }

        Window Sheet(string title, UIElement content, double width)
        {
            var t = Theme.Current;
            var w = new Window { Title = title, Content = V.Box(content, V.P(20), t.PanelBackground, 0), Width = width, SizeToContent = SizeToContent.Height, ResizeMode = ResizeMode.NoResize, WindowStartupLocation = WindowStartupLocation.CenterOwner, Owner = Window.GetWindow(this), Background = t.PanelBackground, FontFamily = UIFonts.UI, ShowInTaskbar = false };
            w.SourceInitialized += delegate { Native.StyleWindow(w, t.IsDark); };
            return w;
        }

        void ShowSnippet()
        {
            var t = Theme.Current;
            string lang = Defaults.Str("apiStudio.snippetLanguage", "Swift (URLSession)");
            var code = new TextBox { IsReadOnly = true, FontFamily = UIFonts.Mono, FontSize = 11, Foreground = t.EditorText, Background = t.P(0.04), BorderThickness = new Thickness(0), Padding = new Thickness(12), Height = 280, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto };
            var req = Build();
            Window w = null;
            var pick = V.Button(V.Size(V.Box(V.H(6, V.T(lang, 11, FontWeights.Medium, t.Primary), V.Sp(), Sym.Icon("chevron.up.chevron.down", 8, t.Secondary)), V.P(8, 0), t.P(0.06), 5), 190, 24), null);
            Action refresh = () => { code.Text = _svc.Snippet(req, lang); ((TextBlock)((Stack)((Border)pick.Child).Child).Children[0]).Text = lang; };
            pick.MenuItems = () => ApiService.SnippetLanguages.Select(l => { var ll = l; return new MenuItemSpec { Title = l, Checked = l == lang, Action = () => { lang = ll; Defaults.Set("apiStudio.snippetLanguage", ll); refresh(); } }; }).ToList();
            refresh();
            var head = V.H(6, Sym.Icon("curlybraces", 13, t.Accent), V.T("Generate Code & SDK", 14, FontWeights.SemiBold, t.Primary), V.Sp(), pick);
            var buttons = V.H(8, V.Button(V.Box(V.T("Close", 12, FontWeights.Normal, t.Primary), V.P(12, 5), t.P(0.08), 6), () => w.Close()), V.Sp(),
                V.Button(V.Box(V.T("Copy Code", 12, FontWeights.SemiBold, Brushes.White), V.P(12, 5), t.Accent, 6), () => { try { Clipboard.SetText(code.Text); } catch (Exception ex) { Debug.WriteLine("copy: " + ex.Message); } w.Close(); }));
            var col = V.VLead(12, V.Self(head, Cross.Stretch), V.Self(new Border { Child = code, CornerRadius = new CornerRadius(6), ClipToBounds = true }, Cross.Stretch), V.Self(buttons, Cross.Stretch));
            col.Align = Cross.Stretch;
            w = Sheet("Code Snippet", col, 580);
            w.ShowDialog();
        }

        void CurlSheet(string initial)
        {
            var t = Theme.Current;
            bool export = initial.Length > 0;
            var box = new TextBox { Text = initial, AcceptsReturn = true, FontFamily = UIFonts.Mono, FontSize = 11, Height = 200, Foreground = t.EditorText, Background = t.P(0.04), BorderThickness = new Thickness(0), Padding = new Thickness(8), TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            Window w = null;
            var buttons = V.H(8, V.Button(V.Box(V.T("Cancel", 12, FontWeights.Normal, t.Primary), V.P(12, 5), t.P(0.08), 6), () => w.Close()), V.Sp());
            if (export)
                buttons.Children.Add(V.Button(V.Box(V.T("Copy", 12, FontWeights.SemiBold, Brushes.White), V.P(12, 5), t.Accent, 6), () => { try { Clipboard.SetText(box.Text); } catch (Exception ex) { Debug.WriteLine("copy: " + ex.Message); } w.Close(); }));
            else
            {
                buttons.Children.Add(V.Button(V.Box(V.T("Paste & Import", 12, FontWeights.Normal, t.Primary), V.P(12, 5), t.P(0.08), 6), () => { try { if (Clipboard.ContainsText()) box.Text = Clipboard.GetText(); } catch (Exception ex) { Debug.WriteLine("paste: " + ex.Message); } }));
                buttons.Children.Add(V.Button(V.Box(V.T("Import", 12, FontWeights.SemiBold, Brushes.White), V.P(12, 5), t.Accent, 6), () =>
                {
                    var req = _svc.ImportCurl(box.Text);
                    if (req == null) { MessageBox.Show(w, "No URL found in the cURL command.", "Import cURL", MessageBoxButton.OK, MessageBoxImage.Information); return; }
                    LoadRequest(req, false); w.Close();
                }));
            }
            var col = V.VLead(12, V.T(export ? "Export cURL" : "Import cURL", 14, FontWeights.SemiBold, t.Primary), V.Self(new Border { Child = box, CornerRadius = new CornerRadius(6), ClipToBounds = true }, Cross.Stretch), V.Self(buttons, Cross.Stretch));
            col.Align = Cross.Stretch;
            w = Sheet(export ? "Export cURL" : "Import cURL", col, 500);
            w.ShowDialog();
        }
    }
}
