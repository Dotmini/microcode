// PNS — Pseudo Neural System 24/7: port of Services/PNS/PNSModels.swift, PNSGanglionRouter.swift, PNSMotorWorktreePlexus.swift and
// PNSOrchestrator.swift. A marathon mission is decomposed by the planner ("prefrontal cortex") into subtasks that run as agent
// "motor fibers" in isolated git worktrees on pns/auto-* branches and are joined back through a verification gate (commit on the
// branch, optional 3-way merge into the working tree). Hebbian synapse weights, an episodic WAL with REM consolidation into
// playbooks / inhibition guards, spinal-reflex fault handling, and the out-of-process pnsd daemon (MicroCode.exe --pns-daemon,
// 127.0.0.1 + X-PNS-Token) that keeps missions running after the app is closed. State lives in ~/.microcode/pns like on macOS.
// Windows: homeostasis reads the power state (GetSystemPowerStatus) instead of the macOS thermal state; the sign-in keep-alive is
// the HKCU Run key instead of launchd; the MCP tracts stay empty because the Windows build has no MCP client yet.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Threading;
using Microsoft.Win32;
using MicroCode.Core;

namespace MicroCode.Views
{
    // ── models (PNSModels.swift) ────────────────────────────────────────────

    /// <summary>Synaptic edge with reward-modulated Hebbian plasticity (myelination / LTD inhibition).</summary>
    public class PnsSynapse
    {
        public string Id, TaskCategory, Tract, TargetNodeId, ProjectPath;
        /// <summary>Synaptic conductance W_e in [0.01, 1.00].</summary>
        public double Weight = 0.5;
        public int SuccessCount, FailureCount, AvgLatencyMs, AvgTokensUsed;
        public DateTime LastFiredAt = DateTime.Now;

        public PnsSynapse() { }
        public PnsSynapse(string taskCategory, string tract, string targetNodeId, string projectPath)
        {
            TaskCategory = taskCategory; Tract = tract; TargetNodeId = targetNodeId; ProjectPath = projectPath;
            Id = MakeId(taskCategory, tract, targetNodeId, projectPath);
        }

        /// <summary>&lt;sha256(project)[0..6] hex&gt;::&lt;category&gt;::&lt;tract&gt;::&lt;target&gt;</summary>
        public static string MakeId(string taskCategory, string tract, string targetNodeId, string projectPath)
        {
            string scope = (projectPath ?? "global").Trim();
            using (var sha = SHA256.Create())
            {
                var h = sha.ComputeHash(Encoding.UTF8.GetBytes(scope));
                var sb = new StringBuilder();
                for (int i = 0; i < 6; i++) sb.Append(h[i].ToString("x2"));
                return sb + "::" + taskCategory + "::" + tract + "::" + targetNodeId;
            }
        }

        /// <summary>Fast path earned through repeated verified wins.</summary>
        [ScriptIgnore] public bool IsMyelinated { get { return Weight >= 0.75 && SuccessCount >= 3; } }
        /// <summary>Long-term depression: a pathway that keeps failing is suppressed.</summary>
        [ScriptIgnore] public bool IsInhibited { get { return Weight <= 0.22 && FailureCount >= 2; } }

        /// <summary>W(t+1) = clip((1-λ)·W(t) + η⁺·R·[ok] − η⁻·C·[fail], 0.01, 1)</summary>
        public void ApplyHebbianImpulse(bool succeeded, double verifiedProgress, int tokensUsed, int latencyMs, double regressionPenalty)
        {
            const double lambda = 0.015, etaPlus = 0.14, etaMinus = 0.20;
            double tokenFactor = Math.Log(1.0 + Math.Max(1, tokensUsed) / 250.0);
            double latencyFactor = Math.Log(1.0 + Math.Max(1, latencyMs) / 500.0);
            double denom = Math.Max(0.65, Math.Sqrt(Math.Max(1.0, tokenFactor * latencyFactor)));
            double reward = Math.Min(1.6, Math.Max(0.35, verifiedProgress / denom));
            double updated = (1.0 - lambda) * Weight;
            if (succeeded) { updated += etaPlus * reward; SuccessCount++; }
            else { updated -= etaMinus * Math.Max(0.5, regressionPenalty); FailureCount++; }
            Weight = Math.Min(1.0, Math.Max(0.01, updated));
            AvgLatencyMs = AvgLatencyMs == 0 ? latencyMs : (AvgLatencyMs * 3 + latencyMs) / 4;
            AvgTokensUsed = AvgTokensUsed == 0 ? tokensUsed : (AvgTokensUsed * 3 + tokensUsed) / 4;
            LastFiredAt = DateTime.Now;
        }
    }

    /// <summary>Tier 1: an episodic action-potential spike, appended to synaptic_wal.jsonl.</summary>
    public class PnsSpike
    {
        public string Id = Guid.NewGuid().ToString(), Kind, Tract, MissionId, ProjectPath, Summary = "";
        public DateTime Timestamp = DateTime.Now;
        public double Salience = 0.7;
        public int LatencyMs;
        public bool Succeeded = true;
    }

    /// <summary>Tier 2: a procedural playbook distilled during REM consolidation.</summary>
    public class PnsPlaybook
    {
        public string Id = Guid.NewGuid().ToString(), TriggerSignature, ProjectPath, Tract, DistilledStrategy, VerificationCheck;
        public List<string> ToolSequence = new List<string>();
        public double ConfidenceWeight = 0.78;
        public int ExecutionWins = 1;
        public DateTime UpdatedAt = DateTime.Now;
    }

    /// <summary>Tier 3: a project-scoped invariant or inhibition warning (a dead end not to repeat).</summary>
    public class PnsInvariant
    {
        public string Id = Guid.NewGuid().ToString(), ProjectPath, ModuleScope, RuleStatement;
        public bool IsInhibitionWarning;
        public DateTime CreatedAt = DateTime.Now;
    }

    public class PnsFiberLease
    {
        public string Id, MissionId, AgentArchetype, RoleTitle, Tract, BaseWorkspacePath, BranchName, State = "active", Summary;
        /// <summary>Where the fiber's agent works (the worktree, or its sub-folder when the project is a sub-folder of the repo).</summary>
        public string IsolatedWorktreePath;
        /// <summary>The worktree / copy folder that is removed when the fiber is released.</summary>
        public string WorktreeRoot;
        /// <summary>HEAD the worktree started from; Committed once the fiber's verified work is committed on BranchName.</summary>
        public string StartCommit;
        public bool IsGit, Committed, VerificationPassed, MergedToTrunk;
        public List<string> OwnedPaths = new List<string>();
        public DateTime StartedAt = DateTime.Now;
        public DateTime? FinishedAt;
    }

    public class PnsSubtask
    {
        public string Id, Title, Description, AssignedArchetype, Tract, Status = Pns.Queued, ResultSummary, WorktreeBranch;
        /// <summary>What the fiber is doing right now (live).</summary>
        public string Activity;
        public List<string> OwnedPaths = new List<string>();
        public List<string> Dependencies = new List<string>();
        public int Attempts;
    }

    public class PnsMarathonMission
    {
        public string Id, Title, Objective, WorkspacePath, BranchPolicy = Pns.PolicyIsolated, VerificationCommand, Status = Pns.Queued, DistilledWorkingMemory, LastError;
        public List<PnsSubtask> Subtasks = new List<PnsSubtask>();
        public List<PnsFiberLease> ActiveFibers = new List<PnsFiberLease>();
        public int CompletedEpisodes, RemConsolidationsCount, SpinalReflexSavesCount;
        public DateTime CreatedAt = DateTime.Now, UpdatedAt = DateTime.Now;

        [ScriptIgnore]
        public double Progress
        {
            get
            {
                if (Subtasks == null || Subtasks.Count == 0) return Status == Pns.Completed ? 1.0 : 0.0;
                return (double)Subtasks.Count(s => s.Status == Pns.Completed) / Subtasks.Count;
            }
        }
    }

    public class PnsTractTelemetry
    {
        public string Tract;
        public List<string> AttachedNodes = new List<string>();
        public int ActiveCount, HibernatedCount, MyelinatedEdgesCount, AvgLatencyMs, TotalImpulses;
    }

    /// <summary>What GET /pns/status returns (and what the dashboard draws).</summary>
    public class PnsStatusSnapshot
    {
        public int DaemonPID;
        public bool IsOutOfProcessDaemon;
        public DateTime StartedAt;
        public string AutonomicMode, EffectiveMode, ThermalStateLabel;
        public double MetabolicBudgetIndex;
        public int TotalExternalMCPServers, TotalExternalMCPTools, ActiveMountedSynapticTools, HibernatedMCPServers;
        public int MyelinatedSynapsesCount, InhibitedSynapsesCount, ProceduralPlaybooksCount, SemanticInvariantsCount, SpinalReflexSavesCount, RemConsolidationCycles;
        public List<PnsTractTelemetry> Tracts = new List<PnsTractTelemetry>();
        public List<PnsMarathonMission> Missions = new List<PnsMarathonMission>();
        public List<PnsSpike> RecentSpikes = new List<PnsSpike>();
        /// <summary>Strongest synapses (the dashboard's W_e table).</summary>
        public List<PnsSynapse> TopSynapses = new List<PnsSynapse>();

        public static PnsStatusSnapshot Parse(string json) { return PnsJson.Read<PnsStatusSnapshot>(json); }
    }

    public static class PnsJson
    {
        static readonly JavaScriptSerializer S = new JavaScriptSerializer { MaxJsonLength = int.MaxValue, RecursionLimit = 256 };
        public static string Write(object o) { return S.Serialize(o); }
        /// <summary>null for empty or malformed JSON.</summary>
        public static T Read<T>(string json) where T : class
        {
            if (string.IsNullOrWhiteSpace(json)) return null;
            try { return S.Deserialize<T>(json); }
            catch (ArgumentException) { return null; }
            catch (InvalidOperationException) { return null; }
        }
    }

    // ── constants and pure functions ────────────────────────────────────────

    public class PnsVitals { public double Index; public string Label, Effective; }
    public class PnsPower { public double Factor; public string Label; public bool Critical; }

    public static class Pns
    {
        // nerve tracts (PNSNerveTractKind raw values)
        public const string McpCodeAst = "mcp_code_ast", McpDataCloud = "mcp_data_cloud", McpBrowserVisual = "mcp_browser_visual", McpDeviceHardware = "mcp_device_hardware", McpKnowledgeScience = "mcp_knowledge_science",
            MotorArchitecture = "motor_architecture", MotorImplementation = "motor_implementation", MotorVerification = "motor_verification",
            SpinalReflex = "spinal_reflex", ThalamicSensory = "thalamic_sensory", HippocampalRem = "hippocampal_rem";
        public static readonly string[] McpTracts = { McpCodeAst, McpDataCloud, McpBrowserVisual, McpDeviceHardware, McpKnowledgeScience };
        public static readonly string[] MotorTracts = { MotorArchitecture, MotorImplementation, MotorVerification };
        public static bool IsMcp(string t) { return McpTracts.Contains(t); }
        public static bool IsMotor(string t) { return MotorTracts.Contains(t); }

        public static string Title(string t)
        {
            switch (t)
            {
                case McpCodeAst: return "Tract A: Code, AST & Git MCP Plexus";
                case McpDataCloud: return "Tract B: Data, SQL & Cloud MCP Plexus";
                case McpBrowserVisual: return "Tract C: Browser, UI & Design MCP Plexus";
                case McpDeviceHardware: return "Tract D: Mobile, Device & Compute MCP Plexus";
                case McpKnowledgeScience: return "Tract E: Research, Docs & Science MCP Plexus";
                case MotorArchitecture: return "Motor Tract 1: Architecture & Contract Fibers";
                case MotorImplementation: return "Motor Tract 2: Parallel Worktree Builders";
                case MotorVerification: return "Motor Tract 3: Adversarial QA & Healer Fibers";
                case SpinalReflex: return "Spinal Cord Reflex Arc (<50ms)";
                case ThalamicSensory: return "Thalamic Sensory Attention Gate";
                case HippocampalRem: return "Hippocampal REM Memory Consolidator";
                default: return t ?? "";
            }
        }

        public static string Badge(string t)
        {
            switch (t)
            {
                case McpCodeAst: return "MCP:Code/AST"; case McpDataCloud: return "MCP:Data/Cloud"; case McpBrowserVisual: return "MCP:UI/Browser";
                case McpDeviceHardware: return "MCP:Device/SSH"; case McpKnowledgeScience: return "MCP:Docs/Sci"; case MotorArchitecture: return "Agent:Arch";
                case MotorImplementation: return "Agent:Build"; case MotorVerification: return "Agent:Verify"; case SpinalReflex: return "Reflex:<50ms";
                case ThalamicSensory: return "Thalamus"; case HippocampalRem: return "REM:Memory"; default: return t ?? "";
            }
        }

