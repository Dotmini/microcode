// AgenticContextInspector + PreviewDockService (WorkspaceXcodeNavigatorAndInspector.swift, PreviewDockService.swift): the
// resizable right pane with Context · Preview · Plan · Tasks. Preview opens files the agent touched or the user clicked —
// code with syntax highlighting and line ranges, Markdown rendered (with LaTeX) or as source, images, PDF pages (native
// Windows.Data.Pdf), CSV/TSV tables, patches and the agent's own edit diffs.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public class PreviewItem
    {
        public string Id, Title, Path, Kind; // kind: web, ios, android, code, markdown, image, pdf, table, patch, diff, binary
        public int Start, End;
        public string Before, After;
        public bool ShowSource;
        /// <summary>Code/Markdown tab view: "preview" | "raw" | "diff" (null = the default for the file).</summary>
        public string View;
        public bool IsRuntime { get { return Kind == "web" || Kind == "ios" || Kind == "android"; } }

        /// <summary>PreviewDockService tab icons.</summary>
        public string Icon
        {
            get
            {
                switch (Kind)
                {
                    case "web": return "globe";
                    case "ios": return "iphone";
                    case "android": return "candybarphone";
                    case "image": return "photo";
                    case "pdf": return "doc.text.fill";
                    case "table": return "tablecells";
                    case "diff": case "patch": return "arrow.left.and.right.square";
                    case "binary": return "doc";
                    default: return "chevron.left.forwardslash.chevron.right";
                }
            }
        }
    }

    /// <summary>PreviewDockService: the dock's open tabs (runtime surfaces first, then files and diffs) and the inspector tab.</summary>
    public static class PreviewDock
    {
        public static readonly List<PreviewItem> Items = new List<PreviewItem>();
        public static PreviewItem Active;
        /// <summary>context | preview | plan | tasks</summary>
        public static string Tab = Defaults.Str("agenticInspectorTab", "context");
        public static double Width { get { return Defaults.Num("agenticInspectorWidth", 380); } set { Defaults.Set("agenticInspectorWidth", value); } }
        public static bool WebCreated { get { return WebAppPreview.Created; } }
        public static bool AndroidCreated { get { return AndroidPreview.Created; } }

        /// <summary>PreviewFileType.detect</summary>
        public static string Detect(string path) { return FileKinds.Detect(path); }

        static void Show(string tab)
        {
            Tab = tab;
            Defaults.Set("agenticInspectorTab", tab);
            var app = AppState.Shared;
            app.AgenticContextVisible = true;
            app.Notify("inspector");
        }

        public static void SelectTab(string tab) { Show(tab); }

        static readonly string[] RuntimeOrder = { "web", "ios", "android" };

        /// <summary>ensureStandardTabExists: the WebApp Preview / iOS Sim / Android Emu tab, created in its usual place.</summary>
        public static PreviewItem Standard(string kind)
        {
            var it = Items.FirstOrDefault(x => x.Kind == kind);
            if (it != null) return it;
            it = new PreviewItem { Id = kind, Kind = kind, Title = kind == "web" ? "WebApp Preview" : kind == "ios" ? "iOS Sim" : "Android Emu" };
            int rank = Array.IndexOf(RuntimeOrder, kind), at = 0;
            while (at < Items.Count && Items[at].IsRuntime && Array.IndexOf(RuntimeOrder, Items[at].Kind) < rank) at++;
            Items.Insert(at, it);
            return it;
        }

        /// <summary>ensureDefaultTabsIfEmpty</summary>
        public static void EnsureDefaultTabs()
        {
            if (Items.Count == 0) { Standard("web"); Standard("ios"); Standard("android"); }
            if (Active == null || !Items.Contains(Active)) Active = Items[0];
        }

        public static void SelectStandard(string kind)
        {
            if (Items.Count == 0) EnsureDefaultTabs();
            Active = Standard(kind);
            Show("preview");
        }

        /// <summary>pruneIdleRuntimePlaceholderTabsWhenOpeningDocument: runtime tabs that show nothing make room for documents.</summary>
        static void PruneIdleRuntimeTabs()
        {
            Items.RemoveAll(x => (x.Kind == "ios") || (x.Kind == "android" && !AndroidPreview.IsActive) || (x.Kind == "web" && !(WebAppPreview.Created && WebAppPreview.Shared.HasPage)));
        }

        /// <summary>openFile(url:startLine:endLine:)</summary>
        public static void OpenFile(string path, int start, int end)
        {
            if (string.IsNullOrEmpty(path)) return;
            try { path = System.IO.Path.GetFullPath(path); } catch (Exception ex) { System.Diagnostics.Debug.WriteLine("preview path: " + ex.Message); }
            string id = "file:" + path.ToLowerInvariant();
            var it = Items.FirstOrDefault(x => x.Id == id);
            if (it == null)
            {
                PruneIdleRuntimeTabs();
                it = new PreviewItem { Id = id, Path = path, Title = System.IO.Path.GetFileName(path), Kind = Detect(path) };
                Items.Add(it);
            }
            if (it.Start != start || it.End != end) it.View = null; // a new range re-picks the default view
            it.Start = start; it.End = end;
            if (it.Kind == "pdf") PdfRender.Forget(path);
            while (Items.Count(x => !x.IsRuntime) > 12) Items.Remove(Items.First(x => !x.IsRuntime && x != it));
            Active = it;
            Show("preview");
        }

        public static void OpenFile(string path) { OpenFile(path, 0, 0); }

        /// <summary>openDiff(id:title:oldContent:newContent:)</summary>
        public static void OpenDiff(string title, string before, string after)
        {
            string id = "diff:" + title + ":" + (before ?? "").GetHashCode() + ":" + (after ?? "").GetHashCode();
            var it = Items.FirstOrDefault(x => x.Id == id);
            if (it == null) { PruneIdleRuntimeTabs(); it = new PreviewItem { Id = id, Title = title, Kind = "diff", Before = before ?? "", After = after ?? "" }; Items.Add(it); }
            Active = it;
            Show("preview");
        }

        /// <summary>closeTab: closing the last tab brings the default runtime tabs back.</summary>
        public static void Close(PreviewItem it)
        {
            int i = Items.IndexOf(it);
            Items.Remove(it);
            if (it.Kind == "android" && AndroidPreview.Created) AndroidPreview.Shared.SetVisible(false);
            if (Active == it) Active = Items.Count == 0 ? null : Items[Math.Max(0, Math.Min(i, Items.Count - 1))];
            if (Items.Count == 0) EnsureDefaultTabs();
            AppState.Shared.Notify("inspector");
        }
    }

    /// <summary>AgenticContextInspector: resizable right pane (220…760pt) with Context · Preview · Plan · Tasks.</summary>
    public class ContextInspector : Border
    {
        readonly AppState _app;
        readonly IAgentHost _host;
        readonly Border _body = new Border(), _headerHost = new Border();
        PreviewDockView _dock;

        /// <summary>Re-renders the tab bar and the body in place: the pane, the dock and the live web / emulator surfaces
        /// inside it survive, so a page keeps its state while the rest of the window changes.</summary>
        public void Rebuild()
        {
            _headerHost.Child = Header();
            RenderBody();
        }

        public ContextInspector(AppState app) : this(app, null) { }

        public ContextInspector(AppState app, IAgentHost host)
        {
            _app = app; _host = host;
            var t = Theme.Current;
            Background = t.PanelBackground;
            Width = Clamp(PreviewDock.Width);
            var root = new Grid();
            root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(6) });
            root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            // NativePaneResizeSplitter on the leading edge: drag to resize, double-click to reset, drag under 120pt to hide
            var grip = new Border { Background = Brushes.Transparent, Cursor = Cursors.SizeWE, Child = new Border { Width = 1, Background = t.Separator, HorizontalAlignment = HorizontalAlignment.Left } };
            double startX = 0, startW = 0;
            grip.MouseLeftButtonDown += (s, e) =>
            {
                if (e.ClickCount == 2) { Width = 380; PreviewDock.Width = 380; e.Handled = true; return; }
                startX = e.GetPosition(Application.Current.MainWindow).X; startW = ActualWidth; grip.CaptureMouse(); e.Handled = true;
            };
            grip.MouseMove += (s, e) =>
            {
                if (!grip.IsMouseCaptured) return;
                double w = startW - (e.GetPosition(Application.Current.MainWindow).X - startX);
                Width = Math.Max(120, Math.Min(MaxPaneWidth(), w));
            };
            grip.MouseLeftButtonUp += (s, e) =>
            {
                if (!grip.IsMouseCaptured) return;
                grip.ReleaseMouseCapture();
                if (ActualWidth < 200) { _app.AgenticContextVisible = false; _app.Notify("inspector"); return; }
                PreviewDock.Width = Clamp(ActualWidth); Width = PreviewDock.Width;
            };
            root.Children.Add(grip);
            var col = new DockPanel();
            Grid.SetColumn(col, 1);
            _headerHost.Child = Header();
            DockPanel.SetDock(_headerHost, Dock.Top);
            col.Children.Add(_headerHost);
            col.Children.Add(_body);
            root.Children.Add(col);
            Child = root;
            RenderBody();

            // Context, Plan and Tasks follow the running agent and open files (coalesced, only when their content
            // changed); Preview keeps its document steady. Static events are dropped on Unloaded so panes don't leak.
            var refresh = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(350) };
            refresh.Tick += delegate { refresh.Stop(); Refresh(); };
            Action poke = () => Dispatcher.BeginInvoke(new Action(() => { if (PreviewDock.Tab != "preview" && !refresh.IsEnabled) refresh.Start(); }));
            Action<string> appChanged = what => { if (what == "files" || what == "dirty" || what == "workspace") poke(); };
            Loaded += delegate { AgentStore.Changed -= poke; AgentStore.Changed += poke; _app.Changed -= appChanged; _app.Changed += appChanged; };
            Unloaded += delegate { AgentStore.Changed -= poke; _app.Changed -= appChanged; refresh.Stop(); };
        }

        string _sig;

        /// <summary>What the current tab shows, so a refresh only rebuilds when something visible changed.</summary>
        string Signature()
        {
            var s = AgentStore.Active;
            switch (PreviewDock.Tab)
            {
                case "context":
                    return "c|" + string.Join(",", _app.OpenFiles.Select(f => f.Path + (f.IsUnsaved ? "*" : ""))) + "|" + (s == null ? "" : s.Id + ":" + s.Messages.Count + ":" + s.Messages.Sum(m => m.Steps == null ? 0 : m.Steps.Count) + ":" +s.Messages.Sum(m => m.Steps == null ? 0 : m.Steps.Count(x => x.Reverted)));
                case "tasks":
                    return "t|" + _taskSub + "|" + (_app.WorkspaceFolder == null ? "" : TaskFiles.Read(_app.WorkspaceFolder, _taskSub == 0 ? "task.md" : "walkthrough.md"));
                default:
                    return null;
            }
        }

        void Refresh()
        {
            if (PreviewDock.Tab == "plan") { if (_plan != null) _plan.Render(); else RenderBody(); return; }
            string sig = Signature();
            if (sig != null && sig != _sig) RenderBody();
        }

        double MaxPaneWidth()
        {
            // before the window has been laid out (ActualWidth 0) only the pane's own cap applies
            var win = Application.Current != null ? Application.Current.MainWindow : null;
            double w = win != null && win.ActualWidth > 0 ? win.ActualWidth : 0;
            double cap = PreviewDock.Tab == "preview" ? 760 : 640;
            if (w <= 0) return cap;
            return Math.Max(260, Math.Min(cap, w - (_app.SidebarVisible ? _app.SidebarWidth : 0) - 380));
        }

        double Clamp(double w) { return Math.Max(220, Math.Min(MaxPaneWidth(), w)); }

        UIElement Header()
        {
            var t = Theme.Current;
            var row = V.H(4);
            Action<string, string, string> tab = (id, icon, label) =>
            {
                bool on = PreviewDock.Tab == id;
                var b = V.Button(V.Box(V.H(4, Sym.Icon(icon, 10.5, on ? t.Primary : t.Secondary), V.T(label, 11, on ? FontWeights.SemiBold : FontWeights.Medium, on ? t.Primary : t.Secondary)), V.P(8, 4), on ? t.P(0.10) : Brushes.Transparent, 5), () => PreviewDock.SelectTab(id));
                if (!on) b.OnState = x => ((Border)x.Child).Background = x.IsHover ? t.P(0.05) : Brushes.Transparent;
                row.Children.Add(b);
            };
            tab("context", "sidebar.right", "Context");
            tab("preview", "doc.text", "Preview");
            tab("plan", "doc.text.magnifyingglass", "Plan");
            tab("tasks", "checklist", "Tasks");
            row.Children.Add(V.Sp());
            var close = V.Button(V.Box(Sym.Icon("xmark", 9.5, t.Secondary, FontWeights.Bold), V.P(5), Brushes.Transparent, 4), () => { _app.AgenticContextVisible = false; _app.Notify("inspector"); });
            close.ToolTip = "Hide Inspector (Ctrl+I)";
            row.Children.Add(close);
            var box = V.VLead(0, V.Self(V.Box(row, V.P(8, 5), null, 0), Cross.Stretch), V.Self(new Border { Height = 1, Background = t.Separator }, Cross.Stretch));
            box.Align = Cross.Stretch;
            return box;
        }

        void RenderBody()
        {
            _sig = Signature();
            switch (PreviewDock.Tab)
            {
                case "preview": _body.Child = PreviewBody(); break;
                case "plan": _body.Child = PlanBody(); break;
                case "tasks": _body.Child = TasksBody(); break;
                default: _body.Child = ContextBody(); break;
            }
        }

        // ── Context ──
        UIElement ContextBody()
        {
            var t = Theme.Current;
            var list = V.VLead(4); list.Align = Cross.Stretch;
            Action<string> section = title => list.Children.Add(V.Box(V.T(title, 10, FontWeights.SemiBold, t.Secondary), V.P(6, 10, 6, 2), null, 0));
            Action<string, string> fileRow = (path, badge) =>
            {
                string name = System.IO.Path.GetFileName(path);
                var row = V.H(6, Sym.Icon(FileTreeView.IconName(name, false), 11, FileTreeView.IconColor(name, false)), V.Shrink(V.T(name, 12, FontWeights.Normal, t.Primary)));
                var rel = V.T(AgentRunner.DisplayPath(path), 10, FontWeights.Normal, t.S(0.6)); rel.TextTrimming = TextTrimming.CharacterEllipsis;
                row.Children.Add(V.Shrink(rel));
                row.Children.Add(V.Sp());
                if (badge != null) row.Children.Add(V.Box(V.T(badge, 9, FontWeights.SemiBold, t.Secondary), V.P(5, 1), t.P(0.06), 4));
                var b = V.Button(V.Box(row, V.P(6, 4), Brushes.Transparent, 5), () => PreviewDock.OpenFile(path));
                b.OnState = x => ((Border)x.Child).Background = x.IsHover ? t.P(0.05) : Brushes.Transparent;
                b.ToolTip = path;
                list.Children.Add(V.Self(b, Cross.Stretch));
            };
            section("OPEN FILES");
            var open = _app.OpenFiles.Where(f => f.Path != null).ToList();
            if (open.Count == 0) list.Children.Add(V.Box(V.T("No files open", 11.5, FontWeights.Normal, t.S(0.7)), V.P(6, 2), null, 0));
            foreach (var f in open) fileRow(f.Path, f.IsUnsaved ? "unsaved" : null);
            var s = AgentStore.Active;
            var touched = new List<KeyValuePair<string, string>>();
            if (s != null)
                foreach (var st in s.Messages.SelectMany(m => m.Steps).Reverse())
                {
                    if (st.Name != "file_read" && !AgentRunner.IsFileEdit(st.Name)) continue;
                    string p = st.Path;
                    if (string.IsNullOrEmpty(p)) continue;
                    if (!System.IO.Path.IsPathRooted(p) && _app.WorkspaceFolder != null) p = System.IO.Path.Combine(_app.WorkspaceFolder, p.Split('#')[0].Replace('/', '\\'));
                    if (touched.Any(k => string.Equals(k.Key, p, StringComparison.OrdinalIgnoreCase))) continue;
                    touched.Add(new KeyValuePair<string, string>(p, st.Name == "file_read" ? "read" : st.Reverted ? "reverted" : "edited"));
                }
            section("AGENT CONTEXT");
            if (touched.Count == 0) list.Children.Add(V.Box(V.T("Files the agent reads or edits in this chat appear here.", 11.5, FontWeights.Normal, t.S(0.7)), V.P(6, 2), null, 0));
            foreach (var kv in touched.Take(40)) fileRow(kv.Key, kv.Value);
            var att = s == null ? new List<string>() : s.Messages.SelectMany(m => m.Attachments ?? new List<string>()).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            if (att.Count > 0) { section("ATTACHMENTS"); foreach (var a in att) fileRow(a, AgentRunner.IsImage(a) ? "image" : null); }
            if (_app.WorkspaceFolder != null)
            {
                section("RULES & SKILLS");
                string rules = System.IO.Path.Combine(_app.WorkspaceFolder, ".microcode", "rules.md");
                if (File.Exists(rules)) fileRow(rules, "rules");
                if (TaskFiles.Exists(_app.WorkspaceFolder, "agent.md")) fileRow(TaskFiles.PathFor(_app.WorkspaceFolder, "agent.md"), "spec");
                // rule files the agent imports from other platforms (AGENTS.md, CLAUDE.md, .cursorrules …)
                foreach (var r in RulesEngine.ScanRules(_app.WorkspaceFolder).Where(r => !r.RelativePath.StartsWith("~") && r.RelativePath != ".microcode/rules.md" && r.RelativePath != ".microcode/agent.md"))
                {
                    string rp = System.IO.Path.Combine(_app.WorkspaceFolder, r.RelativePath.Replace('/', '\\'));
                    if (File.Exists(rp)) fileRow(rp, r.Badge.ToLowerInvariant());
                }
                int hooks = RulesEngine.ScanHooks(_app.WorkspaceFolder, null).Count;
                if (hooks > 0)
                {
                    var hookRow = V.Box(V.T(hooks + " lifecycle hook" + (hooks == 1 ? "" : "s") + " · run once you trust this workspace", 11.5, FontWeights.Normal, t.S(0.75)), V.P(6, 2), null, 0);
                    hookRow.ToolTip = "pre_tool / post_tool / pre_finish hooks from .microcode/hooks.json, .cursor/hooks.json or .claude/settings.json";
                    list.Children.Add(hookRow);
                }
                int skills = SkillStore.Skills.Count(k => k.Enabled);
                list.Children.Add(V.Box(V.T(skills + " active skill" + (skills == 1 ? "" : "s") + " available to the agent", 11.5, FontWeights.Normal, t.S(0.75)), V.P(6, 2), null, 0));
            }
            return new ScrollViewer { Content = new Border { Child = list, Padding = new Thickness(8, 4, 8, 16) }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        }

        // ── Plan / Tasks ──
        UIElement PlanBody()
        {
            if (_host == null) return PanelUI.Empty("doc.text.magnifyingglass", "Open the AI Agent to see its plan", null);
            _plan = new PlanPanel(_host);
            _plan.CloseRequested += () => PreviewDock.SelectTab("context");
            return _plan;
        }

        PlanPanel _plan;

        int _taskSub;
        UIElement TasksBody()
        {
            var t = Theme.Current;
            string ws = _app.WorkspaceFolder;
            if (ws == null) return PanelUI.Empty("checklist", "Open a project folder", "task.md and walkthrough.md are kept per workspace.");
            var seg = V.H(1);
            Action<int, string> segBtn = (i, label) =>
            {
                bool on = _taskSub == i;
                seg.Children.Add(V.Button(V.Box(V.T(label, 10.5, on ? FontWeights.SemiBold : FontWeights.Medium, on ? t.Primary : t.Secondary), V.P(8, 3), on ? t.P(0.12) : Brushes.Transparent, 4), () => { _taskSub = i; RenderBody(); }));
            };
            segBtn(0, "Task"); segBtn(1, "Walkthrough");
            var full = PanelUI.Small("arrow.up.right.square", "Open Task Editor", () => { _app.SwitchToMode(EditorMode.AIAgent); AgentStore.SelectTaskTab(_taskSub == 0 ? 0 : 2); });
            var bar = V.H(8, V.Box(seg, V.P(2), t.P(0.04), 5), V.Sp(), PanelUI.Small("arrow.clockwise", null, RenderBody), full);
            string name = _taskSub == 0 ? "task.md" : "walkthrough.md";
            string md = TaskFiles.Read(ws, name);
            UIElement content = string.IsNullOrWhiteSpace(md)
                ? PanelUI.Empty(_taskSub == 0 ? "checklist" : "doc.text.magnifyingglass", _taskSub == 0 ? "No task.md yet" : "No walkthrough generated yet", _taskSub == 0 ? "The agent creates .microcode/task.md for multi-step work, or write one in the Task editor." : "Once the Agent executes steps and produces walkthrough.md, the summary will render here.")
                : PanelUI.Md(md, 12.5);
            var col = V.VLead(10, V.Self(bar, Cross.Stretch), V.Self(content, Cross.Stretch));
            col.Align = Cross.Stretch;
            return new ScrollViewer { Content = new Border { Child = col, Padding = new Thickness(12, 10, 12, 16) }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        }

        // ── Preview: EmbeddedDeviceDockView ──
        UIElement PreviewBody()
        {
            if (_dock == null) _dock = new PreviewDockView(_app);
            else _dock.Refresh();
            return _dock;
        }
    }

    /// <summary>PreviewDock renderers shared by the Preview pane and the editor: images, PDF pages (Windows.Data.Pdf),
    /// CSV/TSV tables, patches, rendered Markdown and a binary-file card. Nothing here ever writes to the file.</summary>
    public static partial class FilePreview
    {
        public static UIElement For(string path, string kind)
        {
            try
            {
                switch (kind)
                {
                    case "image": return Image(path);
                    case "pdf": return Pdf(path);
                    case "table": return Table(path);
                    case "patch": return Patch(path);
                    case "markdown": return Markdown(path, 13, new Thickness(16, 12, 16, 20));
                    default: return Binary(path);
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine("preview " + kind + ": " + ex);
                return PanelUI.Empty("exclamationmark.triangle", "Could not preview this file", ex.Message);
            }
        }

        /// <summary>Types Windows would execute rather than display; previews never launch these.</summary>
        static readonly HashSet<string> Runnable = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".exe", ".com", ".bat", ".cmd", ".ps1", ".psm1", ".vbs", ".vbe", ".js", ".jse", ".wsf", ".wsh", ".msi", ".msp", ".scr", ".lnk", ".url", ".hta", ".jar", ".reg", ".cpl", ".pif", ".application", ".appref-ms", ".sh", ".py", ".pyw" };

        public static bool IsRunnable(string path) { return Runnable.Contains(System.IO.Path.GetExtension(path ?? "")); }

        public static void Shell(string file, string args)
        {
            try { if (args == null) System.Diagnostics.Process.Start(file); else System.Diagnostics.Process.Start(file, args); }
            catch (Exception ex) { System.Diagnostics.Debug.WriteLine("preview open: " + ex.Message); }
        }

        public static void Reveal(string path) { Shell("explorer.exe", "/select,\"" + path + "\""); }

        /// <summary>Reads at most <paramref name="maxChars"/> characters (BOM-aware), sharing the file with writers.</summary>
        public static string ReadHead(string path, int maxChars)
        {
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var sr = new StreamReader(fs, Encoding.UTF8, true))
            {
                var buf = new char[Math.Min(maxChars, (int)Math.Min(int.MaxValue, Math.Max(1, fs.Length)))];
                int n = sr.ReadBlock(buf, 0, buf.Length);
                string s = new string(buf, 0, n);
                if (!sr.EndOfStream) s += "\n… (preview shows the first " + Size(maxChars) + ")";
                return s;
            }
        }

        public static string Size(long n) { return n >= 1048576 ? (n / 1048576.0).ToString("0.0", CultureInfo.InvariantCulture) + " MB" : n >= 1024 ? (n / 1024.0).ToString("0.0", CultureInfo.InvariantCulture) + " KB" : n + " B"; }

        static Brush Checker()
        {
            var g = new DrawingGroup();
            g.Children.Add(new GeometryDrawing(new SolidColorBrush(Color.FromRgb(58, 58, 60)), null, new RectangleGeometry(new Rect(0, 0, 16, 16))));
            g.Children.Add(new GeometryDrawing(new SolidColorBrush(Color.FromRgb(72, 72, 74)), null, new GeometryGroup { Children = { new RectangleGeometry(new Rect(0, 0, 8, 8)), new RectangleGeometry(new Rect(8, 8, 8, 8)) } }));
            return new DrawingBrush(g) { TileMode = TileMode.Tile, Viewport = new Rect(0, 0, 16, 16), ViewportUnits = BrushMappingMode.Absolute };
        }

        public static UIElement Markdown(string path, double size, Thickness padding)
        {
            // relative links and images resolve against the document's own folder
            var md = MarkdownView.Render(ReadHead(path, 4000000), size, System.IO.Path.GetDirectoryName(path));
            var box = md as Border;
            if (box != null) box.Padding = new Thickness(0);
            return new ScrollViewer { Content = new Border { Child = md, Padding = padding }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        }

        public static UIElement Image(string path)
        {
            var t = Theme.Current;
            var fi = new FileInfo(path);
            var bmp = new BitmapImage();
            bmp.BeginInit(); bmp.CacheOption = BitmapCacheOption.OnLoad; bmp.CreateOptions = BitmapCreateOptions.IgnoreImageCache; bmp.UriSource = new Uri(path); bmp.EndInit();
            var img = new System.Windows.Controls.Image { Source = bmp, Stretch = Stretch.Uniform, MaxWidth = bmp.PixelWidth, MaxHeight = bmp.PixelHeight, HorizontalAlignment = HorizontalAlignment.Center };
            RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
            var info = V.T(bmp.PixelWidth + " × " + bmp.PixelHeight + " px · " + Size(fi.Length), 10.5, FontWeights.Normal, t.Secondary);
            info.HorizontalAlignment = HorizontalAlignment.Center;
            var col = V.Vs(10, new Border { Child = img, Background = Checker(), CornerRadius = new CornerRadius(4), HorizontalAlignment = HorizontalAlignment.Center }, info);
            return new ScrollViewer { Content = new Border { Child = col, Padding = new Thickness(12) }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        }

        public static UIElement Patch(string path)
        {
            var res = new DiffResult();
            foreach (var raw in ReadHead(path, 2000000).Replace("\r\n", "\n").Split('\n'))
            {
                if (raw.StartsWith("@@")) res.Lines.Add(new DiffLine { Kind = DiffKind.Hunk, Text = raw });
                else if (raw.StartsWith("+") && !raw.StartsWith("+++")) { res.Lines.Add(new DiffLine { Kind = DiffKind.Add, Text = raw.Substring(1) }); res.Added++; }
                else if (raw.StartsWith("-") && !raw.StartsWith("---")) { res.Lines.Add(new DiffLine { Kind = DiffKind.Del, Text = raw.Substring(1) }); res.Removed++; }
                else res.Lines.Add(new DiffLine { Kind = DiffKind.Context, Text = raw.StartsWith(" ") ? raw.Substring(1) : raw });
            }
            return new ScrollViewer { Content = DiffViews.Section(res), VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        }

        public static UIElement Binary(string path)
        {
            var t = Theme.Current;
            var fi = new FileInfo(path);
            bool runnable = IsRunnable(path);
            var col = V.Vs(8, Sym.Icon("doc", 28, t.S(0.5)), V.T(System.IO.Path.GetFileName(path), 13, FontWeights.SemiBold, t.Primary),
                V.T(Size(fi.Length) + " · modified " + fi.LastWriteTime.ToString("MMM d, yyyy HH:mm", CultureInfo.InvariantCulture), 11, FontWeights.Normal, t.Secondary),
                V.T(runnable ? "This file can run code, so it is not opened from here." : "Binary file — open it with its default app.", 11, FontWeights.Normal, t.S(0.7)),
                runnable ? PanelUI.Small("folder", "Reveal in File Explorer", () => Reveal(path)) : PanelUI.Small("arrow.up.right.square", "Open with Default App", () => Shell(path, null)));
            col.Margin = new Thickness(0, 40, 0, 0);
            return col;
        }

        public static UIElement Table(string path) { return TableText(ReadHead(path, 4000000), path.EndsWith(".tsv", StringComparison.OrdinalIgnoreCase)); }

        /// <summary>Spreadsheet preview of CSV/TSV text: row numbers, header row, numbers right-aligned, first 500 rows.</summary>
        public static UIElement TableText(string text, bool tsv)
        {
            var t = Theme.Current;
            char sep = tsv ? '\t' : ',';
            var rows = new List<List<string>>();
            foreach (var line in (text ?? "").Replace("\r\n", "\n").Split('\n'))
            {
                if (rows.Count >= 501) break;
                if (line.Length == 0) continue;
                rows.Add(ParseCsvLine(line, sep));
            }
            if (rows.Count == 0) return PanelUI.Empty("tablecells", "Empty table", null);
            int cols = Math.Min(40, rows.Max(r => r.Count));
            var grid = new Grid();
            for (int c = 0; c <= cols; c++) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            for (int r = 0; r < rows.Count; r++)
            {
                grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                var num = V.Box(V.Mono(r == 0 ? "" : r.ToString(), 9.5, FontWeights.Normal, t.S(0.55)), V.P(6, 3), t.P(r == 0 ? 0.06 : 0.025), 0, t.P(0.08), 0.5);
                Grid.SetRow(num, r); grid.Children.Add(num);
                for (int c = 0; c < cols; c++)
                {
                    string v = c < rows[r].Count ? rows[r][c] : "";
                    var tb = V.T(v.Length > 80 ? v.Substring(0, 80) + "…" : v, 11, r == 0 ? FontWeights.SemiBold : FontWeights.Normal, r == 0 ? t.Primary : t.P(0.9));
                    double dummy;
                    if (r > 0 && double.TryParse(v, NumberStyles.Float, CultureInfo.InvariantCulture, out dummy)) tb.HorizontalAlignment = HorizontalAlignment.Right;
                    var cell = V.Box(tb, V.P(8, 3), r == 0 ? t.P(0.06) : Brushes.Transparent, 0, t.P(0.08), 0.5);
                    Grid.SetRow(cell, r); Grid.SetColumn(cell, c + 1); grid.Children.Add(cell);
                }
            }
            var note = V.T((rows.Count - 1) + " rows" + (rows.Count >= 501 ? " (first 500 shown)" : "") + " · " + cols + " columns", 10.5, FontWeights.Normal, t.Secondary);
            var col = V.VLead(8, note, new ScrollViewer { Content = grid, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled });
            return new ScrollViewer { Content = new Border { Child = col, Padding = new Thickness(10) }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        }

        static List<string> ParseCsvLine(string line, char sep)
        {
            var cells = new List<string>(); var sb = new StringBuilder(); bool q = false;
            for (int i = 0; i < line.Length; i++)
            {
                char ch = line[i];
                if (q) { if (ch == '"') { if (i + 1 < line.Length && line[i + 1] == '"') { sb.Append('"'); i++; } else q = false; } else sb.Append(ch); }
                else if (ch == '"') q = true;
                else if (ch == sep) { cells.Add(sb.ToString()); sb.Clear(); }
                else sb.Append(ch);
            }
            cells.Add(sb.ToString());
            return cells;
        }

        class PdfSlot
        {
            public int Index;
            public Viewbox Host;
            public Border Card;
            public double W, H;
            public bool Rendered, Busy;
        }

        /// <summary>PDFKit-style continuous view: every page gets a placeholder of its real size, and only pages near the
        /// viewport are rendered (at the displayed width × DPI); pages far off-screen drop their bitmaps to bound memory.</summary>
        public static UIElement Pdf(string path)
        {
            var t = Theme.Current;
            var pages = new StackPanel();
            var status = V.T("Loading PDF…", 10.5, FontWeights.Normal, t.Secondary);
            status.Margin = new Thickness(0, 0, 0, 8);
            pages.Children.Add(status);
            var sv = new ScrollViewer { Content = new Border { Child = pages, Padding = new Thickness(12) }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, Background = t.P(0.03) };
            var slots = new List<PdfSlot>();
            bool rendering = false;
            Action update = null;
            Func<UIElement> blank = () => new System.Windows.Shapes.Rectangle { Fill = Brushes.White };
            update = async () =>
            {
                if (rendering || slots.Count == 0 || !sv.IsLoaded) return;
                double view = sv.ViewportHeight, keep = view * 4;
                PdfSlot next = null;
                foreach (var s in slots)
                {
                    double top;
                    try { top = s.Card.TranslatePoint(new Point(0, 0), sv).Y; }
                    catch (InvalidOperationException) { continue; } // not in the tree (pane re-rendered)
                    double bottom = top + s.Card.ActualHeight;
                    bool near = bottom > -view * 0.5 && top < view * 1.5;
                    if (near && !s.Rendered && !s.Busy && next == null) next = s;
                    if (s.Rendered && (bottom < -keep || top > view + keep)) { s.Host.Child = blank(); ((FrameworkElement)s.Host.Child).Width = s.W; ((FrameworkElement)s.Host.Child).Height = s.H; s.Rendered = false; }
                }
                if (next == null) return;
                rendering = true; next.Busy = true;
                try
                {
                    var src = PresentationSource.FromVisual(sv);
                    double dpi = src != null && src.CompositionTarget != null ? src.CompositionTarget.TransformToDevice.M11 : 1;
                    double shown = Math.Max(300, next.Card.ActualWidth) * Math.Max(1, dpi);
                    uint px = (uint)Math.Min(2400, Math.Max(600, Math.Ceiling(shown / 200) * 200));
                    var bytes = await PdfRender.Page(path, next.Index, px);
                    var bmp = new BitmapImage();
                    using (var ms = new MemoryStream(bytes)) { bmp.BeginInit(); bmp.CacheOption = BitmapCacheOption.OnLoad; bmp.StreamSource = ms; bmp.EndInit(); }
                    bmp.Freeze();
                    var img = new System.Windows.Controls.Image { Source = bmp, Width = next.W, Height = next.H, Stretch = Stretch.Fill };
                    RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
                    next.Host.Child = img;
                    next.Rendered = true;
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine("pdf page " + (next.Index + 1) + ": " + ex.Message);
                    next.Rendered = true; // leave the blank page rather than retrying forever
                }
                finally { next.Busy = false; rendering = false; }
                update(); // continue with the next visible page
            };
            // start once the view is in the tree: the awaits then resume on the UI dispatcher (an early start from
            // startup code has no SynchronizationContext and would touch the controls from a pool thread)
            bool started = false;
            sv.Loaded += async delegate
            {
                if (started) { update(); return; }
                started = true;
                try
                {
                    var sizes = await PdfRender.PageSizes(path, 400);
                    status.Text = sizes.Count + " page" + (sizes.Count == 1 ? "" : "s") + " · " + System.IO.Path.GetFileName(path);
                    for (int i = 0; i < sizes.Count; i++)
                    {
                        var ph = (FrameworkElement)blank();
                        ph.Width = sizes[i].Width; ph.Height = sizes[i].Height;
                        var host = new Viewbox { Stretch = Stretch.Uniform, Child = ph };
                        var card = new Border { Child = host, Background = Brushes.White, MaxWidth = 1000, HorizontalAlignment = HorizontalAlignment.Stretch, Margin = new Thickness(0, 0, 0, 6), Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 6, ShadowDepth = 1, Opacity = 0.3 } };
                        pages.Children.Add(card);
                        var label = V.T("Page " + (i + 1) + " / " + sizes.Count, 9.5, FontWeights.Normal, t.S(0.6));
                        label.HorizontalAlignment = HorizontalAlignment.Center;
                        label.Margin = new Thickness(0, 0, 0, 10);
                        pages.Children.Add(label);
                        slots.Add(new PdfSlot { Index = i, Host = host, Card = card, W = sizes[i].Width, H = sizes[i].Height });
                    }
                    var queued = sv.Dispatcher.BeginInvoke(new Action(() => update()), System.Windows.Threading.DispatcherPriority.Loaded); // after layout, so page positions are known
                }
                catch (Exception ex)
                {
                    status.Text = "Could not render this PDF: " + ex.GetBaseException().Message;
                }
            };
            sv.ScrollChanged += delegate { update(); };
            return sv;
        }
    }
}
