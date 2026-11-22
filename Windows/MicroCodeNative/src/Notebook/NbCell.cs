// Port of NotebookCellView (NotebookView.swift) and the Cell Mode output views in DataFrameView.swift:
// standard / inline-agent / executive app-mode cards, cellHeader chips, # @param widgets, AI ghost-diff banner, time-travel
// history, self-healing error banner, virtualized output log, inline graph / PDF / Markdown-TeX / HTML cards and the
// inline DataFrame grid & chart studio.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using MicroCode.Core;
using MicroCode.Editor;
using MicroCode.UI;

namespace MicroCode.Views
{
    internal class CellCard : Border
    {
        readonly NotebookView _nb;
        internal readonly NbCell Cell;
        internal CellDagInfo Dag;
        bool _hover, _mdEditing, _fixing;
        string _fixStatus = "";
        readonly List<UIElement> _hoverOnly = new List<UIElement>();
        Border _outputsHost;
        UIElement _play;

        const double Gutter = 46;

        public CellCard(NotebookView nb, NbCell c)
        {
            _nb = nb; Cell = c;
            SnapsToDevicePixels = true;
            MouseEnter += delegate { _hover = true; UpdateChrome(); };
            MouseLeave += delegate { _hover = false; UpdateChrome(); };
            PreviewMouseLeftButtonDown += delegate { _nb.Select(Cell); };
        }

        bool Sel { get { return _nb.SelectedId == Cell.Id; } }
        double CardW { get { return _nb.CardWidth; } }
        double MainW { get { return Math.Max(216, CardW - Gutter - 8); } }
        double EditorW { get { return Math.Max(200, MainW - 8); } }
        double RichW { get { return _nb.AppMode ? Math.Max(240, CardW - 20) : Math.Max(196, MainW - 16); } }
        static Theme T { get { return Theme.Current; } }
        static bool Dark { get { return Theme.Current.IsDark; } }

        /// <summary>Selection border and hover-only controls (move / collapse / delete, run button) without rebuilding the card.</summary>
        internal void UpdateChrome()
        {
            bool show = _hover || Sel;
            foreach (var e in _hoverOnly) { e.Opacity = show ? 1 : 0; e.IsHitTestVisible = show; }
            if (_play != null) { bool p = _hover || Sel || Cell.IsExecuting; _play.Opacity = p ? 1 : 0; }
            if (Cell.IsAgent || _nb.AppMode) BorderBrush = Cell.IsAgent && !_nb.AppMode ? (Sel ? T.A(0.85) : T.P(Dark ? 0.12 : 0.09)) : Cell.BorderTint;
            else BorderBrush = Sel ? T.A(0.9) : Cell.BorderTint;
        }

        internal void FocusEditor()
        {
            CodeEditorView ed;
            if (_nb.Editors.TryGetValue(Cell.Id, out ed)) ed.Focus2();
        }

        internal void Rebuild()
        {
            _hoverOnly.Clear(); _outputsHost = null; _play = null;
            Visibility = Visibility.Visible;
            if (_nb.AppMode) BuildAppMode();
            else if (Cell.IsAgent) BuildAgentCard();
            else BuildStandard();
            UpdateChrome();
        }

        internal void RefreshOutputs()
        {
            if (_outputsHost == null || Cell.IsAgent) { Rebuild(); return; }
            _outputsHost.Child = Outputs();
        }

        UIElement Layered(UIElement content, double radius)
        {
            // ZStack { elevatedBackground; colour-theme tint } behind the content
            var g = new Grid();
            g.Children.Add(new Border { Background = Cell.CardTint, CornerRadius = new CornerRadius(Math.Max(0, radius - 1)) });
            g.Children.Add(content);
            return g;
        }

        void Frame(UIElement content, double radius)
        {
            Background = T.ElevatedBackground;
            CornerRadius = new CornerRadius(radius);
            BorderThickness = new Thickness(_nb.AppMode ? 0.8 : 1);
            Child = Layered(content, radius);
        }

        // ── standardNotebookCellCard ─────────────────────────────────────────
        void BuildStandard()
        {
            var t = T;
            var row = new Grid();
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Gutter) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            // left gutter: [n] + play / stop
            string label = Cell.IsExecuting ? "[*]" : Cell.IsQueued ? "[\u23F3]" : Cell.ExecCount > 0 ? "[" + Cell.ExecCount + "]" : "[ ]";
            var count = V.Mono(label, 10, FontWeights.Normal, t.Secondary); count.Width = 40; count.TextAlignment = TextAlignment.Center;
            var gutter = V.Vs(4, count);
            if (Cell.IsRunnable)
            {
                var play = V.Button(Sym.Icon(Cell.IsExecuting ? "stop.circle.fill" : "play.circle.fill", 16, Cell.IsExecuting ? t.SysRed : t.SysGreen), () => _nb.RunCell(Cell));
                play.ToolTip = Cell.IsExecuting ? "Stop" : "Run Cell";
                _play = play;
                gutter.Children.Add(play);
            }
            gutter.VerticalAlignment = VerticalAlignment.Top; gutter.Margin = new Thickness(0, 12, 0, 0);
            row.Children.Add(gutter);

            var main = V.VLead(0); main.Align = Cross.Stretch;
            main.Children.Add(Header());
            if (!Cell.Collapsed)
            {
                if (Cell.PendingDiffOld != null && Cell.PendingDiffOld != Cell.Content) main.Children.Add(DiffBanner());
                if (Cell.IsCode)
                {
                    var specs = CellParams.Parse(Cell.Content);
                    if (specs.Count > 0) main.Children.Add(ParamBar(specs));
                }
                if (Cell.Type == "Markdown") main.Children.Add(RichMarkdown(false));
                else main.Children.Add(Editor());
                if (HasOutput)
                {
                    var line = V.Line(t.Separator, true); line.Margin = new Thickness(8, 0, 8, 0);
                    main.Children.Add(line);
                    _outputsHost = new Border { Padding = new Thickness(8), Child = Outputs(), Opacity = Cell.IsExecuting ? 0.65 : 1 };
                    main.Children.Add(_outputsHost);
                }
            }
            var mainBox = new Border { Child = main, Margin = new Thickness(0, 0, 8, 8) };
            Grid.SetColumn(mainBox, 1);
            row.Children.Add(mainBox);
            Frame(row, 12);
        }

        bool HasOutput { get { return (Cell.Output ?? "").Length > 0 || Cell.Images.Count > 0 || Cell.DataFrame != null; } }

        // ── cellHeader ───────────────────────────────────────────────────────
        static Btn Chip(UIElement content, Brush bg, Thickness pad, double radius, Action click)
        {
            var b = V.Button(V.Box(content, pad, bg, radius), click);
            b.VerticalAlignment = VerticalAlignment.Center;
            return b;
        }

        UIElement Header()
        {
            var t = T;
            bool compact = MainW < 560;
            var h = V.H(5);
            if (!Cell.IsCode)
            {
                Brush tc = Cell.Type == "Markdown" ? t.SysGreen : Cell.Type == "Raw" ? t.SysGray : Cell.Type == "Procedure" ? t.SysOrange : t.Accent;
                var badge = V.Box(V.T(Cell.Type, 9, FontWeights.Medium, tc), V.P(6, 2), NbColor.Alpha((SolidColorBrush)tc, 0.16), 4);
                h.Children.Add(badge);
            }
            else
            {
                var lang = Cell.Lang;
                var langChip = Chip(V.H(4, Sym.Icon(lang.Icon, 10, lang.Brush), V.T(lang.Name, 9, FontWeights.Medium, lang.Brush)), NbColor.Alpha(lang.Brush, 0.2), V.P(6, 2), 4, null);
                langChip.MenuItems = () => CellLang.All.Select(l => { var ll = l; return new MenuItemSpec { Title = l.Name, Icon = l.Icon, Checked = Cell.Language == l.Name, Action = () => SetLanguage(ll.Name) }; }).ToList();
                h.Children.Add(langChip);

                string cur = Cell.ComputeOverride ?? ComputeTargets.Current;
                bool over = Cell.ComputeOverride != null;
                var cr = V.H(3, Sym.Icon(over ? ComputeTargets.Icon(cur) : "arrow.triangle.branch", 8.5, over ? t.Accent : t.Secondary));
                if (over || !compact) cr.Children.Add(V.T(over ? ComputeTargets.Display(cur) : "Default", 9, FontWeights.Medium, over ? t.Accent : t.Secondary));
                var comp = Chip(cr, over ? t.A(0.18) : t.S(0.12), V.P(5, 2), 4, null);
                comp.ToolTip = "Per-Cell Compute Engine (Overrides default target for this cell)";
                comp.MenuItems = () =>
                {
                    var items = new List<MenuItemSpec> { new MenuItemSpec { Title = "Default (" + ComputeTargets.Display(ComputeTargets.Current) + ")", Checked = Cell.ComputeOverride == null, Action = () => { Cell.ComputeOverride = null; _nb.SaveSoon(); Rebuild(); } }, MenuItemSpec.Sep() };
                    foreach (var target in ComputeTargets.UserSelectable)
                    {
                        var tg = target; string why = ComputeTargets.Unavailable(tg);
                        items.Add(new MenuItemSpec { Title = ComputeTargets.Display(tg) + (why != null ? "  (" + why + ")" : ""), Icon = ComputeTargets.Icon(tg), Checked = Cell.ComputeOverride == tg, Disabled = why != null, Action = () => { Cell.ComputeOverride = tg; _nb.SaveSoon(); Rebuild(); } });
                    }
                    return items;
                };
                h.Children.Add(comp);
            }

            // name-tag chip
            bool hasTag = (Cell.Tag ?? "").Length > 0;
            var tagRow = V.H(3, Sym.Icon(hasTag ? "tag.fill" : "tag", 9, hasTag ? t.Accent : t.Secondary));
            if (hasTag || !compact) { var tt = V.T(hasTag ? Cell.Tag : "Tag", 9, FontWeights.Medium, hasTag ? t.Accent : t.Secondary); tt.MaxWidth = 64; tagRow.Children.Add(tt); }
            Btn tag = null;
            tag = Chip(tagRow, hasTag ? t.A(0.18) : t.S(0.18), V.P(5.5, 2), 4, () => TagEditor(tag));
            tag.ToolTip = "Name this cell for selective Run by Tag";
            h.Children.Add(tag);

            // colour picker menu
            Brush dot = Cell.UseCustomColor && Cell.CustomColor != null ? Cell.CustomColor.Border : CellColors.Icon(Cell.ColorTheme);
            var color = Chip(V.H(2, V.Dot(10, dot), Sym.Icon("chevron.down", 8, t.Secondary)), t.ElevatedBackground == null ? null : (Brush)ControlBg, V.P(4, 2), 4, null);
            color.MenuItems = ColorMenu;
            h.Children.Add(color);
            if (Cell.UseCustomColor)
            {
                Btn sw = null;
                sw = V.Button(V.Box(new Border(), V.P(0), Cell.CustomColor != null ? Cell.CustomColor.Border : t.SysBlue, 5, t.P(0.25), 1), () => CustomColorEditor(sw));
                sw.Width = 18; sw.Height = 18; sw.ToolTip = "Custom cell colour";
                h.Children.Add(sw);
            }

            // post-run badges: DAG lineage + telemetry + time-travel history (tiered so Run never widens the header)
            bool full = MainW >= 560;
            foreach (var b in DagBadges(!full)) h.Children.Add(b);
            var tel = TelemetryPill(full);
            if (tel != null) h.Children.Add(tel);
            var hist = HistoryButton();
            if (hist != null && MainW >= 300) h.Children.Add(hist);

            h.Children.Add(V.Sp(2));
            var acts = V.H(7,
                V.Tip(V.Button(Sym.Icon("arrow.up", 11, t.Secondary), () => _nb.MoveCell(Cell, -1)), "Move Cell Up"),
                V.Tip(V.Button(Sym.Icon("arrow.down", 11, t.Secondary), () => _nb.MoveCell(Cell, 1)), "Move Cell Down"),
                V.Tip(V.Button(Sym.Icon(Cell.Collapsed ? "chevron.down" : "chevron.up", 11, t.Secondary), () => { Cell.Collapsed = !Cell.Collapsed; _nb.SaveSoon(); Rebuild(); }), Cell.Collapsed ? "Expand Cell" : "Collapse Cell"),
                V.Tip(V.Button(Sym.Icon("trash", 11, t.SysRed), () => _nb.DeleteCell(Cell)), "Delete Cell"));
            _hoverOnly.Add(acts);
            h.Children.Add(acts);
            var box = new Border { Child = h, Height = 28, Padding = new Thickness(8, 0, 8, 0), ClipToBounds = true };
            return box;
        }

