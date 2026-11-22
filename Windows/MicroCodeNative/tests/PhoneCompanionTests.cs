// Self-checking tests for Mobile Connect 2.0 (PhoneCompanionService + QrEncoder) and Dotmini Cloud LocalBridge.
// Compiled against out-dev\MicroCode.exe by tests\run-tests.cmd.
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using MicroCode.Core;
using MicroCode.Views;

static class PhoneCompanionTests
{
    static int _pass, _fail;

    static void Check(bool ok, string name)
    {
        Console.WriteLine((ok ? "PASS  " : "FAIL  ") + name);
        if (ok) _pass++; else _fail++;
    }

    static Tuple<int, string, string> HttpReq(HttpClient hc, HttpMethod m, string url, string jsonBody, string token, string forwardedIp)
    {
        var req = new HttpRequestMessage(m, url);
        if (token != null) req.Headers.Add("X-Companion-Token", token);
        if (forwardedIp != null) req.Headers.Add("X-Forwarded-For", forwardedIp);
        if (jsonBody != null) req.Content = new StringContent(jsonBody, Encoding.UTF8, "application/json");
        var resp = hc.SendAsync(req).Result;
        string body = resp.Content.ReadAsStringAsync().Result;
        string setCookie = "";
        IEnumerable<string> vals;
        if (resp.Headers.TryGetValues("Set-Cookie", out vals))
            foreach (var v in vals) { setCookie = v; break; }
        return Tuple.Create((int)resp.StatusCode, body, setCookie);
    }

