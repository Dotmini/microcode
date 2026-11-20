// The file tabs of the Preview dock, ported from InteractiveCodePreviewView / InteractivePDFPreviewView /
// InteractiveImagePreviewView / InteractiveDiffPreviewView: each has the macOS sub-header bar (breadcrumb, Preview/Raw,
// Live Preview, Git Diff, Copy, Open in Editor · page count + Continuous/Single Page · zoom −/%/+/Fit · ⋯ menu) and
// reloads by itself when the file changes on disk (editor save or an agent edit).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

using System.Windows.Threading;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public static partial class FilePreview
    {
        /// <summary>A dock tab's content with its macOS sub-header.</summary>
        public static UIElement ForItem(PreviewItem it, AppState app)
        {
            if (it.Kind == "diff") return DiffPanel(it.Title, it.Before ?? "", it.After ?? "");
            if (string.IsNullOrEmpty(it.Path) || !File.Exists(it.Path)) return PanelUI.Empty("questionmark.circle", "File not found", it.Path);
            try
            {
                switch (it.Kind)
                {
                    case "image": return new ImagePreview(it.Path, app);
                    case "pdf": return new PdfPreview(it.Path);
                    case "table": return Framed(Header(Pill("tablecells", Path.GetFileName(it.Path)), V.Sp(), OpenButton(it.Path), More(it.Path, null)), Table(it.Path));
                    case "patch": return PatchPanel(it.Path);
                    case "code": case "markdown": return new CodePreview(it, app);
                    default: return Framed(Header(Pill("doc", Size(new FileInfo(it.Path).Length)), V.Sp(), More(it.Path, null)), Binary(it.Path));
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine("preview " + it.Kind + ": " + ex);
                return Framed(Header(Pill("exclamationmark.triangle", "Cannot Preview File")), PanelUI.Empty("exclamationmark.triangle", "Cannot Preview File", ex.Message));
            }
        }

        // ── sub-header pieces ──

        internal static Border Header(params UIElement[] items) { return HeaderInto(new Border(), items); }

        /// <summary>Styles <paramref name="target"/> as a sub-header bar and fills it with the items.</summary>
        internal static Border HeaderInto(Border target, params UIElement[] items)
        {
            var t = Theme.Current;
            target.Child = V.H(8, items);
            target.Padding = new Thickness(10, 5, 10, 5);
            target.Background = t.PanelBackground;
            target.BorderBrush = t.Separator;
            target.BorderThickness = new Thickness(0, 0, 0, 1);
            return target;
        }

        internal static DockPanel Framed(Border header, UIElement content)
        {
            var d = new DockPanel { Background = Theme.Current.EditorBackground };
            DockPanel.SetDock(header, Dock.Top);
            d.Children.Add(header);
            d.Children.Add(content);
            return d;
        }

        internal static UIElement Pill(string icon, string text)
        {
            var t = Theme.Current;
            var label = V.T(text, 10, FontWeights.Medium, t.Secondary);
            label.TextTrimming = TextTrimming.CharacterEllipsis;
            return V.Shrink(V.Box(V.H(5, Sym.Icon(icon, 11, t.Secondary), V.Shrink(label)), V.P(8, 4), t.P(0.05), 4));
        }

        internal static Btn Tool(string icon, string tip, Action a)
        {
            var t = Theme.Current;
            var b = V.Button(V.Size(V.Box(Sym.Icon(icon, 11, t.Secondary), V.P(0), Brushes.Transparent, 4), 22, 22), a);
            b.ToolTip = tip;
            b.OnState = x => ((Border)((FrameworkElement)x.Child)).Background = x.IsHover ? t.P(0.08) : Brushes.Transparent;
            return b;
        }

        internal static Btn OpenButton(string path)
        {
            var t = Theme.Current;
            if (IsRunnable(path)) return Tool("folder", "Reveal in File Explorer", () => Reveal(path));
            var b = V.Button(V.Box(V.T("Open", 10, FontWeights.Medium, t.Primary), V.P(8, 2.5), t.P(0.06), 4, t.P(0.14), 0.8), () => Shell(path, null));
            b.ToolTip = "Open with the default app";
            return b;
        }

        /// <summary>The ⋯ menu: Reveal in File Explorer, Copy File Path (+ view-specific items first).</summary>
        internal static Btn More(string path, List<MenuItemSpec> extra)
        {
            var t = Theme.Current;
            var b = V.Button(V.Size(V.Box(Sym.Icon("ellipsis", 10, t.Secondary), V.P(0), Brushes.Transparent, 4), 20, 20), null);
            b.MenuAlignRight = true;
            b.MenuItems = () =>
            {
                var items = new List<MenuItemSpec>();
                if (extra != null && extra.Count > 0) { items.AddRange(extra); items.Add(MenuItemSpec.Sep()); }
                items.Add(MenuItemSpec.Item("Reveal in File Explorer", "folder", () => Reveal(path)));
                items.Add(MenuItemSpec.Item("Copy File Path", "doc.on.doc", () => CopyText(path)));
                if (!IsRunnable(path)) items.Add(MenuItemSpec.Item("Open in Default App", "arrow.up.right.square", () => Shell(path, null)));
                return items;
            };
            return b;
        }

        internal static void CopyText(string s) { try { Clipboard.SetText(s ?? ""); } catch (System.Runtime.InteropServices.ExternalException ex) { Debug.WriteLine("clipboard: " + ex.Message); } }

        /// <summary>Runs a callback (on the UI thread, debounced) whenever the file changes on disk; stops when the view unloads.</summary>
        internal static void WatchFile(FrameworkElement owner, string path, Action changed)
        {
            FileSystemWatcher w = null;
            var debounce = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) };
            debounce.Tick += delegate { debounce.Stop(); changed(); };
            owner.Loaded += delegate
            {
                if (w != null) return;
                try
                {
                    w = new FileSystemWatcher(Path.GetDirectoryName(path), Path.GetFileName(path)) { NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.FileName };
                    FileSystemEventHandler h = (s, e) => owner.Dispatcher.BeginInvoke(new Action(() => { debounce.Stop(); debounce.Start(); }));
                    w.Changed += h; w.Created += h;
                    w.EnableRaisingEvents = true;
                }
                catch (ArgumentException ex) { Debug.WriteLine("watch: " + ex.Message); }
            };
            owner.Unloaded += delegate { if (w != null) { w.EnableRaisingEvents = false; w.Dispose(); w = null; } debounce.Stop(); };
        }

        static UIElement Stats(int added, int removed)
        {
            var row = V.H(5);
            if (added > 0 || removed == 0) row.Children.Add(V.Mono("+" + added, 9.5, FontWeights.Medium, Theme.Current.Secondary));
            if (removed > 0) row.Children.Add(V.Mono("-" + removed, 9.5, FontWeights.Medium, Theme.Current.S(0.75)));
            return row;
        }

        /// <summary>InteractiveDiffPreviewView: title + stats, Split View, Copy unified diff.</summary>
        public static UIElement DiffPanel(string title, string before, string after)
        {
            var d = Differ.Compute(before, after, 3);
            var t = Theme.Current;
            var head = Header(Sym.Icon("arrow.left.and.right.square", 11, t.Secondary), V.Shrink(V.T(title, 11.5, FontWeights.SemiBold, t.Primary)), Stats(d.Added, d.Removed), V.Sp(),
                PanelUI.Small("arrow.left.and.right.square", "Split View", () => DiffViews.ShowSplit(title, before, after)),
                Tool("doc.on.doc", "Copy full unified diff to clipboard", () => CopyText(Unified(title, d))));
            return Framed(head, new ScrollViewer { Content = DiffViews.Section(d), VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled });
        }

        static string Unified(string title, DiffResult d)
        {
            var sb = new StringBuilder("--- a/" + title + "\n+++ b/" + title + "\n");
            foreach (var l in d.Lines) sb.Append(l.Kind == DiffKind.Hunk ? "" : l.Kind == DiffKind.Add ? "+" : l.Kind == DiffKind.Del ? "-" : " ").Append(l.Text).Append('\n');
            return sb.ToString();
        }

        static UIElement PatchPanel(string path)
        {
            var t = Theme.Current;
            string text = ReadHead(path, 2000000);
            var body = Patch(path);
            int add = 0, del = 0;
            foreach (var l in text.Replace("\r\n", "\n").Split('\n')) { if (l.StartsWith("+") && !l.StartsWith("+++")) add++; else if (l.StartsWith("-") && !l.StartsWith("---")) del++; }
            var head = Header(Sym.Icon("arrow.left.and.right.square", 11, t.Secondary), V.Shrink(V.T(Path.GetFileName(path), 11.5, FontWeights.SemiBold, t.Primary)), Stats(add, del), V.Sp(),
                Tool("doc.on.doc", "Copy patch content", () => CopyText(text)), More(path, null));
            return Framed(head, body);
        }

        /// <summary>"HEAD" content of a file tracked by git, or null (not a repo, untracked, git missing).</summary>
        internal static string GitHead(string path)
        {
            try
            {
                string dir = Path.GetDirectoryName(path);
                string root = Git(dir, "rev-parse --show-toplevel");
                if (string.IsNullOrWhiteSpace(root)) return null;
                root = root.Trim().Replace('/', '\\');
                string rel = path.Substring(Math.Min(path.Length, root.Length)).TrimStart('\\').Replace('\\', '/');
                return Git(root, "show \"HEAD:" + rel + "\"");
            }
            catch (ArgumentException) { return null; }
        }

        static string Git(string dir, string args)
        {
            try
            {
                var psi = new ProcessStartInfo("git", "-C \"" + dir + "\" " + args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8 };
                using (var p = Process.Start(psi))
                {
                    if (p == null) return null;
                    var outTask = p.StandardOutput.ReadToEndAsync();
                    p.StandardError.ReadToEndAsync();
                    if (!p.WaitForExit(6000)) { try { p.Kill(); } catch (InvalidOperationException) { } return null; }
                    return p.ExitCode == 0 ? outTask.Result : null;
                }
            }
            catch (System.ComponentModel.Win32Exception) { return null; } // git not installed
            catch (InvalidOperationException) { return null; }
        }
    }

    /// <summary>InteractiveCodePreviewView: breadcrumb header, Preview/Raw for Markdown, Live Preview for HTML/SVG,
    /// Git Diff with HEAD, Copy, Open in Code Editor; highlighted read-only code with the #L range selected.</summary>
    public class CodePreview : DockPanel
    {
        readonly PreviewItem _it;
        readonly AppState _app;
        readonly Border _header = new Border(), _body = new Border();
        string _text, _head, _error;
        bool _copied;

        public CodePreview(PreviewItem it, AppState app)
        {
            _it = it; _app = app;
            if (it.View == null) it.View = it.Kind == "markdown" && it.Start <= 0 ? "preview" : "raw";
            Background = Theme.Current.EditorBackground;
            DockPanel.SetDock(_header, Dock.Top);
            Children.Add(_header);
            Children.Add(_body);
            Load();
            Render();
            string path = it.Path;
            System.Threading.ThreadPool.QueueUserWorkItem(_ => { string head = FilePreview.GitHead(path); Dispatcher.BeginInvoke(new Action(() => { _head = head; RenderHeader(); })); });
            FilePreview.WatchFile(this, path, () => { Load(); Render(); });
        }

        bool IsMarkdown { get { return _it.Kind == "markdown"; } }
        bool CanLive { get { string e = Path.GetExtension(_it.Path).ToLowerInvariant(); return e == ".html" || e == ".htm" || e == ".svg"; } }
        bool HasDiff { get { return _head != null && _text != null && _head.Replace("\r\n", "\n") != _text.Replace("\r\n", "\n"); } }

        void Load()
        {
            try { _text = FilePreview.ReadHead(_it.Path, 2000000); _error = null; }
            catch (IOException ex) { _error = ex.Message; }
            catch (UnauthorizedAccessException ex) { _error = ex.Message; }
        }

        void Render() { RenderHeader(); RenderBody(); }

        IEnumerable<string> Breadcrumb()
        {
            string ws = _app.WorkspaceFolder;
            string dir = Path.GetDirectoryName(_it.Path) ?? "";
            if (ws != null && dir.StartsWith(ws, StringComparison.OrdinalIgnoreCase))
            {
                yield return Path.GetFileName(ws.TrimEnd('\\'));
                foreach (var seg in dir.Substring(ws.Length).Split(new[] { '\\', '/' }, StringSplitOptions.RemoveEmptyEntries)) yield return seg;
            }
            else
                foreach (var seg in dir.Split(new[] { '\\', '/' }, StringSplitOptions.RemoveEmptyEntries).Reverse().Take(2).Reverse()) yield return seg;
        }

        void RenderHeader()
        {
            var t = Theme.Current;
            var crumbs = new StackPanel { Orientation = Orientation.Horizontal };
            foreach (var seg in Breadcrumb())
            {
                crumbs.Children.Add(V.T(seg, 11.5, FontWeights.Normal, t.S(0.85)));
                var chev = Sym.Icon("chevron.right", 8.5, t.S(0.5), FontWeights.SemiBold);
                chev.Margin = new Thickness(5, 0, 5, 0);
                crumbs.Children.Add(chev);
            }
            crumbs.Children.Add(V.H(5, Sym.Icon(FileTreeView.IconName(_it.Title, false), 12, FileTreeView.IconColor(_it.Title, false)), V.T(_it.Title, 11.5, FontWeights.SemiBold, t.Primary)));
            if (_it.Start > 0)
            {
                string range = _it.End > _it.Start ? "#L" + _it.Start + "-" + _it.End : "#L" + _it.Start;
                var badge = V.Button(V.Box(V.H(3, V.Mono(range, 10, FontWeights.SemiBold, t.Primary), Sym.Icon("xmark", 7.5, t.Primary, FontWeights.Bold)), V.P(6, 2), t.P(0.10), 4),
                    () => { _it.Start = _it.End = 0; Render(); });
                badge.ToolTip = "Clear line highlight";
                badge.Margin = new Thickness(6, 0, 0, 0);
                crumbs.Children.Add(badge);
            }
            var crumbScroll = new ScrollViewer { Content = crumbs, HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled };
            var row = V.H(6, V.Flex(crumbScroll));
            if (IsMarkdown)
            {
                Func<string, string, string, UIElement> seg = (icon, label, view) =>
                {
                    bool on = _it.View == view;
                    return V.Button(V.Box(V.H(3, Sym.Icon(icon, 9, on ? t.Primary : t.Secondary, FontWeights.SemiBold), V.T(label, 10, FontWeights.SemiBold, on ? t.Primary : t.Secondary)), V.P(7, 2.5), on ? t.P(0.12) : Brushes.Transparent, 3.5),
                        () => { _it.View = view; Render(); });
                };
                var segBox = V.Box(V.H(1, seg("doc.richtext", "Preview", "preview"), seg("chevron.left.forwardslash.chevron.right", "Raw", "raw")), V.P(2), t.P(0.05), 5);
                ((FrameworkElement)segBox).ToolTip = "Switch between Rendered Markdown Preview and Raw Markdown Source";
                row.Children.Add(segBox);
            }
            else if (CanLive)
            {
                var live = V.Button(V.Box(V.H(3, Sym.Icon("play.tv", 9, t.Secondary, FontWeights.Bold), V.T("Live Preview", 10, FontWeights.SemiBold, t.Secondary)), V.P(7, 2.5), t.P(0.06), 4), () =>
                {
                    WebAppPreview.Shared.Open(new Uri(_it.Path).AbsoluteUri, null);
                    PreviewDock.SelectStandard("web");
                });
                live.ToolTip = "Open this page in the WebApp Preview (reloads on save)";
                row.Children.Add(live);
            }
            if (HasDiff)
            {
                bool on = _it.View == "diff";
                var diff = V.Button(V.Box(V.H(3, Sym.Icon("arrow.triangle.swap", 9, on ? t.Primary : t.Secondary), V.T(on ? "Code" : "Diff", 10, FontWeights.Medium, on ? t.Primary : t.Secondary)), V.P(6, 2.5), on ? t.P(0.14) : t.P(0.06), 4),
                    () => { _it.View = on ? (IsMarkdown ? "preview" : "raw") : "diff"; Render(); });
                diff.ToolTip = "Toggle Git Diff with HEAD";
                row.Children.Add(diff);
            }
            row.Children.Add(FilePreview.Tool(_copied ? "checkmark" : "doc.on.doc", "Copy file content", () =>
            {
                FilePreview.CopyText(_text);
                _copied = true; RenderHeader();
                var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
                timer.Tick += delegate { timer.Stop(); _copied = false; RenderHeader(); };
                timer.Start();
            }));
            row.Children.Add(FilePreview.Tool("square.and.pencil", "Open in full Code Editor", () => { _app.LoadFile(_it.Path); _app.SwitchToMode(EditorMode.Code); }));
            _header.Child = row;
            _header.Padding = new Thickness(10, 5, 10, 5);
            _header.Background = t.PanelBackground;
            _header.BorderBrush = t.Separator; _header.BorderThickness = new Thickness(0, 0, 0, 1);
        }

        void RenderBody()
        {
            var t = Theme.Current;
            if (_error != null) { _body.Child = PanelUI.Empty("exclamationmark.triangle", "Cannot Preview File", _error); return; }
            if (_it.View == "diff" && HasDiff)
            {
                _body.Child = new ScrollViewer { Content = DiffViews.Section(Differ.Compute(_head, _text, 3)), VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
                return;
            }
            if (IsMarkdown && _it.View == "preview")
            {
                var md = MarkdownView.Render(_text, 13, Path.GetDirectoryName(_it.Path));
                var box = md as Border;
                if (box != null) box.Padding = new Thickness(0);
                _body.Child = new ScrollViewer { Content = new Border { Child = md, Padding = new Thickness(16, 12, 16, 20) }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
                return;
            }
            var ed = new Editor.CodeEditorView(_text.Replace("\r\n", "\n"), IsMarkdown ? "markdown" : AppState.DetectLanguage(_it.Path), 12.5);
            ed.Box.IsReadOnly = true;
            if (_it.Start > 0)
            {
                int start = _it.Start, end = Math.Max(_it.Start, _it.End);
                ed.Loaded += delegate
                {
                    ed.Dispatcher.BeginInvoke(new Action(() =>
                    {
                        try
                        {
                            ed.GoToLine(start);
                            int a = ed.Box.GetCharacterIndexFromLineIndex(Math.Max(0, Math.Min(start, ed.Box.LineCount) - 1));
                            int b = end < ed.Box.LineCount ? ed.Box.GetCharacterIndexFromLineIndex(end) : ed.Box.Text.Length;
                            ed.Box.Select(a, Math.Max(0, b - a));
                        }
                        catch (ArgumentOutOfRangeException ex) { Debug.WriteLine("preview line range: " + ex.Message); }
                    }), DispatcherPriority.Loaded);
                };
            }
            _body.Child = ed;
        }
    }

    /// <summary>InteractivePDFPreviewView: page-count badge, Continuous / Single Page, Open, ⋯ menu.</summary>
    public class PdfPreview : DockPanel
    {
        readonly string _path;
        readonly Border _header = new Border(), _body = new Border();
        bool _continuous = Defaults.Bool("pdfPreviewContinuous", true);
        int _pages = -1, _page;

        public PdfPreview(string path)
        {
            _path = path;
            Background = Theme.Current.EditorBackground;
            DockPanel.SetDock(_header, Dock.Top);
            Children.Add(_header); Children.Add(_body);
            Render();
            Loaded += async delegate
            {
                if (_pages >= 0) return;
                try { _pages = await PdfRender.PageCount(_path); }
                catch (Exception ex) { Debug.WriteLine("pdf pages: " + ex.Message); _pages = 0; }
                RenderHeader(); if (!_continuous) RenderBody();
            };
            FilePreview.WatchFile(this, path, () => { PdfRender.Forget(_path); _pages = -1; Render(); RecountPages(); });
            KeyDown += (s, e) =>
            {
                if (_continuous || _pages <= 0) return;
                if (e.Key == Key.Right || e.Key == Key.PageDown || e.Key == Key.Down) { Go(_page + 1); e.Handled = true; }
                if (e.Key == Key.Left || e.Key == Key.PageUp || e.Key == Key.Up) { Go(_page - 1); e.Handled = true; }
            };
            Focusable = true;
        }

        async void RecountPages()
        {
            try { _pages = await PdfRender.PageCount(_path); } catch (Exception ex) { Debug.WriteLine("pdf pages: " + ex.Message); _pages = 0; }
            RenderHeader();
        }

        void Render() { RenderHeader(); RenderBody(); }

        void Go(int page) { if (_pages <= 0) return; _page = Math.Max(0, Math.Min(_pages - 1, page)); RenderHeader(); RenderBody(); }

        void RenderHeader()
        {
            var t = Theme.Current;
            var mode = V.Button(V.Box(V.H(4, Sym.Icon(_continuous ? "scroll" : "book.closed", 10, t.Secondary), V.T(_continuous ? "Continuous" : "Single Page", 10, FontWeights.Normal, t.Secondary)), V.P(8, 4), t.P(0.05), 4),
                () => { _continuous = !_continuous; Defaults.Set("pdfPreviewContinuous", _continuous); Render(); });
            var items = new List<UIElement> { FilePreview.Pill("doc.text.fill", _pages > 0 ? _pages + " pages" : "PDF"), mode };
            if (!_continuous && _pages > 0)
            {
                items.Add(FilePreview.Tool("chevron.left", "Previous page", () => Go(_page - 1)));
                items.Add(V.Mono((_page + 1) + " / " + _pages, 10, FontWeights.Medium, t.Secondary));
                items.Add(FilePreview.Tool("chevron.right", "Next page", () => Go(_page + 1)));
            }
            items.Add(V.Sp());
            items.Add(FilePreview.OpenButton(_path));
            items.Add(FilePreview.More(_path, null));
            FilePreview.HeaderInto(_header, items.ToArray());
        }

        void RenderBody()
        {
            if (_continuous) { _body.Child = FilePreview.Pdf(_path); return; }
            var t = Theme.Current;
            var img = new System.Windows.Controls.Image { Stretch = Stretch.Uniform, Margin = new Thickness(16) };
            RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
            var page = new Border { Child = img, Background = t.P(0.03) };
            _body.Child = page;
            int index = _page;
            page.Loaded += async delegate
            {
                if (_pages == 0) return;
                try
                {
                    var bytes = await PdfRender.Page(_path, index, 1600);
                    var bmp = new BitmapImage();
                    using (var ms = new MemoryStream(bytes)) { bmp.BeginInit(); bmp.CacheOption = BitmapCacheOption.OnLoad; bmp.StreamSource = ms; bmp.EndInit(); }
                    img.Source = bmp;
                }
                catch (Exception ex) { _body.Child = PanelUI.Empty("exclamationmark.triangle", "Could not render this PDF", ex.GetBaseException().Message); }
            };
        }
    }

    /// <summary>InteractiveImagePreviewView: size pill, zoom −/%/+/Fit, ⋯ menu; drag on the image to mark regions and send
    /// them with notes to the AI Agent.</summary>
    public class ImagePreview : DockPanel
    {
        class Region { public Rect Px; public TextBox Note; }

        readonly string _path;
        readonly AppState _app;
        readonly Border _header = new Border(), _card = new Border();
        readonly ScrollViewer _scroll = new ScrollViewer { HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        readonly Grid _stage = new Grid();
        readonly System.Windows.Controls.Image _img = new System.Windows.Controls.Image { Stretch = Stretch.Fill };
        readonly Canvas _overlay = new Canvas { Background = Brushes.Transparent };
        readonly List<Region> _regions = new List<Region>();
        BitmapSource _bmp;
        double _zoom = 1;   // 1 = fit
        Point? _dragStart;
        System.Windows.Shapes.Rectangle _marquee;
        TextBox _comment;
        string _sizeText = "";

        public ImagePreview(string path, AppState app)
        {
            _path = path; _app = app;
            var t = Theme.Current;
            Background = t.EditorBackground;
            DockPanel.SetDock(_header, Dock.Top); Children.Add(_header);
            DockPanel.SetDock(_card, Dock.Bottom); Children.Add(_card);
            RenderOptions.SetBitmapScalingMode(_img, BitmapScalingMode.HighQuality);
            _stage.Children.Add(_img); _stage.Children.Add(_overlay);
            _stage.HorizontalAlignment = HorizontalAlignment.Center; _stage.VerticalAlignment = VerticalAlignment.Center;
            _scroll.Content = _stage;
            Children.Add(_scroll);
            _scroll.SizeChanged += delegate { Layout(); RenderHeader(); }; // the zoom % depends on the fitted size
            _overlay.MouseLeftButtonDown += OnDown;
            _overlay.MouseMove += OnMove;
            _overlay.MouseLeftButtonUp += OnUp;
            _overlay.Cursor = Cursors.Cross;
            _scroll.PreviewMouseWheel += (s, e) => { if ((Keyboard.Modifiers & ModifierKeys.Control) != 0) { SetZoom(_zoom * (e.Delta > 0 ? 1.15 : 1 / 1.15)); e.Handled = true; } };
            Load();
            FilePreview.WatchFile(this, path, () => { Load(); });
        }

        void Load()
        {
            try
            {
                var bmp = new BitmapImage();
                bmp.BeginInit(); bmp.CacheOption = BitmapCacheOption.OnLoad; bmp.CreateOptions = BitmapCreateOptions.IgnoreImageCache; bmp.UriSource = new Uri(_path); bmp.EndInit();
                bmp.Freeze();
                _bmp = bmp;
                _img.Source = bmp;
                _sizeText = bmp.PixelWidth + " × " + bmp.PixelHeight + " · " + FilePreview.Size(new FileInfo(_path).Length);
            }
            catch (Exception ex)
            {
                if (!(ex is IOException || ex is NotSupportedException || ex is UnauthorizedAccessException || ex is ArgumentException)) throw;
                _bmp = null; _sizeText = "Cannot load image";
                _scroll.Content = PanelUI.Empty("photo", "Cannot load image", ex.Message);
            }
            RenderHeader(); Layout(); RenderCard();
        }

        double FitScale()
        {
            if (_bmp == null) return 1;
            double w = Math.Max(50, _scroll.ActualWidth - 32), h = Math.Max(50, _scroll.ActualHeight - 32);
            return Math.Min(1, Math.Min(w / _bmp.PixelWidth, h / _bmp.PixelHeight));
        }

        double Scale { get { return FitScale() * _zoom; } }

        void Layout()
        {
            if (_bmp == null) return;
            double s = Scale;
            _stage.Width = _bmp.PixelWidth * s; _stage.Height = _bmp.PixelHeight * s;
            _stage.Margin = new Thickness(16);
            DrawRegions();
        }

        void SetZoom(double z) { _zoom = Math.Max(0.1, Math.Min(6, z)); Layout(); RenderHeader(); }

        void RenderHeader()
        {
            var t = Theme.Current;
            var zoom = V.Box(V.H(2, FilePreview.Tool("minus.magnifyingglass", "Zoom out", () => SetZoom(_zoom - 0.2)), V.Size(V.Mono((int)Math.Round(Scale * 100) + "%", 9, FontWeights.Normal, t.Secondary), 36, double.NaN),
                FilePreview.Tool("plus.magnifyingglass", "Zoom in", () => SetZoom(_zoom + 0.2)),
                V.Button(V.Box(V.T("Fit", 9, FontWeights.Medium, t.Secondary), V.P(4, 2), Brushes.Transparent, 3), () => SetZoom(1))), V.P(6, 1), t.P(0.05), 4);
            var more = FilePreview.More(_path, new List<MenuItemSpec>
            {
                MenuItemSpec.Item("Copy Image", "photo", () => { if (_bmp != null) try { Clipboard.SetImage(_bmp); } catch (System.Runtime.InteropServices.ExternalException ex) { Debug.WriteLine("copy image: " + ex.Message); } })
            });
            FilePreview.HeaderInto(_header, FilePreview.Pill("photo", _sizeText), V.Sp(), zoom, more);
        }

        // ── region selection ──

        void OnDown(object s, MouseButtonEventArgs e)
        {
            _dragStart = e.GetPosition(_overlay);
            _marquee = new System.Windows.Shapes.Rectangle { Stroke = Theme.Current.Primary, StrokeThickness = 1.5, StrokeDashArray = new DoubleCollection { 4, 4 }, Fill = Theme.Current.P(0.08) };
            Canvas.SetLeft(_marquee, _dragStart.Value.X); Canvas.SetTop(_marquee, _dragStart.Value.Y);
            _overlay.Children.Add(_marquee);
            _overlay.CaptureMouse();
            e.Handled = true;
        }

        void OnMove(object s, MouseEventArgs e)
        {
            if (_dragStart == null || _marquee == null) return;
            var p = e.GetPosition(_overlay); var a = _dragStart.Value;
            Canvas.SetLeft(_marquee, Math.Min(a.X, p.X)); Canvas.SetTop(_marquee, Math.Min(a.Y, p.Y));
            _marquee.Width = Math.Abs(p.X - a.X); _marquee.Height = Math.Abs(p.Y - a.Y);
        }

        void OnUp(object s, MouseButtonEventArgs e)
        {
            if (_dragStart == null) return;
            _overlay.ReleaseMouseCapture();
            var p = e.GetPosition(_overlay); var a = _dragStart.Value;
            _dragStart = null;
            _overlay.Children.Remove(_marquee); _marquee = null;
            var r = new Rect(a, p);
            if (r.Width < 15 || r.Height < 15 || _bmp == null) return;
            double sc = Scale;
            _regions.Add(new Region { Px = new Rect(Math.Round(r.X / sc), Math.Round(r.Y / sc), Math.Round(r.Width / sc), Math.Round(r.Height / sc)) });
            DrawRegions(); RenderCard();
        }

        void DrawRegions()
        {
            _overlay.Children.Clear();
            var t = Theme.Current;
            double sc = Scale;
            for (int i = 0; i < _regions.Count; i++)
            {
                var r = _regions[i].Px; int idx = i;
                var box = new System.Windows.Shapes.Rectangle { Stroke = t.Primary, StrokeThickness = 1.5, Fill = t.P(0.10), Width = r.Width * sc, Height = r.Height * sc };
                Canvas.SetLeft(box, r.X * sc); Canvas.SetTop(box, r.Y * sc);
                _overlay.Children.Add(box);
                var tag = V.Box(V.H(4, V.Mono("#" + (i + 1), 9.5, FontWeights.Bold, t.Primary), V.Mono((int)r.Width + "×" + (int)r.Height, 8.5, FontWeights.Normal, t.Secondary),
                    V.Button(Sym.Icon("xmark", 7, t.Secondary, FontWeights.Bold), () => { _regions.RemoveAt(idx); DrawRegions(); RenderCard(); })), V.P(6, 2), t.WindowBackground, 3, t.P(0.28), 1);
                Canvas.SetLeft(tag, r.X * sc); Canvas.SetTop(tag, Math.Max(0, r.Y * sc - 22));
                _overlay.Children.Add(tag);
            }
        }

        void RenderCard()
        {
            var t = Theme.Current;
            if (_regions.Count == 0) { _card.Child = null; return; }
            var col = V.VLead(6); col.Align = Cross.Stretch;
            col.Children.Add(V.Self(V.H(6, Sym.Icon("viewfinder", 10, t.Primary, FontWeights.SemiBold), V.Mono("SELECTED REGIONS (" + _regions.Count + ")", 9.5, FontWeights.Bold, t.Primary), V.Sp(),
                V.T("Drag on image to add more spots", 9, FontWeights.Normal, t.Secondary), PanelUI.Small(null, "Clear", () => { _regions.Clear(); DrawRegions(); RenderCard(); })), Cross.Stretch));
            for (int i = 0; i < _regions.Count; i++)
            {
                TextBox note;
                var field = Styles.Field("คำสั่งเฉพาะจุด #" + (i + 1) + "...", 10, t.Primary, t.S(0.6), out note);
                if (_regions[i].Note != null) note.Text = _regions[i].Note.Text;
                _regions[i].Note = note;
                col.Children.Add(V.Self(V.H(5, V.Size(V.Mono("#" + (i + 1), 9, FontWeights.Bold, t.Primary), 22, double.NaN), V.Flex(V.Box(field, V.P(6, 3), t.P(0.05), 4))), Cross.Stretch));
            }
            TextBox comment;
            var cf = Styles.Field("คำสั่งรวมสำหรับทุกจุดที่เลือก…", 10.5, t.Primary, t.S(0.6), out comment);
            if (_comment != null) comment.Text = _comment.Text;
            _comment = comment;
            comment.KeyDown += (s, e) => { if (e.Key == Key.Enter) { Send(); e.Handled = true; } };
            var send = V.Button(V.Box(V.H(4, Sym.Icon("arrow.up.circle.fill", 9.5, t.WindowBackground), V.T("Send (" + _regions.Count + ")", 10, FontWeights.SemiBold, t.WindowBackground)), V.P(8, 5), t.Primary, 4), Send);
            send.ToolTip = "Send all selected image regions to AI Agent";
            col.Children.Add(V.Self(V.H(5, V.Flex(V.Box(cf, V.P(7, 4.5), t.P(0.06), 4)), send), Cross.Stretch));
            var card = V.Box(col, V.P(8), t.WindowBackground, 7, t.P(0.22), 1);
            card.Margin = new Thickness(12, 0, 12, 12);
            _card.Child = card;
        }

        void Send()
        {
            if (_regions.Count == 0 || _bmp == null) return;
            var sb = new StringBuilder("Look at the image " + _path + " (" + _bmp.PixelWidth + "×" + _bmp.PixelHeight + " px). Selected regions (x, y, width, height in image pixels):\n");
            for (int i = 0; i < _regions.Count; i++)
            {
                var r = _regions[i].Px;
                sb.Append("#").Append(i + 1).Append(": ").Append((int)r.X).Append(", ").Append((int)r.Y).Append(", ").Append((int)r.Width).Append(", ").Append((int)r.Height);
                string note = _regions[i].Note != null ? _regions[i].Note.Text.Trim() : "";
                if (note.Length > 0) sb.Append(" — ").Append(note);
                sb.Append('\n');
            }
            string all = _comment != null ? _comment.Text.Trim() : "";
            if (all.Length > 0) sb.Append("\nInstruction: ").Append(all);
            _regions.Clear(); _comment = null; DrawRegions(); RenderCard();
            _app.SwitchToMode(EditorMode.AIAgent);
            _app.Notify("agent:send:" + sb);
        }
    }
}