        static Brush ControlBg { get { return Theme.Current.ElevatedBackground; } }

        void SetLanguage(string lang)
        {
            Cell.Language = lang;
            CodeEditorView ed;
            if (_nb.Editors.TryGetValue(Cell.Id, out ed)) ed.SetLanguage(CellLang.Get(lang).EditorKey);
            _nb.SaveSoon();
            Rebuild();
        }

        List<MenuItemSpec> ColorMenu()
        {
            var items = new List<MenuItemSpec> { MenuItemSpec.Header("Preset Colors") };
            foreach (var th in new[] { "None", "Gray", "Blue", "Green", "Purple", "Orange", "Pink", "Yellow", "Red", "Cyan", "Teal", "Indigo", "Mint", "Brown" })
            {
                var theme = th;
                items.Add(new MenuItemSpec { Title = theme, Icon = "circle.fill", Checked = Cell.ColorTheme == theme && !Cell.UseCustomColor, Action = () => { Cell.ColorTheme = theme; Cell.UseCustomColor = false; _nb.SaveSoon(); _nb.RenderCells(); } });
            }
            items.Add(MenuItemSpec.Sep());
            items.Add(new MenuItemSpec { Title = "Custom Color...", Icon = "paintpalette", Checked = Cell.UseCustomColor, Action = () => { Cell.UseCustomColor = true; if (Cell.CustomColor == null) Cell.CustomColor = new CustomCellColor(); _nb.SaveSoon(); Rebuild(); } });
            return items;
        }

        void CustomColorEditor(FrameworkElement anchor)
        {
            var t = T;
            var cc = Cell.CustomColor ?? (Cell.CustomColor = new CustomCellColor());
            var col = V.VLead(8, V.T("Custom Cell Color", 12, FontWeights.SemiBold, t.Primary));
            col.Align = Cross.Stretch;
            Action<string, Func<double>, Action<double>> slider = (name, get, set) =>
            {
                var s = new Slider { Minimum = 0, Maximum = 1, Value = get(), Width = 170, SmallChange = 0.01, LargeChange = 0.1 };
                var val = V.Mono(((int)Math.Round(get() * 255)).ToString(), 10, FontWeights.Medium, t.Secondary);
                val.Width = 28;
                s.ValueChanged += (o, e) => { set(e.NewValue); val.Text = ((int)Math.Round(e.NewValue * 255)).ToString(); _nb.SaveSoon(); Rebuild(); };
                var lbl = V.T(name, 11, FontWeights.Medium, t.Primary); lbl.Width = 50;
                col.Children.Add(V.H(6, lbl, s, val));
            };
            slider("Red", () => cc.Red, v => cc.Red = v);
            slider("Green", () => cc.Green, v => cc.Green = v);
            slider("Blue", () => cc.Blue, v => cc.Blue = v);
            slider("Opacity", () => cc.Opacity, v => cc.Opacity = v);
            NbPop.Show(anchor, V.Box(col, V.P(14), null, 0), double.NaN);
        }

        void TagEditor(FrameworkElement anchor)
        {
            var t = T;
            TextBox box;
            var field = Styles.Field("e.g. setup, train, report", 12, t.Primary, t.Secondary, out box);
            box.Text = Cell.Tag ?? "";
            var fieldBox = V.Box(field, V.P(6, 3), t.TextBackground, 5, t.P(0.2), 1); fieldBox.Width = 220;
            Popup pop = null;
            Action set = () => { Cell.Tag = box.Text.Trim(); _nb.SaveSoon(); if (pop != null) pop.IsOpen = false; Rebuild(); };
            box.KeyDown += (s, e) => { if (e.Key == Key.Enter) { set(); e.Handled = true; } };
            var clear = V.Button(V.Box(V.T("Clear", 11, FontWeights.Medium, t.Secondary), V.P(10, 4), t.P(0.07), 5), () => { Cell.Tag = ""; _nb.SaveSoon(); if (pop != null) pop.IsOpen = false; Rebuild(); });
            var setB = V.Button(V.Box(V.T("Set", 11, FontWeights.SemiBold, Brushes.White), V.P(12, 4), t.Accent, 5), set);
            var buttons = V.H(6, clear, V.Sp(), setB); buttons.Width = 220;
            var col = V.VLead(10, V.T("Cell Name-tag", 12, FontWeights.SemiBold, t.Primary), fieldBox, buttons);
            pop = NbPop.Show(anchor, V.Box(col, V.P(14), null, 0), double.NaN);
            pop.Opened += delegate { box.Focus(); box.SelectAll(); };
            Dispatcher.BeginInvoke(new Action(() => { box.Focus(); box.SelectAll(); }), DispatcherPriority.Input);
        }

        IEnumerable<UIElement> DagBadges(bool compact)
        {
            var t = T;
            var list = new List<UIElement>();
            if (Dag == null) return list;
            if (Dag.IsStale)
            {
                var r = V.H(2.5, Sym.Icon("exclamationmark.arrow.triangle.2.circlepath", 8.5, t.SysOrange, FontWeights.SemiBold));
                if (!compact) r.Children.Add(V.T("Stale", 9, FontWeights.SemiBold, t.SysOrange));
                var b = Chip(r, NbColor.Alpha(t.SysOrange, 0.15), V.P(5, 2), 4, () => _nb.RunCell(Cell));
                b.ToolTip = "Upstream cell (" + string.Join(", ", Dag.UpstreamNumbers.Select(n => "#" + n)) + ") updated " + string.Join(", ", Dag.UpstreamSymbols) + ". Click to re-run.";
                list.Add(b);
            }
            if (Dag.Downstream.Count > 0)
            {
                var b = Chip(V.H(2.5, Sym.Icon("arrow.turn.right.down", 8, t.Secondary, FontWeights.SemiBold), V.Mono(Dag.Downstream.Count.ToString(), 9, FontWeights.Medium, t.Secondary)), t.P(0.06), V.P(4.5, 2), 4, () => _nb.RunDownstream(Cell));
                b.ToolTip = "Run this cell + " + Dag.Downstream.Count + " downstream dependent cell(s)";
                list.Add(b);
            }
            return list;
        }

        UIElement TelemetryPill(bool full)
        {
            var tel = Cell.Telemetry;
            if (tel == null) return null;
            var t = T;
            Brush fg = tel.IsCachedBinary ? (Brush)t.SysGreen : t.Secondary;
            var r = V.H(3.5, Sym.Icon(tel.IsCachedBinary ? "bolt.fill" : "timer", 8, fg));
            if (tel.IsCachedBinary && full) r.Children.Add(V.T("Cached", 8.5, FontWeights.SemiBold, t.SysGreen));
            r.Children.Add(V.Mono(tel.FormattedDuration, 9, FontWeights.Medium, fg));
            if (full)
            {
                if (tel.FormattedMemoryDelta != null) r.Children.Add(V.Mono("\u00B7 " + tel.FormattedMemoryDelta, 8.5, FontWeights.Normal, t.S(0.85)));
                if (tel.FormattedGpu != null) r.Children.Add(V.Mono("\u00B7 " + tel.FormattedGpu, 8.5, FontWeights.SemiBold, t.SysPurple));
            }
            var box = V.Box(r, V.P(5, 2), tel.IsCachedBinary ? NbColor.Alpha(t.SysGreen, 0.065) : t.P(0.065), 4);
            box.VerticalAlignment = VerticalAlignment.Center;
            return box;
        }

        UIElement HistoryButton()
        {
            if (Cell.Versions.Count == 0) return null;
            var t = T;
            Btn b = null;
            b = Chip(V.H(2.5, Sym.Icon("clock.arrow.circlepath", 8.5, t.Secondary), V.Mono("v" + Cell.Versions[Cell.Versions.Count - 1].VersionNumber, 9, FontWeights.Medium, t.Secondary)), t.P(0.06), V.P(5, 2), 4, () => HistoryPopover(b));
            b.ToolTip = "Cell Execution & Edit History (Time-Travel)";
            return b;
        }

