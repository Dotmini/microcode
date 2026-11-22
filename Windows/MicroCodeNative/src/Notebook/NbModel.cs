// Cell Mode data model — port of NotebookView.swift (CellLanguage, NotebookCellModel, NotebookModel, DataFile),
// CellModels.swift (CellColorTheme, CustomCellColor, ComputeTarget), SharedMemoryService.swift value types and
// MicFormat.swift / PythonScriptNotebookBridge.swift (.mic, .mcnb, .ipynb and "# %%" .py files).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Media;
using MicroCode.Core;

namespace MicroCode.Views
{
    // ── CellLanguage ─────────────────────────────────────────────────────────
    public class CellLang
    {
        public readonly string Name, Icon, ColorKey, Ext, DefaultContent;
        CellLang(string name, string icon, string color, string ext, string def) { Name = name; Icon = icon; ColorKey = color; Ext = ext; DefaultContent = def; }

        public SolidColorBrush Brush { get { return NbColor.Named(ColorKey); } }

        public static readonly CellLang[] All =
        {
            new CellLang("Python", "p.circle.fill", "blue", "py", "# Your Python code here\nprint('Hello, World!')"),
            new CellLang("R", "r.circle.fill", "purple", "R", "# Your R code here\nprint('Hello, World!')"),
            new CellLang("Julia", "j.circle.fill", "green", "jl", "# Your Julia code here\nprintln(\"Hello, Julia!\")\n\n# Example: Calculate factorial\nfunction factorial(n)\n    n <= 1 ? 1 : n * factorial(n - 1)\nend\n\nprintln(\"5! = \", factorial(5))"),
            new CellLang("SQL", "cylinder.fill", "cyan", "sql", "-- SQL Query\n-- Connect to: sqlite:///path/to/database.db\n\nSELECT * FROM users\nWHERE active = 1\nORDER BY created_at DESC\nLIMIT 10;"),
            new CellLang("Ardium", "sparkles", "purple", "ar", "// ==========================================\n// Ardium Native High-Performance Module\n// ==========================================\n\nlet version = \"v2.3\";\nlet sum = 0;\nlet i = 1;\n\nfn main() {\n    println(\"=========================================\");\n    println(\"      HELLO FROM ARDIUM NOTEBOOK!        \");\n    println(\"=========================================\");\n    print(\"Ardium Native Toolchain: \");\n    println(version);\n\n    while (i < 11) {\n        sum = sum + (i * i);\n        i = i + 1;\n    }\n\n    print(\"Sum of squares (1..10) = \");\n    println(sum);\n    println(\"=========================================\");\n}"),
            new CellLang("Rust", "gearshape.fill", "orange", "rs", "// Rust Code\nfn main() {\n    println!(\"Hello from Rust!\");\n}"),
            new CellLang("Go", "g.circle.fill", "mint", "go", "// Go Code\npackage main\n\nimport \"fmt\"\n\nfunc main() {\n    fmt.Println(\"Hello from Go!\")\n}"),
            new CellLang("C++", "c.circle.fill", "blue", "cpp", "// C++ Code\n#include <iostream>\n#include <vector>\n#include <numeric>\n\nint main() {\n    std::cout << \"Hello, C++!\" << std::endl;\n\n    std::vector<int> numbers = {1, 2, 3, 4, 5};\n    int sum = std::accumulate(numbers.begin(), numbers.end(), 0);\n    std::cout << \"Sum: \" << sum << std::endl;\n\n    return 0;\n}"),
            new CellLang("Objective-C", "apple.logo", "indigo", "m", "// Objective-C Code\n#import <Foundation/Foundation.h>\n\nint main(int argc, const char * argv[]) {\n    @autoreleasepool {\n        NSLog(@\"Hello, Objective-C!\");\n    }\n    return 0;\n}"),
            new CellLang("Java", "cup.and.saucer.fill", "red", "java", "// Java Code\npublic class Main {\n    public static void main(String[] args) {\n        System.out.println(\"Hello, Java!\");\n    }\n}"),
            new CellLang("C#", "number.circle.fill", "purple", "cs", "// C# Code\nusing System;\n\nConsole.WriteLine(\"Hello, C#!\");"),
            new CellLang("R Markdown", "doc.richtext.fill", "teal", "Rmd", "---\ntitle: \"My Document\"\noutput: html_document\n---\n\n## Introduction\n\nThis is an **R Markdown** document.\n\n```{r}\n# R code chunk\nsummary(cars)\n```\n\n## Conclusion\n\nYou can include LaTeX math: $E = mc^2$"),
            new CellLang("LaTeX", "function", "orange", "tex", "\\documentclass{article}\n\\usepackage{amsmath}\n\n\\begin{document}\n\n\\section{Introduction}\nThis is a \\LaTeX\\ document.\n\nThe quadratic formula:\n\\begin{equation}\n    x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}\n\\end{equation}\n\n\\end{document}")
        };

        public static CellLang Get(string name)
        {
            foreach (var l in All) if (string.Equals(l.Name, name, StringComparison.OrdinalIgnoreCase)) return l;
            return All[0];
        }

