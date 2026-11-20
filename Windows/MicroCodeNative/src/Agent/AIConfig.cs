// AI mode & provider configuration (SettingsView "AI & Agent"): Dotmini Cloud / Web Subscription / Direct API Key (BYOK) /
// Enterprise / Local LLM. Keys are encrypted per Windows user with DPAPI. AIEndpoint resolves the mode into one concrete
// request target (format, base URL, model, credential) used by chat, the agent tool loop, inline edit and Cell Mode AI.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using MicroCode.Core;

namespace MicroCode.Views
{
    public class ProviderInfo
    {
        public string Id, Name, Endpoint, DefaultModel;
        public string[] Models;
        public ProviderInfo(string id, string name, string endpoint, string defModel, params string[] models) { Id = id; Name = name; Endpoint = endpoint; DefaultModel = defModel; Models = models; }
    }

    public static class AIConfig
    {
        // BYOK providers (AIModelCatalog providers without "omni" / "local")
        public static readonly List<ProviderInfo> Catalog = new List<ProviderInfo>
        {
            new ProviderInfo("openai", "OpenAI", "https://api.openai.com/v1", "gpt-5", "gpt-5", "gpt-5-mini", "gpt-4.1", "o4-mini"),
            new ProviderInfo("anthropic", "Anthropic", "https://api.anthropic.com/v1", "claude-sonnet-5-5", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"),
            new ProviderInfo("gemini", "Google Gemini", "https://generativelanguage.googleapis.com/v1beta", "gemini-2.5-pro", "gemini-2.5-pro", "gemini-2.5-flash"),
            new ProviderInfo("deepseek", "DeepSeek", "https://api.deepseek.com/v1", "deepseek-chat", "deepseek-chat", "deepseek-reasoner"),
            new ProviderInfo("openrouter", "OpenRouter", "https://openrouter.ai/api/v1", "openrouter/auto", "openrouter/auto"),
            new ProviderInfo("groq", "Groq", "https://api.groq.com/openai/v1", "llama-3.3-70b-versatile", "llama-3.3-70b-versatile"),
            new ProviderInfo("mistral", "Mistral", "https://api.mistral.ai/v1", "mistral-large-latest", "mistral-large-latest", "codestral-latest"),
            new ProviderInfo("grok", "xAI Grok", "https://api.x.ai/v1", "grok-4", "grok-4", "grok-code-fast-1"),
            new ProviderInfo("qwen", "Qwen", "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", "qwen-max", "qwen-max", "qwen3-coder-plus"),
            new ProviderInfo("glm", "Zhipu GLM", "https://open.bigmodel.cn/api/paas/v4", "glm-4.6", "glm-4.6"),
            new ProviderInfo("kimi", "Kimi", "https://api.moonshot.ai/v1", "kimi-k2-0905-preview", "kimi-k2-0905-preview"),
            new ProviderInfo("together", "Together AI", "https://api.together.xyz/v1", "meta-llama/Llama-3.3-70B-Instruct-Turbo", "meta-llama/Llama-3.3-70B-Instruct-Turbo"),
            new ProviderInfo("fireworks", "Fireworks", "https://api.fireworks.ai/inference/v1", "accounts/fireworks/models/llama-v3p3-70b-instruct", "accounts/fireworks/models/llama-v3p3-70b-instruct"),
            new ProviderInfo("perplexity", "Perplexity", "https://api.perplexity.ai", "sonar-pro", "sonar-pro", "sonar"),
            new ProviderInfo("custom", "Custom (OpenAI-compatible)", "http://localhost:8000/v1", "", "")
        };
        public static readonly ProviderInfo Local = new ProviderInfo("local", "Local LLM", "http://localhost:11434/v1", "llama3.1", "llama3.1");
        public static readonly ProviderInfo Cloud = new ProviderInfo("omni", "Dotmini Cloud", DotminiCloud.DefaultProxy, "", "");

        /// <summary>aiKeyMode: cloud | subscription | direct | enterprise | local. Like the macOS app, Dotmini Cloud is the default.</summary>
        public static string Mode { get { return Defaults.Str("ai_key_mode", "cloud"); } set { Defaults.Set("ai_key_mode", value); } }

        public static string SelectedProvider
        {
            get
            {
                string p = Defaults.Str("ai_provider", "openai");
                // migrate earlier Windows builds that stored display names
                var byName = Catalog.FirstOrDefault(c => c.Name == p || (p == "Anthropic Claude" && c.Id == "anthropic") || (p == "xAI Grok" && c.Id == "grok"));
                if (byName != null) return byName.Id;
                return Catalog.Any(c => c.Id == p) ? p : "openai";
            }
            set { Defaults.Set("ai_provider", value); }
        }

        public static ProviderInfo Info(string id)
        {
            if (id == "local") return Local;
            if (id == "omni") return Cloud;
            return Catalog.FirstOrDefault(c => c.Id == id) ?? Catalog[0];
        }

        /// <summary>The provider the agent actually talks to for the current mode.</summary>
        public static string Provider
        {
            get
            {
                switch (Mode) { case "local": return "local"; case "cloud": return "omni"; default: return SelectedProvider; }
            }
            set { SelectedProvider = value; }
        }

        public static string ProviderName { get { return Info(Provider).Name; } }
        /// <summary>Wire format of the current target: Dotmini Cloud is OpenAI-compatible for every upstream model.</summary>
        public static bool IsAnthropic { get { return Mode != "cloud" && Mode != "local" && Provider == "anthropic"; } }
        public static bool IsGemini { get { return Mode != "cloud" && Mode != "local" && Provider == "gemini"; } }

        public static string ModelFor(string id)
        {
            if (id == "omni") { var m = Defaults.Str("ai_model_omni", null); return string.IsNullOrWhiteSpace(m) ? DotminiCloud.DefaultModelId : m; }
            return Defaults.Str("ai_model_" + id, Info(id).DefaultModel);
        }
        public static void SetModelFor(string id, string model) { Defaults.Set("ai_model_" + id, model); }
        public static string Model { get { return ModelFor(Provider); } set { SetModelFor(Provider, value); } }

        public static string BaseUrlFor(string id) { if (id == "omni") return DotminiCloud.ProxyURL; return Defaults.Str("ai_base_" + id, Info(id).Endpoint); }
        public static void SetBaseUrlFor(string id, string url) { if (string.IsNullOrWhiteSpace(url)) Defaults.Remove("ai_base_" + id); else Defaults.Set("ai_base_" + id, url.Trim()); }
        public static string BaseUrl { get { return BaseUrlFor(Provider); } set { SetBaseUrlFor(Provider, value); } }
        public static bool HasCustomUrl(string id) { var v = Defaults.Str("ai_base_" + id, null); return v != null && v.TrimEnd('/') != Info(id).Endpoint.TrimEnd('/'); }

        /// <summary>Strips what people paste around a key: spaces, new lines, quotes and a leading "Bearer ".</summary>
        public static string CleanKey(string raw)
        {
            if (raw == null) return null;
            string v = raw.Trim().Trim('"', '\'', '`').Trim();
            if (v.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)) v = v.Substring(7).Trim();
            v = Regex.Replace(v, @"\s+", "");
            return v.Length == 0 ? null : v;
        }