        void HistoryPopover(FrameworkElement anchor)
        {
            var t = T;
            Popup pop = null;
            var list = V.VLead(6); list.Align = Cross.Stretch;
            foreach (var s in Enumerable.Reverse(Cell.Versions))
            {
                var snap = s;
                var top = V.H(5, V.Mono("v" + s.VersionNumber, 10.5, FontWeights.Bold, t.Accent), V.T(s.SourceLabel, 10, FontWeights.Medium, t.Primary));
                if (s.DurationMs.HasValue) top.Children.Add(V.Mono("\u00B7 " + s.DurationMs.Value.ToString("0.0", CultureInfo.InvariantCulture) + "ms", 9.5, FontWeights.Normal, t.Secondary));
                var preview = V.Mono(s.Content.Replace("\n", " "), 10, FontWeights.Normal, t.Secondary);
                preview.TextWrapping = TextWrapping.Wrap; preview.MaxHeight = 28; preview.TextTrimming = TextTrimming.CharacterEllipsis;
                var restore = V.Button(V.Box(V.T("Restore", 10, FontWeights.SemiBold, t.Primary), V.P(7, 3), t.P(0.09), 4), () =>
                {
                    Cell.Content = snap.Content; Cell.PendingDiffOld = null;
                    if (pop != null) pop.IsOpen = false;
                    _nb.RefreshEditor(Cell); _nb.SaveSoon();
                });
                list.Children.Add(V.Box(V.H(8, V.Flex(V.VLead(2, top, preview)), restore), V.P(6), t.P(0.035), 5));
            }
            var sv = new ScrollViewer { Content = list, MaxHeight = 230, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            var col = V.VLead(8, V.T("Cell Version Time-Travel", 12, FontWeights.SemiBold, t.Primary), V.Self(V.Line(t.Separator, true), Cross.Stretch), V.Self(sv, Cross.Stretch));
            col.Align = Cross.Stretch;
            pop = NbPop.Show(anchor, V.Box(col, V.P(12), null, 0), 315);
        }

        // ── CellInlineDiffBanner ─────────────────────────────────────────────
        bool _hideDiff;
        UIElement DiffBanner()
        {
            var t = T;
            string oldCode = Cell.PendingDiffOld, newCode = Cell.Content;
            var head = V.H(6, Sym.Icon("sparkles", 10, t.Accent), V.T(Cell.PendingDiffSource + " modified this cell", 10.5, FontWeights.SemiBold, t.Primary),
                V.Button(V.T(_hideDiff ? "View Diff" : "Hide Diff", 9.5, FontWeights.Medium, t.Secondary), () => { _hideDiff = !_hideDiff; Rebuild(); }), V.Sp(),
                V.Button(V.Size(V.Box(V.H(3, Sym.Icon("arrow.uturn.backward", 9, t.SysRed), V.T("Revert", 10, FontWeights.Medium, t.SysRed)), V.P(7, 0), NbColor.Alpha(t.SysRed, 0.12), 4), double.NaN, 19), () => { Cell.Content = oldCode; Cell.PendingDiffOld = null; _nb.RefreshEditor(Cell); _nb.SaveSoon(); }),
                V.Button(V.Size(V.Box(V.H(3, Sym.Icon("checkmark", 9, t.SysGreen, FontWeights.Bold), V.T("Accept", 10, FontWeights.SemiBold, t.SysGreen)), V.P(7, 0), NbColor.Alpha(t.SysGreen, 0.14), 4), double.NaN, 19), () => { Cell.PendingDiffOld = null; _nb.SaveSoon(); Rebuild(); }));
            var col = V.VLead(4, V.Self(head, Cross.Stretch)); col.Align = Cross.Stretch;
            if (!_hideDiff)
            {
                var oldLines = oldCode.Replace("\r\n", "\n").Split('\n'); var newLines = newCode.Replace("\r\n", "\n").Split('\n');
                var oldSet = new HashSet<string>(oldLines); var newSet = new HashSet<string>(newLines);
                var diff = new List<Tuple<bool, string>>();
                foreach (var l in oldLines) { if (!newSet.Contains(l) && l.Trim().Length > 0) { diff.Add(Tuple.Create(false, "- " + l)); if (diff.Count >= 14) break; } }
                foreach (var l in newLines) { if (!oldSet.Contains(l) && l.Trim().Length > 0) { diff.Add(Tuple.Create(true, "+ " + l)); if (diff.Count >= 28) break; } }
                foreach (var d in diff)
                {
                    var c = d.Item1 ? t.SysGreen : t.SysRed;
                    col.Children.Add(V.Box(V.Mono(d.Item2, 10.5, FontWeights.Normal, c), V.P(6, 1), NbColor.Alpha(c, 0.08), 3));
                }
            }
            var box = V.Box(col, V.P(9, 6), t.P(Dark ? 0.05 : 0.032), 6, t.A(0.28), 0.8);
            box.Margin = new Thickness(8, 0, 8, 4);
            return box;
        }

        // ── CellParamWidgetsBar ──────────────────────────────────────────────
        UIElement ParamBar(List<CellParam> specs)
        {
            var t = T;
            var col = V.VLead(5); col.Align = Cross.Stretch;
            bool py = Cell.Language == "Python";
            foreach (var sp in specs)
            {
                var spec = sp;
                var name = V.Mono(spec.Name, 11, FontWeights.SemiBold, t.Primary); name.MinWidth = 95;
                var row = V.H(8, Sym.Icon("slider.horizontal.3", 9.5, t.Accent), name);
                switch (spec.Kind)
                {
                    case CellParam.Kinds.SliderDouble:
                    case CellParam.Kinds.SliderInt:
                        {
                            bool isInt = spec.Kind == CellParam.Kinds.SliderInt;
                            var s = new Slider { Minimum = spec.Min, Maximum = spec.Max, Value = spec.DoubleValue, Width = 190, VerticalAlignment = VerticalAlignment.Center, Style = SliderStyle(), Focusable = true };
                            bool user = false;
                            s.PreviewMouseLeftButtonDown += delegate { user = true; };
                            s.PreviewKeyDown += delegate { user = true; };
                            var val = V.Mono(spec.StringValue, 10.5, FontWeights.Medium, t.Accent); val.Width = 58; val.TextAlignment = TextAlignment.Right;
                            string lastLiteral = spec.StringValue;
                            s.ValueChanged += (o, e) =>
                            {
                                if (!user) return;
                                double v = e.NewValue;
                                string lit = isInt ? ((int)(Math.Round(v / Math.Max(1, spec.Step)) * Math.Max(1, spec.Step))).ToString(CultureInfo.InvariantCulture)
                                                   : CellParams.FormatDouble(Math.Min(Math.Max(Math.Round((v - spec.Min) / spec.Step) * spec.Step + spec.Min, spec.Min), spec.Max), spec.Step);
                                if (lit == lastLiteral) return;
                                lastLiteral = lit; val.Text = lit;
                                Cell.Content = CellParams.Update(Cell.Content, spec, lit);
                                SyncEditorText();
                            };
                            s.PreviewMouseLeftButtonUp += delegate { _nb.SaveSoon(); _nb.RunCell(Cell); };
                            row.Children.Add(s); row.Children.Add(val);
                            break;
                        }
                    case CellParam.Kinds.Dropdown:
                        foreach (var o in spec.Options.Take(5))
                        {
                            var opt = o; bool sel = spec.StringValue == o;
                            row.Children.Add(V.Button(V.Box(V.T(o, 10, sel ? FontWeights.SemiBold : FontWeights.Normal, sel ? Brushes.White : (Brush)t.P(0.85)), V.P(7, 2.5), sel ? t.Accent : t.P(0.06), 4), () => Mutate(spec, "\"" + opt + "\"", true)));
                        }
                        break;
                    case CellParam.Kinds.Toggle:
                        row.Children.Add(V.Button(V.H(4, Sym.Icon(spec.BoolValue ? "checkmark.square.fill" : "square", 11, spec.BoolValue ? t.SysGreen : t.Secondary), V.T(spec.BoolValue ? "Enabled" : "Disabled", 10.5, FontWeights.Medium, t.Primary)),
                            () => { bool next = !spec.BoolValue; Mutate(spec, py ? (next ? "True" : "False") : (next ? "true" : "false"), true); }));
                        break;
                    default:
                        {
                            var tb = Styles.PlainField(spec.Name, 11, t.Primary);
                            tb.FontFamily = UIFonts.Mono; tb.Text = spec.StringValue;
                            tb.KeyDown += (o, e) => { if (e.Key == Key.Enter) { Mutate(spec, "\"" + tb.Text + "\"", true); e.Handled = true; } };
                            var b = V.Box(tb, V.P(6, 2.5), t.P(0.06), 4); b.MaxWidth = 180; b.MinWidth = 120;
                            row.Children.Add(b);
                            break;
                        }
                }
                col.Children.Add(row);
            }
            var box = V.Box(col, V.P(10, 6), t.A(Dark ? 0.065 : 0.045), 6);
            box.Margin = new Thickness(8, 0, 8, 4);
            return box;
        }

        static Style _slider;
        /// <summary>.controlSize(.small) macOS slider: thin track filled with the accent colour up to a round knob.</summary>
        static Style SliderStyle()
        {
            if (_slider != null) return _slider;
            var t = Theme.Current;
            string accent = t.AccentColor.ToString(), track = Theme.WithAlpha(t.PrimaryColor, t.IsDark ? 0.18 : 0.14).ToString();
            _slider = (Style)System.Windows.Markup.XamlReader.Parse(@"<Style TargetType='Slider' xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>
  <Setter Property='FocusVisualStyle' Value='{x:Null}'/>
  <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='Slider'>
    <Grid Height='18' Background='Transparent'>
      <Border Height='3' CornerRadius='1.5' Background='" + track + @"' VerticalAlignment='Center'/>
      <Track x:Name='PART_Track'>
        <Track.DecreaseRepeatButton><RepeatButton Command='Slider.DecreaseLarge' Focusable='False'><RepeatButton.Template><ControlTemplate TargetType='RepeatButton'><Border Height='3' CornerRadius='1.5' Background='" + accent + @"'/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.DecreaseRepeatButton>
        <Track.IncreaseRepeatButton><RepeatButton Command='Slider.IncreaseLarge' Focusable='False'><RepeatButton.Template><ControlTemplate TargetType='RepeatButton'><Border Background='Transparent'/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.IncreaseRepeatButton>
        <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType='Thumb'><Ellipse Width='14' Height='14' Fill='White' Stroke='#33000000' StrokeThickness='0.5'><Ellipse.Effect><DropShadowEffect BlurRadius='3' ShadowDepth='0.6' Opacity='0.35'/></Ellipse.Effect></Ellipse></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
      </Track>
    </Grid>
  </ControlTemplate></Setter.Value></Setter></Style>");
            return _slider;
        }

        void Mutate(CellParam spec, string literal, bool run)
        {
            Cell.Content = CellParams.Update(Cell.Content, spec, literal);
            _nb.RefreshEditor(Cell);
            _nb.SaveSoon();
            if (run) _nb.RunCell(Cell);
        }

        void SyncEditorText()
        {
            CodeEditorView ed;
            if (_nb.Editors.TryGetValue(Cell.Id, out ed) && ed.Box.Text != Cell.Content)
            {
                int caret = ed.Box.CaretIndex;
                ed.Box.Text = Cell.Content;
                ed.Box.CaretIndex = Math.Min(caret, ed.Box.Text.Length);
            }
        }

        // ── code editor (SyntaxHighlightedCodeView: transparent, no inner scrolling, deterministic height) ──
        UIElement Editor()
        {
            CodeEditorView ed;
            string key = Cell.Type == "Raw" ? "plaintext" : Cell.Lang.EditorKey;
            if (!_nb.Editors.TryGetValue(Cell.Id, out ed))
            {
                ed = new CodeEditorView(Cell.Content, key, Defaults.Num("cellFontSize", 13), UIFonts.Code("cellFontName", "SF Mono"));
                ed.Transparent = true;
                var cell = Cell; var nb = _nb; var edRef = ed;
                ed.TextEdited += text => { cell.Content = text; nb.SaveSoon(); FitEditor(edRef); };
                ed.Box.GotKeyboardFocus += delegate { nb.Select(cell); };
                ed.PreviewMouseWheel += (s, e) =>
                {
                    // the cell list scrolls, not the editor (isScrollEnabled: false)
                    if (Keyboard.Modifiers != ModifierKeys.None) return;
                    e.Handled = true;
                    nb.Scroll.RaiseEvent(new MouseWheelEventArgs(e.MouseDevice, e.Timestamp, e.Delta) { RoutedEvent = UIElement.MouseWheelEvent, Source = s });
                };
                _nb.Editors[Cell.Id] = ed;
            }
            if (ed.Parent is Decorator) ((Decorator)ed.Parent).Child = null;
            FitEditor(ed);
            return new Border { Child = ed, CornerRadius = new CornerRadius(4), Margin = new Thickness(4), ClipToBounds = true };
        }

        static void FitEditor(CodeEditorView ed)
        {
            int lines = Math.Max(1, ed.LineCount);
            double lh = Math.Max(16, ed.LineHeightPx);
            double longest = ed.LongestLineWidth;
            double extra = longest > ed.ActualWidth - 60 && ed.ActualWidth > 0 ? 14 : 0;
            ed.Height = Math.Max(92, Math.Ceiling(lines * lh) + 28 + extra);
        }

        // ── RichMarkdownCellView ─────────────────────────────────────────────
        UIElement RichMarkdown(bool renderedOnly)
        {
            var t = T;
            var col = V.VLead(6); col.Align = Cross.Stretch;
            if (_mdEditing && !renderedOnly)
            {
                var done = V.Button(V.Size(V.Box(V.H(3, Sym.Icon("checkmark", 9, t.SysGreen, FontWeights.Bold), V.T("Render Preview", 10, FontWeights.SemiBold, t.SysGreen)), V.P(8, 0), NbColor.Alpha(t.SysGreen, 0.14), 4), double.NaN, 20), () => { _mdEditing = false; Rebuild(); });
                col.Children.Add(V.Self(V.H(6, V.T("Editing Markdown & LaTeX Math ($...$ / $$...$$)", 10.5, FontWeights.Medium, t.Secondary), V.Sp(), done), Cross.Stretch));
                var tb = new TextBox
                {
                    Text = Cell.Content, AcceptsReturn = true, AcceptsTab = true, TextWrapping = TextWrapping.Wrap, FontFamily = UIFonts.Mono, FontSize = 13,
                    Foreground = t.Primary, Background = Brushes.Transparent, BorderThickness = new Thickness(0), CaretBrush = t.Primary,
                    MinHeight = 132 - 16, MaxHeight = 420 - 16, VerticalScrollBarVisibility = ScrollBarVisibility.Auto
                };
                tb.TextChanged += delegate { Cell.Content = tb.Text; _nb.SaveSoon(); };
                tb.GotKeyboardFocus += delegate { _nb.Select(Cell); };
                col.Children.Add(V.Box(tb, V.P(8), t.P(Dark ? 0.045 : 0.03), 6));
                Dispatcher.BeginInvoke(new Action(() => tb.Focus()), DispatcherPriority.Input);
            }
            else
            {
                var g = new Grid();
                string trimmed = (Cell.Content ?? "").Trim();
                UIElement body;
                if (trimmed.Length == 0)
                {
                    var ph = V.Wrap(V.T("Double-click to write Markdown, LaTeX math ($...$ / $$...$$), tables, or {{ variable }} templates\u2026", 12.5, FontWeights.Normal, t.S(0.75)), TextAlignment.Left);
                    ph.MinHeight = 44;
                    body = ph;
                }
                else body = MarkdownView.Render(ResolveVariables(Cell.Content), 13, NbStore.WorkingDirectory);
                var holder = new Border { Child = body, Background = Brushes.Transparent, Margin = new Thickness(0, 0, renderedOnly ? 0 : 44, 0) };
                if (!renderedOnly) holder.MouseLeftButtonDown += (s, e) => { if (e.ClickCount == 2) { _mdEditing = true; Rebuild(); e.Handled = true; } };
                g.Children.Add(holder);
                if (!renderedOnly)
                {
                    var edit = V.Button(V.Size(V.Box(V.H(3, Sym.Icon("pencil", 9, t.Secondary), V.T("Edit", 9.5, FontWeights.Medium, t.Secondary)), V.P(6, 0), t.P(Dark ? 0.06 : 0.04), 4), double.NaN, 19), () => { _mdEditing = true; Rebuild(); });
                    edit.HorizontalAlignment = HorizontalAlignment.Right; edit.VerticalAlignment = VerticalAlignment.Top;
                    g.Children.Add(edit);
                }
                col.Children.Add(g);
            }
            return V.Box(col, V.P(12, 8), null, 0);
        }

        string ResolveVariables(string raw)
        {
            if (!raw.Contains("{{")) return raw;
            string o = raw;
            foreach (var v in _nb.Kernel.Variables)
            {
                string val = (v.Preview ?? "").Split('\n')[0];
                o = o.Replace("{{" + v.Name + "}}", val).Replace("{{ " + v.Name + " }}", val);
            }
            return o;
        }

        // ── outputs (cellRichOutputsContent) ─────────────────────────────────
        UIElement Outputs()
        {
            var t = T;
            double w = RichW;
            var col = V.VLead(8); col.Align = Cross.Stretch; col.Width = w;
            if (Cell.DataFrame != null) col.Children.Add(new DataGridStudio(Cell.DataFrame, code => { var nc = _nb.AddCell("Code", "Python"); nc.Content = code; _nb.RefreshEditor(nc); _nb.RunCell(nc); }));
            string output = Cell.Output ?? "";
            if (output.Length > 0)
            {
                bool hasError = output.Contains("Error") || output.Contains("Traceback") || output.Contains("Exception") || output.Contains("CUDA out of memory");
                if (hasError && !_nb.AppMode && !Cell.IsExecuting) col.Children.Add(SelfHealingBanner());
                col.Children.Add(new OutputLog(output, hasError));
            }
            foreach (var f in Cell.Images)
            {
                string ext = System.IO.Path.GetExtension(f).ToLowerInvariant();
                if (!File.Exists(f)) continue;
                if (ext == ".pdf") col.Children.Add(new PdfCard(f));
                else if (ext == ".md" || ext == ".markdown" || ext == ".tex") col.Children.Add(MarkdownCard(f));
                else if (ext == ".html" || ext == ".htm" || ext == ".svg") col.Children.Add(HtmlCard(f));
                else col.Children.Add(new GraphCard(f, w));
            }
            return col;
        }

        // ── CellSelfHealingBanner ────────────────────────────────────────────
        UIElement SelfHealingBanner()
        {
            var t = T;
            var row = V.H(6, V.H(4, Sym.Icon("exclamationmark.triangle", 11, t.SysOrange), V.T("Error", 11, FontWeights.Medium, t.Primary)));
            if (_fixing) row.Children.Add(V.H(4, new ThreeDots(), V.Shrink(V.T(_fixStatus, 10, FontWeights.Normal, t.Secondary))));
            row.Children.Add(V.Sp(4));
            var fix = V.Button(V.Box(V.H(3.5, Sym.Icon("bolt.badge.automatic.fill", 10, t.Primary), V.T("Auto-Fix", 10, FontWeights.SemiBold, t.Primary)), V.P(7.5, 3.5), t.P(0.09), 4.5, t.P(0.14), 0.8), AutoFix);
            fix.ToolTip = "MicroCode AI Agent repairs and re-runs this cell automatically"; fix.IsEnabled = !_fixing;
            var ask = V.Button(V.Box(V.H(3, Sym.Icon("bubble.left.and.bubble.right", 9, t.Secondary), V.T("Ask", 10, FontWeights.Medium, t.Secondary)), V.P(6.5, 3.5), t.P(0.06), 4.5), AskAgent);
            ask.ToolTip = "Switch to MicroCode AI Agent to interactively debug and fix this error"; ask.IsEnabled = !_fixing;
            var copyIcon = Sym.Icon("doc.on.doc", 9.5, t.Secondary);
            var copy = V.Button(V.Box(copyIcon, V.P(6, 4), t.P(0.06), 4.5), () =>
            {
                try { Clipboard.SetText(Cell.Output ?? ""); copyIcon.SetBrush(t.SysGreen); } catch (Exception ex) { Debug.WriteLine("copy traceback: " + ex.Message); }
            });
            copy.ToolTip = "Copy Error Traceback";
            row.Children.Add(fix); row.Children.Add(ask); row.Children.Add(copy);
            return V.Box(row, V.P(8, 4), t.P(0.04), 6, t.P(0.12), 1);
        }

        void AutoFix()
        {
            _fixing = true; _fixStatus = "Agent analyzing traceback...";
            RefreshOutputs();
            string lang = Cell.Language, fence = lang.ToLowerInvariant();
            string prompt = "You are the MicroCode Autonomous AI Agent.\nThe following " + lang + " notebook cell failed with an execution error.\n\nLANGUAGE: " + lang + "\nCODE:\n```" + fence + "\n" + Cell.Content + "\n```\n\nTRACEBACK:\n```\n" + Cell.Output + "\n```\n\nAnalyze the exact failure (syntax, missing import, compiler flags, or logic).\nRepair the code completely.\nOutput ONLY the corrected runnable code inside a single ```" + fence + " ... ``` block.\nDo NOT write explanations or conversation.";
            var cell = Cell; var nb = _nb;
            NbAgent.Ask("self-heal-" + cell.Id, prompt, "bug_hunter", s => { if (s.Length > 0) { _fixStatus = s; RefreshOutputs(); } }, (text, err) =>
            {
                _fixing = false;
                if (err != null) { cell.Output = (cell.Output ?? "") + "\n\u26A0\uFE0F [Agent Self-Healing] Repair error: " + err + "\n"; nb.SaveSoon(); Rebuild(); return; }
                string fixedCode = ExtractCode(text);
                if (fixedCode.Trim().Length == 0) { Rebuild(); return; }
                cell.RecordAgentEditBaseline(cell.Content, "Agent Auto-Fix");
                cell.Content = fixedCode;
                cell.Output = (cell.Output ?? "") + "\n\u26A1 [Agent Self-Healing] Code patched. Re-executing now...\n";
                nb.RefreshEditor(cell);
                nb.SaveSoon();
                nb.RunCell(cell);
            });
        }

        internal static string ExtractCode(string response)
        {
            string s = (response ?? "").Trim();
            if (!s.Contains("```")) return s;
            var lines = s.Replace("\r\n", "\n").Split('\n');
            var code = new List<string>(); bool inside = false;
            foreach (var l in lines)
            {
                if (l.Trim().StartsWith("```")) { inside = !inside; continue; }
                if (inside) code.Add(l);
            }
            return code.Count > 0 ? string.Join("\n", code) : s;
        }

        void AskAgent()
        {
            string lang = Cell.Language;
            string inquiry = "Please analyze and fix this " + lang + " notebook cell error:\n\nCODE:\n```" + lang.ToLowerInvariant() + "\n" + Cell.Content + "\n```\n\nERROR TRACEBACK:\n```\n" + Cell.Output + "\n```";
            try { Clipboard.SetText(inquiry); } catch (Exception ex) { Debug.WriteLine("clipboard: " + ex.Message); }
            _nb.App.Notify("agent:send:" + inquiry);
        }

        // ── CellInlineMarkdownPreviewCard ────────────────────────────────────
        UIElement MarkdownCard(string path)
        {
            var t = T;
            string name = System.IO.Path.GetFileName(path);
            bool tex = path.EndsWith(".tex", StringComparison.OrdinalIgnoreCase);
            bool auto = name.StartsWith("cell_") && (name.Contains("_rich") || tex);
            string raw = "";
            try { raw = File.ReadAllText(path); } catch (Exception ex) { raw = "Could not read " + name + ": " + ex.Message; }
            bool showSource = false;
            var body = new Border { Padding = new Thickness(12) };
            Action render = null;
            var toggleText = V.T("Source", 10, FontWeights.Medium, t.Secondary);
            render = () =>
            {
                if (showSource) { var tb = new TextBox { Text = raw, IsReadOnly = true, FontFamily = UIFonts.Mono, FontSize = 12, Foreground = t.Secondary, Background = Brushes.Transparent, BorderThickness = new Thickness(0), TextWrapping = TextWrapping.Wrap }; body.Child = tb; }
                else body.Child = MarkdownView.Render(NormalizeTex(raw, tex), 13, System.IO.Path.GetDirectoryName(path));
                toggleText.Text = showSource ? "Rendered Preview" : "Source";
                toggleText.Foreground = showSource ? t.Accent : t.Secondary;
            };
            var toggle = V.Button(V.Box(toggleText, V.P(7, 2.5), t.P(0.06), 4), () => { showSource = !showSource; render(); });
            var copyIcon = Sym.Icon("doc.on.doc", 9.5, t.Secondary);
            var copy = V.Button(V.Box(copyIcon, V.P(4), t.P(0.06), 4), () => { try { Clipboard.SetText(raw); copyIcon.SetBrush(t.SysGreen); } catch (Exception ex) { Debug.WriteLine("copy: " + ex.Message); } });
            var head = V.H(8, Sym.Icon(tex ? "function" : "doc.text.magnifyingglass", 10.5, t.Accent, FontWeights.SemiBold), V.Shrink(V.T(auto ? (tex ? "LaTeX Preview" : "Markdown & TeX Preview") : name, 11, FontWeights.SemiBold, t.Primary)), V.Sp(), toggle, copy);
            if (!auto) head.Children.Add(V.Button(V.Box(Sym.Icon("arrow.up.right.square", 10, t.Secondary), V.P(4), t.P(0.06), 4), () => PreviewDock.OpenFile(path)));
            render();
            return OutputCardFrame(head, body);
        }

        internal static string NormalizeTex(string src, bool tex)
        {
            if (!tex) return src;
            int a = src.IndexOf("\\begin{document}", StringComparison.Ordinal);
            if (a >= 0) src = src.Substring(a + "\\begin{document}".Length);
            int b = src.IndexOf("\\end{document}", StringComparison.Ordinal);
            if (b >= 0) src = src.Substring(0, b);
            src = Regex.Replace(src, @"\\section\*?\{([^}]*)\}", "## $1");
            src = Regex.Replace(src, @"\\subsection\*?\{([^}]*)\}", "### $1");
            src = Regex.Replace(src, @"\\subsubsection\*?\{([^}]*)\}", "#### $1");
            src = Regex.Replace(src, @"\\textbf\{([^}]*)\}", "**$1**");
            src = Regex.Replace(src, @"\\textit\{([^}]*)\}", "*$1*");
            // equation environments → display math for the native TeX renderer
            src = Regex.Replace(src, @"\\begin\{(equation\*?|align\*?)\}([\s\S]*?)\\end\{\1\}", m => "\n$$" + m.Groups[2].Value.Trim() + "$$\n");
            return src;
        }

        // ── CellInlineHTMLPreviewCard: WebView2 cannot live inside a scrolling list (airspace), so the page opens in the Preview dock ──
        UIElement HtmlCard(string path)
        {
            var t = T;
            string name = System.IO.Path.GetFileName(path);
            bool auto = name.StartsWith("cell_") && name.Contains("_rich");
            bool svg = path.EndsWith(".svg", StringComparison.OrdinalIgnoreCase);
            var open = V.Button(V.Box(V.T("Open Preview", 10, FontWeights.Medium, t.Accent), V.P(7, 2.5), t.A(0.12), 4), () => OpenWebPreview(path));
            var browser = V.Tip(V.Button(V.Box(Sym.Icon("arrow.up.right.square", 10, t.Secondary), V.P(4), t.P(0.06), 4), () => { try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); } catch (Exception ex) { Debug.WriteLine("open html: " + ex.Message); } }), "Open in Browser");
            var head = V.H(8, Sym.Icon(svg ? "photo" : "globe", 11, t.SysBlue), V.Shrink(V.T(auto ? "Interactive Plot / HTML Output" : name, 11, FontWeights.SemiBold, t.Primary)), V.Sp(), open, browser);
            long size = 0; try { size = new FileInfo(path).Length; } catch (IOException) { }
            var info = V.H(8, Sym.Icon("play.rectangle", 14, t.Secondary), V.Flex(V.VLead(2, V.T(name, 12, FontWeights.Medium, t.Primary), V.T(NbFmt.Bytes(size) + " \u00B7 renders in the WebApp Preview tab", 10.5, FontWeights.Normal, t.Secondary))));
            var body = new Border { Padding = new Thickness(12), Child = info, Cursor = Cursors.Hand, Background = Brushes.Transparent };
            body.MouseLeftButtonUp += delegate { OpenWebPreview(path); };
            return OutputCardFrame(head, body);
        }

