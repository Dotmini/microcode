// ACP Host Bridge, Sub-Agent Harness (including 3-role Squad), Cross-chat Memory (agent_memory_v2.json),
// RepoMap symbol/codebase index, .ARX portable capsule bundles, Execution Evidence Guard, and Windows Computer Use.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using MicroCode.Core;

namespace MicroCode.Views
{
    // ── 1. ACP Host Bridge (external CLI agents) ─────────────────────────────

    public class AcpAgentInfo
    {
        public string Id = "";
        public string Name = "";
        public string Command = "";
        public string ResolvedPath = "";
        public bool Available;
        public string ArgTemplate = "";
        public bool UseStdinPrompt;
    }

    public class AcpRunResult
    {
        public string AgentId = "";
        public int ExitCode = -1;
        public string Output = "";
        public string Error = "";
        public bool Success;
        public long DurationMs;
    }

    public static class AcpHostService
    {
        static readonly object _gate = new object();
        static readonly Dictionary<string, AcpAgentInfo> _adapters = new Dictionary<string, AcpAgentInfo>(StringComparer.OrdinalIgnoreCase);

        static AcpHostService()
        {
            RegisterDefault("claude", "Claude Code", "claude", "-p {prompt} --output-format text", false);
            RegisterDefault("codex", "OpenAI Codex CLI", "codex", "exec {prompt}", false);
            RegisterDefault("gemini", "Gemini CLI", "gemini", "-p {prompt}", false);
            RegisterDefault("agy", "Antigravity CLI", "agy", "chat -p {prompt}", false);
            RegisterDefault("goose", "Goose CLI", "goose", "run --text {prompt}", false);
            RegisterDefault("opencode", "OpenCode CLI", "opencode", "run {prompt}", false);
            RegisterDefault("aider", "Aider CLI", "aider", "--message {prompt} --yes --no-auto-commits", false);
        }

        static void RegisterDefault(string id, string name, string cmd, string argTemplate, bool useStdin)
        {
            _adapters[id] = new AcpAgentInfo
            {
                Id = id,
                Name = name,
                Command = cmd,
                ArgTemplate = argTemplate,
                UseStdinPrompt = useStdin
            };
        }

        public static void RegisterAdapter(string id, string name, string command, string argTemplate, bool useStdinPrompt)
        {
            if (string.IsNullOrWhiteSpace(id)) return;
            lock (_gate)
            {
                _adapters[id.Trim()] = new AcpAgentInfo
                {
                    Id = id.Trim(),
                    Name = name ?? id.Trim(),
                    Command = command ?? id.Trim(),
                    ArgTemplate = argTemplate ?? "{prompt}",
                    UseStdinPrompt = useStdinPrompt
                };
            }
        }

        public static List<AcpAgentInfo> ListKnown()
        {
            var list = new List<AcpAgentInfo>();
            lock (_gate)
            {
                foreach (var kv in _adapters)
                {
                    var a = kv.Value;
                    string resolved = File.Exists(a.Command) ? a.Command : LspManager.FindExecutable(a.Command);
                    list.Add(new AcpAgentInfo
                    {
                        Id = a.Id,
                        Name = a.Name,
                        Command = a.Command,
                        ArgTemplate = a.ArgTemplate,
                        UseStdinPrompt = a.UseStdinPrompt,
                        ResolvedPath = resolved ?? "",
                        Available = !string.IsNullOrEmpty(resolved)
                    });
                }
            }
            return list;
        }

        public static List<AcpAgentInfo> ListAvailable()
        {
            return ListKnown().Where(a => a.Available).ToList();
        }

        public static AcpRunResult RunPrompt(string agentId, string prompt, string cwd)
        {
            return RunPrompt(agentId, prompt, cwd, 120000);
        }

        public static AcpRunResult RunPrompt(string agentId, string prompt, string cwd, int timeoutMs)
        {
            var sw = Stopwatch.StartNew();
            var res = new AcpRunResult { AgentId = agentId ?? "" };
            AcpAgentInfo spec = null;
            lock (_gate)
            {
                if (!string.IsNullOrEmpty(agentId)) _adapters.TryGetValue(agentId.Trim(), out spec);
            }
            if (spec == null)
            {
                res.Error = "Unknown ACP agent: " + (agentId ?? "");
                res.DurationMs = sw.ElapsedMilliseconds;
                return res;
            }

            string exe = File.Exists(spec.Command) ? spec.Command : LspManager.FindExecutable(spec.Command);
            if (string.IsNullOrEmpty(exe))
            {
                res.Error = "ACP agent executable not found on PATH: " + spec.Command;
                res.DurationMs = sw.ElapsedMilliseconds;
                return res;
            }

            try
            {
                string safePrompt = QuoteArg(prompt ?? "");
                string args = (spec.ArgTemplate ?? "").Replace("{prompt}", safePrompt);

                var psi = new ProcessStartInfo();
                psi.FileName = exe;
                psi.Arguments = args;
                psi.WorkingDirectory = !string.IsNullOrEmpty(cwd) && Directory.Exists(cwd) ? cwd : Environment.CurrentDirectory;
                psi.UseShellExecute = false;
                psi.RedirectStandardInput = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.CreateNoWindow = true;
                psi.StandardOutputEncoding = Encoding.UTF8;
                psi.StandardErrorEncoding = Encoding.UTF8;

                using (var proc = Process.Start(psi))
                {
                    if (proc == null)
                    {
                        res.Error = "Failed to start process: " + exe;
                        res.DurationMs = sw.ElapsedMilliseconds;
                        return res;
                    }

                    if (spec.UseStdinPrompt && !string.IsNullOrEmpty(prompt))
                    {
                        proc.StandardInput.Write(prompt);
                    }
                    proc.StandardInput.Close();

                    var outBuf = new StringBuilder();
                    var errBuf = new StringBuilder();
                    var outDone = new ManualResetEventSlim(false);
                    var errDone = new ManualResetEventSlim(false);

                    ThreadPool.QueueUserWorkItem(delegate
                    {
                        try { outBuf.Append(proc.StandardOutput.ReadToEnd()); } catch { }
                        finally { outDone.Set(); }
                    });
                    ThreadPool.QueueUserWorkItem(delegate
                    {
                        try { errBuf.Append(proc.StandardError.ReadToEnd()); } catch { }
                        finally { errDone.Set(); }
                    });

                    int waitMs = timeoutMs > 0 ? timeoutMs : 120000;
                    if (!proc.WaitForExit(waitMs))
                    {
                        try { proc.Kill(); } catch { }
                        res.ExitCode = -1;
                        res.Error = "ACP agent timed out after " + waitMs + " ms.";
                        res.Output = outBuf.ToString();
                        res.Success = false;
                        res.DurationMs = sw.ElapsedMilliseconds;
                        return res;
                    }

                    outDone.Wait(2000);
                    errDone.Wait(2000);
                    res.ExitCode = proc.ExitCode;
                    res.Output = outBuf.ToString();
                    res.Error = errBuf.ToString();
                    res.Success = proc.ExitCode == 0;
                    res.DurationMs = sw.ElapsedMilliseconds;
                    return res;
                }
            }
            catch (Exception ex)
            {
                res.Error = ex.Message;
                res.DurationMs = sw.ElapsedMilliseconds;
                return res;
            }
        }