        public static string KeyFor(string id) { return CleanKey(Dpapi.Unprotect(Defaults.Str("ai_key_" + id, null))); }

        public static void SetKeyFor(string id, string value)
        {
            value = CleanKey(value);
            if (string.IsNullOrEmpty(value)) { Defaults.Remove("ai_key_" + id); return; }
            Defaults.Set("ai_key_" + id, Dpapi.Protect(value));
        }

        public static string Key { get { return KeyFor(Provider); } set { SetKeyFor(Provider, value); } }

        public static bool IsConfigured
        {
            get
            {
                string m = Mode;
                if (m == "local") return true;
                if (m == "cloud") return DotminiCloud.HasCredential;
                if (m == "subscription" || m == "enterprise") return false;
                if (Provider == "custom" || HasCustomUrl(Provider)) return true;
                return !string.IsNullOrEmpty(Key);
            }
        }

        /// <summary>ExecutionMode.badgeTitle</summary>
        public static string BadgeTitle
        {
            get
            {
                switch (Mode) { case "local": return "Local LLM"; case "cloud": return "Dotmini Cloud"; case "subscription": return "Subscription"; case "enterprise": return "Enterprise"; default: return "BYOK"; }
            }
        }

        /// <summary>currentModelDisplayName</summary>
        public static string ModelDisplayName
        {
            get
            {
                string id = Model;
                if (string.IsNullOrEmpty(id)) return "Custom model";
                var cm = DotminiCloud.Find(id); // the gateway catalog carries canonical names ("Claude Sonnet 5.5")
                return cm != null ? cm.Name : FormatModelName(id);
            }
        }

