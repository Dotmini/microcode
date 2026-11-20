// Port of NotebookView (Cell Mode): Cell Sheets sidebar, 28pt toolbar, cell cards, persistent Python kernel, notebook agent panel.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using MicroCode.Core;
using MicroCode.Editor;
using MicroCode.UI;

namespace MicroCode.Views
{
    public class NbCell
    {
        public string Id = Guid.NewGuid().ToString(), Type = "Code", Language = "Python", Content = "", Output = "", Error = "", Tag = "";
        public List<string> Images = new List<string>();
        public int ExecCount;
        [ScriptIgnore] public bool IsExecuting;
    }

    public class NbDoc
    {
        public string Id = Guid.NewGuid().ToString(), Name = "Cell Sheet 1";
        public List<NbCell> Cells = new List<NbCell>();
        public List<string> DataFiles = new List<string>();
    }

    public static class NbStore
    {
        public static List<NbDoc> Docs = new List<NbDoc>();
        public static string ActiveId;
        public static List<NbDoc> Seed;      // snapshot/test hook: in-memory notebooks, never persisted
        static bool ReadOnly { get { return Seed != null; } }
        static string FilePath { get { return Path.Combine(Defaults.Dir, "notebooks.json"); } }

        public static string DefaultCode(string lang)
        {
            switch (lang)
            {
                case "Python": return "# Your Python code here\nprint('Hello, World!')";
                case "R": return "# Your R code here\nprint('Hello, World!')";
                case "Julia": return "# Your Julia code here\nprintln(\"Hello, Julia!\")";
                case "SQL": return "-- Your SQL query here\nSELECT 'Hello, World!';";
                default: return "// Your " + lang + " code here";
            }
        }

        public static void Load()
        {
            if (Seed != null) { Docs = Seed; if (ActiveId == null) ActiveId = Docs[0].Id; return; }
            try { if (File.Exists(FilePath)) Docs = new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Deserialize<List<NbDoc>>(Defaults.ReadShared(FilePath)) ?? new List<NbDoc>(); } catch { Docs = new List<NbDoc>(); }
            if (Docs.Count == 0) Docs.Add(NewDoc("Cell Sheet 1"));
            if (ActiveId == null || !Docs.Any(d => d.Id == ActiveId)) ActiveId = Docs[0].Id;
        }

        public static NbDoc NewDoc(string name)
        {
            var d = new NbDoc { Name = name };
            d.Cells.Add(new NbCell { Content = DefaultCode("Python") });
            return d;
        }

        public static void Save()
        {
            if (ReadOnly) return;
            try { Defaults.WriteAtomic(FilePath, new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Serialize(Docs)); } catch { }
        }

        public static NbDoc Active { get { return Docs.FirstOrDefault(d => d.Id == ActiveId) ?? Docs.FirstOrDefault(); } }
    }

    /// <summary>Persistent Python kernel: one interpreter keeps globals across cells (Jupyter-like), echoes the value of a
    /// trailing expression and saves matplotlib figures as PNGs. JSON-lines protocol over stdin/stdout (ASCII-escaped).</summary>
    public class PythonKernel
    {
        const string Driver = @"import sys, os, io, ast, json, traceback, contextlib, tempfile
os.environ.setdefault('MPLBACKEND', 'Agg')
G = {'__name__': '__main__'}
N = [0]
def figures():
    out = []
    try:
        if 'matplotlib.pyplot' in sys.modules:
            plt = sys.modules['matplotlib.pyplot']
            for num in plt.get_fignums():
                N[0] += 1
                p = os.path.join(tempfile.gettempdir(), 'microcode_fig_%d_%d.png' % (os.getpid(), N[0]))
                plt.figure(num).savefig(p, dpi=144, bbox_inches='tight')
                out.append(p)
            plt.close('all')
    except Exception:
        pass
    return out
def run(code):
    out, err, ok = io.StringIO(), io.StringIO(), True
    try:
        tree = ast.parse(code, '<cell>', 'exec')
        last = None
        if tree.body and isinstance(tree.body[-1], ast.Expr):
            last = ast.Expression(tree.body.pop().value)
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            exec(compile(tree, '<cell>', 'exec'), G)
            if last is not None:
                v = eval(compile(last, '<cell>', 'eval'), G)
                if v is not None:
                    print(repr(v))
    except SystemExit:
        pass
    except BaseException:
        ok = False
        et, ev, tb = sys.exc_info()
        while tb is not None and tb.tb_frame.f_code.co_filename != '<cell>':
            tb = tb.tb_next
        err.write(''.join(traceback.format_exception(et, ev, tb)))
    return out.getvalue(), err.getvalue(), ok
sys.__stdout__.write(json.dumps({'ready': True, 'version': sys.version.split()[0]}) + '\n'); sys.__stdout__.flush()
for line in sys.stdin:
    try:
        req = json.loads(line)
    except Exception:
        continue
    o, e, ok = run(req.get('code', ''))
    sys.__stdout__.write(json.dumps({'id': req.get('id'), 'out': o, 'err': e, 'ok': ok, 'figs': figures()}) + '\n')
    sys.__stdout__.flush()
";
        Process _p;
        readonly JavaScriptSerializer _js = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
        readonly Dictionary<string, Action<Dictionary<string, object>>> _pending = new Dictionary<string, Action<Dictionary<string, object>>>();
        public string Status = "Not Started", Version = "";
        public event Action StatusChanged;

        void SetStatus(string s) { Status = s; var d = Application.Current.Dispatcher; d.BeginInvoke(new Action(() => { if (StatusChanged != null) StatusChanged(); })); }

        public void Start()
        {
            Stop();
            string script = Path.Combine(Path.GetTempPath(), "microcode_kernel.py");
            File.WriteAllText(script, Driver);
            foreach (var exe in new[] { "python", "py" })
            {
                try
                {
                    var psi = new ProcessStartInfo(exe, (exe == "py" ? "-3 " : "") + "-u \"" + script + "\"")
                    {
                        UseShellExecute = false, RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true,
                        StandardOutputEncoding = Encoding.UTF8, WorkingDirectory = AppState.Shared.WorkspaceFolder ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
                    };
                    psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
                    var p = new Process { StartInfo = psi, EnableRaisingEvents = true };
                    p.OutputDataReceived += (s, e) => OnLine(e.Data);
                    p.ErrorDataReceived += (s, e) => { };
                    p.Exited += delegate { if (_p == p) SetStatus("Dead"); };
                    p.Start();
                    p.BeginOutputReadLine(); p.BeginErrorReadLine();
                    _p = p;
                    SetStatus("Starting…");
                    return;
                }
                catch { }
            }
            SetStatus("Python not found");
        }

