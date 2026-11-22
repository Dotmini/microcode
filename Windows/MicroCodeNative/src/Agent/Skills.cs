// Agent Skills Engine (AgentSkillsView + SkillRouter + SkillEngine):
// Discovers SKILL.md toolkits on disk, ranks relevant skills per prompt (including Thai/Unicode tokenization),
// executes bundled scripts/, and crystallizes reusable skills from completed tasks.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using MicroCode.Core;

namespace MicroCode.Views
{
    public enum SkillTier { Project, User, External, Builtin }

    public class Skill
    {
        public string Name, Description, Path, Source;
        public SkillTier Tier;
        public bool Enabled { get { return Defaults.Bool("skill_enabled_" + Path.ToLowerInvariant(), true); } set { Defaults.Set("skill_enabled_" + Path.ToLowerInvariant(), value); } }
        public string Dir { get { return System.IO.Path.GetDirectoryName(Path); } }
    }

    public static class SkillStore
    {
        public static List<Skill> Skills = new List<Skill>();

        public static string UserSkillsDir { get { return System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".microcode", "skills"); } }

        public static IEnumerable<Tuple<string, string, SkillTier>> Roots()
        {
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string ws = AppState.Shared.WorkspaceFolder;
            if (ws != null)
            {
                yield return Tuple.Create(System.IO.Path.Combine(ws, ".microcode", "skills"), "Project", SkillTier.Project);
                yield return Tuple.Create(System.IO.Path.Combine(ws, ".agents", "skills"), "Project", SkillTier.Project);
            }
            yield return Tuple.Create(UserSkillsDir, "MicroCode", SkillTier.User);
            yield return Tuple.Create(System.IO.Path.Combine(home, ".agents", "skills"), "Antigravity", SkillTier.External);
            yield return Tuple.Create(System.IO.Path.Combine(home, ".codex", "skills"), "Codex", SkillTier.External);
            yield return Tuple.Create(System.IO.Path.Combine(home, ".claude", "skills"), "Claude", SkillTier.External);
        }

        public static void Rescan()
        {
            var list = new List<Skill>();
            foreach (var root in Roots())
            {
                if (!Directory.Exists(root.Item1)) continue;
                try
                {
                    foreach (var f in Directory.GetFiles(root.Item1, "SKILL.md", SearchOption.AllDirectories).Concat(Directory.GetFiles(root.Item1, "*.md", SearchOption.TopDirectoryOnly)).Distinct())
                    {
                        if (list.Any(s => string.Equals(s.Path, f, StringComparison.OrdinalIgnoreCase))) continue;
                        var sk = Parse(f);
                        sk.Source = root.Item2;
                        sk.Tier = root.Item3;
                        list.Add(sk);
                    }
                }
                catch { }
            }
            Skills = list.OrderBy(s => s.Tier).ThenBy(s => s.Name, StringComparer.OrdinalIgnoreCase).ToList();
        }

        static Skill Parse(string file)
        {
            string name = System.IO.Path.GetFileName(file) == "SKILL.md" ? System.IO.Path.GetFileName(System.IO.Path.GetDirectoryName(file)) : System.IO.Path.GetFileNameWithoutExtension(file);
            string desc = "";
            try
            {
                var lines = File.ReadAllLines(file);
                if (lines.Length > 0 && lines[0].Trim() == "---")
                {
                    for (int i = 1; i < lines.Length && lines[i].Trim() != "---"; i++)
                    {
                        if (lines[i].StartsWith("name:")) name = lines[i].Substring(5).Trim().Trim('"');
                        else if (lines[i].StartsWith("description:")) desc = lines[i].Substring(12).Trim().Trim('"');
                    }
                }
                if (desc.Length == 0) desc = lines.Select(l => l.Trim()).FirstOrDefault(l => l.Length > 0 && !l.StartsWith("#") && l != "---") ?? "";
            }
            catch { }
            return new Skill { Name = name, Description = desc, Path = file };
        }