        void OpenWebPreview(string path)
        {
            try { WebAppPreview.OpenInDock(path); }
            catch (Exception ex) { Debug.WriteLine("web preview: " + ex.Message); PreviewDock.OpenFile(path); }
        }

        internal static Border OutputCardFrame(UIElement head, UIElement body)
        {
            var t = Theme.Current; bool d = t.IsDark;
            var col = V.VLead(0); col.Align = Cross.Stretch;
            col.Children.Add(V.Box(head, V.P(10, 6), t.P(d ? 0.045 : 0.03), 0));
            var line = V.Line(t.Separator, true); line.Opacity = 0.5; col.Children.Add(line);
            col.Children.Add(body);
            var frame = V.Box(col, V.P(0), t.P(d ? 0.025 : 0.015), 8, t.P(d ? 0.11 : 0.09), 1);
            frame.ClipToBounds = true;
            return frame;
        }

        // ── dedicated inline Agent cell (clean composer + send) ──────────────
        void BuildAgentCard()
        {
            var t = T;
            var col = V.VLead(0); col.Align = Cross.Stretch;
            bool canSend = (Cell.Content ?? "").Trim().Length > 0;
            if (!Cell.Collapsed)
            {
                var input = NbAgentUI.PromptBox(Cell.AgentMode ? "สั่ง Agent ให้สร้าง แก้ไข หรือรัน Cell… (กด Enter เพื่อส่ง, Shift+Enter ขึ้นบรรทัดใหม่)" : "พิมพ์คำถามหรือให้ AI สร้างโค้ด… (กด Enter เพื่อส่ง)",
                    Cell.Content, 36, 160, 12.5, text => { Cell.Content = text; _nb.SaveSoon(); }, () =>
                    {
                        _nb.Select(Cell);
                        if (!Cell.IsExecuting && (Cell.Content ?? "").Trim().Length > 0) _nb.RunCell(Cell);
                    });
                input.GotKeyboardFocus += delegate { _nb.Select(Cell); };
                input.Margin = new Thickness(12, 10, 12, 6);
                col.Children.Add(input);
            }
            var bar = V.H(6, NbAgentUI.ModeToggle(() => Cell.AgentMode, v => { Cell.AgentMode = v; _nb.SaveSoon(); Rebuild(); }, true),
                NbAgentUI.ModelPill(_nb.App, 230, true, true, Cell.AgentMode ? new Func<string>(() => Cell.AiRole) : null, v => { Cell.AiRole = v; _nb.SaveSoon(); Rebuild(); }, true));
            if (Cell.Collapsed && canSend) bar.Children.Add(V.Shrink(V.T(Cell.Content.Replace("\n", " "), 11.5, FontWeights.Normal, t.Secondary)));
            bar.Children.Add(V.Sp(6));
            var acts = V.H(5,
                V.Tip(V.Size(V.Button(Sym.Icon("arrow.up", 10.5, t.Secondary, FontWeights.Medium), () => _nb.MoveCell(Cell, -1)), 20, 20), "Move Cell Up"),
                V.Tip(V.Size(V.Button(Sym.Icon("arrow.down", 10.5, t.Secondary, FontWeights.Medium), () => _nb.MoveCell(Cell, 1)), 20, 20), "Move Cell Down"),
                V.Tip(V.Size(V.Button(Sym.Icon(Cell.Collapsed ? "chevron.down" : "chevron.up", 10.5, t.Secondary, FontWeights.Medium), () => { Cell.Collapsed = !Cell.Collapsed; _nb.SaveSoon(); Rebuild(); }), 20, 20), Cell.Collapsed ? "Expand Cell" : "Collapse Cell"),
                V.Tip(V.Size(V.Button(Sym.Icon("trash", 10.5, t.Secondary, FontWeights.Medium), () => _nb.DeleteCell(Cell)), 20, 20), "Delete Cell"));
            _hoverOnly.Add(acts);
            bar.Children.Add(acts);
            bar.Children.Add(NbAgentUI.SendButton(Cell.IsExecuting, canSend, Cell.AgentMode, () => { _nb.Select(Cell); _nb.RunCell(Cell); }));
            col.Children.Add(V.Box(bar, new Thickness(12, Cell.Collapsed ? 8 : 7, 12, Cell.Collapsed ? 8 : 7), null, 0));

            bool activity = Cell.IsExecuting || Cell.AgentThought.Length > 0 || Cell.AgentSteps.Count > 0 || Cell.AgentStatus.Length > 0 || (Cell.Output ?? "").Trim().Length > 0;
            if (!Cell.Collapsed && activity)
            {
                var line = V.Line(t.Separator, true); line.Opacity = 0.55; line.Margin = new Thickness(12, 0, 12, 0);
                col.Children.Add(line);
                var act = V.VLead(8); act.Align = Cross.Stretch;
                if (Cell.IsExecuting) act.Children.Add(V.H(7, new ThreeDots(), V.Shrink(V.Mono(Cell.AgentStatus.Length == 0 ? "Working\u2026" : Cell.AgentStatus, 11, FontWeights.Normal, t.Secondary))));
                if (Cell.AgentThought.Length > 0) act.Children.Add(NbAgentUI.Thought(Cell.AgentThought));
                if (Cell.AgentSteps.Count > 0) act.Children.Add(NbAgentUI.Timeline(Cell.AgentSteps));
                if ((Cell.Output ?? "").Trim().Length > 0) act.Children.Add(NbAgentUI.RichContent(Cell.Output, false, RichW));
                col.Children.Add(V.Box(act, V.P(14, 10), null, 0));
            }
            Frame(col, 10);
        }