        static string QuoteArg(string s)
        {
            if (s == null) return "\"\"";
            return "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", " ").Replace("\n", " ") + "\"";
        }
    }

    // ── 2. Sub-Agent Harness + 3-Role Squad ──────────────────────────────────

    public class SubagentDefinition
    {
        public string Name = "";
        public string Description = "";
        public string SystemPrompt = "";
        public bool AllowWrite;
        public DateTime CreatedAt = DateTime.UtcNow;
    }

    public class SubagentInstance
    {
        public string Id = "";
        public string TypeName = "";
        public string Role = "";
        public string Model = "";
        public string Workspace = "";
        public string Status = "running"; // running, completed, failed, killed
        public string Result = "";
        public string Error = "";
        public DateTime CreatedAt = DateTime.UtcNow;
        public DateTime UpdatedAt = DateTime.UtcNow;
        public List<string> Inbox = new List<string>();
        internal CancellationTokenSource Cts = new CancellationTokenSource();
        internal Task WorkerTask;
    }

    public class SubagentInvocationContext
    {
        public SubagentDefinition Definition;
        public SubagentInstance Instance;
        public string Prompt = "";
        public string Workspace = "";
        public CancellationToken Token;
    }

    public class SquadResult
    {
        public bool Success;
        public string ArchitectOutput = "";
        public string ImplementerOutput = "";
        public string ReviewerOutput = "";
        public string Summary = "";
        public List<string> SubagentIds = new List<string>();
    }

    public static class SubAgentHarness
    {
        static readonly object _gate = new object();
        static readonly Dictionary<string, SubagentDefinition> _defs = new Dictionary<string, SubagentDefinition>(StringComparer.OrdinalIgnoreCase);
        static readonly Dictionary<string, SubagentInstance> _instances = new Dictionary<string, SubagentInstance>(StringComparer.OrdinalIgnoreCase);

        /// <summary>Optional host hook (wired by AgentRunner) to run real LLM turns for subagents.</summary>
        public static Func<SubagentInvocationContext, string> CustomExecutor;

        static SubAgentHarness()
        {
            DefineSubagent("architect", "Analyzes workspace architecture and designs implementation plans.", "You are the Architect. Inspect the codebase and produce a concise, concrete implementation plan. Do not modify files.", false);
            DefineSubagent("implementer", "Implements code changes and runs verification commands.", "You are the Implementer. Execute the plan cleanly, write or edit code, and verify with tests.", true);
            DefineSubagent("reviewer", "Audits changes for correctness, regressions, and execution evidence.", "You are the Reviewer. Verify changes against requirements and check execution evidence. Do not modify files.", false);
            DefineSubagent("research", "Read-only codebase and documentation explorer.", "You are a read-only Research subagent. Gather exact symbols, file paths, and facts.", false);
        }

        public static SubagentDefinition DefineSubagent(string name, string desc, string sysPrompt, bool allowWrite)
        {
            if (string.IsNullOrWhiteSpace(name)) throw new ArgumentException("Subagent name is required.");
            var def = new SubagentDefinition
            {
                Name = name.Trim(),
                Description = desc ?? "",
                SystemPrompt = sysPrompt ?? "",
                AllowWrite = allowWrite,
                CreatedAt = DateTime.UtcNow
            };
            lock (_gate)
            {
                _defs[def.Name] = def;
            }
            return def;
        }

        public static SubagentDefinition GetDefinition(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return null;
            lock (_gate)
            {
                SubagentDefinition def;
                return _defs.TryGetValue(name.Trim(), out def) ? def : null;
            }
        }

        public static List<SubagentDefinition> ListDefinitions()
        {
            lock (_gate) { return new List<SubagentDefinition>(_defs.Values); }
        }

        public static SubagentInstance InvokeSubagent(string typeName, string role, string prompt, string model)
        {
            return InvokeSubagent(typeName, role, prompt, model, Environment.CurrentDirectory);
        }

        public static SubagentInstance InvokeSubagent(string typeName, string role, string prompt, string model, string cwd)
        {
            string id = "sub-" + Guid.NewGuid().ToString("N").Substring(0, 10);
            SubagentDefinition def = GetDefinition(typeName);
            if (def == null)
            {
                def = new SubagentDefinition
                {
                    Name = string.IsNullOrWhiteSpace(typeName) ? "worker" : typeName.Trim(),
                    Description = role ?? "Subagent",
                    SystemPrompt = "You are a focused subagent.",
                    AllowWrite = false
                };
            }

            var inst = new SubagentInstance
            {
                Id = id,
                TypeName = def.Name,
                Role = string.IsNullOrWhiteSpace(role) ? def.Name : role.Trim(),
                Model = model ?? "inherit",
                Workspace = cwd ?? Environment.CurrentDirectory,
                Status = "running",
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            };
            if (!string.IsNullOrEmpty(prompt)) inst.Inbox.Add("user: " + prompt);

            lock (_gate) { _instances[id] = inst; }

            var ctx = new SubagentInvocationContext
            {
                Definition = def,
                Instance = inst,
                Prompt = prompt ?? "",
                Workspace = inst.Workspace,
                Token = inst.Cts.Token
            };

            inst.WorkerTask = Task.Run(delegate
            {
                try
                {
                    ctx.Token.ThrowIfCancellationRequested();
                    string output = ExecuteSubagentWork(ctx);
                    if (ctx.Token.IsCancellationRequested || inst.Status == "killed") return;
                    inst.Result = output ?? "";
                    inst.Status = "completed";
                    inst.UpdatedAt = DateTime.UtcNow;
                }
                catch (OperationCanceledException)
                {
                    if (inst.Status != "killed") inst.Status = "killed";
                    inst.UpdatedAt = DateTime.UtcNow;
                }
                catch (Exception ex)
                {
                    if (inst.Status != "killed")
                    {
                        inst.Error = ex.Message;
                        inst.Status = "failed";
                    }
                    inst.UpdatedAt = DateTime.UtcNow;
                }
            });

            return inst;
        }

        static string ExecuteSubagentWork(SubagentInvocationContext ctx)
        {
            var hook = CustomExecutor;
            if (hook != null) return hook(ctx);

            string model = ctx.Instance.Model ?? "";
            if (model.StartsWith("acp:", StringComparison.OrdinalIgnoreCase))
            {
                string acpId = model.Substring(4).Trim();
                string fullPrompt = string.IsNullOrEmpty(ctx.Definition.SystemPrompt)
                    ? ctx.Prompt
                    : ctx.Definition.SystemPrompt + "\n\nTask:\n" + ctx.Prompt;
                var acpRes = AcpHostService.RunPrompt(acpId, fullPrompt, ctx.Workspace, 120000);
                if (!acpRes.Success && !string.IsNullOrEmpty(acpRes.Error))
                {
                    throw new InvalidOperationException(acpRes.Error);
                }
                return acpRes.Output;
            }

            // Deterministic local fallback when no LLM executor is attached (e.g. offline/tests).
            var sb = new StringBuilder();
            sb.AppendLine("[" + ctx.Instance.Role + " / " + ctx.Definition.Name + "]");
            if (!string.IsNullOrEmpty(ctx.Workspace) && Directory.Exists(ctx.Workspace))
            {
                string map = RepoMapService.BuildRepoMap(ctx.Workspace, 1500);
                if (!string.IsNullOrEmpty(map))
                {
                    sb.AppendLine("Workspace context:");
                    sb.AppendLine(map);
                }
            }
            sb.AppendLine("Processed prompt: " + ctx.Prompt);
            return sb.ToString().TrimEnd();
        }

        public static bool SendMessage(string id, string msg)
        {
            if (string.IsNullOrWhiteSpace(id)) return false;
            SubagentInstance inst;
            lock (_gate)
            {
                if (!_instances.TryGetValue(id.Trim(), out inst)) return false;
            }
            if (inst.Status == "killed") return false;
            lock (inst.Inbox)
            {
                inst.Inbox.Add("message: " + (msg ?? ""));
                inst.UpdatedAt = DateTime.UtcNow;
            }
            return true;
        }

        public static List<SubagentInstance> ListSubagents()
        {
            lock (_gate)
            {
                return _instances.Values.OrderBy(i => i.CreatedAt).ToList();
            }
        }

        public static SubagentInstance GetSubagent(string id)
        {
            if (string.IsNullOrWhiteSpace(id)) return null;
            lock (_gate)
            {
                SubagentInstance inst;
                return _instances.TryGetValue(id.Trim(), out inst) ? inst : null;
            }
        }

        public static string ManageSubagents(string action)
        {
            return ManageSubagents(action, null);
        }

        public static string ManageSubagents(string action, string id)
        {
            string act = (action ?? "list").Trim().ToLowerInvariant();
            if (act == "kill")
            {
                if (string.IsNullOrWhiteSpace(id)) return "Error: subagent id is required for kill.";
                SubagentInstance inst;
                lock (_gate) { _instances.TryGetValue(id.Trim(), out inst); }
                if (inst == null) return "Error: subagent not found: " + id;
                KillInstance(inst);
                return "Killed subagent " + inst.Id;
            }
            if (act == "kill_all")
            {
                List<SubagentInstance> all = ListSubagents();
                int count = 0;
                for (int i = 0; i < all.Count; i++)
                {
                    if (all[i].Status != "killed")
                    {
                        KillInstance(all[i]);
                        count++;
                    }
                }
                return "Killed " + count + " subagent(s).";
            }

            List<SubagentInstance> list = ListSubagents();
            if (list.Count == 0) return "No subagents.";
            var sb = new StringBuilder();
            for (int i = 0; i < list.Count; i++)
            {
                var s = list[i];
                sb.AppendLine(string.Format(CultureInfo.InvariantCulture, "{0} | type={1} | role={2} | status={3} | inbox={4}", s.Id, s.TypeName, s.Role, s.Status, s.Inbox.Count));
            }
            return sb.ToString().TrimEnd();
        }

        static void KillInstance(SubagentInstance inst)
        {
            inst.Status = "killed";
            inst.UpdatedAt = DateTime.UtcNow;
            try { inst.Cts.Cancel(); } catch { }
        }

        public static bool WaitSubagent(string id, int timeoutMs)
        {
            var inst = GetSubagent(id);
            if (inst == null || inst.WorkerTask == null) return false;
            try { return inst.WorkerTask.Wait(timeoutMs > 0 ? timeoutMs : 10000); }
            catch { return true; }
        }

        /// <summary>Runs the 3-role Architect -> Implementer -> Reviewer squad pipeline with parallel context gather.</summary>
        public static SquadResult RunSquad(string task, string cwd)
        {
            var result = new SquadResult();
            string ws = !string.IsNullOrEmpty(cwd) && Directory.Exists(cwd) ? cwd : Environment.CurrentDirectory;

            // Parallel Stage 1: Architect analysis + Research context discovery
            var arch = InvokeSubagent("architect", "Squad Architect", "Design an implementation plan for:\n" + (task ?? ""), "inherit", ws);
            var res = InvokeSubagent("research", "Squad Researcher", "Gather relevant symbols and files for:\n" + (task ?? ""), "inherit", ws);
            result.SubagentIds.Add(arch.Id);
            result.SubagentIds.Add(res.Id);
            Task.WaitAll(new[] { arch.WorkerTask, res.WorkerTask }, 60000);

            result.ArchitectOutput = arch.Result;
            string combinedPlan = "Task: " + (task ?? "") + "\n\nArchitect Plan:\n" + (arch.Result ?? "") + "\n\nResearch Notes:\n" + (res.Result ?? "");

            // Stage 2: Implementer executes against plan
            var impl = InvokeSubagent("implementer", "Squad Implementer", combinedPlan, "inherit", ws);
            result.SubagentIds.Add(impl.Id);
            if (impl.WorkerTask != null) impl.WorkerTask.Wait(60000);
            result.ImplementerOutput = impl.Result;

            // Stage 3: Reviewer validates outcome
            var rev = InvokeSubagent("reviewer", "Squad Reviewer", "Review the implementation for task:\n" + (task ?? "") + "\n\nImplementation output:\n" + (impl.Result ?? ""), "inherit", ws);
            result.SubagentIds.Add(rev.Id);
            if (rev.WorkerTask != null) rev.WorkerTask.Wait(60000);
            result.ReviewerOutput = rev.Result;

            result.Success = arch.Status == "completed" && impl.Status == "completed" && rev.Status == "completed";
            result.Summary = "Architect: " + arch.Status + " | Implementer: " + impl.Status + " | Reviewer: " + rev.Status;
            return result;
        }
    }

    // ── 3. Cross-Chat Agent Memory (agent_memory_v2.json) ────────────────────

    public class MemoryEntry
    {
        public string Id = Guid.NewGuid().ToString("N");
        public string Topic = "";
        public string Summary = "";
        public string Workspace = "";
        public List<string> Keywords = new List<string>();
        public DateTime CreatedAt = DateTime.UtcNow;
        public DateTime UpdatedAt = DateTime.UtcNow;
        public int AccessCount;
    }

    public static class AgentMemoryService
    {
        static readonly object _gate = new object();
        static readonly Regex RxWord = new Regex(@"[a-zA-Z0-9_]{2,}", RegexOptions.Compiled);
        static readonly HashSet<string> StopWords = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "the", "and", "for", "with", "that", "this", "from", "into", "when", "what", "where", "how",
            "are", "was", "were", "have", "has", "had", "not", "but", "can", "will", "use", "using"
        };

        public static string FilePath
        {
            get { return Path.Combine(Defaults.Dir, "agent_memory_v2.json"); }
        }

        public static MemoryEntry Remember(string topic, string summary, string workspace)
        {
            string normTopic = (topic ?? "").Trim();
            string normSummary = (summary ?? "").Trim();
            string normWs = NormalizeWorkspace(workspace);
            if (normTopic.Length == 0 && normSummary.Length == 0) return null;
            if (normTopic.Length == 0) normTopic = normSummary.Length > 48 ? normSummary.Substring(0, 48) : normSummary;

            List<string> kw = ExtractKeywords(normTopic + " " + normSummary);

            lock (_gate)
            {
                List<MemoryEntry> entries = LoadInternal();
                MemoryEntry existing = entries.FirstOrDefault(e =>
                    string.Equals(e.Topic, normTopic, StringComparison.OrdinalIgnoreCase) &&
                    string.Equals(NormalizeWorkspace(e.Workspace), normWs, StringComparison.OrdinalIgnoreCase));

                if (existing != null)
                {
                    existing.Summary = normSummary;
                    existing.Keywords = kw;
                    existing.UpdatedAt = DateTime.UtcNow;
                    SaveInternal(entries);
                    return CloneEntry(existing);
                }

                var entry = new MemoryEntry
                {
                    Id = Guid.NewGuid().ToString("N"),
                    Topic = normTopic,
                    Summary = normSummary,
                    Workspace = normWs,
                    Keywords = kw,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow,
                    AccessCount = 0
                };
                entries.Add(entry);
                SaveInternal(entries);
                return CloneEntry(entry);
            }
        }

        public static List<MemoryEntry> Recall(string query, string workspace, int limit)
        {
            int max = limit > 0 ? limit : 5;
            string normWs = NormalizeWorkspace(workspace);
            string q = (query ?? "").Trim();
            List<string> qTokens = ExtractKeywords(q);

            lock (_gate)
            {
                List<MemoryEntry> entries = LoadInternal();
                if (entries.Count == 0) return new List<MemoryEntry>();

                var scored = new List<Tuple<double, MemoryEntry>>();
                for (int i = 0; i < entries.Count; i++)
                {
                    var e = entries[i];
                    double score = ScoreEntry(e, q, qTokens, normWs);
                    if (q.Length == 0 || score > 0.05)
                    {
                        scored.Add(Tuple.Create(score, e));
                    }
                }

                var top = scored
                    .OrderByDescending(x => x.Item1)
                    .ThenByDescending(x => x.Item2.UpdatedAt)
                    .Take(max)
                    .Select(x => x.Item2)
                    .ToList();

                if (top.Count > 0)
                {
                    for (int i = 0; i < top.Count; i++) top[i].AccessCount++;
                    SaveInternal(entries);
                }

                return top.Select(CloneEntry).ToList();
            }
        }

        public static List<MemoryEntry> ListAll()
        {
            lock (_gate) { return LoadInternal().Select(CloneEntry).ToList(); }
        }

        public static void Clear()
        {
            lock (_gate) { SaveInternal(new List<MemoryEntry>()); }
        }

        public static string FormatForPrompt(string query, string workspace, int limit)
        {
            var items = Recall(query, workspace, limit);
            if (items.Count == 0) return "";
            var sb = new StringBuilder();
            sb.AppendLine("## Recalled Cross-Chat Memory");
            for (int i = 0; i < items.Count; i++)
            {
                sb.AppendLine("- **" + items[i].Topic + "**: " + items[i].Summary);
            }
            return sb.ToString().TrimEnd();
        }

        static double ScoreEntry(MemoryEntry e, string query, List<string> qTokens, string normWs)
        {
            double wsBonus = 0.0;
            string entryWs = NormalizeWorkspace(e.Workspace);
            if (!string.IsNullOrEmpty(normWs) && string.Equals(entryWs, normWs, StringComparison.OrdinalIgnoreCase))
            {
                wsBonus = 1.5;
            }
            else if (string.IsNullOrEmpty(entryWs))
            {
                wsBonus = 0.5;
            }

            if (string.IsNullOrEmpty(query)) return 1.0 + wsBonus;

            double match = 0.0;
            string topicLower = (e.Topic ?? "").ToLowerInvariant();
            string summaryLower = (e.Summary ?? "").ToLowerInvariant();
            string qLower = query.ToLowerInvariant();

            if (topicLower.Contains(qLower)) match += 6.0;
            if (summaryLower.Contains(qLower)) match += 3.0;

            var entryKw = new HashSet<string>(e.Keywords ?? new List<string>(), StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < qTokens.Count; i++)
            {
                string tok = qTokens[i];
                if (topicLower.Contains(tok)) match += 2.5;
                else if (entryKw.Contains(tok)) match += 1.8;
                else if (summaryLower.Contains(tok)) match += 1.0;
                else
                {
                    // Partial stem/prefix similarity for semantic-like recall
                    foreach (var kw in entryKw)
                    {
                        if (kw.Length >= 4 && tok.Length >= 4 && (kw.StartsWith(tok, StringComparison.OrdinalIgnoreCase) || tok.StartsWith(kw, StringComparison.OrdinalIgnoreCase)))
                        {
                            match += 0.9;
                            break;
                        }
                    }
                }
            }

            if (match <= 0) return 0.0;
            return match + wsBonus + Math.Min(1.0, e.AccessCount * 0.05);
        }

        static List<string> ExtractKeywords(string text)
        {
            var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (string.IsNullOrWhiteSpace(text)) return new List<string>();
            var matches = RxWord.Matches(text);
            for (int i = 0; i < matches.Count; i++)
            {
                string w = matches[i].Value.ToLowerInvariant();
                if (!StopWords.Contains(w)) set.Add(w);
            }
            return set.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList();
        }

        static string NormalizeWorkspace(string ws)
        {
            if (string.IsNullOrWhiteSpace(ws)) return "";
            return ws.Trim().TrimEnd('\\', '/').Replace('\\', '/');
        }

        static List<MemoryEntry> LoadInternal()
        {
            try
            {
                string p = FilePath;
                if (!File.Exists(p)) return new List<MemoryEntry>();
                string json = Defaults.ReadShared(p);
                if (string.IsNullOrWhiteSpace(json)) return new List<MemoryEntry>();
                var list = DJ.S.Deserialize<List<MemoryEntry>>(json);
                return list ?? new List<MemoryEntry>();
            }
            catch { return new List<MemoryEntry>(); }
        }

        static void SaveInternal(List<MemoryEntry> entries)
        {
            try { Defaults.WriteAtomic(FilePath, DJ.Ser(entries ?? new List<MemoryEntry>())); }
            catch { }
        }

        static MemoryEntry CloneEntry(MemoryEntry e)
        {
            return new MemoryEntry
            {
                Id = e.Id,
                Topic = e.Topic,
                Summary = e.Summary,
                Workspace = e.Workspace,
                Keywords = new List<string>(e.Keywords ?? new List<string>()),
                CreatedAt = e.CreatedAt,
                UpdatedAt = e.UpdatedAt,
                AccessCount = e.AccessCount
            };
        }
    }

    // ── 4. RepoMap Symbol & Codebase Search Service ──────────────────────────

    public class RepoSymbol
    {
        public string Name = "";
        public string Kind = "";
        public string FilePath = "";
        public int Line;
        public string Signature = "";
    }

    public class CodeSearchHit
    {
        public string FilePath = "";
        public int Line;
        public string Symbol = "";
        public string Snippet = "";
        public double Score;
    }

    public static class RepoMapService
    {
        static readonly HashSet<string> SkipDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            ".git", ".svn", ".hg", "node_modules", "bin", "obj", "out", "out-dev", ".vs", ".idea",
            "target", "dist", "build", ".codetuner-build", "Pods", ".next", "__pycache__", ".venv", "venv"
        };

        static readonly HashSet<string> SourceExts = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            ".cs", ".py", ".ts", ".tsx", ".js", ".jsx", ".swift", ".rs", ".go", ".java",
            ".cpp", ".cc", ".c", ".h", ".hpp", ".rb", ".kt", ".ar", ".md"
        };

        static readonly Regex RxTypeDecl = new Regex(@"^\s*(?:export\s+)?(?:public|private|internal|protected|static|abstract|sealed|partial|final|open|pub\s+)?\s*(?:class|struct|interface|enum|protocol|trait|record)\s+([A-Za-z_][A-Za-z0-9_]*)", RegexOptions.Compiled);
        static readonly Regex RxFuncDecl = new Regex(@"^\s*(?:export\s+)?(?:async\s+)?(?:def|fn|func|function)\s+([A-Za-z_][A-Za-z0-9_]*)\s*[\(\<]", RegexOptions.Compiled);
        static readonly Regex RxCStyleMethod = new Regex(@"^\s*(?:public|private|internal|protected|static|virtual|override|async|sealed|extern)\s+(?:static\s+|async\s+|override\s+|virtual\s+|extern\s+)*[A-Za-z_][A-Za-z0-9_<>\[\],\.\?\s]*\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", RegexOptions.Compiled);

        public static List<string> EnumerateSourceFiles(string ws, int maxFiles)
        {
            var files = new List<string>();
            if (string.IsNullOrWhiteSpace(ws) || !Directory.Exists(ws)) return files;
            string root = Path.GetFullPath(ws);
            Walk(root, files, maxFiles > 0 ? maxFiles : 2000);
            files.Sort(StringComparer.OrdinalIgnoreCase);
            return files;
        }

        static void Walk(string dir, List<string> acc, int maxFiles)
        {
            if (acc.Count >= maxFiles) return;
            string[] subFiles;
            try { subFiles = Directory.GetFiles(dir); }
            catch { return; }

            for (int i = 0; i < subFiles.Length && acc.Count < maxFiles; i++)
            {
                string ext = Path.GetExtension(subFiles[i]);
                if (SourceExts.Contains(ext)) acc.Add(subFiles[i]);
            }

            string[] subDirs;
            try { subDirs = Directory.GetDirectories(dir); }
            catch { return; }

            for (int i = 0; i < subDirs.Length && acc.Count < maxFiles; i++)
            {
                string name = Path.GetFileName(subDirs[i]);
                if (string.IsNullOrEmpty(name) || SkipDirs.Contains(name)) continue;
                Walk(subDirs[i], acc, maxFiles);
            }
        }

        public static List<RepoSymbol> ExtractSymbols(string filePath, string rootDir)
        {
            var list = new List<RepoSymbol>();
            if (string.IsNullOrEmpty(filePath) || !File.Exists(filePath)) return list;
            try
            {
                var info = new FileInfo(filePath);
                if (info.Length > 512 * 1024) return list;
                string rel = MakeRelative(rootDir, filePath);
                string[] lines = File.ReadAllLines(filePath);
                for (int i = 0; i < lines.Length; i++)
                {
                    string line = lines[i];
                    if (line.Length > 300 || line.TrimStart().StartsWith("//") || line.TrimStart().StartsWith("#")) continue;

                    Match mt = RxTypeDecl.Match(line);
                    if (mt.Success)
                    {
                        list.Add(new RepoSymbol { Name = mt.Groups[1].Value, Kind = "type", FilePath = rel, Line = i + 1, Signature = line.Trim() });
                        continue;
                    }
                    Match mf = RxFuncDecl.Match(line);
                    if (mf.Success)
                    {
                        list.Add(new RepoSymbol { Name = mf.Groups[1].Value, Kind = "func", FilePath = rel, Line = i + 1, Signature = line.Trim() });
                        continue;
                    }
                    Match mc = RxCStyleMethod.Match(line);
                    if (mc.Success)
                    {
                        string name = mc.Groups[1].Value;
                        if (name != "if" && name != "for" && name != "while" && name != "switch" && name != "catch" && name != "using" && name != "lock" && name != "return")
                        {
                            list.Add(new RepoSymbol { Name = name, Kind = "method", FilePath = rel, Line = i + 1, Signature = line.Trim() });
                        }
                    }
                }
            }
            catch { }
            return list;
        }

        public static string BuildRepoMap(string ws, int maxChars)
        {
            if (string.IsNullOrWhiteSpace(ws) || !Directory.Exists(ws)) return "";
            int budget = maxChars > 0 ? maxChars : 8000;
            string root = Path.GetFullPath(ws);
            List<string> files = EnumerateSourceFiles(root, 1500);
            var sb = new StringBuilder();
            sb.AppendLine("# RepoMap (" + files.Count + " indexed files)");

            for (int i = 0; i < files.Count; i++)
            {
                string rel = MakeRelative(root, files[i]);
                var syms = ExtractSymbols(files[i], root);
                var entry = new StringBuilder();
                entry.Append(rel);
                if (syms.Count > 0)
                {
                    entry.Append(": ");
                    int shown = Math.Min(syms.Count, 12);
                    for (int j = 0; j < shown; j++)
                    {
                        if (j > 0) entry.Append(", ");
                        entry.Append(syms[j].Name).Append(" (L").Append(syms[j].Line).Append(")");
                    }
                    if (syms.Count > shown) entry.Append(", +").Append(syms.Count - shown).Append(" more");
                }
                entry.AppendLine();

                if (sb.Length + entry.Length > budget)
                {
                    sb.AppendLine("... (truncated at " + budget + " chars)");
                    break;
                }
                sb.Append(entry.ToString());
            }
            return sb.ToString().TrimEnd();
        }

        public static List<CodeSearchHit> CodebaseSearch(string ws, string query, int limit)
        {
            var hits = new List<CodeSearchHit>();
            if (string.IsNullOrWhiteSpace(ws) || !Directory.Exists(ws) || string.IsNullOrWhiteSpace(query)) return hits;
            int max = limit > 0 ? limit : 20;
            string root = Path.GetFullPath(ws);
            string q = query.Trim();
            string[] terms = q.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            List<string> files = EnumerateSourceFiles(root, 1500);

            for (int i = 0; i < files.Count; i++)
            {
                string file = files[i];
                string rel = MakeRelative(root, file);
                var syms = ExtractSymbols(file, root);
                for (int s = 0; s < syms.Count; s++)
                {
                    var sym = syms[s];
                    double score = 0;
                    if (string.Equals(sym.Name, q, StringComparison.OrdinalIgnoreCase)) score = 100.0;
                    else if (sym.Name.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0) score = 60.0;
                    else if (terms.Length > 1 && terms.All(t => sym.Signature.IndexOf(t, StringComparison.OrdinalIgnoreCase) >= 0)) score = 40.0;

                    if (score > 0)
                    {
                        hits.Add(new CodeSearchHit
                        {
                            FilePath = rel,
                            Line = sym.Line,
                            Symbol = sym.Name,
                            Snippet = sym.Signature,
                            Score = score
                        });
                    }
                }

                // Content line fallback search
                try
                {
                    if (new FileInfo(file).Length <= 256 * 1024)
                    {
                        string[] lines = File.ReadAllLines(file);
                        for (int ln = 0; ln < lines.Length; ln++)
                        {
                            if (lines[ln].IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0)
                            {
                                bool alreadySym = hits.Any(h => h.FilePath == rel && h.Line == ln + 1);
                                if (!alreadySym)
                                {
                                    hits.Add(new CodeSearchHit
                                    {
                                        FilePath = rel,
                                        Line = ln + 1,
                                        Symbol = "",
                                        Snippet = lines[ln].Trim(),
                                        Score = rel.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0 ? 25.0 : 15.0
                                    });
                                }
                            }
                        }
                    }
                }
                catch { }
            }

            return hits
                .OrderByDescending(h => h.Score)
                .ThenBy(h => h.FilePath, StringComparer.OrdinalIgnoreCase)
                .ThenBy(h => h.Line)
                .Take(max)
                .ToList();
        }

        static string MakeRelative(string root, string full)
        {
            string r = root.TrimEnd('\\', '/') + Path.DirectorySeparatorChar;
            if (full.StartsWith(r, StringComparison.OrdinalIgnoreCase))
            {
                return full.Substring(r.Length).Replace('\\', '/');
            }
            return full.Replace('\\', '/');
        }
    }

    // ── 5. .ARX Portable Agent Capsule Service ───────────────────────────────

    public class ArxRuleEntry
    {
        public string Badge = "";
        public string RelativePath = "";
        public string Description = "";
        public string Content = "";
        public bool AlwaysApply = true;
    }

    public class ArxCapsule
    {
        public string Format = "microcode.arx.v1";
        public string Version = "1.0";
        public DateTime ExportedAt = DateTime.UtcNow;
        public string Workspace = "";
        public ChatSession Session;
        public List<ArxRuleEntry> Rules = new List<ArxRuleEntry>();
        public List<MemoryEntry> Memories = new List<MemoryEntry>();
        public Dictionary<string, string> Metadata = new Dictionary<string, string>();
    }

    public static class ArxCapsuleService
    {
        public static string ExportCapsule(ChatSession session, string outPath)
        {
            if (session == null) throw new ArgumentNullException("session");
            if (string.IsNullOrWhiteSpace(outPath)) throw new ArgumentException("Output path is required.");

            var capsule = new ArxCapsule();
            capsule.ExportedAt = DateTime.UtcNow;
            capsule.Workspace = session.ProjectPath ?? "";
            capsule.Session = session;
            capsule.Metadata["app"] = "MicroCodeNative";
            capsule.Metadata["platform"] = Environment.OSVersion.Platform.ToString();

            if (!string.IsNullOrEmpty(session.ProjectPath) && Directory.Exists(session.ProjectPath))
            {
                try
                {
                    var rules = RulesEngine.ScanRules(session.ProjectPath);
                    for (int i = 0; i < rules.Count; i++)
                    {
                        capsule.Rules.Add(new ArxRuleEntry
                        {
                            Badge = rules[i].Badge ?? "",
                            RelativePath = rules[i].RelativePath ?? "",
                            Description = rules[i].Description ?? "",
                            Content = rules[i].Content ?? "",
                            AlwaysApply = rules[i].AlwaysApply
                        });
                    }
                }
                catch { }
            }

            try
            {
                capsule.Memories = AgentMemoryService.Recall("", session.ProjectPath, 25);
            }
            catch { }

            string json = DJ.Ser(capsule);
            Defaults.WriteAtomic(Path.GetFullPath(outPath), json);
            return Path.GetFullPath(outPath);
        }

        public static ArxCapsule ImportCapsule(string path)
        {
            if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
            {
                throw new FileNotFoundException("ARX capsule file not found.", path);
            }
            string json = Defaults.ReadShared(path);
            var capsule = DJ.S.Deserialize<ArxCapsule>(json);
            if (capsule == null || capsule.Session == null || string.IsNullOrEmpty(capsule.Format) || !capsule.Format.StartsWith("microcode.arx", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("Invalid .arx capsule file.");
            }
            return capsule;
        }
    }

    // ── 6. Execution Evidence Guard ──────────────────────────────────────────

    public class EvidenceReport
    {
        public bool Passed = true;
        public bool ClaimedMutation;
        public bool ClaimedVerification;
        public int SuccessfulEdits;
        public int FailedEdits;
        public int SuccessfulShellChecks;
        public List<string> Warnings = new List<string>();
        public string Summary = "";
    }

    public static class ExecutionEvidenceGuard
    {
        static readonly Regex RxMutationClaim = new Regex(@"\b(i(?:'ve| have)?\s+(?:created|wrote|written|edited|modified|updated|patched|implemented|added|fixed|refactored)|files?\s+(?:created|updated|modified|written|edited))\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        static readonly Regex RxTestClaim = new Regex(@"\b((?:all\s+)?tests?\s+(?:passed|pass|succeeded|passing)|build\s+(?:succeeded|passed)|compiled\s+(?:cleanly|successfully)|verified\s+by\s+running)\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        static readonly HashSet<string> EditTools = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "file_write", "write_file", "write_to_file", "create_file", "write", "save_file", "overwrite_file",
            "replace_in_file", "edit_file", "str_replace", "edit", "replace", "modify_file",
            "multi_replace_in_file", "multiedit", "multi_edit",
            "patch_file", "apply_patch", "applypatch", "patch",
            "rename_file", "move_file", "create_directory", "mkdir"
        };

        static readonly HashSet<string> ShellTools = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "shell", "bash", "run_terminal_cmd", "execute_command", "run_command", "terminal", "exec", "cmd", "sh", "run_shell", "shell_command", "powershell"
        };

        public static EvidenceReport CheckCompletion(List<ToolStep> steps, string reply)
        {
            var report = new EvidenceReport();
            var list = steps ?? new List<ToolStep>();
            string text = reply ?? "";

            for (int i = 0; i < list.Count; i++)
            {
                var st = list[i];
                if (st == null || string.IsNullOrEmpty(st.Name)) continue;
                bool allowed = st.Approval != "rejected" && st.Approval != "blocked" && st.Approval != "timeout";

                if (EditTools.Contains(st.Name))
                {
                    if (st.Ok && allowed) report.SuccessfulEdits++;
                    else report.FailedEdits++;
                }
                else if (ShellTools.Contains(st.Name))
                {
                    if (st.Ok && allowed) report.SuccessfulShellChecks++;
                }
            }

            report.ClaimedMutation = RxMutationClaim.IsMatch(text);
            report.ClaimedVerification = RxTestClaim.IsMatch(text);

            if (report.ClaimedMutation && report.SuccessfulEdits == 0 && report.SuccessfulShellChecks == 0)
            {
                report.Warnings.Add("Reply claims file modifications, but no successful write/edit tool step was executed.");
            }
            if (report.ClaimedVerification && report.SuccessfulShellChecks == 0)
            {
                report.Warnings.Add("Reply claims tests or build passed, but no successful shell execution step was recorded.");
            }
            if (report.FailedEdits > 0 && report.SuccessfulEdits == 0)
            {
                report.Warnings.Add("Edit tool calls failed and no successful edit followed.");
            }

            report.Passed = report.Warnings.Count == 0;
            report.Summary = report.Passed
                ? string.Format(CultureInfo.InvariantCulture, "Evidence OK (edits={0}, shell={1})", report.SuccessfulEdits, report.SuccessfulShellChecks)
                : string.Join(" ", report.Warnings.ToArray());
            return report;
        }
    }

    // ── 7. Windows Desktop Automation (ComputerUseService) ───────────────────

    public static class ComputerUseService
    {
        public static bool IsSupported
        {
            get { return Environment.OSVersion.Platform == PlatformID.Win32NT && Type.GetType("Mono.Runtime") == null; }
        }

        public static bool Screenshot(string outPath)
        {
            if (!IsSupported || string.IsNullOrWhiteSpace(outPath)) return false;
            string full = Path.GetFullPath(outPath);
            Directory.CreateDirectory(Path.GetDirectoryName(full));

            if (full.EndsWith(".png", StringComparison.OrdinalIgnoreCase))
            {
                string tmpBmp = full + ".tmp.bmp";
                if (!CaptureDesktopBmp(tmpBmp)) return false;
                try
                {
                    if (ConvertBmpToPngViaPowerShell(tmpBmp, full))
                    {
                        try { File.Delete(tmpBmp); } catch { }
                        return File.Exists(full);
                    }
                    // Fallback: keep BMP bytes if PowerShell conversion unavailable
                    File.Copy(tmpBmp, full, true);
                    try { File.Delete(tmpBmp); } catch { }
                    return File.Exists(full);
                }
                catch { return false; }
            }
            return CaptureDesktopBmp(full);
        }

        static bool CaptureDesktopBmp(string bmpPath)
        {
            IntPtr hdcScreen = IntPtr.Zero;
            IntPtr hdcMem = IntPtr.Zero;
            IntPtr hBitmap = IntPtr.Zero;
            IntPtr hOld = IntPtr.Zero;
            try
            {
                int left = NativeWin32.GetSystemMetrics(NativeWin32.SM_XVIRTUALSCREEN);
                int top = NativeWin32.GetSystemMetrics(NativeWin32.SM_YVIRTUALSCREEN);
                int width = NativeWin32.GetSystemMetrics(NativeWin32.SM_CXVIRTUALSCREEN);
                int height = NativeWin32.GetSystemMetrics(NativeWin32.SM_CYVIRTUALSCREEN);
                if (width <= 0 || height <= 0)
                {
                    left = 0; top = 0;
                    width = NativeWin32.GetSystemMetrics(NativeWin32.SM_CXSCREEN);
                    height = NativeWin32.GetSystemMetrics(NativeWin32.SM_CYSCREEN);
                }
                if (width <= 0 || height <= 0) return false;

                hdcScreen = NativeWin32.GetDC(IntPtr.Zero);
                hdcMem = NativeWin32.CreateCompatibleDC(hdcScreen);
                hBitmap = NativeWin32.CreateCompatibleBitmap(hdcScreen, width, height);
                hOld = NativeWin32.SelectObject(hdcMem, hBitmap);

                if (!NativeWin32.BitBlt(hdcMem, 0, 0, width, height, hdcScreen, left, top, NativeWin32.SRCCOPY))
                {
                    return false;
                }

                var bi = new NativeWin32.BITMAPINFOHEADER();
                bi.biSize = Marshal.SizeOf(typeof(NativeWin32.BITMAPINFOHEADER));
                bi.biWidth = width;
                bi.biHeight = height;
                bi.biPlanes = 1;
                bi.biBitCount = 24;
                bi.biCompression = 0; // BI_RGB

                int stride = ((width * 3 + 3) / 4) * 4;
                int imgSize = stride * height;
                byte[] pixels = new byte[imgSize];

                int lines = NativeWin32.GetDIBits(hdcMem, hBitmap, 0, (uint)height, pixels, ref bi, 0);
                if (lines <= 0) return false;

                using (var fs = new FileStream(bmpPath, FileMode.Create, FileAccess.Write, FileShare.None))
                using (var bw = new BinaryWriter(fs))
                {
                    int headerSize = 14 + 40;
                    bw.Write((byte)'B');
                    bw.Write((byte)'M');
                    bw.Write(headerSize + imgSize);
                    bw.Write((short)0);
                    bw.Write((short)0);
                    bw.Write(headerSize);

                    bw.Write(40);
                    bw.Write(width);
                    bw.Write(height);
                    bw.Write((short)1);
                    bw.Write((short)24);
                    bw.Write(0);
                    bw.Write(imgSize);
                    bw.Write(0);
                    bw.Write(0);
                    bw.Write(0);
                    bw.Write(0);
                    bw.Write(pixels);
                }
                return true;
            }
            catch { return false; }
            finally
            {
                if (hOld != IntPtr.Zero && hdcMem != IntPtr.Zero) NativeWin32.SelectObject(hdcMem, hOld);
                if (hBitmap != IntPtr.Zero) NativeWin32.DeleteObject(hBitmap);
                if (hdcMem != IntPtr.Zero) NativeWin32.DeleteDC(hdcMem);
                if (hdcScreen != IntPtr.Zero) NativeWin32.ReleaseDC(IntPtr.Zero, hdcScreen);
            }
        }

        static bool ConvertBmpToPngViaPowerShell(string bmpPath, string pngPath)
        {
            string script = "Add-Type -AssemblyName System.Drawing; $b = [System.Drawing.Bitmap]::FromFile('" + bmpPath.Replace("'", "''") + "'); $b.Save('" + pngPath.Replace("'", "''") + "', [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose()";
            var psi = new ProcessStartInfo("powershell.exe", "-NoProfile -NonInteractive -Command \"" + script.Replace("\"", "\\\"") + "\"");
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            using (var p = Process.Start(psi))
            {
                if (p == null) return false;
                p.WaitForExit(10000);
                return p.ExitCode == 0;
            }
        }

        public static bool Click(int x, int y, string button, int clicks)
        {
            if (!IsSupported) return false;
            try
            {
                NativeWin32.SetCursorPos(x, y);
                uint downFlag = NativeWin32.MOUSEEVENTF_LEFTDOWN;
                uint upFlag = NativeWin32.MOUSEEVENTF_LEFTUP;
                string btn = (button ?? "left").Trim().ToLowerInvariant();
                if (btn == "right") { downFlag = NativeWin32.MOUSEEVENTF_RIGHTDOWN; upFlag = NativeWin32.MOUSEEVENTF_RIGHTUP; }
                else if (btn == "middle") { downFlag = NativeWin32.MOUSEEVENTF_MIDDLEDOWN; upFlag = NativeWin32.MOUSEEVENTF_MIDDLEUP; }

                int count = clicks > 0 ? clicks : 1;
                for (int i = 0; i < count; i++)
                {
                    NativeWin32.mouse_event(downFlag, 0, 0, 0, UIntPtr.Zero);
                    NativeWin32.mouse_event(upFlag, 0, 0, 0, UIntPtr.Zero);
                    if (i + 1 < count) Thread.Sleep(40);
                }
                return true;
            }
            catch { return false; }
        }

        public static bool TypeText(string text)
        {
            if (!IsSupported || string.IsNullOrEmpty(text)) return IsSupported && string.IsNullOrEmpty(text);
            try
            {
                var inputs = new List<NativeWin32.INPUT>(text.Length * 2);
                for (int i = 0; i < text.Length; i++)
                {
                    char ch = text[i];
                    inputs.Add(MakeUnicodeInput(ch, false));
                    inputs.Add(MakeUnicodeInput(ch, true));
                }
                NativeWin32.INPUT[] arr = inputs.ToArray();
                uint sent = NativeWin32.SendInput((uint)arr.Length, arr, Marshal.SizeOf(typeof(NativeWin32.INPUT)));
                return sent == (uint)arr.Length;
            }
            catch { return false; }
        }

        public static bool SendKey(string keyCombo)
        {
            if (!IsSupported || string.IsNullOrWhiteSpace(keyCombo)) return false;
            try
            {
                string[] parts = keyCombo.Split(new[] { '+' }, StringSplitOptions.RemoveEmptyEntries);
                var vks = new List<ushort>();
                for (int i = 0; i < parts.Length; i++)
                {
                    ushort vk = ParseVirtualKey(parts[i].Trim());
                    if (vk == 0) return false;
                    vks.Add(vk);
                }

                var inputs = new List<NativeWin32.INPUT>();
                for (int i = 0; i < vks.Count; i++) inputs.Add(MakeKeyInput(vks[i], false));
                for (int i = vks.Count - 1; i >= 0; i--) inputs.Add(MakeKeyInput(vks[i], true));

                NativeWin32.INPUT[] arr = inputs.ToArray();
                uint sent = NativeWin32.SendInput((uint)arr.Length, arr, Marshal.SizeOf(typeof(NativeWin32.INPUT)));
                return sent == (uint)arr.Length;
            }
            catch { return false; }
        }

        static NativeWin32.INPUT MakeUnicodeInput(char ch, bool keyUp)
        {
            var inp = new NativeWin32.INPUT();
            inp.type = NativeWin32.INPUT_KEYBOARD;
            inp.U.ki.wVk = 0;
            inp.U.ki.wScan = ch;
            inp.U.ki.dwFlags = NativeWin32.KEYEVENTF_UNICODE | (keyUp ? NativeWin32.KEYEVENTF_KEYUP : 0u);
            return inp;
        }

        static NativeWin32.INPUT MakeKeyInput(ushort vk, bool keyUp)
        {
            var inp = new NativeWin32.INPUT();
            inp.type = NativeWin32.INPUT_KEYBOARD;
            inp.U.ki.wVk = vk;
            inp.U.ki.wScan = 0;
            inp.U.ki.dwFlags = keyUp ? NativeWin32.KEYEVENTF_KEYUP : 0u;
            return inp;
        }

        static ushort ParseVirtualKey(string token)
        {
            string k = (token ?? "").Trim().ToLowerInvariant();
            switch (k)
            {
                case "ctrl": case "control": return 0x11;
                case "shift": return 0x10;
                case "alt": case "menu": return 0x12;
                case "win": case "lwin": case "super": case "cmd": return 0x5B;
                case "enter": case "return": return 0x0D;
                case "tab": return 0x09;
                case "esc": case "escape": return 0x1B;
                case "space": return 0x20;
                case "backspace": case "back": return 0x08;
                case "delete": case "del": return 0x2E;
                case "insert": case "ins": return 0x2D;
                case "home": return 0x24;
                case "end": return 0x23;
                case "pageup": case "pgup": return 0x21;
                case "pagedown": case "pgdn": return 0x22;
                case "left": return 0x25;
                case "up": return 0x26;
                case "right": return 0x27;
                case "down": return 0x28;
            }
            if (k.Length == 1)
            {
                char c = char.ToUpperInvariant(k[0]);
                if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) return (ushort)c;
            }
            if (k.StartsWith("f") && k.Length >= 2)
            {
                int fn;
                if (int.TryParse(k.Substring(1), NumberStyles.Integer, CultureInfo.InvariantCulture, out fn) && fn >= 1 && fn <= 24)
                {
                    return (ushort)(0x6F + fn);
                }
            }
            return 0;
        }

        internal static class NativeWin32
        {
            public const int SM_CXSCREEN = 0;
            public const int SM_CYSCREEN = 1;
            public const int SM_XVIRTUALSCREEN = 76;
            public const int SM_YVIRTUALSCREEN = 77;
            public const int SM_CXVIRTUALSCREEN = 78;
            public const int SM_CYVIRTUALSCREEN = 79;
            public const int SRCCOPY = 0x00CC0020;

            public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
            public const uint MOUSEEVENTF_LEFTUP = 0x0004;
            public const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
            public const uint MOUSEEVENTF_RIGHTUP = 0x0010;
            public const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
            public const uint MOUSEEVENTF_MIDDLEUP = 0x0040;

            public const uint INPUT_KEYBOARD = 1;
            public const uint KEYEVENTF_KEYUP = 0x0002;
            public const uint KEYEVENTF_UNICODE = 0x0004;

            [StructLayout(LayoutKind.Sequential)]
            public struct BITMAPINFOHEADER
            {
                public int biSize;
                public int biWidth;
                public int biHeight;
                public short biPlanes;
                public short biBitCount;
                public int biCompression;
                public int biSizeImage;
                public int biXPelsPerMeter;
                public int biYPelsPerMeter;
                public int biClrUsed;
                public int biClrImportant;
            }

            [StructLayout(LayoutKind.Sequential)]
            public struct INPUT
            {
                public uint type;
                public InputUnion U;
            }

            [StructLayout(LayoutKind.Explicit)]
            public struct InputUnion
            {
                [FieldOffset(0)] public MOUSEINPUT mi;
                [FieldOffset(0)] public KEYBDINPUT ki;
                [FieldOffset(0)] public HARDWAREINPUT hi;
            }

            [StructLayout(LayoutKind.Sequential)]
            public struct MOUSEINPUT
            {
                public int dx;
                public int dy;
                public uint mouseData;
                public uint dwFlags;
                public uint time;
                public IntPtr dwExtraInfo;
            }

            [StructLayout(LayoutKind.Sequential)]
            public struct KEYBDINPUT
            {
                public ushort wVk;
                public ushort wScan;
                public uint dwFlags;
                public uint time;
                public IntPtr dwExtraInfo;
            }

            [StructLayout(LayoutKind.Sequential)]
            public struct HARDWAREINPUT
            {
                public uint uMsg;
                public ushort wParamL;
                public ushort wParamH;
            }

            [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);
            [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
            [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
            [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr hdc);
            [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int nWidth, int nHeight);
            [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr hdc, IntPtr hgdiobj);
            [DllImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool BitBlt(IntPtr hdcDest, int nXDest, int nYDest, int nWidth, int nHeight, IntPtr hdcSrc, int nXSrc, int nYSrc, int dwRop);
            [DllImport("gdi32.dll")] public static extern int GetDIBits(IntPtr hdc, IntPtr hbmp, uint uStartScan, uint cScanLines, byte[] lpvBits, ref BITMAPINFOHEADER lpbi, uint uUsage);
            [DllImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool DeleteObject(IntPtr hObject);
            [DllImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool DeleteDC(IntPtr hdc);

            [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool SetCursorPos(int X, int Y);
            [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
            [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
        }
    }
}
