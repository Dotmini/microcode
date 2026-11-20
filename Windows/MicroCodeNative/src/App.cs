// MicroCode for Windows — entry point.
// --snapshot <out.png> [--size WxH] [--folder <path>] [--file <path>] [--mode code|agent|playground|welcome] [--theme raw] [--console]
// renders the main window offscreen to a PNG (used to verify the port against the macOS layout) and exits.
using System;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using MicroCode.Core;
using MicroCode.UI;
using MicroCode.Views;

[assembly: System.Runtime.Versioning.TargetFramework(".NETFramework,Version=v4.8")]
[assembly: System.Reflection.AssemblyTitle("MicroCode")]
[assembly: System.Reflection.AssemblyProduct("MicroCode")]
[assembly: System.Reflection.AssemblyCompany("Dotmini Company Limited")]
[assembly: System.Reflection.AssemblyCopyright("Copyright © 2024-2026 Dotmini Company Limited")]
[assembly: System.Reflection.AssemblyVersion("2.5.41.1")]
[assembly: System.Reflection.AssemblyFileVersion("2.5.41.1")]
[assembly: System.Windows.ThemeInfo(System.Windows.ResourceDictionaryLocation.None, System.Windows.ResourceDictionaryLocation.SourceAssembly)]

namespace MicroCode
{
    public static class Program
    {
        [STAThread]
        public static int Main(string[] args)
        {
            try { return Run(args); }
            catch (Exception ex)
            {
                try { Directory.CreateDirectory(Defaults.Dir); File.AppendAllText(Path.Combine(Defaults.Dir, "crash.log"), DateTime.Now + " " + ex + "\n\n"); } catch { }
                if (Arg(args, "--snapshot") == null && !args.Contains("--pns-daemon")) MessageBox.Show(ex.ToString(), "MicroCode failed to start", MessageBoxButton.OK, MessageBoxImage.Error);
                return 2;
            }
        }