        void OnLine(string line)
        {
            if (string.IsNullOrEmpty(line)) return;
            Dictionary<string, object> o;
            try { o = _js.Deserialize<Dictionary<string, object>>(line); } catch { return; }
            if (o.ContainsKey("ready")) { Version = Convert.ToString(o["version"]); SetStatus("Idle"); return; }
            string id = Convert.ToString(o.ContainsKey("id") ? o["id"] : "");
            Action<Dictionary<string, object>> cb;
            lock (_pending) { if (_pending.TryGetValue(id, out cb)) _pending.Remove(id); }
            bool busy; lock (_pending) busy = _pending.Count > 0;
            SetStatus(busy ? "Busy" : "Idle");
            if (cb != null) Application.Current.Dispatcher.BeginInvoke(new Action(() => cb(o)));
        }

        static string Ascii(string json)
        {
            var sb = new StringBuilder(json.Length);
            foreach (char c in json) { if (c > 127) sb.Append("\\u").Append(((int)c).ToString("x4")); else sb.Append(c); }
            return sb.ToString();
        }

        public void Execute(string code, Action<Dictionary<string, object>> done)
        {
            if (_p == null || _p.HasExited) Start();
            if (_p == null) { done(new Dictionary<string, object> { { "out", "" }, { "err", "Python was not found on PATH. Install Python 3 from python.org and restart the kernel." }, { "ok", false } }); return; }
            string id = Guid.NewGuid().ToString("N");
            lock (_pending) _pending[id] = done;
            SetStatus("Busy");
            try { _p.StandardInput.WriteLine(Ascii(_js.Serialize(new Dictionary<string, object> { { "id", id }, { "code", code } }))); _p.StandardInput.Flush(); }
            catch (Exception ex) { lock (_pending) _pending.Remove(id); done(new Dictionary<string, object> { { "out", "" }, { "err", ex.Message }, { "ok", false } }); }
        }

        public void Stop()
        {
            try { if (_p != null && !_p.HasExited) _p.Kill(); } catch { }
            _p = null;
            List<Action<Dictionary<string, object>>> waiting;
            lock (_pending) { waiting = _pending.Values.ToList(); _pending.Clear(); }
            foreach (var w in waiting) { var cb = w; Application.Current.Dispatcher.BeginInvoke(new Action(() => cb(new Dictionary<string, object> { { "out", "" }, { "err", "KeyboardInterrupt: kernel restarted" }, { "ok", false } }))); }
            SetStatus("Not Started");
        }
    }

    public class NotebookView : Grid
    {
        readonly AppState _app;
        static readonly PythonKernel Kernel = new PythonKernel();
        public static void ShutdownKernel() { try { Kernel.Stop(); } catch { } }
        readonly Border _sidebar = new Border(), _toolbar = new Border(), _cellsHost = new Border(), _aiHost = new Border();
        readonly ScrollViewer _scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        readonly Dictionary<string, CodeEditorView> _editors = new Dictionary<string, CodeEditorView>();
        bool _showSidebar = true, _showAI = ForceShowAI || Defaults.Bool("notebook.showAIPanel", false);
        public static bool ForceShowAI; // snapshot/test hook
        double _sidebarW = Defaults.Num("notebook.sidebarWidth", 232), _aiW = Defaults.Num("notebook.aiPanelWidth", 356);
        string _selected;
        int _totalExec;
        NotebookAIPanel _ai;

        static readonly string[] Langs = { "Python", "R", "Julia", "SQL", "Rust", "Go", "C++", "Java", "C#", "JavaScript" };

