// Port of TeamTasksView.swift: the shared task board (list + contract detail), the "Create Shared Task" composer and the
// Team Collaboration integrations sheet (Slack / Microsoft Teams). Embedded in Collaboration ▸ Team Tasks, or as its own
// window from the Agent's Team menu. Monochrome like the Mac: primary / secondary at different opacities, no accents.
using System;
using System.Collections.Generic;
using System.Globalization;
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
    public class TeamTasksView : Border
    {
        static Window _window;

        readonly bool _embedded;
        readonly TeamTaskStore _store;
        readonly TeamIntegrations _integrations;
        readonly Func<string> _workspace;
        readonly Func<string> _activeChatID;
        readonly Action _onOpenInAgent;
        readonly DispatcherTimer _coalesce = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(120) };
        bool _dirty;

        // view-level state, like the Mac's @State (typed text survives switching tasks)
        readonly TextBox _handoff, _decision;
        readonly Grid _handoffField, _decisionField;

        public TeamTasksView(bool embedded, Func<string> workspacePath, Func<string> activeChatID, Action onOpenInAgent)
        {
            _embedded = embedded;
            _store = CollabService.Shared.Tasks;
            _integrations = CollabService.Shared.Integrations;
            _workspace = workspacePath;
            _activeChatID = activeChatID;
            _onOpenInAgent = onOpenInAgent;
            var t = Theme.Current;
            _handoffField = Styles.Field("Handoff to teammate", 11.5, t.Primary, t.S(0.6), out _handoff);
            _handoff.TextChanged += delegate { Render(); };
            _decisionField = Styles.Field("Record a decision or blocker", 11.5, t.Primary, t.S(0.6), out _decision);
            _decision.TextChanged += delegate { Render(); };
            _decision.KeyDown += (s, e) => { if (e.Key == Key.Enter) SaveDecision(); };
            _coalesce.Tick += delegate { _coalesce.Stop(); if (_dirty) { _dirty = false; Render(); } };
            Action changed = () => Dispatcher.BeginInvoke(new Action(() => { _dirty = true; if (!_coalesce.IsEnabled) _coalesce.Start(); }));
            Loaded += delegate { _store.Changed += changed; _integrations.Changed += changed; _store.EnsureLoaded(_workspace()); Render(); };
            Unloaded += delegate { _store.Changed -= changed; _integrations.Changed -= changed; _coalesce.Stop(); };
            Render();
        }

        /// <summary>The Agent's "Team tasks" window (non-embedded layout).</summary>
        public static void ShowWindow(Func<string> activeChatID, Action onOpenInAgent)
        {
            if (_window != null) { _window.Activate(); return; }
            var t = Theme.Current;
            var w = new Window { Title = "Team Tasks", Width = 860, Height = 560, MinWidth = 760, MinHeight = 510, Owner = Application.Current.MainWindow, WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = t.WindowBackground, FontFamily = UIFonts.UI };
            w.SourceInitialized += delegate { Native.StyleWindow(w, t.IsDark); };
            w.Content = new TeamTasksView(false, () => AppState.Shared.WorkspaceFolder, activeChatID, () => { if (onOpenInAgent != null) onOpenInAgent(); var ww = _window; if (ww != null) ww.Close(); });
            w.Closed += delegate { _window = null; };
            _window = w;
            w.Show();
        }

        static void Unparent(FrameworkElement e)
        {
            var p = e.Parent;
            if (p is Panel) ((Panel)p).Children.Remove(e);
            else if (p is Decorator) ((Decorator)p).Child = null;
        }

        void Render()
        {
            var t = Theme.Current;
            var focused = Keyboard.FocusedElement as TextBox;
            Unparent(_handoffField); Unparent(_decisionField);
            Background = _embedded ? t.ControlBackground : t.WindowBackground;
            CornerRadius = new CornerRadius(_embedded ? 10 : 0);
            BorderBrush = _embedded ? t.P(0.08) : Brushes.Transparent;
            BorderThickness = new Thickness(_embedded ? 1 : 0);
            MinHeight = _embedded ? 420 : 510;
            if (!_integrations.TeamTasksEnabled) { Child = DisabledState(); return; }
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(_embedded ? 225 : 270) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.Children.Add(TaskList());
            var div = V.Line(t.P(0.04), false); Grid.SetColumn(div, 1); g.Children.Add(div);
            var detail = TaskDetail(); Grid.SetColumn(detail, 2); g.Children.Add(detail);
            Child = g;
            if (focused == _handoff || focused == _decision)
                Dispatcher.BeginInvoke(new Action(() => { if (focused.IsVisible) { focused.Focus(); Keyboard.Focus(focused); } }), DispatcherPriority.Input);
        }

        static Btn Small(string label, Action click, bool enabled = true, double opacity = 0.06)
        {
            var t = Theme.Current;
            var b = V.Button(V.Box(V.T(label, 11, FontWeights.Medium, enabled ? t.Primary : t.S(0.5)), V.P(8, 4), t.P(enabled ? opacity : opacity * 0.5), 5), enabled ? click : null);
            b.IsHitTestVisible = enabled;
            return b;
        }

        static Btn Framed(string label, double size, Action click, double padH = 12)
        {
            var t = Theme.Current;
            return V.Button(V.Box(V.T(label, size, FontWeights.SemiBold, t.Primary), V.P(padH, 6), t.P(0.09), 6, t.P(0.18), 1), click);
        }

        UIElement DisabledState()
        {
            var t = Theme.Current;
            var s = V.Vs(12, V.Sp(), Sym.Icon("person.2.slash", 26, t.Secondary, FontWeights.Light), V.T("Team tasks are turned off", 14, FontWeights.SemiBold, t.Primary),
                V.Size(V.Wrap(V.T("Existing local task contracts are preserved. Enable the feature when this workspace needs collaboration.", 11, FontWeights.Normal, t.Secondary), TextAlignment.Center), 410, double.NaN),
                Framed("Configure Team Collaboration", 11.5, () => ShowIntegrations(Window.GetWindow(this))), V.Sp());
            s.MinHeight = 320;
            return s;
        }

        // ── list ──

        UIElement TaskList()
        {
            var t = Theme.Current;
            var head = V.H(8, V.VLead(2, V.T("Team Tasks", 13.5, FontWeights.SemiBold, t.Primary), V.T("Shared contracts", 10, FontWeights.Normal, t.Secondary)), V.Sp(),
                V.Tip(V.Button(Sym.Icon("arrow.clockwise", 11, t.Secondary), () => _store.Load(_workspace())), "Reload shared task board"),
                V.Tip(V.Button(Sym.Icon("bell", 11, t.Secondary), () => ShowIntegrations(Window.GetWindow(this))), "Slack and Microsoft Teams notifications"),
                V.Tip(V.Button(V.Size(V.Box(V.Vs(0, V.Sp(), Sym.Icon("plus", 11, t.Primary, FontWeights.SemiBold), V.Sp()), V.P(0), t.P(0.08), 5), 24, 24), ShowComposer), "Create shared task"));
            var list = V.VLead(3); list.Align = Cross.Stretch;
            var tasks = _store.Tasks;
            string selected = _store.SelectedTaskID;
            if (tasks.Count == 0) list.Children.Add(V.Box(EmptyState("checklist", "No shared tasks", "Create a task contract for the team or an agent."), V.P(0, 60, 0, 0), Brushes.Transparent, 0));
            foreach (var task in tasks)
            {
                string id = task.Id;
                list.Children.Add(V.Button(TaskRow(task, task.Id == selected), () => _store.Select(id)));
            }
            var scroll = new ScrollViewer { Content = V.Box(list, V.P(8), Brushes.Transparent, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
            var g = new Grid();
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1) });
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            g.Children.Add(V.Box(head, V.P(12), Brushes.Transparent, 0));
            var div = V.Line(t.P(0.04), true); Grid.SetRow(div, 1); g.Children.Add(div);
            Grid.SetRow(scroll, 2); g.Children.Add(scroll);
            return g;
        }

        static Brush DotColor(TeamTaskStatus s)
        {
            var t = Theme.Current;
            switch (s)
            {
                case TeamTaskStatus.Active: return t.P(0.85);
                case TeamTaskStatus.Blocked: return t.P(0.55);
                case TeamTaskStatus.Review: return t.P(0.70);
                case TeamTaskStatus.Done: return t.S(0.65);
                default: return t.S(0.45);
            }
        }

        static UIElement TaskRow(TeamTask task, bool selected)
        {
            var t = Theme.Current;
            var info = V.Flex(V.Shrink(V.VLead(3, V.T(task.Title, 12, selected ? FontWeights.SemiBold : FontWeights.Normal, t.Primary), V.T(TeamTaskStatusInfo.Label(task.Status) + " · " + task.Owner, 9, FontWeights.Normal, t.Secondary))));
            var row = V.H(8, V.Dot(6, DotColor(task.Status)), info);
            if (task.Followers.Count > 1) row.Children.Add(V.Mono(task.Followers.Count.ToString(CultureInfo.InvariantCulture), 9, FontWeights.Normal, t.Secondary));
            return V.Box(row, V.P(8, 8), selected ? t.P(0.09) : Brushes.Transparent, 5);
        }

        static UIElement EmptyState(string icon, string title, string detail)
        {
            var t = Theme.Current;
            return V.Box(V.Vs(9, Sym.Icon(icon, 24, t.Secondary, FontWeights.Light), V.T(title, 13, FontWeights.Medium, t.Primary), V.Wrap(V.T(detail, 11, FontWeights.Normal, t.Secondary), TextAlignment.Center)), V.P(20), Brushes.Transparent, 0);
        }

        static string When(DateTime utc) { return utc.ToLocalTime().ToString("MMM d, yyyy 'at' h:mm tt", CultureInfo.GetCultureInfo("en-US")); }

        // ── detail ──

        UIElement TaskDetail()
        {
            var t = Theme.Current;
            var task = _store.SelectedTask;
            if (task == null)
            {
                var empty = V.Vs(0, V.Sp(), EmptyState("person.2", "Select a team task", "Task contracts make handoff, review, and agent context explicit."), V.Sp());
                empty.MinHeight = 320;
                return empty;
            }
            string id = task.Id;
            var status = V.Button(V.Box(V.H(4, V.T(TeamTaskStatusInfo.Label(task.Status), 11, FontWeights.Medium, t.Primary), Sym.Icon("chevron.down", 9, t.Primary)), V.P(8, 4), t.P(0.07), 5), null);
            status.MenuItems = () => TeamTaskStatusInfo.All.Select(s => { var st = s; return MenuItemSpec.Item(TeamTaskStatusInfo.Label(s), null, () => _store.UpdateStatus(st, id)); }).ToList();
            var head = V.H(8, V.Flex(V.Shrink(V.VLead(4, V.Wrap(V.T(task.Title, 16, FontWeights.SemiBold, t.Primary), TextAlignment.Left), V.T("Updated " + When(task.UpdatedAt) + " by " + task.UpdatedBy, 10, FontWeights.Normal, t.Secondary)))), V.Self(status, Cross.Start));

            var body = V.VLead(18, Contract("Objective", task.Objective, "No objective recorded"), Contract("Scope", task.Scope, "No scope recorded"), V.Self(Ownership(task), Cross.Stretch), V.Self(DecisionLog(task), Cross.Stretch));
            body.Align = Cross.Stretch;
            var scroll = new ScrollViewer { Content = V.Box(body, V.P(14), Brushes.Transparent, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };

            var footer = V.H(8, V.Shrink(V.T("The agent receives this contract only; chat transcripts remain private.", 10, FontWeights.Normal, t.Secondary)), V.Sp(),
                V.Button(V.Box(V.T("Use in Agent", 11, FontWeights.SemiBold, t.Primary), V.P(10, 5), t.P(0.09), 5, t.P(0.18), 1), () => { _store.Select(id); if (_onOpenInAgent != null) _onOpenInAgent(); }),
                V.Button(V.Box(Sym.Icon("trash", 11, t.Secondary), V.P(6), t.P(0.05), 5), () => _store.Delete(id)));

            var g = new Grid();
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1) });
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1) });
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g.Children.Add(V.Box(head, V.P(14), Brushes.Transparent, 0));
            var d1 = V.Line(t.P(0.04), true); Grid.SetRow(d1, 1); g.Children.Add(d1);
            Grid.SetRow(scroll, 2); g.Children.Add(scroll);
            var d2 = V.Line(t.P(0.04), true); Grid.SetRow(d2, 3); g.Children.Add(d2);
            var f = V.Box(footer, V.P(12), Brushes.Transparent, 0); Grid.SetRow(f, 4); g.Children.Add(f);
            return g;
        }

        static UIElement Contract(string title, string value, string empty)
        {
            var t = Theme.Current;
            var text = new TextBox { Text = value.Length == 0 ? empty : value, IsReadOnly = true, BorderThickness = new Thickness(0), Background = Brushes.Transparent, Foreground = value.Length == 0 ? t.Secondary : t.Primary, FontFamily = UIFonts.UI, FontSize = 13, TextWrapping = TextWrapping.Wrap, Padding = new Thickness(0), Margin = new Thickness(-3, 0, 0, 0) };
            var s = V.VLead(6, V.T(title, 11, FontWeights.SemiBold, t.Secondary), V.Self(text, Cross.Stretch));
            s.Align = Cross.Stretch;
            return s;
        }

        static Border Framed(UIElement field)
        {
            var t = Theme.Current;
            return V.Box(field, V.P(8, 5), t.P(0.04), 5, t.P(0.09), 1);
        }

        UIElement Ownership(TeamTask task)
        {
            var t = Theme.Current;
            string id = task.Id;
            bool watching = task.Followers.Contains(Actor);
            var owner = V.H(5, Sym.Icon("person", 12, t.Primary), V.T(task.Owner, 12, FontWeights.Medium, t.Primary));
            var row1 = V.H(8, owner, V.Sp(), Small("Claim me", () => _store.Claim(id)), Small(watching ? "Watching" : "Watch", () => _store.ToggleFollowing(id)));
            bool canHandoff = _handoff.Text.Trim().Length > 0;
            var row2 = V.H(8, V.Flex(Framed(_handoffField)), Small("Handoff", () => { _store.Handoff(id, _handoff.Text); _handoff.Text = ""; }, canHandoff, 0.07));
            int n = task.Followers.Count;
            var s = V.VLead(8, V.T("Ownership", 11, FontWeights.SemiBold, t.Secondary), V.Self(row1, Cross.Stretch), V.Self(row2, Cross.Stretch), V.T(n + " collaborator" + (n == 1 ? "" : "s") + " following this task", 10, FontWeights.Normal, t.Secondary));
            s.Align = Cross.Stretch;
            return s;
        }

        string Actor { get { string a = CollabService.Shared.LocalDisplayName; return string.IsNullOrWhiteSpace(a) ? Environment.UserName : a.Trim(); } }

        UIElement DecisionLog(TeamTask task)
        {
            var t = Theme.Current;
            string id = task.Id;
            var s = V.VLead(8, V.T("Decision log", 11, FontWeights.SemiBold, t.Secondary));
            s.Align = Cross.Stretch;
            if (task.Decisions.Count == 0) s.Children.Add(V.Wrap(V.T("Record decisions and blockers so the next person or agent can continue safely.", 11, FontWeights.Normal, t.Secondary), TextAlignment.Left));
            foreach (var d in Enumerable.Reverse(task.Decisions))
                s.Children.Add(V.Box(V.VLead(3, V.Wrap(V.T(d.Text, 12, FontWeights.Normal, t.Primary), TextAlignment.Left), V.T(d.Author + " · " + When(d.CreatedAt), 9, FontWeights.Normal, t.Secondary)), V.P(9), t.P(0.035), 5));
            bool canAdd = _decision.Text.Trim().Length > 0;
            s.Children.Add(V.Self(V.H(8, V.Flex(Framed(_decisionField)), Small("Add", SaveDecision, canAdd, 0.07)), Cross.Stretch));
            return s;
        }

        void SaveDecision()
        {
            var task = _store.SelectedTask;
            if (task == null) return;
            _store.AddDecision(_decision.Text, task.Id);
            _decision.Text = "";
        }

        // ── sheets ──

        static Window Sheet(Window owner, string title, UIElement content, double width)
        {
            var t = Theme.Current;
            var w = new Window { Title = title, Content = V.Box(content, V.P(22), t.WindowBackground, 0), Width = width, SizeToContent = SizeToContent.Height, ResizeMode = ResizeMode.NoResize, WindowStartupLocation = owner != null ? WindowStartupLocation.CenterOwner : WindowStartupLocation.CenterScreen, Owner = owner, Background = t.WindowBackground, FontFamily = UIFonts.UI, ShowInTaskbar = false };
            w.SourceInitialized += delegate { Native.StyleWindow(w, t.IsDark); };
            return w;
        }

        void ShowComposer()
        {
            var t = Theme.Current;
            TextBox title, scope, objective;
            var titleField = Styles.Field("Title", 12, t.Primary, t.S(0.6), out title);
            var scopeField = Styles.Field("Scope (files, components, or boundaries)", 12, t.Primary, t.S(0.6), out scope);
            var objBox = AgentUI.Field("", 12, false, true, out objective);
            objBox.Height = 100;
            Window w = null;
            string ws = _workspace();
            var create = V.Button(V.Box(V.T("Create Task", 11.5, FontWeights.SemiBold, t.Primary), V.P(14, 6), t.P(0.09), 6, t.P(0.18), 1), null);
            Action refresh = () => { bool ok = title.Text.Trim().Length > 0 && ws != null; create.Opacity = ok ? 1 : 0.45; create.IsHitTestVisible = ok; };
            title.TextChanged += delegate { refresh(); };
            create.Click += () =>
            {
                _store.EnsureLoaded(ws);
                _store.CreateTask(title.Text, objective.Text, scope.Text, _activeChatID != null ? _activeChatID() : null);
                w.Close();
            };
            refresh();
            var content = V.VLead(14,
                V.T("Create Shared Task", 16, FontWeights.SemiBold, t.Primary),
                V.Wrap(V.T("Write a concise contract. Your raw chat prompt is not copied or shared.", 11, FontWeights.Normal, t.Secondary), TextAlignment.Left),
                V.Self(V.Box(titleField, V.P(9, 6), t.P(0.04), 6, t.P(0.09), 1), Cross.Stretch),
                V.Self(V.VLead(5, V.T("Objective", 11, FontWeights.Medium, t.Primary), V.Self(objBox, Cross.Stretch)), Cross.Stretch),
                V.Self(V.Box(scopeField, V.P(9, 6), t.P(0.04), 6, t.P(0.09), 1), Cross.Stretch),
                V.Self(V.H(8, V.Sp(), V.Button(V.Box(V.T("Cancel", 11.5, FontWeights.Medium, t.Secondary), V.P(12, 6), t.P(0.05), 6), () => w.Close()), create), Cross.Stretch));
            content.Align = Cross.Stretch;
            w = Sheet(Window.GetWindow(this), "Create Shared Task", content, 470);
            w.Loaded += delegate { title.Focus(); };
            w.ShowDialog();
        }

        /// <summary>TeamIntegrationsSettings: the Team tasks / agent-context switches and the Slack / Teams webhooks.</summary>
        public static void ShowIntegrations(Window owner)
        {
            var integ = CollabService.Shared.Integrations;
            var t = Theme.Current;
            var host = new Border();
            string setup = null;
            var urls = new Dictionary<string, string> { { "slack", "" }, { "teams", "" } };
            Window w = null;
            Action render = null;
            Func<UIElement, Border> card = c => V.Box(c, V.P(12), t.P(0.035), 6, t.P(0.09), 1);
            render = () =>
            {
                var head = V.H(8, V.VLead(3, V.T("Team Collaboration", 16, FontWeights.SemiBold, t.Primary), V.T("Use Team tasks locally first. Notifications are optional.", 11, FontWeights.Normal, t.Secondary)), V.Sp(), V.Button(Sym.Icon("xmark", 11, t.Secondary), () => w.Close()));
                var c1 = V.VLead(10,
                    V.H(6, Sym.Icon("person.2", 13, t.Primary), V.T("1. Work together in MicroCode", 13, FontWeights.SemiBold, t.Primary)),
                    V.Self(V.H(8, V.T("Use Team tasks in this app", 12, FontWeights.Normal, t.Primary), V.Sp(), AgentUI.Switch(integ.TeamTasksEnabled, true, v => { integ.SetTeamTasksEnabled(v); render(); })), Cross.Stretch),
                    V.Wrap(V.T("Creates a small shared task board inside the project. It contains tasks, owners, and decisions — never chat transcripts.", 10, FontWeights.Normal, t.Secondary), TextAlignment.Left),
                    V.Self(V.Line(t.Separator, true), Cross.Stretch),
                    V.Self(V.H(8, V.T("Let the Agent use the selected task", 12, FontWeights.Normal, integ.TeamTasksEnabled ? t.Primary : t.S(0.5)), V.Sp(), AgentUI.Switch(integ.AgentContextEnabled, integ.TeamTasksEnabled, v => integ.SetAgentContextEnabled(v))), Cross.Stretch),
                    V.Wrap(V.T("Turn this off if you want the Agent to work only from the current chat. No Team task data will be included in its request.", 10, FontWeights.Normal, t.Secondary), TextAlignment.Left));
                c1.Align = Cross.Stretch;
                var c2 = V.VLead(9,
                    V.H(6, Sym.Icon("bell", 13, t.Primary), V.T("2. Send task updates somewhere else (optional)", 13, FontWeights.SemiBold, t.Primary)),
                    V.Wrap(V.T("MicroCode can post a concise update when a task is created, assigned, or changes status. It does not read or reply to channel messages.", 10, FontWeights.Normal, t.Secondary), TextAlignment.Left));
                c2.Align = Cross.Stretch;
                foreach (var i in TeamIntegrations.All)
                {
                    string ig = i;
                    var row = V.H(10, V.Size(new Border { Child = Sym.Icon(ig == "slack" ? "bubble.left.and.bubble.right" : "person.2", 12, t.Secondary) }, 18, double.NaN),
                        V.VLead(2, V.T(TeamIntegrations.Title(ig), 12, FontWeights.Medium, t.Primary), V.T(ig == "slack" ? "Post updates to a Slack channel." : "Post updates to a Microsoft Teams channel.", 10, FontWeights.Normal, t.Secondary)), V.Sp());
                    if (integ.IsConfigured(ig))
                    {
                        bool on = integ.IsEnabled(ig);
                        var check = V.Button(V.Size(V.Box(on ? (UIElement)Sym.Icon("checkmark", 9, Brushes.White, FontWeights.Bold) : null, V.P(0), on ? t.Accent : t.P(0.06), 3, on ? t.Accent : t.P(0.25), 1), 14, 14), () => { integ.SetEnabled(!integ.IsEnabled(ig), ig); render(); });
                        row.Children.Add(check);
                        row.Children.Add(Small("Manage", () => { setup = ig; render(); }, true, 0.07));
                    }
                    else row.Children.Add(Small("Connect", () => { setup = ig; render(); }, true, 0.07));
                    c2.Children.Add(V.Self(row, Cross.Stretch));
                }
                var s = V.VLead(16, V.Self(head, Cross.Stretch), V.Self(card(c1), Cross.Stretch), V.Self(card(c2), Cross.Stretch));
                s.Align = Cross.Stretch;
                if (setup != null)
                {
                    string ig = setup;
                    TextBox url;
                    var urlField = Styles.Field(ig == "slack" ? "https://hooks.slack.com/services/..." : "Paste a Teams Workflow webhook URL", 11.5, t.Primary, t.S(0.6), out url);
                    url.Text = urls[ig];
                    var save = Small("Save", null, true, 0.08);
                    Action refreshSave = () => { bool ok = url.Text.Trim().Length > 0; save.Opacity = ok ? 1 : 0.45; save.IsHitTestVisible = ok; };
                    url.TextChanged += delegate { urls[ig] = url.Text; refreshSave(); };
                    save.Click += () => { integ.SaveWebhook(url.Text, ig); if (integ.IsConfigured(ig)) { urls[ig] = ""; setup = null; } render(); };
                    refreshSave();
                    var actions = V.H(7, V.Flex(Framed(urlField)), save);
                    if (integ.IsConfigured(ig))
                    {
                        actions.Children.Add(Small("Send test", () => { var _ = integ.Test(ig).ContinueWith(x => host.Dispatcher.BeginInvoke(render)); }, true, 0.06));
                        actions.Children.Add(V.Button(V.Box(Sym.Icon("trash", 11, t.Secondary), V.P(5), Brushes.Transparent, 0), () => { integ.Remove(ig); render(); }));
                    }
                    var c3 = V.VLead(9, V.Self(V.H(8, V.T("Connect " + TeamIntegrations.Title(ig), 12, FontWeights.SemiBold, t.Primary), V.Sp(), V.Button(Sym.Icon("xmark", 10, t.Secondary), () => { setup = null; render(); })), Cross.Stretch),
                        V.Wrap(V.T(ig == "slack" ? "Create an Incoming Webhook in Slack, choose its channel, then paste the URL here." : "Create a Teams Workflow with “When a Teams webhook request is received”, then paste its URL here.", 10, FontWeights.Normal, t.Secondary), TextAlignment.Left),
                        V.Self(actions, Cross.Stretch));
                    c3.Align = Cross.Stretch;
                    s.Children.Add(V.Self(card(c3), Cross.Stretch));
                }
                if (!string.IsNullOrEmpty(integ.LastResult)) s.Children.Add(V.T(integ.LastResult, 10, FontWeights.Normal, t.Secondary));
                s.Children.Add(V.Self(V.H(8, V.Flex(V.Wrap(V.T("External notifications include only task title, owner, status, and objective. URLs are encrypted for your Windows account (DPAPI).", 10, FontWeights.Normal, t.Secondary), TextAlignment.Left)),
                    V.Button(V.Box(V.T("Done", 11.5, FontWeights.SemiBold, t.Primary), V.P(14, 6), t.P(0.09), 6, t.P(0.18), 1), () => w.Close())), Cross.Stretch));
                host.Child = s;
            };
            render();
            w = Sheet(owner ?? Application.Current.MainWindow, "Team Collaboration", host, 590);
            w.ShowDialog();
        }
    }
}
