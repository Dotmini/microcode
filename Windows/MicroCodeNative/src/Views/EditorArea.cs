// Port of EditorArea / EditorTabBar / EditorTab / CodeEditor header / DebugArea (Views/Workspace/WorkspaceEditorAndDebugViews.swift).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using MicroCode.Core;
using MicroCode.Editor;
using MicroCode.UI;

namespace MicroCode.Views
{
    public class EditorArea : Grid
    {
        readonly AppState _app;
        readonly Border _tabs = new Border(), _body = new Border(), _console = new Border();
        readonly Dictionary<Guid, CodeEditorView> _editors = new Dictionary<Guid, CodeEditorView>();
        readonly Dictionary<Guid, bool> _mdRendered = new Dictionary<Guid, bool>();
        DebugArea _debug;
        bool _inlineEdit;

        public EditorArea(AppState app)
        {
            _app = app;
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            SetRow(_tabs, 0); SetRow(_body, 1); SetRow(_console, 2);
            Children.Add(_tabs); Children.Add(_body); Children.Add(_console);
            Render();
            app.Changed += OnChanged;
        }

        public CodeEditorView ActiveEditor
        {
            get { var f = _app.CurrentFile; CodeEditorView e; return f != null && _editors.TryGetValue(f.Id, out e) ? e : null; }
        }

        void OnChanged(string what)
        {
            switch (what)
            {
                case "files": case "workspace": case "theme": case "mode":
                    Render(); break;
                case "dirty": RenderTabs(); break;
                case "console": RenderConsole(); break;
                case "font": _editors.Clear(); Render(); break; // family / size / line-number prefs may have changed
                case "content": SyncEditorsFromModel(); break; // a collaborator / the agent changed an open buffer
            }
        }

        /// <summary>Open editors whose buffer changed outside them (collaboration, agent edits) take the new text in place.</summary>
        void SyncEditorsFromModel()
        {
            foreach (var f in _app.OpenFiles)
            {
                CodeEditorView ed;
                if (f.Content != null && _editors.TryGetValue(f.Id, out ed) && ed.Text != f.Content) ed.ReplaceText(f.Content);
            }
            RenderTabs();
        }

        public void Render()
        {
            var t = Theme.Current;
            Background = t.EditorBackground;
            if (_app.ThemeRaw != null) foreach (var e in _editors.Values) e.ApplySyntaxTheme();
            // drop editors for closed files
            foreach (var id in _editors.Keys.ToList()) if (!_app.OpenFiles.Any(f => f.Id == id)) _editors.Remove(id);
            RenderTabs();
            var file = _app.CurrentFile;
            if (file != null) _body.Child = FileSurface(file);
            else if (_app.WorkspaceFolder != null)
            {
                _body.Child = V.Vs(16, V.Sp(), Sym.Icon("doc.text.magnifyingglass", 48, t.S(0.2)), V.T("Select a file to view", 14, FontWeights.Normal, t.S(0.5)), V.Sp());
            }
            else _body.Child = new WelcomeScreen(_app);
            RenderConsole();
        }

        // MARK: EditorTabBar (height 30, panelBackground)
        void RenderTabs()
        {
            var t = Theme.Current;
            if (_app.OpenFiles.Count == 0) { _tabs.Child = null; return; }
            var row = V.H(0);
            foreach (var f in _app.OpenFiles) row.Children.Add(EditorTab(f, f == _app.CurrentFile));
            var sv = new ScrollViewer { Content = row, HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled };
            sv.PreviewMouseWheel += delegate(object s, MouseWheelEventArgs e) { sv.ScrollToHorizontalOffset(sv.HorizontalOffset - e.Delta / 3.0); e.Handled = true; };
            _tabs.Child = V.Size(V.Box(sv, V.P(0), t.PanelBackground, 0), double.NaN, 30);
        }

        UIElement EditorTab(CodeFile file, bool selected)
        {
            var t = Theme.Current;
            var close = V.Button(V.Box(Sym.Icon("xmark", 9, t.Secondary, FontWeights.SemiBold), V.P(4), null, 0), () => _app.CloseFile(file));
            close.ToolTip = "Close Tab (Ctrl+W)";
            close.Opacity = selected ? 1 : 0;
            var content = V.H(6, Sym.Icon(TabIcon(file.Name), 11, TabColor(file.Name)), V.T(file.Name, 12, FontWeights.Normal, selected ? t.Primary : t.Secondary));
            if (file.IsUnsaved) content.Children.Add(V.Dot(6, t.SysOrange));
            content.Children.Add(close);
            var underline = new Border { Height = 2, Background = selected ? t.Accent : Brushes.Transparent, VerticalAlignment = VerticalAlignment.Bottom };
            var g = new Grid { Height = 30 };
            g.Children.Add(V.Box(content, V.P(10, 0), null, 0));
            g.Children.Add(underline);
            var tab = V.Button(g, () => _app.SelectFile(file));
            tab.PressedOpacity = 1;
            tab.Background = selected ? t.TextBackground : Brushes.Transparent;
            tab.OnState = b =>
            {
                if (!selected) b.Background = b.IsHover ? t.S(0.1) : Brushes.Transparent;
                close.Opacity = b.IsHover || selected ? 1 : 0;
            };
            tab.MouseDown += delegate(object s, MouseButtonEventArgs e) { if (e.ChangedButton == MouseButton.Middle) _app.CloseFile(file); };
            return tab;
        }

        static string TabIcon(string name)
        {
            switch ((Path.GetExtension(name) ?? "").TrimStart('.').ToLowerInvariant())
            {
                case "swift": return "swift";
                case "py": return "chevron.left.forwardslash.chevron.right";
                case "js": case "ts": return "curlybraces";
                case "rs": return "gearshape.2";
                case "json": return "curlybraces.square";
                case "md": return "doc.richtext";
                default: return "doc.text";
            }
        }

        static Brush TabColor(string name)
        {
            var t = Theme.Current;
            switch ((Path.GetExtension(name) ?? "").TrimStart('.').ToLowerInvariant())
            {
                case "swift": return t.SysOrange;
                case "py": return t.SysGreen;
                case "js": return t.SysYellow;
                case "ts": return t.SysBlue;
                case "rs": return t.SysOrange;
                default: return t.Secondary;
            }
        }

        static Brush LanguageColor(string lang)
        {
            var t = Theme.Current;
            switch (lang)
            {
                case "swift": return t.SysOrange;
                case "python": return Theme.B(Theme.Rgb(51, 128, 204));
                case "javascript": return t.SysYellow;
                case "typescript": return t.SysBlue;
                case "rust": return Theme.B(Theme.Rgb(204, 77, 26));
                case "go": return t.SysCyan;
                default: return t.SysGray;
            }
        }

        bool IsMarkdown(CodeFile f) { return f.Language == "markdown" || f.Name.EndsWith(".md", StringComparison.OrdinalIgnoreCase) || f.Name.EndsWith(".markdown", StringComparison.OrdinalIgnoreCase); }
        bool IsTable(CodeFile f) { return f.Name.EndsWith(".csv", StringComparison.OrdinalIgnoreCase) || f.Name.EndsWith(".tsv", StringComparison.OrdinalIgnoreCase); }

        void AddCrumbs(Stack header, CodeFile file)
        {
            var t = Theme.Current;
            var comps = file.Path.Split(new[] { '\\', '/' }, StringSplitOptions.RemoveEmptyEntries);
            var crumbs = comps.Skip(Math.Max(0, comps.Length - 3)).ToList();
            if (!Path.IsPathRooted(file.Path)) crumbs = new List<string> { file.Name };
            for (int i = 0; i < crumbs.Count; i++)
            {
                var c = V.H(4, V.T(crumbs[i], 11, FontWeights.Normal, t.Secondary));
                if (i < crumbs.Count - 1) c.Children.Add(Sym.Icon("chevron.right", 8, t.S(0.6)));
                header.Children.Add(i == crumbs.Count - 1 ? V.Shrink(c) : (UIElement)c);
            }
        }

