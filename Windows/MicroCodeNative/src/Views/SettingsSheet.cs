// Port of SettingsView (Views/Workspace/WorkspaceSettingsAndWindowModifiers.swift): Codex-style sidebar (236pt), 20pt title,
// Cancel / Save Changes, 12 sections. Edits are staged and applied on Save Changes, discarded on Cancel / Esc.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shell;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public static class SettingsWindow
    {
        public static void Show(AppState app) { Show(app, (int)Defaults.Num("settingsSelectedTab", 2)); }
        public static void Show(AppState app, int tab) { new SettingsSheet(app, tab).ShowDialog(); }
    }

    public class SettingsSheet : Window
    {
        static readonly object[,] Items = {
            {0, "General", "gearshape"}, {1, "Editor", "text.cursor"}, {2, "AI & Agent", "cpu"},
            {11, "Connect with Phone", "iphone.radiowaves.left.and.right"}, {12, "Team Collaboration", "person.2"},
            {9, "Cloud GPU", "memorychip"}, {10, "Skills", "square.stack.3d.up"}, {8, "MCP Servers", "server.rack"},
            {3, "Tools", "wrench.and.screwdriver"}, {5, "Extensions", "puzzlepiece.extension"}, {6, "Account & License", "person.badge.key"}, {4, "About", "info.circle"}
        };

        readonly AppState _app;
        int _tab;
        readonly Dictionary<string, object> _pending = new Dictionary<string, object>();
        readonly Border _sidebar = new Border(), _title = new Border(), _content = new Border();
        readonly ScrollViewer _scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        static Style _sliderStyle;

        public SettingsSheet(AppState app, int tab)
        {
            _app = app; _tab = tab;
            var t = Theme.Current;
            var owner = Application.Current.MainWindow;
            if (owner != null && owner.IsVisible) Owner = owner; else owner = null;
            double ow = owner != null && owner.ActualWidth > 0 ? owner.ActualWidth : 1400, oh = owner != null && owner.ActualHeight > 0 ? owner.ActualHeight : 900;
            Width = Math.Max(Math.Min(880, ow - 24), Math.Min(1000, ow - 60));
            Height = Math.Max(Math.Min(600, oh - 24), Math.Min(700, oh - 60));
            MinWidth = Math.Min(880, ow - 24); MinHeight = Math.Min(600, oh - 24); MaxWidth = 1240; MaxHeight = 920;
            WindowStartupLocation = owner != null ? WindowStartupLocation.CenterOwner : WindowStartupLocation.CenterScreen;
            ShowInTaskbar = false;
            ResizeMode = ResizeMode.CanResize;
            FontFamily = UIFonts.UI;
            UseLayoutRounding = true;
            Title = "Settings";
            Background = t.WindowBackground;
            WindowChrome.SetWindowChrome(this, new WindowChrome { CaptionHeight = 0, ResizeBorderThickness = new Thickness(5), GlassFrameThickness = new Thickness(0, 0, 0, 1), UseAeroCaptionButtons = false });
            SourceInitialized += delegate { Native.StyleWindow(this, t.IsDark); };

            var root = new Grid { Background = t.WindowBackground };
            root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(236) });
            root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
            root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            _sidebar.Background = Theme.B(t.IsDark ? Theme.Rgb(38, 38, 40) : Theme.Rgb(232, 232, 234));
            root.Children.Add(_sidebar);
            var div = new Border { Background = t.Separator }; Grid.SetColumn(div, 1); root.Children.Add(div);
            var right = new Grid();
            right.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            right.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            right.Children.Add(_title);
            _scroll.Content = _content;
            Grid.SetRow(_scroll, 1); right.Children.Add(_scroll);
            Grid.SetColumn(right, 2); root.Children.Add(right);
            Content = root;
            // drag the sheet by its sidebar / title area
            MouseLeftButtonDown += (s, e) => { if (e.GetPosition(this).Y < 60 && e.ClickCount == 1) { try { DragMove(); } catch { } } };
            PreviewKeyDown += (s, e) => { if (e.Key == Key.Escape) { Close(); e.Handled = true; } };
            if (SkillStore.Skills.Count == 0) SkillStore.Rescan();
            Action live = () => Dispatcher.BeginInvoke(new Action(() => { if (IsLoaded && (_tab == 6 || _tab == 2)) Rerender(); }));
            DotminiAuth.Changed += live; DotminiPlatformKey.Changed += live; DotminiCloud.Changed += live;
            Closed += delegate { DotminiAuth.Changed -= live; DotminiPlatformKey.Changed -= live; DotminiCloud.Changed -= live; };
            Render();
        }

        // ── staged values ──────────────────────────────────────────────
        T Get<T>(string key, T def)
        {
            object v;
            if (_pending.TryGetValue(key, out v)) return (T)v;
            object d = Defaults.Get(key);
            if (d == null) return def;
            try { return (T)Convert.ChangeType(d, typeof(T)); } catch { return def; }
        }
        void Set(string key, object value) { _pending[key] = value; }

        void Save()
        {
            foreach (var kv in _pending)
            {
                if (kv.Key.StartsWith("key:")) AIConfig.SetKeyFor(kv.Key.Substring(4), (string)kv.Value);
                else if (kv.Key.StartsWith("base:")) AIConfig.SetBaseUrlFor(kv.Key.Substring(5), (string)kv.Value);
                else if (kv.Key == "appTheme") { }
                else if (kv.Key == "editorFontSize") { }
                else Defaults.Set(kv.Key, kv.Value);
            }
            object theme, size;
            if (_pending.TryGetValue("editorFontSize", out size)) _app.SetFontSize(Convert.ToDouble(size));
            if (_pending.TryGetValue("sidebarVisible", out size)) _app.SetSidebarVisible((bool)size);
            Defaults.Flush();
            _app.Notify("agentBar");
            _app.Notify("font");
            if (_pending.TryGetValue("appTheme", out theme) && (string)theme != _app.ThemeRaw)
            {
                string raw = (string)theme;
                Close();
                _app.SetTheme(raw); // deferThemeUntilDismissed
                return;
            }
            Close();
        }

        // ── layout ─────────────────────────────────────────────────────
        void Render()
        {
            var t = Theme.Current;
            Defaults.Set("settingsSelectedTab", _tab);
            // Sidebar (Codex-style)
            var side = V.VLead(2); side.Align = Cross.Stretch;
            var back = V.Button(V.H(6, Sym.Icon("chevron.left", 12, t.Secondary, FontWeights.Medium), V.T("Back to app", 12, FontWeights.Medium, t.Secondary)), Close);
            side.Children.Add(V.Box(back, V.P(0, 6, 0, 16), null, 0));
            for (int i = 0; i < Items.GetLength(0); i++)
            {
                int tab = (int)Items[i, 0];
                bool sel = tab == _tab;
                var icon = V.Size(new Grid { Children = { Sym.Icon((string)Items[i, 2], 13, sel ? t.Primary : t.Secondary, sel ? FontWeights.SemiBold : FontWeights.Normal) } }, 18, double.NaN);
                var row = V.Button(V.Box(V.H(10, icon, V.T((string)Items[i, 1], 13, sel ? FontWeights.SemiBold : FontWeights.Normal, sel ? t.Primary : t.Secondary), V.Sp()), V.P(10, 6.5), sel ? t.P(0.09) : Brushes.Transparent, 7), () => { _tab = tab; Render(); _scroll.ScrollToTop(); });
                if (!sel) row.OnState = b => ((Border)b.Child).Background = b.IsHover ? t.P(0.045) : Brushes.Transparent;
                side.Children.Add(row);
            }
            side.Children.Add(V.Sp());
            side.Children.Add(V.T("© 2025 MicroCode · Dotmini Software", 10, FontWeights.Normal, t.S(0.65)));
            _sidebar.Child = V.Box(side, V.P(14, 18), null, 0);

            // Title bar
            string title = "Settings";
            for (int i = 0; i < Items.GetLength(0); i++) if ((int)Items[i, 0] == _tab) title = (string)Items[i, 1];
            var cancel = V.Button(V.Box(V.T("Cancel", 11.5, FontWeights.Medium, t.Secondary), V.P(12, 5), t.P(0.05), 6, t.P(0.09), 1), Close);
            var save = V.Button(V.Box(V.T("Save Changes", 11.5, FontWeights.SemiBold, t.Primary), V.P(14, 5), t.P(0.10), 6, t.P(0.20), 1), Save);
            var head = V.VLead(0, V.Self(V.Box(V.H(8, V.T(title, 20, FontWeights.Bold, t.Primary), V.Sp(), cancel, save), V.P(32, 20, 32, 16), null, 0), Cross.Stretch),
                V.Self(V.Line(t.Op(t.Separator, 0.5), true), Cross.Stretch));
            head.Align = Cross.Stretch;
            _title.Child = head;

            UIElement body;
            switch (_tab)
            {
                case 0: body = General(); break;
                case 1: body = EditorTab(); break;
                case 2: body = AITab(); break;
                case 11: body = PhoneTab(); break;
                case 12: body = TeamTab(); break;
                case 9: body = CloudGPUTab(); break;
                case 10: body = SkillsTab(); break;
                case 8: body = MCPTab(); break;
                case 3: body = ToolsTab(); break;
                case 5: body = ExtensionsTab(); break;
                case 6: body = AccountTab(); break;
                default: body = AboutTab(); break;
            }
            var wrap = V.VLead(18, V.Self(body, Cross.Stretch)); wrap.Align = Cross.Stretch;
            _content.Child = V.Box(wrap, V.P(32, 20, 32, 32), null, 0);
        }

        void Rerender()
        {
            double off = _scroll.VerticalOffset;
            var focused = Keyboard.FocusedElement as FrameworkElement;
            string tag = focused != null ? focused.Tag as string : null;
            int caret = focused is TextBox ? ((TextBox)focused).CaretIndex : -1;
            Render();
            _scroll.ScrollToVerticalOffset(off);
            if (tag != null && tag.StartsWith("field:"))
                Dispatcher.BeginInvoke(new Action(() =>
                {
                    var el = FindTagged(_content, tag);
                    if (el == null) return;
                    el.Focus();
                    if (el is TextBox && caret >= 0) ((TextBox)el).CaretIndex = Math.Min(caret, ((TextBox)el).Text.Length);
                }), System.Windows.Threading.DispatcherPriority.Input);
        }

        static FrameworkElement FindTagged(DependencyObject root, string tag)
        {
            if (root == null) return null;
            var fe = root as FrameworkElement;
            if (fe != null && tag.Equals(fe.Tag as string)) return fe;
            int n = VisualTreeHelper.GetChildrenCount(root);
            for (int i = 0; i < n; i++) { var r = FindTagged(VisualTreeHelper.GetChild(root, i), tag); if (r != null) return r; }
            return null;
        }

        /// <summary>Runs async work off the UI thread and refreshes the sheet when it completes.</summary>
        void RunAsync(Func<Task> work)
        {
            Task.Run(work).ContinueWith(tk => Dispatcher.BeginInvoke(new Action(Rerender)));
        }

        Btn SmallBtn(string label, string icon, Action a)
        {
            var t = Theme.Current;
            var row = V.H(5);
            if (icon != null) row.Children.Add(Sym.Icon(icon, 10.5, t.Primary));
            row.Children.Add(V.T(label, 11.5, FontWeights.Medium, t.Primary));
            return V.Button(V.Box(row, V.P(9, 3.5), t.P(0.09), 5, t.P(0.12), 0.5), a);
        }

        Btn PrimaryBtn(string label, Action a)
        {
            var t = Theme.Current;
            var tb = V.T(label, 12, FontWeights.SemiBold, Brushes.White); tb.HorizontalAlignment = HorizontalAlignment.Center;
            return V.Button(V.Box(tb, V.P(14, 5), t.Accent, 6), a);
        }

        // ── macOS controls ─────────────────────────────────────────────
        UIElement SectionHeader(string title)
        {
            return V.Box(V.T(title.ToUpperInvariant(), 11, FontWeights.Bold, Theme.Current.Secondary), V.P(0, 8, 0, 0), null, 0);
        }

        UIElement Card(params UIElement[] kids)
        {
            var s = V.VLead(12, kids); s.Align = Cross.Stretch;
            return V.Self(V.Box(s, V.P(16), Theme.Current.ControlBackground, 12), Cross.Stretch);
        }

        UIElement Checkbox(string label, string key, bool def)
        {
            var t = Theme.Current;
            bool on = Get(key, def);
            var mark = Sym.Icon("checkmark", 9, Brushes.White, FontWeights.Bold);
            var box = new Border { Width = 14, Height = 14, CornerRadius = new CornerRadius(3.5), Child = mark, VerticalAlignment = VerticalAlignment.Center };
            Action paint = () =>
            {
                bool v = Get(key, def);
                box.Background = v ? t.Accent : t.P(0.08);
                box.BorderBrush = v ? t.Accent : t.P(0.32);
                box.BorderThickness = new Thickness(v ? 0 : 1);
                mark.Visibility = v ? Visibility.Visible : Visibility.Hidden;
            };
            paint();
            var b = V.Button(V.H(7, box, V.T(label, 13, FontWeights.Normal, t.Primary)), () => { Set(key, !Get(key, def)); paint(); });
            b.PressedOpacity = 0.85;
            return b;
        }

        UIElement PopUp(string current, IEnumerable<string> options, Action<string> pick, double width)
        {
            var t = Theme.Current;
            var b = V.Button(V.Box(V.H(6, V.Flex(V.T(current, 13, FontWeights.Normal, t.Primary)), Sym.Icon("chevron.up.chevron.down", 9, t.Secondary, FontWeights.SemiBold)), V.P(9, 3), t.P(0.12), 5, t.P(0.06), 0.5), null);
            if (!double.IsNaN(width)) b.Width = width;
            var opts = options.ToList();
            b.MenuItems = () => opts.Select(o => new MenuItemSpec { Title = o, Checked = o == current, Action = () => pick(o) }).ToList();
            return b;
        }

        UIElement Slider(double value, double min, double max, Action<double> changed)
        {
            if (_sliderStyle == null)
            {
                _sliderStyle = (Style)System.Windows.Markup.XamlReader.Parse(@"<Style TargetType='Slider' xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>
  <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='Slider'>
    <Grid Height='20' Background='Transparent'>
      <Border Height='4' CornerRadius='2' Background='#33FFFFFF' VerticalAlignment='Center'/>
      <Track x:Name='PART_Track' VerticalAlignment='Center'>
        <Track.DecreaseRepeatButton><RepeatButton Command='Slider.DecreaseLarge' Focusable='False'><RepeatButton.Template><ControlTemplate TargetType='RepeatButton'><Border Height='4' CornerRadius='2' Background='#0A84FF'/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.DecreaseRepeatButton>
        <Track.IncreaseRepeatButton><RepeatButton Command='Slider.IncreaseLarge' Focusable='False'><RepeatButton.Template><ControlTemplate TargetType='RepeatButton'><Border Background='Transparent'/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.IncreaseRepeatButton>
        <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType='Thumb'><Ellipse Width='18' Height='18' Fill='White'><Ellipse.Effect><DropShadowEffect BlurRadius='4' ShadowDepth='1' Opacity='0.4'/></Ellipse.Effect></Ellipse></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
      </Track>
    </Grid></ControlTemplate></Setter.Value></Setter></Style>");
            }
            var s = new System.Windows.Controls.Slider { Minimum = min, Maximum = max, Value = value, IsSnapToTickEnabled = true, TickFrequency = 1, Style = _sliderStyle, VerticalAlignment = VerticalAlignment.Center };
            s.ValueChanged += (o, e) => changed(Math.Round(e.NewValue));
            return s;
        }

        UIElement Segmented(string[] labels, int selected, Action<int> pick)
        {
            var t = Theme.Current;
            var row = new UniformGrid { Rows = 1, Columns = labels.Length };
            for (int i = 0; i < labels.Length; i++)
            {
                int idx = i;
                bool on = i == selected;
                var label = V.T(labels[i], 12, on ? FontWeights.Medium : FontWeights.Normal, on ? t.Primary : t.Secondary);
                label.HorizontalAlignment = HorizontalAlignment.Center;
                row.Children.Add(V.Button(V.Box(label, V.P(6, 3), on ? t.P(0.20) : Brushes.Transparent, 5), () => pick(idx)));
            }
            return V.Self(V.Box(row, V.P(2), t.P(0.08), 7), Cross.Stretch);
        }

        UIElement Stepper(string label, int value, int min, int max, int step, Action<int> changed)
        {
            var t = Theme.Current;
            var minus = V.Button(V.Size(V.Box(V.T("−", 13, FontWeights.Medium, t.Primary), V.P(0), Brushes.Transparent, 0), 20, 20), () => changed(Math.Max(min, value - step)));
            var plus = V.Button(V.Size(V.Box(V.T("+", 13, FontWeights.Medium, t.Primary), V.P(0), Brushes.Transparent, 0), 20, 20), () => changed(Math.Min(max, value + step)));
            foreach (var b in new[] { minus, plus }) ((TextBlock)((Border)b.Child).Child).HorizontalAlignment = HorizontalAlignment.Center;
            return V.H(8, V.T(label, 13, FontWeights.Normal, t.Primary), V.Box(V.H(0, minus, V.Size(V.Line(t.P(0.15), false), 1, 14), plus), V.P(0), t.P(0.12), 5));
        }

        TextBox TextArea(string key, string def, double height)
        {
            var t = Theme.Current;
            var tb = new TextBox
            {
                Text = Get(key, def), AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, FontFamily = UIFonts.Mono, FontSize = 11, Height = height,
                Foreground = t.Primary, Background = Brushes.Transparent, BorderThickness = new Thickness(0), CaretBrush = t.Primary, VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            };
            tb.TextChanged += delegate { Set(key, tb.Text); };
            return tb;
        }

        UIElement Framed(UIElement inner) { var t = Theme.Current; return V.Self(V.Box(inner, V.P(6), t.Op(t.TextBackground, 0.5), 6, t.P(0.1), 1), Cross.Stretch); }

        UIElement Field(string placeholder, string value, bool secure, Action<string> changed, double width) { return Field(placeholder, value, secure, changed, width, null); }

        UIElement Field(string placeholder, string value, bool secure, Action<string> changed, double width, Action onEnter)
        {
            var t = Theme.Current;
            FrameworkElement input;
            if (secure)
            {
                var pb = new PasswordBox { Password = value ?? "", Background = Brushes.Transparent, BorderThickness = new Thickness(0), Foreground = t.Primary, CaretBrush = t.Primary, FontSize = 11, VerticalContentAlignment = VerticalAlignment.Center, Tag = "field:" + placeholder };
                var ph = V.T(placeholder, 11, FontWeights.Normal, t.Secondary); ph.IsHitTestVisible = false;
                ph.Visibility = string.IsNullOrEmpty(value) ? Visibility.Visible : Visibility.Collapsed;
                pb.PasswordChanged += delegate { ph.Visibility = pb.Password.Length == 0 ? Visibility.Visible : Visibility.Collapsed; changed(pb.Password); };
                if (onEnter != null) pb.KeyDown += (s, e) => { if (e.Key == Key.Enter) { e.Handled = true; onEnter(); } };
                var g = new Grid(); g.Children.Add(ph); g.Children.Add(pb);
                input = g;
            }
            else
            {
                TextBox tb;
                var g = Styles.Field(placeholder, 11, t.Primary, t.Secondary, out tb);
                tb.FontFamily = UIFonts.Mono; tb.Text = value ?? "";
                tb.Tag = "field:" + placeholder;
                tb.TextChanged += delegate { changed(tb.Text); };
                if (onEnter != null) tb.KeyDown += (s, e) => { if (e.Key == Key.Enter) { e.Handled = true; onEnter(); } };
                input = g;
            }
            var box = V.Box(input, V.P(8, 5), t.Op(t.TextBackground, 0.8), 5, t.P(0.12), 1);
            if (!double.IsNaN(width)) box.Width = width;
            return box;
        }

        static readonly string[] FontNames = { "SF Pro", "SF Mono", "Menlo", "Fira Code", "Monaco", "Courier New", "Helvetica Neue" };

        // ── General ────────────────────────────────────────────────────
        UIElement General()
        {
            var t = Theme.Current;
            var root = V.VLead(20); root.Align = Cross.Stretch;
            int iters = Get("agentMaxIterations", 0);
            var iterRow = V.VLead(3, V.Self(V.H(8, V.T("Max Tool Loop Iterations:", 12, FontWeights.Medium, t.Primary), V.Sp(),
                Stepper(iters <= 0 ? "Unlimited (∞)" : iters + " steps", iters, 0, 200, 5, v => { Set("agentMaxIterations", v); Rerender(); })), Cross.Stretch));
            if (iters <= 0) iterRow.Children.Add(V.T("No limit — Agent will continue multi-turn thinking & tool loops until the task is complete.", 10.5, FontWeights.Normal, t.S(0.8)));
            iterRow.Align = Cross.Stretch;
            double af = Get("agentFontSize", 16.0);
            TextBlock afLabel = V.T("Agent Size: " + (int)af + " pt", 12, FontWeights.Medium, t.Primary); afLabel.Width = 120;
            root.Children.Add(Card(
                SectionHeader("AI Agent & Automation"),
                Checkbox("Autonomous Agent Mode (Multi-turn tool loop & file edits)", "agentMode", true),
                Checkbox("Auto-Approve Tool Execution (Files, Shell, Refactor)", "agentAutoApproveTools", false),
                iterRow,
                V.Self(V.H(8, V.T("Agent Font:", 12, FontWeights.Medium, t.Primary), V.Sp(), PopUp(Get("agentFontName", "SF Pro"), FontNames.Take(4), v => { Set("agentFontName", v); Rerender(); }, 120)), Cross.Stretch),
                V.Self(V.H(8, afLabel, V.Flex(Slider(af, 12, 26, v => { Set("agentFontSize", v); afLabel.Text = "Agent Size: " + (int)v + " pt"; }))), Cross.Stretch),
                V.VLead(4, V.T("Custom System Instructions / Rules:", 11, FontWeights.SemiBold, t.Secondary), Framed(TextArea("agentCustomInstructions", "", 70)))));
            root.Children.Add(V.Line(t.Separator, true));
            root.Children.Add(SectionHeader("Appearance"));
            root.Children.Add(Checkbox("Show sidebar on startup", "sidebarVisible", _app.SidebarVisible));
            root.Children.Add(Checkbox("Show console on startup", "showConsoleOnStartup", false));
            root.Children.Add(V.Line(t.Separator, true));
            root.Children.Add(SectionHeader("Theme"));
            root.Children.Add(ThemePicker());
            return root;
        }

        UIElement ThemePicker()
        {
            var t = Theme.Current;
            string sel = Get("appTheme", _app.ThemeRaw);
            var root = V.VLead(20); root.Align = Cross.Stretch;
            Action<string, string[]> section = (title, raws) =>
            {
                var grid = new WrapPanel();
                foreach (var raw in raws)
                {
                    var d = ThemeTable.Find(raw);
                    if (d.Raw != raw) continue;
                    bool on = raw == sel;
                    string r = raw;
                    var preview = new Border { Height = 70, Width = 148, CornerRadius = new CornerRadius(8), Background = Theme.B(Theme.WithAlpha(d.EditorBackground, Math.Max(0.35, d.EditorBackground.A / 255.0))), BorderBrush = on ? t.Accent : Brushes.Transparent, BorderThickness = new Thickness(on ? 3 : 0) };
                    if (raw == "transparent") preview.Background = new LinearGradientBrush(Theme.WithAlpha(Colors.Blue, 0.4), Theme.WithAlpha(Colors.DeepPink, 0.4), 45);
                    var bars = V.VLead(2, new Border { Width = 30, Height = 4, CornerRadius = new CornerRadius(1), Background = Theme.B(d.Keyword) }, new Border { Width = 50, Height = 4, CornerRadius = new CornerRadius(1), Background = Theme.B(d.EditorText) }, new Border { Width = 40, Height = 4, CornerRadius = new CornerRadius(1), Background = Theme.B(d.String) });
                    bars.Margin = new Thickness(8); bars.VerticalAlignment = VerticalAlignment.Top; bars.HorizontalAlignment = HorizontalAlignment.Left;
                    var pg = new Grid(); pg.Children.Add(bars);
                    if (on) { var chk = Sym.Icon("checkmark.circle.fill", 13, t.Accent); chk.HorizontalAlignment = HorizontalAlignment.Right; chk.VerticalAlignment = VerticalAlignment.Top; chk.Margin = new Thickness(0, 4, 4, 0); pg.Children.Add(chk); }
                    preview.Child = pg;
                    preview.Effect = new DropShadowEffect { BlurRadius = on ? 8 : 4, ShadowDepth = 1, Opacity = on ? 0.3 : 0.18 };
                    var name = V.T(d.DisplayName, 11, on ? FontWeights.Bold : FontWeights.Medium, on ? t.Accent : t.Primary); name.Width = 148;
                    var card = V.Button(V.VLead(6, preview, name), () => { Set("appTheme", r); Rerender(); });
                    card.Margin = new Thickness(0, 0, 12, 12);
                    grid.Children.Add(card);
                }
                root.Children.Add(V.VLead(8, V.T(title.ToUpperInvariant(), 10, FontWeights.Bold, t.Secondary), V.Self(grid, Cross.Stretch)));
            };
            section("Festive Season 🎆", new[] { "happyNewYear2026", "happyNewYear2026Light", "christmas", "christmasLight" });
            section("Modern & Sleek", new[] { "dark", "vscode", "xcodeDark", "githubDark", "dracula", "navy", "doki", "monokaiPro", "oneDarkPro", "nord", "tokyoNight", "catppuccin" });
            section("Classic & Familiar", new[] { "light", "xcodeLight", "visualStudio", "githubLight", "lightBlue", "solarizedDark", "solarizedLight", "gruvboxDark" });
            section("Retro & Synthwave", new[] { "cyberPunk", "synthWave", "powershell" });
            section("Transparency & Special", new[] { "transparent", "crystalClear", "obsidianGlass", "extraClear", "wwdc", "wwdcLight", "keynote", "keynoteLight", "xnuDark" });
            bool sys = sel == "system";
            root.Children.Add(V.Box(V.H(10, V.T("System Default", 11, FontWeights.Bold, t.Secondary),
                V.Button(V.Box(V.H(6, Sym.Icon("desktopcomputer", 12, sys ? Brushes.White : t.Primary), V.T("Follow Windows Appearance", 13, FontWeights.Normal, sys ? Brushes.White : t.Primary)), V.P(12, 6), sys ? t.Accent : t.S(0.1), 6), () => { Set("appTheme", "system"); Rerender(); })), V.P(0, 10, 0, 0), null, 0));
            return root;
        }

        // ── Editor ─────────────────────────────────────────────────────
        UIElement FontCard(string header, string nameKey, string nameDef, string sizeKey, double sizeDef, double min, double max, string weightKey, string[] fonts)
        {
            var t = Theme.Current;
            double size = Get(sizeKey, sizeDef);
            var label = V.T("Size: " + (int)size, 13, FontWeights.Normal, t.Primary); label.Width = 60;
            var kids = new List<UIElement>
            {
                SectionHeader(header),
                V.H(8, V.T("Font Family", 13, FontWeights.Normal, t.Primary), PopUp(Get(nameKey, nameDef), fonts, v => { Set(nameKey, v); Rerender(); }, 220)),
                V.Self(V.H(8, label, V.Flex(Slider(size, min, max, v => { Set(sizeKey, v); label.Text = "Size: " + (int)v; }))), Cross.Stretch)
            };
            if (weightKey != null)
                kids.Add(V.Self(V.H(10, V.T("Font Weight", 13, FontWeights.Normal, t.Primary), V.Flex(Segmented(new[] { "Thin", "Light", "Regular", "Medium", "Semibold", "Bold" }, Get(weightKey, 2), i => { Set(weightKey, i); Rerender(); }))), Cross.Stretch));
            return Card(kids.ToArray());
        }

        UIElement EditorTab()
        {
            var t = Theme.Current;
            var root = V.VLead(24); root.Align = Cross.Stretch;
            root.Children.Add(FontCard("AI Agent & Chat Font", "agentFontName", "SF Pro", "agentFontSize", 16, 12, 26, null, new[] { "SF Pro", "SF Mono", "Menlo", "Fira Code", "Monaco", "Helvetica Neue" }));
            root.Children.Add(FontCard("Main Editor Font", "editorFontFamily", "SF Mono", "editorFontSize", _app.FontSize, 10, 24, null, FontNames));
            root.Children.Add(FontCard("Playground Font", "playgroundFontName", "SF Mono", "playgroundFontSize", 13, 10, 24, "playgroundFontWeight", FontNames.Take(5).ToArray()));
            root.Children.Add(FontCard("Cell Mode Font", "cellFontName", "SF Mono", "cellFontSize", 13, 10, 24, "cellFontWeight", FontNames.Take(5).ToArray()));
            root.Children.Add(Card(SectionHeader("Editing Preferences"), Checkbox("Show line numbers", "showLineNumbers", true),
                V.T("Off by default. Large files in Performance mode hide line numbers automatically for stability.", 11, FontWeights.Normal, t.Secondary),
                Checkbox("Word wrap", "wordWrap", false)));
            root.Children.Add(V.T("Windows maps SF Pro → Segoe UI and SF Mono / Menlo / Monaco → Consolas (Apple fonts are licensed for Apple platforms only).", 10.5, FontWeights.Normal, t.S(0.75)));
            return root;
        }

        // ── AI & Agent ─────────────────────────────────────────────────
        string _fetchStatus = "";
        List<string> _fetched;

        UIElement AITab()
        {
            var t = Theme.Current;
            string mode = Get("ai_key_mode", AIConfig.Mode);
            var root = V.VLead(18); root.Align = Cross.Stretch;
            var modes = new UniformGrid { Rows = 1, Columns = 5 };
            Action<string, string, string> modeBtn = (id, label, icon) =>
            {
                bool on = mode == id;
                var b = V.Button(V.Size(V.Box(V.Self(V.H(6, Sym.Icon(icon, 12, t.Primary), V.T(label, 11.5, on ? FontWeights.SemiBold : FontWeights.Normal, t.Primary)), Cross.Center), V.P(6, 0), on ? t.P(0.12) : t.P(0.03), 6, on ? t.P(0.25) : t.P(0.06), 1), double.NaN, 34), () => { Set("ai_key_mode", id); Rerender(); });
                ((Stack)((Border)b.Child).Child).HorizontalAlignment = HorizontalAlignment.Center;
                b.Margin = new Thickness(0, 0, 8, 0);
                modes.Children.Add(b);
            };
            modeBtn("cloud", "Dotmini Cloud", "sparkles");
            modeBtn("subscription", "Web Subscription", "person.crop.circle");
            modeBtn("direct", "Direct API Key", "key");
            modeBtn("enterprise", "Enterprise", "building.2");
            modeBtn("local", "Local LLM", "desktopcomputer");
            root.Children.Add(V.VLead(10, V.H(8, Sym.Icon("slider.horizontal.3", 12, t.Primary, FontWeights.SemiBold), V.T("AI Mode & Provider", 13, FontWeights.SemiBold, t.Primary)), V.Self(modes, Cross.Stretch)));
            if (mode == "direct") root.Children.Add(DirectPanel());
            else if (mode == "local") root.Children.Add(LocalPanel());
            else if (mode == "cloud") root.Children.Add(CloudPanel());
            else if (mode == "subscription") root.Children.Add(Panel("Web Subscription", "ChatGPT Plus/Team · Claude Pro · Gemini · Zhipu GLM",
                "Direct subscription login runs through the provider's own web sign-in. On Windows this flow is not available yet — use Direct API Key or Local LLM.",
                V.H(8, LinkBtn("ChatGPT", "https://chatgpt.com"), LinkBtn("Claude", "https://claude.ai"), LinkBtn("Gemini", "https://gemini.google.com"), LinkBtn("Zhipu GLM", "https://chatglm.cn"))));
            else root.Children.Add(Panel("Enterprise Connect Hub", "Azure OpenAI · AWS Bedrock · Vertex AI · On-prem gateways",
                "Point MicroCode at your organisation's OpenAI-compatible gateway. Choose Direct API Key → Custom (OpenAI-compatible) and set its Base URL.", null));
            return root;
        }

        UIElement LinkBtn(string label, string url) { var t = Theme.Current; return V.Button(V.Box(V.T(label, 12, FontWeights.Medium, t.Primary), V.P(12, 5), t.P(0.1), 6), () => OpenUrl(url)); }

        UIElement Panel(string title, string mono, string desc, UIElement extra)
        {
            var t = Theme.Current;
            var s = V.VLead(10, V.VLead(2, V.T(title, 13, FontWeights.SemiBold, t.Primary), V.Mono(mono, 10, FontWeights.Normal, t.Secondary)), V.Wrap(V.T(desc, 11.5, FontWeights.Normal, t.Secondary), TextAlignment.Left), extra);
            s.Align = Cross.Stretch;
            return V.Self(V.Box(s, V.P(16), t.ControlBackground, 8, t.P(0.08), 1), Cross.Stretch);
        }

        UIElement DirectPanel()
        {
            var t = Theme.Current;
            string pid = Get("ai_provider", AIConfig.SelectedProvider);
            var info = AIConfig.Info(pid);
            string model = Get("ai_model_" + pid, AIConfig.ModelFor(pid));
            var models = new List<string>(_fetched != null ? _fetched : info.Models.Where(m => m.Length > 0));
            if (model.Length > 0 && !models.Contains(model)) models.Insert(0, model);
            var s = V.VLead(12); s.Align = Cross.Stretch;
            s.Children.Add(V.H(8, Sym.Icon("key", 12, t.Primary, FontWeights.SemiBold), V.T("Bring Your Own Key (BYOK) & Custom Base URL", 13, FontWeights.SemiBold, t.Primary),
                V.Box(V.T("Isolated from Local/LAN LLM", 9.5, FontWeights.SemiBold, t.Secondary), V.P(6, 2), t.P(0.08), 4)));
            s.Children.Add(V.Wrap(V.T("Connect directly to official AI providers (OpenAI, Claude, Gemini, etc.) or any custom Base URL / remote Cloudflare Tunnel (*.trycloudflare.com/v1) without mixing with Local/LAN LLM.", 11.5, FontWeights.Normal, t.Secondary), TextAlignment.Left));
            var lbl1 = V.T("Active Provider:", 12, FontWeights.Medium, t.Primary); lbl1.Width = 110;
            s.Children.Add(V.Self(V.H(8, lbl1, V.Flex(PopUp(info.Name, AIConfig.Catalog.Select(c => c.Name), n => { var p = AIConfig.Catalog.First(c => c.Name == n); Set("ai_provider", p.Id); _fetched = null; _fetchStatus = ""; Rerender(); }, double.NaN))), Cross.Stretch));
            var lbl2 = V.T("Model:", 12, FontWeights.Medium, t.Primary); lbl2.Width = 110;
            var fetch = V.Button(V.Box(V.H(4, Sym.Icon("bolt", 11, t.Primary), V.T(_fetchStatus == "…" ? "Fetching…" : "Fetch Models", 10.5, FontWeights.Medium, t.Primary)), V.P(8, 3), t.P(0.1), 5, t.P(0.12), 0.5), () => FetchModels(pid));
            fetch.ToolTip = "Query /v1/models from this provider's Base URL / Cloudflare Tunnel";
            s.Children.Add(V.Self(V.H(8, lbl2, V.Flex(PopUp(model.Length > 0 ? info.Name + " : " + model : "Custom model…", models.Select(m => info.Name + " : " + m).Concat(new[] { "Custom model…" }), sel =>
            {
                if (sel == "Custom model…") { var m = Prompt.Ask("Custom Model", "Model id:", model); if (!string.IsNullOrWhiteSpace(m)) Set("ai_model_" + pid, m.Trim()); }
                else Set("ai_model_" + pid, sel.Substring(info.Name.Length + 3));
                Rerender();
            }, double.NaN)), fetch), Cross.Stretch));
            if (_fetchStatus.Length > 1) s.Children.Add(V.T(_fetchStatus, 10.5, FontWeights.Medium, _fetchStatus.StartsWith("✓") ? t.SysGreen : t.SysOrange));
            var lbl3 = V.T("Base URL:", 12, FontWeights.Medium, t.Primary); lbl3.Width = 110;
            s.Children.Add(V.Self(V.H(8, lbl3, V.Flex(Field(info.Endpoint, Get("base:" + pid, AIConfig.BaseUrlFor(pid)), false, v => Set("base:" + pid, v), double.NaN))), Cross.Stretch));
            s.Children.Add(V.Line(t.Op(t.Separator, 0.6), true));
            s.Children.Add(V.T("Provider API Keys & Endpoints", 11, FontWeights.SemiBold, t.Secondary));
            var keys = V.VLead(6); keys.Align = Cross.Stretch;
            foreach (var p in AIConfig.Catalog) keys.Children.Add(KeyCard(p, p.Id == pid));
            s.Children.Add(keys);
            return V.Self(V.Box(s, V.P(16), t.ControlBackground, 8, t.P(0.08), 1), Cross.Stretch);
        }

        UIElement KeyCard(ProviderInfo p, bool active)
        {
            var t = Theme.Current;
            var tile = new Border { Width = 28, Height = 28, CornerRadius = new CornerRadius(6), Background = t.P(0.06), BorderBrush = t.P(0.08), BorderThickness = new Thickness(0.5), Child = V.T(p.Name.Substring(0, 1), 13, FontWeights.Bold, t.Primary) };
            ((TextBlock)tile.Child).HorizontalAlignment = HorizontalAlignment.Center;
            var nameRow = V.H(5, V.T(p.Name, 12, FontWeights.SemiBold, t.Primary));
            if (active) nameRow.Children.Add(V.Box(V.T("ACTIVE", 8, FontWeights.Bold, t.Primary), V.P(4, 1.5), t.P(0.1), 3));
            if (AIConfig.HasCustomUrl(p.Id)) nameRow.Children.Add(V.Box(V.T("URL", 8, FontWeights.Bold, t.SysTeal), V.P(4, 1.5), t.Op(t.SysTeal, 0.14), 3));
            var left = V.H(8, tile, V.VLead(1, nameRow, V.Mono(AIConfig.BaseUrlFor(p.Id), 9.5, FontWeights.Normal, t.Secondary)));
            left.Width = 195;
            string existing = AIConfig.KeyFor(p.Id);
            var key = Field(p.Id == "custom" ? "API Key (optional for Cloudflare Tunnel)" : "Paste API key here", existing, true, v => Set("key:" + p.Id, v), double.NaN);
            var row = V.H(10, left, V.Flex(key));
            return V.Self(V.Box(row, V.P(10, 6), active ? t.P(0.05) : Brushes.Transparent, 6, active ? t.P(0.12) : t.P(0.05), 1), Cross.Stretch);
        }

        void FetchModels(string pid)
        {
            _fetchStatus = "…"; Rerender();
            string url = Get("base:" + pid, AIConfig.BaseUrlFor(pid)).TrimEnd('/') + "/models";
            string key = _pending.ContainsKey("key:" + pid) ? (string)_pending["key:" + pid] : AIConfig.KeyFor(pid);
            bool anthropic = pid == "anthropic";
            Task.Run(async () =>
            {
                using (var http = new HttpClient { Timeout = TimeSpan.FromSeconds(20) })
                {
                    var req = new HttpRequestMessage(HttpMethod.Get, pid == "gemini" ? url + "?key=" + Uri.EscapeDataString(key ?? "") : url);
                    if (anthropic) { req.Headers.Add("x-api-key", key ?? ""); req.Headers.Add("anthropic-version", "2023-06-01"); }
                    else if (!string.IsNullOrEmpty(key) && pid != "gemini") req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
                    var resp = await http.SendAsync(req);
                    string body = await resp.Content.ReadAsStringAsync();
                    if (!resp.IsSuccessStatusCode) throw AIException.FromHttp((int)resp.StatusCode, body, null);
                    var o = new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Deserialize<Dictionary<string, object>>(body);
                    var arr = (o.ContainsKey("data") ? o["data"] : o.ContainsKey("models") ? o["models"] : null) as System.Collections.ArrayList;
                    var ids = new List<string>();
                    if (arr != null) foreach (Dictionary<string, object> m in arr) { object id; if (m.TryGetValue("id", out id) || m.TryGetValue("name", out id)) ids.Add(Convert.ToString(id).Replace("models/", "")); }
                    return ids;
                }
            }).ContinueWith(tk => Dispatcher.BeginInvoke(new Action(() =>
            {
                if (tk.IsFaulted) { _fetchStatus = "Could not fetch models: " + AIException.Describe(tk.Exception, false); _fetched = null; }
                else { _fetched = tk.Result.OrderBy(x => x).ToList(); _fetchStatus = "✓ " + _fetched.Count + " models available"; }
                Rerender();
            })));
        }

        UIElement LocalPanel()
        {
            var t = Theme.Current;
            string ep = Get("base:local", AIConfig.BaseUrlFor("local"));
            string model = Get("ai_model_local", AIConfig.ModelFor("local"));
            var s = V.VLead(12); s.Align = Cross.Stretch;
            s.Children.Add(V.H(8, Sym.Icon("desktopcomputer", 12, t.Primary, FontWeights.SemiBold), V.T("Local LLM (Ollama · LM Studio · llama.cpp · vLLM)", 13, FontWeights.SemiBold, t.Primary)));
            s.Children.Add(V.Wrap(V.T("Runs fully on this PC or your LAN. Any OpenAI-compatible endpoint works: Ollama http://localhost:11434/v1, LM Studio http://localhost:1234/v1.", 11.5, FontWeights.Normal, t.Secondary), TextAlignment.Left));
            var l1 = V.T("Endpoint:", 12, FontWeights.Medium, t.Primary); l1.Width = 110;
            s.Children.Add(V.Self(V.H(8, l1, V.Flex(Field("http://localhost:11434/v1", ep, false, v => Set("base:local", v), double.NaN)),
                V.Button(V.Box(V.T("Ollama", 11, FontWeights.Medium, t.Primary), V.P(8, 4), t.P(0.1), 5), () => { Set("base:local", "http://localhost:11434/v1"); Rerender(); }),
                V.Button(V.Box(V.T("LM Studio", 11, FontWeights.Medium, t.Primary), V.P(8, 4), t.P(0.1), 5), () => { Set("base:local", "http://localhost:1234/v1"); Rerender(); })), Cross.Stretch));
            var l2 = V.T("Model:", 12, FontWeights.Medium, t.Primary); l2.Width = 110;
            var models = _fetched ?? new List<string> { model };
            if (!models.Contains(model)) models.Insert(0, model);
            var scan = V.Button(V.Box(V.H(4, Sym.Icon("arrow.clockwise", 11, t.Primary), V.T("Scan Models", 10.5, FontWeights.Medium, t.Primary)), V.P(8, 3), t.P(0.1), 5), () => FetchModels("local"));
            s.Children.Add(V.Self(V.H(8, l2, V.Flex(PopUp(model, models, v => { Set("ai_model_local", v); Rerender(); }, double.NaN)), scan), Cross.Stretch));
            if (_fetchStatus.Length > 1) s.Children.Add(V.T(_fetchStatus, 10.5, FontWeights.Medium, _fetchStatus.StartsWith("✓") ? t.SysGreen : t.SysOrange));
            return V.Self(V.Box(s, V.P(16), t.ControlBackground, 8, t.P(0.08), 1), Cross.Stretch);
        }

        // ── Connect with Phone / Team / Cloud GPU ──────────────────────
        UIElement HeroCard(string icon, string title, string subtitle, UIElement body)
        {
            var t = Theme.Current;
            var head = V.H(12, V.Size(V.Box(Sym.Icon(icon, 18, t.Primary), V.P(0), t.P(0.08), 10), 40, 40), V.VLead(2, V.T(title, 15, FontWeights.SemiBold, t.Primary), V.Wrap(V.T(subtitle, 11.5, FontWeights.Normal, t.Secondary), TextAlignment.Left)));
            var s = V.VLead(14, V.Self(head, Cross.Stretch), body); s.Align = Cross.Stretch;
            return V.Self(V.Box(s, V.P(18), t.ControlBackground, 12, t.P(0.08), 1), Cross.Stretch);
        }

        UIElement Note(string text)
        {
            var t = Theme.Current;
            return V.Self(V.Box(V.H(8, V.Self(Sym.Icon("info.circle", 12, t.SysOrange), Cross.Start), V.Flex(V.Wrap(V.T(text, 11.5, FontWeights.Normal, t.Secondary), TextAlignment.Left))), V.P(12, 9), t.Op(t.SysOrange, 0.08), 8), Cross.Stretch);
        }

        UIElement PhoneTab()
        {
            return HeroCard("qrcode", "Mobile Connect 2.0", "Remote Chat, File/Camera uploads, Live Preview, Git controls, Terminal, Voice Dictation, and Push.",
                Note("The phone companion server is not available in the Windows build yet. Pairing, QR code and the 6-digit PIN will appear here once it ships."));
        }

        UIElement TeamTab()
        {
            var t = Theme.Current;
            var s = V.VLead(10, V.H(8, V.Button(V.Box(V.H(6, Sym.Icon("plus", 11, Brushes.White, FontWeights.SemiBold), V.T("Start Session", 12, FontWeights.SemiBold, Brushes.White)), V.P(12, 6), t.Accent, 6), null),
                V.Button(V.Box(V.H(6, Sym.Icon("link", 11, t.Primary), V.T("Join with Room Code", 12, FontWeights.Medium, t.Primary)), V.P(12, 6), t.P(0.1), 6), null)),
                Note("Realtime CRDT collaboration (rooms, live cursors, AI teammate & follow mode) is not available in the Windows build yet."));
            s.Align = Cross.Stretch;
            return HeroCard("person.2", "Realtime Collaboration", "Share a room code, edit together with live cursors, and bring the MicroCode AI teammate into the session.", s);
        }

        UIElement CloudGPUTab()
        {
            var t = Theme.Current;
            var tabs = V.H(2, V.Box(V.T("GPU Cluster", 11.5, FontWeights.SemiBold, t.Primary), V.P(10, 5), t.P(0.1), 6), V.Box(V.T("GPU Wallet (Pay As You Go)", 11.5, FontWeights.Medium, t.Secondary), V.P(10, 5), Brushes.Transparent, 6),
                V.Box(V.T("Git Ingest (10Gbps)", 11.5, FontWeights.Medium, t.Secondary), V.P(10, 5), Brushes.Transparent, 6), V.Box(V.T("SSH / Custom", 11.5, FontWeights.Medium, t.Secondary), V.P(10, 5), Brushes.Transparent, 6));
            var s = V.VLead(12, V.Box(tabs, V.P(2), t.P(0.04), 8), V.T("Select a GPU instance. Rates are billed per minute from your GPU Wallet.", 11.5, FontWeights.Normal, t.Secondary),
                Note("Sign in to Dotmini Cloud (Account & License) to list GPU instances and your wallet balance."));
            s.Align = Cross.Stretch;
            return HeroCard("cpu", "Dotmini Cloud GPU Hub", "High-performance compute clusters, persistent storage, and dataset ingestion.", s);
        }

        // ── Skills ─────────────────────────────────────────────────────
        string _skillQuery = "";
        UIElement SkillsTab()
        {
            var t = Theme.Current;
            var all = SkillStore.Skills;
            int active = all.Count(s => Get("skill_enabled_" + s.Path.ToLowerInvariant(), true));
            var head = V.H(12, V.Size(V.Box(Sym.Icon("square.stack.3d.up", 18, t.Primary), V.P(0), t.P(0.08), 10), 40, 40),
                V.Flex(V.VLead(2, V.H(8, V.T("Agent Skills Engine", 15, FontWeights.SemiBold, t.Primary), V.Box(V.T(active + " / " + all.Count + " Active", 10, FontWeights.SemiBold, t.SysGreen), V.P(6, 2), t.Op(t.SysGreen, 0.12), 4)),
                    V.T("Live-loaded real instruction toolkits from Antigravity, Codex, Science & MCP on disk", 11.5, FontWeights.Normal, t.Secondary))));
            Func<string, string, Action, UIElement> btn = (icon, label, a) => V.Button(V.Box(V.H(5, Sym.Icon(icon, 11, t.Primary), V.T(label, 12, FontWeights.Medium, t.Primary)), V.P(10, 5), t.P(0.08), 6), a);
            var actions = V.H(8, btn("arrow.clockwise", "Rescan Disk", () => { SkillStore.Rescan(); Rerender(); }),
                btn("square.and.arrow.down", "Import Skill / .md...", () => { var d = new Microsoft.Win32.OpenFileDialog { Filter = "Skill (*.md)|*.md" }; if (d.ShowDialog() == true) { SkillStore.Import(d.FileName); Rerender(); } }),
                V.Sp(), btn("checkmark", "Enable All", () => { foreach (var s in all) Set("skill_enabled_" + s.Path.ToLowerInvariant(), true); Rerender(); }),
                btn("xmark", "Disable All", () => { foreach (var s in all) Set("skill_enabled_" + s.Path.ToLowerInvariant(), false); Rerender(); }));
            TextBox search;
            var sf = Styles.Field("Search skills…", 12, t.Primary, t.Secondary, out search);
            search.Text = _skillQuery;
            search.TextChanged += delegate { _skillQuery = search.Text; };
            search.KeyUp += delegate { Rerender(); var tb = search; };
            var list = V.VLead(6); list.Align = Cross.Stretch;
            var shown = all.Where(s => _skillQuery.Length == 0 || (s.Name + " " + s.Description).IndexOf(_skillQuery, StringComparison.OrdinalIgnoreCase) >= 0).ToList();
            if (shown.Count == 0)
                list.Children.Add(V.Box(V.Vs(6, Sym.Icon("magnifyingglass", 18, t.S(0.6)), V.T(all.Count == 0 ? "No skills found. Put SKILL.md folders in " + SkillStore.UserSkillsDir : "No skills match your search", 12, FontWeights.Normal, t.Secondary)), V.P(0, 24), null, 0));
            foreach (var sk in shown)
            {
                var skill = sk;
                string k = "skill_enabled_" + sk.Path.ToLowerInvariant();
                var check = Checkbox("", k, true);
                list.Children.Add(V.Self(V.Box(V.H(10, check, V.Flex(V.VLead(2, V.H(6, V.T(sk.Name, 12.5, FontWeights.SemiBold, t.Primary), V.Box(V.T(sk.Source, 9, FontWeights.SemiBold, t.Secondary), V.P(5, 1.5), t.P(0.08), 3)),
                    V.T(sk.Description, 11, FontWeights.Normal, t.Secondary))), V.Button(Sym.Icon("folder", 11, t.Secondary), () => Process.Start("explorer.exe", "/select,\"" + skill.Path + "\""))), V.P(12, 8), t.ControlBackground, 8, t.P(0.06), 1), Cross.Stretch));
            }
            var root = V.VLead(14, V.Self(head, Cross.Stretch), V.Self(actions, Cross.Stretch), V.Self(V.Box(V.H(6, Sym.Icon("magnifyingglass", 11, t.Secondary), V.Flex(sf)), V.P(10, 6), t.P(0.05), 7), Cross.Stretch), list);
            root.Align = Cross.Stretch;
            return root;
        }

        // ── MCP / Tools / Extensions / Account / About ─────────────────
        UIElement MCPTab()
        {
            var t = Theme.Current;
            Func<string, string, UIElement> stat = (label, value) => V.VLead(2, V.T(label, 9, FontWeights.SemiBold, t.Secondary), V.Mono(value, 16, FontWeights.Bold, t.Primary));
            var tools = new WrapPanel();
            foreach (var n in new[] { "read_file", "write_file", "list_directory", "search_code", "run_terminal", "git_status", "git_diff", "get_diagnostics" })
            {
                var chip = V.Box(V.Mono(n, 10, FontWeights.Medium, t.P(0.85)), V.P(7, 3), t.P(0.06), 5);
                chip.Margin = new Thickness(0, 0, 6, 6);
                tools.Children.Add(chip);
            }
            var s = V.VLead(12,
                V.Self(V.H(8, Sym.Icon("server.rack", 13, t.Primary), V.T("MCP Protocol Server", 13, FontWeights.SemiBold, t.Primary), V.Box(V.H(4, V.Dot(6, t.SysGray), V.T("Stopped", 10, FontWeights.Medium, t.Secondary)), V.P(6, 2), t.P(0.06), 4), V.Sp(),
                    V.Button(V.Box(V.T("Start", 11.5, FontWeights.Medium, t.Primary), V.P(12, 4), t.P(0.1), 6), () => MessageBox.Show(this, "The built-in MCP server is not available in the Windows build yet.", "MCP Servers"))), Cross.Stretch),
                V.Wrap(V.T("Model Context Protocol server exposes workspace tools (read, write, search, terminal, git) to external AI clients like Claude Desktop, Cursor, and ChatGPT plugins.", 11, FontWeights.Normal, t.Secondary), TextAlignment.Left),
                V.H(24, stat("Requests", "0"), stat("Clients", "0"), stat("Tools", "8")),
                V.T("Available Tools", 10, FontWeights.SemiBold, t.Secondary), V.Self(tools, Cross.Stretch),
                V.T("Recent Activity", 10, FontWeights.SemiBold, t.Secondary), V.T("No requests yet", 11, FontWeights.Normal, t.S(0.7)));
            s.Align = Cross.Stretch;
            return V.Self(V.Box(s, V.P(16), t.ControlBackground, 12, t.P(0.08), 1), Cross.Stretch);
        }

        UIElement ToolsTab()
        {
            var root = V.VLead(12, SectionHeader("Code Execution"), Checkbox("Auto-run on save", "autoRunOnSave", false), Checkbox("Clear console before run", "clearConsoleBeforeRun", true),
                SectionHeader("Git"), Checkbox("Auto-fetch on open", "gitAutoFetch", true), Checkbox("Show commit message suggestions", "gitCommitSuggestions", true),
                SectionHeader("Refactoring"), Checkbox("Use AI for refactoring", "aiRefactoring", true));
            return root;
        }

        UIElement ExtensionsTab()
        {
            var t = Theme.Current;
            string dir = Path.Combine(Defaults.Dir, "Extensions");
            var installed = Directory.Exists(dir) ? Directory.GetFileSystemEntries(dir).ToList() : new List<string>();
            Func<string, string, Action, UIElement> btn = (icon, label, a) => V.Button(V.Box(V.H(5, Sym.Icon(icon, 11, t.Primary), V.T(label, 12, FontWeights.Medium, t.Primary)), V.P(10, 5), t.P(0.08), 6), a);
            var actions = V.H(8, btn("arrow.down.circle", "Install File", () =>
            {
                var d = new Microsoft.Win32.OpenFileDialog { Filter = "Extensions (*.vsix;*.mcx;*.zip)|*.vsix;*.mcx;*.zip" };
                if (d.ShowDialog() == true) { Directory.CreateDirectory(dir); File.Copy(d.FileName, Path.Combine(dir, Path.GetFileName(d.FileName)), true); Rerender(); }
            }), btn("plus", "New Starter", null), btn("folder", "All Types", () => { Directory.CreateDirectory(dir); Process.Start("explorer.exe", dir); }));
            var list = V.VLead(6); list.Align = Cross.Stretch;
            if (installed.Count == 0) list.Children.Add(V.Box(V.Vs(6, Sym.Icon("puzzlepiece.extension", 22, t.S(0.6)), V.T("No extensions installed", 12, FontWeights.Normal, t.Secondary)), V.P(0, 24), null, 0));
            foreach (var f in installed) list.Children.Add(V.Self(V.Box(V.H(10, Sym.Icon("puzzlepiece.extension", 13, t.Accent), V.T(Path.GetFileName(f), 12.5, FontWeights.Medium, t.Primary), V.Sp()), V.P(12, 8), t.ControlBackground, 8), Cross.Stretch));
            var root = V.VLead(14, HeroCard("puzzlepiece.extension.fill", "Extension Hub", "Install, manage, and mount community and official extensions.", actions), list);
            root.Align = Cross.Stretch;
            return root;
        }

        // ── Dotmini Cloud panel (AI & Agent → Dotmini Cloud) ───────────────────
        UIElement CloudPanel()
        {
            var t = Theme.Current;
            DotminiCloud.EnsureFresh();
            var s = V.VLead(14); s.Align = Cross.Stretch;
            var tile = V.Size(V.Box(Sym.Icon("sparkles", 12, t.Primary), V.P(0), t.P(0.08), 5), 22, 22);
            var refresh = SmallBtn(DotminiCloud.Refreshing ? "Refreshing…" : "Refresh Catalog", null, () => RunAsync(async () => { await DotminiCloud.Refresh(true); await DotminiAuth.RefreshEntitlement(); }));
            s.Children.Add(V.Self(V.H(10, tile, V.VLead(1, V.T("Dotmini Cloud Subscription", 13, FontWeights.SemiBold, t.Primary), V.Mono("microcode.dotmini.net/v1", 10, FontWeights.Normal, t.Secondary)), V.Sp(), V.T(DotminiCloud.Source, 10, FontWeights.Normal, t.Secondary), refresh), Cross.Stretch));
            s.Children.Add(V.Self(V.Line(t.Op(t.Separator, 0.6), true), Cross.Stretch));
            string cur = Get("ai_model_omni", AIConfig.ModelFor("omni"));
            var cm = DotminiCloud.Find(cur);
            string label = DotminiCloud.Models.Count == 0 ? "Fetching live models from microcode.dotmini.net/v1…" : cm != null ? cm.Name + " (" + cm.Rate + ")" : AIConfig.FormatModelName(cur);
            var picker = V.Button(V.Box(V.H(6, V.Flex(V.T(label, 13, FontWeights.Normal, t.Primary)), Sym.Icon("chevron.up.chevron.down", 9, t.Secondary, FontWeights.SemiBold)), V.P(9, 3), t.P(0.12), 5, t.P(0.06), 0.5), null);
            picker.MenuItems = () => DotminiCloud.ByProvider().Select(g => MenuItemSpec.Sub(DotminiCloud.ProviderName(g.Key) + " (" + g.Value.Count + ")", null,
                g.Value.Select(m => { var id = m.Id; return new MenuItemSpec { Title = m.Name + " (" + m.Rate + ")", Checked = id == cur, Action = () => { Set("ai_model_omni", id); Rerender(); } }; }).ToList())).ToList();
            var lbl = V.T("Active Model:", 12, FontWeights.Medium, t.Secondary); lbl.Width = 110;
            s.Children.Add(V.Self(V.H(12, lbl, V.Flex(picker)), Cross.Stretch));
            var status = V.H(10);
            var sess = DotminiAuth.Session; var e = DotminiAuth.Entitlement;
            if (sess != null)
            {
                status.Children.Add(V.Dot(6, t.P(e.IsPaid || e.TotalAvailableTHB > 0 ? 0.85 : 0.45)));
                status.Children.Add(V.T(sess.Email + " · Plan: " + e.PlanUpper, 11.5, FontWeights.SemiBold, t.Primary));
                if (e.Loaded)
                {
                    var tb = V.T("(Available: " + e.FormattedAvailable + " · Plan: " + e.FormattedPlanPool + " + AI Top-Up: ฿" + e.TopupTHB.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture) + ")", 11, FontWeights.Normal, t.Secondary);
                    tb.TextTrimming = TextTrimming.CharacterEllipsis;
                    status.Children.Add(V.Shrink(tb));
                }
                status.Children.Add(V.Sp());
                status.Children.Add(SmallBtn("Top Up / Plans", null, () => { _tab = 6; Render(); _scroll.ScrollToTop(); }));
                status.Children.Add(SmallBtn("Web Console", null, () => OpenUrl(DotminiAuth.PortalUrl("/dashboard"))));
            }
            else if (DotminiPlatformKey.IsConfigured)
            {
                status.Children.Add(V.Dot(6, t.P(0.85)));
                status.Children.Add(V.T("Dotmini Cloud Platform Key Configured", 11.5, FontWeights.Medium, t.Secondary));
                status.Children.Add(V.Sp());
            }
            else
            {
                status.Children.Add(V.Dot(6, t.S(0.35)));
                var tb = V.T("Not signed in — sign in on microcode.dotmini.net (auto-syncs) or Account & License.", 11, FontWeights.Normal, t.Secondary);
                tb.TextTrimming = TextTrimming.CharacterEllipsis;
                status.Children.Add(V.Shrink(tb));
                status.Children.Add(V.Sp());
                status.Children.Add(SmallBtn("Sign In", null, () => { _tab = 6; Render(); _scroll.ScrollToTop(); }));
            }
            s.Children.Add(V.Self(V.Box(status, V.P(0, 2, 0, 0), null, 0), Cross.Stretch));
            return V.Self(V.Box(s, V.P(16), t.ControlBackground, 8, t.P(0.08), 1), Cross.Stretch);
        }

        // ── Account & License (MicroCodeLicenseSettingsView) ───────────────────
        string _email, _password = "", _displayName = "", _status = "", _checkout = "", _platformInput = "", _connectCode = "", _customTopup = "";
        bool _creating, _working, _checkingOut, _checkoutOk, _accountRefreshed;

        UIElement AccountTab()
        {
            if (_email == null) _email = Defaults.Str("dotminiUserEmail", "");
            LocalBridge.Start();
            if (!_accountRefreshed)
            {
                _accountRefreshed = true;
                RunAsync(async () =>
                {
                    await DotminiAuth.AccessToken(false);
                    await DotminiAuth.RefreshEntitlement();
                    if (DotminiPlatformKey.IsConfigured) await DotminiPlatformKey.Validate();
                });
            }
            var root = V.VLead(16); root.Align = Cross.Stretch;
            root.Children.Add(ServiceHeader());
            root.Children.Add(DotminiAuth.SignedIn ? AccountCard() : SignInCard());
            root.Children.Add(EntitlementCard());
            root.Children.Add(PlatformKeyCard());
            var t = Theme.Current;
            root.Children.Add(Card(V.Self(V.H(8, V.T("License Key:", 12, FontWeights.Medium, t.Primary), V.Flex(Field("XXXX-XXXX-XXXX-XXXX", AIConfig.KeyFor("license"), true, v => Set("key:license", v), double.NaN))), Cross.Stretch),
                V.T("Optional MicroCode license (sent as X-Dotmini-License with Dotmini Cloud requests). Saved with Save Changes.", 10.5, FontWeights.Normal, t.S(0.8))));
            return root;
        }

        UIElement ServiceHeader()
        {
            var t = Theme.Current;
            bool signed = DotminiAuth.SignedIn;
            var e = DotminiAuth.Entitlement;
            string planLabel = signed ? (string.IsNullOrWhiteSpace(e.Plan) ? "FREE PLAN" : e.Plan.Trim().ToUpperInvariant() + " PLAN") : "NOT SIGNED IN";
            var chip = V.Box(V.H(5, V.Dot(5.5, signed ? Theme.B(Color.FromArgb(217, 48, 209, 88)) : t.S(0.45)), V.Mono(planLabel, 10, FontWeights.SemiBold, t.Secondary)), V.P(7, 2), t.P(0.05), 4);
            var titleRow = V.H(8, V.T("Dotmini ID & Cloud Billing", 13.5, FontWeights.SemiBold, t.Primary), chip);
            if ((e.Role ?? "").ToLowerInvariant() == "admin") titleRow.Children.Add(V.Box(V.Mono("ADMIN", 9.5, FontWeights.SemiBold, t.SysOrange), V.P(6, 2), t.Op(t.SysOrange, 0.12), 4));
            var desc = V.Wrap(V.T("Sign in with Google or your Dotmini ID to sync Cloud AI credits, monthly subscriptions, and devices across MicroCode.", 11.5, FontWeights.Normal, t.Secondary), TextAlignment.Left);
            var tile = V.Size(V.Box(Sym.Icon("sparkles", 18, t.Primary), V.P(0), t.P(0.06), 8), 38, 38);
            var row = V.H(14, V.Self(tile, Cross.Start), V.Flex(V.VLead(3, titleRow, desc)), V.Self(SmallBtn("Web Portal", "arrow.up.right.square", () => OpenUrl(DotminiAuth.PortalUrl("/dashboard"))), Cross.Start));
            return Card(V.Self(row, Cross.Stretch));
        }

        UIElement StatusText(string text, bool ok)
        {
            var t = Theme.Current;
            string l = (text ?? "").ToLowerInvariant();
            bool bad = !ok && (l.Contains("fail") || l.Contains("invalid") || l.Contains("could not") || l.Contains("rejected") || l.Contains("ไม่") || l.Contains("error"));
            return V.Wrap(V.T(text, 11, FontWeights.Medium, ok ? t.SysGreen : bad ? t.SysRed : t.Secondary), TextAlignment.Left);
        }

        UIElement AccountCard()
        {
            var t = Theme.Current;
            var s = DotminiAuth.Session;
            string email = s.Email ?? "";
            var letter = V.T((email.Length > 0 ? email.Substring(0, 1) : "U").ToUpperInvariant(), 14, FontWeights.SemiBold, t.Primary);
            letter.HorizontalAlignment = HorizontalAlignment.Center;
            var avatar = new Border { Width = 36, Height = 36, CornerRadius = new CornerRadius(18), Background = t.P(0.08), Child = letter };
            var info = V.VLead(2, V.T(email.Length > 0 ? email : "Signed in with Dotmini ID", 13, FontWeights.SemiBold, t.Primary),
                V.H(6, Sym.Icon("checkmark.circle.fill", 10.5, t.SysGreen), V.T("Authenticated session active (Windows DPAPI)", 11, FontWeights.Normal, t.Secondary)));
            var sync = SmallBtn(_working ? "Syncing…" : "Sync", "arrow.clockwise", () =>
            {
                if (_working) return;
                _working = true; Rerender();
                RunAsync(async () => { await DotminiAuth.AccessToken(true); await DotminiAuth.RefreshEntitlement(); _working = false; });
            });
            var outTb = V.T("Sign Out", 11.5, FontWeights.Medium, t.Op(t.SysRed, 0.9));
            var signOut = V.Button(V.Box(outTb, V.P(9, 3.5), t.P(0.09), 5, t.P(0.12), 0.5), () => { DotminiAuth.SignOut(); _status = "Signed out from this PC."; Rerender(); });
            var kids = new List<UIElement> { V.Self(V.H(12, avatar, V.Flex(info), sync, signOut), Cross.Stretch) };
            if (AIConfig.Mode != "cloud")
                kids.Add(V.Self(V.H(8, Sym.Icon("sparkles", 11, t.Accent), V.T("AI Agent is using " + AIConfig.BadgeTitle + ". Switch it to your Dotmini Cloud credits?", 11.5, FontWeights.Normal, t.Secondary), V.Sp(),
                    SmallBtn("Use Dotmini Cloud AI now", null, () => { AIConfig.Mode = "cloud"; _pending.Remove("ai_key_mode"); Defaults.Flush(); _app.Notify("agentBar"); _status = "สลับ AI Agent ไปใช้ Dotmini Cloud แล้ว (โมเดล " + AIConfig.ModelDisplayName + ")"; Rerender(); })), Cross.Stretch));
            if (_status.Length > 0) kids.Add(StatusText(_status, _status.StartsWith("สลับ") || _status.StartsWith("Signed in")));
            return Card(kids.ToArray());
        }

        UIElement SignInCard()
        {
            var t = Theme.Current;
            var kids = new List<UIElement>();
            if (DotminiAuth.ReauthReason.Length > 0)
                kids.Add(V.Self(V.Box(V.H(8, Sym.Icon("exclamationmark.triangle.fill", 12, t.SysOrange), V.Wrap(V.T(DotminiAuth.ReauthReason, 11.5, FontWeights.Medium, t.Primary), TextAlignment.Left)), V.P(10), t.Op(t.SysOrange, 0.12), 8, t.Op(t.SysOrange, 0.28), 1), Cross.Stretch));
            var g = new TextBlock { Text = "G", FontSize = 12, FontWeight = FontWeights.Black, Foreground = new LinearGradientBrush(new GradientStopCollection { new GradientStop(Color.FromRgb(66, 133, 245), 0), new GradientStop(Color.FromRgb(52, 168, 83), 0.4), new GradientStop(Color.FromRgb(250, 188, 5), 0.7), new GradientStop(Color.FromRgb(235, 66, 54), 1) }, 45), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            var mark = new Border { Width = 19, Height = 19, CornerRadius = new CornerRadius(9.5), Background = Brushes.White, Child = g };
            var gRow = V.H(8, mark, V.T("Continue with Google", 12.5, FontWeights.SemiBold, t.Primary)); gRow.HorizontalAlignment = HorizontalAlignment.Center;
            var google = V.Button(V.Size(V.Box(gRow, V.P(0), t.P(0.08), 7, t.P(0.16), 1), double.NaN, 34), () =>
            {
                bool ok = DotminiAuth.StartBrowserSignIn("google");
                _status = ok ? "Opened Google sign-in in your browser. Finish there — MicroCode picks up the session automatically."
                             : "Could not start the local sign-in bridge on 127.0.0.1:" + LocalBridge.Port + " (" + LocalBridge.Error + "). Sign in with email below instead.";
                Rerender();
            });
            var bRow = V.H(6, Sym.Icon("safari", 12.5, t.Primary), V.T("Sign in via Web Browser", 12, FontWeights.Medium, t.Primary));
            var browser = V.Button(V.Size(V.Box(bRow, V.P(14, 0), t.P(0.04), 7, t.P(0.10), 1), double.NaN, 34), () =>
            {
                DotminiAuth.StartBrowserSignIn(null);
                _status = "Opened default web browser. Completing sign-in will sync back to MicroCode automatically.";
                Rerender();
            });
            browser.ToolTip = "Use your default browser if you are already signed in to microcode.dotmini.net";
            kids.Add(V.Self(V.H(10, V.Flex(google), browser), Cross.Stretch));
            kids.Add(V.Self(V.H(10, V.Flex(V.Line(t.P(0.08), true)), V.T(_creating ? "or create a Dotmini ID with email" : "or sign in with email", 10.5, FontWeights.Medium, t.Secondary), V.Flex(V.Line(t.P(0.08), true))), Cross.Stretch));
            if (_creating) kids.Add(V.Self(Field("Display Name (optional)", _displayName, false, v => _displayName = v, double.NaN), Cross.Stretch));
            Action submit = SubmitAuth;
            var emailF = Field("Email address", _email, false, v => _email = v, double.NaN, submit);
            var passF = Field("Password", _password, true, v => _password = v, double.NaN, submit);
            var go = PrimaryBtn(_working ? (_creating ? "Creating…" : "Signing in…") : (_creating ? "Create Account" : "Sign In"), submit);
            kids.Add(V.Self(V.H(8, V.Flex(emailF), V.Flex(passF), go), Cross.Stretch));
            var toggle = V.Button(V.T(_creating ? "Already have an account? Sign in" : "Create a new account", 11.5, FontWeights.Medium, t.Accent), () => { _creating = !_creating; _status = ""; Rerender(); });
            var links = V.H(8, toggle, V.Sp());
            if (!_creating) links.Children.Add(V.Button(V.T("Forgot password?", 11.5, FontWeights.Medium, t.Accent), () =>
            {
                string em = (_email ?? "").Trim();
                if (em.Length == 0) { _status = "กรอกอีเมลก่อน แล้วกด Forgot password?"; Rerender(); return; }
                _working = true; Rerender();
                Task.Run(() => DotminiAuth.SendPasswordReset(em)).ContinueWith(tk => Dispatcher.BeginInvoke(new Action(() =>
                {
                    _working = false;
                    _status = tk.IsFaulted ? tk.Exception.GetBaseException().Message : "หากอีเมลนี้มีบัญชี ระบบได้ส่งลิงก์รีเซ็ตรหัสผ่านไปแล้ว";
                    Rerender();
                })));
            }));
            kids.Add(V.Self(links, Cross.Stretch));
            if (_status.Length > 0) kids.Add(StatusText(_status, false));
            return Card(kids.ToArray());
        }

        void SubmitAuth()
        {
            string em = (_email ?? "").Trim(), pw = _password ?? "", dn = _displayName ?? "";
            if (_working || em.Length == 0 || pw.Length == 0) { if (!_working) { _status = "กรอกอีเมลและรหัสผ่านก่อน"; Rerender(); } return; }
            bool creating = _creating;
            _working = true; _status = ""; Rerender();
            Task.Run(async () =>
            {
                if (creating)
                {
                    var s = await DotminiAuth.SignUp(em, pw, dn);
                    return s == null ? "ส่งอีเมลยืนยันไปที่ " + em + " แล้ว กรุณากดลิงก์ในอีเมล จากนั้นกลับมากด Sign In" : "Signed in securely.";
                }
                await DotminiAuth.SignIn(em, pw);
                return "Signed in securely.";
            }).ContinueWith(tk => Dispatcher.BeginInvoke(new Action(() =>
            {
                _working = false;
                _status = tk.IsFaulted ? tk.Exception.GetBaseException().Message : tk.Result;
                if (!tk.IsFaulted) { _password = ""; if (DotminiAuth.SignedIn) _creating = false; _app.Notify("agentBar"); }
                Rerender();
            })));
        }

        UIElement EntitlementCard()
        {
            var t = Theme.Current;
            var e = DotminiAuth.Entitlement;
            bool signed = DotminiAuth.SignedIn;
            string active = (e.Plan ?? "").ToLowerInvariant();
            var verify = SmallBtn(_checkingOut ? "Verifying…" : "Verify Payment", "checkmark.seal", () =>
            {
                if (!signed || _checkingOut) return;
                _checkingOut = true; Rerender();
                Task.Run(() => DotminiAuth.VerifyLatestPayment()).ContinueWith(tk => Dispatcher.BeginInvoke(new Action(() =>
                {
                    _checkingOut = false;
                    if (tk.IsFaulted) { _checkout = tk.Exception.GetBaseException().Message; _checkoutOk = false; }
                    else { _checkout = tk.Result.Value; _checkoutOk = tk.Result.Key; }
                    Rerender();
                })));
            });
            if (!signed) verify.Opacity = 0.45;
            var kids = new List<UIElement>
            {
                V.Self(V.H(8, V.Flex(V.VLead(2, V.T("Cloud AI Credit & Monthly Plans", 13, FontWeights.SemiBold, t.Primary),
                    V.Wrap(V.T("Token-metered billing across Claude, GPT, Gemini, DeepSeek, and Omni AI. Top-up wallet credits never expire.", 11.5, FontWeights.Normal, t.Secondary), TextAlignment.Left))), V.Self(verify, Cross.Start)), Cross.Stretch)
            };
            if (e.Loaded)
            {
                Func<string, string, UIElement> metric = (label, value) => V.VLead(2, V.T(label, 10, FontWeights.Medium, t.Secondary), V.T(value, 14, FontWeights.SemiBold, t.Primary));
                var grid = new UniformGrid { Rows = 1, Columns = 4 };
                grid.Children.Add(metric("Available Credit", e.FormattedAvailable));
                grid.Children.Add(metric("Monthly Plan Pool", e.FormattedPlanPool));
                grid.Children.Add(metric("Top-Up Wallet", "฿" + e.TopupTHB.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture)));
                grid.Children.Add(metric("Metered Tokens", e.TotalTokens.ToString("N0")));
                var strip = V.VLead(10, V.Self(grid, Cross.Stretch)); strip.Align = Cross.Stretch;
                if (e.CreditLimitTHB > 0)
                {
                    double ratio = Math.Max(0, Math.Min(1, e.CreditRemainingTHB / e.CreditLimitTHB));
                    var fill = new Border { CornerRadius = new CornerRadius(2.5), Background = ratio > 0.2 ? t.Accent : (Brush)t.SysOrange, HorizontalAlignment = HorizontalAlignment.Left };
                    var bar = new Grid { Height = 5 };
                    bar.Children.Add(new Border { CornerRadius = new CornerRadius(2.5), Background = t.P(0.08) });
                    bar.Children.Add(fill);
                    bar.SizeChanged += delegate { fill.Width = Math.Max(4, bar.ActualWidth * ratio); };
                    strip.Children.Add(V.Self(bar, Cross.Stretch));
                    strip.Children.Add(V.Wrap(V.T(string.Format(System.Globalization.CultureInfo.InvariantCulture, "฿{0:0.00} used of ฿{1:0} monthly plan pool · Automatically draws from Top-Up Wallet when monthly pool reaches ฿0.00.", e.CreditUsedTHB, e.CreditLimitTHB), 10.5, FontWeights.Normal, t.Secondary), TextAlignment.Left));
                }
                kids.Add(V.Self(V.Box(strip, V.P(12), t.P(0.03), 8, t.P(0.06), 1), Cross.Stretch));
            }
            kids.Add(V.Self(V.H(8, V.T("Monthly Subscriptions", 11.5, FontWeights.SemiBold, t.Primary), V.Sp(), V.T("PromptPay QR / Credit Card via Beam Checkout", 10.5, FontWeights.Normal, t.Secondary)), Cross.Stretch));
            var tiles = new UniformGrid { Rows = 1, Columns = 4 };
            Action<string, string, string, string, bool> tileFn = (title, price, quota, key, current) =>
            {
                var head = V.H(4, V.T(title, 12, FontWeights.SemiBold, t.Primary), V.Sp());
                if (current) head.Children.Add(V.Box(V.Mono("ACTIVE", 8.5, FontWeights.Bold, t.SysGreen), V.P(5, 2), t.Op(t.SysGreen, 0.18), 8));
                var col = V.VLead(6, V.Self(head, Cross.Stretch), V.H(2, V.T(price, 15, FontWeights.Bold, t.Primary), V.T("/mo", 11, FontWeights.Normal, t.Secondary)),
                    V.T(quota, 10.5, FontWeights.Normal, t.Secondary), current ? (UIElement)V.T("Current Plan", 11, FontWeights.Medium, t.SysGreen) : SmallBtn("Subscribe", null, () => StartCheckout(key, null, title)));
                col.Align = Cross.Stretch;
                var card = V.Box(col, V.P(10), current ? t.Op(t.SysGreen, 0.06) : t.P(0.03), 8, current ? t.Op(t.SysGreen, 0.35) : t.P(0.08), 1);
                card.Margin = new Thickness(0, 0, 10, 0);
                tiles.Children.Add(card);
            };
            tileFn("Lite", "฿179", "฿179 AI Credit Pool", "microai_lite", active == "lite" || active == "microai_lite");
            tileFn("Pro", "฿529", "฿529 AI Credit Pool", "microai_pro", active == "pro" || active == "microai_pro");
            tileFn("Advanced", "฿990", "฿990 AI Credit Pool", "microai_advanced", active == "advanced" || active == "microai_advanced");
            tileFn("Bundle Pro", "฿1,365", "฿1,365 Credit + IDE", "bundle_pro", active == "bundle_pro" || active == "bundle");
            kids.Add(V.Self(tiles, Cross.Stretch));
            var topRow = V.H(8, V.T("Top-Up Wallet:", 11.5, FontWeights.Medium, t.Secondary));
            foreach (var amt in new[] { new[] { "+฿100", "ai_topup_100" }, new[] { "+฿300", "ai_topup_300" }, new[] { "+฿500", "ai_topup_500" }, new[] { "+฿1,000", "ai_topup_1000" } })
            {
                var a = amt;
                topRow.Children.Add(SmallBtn(a[0], null, () => StartCheckout(a[1], null, a[0])));
            }
            topRow.Children.Add(V.Sp());
            topRow.Children.Add(Field("Custom ฿ (≥20)", _customTopup, false, v => _customTopup = v, 108));
            topRow.Children.Add(SmallBtn("Top Up", null, () =>
            {
                double amt;
                if (!double.TryParse((_customTopup ?? "").Trim(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out amt) || amt < 20) { _checkout = "กรุณาระบุยอดเติมเครดิต Cloud AI ขั้นต่ำ ฿20"; _checkoutOk = false; Rerender(); return; }
                StartCheckout("ai_topup_custom", amt, "฿" + (int)amt);
            }));
            kids.Add(V.Self(V.Box(topRow, V.P(12, 9), t.P(0.03), 8, t.P(0.06), 1), Cross.Stretch));
            if (_checkout.Length > 0) kids.Add(StatusText(_checkout, _checkoutOk));
            return Card(kids.ToArray());
        }

        void StartCheckout(string plan, double? amount, string title)
        {
            if (!DotminiAuth.SignedIn) { _checkout = "กรุณาเข้าสู่ระบบบัญชี MicroCode ก่อนทำการสมัครแพ็กเกจหรือเติมเครดิต"; _checkoutOk = false; Rerender(); return; }
            if (_checkingOut) return;
            _checkingOut = true; _checkoutOk = false;
            _checkout = "กำลังสร้างลิงก์ชำระเงิน (" + title + ") ผ่าน Beam Checkout…";
            Rerender();
            Task.Run(() => DotminiAuth.CreateCheckout(plan, amount)).ContinueWith(tk => Dispatcher.BeginInvoke(new Action(() =>
            {
                _checkingOut = false;
                if (tk.IsFaulted) _checkout = tk.Exception.GetBaseException().Message;
                else { _checkout = "เปิดหน้าชำระเงินแล้ว กรุณาสแกน QR PromptPay หรือชำระผ่านบัตร แล้วกด Verify Payment"; OpenUrl(tk.Result); }
                Rerender();
            })));
        }

        UIElement PlatformKeyCard()
        {
            var t = Theme.Current;
            var head = V.H(8, V.Flex(V.VLead(2, V.T("Dotmini Platform (Unified Omni AI + MicroCode)", 13, FontWeights.SemiBold, t.Primary),
                V.Wrap(V.T("SHA-256 hashed developer credential shared across Omni AI, MicroCode Cloud Runtime, and API Gateway. Stored only in Windows DPAPI.", 11.5, FontWeights.Normal, t.Secondary), TextAlignment.Left))));
            bool busy = DotminiPlatformKey.Provisioning || DotminiPlatformKey.Validating;
            if (DotminiAuth.SignedIn)
                head.Children.Add(V.Self(SmallBtn(DotminiPlatformKey.Provisioning ? "Connecting…" : DotminiPlatformKey.IsConfigured ? "Rotate Key" : "1-Click Auto-Connect", null, () => { if (!busy) RunAsync(async () => { if (await DotminiPlatformKey.AutoConnect()) await DotminiCloud.Refresh(true); }); }), Cross.Start));
            head.Children.Add(V.Self(SmallBtn("Open Platform", null, () => OpenUrl(DotminiPlatformKey.PlatformOrigin)), Cross.Start));
            var kids = new List<UIElement> { V.Self(head, Cross.Stretch) };
            if (DotminiPlatformKey.IsConfigured)
            {
                var row = V.H(8, Sym.Icon("checkmark.shield", 11, t.SysGreen), V.Mono(DotminiPlatformKey.Masked, 11, FontWeights.Medium, t.Primary));
                if (DotminiPlatformKey.AvailableTHB.HasValue) row.Children.Add(V.T(string.Format(System.Globalization.CultureInfo.InvariantCulture, "Shared Pool: ฿{0:0.00}", DotminiPlatformKey.AvailableTHB.Value), 11, FontWeights.Medium, t.Secondary));
                if (DotminiPlatformKey.OmniPlan.Length > 0 || DotminiPlatformKey.MicroCodePlan.Length > 0)
                    row.Children.Add(V.T("Omni: " + (DotminiPlatformKey.OmniPlan.Length == 0 ? "FREE" : DotminiPlatformKey.OmniPlan) + " · MC: " + (DotminiPlatformKey.MicroCodePlan.Length == 0 ? "FREE" : DotminiPlatformKey.MicroCodePlan), 11, FontWeights.Medium, t.Secondary));
                row.Children.Add(V.Sp());
                row.Children.Add(SmallBtn(DotminiPlatformKey.Validating ? "Checking…" : "Verify", null, () => { if (!busy) RunAsync(() => DotminiPlatformKey.Validate()); }));
                var rm = V.Button(V.Box(V.T("Remove", 11.5, FontWeights.Medium, t.Op(t.SysRed, 0.9)), V.P(9, 3.5), t.P(0.09), 5, t.P(0.12), 0.5), () => { DotminiPlatformKey.Remove(); _app.Notify("agentBar"); Rerender(); });
                row.Children.Add(rm);
                kids.Add(V.Self(row, Cross.Stretch));
            }
            else
            {
                Action save = () => { if (DotminiPlatformKey.Save(_platformInput)) { _platformInput = ""; _app.Notify("agentBar"); RunAsync(() => DotminiPlatformKey.Validate()); } Rerender(); };
                kids.Add(V.Self(V.H(8, V.Flex(Field("sk-dotmini-live-… or mci-live-…", _platformInput, true, v => _platformInput = v, double.NaN, save)), SmallBtn("Save Key", null, save)), Cross.Stretch));
            }
            Action connect = () => { string c = _connectCode; _connectCode = ""; RunAsync(async () => { if (await DotminiPlatformKey.RedeemConnectCode(c)) { Dispatcher.Invoke(new Action(() => _app.Notify("agentBar"))); await DotminiCloud.Refresh(true); } }); };
            kids.Add(V.Self(V.H(8, V.T("1-Click Connect code:", 11.5, FontWeights.Medium, t.Secondary), V.Flex(Field("otc_… (from platform.dotmini.net → Connect)", _connectCode, false, v => _connectCode = v, double.NaN, connect)), SmallBtn("Connect", null, connect)), Cross.Stretch));
            if (DotminiPlatformKey.Message.Length > 0) kids.Add(StatusText(DotminiPlatformKey.Message, DotminiPlatformKey.Message.StartsWith("Connected")));
            return Card(kids.ToArray());
        }

        UIElement AboutTab()
        {
            var t = Theme.Current;
            UIElement icon;
            try
            {
                string p = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "MicroCode.ico");
                // pick the largest frame of the .ico (256px) instead of the default 16px one
                var dec = System.Windows.Media.Imaging.BitmapDecoder.Create(new Uri(p), System.Windows.Media.Imaging.BitmapCreateOptions.None, System.Windows.Media.Imaging.BitmapCacheOption.OnLoad);
                var frame = dec.Frames.OrderByDescending(f => f.PixelWidth).First();
                var img = new Image { Source = frame, Width = 116, Height = 116, Clip = new RectangleGeometry(new Rect(0, 0, 116, 116), 26, 26) };
                RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
                icon = new Border { Child = img, Effect = new DropShadowEffect { BlurRadius = 14, ShadowDepth = 8, Direction = 270, Opacity = 0.25 } };
            }
            catch { icon = Sym.Icon("chevron.left.forwardslash.chevron.right", 60, t.Primary); }
            var col = V.Vs(0, new Border { Height = 24 }, icon, new Border { Height = 18 },
                V.T("MicroCode", 30, FontWeights.SemiBold, t.Primary),
                V.Box(V.T("Version " + AppInfo.Version + " (" + AppInfo.Build + ")", 13, FontWeights.Normal, t.Secondary), V.P(0, 2, 0, 0), null, 0),
                V.Box(V.T("The native AI-powered IDE — Windows edition", 12, FontWeights.Normal, t.Secondary), V.P(0, 10, 0, 0), null, 0),
                V.Box(V.H(18, V.Button(V.H(5, Sym.Icon("chevron.left.forwardslash.chevron.right", 12, t.Accent), V.T("GitHub", 12, FontWeights.Medium, t.Accent)), () => OpenUrl("https://github.com/Dotmini/microcode")),
                    V.Button(V.H(5, Sym.Icon("globe", 12, t.Accent), V.T("dotmini.net", 12, FontWeights.Medium, t.Accent)), () => OpenUrl("https://dotmini.net"))), V.P(0, 20, 0, 0), null, 0),
                new Border { Height = 48 },
                V.T("Dotmini Software", 12, FontWeights.SemiBold, t.Primary),
                V.Box(V.T("© 2025 Dotmini Software. All rights reserved.", 11, FontWeights.Normal, t.Secondary), V.P(0, 3, 0, 8), null, 0));
            return V.Self(col, Cross.Stretch);
        }

        static void OpenUrl(string url) { try { Process.Start(url); } catch { } }
    }
}
