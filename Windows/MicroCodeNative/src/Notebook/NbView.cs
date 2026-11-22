// Port of NotebookView.swift (Cell Mode): resizable Cell Sheets sidebar (GroupBoxes: sheets, kernel, data files, shared data,
// actions), the 28pt bezel-free executive toolbar, the live kernel variable bar, the cell list, the sequential execution queue
// with the reactive DAG, and the Notebook Agent panel on the right.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using MicroCode.Core;
using MicroCode.Editor;
using MicroCode.UI;

namespace MicroCode.Views
{
    /// <summary>SwiftUI .popover look-alike: a rounded panel anchored under a control that closes on outside click.</summary>
    public static class NbPop
    {
        public static Popup Show(FrameworkElement anchor, UIElement content, double width)
        {
            var t = Theme.Current;
            var panel = new Border
            {
                Child = content, Background = t.MenuBackground, BorderBrush = t.MenuBorder, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(10),
                Margin = new Thickness(14, 8, 14, 20), Effect = new DropShadowEffect { BlurRadius = 22, ShadowDepth = 6, Direction = 270, Opacity = 0.45, Color = Colors.Black }
            };
            if (!double.IsNaN(width)) panel.Width = width;
            var pop = new Popup { Child = panel, AllowsTransparency = true, StaysOpen = false, PlacementTarget = anchor, Placement = PlacementMode.Bottom, HorizontalOffset = -14, VerticalOffset = -4, PopupAnimation = PopupAnimation.Fade };
            pop.IsOpen = true;
            return pop;
        }

        /// <summary>Recolours every TextBlock and symbol inside a control (hover foreground changes).</summary>
        public static void Tint(DependencyObject root, Brush b)
        {
            if (root == null) return;
            var tb = root as TextBlock; if (tb != null) { tb.Foreground = b; return; }
            var sym = root as SymbolIcon; if (sym != null) { sym.SetBrush(b); return; }
            var dec = root as Decorator; if (dec != null) { Tint(dec.Child, b); return; }
            var pan = root as Panel; if (pan != null) foreach (UIElement c in pan.Children) Tint(c, b);
        }
    }

    public partial class NotebookView : Grid
    {
        public static bool AutoRunAll, ForceShowAI, ForceVars, ForceAppMode;
        /// <summary>Snapshot hook: once every queued cell has finished, scroll this 1-based cell to the top.</summary>
        public static int ScrollToCell = -1;
        public static NotebookView Current;
        public static void ShutdownKernel() { NbPythonKernel.ShutdownAll(); }

        internal readonly AppState App;
        readonly Border _sidebarHost = new Border(), _toolbarHost = new Border(), _varBarHost = new Border(), _aiHost = new Border(), _sideHandle, _aiHandle;
        internal readonly ScrollViewer Scroll;
        readonly StackPanel _list = new StackPanel();
        readonly Grid _center = new Grid();
        bool _showSidebar = Defaults.Bool("notebook.showSidebar", true), _showAI;
        double _sidebarW = Defaults.Num("notebook.sidebarWidth", 232), _aiW = Defaults.Num("notebook.aiPanelWidth", 356);
        internal string SelectedId;
        internal bool Reactive, ShowVars, AppMode;
        bool _editingName;
        internal int TotalExec, Epoch;
        readonly List<string> _queue = new List<string>();
        bool _draining;
        string _kernelStatus = "Idle";
        internal NotebookAIPanel Ai;
        internal readonly Dictionary<string, CodeEditorView> Editors = new Dictionary<string, CodeEditorView>();
        readonly Dictionary<string, CellCard> _cards = new Dictionary<string, CellCard>();
        DateTime? _lastAutoSave;
        DispatcherTimer _resizeTimer;
        double _lastToolbarWidth = -1;

        internal NbDoc Doc { get { return NbStore.Active; } }
        internal NbPythonKernel Kernel { get { return NbPythonKernel.For(Doc.Id); } }
        internal bool AnyExecuting { get { return Doc.Cells.Any(c => c.IsExecuting); } }
        internal NbCell Selected { get { return Doc.Cells.FirstOrDefault(c => c.Id == SelectedId); } }
        internal bool IsDark { get { return Theme.Current.IsDark; } }

