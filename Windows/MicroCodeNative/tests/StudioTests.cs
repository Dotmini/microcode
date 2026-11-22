// Self-checking tests for API Studio (src/Views/ApiStudio.cs) and first-launch onboarding (src/Views/FirstLaunch.cs),
// compiled against out-dev\MicroCode.exe by run-tests.cmd. The HTTP checks talk to a tiny HTTP/1.1 server on a loopback
// TcpListener (no http.sys URL ACL needed); nothing leaves the machine and the data dir is an isolated temp folder.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;
using MicroCode.Core;
using MicroCode.Views;

static class StudioTests
{
    static int _pass, _fail;
    static void Check(bool ok, string name) { Console.WriteLine((ok ? "PASS  " : "FAIL  ") + name); if (ok) _pass++; else _fail++; }

    [STAThread]
    static int Main()
    {
        string root = Path.Combine(Path.GetTempPath(), "mc-studiotests-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        Directory.CreateDirectory(root);
        Defaults.UseDir(Path.Combine(root, "data"));
        TaskFiles.HomeOverride = Path.Combine(root, "data", ".microcode");
        try { ApiTests(root); WelcomeTests(); BrowserTests(); }
        catch (Exception ex) { Check(false, "unexpected exception: " + ex); }
        finally { try { Directory.Delete(root, true); } catch (Exception ex) { Console.WriteLine("cleanup: " + ex.Message); } }
        Console.WriteLine();
        Console.WriteLine(_pass + " passed, " + _fail + " failed");
        return _fail == 0 ? 0 : 1;
    }

    /// <summary>Reads one HTTP/1.1 request: headers (case-insensitive), ":line" = request line, ":body" = Content-Length bytes.</summary>
    static Dictionary<string, string> ReadRequest(NetworkStream s)
    {
        var head = new List<byte>();
        while (true)
        {
            int b = s.ReadByte();
            if (b < 0) break;
            head.Add((byte)b);
            int n = head.Count;
            if (n >= 4 && head[n - 4] == '\r' && head[n - 3] == '\n' && head[n - 2] == '\r' && head[n - 1] == '\n') break;
        }
        var lines = Encoding.ASCII.GetString(head.ToArray()).Split(new[] { "\r\n" }, StringSplitOptions.None);
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        map[":line"] = lines[0];
        foreach (var l in lines.Skip(1)) { int c = l.IndexOf(':'); if (c > 0) map[l.Substring(0, c).Trim()] = l.Substring(c + 1).Trim(); }
        string expect;
        if (map.TryGetValue("Expect", out expect) && expect.Equals("100-continue", StringComparison.OrdinalIgnoreCase))
        {
            byte[] cont = Encoding.ASCII.GetBytes("HTTP/1.1 100 Continue\r\n\r\n");
            s.Write(cont, 0, cont.Length);
        }
        int len = 0; string cl;
        if (map.TryGetValue("Content-Length", out cl)) int.TryParse(cl, out len);
        var body = new byte[len]; int got = 0;
        while (got < len) { int r = s.Read(body, got, len - got); if (r <= 0) break; got += r; }
        map[":body"] = Encoding.UTF8.GetString(body, 0, got);
        return map;
    }

    static void ApiTests(string root)
    {
        var svc = new ApiService();
        svc.EnsureLoaded();
        Check(svc.Collections.Any(c => c.Name == "Default Collection") && svc.Environments.Any(e => e.Name == "Development" && e.Variables.Any(v => v.Key == "base_url")), "API: default collection and Development environment with base_url");
        svc.ActiveEnvironmentId = svc.Environments[0].Id;
        Check(svc.Resolve("{{base_url}}/users") == "http://localhost:3000/users", "API: {{variables}} resolve from the active environment");
        var auth = new ApiAuth { Type = "API Key", ApiKeyName = "key", ApiKeyValue = "a b", ApiKeyIn = "query" };
        string url = svc.BuildUrl("http://x/y?z=1", new List<ApiKV> { new ApiKV { Key = "q", Value = "hello world" }, new ApiKV { Key = "off", Value = "1", IsEnabled = false } }, auth);
        Check(url == "http://x/y?z=1&q=hello%20world&key=a%20b", "API: query params and an API key in the query are encoded, disabled params skipped (" + url + ")");

        var imported = svc.ImportCurl("curl -X POST 'https://api.example.com/v1/items' \\\n  -H 'Content-Type: application/json' -H \"X-Trace: 7\" \\\n  -d '{\"name\": \"a b\"}' -u 'me:secret'");
        Check(imported != null && imported.Method == "POST" && imported.Url == "https://api.example.com/v1/items" && imported.Headers["X-Trace"] == "7" && imported.Body == "{\"name\": \"a b\"}" && imported.Auth.Type == "Basic Auth" && imported.Auth.BasicPassword == "secret",
            "cURL import: method, URL, headers, quoted body with spaces, basic auth");
        Check(svc.ImportCurl("curl -H 'A: 1'") == null, "cURL import: a command without a URL is rejected");
        string curl = svc.ExportCurl(new ApiRequest { Method = "PUT", Url = "https://h/p", Headers = new Dictionary<string, string> { { "A", "1" } }, Body = "it's", Auth = new ApiAuth { Type = "Bearer Token", BearerToken = "tok" } });
        Check(curl.StartsWith("curl \\\n  -X PUT \\\n  'https://h/p'") && curl.Contains("-H 'Authorization: Bearer tok'") && curl.Contains("-d 'it'\\''s'"), "cURL export: one flag per line, bearer header, shell-escaped body");
        var round = svc.ImportCurl(curl);
        Check(round != null && round.Method == "PUT" && round.Body == "it's" && round.Headers["Authorization"] == "Bearer tok", "cURL: export then import keeps the method, an apostrophe and the headers");

        string pretty = ApiService.PrettyJson("{\"b\":[1,2],\"a\":{\"s\":\"x, y: z\"},\"e\":[]}");
        Check(pretty != null && pretty.Contains("\"s\": \"x, y: z\"") && pretty.Contains("\n  \"b\": [\n    1,\n    2\n  ]") && pretty.Contains("\"e\": []"), "Pretty JSON: indentation, strings with , and : untouched, empty arrays inline");
        Check(ApiService.PrettyJson("not json") == null && ApiService.PrettyJson("{broken") == null, "Pretty JSON: non-JSON bodies are left as they are");

        foreach (var lang in ApiService.SnippetLanguages)
        {
            string code = svc.Snippet(new ApiRequest { Method = "POST", Url = "{{base_url}}/x", Headers = new Dictionary<string, string> { { "Content-Type", "application/json" } }, Body = "{\"k\": 1}" }, lang);
            Check(code.Contains("http://localhost:3000/x") && (lang == "cURL" || code.Contains("{\"k\": 1}") || code.Contains("{\\\"k\\\": 1}")), "Code snippet: " + lang + " resolves variables and carries the body");
        }

        // workspace route scanner + project .env importer
        string ws = Path.Combine(root, "proj");
        Directory.CreateDirectory(Path.Combine(ws, "api"));
        Directory.CreateDirectory(Path.Combine(ws, "app", "users"));
        Directory.CreateDirectory(Path.Combine(ws, "node_modules", "lib"));
        File.WriteAllText(Path.Combine(ws, "api", "main.py"), "@app.get(\"/health\")\ndef h(): pass\n@router.post('/items')\ndef c(): pass\n");
        File.WriteAllText(Path.Combine(ws, "server.js"), "app.delete('/items/:id', h)\nrouter.patch(\"/items/:id\", h)\n");
        File.WriteAllText(Path.Combine(ws, "app", "users", "route.ts"), "export async function GET() {}\nexport function POST() {}\n");
        File.WriteAllText(Path.Combine(ws, "main.go"), "r.GET(\"/ping\", h)\n");
        File.WriteAllText(Path.Combine(ws, "lib.rs"), ".route(\"/rust\", get(handler))\n");
        File.WriteAllText(Path.Combine(ws, "node_modules", "lib", "x.js"), "app.get('/ignored', h)\n");
        var routes = svc.ScanRoutes(ws);
        var names = routes.Select(r => r.Method + " " + r.Url.Replace("{{base_url}}", "")).ToList();
        Check(names.Contains("GET /health") && names.Contains("POST /items") && names.Contains("DELETE /items/:id") && names.Contains("PATCH /items/:id") && names.Contains("GET /users") && names.Contains("POST /users") && names.Contains("GET /ping") && names.Contains("GET /rust"),
            "Route scan: FastAPI, Express, Next.js app router, Go and Axum routes (" + string.Join(", ", names) + ")");
        Check(!names.Any(x => x.Contains("ignored")) && svc.Collections[0].Name == "Scanned Project Routes (" + routes.Count + ")", "Route scan: node_modules skipped; results land in a 'Scanned Project Routes' collection");
        File.WriteAllText(Path.Combine(ws, ".env"), "# comment\nAPI_KEY=\"abc 123\"\nbase_url=http://127.0.0.1:9000\nEMPTY=\n");
        int count = svc.LoadDotEnv(ws);
        var env = svc.ActiveEnvironment;
        Check(count == 3 && env.Name == "Project (.env)" && env.Variables.First(v => v.Key == "API_KEY").Value == "abc 123" && svc.Resolve("{{base_url}}") == "http://127.0.0.1:9000", "Load .env: quoted values, comments skipped, becomes the active environment");

        // real requests against a loopback server
        var tcp = new TcpListener(IPAddress.Loopback, 0);
        tcp.Start();
        int port = ((IPEndPoint)tcp.LocalEndpoint).Port;
        var seen = new List<Dictionary<string, string>>();
        var serve = Task.Run(() =>
        {
            for (int i = 0; i < 2; i++)
            {
                using (var client = tcp.AcceptTcpClient())
                {
                    client.ReceiveTimeout = 10000;
                    var s = client.GetStream();
                    var req = ReadRequest(s);
                    lock (seen) seen.Add(req);
                    byte[] body = Encoding.UTF8.GetBytes(i == 0 ? "{\"ok\":true,\"items\":[1,2,3]}" : "nope");
                    byte[] head = Encoding.ASCII.GetBytes("HTTP/1.1 " + (i == 0 ? "201 Created" : "404 Not Found") + "\r\nContent-Type: application/json\r\nX-Request-Id: test-123\r\nContent-Length: " + body.Length + "\r\nConnection: close\r\n\r\n");
                    s.Write(head, 0, head.Length);
                    s.Write(body, 0, body.Length);
                    s.Flush();
                }
            }
        });
        var post = new ApiRequest { Method = "POST", Url = "http://127.0.0.1:" + port + "/v1/items", Headers = new Dictionary<string, string> { { "Content-Type", "application/json" } }, Body = "{\"base\": \"{{base_url}}\"}", Auth = new ApiAuth { Type = "Bearer Token", BearerToken = "{{API_KEY}}" } };
        var resp = svc.Execute(post).GetAwaiter().GetResult();
        Check(resp != null && resp.Status == 201 && resp.StatusText == "Created" && resp.FormattedBody.Contains("\"items\": [") && resp.BodySize > 0 && resp.Headers["X-Request-Id"] == "test-123",
            "Execute: a real POST returns 201 Created with a pretty body and the response headers" + (resp == null ? " (error: " + svc.Error + ")" : ""));
        var first = seen.Count > 0 ? seen[0] : new Dictionary<string, string>();
        string line, authz, body0, ct;
        first.TryGetValue(":line", out line); first.TryGetValue("Authorization", out authz); first.TryGetValue(":body", out body0); first.TryGetValue("Content-Type", out ct);
        Check(line == "POST /v1/items HTTP/1.1" && authz == "Bearer abc 123" && body0 == "{\"base\": \"http://127.0.0.1:9000\"}" && ct == "application/json",
            "Execute: method/path, bearer token and body resolved from {{variables}}, Content-Type sent");
        var latency = svc.Assertions.FirstOrDefault(a => a.Name == "Latency SLA (< 1500ms)");
        Check(svc.History.Count == 1 && svc.History[0].Status == 201 && svc.Assertions.Count == 5 && latency != null && latency.Passed == (resp != null && resp.DurationMs < 1500)
            && svc.Assertions.Where(a => a != latency).All(a => a.Passed) && svc.Assertions.Any(a => a.Name == "Valid JSON Object" && a.Details == "Root keys: [items, ok]"),
            "Execute: history entry + 5 contract/SLA checks (status, latency, body, JSON object keys, Content-Type)");
        var bad = svc.Execute(new ApiRequest { Method = "GET", Url = "http://127.0.0.1:" + port + "/missing" }).GetAwaiter().GetResult();
        Check(bad != null && bad.Status == 404 && bad.StatusText == "Not Found" && svc.Assertions.Any(a => a.Name == "Status Code 2xx OK" && !a.Passed) && svc.Assertions.Any(a => a.Name == "Valid JSON Format" && !a.Passed),
            "Execute: a 404 with a non-JSON body fails the status and JSON checks");
        Check(serve.Wait(10000), "Execute: the loopback server saw both requests");
        tcp.Stop();
        var invalid = svc.Execute(new ApiRequest { Method = "GET", Url = "ftp://nope" }).GetAwaiter().GetResult();
        Check(invalid == null && svc.Error != null && svc.Error.StartsWith("Invalid URL") && svc.History.Count == 2, "Execute: invalid URLs are reported instead of sent and stay out of history");

        var svc2 = new ApiService();
        svc2.EnsureLoaded();
        Check(svc2.History.Count == 2 && svc2.History[0].Status == 404 && svc2.Environments.Any(e => e.Name == "Project (.env)") && svc2.ActiveEnvironment.Name == "Project (.env)" && svc2.Collections.Any(c => c.Name.StartsWith("Scanned Project Routes")),
            "Persistence: history, the active environment and collections reload from disk");
    }

    static void BrowserTests()
    {
        Check(BrowserSession.Normalize("example.com") == "https://example.com" && BrowserSession.Normalize("https://a.b/c") == "https://a.b/c"
            && BrowserSession.Normalize("localhost:5173/x") == "http://localhost:5173/x" && BrowserSession.Normalize("salt & pepper") == "https://www.google.com/search?q=salt%20%26%20pepper"
            && BrowserSession.Normalize("   ") == null, "Browser: URL bar input → https host, localhost over http, otherwise a Google search");

        var s = new BrowserSession();
        string first = s.Tabs[0].Id;
        var t2 = s.AddTab();
        Check(s.Tabs.Count == 2 && s.Active == 1 && t2.Url == BrowserSession.HomeUrl && t2.Title == "New Tab", "Browser: + opens a Google tab and selects it");
        Check(s.CloseTab(t2.Id) && s.Active == 0 && !s.CloseTab(first) && s.Tabs.Count == 1, "Browser: closing clamps the active tab; the last tab cannot be closed");
        for (int i = 0; i < 205; i++) s.RecordVisit("https://h/" + i, "p" + i);
        Check(s.History.Count == 200 && s.History[0].Url == "https://h/204", "Browser: history keeps the newest 200 visits");
        Check(s.ToggleBookmark("https://x", "X") && s.IsBookmarked("https://x") && !s.ToggleBookmark("https://x", "X") && !s.IsBookmarked("https://x"), "Browser: the star adds and removes a bookmark");

        Check(s.Handle("{\"_type\":\"console\",\"level\":\"warn\",\"message\":\"slow\"}") == "console" && s.Console[0].Level == "warn" && s.Console[0].Message == "slow", "Browser: console messages from the page are logged");
        for (int i = 0; i < 310; i++) s.Handle("{\"_type\":\"network\",\"method\":\"POST\",\"url\":\"/api/" + i + "\",\"status\":201,\"durationMs\":12.6}");
        Check(s.Network.Count == 300 && s.Network[299].Url == "/api/309" && s.Network[0].Url == "/api/10" && s.Network[299].DurationMs == 13 && s.Network[299].Status == 201, "Browser: network log keeps the newest 300 fetch/XHR entries");
        Check(s.Handle("not json") == null && s.Handle("{\"_type\":\"other\"}") == null, "Browser: unknown or malformed page messages are ignored");
        string pick = "{\"_type\":\"element_picked\",\"selector\":\"#buy\",\"tag\":\"button\",\"text\":\"Buy now\",\"outerHTML\":\"<button id=\\\"buy\\\">Buy now</button>\",\"styles\":\"display:block\",\"rect\":\"10,20 (100x30)\"}";
        s.Handle(pick);
        s.Picked[0].Note = "make it green";
        s.Handle(pick.Replace("Buy now\",\"outerHTML", "Buy today\",\"outerHTML"));
        Check(s.Picked.Count == 1 && s.Picked[0].Text == "Buy today" && s.Picked[0].Note == "make it green", "Browser: picking the same selector again updates it and keeps its note");
        for (int i = 0; i < 25; i++) s.Handle(pick.Replace("#buy", "#b" + i));
        Check(s.Picked.Count == 20 && s.Picked[19].Selector == "#b24", "Browser: at most 20 picked elements are kept");
        s.Handle("{\"_type\":\"element_unpicked\",\"selector\":\"#b24\"}");
        Check(s.Picked.Count == 19 && !s.Picked.Any(p => p.Selector == "#b24"), "Browser: clicking a picked element again removes it");

        var one = new List<BrowserPicked> { new BrowserPicked { Selector = "#buy", Tag = "button", Text = "Buy", OuterHtml = "<button>Buy</button>", Styles = "display:block", Rect = "1,2 (3x4)", Note = "green" } };
        string p1 = BrowserSession.AgentPrompt(one, "http://localhost:3000/", "bigger");
        Check(p1 == "[Inspect Element Target]\n- Page URL: http://localhost:3000/\n- Selector: `#buy` (`<button>` at 1,2 (3x4))\n- Element / Selected Text: `Buy`\n- Computed Styles: `display:block`\n- HTML Snippet:\n```html\n<button>Buy</button>\n```\n\nInstruction: green — bigger",
            "Agent prompt: one element in the Mac's [Inspect Element Target] format");
        var two = new List<BrowserPicked> { new BrowserPicked { Selector = "h1", Tag = "h1", Rect = "0,0 (9x9)", Styles = "s", OuterHtml = "<h1></h1>" }, new BrowserPicked { Selector = "p", Tag = "p", Rect = "0,9 (9x9)", Styles = "s", OuterHtml = "<p></p>", Text = "hi" } };
        string p2 = BrowserSession.AgentPrompt(two, "http://x/", "");
        Check(p2.StartsWith("[Multi-Point Inspect Targets (2 Elements Selected)]\n- Page URL: http://x/\n\n### Target #1: `h1` (`<h1>` at 0,0 (9x9))\n- Computed Styles: `s`") && p2.Contains("### Target #2: `p` (`<p>` at 0,9 (9x9))\n- Text Content: `hi`")
            && p2.EndsWith("### Overall Instruction for Selected Targets:\nปรับปรุงและแก้ไของค์ประกอบทั้ง 2 จุดที่เลือกให้สมบูรณ์และสอดคล้องกัน"), "Agent prompt: several elements with the default Thai instruction");

        Check(BrowserSession.FormatEvalResult("{\"ok\":true,\"v\":\"hi\"}") == "hi" && BrowserSession.FormatEvalResult("{\"ok\":true,\"v\":3}") == "3" && BrowserSession.FormatEvalResult("{\"ok\":true}") == "null"
            && BrowserSession.FormatEvalResult("{\"ok\":false}") == "Error evaluating JS" && BrowserSession.FormatEvalResult("{\"ok\":true,\"v\":{\"a\":[1]}}") == "{\n  \"a\": [\n    1\n  ]\n}",
            "JS REPL: strings raw, numbers, undefined as null, errors, objects as pretty JSON");
        Check(BrowserSession.EvalWrapper("1+'\"'").Contains("(0,eval)(\"1+\\u0027\\\"\\u0027\")"), "JS REPL: the script is passed to eval as an escaped JSON string");
    }

    static void WelcomeTests()
    {
        string flag = Path.Combine(Defaults.Dir, ".welcome_done");
        FirstLaunchWelcome.Suppressed = false;
        Check(FirstLaunchWelcome.ShouldShow, "Onboarding: shown on a fresh install with nobody signed in");
        File.WriteAllText(flag, "");
        Check(!FirstLaunchWelcome.ShouldShow, "Onboarding: the .welcome_done flag keeps it closed");
        File.Delete(flag);
        FirstLaunchWelcome.Suppressed = true;
        Check(!FirstLaunchWelcome.ShouldShow, "Onboarding: snapshot runs suppress it");
        FirstLaunchWelcome.Suppressed = false;
    }
}
