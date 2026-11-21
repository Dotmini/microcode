// Agent Skills Engine (AgentSkillsView): skill toolkits discovered on disk + extra agent context (rules, custom instructions).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using MicroCode.Core;

namespace MicroCode.Views
{
    public class Skill
    {
        public string Name, Description, Path, Source;
        public bool Enabled { get { return Defaults.Bool("skill_enabled_" + Path.ToLowerInvariant(), true); } set { Defaults.Set("skill_enabled_" + Path.ToLowerInvariant(), value); } }
    }

    public static class SkillStore
    {
        public static List<Skill> Skills = new List<Skill>();

        public static string UserSkillsDir { get { return System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".microcode", "skills"); } }

        public static IEnumerable<Tuple<string, string>> Roots()
        {
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            yield return Tuple.Create(UserSkillsDir, "MicroCode");
            yield return Tuple.Create(System.IO.Path.Combine(home, ".agents", "skills"), "Antigravity");
            yield return Tuple.Create(System.IO.Path.Combine(home, ".codex", "skills"), "Codex");
            yield return Tuple.Create(System.IO.Path.Combine(home, ".claude", "skills"), "Claude");
            string ws = AppState.Shared.WorkspaceFolder;
            if (ws != null)
            {
                yield return Tuple.Create(System.IO.Path.Combine(ws, ".agents", "skills"), "Project");
                yield return Tuple.Create(System.IO.Path.Combine(ws, ".microcode", "skills"), "Project");
            }
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
                        list.Add(sk);
                    }
                }
                catch { }
            }
            Skills = list.OrderBy(s => s.Name, StringComparer.OrdinalIgnoreCase).ToList();
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

    /// <summary>Extra system context: custom instructions (Settings → General), project rules (.microcode/rules.md), active skills.</summary>
    public static class AgentContext
    {
        public static string Extra(string ws)
        {
            var sb = new StringBuilder();
            string custom = Defaults.Str("agentCustomInstructions", "");
            if (custom.Trim().Length > 0) sb.Append("\n\nUser instructions:\n").Append(custom.Trim());
            if (ws != null)
            {
                string rules = System.IO.Path.Combine(ws, ".microcode", "rules.md");
                try { if (File.Exists(rules)) sb.Append("\n\nProject rules (.microcode/rules.md):\n").Append(File.ReadAllText(rules)); } catch { }
                // AGENTS.md, CLAUDE.md, .cursorrules, .cursor/rules, Windsurf, Cline, Copilot, Zed (MultiPlatformRulesEngine, 800-token budget)
                sb.Append(RulesEngine.PromptSection(ws, 800));
            }
            if (SkillStore.Skills.Count == 0) SkillStore.Rescan();
            var active = SkillStore.Skills.Where(s => s.Enabled).Take(60).ToList();
            if (active.Count > 0)
            {
                // progressive disclosure: names + descriptions only; the agent loads a skill with read_skill when it applies
                sb.Append("\n\nAvailable skills (call read_skill with the exact name before doing a task a skill covers):");
                foreach (var s in active)
                {
                    string d = (s.Description ?? "").Replace("\n", " ");
                    if (d.Length > 160) d = d.Substring(0, 160) + "…";
                    sb.Append("\n- ").Append(s.Name).Append(": ").Append(d);
                }
            }
            // live external MCP servers (ExternalMCPManager.compactPromptSummary)
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