        /// <summary>AIModelCatalog.formatModelName: "claude-sonnet-5-5" → "Claude Sonnet 5 5", "gpt-5-mini" → "GPT-5 Mini".</summary>
        public static string FormatModelName(string id)
        {
            string clean = (id ?? "").Trim();
            if (clean.StartsWith("models/")) clean = clean.Substring(7);
            string prefix = "";
            int slash = clean.IndexOf('/');
            if (slash >= 0) { string org = clean.Substring(0, slash); prefix = Cap(org) + " / "; clean = clean.Substring(slash + 1); }
            string dateSuffix = "";
            var dm = Regex.Match(clean, @"-(202[4-9]-\d{2}-\d{2})$");
            if (dm.Success) { dateSuffix = " (" + dm.Groups[1].Value + ")"; clean = clean.Substring(0, dm.Index); }
            var parts = new List<string>();
            foreach (var part in clean.Split('-', '_'))
            {
                string l = part.ToLowerInvariant();
                if (l.Length == 0) continue;
                int dn;
                if (l.Length == 8 && int.TryParse(l, out dn) && dn > 20200000) { parts.Add("(" + l.Substring(0, 4) + "-" + l.Substring(4, 2) + "-" + l.Substring(6, 2) + ")"); continue; }
                switch (l)
                {
                    case "deepseek": parts.Add("DeepSeek"); break;
                    case "glm": parts.Add("GLM"); break;
                    case "gpt": parts.Add("GPT"); break;
                    case "ai": parts.Add("AI"); break;
                    case "llm": parts.Add("LLM"); break;
                    case "moe": parts.Add("MoE"); break;
                    case "oss": parts.Add("OSS"); break;
                    case "api": parts.Add("API"); break;
                    case "tts": parts.Add("TTS"); break;
                    case "exp": parts.Add("Experimental"); break;
                    case "r1": case "r2": case "r3": parts.Add(l.ToUpperInvariant()); break;
                    default:
                        double num;
                        if (Regex.IsMatch(l, "^v[1-9]$") || l == "nvfp4" || l == "fp8" || l == "fp4" || l == "bf16") parts.Add(l.ToUpperInvariant());
                        else if (l.EndsWith("b") && double.TryParse(l.Substring(0, l.Length - 1), NumberStyles.Float, CultureInfo.InvariantCulture, out num)) parts.Add(l.ToUpperInvariant());
                        else if (Regex.IsMatch(l, "^o[0-9]")) parts.Add(l);
                        else if (l.StartsWith("gpt")) parts.Add("GPT-" + l.Substring(3));
                        else parts.Add(Cap(part));
                        break;
                }
            }
            // "claude-sonnet-5-5" → "Claude Sonnet 5.5": adjacent short version numbers form one version
            for (int i = parts.Count - 1; i > 0; i--)
                if (Regex.IsMatch(parts[i], @"^\d{1,2}$") && Regex.IsMatch(parts[i - 1], @"^\d{1,2}(\.\d{1,2})*$")) { parts[i - 1] = parts[i - 1] + "." + parts[i]; parts.RemoveAt(i); }
            string result = prefix + string.Join(" ", parts) + dateSuffix;
            return result.Length == 0 ? id : result;
        }

