// AI Agent workspace: chat store (AgentService), agentic sidebar, the agent surface (AIAgentView: transcript, live streaming turn,
// inline tool approval, queue, attachments, @mentions, slash commands, plan review) and the plain streaming client.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public class ChatMessage
    {
        public string Id = Guid.NewGuid().ToString("N");
        public string Role, Content;
        public DateTime Time = DateTime.Now;
        public double ThoughtSeconds;
        /// <summary>Provider reasoning (reasoning_content / thinking blocks).</summary>
        public string Thinking;
        public string Model;
        /// <summary>Readable failure text and which settings page fixes it ("ai", "account", "topup").</summary>
        public string Error, ErrorFix;
        /// <summary>Plan-mode reply awaiting review: "pending", "approved", "rejected".</summary>
        public string PlanState;
        public List<string> Attachments = new List<string>();
        public List<ToolStep> Steps = new List<ToolStep>();
        /// <summary>Token usage of the turn (CostTracker); UsageEstimated when the provider did not report it.</summary>
        public int InputTokens, OutputTokens, Requests;
        public bool UsageEstimated;
    }
    public class ChatSession
    {
        public string Id = Guid.NewGuid().ToString(), Name = "New Task", ProjectPath, ProjectName;
        public DateTime Updated = DateTime.Now;
        public List<ChatMessage> Messages = new List<ChatMessage>();
    }

    /// <summary>AgentWorkspaceBarState: Chat · Plan (side panel) · Task (editor tabs) · More (Walkthrough, Cells, Logs, Cost, Audit…).</summary>
    public class AgentBarState
    {
        public bool PlanMode, TaskMode, WalkthroughMode, CellMode;
        public int TaskTab;
        public bool ChatActive { get { return !PlanMode && !TaskMode && !WalkthroughMode && !CellMode; } }
        public bool SecondaryMode { get { return CellMode || WalkthroughMode || (TaskMode && TaskTab > 0); } }
        public string SecondaryLabel
        {
            get
            {
                if (WalkthroughMode) return "Walkthrough";
                if (CellMode) return "Cells";
                if (TaskMode)
                    switch (TaskTab) { case 1: return "Spec"; case 2: return "Walkthrough"; case 3: return "Logs"; case 4: return "Cost"; case 5: return "Audit"; case 6: return "Verify"; case 7: return "Background"; }
                return "More";
            }
        }
    }

    /// <summary>AgentService chat sessions + AgentWorkspaceBarState.</summary>
    public static class AgentStore
    {
        public static List<ChatSession> Sessions = new List<ChatSession>();
        public static string ActiveId;
        public static AgentView CurrentView;
        public static readonly AgentBarState Bar = new AgentBarState();
        public static event Action Changed;
        static string FilePath { get { return Path.Combine(Defaults.Dir, "chats.json"); } }

        public static void Load()
        {
            try
            {
                if (File.Exists(FilePath)) Sessions = new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Deserialize<List<ChatSession>>(Defaults.ReadShared(FilePath)) ?? new List<ChatSession>();
            }
            catch { Sessions = new List<ChatSession>(); }
            // JavaScriptSerializer hands DateTime back as UTC; the UI works in local time ("now", "5m", 14:03:22)
            foreach (var s in Sessions)
            {
                s.Updated = Local(s.Updated);
                foreach (var m in s.Messages) { m.Time = Local(m.Time); foreach (var st in m.Steps) st.Time = Local(st.Time); }
            }
            ActiveId = Sessions.OrderByDescending(s => s.Updated).Select(s => s.Id).FirstOrDefault();
        }

        static DateTime Local(DateTime d) { return d.Kind == DateTimeKind.Utc ? d.ToLocalTime() : d; }

        public static void Save()
        {
            try { Defaults.WriteAtomic(FilePath, new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Serialize(Sessions)); } catch { }
        }

        public static void Notify() { if (Changed != null) Changed(); AppState.Shared.Notify("agentBar"); }

        public static ChatSession Active { get { return Sessions.FirstOrDefault(s => s.Id == ActiveId); } }
        public static string ActiveTitle() { var a = Active; return a != null ? a.Name : "New Task"; }

        public static ChatSession NewChat(string projectPath) { return NewChat(projectPath, true); }

        /// <summary>resetModes=false when the first message of an empty conversation creates the session — Plan mode stays on.</summary>
        public static ChatSession NewChat(string projectPath, bool resetModes)
        {
            var s = new ChatSession { ProjectPath = projectPath, ProjectName = projectPath != null ? Path.GetFileName(projectPath.TrimEnd('\\')) : null };
            Sessions.Insert(0, s);
            ActiveId = s.Id;
            if (resetModes) ClearModes();
            Save(); Notify();
            return s;
        }

        public static void SwitchChat(string sessionId, string projectPath = null)
        {
            var target = Sessions.FirstOrDefault(x => x.Id == sessionId);
            if (target != null)
            {
                ActiveId = target.Id;
                if (!string.IsNullOrEmpty(target.ProjectPath) && Directory.Exists(target.ProjectPath))
                {
                    AppState.Shared.OpenWorkspace(target.ProjectPath);
                }
                ClearModes();
                Notify();
            }
            else if (!string.IsNullOrEmpty(projectPath) && Directory.Exists(projectPath))
            {
                AppState.Shared.OpenWorkspace(projectPath);
                var existing = Sessions.FirstOrDefault(x => string.Equals(x.ProjectPath, projectPath, StringComparison.OrdinalIgnoreCase));
                if (existing != null) { ActiveId = existing.Id; ClearModes(); Notify(); }
                else { NewChat(projectPath); }
            }
        }

        static void ClearModes() { Bar.PlanMode = Bar.TaskMode = Bar.WalkthroughMode = Bar.CellMode = false; }
        public static void SelectChat() { ClearModes(); Notify(); }
        public static void TogglePlan() { bool on = !Bar.PlanMode; ClearModes(); Bar.PlanMode = on; Notify(); }
        public static void SelectTask() { SelectTaskTab(0); }
        public static void SelectTaskTab(int tab) { ClearModes(); Bar.TaskMode = true; Bar.TaskTab = tab; Notify(); }
        public static void SelectWalkthrough() { ClearModes(); Bar.WalkthroughMode = true; Notify(); }
        public static void SelectCells() { ClearModes(); Bar.CellMode = true; Notify(); }
        public static void SelectSecondary(string label)
        {
            switch (label)
            {
                case "Walkthrough": SelectWalkthrough(); break;
                case "Cells": SelectCells(); break;
                case "Background": SelectTaskTab(7); break;
                case "Cost": SelectTaskTab(4); break;
                case "Logs": SelectTaskTab(3); break;
                case "Audit": SelectTaskTab(5); break;
                case "Verify": SelectTaskTab(6); break;
                default: SelectChat(); break;
            }
        }

        /// <summary>The newest plan-mode reply in the active chat that is still awaiting review (orange dot on the Plan pill).</summary>
        public static bool PlanPending { get { var a = Active; return a != null && a.Messages.Any(m => m.PlanState == "pending"); } }
    }

    /// <summary>Plain streaming completion (no tools) through the active AI mode — Inline Edit, Cell Mode AI.</summary>
    public static class AIClient
    {
        public static Task Stream(List<ChatMessage> history, string system, Action<string> onDelta, CancellationToken ct)
        {
            return Task.Run(() => AgentRunner.Run(history, system, false, true, null, new AgentCallbacks { OnText = onDelta }, ct), ct);
        }

        public static string NotConnectedText()
        {
            return AIConfig.Mode == "cloud"
                ? "Dotmini Cloud requires signing in. Sign in via Settings → Account & License (or on microcode.dotmini.net — it syncs back automatically), or pick another AI mode in Settings → AI & Agent."
                : "No AI provider is connected yet. Open Settings → AI & Agent (Ctrl+,) to sign in to Dotmini Cloud, add an API key, or use a Local LLM.";
        }

        public static void InlineEdit(CodeFile file, string prompt, Action<string, string> done)
        {
            if (!AIConfig.IsConfigured) { done(null, NotConnectedText()); return; }
            var sb = new StringBuilder();
            var disp = Application.Current.Dispatcher;
            var hist = new List<ChatMessage> { new ChatMessage { Role = "user", Content = "Edit this " + file.Language + " file according to the instruction. Return ONLY the full updated file content, no explanations, no code fences.\n\nInstruction: " + prompt + "\n\nFile " + file.Name + ":\n" + file.Content } };
            Stream(hist, "You are MicroCode's inline code editor.", d => { lock (sb) sb.Append(d); }, CancellationToken.None).ContinueWith(t =>
            {
                disp.BeginInvoke(new Action(() =>
                {
                    if (t.IsFaulted) { done(null, AIException.Describe(t.Exception, AIConfig.Mode == "cloud")); return; }
                    string s; lock (sb) s = sb.ToString().Trim();
                    if (s.StartsWith("```")) { int nl = s.IndexOf('\n'); s = nl > 0 ? s.Substring(nl + 1) : s; if (s.EndsWith("```")) s = s.Substring(0, s.Length - 3); }
                    done(s.TrimEnd() + "\n", null);
                }));
            });
        }
    }

    /// <summary>AgenticWorkspaceSidebar: new conversation, projects with their recent conversations.</summary>
    public class AgentSidebar : Grid
    {
        readonly AppState _app;
        public AgentSidebar(AppState app)
        {
            _app = app;
            AgentStore.Changed += Render;
            app.Changed += w => { if (w == "workspace") Render(); };
            Render();
        }

        void Render()
        {
            var t = Theme.Current;
            Children.Clear();
            var root = V.VLead(0); root.Align = Cross.Stretch;
            var top = V.H(2, new Border { Width = 70 }, V.Sp());
            root.Children.Add(V.Size(V.Box(top, V.P(6, 0, 4, 0), null, 0), double.NaN, 36));
            var newBtn = V.Button(V.Box(V.H(8, Sym.Icon("square.and.pencil", 12, t.Primary), V.T("New Conversation", 12.5, FontWeights.Medium, t.Primary), V.Sp(), V.T("Ctrl+N", 10.5, FontWeights.Normal, t.Secondary)), V.P(10, 7), Brushes.Transparent, 7), () => AgentStore.NewChat(_app.WorkspaceFolder));
            newBtn.OnState = b => ((Border)b.Child).Background = b.IsHover ? t.P(0.07) : Brushes.Transparent;
            root.Children.Add(V.Box(newBtn, V.P(8, 2), null, 0));
            root.Children.Add(V.Box(V.T("PROJECTS", 10, FontWeights.SemiBold, t.Secondary), V.P(16, 12, 16, 4), null, 0));
            var groups = AgentStore.Sessions.GroupBy(s => s.ProjectPath ?? "").OrderByDescending(g => g.Max(s => s.Updated));
            var list = V.VLead(1); list.Align = Cross.Stretch;
            if (!AgentStore.Sessions.Any())
                list.Children.Add(V.Box(V.T("No conversations yet", 11.5, FontWeights.Normal, t.Secondary), V.P(16, 6), null, 0));
            foreach (var g in groups)
            {
                string name = g.Key.Length > 0 ? Path.GetFileName(g.Key.TrimEnd('\\')) : "No Project";
                list.Children.Add(V.Box(V.H(6, Sym.Icon("folder", 11, t.Secondary), V.T(name, 12, FontWeights.SemiBold, t.P(0.9))), V.P(14, 6, 10, 2), null, 0));
                foreach (var s in g.OrderByDescending(x => x.Updated).Take(5))
                {
                    var session = s;
                    bool active = s.Id == AgentStore.ActiveId;
                    var row = V.Button(V.Box(V.H(6, V.Flex(V.T(s.Name, 12, active ? FontWeights.Medium : FontWeights.Normal, active ? t.Primary : t.P(0.8))), V.T(Ago(s.Updated), 10.5, FontWeights.Normal, t.Secondary)), V.P(28, 5, 10, 5), active ? t.P(0.10) : Brushes.Transparent, 6), () => { AgentStore.ActiveId = session.Id; AgentStore.Notify(); });
                    if (!active) row.OnState = b => ((Border)b.Child).Background = b.IsHover ? t.P(0.05) : Brushes.Transparent;
                    row.MenuItems = null;
                    row.MouseRightButtonUp += (o, e) =>
                    {
                        e.Handled = true;
                        MacMenu.ShowAtMouse(new List<MenuItemSpec>
                        {
                            MenuItemSpec.Item("Rename…", "pencil", () => { var n = Prompt.Ask("Rename Conversation", "Name:", session.Name); if (!string.IsNullOrWhiteSpace(n)) { session.Name = n.Trim(); AgentStore.Save(); AgentStore.Notify(); } }),
                            MenuItemSpec.Sep(),
                            new MenuItemSpec { Title = "Delete Conversation", Icon = "trash", Destructive = true, Action = () => { AgentStore.Sessions.Remove(session); if (AgentStore.ActiveId == session.Id) AgentStore.ActiveId = AgentStore.Sessions.Select(x => x.Id).FirstOrDefault(); AgentStore.Save(); AgentStore.Notify(); } }
                        });
                    };
                    list.Children.Add(V.Box(row, V.P(6, 0), null, 0));
                }
            }
            root.Children.Add(V.Flex(new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }));
            var settings = V.Button(V.Box(V.H(8, Sym.Icon("gearshape", 12, t.Secondary), V.T("Settings", 12, FontWeights.Normal, t.Secondary), V.Sp()), V.P(10, 7), Brushes.Transparent, 7), () => SettingsWindow.Show(_app));
            settings.OnState = b => ((Border)b.Child).Background = b.IsHover ? t.P(0.06) : Brushes.Transparent;
            root.Children.Add(V.Box(settings, V.P(8, 4, 8, 10), null, 0));
            Children.Add(root);
        }

        static string Ago(DateTime d)
        {
            var s = DateTime.Now - d;
            if (s.TotalMinutes < 1) return "now";
            if (s.TotalHours < 1) return (int)s.TotalMinutes + "m";
            if (s.TotalDays < 1) return (int)s.TotalHours + "h";
            return (int)s.TotalDays + "d";
        }
    }

    /// <summary>AIAgentView: transcript + composer, streaming replies and the autonomous tool loop.</summary>
    public class AgentView : Grid, IAgentHost
    {
        readonly AppState _app;
        // layout: chat column | splitter | Implementation Plan side panel, plus a full-surface host for Task / Walkthrough / Cells
        readonly Grid _chat = new Grid();
        readonly Border _planHost = new Border(), _modeHost = new Border(), _splitLine = new Border();
        GridSplitter _splitter;
        ColumnDefinition _colChat, _colSplit, _colPlan;
        double _planWidth = 400;
        PlanPanel _planPanel;
        TaskPanel _taskPanel;
        NotebookView _cells;

        public AppState App { get { return _app; } }
        public bool IsRunning { get { return _running; } }
        public void RunPrompt(string prompt, bool plan)
        {
            if (_running) { _queue.Add(new Queued { Text = prompt, Files = new List<string>() }); RenderQueue(); return; }
            Start(prompt, new List<string>(), plan);
        }

        /// <summary>Runs (or queues) a prompt in the active chat and hands back the reply of THAT turn — its own message, never
        /// "the last assistant message" (which could be an earlier run's when the prompt had to wait in the queue).</summary>
        public void RunPromptWithReply(string prompt, Action<ChatMessage> onReply)
        {
            if (_running) { _queue.Add(new Queued { Text = prompt, Files = new List<string>(), OnReply = onReply }); RenderQueue(); return; }
            Start(prompt, new List<string>(), null, onReply);
        }
        public void StopRun() { Stop(); }
        public int QueuedCount { get { return _queue.Count; } }
        public string PendingApprovalToolName { get { return _pendingApprovalToolName; } }
        public string PendingApprovalDescription { get { return _pendingApprovalDescription; } }
        public bool ApprovePendingTool(bool allow)
        {
            if (_pendingApproval == null) return false;
            ResolveApproval(allow);
            return true;
        }
        public bool ApproveLatestPlan(bool approve)
        {
            var s = AgentStore.Active;
            if (s == null) return false;
            var m = s.Messages.LastOrDefault(x => x.PlanState == "pending");
            if (m == null) return false;
            m.PlanState = approve ? "approved" : "rejected";
            AgentStore.Save();
            AgentStore.Notify();
            if (approve && !_running)
            {
                Start("Plan approved. Execute the approved implementation plan cleanly step-by-step.", new List<string>(), false);
            }
            return true;
        }
        readonly bool _embeddedInWelcome;
        readonly StackPanel _transcript = new StackPanel();
        readonly ScrollViewer _scroll;
        readonly Border _emptyHost = new Border(), _bottomHost = new Border();
        readonly Border _approvalHost = new Border(), _queueHost = new Border();
        readonly WrapPanel _attachBar = new WrapPanel();
        Border _card, _bottomHolder;
        Stack _composer;
        TextBox _input;
        TextBlock _placeholder;
        StackPanel _sendHost;
        Action _renderModel, _renderScope;

        CancellationTokenSource _cts;
        bool _running;
        LiveTurn _live;
        readonly List<string> _attachments = new List<string>();
        class Queued { public string Text; public List<string> Files; public Action<ChatMessage> OnReply; }
        readonly List<Queued> _queue = new List<Queued>();
        Queued _sendAfterStop;
        TaskCompletionSource<bool> _pendingApproval;
        string _pendingApprovalToolName = "", _pendingApprovalDescription = "";
        bool _planRevision;

        public AgentView(AppState app, bool embeddedInWelcome)
        {
            _app = app; _embeddedInWelcome = embeddedInWelcome;
            if (!embeddedInWelcome) AgentStore.CurrentView = this;
            Loaded += delegate { if (!embeddedInWelcome) AgentStore.CurrentView = this; };
            var t = Theme.Current;
            Background = t.WorkspaceBackground;
            _colChat = new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = 200 };
            _colSplit = new ColumnDefinition { Width = new GridLength(0) };
            _colPlan = new ColumnDefinition { Width = new GridLength(0) };
            ColumnDefinitions.Add(_colChat); ColumnDefinitions.Add(_colSplit); ColumnDefinitions.Add(_colPlan);
            _chat.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            _chat.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            _scroll = new ScrollViewer { Content = new Border { Child = _transcript, MaxWidth = 880, Padding = new Thickness(28, 20, 28, 20) }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            _chat.Children.Add(_scroll);
            Grid.SetRowSpan(_emptyHost, 2);
            _chat.Children.Add(_emptyHost);
            Grid.SetRow(_bottomHost, 1);
            _chat.Children.Add(_bottomHost);
            Children.Add(_chat);
            // NativePaneResizeSplitter: 6pt hit area with a hairline, double-click resets the plan width
            _splitLine.Width = 1; _splitLine.Background = t.Separator; _splitLine.IsHitTestVisible = false; _splitLine.HorizontalAlignment = HorizontalAlignment.Center;
            Grid.SetColumn(_splitLine, 1); Children.Add(_splitLine);
            _splitter = new GridSplitter { HorizontalAlignment = HorizontalAlignment.Stretch, VerticalAlignment = VerticalAlignment.Stretch, ResizeDirection = GridResizeDirection.Columns, ResizeBehavior = GridResizeBehavior.PreviousAndNext, Background = Brushes.Transparent, Cursor = Cursors.SizeWE, ShowsPreview = false };
            Grid.SetColumn(_splitter, 1); Children.Add(_splitter);
            _splitter.DragCompleted += delegate { if (_colPlan.ActualWidth > 0) _planWidth = _colPlan.ActualWidth; };
            _splitter.MouseDoubleClick += delegate { _planWidth = 400; ApplyMode(); };
            Grid.SetColumn(_planHost, 2); Children.Add(_planHost);
            Grid.SetColumnSpan(_modeHost, 3); _modeHost.Visibility = Visibility.Collapsed; Children.Add(_modeHost);
            _card = BuildComposer();
            _composer = V.VLead(6, _queueHost, _approvalHost, _card);
            _composer.Align = Cross.Stretch;
            SizeChanged += delegate { UpdatePlaceholder(); };
            AgentStore.Changed += OnStoreChanged;
            app.Changed += w => { if (w == "workspace" || w == "agentBar") { if (!_running) RenderTranscript(); if (_renderModel != null) _renderModel(); if (_renderScope != null) _renderScope(); ApplyMode(); } };
            Action refreshModel = () => { if (_renderModel != null) _renderModel(); };
            DotminiAuth.Changed += refreshModel;
            DotminiCloud.Changed += refreshModel;
            DotminiPlatformKey.Changed += refreshModel;
            Unloaded += delegate { DotminiAuth.Changed -= refreshModel; DotminiCloud.Changed -= refreshModel; DotminiPlatformKey.Changed -= refreshModel; };
            if (AIConfig.Mode == "cloud") DotminiCloud.EnsureFresh();
            RenderTranscript();
            ApplyMode();
        }

        void OnStoreChanged() { if (!_running) RenderTranscript(); ApplyMode(); }

        /// <summary>Shows the surface for the header pills: chat, chat + plan side panel, or the Task / Walkthrough / Cells views.</summary>
        void ApplyMode()
        {
            var bar = AgentStore.Bar;
            bool overlay = bar.TaskMode || bar.WalkthroughMode || bar.CellMode;
            if (overlay)
            {
                UIElement view;
                if (bar.TaskMode)
                {
                    if (_taskPanel == null) _taskPanel = new TaskPanel(this, bar.TaskTab);
                    else { _taskPanel.Tab = bar.TaskTab; _taskPanel.Refresh(); }
                    view = _taskPanel;
                }
                else if (bar.WalkthroughMode) view = new WalkthroughPanel(this);
                else { if (_cells == null) _cells = new NotebookView(_app); view = _cells; }
                if (_modeHost.Child != view) _modeHost.Child = view;
                _modeHost.Visibility = Visibility.Visible;
                _chat.Visibility = _planHost.Visibility = _splitter.Visibility = _splitLine.Visibility = Visibility.Collapsed;
                return;
            }
            _modeHost.Child = null;
            _modeHost.Visibility = Visibility.Collapsed;
            _chat.Visibility = _planHost.Visibility = Visibility.Visible;
            if (bar.PlanMode)
            {
                if (_planPanel == null)
                {
                    _planPanel = new PlanPanel(this);
                    _planPanel.CloseRequested += () => AgentStore.SelectChat();
                    _planPanel.FullscreenToggled += ApplyMode;
                }
                else _planPanel.Render();
                if (_planHost.Child != _planPanel) _planHost.Child = _planPanel;
                if (_planPanel.Fullscreen)
                {
                    _colChat.MinWidth = 0; _colChat.Width = new GridLength(0);
                    _colSplit.Width = new GridLength(0);
                    _colPlan.MinWidth = 0; _colPlan.MaxWidth = double.PositiveInfinity; _colPlan.Width = new GridLength(1, GridUnitType.Star);
                    _splitter.Visibility = _splitLine.Visibility = Visibility.Collapsed;
                }
                else
                {
                    double max = Math.Max(280, Math.Min(680, (ActualWidth > 0 ? ActualWidth : 1200) - 260));
                    _colChat.MinWidth = 200; _colChat.Width = new GridLength(1, GridUnitType.Star);
                    _colSplit.Width = new GridLength(6);
                    _colPlan.MinWidth = 260; _colPlan.MaxWidth = max; _colPlan.Width = new GridLength(Math.Max(260, Math.Min(max, _planWidth)));
                    _splitter.Visibility = _splitLine.Visibility = Visibility.Visible;
                }
            }
            else
            {
                if (_planPanel != null) _planPanel.Fullscreen = false;
                _planHost.Child = null;
                _colChat.MinWidth = 200; _colChat.Width = new GridLength(1, GridUnitType.Star);
                _colSplit.Width = new GridLength(0);
                _colPlan.MinWidth = 0; _colPlan.Width = new GridLength(0);
                _splitter.Visibility = _splitLine.Visibility = Visibility.Collapsed;
            }
        }

        void UpdatePlaceholder()
        {
            if (_placeholder == null) return;
            bool narrow = ActualWidth > 0 && ActualWidth < 920 || _app.AgenticContextVisible || AgentStore.Bar.PlanMode;
            _placeholder.Text = _planRevision ? "Describe what to change in the plan…"
                : AgentStore.Bar.PlanMode ? "Plan mode — describe the task; the agent researches and drafts a plan for your review"
                : narrow ? "Ask anything, @ to mention, / for commands" : "Ask anything, @ to mention, / for commands — paste (Ctrl+V) or drop files";
        }

        /// <summary>centeredEmptyStateView: project pill + composer, vertically centred, maxWidth 880.</summary>
        UIElement EmptyState()
        {
            var t = Theme.Current;
            string project = _app.WorkspaceFolder != null ? Path.GetFileName(_app.WorkspaceFolder.TrimEnd('\\')) : "No Project";
            var pill = V.Button(V.Box(V.H(5, Sym.Icon("folder", 11, t.Secondary), V.T(project, 12, FontWeights.Medium, t.P(0.85)), Sym.Icon("chevron.down", 8, t.S(0.7), FontWeights.SemiBold)), V.P(8, 4), t.P(0.04), 6), null);
            pill.MenuItems = () =>
            {
                var items = new List<MenuItemSpec> { MenuItemSpec.Header("Workspace") };
                foreach (var p in AppState.RecentWorkspaces().Take(8)) { var path = p; items.Add(new MenuItemSpec { Title = Path.GetFileName(path.TrimEnd('\\')), Icon = "folder", Checked = string.Equals(path, _app.WorkspaceFolder, StringComparison.OrdinalIgnoreCase), Action = () => _app.OpenWorkspace(path) }); }
                items.Add(MenuItemSpec.Sep());
                items.Add(MenuItemSpec.Item("Open Folder…", "folder.badge.plus", _app.OpenFolderDialog));
                return items;
            };
            var col = V.VLead(8, V.Box(pill, V.P(2, 0, 0, 0), null, 0), V.Self(Detach(_composer), Cross.Stretch));
            col.MaxWidth = 880;
            col.Margin = new Thickness(28, 0, 28, 0);
            var g = new Grid();
            col.VerticalAlignment = VerticalAlignment.Center;
            g.Children.Add(col);
            return g;
        }

        static UIElement Detach(FrameworkElement e)
        {
            if (e.Parent is Decorator) ((Decorator)e.Parent).Child = null;
            else if (e.Parent is Panel) ((Panel)e.Parent).Children.Remove(e);
            return e;
        }

        public void HandleCommand(string cmd)
        {
            if (cmd == "new") AgentStore.NewChat(_app.WorkspaceFolder);
            else if (cmd == "clear") { var a = AgentStore.Active; if (a != null && !_running) { a.Messages.Clear(); AgentStore.Save(); AgentStore.Notify(); } }
            else if (cmd == "undoLast") { var a = AgentStore.Active; if (a != null && !_running && a.Messages.Count >= 2) { a.Messages.RemoveRange(a.Messages.Count - 2, 2); AgentStore.Save(); AgentStore.Notify(); } }
            else if (cmd == "stop") Stop();
            else if (cmd.StartsWith("send:")) Submit(cmd.Substring(5), new List<string>());
            else if (cmd.StartsWith("fix:")) { _app.SwitchToMode(EditorMode.AIAgent); Submit("Fix the error shown in this terminal output:\n\n```\n" + cmd.Substring(4) + "\n```", new List<string>()); }
        }

        // ── composer (inputCardView) ───────────────────────────────────────────
        Border BuildComposer()
        {
            var t = Theme.Current;
            var field = Styles.Field("Ask anything, @ to mention, / for commands — paste (Ctrl+V) or drop files", 13, t.Primary, t.Secondary, out _input);
            _placeholder = (TextBlock)field.Children[0];
            _placeholder.VerticalAlignment = VerticalAlignment.Top;
            _placeholder.Margin = new Thickness(2, 2, 0, 0);
            _input.AcceptsReturn = true;
            _input.TextWrapping = TextWrapping.Wrap;
            _input.MinHeight = 24;
            _input.MaxHeight = 240;
            _input.VerticalContentAlignment = VerticalAlignment.Top;
            _input.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
            _input.PreviewKeyDown += OnInputKey;
            _input.TextChanged += delegate { RenderSend(); UpdateSuggestions(); };
            _input.LostKeyboardFocus += delegate { Dispatcher.BeginInvoke(new Action(() => { if (!_input.IsKeyboardFocusWithin && _suggest != null && !_suggest.IsMouseOver) CloseSuggestions(); }), DispatcherPriority.Background); };
            DataObject.AddPastingHandler(_input, OnPaste);

            // plusActionMenu: 24pt circle
            var plus = V.Button(V.Size(V.Box(Sym.Icon("plus", 12, t.Secondary, FontWeights.SemiBold), V.P(0), t.P(0.055), 12), 24, 24), null);
            plus.ToolTip = "Attach files, insert commands, or configure Agents & MCP";
            plus.MenuItems = () => new List<MenuItemSpec>
            {
                MenuItemSpec.Item("Add Files, PDF, Code or Images…", "paperclip", PickFiles),
                MenuItemSpec.Item("Paste Image from Clipboard", "photo", () => { if (!PasteClipboardAttachments()) MessageBox.Show(Window.GetWindow(this), "The clipboard has no image or files.", "MicroCode"); }),
                MenuItemSpec.Item("Mention Active File", "doc.text", () => { if (_app.CurrentFile != null && _app.CurrentFile.Path != null) InsertText("@" + RelPath(_app.CurrentFile.Path) + " "); }),
                MenuItemSpec.Item("Include Last Terminal Output", "terminal", () => Submit("/terminal", new List<string>())),
                MenuItemSpec.Sep(),
                MenuItemSpec.Item("Plan Mode (/plan)", "list.bullet.clipboard", () => { AgentStore.TogglePlan(); UpdatePlaceholder(); }),
                MenuItemSpec.Item("Code Review (/review)", "checkmark.shield", () => { _input.Text = "/review "; _input.CaretIndex = _input.Text.Length; _input.Focus(); }),
                MenuItemSpec.Item("All Slash Commands (/help)", "info.circle", () => Submit("/help", new List<string>())),
                MenuItemSpec.Sep(),
                MenuItemSpec.Item("Connect External Agents…", "link.badge.plus", () => SettingsWindow.Show(_app, 2)),
                MenuItemSpec.Item("Rules, MCP & Context Settings…", "slider.horizontal.3", () => SettingsWindow.Show(_app, 0))
            };

            // modelSelectorDropdown
            var modelRow = V.H(5);
            var model = V.Button(V.Box(modelRow, V.P(7, 3), t.P(0.06), 6, Theme.B(Theme.WithAlpha(Colors.White, 0.1)), 1), null);
            model.MinWidth = 64; model.MaxWidth = 220;
            _renderModel = () =>
            {
                modelRow.Children.Clear();
                if (!AIConfig.IsConfigured)
                {
                    modelRow.Children.Add(Sym.Icon("link", 10, t.Secondary, FontWeights.Medium));
                    modelRow.Children.Add(V.T("Connect AI", 11, FontWeights.Medium, t.Primary));
                    model.ToolTip = AIClient.NotConnectedText();
                }
                else
                {
                    modelRow.Children.Add(Sym.Icon(AIConfig.Mode == "local" ? "desktopcomputer" : AIConfig.Mode == "cloud" ? "sparkles" : "key", 11, t.Primary));
                    var name = V.T(AIConfig.BadgeTitle + " · " + AIConfig.ModelDisplayName, 11, FontWeights.Medium, t.Primary);
                    name.TextTrimming = TextTrimming.CharacterEllipsis;
                    modelRow.Children.Add(V.Shrink(name));
                    model.ToolTip = AIConfig.BadgeTitle + " · " + AIConfig.Model;
                }
                modelRow.Children.Add(Sym.Icon("chevron.up.chevron.down", 8.5, t.Secondary, FontWeights.SemiBold));
            };
            _renderModel();
            model.Click += () =>
            {
                if (!AIConfig.IsConfigured) { SettingsWindow.Show(_app, AIConfig.Mode == "cloud" ? 6 : 2); if (_renderModel != null) _renderModel(); return; }
                MacMenu.Show(model, ModelMenu(), false);
            };

            // scopeLockMenuPill
            var scopeRow = V.H(3);
            var scope = V.Button(V.Box(scopeRow, V.P(5, 3), t.P(0.04), 5), null);
            scope.ToolTip = "Scope Lock & Protected Files Guard — Lock files from AI edits or enforce Strict @Mention Scope";
            _renderScope = () =>
            {
                scopeRow.Children.Clear();
                int n = _app.WorkspaceFolder != null ? ScopeLock.ActiveCount : 0;
                scopeRow.Children.Add(Sym.Icon(n > 0 ? "lock.fill" : "lock.shield", 10, n > 0 ? t.SysOrange : t.Secondary, FontWeights.SemiBold));
                if (n > 0) scopeRow.Children.Add(V.T(n.ToString(), 10, FontWeights.SemiBold, t.SysOrange));
            };
            _renderScope();
            scope.MenuItems = ScopeMenu;
            // AgentTargetEnvironmentMenu
            var env = V.Button(V.Box(V.H(4, Sym.Icon("desktopcomputer", 9, t.S(0.85)), V.T("Local", 10, FontWeights.Normal, t.S(0.85)), Sym.Icon("chevron.down", 7, t.S(0.85))), V.P(6, 2), Brushes.Transparent, 4), null);
            env.MenuItems = () => new List<MenuItemSpec> { new MenuItemSpec { Title = "Local (This PC)", Icon = "desktopcomputer", Checked = true }, MenuItemSpec.Sep(), MenuItemSpec.Header("REMOTE SERVERS / CLOUD"), new MenuItemSpec { Title = "No SSH servers configured", Disabled = true } };
            // ToolApprovalModePickerView (default .smart)
            var approvalRow = V.H(4);
            var approval = V.Button(V.Box(approvalRow, V.P(6, 3), t.A(0.10), 5), null);
            Action renderApproval = () =>
            {
                string mode = Defaults.Bool("agentAutoApproveTools", false) ? "yolo" : Defaults.Str("toolApprovalMode", "smart");
                approvalRow.Children.Clear();
                Brush tint = mode == "yolo" ? t.SysGreen : mode == "safe" ? t.SysOrange : t.Accent;
                approvalRow.Children.Add(Sym.Icon(mode == "yolo" ? "flame.fill" : mode == "safe" ? "lock.shield" : "brain.head.profile", 9.5, tint, FontWeights.SemiBold));
                approvalRow.Children.Add(V.T(mode == "yolo" ? "Auto" : mode == "safe" ? "Safe" : "Smart", 10, FontWeights.SemiBold, t.P(0.85)));
                ((Border)approval.Child).Background = Theme.B(Theme.WithAlpha(((SolidColorBrush)tint).Color, 0.10));
                approval.ToolTip = mode == "yolo" ? "Full Auto — auto-approve workspace tools" : mode == "safe" ? "Safe — ask before every tool execution" : "Smart — ask only for file edits and commands";
            };
            renderApproval();
            approval.MenuItems = () =>
            {
                string cur = Defaults.Bool("agentAutoApproveTools", false) ? "yolo" : Defaults.Str("toolApprovalMode", "smart");
                Func<string, string, string, MenuItemSpec> m = (key, title, icon) => new MenuItemSpec { Title = title, Icon = icon, Checked = cur == key, Action = () => { Defaults.Set("toolApprovalMode", key); Defaults.Set("agentAutoApproveTools", key == "yolo"); renderApproval(); if (key == "yolo" && _pendingApproval != null) ResolveApproval(true); } };
                return new List<MenuItemSpec> { MenuItemSpec.Header("Agent Tool Autonomy"), m("safe", "Safe — Ask before every tool", "lock.shield"), m("smart", "Smart — Ask only for dangerous operations", "brain.head.profile"), m("yolo", "Full Auto — Auto-approve workspace tools", "flame.fill") };
            };
            // subAgentPickerButton
            var subLabel = V.T("Agent", 10, FontWeights.Normal, t.S(0.85));
            var sub = V.Button(V.Box(V.H(3, subLabel, Sym.Icon("chevron.down", 7, t.S(0.85))), V.P(6, 3), t.P(0.03), 5), null);
            Action renderSub = () => { string p = Defaults.Str("agentPersona", "main"); subLabel.Text = p == "main" ? "Agent" : char.ToUpperInvariant(p[0]) + p.Substring(1); };
            renderSub();
            sub.ToolTip = "Choose the agent persona for the next message";
            sub.MenuItems = () =>
            {
                string cur = Defaults.Str("agentPersona", "main");
                Func<string, string, string, MenuItemSpec> m = (key, title, icon) => new MenuItemSpec { Title = title, Icon = icon, Checked = cur == key, Action = () => { Defaults.Set("agentPersona", key); renderSub(); } };
                return new List<MenuItemSpec> { m("main", "Agent (Main)", "sparkles"), m("explorer", "Explorer — read-only codebase research", "magnifyingglass"), m("planner", "Planner — drafts a plan for review", "list.bullet.clipboard"), m("reviewer", "Reviewer — senior code review", "checkmark.shield") };
            };
            // voiceInputButton → Windows Voice Typing (Win+H), which also dictates Thai
            var mic = V.Button(V.Size(V.Box(Sym.Icon("mic", 12, t.Secondary, FontWeights.Medium), V.P(0), t.P(0.05), 13), 26, 26), () => { _input.Focus(); Dispatcher.BeginInvoke(new Action(VoiceTyping), DispatcherPriority.Input); });
            mic.ToolTip = "สั่งงานด้วยเสียง — Windows Voice Typing (Win+H) รองรับไทย/EN";
            // sendOrStopButton
            _sendHost = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            RenderSend();

            _attachBar.Margin = new Thickness(0, 0, 0, 2);
            _attachBar.Visibility = Visibility.Collapsed;
            // UnifiedAgentActionsMenu "Team" pill: the shared task board and its settings; a dot when a task contract is active
            var teamRow = V.H(3);
            var team = V.Button(V.Box(teamRow, V.P(6, 4), t.P(0.06), 6), null);
            team.ToolTip = "Team Tasks & Collaboration";
            Action renderTeam = () =>
            {
                var integ = CollabService.Shared.Integrations;
                var sel = CollabService.Shared.Tasks.SelectedTask;
                bool active = integ.TeamTasksEnabled && (sel != null || TeamIntegrations.All.Any(i => integ.IsEnabled(i)));
                team.Visibility = integ.TeamTasksEnabled ? Visibility.Visible : Visibility.Collapsed;
                teamRow.Children.Clear();
                teamRow.Children.Add(Sym.Icon("person.2", 9.5, active ? t.Primary : t.Secondary, FontWeights.Medium));
                teamRow.Children.Add(V.T("Team", 11, active ? FontWeights.SemiBold : FontWeights.Medium, active ? t.Primary : t.Secondary));
                if (sel != null) teamRow.Children.Add(V.Dot(5, t.Accent));
            };
            team.MenuItems = () =>
            {
                var items = new List<MenuItemSpec>
                {
                    MenuItemSpec.Item("Team Tasks", "checklist", () => TeamTasksView.ShowWindow(() => AgentStore.ActiveId, null)),
                    MenuItemSpec.Item("Configure Team Collaboration", "slider.horizontal.3", () => TeamTasksView.ShowIntegrations(Window.GetWindow(this)))
                };
                var sel = CollabService.Shared.Tasks.SelectedTask;
                if (sel != null)
                {
                    items.Add(MenuItemSpec.Sep());
                    items.Add(new MenuItemSpec { Title = "Active: " + sel.Title, Disabled = true });
                    items.Add(new MenuItemSpec { Title = TeamTaskStatusInfo.Label(sel.Status) + " · " + sel.Owner, Disabled = true });
                }
                return items;
            };
            Action teamChanged = () => Dispatcher.BeginInvoke(renderTeam);
            CollabService.Shared.Tasks.Changed += teamChanged;
            CollabService.Shared.Integrations.Changed += teamChanged;
            Unloaded += delegate { CollabService.Shared.Tasks.Changed -= teamChanged; CollabService.Shared.Integrations.Changed -= teamChanged; };
            renderTeam();
            var bottom = V.H(5, plus, model, scope, env, team, V.Sp(4), approval, sub, mic, _sendHost);
            var stack = V.VLead(6, V.Self(_attachBar, Cross.Stretch), V.Self(V.Box(field, V.P(2, 2, 2, 0), null, 0), Cross.Stretch), V.Self(V.Box(bottom, V.P(0, 2, 0, 0), null, 0), Cross.Stretch));
            var card = V.Box(stack, V.P(12, 9), Theme.B(Theme.WithAlpha(Colors.White, 0.04)), 14, t.P(0.10), 1);
            _input.GotKeyboardFocus += delegate { card.BorderBrush = t.P(0.24); };
            _input.LostKeyboardFocus += delegate { card.BorderBrush = t.P(0.10); };
            card.AllowDrop = true;
            card.PreviewDragOver += (s, e) => { e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None; e.Handled = true; };
            card.PreviewDrop += (s, e) =>
            {
                var files = e.Data.GetData(DataFormats.FileDrop) as string[];
                if (files != null) { foreach (var f in files) AddAttachment(f); e.Handled = true; }
            };
            return card;
        }

        void RenderSend()
        {
            if (_sendHost == null) return;
            var t = Theme.Current;
            _sendHost.Children.Clear();
            bool hasInput = _input.Text.Trim().Length > 0 || _attachments.Count > 0;
            Func<Brush, string, double, Brush, UIElement> circle = (bg, icon, size, fg) => V.Size(V.Box(Sym.Icon(icon, 11, fg, FontWeights.Bold), V.P(0), bg, size / 2), size, size);
            if (_running)
            {
                if (hasInput)
                {
                    var q = V.Button(circle(Theme.B(Theme.WithAlpha(Color.FromRgb(255, 159, 10), 0.88)), "plus", 24, Brushes.White), EnqueueInput);
                    q.ToolTip = "Add to Queue (Runs after active task finishes)";
                    q.Margin = new Thickness(0, 0, 5, 0);
                    var now = V.Button(circle(t.Accent, "arrow.up", 26, Brushes.White), SendNow);
                    now.ToolTip = "Send Immediately (Interrupts active loop and starts new message)";
                    now.Margin = new Thickness(0, 0, 5, 0);
                    _sendHost.Children.Add(q); _sendHost.Children.Add(now);
                }
                var square = new Border { Width = 8, Height = 8, CornerRadius = new CornerRadius(1.5), Background = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
                var stop = V.Button(V.Size(V.Box(square, V.P(0), Theme.B(Theme.WithAlpha(Color.FromRgb(255, 59, 48), 0.85)), 13), 26, 26), Stop);
                stop.ToolTip = "Stop active AI task";
                _sendHost.Children.Add(stop);
                return;
            }
            var send = V.Button(circle(hasInput ? t.Accent : t.P(0.12), "arrow.up", 26, hasInput ? (Brush)Brushes.White : t.S(0.6)), () => Submit(_input.Text, TakeAttachments()));
            send.ToolTip = "Send Message";
            _sendHost.Children.Add(send);
        }

        [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
        static void VoiceTyping()
        {
            const byte LWIN = 0x5B, H = 0x48; const uint UP = 0x0002;
            keybd_event(LWIN, 0, 0, UIntPtr.Zero); keybd_event(H, 0, 0, UIntPtr.Zero);
            keybd_event(H, 0, UP, UIntPtr.Zero); keybd_event(LWIN, 0, UP, UIntPtr.Zero);
        }

        void InsertText(string s)
        {
            int at = _input.CaretIndex;
            _input.Text = _input.Text.Insert(at, s);
            _input.CaretIndex = at + s.Length;
            _input.Focus();
        }

        // ── model menu (presentNativeModelMenu) ────────────────────────────────
        List<MenuItemSpec> ModelMenu() { return BuildModelMenu(_app); }

        /// <summary>The model menu shared by the Agent composer and Cell Mode's model pills (CellAIModelMenuPresenter).</summary>
        public static List<MenuItemSpec> BuildModelMenu(AppState _app)
        {
            DotminiCloud.EnsureFresh();
            string mode = AIConfig.Mode;
            var root = new List<MenuItemSpec>();
            Action<int> settings = tab => { SettingsWindow.Show(_app, tab); _app.Notify("agentBar"); };

            root.Add(new MenuItemSpec { Title = "Enterprise API (Vertex AI, Azure, Bedrock, LiteLLM)", Icon = "building.2", Checked = mode == "enterprise", Children = new List<MenuItemSpec>
            {
                new MenuItemSpec { Title = "Use Direct API Key → Custom (OpenAI-compatible) with your gateway Base URL", Disabled = true },
                MenuItemSpec.Sep(),
                MenuItemSpec.Item("Open 1-Click Enterprise API Hub…", "building.2", () => { Defaults.Set("ai_key_mode", "enterprise"); settings(2); })
            } });
            root.Add(new MenuItemSpec { Title = "Subscription (ChatGPT, Claude, Gemini)", Icon = "person.crop.circle", Checked = mode == "subscription", Children = new List<MenuItemSpec>
            {
                new MenuItemSpec { Title = "Web subscription sign-in is not available on Windows yet", Disabled = true },
                MenuItemSpec.Sep(),
                MenuItemSpec.Item("Manage Subscriptions in Settings...", "gearshape", () => settings(2))
            } });

            var byok = new List<MenuItemSpec>();
            foreach (var p in AIConfig.Catalog)
            {
                var prov = p;
                bool hasKey = !string.IsNullOrEmpty(AIConfig.KeyFor(p.Id)) || p.Id == "custom" || AIConfig.HasCustomUrl(p.Id);
                var models = new List<string>(p.Models.Where(m => m.Length > 0));
                List<string> live; if (LiveModels.TryGetValue(p.Id, out live)) foreach (var m in live) if (!models.Contains(m)) models.Add(m);
                string cur = AIConfig.ModelFor(p.Id);
                if (cur.Length > 0 && !models.Contains(cur)) models.Insert(0, cur);
                var items = models.Take(100).Select(m => { var id = m; return new MenuItemSpec { Title = AIConfig.FormatModelName(id), Checked = mode == "direct" && AIConfig.SelectedProvider == prov.Id && cur == id, Action = () => { AIConfig.Mode = "direct"; AIConfig.SelectedProvider = prov.Id; AIConfig.SetModelFor(prov.Id, id); _app.Notify("agentBar"); } }; }).ToList();
                items.Add(MenuItemSpec.Sep());
                items.Add(MenuItemSpec.Item("Enter Custom Model ID...", null, () => { var id = Prompt.Ask("Enter Custom Model ID", "Type the exact model identifier from " + prov.Name + ":", ""); if (!string.IsNullOrWhiteSpace(id)) { AIConfig.Mode = "direct"; AIConfig.SelectedProvider = prov.Id; AIConfig.SetModelFor(prov.Id, id.Trim()); _app.Notify("agentBar"); } }));
                if (hasKey) items.Add(MenuItemSpec.Item("Fetch Live Models Now", "arrow.clockwise", () => FetchLiveModels(prov.Id)));
                else { items.Add(MenuItemSpec.Sep()); items.Add(MenuItemSpec.Item("Set " + prov.Name + " API Key in Settings...", "key", () => { Defaults.Set("ai_key_mode", "direct"); Defaults.Set("ai_provider", prov.Id); settings(2); })); }
                byok.Add(new MenuItemSpec { Title = prov.Name + (hasKey ? "" : " (No Key)"), Icon = "key", Checked = mode == "direct" && AIConfig.SelectedProvider == prov.Id, Children = items });
            }
            byok.Add(MenuItemSpec.Sep());
            byok.Add(MenuItemSpec.Item("Fetch All Provider Models", "arrow.clockwise", () => { foreach (var p in AIConfig.Catalog) if (!string.IsNullOrEmpty(AIConfig.KeyFor(p.Id))) FetchLiveModels(p.Id); }));
            root.Add(new MenuItemSpec { Title = "BYOK & Smart Routers (OpenRouter, Direct API)", Icon = "key", Checked = mode == "direct", Children = byok });

            var local = new List<MenuItemSpec>();
            List<string> localModels; LiveModels.TryGetValue("local", out localModels);
            string curLocal = AIConfig.ModelFor("local");
            if (localModels == null || localModels.Count == 0)
            {
                local.Add(new MenuItemSpec { Title = "Endpoint: " + AIConfig.BaseUrlFor("local"), Disabled = true });
                local.Add(new MenuItemSpec { Title = curLocal, Checked = mode == "local", Action = () => { AIConfig.Mode = "local"; _app.Notify("agentBar"); } });
            }
            else foreach (var m in localModels) { var id = m; local.Add(new MenuItemSpec { Title = id, Checked = mode == "local" && curLocal == id, Action = () => { AIConfig.Mode = "local"; AIConfig.SetModelFor("local", id); _app.Notify("agentBar"); } }); }
            local.Add(MenuItemSpec.Sep());
            local.Add(MenuItemSpec.Item("Scan for Local Engines (Ollama, LM Studio)", "arrow.clockwise", ScanLocal));
            local.Add(MenuItemSpec.Item("Configure Local LLM in Settings...", "gearshape", () => { Defaults.Set("ai_key_mode", "local"); settings(2); }));
            root.Add(new MenuItemSpec { Title = "Local LLM (Ollama, LM Studio, llama.cpp)", Icon = "desktopcomputer", Checked = mode == "local", Children = local });

            var acpItems = new List<MenuItemSpec>();
            foreach (var ag in AcpHostService.ListKnown())
            {
                var agent = ag;
                string badge = agent.Available ? "Installed" : "Not in PATH";
                acpItems.Add(new MenuItemSpec
                {
                    Title = agent.Name + " (" + badge + ")",
                    Icon = agent.Available ? "checkmark.circle.fill" : "circle.dashed",
                    Disabled = !agent.Available,
                    Action = () =>
                    {
                        // BuildModelMenu is static: act on the agent view that is on screen
                        var view = AgentStore.CurrentView;
                        if (view == null || view._input == null) return;
                        view._input.Text = "/acp " + agent.Id + " ";
                        view._input.CaretIndex = view._input.Text.Length;
                        view._input.Focus();
                    }
                });
            }
            root.Add(new MenuItemSpec { Title = "ACP Harnesses (Claude Code, Codex, Gemini CLI, Goose, Cursor...)", Icon = "terminal", Children = acpItems });

            var cloud = new List<MenuItemSpec>();
            var sess = DotminiAuth.Session;
            if (sess != null)
            {
                var e = DotminiAuth.Entitlement;
                cloud.Add(new MenuItemSpec { Title = e.Loaded ? sess.Email + " · " + e.PlanUpper + " (" + e.FormattedAvailable + " AI Credit · API +" + (int)e.MarginPct + "%)" : sess.Email + " · Syncing AI Credit…", Icon = "checkmark.seal.fill", Disabled = true });
            }
            else if (DotminiPlatformKey.IsConfigured) cloud.Add(new MenuItemSpec { Title = "Dotmini Platform key · " + DotminiPlatformKey.Masked, Icon = "checkmark.seal.fill", Disabled = true });
            else cloud.Add(MenuItemSpec.Item("Sign in to Dotmini Cloud…", "person.badge.key", () => settings(6)));
            cloud.Add(MenuItemSpec.Sep());
            if (DotminiCloud.Models.Count == 0) cloud.Add(new MenuItemSpec { Title = DotminiCloud.Refreshing ? "Fetching live models from microcode.dotmini.net/v1…" : "No live models yet — Refresh", Icon = "arrow.triangle.2.circlepath", Disabled = DotminiCloud.Refreshing, Action = () => { var _ = DotminiCloud.Refresh(true); } });
            else
            {
                cloud.Add(new MenuItemSpec { Title = DotminiCloud.Source, Icon = "antenna.radiowaves.left.and.right", Disabled = true });
                string curCloud = AIConfig.ModelFor("omni");
                var active = DotminiCloud.Find(curCloud);
                if (mode == "cloud" && active != null) { cloud.Add(new MenuItemSpec { Title = "Active: " + active.Name + " · " + active.Rate, Checked = true, Disabled = true }); cloud.Add(MenuItemSpec.Sep()); }
                foreach (var g in DotminiCloud.ByProvider())
                {
                    var kids = g.Value.Select(m => { var id = m.Id; return new MenuItemSpec { Title = m.Name + " · " + m.Rate, Checked = mode == "cloud" && curCloud == id, Action = () => { AIConfig.Mode = "cloud"; AIConfig.SetModelFor("omni", id); _app.Notify("agentBar"); } }; }).ToList();
                    cloud.Add(new MenuItemSpec { Title = DotminiCloud.ProviderName(g.Key) + " (" + g.Value.Count + ")", Checked = mode == "cloud" && g.Value.Any(m => m.Id == curCloud), Children = kids });
                }
            }
            cloud.Add(MenuItemSpec.Sep());
            cloud.Add(MenuItemSpec.Item("Refresh Live Models", "arrow.clockwise", () => { var _ = DotminiCloud.Refresh(true); }));
            cloud.Add(MenuItemSpec.Item("Dotmini Cloud Settings…", "gearshape", () => { Defaults.Set("ai_key_mode", "cloud"); settings(2); }));
            root.Add(new MenuItemSpec { Title = "Dotmini Cloud", Icon = "sparkles", Checked = mode == "cloud", Children = cloud });

            root.Add(MenuItemSpec.Sep());
            root.Add(MenuItemSpec.Item("Rescan Local Engines & Cloud APIs", "arrow.triangle.2.circlepath", () => { ScanLocal(); var _ = DotminiCloud.Refresh(true); }));
            root.Add(MenuItemSpec.Item("AI Settings...", "gearshape", () => settings(2)));
            return root;
        }

        static readonly Dictionary<string, List<string>> LiveModels = new Dictionary<string, List<string>>();

        static void FetchLiveModels(string pid)
        {
            var disp = Application.Current.Dispatcher;
            Task.Run(async () =>
            {
                string url = AIConfig.BaseUrlFor(pid).TrimEnd('/') + "/models", key = AIConfig.KeyFor(pid);
                var req = new System.Net.Http.HttpRequestMessage(System.Net.Http.HttpMethod.Get, pid == "gemini" ? url + "?key=" + Uri.EscapeDataString(key ?? "") : url);
                if (pid == "anthropic") { req.Headers.TryAddWithoutValidation("x-api-key", key ?? ""); req.Headers.TryAddWithoutValidation("anthropic-version", "2023-06-01"); }
                else if (!string.IsNullOrEmpty(key) && pid != "gemini") req.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", key);
                var resp = await DotminiNet.Http.SendAsync(req);
                var o = DJ.Obj(await resp.Content.ReadAsStringAsync());
                var arr = DJ.Arr(o, "data") ?? DJ.Arr(o, "models");
                var ids = new List<string>();
                if (arr != null) foreach (var item in arr) { var d = item as Dictionary<string, object>; string id = DJ.Str(d, "id") ?? DJ.Str(d, "name"); if (id != null) ids.Add(id.Replace("models/", "")); }
                return ids;
            }).ContinueWith(tk => disp.BeginInvoke(new Action(() => { if (!tk.IsFaulted && tk.Result.Count > 0) LiveModels[pid] = tk.Result.OrderBy(x => x).ToList(); })));
        }

        static void ScanLocal()
        {
            var disp = Application.Current.Dispatcher;
            // the configured endpoint first, then Ollama 11434, LM Studio 1234 (1235 when 1234 is taken),
            // llama.cpp / LocalAI 8080, vLLM 8000 and Jan 1337 — use 127.0.0.1 to avoid Windows IPv6 ::1 refusal
            var candidates = new[] {
                AIConfig.BaseUrlFor("local"),
                "http://127.0.0.1:11434/v1",
                "http://127.0.0.1:1234/v1",
                "http://127.0.0.1:1235/v1",
                "http://127.0.0.1:8080/v1",
                "http://127.0.0.1:8000/v1",
                "http://127.0.0.1:1337/v1"
            }.Select(AIConfig.NormalizeLocalBaseUrl).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            Task.Run(async () =>
            {
                var probes = candidates.Select(async ep =>
                {
                    var ids = new List<string>();
                    try
                    {
                        using (var c = new System.Net.Http.HttpClient { Timeout = TimeSpan.FromSeconds(3) })
                        {
                            try
                            {
                                var o = DJ.Obj(await c.GetStringAsync(ep.TrimEnd('/') + "/models"));
                                var arr = DJ.Arr(o, "data") ?? DJ.Arr(o, "models");
                                if (arr != null) foreach (var item in arr) { var d = item as Dictionary<string, object>; string id = DJ.Str(d, "id") ?? DJ.Str(d, "name"); if (!string.IsNullOrEmpty(id) && !ids.Contains(id)) ids.Add(id); }
                            }
                            catch { }
                            // Fallback for native Ollama /api/tags
                            if (ids.Count == 0 && ep.EndsWith("/v1", StringComparison.OrdinalIgnoreCase))
                            {
                                try
                                {
                                    string origin = ep.Substring(0, ep.Length - 3);
                                    var o = DJ.Obj(await c.GetStringAsync(origin + "/api/tags"));
                                    var arr = DJ.Arr(o, "models");
                                    if (arr != null) foreach (var item in arr) { var d = item as Dictionary<string, object>; string id = DJ.Str(d, "name") ?? DJ.Str(d, "model"); if (!string.IsNullOrEmpty(id) && !ids.Contains(id)) ids.Add(id); }
                                }
                                catch { }
                            }
                        }
                    }
                    catch (Exception ex) { System.Diagnostics.Debug.WriteLine("local scan " + ep + ": " + ex.Message); }
                    return ids;
                }).ToList();
                var results = await Task.WhenAll(probes);
                for (int i = 0; i < results.Length; i++)
                    if (results[i].Count > 0) return new KeyValuePair<string, List<string>>(candidates[i], results[i]);
                return new KeyValuePair<string, List<string>>(null, new List<string>());
            }).ContinueWith(tk => disp.BeginInvoke(new Action(() =>
            {
                if (tk.IsFaulted) return;
                if (tk.Result.Key != null && tk.Result.Key != AIConfig.BaseUrlFor("local")) AIConfig.SetBaseUrlFor("local", tk.Result.Key);
                LiveModels["local"] = tk.Result.Value;
                if (tk.Result.Value.Count > 0)
                {
                    string cur = AIConfig.ModelFor("local");
                    if (string.IsNullOrWhiteSpace(cur) || !tk.Result.Value.Contains(cur))
                        AIConfig.SetModelFor("local", tk.Result.Value[0]);
                    Defaults.Flush();
                    AppState.Shared.Notify("agentBar");
                }
            })));
        }

        List<MenuItemSpec> ScopeMenu()
        {
            var items = new List<MenuItemSpec>();
            if (_app.WorkspaceFolder == null) { items.Add(new MenuItemSpec { Title = "Open a folder to use Scope Lock", Disabled = true }); return items; }
            var cf = _app.CurrentFile;
            if (cf != null && cf.Path != null)
            {
                bool locked = ScopeLock.IsLocked(cf.Path);
                items.Add(MenuItemSpec.Item(locked ? "Unlock " + cf.Name : "Lock " + cf.Name + " (Protect from AI)", locked ? "lock.open" : "lock.fill", () => { ScopeLock.Toggle(cf.Path); _renderScope(); }));
            }
            else items.Add(new MenuItemSpec { Title = "Lock Active File (Protect from AI)", Icon = "lock.fill", Disabled = true });
            items.Add(MenuItemSpec.Sep());
            items.Add(new MenuItemSpec { Title = "Strict Scope (Edit Only @Mentioned Files)", Icon = "scope", Checked = ScopeLock.Strict, Action = () => { ScopeLock.Strict = !ScopeLock.Strict; _renderScope(); } });
            items.Add(new MenuItemSpec { Title = "Lock Core Configs (.env, package.json, Cargo.toml)", Icon = "shield", Checked = ScopeLock.CoreConfigs, Action = () => { ScopeLock.CoreConfigs = !ScopeLock.CoreConfigs; _renderScope(); } });
            var locked2 = ScopeLock.Locked;
            if (locked2.Count > 0)
            {
                items.Add(MenuItemSpec.Sep());
                items.Add(MenuItemSpec.Header("LOCKED FILES"));
                foreach (var p in locked2) { var path = p; items.Add(MenuItemSpec.Item("Unlock " + RelPath(path), "lock.open", () => { ScopeLock.Toggle(path); _renderScope(); })); }
            }
            return items;
        }

        // ── input handling: keys, paste, attachments, suggestions ──────────────
        void OnInputKey(object s, KeyEventArgs e)
        {
            if (_suggest != null && _suggest.IsOpen)
            {
                if (e.Key == Key.Down) { MoveSuggestion(1); e.Handled = true; return; }
                if (e.Key == Key.Up) { MoveSuggestion(-1); e.Handled = true; return; }
                if (e.Key == Key.Escape) { CloseSuggestions(); e.Handled = true; return; }
                if ((e.Key == Key.Enter && (Keyboard.Modifiers & ModifierKeys.Shift) == 0) || e.Key == Key.Tab) { AcceptSuggestion(); e.Handled = true; return; }
            }
            if (e.Key == Key.Enter && (Keyboard.Modifiers & ModifierKeys.Shift) == 0)
            {
                e.Handled = true;
                if (_running && (Keyboard.Modifiers & ModifierKeys.Control) == 0) EnqueueInput();
                else if (_running) SendNow();
                else Submit(_input.Text, TakeAttachments());
                return;
            }
            if (e.Key == Key.Escape && _running) { Stop(); e.Handled = true; }
        }

        void OnPaste(object sender, DataObjectPastingEventArgs e)
        {
            if (e.DataObject.GetDataPresent(DataFormats.FileDrop) || (!e.DataObject.GetDataPresent(DataFormats.UnicodeText) && Clipboard.ContainsImage()))
            {
                if (PasteClipboardAttachments()) e.CancelCommand();
            }
        }

        bool PasteClipboardAttachments()
        {
            try
            {
                if (Clipboard.ContainsFileDropList()) { foreach (var f in Clipboard.GetFileDropList()) AddAttachment(f); return true; }
                if (Clipboard.ContainsImage())
                {
                    var img = Clipboard.GetImage();
                    if (img == null) return false;
                    string dir = Path.Combine(Defaults.Dir, "attachments");
                    Directory.CreateDirectory(dir);
                    string file = Path.Combine(dir, "pasted-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".png");
                    var enc = new PngBitmapEncoder();
                    enc.Frames.Add(BitmapFrame.Create(img));
                    using (var fs = File.Create(file)) enc.Save(fs);
                    AddAttachment(file);
                    return true;
                }
            }
            catch { }
            return false;
        }

        void PickFiles()
        {
            var dlg = new Microsoft.Win32.OpenFileDialog { Multiselect = true, Title = "Add Files, PDF, Code or Images", InitialDirectory = _app.WorkspaceFolder ?? "" };
            if (dlg.ShowDialog() == true) foreach (var f in dlg.FileNames) AddAttachment(f);
        }

        void AddAttachment(string path)
        {
            if (string.IsNullOrEmpty(path) || Directory.Exists(path)) { if (Directory.Exists(path)) InsertText("@" + RelPath(path) + " "); return; }
            if (!File.Exists(path) || _attachments.Any(a => string.Equals(a, path, StringComparison.OrdinalIgnoreCase))) return;
            _attachments.Add(path);
            RenderAttachments();
            RenderSend();
        }

        List<string> TakeAttachments() { var l = new List<string>(_attachments); return l; }

        void RenderAttachments()
        {
            var t = Theme.Current;
            _attachBar.Children.Clear();
            foreach (var f in _attachments)
            {
                var path = f;
                UIElement icon;
                if (AgentRunner.IsImage(f))
                {
                    try
                    {
                        var bmp = new BitmapImage(); bmp.BeginInit(); bmp.CacheOption = BitmapCacheOption.OnLoad; bmp.DecodePixelHeight = 56; bmp.UriSource = new Uri(f); bmp.EndInit();
                        icon = new Border { Width = 26, Height = 26, CornerRadius = new CornerRadius(4), Background = new ImageBrush(bmp) { Stretch = Stretch.UniformToFill } };
                    }
                    catch { icon = Sym.Icon("photo", 12, t.Secondary); }
                }
                else icon = Sym.Icon(FileTreeView.IconName(Path.GetFileName(f), false), 12, FileTreeView.IconColor(Path.GetFileName(f), false));
                var x = V.Button(Sym.Icon("xmark", 8, t.Secondary, FontWeights.Bold), () => { _attachments.Remove(path); RenderAttachments(); RenderSend(); });
                x.ToolTip = "Remove";
                var name = V.T(Path.GetFileName(f), 11, FontWeights.Medium, t.P(0.9)); name.MaxWidth = 180; name.TextTrimming = TextTrimming.CharacterEllipsis;
                var chip = V.Box(V.H(6, icon, name, x), V.P(6, 3), t.P(0.06), 6, t.P(0.10), 0.5);
                chip.ToolTip = f;
                chip.Margin = new Thickness(0, 0, 6, 4);
                _attachBar.Children.Add(chip);
            }
            _attachBar.Visibility = _attachments.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        }

        // @mention + slash command popup (SlashCommandSuggestionView)
        Popup _suggest;
        StackPanel _suggestList;
        int _suggestIndex;
        readonly List<Action> _suggestActions = new List<Action>();
        readonly List<Border> _suggestRows = new List<Border>();
        List<string> _fileIndex;
        string _fileIndexRoot;

        static readonly string[][] Slash =
        {
            new[] { "file", "Include file content as context", "doc", "arg" }, new[] { "compact", "Compact and summarize chat history", "arrow.down.right.and.arrow.up.left", "" },
            new[] { "clear", "Clear chat history", "trash", "" }, new[] { "model", "Switch AI model", "cpu", "arg" },
            new[] { "explain", "Explain selected code", "questionmark.circle", "" }, new[] { "fix", "Fix errors in selected code", "wrench.and.screwdriver", "" },
            new[] { "test", "Write unit tests for selected code", "checkmark.seal", "" }, new[] { "refactor", "Refactor selected code", "hammer", "" },
            new[] { "review", "Perform a comprehensive senior code review", "checkmark.shield", "" }, new[] { "learn", "Save a persistent rule into .microcode/rules.md", "bookmark", "arg" },
            new[] { "arx", "Export, import, or apply patch from a Portable .ARX Agent Capsule", "shippingbox.fill", "" }, new[] { "compare", "Compare responses from 2 AI models side-by-side", "rectangle.split.2x1", "" },
            new[] { "squad", "Configure or launch multi-agent specialist team", "square.stack.3d.up", "" }, new[] { "pns", "Open PNS 24/7 Neural System Console or dispatch a 24/7 marathon mission", "point.3.connected.trianglepath.dotted", "" },
            new[] { "search", "Search workspace for query", "magnifyingglass", "arg" }, new[] { "terminal", "Include last terminal output", "terminal", "" },
            new[] { "help", "Show list of all slash commands", "info.circle", "" }, new[] { "plan", "Toggle plan mode", "list.bullet.clipboard", "" },
            new[] { "task", "Show/manage tasks", "checklist", "" }
        };

        void UpdateSuggestions()
        {
            string text = _input.Text;
            int caret = _input.CaretIndex;
            if (text.StartsWith("/") && !text.Contains(" ") && !text.Contains("\n"))
            {
                string prefix = text.Substring(1).ToLowerInvariant();
                var hits = Slash.Where(c => c[0].StartsWith(prefix)).ToList();
                if (hits.Count == 0) { CloseSuggestions(); return; }
                ShowSuggestions(hits.Select(c => new[] { c[2], "/" + c[0], c[1], c[3] }).ToList(), hits.Select(c => (Action)(() => { _input.Text = "/" + c[0] + " "; _input.CaretIndex = _input.Text.Length; if (c[3] != "arg") { var cmd = _input.Text; Submit(cmd, TakeAttachments()); } })).ToList());
                return;
            }
            // @mention token right before the caret
            int start = caret - 1;
            while (start >= 0 && !char.IsWhiteSpace(text[start]) && text[start] != '@') start--;
            if (start >= 0 && text[start] == '@' && (start == 0 || char.IsWhiteSpace(text[start - 1])) && _app.WorkspaceFolder != null)
            {
                string q = text.Substring(start + 1, caret - start - 1).Replace('\\', '/').ToLowerInvariant();
                var files = WorkspaceFiles();
                var hits = files.Where(f => q.Length == 0 || f.ToLowerInvariant().Contains(q))
                    .OrderBy(f => Path.GetFileName(f).ToLowerInvariant().StartsWith(q) ? 0 : 1).ThenBy(f => f.Length).Take(8).ToList();
                if (hits.Count == 0) { CloseSuggestions(); return; }
                int s0 = start;
                ShowSuggestions(hits.Select(f => new[] { FileTreeView.IconName(Path.GetFileName(f), false), Path.GetFileName(f), f, "" }).ToList(),
                    hits.Select(f => (Action)(() => { int c2 = _input.CaretIndex; string ins = "@" + f + " "; _input.Text = _input.Text.Substring(0, s0) + ins + _input.Text.Substring(Math.Min(c2, _input.Text.Length)); _input.CaretIndex = s0 + ins.Length; CloseSuggestions(); })).ToList());
                return;
            }
            CloseSuggestions();
        }

        List<string> WorkspaceFiles()
        {
            string ws = _app.WorkspaceFolder;
            if (_fileIndex != null && _fileIndexRoot == ws) return _fileIndex;
            _fileIndexRoot = ws;
            var list = new List<string>();
            var skip = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".git", "node_modules", "bin", "obj", "build", "target", "dist", ".venv", "venv", "__pycache__", ".vs", ".idea", "out" };
            var stack = new Stack<string>(); stack.Push(ws);
            while (stack.Count > 0 && list.Count < 8000)
            {
                string d = stack.Pop();
                try
                {
                    foreach (var f in Directory.GetFiles(d)) list.Add(f.Substring(ws.Length).TrimStart('\\').Replace('\\', '/'));
                    foreach (var sub in Directory.GetDirectories(d)) if (!skip.Contains(Path.GetFileName(sub))) stack.Push(sub);
                }
                catch { }
            }
            _fileIndex = list;
            return list;
        }

        void ShowSuggestions(List<string[]> rows, List<Action> actions)
        {
            var t = Theme.Current;
            if (_suggest == null)
            {
                _suggestList = new StackPanel();
                var sv = new ScrollViewer { Content = _suggestList, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, MaxHeight = 6 * 34 };
                var border = new Border
                {
                    Child = sv, CornerRadius = new CornerRadius(10), Background = Theme.B(t.IsDark ? Color.FromArgb(250, 38, 38, 42) : Color.FromArgb(250, 250, 250, 252)),
                    BorderBrush = t.P(0.12), BorderThickness = new Thickness(1), ClipToBounds = true, Margin = new Thickness(8),
                    Effect = new DropShadowEffect { BlurRadius = 16, ShadowDepth = 3, Direction = 270, Opacity = 0.35 }
                };
                _suggest = new Popup { Child = border, AllowsTransparency = true, StaysOpen = true, Placement = PlacementMode.Top, PlacementTarget = _card, VerticalOffset = 6 };
            }
            ((FrameworkElement)_suggest.Child).Width = Math.Max(320, _card.ActualWidth + 16);
            _suggestList.Children.Clear(); _suggestActions.Clear(); _suggestRows.Clear();
            for (int i = 0; i < rows.Count; i++)
            {
                var r = rows[i];
                int idx = i;
                var line = V.H(10, V.Size(new Grid { Children = { Sym.Icon(r[0], 12.5, t.Secondary, FontWeights.Medium) } }, 18, double.NaN),
                    V.Mono(r[1], 12.5, FontWeights.SemiBold, t.Primary), V.Shrink(V.T(r[2], 11.5, FontWeights.Normal, t.Secondary)), V.Sp());
                if (r[3] == "arg") line.Children.Add(V.Box(V.Mono("arg", 9.5, FontWeights.Normal, t.Secondary), V.P(5, 1.5), t.P(0.08), 4));
                var row = new Border { Height = 34, Padding = new Thickness(12, 0, 12, 0), Child = line, Background = Brushes.Transparent, Cursor = Cursors.Hand };
                row.MouseLeftButtonDown += (s, e) => { e.Handled = true; _suggestIndex = idx; AcceptSuggestion(); };
                row.MouseEnter += delegate { _suggestIndex = idx; PaintSuggestions(); };
                _suggestRows.Add(row);
                _suggestList.Children.Add(row);
                if (i < rows.Count - 1) _suggestList.Children.Add(new Border { Height = 1, Background = t.P(0.08) });
            }
            _suggestActions.AddRange(actions);
            _suggestIndex = 0;
            PaintSuggestions();
            _suggest.IsOpen = true;
        }

        void PaintSuggestions()
        {
            var t = Theme.Current;
            for (int i = 0; i < _suggestRows.Count; i++)
            {
                bool on = i == _suggestIndex;
                _suggestRows[i].Background = on ? t.A(0.14) : Brushes.Transparent;
                var icon = ((Grid)((Stack)_suggestRows[i].Child).Children[0]).Children[0] as SymbolIcon;
                if (icon != null) icon.SetBrush(on ? t.Accent : t.Secondary);
            }
            if (_suggestIndex >= 0 && _suggestIndex < _suggestRows.Count) _suggestRows[_suggestIndex].BringIntoView();
        }

        void MoveSuggestion(int d) { if (_suggestRows.Count == 0) return; _suggestIndex = (_suggestIndex + d + _suggestRows.Count) % _suggestRows.Count; PaintSuggestions(); }
        void AcceptSuggestion() { if (_suggestIndex >= 0 && _suggestIndex < _suggestActions.Count) { var a = _suggestActions[_suggestIndex]; CloseSuggestions(); a(); _input.Focus(); } }
        void CloseSuggestions() { if (_suggest != null) _suggest.IsOpen = false; }

        string RelPath(string full)
        {
            string ws = _app.WorkspaceFolder;
            if (ws != null && full.StartsWith(ws, StringComparison.OrdinalIgnoreCase)) return full.Substring(ws.Length).TrimStart('\\').Replace('\\', '/');
            return full;
        }

        // ── submit / slash commands / queue ────────────────────────────────────
        void ClearComposer() { _input.Text = ""; _attachments.Clear(); RenderAttachments(); RenderSend(); CloseSuggestions(); }

        void Submit(string raw, List<string> files)
        {
            string text = (raw ?? "").Trim();
            if (text.Length == 0 && files.Count == 0) return;
            if (text.StartsWith("/") && Slashed(text, files)) return;
            if (_running) { _queue.Add(new Queued { Text = text, Files = files }); ClearComposer(); RenderQueue(); return; }
            ClearComposer();
            Start(text, files, null);
        }

        void EnqueueInput()
        {
            string text = _input.Text.Trim();
            if (text.Length == 0 && _attachments.Count == 0) return;
            _queue.Add(new Queued { Text = text, Files = TakeAttachments() });
            ClearComposer();
            RenderQueue();
        }

        void SendNow()
        {
            string text = _input.Text.Trim();
            if (text.Length == 0 && _attachments.Count == 0) return;
            _sendAfterStop = new Queued { Text = text, Files = TakeAttachments() };
            ClearComposer();
            Stop();
        }

        void RenderQueue()
        {
            var t = Theme.Current;
            if (_queue.Count == 0) { _queueHost.Child = null; return; }
            var col = V.VLead(3); col.Align = Cross.Stretch;
            col.Children.Add(V.H(6, Sym.Icon("list.bullet", 10, t.SysOrange, FontWeights.SemiBold), V.T("Queued (" + _queue.Count + ") — runs after the active task finishes", 11, FontWeights.SemiBold, t.Secondary), V.Sp(),
                V.Button(V.T("Clear", 10.5, FontWeights.Medium, t.Secondary), () => { _queue.Clear(); RenderQueue(); })));
            foreach (var q in _queue.Take(4))
            {
                var item = q;
                string label = item.Text.Length > 0 ? item.Text.Replace("\n", " ") : item.Files.Count + " attachment(s)";
                var tb = V.T(label, 11.5, FontWeights.Normal, t.P(0.85)); tb.TextTrimming = TextTrimming.CharacterEllipsis;
                col.Children.Add(V.Self(V.H(6, V.Flex(tb), V.Button(Sym.Icon("xmark", 8, t.Secondary, FontWeights.Bold), () => { _queue.Remove(item); RenderQueue(); })), Cross.Stretch));
            }
            _queueHost.Child = V.Box(col, V.P(10, 6), Theme.B(Theme.WithAlpha(Color.FromRgb(255, 159, 10), 0.08)), 8, Theme.B(Theme.WithAlpha(Color.FromRgb(255, 159, 10), 0.25)), 1);
        }

        void LocalReply(string user, string reply)
        {
            var s = AgentStore.Active ?? AgentStore.NewChat(_app.WorkspaceFolder, false);
            if (user != null) s.Messages.Add(new ChatMessage { Role = "user", Content = user });
            s.Messages.Add(new ChatMessage { Role = "assistant", Content = reply });
            if (s.Messages.Count <= 2 && user != null) s.Name = user.Length > 48 ? user.Substring(0, 48) + "…" : user;
            s.Updated = DateTime.Now;
            AgentStore.Save(); AgentStore.Notify();
        }

        /// <summary>SlashCommandService: handles the command locally or rewrites it into a prompt. Returns true when consumed.</summary>
        bool Slashed(string text, List<string> files)
        {
            var m = Regex.Match(text, @"^/(\w+)\s*([\s\S]*)$");
            if (!m.Success) return false;
            string cmd = m.Groups[1].Value.ToLowerInvariant(), arg = m.Groups[2].Value.Trim();
            var cf = _app.CurrentFile;
            string code = cf != null ? "\n\nFile `" + (cf.Path != null ? RelPath(cf.Path) : cf.Name) + "`:\n```" + (cf.Language ?? "") + "\n" + cf.Content + "\n```" : "";
            Func<string, bool> run = prompt => { ClearComposer(); if (_running) { _queue.Add(new Queued { Text = prompt, Files = files }); RenderQueue(); } else Start(prompt, files, null); return true; };
            switch (cmd)
            {
                case "clear": ClearComposer(); HandleCommand("clear"); return true;
                case "help":
                    ClearComposer();
                    LocalReply("/help", "## Slash commands\n\n| Command | What it does |\n|---|---|\n" + string.Join("\n", Slash.Select(c => "| `/" + c[0] + (c[3] == "arg" ? " <arg>" : "") + "` | " + c[1] + " |")) + "\n\nType `@` to mention a workspace file, paste (Ctrl+V) or drop files to attach them.");
                    return true;
                case "plan":
                    ClearComposer();
                    if (arg.Length == 0) { AgentStore.TogglePlan(); UpdatePlaceholder(); return true; }
                    Start("[PLAN MODE — 3-Phase Analysis]\nAnalyze requirements, inspect relevant files/architecture read-only, then call `create_plan` (or present the structured Implementation Plan) for: " + arg, files, true);
                    return true;
                case "task": ClearComposer(); AgentStore.SelectTask(); return true;
                case "model": ClearComposer(); if (arg.Length > 0) { AIConfig.SetModelFor(AIConfig.Provider, arg); _app.Notify("agentBar"); } else SettingsWindow.Show(_app, 2); return true;
                case "learn":
                    ClearComposer();
                    if (arg.Length == 0 || _app.WorkspaceFolder == null) { LocalReply("/learn", _app.WorkspaceFolder == null ? "Open a project folder first — rules are saved to `.microcode/rules.md` inside it." : "Usage: `/learn <rule>`"); return true; }
                    SaveRule(arg); LocalReply("/learn " + arg, "Saved to `.microcode/rules.md` — the agent follows it in every conversation for this project.");
                    return true;
                case "file":
                {
                    if (arg.Length == 0) { ClearComposer(); PickFiles(); return true; }
                    string p = _app.WorkspaceFolder != null && !Path.IsPathRooted(arg) ? Path.Combine(_app.WorkspaceFolder, arg.Replace('/', '\\')) : arg;
                    if (File.Exists(p)) { ClearComposer(); AddAttachment(p); return true; }
                    ClearComposer(); LocalReply("/file " + arg, "File not found: `" + arg + "`");
                    return true;
                }
                case "terminal":
                {
                    string output = (_app.ConsoleOutput ?? "").Trim();
                    if (output.Length == 0) { ClearComposer(); LocalReply("/terminal", "The console is empty — run something first (Ctrl+R)."); return true; }
                    if (output.Length > 12000) output = "…" + output.Substring(output.Length - 12000);
                    return run((arg.Length > 0 ? arg : "Here is the latest terminal output. Explain what happened and fix any errors.") + "\n\n```\n" + output + "\n```");
                }
                case "explain": return run((arg.Length > 0 ? arg + "\n\n" : "") + "Explain this code clearly: what it does, how it works, and anything risky." + code);
                case "fix": return run((arg.Length > 0 ? arg + "\n\n" : "") + "Find and fix the bugs and errors in this code. Edit the file directly and verify." + code);
                case "test": return run((arg.Length > 0 ? arg + "\n\n" : "") + "Write thorough unit tests for this code using the project's test framework, then run them." + code);
                case "refactor": return run((arg.Length > 0 ? arg + "\n\n" : "") + "Refactor this code for readability and maintainability without changing behaviour. Edit the file directly." + code);
                case "review": return run("Perform a comprehensive senior code review" + (arg.Length > 0 ? " of " + arg : " of the current changes (use `git diff` / `git status` via shell)") + ". Report correctness bugs, security issues, performance problems and maintainability concerns, most severe first, with file:line references.");
                case "search": return arg.Length == 0 ? false : run("Search the workspace for `" + arg + "` (grep_search / file_search) and summarise where and how it is used.");
                case "compact": ClearComposer(); Compact(); return true;
                case "pns":
                    // macOS: open the PNS 24/7 console and dispatch the argument as a marathon mission (safe worktree branch policy)
                    ClearComposer();
                    if (arg.Length > 0 && _app.WorkspaceFolder == null) { LocalReply("/pns " + arg, "Open a project folder first — PNS missions run in isolated git worktrees of the open project."); return true; }
                    if (arg.Length > 0 && !AIConfig.IsConfigured) { LocalReply("/pns " + arg, AIClient.NotConnectedText()); return true; }
                    AgentStore.SelectTaskTab(7);
                    if (arg.Length > 0) { var dispatch = PnsOrchestrator.Shared.DispatchMission(arg, _app.WorkspaceFolder, Pns.PolicyIsolated, null, true); }
                    return true;
                case "arx":
                {
                    ClearComposer();
                    var sCur = AgentStore.Active;
                    if (arg.StartsWith("import ", StringComparison.OrdinalIgnoreCase))
                    {
                        string impPath = arg.Substring(7).Trim().Trim('"');
                        try
                        {
                            var cap = ArxCapsuleService.ImportCapsule(impPath);
                            if (cap != null && cap.Session != null)
                            {
                                AgentStore.Sessions.Insert(0, cap.Session);
                                AgentStore.ActiveId = cap.Session.Id;
                                AgentStore.Save(); AgentStore.Notify();
                                LocalReply("/arx import", "Imported `.arx` capsule (" + cap.Session.Messages.Count + " messages, " + cap.Rules.Count + " rules, " + cap.Memories.Count + " memories).");
                            }
                        }
                        catch (Exception ex) { LocalReply("/arx import", "Failed: " + ex.Message); }
                        return true;
                    }
                    if (sCur == null) { LocalReply("/arx", "No active conversation to export."); return true; }
                    string defDir = _app.WorkspaceFolder != null ? Path.Combine(_app.WorkspaceFolder, ".microcode") : Defaults.Dir;
                    string outPath = arg.Length > 0 && !arg.Equals("export", StringComparison.OrdinalIgnoreCase) ? arg.Trim('"') : Path.Combine(defDir, "capsule-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".arx");
                    try { LocalReply("/arx export", "Exported `.arx` capsule to `" + ArxCapsuleService.ExportCapsule(sCur, outPath) + "`."); }
                    catch (Exception ex) { LocalReply("/arx export", "Failed: " + ex.Message); }
                    return true;
                }
                case "acp":
                {
                    if (arg.Length == 0) { ClearComposer(); LocalReply("/acp", "Usage: `/acp <claude|codex|gemini|goose|opencode|aider> <prompt>`\nAvailable: " + string.Join(", ", AcpHostService.ListAvailable().Select(a => a.Id))); return true; }
                    int sp = arg.IndexOf(' ');
                    if (sp <= 0) { ClearComposer(); LocalReply("/acp " + arg, "Usage: `/acp " + arg + " <prompt>`"); return true; }
                    string aid = arg.Substring(0, sp).Trim(), promptA = arg.Substring(sp + 1).Trim();
                    ClearComposer();
                    string wsA = _app.WorkspaceFolder;
                    LocalReply("/acp " + aid + " " + promptA, "Running external ACP harness `" + aid + "`…");
                    Task.Run(() => AcpHostService.RunPrompt(aid, promptA, wsA, 120000)).ContinueWith(tk => Dispatcher.BeginInvoke(new Action(() =>
                    {
                        var r = tk.Status == TaskStatus.RanToCompletion ? tk.Result : null;
                        string outTxt = r == null ? "ACP execution failed." : (r.Success ? r.Output : "Exit " + r.ExitCode + "\n" + r.Error + "\n" + r.Output);
                        var act = AgentStore.Active;
                        if (act != null && act.Messages.Count > 0) { act.Messages[act.Messages.Count - 1].Content = "### ACP Harness (`" + aid + "`)\n\n" + outTxt; AgentStore.Save(); AgentStore.Notify(); }
                    })));
                    return true;
                }
                case "squad":
                {
                    if (arg.Length == 0) { ClearComposer(); LocalReply("/squad", "Usage: `/squad <task description>` — dispatches Architect, Implementer & Reviewer sub-agents."); return true; }
                    ClearComposer();
                    string wsS = _app.WorkspaceFolder;
                    LocalReply("/squad " + arg, "Dispatching 3-specialist Agent Squad (Architect · Implementer · Reviewer)…");
                    Task.Run(() => SubAgentHarness.RunSquad(arg, wsS)).ContinueWith(tk => Dispatcher.BeginInvoke(new Action(() =>
                    {
                        var act = AgentStore.Active;
                        if (act != null && act.Messages.Count > 0)
                        {
                            act.Messages[act.Messages.Count - 1].Content = tk.Status == TaskStatus.RanToCompletion ? tk.Result.Summary : "Squad failed: " + (tk.Exception != null ? tk.Exception.GetBaseException().Message : "error");
                            AgentStore.Save(); AgentStore.Notify();
                        }
                    })));
                    return true;
                }
                case "compare":
                {
                    if (arg.Length == 0) { ClearComposer(); LocalReply("/compare", "Usage: `/compare <prompt>` — compares responses from 2 models side by side."); return true; }
                    ClearComposer();
                    if (!AIConfig.IsConfigured) { LocalReply("/compare " + arg, AIClient.NotConnectedText()); return true; }
                    string altModel = DotminiCloud.Models.Count > 1 ? DotminiCloud.Models.Select(x => x.Id).FirstOrDefault(id => id != AIConfig.ModelDisplayName) : AIConfig.ModelFor(AIConfig.Provider);
                    var msgListA = new List<ChatMessage> { new ChatMessage { Role = "user", Content = arg } };
                    string wsCmp = _app.WorkspaceFolder;
                    LocalReply("/compare " + arg, "Running parallel model comparison (`" + AIConfig.BadgeTitle + " · " + AIConfig.ModelDisplayName + "` vs `" + (altModel ?? "secondary") + "`)…");
                    Task.Run(async () =>
                    {
                        var t1 = AgentRunner.Run(msgListA, "Answer concisely and accurately.", false, true, null, new AgentCallbacks(), CancellationToken.None);
                        var inst = SubAgentHarness.InvokeSubagent("self", "Compare Model", arg, altModel ?? "secondary", wsCmp);
                        await Task.WhenAll(t1);
                        SubAgentHarness.WaitSubagent(inst.Id, 45000);
                        string r1 = t1.Status == TaskStatus.RanToCompletion ? t1.Result.Text : "(error)";
                        string r2 = !string.IsNullOrEmpty(inst.Result) ? inst.Result : r1;
                        return "## Model Comparison\n\n### Model A (`" + AIConfig.ModelDisplayName + "`)\n" + r1 + "\n\n---\n\n### Model B (`" + (altModel ?? "secondary") + "`)\n" + r2;
                    }).ContinueWith(tk => Dispatcher.BeginInvoke(new Action(() =>
                    {
                        var act = AgentStore.Active;
                        if (act != null && act.Messages.Count > 0)
                        {
                            act.Messages[act.Messages.Count - 1].Content = tk.Status == TaskStatus.RanToCompletion ? tk.Result : "Compare failed.";
                            AgentStore.Save(); AgentStore.Notify();
                        }
                    })));
                    return true;
                }
            }
            return false;
        }

        /// <summary>/compact: summarise the conversation and replace the history with the summary.</summary>
        void Compact()
        {
            var s = AgentStore.Active;
            if (s == null || s.Messages.Count < 2 || _running) return;
            if (!AIConfig.IsConfigured) { LocalReply("/compact", AIClient.NotConnectedText()); return; }
            var history = s.Messages.ToList();
            history.Add(new ChatMessage { Role = "user", Content = "Summarize our conversation so far into a compact brief that preserves every decision, file path, open task and important detail needed to continue the work. Use headings and bullets." });
            var sb = new StringBuilder();
            _running = true; RenderSend();
            AIClient.Stream(history, "You compress chat history for an AI coding agent.", d => { lock (sb) sb.Append(d); }, CancellationToken.None).ContinueWith(tk => Dispatcher.BeginInvoke(new Action(() =>
            {
                _running = false; RenderSend();
                string summary; lock (sb) summary = sb.ToString().Trim();
                if (tk.IsFaulted || summary.Length == 0) { LocalReply("/compact", "Could not compact: " + (tk.IsFaulted ? AIException.Describe(tk.Exception, AIConfig.Mode == "cloud") : "empty summary")); return; }
                int n = s.Messages.Count;
                s.Messages.Clear();
                s.Messages.Add(new ChatMessage { Role = "assistant", Content = "**Conversation compacted** (" + n + " messages → summary)\n\n" + summary });
                AgentStore.Save(); AgentStore.Notify();
            })));
        }

        static readonly Regex MentionRe = new Regex(@"(?<=^|\s)@([^\s@]+)");

        // ── running a turn ─────────────────────────────────────────────────────
        string SystemPrompt(string ws, bool plan, bool tools, string userPrompt)
        {
            string persona = Defaults.Str("agentPersona", "main");
            var sb = new StringBuilder();
            sb.Append("You are MicroCode AI — a senior full-stack software engineer integrated into the MicroCode IDE, running natively on Windows.\nYour role is to help the user understand, modify, debug, and build production-quality software.\n\n");
            sb.Append("## Communication Style\n- Professional, authoritative, and precise. Use structured output: headings and concise bullet points.\n- When the user writes in Thai, respond in Thai. When in English, respond in English.\n- Be direct. No filler. Lead with the most important information.\n");
            if (tools) sb.Append("- NEVER dump whole source files into the chat: create or change project files with `file_write` / `replace_in_file` directly in the workspace; the IDE shows the edits. Keep chat prose concise.\n");
            sb.Append("- Use fenced code blocks with a language tag for snippets.\n\n");
            if (ws != null && tools)
            {
                sb.Append("## Workspace\n- Active project: `" + ws + "`. All tool paths are relative to this root; never touch files of other projects.\n- OS: Windows. `shell` runs cmd.exe; use `powershell -NoProfile -Command \"…\"` when PowerShell is needed.\n\n");
                sb.Append("## Rules\n1. Take action — read files, WRITE changes, RUN commands. Don't just describe.\n2. Read a file before modifying it. Locate code with `grep_search` / `file_search` first and read only the relevant ranges (`start_line` / `end_line`).\n3. Make minimal, targeted edits with `replace_in_file`; use `file_write` for new files or complete rewrites.\n4. After changes, verify by running the build / tests with `shell`. If a command fails, analyse the error and fix it.\n5. Aim to finish in 3–6 iterations; call independent tools together in one turn.\n6. SAFETY: never delete user files or folders blindly (`rmdir /s`, `del /s`, `git clean -fdx` are forbidden); never `git init`, `git commit` or `git push` unless the user asks.\n7. Never write API keys, passwords or tokens into files or logs.\n8. Files protected by Scope Lock cannot be edited; tell the user instead of working around it.\n9. For multi-step implementations keep a checklist in `.microcode/task.md` (check items off `- [x]` only after verification) and summarize the outcome in `.microcode/walkthrough.md`. Do not touch task.md for simple questions.\n");
                string agentMd = TaskFiles.Exists(ws, "agent.md") ? TaskFiles.Read(ws, "agent.md") : null;
                if (!string.IsNullOrWhiteSpace(agentMd)) sb.Append("\n## Workspace Agent Directive (.microcode/agent.md)\n" + (agentMd.Length > 8000 ? agentMd.Substring(0, 8000) + "\n…" : agentMd) + "\n");
            }
            else if (ws == null) sb.Append("## Workspace\nNo project folder is open, so you cannot read or change files. Answer directly; suggest opening a folder (File → Open Folder) when file access is needed.\n");
            if (plan)
                sb.Append("\n[PLAN MODE — MANDATORY ANALYSIS BEFORE PLANNING (ห้ามมั่วเด็ดขาด)]\n1. Research first: explore the REAL workspace with `list_directory_tree`, `file_read`, `grep_search` and `file_search`. Never invent file paths or use generic placeholder steps.\n2. Then reply with the implementation plan in Markdown:\n   # Implementation Plan: <specific title>\n   ## Summary\n   ## User Review Required — breaking changes, trade-offs, decisions\n   ## Open Questions\n   ## Proposed Changes — grouped by component; tag every file `[NEW]`, `[MODIFY]` or `[DELETE]` and say exactly what changes\n   ## Verification Plan — exact build / test commands and manual checks\n3. ZERO MUTATION before approval: do NOT edit files or run mutating commands. The user reviews the plan and clicks Approve before anything is changed.\n");
            if (persona == "explorer") sb.Append("\n[EXPLORER] Research the codebase read-only and report findings with file:line references. Do not edit files.\n");
            else if (persona == "reviewer") sb.Append("\n[REVIEWER] Act as a senior code reviewer: find correctness bugs, security issues and risky patterns, most severe first, with file:line references. Do not edit files unless asked.\n");
            sb.Append(AgentContext.Extra(ws, userPrompt));
            string mem = AgentMemoryService.FormatForPrompt(userPrompt ?? "", ws, 5);
            if (!string.IsNullOrEmpty(mem)) sb.Append(mem);
            if (ws != null && tools)
            {
                string repoMap = RepoMapService.BuildRepoMap(ws, 2200);
                if (!string.IsNullOrEmpty(repoMap)) sb.Append("\n\n").Append(repoMap);
            }
            // Shared tasks are explicit, reviewable contracts: only the selected contract, never another person's prompts
            string teamTask = CollabService.HasShared ? CollabService.Shared.Tasks.ContextForSelectedTask() : null;
            if (teamTask != null) sb.Append("\n\n").Append(teamTask);
            return sb.ToString();
        }

        void Start(string text, List<string> files, bool? planOverride, Action<ChatMessage> onReply = null)
        {
            var s = AgentStore.Active ?? AgentStore.NewChat(_app.WorkspaceFolder, false);
            if (s.Messages.Count == 0) s.Name = text.Length > 0 ? (text.Length > 48 ? text.Substring(0, 48) + "…" : text) : Path.GetFileName(files.FirstOrDefault() ?? "Attachment");
            string ws = _app.WorkspaceFolder;
            // @mentions → file context + Strict Scope allow-list
            var mentioned = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (ws != null)
                foreach (Match mm in MentionRe.Matches(text))
                {
                    string p = Path.GetFullPath(Path.Combine(ws, mm.Groups[1].Value.Trim('.', ',', ';', ')').Replace('/', '\\')));
                    if (File.Exists(p) && p.StartsWith(ws, StringComparison.OrdinalIgnoreCase)) { mentioned.Add(p); if (!files.Any(f => string.Equals(f, p, StringComparison.OrdinalIgnoreCase))) files.Add(p); }
                }
            ScopeLock.Mentioned = mentioned;
            var userMsg = new ChatMessage { Role = "user", Content = text, Attachments = files };
            s.Messages.Add(userMsg);
            s.Updated = DateTime.Now;
            bool revision = _planRevision;
            _planRevision = false;
            UpdatePlaceholder();
            AgentStore.Save();
            AgentStore.Notify(); // sidebar + header pick up the new conversation title
            if (!AIConfig.IsConfigured)
            {
                var notConnected = new ChatMessage { Role = "assistant", Content = "", Error = AIClient.NotConnectedText(), ErrorFix = AIConfig.Mode == "cloud" ? "account" : "ai" };
                s.Messages.Add(notConnected);
                AgentStore.Save(); AgentStore.Notify();
                if (onReply != null) onReply(notConnected);
                return;
            }
            string persona = Defaults.Str("agentPersona", "main");
            bool plan = planOverride ?? (AgentStore.Bar.PlanMode || persona == "planner" || revision);
            bool tools = AgentRunner.AgentModeEnabled && ws != null;
            bool readOnly = plan || persona == "explorer" || persona == "reviewer";
            string system = SystemPrompt(ws, plan && tools, tools, text);
            var history = s.Messages.ToList();

            _running = true;
            RenderSend();
            _cts = new CancellationTokenSource();
            var token = _cts.Token;
            var live = new LiveTurn(this);
            _live = live;
            _transcript.Children.Add(live.Row);
            _scroll.ScrollToEnd();
            var cb = new AgentCallbacks
            {
                OnText = live.AddText, OnThinking = live.AddThinking, OnActivity = live.SetActivity,
                OnStepStart = live.StepStarted, OnStep = live.StepDone,
                Approve = (step, args) =>
                {
                    var tcs = new TaskCompletionSource<bool>();
                    Dispatcher.BeginInvoke(new Action(() => ShowApproval(step, args, tcs)));
                    return tcs.Task;
                }
            };
            var started = DateTime.Now;
            string sid = s.Id;
            Task.Run(() => AgentRunner.Run(history, system, tools, readOnly, sid, cb, token), token).ContinueWith(task => Dispatcher.BeginInvoke(new Action(() =>
            {
                live.Stop();
                ClearApproval(false);
                _running = false;
                _live = null;
                var reply = new ChatMessage { Role = "assistant", ThoughtSeconds = (DateTime.Now - started).TotalSeconds };
                if (task.Status == TaskStatus.RanToCompletion)
                {
                    var r = task.Result;
                    var ev = ExecutionEvidenceGuard.CheckCompletion(r.Steps, r.Text);
                    reply.Content = (ev != null && !ev.Passed && ev.Warnings.Count > 0) ? (r.Text + "\n\n> ⚠️ **Evidence Guard**: " + string.Join("; ", ev.Warnings)) : r.Text;
                    reply.Thinking = r.Thinking; reply.Steps = r.Steps; reply.Model = r.Model;
                    reply.InputTokens = r.InputTokens; reply.OutputTokens = r.OutputTokens; reply.Requests = r.Requests; reply.UsageEstimated = r.Estimated;
                    if (plan && tools && r.Text.Trim().Length > 0) reply.PlanState = "pending";
                    if (r.Steps != null && r.Steps.Count > 0 && !string.IsNullOrEmpty(r.Text))
                        AgentMemoryService.Remember(s.Name ?? "Task", r.Text.Length > 360 ? r.Text.Substring(0, 360) : r.Text, ws);
                }
                else
                {
                    reply.Content = live.AllText(); reply.Steps = live.Steps(); reply.Thinking = live.Thinking();
                    var ex = task.Exception != null ? task.Exception.GetBaseException() : null;
                    if (task.IsCanceled || ex is OperationCanceledException) reply.Content = (reply.Content.Length > 0 ? reply.Content + "\n\n" : "") + "_Stopped._";
                    else
                    {
                        reply.Error = AIException.Describe(ex, AIConfig.Mode == "cloud");
                        var ae = ex as AIException;
                        reply.ErrorFix = ae != null ? ae.Fix : "ai";
                    }
                }
                s.Messages.Add(reply);
                s.Updated = DateTime.Now;
                AgentStore.Save();
                RenderSend();
                AgentStore.Notify();
                if (onReply != null) { try { onReply(reply); } catch (Exception cbEx) { System.Diagnostics.Debug.WriteLine("agent reply observer: " + cbEx); } }
                if (_sendAfterStop != null) { var q = _sendAfterStop; _sendAfterStop = null; Start(q.Text, q.Files, null, q.OnReply); }
                else if (_queue.Count > 0 && task.Status == TaskStatus.RanToCompletion) { var q = _queue[0]; _queue.RemoveAt(0); RenderQueue(); Start(q.Text, q.Files, null, q.OnReply); }
                else if (_queue.Count > 0)
                {
                    // the run failed or was stopped, so the queue waits for the user; requests from teammates get an answer now
                    foreach (var q in _queue.Where(x => x.OnReply != null).ToList()) { _queue.Remove(q); q.OnReply(new ChatMessage { Role = "assistant", Content = "", Error = "The agent's previous run did not finish, so this request was not started." }); }
                    RenderQueue();
                }
            })));
        }

        void Stop()
        {
            if (_cts != null && !_cts.IsCancellationRequested) _cts.Cancel();
            ClearApproval(false);
        }

        // ── inline tool approval (ToolApprovalView) ────────────────────────────
        void ShowApproval(ToolStep step, Dictionary<string, object> args, TaskCompletionSource<bool> tcs)
        {
            if (_cts == null || _cts.IsCancellationRequested) { tcs.TrySetResult(false); return; }
            var t = Theme.Current;
            _pendingApproval = tcs;
            _pendingApprovalToolName = step != null ? (step.Name ?? "tool") : "tool";
            _pendingApprovalDescription = step != null ? AgentRunner.RequestText(step) : "";
            string risk = AgentRunner.Risk(step);
            Color rc = risk == "critical" ? Color.FromRgb(255, 69, 58) : risk == "dangerous" ? Color.FromRgb(255, 159, 10) : risk == "moderate" ? Color.FromRgb(255, 214, 10) : Color.FromRgb(48, 209, 88);
            var keys = args.Keys.OrderBy(k => k).ToList();
            bool expanded = false;
            var argsBox = V.VLead(2.5); argsBox.Align = Cross.Stretch;
            Action renderArgs = null;
            var chevron = Sym.Icon("chevron.down", 8.5, t.Secondary, FontWeights.SemiBold);
            renderArgs = () =>
            {
                argsBox.Children.Clear();
                foreach (var k in expanded ? keys : keys.Take(2).ToList())
                {
                    string v = AgentRunner.Arg(args, k);
                    if (!expanded) { v = v.Replace("\r", "").Replace("\n", " ⏎ "); if (v.Length > 140) v = v.Substring(0, 70) + " … " + v.Substring(v.Length - 60); }
                    else if (v.Length > 4000) v = v.Substring(0, 4000) + "\n…";
                    var val = V.Mono(v, 9.5, FontWeights.Normal, t.P(0.9));
                    if (expanded) val.TextWrapping = TextWrapping.Wrap; else val.TextTrimming = TextTrimming.CharacterEllipsis;
                    argsBox.Children.Add(V.Self(V.H(4, V.Self(V.Mono(k + ":", 9.5, FontWeights.Medium, t.S(0.7)), Cross.Start), V.Flex(val)), Cross.Stretch));
                }
                if (!expanded && keys.Count > 2) argsBox.Children.Add(V.Mono("+" + (keys.Count - 2) + " more parameter(s)...", 8.5, FontWeights.Normal, t.S(0.6)));
                chevron.Glyph.Text = Sym.GlyphText(expanded ? "chevron.up" : "chevron.down");
            };
            renderArgs();
            var toggle = V.Button(V.Box(chevron, V.P(2), Brushes.Transparent, 0), () => { expanded = !expanded; renderArgs(); });
            toggle.ToolTip = "Expand all parameters";
            var head = V.H(6, Sym.Icon(risk == "critical" || risk == "dangerous" ? "exclamationmark.shield.fill" : "shield.lefthalf.filled", 11, Theme.B(rc), FontWeights.SemiBold),
                V.T("Permission Required", 11, FontWeights.SemiBold, t.Primary),
                V.Box(V.H(4, Sym.Icon("terminal", 8.5, t.Secondary), V.Mono(step.Name, 10, FontWeights.SemiBold, t.Secondary)), V.P(6, 2), Theme.B(Theme.WithAlpha(Colors.White, 0.06)), 4),
                V.Shrink(V.T(AgentRunner.RequestText(step), 10.5, FontWeights.Normal, t.S(0.85))), V.Sp(),
                V.Box(V.Mono(risk.ToUpperInvariant(), 8.5, FontWeights.Bold, Theme.B(rc)), V.P(5, 2), Theme.B(Theme.WithAlpha(rc, 0.12)), 3.5), toggle);
            var reject = V.Button(V.Box(V.H(4, Sym.Icon("xmark", 8.5, Theme.B(Theme.WithAlpha(Color.FromRgb(255, 69, 58), 0.85)), FontWeights.Bold), V.T("Reject", 10.5, FontWeights.Medium, Theme.B(Theme.WithAlpha(Color.FromRgb(255, 69, 58), 0.85)))), V.P(10, 4), Theme.B(Theme.WithAlpha(Color.FromRgb(255, 69, 58), 0.08)), 5, Theme.B(Theme.WithAlpha(Color.FromRgb(255, 69, 58), 0.2)), 0.5), () => ResolveApproval(false));
            var always = V.Button(V.Box(V.H(4, Sym.Icon("lock.open", 8.5, t.Secondary), V.T("Always Allow", 10.5, FontWeights.Medium, t.Secondary)), V.P(9, 4), Theme.B(Theme.WithAlpha(Colors.White, 0.04)), 5, Theme.B(Theme.WithAlpha(Colors.White, 0.08)), 0.5), () => { AgentRunner.AlwaysAllow(step.Name); ResolveApproval(true); });
            always.ToolTip = "Approve " + step.Name + " for the rest of this session";
            var approve = V.Button(V.Box(V.H(4, Sym.Icon("checkmark", 8.5, Brushes.White, FontWeights.Bold), V.T("Approve", 10.5, FontWeights.SemiBold, Brushes.White)), V.P(12, 4), t.Accent, 5), () => ResolveApproval(true));
            approve.ToolTip = "Approve (Enter)";
            var col = V.VLead(7, V.Self(head, Cross.Stretch), V.Self(V.Box(argsBox, V.P(7, 4), Theme.B(Theme.WithAlpha(Colors.White, 0.03)), 5), Cross.Stretch), V.Self(V.H(8, reject, V.Sp(), always, approve), Cross.Stretch));
            col.Align = Cross.Stretch;
            var card = V.Box(col, V.P(10, 8), Theme.B(t.IsDark ? Color.FromArgb(245, 28, 28, 33) : Color.FromArgb(250, 246, 246, 248)), 9, Theme.B(Theme.WithAlpha(Colors.White, 0.08)), 0.8);
            card.Effect = new DropShadowEffect { BlurRadius = 12, ShadowDepth = 2, Direction = 270, Opacity = 0.3 };
            _approvalHost.Child = card;
            _approvalHost.Focusable = true;
            _approvalHost.PreviewKeyDown -= ApprovalKeys;
            _approvalHost.PreviewKeyDown += ApprovalKeys;
            if (_live != null) _live.SetActivity("Waiting for your approval…");
            Dispatcher.BeginInvoke(new Action(() => _approvalHost.Focus()), DispatcherPriority.Input);
        }

        void ApprovalKeys(object s, KeyEventArgs e)
        {
            if (_pendingApproval == null) return;
            if (e.Key == Key.Enter) { ResolveApproval(true); e.Handled = true; }
            else if (e.Key == Key.Escape) { ResolveApproval(false); e.Handled = true; }
        }

        void ResolveApproval(bool ok)
        {
            var p = _pendingApproval;
            _pendingApprovalToolName = "";
            _pendingApprovalDescription = "";
            _pendingApproval = null;
            _approvalHost.Child = null;
            if (p != null) p.TrySetResult(ok);
            _input.Focus();
        }

        void ClearApproval(bool ok) { if (_pendingApproval != null) ResolveApproval(ok); else _approvalHost.Child = null; }

        // ── transcript ─────────────────────────────────────────────────────────
        void RenderTranscript()
        {
            _transcript.Children.Clear();
            var s = AgentStore.Active;
            if (s == null || s.Messages.Count == 0)
            {
                _bottomHost.Child = null;
                _scroll.Visibility = Visibility.Collapsed;
                _emptyHost.Child = EmptyState();
                UpdatePlaceholder();
                return;
            }
            _emptyHost.Child = null;
            _scroll.Visibility = Visibility.Visible;
            if (_bottomHolder == null) _bottomHolder = new Border { MaxWidth = 880, Margin = new Thickness(28, 6, 28, 14) };
            if (_bottomHolder.Child != _composer) { Detach(_composer); _bottomHolder.Child = _composer; }
            if (_bottomHost.Child != _bottomHolder) _bottomHost.Child = _bottomHolder;
            foreach (var m in s.Messages) _transcript.Children.Add(MessageRow(m));
            if (_live != null && _live.Row.Parent == null) _transcript.Children.Add(_live.Row);
            _scroll.ScrollToEnd();
            UpdatePlaceholder();
        }

        /// <summary>RichMessageRow: user bubble (right, max 620) / assistant cell content (left, max 880) + hover action toolbar.</summary>
        UIElement MessageRow(ChatMessage m)
        {
            var t = Theme.Current;
            var msg = m;
            var session = AgentStore.Active;
            Func<string, string, string, bool, Action, Btn> act = (icon, label, tip, destructive, a) =>
            {
                Brush fg = destructive ? t.Op(t.SysRed, 0.85) : t.Secondary;
                var b = V.Button(V.Box(V.H(3.5, Sym.Icon(icon, 9.5, fg, FontWeights.Medium), V.T(label, 10, FontWeights.Medium, fg)), V.P(7, 3.5), t.P(0.045), 5, t.P(0.08), 0.5), a);
                b.ToolTip = tip;
                return b;
            };
            Action<string> copy = s => { try { Clipboard.SetText(s); } catch { } };
            Action delete = () => { if (session != null && !_running) { session.Messages.Remove(msg); AgentStore.Save(); AgentStore.Notify(); } };
            StackPanel toolbar;
            Grid row = new Grid();
            if (m.Role == "user")
            {
                var inner = V.VLead(6); inner.Align = Cross.End;
                if (m.Attachments != null && m.Attachments.Count > 0)
                {
                    var chips = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Right };
                    foreach (var f in m.Attachments)
                    {
                        var path = f;
                        var chip = V.Button(V.Box(V.H(5, Sym.Icon(AgentRunner.IsImage(f) ? "photo" : FileTreeView.IconName(Path.GetFileName(f), false), 10.5, t.Secondary), V.T(Path.GetFileName(f), 10.5, FontWeights.Medium, t.P(0.85))), V.P(6, 2.5), t.P(0.05), 5, t.P(0.08), 0.5), () => { if (File.Exists(path)) PreviewDock.OpenFile(path); });
                        chip.ToolTip = f;
                        chip.Margin = new Thickness(4, 0, 0, 4);
                        chips.Children.Add(chip);
                    }
                    inner.Children.Add(chips);
                }
                if ((m.Content ?? "").Length > 0)
                {
                    var text = V.Wrap(V.T(m.Content, Defaults.Num("agentFontSize", 16), FontWeights.Normal, t.P(0.95)), TextAlignment.Left);
                    var bubble = V.Box(text, V.P(14, 10), t.P(t.IsDark ? 0.095 : 0.065), 14, t.P(t.IsDark ? 0.14 : 0.10), 0.8);
                    bubble.MaxWidth = 620;
                    inner.Children.Add(bubble);
                }
                toolbar = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Opacity = 0 };
                toolbar.Children.Add(act("arrow.uturn.backward", "ย้อนกลับ", "Restore Checkpoint — ย้อนกลับข้อความและการแก้ไขไฟล์มาที่จุดนี้ (Revert to this checkpoint)", false, () => RestoreTo(msg, false)));
                toolbar.Children.Add(act("pencil", "แก้ไข", "แก้ไขข้อความและส่งใหม่ (Edit & Resend)", false, () => { if (session != null && !_running) { int i = session.Messages.IndexOf(msg); if (i >= 0) { AgentRunner.Revert(session.Messages.Skip(i).SelectMany(x => x.Steps)); session.Messages.RemoveRange(i, session.Messages.Count - i); AgentStore.Save(); AgentStore.Notify(); _input.Text = msg.Content; foreach (var f in msg.Attachments) AddAttachment(f); _input.Focus(); _input.CaretIndex = _input.Text.Length; } } }));
                toolbar.Children.Add(act("bookmark", "บันทึกกฎ", "บันทึกคำสั่งนี้เป็นกฎของโปรเจกต์ใน .microcode/rules.md (Save as Project Rule)", false, () => SaveRule(msg.Content)));
                toolbar.Children.Add(act("doc.on.doc", "คัดลอก", "คัดลอกข้อความ (Copy message)", false, () => copy(msg.Content)));
                toolbar.Children.Add(act("trash", "ลบ", "ลบข้อความนี้ (Delete message)", true, delete));
                foreach (FrameworkElement c in toolbar.Children) c.Margin = new Thickness(4, 0, 0, 0);
                var col = V.VLead(6, V.Self(inner, Cross.End), V.Self(toolbar, Cross.End));
                col.Align = Cross.End;
                var outer = new Border { Child = col, MaxWidth = 880, Padding = new Thickness(88, 0, 0, 0) };
                row.Children.Add(outer);
                row.Margin = new Thickness(12, 6, 12, 6);
            }
            else
            {
                var content = AssistantContent(m);
                toolbar = new StackPanel { Orientation = Orientation.Horizontal, Opacity = 0 };
                toolbar.Children.Add(act("doc.on.doc", "คัดลอก", "คัดลอกคำตอบ (Copy response)", false, () => copy(AgentBlocks.StripThoughts(msg.Content))));
                toolbar.Children.Add(act("arrow.clockwise", "ลองใหม่", "สร้างคำตอบใหม่อีกครั้ง (Regenerate response)", false, () => Regenerate(msg)));
                int files = msg.Steps.Count(s2 => !string.IsNullOrEmpty(s2.Checkpoint));
                toolbar.Children.Add(act("arrow.uturn.backward", files == 0 ? "ย้อนกลับ" : "ย้อนกลับ (" + files + " ไฟล์)", "Restore Checkpoint — ย้อนกลับคำตอบนี้และคืนค่าไฟล์ที่ถูกแก้ไข (Revert turn & restore files)", false, () => RestoreTo(msg, true)));
                toolbar.Children.Add(act("trash", "ลบ", "ลบข้อความนี้ (Delete message)", true, delete));
                foreach (FrameworkElement c in toolbar.Children) c.Margin = new Thickness(0, 0, 4, 0);
                if (!string.IsNullOrEmpty(m.Model)) toolbar.Children.Add(V.Box(V.T(AIConfig.FormatModelName(m.Model), 9.5, FontWeights.Normal, t.S(0.6)), V.P(4, 4, 0, 0), null, 0));
                var col = V.VLead(6, V.Self(content, Cross.Stretch), toolbar);
                col.Align = Cross.Stretch;
                row.Children.Add(new Border { Child = col, MaxWidth = 880, HorizontalAlignment = HorizontalAlignment.Stretch });
                row.Margin = new Thickness(12, 8, 12, 8);
            }
            row.Background = Brushes.Transparent;
            row.MouseEnter += delegate { toolbar.Opacity = 0.92; };
            row.MouseLeave += delegate { toolbar.Opacity = 0; };
            return row;
        }

        /// <summary>Restore Checkpoint: drop the conversation after this point and restore every file the agent edited since.</summary>
        void RestoreTo(ChatMessage msg, bool includeThis)
        {
            var session = AgentStore.Active;
            if (session == null || _running) return;
            int i = session.Messages.IndexOf(msg);
            if (i < 0) return;
            int from = includeThis ? i : i + 1;
            var dropped = session.Messages.Skip(from).ToList();
            int restored = AgentRunner.Revert(dropped.SelectMany(x => x.Steps));
            session.Messages.RemoveRange(from, session.Messages.Count - from);
            AgentStore.Save(); AgentStore.Notify();
            if (restored > 0) _app.AppendConsole("↩ Restored " + restored + " file edit(s) from the agent checkpoint.\n");
        }

        void Regenerate(ChatMessage msg)
        {
            var session = AgentStore.Active;
            if (session == null || _running) return;
            int i = session.Messages.IndexOf(msg);
            if (i <= 0) return;
            var prompt = session.Messages[i - 1];
            AgentRunner.Revert(session.Messages.Skip(i).SelectMany(x => x.Steps));
            session.Messages.RemoveRange(i - 1, session.Messages.Count - i + 1);
            AgentStore.Save();
            Start(prompt.Content, new List<string>(prompt.Attachments ?? new List<string>()), null);
        }

        void SaveRule(string text)
        {
            string ws = _app.WorkspaceFolder;
            if (ws == null) return;
            try
            {
                string dir = Path.Combine(ws, ".microcode"); Directory.CreateDirectory(dir);
                File.AppendAllText(Path.Combine(dir, "rules.md"), "- " + text.Replace("\n", " ") + Environment.NewLine);
            }
            catch { }
        }

        /// <summary>AICellContentHost: thought header, interleaved text / tool steps, code cards, plan review and error cards.</summary>
        UIElement AssistantContent(ChatMessage m)
        {
            var col = V.VLead(12); col.Align = Cross.Stretch;
            string content = m.Content ?? "";
            var inlineThoughts = AgentBlocks.Parse(content).Where(x => x.Kind == "thought").Select(x => x.Text).ToList();
            string thinking = string.Join("\n\n", new[] { m.Thinking }.Concat(inlineThoughts).Where(x => !string.IsNullOrWhiteSpace(x)));
            if (thinking.Trim().Length > 0) col.Children.Add(ThoughtView(thinking, m.ThoughtSeconds));
            // steps before any text, then text segments split at the offsets where tools ran
            var steps = m.Steps ?? new List<ToolStep>();
            int pos = 0;
            var pending = new List<ToolStep>();
            foreach (var st in steps.Where(x => x.At <= 0)) pending.Add(st);
            if (pending.Count > 0) col.Children.Add(StepsView(pending));
            foreach (var group in steps.Where(x => x.At > 0).GroupBy(x => Math.Min(x.At, content.Length)).OrderBy(g => g.Key))
            {
                AddText(col, content.Substring(pos, group.Key - pos));
                pos = group.Key;
                col.Children.Add(StepsView(group.ToList()));
            }
            AddText(col, content.Substring(Math.Min(pos, content.Length)));
            var cards = ChangeCards(m);
            if (cards != null) col.Children.Add(cards);
            if (!string.IsNullOrEmpty(m.Error)) col.Children.Add(ErrorCard(m));
            if (m.PlanState == "pending" && AgentStore.Active != null && AgentStore.Active.Messages.LastOrDefault() == m) col.Children.Add(PlanReviewCard(m));
            else if (m.PlanState == "approved" || m.PlanState == "rejected") col.Children.Add(PlanStatus(m.PlanState));
            if (col.Children.Count == 0) col.Children.Add(V.T("(no reply)", 12.5, FontWeights.Normal, Theme.Current.Secondary));
            return col;
        }

        /// <summary>One PendingChangeCard per file the turn edited (first "before" → last "after"), with Revert / Restore.</summary>
        UIElement ChangeCards(ChatMessage m)
        {
            var edits = (m.Steps ?? new List<ToolStep>()).Where(s => !string.IsNullOrEmpty(s.Checkpoint) && !string.IsNullOrEmpty(s.Path)).ToList();
            if (edits.Count == 0) return null;
            var col = V.VLead(8); col.Align = Cross.Stretch;
            var msg = m;
            foreach (var g in edits.GroupBy(s => s.Path.ToLowerInvariant()))
            {
                var list = g.ToList();
                var first = list[0]; var last = list[list.Count - 1];
                string path = first.Path;
                string before = first.Existed ? (AgentRunner.ReadSnapshot(first.Checkpoint) ?? "") : "";
                string after = AgentRunner.ReadSnapshot(last.After);
                if (after == null) { try { after = File.Exists(path) ? File.ReadAllText(path) : ""; } catch { after = ""; } }
                bool reverted = list.All(s => s.Reverted);
                string desc = (!first.Existed ? "New file" : list.Count == 1 ? (last.Name == "file_write" ? "Rewritten" : "Edited") : list.Count + " edits") + " · " + AgentRunner.DisplayPath(path);
                var card = DiffViews.Card(path, before, after, desc, reverted, false,
                    () => { if (File.Exists(path)) PreviewDock.OpenFile(path); },
                    () =>
                    {
                        if (_running) return;
                        if (reverted) AgentRunner.ReapplyFile(msg.Steps, path); else AgentRunner.RevertFile(msg.Steps, path);
                        AgentStore.Save(); AgentStore.Notify();
                    });
                col.Children.Add(V.Self(card, Cross.Stretch));
            }
            return col;
        }

        void AddText(Stack col, string text)
        {
            foreach (var b in AgentBlocks.Parse(text).Where(x => x.Kind != "thought"))
            {
                if (b.Kind == "code") col.Children.Add(MarkdownView.IsMathFence((b.Lang ?? "").ToLowerInvariant(), b.Text) ? (UIElement)MathBlock.Create(b.Text, Defaults.Num("agentFontSize", 16)) : CodeBlock(b.Text, b.Lang));
                else if (b.Text.Trim().Length > 0)
                {
                    var md = MarkdownView.Render(b.Text.Trim('\n'), Defaults.Num("agentFontSize", 16));
                    ((Border)md).Padding = new Thickness(0);
                    col.Children.Add(md);
                }
            }
        }

        UIElement ErrorCard(ChatMessage m)
        {
            var t = Theme.Current;
            Color orange = Color.FromRgb(255, 159, 10);
            var text = V.Wrap(V.T(m.Error, 12.5, FontWeights.Normal, t.P(0.92)), TextAlignment.Left);
            var buttons = V.H(8);
            Func<string, string, bool, Action, Btn> btn = (icon, label, primary, a) => V.Button(V.Box(V.H(5, Sym.Icon(icon, 10.5, primary ? (Brush)Brushes.White : t.Primary), V.T(label, 11.5, FontWeights.SemiBold, primary ? (Brush)Brushes.White : t.Primary)), V.P(10, 4.5), primary ? t.Accent : t.P(0.08), 6), a);
            string fix = m.ErrorFix ?? "ai";
            if (fix == "account") buttons.Children.Add(btn("person.badge.key", "Sign in to Dotmini Cloud", true, () => { SettingsWindow.Show(_app, 6); _app.Notify("agentBar"); }));
            else if (fix == "topup") buttons.Children.Add(btn("creditcard", "Top Up Cloud AI Credit", true, () => { SettingsWindow.Show(_app, 6); _app.Notify("agentBar"); }));
            buttons.Children.Add(btn("gearshape", "AI & Agent Settings", fix == "ai", () => { SettingsWindow.Show(_app, 2); _app.Notify("agentBar"); }));
            var session = AgentStore.Active;
            var msg = m;
            buttons.Children.Add(btn("arrow.clockwise", "Retry", false, () => Regenerate(msg)));
            var col = V.VLead(10, V.Self(V.H(8, V.Self(Sym.Icon("exclamationmark.triangle.fill", 13, Theme.B(orange)), Cross.Start), V.Flex(text)), Cross.Stretch), buttons);
            col.Align = Cross.Stretch;
            return V.Self(V.Box(col, V.P(12, 10), Theme.B(Theme.WithAlpha(orange, 0.08)), 9, Theme.B(Theme.WithAlpha(orange, 0.28)), 1), Cross.Stretch);
        }

        /// <summary>approvalActionCard: "Plan Review Required".</summary>
        UIElement PlanReviewCard(ChatMessage m)
        {
            var t = Theme.Current;
            var msg = m;
            Color orange = Color.FromRgb(255, 159, 10);
            var head = V.H(8, Sym.Icon("list.bullet.clipboard", 12, Theme.B(orange), FontWeights.SemiBold), V.T("Plan Review Required", 12.5, FontWeights.SemiBold, t.Primary), V.Sp(),
                V.Box(V.T("Awaiting Review", 10, FontWeights.SemiBold, Theme.B(orange)), V.P(6, 2), Theme.B(Theme.WithAlpha(orange, 0.12)), 4));
            var note = V.Wrap(V.T("The AI agent is paused awaiting authorization before making code modifications.", 11.5, FontWeights.Normal, t.Secondary), TextAlignment.Left);
            var reject = V.Button(V.Box(V.H(4, Sym.Icon("xmark", 9, t.Op(t.SysRed, 0.9), FontWeights.Bold), V.T("Reject", 11, FontWeights.Medium, t.Op(t.SysRed, 0.9))), V.P(10, 5), t.Op(t.SysRed, 0.08), 6, t.Op(t.SysRed, 0.2), 0.5), () => RejectPlan(msg));
            var approve = V.Button(V.Box(V.H(6, Sym.Icon("checkmark", 9, Brushes.White, FontWeights.Bold), V.T("Approve Plan & Proceed", 11, FontWeights.SemiBold, Brushes.White), V.T("Ctrl+↵", 10, FontWeights.Medium, Theme.B(Theme.WithAlpha(Colors.White, 0.7)))), V.P(12, 5), t.Accent, 6), () => ApprovePlan(msg));
            var col = V.VLead(8, V.Self(head, Cross.Stretch), note, V.Self(V.H(8, reject, V.Sp(), approve), Cross.Stretch));
            col.Align = Cross.Stretch;
            var card = V.Box(col, V.P(12, 10), t.P(0.035), 10, Theme.B(Theme.WithAlpha(orange, 0.3)), 1);
            card.Focusable = true;
            card.PreviewKeyDown += (s, e) => { if (e.Key == Key.Enter && (Keyboard.Modifiers & ModifierKeys.Control) != 0) { ApprovePlan(msg); e.Handled = true; } };
            return V.Self(card, Cross.Stretch);
        }

        /// <summary>Reject: keep plan mode on so the next message revises the plan.</summary>
        public void RejectPlan(ChatMessage msg)
        {
            msg.PlanState = "rejected";
            AgentStore.Save();
            _planRevision = true;
            if (!AgentStore.Bar.PlanMode) AgentStore.TogglePlan(); else AgentStore.Notify();
            UpdatePlaceholder();
            _input.Focus();
        }

        public void ApprovePlan(ChatMessage msg)
        {
            if (_running) return;
            msg.PlanState = "approved";
            AgentStore.Bar.PlanMode = false;
            if (Defaults.Str("agentPersona", "main") == "planner") Defaults.Set("agentPersona", "main");
            AgentStore.Save();
            AgentStore.Notify();
            Start("Approved. Execute the implementation plan above step by step, then verify the result with the build/tests.", new List<string>(), false);
        }

        UIElement PlanStatus(string state)
        {
            var t = Theme.Current;
            bool ok = state == "approved";
            return V.H(6, Sym.Icon(ok ? "checkmark.seal.fill" : "xmark.circle", 11, ok ? t.SysGreen : t.SysRed), V.T(ok ? "Plan approved — executing" : "Plan rejected — waiting for your changes", 11.5, FontWeights.Medium, t.Secondary));
        }

        public static UIElement ThoughtView(string text, double seconds)
        {
            var t = Theme.Current;
            var body = V.Wrap(V.T(text.Trim(), 13, FontWeights.Normal, t.S(0.85)), TextAlignment.Left);
            var bodyBox = V.Box(body, V.P(12, 2, 0, 2), null, 0, t.P(0.15), 0);
            bodyBox.BorderThickness = new Thickness(2, 0, 0, 0);
            bodyBox.Visibility = Visibility.Collapsed;
            var chev = Sym.Icon("chevron.right", 8.5, t.S(0.6), FontWeights.SemiBold);
            var head = V.Button(V.H(5, V.T("Thought for " + Math.Max(1, (int)Math.Round(seconds)) + "s", 12.5, FontWeights.Normal, t.S(0.78)), chev), null);
            head.Click += delegate { bool open = bodyBox.Visibility != Visibility.Visible; bodyBox.Visibility = open ? Visibility.Visible : Visibility.Collapsed; chev.Glyph.Text = Sym.GlyphText(open ? "chevron.down" : "chevron.right"); };
            return V.VLead(6, head, V.Self(bodyBox, Cross.Stretch));
        }

        /// <summary>ToolResultRow list: "Analyzed main.py #L1-80", "Edited app.py +12 −3", "Ran pytest -q"; click to expand the output.</summary>
        public UIElement StepsView(List<ToolStep> steps)
        {
            var col = V.VLead(2); col.Align = Cross.Stretch;
            foreach (var s in steps) col.Children.Add(StepRow(s));
            return col;
        }

        public UIElement StepRow(ToolStep step)
        {
            var t = Theme.Current;
            var box = V.VLead(4); box.Align = Cross.Stretch;
            var result = new TextBox { Text = step.Result ?? "", IsReadOnly = true, FontFamily = UIFonts.Mono, FontSize = 11.5, Foreground = t.S(0.9), Background = Brushes.Transparent, BorderThickness = new Thickness(0), TextWrapping = TextWrapping.Wrap, MaxHeight = 260, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, CaretBrush = Brushes.Transparent };
            var resultBox = V.Box(result, V.P(10, 6), t.P(0.035), 6);
            resultBox.Visibility = Visibility.Collapsed;
            resultBox.Margin = new Thickness(0, 2, 0, 4);
            var chev = Sym.Icon("chevron.right", 8.5, t.S(0.55), FontWeights.SemiBold);
            bool isEdit = AgentRunner.IsFileEdit(step.Name) && step.Ok && !string.IsNullOrEmpty(step.Checkpoint);
            Func<string> before = () => step.Existed ? (AgentRunner.ReadSnapshot(step.Checkpoint) ?? "") : "";
            Func<string> after = () => AgentRunner.ReadSnapshot(step.After) ?? "";
            bool diffBuilt = false;
            Action toggle = () =>
            {
                if (isEdit && !diffBuilt)
                {
                    // inline diff for this edit ("Show inline diff")
                    diffBuilt = true;
                    resultBox.Child = DiffViews.Section(Differ.Compute(before(), after(), 3));
                    resultBox.Padding = new Thickness(0); resultBox.ClipToBounds = true;
                    resultBox.BorderBrush = t.P(0.08); resultBox.BorderThickness = new Thickness(1);
                }
                bool open = resultBox.Visibility != Visibility.Visible;
                resultBox.Visibility = open ? Visibility.Visible : Visibility.Collapsed;
                chev.Glyph.Text = Sym.GlyphText(open ? "chevron.down" : "chevron.right");
            };
            Brush verbBrush = t.S(0.82);
            var line = V.H(6);
            string fname = AgentRunner.FileName(step);
            Func<UIElement> pill = () =>
            {
                var p = V.Button(V.Box(V.H(5, Sym.Icon(FileTreeView.IconName(fname, false), 11, FileTreeView.IconColor(fname, false)), V.T(fname, 12.5, FontWeights.Medium, t.P(0.95))), V.P(6, 2), t.P(0.035), 5), () =>
                {
                    string full = step.Path != null && Path.IsPathRooted(step.Path) ? step.Path : (_app.WorkspaceFolder != null ? Path.Combine(_app.WorkspaceFolder, (step.Path ?? "").Split('#')[0].Replace('/', '\\')) : null);
                    var rm = Regex.Match(step.Target ?? "", @"#L(\d+)(?:-L?(\d+))?$");
                    int from = rm.Success ? int.Parse(rm.Groups[1].Value) : 0;
                    int to = rm.Success && rm.Groups[2].Success ? int.Parse(rm.Groups[2].Value) : from;
                    if (full != null && File.Exists(full)) PreviewDock.OpenFile(full, from, to); else toggle();
                });
                p.OnState = b => ((Border)b.Child).Background = b.IsHover ? t.P(0.09) : t.P(0.035);
                p.ToolTip = "Click to preview " + fname + " in the side pane";
                return p;
            };
            switch (step.Name)
            {
                case "file_read":
                {
                    line.Children.Add(V.T("Analyzed", 12.5, FontWeights.Normal, verbBrush));
                    line.Children.Add(pill());
                    var lm = Regex.Match(step.Target ?? "", @"#L\d+-\d+$");
                    string range = lm.Success ? lm.Value : step.Lines > 1 ? "#L1-" + Math.Min(350, step.Lines) : null;
                    if (range != null) line.Children.Add(V.Mono(range, 11, FontWeights.Normal, t.S(0.6)));
                    break;
                }
                case "file_write": case "replace_in_file": case "multi_replace_in_file": case "patch_file": case "apply_patch":
                {
                    if (!step.Ok)
                    {
                        // blocked (plan mode, Scope Lock, rejected) or failed: nothing was written
                        line.Children.Add(V.T("Edit", 12.5, FontWeights.Normal, verbBrush));
                        line.Children.Add(pill());
                        string why = (step.Result ?? "").Contains("denied") ? "Rejected" : (step.Result ?? "").Contains("read-only") ? "Blocked by Plan mode" : (step.Result ?? "").Contains("Scope") ? "Blocked by Scope Lock" : "Not applied";
                        line.Children.Add(V.T("· " + why, 12.5, FontWeights.Normal, t.S(0.75)));
                        break;
                    }
                    line.Children.Add(V.T("Edited", 12.5, FontWeights.Normal, verbBrush));
                    line.Children.Add(pill());
                    var diff = V.H(4);
                    if (step.Added > 0 || step.Removed == 0) diff.Children.Add(V.Mono("+" + step.Added, 11.5, FontWeights.SemiBold, Theme.B(Color.FromRgb(64, 199, 97))));
                    if (step.Removed > 0) diff.Children.Add(V.Mono("-" + step.Removed, 11.5, FontWeights.SemiBold, Theme.B(Color.FromRgb(245, 84, 79))));
                    var badge = V.Button(V.Box(diff, V.P(5, 2), t.P(0.04), 4), () => { if (isEdit) PreviewDock.OpenDiff(fname, before(), after()); else toggle(); });
                    badge.ToolTip = "Click to inspect the diff for " + fname;
                    badge.OnState = b => ((Border)b.Child).Background = b.IsHover ? t.P(0.09) : t.P(0.04);
                    line.Children.Add(badge);
                    if (step.Reverted) line.Children.Add(V.T("· Reverted", 12.5, FontWeights.Normal, t.S(0.7)));
                    break;
                }
                case "shell":
                {
                    string c = (step.Target ?? "").Trim(); int nl = c.IndexOf('\n'); if (nl >= 0) c = c.Substring(0, nl);
                    var tb = V.T("Ran " + (c.Length > 68 ? c.Substring(0, 68) : c), 12.5, FontWeights.Normal, verbBrush); tb.TextTrimming = TextTrimming.CharacterEllipsis;
                    line.Children.Add(V.Shrink(tb));
                    if (!step.Ok)
                    {
                        string r = step.Result ?? "";
                        var em = Regex.Match(r, @"exit code (\d+)");
                        string why = r.Contains("read-only") ? "Blocked by Plan mode" : r.Contains("denied") ? "Rejected" : r.Contains("timed out") ? "Timed out" : em.Success ? "Exited with code " + em.Groups[1].Value : "Failed";
                        line.Children.Add(V.T("· " + why, 12.5, FontWeights.Normal, t.S(0.75)));
                    }
                    break;
                }
                default:
                {
                    string head = AgentRunner.Headline(step);
                    var tb = V.T(head, 12.5, FontWeights.Normal, verbBrush); tb.TextTrimming = TextTrimming.CharacterEllipsis;
                    line.Children.Add(V.Shrink(tb));
                    break;
                }
            }
            if (!step.Ok && step.Name != "shell") line.Children.Add(Sym.Icon("xmark", 9, t.SysRed, FontWeights.Bold));
            var expand = V.Button(V.Size(new Grid { Children = { chev } }, 16, 16), toggle);
            expand.ToolTip = "Show output";
            line.Children.Add(expand);
            var headBtn = V.Button(V.Box(line, V.P(2, 2), Brushes.Transparent, 5), null);
            headBtn.Click += toggle;
            box.Children.Add(headBtn);
            box.Children.Add(resultBox);
            return box;
        }

        /// <summary>NativeCodeBlockView: header (language badge, line count, Editor / Copy), code on the editor canvas.</summary>
        static UIElement CodeBlock(string code, string lang) { return MarkdownView.CodeCard(code, lang, 13); }

        /// <summary>The in-flight assistant turn: streamed text segments and tool rows in order, thinking, activity line (liveTaskActivityBanner).</summary>
        class LiveTurn
        {
            readonly AgentView _v;
            public readonly Border Row;
            readonly Stack _items;
            readonly ThreeDots _dots = new ThreeDots();
            readonly TextBlock _activity;
            readonly TextBlock _thinkHead, _thinkBody;
            readonly Border _thinkBox;
            readonly Stack _thinkWrap;
            readonly DispatcherTimer _timer;
            readonly DateTime _started = DateTime.Now;
            readonly object _lock = new object();
            readonly List<object> _model = new List<object>(); // StringBuilder | ToolStep
            readonly StringBuilder _thinking = new StringBuilder();
            readonly Dictionary<object, UIElement> _shown = new Dictionary<object, UIElement>();
            readonly HashSet<ToolStep> _done = new HashSet<ToolStep>();
            readonly Dictionary<StringBuilder, int> _rendered = new Dictionary<StringBuilder, int>();
            string _activityText = "Thinking…";
            bool _dirty = true;
            DateTime? _thinkEnded;
            DateTime _lastTick = DateTime.Now;

            public LiveTurn(AgentView v)
            {
                _v = v;
                var t = Theme.Current;
                _items = V.VLead(10); _items.Align = Cross.Stretch;
                _thinkHead = V.T("Thinking…", 12.5, FontWeights.Normal, t.S(0.78));
                _thinkBody = V.Wrap(V.T("", 13, FontWeights.Normal, t.S(0.85)), TextAlignment.Left);
                _thinkBox = V.Box(_thinkBody, V.P(12, 2, 0, 2), null, 0, t.P(0.15), 0);
                _thinkBox.BorderThickness = new Thickness(2, 0, 0, 0);
                _thinkBox.Visibility = Visibility.Collapsed;
                _thinkBox.MaxHeight = 220;
                var chev = Sym.Icon("chevron.right", 8.5, t.S(0.6), FontWeights.SemiBold);
                var head = V.Button(V.H(5, _thinkHead, chev), null);
                head.Click += delegate { bool open = _thinkBox.Visibility != Visibility.Visible; _thinkBox.Visibility = open ? Visibility.Visible : Visibility.Collapsed; chev.Glyph.Text = Sym.GlyphText(open ? "chevron.down" : "chevron.right"); };
                _thinkWrap = V.VLead(6, head, V.Self(_thinkBox, Cross.Stretch));
                _thinkWrap.Visibility = Visibility.Collapsed;
                _activity = V.T(_activityText, 12, FontWeights.Medium, t.Secondary);
                _activity.TextTrimming = TextTrimming.CharacterEllipsis;
                var col = V.VLead(10, V.Self(_thinkWrap, Cross.Stretch), V.Self(_items, Cross.Stretch), V.H(8, _dots, V.Shrink(_activity)));
                col.Align = Cross.Stretch;
                Row = new Border { Child = col, MaxWidth = 880, Margin = new Thickness(12, 8, 12, 8) };
                _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(50) };
                _timer.Tick += delegate
                {
                    // keep the "Thinking… Ns" counter moving while the model reasons
                    lock (_lock) if (_thinking.Length > 0 && _thinkEnded == null && (DateTime.Now - _lastTick).TotalSeconds >= 1) { _dirty = true; _lastTick = DateTime.Now; }
                    Flush();
                };
                _timer.Start();
            }

            // background-thread callbacks
            public void AddText(string d)
            {
                lock (_lock)
                {
                    var last = _model.Count > 0 ? _model[_model.Count - 1] as StringBuilder : null;
                    if (last == null) { last = new StringBuilder(); _model.Add(last); }
                    last.Append(d);
                    _dirty = true;
                }
            }
            public void AddThinking(string d) { lock (_lock) { _thinking.Append(d); _dirty = true; } }
            public void SetActivity(string a) { lock (_lock) { _activityText = a; _dirty = true; } }
            public void StepStarted(ToolStep s) { lock (_lock) { if (!_model.Contains(s)) _model.Add(s); _dirty = true; } }
            public void StepDone(ToolStep s) { lock (_lock) { if (!_model.Contains(s)) _model.Add(s); _dirty = true; } }

            public string AllText() { lock (_lock) return string.Join("\n\n", _model.OfType<StringBuilder>().Select(b => b.ToString().Trim()).Where(x => x.Length > 0)); }
            public List<ToolStep> Steps()
            {
                lock (_lock)
                {
                    var list = new List<ToolStep>(); int at = 0;
                    foreach (var o in _model)
                    {
                        var sb = o as StringBuilder;
                        if (sb != null) { string tx = sb.ToString().Trim(); if (tx.Length > 0) at += (at > 0 ? 2 : 0) + tx.Length; }
                        else { var st = (ToolStep)o; if (st.Result != null) { st.At = at; list.Add(st); } }
                    }
                    return list;
                }
            }
            public string Thinking() { lock (_lock) return _thinking.ToString(); }

            public void Stop() { _timer.Stop(); _dots.Stop(); Flush(); }

            void Flush()
            {
                List<object> snapshot; string think, activity;
                lock (_lock)
                {
                    if (!_dirty) return;
                    _dirty = false;
                    snapshot = _model.ToList();
                    think = _thinking.ToString();
                    activity = _activityText;
                }
                var t = Theme.Current;
                _activity.Text = activity;
                if (think.Length > 0)
                {
                    _thinkWrap.Visibility = Visibility.Visible;
                    if (_thinkEnded == null && snapshot.Count > 0) _thinkEnded = DateTime.Now; // the answer started
                    int secs = (int)Math.Round(((_thinkEnded ?? DateTime.Now) - _started).TotalSeconds);
                    _thinkHead.Text = _thinkEnded != null ? "Thought for " + Math.Max(1, secs) + "s" : "Thinking… " + secs + "s";
                    _thinkBody.Text = think.Length > 6000 ? "…" + think.Substring(think.Length - 6000) : think;
                }
                for (int i = 0; i < snapshot.Count; i++)
                {
                    var o = snapshot[i];
                    var sb = o as StringBuilder;
                    if (sb != null)
                    {
                        string text; lock (_lock) text = sb.ToString();
                        bool closed = i < snapshot.Count - 1; // a tool ran after this segment
                        UIElement el;
                        int len;
                        if (_shown.TryGetValue(sb, out el) && _rendered.TryGetValue(sb, out len) && len == text.Length && !(closed && el is TextBlock)) continue;
                        string clean = Regex.Replace(AgentBlocks.StripThoughts(text), @"<tool_call>[\s\S]*?(</tool_call>|$)", "").Trim();
                        UIElement fresh;
                        if (closed)
                        {
                            var host = V.VLead(12); host.Align = Cross.Stretch;
                            _v.AddText(host, clean);
                            fresh = host;
                        }
                        else fresh = V.Wrap(V.T(clean, Defaults.Num("agentFontSize", 16), FontWeights.Normal, t.Primary), TextAlignment.Left);
                        if (el != null && el is TextBlock && fresh is TextBlock) ((TextBlock)el).Text = ((TextBlock)fresh).Text;
                        else Replace(el, fresh, sb);
                        _rendered[sb] = text.Length;
                        if (clean.Length > 0) _dots.Visibility = Visibility.Visible;
                    }
                    else
                    {
                        var st = (ToolStep)o;
                        bool finished = st.Result != null;
                        UIElement el;
                        if (_shown.TryGetValue(st, out el) && (!finished || _done.Contains(st))) continue;
                        UIElement fresh;
                        if (finished) { fresh = _v.StepRow(st); _done.Add(st); }
                        else fresh = V.H(7, new ThreeDots { Height = 10 }, V.T(AgentRunner.Headline(st) + "…", 12.5, FontWeights.Normal, t.S(0.82)));
                        Replace(el, fresh, st);
                    }
                }
                _v._scroll.ScrollToEnd();
            }

            void Replace(UIElement old, UIElement fresh, object key)
            {
                if (old != null)
                {
                    int idx = _items.Children.IndexOf(old);
                    if (idx >= 0) { _items.Children.RemoveAt(idx); _items.Children.Insert(idx, fresh); }
                    else _items.Children.Add(fresh);
                }
                else _items.Children.Add(fresh);
                _shown[key] = fresh;
            }
        }
    }

    /// <summary>MessageContentParser: splits a reply into thought, fenced code and markdown text blocks.</summary>
    public static class AgentBlocks
    {
        public class Block { public string Kind, Text, Lang; }

        public static string StripThoughts(string s)
        {
            return Regex.Replace(s ?? "", @"<(think|thought|thinking)>[\s\S]*?(</\1>|$)", "").Trim();
        }

        public static List<Block> Parse(string s)
        {
            var list = new List<Block>();
            s = s ?? "";
            var tm = Regex.Matches(s, @"<(think|thought|thinking)>([\s\S]*?)(</\1>|$)");
            foreach (Match m in tm) list.Add(new Block { Kind = "thought", Text = m.Groups[2].Value });
            s = StripThoughts(s);
            var lines = s.Replace("\r\n", "\n").Split('\n');
            var text = new StringBuilder();
            for (int i = 0; i < lines.Length; i++)
            {
                string tl = lines[i].TrimStart();
                if (tl.StartsWith("```"))
                {
                    if (text.Length > 0) { list.Add(new Block { Kind = "text", Text = text.ToString() }); text.Clear(); }
                    string lang = tl.Substring(3).Trim();
                    var code = new StringBuilder();
                    i++;
                    while (i < lines.Length && !lines[i].TrimStart().StartsWith("```")) { code.Append(lines[i]).Append('\n'); i++; }
                    list.Add(new Block { Kind = "code", Lang = lang, Text = code.ToString().TrimEnd('\n') });
                    continue;
                }
                text.Append(lines[i]).Append('\n');
            }
            if (text.ToString().Trim().Length > 0) list.Add(new Block { Kind = "text", Text = text.ToString() });
            return list;
        }
    }

    /// <summary>AIStreamingThreeDotsView: three accent dots in a travelling sine wave.</summary>
    public class ThreeDots : StackPanel
    {
        readonly System.Windows.Shapes.Ellipse[] _d = new System.Windows.Shapes.Ellipse[3];
        readonly DispatcherTimer _timer;
        public ThreeDots()
        {
            Orientation = Orientation.Horizontal;
            Height = 12;
            var t = Theme.Current;
            for (int i = 0; i < 3; i++)
            {
                _d[i] = new System.Windows.Shapes.Ellipse { Width = 6, Height = 6, Fill = t.Accent, Margin = new Thickness(i == 0 ? 0 : 5, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center, RenderTransformOrigin = new Point(0.5, 0.5) };
                Children.Add(_d[i]);
            }
            var start = DateTime.Now;
            _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(33) };
            _timer.Tick += delegate
            {
                double tt = (DateTime.Now - start).TotalSeconds;
                for (int i = 0; i < 3; i++)
                {
                    double phase = tt * 4.6 - i * 0.72;
                    double wave = (Math.Sin(phase) + 1) * 0.5;
                    double sc = 0.72 + 0.36 * wave;
                    _d[i].Opacity = 0.25 + 0.75 * wave;
                    var tg = new TransformGroup();
                    tg.Children.Add(new ScaleTransform(sc, sc));
                    tg.Children.Add(new TranslateTransform(0, -2.2 * Math.Max(0, Math.Sin(phase))));
                    _d[i].RenderTransform = tg;
                }
            };
            _timer.Start();
            Unloaded += delegate { _timer.Stop(); };
        }
        public void Stop() { _timer.Stop(); }
    }
}