        public NotebookView(AppState app)
        {
            App = app;
            Current = this;
            NbStore.Load();
            _showAI = ForceShowAI || Defaults.Bool("notebook.showAIPanel", false);
            ShowVars = ForceVars; AppMode = ForceAppMode;
            var t = Theme.Current;
            Background = t.WorkspaceBackground;
            foreach (var w in new[] { GridLength.Auto, GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto, GridLength.Auto })
                ColumnDefinitions.Add(new ColumnDefinition { Width = w });
            Children.Add(_sidebarHost);
            _sideHandle = ResizeHandle(true); SetColumn(_sideHandle, 1); Children.Add(_sideHandle);

            _center.RowDefinitions.Add(new RowDefinition { Height = new GridLength(28) });
            _center.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1) });
            _center.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            _center.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            _center.Children.Add(_toolbarHost);
            var div = V.Line(t.Separator, true); SetRow(div, 1); _center.Children.Add(div);
            SetRow(_varBarHost, 2); _center.Children.Add(_varBarHost);
            Scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, Background = t.WorkspaceBackground, Focusable = false };
            _list.Margin = new Thickness(0, 16, 0, 16);
            Scroll.Content = _list;
            SetRow(Scroll, 3); _center.Children.Add(Scroll);
            _center.ClipToBounds = true;
            SetColumn(_center, 2); Children.Add(_center);
            _aiHandle = ResizeHandle(false); SetColumn(_aiHandle, 3); Children.Add(_aiHandle);
            SetColumn(_aiHost, 4); Children.Add(_aiHost);

            var doc = Doc;
            SelectedId = doc.Cells.Count > 0 ? doc.Cells[0].Id : null;
            TotalExec = doc.Cells.Count == 0 ? 0 : doc.Cells.Max(c => c.ExecCount);
            Epoch = doc.Cells.Count == 0 ? 0 : doc.Cells.Max(c => c.LastRunEpoch);
            var k = Kernel;
            k.Changed += OnKernelChanged;
            if (k.Status == "Not Started") k.Start();

            RenderAll();
            SizeChanged += delegate { ApplyWidths(); };
            _center.SizeChanged += (s, e) =>
            {
                foreach (var c in _cards.Values) c.Width = CardWidth;
                if (ToolbarBucket(e.NewSize.Width) != ToolbarBucket(_lastToolbarWidth)) RenderToolbar();
                // headers, rich outputs and editors are sized from the column width (compact chips under 560pt): rebuild once the
                // width settles — this also replaces the first pass that ran before layout knew the real width
                if (Math.Abs(e.NewSize.Width - e.PreviousSize.Width) > 0.5)
                {
                    if (_resizeTimer == null)
                    {
                        _resizeTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(140) };
                        _resizeTimer.Tick += delegate { _resizeTimer.Stop(); RenderCells(); };
                    }
                    _resizeTimer.Stop(); _resizeTimer.Start();
                }
            };
            PreviewKeyDown += OnKey;
            Unloaded += delegate { Kernel.Changed -= OnKernelChanged; };
            Loaded += delegate { if (!Kernel.Busy) { Kernel.Changed -= OnKernelChanged; Kernel.Changed += OnKernelChanged; } };
            if (AutoRunAll) Loaded += delegate { Dispatcher.BeginInvoke(new Action(RunAll), DispatcherPriority.ApplicationIdle); };
        }

        static int ToolbarBucket(double w) { return w < 0 ? -1 : w < 680 ? 0 : w < 820 ? 1 : 2; }

        void OnKernelChanged()
        {
            RenderSidebar();
            if (ShowVars) RenderVarBar();
            RenderToolbar();
        }

        internal void RenderAll() { RenderSidebar(); RenderToolbar(); RenderVarBar(); RenderCells(); RenderAI(); ApplyWidths(); }

        // ── widths (GeometryReader math from NotebookView.body) ─────────────────
        double CenterWidth { get { return _center.ActualWidth > 0 ? _center.ActualWidth : Math.Max(320, ActualWidth - (_showSidebar ? _sidebarW + 6 : 0) - (_showAI ? _aiW + 6 : 0)); } }
        internal double CardWidth { get { return Math.Max(280, Math.Floor(CenterWidth - 32)); } }

        void ApplyWidths()
        {
            double total = Math.Max(640, ActualWidth > 0 ? ActualWidth : 1200);
            double maxSide = Math.Min(320, Math.Max(180, total * 0.25));
            double side = _showSidebar ? Math.Min(Math.Max(180, _sidebarW), maxSide) : 0;
            double maxAI = Math.Min(560, Math.Max(280, total - side - (_showSidebar ? 6 : 0) - 430));
            double ai = _showAI ? Math.Min(Math.Max(280, _aiW), maxAI) : 0;
            _sidebarHost.Width = side; _sidebarHost.Visibility = _showSidebar ? Visibility.Visible : Visibility.Collapsed;
            _sideHandle.Visibility = _showSidebar ? Visibility.Visible : Visibility.Collapsed;
            _aiHost.Width = ai; _aiHost.Visibility = _showAI ? Visibility.Visible : Visibility.Collapsed;
            _aiHandle.Visibility = _showAI ? Visibility.Visible : Visibility.Collapsed;
        }

        /// <summary>NotebookVerticalResizeHandle: 6pt hit area, 1pt separator that brightens on hover/drag.</summary>
        Border ResizeHandle(bool leading)
        {
            var t = Theme.Current;
            var line = new Border { Width = 1, Background = t.Separator, HorizontalAlignment = HorizontalAlignment.Center };
            var h = new Border { Width = 6, Background = Brushes.Transparent, Cursor = Cursors.SizeWE, Child = line };
            double sx = 0, sw = 0;
            h.MouseEnter += delegate { line.Background = t.P(0.28); };
            h.MouseLeave += delegate { if (!h.IsMouseCaptured) line.Background = t.Separator; };
            h.MouseLeftButtonDown += (s, e) => { sx = e.GetPosition(this).X; sw = leading ? _sidebarHost.ActualWidth : _aiHost.ActualWidth; h.CaptureMouse(); e.Handled = true; };
            h.MouseMove += (s, e) =>
            {
                if (!h.IsMouseCaptured) return;
                double dx = e.GetPosition(this).X - sx;
                if (leading) _sidebarW = Math.Max(180, Math.Min(320, sw + dx)); else _aiW = Math.Max(280, Math.Min(560, sw - dx));
                ApplyWidths();
            };
            h.MouseLeftButtonUp += delegate
            {
                h.ReleaseMouseCapture(); line.Background = t.Separator;
                Defaults.Set(leading ? "notebook.sidebarWidth" : "notebook.aiPanelWidth", leading ? _sidebarW : _aiW);
            };
            return h;
        }

        // ── shared chrome helpers ────────────────────────────────────────────
        internal static Btn HoverIcon(string icon, double size, double w, double h, double radius, string tip, Action click)
        {
            var t = Theme.Current;
            var ic = Sym.Icon(icon, size, t.Secondary, FontWeights.Medium);
            var b = V.Button(ic, click);
            b.Width = w; b.Height = h; b.CornerRadius = new CornerRadius(radius);
            b.OnState = x => { x.Background = x.IsHover ? t.P(t.IsDark ? 0.09 : 0.06) : Brushes.Transparent; ic.SetBrush(x.IsHover ? t.Primary : t.Secondary); };
            b.Refresh();
            if (tip != null) b.ToolTip = tip;
            return b;
        }

        Border Group(UIElement content)
        {
            var t = Theme.Current;
            return new Border { Child = content, Padding = new Thickness(9), CornerRadius = new CornerRadius(6), Background = t.P(t.IsDark ? 0.05 : 0.04), BorderBrush = t.P(0.06), BorderThickness = new Thickness(1) };
        }

        // ── notebookSidebar ──────────────────────────────────────────────────
        void RenderSidebar()
        {
            var t = Theme.Current;
            var plus = HoverIcon("plus", 10.5, 22, 20, 4.5, "New Cell Sheet", CreateNotebook);
            var header = new Border { Height = 28, Padding = new Thickness(10, 0, 10, 0), Background = t.PanelBackground, Child = V.H(6, Sym.Icon("doc.text.fill", 11, t.SysOrange), V.T("Cell Sheets", 11.5, FontWeights.SemiBold, t.P(0.92)), V.Sp(), plus) };

            var body = V.VLead(12); body.Align = Cross.Stretch;

            // notebook list
            var list = V.VLead(4); list.Align = Cross.Stretch;
            foreach (var d in NbStore.Docs)
            {
                var doc = d;
                bool active = d.Id == NbStore.ActiveId;
                var del = V.Button(Sym.Icon("xmark.circle", 10.5, t.Secondary), () => DeleteNotebook(doc));
                del.Opacity = 0; del.IsHitTestVisible = false;
                var row = V.Button(V.Box(V.H(8, Sym.Icon("doc.text", 12, active ? t.SysOrange : t.Secondary),
                    V.Flex(V.VLead(2, V.T(d.Name, 12, active ? FontWeights.SemiBold : FontWeights.Normal, t.Primary), V.T(d.Cells.Count + " cells", 10, FontWeights.Normal, t.Secondary))), del),
                    V.P(8, 6), active ? t.A(0.15) : Brushes.Transparent, 6), () => SelectNotebook(doc));
                row.PressedOpacity = 1;
                row.OnState = b => { del.Opacity = b.IsHover ? 1 : 0; del.IsHitTestVisible = b.IsHover; };
                list.Children.Add(row);
            }
            body.Children.Add(Group(list));

            // kernel status
            var k = Kernel;
            string status = k.Status == "Python not found" || k.Status == "Dead" || k.Status.StartsWith("Starting") ? k.Status : _kernelStatus;
            var envLabel = PythonEnvs.SelectedName == "Python" ? "System Python" + (k.Version.Length > 0 ? " " + k.Version : "") : PythonEnvs.SelectedName;
            var env = V.Button(V.Box(V.H(6, Sym.Icon("cpu.fill", 10, t.SysGreen), V.Flex(V.T(envLabel, 10, FontWeights.Normal, t.Primary)), Sym.Icon("chevron.down", 8, t.Secondary)), V.P(6), t.ElevatedBackground, 4), null);
            env.MenuItems = () => PythonMenu(true);
            var kernel = V.VLead(8,
                V.Self(V.H(6, V.Dot(8, _kernelStatus == "Running" ? t.SysGreen : t.SysGray), V.T("Python 3", 12, FontWeights.Medium, t.Primary), V.Sp(), V.T(status, 10, FontWeights.Normal, t.Secondary)), Cross.Stretch),
                V.Self(V.VLead(2, V.Self(V.H(4, V.T("LOCAL / WINDOWS", 9, FontWeights.Bold, t.Secondary), V.Sp(), V.Box(V.T("Default", 8, FontWeights.Medium, t.Accent), V.P(4, 1), t.A(0.15), 3)), Cross.Stretch), V.Self(env, Cross.Stretch)), Cross.Stretch));
            kernel.Align = Cross.Stretch;
            body.Children.Add(Group(kernel));

            // data files
            var add = V.Button(Sym.Icon("plus.circle", 11, t.Secondary), null);
            add.MenuItems = () => new List<MenuItemSpec> { MenuItemSpec.Item("Import Files…", null, ImportDataFiles), MenuItemSpec.Item("New CSV File", null, CreateDataFile) };
            var dataHead = V.H(6, V.T("Data Files", 10, FontWeights.SemiBold, t.Secondary), V.Sp());
            if (App.WorkspaceFolder != null) dataHead.Children.Add(V.Tip(V.Button(Sym.Icon("arrow.triangle.2.circlepath", 11, t.Secondary), SyncWorkspaceFiles), "Sync scientific artifacts from project"));
            dataHead.Children.Add(add);
            var data = V.VLead(8, V.Self(dataHead, Cross.Stretch)); data.Align = Cross.Stretch;
            var files = Doc.Files;
            if (files.Count == 0)
                data.Children.Add(V.Self(V.Box(V.Vs(4, Sym.Icon("doc.badge.plus", 16, t.Secondary), V.T("No data files", 10, FontWeights.Normal, t.Secondary)), V.P(0, 12), null, 0), Cross.Center));
            foreach (var f in files.Take(5)) data.Children.Add(DataFileRow(f));
            if (files.Count > 5)
            {
                var more = V.Button(V.Box(V.H(6, Sym.Icon("folder.fill", 11, t.Secondary), V.T("More Files (+" + (files.Count - 5) + ")...", 11, FontWeights.Medium, t.Secondary), V.Sp(), Sym.Icon("chevron.up.chevron.down", 9, t.Secondary)), V.P(8, 5), t.ElevatedBackground, 5), null);
                more.ToolTip = "Access remaining data files in this notebook";
                more.MenuItems = () => files.Skip(5).Select(f => { var file = f; return MenuItemSpec.Sub(f.Name + " (" + NbFmt.Bytes(f.Size) + ")", f.Icon, DataFileMenu(file)); }).ToList();
                more.Margin = new Thickness(0, 2, 0, 0);
                data.Children.Add(more);
            }
            body.Children.Add(Group(data));

            // shared data (SharedMemoryService is not part of the Windows port, so nothing is ever shared)
            var shared = V.VLead(8, V.Self(V.H(6, V.T("Shared Data", 10, FontWeights.SemiBold, t.Secondary), V.Sp(), V.Tip(V.Button(Sym.Icon("arrow.clockwise", 11, t.Secondary), RenderSidebar), "Refresh")), Cross.Stretch),
                V.Self(V.Box(V.T("No shared data", 10, FontWeights.Normal, t.Secondary), V.P(0, 8), null, 0), Cross.Center));
            shared.Align = Cross.Stretch;
            body.Children.Add(Group(shared));

            // actions
            Func<string, string, Brush, Action, Btn> act = (icon, label, fg, a) =>
            {
                var b = V.Button(V.Box(V.H(7, Sym.Icon(icon, 12, fg), V.T(label, 13, FontWeights.Normal, fg), V.Sp()), V.P(2, 3), Brushes.Transparent, 4), a);
                return b;
            };
            var run = act("play.fill", "Run…", t.Primary, RunAll);
            ((Stack)((Border)run.Child).Child).Children.Add(V.Tip(V.Button(Sym.Icon("chevron.up.chevron.down", 9, t.Secondary), null), "Run by Color / Tag"));
            var runChevron = (Btn)((Stack)((Border)run.Child).Child).Children[3];
            runChevron.MenuItems = () => RunMenu(false);
            var actions = V.VLead(8, run, act("trash", "Clear Outputs", t.Primary, ClearAllOutputs), act("arrow.clockwise", "Restart Kernel", t.SysOrange, RestartKernel));
            actions.Align = Cross.Stretch;
            body.Children.Add(Group(actions));

            var g = new Grid { Background = t.PanelBackground };
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(28) });
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1) });
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            g.Children.Add(header);
            var d1 = V.Line(t.Separator, true); SetRow(d1, 1); g.Children.Add(d1);
            var sv = new ScrollViewer { Content = V.Box(body, V.P(16), null, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Focusable = false };
            SetRow(sv, 2); g.Children.Add(sv);
            _sidebarHost.Child = g;
        }

        UIElement DataFileRow(NbDataFile f)
        {
            var t = Theme.Current;
            var file = f;
            var insert = V.Tip(V.Button(Sym.Icon("arrow.down.to.line", 10.5, t.Secondary), () => InsertLoaderCell(file)), "Insert loader cell");
            insert.Opacity = 0; insert.IsHitTestVisible = false;
            var badge = V.Box(V.T(f.Type, 9, FontWeights.Medium, f.Brush), V.P(4, 2), NbColor.Alpha(f.Brush, 0.2), 3);
            var row = V.Button(V.Box(V.H(8, V.Size(Sym.Icon(f.Icon, 12, f.Brush), 16, double.NaN), V.Flex(V.VLead(1, V.T(f.Name, 11, FontWeights.Normal, t.Primary), V.T(NbFmt.Bytes(f.Size), 10, FontWeights.Normal, t.Secondary))), badge, insert), V.P(0, 4), Brushes.Transparent, 0), () => InsertLoaderCell(file));
            row.PressedOpacity = 1;
            row.OnState = b => { insert.Opacity = b.IsHover ? 1 : 0; insert.IsHitTestVisible = b.IsHover; };
            row.MouseRightButtonUp += (s, e) => { MacMenu.ShowAtMouse(DataFileMenu(file)); e.Handled = true; };
            return row;
        }

        List<MenuItemSpec> DataFileMenu(NbDataFile f)
        {
            return new List<MenuItemSpec>
            {
                MenuItemSpec.Item("Insert Loader Cell", "arrow.down.to.line", () => InsertLoaderCell(f)),
                MenuItemSpec.Item("Open Preview", "eye", () => PreviewDock.OpenFile(f.Path)),
                MenuItemSpec.Sep(),
                MenuItemSpec.Item("Copy Path", "doc.on.doc", () => { try { Clipboard.SetText(f.Path); } catch (Exception ex) { Debug.WriteLine("clipboard: " + ex.Message); } }),
                MenuItemSpec.Item("Rename…", "pencil", () => RenameDataFile(f)),
                MenuItemSpec.Sep(),
                MenuItemSpec.Item("Remove Reference", "xmark", () => { Doc.Files.Remove(f); SaveSoon(); RenderSidebar(); }),
                new MenuItemSpec { Title = "Move File to Recycle Bin", Icon = "trash", Destructive = true, Action = () => DeleteDataFile(f) }
            };
        }

        // ── notebookToolbar (28pt) ───────────────────────────────────────────
        static Brush PillFill(bool active, bool hover) { var t = Theme.Current; bool d = t.IsDark; return active ? t.P(d ? 0.115 : 0.08) : hover ? t.P(d ? 0.085 : 0.058) : t.P(d ? 0.045 : 0.03); }
        static Brush PillStroke(bool active, bool hover) { var t = Theme.Current; bool d = t.IsDark; return active ? t.P(d ? 0.22 : 0.16) : hover ? t.P(d ? 0.16 : 0.12) : t.P(d ? 0.10 : 0.07); }

        /// <summary>A 21pt toolbar pill (toolbarPillFill / toolbarPillStroke) with optional active colours and hover foreground.</summary>
        internal static Btn Pill(UIElement content, double padH, Func<bool> active, Brush activeFill, Brush activeStroke, Brush fg, Brush hoverFg, Action click, string tip)
        {
            var b = V.Button(content, click);
            b.Height = 21; b.CornerRadius = new CornerRadius(5); b.BorderThickness = new Thickness(0.8); b.Padding = new Thickness(padH, 0, padH, 0);
            b.VerticalAlignment = VerticalAlignment.Center;
            b.OnState = x =>
            {
                bool a = active != null && active();
                x.Background = a && activeFill != null ? activeFill : PillFill(a, x.IsHover);
                x.BorderBrush = a && activeStroke != null ? activeStroke : PillStroke(a, x.IsHover);
                if (fg != null) NbPop.Tint(x.Child, x.IsHover && hoverFg != null && !a ? hoverFg : fg);
            };
            b.Refresh();
            if (tip != null) b.ToolTip = tip;
            return b;
        }

        Btn ToolbarIcon(string icon, string tip, Brush tint, bool active, Action click)
        {
            var t = Theme.Current; bool d = t.IsDark;
            var ic = Sym.Icon(icon, 11, tint ?? (active ? t.Primary : t.Secondary), FontWeights.Medium);
            var b = V.Button(ic, click);
            b.Width = 22; b.Height = 21; b.CornerRadius = new CornerRadius(5); b.BorderThickness = new Thickness(0.8);
            b.OnState = x =>
            {
                x.Background = active ? t.P(d ? 0.11 : 0.08) : x.IsHover ? t.P(d ? 0.085 : 0.055) : Brushes.Transparent;
                x.BorderBrush = active ? t.P(d ? 0.20 : 0.14) : Brushes.Transparent;
                ic.SetBrush(tint ?? (active || x.IsHover ? t.Primary : t.Secondary));
            };
            b.Refresh();
            b.ToolTip = tip;
            return b;
        }

        static UIElement Divider13() { var l = V.Size(V.Line(Theme.Current.Separator, false), 1, 13); l.Opacity = 0.65; return l; }

        internal void RenderToolbar()
        {
            var t = Theme.Current; bool d = t.IsDark;
            double width = CenterWidth;
            _lastToolbarWidth = _center.ActualWidth > 0 ? _center.ActualWidth : width;
            bool compact = width < 820, ultra = width < 680;
            double maxTitle = width > 840 ? 200 : width > 680 ? 128 : 84;
            var bar = V.H(compact ? 4 : 5.5);

            bar.Children.Add(ToolbarIcon("sidebar.left", "Toggle Cell Sheets Sidebar", _showSidebar ? t.P(0.88) : null, false, () =>
            {
                _showSidebar = !_showSidebar; Defaults.Set("notebook.showSidebar", _showSidebar);
                if (_showSidebar) RenderSidebar();
                ApplyWidths(); RenderToolbar();
            }));
            bar.Children.Add(Divider13());

            // notebook name (double-click or pencil to rename)
            if (_editingName)
            {
                var box = Styles.PlainField("Name", 11.5, t.Primary);
                box.FontWeight = FontWeights.SemiBold; box.Text = Doc.Name;
                var holder = V.Box(box, V.P(5, 0), t.P(d ? 0.08 : 0.05), 4); holder.Height = 20; holder.MaxWidth = maxTitle; holder.MinWidth = 80;
                Action commit = () => { if (!_editingName) return; _editingName = false; string n = box.Text.Trim(); if (n.Length > 0) Doc.Name = n; SaveSoon(); RenderToolbar(); RenderSidebar(); };
                box.KeyDown += (s, e) => { if (e.Key == Key.Enter) { commit(); e.Handled = true; } else if (e.Key == Key.Escape) { _editingName = false; RenderToolbar(); e.Handled = true; } };
                box.LostKeyboardFocus += delegate { commit(); };
                bar.Children.Add(holder);
                Dispatcher.BeginInvoke(new Action(() => { box.Focus(); box.SelectAll(); }), DispatcherPriority.Input);
            }
            else
            {
                var name = V.T(Doc.Name, 11.5, FontWeights.SemiBold, t.P(0.93));
                name.MinWidth = ultra ? 46 : 68; name.MaxWidth = maxTitle;
                name.MouseLeftButtonDown += (s, e) => { if (e.ClickCount == 2) { _editingName = true; RenderToolbar(); e.Handled = true; } };
                var pencil = Sym.Icon("pencil", 9, t.S(0.75), FontWeights.Medium);
                var rename = V.Button(pencil, () => { _editingName = true; RenderToolbar(); });
                rename.Width = 17; rename.Height = 19; rename.CornerRadius = new CornerRadius(4);
                rename.OnState = x => { x.Background = x.IsHover ? t.P(d ? 0.08 : 0.05) : Brushes.Transparent; pencil.SetBrush(x.IsHover ? t.Primary : t.S(0.75)); };
                rename.ToolTip = "Rename Cell Sheet";
                bar.Children.Add(V.H(3, name, rename));
            }
            bar.Children.Add(Divider13());

            // Python version pill
            var pyLabel = V.T(PythonEnvs.SelectedName == "Python" && Kernel.Version.Length > 0 ? "Python " + Kernel.Version : PythonEnvs.SelectedName, 10.5, FontWeights.Medium, t.P(0.9));
            var py = Pill(V.H(4.5, Sym.Icon("chevron.left.forwardslash.chevron.right", 9.5, t.SysGreen, FontWeights.SemiBold), V.Shrink(pyLabel), Sym.Icon("chevron.down", 7.5, t.S(0.8), FontWeights.SemiBold)), 7, null, null, null, null, null, null, "Select Python Interpreter or Virtual Environment (" + pyLabel.Text + ")");
            py.MaxWidth = ultra ? 92 : compact ? 120 : 158;
            py.MenuItems = () => PythonMenu(false);
            bar.Children.Add(py);

            // [ + | ▶ | ▶▶ ▾ ] capsule
            bar.Children.Add(ExecutionCapsule());

            // Reactive DAG pill
            var dagRow = V.H(3.5, Sym.Icon(Reactive ? "bolt.fill" : "bolt", 9.5, Reactive ? t.SysOrange : t.Secondary, FontWeights.SemiBold));
            if (!compact) dagRow.Children.Add(V.T("DAG", 10, Reactive ? FontWeights.SemiBold : FontWeights.Medium, Reactive ? t.SysOrange : t.Secondary));
            bar.Children.Add(Pill(dagRow, compact ? 5.5 : 6.5, () => Reactive, NbColor.Alpha(t.SysOrange, d ? 0.16 : 0.11), NbColor.Alpha(t.SysOrange, 0.45), Reactive ? t.SysOrange : t.Secondary, Reactive ? null : t.Primary,
                () => { Reactive = !Reactive; RenderToolbar(); }, "Reactive DAG Mode: Automatically re-run downstream dependent cells when an upstream variable changes"));

            bar.Children.Add(V.Sp(4));

            // compute engine pill
            string target = ComputeTargets.Current;
            var compRow = V.H(4, Sym.Icon(ComputeTargets.Icon(target), 10, t.Secondary, FontWeights.Medium), Sym.Icon("chevron.down", 7.5, t.S(0.8), FontWeights.SemiBold));
            var comp = Pill(compRow, 6.5, null, null, null, null, null, null, "Select Compute Engine: " + ComputeTargets.Display(target));
            comp.MenuItems = ComputeMenu;
            bar.Children.Add(comp);

            // live variables pill
            int varCount = Kernel.Variables.Count;
            var green = t.SysGreen;
            var varsRow = V.H(3.5, Sym.Icon("memorychip", 10, ShowVars || varCount > 0 ? green : t.Secondary, FontWeights.Medium));
            if (varCount > 0) varsRow.Children.Add(V.Mono(varCount.ToString(), 9.5, FontWeights.SemiBold, green));
            else if (!compact) varsRow.Children.Add(V.T("Vars", 10, FontWeights.Medium, ShowVars ? green : t.Secondary));
            bar.Children.Add(Pill(varsRow, 6, () => ShowVars, NbColor.Alpha(green, d ? 0.15 : 0.11), NbColor.Alpha(green, 0.42), ShowVars ? green : varCount > 0 ? NbColor.Alpha(green, 0.9) : t.Secondary, ShowVars || varCount > 0 ? null : t.Primary,
                () => { ShowVars = !ShowVars; RenderVarBar(); RenderToolbar(); }, "Toggle Live Kernel Variable & Memory Inspector"));

            // App / dashboard presentation pill
            var appRow = V.H(3.5, Sym.Icon(AppMode ? "sparkles.tv.fill" : "sparkles.tv", 10, AppMode ? t.Accent : t.Secondary, FontWeights.Medium));
            if (!compact) appRow.Children.Add(V.T("App", 10, AppMode ? FontWeights.SemiBold : FontWeights.Medium, AppMode ? t.Accent : t.Secondary));
            bar.Children.Add(Pill(appRow, compact ? 5.5 : 6, () => AppMode, null, null, AppMode ? t.Accent : t.Secondary, AppMode ? null : t.Primary,
                () => { AppMode = !AppMode; RenderToolbar(); RenderCells(); }, "Toggle Executive App / Dashboard Presentation Mode (hides raw code, shows Markdown, @param widgets, DataGrids & plots)"));

            bar.Children.Add(ToolbarIcon("folder", "Open Notebook (.mic / .ipynb)", null, false, OpenNotebookFile));
            Btn export = null;
            export = ToolbarIcon("square.and.arrow.down", "Export Notebook (.mic / .ipynb)", null, false, () => ShowExportPopover(export));
            bar.Children.Add(export);
            bar.Children.Add(Divider13());

            if (!ultra)
            {
                var count = V.Box(V.Mono(TotalExec.ToString(), 10, FontWeights.Medium, t.Secondary), V.P(5.5, 0), t.P(d ? 0.05 : 0.035), 4.5, t.P(d ? 0.09 : 0.06), 0.7);
                count.Height = 21; count.ToolTip = "Total Executions: " + TotalExec;
                ((TextBlock)count.Child).VerticalAlignment = VerticalAlignment.Center;
                bar.Children.Add(count);
            }
            if (!_showAI && !compact) bar.Children.Add(NbAgentUI.ModelPill(App, Math.Min(165, width * 0.24), true, true, null));

            var agentRow = V.H(4, Sym.Icon("sidebar.right", 10.5, _showAI ? t.Primary : t.Secondary, FontWeights.Medium));
            if (!ultra) agentRow.Children.Add(V.T("Agent", 10.5, _showAI ? FontWeights.SemiBold : FontWeights.Medium, _showAI ? t.Primary : t.Secondary));
            bar.Children.Add(Pill(agentRow, ultra ? 6 : 7.5, () => _showAI, null, null, _showAI ? t.Primary : t.Secondary, t.Primary, ToggleAgentPanel, "Toggle Notebook Agent Panel"));

            _toolbarHost.Child = new Border { Child = bar, Padding = new Thickness(10, 0, 10, 0), Background = t.PanelBackground, ClipToBounds = true };
        }

        UIElement ExecutionCapsule()
        {
            var t = Theme.Current; bool d = t.IsDark;
            bool canRun = Selected != null && Selected.IsRunnable;
            Func<string, double, Brush, Brush, double, Action, string, Btn> seg = (icon, size, fg, hoverBg, w, a, tip) =>
            {
                var ic = Sym.Icon(icon, size, fg, FontWeights.SemiBold);
                var b = V.Button(ic, a); b.Width = w; b.Height = 21;
                b.OnState = x => x.Background = x.IsHover && hoverBg != null ? hoverBg : Brushes.Transparent;
                b.ToolTip = tip;
                return b;
            };
            Func<UIElement> sep = () => V.Size(new Border { Background = t.P(d ? 0.11 : 0.08) }, 0.8, 13);
            var add = seg("plus", 10.5, t.P(0.82), t.P(d ? 0.10 : 0.07), 24, null, "Add Cell");
            add.MenuItems = AddCellMenu;
            var runSel = seg("play.fill", 9.5, canRun ? NbColor.Alpha(t.SysGreen, 0.88) : t.S(0.32), canRun ? NbColor.Alpha(t.SysGreen, d ? 0.14 : 0.10) : null, 24, () => { var c = Selected; if (c != null) RunCell(c); }, "Run Selected Cell");
            runSel.IsEnabled = canRun;
            var runAll = seg("forward.fill", 9.5, t.P(0.85), NbColor.Alpha(t.SysGreen, d ? 0.14 : 0.10), 25, RunAll, "Run All Cells");
            var opts = seg("chevron.down", 7.5, t.S(0.8), t.P(d ? 0.10 : 0.07), 15, null, "Run by Color / Tag & Kernel Actions");
            opts.MenuItems = () => RunMenu(true);
            var cap = V.Box(V.H(0, add, sep(), runSel, sep(), runAll, opts), V.P(0), t.P(d ? 0.048 : 0.032), 5.5, t.P(d ? 0.12 : 0.085), 0.8);
            cap.Height = 21; cap.ClipToBounds = true; cap.VerticalAlignment = VerticalAlignment.Center;
            return cap;
        }

        List<MenuItemSpec> AddCellMenu()
        {
            Func<string, string, Action, MenuItemSpec> i = (title, icon, a) => MenuItemSpec.Item(title, icon, a);
            return new List<MenuItemSpec>
            {
                MenuItemSpec.Header("Code Cells"),
                i("Python", "p.circle.fill", () => AddCell("Code", "Python")), i("R", "r.circle.fill", () => AddCell("Code", "R")),
                i("Julia", "j.circle.fill", () => AddCell("Code", "Julia")), i("SQL", "cylinder.fill", () => AddCell("Code", "SQL")),
                MenuItemSpec.Sep(), MenuItemSpec.Header("Compiled"),
                i("Ardium", "sparkles", () => AddCell("Code", "Ardium")), i("Rust", "gearshape.fill", () => AddCell("Code", "Rust")),
                i("Go", "g.circle.fill", () => AddCell("Code", "Go")), i("C++", "c.circle.fill", () => AddCell("Code", "C++")),
                i("Objective-C", "apple.logo", () => AddCell("Code", "Objective-C")),
                MenuItemSpec.Sep(), MenuItemSpec.Header("Documents"),
                i("Markdown", "text.alignleft", () => AddCell("Markdown", null)), i("R Markdown", "doc.richtext.fill", () => AddCell("Code", "R Markdown")),
                i("LaTeX", "function", () => AddCell("Code", "LaTeX")), i("Raw Text", "doc.plaintext", () => AddCell("Raw", null)),
                MenuItemSpec.Sep(), MenuItemSpec.Header("Autonomous & Analytics"),
                i("AI Agent Cell", "brain.head.profile", () => AddCell("Agent", null))
            };
        }

        List<string> UsedColors() { return Doc.Cells.Where(c => c.Type == "Code" || c.Type == "Procedure").Select(c => c.ColorTheme ?? "None").Distinct().Where(c => c != "None").OrderBy(c => c, StringComparer.Ordinal).ToList(); }
        List<string> UsedTags() { return Doc.Cells.Where(c => c.IsRunnable).Select(c => (c.Tag ?? "").Trim()).Where(x => x.Length > 0).Distinct().OrderBy(x => x, StringComparer.Ordinal).ToList(); }

        /// <summary>presentRunOptionsMenu (toolbar chevron) and the sidebar "Run…" menu.</summary>
        List<MenuItemSpec> RunMenu(bool toolbar)
        {
            var items = new List<MenuItemSpec> { MenuItemSpec.Item("Run All Cells", "forward.fill", RunAll) };
            var sel = Selected;
            if (toolbar && sel != null)
            {
                items.Add(MenuItemSpec.Item("Run Selected Cell", "play.fill", () => RunCell(sel)));
                items.Add(MenuItemSpec.Item("Run Selected + Downstream Cells (DAG)", "arrow.turn.right.down", () => RunDownstream(sel)));
            }
            if (toolbar) items.Add(new MenuItemSpec { Title = "Reactive DAG Auto-Run Mode", Icon = "bolt.fill", Checked = Reactive, Action = () => { Reactive = !Reactive; RenderToolbar(); } });
            var colors = UsedColors();
            if (colors.Count > 0) items.Add(MenuItemSpec.Sub("Run by Color", "paintpalette", colors.Select(c => { var col = c; return MenuItemSpec.Item(col, "circle.fill", () => RunByColor(col)); }).ToList()));
            var tags = UsedTags();
            if (tags.Count > 0) items.Add(MenuItemSpec.Sub("Run by Tag", "tag", tags.Select(x => { var tag = x; return MenuItemSpec.Item(tag, "tag.fill", () => RunByTag(tag)); }).ToList()));
            if (toolbar)
            {
                items.Add(MenuItemSpec.Sep());
                items.Add(MenuItemSpec.Item("Clear All Outputs", "trash", ClearAllOutputs));
                items.Add(MenuItemSpec.Item("Restart Kernel", "arrow.clockwise", RestartKernel));
            }
            return items;
        }

        /// <summary>presentPythonVersionMenu: interpreters, virtual environments, refresh.</summary>
        List<MenuItemSpec> PythonMenu(bool sidebar)
        {
            var envs = PythonEnvs.All(false);
            string sel = PythonEnvs.Selected;
            var items = new List<MenuItemSpec> { MenuItemSpec.Header("Python Interpreter") };
            items.Add(new MenuItemSpec { Title = "python (System Default)", Icon = "terminal", Checked = sel == null, Action = () => SwitchPython(null) });
            foreach (var e in envs.Where(x => x.Kind != "venv")) { var env = e; items.Add(new MenuItemSpec { Title = e.Name + "  —  " + e.Path, Icon = "cpu", Checked = string.Equals(sel, e.Path, StringComparison.OrdinalIgnoreCase), Action = () => SwitchPython(env.Path) }); }
            var venvs = envs.Where(x => x.Kind == "venv").ToList();
            if (venvs.Count > 0)
            {
                items.Add(MenuItemSpec.Sep()); items.Add(MenuItemSpec.Header("Virtual Environments"));
                foreach (var e in venvs) { var env = e; items.Add(new MenuItemSpec { Title = "venv: " + e.Name, Icon = "shippingbox.fill", Checked = string.Equals(sel, e.Path, StringComparison.OrdinalIgnoreCase), Action = () => SwitchPython(env.Path) }); }
            }
            items.Add(MenuItemSpec.Sep());
            items.Add(MenuItemSpec.Item("Rescan Python Environments", "arrow.clockwise", () => { PythonEnvs.All(true); RenderToolbar(); RenderSidebar(); }));
            return items;
        }

        void SwitchPython(string path)
        {
            PythonEnvs.Selected = path;
            Kernel.Restart();
            RenderToolbar(); RenderSidebar();
        }

        List<MenuItemSpec> ComputeMenu()
        {
            var items = new List<MenuItemSpec> { MenuItemSpec.Header("Compute Engine") };
            string cur = ComputeTargets.Current;
            foreach (var target in ComputeTargets.UserSelectable)
            {
                var tg = target;
                string why = ComputeTargets.Unavailable(tg);
                string title = ComputeTargets.Display(tg) + (ComputeTargets.IsPremium(tg) ? "  \u2605" : "") + (why != null ? "  (" + why + ")" : "");
                items.Add(new MenuItemSpec { Title = title, Icon = ComputeTargets.Icon(tg), Checked = cur == tg, Disabled = why != null, Action = () => { ComputeTargets.Current = tg; RenderToolbar(); RenderCells(); } });
            }
            return items;
        }

        void ShowExportPopover(Btn anchor)
        {
            var t = Theme.Current; bool d = t.IsDark;
            Popup pop = null;
            var close = V.Button(Sym.Icon("xmark.circle.fill", 13, t.Secondary), () => { if (pop != null) pop.IsOpen = false; });
            close.ToolTip = "Close";
            var body = V.VLead(8, V.Self(V.H(6, V.Flex(V.VLead(2, V.T("Export Notebook", 12.5, FontWeights.SemiBold, t.Primary), V.T("Save .mic, Jupyter .ipynb, or clean Python script", 10.5, FontWeights.Normal, t.Secondary))), close), Cross.Stretch),
                V.Self(V.Line(t.Separator, true), Cross.Stretch));
            body.Align = Cross.Stretch;
            Action<string, string, string, Action> row = (title, hint, icon, a) =>
            {
                var ic = Sym.Icon(icon, 11, t.Secondary, FontWeights.Medium);
                var h = V.H(8, V.Size(ic, 16, double.NaN), V.T(title, 11.5, FontWeights.Medium, t.Primary), V.Sp());
                if (hint != null) h.Children.Add(V.Mono(hint, 10, FontWeights.Normal, t.Secondary));
                var b = V.Button(V.Box(h, V.P(8, 5.5), Brushes.Transparent, 5), () => { if (pop != null) pop.IsOpen = false; a(); });
                b.OnState = x => { ((Border)x.Child).Background = x.IsHover ? t.P(d ? 0.09 : 0.06) : Brushes.Transparent; ic.SetBrush(x.IsHover ? t.Accent : t.Secondary); };
                body.Children.Add(b);
            };
            row("Quick Save (.mic)", "Ctrl+S", "bolt.fill", QuickSave);
            row("Save As\u2026 (.mic)", "Ctrl+Shift+S", "square.and.arrow.down", SaveAs);
            row("Export as Jupyter (.ipynb)", null, "arrow.up.forward.square", ExportIpynb);
            row("Export as Git-Clean Script (.py # %%)", null, "doc.text.fill", ExportPy);
            row("Open in Google Colab", null, "sparkles.rectangle.stack", OpenInColab);
            body.Children.Add(V.Self(V.Line(t.Separator, true), Cross.Stretch));
            body.Children.Add(V.T(_lastAutoSave.HasValue ? "Autosaved " + _lastAutoSave.Value.ToString("HH:mm:ss") : "Autosave active", 10, FontWeights.Normal, t.Secondary));
            pop = NbPop.Show(anchor, V.Box(body, V.P(12), null, 0), 288);
        }

        // ── live variable inspector bar (NotebookVariableInspectorBar) ───────
        void RenderVarBar()
        {
            if (!ShowVars) { _varBarHost.Child = null; return; }
            var t = Theme.Current; bool d = t.IsDark;
            var k = Kernel;
            var vars = k.Variables;
            var head = V.H(8, Sym.Icon("memorychip", 10.5, t.SysGreen, FontWeights.SemiBold), V.T("Live Kernel Memory", 11, FontWeights.SemiBold, t.Primary), V.T("\u00B7 " + vars.Count + " vars", 10.5, FontWeights.Normal, t.Secondary));
            if (k.RssBytes > 0) head.Children.Add(V.Box(V.Mono("RAM " + NbFmt.Bytes(k.RssBytes), 9.5, FontWeights.Medium, t.Secondary), V.P(5.5, 1.5), t.P(0.06), 4));
            if (k.GpuBytes > 0) head.Children.Add(V.Box(V.Mono("CUDA GPU " + NbFmt.Bytes(k.GpuBytes), 9.5, FontWeights.SemiBold, t.SysPurple), V.P(5.5, 1.5), NbColor.Alpha(t.SysPurple, 0.12), 4));
            head.Children.Add(V.Sp());
            var close = V.Button(Sym.Icon("xmark", 10, t.Secondary, FontWeights.Medium), () => { ShowVars = false; RenderVarBar(); RenderToolbar(); });
            close.Width = 20; close.Height = 18;
            head.Children.Add(close);
            var col = V.VLead(0, V.Self(V.Size(V.Box(head, V.P(12, 0), null, 0), double.NaN, 26), Cross.Stretch));
            col.Align = Cross.Stretch;
            var sepLine = V.Line(t.Separator, true); sepLine.Opacity = 0.55;
            col.Children.Add(sepLine);
            if (vars.Count == 0)
                col.Children.Add(V.Box(V.Wrap(V.T("Run a Python cell to inspect live variables, DataFrames, tensors, and process / GPU memory.", 11, FontWeights.Normal, t.Secondary), TextAlignment.Left), V.P(12, 10), null, 0));
            else
            {
                var cards = V.H(8);
                foreach (var v in vars) cards.Children.Add(VariableCard(v));
                col.Children.Add(new ScrollViewer { Content = V.Box(cards, V.P(12, 7), null, 0), HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, Focusable = false });
            }
            _varBarHost.Child = new Border { Child = col, Background = t.P(d ? 0.035 : 0.022), BorderBrush = t.Separator, BorderThickness = new Thickness(0, 0, 0, 1) };
        }

        UIElement VariableCard(KernelVar v)
        {
            var t = Theme.Current; bool d = t.IsDark;
            var top = V.H(5, V.Mono(v.Name, 11, FontWeights.SemiBold, t.Primary), V.Box(V.T(v.TypeName, 9, FontWeights.Medium, t.Accent), V.P(4.5, 1), t.A(0.14), 3.5), V.Sp(4), V.Mono(v.FormattedMemory, 9, FontWeights.Normal, t.Secondary));
            var mid = V.H(6);
            if (v.Shape.Length > 0) mid.Children.Add(V.Mono(v.Shape, 9.5, FontWeights.Normal, t.Secondary));
            if (v.NumericSample.Count >= 3) mid.Children.Add(Sparkline(v.NumericSample, 64, 15));
            else { var p = V.Mono(v.Preview.Replace("\n", " "), 9.5, FontWeights.Normal, t.S(0.8)); p.MaxWidth = 130; mid.Children.Add(p); }
            var var2 = v;
            Func<string, string, Action, UIElement> mini = (icon, label, a) => V.Button(V.Box(V.H(2.5, Sym.Icon(icon, 8.5, t.Secondary), V.T(label, 9, FontWeights.Medium, t.Secondary)), V.P(5, 2), t.P(0.055), 3.5), a);
            var btns = V.H(4, mini("eye", "Inspect", () => InspectVariable(var2)), mini("at", "Agent", () => SendVariableToAgent(var2)));
            var card = V.Box(V.VLead(4, V.Self(top, Cross.Stretch), mid, btns), V.P(8.5, 6), t.P(d ? 0.05 : 0.035), 6.5, t.P(d ? 0.11 : 0.08), 0.75);
            card.MinWidth = 175; card.MaxWidth = 220;
            return card;
        }

        internal static FrameworkElement Sparkline(List<double> values, double w, double h)
        {
            var c = new Canvas { Width = w, Height = h };
            if (values.Count < 2) return c;
            double lo = values.Min(), hi = values.Max(), span = Math.Max(1e-9, hi - lo);
            var pts = new PointCollection();
            for (int i = 0; i < values.Count; i++) pts.Add(new Point(i / (double)(values.Count - 1) * w, h - (values[i] - lo) / span * (h - 2) - 1));
            c.Children.Add(new System.Windows.Shapes.Polyline { Points = pts, Stroke = NbColor.Alpha(Theme.Current.SysGreen, 0.85), StrokeThickness = 1.3, StrokeLineJoin = PenLineJoin.Round });
            return c;
        }

        void InspectVariable(KernelVar v)
        {
            var c = AddCell("Code", "Python");
            c.Content = v.Name; RefreshEditor(c);
            RunCell(c);
        }

        void SendVariableToAgent(KernelVar v)
        {
            if (!_showAI) ToggleAgentPanel();
            Dispatcher.BeginInvoke(new Action(() => { if (Ai != null) Ai.InsertMention("@" + v.Name); }), DispatcherPriority.Background);
        }

        // ── cells list ───────────────────────────────────────────────────────
        internal void RenderCells()
        {
            var t = Theme.Current;
            var doc = Doc;
            if (SelectedId != null && !doc.Cells.Any(c => c.Id == SelectedId)) SelectedId = doc.Cells.Count > 0 ? doc.Cells[0].Id : null;
            var dag = CellDag.Analyze(doc.Cells);
            double off = Scroll.VerticalOffset;
            _list.Children.Clear();
            var keep = new HashSet<string>();
            foreach (var c in doc.Cells)
            {
                CellCard card;
                if (!_cards.TryGetValue(c.Id, out card)) _cards[c.Id] = card = new CellCard(this, c);
                CellDagInfo info; dag.TryGetValue(c.Id, out info);
                card.Dag = info;
                card.Rebuild();
                card.Width = CardWidth;
                card.HorizontalAlignment = HorizontalAlignment.Center;
                if (card.Visibility == Visibility.Visible) card.Margin = new Thickness(0, 0, 0, 12);
                _list.Children.Add(card);
                keep.Add(c.Id);
            }
            foreach (var id in _cards.Keys.Where(x => !keep.Contains(x)).ToList()) { _cards.Remove(id); Editors.Remove(id); }
            if (!AppMode)
            {
                Func<UIElement, string, Brush, Action, Btn> add = (icon, label, stroke, a) =>
                {
                    var b = V.Button(V.Box(V.H(6, icon, V.T(label, 13, FontWeights.Normal, t.Primary)), V.P(16, 8), t.ElevatedBackground, 8, stroke, stroke == null ? 0 : 1), a);
                    return b;
                };
                var row = V.H(16,
                    add(Sym.Icon("chevron.left.forwardslash.chevron.right", 12, t.Primary), "Code", null, () => AddCell("Code", null)),
                    add(Sym.Icon("text.alignleft", 12, t.Primary), "Text", null, () => AddCell("Markdown", null)),
                    add(Sym.Icon("brain.head.profile", 12, t.Accent), "AI Agent", t.A(0.28), () => AddCell("Agent", null)));
                row.HorizontalAlignment = HorizontalAlignment.Center;
                row.Margin = new Thickness(0, 20, 0, 20);
                _list.Children.Add(row);
            }
            Scroll.ScrollToVerticalOffset(off);
        }

        internal CellCard CardFor(NbCell c) { CellCard card; return c != null && _cards.TryGetValue(c.Id, out card) ? card : null; }
        internal void RefreshCell(NbCell c) { var card = CardFor(c); if (card != null) card.Rebuild(); }

        DateTime _lastStreamRender;
        internal void RefreshCellLive(NbCell c)
        {
            if ((DateTime.Now - _lastStreamRender).TotalMilliseconds < 60) return;
            _lastStreamRender = DateTime.Now;
            var card = CardFor(c); if (card != null) card.RefreshOutputs();
        }

        internal void Select(NbCell c)
        {
            if (c == null || SelectedId == c.Id) return;
            var prev = Selected;
            SelectedId = c.Id;
            var pc = CardFor(prev); if (pc != null) pc.UpdateChrome();
            var cc = CardFor(c); if (cc != null) cc.UpdateChrome();
            RenderToolbar();
            if (Ai != null) Ai.RefreshScope();
        }

        internal void RefreshEditor(NbCell c)
        {
            CodeEditorView ed;
            if (Editors.TryGetValue(c.Id, out ed)) Editors.Remove(c.Id);
            RefreshCell(c);
        }

        // ── cell operations (NotebookViewModel) ─────────────────────────────
        internal NbCell AddCell(string type, string lang)
        {
            var doc = Doc;
            string content = type == "Code" ? null : type == "Agent" ? "" : "# Heading\n\nText here...";
            var c = NbCell.Create(type, lang ?? "Python", content);
            var sel = Selected;
            int i = sel != null ? doc.Cells.IndexOf(sel) + 1 : doc.Cells.Count;
            doc.Cells.Insert(i, c);
            SelectedId = c.Id;
            doc.ModifiedAt = DateTime.Now;
            SaveSoon();
            RenderCells(); RenderToolbar(); RenderSidebar();
            if (Ai != null) Ai.RefreshScope();
            var card = CardFor(c);
            if (card != null) Dispatcher.BeginInvoke(new Action(() => { card.BringIntoView(); card.FocusEditor(); }), DispatcherPriority.Loaded);
            return c;
        }

        internal void DeleteCell(NbCell c)
        {
            var doc = Doc;
            int i = doc.Cells.IndexOf(c);
            if (i < 0) return;
            _queue.Remove(c.Id);
            doc.Cells.RemoveAt(i);
            if (SelectedId == c.Id) SelectedId = doc.Cells.Count > 0 ? doc.Cells[0].Id : null;
            doc.ModifiedAt = DateTime.Now;
            SaveSoon(); RenderCells(); RenderToolbar(); RenderSidebar();
            if (Ai != null) Ai.RefreshScope();
        }

        internal void MoveCell(NbCell c, int dir)
        {
            var doc = Doc;
            int i = doc.Cells.IndexOf(c), j = i + dir;
            if (i < 0 || j < 0 || j >= doc.Cells.Count) return;
            doc.Cells[i] = doc.Cells[j]; doc.Cells[j] = c;
            doc.ModifiedAt = DateTime.Now;
            SaveSoon(); RenderCells();
        }

        void CreateNotebook()
        {
            var d = NbStore.NewDoc("Cell Sheet " + (NbStore.Docs.Count + 1));
            NbStore.Docs.Add(d);
            SelectNotebook(d);
        }

        void SelectNotebook(NbDoc d)
        {
            if (NbStore.ActiveId == d.Id) return;
            Kernel.Changed -= OnKernelChanged;
            NbStore.ActiveId = d.Id;
            SelectedId = d.Cells.Count > 0 ? d.Cells[0].Id : null;
            _queue.Clear();
            _cards.Clear(); Editors.Clear();
            TotalExec = d.Cells.Count == 0 ? 0 : d.Cells.Max(c => c.ExecCount);
            Epoch = d.Cells.Count == 0 ? 0 : d.Cells.Max(c => c.LastRunEpoch);
            var k = Kernel; k.Changed += OnKernelChanged; if (k.Status == "Not Started") k.Start();
            SaveSoon();
            RenderAll();
            if (Ai != null) Ai.RefreshScope();
        }

        void DeleteNotebook(NbDoc d)
        {
            if (NbStore.Docs.Count <= 1) return;
            bool wasActive = NbStore.ActiveId == d.Id;
            NbPythonKernel.For(d.Id).Kill(null);
            NbStore.Docs.Remove(d);
            if (wasActive) { NbStore.ActiveId = null; SelectNotebook(NbStore.Docs[0]); }
            else { SaveSoon(); RenderSidebar(); }
        }

        // ── execution queue (Cell Mode v2 sequential scheduler) ──────────────
        public void RunCell(NbCell c)
        {
            if (c == null || !c.IsRunnable) return;
            if (c.IsQueued && !c.IsExecuting) { _queue.Remove(c.Id); c.IsQueued = false; RefreshCell(c); return; }
            if (c.IsExecuting) { CancelQueue(); Interrupt(c); return; }
            if (_draining || AnyExecuting) { Enqueue(new[] { c }); return; }
            StartCell(c, ok =>
            {
                if (ok && Reactive) EnqueueDownstream(c, false);
                Drain();
            });
        }

        internal void Enqueue(IEnumerable<NbCell> cells)
        {
            foreach (var c in cells)
            {
                if (!c.IsRunnable || c.IsExecuting || _queue.Contains(c.Id)) continue;
                c.IsQueued = true; _queue.Add(c.Id); RefreshCell(c);
            }
            Drain();
        }

        void Drain()
        {
            if (_draining || AnyExecuting) return;
            if (_queue.Count == 0) { if (_kernelStatus == "Running") SetKernelStatus("Idle"); return; }
            string id = _queue[0]; _queue.RemoveAt(0);
            var c = Doc.Cells.FirstOrDefault(x => x.Id == id);
            if (c == null) { Drain(); return; }
            c.IsQueued = false;
            _draining = true;
            StartCell(c, ok =>
            {
                _draining = false;
                if (!ok) { CancelQueue(); SetKernelStatus("Error"); return; }
                Drain();
            });
        }

        void CancelQueue()
        {
            foreach (var id in _queue) { var c = Doc.Cells.FirstOrDefault(x => x.Id == id); if (c != null) { c.IsQueued = false; RefreshCell(c); } }
            _queue.Clear();
        }

        void EnqueueDownstream(NbCell root, bool includeRoot)
        {
            var graph = CellDag.Analyze(Doc.Cells);
            var ids = CellDag.TransitiveDownstream(root.Id, graph, Doc.Cells);
            var batch = new List<NbCell>();
            if (includeRoot) batch.Add(root);
            foreach (var id in ids) { var c = Doc.Cells.FirstOrDefault(x => x.Id == id); if (c != null) batch.Add(c); }
            if (batch.Count > 0) Enqueue(batch);
        }

        internal void RunDownstream(NbCell c) { EnqueueDownstream(c, true); }
        public void RunAll() { Enqueue(Doc.Cells.Where(c => c.Type == "Code" || c.Type == "Procedure").ToList()); }
        void RunByColor(string theme) { Enqueue(Doc.Cells.Where(c => (c.ColorTheme ?? "None") == theme && (c.Type == "Code" || c.Type == "Procedure")).ToList()); }
        void RunByTag(string tag) { Enqueue(Doc.Cells.Where(c => c.IsRunnable && (c.Tag ?? "").Trim() == tag).ToList()); }

        void SetKernelStatus(string s) { _kernelStatus = s; RenderSidebar(); }

        void Interrupt(NbCell c)
        {
            if (c.IsAgent) { NbAgent.Stop("agent-cell-" + c.Id); c.AgentStatus = ""; c.IsExecuting = false; SetKernelStatus("Idle"); RefreshCell(c); return; }
            if (c.Language == "Python" || c.Language == "SQL")
            {
                var k = Kernel;
                k.Interrupt();
                var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
                timer.Tick += delegate { timer.Stop(); if (c.IsExecuting) k.Kill("\u23F9 The cell did not stop within 5 s, so the kernel was restarted (variables cleared)."); };
                timer.Start();
            }
            else NbRunner.Cancel(c.Id);
        }

        static readonly HashSet<string> RichExt = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg", ".pdf", ".md", ".markdown", ".html", ".htm" };

        Dictionary<string, Tuple<DateTime, long>> SnapshotRich()
        {
            var snap = new Dictionary<string, Tuple<DateTime, long>>(StringComparer.OrdinalIgnoreCase);
            string wd = NbStore.WorkingDirectory;
            foreach (var dir in new[] { wd, Path.Combine(wd, "artifacts"), Path.Combine(wd, "figures"), Path.Combine(wd, "outputs"), Path.Combine(wd, "plots") })
            {
                try
                {
                    if (!Directory.Exists(dir)) continue;
                    foreach (var f in Directory.GetFiles(dir))
                        if (RichExt.Contains(Path.GetExtension(f))) { var fi = new FileInfo(f); snap[fi.FullName] = Tuple.Create(fi.LastWriteTimeUtc, fi.Length); }
                }
                catch (Exception ex) { Debug.WriteLine("rich snapshot: " + ex.Message); }
            }
            return snap;
        }

        List<string> ChangedRich(Dictionary<string, Tuple<DateTime, long>> before)
        {
            var changed = new List<Tuple<string, DateTime>>();
            foreach (var kv in SnapshotRich())
            {
                if (kv.Value.Item2 <= 0) continue;
                string name = Path.GetFileName(kv.Key);
                if (name.StartsWith("cell_") && (name.Contains("_run") || name.Contains("_rich") || name.Contains("_fig") || name.Contains("_rplot_"))) continue;
                Tuple<DateTime, long> prev;
                if (!before.TryGetValue(kv.Key, out prev) || prev.Item1 != kv.Value.Item1 || prev.Item2 != kv.Value.Item2) changed.Add(Tuple.Create(kv.Key, kv.Value.Item1));
            }
            return changed.OrderBy(x => x.Item2).Select(x => x.Item1).ToList();
        }

        internal string CellTag(NbCell c) { return "cell_" + c.Id.Replace("-", "").Substring(0, 8).ToLowerInvariant() + "_run" + (TotalExec + 1); }

        void StartCell(NbCell c, Action<bool> done)
        {
            c.IsQueued = false;
            c.IsExecuting = true;
            if (c.IsAgent) c.ClearOutput();
            SetKernelStatus("Running");
            RefreshCell(c);
            if (c.IsAgent) { NbAgent.RunAgentCell(this, c, ok => { c.IsExecuting = false; SetKernelStatus(ok ? "Idle" : "Error"); SaveSoon(); RefreshCell(c); done(ok); }); return; }
            string target = c.ComputeOverride ?? ComputeTargets.Current;
            if (!ComputeTargets.IsLocal(target))
            {
                done(Finalize(c, "\u274C " + ComputeTargets.Display(target) + " is not available in MicroCode for Windows yet (" + ComputeTargets.Unavailable(target) + "). Set this cell's compute engine to Local CPU.", null, null, null, true));
                return;
            }
            string tag = CellTag(c);
            var before = SnapshotRich();
            if (c.Language == "Python" || c.Language == "SQL")
            {
                bool explicitDb = false;
                string code = c.Language == "SQL" ? NbRunner.SqlScript(c.Content, out explicitDb) : c.Content;
                Kernel.Execute(code, tag, live => { c.Output = live; RefreshCellLive(c); }, o =>
                {
                    var files = o.Files.ToList();
                    foreach (var f in ChangedRich(before)) if (!files.Contains(f, StringComparer.OrdinalIgnoreCase)) files.Add(f);
                    done(Finalize(c, o.Text, files, o.DataFrame, o.Telemetry, o.HadError));
                });
                return;
            }
            NbRunner.Run(c, tag, live => { c.Output = live; RefreshCellLive(c); }, r =>
            {
                var files = r.Files.ToList();
                foreach (var f in ChangedRich(before)) if (!files.Contains(f, StringComparer.OrdinalIgnoreCase)) files.Add(f);
                done(Finalize(c, r.Output, files, null, new CellTelemetry { DurationMs = r.Ms }, r.HadError));
            });
        }

        /// <summary>finalizeCellExecution.</summary>
        bool Finalize(NbCell c, string text, List<string> images, InlineDataFrame df, CellTelemetry tel, bool hadError)
        {
            c.Output = (text ?? "").Trim('\r', '\n').TrimEnd();
            c.Images = images ?? new List<string>();
            c.DataFrame = df;
            c.Telemetry = tel;
            c.IsExecuting = false;
            TotalExec++; c.ExecCount = TotalExec;
            Epoch++; c.LastRunEpoch = Epoch;
            c.RecordExecutionSnapshot(tel != null && tel.IsCachedBinary ? "Cached Run" : "Run");
            _kernelStatus = hadError ? "Error" : "Idle";
            Doc.ModifiedAt = DateTime.Now;
            SaveSoon();
            RenderCells(); RenderToolbar(); RenderSidebar();
            if (ShowVars) RenderVarBar();
            if (Ai != null) Ai.RefreshErrorStrip();
            if (ScrollToCell > 0 && _queue.Count <= 1 && ScrollToCell <= Doc.Cells.Count)
            {
                var target = CardFor(Doc.Cells[ScrollToCell - 1]);
                if (target != null) Dispatcher.BeginInvoke(new Action(() => { try { var p = target.TransformToAncestor(_list).Transform(new Point(0, 0)); Scroll.ScrollToVerticalOffset(p.Y + 16 - 8); } catch (InvalidOperationException) { } }), DispatcherPriority.Loaded);
            }
            return !hadError;
        }

        internal void ClearAllOutputs()
        {
            CancelQueue();
            foreach (var c in Doc.Cells) { c.ClearOutput(); c.ExecCount = 0; c.LastRunEpoch = 0; }
            SaveSoon(); RenderCells(); RenderToolbar();
            if (Ai != null) Ai.RefreshErrorStrip();
        }

        internal void RestartKernel()
        {
            CancelQueue();
            Kernel.Restart();
            ClearAllOutputs();
            TotalExec = 0; Epoch = 0;
            SetKernelStatus("Restarted");
            var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            timer.Tick += delegate { timer.Stop(); if (_kernelStatus == "Restarted") SetKernelStatus("Idle"); };
            timer.Start();
            RenderToolbar();
        }

        // ── data files ───────────────────────────────────────────────────────
        string DataDir { get { string d = Path.Combine(NbStore.WorkingDirectory, "data"); Directory.CreateDirectory(d); return d; } }

        void ImportDataFiles()
        {
            var dlg = new Microsoft.Win32.OpenFileDialog { Multiselect = true, Title = "Import Data Files", Filter = "Data files|*.csv;*.tsv;*.json;*.xlsx;*.xls;*.parquet;*.sqlite;*.db;*.txt;*.pdb;*.cif;*.fasta;*.fa;*.h5;*.npy;*.npz|All files|*.*" };
            if (dlg.ShowDialog() != true) return;
            foreach (var f in dlg.FileNames) AddDataFile(f);
        }

        internal void AddDataFile(string path)
        {
            try
            {
                string dir = DataDir, dest;
                if (string.Equals(Path.GetDirectoryName(Path.GetFullPath(path)), dir, StringComparison.OrdinalIgnoreCase)) dest = path;
                else { dest = Unique(dir, Path.GetFileName(path)); File.Copy(path, dest); }
                Doc.Files.RemoveAll(f => string.Equals(f.Path, dest, StringComparison.OrdinalIgnoreCase));
                Doc.Files.Add(NbDataFile.For(dest));
                SaveSoon(); RenderSidebar();
            }
            catch (Exception ex) { MessageBox.Show("Could not import " + Path.GetFileName(path) + ":\n" + ex.Message, "Import Data Files", MessageBoxButton.OK, MessageBoxImage.Warning); }
        }

        static string Unique(string dir, string name)
        {
            string stem = Path.GetFileNameWithoutExtension(name), ext = Path.GetExtension(name), cand = Path.Combine(dir, name);
            for (int i = 2; File.Exists(cand); i++) cand = Path.Combine(dir, stem + " " + i + ext);
            return cand;
        }

        void CreateDataFile()
        {
            try
            {
                string dir = DataDir, p = Path.Combine(dir, "dataset.csv");
                for (int i = 2; File.Exists(p); i++) p = Path.Combine(dir, "dataset_" + i + ".csv");
                File.WriteAllText(p, "column,value\n");
                Doc.Files.Add(NbDataFile.For(p));
                SaveSoon(); RenderSidebar();
            }
            catch (Exception ex) { MessageBox.Show(ex.Message, "New CSV File", MessageBoxButton.OK, MessageBoxImage.Warning); }
        }

        void RenameDataFile(NbDataFile f)
        {
            string n = Prompt.Ask("Rename Data File", "New file name:", f.Name);
            if (string.IsNullOrWhiteSpace(n)) return;
            n = Path.GetFileName(n.Trim());
            if (n.Length == 0 || n == "." || n == "..") return;
            string dest = Path.Combine(Path.GetDirectoryName(f.Path) ?? DataDir, n);
            if (File.Exists(dest)) { MessageBox.Show(n + " already exists.", "Rename Data File", MessageBoxButton.OK, MessageBoxImage.Warning); return; }
            try { File.Move(f.Path, dest); f.Path = dest; f.Name = n; f.Type = NbDataFile.TypeFor(Path.GetExtension(dest)); SaveSoon(); RenderSidebar(); }
            catch (Exception ex) { MessageBox.Show(ex.Message, "Rename Data File", MessageBoxButton.OK, MessageBoxImage.Warning); }
        }

        void DeleteDataFile(NbDataFile f)
        {
            if (MessageBox.Show("Move " + f.Name + " to the Recycle Bin?\n\nThe file will be moved to the Recycle Bin and removed from this notebook.", "Move to Recycle Bin", MessageBoxButton.OKCancel, MessageBoxImage.Warning) != MessageBoxResult.OK) return;
            try
            {
                if (File.Exists(f.Path)) Microsoft.VisualBasic.FileIO.FileSystem.DeleteFile(f.Path, Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs, Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin);
                Doc.Files.Remove(f); SaveSoon(); RenderSidebar();
            }
            catch (Exception ex) { MessageBox.Show(ex.Message, "Move to Recycle Bin", MessageBoxButton.OK, MessageBoxImage.Warning); }
        }

        /// <summary>syncScientificFiles: index data-like files in the open project (≤1000) and drop references to files that are gone.</summary>
        void SyncWorkspaceFiles()
        {
            string ws = App.WorkspaceFolder;
            if (ws == null) return;
            var exts = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".csv", ".tsv", ".xlsx", ".xls", ".json", ".parquet", ".sqlite", ".db", ".pdb", ".ent", ".cif", ".mmcif", ".fasta", ".fa", ".faa", ".fna", ".a3m", ".h5", ".hdf5", ".h5ad", ".npy", ".npz", ".sdf", ".mol", ".mol2" };
            var skip = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "node_modules", ".git", "bin", "obj", "build", "dist", ".venv", "venv", "__pycache__", "out", "target" };
            var found = new List<string>();
            var stack = new Stack<string>(); stack.Push(ws);
            while (stack.Count > 0 && found.Count < 1000)
            {
                string dir = stack.Pop();
                try
                {
                    foreach (var f in Directory.GetFiles(dir)) if (exts.Contains(Path.GetExtension(f))) { found.Add(f); if (found.Count >= 1000) break; }
                    foreach (var sub in Directory.GetDirectories(dir)) if (!skip.Contains(Path.GetFileName(sub)) && !Path.GetFileName(sub).StartsWith(".")) stack.Push(sub);
                }
                catch (Exception ex) { Debug.WriteLine("sync scan: " + ex.Message); }
            }
            Doc.Files.RemoveAll(f => f.Path.StartsWith(ws, StringComparison.OrdinalIgnoreCase) && !File.Exists(f.Path));
            foreach (var f in found) if (!Doc.Files.Any(x => string.Equals(x.Path, f, StringComparison.OrdinalIgnoreCase))) Doc.Files.Add(NbDataFile.For(f));
            SaveSoon(); RenderSidebar();
        }

        /// <summary>insertLoaderCell(for:).</summary>
        internal void InsertLoaderCell(NbDataFile f)
        {
            string p = f.Path.Replace("\\", "\\\\").Replace("\"", "\\\"");
            string code;
            switch (f.Type)
            {
                case "Structure":
                    code = "from pathlib import Path\nstructure_path = Path(r\"" + p + "\")\nprint(f\"Structure: {structure_path.name}\")\ntry:\n    from Bio.PDB import PDBParser, MMCIFParser\nexcept ImportError:\n    print(\"Biopython is not installed. Run: pip install biopython\")\nelse:\n    parser = MMCIFParser(QUIET=True) if structure_path.suffix.lower() in {\".cif\", \".mmcif\"} else PDBParser(QUIET=True)\n    structure = parser.get_structure(structure_path.stem, structure_path)\n    print(\"Models:\", len(list(structure.get_models())))\n    print(\"Chains:\", [chain.id for chain in structure.get_chains()])";
                    break;
                case "Sequence":
                    code = "from pathlib import Path\nfasta_path = Path(r\"" + p + "\")\ntry:\n    from Bio import SeqIO\nexcept ImportError:\n    print(\"Biopython is not installed. Run: pip install biopython\")\nelse:\n    records = list(SeqIO.parse(fasta_path, \"fasta\"))\n    print(f\"{len(records)} sequences\", [len(r.seq) for r in records[:20]])";
                    break;
                case "CSV": code = "import pandas as pd\ndata = pd.read_csv(r\"" + p + "\")\ndisplay(data.head())"; break;
                case "Excel": code = "import pandas as pd\ndata = pd.read_excel(r\"" + p + "\")\ndisplay(data.head())"; break;
                case "Parquet": code = "import pandas as pd\ndata = pd.read_parquet(r\"" + p + "\")\ndisplay(data.head())"; break;
                case "JSON": code = "import json\nwith open(r\"" + p + "\") as f:\n    data = json.load(f)\nprint(type(data), data if isinstance(data, dict) else f\"{len(data)} records\")"; break;
                default: code = "from pathlib import Path\nartifact = Path(r\"" + p + "\")\nprint(artifact, artifact.stat().st_size, \"bytes\")"; break;
            }
            var c = AddCell("Code", "Python");
            c.Content = code;
            RefreshEditor(c);
            SaveSoon();
        }

        // ── files: open / save / export ──────────────────────────────────────
        void OpenNotebookFile()
        {
            var dlg = new Microsoft.Win32.OpenFileDialog { Title = "Open Notebook", Filter = "Notebooks (*.mic;*.mcnb;*.ipynb;*.py)|*.mic;*.mcnb;*.ipynb;*.py|JSON (*.json)|*.json|All files|*.*" };
            if (dlg.ShowDialog() != true) return;
            OpenNotebook(dlg.FileName);
        }

        public void OpenNotebook(string path)
        {
            try
            {
                var d = NbFormats.Load(path);
                NbStore.Docs.Add(d);
                NbStore.ActiveId = null;
                SelectNotebook(d);
            }
            catch (Exception ex) { MessageBox.Show("Could not open " + Path.GetFileName(path) + ":\n" + ex.Message, "Open Notebook", MessageBoxButton.OK, MessageBoxImage.Warning); }
        }

        void QuickSave()
        {
            var d = Doc;
            if (d.FilePath == null) { SaveAs(); return; }
            try { NbFormats.SaveMic(d, d.FilePath); _lastAutoSave = DateTime.Now; }
            catch (Exception ex) { MessageBox.Show(ex.Message, "Quick Save", MessageBoxButton.OK, MessageBoxImage.Warning); }
        }

        void SaveAs()
        {
            var d = Doc;
            var dlg = new Microsoft.Win32.SaveFileDialog { Title = "Save Notebook", FileName = SafeName(d.Name) + ".mic", Filter = "MicroCode Notebook (*.mic)|*.mic", DefaultExt = ".mic" };
            if (dlg.ShowDialog() != true) return;
            try { NbFormats.SaveMic(d, dlg.FileName); d.FilePath = dlg.FileName; _lastAutoSave = DateTime.Now; SaveSoon(); }
            catch (Exception ex) { MessageBox.Show(ex.Message, "Save Notebook", MessageBoxButton.OK, MessageBoxImage.Warning); }
        }

        void ExportIpynb()
        {
            var d = Doc;
            var dlg = new Microsoft.Win32.SaveFileDialog { Title = "Export as Jupyter Notebook", FileName = SafeName(d.Name) + ".ipynb", Filter = "Jupyter Notebook (*.ipynb)|*.ipynb", DefaultExt = ".ipynb" };
            if (dlg.ShowDialog() != true) return;
            try { NbFormats.SaveIpynb(d, dlg.FileName); }
            catch (Exception ex) { MessageBox.Show(ex.Message, "Export", MessageBoxButton.OK, MessageBoxImage.Warning); }
        }

        void ExportPy()
        {
            var d = Doc;
            var dlg = new Microsoft.Win32.SaveFileDialog { Title = "Export as Plain-Text Python Script (# %%)", FileName = SafeName(d.Name.Replace(".mic", "").Replace(".ipynb", "")) + ".py", Filter = "Python script (*.py)|*.py", DefaultExt = ".py" };
            if (dlg.ShowDialog() != true) return;
            try { File.WriteAllText(dlg.FileName, NbFormats.ToPy(d), new System.Text.UTF8Encoding(false)); }
            catch (Exception ex) { MessageBox.Show(ex.Message, "Export", MessageBoxButton.OK, MessageBoxImage.Warning); }
        }

        /// <summary>GoogleColabService.openColabInBrowser: writes the sheet as .ipynb and opens a new Colab notebook to upload it into.</summary>
        void OpenInColab()
        {
            try
            {
                string dir = Path.Combine(Path.GetTempPath(), "MicroCode", "colab");
                Directory.CreateDirectory(dir);
                string p = Path.Combine(dir, SafeName(Doc.Name) + ".ipynb");
                NbFormats.SaveIpynb(Doc, p);
                Process.Start(new ProcessStartInfo("https://colab.research.google.com/#create=true") { UseShellExecute = true });
                Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + p + "\"") { UseShellExecute = true });
            }
            catch (Exception ex) { MessageBox.Show(ex.Message, "Open in Google Colab", MessageBoxButton.OK, MessageBoxImage.Warning); }
        }

        static string SafeName(string n) { foreach (var ch in Path.GetInvalidFileNameChars()) n = n.Replace(ch, '_'); return n.Length == 0 ? "Notebook" : n; }

        DispatcherTimer _saveTimer;
        internal void SaveSoon()
        {
            if (_saveTimer == null)
            {
                _saveTimer = new DispatcherTimer();
                _saveTimer.Tick += delegate
                {
                    _saveTimer.Stop();
                    if (AnyExecuting) { SaveSoon(); return; }
                    NbStore.Save();
                    if (NbStore.Seed != null) return;
                    var d = Doc;
                    try
                    {
                        // performAutoSave: the bound .mic, or autosave.mic in the notebook workspace
                        NbFormats.SaveMic(d, d.FilePath ?? Path.Combine(NbStore.WorkingDirectory, "autosave.mic"));
                        _lastAutoSave = DateTime.Now;
                    }
                    catch (Exception ex) { Debug.WriteLine("autosave: " + ex.Message); }
                };
            }
            _saveTimer.Interval = TimeSpan.FromMilliseconds(AnyExecuting ? 1800 : 800);
            _saveTimer.Stop(); _saveTimer.Start();
        }

        // ── agent panel host ─────────────────────────────────────────────────
        internal void ToggleAgentPanel()
        {
            _showAI = !_showAI;
            Defaults.Set("notebook.showAIPanel", _showAI);
            RenderAI(); RenderToolbar(); ApplyWidths();
        }

        void RenderAI()
        {
            if (!_showAI) { _aiHost.Child = null; return; }
            if (Ai == null) Ai = new NotebookAIPanel(this);
            if (Ai.Parent is Decorator) ((Decorator)Ai.Parent).Child = null;
            _aiHost.Child = Ai;
            Ai.RefreshScope();
        }

        // ── keyboard ─────────────────────────────────────────────────────────
        void OnKey(object sender, KeyEventArgs e)
        {
            var m = Keyboard.Modifiers;
            if (e.Key == Key.Enter && (m == ModifierKeys.Shift || m == ModifierKeys.Control))
            {
                if (Ai != null && Ai.IsKeyboardFocusWithin) return;
                var c = Selected;
                if (c == null || c.IsAgent) return;
                if (c.IsRunnable) RunCell(c);
                if (m == ModifierKeys.Shift)
                {
                    int i = Doc.Cells.IndexOf(c);
                    if (i == Doc.Cells.Count - 1) AddCell("Code", c.IsCode ? c.Language : "Python");
                    else { Select(Doc.Cells[i + 1]); var card = CardFor(Doc.Cells[i + 1]); if (card != null) card.FocusEditor(); }
                }
                e.Handled = true;
            }
            else if (e.Key == Key.S && m == ModifierKeys.Control) { QuickSave(); e.Handled = true; }
            else if (e.Key == Key.S && m == (ModifierKeys.Control | ModifierKeys.Shift)) { SaveAs(); e.Handled = true; }
        }

        // ── cell agent tools (cell_list / cell_read / cell_create / cell_update / cell_delete / cell_run) ──
        public string NotebookContext() { return NbAgent.NotebookSnapshot(this); }
        public int CellCount { get { return Doc.Cells.Count; } }
    }
}
