// Port of SharedMemoryService.swift engines: CellParameterEngine (# @param widgets) and CellLineageDAGAnalyzer (reactive DAG).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace MicroCode.Views
{
    public class CellParam
    {
        public enum Kinds { SliderDouble, SliderInt, Dropdown, Toggle, Text }
        public string Name;
        public int LineIndex;
        public Kinds Kind;
        public double Min, Max, Step;
        public List<string> Options = new List<string>();
        public string StringValue = "";
        public double DoubleValue;
        public bool BoolValue;
    }

    /// <summary>CellParameterEngine: `x = 0.5  # @param [0.0..1.0, step=0.05]`, `name = "a" # @param ["a", "b"]`, `flag = True # @param`,
    /// or a header comment `# @param threshold: float = 0.75 [0.0..1.0, step=0.05]`.</summary>
    public static class CellParams
    {
        static readonly CultureInfo Inv = CultureInfo.InvariantCulture;
        static bool D(string s, out double v) { return double.TryParse(s, NumberStyles.Float, Inv, out v); }

        public static List<CellParam> Parse(string code)
        {
            var lines = (code ?? "").Split('\n');
            var specs = new List<CellParam>();
            for (int idx = 0; idx < lines.Length; idx++)
            {
                string raw = lines[idx].TrimEnd('\r');
                string trimmed = raw.Trim();
                if (!raw.Contains("@param")) continue;
                if (!trimmed.StartsWith("#") && !trimmed.StartsWith("//"))
                {
                    int h = raw.IndexOf('#'), sl = raw.IndexOf("//", StringComparison.Ordinal);
                    int c = h >= 0 ? h : sl;
                    if (c < 0) continue;
                    string lhs = raw.Substring(0, c), rhs = raw.Substring(c + (h >= 0 ? 1 : 2));
                    if (!rhs.Contains("@param")) continue;
                    int eq = lhs.IndexOf('=');
                    if (eq < 0) continue;
                    string name = lhs.Substring(0, eq).Trim();
                    foreach (var prefix in new[] { "let mut ", "let ", "var ", "const ", "auto ", "double ", "float ", "int ", "bool " })
                        if (name.StartsWith(prefix)) name = name.Substring(prefix.Length).Trim();
                    int colon = name.IndexOf(':');
                    if (colon >= 0) name = name.Substring(0, colon).Trim();
                    string val = lhs.Substring(eq + 1).Trim();
                    if (val.EndsWith(";")) val = val.Substring(0, val.Length - 1);
                    var spec = Build(name, idx, val, rhs);
                    if (spec != null) specs.Add(spec);
                }
                else
                {
                    int p = trimmed.IndexOf("@param", StringComparison.Ordinal);
                    string after = trimmed.Substring(p + 6).Trim();
                    int eq = after.IndexOf('=');
                    if (eq < 0) continue;
                    string varName = after.Substring(0, eq).Trim().Split(':')[0].Trim();
                    string valPart = after.Substring(eq + 1).Trim();
                    int b = valPart.IndexOf('[');
                    if (b >= 0) valPart = valPart.Substring(0, b).Trim();
                    string rawVal = valPart;
                    int target = idx;
                    if (idx + 1 < lines.Length && varName.Length > 0 && lines[idx + 1].Trim().StartsWith(varName) && lines[idx + 1].Contains("="))
                    {
                        target = idx + 1;
                        string next = lines[idx + 1].TrimEnd('\r');
                        rawVal = next.Substring(next.IndexOf('=') + 1).Trim();
                        if (rawVal.EndsWith(";")) rawVal = rawVal.Substring(0, rawVal.Length - 1);
                    }
                    if (varName.Length > 0) { var spec = Build(varName, target, rawVal, after); if (spec != null) specs.Add(spec); }
                }
            }
            return specs;
        }

        static CellParam Build(string name, int line, string rawValue, string meta)
        {
            if (string.IsNullOrEmpty(name)) return null;
            string unq = rawValue.Trim(' ', '"', '\'');
            string lower = unq.ToLowerInvariant();
            int ob = meta.IndexOf('['), cb = meta.LastIndexOf(']');
            if (ob >= 0 && cb > ob)
            {
                string inside = meta.Substring(ob + 1, cb - ob - 1).Trim();
                if (inside.Contains(".."))
                {
                    var parts = inside.Split(',');
                    var bounds = parts[0].Split(new[] { ".." }, StringSplitOptions.None);
                    if (bounds.Length == 2)
                    {
                        string minS = bounds[0].Trim(), maxS = bounds[1].Trim();
                        double? step = null;
                        foreach (var part in parts.Skip(1))
                        {
                            var kv = part.Split('=');
                            double sv; if (kv.Length == 2 && kv[0].Trim() == "step" && D(kv[1].Trim(), out sv)) step = sv;
                        }
                        bool floating = minS.Contains(".") || maxS.Contains(".") || rawValue.Contains(".") || (step.HasValue && Math.Floor(step.Value) != step.Value) || meta.Contains("float");
                        double lo, hi; int ilo, ihi;
                        if (floating && D(minS, out lo) && D(maxS, out hi) && hi > lo)
                        {
                            double cur; if (!D(unq, out cur)) cur = lo;
                            return new CellParam { Name = name, LineIndex = line, Kind = CellParam.Kinds.SliderDouble, Min = lo, Max = hi, Step = step ?? Math.Max((hi - lo) / 100.0, 0.0001), StringValue = unq, DoubleValue = Math.Min(Math.Max(cur, lo), hi) };
                        }
                        if (int.TryParse(minS, out ilo) && int.TryParse(maxS, out ihi) && ihi > ilo)
                        {
                            int cur; if (!int.TryParse(unq, out cur)) cur = ilo;
                            return new CellParam { Name = name, LineIndex = line, Kind = CellParam.Kinds.SliderInt, Min = ilo, Max = ihi, Step = Math.Max(1, (int)(step ?? 1)), StringValue = cur.ToString(Inv), DoubleValue = Math.Min(Math.Max(cur, ilo), ihi) };
                        }
                    }
                }
                else
                {
                    var opts = inside.Split(',').Select(o => o.Trim(' ', '"', '\'')).Where(o => o.Length > 0).ToList();
                    if (opts.Count >= 2)
                        return new CellParam { Name = name, LineIndex = line, Kind = CellParam.Kinds.Dropdown, Options = opts, StringValue = opts.Contains(unq) ? unq : opts[0] };
                }
            }
            if (lower == "true" || lower == "false")
            {
                bool bv = lower == "true";
                return new CellParam { Name = name, LineIndex = line, Kind = CellParam.Kinds.Toggle, StringValue = bv ? "True" : "False", DoubleValue = bv ? 1 : 0, BoolValue = bv };
            }
            double d;
            if (D(unq, out d))
            {
                if (unq.Contains("."))
                {
                    double hi = d == 0 ? 1.0 : Math.Max(Math.Abs(d) * 4.0, 1.0), lo = d < 0 ? -hi : 0.0;
                    return new CellParam { Name = name, LineIndex = line, Kind = CellParam.Kinds.SliderDouble, Min = lo, Max = hi, Step = Math.Max((hi - lo) / 100.0, 0.001), StringValue = unq, DoubleValue = d };
                }
                int i;
                if (int.TryParse(unq, out i))
                {
                    int hi = Math.Max(Math.Abs(i) * 4, 100), lo = i < 0 ? -hi : 0;
                    return new CellParam { Name = name, LineIndex = line, Kind = CellParam.Kinds.SliderInt, Min = lo, Max = hi, Step = 1, StringValue = i.ToString(Inv), DoubleValue = i };
                }
            }
            return new CellParam { Name = name, LineIndex = line, Kind = CellParam.Kinds.Text, StringValue = unq };
        }

        /// <summary>Rewrites the literal on the parameter's line, keeping indentation, a trailing `;` and the `# @param` comment.</summary>
        public static string Update(string code, CellParam spec, string newLiteral)
        {
            var lines = (code ?? "").Split('\n').ToList();
            if (spec.LineIndex < 0 || spec.LineIndex >= lines.Count) return code;
            string line = lines[spec.LineIndex];
            string cr = line.EndsWith("\r") ? "\r" : "";
            line = line.TrimEnd('\r');
            string t = line.Trim();
            if (t.StartsWith("#") || t.StartsWith("//"))
            {
                lines.Insert(spec.LineIndex + 1, spec.Name + " = " + newLiteral);
                return string.Join("\n", lines);
            }
            int h = line.IndexOf('#'), sl = line.IndexOf("//", StringComparison.Ordinal);
            int ci = h >= 0 ? h : sl;
            string codePart = ci >= 0 ? line.Substring(0, ci) : line;
            string commentPart = ci >= 0 ? "  " + line.Substring(ci) : "";
            bool semi = codePart.Trim().EndsWith(";");
            int eq = codePart.IndexOf('=');
            if (eq < 0) return code;
            string lhs = codePart.Substring(0, eq).Trim();
            string indent = new string(line.TakeWhile(ch => ch == ' ' || ch == '\t').ToArray());
            lines[spec.LineIndex] = indent + lhs + " = " + newLiteral + (semi ? ";" : "") + commentPart + cr;
            return string.Join("\n", lines);
        }

        public static string FormatDouble(double v, double step) { return v.ToString(step < 0.01 ? "0.0000" : "0.00", Inv); }
    }

    public class CellDagInfo
    {
        public string CellId;
        public int CellNumber;
        public HashSet<string> Defined = new HashSet<string>();
        public List<string> UpstreamSymbols = new List<string>();
        public List<int> UpstreamNumbers = new List<int>();
        public List<string> Downstream = new List<string>();
        public bool IsStale;
    }

    /// <summary>CellLineageDAGAnalyzer: static def/ref extraction per cell, latest-producer lineage, stale detection by run epoch.</summary>
    public static class CellDag
    {
        static readonly HashSet<string> Ignored = new HashSet<string>
        {
            "import", "from", "as", "def", "class", "return", "if", "elif", "else", "for", "while", "in", "not", "and", "or", "is", "None", "True", "False",
            "try", "except", "finally", "with", "lambda", "yield", "async", "await", "pass", "break", "continue", "global", "print", "len", "range", "list",
            "dict", "set", "str", "int", "float", "bool", "type", "enumerate", "zip", "min", "max", "sum", "abs", "round", "open", "display", "pd", "np",
            "plt", "sns", "os", "sys", "json", "math", "time", "Path", "shm", "self", "let", "mut", "fn", "func", "var", "const", "pub", "struct", "enum",
            "impl", "use", "package", "main", "std", "cout", "endl", "include", "SELECT", "FROM", "WHERE", "GROUP", "BY", "ORDER", "LIMIT", "JOIN", "LEFT",
            "INNER", "ON", "AS", "INSERT", "INTO", "CREATE", "TABLE"
        };

        static bool IsIdent(string s) { return s.Length >= 2 && (char.IsLetter(s[0]) || s[0] == '_') && !Ignored.Contains(s); }

        static int SingleAssign(string line)
        {
            int depth = 0;
            for (int i = 0; i < line.Length; i++)
            {
                char c = line[i];
                if (c == '(' || c == '[' || c == '{') depth++;
                else if (c == ')' || c == ']' || c == '}') depth = Math.Max(0, depth - 1);
                else if (c == '=' && depth == 0)
                {
                    char prev = i > 0 ? line[i - 1] : ' ', next = i + 1 < line.Length ? line[i + 1] : ' ';
                    if (next == '=' || next == '>') continue;
                    if (prev == '=' || prev == '!' || prev == '<' || prev == '>') continue;
                    return i;
                }
            }
            return -1;
        }

        public static void Extract(string code, HashSet<string> defs, HashSet<string> refs)
        {
            foreach (var rawLine in (code ?? "").Split('\n'))
            {
                string t = rawLine.Trim();
                if (t.Length == 0 || t.StartsWith("#") || t.StartsWith("//") || t.StartsWith("--")) continue;
                string c = t;
                int hc = t.IndexOf(" #", StringComparison.Ordinal), sc = t.IndexOf("//", StringComparison.Ordinal);
                if (hc >= 0) c = t.Substring(0, hc); else if (sc >= 0) c = t.Substring(0, sc);
                foreach (var kw in new[] { "def ", "class ", "fn ", "func " })
                    if (c.StartsWith(kw))
                    {
                        string ident = new string(c.Substring(kw.Length).TakeWhile(ch => char.IsLetterOrDigit(ch) || ch == '_').ToArray());
                        if (ident.Length >= 2 && !Ignored.Contains(ident)) defs.Add(ident);
                    }
                int arrow = c.IndexOf("<-", StringComparison.Ordinal);
                if (arrow >= 0) { string lhs = c.Substring(0, arrow).Trim(); if (IsIdent(lhs) && lhs.All(ch => char.IsLetterOrDigit(ch) || ch == '_')) defs.Add(lhs); }
                else
                {
                    int eq = SingleAssign(c);
                    if (eq >= 0)
                    {
                        string lhs = c.Substring(0, eq).Trim();
                        foreach (var prefix in new[] { "let mut ", "let ", "var ", "const ", "auto " }) if (lhs.StartsWith(prefix)) lhs = lhs.Substring(prefix.Length).Trim();
                        int colon = lhs.IndexOf(':'); if (colon >= 0) lhs = lhs.Substring(0, colon).Trim();
                        foreach (var cand in lhs.Split(','))
                        {
                            string clean = cand.Trim('(', ')', '[', ']', ' ', '\t');
                            if (IsIdent(clean) && clean.All(ch => char.IsLetterOrDigit(ch) || ch == '_')) defs.Add(clean);
                        }
                    }
                }
                var cur = new System.Text.StringBuilder();
                foreach (char ch in c)
                {
                    if (char.IsLetterOrDigit(ch) || ch == '_') cur.Append(ch);
                    else { if (IsIdent(cur.ToString())) refs.Add(cur.ToString()); cur.Clear(); }
                }
                if (IsIdent(cur.ToString())) refs.Add(cur.ToString());
            }
        }

        public static Dictionary<string, CellDagInfo> Analyze(IList<NbCell> cells)
        {
            var result = new Dictionary<string, CellDagInfo>();
            var producer = new Dictionary<string, Tuple<string, int, int>>();       // symbol → (cellId, number, epoch)
            var ups = new Dictionary<string, List<Tuple<string, int, string, int>>>();
            var downs = new Dictionary<string, List<string>>();
            var nodes = new List<Tuple<NbCell, int, HashSet<string>, HashSet<string>>>();
            for (int i = 0; i < cells.Count; i++)
            {
                var c = cells[i];
                if (c.Type != "Code" && c.Type != "Procedure") continue;
                var defs = new HashSet<string>(); var refs = new HashSet<string>();
                Extract(c.Type == "Procedure" ? c.GeneratedCode : c.Content, defs, refs);
                nodes.Add(Tuple.Create(c, i + 1, defs, refs));
            }
            foreach (var n in nodes)
            {
                var list = new List<Tuple<string, int, string, int>>();
                foreach (var r in n.Item4.OrderBy(x => x, StringComparer.Ordinal))
                {
                    Tuple<string, int, int> prod;
                    if (producer.TryGetValue(r, out prod) && prod.Item1 != n.Item1.Id)
                    {
                        list.Add(Tuple.Create(prod.Item1, prod.Item2, r, prod.Item3));
                        List<string> d; if (!downs.TryGetValue(prod.Item1, out d)) downs[prod.Item1] = d = new List<string>();
                        if (!d.Contains(n.Item1.Id)) d.Add(n.Item1.Id);
                    }
                }
                ups[n.Item1.Id] = list;
                foreach (var def in n.Item3) producer[def] = Tuple.Create(n.Item1.Id, n.Item2, n.Item1.LastRunEpoch);
            }
            foreach (var n in nodes)
            {
                var u = ups[n.Item1.Id];
                List<string> d; downs.TryGetValue(n.Item1.Id, out d);
                result[n.Item1.Id] = new CellDagInfo
                {
                    CellId = n.Item1.Id, CellNumber = n.Item2, Defined = n.Item3,
                    UpstreamSymbols = u.Select(x => x.Item3).Distinct().OrderBy(x => x, StringComparer.Ordinal).ToList(),
                    UpstreamNumbers = u.Select(x => x.Item2).Distinct().OrderBy(x => x).ToList(),
                    Downstream = d ?? new List<string>(),
                    IsStale = n.Item1.LastRunEpoch > 0 && u.Any(x => x.Item4 > n.Item1.LastRunEpoch)
                };
            }
            return result;
        }

        public static List<string> TransitiveDownstream(string root, Dictionary<string, CellDagInfo> graph, IList<NbCell> ordered)
        {
            var reach = new HashSet<string>();
            CellDagInfo info;
            var queue = new Queue<string>(graph.TryGetValue(root, out info) ? info.Downstream : new List<string>());
            while (queue.Count > 0)
            {
                string next = queue.Dequeue();
                if (reach.Add(next) && graph.TryGetValue(next, out info)) foreach (var x in info.Downstream) queue.Enqueue(x);
            }
            return ordered.Where(c => reach.Contains(c.Id)).Select(c => c.Id).ToList();
        }
    }
}