        /// <summary>CellLanguage.from(fenceTag:) — maps a Markdown fence tag (```python, ```tex, ```cpp …) to a language, null when unknown.</summary>
        public static CellLang FromFence(string raw)
        {
            string t = (raw ?? "").Trim().ToLowerInvariant();
            if (t.Length == 0) return null;
            switch (t)
            {
                case "python": case "py": case "python3": case "ipython": return Get("Python");
                case "r": case "rscript": return Get("R");
                case "julia": case "jl": return Get("Julia");
                case "sql": case "mysql": case "postgresql": case "postgres": case "sqlite": case "plsql": case "tsql": return Get("SQL");
                case "ardium": case "ar": return Get("Ardium");
                case "rust": case "rs": return Get("Rust");
                case "go": case "golang": return Get("Go");
                case "cpp": case "c++": case "cxx": case "cc": case "c": case "h": case "hpp": return Get("C++");
                case "objc": case "objective-c": case "objectivec": case "m": case "mm": return Get("Objective-C");
                case "java": return Get("Java");
                case "csharp": case "c#": case "cs": case "dotnet": case ".net": return Get("C#");
                case "rmarkdown": case "rmd": return Get("R Markdown");
                case "latex": case "tex": case "katex": return Get("LaTeX");
            }
            foreach (var l in All) if (l.Name.ToLowerInvariant() == t || l.Ext.ToLowerInvariant() == t) return l;
            return null;
        }

        /// <summary>Highlighter key used by the Windows code editor.</summary>
        public string EditorKey
        {
            get
            {
                switch (Name)
                {
                    case "C++": return "cpp"; case "C#": return "csharp"; case "Objective-C": return "objectivec";
                    case "R Markdown": return "markdown"; case "LaTeX": return "latex"; case "Ardium": return "rust";
                    default: return Name.ToLowerInvariant();
                }
            }
        }
    }

    // ── SwiftUI named colours (Color.blue, .purple …) in the active appearance ──
    public static class NbColor
    {
        public static SolidColorBrush Named(string key)
        {
            var t = Theme.Current;
            switch ((key ?? "").ToLowerInvariant())
            {
                case "blue": return t.SysBlue; case "purple": return t.SysPurple; case "green": return t.SysGreen; case "cyan": return t.SysCyan;
                case "orange": return t.SysOrange; case "mint": return t.SysMint; case "indigo": return t.SysIndigo; case "red": return t.SysRed;
                case "teal": return t.SysTeal; case "pink": return t.SysPink; case "yellow": return t.SysYellow; case "gray": case "grey": return t.SysGray;
                case "brown": return Theme.B(t.IsDark ? Theme.Rgb(172, 142, 104) : Theme.Rgb(162, 132, 94));
                case "accent": return t.Accent;
                default: return t.SysGray;
            }
        }
        public static SolidColorBrush Alpha(SolidColorBrush b, double a) { return Theme.B(Theme.WithAlpha(b.Color, a)); }
    }

    /// <summary>CellColorTheme: tint fill 0.15, border 0.6, icon colour.</summary>
    public static class CellColors
    {
        public static readonly string[] All = { "None", "Blue", "Green", "Purple", "Orange", "Pink", "Yellow", "Red", "Cyan", "Teal", "Indigo", "Mint", "Brown", "Gray" };
        public static Brush Fill(string theme) { return theme == null || theme == "None" ? (Brush)Brushes.Transparent : NbColor.Alpha(NbColor.Named(theme), 0.15); }
        public static Brush Border(string theme) { return theme == null || theme == "None" ? (Brush)Theme.Current.S(0.25) : NbColor.Alpha(NbColor.Named(theme), 0.6); }
        public static Brush Icon(string theme) { return theme == null || theme == "None" ? (Brush)Theme.Current.Primary : NbColor.Named(theme); }
    }

    public class CustomCellColor
    {
        public double Red = 0.3, Green = 0.5, Blue = 0.8, Opacity = 0.15;
        Color Rgb { get { return Color.FromRgb((byte)Math.Round(Clamp(Red) * 255), (byte)Math.Round(Clamp(Green) * 255), (byte)Math.Round(Clamp(Blue) * 255)); } }
        static double Clamp(double v) { return Math.Max(0, Math.Min(1, v)); }
        public Brush Fill { get { return Theme.B(Theme.WithAlpha(Rgb, Clamp(Opacity))); } }
        public Brush Border { get { return Theme.B(Theme.WithAlpha(Rgb, Math.Min(Opacity * 3, 1.0))); } }
    }

    /// <summary>ComputeTarget. Windows runs every local target in the same local kernel (like the Mac's localCPU / localNvidia);
    /// remote targets need services that are not ported yet and are listed as unavailable instead of pretending to run.</summary>
    public static class ComputeTargets
    {
        public static readonly string[] UserSelectable = { "Local CPU", "Apple Silicon (NPU/Metal)", "Nvidia GPU (CUDA/eGPU)", "Google Colab (Cloud GPU/TPU)", "Custom Cloud GPU (RunPod/Vast.ai/Akamai)", "Your Cloud (SSH)" };

        public static string Display(string raw)
        {
            switch (raw)
            {
                case "Apple Silicon (NPU/Metal)": return "Apple Silicon";
                case "Nvidia GPU (CUDA/eGPU)": return "Local Nvidia GPU";
                case "Google Colab (Cloud GPU/TPU)": return "Google Colab";
                case "Microrent Cloud (Serverless)": return "MicroCode Cloud (Premium)";
                case "Custom Cloud GPU (RunPod/Vast.ai/Akamai)": return "MicroCode Cloud";
                case "Your Cloud (SSH)": return "Your Cloud (SSH)";
                default: return "Local CPU";
            }
        }

        public static string Icon(string raw)
        {
            switch (raw)
            {
                case "Apple Silicon (NPU/Metal)": return "applelogo";
                case "Nvidia GPU (CUDA/eGPU)": return "memorychip";
                case "Google Colab (Cloud GPU/TPU)": return "sparkles.rectangle.stack";
                case "Custom Cloud GPU (RunPod/Vast.ai/Akamai)": case "Microrent Cloud (Serverless)": return "cloud.fill";
                case "Your Cloud (SSH)": return "server.rack";
                default: return "cpu";
            }
        }

