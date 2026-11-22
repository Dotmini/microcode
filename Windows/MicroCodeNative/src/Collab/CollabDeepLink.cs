// microcode://collab deep links on Windows (the Mac's MicroCodeApp.onOpenURL collab branch + CollabDeepLinkConfirmation):
// invite pages (/join) open microcode://collab?token=<base>/?code=CODE; sharing or joining always needs a click in the app,
// because any web page can open a microcode:// URL. Windows plumbing: the microcode / codetuner URL protocols are registered
// per user (HKCU\Software\Classes, no admin), and a running instance receives URLs from later launches over a per-user pipe.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public static class CollabDeepLink
    {
        public static readonly string[] Schemes = { "microcode", "codetuner" };
        const int MaxUrlLength = 8192;

        /// <summary>True for a microcode: / codetuner: URL (the only thing --open-url accepts).</summary>
        public static bool IsAppUrl(string url)
        {
            string t = (url ?? "").Trim();
            int colon = t.IndexOf(':');
            return colon > 0 && t.Length <= MaxUrlLength && Schemes.Contains(t.Substring(0, colon).ToLowerInvariant());
        }

        /// <summary>The host part of scheme://host/…?…, lowercased ("" when there is none).</summary>
        public static string HostOf(string url)
        {
            string t = (url ?? "").Trim();
            int colon = t.IndexOf(':');
            if (colon <= 0) return "";
            string rest = t.Substring(colon + 1);
            if (!rest.StartsWith("//")) return ""; // scheme:path has no host (URL.host is nil on the Mac)
            rest = rest.Substring(2);
            int end = rest.IndexOfAny(new[] { '/', '?', '#' });
            return (end >= 0 ? rest.Substring(0, end) : rest).ToLowerInvariant();
        }

        /// <summary>URLComponents.queryItems: the first value whose (case-insensitive) name is in names, percent-decoded and
        /// without '+'-to-space; null when no such item.</summary>
        public static string QueryValue(string url, params string[] names)
        {
            string t = (url ?? "").Trim();
            int q = t.IndexOf('?');
            if (q < 0) return null;
            string query = t.Substring(q + 1);
            int hash = query.IndexOf('#');
            // links built by the pages escape '#' as %23; an unescaped host:port#CODE token is kept whole unless another
            // name=value follows the '#' (then it really is a fragment)
            if (hash >= 0 && query.IndexOf('=', hash) >= 0) query = query.Substring(0, hash);
            foreach (var pair in query.Split('&'))
            {
                int e = pair.IndexOf('=');
                string k = Decode(e >= 0 ? pair.Substring(0, e) : pair).ToLowerInvariant();
                if (names.Any(n => n == k)) return e >= 0 ? Decode(pair.Substring(e + 1)) : "";
            }
            return null;
        }

        static string Decode(string s)
        {
            try { return Uri.UnescapeDataString(s); }
            catch (UriFormatException) { return s; }
        }

        /// <summary>CollabDeepLinkConfirmation.describe: host and room code from http(s)://host[:port][/path]/?code=XXXX or
        /// host:port#CODE.</summary>
        public static Tuple<string, string> Describe(string token)
        {
            string trimmed = (token ?? "").Trim();
            Uri u;
            if ((trimmed.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || trimmed.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                && Uri.TryCreate(trimmed, UriKind.Absolute, out u) && u.Host.Length > 0)
            {
                string port = u.IsDefaultPort ? "" : ":" + u.Port;
                string code = (QueryValueExact(trimmed, "code") ?? "").ToUpperInvariant();
                return Tuple.Create(u.Host + port, code);
            }
            var parts = trimmed.Split('#');
            return Tuple.Create(parts[0], parts.Length > 1 ? parts[1].ToUpperInvariant() : "");
        }

        // Describe matches the name "code" exactly, as the Mac does
        static string QueryValueExact(string url, string name)
        {
            int q = url.IndexOf('?');
            if (q < 0) return null;
            string query = url.Substring(q + 1);
            int hash = query.IndexOf('#'); if (hash >= 0) query = query.Substring(0, hash);
            foreach (var pair in query.Split('&'))
            {
                int e = pair.IndexOf('=');
                if (Decode(e >= 0 ? pair.Substring(0, e) : pair) == name) return e >= 0 ? Decode(pair.Substring(e + 1)) : "";
            }
            return null;
        }

        /// <summary>What a collab URL asks for, with the exact prompt the Mac shows (null prompt = no confirmation needed).</summary>
        public sealed class Plan
        {
            public string Kind;       // host | leave | join | show | ignore
            public bool Online;       // host: tunnel / online mode
            public string Token;      // join input
            public string Title, Detail, Confirm;
        }

        /// <summary>The decision part of the handler, separate from the UI so it can be tested.</summary>
        public static Plan PlanFor(string url, string currentShareCode, string workspaceName, bool hostingNow = false)
        {
            string host = HostOf(url);
            if (!IsAppUrl(url) || (host != "collab" && host != "team-collab")) return new Plan { Kind = "ignore" };
            string action = (QueryValue(url, "action") ?? "").ToLowerInvariant();
            string mode = (QueryValue(url, "mode") ?? "").ToLowerInvariant();
            string token = QueryValue(url, "token", "code", "url") ?? "";
            // a token that is itself a microcode:// link is unwrapped here (ParseJoinInput would do it later), so the prompt
            // names the host and room that are actually joined
            for (int depth = 0; depth < 4 && IsAppUrl(token); depth++) token = QueryValue(token, "token", "code", "url") ?? "";
            if (IsAppUrl(token)) token = "";
            if (action == "host")
            {
                bool online = mode == "tunnel" || mode == "online";
                if (hostingNow) return new Plan { Kind = "show" }; // already sharing: show the room instead of a second one
                // Windows: a peer is left before hosting (the Mac would run both and leak the peer timers)
                string leavingPeer = currentShareCode != null ? "\n\nYou will leave your current session first." : "";
                return new Plan
                {
                    Kind = "host", Online = online,
                    Title = "Share “" + (workspaceName ?? "Workspace") + "” for live collaboration?",
                    Detail = (online
                        ? "A link opened MicroCode asking to share this workspace over the internet. Anyone with the invite link and room code can read and edit its files."
                        : "A link opened MicroCode asking to share this workspace on your local network. Anyone on the network with the room code can read and edit its files.")
                        + leavingPeer,
                    Confirm = "Share Workspace"
                };
            }
            if (action == "leave" || action == "stop") return new Plan { Kind = "leave" };
            if (token.Length == 0) return new Plan { Kind = "show" };
            var target = Describe(token);
            if (currentShareCode != null && target.Item2.Length > 0 && currentShareCode.ToUpperInvariant() == target.Item2) return new Plan { Kind = "show" };
            string leaving = currentShareCode != null ? "\n\nYou will leave your current session first." : "";
            return new Plan
            {
                Kind = "join", Token = token,
                Title = "Join live session " + target.Item2 + "?",
                Detail = "Host: " + target.Item1 + "\nMicroCode will open the shared workspace and sync your edits with everyone in the session in real time." + leaving,
                Confirm = "Join Session"
            };
        }

        /// <summary>onOpenURL for a collab link; runs on the UI thread. Other microcode:// hosts are Mac-only features.</summary>
        static bool _busy; // one link at a time: the invite page's auto-open and a click on "Open in MicroCode" can both arrive

        public static async void Handle(string url)
        {
            if (_busy) { Debug.WriteLine("deep link: ignored while another link is being handled"); return; }
            _busy = true;
            try
            {
                var svc = CollabService.Shared;
                var s = svc.Session;
                string ws = AppState.Shared.WorkspaceFolder;
                string wsName = "Workspace";
                if (ws != null) { string full = Path.GetFullPath(ws).TrimEnd('\\'); wsName = Path.GetFileName(full); if (wsName.Length == 0) wsName = full; }
                var plan = PlanFor(url, s != null ? s.ShareCode : null, wsName, s != null && s.IsHostingLocally);
                if (plan.Kind == "ignore") { Debug.WriteLine("deep link: not a collab link"); return; }
                if (plan.Kind == "show") { CollabView.ShowWindow(); return; }
                if (plan.Kind == "leave") { await svc.LeaveSession(); return; }
                if (!Ask(plan.Title, plan.Detail, plan.Confirm)) return;
                if (plan.Kind == "host")
                {
                    if (svc.Session != null) await svc.LeaveSession();
                    svc.SetOnlineMode(plan.Online);
                    svc.CreateSession();
                    CollabView.ShowWindow();
                    return;
                }
                if (svc.Session != null) await svc.LeaveSession();
                CollabView.ShowWindow();
                try { await svc.JoinSession(plan.Token, true); }
                catch (Exception ex) { Debug.WriteLine("Collaboration deep link join failed: " + ex.Message); }
            }
            catch (Exception ex) { Debug.WriteLine("Collaboration deep link failed: " + ex); }
            finally { _busy = false; }
        }

        /// <summary>CollabDeepLinkConfirmation.ask: an informational alert with the confirm button first, then Cancel.</summary>
        static bool Ask(string title, string detail, string confirm)
        {
            var t = Theme.Current;
            var main = Application.Current != null ? Application.Current.MainWindow : null;
            if (main != null) { if (main.WindowState == WindowState.Minimized) main.WindowState = WindowState.Normal; main.Activate(); }
            bool result = false;
            var w = new Window { Title = "MicroCode", Width = 460, SizeToContent = SizeToContent.Height, ResizeMode = ResizeMode.NoResize, WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = t.ElevatedBackground, FontFamily = UIFonts.UI, ShowInTaskbar = false, Topmost = true };
            if (main != null && main.IsVisible) w.Owner = main;
            else w.WindowStartupLocation = WindowStartupLocation.CenterScreen;
            w.SourceInitialized += delegate { Native.StyleWindow(w, t.IsDark); };
            var col = V.VLead(10); col.Align = Cross.Stretch;
            col.Children.Add(V.H(10, Sym.Icon("person.2.fill", 22, t.Accent), V.Wrap(V.T(title, 14, FontWeights.SemiBold, t.Primary), TextAlignment.Left)));
            col.Children.Add(V.Wrap(V.T(detail, 12, FontWeights.Normal, t.Secondary), TextAlignment.Left));
            var ok = V.Button(V.Box(V.T(confirm, 12, FontWeights.SemiBold, Brushes.White), V.P(14, 6), t.Accent, 6), () => { result = true; w.Close(); });
            var cancel = V.Button(V.Box(V.T("Cancel", 12, FontWeights.Medium, t.Primary), V.P(14, 6), t.P(0.1), 6), () => { result = false; w.Close(); });
            var buttons = V.H(8, V.Sp(), cancel, ok); buttons.Margin = new Thickness(0, 6, 0, 0);
            col.Children.Add(buttons);
            w.Content = new System.Windows.Controls.Border { Padding = new Thickness(20), Child = col };
            // Enter is the default (first) button, Esc cancels — NSAlert's keys
            w.KeyDown += (snd, e) =>
            {
                if (e.Key == System.Windows.Input.Key.Escape) { result = false; w.Close(); }
                else if (e.Key == System.Windows.Input.Key.Enter) { result = true; w.Close(); }
            };
            w.ShowDialog();
            return result;
        }

        // ── cold start + forwarding from later launches ──

        static readonly List<string> _pending = new List<string>();
        static bool _ready;

        /// <summary>Queue a URL until the main window is up, then handle it (cold start: the app was launched by the link).</summary>
        public static void Enqueue(string url)
        {
            if (!IsAppUrl(url)) return;
            lock (_pending)
            {
                if (!_ready) { _pending.Add(url.Trim()); return; }
            }
            Dispatch(url.Trim());
        }

        /// <summary>The main window has rendered: handle what arrived before it.</summary>
        public static void MarkReady()
        {
            List<string> now;
            lock (_pending) { _ready = true; now = _pending.ToList(); _pending.Clear(); }
            foreach (var u in now) Dispatch(u);
        }

        static void Dispatch(string url)
        {
            var app = Application.Current;
            if (app == null) return;
            app.Dispatcher.BeginInvoke(new Action(() =>
            {
                var main = app.MainWindow;
                if (main != null) { if (main.WindowState == WindowState.Minimized) main.WindowState = WindowState.Normal; main.Activate(); }
                Handle(url);
            }));
        }
    }

    /// <summary>One MicroCode per data folder (and Windows logon session) receives URLs: a named mutex marks the running
    /// instance, and a later launch with --open-url hands its URL over a pipe, then exits. The pipe name is random and only
    /// written to a file in the user's own data folder, so another account cannot guess it and squat it; the pipe itself
    /// admits only this user and refuses network clients.</summary>
    public sealed class SingleInstance : IDisposable
    {
        const int MaxMessageBytes = 32768;            // 8192 UTF-16 chars are at most 24576 UTF-8 bytes
        static readonly TimeSpan ReadTimeout = TimeSpan.FromSeconds(3);
        readonly Mutex _mutex;
        readonly string _nameFile;
        readonly string _pipeName;
        readonly CancellationTokenSource _stop = new CancellationTokenSource();
        public bool IsFirst { get; private set; }

        public static string KeyFor(string dataDir)
        {
            using (var sha = SHA256.Create())
            {
                var h = sha.ComputeHash(Encoding.UTF8.GetBytes(Path.GetFullPath(dataDir).TrimEnd('\\').ToLowerInvariant()));
                return BitConverter.ToString(h, 0, 8).Replace("-", "");
            }
        }

        public SingleInstance(string dataDir)
        {
            string key = KeyFor(dataDir);
            int session = Process.GetCurrentProcess().SessionId;
            _nameFile = Path.Combine(dataDir, "instance-" + session + ".pipe");
            bool created;
            _mutex = new Mutex(true, @"Local\MicroCode.Main." + key, out created);
            IsFirst = created;
            if (IsFirst)
            {
                _pipeName = "MicroCode.Main." + Guid.NewGuid().ToString("N");
                Directory.CreateDirectory(dataDir);
                File.WriteAllText(_nameFile, _pipeName);
            }
            else
            {
                try { _pipeName = File.ReadAllText(_nameFile).Trim(); }
                catch (Exception ex)
                {
                    if (!(ex is IOException || ex is UnauthorizedAccessException)) throw;
                    Debug.WriteLine("deep link: no running instance pipe: " + ex.Message);
                    _pipeName = null;
                }
            }
        }

        /// <summary>Running instance: accept URLs from later launches until disposed.</summary>
        public void Listen(Action<string> received)
        {
            Task.Run(async () =>
            {
                while (!_stop.IsCancellationRequested)
                {
                    bool failed = false;
                    try
                    {
                        var sec = new PipeSecurity();
                        sec.AddAccessRule(new PipeAccessRule(WindowsIdentity.GetCurrent().User, PipeAccessRights.ReadWrite, AccessControlType.Allow));
                        sec.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.NetworkSid, null), PipeAccessRights.FullControl, AccessControlType.Deny));
                        using (var server = new NamedPipeServerStream(_pipeName, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous, MaxMessageBytes, 0, sec))
                        {
                            await Task.Factory.FromAsync(server.BeginWaitForConnection, server.EndWaitForConnection, null);
                            // a client that connects and never finishes is dropped after ReadTimeout (disposing ends the read)
                            var read = ReadAll(server);
                            if (await Task.WhenAny(read, Task.Delay(ReadTimeout)) != read) { Debug.WriteLine("deep link pipe: client timed out"); continue; }
                            string url = read.Result;
                            if (CollabDeepLink.IsAppUrl(url)) received(url);
                        }
                    }
                    catch (Exception ex)
                    {
                        // the listener must outlive any one bad client; log and start a fresh pipe
                        Debug.WriteLine("deep link pipe: " + ex.GetType().Name + " " + ex.Message);
                        failed = true;
                    }
                    if (failed) await Task.Delay(500); // C# 5: no await inside catch
                }
            });
        }

        static async Task<string> ReadAll(Stream s)
        {
            var buf = new byte[MaxMessageBytes];
            int total = 0, n;
            while (total < buf.Length && (n = await s.ReadAsync(buf, total, buf.Length - total)) > 0) total += n;
            return Encoding.UTF8.GetString(buf, 0, total).Trim();
        }

        [DllImport("user32.dll")] static extern bool AllowSetForegroundWindow(int processId);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetNamedPipeServerProcessId(IntPtr pipe, out int serverProcessId);

        /// <summary>Later launch: hand the URL to the running instance (true when it took it).</summary>
        public bool Forward(string url)
        {
            if (string.IsNullOrEmpty(_pipeName)) return false;
            var bytes = Encoding.UTF8.GetBytes(url ?? "");
            if (bytes.Length > MaxMessageBytes) return false;
            try
            {
                using (var client = new NamedPipeClientStream(".", _pipeName, PipeDirection.Out))
                {
                    client.Connect(3000);
                    // let exactly the running instance bring its window forward
                    int pid;
                    if (GetNamedPipeServerProcessId(client.SafePipeHandle.DangerousGetHandle(), out pid)) AllowSetForegroundWindow(pid);
                    client.Write(bytes, 0, bytes.Length);
                    client.Flush();
                    return true;
                }
            }
            catch (Exception ex)
            {
                if (!(ex is IOException || ex is TimeoutException || ex is UnauthorizedAccessException)) throw;
                Debug.WriteLine("deep link forward: " + ex.Message);
                return false;
            }
        }

        public void Dispose()
        {
            _stop.Cancel();
            if (IsFirst)
            {
                try { if (File.Exists(_nameFile) && File.ReadAllText(_nameFile).Trim() == _pipeName) File.Delete(_nameFile); }
                catch (Exception ex) { if (!(ex is IOException || ex is UnauthorizedAccessException)) throw; Debug.WriteLine("deep link: " + ex.Message); }
                try { _mutex.ReleaseMutex(); } catch (ApplicationException) { } // released from a thread that does not own it
            }
            _mutex.Dispose();
        }
    }

    /// <summary>Per-user URL protocol registration (no admin): HKCU\Software\Classes\microcode and \codetuner open
    /// "MicroCode.exe" --open-url "%1". Only rewritten when the exe path changed.</summary>
    public static class UrlProtocol
    {
        public static string CommandFor(string exePath) { return "\"" + exePath + "\" --open-url \"%1\""; }

        public static void EnsureRegistered(string exePath)
        {
            foreach (var scheme in CollabDeepLink.Schemes)
            {
                try
                {
                    string want = CommandFor(exePath);
                    using (var cmd = Registry.CurrentUser.OpenSubKey(@"Software\Classes\" + scheme + @"\shell\open\command"))
                    {
                        if (cmd != null && string.Equals(cmd.GetValue("") as string, want, StringComparison.OrdinalIgnoreCase)) continue;
                    }
                    using (var root = Registry.CurrentUser.CreateSubKey(@"Software\Classes\" + scheme))
                    {
                        root.SetValue("", "URL:MicroCode Protocol");
                        root.SetValue("URL Protocol", "");
                        using (var icon = root.CreateSubKey("DefaultIcon")) icon.SetValue("", "\"" + exePath + "\",0");
                        using (var cmd = root.CreateSubKey(@"shell\open\command")) cmd.SetValue("", want);
                    }
                }
                catch (Exception ex)
                {
                    if (!(ex is UnauthorizedAccessException || ex is System.Security.SecurityException || ex is IOException)) throw;
                    Debug.WriteLine("url protocol " + scheme + ": " + ex.Message);
                }
            }
        }
    }
}