        static int Run(string[] args)
        {
            // Test renders get their own data folder so they can never touch the user's settings, keys, chats or notebooks.
            string dataDir = Arg(args, "--data-dir");
            if (dataDir == null && Arg(args, "--snapshot") != null) dataDir = Path.Combine(Path.GetTempPath(), "MicroCode-snapshot");
            if (dataDir != null)
            {
                Defaults.UseDir(Path.GetFullPath(dataDir));
                TaskFiles.HomeOverride = Path.Combine(Defaults.Dir, ".microcode");
            }
            var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
            app.Exit += delegate { Defaults.Flush(); NotebookView.ShutdownKernel(); };
            app.DispatcherUnhandledException += (s, e) =>
            {
                try { File.AppendAllText(Path.Combine(Defaults.Dir, "crash.log"), DateTime.Now + " " + e.Exception + "\n\n"); } catch { }
                if (!PnsOrchestrator.IsDaemonProcess) MessageBox.Show(e.Exception.Message, "MicroCode", MessageBoxButton.OK, MessageBoxImage.Error);
                e.Handled = true;
            };
            // Test hooks — only with an isolated data folder (--snapshot / --data-dir), never against the user's real settings:
            // --fresh wipes that folder, --set key=value seeds settings, --set-key provider=key stores an API key, --agent-prompt sends a message.
            if (dataDir != null)
            {
                string real = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "MicroCode");
                bool isolated = !string.Equals(Path.GetFullPath(dataDir).TrimEnd('\\'), real.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
                if (isolated && args.Contains("--fresh")) { try { if (Directory.Exists(Defaults.Dir)) Directory.Delete(Defaults.Dir, true); } catch { } Defaults.UseDir(Defaults.Dir); }
                if (isolated)
                {
                    foreach (var kv in Args(args, "--set")) { int eq = kv.IndexOf('='); if (eq > 0) { string v = kv.Substring(eq + 1); Defaults.Set(kv.Substring(0, eq), v == "true" ? (object)true : v == "false" ? (object)false : v); } }
                    foreach (var kv in Args(args, "--set-key")) { int eq = kv.IndexOf('='); if (eq > 0) AIConfig.SetKeyFor(kv.Substring(0, eq), kv.Substring(eq + 1)); }
                    Defaults.Flush();
                }
            }
            // --pns-daemon [--pns-port N]: the headless PNS 24/7 daemon (no window); the app talks to it on 127.0.0.1 with a token
            if (args.Contains("--pns-daemon"))
            {
                int pnsPort;
                if (!int.TryParse(Arg(args, "--pns-port") ?? "", out pnsPort) || pnsPort <= 0) pnsPort = PnsOrchestrator.DefaultDaemonPort;
                return PnsDaemon.RunHeadless(app, pnsPort);
            }
            var state = AppState.Shared;
            string snapshot = Arg(args, "--snapshot");
            string agentPrompt = Arg(args, "--agent-prompt");
            if (snapshot != null)
            {
                // isolated, deterministic state for screenshots
                state.ThemeRaw = Arg(args, "--theme") ?? "dark";
                Theme.Apply(state.ThemeRaw);
            }
            else
            {
                state.Load();
                // loopback bridge for the web sign-in hand-off (microcode.dotmini.net/auth.html → 127.0.0.1:18888) + account refresh
                LocalBridge.Start();
                if (DotminiAuth.SignedIn) System.Threading.Tasks.Task.Run(() => DotminiAuth.RefreshEntitlement());
                if (AIConfig.Mode == "cloud") DotminiCloud.EnsureFresh();
            }
            Styles.Install(app);
            AgentStore.Load();

            var win = new MainWindow(state);
            string folder = Arg(args, "--folder") ?? Positional(args).FirstOrDefault(a => Directory.Exists(a));
            string file = Arg(args, "--file") ?? Positional(args).FirstOrDefault(a => File.Exists(a));
            if (folder != null) state.OpenWorkspace(Path.GetFullPath(folder));
            if (file != null) state.LoadFile(Path.GetFullPath(file));
            string mode = Arg(args, "--mode");
            if (mode == "agent") state.SwitchToMode(EditorMode.AIAgent);
            else if (mode == "playground") state.SwitchToMode(EditorMode.Playground);
            else if (mode == "notebook")
            {
                if (args.Contains("--notebook-demo"))
                {
                    var d = new NbDoc { Name = "Basic Data" };
                    d.Cells.Add(new NbCell { Type = "Markdown", Content = "## Sales analysis\nLoad the numbers, compute stats and plot." });
                    d.Cells.Add(new NbCell { Content = "data = [12, 19, 3, 5, 2, 3, 21, 14]\ntotal = sum(data)\nprint('total =', total)\nsorted(data)" });
                    d.Cells.Add(new NbCell { Content = "mean = total / len(data)\nf'mean = {mean:.2f}  (state kept from the previous cell)'" });
                    d.Cells.Add(new NbCell { Content = "1 / 0" });
                    NbStore.Seed = new List<NbDoc> { d };
                    NotebookView.AutoRunAll = args.Contains("--run-cells");
                    NotebookView.ForceShowAI = args.Contains("--nb-agent");
                }
                else if (Arg(args, "--notebook-file") != null)
                {
                    // snapshot/test hook: open a .mic / .mcnb / .ipynb / .py sheet in memory (never persisted)
                    NbStore.Seed = new List<NbDoc> { NbFormats.Load(Path.GetFullPath(Arg(args, "--notebook-file"))) };
                    NotebookView.AutoRunAll = args.Contains("--run-cells");
                    NotebookView.ForceShowAI = args.Contains("--nb-agent");
                }
                NotebookView.ForceVars = args.Contains("--nb-vars");
                int nbScroll; if (int.TryParse(Arg(args, "--nb-scroll") ?? "", out nbScroll)) NotebookView.ScrollToCell = nbScroll;
                NotebookView.ForceAppMode = args.Contains("--nb-app");
                state.SwitchToMode(EditorMode.Notebook);
            }
            else if (mode == "welcome") { state.ShowingWelcomeHome = true; state.Notify("mode"); }
            if (args.Contains("--console")) { state.ConsoleVisible = true; state.Notify("console"); }
            if (snapshot != null && args.Contains("--seed-chat")) SeedChat(state);
            if (args.Contains("--nosidebar")) state.SidebarVisible = false;
            if (args.Contains("--no-autohide")) state.AutoHideTrafficLights = false;
            if (args.Contains("--show-menu")) win.ContentRendered += delegate { win.Dispatcher.BeginInvoke(new Action(() => { foreach (var c in ((System.Windows.Controls.Grid)win.Content).Children) if (c is MenuStrip) ((MenuStrip)c).Show(); })); };

            // --agent-bar plan | task[:N] | walkthrough | cells — open that agent surface; --expand-diffs opens change cards
            string barMode = snapshot != null ? Arg(args, "--agent-bar") : null;
            if (barMode != null)
            {
                if (barMode == "plan") AgentStore.TogglePlan();
                else if (barMode.StartsWith("task")) { int tab = 0; if (barMode.Contains(":")) int.TryParse(barMode.Substring(barMode.IndexOf(':') + 1), out tab); AgentStore.SelectTaskTab(tab); }
                else if (barMode == "walkthrough") AgentStore.SelectWalkthrough();
                else if (barMode == "cells") AgentStore.SelectCells();
            }
            if (snapshot != null && args.Contains("--expand-diffs")) DiffViews.ForceOpen = true;
            // --preview <file> (repeatable) opens files in the inspector's Preview tab; --inspector-tab context|preview|plan|tasks
            if (snapshot != null)
            {
                foreach (var pv in Args(args, "--preview")) PreviewDock.OpenFile(Path.GetFullPath(pv));
                string itab = Arg(args, "--inspector-tab");
                if (itab != null) PreviewDock.SelectTab(itab);
                // --web <url> [--web-viewport iphone|ipad|macbook|responsive]: open the WebApp preview (the page is captured
                // into the snapshot; --web-eval <file> also writes innerWidth / UA / touch read from the live page)
                string webUrl = Arg(args, "--web");
                if (webUrl != null) { WebAppPreview.Shared.Open(webUrl, Arg(args, "--web-viewport")); PreviewDock.SelectStandard("web"); }
                // --android-avd <name>: boot that AVD headless in the Android tab (use with --wait)
                string avd = Arg(args, "--android-avd");
                if (avd != null) { PreviewDock.SelectStandard("android"); win.ContentRendered += delegate { AndroidPreview.Shared.StartEmulator(avd); }; }
            }
            if (snapshot != null && agentPrompt != null)
                win.ContentRendered += delegate { win.Dispatcher.BeginInvoke(new Action(() => state.Notify("agent:send:" + agentPrompt)), System.Windows.Threading.DispatcherPriority.ApplicationIdle); };
            // --consensus-run "<request>" / --pns-launch "<objective>": press Run Consensus / Launch 24/7 once the window is up (test hooks)
            string consensusRun = snapshot != null ? Arg(args, "--consensus-run") : null, pnsLaunch = snapshot != null ? Arg(args, "--pns-launch") : null;
            if (consensusRun != null || pnsLaunch != null)
                win.ContentRendered += delegate
                {
                    win.Dispatcher.BeginInvoke(new Action(() =>
                    {
                        if (consensusRun != null) { var run = ConsensusEngine.Shared.Run(consensusRun, state.WorkspaceFolder); }
                        if (pnsLaunch != null && state.WorkspaceFolder != null) { var launch = PnsOrchestrator.Shared.DispatchMission(pnsLaunch, state.WorkspaceFolder, Pns.PolicyIsolated, null, true); }
                    }), System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                };

            // --split-diff <before> <after>: render the Split Diff window (test hook)
            int sd = Array.IndexOf(args, "--split-diff");
            if (snapshot != null && sd >= 0 && sd + 2 < args.Length)
                return Snapshot(app, DiffViews.SplitWindow(Path.GetFileName(args[sd + 2]), File.ReadAllText(args[sd + 1]), File.ReadAllText(args[sd + 2])), snapshot, Arg(args, "--size") ?? "1100x720", false);

            string settingsTab = Arg(args, "--settings-tab");
            if (snapshot != null && settingsTab != null) return Snapshot(app, new SettingsSheet(state, int.Parse(settingsTab)), snapshot, Arg(args, "--size") ?? "1000x700", false);
            if (snapshot != null) return Snapshot(app, win, snapshot, Arg(args, "--size") ?? "1440x900", args.Contains("--run"));
            app.Run(win);
            return 0;
        }

        static void SeedChat(AppState state)
        {
            var s = new ChatSession { Name = "Add a health check endpoint", ProjectPath = state.WorkspaceFolder, ProjectName = state.WorkspaceFolder != null ? Path.GetFileName(state.WorkspaceFolder) : null };
            s.Messages.Add(new ChatMessage { Role = "user", Content = "Add a /health endpoint to the API and show me how to test it." });
            var a = new ChatMessage { Role = "assistant", ThoughtSeconds = 4, Content = "<think>The API is a FastAPI app in main.py; add a lightweight route and verify it.</think>I added a **`/health`** endpoint to `main.py` that returns the service status.\n\n```python\n@app.get(\"/health\")\ndef health():\n    return {\"status\": \"ok\"}\n```\n\nTest it while the server is running:\n\n```bash\ncurl http://localhost:8000/health\n```\n\n| Check | Result |\n|---|---|\n| Route registered | yes |\n| Tests | 12 passed |" };
            string mainPy = state.WorkspaceFolder != null ? Path.Combine(state.WorkspaceFolder, "main.py") : "main.py";
            a.Steps.Add(new ToolStep { Name = "file_read", Target = "main.py#L1-20", Path = mainPy, Ok = true, Lines = 20, Result = "from fastapi import FastAPI\napp = FastAPI()" });
            a.Steps.Add(new ToolStep { Name = "file_write", Target = "main.py", Path = mainPy, Ok = true, Added = 4, Result = "Wrote 24 lines to main.py (previously 20 lines)." });
            a.Steps.Add(new ToolStep { Name = "shell", Target = "python -m pytest -q", Ok = true, Result = "exit code 0\n12 passed in 0.41s" });
            s.Messages.Add(a);
            AgentStore.Sessions.Insert(0, s);
            AgentStore.ActiveId = s.Id;
            AgentStore.Notify();
        }

        static readonly HashSet<string> ValueFlags = new HashSet<string> { "--snapshot", "--size", "--folder", "--file", "--mode", "--theme", "--preview", "--inspector-tab", "--wait", "--set", "--set-key", "--agent-prompt", "--agent-bar", "--settings-tab", "--data-dir", "--split-diff", "--pns-port", "--consensus-run", "--pns-launch", "--web", "--web-viewport", "--web-eval", "--android-avd", "--notebook-file", "--nb-scroll" };

        /// <summary>Arguments that are neither flags nor a flag's value — e.g. a file or folder passed by Explorer's Open with.</summary>
        static IEnumerable<string> Positional(string[] args)
        {
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i].StartsWith("--")) { if (ValueFlags.Contains(args[i])) i += args[i] == "--split-diff" ? 2 : 1; continue; }
                yield return args[i];
            }
        }

        static IEnumerable<string> Args(string[] args, string name)
        {
            for (int i = 0; i + 1 < args.Length; i++) if (args[i] == name) yield return args[i + 1];
        }

        static string Arg(string[] args, string name)
        {
            int i = Array.IndexOf(args, name);
            return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
        }

        static int Snapshot(Application app, Window win, string outPath, string size, bool runFirst)
        {
            var parts = size.Split('x');
            double w = double.Parse(parts[0]), h = double.Parse(parts[1]);
            win.Width = w; win.Height = h;
            win.Left = -20000; win.Top = -20000;
            win.ShowActivated = false;
            win.ShowInTaskbar = false;
            int code = 1;
            Action capture = null;
            win.ContentRendered += delegate
            {
                if (runFirst)
                {
                    // exercise Run (Ctrl+R) end-to-end, capture once the process has exited
                    AppState.Shared.RunCode();
                    var started = DateTime.Now;
                    var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
                    timer.Tick += delegate
                    {
                        if (AppState.Shared.IsRunning && (DateTime.Now - started).TotalSeconds < 20) return;
                        timer.Stop();
                        capture();
                    };
                    timer.Start();
                }
                else
                {
                    int wait = 0; int.TryParse(Arg(Environment.GetCommandLineArgs(), "--wait") ?? "0", out wait);
                    if (wait <= 0) { capture(); return; }
                    var waitTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(wait) };
                    waitTimer.Tick += delegate { waitTimer.Stop(); capture(); };
                    waitTimer.Start();
                }
            };
            bool webCaptured = false;
            byte[] webPng = null; Rect webRect = Rect.Empty;
            capture = delegate
            {
                win.Dispatcher.BeginInvoke(new Action(() =>
                {
                    // a WebView2 page is a child window RenderTargetBitmap cannot see: grab it first and paint it in place
                    if (!webCaptured && WebAppPreview.Created && WebAppPreview.Shared.HasPage)
                    {
                        webCaptured = true;
                        string evalOut = Arg(Environment.GetCommandLineArgs(), "--web-eval");
                        WebAppPreview.Shared.SnapshotLayer((FrameworkElement)win.Content, (png, rect, info) =>
                        {
                            webPng = png; webRect = rect;
                            if (evalOut != null && info != null) try { File.WriteAllText(evalOut, info); } catch (IOException ex) { System.Diagnostics.Debug.WriteLine("web-eval: " + ex.Message); }
                            capture();
                        });
                        return;
                    }
                    try
                    {
                        var root = (FrameworkElement)win.Content;
                        root.UpdateLayout();
                        double scale = 2.0; // Retina-equivalent capture for comparison with the macOS screenshots
                        var bmp = new RenderTargetBitmap((int)(root.ActualWidth * scale), (int)(root.ActualHeight * scale), 96 * scale, 96 * scale, PixelFormats.Pbgra32);
                        var dv = new DrawingVisual();
                        using (var dc = dv.RenderOpen())
                        {
                            dc.DrawRectangle(Theme.Current.WorkspaceBackground, null, new Rect(0, 0, root.ActualWidth, root.ActualHeight));
                            dc.DrawRectangle(new VisualBrush(root), null, new Rect(0, 0, root.ActualWidth, root.ActualHeight));
                            if (webPng != null && !webRect.IsEmpty)
                            {
                                var page = new BitmapImage();
                                using (var ms = new MemoryStream(webPng)) { page.BeginInit(); page.CacheOption = BitmapCacheOption.OnLoad; page.StreamSource = ms; page.EndInit(); }
                                dc.DrawImage(page, webRect);
                            }
                        }
                        bmp.Render(dv);
                        var enc = new PngBitmapEncoder();
                        enc.Frames.Add(BitmapFrame.Create(bmp));
                        using (var fs = File.Create(outPath)) enc.Save(fs);
                        code = 0;
                    }
                    catch (Exception ex) { try { File.AppendAllText(Path.Combine(Defaults.Dir, "crash.log"), DateTime.Now + " snapshot: " + ex + Environment.NewLine + Environment.NewLine); } catch { } }
                    app.Shutdown(code);
                }), DispatcherPriority.ApplicationIdle);
            };
            app.Run(win);
            return code;
        }
    }
}
