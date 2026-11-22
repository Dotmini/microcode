// Port of Notebook/CellAIAgentEngine.swift (sub-agent roles, Agent/Ask switch, model & role pill, tool-step timeline,
// CellAgentCoordinator with the cell_* tools) and Notebook/NotebookAIPanel.swift (the right-hand Notebook Agent panel).
// The agent loop is the main Agent's AgentRunner; Cell Mode only adds its six notebook tools through AgentRunner.RunWithTools.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
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
    public class CellRole
    {
        public string Id, Name, Badge, Icon, Prompt;
    }

    public static class NbAgent
    {
        /// <summary>CellSubAgentRole (the Embedded & HIL role is left out: Embedded Studio and its embedded_* tools are not part of the Windows port).</summary>
        public static readonly CellRole[] Roles =
        {
            new CellRole { Id = "data_scientist", Name = "Notebook & Data Scientist", Badge = "Data Science", Icon = "chart.xyaxis.line", Prompt = "Act as a Principal Data Scientist & Polyglot Notebook Architect. Design clean reproducible pipelines across Python, R, Julia, SQL, Rust, Go, C++, Ardium, and LaTeX cells, inspect outputs/dataframes, generate publication-quality visualizations, and verify cell execution results." },
            new CellRole { Id = "main", Name = "Full OS & Workspace Agent", Badge = "Main Agent", Icon = "cpu.fill", Prompt = "Act as MicroCode Full OS & Workspace Autonomous Agent. Inspect, create, update, and run notebook cells as well as workspace files, shell commands, and MCP integrations to accomplish the user's goal end-to-end." },
            new CellRole { Id = "architect", Name = "System Architect", Badge = "Architect", Icon = "square.stack.3d.up.fill", Prompt = "Act as a Principal Software & Data Architect. Analyze dependencies, structure clean multi-cell modular workflows, and establish clear contracts." },
            new CellRole { Id = "bug_hunter", Name = "Bug Hunter & Auto-Healer", Badge = "Bug Hunter", Icon = "ladybug.fill", Prompt = "Act as an Autonomous Debugger & Self-Healer. Diagnose tracebacks, compiler/runtime errors, and broken imports, patch cells or files surgically, and re-run to verify zero errors." },
            new CellRole { Id = "backend_engineer", Name = "Backend & SQL Engineer", Badge = "Backend", Icon = "server.rack", Prompt = "Act as a Senior Backend, Systems & SQL Engineer. Optimize queries, data pipelines, Rust/Go/C++/Python performance, and API integrations." },
            new CellRole { Id = "frontend_engineer", Name = "Visualization & UI Specialist", Badge = "Viz / UI", Icon = "paintbrush.pointed.fill", Prompt = "Act as a Visualization & Interactive UI Specialist. Build clear charts, dashboards, HTML/LaTeX reports, and polished interfaces." },
            new CellRole { Id = "test_runner", Name = "Verification & Test Runner", Badge = "Verifier", Icon = "checkmark.seal.fill", Prompt = "Act as a QA & Reproducibility Verifier. Execute cells, validate assertions, check edge cases/NaNs, and confirm deterministic outputs." },
            new CellRole { Id = "security_auditor", Name = "Security & Perf Auditor", Badge = "Auditor", Icon = "lock.shield.fill", Prompt = "Act as a Security & Performance Auditor. Audit code and queries for vulnerabilities, credential leaks, memory bottlenecks, and O(N^2) traps." },
            new CellRole { Id = "autonomous_loop", Name = "Autonomous Build-Run-Fix Loop", Badge = "Auto-Loop", Icon = "arrow.triangle.2.circlepath.circle.fill", Prompt = "Act as an Autonomous Run-Analyze-Fix Agent. Iteratively write, execute, inspect outputs, and repair cells or files until execution succeeds cleanly." }
        };

        public static CellRole Role(string id) { return Roles.FirstOrDefault(r => r.Id == id) ?? Roles[0]; }

        static readonly Dictionary<string, CancellationTokenSource> Sessions = new Dictionary<string, CancellationTokenSource>();
        public static bool IsRunning(string session) { lock (Sessions) return Sessions.ContainsKey(session); }
        public static void Stop(string session)
        {
            CancellationTokenSource cts;
            lock (Sessions) { if (Sessions.TryGetValue(session, out cts)) Sessions.Remove(session); }
            if (cts != null) { try { cts.Cancel(); } catch (ObjectDisposedException) { } }
        }

        static string Fence(NbCell c) { return c.Lang.Ext.ToLowerInvariant() == "r" ? "R" : c.Lang.Ext; }

        /// <summary>buildNotebookContextSnapshot.</summary>
        public static string NotebookSnapshot(NotebookView nb)
        {
            var doc = nb.Doc;
            var sb = new StringBuilder("## Active Notebook: " + doc.Name + "\n");
            sb.Append("- Working Directory: `" + NbStore.WorkingDirectory + "`\n");
            sb.Append("- Total Cells: " + doc.Cells.Count + "\n");
            if (doc.Files.Count > 0) sb.Append("- Attached Datasets: " + string.Join(", ", doc.Files.Select(f => f.Name + " (" + NbFmt.Bytes(f.Size) + ", path: " + f.Path + ")")) + "\n");
            sb.Append("\n");
            for (int i = 0; i < doc.Cells.Count; i++)
            {
                var c = doc.Cells[i];
                sb.Append("### Cell #" + (i + 1) + " (id: `" + c.Id + "`, type: " + c.Type + ", lang: " + c.Language + ")" + (c.Id == nb.SelectedId ? " [SELECTED]" : "") + ((c.Tag ?? "").Length > 0 ? " [tag: " + c.Tag + "]" : "") + "\n");
                string code = c.Content.Length > 2200 ? c.Content.Substring(0, 2200) + "\n... (truncated)" : c.Content;
                sb.Append("```" + Fence(c) + "\n" + code + "\n```\n");
                if ((c.Output ?? "").Length > 0) sb.Append("Output:\n```\n" + (c.Output.Length > 1200 ? c.Output.Substring(0, 1200) + "\n... (truncated)" : c.Output) + "\n```\n");
                if (c.Images.Count > 0) sb.Append("Generated Images/Plots: " + string.Join(", ", c.Images.Select(Path.GetFileName)) + "\n");
                sb.Append("\n");
            }
            return sb.ToString();
        }

        public static string SystemPrompt(CellRole role, bool agentMode, string workspaceRoot, string context)
        {
            if (agentMode)
                return "You are MicroCode Cell Mode Autonomous Agent (" + role.Name + ").\n" + role.Prompt + "\n\n## Environment & Capabilities\n- Working Directory: `" + workspaceRoot + "`\n- Operating system: Windows (cmd.exe for the shell tool).\n- Supported Cell Languages: Python, R, Julia, SQL, Rust, Go, C++, Java, C#, R Markdown, LaTeX, Markdown (Ardium and Objective-C cells only run on the Mac).\n" +
                       "- You have direct access to **Notebook Cell Tools**:\n  - `cell_list`: List all cells and attached datasets in the active notebook.\n  - `cell_read`: Read the full code, output, and plot paths of any cell (`cell_number` 1-based or `cell_id`).\n  - `cell_create`: Create a new cell (`type`: `code`/`markdown`/`raw`, `language`, `code`, optional `after_cell_number`, optional `auto_run`: true).\n  - `cell_update`: Modify an existing cell's `code`, `language`, or `tag` (`cell_number` 1-based, optional `auto_run`: true).\n  - `cell_run`: Execute an existing cell in the live Notebook (`cell_number` 1-based) or run a standalone code snippet (`code` + `language`) and inspect real stdout/stderr/plots.\n  - `cell_delete`: Delete a cell by `cell_number`.\n" +
                       "- You ALSO have the **Workspace & OS Tools** (`file_read`, `file_write`, `replace_in_file`, `list_directory_tree`, `grep_search`, `file_search`, `shell`).\n\n## Execution Rules\n1. When asked to build, analyze, plot, debug, or run cells, **use `cell_create` / `cell_update` / `cell_run` proactively** and verify the real execution output!\n2. If a cell execution fails with a traceback, inspect the error, fix the cell with `cell_update`, and re-run with `cell_run` until it succeeds.\n3. Never overwrite unrelated user cells unless asked to edit that specific cell; prefer `cell_create` to add new pipeline steps cleanly.\n4. Respond in Thai when the user writes in Thai, and in English when the user writes in English. Keep summaries concise and technical.\n\n" + context;
            return "You are MicroCode Cell Mode AI Assistant (" + role.Name + ") in **Ask Mode (Read-Only)**.\n" + role.Prompt + "\n\n## Rules\n1. You see all cells, languages, datasets, and outputs in the current notebook below.\n2. Wrap runnable code inside fenced markdown blocks with the exact language tag (e.g. ```python, ```r, ```sql, ```rust, ```go, ```cpp, ```latex) so the user can 1-click Insert or Apply it to a cell.\n3. Specify which cell number a fix applies to when debugging errors.\n4. Respond in Thai when the user writes in Thai, and in English when the user writes in English. Be concise and direct.\n\n" + context;
        }

        /// <summary>splitThoughtAndVisibleText: &lt;think&gt;/&lt;thought&gt; blocks (closed or still streaming) become the reasoning trace.</summary>
        public static string SplitThought(string raw, out string thought)
        {
            var thoughts = new List<string>();
            string text = Regex.Replace(raw ?? "", @"<(?:thought|think)>([\s\S]*?)</(?:thought|think)>", m => { string inner = m.Groups[1].Value.Trim(); if (inner.Length > 0) thoughts.Add(inner); return ""; }, RegexOptions.IgnoreCase);
            var open = Regex.Match(text, @"<(?:thought|think)>", RegexOptions.IgnoreCase);
            if (open.Success)
            {
                string trailing = text.Substring(open.Index + open.Length).Trim();
                if (trailing.Length > 0) thoughts.Add(trailing);
                text = text.Substring(0, open.Index);
            }
            thought = string.Join("\n\n", thoughts);
            return text.Trim();
        }

        public class Callbacks
        {
            public Action<string> Status, Thought, Text, Complete, Error;
            public Action<List<CellToolStep>> Steps;
            public Action Cancelled;
            public Func<ToolStep, Dictionary<string, object>, Task<bool>> Approve;
        }

        /// <summary>CellAgentCoordinator.startExecution: Agent mode runs the shared tool loop with the cell tools added; Ask mode is a
        /// single read-only reply. Callbacks arrive on the UI thread.</summary>
        public static void Start(string session, string prompt, string roleId, bool agentMode, string context, List<ChatMessage> history, Callbacks cb)
        {
            Stop(session);
            var disp = Application.Current.Dispatcher;
            if (!AIConfig.IsConfigured) { disp.BeginInvoke(new Action(() => cb.Error(AIClient.NotConnectedText()))); return; }
            var cts = new CancellationTokenSource();
            lock (Sessions) Sessions[session] = cts;
            string ws = AppState.Shared != null && AppState.Shared.WorkspaceFolder != null ? AppState.Shared.WorkspaceFolder : NbStore.WorkingDirectory;
            string system = SystemPrompt(Role(roleId), agentMode, ws, context);
            var msgs = new List<ChatMessage>(history ?? new List<ChatMessage>()) { new ChatMessage { Role = "user", Content = prompt } };
            var text = new StringBuilder();
            var reasoning = new StringBuilder();
            var steps = new List<CellToolStep>();
            var map = new Dictionary<ToolStep, CellToolStep>();
            bool pending = false;
            Action emit = () =>
            {
                if (pending) return;
                pending = true;
                disp.BeginInvoke(new Action(() =>
                {
                    pending = false;
                    string th; string all; lock (text) all = text.ToString();
                    string visible = SplitThought(all, out th);
                    string r; lock (reasoning) r = reasoning.ToString();
                    string merged = (r.Trim() + (r.Trim().Length > 0 && th.Length > 0 ? "\n\n" : "") + th).Trim();
                    if (merged.Length > 0 && cb.Thought != null) cb.Thought(merged);
                    if (cb.Text != null) cb.Text(visible);
                }), DispatcherPriority.Background);
            };
            Func<List<CellToolStep>> snapshot = () => steps.Select(s => new CellToolStep { Id = s.Id, ToolName = s.ToolName, Summary = s.Summary, Output = s.Output, IsRunning = s.IsRunning, IsError = s.IsError, StartedAt = s.StartedAt, DurationMs = s.DurationMs }).ToList();
            var acb = new AgentCallbacks
            {
                OnText = d => { lock (text) text.Append(d); emit(); },
                OnThinking = d => { lock (reasoning) reasoning.Append(d); emit(); },
                OnActivity = s => disp.BeginInvoke(new Action(() => { if (cb.Status != null) cb.Status(s); })),
                OnStepStart = st => disp.BeginInvoke(new Action(() =>
                {
                    var cs = new CellToolStep { ToolName = st.Name, Summary = st.Target == "." ? "" : st.Target ?? "", IsRunning = true, StartedAt = DateTime.Now };
                    map[st] = cs; steps.Add(cs);
                    if (cb.Steps != null) cb.Steps(snapshot());
                    if (cb.Status != null) cb.Status("Executing " + st.Name + "…");
                })),
                OnStep = st => disp.BeginInvoke(new Action(() =>
                {
                    CellToolStep cs;
                    if (!map.TryGetValue(st, out cs)) { cs = new CellToolStep { ToolName = st.Name, Summary = st.Target ?? "", StartedAt = st.Time }; steps.Add(cs); }
                    cs.IsRunning = false; cs.IsError = !st.Ok; cs.Output = st.Result ?? "";
                    cs.DurationMs = Math.Max(1, (int)(DateTime.Now - cs.StartedAt).TotalMilliseconds);
                    if (cb.Steps != null) cb.Steps(snapshot());
                })),
                Approve = cb.Approve
            };
            if (cb.Status != null) cb.Status(agentMode ? "Agent analyzing cells…" : "Generating…");
            Task<AgentResult> run = agentMode
                ? AgentRunner.RunWithTools(CellTools.Extension, msgs, system, false, session, acb, cts.Token)
                : AgentRunner.Run(msgs, system, false, true, session, acb, cts.Token);
            run.ContinueWith(tk => disp.BeginInvoke(new Action(() =>
            {
                bool mine; lock (Sessions) { CancellationTokenSource cur; mine = Sessions.TryGetValue(session, out cur) && cur == cts; if (mine) Sessions.Remove(session); }
                if (tk.IsCanceled || cts.IsCancellationRequested || (tk.IsFaulted && tk.Exception.GetBaseException() is OperationCanceledException))
                {
                    if (cb.Cancelled != null) cb.Cancelled();
                    return;
                }
                string th; string all; lock (text) all = text.ToString();
                string visible = SplitThought(all, out th);
                if (tk.IsFaulted) { cb.Error(AIException.Describe(tk.Exception, AIConfig.Mode == "cloud")); return; }
                string final = visible.Length > 0 ? visible : SplitThought(tk.Result.Text ?? "", out th);
                cb.Complete(final);
            })));
        }

        /// <summary>One-shot Ask-mode request (CellSelfHealingBanner auto-fix).</summary>
        public static void Ask(string session, string prompt, string roleId, Action<string> onStatus, Action<string, string> onDone)
        {
            Start(session, prompt, roleId, false, "", null, new Callbacks
            {
                Status = onStatus, Text = t => { },
                Complete = t => onDone(t, null), Error = e => onDone(null, e), Cancelled = () => onDone(null, "Cancelled")
            });
        }

        /// <summary>executeAgentCellAsync: an inline AI Agent cell runs its prompt and streams thought / tool steps / answer into the cell.</summary>
        public static void RunAgentCell(NotebookView nb, NbCell cell, Action<bool> done)
        {
            string prompt = (cell.Content ?? "").Trim();
            if (prompt.Length == 0) { done(true); return; }
            string session = "agent-cell-" + cell.Id;
            var t0 = DateTime.Now;
            cell.AgentStatus = cell.AgentMode ? "Agent inspecting notebook…" : "Generating…";
            cell.AgentThought = ""; cell.AgentSteps = new List<CellToolStep>();
            nb.RefreshCell(cell);
            Action<bool> finish = ok =>
            {
                cell.AgentStatus = "";
                cell.Telemetry = new CellTelemetry { DurationMs = (DateTime.Now - t0).TotalMilliseconds };
                nb.TotalExec++; cell.ExecCount = nb.TotalExec; nb.Epoch++; cell.LastRunEpoch = nb.Epoch;
                done(ok);
            };
            Start(session, prompt, cell.AiRole, cell.AgentMode, NotebookSnapshot(nb), null, new Callbacks
            {
                Status = s => { cell.AgentStatus = s; nb.RefreshCellLive(cell); },
                Thought = th => { cell.AgentThought = th; nb.RefreshCellLive(cell); },
                Text = tx => { cell.Output = tx; nb.RefreshCellLive(cell); },
                Steps = st => { cell.AgentSteps = st; nb.RefreshCellLive(cell); },
                Complete = final =>
                {
                    if ((cell.Output ?? "").Length == 0 && final.Length > 0) cell.Output = final;
                    else if ((cell.Output ?? "").Length == 0 && cell.AgentSteps.Count > 0) cell.Output = "ดำเนินการเสร็จเรียบร้อย (" + cell.AgentSteps.Count + " tool steps)";
                    finish(true);
                },
                Error = e => { cell.Output = ((cell.Output ?? "").Length == 0 ? "" : cell.Output + "\n\n") + "⚠️ " + e; finish(false); },
                Cancelled = () => { cell.AgentStatus = ""; done(true); },
                Approve = (step, args) => nb.ApproveTool(step, args)
            });
        }
    }

    /// <summary>The six Cell Mode notebook tools (AgentToolBox: CellListTool … CellRunTool), executed against the visible notebook.</summary>
    public static class CellTools
    {
        static Dictionary<string, object> P(string type, string desc) { return new Dictionary<string, object> { { "type", type }, { "description", desc } }; }
        static Dictionary<string, object> Tool(string name, string desc, Dictionary<string, object> props, params string[] required)
        {
            return new Dictionary<string, object> { { "name", name }, { "description", desc }, { "parameters", new Dictionary<string, object> { { "type", "object" }, { "properties", props }, { "required", required } } } };
        }

        public static readonly ToolExtension Extension = new ToolExtension
        {
            Schemas = new List<Dictionary<string, object>>
            {
                Tool("cell_list", "List all cells, languages, tags, execution counts, output previews, and attached data files in the active Cell Mode notebook.", new Dictionary<string, object>()),
                Tool("cell_read", "Read the complete source code, stdout/stderr output, and generated plot paths of a notebook cell by 1-based cell_number or cell_id.",
                    new Dictionary<string, object> { { "cell_number", P("integer", "1-based cell number to inspect (e.g. 1 for first cell)") }, { "cell_id", P("string", "Optional UUID of the cell") } }),
                Tool("cell_create", "Create a new cell in the active Cell Mode notebook with code or markdown, optional position, and optional immediate execution.",
                    new Dictionary<string, object> { { "code", P("string", "Source code or markdown content for the new cell") }, { "language", P("string", "Cell language (python, r, julia, sql, rust, go, cpp, java, csharp, rmarkdown, latex)") },
                        { "type", P("string", "Cell type: 'code' (default), 'markdown', 'raw', or 'agent'") }, { "after_cell_number", P("integer", "Insert after this 1-based cell number (0 inserts at top; omit to append at end)") },
                        { "tag", P("string", "Optional tag label for selective execution") }, { "auto_run", P("boolean", "If true, immediately execute the newly created code cell and return its output") } }, "code"),
                Tool("cell_update", "Update an existing notebook cell's code/content, language, or tag by 1-based cell_number or cell_id, with optional immediate execution.",
                    new Dictionary<string, object> { { "cell_number", P("integer", "1-based cell number to update") }, { "cell_id", P("string", "Optional UUID of the cell to update") }, { "code", P("string", "Updated code or markdown content") },
                        { "language", P("string", "Optional updated cell language") }, { "tag", P("string", "Optional updated cell tag") }, { "auto_run", P("boolean", "If true, immediately execute the cell after updating") } }, "code"),
                Tool("cell_delete", "Delete a cell from the active Cell Mode notebook by 1-based cell_number or cell_id.",
                    new Dictionary<string, object> { { "cell_number", P("integer", "1-based cell number to delete") }, { "cell_id", P("string", "Optional UUID of the cell to delete") } }),
                Tool("cell_run", "Execute an existing notebook cell in Cell Mode by 1-based cell_number or cell_id (updating live Notebook output & plots), OR run a standalone code snippet if code + language are provided.",
                    new Dictionary<string, object> { { "cell_number", P("integer", "1-based cell number in the active notebook to execute") }, { "cell_id", P("string", "Optional UUID of the notebook cell to execute") },
                        { "code", P("string", "Optional standalone source code (or updated code if cell_number is also provided)") }, { "language", P("string", "Language when running standalone code (e.g. python, r, julia, sql, rust, go, cpp)") } })
            },
            Execute = Execute,
            Target = Summary
        };

        static readonly HashSet<string> Names = new HashSet<string> { "cell_list", "cell_read", "cell_create", "cell_update", "cell_delete", "cell_run" };

        /// <summary>summarizeToolArgs.</summary>
        static string Summary(string name, Dictionary<string, object> a)
        {
            if (!Names.Contains(name)) return null;
            object num, lang;
            a.TryGetValue("cell_number", out num); a.TryGetValue("language", out lang);
            if (num != null) return lang != null ? "Cell #" + num + " (" + lang + ")" : "Cell #" + num;
            if (lang != null) return Convert.ToString(lang);
            return "";
        }

        static int? Int(object v)
        {
            if (v == null) return null;
            try { return Convert.ToInt32(v, System.Globalization.CultureInfo.InvariantCulture); }
            catch (FormatException) { int i; return int.TryParse(Convert.ToString(v).Trim(), out i) ? (int?)i : null; }
        }
        static bool Bool(object v)
        {
            if (v is bool) return (bool)v;
            var s = Convert.ToString(v ?? "").Trim().ToLowerInvariant();
            return s == "true" || s == "1" || s == "yes";
        }
        static string Str(Dictionary<string, object> a, string k) { object v; return a.TryGetValue(k, out v) && v != null ? Convert.ToString(v) : null; }

        static T Ui<T>(Func<T> f) { return Application.Current.Dispatcher.Invoke(f); }

        static NotebookView View
        {
            get
            {
                var nb = NotebookView.Current;
                if (nb == null) throw new InvalidOperationException("Cell Mode is not open. Switch to Cell Mode (Notebook) first.");
                return nb;
            }
        }

        static NbCell Resolve(NotebookView nb, Dictionary<string, object> a, out int index)
        {
            var cells = nb.Doc.Cells;
            string id = Str(a, "cell_id");
            index = -1;
            if (!string.IsNullOrWhiteSpace(id)) { index = cells.FindIndex(c => string.Equals(c.Id, id.Trim(), StringComparison.OrdinalIgnoreCase)); if (index >= 0) return cells[index]; }
            object raw; a.TryGetValue("cell_number", out raw); if (raw == null) a.TryGetValue("index", out raw);
            int? n = Int(raw);
            if (n.HasValue && n.Value >= 1 && n.Value <= cells.Count) { index = n.Value - 1; return cells[index]; }
            return null;
        }

        static string Execute(string name, Dictionary<string, object> a, ToolStep step, CancellationToken ct)
        {
            if (!Names.Contains(name)) return null;
            try
            {
                switch (name)
                {
                    case "cell_list": return Ui(() => List(View));
                    case "cell_read": return Ui(() => Read(View, a));
                    case "cell_create": return Create(a, ct);
                    case "cell_update": return Update(a, ct);
                    case "cell_delete": return Ui(() => Delete(View, a));
                    default: return RunTool(a, ct);
                }
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex) { return "Error: " + (ex is InvalidOperationException || ex is ArgumentException ? ex.Message : ex.GetType().Name + ": " + ex.Message); }
        }

        static string List(NotebookView nb)
        {
            var d = nb.Doc;
            var lines = new List<string> { "Notebook: " + d.Name + " (" + d.Cells.Count + " cells, cwd: " + NbStore.WorkingDirectory + ")" };
            if (d.Files.Count > 0) lines.Add("Attached Datasets: " + string.Join(", ", d.Files.Select(f => f.Name + " (" + f.Path + ")")));
            for (int i = 0; i < d.Cells.Count; i++)
            {
                var c = d.Cells[i];
                string first = (c.Content ?? "").Split('\n')[0];
                lines.Add("Cell #" + (i + 1) + " (id:" + c.Id + ") | " + c.Type + " | " + c.Language + " | " + (c.ExecCount > 0 ? "#" + c.ExecCount : "unrun") + " | " + ((c.Output ?? "").Length == 0 ? "no-output" : "output:" + c.Output.Length + "chars") +
                          (c.Id == nb.SelectedId ? " [SELECTED]" : "") + ((c.Tag ?? "").Length > 0 ? " [tag:" + c.Tag + "]" : "") + " | " + (first.Length > 70 ? first.Substring(0, 70) : first));
            }
            return string.Join("\n", lines);
        }

        static string Read(NotebookView nb, Dictionary<string, object> a)
        {
            int idx; var c = Resolve(nb, a, out idx);
            if (c == null) throw new ArgumentException("Valid cell_number (1..." + nb.Doc.Cells.Count + ") or cell_id is required.");
            var sb = new StringBuilder("Cell #" + (idx + 1) + " (id: " + c.Id + ")\n");
            sb.Append("Type: " + c.Type + " | Language: " + c.Language + " | Tag: " + ((c.Tag ?? "").Length == 0 ? "(none)" : c.Tag) + "\n");
            sb.Append("Code:\n```" + c.Lang.Ext + "\n" + c.Content + "\n```\n");
            sb.Append((c.Output ?? "").Length > 0 ? "Output:\n```\n" + c.Output + "\n```\n" : "Output: (none)\n");
            if (c.Images.Count > 0) sb.Append("Images: " + string.Join(", ", c.Images) + "\n");
            return sb.ToString();
        }

        static string TypeOf(string raw)
        {
            switch ((raw ?? "code").ToLowerInvariant()) { case "markdown": case "md": return "Markdown"; case "raw": return "Raw"; case "agent": case "ai": return "Agent"; default: return "Code"; }
        }

        static string Create(Dictionary<string, object> a, CancellationToken ct)
        {
            string code = Str(a, "code") ?? Str(a, "content") ?? "";
            bool autoRun = Bool(a.ContainsKey("auto_run") ? a["auto_run"] : null);
            var created = Ui(() =>
            {
                var nb = View; var d = nb.Doc;
                string type = TypeOf(Str(a, "type"));
                var lang = CellLang.FromFence(Str(a, "language") ?? "python") ?? CellLang.Get("Python");
                var c = NbCell.Create(type, lang.Name, code);
                if (type == "Code" && code.Length == 0) c.Content = "";
                c.Tag = Str(a, "tag") ?? "";
                int? after = Int(a.ContainsKey("after_cell_number") ? a["after_cell_number"] : null);
                int at = after.HasValue ? Math.Max(0, Math.Min(after.Value, d.Cells.Count)) : d.Cells.Count;
                d.Cells.Insert(at, c);
                nb.SelectedId = c.Id; d.ModifiedAt = DateTime.Now;
                nb.SaveSoon(); nb.RenderCells(); nb.RenderToolbar();
                if (autoRun && (c.IsCode || c.IsAgent)) nb.RunCell(c);
                return Tuple.Create(c, at + 1);
            });
            if (autoRun) return "Created Cell #" + created.Item2 + " and executed:\n" + Wait(created.Item1, created.Item2, ct);
            return "Created Cell #" + created.Item2 + " (id: " + created.Item1.Id + ", language: " + created.Item1.Language + ").";
        }

        static string Update(Dictionary<string, object> a, CancellationToken ct)
        {
            string code = Str(a, "code") ?? Str(a, "content");
            if (code == null) throw new ArgumentException("code is required");
            bool autoRun = Bool(a.ContainsKey("auto_run") ? a["auto_run"] : null);
            var target = Ui(() =>
            {
                var nb = View;
                int idx; var c = Resolve(nb, a, out idx);
                if (c == null) throw new ArgumentException("Valid cell_number (1..." + nb.Doc.Cells.Count + ") or cell_id is required.");
                c.RecordAgentEditBaseline(c.Content, "AI Agent");
                c.Content = code;
                var lang = CellLang.FromFence(Str(a, "language") ?? ""); if (lang != null) c.Language = lang.Name;
                string tag = Str(a, "tag"); if (tag != null) c.Tag = tag;
                nb.SelectedId = c.Id; nb.Doc.ModifiedAt = DateTime.Now;
                nb.SaveSoon(); nb.RefreshEditor(c); nb.RenderCells();
                if (autoRun && (c.IsCode || c.IsAgent)) nb.RunCell(c);
                return Tuple.Create(c, idx + 1);
            });
            if (autoRun) return "Updated Cell #" + target.Item2 + " and executed:\n" + Wait(target.Item1, target.Item2, ct);
            return "Updated Cell #" + target.Item2 + " (language: " + target.Item1.Language + ").";
        }

        static string Delete(NotebookView nb, Dictionary<string, object> a)
        {
            int idx; var c = Resolve(nb, a, out idx);
            if (c == null) throw new ArgumentException("Valid cell_number (1..." + nb.Doc.Cells.Count + ") or cell_id is required.");
            nb.DeleteCell(c);
            return "Deleted Cell #" + (idx + 1) + ". Remaining cells: " + nb.Doc.Cells.Count + ".";
        }

        static string RunTool(Dictionary<string, object> a, CancellationToken ct)
        {
            bool hasCell = a.ContainsKey("cell_number") || a.ContainsKey("cell_id") || a.ContainsKey("index");
            if (hasCell)
            {
                var target = Ui(() =>
                {
                    var nb = View;
                    int idx; var c = Resolve(nb, a, out idx);
                    if (c == null) throw new ArgumentException("Valid cell_number (1..." + nb.Doc.Cells.Count + ") or cell_id is required.");
                    string code = Str(a, "code");
                    if (!string.IsNullOrEmpty(code)) { c.Content = code; nb.RefreshEditor(c); }
                    var lang = CellLang.FromFence(Str(a, "language") ?? ""); if (lang != null) c.Language = lang.Name;
                    nb.SelectedId = c.Id;
                    nb.RunCell(c);
                    return Tuple.Create(c, idx + 1);
                });
                return Wait(target.Item1, target.Item2, ct);
            }
            return Snippet(Str(a, "code") ?? "", Str(a, "language") ?? "python", ct);
        }

        /// <summary>NotebookToolHelper.waitForCellExecution (120 s) and its report.</summary>
        static string Wait(NbCell c, int number, CancellationToken ct)
        {
            var deadline = DateTime.Now.AddSeconds(120);
            while (DateTime.Now < deadline)
            {
                ct.ThrowIfCancellationRequested();
                bool running = Ui(() => c.IsExecuting || c.IsQueued);
                if (!running) break;
                Thread.Sleep(120);
            }
            return Ui(() =>
            {
                var sb = new StringBuilder("Cell #" + number + " " + (c.ExecCount > 0 ? "[" + c.ExecCount + "]" : "[*]") + " (" + c.Language + ") finished" + (c.Telemetry != null ? " in " + c.Telemetry.FormattedDuration : "") + ".\n");
                if (c.IsExecuting || c.IsQueued) sb.Append("Status: Still running/queued in background after 120s.\n");
                sb.Append((c.Output ?? "").Length > 0 ? "Output:\n" + (c.Output.Length > 6000 ? c.Output.Substring(0, 6000) + "\n... (truncated)" : c.Output) + "\n" : "Output: (empty stdout)\n");
                if (c.DataFrame != null) sb.Append("Inline DataFrame `" + c.DataFrame.VariableName + "` (" + c.DataFrame.TotalRows + " × " + c.DataFrame.TotalCols + ") — columns: " + string.Join(", ", c.DataFrame.Columns.Take(20)) + "\n");
                if (c.Images.Count > 0) sb.Append("Generated plots/artifacts: " + string.Join(", ", c.Images) + "\n");
                return sb.ToString();
            });
        }

        /// <summary>playground_run equivalent: a standalone snippet in a fresh process (the notebook kernel's state is left alone).</summary>
        static string Snippet(string code, string language, CancellationToken ct)
        {
            if (code.Trim().Length == 0) throw new ArgumentException("code is required when no cell_number is given");
            var lang = CellLang.FromFence(language) ?? CellLang.Get("Python");
            string dir = Path.Combine(Path.GetTempPath(), "MicroCodeCells", "snippet_" + Guid.NewGuid().ToString("N").Substring(0, 8));
            Directory.CreateDirectory(dir);
            try
            {
                string key = lang.Name == "C++" ? "cpp" : lang.Name == "C#" ? "csharp" : lang.Name.ToLowerInvariant();
                string file = Path.Combine(dir, (lang.Name == "Java" ? "Main" : "snippet") + "." + lang.Ext);
                File.WriteAllText(file, code, new UTF8Encoding(false));
                string exe, args;
                if (!Runner.CommandFor(key, file, out exe, out args)) return "Error: no local runtime is configured for " + lang.Name + " on Windows.";
                var psi = new ProcessStartInfo(exe, args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, WorkingDirectory = dir, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
                psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
                using (var p = Process.Start(psi))
                {
                    var o = p.StandardOutput.ReadToEndAsync(); var e = p.StandardError.ReadToEndAsync();
                    var sw = Stopwatch.StartNew();
                    while (!p.WaitForExit(200)) { if (ct.IsCancellationRequested || sw.Elapsed.TotalSeconds > 120) { try { p.Kill(); } catch (InvalidOperationException) { } break; } }
                    p.WaitForExit();
                    string outText = o.Result + (e.Result.Length > 0 ? (o.Result.Length > 0 ? "\n" : "") + e.Result : "");
                    return "Exit code " + p.ExitCode + " (" + lang.Name + ", " + sw.ElapsedMilliseconds + " ms)\n" + (outText.Length > 8000 ? outText.Substring(0, 8000) + "\n... (truncated)" : outText);
                }
            }
            catch (System.ComponentModel.Win32Exception ex) { return "Error: the " + lang.Name + " toolchain is not installed (" + ex.Message + ")."; }
            finally { try { Directory.Delete(dir, true); } catch (Exception ex) { Debug.WriteLine("snippet cleanup: " + ex.Message); } }
        }
    }

    /// <summary>Shared Cell Mode AI chrome: Agent/Ask switch, model & role pill, send button, prompt composer, thought block,
    /// tool-step timeline and rich answer renderer with 1-click cell actions.</summary>
    public static class NbAgentUI
    {
        static Theme T { get { return Theme.Current; } }

        /// <summary>CellModeTogglePill.</summary>
        public static UIElement ModeToggle(Func<bool> get, Action<bool> set, bool compact)
        {
            var t = T; bool d = t.IsDark;
            var row = V.H(1);
            Func<string, bool, Btn> seg = (title, isAgent) =>
            {
                bool sel = get() == isAgent;
                var b = V.Button(V.Box(V.T(title, compact ? 10 : 10.5, sel ? FontWeights.SemiBold : FontWeights.Normal, sel ? t.Primary : t.Secondary), compact ? V.P(6.5, 2) : V.P(8, 3), sel ? t.P(d ? 0.13 : 0.09) : Brushes.Transparent, 3.5), () => set(isAgent));
                return b;
            };
            row.Children.Add(seg("Agent", true));
            row.Children.Add(seg("Ask", false));
            var box = V.Box(row, V.P(2), t.P(d ? 0.06 : 0.045), 5, t.P(d ? 0.11 : 0.08), 0.8);
            box.VerticalAlignment = VerticalAlignment.Center;
            box.ToolTip = get() ? "Agent Mode: Autonomous tool calling (inspect, create, edit & execute cells and workspace files)" : "Ask Mode: Read-only Q&A and code generation without auto-mutating cells";
            return box;
        }

        public static UIElement ModelPill(AppState app, double maxWidth, bool compact, bool minimal, Func<string> role)
        {
            return ModelPill(app, maxWidth, compact, minimal, role, null, false);
        }

        /// <summary>CellAIModelSelectorPill: the global model (same menu as the Agent composer) plus an optional specialist-role menu.</summary>
        public static UIElement ModelPill(AppState app, double maxWidth, bool compact, bool minimal, Func<string> role, Action<string> setRole, bool roleIconOnly)
        {
            var t = T; bool d = t.IsDark;
            Brush bg = minimal ? t.P(0.035) : t.ElevatedBackground;
            Brush stroke = t.P(minimal ? 0.06 : d ? 0.11 : 0.08);
            var row = V.H(4.5);
            if (!AIConfig.IsConfigured)
            {
                row.Children.Add(Sym.Icon("link.badge.plus", compact ? 9.5 : 10.5, t.Accent, FontWeights.Medium));
                row.Children.Add(V.T("Connect AI", compact ? 10 : 11, FontWeights.Medium, t.Primary));
            }
            else
            {
                row.Children.Add(Sym.Icon(AIConfig.Mode == "local" ? "desktopcomputer" : AIConfig.Mode == "cloud" ? "sparkles" : "key", compact ? 10.5 : 11.5, t.Primary));
                row.Children.Add(V.Shrink(V.T(AIConfig.ModelDisplayName, compact ? 10 : 11, FontWeights.Medium, minimal ? t.Secondary : t.P(0.9))));
            }
            row.Children.Add(Sym.Icon("chevron.down", 7.5, t.S(0.8), FontWeights.SemiBold));
            Btn model = null;
            model = V.Button(V.Box(row, compact ? V.P(6, 2.5) : V.P(7.5, 3.5), bg, 5, stroke, 0.8), () =>
            {
                if (!AIConfig.IsConfigured) { SettingsWindow.Show(app, AIConfig.Mode == "cloud" ? 6 : 2); return; }
                MacMenu.Show(model, AgentView.BuildModelMenu(app), false);
            });
            model.MaxWidth = maxWidth; model.MinWidth = 52;
            model.ToolTip = AIConfig.IsConfigured ? AIConfig.BadgeTitle + " · " + AIConfig.ModelDisplayName : AIClient.NotConnectedText();
            model.VerticalAlignment = VerticalAlignment.Center;
            if (role == null) return model;
            var r = NbAgent.Role(role());
            var rrow = V.H(3.5, Sym.Icon(r.Icon, compact ? 9 : 10, t.Secondary));
            if (!roleIconOnly) rrow.Children.Add(V.T(r.Badge, compact ? 10 : 10.5, FontWeights.Normal, t.Secondary));
            rrow.Children.Add(Sym.Icon("chevron.down", 7, t.S(0.75), FontWeights.SemiBold));
            var roleBtn = V.Button(V.Box(rrow, compact ? V.P(5.5, 2.5) : V.P(6.5, 3.5), bg, 5, stroke, 0.8), null);
            roleBtn.VerticalAlignment = VerticalAlignment.Center;
            roleBtn.ToolTip = "Specialist Role: " + r.Name;
            roleBtn.MenuItems = () =>
            {
                var items = new List<MenuItemSpec> { MenuItemSpec.Header("Specialist Role") };
                foreach (var x in NbAgent.Roles) { var rr = x; items.Add(new MenuItemSpec { Title = x.Name, Icon = x.Icon, Checked = role() == x.Id, Action = () => { if (setRole != null) setRole(rr.Id); } }); }
                return items;
            };
            return V.H(4, V.Shrink(model), roleBtn);
        }

        public static UIElement SendButton(bool running, bool canSend, bool agentMode, Action click)
        {
            var t = T;
            if (running)
            {
                var stop = V.Button(new Border { Width = 25, Height = 25, CornerRadius = new CornerRadius(12.5), Background = NbColor.Alpha(t.SysRed, 0.85), Child = Sym.Icon("stop.fill", 9.5, Brushes.White, FontWeights.Bold) }, click);
                stop.ToolTip = "Stop Agent";
                return stop;
            }
            var send = V.Button(new Border { Width = 25, Height = 25, CornerRadius = new CornerRadius(12.5), Background = canSend ? t.Accent : t.P(0.07), Child = Sym.Icon("arrow.up", 11, canSend ? Brushes.White : (Brush)t.S(0.55), FontWeights.Bold) }, canSend ? click : null);
            send.IsEnabled = canSend;
            send.ToolTip = agentMode ? "Run Agent (Enter)" : "Send (Enter)";
            return send;
        }

        /// <summary>CellPromptInputView: multi-line composer, Enter sends, Shift+Enter inserts a newline, IME-safe.</summary>
        public static Grid PromptBox(string placeholder, string text, double minH, double maxH, double fontSize, Action<string> onChange, Action onSubmit)
        {
            var t = T;
            TextBox box;
            var g = Styles.Field(placeholder, fontSize, t.Primary, t.S(0.65), out box);
            box.Text = text ?? "";
            box.AcceptsReturn = true; box.TextWrapping = TextWrapping.Wrap; box.VerticalContentAlignment = VerticalAlignment.Top;
            box.MinHeight = minH - 8; box.MaxHeight = maxH; box.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
            var ph = g.Children.OfType<TextBlock>().FirstOrDefault();
            if (ph != null) { ph.VerticalAlignment = VerticalAlignment.Top; ph.Margin = new Thickness(2, 1, 0, 0); ph.TextTrimming = TextTrimming.CharacterEllipsis; }
            box.TextChanged += delegate { if (onChange != null) onChange(box.Text); };
            box.PreviewKeyDown += (s, e) =>
            {
                if (e.Key == Key.Enter && (Keyboard.Modifiers & ModifierKeys.Shift) == 0 && !e.IsRepeat && e.ImeProcessedKey == Key.None)
                {
                    e.Handled = true;
                    if (onSubmit != null) onSubmit();
                }
            };
            g.Tag = box;
            return g;
        }

        /// <summary>AntigravityThoughtBlockView without a duration: a collapsible reasoning trace.</summary>
        public static UIElement Thought(string text)
        {
            var t = T;
            var body = V.Wrap(V.T(text.Trim(), 12, FontWeights.Normal, t.S(0.85)), TextAlignment.Left);
            var bodyBox = V.Box(body, V.P(12, 2, 0, 2), null, 0, t.P(0.15), 0);
            bodyBox.BorderThickness = new Thickness(2, 0, 0, 0);
            bodyBox.Visibility = Visibility.Collapsed;
            var chev = Sym.Icon("chevron.right", 8.5, t.S(0.6), FontWeights.SemiBold);
            var head = V.Button(V.H(5, V.T("Thought", 12, FontWeights.Normal, t.S(0.78)), chev), null);
            head.Click += delegate { bool open = bodyBox.Visibility != Visibility.Visible; bodyBox.Visibility = open ? Visibility.Visible : Visibility.Collapsed; if (chev.Glyph != null) chev.Glyph.Text = Sym.GlyphText(open ? "chevron.down" : "chevron.right"); };
            var col = V.VLead(6, head, V.Self(bodyBox, Cross.Stretch)); col.Align = Cross.Stretch;
            return col;
        }

        /// <summary>CellAgentToolStepsTimeline: "Executed N steps · 1.2s" header, vertical rule, rows that expand to their output.</summary>
        public static UIElement Timeline(List<CellToolStep> steps)
        {
            var t = T; bool d = t.IsDark;
            bool running = steps.Any(s => s.IsRunning);
            int errors = steps.Count(s => !s.IsRunning && s.IsError);
            int totalMs = steps.Where(s => s.DurationMs.HasValue).Sum(s => s.DurationMs.Value);
            string summary;
            var active = steps.LastOrDefault(s => s.IsRunning);
            if (active != null) summary = active.FriendlyTitle + (active.Summary.Length > 0 ? " " + active.Summary : "") + "…";
            else summary = "Executed " + steps.Count + (steps.Count == 1 ? " step" : " steps") + (errors > 0 ? " (" + errors + " failed)" : "");
            var rows = V.VLead(1); rows.Align = Cross.Stretch;
            foreach (var s in steps) rows.Children.Add(StepRow(s));
            var rule = new Border { Width = 1, Background = t.P(d ? 0.12 : 0.09), Margin = new Thickness(5, 2, 0, 2) };
            var body = new Grid();
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            body.Children.Add(rule);
            var rowsBox = new Border { Child = rows, Margin = new Thickness(9, 0, 0, 0) }; Grid.SetColumn(rowsBox, 1); body.Children.Add(rowsBox);
            var chev = running ? (UIElement)new ThreeDots() : Sym.Icon("chevron.down", 8.5, t.S(0.8), FontWeights.SemiBold);
            var title = V.T(summary, 11.5, FontWeights.Medium, t.Secondary);
            var head = V.H(6, chev, V.Shrink(title));
            if (!running && totalMs > 0) head.Children.Add(V.Mono("· " + (totalMs >= 1000 ? (totalMs / 1000.0).ToString("0.0", System.Globalization.CultureInfo.InvariantCulture) + "s" : totalMs + "ms"), 10.5, FontWeights.Normal, t.S(0.7)));
            var headBtn = V.Button(V.Box(head, V.P(0, 3), Brushes.Transparent, 0), null);
            headBtn.OnState = b => title.Foreground = b.IsHover ? t.Primary : t.Secondary;
            headBtn.Click += delegate
            {
                bool open = body.Visibility != Visibility.Visible;
                body.Visibility = open ? Visibility.Visible : Visibility.Collapsed;
                var sym = chev as SymbolIcon; if (sym != null && sym.Glyph != null) sym.Glyph.Text = Sym.GlyphText(open ? "chevron.down" : "chevron.right");
            };
            var col = V.VLead(2, headBtn, V.Self(body, Cross.Stretch)); col.Align = Cross.Stretch;
            return col;
        }

        static UIElement StepRow(CellToolStep s)
        {
            var t = T; bool d = t.IsDark;
            UIElement icon = s.IsRunning ? (UIElement)new ThreeDots() : s.IsError ? Sym.Icon("xmark.circle", 10.5, NbColor.Alpha(t.SysRed, 0.85), FontWeights.Medium) : Sym.Icon(s.Icon, 10, t.Secondary);
            var row = V.H(6, V.Size(new Border { Child = icon }, 13, 13), V.T(s.FriendlyTitle, 11.5, FontWeights.Normal, s.IsError ? NbColor.Alpha(t.SysRed, 0.9) : t.P(0.86)));
            if (s.Summary.Length > 0) { var sum = V.Mono(s.Summary, 11, FontWeights.Normal, t.Secondary); sum.TextTrimming = TextTrimming.CharacterEllipsis; row.Children.Add(V.Shrink(sum)); }
            row.Children.Add(V.Sp(4));
            if (s.DurationMs.HasValue) row.Children.Add(V.Mono(s.DurationMs.Value >= 1000 ? (s.DurationMs.Value / 1000.0).ToString("0.0", System.Globalization.CultureInfo.InvariantCulture) + "s" : s.DurationMs.Value + "ms", 10, FontWeights.Normal, t.S(0.68)));
            SymbolIcon chev = null;
            if (s.Output.Length > 0) { chev = Sym.Icon("chevron.right", 8, t.S(0.45), FontWeights.SemiBold); row.Children.Add(chev); }
            var outBox = new TextBox
            {
                Text = s.Output.Length > 4000 ? s.Output.Substring(0, 4000) : s.Output, IsReadOnly = true, FontFamily = UIFonts.Mono, FontSize = 10.5,
                Foreground = s.IsError ? NbColor.Alpha(t.SysRed, 0.9) : t.P(0.84), Background = Brushes.Transparent, BorderThickness = new Thickness(0), TextWrapping = TextWrapping.Wrap,
                MaxHeight = 150 - 16, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, CaretBrush = Brushes.Transparent
            };
            var outFrame = V.Box(outBox, V.P(8), t.P(d ? 0.045 : 0.03), 5, t.P(d ? 0.10 : 0.07), 0.8);
            outFrame.Margin = new Thickness(6, 0, 0, 3);
            outFrame.Visibility = Visibility.Collapsed;
            var btn = V.Button(V.Box(row, V.P(6, 3.5), Brushes.Transparent, 4), null);
            btn.OnState = b => { ((Border)b.Child).Background = b.IsHover && s.Output.Length > 0 ? t.P(0.045) : Brushes.Transparent; if (chev != null) chev.SetBrush(b.IsHover ? t.S(0.9) : t.S(0.45)); };
            btn.Click += delegate
            {
                if (s.Output.Length == 0) return;
                bool open = outFrame.Visibility != Visibility.Visible;
                outFrame.Visibility = open ? Visibility.Visible : Visibility.Collapsed;
                if (chev != null && chev.Glyph != null) chev.Glyph.Text = Sym.GlyphText(open ? "chevron.down" : "chevron.right");
            };
            var col = V.VLead(3, btn, V.Self(outFrame, Cross.Stretch)); col.Align = Cross.Stretch;
            return col;
        }

        /// <summary>CellAIRichContentView: Markdown + TeX text, LaTeX/Markdown fences rendered, code fences as CellAICodeBlockView.</summary>
        public static UIElement RichContent(string content, bool isError, double maxWidth)
        {
            var t = T;
            var col = V.VLead(8); col.Align = Cross.Stretch;
            foreach (var b in AgentBlocks.Parse(content))
            {
                if (b.Kind == "thought") { if (b.Text.Trim().Length > 0) col.Children.Add(Thought(b.Text)); continue; }
                if (b.Kind == "code")
                {
                    string lower = (b.Lang ?? "").Trim().ToLowerInvariant();
                    if (lower == "latex" || lower == "tex" || lower == "math") { col.Children.Add(MathBlock.Create(b.Text, 15)); continue; }
                    if (lower == "markdown" || lower == "md") { col.Children.Add(MarkdownView.Render(b.Text, 12.5, NbStore.WorkingDirectory)); continue; }
                    col.Children.Add(CodeBlock(b.Lang ?? "", b.Text, maxWidth));
                    continue;
                }
                if (b.Text.Trim().Length == 0) continue;
                if (isError) col.Children.Add(V.Wrap(V.T(b.Text.Trim(), 12.5, FontWeights.Normal, NbColor.Alpha(t.SysRed, 0.9)), TextAlignment.Left));
                else col.Children.Add(MarkdownView.Render(b.Text.Trim(), 12.5, NbStore.WorkingDirectory));
            }
            return col;
        }

        /// <summary>CellAICodeBlockView: language label, Insert / Apply / Run actions and Copy over a monospaced block.</summary>
        static UIElement CodeBlock(string language, string code, double maxWidth)
        {
            var t = T; bool d = t.IsDark;
            var feedback = V.T("", 10, FontWeights.Medium, t.Secondary);
            Func<string, string, string, string, bool, Btn> act = (icon, label, tip, mode, autoRun) =>
            {
                var r = V.H(3, Sym.Icon(icon, 9, t.P(0.82)));
                bool wide = maxWidth <= 0 || maxWidth > 300;
                if (wide) r.Children.Add(V.T(label, 9.5, FontWeights.Medium, t.P(0.82)));
                var b = V.Button(V.Box(r, wide ? V.P(6, 2.5) : V.P(5, 2.5), t.P(d ? 0.07 : 0.05), 4), () =>
                {
                    var nb = NotebookView.Current;
                    if (nb == null) return;
                    nb.ApplyCode(code, language, mode, autoRun);
                    feedback.Text = "· " + (mode == "replace_selected" ? "Applied" : autoRun ? "Running" : "Inserted");
                    var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
                    timer.Tick += delegate { timer.Stop(); feedback.Text = ""; };
                    timer.Start();
                });
                b.ToolTip = tip;
                return b;
            };
            var copyIcon = Sym.Icon("doc.on.doc", 9.5, t.Secondary);
            var copy = V.Button(V.Size(new Border { Child = copyIcon }, 20, 18), () => { try { Clipboard.SetText(code); copyIcon.SetBrush(t.SysGreen); } catch (Exception ex) { Debug.WriteLine("copy code: " + ex.Message); } });
            copy.ToolTip = "Copy Code";
            var head = V.H(5, V.Mono(language.Length == 0 ? "code" : language.ToLowerInvariant(), 10, FontWeights.Medium, t.Secondary), feedback, V.Sp(4),
                act("plus.rectangle", "Insert", "Insert as a new cell below", "insert", false),
                act("arrow.down.doc", "Apply", "Apply to selected cell", "replace_selected", false),
                act("play.fill", "Run", "Insert as new cell and run", "insert", true), copy);
            int lines = code.Split('\n').Length;
            var tb = new TextBox
            {
                Text = code, IsReadOnly = true, FontFamily = UIFonts.Mono, FontSize = 11.5, Foreground = t.P(0.9), Background = Brushes.Transparent, BorderThickness = new Thickness(0),
                TextWrapping = TextWrapping.NoWrap, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = lines > 14 ? ScrollBarVisibility.Auto : ScrollBarVisibility.Disabled,
                CaretBrush = Brushes.Transparent, Padding = new Thickness(10)
            };
            if (lines > 14) tb.MaxHeight = 250;
            var col = V.VLead(0); col.Align = Cross.Stretch;
            col.Children.Add(V.Box(head, V.P(9, 5), t.P(d ? 0.055 : 0.035), 0));
            var line = V.Line(t.Separator, true); line.Opacity = 0.45; col.Children.Add(line);
            col.Children.Add(tb);
            var frame = V.Box(col, V.P(0), t.EditorBackground, 7, t.P(d ? 0.12 : 0.09), 0.8);
            frame.ClipToBounds = true;
            if (maxWidth > 0) frame.MaxWidth = maxWidth;
            return frame;
        }
    }

    public class NbChatMessage
    {
        public string Id = Guid.NewGuid().ToString("N"), Role = "user", Content = "", Thought = "", ModelLabel = "";
        public List<CellToolStep> Steps = new List<CellToolStep>();
        public bool IsAgentTurn = true, IsError;
        public DateTime Time = DateTime.Now;
    }

    /// <summary>NotebookAIPanel: 28pt "Agent · N cells" header with context-scope menu, error diagnostic strip, suggestion empty state,
    /// IDE-style transcript and the multi-row composer (+ attach, @ mention, Agent/Ask, model & role, send/stop).</summary>
    public class NotebookAIPanel : Grid
    {
        readonly NotebookView _nb;
        readonly Border _header = new Border(), _strip = new Border(), _composer = new Border();
        readonly StackPanel _list = new StackPanel();
        readonly ScrollViewer _scroll;
        readonly List<NbChatMessage> _messages = new List<NbChatMessage>();
        bool _agentMode = Defaults.Bool("cellMode.agentModeActive", true), _focusSelected, _loading, _composerFocused;
        string _role = Defaults.Str("cellMode.subAgentRole", "data_scientist"), _status = "";
        TextBox _input;
        const string Session = "notebook-ai-panel-main";

        public NotebookAIPanel(NotebookView nb)
        {
            _nb = nb;
            var t = Theme.Current;
            Background = t.PanelBackground;
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(28) });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1) });
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            Children.Add(_header);
            var div = V.Line(t.Separator, true); SetRow(div, 1); Children.Add(div);
            SetRow(_strip, 2); Children.Add(_strip);
            _list.Margin = new Thickness(0, 10, 0, 10);
            _scroll = new ScrollViewer { Content = _list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, Background = t.WorkspaceBackground, Focusable = false };
            SetRow(_scroll, 3); Children.Add(_scroll);
            SetRow(_composer, 4); Children.Add(_composer);
            RenderHeader(); RefreshErrorStrip(); RenderMessages(); RenderComposer();
        }

        NbCell SelectedCell { get { return _nb.Selected; } }
        int SelectedNumber { get { var c = SelectedCell; return c == null ? 0 : _nb.Doc.Cells.IndexOf(c) + 1; } }

        public void RefreshScope() { RenderHeader(); RefreshErrorStrip(); if (_messages.Count == 0) RenderMessages(); }

        // ── header ───────────────────────────────────────────────────────────
        void RenderHeader()
        {
            var t = Theme.Current;
            var doc = _nb.Doc;
            var row = V.H(5, V.T("Agent", 11.5, FontWeights.SemiBold, t.P(0.92)));
            string scope = _focusSelected && SelectedCell != null ? "Cell #" + SelectedNumber : SelectedCell != null ? doc.Cells.Count + " cells · #" + SelectedNumber : doc.Cells.Count + " cells";
            var scopeBtn = V.Button(V.Box(V.H(3.5, V.T("·", 10.5, FontWeights.Normal, t.S(0.6)), V.Shrink(V.T(scope, 10.5, FontWeights.Normal, _focusSelected ? t.Accent : t.Secondary)), Sym.Icon("chevron.down", 7.5, t.S(0.75), FontWeights.SemiBold)), V.P(4, 2), Brushes.Transparent, 0), null);
            scopeBtn.ToolTip = "Configure Notebook Context Scope";
            scopeBtn.MenuItems = ScopeMenu;
            row.Children.Add(scopeBtn);
            row.Children.Add(V.Sp(4));
            row.Children.Add(NotebookView.HoverIcon("plus", 10.5, 22, 20, 4, "New Session", () => { if (_loading) Stop(); _messages.Clear(); RenderMessages(); }));
            row.Children.Add(NotebookView.HoverIcon("plus.rectangle.on.rectangle", 10.5, 22, 20, 4, "Insert Inline Agent Cell", () => _nb.AddCell("Agent", null)));
            row.Children.Add(NotebookView.HoverIcon("xmark", 10.5, 22, 20, 4, "Close Agent Panel", _nb.ToggleAgentPanel));
            _header.Child = new Border { Child = row, Padding = new Thickness(10, 0, 10, 0), Background = t.PanelBackground };
        }

        List<MenuItemSpec> ScopeMenu()
        {
            var doc = _nb.Doc;
            var items = new List<MenuItemSpec> { new MenuItemSpec { Title = "Entire Sheet (" + doc.Cells.Count + " cells)", Icon = "rectangle.grid.1x2", Checked = !_focusSelected, Action = () => { _focusSelected = false; RenderHeader(); } } };
            var sel = SelectedCell;
            if (sel != null) items.Add(new MenuItemSpec { Title = "Focused Cell Only (#" + SelectedNumber + " · " + (sel.IsAgent ? "Agent" : sel.Language) + ")", Icon = "scope", Checked = _focusSelected, Action = () => { _focusSelected = true; RenderHeader(); } });
            items.Add(MenuItemSpec.Sep());
            items.Add(MenuItemSpec.Item("Quote Selected Cell Code", "curlybraces", () => QuoteSelected(false)));
            items.Add(MenuItemSpec.Item("Quote Cell + Output", "doc.plaintext", () => QuoteSelected(true)));
            return items;
        }

        // ── error diagnostic strip ───────────────────────────────────────────
        Tuple<int, NbCell> FirstError()
        {
            var cells = _nb.Doc.Cells;
            for (int i = 0; i < cells.Count; i++)
            {
                var c = cells[i];
                string o = c.Output ?? "";
                if (c.IsCode && o.Length > 0 && (o.Contains("Error") || o.Contains("Traceback") || o.Contains("Exception"))) return Tuple.Create(i + 1, c);
            }
            return null;
        }

        public void RefreshErrorStrip()
        {
            var t = Theme.Current; bool d = t.IsDark;
            var err = FirstError();
            if (_messages.Count == 0) RenderMessages();
            if (err == null || _loading) { _strip.Child = null; return; }
            int n = err.Item1;
            var fix = V.Button(V.Box(V.T("Auto-Fix", 10, FontWeights.Medium, t.P(0.88)), V.P(7, 2), t.P(d ? 0.08 : 0.06), 4, t.P(d ? 0.11 : 0.08), 0.8), () =>
            {
                if (_input != null) _input.Text = "วิเคราะห์และซ่อม Error ใน Cell #" + n + " แล้วรันทดสอบจนผ่าน";
                if (!_agentMode) { _agentMode = true; Defaults.Set("cellMode.agentModeActive", true); RenderComposer(); }
                Send();
            });
            fix.ToolTip = "Have the Agent inspect, patch, and re-run Cell #" + n;
            var row = V.H(6, Sym.Icon("exclamationmark.circle", 10.5, NbColor.Alpha(t.SysOrange, 0.9), FontWeights.Medium), V.Shrink(V.T("Cell #" + n + " reported an error", 10.5, FontWeights.Normal, t.Secondary)), V.Sp(4), fix);
            _strip.Child = new Border { Child = row, Padding = new Thickness(10, 5, 10, 5), Background = t.P(d ? 0.025 : 0.018), BorderBrush = t.Separator, BorderThickness = new Thickness(0, 0, 0, 1) };
        }

        // ── transcript ───────────────────────────────────────────────────────
        List<Tuple<string, string>> Suggestions()
        {
            var cells = _nb.Doc.Cells;
            var items = new List<Tuple<string, string>>();
            var langs = cells.Where(c => c.IsCode).Select(c => c.Language).Distinct().ToList();
            var err = FirstError();
            if (err != null) items.Add(Tuple.Create("wrench.and.screwdriver", "วิเคราะห์และแก้ Error ใน Cell #" + err.Item1 + " แล้วรันทดสอบให้ผ่าน"));
            if (_agentMode) items.Add(Tuple.Create("sparkles.rectangle.stack", "สร้าง Pipeline วิเคราะห์ข้อมูลและพล็อตกราฟเป็น Cell ใหม่พร้อมรันตรวจสอบผลลัพธ์"));
            if (langs.Contains("Python")) items.Add(Tuple.Create("chart.xyaxis.line", "สร้าง Visualization สรุปข้อมูลจาก Cell ก่อนหน้า"));
            if (langs.Count > 1) items.Add(Tuple.Create("arrow.triangle.branch", "เชื่อมผลลัพธ์ข้ามภาษา (" + string.Join(" + ", langs.OrderBy(x => x, StringComparer.Ordinal)) + ")"));
            items.Add(Tuple.Create("slider.horizontal.3", "ปรับโครงสร้างและประสิทธิภาพโค้ดใน Notebook นี้"));
            return items;
        }

        void RenderMessages()
        {
            var t = Theme.Current; bool d = t.IsDark;
            _list.Children.Clear();
            if (_messages.Count == 0)
            {
                var col = V.VLead(14); col.Align = Cross.Stretch; col.Margin = new Thickness(12, 18, 12, 0);
                var intro = V.VLead(5, V.H(6, Sym.Icon("sparkles", 12, t.Secondary, FontWeights.Medium), V.T(_agentMode ? "Notebook Agent" : "Notebook Assistant", 13, FontWeights.SemiBold, t.Primary)),
                    V.Self(V.Wrap(V.T(_agentMode ? "Inspects, edits, creates, and executes cells across languages with full workspace tool access." : "Answers questions and drafts code blocks ready to insert into any cell.", 11.5, FontWeights.Normal, t.Secondary), TextAlignment.Left), Cross.Stretch));
                intro.Align = Cross.Stretch; intro.Margin = new Thickness(4, 0, 4, 0);
                col.Children.Add(intro);
                var sugg = V.VLead(5); sugg.Align = Cross.Stretch;
                foreach (var s in Suggestions())
                {
                    var text = s.Item2;
                    var label = V.Wrap(V.T(text, 11.5, FontWeights.Normal, t.P(0.86)), TextAlignment.Left);
                    var row = new Grid();
                    row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(23) });
                    row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                    row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                    var ic = Sym.Icon(s.Item1, 10.5, t.Secondary); ic.HorizontalAlignment = HorizontalAlignment.Left;
                    row.Children.Add(ic);
                    Grid.SetColumn(label, 1); row.Children.Add(label);
                    var arrow = Sym.Icon("arrow.up.right", 8.5, t.S(0.6), FontWeights.Medium); Grid.SetColumn(arrow, 2); row.Children.Add(arrow);
                    var b = V.Button(V.Box(row, V.P(10, 7.5), t.P(d ? 0.035 : 0.025), 6, t.P(d ? 0.11 : 0.08), 0.8), () => { if (_input != null) _input.Text = text; Send(); });
                    sugg.Children.Add(b);
                }
                col.Children.Add(sugg);
                _list.Children.Add(col);
                return;
            }
            foreach (var m in _messages) _list.Children.Add(MessageRow(m));
            _scroll.ScrollToEnd();
        }

        UIElement MessageRow(NbChatMessage m)
        {
            var t = Theme.Current; bool d = t.IsDark;
            if (m.Role == "user")
            {
                var text = V.Wrap(V.T(m.Content, 12.5, FontWeights.Normal, t.Primary), TextAlignment.Left);
                var bubble = V.Box(text, V.P(12, 8), t.P(d ? 0.095 : 0.06), 12, t.P(d ? 0.14 : 0.09), 0.8);
                bubble.HorizontalAlignment = HorizontalAlignment.Right;
                bubble.Margin = new Thickness(12 + 44, 2, 12, 0);
                return bubble;
            }
            var col = V.VLead(8); col.Align = Cross.Stretch;
            var head = V.H(5, Sym.Icon(AIConfig.Mode == "local" ? "desktopcomputer" : AIConfig.Mode == "cloud" ? "sparkles" : "key", 11.5, t.Secondary), V.Shrink(V.T(m.ModelLabel.Length == 0 ? "Assistant" : m.ModelLabel, 11, FontWeights.Medium, t.Secondary)), V.T("· " + (m.IsAgentTurn ? "Agent" : "Ask"), 10.5, FontWeights.Normal, t.S(0.65)), V.Sp(4));
            if (m.Content.Length > 0)
            {
                var copyIcon = Sym.Icon("doc.on.doc", 9.5, t.Secondary);
                var copy = V.Button(copyIcon, () => { try { Clipboard.SetText(m.Content); copyIcon.SetBrush(t.SysGreen); } catch (Exception ex) { Debug.WriteLine("copy: " + ex.Message); } });
                copy.ToolTip = "Copy Response"; copy.Opacity = 0;
                col.MouseEnter += delegate { copy.Opacity = 1; }; col.MouseLeave += delegate { copy.Opacity = 0; };
                head.Children.Add(copy);
            }
            if (m.IsError)
            {
                var retry = V.Button(V.Box(V.H(3, Sym.Icon("arrow.clockwise", 9, t.P(0.85)), V.T("Retry", 10, FontWeights.Medium, t.P(0.85))), V.P(6, 2), t.P(0.07), 4), () => Retry(m));
                head.Children.Add(retry);
            }
            col.Children.Add(V.Self(head, Cross.Stretch));
            if (m.Thought.Length > 0) col.Children.Add(NbAgentUI.Thought(m.Thought));
            if (m.Steps.Count > 0) col.Children.Add(NbAgentUI.Timeline(m.Steps));
            if (m.Content.Trim().Length > 0) col.Children.Add(NbAgentUI.RichContent(m.Content, m.IsError, Math.Max(180, ActualWidth - 28)));
            else if (_loading && m == _messages.LastOrDefault() && m.Steps.Count == 0) col.Children.Add(new ThreeDots());
            return V.Box(col, V.P(14, 4), Brushes.Transparent, 0);
        }

        // ── composer ─────────────────────────────────────────────────────────
        void RenderComposer()
        {
            var t = Theme.Current; bool d = t.IsDark;
            string keep = _input != null ? _input.Text : "";
            var col = V.VLead(6); col.Align = Cross.Stretch;
            if (_loading) col.Children.Add(V.Box(V.H(7, new ThreeDots(), V.Shrink(V.Mono(_status.Length == 0 ? (_agentMode ? "Working…" : "Generating…") : _status, 11, FontWeights.Normal, t.Secondary))), V.P(4, 0), null, 0));
            var input = NbAgentUI.PromptBox(_agentMode ? "สั่ง Agent ให้สร้าง แก้ไข หรือรัน Cell… (Enter เพื่อส่ง)" : "ถามคำถามหรือให้ AI เขียนโค้ด… (Enter เพื่อส่ง)", keep, 30, 132, 12.5, null, () => { if (!_loading) Send(); });
            _input = (TextBox)input.Tag;
            input.Margin = new Thickness(2, 0, 2, 0);
            var card = new Border();
            _input.GotKeyboardFocus += delegate { _composerFocused = true; StyleCard(card); };
            _input.LostKeyboardFocus += delegate { _composerFocused = false; StyleCard(card); };
            _input.TextChanged += delegate { RenderSendOnly(); };
            Func<string, double, string, Btn> square = (icon, size, tip) =>
            {
                var b = V.Button(V.Size(V.Box(Sym.Icon(icon, size, t.Secondary, FontWeights.Medium), V.P(0), t.P(0.045), 5), 22, 22), null);
                b.ToolTip = tip;
                return b;
            };
            var attach = square("plus", 11, "Quote cell code, attach dataset, or insert inline Agent cell");
            attach.MenuItems = AttachMenu;
            var mention = square("at", 10.5, "Mention live kernel variable (@df) or cell (@Cell#1) with full schema & stats");
            mention.MenuItems = MentionMenu;
            _sendHost = new Border();
            var footer = V.H(5, attach, mention,
                NbAgentUI.ModeToggle(() => _agentMode, v => { _agentMode = v; Defaults.Set("cellMode.agentModeActive", v); RenderComposer(); if (_messages.Count == 0) RenderMessages(); }, true),
                V.Shrink(new Border { Child = NbAgentUI.ModelPill(_nb.App, double.PositiveInfinity, true, true, _agentMode ? new Func<string>(() => _role) : null, v => { _role = v; Defaults.Set("cellMode.subAgentRole", v); RenderComposer(); }, true) }),
                V.Sp(2), _sendHost);
            RenderSendOnly();
            col.Children.Add(input);
            col.Children.Add(V.Self(footer, Cross.Stretch));
            card.Child = col; card.Padding = new Thickness(9, 8, 9, 8); card.CornerRadius = new CornerRadius(10);
            StyleCard(card);
            _composer.Child = new Border { Child = card, Padding = new Thickness(10, 6, 10, 10), Background = t.PanelBackground };
        }

        Border _sendHost;
        void RenderSendOnly()
        {
            if (_sendHost == null) return;
            bool canSend = _input != null && _input.Text.Trim().Length > 0;
            _sendHost.Child = NbAgentUI.SendButton(_loading, canSend, _agentMode, () => { if (_loading) Stop(); else Send(); });
        }

        void StyleCard(Border card)
        {
            var t = Theme.Current; bool d = t.IsDark;
            card.Background = d ? Theme.B(Theme.WithAlpha(Colors.White, 0.04)) : Theme.B(Theme.WithAlpha(Colors.Black, 0.03));
            card.BorderBrush = _composerFocused ? t.A(0.55) : t.P(d ? 0.11 : 0.08);
            card.BorderThickness = new Thickness(_composerFocused ? 1.1 : 0.9);
        }

        List<MenuItemSpec> AttachMenu()
        {
            bool hasSel = SelectedCell != null;
            return new List<MenuItemSpec>
            {
                new MenuItemSpec { Title = "Quote Selected Cell Code", Icon = "curlybraces", Disabled = !hasSel, Action = () => QuoteSelected(false) },
                new MenuItemSpec { Title = "Quote Cell + Output / Traceback", Icon = "exclamationmark.bubble", Disabled = !hasSel, Action = () => QuoteSelected(true) },
                MenuItemSpec.Sep(),
                MenuItemSpec.Item("Attach Dataset File…", "tablecells.badge.ellipsis", AttachDataset),
                MenuItemSpec.Item("Insert Inline Agent Cell", "plus.rectangle.on.rectangle", () => _nb.AddCell("Agent", null))
            };
        }

        void AttachDataset()
        {
            var dlg = new Microsoft.Win32.OpenFileDialog { Multiselect = true, Title = "Attach Dataset", Filter = "Data files|*.csv;*.tsv;*.json;*.xlsx;*.xls;*.parquet;*.txt|All files|*.*" };
            if (dlg.ShowDialog() != true) return;
            foreach (var f in dlg.FileNames) _nb.AddDataFile(f);
        }

        List<MenuItemSpec> MentionMenu()
        {
            var items = new List<MenuItemSpec> { MenuItemSpec.Header("Live Kernel Variables") };
            var vars = _nb.Kernel.Variables;
            if (vars.Count == 0) items.Add(new MenuItemSpec { Title = "No active RAM variables yet (run a Python cell)", Disabled = true });
            foreach (var v in vars.Take(18)) { var name = v.Name; items.Add(MenuItemSpec.Item("@" + v.Name + " · " + v.TypeName + (v.Shape.Length > 0 ? " (" + v.Shape + ")" : ""), "memorychip", () => InsertMention("@" + name))); }
            var cells = _nb.Doc.Cells;
            if (cells.Count > 0)
            {
                items.Add(MenuItemSpec.Sep()); items.Add(MenuItemSpec.Header("Notebook Cells"));
                for (int i = 0; i < Math.Min(20, cells.Count); i++)
                {
                    var c = cells[i]; int n = i + 1;
                    string label = c.IsAgent ? "Agent" : c.Type == "Markdown" ? "Markdown" : c.Language;
                    string preview = (c.Content ?? "").Replace("\n", " "); if (preview.Length > 28) preview = preview.Substring(0, 28);
                    items.Add(MenuItemSpec.Item("@Cell#" + n + " · " + label + " — " + preview, "number.square", () => InsertMention("@Cell#" + n)));
                }
            }
            return items;
        }

        public void InsertMention(string mention)
        {
            if (_input == null) return;
            string cur = _input.Text;
            string sep = cur.Length == 0 || cur.EndsWith(" ") || cur.EndsWith("\n") ? "" : " ";
            _input.Text = cur + sep + mention + " ";
            _input.CaretIndex = _input.Text.Length;
            _input.Focus();
        }

        void QuoteSelected(bool withOutput)
        {
            var c = SelectedCell;
            if (c == null || _input == null) return;
            string snippet = "[Cell #" + SelectedNumber + " (" + c.Language + ")]:\n```" + c.Lang.Ext + "\n" + c.Content + "\n```";
            if (withOutput && (c.Output ?? "").Length > 0) snippet += "\n[Output]:\n```\n" + (c.Output.Length > 1200 ? c.Output.Substring(0, 1200) : c.Output) + "\n```";
            _input.Text += (_input.Text.Length == 0 ? "" : "\n") + snippet.Trim();
            _input.CaretIndex = _input.Text.Length;
            _input.Focus();
        }

        /// <summary>buildNotebookContext: whole sheet or the focused cell, the live kernel variables, and any @var / @Cell#N mentions.</summary>
        string BuildContext(string prompt)
        {
            var doc = _nb.Doc;
            string ctx;
            var sel = SelectedCell;
            if (_focusSelected && sel != null)
            {
                var sb = new StringBuilder("## Active Notebook: " + doc.Name + " (Focused on Cell #" + SelectedNumber + " of " + doc.Cells.Count + ")\n");
                sb.Append("- Working Directory: `" + NbStore.WorkingDirectory + "`\n");
                sb.Append("### Focused Cell #" + SelectedNumber + " (id: `" + sel.Id + "`, type: " + sel.Type + ", lang: " + sel.Language + ")\n```" + sel.Lang.Ext + "\n" + sel.Content + "\n```\n");
                if ((sel.Output ?? "").Length > 0) sb.Append("Output:\n```\n" + (sel.Output.Length > 2000 ? sel.Output.Substring(0, 2000) : sel.Output) + "\n```\n");
                ctx = sb.ToString();
            }
            else ctx = NbAgent.NotebookSnapshot(_nb);
            var vars = _nb.Kernel.Variables;
            if (vars.Count > 0)
            {
                var sb = new StringBuilder("\n### Live Kernel RAM Variables (" + vars.Count + "):\n");
                foreach (var v in vars.Take(24)) sb.Append("- `" + v.Name + "` (" + v.TypeName + (v.Shape.Length > 0 ? " shape=" + v.Shape : "") + ", " + v.FormattedMemory + ")" + (v.Columns.Count > 0 ? " cols=[" + string.Join(", ", v.Columns.Take(12)) + "]" : "") + "\n");
                foreach (var v in vars.Where(x => prompt.Contains("@" + x.Name)))
                    sb.Append("\n#### @" + v.Name + " (" + v.TypeName + ")\n- shape: " + v.Shape + "\n- dtype: " + v.Dtype + "\n- memory: " + v.FormattedMemory + (v.Columns.Count > 0 ? "\n- columns: " + string.Join(", ", v.Columns) : "") + "\n- preview: " + v.Preview + "\n");
                ctx += sb.ToString();
            }
            if (prompt.Contains("@Cell#"))
                for (int i = 0; i < doc.Cells.Count; i++)
                {
                    if (!Regex.IsMatch(prompt, "@Cell#" + (i + 1) + "(?![0-9])")) continue;
                    var c = doc.Cells[i];
                    ctx += "\n### Explicitly Mentioned @Cell#" + (i + 1) + " (" + c.Language + "):\n```" + c.Lang.Ext + "\n" + c.Content + "\n```\n";
                    if ((c.Output ?? "").Length > 0) ctx += "Output:\n```\n" + (c.Output.Length > 2000 ? c.Output.Substring(0, 2000) : c.Output) + "\n```\n";
                }
            return ctx;
        }

        void Stop()
        {
            NbAgent.Stop(Session);
            _loading = false; _status = "";
            RenderComposer(); RefreshErrorStrip(); RenderMessages();
        }

        void Retry(NbChatMessage m)
        {
            if (_loading) return;
            int idx = _messages.IndexOf(m);
            if (idx > 0 && _messages[idx - 1].Role == "user")
            {
                string prompt = _messages[idx - 1].Content;
                _messages.RemoveRange(idx - 1, 2);
                if (_input != null) _input.Text = prompt;
                Send();
            }
        }

        void Send()
        {
            if (_input == null) return;
            string text = _input.Text.Trim();
            if (text.Length == 0 || _loading) return;
            _input.Text = "";
            bool agentTurn = _agentMode;
            var history = _messages.Where(x => x.Content.Length > 0 && !x.IsError).Select(x => new ChatMessage { Role = x.Role, Content = x.Content }).ToList();
            _messages.Add(new NbChatMessage { Role = "user", Content = text });
            var reply = new NbChatMessage { Role = "assistant", ModelLabel = AIConfig.IsConfigured ? AIConfig.ModelDisplayName : "Assistant", IsAgentTurn = agentTurn };
            _messages.Add(reply);
            _loading = true; _status = agentTurn ? "Inspecting notebook…" : "Generating…";
            RenderMessages(); RenderComposer(); RefreshErrorStrip();
            DateTime lastRender = DateTime.MinValue;
            Action live = () =>
            {
                if ((DateTime.Now - lastRender).TotalMilliseconds < 80) return;
                lastRender = DateTime.Now;
                RenderMessages();
            };
            NbAgent.Start(Session, text, _role, agentTurn, BuildContext(text), history, new NbAgent.Callbacks
            {
                Status = s => { _status = s; RenderComposerStatus(); },
                Thought = th => { reply.Thought = th; live(); },
                Text = tx => { reply.Content = tx; live(); },
                Steps = st => { reply.Steps = st; live(); },
                Complete = final =>
                {
                    if (reply.Content.Length == 0 && final.Length > 0) reply.Content = final;
                    else if (reply.Content.Length == 0 && reply.Steps.Count > 0) reply.Content = "Completed " + reply.Steps.Count + " notebook actions.";
                    _loading = false; _status = "";
                    RenderMessages(); RenderComposer(); RefreshErrorStrip();
                },
                Error = e =>
                {
                    reply.Content = (reply.Content.Length == 0 ? "" : reply.Content + "\n\n") + "Error: " + e;
                    reply.IsError = true;
                    _loading = false; _status = "";
                    RenderMessages(); RenderComposer(); RefreshErrorStrip();
                },
                Cancelled = () => { _loading = false; _status = ""; RenderMessages(); RenderComposer(); },
                Approve = (step, args) => _nb.ApproveTool(step, args)
            });
        }

        void RenderComposerStatus()
        {
            // keep the typed text and focus; only the status line changes
            var card = _composer.Child as Border;
            if (card == null || !_loading) return;
            var inner = card.Child as Border; if (inner == null) return;
            var col = inner.Child as Stack; if (col == null || col.Children.Count == 0) return;
            var line = col.Children[0] as Border;
            var h = line != null ? line.Child as Stack : null;
            var tb = h != null && h.Children.Count > 1 ? h.Children[1] as TextBlock : null;
            if (tb != null) tb.Text = _status.Length == 0 ? (_agentMode ? "Working…" : "Generating…") : _status;
        }
    }

    public partial class NotebookView
    {
        /// <summary>ApplyCodeToCell notification: insert as a new cell (optionally run) or replace the selected code cell.</summary>
        internal void ApplyCode(string code, string fenceLang, string mode, bool autoRun)
        {
            if ((code ?? "").Trim().Length == 0) return;
            var sel = Selected;
            var lang = CellLang.FromFence(fenceLang) ?? (sel != null && sel.IsCode ? sel.Lang : null) ?? (Doc.Cells.Count > 0 ? Doc.Cells[Doc.Cells.Count - 1].Lang : CellLang.Get("Python"));
            if (mode == "replace_selected" && sel != null && sel.IsCode)
            {
                sel.RecordAgentEditBaseline(sel.Content, "Notebook Agent");
                sel.Language = lang.Name;
                sel.Content = code;
                SaveSoon(); RefreshEditor(sel); RenderCells();
                if (autoRun) RunCell(sel);
                return;
            }
            var c = AddCell("Code", lang.Name);
            c.Content = code;
            RefreshEditor(c);
            SaveSoon();
            if (autoRun) RunCell(c);
        }

        /// <summary>Tool approval inside Cell Mode: the shared approval policy (Settings → Agent) asks here for risky tools such as shell
        /// or file writes, with an Allow / Deny prompt.</summary>
        internal Task<bool> ApproveTool(ToolStep step, Dictionary<string, object> args)
        {
            var tcs = new TaskCompletionSource<bool>();
            Dispatcher.BeginInvoke(new Action(() =>
            {
                string what = AgentRunner.Headline(step);
                string detail = AgentRunner.RequestText(step);
                var r = MessageBox.Show(Window.GetWindow(this), "The Notebook Agent wants to run:\n\n" + what + "\n\n" + (detail.Length > 600 ? detail.Substring(0, 600) + "…" : detail) + "\n\nAllow it?", "Allow Tool — " + step.Name, MessageBoxButton.YesNo, MessageBoxImage.Question);
                tcs.TrySetResult(r == MessageBoxResult.Yes);
            }));
            return tcs.Task;
        }
    }
}
