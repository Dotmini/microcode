// Port of CollaborationView.swift: the Team Collaboration hub, standalone (More ▸ Realtime Collaboration) or embedded in
// Settings ▸ Team Collaboration. Same cards, labels, tabs and responsive breakpoints as the Mac, including the shared Team
// Tasks board and the MicroCode AI teammate. Parts that are not in the Windows build yet (Bonjour discovery, the QR popover)
// say so instead of offering dead buttons.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public class CollabView : Border
    {
        enum Tab { Overview, Files, Tasks, Activity }
        static readonly string[] TabNames = { "Session & Peers", "Workspace Files", "Team Tasks", "Chat & Activity" };
        static readonly string[] TabIcons = { "person.2", "folder", "checklist", "text.bubble" };

        static Window _window;

        readonly bool _embedded;
        readonly CollabService _svc;
        readonly Border _headerStatus = new Border(), _tabsHost = new Border(), _bodyHost = new Border();
        Tab _tab = Tab.Overview;
        bool _joining, _copiedLink, _copiedCode, _copiedToken;
        string _joinError;
        double _width = 640;
        bool _dirty;
        readonly DispatcherTimer _coalesce = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(220) };

        // persistent inputs (rebuilding the cards must not lose what the user is typing)
        TextBox _name, _join, _chat, _filter;
        readonly Grid _nameField, _joinField, _chatField, _filterField;
        TeamTasksView _tasksView;

        static readonly SolidColorBrush Green = Frozen(Color.FromRgb(56, 194, 122));
        static SolidColorBrush Frozen(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }

        public static void ShowWindow()
        {
            if (_window != null) { _window.Activate(); return; }
            var t = Theme.Current;
            var w = new Window { Title = "Team Collaboration", Width = 940, Height = 680, MinWidth = 860, MinHeight = 600, MaxWidth = 1120, MaxHeight = 820, Owner = Application.Current.MainWindow, WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = t.WindowBackground, FontFamily = UIFonts.UI };
            w.SourceInitialized += delegate { Native.StyleWindow(w, t.IsDark); };
            var view = new CollabView(false);
            w.Content = view;
            w.Closed += delegate { view.Detach(); _window = null; };
            _window = w;
            w.Show();
        }

        public CollabView(bool embeddedInSettings)
        {
            _embedded = embeddedInSettings;
            _svc = CollabService.Shared;
            var t = Theme.Current;
            _nameField = Styles.Field("Collaborator display name", 12, t.Primary, t.S(0.6), out _name);
            _name.FontWeight = FontWeights.Medium;
            _name.Text = _svc.LocalDisplayName;
            _name.LostKeyboardFocus += delegate { string n = _name.Text.Trim(); if (n.Length > 0 && n != _svc.LocalDisplayName) _svc.SetDisplayName(n); };
            _name.KeyDown += (s, e) => { if (e.Key == Key.Enter) Keyboard.ClearFocus(); };
            _joinField = Styles.Field("https://cloudai.dotmini.net/... or Room Code", 11.5, t.Primary, t.S(0.6), out _join);
            _join.FontFamily = UIFonts.Mono;
            _join.TextChanged += delegate { Rebuild(); };
            _join.KeyDown += (s, e) => { if (e.Key == Key.Enter) TriggerJoin(); };
            _chatField = Styles.Field("Message collaborators or type @ai to command AI Agent…", 12, t.Primary, t.S(0.6), out _chat);
            _chat.KeyDown += (s, e) => { if (e.Key == Key.Enter) SubmitChat(); };
            _filterField = Styles.Field("Filter shared workspace files by name or path…", 12, t.Primary, t.S(0.6), out _filter);
            _filter.TextChanged += delegate { Rebuild(); };

            _coalesce.Tick += delegate { _coalesce.Stop(); if (_dirty) { _dirty = false; Rebuild(); } };
            _svc.Changed += OnServiceChanged;
            SizeChanged += (s, e) =>
            {
                double w = e.NewSize.Width;
                bool crossed = new[] { 600.0, 620.0, 740.0 }.Any(b => (_width < b) != (w < b));
                _width = w;
                if (crossed) Rebuild();
            };
            _svc.RefreshNetworkAddresses();
            Child = _embedded ? EmbeddedBody() : StandaloneBody();
            if (!_embedded) Background = t.WindowBackground;
            Rebuild();
        }

        public void SelectTab(int i) { if (i >= 0 && i < TabNames.Length) { _tab = (Tab)i; Rebuild(); } }

        public void Detach() { _svc.Changed -= OnServiceChanged; _coalesce.Stop(); }

        void OnServiceChanged()
        {
            // the service fires from worker threads and on every caret move: coalesce into one rebuild per ~0.2 s
            Dispatcher.BeginInvoke(new Action(() => { _dirty = true; if (!_coalesce.IsEnabled) _coalesce.Start(); }));
        }

        // ── layout shells ──

        UIElement EmbeddedBody()
        {
            var t = Theme.Current;
            var header = Card(V.VLead(12, HeaderTopRow(false), V.Self(V.Line(t.P(0.04), true), Cross.Stretch), V.Self(_tabsHost, Cross.Stretch)));
            var s = V.VLead(14, V.Self(header, Cross.Stretch), V.Self(_bodyHost, Cross.Stretch));
            s.Align = Cross.Stretch;
            Unloaded += delegate { Detach(); };
            Loaded += delegate { _svc.Changed -= OnServiceChanged; _svc.Changed += OnServiceChanged; };
            return s;
        }

        UIElement StandaloneBody()
        {
            var t = Theme.Current;
            var g = new Grid();
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            var top = V.VLead(12, V.Self(HeaderTopRow(true), Cross.Stretch), V.Self(_tabsHost, Cross.Stretch));
            top.Align = Cross.Stretch;
            var topBox = V.Box(top, V.P(16), t.ControlBackground, 0);
            g.Children.Add(topBox);
            var div = V.Line(t.Op(t.Separator, 0.5), true); Grid.SetRow(div, 1); g.Children.Add(div);
            var scroll = new ScrollViewer { Content = V.Box(_bodyHost, V.P(18), Brushes.Transparent, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
            Grid.SetRow(scroll, 2); g.Children.Add(scroll);
            return g;
        }

        void Rebuild()
        {
            var focused = Keyboard.FocusedElement as TextBox;
            _headerStatus.Child = StatusBadge();
            _tabsHost.Child = TabBar();
            foreach (var f in new FrameworkElement[] { _nameField, _joinField, _chatField, _filterField }) Unparent(f);
            _bodyHost.Child = Body();
            if (focused != null && (focused == _name || focused == _join || focused == _chat || focused == _filter))
                Dispatcher.BeginInvoke(new Action(() => { if (focused.IsVisible) { focused.Focus(); Keyboard.Focus(focused); } }), DispatcherPriority.Input);
        }

        static void Unparent(FrameworkElement e)
        {
            var p = e.Parent;
            if (p is Panel) ((Panel)p).Children.Remove(e);
            else if (p is Decorator) ((Decorator)p).Child = null;
            else if (p is ContentControl) ((ContentControl)p).Content = null;
        }

        UIElement Body()
        {
            var t = Theme.Current;
            var s = V.VLead(_embedded ? 14 : 16);
            s.Align = Cross.Stretch;
            if (_svc.Session != null)
            {
                s.Children.Add(ActiveSessionBanner());
                switch (_tab)
                {
                    case Tab.Overview: s.Children.Add(Split(ParticipantsCard(), FilesOverviewCard(), _width < 740)); break;
                    case Tab.Files: s.Children.Add(FilesCard()); break;
                    case Tab.Tasks: s.Children.Add(TasksCard()); break;
                    case Tab.Activity: s.Children.Add(Split(ChatCard(), ActivityCard(), _width < 740)); break;
                }
            }
            else
            {
                switch (_tab)
                {
                    case Tab.Overview:
                        s.Children.Add(IdentityCard());
                        s.Children.Add(Split(HostCard(), JoinCard(), _width < 620));
                        s.Children.Add(DiscoveryCard());
                        break;
                    case Tab.Files: s.Children.Add(FilesCard()); break;
                    case Tab.Tasks: s.Children.Add(TasksCard()); break;
                    case Tab.Activity: s.Children.Add(Split(ChatCard(), ActivityCard(), _width < 740)); break;
                }
            }
            return s;
        }

        // ── building blocks ──

        static Border Card(UIElement content)
        {
            var t = Theme.Current;
            return V.Box(content, V.P(14), t.ControlBackground, 10, t.P(0.08), 1);
        }

        static TextBlock Caption(string text) { var t = Theme.Current; return V.Mono(text, 10, FontWeights.SemiBold, t.Secondary); }

        static UIElement Pill(string text, double size)
        {
            var t = Theme.Current;
            return V.Box(V.Mono(text, size, FontWeights.SemiBold, t.Secondary), V.P(6, 2), t.P(0.05), 4);
        }

        /// <summary>Two cards side by side with equal widths (top aligned), or stacked below a width breakpoint.</summary>
        static UIElement Split(UIElement a, UIElement b, bool stacked)
        {
            if (stacked) { var s = V.VLead(14, V.Self(a, Cross.Stretch), V.Self(b, Cross.Stretch)); s.Align = Cross.Stretch; return s; }
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(14) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var fa = a as FrameworkElement; var fb = b as FrameworkElement;
            if (fa != null) fa.VerticalAlignment = VerticalAlignment.Stretch;
            if (fb != null) fb.VerticalAlignment = VerticalAlignment.Stretch;
            Grid.SetColumn(b, 2);
            g.Children.Add(a); g.Children.Add(b);
            return g;
        }

        static Btn ActionButton(string icon, string label, Action click)
        {
            var t = Theme.Current;
            var b = V.Button(V.Box(V.H(4, Sym.Icon(icon, 10, t.Primary), V.T(label, 11, FontWeights.Medium, t.Primary)), V.P(8, 5), t.P(0.06), 5, t.P(0.10), 1), click);
            return b;
        }

        /// <summary>A full-width primary button (Start Host Session / Connect to Session).</summary>
        static Btn PrimaryButton(UIElement icon, string label, bool enabled, Action click)
        {
            var t = Theme.Current;
            var content = V.H(6, V.Sp(), icon, V.T(label, 11.5, FontWeights.SemiBold, enabled ? t.Primary : t.S(0.5)), V.Sp());
            var b = V.Button(V.Box(content, V.P(0, 7), enabled ? t.P(0.09) : t.P(0.03), 6, enabled ? t.P(0.18) : t.P(0.07), 1), enabled ? click : null);
            b.IsHitTestVisible = enabled;
            return V.Self(b, Cross.Stretch);
        }

        static System.Windows.Media.Imaging.BitmapSource _logo;
        static bool _logoTried;

        /// <summary>AIProviderBrandIcon(provider: "microcode"): the MicroCode app icon, for the AI teammate.</summary>
        static UIElement AIIcon(double size)
        {
            if (!_logoTried)
            {
                _logoTried = true;
                try
                {
                    string p = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "MicroCode.ico");
                    var dec = System.Windows.Media.Imaging.BitmapDecoder.Create(new Uri(p), System.Windows.Media.Imaging.BitmapCreateOptions.None, System.Windows.Media.Imaging.BitmapCacheOption.OnLoad);
                    _logo = dec.Frames.OrderByDescending(f => f.PixelWidth).First();
                    _logo.Freeze();
                }
                catch (System.IO.IOException) { _logo = null; }
                catch (UriFormatException) { _logo = null; }
                catch (NotSupportedException) { _logo = null; }
            }
            if (_logo == null) return Sym.Icon("sparkles", size, Theme.Current.Primary);
            var img = new System.Windows.Controls.Image { Source = _logo, Width = size, Height = size, VerticalAlignment = VerticalAlignment.Center };
            RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
            return img;
        }

        static UIElement FileIcon(string name, double size)
        {
            return Sym.Icon(FileTreeView.IconName(name ?? "", false), size, FileTreeView.IconColor(name ?? "", false));
        }

        static SolidColorBrush Hex(string hex, double opacity)
        {
            try
            {
                var c = (Color)ColorConverter.ConvertFromString(string.IsNullOrEmpty(hex) ? "#3B82F6" : hex);
                c.A = (byte)(255 * opacity);
                return Frozen(c);
            }
            catch (FormatException) { return Frozen(Color.FromArgb((byte)(255 * opacity), 0x3B, 0x82, 0xF6)); }
        }

        void Copy(string text, Action<bool> setFlag)
        {
            if (string.IsNullOrEmpty(text)) return;
            try { Clipboard.SetText(text); }
            catch (System.Runtime.InteropServices.COMException) { return; } // the clipboard is held by another app; nothing was copied
            setFlag(true); Rebuild();
            var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
            timer.Tick += delegate { timer.Stop(); setFlag(false); Rebuild(); };
            timer.Start();
        }

        // ── header ──

        UIElement HeaderTopRow(bool closeButton)
        {
            var t = Theme.Current;
            var icon = V.Size(new Grid(), 38, 38);
            icon.Children.Add(V.Box(null, V.P(0), t.P(0.06), 8));
            var glyph = Sym.Icon("person.2", 16, t.P(0.85), FontWeights.Medium); glyph.HorizontalAlignment = HorizontalAlignment.Center; glyph.VerticalAlignment = VerticalAlignment.Center;
            icon.Children.Add(glyph);
            var title = V.H(8, V.T("Team Collaboration", 13.5, FontWeights.SemiBold, t.Primary), _headerStatus);
            var sub = V.Wrap(V.T("Real-time P2P LAN & Dotmini Official HTTPS co-editing, live multiplayer cursors, and shared tasks.", 11.5, FontWeights.Normal, t.Secondary), TextAlignment.Left);
            var text = V.Flex(V.Shrink(V.VLead(3, title, sub)));
            var row = V.H(14, V.Self(icon, Cross.Center), text);
            if (closeButton)
                row.Children.Add(V.Button(V.Size(V.Box(V.Vs(0, V.Sp(), Sym.Icon("xmark", 11, t.Secondary, FontWeights.Medium), V.Sp()), V.P(0), t.P(0.06), 6), 26, 26), () => { var w = Window.GetWindow(this); if (w != null) w.Close(); }));
            return row;
        }

        UIElement StatusBadge()
        {
            var t = Theme.Current;
            Brush dot; string text;
            switch (_svc.Status)
            {
                case CollabStatus.Connected: dot = t.SysGreen; break;
                case CollabStatus.Connecting: case CollabStatus.Reconnecting: dot = t.SysOrange; break;
                case CollabStatus.Error: dot = t.Op(t.SysRed, 0.8); break;
                default: dot = t.S(0.45); break;
            }
            var s = _svc.Session;
            if (s != null) text = s.IsHostingLocally ? "HOSTING · :" + _svc.Server.Port : (_svc.Status == CollabStatus.Reconnecting ? "RECONNECTING · " : "CONNECTED · ") + s.ShareCode;
            else
                switch (_svc.Status)
                {
                    case CollabStatus.Connected: text = "CONNECTED"; break;
                    case CollabStatus.Connecting: text = "CONNECTING"; break;
                    case CollabStatus.Reconnecting: text = "RECONNECTING"; break;
                    case CollabStatus.Error: text = (_svc.StatusError ?? "ERROR").ToUpperInvariant(); break;
                    default: text = "STANDBY"; break;
                }
            return V.Box(V.H(5, V.Dot(6, dot), V.Mono(text, 10, FontWeights.SemiBold, t.Secondary)), V.P(7, 2), t.P(0.05), 4, t.P(0.08), 1);
        }

        UIElement TabBar()
        {
            var t = Theme.Current;
            var g = new Grid();
            for (int i = 0; i < TabNames.Length; i++)
            {
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                if (i < TabNames.Length - 1) g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(4) });
                var tab = (Tab)i;
                bool sel = tab == _tab;
                var label = V.H(5, V.Sp(), Sym.Icon(TabIcons[i], 10.5, sel ? t.Primary : t.Secondary, sel ? FontWeights.SemiBold : FontWeights.Normal), V.T(TabNames[i], 11, sel ? FontWeights.SemiBold : FontWeights.Medium, sel ? t.Primary : t.Secondary));
                int taskCount = tab == Tab.Tasks ? _svc.Tasks.Count : 0;
                if (taskCount > 0) label.Children.Add(V.Box(V.Mono(taskCount.ToString(), 9.5, FontWeights.SemiBold, sel ? t.Primary : t.Secondary), V.P(5, 1), t.P(0.08), 3));
                label.Children.Add(V.Sp());
                var b = V.Button(V.Box(label, V.P(6, 6), sel ? t.P(0.08) : Brushes.Transparent, 6, sel ? t.P(0.16) : Brushes.Transparent, 1), () => { _tab = tab; Rebuild(); });
                Grid.SetColumn(b, i * 2);
                g.Children.Add(b);
            }
            return V.Box(g, V.P(3), t.P(0.035), 8, t.P(0.06), 1);
        }

        // ── disconnected cards ──

        UIElement IdentityCard()
        {
            var t = Theme.Current;
            var top = V.H(8, Caption("COLLABORATOR IDENTITY"), V.Sp(), V.Shrink(V.T("Used for live cursor labels, file lock indicators, and shared task ownership", 11, FontWeights.Normal, t.Secondary)));
            string initial = (_svc.LocalDisplayName ?? "").Trim();
            initial = initial.Length > 0 ? initial.Substring(0, 1).ToUpperInvariant() : "?";
            var avatar = V.Size(V.Box(V.Vs(0, V.Sp(), V.Mono(initial, 12, FontWeights.SemiBold, t.P(0.88)), V.Sp()), V.P(0), t.P(0.07), 6, t.P(0.14), 1), 30, 30);
            var name = V.Flex(V.Box(V.H(8, V.Mono("NAME", 9.5, FontWeights.SemiBold, t.Secondary), V.Flex(_nameField)), V.P(10, 6), t.P(0.035), 6, t.P(0.09), 1));
            var roles = V.H(2);
            foreach (var role in new[] { "Editor", "Reviewer" })
            {
                bool sel = _svc.LocalRole == role;
                string r = role;
                roles.Children.Add(V.Button(V.Box(V.T(role, 11, sel ? FontWeights.SemiBold : FontWeights.Normal, sel ? t.Primary : t.Secondary), V.P(10, 5), sel ? t.P(0.09) : Brushes.Transparent, 5), () => _svc.SetRole(r)));
            }
            var row = V.H(10, avatar, name, V.Box(roles, V.P(2), t.P(0.035), 6, t.P(0.09), 1));
            var s = V.VLead(12, V.Self(top, Cross.Stretch), V.Self(row, Cross.Stretch));
            return Card(s);
        }

        UIElement TransportBar(bool compact)
        {
            var t = Theme.Current;
            var g = new Grid();
            int i = 0;
            foreach (var online in new[] { false, true })
            {
                bool sel = _svc.OnlineMode == online;
                bool mode = online;
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = compact ? GridLength.Auto : new GridLength(1, GridUnitType.Star) });
                if (i == 0) g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(compact ? 2 : 4) });
                var label = V.H(compact ? 4 : 5, compact ? null : V.Sp(), Sym.Icon(online ? "globe" : "wifi", compact ? 9.5 : 10, sel ? t.Primary : t.Secondary, compact ? FontWeights.SemiBold : FontWeights.Medium),
                    V.T(online ? "Online HTTPS" : "LAN / P2P", compact ? 10.5 : 11, sel ? FontWeights.SemiBold : (compact ? FontWeights.Medium : FontWeights.Normal), sel ? t.Primary : t.Secondary), compact ? null : V.Sp());
                var b = V.Button(V.Box(label, compact ? V.P(9, 4.5) : V.P(0, 5), sel ? t.P(compact ? 0.10 : 0.09) : Brushes.Transparent, 5), () => _svc.SetOnlineMode(mode));
                Grid.SetColumn(b, i * 2);
                g.Children.Add(b);
                i++;
            }
            return V.Box(g, V.P(2), t.P(compact ? 0.045 : 0.035), 6, t.P(0.08), 1);
        }

        UIElement HostCard()
        {
            var t = Theme.Current;
            string ws = AppState.Shared.WorkspaceFolder;
            string wsName = ws != null ? Path.GetFileName(ws.TrimEnd('\\')) : "Workspace";
            var head = V.H(6, Sym.Icon("antenna.radiowaves.left.and.right", 10.5, t.Secondary, FontWeights.Medium), Caption("HOST WORKSPACE SESSION"), V.Sp(), Pill("ZERO SETUP", 9));
            var name = V.H(8, Sym.Icon("folder", 16, t.Secondary), V.Shrink(V.T(wsName, 13, FontWeights.SemiBold, t.Primary)));
            var desc = V.Wrap(V.T("Starts an embedded collaboration host on a dedicated isolated port. Teammates on Wi-Fi discover it automatically, or join anywhere via Dotmini Official HTTPS Relay.", 11, FontWeights.Normal, t.Secondary), TextAlignment.Left);
            var start = PrimaryButton(Sym.Icon("play.fill", 9.5, t.Primary), "Start Host Session", true, () =>
            {
                _joinError = null;
                if (_svc.CreateSession() == null) _joinError = _svc.StatusError;
                Rebuild();
            });
            var s = V.VLead(12, V.Self(head, Cross.Stretch), name, desc, V.Sp(0), V.Self(TransportBar(false), Cross.Stretch), start);
            return Card(s);
        }

        UIElement JoinCard()
        {
            var t = Theme.Current;
            bool canJoin = _join.Text.Trim().Length > 0 && !_joining;
            var head = V.H(6, Sym.Icon("link", 10.5, t.Secondary, FontWeights.Medium), Caption("JOIN TEAMMATE SESSION"), V.Sp(), Pill("LAN / HTTPS", 9));
            var desc = V.Wrap(V.T("Paste an Invite Link (https://cloudai.dotmini.net/.../?code=ABCD12), LAN Join Token (192.168.1.x:8490#ABCD12), or 6-character Room Code.", 11, FontWeights.Normal, t.Secondary), TextAlignment.Left);
            var s = V.VLead(12, V.Self(head, Cross.Stretch), desc);
            if (_joinError != null) s.Children.Add(V.T(_joinError, 10.5, FontWeights.Normal, t.Secondary));
            s.Children.Add(V.Sp(0));
            var paste = V.Button(V.Box(V.H(4, Sym.Icon("doc.on.clipboard", 9.5, t.Secondary), V.T("Paste", 10.5, FontWeights.Medium, t.Secondary)), V.P(7, 3), t.P(0.06), 4), () =>
            {
                string clip = null;
                try { if (Clipboard.ContainsText()) clip = Clipboard.GetText(); } catch (System.Runtime.InteropServices.COMException) { }
                if (clip != null) { _join.Text = clip.Trim(); _join.CaretIndex = _join.Text.Length; }
            });
            s.Children.Add(V.Self(V.Box(V.H(6, V.Flex(_joinField), paste), V.P(9, 5), t.P(0.035), 6, t.P(0.09), 1), Cross.Stretch));
            UIElement icon = _joining ? (UIElement)V.T("…", 11, FontWeights.SemiBold, t.Secondary) : Sym.Icon("arrow.right", 10, canJoin ? t.Primary : t.S(0.5), FontWeights.SemiBold);
            s.Children.Add(PrimaryButton(icon, "Connect to Session", canJoin, TriggerJoin));
            return Card(s);
        }

        UIElement DiscoveryCard()
        {
            var t = Theme.Current;
            var head = V.H(6, Sym.Icon("wifi", 10.5, t.Secondary, FontWeights.Medium), Caption("DISCOVERED ON LOCAL NETWORK (BONJOUR / mDNS)"), V.Sp());
            var note = V.H(10, V.Self(Sym.Icon("network", 13, t.Secondary), Cross.Start), V.Flex(V.Wrap(V.T("Automatic LAN discovery (Bonjour / mDNS) is not in the Windows build yet. Ask the host for the LAN Join Token (192.168.1.x:8490#ABCD12) or the invite link and paste it above.", 11, FontWeights.Normal, t.Secondary), TextAlignment.Left)));
            var s = V.VLead(10, V.Self(head, Cross.Stretch), V.Self(V.Box(note, V.P(0, 6), Brushes.Transparent, 0), Cross.Stretch));
            return Card(s);
        }

        void TriggerJoin()
        {
            string code = _join.Text.Trim();
            if (code.Length == 0 || _joining) return;
            _joining = true; _joinError = null; Rebuild();
            var task = _svc.JoinSession(code);
            task.ContinueWith(r => Dispatcher.BeginInvoke(new Action(() =>
            {
                _joining = false;
                if (r.IsFaulted || r.Result == null) _joinError = r.IsFaulted ? r.Exception.GetBaseException().Message : (_svc.StatusError ?? "Session not found or rejected");
                else _join.Text = "";
                Rebuild();
            })));
        }

        void SubmitChat()
        {
            string msg = _chat.Text.Trim();
            if (msg.Length == 0) return;
            _chat.Text = "";
            var _ = _svc.SendChatMessage(msg);
        }

        // ── active session ──

        UIElement ActiveSessionBanner()
        {
            var t = Theme.Current;
            var s = _svc.Session;
            string code = s.ShareCode, link = _svc.GetShareLink() ?? "", token = _svc.GetJoinToken();
            bool online = _svc.OnlineMode, connectingOnline = online && _svc.TunnelStatus == "starting", relayActive = _svc.TunnelStatus == "active";
            var row = V.H(10, Sym.Icon("folder", 17, t.Secondary), V.Shrink(V.T(s.WorkspaceName, 13.5, FontWeights.Bold, t.Primary)));
            if (online)
            {
                string label = connectingOnline ? "Connecting cloudai.dotmini.net…" : _svc.TunnelStatus == "failed" ? "Relay unavailable" : (_svc.IsOfficialRelayActive ? "Dotmini Official Relay" : "Online HTTPS Relay");
                UIElement lead = connectingOnline ? (UIElement)V.T("…", 10, FontWeights.SemiBold, t.Secondary) : V.Dot(5.5, relayActive ? (Brush)Green : t.S(0.55));
                row.Children.Add(V.Box(V.H(5, lead, V.T(label, 10, FontWeights.Medium, t.Secondary)), V.P(8, 3), t.P(0.055), 5, t.P(0.09), 1));
            }
            else row.Children.Add(V.Box(V.H(4.5, V.Dot(5.5, _svc.Status == CollabStatus.Connected ? (Brush)Green : t.SysOrange), V.Mono("LAN · :" + (s.IsHostingLocally ? _svc.Server.Port.ToString() : PortOf(s.RemoteEndpoint)), 10, FontWeights.Medium, t.Secondary)), V.P(7, 3), t.P(0.055), 5, t.P(0.09), 1));
            row.Children.Add(V.Sp(8));
            if (s.IsHostingLocally) row.Children.Add(TransportBar(true));
            row.Children.Add(ActionButton("xmark", s.IsHostingLocally ? "End" : "Leave", () => { var _ = _svc.LeaveSession(); }));

            var codeBox = RoomCodeBox(code);
            var linkBox = InviteLinkBox(link, code, token, connectingOnline);
            UIElement creds;
            if (_width < 600) { var st = V.VLead(8, V.Self(codeBox, Cross.Stretch), V.Self(linkBox, Cross.Stretch)); st.Align = Cross.Stretch; creds = st; }
            else creds = V.H(10, codeBox, V.Flex(linkBox));
            var body = V.VLead(12, V.Self(row, Cross.Stretch), V.Self(creds, Cross.Stretch));
            if (online && _svc.TunnelStatus == "failed" && !string.IsNullOrEmpty(_svc.TunnelError))
                body.Children.Add(V.Wrap(V.T(_svc.TunnelError, 11, FontWeights.Normal, t.Secondary), TextAlignment.Left));
            return Card(body);
        }

        static string PortOf(string endpoint)
        {
            Uri u;
            return Uri.TryCreate(endpoint ?? "", UriKind.Absolute, out u) ? u.Port.ToString() : "";
        }

        UIElement RoomCodeBox(string code)
        {
            var t = Theme.Current;
            var codeText = V.Mono(code, 14, FontWeights.Bold, t.Primary);
            codeText.Text = string.Join(" ", code.Select(c => c.ToString())); // the Mac's 1.6 pt tracking
            var copy = V.Button(V.Box(V.H(3, Sym.Icon(_copiedCode ? "checkmark" : "doc.on.doc", 9.5, _copiedCode ? t.SysGreen : t.Secondary, FontWeights.SemiBold), V.T(_copiedCode ? "Copied" : "Copy", 10, FontWeights.SemiBold, _copiedCode ? t.SysGreen : t.Secondary)), V.P(7, 3.5), t.P(0.06), 4), () => Copy(code, v => _copiedCode = v));
            V.Tip(copy, "Copy 6-character Room Access Code (" + code + ")");
            return V.Box(V.VLead(4, V.Mono("ROOM ACCESS CODE", 9, FontWeights.Bold, t.Secondary), V.H(8, codeText, copy)), V.P(11, 8), t.P(0.035), 7, t.P(0.09), 1);
        }

        UIElement InviteLinkBox(string link, string code, string token, bool connectingOnline)
        {
            var t = Theme.Current;
            var head = V.H(6, V.Shrink(V.Mono("DIRECT INVITE LINK (ROOM CODE INCLUDED · NO EXTRA PASSWORD)", 9, FontWeights.Bold, t.Secondary)), V.Sp(4));
            if (!_svc.OnlineMode)
                head.Children.Add(V.Tip(V.Button(V.T(_copiedToken ? "✓ IDE Token Copied" : "Copy IDE Token", 9.5, FontWeights.Medium, t.Secondary), () => Copy(token, v => _copiedToken = v)), "Copy compact IDE Join Token (" + token + ")"));
            var linkText = V.Mono(connectingOnline ? "Establishing Dotmini Official HTTPS Relay (cloudai.dotmini.net)…" : link, 11.5, FontWeights.Medium, connectingOnline ? t.Secondary : t.Primary);
            linkText.ToolTip = link;
            var copyLink = V.Button(V.Box(V.H(4, Sym.Icon(_copiedLink ? "checkmark" : "link", 10, t.Primary, FontWeights.SemiBold), V.T(_copiedLink ? "Copied Link" : "Copy Invite Link", 11, FontWeights.SemiBold, t.Primary)), V.P(10, 4.5), t.P(0.10), 5, t.P(0.18), 1), connectingOnline ? null : (Action)(() => Copy(link, v => _copiedLink = v)));
            var row = V.H(8, V.Flex(V.Shrink(linkText)), copyLink);
            return V.Box(V.VLead(4, V.Self(head, Cross.Stretch), V.Self(row, Cross.Stretch)), V.P(11, 8), t.P(0.035), 7, t.P(0.09), 1);
        }

        UIElement ParticipantsCard()
        {
            var t = Theme.Current;
            var parts = _svc.Participants.ToList();
            var head = V.H(8, Caption("PARTICIPANTS (" + parts.Count + ")"), V.Sp(6));
            bool aiOn = _svc.IsAITeammateEnabled, followingAI = _svc.FollowingUserId == CollabService.AITeammateUserId;
            head.Children.Add(V.Tip(V.Button(V.Box(V.H(4.5, AIIcon(11), V.T(aiOn ? "Agent · ON" : "Agent · OFF", 10, FontWeights.Medium, aiOn ? t.Primary : t.Secondary)), V.P(8, 3.5), t.P(aiOn ? 0.09 : 0.04), 5, t.P(aiOn ? 0.16 : 0.08), 1),
                () => _svc.SetAITeammateEnabled(!_svc.IsAITeammateEnabled)), "เปิด/ปิด MicroCode Agent เป็นผู้ร่วมงานในเซสชัน"));
            if (aiOn)
                head.Children.Add(V.Tip(V.Button(V.Box(V.H(4, Sym.Icon(followingAI ? "eye.fill" : "eye", 9.5, followingAI ? t.Primary : t.Secondary, FontWeights.Medium), V.T(followingAI ? "Following Agent" : "Follow Agent", 10, FontWeights.Medium, followingAI ? t.Primary : t.Secondary)), V.P(8, 3.5), t.P(followingAI ? 0.13 : 0.04), 5, t.P(followingAI ? 0.24 : 0.08), 1),
                    () => _svc.ToggleFollow(CollabService.AITeammateUserId)), followingAI ? "คลิกเพื่อหยุดติดตามตำแหน่งไฟล์ของ Agent" : "ติดตามดูไฟล์และบรรทัดที่ Agent กำลังทำงานแบบ Real-Time"));
            if (_svc.FollowingUserId != null && !followingAI)
                head.Children.Add(V.Button(V.Box(V.T("Unfollow", 10, FontWeights.SemiBold, t.Primary), V.P(7, 3.5), t.P(0.07), 5), () => _svc.ToggleFollow(_svc.FollowingUserId)));
            var s = V.VLead(10, V.Self(head, Cross.Stretch), V.Self(V.Line(t.P(0.04), true), Cross.Stretch));
            if (parts.Count == 0) s.Children.Add(V.Box(V.T("No active participants.", 11.5, FontWeights.Normal, t.Secondary), V.P(0, 8), Brushes.Transparent, 0));
            else
            {
                var list = V.VLead(8); list.Align = Cross.Stretch;
                foreach (var p in parts) list.Children.Add(ParticipantRow(p, p.UserId == _svc.LocalUserId, _svc.FollowingUserId == p.UserId));
                s.Children.Add(V.Self(list, Cross.Stretch));
            }
            var card = Card(s);
            card.VerticalAlignment = VerticalAlignment.Top;
            return card;
        }

        UIElement ParticipantRow(CollabParticipant p, bool isSelf, bool following)
        {
            var t = Theme.Current;
            string initial = string.IsNullOrEmpty(p.DisplayName) ? "?" : p.DisplayName.Substring(0, 1).ToUpperInvariant();
            bool isAI = CollabService.IsAIParticipant(p);
            UIElement face = isAI ? AIIcon(15) : (UIElement)V.Mono(initial, 11, FontWeights.SemiBold, t.Primary);
            var faceRow = V.H(0, V.Sp(), face, V.Sp());
            var avatar = V.Size(V.Box(V.Vs(0, V.Sp(), faceRow, V.Sp()), V.P(0), t.P(0.055), 6, t.P(0.11), 1), 28, 28);
            var nameRow = V.H(6, V.Shrink(V.T(p.DisplayName + (isSelf ? " (You)" : ""), 12, FontWeights.SemiBold, t.Primary)), V.Box(V.Mono(isAI ? "AGENT" : (p.Role ?? "").ToUpperInvariant(), 9, FontWeights.Medium, t.Secondary), V.P(5.5, 1.5), t.P(0.055), 3.5));
            bool typing = p.Cursor != null && p.Cursor.IsTyping == true;
            UIElement lead = p.Cursor != null && p.Cursor.FilePath.Length > 0 ? FileIcon(p.Cursor.FilePath.Split('/').Last(), 11) : (UIElement)V.Dot(5, Hex(p.Color, 0.75));
            var activity = V.H(5, lead, V.Shrink(V.Mono(p.LiveActivitySummary, 10.5, typing ? FontWeights.Medium : FontWeights.Normal, typing ? t.Primary : t.Secondary)));
            var info = V.Flex(V.Shrink(V.VLead(2.5, nameRow, activity)));
            if (p.IsAIActive && !string.IsNullOrEmpty(p.AiStatusText)) info.Children.Add(V.H(4, V.Dot(4.5, t.S(0.65)), V.Shrink(V.Mono(p.AiStatusText, 10, FontWeights.Normal, t.Secondary))));
            var row = V.H(10, avatar, info);
            if (!isSelf && p.Cursor != null)
            {
                var person = p;
                row.Children.Add(V.Button(V.Box(V.H(3, Sym.Icon("arrow.up.right", 8.5, t.Secondary, FontWeights.SemiBold), V.T("Jump", 10.5, FontWeights.Medium, t.Secondary)), V.P(8, 4), t.P(0.045), 5, t.P(0.09), 1), () => _svc.JumpTo(person)));
            }
            if (!isSelf)
            {
                string uid = p.UserId;
                row.Children.Add(V.Button(V.Box(V.T(following ? "Following" : "Follow", 10.5, FontWeights.Medium, t.Primary), V.P(8, 4), t.P(following ? 0.13 : 0.045), 5, t.P(following ? 0.26 : 0.10), 1), () => _svc.ToggleFollow(uid)));
            }
            row.Children.Add(V.Dot(6, p.IsOnline ? (Brush)Green : t.S(0.30)));
            return V.Box(row, V.P(10), t.P(0.025), 6, t.P(following ? 0.22 : 0.07), 1);
        }

        UIElement FilesOverviewCard()
        {
            var t = Theme.Current;
            var files = _svc.SharedFiles.ToList();
            var ordered = files.OrderBy(f => !(!string.IsNullOrEmpty(f.ActiveEditorName) || f.IsOpenOnHost)).ThenBy(f => f.RelativePath, StringComparer.Ordinal).Take(8).ToList();
            var head = V.H(8, Caption("SHARED WORKSPACE FILES (" + files.Count + ")"), V.Sp());
            if (files.Count > 8) head.Children.Add(V.Button(V.H(3, V.T("Browse all " + files.Count, 10.5, FontWeights.Medium, t.Secondary), Sym.Icon("arrow.right", 9, t.Secondary, FontWeights.SemiBold)), () => { _tab = Tab.Files; Rebuild(); }));
            head.Children.Add(V.Tip(V.Button(Sym.Icon("arrow.clockwise", 10.5, t.Secondary), Reindex), "Re-index workspace files"));
            var s = V.VLead(10, V.Self(head, Cross.Stretch), V.Self(V.Line(t.P(0.04), true), Cross.Stretch));
            if (files.Count == 0) s.Children.Add(V.Box(V.T("Start or join a session to browse shared workspace files.", 11.5, FontWeights.Normal, t.Secondary), V.P(0, 8), Brushes.Transparent, 0));
            else { var list = V.VLead(6); list.Align = Cross.Stretch; foreach (var f in ordered) list.Children.Add(FileRow(f)); s.Children.Add(V.Self(list, Cross.Stretch)); }
            var card = Card(s);
            card.VerticalAlignment = VerticalAlignment.Top;
            return card;
        }

        void Reindex()
        {
            if (_svc.IsHosting) { _svc.IndexLocalWorkspaceFiles(true); Rebuild(); }
        }

        UIElement FilesCard()
        {
            var t = Theme.Current;
            string q = _filter.Text.Trim().ToLowerInvariant();
            var all = _svc.SharedFiles.OrderBy(f => f.RelativePath, StringComparer.Ordinal).ToList();
            var filtered = q.Length == 0 ? all : all.Where(f => f.RelativePath.ToLowerInvariant().Contains(q) || f.Name.ToLowerInvariant().Contains(q)).ToList();
            var bar = V.H(8, Sym.Icon("magnifyingglass", 11, t.Secondary), V.Flex(_filterField), V.Mono(_svc.SharedDirectories.Count + " folders · " + filtered.Count + " files", 10.5, FontWeights.Normal, t.Secondary), V.Button(Sym.Icon("arrow.clockwise", 10.5, t.Secondary), Reindex));
            var s = V.VLead(12, V.Self(V.Box(bar, V.P(10, 7), t.P(0.035), 6, t.P(0.08), 1), Cross.Stretch));
            if (filtered.Count == 0) s.Children.Add(V.Box(V.T("No workspace files indexed yet. Start a host session or click refresh.", 11.5, FontWeights.Normal, t.Secondary), V.P(0, 12), Brushes.Transparent, 0));
            else { var list = V.VLead(5); list.Align = Cross.Stretch; foreach (var f in filtered.Take(300)) list.Children.Add(FileRow(f)); s.Children.Add(V.Self(list, Cross.Stretch)); }
            return Card(s);
        }

        UIElement FileRow(CollabSharedFile f)
        {
            var t = Theme.Current;
            var nameRow = V.H(6, V.Shrink(V.T(f.Name, 12, FontWeights.SemiBold, t.Primary)));
            if (f.IsOpenOnHost) nameRow.Children.Add(V.Box(V.Mono("OPEN", 8.5, FontWeights.SemiBold, t.Secondary), V.P(4.5, 1), t.P(0.06), 3));
            var info = V.Flex(V.Shrink(V.VLead(1.5, nameRow)));
            if (f.RelativePath.Contains("/")) { var p = V.Mono(f.RelativePath, 10, FontWeights.Normal, t.S(0.82)); p.TextTrimming = TextTrimming.CharacterEllipsis; info.Children.Add(p); }
            var row = V.H(10, FileIcon(f.Name, 15), info);
            if (!string.IsNullOrEmpty(f.ActiveEditorName))
                row.Children.Add(V.Box(V.H(4.5, f.ActiveEditorName == CollabService.AITeammateDisplayName ? AIIcon(10) : (UIElement)V.Dot(5.5, Hex(f.ActiveEditorColor, 0.85)), V.T(f.ActiveEditorName, 10, FontWeights.Medium, t.Secondary)), V.P(7, 3), t.P(0.045), 4, t.P(0.08), 1));
            string rel = f.RelativePath;
            row.Children.Add(ActionButton("arrow.up.forward.square", "Open", () => _svc.OpenShared(rel, 1)));
            return V.Box(row, V.P(10, 7), t.P(0.025), 6, t.P(0.06), 1);
        }

        /// <summary>TeamTasksView(isEmbedded: true) — one instance for the view's lifetime so typed text and selection survive
        /// the room's frequent re-renders.</summary>
        UIElement TasksCard()
        {
            if (_tasksView == null)
                _tasksView = new TeamTasksView(true, () => _svc.Session != null && _svc.SharedRoot != null ? _svc.SharedRoot : AppState.Shared.WorkspaceFolder, () => AgentStore.ActiveId, () => AppState.Shared.SwitchToMode(EditorMode.AIAgent));
            Unparent(_tasksView);
            return _tasksView;
        }

        UIElement ChatCard()
        {
            var t = Theme.Current;
            var s = V.VLead(10, Caption("SESSION CHAT"), V.Self(V.Line(t.P(0.04), true), Cross.Stretch));
            var msgs = _svc.Chat.ToList();
            if (msgs.Count == 0) s.Children.Add(V.Box(V.T("No messages in this session yet.", 11.5, FontWeights.Normal, t.Secondary), V.P(0, 16), Brushes.Transparent, 0));
            else
            {
                var list = V.VLead(8); list.Align = Cross.Stretch;
                foreach (var m in msgs.Skip(Math.Max(0, msgs.Count - 25)))
                {
                    var head = V.H(6, V.Shrink(V.T(m.DisplayName, 11, FontWeights.SemiBold, t.Primary)), V.Sp(), V.Mono(m.Timestamp.ToLocalTime().ToString("t"), 9.5, FontWeights.Normal, t.Secondary));
                    var body = new TextBox { Text = m.Message, IsReadOnly = true, BorderThickness = new Thickness(0), Background = Brushes.Transparent, Foreground = t.Primary, FontFamily = UIFonts.UI, FontSize = 12, TextWrapping = TextWrapping.Wrap, Padding = new Thickness(0) };
                    var item = V.VLead(3, V.Self(head, Cross.Stretch), V.Self(body, Cross.Stretch));
                    list.Children.Add(V.Box(item, V.P(9), t.P(0.03), 6, t.P(0.06), 1));
                }
                s.Children.Add(V.Self(list, Cross.Stretch));
            }
            bool canSend = _svc.Session != null;
            var field = V.Flex(V.Box(_chatField, V.P(9, 6), t.P(0.035), 6, t.P(0.09), 1));
            _chat.IsEnabled = canSend;
            var ai = V.Tip(V.Button(V.Box(V.H(4, AIIcon(11), V.Mono("@ai", 11, FontWeights.Medium, t.Primary)), V.P(8, 6), t.P(0.05), 6, t.P(0.12), 1), () =>
            {
                if (!_chat.Text.ToLowerInvariant().StartsWith("@ai ")) _chat.Text = "@ai " + _chat.Text;
                _chat.Focus(); _chat.CaretIndex = _chat.Text.Length;
            }), "สั่งงาน MicroCode Agent ร่วมกับทีมใน Session Chat (@ai ...)");
            var row = V.H(8, ai, field, ActionButton("paperplane", "Send", SubmitChat));
            s.Children.Add(V.Self(row, Cross.Stretch));
            var card = Card(s);
            card.VerticalAlignment = VerticalAlignment.Top;
            return card;
        }

        UIElement ActivityCard()
        {
            var t = Theme.Current;
            var s = V.VLead(10, Caption("REALTIME ACTIVITY LOG"), V.Self(V.Line(t.P(0.04), true), Cross.Stretch));
            var items = _svc.Activity.ToList();
            if (items.Count == 0) s.Children.Add(V.Box(V.T("Session events (joins, edits, tasks) appear here.", 11.5, FontWeights.Normal, t.Secondary), V.P(0, 16), Brushes.Transparent, 0));
            else
            {
                var list = V.VLead(6); list.Align = Cross.Stretch;
                foreach (var a in Enumerable.Reverse(items.Skip(Math.Max(0, items.Count - 25)).ToList()))
                {
                    var line = V.H(4, V.T(a.ActorName, 11.5, FontWeights.SemiBold, t.Primary), V.T(a.Action, 11.5, FontWeights.Normal, t.Secondary));
                    if (!string.IsNullOrEmpty(a.Target)) line.Children.Add(V.Shrink(V.Mono(a.Target, 11, FontWeights.Medium, t.Primary)));
                    list.Children.Add(V.Box(V.VLead(2, line, V.Mono(a.Timestamp.ToLocalTime().ToString("T"), 9.5, FontWeights.Normal, t.Secondary)), V.P(10, 6), t.P(0.025), 5));
                }
                s.Children.Add(V.Self(list, Cross.Stretch));
            }
            var card = Card(s);
            card.VerticalAlignment = VerticalAlignment.Top;
            return card;
        }
    }
}
