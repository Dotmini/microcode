// Agent workspace panels ported from AIAgentView.swift: the Implementation Plan side panel (planSidePanelView /
// planStructuredView), the Task editor (taskEditorView: Checklist · Spec · Walkthrough · Logs · Cost · Audit · Consensus · PNS),
// the Walkthrough artifact view, and the per-workspace task.md / agent.md / walkthrough.md files that live under
// ~/.microcode/workspaces/<name>-<hash>/ (WorkspaceStoragePaths.managedStateFile).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    /// <summary>What the panels need from the agent surface that hosts them.</summary>
    public interface IAgentHost
    {
        AppState App { get; }
        bool IsRunning { get; }
        void RunPrompt(string prompt, bool plan);
        void StopRun();
        void ApprovePlan(ChatMessage plan);
        void RejectPlan(ChatMessage plan);
    }

    // ── task.md / agent.md / walkthrough.md ───────────────────────────────────

    public static class TaskFiles
    {
        /// <summary>Set by --snapshot / --data-dir so test runs keep their agent state inside the isolated data folder.</summary>
        public static string HomeOverride;
        public static string Home { get { return HomeOverride ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".microcode"); } }

        /// <summary>workspaceStateDirectory: ~/.microcode/workspaces/&lt;name&gt;-&lt;hash12&gt; — keeps agent state out of the repo.</summary>
        public static string StateDir(string ws)
        {
            string root = Path.Combine(Home, "workspaces");
            if (string.IsNullOrWhiteSpace(ws)) return Path.Combine(root, "_global");
            string canonical = Path.GetFullPath(ws).TrimEnd('\\');
            string name = Regex.Replace(Path.GetFileName(canonical) ?? "", "[^A-Za-z0-9._-]", "_").Trim('.', '_', '-');
            if (name.Length == 0) name = "workspace";
            if (name.Length > 40) name = name.Substring(0, 40);
            using (var sha = SHA256.Create())
            {
                string hex = BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(canonical.ToLowerInvariant()))).Replace("-", "").ToLowerInvariant();
                return Path.Combine(root, name + "-" + hex.Substring(0, 12));
            }
        }

        public static string Managed(string ws, string name) { return Path.Combine(StateDir(ws), name); }

        /// <summary>readableWorkspaceOrStateFile: the managed copy, else a committed &lt;workspace&gt;/.microcode copy, else the managed path.</summary>
        public static string PathFor(string ws, string name)
        {
            string managed = Managed(ws, name);
            if (File.Exists(managed)) return managed;
            if (!string.IsNullOrEmpty(ws)) { string legacy = Path.Combine(ws, ".microcode", name); if (File.Exists(legacy)) return legacy; }
            return managed;
        }

        public static bool Exists(string ws, string name) { return File.Exists(PathFor(ws, name)); }

        public static string Read(string ws, string name)
        {
            try { string p = PathFor(ws, name); return File.Exists(p) ? File.ReadAllText(p) : null; } catch { return null; }
        }

        public static void Write(string ws, string name, string text)
        {
            string p = Managed(ws, name);
            Directory.CreateDirectory(Path.GetDirectoryName(p));
            File.WriteAllText(p, text ?? "", new UTF8Encoding(false));
        }

        public const string DefaultWalkthrough = "# Walkthrough\n\n## Changes\n- Verified implementation\n\n## Verification\n- Tests passing\n\n## Privacy Audit\n- [x] Zero API keys or secrets detected in artifacts\n";

        /// <summary>AgentService.defaultTaskMarkdown</summary>
        public static string DefaultTask(string objective)
        {
            string o = string.IsNullOrWhiteSpace(objective) ? "<!-- Describe the objective here -->" : objective.Trim();
            if (o.Length > 8000) o = o.Substring(0, 8000);
            return "# Workspace Autonomous Task\n<!-- microcode:managed-task -->\n\n## 📋 Task Overview\n- **Objective**: " + o +
                "\n- **Status**: 🟡 IN_PROGRESS  <!-- PENDING | IN_PROGRESS | COMPLETED | FAILED -->\n- **Active Owner**: main\n- **Last Updated**: " + DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture) +
                "\n\n---\n\n## 🎯 Scope Boundaries\n- **In Scope**: Targeted changes requested for this objective.\n- **Out of Scope**: Unrelated refactoring, third-party library additions, modifying secrets.\n\n---\n\n" +
                "## 🚀 Execution Phases & Structured TODOs\n\n### Phase 1: Inspection & Baseline Analysis\n- [ ] **1.1** Inspect workspace files, dependencies, and existing architectural patterns.\n- [ ] **1.2** Check compiler diagnostics, errors, and current git status.\n- [ ] **1.3** Formulate atomic changes and verify preconditions.\n\n" +
                "### Phase 2: Implementation & Code Changes\n- [ ] **2.1** Implement core changes surgically using targeted edit tools.\n- [ ] **2.2** Ensure full backward compatibility and adhere to project code style.\n- [ ] **2.3** Preserve all existing functionality and comments.\n\n" +
                "### Phase 3: Verification & Evidence Capture\n- [ ] **3.1** Run build/compilation tool and ensure zero errors.\n- [ ] **3.2** Run test suite to verify no regressions.\n- [ ] **3.3** Verify live app behavior or inspect UI elements.\n\n" +
                "### Phase 4: Privacy Audit & Completion\n- [ ] **4.1** Verify git diff to ensure no unexpected files were touched.\n- [ ] **4.2** 🔒 **PRIVACY CHECK**: Confirm ZERO API keys, tokens, credentials, or PII are present in `.microcode/` or project files.\n- [ ] **4.3** Mark task as COMPLETED and report verified results.\n\n---\n\n" +
                "## 🛡️ Active Constraints & Safety Guidelines\n1. **Zero Secret Storage**: Never write passwords, keys, or auth headers into this file.\n2. **Autonomous Execution**: Run build and test tools directly; do not offload execution to the user.\n3. **Evidence-Based Completion**: Mark items `[x]` ONLY after tool verification has succeeded.\n\n---\n\n## 📊 Verification Log\n- Baseline check: Pending\n- Build status: Pending\n- Privacy audit: Clean\n";
        }

        /// <summary>AgentService.defaultAgentMarkdown (tool names adapted to the Windows agent).</summary>
        public static string DefaultAgent()
        {
            return "# MicroCode Workspace Agent Directive\n<!-- microcode:managed-agent -->\n\n## 1. Operating Identity & Core Mandate\n- You are the autonomous MicroCode workspace engineer and code orchestrator.\n- You have direct access to native developer tools (`file_read`, `replace_in_file`, `file_write`, `grep_search`, `shell`).\n- Your core duty is delivering reliable, high-stability code changes backed by verified test and build results.\n\n" +
                "## 2. Strict Prohibitions & Hard Constraints (ข้อห้ามเด็ดขาด - DO NOTs)\n- 🚫 **STRICT ZERO-PRIVACY LEAKAGE (ห้ามเก็บข้อมูลส่วนตัว/รหัสลับเด็ดขาด)**:\n  - NEVER write, log, commit, or persist API keys, auth tokens, passwords, private keys, session cookies, database credentials, or Personally Identifiable Information (PII) into `.microcode/agent.md`, `.microcode/task.md`, `.microcode/walkthrough.md`, git history, or any workspace file.\n  - All credentials must be accessed strictly via the OS credential store, `.env` (gitignored), or environment variables.\n  - Always sanitize and redact sensitive values with `[REDACTED_SECRET_FOR_PRIVACY]`.\n" +
                "- 🚫 **NO Destructive / Irreversible Operations**:\n  - Never execute destructive commands without confirmation (`rmdir /s`, `del /s /q`, `format`, `DROP DATABASE`).\n  - Never run `git reset --hard`, `git clean -fd`, or force-push without explicit user request.\n- 🚫 **NO Phantom / Hallucinated Verification**:\n  - Never claim that code compiles, tests pass, or bugs are fixed without real terminal tool execution evidence.\n  - Never ask the user to manually run verification steps when native agent tools are available.\n- 🚫 **NO Half-Finished Placeholder Implementations**:\n  - Never leave unfinished stubs (`// TODO: implement later`, `pass`, `...`) in production logic.\n- 🚫 **NO Scope Creep**:\n  - Do not rewrite unrelated files or introduce unrequested third-party dependencies outside the assigned task scope.\n\n" +
                "## 3. Four-Phase Autonomous Execution Protocol\nEvery non-trivial task must progress through four sequential phases:\n1. **Phase 1: Deep Workspace Inspection & Baseline Diagnostics**\n   - Read relevant source files using native read tools before proposing edits.\n   - Inspect compiler diagnostics, dependencies, and git status.\n   - Formulate a clear plan with dependencies before modifying code.\n2. **Phase 2: Atomic Implementation**\n   - Apply surgical, localized edits (`replace_in_file` or focused rewrites).\n   - Maintain consistent coding style, indentation, architecture patterns, and naming conventions.\n3. **Phase 3: Deterministic Verification & Validation**\n   - Run compilation commands and the tests relevant to the changed modules.\n   - Capture clean evidence (exit code, build duration, test pass counts).\n4. **Phase 4: Privacy & Git Safety Audit**\n   - Review git status and diff (`git diff`) before finalizing.\n   - Verify that NO private secrets or credentials have been written into `.microcode/` or workspace files.\n   - Update `.microcode/task.md` checklist with completion evidence.\n\n" +
                "## 4. Durable Project Conventions\n<!-- Add durable project conventions, tech stack guidelines, or architecture patterns below -->\n";
        }

        public static bool IsManagedTemplate(string text) { return text != null && (text.Contains("<!-- microcode:managed-agent -->") || text.Contains("<!-- microcode:managed-task -->")); }
    }

    // ── plan model (ImplementationPlan) ───────────────────────────────────────

    public class PlanStep { public string Text, Tag; public bool Done; }
    public class PlanSection { public string Title; public List<PlanStep> Steps = new List<PlanStep>(); }

    public class PlanDoc
    {
        public string Title = "Implementation Plan", Summary = "", Raw = "";
        public DateTime Created = DateTime.Now;
        public readonly List<string> Questions = new List<string>(), Review = new List<string>(), Verification = new List<string>();
        public readonly List<PlanSection> Sections = new List<PlanSection>();
        public int Total { get { return Sections.Sum(s => s.Steps.Count); } }
        public int Done { get { return Sections.Sum(s => s.Steps.Count(x => x.Done)); } }

        static readonly Regex Bullet = new Regex(@"^(?:[-*+]|\d+[.)])\s+(?:\[([ xX])\]\s+)?(.*)$");
        static readonly Regex TagRe = new Regex(@"\[(NEW|MODIFY|MODIFIED|DELETE|DELETED|ADD|UPDATE)\]", RegexOptions.IgnoreCase);

        /// <summary>Markdown → structured plan: H1 title, ## Summary / User Review / Open Questions / Proposed Changes (### groups) / Verification.</summary>
        public static PlanDoc Parse(string md, DateTime created)
        {
            // a reply often starts with chatter ("Let me look at the project first.") before the plan's H1 — the plan starts at the H1
            string text0 = (md ?? "").Replace("\r\n", "\n");
            var h1 = Regex.Match(text0, @"(?m)^#\s+\S");
            if (h1.Success) text0 = text0.Substring(h1.Index);
            var p = new PlanDoc { Raw = text0, Created = created };
            string h2 = "";
            bool titled = false;
            PlanSection cur = null;
            var summary = new StringBuilder();
            var preamble = new StringBuilder();
            foreach (var raw in text0.Split('\n'))
            {
                string tl = raw.Trim();
                if (tl.Length == 0 || tl == "---" || tl.StartsWith("<!--")) continue;
                if (tl.StartsWith("# ")) { if (!titled) { p.Title = Regex.Replace(tl.Substring(2), @"[`*_]", "").Trim(); titled = true; } continue; }
                if (tl.StartsWith("## ")) { h2 = Strip(tl.Substring(3)).ToLowerInvariant(); cur = null; continue; }
                if (tl.StartsWith("### ") || tl.StartsWith("#### "))
                {
                    if (!IsMeta(h2)) { cur = new PlanSection { Title = Strip(tl.TrimStart('#').Trim()) }; p.Sections.Add(cur); }
                    continue;
                }
                var bm = Bullet.Match(tl);
                if (bm.Success)
                {
                    string text = bm.Groups[2].Value.Trim();
                    bool done = bm.Groups[1].Value.ToLowerInvariant() == "x";
                    if (h2.Contains("question")) p.Questions.Add(text);
                    else if (h2.Contains("review") || h2.Contains("risk") || h2.Contains("decision")) p.Review.Add(text);
                    else if (h2.Contains("verif") || h2.Contains("test plan") || h2.Contains("validation")) p.Verification.Add(text);
                    else if (h2.Contains("summary") || h2.Contains("overview") || h2.Contains("scope") || h2.Contains("constraint") || h2.Contains("log")) { if (h2.Contains("summary") || h2.Contains("overview")) summary.Append(text).Append(' '); }
                    else
                    {
                        if (cur == null) { cur = new PlanSection { Title = h2.Length > 0 ? Cap(h2) : "Changes" }; p.Sections.Add(cur); }
                        var st = new PlanStep { Text = text, Done = done };
                        var tm = TagRe.Match(text);
                        if (tm.Success) { st.Tag = tm.Groups[1].Value.ToUpperInvariant(); st.Text = TagRe.Replace(text, "").Trim(); }
                        cur.Steps.Add(st);
                    }
                    continue;
                }
                if (h2.Contains("summary") || h2.Contains("overview")) summary.Append(tl).Append(' ');
                else if (h2.Length == 0) preamble.Append(tl).Append(' ');
            }
            p.Summary = (summary.Length > 0 ? summary : preamble).ToString().Trim();
            p.Sections.RemoveAll(s => s.Steps.Count == 0);
            return p;
        }

        static bool IsMeta(string h2) { return h2.Contains("question") || h2.Contains("verif") || h2.Contains("summary") || h2.Contains("overview") || h2.Contains("review"); }
        static string Strip(string s) { return Regex.Replace(s, @"^[^\p{L}\p{N}\[]+", "").Trim(); }
        static string Cap(string s) { return s.Length == 0 ? s : char.ToUpperInvariant(s[0]) + s.Substring(1); }
    }

    static class PanelUI
    {
        public static Btn Small(string icon, string label, Action a)
        {
            var t = Theme.Current;
            var row = V.H(3);
            if (icon != null) row.Children.Add(Sym.Icon(icon, 9.5, t.Secondary));
            if (label != null) row.Children.Add(V.T(label, 10, FontWeights.Medium, t.Secondary));
            return V.Button(V.Box(row, V.P(label != null ? 6 : 4, 3.5), t.P(0.05), 4), a);
        }

        public static Btn BackToChat(Action a)
        {
            var t = Theme.Current;
            var b = V.Button(V.Box(V.H(3, Sym.Icon("chevron.left", 9.5, t.Accent, FontWeights.Bold), V.T("Chat", 10.5, FontWeights.SemiBold, t.Accent)), V.P(7, 3.5), t.A(0.12), 5), a);
            b.ToolTip = "Return to AI Chat";
            return b;
        }

        public static UIElement Md(string md, double size)
        {
            var e = MarkdownView.Render(md ?? "", size);
            var b = e as Border;
            if (b != null) b.Padding = new Thickness(0);
            return e;
        }

        public static UIElement Empty(string icon, string title, string body)
        {
            var t = Theme.Current;
            var s = V.Vs(8, Sym.Icon(icon, 26, t.S(0.45)), V.T(title, 12.5, FontWeights.Medium, t.Secondary));
            if (body != null) { var tb = V.Wrap(V.T(body, 11, FontWeights.Normal, t.S(0.7)), TextAlignment.Center); tb.MaxWidth = 360; s.Children.Add(tb); }
            s.Margin = new Thickness(0, 50, 0, 30);
            return s;
        }

        public static TextBox Editor(string text, Action<string> changed)
        {
            var t = Theme.Current;
            var tb = new TextBox
            {
                Text = text ?? "", AcceptsReturn = true, AcceptsTab = true, TextWrapping = TextWrapping.Wrap, FontFamily = UIFonts.Mono, FontSize = 12,
                Foreground = t.Primary, Background = t.WorkspaceBackground, BorderThickness = new Thickness(0), CaretBrush = t.Primary,
                Padding = new Thickness(16, 12, 16, 12), VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            };
            tb.TextChanged += delegate { changed(tb.Text); };
            return tb;
        }

        public static string Ago(DateTime d)
        {
            var s = DateTime.Now - d;
            if (s.TotalMinutes < 1) return "now";
            if (s.TotalHours < 1) return (int)s.TotalMinutes + "m ago";
            if (s.TotalDays < 1) return (int)s.TotalHours + "h ago";
            return d.ToString("MMM d", CultureInfo.InvariantCulture);
        }

        public static string Tok(long n) { return n >= 1000000 ? (n / 1000000.0).ToString("0.0", CultureInfo.InvariantCulture) + "M" : n >= 1000 ? (n / 1000.0).ToString("0.0", CultureInfo.InvariantCulture) + "K" : n.ToString(); }
    }

    // ── Implementation Plan side panel ───────────────────────────────────────

    public class PlanPanel : Border
    {
        readonly IAgentHost _host;
        bool _raw;
        public bool Fullscreen;
        public event Action FullscreenToggled;
        public event Action CloseRequested;
        readonly ScrollViewer _scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };

        public PlanPanel(IAgentHost host)
        {
            _host = host;
            Background = Theme.Current.WorkspaceBackground;
            Render();
            // the header drops button labels when the panel is narrow
            double lastW = 0;
            SizeChanged += (s, e) => { if ((e.NewSize.Width < 470) != (lastW < 470)) { lastW = e.NewSize.Width; Render(); } else lastW = e.NewSize.Width; };
        }

        /// <summary>The plan on screen: the newest plan-mode reply in this chat, else the checklist in .microcode/task.md.</summary>
        public static PlanDoc Current(AppState app, out ChatMessage msg)
        {
            msg = null;
            var s = AgentStore.Active;
            if (s != null)
            {
                var m = s.Messages.LastOrDefault(x => x.Role == "assistant" && !string.IsNullOrEmpty(x.PlanState));
                if (m != null) { msg = m; return PlanDoc.Parse(AgentBlocks.StripThoughts(m.Content), m.Time); }
            }
            if (app.WorkspaceFolder != null && TaskFiles.Exists(app.WorkspaceFolder, "task.md"))
            {
                string md = TaskFiles.Read(app.WorkspaceFolder, "task.md");
                if (!string.IsNullOrWhiteSpace(md)) return PlanDoc.Parse(md, File.GetLastWriteTime(TaskFiles.PathFor(app.WorkspaceFolder, "task.md")));
            }
            return null;
        }

        public void Render()
        {
            var t = Theme.Current;
            ChatMessage msg;
            var plan = Current(_host.App, out msg);
            string state = msg != null ? msg.PlanState : null;
            // header (30pt)
            var titleTb = V.T("Implementation Plan", 12, FontWeights.Bold, t.Primary);
            titleTb.TextTrimming = TextTrimming.CharacterEllipsis;
            var head = V.H(6, PanelUI.BackToChat(() => { if (CloseRequested != null) CloseRequested(); }),
                Sym.Icon("list.bullet.clipboard.fill", 12, t.Accent), V.Shrink(titleTb));
            if (state != null) head.Children.Add(V.Shrink(Badge(state)));
            head.Children.Add(V.Sp(4));
            if (plan != null)
            {
                bool narrow = ActualWidth > 0 && ActualWidth < 470;
                var md = PanelUI.Small(_raw ? "list.bullet" : "chevron.left.forwardslash.chevron.right", narrow ? null : _raw ? "Structured" : "Markdown", () => { _raw = !_raw; Render(); });
                md.ToolTip = _raw ? "Switch to interactive structured plan" : "Switch to raw markdown";
                var copy = PanelUI.Small("doc.on.doc", null, () => { try { Clipboard.SetText(plan.Raw); } catch { } });
                copy.ToolTip = "Copy full implementation plan";
                head.Children.Add(md); head.Children.Add(copy);
            }
            var reload = PanelUI.Small("arrow.clockwise", null, Render);
            reload.ToolTip = "Reload plan (latest plan reply or .microcode/task.md)";
            var full = PanelUI.Small(Fullscreen ? "rectangle.split.2x1" : "arrow.up.left.and.arrow.down.right", null, () => { Fullscreen = !Fullscreen; if (FullscreenToggled != null) FullscreenToggled(); Render(); });
            full.ToolTip = Fullscreen ? "Exit Fullscreen (Restore Split View)" : "Expand Plan to Fullscreen";
            var close = PanelUI.Small("xmark", null, () => { if (CloseRequested != null) CloseRequested(); });
            close.ToolTip = "Close Plan Side Panel";
            head.Children.Add(reload); head.Children.Add(full); head.Children.Add(close);
            var header = V.Box(head, V.P(10, 0), null, 0);
            header.Height = 30;
            var body = V.VLead(18); body.Align = Cross.Stretch;
            if (plan == null) body.Children.Add(EmptyState());
            else if (_raw) body.Children.Add(PanelUI.Md(plan.Raw, 13));
            else Structured(body, plan, msg);
            double offset = _scroll.VerticalOffset;
            var oldRoot = _scroll.Parent as Panel;
            if (oldRoot != null) oldRoot.Children.Remove(_scroll); // re-render reuses the scroller (keeps the reading position)
            _scroll.Content = new Border { Child = body, Padding = new Thickness(18, 16, 18, 24) };
            _scroll.ScrollToVerticalOffset(offset);
            var root = new DockPanel();
            var top = V.VLead(0, V.Self(header, Cross.Stretch), V.Self(new Border { Height = 1, Background = t.Separator }, Cross.Stretch));
            top.Align = Cross.Stretch;
            DockPanel.SetDock(top, Dock.Top);
            root.Children.Add(top);
            root.Children.Add(_scroll);
            Child = root;
        }

        static UIElement Badge(string state)
        {
            var t = Theme.Current;
            Color c = state == "approved" ? Color.FromRgb(48, 209, 88) : state == "rejected" ? Color.FromRgb(255, 69, 58) : Color.FromRgb(255, 159, 10);
            string label = state == "approved" ? "Approved" : state == "rejected" ? "Changes Requested" : "Awaiting Review";
            var tb = V.T(label, 9.5, FontWeights.SemiBold, t.Secondary);
            tb.TextTrimming = TextTrimming.CharacterEllipsis;
            var b = V.Box(V.H(4, V.Dot(6, Theme.B(Theme.WithAlpha(c, 0.85))), V.Shrink(tb)), V.P(6, 2), t.P(0.05), 4);
            b.ToolTip = label;
            return b;
        }

        UIElement EmptyState()
        {
            var t = Theme.Current;
            var s = V.Vs(10, Sym.Icon("list.bullet.clipboard", 28, t.S(0.45)), V.T("No implementation plan yet", 13, FontWeights.Medium, t.Secondary));
            var note = V.Wrap(V.T("Switch to Plan mode and describe a task — the agent researches the workspace read-only and drafts a plan here for your approval.", 11, FontWeights.Normal, t.S(0.7)), TextAlignment.Center);
            note.MaxWidth = 300;
            s.Children.Add(note);
            var load = PanelUI.Small("arrow.down.doc", "Load from task.md", Render);
            var draft = V.Button(V.Box(V.H(4, Sym.Icon("sparkles", 10, Brushes.White), V.T("Draft a plan (/plan)", 10.5, FontWeights.SemiBold, Brushes.White)), V.P(10, 4), t.Accent, 5), () =>
            {
                string task = Prompt.Ask("Draft Implementation Plan", "What should the agent plan?", "");
                if (!string.IsNullOrWhiteSpace(task)) _host.RunPrompt(task.Trim(), true);
            });
            s.Children.Add(V.H(8, load, draft));
            s.Margin = new Thickness(0, 40, 0, 0);
            return s;
        }

        void Structured(Stack body, PlanDoc plan, ChatMessage msg)
        {
            var t = Theme.Current;
            Color orange = Color.FromRgb(255, 159, 10), green = Color.FromRgb(48, 209, 88);
            if (msg != null && msg.PlanState == "pending")
            {
                var reject = V.Button(V.Box(V.H(4, Sym.Icon("xmark", 9, t.Op(t.SysRed, 0.9), FontWeights.Bold), V.T("Reject", 11, FontWeights.Medium, t.Op(t.SysRed, 0.9))), V.P(10, 5), t.Op(t.SysRed, 0.08), 6, t.Op(t.SysRed, 0.2), 0.5), () => _host.RejectPlan(msg));
                var approve = V.Button(V.Box(V.H(6, Sym.Icon("checkmark", 9, Brushes.White, FontWeights.Bold), V.T("Approve Plan & Proceed", 11, FontWeights.SemiBold, Brushes.White)), V.P(12, 5), t.Accent, 6), () => _host.ApprovePlan(msg));
                var c = V.VLead(8, V.Self(V.H(8, Sym.Icon("list.bullet.clipboard", 12, Theme.B(orange), FontWeights.SemiBold), V.T("Plan Review Required", 12.5, FontWeights.SemiBold, t.Primary), V.Sp(),
                    V.Box(V.T("Awaiting Review", 10, FontWeights.SemiBold, Theme.B(orange)), V.P(6, 2), Theme.B(Theme.WithAlpha(orange, 0.12)), 4)), Cross.Stretch),
                    V.Wrap(V.T("The AI agent is paused awaiting authorization before making code modifications.", 11.5, FontWeights.Normal, t.Secondary), TextAlignment.Left),
                    V.Self(V.H(8, reject, V.Sp(), approve), Cross.Stretch));
                c.Align = Cross.Stretch;
                body.Children.Add(V.Self(V.Box(c, V.P(12, 10), t.P(0.035), 10, Theme.B(Theme.WithAlpha(orange, 0.3)), 1), Cross.Stretch));
            }
            else if (msg != null)
            {
                bool ok = msg.PlanState == "approved";
                body.Children.Add(V.Self(V.Box(V.H(8, Sym.Icon(ok ? "checkmark.seal.fill" : "xmark.circle", 12, ok ? Theme.B(green) : t.SysRed), V.T(ok ? "Plan approved — the agent is executing it" : "Plan rejected — describe your changes in the chat", 11.5, FontWeights.Medium, t.Primary)),
                    V.P(12, 9), ok ? Theme.B(Theme.WithAlpha(green, 0.08)) : t.Op(t.SysRed, 0.06), 9), Cross.Stretch));
            }
            var info = V.VLead(6, V.Wrap(V.T(plan.Title, 16, FontWeights.Bold, t.Primary), TextAlignment.Left));
            info.Align = Cross.Stretch;
            if (plan.Summary.Length > 0) info.Children.Add(V.Wrap(V.T(Regex.Replace(plan.Summary, @"[`*]", ""), 12, FontWeights.Normal, t.Secondary), TextAlignment.Left));
            var meta = V.H(12, V.H(4, Sym.Icon("calendar", 10, t.S(0.7)), V.T(plan.Created.ToString("MMM d, yyyy", CultureInfo.InvariantCulture), 10.5, FontWeights.Normal, t.S(0.8))),
                V.H(4, Sym.Icon("clock", 10, t.S(0.7)), V.T(plan.Created.ToString("HH:mm", CultureInfo.InvariantCulture), 10.5, FontWeights.Normal, t.S(0.8))));
            if (plan.Total > 0) meta.Children.Add(V.H(4, Sym.Icon("checklist", 10, t.S(0.7)), V.T(plan.Done + "/" + plan.Total + " steps completed (" + (int)(100.0 * plan.Done / plan.Total) + "%)", 10.5, FontWeights.Normal, t.S(0.8))));
            info.Children.Add(meta);
            body.Children.Add(info);
            if (plan.Total > 0)
            {
                double ratio = (double)plan.Done / plan.Total;
                var fill = new Border { CornerRadius = new CornerRadius(2), Background = ratio >= 1 ? Theme.B(green) : t.Accent, HorizontalAlignment = HorizontalAlignment.Left };
                var bar = new Grid { Height = 4 };
                bar.Children.Add(new Border { CornerRadius = new CornerRadius(2), Background = t.P(0.08) });
                bar.Children.Add(fill);
                bar.SizeChanged += delegate { fill.Width = Math.Max(ratio > 0 ? 4 : 0, bar.ActualWidth * ratio); };
                body.Children.Add(V.Self(bar, Cross.Stretch));
            }
            Action<string, string, Color, List<string>, bool> listBox = (icon, title, color, items, numbered) =>
            {
                if (items.Count == 0) return;
                var col = V.VLead(8, V.H(6, Sym.Icon(icon, 11, Theme.B(color)), V.T(title, 12, FontWeights.SemiBold, t.Primary)));
                col.Align = Cross.Stretch;
                for (int i = 0; i < items.Count; i++)
                {
                    var line = V.H(8, V.Self(V.T(numbered ? (i + 1) + "." : "•", 11.5, FontWeights.SemiBold, t.Secondary), Cross.Start), V.Flex(PanelUI.Md(items[i], 12)));
                    col.Children.Add(V.Self(line, Cross.Stretch));
                }
                body.Children.Add(V.Self(V.Box(col, V.P(12, 10), Theme.B(Theme.WithAlpha(color, 0.06)), 8, Theme.B(Theme.WithAlpha(color, 0.2)), 1), Cross.Stretch));
            };
            listBox("exclamationmark.triangle.fill", "User Review Required", orange, plan.Review, false);
            listBox("questionmark.circle.fill", "Open Questions & Decisions", Color.FromRgb(191, 90, 242), plan.Questions, false);
            if (plan.Sections.Count > 0)
            {
                var changes = V.VLead(14, V.Self(V.H(8, V.T("Proposed Changes", 13, FontWeights.SemiBold, t.Primary), V.Sp(), V.T(plan.Sections.Count + " sections • " + plan.Total + " steps", 10.5, FontWeights.Normal, t.Secondary)), Cross.Stretch));
                changes.Align = Cross.Stretch;
                foreach (var sec in plan.Sections)
                {
                    var sc = V.VLead(8, V.Self(V.H(8, V.Shrink(V.T(sec.Title, 12, FontWeights.SemiBold, t.Primary)), V.Sp(), V.T(sec.Steps.Count + " steps", 10, FontWeights.Normal, t.Secondary)), Cross.Stretch));
                    sc.Align = Cross.Stretch;
                    var steps = V.VLead(4); steps.Align = Cross.Stretch;
                    foreach (var st in sec.Steps) steps.Children.Add(StepRow(st));
                    sc.Children.Add(steps);
                    changes.Children.Add(V.Self(V.Box(sc, V.P(12, 10), t.P(0.03), 8, t.P(0.07), 1), Cross.Stretch));
                }
                body.Children.Add(changes);
            }
            listBox("checkmark.shield.fill", "Verification Plan", green, plan.Verification, true);
        }

        UIElement StepRow(PlanStep st)
        {
            var t = Theme.Current;
            Color tagColor = st.Tag == null ? Colors.Gray : st.Tag.StartsWith("NEW") || st.Tag == "ADD" ? Color.FromRgb(48, 209, 88) : st.Tag.StartsWith("DEL") ? Color.FromRgb(255, 69, 58) : Color.FromRgb(10, 132, 255);
            var row = V.H(8, V.Self(Sym.Icon(st.Done ? "checkmark.circle.fill" : "circle", 12, st.Done ? Theme.B(Color.FromRgb(48, 209, 88)) : t.S(0.55)), Cross.Start));
            if (st.Tag != null) row.Children.Add(V.Self(V.Box(V.Mono(st.Tag, 8.5, FontWeights.Bold, Theme.B(tagColor)), V.P(5, 1.5), Theme.B(Theme.WithAlpha(tagColor, 0.12)), 3.5), Cross.Start));
            var text = PanelUI.Md(st.Text, 12);
            ((FrameworkElement)text).Opacity = st.Done ? 0.65 : 1;
            row.Children.Add(V.Flex(text));
            return V.Self(V.Box(row, V.P(8, 6), st.Done ? t.P(0.015) : t.P(0.03), 6), Cross.Stretch);
        }
    }

    // ── Task editor (taskEditorView) ─────────────────────────────────────────

    public class TaskPanel : Border
    {
        readonly IAgentHost _host;
        public int Tab;
        int _viewMode; // 0 rendered, 1 edit
        string _task, _agent, _walk, _ws;
        bool _dirty;
        FileSystemWatcher _watch;
        DispatcherTimer _refresh;
        // kept across re-renders so a request being typed (and the PNS launcher fields) survive live updates
        ConsensusView _consensus;
        PnsView _pnsView;
        readonly Border _content = new Border();
        readonly Border _toolbar = new Border();

        public TaskPanel(IAgentHost host, int tab)
        {
            _host = host; Tab = tab;
            Background = Theme.Current.WorkspaceBackground;
            var dock = new DockPanel();
            DockPanel.SetDock(_toolbar, Dock.Top);
            dock.Children.Add(_toolbar);
            dock.Children.Add(_content);
            Child = dock;
            Load();
            Unloaded += delegate { if (_watch != null) { _watch.EnableRaisingEvents = false; _watch.Dispose(); _watch = null; } };
            Loaded += delegate { Watch(); };
            Render();
        }

        /// <summary>loadTaskFiles: task.md / agent.md fall back to the managed templates; the walkthrough to the template only once it exists.</summary>
        void Load()
        {
            _ws = _host.App.WorkspaceFolder;
            _task = TaskFiles.Read(_ws, "task.md") ?? TaskFiles.DefaultTask("");
            _agent = TaskFiles.Read(_ws, "agent.md") ?? TaskFiles.DefaultAgent();
            _walk = TaskFiles.Read(_ws, "walkthrough.md") ?? TaskFiles.DefaultWalkthrough;
            _dirty = false;
        }

        void Save()
        {
            if (_ws == null) return;
            try
            {
                TaskFiles.Write(_ws, "task.md", Redact(_task));
                TaskFiles.Write(_ws, "agent.md", Redact(_agent));
                TaskFiles.Write(_ws, "walkthrough.md", Redact(_walk));
                _dirty = false;
            }
            catch (Exception ex) { MessageBox.Show(Window.GetWindow(this), "Could not save task files: " + ex.Message, "MicroCode"); }
        }

        /// <summary>AgentPrivacyGuard.sanitize: never persist secrets into the agent's state files.</summary>
        static string Redact(string s)
        {
            if (s == null) return "";
            return Regex.Replace(s, @"(sk-[A-Za-z0-9_\-]{16,}|sk-ant-[A-Za-z0-9_\-]{16,}|AIza[0-9A-Za-z_\-]{30,}|ghp_[A-Za-z0-9]{30,}|xox[baprs]-[A-Za-z0-9\-]{10,}|sk-dotmini-[a-z]+-[A-Za-z0-9]{8,})", "[REDACTED_SECRET_FOR_PRIVACY]");
        }

        void Watch()
        {
            if (_ws == null || _watch != null) return;
            try
            {
                string dir = TaskFiles.StateDir(_ws);
                Directory.CreateDirectory(dir);
                _watch = new FileSystemWatcher(dir, "*.md") { NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.Size };
                FileSystemEventHandler h = (s, e) => Dispatcher.BeginInvoke(new Action(ScheduleReload));
                _watch.Changed += h; _watch.Created += h;
                _watch.EnableRaisingEvents = true;
            }
            catch { }
        }

        void ScheduleReload()
        {
            if (_refresh == null)
            {
                _refresh = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) };
                _refresh.Tick += delegate { _refresh.Stop(); if (!_dirty && _viewMode == 0) { Load(); Render(); } };
            }
            _refresh.Stop(); _refresh.Start();
        }

        public void Refresh() { if (!_dirty) Load(); Render(); }

        public void Render()
        {
            var t = Theme.Current;
            var tabs = V.H(4);
            Action<string, string, int, int> tab = (label, icon, idx, badge) =>
            {
                bool on = Tab == idx;
                var row = V.H(4, Sym.Icon(icon, 9, on ? t.Primary : t.Secondary), V.T(label, 10.5, on ? FontWeights.SemiBold : FontWeights.Medium, on ? t.Primary : t.Secondary));
                if (badge > 0) row.Children.Add(V.Box(V.Mono(badge.ToString(), 8.5, FontWeights.Bold, t.Secondary), V.P(4, 0.5), t.P(0.08), 6));
                var b = V.Button(V.Box(row, V.P(8, 4), on ? t.P(0.10) : Brushes.Transparent, 5), () => { Tab = idx; if (idx == 0) AgentStore.SelectTaskTab(0); else AgentStore.SelectTaskTab(idx); Render(); });
                if (!on) b.OnState = x => ((Border)x.Child).Background = x.IsHover ? t.P(0.05) : Brushes.Transparent;
                tabs.Children.Add(b);
            };
            tab("Checklist", "checklist", 0, 0);
            tab("Spec", "doc.text", 1, 0);
            tab("Walkthrough", "sparkles", 2, 0);
            tab("Logs", "terminal", 3, ActivityCount());
            if (Tab == 4) tab("Cost", "chart.bar.xaxis", 4, 0);
            else if (Tab == 5) tab("Audit", "airplane.circle", 5, 0);
            else if (Tab == 6) tab("Consensus", "shield.checkered", 6, 0);
            else if (Tab == 7) tab("PNS 24/7", "point.3.connected.trianglepath.dotted", 7, 0);
            var bar = V.H(8, PanelUI.BackToChat(() => AgentStore.SelectChat()), tabs, V.Sp(4));
            if (Tab < 3)
            {
                Func<int, string, string, UIElement> seg = (mode, icon, label) =>
                {
                    bool on = _viewMode == mode;
                    var b = V.Button(V.Box(V.H(3, Sym.Icon(icon, 10, on ? t.Primary : t.Secondary), V.T(label, 9.5, on ? FontWeights.SemiBold : FontWeights.Normal, on ? t.Primary : t.Secondary)), V.P(6, 3), on ? t.P(0.12) : Brushes.Transparent, 4), () => { _viewMode = mode; Render(); });
                    b.ToolTip = mode == 0 ? "Rendered Document View" : "Edit Markdown Source";
                    return b;
                };
                bar.Children.Add(V.Box(V.H(1, seg(0, "doc.richtext", "Rendered"), seg(1, "pencil", "Edit")), V.P(2), t.P(0.04), 5));
                bar.Children.Add(V.Size(new Border { Background = t.P(0.15) }, 1, 14));
                if (_host.IsRunning)
                {
                    var stop = V.Button(V.Box(V.H(4, Sym.Icon("stop.fill", 8, Theme.B(Color.FromRgb(255, 69, 58))), V.T("Stop", 10, FontWeights.SemiBold, Theme.B(Color.FromRgb(255, 69, 58)))), V.P(8, 3.5), Theme.B(Theme.WithAlpha(Color.FromRgb(255, 69, 58), 0.12)), 4), () => { _host.StopRun(); Render(); });
                    stop.ToolTip = "Stop Task Execution";
                    bar.Children.Add(stop);
                }
                else
                {
                    var run = V.Button(V.Box(V.H(4, Sym.Icon("play.fill", 8, t.Primary), V.T("Run", 10, FontWeights.SemiBold, t.Primary)), V.P(8, 3.5), t.A(0.2), 4, t.A(0.4), 1), RunTask);
                    run.ToolTip = "Run Task with Agent";
                    bar.Children.Add(run);
                }
                var save = V.Button(V.Box(V.H(3, Sym.Icon("arrow.down.doc", 8.5, t.Secondary), V.T(_dirty ? "Save •" : "Save", 10, FontWeights.Medium, t.Secondary)), V.P(7, 3.5), t.P(0.06), 4), () => { Save(); Render(); });
                save.ToolTip = "Save Markdown Files";
                bar.Children.Add(save);
            }
            var tb = V.VLead(0, V.Self(V.Box(bar, V.P(10, 0), t.PanelBackground, 0), Cross.Stretch), V.Self(new Border { Height = 1, Background = t.Separator }, Cross.Stretch));
            ((Border)tb.Children[0]).Height = 32;
            tb.Align = Cross.Stretch;
            _toolbar.Child = tb;
            if (_ws == null && Tab < 3) { _content.Child = PanelUI.Empty("folder", "Open a project folder", "Task, Spec and Walkthrough files are kept per workspace."); return; }
            switch (Tab)
            {
                case 0: _content.Child = _viewMode == 1 ? (UIElement)PanelUI.Editor(_task, v => { _task = v; _dirty = true; }) : Checklist(); break;
                case 1: _content.Child = _viewMode == 1 ? (UIElement)PanelUI.Editor(_agent, v => { _agent = v; _dirty = true; }) : Doc(_agent); break;
                case 2: _content.Child = _viewMode == 1 ? (UIElement)PanelUI.Editor(_walk, v => { _walk = v; _dirty = true; }) : Doc(_walk); break;
                case 3: _content.Child = new AgentLogsView(_host); break;
                case 4: _content.Child = new CostView(); break;
                case 5: _content.Child = new AuditView(); break;
                case 6: _content.Child = _consensus ?? (_consensus = new ConsensusView(_host.App)); break;
                default: _content.Child = _pnsView ?? (_pnsView = new PnsView(_host.App, PnsOrchestrator.Shared)); break;
            }
        }

        int ActivityCount() { var s = AgentStore.Active; return s == null ? 0 : s.Messages.Sum(m => m.Steps.Count); }

        UIElement Doc(string md)
        {
            return new ScrollViewer { Content = new Border { Child = PanelUI.Md(md, 13), Padding = new Thickness(18) }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        }

        class Step { public int Line; public string Text; public bool Done; }

        static List<Step> Parse(string text)
        {
            var list = new List<Step>();
            var lines = (text ?? "").Replace("\r\n", "\n").Split('\n');
            for (int i = 0; i < lines.Length; i++)
            {
                string tl = lines[i].Trim();
                if (tl.StartsWith("- [ ] ") || tl.StartsWith("* [ ] ")) list.Add(new Step { Line = i, Text = tl.Substring(6), Done = false });
                else if (tl.StartsWith("- [x] ") || tl.StartsWith("- [X] ") || tl.StartsWith("* [x] ") || tl.StartsWith("* [X] ")) list.Add(new Step { Line = i, Text = tl.Substring(6), Done = true });
            }
            return list;
        }

        void Toggle(int lineIndex)
        {
            var lines = _task.Replace("\r\n", "\n").Split('\n');
            if (lineIndex < 0 || lineIndex >= lines.Length) return;
            string l = lines[lineIndex];
            if (l.Contains("- [ ]")) l = l.Replace("- [ ]", "- [x]");
            else if (l.Contains("- [x]")) l = l.Replace("- [x]", "- [ ]");
            else if (l.Contains("- [X]")) l = l.Replace("- [X]", "- [ ]");
            else if (l.Contains("* [ ]")) l = l.Replace("* [ ]", "* [x]");
            else if (l.Contains("* [x]")) l = l.Replace("* [x]", "* [ ]");
            lines[lineIndex] = l;
            _task = string.Join("\n", lines);
            Save();
            Render();
        }

        UIElement Checklist()
        {
            var t = Theme.Current;
            var steps = Parse(_task);
            int done = steps.Count(s => s.Done), total = steps.Count;
            var root = new DockPanel();
            if (total > 0)
            {
                double ratio = (double)done / total;
                var fill = new Border { CornerRadius = new CornerRadius(2), Background = t.Accent, HorizontalAlignment = HorizontalAlignment.Left };
                var pbar = new Grid { Height = 4, Margin = new Thickness(16, 0, 16, 10) };
                pbar.Children.Add(new Border { CornerRadius = new CornerRadius(2), Background = t.P(0.08) });
                pbar.Children.Add(fill);
                pbar.SizeChanged += delegate { fill.Width = Math.Max(ratio > 0 ? 4 : 0, pbar.ActualWidth * ratio); };
                var head = V.VLead(6, V.Self(V.Box(V.H(8, V.T(done + " of " + total + " steps completed", 11, FontWeights.Medium, t.Secondary), V.Sp(), V.Mono((int)(ratio * 100) + "%", 11, FontWeights.SemiBold, t.Primary)), V.P(16, 10, 16, 0), null, 0), Cross.Stretch),
                    V.Self(pbar, Cross.Stretch), V.Self(new Border { Height = 1, Background = t.P(0.06) }, Cross.Stretch));
                head.Align = Cross.Stretch;
                DockPanel.SetDock(head, Dock.Top);
                root.Children.Add(head);
            }
            var list = V.VLead(6); list.Align = Cross.Stretch;
            if (steps.Count == 0)
            {
                if (_task.Trim().Length > 0) list.Children.Add(PanelUI.Md(_task, 13));
                else list.Children.Add(PanelUI.Empty("list.bullet.rectangle", "No checklist steps found in task.md", "Add lines starting with `- [ ] Your step description`"));
            }
            else
            {
                foreach (var st in steps)
                {
                    var s = st;
                    var box = V.Button(Sym.Icon(s.Done ? "checkmark.square.fill" : "square", 14, s.Done ? t.Accent : t.Secondary), () => Toggle(s.Line));
                    box.ToolTip = s.Done ? "Mark as not done" : "Mark as done";
                    var text = PanelUI.Md(s.Text, 12.5);
                    ((FrameworkElement)text).Opacity = s.Done ? 0.65 : 1;
                    var row = V.H(10, V.Self(box, Cross.Start), V.Flex(text));
                    if (!s.Done && !_host.IsRunning)
                    {
                        var runStep = V.Button(V.Box(V.H(3, Sym.Icon("play.fill", 7, t.Secondary), V.T("Run Step", 9.5, FontWeights.Normal, t.Secondary)), V.P(6, 3), t.P(0.05), 4), () => RunStep(s.Text));
                        row.Children.Add(V.Self(runStep, Cross.Start));
                    }
                    list.Children.Add(V.Self(V.Box(row, V.P(16, 8), s.Done ? t.P(0.015) : t.P(0.035), 6), Cross.Stretch));
                }
                list.Children.Add(V.Self(V.Box(new Border { Height = 1, Background = t.P(0.06) }, V.P(0, 8), null, 0), Cross.Stretch));
                list.Children.Add(V.Box(PanelUI.Md(_task, 13), V.P(8, 0), null, 0));
            }
            var sv = new ScrollViewer { Content = new Border { Child = list, Padding = new Thickness(14) }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            root.Children.Add(sv);
            return root;
        }

        /// <summary>executeCurrentTaskPlan</summary>
        void RunTask()
        {
            if (_ws == null) return;
            Save();
            _host.RunPrompt("Execute the task plan in `.microcode/task.md` step by step.\nRules:\n1. Work through the unchecked `- [ ]` steps in order, using the tools to actually do and verify each one.\n2. After a step is verified, check it off (`- [x]`) in `.microcode/task.md` and record evidence in its Verification Log.\n3. When everything is done, set **Status** to 🟢 COMPLETED and write a concise summary of the changes and verification results to `.microcode/walkthrough.md`.", false);
            Render();
        }

        /// <summary>executeSingleStep</summary>
        void RunStep(string text)
        {
            Save();
            _host.RunPrompt("Execute this single task step from .microcode/task.md:\nTarget Step: " + text + "\nInstructions:\n1. Execute the necessary actions/tools to complete this specific step.\n2. Once completed, update .microcode/task.md to check off this step.", false);
            Render();
        }
    }

    // ── Walkthrough artifact (walkthroughView) ───────────────────────────────

    public class WalkthroughPanel : Border
    {
        readonly IAgentHost _host;
        public WalkthroughPanel(IAgentHost host) { _host = host; Background = Theme.Current.WorkspaceBackground; Render(); }

        public void Render()
        {
            var t = Theme.Current;
            string ws = _host.App.WorkspaceFolder;
            string md = ws != null ? TaskFiles.Read(ws, "walkthrough.md") : null;
            var head = V.H(10, PanelUI.BackToChat(() => AgentStore.SelectChat()), Sym.Icon("sparkles", 16, t.Accent),
                V.VLead(2, V.T("Walkthrough Artifact", 16, FontWeights.SemiBold, t.Primary), V.T("Task accomplishments, verification results, and artifacts summary", 11, FontWeights.Normal, t.Secondary)), V.Sp(),
                PanelUI.Small("arrow.clockwise", "Refresh", Render));
            var col = V.VLead(16, V.Self(head, Cross.Stretch), V.Self(new Border { Height = 1, Background = t.Separator }, Cross.Stretch));
            col.Align = Cross.Stretch;
            if (string.IsNullOrWhiteSpace(md))
                col.Children.Add(PanelUI.Empty("doc.text.magnifyingglass", "No walkthrough generated yet", "Once the Agent executes steps and produces walkthrough.md, the summary will render here."));
            else
                col.Children.Add(V.Self(V.Box(PanelUI.Md(md, 13), V.P(18), t.PanelBackground, 10, t.P(0.08), 1), Cross.Stretch));
            Child = new ScrollViewer { Content = new Border { Child = col, Padding = new Thickness(20, 16, 20, 24), MaxWidth = 980 }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        }
    }

    // ── Logs (TaskLogsView) ──────────────────────────────────────────────────

    public class AgentLogsView : Border
    {
        public AgentLogsView(IAgentHost host)
        {
            var t = Theme.Current;
            var s = AgentStore.Active;
            var steps = s == null ? new List<ToolStep>() : s.Messages.SelectMany(m => m.Steps).OrderByDescending(x => x.Time).ToList();
            Func<string> asText = () => string.Join(Environment.NewLine, steps.OrderBy(x => x.Time).Select(x => x.Time.ToString("HH:mm:ss", CultureInfo.InvariantCulture) + "  " + (x.Ok ? "OK  " : "FAIL") + "  " + AgentRunner.Headline(x) + "  [" + x.Approval + "]" + Environment.NewLine + Indent(x.Result)));
            var copy = PanelUI.Small("doc.on.doc", "Copy", () => { try { Clipboard.SetText(asText()); } catch { } });
            var export = PanelUI.Small("square.and.arrow.up", "Export", () =>
            {
                var d = new Microsoft.Win32.SaveFileDialog { FileName = "agent-activity-" + DateTime.Now.ToString("yyyyMMdd-HHmm") + ".log", Filter = "Log (*.log)|*.log|Text (*.txt)|*.txt" };
                if (d.ShowDialog() == true) File.WriteAllText(d.FileName, asText(), new UTF8Encoding(false));
            });
            bool running = host.IsRunning;
            var head = V.H(8, V.Dot(7, running ? Theme.B(Color.FromRgb(48, 209, 88)) : t.S(0.4)), V.T(running ? "Running…" : "Idle / Completed", 11.5, FontWeights.SemiBold, t.Primary),
                V.Box(V.Mono(steps.Count.ToString(), 9.5, FontWeights.Bold, t.Secondary), V.P(5, 1), t.P(0.08), 6), V.Sp(), copy, export);
            var list = V.VLead(4); list.Align = Cross.Stretch;
            if (steps.Count == 0) list.Children.Add(PanelUI.Empty("terminal", "No Task Activities Logged", "When you ask the AI Agent to execute tasks, search code, edit files, or run commands, real-time activity steps will stream here."));
            foreach (var st in steps)
            {
                var step = st;
                var output = new TextBox { Text = step.Result ?? "", IsReadOnly = true, FontFamily = UIFonts.Mono, FontSize = 11, Foreground = t.S(0.9), Background = Brushes.Transparent, BorderThickness = new Thickness(0), TextWrapping = TextWrapping.Wrap, MaxHeight = 240, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
                var outBox = V.Box(output, V.P(10, 6), t.P(0.035), 6);
                outBox.Visibility = Visibility.Collapsed;
                outBox.Margin = new Thickness(76, 2, 0, 4);
                Color ac = step.Approval == "rejected" || step.Approval == "timeout" || step.Approval == "blocked" ? Color.FromRgb(255, 159, 10) : step.Approval == "approved" ? Color.FromRgb(10, 132, 255) : Colors.Gray;
                var line = V.H(8, V.Mono(step.Time.ToString("HH:mm:ss", CultureInfo.InvariantCulture), 10.5, FontWeights.Normal, t.S(0.6)), Sym.Icon(step.Ok ? "checkmark.circle.fill" : "xmark.circle", 11, step.Ok ? t.SysGreen : t.SysRed),
                    V.Shrink(V.T(AgentRunner.Headline(step), 12, FontWeights.Normal, t.P(0.9))), V.Sp(), V.Box(V.Mono(step.Approval, 9, FontWeights.SemiBold, Theme.B(ac)), V.P(5, 1.5), Theme.B(Theme.WithAlpha(ac, 0.12)), 4));
                var row = V.Button(V.Box(line, V.P(10, 5), Brushes.Transparent, 6), () => outBox.Visibility = outBox.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible);
                row.OnState = b => ((Border)b.Child).Background = b.IsHover ? t.P(0.04) : Brushes.Transparent;
                list.Children.Add(V.Self(row, Cross.Stretch));
                list.Children.Add(V.Self(outBox, Cross.Stretch));
            }
            var root = new DockPanel();
            var top = V.Box(head, V.P(16, 10), null, 0);
            DockPanel.SetDock(top, Dock.Top);
            root.Children.Add(top);
            root.Children.Add(new ScrollViewer { Content = new Border { Child = list, Padding = new Thickness(8, 0, 8, 16) }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
            Child = root;
        }

        static string Indent(string s) { return string.Join(Environment.NewLine, (s ?? "").Replace("\r\n", "\n").Split('\n').Take(40).Select(l => "    " + l)); }
    }

    // ── Cost (CostDashboardView) ─────────────────────────────────────────────

    public class CostView : Border
    {
        public CostView()
        {
            var t = Theme.Current;
            var turns = AgentStore.Sessions.SelectMany(s => s.Messages).Where(m => m.Role == "assistant" && (m.InputTokens > 0 || m.OutputTokens > 0)).OrderByDescending(m => m.Time).ToList();
            long tin = turns.Sum(m => (long)m.InputTokens), tout = turns.Sum(m => (long)m.OutputTokens);
            int reqs = turns.Sum(m => Math.Max(1, m.Requests));
            bool estimated = turns.Any(m => m.UsageEstimated);
            double thb = turns.Sum(m => Cost(m));
            Func<string, string, string, UIElement> tile = (label, value, sub) =>
            {
                var c = V.VLead(3, V.T(label, 10, FontWeights.Medium, t.Secondary), V.T(value, 18, FontWeights.SemiBold, t.Primary));
                if (sub != null) c.Children.Add(V.T(sub, 9.5, FontWeights.Normal, t.S(0.7)));
                var b = V.Box(c, V.P(12, 10), t.P(0.035), 8, t.P(0.07), 1);
                b.Margin = new Thickness(0, 0, 10, 0);
                return b;
            };
            var tiles = new UniformGrid { Rows = 1, Columns = 4 };
            tiles.Children.Add(tile("Requests", reqs.ToString(), turns.Count + " agent turns"));
            tiles.Children.Add(tile("Input Tokens", PanelUI.Tok(tin) + "↑", estimated ? "≈ includes estimates" : null));
            tiles.Children.Add(tile("Output Tokens", PanelUI.Tok(tout) + "↓", null));
            tiles.Children.Add(tile("Est. Cost", thb > 0 ? "฿" + thb.ToString("0.00", CultureInfo.InvariantCulture) : "—", "Dotmini Cloud rates"));
            var col = V.VLead(16, V.H(8, Sym.Icon("chart.bar.xaxis", 14, t.Accent), V.T("Cost Dashboard", 15, FontWeights.SemiBold, t.Primary)), V.Self(tiles, Cross.Stretch));
            col.Align = Cross.Stretch;
            if (turns.Count == 0) col.Children.Add(PanelUI.Empty("chart.bar.xaxis", "No usage data yet", "Token usage and costs will appear here as you use AI features."));
            else
            {
                var byModel = V.VLead(4, V.T("By Model", 12, FontWeights.SemiBold, t.Primary)); byModel.Align = Cross.Stretch;
                foreach (var g in turns.GroupBy(m => m.Model ?? "unknown").OrderByDescending(g => g.Sum(m => (long)m.InputTokens + m.OutputTokens)))
                {
                    var cm = DotminiCloud.Find(g.Key);
                    double c = g.Sum(m => Cost(m));
                    byModel.Children.Add(V.Self(V.Box(V.H(10, V.Flex(V.T(cm != null ? cm.Name : AIConfig.FormatModelName(g.Key), 12, FontWeights.Medium, t.Primary)), V.T(g.Sum(m => Math.Max(1, m.Requests)) + " req", 10.5, FontWeights.Normal, t.Secondary),
                        V.Mono(PanelUI.Tok(g.Sum(m => (long)m.InputTokens)) + "↑", 10.5, FontWeights.Normal, t.Secondary), V.Mono(PanelUI.Tok(g.Sum(m => (long)m.OutputTokens)) + "↓", 10.5, FontWeights.Normal, t.Secondary),
                        V.Mono(c > 0 ? "฿" + c.ToString("0.00", CultureInfo.InvariantCulture) : "—", 10.5, FontWeights.SemiBold, t.Primary)), V.P(10, 6), t.P(0.03), 6), Cross.Stretch));
                }
                col.Children.Add(byModel);
                var recent = V.VLead(4, V.H(8, V.T("Recent", 12, FontWeights.SemiBold, t.Primary), V.Sp(), V.T(turns.Count + " total", 10.5, FontWeights.Normal, t.Secondary))); recent.Align = Cross.Stretch;
                foreach (var m in turns.Take(25))
                    recent.Children.Add(V.Self(V.H(10, V.Mono(m.Time.ToString("MMM d HH:mm", CultureInfo.InvariantCulture), 10.5, FontWeights.Normal, t.S(0.6)), V.Flex(V.T(AIConfig.FormatModelName(m.Model ?? "unknown"), 11.5, FontWeights.Normal, t.P(0.9))),
                        V.Mono((m.InputTokens + m.OutputTokens) + " tok" + (m.UsageEstimated ? " ≈" : ""), 10.5, FontWeights.Normal, t.Secondary)), Cross.Stretch));
                col.Children.Add(recent);
                if (estimated) col.Children.Add(V.Wrap(V.T("≈ Some providers do not report token usage while streaming; those turns are estimated at ~4 characters per token.", 10.5, FontWeights.Normal, t.S(0.7)), TextAlignment.Left));
            }
            Child = new ScrollViewer { Content = new Border { Child = col, Padding = new Thickness(18, 14, 18, 24) }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        }

        static double Cost(ChatMessage m)
        {
            var cm = DotminiCloud.Find(m.Model ?? "");
            if (cm == null) return 0;
            double i = cm.InTHB, o = cm.OutTHB;
            if (i <= 0 && o <= 0) { i = cm.InUSD * 36.5 * 1.2; o = cm.OutUSD * 36.5 * 1.2; }
            return m.InputTokens / 1e6 * i + m.OutputTokens / 1e6 * o;
        }
    }

    // ── Audit (FlightRecorderView) ───────────────────────────────────────────

    public class AuditView : Border
    {
        class Ev { public DateTime Time; public string Icon, Kind, Text, Detail; public Color Color; }

        public AuditView()
        {
            var t = Theme.Current;
            var s = AgentStore.Active;
            var evs = new List<Ev>();
            if (s != null)
                foreach (var m in s.Messages)
                {
                    if (m.Role == "user") evs.Add(new Ev { Time = m.Time, Icon = "person.crop.circle", Kind = "PROMPT", Text = Short(m.Content), Detail = m.Attachments.Count > 0 ? m.Attachments.Count + " attachment(s)" : null, Color = Color.FromRgb(10, 132, 255) });
                    else
                    {
                        foreach (var st in m.Steps)
                        {
                            bool edit = st.Name == "file_write" || st.Name == "replace_in_file";
                            evs.Add(new Ev { Time = st.Time, Icon = edit ? "pencil" : st.Name == "shell" ? "terminal" : "doc.text", Kind = edit ? "FILE WRITE" : st.Name == "shell" ? "SHELL" : "READ", Text = AgentRunner.Headline(st) + (edit && st.Ok ? "  +" + st.Added + " -" + st.Removed : ""),
                                Detail = "approval: " + st.Approval + (st.Ok ? "" : " · failed") + (st.Reverted ? " · reverted" : "") + (st.Path != null ? " · " + AgentRunner.DisplayPath(st.Path) : ""),
                                Color = !st.Ok ? Color.FromRgb(255, 69, 58) : edit ? Color.FromRgb(255, 159, 10) : st.Name == "shell" ? Color.FromRgb(191, 90, 242) : Color.FromRgb(142, 142, 147) });
                        }
                        if (!string.IsNullOrEmpty(m.Error)) evs.Add(new Ev { Time = m.Time, Icon = "exclamationmark.triangle.fill", Kind = "ERROR", Text = Short(m.Error), Color = Color.FromRgb(255, 69, 58) });
                        if (!string.IsNullOrEmpty(m.PlanState)) evs.Add(new Ev { Time = m.Time, Icon = "list.bullet.clipboard", Kind = "PLAN", Text = "Plan " + m.PlanState, Color = Color.FromRgb(255, 159, 10) });
                    }
                }
            evs = evs.OrderByDescending(e => e.Time).ToList();
            var head = V.H(10, Sym.Icon("airplane.circle", 16, t.Accent), V.VLead(2, V.T("Flight Recorder", 15, FontWeights.SemiBold, t.Primary),
                V.T(evs.Count + " events · Session " + (s != null ? s.Id.Substring(0, Math.Min(8, s.Id.Length)) : "—"), 10.5, FontWeights.Normal, t.Secondary)), V.Sp(),
                V.Box(V.H(4, V.Dot(6, Theme.B(Color.FromRgb(255, 69, 58))), V.Mono("REC", 9.5, FontWeights.Bold, t.Secondary)), V.P(6, 2), t.P(0.05), 4));
            var list = V.VLead(4); list.Align = Cross.Stretch;
            if (evs.Count == 0) list.Children.Add(PanelUI.Empty("airplane.circle", "No audit events recorded", "Events will appear as the AI agent operates."));
            foreach (var e in evs)
            {
                var c = V.VLead(2, V.H(8, V.Box(V.Mono(e.Kind, 8.5, FontWeights.Bold, Theme.B(e.Color)), V.P(5, 1.5), Theme.B(Theme.WithAlpha(e.Color, 0.12)), 3.5), V.Shrink(V.T(e.Text, 12, FontWeights.Normal, t.P(0.92))), V.Sp(), V.Mono(e.Time.ToString("HH:mm:ss", CultureInfo.InvariantCulture), 10, FontWeights.Normal, t.S(0.6))));
                if (e.Detail != null) { var d = V.Mono(e.Detail, 10, FontWeights.Normal, t.S(0.65)); d.TextTrimming = TextTrimming.CharacterEllipsis; c.Children.Add(d); }
                c.Align = Cross.Stretch;
                list.Children.Add(V.Self(V.Box(V.H(10, V.Self(Sym.Icon(e.Icon, 12, Theme.B(e.Color)), Cross.Start), V.Flex(c)), V.P(10, 7), t.P(0.025), 6), Cross.Stretch));
            }
            var col = V.VLead(14, V.Self(head, Cross.Stretch), list); col.Align = Cross.Stretch;
            Child = new ScrollViewer { Content = new Border { Child = col, Padding = new Thickness(18, 14, 18, 24) }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        }

        static string Short(string s) { s = (s ?? "").Replace("\r", "").Replace("\n", " ").Trim(); return s.Length > 120 ? s.Substring(0, 120) + "…" : s; }
    }
}
