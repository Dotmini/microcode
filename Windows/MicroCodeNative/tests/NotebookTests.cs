// Self-checking tests for Cell Mode (src/Notebook), compiled against out-dev\MicroCode.exe by run-tests.cmd:
// # @param parsing/rewriting, the reactive DAG, .ipynb / .py / .mcnb / .mic files (LZFSE container), the warm Python kernel
// (state, errors, interrupt, rich files, DataFrame payload), polyglot cells and the agent's cell_* tools on a live NotebookView.
// Everything runs in a temp folder with an isolated data dir, so the user's %APPDATA%\MicroCode is never touched.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using MicroCode.Core;
using MicroCode.UI;
using MicroCode.Views;

static class NotebookTests
{
    static int _pass, _fail;

    static void Check(bool ok, string name)
    {
        Console.WriteLine((ok ? "PASS  " : "FAIL  ") + name);
        if (ok) _pass++; else _fail++;
    }

    /// <summary>Runs the WPF dispatcher until <paramref name="done"/> is true or the timeout passes.</summary>
    static bool Pump(Func<bool> done, int timeoutMs)
    {
        var sw = Stopwatch.StartNew();
        while (!done() && sw.ElapsedMilliseconds < timeoutMs)
        {
            var frame = new DispatcherFrame();
            var t = new DispatcherTimer(TimeSpan.FromMilliseconds(30), DispatcherPriority.Background, (s, e) => { ((DispatcherTimer)s).Stop(); frame.Continue = false; }, Dispatcher.CurrentDispatcher);
            t.Start();
            Dispatcher.PushFrame(frame);
        }
        return done();
    }

    static bool Has(string exe, string args)
    {
        try
        {
            var p = Process.Start(new ProcessStartInfo(exe, args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true });
            p.WaitForExit(20000);
            return p.ExitCode == 0;
        }
        catch (Exception) { return false; }
    }