        static string Cap(string s) { return s.Length == 0 ? s : char.ToUpperInvariant(s[0]) + s.Substring(1).ToLowerInvariant(); }
    }

    /// <summary>One concrete request target for the current AI mode.</summary>
    public class AIEndpoint
    {
        public string Provider, Format, BaseUrl, Model, Key;
        public bool IsCloud;

        /// <summary>Resolves mode → endpoint. Throws a friendly AIException when nothing usable is connected.</summary>
        public static async Task<AIEndpoint> Resolve(bool forceRefresh)
        {
            string mode = AIConfig.Mode;
            if (mode == "cloud")
            {
                DotminiCloud.EnsureFresh();
                string token = await DotminiCloud.Token(forceRefresh);
                if (string.IsNullOrEmpty(token))
                    throw new AIException(0, DotminiAuth.ReauthReason.Length > 0 ? DotminiAuth.ReauthReason
                        : "Dotmini Cloud requires signing in. Sign in via Settings → Account & License or on microcode.dotmini.net (auto-syncs seamlessly).", "account");
                return new AIEndpoint { Provider = "omni", Format = "openai", BaseUrl = DotminiCloud.ProxyURL, Model = AIConfig.ModelFor("omni"), Key = token, IsCloud = true };
            }
            if (mode == "local")
                return new AIEndpoint { Provider = "local", Format = "openai", BaseUrl = AIConfig.BaseUrlFor("local").TrimEnd('/'), Model = AIConfig.ModelFor("local"), Key = AIConfig.KeyFor("local") };
            if (mode == "subscription")
                throw new AIException(0, "No subscription session found. Web Subscription sign-in is not available on Windows yet — choose Dotmini Cloud, Direct API Key or Local LLM in Settings → AI & Agent.", "ai");
            if (mode == "enterprise")
                throw new AIException(0, "No Enterprise gateway is configured. Use Direct API Key → Custom (OpenAI-compatible) with your gateway's Base URL in Settings → AI & Agent.", "ai");
            string p = AIConfig.SelectedProvider;
            string key = AIConfig.KeyFor(p);
            bool custom = p == "custom" || AIConfig.HasCustomUrl(p);
            if (string.IsNullOrEmpty(key) && !custom)
                throw new AIException(0, "API key missing for " + AIConfig.Info(p).Name + ". Go to Settings → AI & Agent → Direct API Key to add your key.", "ai");
            string baseUrl = AIConfig.BaseUrlFor(p).TrimEnd('/');
            // Gemini: use Google's OpenAI-compatible surface so streaming + function calling share one code path.
            if (p == "gemini" && baseUrl.EndsWith("generativelanguage.googleapis.com/v1beta", StringComparison.OrdinalIgnoreCase)) baseUrl += "/openai";
            return new AIEndpoint
            {
                Provider = p, Format = p == "anthropic" ? "anthropic" : "openai",
                BaseUrl = baseUrl, Model = AIConfig.ModelFor(p), Key = key
            };
        }

        public void Authorize(HttpRequestMessage req, string feature)
        {
            if (IsCloud) { DotminiCloud.ApplyHeaders(req, Key, feature); return; }
            if (Format == "anthropic")
            {
                req.Headers.TryAddWithoutValidation("x-api-key", Key ?? "");
                req.Headers.TryAddWithoutValidation("anthropic-version", "2023-06-01");
                return;
            }
            if (!string.IsNullOrEmpty(Key)) req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", Key);
            if (BaseUrl.Contains("openrouter.ai")) { req.Headers.TryAddWithoutValidation("HTTP-Referer", "https://dotmini.net"); req.Headers.TryAddWithoutValidation("X-Title", "MicroCode IDE"); }
        }