        /// <summary>Images, PDFs and other binaries: a read-only preview with Preview pane / default app / Explorer actions.</summary>
        UIElement PreviewSurface(CodeFile file)
        {
            var t = Theme.Current;
            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            var header = V.H(6);
            AddCrumbs(header, file);
            header.Children.Add(V.Sp());
            Func<string, string, Action, Btn> small = (icon, label, a) => V.Button(V.Box(V.H(4, Sym.Icon(icon, 9.5, t.Secondary), V.T(label, 10, FontWeights.Medium, t.Secondary)), V.P(8, 3), t.P(0.05), 4), a);
            header.Children.Add(small("sidebar.right", "Preview Pane", () => PreviewDock.OpenFile(file.Path)));
            if (!FilePreview.IsRunnable(file.Path)) header.Children.Add(small("arrow.up.right.square", "Open", () => FilePreview.Shell(file.Path, null)));
            header.Children.Add(small("folder", "Reveal", () => FilePreview.Reveal(file.Path)));
            header.Children.Add(V.Box(V.T(file.PreviewKind.ToUpperInvariant(), 9, FontWeights.Bold, Brushes.White), V.P(6, 2), t.SysGray, 3));
            var headerBox = V.Size(V.Box(header, V.P(12, 0), t.IsDark ? Theme.B(Theme.Rgb(25, 25, 25)) : t.Op(t.WindowBackground, 0.5), 0), double.NaN, 28);
            var hdr = V.Vs(0, V.Self(headerBox, Cross.Stretch), V.Self(V.Line(t.Separator, true), Cross.Stretch));
            hdr.Align = Cross.Stretch;
            Grid.SetRow(hdr, 0);
            grid.Children.Add(hdr);
            // the same interactive viewers as the Preview pane (zoom & regions for images, Continuous/Single Page for PDFs)
            var item = new PreviewItem { Id = "editor:" + file.Path.ToLowerInvariant(), Path = file.Path, Title = file.Name, Kind = file.PreviewKind };
            var body = new Border { Background = t.TextBackground, Child = FilePreview.ForItem(item, _app) };
            Grid.SetRow(body, 1);
            grid.Children.Add(body);
            return grid;
        }

        // MARK: CodeEditor (header 28pt + editor)
        UIElement FileSurface(CodeFile file)
        {
            var t = Theme.Current;
            if (file.PreviewKind != null && File.Exists(file.Path)) return PreviewSurface(file);

            var stack = new Grid();
            stack.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            stack.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            stack.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            // header
            var header = V.H(6);
            AddCrumbs(header, file);
            header.Children.Add(V.Sp());
            var inline = V.Button(V.Box(V.H(4, Sym.Icon("wand.and.stars", 9.5, _inlineEdit ? t.Accent : t.Secondary, FontWeights.SemiBold), V.T("Inline Edit (Ctrl+K)", 10, FontWeights.Medium, _inlineEdit ? t.Accent : t.Secondary)), V.P(8, 3), _inlineEdit ? t.A(0.14) : t.P(0.05), 4), () => { _inlineEdit = !_inlineEdit; Render(); });
            if (!file.ReadOnly) header.Children.Add(inline);
            bool md = IsMarkdown(file);
            bool csv = !md && IsTable(file);
            bool rendered = (md || csv) && (!_mdRendered.ContainsKey(file.Id) || _mdRendered[file.Id]);
            if (md || csv)
            {
                Func<string, string, bool, Action, UIElement> seg = (icon, label, on, act) => V.Button(V.Box(V.H(3, Sym.Icon(icon, 9.5, on ? t.Primary : t.Secondary), V.T(label, 9.5, on ? FontWeights.SemiBold : FontWeights.Normal, on ? t.Primary : t.Secondary)), V.P(7, 3), on ? t.P(0.12) : Brushes.Transparent, 4), act);
                header.Children.Add(V.Box(V.H(1,
                    seg(md ? "doc.richtext" : "tablecells", md ? "Rendered" : "Table", rendered, () => { _mdRendered[file.Id] = true; Render(); }),
                    seg("chevron.left.forwardslash.chevron.right", "Source", !rendered, () => { _mdRendered[file.Id] = false; Render(); })), V.P(2), t.P(0.04), 5));
            }
            var lang = V.Button(V.Box(V.T(file.Language.ToUpperInvariant(), 9, FontWeights.Bold, Brushes.White), V.P(6, 2), LanguageColor(file.Language), 3), null);
            lang.MenuItems = () =>
            {
                Action<string> set = l => { _app.UpdateFileLanguage(l, file); CodeEditorView ed; if (_editors.TryGetValue(file.Id, out ed)) ed.SetLanguage(l); };
                var items = new List<MenuItemSpec> { MenuItemSpec.Item("Auto Detect", null, () => set(AppState.DetectLanguage(file.Path))), MenuItemSpec.Sep() };
                foreach (var pair in new[] { new[] { "Swift", "swift" }, new[] { "Python", "python" }, new[] { "JavaScript", "typescript" }, new[] { "TypeScript", "typescript" }, new[] { "Rust", "rust" }, new[] { "Go", "go" }, new[] { "HTML", "html" }, new[] { "CSS", "css" }, new[] { "JSON", "json" }, new[] { "Markdown", "markdown" } })
                {
                    var p = pair; items.Add(MenuItemSpec.Item(p[0], null, () => set(p[1])));
                }
                return items;
            };
            header.Children.Add(lang);
            var headerBox = V.Size(V.Box(header, V.P(12, 0), t.IsDark ? Theme.B(Theme.Rgb(25, 25, 25)) : t.Op(t.WindowBackground, 0.5), 0), double.NaN, 28);
            var hdr = V.Vs(0, V.Self(headerBox, Cross.Stretch), V.Self(V.Line(t.Separator, true), Cross.Stretch));
            hdr.Align = Cross.Stretch;
            if (_inlineEdit)
            {
                TextBox prompt;
                var pf = Styles.Field("Describe how to edit " + file.Name + " (e.g., refactor function, add error handling)...", 11.5, t.Primary, t.Secondary, out prompt);
                var gen = V.Button(V.Box(V.T("Generate", 10.5, FontWeights.SemiBold, Brushes.White), V.P(10, 4), t.Accent, 5), () => InlineGenerate(file, prompt.Text));
                var closeBar = V.Button(Sym.Icon("xmark", 9.5, t.Secondary, FontWeights.SemiBold), () => { _inlineEdit = false; Render(); });
                prompt.KeyDown += delegate(object s, KeyEventArgs e) { if (e.Key == Key.Enter) InlineGenerate(file, prompt.Text); if (e.Key == Key.Escape) { _inlineEdit = false; Render(); } };
                hdr.Children.Add(V.Self(V.Box(V.H(8, Sym.Icon("wand.and.stars", 11, t.Accent, FontWeights.SemiBold), V.Flex(pf), gen, closeBar), V.P(12, 7), t.A(0.06), 0), Cross.Stretch));
                hdr.Children.Add(V.Self(V.Line(t.Separator, true), Cross.Stretch));
                Dispatcher.BeginInvoke(new Action(() => prompt.Focus()), System.Windows.Threading.DispatcherPriority.Input);
            }
            Grid.SetRow(hdr, 0);
            stack.Children.Add(hdr);

            UIElement body;
            if (rendered && csv)
            {
                // table view of the current (possibly unsaved) text
                body = new Border { Background = t.TextBackground, Child = FilePreview.TableText(file.Content, file.Name.EndsWith(".tsv", StringComparison.OrdinalIgnoreCase)) };
            }
            else if (rendered)
            {
                body = new ScrollViewer { Content = MarkdownView.Render(file.Content, 14, Path.IsPathRooted(file.Path) ? Path.GetDirectoryName(file.Path) : null), VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, Background = t.TextBackground };
            }
            else
            {
                CodeEditorView ed;
                if (!_editors.TryGetValue(file.Id, out ed))
                {
                    ed = new CodeEditorView(file.Content, file.Language, _app.FontSize);
                    if (file.ReadOnly) ed.Box.IsReadOnly = true; // placeholder text for files too large or unreadable
                    var f = file;
                    ed.TextEdited += text => { _app.UpdateContent(f, text); CollabHooks.LocalEdit(f, text); };
                    var edRef = ed;
                    bool typing = false;
                    ed.TextEdited += _ => typing = true;
                    ed.CaretMoved += () => { CollabHooks.Caret(f, edRef, typing); typing = false; };
                    _editors[file.Id] = ed;
                }
                else if (ed.Text != file.Content) ed.ReplaceText(file.Content); // cached editor, buffer changed meanwhile
                if (ed.Parent is Panel) ((Panel)ed.Parent).Children.Remove(ed);
                if (ed.Parent is Decorator) ((Decorator)ed.Parent).Child = null;
                body = ed;
                Dispatcher.BeginInvoke(new Action(() => { if (!_inlineEdit) ed.Focus2(); }), System.Windows.Threading.DispatcherPriority.Input);
            }
            Grid.SetRow((UIElement)body, 2);
            stack.Children.Add(body);
            return stack;
        }

        void InlineGenerate(CodeFile file, string prompt)
        {
            if (string.IsNullOrWhiteSpace(prompt)) return;
            AIClient.InlineEdit(file, prompt, (newText, error) =>
            {
                if (error != null) { MessageBox.Show(error, "MicroCode"); return; }
                CodeEditorView ed;
                if (_editors.TryGetValue(file.Id, out ed)) { ed.Box.SelectAll(); ed.Box.SelectedText = newText; }
                _inlineEdit = false; Render();
            });
        }

        void RenderConsole()
        {
            if (!_app.ConsoleVisible) { _console.Child = null; return; }
            if (_debug == null) _debug = new DebugArea(_app);
            _debug.Render();
            if (_console.Child != _debug) _console.Child = _debug;
        }
    }

