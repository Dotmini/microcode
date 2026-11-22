// Native Windows Studios: Science, RemoteX, Scenario, Embedded & IoT, Extension Marketplace,
// Database, Containers, CI/CD Pipelines, and Cloud GPU Hub.
// Strict C# 5 (.NET Framework 4.8, zero NuGet dependencies).
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.IO.Ports;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public static class AppStateStudioExtensions
    {
        public static void OpenFile(this AppState app, string path)
        {
            if (app != null && !string.IsNullOrEmpty(path)) app.LoadFile(path);
        }
    }

    public class StudioExecResult
    {
        public int ExitCode;
        public string StdOut = "";
        public string StdErr = "";
        public long ElapsedMs;
        public bool TimedOut;
        public bool Ok { get { return !TimedOut && ExitCode == 0; } }
        public string Combined
        {
            get
            {
                if (string.IsNullOrEmpty(StdErr)) return StdOut ?? "";
                if (string.IsNullOrEmpty(StdOut)) return StdErr;
                return StdOut.TrimEnd() + "\n" + StdErr;
            }
        }
    }

    public static class StudioProcess
    {
        public static bool IsWindows
        {
            get
            {
                PlatformID p = Environment.OSVersion.Platform;
                return p == PlatformID.Win32NT || p == PlatformID.Win32Windows || p == PlatformID.Win32S || p == PlatformID.WinCE;
            }
        }

        public static string QuoteArg(string s)
        {
            if (s == null) return "\"\"";
            return "\"" + s.Replace("\"", "\\\"") + "\"";
        }

        public static StudioExecResult Run(string exe, string args, string workDir, int timeoutMs, Action<string> onLine)
        {
            var res = new StudioExecResult();
            var sw = Stopwatch.StartNew();
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = exe,
                    Arguments = args ?? "",
                    WorkingDirectory = (!string.IsNullOrEmpty(workDir) && Directory.Exists(workDir)) ? workDir : Environment.CurrentDirectory,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    StandardOutputEncoding = Encoding.UTF8,
                    StandardErrorEncoding = Encoding.UTF8
                };
                using (var proc = new Process { StartInfo = psi })
                {
                    var outSb = new StringBuilder();
                    var errSb = new StringBuilder();
                    var gate = new object();
                    proc.OutputDataReceived += delegate(object s, DataReceivedEventArgs e)
                    {
                        if (e.Data == null) return;
                        lock (gate) { outSb.AppendLine(e.Data); }
                        if (onLine != null) onLine(e.Data);
                    };
                    proc.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e)
                    {
                        if (e.Data == null) return;
                        lock (gate) { errSb.AppendLine(e.Data); }
                        if (onLine != null) onLine(e.Data);
                    };
                    proc.Start();
                    proc.BeginOutputReadLine();
                    proc.BeginErrorReadLine();
                    int wait = timeoutMs > 0 ? timeoutMs : 30000;
                    if (!proc.WaitForExit(wait))
                    {
                        res.TimedOut = true;
                        try { proc.Kill(); } catch { }
                        res.ExitCode = -1;
                    }
                    else
                    {
                        proc.WaitForExit();
                        res.ExitCode = proc.ExitCode;
                    }
                    lock (gate)
                    {
                        res.StdOut = outSb.ToString();
                        res.StdErr = errSb.ToString();
                    }
                }
            }
            catch (Exception ex)
            {
                res.ExitCode = -1;
                res.StdErr = ex.Message;
            }
            sw.Stop();
            res.ElapsedMs = sw.ElapsedMilliseconds;
            return res;
        }

        public static StudioExecResult RunShell(string command, string workDir, int timeoutMs, Action<string> onLine)
        {
            if (IsWindows) return Run("cmd.exe", "/c " + (command ?? ""), workDir, timeoutMs, onLine);
            return Run("/bin/sh", "-c " + QuoteArg(command ?? ""), workDir, timeoutMs, onLine);
        }

        public static string FindExecutable(params string[] candidates)
        {
            if (candidates == null) return null;
            for (int i = 0; i < candidates.Length; i++)
            {
                string c = candidates[i];
                if (string.IsNullOrEmpty(c)) continue;
                if (Path.IsPathRooted(c))
                {
                    if (File.Exists(c)) return c;
                    continue;
                }
                string pathEnv = Environment.GetEnvironmentVariable("PATH") ?? "";
                string[] dirs = pathEnv.Split(Path.PathSeparator);
                for (int d = 0; d < dirs.Length; d++)
                {
                    if (string.IsNullOrWhiteSpace(dirs[d])) continue;
                    string full = Path.Combine(dirs[d].Trim(), c);
                    if (File.Exists(full)) return full;
                    if (IsWindows && !c.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) && File.Exists(full + ".exe"))
                        return full + ".exe";
                }
            }
            return null;
        }
    }

    internal static class StudioUi
    {
        public static UIElement Header(string icon, string title, string subtitle, params UIElement[] rightControls)
        {
            var t = Theme.Current;
            var row = V.H(8,
                Sym.Icon(icon, 15, t.Accent),
                V.VLead(1,
                    V.T(title, 13.5, FontWeights.SemiBold, t.Primary),
                    string.IsNullOrEmpty(subtitle) ? null : V.T(subtitle, 10.5, FontWeights.Normal, t.Secondary)),
                V.Sp());
            if (rightControls != null)
            {
                for (int i = 0; i < rightControls.Length; i++)
                    if (rightControls[i] != null) row.Children.Add(rightControls[i]);
            }
            return V.Box(row, V.P(14, 10), t.PanelBackground, 0, t.Separator, 0);
        }

        public static Btn PillButton(string label, string icon, bool accent, Action onClick)
        {
            var t = Theme.Current;
            Brush bg = accent ? t.Accent : t.P(0.08);
            Brush fg = accent ? Brushes.White : t.Primary;
            var content = string.IsNullOrEmpty(icon)
                ? (UIElement)V.T(label, 11.5, FontWeights.SemiBold, fg)
                : V.H(5, Sym.Icon(icon, 11, fg), V.T(label, 11.5, FontWeights.SemiBold, fg));
            var b = V.Button(V.Box(content, V.P(10, 5), bg, 6), onClick);
            b.Cursor = Cursors.Hand;
            return b;
        }

        public static UIElement TabBar(string[] labels, int activeIdx, Action<int> onSelect)
        {
            var t = Theme.Current;
            var row = V.H(4);
            for (int i = 0; i < labels.Length; i++)
            {
                int idx = i;
                bool active = idx == activeIdx;
                var tab = V.Button(
                    V.Box(V.T(labels[i], 11.5, active ? FontWeights.SemiBold : FontWeights.Normal, active ? t.Primary : t.Secondary),
                        V.P(10, 4), active ? t.P(0.14) : Brushes.Transparent, 5),
                    delegate { onSelect(idx); });
                tab.Cursor = Cursors.Hand;
                row.Children.Add(tab);
            }
            return V.Box(row, V.P(3), t.P(0.05), 7);
        }

        public static Grid SafeField(string placeholder, string initial, double fontSize, out TextBox box)
        {
            var t = Theme.Current;
            var g = new Grid();
            var ph = V.T(placeholder, fontSize, FontWeights.Normal, t.Tertiary);
            ph.IsHitTestVisible = false;
            ph.Margin = new Thickness(4, 0, 0, 0);
            TextBox tb;
            if (Application.Current != null && Application.Current.TryFindResource("PlainTextBox") != null)
            {
                tb = Styles.PlainField(placeholder, fontSize, t.Primary);
            }
            else
            {
                tb = new TextBox
                {
                    Background = Brushes.Transparent,
                    BorderThickness = new Thickness(0),
                    FontFamily = UIFonts.UI,
                    FontSize = fontSize,
                    Foreground = t.Primary,
                    VerticalContentAlignment = VerticalAlignment.Center
                };
            }
            tb.Text = initial ?? "";
            ph.Visibility = tb.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
            tb.TextChanged += delegate { ph.Visibility = tb.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed; };
            g.Children.Add(ph);
            g.Children.Add(tb);
            box = tb;
            return g;
        }

        public static Border InputBox(string placeholder, string initial, double minWidth, out TextBox box)
        {
            var t = Theme.Current;
            var g = SafeField(placeholder, initial, 12, out box);
            if (minWidth > 0) g.MinWidth = minWidth;
            return V.Box(g, V.P(8, 5), t.ControlBackground, 6, t.Separator, 1);
        }

        public static TextBox MultiLineEditor(string initial, bool readOnly, bool mono)
        {
            var t = Theme.Current;
            return new TextBox
            {
                Text = initial ?? "",
                IsReadOnly = readOnly,
                AcceptsReturn = true,
                AcceptsTab = true,
                TextWrapping = TextWrapping.Wrap,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                FontFamily = mono ? UIFonts.Mono : UIFonts.UI,
                FontSize = 12,
                Foreground = t.EditorText,
                Background = t.EditorBackground,
                BorderBrush = t.Separator,
                BorderThickness = new Thickness(1),
                Padding = new Thickness(8),
                CaretBrush = t.Primary
            };
        }

        public static UIElement MetricCard(string label, string value, Brush accent)
        {
            var t = Theme.Current;
            return V.Box(
                V.VLead(2,
                    V.T(label, 10, FontWeights.Medium, t.Secondary),
                    V.T(value, 14, FontWeights.SemiBold, accent ?? t.Primary)),
                V.P(12, 8), t.ElevatedBackground, 8, t.Separator, 1);
        }

        public static ScrollViewer Scroller(UIElement child)
        {
            return new ScrollViewer
            {
                Content = child,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
            };
        }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 1. SCIENCE STUDIO (Bioinformatics, PubChem/PDB/UniProt/AlphaFold, AF3 JSON)
    // ═════════════════════════════════════════════════════════════════════════════

    public class FastaRecord
    {
        public string Header = "";
        public string Id = "";
        public string Description = "";
        public string Sequence = "";
    }

    public class ProteinAnalysis
    {
        public string Id = "";
        public int Length;
        public double MolecularWeightDa;
        public double MolecularWeightKDa;
        public double TheoreticalPI;
        public double NetChargeAtPh74;
        public double Gravy;
        public Dictionary<char, int> Composition = new Dictionary<char, int>();
        public Dictionary<char, double> CompositionPct = new Dictionary<char, double>();
        public List<char> InvalidCharacters = new List<char>();
    }

    public class MoleculeLookupResult
    {
        public bool Ok;
        public string Error = "";
        public string Query = "";
        public string Cid = "";
        public string Formula = "";
        public string MolecularWeight = "";
        public string CanonicalSmiles = "";
        public string IupacName = "";
        public string XLogP = "";
        public string Tpsa = "";
        public string RawJson = "";
    }

    public class BioEntryResult
    {
        public bool Ok;
        public string Source = "";
        public string Id = "";
        public string Title = "";
        public string Organism = "";
        public string Details = "";
        public string Sequence = "";
        public string ModelUrl = "";
        public string Error = "";
        public string RawJson = "";
    }

    public static class ScienceService
    {
        static readonly Dictionary<char, double> ResidueMass = new Dictionary<char, double>
        {
            {'A', 71.0788}, {'R', 156.1875}, {'N', 114.1038}, {'D', 115.0886}, {'C', 103.1388},
            {'E', 129.1155}, {'Q', 128.1307}, {'G', 57.0519},  {'H', 137.1411}, {'I', 113.1594},
            {'L', 113.1594}, {'K', 128.1741}, {'M', 131.1926}, {'F', 147.1766}, {'P', 97.1167},
            {'S', 87.0782},  {'T', 101.1051}, {'W', 186.2132}, {'Y', 163.1760}, {'V', 99.1326},
            {'U', 150.0388}, {'O', 237.3018}, {'X', 110.0}
        };

        static readonly Dictionary<char, double> Hydropathy = new Dictionary<char, double>
        {
            {'A', 1.8},  {'R', -4.5}, {'N', -3.5}, {'D', -3.5}, {'C', 2.5},
            {'Q', -3.5}, {'E', -3.5}, {'G', -0.4}, {'H', -3.2}, {'I', 4.5},
            {'L', 3.8},  {'K', -3.9}, {'M', 1.9},  {'F', 2.8},  {'P', -1.6},
            {'S', -0.8}, {'T', -0.7}, {'W', -0.9}, {'Y', -1.3}, {'V', 4.2}
        };

        const double H2OMass = 18.01528;

        public static List<FastaRecord> ParseFasta(string text)
        {
            var list = new List<FastaRecord>();
            if (string.IsNullOrWhiteSpace(text)) return list;
            string[] lines = text.Replace("\r\n", "\n").Split('\n');
            FastaRecord cur = null;
            var seq = new StringBuilder();
            for (int i = 0; i < lines.Length; i++)
            {
                string line = lines[i].Trim();
                if (line.Length == 0) continue;
                if (line.StartsWith(">"))
                {
                    if (cur != null)
                    {
                        cur.Sequence = seq.ToString();
                        list.Add(cur);
                    }
                    string hdr = line.Substring(1).Trim();
                    int sp = hdr.IndexOf(' ');
                    string id = sp > 0 ? hdr.Substring(0, sp) : hdr;
                    string desc = sp > 0 ? hdr.Substring(sp + 1).Trim() : "";
                    cur = new FastaRecord { Header = hdr, Id = id, Description = desc };
                    seq.Clear();
                }
                else
                {
                    if (cur == null) cur = new FastaRecord { Header = "seq_1", Id = "seq_1", Description = "" };
                    for (int k = 0; k < line.Length; k++)
                    {
                        char ch = char.ToUpperInvariant(line[k]);
                        if (ch >= 'A' && ch <= 'Z') seq.Append(ch);
                    }
                }
            }
            if (cur != null)
            {
                cur.Sequence = seq.ToString();
                if (cur.Sequence.Length > 0 || !string.IsNullOrEmpty(cur.Header)) list.Add(cur);
            }
            return list;
        }

        public static double NetChargeAtPh(string sequence, double ph)
        {
            if (string.IsNullOrEmpty(sequence)) return 0.0;
            int nD = 0, nE = 0, nC = 0, nY = 0, nH = 0, nK = 0, nR = 0;
            for (int i = 0; i < sequence.Length; i++)
            {
                switch (char.ToUpperInvariant(sequence[i]))
                {
                    case 'D': nD++; break;
                    case 'E': nE++; break;
                    case 'C': nC++; break;
                    case 'Y': nY++; break;
                    case 'H': nH++; break;
                    case 'K': nK++; break;
                    case 'R': nR++; break;
                }
            }
            double pos =
                1.0 / (1.0 + Math.Pow(10.0, ph - 8.6)) +
                nH / (1.0 + Math.Pow(10.0, ph - 6.5)) +
                nK / (1.0 + Math.Pow(10.0, ph - 10.8)) +
                nR / (1.0 + Math.Pow(10.0, ph - 12.5));
            double neg =
                1.0 / (1.0 + Math.Pow(10.0, 3.6 - ph)) +
                nD / (1.0 + Math.Pow(10.0, 3.9 - ph)) +
                nE / (1.0 + Math.Pow(10.0, 4.1 - ph)) +
                nC / (1.0 + Math.Pow(10.0, 8.5 - ph)) +
                nY / (1.0 + Math.Pow(10.0, 10.1 - ph));
            return pos - neg;
        }

        public static double ComputeTheoreticalPI(string sequence)
        {
            if (string.IsNullOrEmpty(sequence)) return 0.0;
            double lo = 0.0, hi = 14.0;
            for (int iter = 0; iter < 50; iter++)
            {
                double mid = 0.5 * (lo + hi);
                double q = NetChargeAtPh(sequence, mid);
                if (q > 0.0) lo = mid; else hi = mid;
            }
            return Math.Round(0.5 * (lo + hi), 2);
        }

        public static ProteinAnalysis AnalyzeProtein(string sequenceOrFasta)
        {
            var records = ParseFasta(sequenceOrFasta);
            string id = records.Count > 0 ? records[0].Id : "seq_1";
            string seq = records.Count > 0 ? records[0].Sequence : "";
            var a = new ProteinAnalysis { Id = id, Length = seq.Length };
            if (seq.Length == 0) return a;

            double mw = H2OMass;
            double gravySum = 0.0;
            int gravyCount = 0;

            for (int i = 0; i < seq.Length; i++)
            {
                char aa = seq[i];
                int cnt;
                a.Composition.TryGetValue(aa, out cnt);
                a.Composition[aa] = cnt + 1;

                double mass;
                if (ResidueMass.TryGetValue(aa, out mass))
                {
                    mw += mass;
                }
                else
                {
                    mw += 110.0;
                    if (!a.InvalidCharacters.Contains(aa)) a.InvalidCharacters.Add(aa);
                }

                double hp;
                if (Hydropathy.TryGetValue(aa, out hp))
                {
                    gravySum += hp;
                    gravyCount++;
                }
            }

            foreach (var kv in a.Composition)
            {
                a.CompositionPct[kv.Key] = Math.Round(100.0 * kv.Value / seq.Length, 2);
            }

            a.MolecularWeightDa = Math.Round(mw, 2);
            a.MolecularWeightKDa = Math.Round(mw / 1000.0, 4);
            a.TheoreticalPI = ComputeTheoreticalPI(seq);
            a.NetChargeAtPh74 = Math.Round(NetChargeAtPh(seq, 7.4), 2);
            a.Gravy = gravyCount > 0 ? Math.Round(gravySum / gravyCount, 3) : 0.0;
            return a;
        }

        public static async Task<MoleculeLookupResult> LookupPubChemAsync(string query)
        {
            var res = new MoleculeLookupResult { Query = query ?? "" };
            string q = (query ?? "").Trim();
            if (q.Length == 0) { res.Error = "Enter a compound name, CID, or SMILES."; return res; }
            try
            {
                string mode = "name";
                int cidNum;
                if (int.TryParse(q, out cidNum)) mode = "cid";
                else if (q.Contains("=") || q.Contains("(") || q.Contains("#") || q.Contains("[")) mode = "smiles";

                string enc = Uri.EscapeDataString(q);
                string url = "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/" + mode + "/" + enc +
                    "/property/MolecularFormula,MolecularWeight,CanonicalSMILES,IUPACName,XLogP,TPSA/JSON";
                string body = await DotminiNet.Http.GetStringAsync(url);
                res.RawJson = body;
                var root = DJ.Obj(body);
                var pt = DJ.Child(root, "PropertyTable");
                var props = DJ.Arr(pt, "Properties");
                if (props == null || props.Count == 0)
                {
                    res.Error = "No compound found in PubChem.";
                    return res;
                }
                var p = props[0] as Dictionary<string, object>;
                res.Cid = DJ.Str(p, "CID") ?? "";
                res.Formula = DJ.Str(p, "MolecularFormula") ?? "";
                res.MolecularWeight = DJ.Str(p, "MolecularWeight") ?? "";
                res.CanonicalSmiles = DJ.Str(p, "CanonicalSMILES") ?? DJ.Str(p, "ConnectivitySMILES") ?? "";
                res.IupacName = DJ.Str(p, "IUPACName") ?? "";
                res.XLogP = DJ.Str(p, "XLogP") ?? "";
                res.Tpsa = DJ.Str(p, "TPSA") ?? "";
                res.Ok = true;
            }
            catch (Exception ex)
            {
                res.Error = ex.Message;
            }
            return res;
        }

        public static async Task<BioEntryResult> LookupUniProtAsync(string accession)
        {
            var res = new BioEntryResult { Source = "UniProt", Id = (accession ?? "").Trim() };
            if (res.Id.Length == 0) { res.Error = "Enter a UniProt accession (e.g. P01308)."; return res; }
            try
            {
                string url = "https://rest.uniprot.org/uniprotkb/" + Uri.EscapeDataString(res.Id) + ".json";
                string body = await DotminiNet.Http.GetStringAsync(url);
                res.RawJson = body;
                var o = DJ.Obj(body);
                if (o == null) { res.Error = "Invalid UniProt JSON."; return res; }
                var pd = DJ.Child(o, "proteinDescription");
                var rec = DJ.Child(pd, "recommendedName");
                var fn = DJ.Child(rec, "fullName");
                res.Title = DJ.Str(fn, "value") ?? DJ.Str(o, "uniProtkbId") ?? res.Id;
                var org = DJ.Child(o, "organism");
                res.Organism = DJ.Str(org, "scientificName") ?? "";
                var seqObj = DJ.Child(o, "sequence");
                res.Sequence = DJ.Str(seqObj, "value") ?? "";
                res.Details = "Length: " + (DJ.Str(seqObj, "length") ?? res.Sequence.Length.ToString()) + " aa";
                res.Ok = true;
            }
            catch (Exception ex) { res.Error = ex.Message; }
            return res;
        }

        public static async Task<BioEntryResult> LookupPdbAsync(string pdbId)
        {
            var res = new BioEntryResult { Source = "RCSB PDB", Id = (pdbId ?? "").Trim().ToUpperInvariant() };
            if (res.Id.Length == 0) { res.Error = "Enter a PDB ID (e.g. 4HHB)."; return res; }
            try
            {
                string url = "https://data.rcsb.org/rest/v1/core/entry/" + Uri.EscapeDataString(res.Id);
                string body = await DotminiNet.Http.GetStringAsync(url);
                res.RawJson = body;
                var o = DJ.Obj(body);
                if (o == null) { res.Error = "Invalid RCSB PDB response."; return res; }
                var st = DJ.Child(o, "struct");
                res.Title = DJ.Str(st, "title") ?? res.Id;
                var exptl = DJ.Arr(o, "exptl");
                string method = "";
                if (exptl != null && exptl.Count > 0)
                    method = DJ.Str(exptl[0] as Dictionary<string, object>, "method") ?? "";
                var info = DJ.Child(o, "rcsb_entry_info");
                var resArr = DJ.Arr(info, "resolution_combined");
                string resol = (resArr != null && resArr.Count > 0) ? Convert.ToString(resArr[0], CultureInfo.InvariantCulture) + " A" : "";
                res.Details = (method + (string.IsNullOrEmpty(resol) ? "" : " | " + resol)).Trim();
                res.ModelUrl = "https://files.rcsb.org/download/" + res.Id + ".cif";
                res.Ok = true;
            }
            catch (Exception ex) { res.Error = ex.Message; }
            return res;
        }

        public static async Task<BioEntryResult> LookupAlphaFoldAsync(string uniprotId)
        {
            var res = new BioEntryResult { Source = "AlphaFold DB", Id = (uniprotId ?? "").Trim().ToUpperInvariant() };
            if (res.Id.Length == 0) { res.Error = "Enter a UniProt ID (e.g. P01308)."; return res; }
            try
            {
                string url = "https://alphafold.ebi.ac.uk/api/prediction/" + Uri.EscapeDataString(res.Id);
                string body = await DotminiNet.Http.GetStringAsync(url);
                res.RawJson = body;
                var arr = DJ.S.DeserializeObject(body) as object[];
                if (arr == null || arr.Length == 0) { res.Error = "No AlphaFold prediction found."; return res; }
                var o = arr[0] as Dictionary<string, object>;
                res.Title = DJ.Str(o, "gene") ?? DJ.Str(o, "uniprotDescription") ?? res.Id;
                res.Organism = DJ.Str(o, "organismScientificName") ?? "";
                res.Sequence = DJ.Str(o, "uniprotSequence") ?? "";
                res.ModelUrl = DJ.Str(o, "cifUrl") ?? DJ.Str(o, "pdbUrl") ?? "";
                res.Details = "Entry: " + (DJ.Str(o, "entryId") ?? "") + " | pLDDT: " + (DJ.Str(o, "globalMetricValue") ?? "n/a");
                res.Ok = true;
            }
            catch (Exception ex) { res.Error = ex.Message; }
            return res;
        }

        public static string GenerateAlphaFold3Json(string jobName, string proteinSequence, string ligandSmiles, int copies)
        {
            var recs = ParseFasta(proteinSequence);
            string seq = recs.Count > 0 ? recs[0].Sequence : (proteinSequence ?? "").Trim().ToUpperInvariant();
            if (copies < 1) copies = 1;
            var sequences = new List<object>();
            if (!string.IsNullOrEmpty(seq))
            {
                var ids = new List<string>();
                for (int i = 0; i < copies; i++) ids.Add(((char)('A' + (i % 26))).ToString());
                sequences.Add(new Dictionary<string, object>
                {
                    { "protein", new Dictionary<string, object> { { "id", ids.Count == 1 ? (object)ids[0] : ids.ToArray() }, { "sequence", seq } } }
                });
            }
            if (!string.IsNullOrWhiteSpace(ligandSmiles))
            {
                sequences.Add(new Dictionary<string, object>
                {
                    { "ligand", new Dictionary<string, object> { { "id", "L" }, { "smiles", ligandSmiles.Trim() } } }
                });
            }
            var job = new Dictionary<string, object>
            {
                { "name", string.IsNullOrWhiteSpace(jobName) ? "microcode_af3_job" : jobName.Trim() },
                { "modelSeeds", new int[] { 1 } },
                { "sequences", sequences.ToArray() },
                { "dialect", "alphafold3" },
                { "version", 1 }
            };
            return PrettyJson(DJ.Ser(job));
        }

        public static bool ValidateAlphaFold3Json(string json, out List<string> errors)
        {
            errors = new List<string>();
            var root = DJ.Obj(json);
            if (root == null) { errors.Add("Invalid JSON object."); return false; }

            if (string.IsNullOrWhiteSpace(DJ.Str(root, "name")))
                errors.Add("Missing required 'name' field.");

            var seeds = DJ.Arr(root, "modelSeeds");
            if (seeds == null || seeds.Count == 0)
                errors.Add("Missing or empty 'modelSeeds' array.");

            var seqs = DJ.Arr(root, "sequences");
            if (seqs == null || seqs.Count == 0)
            {
                errors.Add("Missing or empty 'sequences' array.");
            }
            else
            {
                for (int i = 0; i < seqs.Count; i++)
                {
                    var item = seqs[i] as Dictionary<string, object>;
                    if (item == null) { errors.Add("sequences[" + i + "] must be an object."); continue; }
                    var prot = DJ.Child(item, "protein");
                    var dna = DJ.Child(item, "dna");
                    var rna = DJ.Child(item, "rna");
                    var lig = DJ.Child(item, "ligand");
                    if (prot == null && dna == null && rna == null && lig == null)
                    {
                        errors.Add("sequences[" + i + "] must specify protein, dna, rna, or ligand.");
                        continue;
                    }
                    if (prot != null)
                    {
                        string s = DJ.Str(prot, "sequence") ?? "";
                        if (s.Length == 0) errors.Add("sequences[" + i + "].protein.sequence is empty.");
                        for (int k = 0; k < s.Length; k++)
                        {
                            char c = char.ToUpperInvariant(s[k]);
                            if (!ResidueMass.ContainsKey(c))
                            {
                                errors.Add("sequences[" + i + "].protein.sequence has invalid amino acid '" + s[k] + "'.");
                                break;
                            }
                        }
                    }
                    if (lig != null && string.IsNullOrWhiteSpace(DJ.Str(lig, "smiles")) && DJ.Arr(lig, "ccdCodes") == null)
                        errors.Add("sequences[" + i + "].ligand requires 'smiles' or 'ccdCodes'.");
                }
            }
            return errors.Count == 0;
        }

        public static string PrettyJson(string raw)
        {
            if (string.IsNullOrWhiteSpace(raw)) return "";
            var sb = new StringBuilder();
            bool inStr = false, esc = false;
            int indent = 0;
            for (int i = 0; i < raw.Length; i++)
            {
                char c = raw[i];
                if (esc) { sb.Append(c); esc = false; continue; }
                if (c == '\\' && inStr) { sb.Append(c); esc = true; continue; }
                if (c == '"') { inStr = !inStr; sb.Append(c); continue; }
                if (inStr) { sb.Append(c); continue; }
                if (c == '{' || c == '[')
                {
                    sb.Append(c);
                    indent++;
                    sb.Append('\n');
                    sb.Append(' ', indent * 2);
                }
                else if (c == '}' || c == ']')
                {
                    indent = Math.Max(0, indent - 1);
                    sb.Append('\n');
                    sb.Append(' ', indent * 2);
                    sb.Append(c);
                }
                else if (c == ',')
                {
                    sb.Append(c);
                    sb.Append('\n');
                    sb.Append(' ', indent * 2);
                }
                else if (c == ':')
                {
                    sb.Append(": ");
                }
                else if (!char.IsWhiteSpace(c))
                {
                    sb.Append(c);
                }
            }
            return sb.ToString();
        }
    }

    public class ScienceStudioView : Grid
    {
        readonly AppState _app;
        int _tab;
        readonly Border _body = new Border();
        readonly Border _header = new Border();
        TextBox _fastaBox, _lookupQuery, _afJobName, _afSeq, _afLigand, _afJsonBox, _lookupOut;
        string _lookupProvider = "PubChem";
        UIElement _proteinResultsPanel;

        public ScienceStudioView() : this(AppState.Shared) { }
        public ScienceStudioView(AppState app)
        {
            _app = app;
            Background = Theme.Current.EditorBackground;
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            Children.Add(_header);
            Grid.SetRow(_body, 1);
            Children.Add(_body);
            BuildHeader();
            RenderTab();
        }

        void BuildHeader()
        {
            _header.Child = StudioUi.Header("atom", "Science Mode", "Bioinformatics, Chemistry, PubChem / PDB / UniProt & AlphaFold 3",
                StudioUi.TabBar(new[] { "Protein & FASTA", "PubChem / Bio DB", "AlphaFold 3" }, _tab, delegate(int idx)
                {
                    _tab = idx;
                    BuildHeader();
                    RenderTab();
                }));
        }

        void RenderTab()
        {
            if (_tab == 0) RenderProteinTab();
            else if (_tab == 1) RenderLookupTab();
            else RenderAlphaFoldTab();
        }

        void RenderProteinTab()
        {
            var t = Theme.Current;
            if (_fastaBox == null)
            {
                _fastaBox = StudioUi.MultiLineEditor(
                    ">sp|P01308|INS_HUMAN Insulin OS=Homo sapiens\nMALWMRLLPLLALLALWGPDPAAAFVNQHLCGSHLVEALYLVCGERGFFYTPKTRREAED\nLQVGQVELGGGPGAGSLQPLALEGSLQKRGIVEQCCTSICSLYQLENYCN",
                    false, true);
                _fastaBox.Height = 140;
            }
            var outHost = new Border();
            Action runAnalyze = delegate
            {
                var a = ScienceService.AnalyzeProtein(_fastaBox.Text);
                var cards = V.H(8,
                    StudioUi.MetricCard("Length", a.Length + " aa", t.Primary),
                    StudioUi.MetricCard("MW", string.Format(CultureInfo.InvariantCulture, "{0:0.0} Da ({1:0.00} kDa)", a.MolecularWeightDa, a.MolecularWeightKDa), t.SysCyan),
                    StudioUi.MetricCard("Theoretical pI", a.TheoreticalPI.ToString("0.00", CultureInfo.InvariantCulture), t.SysPurple),
                    StudioUi.MetricCard("Charge (pH 7.4)", a.NetChargeAtPh74.ToString("+0.00;-0.00;0.00", CultureInfo.InvariantCulture), a.NetChargeAtPh74 >= 0 ? t.SysGreen : t.SysOrange),
                    StudioUi.MetricCard("GRAVY", a.Gravy.ToString("0.000", CultureInfo.InvariantCulture), t.SysBlue));

                var compWrap = new WrapPanel();
                foreach (var kv in a.Composition.OrderByDescending(x => x.Value))
                {
                    double pct;
                    a.CompositionPct.TryGetValue(kv.Key, out pct);
                    var chip = V.Box(
                        V.H(5,
                            V.Mono(kv.Key.ToString(), 12, FontWeights.Bold, t.Accent),
                            V.T(kv.Value + " (" + pct.ToString("0.0", CultureInfo.InvariantCulture) + "%)", 11, FontWeights.Normal, t.Secondary)),
                        V.P(8, 4), t.ElevatedBackground, 5, t.Separator, 1);
                    chip.Margin = new Thickness(0, 0, 6, 6);
                    compWrap.Children.Add(chip);
                }

                var panel = V.VLead(10,
                    V.T("Entry: " + a.Id, 12, FontWeights.SemiBold, t.Primary),
                    cards,
                    V.T("Amino Acid Composition", 11.5, FontWeights.SemiBold, t.Secondary),
                    compWrap);
                if (a.InvalidCharacters.Count > 0)
                    panel.Children.Add(V.T("Non-standard residues: " + string.Join(", ", a.InvalidCharacters), 11, FontWeights.Normal, t.SysYellow));
                _proteinResultsPanel = panel;
                outHost.Child = panel;
            };
            if (_proteinResultsPanel != null) outHost.Child = _proteinResultsPanel;
            else runAnalyze();

            var body = V.VLead(10,
                V.H(8,
                    V.T("FASTA or Protein Sequence", 12, FontWeights.SemiBold, t.Primary),
                    V.Sp(),
                    StudioUi.PillButton("Analyze Sequence", "play.fill", true, runAnalyze)),
                _fastaBox,
                outHost);
            body.Margin = V.P(14);
            _body.Child = StudioUi.Scroller(body);
        }

        void RenderLookupTab()
        {
            var t = Theme.Current;
            if (_lookupOut == null) { _lookupOut = StudioUi.MultiLineEditor("", true, true); _lookupOut.MinHeight = 280; }
            var providers = new[] { "PubChem", "UniProt", "RCSB PDB", "AlphaFold DB" };
            var provRow = V.H(4);
            for (int i = 0; i < providers.Length; i++)
            {
                string p = providers[i];
                bool act = p == _lookupProvider;
                var b = V.Button(V.Box(V.T(p, 11.5, act ? FontWeights.SemiBold : FontWeights.Normal, act ? Brushes.White : t.Secondary), V.P(9, 4), act ? t.Accent : t.P(0.08), 5),
                    delegate { _lookupProvider = p; RenderLookupTab(); });
                b.Cursor = Cursors.Hand;
                provRow.Children.Add(b);
            }
            string prevQ = _lookupQuery != null ? _lookupQuery.Text : "aspirin";
            var qBorder = StudioUi.InputBox("Name / SMILES / CID / UniProt ID / PDB ID...", prevQ, 280, out _lookupQuery);

            Action runLookup = async delegate
            {
                string q = _lookupQuery.Text.Trim();
                _lookupOut.Text = "Querying " + _lookupProvider + " for \"" + q + "\"...";
                if (_lookupProvider == "PubChem")
                {
                    var r = await ScienceService.LookupPubChemAsync(q);
                    if (!r.Ok) { _lookupOut.Text = "Error: " + r.Error; return; }
                    _lookupOut.Text = "CID: " + r.Cid + "\nFormula: " + r.Formula + "\nMolecular Weight: " + r.MolecularWeight +
                        "\nCanonical SMILES: " + r.CanonicalSmiles + "\nIUPAC: " + r.IupacName + "\nXLogP: " + r.XLogP + " | TPSA: " + r.Tpsa;
                }
                else
                {
                    BioEntryResult r;
                    if (_lookupProvider == "UniProt") r = await ScienceService.LookupUniProtAsync(q);
                    else if (_lookupProvider == "RCSB PDB") r = await ScienceService.LookupPdbAsync(q);
                    else r = await ScienceService.LookupAlphaFoldAsync(q);
                    if (!r.Ok) { _lookupOut.Text = "Error: " + r.Error; return; }
                    _lookupOut.Text = r.Source + " [" + r.Id + "]\nTitle: " + r.Title +
                        (string.IsNullOrEmpty(r.Organism) ? "" : "\nOrganism: " + r.Organism) +
                        (string.IsNullOrEmpty(r.Details) ? "" : "\nDetails: " + r.Details) +
                        (string.IsNullOrEmpty(r.ModelUrl) ? "" : "\nModel URL: " + r.ModelUrl) +
                        (string.IsNullOrEmpty(r.Sequence) ? "" : "\nSequence (" + r.Sequence.Length + " aa):\n" + r.Sequence);
                }
            };

            var col = V.VLead(10,
                provRow,
                V.H(8, V.Flex(qBorder), StudioUi.PillButton("Lookup", "magnifyingglass", true, runLookup)),
                _lookupOut);
            col.Margin = V.P(14);
            _body.Child = StudioUi.Scroller(col);
        }

        void RenderAlphaFoldTab()
        {
            var t = Theme.Current;
            var jBorder = StudioUi.InputBox("Job Name", _afJobName != null ? _afJobName.Text : "insulin_ligand_complex", 180, out _afJobName);
            var lBorder = StudioUi.InputBox("Optional Ligand SMILES (e.g. CC(=O)OC1=CC=CC=C1C(=O)O)", _afLigand != null ? _afLigand.Text : "", 260, out _afLigand);
            if (_afSeq == null) { _afSeq = StudioUi.MultiLineEditor("GIVEQCCTSICSLYQLENYCN", false, true); _afSeq.Height = 90; }
            if (_afJsonBox == null) { _afJsonBox = StudioUi.MultiLineEditor("", false, true); _afJsonBox.Height = 220; }
            var statusLbl = V.T("Ready", 11.5, FontWeights.Medium, t.Secondary);

            Action gen = delegate
            {
                _afJsonBox.Text = ScienceService.GenerateAlphaFold3Json(_afJobName.Text, _afSeq.Text, _afLigand.Text, 1);
                statusLbl.Text = "Generated AlphaFold 3 JSON input.";
                statusLbl.Foreground = t.SysCyan;
            };
            Action val = delegate
            {
                List<string> errs;
                bool ok = ScienceService.ValidateAlphaFold3Json(_afJsonBox.Text, out errs);
                statusLbl.Text = ok ? "Valid AlphaFold 3 JSON." : ("Invalid: " + string.Join("; ", errs));
                statusLbl.Foreground = ok ? t.SysGreen : t.SysRed;
            };

            Action openAf3 = delegate
            {
                if (string.IsNullOrWhiteSpace(_afJsonBox.Text)) gen();
                string dir = !string.IsNullOrEmpty(_app.WorkspaceFolder) ? _app.WorkspaceFolder : Path.GetTempPath();
                string fname = (string.IsNullOrWhiteSpace(_afJobName.Text) ? "af3_job" : _afJobName.Text.Trim()) + ".json";
                string p = Path.Combine(dir, fname);
                File.WriteAllText(p, _afJsonBox.Text, Encoding.UTF8);
                _app.OpenFile(p);
            };

            var col = V.VLead(10,
                V.H(8, V.Flex(jBorder), V.Flex(lBorder)),
                V.T("Protein Sequence / FASTA", 11.5, FontWeights.SemiBold, t.Secondary),
                _afSeq,
                V.H(8, StudioUi.PillButton("Generate AF3 JSON", "sparkles", true, gen),
                    StudioUi.PillButton("Validate JSON", "checkmark.circle", false, val),
                    StudioUi.PillButton("Open in Editor", "doc.text", false, openAf3),
                    statusLbl),
                _afJsonBox);
            col.Margin = V.P(14);
            _body.Child = StudioUi.Scroller(col);
        }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 2. REMOTEX STUDIO (SSH Config Parser + OpenSSH / SCP Remote Explorer)
    // ═════════════════════════════════════════════════════════════════════════════

    public class SSHConfigProfile
    {
        public string Id = Guid.NewGuid().ToString("N").Substring(0, 8);
        public string Name = "";
        public string HostName = "";
        public string User = "";
        public int Port = 22;
        public string IdentityFile = "";
        public string ProxyJump = "";
        public string Protocol = "ssh";
        public string RemotePath = ".";
        public bool IsCustom;
    }

    public class RemoteEntry
    {
        public string Name = "";
        public string FullPath = "";
        public bool IsDirectory;
        public long SizeBytes;
        public string Permissions = "";
        public string Modified = "";
    }

    public static class SSHConfigParser
    {
        public static List<SSHConfigProfile> ParseDefaultConfig()
        {
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string cfg = Path.Combine(Path.Combine(home, ".ssh"), "config");
            if (!File.Exists(cfg)) return new List<SSHConfigProfile>();
            try { return ParseText(File.ReadAllText(cfg)); }
            catch { return new List<SSHConfigProfile>(); }
        }

        public static List<SSHConfigProfile> ParseText(string configText)
        {
            var result = new List<SSHConfigProfile>();
            if (string.IsNullOrWhiteSpace(configText)) return result;
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            List<SSHConfigProfile> current = null;
            string[] lines = configText.Replace("\r\n", "\n").Split('\n');

            for (int i = 0; i < lines.Length; i++)
            {
                string raw = lines[i].Trim();
                if (raw.Length == 0 || raw.StartsWith("#")) continue;
                int hash = raw.IndexOf('#');
                if (hash > 0) raw = raw.Substring(0, hash).Trim();

                string key, val;
                SplitDirective(raw, out key, out val);
                if (string.IsNullOrEmpty(key)) continue;

                if (key.Equals("Host", StringComparison.OrdinalIgnoreCase))
                {
                    current = new List<SSHConfigProfile>();
                    string[] patterns = val.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                    for (int p = 0; p < patterns.Length; p++)
                    {
                        string pat = patterns[p].Trim();
                        if (pat == "*" || pat.Contains("*") || pat.Contains("?")) continue;
                        var prof = new SSHConfigProfile { Name = pat, HostName = pat, Port = 22 };
                        current.Add(prof);
                        result.Add(prof);
                    }
                    continue;
                }
                if (current == null || current.Count == 0) continue;

                for (int c = 0; c < current.Count; c++)
                {
                    var pr = current[c];
                    if (key.Equals("HostName", StringComparison.OrdinalIgnoreCase)) pr.HostName = val;
                    else if (key.Equals("User", StringComparison.OrdinalIgnoreCase)) pr.User = val;
                    else if (key.Equals("Port", StringComparison.OrdinalIgnoreCase))
                    {
                        int pt;
                        if (int.TryParse(val, out pt) && pt > 0) pr.Port = pt;
                    }
                    else if (key.Equals("IdentityFile", StringComparison.OrdinalIgnoreCase))
                    {
                        if (val.StartsWith("~/") || val.StartsWith("~\\"))
                            val = Path.Combine(home, val.Substring(2));
                        pr.IdentityFile = val;
                    }
                    else if (key.Equals("ProxyJump", StringComparison.OrdinalIgnoreCase)) pr.ProxyJump = val;
                }
            }
            return result;
        }

        static void SplitDirective(string line, out string key, out string val)
        {
            key = ""; val = "";
            int eq = line.IndexOf('=');
            int sp = line.IndexOfAny(new[] { ' ', '\t' });
            int idx = (eq > 0 && (sp < 0 || eq < sp)) ? eq : sp;
            if (idx <= 0) return;
            key = line.Substring(0, idx).Trim();
            val = line.Substring(idx + 1).Trim().Trim('"');
        }
    }

    public static class RemoteProfileStore
    {
        const string Key = "remotex_custom_profiles_v1";

        public static List<SSHConfigProfile> LoadCustomProfiles()
        {
            var list = new List<SSHConfigProfile>();
            string raw = Defaults.Str(Key, "[]");
            var arr = DJ.S.DeserializeObject(raw) as object[];
            if (arr == null) return list;
            for (int i = 0; i < arr.Length; i++)
            {
                var d = arr[i] as Dictionary<string, object>;
                if (d == null) continue;
                int pt = 22;
                double? pNum = DJ.Num(d, "port");
                if (pNum.HasValue && pNum.Value > 0) pt = (int)pNum.Value;
                list.Add(new SSHConfigProfile
                {
                    Id = DJ.Str(d, "id") ?? Guid.NewGuid().ToString("N").Substring(0, 8),
                    Name = DJ.Str(d, "name") ?? "",
                    HostName = DJ.Str(d, "hostName") ?? "",
                    User = DJ.Str(d, "user") ?? "",
                    Port = pt,
                    IdentityFile = DJ.Str(d, "identityFile") ?? "",
                    ProxyJump = DJ.Str(d, "proxyJump") ?? "",
                    Protocol = DJ.Str(d, "protocol") ?? "ssh",
                    RemotePath = DJ.Str(d, "remotePath") ?? ".",
                    IsCustom = true
                });
            }
            return list;
        }

        public static void SaveCustomProfiles(List<SSHConfigProfile> profiles)
        {
            var outList = new List<Dictionary<string, object>>();
            if (profiles != null)
            {
                for (int i = 0; i < profiles.Count; i++)
                {
                    var p = profiles[i];
                    outList.Add(new Dictionary<string, object>
                    {
                        { "id", p.Id }, { "name", p.Name }, { "hostName", p.HostName },
                        { "user", p.User }, { "port", p.Port }, { "identityFile", p.IdentityFile },
                        { "proxyJump", p.ProxyJump }, { "protocol", p.Protocol }, { "remotePath", p.RemotePath }
                    });
                }
            }
            Defaults.Set(Key, DJ.Ser(outList));
            Defaults.Flush();
        }
    }

    public static class RemoteWorkspaceManager
    {
        public static string FindSshExe()
        {
            string sys = @"C:\Windows\System32\OpenSSH\ssh.exe";
            return StudioProcess.FindExecutable(sys, "ssh.exe", "ssh");
        }

        public static string FindScpExe()
        {
            string sys = @"C:\Windows\System32\OpenSSH\scp.exe";
            return StudioProcess.FindExecutable(sys, "scp.exe", "scp");
        }

        public static string BuildSshTarget(SSHConfigProfile p)
        {
            string host = !string.IsNullOrWhiteSpace(p.HostName) ? p.HostName : p.Name;
            return string.IsNullOrWhiteSpace(p.User) ? host : (p.User + "@" + host);
        }

        public static string BuildSshArgs(SSHConfigProfile p, string remoteCommand)
        {
            var sb = new StringBuilder();
            sb.Append("-o BatchMode=yes -o ConnectTimeout=10 ");
            if (p.Port > 0 && p.Port != 22) sb.Append("-p ").Append(p.Port).Append(" ");
            if (!string.IsNullOrWhiteSpace(p.IdentityFile)) sb.Append("-i ").Append(StudioProcess.QuoteArg(p.IdentityFile)).Append(" ");
            if (!string.IsNullOrWhiteSpace(p.ProxyJump)) sb.Append("-J ").Append(StudioProcess.QuoteArg(p.ProxyJump)).Append(" ");
            sb.Append(BuildSshTarget(p));
            if (!string.IsNullOrWhiteSpace(remoteCommand)) sb.Append(" ").Append(StudioProcess.QuoteArg(remoteCommand));
            return sb.ToString();
        }

        public static StudioExecResult RunCommand(SSHConfigProfile p, string command, int timeoutMs)
        {
            string ssh = FindSshExe();
            if (ssh == null) return new StudioExecResult { ExitCode = -1, StdErr = "OpenSSH ssh.exe not found on PATH." };
            return StudioProcess.Run(ssh, BuildSshArgs(p, command), null, timeoutMs, null);
        }

        public static List<RemoteEntry> ParseLsOutput(string output, string baseDir)
        {
            var entries = new List<RemoteEntry>();
            if (string.IsNullOrWhiteSpace(output)) return entries;
            string dir = string.IsNullOrWhiteSpace(baseDir) ? "." : baseDir.TrimEnd('/');
            string[] lines = output.Replace("\r\n", "\n").Split('\n');
            for (int i = 0; i < lines.Length; i++)
            {
                string line = lines[i].Trim();
                if (line.Length == 0 || line.StartsWith("total ")) continue;
                var m = Regex.Match(line, @"^([d\-lcbps][rwxstST\-]{9}[@+\.]?)\s+\d+\s+\S+\s+\S+\s+(\d+)\s+((?:[A-Za-z]{3}\s+\d+\s+[\d:]+|\d{4}-\d{2}-\d{2}\s+[\d:]+))\s+(.+)$");
                if (!m.Success) continue;
                string perm = m.Groups[1].Value;
                long size = 0;
                long.TryParse(m.Groups[2].Value, out size);
                string mod = m.Groups[3].Value.Trim();
                string name = m.Groups[4].Value.Trim();
                int arrow = name.IndexOf(" -> ");
                if (arrow > 0 && perm.StartsWith("l")) name = name.Substring(0, arrow);
                if (name == "." || name == "..") continue;
                entries.Add(new RemoteEntry
                {
                    Permissions = perm,
                    SizeBytes = size,
                    Modified = mod,
                    Name = name,
                    IsDirectory = perm.StartsWith("d"),
                    FullPath = dir == "." ? name : (dir + "/" + name)
                });
            }
            return entries.OrderByDescending(e => e.IsDirectory).ThenBy(e => e.Name).ToList();
        }

        public static List<RemoteEntry> ListDirectory(SSHConfigProfile p, string remoteDir, out string error)
        {
            error = "";
            string dir = string.IsNullOrWhiteSpace(remoteDir) ? "." : remoteDir;
            var res = RunCommand(p, "ls -la " + StudioProcess.QuoteArg(dir), 15000);
            if (!res.Ok) { error = res.Combined; return new List<RemoteEntry>(); }
            return ParseLsOutput(res.StdOut, dir);
        }

        public static string FetchFile(SSHConfigProfile p, string remotePath, string localDir, out string error)
        {
            error = "";
            string scp = FindScpExe();
            if (scp == null) { error = "OpenSSH scp.exe not found."; return null; }
            Directory.CreateDirectory(localDir);
            string localPath = Path.Combine(localDir, Path.GetFileName(remotePath.Replace('\\', '/')));
            var sb = new StringBuilder();
            sb.Append("-o BatchMode=yes -o ConnectTimeout=10 ");
            if (p.Port > 0 && p.Port != 22) sb.Append("-P ").Append(p.Port).Append(" ");
            if (!string.IsNullOrWhiteSpace(p.IdentityFile)) sb.Append("-i ").Append(StudioProcess.QuoteArg(p.IdentityFile)).Append(" ");
            sb.Append(StudioProcess.QuoteArg(BuildSshTarget(p) + ":" + remotePath)).Append(" ").Append(StudioProcess.QuoteArg(localPath));
            var res = StudioProcess.Run(scp, sb.ToString(), null, 30000, null);
            if (!res.Ok) { error = res.Combined; return null; }
            return localPath;
        }

        public static bool SaveFile(SSHConfigProfile p, string localPath, string remotePath, out string error)
        {
            error = "";
            string scp = FindScpExe();
            if (scp == null) { error = "OpenSSH scp.exe not found."; return false; }
            var sb = new StringBuilder();
            sb.Append("-o BatchMode=yes -o ConnectTimeout=10 ");
            if (p.Port > 0 && p.Port != 22) sb.Append("-P ").Append(p.Port).Append(" ");
            if (!string.IsNullOrWhiteSpace(p.IdentityFile)) sb.Append("-i ").Append(StudioProcess.QuoteArg(p.IdentityFile)).Append(" ");
            sb.Append(StudioProcess.QuoteArg(localPath)).Append(" ").Append(StudioProcess.QuoteArg(BuildSshTarget(p) + ":" + remotePath));
            var res = StudioProcess.Run(scp, sb.ToString(), null, 30000, null);
            if (!res.Ok) { error = res.Combined; return false; }
            return true;
        }
    }

    public class RemoteXStudioView : Grid
    {
        readonly AppState _app;
        List<SSHConfigProfile> _profiles = new List<SSHConfigProfile>();
        SSHConfigProfile _selected;
        string _remoteDir = ".";
        List<RemoteEntry> _entries = new List<RemoteEntry>();
        string _status = "Select a host from ~/.ssh/config or add a custom profile.";
        readonly StackPanel _profileList = new StackPanel();
        readonly StackPanel _fileList = new StackPanel();
        TextBox _pathBox, _cmdBox, _cmdOut, _newName, _newHost, _newUser, _newPort;
        string _newProto = "ssh";
        readonly TextBlock _statusText;

        public RemoteXStudioView() : this(AppState.Shared) { }
        public RemoteXStudioView(AppState app)
        {
            _app = app ?? AppState.Shared;
            var t = Theme.Current;
            Background = t.EditorBackground;
            _statusText = V.T(_status, 11, FontWeights.Normal, t.Secondary);

            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            Children.Add(StudioUi.Header("server.rack", "Remote Explorer", "OpenSSH / SFTP / FTP Workspace Browser",
                StudioUi.PillButton("Reload ~/.ssh/config", "arrow.clockwise", false, ReloadProfiles)));

            var split = new Grid();
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(280) });
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Grid.SetRow(split, 1);
            Children.Add(split);

            var left = BuildLeftPane();
            split.Children.Add(left);
            var sep = V.Line(t.Separator, false);
            Grid.SetColumn(sep, 1);
            split.Children.Add(sep);
            var right = BuildRightPane();
            Grid.SetColumn(right, 2);
            split.Children.Add(right);

            ReloadProfiles();
        }

        UIElement BuildLeftPane()
        {
            var t = Theme.Current;
            var nb = StudioUi.InputBox("Profile Name", "", 0, out _newName);
            var hb = StudioUi.InputBox("Host / IP", "", 0, out _newHost);
            var ub = StudioUi.InputBox("User", "root", 0, out _newUser);
            var pb = StudioUi.InputBox("Port", "22", 0, out _newPort);

            var protoRow = V.H(4);
            var protos = new[] { "ssh", "sftp", "ftp" };
            for (int i = 0; i < protos.Length; i++)
            {
                string pr = protos[i];
                var btn = StudioUi.PillButton(pr.ToUpperInvariant(), null, pr == _newProto, delegate { _newProto = pr; });
                protoRow.Children.Add(btn);
            }

            var addForm = V.VLead(6,
                V.T("Add Custom Profile", 11.5, FontWeights.SemiBold, t.Secondary),
                nb, hb, V.H(6, V.Flex(ub), V.Size(pb, 64, double.NaN)),
                protoRow,
                StudioUi.PillButton("Save Profile", "plus", true, delegate
                {
                    if (string.IsNullOrWhiteSpace(_newHost.Text)) return;
                    int pt = 22;
                    int.TryParse(_newPort.Text, out pt);
                    var custom = RemoteProfileStore.LoadCustomProfiles();
                    custom.Add(new SSHConfigProfile
                    {
                        Name = string.IsNullOrWhiteSpace(_newName.Text) ? _newHost.Text.Trim() : _newName.Text.Trim(),
                        HostName = _newHost.Text.Trim(),
                        User = _newUser.Text.Trim(),
                        Port = pt > 0 ? pt : 22,
                        Protocol = _newProto,
                        IsCustom = true
                    });
                    RemoteProfileStore.SaveCustomProfiles(custom);
                    _newName.Text = ""; _newHost.Text = "";
                    ReloadProfiles();
                }));

            var leftGrid = new Grid { Background = t.PanelBackground };
            leftGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            leftGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            leftGrid.Children.Add(StudioUi.Scroller(V.Box(_profileList, V.P(10), Brushes.Transparent, 0)));
            var formBox = V.Box(addForm, V.P(10), t.ElevatedBackground, 0, t.Separator, 1);
            Grid.SetRow(formBox, 1);
            leftGrid.Children.Add(formBox);
            return leftGrid;
        }

        UIElement BuildRightPane()
        {
            var t = Theme.Current;
            var pathInput = StudioUi.InputBox("Remote directory (e.g. /home/user)", ".", 220, out _pathBox);
            var cmdInput = StudioUi.InputBox("Remote command (e.g. uname -a && nvidia-smi)", "pwd && ls -1", 220, out _cmdBox);
            _cmdOut = StudioUi.MultiLineEditor("", true, true);
            _cmdOut.Height = 140;

            var right = new Grid();
            right.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            right.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            right.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var topBar = V.VLead(6,
                V.H(6,
                    StudioUi.PillButton("Up", "arrow.up", false, delegate
                    {
                        int slash = _remoteDir.TrimEnd('/').LastIndexOf('/');
                        _remoteDir = slash > 0 ? _remoteDir.Substring(0, slash) : ".";
                        _pathBox.Text = _remoteDir;
                        BrowseRemote();
                    }),
                    V.Flex(pathInput),
                    StudioUi.PillButton("List Dir", "folder", true, delegate
                    {
                        _remoteDir = string.IsNullOrWhiteSpace(_pathBox.Text) ? "." : _pathBox.Text.Trim();
                        BrowseRemote();
                    })),
                _statusText);
            right.Children.Add(V.Box(topBar, V.P(12, 8), t.PanelBackground, 0));

            var filesScroll = StudioUi.Scroller(V.Box(_fileList, V.P(12), Brushes.Transparent, 0));
            Grid.SetRow(filesScroll, 1);
            right.Children.Add(filesScroll);

            var cmdPanel = V.VLead(6,
                V.H(6, V.Flex(cmdInput), StudioUi.PillButton("Run SSH Cmd", "terminal", true, RunRemoteCmd)),
                _cmdOut);
            var cmdWrap = V.Box(cmdPanel, V.P(12, 8), t.PanelBackground, 0, t.Separator, 1);
            Grid.SetRow(cmdWrap, 2);
            right.Children.Add(cmdWrap);
            return right;
        }

        void ReloadProfiles()
        {
            _profiles = new List<SSHConfigProfile>();
            _profiles.AddRange(SSHConfigParser.ParseDefaultConfig());
            _profiles.AddRange(RemoteProfileStore.LoadCustomProfiles());
            RenderProfiles();
        }

        void RenderProfiles()
        {
            var t = Theme.Current;
            _profileList.Children.Clear();
            if (_profiles.Count == 0)
            {
                _profileList.Children.Add(V.T("No SSH hosts found in ~/.ssh/config.", 11.5, FontWeights.Normal, t.Secondary));
                return;
            }
            for (int i = 0; i < _profiles.Count; i++)
            {
                var p = _profiles[i];
                bool sel = _selected != null && _selected.Id == p.Id;
                var row = V.H(6,
                    Sym.Icon(p.IsCustom ? "link" : "server.rack", 12, sel ? Brushes.White : t.Accent),
                    V.Flex(V.VLead(1,
                        V.T(p.Name, 12, FontWeights.SemiBold, sel ? Brushes.White : t.Primary),
                        V.T(p.Protocol.ToUpperInvariant() + " · " + RemoteWorkspaceManager.BuildSshTarget(p) + ":" + p.Port, 10, FontWeights.Normal, sel ? Brushes.White : t.Secondary))));
                if (p.IsCustom)
                {
                    var del = V.Button(Sym.Icon("trash", 11, t.SysRed), delegate
                    {
                        var custom = RemoteProfileStore.LoadCustomProfiles().Where(x => x.Id != p.Id).ToList();
                        RemoteProfileStore.SaveCustomProfiles(custom);
                        if (_selected == p) _selected = null;
                        ReloadProfiles();
                    });
                    row.Children.Add(del);
                }
                var card = V.Button(V.Box(row, V.P(8, 6), sel ? t.Accent : t.ElevatedBackground, 6), delegate
                {
                    _selected = p;
                    _remoteDir = string.IsNullOrEmpty(p.RemotePath) ? "." : p.RemotePath;
                    _pathBox.Text = _remoteDir;
                    RenderProfiles();
                    BrowseRemote();
                });
                card.Margin = new Thickness(0, 0, 0, 6);
                _profileList.Children.Add(card);
            }
        }

        void BrowseRemote()
        {
            if (_selected == null) { _statusText.Text = "Select a profile first."; return; }
            _statusText.Text = "Listing " + _remoteDir + " on " + _selected.Name + "...";
            var prof = _selected;
            string dir = _remoteDir;
            Task.Run(delegate
            {
                string err;
                var entries = RemoteWorkspaceManager.ListDirectory(prof, dir, out err);
                Dispatcher.BeginInvoke(new Action(delegate
                {
                    _entries = entries;
                    _statusText.Text = string.IsNullOrEmpty(err) ? ("Listed " + entries.Count + " items in " + dir) : ("SSH error: " + err);
                    RenderEntries();
                }));
            });
        }

        void RenderEntries()
        {
            var t = Theme.Current;
            _fileList.Children.Clear();
            for (int i = 0; i < _entries.Count; i++)
            {
                var e = _entries[i];
                var row = V.H(8,
                    Sym.Icon(e.IsDirectory ? "folder.fill" : "doc.text", 13, e.IsDirectory ? t.SysBlue : t.Secondary),
                    V.Flex(V.T(e.Name, 12, FontWeights.Medium, t.Primary)),
                    V.Mono(e.IsDirectory ? "<DIR>" : (e.SizeBytes + " B"), 10.5, FontWeights.Normal, t.Secondary),
                    V.Mono(e.Permissions, 10.5, FontWeights.Normal, t.Tertiary));
                var btn = V.Button(V.Box(row, V.P(8, 5), t.ElevatedBackground, 5), delegate
                {
                    if (e.IsDirectory)
                    {
                        _remoteDir = e.FullPath;
                        _pathBox.Text = _remoteDir;
                        BrowseRemote();
                    }
                    else
                    {
                        PullAndOpen(e);
                    }
                });
                btn.Margin = new Thickness(0, 0, 0, 4);
                _fileList.Children.Add(btn);
            }
        }

        void PullAndOpen(RemoteEntry entry)
        {
            if (_selected == null) return;
            var prof = _selected;
            string cacheDir = Path.Combine(Path.Combine(Defaults.Dir, "RemoteCache"), prof.Name);
            _statusText.Text = "Pulling " + entry.FullPath + "...";
            Task.Run(delegate
            {
                string err;
                string local = RemoteWorkspaceManager.FetchFile(prof, entry.FullPath, cacheDir, out err);
                Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (local != null)
                    {
                        _statusText.Text = "Opened " + local;
                        (_app ?? AppState.Shared).OpenFile(local);
                    }
                    else
                    {
                        _statusText.Text = "Fetch failed: " + err;
                    }
                }));
            });
        }

        void RunRemoteCmd()
        {
            if (_selected == null) { _cmdOut.Text = "Select a host first."; return; }
            var prof = _selected;
            string cmd = _cmdBox.Text;
            _cmdOut.Text = "Running on " + prof.Name + "...";
            Task.Run(delegate
            {
                var r = RemoteWorkspaceManager.RunCommand(prof, cmd, 20000);
                Dispatcher.BeginInvoke(new Action(delegate
                {
                    _cmdOut.Text = "Exit " + r.ExitCode + " (" + r.ElapsedMs + " ms)\n" + r.Combined;
                }));
            });
        }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 3. SCENARIO STUDIO (Persistent Test/Workflow Scenarios + JSON Report)
    // ═════════════════════════════════════════════════════════════════════════════

    public class ScenarioStep
    {
        public string Id = Guid.NewGuid().ToString("N").Substring(0, 8);
        public string Name = "Step";
        public string Kind = "shell"; // http | shell | file_exists | file_contains
        public string Target = "";
        public string Method = "GET";
        public string Body = "";
        public int ExpectedStatus = 200;
        public string ExpectedText = "";
        public int TimeoutMs = 15000;
    }

    public class ScenarioSuite
    {
        public string Id = Guid.NewGuid().ToString("N").Substring(0, 8);
        public string Name = "Default Suite";
        public List<ScenarioStep> Steps = new List<ScenarioStep>();
    }

    public class ScenarioStepResult
    {
        public string StepId = "";
        public string StepName = "";
        public string Kind = "";
        public bool Passed;
        public long ElapsedMs;
        public string Details = "";
        public string OutputPreview = "";
    }

    public class ScenarioRunReport
    {
        public string SuiteName = "";
        public string TimestampUtc = "";
        public int TotalSteps;
        public int PassedSteps;
        public int FailedSteps;
        public long TotalElapsedMs;
        public List<ScenarioStepResult> Results = new List<ScenarioStepResult>();
    }

    public static class ScenarioService
    {
        public static string DefaultSuitePath(string workspaceDir)
        {
            string root = !string.IsNullOrEmpty(workspaceDir) ? workspaceDir : Defaults.Dir;
            return Path.Combine(Path.Combine(root, ".microcode"), "scenarios.json");
        }

        public static ScenarioSuite LoadSuite(string path)
        {
            if (string.IsNullOrEmpty(path) || !File.Exists(path))
                return new ScenarioSuite { Name = "Workspace Scenarios" };
            try
            {
                var o = DJ.Obj(File.ReadAllText(path, Encoding.UTF8));
                if (o == null) return new ScenarioSuite();
                var suite = new ScenarioSuite
                {
                    Id = DJ.Str(o, "id") ?? Guid.NewGuid().ToString("N").Substring(0, 8),
                    Name = DJ.Str(o, "name") ?? "Workspace Scenarios"
                };
                var arr = DJ.Arr(o, "steps");
                if (arr != null)
                {
                    for (int i = 0; i < arr.Count; i++)
                    {
                        var s = arr[i] as Dictionary<string, object>;
                        if (s == null) continue;
                        double? expSt = DJ.Num(s, "expectedStatus");
                        double? tmo = DJ.Num(s, "timeoutMs");
                        suite.Steps.Add(new ScenarioStep
                        {
                            Id = DJ.Str(s, "id") ?? Guid.NewGuid().ToString("N").Substring(0, 8),
                            Name = DJ.Str(s, "name") ?? ("Step " + (i + 1)),
                            Kind = DJ.Str(s, "kind") ?? "shell",
                            Target = DJ.Str(s, "target") ?? "",
                            Method = DJ.Str(s, "method") ?? "GET",
                            Body = DJ.Str(s, "body") ?? "",
                            ExpectedStatus = expSt.HasValue ? (int)expSt.Value : 200,
                            ExpectedText = DJ.Str(s, "expectedText") ?? "",
                            TimeoutMs = tmo.HasValue && tmo.Value > 0 ? (int)tmo.Value : 15000
                        });
                    }
                }
                return suite;
            }
            catch
            {
                return new ScenarioSuite();
            }
        }

        public static void SaveSuite(string path, ScenarioSuite suite)
        {
            if (string.IsNullOrEmpty(path) || suite == null) return;
            var steps = new List<Dictionary<string, object>>();
            for (int i = 0; i < suite.Steps.Count; i++)
            {
                var st = suite.Steps[i];
                steps.Add(new Dictionary<string, object>
                {
                    { "id", st.Id }, { "name", st.Name }, { "kind", st.Kind }, { "target", st.Target },
                    { "method", st.Method }, { "body", st.Body }, { "expectedStatus", st.ExpectedStatus },
                    { "expectedText", st.ExpectedText }, { "timeoutMs", st.TimeoutMs }
                });
            }
            var payload = new Dictionary<string, object>
            {
                { "id", suite.Id },
                { "name", suite.Name },
                { "steps", steps.ToArray() }
            };
            Defaults.WriteAtomic(path, ScienceService.PrettyJson(DJ.Ser(payload)));
        }

        public static ScenarioStepResult RunStep(ScenarioStep step, string workingDir)
        {
            var res = new ScenarioStepResult
            {
                StepId = step.Id,
                StepName = step.Name,
                Kind = step.Kind
            };
            var sw = Stopwatch.StartNew();
            try
            {
                if (step.Kind == "http")
                {
                    var req = new HttpRequestMessage(new HttpMethod(string.IsNullOrEmpty(step.Method) ? "GET" : step.Method.ToUpperInvariant()), step.Target);
                    if (!string.IsNullOrEmpty(step.Body) && req.Method != HttpMethod.Get && req.Method != HttpMethod.Head)
                        req.Content = new StringContent(step.Body, Encoding.UTF8, "application/json");
                    var resp = DotminiNet.Http.SendAsync(req).Result;
                    int code = (int)resp.StatusCode;
                    string body = resp.Content.ReadAsStringAsync().Result ?? "";
                    res.OutputPreview = body.Length > 800 ? body.Substring(0, 800) + "..." : body;
                    bool statusOk = step.ExpectedStatus <= 0 ? (code >= 200 && code < 300) : (code == step.ExpectedStatus);
                    bool textOk = string.IsNullOrEmpty(step.ExpectedText) || body.Contains(step.ExpectedText);
                    res.Passed = statusOk && textOk;
                    res.Details = "HTTP " + code + (textOk ? "" : (" (missing \"" + step.ExpectedText + "\")"));
                }
                else if (step.Kind == "file_exists" || step.Kind == "file_contains")
                {
                    string p = Path.IsPathRooted(step.Target) ? step.Target : Path.Combine(workingDir ?? Environment.CurrentDirectory, step.Target ?? "");
                    bool exists = File.Exists(p) || Directory.Exists(p);
                    if (!exists)
                    {
                        res.Passed = false;
                        res.Details = "Missing path: " + p;
                    }
                    else if (step.Kind == "file_exists")
                    {
                        res.Passed = true;
                        res.Details = "Found: " + p;
                    }
                    else
                    {
                        string content = File.ReadAllText(p, Encoding.UTF8);
                        res.OutputPreview = content.Length > 800 ? content.Substring(0, 800) + "..." : content;
                        bool has = string.IsNullOrEmpty(step.ExpectedText) || content.Contains(step.ExpectedText);
                        res.Passed = has;
                        res.Details = has ? "Matched expected text." : ("Missing text: " + step.ExpectedText);
                    }
                }
                else
                {
                    var exec = StudioProcess.RunShell(step.Target, workingDir, step.TimeoutMs, null);
                    string combined = exec.Combined;
                    res.OutputPreview = combined.Length > 800 ? combined.Substring(0, 800) + "..." : combined;
                    bool textOk = string.IsNullOrEmpty(step.ExpectedText) || combined.Contains(step.ExpectedText);
                    res.Passed = exec.Ok && textOk;
                    res.Details = "Exit " + exec.ExitCode + (textOk ? "" : (" (missing \"" + step.ExpectedText + "\")"));
                }
            }
            catch (Exception ex)
            {
                res.Passed = false;
                res.Details = ex.Message;
            }
            sw.Stop();
            res.ElapsedMs = sw.ElapsedMilliseconds;
            return res;
        }

        public static ScenarioRunReport RunSuite(ScenarioSuite suite, string workingDir)
        {
            var report = new ScenarioRunReport
            {
                SuiteName = suite != null ? suite.Name : "",
                TimestampUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture)
            };
            if (suite == null) return report;
            var sw = Stopwatch.StartNew();
            for (int i = 0; i < suite.Steps.Count; i++)
            {
                var r = RunStep(suite.Steps[i], workingDir);
                report.Results.Add(r);
                report.TotalSteps++;
                if (r.Passed) report.PassedSteps++; else report.FailedSteps++;
            }
            sw.Stop();
            report.TotalElapsedMs = sw.ElapsedMilliseconds;
            return report;
        }

        public static string ExportReportJson(ScenarioRunReport report)
        {
            var items = new List<Dictionary<string, object>>();
            for (int i = 0; i < report.Results.Count; i++)
            {
                var r = report.Results[i];
                items.Add(new Dictionary<string, object>
                {
                    { "stepId", r.StepId }, { "stepName", r.StepName }, { "kind", r.Kind },
                    { "passed", r.Passed }, { "elapsedMs", r.ElapsedMs },
                    { "details", r.Details }, { "outputPreview", r.OutputPreview }
                });
            }
            var obj = new Dictionary<string, object>
            {
                { "suiteName", report.SuiteName },
                { "timestampUtc", report.TimestampUtc },
                { "totalSteps", report.TotalSteps },
                { "passedSteps", report.PassedSteps },
                { "failedSteps", report.FailedSteps },
                { "totalElapsedMs", report.TotalElapsedMs },
                { "results", items.ToArray() }
            };
            return ScienceService.PrettyJson(DJ.Ser(obj));
        }
    }

    public class ScenarioStudioView : Grid
    {
        readonly AppState _app;
        ScenarioSuite _suite;
        ScenarioRunReport _lastReport;
        readonly StackPanel _stepsPanel = new StackPanel();
        TextBox _stepName, _stepTarget, _stepExpect, _previewBox;
        string _newKind = "shell";
        readonly TextBlock _summaryLbl;

        public ScenarioStudioView() : this(AppState.Shared) { }
        public ScenarioStudioView(AppState app)
        {
            _app = app ?? AppState.Shared;
            var t = Theme.Current;
            Background = t.EditorBackground;
            _suite = ScenarioService.LoadSuite(SuitePath);
            _summaryLbl = V.T("Loaded " + _suite.Steps.Count + " steps", 11.5, FontWeights.Medium, t.Secondary);

            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            Children.Add(StudioUi.Header("flowchart", "Scenario Studio", "Sequential HTTP, Shell & File Assertion Suites (.microcode/scenarios.json)",
                _summaryLbl,
                StudioUi.PillButton("Save", "square.and.arrow.down", false, delegate
                {
                    ScenarioService.SaveSuite(SuitePath, _suite);
                    _summaryLbl.Text = "Saved " + SuitePath;
                }),
                StudioUi.PillButton("Export Report", "doc.text", false, ExportReport),
                StudioUi.PillButton("Run Suite", "play.fill", true, RunAll)));

            var addBar = BuildAddBar();
            Grid.SetRow(addBar, 1);
            Children.Add(addBar);

            var split = new Grid();
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0.55, GridUnitType.Star) });
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0.45, GridUnitType.Star) });
            Grid.SetRow(split, 2);
            Children.Add(split);

            split.Children.Add(StudioUi.Scroller(V.Box(_stepsPanel, V.P(12), Brushes.Transparent, 0)));
            var sep = V.Line(t.Separator, false);
            Grid.SetColumn(sep, 1);
            split.Children.Add(sep);
            _previewBox = StudioUi.MultiLineEditor("Run a scenario suite to inspect step output and JSON report previews.", true, true);
            Grid.SetColumn(_previewBox, 2);
            split.Children.Add(_previewBox);

            RenderSteps();
        }

        string SuitePath { get { return ScenarioService.DefaultSuitePath(_app.WorkspaceFolder); } }

        UIElement BuildAddBar()
        {
            var t = Theme.Current;
            var kinds = new[] { "shell", "http", "file_exists", "file_contains" };
            var kindRow = V.H(4);
            for (int i = 0; i < kinds.Length; i++)
            {
                string k = kinds[i];
                kindRow.Children.Add(StudioUi.PillButton(k, null, k == _newKind, delegate { _newKind = k; }));
            }
            var nBox = StudioUi.InputBox("Step Name", "Check Build", 140, out _stepName);
            var tBox = StudioUi.InputBox("Target (URL / command / file path)", "echo ok", 220, out _stepTarget);
            var eBox = StudioUi.InputBox("Expected substring", "", 150, out _stepExpect);
            return V.Box(V.VLead(6, kindRow, V.H(6, nBox, V.Flex(tBox), eBox,
                StudioUi.PillButton("Add Step", "plus", true, delegate
                {
                    _suite.Steps.Add(new ScenarioStep
                    {
                        Name = string.IsNullOrWhiteSpace(_stepName.Text) ? "Step" : _stepName.Text.Trim(),
                        Kind = _newKind,
                        Target = _stepTarget.Text.Trim(),
                        ExpectedText = _stepExpect.Text
                    });
                    RenderSteps();
                }))), V.P(12, 8), t.PanelBackground, 0, t.Separator, 1);
        }

        void RenderSteps()
        {
            var t = Theme.Current;
            _stepsPanel.Children.Clear();
            for (int i = 0; i < _suite.Steps.Count; i++)
            {
                int idx = i;
                var st = _suite.Steps[i];
                ScenarioStepResult res = null;
                if (_lastReport != null)
                    res = _lastReport.Results.FirstOrDefault(r => r.StepId == st.Id);
                Brush badgeBg = res == null ? t.P(0.08) : (res.Passed ? t.Op(t.SysGreen, 0.22) : t.Op(t.SysRed, 0.22));
                Brush badgeFg = res == null ? t.Secondary : (res.Passed ? t.SysGreen : t.SysRed);
                string badgeTxt = res == null ? st.Kind : ((res.Passed ? "PASS " : "FAIL ") + res.ElapsedMs + "ms");

                var row = V.H(8,
                    V.Box(V.T(badgeTxt, 10.5, FontWeights.SemiBold, badgeFg), V.P(8, 3), badgeBg, 5),
                    V.Flex(V.VLead(2,
                        V.T((i + 1) + ". " + st.Name, 12, FontWeights.SemiBold, t.Primary),
                        V.Mono(st.Kind + ": " + st.Target, 10.5, FontWeights.Normal, t.Secondary))),
                    V.Button(Sym.Icon("trash", 11, t.SysRed), delegate { _suite.Steps.RemoveAt(idx); RenderSteps(); }));
                var card = V.Button(V.Box(row, V.P(10, 7), t.ElevatedBackground, 6, t.Separator, 1), delegate
                {
                    if (res != null) _previewBox.Text = res.Details + "\n\n" + res.OutputPreview;
                });
                card.Margin = new Thickness(0, 0, 0, 6);
                _stepsPanel.Children.Add(card);
            }
        }

        void RunAll()
        {
            var suite = _suite;
            string wd = _app.WorkspaceFolder ?? Environment.CurrentDirectory;
            _summaryLbl.Text = "Running " + suite.Steps.Count + " steps...";
            Task.Run(delegate
            {
                var report = ScenarioService.RunSuite(suite, wd);
                Dispatcher.BeginInvoke(new Action(delegate
                {
                    _lastReport = report;
                    _summaryLbl.Text = report.PassedSteps + "/" + report.TotalSteps + " passed (" + report.TotalElapsedMs + " ms)";
                    _summaryLbl.Foreground = report.FailedSteps == 0 ? Theme.Current.SysGreen : Theme.Current.SysRed;
                    _previewBox.Text = ScenarioService.ExportReportJson(report);
                    RenderSteps();
                }));
            });
        }

        void ExportReport()
        {
            if (_lastReport == null) { _summaryLbl.Text = "Run suite first to export report."; return; }
            string dir = Path.GetDirectoryName(SuitePath);
            Directory.CreateDirectory(dir);
            string outPath = Path.Combine(dir, "scenario-report.json");
            Defaults.WriteAtomic(outPath, ScenarioService.ExportReportJson(_lastReport));
            _summaryLbl.Text = "Exported " + outPath;
        }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 4. EMBEDDED & IOT STUDIO (Serial Monitor + Toolchain + Backtrace Decoder)
    // ═════════════════════════════════════════════════════════════════════════════

    public class BacktraceFrame
    {
        public string PcHex = "";
        public string SpHex = "";
        public string Symbol = "";
        public string FileLine = "";
    }

    public class BacktraceDecodeResult
    {
        public string Architecture = "Unknown";
        public string PanicReason = "";
        public string FaultAddress = "";
        public List<BacktraceFrame> Frames = new List<BacktraceFrame>();
        public string Summary = "";
    }

    public class EmbeddedHardwareService : IDisposable
    {
        public static readonly int[] SupportedBaudRates = new[] { 9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600 };
        SerialPort _port;
        public event Action<string> DataReceived;
        public bool IsConnected { get { return _port != null && _port.IsOpen; } }

        public static string[] ListSerialPorts()
        {
            try { return SerialPort.GetPortNames().OrderBy(x => x).ToArray(); }
            catch { return new string[0]; }
        }

        public string Connect(string portName, int baudRate)
        {
            Disconnect();
            if (string.IsNullOrWhiteSpace(portName)) return "No serial port selected.";
            try
            {
                _port = new SerialPort(portName.Trim(), baudRate, Parity.None, 8, StopBits.One);
                _port.Encoding = Encoding.UTF8;
                _port.ReadTimeout = 500;
                _port.WriteTimeout = 500;
                _port.DataReceived += delegate
                {
                    try
                    {
                        if (_port != null && _port.IsOpen)
                        {
                            string chunk = _port.ReadExisting();
                            if (!string.IsNullOrEmpty(chunk) && DataReceived != null) DataReceived(chunk);
                        }
                    }
                    catch { }
                };
                _port.Open();
                return null;
            }
            catch (Exception ex)
            {
                Disconnect();
                return ex.Message;
            }
        }

        public void Disconnect()
        {
            if (_port != null)
            {
                try { if (_port.IsOpen) _port.Close(); } catch { }
                try { _port.Dispose(); } catch { }
                _port = null;
            }
        }

        public bool SendLine(string text)
        {
            if (!IsConnected) return false;
            try { _port.WriteLine(text ?? ""); return true; }
            catch { return false; }
        }

        public static void BuildToolchainCommand(string tool, string action, string port, string target, out string exe, out string args)
        {
            string p = string.IsNullOrWhiteSpace(port) ? "COM3" : port.Trim();
            string tgt = string.IsNullOrWhiteSpace(target) ? "esp32:esp32:esp32" : target.Trim();
            switch ((tool ?? "arduino-cli").ToLowerInvariant())
            {
                case "pio":
                    exe = "pio";
                    args = action == "flash" ? ("run -t upload --upload-port " + p) : (action == "erase" ? "run -t erase" : "run");
                    break;
                case "esptool":
                    exe = "esptool.py";
                    args = action == "erase" ? ("--port " + p + " erase_flash") : ("--port " + p + " chip_id");
                    break;
                case "idf.py":
                    exe = "idf.py";
                    args = action == "flash" ? ("-p " + p + " flash") : (action == "erase" ? ("-p " + p + " erase-flash") : "build");
                    break;
                case "avrdude":
                    exe = "avrdude";
                    args = "-p " + tgt + " -c arduino -P " + p + " -b 115200";
                    break;
                default:
                    exe = "arduino-cli";
                    args = action == "flash"
                        ? ("upload -p " + p + " --fqbn " + tgt)
                        : ("compile --fqbn " + tgt);
                    break;
            }
        }

        public static StudioExecResult RunToolchain(string tool, string action, string port, string target, string workDir, Action<string> onLine)
        {
            string exe, args;
            BuildToolchainCommand(tool, action, port, target, out exe, out args);
            string resolved = StudioProcess.FindExecutable(exe);
            if (resolved == null)
                return new StudioExecResult { ExitCode = -1, StdErr = exe + " not found on PATH." };
            return StudioProcess.Run(resolved, args, workDir, 60000, onLine);
        }

        public static BacktraceDecodeResult DecodeBacktrace(string crashLog, string elfPath)
        {
            var res = new BacktraceDecodeResult();
            if (string.IsNullOrWhiteSpace(crashLog))
            {
                res.Summary = "Paste a serial crash / Guru Meditation / HardFault log.";
                return res;
            }

            var panicM = Regex.Match(crashLog, @"Guru Meditation Error:\s*([^\r\n]+)", RegexOptions.IgnoreCase);
            if (panicM.Success)
            {
                res.Architecture = "Xtensa / ESP32";
                res.PanicReason = panicM.Groups[1].Value.Trim();
            }
            var exvM = Regex.Match(crashLog, @"EXCVADDR\s*:\s*(0x[0-9a-fA-F]+)", RegexOptions.IgnoreCase);
            if (exvM.Success) res.FaultAddress = exvM.Groups[1].Value;

            var btPairs = Regex.Matches(crashLog, @"(0x4[0-9a-fA-F]{7}):(0x3[0-9a-fA-F]{7})");
            if (btPairs.Count > 0)
            {
                res.Architecture = "Xtensa / ESP32";
                for (int i = 0; i < btPairs.Count; i++)
                {
                    res.Frames.Add(new BacktraceFrame
                    {
                        PcHex = btPairs[i].Groups[1].Value,
                        SpHex = btPairs[i].Groups[2].Value
                    });
                }
            }
            else
            {
                var armM = Regex.Matches(crashLog, @"(?:PC|LR|BFAR|MMFAR)\s*[:=]\s*(0x[0-9a-fA-F]{7,8})", RegexOptions.IgnoreCase);
                if (armM.Count > 0) res.Architecture = "ARM Cortex-M";
                for (int i = 0; i < armM.Count; i++)
                    res.Frames.Add(new BacktraceFrame { PcHex = armM[i].Groups[1].Value });
            }

            if (res.Frames.Count == 0)
            {
                var hexes = Regex.Matches(crashLog, @"0x[0-9a-fA-F]{8}");
                for (int i = 0; i < hexes.Count; i++)
                    res.Frames.Add(new BacktraceFrame { PcHex = hexes[i].Value });
            }

            if (!string.IsNullOrEmpty(elfPath) && File.Exists(elfPath) && res.Frames.Count > 0)
            {
                string addr2line = StudioProcess.FindExecutable("xtensa-esp32-elf-addr2line", "arm-none-eabi-addr2line", "addr2line");
                if (addr2line != null)
                {
                    string pcs = string.Join(" ", res.Frames.Select(f => f.PcHex).ToArray());
                    var run = StudioProcess.Run(addr2line, "-pfiaC -e " + StudioProcess.QuoteArg(elfPath) + " " + pcs, null, 10000, null);
                    if (run.Ok)
                    {
                        string[] lines = run.StdOut.Replace("\r\n", "\n").Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
                        for (int i = 0; i < Math.Min(lines.Length, res.Frames.Count); i++)
                            res.Frames[i].FileLine = lines[i].Trim();
                    }
                }
            }

            string hint = "";
            if (crashLog.IndexOf("LoadProhibited", StringComparison.OrdinalIgnoreCase) >= 0)
                hint = "Null/invalid pointer dereference (LoadProhibited).";
            else if (crashLog.IndexOf("StoreProhibited", StringComparison.OrdinalIgnoreCase) >= 0)
                hint = "Write to invalid/read-only memory address (StoreProhibited).";
            else if (crashLog.IndexOf("InstrFetchProhibited", StringComparison.OrdinalIgnoreCase) >= 0)
                hint = "Corrupted function pointer or stack return address.";
            else if (crashLog.IndexOf("HardFault", StringComparison.OrdinalIgnoreCase) >= 0)
                hint = "ARM HardFault: check stack overflow, unaligned access, or null pointer.";

            res.Summary = res.Architecture + " | " + res.Frames.Count + " frame(s)" +
                (string.IsNullOrEmpty(res.PanicReason) ? "" : (" | " + res.PanicReason)) +
                (string.IsNullOrEmpty(hint) ? "" : ("\nHint: " + hint));
            return res;
        }

        public void Dispose() { Disconnect(); }
    }

    public class EmbeddedStudioView : Grid
    {
        readonly AppState _app;
        readonly EmbeddedHardwareService _svc = new EmbeddedHardwareService();
        int _tab;
        string _selectedPort = "";
        int _baud = 115200;
        string _tool = "arduino-cli";
        readonly Border _header = new Border(), _body = new Border();
        TextBox _monitorOut, _txBox, _targetBox, _crashBox, _elfBox, _decodeOut;

        public EmbeddedStudioView() : this(AppState.Shared) { }
        public EmbeddedStudioView(AppState app)
        {
            _app = app ?? AppState.Shared;
            Background = Theme.Current.EditorBackground;
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            Children.Add(_header);
            Grid.SetRow(_body, 1);
            Children.Add(_body);

            _svc.DataReceived += delegate(string chunk)
            {
                Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (_monitorOut != null) { _monitorOut.AppendText(chunk); _monitorOut.ScrollToEnd(); }
                }));
            };
            Unloaded += delegate { _svc.Dispose(); };
            BuildHeader();
            RenderTab();
        }

        void BuildHeader()
        {
            _header.Child = StudioUi.Header("cpu.fill", "Embed & IoT Studio", "Serial Monitor, Firmware Toolchains & Crash Backtrace Decoder",
                StudioUi.TabBar(new[] { "Serial & Toolchain", "Backtrace Decoder" }, _tab, delegate(int idx)
                {
                    _tab = idx;
                    BuildHeader();
                    RenderTab();
                }));
        }

        void RenderTab()
        {
            if (_tab == 0) RenderMonitorTab();
            else RenderDecoderTab();
        }

        void RenderMonitorTab()
        {
            var t = Theme.Current;
            string[] ports = EmbeddedHardwareService.ListSerialPorts();
            if (string.IsNullOrEmpty(_selectedPort) && ports.Length > 0) _selectedPort = ports[0];
            if (_monitorOut == null) _monitorOut = StudioUi.MultiLineEditor("", true, true);

            var portBtn = V.Button(V.Box(V.H(5, Sym.Icon("cable.connector", 11, t.Accent),
                V.T(string.IsNullOrEmpty(_selectedPort) ? "No COM Ports" : _selectedPort, 11.5, FontWeights.SemiBold, t.Primary),
                Sym.Icon("chevron.down", 9, t.Secondary)), V.P(9, 4), t.ControlBackground, 5, t.Separator, 1), null);
            portBtn.MenuItems = delegate
            {
                var ps = EmbeddedHardwareService.ListSerialPorts();
                if (ps.Length == 0) return new List<MenuItemSpec> { new MenuItemSpec { Title = "No COM ports detected", Disabled = true } };
                return ps.Select(p => new MenuItemSpec { Title = p, Checked = p == _selectedPort, Action = delegate { _selectedPort = p; RenderMonitorTab(); } }).ToList();
            };

            var baudBtn = V.Button(V.Box(V.H(5, V.T(_baud + " baud", 11.5, FontWeights.Medium, t.Primary), Sym.Icon("chevron.down", 9, t.Secondary)), V.P(9, 4), t.ControlBackground, 5, t.Separator, 1), null);
            baudBtn.MenuItems = delegate
            {
                return EmbeddedHardwareService.SupportedBaudRates.Select(b => new MenuItemSpec { Title = b + " baud", Checked = b == _baud, Action = delegate { _baud = b; RenderMonitorTab(); } }).ToList();
            };

            var toolBtn = V.Button(V.Box(V.H(5, V.T(_tool, 11.5, FontWeights.Medium, t.Primary), Sym.Icon("chevron.down", 9, t.Secondary)), V.P(9, 4), t.ControlBackground, 5, t.Separator, 1), null);
            toolBtn.MenuItems = delegate
            {
                return new[] { "arduino-cli", "pio", "esptool", "idf.py", "avrdude" }.Select(tl =>
                    new MenuItemSpec { Title = tl, Checked = tl == _tool, Action = delegate { _tool = tl; RenderMonitorTab(); } }).ToList();
            };

            var tgtBox = StudioUi.InputBox("Board / FQBN (e.g. esp32:esp32:esp32)", _targetBox != null ? _targetBox.Text : "esp32:esp32:esp32", 180, out _targetBox);
            var txInput = StudioUi.InputBox("TX serial command...", "", 220, out _txBox);

            var topBar = V.H(6,
                portBtn, baudBtn,
                StudioUi.PillButton("Refresh", "arrow.clockwise", false, RenderMonitorTab),
                StudioUi.PillButton(_svc.IsConnected ? "Disconnect" : "Connect", _svc.IsConnected ? "stop.fill" : "play.fill", true, delegate
                {
                    if (_svc.IsConnected) _svc.Disconnect();
                    else
                    {
                        string err = _svc.Connect(_selectedPort, _baud);
                        if (err != null) _monitorOut.AppendText("\n[Serial Error] " + err + "\n");
                        else _monitorOut.AppendText("\n[Connected " + _selectedPort + " @ " + _baud + "]\n");
                    }
                    RenderMonitorTab();
                }),
                V.Sp(),
                toolBtn, tgtBox,
                StudioUi.PillButton("Compile", "hammer.fill", false, delegate { RunTool("compile"); }),
                StudioUi.PillButton("Flash", "bolt.fill", true, delegate { RunTool("flash"); }));

            var g = new Grid { Margin = V.P(12) };
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g.Children.Add(topBar);
            Grid.SetRow(_monitorOut, 1);
            _monitorOut.Margin = V.P(0, 8, 0, 8);
            g.Children.Add(_monitorOut);

            var txRow = V.H(6, V.Flex(txInput),
                StudioUi.PillButton("Send", "paperplane.fill", true, delegate
                {
                    if (_svc.SendLine(_txBox.Text)) { _monitorOut.AppendText("> " + _txBox.Text + "\n"); _txBox.Text = ""; }
                    else _monitorOut.AppendText("[Not connected]\n");
                }),
                StudioUi.PillButton("Clear", "trash", false, delegate { _monitorOut.Text = ""; }));
            Grid.SetRow(txRow, 2);
            g.Children.Add(txRow);
            _body.Child = g;
        }

        void RunTool(string action)
        {
            string tool = _tool, port = _selectedPort, target = _targetBox.Text, wd = _app.WorkspaceFolder ?? Environment.CurrentDirectory;
            _monitorOut.AppendText("\n[" + tool + " " + action + "]\n");
            Task.Run(delegate
            {
                var r = EmbeddedHardwareService.RunToolchain(tool, action, port, target, wd, delegate(string line)
                {
                    Dispatcher.BeginInvoke(new Action(delegate { _monitorOut.AppendText(line + "\n"); _monitorOut.ScrollToEnd(); }));
                });
                Dispatcher.BeginInvoke(new Action(delegate { _monitorOut.AppendText("[Done exit=" + r.ExitCode + " in " + r.ElapsedMs + "ms]\n"); }));
            });
        }

        void RenderDecoderTab()
        {
            if (_crashBox == null)
            {
                _crashBox = StudioUi.MultiLineEditor("Guru Meditation Error: Core  1 panic'ed (LoadProhibited). Exception was unhandled.\nEXCVADDR: 0x00000000\nBacktrace: 0x400d12a4:0x3ffb1f10 0x400d1580:0x3ffb1f40", false, true);
                _crashBox.Height = 140;
            }
            if (_decodeOut == null) _decodeOut = StudioUi.MultiLineEditor("", true, true);
            var elfInput = StudioUi.InputBox("Optional .elf path for addr2line symbol resolution", _elfBox != null ? _elfBox.Text : "", 300, out _elfBox);

            var col = V.VLead(8,
                V.H(8, V.Flex(elfInput), StudioUi.PillButton("Decode Backtrace", "ladybug", true, delegate
                {
                    var d = EmbeddedHardwareService.DecodeBacktrace(_crashBox.Text, _elfBox.Text);
                    var sb = new StringBuilder();
                    sb.AppendLine(d.Summary);
                    if (!string.IsNullOrEmpty(d.FaultAddress)) sb.AppendLine("Fault Address: " + d.FaultAddress);
                    for (int i = 0; i < d.Frames.Count; i++)
                    {
                        var f = d.Frames[i];
                        sb.AppendLine("  #" + i + "  PC=" + f.PcHex + (string.IsNullOrEmpty(f.SpHex) ? "" : ("  SP=" + f.SpHex)) + (string.IsNullOrEmpty(f.FileLine) ? "" : ("  -> " + f.FileLine)));
                    }
                    _decodeOut.Text = sb.ToString();
                })),
                _crashBox,
                _decodeOut);
            col.Margin = V.P(12);
            _body.Child = StudioUi.Scroller(col);
        }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 5. EXTENSION STUDIO (Open VSX Marketplace + Local VSIX Unpacker & Manager)
    // ═════════════════════════════════════════════════════════════════════════════

    public class VsxExtension
    {
        public string Name = "";
        public string Namespace = "";
        public string DisplayName = "";
        public string Version = "";
        public string Description = "";
        public string DownloadUrl = "";
        public string IconUrl = "";
        public long DownloadCount;
        public bool Enabled = true;
        public string InstallPath = "";
        public string Id
        {
            get { return string.IsNullOrEmpty(Namespace) ? Name : (Namespace + "." + Name); }
        }
    }

    public static class OpenVsxService
    {
        public static string ExtensionsDir
        {
            get { return Path.Combine(Defaults.Dir, "Extensions"); }
        }

        public static List<VsxExtension> ParseSearchJson(string json)
        {
            var list = new List<VsxExtension>();
            var root = DJ.Obj(json);
            var exts = DJ.Arr(root, "extensions");
            if (exts == null) return list;
            for (int i = 0; i < exts.Count; i++)
            {
                var o = exts[i] as Dictionary<string, object>;
                if (o == null) continue;
                var files = DJ.Child(o, "files");
                double? dlCount = DJ.Num(o, "downloadCount");
                string ns = DJ.Str(o, "namespace") ?? "";
                string name = DJ.Str(o, "name") ?? "";
                list.Add(new VsxExtension
                {
                    Namespace = ns,
                    Name = name,
                    DisplayName = DJ.Str(o, "displayName") ?? name,
                    Version = DJ.Str(o, "version") ?? "",
                    Description = DJ.Str(o, "description") ?? "",
                    DownloadCount = dlCount.HasValue ? (long)dlCount.Value : 0,
                    DownloadUrl = DJ.Str(files, "download") ?? "",
                    IconUrl = DJ.Str(files, "icon") ?? ""
                });
            }
            return list;
        }

        public static async Task<List<VsxExtension>> SearchAsync(string query, int size)
        {
            string q = Uri.EscapeDataString((query ?? "").Trim());
            int lim = size > 0 ? size : 20;
            string url = "https://open-vsx.org/api/-/search?query=" + q + "&size=" + lim;
            string json = await DotminiNet.Http.GetStringAsync(url);
            return ParseSearchJson(json);
        }

        public static void UnpackVsix(string vsixPath, string targetDir)
        {
            if (string.IsNullOrEmpty(vsixPath) || !File.Exists(vsixPath))
                throw new FileNotFoundException("VSIX package not found.", vsixPath);
            Directory.CreateDirectory(targetDir);

            // 1. Try System.IO.Compression.ZipFile via reflection so build.cmd needs no extra /r: flag.
            try
            {
                var asm = Assembly.Load("System.IO.Compression.FileSystem, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089");
                if (asm != null)
                {
                    var zipType = asm.GetType("System.IO.Compression.ZipFile");
                    if (zipType != null)
                    {
                        var mi = zipType.GetMethod("ExtractToDirectory", new[] { typeof(string), typeof(string) });
                        if (mi != null)
                        {
                            mi.Invoke(null, new object[] { vsixPath, targetDir });
                            return;
                        }
                    }
                }
            }
            catch { }

            // 2. Pure-C# ZIP extractor using System.IO.Compression.DeflateStream (built into System.dll).
            if (TryExtractZipWithDeflateStream(vsixPath, targetDir)) return;

            // 3. PowerShell Expand-Archive fallback on Windows.
            if (StudioProcess.IsWindows)
            {
                string tmpZip = vsixPath + ".zip";
                File.Copy(vsixPath, tmpZip, true);
                try
                {
                    var res = StudioProcess.Run("powershell.exe",
                        "-NoProfile -ExecutionPolicy Bypass -Command " + StudioProcess.QuoteArg("Expand-Archive -Force -Path " + StudioProcess.QuoteArg(tmpZip) + " -DestinationPath " + StudioProcess.QuoteArg(targetDir)),
                        null, 30000, null);
                    if (!res.Ok) throw new InvalidOperationException("Expand-Archive failed: " + res.Combined);
                    return;
                }
                finally
                {
                    try { File.Delete(tmpZip); } catch { }
                }
            }
            throw new InvalidOperationException("Unable to unpack VSIX archive.");
        }

        static bool TryExtractZipWithDeflateStream(string zipPath, string targetDir)
        {
            try
            {
                string fullRoot = Path.GetFullPath(targetDir).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
                using (var fs = new FileStream(zipPath, FileMode.Open, FileAccess.Read, FileShare.Read))
                using (var br = new BinaryReader(fs))
                {
                    while (fs.Position + 30 <= fs.Length)
                    {
                        uint sig = br.ReadUInt32();
                        if (sig != 0x04034b50) break;
                        br.ReadUInt16(); // version
                        ushort flags = br.ReadUInt16();
                        ushort method = br.ReadUInt16();
                        br.ReadUInt16(); // mtime
                        br.ReadUInt16(); // mdate
                        br.ReadUInt32(); // crc32
                        uint compSize = br.ReadUInt32();
                        br.ReadUInt32(); // uncompSize
                        ushort nameLen = br.ReadUInt16();
                        ushort extraLen = br.ReadUInt16();
                        byte[] nameBytes = br.ReadBytes(nameLen);
                        if (extraLen > 0) br.ReadBytes(extraLen);
                        string rel = Encoding.UTF8.GetString(nameBytes).Replace('/', Path.DirectorySeparatorChar);
                        if ((flags & 0x08) != 0 && compSize == 0) return false; // data descriptor streaming not handled here
                        byte[] payload = compSize > 0 ? br.ReadBytes((int)compSize) : new byte[0];

                        string dest = Path.GetFullPath(Path.Combine(targetDir, rel));
                        if (!dest.StartsWith(fullRoot, StringComparison.OrdinalIgnoreCase) &&
                            !string.Equals(dest + Path.DirectorySeparatorChar, fullRoot, StringComparison.OrdinalIgnoreCase))
                            continue;
                        if (rel.EndsWith(Path.DirectorySeparatorChar.ToString()))
                        {
                            Directory.CreateDirectory(dest);
                            continue;
                        }
                        Directory.CreateDirectory(Path.GetDirectoryName(dest));
                        if (method == 0)
                        {
                            File.WriteAllBytes(dest, payload);
                        }
                        else if (method == 8)
                        {
                            using (var ms = new MemoryStream(payload))
                            using (var ds = new DeflateStream(ms, CompressionMode.Decompress))
                            using (var outFs = new FileStream(dest, FileMode.Create, FileAccess.Write))
                            {
                                ds.CopyTo(outFs);
                            }
                        }
                        else
                        {
                            return false;
                        }
                    }
                }
                return true;
            }
            catch
            {
                return false;
            }
        }

        public static async Task<VsxExtension> DownloadAndInstallAsync(VsxExtension ext)
        {
            if (ext == null || string.IsNullOrEmpty(ext.DownloadUrl))
                throw new InvalidOperationException("Extension has no download URL.");
            string id = ext.Id;
            string target = Path.Combine(ExtensionsDir, id);
            if (Directory.Exists(target)) Directory.Delete(target, true);
            Directory.CreateDirectory(ExtensionsDir);
            string tmpVsix = Path.Combine(Path.GetTempPath(), "mc_vsix_" + Guid.NewGuid().ToString("N") + ".vsix");
            try
            {
                byte[] bytes = await DotminiNet.Http.GetByteArrayAsync(ext.DownloadUrl);
                File.WriteAllBytes(tmpVsix, bytes);
                UnpackVsix(tmpVsix, target);
                var meta = new Dictionary<string, object>
                {
                    { "id", id }, { "namespace", ext.Namespace }, { "name", ext.Name },
                    { "displayName", ext.DisplayName }, { "version", ext.Version },
                    { "description", ext.Description }, { "downloadUrl", ext.DownloadUrl }
                };
                File.WriteAllText(Path.Combine(target, "microcode-vsix.json"), DJ.Ser(meta), Encoding.UTF8);
                ext.InstallPath = target;
                ext.Enabled = true;
                return ext;
            }
            finally
            {
                try { if (File.Exists(tmpVsix)) File.Delete(tmpVsix); } catch { }
            }
        }

        public static List<VsxExtension> ListInstalled()
        {
            var list = new List<VsxExtension>();
            if (!Directory.Exists(ExtensionsDir)) return list;
            string[] dirs = Directory.GetDirectories(ExtensionsDir);
            for (int i = 0; i < dirs.Length; i++)
            {
                string dir = dirs[i];
                string folderName = Path.GetFileName(dir);
                string metaPath = Path.Combine(dir, "microcode-vsix.json");
                string pkgPath = Path.Combine(dir, "extension", "package.json");
                var ext = new VsxExtension
                {
                    Name = folderName,
                    DisplayName = folderName,
                    InstallPath = dir,
                    Enabled = !File.Exists(Path.Combine(dir, ".disabled"))
                };
                if (File.Exists(metaPath))
                {
                    var o = DJ.Obj(File.ReadAllText(metaPath, Encoding.UTF8));
                    if (o != null)
                    {
                        ext.Namespace = DJ.Str(o, "namespace") ?? "";
                        ext.Name = DJ.Str(o, "name") ?? folderName;
                        ext.DisplayName = DJ.Str(o, "displayName") ?? ext.Name;
                        ext.Version = DJ.Str(o, "version") ?? "";
                        ext.Description = DJ.Str(o, "description") ?? "";
                    }
                }
                else if (File.Exists(pkgPath))
                {
                    var o = DJ.Obj(File.ReadAllText(pkgPath, Encoding.UTF8));
                    if (o != null)
                    {
                        ext.Namespace = DJ.Str(o, "publisher") ?? "";
                        ext.Name = DJ.Str(o, "name") ?? folderName;
                        ext.DisplayName = DJ.Str(o, "displayName") ?? ext.Name;
                        ext.Version = DJ.Str(o, "version") ?? "";
                        ext.Description = DJ.Str(o, "description") ?? "";
                    }
                }
                list.Add(ext);
            }
            return list.OrderBy(e => e.Id).ToList();
        }

        public static void SetEnabled(string id, bool enabled)
        {
            string dir = Path.Combine(ExtensionsDir, id);
            if (!Directory.Exists(dir)) return;
            string marker = Path.Combine(dir, ".disabled");
            if (enabled) { if (File.Exists(marker)) File.Delete(marker); }
            else File.WriteAllText(marker, "disabled");
        }

        public static void RemoveInstalled(string id)
        {
            string dir = Path.Combine(ExtensionsDir, id);
            if (Directory.Exists(dir)) Directory.Delete(dir, true);
        }
    }

    public class ExtensionStudioView : Grid
    {
        readonly AppState _app;
        int _tab;
        List<VsxExtension> _results = new List<VsxExtension>();
        readonly Border _header = new Border();
        readonly StackPanel _listPanel = new StackPanel();
        TextBox _searchBox;
        readonly TextBlock _statusLbl;

        public ExtensionStudioView() : this(AppState.Shared) { }
        public ExtensionStudioView(AppState app)
        {
            _app = app ?? AppState.Shared;
            var t = Theme.Current;
            Background = t.EditorBackground;
            _statusLbl = V.T("Open VSX Marketplace ready", 11, FontWeights.Normal, t.Secondary);
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            Children.Add(_header);
            var qBox = StudioUi.InputBox("Search Open VSX extensions (e.g. python, rust, theme)...", "python", 260, out _searchBox);
            var bar = V.Box(V.H(8, V.Flex(qBox), StudioUi.PillButton("Search", "magnifyingglass", true, DoSearch), _statusLbl),
                V.P(12, 8), t.PanelBackground, 0, t.Separator, 1);
            Grid.SetRow(bar, 1);
            Children.Add(bar);

            var sc = StudioUi.Scroller(V.Box(_listPanel, V.P(12), Brushes.Transparent, 0));
            Grid.SetRow(sc, 2);
            Children.Add(sc);

            BuildHeader();
            RenderList();
        }

        void BuildHeader()
        {
            _header.Child = StudioUi.Header("puzzlepiece.extension", "Extension Studio", "Open VSX Marketplace & Local VSIX Manager",
                StudioUi.TabBar(new[] { "Marketplace", "Installed" }, _tab, delegate(int idx)
                {
                    _tab = idx;
                    BuildHeader();
                    RenderList();
                }));
        }

        async void DoSearch()
        {
            _tab = 0;
            BuildHeader();
            string q = _searchBox.Text.Trim();
            _statusLbl.Text = "Searching Open VSX...";
            try
            {
                _results = await OpenVsxService.SearchAsync(q, 25);
                _statusLbl.Text = _results.Count + " extensions found";
                RenderList();
            }
            catch (Exception ex)
            {
                _statusLbl.Text = "Search error: " + ex.Message;
            }
        }

        void RenderList()
        {
            var t = Theme.Current;
            _listPanel.Children.Clear();
            var items = _tab == 0 ? _results : OpenVsxService.ListInstalled();
            if (items.Count == 0)
            {
                _listPanel.Children.Add(V.T(_tab == 0 ? "Search Open VSX above to browse extensions." : "No VSIX extensions installed in " + OpenVsxService.ExtensionsDir,
                    12, FontWeights.Normal, t.Secondary));
                return;
            }
            for (int i = 0; i < items.Count; i++)
            {
                var ext = items[i];
                var rightBtns = V.H(6);
                if (_tab == 0)
                {
                    rightBtns.Children.Add(StudioUi.PillButton("Install", "arrow.down.circle", true, async delegate
                    {
                        _statusLbl.Text = "Downloading " + ext.Id + "...";
                        try
                        {
                            await OpenVsxService.DownloadAndInstallAsync(ext);
                            _statusLbl.Text = "Installed " + ext.Id;
                        }
                        catch (Exception ex) { _statusLbl.Text = "Install failed: " + ex.Message; }
                    }));
                }
                else
                {
                    string manifestPath = Path.Combine(Path.Combine(ext.InstallPath, "extension"), "package.json");
                    if (File.Exists(manifestPath))
                    {
                        rightBtns.Children.Add(StudioUi.PillButton("Manifest", "doc.text", false, delegate
                        {
                            (_app ?? AppState.Shared).OpenFile(manifestPath);
                        }));
                    }
                    rightBtns.Children.Add(StudioUi.PillButton(ext.Enabled ? "Disable" : "Enable", null, false, delegate
                    {
                        OpenVsxService.SetEnabled(ext.Id, !ext.Enabled);
                        RenderList();
                    }));
                    rightBtns.Children.Add(StudioUi.PillButton("Remove", "trash", false, delegate
                    {
                        OpenVsxService.RemoveInstalled(ext.Id);
                        RenderList();
                    }));
                }

                var card = V.Box(
                    V.H(10,
                        Sym.Icon("puzzlepiece.extension.fill", 18, ext.Enabled ? t.Accent : t.Secondary),
                        V.Flex(V.VLead(2,
                            V.H(6,
                                V.T(ext.DisplayName, 12.5, FontWeights.SemiBold, t.Primary),
                                V.Mono(ext.Id + (string.IsNullOrEmpty(ext.Version) ? "" : (" v" + ext.Version)), 10.5, FontWeights.Normal, t.Secondary)),
                            V.T(ext.Description, 11.5, FontWeights.Normal, t.Secondary))),
                        rightBtns),
                    V.P(10, 8), t.ElevatedBackground, 7, t.Separator, 1);
                card.Margin = new Thickness(0, 0, 0, 6);
                _listPanel.Children.Add(card);
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 6. DATABASE STUDIO (SQLite / PostgreSQL / MySQL / SQL Server)
    // ═════════════════════════════════════════════════════════════════════════════

    public class DbQueryResult
    {
        public bool Ok;
        public string Error = "";
        public List<string> Columns = new List<string>();
        public List<List<string>> Rows = new List<List<string>>();
        public string RawOutput = "";
        public long ElapsedMs;
    }

    public static class DatabaseStudioService
    {
        public static string SchemaQueryFor(string engine)
        {
            switch ((engine ?? "SQLite").ToLowerInvariant())
            {
                case "postgresql": return "SELECT tablename AS table_name FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;";
                case "mysql": return "SHOW TABLES;";
                case "sql server": return "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;";
                default: return "SELECT name AS table_name FROM sqlite_master WHERE type='table' ORDER BY name;";
            }
        }

        public static DbQueryResult ParseDelimitedTable(string raw, char sep)
        {
            var res = new DbQueryResult { Ok = true, RawOutput = raw ?? "" };
            if (string.IsNullOrWhiteSpace(raw)) return res;
            string[] lines = raw.Replace("\r\n", "\n").Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
            if (lines.Length == 0) return res;
            res.Columns = lines[0].Split(sep).Select(c => c.Trim()).ToList();
            for (int i = 1; i < lines.Length; i++)
            {
                res.Rows.Add(lines[i].Split(sep).Select(c => c.Trim()).ToList());
            }
            return res;
        }

        public static void BuildCommand(string engine, string conn, string query, out string exe, out string args)
        {
            string c = (conn ?? "").Trim();
            string q = (query ?? "").Trim();
            switch ((engine ?? "SQLite").ToLowerInvariant())
            {
                case "postgresql":
                    exe = "psql";
                    args = StudioProcess.QuoteArg(c) + " -A -F " + StudioProcess.QuoteArg("\t") + " -c " + StudioProcess.QuoteArg(q);
                    break;
                case "mysql":
                    exe = "mysql";
                    args = c + " --batch -e " + StudioProcess.QuoteArg(q);
                    break;
                case "sql server":
                    exe = "sqlcmd";
                    args = c + " -s " + StudioProcess.QuoteArg("\t") + " -W -Q " + StudioProcess.QuoteArg(q);
                    break;
                default:
                    exe = "sqlite3";
                    args = "-header -separator " + StudioProcess.QuoteArg("\t") + " " + StudioProcess.QuoteArg(c) + " " + StudioProcess.QuoteArg(q);
                    break;
            }
        }

        public static DbQueryResult ExecuteQuery(string engine, string conn, string query)
        {
            if (string.IsNullOrWhiteSpace(conn))
                return new DbQueryResult { Error = "Provide a database path or connection string." };
            if (string.IsNullOrWhiteSpace(query))
                return new DbQueryResult { Error = "SQL query is empty." };

            string exe, args;
            BuildCommand(engine, conn, query, out exe, out args);
            string resolved = StudioProcess.FindExecutable(exe);

            // Python sqlite3 fallback when sqlite3 CLI is missing on Windows/macOS.
            if (resolved == null && (engine ?? "SQLite").Equals("SQLite", StringComparison.OrdinalIgnoreCase))
            {
                string py = StudioProcess.FindExecutable("python3", "python");
                if (py != null)
                {
                    string script = "import sqlite3,sys;con=sqlite3.connect(sys.argv[1]);cur=con.cursor();cur.execute(sys.argv[2]);" +
                        "cols=[d[0] for d in cur.description] if cur.description else [];" +
                        "print('\\t'.join(cols)) if cols else None;" +
                        "[print('\\t'.join('' if v is None else str(v) for v in r)) for r in cur.fetchall()];con.commit()";
                    var pr = StudioProcess.Run(py, "-c " + StudioProcess.QuoteArg(script) + " " + StudioProcess.QuoteArg(conn.Trim()) + " " + StudioProcess.QuoteArg(query.Trim()), null, 20000, null);
                    if (!pr.Ok) return new DbQueryResult { Error = pr.Combined, RawOutput = pr.Combined, ElapsedMs = pr.ElapsedMs };
                    var parsed = ParseDelimitedTable(pr.StdOut, '\t');
                    parsed.ElapsedMs = pr.ElapsedMs;
                    return parsed;
                }
            }

            if (resolved == null)
                return new DbQueryResult { Error = exe + " CLI not found on PATH." };

            var run = StudioProcess.Run(resolved, args, null, 30000, null);
            if (!run.Ok) return new DbQueryResult { Error = run.Combined, RawOutput = run.Combined, ElapsedMs = run.ElapsedMs };
            var tbl = ParseDelimitedTable(run.StdOut, '\t');
            tbl.ElapsedMs = run.ElapsedMs;
            return tbl;
        }
    }

    public class DatabaseStudioView : Grid
    {
        readonly AppState _app;
        string _engine = "SQLite";
        TextBox _connBox, _sqlBox;
        readonly StackPanel _tablesPanel = new StackPanel();
        readonly Border _resultHost = new Border();
        readonly TextBlock _statusLbl;

        public DatabaseStudioView() : this(AppState.Shared) { }
        public DatabaseStudioView(AppState app)
        {
            _app = app ?? AppState.Shared;
            var t = Theme.Current;
            Background = t.EditorBackground;
            _statusLbl = V.T("Ready", 11, FontWeights.Normal, t.Secondary);

            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            Children.Add(StudioUi.Header("cylinder.fill", "Database Studio", "SQLite, PostgreSQL (psql), MySQL (mysql) & SQL Server (sqlcmd)", _statusLbl));

            var engLbl = V.T(_engine, 11.5, FontWeights.SemiBold, t.Primary);
            var engBtn = V.Button(V.Box(V.H(5, engLbl, Sym.Icon("chevron.down", 9, t.Secondary)),
                V.P(10, 5), t.ControlBackground, 5, t.Separator, 1), null);
            engBtn.MenuItems = delegate
            {
                return new[] { "SQLite", "PostgreSQL", "MySQL", "SQL Server" }.Select(e =>
                    new MenuItemSpec { Title = e, Checked = e == _engine, Action = delegate { _engine = e; engLbl.Text = e; _connBox.Text = ""; } }).ToList();
            };

            string defaultDb = !string.IsNullOrEmpty(_app.WorkspaceFolder) ? Path.Combine(_app.WorkspaceFolder, "app.db") : "app.db";
            var connBorder = StudioUi.InputBox("Database file path or connection string / flags...", defaultDb, 280, out _connBox);
            var connBar = V.Box(V.H(8, engBtn, V.Flex(connBorder),
                StudioUi.PillButton("Load Tables", "arrow.clockwise", false, LoadTables),
                StudioUi.PillButton("Run (Ctrl+Enter)", "play.fill", true, RunQuery)),
                V.P(12, 8), t.PanelBackground, 0, t.Separator, 1);
            Grid.SetRow(connBar, 1);
            Children.Add(connBar);

            var split = new Grid();
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(220) });
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Grid.SetRow(split, 2);
            Children.Add(split);

            split.Children.Add(StudioUi.Scroller(V.Box(_tablesPanel, V.P(10), t.PanelBackground, 0)));
            var sep = V.Line(t.Separator, false);
            Grid.SetColumn(sep, 1);
            split.Children.Add(sep);

            var right = new Grid();
            right.RowDefinitions.Add(new RowDefinition { Height = new GridLength(150) });
            right.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1) });
            right.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            _sqlBox = StudioUi.MultiLineEditor("SELECT 1 AS ok;", false, true);
            _sqlBox.PreviewKeyDown += delegate(object s, KeyEventArgs e)
            {
                if (e.Key == Key.Enter && (Keyboard.Modifiers & ModifierKeys.Control) == ModifierKeys.Control)
                {
                    e.Handled = true;
                    RunQuery();
                }
            };
            right.Children.Add(_sqlBox);
            var rSep = V.Line(t.Separator, true);
            Grid.SetRow(rSep, 1);
            right.Children.Add(rSep);
            Grid.SetRow(_resultHost, 2);
            right.Children.Add(_resultHost);

            Grid.SetColumn(right, 2);
            split.Children.Add(right);
        }

        void LoadTables()
        {
            string eng = _engine, conn = _connBox.Text;
            string sql = DatabaseStudioService.SchemaQueryFor(eng);
            _statusLbl.Text = "Loading schema...";
            Task.Run(delegate
            {
                var r = DatabaseStudioService.ExecuteQuery(eng, conn, sql);
                Dispatcher.BeginInvoke(new Action(delegate
                {
                    var t = Theme.Current;
                    _tablesPanel.Children.Clear();
                    if (!r.Ok)
                    {
                        _statusLbl.Text = r.Error;
                        return;
                    }
                    _statusLbl.Text = r.Rows.Count + " table(s)";
                    for (int i = 0; i < r.Rows.Count; i++)
                    {
                        if (r.Rows[i].Count == 0) continue;
                        string tblName = r.Rows[i][0];
                        var tb = V.Button(V.Box(V.H(6, Sym.Icon("tablecells", 11, t.Accent), V.T(tblName, 11.5, FontWeights.Medium, t.Primary)),
                            V.P(8, 5), t.ElevatedBackground, 5), delegate
                        {
                            _sqlBox.Text = "SELECT * FROM " + tblName + " LIMIT 100;";
                            RunQuery();
                        });
                        tb.Margin = new Thickness(0, 0, 0, 4);
                        _tablesPanel.Children.Add(tb);
                    }
                }));
            });
        }

        void RunQuery()
        {
            string eng = _engine, conn = _connBox.Text, sql = _sqlBox.Text;
            _statusLbl.Text = "Executing query...";
            Task.Run(delegate
            {
                var r = DatabaseStudioService.ExecuteQuery(eng, conn, sql);
                Dispatcher.BeginInvoke(new Action(delegate { RenderResult(r); }));
            });
        }

        void RenderResult(DbQueryResult r)
        {
            var t = Theme.Current;
            if (!r.Ok)
            {
                _statusLbl.Text = "Query failed";
                _resultHost.Child = StudioUi.MultiLineEditor(r.Error, true, true);
                return;
            }
            _statusLbl.Text = r.Rows.Count + " row(s) in " + r.ElapsedMs + " ms";
            if (r.Columns.Count == 0)
            {
                _resultHost.Child = StudioUi.MultiLineEditor(string.IsNullOrEmpty(r.RawOutput) ? "Query executed successfully (0 rows returned)." : r.RawOutput, true, true);
                return;
            }
            var grid = new Grid { Margin = V.P(8) };
            for (int c = 0; c < r.Columns.Count; c++)
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto, MinWidth = 90 });

            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            for (int c = 0; c < r.Columns.Count; c++)
            {
                var hdr = V.Box(V.T(r.Columns[c], 11.5, FontWeights.SemiBold, t.Primary), V.P(8, 5), t.PanelBackground, 0, t.Separator, 1);
                Grid.SetColumn(hdr, c);
                grid.Children.Add(hdr);
            }

            int maxRows = Math.Min(r.Rows.Count, 250);
            for (int rowIdx = 0; rowIdx < maxRows; rowIdx++)
            {
                grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                var row = r.Rows[rowIdx];
                Brush bg = (rowIdx % 2 == 0) ? t.EditorBackground : t.P(0.03);
                for (int c = 0; c < r.Columns.Count; c++)
                {
                    string val = c < row.Count ? row[c] : "";
                    var cell = V.Box(V.Mono(val, 11, FontWeights.Normal, t.Primary), V.P(8, 4), bg, 0, t.Separator, 0.5);
                    Grid.SetRow(cell, rowIdx + 1);
                    Grid.SetColumn(cell, c);
                    grid.Children.Add(cell);
                }
            }
            _resultHost.Child = new ScrollViewer
            {
                Content = grid,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            };
        }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 7. CONTAINER STUDIO (Docker CLI Controller)
    // ═════════════════════════════════════════════════════════════════════════════

    public class DockerContainerInfo
    {
        public string Id = "";
        public string Name = "";
        public string Image = "";
        public string Status = "";
        public string Ports = "";
        public bool IsRunning { get { return Status.StartsWith("Up", StringComparison.OrdinalIgnoreCase); } }
    }

    public class DockerImageInfo
    {
        public string Repository = "";
        public string Tag = "";
        public string Id = "";
        public string Size = "";
    }

    public static class ContainerService
    {
        public static List<DockerContainerInfo> ParseContainersOutput(string raw)
        {
            var list = new List<DockerContainerInfo>();
            if (string.IsNullOrWhiteSpace(raw)) return list;
            string[] lines = raw.Replace("\r\n", "\n").Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
            for (int i = 0; i < lines.Length; i++)
            {
                string[] parts = lines[i].Split('\t');
                if (parts.Length < 4) continue;
                list.Add(new DockerContainerInfo
                {
                    Id = parts[0].Trim(),
                    Name = parts[1].Trim(),
                    Image = parts[2].Trim(),
                    Status = parts[3].Trim(),
                    Ports = parts.Length > 4 ? parts[4].Trim() : ""
                });
            }
            return list;
        }

        public static List<DockerImageInfo> ParseImagesOutput(string raw)
        {
            var list = new List<DockerImageInfo>();
            if (string.IsNullOrWhiteSpace(raw)) return list;
            string[] lines = raw.Replace("\r\n", "\n").Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
            for (int i = 0; i < lines.Length; i++)
            {
                string[] parts = lines[i].Split('\t');
                if (parts.Length < 4) continue;
                list.Add(new DockerImageInfo
                {
                    Repository = parts[0].Trim(),
                    Tag = parts[1].Trim(),
                    Id = parts[2].Trim(),
                    Size = parts[3].Trim()
                });
            }
            return list;
        }

        public static List<DockerContainerInfo> ListContainers(out string error)
        {
            error = "";
            string docker = StudioProcess.FindExecutable("docker");
            if (docker == null) { error = "docker CLI not found on PATH."; return new List<DockerContainerInfo>(); }
            var r = StudioProcess.Run(docker, "ps -a --format \"{{.ID}}\\t{{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}\"", null, 12000, null);
            if (!r.Ok) { error = r.Combined; return new List<DockerContainerInfo>(); }
            return ParseContainersOutput(r.StdOut);
        }

        public static List<DockerImageInfo> ListImages(out string error)
        {
            error = "";
            string docker = StudioProcess.FindExecutable("docker");
            if (docker == null) { error = "docker CLI not found on PATH."; return new List<DockerImageInfo>(); }
            var r = StudioProcess.Run(docker, "images --format \"{{.Repository}}\\t{{.Tag}}\\t{{.ID}}\\t{{.Size}}\"", null, 12000, null);
            if (!r.Ok) { error = r.Combined; return new List<DockerImageInfo>(); }
            return ParseImagesOutput(r.StdOut);
        }

        public static StudioExecResult ContainerAction(string action, string id)
        {
            string docker = StudioProcess.FindExecutable("docker");
            if (docker == null) return new StudioExecResult { ExitCode = -1, StdErr = "docker CLI not found." };
            string cmd = action == "rm" ? ("rm -f " + id) : (action + " " + id);
            return StudioProcess.Run(docker, cmd, null, 20000, null);
        }

        public static StudioExecResult GetLogs(string id, int tail)
        {
            string docker = StudioProcess.FindExecutable("docker");
            if (docker == null) return new StudioExecResult { ExitCode = -1, StdErr = "docker CLI not found." };
            return StudioProcess.Run(docker, "logs --tail " + (tail > 0 ? tail : 200) + " " + id, null, 12000, null);
        }
    }

    public class ContainerStudioView : Grid
    {
        readonly AppState _app;
        int _tab;
        readonly Border _header = new Border();
        readonly StackPanel _listPanel = new StackPanel();
        TextBox _logsBox;
        readonly TextBlock _statusLbl;

        public ContainerStudioView() : this(AppState.Shared) { }
        public ContainerStudioView(AppState app)
        {
            _app = app ?? AppState.Shared;
            var t = Theme.Current;
            Background = t.EditorBackground;
            _statusLbl = V.T(string.IsNullOrEmpty(_app.WorkspaceFolder) ? "Docker CLI" : ("Docker CLI (" + Path.GetFileName(_app.WorkspaceFolder) + ")"), 11, FontWeights.Normal, t.Secondary);

            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            Children.Add(_header);

            var split = new Grid();
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0.58, GridUnitType.Star) });
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0.42, GridUnitType.Star) });
            Grid.SetRow(split, 1);
            Children.Add(split);

            split.Children.Add(StudioUi.Scroller(V.Box(_listPanel, V.P(12), Brushes.Transparent, 0)));
            var sep = V.Line(t.Separator, false);
            Grid.SetColumn(sep, 1);
            split.Children.Add(sep);
            _logsBox = StudioUi.MultiLineEditor("Select a container and click Logs to inspect stdout/stderr.", true, true);
            Grid.SetColumn(_logsBox, 2);
            split.Children.Add(_logsBox);

            BuildHeader();
            Refresh();
        }

        void BuildHeader()
        {
            _header.Child = StudioUi.Header("shippingbox.fill", "Container Studio", "Docker Containers, Images & Live Logs",
                _statusLbl,
                StudioUi.TabBar(new[] { "Containers", "Images" }, _tab, delegate(int idx)
                {
                    _tab = idx;
                    BuildHeader();
                    Refresh();
                }),
                StudioUi.PillButton("Refresh", "arrow.clockwise", true, Refresh));
        }

        void Refresh()
        {
            _statusLbl.Text = "Querying docker...";
            int tab = _tab;
            Task.Run(delegate
            {
                string err;
                if (tab == 0)
                {
                    var items = ContainerService.ListContainers(out err);
                    Dispatcher.BeginInvoke(new Action(delegate { RenderContainers(items, err); }));
                }
                else
                {
                    var imgs = ContainerService.ListImages(out err);
                    Dispatcher.BeginInvoke(new Action(delegate { RenderImages(imgs, err); }));
                }
            });
        }

        void RenderContainers(List<DockerContainerInfo> items, string err)
        {
            var t = Theme.Current;
            _listPanel.Children.Clear();
            _statusLbl.Text = string.IsNullOrEmpty(err) ? (items.Count + " container(s)") : err;
            for (int i = 0; i < items.Count; i++)
            {
                var c = items[i];
                var btns = V.H(4,
                    StudioUi.PillButton(c.IsRunning ? "Stop" : "Start", c.IsRunning ? "stop.fill" : "play.fill", true, delegate { RunAction(c.IsRunning ? "stop" : "start", c.Id); }),
                    StudioUi.PillButton("Restart", "arrow.clockwise", false, delegate { RunAction("restart", c.Id); }),
                    StudioUi.PillButton("Logs", "terminal", false, delegate { ShowLogs(c.Id, c.Name); }),
                    StudioUi.PillButton("Rm", "trash", false, delegate { RunAction("rm", c.Id); }));
                var card = V.Box(
                    V.H(8,
                        V.Dot(9, c.IsRunning ? t.SysGreen : t.SysGray),
                        V.Flex(V.VLead(2,
                            V.T(c.Name + " (" + c.Id + ")", 12, FontWeights.SemiBold, t.Primary),
                            V.Mono(c.Image + " · " + c.Status, 10.5, FontWeights.Normal, t.Secondary))),
                        btns),
                    V.P(10, 7), t.ElevatedBackground, 6, t.Separator, 1);
                card.Margin = new Thickness(0, 0, 0, 6);
                _listPanel.Children.Add(card);
            }
        }

        void RenderImages(List<DockerImageInfo> imgs, string err)
        {
            var t = Theme.Current;
            _listPanel.Children.Clear();
            _statusLbl.Text = string.IsNullOrEmpty(err) ? (imgs.Count + " image(s)") : err;
            for (int i = 0; i < imgs.Count; i++)
            {
                var im = imgs[i];
                var card = V.Box(
                    V.H(8,
                        Sym.Icon("cube.fill", 14, t.Accent),
                        V.Flex(V.VLead(2,
                            V.T(im.Repository + ":" + im.Tag, 12, FontWeights.SemiBold, t.Primary),
                            V.Mono(im.Id + " · " + im.Size, 10.5, FontWeights.Normal, t.Secondary)))),
                    V.P(10, 7), t.ElevatedBackground, 6, t.Separator, 1);
                card.Margin = new Thickness(0, 0, 0, 6);
                _listPanel.Children.Add(card);
            }
        }

        void RunAction(string act, string id)
        {
            _statusLbl.Text = "docker " + act + " " + id + "...";
            Task.Run(delegate
            {
                var r = ContainerService.ContainerAction(act, id);
                Dispatcher.BeginInvoke(new Action(delegate
                {
                    _logsBox.Text = r.Combined;
                    Refresh();
                }));
            });
        }

        void ShowLogs(string id, string name)
        {
            _logsBox.Text = "Fetching logs for " + name + "...";
            Task.Run(delegate
            {
                var r = ContainerService.GetLogs(id, 200);
                Dispatcher.BeginInvoke(new Action(delegate { _logsBox.Text = r.Combined; }));
            });
        }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 8. CI/CD PIPELINES VIEW (.github/workflows/*.yml + Local Runner + gh run list)
    // ═════════════════════════════════════════════════════════════════════════════

    public class CiStep
    {
        public string Name = "";
        public string Uses = "";
        public string Run = "";
        public string Shell = "";
    }

    public class CiJob
    {
        public string Id = "";
        public string Name = "";
        public string RunsOn = "";
        public List<CiStep> Steps = new List<CiStep>();
    }

    public class CiWorkflow
    {
        public string FilePath = "";
        public string FileName = "";
        public string Name = "";
        public string Triggers = "";
        public List<CiJob> Jobs = new List<CiJob>();
    }

    public class GhRunInfo
    {
        public string DatabaseId = "";
        public string Title = "";
        public string Status = "";
        public string Conclusion = "";
        public string Branch = "";
        public string CreatedAt = "";
    }

    public static class CiCdService
    {
        public static List<CiWorkflow> ScanWorkspace(string workspaceDir)
        {
            var list = new List<CiWorkflow>();
            if (string.IsNullOrEmpty(workspaceDir)) return list;
            string wfDir = Path.Combine(Path.Combine(workspaceDir, ".github"), "workflows");
            if (!Directory.Exists(wfDir)) return list;
            var files = Directory.GetFiles(wfDir, "*.yml").Concat(Directory.GetFiles(wfDir, "*.yaml")).OrderBy(f => f).ToArray();
            for (int i = 0; i < files.Length; i++)
            {
                try { list.Add(ParseWorkflowYaml(files[i], File.ReadAllText(files[i], Encoding.UTF8))); }
                catch { }
            }
            return list;
        }

        public static CiWorkflow ParseWorkflowYaml(string filePath, string yaml)
        {
            var wf = new CiWorkflow
            {
                FilePath = filePath ?? "",
                FileName = string.IsNullOrEmpty(filePath) ? "workflow.yml" : Path.GetFileName(filePath),
                Name = string.IsNullOrEmpty(filePath) ? "Workflow" : Path.GetFileNameWithoutExtension(filePath)
            };
            if (string.IsNullOrWhiteSpace(yaml)) return wf;
            string[] lines = yaml.Replace("\r\n", "\n").Split('\n');
            bool inJobs = false, inSteps = false, inRunBlock = false;
            int jobsIndent = -1, jobIndent = -1, stepIndent = -1, runBlockIndent = -1;
            CiJob curJob = null;
            CiStep curStep = null;
            var runSb = new StringBuilder();

            Action flushRun = delegate
            {
                if (inRunBlock && curStep != null)
                {
                    curStep.Run = runSb.ToString().TrimEnd('\r', '\n');
                }
                inRunBlock = false;
                runBlockIndent = -1;
                runSb.Clear();
            };

            for (int i = 0; i < lines.Length; i++)
            {
                string raw = lines[i];
                string trimmed = raw.Trim();
                int indent = 0;
                while (indent < raw.Length && raw[indent] == ' ') indent++;

                if (inRunBlock)
                {
                    if (trimmed.Length == 0) { runSb.AppendLine(""); continue; }
                    if (runBlockIndent < 0) runBlockIndent = indent;
                    if (indent >= runBlockIndent)
                    {
                        runSb.AppendLine(raw.Length >= runBlockIndent ? raw.Substring(runBlockIndent) : trimmed);
                        continue;
                    }
                    flushRun();
                }

                if (trimmed.Length == 0 || trimmed.StartsWith("#")) continue;

                if (indent == 0)
                {
                    inJobs = false; inSteps = false; curJob = null; curStep = null;
                    if (trimmed.StartsWith("name:"))
                    {
                        wf.Name = StripQuotes(trimmed.Substring(5).Trim());
                    }
                    else if (trimmed.StartsWith("on:"))
                    {
                        string onVal = trimmed.Substring(3).Trim();
                        if (!string.IsNullOrEmpty(onVal)) wf.Triggers = onVal;
                    }
                    else if (trimmed.StartsWith("jobs:"))
                    {
                        inJobs = true;
                        jobsIndent = indent;
                    }
                    continue;
                }

                if (!inJobs) continue;

                if (!inSteps && indent > jobsIndent && trimmed.EndsWith(":") && !trimmed.StartsWith("-"))
                {
                    if (jobIndent < 0 || indent <= jobIndent)
                    {
                        jobIndent = indent;
                        string jid = trimmed.Substring(0, trimmed.Length - 1).Trim();
                        curJob = new CiJob { Id = jid, Name = jid };
                        wf.Jobs.Add(curJob);
                        curStep = null;
                        inSteps = false;
                        continue;
                    }
                }

                if (curJob != null && indent > jobIndent)
                {
                    if (inSteps && indent <= stepIndent && !trimmed.StartsWith("-"))
                    {
                        // Left steps block back into job properties or next job
                        if (indent == jobIndent && trimmed.EndsWith(":"))
                        {
                            inSteps = false;
                            string jid = trimmed.Substring(0, trimmed.Length - 1).Trim();
                            curJob = new CiJob { Id = jid, Name = jid };
                            wf.Jobs.Add(curJob);
                            curStep = null;
                            continue;
                        }
                        inSteps = false;
                    }

                    if (!inSteps)
                    {
                        if (trimmed.StartsWith("name:")) curJob.Name = StripQuotes(trimmed.Substring(5).Trim());
                        else if (trimmed.StartsWith("runs-on:")) curJob.RunsOn = StripQuotes(trimmed.Substring(8).Trim());
                        else if (trimmed.StartsWith("steps:")) { inSteps = true; stepIndent = indent; }
                        continue;
                    }

                    if (trimmed.StartsWith("-"))
                    {
                        curStep = new CiStep();
                        curJob.Steps.Add(curStep);
                        string afterDash = trimmed.Substring(1).Trim();
                        if (afterDash.Length > 0) ParseStepField(afterDash, curStep, ref inRunBlock, runSb);
                    }
                    else if (curStep != null)
                    {
                        ParseStepField(trimmed, curStep, ref inRunBlock, runSb);
                    }
                }
            }
            flushRun();
            return wf;
        }

        static void ParseStepField(string kv, CiStep step, ref bool inRunBlock, StringBuilder runSb)
        {
            if (kv.StartsWith("name:")) step.Name = StripQuotes(kv.Substring(5).Trim());
            else if (kv.StartsWith("uses:")) step.Uses = StripQuotes(kv.Substring(5).Trim());
            else if (kv.StartsWith("shell:")) step.Shell = StripQuotes(kv.Substring(6).Trim());
            else if (kv.StartsWith("run:"))
            {
                string val = kv.Substring(4).Trim();
                if (val == "|" || val == "|-" || val == ">" || val == ">-")
                {
                    inRunBlock = true;
                    runSb.Clear();
                }
                else
                {
                    step.Run = StripQuotes(val);
                }
            }
        }

        static string StripQuotes(string s)
        {
            if (s.Length >= 2 && ((s[0] == '"' && s[s.Length - 1] == '"') || (s[0] == '\'' && s[s.Length - 1] == '\'')))
                return s.Substring(1, s.Length - 2);
            return s;
        }

        public static StudioExecResult ExecuteStep(CiStep step, string workDir, Action<string> onLine)
        {
            if (step == null || string.IsNullOrWhiteSpace(step.Run))
                return new StudioExecResult { ExitCode = 0, StdOut = "(Skipped uses/no-run step: " + (step != null ? step.Uses : "") + ")" };
            if (StudioProcess.IsWindows && (step.Shell == "pwsh" || step.Shell == "powershell"))
                return StudioProcess.Run("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -Command " + StudioProcess.QuoteArg(step.Run), workDir, 60000, onLine);
            return StudioProcess.RunShell(step.Run, workDir, 60000, onLine);
        }

        public static List<GhRunInfo> ParseGhRunListJson(string json)
        {
            var list = new List<GhRunInfo>();
            var arr = DJ.S.DeserializeObject(json) as object[];
            if (arr == null) return list;
            for (int i = 0; i < arr.Length; i++)
            {
                var o = arr[i] as Dictionary<string, object>;
                if (o == null) continue;
                list.Add(new GhRunInfo
                {
                    DatabaseId = DJ.Str(o, "databaseId") ?? "",
                    Title = DJ.Str(o, "displayTitle") ?? "",
                    Status = DJ.Str(o, "status") ?? "",
                    Conclusion = DJ.Str(o, "conclusion") ?? "",
                    Branch = DJ.Str(o, "headBranch") ?? "",
                    CreatedAt = DJ.Str(o, "createdAt") ?? ""
                });
            }
            return list;
        }

        public static List<GhRunInfo> FetchGhRuns(string workDir, out string error)
        {
            error = "";
            string gh = StudioProcess.FindExecutable("gh");
            if (gh == null) { error = "GitHub CLI (gh) not found on PATH."; return new List<GhRunInfo>(); }
            var r = StudioProcess.Run(gh, "run list --limit 15 --json databaseId,displayTitle,status,conclusion,headBranch,createdAt", workDir, 15000, null);
            if (!r.Ok) { error = r.Combined; return new List<GhRunInfo>(); }
            return ParseGhRunListJson(r.StdOut);
        }
    }

    public class CiCdPipelineView : Grid
    {
        readonly AppState _app;
        int _tab;
        List<CiWorkflow> _workflows = new List<CiWorkflow>();
        CiJob _selectedJob;
        readonly Border _header = new Border();
        readonly StackPanel _leftPanel = new StackPanel(), _stepsPanel = new StackPanel();
        TextBox _consoleBox;

        public CiCdPipelineView() : this(AppState.Shared) { }
        public CiCdPipelineView(AppState app)
        {
            _app = app ?? AppState.Shared;
            var t = Theme.Current;
            Background = t.EditorBackground;
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            Children.Add(_header);

            var split = new Grid();
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(280) });
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Grid.SetRow(split, 1);
            Children.Add(split);

            split.Children.Add(StudioUi.Scroller(V.Box(_leftPanel, V.P(10), t.PanelBackground, 0)));
            var sep = V.Line(t.Separator, false);
            Grid.SetColumn(sep, 1);
            split.Children.Add(sep);

            var right = new Grid();
            right.RowDefinitions.Add(new RowDefinition { Height = new GridLength(0.5, GridUnitType.Star) });
            right.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1) });
            right.RowDefinitions.Add(new RowDefinition { Height = new GridLength(0.5, GridUnitType.Star) });
            right.Children.Add(StudioUi.Scroller(V.Box(_stepsPanel, V.P(12), Brushes.Transparent, 0)));
            var rSep = V.Line(t.Separator, true);
            Grid.SetRow(rSep, 1);
            right.Children.Add(rSep);
            _consoleBox = StudioUi.MultiLineEditor("", true, true);
            Grid.SetRow(_consoleBox, 2);
            right.Children.Add(_consoleBox);
            Grid.SetColumn(right, 2);
            split.Children.Add(right);

            BuildHeader();
            Rescan();
        }

        void BuildHeader()
        {
            _header.Child = StudioUi.Header("checklist", "CI/CD Pipelines", ".github/workflows Local Runner & GitHub Actions Runs",
                StudioUi.TabBar(new[] { "Workflows", "gh run list" }, _tab, delegate(int idx)
                {
                    _tab = idx;
                    BuildHeader();
                    if (_tab == 1) LoadGhRuns(); else RenderLeft();
                }),
                StudioUi.PillButton("Scan", "arrow.clockwise", false, Rescan));
        }

        void Rescan()
        {
            _workflows = CiCdService.ScanWorkspace(_app.WorkspaceFolder);
            if (_workflows.Count > 0 && _workflows[0].Jobs.Count > 0 && _selectedJob == null)
                _selectedJob = _workflows[0].Jobs[0];
            RenderLeft();
            RenderJobSteps();
        }

        void RenderLeft()
        {
            var t = Theme.Current;
            _leftPanel.Children.Clear();
            if (_workflows.Count == 0)
            {
                _leftPanel.Children.Add(V.T("No .github/workflows/*.yml files found in workspace.", 11.5, FontWeights.Normal, t.Secondary));
                return;
            }
            for (int w = 0; w < _workflows.Count; w++)
            {
                var wf = _workflows[w];
                _leftPanel.Children.Add(V.T(wf.Name + " (" + wf.FileName + ")", 11.5, FontWeights.SemiBold, t.Secondary));
                for (int j = 0; j < wf.Jobs.Count; j++)
                {
                    var job = wf.Jobs[j];
                    bool sel = _selectedJob == job;
                    var btn = V.Button(V.Box(
                        V.VLead(1,
                            V.T(job.Name, 12, FontWeights.SemiBold, sel ? Brushes.White : t.Primary),
                            V.T(job.Steps.Count + " steps · " + (string.IsNullOrEmpty(job.RunsOn) ? "local" : job.RunsOn), 10, FontWeights.Normal, sel ? Brushes.White : t.Secondary)),
                        V.P(8, 6), sel ? t.Accent : t.ElevatedBackground, 6), delegate
                    {
                        _selectedJob = job;
                        RenderLeft();
                        RenderJobSteps();
                    });
                    btn.Margin = new Thickness(0, 4, 0, 4);
                    _leftPanel.Children.Add(btn);
                }
            }
        }

        void RenderJobSteps()
        {
            var t = Theme.Current;
            _stepsPanel.Children.Clear();
            if (_selectedJob == null) return;
            var job = _selectedJob;
            _stepsPanel.Children.Add(V.H(8,
                V.T("Job: " + job.Name, 13, FontWeights.SemiBold, t.Primary),
                V.Sp(),
                StudioUi.PillButton("Run Job Locally", "play.fill", true, delegate { RunJob(job); })));
            for (int i = 0; i < job.Steps.Count; i++)
            {
                var st = job.Steps[i];
                var card = V.Box(
                    V.H(8,
                        V.Flex(V.VLead(2,
                            V.T((i + 1) + ". " + (string.IsNullOrEmpty(st.Name) ? (string.IsNullOrEmpty(st.Uses) ? "Run script" : st.Uses) : st.Name), 12, FontWeights.SemiBold, t.Primary),
                            V.Mono(string.IsNullOrEmpty(st.Run) ? ("uses: " + st.Uses) : st.Run, 10.5, FontWeights.Normal, t.Secondary))),
                        string.IsNullOrEmpty(st.Run) ? null : StudioUi.PillButton("Run Step", "play", false, delegate { RunSingleStep(st); })),
                    V.P(9, 6), t.ElevatedBackground, 6, t.Separator, 1);
                card.Margin = new Thickness(0, 6, 0, 0);
                _stepsPanel.Children.Add(card);
            }
        }

        void RunSingleStep(CiStep st)
        {
            string wd = _app.WorkspaceFolder ?? Environment.CurrentDirectory;
            _consoleBox.AppendText("\n=== Step: " + st.Name + " ===\n");
            Task.Run(delegate
            {
                var r = CiCdService.ExecuteStep(st, wd, delegate(string l)
                {
                    Dispatcher.BeginInvoke(new Action(delegate { _consoleBox.AppendText(l + "\n"); _consoleBox.ScrollToEnd(); }));
                });
                Dispatcher.BeginInvoke(new Action(delegate { _consoleBox.AppendText("[Exit " + r.ExitCode + " in " + r.ElapsedMs + " ms]\n"); }));
            });
        }

        void RunJob(CiJob job)
        {
            string wd = _app.WorkspaceFolder ?? Environment.CurrentDirectory;
            _consoleBox.Text = "=== Running Job: " + job.Name + " ===\n";
            Task.Run(delegate
            {
                for (int i = 0; i < job.Steps.Count; i++)
                {
                    var st = job.Steps[i];
                    Dispatcher.BeginInvoke(new Action(delegate { _consoleBox.AppendText("\n-- Step " + (i + 1) + ": " + st.Name + " --\n"); }));
                    var r = CiCdService.ExecuteStep(st, wd, delegate(string l)
                    {
                        Dispatcher.BeginInvoke(new Action(delegate { _consoleBox.AppendText(l + "\n"); _consoleBox.ScrollToEnd(); }));
                    });
                    if (!r.Ok)
                    {
                        Dispatcher.BeginInvoke(new Action(delegate { _consoleBox.AppendText("[Step failed exit=" + r.ExitCode + "]\n"); }));
                        break;
                    }
                }
            });
        }

        void LoadGhRuns()
        {
            string wd = _app.WorkspaceFolder ?? Environment.CurrentDirectory;
            _stepsPanel.Children.Clear();
            _stepsPanel.Children.Add(V.T("Loading GitHub Actions runs via gh CLI...", 12, FontWeights.Normal, Theme.Current.Secondary));
            Task.Run(delegate
            {
                string err;
                var runs = CiCdService.FetchGhRuns(wd, out err);
                Dispatcher.BeginInvoke(new Action(delegate
                {
                    var t = Theme.Current;
                    _stepsPanel.Children.Clear();
                    if (!string.IsNullOrEmpty(err))
                    {
                        _stepsPanel.Children.Add(V.T(err, 12, FontWeights.Normal, t.SysRed));
                        return;
                    }
                    for (int i = 0; i < runs.Count; i++)
                    {
                        var r = runs[i];
                        bool ok = string.Equals(r.Conclusion, "success", StringComparison.OrdinalIgnoreCase);
                        var card = V.Box(
                            V.H(8,
                                V.Dot(8, ok ? t.SysGreen : (string.IsNullOrEmpty(r.Conclusion) ? t.SysYellow : t.SysRed)),
                                V.Flex(V.VLead(2,
                                    V.T(r.Title, 12, FontWeights.SemiBold, t.Primary),
                                    V.Mono("#" + r.DatabaseId + " · " + r.Branch + " · " + r.Status + "/" + r.Conclusion, 10.5, FontWeights.Normal, t.Secondary)))),
                            V.P(9, 6), t.ElevatedBackground, 6, t.Separator, 1);
                        card.Margin = new Thickness(0, 0, 0, 6);
                        _stepsPanel.Children.Add(card);
                    }
                }));
            });
        }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 9. CLOUD GPU HUB (Dotmini Cloud GPU + RunPod/Vast.ai + Git Ingest + SSH)
    // ═════════════════════════════════════════════════════════════════════════════

    public class CloudGpuType
    {
        public string Id = "";
        public string Label = "";
        public int VramGB;
        public int PricePerMinute; // minor units (satang)
        public bool Available = true;
        public string PricePerHourText
        {
            get { return "฿" + (PricePerMinute * 60.0 / 100.0).ToString("0.00", CultureInfo.InvariantCulture) + "/hr"; }
        }
        public string PricePerMinText
        {
            get { return "฿" + (PricePerMinute / 100.0).ToString("0.00", CultureInfo.InvariantCulture) + "/min"; }
        }
    }

    public class CloudGpuSession
    {
        public string SessionId = "";
        public string WssUrl = "";
        public string JupyterToken = "";
        public string GpuLabel = "";
        public int PricePerMinute;
        public string Status = "idle";
        public int ElapsedSeconds;
        public int CostSoFar;
    }

    public class ByoGpuInstance
    {
        public string Provider = "";
        public string Id = "";
        public string Label = "";
        public string GpuName = "";
        public string Status = "";
        public string SshHost = "";
        public int SshPort = 22;
        public string User = "root";
        public double CostPerHourUsd;
        public bool Running;
    }

    public static class CloudGpuService
    {
        public const string DefaultCatalogEndpoint = "https://microcode.dotmini.net/v1/gpu/catalog";

        public static List<CloudGpuType> DefaultCatalog
        {
            get
            {
                return new List<CloudGpuType>
                {
                    new CloudGpuType { Id = "rtx4090", Label = "NVIDIA RTX 4090 24GB", VramGB = 24, PricePerMinute = 48, Available = true },
                    new CloudGpuType { Id = "l40s", Label = "NVIDIA L40S 48GB", VramGB = 48, PricePerMinute = 98, Available = true },
                    new CloudGpuType { Id = "a100", Label = "NVIDIA A100 SXM4 80GB", VramGB = 80, PricePerMinute = 152, Available = true },
                    new CloudGpuType { Id = "h100", Label = "NVIDIA H100 SXM 80GB", VramGB = 80, PricePerMinute = 263, Available = true }
                };
            }
        }

        public static string BaseUrl
        {
            get
            {
                string cfg = (Defaults.Str("cloudGPUBaseURL", "") ?? "").Trim().TrimEnd('/');
                return string.IsNullOrEmpty(cfg) ? "https://microcode.dotmini.net/v1/gpu" : cfg;
            }
        }

        public static string FormatMoney(int minorUnits, string currency)
        {
            string sym = string.Equals(currency, "USD", StringComparison.OrdinalIgnoreCase) ? "$" : "฿";
            return sym + (minorUnits / 100.0).ToString("0.00", CultureInfo.InvariantCulture);
        }

        public static int EstimateSessionMinutes(int balanceSatang, int pricePerMinute)
        {
            if (balanceSatang <= 0 || pricePerMinute <= 0) return 0;
            return balanceSatang / pricePerMinute;
        }

        public static int EstimateCostSatang(int elapsedSeconds, int pricePerMinute)
        {
            if (elapsedSeconds <= 0 || pricePerMinute <= 0) return 0;
            return (int)Math.Ceiling((elapsedSeconds / 60.0) * pricePerMinute);
        }

        public static bool ExceedsBudget(int costSatang, int maxBudgetThb)
        {
            if (maxBudgetThb <= 0) return false;
            return costSatang >= maxBudgetThb * 100;
        }

        public static List<CloudGpuType> ParseCatalogJson(string json)
        {
            var list = new List<CloudGpuType>();
            var o = DJ.Obj(json);
            var arr = DJ.Arr(o, "gpus");
            if (arr == null) return list;
            for (int i = 0; i < arr.Count; i++)
            {
                var g = arr[i] as Dictionary<string, object>;
                if (g == null) continue;
                double? vram = DJ.Num(g, "vramGB");
                double? ppm = DJ.Num(g, "pricePerMinute");
                object availObj;
                bool avail = !g.TryGetValue("available", out availObj) || !(availObj is bool) || (bool)availObj;
                list.Add(new CloudGpuType
                {
                    Id = DJ.Str(g, "id") ?? "",
                    Label = DJ.Str(g, "label") ?? DJ.Str(g, "id") ?? "GPU",
                    VramGB = vram.HasValue ? (int)vram.Value : 0,
                    PricePerMinute = ppm.HasValue ? (int)ppm.Value : 0,
                    Available = avail
                });
            }
            return list;
        }

        static HttpRequestMessage AuthReq(HttpMethod m, string url, object body)
        {
            var r = new HttpRequestMessage(m, url);
            var sess = DotminiAuth.Session;
            if (sess != null && !string.IsNullOrEmpty(sess.AccessToken))
                r.Headers.TryAddWithoutValidation("Authorization", "Bearer " + sess.AccessToken);
            if (body != null) r.Content = DJ.Body(body);
            return r;
        }

        public static async Task<List<CloudGpuType>> FetchCatalogAsync()
        {
            try
            {
                var resp = await DotminiNet.Http.SendAsync(AuthReq(HttpMethod.Get, BaseUrl + "/catalog", null));
                if (resp.IsSuccessStatusCode)
                {
                    string json = await resp.Content.ReadAsStringAsync();
                    var parsed = ParseCatalogJson(json);
                    if (parsed.Count > 0) return parsed;
                }
            }
            catch { }
            return DefaultCatalog;
        }

        public static async Task<Tuple<int, string>> FetchWalletAsync()
        {
            try
            {
                var resp = await DotminiNet.Http.SendAsync(AuthReq(HttpMethod.Get, BaseUrl + "/wallet", null));
                if (resp.IsSuccessStatusCode)
                {
                    var o = DJ.Obj(await resp.Content.ReadAsStringAsync());
                    double? bal = DJ.Num(o, "balance");
                    string cur = DJ.Str(o, "currency") ?? "THB";
                    int minor = bal.HasValue ? (int)bal.Value : 0;
                    Defaults.Set("gpuWalletBalanceSatang", minor);
                    return Tuple.Create(minor, cur);
                }
            }
            catch { }
            return Tuple.Create((int)Defaults.Num("gpuWalletBalanceSatang", 0), "THB");
        }

        public static async Task<Tuple<CloudGpuSession, string>> StartSessionAsync(string gpuId)
        {
            try
            {
                var resp = await DotminiNet.Http.SendAsync(AuthReq(HttpMethod.Post, BaseUrl + "/sessions", new Dictionary<string, object> { { "gpuId", gpuId } }));
                string body = await resp.Content.ReadAsStringAsync();
                if (!resp.IsSuccessStatusCode)
                    return Tuple.Create((CloudGpuSession)null, DJ.ErrorText(body));
                var o = DJ.Obj(body);
                var s = new CloudGpuSession
                {
                    SessionId = DJ.Str(o, "sessionId") ?? DJ.Str(o, "session_id") ?? "",
                    WssUrl = DJ.Str(o, "wssURL") ?? DJ.Str(o, "wssUrl") ?? DJ.Str(o, "endpoint") ?? "",
                    JupyterToken = DJ.Str(o, "jupyterToken") ?? DJ.Str(o, "jupyter_token") ?? DJ.Str(o, "token") ?? "",
                    GpuLabel = DJ.Str(o, "gpuLabel") ?? DJ.Str(o, "gpu_label") ?? gpuId,
                    PricePerMinute = (int)(DJ.Num(o, "pricePerMinute") ?? DJ.Num(o, "price_per_minute") ?? 0),
                    Status = "running"
                };
                return Tuple.Create(s, "");
            }
            catch (Exception ex) { return Tuple.Create((CloudGpuSession)null, ex.Message); }
        }

        public static async Task<bool> StopSessionAsync(string sessionId)
        {
            if (string.IsNullOrEmpty(sessionId)) return false;
            try
            {
                var resp = await DotminiNet.Http.SendAsync(AuthReq(HttpMethod.Delete, BaseUrl + "/sessions/" + Uri.EscapeDataString(sessionId), null));
                return resp.IsSuccessStatusCode;
            }
            catch { return false; }
        }

        public static List<ByoGpuInstance> ParseRunPodJson(string json)
        {
            var list = new List<ByoGpuInstance>();
            var root = DJ.Obj(json);
            var data = DJ.Child(root, "data");
            var myself = DJ.Child(data, "myself");
            var pods = DJ.Arr(myself, "pods");
            if (pods == null) return list;
            for (int i = 0; i < pods.Count; i++)
            {
                var p = pods[i] as Dictionary<string, object>;
                if (p == null) continue;
                string id = DJ.Str(p, "id") ?? "";
                string name = DJ.Str(p, "name") ?? "pod";
                string status = (DJ.Str(p, "desiredStatus") ?? "UNKNOWN").ToUpperInvariant();
                var machine = DJ.Child(p, "machine");
                string gpu = DJ.Str(machine, "gpuDisplayName") ?? "GPU";
                double cost = DJ.Num(p, "costPerHr") ?? 0.0;
                string sshHost = "";
                int sshPort = 22;
                var rt = DJ.Child(p, "runtime");
                var ports = DJ.Arr(rt, "ports");
                if (ports != null)
                {
                    for (int k = 0; k < ports.Count; k++)
                    {
                        var po = ports[k] as Dictionary<string, object>;
                        if (po == null) continue;
                        if ((int)(DJ.Num(po, "privatePort") ?? 0) == 22 && string.Equals(DJ.Str(po, "type"), "tcp", StringComparison.OrdinalIgnoreCase))
                        {
                            sshHost = DJ.Str(po, "ip") ?? "";
                            sshPort = (int)(DJ.Num(po, "publicPort") ?? 22);
                            break;
                        }
                    }
                }
                list.Add(new ByoGpuInstance
                {
                    Provider = "RunPod",
                    Id = id,
                    Label = gpu + " · " + name + " · " + status,
                    GpuName = gpu,
                    Status = status,
                    SshHost = sshHost,
                    SshPort = sshPort,
                    User = "root",
                    CostPerHourUsd = cost,
                    Running = status == "RUNNING"
                });
            }
            return list;
        }

        public static async Task<Tuple<List<ByoGpuInstance>, string>> FetchRunPodAsync(string apiKey)
        {
            if (string.IsNullOrWhiteSpace(apiKey))
                return Tuple.Create(new List<ByoGpuInstance>(), "Enter RunPod API key.");
            try
            {
                var req = new HttpRequestMessage(HttpMethod.Post, "https://api.runpod.io/graphql");
                req.Headers.TryAddWithoutValidation("Authorization", "Bearer " + apiKey.Trim());
                req.Content = DJ.Body(new Dictionary<string, object>
                {
                    { "query", "query{myself{pods{id name desiredStatus costPerHr machine{gpuDisplayName} runtime{ports{ip isIpPublic privatePort publicPort type}}}}}" }
                });
                var resp = await DotminiNet.Http.SendAsync(req);
                string body = await resp.Content.ReadAsStringAsync();
                if (!resp.IsSuccessStatusCode) return Tuple.Create(new List<ByoGpuInstance>(), "HTTP " + (int)resp.StatusCode + ": " + DJ.ErrorText(body));
                return Tuple.Create(ParseRunPodJson(body), "");
            }
            catch (Exception ex) { return Tuple.Create(new List<ByoGpuInstance>(), ex.Message); }
        }

        public static List<ByoGpuInstance> ParseVastJson(string json)
        {
            var list = new List<ByoGpuInstance>();
            var root = DJ.Obj(json);
            var arr = DJ.Arr(root, "instances");
            if (arr == null) return list;
            for (int i = 0; i < arr.Count; i++)
            {
                var inst = arr[i] as Dictionary<string, object>;
                if (inst == null) continue;
                string id = DJ.Str(inst, "id") ?? "";
                string gpu = DJ.Str(inst, "gpu_name") ?? "GPU";
                string status = (DJ.Str(inst, "actual_status") ?? DJ.Str(inst, "cur_state") ?? "unknown").ToUpperInvariant();
                string host = DJ.Str(inst, "ssh_host") ?? "";
                int port = (int)(DJ.Num(inst, "ssh_port") ?? 22);
                double dph = DJ.Num(inst, "dph_total") ?? 0.0;
                list.Add(new ByoGpuInstance
                {
                    Provider = "Vast.ai",
                    Id = id,
                    Label = gpu + " · #" + id + " · " + status,
                    GpuName = gpu,
                    Status = status,
                    SshHost = host,
                    SshPort = port,
                    User = "root",
                    CostPerHourUsd = dph,
                    Running = status == "RUNNING"
                });
            }
            return list;
        }

        public static async Task<Tuple<List<ByoGpuInstance>, string>> FetchVastAsync(string apiKey)
        {
            if (string.IsNullOrWhiteSpace(apiKey))
                return Tuple.Create(new List<ByoGpuInstance>(), "Enter Vast.ai API key.");
            try
            {
                var req = new HttpRequestMessage(HttpMethod.Get, "https://console.vast.ai/api/v0/instances/?owner=me");
                req.Headers.TryAddWithoutValidation("Authorization", "Bearer " + apiKey.Trim());
                var resp = await DotminiNet.Http.SendAsync(req);
                string body = await resp.Content.ReadAsStringAsync();
                if (!resp.IsSuccessStatusCode) return Tuple.Create(new List<ByoGpuInstance>(), "HTTP " + (int)resp.StatusCode + ": " + DJ.ErrorText(body));
                return Tuple.Create(ParseVastJson(body), "");
            }
            catch (Exception ex) { return Tuple.Create(new List<ByoGpuInstance>(), ex.Message); }
        }

        public static string BuildGpuSshCommand(string user, string host, int port, int localJupyterPort, int remoteJupyterPort)
        {
            string u = string.IsNullOrWhiteSpace(user) ? "root" : user.Trim();
            string h = (host ?? "").Trim();
            int p = port > 0 ? port : 22;
            string tunnel = (localJupyterPort > 0 && remoteJupyterPort > 0)
                ? (" -L " + localJupyterPort + ":localhost:" + remoteJupyterPort)
                : "";
            return "ssh " + u + "@" + h + " -p " + p + tunnel;
        }
    }

    public class CloudGpuHubView : Grid
    {
        readonly AppState _app;
        int _tab;
        List<CloudGpuType> _catalog = CloudGpuService.DefaultCatalog;
        int _walletSatang;
        string _currency = "THB";
        CloudGpuSession _session;
        string _byoProvider = "RunPod";
        List<ByoGpuInstance> _byoInstances = new List<ByoGpuInstance>();
        readonly Border _header = new Border(), _body = new Border();
        readonly TextBlock _walletLbl;
        TextBox _byoKeyBox, _gitUrlBox, _gitOutBox, _sshHostBox, _sshUserBox, _sshPortBox, _sshOutBox;

        public CloudGpuHubView() : this(AppState.Shared) { }
        public CloudGpuHubView(AppState app)
        {
            _app = app ?? AppState.Shared;
            var t = Theme.Current;
            Background = t.EditorBackground;
            _walletSatang = (int)Defaults.Num("gpuWalletBalanceSatang", 0);
            _walletLbl = V.T("Wallet: " + CloudGpuService.FormatMoney(_walletSatang, _currency), 12, FontWeights.SemiBold, t.SysGreen);

            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            Children.Add(_header);
            Grid.SetRow(_body, 1);
            Children.Add(_body);

            BuildHeader();
            RenderTab();
            RefreshCloud();
        }

        void BuildHeader()
        {
            _header.Child = StudioUi.Header("bolt.fill", "Cloud GPU Hub", "Dotmini Managed GPUs, RunPod / Vast.ai BYO, Git Ingest & SSH",
                _walletLbl,
                StudioUi.TabBar(new[] { "Dotmini Cloud", "BYO GPU", "Git Ingest", "SSH Custom" }, _tab, delegate(int idx)
                {
                    _tab = idx;
                    BuildHeader();
                    RenderTab();
                }),
                StudioUi.PillButton("Refresh", "arrow.clockwise", false, RefreshCloud));
        }

        async void RefreshCloud()
        {
            _catalog = await CloudGpuService.FetchCatalogAsync();
            var w = await CloudGpuService.FetchWalletAsync();
            _walletSatang = w.Item1;
            _currency = w.Item2;
            _walletLbl.Text = "Wallet: " + CloudGpuService.FormatMoney(_walletSatang, _currency);
            if (_tab == 0) RenderTab();
        }

        void RenderTab()
        {
            if (_tab == 0) RenderDotminiTab();
            else if (_tab == 1) RenderByoTab();
            else if (_tab == 2) RenderGitIngestTab();
            else RenderSshCustomTab();
        }

        void RenderDotminiTab()
        {
            var t = Theme.Current;
            var col = new StackPanel { Margin = V.P(14) };

            if (_session != null)
            {
                var sessCard = V.Box(
                    V.H(8,
                        V.Dot(10, t.SysGreen),
                        V.Flex(V.VLead(2,
                            V.T("Active Session: " + _session.GpuLabel + " (" + _session.SessionId + ")", 12.5, FontWeights.SemiBold, t.Primary),
                            V.Mono("Endpoint: " + _session.WssUrl, 10.5, FontWeights.Normal, t.Secondary))),
                        StudioUi.PillButton("Stop Session", "stop.fill", true, async delegate
                        {
                            await CloudGpuService.StopSessionAsync(_session.SessionId);
                            _session = null;
                            RenderDotminiTab();
                        })),
                    V.P(12, 10), t.Op(t.SysGreen, 0.12), 8, t.SysGreen, 1);
                sessCard.Margin = new Thickness(0, 0, 0, 12);
                col.Children.Add(sessCard);
            }

            for (int i = 0; i < _catalog.Count; i++)
            {
                var gpu = _catalog[i];
                int estMins = CloudGpuService.EstimateSessionMinutes(_walletSatang, gpu.PricePerMinute);
                var card = V.Box(
                    V.H(10,
                        Sym.Icon("memorychip", 18, t.Accent),
                        V.Flex(V.VLead(2,
                            V.T(gpu.Label, 13, FontWeights.SemiBold, t.Primary),
                            V.T(gpu.VramGB + " GB VRAM · " + gpu.PricePerHourText + " (" + gpu.PricePerMinText + ")" +
                                (estMins > 0 ? (" · ~" + estMins + " min with current wallet") : ""), 11, FontWeights.Normal, t.Secondary))),
                        StudioUi.PillButton(gpu.Available ? "Launch GPU" : "Unavailable", "play.fill", gpu.Available, async delegate
                        {
                            if (!gpu.Available) return;
                            var started = await CloudGpuService.StartSessionAsync(gpu.Id);
                            if (started.Item1 != null)
                            {
                                _session = started.Item1;
                                RenderDotminiTab();
                            }
                            else
                            {
                                _walletLbl.Text = "Launch: " + (string.IsNullOrEmpty(started.Item2) ? "Sign in & top up GPU wallet" : started.Item2);
                            }
                        })),
                    V.P(12, 10), t.ElevatedBackground, 8, t.Separator, 1);
                card.Margin = new Thickness(0, 0, 0, 8);
                col.Children.Add(card);
            }
            _body.Child = StudioUi.Scroller(col);
        }

        void RenderByoTab()
        {
            var t = Theme.Current;
            string savedKey = Dpapi.Unprotect(Defaults.Str("byo_gpu_key_" + _byoProvider, null)) ?? "";
            var keyBorder = StudioUi.InputBox(_byoProvider + " API Key...", _byoKeyBox != null ? _byoKeyBox.Text : savedKey, 260, out _byoKeyBox);
            var listPanel = new StackPanel();
            for (int i = 0; i < _byoInstances.Count; i++)
            {
                var inst = _byoInstances[i];
                var card = V.Box(
                    V.H(8,
                        V.Dot(9, inst.Running ? t.SysGreen : t.SysGray),
                        V.Flex(V.VLead(2,
                            V.T(inst.Label, 12, FontWeights.SemiBold, t.Primary),
                            V.Mono(CloudGpuService.BuildGpuSshCommand(inst.User, inst.SshHost, inst.SshPort, 8888, 8888), 10.5, FontWeights.Normal, t.Secondary)))),
                    V.P(10, 7), t.ElevatedBackground, 6, t.Separator, 1);
                card.Margin = new Thickness(0, 0, 0, 6);
                listPanel.Children.Add(card);
            }

            var col = V.VLead(10,
                V.H(6,
                    StudioUi.PillButton("RunPod", null, _byoProvider == "RunPod", delegate { _byoProvider = "RunPod"; RenderByoTab(); }),
                    StudioUi.PillButton("Vast.ai", null, _byoProvider == "Vast.ai", delegate { _byoProvider = "Vast.ai"; RenderByoTab(); }),
                    V.Flex(keyBorder),
                    StudioUi.PillButton("Fetch Instances", "arrow.clockwise", true, async delegate
                    {
                        string k = _byoKeyBox.Text.Trim();
                        if (!string.IsNullOrEmpty(k)) Defaults.Set("byo_gpu_key_" + _byoProvider, Dpapi.Protect(k));
                        var r = _byoProvider == "RunPod"
                            ? await CloudGpuService.FetchRunPodAsync(k)
                            : await CloudGpuService.FetchVastAsync(k);
                        _byoInstances = r.Item1;
                        if (!string.IsNullOrEmpty(r.Item2)) _walletLbl.Text = r.Item2;
                        RenderByoTab();
                    })),
                listPanel);
            col.Margin = V.P(14);
            _body.Child = StudioUi.Scroller(col);
        }

        void RenderGitIngestTab()
        {
            var urlBorder = StudioUi.InputBox("Git repository URL (https://github.com/owner/repo.git)", _gitUrlBox != null ? _gitUrlBox.Text : "", 300, out _gitUrlBox);
            if (_gitOutBox == null) { _gitOutBox = StudioUi.MultiLineEditor("", true, true); _gitOutBox.Height = 280; }

            var col = V.VLead(10,
                V.H(8, V.Flex(urlBorder),
                    StudioUi.PillButton("Inspect Refs", "magnifyingglass", false, delegate
                    {
                        string u = _gitUrlBox.Text.Trim();
                        _gitOutBox.Text = "Running git ls-remote " + u + "...";
                        Task.Run(delegate
                        {
                            var r = StudioProcess.Run("git", "ls-remote --heads " + StudioProcess.QuoteArg(u), null, 20000, null);
                            Dispatcher.BeginInvoke(new Action(delegate { _gitOutBox.Text = r.Combined; }));
                        });
                    }),
                    StudioUi.PillButton("Clone to Workspace", "arrow.down.circle", true, delegate
                    {
                        string u = _gitUrlBox.Text.Trim();
                        string ws = _app.WorkspaceFolder ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                        _gitOutBox.Text = "Cloning " + u + " into " + ws + "...";
                        Task.Run(delegate
                        {
                            var r = StudioProcess.Run("git", "clone --depth 1 " + StudioProcess.QuoteArg(u), ws, 60000, null);
                            Dispatcher.BeginInvoke(new Action(delegate { _gitOutBox.Text = r.Combined; }));
                        });
                    })),
                _gitOutBox);
            col.Margin = V.P(14);
            _body.Child = StudioUi.Scroller(col);
        }

        void RenderSshCustomTab()
        {
            var hb = StudioUi.InputBox("GPU Host / IP", _sshHostBox != null ? _sshHostBox.Text : "", 200, out _sshHostBox);
            var ub = StudioUi.InputBox("User", _sshUserBox != null ? _sshUserBox.Text : "root", 100, out _sshUserBox);
            var pb = StudioUi.InputBox("Port", _sshPortBox != null ? _sshPortBox.Text : "22", 70, out _sshPortBox);
            if (_sshOutBox == null) { _sshOutBox = StudioUi.MultiLineEditor("", true, true); _sshOutBox.Height = 240; }

            var col = V.VLead(10,
                V.H(8, V.Flex(hb), ub, pb,
                    StudioUi.PillButton("Test nvidia-smi", "play.fill", true, delegate
                    {
                        int pt = 22;
                        int.TryParse(_sshPortBox.Text, out pt);
                        var prof = new SSHConfigProfile { Name = _sshHostBox.Text.Trim(), HostName = _sshHostBox.Text.Trim(), User = _sshUserBox.Text.Trim(), Port = pt > 0 ? pt : 22 };
                        _sshOutBox.Text = "$ " + CloudGpuService.BuildGpuSshCommand(prof.User, prof.HostName, prof.Port, 8888, 8888) + "\nRunning nvidia-smi...\n";
                        Task.Run(delegate
                        {
                            var r = RemoteWorkspaceManager.RunCommand(prof, "nvidia-smi || uname -a", 15000);
                            Dispatcher.BeginInvoke(new Action(delegate { _sshOutBox.AppendText(r.Combined); }));
                        });
                    })),
                _sshOutBox);
            col.Margin = V.P(14);
            _body.Child = StudioUi.Scroller(col);
        }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 10. STUDIO DISPATCH FACTORY
    // ═════════════════════════════════════════════════════════════════════════════

    public static class StudioFactory
    {
        public static UIElement Create(EditorMode mode, AppState app)
        {
            switch (mode)
            {
                case EditorMode.Science: return new ScienceStudioView(app);
                case EditorMode.RemoteX: return new RemoteXStudioView(app);
                case EditorMode.Scenario: return new ScenarioStudioView(app);
                case EditorMode.Embedded: return new EmbeddedStudioView(app);
                case EditorMode.Extensions: return new ExtensionStudioView(app);
                default: return null;
            }
        }

        public static UIElement CreateByName(string name, AppState app)
        {
            switch ((name ?? "").Trim())
            {
                case "Science Mode": return new ScienceStudioView(app);
                case "Remote Explorer": return new RemoteXStudioView(app);
                case "Scenario": return new ScenarioStudioView(app);
                case "Embed & IoT Studio": return new EmbeddedStudioView(app);
                case "Extension Studio": return new ExtensionStudioView(app);
                case "Database Studio": return new DatabaseStudioView(app);
                case "Container Studio": return new ContainerStudioView(app);
                case "CI/CD Pipelines": return new CiCdPipelineView(app);
                case "Cloud GPU Hub": return new CloudGpuHubView(app);
                default: return null;
            }
        }

        public static void ShowWindow(string name, AppState app)
        {
            var t = Theme.Current;
            var view = CreateByName(name, app ?? AppState.Shared) ?? new StudioPlaceholder(name, "square.grid.2x2");
            var w = new Window
            {
                Title = name,
                Width = 1020,
                Height = 680,
                Owner = Application.Current != null ? Application.Current.MainWindow : null,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Background = t.WorkspaceBackground,
                FontFamily = UIFonts.UI,
                Content = view
            };
            w.SourceInitialized += delegate { Native.StyleWindow(w, t.IsDark); };
            w.Show();
        }
    }
}

