// PNS 24/7 console — port of Views/AI/PNSNeuralDashboardView.swift: daemon header (pnsd state, Boot / Stop, autonomic mode,
// sign-in keep-alive, REM Consolidate), vital metrics, the marathon mission launcher and ledger, the nerve-tract topology, the
// Hebbian synapse table and the spike feed. Windows additions: approvals for fiber commands and live fiber activity.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public class PnsView : Border
    {
        readonly AppState _app;
        readonly PnsOrchestrator _pns;
        readonly Border _header = new Border(), _banner = new Border(), _metrics = new Border(), _approvals = new Border(), _missions = new Border(), _plexus = new Border(), _synapses = new Border();
        readonly Border _launcher;
        readonly TextBox _objective, _verify;
        readonly Border _policyHost = new Border(), _launchHost = new Border();
        readonly TextBlock _workspaceLabel;
        string _policy = Pns.PolicyIsolated, _bannerText;
        bool _dispatching, _queued;

        public PnsView(AppState app, PnsOrchestrator pns)
        {
            _app = app;
            _pns = pns;
            var t = Theme.Current;
            Background = t.WorkspaceBackground;
            // marathonLauncherCard is built once so typing survives the live refreshes
            var objectiveBox = AgentUI.Field("Describe long-horizon 24/7 engineering mission (e.g. Audit modules, fix failing tests, add unit coverage across isolated worktrees)...", 11.5, false, false, out _objective);
            var verifyBox = AgentUI.Field("Optional Verify Cmd (e.g. npm test / dotnet test / cargo check)", 11, true, false, out _verify);
            _objective.TextChanged += delegate { RenderLaunch(); };
            _objective.KeyDown += (s, e) => { if (e.Key == Key.Enter) { e.Handled = true; Launch(); } };
            _workspaceLabel = V.Mono("", 10, FontWeights.Normal, t.Secondary);
            var top = V.H(8, Sym.Icon("flag", 12, t.Primary), V.T("Dispatch 24/7 Autonomous Marathon Mission", 12.5, FontWeights.SemiBold, t.Primary), V.Sp(), V.Shrink(_workspaceLabel));
            var bottom = V.H(10, _policyHost, V.Flex(verifyBox), _launchHost);
            var card = V.VLead(10, V.Self(top, Cross.Stretch), V.Self(objectiveBox, Cross.Stretch), V.Self(bottom, Cross.Stretch));
            card.Align = Cross.Stretch;
            _launcher = V.Box(card, V.P(13), t.P(0.03), 9);

            var col = V.VLead(16, V.Self(_header, Cross.Stretch), V.Self(_banner, Cross.Stretch), V.Self(_metrics, Cross.Stretch), V.Self(_launcher, Cross.Stretch),
                V.Self(_approvals, Cross.Stretch), V.Self(_missions, Cross.Stretch), V.Self(_plexus, Cross.Stretch), V.Self(_synapses, Cross.Stretch));
            col.Align = Cross.Stretch;
            Child = new ScrollViewer { Content = new Border { Child = col, Padding = new Thickness(18) }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
            Loaded += delegate
            {
                _pns.Changed -= Queue; _pns.Changed += Queue;
                IsolatedApprovals.Changed -= Queue; IsolatedApprovals.Changed += Queue;
                _pns.ViewAttached = true;
                _pns.UpdateHomeostasis();
                var poll = _pns.PollDaemonOnce();
                Render();
            };
            Unloaded += delegate { _pns.Changed -= Queue; IsolatedApprovals.Changed -= Queue; _pns.ViewAttached = false; };
            Render();
        }

        void Queue()
        {
            if (_queued) return;
            _queued = true;
            Dispatcher.BeginInvoke(new Action(() => { _queued = false; Render(); }), DispatcherPriority.Background);
        }

        string Workspace { get { return _app.WorkspaceFolder; } }

        void Banner(string text) { _bannerText = text; Render(); }

        /// <summary>Runs an async UI action; a failure becomes the status banner instead of an unhandled exception.</summary>
        void Do(Func<Task> work)
        {
            work().ContinueWith(t => { if (t.IsFaulted) Banner("PNS error: " + t.Exception.GetBaseException().Message); }, TaskScheduler.FromCurrentSynchronizationContext());
        }

        public void Render()
        {
            var snap = _pns.Status();
            RenderHeader(snap);
            RenderBanner();
            RenderMetrics(snap);
            RenderLaunch();
            var ap = AgentUI.ApprovalCards("pns");
            _approvals.Child = ap == null ? null : V.VLead(8, V.T("Fiber commands waiting for your approval", 12, FontWeights.SemiBold, Theme.Current.Secondary), ap);
            _approvals.Visibility = ap == null ? Visibility.Collapsed : Visibility.Visible;
            RenderMissions(snap);
            RenderPlexus(snap);
            RenderSynapses(snap);
        }

        // ── 1. header & daemon controls ──
        void RenderHeader(PnsStatusSnapshot snap)
        {
            var t = Theme.Current;
            bool online = snap.IsOutOfProcessDaemon;
            var c = online ? t.SysGreen : t.SysOrange;
            var pill = V.Box(V.H(5, V.Dot(7, c), V.Mono(online ? "pnsd 24/7 ONLINE (PID " + snap.DaemonPID + " • Survives App Quit)" : "In-Process Standby", 10, FontWeights.SemiBold, t.Primary)), V.P(8, 3), t.Op(c, 0.14), 99);
            var titles = V.VLead(2, V.H(8, V.T("PNS — Pseudo Neural System", 15, FontWeights.Bold, t.Primary), pill),
                V.T("Biomimetic 24/7 Nerve-Tract Orchestrator for Massive MCP_1..xx & Isolated Git-Worktree Agent_1..n Swarms", 11, FontWeights.Normal, t.Secondary));
            Btn daemonBtn;
            if (online)
                daemonBtn = AgentUI.Pill("stop.circle.fill", "Stop pnsd", t.SysRed, t.Op(t.SysRed, 0.12), 10.5, FontWeights.Medium, () => Do(async () =>
                {
                    await _pns.StopDaemon();
                    Banner("Stopped out-of-process microcode-pnsd daemon.");
                }));
            else
                daemonBtn = AgentUI.Pill("power", "Boot 24/7 pnsd", t.Accent, t.A(0.18), 10.5, FontWeights.SemiBold, () => Do(async () =>
                {
                    Banner("Booting microcode-pnsd…");
                    bool ok = await _pns.EnsureDaemonRunning();
                    Banner(ok ? "Booted detached 24/7 microcode-pnsd daemon (PID " + _pns.RemotePid + "). Safe to close MicroCode." : "Could not start or reach the out-of-process daemon on 127.0.0.1.");
                }));
            daemonBtn.ToolTip = online ? "Stop the background daemon (running missions pause)" : "Start MicroCode.exe --pns-daemon in the background so missions keep running after the app is closed";
            var row1 = V.H(10, Sym.Icon("point.3.connected.trianglepath.dotted", 18, t.Accent, FontWeights.SemiBold), V.Shrink(titles), V.Sp(), daemonBtn);

            string mode = snap.AutonomicMode ?? Pns.AutoHomeostasis;
            var modeBtn = V.Button(V.Box(V.H(5, Sym.Icon(Pns.ModeIcon(mode), 10, t.Secondary), V.T(Pns.ModeName(mode), 11, FontWeights.Normal, t.Primary), Sym.Icon("chevron.up.chevron.down", 8, t.Secondary)), V.P(8, 4), t.P(0.06), 5), null);
            modeBtn.MaxWidth = 260;
            modeBtn.ToolTip = "Autonomic Mode";
            modeBtn.MenuItems = () => Pns.Modes.Select(m => new MenuItemSpec { Title = Pns.ModeName(m), Icon = Pns.ModeIcon(m), Checked = m == mode, Action = () => Do(() => _pns.SetModeAsync(m)) }).ToList();
            bool isolatedData = TaskFiles.HomeOverride != null;
            bool installed = false;
            if (!isolatedData) { try { installed = PnsKeepAlive.IsInstalled; } catch (System.Security.SecurityException) { installed = false; } }
            var keep = V.H(5, AgentUI.Switch(installed, !isolatedData, on =>
            {
                try
                {
                    PnsKeepAlive.SetEnabled(on);
                    if (on) Do(async () => { await _pns.EnsureDaemonRunning(); Banner("pnsd now starts when you sign in to Windows (HKCU\\…\\Run → \"MicroCode PNS\")."); });
                    else Banner("Removed the sign-in start of pnsd.");
                }
                catch (UnauthorizedAccessException ex) { Banner("Could not change the sign-in start: " + ex.Message); }
                catch (System.Security.SecurityException ex) { Banner("Could not change the sign-in start: " + ex.Message); }
            }), V.T("Start pnsd at sign-in (24/7 Keep-Alive)", 10.5, FontWeights.Medium, t.Primary));
            keep.ToolTip = isolatedData ? "Not available with an isolated --data-dir" : "Windows counterpart of the macOS launchd KeepAlive agent";
            var rem = AgentUI.Pill("brain.head.profile", "REM Consolidate", t.Primary, t.P(0.06), 10.5, FontWeights.Medium, () => Do(async () => Banner(await _pns.ConsolidateAsync(Workspace))));
            rem.ToolTip = "Distill episodic logs into Procedural Playbooks & prune Context Rot";
            var row2 = V.H(8, modeBtn, keep, V.Sp(), rem);
            var col = V.VLead(10, V.Self(row1, Cross.Stretch), V.Self(row2, Cross.Stretch));
            col.Align = Cross.Stretch;
            _header.Child = V.Box(col, V.P(14), t.P(0.035), 10);
        }

        void RenderBanner()
        {
            var t = Theme.Current;
            if (string.IsNullOrEmpty(_bannerText)) { _banner.Child = null; _banner.Visibility = Visibility.Collapsed; return; }
            var dismiss = V.Button(V.T("Dismiss", 10, FontWeights.Normal, t.Secondary), () => { _bannerText = null; Render(); });
            _banner.Child = V.Box(V.H(8, V.Self(Sym.Icon("bolt.fill", 12, t.Accent), Cross.Start), V.Flex(V.Wrap(V.T(_bannerText, 11, FontWeights.Medium, t.Primary), TextAlignment.Left)), V.Self(dismiss, Cross.Start)), V.P(12, 8), t.A(0.10), 7);
            _banner.Visibility = Visibility.Visible;
        }

        // ── 2. vital homeostasis metrics ──
        static UIElement Tile(string title, string value, string subtitle, string icon, SolidColorBrush tint)
        {
            var t = Theme.Current;
            var sub = V.T(subtitle, 9.5, FontWeights.Normal, t.Secondary);
            sub.ToolTip = subtitle;
            var col = V.VLead(5, V.H(5, Sym.Icon(icon, 11, tint), V.Shrink(V.T(title, 10, FontWeights.Medium, t.Secondary))), V.Mono(value, 15, FontWeights.Bold, t.Primary), sub);
            return V.Box(col, V.P(11), t.P(0.03), 8);
        }

        void RenderMetrics(PnsStatusSnapshot s)
        {
            var t = Theme.Current;
            var g = new Grid();
            for (int i = 0; i < 4; i++) g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var tiles = new[]
            {
                Tile("Metabolic Index (M_t)", (s.MetabolicBudgetIndex * 100).ToString("0", CultureInfo.InvariantCulture) + "%", (s.EffectiveMode ?? "") + " • Power: " + s.ThermalStateLabel, Pns.ModeIcon(s.EffectiveMode), s.MetabolicBudgetIndex > 0.6 ? t.SysGreen : t.SysOrange),
                Tile("MCP Ganglion Filter", s.TotalExternalMCPTools + " → " + s.ActiveMountedSynapticTools, "No MCP client in the Windows build yet", "network", t.SysBlue),
                Tile("Synaptic Plasticity", s.MyelinatedSynapsesCount + " Myelinated", s.ProceduralPlaybooksCount + " Playbooks • " + s.InhibitedSynapsesCount + " Inhibited", "shield", t.SysPurple),
                Tile("Spinal Reflex & REM", s.SpinalReflexSavesCount + " Saves", "<50ms 0-LLM • " + s.RemConsolidationCycles + " REM Cycles", "waveform", t.SysTeal)
            };
            for (int i = 0; i < 4; i++)
            {
                var fe = (FrameworkElement)tiles[i];
                fe.Margin = new Thickness(i == 0 ? 0 : 5, 0, i == 3 ? 0 : 5, 0);
                Grid.SetColumn(fe, i);
                g.Children.Add(fe);
            }
            _metrics.Child = g;
        }

        // ── 3. launcher ──
        void RenderLaunch()
        {
            var t = Theme.Current;
            string ws = Workspace;
            _workspaceLabel.Text = "Workspace: " + (ws != null ? System.IO.Path.GetFileName(ws.TrimEnd('\\')) : "— open a folder");
            var policyBtn = V.Button(V.Box(V.H(5, Sym.Icon("arrow.triangle.branch", 10, t.Secondary), V.T(Pns.PolicyName(_policy), 11, FontWeights.Normal, t.Primary), Sym.Icon("chevron.up.chevron.down", 8, t.Secondary)), V.P(8, 5), t.P(0.06), 5), null);
            policyBtn.MaxWidth = 280;
            policyBtn.ToolTip = "Branch Policy";
            policyBtn.MenuItems = () => new[] { Pns.PolicyIsolated, Pns.PolicyAutoMerge }.Select(p => new MenuItemSpec { Title = Pns.PolicyName(p), Checked = p == _policy, Action = () => { _policy = p; RenderLaunch(); } }).ToList();
            _policyHost.Child = policyBtn;
            bool can = !_dispatching && ws != null && _objective.Text.Trim().Length > 0;
            var launch = V.Button(V.Box(V.H(5, Sym.Icon(_dispatching ? "clock" : "paperplane.fill", 10, can ? Brushes.White : t.Secondary), V.T(_dispatching ? "Dispatching..." : "Launch 24/7", 11, FontWeights.SemiBold, can ? Brushes.White : t.Secondary)), V.P(12, 6), can ? t.Accent : t.S(0.15), 6), Launch);
            launch.ToolTip = ws == null ? "Open a project folder first" : "Plan the mission and run its fibers in isolated worktrees";
            _launchHost.Child = launch;
        }

        void Launch()
        {
            string ws = Workspace, objective = _objective.Text.Trim(), verify = _verify.Text.Trim();
            if (_dispatching || ws == null || objective.Length == 0) return;
            if (!AIConfig.IsConfigured) { Banner(AIClient.NotConnectedText()); return; }
            _dispatching = true;
            RenderLaunch();
            string policy = _policy;
            _pns.DispatchMission(objective, ws, policy, verify.Length == 0 ? null : verify, true).ContinueWith(t =>
            {
                _dispatching = false;
                if (t.IsFaulted) { Banner("Could not dispatch the mission: " + t.Exception.GetBaseException().Message); return; }
                var m = t.Result;
                _objective.Text = "";
                Banner("Dispatched 24/7 mission '" + m.Title + "' (" + m.Id.Substring(0, 8) + ") to PNS" + (_pns.RemoteOnline ? " — running in microcode-pnsd." : " — running in this window (in-process)."));
            }, TaskScheduler.FromCurrentSynchronizationContext());
        }

        // ── 4. marathon missions ledger ──
        static SolidColorBrush StatusColor(string status)
        {
            var t = Theme.Current;
            switch (status)
            {
                case Pns.Completed: return t.SysGreen;
                case Pns.Running: case Pns.ConsolidatingRem: return t.Accent;
                case Pns.Paused: case Pns.PacingHomeostasis: case Pns.Queued: return t.SysOrange;
                default: return t.SysRed;
            }
        }

        static Btn TextButton(string label, SolidColorBrush color, Action a) { return V.Button(V.T(label, 10, FontWeights.Medium, color), a); }

        void RenderMissions(PnsStatusSnapshot s)
        {
            var t = Theme.Current;
            var missions = (s.Missions ?? new List<PnsMarathonMission>()).Take(6).ToList();
            if (missions.Count == 0) { _missions.Child = null; _missions.Visibility = Visibility.Collapsed; return; }
            var col = V.VLead(8, V.T("24/7 Marathon Missions Ledger", 12, FontWeights.SemiBold, t.Secondary));
            col.Align = Cross.Stretch;
            foreach (var mission in missions)
            {
                var m = mission;
                var sc = StatusColor(m.Status);
                var title = V.T(m.Title, 12, FontWeights.SemiBold, t.Primary);
                title.ToolTip = m.Objective + "\n\n" + m.WorkspacePath + " · " + Pns.PolicyName(m.BranchPolicy) + (m.VerificationCommand != null ? " · verify: " + m.VerificationCommand : "");
                var head = V.H(8, V.Box(V.Mono((m.Status ?? "").ToUpperInvariant(), 9, FontWeights.Bold, sc), V.P(6, 2), t.Op(sc, 0.16), 4), V.Shrink(title), V.Sp(),
                    V.Mono((int)(m.Progress * 100) + "% • REM:" + m.RemConsolidationsCount + " • Reflex:" + m.SpinalReflexSavesCount, 10, FontWeights.Normal, t.Secondary));
                if (m.Status == Pns.Running || m.Status == Pns.ConsolidatingRem) head.Children.Add(TextButton("Pause", t.SysOrange, () => Do(() => _pns.ControlMission(m.Id, "pause"))));
                else if (m.Status == Pns.Paused) head.Children.Add(TextButton("Resume", t.SysGreen, () => Do(() => _pns.ControlMission(m.Id, "resume"))));
                if (m.Status == Pns.Running || m.Status == Pns.Paused || m.Status == Pns.Queued) head.Children.Add(TextButton("Cancel", t.SysRed, () => Do(() => _pns.ControlMission(m.Id, "cancel"))));
                var card = V.VLead(8, V.Self(head, Cross.Stretch), V.Self(AgentUI.Progress(m.Progress, t.Accent), Cross.Stretch));
                card.Align = Cross.Stretch;
                if (!string.IsNullOrEmpty(m.LastError) && m.Status != Pns.Completed)
                {
                    var err = V.Wrap(V.T(m.LastError, 10.5, FontWeights.Normal, m.Status == Pns.Paused ? t.SysOrange : t.SysRed), TextAlignment.Left);
                    err.MaxHeight = 44;
                    card.Children.Add(err);
                }
                if (m.Subtasks != null && m.Subtasks.Count > 0)
                {
                    var subs = V.VLead(4);
                    subs.Align = Cross.Stretch;
                    foreach (var subtask in m.Subtasks)
                    {
                        var st = subtask;
                        var stc = StatusColor(st.Status);
                        string icon = st.Status == Pns.Completed ? "checkmark.circle.fill" : st.Status == Pns.Running ? "bolt.fill" : st.Status == Pns.Failed ? "xmark.circle.fill" : "circle";
                        var label = V.T("[" + st.AssignedArchetype + "] " + st.Title + (st.Attempts > 1 ? "  (attempt " + st.Attempts + ")" : ""), 10.5, FontWeights.Medium, t.Primary);
                        label.ToolTip = st.Description + (string.IsNullOrEmpty(st.ResultSummary) ? "" : "\n\n" + st.ResultSummary);
                        var line = V.H(6, Sym.Icon(icon, 10.5, stc), V.Shrink(label), V.Sp());
                        if (!string.IsNullOrEmpty(st.WorktreeBranch))
                        {
                            string branch = st.WorktreeBranch;
                            var chip = V.Button(V.Box(V.Mono(branch, 9.5, FontWeights.Normal, t.Primary), V.P(6, 2), t.A(0.12), 4), () =>
                            {
                                try { Clipboard.SetText(branch); Banner("Copied verified worktree branch '" + branch + "' to clipboard."); }
                                catch (System.Runtime.InteropServices.ExternalException ex) { Banner("Could not copy to the clipboard: " + ex.Message); }
                            });
                            chip.ToolTip = "Copy branch name";
                            line.Children.Add(chip);
                        }
                        subs.Children.Add(V.Self(line, Cross.Stretch));
                        if (st.Status == Pns.Running && !string.IsNullOrEmpty(st.Activity))
                        {
                            var act = V.Mono("↳ " + st.Activity, 9.5, FontWeights.Normal, t.S(0.75));
                            act.Margin = new Thickness(17, 0, 0, 0);
                            subs.Children.Add(act);
                        }
                    }
                    card.Children.Add(subs);
                }
                col.Children.Add(V.Self(V.Box(card, V.P(11), t.P(0.025), 8), Cross.Stretch));
            }
            _missions.Child = col;
            _missions.Visibility = Visibility.Visible;
        }

        // ── 5. nerve-tract topology ──
        static UIElement TractCard(PnsTractTelemetry tr)
        {
            var t = Theme.Current;
            var head = V.H(6, Sym.Icon(Pns.Icon(tr.Tract), 11.5, t.Accent), V.Shrink(V.T(Pns.Title(tr.Tract), 11, FontWeights.SemiBold, t.Primary)), V.Sp(6),
                V.Mono("Active:" + tr.ActiveCount + " • Idle:" + tr.HibernatedCount + " • Myelin:" + tr.MyelinatedEdgesCount, 9.5, FontWeights.Normal, t.Secondary));
            TextBlock body;
            if (tr.AttachedNodes == null || tr.AttachedNodes.Count == 0)
                body = V.T(Pns.IsMcp(tr.Tract) ? "No MCP servers — the Windows build has no MCP client yet" : "No fibers attached yet", 10, FontWeights.Normal, t.S(0.75));
            else
            {
                body = V.Wrap(V.Mono(string.Join("  •  ", tr.AttachedNodes), 10, FontWeights.Normal, t.Secondary), TextAlignment.Left);
                body.MaxHeight = 30;
            }
            var col = V.VLead(5, V.Self(head, Cross.Stretch), body);
            col.Align = Cross.Stretch;
            var box = V.Box(col, V.P(10), t.P(0.03), 7);
            box.ToolTip = tr.TotalImpulses + " impulse(s)";
            return V.Self(box, Cross.Stretch);
        }

        static Grid TwoColumns(UIElement left, UIElement right)
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Grid.SetColumn(right, 2);
            g.Children.Add(left);
            g.Children.Add(right);
            return g;
        }

        static Stack Column(string icon, string title)
        {
            var t = Theme.Current;
            var col = V.VLead(8, V.H(5, Sym.Icon(icon, 11, t.Secondary), V.T(title, 12, FontWeights.SemiBold, t.Secondary)));
            col.Align = Cross.Stretch;
            return col;
        }

        void RenderPlexus(PnsStatusSnapshot s)
        {
            var left = Column("link", "Efferent MCP Nerve Tracts (MCP_1 ... MCP_xx)");
            var right = Column("person.2", "Somatic Motor Agent Tracts (Agent_1 ... Agent_n)");
            foreach (var tr in s.Tracts ?? new List<PnsTractTelemetry>())
            {
                if (Pns.IsMcp(tr.Tract)) left.Children.Add(TractCard(tr));
                else if (Pns.IsMotor(tr.Tract)) right.Children.Add(TractCard(tr));
            }
            left.VerticalAlignment = right.VerticalAlignment = VerticalAlignment.Top;
            _plexus.Child = TwoColumns(left, right);
        }

        // ── 6. synaptic plasticity table & spike feed ──
        void RenderSynapses(PnsStatusSnapshot s)
        {
            var t = Theme.Current;
            var left = Column("bolt.fill", "Hebbian Synaptic Weights & Myelination (W_e)");
            var edges = (s.TopSynapses ?? new List<PnsSynapse>()).OrderByDescending(e => e.Weight).Take(8).ToList();
            if (edges.Count == 0)
            {
                var empty = V.Wrap(V.T("Synaptic weights populate automatically as motor fibers execute and verify tasks.", 10.5, FontWeights.Normal, t.Secondary), TextAlignment.Left);
                empty.Margin = new Thickness(10);
                left.Children.Add(empty);
            }
            foreach (var e in edges)
            {
                var c = e.IsMyelinated ? t.SysPurple : e.IsInhibited ? t.SysRed : t.SysBlue;
                var badge = V.Box(V.Mono(e.IsMyelinated ? "MYELIN" : e.IsInhibited ? "INHIB" : "PLASTIC", 8.5, FontWeights.Bold, c), V.P(5, 2), t.Op(c, 0.15), 4);
                var info = V.VLead(1, V.Mono(e.TargetNodeId, 10.5, FontWeights.Medium, t.Primary), V.T(e.TaskCategory + " • +" + e.SuccessCount + "/-" + e.FailureCount + " • " + e.AvgLatencyMs + "ms", 9.5, FontWeights.Normal, t.Secondary));
                var row = V.H(8, badge, V.Shrink(info), V.Sp(), V.Mono(e.Weight.ToString("0.00", CultureInfo.InvariantCulture), 10.5, FontWeights.Bold, t.Primary));
                left.Children.Add(V.Self(V.Box(row, V.P(8), t.P(0.025), 6), Cross.Stretch));
            }
            var right = Column("waveform", "Thalamic & Autonomic Spike Feed (WAL)");
            var spikes = (s.RecentSpikes ?? new List<PnsSpike>()).AsEnumerable().Reverse().Take(8).ToList();
            if (spikes.Count == 0)
            {
                var empty = V.T("Waiting for sensory or motor action-potential spikes...", 10.5, FontWeights.Normal, t.Secondary);
                empty.Margin = new Thickness(10);
                right.Children.Add(empty);
            }
            foreach (var sp in spikes)
            {
                var head = V.H(6, V.Mono(Pns.Badge(sp.Tract), 9, FontWeights.SemiBold, t.Accent), V.Mono(sp.Kind ?? "", 9, FontWeights.Normal, t.Secondary), V.Sp(),
                    V.Mono("S:" + sp.Salience.ToString("0.00", CultureInfo.InvariantCulture), 9, FontWeights.Normal, t.Secondary));
                var summary = V.Wrap(V.T(sp.Summary, 10.5, FontWeights.Normal, sp.Succeeded ? t.Primary : t.SysRed), TextAlignment.Left);
                summary.MaxHeight = 30;
                summary.ToolTip = sp.Summary;
                var col = V.VLead(2, V.Self(head, Cross.Stretch), summary);
                col.Align = Cross.Stretch;
                right.Children.Add(V.Self(V.Box(col, V.P(8), t.P(0.025), 6), Cross.Stretch));
            }
            left.VerticalAlignment = right.VerticalAlignment = VerticalAlignment.Top;
            _synapses.Child = TwoColumns(left, right);
        }
    }
}