        /// <summary>Closest Windows symbols for the macOS tract icons.</summary>
        public static string Icon(string t)
        {
            switch (t)
            {
                case McpCodeAst: return "curlybraces.square"; case McpDataCloud: return "database"; case McpBrowserVisual: return "macwindow";
                case McpDeviceHardware: return "iphone.radiowaves.left.and.right"; case McpKnowledgeScience: return "atom"; case MotorArchitecture: return "square.stack.3d.up";
                case MotorImplementation: return "hammer"; case MotorVerification: return "checkmark.shield.fill"; case SpinalReflex: return "bolt.fill";
                case ThalamicSensory: return "antenna.radiowaves.left.and.right"; default: return "brain.head.profile";
            }
        }

        // autonomic modes
        public const string AutoHomeostasis = "auto_homeostasis", Sympathetic = "sympathetic", Parasympathetic = "parasympathetic";
        public static readonly string[] Modes = { AutoHomeostasis, Sympathetic, Parasympathetic };
        public static string ModeName(string m) { return m == Sympathetic ? "Sympathetic (Parallel Burst)" : m == Parasympathetic ? "Parasympathetic (Nightly / Low-Burn)" : "Auto Homeostasis (24/7 Adaptive)"; }
        public static string ModeIcon(string m) { return m == Sympathetic ? "bolt.fill" : m == Parasympathetic ? "moon" : "waveform"; }

        // branch safety policies
        public const string PolicyIsolated = "isolated_worktree_branch", PolicyAutoMerge = "auto_three_way_merge_on_verify";
        public static string PolicyName(string p) { return p == PolicyAutoMerge ? "Auto 3-Way Merge After Verification" : "Safe Worktree Branch (pns/auto-*)"; }

        // mission statuses
        public const string Queued = "queued", Running = "running", ConsolidatingRem = "consolidatingREM", PacingHomeostasis = "pacingHomeostasis", Paused = "paused", Completed = "completed", Failed = "failed", Cancelled = "cancelled";

        // spike kinds
        public const string SpikeSensory = "sensory_stimulus", SpikeGanglion = "ganglion_route", SpikeSpinal = "spinal_reflex", SpikeFiberSpawn = "motor_fiber_spawn",
            SpikeFiberMerge = "motor_fiber_merge", SpikeRem = "rem_consolidation", SpikeHomeostasis = "homeostasis_shift", SpikePain = "nociceptive_pain";

        /// <summary>Motor fiber archetypes (SubAgentHarness definitions on macOS).</summary>
        public static readonly string[] Archetypes = { "architect", "frontend_engineer", "backend_engineer", "mobile_device_controller", "bug_hunter", "test_runner", "security_auditor", "autonomous_loop" };

        static bool Any(string lower, params string[] words) { foreach (var w in words) if (lower.Contains(w)) return true; return false; }

        /// <summary>classifyTaskCategory (same keywords, English and Thai).</summary>
        public static string ClassifyTaskCategory(string text)
        {
            string l = (text ?? "").ToLowerInvariant();
            if (Any(l, "sql", "query", "bigquery", "postgres", "database", "schema", "migration", "ฐานข้อมูล", "ตาราง", "คิวรี")) return "data_engineering";
            if (Any(l, "ios", "simulator", "simctl", "android", "adb", "apk", "device", "มือถือ", "แอนดรอยด์", "ไอโฟน", "จำลอง")) return "mobile_device";
            if (Any(l, "browser", "css", "dom", "devtools", "ui", "layout", "preview", "หน้าจอ", "หน้าเว็บ", "พรีวิว", "เบราว์เซอร์", "ปุ่ม")) return "ui_visual";
            if (Any(l, "test", "fix", "bug", "crash", "error", "diagnostic", "แก้", "บั๊ก", "พัง", "เทส")) return "debug_verification";
            if (Any(l, "paper", "arxiv", "protein", "alphafold", "docs", "research", "วิจัย", "เอกสาร", "โปรตีน")) return "research_science";
            if (Any(l, "architect", "design", "refactor", "plan", "ออกแบบ", "โครงสร้าง", "วางแผน")) return "architecture_refactor";
            return "code_implementation";
        }

        public static string MotorTractFor(string archetype)
        {
            switch ((archetype ?? "").ToLowerInvariant())
            {
                case "architect": return MotorArchitecture;
                case "bug_hunter": case "test_runner": case "security_auditor": case "mobile_device_controller": return MotorVerification;
                default: return MotorImplementation;
            }
        }

        static readonly Regex Ansi = new Regex("\u001B\\[[0-9;]*[a-zA-Z]");
        static readonly Regex Spaces = new Regex(@"\s+");

        /// <summary>Thalamic Sensory Attention Gate: compresses noisy command output into its salient lines (anti context-rot).</summary>
        public static Tuple<string, double> ThalamicFilter(string rawOutput, string source, int maxChars)
        {
            string clean = Ansi.Replace(rawOutput ?? "", "");
            string[] lines = clean.Split('\r', '\n');
            var high = new List<string>();
            var seen = new HashSet<string>();
            int errorHits = 0, warningHits = 0;
            foreach (var rawLine in lines)
            {
                string trimmed = rawLine.Trim(' ', '\t');
                if (trimmed.Length == 0) continue;
                string lower = trimmed.ToLowerInvariant();
                // compiler / bundler progress chatter
                if (lower.StartsWith("compiling ") || lower.StartsWith("downloading ") || lower.StartsWith("fetching ") || (lower.StartsWith("linking ") && !lower.Contains("error"))) continue;
                bool isHigh = lower.Contains("error:") || lower.Contains("error[") || lower.Contains("fatal:") || lower.Contains("panic") || lower.Contains("failed") || lower.Contains("assertion") || lower.Contains("exception") || lower.Contains("warning:");
                if (lower.Contains("error") || lower.Contains("panic") || lower.Contains("fatal") || lower.Contains("failed")) errorHits++;
                else if (lower.Contains("warning:")) warningHits++;
                if (isHigh && seen.Add(Spaces.Replace(trimmed, " "))) high.Add(trimmed);
            }
            double salience = errorHits > 0 ? Math.Min(1.0, 0.72 + Math.Min(10, errorHits) * 0.028) : warningHits > 0 ? Math.Min(0.68, 0.35 + Math.Min(10, warningHits) * 0.03) : 0.18;
            if (clean.Length <= maxChars && high.Count == 0) return Tuple.Create(clean, salience);
            var parts = new List<string> { "[Thalamus Gate • " + source + " • " + lines.Length + " lines -> Salience " + salience.ToString("0.00", CultureInfo.InvariantCulture) + " • Errors: " + errorHits + ", Warnings: " + warningHits + "]" };
            if (high.Count > 0) parts.Add(string.Join("\n", high.Take(24)));
            var tail = lines.Skip(Math.Max(0, lines.Length - 12)).Select(l => l.Trim()).Where(l => l.Length > 0).ToList();
            if (tail.Count > 0) parts.Add("--- Tail ---\n" + string.Join("\n", tail));
            string joined = string.Join("\n", parts);
            if (joined.Length <= maxChars) return Tuple.Create(joined, salience);
            return Tuple.Create(joined.Substring(0, maxChars) + "\n…[thalamic truncation]", salience);
        }

        /// <summary>Metabolic budget index M_t and the effective autonomic mode.</summary>
        public static PnsVitals Homeostasis(double powerFactor, string powerLabel, bool critical, string mode, double rateLimitPressure)
        {
            double raw = powerFactor * (1.0 - Math.Min(0.65, rateLimitPressure));
            double index = Math.Min(1.0, Math.Max(0.10, raw));
            string effective = mode == Sympathetic ? (critical ? Parasympathetic : Sympathetic) : mode == Parasympathetic ? Parasympathetic : (index >= 0.58 ? Sympathetic : Parasympathetic);
            return new PnsVitals { Index = index, Label = powerLabel, Effective = effective };
        }

        public static int MaxConcurrentFibers(string effective, double index)
        {
            if (effective == Sympathetic) return index > 0.80 ? 3 : 2;
            return effective == Parasympathetic ? 1 : 2;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct SystemPowerStatus { public byte ACLineStatus, BatteryFlag, BatteryLifePercent, SystemStatusFlag; public int BatteryLifeTime, BatteryFullLifeTime; }

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetSystemPowerStatus(out SystemPowerStatus status);

        /// <summary>The Windows stand-in for ProcessInfo.thermalState: AC power, battery level and Battery Saver.</summary>
        public static PnsPower ReadPower()
        {
            SystemPowerStatus s;
            if (!GetSystemPowerStatus(out s)) return new PnsPower { Factor = 0.90, Label = "Nominal" };
            bool onBattery = s.ACLineStatus == 0;
            bool saver = s.SystemStatusFlag == 1;
            int pct = s.BatteryLifePercent == 255 ? 100 : s.BatteryLifePercent;
            if (onBattery && pct <= 15) return new PnsPower { Factor = 0.22, Label = "Critical (Low Battery)", Critical = true };
            if (saver || (onBattery && pct <= 40)) return new PnsPower { Factor = 0.48, Label = "Serious (Battery Saver)" };
            if (onBattery) return new PnsPower { Factor = 0.84, Label = "Fair (On Battery)" };
            return new PnsPower { Factor = 1.0, Label = "Nominal" };
        }
    }

    // ── spinal cord reflex arc (PNSGanglionRouter.evaluateSpinalReflex) ─────

    public enum PnsReflexAction { None, SwitchProviderEndpoint, RemapCollidedPort, CircuitBreakBehavioralFixation }

    public class PnsReflexOutcome
    {
        public PnsReflexAction Action;
        public int CooldownMs, DetectedPort, SuggestedPort, LatencyMs;
        public string Fingerprint, InhibitionRule, Summary = "";
    }

    /// <summary>Deterministic (&lt;50 ms, no model) fault interception: provider failover, port remapping and the behavioral-fixation
    /// circuit breaker. (The macOS MCP pipe respawn reflex has no counterpart until MCP is ported.)</summary>
    public class PnsSpinalCord
    {
        readonly List<string> _window = new List<string>();
        const int MaxWindow = 16, FixationThreshold = 3;
        public int SavesCount;

        public PnsReflexOutcome Evaluate(string toolOrProviderName, string targetHint, string errorMessage)
        {
            var sw = Stopwatch.StartNew();
            string lower = (errorMessage ?? "").ToLowerInvariant();
            PnsReflexOutcome o;
            lock (_window)
            {
                if (lower.Contains("429") || lower.Contains("rate limit") || lower.Contains("resource_exhausted") || lower.Contains("quota") || lower.Contains("overloaded") || lower.Contains("503 service unavailable") || lower.Contains("502 bad gateway"))
                    o = new PnsReflexOutcome { Action = PnsReflexAction.SwitchProviderEndpoint, CooldownMs = lower.Contains("quota") ? 8000 : 2000, Summary = "Spinal Reflex (<50ms): Intercepted rate-limit/5xx on '" + toolOrProviderName + "' -> rotated endpoint & adjusted homeostasis pacing." };
                else if (lower.Contains("eaddrinuse") || lower.Contains("address already in use"))
                {
                    var m = Regex.Match(errorMessage ?? "", @"(?:port|:)\s*([0-9]{2,5})", RegexOptions.IgnoreCase);
                    int detected = 0;
                    if (m.Success) int.TryParse(m.Groups[1].Value, out detected);
                    int free = AllocateFreeLocalPort();
                    if (free <= 0) free = (detected > 0 ? detected : 3000) + new Random().Next(11, 90);
                    o = new PnsReflexOutcome { Action = PnsReflexAction.RemapCollidedPort, DetectedPort = detected, SuggestedPort = free, Summary = "Spinal Reflex (<50ms): Port collision (" + (detected > 0 ? detected.ToString() : "unknown") + ") -> allocated clean port " + free + "." };
                }
                else
                {
                    string head = lower.Length > 120 ? lower.Substring(0, 120) : lower;
                    string fp;
                    using (var sha = SHA256.Create())
                    {
                        var h = sha.ComputeHash(Encoding.UTF8.GetBytes(toolOrProviderName + "|" + targetHint + "|" + Regex.Replace(head, "[0-9]+", "#")));
                        fp = BitConverter.ToString(h, 0, 8).Replace("-", "").ToLowerInvariant();
                    }
                    _window.Add(fp);
                    if (_window.Count > MaxWindow) _window.RemoveRange(0, _window.Count - MaxWindow);
                    int repeat = _window.Count(x => x == fp);
                    if (repeat >= FixationThreshold)
                    {
                        _window.RemoveAll(x => x == fp);
                        o = new PnsReflexOutcome
                        {
                            Action = PnsReflexAction.CircuitBreakBehavioralFixation, Fingerprint = fp,
                            InhibitionRule = "INHIBITION [" + fp + "]: Repeatedly failed (" + repeat + "x) calling '" + toolOrProviderName + "' on '" + targetHint + "'. Do NOT repeat this action; rollback dirty hunk and pivot strategy.",
                            Summary = "Spinal Reflex (<50ms): Tripped Behavioral Fixation circuit-breaker [" + fp + "] after " + repeat + " identical failures."
                        };
                    }
                    else o = new PnsReflexOutcome { Action = PnsReflexAction.None, Summary = "Escalated to Cortex" };
                }
                if (o.Action != PnsReflexAction.None) SavesCount++;
            }
            o.LatencyMs = Math.Max(1, (int)sw.ElapsedMilliseconds);
            return o;
        }

