// Dotmini ID & Dotmini Cloud — port of SupabaseAuthService.swift (self-hosted Supabase GoTrue session), DotminiPlatformKeyService.swift
// (sk-dotmini-live-… platform keys, 1-Click Connect), the Dotmini Cloud model catalog in AIModelCatalog.swift, and the loopback
// auth bridge in MCPServer.swift (127.0.0.1:18888/v1/auth/sync, used by microcode.dotmini.net/auth.html to hand a web sign-in to the app).
// Sessions and keys are stored DPAPI-encrypted (per Windows user) in settings.json — the Windows counterpart of the macOS Keychain.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using MicroCode.Core;

namespace MicroCode.Views
{
    /// <summary>Small JSON helpers over JavaScriptSerializer dictionaries.</summary>
    public static class DJ
    {
        public static readonly JavaScriptSerializer S = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
        public static Dictionary<string, object> Obj(string s)
        {
            if (string.IsNullOrWhiteSpace(s)) return null;
            try { return S.Deserialize<Dictionary<string, object>>(s); } catch { return null; }
        }
        public static string Str(Dictionary<string, object> o, string k)
        {
            object v;
            if (o == null || !o.TryGetValue(k, out v) || v == null || v is Dictionary<string, object> || v is System.Collections.ArrayList) return null;
            return Convert.ToString(v, CultureInfo.InvariantCulture);
        }
        public static double? Num(Dictionary<string, object> o, string k)
        {
            object v;
            if (o == null || !o.TryGetValue(k, out v) || v == null) return null;
            try { return Convert.ToDouble(v, CultureInfo.InvariantCulture); } catch { return null; }
        }
        public static Dictionary<string, object> Child(Dictionary<string, object> o, string k) { object v; return o != null && o.TryGetValue(k, out v) ? v as Dictionary<string, object> : null; }
        public static System.Collections.ArrayList Arr(Dictionary<string, object> o, string k) { object v; return o != null && o.TryGetValue(k, out v) ? AsList(v) : null; }
        /// <summary>JavaScriptSerializer yields ArrayList from Deserialize&lt;T&gt; but object[] from DeserializeObject — accept both.</summary>
        public static System.Collections.ArrayList AsList(object v)
        {
            var l = v as System.Collections.ArrayList;
            if (l != null) return l;
            var a = v as object[];
            return a != null ? new System.Collections.ArrayList(a) : null;
        }
        public static string Ser(object o) { return S.Serialize(o); }
        public static StringContent Body(object o) { return new StringContent(S.Serialize(o), Encoding.UTF8, "application/json"); }

        /// <summary>extractOpenAICompatibleErrorMessage: best human-readable text out of an OpenAI / Anthropic / GoTrue / FastAPI error body.</summary>
        public static string ErrorText(string raw)
        {
            var o = Obj(raw);
            if (o == null)
            {
                string s = Regex.Replace(raw ?? "", "<[^>]+>", " ").Trim();
                s = Regex.Replace(s, @"\s+", " ");
                return s.Length > 300 ? s.Substring(0, 300) + "…" : s;
            }
            var err = Child(o, "error");
            if (err != null) { string m = Str(err, "message") ?? Str(err, "detail"); if (!string.IsNullOrEmpty(m)) return m; }
            string es = Str(o, "error_description") ?? Str(o, "msg") ?? Str(o, "message") ?? Str(o, "detail") ?? Str(o, "error");
            if (!string.IsNullOrEmpty(es)) return es;
            var det = Arr(o, "detail");
            if (det != null) return string.Join("; ", det.OfType<Dictionary<string, object>>().Select(d => Str(d, "msg")).Where(x => x != null));
            return "";
        }
    }

    public static class Dpapi
    {
        public static string Protect(string plain)
        {
            if (string.IsNullOrEmpty(plain)) return null;
            return Convert.ToBase64String(ProtectedData.Protect(Encoding.UTF8.GetBytes(plain), null, DataProtectionScope.CurrentUser));
        }
        public static string Unprotect(string b64)
        {
            if (string.IsNullOrEmpty(b64)) return null;
            try { return Encoding.UTF8.GetString(ProtectedData.Unprotect(Convert.FromBase64String(b64), null, DataProtectionScope.CurrentUser)); } catch { return null; }
        }
    }