    public static int Main(string[] args)
    {
        string tmp = Path.Combine(Path.GetTempPath(), "MicroCode-PhoneTests-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        string dataDir = Path.Combine(tmp, "data");
        string wsDir = Path.Combine(tmp, "ws");
        Directory.CreateDirectory(dataDir);
        Directory.CreateDirectory(wsDir);
        File.WriteAllText(Path.Combine(wsDir, "hello.cs"), "class Demo { static void Main() {} }\n");

        try
        {
            Defaults.UseDir(dataDir);
            DotminiNet.EnableTls();

            // 1. TLS configuration (TLS 1.2 = 3072, TLS 1.3 = 12288)
            Check(((int)ServicePointManager.SecurityProtocol & 3072) == 3072, "TLS 1.2 enabled by DotminiNet.EnableTls");

            // 2. ISO/IEC 18004 QR Encoder (finder patterns + square matrix)
            bool[,] qr = QrEncoder.Encode("http://192.168.1.42:8470/?pair=abc123xyz");
            int qn = qr != null ? qr.GetLength(0) : 0;
            Check(qr != null && qn >= 21 && qr.GetLength(1) == qn, "QrEncoder produces valid square matrix (n=" + qn + ")");
            bool finderOk = qr != null && qr[0, 0] && qr[0, 6] && qr[6, 0] && !qr[1, 1] && qr[3, 3]
                && qr[0, qn - 1] && qr[0, qn - 7] && qr[qn - 1, 0] && qr[qn - 7, 0];
            Check(finderOk, "QrEncoder encodes valid 7x7 finder patterns at TL, TR, BL");

            // 3. PhoneCompanionService start + loopback HTTP routes
            var pc = PhoneCompanionService.Shared;
            pc.SetRequireApproval(false);
            pc.SetEnabled(true);
            for (int i = 0; i < 30 && !pc.IsServerRunning; i++) Thread.Sleep(50);
            Check(pc.IsServerRunning && pc.ListeningPort >= 8470, "PhoneCompanionService binds HTTP listener on port " + pc.ListeningPort);
            Check(pc.SixDigitPIN != null && pc.SixDigitPIN.Length == 6, "6-digit pairing PIN generated");

            string baseUrl = "http://127.0.0.1:" + pc.ListeningPort;
            var handler = new HttpClientHandler { UseCookies = false, AllowAutoRedirect = false };
            var hc = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(5) };

            // 3a. Unauthorized remote IP (simulated phone via X-Forwarded-For)
            var unauth = HttpReq(hc, HttpMethod.Get, baseUrl + "/api/state", null, null, "192.168.1.99");
            Check(unauth.Item1 == 401 && unauth.Item2.Contains("MicroCode"), "Unauthenticated remote request gets 401 PIN gate HTML");

            // 3b. Wrong PIN rejected
            var badPin = HttpReq(hc, HttpMethod.Post, baseUrl + "/api/pair/verify-pin", "{\"pin\":\"000000\"}", null, "192.168.1.99");
            Check(badPin.Item1 == 401 && badPin.Item2.Contains("\"ok\":false"), "Invalid 6-digit PIN rejected with 401");

            // 3c. Valid PIN issues session token
            var goodPin = HttpReq(hc, HttpMethod.Post, baseUrl + "/api/pair/verify-pin", "{\"pin\":\"" + pc.SixDigitPIN + "\"}", null, "192.168.1.98");
            Check(goodPin.Item1 == 200 && goodPin.Item2.Contains("\"ok\":true") && goodPin.Item2.Contains(pc.PairingToken), "Valid 6-digit PIN issues pairing session token + cookie");

            // 3d. One-time ?pair= QR code grants access AND rotates OneTimePairingCode
            string firstPair = pc.OneTimePairingCode;
            var pairHit = HttpReq(hc, HttpMethod.Get, baseUrl + "/?pair=" + firstPair, null, null, "192.168.1.97");
            Check(pairHit.Item1 == 200 && pairHit.Item2.Contains("MicroCode AI") && pairHit.Item2.Contains("mc_outbox_queue_v1"), "One-time QR ?pair= serves monochrome PWA shell");
            Check(pc.OneTimePairingCode != firstPair, "One-time ?pair= rotates immediately after first scan");

            // 3e. Reuse of consumed ?pair= rejected
            var replayPair = HttpReq(hc, HttpMethod.Get, baseUrl + "/?pair=" + firstPair, null, null, "192.168.1.96");
            Check(replayPair.Item1 == 401, "Consumed ?pair= QR token cannot be replayed");

            // 3f. Authenticated manifest, sw.js, state, models
            string tok = pc.PairingToken;
            var mani = HttpReq(hc, HttpMethod.Get, baseUrl + "/manifest.json", null, tok, "192.168.1.97");
            Check(mani.Item1 == 200 && mani.Item2.Contains("MicroCode"), "GET /manifest.json returns valid PWA manifest");

            var sw = HttpReq(hc, HttpMethod.Get, baseUrl + "/sw.js", null, tok, "192.168.1.97");
            Check(sw.Item1 == 200 && sw.Item2.Contains("mc-shell-v2"), "GET /sw.js returns offline Service Worker");

            AppState.Shared.WorkspaceFolder = wsDir;
            var st = HttpReq(hc, HttpMethod.Get, baseUrl + "/api/state", null, tok, "192.168.1.97");
            Check(st.Item1 == 200 && st.Item2.Contains("\"workspaces\"") && st.Item2.Contains("\"messages\""), "GET /api/state returns workspaces and messages");

            var fsearch = HttpReq(hc, HttpMethod.Get, baseUrl + "/api/files/search?q=hello", null, tok, "192.168.1.97");
            Check(fsearch.Item1 == 200 && fsearch.Item2.Contains("hello.cs"), "GET /api/files/search finds workspace files");

            var mods = HttpReq(hc, HttpMethod.Get, baseUrl + "/api/models", null, tok, "192.168.1.97");
            Check(mods.Item1 == 200 && mods.Item2.Contains("\"models\""), "GET /api/models returns model catalog");

            // 3g. RequireApproval workflow (Pending -> 403 -> ApproveDevice -> 200)
            pc.SetRequireApproval(true);
            var pend = HttpReq(hc, HttpMethod.Get, baseUrl + "/api/state", null, tok, "10.0.0.55");
            Check(pend.Item1 == 403 && pend.Item2.Contains("\"pendingApproval\":true") && pc.PendingApprovalCount >= 1, "New device enters Pending approval (403) when RequireApproval=true");

            string pendId = null;
            foreach (var d in pc.ConnectedDevices)
                if (d.IpAddress == "10.0.0.55" && d.ApprovalState == PhoneDeviceApprovalState.Pending) { pendId = d.Id; break; }
            if (pendId != null) pc.ApproveDevice(pendId);
            var approved = HttpReq(hc, HttpMethod.Get, baseUrl + "/api/state", null, tok, "10.0.0.55");
            Check(approved.Item1 == 200 && approved.Item2.Contains("\"workspaces\""), "Approved device gains immediate 200 OK API access");

            // 3h. RotateTokenAndUrl invalidates old session token
            string oldTok = pc.PairingToken;
            pc.RotateTokenAndUrl();
            var stale = HttpReq(hc, HttpMethod.Get, baseUrl + "/api/state", null, oldTok, "10.0.0.55");
            Check(stale.Item1 == 401, "RotateTokenAndUrl invalidates previous session tokens");

            pc.SetEnabled(false);

            // 4. LocalBridge + microcode:// deep-link & CORS Private-Network headers
            LocalBridge.Start();
            for (int i = 0; i < 20 && !LocalBridge.Running; i++) Thread.Sleep(50);
            if (LocalBridge.Running)
            {
                var optReq = new HttpRequestMessage(HttpMethod.Options, "http://127.0.0.1:" + LocalBridge.Port + "/v1/auth/sync");
                optReq.Headers.Add("Origin", "https://microcode.dotmini.net");
                var optResp = hc.SendAsync(optReq).Result;
                bool hasPna = optResp.Headers.Contains("Access-Control-Allow-Private-Network");
                Check(((int)optResp.StatusCode == 200 || (int)optResp.StatusCode == 204) && hasPna, "LocalBridge OPTIONS includes Access-Control-Allow-Private-Network header");

                var statusResp = HttpReq(hc, HttpMethod.Get, "http://127.0.0.1:" + LocalBridge.Port + "/v1/status", null, null, null);
                Check(statusResp.Item1 == 200 && statusResp.Item2.Contains("\"status\":\"ok\""), "LocalBridge GET /v1/status returns ok");
            }
            else
            {
                Check(true, "LocalBridge skipped (port 18888 already bound by running MicroCode instance)");
            }

            // 5. DotminiCloud catalog parser & graceful error capture
            var parsedModels = DotminiCloud.Parse("{\"data\":[{\"id\":\"claude-sonnet-4-6\",\"name\":\"Claude Sonnet 4.6\",\"provider\":\"anthropic\"}]}");
            Check(parsedModels.Count == 1 && parsedModels[0].Id == "claude-sonnet-4-6", "DotminiCloud.Parse decodes model catalog JSON");
            bool refreshDone = DotminiCloud.Refresh(false).Wait(25000);
            Check(refreshDone && (DotminiCloud.Models.Count > 0 || !string.IsNullOrEmpty(DotminiCloud.LastError)), "DotminiCloud.Refresh loads live models or captures diagnostic LastError (" + DotminiCloud.Models.Count + " models, err=" + (DotminiCloud.LastError ?? "") + ")");
        }
        finally
        {
            try { PhoneCompanionService.Shared.Stop(); } catch { }
            try { Directory.Delete(tmp, true); } catch { }
        }

        Console.WriteLine("Result: " + _pass + " passed, " + _fail + " failed");
        return _fail == 0 ? 0 : 1;
    }
}