        public static bool IsPremium(string raw) { return raw == "Custom Cloud GPU (RunPod/Vast.ai/Akamai)" || raw == "Microrent Cloud (Serverless)"; }
        public static bool IsLocal(string raw) { return raw == null || raw == "Local CPU" || raw == "Nvidia GPU (CUDA/eGPU)"; }

        static bool? _nvidia;
        /// <summary>True when an NVIDIA driver is installed (nvidia-smi answers).</summary>
        public static bool HasNvidia
        {
            get
            {
                if (_nvidia.HasValue) return _nvidia.Value;
                bool ok = false;
                try
                {
                    var p = Process.Start(new ProcessStartInfo("nvidia-smi", "-L") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true });
                    if (p != null) { string o = p.StandardOutput.ReadToEnd(); p.WaitForExit(3000); ok = p.ExitCode == 0 && o.Contains("GPU"); }
                }
                catch (Exception ex) { Debug.WriteLine("nvidia-smi: " + ex.Message); }
                _nvidia = ok;
                return ok;
            }
        }

        /// <summary>Null when the target can run on this PC, otherwise the reason it cannot.</summary>
        public static string Unavailable(string raw)
        {
            switch (raw)
            {
                case "Local CPU": return null;
                case "Nvidia GPU (CUDA/eGPU)": return HasNvidia ? null : "no NVIDIA driver found (nvidia-smi)";
                case "Apple Silicon (NPU/Metal)": return "Apple Silicon only exists on Macs";
                default: return "not available in MicroCode for Windows yet";
            }
        }