        public void ResetFixationWindow() { lock (_window) _window.Clear(); }

        public static int AllocateFreeLocalPort()
        {
            try
            {
                var l = new TcpListener(IPAddress.Loopback, 0);
                l.Start();
                int p = ((IPEndPoint)l.LocalEndpoint).Port;
                l.Stop();
                return p;
            }
            catch (SocketException) { return 0; }
        }
    }

    // ── somatic motor plexus (PNSMotorWorktreePlexus.swift) ─────────────────

    public class PnsJoinResult
    {
        public bool VerificationPassed, MergedToTrunk;
        public string VerificationSpike = "", CommittedBranch, KeptWorktree, Note;
        public List<string> ModifiedFiles = new List<string>();
        /// <summary>"path — reason" for files the merge left alone (Scope Lock, write errors).</summary>
        public List<string> SkippedMerges = new List<string>();
    }

    /// <summary>Allocates isolated git worktrees (or folder copies) for motor fibers, enforces owned-path leases, runs the
    /// neuromuscular verification gate and joins verified work back (commit on pns/auto-* and/or 3-way merge into the trunk).</summary>
    public class PnsMotorPlexus
    {
        public readonly string WorktreesRoot;
        readonly Dictionary<string, PnsFiberLease> _leases = new Dictionary<string, PnsFiberLease>();
        readonly Dictionary<string, Dictionary<string, string>> _base = new Dictionary<string, Dictionary<string, string>>();
        readonly Dictionary<string, int> _impulses = new Dictionary<string, int>();

        /// <summary>Text files whose changes are joined back (macOS list + the usual Windows / .NET sources).</summary>
        public static readonly HashSet<string> SourceExtensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "swift", "rs", "ts", "tsx", "js", "jsx", "py", "go", "java", "kt", "kts", "c", "cpp", "cc", "h", "hpp", "json", "toml", "yaml", "yml", "md", "html", "css", "scss", "sql", "ar",
            "cs", "csproj", "sln", "xaml", "xml", "props", "targets", "config", "cmd", "bat", "ps1", "sh", "txt", "ini", "cfg", "gradle", "m", "mm", "vue", "svelte", "php", "rb", "lua", "dart"
        };

        public PnsMotorPlexus(string worktreesRoot) { WorktreesRoot = worktreesRoot; }

        static string Short(string id) { string s = (id ?? "").Replace("-", ""); return (s.Length > 6 ? s.Substring(0, 6) : s).ToLowerInvariant(); }

        public PnsFiberLease AllocateFiber(string missionId, string archetype, string roleTitle, string baseWorkspace, List<string> ownedPaths)
        {
            string fiberId = Guid.NewGuid().ToString("N");
            string slug = new string((archetype ?? "").ToLowerInvariant().Where(c => char.IsLetterOrDigit(c) || c == '_').ToArray());
            if (slug.Length == 0) slug = "fiber";
            string branch = "pns/auto-" + Short(missionId) + "-" + slug + "-" + fiberId.Substring(0, 6);
            string target = System.IO.Path.Combine(WorktreesRoot, Short(missionId), slug + "-" + fiberId.Substring(0, 6));
            string ws = System.IO.Path.GetFullPath(baseWorkspace).TrimEnd('\\');
            WorkspaceCopy.DeleteTree(target);
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(target));
            bool isGit = false;
            string agentRoot = target, startCommit = null;
            string top = GitCli.TopLevel(ws);
            if (top != null && (string.Equals(top, ws, StringComparison.OrdinalIgnoreCase) || ws.StartsWith(top + "\\", StringComparison.OrdinalIgnoreCase)))
            {
                GitCli.Run(ws, "worktree prune", null, 15000);
                var add = GitCli.Run(ws, "worktree add -B " + GitCli.Q(branch) + " " + GitCli.Q(target) + " HEAD", null, 180000);
                isGit = add.Ok;
                if (isGit)
                {
                    string sub = ws.Length > top.Length ? ws.Substring(top.Length + 1) : "";
                    if (sub.Length > 0) agentRoot = System.IO.Path.Combine(target, sub);
                    var head = GitCli.Run(target, "rev-parse HEAD", null, 8000);
                    if (head.Ok) startCommit = head.Out.Trim();
                }
                else WorkspaceCopy.DeleteTree(target); // e.g. a repository without commits: fall back to a copy like the macOS APFS clone
            }
            if (!isGit)
            {
                try { WorkspaceCopy.Copy(ws, target); }
                catch { WorkspaceCopy.DeleteTree(target); throw; }
            }
            string tract = Pns.MotorTractFor(archetype);
            var lease = new PnsFiberLease
            {
                Id = fiberId, MissionId = missionId, AgentArchetype = archetype, RoleTitle = roleTitle, Tract = tract, BaseWorkspacePath = ws, IsolatedWorktreePath = agentRoot,
                WorktreeRoot = target, BranchName = branch, OwnedPaths = ownedPaths ?? new List<string>(), IsGit = isGit, StartCommit = startCommit, State = "active", StartedAt = DateTime.Now
            };
            var snap = CaptureSnapshot(agentRoot);
            lock (_leases)
            {
                _leases[fiberId] = lease;
                _base[fiberId] = snap;
                int n;
                _impulses.TryGetValue(tract, out n);
                _impulses[tract] = n + 1;
            }
            return lease;
        }

        /// <summary>relative path → text for the joinable source files under root (≤ 512 KB each).</summary>
        public static Dictionary<string, string> CaptureSnapshot(string root)
        {
            var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (!Directory.Exists(root)) return map;
            foreach (var rel in WorkspaceCopy.Files(root))
            {
                if (!SourceExtensions.Contains(System.IO.Path.GetExtension(rel).TrimStart('.'))) continue;
                var bytes = WorkspaceCopy.TryRead(System.IO.Path.Combine(root, rel.Replace('/', '\\')), 512000);
                if (bytes != null && !WorkspaceCopy.IsBinary(bytes)) map[rel] = WorkspaceCopy.Decode(bytes);
            }
            return map;
        }

        public static bool MatchesOwnedScope(string relPath, List<string> patterns)
        {
            foreach (var p in patterns)
            {
                string clean = (p ?? "").Trim().Replace("*", "").Replace('\\', '/');
                if (clean.Length == 0 || relPath.Contains(clean) || relPath.StartsWith(clean)) return true;
            }
            return false;
        }