        // ── executiveAppModeCellCard ─────────────────────────────────────────
        void BuildAppMode()
        {
            if (Cell.Type == "Markdown")
            {
                var md = RichMarkdown(true);
                ((FrameworkElement)md).Margin = new Thickness(0, 4, 0, 4);
                Frame(md, 10);
                return;
            }
            var specs = Cell.IsCode ? CellParams.Parse(Cell.Content) : new List<CellParam>();
            bool visual = specs.Count > 0 || Cell.DataFrame != null || Cell.Images.Count > 0 || (Cell.Output ?? "").Trim().Length > 0;
            if (!visual || Cell.IsAgent) { Child = null; Visibility = Visibility.Collapsed; Margin = new Thickness(0); return; }
            var col = V.VLead(8); col.Align = Cross.Stretch;
            if (specs.Count > 0) { var bar = ParamBar(specs); ((FrameworkElement)bar).Margin = new Thickness(8, 8, 8, 4); col.Children.Add(bar); }
            _outputsHost = new Border { Padding = new Thickness(10, 8, 10, 8), Child = Outputs() };
            col.Children.Add(_outputsHost);
            Frame(col, 10);
        }
    }

    /// <summary>VirtualizedCellOutputLogView: monospaced log, red on errors, head+tail window for huge output, MD/TeX preview toggle.</summary>
    internal class OutputLog : Border
    {
        const int Window = 28000;
        readonly string _output;
        readonly bool _error;
        bool _full, _rendered;

        public OutputLog(string output, bool hasError) { _output = output; _error = hasError; Build(); }

        bool LooksLikeMarkdown
        {
            get
            {
                if (_error) return false;
                string o = _output;
                return o.Contains("$$") || o.Contains("\\(") || o.Contains("\\text{") || o.Contains("\\frac{") || o.Contains("\n# ") || o.Contains("\n## ") || o.StartsWith("# ") || o.StartsWith("## ") || o.Contains("|---|") || o.Contains("| ---");
            }
        }

        void Build()
        {
            var t = Theme.Current;
            bool truncated = !_full && _output.Length > Window;
            string display = truncated ? _output.Substring(0, 8000) + "\n\n\u22EF [" + (_output.Length - 24000) + " characters hidden for responsiveness] \u22EF\n\n" + _output.Substring(_output.Length - 16000) : _output;
            var col = V.VLead(5); col.Align = Cross.Stretch;
            if (LooksLikeMarkdown)
            {
                var b = V.Button(V.Box(V.H(3.5, Sym.Icon(_rendered ? "terminal" : "function", 9.5, _rendered ? t.Accent : t.Secondary, FontWeights.SemiBold), V.T(_rendered ? "Raw Console" : "MD / TeX Preview", 10, FontWeights.Medium, _rendered ? t.Accent : t.Secondary)), V.P(7, 2.5), _rendered ? t.A(0.08) : t.P(0.08), 4), () => { _rendered = !_rendered; Build(); });
                col.Children.Add(V.H(8, b));
            }
            if (_rendered) col.Children.Add(MarkdownView.Render(display, 13, NbStore.WorkingDirectory));
            else
            {
                var tb = new TextBox
                {
                    Text = display, IsReadOnly = true, BorderThickness = new Thickness(0), Background = Brushes.Transparent, Foreground = _error ? (Brush)t.SysRed : t.Primary,
                    FontFamily = UIFonts.Mono, FontSize = 12, TextWrapping = TextWrapping.Wrap, CaretBrush = Brushes.Transparent, Padding = new Thickness(0), Focusable = true
                };
                tb.PreviewMouseWheel += (s, e) => { var sv = FindScroll(tb); if (sv == null) return; e.Handled = true; sv.RaiseEvent(new MouseWheelEventArgs(e.MouseDevice, e.Timestamp, e.Delta) { RoutedEvent = UIElement.MouseWheelEvent, Source = s }); };
                col.Children.Add(tb);
            }
            if (_output.Length > Window)
            {
                var more = V.Button(V.T(_full ? "Compact Log Window" : "Show Full Output (" + NbFmt.Bytes(Encoding.UTF8.GetByteCount(_output)) + ")", 10, FontWeights.Medium, t.Accent), () => { _full = !_full; Build(); });
                var save = V.Button(V.T("Save Log\u2026", 10, FontWeights.Medium, t.Secondary), () =>
                {
                    var dlg = new Microsoft.Win32.SaveFileDialog { FileName = "cell_output.log", Filter = "Log (*.log)|*.log|Text (*.txt)|*.txt" };
                    if (dlg.ShowDialog() == true) { try { File.WriteAllText(dlg.FileName, _output); } catch (Exception ex) { MessageBox.Show(ex.Message, "Save Log", MessageBoxButton.OK, MessageBoxImage.Warning); } }
                });
                col.Children.Add(V.H(8, more, save));
            }
            Child = col;
        }

        static ScrollViewer FindScroll(DependencyObject d)
        {
            var p = VisualTreeHelper.GetParent(d);
            while (p != null) { var sv = p as ScrollViewer; if (sv != null && !(sv.TemplatedParent is TextBox)) return sv; p = VisualTreeHelper.GetParent(p); }
            return null;
        }
    }

    /// <summary>CellInlineGraphImageCard: header (Plot Output, size, Zoom, expand, Copy, Save As, Open) + fitted image.</summary>
    internal class GraphCard : Border
    {
        readonly string _path;
        readonly double _maxW;
        bool _expanded;

        public GraphCard(string path, double maxW) { _path = path; _maxW = maxW; Build(); }

        static BitmapSource Load(string path)
        {
            try
            {
                var bmp = new BitmapImage();
                bmp.BeginInit(); bmp.CacheOption = BitmapCacheOption.OnLoad; bmp.CreateOptions = BitmapCreateOptions.IgnoreImageCache; bmp.UriSource = new Uri(path); bmp.EndInit(); bmp.Freeze();
                return bmp;
            }
            catch (Exception ex) { Debug.WriteLine("graph image: " + ex.Message); return null; }
        }

        void Build()
        {
            var t = Theme.Current; bool d = t.IsDark;
            string name = System.IO.Path.GetFileName(_path);
            bool auto = name.StartsWith("cell_") && (name.Contains("_rich") || name.Contains("_fig") || name.Contains("_rplot_"));
            bool compact = _maxW < 500;
            var img = Load(_path);
            var head = V.H(6, Sym.Icon(auto ? "chart.xyaxis.line" : "photo", 10.5, t.Accent, FontWeights.SemiBold), V.Shrink(V.T(auto ? "Plot Output" : name, 11, FontWeights.Medium, t.P(0.88))));
            if (!compact && img != null) head.Children.Add(V.Mono(img.PixelWidth + "\u00D7" + img.PixelHeight, 9.5, FontWeights.Normal, t.Secondary));
            head.Children.Add(V.Sp(4));
            Func<string, string, Action, string, Btn> btn = (icon, label, a, tip) =>
            {
                var r = V.H(3, Sym.Icon(icon, 9.5, t.Secondary));
                if (label != null && !compact) r.Children.Add(V.T(label, 10, FontWeights.Medium, t.Secondary));
                var b = V.Button(V.Box(r, label != null ? V.P(compact ? 5 : 6, 2.5) : V.P(4), t.P(0.06), 4), a);
                b.ToolTip = tip;
                return b;
            };
            if (img != null) head.Children.Add(btn("plus.magnifyingglass", "Zoom", Zoom, "Zoom Plot"));
            head.Children.Add(btn(_expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", null, () => { _expanded = !_expanded; Build(); }, _expanded ? "Fit Height" : "Expand Full Size"));
            if (img != null) head.Children.Add(btn("doc.on.doc", "Copy", () => { try { Clipboard.SetImage(img); } catch (Exception ex) { Debug.WriteLine("copy image: " + ex.Message); } }, "Copy Image"));
            head.Children.Add(btn("square.and.arrow.down", null, SaveAs, "Save As\u2026"));
            head.Children.Add(btn("arrow.up.right.square", null, () => PreviewDock.OpenFile(_path), "Open in Preview"));
            UIElement body;
            if (img != null)
            {
                double availW = Math.Max(160, _maxW - 16), maxH = _expanded ? 860 : 380;
                double scale = Math.Min(Math.Min(availW / Math.Max(1, img.Width), maxH / Math.Max(1, img.Height)), 1.0);
                var image = new Image { Source = img, Width = Math.Max(60, Math.Floor(img.Width * scale)), Height = Math.Max(48, Math.Floor(img.Height * scale)), Stretch = Stretch.Uniform, HorizontalAlignment = HorizontalAlignment.Center };
                RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
                var holder = new Border { Child = image, Padding = new Thickness(8), Background = d ? (Brush)Theme.B(Theme.WithAlpha(Colors.White, 0.02)) : Theme.B(Theme.WithAlpha(Colors.White, 0.5)) };
                holder.MouseLeftButtonDown += (s, e) => { if (e.ClickCount == 2) { Zoom(); e.Handled = true; } };
                body = holder;
            }
            else body = V.Box(V.H(8, Sym.Icon("doc.richtext", 12, t.Secondary), V.Flex(V.T(name, 12, FontWeights.Normal, t.Primary)), V.Button(V.Box(V.T("Open File", 11, FontWeights.Medium, t.Primary), V.P(8, 3), t.P(0.08), 5), () => PreviewDock.OpenFile(_path))), V.P(12), null, 0);
            Child = CellCard.OutputCardFrame(head, body);
        }

        void SaveAs()
        {
            var dlg = new Microsoft.Win32.SaveFileDialog { FileName = System.IO.Path.GetFileName(_path) };
            if (dlg.ShowDialog() != true) return;
            try { File.Copy(_path, dlg.FileName, true); } catch (Exception ex) { MessageBox.Show(ex.Message, "Save As", MessageBoxButton.OK, MessageBoxImage.Warning); }
        }

        /// <summary>CellGraphZoomLightboxSheet: a window with the plot at 25–400 %, Ctrl+wheel to zoom.</summary>
        void Zoom()
        {
            var img = Load(_path);
            if (img == null) return;
            var t = Theme.Current;
            double zoom = 1.0;
            var image = new Image { Source = img, Stretch = Stretch.Uniform };
            RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
            var sv = new ScrollViewer { Content = image, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Background = Brushes.White };
            var label = V.Mono("100%", 11, FontWeights.Medium, t.Secondary);
            Action apply = () => { image.Width = img.Width * zoom; image.Height = img.Height * zoom; label.Text = (int)Math.Round(zoom * 100) + "%"; };
            apply();
            var bar = V.H(8, V.T(System.IO.Path.GetFileName(_path), 12, FontWeights.SemiBold, t.Primary), V.Sp(),
                V.Button(Sym.Icon("minus.magnifyingglass", 12, t.Primary), () => { zoom = Math.Max(0.25, zoom / 1.25); apply(); }), label,
                V.Button(Sym.Icon("plus.magnifyingglass", 12, t.Primary), () => { zoom = Math.Min(4, zoom * 1.25); apply(); }));
            var root = new DockPanel { Background = t.PanelBackground };
            var top = V.Box(bar, V.P(12, 8), t.PanelBackground, 0); DockPanel.SetDock(top, Dock.Top);
            root.Children.Add(top); root.Children.Add(sv);
            sv.PreviewMouseWheel += (s, e) => { if (Keyboard.Modifiers == ModifierKeys.Control) { zoom = e.Delta > 0 ? Math.Min(4, zoom * 1.1) : Math.Max(0.25, zoom / 1.1); apply(); e.Handled = true; } };
            var w = new Window { Title = "Plot", Content = root, Width = Math.Min(1200, img.Width + 60), Height = Math.Min(900, img.Height + 110), WindowStartupLocation = WindowStartupLocation.CenterOwner, Owner = Application.Current.MainWindow, Background = t.PanelBackground };
            w.Show();
        }
    }

    /// <summary>CellInlinePDFPreviewCard: page count, Continuous / Single Page, expand, Open in Preview; pages rendered by Windows.Data.Pdf.</summary>
    internal class PdfCard : Border
    {
        readonly string _path;
        bool _continuous = true, _expanded;
        int _pages, _page;
        readonly StackPanel _pagesHost = new StackPanel();

        public PdfCard(string path) { _path = path; Build(); Loaded += async delegate { try { _pages = await PdfRender.PageCount(_path); } catch (Exception ex) { Debug.WriteLine("pdf pages: " + ex.Message); } Build(); }; }

        void Build()
        {
            var t = Theme.Current;
            var head = V.H(8, Sym.Icon("doc.richtext.fill", 11, t.SysRed), V.Shrink(V.T(System.IO.Path.GetFileName(_path), 11, FontWeights.SemiBold, t.Primary)));
            if (_pages > 0) head.Children.Add(V.Box(V.Mono(_pages + (_pages == 1 ? " page" : " pages"), 9.5, FontWeights.Medium, t.Secondary), V.P(6, 2), t.P(0.06), 4));
            head.Children.Add(V.Button(V.Box(V.H(3, Sym.Icon(_continuous ? "scroll" : "book.closed", 9.5, t.Secondary), V.T(_continuous ? "Continuous" : "Single Page", 10, FontWeights.Normal, t.Secondary)), V.P(6, 2.5), t.P(0.06), 4), () => { _continuous = !_continuous; Build(); }));
            if (!_continuous && _pages > 1)
            {
                head.Children.Add(V.Button(Sym.Icon("chevron.left", 10, t.Secondary), () => { if (_page > 0) { _page--; Build(); } }));
                head.Children.Add(V.Mono((_page + 1) + " / " + _pages, 10, FontWeights.Medium, t.Secondary));
                head.Children.Add(V.Button(Sym.Icon("chevron.right", 10, t.Secondary), () => { if (_page < _pages - 1) { _page++; Build(); } }));
            }
            head.Children.Add(V.Sp());
            head.Children.Add(V.Button(V.Box(Sym.Icon(_expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", 9.5, t.Secondary, FontWeights.Medium), V.P(4), t.P(0.06), 4), () => { _expanded = !_expanded; Build(); }));
            head.Children.Add(V.Button(V.Box(V.T("Open in Preview", 10, FontWeights.Medium, t.Accent), V.P(7, 2.5), t.A(0.12), 4), () => PreviewDock.OpenFile(_path)));
            _pagesHost.Children.Clear();
            var sv = new ScrollViewer { Content = _pagesHost, Height = _expanded ? 760 : 440, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Background = t.P(0.03) };
            Child = CellCard.OutputCardFrame(head, sv);
            if (_pages > 0) RenderPages();
        }

        async void RenderPages()
        {
            var t = Theme.Current;
            var indexes = _continuous ? Enumerable.Range(0, Math.Min(_pages, 30)).ToList() : new List<int> { _page };
            foreach (var i in indexes)
            {
                try
                {
                    var bytes = await PdfRender.Page(_path, i, 1200);
                    if (bytes == null) continue;
                    var bmp = new BitmapImage();
                    using (var ms = new MemoryStream(bytes)) { bmp.BeginInit(); bmp.CacheOption = BitmapCacheOption.OnLoad; bmp.StreamSource = ms; bmp.EndInit(); }
                    bmp.Freeze();
                    var img = new Image { Source = bmp, Stretch = Stretch.Uniform, Margin = new Thickness(10, 10, 10, 0), MaxWidth = 900 };
                    _pagesHost.Children.Add(new Border { Child = img, Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 6, ShadowDepth = 1, Opacity = 0.25 } });
                }
                catch (Exception ex) { _pagesHost.Children.Add(V.Box(V.T("Page " + (i + 1) + ": " + ex.Message, 11, FontWeights.Normal, t.SysRed), V.P(10), null, 0)); break; }
            }
        }
    }

    /// <summary>NotebookInlineDataGridStudio: Table (filter, sort by column) · Chart (bar / line / scatter / histogram) · Stats, CSV copy / save, SQL cell.</summary>
    internal class DataGridStudio : Border
    {
        readonly InlineDataFrame _p;
        readonly Action<string> _sqlCell;
        string _tab = "Table", _filter = "", _chart = "Bar", _x = "", _y = "";
        int _sortCol = -1;
        bool _asc = true;
        TextBox _filterBox;

        public DataGridStudio(InlineDataFrame payload, Action<string> onSqlCell)
        {
            _p = payload; _sqlCell = onSqlCell;
            _x = _p.Columns.FirstOrDefault() ?? "";
            _y = Numeric.FirstOrDefault() ?? _p.Columns.Skip(1).FirstOrDefault() ?? _x;
            Build();
        }

        List<string> Numeric
        {
            get
            {
                return _p.Columns.Where(c =>
                {
                    DfStats st; if (_p.Stats.TryGetValue(c, out st) && st.MinVal.HasValue) return true;
                    string dt; _p.Dtypes.TryGetValue(c, out dt); dt = (dt ?? "").ToLowerInvariant();
                    return dt.Contains("int") || dt.Contains("float") || dt.Contains("double") || dt.Contains("f64") || dt.Contains("i64");
                }).ToList();
            }
        }

        static bool Num(string s, out double v) { return double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out v); }

        List<List<string>> Rows
        {
            get
            {
                IEnumerable<List<string>> rows = _p.Rows;
                string needle = _filter.Trim().ToLowerInvariant();
                if (needle.Length > 0) rows = rows.Where(r => r.Any(c => (c ?? "").ToLowerInvariant().Contains(needle)));
                var list = rows.ToList();
                if (_sortCol >= 0 && _sortCol < _p.Columns.Count)
                {
                    int ci = _sortCol;
                    list.Sort((a, b) =>
                    {
                        string va = ci < a.Count ? a[ci] : "", vb = ci < b.Count ? b[ci] : "";
                        double da, db;
                        int cmp = Num(va, out da) && Num(vb, out db) ? da.CompareTo(db) : string.Compare(va, vb, StringComparison.CurrentCultureIgnoreCase);
                        return _asc ? cmp : -cmp;
                    });
                }
                return list;
            }
        }

        void Build()
        {
            var t = Theme.Current; bool d = t.IsDark;
            var head = V.H(6, Sym.Icon("tablecells.fill", 10, t.Accent), V.Shrink(V.Mono(_p.VariableName, 11, FontWeights.SemiBold, t.Primary)), V.Mono("\u00B7 " + _p.TotalRows + "\u00D7" + _p.TotalCols, 10, FontWeights.Normal, t.Secondary));
            var tabs = V.H(2);
            foreach (var tb in new[] { "Table", "Chart", "Stats" })
            {
                var tab = tb; bool sel = _tab == tb;
                tabs.Children.Add(V.Button(V.Box(V.T(tb, 10, sel ? FontWeights.SemiBold : FontWeights.Medium, sel ? t.Primary : t.Secondary), V.P(6, 2.5), sel ? t.P(d ? 0.13 : 0.09) : Brushes.Transparent, 4), () => { _tab = tab; Build(); }));
            }
            head.Children.Add(V.Box(tabs, V.P(2), t.P(d ? 0.055 : 0.04), 5));
            if (_tab == "Table")
            {
                var field = Styles.Field("Filter\u2026", 10.5, t.Primary, t.Secondary, out _filterBox);
                _filterBox.Text = _filter; field.MinWidth = 36; field.Width = 96;
                _filterBox.TextChanged += delegate { _filter = _filterBox.Text; RebuildBodyOnly(); };
                head.Children.Add(V.Size(V.Box(V.H(4, Sym.Icon("magnifyingglass", 9.5, t.Secondary), field), V.P(6, 0), t.P(d ? 0.05 : 0.035), 4.5), double.NaN, 20));
            }
            head.Children.Add(V.Sp(2));
            if (_sqlCell != null && _p.CsvExportPath != null)
            {
                var sql = V.Button(V.Size(V.Box(V.H(3, Sym.Icon("cylinder", 9, t.SysCyan), V.T("SQL", 10, FontWeights.Medium, t.SysCyan)), V.P(5.5, 0), NbColor.Alpha(t.SysCyan, 0.11), 4), double.NaN, 20), () =>
                {
                    string safe = _p.VariableName.Replace(" ", "_");
                    _sqlCell("import sqlite3, pandas as pd\n_conn = sqlite3.connect(\":memory:\")\npd.read_csv(r\"" + _p.CsvExportPath + "\").to_sql(\"" + safe + "\", _conn, index=False, if_exists=\"replace\")\nsql_result = pd.read_sql_query(\"SELECT * FROM " + safe + " LIMIT 25\", _conn)\nsql_result");
                });
                sql.ToolTip = "Insert a SQL query cell over this DataFrame";
                head.Children.Add(sql);
            }
            var csvIcon = Sym.Icon("doc.on.doc", 9, t.Secondary);
            var csvText = V.T("CSV", 10, FontWeights.Medium, t.Secondary);
            var csv = V.Button(V.Size(V.Box(V.H(3, csvIcon, csvText), V.P(5.5, 0), t.P(d ? 0.055 : 0.04), 4), double.NaN, 20), () =>
            {
                try { Clipboard.SetText(Csv()); csvText.Text = "Copied"; csvText.Foreground = t.SysGreen; csvIcon.SetBrush(t.SysGreen); } catch (Exception ex) { Debug.WriteLine("csv copy: " + ex.Message); }
            });
            csv.ToolTip = "Copy visible DataFrame slice as CSV";
            head.Children.Add(csv);
            var save = V.Button(V.Size(V.Box(Sym.Icon("square.and.arrow.down", 10, t.Secondary), V.P(5, 0), t.P(d ? 0.055 : 0.04), 4), 21, 20), SaveCsv);
            save.ToolTip = "Save DataFrame as CSV\u2026";
            head.Children.Add(save);

            var col = V.VLead(0); col.Align = Cross.Stretch;
            col.Children.Add(V.Size(V.Box(head, V.P(9, 0), null, 0), double.NaN, 29));
            var line = V.Line(t.Separator, true); line.Opacity = 0.6; col.Children.Add(line);
            _body = new Border();
            col.Children.Add(_body);
            RebuildBodyOnly();
            Child = V.Box(col, V.P(0), t.P(d ? 0.032 : 0.02), 8, t.P(d ? 0.12 : 0.09), 0.8);
        }

        Border _body;
        void RebuildBodyOnly() { if (_body == null) return; _body.Child = _tab == "Chart" ? Chart() : _tab == "Stats" ? Stats() : Grid(); }

        UIElement Grid()
        {
            var t = Theme.Current; bool d = t.IsDark;
            var rows = Rows;
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(44) });
            foreach (var c in _p.Columns) g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(132) });
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var hdrBg = t.P(d ? 0.065 : 0.045);
            var corner = new Border { Background = hdrBg, Child = V.Mono("#", 9.5, FontWeights.SemiBold, t.Secondary) };
            ((TextBlock)corner.Child).HorizontalAlignment = HorizontalAlignment.Right; ((TextBlock)corner.Child).Margin = new Thickness(0, 5, 6, 5);
            g.Children.Add(corner);
            for (int i = 0; i < _p.Columns.Count; i++)
            {
                int ci = i; string colName = _p.Columns[i];
                string dt; _p.Dtypes.TryGetValue(colName, out dt);
                var title = V.H(3, V.Shrink(V.T(colName, 10.5, FontWeights.SemiBold, t.Primary)), V.Sp(2));
                if (_sortCol == i) title.Children.Add(Sym.Icon(_asc ? "arrow.up" : "arrow.down", 8.5, t.Accent, FontWeights.Bold));
                var cellHead = V.Button(new Border { Background = hdrBg, BorderBrush = t.P(0.08), BorderThickness = new Thickness(0, 0, 0.7, 0), Padding = new Thickness(8, 4.5, 8, 4.5), Child = V.VLead(1, V.Self(title, Cross.Stretch), V.Mono(dt ?? "", 8.5, FontWeights.Normal, t.Secondary)) },
                    () => { if (_sortCol == ci) _asc = !_asc; else { _sortCol = ci; _asc = true; } RebuildBodyOnly(); });
                System.Windows.Controls.Grid.SetColumn(cellHead, i + 1);
                g.Children.Add(cellHead);
            }
            int r = 1;
            foreach (var row in rows)
            {
                g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                if (r % 2 == 0)
                {
                    var zebra = new Border { Background = t.P(d ? 0.024 : 0.018) };
                    System.Windows.Controls.Grid.SetRow(zebra, r); System.Windows.Controls.Grid.SetColumnSpan(zebra, _p.Columns.Count + 1);
                    g.Children.Add(zebra);
                }
                var num = V.Mono(r.ToString(), 9.5, FontWeights.Normal, t.S(0.75)); num.HorizontalAlignment = HorizontalAlignment.Right; num.Margin = new Thickness(0, 4, 6, 4);
                System.Windows.Controls.Grid.SetRow(num, r); g.Children.Add(num);
                for (int i = 0; i < _p.Columns.Count; i++)
                {
                    string v = i < row.Count ? row[i] : "";
                    double dv; bool isNum = Num(v, out dv);
                    var tb = V.Mono(v.Length == 0 ? "null" : v, 10.5, FontWeights.Normal, v.Length == 0 ? t.S(0.45) : t.P(0.92));
                    tb.TextAlignment = isNum ? TextAlignment.Right : TextAlignment.Left;
                    var cell = new Border { Child = tb, Padding = new Thickness(8, 4, 8, 4), BorderBrush = t.P(0.05), BorderThickness = new Thickness(0, 0, 0.7, 0) };
                    System.Windows.Controls.Grid.SetRow(cell, r); System.Windows.Controls.Grid.SetColumn(cell, i + 1);
                    g.Children.Add(cell);
                }
                r++;
            }
            double h = Math.Min(255, 34 + Math.Max(1, Math.Min(rows.Count, 9)) * 23);
            return new ScrollViewer { Content = g, Height = h, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Focusable = false };
        }

        static string Compact(double v)
        {
            if (Math.Abs(v) >= 1000000) return (v / 1000000).ToString("0.00", CultureInfo.InvariantCulture) + "M";
            if (Math.Abs(v) >= 10000) return (v / 1000).ToString("0.0", CultureInfo.InvariantCulture) + "K";
            if (Math.Floor(v) == v) return v.ToString("0", CultureInfo.InvariantCulture);
            return v.ToString("0.000", CultureInfo.InvariantCulture);
        }

        List<Tuple<double, double, string>> Series()
        {
            var pts = new List<Tuple<double, double, string>>();
            int yi = _p.Columns.IndexOf(_y);
            if (yi < 0) return pts;
            int xi = Math.Max(0, _p.Columns.IndexOf(_x));
            if (_chart == "Histogram")
            {
                var vals = new List<double>();
                foreach (var r in _p.Rows) { double v; if (yi < r.Count && Num(r[yi], out v)) vals.Add(v); }
                if (vals.Count == 0) return pts;
                double lo = vals.Min(), hi = vals.Max();
                if (hi == lo) { pts.Add(Tuple.Create(0.0, (double)vals.Count, Compact(lo))); return pts; }
                int bins = Math.Min(20, Math.Max(6, (int)Math.Sqrt(vals.Count)));
                var counts = new int[bins];
                foreach (var v in vals) counts[Math.Min(bins - 1, Math.Max(0, (int)((v - lo) / (hi - lo) * bins)))]++;
                for (int i = 0; i < bins; i++) pts.Add(Tuple.Create((double)i, (double)counts[i], Compact(lo + i / (double)bins * (hi - lo))));
                return pts;
            }
            int n = 0;
            foreach (var r in _p.Rows.Take(120))
            {
                double y;
                if (yi < r.Count && Num(r[yi], out y))
                {
                    string rawX = xi < r.Count ? r[xi] : n.ToString();
                    double x; if (!Num(rawX, out x)) x = n;
                    pts.Add(Tuple.Create(x, y, rawX));
                }
                n++;
            }
            return pts;
        }

        UIElement Chart()
        {
            var t = Theme.Current; bool d = t.IsDark;
            var kinds = V.H(6);
            foreach (var k in new[] { "Bar", "Line", "Scatter", "Histogram" })
            {
                var kind = k; bool active = _chart == k;
                string icon = k == "Bar" ? "chart.bar.fill" : k == "Line" ? "chart.xyaxis.line" : k == "Scatter" ? "circle.dotted" : "chart.bar.xaxis";
                kinds.Children.Add(V.Button(V.Size(V.Box(V.H(3.5, Sym.Icon(icon, 9.5, active ? t.Primary : t.Secondary), V.T(k, 10, active ? FontWeights.SemiBold : FontWeights.Medium, active ? t.Primary : t.Secondary)), V.P(7, 0), active ? t.P(d ? 0.13 : 0.09) : t.P(0.04), 4.5), double.NaN, 20), () => { _chart = kind; RebuildBodyOnly(); }));
            }
            kinds.Children.Add(V.Sp(6));
            Func<string, string, List<string>, Action<string>, UIElement> picker = (prefix, sel, cands, set) =>
            {
                var b = V.Button(V.Size(V.Box(V.H(3.5, V.T(prefix + ":", 9.5, FontWeights.SemiBold, t.Secondary), V.Mono(sel.Length == 0 ? "Select" : sel, 10, FontWeights.Medium, t.Primary), Sym.Icon("chevron.down", 7.5, t.Secondary, FontWeights.SemiBold)), V.P(6.5, 0), t.P(d ? 0.07 : 0.045), 4.5), double.NaN, 20), null);
                b.MenuItems = () => cands.Select(c => { var cc = c; return new MenuItemSpec { Title = c, Checked = c == sel, Action = () => { set(cc); RebuildBodyOnly(); } }; }).ToList();
                return b;
            };
            if (_chart != "Histogram") kinds.Children.Add(picker("X", _x, _p.Columns, v => _x = v));
            kinds.Children.Add(picker(_chart == "Histogram" ? "Col" : "Y", _y, Numeric.Count == 0 ? _p.Columns : Numeric, v => _y = v));
            var col = V.VLead(8, V.Self(kinds, Cross.Stretch)); col.Align = Cross.Stretch;
            var pts = Series();
            if (pts.Count == 0)
            {
                var msg = V.T("Select a numeric column for Y to render chart.", 11, FontWeights.Normal, t.Secondary); msg.HorizontalAlignment = HorizontalAlignment.Center;
                col.Children.Add(V.Size(new Border { Child = msg }, double.NaN, 165));
            }
            else
            {
                double minY = pts.Min(p => p.Item2), maxY = pts.Max(p => p.Item2);
                var axis = new Grid { Width = 44, Height = 168 };
                Func<string, VerticalAlignment, TextBlock> ax = (s, va) => { var tb = V.Mono(s, 9, FontWeights.Normal, t.Secondary); tb.HorizontalAlignment = HorizontalAlignment.Right; tb.VerticalAlignment = va; return tb; };
                axis.Children.Add(ax(Compact(maxY), VerticalAlignment.Top)); axis.Children.Add(ax(Compact((minY + maxY) * 0.5), VerticalAlignment.Center)); axis.Children.Add(ax(Compact(minY), VerticalAlignment.Bottom));
                var canvas = new ChartCanvas { Kind = _chart, Points = pts, MinY = minY, MaxY = maxY, Height = 168 };
                var plot = new Grid();
                plot.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                plot.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                plot.Children.Add(axis); System.Windows.Controls.Grid.SetColumn(canvas, 1); canvas.Margin = new Thickness(6, 0, 0, 0); plot.Children.Add(canvas);
                col.Children.Add(plot);
                var legend = new Grid { Margin = new Thickness(50, 0, 0, 0) };
                var l1 = V.Mono(pts[0].Item3, 9, FontWeights.Normal, t.Secondary); l1.HorizontalAlignment = HorizontalAlignment.Left;
                var l2 = V.Mono(pts.Count + " points \u00B7 " + _y, 9, FontWeights.Normal, t.Secondary); l2.HorizontalAlignment = HorizontalAlignment.Center;
                var l3 = V.Mono(pts[pts.Count - 1].Item3, 9, FontWeights.Normal, t.Secondary); l3.HorizontalAlignment = HorizontalAlignment.Right;
                legend.Children.Add(l1); legend.Children.Add(l2); legend.Children.Add(l3);
                col.Children.Add(legend);
            }
            return V.Box(col, V.P(10), null, 0);
        }

        UIElement Stats()
        {
            var t = Theme.Current;
            var col = V.VLead(0); col.Align = Cross.Stretch;
            Func<string, double, TextAlignment, Brush, TextBlock> cell = (s, w, a, fg) => { var tb = V.Mono(s, 10, FontWeights.Normal, fg); tb.Width = w; tb.TextAlignment = a; return tb; };
            col.Children.Add(V.Box(V.H(0, cell("Column", 135, TextAlignment.Left, t.Secondary), cell("Dtype", 80, TextAlignment.Left, t.Secondary), cell("Nulls", 60, TextAlignment.Right, t.Secondary), cell("Min", 78, TextAlignment.Right, t.Secondary), cell("Mean", 78, TextAlignment.Right, t.Secondary), cell("Max", 78, TextAlignment.Right, t.Secondary)), V.P(10, 4.5), t.P(0.05), 0));
            int idx = 0;
            foreach (var c in _p.Columns)
            {
                DfStats st; _p.Stats.TryGetValue(c, out st);
                string dt; _p.Dtypes.TryGetValue(c, out dt);
                bool isNum = st != null && st.MinVal.HasValue;
                var nameTb = V.T(c, 10.5, FontWeights.Medium, t.Primary); nameTb.Width = 135;
                var row = V.H(0, nameTb, cell(dt ?? "-", 80, TextAlignment.Left, t.Secondary), cell((st != null ? st.NullCount : 0).ToString(), 60, TextAlignment.Right, st != null && st.NullCount > 0 ? (Brush)t.SysOrange : t.Secondary),
                    cell(st != null && st.MinVal.HasValue ? Compact(st.MinVal.Value) : "-", 78, TextAlignment.Right, t.Primary), cell(st != null && st.MeanVal.HasValue ? Compact(st.MeanVal.Value) : "-", 78, TextAlignment.Right, t.Primary),
                    cell(st != null && st.MaxVal.HasValue ? Compact(st.MaxVal.Value) : "-", 78, TextAlignment.Right, t.Primary), V.Sp());
                if (isNum) { var colName = c; row.Children.Add(V.Tip(V.Button(Sym.Icon("chart.bar.xaxis", 10, t.Accent), () => { _y = colName; _chart = "Histogram"; _tab = "Chart"; Build(); }), "Plot Histogram for " + c)); }
                col.Children.Add(V.Box(row, V.P(10, 4.5), idx % 2 == 0 ? Brushes.Transparent : (Brush)t.P(0.02), 0));
                idx++;
            }
            return new ScrollViewer { Content = col, MaxHeight = 210, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, Focusable = false };
        }

        string Csv()
        {
            Func<string, string> esc = s => s.Contains(",") || s.Contains("\"") || s.Contains("\n") ? "\"" + s.Replace("\"", "\"\"") + "\"" : s;
            var lines = new List<string> { string.Join(",", _p.Columns.Select(esc)) };
            foreach (var r in Rows) lines.Add(string.Join(",", r.Select(x => esc(x ?? ""))));
            return string.Join("\n", lines);
        }

        void SaveCsv()
        {
            var dlg = new Microsoft.Win32.SaveFileDialog { FileName = _p.VariableName + ".csv", Filter = "CSV (*.csv)|*.csv" };
            if (dlg.ShowDialog() != true) return;
            try
            {
                if (_p.CsvExportPath != null && File.Exists(_p.CsvExportPath) && _filter.Length == 0) File.Copy(_p.CsvExportPath, dlg.FileName, true);
                else File.WriteAllText(dlg.FileName, Csv(), new UTF8Encoding(false));
            }
            catch (Exception ex) { MessageBox.Show(ex.Message, "Save CSV", MessageBoxButton.OK, MessageBoxImage.Warning); }
        }
    }

    internal class ChartCanvas : FrameworkElement
    {
        public string Kind;
        public List<Tuple<double, double, string>> Points;
        public double MinY, MaxY;

        protected override void OnRender(DrawingContext dc)
        {
            var t = Theme.Current;
            double w = Math.Max(10, ActualWidth), h = Math.Max(10, ActualHeight);
            double yBase = Kind == "Bar" || Kind == "Histogram" ? Math.Min(0, MinY) : MinY;
            double span = Math.Max(1e-9, MaxY - yBase);
            var grid = new Pen(t.P(0.08), 0.7);
            for (int g = 0; g <= 3; g++) dc.DrawLine(grid, new Point(0, h * g / 3.0), new Point(w, h * g / 3.0));
            Func<double, double> mapY = v => h - (v - yBase) / span * (h - 8) - 4;
            var accent = t.Accent;
            if (Kind == "Bar" || Kind == "Histogram")
            {
                double n = Math.Max(1, Points.Count), slot = w / n, barW = Math.Max(2, slot * 0.74), zero = mapY(Math.Max(0, yBase));
                var fill = Theme.B(Theme.WithAlpha(t.AccentColor, 0.82));
                for (int i = 0; i < Points.Count; i++)
                {
                    double x = i * slot + (slot - barW) * 0.5, y = mapY(Points[i].Item2);
                    double top = Math.Min(zero, y), bot = Math.Max(zero, y);
                    dc.DrawRoundedRectangle(fill, null, new Rect(x, top, barW, Math.Max(1.5, bot - top)), 2, 2);
                }
            }
            else if (Kind == "Line")
            {
                if (Points.Count < 2) { dc.DrawEllipse(accent, null, new Point(w * 0.5, mapY(Points[0].Item2)), 3, 3); return; }
                var line = new StreamGeometry(); var area = new StreamGeometry();
                using (var lc = line.Open())
                using (var ac = area.Open())
                {
                    for (int i = 0; i < Points.Count; i++)
                    {
                        var p = new Point(i / (double)(Points.Count - 1) * (w - 8) + 4, mapY(Points[i].Item2));
                        if (i == 0) { lc.BeginFigure(p, false, false); ac.BeginFigure(new Point(p.X, h), true, true); ac.LineTo(p, false, false); }
                        else { lc.LineTo(p, true, true); ac.LineTo(p, false, false); }
                    }
                    ac.LineTo(new Point(w - 4, h), false, false);
                }
                dc.DrawGeometry(Theme.B(Theme.WithAlpha(t.AccentColor, 0.14)), null, area);
                dc.DrawGeometry(null, new Pen(accent, 1.8) { LineJoin = PenLineJoin.Round }, line);
            }
            else
            {
                double minX = Points.Min(p => p.Item1), spanX = Math.Max(1e-9, Points.Max(p => p.Item1) - minX);
                var dot = Theme.B(Theme.WithAlpha(t.SysCyan.Color, 0.85));
                foreach (var p in Points) dc.DrawEllipse(dot, null, new Point((p.Item1 - minX) / spanX * (w - 10) + 5, mapY(p.Item2)), 3, 3);
            }
        }
    }
}