    [STAThread]
    static int Main()
    {
        string root = Path.Combine(Path.GetTempPath(), "mc-nbtests-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        Directory.CreateDirectory(root);
        Defaults.UseDir(Path.Combine(root, "data"));
        TaskFiles.HomeOverride = Path.Combine(root, "data", ".microcode");
        try
        {
            ParamTests();
            DagTests();
            FileTests(root);
            LzfseTests(root);
            var app = new Application();
            Styles.Install(app);
            KernelTests();
            RunnerTests();
            ViewAndToolTests();
        }
        catch (Exception ex) { Check(false, "unexpected exception: " + ex); }
        finally
        {
            NotebookView.ShutdownKernel();
            try { Directory.Delete(root, true); } catch (Exception) { }
        }
        Console.WriteLine();
        Console.WriteLine(_pass + " passed, " + _fail + " failed");
        return _fail == 0 ? 0 : 1;
    }

    // â”€â”€ # @param widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    static void ParamTests()
    {
        string code = "lr = 0.01  # @param [0.0001..0.1, step=0.001]\nepochs = 10 # @param [1..50]\nschool = \"Sarasas\" # @param [\"Sarasas\", \"Ruamrudee\", \"BCC\"]\nnormalize = True # @param\nname = \"run-a\" # @param\n# @param threshold: float = 0.75 [0.0..1.0, step=0.05]\nthreshold = 0.75";
        var p = CellParams.Parse(code);
        Check(p.Count == 6, "@param: six declarations found (" + p.Count + ")");
        var lr = p.FirstOrDefault(x => x.Name == "lr");
        Check(lr != null && lr.Kind == CellParam.Kinds.SliderDouble && Math.Abs(lr.Min - 0.0001) < 1e-12 && Math.Abs(lr.Max - 0.1) < 1e-12 && Math.Abs(lr.Step - 0.001) < 1e-12 && Math.Abs(lr.DoubleValue - 0.01) < 1e-12, "@param: [min..max, step] â†’ floating slider");
        var ep = p.FirstOrDefault(x => x.Name == "epochs");
        Check(ep != null && ep.Kind == CellParam.Kinds.SliderInt && ep.Min == 1 && ep.Max == 50 && ep.StringValue == "10", "@param: integer range â†’ int slider");
        var sc = p.FirstOrDefault(x => x.Name == "school");
        Check(sc != null && sc.Kind == CellParam.Kinds.Dropdown && sc.Options.SequenceEqual(new[] { "Sarasas", "Ruamrudee", "BCC" }) && sc.StringValue == "Sarasas", "@param: option list â†’ dropdown");
        var nm = p.FirstOrDefault(x => x.Name == "normalize");
        Check(nm != null && nm.Kind == CellParam.Kinds.Toggle && nm.BoolValue, "@param: True â†’ toggle");
        var tx = p.FirstOrDefault(x => x.Name == "name");
        Check(tx != null && tx.Kind == CellParam.Kinds.Text && tx.StringValue == "run-a", "@param: plain string â†’ text field");
        var th = p.FirstOrDefault(x => x.Name == "threshold");
        Check(th != null && th.Kind == CellParam.Kinds.SliderDouble && th.LineIndex == 6, "@param: header comment form binds to the assignment on the next line");
        string updated = CellParams.Update("    lr = 0.01  # @param [0.0001..0.1, step=0.001]", CellParams.Parse("    lr = 0.01  # @param [0.0001..0.1, step=0.001]")[0], "0.0500");
        Check(updated == "    lr = 0.0500  # @param [0.0001..0.1, step=0.001]", "@param: rewrite keeps indentation and the @param comment (" + updated + ")");
        string js = CellParams.Update("let rate = 3; // @param [1..9]", CellParams.Parse("let rate = 3; // @param [1..9]")[0], "7");
        Check(js == "let rate = 7;  // @param [1..9]", "@param: rewrite keeps a trailing semicolon and // comment (" + js + ")");
    }

    // â”€â”€ reactive DAG â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    static void DagTests()
    {
        var a = new NbCell { Content = "data = [1, 2, 3]\ntotal = sum(data)", LastRunEpoch = 3 };
        var b = new NbCell { Content = "mean = total / len(data)", LastRunEpoch = 2 };
        var c = new NbCell { Content = "print(mean)", LastRunEpoch = 4 };
        var md = new NbCell { Type = "Markdown", Content = "total" };
        var d = new NbCell { Content = "def helper(x):\n    return x * 2\nunused = 1", LastRunEpoch = 0 };
        var cells = new List<NbCell> { a, md, b, c, d };
        var g = CellDag.Analyze(cells);
        Check(!g.ContainsKey(md.Id), "DAG: markdown cells are not part of the graph");
        Check(g[a.Id].Downstream.Contains(b.Id) && g[b.Id].Downstream.Contains(c.Id), "DAG: total/data flow a â†’ b â†’ c");
        Check(g[b.Id].UpstreamNumbers.SequenceEqual(new[] { 1 }) && g[b.Id].UpstreamSymbols.Contains("total") && g[b.Id].UpstreamSymbols.Contains("data"), "DAG: b depends on cell #1 through data and total");
        Check(g[b.Id].IsStale && !g[c.Id].IsStale && !g[a.Id].IsStale, "DAG: b ran before its upstream re-ran â†’ Stale; c ran after b â†’ fresh");
        Check(g[d.Id].Defined.Contains("helper") && g[d.Id].Defined.Contains("unused") && !g[d.Id].IsStale, "DAG: def / assignment symbols, never-run cell is not stale");
        var down = CellDag.TransitiveDownstream(a.Id, g, cells);
        Check(down.SequenceEqual(new[] { b.Id, c.Id }), "DAG: transitive downstream of #1 is b, c in notebook order");
    }

    // â”€â”€ notebook files â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    static NbDoc Sample()
    {
        var doc = new NbDoc { Name = "Round Trip" };
        doc.Cells.Add(new NbCell { Type = "Markdown", Content = "# Title\nSome *text* with $x^2$." });
        doc.Cells.Add(new NbCell { Type = "Code", Language = "Python", Content = "x = 1\nprint(x)", Output = "1", ExecCount = 3, ColorTheme = "Blue", Collapsed = true, AiRole = "bug_hunter" });
        doc.Cells.Add(new NbCell { Type = "Code", Language = "SQL", Content = "SELECT 1;" });
        doc.Cells.Add(new NbCell { Type = "Agent", Content = "à¸ªà¸£à¸¸à¸›à¸‚à¹‰à¸­à¸¡à¸¹à¸¥à¹ƒà¸«à¹‰à¸«à¸™à¹ˆà¸­à¸¢", AgentMode = false });
        return doc;
    }

    static void FileTests(string root)
    {
        var doc = Sample();
        string ipynb = Path.Combine(root, "rt.ipynb");
        NbFormats.SaveIpynb(doc, ipynb);
        var back = NbFormats.Load(ipynb);
        Check(back.Cells.Count == 4 && back.Cells[0].Type == "Markdown" && back.Cells[1].Content == "x = 1\nprint(x)" && back.Cells[1].Output == "1", ".ipynb: cells, sources and stream output round-trip");
        Check(back.Cells[2].Language == "SQL" && back.Cells[1].ExecCount == 3, ".ipynb: per-cell language metadata and execution_count survive");
        var o = DJ.Obj(File.ReadAllText(ipynb));
        Check(o != null && Convert.ToInt32(o["nbformat"]) == 4 && DJ.Child(DJ.Child(o, "metadata"), "kernelspec") != null, ".ipynb: nbformat 4 with a python3 kernelspec (opens in Jupyter / Colab)");

        string py = NbFormats.ToPy(doc);
        Check(py.Contains("# %% [markdown]\n# # Title") && py.Contains("# %% [python]\nx = 1\nprint(x)") && py.Contains("# %% [agent]"), ".py export: # %% cell markers, markdown as comments");
        var fromPy = NbFormats.FromPy(py, "rt.py");
        Check(fromPy.Cells.Any(c => c.Type == "Markdown" && c.Content.StartsWith("# Title")) && fromPy.Cells.Any(c => c.Type == "Code" && c.Content == "x = 1\nprint(x)"), ".py import: markers split cells back");

        string mcnb = Path.Combine(root, "nb.mcnb");
        File.WriteAllText(mcnb, "{\"format\":\"mcnb\",\"version\":1,\"name\":\"Legacy\",\"cells\":[{\"type\":\"Code\",\"language\":\"Julia\",\"content\":\"println(1)\",\"output\":\"1\",\"execution_count\":2,\"color_theme\":\"Green\",\"tag\":\"setup\",\"is_collapsed\":false,\"use_custom_color\":true,\"custom_color\":{\"red\":0.1,\"green\":0.2,\"blue\":0.3,\"opacity\":0.4}}]}");
        var legacy = NbFormats.Load(mcnb);
        Check(legacy.Name == "Legacy" && legacy.Cells[0].Language == "Julia" && legacy.Cells[0].Tag == "setup" && legacy.Cells[0].UseCustomColor && Math.Abs(legacy.Cells[0].CustomColor.Blue - 0.3) < 1e-9, ".mcnb: MicroCode native JSON with tags and custom colours");

        string mic = Path.Combine(root, "rt.mic");
        NbFormats.SaveMic(doc, mic);
        var raw = File.ReadAllBytes(mic);
        Check(raw.Length > 12 && Encoding.ASCII.GetString(raw, 0, 4) == "bvx-" && Encoding.ASCII.GetString(raw, raw.Length - 4, 4) == "bvx$", ".mic: LZFSE container (stored block + end marker) that NSData.decompressed(.lzfse) reads");
        var json = DJ.Obj(Encoding.UTF8.GetString(Lzfse.Decode(raw)));
        var firstCell = DJ.Arr(json, "cells")[1] as Dictionary<string, object>;
        Guid g;
        object created = null;
        if (json != null) json.TryGetValue("createdAt", out created);
        bool numericDate = created is decimal || created is double || created is int || created is long;
        Check(json != null && Guid.TryParse(DJ.Str(json, "id"), out g) && DJ.Str(json, "id") == DJ.Str(json, "id").ToUpperInvariant() && numericDate, ".mic: MicNotebook JSON (upper-case UUID, Swift reference-date timestamps)");
        Check(firstCell != null && DJ.Str(firstCell, "colorTheme") == "Blue" && true.Equals(firstCell["isCollapsed"]) && Convert.ToInt32(firstCell["executionCount"]) == 3 && DJ.Child(firstCell, "aiSelection") != null && DJ.Str(DJ.Child(firstCell, "aiSelection"), "subAgentRole") == "bug_hunter", ".mic: MicCell fields the Mac decoder requires (colorTheme, isCollapsed, generatedCode, aiSelection)");
        var micBack = NbFormats.Load(mic);
        Check(micBack.Cells.Count == 4 && micBack.Cells[3].Type == "Agent" && !micBack.Cells[3].AgentMode && micBack.Cells[3].Content == "à¸ªà¸£à¸¸à¸›à¸‚à¹‰à¸­à¸¡à¸¹à¸¥à¹ƒà¸«à¹‰à¸«à¸™à¹ˆà¸­à¸¢" && micBack.FilePath == mic, ".mic: loads back (agent cell, Ask mode, Thai text) and binds Quick Save to the file");
    }

    // â”€â”€ LZFSE decoder â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    static byte[] Block(string magic, params byte[][] parts)
    {
        var ms = new MemoryStream();
        ms.Write(Encoding.ASCII.GetBytes(magic), 0, 4);
        foreach (var p in parts) ms.Write(p, 0, p.Length);
        return ms.ToArray();
    }

    static void LzfseTests(string root)
    {
        // hand-assembled LZVN stream for "abcabcabcXYZ": small literal "abc", small-distance match (L=0, M=6, D=3), small literal "XYZ", end of stream
        var lzvn = new byte[] { 0xE3, (byte)'a', (byte)'b', (byte)'c', 0x18, 0x03, 0xE3, (byte)'X', (byte)'Y', (byte)'Z', 0x06, 0, 0, 0, 0, 0, 0, 0 };
        var stream = Block("bvxn", BitConverter.GetBytes((uint)12), BitConverter.GetBytes((uint)lzvn.Length), lzvn).Concat(Encoding.ASCII.GetBytes("bvx$")).ToArray();
        string text = null;
        try { text = Encoding.ASCII.GetString(LzfseDecoder.Decode(stream)); } catch (Exception ex) { text = ex.Message; }
        Check(text == "abcabcabcXYZ", "LZFSE: LZVN block (literal + overlapping match) decodes (" + text + ")");
        var stored = Block("bvx-", BitConverter.GetBytes((uint)5), Encoding.ASCII.GetBytes("hello")).Concat(stream).ToArray();
        try { text = Encoding.ASCII.GetString(LzfseDecoder.Decode(stored)); } catch (Exception ex) { text = ex.Message; }
        Check(text == "helloabcabcabcXYZ", "LZFSE: stored block followed by an LZVN block whose match stays inside its own output");
        bool threw = false;
        try { LzfseDecoder.Decode(Encoding.ASCII.GetBytes("bvxZgarbage")); } catch (InvalidDataException) { threw = true; }
        Check(threw, "LZFSE: unknown block magic is rejected with InvalidDataException");
        threw = false;
        try { LzfseDecoder.Decode(Block("bvx-", BitConverter.GetBytes((uint)50), Encoding.ASCII.GetBytes("short"))); } catch (InvalidDataException) { threw = true; }
        Check(threw, "LZFSE: truncated stored block is rejected");
    }

    // â”€â”€ warm Python kernel â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    static KernelOutcome Run(NbPythonKernel k, string code, int timeoutMs)
    {
        KernelOutcome got = null;
        k.Execute(code, "cell_test_run1", null, o => got = o);
        Pump(() => got != null, timeoutMs);
        return got;
    }

    static void KernelTests()
    {
        if (!Has("python", "--version")) { Console.WriteLine("SKIP  kernel tests (python not on PATH)"); return; }
        var k = NbPythonKernel.For("kernel-test");
        k.Start();
        Pump(() => k.Status == "Idle", 20000);
        Check(k.Status == "Idle" && k.Version.Length > 0, "kernel: starts and reports the interpreter version (" + k.Version + ")");
        var o = Run(k, "x = 41\nprint('side effect')\nx + 1", 20000);
        Check(o != null && !o.HadError && o.Text == "side effect\n42", "kernel: stdout then the value of the last expression (" + (o == null ? "timeout" : o.Text) + ")");
        Check(k.Variables.Any(v => v.Name == "x" && v.TypeName == "int"), "kernel: live variables reported after the cell");
        o = Run(k, "x * 2", 20000);
        Check(o != null && o.Text == "82", "kernel: state persists between cells");
        o = Run(k, "def f():\n    return 1 / 0\nf()", 20000);
        Check(o != null && o.HadError && o.Text.Contains("ZeroDivisionError") && o.Text.Contains("<cell>") && !o.Text.Contains("microcode_nb_kernel"), "kernel: traceback limited to the cell's own frames");
        Check(o != null && o.Telemetry != null && o.Telemetry.DurationMs >= 0, "kernel: per-cell telemetry");

        string streamed = null;
        KernelOutcome slow = null;
        k.Execute("import time\nfor i in range(3):\n    print('tick', i, flush=True)\n    time.sleep(0.3)", "cell_test_run2", s => streamed = s, r => slow = r);
        Pump(() => streamed != null && streamed.Contains("tick 0") && slow == null, 8000);
        Check(streamed != null && streamed.Contains("tick 0") && slow == null, "kernel: output streams while the cell is still running");
        Pump(() => slow != null, 10000);

        KernelOutcome stopped = null;
        k.Execute("import time\nwhile True:\n    time.sleep(0.05)", "cell_test_run3", null, r => stopped = r);
        Pump(() => false, 800);
        k.Interrupt();
        Pump(() => stopped != null, 8000);
        Check(stopped != null && stopped.Text.Contains("Interrupted"), "kernel: Interrupt stops a running cell (KeyboardInterrupt)");
        o = Run(k, "x", 10000);
        Check(o != null && o.Text == "41", "kernel: variables survive an interrupt");

        o = Run(k, "open('figure_out.svg', 'w').write('<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"4\" height=\"4\"/>')\nNone", 10000);
        Check(o != null && o.Files.Any(f => f.EndsWith("figure_out.svg", StringComparison.OrdinalIgnoreCase)), "kernel: rich files the cell writes into the working directory become outputs");

        if (Has("python", "-c \"import pandas\""))
        {
            o = Run(k, "import pandas as pd\ndf = pd.DataFrame({'a': [1, 2, 3], 'b': [0.5, None, 2.5], 's': ['x', 'y', 'z']})\ndf", 60000);
            var df = o == null ? null : o.DataFrame;
            Check(df != null && df.VariableName == "df" && df.TotalRows == 3 && df.Columns.SequenceEqual(new[] { "a", "b", "s" }) && df.Rows.Count == 3, "kernel: a DataFrame result becomes the inline grid payload (pandas import does not deadlock)");
            Check(df != null && df.Stats["b"].NullCount == 1 && df.Stats["a"].MaxVal == 3 && df.CsvExportPath != null && File.Exists(df.CsvExportPath), "kernel: column stats (nulls, min/max) and the CSV export");
            Check(k.Variables.Any(v => v.Name == "df" && v.TypeName == "DataFrame" && v.Columns.Contains("s")), "kernel: DataFrame variable with its columns in the inspector");
            o = Run(k, NbRunner.SqlScript("SELECT a, s FROM df WHERE a > 1;", out bool_dummy), 20000);
            Check(o != null && o.DataFrame != null && o.DataFrame.TotalRows == 2, "SQL cell: queries a live DataFrame through sqlite (" + (o == null ? "timeout" : o.Text) + ")");
        }
        else Console.WriteLine("SKIP  pandas tests (pandas not installed)");

        k.Restart();
        Pump(() => k.Status == "Idle", 20000);
        o = Run(k, "'x' in globals()", 10000);
        Check(o != null && o.Text == "False", "kernel: Restart clears the namespace");
        k.Kill(null);
    }
    static bool bool_dummy;

    // â”€â”€ polyglot cells â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    static void RunnerTests()
    {
        NbRunner.Result r = null;
        NbRunner.Run(new NbCell { Language = "Ardium", Content = "fn main() {}" }, "cell_t", null, x => r = x);
        Pump(() => r != null, 5000);
        Check(r != null && r.HadError && r.Output.Contains("macOS"), "Ardium cell: honest 'Mac only' error instead of a fake run");
        if (Has("g++", "--version"))
        {
            r = null;
            NbRunner.Run(new NbCell { Language = "C++", Content = "#include <iostream>\nint main(){ std::cout << \"sum=\" << 2+3 << std::endl; }" }, "cell_t2", null, x => r = x);
            Pump(() => r != null, 120000);
            Check(r != null && !r.HadError && r.Output.Contains("sum=5"), "C++ cell: compiled with g++ and run (" + (r == null ? "timeout" : r.Output) + ")");
        }
        else Console.WriteLine("SKIP  C++ cell (g++ not on PATH)");
        r = null;
        NbRunner.Run(new NbCell { Language = "Rust", Content = "fn main(){}" }, "cell_t3", null, x => r = x);
        Pump(() => r != null, 35000);
        Check(r != null && (r.Output.Contains("rustc") || !r.HadError), "Rust cell: runs, or names the missing rustc toolchain");
    }

    // â”€â”€ live NotebookView + agent cell tools â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    static string Tool(string name, Dictionary<string, object> args)
    {
        var step = new ToolStep { Name = name };
        return CellTools.Extension.Execute(name, args, step, CancellationToken.None);
    }

    static void ViewAndToolTests()
    {
        var doc = new NbDoc { Name = "Tools" };
        doc.Cells.Add(new NbCell { Content = "value = 21" });
        NbStore.Seed = new List<NbDoc> { doc };
        NbStore.ActiveId = doc.Id;
        var win = new Window { Width = 1300, Height = 860, Left = -20000, Top = -20000, ShowActivated = false, ShowInTaskbar = false };
        var view = new NotebookView(AppState.Shared);
        win.Content = view;
        win.Show();
        Pump(() => view.IsLoaded, 5000);
        Check(NotebookView.Current == view, "view: Cell Mode registers itself for the agent tools");
        string list = Tool("cell_list", new Dictionary<string, object>());
        Check(list.Contains("Notebook: Tools (1 cells") && list.Contains("Cell #1"), "cell_list: lists the sheet");
        string created = Tool("cell_create", new Dictionary<string, object> { { "code", "print(value * 2)" }, { "language", "py" } });
        Check(created.StartsWith("Created Cell #2") && doc.Cells.Count == 2 && doc.Cells[1].Language == "Python", "cell_create: appends a Python cell (" + created + ")");
        string upd = Tool("cell_update", new Dictionary<string, object> { { "cell_number", 2 }, { "code", "print(value * 3)" }, { "tag", "report" } });
        Check(upd.StartsWith("Updated Cell #2") && doc.Cells[1].Tag == "report" && doc.Cells[1].PendingDiffOld == "print(value * 2)" && doc.Cells[1].Versions.Count == 1, "cell_update: edits with an AI diff baseline and a version snapshot");
        string read = Tool("cell_read", new Dictionary<string, object> { { "cell_number", 2 } });
        Check(read.Contains("print(value * 3)") && read.Contains("Tag: report"), "cell_read: returns code and tag");
        string bad = Tool("cell_read", new Dictionary<string, object> { { "cell_number", 9 } });
        Check(bad.StartsWith("Error:") && bad.Contains("1...2"), "cell_read: out-of-range cell number is an error the model can read");

        if (Has("python", "--version"))
        {
            // run cell 1 then 2 from a worker thread (the tools block until the cell finishes) while this thread pumps the UI
            string r1 = null, r2 = null;
            Task.Run(() => { r1 = Tool("cell_run", new Dictionary<string, object> { { "cell_number", 1 } }); r2 = Tool("cell_run", new Dictionary<string, object> { { "cell_number", 2 } }); });
            Pump(() => r2 != null, 60000);
            Check(r1 != null && r1.Contains("Cell #1 [1]"), "cell_run: executes cell #1 in the warm kernel (" + r1 + ")");
            Check(r2 != null && r2.Contains("Output:\n63"), "cell_run: cell #2 sees cell #1's variables (" + r2 + ")");
            Check(doc.Cells[1].ExecCount == 2 && doc.Cells[1].Output == "63", "view: execution count and output recorded on the cell");
        }
        string del = Tool("cell_delete", new Dictionary<string, object> { { "cell_number", 2 } });
        Check(del.StartsWith("Deleted Cell #2") && doc.Cells.Count == 1, "cell_delete: removes the cell");
        Check(Tool("shell", new Dictionary<string, object>()) == null, "tool extension: leaves non-cell tools to the standard toolbox");
        win.Close();
        NbStore.Seed = null;
    }
}