        public static string Current
        {
            get { string v = Defaults.Str("currentComputeTarget", "Local CPU"); return Unavailable(v) == null ? v : "Local CPU"; }
            set { Defaults.Set("currentComputeTarget", value); }
        }
    }

    // ── kernel value types (SharedMemoryService.swift) ────────────────────────
    public class KernelVar
    {
        public string Name = "", TypeName = "", Shape = "", Dtype = "", Preview = "";
        public long MemoryBytes;
        public List<string> Columns = new List<string>();
        public List<double> NumericSample = new List<double>();
        public string FormattedMemory { get { return MemoryBytes < 1024 ? MemoryBytes + " B" : NbFmt.Bytes(MemoryBytes); } }
    }

    public class CellTelemetry
    {
        public double DurationMs;
        public long MemoryDeltaBytes, PeakRSSBytes, GpuBytes;
        public bool IsCachedBinary;
        public string FormattedDuration
        {
            get
            {
                if (DurationMs < 1.0) return DurationMs.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture) + "ms";
                if (DurationMs < 1000.0) return DurationMs.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture) + "ms";
                return (DurationMs / 1000.0).ToString("0.00", System.Globalization.CultureInfo.InvariantCulture) + "s";
            }
        }
        public string FormattedMemoryDelta
        {
            get { long a = Math.Abs(MemoryDeltaBytes); if (a < 64 * 1024) return null; return (MemoryDeltaBytes >= 0 ? "+" : "-") + NbFmt.Bytes(a); }
        }
        public string FormattedGpu { get { return GpuBytes > 0 ? "CUDA " + NbFmt.Bytes(GpuBytes) : null; } }
    }

    public class DfStats { public int NullCount; public double? MinVal, MaxVal, MeanVal; }

    public class InlineDataFrame
    {
        public string VariableName = "DataFrame", CsvExportPath;
        public int TotalRows, TotalCols;
        public List<string> Columns = new List<string>();
        public Dictionary<string, string> Dtypes = new Dictionary<string, string>();
        public Dictionary<string, DfStats> Stats = new Dictionary<string, DfStats>();
        public List<List<string>> Rows = new List<List<string>>();
    }

    public class CellVersion
    {
        public int VersionNumber;
        public DateTime Timestamp;
        public string SourceLabel = "", Content = "", OutputPreview = "";
        public double? DurationMs;
    }

    /// <summary>CellAgentToolStep.</summary>
    public class CellToolStep
    {
        public string Id = Guid.NewGuid().ToString("N"), ToolName = "", Summary = "", Output = "";
        public bool IsRunning, IsError;
        public DateTime StartedAt = DateTime.Now;
        public int? DurationMs;

        public string Icon
        {
            get
            {
                switch (ToolName)
                {
                    case "cell_list": return "list.number"; case "cell_read": return "doc.text.magnifyingglass"; case "cell_create": return "plus.rectangle.on.rectangle";
                    case "cell_update": return "pencil"; case "cell_delete": return "trash"; case "cell_run": case "playground_run": case "ardium_run": return "play.fill";
                    case "shell": return "terminal"; case "file_read": case "multi_file_read": return "doc.text";
                    case "file_write": case "replace_in_file": case "patch_file": case "apply_patch": return "square.and.pencil";
                    case "grep_search": case "codebase_search": case "file_search": return "magnifyingglass"; case "web_fetch": return "globe";
                    default: return ToolName.StartsWith("mcp__") ? "puzzlepiece.extension" : "wrench.and.screwdriver";
                }
            }
        }

        public string FriendlyTitle
        {
            get
            {
                bool r = IsRunning;
                switch (ToolName)
                {
                    case "cell_list": return r ? "Listing cells" : "Listed cells";
                    case "cell_read": return r ? "Inspecting" : "Inspected";
                    case "cell_create": return r ? "Creating" : "Created";
                    case "cell_update": return r ? "Editing" : "Edited";
                    case "cell_delete": return r ? "Removing" : "Removed";
                    case "cell_run": return r ? "Executing" : "Executed";
                    case "playground_run": return r ? "Running snippet" : "Ran snippet";
                    case "shell": return r ? "Running command" : "Ran command";
                    case "file_read": case "multi_file_read": return r ? "Reading" : "Read";
                    case "file_write": return r ? "Writing" : "Wrote";
                    case "replace_in_file": case "patch_file": case "apply_patch": return r ? "Editing" : "Edited";
                    case "codebase_search": case "grep_search": case "file_search": return r ? "Searching" : "Searched";
                    case "list_directory_tree": return r ? "Listing" : "Listed";
                    default:
                        string clean = ToolName.Replace("mcp__", "").Replace("_", " ");
                        return r ? "Running " + clean : "Ran " + clean;
                }
            }
        }
    }

    // ── cells, sheets, data files ─────────────────────────────────────────────
    public class NbCell
    {
        public string Id = Guid.NewGuid().ToString(), Type = "Code", Language = "Python", Content = "", Output = "", Tag = "";
        /// <summary>Rich outputs written by the cell (plots, images, PDF, Markdown/TeX, HTML).</summary>
        public List<string> Images = new List<string>();
        public int ExecCount;
        public string ColorTheme = "None";
        public bool UseCustomColor;
        public CustomCellColor CustomColor;
        public string ComputeOverride;
        public bool Collapsed;
        public string AiRole = "data_scientist";
        public bool AgentMode = true;
        public CellTelemetry Telemetry;
        public List<CellVersion> Versions = new List<CellVersion>();
        public string PendingDiffOld, PendingDiffSource = "AI Agent";
        public InlineDataFrame DataFrame;
        public int LastRunEpoch;
        public string GeneratedCode = "";
        /// <summary>Legacy (first Windows port kept stderr apart); merged into Output when loaded.</summary>
        public string Error = "";

        [ScriptIgnore] public bool IsExecuting, IsQueued;
        [ScriptIgnore] public string AgentThought = "", AgentStatus = "";
        [ScriptIgnore] public List<CellToolStep> AgentSteps = new List<CellToolStep>();

        public bool IsCode { get { return Type == "Code"; } }
        public bool IsAgent { get { return Type == "Agent"; } }
        public bool IsRunnable { get { return Type == "Code" || Type == "Procedure" || Type == "Agent"; } }
        public CellLang Lang { get { return CellLang.Get(Language); } }

        public static NbCell Create(string type, string language, string content)
        {
            var c = new NbCell { Type = type, Language = language ?? "Python" };
            c.Content = string.IsNullOrEmpty(content) && type == "Code" ? CellLang.Get(c.Language).DefaultContent : content ?? "";
            return c;
        }

        public void ClearOutput()
        {
            Output = ""; Error = ""; Images = new List<string>(); DataFrame = null; Telemetry = null;
            AgentThought = ""; AgentSteps = new List<CellToolStep>(); AgentStatus = "";
        }

        public void RecordAgentEditBaseline(string previousContent, string source)
        {
            if ((previousContent ?? "").Trim().Length == 0) return;
            if (PendingDiffOld == null) PendingDiffOld = previousContent;
            PendingDiffSource = source ?? "AI Agent";
            Versions.Add(new CellVersion
            {
                VersionNumber = (Versions.Count > 0 ? Versions[Versions.Count - 1].VersionNumber : 0) + 1, Timestamp = DateTime.Now,
                SourceLabel = "Before " + PendingDiffSource, Content = previousContent, OutputPreview = Prefix(Output, 160),
                DurationMs = Telemetry != null ? (double?)Telemetry.DurationMs : null
            });
            Trim();
        }

        public void RecordExecutionSnapshot(string source)
        {
            if ((Content ?? "").Trim().Length == 0) return;
            if (Versions.Count > 0 && Versions[Versions.Count - 1].Content == Content) return;
            Versions.Add(new CellVersion
            {
                VersionNumber = (Versions.Count > 0 ? Versions[Versions.Count - 1].VersionNumber : 0) + 1, Timestamp = DateTime.Now,
                SourceLabel = source, Content = Content, OutputPreview = Prefix(Output, 160),
                DurationMs = Telemetry != null ? (double?)Telemetry.DurationMs : null
            });
            Trim();
        }

        void Trim() { if (Versions.Count > 12) Versions.RemoveRange(0, Versions.Count - 12); }
        static string Prefix(string s, int n) { s = s ?? ""; return s.Length > n ? s.Substring(0, n) : s; }

        public Brush CardTint { get { return UseCustomColor && CustomColor != null ? CustomColor.Fill : CellColors.Fill(ColorTheme); } }
        public Brush BorderTint
        {
            get
            {
                if (UseCustomColor && CustomColor != null) return CustomColor.Border;
                if (ColorTheme != null && ColorTheme != "None") return CellColors.Border(ColorTheme);
                return Theme.Current.IsDark ? Theme.B(Theme.WithAlpha(Colors.White, 0.12)) : Theme.B(Theme.WithAlpha(Colors.Black, 0.1));
            }
        }
    }

    public class NbDataFile
    {
        public string Name = "", Path = "", Type = "File";
        public long Size;

        public static NbDataFile For(string path)
        {
            long size = 0;
            try { size = new FileInfo(path).Length; } catch (Exception ex) { Debug.WriteLine("data file size: " + ex.Message); }
            return new NbDataFile { Name = System.IO.Path.GetFileName(path), Path = path, Type = TypeFor(System.IO.Path.GetExtension(path)), Size = size };
        }

        public static string TypeFor(string ext)
        {
            switch ((ext ?? "").TrimStart('.').ToLowerInvariant())
            {
                case "csv": return "CSV"; case "xlsx": case "xls": return "Excel"; case "json": return "JSON";
                case "sql": case "sqlite": case "db": return "SQL"; case "parquet": return "Parquet";
                case "pdb": case "ent": case "cif": case "mmcif": return "Structure";
                case "fasta": case "fa": case "faa": case "fna": case "a3m": return "Sequence";
                case "png": case "jpg": case "jpeg": case "gif": case "webp": case "svg": case "tiff": return "Figure";
                case "pdf": return "Paper"; case "tex": case "bib": return "LaTeX";
                case "h5": case "hdf5": case "h5ad": case "npy": case "npz": case "sdf": case "mol": case "mol2": return "Scientific";
                default: return "File";
            }
        }

        public string Icon
        {
            get
            {
                switch (Type)
                {
                    case "CSV": return "tablecells"; case "Excel": return "tablecells.fill"; case "JSON": return "curlybraces"; case "SQL": return "cylinder";
                    case "Parquet": return "doc.zipper"; case "Structure": return "atom"; case "Sequence": return "text.line.first.and.arrowtriangle.forward";
                    case "Figure": return "photo"; case "Paper": return "doc.richtext"; case "LaTeX": return "textformat"; case "Scientific": return "waveform.path.ecg";
                    default: return "doc";
                }
            }
        }

        public SolidColorBrush Brush
        {
            get
            {
                switch (Type)
                {
                    case "CSV": case "Excel": return NbColor.Named("green"); case "JSON": return NbColor.Named("orange"); case "SQL": return NbColor.Named("blue");
                    case "Parquet": return NbColor.Named("purple"); case "Structure": return NbColor.Named("cyan"); case "Sequence": return NbColor.Named("mint");
                    case "Figure": return NbColor.Named("indigo"); case "Paper": return NbColor.Named("red"); case "LaTeX": return NbColor.Named("orange");
                    case "Scientific": return NbColor.Named("teal"); default: return NbColor.Named("gray");
                }
            }
        }
    }

    public class NbDoc
    {
        public string Id = Guid.NewGuid().ToString(), Name = "Cell Sheet 1";
        public List<NbCell> Cells = new List<NbCell>();
        public List<NbDataFile> Files = new List<NbDataFile>();
        /// <summary>Legacy list of plain paths (first Windows port); migrated into Files.</summary>
        public List<string> DataFiles = new List<string>();
        public DateTime CreatedAt = DateTime.Now, ModifiedAt = DateTime.Now;
        /// <summary>The .mic file this sheet is bound to (Quick Save target); null until saved.</summary>
        public string FilePath;
    }

    public static class NbFmt
    {
        public static string Bytes(long b)
        {
            double v = b; string[] u = { "bytes", "KB", "MB", "GB", "TB" }; int i = 0;
            if (b < 1000) return b + (b == 1 ? " byte" : " bytes");
            while (v >= 1000 && i < u.Length - 1) { v /= 1000; i++; }
            return v.ToString(v < 10 ? "0.#" : "0", System.Globalization.CultureInfo.InvariantCulture) + " " + u[i];
        }
    }

    // ── persistence ──────────────────────────────────────────────────────────
    public static class NbStore
    {
        public static List<NbDoc> Docs = new List<NbDoc>();
        public static string ActiveId;
        public static List<NbDoc> Seed;      // snapshot/test hook: in-memory notebooks, never persisted
        static bool ReadOnly { get { return Seed != null; } }
        static string FilePath { get { return Path.Combine(Defaults.Dir, "notebooks.json"); } }
        static readonly JavaScriptSerializer Js = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };

        /// <summary>NotebookViewModel.workingDirectory: cells run here and write their artifacts/ next to it.</summary>
        public static string WorkingDirectory
        {
            get
            {
                string d = Path.Combine(Defaults.Dir, "notebooks_workspace");
                try { Directory.CreateDirectory(d); } catch (Exception ex) { Debug.WriteLine("notebook workspace: " + ex.Message); }
                return d;
            }
        }

        public static void Load()
        {
            if (Seed != null) { Docs = Seed; if (ActiveId == null || !Docs.Any(d => d.Id == ActiveId)) ActiveId = Docs[0].Id; Migrate(); return; }
            try { if (File.Exists(FilePath)) Docs = Js.Deserialize<List<NbDoc>>(Defaults.ReadShared(FilePath)) ?? new List<NbDoc>(); }
            catch (Exception ex) { Debug.WriteLine("notebooks.json: " + ex.Message); Docs = new List<NbDoc>(); }
            if (Docs.Count == 0) Docs.Add(NewDoc("Cell Sheet 1"));
            if (ActiveId == null || !Docs.Any(d => d.Id == ActiveId)) ActiveId = Docs[0].Id;
            Migrate();
        }

        static void Migrate()
        {
            foreach (var d in Docs)
            {
                if (d.Cells == null) d.Cells = new List<NbCell>();
                if (d.Files == null) d.Files = new List<NbDataFile>();
                if (d.DataFiles != null && d.DataFiles.Count > 0)
                {
                    foreach (var p in d.DataFiles) if (!d.Files.Any(f => string.Equals(f.Path, p, StringComparison.OrdinalIgnoreCase))) d.Files.Add(NbDataFile.For(p));
                    d.DataFiles.Clear();
                }
                foreach (var c in d.Cells)
                {
                    if (c.Images == null) c.Images = new List<string>();
                    if (c.Versions == null) c.Versions = new List<CellVersion>();
                    if (c.AgentSteps == null) c.AgentSteps = new List<CellToolStep>();
                    if (c.Output == null) c.Output = "";
                    if (!string.IsNullOrEmpty(c.Error)) { c.Output = (c.Output.Length > 0 ? c.Output.TrimEnd('\n') + "\n" : "") + c.Error; c.Error = ""; }
                    if (c.ColorTheme == null) c.ColorTheme = "None";
                    if (c.AiRole == null) c.AiRole = "data_scientist";
                    if (c.Type == "Code" && CellLang.All.All(l => l.Name != c.Language)) c.Language = c.Language == "JavaScript" ? "Python" : "Python";
                }
            }
        }

        public static NbDoc NewDoc(string name)
        {
            var d = new NbDoc { Name = name };
            d.Cells.Add(NbCell.Create("Code", "Python", "# Your Python code here\nprint('Hello, World!')"));
            return d;
        }

        public static void Save()
        {
            if (ReadOnly) return;
            try { Defaults.WriteAtomic(FilePath, Js.Serialize(Docs)); }
            catch (Exception ex) { Debug.WriteLine("notebooks.json save: " + ex.Message); }
        }

        public static NbDoc Active { get { return Docs.FirstOrDefault(d => d.Id == ActiveId) ?? Docs.FirstOrDefault(); } }
    }

    // ── file formats ─────────────────────────────────────────────────────────
    public static class NbFormats
    {
        static readonly DateTime RefDate = new DateTime(2001, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        static double SwiftDate(DateTime d) { return (d.ToUniversalTime() - RefDate).TotalSeconds; }
        static DateTime FromSwift(object v) { try { return RefDate.AddSeconds(Convert.ToDouble(v)).ToLocalTime(); } catch { return DateTime.Now; } }
        static string Uuid(string id) { Guid g; return Guid.TryParse(id, out g) ? g.ToString().ToUpperInvariant() : Guid.NewGuid().ToString().ToUpperInvariant(); }
        static string Str(Dictionary<string, object> o, string k, string def) { object v; return o != null && o.TryGetValue(k, out v) && v != null ? Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture) : def; }
        static bool Bool(Dictionary<string, object> o, string k) { object v; return o != null && o.TryGetValue(k, out v) && v is bool && (bool)v; }

        /// <summary>NotebookViewModel.loadNotebook(from:): .mic, .mcnb, .ipynb (or Jupyter JSON) and "# %%" .py scripts.</summary>
        public static NbDoc Load(string path)
        {
            string ext = Path.GetExtension(path).ToLowerInvariant();
            if (ext == ".mic") { var d = FromMicJson(Encoding.UTF8.GetString(Lzfse.Decode(File.ReadAllBytes(path)))); d.FilePath = path; return d; }
            if (ext == ".py") return FromPy(File.ReadAllText(path), Path.GetFileName(path));
            var o = DJ.Obj(File.ReadAllText(path));
            if (o == null) throw new InvalidDataException("Not a notebook JSON file.");
            if (Str(o, "format", "") == "mcnb") return FromMcnb(o);
            if (o.ContainsKey("nbformat")) return FromIpynb(o, Path.GetFileNameWithoutExtension(path));
            throw new InvalidDataException("Unknown notebook format (expected .mic, .mcnb, .ipynb or .py).");
        }

        // .mic = LZFSE(JSON of MicNotebook) — JSONEncoder defaults: Date = seconds since 2001-01-01, UUID = upper-case string.
        public static void SaveMic(NbDoc d, string path)
        {
            var cells = d.Cells.Select(c =>
            {
                var m = new Dictionary<string, object>
                {
                    { "id", Uuid(c.Id) }, { "type", c.Type }, { "language", c.Language }, { "content", c.Content ?? "" }, { "output", c.Output ?? "" },
                    { "colorTheme", c.ColorTheme ?? "None" }, { "isCollapsed", c.Collapsed }, { "generatedCode", c.GeneratedCode ?? "" },
                    { "agentExecutionMode", c.AgentMode },
                    { "aiSelection", new Dictionary<string, object> { { "useGlobal", true }, { "keyMode", "direct" }, { "provider", "" }, { "model", "" }, { "subscriptionProvider", "" }, { "localEndpoint", "" }, { "subAgentRole", c.AiRole ?? "data_scientist" } } }
                };
                if (c.ExecCount > 0) m["executionCount"] = c.ExecCount;
                return (object)m;
            }).ToList();
            var root = new Dictionary<string, object>
            {
                { "version", 1 }, { "id", Uuid(d.Id) }, { "name", d.Name }, { "createdAt", SwiftDate(d.CreatedAt) }, { "modifiedAt", SwiftDate(DateTime.Now) },
                { "cells", cells },
                { "dataFiles", d.Files.Select(f => (object)new Dictionary<string, object> { { "name", f.Name }, { "path", f.Path }, { "type", f.Type }, { "size", f.Size } }).ToList() }
            };
            WriteBytesAtomic(path, Lzfse.EncodeStored(Encoding.UTF8.GetBytes(DJ.Ser(root))));
        }

        static NbDoc FromMicJson(string json)
        {
            var o = DJ.Obj(json);
            if (o == null) throw new InvalidDataException("The .mic file does not contain a notebook.");
            var d = new NbDoc { Name = Str(o, "name", "Untitled Notebook"), CreatedAt = o.ContainsKey("createdAt") ? FromSwift(o["createdAt"]) : DateTime.Now };
            var cells = DJ.Arr(o, "cells");
            if (cells != null)
                foreach (var x in cells)
                {
                    var c = x as Dictionary<string, object>; if (c == null) continue;
                    var cell = new NbCell
                    {
                        Type = Str(c, "type", "Code"), Language = CellLang.Get(Str(c, "language", "Python")).Name, Content = Str(c, "content", ""),
                        Output = Str(c, "output", ""), ColorTheme = Str(c, "colorTheme", "None"), Collapsed = Bool(c, "isCollapsed"), GeneratedCode = Str(c, "generatedCode", "")
                    };
                    object ec; if (c.TryGetValue("executionCount", out ec) && ec != null) cell.ExecCount = Convert.ToInt32(ec);
                    object am; if (c.TryGetValue("agentExecutionMode", out am) && am is bool) cell.AgentMode = (bool)am;
                    var sel = DJ.Child(c, "aiSelection"); if (sel != null) cell.AiRole = Str(sel, "subAgentRole", "data_scientist");
                    if (cell.Type == "Procedure") { cell.Type = "Code"; if (cell.Content.Trim().Length == 0) cell.Content = cell.GeneratedCode; }
                    d.Cells.Add(cell);
                }
            ReadDataFiles(DJ.Arr(o, "dataFiles"), d);
            if (d.Cells.Count == 0) d.Cells.Add(NbCell.Create("Code", "Python", null));
            return d;
        }

        static void ReadDataFiles(System.Collections.ArrayList arr, NbDoc d)
        {
            if (arr == null) return;
            foreach (var x in arr)
            {
                var f = x as Dictionary<string, object>; if (f == null) continue;
                string p = Str(f, "path", ""); if (p.Length == 0 || !File.Exists(p)) continue;
                d.Files.Add(NbDataFile.For(p));
            }
        }

        static NbDoc FromMcnb(Dictionary<string, object> o)
        {
            var d = new NbDoc { Name = Str(o, "name", "Imported Notebook") };
            var cells = DJ.Arr(o, "cells");
            if (cells != null)
                foreach (var x in cells)
                {
                    var c = x as Dictionary<string, object>; if (c == null) continue;
                    var cell = new NbCell
                    {
                        Type = Str(c, "type", "Code"), Language = CellLang.Get(Str(c, "language", "Python")).Name, Content = Str(c, "content", ""),
                        Output = Str(c, "output", ""), ColorTheme = Str(c, "color_theme", "None"), Tag = Str(c, "tag", ""), Collapsed = Bool(c, "is_collapsed"),
                        UseCustomColor = Bool(c, "use_custom_color")
                    };
                    object ec; if (c.TryGetValue("execution_count", out ec) && ec != null) cell.ExecCount = Convert.ToInt32(ec);
                    var cc = DJ.Child(c, "custom_color");
                    if (cc != null) cell.CustomColor = new CustomCellColor { Red = DJ.Num(cc, "red") ?? 0, Green = DJ.Num(cc, "green") ?? 0, Blue = DJ.Num(cc, "blue") ?? 0, Opacity = DJ.Num(cc, "opacity") ?? 1 };
                    if (cell.ColorTheme == "none") cell.ColorTheme = "None";
                    d.Cells.Add(cell);
                }
            ReadDataFiles(DJ.Arr(o, "data_files"), d);
            if (d.Cells.Count == 0) d.Cells.Add(NbCell.Create("Code", "Python", null));
            return d;
        }

        static string Joined(object src)
        {
            if (src == null) return "";
            var s = src as string; if (s != null) return s;
            var arr = DJ.AsList(src); if (arr == null) return "";
            var sb = new StringBuilder(); foreach (var x in arr) sb.Append(Convert.ToString(x)); return sb.ToString();
        }

        static NbDoc FromIpynb(Dictionary<string, object> o, string name)
        {
            var d = new NbDoc { Name = name };
            var cells = DJ.Arr(o, "cells");
            if (cells != null)
                foreach (var x in cells)
                {
                    var c = x as Dictionary<string, object>; if (c == null) continue;
                    string ct = Str(c, "cell_type", "code");
                    var cell = new NbCell { Type = ct == "markdown" ? "Markdown" : ct == "raw" ? "Raw" : "Code" };
                    object src; c.TryGetValue("source", out src); cell.Content = Joined(src);
                    var meta = DJ.Child(c, "metadata");
                    string lang = Str(meta, "language", "Python");
                    cell.Language = CellLang.All.Any(l => string.Equals(l.Name, lang, StringComparison.OrdinalIgnoreCase)) ? CellLang.Get(lang).Name : "Python";
                    object ec; if (c.TryGetValue("execution_count", out ec) && ec != null) cell.ExecCount = Convert.ToInt32(ec);
                    var outs = DJ.Arr(c, "outputs");
                    if (outs != null)
                    {
                        var sb = new StringBuilder();
                        foreach (var oo in outs)
                        {
                            var od = oo as Dictionary<string, object>; if (od == null) continue;
                            object t;
                            if (od.TryGetValue("text", out t)) sb.Append(Joined(t));
                            else { var data = DJ.Child(od, "data"); object plain; if (data != null && data.TryGetValue("text/plain", out plain)) sb.Append(Joined(plain)); }
                            if (Str(od, "output_type", "") == "error") sb.Append(Str(od, "ename", "Error") + ": " + Str(od, "evalue", ""));
                        }
                        cell.Output = sb.ToString();
                    }
                    d.Cells.Add(cell);
                }
            if (d.Cells.Count == 0) d.Cells.Add(NbCell.Create("Code", "Python", null));
            return d;
        }

        static List<string> Lines(string s)
        {
            var parts = (s ?? "").Split('\n');
            return parts.Select((p, i) => i < parts.Length - 1 ? p + "\n" : p).Where((p, i) => !(i == parts.Length - 1 && p.Length == 0)).ToList();
        }

        /// <summary>exportAsIPYNB — cells keep their language in metadata so the Mac and Windows apps restore polyglot sheets.</summary>
        public static void SaveIpynb(NbDoc d, string path)
        {
            var cells = d.Cells.Select(c =>
            {
                var m = new Dictionary<string, object>
                {
                    { "cell_type", c.Type == "Code" ? "code" : c.Type == "Markdown" ? "markdown" : "raw" },
                    { "metadata", new Dictionary<string, object> { { "language", c.Language } } },
                    { "source", Lines(c.Content) }
                };
                if (c.Type == "Code")
                {
                    m["execution_count"] = c.ExecCount > 0 ? (object)c.ExecCount : null;
                    m["outputs"] = (c.Output ?? "").Length == 0 ? new List<object>() : new List<object> { new Dictionary<string, object> { { "output_type", "stream" }, { "name", "stdout" }, { "text", Lines(c.Output) } } };
                }
                return (object)m;
            }).ToList();
            var root = new Dictionary<string, object>
            {
                { "cells", cells },
                { "metadata", new Dictionary<string, object>
                    {
                        { "kernelspec", new Dictionary<string, object> { { "display_name", "Python 3" }, { "language", "python" }, { "name", "python3" } } },
                        { "language_info", new Dictionary<string, object> { { "name", "python" } } },
                        { "microcode", new Dictionary<string, object> { { "version", "1.0.1" }, { "multi_language", true } } }
                    } },
                { "nbformat", 4 }, { "nbformat_minor", 4 }
            };
            WriteBytesAtomic(path, Encoding.UTF8.GetBytes(DJ.Ser(root)));
        }

        /// <summary>PythonScriptNotebookBridge.export — plain-text "# %%" script for Git and CI.</summary>
        public static string ToPy(NbDoc d)
        {
            var o = new List<string> { "#!/usr/bin/env python3", "# -*- coding: utf-8 -*-", "# Generated by MicroCode - Plain-Text Git-Friendly Notebook", "" };
            foreach (var c in d.Cells)
            {
                switch (c.Type)
                {
                    case "Markdown":
                        o.Add("# %% [markdown]");
                        foreach (var l in (c.Content ?? "").Split('\n')) o.Add("# " + l.TrimEnd('\r'));
                        o.Add(""); break;
                    case "Agent":
                        o.Add("# %% [agent]"); o.Add("# " + (c.Content ?? "").Replace("\n", "\n# ")); o.Add(""); break;
                    case "Raw":
                        o.Add("# %% [raw]"); o.Add((c.Content ?? "").Trim('\n')); o.Add(""); break;
                    default:
                        o.Add("# %% [" + (c.Language == "Python" ? "python" : c.Lang.Ext.ToLowerInvariant()) + "]"); o.Add((c.Content ?? "").Trim('\n')); o.Add(""); break;
                }
            }
            return string.Join("\n", o);
        }

        /// <summary>PythonScriptNotebookBridge.parse.</summary>
        public static NbDoc FromPy(string script, string name)
        {
            var d = new NbDoc { Name = name };
            var lines = (script ?? "").Replace("\r\n", "\n").Split('\n');
            var cur = new List<string>();
            string type = "Code";
            bool first = true;
            Action flush = () =>
            {
                string content = string.Join("\n", cur).Trim('\n');
                if (content.Length > 0 || d.Cells.Count > 0) d.Cells.Add(new NbCell { Type = type, Language = "Python", Content = content });
                cur.Clear();
            };
            foreach (var line in lines)
            {
                string t = line.Trim();
                if (t.StartsWith("# %%") || t.StartsWith("#%%"))
                {
                    if (!first || cur.Count > 0) flush();
                    first = false;
                    string lower = t.ToLowerInvariant();
                    type = lower.Contains("[markdown]") || lower.Contains("md") ? "Markdown" : "Code";
                    continue;
                }
                if (type == "Markdown" && line.StartsWith("# ")) cur.Add(line.Substring(2));
                else if (type == "Markdown" && line == "#") cur.Add("");
                else cur.Add(line);
            }
            flush();
            if (d.Cells.Count == 0) d.Cells.Add(new NbCell { Type = "Code", Language = "Python", Content = script ?? "" });
            return d;
        }

        public static void WriteBytesAtomic(string path, byte[] data)
        {
            string tmp = path + ".tmp-" + Guid.NewGuid().ToString("N").Substring(0, 6);
            File.WriteAllBytes(tmp, data);
            if (File.Exists(path)) File.Replace(tmp, path, null); else File.Move(tmp, path);
        }
    }

    /// <summary>Apple LZFSE container as used by NSData.compressed(using: .lzfse). Writes "stored" (bvx-) blocks that Apple's
    /// decoder reads natively; reads stored blocks and LZFSE/LZVN compressed blocks (see LzfseDecoder).</summary>
    public static class Lzfse
    {
        const uint Stored = 0x2d787662, End = 0x24787662;   // "bvx-", "bvx$"

        public static byte[] EncodeStored(byte[] raw)
        {
            using (var ms = new MemoryStream())
            {
                var w = new BinaryWriter(ms);
                w.Write(Stored); w.Write((uint)raw.Length); w.Write(raw); w.Write(End);
                w.Flush();
                return ms.ToArray();
            }
        }

        public static byte[] Decode(byte[] src)
        {
            // Files written before LZFSE wrapping (or plain JSON .mic exports) are accepted as-is.
            if (src.Length > 0 && (src[0] == '{' || src[0] == 0xEF)) return src;
            return LzfseDecoder.Decode(src);
        }
    }
}