        public static void Import(string file)
        {
            Directory.CreateDirectory(UserSkillsDir);
            File.Copy(file, System.IO.Path.Combine(UserSkillsDir, System.IO.Path.GetFileName(file)), true);
            Rescan();
        }
    }

    /// <summary>Port of SkillRouter.swift: ranks skills per user prompt with English+Thai tokenization, $skill boosts, and character budget.</summary>
    public static class SkillRouter
    {
        public static List<string> Tokenize(string text)
        {
            var tokens = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (string.IsNullOrEmpty(text)) return tokens.ToList();
            string lower = text.ToLowerInvariant();
            foreach (Match m in Regex.Matches(lower, @"[a-z0-9_-]{2,}"))
            {
                string w = m.Value;
                tokens.Add(w);
                if (w.Length > 4 && (w.EndsWith("ing") || w.EndsWith("ies"))) tokens.Add(w.Substring(0, w.Length - 3));
                else if (w.Length > 3 && w.EndsWith("ed")) tokens.Add(w.Substring(0, w.Length - 2));
                else if (w.Length > 3 && w.EndsWith("s")) tokens.Add(w.Substring(0, w.Length - 1));
            }
            // Thai Unicode blocks (\u0E00-\u0E7F) without whitespace word boundaries -> sliding 3-grams + whole span
            foreach (Match m in Regex.Matches(lower, @"[\u0E00-\u0E7F]{2,}"))
            {
                string t = m.Value;
                tokens.Add(t);
                for (int i = 0; i + 3 <= t.Length; i++) tokens.Add(t.Substring(i, 3));
            }
            return tokens.ToList();
        }

        public static List<Skill> Route(string query, string ws, int maxCount)
        {
            if (SkillStore.Skills.Count == 0) SkillStore.Rescan();
            var enabled = SkillStore.Skills.Where(s => s.Enabled).ToList();
            if (enabled.Count == 0) return enabled;
            if (string.IsNullOrWhiteSpace(query)) return enabled.Take(maxCount).ToList();

            var qTokens = Tokenize(query);
            var explicitRefs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (Match m in Regex.Matches(query, @"\$([a-zA-Z0-9_-]+)")) explicitRefs.Add(m.Groups[1].Value);

            var scored = new List<Tuple<int, Skill>>();
            foreach (var s in enabled)
            {
                int score = s.Tier == SkillTier.Project ? 12 : s.Tier == SkillTier.User ? 6 : 2;
                if (explicitRefs.Contains(s.Name)) score += 200;
                string nLower = (s.Name ?? "").ToLowerInvariant();
                string dLower = (s.Description ?? "").ToLowerInvariant();
                foreach (var tk in qTokens)
                {
                    if (nLower.Contains(tk)) score += 18;
                    else if (dLower.Contains(tk)) score += 5;
                }
                if (ws != null && s.Path != null && s.Path.StartsWith(ws, StringComparison.OrdinalIgnoreCase)) score += 8;
                scored.Add(Tuple.Create(score, s));
            }
            return scored.OrderByDescending(x => x.Item1).ThenBy(x => x.Item2.Name, StringComparer.OrdinalIgnoreCase).Take(maxCount).Select(x => x.Item2).ToList();
        }
    }

    /// <summary>Port of skill_engine (`match`, `read`, `run_script`, `crystallize`).</summary>
    public static class SkillEngine
    {
        public static string Invoke(string action, string skillName, string queryOrScript, string instructions, string ws)
        {
            string act = (action ?? "match").ToLowerInvariant();
            if (act == "match")
            {
                var hits = SkillRouter.Route(queryOrScript ?? skillName ?? "", ws, 10);
                if (hits.Count == 0) return "No enabled skills matched.";
                return string.Join("\n", hits.Select(s => "- " + s.Name + " (" + s.Tier + "): " + (s.Description ?? "")));
            }
            if (act == "read") return AgentContext.ReadSkill(skillName ?? "");
            if (act == "run_script") return RunScript(skillName, queryOrScript, ws);
            if (act == "crystallize") return Crystallize(skillName, queryOrScript, instructions, ws);
            return "Unknown skill_engine action '" + action + "'. Use match, read, run_script, or crystallize.";
        }

        public static string RunScript(string skillName, string scriptRel, string ws)
        {
            if (SkillStore.Skills.Count == 0) SkillStore.Rescan();
            var s = SkillStore.Skills.FirstOrDefault(x => x.Enabled && string.Equals(x.Name, skillName, StringComparison.OrdinalIgnoreCase));
            if (s == null) return "Error: skill '" + skillName + "' not found.";
            string scriptsDir = Path.GetFullPath(Path.Combine(s.Dir, "scripts"));
            string target = Path.GetFullPath(Path.Combine(scriptsDir, (scriptRel ?? "").Replace('/', Path.DirectorySeparatorChar).TrimStart(Path.DirectorySeparatorChar)));
            if (!target.StartsWith(scriptsDir, StringComparison.OrdinalIgnoreCase)) return "Error: script path must stay inside skill scripts/ folder.";
            if (!File.Exists(target)) return "Error: script not found: " + target;
            string ext = Path.GetExtension(target).ToLowerInvariant();
            string exe = target, args = "";
            if (ext == ".py") { exe = "python"; args = "\"" + target + "\""; }
            else if (ext == ".ps1") { exe = "powershell"; args = "-NoProfile -ExecutionPolicy Bypass -File \"" + target + "\""; }
            else if (ext == ".sh") { exe = "bash"; args = "\"" + target + "\""; }
            else if (ext == ".bat" || ext == ".cmd") { exe = "cmd.exe"; args = "/c \"" + target + "\""; }
            try
            {
                var psi = new ProcessStartInfo(exe, args)
                {
                    WorkingDirectory = ws ?? s.Dir,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    StandardOutputEncoding = Encoding.UTF8,
                    StandardErrorEncoding = Encoding.UTF8
                };
                var p = Process.Start(psi);
                string stdout = p.StandardOutput.ReadToEnd();
                string stderr = p.StandardError.ReadToEnd();
                p.WaitForExit(30000);
                return "Exit " + p.ExitCode + "\n" + stdout + (stderr.Length > 0 ? "\n[stderr]\n" + stderr : "");
            }
            catch (Exception ex) { return "Error running script: " + ex.Message; }
        }

        public static string Crystallize(string rawName, string description, string body, string ws)
        {
            string safe = Regex.Replace((rawName ?? "new-skill").ToLowerInvariant(), @"[^a-z0-9_-]+", "-").Trim('-');
            if (safe.Length == 0) safe = "new-skill";
            string root = !string.IsNullOrEmpty(ws) ? Path.Combine(ws, ".microcode", "skills") : SkillStore.UserSkillsDir;
            string dir = Path.Combine(root, safe);
            Directory.CreateDirectory(dir);
            string path = Path.Combine(dir, "SKILL.md");
            string content = "---\nname: " + safe + "\ndescription: " + (description ?? safe).Replace("\n", " ") + "\n---\n\n" + (body ?? "");
            File.WriteAllText(path, content, Encoding.UTF8);
            SkillStore.Rescan();
            return "Crystallized skill '" + safe + "' at " + path;
        }
    }

    /// <summary>Extra system context: custom instructions (Settings -> General), project rules, routed skills, MCP & memory.</summary>
    public static class AgentContext
    {
        public static string Extra(string ws) { return Extra(ws, null); }

        public static string Extra(string ws, string userPrompt)
        {
            var sb = new StringBuilder();
            string custom = Defaults.Str("agentCustomInstructions", "");
            if (custom.Trim().Length > 0) sb.Append("\n\nUser instructions:\n").Append(custom.Trim());
            if (ws != null)
            {
                string rules = System.IO.Path.Combine(ws, ".microcode", "rules.md");
                try { if (File.Exists(rules)) sb.Append("\n\nProject rules (.microcode/rules.md):\n").Append(File.ReadAllText(rules)); } catch { }
                sb.Append(RulesEngine.PromptSection(ws, 800));
            }
            if (SkillStore.Skills.Count == 0) SkillStore.Rescan();
            var active = SkillRouter.Route(userPrompt, ws, 60);
            if (active.Count > 0)
            {
                sb.Append("\n\nAvailable skills (call read_skill with the exact name before doing a task a skill covers):");
                int budget = 4200;
                foreach (var s in active)
                {
                    string d = (s.Description ?? "").Replace("\n", " ");
                    if (d.Length > 160) d = d.Substring(0, 160) + "…";
                    string line = "\n- " + s.Name + " [" + s.Tier + "]: " + d;
                    if (budget - line.Length < 0) break;
                    budget -= line.Length;
                    sb.Append(line);
                }
            }
            McpManager.EnsureSynced(ws);
            sb.Append(McpManager.PromptSummary());
            return sb.ToString();
        }

        public static string ReadSkill(string name)
        {
            if (SkillStore.Skills.Count == 0) SkillStore.Rescan();
            var s = SkillStore.Skills.FirstOrDefault(x => x.Enabled && string.Equals(x.Name, name, StringComparison.OrdinalIgnoreCase));
            if (s == null) return "Error: no active skill named '" + name + "'.";
            string body = File.ReadAllText(s.Path);
            return body.Length > 60000 ? body.Substring(0, 60000) + "\n[truncated]" : body;
        }
    }
}
