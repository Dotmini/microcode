// Port of MultiPlatformRulesEngine.swift + WorkspaceTrustService.swift: project rules from every agent platform (AGENTS.md,
// CLAUDE.md with @imports, TX Code, Cursor .cursorrules / .cursor/rules/*.mdc, Windsurf, Cline, Copilot, Zed, MicroCode) and
// lifecycle hooks (pre_tool / post_tool / pre_finish — Claude Code's PreToolUse / PostToolUse / Stop) that run shell commands
// around agent tools. Repo-declared hooks execute programs, so they stay off until the user trusts this exact config.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Media;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public class PlatformRule
    {
        public string Badge, FileName, RelativePath, Description, Content;
        public List<string> Globs = new List<string> { "*" };
        public bool AlwaysApply = true;
    }

    public class AgentHook
    {
        public const string PreTool = "pre_tool", PostTool = "post_tool", PreFinish = "pre_finish";
        public string Stage, Name, Matcher = "*", Command, SourceFile;
        public bool BlockOnFailure = true;
        public static string StageBadge(string s) { return s == PreTool ? "PRE_TOOL" : s == PostTool ? "POST_TOOL" : "PRE_FINISH"; }
    }

    public class HookOutcome
    {
        public bool Allowed = true;
        public string Feedback = "";
    }

    public static class RulesEngine
    {
        static readonly HashSet<string> NestedSkip = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".git", "node_modules", ".build", "target", "dist", "build", ".codetuner-build", "Pods", ".next", "venv", ".venv" };

        static string ReadText(string path)
        {
            try { return File.Exists(path) ? File.ReadAllText(path) : null; }
            catch (IOException ex) { Debug.WriteLine("rules read " + path + ": " + ex.Message); return null; }
            catch (UnauthorizedAccessException ex) { Debug.WriteLine("rules read " + path + ": " + ex.Message); return null; }
        }

        static bool Blank(string s) { return s == null || s.Trim().Length == 0; }

        static PlatformRule Always(string badge, string fileName, string rel, string desc, string content)
        {
            return new PlatformRule { Badge = badge, FileName = fileName, RelativePath = rel, Description = desc, Content = content, Globs = new List<string> { "*" }, AlwaysApply = true };
        }

        /// <summary>refresh(workspaceRoot:) rules half: every rule file the Mac discovers, in the Mac's order.</summary>
        public static List<PlatformRule> ScanRules(string root)
        {
            var rules = new List<PlatformRule>();
            if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) return rules;
            root = Path.GetFullPath(root).TrimEnd('\\');

            // 0A. AGENTS.md (root, with @imports) + AGENTS.md in immediate subdirectories, scoped to that directory
            string agents = ReadText(Path.Combine(root, "AGENTS.md"));
            if (!Blank(agents)) rules.Add(Always("AGENTS.MD", "AGENTS.md", "AGENTS.md", "Workspace Root AGENTS.md Instructions", ExpandImports(agents, root, root)));
            string[] children = new string[0];
            try { children = Directory.GetDirectories(root); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            foreach (var child in children.OrderBy(c => c, StringComparer.OrdinalIgnoreCase))
            {
                string dn = Path.GetFileName(child);
                if (NestedSkip.Contains(dn) || dn.StartsWith(".")) continue;
                string nested = ReadText(Path.Combine(child, "AGENTS.md"));
                if (Blank(nested)) continue;
                string rel = dn + "/AGENTS.md";
                rules.Add(new PlatformRule { Badge = "AGENTS.MD", FileName = rel, RelativePath = rel, Description = "Scoped AGENTS.md for " + dn + "/", Content = nested, Globs = new List<string> { dn + "/*", dn + "/**/*" }, AlwaysApply = false });
            }
            // 0B. Claude Code CLAUDE.md and .claude/CLAUDE.md (with @path imports)
            foreach (var rel in new[] { "CLAUDE.md", ".claude/CLAUDE.md" })
            {
                string p = Path.Combine(root, rel.Replace('/', '\\'));
                string raw = ReadText(p);
                if (!Blank(raw)) rules.Add(Always("CLAUDE", "CLAUDE.md", rel, "Claude Code Project Memory & Guidelines", ExpandImports(raw, Path.GetDirectoryName(p), root)));
            }
            // 0C. TX Code
            foreach (var rel in new[] { ".txcode-rules", ".txcoderules" })
            {
                string c = ReadText(Path.Combine(root, rel));
                if (!Blank(c)) rules.Add(Always("TXCODE", rel, rel, "TX Code Project Rules", c));
            }
            AddMdcDir(rules, Path.Combine(root, ".txcode", "rules"), root, "TXCODE");
            // 1. Cursor legacy
            string cursor = ReadText(Path.Combine(root, ".cursorrules"));
            if (!Blank(cursor)) rules.Add(Always("CURSOR", ".cursorrules", ".cursorrules", "Cursor Project Rules", cursor));
            // 3. Cursor modern .cursor/rules/*.mdc
            AddMdcDir(rules, Path.Combine(root, ".cursor", "rules"), root, "CURSOR");
            // 4. Windsurf
            string wind = ReadText(Path.Combine(root, ".windsurfrules"));
            if (!Blank(wind)) rules.Add(Always("WINDSURF", ".windsurfrules", ".windsurfrules", "Windsurf Cascade Rules", wind));
            // 5. Cline / Roo Code
            string cline = ReadText(Path.Combine(root, ".clinerules"));
            if (!Blank(cline)) rules.Add(Always("CLINE", ".clinerules", ".clinerules", "Cline / Roo Code Rules", cline));
            // 6. GitHub Copilot (first one found)
            foreach (var rel in new[] { ".github/copilot-instructions.md", ".copilot-instructions.md" })
            {
                string c = ReadText(Path.Combine(root, rel.Replace('/', '\\')));
                if (Blank(c)) continue;
                rules.Add(Always("COPILOT", Path.GetFileName(rel), rel, "GitHub Copilot Instructions", c));
                break;
            }
            // 7. Zed assistant system prompt
            string zed = ReadText(Path.Combine(root, ".zed", "settings.json"));
            if (zed != null)
            {
                try
                {
                    var o = new JavaScriptSerializer().DeserializeObject(zed) as Dictionary<string, object>;
                    object a;
                    var assistant = o != null && o.TryGetValue("assistant", out a) ? a as Dictionary<string, object> : null;
                    object sp;
                    string prompt = assistant != null && assistant.TryGetValue("system_prompt", out sp) ? sp as string : null;
                    if (!string.IsNullOrEmpty(prompt)) rules.Add(Always("ZED", "settings.json", ".zed/settings.json", "Zed Assistant System Prompt", prompt));
                }
                catch (ArgumentException) { } catch (InvalidOperationException) { }
            }
            // 8. MicroCode rules: workspace state (~/.microcode/workspaces/<id>), repository .microcode, global ~/.microcode
            string state = TaskFiles.StateDir(root), home = TaskFiles.Home;
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var direct = new[]
            {
                Tuple.Create(Path.Combine(state, "rules.md"), "rules.md", "~/.microcode/workspaces/" + Path.GetFileName(state) + "/rules.md", "Learned Workspace Rules (/learn)"),
                Tuple.Create(Path.Combine(state, "agent.md"), "agent.md", "~/.microcode/workspaces/" + Path.GetFileName(state) + "/agent.md", "MicroCode Workspace Agent Instructions (~/.microcode)"),
                Tuple.Create(Path.Combine(root, ".microcode", "rules.md"), ".microcode/rules.md", ".microcode/rules.md", "Repository MicroCode Rules"),
                Tuple.Create(Path.Combine(root, ".microcode", "agent.md"), ".microcode/agent.md", ".microcode/agent.md", "Repository MicroCode Agent Instructions"),
                Tuple.Create(Path.Combine(home, "rules.md"), "~/.microcode/rules.md", "~/.microcode/rules.md", "Global MicroCode User Rules")
            };
            foreach (var d in direct)
            {
                string full = Path.GetFullPath(d.Item1);
                if (seen.Contains(full)) continue;
                string c = ReadText(full);
                if (Blank(c)) continue;
                seen.Add(full);
                rules.Add(Always("MICROCODE", d.Item2, d.Item3, d.Item4, c.Trim()));
            }
            foreach (var dir in new[] { Tuple.Create(Path.Combine(state, "rules"), state), Tuple.Create(Path.Combine(root, ".microcode", "rules"), root), Tuple.Create(Path.Combine(home, "rules"), home) })
                AddMdcDir(rules, dir.Item1, dir.Item2, "MICROCODE", seen);
            return rules;
        }

        static void AddMdcDir(List<PlatformRule> rules, string dir, string baseRoot, string badge, HashSet<string> seen = null)
        {
            if (!Directory.Exists(dir)) return;
            string[] files;
            try { files = Directory.GetFiles(dir, "*", SearchOption.AllDirectories); }
            catch (IOException) { return; } catch (UnauthorizedAccessException) { return; }
            foreach (var f in files.OrderBy(x => x, StringComparer.OrdinalIgnoreCase))
            {
                string ext = Path.GetExtension(f).ToLowerInvariant();
                if (ext != ".mdc" && ext != ".md") continue;
                if (Path.GetFileName(f).StartsWith(".")) continue;
                string full = Path.GetFullPath(f);
                if (seen != null && seen.Contains(full)) continue;
                var r = ParseMdc(full, baseRoot, badge);
                if (r == null) continue;
                if (seen != null) seen.Add(full);
                rules.Add(r);
            }
        }

        /// <summary>parseMdcRule: YAML front matter (description / globs / alwaysApply) then the markdown body.</summary>
        public static PlatformRule ParseMdc(string file, string baseRoot, string badge)
        {
            string text = ReadText(file);
            if (string.IsNullOrEmpty(text)) return null;
            string desc = "", body = text;
            var globs = new List<string>();
            bool always = false;
            if (text.StartsWith("---"))
            {
                var parts = text.Split(new[] { "---" }, StringSplitOptions.None);
                if (parts.Length >= 3)
                {
                    body = string.Join("---", parts.Skip(2)).Trim();
                    foreach (var line in parts[1].Split('\n'))
                    {
                        string t = line.Trim();
                        if (t.StartsWith("description:")) desc = t.Substring(12).Trim(' ', '"', '\'');
                        else if (t.StartsWith("globs:")) globs = t.Substring(6).Trim(' ', '"', '\'', '[', ']').Split(',').Select(g => g.Trim().Trim('"', '\'')).Where(g => g.Length > 0).ToList();
                        else if (t.StartsWith("alwaysApply:")) { string b = t.Substring(12).Trim().ToLowerInvariant(); always = b == "true" || b == "1"; }
                    }
                }
            }
            string rootN = Path.GetFullPath(baseRoot).TrimEnd('\\') + "\\";
            string rel = file.StartsWith(rootN, StringComparison.OrdinalIgnoreCase) ? file.Substring(rootN.Length).Replace('\\', '/') : file;
            string fallback = Regex.Replace(Path.GetFileNameWithoutExtension(file).Replace('-', ' ').Replace('_', ' '), @"\b\w", m => m.Value.ToUpperInvariant());
            return new PlatformRule { Badge = badge == "CURSOR" ? "CURSOR" : badge, FileName = Path.GetFileName(file), RelativePath = rel, Description = desc.Length == 0 ? fallback : desc, Globs = globs.Count == 0 ? new List<string> { "*" } : globs, AlwaysApply = always, Content = body };
        }

        /// <summary>expandAtFileImports: a line that is only "@path/file.md" (or .mdc / .txt) is replaced by that file, if it is inside the workspace.</summary>
        public static string ExpandImports(string text, string baseDir, string root)
        {
            string rootN = Path.GetFullPath(root).TrimEnd('\\');
            var outLines = new List<string>();
            foreach (var line in (text ?? "").Replace("\r\n", "\n").Split('\n'))
            {
                string t = line.Trim();
                if (t.StartsWith("@") && !t.Contains(" ") && t.Length > 2 && (t.EndsWith(".md") || t.EndsWith(".mdc") || t.EndsWith(".txt")))
                {
                    string rel = t.Substring(1);
                    try
                    {
                        string cand = Path.IsPathRooted(rel) ? Path.GetFullPath(rel) : Path.GetFullPath(Path.Combine(baseDir, rel.Replace('/', '\\')));
                        if (cand.StartsWith(rootN + "\\", StringComparison.OrdinalIgnoreCase))
                        {
                            string imported = ReadText(cand);
                            if (!string.IsNullOrEmpty(imported)) { outLines.Add("<!-- Imported from " + rel + " -->"); outLines.Add(imported); continue; }
                        }
                    }
                    catch (ArgumentException) { } catch (NotSupportedException) { } catch (PathTooLongException) { }
                }
                outLines.Add(line);
            }
            return string.Join("\n", outLines);
        }

        /// <summary>activeRules(forFiles:): alwaysApply rules, wildcard rules, and glob-scoped rules that match an active file.</summary>
        public static List<PlatformRule> ActiveRules(List<PlatformRule> rules, List<string> relFiles)
        {
            if (relFiles == null || relFiles.Count == 0) return rules.Where(r => r.AlwaysApply || r.Globs.Contains("*")).ToList();
            return rules.Where(r => r.AlwaysApply || r.Globs.Any(g => g == "*" || g == "**/*" || relFiles.Any(f => MatchGlob(g, f)))).ToList();
        }

        /// <summary>formatPromptSection: rules as a token-budgeted prompt section (each rule capped at 2,000 characters).</summary>
        public static string FormatPromptSection(List<PlatformRule> rules, List<string> relFiles, int maxTokens)
        {
            var matching = ActiveRules(rules, relFiles);
            if (matching.Count == 0) return "";
            var sb = new StringBuilder("\n\n## Multi-Platform Rules & Guidelines (Cursor, Zed, Copilot)\nThe following rules are dynamically imported and active for this project:\n\n");
            int est = 0;
            foreach (var r in matching)
            {
                string content = r.Content.Trim();
                if (content.Length > 2000) content = content.Substring(0, 2000);
                string text = "### [" + r.Badge + "] " + r.FileName + " (" + r.Description + ")\n> Scope: `" + string.Join(", ", r.Globs) + "` | Always Apply: `" + (r.AlwaysApply ? "true" : "false") + "`\n\n```markdown\n" + content + "\n```\n\n";
                int tokens = text.Length / 4;
                if (est + tokens > maxTokens && est > 200) { sb.Append("> ... [" + (matching.Count - 1) + " more rules omitted for token budget]\n"); break; }
                sb.Append(text);
                est += tokens;
            }
            return sb.ToString();
        }

        /// <summary>The agent's rules section for the open workspace and the file open in the editor (software domain budget: 800 tokens).
        /// .microcode/rules.md is left out because the agent context already carries it in full.</summary>
        public static string PromptSection(string ws, int maxTokens)
        {
            if (string.IsNullOrEmpty(ws)) return "";
            var rules = ScanRules(ws).Where(r => r.RelativePath != ".microcode/rules.md").ToList();
            var active = new List<string>();
            var cf = AppState.Shared != null ? AppState.Shared.CurrentFile : null;
            if (cf != null && cf.Path != null)
            {
                string root = Path.GetFullPath(ws).TrimEnd('\\') + "\\";
                if (cf.Path.StartsWith(root, StringComparison.OrdinalIgnoreCase)) active.Add(cf.Path.Substring(root.Length).Replace('\\', '/'));
            }
            return FormatPromptSection(rules, active, maxTokens);
        }

        /// <summary>matchGlob: exact, "*.ext", "**/*.ext", fnmatch (FNM_PATHNAME | FNM_PERIOD), then the pattern without "**/" against the file name.</summary>
        public static bool MatchGlob(string pattern, string path)
        {
            if (pattern == null || path == null) return false;
            path = path.Replace('\\', '/');
            if (pattern == path) return true;
            if (pattern.StartsWith("*.")) return path.EndsWith("." + pattern.Substring(2));
            if (pattern.StartsWith("**/*.")) return path.EndsWith("." + pattern.Substring(5));
            if (Fnmatch(pattern, path, true)) return true;
            string clean = pattern.Replace("**/", "");
            int slash = path.LastIndexOf('/');
            return Fnmatch(clean, slash >= 0 ? path.Substring(slash + 1) : path, false);
        }

        static bool Fnmatch(string pattern, string s, bool pathname)
        {
            var re = new StringBuilder("^");
            string any = pathname ? "[^/]" : ".";
            for (int i = 0; i < pattern.Length; i++)
            {
                char c = pattern[i];
                if (c == '*') re.Append(any).Append('*');
                else if (c == '?') re.Append(any);
                else if (c == '[')
                {
                    int j = pattern.IndexOf(']', i + 1);
                    if (j < 0) { re.Append("\\["); continue; }
                    string cls = pattern.Substring(i + 1, j - i - 1);
                    if (cls.StartsWith("!")) cls = "^" + cls.Substring(1);
                    re.Append('[').Append(cls.Replace("\\", "\\\\")).Append(']');
                    i = j;
                }
                else re.Append(Regex.Escape(c.ToString()));
            }
            re.Append('$');
            // FNM_PERIOD: a leading dot (of the string, or of a path segment with FNM_PATHNAME) must be matched literally
            if (pathname)
            {
                var segs = s.Split('/');
                var psegs = pattern.Split('/');
                for (int k = 0; k < segs.Length && k < psegs.Length; k++)
                    if (segs[k].StartsWith(".") && !psegs[k].StartsWith(".")) return false;
            }
            try { return Regex.IsMatch(s, re.ToString()); }
            catch (ArgumentException) { return false; }
        }

        // ── lifecycle hooks ──────────────────────────────────────────────────

        static readonly string[] HookFiles = { ".microcode/hooks.json", ".txcode/hooks.json", ".cursor/hooks.json", ".claude/settings.json", ".claude/settings.local.json" };

        /// <summary>scanLifecycleHooks: hooks from the five config files, in Mac or Claude Code format. <paramref name="contributing"/>
        /// gets the files that declared at least one hook (the trust fingerprint covers exactly those).</summary>
        public static List<AgentHook> ScanHooks(string root, List<string> contributing)
        {
            var hooks = new List<AgentHook>();
            if (string.IsNullOrEmpty(root)) return hooks;
            var mappings = new[]
            {
                Tuple.Create(new[] { "pre_tool", "preTool", "PreToolUse" }, AgentHook.PreTool),
                Tuple.Create(new[] { "post_tool", "postTool", "PostToolUse" }, AgentHook.PostTool),
                Tuple.Create(new[] { "pre_finish", "preFinish", "Stop" }, AgentHook.PreFinish)
            };
            foreach (var rel in HookFiles)
            {
                string path = Path.Combine(root, rel.Replace('/', '\\'));
                string raw = ReadText(path);
                if (raw == null) continue;
                Dictionary<string, object> json;
                try { json = new JavaScriptSerializer().DeserializeObject(raw) as Dictionary<string, object>; }
                catch (ArgumentException) { continue; } catch (InvalidOperationException) { continue; }
                if (json == null) continue;
                object h;
                var hooksRoot = json.TryGetValue("hooks", out h) && h is Dictionary<string, object> ? (Dictionary<string, object>)h : json;
                int before = hooks.Count;
                foreach (var map in mappings)
                    foreach (var key in map.Item1)
                    {
                        object v;
                        if (!hooksRoot.TryGetValue(key, out v) || v == null) continue;
                        var single = v as string;
                        if (single != null)
                        {
                            if (single.Length > 0) hooks.Add(new AgentHook { Stage = map.Item2, Name = map.Item2 + " hook", Matcher = "*", Command = single, BlockOnFailure = true, SourceFile = rel });
                            continue;
                        }
                        var arr = v as object[];
                        if (arr == null && v is System.Collections.ArrayList) arr = ((System.Collections.ArrayList)v).ToArray();
                        if (arr == null) continue;
                        foreach (var entryObj in arr)
                        {
                            var entry = entryObj as Dictionary<string, object>;
                            if (entry == null) continue;
                            string matcher = Str(entry, "matcher") ?? Str(entry, "glob") ?? Str(entry, "tool") ?? "*";
                            bool block = Bool(entry, "blockOnFailure") ?? Bool(entry, "block_on_failure") ?? true;
                            string cmd = Str(entry, "command");
                            if (!string.IsNullOrEmpty(cmd))
                            {
                                hooks.Add(new AgentHook { Stage = map.Item2, Name = Str(entry, "name") ?? map.Item2 + ": " + (cmd.Length > 36 ? cmd.Substring(0, 36) : cmd), Matcher = matcher, Command = cmd, BlockOnFailure = block, SourceFile = rel });
                                continue;
                            }
                            object innerObj;
                            if (!entry.TryGetValue("hooks", out innerObj)) continue;
                            var inner = innerObj as object[];
                            if (inner == null && innerObj is System.Collections.ArrayList) inner = ((System.Collections.ArrayList)innerObj).ToArray();
                            if (inner == null) continue;
                            // Claude Code format: { "matcher": "...", "hooks": [ { "type": "command", "command": "..." } ] }
                            foreach (var io in inner)
                            {
                                var ie = io as Dictionary<string, object>;
                                string ic = ie != null ? Str(ie, "command") : null;
                                if (string.IsNullOrEmpty(ic)) continue;
                                hooks.Add(new AgentHook { Stage = map.Item2, Name = Str(ie, "name") ?? map.Item2 + " (" + matcher + ")", Matcher = matcher, Command = ic, BlockOnFailure = block, SourceFile = rel });
                            }
                        }
                    }
                if (hooks.Count > before && contributing != null) contributing.Add(path);
            }
            return hooks;
        }

        static string Str(Dictionary<string, object> d, string k) { object v; return d.TryGetValue(k, out v) ? v as string : null; }
        static bool? Bool(Dictionary<string, object> d, string k) { object v; return d.TryGetValue(k, out v) && v is bool ? (bool?)(bool)v : null; }

        /// <summary>The MicroCode tool names a Claude Code matcher means (Edit, Write, Bash …) — so Claude settings.json hooks fire here too.</summary>
        static readonly Dictionary<string, string[]> ClaudeToolNames = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
        {
            { "file_read", new[] { "Read" } }, { "multi_file_read", new[] { "Read" } }, { "file_write", new[] { "Write" } },
            { "replace_in_file", new[] { "Edit" } }, { "multi_replace_in_file", new[] { "MultiEdit", "Edit" } }, { "patch_file", new[] { "MultiEdit", "Edit" } },
            { "apply_patch", new[] { "Edit", "Write" } }, { "shell", new[] { "Bash" } }, { "grep_search", new[] { "Grep" } }, { "file_search", new[] { "Glob" } },
            { "list_directory_tree", new[] { "LS" } }, { "web_fetch", new[] { "WebFetch" } }
        };

        public static bool HookMatches(AgentHook hook, string tool, string relFile)
        {
            string m = (hook.Matcher ?? "").Trim();
            if (m.Length == 0 || m == "*" || m == "**/*") return true;
            if (tool != null)
            {
                var parts = m.Split('|').Select(p => p.Trim()).ToList();
                if (parts.Any(p => string.Equals(p, tool, StringComparison.OrdinalIgnoreCase))) return true;
                string[] aliases;
                if (ClaudeToolNames.TryGetValue(tool, out aliases) && parts.Any(p => aliases.Contains(p, StringComparer.OrdinalIgnoreCase))) return true;
            }
            return relFile != null && MatchGlob(m, relFile);
        }

        /// <summary>executeHooks: runs the matching hooks of <paramref name="stage"/> in <paramref name="cwd"/> (cmd.exe, 15 s each).
        /// A failing blocking hook stops at once (Allowed=false) with its output as feedback; other output is passed back as info
        /// (never for pre_tool). Hooks of an untrusted workspace never run.</summary>
        public static HookOutcome RunHooks(string stage, string tool, string filePath, string workspace, string cwd)
        {
            var outcome = new HookOutcome();
            if (string.IsNullOrEmpty(workspace)) return outcome;
            var files = new List<string>();
            var hooks = ScanHooks(workspace, files).Where(h => h.Stage == stage).ToList();
            if (hooks.Count == 0) return outcome;
            var all = ScanHooks(workspace, new List<string>());
            if (!WorkspaceTrust.RequestTrust(workspace, "exec-config", all.Select(h => Tuple.Create("Hook " + h.Stage + " `" + h.Name + "` (" + h.SourceFile + ")", h.Command)).ToList(), WorkspaceTrust.Fingerprint(files, workspace)))
                return outcome;
            string relFile = null;
            if (filePath != null)
            {
                string rootN = Path.GetFullPath(cwd ?? workspace).TrimEnd('\\') + "\\";
                relFile = (filePath.StartsWith(rootN, StringComparison.OrdinalIgnoreCase) ? filePath.Substring(rootN.Length) : filePath).Replace('\\', '/');
            }
            var parts = new List<string>();
            foreach (var hook in hooks.Where(h => HookMatches(h, tool, relFile)))
            {
                int code; string output;
                RunHookCommand(hook.Command, stage, tool, filePath, cwd ?? workspace, out code, out output);
                string trimmed = (output ?? "").Trim();
                if (code != 0)
                {
                    string snippet = trimmed.Length > 1200 ? trimmed.Substring(trimmed.Length - 1200) : trimmed;
                    parts.Add("⚠️ [Hook " + AgentHook.StageBadge(stage) + " Failed — " + hook.Name + " (`" + hook.Command + "` exited with " + code + ")]:\n" + (snippet.Length == 0 ? "(no output)" : snippet));
                    if (hook.BlockOnFailure) { outcome.Allowed = false; outcome.Feedback = string.Join("\n\n", parts); return outcome; }
                }
                else if (trimmed.Length > 0 && stage != AgentHook.PreTool)
                    parts.Add("ℹ️ [Hook " + AgentHook.StageBadge(stage) + " — " + hook.Name + "]: " + (trimmed.Length > 600 ? trimmed.Substring(trimmed.Length - 600) : trimmed));
            }
            outcome.Feedback = string.Join("\n\n", parts);
            return outcome;
        }

        /// <summary>runHookShellCommand on Windows: cmd.exe /c with MICROCODE_HOOK_STAGE / MICROCODE_WORKSPACE / MICROCODE_TOOL /
        /// MICROCODE_FILE / FILE, stdin closed, killed (with its child processes) after 15 seconds.</summary>
        static void RunHookCommand(string command, string stage, string tool, string file, string cwd, out int code, out string output)
        {
            code = -1; output = "";
            try
            {
                var psi = new ProcessStartInfo("cmd.exe", "/d /s /c \"" + command + "\"") { WorkingDirectory = cwd, UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, RedirectStandardInput = true, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
                psi.EnvironmentVariables["MICROCODE_HOOK_STAGE"] = stage;
                psi.EnvironmentVariables["MICROCODE_WORKSPACE"] = cwd;
                if (tool != null) psi.EnvironmentVariables["MICROCODE_TOOL"] = tool;
                if (file != null) { psi.EnvironmentVariables["MICROCODE_FILE"] = file; psi.EnvironmentVariables["FILE"] = file; }
                using (var p = Process.Start(psi))
                {
                    try { p.StandardInput.Close(); } catch (IOException) { }
                    var o = p.StandardOutput.ReadToEndAsync(); var e = p.StandardError.ReadToEndAsync();
                    if (!p.WaitForExit(15000))
                    {
                        try { using (var k = Process.Start(new ProcessStartInfo("taskkill", "/T /F /PID " + p.Id) { CreateNoWindow = true, UseShellExecute = false })) k.WaitForExit(3000); }
                        catch (System.ComponentModel.Win32Exception ex) { Debug.WriteLine("hook kill: " + ex.Message); }
                        code = -1; output = "Hook timed out after 15s";
                        return;
                    }
                    p.WaitForExit();
                    code = p.ExitCode;
                    output = (o.Result + e.Result);
                }
            }
            catch (System.ComponentModel.Win32Exception ex) { code = -1; output = ex.Message; }
            catch (InvalidOperationException ex) { code = -1; output = ex.Message; }
        }
    }

    /// <summary>WorkspaceTrustService: repo-declared executable config (hooks, later MCP servers) runs only after the user trusts
    /// this workspace; the approval is pinned to a SHA-256 of the exact config files, so any change asks again.</summary>
    public static class WorkspaceTrust
    {
        const string Key = "workspaceTrust.v1";
        static readonly HashSet<string> Declined = new HashSet<string>();
        static readonly object Gate = new object();
        /// <summary>Tests replace the dialog; return true to trust.</summary>
        public static Func<string, List<Tuple<string, string>>, bool> Prompt;

        public static string Fingerprint(List<string> files, string workspace)
        {
            string root = Path.GetFullPath(workspace).TrimEnd('\\');
            using (var sha = SHA256.Create())
            {
                var ms = new MemoryStream();
                foreach (var f in files.Select(Path.GetFullPath).OrderBy(x => x, StringComparer.OrdinalIgnoreCase))
                {
                    string rel = f.StartsWith(root + "\\", StringComparison.OrdinalIgnoreCase) ? f.Substring(root.Length + 1).Replace('\\', '/') : f;
                    byte[] r = Encoding.UTF8.GetBytes(rel); ms.Write(r, 0, r.Length); ms.WriteByte(0);
                    byte[] c; try { c = File.ReadAllBytes(f); } catch (IOException) { c = new byte[0]; } catch (UnauthorizedAccessException) { c = new byte[0]; }
                    ms.Write(c, 0, c.Length); ms.WriteByte(0);
                }
                return BitConverter.ToString(sha.ComputeHash(ms.ToArray())).Replace("-", "").ToLowerInvariant();
            }
        }

        static string StoreKey(string workspace, string kind) { return kind + "|" + Path.GetFullPath(workspace).TrimEnd('\\').ToLowerInvariant(); }

        static Dictionary<string, object> Load()
        {
            try { return new JavaScriptSerializer().DeserializeObject(Defaults.Str(Key, "{}")) as Dictionary<string, object> ?? new Dictionary<string, object>(); }
            catch (ArgumentException) { return new Dictionary<string, object>(); }
        }

        public static bool IsTrusted(string workspace, string kind, string fingerprint)
        {
            object v;
            return Load().TryGetValue(StoreKey(workspace, kind), out v) && (v as string) == fingerprint;
        }

        public static void Trust(string workspace, string kind, string fingerprint)
        {
            var d = Load(); d[StoreKey(workspace, kind)] = fingerprint;
            Defaults.Set(Key, new JavaScriptSerializer().Serialize(d));
            lock (Gate) Declined.Remove(fingerprint);
        }

        public static void Revoke(string workspace, string kind)
        {
            var d = Load(); d.Remove(StoreKey(workspace, kind));
            Defaults.Set(Key, new JavaScriptSerializer().Serialize(d));
        }

        /// <summary>True when the items may run. Asks at most once per fingerprint per session; headless runs (PNS daemon, snapshots,
        /// no UI) never ask and fail closed.</summary>
        public static bool RequestTrust(string workspace, string kind, List<Tuple<string, string>> items, string fingerprint)
        {
            if (items == null || items.Count == 0) return true;
            if (IsTrusted(workspace, kind, fingerprint)) return true;
            lock (Gate) if (Declined.Contains(fingerprint)) return false;
            bool trusted;
            if (Prompt != null) trusted = Prompt(workspace, items);
            else
            {
                var args = Environment.GetCommandLineArgs();
                var app = Application.Current;
                if (app == null || args.Contains("--pns-daemon") || args.Contains("--snapshot")) return false;
                trusted = false;
                app.Dispatcher.Invoke(new Action(() => { trusted = TrustDialog.Ask(workspace, kind, items); }));
            }
            if (trusted) Trust(workspace, kind, fingerprint);
            else lock (Gate) Declined.Add(fingerprint);
            return trusted;
        }
    }

    /// <summary>The trust alert (NSAlert on the Mac): what would run, "Keep Disabled" as the default, "Trust" to allow.</summary>
    static class TrustDialog
    {
        public static bool Ask(string workspace, string kind, List<Tuple<string, string>> items)
        {
            var t = Theme.Current;
            string folder = Path.GetFileName(Path.GetFullPath(workspace).TrimEnd('\\'));
            bool result = false;
            var w = new Window { Title = "MicroCode", Width = 520, SizeToContent = SizeToContent.Height, ResizeMode = ResizeMode.NoResize, WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = t.ElevatedBackground, FontFamily = UIFonts.UI, ShowInTaskbar = false };
            if (Application.Current != null && Application.Current.MainWindow != null && Application.Current.MainWindow.IsVisible) w.Owner = Application.Current.MainWindow;
            w.SourceInitialized += delegate { Native.StyleWindow(w, t.IsDark); };
            var col = V.VLead(10); col.Align = Cross.Stretch;
            col.Children.Add(V.H(10, Sym.Icon("exclamationmark.triangle.fill", 22, t.SysYellow), V.Wrap(V.T(kind == "project-skills" ? "Enable agent skills from “" + folder + "”?" : "Trust commands from “" + folder + "”?", 14, FontWeights.SemiBold, t.Primary), TextAlignment.Left)));
            col.Children.Add(V.Wrap(V.T(kind == "project-skills"
                ? "This workspace ships agent skills (instructions and scripts the AI agent can load and run). They will stay disabled until you enable them."
                : "This workspace ships configuration that runs programs on your PC (MCP servers / agent hooks). They will stay disabled until you trust them. Only trust folders you created or fully reviewed.", 12, FontWeights.Normal, t.Secondary), TextAlignment.Left));
            var list = V.VLead(6); list.Align = Cross.Stretch;
            foreach (var it in items.Take(12))
            {
                string detail = it.Item2 ?? ""; if (detail.Length > 160) detail = detail.Substring(0, 160);
                list.Children.Add(V.VLead(2, V.Wrap(V.T("• " + it.Item1, 11.5, FontWeights.Medium, t.Primary), TextAlignment.Left), V.Wrap(V.Mono("   " + detail, 10.5, FontWeights.Normal, t.Secondary), TextAlignment.Left)));
            }
            if (items.Count > 12) list.Children.Add(V.T("…and " + (items.Count - 12) + " more", 11, FontWeights.Normal, t.Secondary));
            col.Children.Add(V.Box(list, V.P(10), t.P(0.05), 6));
            var keep = V.Button(V.Box(V.T("Keep Disabled", 12, FontWeights.SemiBold, Brushes.White), V.P(14, 6), t.Accent, 6), () => { result = false; w.Close(); });
            var trust = V.Button(V.Box(V.T("Trust", 12, FontWeights.Medium, t.Primary), V.P(14, 6), t.P(0.1), 6), () => { result = true; w.Close(); });
            var buttons = V.H(8, V.Sp(), trust, keep); buttons.Margin = new Thickness(0, 6, 0, 0);
            col.Children.Add(buttons);
            w.Content = new System.Windows.Controls.Border { Padding = new Thickness(20), Child = col };
            w.KeyDown += (s, e) => { if (e.Key == System.Windows.Input.Key.Escape || e.Key == System.Windows.Input.Key.Enter) { result = false; w.Close(); } };
            w.ShowDialog();
            return result;
        }
    }
}