    public static class DotminiNet
    {
        public static readonly HttpClient Http;
        static DotminiNet()
        {
            EnableTls();
            var handler = new HttpClientHandler
            {
                AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate
            };
            Http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(25) };
        }
        public static void EnableTls()
        {
            try
            {
                // .NET Framework 4.8: explicitly enable TLS 1.2 (3072) and TLS 1.3 (12288)
                ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072 | (SecurityProtocolType)12288 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;
            }
            catch
            {
                try { ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls; } catch { }
            }
            try { ServicePointManager.DefaultConnectionLimit = 32; } catch { }
            try { ServicePointManager.Expect100Continue = false; } catch { }
        }
        public static void OpenExternalUrl(string url)
        {
            if (string.IsNullOrWhiteSpace(url)) return;
            try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true }); }
            catch { try { System.Diagnostics.Process.Start(url); } catch { } }
        }
        public static bool StandaloneAI;
        public static string AppVersion { get { return AppInfo.Version; } }
        public static string UserAgent { get { return (StandaloneAI ? "MicroCodeAI/" : "MicroCode/") + AppVersion + " (Windows)"; } }
        public static double UnixNow() { return (DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds; }

        /// <summary>Raises a static event on the UI thread.</summary>
        public static void Raise(Action handlers)
        {
            if (handlers == null) return;
            var app = Application.Current;
            if (app == null) { handlers(); return; }
            app.Dispatcher.BeginInvoke(handlers);
        }
    }

    // ── Dotmini ID (Supabase GoTrue) ─────────────────────────────────────────────

    public class DotminiSession
    {
        public string AccessToken, RefreshToken, UserId, Email, DisplayName;
        public double ExpiresAt; // unix seconds
        public bool IsExpired { get { return ExpiresAt <= 0 || ExpiresAt <= DotminiNet.UnixNow() + 60; } }
    }

    public class DotminiEntitlement
    {
        public string Plan = "", Role = "", BillingMode = "";
        public double CreditLimitTHB, CreditUsedTHB, CreditRemainingTHB, TopupTHB, TotalAvailableTHB, MarginPct = 20;
        public long TotalTokens;
        public int Quota, Used;
        public bool Loaded;
        static string B(double v, string fmt) { return "฿" + v.ToString(fmt, CultureInfo.InvariantCulture); }
        public string FormattedAvailable { get { return Role.ToLowerInvariant() == "admin" && TotalAvailableTHB <= 0 ? "ADMIN" : B(TotalAvailableTHB, "0.00"); } }
        public string FormattedPlanPool { get { return CreditLimitTHB > 0 ? B(CreditRemainingTHB, "0.00") + " / " + B(CreditLimitTHB, "0") : B(CreditRemainingTHB, "0.00"); } }
        public string PlanUpper { get { return string.IsNullOrWhiteSpace(Plan) ? "FREE" : Plan.Trim().ToUpperInvariant(); } }
        public bool IsPaid { get { string p = (Plan ?? "").ToLowerInvariant(); return new[] { "lite", "pro", "advanced", "bundle_pro", "bundle", "enterprise", "admin" }.Any(x => p.Contains(x)); } }
    }

    public static class DotminiAuth
    {
        const string DefaultUrl = "https://supabase-ai.dotmini.net";
        // Public anon key (role "anon") — configuration, not a credential; identical to SupabaseAuthService.Configuration.defaultPublicAnonKey.
        const string DefaultAnonKey = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc4NDExODEyMCwiZXhwIjo0OTM5NzkxNzIwLCJyb2xlIjoiYW5vbiJ9.mYIkNUopKdGqKfEnzV68pXTni670PFd-nuWXjCx174M";
        const string ConfigUrl = "https://microcode.dotmini.net/api/microcode/auth-config";
        public const string Portal = "https://microcode.dotmini.net";
        const string SessionKey = "dotmini_session_v1";

        public static event Action Changed;
        public static DotminiEntitlement Entitlement = new DotminiEntitlement();
        public static string ReauthReason = "";
        public static string LastError = "";
        static DotminiSession _session;
        static bool _loaded;
        static Task<string> _refreshing;
        static readonly object _gate = new object();

        static void Notify() { DotminiNet.Raise(Changed); }

        public static DotminiSession Session
        {
            get
            {
                if (!_loaded) { _loaded = true; _session = Load(); }
                return _session;
            }
        }
        public static bool SignedIn { get { return Session != null; } }

        static string BaseUrl { get { return (Defaults.Str("microcode.supabase.url", null) ?? DefaultUrl).TrimEnd('/'); } }
        static string AnonKey { get { return Defaults.Str("microcode.supabase.anon-key", null) ?? DefaultAnonKey; } }

        /// <summary>bootstrapConfiguration: fetch the public Supabase URL + anon key from the MicroCode host once, then cache it.</summary>
        static async Task Bootstrap()
        {
            if (Defaults.Has("microcode.supabase.url")) return;
            try
            {
                var raw = await DotminiNet.Http.GetStringAsync(ConfigUrl);
                var o = DJ.Obj(raw);
                string url = DJ.Str(o, "url"), anon = DJ.Str(o, "anon_key");
                if (!string.IsNullOrEmpty(url) && !string.IsNullOrEmpty(anon))
                {
                    Defaults.Set("microcode.supabase.url", url);
                    Defaults.Set("microcode.supabase.anon-key", anon);
                    Defaults.Set("microcode.supabase.redirect-url", DJ.Str(o, "redirect_url") ?? "microcode://auth/callback");
                }
            }
            catch { }
        }

        static HttpRequestMessage Req(HttpMethod m, string path, object body)
        {
            var r = new HttpRequestMessage(m, BaseUrl + path);
            r.Headers.TryAddWithoutValidation("apikey", AnonKey);
            r.Headers.TryAddWithoutValidation("User-Agent", DotminiNet.UserAgent);
            if (body != null) r.Content = DJ.Body(body);
            return r;
        }

        static DotminiSession Load()
        {
            var o = DJ.Obj(Dpapi.Unprotect(Defaults.Str(SessionKey, null)));
            if (o == null || string.IsNullOrEmpty(DJ.Str(o, "AccessToken"))) return null;
            return new DotminiSession
            {
                AccessToken = DJ.Str(o, "AccessToken"), RefreshToken = DJ.Str(o, "RefreshToken") ?? "", UserId = DJ.Str(o, "UserId") ?? "",
                Email = DJ.Str(o, "Email") ?? "", DisplayName = DJ.Str(o, "DisplayName") ?? "", ExpiresAt = DJ.Num(o, "ExpiresAt") ?? 0
            };
        }

        static void Persist(DotminiSession s)
        {
            _session = s; _loaded = true;
            ReauthReason = "";
            Defaults.Set(SessionKey, Dpapi.Protect(DJ.Ser(s)));
            if (!string.IsNullOrEmpty(s.Email)) Defaults.Set("dotminiUserEmail", s.Email);
            Defaults.Flush();
            Notify();
        }

        public static double JwtExp(string jwt)
        {
            try
            {
                var parts = (jwt ?? "").Split('.');
                if (parts.Length < 2) return 0;
                string p = parts[1].Replace('-', '+').Replace('_', '/');
                p = p.PadRight(p.Length + (4 - p.Length % 4) % 4, '=');
                return DJ.Num(DJ.Obj(Encoding.UTF8.GetString(Convert.FromBase64String(p))), "exp") ?? 0;
            }
            catch { return 0; }
        }

        static DotminiSession Decode(Dictionary<string, object> raw)
        {
            string access = DJ.Str(raw, "access_token");
            var user = DJ.Child(raw, "user");
            string id = DJ.Str(user, "id");
            if (string.IsNullOrEmpty(access) || string.IsNullOrEmpty(id)) return null;
            double exp = DJ.Num(raw, "expires_at") ?? 0;
            if (exp <= 0) { var ein = DJ.Num(raw, "expires_in"); if (ein.HasValue) exp = DotminiNet.UnixNow() + ein.Value; }
            if (exp <= 0) exp = JwtExp(access);
            var meta = DJ.Child(user, "user_metadata");
            return new DotminiSession
            {
                AccessToken = access, RefreshToken = DJ.Str(raw, "refresh_token") ?? "", UserId = id, Email = DJ.Str(user, "email") ?? "",
                DisplayName = DJ.Str(meta, "display_name") ?? DJ.Str(meta, "full_name") ?? DJ.Str(meta, "name") ?? "", ExpiresAt = exp
            };
        }

        public static async Task<DotminiSession> SignIn(string email, string password)
        {
            await Bootstrap();
            HttpResponseMessage resp;
            try { resp = await DotminiNet.Http.SendAsync(Req(HttpMethod.Post, "/auth/v1/token?grant_type=password", new Dictionary<string, object> { { "email", email.Trim() }, { "password", password } })); }
            catch (Exception ex) { throw new Exception("Could not reach Dotmini ID (" + ex.GetBaseException().Message + "). Check your internet connection."); }
            string raw = await resp.Content.ReadAsStringAsync();
            if (!resp.IsSuccessStatusCode)
            {
                string detail = DJ.ErrorText(raw), lower = detail.ToLowerInvariant();
                if (lower.Contains("invalid login") || lower.Contains("invalid_credentials") || lower.Contains("invalid grant")) throw new Exception("อีเมลหรือรหัสผ่านไม่ถูกต้อง (Invalid login credentials)");
                if (lower.Contains("not confirmed")) throw new Exception("อีเมลนี้ยังไม่ได้ยืนยัน กรุณากดลิงก์ยืนยันในอีเมล แล้วกด Sign In อีกครั้ง");
                if ((int)resp.StatusCode == 429) throw new Exception("ส่งคำขอบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่");
                throw new Exception("Authentication failed (HTTP " + (int)resp.StatusCode + ")" + (detail.Length > 0 ? ": " + detail : "") + ". Please sign in again.");
            }
            var s = Decode(DJ.Obj(raw));
            if (s == null) throw new Exception("Supabase returned an invalid authentication response.");
            Persist(s);
            await RefreshEntitlement();
            return s;
        }

        /// <summary>Creates a Dotmini ID. Returns null when Supabase requires email confirmation first.</summary>
        public static async Task<DotminiSession> SignUp(string email, string password, string displayName)
        {
            await Bootstrap();
            var resp = await DotminiNet.Http.SendAsync(Req(HttpMethod.Post, "/auth/v1/signup", new Dictionary<string, object> {
                { "email", email.Trim() }, { "password", password }, { "data", new Dictionary<string, object> { { "display_name", displayName ?? "" } } } }));
            string raw = await resp.Content.ReadAsStringAsync();
            if (!resp.IsSuccessStatusCode)
            {
                string detail = DJ.ErrorText(raw), lower = detail.ToLowerInvariant();
                if (lower.Contains("password")) throw new Exception("รหัสผ่านไม่ผ่านเกณฑ์ความปลอดภัย กรุณาใช้อย่างน้อย 8 ตัวอักษร ผสมตัวอักษรและตัวเลข");
                if (lower.Contains("already") || lower.Contains("registered")) throw new Exception("อีเมลนี้มีบัญชีอยู่แล้ว กรุณาเข้าสู่ระบบ หรือกด “ลืมรหัสผ่าน”");
                if (lower.Contains("rate limit") || (int)resp.StatusCode == 429) throw new Exception("ส่งคำขอบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่");
                throw new Exception(detail.Length == 0 ? "สร้างบัญชีไม่สำเร็จ กรุณาตรวจสอบอีเมลและรหัสผ่านแล้วลองใหม่" : "สร้างบัญชีไม่สำเร็จ: " + detail);
            }
            var o = DJ.Obj(raw);
            if (DJ.Str(o, "access_token") == null) return null;
            var s = Decode(o);
            if (s == null) throw new Exception("Supabase returned an invalid authentication response.");
            Persist(s);
            await RefreshEntitlement();
            return s;
        }

        public static async Task SendPasswordReset(string email)
        {
            await Bootstrap();
            var resp = await DotminiNet.Http.SendAsync(Req(HttpMethod.Post, "/auth/v1/recover", new Dictionary<string, object> { { "email", email.Trim() } }));
            if (!resp.IsSuccessStatusCode) throw new Exception("ส่งอีเมลรีเซ็ตรหัสผ่านไม่สำเร็จ กรุณารอสักครู่แล้วลองใหม่");
        }

        /// <summary>Registers the microcode:// custom URL scheme in HKCU (no admin required) so web OAuth callbacks return to Windows MicroCode.</summary>
        public static void RegisterUriScheme()
        {
            try
            {
                string exePath = System.Reflection.Assembly.GetEntryAssembly() != null
                    ? System.Reflection.Assembly.GetEntryAssembly().Location
                    : System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName;
                if (string.IsNullOrEmpty(exePath)) return;
                using (var root = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(@"Software\Classes\microcode"))
                {
                    if (root == null) return;
                    root.SetValue("", "URL:MicroCode Protocol");
                    root.SetValue("URL Protocol", "");
                    using (var cmd = root.CreateSubKey(@"shell\open\command"))
                    {
                        if (cmd != null) cmd.SetValue("", "\"" + exePath + "\" \"%1\"");
                    }
                }
            }
            catch { }
        }

        public static bool TryForwardDeepLinkToRunningInstance(string uri)
        {
            if (string.IsNullOrWhiteSpace(uri) || !uri.StartsWith("microcode://", StringComparison.OrdinalIgnoreCase)) return false;
            try
            {
                using (var client = new HttpClient { Timeout = TimeSpan.FromMilliseconds(6000) })
                {
                    var resp = client.PostAsync("http://127.0.0.1:" + LocalBridge.Port + "/v1/auth/deeplink",
                        DJ.Body(new Dictionary<string, object> { { "url", uri } })).Result;
                    return resp.IsSuccessStatusCode;
                }
            }
            catch { return false; }
        }

        public static event Action<string> CollabDeepLinkReceived;

        public static async Task<bool> HandleDeepLink(string rawUri)
        {
            Uri u;
            if (string.IsNullOrWhiteSpace(rawUri) || !Uri.TryCreate(rawUri.Trim(), UriKind.Absolute, out u)) return false;
            if (!string.Equals(u.Scheme, "microcode", StringComparison.OrdinalIgnoreCase)) return false;
            var qp = ParseQueryString(u.Query);
            if (!string.IsNullOrEmpty(u.Fragment))
            {
                var fp = ParseQueryString(u.Fragment.TrimStart('#'));
                foreach (var kv in fp) if (!qp.ContainsKey(kv.Key) || string.IsNullOrEmpty(qp[kv.Key])) qp[kv.Key] = kv.Value;
            }
            string host = (u.Host ?? "").ToLowerInvariant();
            string path = (u.AbsolutePath ?? "").Trim('/').ToLowerInvariant();
            if (host == "collab" || path == "collab")
            {
                if (CollabDeepLinkReceived != null)
                {
                    string raw = rawUri.Trim();
                    DotminiNet.Raise(() => { LocalBridge.BringToFront(); CollabDeepLinkReceived(raw); });
                    return true;
                }
                return false;
            }
            if (host == "colab" || path == "colab")
            {
                string ep; string tk;
                qp.TryGetValue("endpoint", out ep);
                qp.TryGetValue("token", out tk);
                if (!string.IsNullOrEmpty(ep)) Defaults.Set("colabEndpoint", ep);
                if (!string.IsNullOrEmpty(tk)) Defaults.Set("colabToken", Dpapi.Protect(tk));
                Defaults.Flush();
                DotminiNet.Raise(() => { LocalBridge.BringToFront(); if (Changed != null) Changed(); });
                return !string.IsNullOrEmpty(ep);
            }
            if (host == "platform-connect" || path == "platform-connect")
            {
                string code;
                if (qp.TryGetValue("code", out code) && !string.IsNullOrEmpty(code))
                {
                    DotminiNet.Raise(LocalBridge.BringToFront);
                    return await DotminiPlatformKey.RedeemConnectCode(code);
                }
                return false;
            }
            if (host == "auth" || host == "auth-callback" || path == "auth" || path == "auth/callback")
            {
                string token; qp.TryGetValue("token", out token);
                if (string.IsNullOrEmpty(token)) qp.TryGetValue("access_token", out token);
                if (!string.IsNullOrEmpty(token))
                {
                    string rt; qp.TryGetValue("refresh_token", out rt);
                    string expStr; qp.TryGetValue("expires_at", out expStr);
                    double exp = 0; double.TryParse(expStr ?? "", NumberStyles.Float, CultureInfo.InvariantCulture, out exp);
                    string nm; qp.TryGetValue("name", out nm);
                    if (string.IsNullOrEmpty(nm)) qp.TryGetValue("display_name", out nm);
                    DotminiNet.Raise(LocalBridge.BringToFront);
                    bool ok = await IngestWebSession(token, rt, exp, nm);
                    if (ok) DotminiNet.Raise(LocalBridge.BringToFront);
                    return ok;
                }
            }
            return false;
        }

        static Dictionary<string, string> ParseQueryString(string q)
        {
            var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (string.IsNullOrEmpty(q)) return d;
            foreach (var part in q.TrimStart('?', '#').Split('&'))
            {
                int eq = part.IndexOf('=');
                if (eq <= 0) continue;
                try { d[Uri.UnescapeDataString(part.Substring(0, eq))] = Uri.UnescapeDataString(part.Substring(eq + 1).Replace('+', ' ')); }
                catch { }
            }
            return d;
        }

        /// <summary>startBrowserSignIn: opens microcode.dotmini.net auth portal with loopback :18888 AND microcode:// callback fallback.</summary>
        public static bool StartBrowserSignIn(string provider)
        {
            DotminiNet.EnableTls();
            RegisterUriScheme();
            bool bridge = LocalBridge.Start();
            string url = Portal + "/auth.html?source=macapp" + (string.IsNullOrEmpty(provider) ? "" : "&provider=" + Uri.EscapeDataString(provider));
            DotminiNet.OpenExternalUrl(url);
            return bridge;
        }

        static async Task<int> UserStatus(string jwt)
        {
            try
            {
                var r = Req(HttpMethod.Get, "/auth/v1/user", null);
                r.Headers.Authorization = new AuthenticationHeaderValue("Bearer", jwt);
                var resp = await DotminiNet.Http.SendAsync(r);
                return (int)resp.StatusCode;
            }
            catch { return 0; }
        }

        /// <summary>ingestWebSession: verifies a browser-synced JWT with GoTrue (/auth/v1/user) before trusting it.</summary>
        public static async Task<bool> IngestWebSession(string access, string refresh, double expiresAt, string displayName)
        {
            DotminiNet.EnableTls();
            access = (access ?? "").Trim();
            if (access.Split('.').Length < 3) { LastError = "Invalid access token format"; return false; }
            var cur = Session;
            if (cur != null && cur.AccessToken == access && Entitlement.Loaded) return true;
            await Bootstrap();
            Dictionary<string, object> user = null;
            string verifyErr = "";
            foreach (var authOrigin in new[] { BaseUrl, DefaultUrl }.Distinct(StringComparer.OrdinalIgnoreCase))
            {
                try
                {
                    var r = new HttpRequestMessage(HttpMethod.Get, authOrigin.TrimEnd('/') + "/auth/v1/user");
                    r.Headers.TryAddWithoutValidation("apikey", AnonKey);
                    r.Headers.TryAddWithoutValidation("User-Agent", DotminiNet.UserAgent);
                    r.Headers.Authorization = new AuthenticationHeaderValue("Bearer", access);
                    var resp = await DotminiNet.Http.SendAsync(r);
                    string body = await resp.Content.ReadAsStringAsync();
                    if (resp.IsSuccessStatusCode) { user = DJ.Obj(body); break; }
                    verifyErr = "HTTP " + (int)resp.StatusCode + " " + DJ.ErrorText(body);
                }
                catch (Exception ex) { verifyErr = ex.GetBaseException().Message; }
            }
            string id = DJ.Str(user, "id");
            if (string.IsNullOrEmpty(id))
            {
                LastError = "Could not verify web session with Dotmini ID (" + (verifyErr.Length > 0 ? verifyErr : "unknown") + ")";
                Notify();
                return false;
            }
            LastError = "";
            var meta = DJ.Child(user, "user_metadata");
            var s = new DotminiSession
            {
                AccessToken = access, RefreshToken = (refresh ?? "").Trim(), UserId = id, Email = DJ.Str(user, "email") ?? "",
                DisplayName = !string.IsNullOrWhiteSpace(displayName) ? displayName.Trim() : (DJ.Str(meta, "display_name") ?? DJ.Str(meta, "full_name") ?? DJ.Str(meta, "name") ?? ""),
                ExpiresAt = expiresAt > 0 ? expiresAt : JwtExp(access)
            };
            Persist(s);
            await RefreshEntitlement();
            await DotminiCloud.Refresh(true);
            return true;
        }

        /// <summary>refreshAccessTokenIfNeeded: a valid access token, refreshing it with the refresh token when it is about to expire.</summary>
        public static Task<string> AccessToken(bool force)
        {
            var s = Session;
            if (s == null) return Task.FromResult<string>(null);
            if (!force && !s.IsExpired) return Task.FromResult(s.AccessToken);
            lock (_gate)
            {
                if (_refreshing == null || _refreshing.IsCompleted) _refreshing = DoRefresh(s);
                return _refreshing;
            }
        }

        static async Task<string> DoRefresh(DotminiSession existing)
        {
            await Bootstrap();
            if (string.IsNullOrEmpty(existing.RefreshToken))
            {
                int st = await UserStatus(existing.AccessToken);
                if (st == 200) return existing.AccessToken;
                if (st == 401 || st == 403) { Expire("เซสชัน Dotmini Cloud หมดอายุแล้ว กรุณาเข้าสู่ระบบใหม่อีกครั้ง"); return null; }
                return existing.IsExpired ? null : existing.AccessToken;
            }
            for (int round = 0; round < 2; round++)
            {
                string token = existing.RefreshToken;
                HttpResponseMessage resp;
                try { resp = await DotminiNet.Http.SendAsync(Req(HttpMethod.Post, "/auth/v1/token?grant_type=refresh_token", new Dictionary<string, object> { { "refresh_token", token } })); }
                catch { return existing.IsExpired ? null : existing.AccessToken; } // transient: keep the current token
                string raw = await resp.Content.ReadAsStringAsync();
                if (resp.IsSuccessStatusCode)
                {
                    var fresh = Decode(DJ.Obj(raw));
                    if (fresh != null && (existing.UserId.Length == 0 || fresh.UserId == existing.UserId))
                    {
                        if (string.IsNullOrEmpty(fresh.DisplayName)) fresh.DisplayName = existing.DisplayName;
                        Persist(fresh);
                        return fresh.AccessToken;
                    }
                    return existing.IsExpired ? null : existing.AccessToken;
                }
                int code = (int)resp.StatusCode;
                if (code >= 500 || code == 429) return existing.IsExpired ? null : existing.AccessToken;
                // Refresh tokens are single-use: another MicroCode window may already have rotated it — pick that up from disk.
                var disk = DJ.Obj(Dpapi.Unprotect(Convert.ToString(Defaults.PeekDisk(SessionKey))));
                string diskRefresh = DJ.Str(disk, "RefreshToken"), diskAccess = DJ.Str(disk, "AccessToken");
                if (round == 0 && disk != null && DJ.Str(disk, "UserId") == existing.UserId && (diskRefresh != existing.RefreshToken || diskAccess != existing.AccessToken))
                {
                    _session = null; _loaded = false; Defaults.Adopt(SessionKey, Defaults.PeekDisk(SessionKey));
                    var reloaded = Session;
                    if (reloaded != null && !reloaded.IsExpired) return reloaded.AccessToken;
                    if (reloaded != null) { existing = reloaded; continue; }
                }
                break;
            }
            if (await UserStatus(existing.AccessToken) == 200) return existing.AccessToken;
            Expire("เซสชัน Dotmini Cloud หมดอายุแล้ว กรุณาเข้าสู่ระบบใหม่อีกครั้ง");
            return null;
        }

        static void Expire(string reason)
        {
            _session = null; _loaded = true;
            ReauthReason = reason;
            Entitlement = new DotminiEntitlement();
            Defaults.Remove(SessionKey);
            Notify();
        }

        public static void SignOut()
        {
            _session = null; _loaded = true;
            ReauthReason = "";
            Entitlement = new DotminiEntitlement();
            Defaults.Remove(SessionKey);
            Defaults.Flush();
            Notify();
        }

        public static string PortalUrl(string path) { return Portal + (path ?? "/dashboard"); }

        /// <summary>createSubscriptionCheckout / createAICreditTopupCheckout: Beam checkout link (PromptPay QR / card) opened in the browser.</summary>
        public static async Task<string> CreateCheckout(string plan, double? amountTHB)
        {
            var s = Session;
            if (s == null) throw new Exception("กรุณาเข้าสู่ระบบบัญชี MicroCode ก่อนทำการสมัครแพ็กเกจหรือเติมเครดิต");
            string jwt = await AccessToken(false) ?? s.AccessToken;
            var payload = new Dictionary<string, object> {
                { "plan", plan }, { "uid", s.UserId }, { "email", s.Email }, { "fullName", (s.Email ?? "").Split('@')[0] },
                { "billingInterval", "monthly" }, { "paymentMethod", "promptpay" }, { "seats", 1 } };
            if (amountTHB.HasValue && amountTHB.Value > 0) payload["amountTHB"] = amountTHB.Value;
            var r = new HttpRequestMessage(HttpMethod.Post, Portal + "/api/payment/beam-checkout") { Content = DJ.Body(payload) };
            r.Headers.Authorization = new AuthenticationHeaderValue("Bearer", jwt);
            Dictionary<string, object> o;
            try { var resp = await DotminiNet.Http.SendAsync(r); o = DJ.Obj(await resp.Content.ReadAsStringAsync()); }
            catch { throw new Exception("ไม่สามารถติดต่อเซิร์ฟเวอร์ชำระเงินได้ กรุณาลองใหม่อีกครั้ง"); }
            if (o == null) throw new Exception("ไม่สามารถติดต่อเซิร์ฟเวอร์ชำระเงินได้ กรุณาลองใหม่อีกครั้ง");
            string url = DJ.Str(o, "url");
            if (url == null) throw new Exception(DJ.Str(o, "message") ?? DJ.Str(o, "error") ?? "ไม่ได้รับลิงก์ชำระเงินจาก Beam Gateway");
            if (!string.IsNullOrEmpty(DJ.Str(o, "orderRef"))) Defaults.Set("microcode.lastOrderRef", DJ.Str(o, "orderRef"));
            string link = DJ.Str(o, "paymentLinkId") ?? DJ.Str(o, "sessionId");
            if (!string.IsNullOrEmpty(link)) Defaults.Set("microcode.lastPaymentLinkID", link);
            return url;
        }

        /// <summary>verifyLatestPayment: confirms the last checkout and refreshes the plan / credit pool.</summary>
        public static async Task<KeyValuePair<bool, string>> VerifyLatestPayment()
        {
            string orderRef = Defaults.Str("microcode.lastOrderRef", ""), linkId = Defaults.Str("microcode.lastPaymentLinkID", "");
            if (orderRef.Length == 0 && linkId.Length == 0)
            {
                await RefreshEntitlement();
                return new KeyValuePair<bool, string>(false, "ซิงค์สิทธิ์แพ็กเกจและเครดิต Cloud AI เรียบร้อยแล้ว (Plan: " + Entitlement.PlanUpper + " · พร้อมใช้ " + Entitlement.FormattedAvailable + ")");
            }
            var s = Session;
            string jwt = await AccessToken(false) ?? (s != null ? s.AccessToken : "");
            var r = new HttpRequestMessage(HttpMethod.Post, Portal + "/api/payment/verify") { Content = DJ.Body(new Dictionary<string, object> { { "orderRef", orderRef }, { "paymentLinkId", linkId }, { "uid", s != null ? s.UserId : "" }, { "email", s != null ? s.Email : "" } }) };
            r.Headers.Authorization = new AuthenticationHeaderValue("Bearer", jwt);
            Dictionary<string, object> o = null;
            try { var resp = await DotminiNet.Http.SendAsync(r); o = DJ.Obj(await resp.Content.ReadAsStringAsync()); } catch { }
            if (o == null) { await RefreshEntitlement(); return new KeyValuePair<bool, string>(false, "ไม่สามารถตรวจสอบสถานะการชำระเงินได้ในขณะนี้"); }
            object v; bool verified = o.TryGetValue("verified", out v) && v is bool && (bool)v;
            await RefreshEntitlement();
            if (verified)
            {
                Defaults.Remove("microcode.lastOrderRef"); Defaults.Remove("microcode.lastPaymentLinkID");
                bool topup = (o.TryGetValue("isAICreditTopup", out v) && v is bool && (bool)v) || DJ.Str(o, "plan") == "ai_credit_topup";
                return new KeyValuePair<bool, string>(true, topup
                    ? "เติมเครดิต Cloud AI สำเร็จ! เครดิตพร้อมใช้งานรวม " + Entitlement.FormattedAvailable
                    : "ชำระเงินสำเร็จ! เปิดใช้งาน " + (DJ.Str(o, "displayName") ?? DJ.Str(o, "plan") ?? Entitlement.Plan) + " เรียบร้อยแล้ว (เครดิตพร้อมใช้ " + Entitlement.FormattedAvailable + ")");
            }
            return new KeyValuePair<bool, string>(false, DJ.Str(o, "message") ?? "รายการชำระเงินยังรอดำเนินการ (สถานะ: " + (DJ.Str(o, "status") ?? "PENDING") + ")");
        }

        /// <summary>refreshEntitlement: plan + AI credit pool from /api/subscription/status, falling back to Supabase public.users.</summary>
        public static async Task RefreshEntitlement()
        {
            var s = Session;
            if (s == null) return;
            string jwt = await AccessToken(false);
            s = Session;
            if (s == null || jwt == null) return;
            var e = new DotminiEntitlement();
            bool got = false;
            try
            {
                var r = new HttpRequestMessage(HttpMethod.Get, Portal + "/api/subscription/status?uid=" + Uri.EscapeDataString(s.UserId) + "&email=" + Uri.EscapeDataString(s.Email ?? ""));
                r.Headers.Authorization = new AuthenticationHeaderValue("Bearer", jwt);
                r.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
                var resp = await DotminiNet.Http.SendAsync(r);
                var o = resp.IsSuccessStatusCode ? DJ.Obj(await resp.Content.ReadAsStringAsync()) : null;
                if (o != null && DJ.Str(o, "plan") != null)
                {
                    e.Plan = DJ.Str(o, "plan"); e.Role = DJ.Str(o, "role") ?? "user";
                    e.Quota = (int)(DJ.Num(o, "ai_quota") ?? 0); e.Used = (int)(DJ.Num(o, "ai_used") ?? 0);
                    e.CreditLimitTHB = DJ.Num(o, "ai_credit_limit_thb") ?? 0; e.CreditUsedTHB = DJ.Num(o, "ai_credit_used_thb") ?? 0;
                    e.CreditRemainingTHB = DJ.Num(o, "ai_credit_remaining_thb") ?? Math.Max(0, e.CreditLimitTHB - e.CreditUsedTHB);
                    e.TopupTHB = DJ.Num(o, "ai_topup_balance_thb") ?? 0;
                    e.TotalAvailableTHB = DJ.Num(o, "ai_total_available_thb") ?? (e.CreditRemainingTHB + e.TopupTHB);
                    e.MarginPct = DJ.Num(o, "ai_margin_pct") ?? 20; e.TotalTokens = (long)(DJ.Num(o, "ai_total_tokens") ?? 0);
                    e.BillingMode = DJ.Str(o, "billing_mode") ?? "";
                    got = true;
                }
            }
            catch { }
            if (!got)
            {
                try
                {
                    var r = Req(HttpMethod.Get, "/rest/v1/users?select=role,plan,ai_quota,ai_used&id=eq." + Uri.EscapeDataString(s.UserId), null);
                    r.Headers.Authorization = new AuthenticationHeaderValue("Bearer", jwt);
                    var resp = await DotminiNet.Http.SendAsync(r);
                    if (resp.IsSuccessStatusCode)
                    {
                        var rows = DJ.S.Deserialize<System.Collections.ArrayList>(await resp.Content.ReadAsStringAsync());
                        var row = rows != null && rows.Count > 0 ? rows[0] as Dictionary<string, object> : null;
                        if (row != null)
                        {
                            e.Plan = DJ.Str(row, "plan") ?? ""; e.Role = DJ.Str(row, "role") ?? "user";
                            e.Quota = (int)(DJ.Num(row, "ai_quota") ?? 0); e.Used = (int)(DJ.Num(row, "ai_used") ?? 0);
                            got = true;
                        }
                    }
                }
                catch { }
            }
            if (got) { e.Loaded = true; Entitlement = e; Notify(); }
        }
    }

    // ── Dotmini Platform key ───────────────────────────────────────────────────

    public static class DotminiPlatformKey
    {
        public const string PlatformOrigin = "https://platform.dotmini.net";
        static readonly string[] Origins = { "https://platform.dotmini.net", "https://api.dotmini.net", "https://microcode.dotmini.net" };
        const string KeyName = "dotmini_platform_key_v1";
        public static event Action Changed;
        public static string Message = "";
        public static bool Validating, Provisioning;
        public static string Email = "", KeyId = "", OmniPlan = "", MicroCodePlan = "";
        public static double? AvailableTHB, BalanceUSD;
        public static int? DailyUsed, DailyLimit;

        static void Notify() { DotminiNet.Raise(Changed); }
        static string DeviceName { get { return string.IsNullOrWhiteSpace(Environment.MachineName) ? "Windows PC" : Environment.MachineName; } }

        public static string Key { get { var k = Dpapi.Unprotect(Defaults.Str(KeyName, null)); return string.IsNullOrWhiteSpace(k) ? null : k.Trim(); } }
        public static bool IsConfigured { get { return Key != null; } }
        public static string Masked
        {
            get
            {
                var k = Key ?? "";
                if (k.Length <= 14) return k.Length == 0 ? "Not connected" : "••••••••";
                return k.Substring(0, 16) + "••••" + k.Substring(k.Length - 4);
            }
        }

        public static bool Save(string raw)
        {
            string v = (raw ?? "").Trim();
            if (!(v.StartsWith("sk-dotmini-live-") || v.StartsWith("sk-dotmini-ent-") || v.StartsWith("mci-live-")))
            {
                Message = "Use an official Dotmini Platform key (sk-dotmini-live-… / sk-dotmini-ent-… / mci-live-…).";
                Notify();
                return false;
            }
            Defaults.Set(KeyName, Dpapi.Protect(v));
            Defaults.Flush();
            Message = v.StartsWith("sk-dotmini-ent-") ? "Dotmini Enterprise key saved securely (Windows DPAPI)." : "Dotmini Platform key saved securely (Windows DPAPI).";
            Notify();
            return true;
        }

        public static void Remove()
        {
            Defaults.Remove(KeyName);
            Defaults.Flush();
            Email = ""; KeyId = ""; OmniPlan = ""; MicroCodePlan = "";
            AvailableTHB = null; BalanceUSD = null; DailyUsed = null; DailyLimit = null;
            Message = "Platform key removed from this PC.";
            Notify();
        }

        static HttpRequestMessage Req(HttpMethod m, string url, object body, string bearer)
        {
            var r = new HttpRequestMessage(m, url);
            if (bearer != null) r.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            r.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            r.Headers.TryAddWithoutValidation("X-Dotmini-Client", "microcode");
            r.Headers.TryAddWithoutValidation("User-Agent", DotminiNet.UserAgent);
            if (body != null) r.Content = DJ.Body(body);
            return r;
        }

        /// <summary>validate(): /api/v1/platform/me → unified plans and shared AI credit.</summary>
        public static async Task<bool> Validate()
        {
            string key = Key;
            if (key == null) { Message = "Add or auto-connect a Dotmini Platform key first."; Notify(); return false; }
            Validating = true; Notify();
            int? lastCode = null; string lastErr = null;
            try
            {
                foreach (var origin in Origins)
                {
                    try
                    {
                        var resp = await DotminiNet.Http.SendAsync(Req(HttpMethod.Get, origin + "/api/v1/platform/me", null, key));
                        lastCode = (int)resp.StatusCode;
                        var o = DJ.Obj(await resp.Content.ReadAsStringAsync());
                        if (resp.IsSuccessStatusCode && o != null) { Apply(o); return true; }
                        if (lastCode == 401 || lastCode == 403)
                        {
                            Message = "Dotmini Platform rejected this key. Use 1-Click Auto-Connect or create a new key on platform.dotmini.net.";
                            return false;
                        }
                    }
                    catch (Exception ex) { lastErr = ex.GetBaseException().Message; }
                }
                Message = lastCode.HasValue ? "Platform validation failed (HTTP " + lastCode + ")." : lastErr != null ? "Could not reach platform.dotmini.net: " + lastErr : "Could not validate Platform key.";
                return false;
            }
            finally { Validating = false; Notify(); }
        }

        static void Apply(Dictionary<string, object> o)
        {
            var user = DJ.Child(o, "user");
            if (DJ.Str(user, "email") != null) Email = DJ.Str(user, "email");
            if (DJ.Str(o, "key_id") != null) KeyId = DJ.Str(o, "key_id");
            var omni = DJ.Child(o, "omni_ai"); if (DJ.Str(omni, "plan") != null) OmniPlan = DJ.Str(omni, "plan").ToUpperInvariant();
            var mc = DJ.Child(o, "microcode"); if (DJ.Str(mc, "plan") != null) MicroCodePlan = DJ.Str(mc, "plan").ToUpperInvariant();
            var credits = DJ.Child(o, "credits");
            if (credits != null) { AvailableTHB = DJ.Num(credits, "available_thb"); BalanceUSD = DJ.Num(credits, "balance_usd"); }
            var q = DJ.Child(o, "quotas");
            if (q != null) { var u = DJ.Num(q, "daily_used"); var l = DJ.Num(q, "daily_limit"); DailyUsed = u.HasValue ? (int?)(int)u.Value : null; DailyLimit = l.HasValue ? (int?)(int)l.Value : null; }
            string mcl = MicroCodePlan.Length == 0 ? "FREE" : MicroCodePlan, ol = OmniPlan.Length == 0 ? "FREE" : OmniPlan;
            Message = AvailableTHB.HasValue
                ? string.Format(CultureInfo.InvariantCulture, "Connected to Dotmini Platform (MicroCode: {0} · Omni AI: {1} · Shared Credit: ฿{2:0.00}).", mcl, ol, AvailableTHB.Value)
                : "Connected to Dotmini Platform (MicroCode: " + mcl + " · Omni AI: " + ol + ").";
        }

        /// <summary>redeemConnectCode: single-use otc_… code from platform.dotmini.net → provisioned key.</summary>
        public static async Task<bool> RedeemConnectCode(string raw)
        {
            string code = (raw ?? "").Trim();
            if (!code.StartsWith("otc_") || code.Length < 20) { Message = "Invalid 1-Click Connect code."; Notify(); return false; }
            Provisioning = true;
            Message = "Completing secure 1-Click Connect with platform.dotmini.net…";
            Notify();
            try
            {
                var payload = new Dictionary<string, object> { { "code", code }, { "device_name", DeviceName }, { "app_name", "MicroCode" } };
                foreach (var origin in Origins)
                {
                    try
                    {
                        var resp = await DotminiNet.Http.SendAsync(Req(HttpMethod.Post, origin + "/api/platform/connect/exchange", payload, null));
                        var o = DJ.Obj(await resp.Content.ReadAsStringAsync()) ?? new Dictionary<string, object>();
                        int st = (int)resp.StatusCode;
                        if (resp.IsSuccessStatusCode && DJ.Str(o, "api_key") != null && Save(DJ.Str(o, "api_key")))
                        {
                            if (!string.IsNullOrEmpty(DJ.Str(o, "email"))) Email = DJ.Str(o, "email");
                            if (DJ.Str(o, "key_id") != null) KeyId = DJ.Str(o, "key_id");
                            Provisioning = false;
                            await Validate();
                            return true;
                        }
                        if (st == 400 || st == 401 || st == 404 || st == 410) { Message = "1-Click Connect failed: " + (DJ.Str(o, "error") ?? "Connect code expired or already used."); return false; }
                    }
                    catch { }
                }
                Message = "Could not exchange 1-Click Connect code with platform.dotmini.net.";
                return false;
            }
            finally { Provisioning = false; Notify(); }
        }

        /// <summary>autoConnectFromSignedInAccount: provision a dedicated key from the signed-in Dotmini ID.</summary>
        public static async Task<bool> AutoConnect()
        {
            string jwt = await DotminiAuth.AccessToken(false);
            if (string.IsNullOrEmpty(jwt)) { Message = "Sign in to your Dotmini account above first, or click Connect on platform.dotmini.net."; Notify(); return false; }
            Provisioning = true;
            Message = "Provisioning encrypted Platform key for " + DeviceName + "…";
            Notify();
            try
            {
                var payload = new Dictionary<string, object> { { "name", "MicroCode · " + DeviceName }, { "prefix", "sk-dotmini-live" } };
                foreach (var origin in Origins)
                {
                    try
                    {
                        var resp = await DotminiNet.Http.SendAsync(Req(HttpMethod.Post, origin + "/api/platform/keys/create", payload, jwt));
                        var o = DJ.Obj(await resp.Content.ReadAsStringAsync()) ?? new Dictionary<string, object>();
                        int st = (int)resp.StatusCode;
                        string created = DJ.Str(o, "api_key") ?? DJ.Str(o, "key");
                        if (resp.IsSuccessStatusCode && created != null && Save(created))
                        {
                            if (DJ.Str(o, "key_id") != null) KeyId = DJ.Str(o, "key_id");
                            Provisioning = false;
                            await Validate();
                            return true;
                        }
                        if (st == 401 || st == 403) { Message = "Could not create Platform key: " + (DJ.Str(o, "error") ?? "Session unauthorized."); return false; }
                    }
                    catch { }
                }
                Message = "Could not reach platform.dotmini.net to auto-provision key.";
                return false;
            }
            finally { Provisioning = false; Notify(); }
        }
    }

    // ── Dotmini Cloud model gateway (microcode.dotmini.net/v1, OpenAI-compatible) ────────────

    public class CloudModel
    {
        public string Id, Name, Provider, Tier;
        public double InTHB, OutTHB, InUSD, OutUSD;
        static string Fmt(double v) { return "฿" + v.ToString(v >= 100 ? "0" : v >= 10 ? "0.0" : "0.00", CultureInfo.InvariantCulture); }
        /// <summary>cloudTHBRateSummary: "฿131/฿657 · 1M"</summary>
        public string Rate
        {
            get
            {
                double i = InTHB, o = OutTHB;
                if (i <= 0 && o <= 0) { i = InUSD * 36.5 * 1.2; o = OutUSD * 36.5 * 1.2; }
                return Fmt(i) + "/" + Fmt(o) + " · 1M";
            }
        }
    }

    public static class DotminiCloud
    {
        public const string DefaultProxy = "https://microcode.dotmini.net/v1";
        public static string ProxyURL { get { var c = Defaults.Str("dotminiProxyURL", null); return string.IsNullOrWhiteSpace(c) ? DefaultProxy : c.Trim().TrimEnd('/'); } }
        public static List<CloudModel> Models = new List<CloudModel>();
        public static string Source = "";
        public static string LastError = "";
        public static bool Refreshing;
        public static event Action Changed;
        static DateTime _lastRefresh = DateTime.MinValue;
        static bool _cacheLoaded;
        static string CachePath { get { return Path.Combine(Defaults.Dir, "cloud-models.json"); } }

        public static bool HasCredential { get { return DotminiPlatformKey.IsConfigured || DotminiAuth.SignedIn; } }

        /// <summary>Platform key first (one credential across Omni AI + MicroCode), else the Dotmini ID session token.</summary>
        public static async Task<string> Token(bool force)
        {
            var k = DotminiPlatformKey.Key;
            if (k != null) return k;
            return await DotminiAuth.AccessToken(force);
        }

        public static void ApplyHeaders(HttpRequestMessage req, string token, string feature)
        {
            req.Headers.TryAddWithoutValidation("User-Agent", DotminiNet.UserAgent);
            req.Headers.TryAddWithoutValidation("X-MicroCode-Client", "windows");
            req.Headers.TryAddWithoutValidation("X-MicroCode-Feature", feature ?? "Agent");
            req.Headers.TryAddWithoutValidation("X-MicroCode-AI-Provider", "Dotmini Cloud");
            string license = AIConfig.KeyFor("license");
            if (!string.IsNullOrEmpty(license)) req.Headers.TryAddWithoutValidation("X-Dotmini-License", license);
            if (!string.IsNullOrEmpty(token)) req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }

        public static CloudModel Find(string id)
        {
            EnsureCache();
            return Models.FirstOrDefault(m => string.Equals(m.Id, id, StringComparison.OrdinalIgnoreCase));
        }

        public static string DefaultModelId { get { EnsureCache(); return Models.Count > 0 ? Models[0].Id : "claude-sonnet-5-5"; } }

        static readonly string[] PreferredOrder = { "openai", "gemini", "anthropic", "deepseek", "glm", "qwen", "grok", "typhoon", "openrouter", "omni" };
        public static List<KeyValuePair<string, List<CloudModel>>> ByProvider()
        {
            EnsureCache();
            return Models.GroupBy(m => m.Provider)
                .OrderBy(g => { int i = Array.IndexOf(PreferredOrder, g.Key); return i < 0 ? 999 : i; }).ThenBy(g => g.Key)
                .Select(g => new KeyValuePair<string, List<CloudModel>>(g.Key, g.ToList())).ToList();
        }

        public static string ProviderName(string p)
        {
            switch ((p ?? "").ToLowerInvariant())
            {
                case "gemini": case "google": return "Google Gemini";
                case "openai": return "OpenAI";
                case "anthropic": return "Anthropic";
                case "omni": return "Dotmini Cloud";
                case "deepseek": return "DeepSeek";
                case "openrouter": return "OpenRouter";
                case "glm": return "Zhipu GLM";
                case "qwen": return "Qwen";
                case "grok": return "xAI Grok";
                case "mistral": return "Mistral";
                case "kimi": return "Kimi";
                default: return string.IsNullOrEmpty(p) ? "Other" : char.ToUpperInvariant(p[0]) + p.Substring(1);
            }
        }

        static void EnsureCache()
        {
            if (_cacheLoaded) return;
            _cacheLoaded = true;
            try
            {
                if (!File.Exists(CachePath)) return;
                var list = Parse(Defaults.ReadShared(CachePath));
                if (list.Count > 0 && Models.Count == 0) { Models = list; Source = Summary(list); }
            }
            catch { }
        }

        static string Summary(List<CloudModel> list) { return list.Count + " live models · " + list.Select(m => m.Provider).Distinct().Count() + " providers"; }

        static DateTime _lastAttempt = DateTime.MinValue;

        /// <summary>Kicks a background refresh when the catalog is empty or older than 30 minutes — at most once a minute,
        /// so views that call this while rendering can never start a refresh loop.</summary>
        public static void EnsureFresh()
        {
            EnsureCache();
            if (Refreshing || (DateTime.Now - _lastAttempt).TotalSeconds < 60) return;
            if (Models.Count == 0 || (DateTime.Now - _lastRefresh).TotalMinutes > 30) { var _ = Refresh(false); }
        }

        static Task _inflight;

        /// <summary>refreshCloudProxyModels: GET {proxy}/models (Bearer when signed in), with api.dotmini.net fallback.</summary>
        public static Task Refresh(bool force)
        {
            if (_inflight != null && !_inflight.IsCompleted) return _inflight;
            _inflight = RefreshCore(force);
            return _inflight;
        }

        static async Task RefreshCore(bool force)
        {
            DotminiNet.EnableTls();
            Refreshing = true;
            _lastAttempt = DateTime.Now;
            DotminiNet.Raise(Changed);
            try
            {
                string token = null;
                try { token = await Token(false); } catch { }
                string lastErr = "";
                foreach (var baseUrl in new[] { ProxyURL, "https://api.dotmini.net/v1" }.Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    try
                    {
                        var req = new HttpRequestMessage(HttpMethod.Get, baseUrl.TrimEnd('/') + "/models" + (force ? "?refresh=1" : ""));
                        if (!string.IsNullOrEmpty(token)) req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
                        req.Headers.TryAddWithoutValidation("User-Agent", DotminiNet.UserAgent);
                        req.Headers.TryAddWithoutValidation("X-MicroCode-Client", "windows");
                        using (var cts = new CancellationTokenSource(10000))
                        {
                            var resp = await DotminiNet.Http.SendAsync(req, cts.Token);
                            string raw = await resp.Content.ReadAsStringAsync();
                            if (!resp.IsSuccessStatusCode) { lastErr = "HTTP " + (int)resp.StatusCode + " " + DJ.ErrorText(raw); continue; }
                            var list = Parse(raw);
                            if (list.Count == 0) { lastErr = "Empty model catalog returned"; continue; }
                            Models = list;
                            Source = Summary(list);
                            LastError = "";
                            _lastRefresh = DateTime.Now;
                            try { Defaults.WriteAtomic(CachePath, raw); } catch { }
                            return;
                        }
                    }
                    catch (Exception ex) { lastErr = ex.GetBaseException().Message; }
                }
                if (lastErr.Length > 0) LastError = lastErr;
            }
            finally { Refreshing = false; DotminiNet.Raise(Changed); }
        }

        /// <summary>Live end-to-end diagnostic probe (port of DotminiCloudProbe.swift).</summary>
        public static async Task<List<string>> RunProbe()
        {
            DotminiNet.EnableTls();
            var lines = new List<string>();
            foreach (var host in new[] { "https://microcode.dotmini.net/v1/models", "https://api.dotmini.net/v1/models" })
            {
                try
                {
                    var req = new HttpRequestMessage(HttpMethod.Get, host);
                    string tok = await Token(false);
                    if (!string.IsNullOrEmpty(tok)) req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tok);
                    var resp = await DotminiNet.Http.SendAsync(req);
                    string raw = await resp.Content.ReadAsStringAsync();
                    var list = Parse(raw);
                    lines.Add(((int)resp.StatusCode == 200 && list.Count > 0 ? "PASS  " : "FAIL  ") + host + " -> HTTP " + (int)resp.StatusCode + " (" + list.Count + " models)");
                }
                catch (Exception ex) { lines.Add("FAIL  " + host + " -> " + ex.GetBaseException().Message); }
            }
            try
            {
                var cfg = DJ.Obj(await DotminiNet.Http.GetStringAsync("https://microcode.dotmini.net/api/microcode/auth-config"));
                lines.Add((cfg != null && DJ.Str(cfg, "url") != null ? "PASS  " : "FAIL  ") + "auth-config -> " + (DJ.Str(cfg, "url") ?? "missing"));
            }
            catch (Exception ex) { lines.Add("FAIL  auth-config -> " + ex.GetBaseException().Message); }

            if (DotminiPlatformKey.IsConfigured)
            {
                bool pkOk = await DotminiPlatformKey.Validate();
                lines.Add((pkOk ? "PASS  " : "FAIL  ") + "Platform Key -> " + DotminiPlatformKey.Message);
            }
            else if (DotminiAuth.SignedIn)
            {
                string tok = await DotminiAuth.AccessToken(true);
                await DotminiAuth.RefreshEntitlement();
                lines.Add((!string.IsNullOrEmpty(tok) ? "PASS  " : "FAIL  ") + "Dotmini ID (" + DotminiAuth.Session.Email + ") -> " + DotminiAuth.Entitlement.PlanUpper + " (" + DotminiAuth.Entitlement.FormattedAvailable + ")");
            }
            else
            {
                lines.Add("INFO  Not signed in and no Platform Key configured yet.");
            }
            return lines;
        }

        public static List<CloudModel> Parse(string raw)
        {
            var result = new List<CloudModel>();
            System.Collections.ArrayList rows = null;
            try
            {
                var top = DJ.S.DeserializeObject(raw);
                rows = DJ.AsList(top);
                var d = top as Dictionary<string, object>;
                if (rows == null && d != null) rows = DJ.Arr(d, "data") ?? DJ.Arr(d, "models");
            }
            catch { }
            if (rows == null) return result;
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var r in rows)
            {
                var o = r as Dictionary<string, object>;
                string id = (DJ.Str(o, "id") ?? DJ.Str(o, "name") ?? "").Replace("models/", "");
                if (id.Length == 0 || !IsChatModel(id) || !seen.Add(id)) continue;
                result.Add(new CloudModel
                {
                    Id = id, Name = PreferredName(id, DJ.Str(o, "name")), Provider = InferProvider(id, DJ.Str(o, "owned_by")), Tier = DJ.Str(o, "tier") ?? "",
                    InTHB = DJ.Num(o, "input_thb_per_1m") ?? 0, OutTHB = DJ.Num(o, "output_thb_per_1m") ?? 0,
                    InUSD = DJ.Num(o, "input_usd_per_1m") ?? 0, OutUSD = DJ.Num(o, "output_usd_per_1m") ?? 0
                });
            }
            return result.OrderByDescending(m => PriorityScore(m.Id)).ThenBy(m => m.Id).ToList();
        }

        static bool IsChatModel(string id)
        {
            string l = id.ToLowerInvariant();
            return !new[] { "embedding", "moderation", "tts", "whisper", "audio", "transcribe", "dall-e", "ocr", "asr" }.Any(x => l.Contains(x));
        }

        static string InferProvider(string id, string owner)
        {
            string o = (owner ?? "").ToLowerInvariant();
            if (o.Contains("deepseek")) return "deepseek";
            if (o.Contains("gemini") || o.Contains("google")) return "gemini";
            if (o.Contains("anthropic") || o.Contains("claude")) return "anthropic";
            if (o.Contains("openai")) return "openai";
            if (o.Contains("glm") || o.Contains("zhipu")) return "glm";
            if (o.Length > 0 && o != "system") return o;
            string l = id.ToLowerInvariant();
            if (l.Contains("claude")) return "anthropic";
            if (l.Contains("gemini") || l.Contains("gemma")) return "gemini";
            if (l.StartsWith("gpt") || Regex.IsMatch(l, "^o[0-9]")) return "openai";
            if (l.Contains("deepseek")) return "deepseek";
            if (l.Contains("glm")) return "glm";
            if (l.Contains("omni")) return "omni";
            return "omni";
        }

        static string PreferredName(string id, string serverName)
        {
            string sn = (serverName ?? "").Trim();
            if (sn.Length > 0)
            {
                string l = sn.ToLowerInvariant();
                bool autoSplit = l.StartsWith("gpt ") || l.StartsWith("glm ") || l.StartsWith("deepseek ") || Regex.IsMatch(sn, @"\b202[4-9]\s+\d{2}\s+\d{2}\b");
                if (!autoSplit) return sn;
            }
            return AIConfig.FormatModelName(id);
        }

        // universalModelPriorityScore / claudeModelSortScore / geminiModelSortScore (AIModelCatalog.swift)
        public static int PriorityScore(string id)
        {
            string l = id.ToLowerInvariant();
            int datePenalty = Regex.IsMatch(l, @"-\d{4}-\d{2}-\d{2}$") ? 80 : 0;
            if (l.Contains("gemini") || l.Contains("gemma")) return GeminiScore(l) + 100 - datePenalty;
            if (l.Contains("claude")) return ClaudeScore(l) - datePenalty;
            int score = 2000;
            if (l.Contains("gpt-6.1") || l.Contains("gpt-6-1")) score = 4450;
            else if (l.Contains("gpt-6")) score = 4400;
            else if (l.Contains("gpt-5.6")) score = 4250;
            else if (l.Contains("gpt-5.5")) score = 4200;
            else if (l.Contains("gpt-5.4")) score = 4150;
            else if (l.Contains("gpt-5.3")) score = 4120;
            else if (l.Contains("gpt-5.2")) score = 4090;
            else if (l.Contains("gpt-5.1")) score = 4060;
            else if (l.Contains("gpt-5")) score = 4020;
            else if (l.StartsWith("o3") || l.StartsWith("o4")) score = 3980;
            else if (l.Contains("gpt-4.1")) score = 3850;
            else if (l.Contains("gpt-4o")) score = 3800;
            else if (l.Contains("deepseek-v4")) score = 4350;
            else if (l.Contains("deepseek-r") || l.Contains("deepseek-reasoner")) score = 3900;
            else if (l.Contains("deepseek")) score = 3700;
            else if (l.Contains("glm-5.3")) score = 4150;
            else if (l.Contains("glm-5.2")) score = 4100;
            else if (l.Contains("glm-5.1")) score = 4050;
            else if (l.Contains("glm-5")) score = 3950;
            else if (l.Contains("glm-4.7")) score = 3820;
            else if (l.Contains("glm-4.6")) score = 3780;
            else if (l.Contains("glm-4.5")) score = 3740;
            else if (l.Contains("omni-o1x")) score = 4300;
            if (l.Contains("-pro")) score += 20;
            else if (l.Contains("-mini")) score -= 15;
            else if (l.Contains("-nano")) score -= 25;
            return score - datePenalty;
        }

        static int GeminiScore(string l)
        {
            int s = 0;
            if (l.Contains("gemini-5")) s += 6000;
            else if (l.Contains("gemini-4")) s += 5000;
            else if (l.Contains("gemini-3.8") || l.Contains("gemini-3-8")) s += 4800;
            else if (l.Contains("gemini-3.7") || l.Contains("gemini-3-7")) s += 4700;
            else if (l.Contains("gemini-3.6") || l.Contains("gemini-3-6")) s += 4600;
            else if (l.Contains("gemini-3.5") || l.Contains("gemini-3-5")) s += 4500;
            else if (l.Contains("gemini-3.1") || l.Contains("gemini-3-1")) s += 4100;
            else if (l.Contains("gemini-3")) s += 4000;
            else if (l.Contains("gemini-2.5") || l.Contains("gemini-2-5")) s += 2500;
            else if (l.Contains("gemini-2.0") || l.Contains("gemini-2-0")) s += 2000;
            else if (l.Contains("gemini-1.5")) s += 1500;
            bool element = l.Contains("argon") || l.Contains("hydrogen") || l.Contains("carbon");
            if (element && !l.Contains("low") && !l.Contains("medium") && !l.Contains("high")) s += 400;
            else if (l.Contains("pro")) s += 350;
            else if (l.Contains("tiered") || l.Contains("high")) s += 320;
            else if (l.Contains("flash") && !l.Contains("lite")) s += 280;
            else if (l.Contains("lite")) s += 220;
            else if (element) s += 200;
            return s;
        }

        static int ClaudeScore(string l)
        {
            int s = 0;
            if (l.Contains("5-5") || l.Contains("5.5")) s += 5500;
            else if (l.Contains("5-2") || l.Contains("5.2")) s += 5200;
            else if (l.Contains("5-1") || l.Contains("5.1")) s += 5100;
            else if (l.Contains("5-0") || l.Contains("5.0") || l.Contains("claude-5") || l.EndsWith("-5")) s += 5000;
            else if (l.Contains("4-8") || l.Contains("4.8")) s += 4800;
            else if (l.Contains("4-7") || l.Contains("4.7")) s += 4700;
            else if (l.Contains("4-6") || l.Contains("4.6")) s += 4600;
            else if (l.Contains("4-5") || l.Contains("4.5")) s += 4500;
            else if (l.Contains("4-1") || l.Contains("4.1")) s += 4100;
            else if (l.Contains("4-0") || l.Contains("4.0") || l.Contains("claude-4")) s += 4000;
            else if (l.Contains("3-7") || l.Contains("3.7")) s += 3700;
            else if (l.Contains("3-5") || l.Contains("3.5")) s += 3500;
            else if (l.Contains("3-")) s += 3000;
            if (l.Contains("opus")) s += 400;
            else if (l.Contains("sonnet")) s += 300;
            else if (l.Contains("fable")) s += 250;
            else if (l.Contains("haiku")) s += 150;
            if (l.Contains("high")) s += 35;
            else if (l.Contains("medium")) s += 25;
            else if (l.Contains("low")) s += 10;
            else s += 30;
            return s;
        }
    }

    // ── Loopback bridge: 127.0.0.1:18888 (MCPServer.startLocalHttpBridge, auth endpoints only) ─────────────

    public static class LocalBridge
    {
        public const int Port = 18888;
        static TcpListener _listener;
        public static string Error;
        public static Func<string, string> McpRpcHandler;
        public static bool Running { get { return _listener != null; } }

        public static bool Start()
        {
            if (_listener != null) return true;
            try
            {
                var l = new TcpListener(IPAddress.Loopback, Port); // loopback only: never reachable from the LAN
                l.Start();
                _listener = l;
                Error = null;
                Task.Run(() => AcceptLoop(l));
                return true;
            }
            catch (Exception ex) { Error = ex.Message; return false; }
        }

        static async Task AcceptLoop(TcpListener l)
        {
            while (true)
            {
                TcpClient c;
                try { c = await l.AcceptTcpClientAsync(); } catch { return; }
                var _ = Task.Run(() => Handle(c));
            }
        }

        static bool AllowedOrigin(string origin)
        {
            Uri u;
            if (!Uri.TryCreate(origin, UriKind.Absolute, out u) || (u.AbsolutePath != "/" && u.AbsolutePath.Length > 0)) return false;
            string host = u.Host.ToLowerInvariant();
            if (host == "localhost" || host == "127.0.0.1" || host == "[::1]" || host == "::1") return u.Scheme == "http" || u.Scheme == "https";
            return u.Scheme == "https" && (host == "dotmini.net" || host.EndsWith(".dotmini.net"));
        }

        /// <summary>Defeats DNS rebinding: a rebinding page reaches 127.0.0.1 but still carries its own hostname in Host.</summary>
        static bool LoopbackHost(string hostHeader)
        {
            string raw = (hostHeader ?? "").Trim().ToLowerInvariant();
            if (raw.Length == 0) return true;
            string host = raw.StartsWith("[") ? raw.Substring(1).Split(']')[0] : raw.Split(':')[0];
            return host == "localhost" || host == "127.0.0.1" || host == "::1";
        }

        static async Task Handle(TcpClient c)
        {
            using (c)
            {
                try
                {
                    var ns = c.GetStream();
                    ns.ReadTimeout = 5000;
                    var buf = new MemoryStream();
                    var tmp = new byte[8192];
                    int headerEnd = -1;
                    while (headerEnd < 0 && buf.Length < 65536)
                    {
                        int n = await ns.ReadAsync(tmp, 0, tmp.Length);
                        if (n <= 0) break;
                        buf.Write(tmp, 0, n);
                        headerEnd = Find(buf.GetBuffer(), (int)buf.Length);
                    }
                    if (headerEnd < 0) return;
                    var all = buf.ToArray();
                    string head = Encoding.ASCII.GetString(all, 0, headerEnd);
                    var lines = head.Split(new[] { "\r\n" }, StringSplitOptions.None);
                    var first = lines[0].Split(' ');
                    if (first.Length < 2) return;
                    string method = first[0].ToUpperInvariant(), path = first[1];
                    var h = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    foreach (var line in lines.Skip(1)) { int i = line.IndexOf(':'); if (i > 0) h[line.Substring(0, i).Trim()] = line.Substring(i + 1).Trim(); }
                    int len = 0; string cl; if (h.TryGetValue("Content-Length", out cl)) int.TryParse(cl, out len);
                    len = Math.Min(len, 1 << 20);
                    int bodyStart = headerEnd + 4;
                    var body = new MemoryStream();
                    body.Write(all, bodyStart, all.Length - bodyStart);
                    while (body.Length < len) { int n = await ns.ReadAsync(tmp, 0, tmp.Length); if (n <= 0) break; body.Write(tmp, 0, n); }
                    string bodyText = Encoding.UTF8.GetString(body.ToArray());
                    string origin; h.TryGetValue("Origin", out origin);
                    string hostHeader; h.TryGetValue("Host", out hostHeader);

                    string status, json, extra = "";
                    if (!LoopbackHost(hostHeader)) { status = "403 Forbidden"; json = "{\"error\": \"Forbidden host\"}"; origin = null; }
                    else if (origin != null && !AllowedOrigin(origin)) { status = "403 Forbidden"; json = "{\"error\": \"Origin not allowed\"}"; origin = null; }
                    else if (method == "OPTIONS")
                    {
                        status = "200 OK"; json = "";
                        string reqHdrs;
                        string allowHdrs = (h.TryGetValue("Access-Control-Request-Headers", out reqHdrs) && !string.IsNullOrWhiteSpace(reqHdrs))
                            ? reqHdrs
                            : "Content-Type, Authorization, X-Dotmini-Bridge, Accept, X-Requested-With";
                        extra = "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: " + allowHdrs + "\r\nAccess-Control-Max-Age: 600\r\n";
                        if (origin == null) extra += "Access-Control-Allow-Private-Network: true\r\n";
                    }
                    else if (method == "POST" && path.StartsWith("/v1/auth/sync"))
                    {
                        var o = DJ.Obj(bodyText) ?? new Dictionary<string, object>();
                        if ((DJ.Str(o, "action") ?? "sync").ToLowerInvariant() == "signout")
                        {
                            DotminiAuth.SignOut();
                            status = "200 OK"; json = "{\"success\": true, \"authenticated\": false}";
                        }
                        else
                        {
                            string access = (DJ.Str(o, "access_token") ?? DJ.Str(o, "token") ?? "").Trim();
                            bool ok = await DotminiAuth.IngestWebSession(access, DJ.Str(o, "refresh_token"), DJ.Num(o, "expires_at") ?? 0, DJ.Str(o, "display_name") ?? DJ.Str(o, "name"));
                            var s = DotminiAuth.Session; var e = DotminiAuth.Entitlement;
                            json = DJ.Ser(new Dictionary<string, object> {
                                { "success", ok }, { "verified", ok }, { "authenticated", s != null }, { "synced_email", s != null ? s.Email : "" }, { "uid", s != null ? s.UserId : "" },
                                { "plan", e.Plan }, { "role", e.Role }, { "ai_credit_available_thb", e.TotalAvailableTHB }, { "ai_credit_remaining_thb", e.CreditRemainingTHB },
                                { "ai_topup_balance_thb", e.TopupTHB }, { "app_version", DotminiNet.AppVersion }, { "error", DotminiAuth.LastError ?? "" } });
                            status = ok ? "200 OK" : "401 Unauthorized";
                            if (ok) DotminiNet.Raise(BringToFront);
                        }
                    }
                    else if (method == "POST" && path.StartsWith("/v1/auth/deeplink"))
                    {
                        var o = DJ.Obj(bodyText) ?? new Dictionary<string, object>();
                        string dlUrl = (DJ.Str(o, "url") ?? "").Trim();
                        if (dlUrl.StartsWith("microcode://", StringComparison.OrdinalIgnoreCase))
                        {
                            // Acknowledge immediately so the short-lived protocol-handler instance exits cleanly
                            // without timing out while network verification runs in the main window.
                            DotminiNet.Raise(BringToFront);
                            var __ = Task.Run(() => DotminiAuth.HandleDeepLink(dlUrl));
                            json = "{\"success\": true, \"queued\": true}";
                            status = "200 OK";
                        }
                        else
                        {
                            json = "{\"success\": false, \"error\": \"Invalid deep link\"}";
                            status = "400 Bad Request";
                        }
                    }
                    else if (method == "POST" && (path == "/mcp" || path == "/v1/mcp"))
                    {
                        json = LocalBridge.McpRpcHandler != null
                            ? LocalBridge.McpRpcHandler(bodyText)
                            : "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32601,\"message\":\"MCP handler not bound\"}}";
                        status = "200 OK";
                    }
                    else if (method == "GET" && (path == "/mcp" || path == "/v1/mcp"))
                    {
                        json = DJ.Ser(new Dictionary<string, object> { { "status", "ok" }, { "protocol", "mcp-streamable-http" }, { "endpoint", "http://127.0.0.1:" + Port + "/mcp" } });
                        status = "200 OK";
                    }
                    else if (method == "GET" && (path.StartsWith("/v1/status") || path == "/v1/health"))
                    {
                        var s = DotminiAuth.Session;
                        json = DJ.Ser(new Dictionary<string, object> { { "status", "ok" }, { "app", "MicroCode Native IDE (Windows)" }, { "authenticated", s != null }, { "email", s != null ? s.Email : "" }, { "app_version", DotminiNet.AppVersion } });
                        status = "200 OK";
                    }
                    else { status = "404 Not Found"; json = "{\"error\": \"Not found\"}"; }

                    var payload = Encoding.UTF8.GetBytes(json);
                    string acao = origin != null ? "Access-Control-Allow-Origin: " + origin + "\r\nAccess-Control-Allow-Private-Network: true\r\nVary: Origin\r\n" : "";
                    var hdr = Encoding.ASCII.GetBytes("HTTP/1.1 " + status + "\r\n" + acao + extra + "Content-Type: application/json\r\nContent-Length: " + payload.Length + "\r\nConnection: close\r\n\r\n");
                    await ns.WriteAsync(hdr, 0, hdr.Length);
                    if (payload.Length > 0) await ns.WriteAsync(payload, 0, payload.Length);
                    await ns.FlushAsync();
                }
                catch { }
            }
        }

        public static void BringToFront()
        {
            var w = Application.Current != null ? Application.Current.MainWindow : null;
            if (w == null) return;
            Native.BringToFront(w);
        }

        static int Find(byte[] b, int len)
        {
            for (int i = 0; i + 3 < len; i++) if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) return i;
            return -1;
        }
    }
}