        public NotebookView(AppState app)
        {
            _app = app;
            NbStore.Load();
            var t = Theme.Current;
            Background = t.EditorBackground;
            ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Children.Add(_sidebar);
            var center = new Grid();
            center.RowDefinitions.Add(new RowDefinition { Height = new GridLength(28) });
            center.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1) });
            center.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            center.Children.Add(_toolbar);
            var div = V.Line(t.Separator, true); SetRow(div, 1); center.Children.Add(div);
            _scroll.Content = _cellsHost;
            SetRow(_scroll, 2); center.Children.Add(_scroll);
            SetColumn(center, 1); Children.Add(center);
            SetColumn(_aiHost, 2); Children.Add(_aiHost);
            Kernel.StatusChanged += RenderSidebar;
            if (Kernel.Status == "Not Started") Kernel.Start();
            var doc = NbStore.Active;
            _selected = doc.Cells.Count > 0 ? doc.Cells[0].Id : null;
            RenderAll();
            PreviewKeyDown += OnKey;
            if (AutoRunAll) Loaded += delegate { Dispatcher.BeginInvoke(new Action(RunAll), System.Windows.Threading.DispatcherPriority.ApplicationIdle); };
        }

        public static bool AutoRunAll;

        NbDoc Doc { get { return NbStore.Active; } }

        void RenderAll() { RenderSidebar(); RenderToolbar(); RenderCells(); RenderAI(); }

        // MARK: notebookSidebar
        void RenderSidebar()
        {
            var t = Theme.Current;
            if (!_showSidebar) { _sidebar.Child = null; return; }
            var plus = V.Button(V.Size(V.Box(Sym.Icon("plus", 10.5, t.Secondary, FontWeights.Medium), V.P(0), t.P(0.06), 4.5), 22, 20), () => { var d = NbStore.NewDoc("Cell Sheet " + (NbStore.Docs.Count + 1)); NbStore.Docs.Add(d); NbStore.ActiveId = d.Id; NbStore.Save(); RenderAll(); });
            plus.ToolTip = "New Cell Sheet";
            var header = V.Size(V.Box(V.H(6, Sym.Icon("doc.text.fill", 11, t.SysOrange), V.T("Cell Sheets", 11.5, FontWeights.SemiBold, t.Primary), V.Sp(), plus), V.P(10, 0), t.PanelBackground, 0), double.NaN, 28);

            var body = V.VLead(12); body.Align = Cross.Stretch;
            var list = V.VLead(4); list.Align = Cross.Stretch;
            foreach (var d in NbStore.Docs)
            {
                var doc = d;
                bool active = d.Id == NbStore.ActiveId;
                var del = V.Button(Sym.Icon("xmark.circle", 11, t.Secondary), () => { if (NbStore.Docs.Count > 1) { NbStore.Docs.Remove(doc); if (NbStore.ActiveId == doc.Id) NbStore.ActiveId = NbStore.Docs[0].Id; NbStore.Save(); RenderAll(); } });
                del.Opacity = 0;
                var row = V.Button(V.Box(V.H(8, Sym.Icon("doc.text", 13, active ? t.SysOrange : t.Secondary),
                    V.Flex(V.VLead(2, V.T(d.Name, 12, active ? FontWeights.SemiBold : FontWeights.Normal, t.Primary), V.T(d.Cells.Count + " cells", 10, FontWeights.Normal, t.Secondary))), del),
                    V.P(8, 6), active ? t.A(0.15) : Brushes.Transparent, 6), () => { NbStore.ActiveId = doc.Id; _selected = doc.Cells.Count > 0 ? doc.Cells[0].Id : null; RenderAll(); });
                row.OnState = b => del.Opacity = b.IsHover ? 1 : 0;
                list.Children.Add(row);
            }
            body.Children.Add(list);

            // kernel card
            string st = Kernel.Status;
            Brush dot = st == "Idle" ? t.SysGreen : st == "Busy" ? t.SysOrange : st.StartsWith("Starting") ? t.SysYellow : t.SysRed;
            var env = V.Button(V.Box(V.H(6, Sym.Icon("cpu.fill", 10, t.Secondary), V.Flex(V.T("System Python" + (Kernel.Version.Length > 0 ? " " + Kernel.Version : ""), 10.5, FontWeights.Normal, t.Primary)), Sym.Icon("chevron.down", 8, t.Secondary)), V.P(6), Theme.B(Theme.WithAlpha(t.Def.EditorBackground, 0.85)), 4), null);
            env.MenuItems = () => new List<MenuItemSpec> { new MenuItemSpec { Title = "System Python", Checked = true }, MenuItemSpec.Sep(), MenuItemSpec.Item("Manage Environments...", "slider.horizontal.3", () => SettingsWindow.Show(_app)) };
            var kernel = V.VLead(8,
                V.Self(V.H(6, V.Dot(8, dot), V.T("Python 3", 12, FontWeights.Medium, t.Primary), V.Sp(), V.T(st, 10.5, FontWeights.Normal, t.Secondary)), Cross.Stretch),
                V.Self(V.VLead(2, V.Self(V.H(4, V.T("LOCAL / WINDOWS", 9, FontWeights.Bold, t.Secondary), V.Sp(), V.Box(V.T("Default", 8, FontWeights.Medium, t.Accent), V.P(4, 1), t.A(0.15), 3)), Cross.Stretch), V.Self(env, Cross.Stretch)), Cross.Stretch));
            kernel.Align = Cross.Stretch;
            body.Children.Add(V.Box(kernel, V.P(10), Theme.B(Theme.WithAlpha(t.Def.EditorBackground, 0.6)), 8, t.P(0.08), 1));

            // data files
            var addData = V.Button(Sym.Icon("plus.circle", 11, t.Secondary), AddDataFile);
            addData.ToolTip = "Import Files…";
            var data = V.VLead(8, V.Self(V.H(4, V.T("Data Files", 11, FontWeights.SemiBold, t.Secondary), V.Sp(), addData), Cross.Stretch));
            data.Align = Cross.Stretch;
            if (Doc.DataFiles.Count == 0) data.Children.Add(V.Box(V.Vs(4, Sym.Icon("doc.badge.plus", 16, t.S(0.6)), V.T("No data files", 10.5, FontWeights.Normal, t.Secondary)), V.P(0, 12), null, 0));
            foreach (var f in Doc.DataFiles)
            {
                var file = f;
                var load = V.Button(Sym.Icon("arrow.down.to.line", 10, t.Secondary), () => InsertLoader(file));
                load.ToolTip = "Insert loader cell";
                data.Children.Add(V.H(6, Sym.Icon("doc.text", 10, t.Accent), V.Flex(V.T(Path.GetFileName(file), 10.5, FontWeights.Normal, t.Primary)), load));
            }
            body.Children.Add(data);
            body.Children.Add(V.VLead(8, V.Self(V.H(4, V.T("Shared Data", 11, FontWeights.SemiBold, t.Secondary), V.Sp(), Sym.Icon("arrow.clockwise", 10, t.Secondary)), Cross.Stretch),
                V.Self(V.Box(V.T("No shared data", 10.5, FontWeights.Normal, t.Secondary), V.P(0, 8), null, 0), Cross.Center)));

            // actions
            Func<string, string, Brush, Action, UIElement> act = (icon, label, fg, a) =>
            {
                var b = V.Button(V.Box(V.H(8, Sym.Icon(icon, 11, fg), V.T(label, 12, FontWeights.Normal, fg), V.Sp()), V.P(6, 5), Brushes.Transparent, 5), a);
                b.OnState = x => ((Border)x.Child).Background = x.IsHover ? t.P(0.06) : Brushes.Transparent;
                return b;
            };
            var actions = V.VLead(2, act("play.fill", "Run All", t.Primary, RunAll), act("trash", "Clear Outputs", t.Primary, ClearOutputs), act("arrow.clockwise", "Restart Kernel", t.SysOrange, () => { Kernel.Start(); }));
            actions.Align = Cross.Stretch;
            body.Children.Add(V.Box(actions, V.P(4), t.P(0.03), 8, t.P(0.06), 1));

            var g = new Grid { Width = _sidebarW, Background = t.PanelBackground };
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(28) });
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1) });
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            g.Children.Add(header);
            var d1 = V.Line(t.Separator, true); SetRow(d1, 1); g.Children.Add(d1);
            var sv = new ScrollViewer { Content = V.Box(body, V.P(16), null, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            SetRow(sv, 2); g.Children.Add(sv);
            var handle = ResizeHandle(w => { _sidebarW = Math.Max(180, Math.Min(320, w)); g.Width = _sidebarW; Defaults.Set("notebook.sidebarWidth", _sidebarW); }, () => _sidebarW, true);
            var wrap = new DockPanel();
            DockPanel.SetDock(handle, Dock.Right); wrap.Children.Add(handle); wrap.Children.Add(g);
            _sidebar.Child = wrap;
        }

        UIElement ResizeHandle(Action<double> setWidth, Func<double> getWidth, bool leading)
        {
            var t = Theme.Current;
            var h = new Border { Width = 6, Background = Brushes.Transparent, Cursor = Cursors.SizeWE };
            var line = new Border { Width = 1, Background = t.Separator, HorizontalAlignment = HorizontalAlignment.Center };
            h.Child = line;
            double sx = 0, sw = 0;
            h.MouseLeftButtonDown += (s, e) => { sx = e.GetPosition(this).X; sw = getWidth(); h.CaptureMouse(); e.Handled = true; };
            h.MouseMove += (s, e) => { if (h.IsMouseCaptured) setWidth(sw + (leading ? 1 : -1) * (e.GetPosition(this).X - sx)); };
            h.MouseLeftButtonUp += delegate { h.ReleaseMouseCapture(); };
            h.MouseEnter += delegate { line.Background = t.A(0.6); };
            h.MouseLeave += delegate { line.Background = t.Separator; };
            return h;
        }

        // MARK: notebookToolbar (28pt)
        void RenderToolbar()
        {
            var t = Theme.Current;
            Func<string, string, bool, Action, string, Btn> pill = (icon, label, active, a, tip) =>
            {
                var h = V.H(4, Sym.Icon(icon, 10, active ? t.Primary : t.Secondary, FontWeights.Medium));
                if (label != null) h.Children.Add(V.T(label, 10, active ? FontWeights.SemiBold : FontWeights.Medium, active ? t.Primary : t.Secondary));
                var b = V.Button(V.Size(V.Box(h, V.P(6.5, 0), active ? t.P(0.12) : t.P(0.05), 5, active ? t.P(0.18) : t.P(0.08), 0.8), double.NaN, 21), a);
                ((Border)b.Child).VerticalAlignment = VerticalAlignment.Center;
                if (tip != null) b.ToolTip = tip;
                return b;
            };
            var side = V.Button(V.Size(V.Box(Sym.Icon("sidebar.left", 11, t.Secondary), V.P(0), Brushes.Transparent, 4), 24, 21), () => { _showSidebar = !_showSidebar; RenderSidebar(); });
            side.ToolTip = "Toggle Cell Sheets";
            var title = V.Box(V.T(Doc.Name, 11.5, FontWeights.SemiBold, t.Primary), V.P(5, 2), t.P(0.08), 4);
            var rename = V.Button(V.Size(V.Box(Sym.Icon("pencil", 9, t.Secondary, FontWeights.Medium), V.P(0), t.P(0.05), 4), 18, 18), () => { var n = Prompt.Ask("Rename Cell Sheet", "Name:", Doc.Name); if (!string.IsNullOrWhiteSpace(n)) { Doc.Name = n.Trim(); NbStore.Save(); RenderAll(); } });
            rename.ToolTip = "Rename Cell Sheet";
            var capsule = V.H(2,
                V.Tip(V.Button(V.Size(V.Box(Sym.Icon("plus", 10.5, t.Primary, FontWeights.SemiBold), V.P(0), Brushes.Transparent, 4), 24, 21), () => AddCell("Code", null)), "Add Code Cell"),
                V.Tip(V.Button(V.Size(V.Box(Sym.Icon("play.fill", 10, t.SysGreen), V.P(0), Brushes.Transparent, 4), 24, 21), () => { var c = SelectedCell(); if (c != null) RunCell(c, false); }), "Run Cell (Ctrl+Enter)"),
                V.Tip(V.Button(V.Size(V.Box(Sym.Icon("forward.fill", 10, t.Primary), V.P(0), Brushes.Transparent, 4), 24, 21), RunAll), "Run All"),
                V.Tip(V.Button(V.Size(V.Box(Sym.Icon("stop.fill", 9, t.SysRed), V.P(0), Brushes.Transparent, 4), 24, 21), () => Kernel.Start()), "Interrupt & Restart Kernel"));
            var bar = V.H(5.5, side, V.Size(V.Line(t.Separator, false), 1, 13), title, rename, V.Size(V.Line(t.Separator, false), 1, 13),
                pill("bolt", "DAG", false, null, "Reactive DAG Mode: Automatically re-run downstream dependent cells when an upstream variable changes"),
                V.Sp(),
                pill("memorychip", "Vars", false, () => { var c = AddCell("Code", "Python"); c.Content = "{k: type(v).__name__ for k, v in globals().items() if not k.startswith('_')}"; RenderCells(); RunCell(c, false); }, "Inspect live kernel variables"),
                V.Box(capsule, V.P(1), t.P(0.05), 6, t.P(0.08), 0.8),
                V.Size(V.Line(t.Separator, false), 1, 13),
                V.Tip(V.Box(V.Mono(_totalExec.ToString(), 10, FontWeights.Medium, t.Secondary), V.P(5.5, 2), t.P(0.05), 4), "Total Executions: " + _totalExec),
                pill("sidebar.right", "Agent", _showAI, () => { _showAI = !_showAI; Defaults.Set("notebook.showAIPanel", _showAI); RenderToolbar(); RenderAI(); }, "Toggle Notebook Agent Panel"));
            _toolbar.Child = V.Box(bar, V.P(10, 0), t.PanelBackground, 0);
        }

        // MARK: cells
        NbCell SelectedCell() { return Doc.Cells.FirstOrDefault(c => c.Id == _selected) ?? Doc.Cells.LastOrDefault(); }

        void RenderCells()
        {
            var t = Theme.Current;
            var list = V.Vs(12); list.Align = Cross.Center;
            double width = Math.Max(420, Math.Min(1000, (ActualWidth > 0 ? ActualWidth - (_showSidebar ? _sidebarW + 6 : 0) - (_showAI ? _aiW + 6 : 0) : 900) - 40));
            foreach (var c in Doc.Cells) list.Children.Add(CellCard(c, width));
            Func<string, string, Action, UIElement> add = (icon, label, a) =>
            {
                var b = V.Button(V.Box(V.H(6, Sym.Icon(icon, 11, t.Secondary), V.T(label, 12, FontWeights.Medium, t.Secondary)), V.P(16, 8), t.P(0.04), 8, t.P(0.08), 1), a);
                b.OnState = x => ((Border)x.Child).Background = x.IsHover ? t.P(0.08) : t.P(0.04);
                return b;
            };
            list.Children.Add(V.Box(V.H(16, add("plus", "Code", () => AddCell("Code", null)), add("doc.richtext", "Markdown", () => AddCell("Markdown", null)), add("sparkles", "Ask Agent", () => { _showAI = true; RenderToolbar(); RenderAI(); })), V.P(0, 20), null, 0));
            _cellsHost.Child = V.Box(list, V.P(0, 16), null, 0);
            // keep width responsive
            SizeChanged -= OnSize; SizeChanged += OnSize;
        }

        void OnSize(object s, SizeChangedEventArgs e) { if (Math.Abs(e.NewSize.Width - e.PreviousSize.Width) > 40) RenderCells(); }

        UIElement CellCard(NbCell c, double width)
        {
            var t = Theme.Current;
            bool sel = c.Id == _selected;
            var cell = c;
            // left gutter (46pt): execution count + run button
            string count = c.IsExecuting ? "[*]" : c.ExecCount > 0 ? "[" + c.ExecCount + "]" : "[ ]";
            var run = V.Button(Sym.Icon(c.IsExecuting ? "stop.circle.fill" : "play.circle.fill", 16, c.IsExecuting ? t.SysRed : t.SysGreen), () => { if (cell.IsExecuting) Kernel.Start(); else RunCell(cell, false); });
            run.ToolTip = c.IsExecuting ? "Interrupt" : "Run Cell (Ctrl+Enter)";
            var gutter = V.Size(V.Box(V.Vs(6, V.Mono(count, 10, FontWeights.Normal, t.Secondary), c.Type == "Code" ? run : null), V.P(0, 12, 0, 0), null, 0), 46, double.NaN);
            gutter.VerticalAlignment = VerticalAlignment.Top;

            // header: type badge, language badge, compute target, tag … actions
            Brush typeColor = c.Type == "Markdown" ? t.SysGreen : t.SysBlue;
            var typeBadge = V.Button(V.Box(V.T(c.Type, 9, FontWeights.Medium, typeColor), V.P(6, 2), Theme.B(Theme.WithAlpha(((SolidColorBrush)typeColor).Color, 0.16)), 4), null);
            typeBadge.MenuItems = () => new List<MenuItemSpec> { new MenuItemSpec { Title = "Code", Checked = cell.Type == "Code", Action = () => { cell.Type = "Code"; Changed(); } }, new MenuItemSpec { Title = "Markdown", Checked = cell.Type == "Markdown", Action = () => { cell.Type = "Markdown"; Changed(); } } };
            var header = V.H(6, typeBadge);
            if (c.Type == "Code")
            {
                Brush lc = LangColor(c.Language);
                var langBadge = V.Button(V.Box(V.H(4, Sym.Icon(LangIcon(c.Language), 10, lc), V.T(c.Language, 9, FontWeights.Medium, lc)), V.P(6, 2), Theme.B(Theme.WithAlpha(((SolidColorBrush)lc).Color, 0.2)), 4), null);
                langBadge.MenuItems = () => Langs.Select(l => new MenuItemSpec { Title = l, Checked = l == cell.Language, Action = () => { cell.Language = l; CodeEditorView ed; if (_editors.TryGetValue(cell.Id, out ed)) ed.SetLanguage(LangKey(l)); Changed(); } }).ToList();
                header.Children.Add(langBadge);
                header.Children.Add(V.Tip(V.Box(V.H(3, Sym.Icon("arrow.triangle.branch", 8.5, t.Secondary), V.T("Default", 9, FontWeights.Medium, t.Secondary)), V.P(5, 2), t.S(0.12), 4), "Per-Cell Compute Engine (Overrides default target for this cell)"));
            }
            header.Children.Add(V.Tip(V.Button(V.Box(V.H(3, Sym.Icon(c.Tag.Length == 0 ? "tag" : "tag.fill", 9, c.Tag.Length == 0 ? t.Secondary : t.Accent), V.T(c.Tag.Length == 0 ? "Tag" : c.Tag, 9, FontWeights.Medium, c.Tag.Length == 0 ? t.Secondary : t.Accent)), V.P(5.5, 2), (c.Tag.Length == 0 ? t.S(0.18) : t.A(0.18)), 4), () => { var n = Prompt.Ask("Cell Name-tag", "Tag:", cell.Tag); if (n != null) { cell.Tag = n.Trim(); Changed(); } }), "Name this cell for selective Run by Tag"));
            header.Children.Add(V.Sp());
            var acts = V.H(2,
                V.Tip(V.Button(Sym.Icon("arrow.up", 10, t.Secondary), () => Move(cell, -1)), "Move Up"),
                V.Tip(V.Button(Sym.Icon("arrow.down", 10, t.Secondary), () => Move(cell, 1)), "Move Down"),
                V.Tip(V.Button(Sym.Icon("doc.on.doc", 10, t.Secondary), () => { var dup = new NbCell { Type = cell.Type, Language = cell.Language, Content = cell.Content }; Doc.Cells.Insert(Doc.Cells.IndexOf(cell) + 1, dup); _selected = dup.Id; Changed(); }), "Duplicate"),
                V.Tip(V.Button(Sym.Icon("trash", 10, t.SysRed), () => { Doc.Cells.Remove(cell); _editors.Remove(cell.Id); if (_selected == cell.Id) _selected = null; Changed(); }), "Delete Cell"));
            acts.Opacity = sel ? 1 : 0;
            header.Children.Add(acts);

            var main = V.VLead(4, V.Self(V.Box(header, V.P(4, 8, 4, 2), null, 0), Cross.Stretch));
            main.Align = Cross.Stretch;
            if (c.Type == "Markdown" && !sel && c.Content.Trim().Length > 0)
            {
                var md = MarkdownView.Render(c.Content);
                ((Border)md).Padding = new Thickness(8, 4, 8, 8);
                main.Children.Add(md);
            }
            else
            {
                CodeEditorView ed;
                if (!_editors.TryGetValue(c.Id, out ed))
                {
                    ed = new CodeEditorView(c.Content, c.Type == "Markdown" ? "markdown" : LangKey(c.Language), Defaults.Num("cellFontSize", 13), UIFonts.Code("cellFontName", "SF Mono"));
                    ed.TextEdited += text => { cell.Content = text; SaveSoon(); UpdateHeight(ed); };
                    ed.Box.GotKeyboardFocus += delegate { if (_selected != cell.Id) { _selected = cell.Id; RenderCellsKeepFocus(cell); } };
                    _editors[c.Id] = ed;
                }
                if (ed.Parent is Decorator) ((Decorator)ed.Parent).Child = null;
                UpdateHeight(ed);
                var holder = new Border { Child = ed, CornerRadius = new CornerRadius(4), ClipToBounds = true, Margin = new Thickness(4) };
                main.Children.Add(holder);
            }
            if (c.Output.Length > 0 || c.Error.Length > 0 || c.Images.Count > 0)
            {
                main.Children.Add(V.Box(V.Line(t.Separator, true), V.P(8, 0), null, 0));
                var outs = V.VLead(6); outs.Align = Cross.Stretch;
                if (c.Output.Length > 0) outs.Children.Add(Selectable(c.Output.TrimEnd('\n'), t.EditorText));
                if (c.Error.Length > 0) outs.Children.Add(Selectable(c.Error.TrimEnd('\n'), t.SysRed));
                foreach (var img in c.Images)
                {
                    try
                    {
                        var bmp = new BitmapImage(); bmp.BeginInit(); bmp.CacheOption = BitmapCacheOption.OnLoad; bmp.UriSource = new Uri(img); bmp.EndInit();
                        var image = new Image { Source = bmp, Stretch = Stretch.Uniform, MaxHeight = 420, HorizontalAlignment = HorizontalAlignment.Left };
                        outs.Children.Add(V.Box(image, V.P(6), Brushes.White, 8));
                    }
                    catch { }
                }
                main.Children.Add(V.Box(outs, V.P(8), null, 0));
            }
            var row = V.H(0, gutter, V.Flex(V.Box(main, V.P(0, 0, 8, 8), null, 0)));
            row.Align = Cross.Start;
            var card = V.Box(row, V.P(0), t.ElevatedBackground, 12, sel ? t.A(0.9) : Theme.B(Theme.WithAlpha(t.IsDark ? Colors.White : Colors.Black, t.IsDark ? 0.12 : 0.1)), 1);
            card.Width = width;
            card.MouseLeftButtonDown += delegate { if (_selected != cell.Id) { _selected = cell.Id; RenderCellsKeepFocus(cell); } };
            return card;
        }

        static UIElement Selectable(string text, Brush fg)
        {
            return new TextBox { Text = text, IsReadOnly = true, BorderThickness = new Thickness(0), Background = Brushes.Transparent, Foreground = fg, FontFamily = UIFonts.Mono, FontSize = 12.5, TextWrapping = TextWrapping.Wrap, CaretBrush = Brushes.Transparent, Padding = new Thickness(0) };
        }

        void UpdateHeight(CodeEditorView ed)
        {
            int lines = Math.Max(2, ed.LineStarts.Count);
            ed.Height = Math.Min(560, lines * Math.Max(15, ed.LineHeight) + 18);
        }

        void RenderCellsKeepFocus(NbCell cell)
        {
            double off = _scroll.VerticalOffset;
            RenderCells();
            _scroll.ScrollToVerticalOffset(off);
            CodeEditorView ed;
            if (_editors.TryGetValue(cell.Id, out ed)) Dispatcher.BeginInvoke(new Action(() => ed.Focus2()), System.Windows.Threading.DispatcherPriority.Input);
        }

        System.Windows.Threading.DispatcherTimer _saveTimer;
        void SaveSoon()
        {
            if (_saveTimer == null) { _saveTimer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(600) }; _saveTimer.Tick += delegate { _saveTimer.Stop(); NbStore.Save(); }; }
            _saveTimer.Stop(); _saveTimer.Start();
        }

        void Changed() { NbStore.Save(); double off = _scroll.VerticalOffset; RenderSidebar(); RenderCells(); _scroll.ScrollToVerticalOffset(off); }

        NbCell AddCell(string type, string lang)
        {
            var cur = SelectedCell();
            string l = lang ?? (cur != null ? cur.Language : "Python");
            var c = new NbCell { Type = type, Language = l, Content = type == "Markdown" ? "## New Section\n" : NbStore.DefaultCode(l) };
            int i = cur != null ? Doc.Cells.IndexOf(cur) + 1 : Doc.Cells.Count;
            Doc.Cells.Insert(i, c);
            _selected = c.Id;
            Changed();
            return c;
        }

        void Move(NbCell c, int d)
        {
            int i = Doc.Cells.IndexOf(c), j = i + d;
            if (j < 0 || j >= Doc.Cells.Count) return;
            Doc.Cells.RemoveAt(i); Doc.Cells.Insert(j, c);
            Changed();
        }

        public void RunCell(NbCell c, bool advance)
        {
            if (c.Type != "Code") { _selected = c.Id; Changed(); return; }
            c.IsExecuting = true; c.Output = ""; c.Error = ""; c.Images.Clear();
            RenderCells();
            Action<string, string, bool, List<string>> finish = (o, e, ok, figs) =>
            {
                c.IsExecuting = false; c.Output = o ?? ""; c.Error = e ?? ""; c.Images = figs ?? new List<string>();
                c.ExecCount = ++_totalExec;
                NbStore.Save();
                double off = _scroll.VerticalOffset; RenderCells(); RenderToolbar(); _scroll.ScrollToVerticalOffset(off);
            };
            if (c.Language == "Python")
            {
                Kernel.Execute(c.Content, r =>
                {
                    var figs = r.ContainsKey("figs") && r["figs"] is System.Collections.ArrayList ? ((System.Collections.ArrayList)r["figs"]).Cast<object>().Select(Convert.ToString).ToList() : new List<string>();
                    finish(Convert.ToString(r.ContainsKey("out") ? r["out"] : ""), Convert.ToString(r.ContainsKey("err") ? r["err"] : ""), r.ContainsKey("ok") && true.Equals(r["ok"]), figs);
                });
            }
            else
            {
                // other languages: stateless run through the local toolchain (same runners as Code mode)
                string ext = c.Language == "R" ? "r" : c.Language == "Julia" ? "jl" : c.Language == "SQL" ? "sql" : c.Language == "Rust" ? "rs" : c.Language == "Go" ? "go" : c.Language == "C++" ? "cpp" : c.Language == "Java" ? "java" : c.Language == "C#" ? "cs" : "js";
                string dir = Path.Combine(Path.GetTempPath(), "MicroCodeCells"); Directory.CreateDirectory(dir);
                string file = Path.Combine(dir, (c.Language == "Java" ? "Main" : "cell") + "." + ext);
                File.WriteAllText(file, c.Content);
                string exe, args;
                if (!Runner.CommandFor(AppState.DetectLanguage(file), file, out exe, out args)) { finish("", "No local runtime configured for " + c.Language + ".", false, null); return; }
                Task.Factory.StartNew(() =>
                {
                    try
                    {
                        var p = Process.Start(new ProcessStartInfo(exe, args) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true, WorkingDirectory = dir, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 });
                        var o = p.StandardOutput.ReadToEndAsync(); var e = p.StandardError.ReadToEndAsync();
                        p.WaitForExit(120000);
                        return Tuple.Create(o.Result, e.Result, p.ExitCode == 0);
                    }
                    catch (Exception ex) { return Tuple.Create("", "Failed to start " + exe + ": " + ex.Message, false); }
                }).ContinueWith(tk => finish(tk.Result.Item1, tk.Result.Item2, tk.Result.Item3, null), TaskScheduler.FromCurrentSynchronizationContext());
            }
            if (advance)
            {
                int i = Doc.Cells.IndexOf(c);
                if (i == Doc.Cells.Count - 1) AddCell("Code", c.Language); else { _selected = Doc.Cells[i + 1].Id; RenderCellsKeepFocus(Doc.Cells[i + 1]); }
            }
        }

        void RunAll()
        {
            var cells = Doc.Cells.Where(x => x.Type == "Code").ToList();
            Action<int> next = null;
            next = i =>
            {
                if (i >= cells.Count) return;
                var c = cells[i];
                RunCell(c, false);
                var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(80) };
                timer.Tick += delegate { if (!c.IsExecuting) { timer.Stop(); if (c.Error.Length == 0) next(i + 1); } };
                timer.Start();
            };
            next(0);
        }

        void ClearOutputs()
        {
            foreach (var c in Doc.Cells) { c.Output = ""; c.Error = ""; c.Images.Clear(); c.ExecCount = 0; }
            Changed();
        }

        void AddDataFile()
        {
            var dlg = new Microsoft.Win32.OpenFileDialog { Multiselect = true, Filter = "Data files|*.csv;*.tsv;*.json;*.xlsx;*.parquet;*.txt|All files|*.*" };
            if (dlg.ShowDialog() != true) return;
            foreach (var f in dlg.FileNames) if (!Doc.DataFiles.Contains(f)) Doc.DataFiles.Add(f);
            Changed();
        }

        void InsertLoader(string file)
        {
            string ext = Path.GetExtension(file).ToLowerInvariant();
            string var = Path.GetFileNameWithoutExtension(file).Replace(" ", "_").Replace("-", "_").Replace(".", "_");
            string p = file.Replace("\\", "/");
            var c = AddCell("Code", "Python");
            c.Content = ext == ".csv" || ext == ".tsv" ? "import pandas as pd\n" + var + " = pd.read_csv(r\"" + p + "\"" + (ext == ".tsv" ? ", sep=\"\\t\"" : "") + ")\n" + var + ".head()"
                : ext == ".json" ? "import json\nwith open(r\"" + p + "\", encoding=\"utf-8\") as f:\n    " + var + " = json.load(f)\n" + var
                : ext == ".xlsx" ? "import pandas as pd\n" + var + " = pd.read_excel(r\"" + p + "\")\n" + var + ".head()"
                : "with open(r\"" + p + "\", encoding=\"utf-8\") as f:\n    " + var + " = f.read()\nprint(" + var + "[:2000])";
            _editors.Remove(c.Id);
            Changed();
        }

        void OnKey(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter && (Keyboard.Modifiers == ModifierKeys.Shift || Keyboard.Modifiers == ModifierKeys.Control))
            {
                var c = SelectedCell();
                if (c != null) RunCell(c, Keyboard.Modifiers == ModifierKeys.Shift);
                e.Handled = true;
            }
        }

        static string LangKey(string lang)
        {
            switch (lang) { case "C++": return "cpp"; case "C#": return "csharp"; default: return lang.ToLowerInvariant(); }
        }

        static Brush LangColor(string l)
        {
            var t = Theme.Current;
            switch (l)
            {
                case "Python": return t.SysBlue; case "R": return t.SysPurple; case "Julia": return t.SysGreen; case "SQL": return t.SysCyan;
                case "Rust": return t.SysOrange; case "Go": return t.SysMint; case "C++": return t.SysBlue; case "Java": return t.SysRed; case "C#": return t.SysPurple;
                default: return t.SysYellow;
            }
        }

        static string LangIcon(string l)
        {
            switch (l) { case "SQL": return "database"; case "Rust": return "gearshape.fill"; case "Java": return "cup.and.saucer.fill"; default: return "circle.fill"; }
        }

        // MARK: NotebookAIPanel
        void RenderAI()
        {
            if (!_showAI) { _aiHost.Child = null; return; }
            if (_ai == null) _ai = new NotebookAIPanel(this, () => { _showAI = false; Defaults.Set("notebook.showAIPanel", false); RenderToolbar(); RenderAI(); });
            _ai.Width = _aiW;
            var handle = ResizeHandle(w => { _aiW = Math.Max(280, Math.Min(560, w)); _ai.Width = _aiW; Defaults.Set("notebook.aiPanelWidth", _aiW); }, () => _aiW, false);
            var dock = new DockPanel();
            DockPanel.SetDock(handle, Dock.Left); dock.Children.Add(handle);
            if (_ai.Parent is Panel) ((Panel)_ai.Parent).Children.Remove(_ai);
            dock.Children.Add(_ai);
            _aiHost.Child = dock;
        }

        public string NotebookContext()
        {
            var sb = new StringBuilder("Notebook \"" + Doc.Name + "\":\n");
            for (int i = 0; i < Doc.Cells.Count; i++)
            {
                var c = Doc.Cells[i];
                sb.AppendLine("Cell [" + (i + 1) + "] (" + c.Language + " - " + c.Type + "):\n```" + LangKey(c.Language) + "\n" + c.Content + "\n```");
                if (c.Output.Length > 0) sb.AppendLine("Output:\n" + (c.Output.Length > 1500 ? c.Output.Substring(0, 1500) : c.Output));
                if (c.Error.Length > 0) sb.AppendLine("Error:\n" + (c.Error.Length > 1500 ? c.Error.Substring(c.Error.Length - 1500) : c.Error));
            }
            return sb.ToString();
        }

        public void ApplyToCell(string code, string lang, bool replaceSelected)
        {
            string l = lang == "py" || lang == "python" ? "Python" : lang == "r" ? "R" : lang == "julia" || lang == "jl" ? "Julia" : lang == "sql" ? "SQL" : "Python";
            var sel = SelectedCell();
            if (replaceSelected && sel != null && sel.Type == "Code") { sel.Content = code; sel.Language = l; _editors.Remove(sel.Id); Changed(); return; }
            var c = AddCell("Code", l);
            c.Content = code; _editors.Remove(c.Id); Changed();
        }

        public int CellCount { get { return Doc.Cells.Count; } }
        public IEnumerable<string> Languages { get { return Doc.Cells.Select(c => c.Language).Distinct(); } }
        public int SelectedIndex { get { var s = SelectedCell(); return s == null ? 0 : Doc.Cells.IndexOf(s) + 1; } }
    }

    /// <summary>NotebookAIPanel: AI AGENT header, context chips, transcript with "Apply to Cell", composer.</summary>
    public class NotebookAIPanel : Grid
    {
        readonly NotebookView _nb;
        readonly StackPanel _list = new StackPanel();
        readonly ScrollViewer _scroll;
        readonly List<ChatMessage> _history = new List<ChatMessage>();
        TextBox _input;
        readonly Border _chips = new Border();

        public NotebookAIPanel(NotebookView nb, Action close)
        {
            _nb = nb;
            var t = Theme.Current;
            Background = t.PanelBackground;
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(28) });
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var header = V.Box(V.H(6, Sym.Icon("brain", 11, t.Accent), V.T("AI AGENT", 10.5, FontWeights.Bold, t.Primary), V.Sp(),
                V.Tip(V.Button(Sym.Icon("trash", 10.5, t.Secondary), () => { _history.Clear(); _list.Children.Clear(); }), "Clear conversation"),
                V.Tip(V.Button(Sym.Icon("xmark", 10, t.Secondary), close), "Close")), V.P(10, 0), null, 0);
            Children.Add(header);
            SetRow(_chips, 1); Children.Add(_chips);
            _scroll = new ScrollViewer { Content = V.Box(_list, V.P(10, 8), null, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            SetRow(_scroll, 2); Children.Add(_scroll);
            var field = Styles.Field("Ask about your cells...", 12, t.Primary, t.Secondary, out _input);
            _input.AcceptsReturn = true; _input.TextWrapping = TextWrapping.Wrap; _input.MaxHeight = 140;
            _input.PreviewKeyDown += (s, e) => { if (e.Key == Key.Enter && (Keyboard.Modifiers & ModifierKeys.Shift) == 0) { e.Handled = true; Send(); } };
            var send = V.Button(V.Size(V.Box(Sym.Icon("paperplane.fill", 10, Brushes.White), V.P(0), t.Accent, 6), 26, 24), Send);
            var composer = V.Box(V.H(6, Sym.Icon("plus.circle.fill", 13, t.Secondary), V.Flex(V.Box(field, V.P(8, 6), t.P(0.04), 7, t.A(0.5), 1)), send), V.P(10, 8), null, 0);
            SetRow(composer, 3); Children.Add(composer);
            RenderChips();
            Loaded += delegate { RenderChips(); };
        }

        void RenderChips()
        {
            var t = Theme.Current;
            var row = V.H(6, V.Box(V.H(4, Sym.Icon("square.grid.2x2", 9, t.Secondary), V.T(_nb.CellCount + " cells", 10, FontWeights.Medium, t.Secondary)), V.P(6, 3), t.P(0.06), 5));
            foreach (var l in _nb.Languages) row.Children.Add(V.Box(V.H(4, V.Dot(6, t.SysBlue), V.T(l, 10, FontWeights.Medium, t.Secondary)), V.P(6, 3), t.P(0.06), 5));
            row.Children.Add(V.Box(V.H(4, Sym.Icon("circle", 8, t.Accent), V.T("Cell " + _nb.SelectedIndex, 10, FontWeights.Medium, t.Accent)), V.P(6, 3), t.A(0.12), 5));
            _chips.Child = V.Box(row, V.P(10, 6), null, 0);
        }

        void Send()
        {
            var t = Theme.Current;
            string text = (_input.Text ?? "").Trim();
            if (text.Length == 0) return;
            _input.Text = "";
            RenderChips();
            _history.Add(new ChatMessage { Role = "user", Content = text });
            var bubble = V.Box(V.Wrap(V.T(text, 12, FontWeights.Normal, t.Primary), TextAlignment.Left), V.P(10, 7), t.P(0.08), 10);
            bubble.HorizontalAlignment = HorizontalAlignment.Right;
            bubble.Margin = new Thickness(30, 6, 0, 6);
            _list.Children.Add(bubble);
            if (!AIConfig.IsConfigured) { AddAnswer("⚠️ " + AIClient.NotConnectedText()); return; }
            var live = V.Wrap(V.T("…", 12, FontWeights.Normal, t.Primary), TextAlignment.Left);
            _list.Children.Add(V.Box(live, V.P(0, 6), null, 0));
            var sb = new StringBuilder();
            string system = "You are MicroCode's Notebook Agent. Answer concisely. When you propose code for a cell, put it in a fenced code block with its language.\n\n" + _nb.NotebookContext();
            AIClient.Stream(_history, system, d => { lock (sb) sb.Append(d); Dispatcher.BeginInvoke(new Action(() => { lock (sb) live.Text = sb.ToString(); _scroll.ScrollToEnd(); })); }, CancellationToken.None)
                .ContinueWith(tk => Dispatcher.BeginInvoke(new Action(() =>
                {
                    string answer; lock (sb) answer = sb.ToString();
                    if (tk.IsFaulted) answer += (answer.Length > 0 ? "\n\n" : "") + "⚠️ " + AIException.Describe(tk.Exception, AIConfig.Mode == "cloud");
                    _list.Children.RemoveAt(_list.Children.Count - 1);
                    _history.Add(new ChatMessage { Role = "assistant", Content = answer });
                    AddAnswer(answer);
                })));
        }

        void AddAnswer(string md)
        {
            var t = Theme.Current;
            foreach (var block in AgentBlocks.Parse(md))
            {
                if (block.Kind == "code")
                {
                    var b = block;
                    var apply = V.Button(V.Box(V.H(4, Sym.Icon("doc.text.fill", 9, t.Accent), V.T("Apply to Cell", 10, FontWeights.SemiBold, t.Accent)), V.P(6, 2), t.A(0.12), 4), () => _nb.ApplyToCell(b.Text, b.Lang, false));
                    var copy = V.Button(Sym.Icon("doc.on.doc", 10, t.Secondary), () => Clipboard.SetText(b.Text));
                    var head = V.H(6, V.Box(V.Mono((b.Lang ?? "").ToUpperInvariant(), 9, FontWeights.SemiBold, t.Secondary), V.P(5, 1.5), t.P(0.06), 3.5), V.Sp(), apply, copy);
                    var code = new TextBox { Text = b.Text, IsReadOnly = true, BorderThickness = new Thickness(0), Background = Brushes.Transparent, Foreground = t.EditorText, FontFamily = UIFonts.Mono, FontSize = 11.5, TextWrapping = TextWrapping.Wrap, CaretBrush = Brushes.Transparent };
                    _list.Children.Add(V.Box(V.VLead(6, V.Self(head, Cross.Stretch), V.Self(code, Cross.Stretch)), V.P(8), t.EditorBackground, 8, t.P(0.13), 1));
                    ((FrameworkElement)_list.Children[_list.Children.Count - 1]).Margin = new Thickness(0, 4, 0, 4);
                }
                else
                {
                    var tb = V.Wrap(V.T(block.Text.Trim(), 12, FontWeights.Normal, t.Primary), TextAlignment.Left);
                    tb.Margin = new Thickness(0, 4, 0, 4);
                    _list.Children.Add(tb);
                }
            }
            _scroll.ScrollToEnd();
        }
    }
}