    /// <summary>DebugArea: resizable bottom panel with OUTPUT / TERMINAL / PROBLEMS / ANALYSIS.</summary>
    public class DebugArea : Grid
    {
        readonly AppState _app;
        double _height = Defaults.Num("mc_debug_area_height", 240);
        bool _max;
        readonly Border _toolbar = new Border(), _stage = new Border();
        TextBox _output;
        TerminalView _terminal;

        public DebugArea(AppState app)
        {
            _app = app;
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(4) });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(28) });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1) });
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var t = Theme.Current;
            var grip = new Border { Background = t.P(0.08), Cursor = Cursors.SizeNS };
            double startY = 0, startH = 0;
            grip.MouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e) { startY = e.GetPosition(Window.GetWindow(this)).Y; startH = _max ? 520 : _height; _max = false; grip.CaptureMouse(); e.Handled = true; };
            grip.MouseMove += delegate(object s, MouseEventArgs e)
            {
                if (!grip.IsMouseCaptured) return;
                _height = Math.Max(130, Math.Min(520, startH - (e.GetPosition(Window.GetWindow(this)).Y - startY)));
                _stage.Height = _height;
            };
            grip.MouseLeftButtonUp += delegate { grip.ReleaseMouseCapture(); Defaults.Set("mc_debug_area_height", _height); };
            SetRow(grip, 0); Children.Add(grip);
            SetRow(_toolbar, 1); Children.Add(_toolbar);
            var div = V.Line(t.Separator, true); SetRow(div, 2); Children.Add(div);
            SetRow(_stage, 3); Children.Add(_stage);
            app.Changed += w => { if (w == "consoleOutput" && _output != null) { _output.Text = Out(); _output.ScrollToEnd(); _output.Foreground = OutColor(); } };
        }

        string Out() { return string.IsNullOrEmpty(_app.ConsoleOutput) ? "No output yet. Run code with Ctrl+R" : _app.ConsoleOutput; }
        Brush OutColor() { var t = Theme.Current; return string.IsNullOrEmpty(_app.ConsoleOutput) ? Theme.B(t.Def.Comment) : t.EditorText; }

        public void Render()
        {
            var t = Theme.Current;
            var tabs = V.H(0);
            string[] names = { "OUTPUT", "TERMINAL", "PROBLEMS", "ANALYSIS" };
            for (int i = 0; i < names.Length; i++)
            {
                int idx = i;
                bool sel = _app.SelectedConsoleTab == i;
                var b = V.Button(V.Box(V.T(names[i], 10, FontWeights.SemiBold, sel ? t.Primary : t.Secondary), V.P(12, 6), sel ? t.A(0.15) : Brushes.Transparent, 0), () => { _app.SelectedConsoleTab = idx; Render(); });
                tabs.Children.Add(b);
            }
            var actions = V.H(6);
            if (_app.SelectedConsoleTab == 1)
            {
                var fix = V.Button(V.Box(V.H(3, Sym.Icon("sparkles", 9.5, t.Accent), V.T("Fix with AI", 10, FontWeights.Medium, t.Accent)), V.P(6, 2), t.A(0.14), 4), () => { if (_terminal != null) _app.Notify("agent:fix:" + _terminal.Recent()); });
                fix.ToolTip = "Send recent terminal output/error to AI Agent";
                actions.Children.Add(fix);
                actions.Children.Add(V.Tip(V.Button(Sym.Icon("arrow.clockwise", 10.5, t.Secondary), () => { if (_terminal != null) _terminal.Restart(); }), "Restart Active Shell"));
            }
            actions.Children.Add(V.Tip(V.Button(Sym.Icon("trash", 11, t.Secondary), () =>
            {
                if (_app.SelectedConsoleTab == 1 && _terminal != null) _terminal.Clear();
                else { _app.ConsoleOutput = ""; _app.Notify("consoleOutput"); }
            }), _app.SelectedConsoleTab == 1 ? "Clear Terminal (Ctrl+K)" : "Clear"));
            actions.Children.Add(V.Tip(V.Button(Sym.Icon(_max ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", 10, t.Secondary), () => { _max = !_max; Render(); }), _max ? "Restore Panel Size" : "Maximize Panel"));
            actions.Children.Add(V.Tip(V.Button(Sym.Icon("xmark", 10, t.Secondary), _app.ToggleConsole), "Close Panel"));
            _toolbar.Child = V.Box(V.H(6, tabs, V.Sp(), V.Box(actions, V.P(0, 0, 8, 0), null, 0)), V.P(0), t.WindowBackground, 0);

            _stage.Height = _max ? 520 : Math.Max(130, Math.Min(520, _height));
            _stage.Background = t.EditorBackground;
            switch (_app.SelectedConsoleTab)
            {
                case 0:
                    if (_output == null)
                    {
                        _output = new TextBox { IsReadOnly = true, FontFamily = UIFonts.Mono, FontSize = 12, Padding = new Thickness(10), TextWrapping = TextWrapping.Wrap, BorderThickness = new Thickness(0), Background = Brushes.Transparent, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
                        _output.Style = null;
                        _output.CaretBrush = Brushes.Transparent;
                        _output.SelectionBrush = t.Accent;
                    }
                    _output.Text = Out(); _output.Foreground = OutColor(); _output.ScrollToEnd();
                    _stage.Child = _output;
                    break;
                case 1:
                    if (_terminal == null) _terminal = new TerminalView(_app.WorkspaceFolder ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
                    _stage.Child = _terminal;
                    break;
                case 2:
                    _stage.Child = V.Vs(8, V.Sp(), Sym.Icon("checkmark.seal.fill", 22, t.Op(t.SysGreen, 0.75)), V.T("No problems detected in workspace", 12, FontWeights.Medium, t.Secondary), V.Sp());
                    break;
                default:
                    _stage.Child = V.Vs(8, V.Sp(), Sym.Icon("chart.bar.xaxis", 22, t.Secondary), V.T("Static analysis runs when a project is indexed", 12, FontWeights.Medium, t.Secondary), V.Sp());
                    break;
            }
        }
    }

    /// <summary>Shell session using Win32 ConPTY (fallback to redirected stdio PowerShell) for the TERMINAL tab.</summary>
    public class TerminalView : Grid
    {
        readonly string _cwd;
        TerminalSession _session;
        readonly TextBox _out, _in;
        readonly StringBuilder _buf = new StringBuilder();

        public TerminalView(string cwd)
        {
            _cwd = cwd;
            var t = Theme.Current;
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            _out = new TextBox { IsReadOnly = true, FontFamily = UIFonts.Mono, FontSize = 13, Padding = new Thickness(10, 8, 10, 0), BorderThickness = new Thickness(0), Background = Brushes.Transparent, Foreground = t.EditorText, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, TextWrapping = TextWrapping.Wrap, CaretBrush = Brushes.Transparent };
            SetRow(_out, 0); Children.Add(_out);
            var field = Styles.Field("", 13, t.EditorText, t.Secondary, out _in);
            _in.FontFamily = UIFonts.Mono;
            var prompt = V.Box(V.H(6, V.Mono("❯", 13, FontWeights.Bold, t.SysGreen), V.Flex(field)), V.P(10, 6), null, 0);
            SetRow(prompt, 1); Children.Add(prompt);
            _in.KeyDown += delegate(object s, KeyEventArgs e)
            {
                if (e.Key == Key.C && (Keyboard.Modifiers & ModifierKeys.Control) != 0 && string.IsNullOrEmpty(_in.SelectedText) && _session != null && _session.IsRunning)
                {
                    _session.WriteInput("\x03");
                    e.Handled = true;
                    return;
                }
                if (e.Key == Key.Enter && _session != null && _session.IsRunning)
                {
                    string cmd = _in.Text; _in.Text = "";
                    if (!_session.UsingConPty) Append(cmd + "\n");
                    _session.WriteInput(cmd + "\r\n");
                    e.Handled = true;
                }
            };
            Loaded += delegate { if (_session == null) Start(); _in.Focus(); };
        }

        void Start()
        {
            try
            {
                _session = new TerminalSession();
                _session.OutputReceived += raw =>
                {
                    string clean = ConPty.StripAnsi(raw);
                    if (!string.IsNullOrEmpty(clean))
                        Dispatcher.BeginInvoke(new Action(() => Append(clean)));
                };
                _session.Exited += code =>
                {
                    Dispatcher.BeginInvoke(new Action(() => Append("\n[Process exited with code " + code + "]\n")));
                };
                _session.Start("powershell.exe -NoLogo", _cwd, 120, 34);
                Append((_session.UsingConPty ? "ConPTY PowerShell" : "PowerShell") + " — " + _cwd + "\n");
            }
            catch (Exception ex) { Append("Failed to start shell: " + ex.Message + "\n"); }
        }

        void Append(string s) { _buf.Append(s); if (_buf.Length > 400000) _buf.Remove(0, 100000); _out.Text = _buf.ToString(); _out.ScrollToEnd(); }
        public void Clear() { _buf.Clear(); _out.Text = ""; }
        public string Recent() { var s = _buf.ToString(); return s.Length > 4000 ? s.Substring(s.Length - 4000) : s; }
        public void Restart() { try { if (_session != null) _session.Dispose(); } catch { } _session = null; Clear(); Start(); }
    }

    /// <summary>
    /// RenderedMarkdownDocumentView + MarkdownTextView: headings (ATX/setext), paragraphs with hard breaks, nested and task lists,
    /// GFM tables with column alignment, block quotes and GitHub alerts, fenced code (highlighted cards), images (local, remote,
    /// linked badges), README-style HTML blocks, front matter and LaTeX ($…$, \(…\), $$…$$, \[…\], \begin{…}, ```math).
    /// Relative links and images resolve against the document's folder; file links open in the Preview pane with #L10-L20 ranges.
    /// </summary>
    public static class MarkdownView
    {
        /// <summary>Folder relative links and images resolve against while a document renders (UI thread only).</summary>
        static string _base;

        public static UIElement Render(string md) { return Render(md, 14); }
        public static UIElement Render(string md, double size) { return Render(md, size, null); }

        public static UIElement Render(string md, double size, string baseDir)
        {
            string saved = _base;
            _base = baseDir ?? saved ?? AppState.Shared.WorkspaceFolder;
            try { return V.Box(Blocks((md ?? "").Replace("\r\n", "\n").Split('\n'), size, Theme.Current.Primary), V.P(24), null, 0); }
            finally { _base = saved; }
        }

        // ── inline ──────────────────────────────────────────────────────────

        static readonly System.Text.RegularExpressions.Regex InlineRe = new System.Text.RegularExpressions.Regex(
            @"((?<![\\$])\$(?!\$)(?=[^\s$])[^$\n]*?[^\s\\$]\$(?!\d)" +
            @"|\\\(.+?\\\)" +
            @"|\[!\[[^\]]*\]\([^)\s]+(?:\s+""[^""]*"")?\)\]\([^)\s]+\)" +
            @"|!\[[^\]]*\]\([^)\s]+(?:\s+""[^""]*"")?\)" +
            @"|\[[^\]]+\]\([^)]+\)" +
            @"|<(?:https?://|mailto:)[^>\s]+>" +
            @"|https?://[^\s<>()\[\]`]*[^\s<>()\[\]`.,;:!?'""*_~]" +
            @"|\*\*[^*\n]+\*\*" +
            @"|(?<![\w\\])__(?=\S)[^_\n]+?(?<=\S)__(?!\w)" +
            @"|~~(?=\S)[^~\n]+?(?<=\S)~~" +
            @"|`[^`]+`" +
            @"|\*[^*\s][^*\n]*\*" +
            @"|(?<![\w\\])_[^_\s](?:[^_\n]*?[^_\s\\])?_(?!\w))");

        /// <summary>Inline code that names a source file becomes a clickable file chip (MarkdownAttrCache.inlineCodeFileRegex).</summary>
        static readonly System.Text.RegularExpressions.Regex FileRefRe = new System.Text.RegularExpressions.Regex(
            @"^[^`\n\s]+?\.(?:swift|ts|tsx|js|jsx|svelte|vue|astro|py|rs|go|java|kt|kts|c|cpp|cc|h|hpp|m|mm|html|css|scss|json|yaml|yml|toml|sql|sh|md|dart|rb|php|cs|proto|graphql|xaml|csproj|ps1|bat|cmd|txt|csv|pdf|png|jpg|ipynb)(?:#L\d+(?:-L?\d+)?|:\d+(?::\d+)?)?$",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);

        static readonly System.Text.RegularExpressions.Regex EscapeRe = new System.Text.RegularExpressions.Regex(@"\\([\\`*_{}\[\]()#+\-.!|~$<>])");

        static string Unescape(string s) { return EscapeRe.Replace(s, "$1"); }

        /// <summary>Inline markdown: **bold**, *italic*, ~~strike~~, `code` (file chips), links, autolinks, images and inline TeX.</summary>
        public static TextBlock Inline(string text, double size, Brush fg)
        {
            var tb = V.Wrap(V.T("", size, FontWeights.Normal, fg), TextAlignment.Left);
            tb.LineHeight = Math.Round(size * 1.45);
            string baseDir = _base;
            int pos = 0;
            foreach (System.Text.RegularExpressions.Match m in InlineRe.Matches(text ?? ""))
            {
                if (m.Index > pos) tb.Inlines.Add(new System.Windows.Documents.Run(Unescape(text.Substring(pos, m.Index - pos))));
                tb.Inlines.Add(InlineFor(m.Value, size, fg, baseDir));
                pos = m.Index + m.Length;
            }
            if (text != null && pos < text.Length) tb.Inlines.Add(new System.Windows.Documents.Run(Unescape(text.Substring(pos))));
            return tb;
        }

        static System.Windows.Documents.Inline InlineFor(string v, double size, Brush fg, string baseDir)
        {
            var t = Theme.Current;
            if (v.StartsWith("$") || v.StartsWith("\\("))
            {
                // inline TeX sits on the text baseline
                string expr = v.StartsWith("$") ? v.Substring(1, v.Length - 2) : v.Substring(2, v.Length - 4);
                var mv = new MathView(expr, size, false, fg);
                mv.RenderTransform = new TranslateTransform(0, mv.Descent);
                return new System.Windows.Documents.InlineUIContainer(mv) { BaselineAlignment = BaselineAlignment.Baseline };
            }
            if (v.StartsWith("[!["))
            {
                var mm = System.Text.RegularExpressions.Regex.Match(v, @"^\[!\[([^\]]*)\]\(([^)\s]+)(?:\s+""[^""]*"")?\)\]\(([^)\s]+)\)$");
                return new System.Windows.Documents.InlineUIContainer(MakeImage(mm.Groups[2].Value, mm.Groups[1].Value, 0, mm.Groups[3].Value, true)) { BaselineAlignment = BaselineAlignment.Center };
            }
            if (v.StartsWith("!["))
            {
                var mm = System.Text.RegularExpressions.Regex.Match(v, @"^!\[([^\]]*)\]\(([^)\s]+)");
                return new System.Windows.Documents.InlineUIContainer(MakeImage(mm.Groups[2].Value, mm.Groups[1].Value, 0, null, true)) { BaselineAlignment = BaselineAlignment.Center };
            }
            if (v.StartsWith("["))
            {
                int mid = v.IndexOf("](", StringComparison.Ordinal);
                string label = v.Substring(1, mid - 1), url = v.Substring(mid + 2, v.Length - mid - 3).Trim();
                int sp = url.IndexOf(" \"", StringComparison.Ordinal);
                if (sp > 0) url = url.Substring(0, sp);
                System.Windows.Documents.Inline content = label.Length > 2 && label.StartsWith("`") && label.EndsWith("`")
                    ? (System.Windows.Documents.Inline)new System.Windows.Documents.Run(label.Substring(1, label.Length - 2)) { FontFamily = UIFonts.Mono, FontSize = size * 0.88, Background = t.P(0.08) }
                    : new System.Windows.Documents.Run(Unescape(label.Replace("**", "")));
                return Link(content, url, baseDir);
            }
            if (v.StartsWith("<")) { string url = v.Substring(1, v.Length - 2); return Link(new System.Windows.Documents.Run(url.StartsWith("mailto:") ? url.Substring(7) : url), url, baseDir); }
            if (v.StartsWith("http")) return Link(new System.Windows.Documents.Run(v), v, baseDir);
            if (v.StartsWith("**") || v.StartsWith("__"))
            {
                string inner = v.Substring(2, v.Length - 4);
                bool code = inner.Length > 2 && inner.StartsWith("`") && inner.EndsWith("`");
                var run = new System.Windows.Documents.Run(code ? inner.Substring(1, inner.Length - 2) : Unescape(inner)) { FontWeight = FontWeights.SemiBold };
                if (code) { run.FontFamily = UIFonts.Mono; run.FontSize = size * 0.88; run.Background = t.P(0.08); }
                return run;
            }
            if (v.StartsWith("~~")) return new System.Windows.Documents.Run(Unescape(v.Substring(2, v.Length - 4))) { TextDecorations = TextDecorations.Strikethrough, Foreground = t.Secondary };
            if (v.StartsWith("`"))
            {
                string code = v.Substring(1, v.Length - 2);
                var run = new System.Windows.Documents.Run(code) { FontFamily = UIFonts.Mono, FontSize = size * 0.88, Background = t.P(0.08) };
                if (FileRefRe.IsMatch(code.Trim())) { run.Foreground = t.Accent; return Link(run, "microcode-file://" + Uri.EscapeDataString(code.Trim()), baseDir); }
                return run;
            }
            return new System.Windows.Documents.Run(Unescape(v.Substring(1, v.Length - 2))) { FontStyle = FontStyles.Italic };
        }

        static System.Windows.Documents.Hyperlink Link(System.Windows.Documents.Inline content, string url, string baseDir)
        {
            var t = Theme.Current;
            var link = new System.Windows.Documents.Hyperlink(content) { Foreground = t.Accent, TextDecorations = null, Cursor = Cursors.Hand };
            link.ToolTip = url.StartsWith("microcode-file://") ? Uri.UnescapeDataString(url.Substring(17)) : url;
            link.Click += delegate { OpenLink(url, baseDir); };
            return link;
        }

        /// <summary>MarkdownAttrCache.handleOpenURL: web links open in the browser; file links (relative, file://, microcode-file://,
        /// optional #L10-L20 or :12) open in the editor (Code mode, text files) or the Preview pane; unknown names are copied.</summary>
        public static void OpenLink(string url, string baseDir)
        {
            if (string.IsNullOrWhiteSpace(url)) return;
            url = url.Trim();
            string lower = url.ToLowerInvariant();
            if (lower.StartsWith("http://") || lower.StartsWith("https://") || lower.StartsWith("mailto:"))
            {
                try { Process.Start(url); } catch (Exception ex) { Debug.WriteLine("open link: " + ex.Message); }
                return;
            }
            if (url.StartsWith("#")) return; // in-page anchors
            string raw;
            if (lower.StartsWith("microcode-file://")) raw = Uri.UnescapeDataString(url.Substring(17));
            else if (lower.StartsWith("file:")) { Uri u; raw = Uri.TryCreate(url, UriKind.Absolute, out u) ? u.LocalPath : Uri.UnescapeDataString(url.Substring(5).TrimStart('/')); }
            else raw = Uri.UnescapeDataString(url);
            int start = 0, end = 0;
            var m = System.Text.RegularExpressions.Regex.Match(raw, @"\s*#L(\d+)(?:-L?(\d+))?$");
            if (m.Success) { start = int.Parse(m.Groups[1].Value); end = m.Groups[2].Success ? int.Parse(m.Groups[2].Value) : start; raw = raw.Substring(0, m.Index); }
            else
            {
                m = System.Text.RegularExpressions.Regex.Match(raw, @":(\d+)(?::\d+)?$");
                if (m.Success && m.Index > 1) { start = end = int.Parse(m.Groups[1].Value); raw = raw.Substring(0, m.Index); }
                else { int hash = raw.IndexOf('#'); if (hash > 0) raw = raw.Substring(0, hash); }
            }
            string path = ResolveFile(raw, baseDir);
            var app = AppState.Shared;
            if (path == null)
            {
                try { Clipboard.SetText(raw); } catch (Exception ex) { Debug.WriteLine("clipboard: " + ex.Message); }
                return;
            }
            string kind = PreviewDock.Detect(path);
            if (app.Mode != EditorMode.AIAgent && app.Surface == Surface.Editor && (kind == "code" || kind == "markdown") && !app.AgenticContextVisible)
            {
                app.LoadFile(path);
                var win = Application.Current != null ? Application.Current.MainWindow as MainWindow : null;
                if (win != null && start > 0) win.GoToLine(start);
                return;
            }
            PreviewDock.OpenFile(path, start, end);
        }

        static readonly HashSet<string> SkipDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".git", "node_modules", "bin", "obj", "build", "dist", ".build", "Pods", "DerivedData", ".venv", "venv", "__pycache__", "target", ".next", ".dart_tool" };

        /// <summary>PreviewDockService.resolveFileURL(pathOrName:workspaceRoot:): absolute, relative to the document, relative to the
        /// workspace, then a bounded search of the workspace by file name.</summary>
        public static string ResolveFile(string raw, string baseDir)
        {
            if (string.IsNullOrWhiteSpace(raw)) return null;
            raw = raw.Trim().Replace('/', Path.DirectorySeparatorChar);
            try
            {
                if (Path.IsPathRooted(raw)) return File.Exists(raw) ? Path.GetFullPath(raw) : null;
                var ws = AppState.Shared.WorkspaceFolder;
                foreach (var root in new[] { baseDir, ws })
                {
                    if (string.IsNullOrEmpty(root)) continue;
                    string p = Path.GetFullPath(Path.Combine(root, raw));
                    if (File.Exists(p)) return p;
                }
                if (string.IsNullOrEmpty(ws) || !Directory.Exists(ws)) return null;
                string name = Path.GetFileName(raw), tail = raw.TrimStart('.', '\\');
                var queue = new Queue<string>();
                queue.Enqueue(ws);
                int visited = 0;
                while (queue.Count > 0 && visited < 4000)
                {
                    string dir = queue.Dequeue(); visited++;
                    string[] files, dirs;
                    try { files = Directory.GetFiles(dir, name); dirs = Directory.GetDirectories(dir); }
                    catch (UnauthorizedAccessException) { continue; }
                    catch (IOException) { continue; }
                    foreach (var f in files) if (f.EndsWith(tail, StringComparison.OrdinalIgnoreCase)) return f;
                    foreach (var d in dirs) if (!SkipDirs.Contains(Path.GetFileName(d))) queue.Enqueue(d);
                }
            }
            catch (ArgumentException) { }
            catch (NotSupportedException) { }
            catch (PathTooLongException) { }
            return null;
        }

        // ── images ──────────────────────────────────────────────────────────

        static Uri ResolveImage(string src)
        {
            if (string.IsNullOrWhiteSpace(src)) return null;
            src = src.Trim().Trim('<', '>');
            Uri u;
            if (src.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || src.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                return Uri.TryCreate(src, UriKind.Absolute, out u) ? u : null;
            if (src.StartsWith("data:", StringComparison.OrdinalIgnoreCase)) return null;
            string local = src;
            if (local.StartsWith("file:", StringComparison.OrdinalIgnoreCase)) { if (Uri.TryCreate(local, UriKind.Absolute, out u)) local = u.LocalPath; }
            else
            {
                int q = local.IndexOfAny(new[] { '?', '#' });
                if (q > 0) local = local.Substring(0, q);
                local = Uri.UnescapeDataString(local);
            }
            string path = ResolveFile(local, _base);
            return path != null ? new Uri(path) : null;
        }

        /// <summary>ChatMediaBlockView for images: shown at pixel size, shrunk to fit; SVG or failed loads fall back to the alt text.</summary>
        static FrameworkElement MakeImage(string src, string alt, double width, string href, bool inline)
        {
            var t = Theme.Current;
            var fallback = V.H(4, Sym.Icon("photo", 11, t.Secondary), V.T(string.IsNullOrEmpty(alt) ? Path.GetFileName(src ?? "") : alt, 11.5, FontWeights.Normal, t.Secondary));
            var host = new Border { HorizontalAlignment = HorizontalAlignment.Left, ToolTip = string.IsNullOrEmpty(alt) ? src : alt };
            Uri uri = ResolveImage(src);
            if (uri == null || (src ?? "").Split('?')[0].EndsWith(".svg", StringComparison.OrdinalIgnoreCase)) { host.Child = fallback; return Clickable(host, href); }
            var img = new Image { Stretch = Stretch.Uniform, HorizontalAlignment = HorizontalAlignment.Left };
            RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
            Action sized = () =>
            {
                var b = img.Source as System.Windows.Media.Imaging.BitmapSource;
                if (b == null) return;
                double w = width > 0 ? width : b.PixelWidth;
                if (inline) w = Math.Min(w, 640); // inside a line of text there is no width to shrink into
                img.MaxWidth = w;
                img.MaxHeight = width > 0 ? w * b.PixelHeight / Math.Max(1, b.PixelWidth) : b.PixelHeight;
            };
            try
            {
                var bmp = new System.Windows.Media.Imaging.BitmapImage();
                bmp.BeginInit();
                bmp.UriSource = uri;
                if (uri.IsFile) { bmp.CacheOption = System.Windows.Media.Imaging.BitmapCacheOption.OnLoad; bmp.CreateOptions = System.Windows.Media.Imaging.BitmapCreateOptions.IgnoreImageCache; }
                bmp.EndInit();
                img.Source = bmp;
                if (bmp.IsDownloading)
                {
                    img.MaxWidth = width > 0 ? width : 1; img.MaxHeight = 1;
                    bmp.DownloadCompleted += delegate { sized(); };
                    bmp.DownloadFailed += delegate { host.Child = fallback; };
                    bmp.DecodeFailed += delegate { host.Child = fallback; };
                }
                else sized();
                host.Child = img;
            }
            catch (Exception ex)
            {
                Debug.WriteLine("markdown image: " + ex.Message);
                host.Child = fallback;
            }
            if (!inline) host.Margin = new Thickness(0, 2, 0, 2);
            return Clickable(host, href);
        }

        static FrameworkElement Clickable(FrameworkElement e, string href)
        {
            if (string.IsNullOrEmpty(href)) return e;
            string baseDir = _base;
            e.Cursor = Cursors.Hand;
            e.MouseLeftButtonUp += (s, a) => { a.Handled = true; OpenLink(href, baseDir); };
            return e;
        }

        // ── code ────────────────────────────────────────────────────────────

        public static string LangExt(string lang)
        {
            switch ((lang ?? "").ToLowerInvariant())
            {
                case "python": case "py": return "py"; case "javascript": case "js": return "js"; case "typescript": case "ts": return "ts";
                case "swift": return "swift"; case "rust": case "rs": return "rs"; case "go": return "go"; case "c": return "c"; case "cpp": case "c++": return "cpp";
                case "csharp": case "cs": case "c#": return "cs"; case "java": return "java"; case "kotlin": return "kt"; case "ruby": case "rb": return "rb";
                case "html": return "html"; case "css": return "css"; case "json": return "json"; case "bash": case "sh": case "shell": case "zsh": return "sh";
                case "powershell": case "ps1": return "ps1"; case "sql": return "sql"; case "yaml": case "yml": return "yaml"; case "markdown": case "md": return "md";
                default: return lang;
            }
        }

        /// <summary>NativeCodeBlockView: language badge, line count, Open in Editor, Copy and a highlighted read-only editor.</summary>
        public static UIElement CodeCard(string code, string lang, double size)
        {
            var t = Theme.Current;
            code = (code ?? "").TrimEnd('\n', '\r');
            int lines = code.Split('\n').Length;
            string language = string.IsNullOrEmpty(lang) ? "text" : AppState.DetectLanguage("x." + LangExt(lang));
            Btn copyBtn = null;
            Func<string, string, Action, Btn> small = (icon, label, a) => V.Button(V.Box(V.H(3, Sym.Icon(icon, 9.5, t.Secondary), V.T(label, 9.5, FontWeights.Medium, t.Secondary)), V.P(6, 3), t.P(0.05), 4), a);
            var editorBtn = small("arrow.up.right.square", "Editor", () =>
            {
                var app = AppState.Shared;
                app.NewFile();
                var f = app.CurrentFile;
                if (f != null) { f.Content = code; f.Language = language; app.Notify("files"); }
                app.SwitchToMode(EditorMode.Code);
            });
            editorBtn.ToolTip = "Open snippet in Code Editor";
            copyBtn = small("doc.on.doc", "Copy", () =>
            {
                try { Clipboard.SetText(code); } catch (Exception ex) { Debug.WriteLine("copy code: " + ex.Message); return; }
                copyBtn.Child = V.Box(V.H(3, Sym.Icon("checkmark", 9.5, t.Primary), V.T("Copied", 9.5, FontWeights.Medium, t.Primary)), V.P(6, 3), t.P(0.05), 4);
            });
            var header = V.H(8, V.Box(V.Mono(string.IsNullOrEmpty(lang) ? "TEXT" : lang.ToUpperInvariant(), 9, FontWeights.SemiBold, t.Secondary), V.P(5, 1.5), t.P(0.06), 3.5),
                V.Mono(lines + (lines == 1 ? " line" : " lines"), 9.5, FontWeights.Normal, t.Secondary), V.Sp(), editorBtn, copyBtn);
            var ed = new CodeEditorView(code, language, Math.Max(11, Math.Min(13, size)));
            ed.Box.IsReadOnly = true;
            ed.Height = Math.Min(420, Math.Max(2, lines) * Math.Max(15, ed.LineHeight) + 18);
            var col = V.VLead(0, V.Self(V.Box(header, V.P(10, 6), null, 0), Cross.Stretch), V.Self(V.Line(t.P(0.32 * 0.12), true), Cross.Stretch), V.Self(ed, Cross.Stretch));
            col.Align = Cross.Stretch;
            var card = V.Box(col, V.P(0), t.EditorBackground, 8, t.P(0.13), 1);
            card.ClipToBounds = true;
            card.Margin = new Thickness(0, 6, 0, 6);
            return card;
        }

        // ── math ────────────────────────────────────────────────────────────

        public static bool IsMathFence(string lang, string body)
        {
            if (lang == "math" || lang == "katex" || lang == "mathjax") return true;
            if (lang == "latex" || lang == "tex") return !body.Contains("\\documentclass") && !body.Contains("\\begin{document}") && !body.Contains("\\usepackage");
            return false;
        }

        /// <summary>Reads a display equation starting at lines[i]; leaves i on its last line.</summary>
        static string CollectMath(string[] lines, ref int i)
        {
            string first = lines[i].Trim();
            string open, close;
            if (first.StartsWith("$$")) { open = "$$"; close = "$$"; }
            else if (first.StartsWith("\\[")) { open = "\\["; close = "\\]"; }
            else
            {
                var m = System.Text.RegularExpressions.Regex.Match(first, @"^\\begin\{([a-zA-Z*]+)\}");
                string env = m.Groups[1].Value;
                var sb0 = new StringBuilder();
                for (; i < lines.Length; i++) { sb0.AppendLine(lines[i]); if (lines[i].Contains("\\end{" + env + "}")) break; }
                return sb0.ToString();
            }
            string rest = first.Substring(open.Length);
            int endHere = rest.IndexOf(close, StringComparison.Ordinal);
            if (endHere >= 0) return rest.Substring(0, endHere);
            var sb = new StringBuilder(rest).Append('\n');
            for (i = i + 1; i < lines.Length; i++)
            {
                int k = lines[i].IndexOf(close, StringComparison.Ordinal);
                if (k >= 0) { sb.Append(lines[i].Substring(0, k)); break; }
                sb.AppendLine(lines[i]);
            }
            return sb.ToString();
        }

        // ── blocks ──────────────────────────────────────────────────────────

        static readonly System.Text.RegularExpressions.Regex HeadingRe = new System.Text.RegularExpressions.Regex(@"^(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$");
        static readonly System.Text.RegularExpressions.Regex RuleRe = new System.Text.RegularExpressions.Regex(@"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$");
        static readonly System.Text.RegularExpressions.Regex ListRe = new System.Text.RegularExpressions.Regex(@"^(\s*)([-*+]|\d{1,9}[.)])[ \t]+(.*)$");
        static readonly System.Text.RegularExpressions.Regex TableSepRe = new System.Text.RegularExpressions.Regex(@"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$");
        static readonly System.Text.RegularExpressions.Regex FenceRe = new System.Text.RegularExpressions.Regex(@"^(`{3,}|~{3,})\s*([^`\s]*)");
        static readonly System.Text.RegularExpressions.Regex DisplayEnvRe = new System.Text.RegularExpressions.Regex(@"^\\begin\{(equation|align|alignat|gather|multline|eqnarray|displaymath|aligned|gathered|cases|matrix|pmatrix|bmatrix|vmatrix|Bmatrix|split)\*?\}");
        static readonly System.Text.RegularExpressions.Regex HtmlStartRe = new System.Text.RegularExpressions.Regex(
            @"^(?:<!--|</?(?:address|article|aside|blockquote|center|details|div|dl|figure|figcaption|footer|h[1-6]|header|hr|li|main|nav|ol|p|picture|section|summary|table|tbody|td|th|thead|tr|ul|img|a|br|video|source|sub|sup|kbd|b|strong|em|span|code)(?:[\s/>]|$))",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);

        static bool IsBlockStart(string tl)
        {
            return tl.Length == 0 || tl.StartsWith("#") || tl.StartsWith(">") || tl.StartsWith("```") || tl.StartsWith("~~~") || tl.StartsWith("$$") || tl.StartsWith("\\[")
                || ListRe.IsMatch(tl) || RuleRe.IsMatch(tl) || HtmlStartRe.IsMatch(tl);
        }

        static Stack Blocks(string[] lines, double size, Brush fg)
        {
            var t = Theme.Current;
            var root = V.VLead(10);
            root.Align = Cross.Stretch;
            var para = new StringBuilder();
            Action flush = () =>
            {
                string p = para.ToString().Trim();
                para.Clear();
                if (p.Length == 0) return;
                if (System.Text.RegularExpressions.Regex.IsMatch(p, @"^(?:\[?!\[[^\]]*\]\([^)]+\)(?:\]\([^)]+\))?\s*)+$"))
                {
                    // a paragraph that is only images: lay them out as blocks (badges flow in a row)
                    var wrap = new WrapPanel();
                    foreach (System.Text.RegularExpressions.Match im in System.Text.RegularExpressions.Regex.Matches(p, @"(\[)?!\[([^\]]*)\]\(([^)\s]+)(?:\s+""[^""]*"")?\)(?:\]\(([^)\s]+)\))?"))
                    {
                        var e = MakeImage(im.Groups[3].Value, im.Groups[2].Value, 0, im.Groups[4].Success ? im.Groups[4].Value : null, false);
                        e.Margin = new Thickness(0, 0, 6, 4);
                        e.VerticalAlignment = VerticalAlignment.Bottom; // images in a row sit on a common baseline
                        wrap.Children.Add(e);
                    }
                    root.Children.Add(wrap);
                    return;
                }
                root.Children.Add(Inline(p, size, fg));
            };
            int start = 0;
            if (lines.Length > 2 && lines[0].Trim() == "---")
            {
                // YAML front matter
                int close = -1;
                for (int k = 1; k < Math.Min(lines.Length, 120); k++) if (lines[k].Trim() == "---" || lines[k].Trim() == "...") { close = k; break; }
                if (close > 1 && lines.Skip(1).Take(close - 1).Any(x => x.Contains(":")))
                {
                    root.Children.Add(CodeCard(string.Join("\n", lines.Skip(1).Take(close - 1)), "yaml", size));
                    start = close + 1;
                }
            }
            for (int i = start; i < lines.Length; i++)
            {
                string l = lines[i];
                string tl = l.Trim();

                var fence = FenceRe.Match(tl);
                if (fence.Success)
                {
                    flush();
                    string marker = fence.Groups[1].Value;
                    string fenceLang = fence.Groups[2].Value.Trim().ToLowerInvariant();
                    var code = new StringBuilder();
                    int indent = l.Length - l.TrimStart().Length;
                    for (i++; i < lines.Length; i++)
                    {
                        string ct = lines[i].Trim();
                        if (ct.StartsWith(marker.Substring(0, 3)) && ct.TrimStart(marker[0]).Trim().Length == 0 && ct.Length >= marker.Length) break;
                        string cl = lines[i];
                        int strip = Math.Min(indent, cl.Length - cl.TrimStart().Length);
                        code.Append(cl.Substring(strip)).Append('\n');
                    }
                    string body = code.ToString().TrimEnd('\n', '\r');
                    if (IsMathFence(fenceLang, body)) root.Children.Add(MathBlock.Create(body, size));
                    else root.Children.Add(CodeCard(body, fenceLang, size));
                    continue;
                }
                if (tl.StartsWith("$$") || tl.StartsWith("\\[") || DisplayEnvRe.IsMatch(tl))
                {
                    // display math: $$…$$, \[…\] or a top-level \begin{equation|align|…}
                    flush();
                    root.Children.Add(MathBlock.Create(CollectMath(lines, ref i), size));
                    continue;
                }
                if (tl.Length == 0) { flush(); continue; }

                // GFM table: header row, |:--|--:| separator, body rows
                if (tl.Contains("|") && i + 1 < lines.Length && lines[i + 1].Contains("-") && TableSepRe.IsMatch(lines[i + 1]) && (lines[i + 1].Contains("|") || tl.StartsWith("|")))
                {
                    flush();
                    var header = Cells(tl);
                    var aligns = Cells(lines[i + 1]).Select(c => c.StartsWith(":") && c.EndsWith(":") ? TextAlignment.Center : c.EndsWith(":") ? TextAlignment.Right : TextAlignment.Left).ToArray();
                    var rows = new List<string[]> { header };
                    for (i += 2; i < lines.Length && lines[i].Trim().Length > 0 && lines[i].Contains("|"); i++) rows.Add(Cells(lines[i]));
                    i--;
                    root.Children.Add(Table(rows, aligns, size, fg));
                    continue;
                }

                var hm = HeadingRe.Match(tl);
                if (hm.Success && !l.StartsWith("    "))
                {
                    flush();
                    root.Children.Add(Heading(hm.Groups[1].Value.Length, hm.Groups[2].Value, size, fg));
                    continue;
                }
                // setext headings: Title / ===== (h1) or Title / ----- (h2)
                if (para.Length == 0 && !IsBlockStart(tl) && i + 1 < lines.Length)
                {
                    string next = lines[i + 1].Trim();
                    if (next.Length >= 2 && (next.All(c => c == '=') || next.All(c => c == '-')))
                    {
                        root.Children.Add(Heading(next[0] == '=' ? 1 : 2, tl, size, fg));
                        i++;
                        continue;
                    }
                }
                if (RuleRe.IsMatch(l)) { flush(); root.Children.Add(V.Line(t.Separator, true)); continue; }

                var lm = ListRe.Match(l);
                if (lm.Success)
                {
                    flush();
                    var item = new StringBuilder(lm.Groups[3].Value.Trim());
                    // indented continuation lines belong to this item
                    while (i + 1 < lines.Length && lines[i + 1].Trim().Length > 0 && lines[i + 1].StartsWith("  ") && !ListRe.IsMatch(lines[i + 1]) && !FenceRe.IsMatch(lines[i + 1].Trim()))
                    {
                        i++;
                        item.Append(' ').Append(lines[i].Trim());
                    }
                    root.Children.Add(ListItem(lm.Groups[1].Value.Replace("\t", "    ").Length, lm.Groups[2].Value, item.ToString(), size, fg));
                    continue;
                }

                if (tl.StartsWith(">"))
                {
                    flush();
                    var inner = new List<string>();
                    for (; i < lines.Length && lines[i].Trim().StartsWith(">"); i++)
                    {
                        string q = lines[i].Trim().Substring(1);
                        inner.Add(q.StartsWith(" ") ? q.Substring(1) : q);
                    }
                    i--;
                    root.Children.Add(Quote(inner, size));
                    continue;
                }

                if (HtmlStartRe.IsMatch(tl))
                {
                    flush();
                    var html = new StringBuilder();
                    if (tl.StartsWith("<!--"))
                    {
                        for (; i < lines.Length; i++) if (lines[i].Contains("-->")) break;
                        continue;
                    }
                    for (; i < lines.Length && lines[i].Trim().Length > 0; i++) html.Append(lines[i]).Append('\n');
                    i--;
                    Html(html.ToString(), size, fg, root);
                    continue;
                }

                // paragraph text: two trailing spaces or a trailing backslash is a hard line break
                if (l.EndsWith("  ") || tl.EndsWith("\\")) para.Append(tl.TrimEnd('\\')).Append('\n');
                else para.Append(tl).Append(' ');
            }
            flush();
            return root;
        }

        static string[] Cells(string line)
        {
            string s = line.Trim();
            if (s.StartsWith("|")) s = s.Substring(1);
            if (s.EndsWith("|") && !s.EndsWith("\\|")) s = s.Substring(0, s.Length - 1);
            var cells = new List<string>();
            var sb = new StringBuilder();
            bool code = false;
            for (int k = 0; k < s.Length; k++)
            {
                char ch = s[k];
                if (ch == '\\' && k + 1 < s.Length && s[k + 1] == '|') { sb.Append('|'); k++; continue; }
                if (ch == '`') code = !code;
                if (ch == '|' && !code) { cells.Add(sb.ToString().Trim()); sb.Clear(); continue; }
                sb.Append(ch);
            }
            cells.Add(sb.ToString().Trim());
            return cells.ToArray();
        }

        /// <summary>TableBlockView: header row, hairline grid, per-column alignment, horizontal scrolling when wide.</summary>
        static UIElement Table(List<string[]> rows, TextAlignment[] aligns, double size, Brush fg)
        {
            var t = Theme.Current;
            var grid = new Grid();
            int cols = rows.Max(r => r.Length);
            for (int c = 0; c < cols; c++) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            for (int r = 0; r < rows.Count; r++)
            {
                grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                for (int c = 0; c < cols; c++)
                {
                    var tb = Inline(c < rows[r].Length ? rows[r][c] : "", size * 0.88, r == 0 ? fg : t.P(0.9));
                    if (r == 0) tb.FontWeight = FontWeights.SemiBold;
                    var al = c < aligns.Length ? aligns[c] : TextAlignment.Left;
                    tb.TextAlignment = al;
                    tb.HorizontalAlignment = al == TextAlignment.Right ? HorizontalAlignment.Right : al == TextAlignment.Center ? HorizontalAlignment.Center : HorizontalAlignment.Left;
                    var cell = V.Box(tb, V.P(10, 6), r == 0 ? t.P(0.06) : (r % 2 == 0 ? t.P(0.02) : Brushes.Transparent), 0, t.P(0.10), 0.5);
                    Grid.SetRow(cell, r); Grid.SetColumn(cell, c); grid.Children.Add(cell);
                }
            }
            return V.Self(V.Box(new ScrollViewer { Content = grid, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled }, V.P(0), null, 6, t.P(0.12), 1), Cross.Start);
        }

        /// <summary>HeadingView: H1 ×1.52, H2 ×1.30, H3 ×1.15, H4 ×1.05 with a hairline under H1/H2.</summary>
        static UIElement Heading(int level, string text, double size, Brush fg)
        {
            var t = Theme.Current;
            double hs = level == 1 ? size * 1.52 : level == 2 ? size * 1.30 : level == 3 ? size * 1.15 : level == 4 ? size * 1.05 : size;
            var h = Inline((text ?? "").Trim(), hs, fg);
            h.FontWeight = level <= 2 ? FontWeights.Bold : FontWeights.SemiBold;
            if (level > 2) return V.Box(h, V.P(0, level == 3 ? 6 : 2, 0, 2), null, 0);
            var col = V.VLead(6, h, V.Self(V.Line(t.Separator, true), Cross.Stretch));
            col.Align = Cross.Stretch;
            col.Margin = new Thickness(0, level == 1 ? 10 : 12, 0, 4);
            return col;
        }

        /// <summary>ListView row: • / ◦ / 1. markers, native checkbox for [ ] and [x].</summary>
        static UIElement ListItem(int indent, string marker, string text, double size, Brush fg)
        {
            var t = Theme.Current;
            UIElement bullet;
            bool ordered = char.IsDigit(marker[0]);
            if (text.StartsWith("[ ] ") || text.StartsWith("[x] ") || text.StartsWith("[X] "))
            {
                bool done = text[1] != ' ';
                bullet = Sym.Icon(done ? "checkmark.square.fill" : "square", size, done ? t.Accent : t.Secondary);
                text = text.Substring(4);
            }
            else bullet = V.T(ordered ? marker.TrimEnd(')', '.') + "." : indent >= 2 ? "◦" : "•", size, FontWeights.Normal, t.Secondary);
            var tb = Inline(text, size, fg);
            var b = bullet as FrameworkElement;
            var bt = bullet as TextBlock; // text markers; checkbox icons are SymbolIcons
            if (bt != null) { bt.LineHeight = tb.LineHeight; bt.VerticalAlignment = VerticalAlignment.Top; } // same line box => shared baseline
            else if (b != null) { b.VerticalAlignment = VerticalAlignment.Top; b.Margin = new Thickness(0, Math.Round(size * 0.18), 0, 0); }
            return V.Box(V.H(8, V.Self(bullet, Cross.Start), V.Flex(tb)), V.P(8 + Math.Min(indent, 16) * 6, 0, 0, 0), null, 0);
        }

        /// <summary>BlockquoteView, with GitHub alerts (> [!NOTE], [!TIP], [!IMPORTANT], [!WARNING], [!CAUTION]).</summary>
        static UIElement Quote(List<string> inner, double size)
        {
            var t = Theme.Current;
            Brush bar = t.P(0.25);
            UIElement title = null;
            if (inner.Count > 0)
            {
                var am = System.Text.RegularExpressions.Regex.Match(inner[0].Trim(), @"^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]$", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                if (am.Success)
                {
                    string kind = am.Groups[1].Value.ToUpperInvariant();
                    string icon = kind == "NOTE" ? "info.circle" : kind == "TIP" ? "checkmark.seal" : kind == "IMPORTANT" ? "exclamationmark.circle" : kind == "WARNING" ? "exclamationmark.triangle" : "exclamationmark.octagon";
                    bar = kind == "NOTE" ? t.SysBlue : kind == "TIP" ? t.SysGreen : kind == "IMPORTANT" ? t.SysPurple : kind == "WARNING" ? t.SysOrange : t.SysRed;
                    title = V.H(6, Sym.Icon(icon, size * 0.95, bar), V.T(kind.Substring(0, 1) + kind.Substring(1).ToLowerInvariant(), size, FontWeights.SemiBold, bar));
                    inner = inner.Skip(1).ToList();
                }
            }
            var body = Blocks(inner.ToArray(), size, title != null ? t.Primary : t.Secondary);
            if (title != null) body.Children.Insert(0, title);
            var box = V.Box(body, V.P(12, 2, 0, 2), null, 0, bar, 0);
            box.BorderThickness = new Thickness(3, 0, 0, 0);
            return box;
        }

        static readonly System.Text.RegularExpressions.Regex HtmlTokenRe = new System.Text.RegularExpressions.Regex(
            @"<h([1-6])\b[^>]*>(.*?)</h\1\s*>|<img\b[^>]*>|<a\b[^>]*>|</a\s*>|<br\s*/?>|<hr\s*/?>|<!--.*?-->|<[^>]+>|[^<]+",
            System.Text.RegularExpressions.RegexOptions.Singleline | System.Text.RegularExpressions.RegexOptions.IgnoreCase);

        static string Attr(string tag, string name)
        {
            var m = System.Text.RegularExpressions.Regex.Match(tag, @"\b" + name + @"\s*=\s*(?:""([^""]*)""|'([^']*)'|([^\s>]+))", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            return !m.Success ? null : m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Success ? m.Groups[2].Value : m.Groups[3].Value;
        }

        static string Decode(string s) { return System.Net.WebUtility.HtmlDecode(s ?? ""); }

        /// <summary>README-style HTML: headings, images (linked badges), links, paragraphs and line breaks, align="center".</summary>
        static void Html(string html, double size, Brush fg, Stack root)
        {
            var t = Theme.Current;
            bool center = System.Text.RegularExpressions.Regex.IsMatch(html, @"align\s*=\s*[""']?center", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            var text = new StringBuilder();
            WrapPanel images = null;
            string href = null;
            Action<FrameworkElement> add = e => { if (center) e.HorizontalAlignment = HorizontalAlignment.Center; root.Children.Add(center ? V.Self(e, Cross.Center) : e); };
            Action flushText = () =>
            {
                // HTML whitespace collapses to single spaces; only <br> breaks a line
                string s = System.Text.RegularExpressions.Regex.Replace(text.ToString(), @" *\n *", "\n").Trim();
                text.Clear();
                if (s.Length == 0) return;
                var tb = Inline(s, size, fg);
                if (center) tb.TextAlignment = TextAlignment.Center;
                add(tb);
            };
            Action flushImages = () => { if (images != null) { add(images); images = null; } };
            foreach (System.Text.RegularExpressions.Match m in HtmlTokenRe.Matches(html))
            {
                string v = m.Value;
                if (m.Groups[1].Success)
                {
                    flushText(); flushImages();
                    string inner = Decode(System.Text.RegularExpressions.Regex.Replace(m.Groups[2].Value, "<[^>]+>", "")).Trim();
                    if (inner.Length > 0) add((FrameworkElement)Heading(int.Parse(m.Groups[1].Value), inner, size, fg));
                }
                else if (v.StartsWith("<img", StringComparison.OrdinalIgnoreCase))
                {
                    if (text.ToString().Trim().Length > 0) flushText();
                    double w; double.TryParse((Attr(v, "width") ?? "").Replace("px", ""), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out w);
                    if (images == null) images = new WrapPanel();
                    var img = MakeImage(Attr(v, "src"), Attr(v, "alt"), w, href, false);
                    img.Margin = new Thickness(0, 0, 6, 4);
                    img.VerticalAlignment = VerticalAlignment.Bottom;
                    images.Children.Add(img);
                }
                else if (System.Text.RegularExpressions.Regex.IsMatch(v, @"^<a\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase)) { href = Attr(v, "href"); if (href != null) text.Append("["); }
                else if (System.Text.RegularExpressions.Regex.IsMatch(v, @"^</a\s*>$", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                {
                    if (href != null)
                    {
                        // close the markdown link we opened, or drop it when the anchor only wrapped images
                        string s = text.ToString();
                        int open = s.LastIndexOf('[');
                        if (open >= 0 && s.Substring(open + 1).Trim().Length > 0) text.Append("](").Append(href).Append(")");
                        else if (open >= 0) text.Remove(open, s.Length - open);
                    }
                    href = null;
                }
                else if (System.Text.RegularExpressions.Regex.IsMatch(v, @"^<br\s*/?>$", System.Text.RegularExpressions.RegexOptions.IgnoreCase)) text.Append("\n");
                else if (System.Text.RegularExpressions.Regex.IsMatch(v, @"^<hr\s*/?>$", System.Text.RegularExpressions.RegexOptions.IgnoreCase)) { flushText(); flushImages(); root.Children.Add(V.Line(t.Separator, true)); }
                else if (v.StartsWith("<"))
                {
                    if (System.Text.RegularExpressions.Regex.IsMatch(v, @"^</?(p|div|details|summary|table|tr|ul|ol|li|section|center|picture)\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase)) { flushText(); flushImages(); }
                    else if (System.Text.RegularExpressions.Regex.IsMatch(v, @"^<(b|strong)\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase) || System.Text.RegularExpressions.Regex.IsMatch(v, @"^</(b|strong)\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase)) text.Append("**");
                    else if (System.Text.RegularExpressions.Regex.IsMatch(v, @"^</?code\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase)) text.Append("`");
                }
                else
                {
                    if (images != null && v.Trim().Length > 0) flushImages();
                    text.Append(System.Text.RegularExpressions.Regex.Replace(Decode(v), @"\s+", " "));
                }
            }
            flushText(); flushImages();
        }
    }
}
