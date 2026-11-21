// Port of ContentView / AgenticEditorWorkspace / NativeSidebarSplitContainer / WorkspaceUnifiedHeaderBar /
// WindowTrafficLightsController + the macOS menu bar commands (MicroCodeApp.swift), as a native Windows window.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Shell;
using System.Windows.Threading;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public class MainWindow : Window
    {
        readonly AppState _app;
        readonly Grid _root = new Grid();
        readonly Border _page = new Border();
        // workspace (sidebar split)
        Grid _workspace;
        Border _sidebarClip, _sidebarInner, _splitter, _mainHost, _surfaceHost, _inspectorHost;
        HeaderBar _header;
        XcodeSidebar _xcodeSidebar;
        AgentSidebar _agentSidebar;
        EditorArea _editorArea;
        AgentView _agentView;
        WelcomeScreen _welcome;
        readonly Dictionary<EditorMode, UIElement> _modeViews = new Dictionary<EditorMode, UIElement>();
        double _revealed;
        TrafficLights _lights;
        MenuStrip _menuStrip;

        public MainWindow(AppState app)
        {
            _app = app;
            Title = "MicroCode";
            var wa = SystemParameters.WorkArea;
            Width = Math.Min(1440, wa.Width * 0.92); Height = Math.Min(900, wa.Height * 0.92);
            MinWidth = Math.Min(1200, wa.Width); MinHeight = Math.Min(800, wa.Height);
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            UseLayoutRounding = true;
            SnapsToDevicePixels = true;
            TextOptions.SetTextFormattingMode(this, TextFormattingMode.Ideal);
            FontFamily = UIFonts.UI;
            WindowChrome.SetWindowChrome(this, new WindowChrome
            {
                CaptionHeight = 36, ResizeBorderThickness = new Thickness(6), GlassFrameThickness = new Thickness(0, 0, 0, 1),
                UseAeroCaptionButtons = false, CornerRadius = new CornerRadius(0)
            });
            try
            {
                var icoPath = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "MicroCode.ico");
                if (File.Exists(icoPath)) Icon = System.Windows.Media.Imaging.BitmapFrame.Create(new Uri(icoPath));
            }
            catch { }

            _root.Children.Add(_page);
            _lights = new TrafficLights(this, app);
            _root.Children.Add(_lights);
            _menuStrip = new MenuStrip(this, app);
            _root.Children.Add(_menuStrip);
            Content = _root;
            if (FirstLaunchWelcome.ShouldShow)
            {
                FirstLaunchWelcome welcome = null;
                welcome = new FirstLaunchWelcome(() => _root.Children.Remove(welcome));
                _root.Children.Add(welcome);
            }
            _revealed = app.SidebarVisible ? app.SidebarWidth : 0;

            SourceInitialized += delegate { Native.StyleWindow(this, Theme.Current.IsDark); };
            StateChanged += delegate { _root.Margin = WindowState == WindowState.Maximized ? MaximizedInset() : new Thickness(0); };
            app.Changed += OnChanged;
            Closing += delegate(object s, System.ComponentModel.CancelEventArgs e)
            {
                var dirty = _app.OpenFiles.Where(f => f.IsUnsaved).ToList();
                if (dirty.Count > 0)
                {
                    var r = MessageBox.Show(this, "You have " + dirty.Count + " unsaved file(s). Save before closing?", "MicroCode", MessageBoxButton.YesNoCancel, MessageBoxImage.Warning);
                    if (r == MessageBoxResult.Cancel) { e.Cancel = true; return; }
                    if (r == MessageBoxResult.Yes) foreach (var f in dirty) _app.Save(f);
                }
                Defaults.Flush();
            };
            InstallShortcuts();
            Render();
        }

        static Thickness MaximizedInset()
        {
            var b = SystemParameters.WindowResizeBorderThickness;
            return new Thickness(b.Left + 4, b.Top + 4, b.Right + 4, b.Bottom + 4);
        }

        bool ShouldShowWelcome
        {
            get { return (_app.WorkspaceFolder == null && _app.OpenFiles.Count == 0 && _app.Mode == EditorMode.Code && _app.Surface == Surface.Editor) || _app.ShowingWelcomeHome; }
        }

        bool ModeHasOwnSidebar
        {
            get
            {
                var m = _app.Mode;
                return m == EditorMode.Embedded || m == EditorMode.Browser || m == EditorMode.ApiClient || m == EditorMode.RemoteX || m == EditorMode.Notebook || m == EditorMode.Playground;
            }
        }

        void OnChanged(string what)
        {
            switch (what)
            {
                case "theme":
                    Native.StyleWindow(this, Theme.Current.IsDark);
                    _workspace = null; _welcome = null; _editorArea = null; _agentView = null; _xcodeSidebar = null; _agentSidebar = null; _modeViews.Clear();
                    Render(); break;
                case "workspace": case "mode": case "files":
                    Render(); break;
                case "sidebar": AnimateSidebar(); break;
                case "sidebarWidth": if (_app.SidebarVisible) { _revealed = _app.SidebarWidth; ApplySidebarFrames(); } break;
                case "inspector": RenderInspector(); if (_header != null) _header.Render(); break;
                case "console": case "running": case "agentBar": if (_header != null) _header.Render(); break;
            }
            if (what.StartsWith("agent:"))
            {
                if (_agentView == null) _agentView = new AgentView(_app, false);
                _agentView.HandleCommand(what.Substring(6));
            }
        }

        public void Render()
        {
            var t = Theme.Current;
            Background = t.WorkspaceBackground;
            _root.Background = t.WorkspaceBackground;
            if (ShouldShowWelcome)
            {
                if (_welcome == null) _welcome = new WelcomeScreen(_app);
                _page.Child = _welcome;
                _lights.SetLeadingContextWelcome(true);
                return;
            }
            _welcome = null;
            _lights.SetLeadingContextWelcome(false);
            if (_workspace == null) BuildWorkspace();
            if (_page.Child != _workspace) _page.Child = _workspace;

            // sidebar content: editor surface => Xcode navigator, agent surface => agentic sidebar
            if (_app.Surface == Surface.Editor)
            {
                if (_xcodeSidebar == null) _xcodeSidebar = new XcodeSidebar(_app);
                if (_sidebarInner.Child != _xcodeSidebar) _sidebarInner.Child = _xcodeSidebar;
            }
            else
            {
                if (_agentSidebar == null) _agentSidebar = new AgentSidebar(_app);
                if (_sidebarInner.Child != _agentSidebar) _sidebarInner.Child = _agentSidebar;
            }
            ApplySidebarFrames();
            _header.Render();
            UIElement surface;
            if (_app.Surface == Surface.Agent || _app.Mode == EditorMode.AIAgent)
            {
                if (_agentView == null) _agentView = new AgentView(_app, false);
                surface = _agentView;
            }
            else if (_app.Mode == EditorMode.Code)
            {
                if (_editorArea == null) _editorArea = new EditorArea(_app);
                surface = _editorArea;
            }
            else
            {
                UIElement v;
                if (!_modeViews.TryGetValue(_app.Mode, out v)) { v = ModeViews.Create(_app.Mode, _app); _modeViews[_app.Mode] = v; }
                surface = v;
            }
            if (_surfaceHost.Child != surface)
            {
                var fe = surface as FrameworkElement;
                if (fe != null && fe.Parent is Decorator) ((Decorator)fe.Parent).Child = null;
                _surfaceHost.Child = surface;
            }
            RenderInspector();
        }

        void BuildWorkspace()
        {
            var t = Theme.Current;
            _workspace = new Grid { ClipToBounds = true };
            _workspace.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0) });
            _workspace.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            // sliding sidebar clip + constant-width inner host (no inner reflow during the slide)
            _sidebarClip = new Border { ClipToBounds = true, Background = t.SidebarBackground };
            _sidebarInner = new Border { HorizontalAlignment = HorizontalAlignment.Right, Width = _app.SidebarWidth };
            _sidebarClip.Child = _sidebarInner;
            Grid.SetColumn(_sidebarClip, 0);
            _workspace.Children.Add(_sidebarClip);

            // main: unified 36pt header + active surface (+ right inspector)
            var main = new Grid { Background = t.WorkspaceBackground };
            main.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = 320 });
            main.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var col = new Grid();
            col.RowDefinitions.Add(new RowDefinition { Height = new GridLength(36) });
            col.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            _header = new HeaderBar(this, _app);
            Grid.SetRow(_header, 0); col.Children.Add(_header);
            _surfaceHost = new Border();
            Grid.SetRow(_surfaceHost, 1); col.Children.Add(_surfaceHost);
            main.Children.Add(col);
            _inspectorHost = new Border();
            Grid.SetColumn(_inspectorHost, 1);
            main.Children.Add(_inspectorHost);
            _mainHost = new Border { Child = main };
            Grid.SetColumn(_mainHost, 1);
            _workspace.Children.Add(_mainHost);

            // NativePaneResizeSplitter (leading pane): 6pt hit area over the seam, grip pill, collapse below 95pt, double-click = 270
            _splitter = new Border { Width = 6, HorizontalAlignment = HorizontalAlignment.Left, Background = Brushes.Transparent, Cursor = Cursors.SizeWE };
            Grid.SetColumnSpan(_splitter, 2);
            var pill = new Border { Width = 3, Height = 28, CornerRadius = new CornerRadius(1.5), Background = t.P(0.28), Opacity = 0, VerticalAlignment = VerticalAlignment.Center };
            _splitter.Child = pill;
            double startX = 0, startW = 0;
            _splitter.MouseEnter += delegate { pill.Opacity = 1; };
            _splitter.MouseLeave += delegate { if (!_splitter.IsMouseCaptured) pill.Opacity = 0; };
            _splitter.MouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e)
            {
                if (e.ClickCount == 2) { _app.SetSidebarWidth(270); AnimateTo(270); e.Handled = true; return; }
                startX = e.GetPosition(this).X; startW = _app.SidebarWidth; _splitter.CaptureMouse(); e.Handled = true;
            };
            _splitter.MouseMove += delegate(object s, MouseEventArgs e)
            {
                if (!_splitter.IsMouseCaptured) return;
                double w = startW + (e.GetPosition(this).X - startX);
                if (w < 95) { _splitter.ReleaseMouseCapture(); pill.Opacity = 0; _app.SetSidebarVisible(false); return; }
                w = Math.Max(160, Math.Min(600, w));
                _app.SetSidebarWidth(w);
                _sidebarInner.Width = w;
                _revealed = w;
                ApplySidebarFrames();
            };
            _splitter.MouseLeftButtonUp += delegate { _splitter.ReleaseMouseCapture(); pill.Opacity = 0; };
            _workspace.Children.Add(_splitter);
        }

        void ApplySidebarFrames()
        {
            if (_workspace == null) return;
            bool show = !ModeHasOwnSidebar;
            double w = show ? Math.Max(0, _revealed) : 0;
            _workspace.ColumnDefinitions[0].Width = new GridLength(w);
            _sidebarInner.Width = _app.SidebarWidth;
            _splitter.Visibility = show && w > 1 && !_animating ? Visibility.Visible : Visibility.Collapsed;
            _splitter.Margin = new Thickness(Math.Max(0, w - 3), 0, 0, 0);
            if (_header != null) _header.SetRevealedSidebar(w, show);
        }

        // quartic ease-out slide (0.12s * fraction), like SidebarAnimationBus
        bool _animating;
        EventHandler _tick;
        void AnimateSidebar() { AnimateTo(_app.SidebarVisible ? _app.SidebarWidth : 0); }

        void AnimateTo(double target)
        {
            if (_workspace == null) { _revealed = target; return; }
            if (_tick != null) CompositionTarget.Rendering -= _tick;
            double from = _revealed;
            double dist = Math.Abs(target - from);
            if (dist < 0.5) { _revealed = target; ApplySidebarFrames(); return; }
            double dur = 0.12 * Math.Min(1.0, Math.Max(0.35, dist / Math.Max(_app.SidebarWidth, 1)));
            var start = DateTime.Now;
            _animating = true;
            _tick = delegate
            {
                double tt = Math.Min(1, (DateTime.Now - start).TotalSeconds / dur);
                double inv = 1 - tt;
                _revealed = from + (target - from) * (1 - inv * inv * inv * inv);
                if (tt >= 1) { _revealed = target; _animating = false; CompositionTarget.Rendering -= _tick; _tick = null; if (_header != null) _header.Render(); }
                ApplySidebarFrames();
            };
            CompositionTarget.Rendering += _tick;
        }

        ContextInspector _inspector;

        void RenderInspector()
        {
            if (_inspectorHost == null) return;
            // hidden rather than dropped: the WebApp preview and the emulator stream inside keep running
            if (!_app.AgenticContextVisible) { _inspectorHost.Visibility = Visibility.Collapsed; return; }
            _inspectorHost.Visibility = Visibility.Visible;
            // the inspector's Plan tab drives the same agent surface (approve / reject / run)
            if (_agentView == null) _agentView = new AgentView(_app, false);
            if (_inspector == null || _inspectorHost.Child != _inspector) { _inspector = new ContextInspector(_app, _agentView); _inspectorHost.Child = _inspector; }
            else _inspector.Rebuild();
        }

        /// <summary>The code editor of the current file, if the editor surface is showing one.</summary>
        public MicroCode.Editor.CodeEditorView ActiveEditor { get { return _editorArea != null ? _editorArea.ActiveEditor : null; } }

        public void GoToLine(int line)
        {
            Dispatcher.BeginInvoke(new Action(() => { if (_editorArea != null && _editorArea.ActiveEditor != null) _editorArea.ActiveEditor.GoToLine(line); }), DispatcherPriority.Loaded);
        }

        // MARK: - Keyboard shortcuts (⌘ → Ctrl, ⌥ → Alt, ⌃ → Alt for the mode switcher)
        void Bind(Key key, ModifierKeys mods, Action a)
        {
            var cmd = new RoutedCommand();
            CommandBindings.Add(new CommandBinding(cmd, delegate { a(); }));
            InputBindings.Add(new KeyBinding(cmd, key, mods));
        }

        void InstallShortcuts()
        {
            var C = ModifierKeys.Control; var CS = ModifierKeys.Control | ModifierKeys.Shift; var CA = ModifierKeys.Control | ModifierKeys.Alt; var A = ModifierKeys.Alt;
            Bind(Key.OemComma, C, () => SettingsWindow.Show(_app));
            Bind(Key.N, C, () => { if (_app.Mode == EditorMode.AIAgent) _app.Notify("agent:new"); else _app.NewFile(); });
            Bind(Key.N, CS, () => { _app.SwitchToMode(EditorMode.AIAgent); _app.Notify("agent:new"); });
            Bind(Key.O, C, _app.OpenFileDialog);
            Bind(Key.O, CS, _app.OpenFolderDialog);
            Bind(Key.W, C, () => { if (_app.CurrentFile != null) _app.CloseFile(_app.CurrentFile); });
            Bind(Key.W, CA, () => { var cur = _app.CurrentFile; foreach (var f in _app.OpenFiles.Where(x => x != cur).ToList()) _app.CloseFile(f); });
            Bind(Key.W, CS, _app.CloseWorkspace);
            Bind(Key.OemCloseBrackets, C, () => CycleTab(1));
            Bind(Key.OemOpenBrackets, C, () => CycleTab(-1));
            Bind(Key.Tab, C, () => CycleTab(1));
            Bind(Key.Tab, CS, () => CycleTab(-1));
            Bind(Key.S, C, _app.SaveCurrentFile);
            Bind(Key.S, CS, _app.SaveFileAs);
            Bind(Key.L, C, () => _app.ToggleAgenticContext());
            Bind(Key.B, C, _app.ToggleSidebar);
            Bind(Key.I, C, _app.ToggleAgenticContext);
            Bind(Key.J, C, _app.ToggleConsole);
            Bind(Key.R, C, _app.RunCode);
            Bind(Key.B, CS, _app.BuildProject);
            Bind(Key.OemPeriod, C, _app.StopExecution);
            Bind(Key.OemPlus, C, () => _app.SetFontSize(_app.FontSize + 1));
            Bind(Key.Add, C, () => _app.SetFontSize(_app.FontSize + 1));
            Bind(Key.OemMinus, C, () => _app.SetFontSize(_app.FontSize - 1));
            Bind(Key.Subtract, C, () => _app.SetFontSize(_app.FontSize - 1));
            Bind(Key.D0, C, () => _app.SetFontSize(16));
            Bind(Key.OemQuestion, C, () => ShortcutsWindow.Show());
            Bind(Key.F, CS, () => { _app.SwitchToMode(EditorMode.Code); _app.Notify("search:find"); });
            Bind(Key.T, CA, _app.ToggleConsole);
            var modes = new[] { EditorMode.Code, EditorMode.AIAgent, EditorMode.Notebook, EditorMode.Playground, EditorMode.Science, EditorMode.Browser, EditorMode.RemoteX, EditorMode.Embedded, EditorMode.ApiClient };
            var keys = new[] { Key.D1, Key.D2, Key.D3, Key.D4, Key.D5, Key.D6, Key.D7, Key.D8, Key.D9 };
            for (int i = 0; i < modes.Length; i++) { var m = modes[i]; Bind(keys[i], A, () => _app.SwitchToMode(m)); }
            Bind(Key.D0, A, () => { _app.ShowingWelcomeHome = !_app.ShowingWelcomeHome; _app.Notify("mode"); });
            Bind(Key.E, A, () => _app.SwitchToMode(EditorMode.Extensions));
            PreviewKeyUp += delegate(object s, KeyEventArgs e)
            {
                // Windows convention: a lone Alt press reveals the menu bar (the macOS window has no in-window menu).
                if ((e.Key == Key.System && (e.SystemKey == Key.LeftAlt || e.SystemKey == Key.RightAlt)) && _altClean) { _menuStrip.Toggle(); e.Handled = true; }
            };
            PreviewKeyDown += delegate(object s, KeyEventArgs e)
            {
                _altClean = e.Key == Key.System && (e.SystemKey == Key.LeftAlt || e.SystemKey == Key.RightAlt);
                if (e.Key == Key.Escape) { MacMenu.CloseAll(); _menuStrip.Hide(); }
            };
        }
        bool _altClean;

        void CycleTab(int d)
        {
            if (_app.OpenFiles.Count == 0) return;
            int i = (_app.CurrentFileIndex + d + _app.OpenFiles.Count) % _app.OpenFiles.Count;
            _app.SelectFile(_app.OpenFiles[i]);
        }

        // MARK: - macOS menu bar commands
        public List<Tuple<string, Func<List<MenuItemSpec>>>> Menus()
        {
            var a = _app;
            Func<string, string, string, Action, MenuItemSpec> I = (title, icon, sc, act) => new MenuItemSpec { Title = title, Icon = icon, Shortcut = sc, Action = act };
            var list = new List<Tuple<string, Func<List<MenuItemSpec>>>>();
            list.Add(Tuple.Create<string, Func<List<MenuItemSpec>>>("MicroCode", () => new List<MenuItemSpec> {
                I("About MicroCode", null, null, () => MessageBox.Show(this, "MicroCode for Windows\nVersion " + AppInfo.Version + "\n\n© Dotmini Company Limited. All rights reserved.", "About MicroCode")),
                MenuItemSpec.Sep(), I("Settings...", null, "Ctrl+,", () => SettingsWindow.Show(a)), MenuItemSpec.Sep(), I("Exit MicroCode", null, "Alt+F4", Close) }));
            list.Add(Tuple.Create<string, Func<List<MenuItemSpec>>>("File", () => new List<MenuItemSpec> {
                I("New File", null, "Ctrl+N", a.NewFile), I("New AI Conversation", null, "Ctrl+Shift+N", () => { a.SwitchToMode(EditorMode.AIAgent); a.Notify("agent:new"); }),
                I("Open File...", null, "Ctrl+O", a.OpenFileDialog), I("Open Folder...", null, "Ctrl+Shift+O", a.OpenFolderDialog), MenuItemSpec.Sep(),
                // .ARX capsules (ARXCapsuleService) are not ported yet: shown disabled instead of a menu item that does nothing
                new MenuItemSpec { Title = "Import .ARX Capsule… (not on Windows yet)", Disabled = true }, new MenuItemSpec { Title = "Export .ARX Capsule… (not on Windows yet)", Disabled = true }, MenuItemSpec.Sep(),
                I("Close Tab", null, "Ctrl+W", () => { if (a.CurrentFile != null) a.CloseFile(a.CurrentFile); }),
                I("Close Other Tabs", null, "Ctrl+Alt+W", () => { var cur = a.CurrentFile; foreach (var f in a.OpenFiles.Where(x => x != cur).ToList()) a.CloseFile(f); }),
                I("Close Workspace", null, "Ctrl+Shift+W", a.CloseWorkspace), MenuItemSpec.Sep(),
                I("Next Tab", null, "Ctrl+]", () => CycleTab(1)), I("Previous Tab", null, "Ctrl+[", () => CycleTab(-1)), MenuItemSpec.Sep(),
                I("Save", null, "Ctrl+S", a.SaveCurrentFile), I("Save As...", null, "Ctrl+Shift+S", a.SaveFileAs) }));
            list.Add(Tuple.Create<string, Func<List<MenuItemSpec>>>("Edit", () => new List<MenuItemSpec> {
                I("Undo", null, "Ctrl+Z", () => ApplicationCommands.Undo.Execute(null, Keyboard.FocusedElement)), I("Redo", null, "Ctrl+Y", () => ApplicationCommands.Redo.Execute(null, Keyboard.FocusedElement)), MenuItemSpec.Sep(),
                I("Cut", null, "Ctrl+X", () => ApplicationCommands.Cut.Execute(null, Keyboard.FocusedElement)), I("Copy", null, "Ctrl+C", () => ApplicationCommands.Copy.Execute(null, Keyboard.FocusedElement)),
                I("Paste", null, "Ctrl+V", () => ApplicationCommands.Paste.Execute(null, Keyboard.FocusedElement)), I("Select All", null, "Ctrl+A", () => ApplicationCommands.SelectAll.Execute(null, Keyboard.FocusedElement)) }));
            list.Add(Tuple.Create<string, Func<List<MenuItemSpec>>>("Modes", () => new List<MenuItemSpec> {
                I("Code Editor", null, "Alt+1", () => a.SwitchToMode(EditorMode.Code)), I("AI Agent Workspace", null, "Alt+2", () => a.SwitchToMode(EditorMode.AIAgent)),
                I("Cell Mode (Notebook)", null, "Alt+3", () => a.SwitchToMode(EditorMode.Notebook)), I("Playground Mode", null, "Alt+4", () => a.SwitchToMode(EditorMode.Playground)),
                I("Science Mode", null, "Alt+5", () => a.SwitchToMode(EditorMode.Science)), I("IDE Web Browser", null, "Alt+6", () => a.SwitchToMode(EditorMode.Browser)),
                I("Remote Explorer (SSH)", null, "Alt+7", () => a.SwitchToMode(EditorMode.RemoteX)), I("Embed & IoT Studio", null, "Alt+8", () => a.SwitchToMode(EditorMode.Embedded)),
                I("API Studio", null, "Alt+9", () => a.SwitchToMode(EditorMode.ApiClient)), I("Extension Studio", null, "Alt+E", () => a.SwitchToMode(EditorMode.Extensions)), MenuItemSpec.Sep(),
                I("Welcome Dashboard", null, "Alt+0", () => { a.ShowingWelcomeHome = true; a.Notify("mode"); }) }));
            list.Add(Tuple.Create<string, Func<List<MenuItemSpec>>>("Code", () => new List<MenuItemSpec> {
                I("Run Code", null, "Ctrl+R", a.RunCode), I("Build Project", null, "Ctrl+Shift+B", a.BuildProject), I("Stop Execution", null, "Ctrl+.", a.StopExecution), MenuItemSpec.Sep(),
                I("Find in Workspace...", null, "Ctrl+Shift+F", () => a.Notify("search:find")), I("Replace in Workspace...", null, "Ctrl+Shift+H", () => a.Notify("search:replace")), MenuItemSpec.Sep(),
                I("Refactor with AI", null, "Ctrl+Alt+R", () => a.Notify("agent:send:Refactor the current file for clarity and performance.")),
                I("Explain Code", null, "Ctrl+Alt+E", () => a.Notify("agent:send:Explain the current file.")) }));
            list.Add(Tuple.Create<string, Func<List<MenuItemSpec>>>("View", () => new List<MenuItemSpec> {
                I("Toggle Sidebar", null, "Ctrl+B", a.ToggleSidebar), I("Toggle Preview & Inspector", null, "Ctrl+I", a.ToggleAgenticContext),
                I("Toggle Terminal / Console", null, "Ctrl+J", a.ToggleConsole), MenuItemSpec.Sep(), I("Keyboard Shortcuts...", null, "Ctrl+/", ShortcutsWindow.Show), MenuItemSpec.Sep(),
                I("Increase Font Size", null, "Ctrl++", () => a.SetFontSize(a.FontSize + 1)), I("Decrease Font Size", null, "Ctrl+-", () => a.SetFontSize(a.FontSize - 1)),
                I("Reset Font Size", null, "Ctrl+0", () => a.SetFontSize(16)) }));
            list.Add(Tuple.Create<string, Func<List<MenuItemSpec>>>("Tools", () => new List<MenuItemSpec> { I("Terminal", null, "Ctrl+Alt+T", a.ToggleConsole) }));
            list.Add(Tuple.Create<string, Func<List<MenuItemSpec>>>("Git", () => new List<MenuItemSpec> {
                I("Refresh Status", null, "Ctrl+Alt+R", () => a.Notify("tree")), I("Commit Changes", null, null, () => GitActions.Commit(a)),
                I("Push", null, null, () => GitActions.Run(a, "push")), I("Pull", null, null, () => GitActions.Run(a, "pull")) }));
            list.Add(Tuple.Create<string, Func<List<MenuItemSpec>>>("Window", () => new List<MenuItemSpec> {
                I("Minimize", null, null, () => WindowState = WindowState.Minimized), I("Zoom", null, null, () => WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized) }));
            list.Add(Tuple.Create<string, Func<List<MenuItemSpec>>>("Help", () => new List<MenuItemSpec> {
                I("Keyboard Shortcuts...", null, "Ctrl+/", ShortcutsWindow.Show), MenuItemSpec.Sep(), I("Welcome to MicroCode", null, null, () => { a.ShowingWelcomeHome = true; a.Notify("mode"); }) }));
            return list;
        }
    }

    // MARK: - Unified 36pt Workspace Header Bar
    public class HeaderBar : Border
    {
        enum Bucket { Regular, Compact, Tight, UltraTight }
        readonly MainWindow _win;
        readonly AppState _app;
        Bucket _bucket = Bucket.Regular;
        double _revealed;
        bool _sidebarShown = true;

        public HeaderBar(MainWindow win, AppState app)
        {
            _win = win; _app = app;
            ClipToBounds = true;
            SizeChanged += delegate { var b = From(ActualWidth); if (b != _bucket) { _bucket = b; Render(); } };
        }

        static Bucket From(double w) { return w >= 1120 ? Bucket.Regular : w >= 760 ? Bucket.Compact : w >= 540 ? Bucket.Tight : Bucket.UltraTight; }

        public void SetRevealedSidebar(double w, bool shown)
        {
            double old = _revealed; _revealed = w; _sidebarShown = shown;
            if (Math.Abs(LeadingWidth(old) - LeadingWidth(w)) >= 0.5 && Child is Stack && ((Stack)Child).Children.Count > 0)
                ((FrameworkElement)((Stack)Child).Children[0]).Width = LeadingWidth(w);
        }

        double LeadingWidth(double revealed)
        {
            double collapsedLeading = _win.WindowState == WindowState.Maximized ? 12 : 78;
            bool own = !_sidebarShown;
            double d = own ? collapsedLeading : Math.Max(10, collapsedLeading - revealed);
            return Math.Round(d * 2) / 2;
        }

        public void Render()
        {
            var t = Theme.Current;
            Background = t.WorkspaceBackground;
            bool compact = _bucket != Bucket.Regular, tight = _bucket == Bucket.Tight || _bucket == Bucket.UltraTight, ultra = _bucket == Bucket.UltraTight;
            bool agentSurface = _app.Surface == Surface.Agent || _app.Mode == EditorMode.AIAgent;
            bool own = !_sidebarShown;
            var outer = V.H(0, new Border { Width = LeadingWidth(_revealed), Height = 1 });
            var row = V.H(tight ? 4 : (compact ? 5 : 8));

            if (!own)
            {
                var lead = V.H(compact ? 4 : 6, SidebarToggle());
                if (agentSurface && !_app.SidebarVisible)
                {
                    var plus = V.Button(V.Size(V.Box(Sym.Icon("plus", 11, t.P(0.85), FontWeights.SemiBold), V.P(0), t.P(0.06), 6), 26, 26), () => _app.Notify("agent:new"));
                    plus.ToolTip = "New Conversation (Ctrl+N)";
                    lead.Children.Add(plus);
                }
                row.Children.Add(lead);
                if (!(tight && _app.SidebarVisible)) row.Children.Add(V.Shrink(Breadcrumb(!tight, compact ? 180 : 240, agentSurface)));
            }
            row.Children.Add(V.Sp(4)); // WindowDragSpacerView

            if (agentSurface)
            {
                var g = V.H(compact ? 4 : 6, AgentModePills(tight), PreviewMenu(tight), ActionsMenu(compact));
                row.Children.Add(g);
            }
            else if (_app.Mode == EditorMode.Code)
            {
                var run = V.Button(V.Box(V.H(4, Sym.Icon("play.fill", 9, t.SysGreen, FontWeights.Bold), ultra ? null : V.T("Run", 11, FontWeights.SemiBold, t.SysGreen)), V.P(ultra ? 7 : 8, 4), t.Op(t.SysGreen, 0.12), 6), _app.RunCode);
                run.ToolTip = "Run Code (Ctrl+R)";
                if (_app.IsRunning)
                {
                    run = V.Button(V.Box(V.H(4, Sym.Icon("stop.fill", 9, t.SysRed, FontWeights.Bold), ultra ? null : V.T("Stop", 11, FontWeights.SemiBold, t.SysRed)), V.P(ultra ? 7 : 8, 4), t.Op(t.SysRed, 0.12), 6), _app.StopExecution);
                    run.ToolTip = "Stop Execution (Ctrl+.)";
                }
                var build = V.Button(V.Box(V.H(4, Sym.Icon("hammer.fill", 9, t.P(0.85), FontWeights.Medium), tight ? null : V.T("Build", 11, FontWeights.Medium, t.P(0.85))), V.P(tight ? 7 : 8, 4), t.P(0.06), 6), _app.BuildProject);
                build.ToolTip = "Build Project (Ctrl+Shift+B)";
                Brush cfg = _app.ConsoleVisible ? t.Accent : t.Secondary;
                var console = V.Button(V.Box(V.H(4, Sym.Icon("terminal", 9, cfg), tight ? null : V.T("Console", 11, FontWeights.Medium, cfg)), V.P(tight ? 7 : 8, 4), _app.ConsoleVisible ? t.A(0.12) : t.P(0.06), 6), _app.ToggleConsole);
                console.ToolTip = "Toggle Terminal / Console (Ctrl+J)";
                row.Children.Add(V.H(tight ? 4 : 5, run, build, PreviewMenu(tight), console));
            }

            // Surface toggle: Agent | Code Editor | More Mode
            bool moreActive = !agentSurface && _app.Mode != EditorMode.Code;
            var seg = V.H(2,
                Tab("brain", ultra ? null : "Agent", agentSurface, compact, () => _app.SwitchToMode(EditorMode.AIAgent), "Agent Mode"),
                Tab("curlybraces", ultra ? null : (compact ? "Editor" : "Code Editor"), !agentSurface && _app.Mode == EditorMode.Code, compact, () => _app.SwitchToMode(EditorMode.Code), "Code Editor Mode"),
                MoreModeTab(moreActive, compact, ultra));
            row.Children.Add(V.Box(seg, V.P(2), t.P(0.04), 6));

            // trailing: [...] layout menu, [◨] inspector, [⚙] settings
            var trailing = V.H(compact ? 4 : 6);
            var dots = V.Button(V.Size(new Grid { Children = { Sym.Icon("ellipsis", 12, t.Secondary, FontWeights.Medium) } }, 26, 26), null);
            dots.ToolTip = "Tools & Layout";
            dots.MenuAlignRight = true;
            dots.MenuItems = LayoutMenu;
            trailing.Children.Add(dots);
            bool rightOpen = _app.AgenticContextVisible || _app.ShowingPreviewView;
            var insp = V.Button(V.Size(V.Box(Sym.Icon("sidebar.right", 12, rightOpen ? t.Primary : t.Secondary), V.P(0), rightOpen ? t.P(0.11) : Brushes.Transparent, 5, rightOpen ? t.P(0.16) : Brushes.Transparent, 0.8), 28, 26), _app.ToggleAgenticContext);
            insp.ToolTip = "Toggle Preview & Context Inspector (Ctrl+I)";
            trailing.Children.Add(insp);
            if (!_app.SidebarVisible || own)
            {
                var gear = V.Button(V.Size(new Grid { Children = { Sym.Icon("gearshape", 12, t.Secondary) } }, 28, 26), () => SettingsWindow.Show(_app));
                gear.ToolTip = "Settings (Ctrl+,)";
                trailing.Children.Add(gear);
            }
            row.Children.Add(trailing);
            outer.Children.Add(V.Flex(V.Box(row, V.P(0, 0, 10, 0), null, 0)));
            Child = outer;
        }

        Btn SidebarToggle()
        {
            var t = Theme.Current;
            var icon = Sym.Icon("sidebar.left", 13, t.Primary, FontWeights.Medium);
            var box = V.Size(V.Box(icon, V.P(0), Brushes.Transparent, 6, Brushes.Transparent, 1), 28, 26);
            var b = V.Button(box, _app.ToggleSidebar);
            b.ToolTip = _app.SidebarVisible ? "Hide Sidebar (Ctrl+B)" : "Show Sidebar (Ctrl+B)";
            Action<Btn> st = x =>
            {
                bool vis = _app.SidebarVisible;
                icon.SetBrush(x.IsHover ? t.Primary : (vis ? t.P(0.8) : t.Secondary));
                box.Background = x.IsHover ? t.P(0.1) : (vis ? Brushes.Transparent : t.P(0.08));
                box.BorderBrush = x.IsHover ? t.P(0.18) : (vis ? Brushes.Transparent : t.P(0.12));
            };
            b.OnState = st; st(b);
            return b;
        }

        UIElement Breadcrumb(bool detail, double maxW, bool agent)
        {
            var t = Theme.Current;
            string project = _app.WorkspaceFolder != null ? System.IO.Path.GetFileName(_app.WorkspaceFolder.TrimEnd('\\')) : "MicroCode";
            var s = V.H(5, Sym.Icon("folder", 11, t.Secondary), V.Shrink(V.T(project, 12, FontWeights.SemiBold, t.Primary)));
            if (detail)
            {
                s.Children.Add(V.T("/", 11, FontWeights.Normal, t.S(0.6)));
                string d = agent ? AgentStore.ActiveTitle() : (_app.CurrentFile != null ? _app.CurrentFile.Name : (_app.Mode == EditorMode.Code ? "Editor" : EditorModeInfo.DisplayName(_app.Mode)));
                s.Children.Add(V.Shrink(V.T(d, 12, FontWeights.Medium, t.P(0.85))));
            }
            s.MaxWidth = maxW;
            return s;
        }

        UIElement Tab(string icon, string label, bool active, bool compact, Action act, string tip)
        {
            var t = Theme.Current;
            Brush fg = active ? t.Primary : t.Secondary;
            var b = V.Button(V.Box(V.H(4, Sym.Icon(icon, 10, fg), label == null ? null : V.T(label, 11, active ? FontWeights.SemiBold : FontWeights.Medium, fg)), V.P(compact ? 7 : 10, 4), active ? t.P(0.1) : Brushes.Transparent, 5), act);
            b.ToolTip = tip;
            return b;
        }

        UIElement MoreModeTab(bool active, bool compact, bool ultra)
        {
            var t = Theme.Current;
            Brush fg = active ? t.Primary : t.Secondary;
            var h = V.H(3, Sym.Icon("square.grid.2x2", 10, fg));
            if (!ultra && (active || !compact)) h.Children.Add(V.T(active ? EditorModeInfo.DisplayName(_app.Mode) : "More Mode", 11, active ? FontWeights.SemiBold : FontWeights.Medium, fg));
            h.Children.Add(Sym.Icon("chevron.down", 7, fg, FontWeights.Bold));
            var b = V.Button(V.Box(h, V.P(compact ? 7 : 10, 4), active ? t.P(0.1) : Brushes.Transparent, 5), null);
            b.ToolTip = "More Modes (Playground, Notebook, Science, SSH, Browser, IoT, API)";
            b.MenuItems = () => new List<MenuItemSpec>
            {
                MenuItemSpec.Item("Playground Mode", null, () => _app.SwitchToMode(EditorMode.Playground)),
                MenuItemSpec.Item("Cell Mode (Notebook)", null, () => _app.SwitchToMode(EditorMode.Notebook)),
                MenuItemSpec.Item("SSH Remote Browser", null, () => _app.SwitchToMode(EditorMode.RemoteX)),
                MenuItemSpec.Item("Science Mode", null, () => _app.SwitchToMode(EditorMode.Science)),
                MenuItemSpec.Item("IDE Web Browser", null, () => _app.SwitchToMode(EditorMode.Browser)),
                MenuItemSpec.Item("Embed & IoT Studio", null, () => _app.SwitchToMode(EditorMode.Embedded)),
                MenuItemSpec.Item("API Studio", null, () => _app.SwitchToMode(EditorMode.ApiClient)),
                MenuItemSpec.Item("Extension Studio", null, () => _app.SwitchToMode(EditorMode.Extensions))
            };
            return b;
        }

        /// <summary>DevicePreviewHeaderMenu: "Preview" shows or hides the Preview pane; the chevron opens the device menu.</summary>
        UIElement PreviewMenu(bool iconOnly)
        {
            var t = Theme.Current;
            bool showing = _app.AgenticContextVisible && PreviewDock.Tab == "preview";
            var active = PreviewDock.Active;
            string icon = active != null && active.Kind == "android" ? "candybarphone" : active != null && active.Kind == "ios" ? "iphone" : "rectangle.split.2x1";
            var h = V.H(4, Sym.Icon(icon, 10, showing ? t.Accent : t.Secondary));
            if (!iconOnly) h.Children.Add(V.T("Preview", 11, showing ? FontWeights.SemiBold : FontWeights.Medium, showing ? t.Primary : t.Secondary));
            var toggle = V.Button(V.Box(h, new Thickness(8, 4, 2, 4), Brushes.Transparent, 5), () =>
            {
                if (showing) { _app.AgenticContextVisible = false; _app.Notify("inspector"); }
                else PreviewDock.SelectTab("preview");
            });
            toggle.ToolTip = showing ? "Hide Simulator / Preview" : "Show Simulator / Preview";
            var chevron = V.Button(V.Box(Sym.Icon("chevron.down", 7, t.Secondary, FontWeights.SemiBold), new Thickness(2, 4, 6, 4), Brushes.Transparent, 5), null);
            chevron.ToolTip = "Live Multi-Platform Preview (Web, iOS Simulator, Android Emulator & USB Devices)";
            chevron.MenuItems = () =>
            {
                var items = new List<MenuItemSpec>
                {
                    MenuItemSpec.Header("Live Preview"),
                    MenuItemSpec.Item("WebApp Preview (Localhost)", "globe", () => PreviewDock.SelectStandard("web")),
                    MenuItemSpec.Item("WebApp in iPhone Frame", "iphone", () => { WebAppPreview.Shared.Open(null, "iphone"); PreviewDock.SelectStandard("web"); }),
                    MenuItemSpec.Item("WebApp in iPad Frame", "ipad", () => { WebAppPreview.Shared.Open(null, "ipad"); PreviewDock.SelectStandard("web"); }),
                    MenuItemSpec.Item("WebApp on MacBook", "laptopcomputer", () => { WebAppPreview.Shared.Open(null, "macbook"); PreviewDock.SelectStandard("web"); }),
                    MenuItemSpec.Sep(),
                    MenuItemSpec.Item("Android Emulator & USB Devices", "candybarphone", () => PreviewDock.SelectStandard("android")),
                    MenuItemSpec.Item("iOS Simulator", "iphone", () => PreviewDock.SelectStandard("ios")),
                    MenuItemSpec.Sep(),
                    MenuItemSpec.Item("Open File to Preview…", "doc.badge.plus", () =>
                    {
                        var dlg = new Microsoft.Win32.OpenFileDialog { Title = "Open File to Preview", InitialDirectory = _app.WorkspaceFolder ?? "" };
                        if (dlg.ShowDialog() == true) PreviewDock.OpenFile(dlg.FileName);
                    })
                };
                if (showing) { items.Add(MenuItemSpec.Sep()); items.Add(MenuItemSpec.Item("Close Preview", "xmark", () => { _app.AgenticContextVisible = false; _app.Notify("inspector"); })); }
                return items;
            };
            var pill = V.Box(V.H(0, toggle, chevron), V.P(0), showing ? t.A(0.12) : t.P(0.06), 5);
            return pill;
        }

        UIElement AgentModePills(bool veryCompact)
        {
            var t = Theme.Current;
            var bar = AgentStore.Bar;
            Func<string, string, bool, Action, bool, UIElement> pillDot = (label, icon, active, act, dot) =>
            {
                Brush fg = active ? t.Primary : t.Secondary;
                UIElement c = veryCompact ? (UIElement)Sym.Icon(icon, 10, fg) : V.T(label, 11, active ? FontWeights.SemiBold : FontWeights.Medium, fg);
                var row = V.H(4, c);
                if (dot) row.Children.Add(V.Dot(5, Theme.B(Color.FromRgb(255, 159, 10))));
                var b = V.Button(V.Box(row, V.P(veryCompact ? 6 : 8, 4), active ? t.P(0.10) : Brushes.Transparent, 5), act);
                b.ToolTip = label;
                return b;
            };
            Func<string, string, bool, Action, UIElement> pill = (label, icon, active, act) => pillDot(label, icon, active, act, false);
            bool plan = bar.PlanMode, task = bar.TaskMode && bar.TaskTab == 0, chat = bar.ChatActive;
            var more = V.H(3);
            more.Children.Add(veryCompact && !bar.SecondaryMode ? (UIElement)Sym.Icon("square.grid.2x2", 9.5, t.Secondary) : V.T(bar.SecondaryMode ? bar.SecondaryLabel : "More", 11, bar.SecondaryMode ? FontWeights.SemiBold : FontWeights.Medium, bar.SecondaryMode ? t.Primary : t.Secondary));
            more.Children.Add(Sym.Icon("chevron.down", 7, bar.SecondaryMode ? t.Primary : t.Secondary, FontWeights.Bold));
            var moreBtn = V.Button(V.Box(more, V.P(veryCompact ? 6 : 7, 4), bar.SecondaryMode ? t.P(0.10) : Brushes.Transparent, 5), null);
            moreBtn.ToolTip = "Walkthrough, Cells, Background Agents, Logs, Cost, Audit & Consensus";
            moreBtn.MenuItems = () => new List<MenuItemSpec>
            {
                MenuItemSpec.Item("Walkthrough Summary", "doc.text.magnifyingglass", () => { _app.SwitchToMode(EditorMode.AIAgent); AgentStore.SelectWalkthrough(); }),
                MenuItemSpec.Item("Interactive Notebook Cells", "square.grid.2x2", () => { _app.SwitchToMode(EditorMode.AIAgent); AgentStore.SelectCells(); }),
                MenuItemSpec.Sep(),
                MenuItemSpec.Item("Background Worktree Agents", "arrow.triangle.branch", () => { _app.SwitchToMode(EditorMode.AIAgent); AgentStore.SelectTaskTab(7); }),
                MenuItemSpec.Item("Token & Cost Usage", "chart.bar.xaxis", () => { _app.SwitchToMode(EditorMode.AIAgent); AgentStore.SelectTaskTab(4); }),
                MenuItemSpec.Item("Diagnostic Logs", "terminal", () => { _app.SwitchToMode(EditorMode.AIAgent); AgentStore.SelectTaskTab(3); }),
                MenuItemSpec.Item("Audit Log (Flight Recorder)", "shield.checkered", () => { _app.SwitchToMode(EditorMode.AIAgent); AgentStore.SelectTaskTab(5); }),
                MenuItemSpec.Item("Consensus Engine", "checkmark.shield", () => { _app.SwitchToMode(EditorMode.AIAgent); AgentStore.SelectTaskTab(6); })
            };
            var h = V.H(2,
                pill("Chat", "bubble.left.and.bubble.right", chat, () => AgentStore.SelectChat()),
                pillDot("Plan", "list.bullet.clipboard", plan, () => { _app.SwitchToMode(EditorMode.AIAgent); AgentStore.TogglePlan(); }, AgentStore.PlanPending),
                pill("Task", "checklist", task, () => { _app.SwitchToMode(EditorMode.AIAgent); AgentStore.SelectTask(); }),
                moreBtn);
            return V.Box(h, V.P(2), t.P(0.04), 6);
        }

        UIElement ActionsMenu(bool compact)
        {
            var t = Theme.Current;
            var h = V.H(3, Sym.Icon("slider.horizontal.3", 10, t.P(0.85)));
            if (!compact) { h.Children.Add(V.T("Actions", 11, FontWeights.Medium, t.P(0.85))); h.Children.Add(Sym.Icon("chevron.down", 7, t.P(0.85), FontWeights.SemiBold)); }
            var b = V.Button(V.Box(h, V.P(7, 4), t.P(0.06), 6), null);
            b.ToolTip = "Agent Actions (External Agents, Rules & MCP, Team, .ARX Capsule, Clear Chat)";
            b.MenuItems = () => new List<MenuItemSpec>
            {
                MenuItemSpec.Header("Agents, Rules & MCP"),
                MenuItemSpec.Item("Connect External Agents (1-Click)…", "link.badge.plus", () => SettingsWindow.Show(_app)),
                MenuItemSpec.Item("Rules, MCP & Context Settings…", "slider.horizontal.3", () => SettingsWindow.Show(_app)),
                MenuItemSpec.Item("Team Tasks…", "checklist", () => AgentStore.SelectTask()),
                MenuItemSpec.Item("Configure Team Collaboration…", "person.2", () => SettingsWindow.Show(_app)),
                MenuItemSpec.Sep(),
                // codebase index (RepoMapService) and .ARX capsules are not ported yet: disabled, not silent no-ops
                new MenuItemSpec { Title = "Index Project (not on Windows yet)", Icon = "database", Disabled = true },
                MenuItemSpec.Sep(),
                new MenuItemSpec { Title = "Export .ARX Capsule… (not on Windows yet)", Icon = "shippingbox.and.arrow.backward", Disabled = true },
                new MenuItemSpec { Title = "Import .ARX Capsule… (not on Windows yet)", Icon = "shippingbox", Disabled = true },
                MenuItemSpec.Sep(),
                MenuItemSpec.Item("Undo Last", "arrow.uturn.backward", () => _app.Notify("agent:undoLast")),
                new MenuItemSpec { Title = "Clear Chat", Icon = "trash", Destructive = true, Action = () => _app.Notify("agent:clear") }
            };
            return b;
        }

        List<MenuItemSpec> LayoutMenu()
        {
            return new List<MenuItemSpec>
            {
                MenuItemSpec.Header("Developer Tools"),
                MenuItemSpec.Item("Run Code (Ctrl+R)", "play.fill", _app.RunCode),
                MenuItemSpec.Item("Build Project (Ctrl+Shift+B)", "hammer.fill", _app.BuildProject),
                MenuItemSpec.Item(_app.ConsoleVisible ? "Hide Terminal / Console" : "Show Terminal / Console (Ctrl+J)", "terminal.fill", _app.ToggleConsole),
                MenuItemSpec.Header("Specialized Studios"),
                MenuItemSpec.Item("Database Studio", "server.rack", () => ModeViews.ShowStudio("Database Studio")),
                MenuItemSpec.Item("API Studio", "network", () => _app.SwitchToMode(EditorMode.ApiClient)),
                MenuItemSpec.Item("Container Studio", "shippingbox.fill", () => ModeViews.ShowStudio("Container Studio")),
                MenuItemSpec.Item("CI/CD Pipelines", "checklist", () => ModeViews.ShowStudio("CI/CD Pipelines")),
                MenuItemSpec.Item("Realtime Collaboration", "person.2.fill", () => CollabView.ShowWindow()),
                MenuItemSpec.Header("Window & Panels"),
                new MenuItemSpec { Title = "Auto-Hide Window Controls", Icon = "macwindow", Checked = _app.AutoHideTrafficLights, Action = () => { _app.AutoHideTrafficLights = !_app.AutoHideTrafficLights; Defaults.Set("autoHideWindowTrafficLights", _app.AutoHideTrafficLights); _app.Notify("lights"); } },
                MenuItemSpec.Item(_app.AgenticContextVisible ? "Hide Context Inspector" : "Show Context Inspector (Ctrl+I)", "sidebar.right", _app.ToggleAgenticContext),
                MenuItemSpec.Item("Connect with Phone (QR)…", "qrcode", () => SettingsWindow.Show(_app))
            };
        }
    }

    // MARK: - Window controls (macOS traffic lights, auto-hidden until the pointer reaches the top-left 82×36 sensor)
    public class TrafficLights : Canvas
    {
        readonly Window _win;
        readonly AppState _app;
        readonly Grid[] _btns = new Grid[3];
        bool _hoverGroup, _revealed, _welcome;
        readonly DispatcherTimer _dwell = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(120) };

        public TrafficLights(Window win, AppState app)
        {
            _win = win; _app = app;
            HorizontalAlignment = HorizontalAlignment.Left; VerticalAlignment = VerticalAlignment.Top;
            Width = 82; Height = 36;
            Background = Brushes.Transparent;
            WindowChrome.SetIsHitTestVisibleInChrome(this, true);
            var colors = new[] { Theme.Rgb(255, 95, 87), Theme.Rgb(254, 188, 46), Theme.Rgb(40, 200, 64) };
            var rims = new[] { Theme.Rgb(224, 68, 62), Theme.Rgb(222, 161, 35), Theme.Rgb(26, 171, 41) };
            var glyphs = new[] { "M3.5,3.5 L8.5,8.5 M8.5,3.5 L3.5,8.5", "M3,6 L9,6", "M3.6,3.6 L7.4,3.6 L3.6,7.4 Z M8.4,8.4 L4.6,8.4 L8.4,4.6 Z" };
            for (int i = 0; i < 3; i++)
            {
                int idx = i;
                var g = new Grid { Width = 12, Height = 12, Cursor = Cursors.Arrow };
                g.Children.Add(new Ellipse { Fill = Theme.B(colors[i]), Stroke = Theme.B(Theme.WithAlpha(rims[i], 0.9)), StrokeThickness = 0.5 });
                var glyph = new System.Windows.Shapes.Path { Data = Geometry.Parse(glyphs[i]), Stroke = Theme.B(Theme.Rgba(0, 0, 0, 0.55)), StrokeThickness = 1.1, Fill = i == 2 ? Theme.B(Theme.Rgba(0, 0, 0, 0.55)) : null, Opacity = 0, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round };
                g.Children.Add(glyph);
                SetLeft(g, 8 + i * 20); SetTop(g, 12);
                g.MouseLeftButtonUp += delegate
                {
                    if (idx == 0) _win.Close();
                    else if (idx == 1) _win.WindowState = WindowState.Minimized;
                    else _win.WindowState = _win.WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
                };
                g.MouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e) { e.Handled = true; };
                _btns[i] = g;
                Children.Add(g);
            }
            MouseEnter += delegate { _hoverGroup = true; ShowGlyphs(true); _dwell.Stop(); _dwell.Start(); };
            MouseLeave += delegate { _hoverGroup = false; ShowGlyphs(false); _dwell.Stop(); Update(); };
            _dwell.Tick += delegate { _dwell.Stop(); if (_hoverGroup) { _revealed = true; Update(); } };
            _win.Activated += delegate { Update(); };
            _win.Deactivated += delegate { Update(); };
            app.Changed += w => { if (w == "lights") Update(); };
            Update();
        }

        public void SetLeadingContextWelcome(bool welcome) { _welcome = welcome; Update(); }

        void ShowGlyphs(bool on) { foreach (var b in _btns) b.Children[1].Opacity = on ? 1 : 0; }

        void Update()
        {
            if (!_hoverGroup) _revealed = false;
            bool visible = !_app.AutoHideTrafficLights || _revealed;
            double target = visible ? 1 : 0;
            foreach (var b in _btns)
            {
                b.BeginAnimation(OpacityProperty, new DoubleAnimation(target, TimeSpan.FromMilliseconds(140)));
                var e = (Ellipse)b.Children[0];
                if (!_win.IsActive && visible && !_hoverGroup) { e.Fill = Theme.B(Theme.Rgba(128, 128, 128, 0.45)); e.Stroke = null; }
            }
            if (_win.IsActive || _hoverGroup)
            {
                var colors = new[] { Theme.Rgb(255, 95, 87), Theme.Rgb(254, 188, 46), Theme.Rgb(40, 200, 64) };
                for (int i = 0; i < 3; i++) ((Ellipse)_btns[i].Children[0]).Fill = Theme.B(colors[i]);
            }
        }
    }

    // MARK: - Menu bar (revealed with Alt, Windows convention for apps without an in-window menu)
    public class MenuStrip : Border
    {
        readonly MainWindow _win;
        public MenuStrip(MainWindow win, AppState app)
        {
            _win = win;
            VerticalAlignment = VerticalAlignment.Top;
            Visibility = Visibility.Collapsed;
            Height = 28;
        }

        public void Toggle() { if (Visibility == Visibility.Visible) Hide(); else Show(); }
        public void Hide() { Visibility = Visibility.Collapsed; }

        public void Show()
        {
            var t = Theme.Current;
            var row = V.H(2, new Border { Width = 8 });
            foreach (var m in _win.Menus())
            {
                var menu = m;
                var b = V.Button(V.Box(V.T(menu.Item1, 13, menu.Item1 == "MicroCode" ? FontWeights.Bold : FontWeights.Normal, t.Primary), V.P(9, 3), Brushes.Transparent, 5), null);
                b.MenuItems = () => { var items = menu.Item2(); return items; };
                b.OnState = x => ((Border)x.Child).Background = x.IsHover ? t.P(0.12) : Brushes.Transparent;
                row.Children.Add(b);
            }
            row.Children.Add(V.Sp());
            row.Children.Add(V.Box(V.T("Esc", 11, FontWeights.Normal, t.Secondary), V.P(10, 0), null, 0));
            Child = row;
            Background = t.ElevatedBackground;
            BorderBrush = t.Separator;
            BorderThickness = new Thickness(0, 0, 0, 1);
            Visibility = Visibility.Visible;
        }
    }
}