        public string ProviderLabel { get { return IsCloud ? "Dotmini Cloud" : AIConfig.Info(Provider).Name; } }
    }

    /// <summary>An AI request failure with the HTTP status and the provider's own message.</summary>
    public class AIException : Exception
    {
        public int Status;
        public string Detail;
        /// <summary>"ai" → Settings · AI & Agent, "account" → Settings · Account & License, "topup" → credits.</summary>
        public string Fix;
        public AIException(int status, string message, string fix) : base(message) { Status = status; Fix = fix; }

        /// <summary>parseErrorMessage (AIClient.swift): readable text for HTTP failures, with the provider's own detail.</summary>
        public static AIException FromHttp(int code, string raw, AIEndpoint ep)
        {
            string detail = DJ.ErrorText(raw);
            bool has = detail.Length > 0;
            bool cloud = ep != null && ep.IsCloud;
            string who = ep != null ? ep.ProviderLabel : "AI provider";
            string msg, fix = "ai";
            switch (code)
            {
                case 402:
                    if (cloud) { msg = has ? "Cloud AI Credit Exhausted (HTTP 402): " + detail : "Payment required: Your Dotmini Cloud AI Credit Pool is exhausted (฿0.00 left). Top up Cloud AI Credit or upgrade your plan in Settings → Account & License."; fix = "topup"; }
                    else msg = who + " returned HTTP 402" + (has ? ": " + detail : " (Insufficient balance or quota on your " + who + " account).") + " Top up that account, or switch to Dotmini Cloud / another provider in Settings → AI & Agent.";
                    break;
                case 429:
                    msg = has ? "Rate limited by " + who + " (HTTP 429): " + detail : "Rate limited by " + who + " (HTTP 429: Requests/Tokens Per Minute quota exceeded on your API key). Please wait 1-2 minutes for the provider quota window to reset.";
                    break;
                case 401: case 403:
                    if (cloud) { msg = "Dotmini Cloud session or Platform key is invalid/expired (" + code + "). Sign in again in Settings → Account & License."; fix = "account"; }
                    else msg = who + " rejected the API key (HTTP " + code + ")" + (has ? " — " + detail : "") + ". Paste a valid key for " + who + " in Settings → AI & Agent → Direct API Key.";
                    break;
                case 404:
                    msg = has ? "Model or endpoint not found (HTTP 404): " + detail : "Model or endpoint not found (HTTP 404). Verify the selected model is supported by this provider.";
                    break;
                case 500: case 502: case 503: case 504: case 529:
                    msg = has ? "AI service error (HTTP " + code + "): " + detail : "AI service temporarily unavailable (" + code + "). Try again in a moment.";
                    break;
                default:
                    msg = "HTTP " + code + (has ? ": " + detail : "");
                    break;
            }
            return new AIException(code, msg, fix) { Detail = detail };
        }

        /// <summary>Readable text for any failure (network errors included).</summary>
        public static string Describe(Exception ex, bool cloud)
        {
            var b = ex is AggregateException ? ex.GetBaseException() : ex;
            if (b is AIException) return b.Message;
            if (b is TaskCanceledException || b is OperationCanceledException) return "Request timed out. Check your internet connection and try again.";
            if (b is HttpRequestException || b is WebException || b is System.Net.Sockets.SocketException || b is System.IO.IOException)
                return cloud ? "Cannot connect to Dotmini Cloud AI (" + (b.InnerException ?? b).Message + "). Check your internet connection, or sign in again in Settings → Account & License."
                             : "Network connection error while contacting the AI provider (" + (b.InnerException ?? b).Message + "). Please check your internet connection.";
            return b.Message;
        }
    }
}