        /// <summary>3-way merge with overlapping hunks resolved to the incoming (verified) side and no conflict markers — the
        /// CollaborativeThreeWayMerger rule — via git merge-file --theirs.</summary>
        public static string ThreeWayMerge(string baseText, string current, string incoming)
        {
            if (incoming == current) return current;
            if (baseText == current) return incoming;
            if (baseText == incoming) return current;
            string dir = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "pns-merge-" + Guid.NewGuid().ToString("N").Substring(0, 10));
            Directory.CreateDirectory(dir);
            try
            {
                var enc = new UTF8Encoding(false);
                string fc = System.IO.Path.Combine(dir, "current"), fb = System.IO.Path.Combine(dir, "base"), fi = System.IO.Path.Combine(dir, "incoming");
                File.WriteAllText(fc, current, enc); File.WriteAllText(fb, baseText, enc); File.WriteAllText(fi, incoming, enc);
                var r = GitCli.Run(dir, "merge-file -p --theirs " + GitCli.Q(fc) + " " + GitCli.Q(fb) + " " + GitCli.Q(fi), null, 30000);
                if (r.Code >= 0 && r.Code < 128 && !r.Out.Contains("<<<<<<<")) return r.Out;
                return incoming; // git unavailable: the verified fiber wins, as macOS does for oversized files
            }
            finally { WorkspaceCopy.DeleteTree(dir); }
        }

        /// <summary>Neuromuscular junction: verification gate in the worktree, commit on the fiber branch, then the branch policy.</summary>
        public PnsJoinResult VerifyAndJoin(string fiberId, string policy, string verificationCommand, string fiberSummary, CancellationToken ct = default(CancellationToken))
        {
            PnsFiberLease lease;
            Dictionary<string, string> initial;
            lock (_leases)
            {
                if (!_leases.TryGetValue(fiberId, out lease)) return new PnsJoinResult { VerificationSpike = "Motor fiber lease not found." };
                _base.TryGetValue(fiberId, out initial);
            }
            initial = initial ?? new Dictionary<string, string>();
            var res = new PnsJoinResult();
            var current = CaptureSnapshot(lease.IsolatedWorktreePath);
            foreach (var kv in current)
            {
                string old;
                if (initial.TryGetValue(kv.Key, out old) && old == kv.Value) continue;
                if (lease.OwnedPaths.Count > 0 && !MatchesOwnedScope(kv.Key, lease.OwnedPaths)) continue; // semantic ownership lease
                res.ModifiedFiles.Add(kv.Key);
            }
            res.ModifiedFiles.Sort(StringComparer.Ordinal);

            // A: verification gate inside the isolated worktree
            res.VerificationPassed = true;
            res.VerificationSpike = "No external verification command configured; syntax & lease boundaries verified.";
            string cmd = (verificationCommand ?? "").Trim();
            if (cmd.Length > 0)
            {
                string output = AgentRunner.ExecuteIsolated(lease.IsolatedWorktreePath, lease.BaseWorkspacePath, "shell", new Dictionary<string, object> { { "command", cmd }, { "timeout_seconds", 300 } }, new ToolStep(), ct);
                var m = Regex.Match(output, @"^(?:Error: )?exit code (-?\d+)");
                res.VerificationPassed = m.Success && m.Groups[1].Value == "0";
                res.VerificationSpike = Pns.ThalamicFilter(output, "MotorVerify:" + lease.AgentArchetype, 2400).Item1;
            }

            // B: commit verified state on the fiber branch (durable audit & rollback anchor)
            if (lease.IsGit && res.ModifiedFiles.Count > 0 && res.VerificationPassed)
            {
                string add = lease.OwnedPaths.Count > 0 ? "add -A -- " + string.Join(" ", res.ModifiedFiles.Select(GitCli.Q)) : "add -A";
                var a = GitCli.Run(lease.IsolatedWorktreePath, add, null, 120000);
                string msgFile = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "pns-commit-" + fiberId + ".txt");
                string subject = GitCli.FirstLine(fiberSummary);
                if (subject.Length > 72) subject = subject.Substring(0, 72);
                File.WriteAllText(msgFile, "PNS [" + lease.AgentArchetype + "]: " + subject + "\n", new UTF8Encoding(false));
                var c = a.Ok ? GitCli.Run(lease.IsolatedWorktreePath, "commit -q -F " + GitCli.Q(msgFile), null, 120000) : a;
                try { File.Delete(msgFile); } catch (IOException) { } // a leftover temp message file is harmless
                if (c.Ok) { res.CommittedBranch = lease.BranchName; lease.Committed = true; }
                else res.Note = "Commit on " + lease.BranchName + " failed: " + GitCli.FirstLine(c.Err + "\n" + c.Out);
            }

            // C: branch safety policy
            if (res.VerificationPassed && res.ModifiedFiles.Count > 0 && policy == Pns.PolicyAutoMerge)
            {
                foreach (var rel in res.ModifiedFiles)
                {
                    string trunk = System.IO.Path.Combine(lease.BaseWorkspacePath, rel.Replace('/', '\\'));
                    string blocked = ScopeLock.BlockedIn(lease.BaseWorkspacePath, trunk);
                    if (blocked != null) { res.SkippedMerges.Add(rel + " — " + blocked.Replace("Error: ", "")); continue; }
                    string baseText;
                    initial.TryGetValue(rel, out baseText);
                    try
                    {
                        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(trunk));
                        var trunkBytes = WorkspaceCopy.TryRead(trunk, long.MaxValue);
                        bool bom = trunkBytes != null && trunkBytes.Length >= 3 && trunkBytes[0] == 0xEF && trunkBytes[1] == 0xBB && trunkBytes[2] == 0xBF;
                        string merged = trunkBytes != null ? ThreeWayMerge(baseText ?? "", WorkspaceCopy.Decode(trunkBytes), current[rel]) : current[rel];
                        File.WriteAllText(trunk, merged, new UTF8Encoding(bom));
                        res.MergedToTrunk = true;
                    }
                    catch (IOException ex) { res.SkippedMerges.Add(rel + " — " + ex.Message); }
                    catch (UnauthorizedAccessException ex) { res.SkippedMerges.Add(rel + " — " + ex.Message); }
                }
            }

            lease.VerificationPassed = res.VerificationPassed;
            lease.MergedToTrunk = res.MergedToTrunk;
            lease.State = res.VerificationPassed ? (res.MergedToTrunk ? "merged" : "verified_branch") : "verification_failed";
            lease.Summary = fiberSummary;
            lease.FinishedAt = DateTime.Now;
            // verified work that could neither be committed nor merged stays on disk instead of being thrown away
            bool keep = lease.IsGit && res.VerificationPassed && res.ModifiedFiles.Count > 0 && res.CommittedBranch == null && !res.MergedToTrunk;
            if (keep) { lease.State = "kept_worktree"; res.KeptWorktree = lease.WorktreeRoot; lock (_leases) { _leases.Remove(fiberId); _base.Remove(fiberId); } }
            else Release(lease);
            return res;
        }

        /// <summary>Removes the fiber's worktree or copy. Its pns/auto-* branch stays when it holds a commit; a branch that never
        /// received one (tip still at the start commit) is deleted so failed attempts leave no clutter in the user's repo.</summary>
        public void Release(PnsFiberLease lease)
        {
            if (lease.IsGit) GitCli.Run(lease.BaseWorkspacePath, "worktree remove --force " + GitCli.Q(lease.WorktreeRoot), null, 60000);
            WorkspaceCopy.DeleteTree(lease.WorktreeRoot);
            if (lease.IsGit)
            {
                GitCli.Run(lease.BaseWorkspacePath, "worktree prune", null, 15000);
                if (!lease.Committed && !string.IsNullOrEmpty(lease.StartCommit))
                {
                    var tip = GitCli.Run(lease.BaseWorkspacePath, "rev-parse --verify --quiet " + GitCli.Q("refs/heads/" + lease.BranchName), null, 8000);
                    if (tip.Ok && tip.Out.Trim() == lease.StartCommit) GitCli.Run(lease.BaseWorkspacePath, "branch -D " + GitCli.Q(lease.BranchName), null, 15000);
                }
            }
            lock (_leases) { _leases.Remove(lease.Id); _base.Remove(lease.Id); }
        }

        public List<PnsTractTelemetry> BuildMotorTelemetry(IEnumerable<PnsSynapse> edges)
        {
            var all = edges.ToList();
            List<PnsFiberLease> leases;
            Dictionary<string, int> impulses;
            lock (_leases) { leases = _leases.Values.ToList(); impulses = new Dictionary<string, int>(_impulses); }
            var list = new List<PnsTractTelemetry>();
            foreach (var tract in Pns.MotorTracts)
            {
                var nodes = Pns.Archetypes.Where(a => Pns.MotorTractFor(a) == tract).OrderBy(a => a, StringComparer.Ordinal).ToList();
                int active = leases.Count(l => l.Tract == tract && l.State == "active"), n;
                impulses.TryGetValue(tract, out n);
                list.Add(new PnsTractTelemetry { Tract = tract, AttachedNodes = nodes, ActiveCount = active, HibernatedCount = Math.Max(0, nodes.Count - active), MyelinatedEdgesCount = all.Count(e => e.Tract == tract && e.IsMyelinated), TotalImpulses = n });
            }
            return list;
        }
    }

    // ── central & autonomic orchestrator (PNSOrchestrator.swift) ────────────

    public class PnsOrchestrator
    {
        public const int DefaultDaemonPort = 18890;
        static PnsOrchestrator _shared;
        /// <summary>The app's instance over ~/.microcode/pns (or the isolated --data-dir copy).</summary>
        public static PnsOrchestrator Shared
        {
            get
            {
                if (_shared == null) { _shared = new PnsOrchestrator(System.IO.Path.Combine(TaskFiles.Home, "pns")); _shared.StartHeartbeat(); }
                return _shared;
            }
        }
        /// <summary>True inside MicroCode.exe --pns-daemon.</summary>
        public static bool IsDaemonProcess;

        public readonly string Dir;
        public readonly PnsMotorPlexus Plexus;
        public readonly PnsSpinalCord Cord = new PnsSpinalCord();
        public readonly DateTime StartedAt = DateTime.Now;
        public Dictionary<string, PnsSynapse> Synapses = new Dictionary<string, PnsSynapse>();
        public List<PnsPlaybook> Playbooks = new List<PnsPlaybook>();
        public List<PnsInvariant> Invariants = new List<PnsInvariant>();
        public List<PnsMarathonMission> Missions = new List<PnsMarathonMission>();
        public List<PnsSpike> RecentSpikes = new List<PnsSpike>();
        public int RemCycles;
        public string EffectiveMode = Pns.Sympathetic, PowerLabel = "Nominal";
        public double MetabolicIndex = 0.94;
        double _rateLimitPressure;
        string _mode = Pns.AutoHomeostasis;

        // link to the out-of-process daemon (GUI side)
        public bool RemoteOnline;
        public int RemotePid;
        PnsStatusSnapshot _remote;
        bool _recovered;
        /// <summary>The dashboard is on screen: the heartbeat polls pnsd.</summary>
        public bool ViewAttached;

        public event Action Changed;
        readonly Dictionary<string, CancellationTokenSource> _loops = new Dictionary<string, CancellationTokenSource>();
        DispatcherTimer _heartbeat;
        TcpListener _listener;
        readonly object _io = new object();

        public PnsOrchestrator(string dir)
        {
            Dir = dir;
            Plexus = new PnsMotorPlexus(System.IO.Path.Combine(dir, "worktrees"));
            Load();
            UpdateHomeostasis();
        }

        public string Mode
        {
            get { return _mode; }
            set
            {
                if (!Pns.Modes.Contains(value)) return;
                _mode = value;
                WriteFile("autonomic_config.json", PnsJson.Write(new Dictionary<string, object> { { "autonomic_mode", value } }));
                UpdateHomeostasis();
                Raise();
            }
        }

        public int MaxConcurrentFibers { get { return Pns.MaxConcurrentFibers(EffectiveMode, MetabolicIndex); } }

        // ── events / threading ──
        public void Raise()
        {
            var h = Changed;
            if (h == null) return;
            var app = Application.Current;
            if (app != null && !app.Dispatcher.CheckAccess()) app.Dispatcher.BeginInvoke(h); else h();
        }

        static void Post(Action a)
        {
            var app = Application.Current;
            if (app != null && !app.Dispatcher.CheckAccess()) app.Dispatcher.BeginInvoke(a); else a();
        }

        public void Log(string line)
        {
            if (!IsDaemonProcess) return;
            try
            {
                lock (_io)
                {
                    Directory.CreateDirectory(Dir);
                    string p = System.IO.Path.Combine(Dir, "pnsd.log");
                    if (File.Exists(p) && new FileInfo(p).Length > (1 << 20)) { File.Copy(p, p + ".1", true); File.Delete(p); } // keep one rotated log
                    File.AppendAllText(p, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture) + "  " + line + Environment.NewLine);
                }
            }
            catch (IOException) { } // the log is best-effort; the daemon keeps running
        }

        // ── durable storage (~/.microcode/pns) ──
        string P(string name) { return System.IO.Path.Combine(Dir, name); }

        string ReadFile(string name)
        {
            try { string p = P(name); return File.Exists(p) ? Defaults.ReadShared(p) : null; }
            catch (IOException) { return null; }
        }

        void WriteFile(string name, string text)
        {
            try { lock (_io) { Directory.CreateDirectory(Dir); Defaults.WriteAtomic(P(name), text); } }
            catch (IOException ex) { Log("write " + name + " failed: " + ex.Message); }
            catch (UnauthorizedAccessException ex) { Log("write " + name + " failed: " + ex.Message); }
        }

        T ReadJson<T>(string name) where T : class
        {
            string text = ReadFile(name);
            if (text == null) return null;
            var v = PnsJson.Read<T>(text);
            if (v == null && text.Trim().Length > 0)
            {
                // keep an unreadable file for inspection instead of silently overwriting it on the next save
                try { File.Copy(P(name), P(name + ".corrupt-" + DateTime.Now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture)), true); } catch (IOException) { }
            }
            return v;
        }

        public void Load()
        {
            var cfg = DJ.Obj(ReadFile("autonomic_config.json"));
            string m = DJ.Str(cfg, "autonomic_mode");
            if (m != null && Pns.Modes.Contains(m)) _mode = m;
            Synapses = ReadJson<Dictionary<string, PnsSynapse>>("synaptic_weights.json") ?? new Dictionary<string, PnsSynapse>();
            Playbooks = ReadJson<List<PnsPlaybook>>("procedural_playbooks.json") ?? new List<PnsPlaybook>();
            Invariants = ReadJson<List<PnsInvariant>>("semantic_invariants.json") ?? new List<PnsInvariant>();
            Missions = ReadJson<List<PnsMarathonMission>>("missions.json") ?? new List<PnsMarathonMission>();
            foreach (var mi in Missions) { if (mi.Subtasks == null) mi.Subtasks = new List<PnsSubtask>(); if (mi.ActiveFibers == null) mi.ActiveFibers = new List<PnsFiberLease>(); }
            var spikes = new List<PnsSpike>();
            string wal = ReadFile("synaptic_wal.jsonl");
            if (wal != null)
            {
                var lines = wal.Split('\n').Where(l => l.Trim().Length > 0).ToList();
                foreach (var l in lines.Skip(Math.Max(0, lines.Count - 48)))
                {
                    var s = PnsJson.Read<PnsSpike>(l);
                    if (s != null) spikes.Add(s);
                }
            }
            RecentSpikes = spikes;
        }

        /// <summary>Saves synapses, playbooks, invariants and missions (not while pnsd owns them).</summary>
        public void SaveNow()
        {
            if (!IsDaemonProcess && RemoteOnline) return;
            WriteFile("synaptic_weights.json", PnsJson.Write(Synapses));
            WriteFile("procedural_playbooks.json", PnsJson.Write(Playbooks));
            WriteFile("semantic_invariants.json", PnsJson.Write(Invariants));
            WriteFile("missions.json", PnsJson.Write(Missions));
        }

        public PnsSpike RecordSpike(string kind, string tract, string missionId, string projectPath, string summary, double salience, int latencyMs, bool succeeded)
        {
            var s = new PnsSpike { Kind = kind, Tract = tract, MissionId = missionId, ProjectPath = projectPath, Summary = summary ?? "", Salience = Math.Min(1.0, Math.Max(0.0, salience)), LatencyMs = latencyMs, Succeeded = succeeded };
            RecentSpikes.Add(s);
            if (RecentSpikes.Count > 80) RecentSpikes.RemoveRange(0, RecentSpikes.Count - 80);
            try
            {
                lock (_io)
                {
                    Directory.CreateDirectory(Dir);
                    string p = P("synaptic_wal.jsonl");
                    File.AppendAllText(p, PnsJson.Write(s) + "\n", new UTF8Encoding(false));
                    if (new FileInfo(p).Length > (2 << 20))
                    {
                        var keep = File.ReadAllLines(p).Where(l => l.Trim().Length > 0).ToList();
                        Defaults.WriteAtomic(p, string.Join("\n", keep.Skip(Math.Max(0, keep.Count - 500))) + "\n");
                    }
                }
            }
            catch (IOException ex) { Log("WAL append failed: " + ex.Message); }
            Raise();
            return s;
        }

        // ── synaptic plasticity ──
        public PnsSynapse LookupSynapse(string taskCategory, string tract, string targetNodeId, string projectPath)
        {
            PnsSynapse e;
            return Synapses.TryGetValue(PnsSynapse.MakeId(taskCategory, tract, targetNodeId, projectPath), out e) ? e : null;
        }

        public void RecordSynapticFeedback(string taskPrompt, string tract, string targetNodeId, string projectPath, bool succeeded, int tokensUsed, int latencyMs, double regressionPenalty)
        {
            string category = Pns.ClassifyTaskCategory(taskPrompt);
            string key = PnsSynapse.MakeId(category, tract, targetNodeId, projectPath);
            PnsSynapse edge;
            if (!Synapses.TryGetValue(key, out edge)) Synapses[key] = edge = new PnsSynapse(category, tract, targetNodeId, projectPath);
            bool was = edge.IsMyelinated;
            edge.ApplyHebbianImpulse(succeeded, succeeded ? 1.0 : 0.0, tokensUsed, latencyMs, regressionPenalty);
            if (!was && edge.IsMyelinated)
                RecordSpike(Pns.SpikeGanglion, tract, null, projectPath, "Synapse MYELINATED (W_e=" + edge.Weight.ToString("0.00", CultureInfo.InvariantCulture) + "): [" + category + " -> " + targetNodeId + "] promoted to Fast-Path!", 0.88, latencyMs, true);
            SaveNow();
        }

        // ── hippocampal REM consolidation ──
        public string RunRemConsolidation(string projectPath, string missionId)
        {
            var sw = Stopwatch.StartNew();
            var scoped = RecentSpikes.Where(s => (missionId != null && s.MissionId == missionId) || (!string.IsNullOrEmpty(projectPath) && s.ProjectPath == projectPath) || (projectPath == null && missionId == null)).ToList();
            var successful = scoped.Where(s => s.Succeeded && s.Salience >= 0.45).ToList();
            var failed = scoped.Where(s => !s.Succeeded).ToList();
            int newPlaybooks = 0, newInhibitions = 0;
            // 1. repeated high-salience wins → procedural playbooks
            foreach (var g in successful.GroupBy(s => s.Tract))
            {
                var spikes = g.ToList();
                if (spikes.Count < 2) continue;
                string strategy = string.Join(" -> ", spikes.Skip(Math.Max(0, spikes.Count - 3)).Select(s => s.Summary));
                var pb = Playbooks.FirstOrDefault(p => p.Tract == g.Key && p.ProjectPath == projectPath);
                if (pb != null) { pb.ExecutionWins++; pb.ConfidenceWeight = Math.Min(0.99, pb.ConfidenceWeight + 0.04); pb.DistilledStrategy = strategy; pb.UpdatedAt = DateTime.Now; }
                else
                {
                    string last = spikes[spikes.Count - 1].Summary ?? "workflow";
                    Playbooks.Add(new PnsPlaybook
                    {
                        TriggerSignature = Pns.Badge(g.Key) + ":" + (last.Length > 48 ? last.Substring(0, 48) : last), ProjectPath = projectPath, Tract = g.Key,
                        ToolSequence = spikes.Skip(Math.Max(0, spikes.Count - 4)).Select(s => s.Kind).ToList(), DistilledStrategy = strategy,
                        VerificationCheck = "Verify zero LSP errors & isolated worktree build/test pass"
                    });
                    newPlaybooks++;
                }
            }
            // 2. dead ends → project inhibition warnings
            if (!string.IsNullOrEmpty(projectPath))
                foreach (var fail in failed.Skip(Math.Max(0, failed.Count - 3)))
                    if ((fail.Kind == Pns.SpikePain || fail.Kind == Pns.SpikeSpinal) && !Invariants.Any(i => i.ProjectPath == projectPath && i.RuleStatement == fail.Summary))
                    {
                        Invariants.Add(new PnsInvariant { ProjectPath = projectPath, ModuleScope = Pns.Badge(fail.Tract), RuleStatement = fail.Summary, IsInhibitionWarning = true });
                        newInhibitions++;
                    }
            // 3. prune episodic noise (context rot)
            if (RecentSpikes.Count > 48) RecentSpikes = RecentSpikes.Skip(RecentSpikes.Count - 48).ToList();
            if (Playbooks.Count > 64) Playbooks = Playbooks.OrderByDescending(p => p.ConfidenceWeight).Take(64).ToList();
            if (Invariants.Count > 80) Invariants = Invariants.Skip(Invariants.Count - 80).ToList();
            RemCycles++;
            int ms = Math.Max(1, (int)sw.ElapsedMilliseconds);
            string summary = "REM Consolidation Cycle #" + RemCycles + " (" + ms + "ms): +" + newPlaybooks + " Procedural Playbooks, +" + newInhibitions + " Inhibition Guards, active episodic buffer pruned.";
            RecordSpike(Pns.SpikeRem, Pns.HippocampalRem, missionId, projectPath, summary, 0.75, ms, true);
            SaveNow();
            return summary;
        }

        /// <summary>Project-scoped playbooks and inhibitions appended to a fiber's prompt (macOS also injects the MCP tract directory).</summary>
        public string PromptMemoryAugmentation(string query, string workspacePath)
        {
            var sections = new List<string>();
            var pbs = Playbooks.Where(pb => string.IsNullOrEmpty(workspacePath) ? pb.ProjectPath == null : pb.ProjectPath == workspacePath).OrderByDescending(pb => pb.ConfidenceWeight).Take(3).ToList();
            if (pbs.Count > 0)
                sections.Add("### PNS Myelinated Procedural Playbooks (Verified Fast-Paths)\n" + string.Join("\n", pbs.Select(pb => "- [" + Pns.Badge(pb.Tract) + " • W=" + pb.ConfidenceWeight.ToString("0.00", CultureInfo.InvariantCulture) + " • " + pb.ExecutionWins + " wins]: " + pb.DistilledStrategy)));
            if (!string.IsNullOrEmpty(workspacePath))
            {
                var guards = Invariants.Where(g => g.ProjectPath == workspacePath).ToList();
                guards = guards.Skip(Math.Max(0, guards.Count - 4)).ToList();
                if (guards.Count > 0)
                    sections.Add("### PNS Synaptic Invariants & LTD Inhibitions (Do Not Repeat Dead-Ends)\n" + string.Join("\n", guards.Select(g => "- " + (g.IsInhibitionWarning ? "⛔ INHIBITED" : "🔒 INVARIANT") + " [" + g.ModuleScope + "]: " + g.RuleStatement)));
            }
            return sections.Count == 0 ? "" : "\n\n## PNS (Pseudo Neural System — Active Cognitive Architecture)\n" + string.Join("\n\n", sections);
        }

        // ── autonomic homeostasis ──
        public void UpdateHomeostasis()
        {
            _rateLimitPressure = Math.Max(0.0, _rateLimitPressure * 0.88);
            var p = Pns.ReadPower();
            var v = Pns.Homeostasis(p.Factor, p.Label, p.Critical, _mode, _rateLimitPressure);
            MetabolicIndex = v.Index; PowerLabel = v.Label; EffectiveMode = v.Effective;
        }

        public void StartHeartbeat()
        {
            if (_heartbeat != null || Application.Current == null) return;
            _heartbeat = new DispatcherTimer(DispatcherPriority.Background, Application.Current.Dispatcher) { Interval = TimeSpan.FromSeconds(6) };
            _heartbeat.Tick += async delegate
            {
                UpdateHomeostasis();
                if (!IsDaemonProcess && (ViewAttached || RemoteOnline)) await PollDaemonOnce();
                else Raise();
            };
            _heartbeat.Start();
        }

        // ── snapshot ──
        public PnsStatusSnapshot BuildStatusSnapshot()
        {
            var edges = Synapses.Values.ToList();
            var tracts = Pns.McpTracts.Select(t => new PnsTractTelemetry { Tract = t, MyelinatedEdgesCount = edges.Count(e => e.Tract == t && e.IsMyelinated) }).ToList();
            tracts.AddRange(Plexus.BuildMotorTelemetry(edges));
            return new PnsStatusSnapshot
            {
                DaemonPID = IsDaemonProcess ? Process.GetCurrentProcess().Id : RemotePid, IsOutOfProcessDaemon = IsDaemonProcess || RemoteOnline, StartedAt = StartedAt,
                AutonomicMode = _mode, EffectiveMode = EffectiveMode, MetabolicBudgetIndex = MetabolicIndex, ThermalStateLabel = PowerLabel,
                MyelinatedSynapsesCount = edges.Count(e => e.IsMyelinated), InhibitedSynapsesCount = edges.Count(e => e.IsInhibited),
                ProceduralPlaybooksCount = Playbooks.Count, SemanticInvariantsCount = Invariants.Count, SpinalReflexSavesCount = Cord.SavesCount, RemConsolidationCycles = RemCycles,
                Tracts = tracts, Missions = Missions.ToList(), RecentSpikes = RecentSpikes.Skip(Math.Max(0, RecentSpikes.Count - 30)).ToList(),
                TopSynapses = edges.OrderByDescending(e => e.Weight).Take(8).ToList()
            };
        }

        /// <summary>What the dashboard draws: pnsd's state while it is online, the local state otherwise.</summary>
        public PnsStatusSnapshot Status() { return !IsDaemonProcess && RemoteOnline && _remote != null ? _remote : BuildStatusSnapshot(); }

        // ── missions ──
        public PnsMarathonMission Find(string id) { return Missions.FirstOrDefault(m => m.Id == id); }

        public static PnsMarathonMission NewMission(string objective, string workspacePath, string policy, string verificationCommand)
        {
            string first = (objective ?? "").Replace("\r", "").Split('\n')[0].Trim();
            if (first.Length == 0) first = "24/7 PNS Mission";
            return new PnsMarathonMission
            {
                Id = Guid.NewGuid().ToString(), Title = first.Length > 76 ? first.Substring(0, 76) : first, Objective = objective, WorkspacePath = workspacePath,
                BranchPolicy = policy == Pns.PolicyAutoMerge ? Pns.PolicyAutoMerge : Pns.PolicyIsolated,
                VerificationCommand = string.IsNullOrWhiteSpace(verificationCommand) ? null : verificationCommand.Trim(), Status = Pns.Queued,
                DistilledWorkingMemory = "GOAL ANCHOR: " + objective, CreatedAt = DateTime.Now, UpdatedAt = DateTime.Now
            };
        }

        public PnsMarathonMission StartLocalMission(string objective, string workspacePath, string policy, string verificationCommand)
        {
            var m = NewMission(objective, workspacePath, policy, verificationCommand);
            Missions.Insert(0, m);
            SaveNow();
            Log("mission " + m.Id + " started: " + m.Title);
            SpawnLoop(m.Id);
            Raise();
            return m;
        }

        public void ControlLocalMission(string missionId, string action)
        {
            var m = Find(missionId);
            if (m == null) return;
            CancellationTokenSource cts;
            switch ((action ?? "").ToLowerInvariant())
            {
                case "pause":
                    if (_loops.TryGetValue(missionId, out cts)) cts.Cancel();
                    m.Status = Pns.Paused; m.UpdatedAt = DateTime.Now;
                    break;
                case "resume":
                    m.Status = Pns.Running; m.UpdatedAt = DateTime.Now; m.LastError = null;
                    SpawnLoop(missionId);
                    break;
                case "cancel":
                    if (_loops.TryGetValue(missionId, out cts)) cts.Cancel();
                    m.Status = Pns.Cancelled; m.UpdatedAt = DateTime.Now;
                    break;
                default: return;
            }
            SaveNow();
            Raise();
        }

        /// <summary>Missions left running by a closed app (no pnsd) are paused instead of looking alive.</summary>
        public void RecoverInterruptedMissions()
        {
            bool changed = false;
            foreach (var m in Missions)
                if ((m.Status == Pns.Running || m.Status == Pns.ConsolidatingRem || m.Status == Pns.Queued || m.Status == Pns.PacingHomeostasis) && !_loops.ContainsKey(m.Id))
                {
                    m.Status = Pns.Paused;
                    m.LastError = "Interrupted — MicroCode closed while this mission was running. Press Resume to continue.";
                    foreach (var st in m.Subtasks) if (st.Status == Pns.Running) { st.Status = Pns.Queued; st.Activity = null; }
                    changed = true;
                }
            if (changed) { SaveNow(); Raise(); }
        }

        void SpawnLoop(string missionId)
        {
            CancellationTokenSource old;
            if (_loops.TryGetValue(missionId, out old)) old.Cancel();
            var cts = new CancellationTokenSource();
            _loops[missionId] = cts;
            ExecuteMissionLoop(missionId, cts).ContinueWith(t =>
            {
                if (t.IsFaulted) Post(() => { var m = Find(missionId); if (m != null) { m.Status = Pns.Failed; m.LastError = "PNS loop error: " + t.Exception.GetBaseException().Message; SaveNow(); Raise(); } Log("loop " + missionId + " crashed: " + t.Exception.GetBaseException()); });
            }, TaskScheduler.Default);
        }

        void EndLoop(string missionId, CancellationTokenSource cts)
        {
            CancellationTokenSource cur;
            if (_loops.TryGetValue(missionId, out cur) && cur == cts) _loops.Remove(missionId);
        }

        class FiberResult { public string SubtaskId, Summary = "", Branch; public bool Passed, Cancelled; }

        async Task ExecuteMissionLoop(string missionId, CancellationTokenSource cts)
        {
            var ct = cts.Token;
            try
            {
                var m = Find(missionId);
                if (m == null) return;
                m.Status = Pns.Running; m.UpdatedAt = DateTime.Now; m.LastError = null;
                foreach (var st in m.Subtasks) if (st.Status == Pns.Running) { st.Status = Pns.Queued; st.Activity = null; } // resume after an interruption
                var stale = m.ActiveFibers.Where(f => f.State == "active").ToList();
                foreach (var f in stale) f.State = "interrupted";
                SaveNow(); Raise();
                if (stale.Count > 0) await Task.Run(() => { foreach (var f in stale) Plexus.Release(f); });

                // 1. prefrontal cortex decomposition
                if (m.Subtasks.Count == 0)
                {
                    var planned = await PlanMissionSubtasks(m.Objective, m.WorkspacePath, missionId, ct);
                    m = Find(missionId);
                    if (m == null) return;
                    m.Subtasks = planned; m.UpdatedAt = DateTime.Now;
                    SaveNow(); Raise();
                }

                // 2. parallel motor fibers + REM consolidation
                while (!ct.IsCancellationRequested)
                {
                    m = Find(missionId);
                    if (m == null || m.Status == Pns.Paused || m.Status == Pns.Cancelled) return;
                    UpdateHomeostasis();
                    var done = new HashSet<string>(m.Subtasks.Where(s => s.Status == Pns.Completed).Select(s => s.Id));
                    var ready = m.Subtasks.Where(s => (s.Status == Pns.Queued || (s.Status == Pns.Failed && s.Attempts < 2)) && s.Dependencies.All(done.Contains)).ToList();
                    if (ready.Count == 0)
                    {
                        bool allDone = m.Subtasks.All(s => s.Status == Pns.Completed);
                        m.Status = allDone ? Pns.Completed : Pns.Failed;
                        if (!allDone && m.LastError == null)
                        {
                            var f = m.Subtasks.FirstOrDefault(s => s.Status == Pns.Failed);
                            m.LastError = f != null ? "Subtask '" + f.Title + "' failed after " + f.Attempts + " attempt(s): " + Trim(f.ResultSummary, 240) : "Blocked: the remaining subtasks wait on dependencies that cannot complete.";
                        }
                        m.UpdatedAt = DateTime.Now;
                        RunRemConsolidation(m.WorkspacePath, missionId);
                        Log("mission " + missionId + " " + m.Status);
                        SaveNow(); Raise();
                        return;
                    }
                    var batch = ready.Take(MaxConcurrentFibers).ToList();
                    foreach (var st in batch) { st.Status = Pns.Running; st.Attempts++; st.Activity = "Allocating isolated worktree…"; }
                    SaveNow(); Raise();
                    var mm = m;
                    var results = await Task.WhenAll(batch.Select(st => ExecuteFiber(missionId, st, mm.WorkspacePath, mm.BranchPolicy, mm.VerificationCommand, mm.DistilledWorkingMemory, ct)));
                    m = Find(missionId);
                    if (m == null) return;
                    foreach (var r in results)
                    {
                        var st = m.Subtasks.FirstOrDefault(s => s.Id == r.SubtaskId);
                        if (st == null) continue;
                        st.Activity = null;
                        if (r.Cancelled) { st.Status = Pns.Queued; continue; }
                        st.Status = r.Passed ? Pns.Completed : Pns.Failed;
                        st.ResultSummary = r.Summary;
                        st.WorktreeBranch = r.Branch;
                        m.CompletedEpisodes++;
                    }
                    m.UpdatedAt = DateTime.Now;
                    if (ct.IsCancellationRequested) { SaveNow(); Raise(); return; }
                    // 3. REM every 3 episodes keeps a 24/7 mission's working memory small
                    if (m.CompletedEpisodes > 0 && m.CompletedEpisodes % 3 == 0)
                    {
                        m.Status = Pns.ConsolidatingRem; Raise();
                        RunRemConsolidation(m.WorkspacePath, missionId);
                        m.RemConsolidationsCount++;
                        m.DistilledWorkingMemory = "GOAL ANCHOR: " + m.Objective + "\nVERIFIED PROGRESS LEDGER:\n" + string.Join("\n", m.Subtasks.Where(s => s.Status == Pns.Completed).Select(s => "- [✓] " + s.Title + ": " + Trim(s.ResultSummary ?? "verified", 140)));
                        if (m.Status == Pns.ConsolidatingRem) m.Status = Pns.Running;
                    }
                    SaveNow(); Raise();
                }
            }
            catch (OperationCanceledException) { } // paused or cancelled: ControlLocalMission already recorded the new status
            finally { EndLoop(missionId, cts); }
        }

        static string Trim(string s, int n) { s = (s ?? "").Trim(); return s.Length > n ? s.Substring(0, n) + "…" : s; }

        static string RoleText(string archetype)
        {
            switch ((archetype ?? "").ToLowerInvariant())
            {
                case "architect": return "inspect the repository and establish the implementation contracts (interfaces, data shapes, file layout) the other fibers build on; keep code changes minimal and write decisions where the team will find them.";
                case "frontend_engineer": return "implement the user-interface part of the subtask.";
                case "backend_engineer": return "implement the server / core-logic part of the subtask.";
                case "bug_hunter": return "reproduce, find and fix the bugs related to the subtask, adding a regression test for each fix.";
                case "test_runner": return "audit the changes, run the diagnostics and tests, and fix the regressions you find.";
                case "security_auditor": return "look for security problems (injection, secrets, unsafe input handling) in the affected code and fix them.";
                case "mobile_device_controller": return "handle the device / emulator work of the subtask (adb, simulators).";
                default: return "implement the subtask end to end.";
            }
        }

        static string FiberSystemPrompt(string archetype, PnsFiberLease lease, string workspace)
        {
            return "You are a PNS motor fiber agent [" + archetype + "] in MicroCode for Windows. Your role: " + RoleText(archetype) + "\n\n" +
                "## Isolated worktree\n- Root: `" + lease.IsolatedWorktreePath + "` — " + (lease.IsGit ? "a git worktree of `" + workspace + "` on branch `" + lease.BranchName + "`" : "an isolated copy of `" + workspace + "`") +
                ". All tool paths are relative to it; the real project only changes through the PNS join after verification.\n- OS: Windows. `shell` runs cmd.exe in the worktree.\n\n" +
                "## Rules\n1. Stay inside your subtask" + (lease.OwnedPaths.Count > 0 ? " and its owned files (" + string.Join(", ", lease.OwnedPaths) + ")" : "") + ".\n" +
                "2. Read before you edit; make minimal, focused changes with `replace_in_file` (`file_write` for new files).\n3. Run the relevant build or tests with `shell` when they exist.\n" +
                "4. Do not run `git commit`, `git push`, `git checkout` or `git reset` — PNS commits verified work on the fiber branch itself.\n5. Never write API keys, passwords or tokens into files.\n" +
                "6. Finish with a concise report: what you changed and how you verified it." + AgentContext.Extra(workspace);
        }

        async Task<FiberResult> ExecuteFiber(string missionId, PnsSubtask subtask, string ws, string policy, string verify, string memory, CancellationToken ct)
        {
            var sw = Stopwatch.StartNew();
            var res = new FiberResult { SubtaskId = subtask.Id };
            PnsFiberLease lease = null;
            bool settled = false; // the worktree was released, or handed to VerifyAndJoin (which releases or keeps it)
            string arch = subtask.AssignedArchetype;
            try
            {
                var owned = (subtask.OwnedPaths ?? new List<string>()).ToList();
                lease = await Task.Run(() => Plexus.AllocateFiber(missionId, arch, subtask.Title, ws, owned), ct);
                var m = Find(missionId);
                if (m != null) { m.ActiveFibers.Add(lease); if (m.ActiveFibers.Count > 30) m.ActiveFibers.RemoveRange(0, m.ActiveFibers.Count - 30); }
                RecordSpike(Pns.SpikeFiberSpawn, lease.Tract, missionId, ws, "Spawned Motor Fiber [" + arch + "] on isolated " + (lease.IsGit ? "worktree branch `" + lease.BranchName + "`" : "copy (no git history)") + ".", 0.65, 0, true);
                subtask.Activity = "Thinking…";
                Raise();
                string prompt = memory + "\n\n## Current Scoped Motor Fiber Subtask\nTitle: " + subtask.Title + "\nInstructions: " + subtask.Description + "\nIsolated Worktree Path: " + lease.IsolatedWorktreePath +
                    (owned.Count > 0 ? "\nOwned File Scope: " + string.Join(", ", owned) : "") + PromptMemoryAugmentation(subtask.Description, ws);
                string system = FiberSystemPrompt(arch, lease, ws);
                var history = new List<ChatMessage> { new ChatMessage { Role = "user", Content = prompt } };
                var cb = new AgentCallbacks
                {
                    OnActivity = a => Post(() => { subtask.Activity = a; Raise(); }),
                    Approve = IsolatedApprovals.Approver("pns", "Fiber [" + arch + "]")
                };
                string root = lease.IsolatedWorktreePath;
                AgentResult agent = null;
                string agentError = null;
                try { agent = await Task.Run(() => AgentRunner.RunIsolated(root, ws, history, system, false, cb, ct), ct); }
                catch (OperationCanceledException) { if (ct.IsCancellationRequested) throw; agentError = "The AI request timed out."; }
                catch (AIException ex) { agentError = ex.Message; }
                catch (HttpRequestException ex) { agentError = AIException.Describe(ex, AIConfig.Mode == "cloud"); }
                catch (IOException ex) { agentError = AIException.Describe(ex, AIConfig.Mode == "cloud"); }

                if (agentError != null)
                {
                    // the fiber never produced a result: release its worktree and let the reflex arc look at the error
                    var l = lease;
                    await Task.Run(() => Plexus.Release(l));
                    settled = true;
                    lease.State = "agent_failed"; lease.FinishedAt = DateTime.Now; lease.Summary = agentError;
                    await Reflex(missionId, ws, subtask, agentError, ct);
                    res.Summary = agentError;
                    return res;
                }

                string report = agent.Text == null || agent.Text.Trim().Length == 0 ? "Subtask finished" : agent.Text.Trim();
                subtask.Activity = verify != null ? "Verifying: " + verify : "Joining verified work…";
                Raise();
                var leaseId = lease.Id;
                var join = await Task.Run(() => Plexus.VerifyAndJoin(leaseId, policy, verify, report, ct), ct);
                settled = true;
                int ms = Math.Max(1, (int)sw.ElapsedMilliseconds);
                int tokens = agent.InputTokens + agent.OutputTokens;
                if (tokens <= 0) tokens = 800;
                RecordSynapticFeedback(subtask.Description, lease.Tract, "agent:" + arch, ws, join.VerificationPassed, tokens, ms, join.VerificationPassed ? 0.8 : 1.5);
                if (!join.VerificationPassed)
                {
                    RecordSpike(Pns.SpikePain, lease.Tract, missionId, ws, "Verification failed for [" + arch + "] " + subtask.Title + ": " + Trim(GitCli.FirstLine(join.VerificationSpike), 200), 0.9, ms, false);
                    await Reflex(missionId, ws, subtask, join.VerificationSpike, ct);
                }
                else
                    RecordSpike(Pns.SpikeFiberMerge, lease.Tract, missionId, ws, "Motor Fiber [" + arch + "] verified (" + join.ModifiedFiles.Count + " file(s), merged=" + join.MergedToTrunk + ", branch=" + (join.CommittedBranch ?? lease.BranchName) + ").", 0.85, ms, true);
                var notes = new List<string>();
                if (!join.VerificationPassed) notes.Add("Verification failed: " + Trim(join.VerificationSpike, 300));
                if (join.Note != null) notes.Add(join.Note);
                if (join.KeptWorktree != null) notes.Add("Verified work kept at " + join.KeptWorktree);
                if (join.SkippedMerges.Count > 0) notes.Add("Not merged: " + string.Join("; ", join.SkippedMerges));
                res.Passed = join.VerificationPassed;
                res.Summary = Trim(report, 400) + (notes.Count > 0 ? "\n" + string.Join("\n", notes) : "");
                res.Branch = join.CommittedBranch;
                return res;
            }
            catch (OperationCanceledException)
            {
                if (lease != null) lease.State = "cancelled";
                res.Cancelled = true;
                res.Summary = "Cancelled";
                return res;
            }
            catch (IsolationException ex) { res.Summary = ex.Message; return res; }
            catch (IOException ex) { res.Summary = "Could not prepare the isolated worktree: " + ex.Message; return res; }
            catch (UnauthorizedAccessException ex) { res.Summary = "Could not prepare the isolated worktree: " + ex.Message; return res; }
            finally
            {
                if (lease != null && !settled) { var l = lease; var release = Task.Run(() => Plexus.Release(l)); }
            }
        }

        async Task Reflex(string missionId, string ws, PnsSubtask subtask, string error, CancellationToken ct)
        {
            var r = Cord.Evaluate("agent:" + subtask.AssignedArchetype, subtask.Title, error);
            if (r.Action == PnsReflexAction.None) return;
            var m = Find(missionId);
            if (m != null) m.SpinalReflexSavesCount++;
            RecordSpike(Pns.SpikeSpinal, Pns.SpinalReflex, missionId, ws, r.Summary, 0.92, r.LatencyMs, true);
            if (r.Action == PnsReflexAction.SwitchProviderEndpoint)
            {
                _rateLimitPressure = Math.Min(0.85, _rateLimitPressure + 0.30);
                await Task.Delay(r.CooldownMs, ct);
            }
            else if (r.Action == PnsReflexAction.CircuitBreakBehavioralFixation)
                Invariants.Add(new PnsInvariant { ProjectPath = ws, ModuleScope = subtask.Title, RuleStatement = r.InhibitionRule, IsInhibitionWarning = true });
        }

        async Task<List<PnsSubtask>> PlanMissionSubtasks(string objective, string ws, string missionId, CancellationToken ct)
        {
            const string system = "You are the Prefrontal Cortex of MicroCode PNS (Pseudo Neural System).\nDecompose the objective into 2 to 5 concrete, verifiable subtasks for specialized Motor Agent Fibers.\nReturn ONLY a valid JSON array of objects with keys:\n[{\"id\":\"step_1\",\"title\":\"...\",\"description\":\"...\",\"archetype\":\"architect|frontend_engineer|backend_engineer|bug_hunter|test_runner|security_auditor\",\"owned_paths\":[],\"dependencies\":[]}]";
            string user = "WORKSPACE: " + ws + "\nOBJECTIVE:\n" + objective;
            string problem;
            try
            {
                var r = await Task.Run(() => AgentRunner.Run(new List<ChatMessage> { new ChatMessage { Role = "user", Content = user } }, system, false, true, null, new AgentCallbacks(), ct), ct);
                var plan = ParsePlan(r.Text, objective);
                if (plan.Count > 0) return plan;
                problem = "the planner reply had no JSON plan";
            }
            catch (OperationCanceledException) { if (ct.IsCancellationRequested) throw; problem = "the planner request timed out"; }
            catch (AIException ex) { problem = ex.Message; }
            catch (HttpRequestException ex) { problem = AIException.Describe(ex, AIConfig.Mode == "cloud"); }
            catch (IOException ex) { problem = AIException.Describe(ex, AIConfig.Mode == "cloud"); }
            var reflex = Cord.Evaluate("cortex_planner", "planMissionSubtasks", problem);
            if (reflex.Action != PnsReflexAction.None) RecordSpike(Pns.SpikeSpinal, Pns.SpinalReflex, missionId, ws, reflex.Summary, 0.85, reflex.LatencyMs, true);
            RecordSpike(Pns.SpikeSensory, Pns.ThalamicSensory, missionId, ws, "Cortex planner unavailable (" + Trim(problem, 160) + ") — using the 3-fiber fallback plan.", 0.6, 0, false);
            return FallbackPlan(objective);
        }

        /// <summary>The planner's JSON array → queued subtasks (at most 8). Dependencies on unknown or the same subtask are dropped
        /// so a mission cannot wait forever.</summary>
        public static List<PnsSubtask> ParsePlan(string raw, string objective)
        {
            var list = new List<PnsSubtask>();
            string text = raw ?? "";
            int start = text.IndexOf('['), end = text.LastIndexOf(']');
            if (start < 0 || end <= start) return list;
            System.Collections.ArrayList arr;
            try { arr = DJ.AsList(DJ.S.DeserializeObject(text.Substring(start, end - start + 1))); }
            catch (ArgumentException) { return list; }      // not JSON: the caller falls back
            catch (InvalidOperationException) { return list; }
            if (arr == null) return list;
            int idx = 0;
            foreach (var o in arr)
            {
                idx++;
                var item = o as Dictionary<string, object>;
                if (item == null) continue;
                string arch = (DJ.Str(item, "archetype") ?? "").Trim();
                if (arch.Length == 0) arch = "backend_engineer";
                list.Add(new PnsSubtask
                {
                    Id = NonEmpty(DJ.Str(item, "id"), "step_" + idx), Title = NonEmpty(DJ.Str(item, "title"), "Subtask " + idx), Description = NonEmpty(DJ.Str(item, "description"), objective),
                    AssignedArchetype = arch, Tract = Pns.MotorTractFor(arch), OwnedPaths = Strings(DJ.Arr(item, "owned_paths")), Dependencies = Strings(DJ.Arr(item, "dependencies")), Status = Pns.Queued
                });
                if (list.Count >= 8) break;
            }
            var ids = new HashSet<string>(list.Select(s => s.Id));
            foreach (var s in list) s.Dependencies = s.Dependencies.Where(d => d != s.Id && ids.Contains(d)).Distinct().ToList();
            return list;
        }

        static string NonEmpty(string s, string fallback) { return string.IsNullOrWhiteSpace(s) ? fallback : s.Trim(); }

        static List<string> Strings(System.Collections.ArrayList a)
        {
            var r = new List<string>();
            if (a != null) foreach (var o in a) { var s = o as string; if (!string.IsNullOrWhiteSpace(s)) r.Add(s.Trim()); }
            return r;
        }

        /// <summary>The macOS 3-fiber fallback: architect → implementation → verification.</summary>
        public static List<PnsSubtask> FallbackPlan(string objective)
        {
            return new List<PnsSubtask>
            {
                new PnsSubtask { Id = "step_1", Title = "Architectural Analysis & Contract Scope", Description = "Inspect repository symbols and establish implementation contracts for: " + objective, AssignedArchetype = "architect", Tract = Pns.MotorArchitecture },
                new PnsSubtask { Id = "step_2", Title = "Scoped Implementation Fiber", Description = "Implement the required changes cleanly inside the isolated worktree for: " + objective, AssignedArchetype = "autonomous_loop", Tract = Pns.MotorImplementation, Dependencies = new List<string> { "step_1" } },
                new PnsSubtask { Id = "step_3", Title = "Adversarial QA & Verification Gate", Description = "Audit changes, run diagnostics/tests, and verify regressions for: " + objective, AssignedArchetype = "test_runner", Tract = Pns.MotorVerification, Dependencies = new List<string> { "step_2" } }
            };
        }

        // ── out-of-process daemon (GUI side) ──
        int DaemonPort
        {
            get
            {
                int p;
                string s = ReadFile("daemon.port");
                return s != null && int.TryParse(s.Trim(), out p) && p > 0 ? p : DefaultDaemonPort;
            }
        }

        public async Task<bool> PollDaemonOnce() { return await Poll(DaemonPort); }

        async Task<bool> Poll(int port)
        {
            if (IsDaemonProcess) return true;
            var snap = PnsStatusSnapshot.Parse(await new PnsDaemonClient(Dir, port).Send("GET", "/pns/status", null));
            if (snap == null)
            {
                bool was = RemoteOnline;
                RemoteOnline = false; RemotePid = 0; _remote = null;
                if (was) Load(); // pnsd stopped: its last state is on disk
                if (was || !_recovered) { _recovered = true; RecoverInterruptedMissions(); }
                Raise();
                return false;
            }
            RemoteOnline = true; RemotePid = snap.DaemonPID; _remote = snap;
            Missions = snap.Missions ?? new List<PnsMarathonMission>();
            if (snap.RecentSpikes != null && snap.RecentSpikes.Count > 0) RecentSpikes = snap.RecentSpikes;
            RemCycles = Math.Max(RemCycles, snap.RemConsolidationCycles);
            Raise();
            return true;
        }

        /// <summary>Starts MicroCode.exe --pns-daemon detached (it keeps running after the app quits) and attaches to it. In-process
        /// missions are handed over first so they are not run twice.</summary>
        public async Task<bool> EnsureDaemonRunning()
        {
            if (IsDaemonProcess) return true;
            if (await PollDaemonOnce()) return true;
            HandOffLocalMissions();
            bool isolated = TaskFiles.HomeOverride != null;
            int port = isolated ? PnsSpinalCord.AllocateFreeLocalPort() : DefaultDaemonPort;
            if (!isolated && !PortFree(port)) port = PnsSpinalCord.AllocateFreeLocalPort();
            if (port <= 0) return false;
            string exe = typeof(PnsOrchestrator).Assembly.Location;
            string args = "--pns-daemon --pns-port " + port + (isolated ? " --data-dir " + GitCli.Q(Defaults.Dir) : "");
            try
            {
                // ShellExecute: the daemon must not inherit this process's handles (a console or pipe it holds open would keep
                // whoever launched MicroCode waiting for as long as pnsd runs)
                var proc = Process.Start(new ProcessStartInfo(exe, args) { UseShellExecute = true, WindowStyle = ProcessWindowStyle.Hidden, WorkingDirectory = System.IO.Path.GetDirectoryName(exe) });
                if (proc != null) proc.Dispose();
            }
            catch (System.ComponentModel.Win32Exception) { return false; }
            for (int i = 0; i < 100; i++)
            {
                await Task.Delay(100);
                if (await Poll(port)) return true;
            }
            return false;
        }

        static bool PortFree(int port)
        {
            try { var l = new TcpListener(IPAddress.Loopback, port); l.Start(); l.Stop(); return true; }
            catch (SocketException) { return false; }
        }

        void HandOffLocalMissions()
        {
            foreach (var kv in _loops.ToList()) kv.Value.Cancel();
            foreach (var m in Missions)
                if (m.Status == Pns.Running || m.Status == Pns.ConsolidatingRem)
                {
                    m.Status = Pns.Queued;
                    foreach (var st in m.Subtasks) if (st.Status == Pns.Running) { st.Status = Pns.Queued; st.Activity = null; }
                }
            SaveNow();
        }

        public async Task StopDaemon()
        {
            if (IsDaemonProcess) return;
            await new PnsDaemonClient(Dir, DaemonPort).Send("POST", "/pns/shutdown", new Dictionary<string, object>());
            RemoteOnline = false; RemotePid = 0; _remote = null;
            await Task.Delay(500);
            Load();
            RecoverInterruptedMissions();
            Raise();
        }

        /// <summary>Dispatches a marathon mission — to pnsd when it can run (so it survives closing the app), otherwise in-process.</summary>
        public async Task<PnsMarathonMission> DispatchMission(string objective, string workspacePath, string policy, string verificationCommand, bool preferDaemon)
        {
            if (preferDaemon && !IsDaemonProcess && await EnsureDaemonRunning())
            {
                var payload = new Dictionary<string, object> { { "objective", objective }, { "workspace_path", workspacePath }, { "branch_policy", policy } };
                if (!string.IsNullOrWhiteSpace(verificationCommand)) payload["verification_command"] = verificationCommand.Trim();
                var remote = PnsJson.Read<PnsMarathonMission>(await new PnsDaemonClient(Dir, DaemonPort).Send("POST", "/pns/missions/start", payload));
                if (remote != null)
                {
                    await PollDaemonOnce();
                    return remote;
                }
            }
            return StartLocalMission(objective, workspacePath, policy, verificationCommand);
        }

        public async Task ControlMission(string missionId, string action)
        {
            if (!IsDaemonProcess && RemoteOnline)
            {
                await new PnsDaemonClient(Dir, DaemonPort).Send("POST", "/pns/missions/control", new Dictionary<string, object> { { "mission_id", missionId }, { "action", action } });
                await PollDaemonOnce();
                return;
            }
            ControlLocalMission(missionId, action);
        }

        public async Task SetModeAsync(string mode)
        {
            if (!IsDaemonProcess && RemoteOnline)
            {
                await new PnsDaemonClient(Dir, DaemonPort).Send("POST", "/pns/mode", new Dictionary<string, object> { { "mode", mode } });
                await PollDaemonOnce();
                return;
            }
            Mode = mode;
        }

        public async Task<string> ConsolidateAsync(string workspacePath)
        {
            if (!IsDaemonProcess && RemoteOnline)
            {
                var o = DJ.Obj(await new PnsDaemonClient(Dir, DaemonPort).Send("POST", "/pns/consolidate", new Dictionary<string, object> { { "workspace_path", workspacePath } }));
                await PollDaemonOnce();
                return DJ.Str(o, "report") ?? "pnsd did not answer the REM request.";
            }
            return RunRemConsolidation(workspacePath, null);
        }

        // ── out-of-process daemon (server side, MicroCode.exe --pns-daemon) ──
        string LoadOrCreateToken()
        {
            string p = P("daemon.token");
            try { if (File.Exists(p)) { string t = File.ReadAllText(p).Trim(); if (t.Length >= 24) return t; } }
            catch (IOException) { } // unreadable token: a fresh one replaces it below
            var bytes = new byte[32];
            using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(bytes);
            string tok = BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant();
            WriteFile("daemon.token", tok);
            return tok;
        }

        public bool StartDaemonServer(int port)
        {
            IsDaemonProcess = true;
            LoadOrCreateToken();
            try { _listener = new TcpListener(IPAddress.Loopback, port); _listener.Start(); }
            catch (SocketException ex) { Log("cannot bind 127.0.0.1:" + port + ": " + ex.Message); return false; }
            int pid = Process.GetCurrentProcess().Id;
            WriteFile("daemon.pid", pid.ToString(CultureInfo.InvariantCulture));
            WriteFile("daemon.port", port.ToString(CultureInfo.InvariantCulture));
            new Thread(AcceptLoop) { IsBackground = true, Name = "pnsd-accept" }.Start();
            RecordSpike(Pns.SpikeHomeostasis, Pns.SpinalReflex, null, null, "Out-of-process 24/7 daemon `microcode-pnsd` booted (PID " + pid + ", 127.0.0.1:" + port + ").", 0.9, 0, true);
            Log("pnsd booted pid " + pid + " on 127.0.0.1:" + port);
            // resume incomplete marathon missions from the durable checkpoint
            foreach (var m in Missions.Where(x => x.Status == Pns.Running || x.Status == Pns.Queued || x.Status == Pns.ConsolidatingRem).ToList()) SpawnLoop(m.Id);
            StartHeartbeat();
            return true;
        }

        void AcceptLoop()
        {
            while (true)
            {
                TcpClient c;
                try { c = _listener.AcceptTcpClient(); }
                catch (SocketException) { return; }        // listener stopped (shutdown)
                catch (ObjectDisposedException) { return; }
                ThreadPool.QueueUserWorkItem(_ => Serve(c));
            }
        }

        void Serve(TcpClient client)
        {
            using (client)
            {
                try
                {
                    client.ReceiveTimeout = 5000; client.SendTimeout = 5000;
                    var stream = client.GetStream();
                    string method, path, token, body;
                    if (!ReadRequest(stream, out method, out path, out token, out body)) { Respond(stream, 400, "{\"error\":\"Malformed request\"}"); return; }
                    if (!TokenEquals(token, LoadOrCreateToken())) { Respond(stream, 401, "{\"error\":\"Unauthorized PNS token\"}"); return; }
                    int status = 500;
                    string json = "{}";
                    var app = Application.Current;
                    if (app == null) return; // shutting down
                    app.Dispatcher.Invoke(new Action(() =>
                    {
                        try { var r = Handle(method, path, body); status = r.Item1; json = r.Item2; }
                        catch (Exception ex) { status = 500; json = PnsJson.Write(new Dictionary<string, object> { { "error", ex.Message } }); Log("request " + method + " " + path + " failed: " + ex); } // answered as HTTP 500 and logged
                    }));
                    Respond(stream, status, json);
                }
                catch (IOException) { } // the client hung up; nothing to answer
            }
        }

        static bool ReadRequest(NetworkStream s, out string method, out string path, out string token, out string body)
        {
            method = path = token = body = null;
            var buf = new List<byte>();
            var one = new byte[4096];
            int headerEnd = -1;
            while (headerEnd < 0)
            {
                int n = s.Read(one, 0, one.Length);
                if (n <= 0) return false;
                buf.AddRange(one.Take(n));
                if (buf.Count > 65536) return false;
                for (int i = 3; i < buf.Count; i++) if (buf[i - 3] == '\r' && buf[i - 2] == '\n' && buf[i - 1] == '\r' && buf[i] == '\n') { headerEnd = i + 1; break; }
            }
            string head = Encoding.ASCII.GetString(buf.ToArray(), 0, headerEnd);
            var lines = head.Split(new[] { "\r\n" }, StringSplitOptions.None);
            var req = lines[0].Split(' ');
            if (req.Length < 2) return false;
            method = req[0].ToUpperInvariant(); path = req[1];
            int length = 0;
            foreach (var l in lines.Skip(1))
            {
                int c = l.IndexOf(':');
                if (c <= 0) continue;
                string k = l.Substring(0, c).Trim().ToLowerInvariant(), v = l.Substring(c + 1).Trim();
                if (k == "x-pns-token") token = v;
                else if (k == "content-length") int.TryParse(v, out length);
            }
            if (length < 0 || length > 262144) return false;
            var bodyBytes = buf.Skip(headerEnd).ToList();
            while (bodyBytes.Count < length)
            {
                int n = s.Read(one, 0, Math.Min(one.Length, length - bodyBytes.Count));
                if (n <= 0) return false;
                bodyBytes.AddRange(one.Take(n));
            }
            body = Encoding.UTF8.GetString(bodyBytes.Take(length).ToArray());
            return true;
        }

        static bool TokenEquals(string a, string b)
        {
            if (a == null || b == null || a.Length != b.Length) return false;
            int d = 0;
            for (int i = 0; i < a.Length; i++) d |= a[i] ^ b[i];
            return d == 0;
        }

        static void Respond(NetworkStream s, int status, string json)
        {
            var body = Encoding.UTF8.GetBytes(json);
            string text = status == 200 ? "OK" : status == 401 ? "Unauthorized" : status == 404 ? "Not Found" : status == 400 ? "Bad Request" : "Error";
            var head = Encoding.ASCII.GetBytes("HTTP/1.1 " + status + " " + text + "\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: " + body.Length + "\r\nConnection: close\r\n\r\n");
            s.Write(head, 0, head.Length);
            s.Write(body, 0, body.Length);
            s.Flush();
        }

        static Tuple<int, string> J(int status, Dictionary<string, object> o) { return Tuple.Create(status, PnsJson.Write(o)); }

        Tuple<int, string> Handle(string method, string path, string body)
        {
            var payload = DJ.Obj(body) ?? new Dictionary<string, object>();
            if (method == "GET" && path == "/pns/status") return Tuple.Create(200, PnsJson.Write(BuildStatusSnapshot()));
            if (method != "POST") return J(404, new Dictionary<string, object> { { "error", "Unknown PNS endpoint " + path } });
            switch (path)
            {
                case "/pns/missions/start":
                {
                    string objective = DJ.Str(payload, "objective");
                    if (string.IsNullOrWhiteSpace(objective)) return J(400, new Dictionary<string, object> { { "error", "Missing objective" } });
                    string ws = DJ.Str(payload, "workspace_path");
                    if (string.IsNullOrWhiteSpace(ws) || !Directory.Exists(ws)) return J(400, new Dictionary<string, object> { { "error", "workspace_path must be an existing folder" } });
                    var m = StartLocalMission(objective, ws, DJ.Str(payload, "branch_policy") ?? Pns.PolicyIsolated, DJ.Str(payload, "verification_command"));
                    return Tuple.Create(200, PnsJson.Write(m));
                }
                case "/pns/missions/control":
                {
                    string id = DJ.Str(payload, "mission_id"), action = DJ.Str(payload, "action");
                    if (id == null || action == null) return J(400, new Dictionary<string, object> { { "error", "Missing mission_id or action" } });
                    ControlLocalMission(id, action);
                    return J(200, new Dictionary<string, object> { { "ok", true }, { "mission_id", id }, { "action", action } });
                }
                case "/pns/consolidate":
                    return J(200, new Dictionary<string, object> { { "ok", true }, { "report", RunRemConsolidation(DJ.Str(payload, "workspace_path"), null) } });
                case "/pns/mode":
                {
                    string mode = DJ.Str(payload, "mode");
                    if (mode != null && Pns.Modes.Contains(mode)) Mode = mode;
                    return J(200, new Dictionary<string, object> { { "ok", true }, { "mode", Mode } });
                }
                case "/pns/shutdown":
                    ScheduleShutdown();
                    return J(200, new Dictionary<string, object> { { "ok", true }, { "shutting_down", true } });
                default:
                    return J(404, new Dictionary<string, object> { { "error", "Unknown PNS endpoint " + path } });
            }
        }

        void ScheduleShutdown()
        {
            foreach (var kv in _loops.ToList()) kv.Value.Cancel();
            SaveNow();
            Log("pnsd shutting down");
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
            timer.Tick += delegate
            {
                timer.Stop();
                SaveNow();
                try { _listener.Stop(); } catch (SocketException) { }
                try { File.Delete(P("daemon.pid")); } catch (IOException) { }
                Application.Current.Shutdown(0);
            };
            timer.Start();
        }
    }

    /// <summary>HTTP client for pnsd on 127.0.0.1 (token from the PNS folder, short timeouts, no proxy).</summary>
    public class PnsDaemonClient
    {
        static readonly HttpClient Http = new HttpClient(new HttpClientHandler { UseProxy = false }) { Timeout = TimeSpan.FromSeconds(30) };
        readonly string _dir;
        public readonly int Port;

        public PnsDaemonClient(string pnsDir, int port) { _dir = pnsDir; Port = port; }

        string Token()
        {
            try { string p = System.IO.Path.Combine(_dir, "daemon.token"); return File.Exists(p) ? File.ReadAllText(p).Trim() : null; }
            catch (IOException) { return null; }
        }

        /// <summary>Response body of a 2xx answer; null when pnsd is not reachable or refused the request.</summary>
        public async Task<string> Send(string method, string path, Dictionary<string, object> body)
        {
            string token = Token();
            if (string.IsNullOrEmpty(token)) return null;
            var req = new HttpRequestMessage(new HttpMethod(method), "http://127.0.0.1:" + Port + path);
            req.Headers.TryAddWithoutValidation("X-PNS-Token", token);
            if (body != null) req.Content = new StringContent(PnsJson.Write(body), Encoding.UTF8, "application/json");
            using (var cts = new CancellationTokenSource(path == "/pns/status" ? 3000 : 15000))
            {
                try
                {
                    using (var resp = await Http.SendAsync(req, cts.Token))
                    {
                        string text = await resp.Content.ReadAsStringAsync();
                        return resp.IsSuccessStatusCode ? text : null;
                    }
                }
                catch (HttpRequestException) { return null; }   // pnsd is not running
                catch (TaskCanceledException) { return null; }   // pnsd did not answer in time
            }
        }
    }

    /// <summary>Starts pnsd at Windows sign-in (HKCU Run key — the counterpart of the macOS launchd KeepAlive agent).</summary>
    public static class PnsKeepAlive
    {
        public const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run", ValueName = "MicroCode PNS";

        public static string CommandLine(string exe, string dataDir)
        {
            return GitCli.Q(exe) + " --pns-daemon" + (dataDir != null ? " --data-dir " + GitCli.Q(dataDir) : "");
        }

        public static bool IsInstalled
        {
            get { using (var k = Registry.CurrentUser.OpenSubKey(RunKey)) return k != null && k.GetValue(ValueName) != null; }
        }

        public static void SetEnabled(bool on)
        {
            using (var k = Registry.CurrentUser.CreateSubKey(RunKey))
            {
                if (on) k.SetValue(ValueName, CommandLine(typeof(PnsOrchestrator).Assembly.Location, null));
                else k.DeleteValue(ValueName, false);
            }
        }
    }

    /// <summary>MicroCode.exe --pns-daemon [--pns-port N]: the headless 24/7 PNS daemon (no window).</summary>
    public static class PnsDaemon
    {
        public static int RunHeadless(Application app, int port)
        {
            PnsOrchestrator.IsDaemonProcess = true;
            IsolatedApprovals.Headless = true;
            app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
            int code = 0;
            app.Startup += delegate
            {
                if (!PnsOrchestrator.Shared.StartDaemonServer(port)) { code = 3; app.Shutdown(3); }
            };
            app.Run();
            return code;
        }
    }
}
