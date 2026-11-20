// Port of Kernel/KernelClient.swift (LocalPersistentPythonKernel) and the polyglot cell runners in NotebookView.swift.
// One warm Python process per Cell Sheet keeps globals between cells. User output streams live on stdout; control packets
// are framed as \x02MCJ:<base64 json>\x03. "MC_INT" interrupts the running cell (KeyboardInterrupt) and keeps variables.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using MicroCode.Core;

namespace MicroCode.Views
{
    public class KernelOutcome
    {
        public string Text = "";
        public List<string> Files = new List<string>();
        public InlineDataFrame DataFrame;
        public CellTelemetry Telemetry;
        public bool HadError;
    }

    /// <summary>Python interpreters on this PC (PythonEnvManager): the py launcher list, python on PATH and workspace virtual envs.</summary>
    public static class PythonEnvs
    {
        public class Env { public string Name, Path, Kind; }
        static List<Env> _cache;

        public static List<Env> All(bool refresh)
        {
            if (_cache != null && !refresh) return _cache;
            var list = new List<Env>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            Action<string, string, string> add = (name, path, kind) =>
            {
                if (string.IsNullOrEmpty(path) || !File.Exists(path) || path.IndexOf("WindowsApps", StringComparison.OrdinalIgnoreCase) >= 0) return;
                string full = System.IO.Path.GetFullPath(path);
                if (seen.Add(full)) list.Add(new Env { Name = name, Path = full, Kind = kind });
            };
            // py -0p: "-V:3.13 *        C:\...\python.exe"
            foreach (var line in Run("py", "-0p").Split('\n'))
            {
                var m = Regex.Match(line.Trim(), @"^-V:(\S+)\s*\*?\s+(.+python[^\\]*\.exe)\s*$", RegexOptions.IgnoreCase);
                if (m.Success) add("Python " + m.Groups[1].Value, m.Groups[2].Value.Trim(), "system");
            }
            foreach (var line in Run("where", "python").Split('\n'))
            {
                string p = line.Trim();
                if (p.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) add("Python (" + ShortDir(p) + ")", p, "system");
            }
            string ws = AppState.Shared != null ? AppState.Shared.WorkspaceFolder : null;
            if (ws != null)
                foreach (var v in new[] { ".venv", "venv", "env", ".env" })
                {
                    string py = System.IO.Path.Combine(ws, v, "Scripts", "python.exe");
                    if (File.Exists(py)) add(v, py, "venv");
                }
            _cache = list;
            return list;
        }

        static string ShortDir(string exe) { var d = System.IO.Path.GetDirectoryName(exe) ?? ""; return System.IO.Path.GetFileName(d); }

        static string Run(string exe, string args)
        {
            try
            {
                var p = Process.Start(new ProcessStartInfo(exe, args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8 });
                if (p == null) return "";
                var o = p.StandardOutput.ReadToEndAsync();
                if (!p.WaitForExit(5000)) { try { p.Kill(); } catch (Exception kx) { Debug.WriteLine("python probe kill: " + kx.Message); } return ""; }
                return o.Result;
            }
            catch (Exception ex) { Debug.WriteLine("python probe " + exe + ": " + ex.Message); return ""; }
        }

        public static string Selected
        {
            get { string p = Defaults.Str("notebook.pythonPath", ""); return p.Length > 0 && File.Exists(p) ? p : null; }
            set { Defaults.Set("notebook.pythonPath", value ?? ""); }
        }

        public static string SelectedName
        {
            get
            {
                string sel = Selected;
                if (sel == null) return "Python";
                var e = All(false).FirstOrDefault(x => string.Equals(x.Path, sel, StringComparison.OrdinalIgnoreCase));
                return e == null ? "Python" : e.Kind == "venv" ? "venv: " + e.Name : e.Name;
            }
        }
    }

    public class NbPythonKernel
    {
        static readonly Dictionary<string, NbPythonKernel> Pool = new Dictionary<string, NbPythonKernel>();
        public static NbPythonKernel For(string docId)
        {
            lock (Pool) { NbPythonKernel k; if (!Pool.TryGetValue(docId ?? "", out k)) Pool[docId ?? ""] = k = new NbPythonKernel(); return k; }
        }
        public static void ShutdownAll() { lock (Pool) foreach (var k in Pool.Values) k.Kill(null); }

        Process _p;
        StreamWriter _in;
        EventWaitHandle _intEvent;
        readonly object _lock = new object();
        readonly StringBuilder _live = new StringBuilder();
        readonly StringBuilder _frame = new StringBuilder();
        Action<string> _onStream;
        Action<KernelOutcome> _onDone;
        DateTime _lastEmit = DateTime.MinValue;
        long _lastRss;
        bool _emitQueued;

        public string Status = "Not Started", Version = "", Executable = "";
        public List<KernelVar> Variables = new List<KernelVar>();
        public long RssBytes, GpuBytes;
        public event Action Changed;
        public bool Busy { get { lock (_lock) return _onDone != null; } }

        void Notify() { var app = Application.Current; if (app != null) app.Dispatcher.BeginInvoke(new Action(() => { if (Changed != null) Changed(); })); }

        static string DriverPath()
        {
            string path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "microcode_nb_kernel_v2.py");
            try { if (!File.Exists(path) || File.ReadAllText(path) != Driver) File.WriteAllText(path, Driver, new UTF8Encoding(false)); }
            catch (IOException ex) { Debug.WriteLine("kernel driver write: " + ex.Message); }
            return path;
        }

        public void Start()
        {
            Kill(null);
            string script = DriverPath();
            var candidates = new List<Tuple<string, string>>();
            if (PythonEnvs.Selected != null) candidates.Add(Tuple.Create(PythonEnvs.Selected, ""));
            candidates.Add(Tuple.Create("python", ""));
            candidates.Add(Tuple.Create("py", "-3 "));
            foreach (var c in candidates)
            {
                try
                {
                    var psi = new ProcessStartInfo(c.Item1, c.Item2 + "-u \"" + script + "\"")
                    {
                        UseShellExecute = false, RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true,
                        StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8, WorkingDirectory = NbStore.WorkingDirectory
                    };
                    psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
                    psi.EnvironmentVariables["PYTHONUNBUFFERED"] = "1";
                    psi.EnvironmentVariables["MPLBACKEND"] = "Agg";
                    string evName = "MicroCodeNbInt-" + Guid.NewGuid().ToString("N");
                    var ev = new EventWaitHandle(false, EventResetMode.AutoReset, evName);
                    psi.EnvironmentVariables["MC_INT_EVENT"] = evName;
                    var p = new Process { StartInfo = psi, EnableRaisingEvents = true };
                    p.Exited += delegate { OnExited(p); };
                    p.Start();
                    // our own UTF-8 writer: Process.StandardInput follows Console.InputEncoding, which writes a BOM in front of the
                    // first command when the console code page is UTF-8 — the kernel then ignored that first cell
                    var input = new StreamWriter(p.StandardInput.BaseStream, new UTF8Encoding(false)) { AutoFlush = true, NewLine = "\n" };
                    lock (_lock) { _p = p; _in = input; _frame.Clear(); if (_intEvent != null) _intEvent.Dispose(); _intEvent = ev; }
                    var t1 = new Thread(() => Pump(p, p.StandardOutput, true)) { IsBackground = true, Name = "nb-kernel-out" }; t1.Start();
                    var t2 = new Thread(() => Pump(p, p.StandardError, false)) { IsBackground = true, Name = "nb-kernel-err" }; t2.Start();
                    Status = "Starting…"; Executable = c.Item1; Notify();
                    return;
                }
                catch (Exception ex) { Debug.WriteLine("kernel start " + c.Item1 + ": " + ex.Message); }
            }
            Status = "Python not found"; Notify();
        }

        void OnExited(Process p)
        {
            Action<KernelOutcome> done = null; string text;
            lock (_lock)
            {
                if (_p != p) return;
                _p = null;
                done = _onDone; _onDone = null; _onStream = null;
                text = _live.ToString();
            }
            Status = "Dead"; Notify();
            if (done != null) Dispatch(() => done(new KernelOutcome { Text = (text.TrimEnd('\n') + "\n\nKernel process exited unexpectedly. Restart the kernel to continue.").Trim(), HadError = true }));
        }

        void Pump(Process p, StreamReader r, bool stdout)
        {
            var buf = new char[4096];
            try
            {
                int n;
                while ((n = r.Read(buf, 0, buf.Length)) > 0)
                {
                    string chunk = new string(buf, 0, n);
                    if (stdout) OnStdout(p, chunk); else AppendUser(chunk);
                }
            }
            catch (Exception ex) { Debug.WriteLine("kernel pump: " + ex.Message); }
        }

        void OnStdout(Process p, string chunk)
        {
            var packets = new List<string>();
            lock (_lock)
            {
                if (_p != p) return;
                _frame.Append(chunk);
                while (true)
                {
                    string s = _frame.ToString();
                    int stx = s.IndexOf("\u0002MCJ:", StringComparison.Ordinal);
                    if (stx < 0)
                    {
                        // keep a partial "\x02MCJ" marker split across reads
                        int hold = s.LastIndexOf('\u0002');
                        string user = hold >= 0 && s.Length - hold < 5 ? s.Substring(0, hold) : s;
                        if (user.Length > 0) { _live.Append(user); _frame.Remove(0, user.Length); }
                        break;
                    }
                    if (stx > 0) { _live.Append(s.Substring(0, stx)); }
                    int etx = s.IndexOf('\u0003', stx);
                    if (etx < 0) { _frame.Remove(0, stx); break; }
                    packets.Add(s.Substring(stx + 5, etx - stx - 5));
                    int after = etx + 1;
                    if (after < s.Length && s[after] == '\r') after++;
                    if (after < s.Length && s[after] == '\n') after++;
                    _frame.Remove(0, after);
                }
            }
            EmitLive();
            foreach (var pk in packets) OnPacket(pk);
        }

        void AppendUser(string text) { lock (_lock) { if (_onDone == null) return; _live.Append(text); } EmitLive(); }

        void EmitLive()
        {
            lock (_lock)
            {
                if (_onStream == null || _emitQueued) return;
                _emitQueued = true;
            }
            int wait = Math.Max(0, 50 - (int)(DateTime.Now - _lastEmit).TotalMilliseconds);
            Task.Delay(wait).ContinueWith(_ =>
            {
                string snap; Action<string> cb;
                lock (_lock) { _emitQueued = false; cb = _onStream; snap = _live.ToString().Replace("\r\n", "\n"); }
                _lastEmit = DateTime.Now;
                if (cb != null) Dispatch(() => cb(snap));
            });
        }

        static void Dispatch(Action a) { var app = Application.Current; if (app != null) app.Dispatcher.BeginInvoke(a); }

        void OnPacket(string b64)
        {
            Dictionary<string, object> o;
            try { o = DJ.Obj(Encoding.UTF8.GetString(Convert.FromBase64String(b64))); }
            catch (Exception ex) { Debug.WriteLine("kernel packet: " + ex.Message); return; }
            if (o == null) return;
            string ev = DJ.Str(o, "event");
            if (ev == "ready") { Version = DJ.Str(o, "version") ?? ""; Executable = DJ.Str(o, "executable") ?? Executable; Status = "Idle"; Notify(); return; }
            if (ev != "done") return;
            var outc = new KernelOutcome { HadError = o.ContainsKey("had_error") && true.Equals(o["had_error"]) };
            long rss = (long)(DJ.Num(o, "rss_bytes") ?? 0), gpu = (long)(DJ.Num(o, "gpu_bytes") ?? 0);
            outc.Telemetry = new CellTelemetry { DurationMs = DJ.Num(o, "duration_ms") ?? 0, PeakRSSBytes = rss, GpuBytes = gpu, MemoryDeltaBytes = _lastRss > 0 ? rss - _lastRss : 0 };
            _lastRss = rss;
            var imgs = DJ.Arr(o, "images");
            if (imgs != null) foreach (var x in imgs) { string f = Convert.ToString(x); if (File.Exists(f)) outc.Files.Add(f); }
            var df = DJ.Child(o, "dataframe");
            if (df != null) outc.DataFrame = ParseDf(df);
            var vars = new List<KernelVar>();
            var va = DJ.Arr(o, "variables");
            if (va != null) foreach (var x in va) { var v = x as Dictionary<string, object>; if (v != null) vars.Add(ParseVar(v)); }
            string expr = DJ.Str(o, "expr_text") ?? "";
            Action<KernelOutcome> done;
            lock (_lock)
            {
                if (expr.Length > 0 && outc.DataFrame == null)
                {
                    string cur = _live.ToString();
                    _live.Append(cur.Length == 0 || cur.EndsWith("\n") ? expr : "\n" + expr);
                }
                outc.Text = _live.ToString().Replace("\r\n", "\n").Trim('\n', '\r');
                done = _onDone; _onDone = null; _onStream = null;
            }
            Variables = vars; RssBytes = rss; GpuBytes = gpu;
            Status = "Idle"; Notify();
            if (done != null) Dispatch(() => done(outc));
        }

        static InlineDataFrame ParseDf(Dictionary<string, object> d)
        {
            var df = new InlineDataFrame
            {
                VariableName = DJ.Str(d, "variableName") ?? "DataFrame", TotalRows = (int)(DJ.Num(d, "totalRows") ?? 0), TotalCols = (int)(DJ.Num(d, "totalCols") ?? 0),
                CsvExportPath = DJ.Str(d, "csvExportPath")
            };
            var cols = DJ.Arr(d, "columns"); if (cols != null) foreach (var c in cols) df.Columns.Add(Convert.ToString(c));
            var dt = DJ.Child(d, "dtypes"); if (dt != null) foreach (var kv in dt) df.Dtypes[kv.Key] = Convert.ToString(kv.Value);
            var st = DJ.Child(d, "stats");
            if (st != null)
                foreach (var kv in st)
                {
                    var s = kv.Value as Dictionary<string, object>; if (s == null) continue;
                    df.Stats[kv.Key] = new DfStats { NullCount = (int)(DJ.Num(s, "nullCount") ?? 0), MinVal = DJ.Num(s, "minVal"), MaxVal = DJ.Num(s, "maxVal"), MeanVal = DJ.Num(s, "meanVal") };
                }
            var rows = DJ.Arr(d, "rows");
            if (rows != null) foreach (var r in rows) { var ra = DJ.AsList(r); if (ra != null) df.Rows.Add(ra.Cast<object>().Select(x => Convert.ToString(x)).ToList()); }
            return df;
        }

        static KernelVar ParseVar(Dictionary<string, object> v)
        {
            var k = new KernelVar
            {
                Name = DJ.Str(v, "name") ?? "", TypeName = DJ.Str(v, "typeName") ?? "", Shape = DJ.Str(v, "shape") ?? "", Dtype = DJ.Str(v, "dtype") ?? "",
                Preview = DJ.Str(v, "preview") ?? "", MemoryBytes = (long)(DJ.Num(v, "memoryBytes") ?? 0)
            };
            var cols = DJ.Arr(v, "columns"); if (cols != null) foreach (var c in cols) k.Columns.Add(Convert.ToString(c));
            var smp = DJ.Arr(v, "numericSample"); if (smp != null) foreach (var c in smp) { try { k.NumericSample.Add(Convert.ToDouble(c)); } catch (Exception ex) { Debug.WriteLine("sample: " + ex.Message); } }
            return k;
        }

        /// <summary>Runs code in the warm interpreter. Callbacks arrive on the UI thread; onDone exactly once.</summary>
        public void Execute(string code, string cellTag, Action<string> onStream, Action<KernelOutcome> onDone)
        {
            Process p; StreamWriter input;
            lock (_lock) { p = _p; input = _in; }
            if (p == null || p.HasExited) { Start(); lock (_lock) { p = _p; input = _in; } }
            if (p == null) { onDone(new KernelOutcome { Text = "Python was not found. Install Python 3 from python.org (tick \"Add to PATH\"), then pick it in the Python menu and restart the kernel.", HadError = true }); return; }
            string artifacts = Path.Combine(NbStore.WorkingDirectory, "artifacts");
            try { Directory.CreateDirectory(artifacts); } catch (Exception ex) { Debug.WriteLine("artifacts dir: " + ex.Message); }
            string clean = (code ?? "").Replace('\u2018', '\'').Replace('\u2019', '\'').Replace('\u201C', '"').Replace('\u201D', '"');
            string json = DJ.Ser(new Dictionary<string, object> { { "code", clean }, { "cell_tag", cellTag }, { "workdir", NbStore.WorkingDirectory }, { "artifacts_dir", artifacts } });
            lock (_lock) { _live.Clear(); _onStream = onStream; _onDone = onDone; }
            Status = "Busy"; Notify();
            try { input.WriteLine("MC_EXEC:" + Convert.ToBase64String(Encoding.UTF8.GetBytes(json))); }
            catch (Exception ex)
            {
                lock (_lock) { _onDone = null; _onStream = null; }
                onDone(new KernelOutcome { Text = "Could not reach the Python kernel: " + ex.Message, HadError = true });
            }
        }

        /// <summary>Raises KeyboardInterrupt in the running cell (variables stay in RAM).</summary>
        public void Interrupt()
        {
            EventWaitHandle ev; lock (_lock) ev = _p != null ? _intEvent : null;
            try { if (ev != null) ev.Set(); }
            catch (ObjectDisposedException ex) { Debug.WriteLine("kernel interrupt: " + ex.Message); }
        }

        /// <summary>Stops the interpreter; a cell still running finishes with <paramref name="message"/>.</summary>
        public void Kill(string message)
        {
            Process p; Action<KernelOutcome> done; string text;
            lock (_lock) { p = _p; _p = null; done = _onDone; _onDone = null; _onStream = null; text = _live.ToString(); }
            if (p != null) { try { if (!p.HasExited) p.Kill(); } catch (Exception ex) { Debug.WriteLine("kernel kill: " + ex.Message); } }
            Variables = new List<KernelVar>(); RssBytes = 0; GpuBytes = 0; _lastRss = 0;
            Status = "Not Started"; Notify();
            if (done != null) Dispatch(() => done(new KernelOutcome { Text = (text.Replace("\r\n", "\n").TrimEnd('\n') + "\n" + (message ?? "⏹ Kernel restarted.")).Trim(), HadError = false }));
        }

        public void Restart() { Kill("⏹ Kernel restarted."); Start(); }

        // The interpreter-side driver (adapted from the Mac worker: Windows RSS via K32GetProcessMemoryInfo, CUDA memory via torch,
        // stdin reader thread so "MC_INT" can interrupt the main thread with _thread.interrupt_main()).
        const string Driver = @"import sys as _mc_sys, os as _mc_os, io as _mc_io, ast as _mc_ast, time as _mc_time, json as _mc_json, base64 as _mc_b64
import traceback as _mc_tb, warnings as _mc_warnings, builtins as _mc_builtins, threading as _mc_threading, _thread as _mc_thread
import ctypes as _mc_ctypes
_mc_os.environ.setdefault('MPLBACKEND', 'Agg')
_mc_warnings.filterwarnings('ignore', message='.*FigureCanvasAgg is non-interactive.*')
_MC_PROTO_IN = _mc_sys.__stdin__
_MC_PROTO_OUT = _mc_sys.__stdout__
_MC_GLOBALS = {'__name__': '__main__', '__builtins__': __builtins__}
_MC_DISPLAYED_DF = None
_MC_CELL_OUTPUT_FILES = []
_MC_CAPTURED_FIG_IDS = set()
_MC_RICH_SEQ = 0
_MC_CUR_ARTIFACTS = _mc_os.getcwd()
_MC_CUR_TAG = 'cell'
_MC_RICH_EXTS = {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.svg', '.pdf', '.md', '.markdown', '.html', '.htm'}

def _mc_emit(obj):
    raw = _mc_json.dumps(obj, ensure_ascii=False, default=str).encode('utf-8')
    _MC_PROTO_OUT.write('\x02MCJ:' + _mc_b64.b64encode(raw).decode('ascii') + '\x03\n')
    _MC_PROTO_OUT.flush()

def _mc_extract_df_payload(obj, var_name, artifacts_dir, cell_tag):
    cls_name = type(obj).__name__
    mod_name = getattr(type(obj), '__module__', '')
    if cls_name == 'DataFrame' and 'polars' in mod_name:
        try:
            total_rows, total_cols = obj.height, obj.width
            cols = [str(c) for c in obj.columns[:60]]
            dtypes = {str(c): str(obj.schema[c]) for c in cols}
            sub = obj.select(cols).head(250)
            rows = [[('' if v is None else str(v)) for v in row] for row in sub.iter_rows()]
            csv_path = _mc_os.path.join(artifacts_dir, cell_tag + '_df.csv')
            try:
                obj.head(5000).write_csv(csv_path)
            except Exception:
                csv_path = None
            return {'variableName': var_name or 'polars.DataFrame', 'totalRows': int(total_rows), 'totalCols': int(total_cols), 'columns': cols, 'dtypes': dtypes, 'stats': {}, 'rows': rows, 'csvExportPath': csv_path}
        except Exception:
            return None
    if cls_name == 'DataFrame' and hasattr(obj, 'columns') and hasattr(obj, 'iloc'):
        try:
            total_rows, total_cols = int(obj.shape[0]), int(obj.shape[1])
            raw_cols = list(obj.columns[:60])
            cols = [str(c) for c in raw_cols]
            dtypes = {}
            stats = {}
            for c, c_name in zip(raw_cols, cols):
                s = obj[c]
                dt = s.dtype
                dtypes[c_name] = str(dt)
                kind = getattr(dt, 'kind', '')
                st = {'nullCount': 0, 'minVal': None, 'maxVal': None, 'meanVal': None}
                try:
                    if kind in ('i', 'u'):
                        if total_rows > 0:
                            arr = s.to_numpy(copy=False)
                            st['minVal'] = float(arr.min()); st['maxVal'] = float(arr.max()); st['meanVal'] = float(arr.mean())
                    elif kind == 'f':
                        arr = s.to_numpy(copy=False)
                        null_cnt = int((arr != arr).sum())
                        st['nullCount'] = null_cnt
                        if total_rows > null_cnt:
                            valid = arr[arr == arr] if null_cnt else arr
                            st['minVal'] = float(valid.min()); st['maxVal'] = float(valid.max()); st['meanVal'] = float(valid.mean())
                    else:
                        st['nullCount'] = int(s.isna().sum())
                except Exception:
                    pass
                stats[c_name] = st
            head_df = obj.iloc[:250, :len(raw_cols)]
            rows = []
            for row_tuple in head_df.itertuples(index=False, name=None):
                rows.append([('' if (v is None or (isinstance(v, float) and v != v)) else str(v)) for v in row_tuple])
            csv_path = _mc_os.path.join(artifacts_dir, cell_tag + '_df.csv')
            try:
                obj.head(5000).to_csv(csv_path, index=False)
            except Exception:
                csv_path = None
            return {'variableName': var_name or 'DataFrame', 'totalRows': total_rows, 'totalCols': total_cols, 'columns': cols, 'dtypes': dtypes, 'stats': stats, 'rows': rows, 'csvExportPath': csv_path}
        except Exception:
            return None
    return None

def _mc_next_artifact_path(ext):
    global _MC_RICH_SEQ
    _MC_RICH_SEQ += 1
    try:
        _mc_os.makedirs(_MC_CUR_ARTIFACTS, exist_ok=True)
    except Exception:
        pass
    return _mc_os.path.join(_MC_CUR_ARTIFACTS, _MC_CUR_TAG + '_rich' + str(_MC_RICH_SEQ) + '.' + ext.lstrip('.'))

def _mc_record_output_file(path_val):
    try:
        p = _mc_os.path.realpath(_mc_os.path.abspath(_mc_os.fspath(path_val)))
        if _mc_os.path.isfile(p) and _mc_os.path.getsize(p) > 0:
            if p not in _MC_CELL_OUTPUT_FILES:
                _MC_CELL_OUTPUT_FILES.append(p)
            return True
    except Exception:
        pass
    return False

def _mc_save_mpl_fig_obj(fig):
    try:
        if fig is None:
            return False
        if not (getattr(fig, 'axes', None) or getattr(fig, 'texts', None) or getattr(fig, 'images', None) or getattr(fig, 'patches', None) or getattr(fig, 'artists', None)):
            return False
        img_path = _mc_next_artifact_path('png')
        dpi_val = max(150, int(getattr(fig, 'dpi', 150) or 150))
        try:
            fig.savefig(img_path, dpi=dpi_val, bbox_inches='tight')
        except Exception:
            fig.savefig(img_path, dpi=dpi_val)
        if _mc_record_output_file(img_path):
            _MC_CAPTURED_FIG_IDS.add(id(fig))
            return True
    except Exception:
        pass
    return False

def _mc_capture_open_mpl_figures(close_after=False):
    if 'matplotlib.pyplot' not in _mc_sys.modules:
        return
    try:
        plt = _mc_sys.modules['matplotlib.pyplot']
        nums = list(plt.get_fignums())
        for num in nums:
            fig = plt.figure(num)
            if id(fig) not in _MC_CAPTURED_FIG_IDS:
                _mc_save_mpl_fig_obj(fig)
        if close_after and nums:
            getattr(plt, '_mc_orig_close', plt.close)('all')
    except Exception:
        pass

def _mc_patch_viz_modules():
    if 'matplotlib.pyplot' in _mc_sys.modules:
        try:
            plt = _mc_sys.modules['matplotlib.pyplot']
            if not getattr(plt, '_mc_patched', False):
                plt._mc_orig_show = plt.show
                plt._mc_orig_close = plt.close
                def _mc_plt_show(*a, **k):
                    _mc_capture_open_mpl_figures(close_after=True)
                plt.show = _mc_plt_show
                plt._mc_patched = True
        except Exception:
            pass
    if 'matplotlib.figure' in _mc_sys.modules:
        try:
            FigCls = getattr(_mc_sys.modules['matplotlib.figure'], 'Figure', None)
            if FigCls is not None and not getattr(FigCls, '_mc_patched', False):
                _orig_savefig = FigCls.savefig
                def _mc_fig_show(self, *a, **k):
                    _mc_save_mpl_fig_obj(self)
                def _mc_fig_savefig(self, fname, *a, **k):
                    res = _orig_savefig(self, fname, *a, **k)
                    if isinstance(fname, (str, _mc_os.PathLike)):
                        p_str = _mc_os.fspath(fname)
                        ext = _mc_os.path.splitext(p_str.lower())[1]
                        if ext in _MC_RICH_EXTS and _mc_record_output_file(p_str) and ext in {'.png', '.jpg', '.jpeg', '.webp', '.svg'}:
                            _MC_CAPTURED_FIG_IDS.add(id(self))
                    return res
                FigCls.show = _mc_fig_show
                FigCls.savefig = _mc_fig_savefig
                FigCls._mc_patched = True
        except Exception:
            pass
    if 'PIL.Image' in _mc_sys.modules:
        try:
            ImgCls = getattr(_mc_sys.modules['PIL.Image'], 'Image', None)
            if ImgCls is not None and not getattr(ImgCls, '_mc_patched', False):
                def _mc_pil_show(self, *a, **k):
                    p = _mc_next_artifact_path('png')
                    self.save(p, format='PNG')
                    _mc_record_output_file(p)
                ImgCls.show = _mc_pil_show
                ImgCls._mc_patched = True
        except Exception:
            pass
    if 'plotly.basedatatypes' in _mc_sys.modules:
        try:
            BFCls = getattr(_mc_sys.modules['plotly.basedatatypes'], 'BaseFigure', None)
            if BFCls is not None and not getattr(BFCls, '_mc_patched', False):
                def _mc_plotly_show(self, *a, **k):
                    p = _mc_next_artifact_path('html')
                    self.write_html(p, include_plotlyjs='cdn')
                    _mc_record_output_file(p)
                BFCls.show = _mc_plotly_show
                BFCls._mc_patched = True
        except Exception:
            pass

_mc_orig_import = _mc_builtins.__import__
def _mc_import_hook(name, globals=None, locals=None, fromlist=(), level=0):
    mod = _mc_orig_import(name, globals, locals, fromlist, level)
    if name.startswith(('matplotlib', 'PIL', 'plotly')):
        _mc_patch_viz_modules()
    return mod
_mc_builtins.__import__ = _mc_import_hook

def _mc_write_text_artifact(ext, text):
    p = _mc_next_artifact_path(ext)
    with open(p, 'w', encoding='utf-8') as f:
        f.write(text)
    return _mc_record_output_file(p)

def _mc_write_bytes_artifact(ext, data):
    if isinstance(data, str):
        data = _mc_b64.b64decode(data)
    p = _mc_next_artifact_path(ext)
    with open(p, 'wb') as f:
        f.write(data)
    return _mc_record_output_file(p)

def _mc_try_capture_rich_value(o, allow_path_str=False):
    global _MC_DISPLAYED_DF
    if o is None:
        return False
    df_p = _mc_extract_df_payload(o, 'display', _MC_CUR_ARTIFACTS, _MC_CUR_TAG)
    if df_p is not None:
        _MC_DISPLAYED_DF = df_p
        return True
    cls_name = type(o).__name__
    mod_name = getattr(type(o), '__module__', '')
    if isinstance(o, _mc_os.PathLike) or (allow_path_str and isinstance(o, str) and len(o) < 1024 and '\n' not in o):
        try:
            p_str = _mc_os.fspath(o)
            if _mc_os.path.splitext(p_str.lower())[1] in _MC_RICH_EXTS and _mc_os.path.isfile(p_str):
                return _mc_record_output_file(p_str)
        except Exception:
            pass
    if 'matplotlib' in mod_name:
        if hasattr(o, 'savefig'):
            return _mc_save_mpl_fig_obj(o)
        if hasattr(o, 'figure') and hasattr(o.figure, 'savefig'):
            return _mc_save_mpl_fig_obj(o.figure)
    if 'PIL' in mod_name and hasattr(o, 'save'):
        try:
            p = _mc_next_artifact_path('png')
            o.save(p, format='PNG')
            return _mc_record_output_file(p)
        except Exception:
            pass
    if hasattr(o, 'write_html'):
        try:
            p = _mc_next_artifact_path('html')
            try:
                o.write_html(p, include_plotlyjs='cdn')
            except TypeError:
                o.write_html(p)
            return _mc_record_output_file(p)
        except Exception:
            pass
    reprs = ('_repr_markdown_', '_repr_latex_', '_repr_svg_', '_repr_png_', '_repr_jpeg_', '_repr_html_', '_repr_pdf_')
    if 'IPython' in mod_name or any(hasattr(o, m) for m in reprs):
        try:
            if cls_name == 'PDF' or hasattr(o, '_repr_pdf_'):
                fn = getattr(o, 'filename', None)
                if fn and _mc_os.path.isfile(fn):
                    return _mc_record_output_file(fn)
                raw_pdf = o._repr_pdf_() if hasattr(o, '_repr_pdf_') else getattr(o, 'data', None)
                if raw_pdf:
                    return _mc_write_bytes_artifact('pdf', raw_pdf)
            if cls_name in ('Latex', 'Math') or hasattr(o, '_repr_latex_'):
                tex_s = o._repr_latex_() if hasattr(o, '_repr_latex_') else getattr(o, 'data', '')
                if isinstance(tex_s, str) and tex_s.strip():
                    s = tex_s.strip()
                    if not (s.startswith('$$') or s.startswith('\\[') or s.startswith('$')):
                        s = '$$\n' + s + '\n$$'
                    return _mc_write_text_artifact('md', s)
            if cls_name == 'Markdown' or hasattr(o, '_repr_markdown_'):
                md_s = o._repr_markdown_() if hasattr(o, '_repr_markdown_') else getattr(o, 'data', '')
                if isinstance(md_s, str) and md_s.strip():
                    return _mc_write_text_artifact('md', md_s)
            if cls_name == 'SVG' or hasattr(o, '_repr_svg_'):
                fn = getattr(o, 'filename', None)
                if fn and _mc_os.path.isfile(fn):
                    return _mc_record_output_file(fn)
                svg_s = o._repr_svg_() if hasattr(o, '_repr_svg_') else getattr(o, 'data', '')
                if isinstance(svg_s, str) and svg_s.strip():
                    return _mc_write_text_artifact('svg', svg_s)
            if cls_name == 'Image' or hasattr(o, '_repr_png_') or hasattr(o, '_repr_jpeg_'):
                fn = getattr(o, 'filename', None)
                if fn and _mc_os.path.isfile(fn):
                    return _mc_record_output_file(fn)
                if hasattr(o, '_repr_png_'):
                    d = o._repr_png_()
                    if d:
                        return _mc_write_bytes_artifact('png', d)
                if hasattr(o, '_repr_jpeg_'):
                    d = o._repr_jpeg_()
                    if d:
                        return _mc_write_bytes_artifact('jpg', d)
            if cls_name == 'HTML' or hasattr(o, '_repr_html_'):
                html_s = o._repr_html_() if hasattr(o, '_repr_html_') else getattr(o, 'data', '')
                if isinstance(html_s, str) and html_s.strip():
                    return _mc_write_text_artifact('html', html_s)
        except Exception:
            pass
    return False

def _mc_display(*objs):
    for o in objs:
        if not _mc_try_capture_rich_value(o, allow_path_str=True):
            print(o if isinstance(o, str) else repr(o))

def _mc_display_markdown(text_str):
    if isinstance(text_str, str) and text_str.strip():
        _mc_write_text_artifact('md', text_str)

_MC_GLOBALS['display'] = _mc_display
_MC_GLOBALS['display_markdown'] = _mc_display_markdown
_MC_GLOBALS['display_pdf'] = lambda p: _mc_record_output_file(p)

_MC_SKIP_VARS = {'__name__', '__doc__', '__package__', '__loader__', '__spec__', '__builtins__', 'display', 'display_markdown', 'display_pdf', 'shm', 'In', 'Out', '_'}

def _mc_inspect_variables():
    items = []
    for k, v in list(_MC_GLOBALS.items()):
        if k.startswith('_') or k in _MC_SKIP_VARS:
            continue
        t_name = type(v).__name__
        if t_name in ('module', 'function', 'type', 'builtin_function_or_method', 'method'):
            continue
        shape = ''
        dtype = t_name
        mem = 0
        cols = []
        sample = []
        preview = ''
        try:
            raw_shape = getattr(v, 'shape', None)
            if raw_shape is not None:
                shape = str(tuple(int(x) for x in raw_shape))
            elif isinstance(v, (list, tuple, set, dict, str, bytes)):
                shape = 'len=' + str(len(v))
            if hasattr(v, 'dtype'):
                dtype = str(v.dtype)
            elif t_name == 'DataFrame' and hasattr(v, 'columns'):
                cols = [str(c) for c in list(v.columns)[:30]]
                dtype = str(len(cols)) + ' cols'
            if hasattr(v, 'nbytes'):
                mem = int(v.nbytes)
            elif hasattr(v, 'memory_usage') and callable(v.memory_usage):
                mem = int(v.memory_usage(index=False, deep=False).sum())
            else:
                mem = int(_mc_sys.getsizeof(v))
            if t_name == 'DataFrame' and hasattr(v, 'iloc') and hasattr(v, 'columns'):
                n_rows, n_cols = int(v.shape[0]), int(v.shape[1])
                if n_rows > 0 and n_cols > 0:
                    for c in list(v.columns[:8]):
                        s_col = v[c]
                        if getattr(s_col.dtype, 'kind', '') in ('i', 'u', 'f'):
                            sample = [float(x) for x in s_col.iloc[:28].tolist() if isinstance(x, (int, float)) and x == x]
                            break
                    preview = 'DataFrame[' + str(n_rows) + 'x' + str(n_cols) + '] ' + ', '.join(str(c) + '=' + repr(v[c].iloc[0]) for c in list(v.columns[:4]))
                else:
                    preview = 'DataFrame[' + str(n_rows) + 'x' + str(n_cols) + ']'
            elif hasattr(v, 'reshape') and hasattr(v, 'dtype') and getattr(v.dtype, 'kind', '') in ('i', 'u', 'f'):
                view1d = v.reshape(-1)
                n_take = min(28, int(view1d.shape[0]))
                if n_take > 0:
                    sample = [float(x) for x in view1d[:n_take].tolist() if isinstance(x, (int, float)) and x == x]
                preview = ('array(shape=' + shape + ', dtype=' + dtype + ', head=' + repr(view1d[:min(4, n_take)].tolist()) + ')')[:180]
            elif isinstance(v, (list, tuple)) and len(v) > 0 and all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in v[:16]):
                sample = [float(x) for x in v[:28] if isinstance(x, (int, float)) and x == x]
                preview = repr(v[:10])[:180]
            else:
                preview = repr(v)[:180]
        except Exception:
            preview = '<' + t_name + '>'
        items.append({'name': str(k), 'typeName': t_name, 'shape': shape, 'dtype': dtype, 'memoryBytes': max(0, mem), 'preview': preview, 'columns': cols, 'numericSample': sample})
        if len(items) >= 60:
            break
    items.sort(key=lambda x: (-x['memoryBytes'], x['name']))
    return items

def _mc_rss_and_gpu():
    rss = 0
    try:
        import ctypes
        from ctypes import wintypes
        class _PMC(ctypes.Structure):
            _fields_ = [('cb', wintypes.DWORD), ('PageFaultCount', wintypes.DWORD), ('PeakWorkingSetSize', ctypes.c_size_t), ('WorkingSetSize', ctypes.c_size_t),
                        ('QuotaPeakPagedPoolUsage', ctypes.c_size_t), ('QuotaPagedPoolUsage', ctypes.c_size_t), ('QuotaPeakNonPagedPoolUsage', ctypes.c_size_t),
                        ('QuotaNonPagedPoolUsage', ctypes.c_size_t), ('PagefileUsage', ctypes.c_size_t), ('PeakPagefileUsage', ctypes.c_size_t)]
        pmc = _PMC()
        pmc.cb = ctypes.sizeof(_PMC)
        fn = ctypes.windll.kernel32.K32GetProcessMemoryInfo
        fn.argtypes = [ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD]
        if fn(ctypes.c_void_p(-1), ctypes.byref(pmc), pmc.cb):
            rss = int(pmc.WorkingSetSize)
    except Exception:
        pass
    gpu = 0
    try:
        th = _mc_sys.modules.get('torch')
        if th is not None and th.cuda.is_available():
            gpu = int(th.cuda.memory_allocated())
    except Exception:
        pass
    return rss, gpu

def _mc_snapshot_rich_files(base_dir):
    snap = {}
    if not base_dir or not _mc_os.path.isdir(base_dir):
        return snap
    dirs = [base_dir] + [_mc_os.path.join(base_dir, s) for s in ('figures', 'outputs', 'plots', 'reports') if _mc_os.path.isdir(_mc_os.path.join(base_dir, s))]
    for d in dirs:
        try:
            for entry in _mc_os.scandir(d):
                if entry.is_file() and _mc_os.path.splitext(entry.name.lower())[1] in _MC_RICH_EXTS:
                    try:
                        st = entry.stat()
                        snap[_mc_os.path.realpath(entry.path)] = (st.st_mtime_ns, st.st_size)
                    except Exception:
                        pass
        except Exception:
            pass
    return snap

_MC_BUSY = [False]
def _mc_int_watcher(handle):
    k32 = _mc_ctypes.windll.kernel32
    while True:
        if k32.WaitForSingleObject(handle, 0xFFFFFFFF) != 0:
            return
        if _MC_BUSY[0]:
            try:
                _mc_thread.interrupt_main()
            except Exception:
                pass
try:
    _mc_k32 = _mc_ctypes.windll.kernel32
    _mc_k32.OpenEventW.restype = _mc_ctypes.c_void_p
    _mc_k32.OpenEventW.argtypes = [_mc_ctypes.c_uint32, _mc_ctypes.c_int, _mc_ctypes.c_wchar_p]
    _mc_k32.WaitForSingleObject.restype = _mc_ctypes.c_uint32
    _mc_k32.WaitForSingleObject.argtypes = [_mc_ctypes.c_void_p, _mc_ctypes.c_uint32]
    _mc_int_handle = _mc_k32.OpenEventW(0x00100000, 0, _mc_os.environ.get('MC_INT_EVENT', ''))
    if _mc_int_handle:
        _mc_threading.Thread(target=_mc_int_watcher, args=(_mc_int_handle,), daemon=True).start()
except Exception:
    pass
_mc_emit({'event': 'ready', 'version': _mc_sys.version.split()[0], 'executable': _mc_sys.executable})

while True:
    try:
        _mc_line = _MC_PROTO_IN.readline()
    except KeyboardInterrupt:
        continue
    if not _mc_line:
        break
    _mc_line = _mc_line.lstrip('﻿').strip()
    if not _mc_line.startswith('MC_EXEC:'):
        continue
    _mc_b64_cmd = _mc_line[8:]
    try:
        _mc_cmd = _mc_json.loads(_mc_b64.b64decode(_mc_b64_cmd).decode('utf-8'))
    except Exception as e:
        _mc_emit({'event': 'done', 'duration_ms': 0, 'rss_bytes': 0, 'gpu_bytes': 0, 'had_error': True, 'expr_text': 'Protocol decode error: ' + str(e), 'images': [], 'variables': []})
        continue
    code = _mc_cmd.get('code', '')
    workdir = _mc_cmd.get('workdir', '')
    _MC_CUR_ARTIFACTS = _mc_cmd.get('artifacts_dir', workdir)
    _MC_CUR_TAG = _mc_cmd.get('cell_tag', 'cell')
    _MC_DISPLAYED_DF = None
    _MC_CELL_OUTPUT_FILES = []
    _MC_CAPTURED_FIG_IDS = set()
    _MC_RICH_SEQ = 0
    had_error = False
    expr_text = ''
    df_payload = None
    t0 = _mc_time.perf_counter()
    try:
        if workdir and _mc_os.path.isdir(workdir):
            try:
                _mc_os.chdir(workdir)
            except Exception:
                pass
            if workdir not in _mc_sys.path:
                _mc_sys.path.insert(0, workdir)
        _mc_patch_viz_modules()
        _mc_before = _mc_snapshot_rich_files(workdir)
        _mc_sys.stdin = _mc_io.StringIO('')
        _MC_BUSY[0] = True
        try:
            tree = _mc_ast.parse(code, filename='<cell>', mode='exec')
            if tree.body and isinstance(tree.body[-1], _mc_ast.Expr):
                last_node = tree.body.pop()
                last_name = last_node.value.id if isinstance(last_node.value, _mc_ast.Name) else None
                if tree.body:
                    exec(compile(tree, '<cell>', 'exec'), _MC_GLOBALS)
                eval_expr = _mc_ast.Expression(last_node.value)
                _mc_ast.fix_missing_locations(eval_expr)
                val = eval(compile(eval_expr, '<cell>', 'eval'), _MC_GLOBALS)
                if val is not None:
                    _MC_GLOBALS['_'] = val
                    df_payload = _mc_extract_df_payload(val, last_name or 'Result', _MC_CUR_ARTIFACTS, _MC_CUR_TAG)
                    if df_payload is None and not _mc_try_capture_rich_value(val, allow_path_str=False):
                        val_mod = getattr(type(val), '__module__', '')
                        if not ('matplotlib' in val_mod or 'seaborn' in val_mod):
                            expr_text = repr(val)
            else:
                exec(compile(tree, '<cell>', 'exec'), _MC_GLOBALS)
        except KeyboardInterrupt:
            had_error = True
            print('\n\u23f9 Interrupted by user (variables in RAM preserved).', flush=True)
        except SystemExit as se:
            print('\n\u2139\ufe0f Cell exited with SystemExit(' + str(se.code) + '). Kernel remains warm.', flush=True)
        except SyntaxError:
            had_error = True
            _mc_tb.print_exc(limit=0)
        except BaseException:
            had_error = True
            et, ev, tb = _mc_sys.exc_info()
            while tb is not None and tb.tb_frame.f_code.co_filename != '<cell>':
                tb = tb.tb_next
            _mc_sys.stdout.write(''.join(_mc_tb.format_exception(et, ev, tb)))
            _mc_sys.stdout.flush()
        finally:
            _MC_BUSY[0] = False
        _mc_capture_open_mpl_figures(close_after=True)
        _mc_after = _mc_snapshot_rich_files(workdir)
        for _f_path, _f_stat in sorted(_mc_after.items(), key=lambda kv: kv[1][0]):
            if _f_path not in _mc_before or _mc_before[_f_path] != _f_stat:
                _mc_record_output_file(_f_path)
        if df_payload is None and _MC_DISPLAYED_DF is not None:
            df_payload = _MC_DISPLAYED_DF
    except KeyboardInterrupt:
        had_error = True
    dt_ms = (_mc_time.perf_counter() - t0) * 1000.0
    try:
        _mc_sys.stdout.flush()
        _mc_sys.stderr.flush()
    except Exception:
        pass
    try:
        rss_b, gpu_b = _mc_rss_and_gpu()
        vars_list = _mc_inspect_variables()
    except BaseException:
        rss_b, gpu_b, vars_list = 0, 0, []
    _mc_emit({'event': 'done', 'duration_ms': round(dt_ms, 3), 'rss_bytes': rss_b, 'gpu_bytes': gpu_b, 'had_error': had_error, 'expr_text': expr_text,
              'images': list(_MC_CELL_OUTPUT_FILES), 'dataframe': df_payload, 'variables': vars_list})
";
    }

    /// <summary>Non-Python cells: SQL through the warm Python kernel (sqlite + live DataFrames as tables), compiled/scripted languages
    /// through the toolchains on PATH. Output streams live; a missing toolchain reports how to install it instead of failing silently.</summary>
    public static class NbRunner
    {
        public class Result { public string Output = ""; public bool HadError; public double Ms; public List<string> Files = new List<string>(); }

        static readonly Dictionary<string, Process> Running = new Dictionary<string, Process>();

        public static void Cancel(string cellId)
        {
            Process p; lock (Running) Running.TryGetValue(cellId, out p);
            if (p == null) return;
            try { Process.Start(new ProcessStartInfo("taskkill", "/T /F /PID " + p.Id) { UseShellExecute = false, CreateNoWindow = true }); }
            catch (Exception ex) { Debug.WriteLine("cell cancel: " + ex.Message); }
        }

        public static string SqlScript(string content, out bool explicitDb)
        {
            string db = Path.Combine(NbStore.WorkingDirectory, "notebook.db");
            explicitDb = false;
            var lines = (content ?? "").Replace("\r\n", "\n").Split('\n');
            foreach (var line in lines)
                if (line.ToLowerInvariant().Contains("connect to:"))
                {
                    explicitDb = true;
                    int i = line.IndexOf("sqlite:///", StringComparison.Ordinal);
                    if (i >= 0) db = line.Substring(i + 10).Trim();
                }
            string sql = string.Join("\n", lines.Where(l => !l.Trim().StartsWith("--")));
            string dbB64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(db)), sqlB64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(sql));
            return "import sqlite3 as _mc_sq3, base64 as _mc_sq_b64\n" +
                   "_mc_db_p = _mc_sq_b64.b64decode('" + dbB64 + "').decode('utf-8')\n" +
                   "_mc_sql_txt = _mc_sq_b64.b64decode('" + sqlB64 + "').decode('utf-8').strip()\n" +
                   "_mc_conn = _mc_sq3.connect(_mc_db_p)\n" +
                   "try:\n" +
                   "    try:\n" +
                   "        import pandas as _mc_pd\n" +
                   "        _mc_existing_tbls = {r[0] for r in _mc_conn.execute(\"SELECT name FROM sqlite_master WHERE type='table'\").fetchall()}\n" +
                   "        for _mc_vn, _mc_vv in list(globals().items()):\n" +
                   "            if not _mc_vn.startswith('_') and type(_mc_vv).__name__ == 'DataFrame' and hasattr(_mc_vv, 'to_sql') and _mc_vn not in _mc_existing_tbls:\n" +
                   "                try:\n" +
                   "                    _mc_vv.to_sql(_mc_vn, _mc_conn, index=False, if_exists='replace')\n" +
                   "                except Exception:\n" +
                   "                    pass\n" +
                   "    except Exception:\n" +
                   "        _mc_pd = None\n" +
                   "    _mc_stmts = [s.strip() for s in _mc_sql_txt.split(';') if s.strip()]\n" +
                   "    for _mc_idx, _mc_st in enumerate(_mc_stmts):\n" +
                   "        _mc_upper = _mc_st.upper()\n" +
                   "        _mc_is_query = _mc_upper.startswith('SELECT') or _mc_upper.startswith('WITH') or _mc_upper.startswith('PRAGMA')\n" +
                   "        if _mc_is_query and _mc_idx == len(_mc_stmts) - 1 and _mc_pd is not None:\n" +
                   "            _mc_df_out = _mc_pd.read_sql_query(_mc_st, _mc_conn)\n" +
                   "            display(_mc_df_out)\n" +
                   "        elif _mc_is_query:\n" +
                   "            _mc_cur = _mc_conn.execute(_mc_st)\n" +
                   "            _mc_rows = _mc_cur.fetchall()\n" +
                   "            _mc_cols = [d[0] for d in (_mc_cur.description or [])]\n" +
                   "            if _mc_cols:\n" +
                   "                print(' | '.join(_mc_cols))\n" +
                   "                print('-' * (len(' | '.join(_mc_cols)) + 6))\n" +
                   "                for _mc_r in _mc_rows[:200]:\n" +
                   "                    print(' | '.join(str(x) for x in _mc_r))\n" +
                   "                print('\\n' + str(len(_mc_rows)) + ' rows returned')\n" +
                   "        else:\n" +
                   "            _mc_cur = _mc_conn.execute(_mc_st)\n" +
                   "            _mc_conn.commit()\n" +
                   "            print('Query executed successfully. Rows affected: ' + str(_mc_cur.rowcount))\n" +
                   "finally:\n" +
                   "    _mc_conn.close()\n";
        }

        static string Which(params string[] names)
        {
            string path = Environment.GetEnvironmentVariable("PATH") ?? "";
            var exts = new[] { ".exe", ".cmd", ".bat", "" };
            foreach (var n in names)
            {
                if (Path.IsPathRooted(n) && File.Exists(n)) return n;
                foreach (var dir in path.Split(';'))
                {
                    if (dir.Trim().Length == 0) continue;
                    foreach (var e in exts)
                    {
                        try { string f = Path.Combine(dir.Trim().Trim('"'), n + e); if (File.Exists(f)) return f; }
                        catch (ArgumentException) { }
                    }
                }
            }
            return null;
        }

        static string RHome()
        {
            string r = Which("Rscript");
            if (r != null) return r;
            foreach (var root in new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles) + "\\R", "C:\\Program Files\\R" })
            {
                try
                {
                    if (!Directory.Exists(root)) continue;
                    var best = Directory.GetDirectories(root).OrderByDescending(d => d).Select(d => Path.Combine(d, "bin", "Rscript.exe")).FirstOrDefault(File.Exists);
                    if (best != null) return best;
                }
                catch (Exception ex) { Debug.WriteLine("R probe: " + ex.Message); }
            }
            return null;
        }

        /// <summary>Runs a non-Python cell. Callbacks on the UI thread.</summary>
        public static void Run(NbCell cell, string cellTag, Action<string> onStream, Action<Result> onDone)
        {
            string lang = cell.Language, content = cell.Content ?? "";
            string wd = NbStore.WorkingDirectory, artifacts = Path.Combine(wd, "artifacts");
            try { Directory.CreateDirectory(artifacts); } catch (Exception ex) { Debug.WriteLine("artifacts: " + ex.Message); }
            string id8 = Guid.NewGuid().ToString("N").Substring(0, 8);
            string exe = null, args = null, tempDir = null;
            var cleanup = new List<string>();
            Func<Result, Result> post = null;
            try
            {
                switch (lang)
                {
                    case "R":
                        {
                            string r = RHome();
                            if (r == null) { Finish(onDone, "\u274C R is not installed. Install R from https://cran.r-project.org/ (Rscript must be on PATH).", true, 0); return; }
                            string tmp = Path.Combine(wd, "temp_script_" + id8 + ".R"); cleanup.Add(tmp);
                            string a = artifacts.Replace("\\", "/");
                            string setup = "setwd(\"" + wd.Replace("\\", "/") + "\")\n.plot_counter <- 0\n.save_plot <- function() {\n    .plot_counter <<- .plot_counter + 1\n    filename <- file.path(\"" + a + "\", paste0(\"" + cellTag + "_rplot_\", .plot_counter, \".png\"))\n    dev.copy(png, filename, width = 1200, height = 840, res = 144)\n    dev.off()\n    cat(paste0(\"[IMAGE:\", filename, \"]\\n\"))\n}\n";
                            string save = "\ntryCatch({\n    if (dev.cur() > 1) { .save_plot() }\n}, error = function(e) {})\n";
                            File.WriteAllText(tmp, setup + content + save, new UTF8Encoding(false));
                            exe = r; args = "--vanilla \"" + tmp + "\"";
                            break;
                        }
                    case "R Markdown":
                        {
                            string r = RHome();
                            if (r == null) { Finish(onDone, "\u274C R is not installed. Install R from https://cran.r-project.org/", true, 0); return; }
                            string rmd = Path.Combine(wd, "temp_" + id8 + ".Rmd"), html = Path.Combine(wd, "report_" + id8 + ".html"); cleanup.Add(rmd);
                            File.WriteAllText(rmd, content, new UTF8Encoding(false));
                            exe = r; args = "-e \"rmarkdown::render('" + rmd.Replace("\\", "/") + "', output_file = '" + html.Replace("\\", "/") + "', quiet = TRUE)\"";
                            post = res =>
                            {
                                if (!res.HadError && File.Exists(html)) { res.Output = "\u2705 R Markdown rendered successfully!\n\U0001F4C4 Output: " + Path.GetFileName(html); res.Files.Add(html); }
                                else { res.HadError = true; res.Output = "\u274C R Markdown render failed:\n" + res.Output; }
                                return res;
                            };
                            break;
                        }
                    case "Julia":
                        {
                            string j = Which("julia");
                            if (j == null) { Finish(onDone, "\u274C Julia is not installed. Install from https://julialang.org/downloads/ (julia must be on PATH).", true, 0); return; }
                            string tmp = Path.Combine(wd, "temp_" + id8 + ".jl"); cleanup.Add(tmp);
                            File.WriteAllText(tmp, content, new UTF8Encoding(false));
                            exe = j; args = "\"" + tmp + "\"";
                            break;
                        }
                    case "LaTeX":
                        {
                            string tex = Path.Combine(artifacts, "latex_" + id8 + ".tex"), pdf = Path.Combine(artifacts, "latex_" + id8 + ".pdf");
                            string pdflatex = Which("pdflatex", "xelatex", "lualatex");
                            if (pdflatex == null)
                            {
                                // Built-in TeX preview (like the Mac without MacTeX): the cell's .tex is rendered by the inline Markdown/TeX card.
                                string preview = Path.Combine(artifacts, "cell_" + cell.Id.Substring(0, Math.Min(8, cell.Id.Length)) + ".tex");
                                File.WriteAllText(preview, content, new UTF8Encoding(false));
                                var r0 = new Result(); r0.Files.Add(preview); Dispatch(() => onDone(r0)); return;
                            }
                            File.WriteAllText(tex, content, new UTF8Encoding(false));
                            foreach (var e in new[] { "aux", "log", "out", "toc", "tex" }) cleanup.Add(Path.Combine(artifacts, "latex_" + id8 + "." + e));
                            exe = pdflatex; args = "-interaction=nonstopmode -output-directory=\"" + artifacts + "\" \"" + tex + "\"";
                            string logPath = Path.Combine(artifacts, "latex_" + id8 + ".log");
                            post = res =>
                            {
                                if (File.Exists(pdf)) { res.Output = ""; res.HadError = false; res.Files.Add(pdf); return res; }
                                string log = ""; try { if (File.Exists(logPath)) log = File.ReadAllText(logPath); } catch (IOException) { }
                                var errs = log.Split('\n').Where(l => l.Contains("!") || l.Contains("Error")).ToList();
                                res.HadError = true; res.Output = "\u274C LaTeX compilation failed:\n" + (errs.Count > 0 ? string.Join("\n", errs) : res.Output);
                                return res;
                            };
                            break;
                        }
                    case "Ardium":
                        Finish(onDone, "\u274C The Ardium toolchain ships with MicroCode for macOS only. Run this cell on the Mac, or switch the cell language.", true, 0);
                        return;
                    case "Objective-C":
                        {
                            string clang = Which("clang");
                            if (clang == null) { Finish(onDone, "\u274C Objective-C needs clang with the GNUstep Foundation framework, which is not installed on this PC.", true, 0); return; }
                            tempDir = Path.Combine(Path.GetTempPath(), "MicroCodeCells", id8); Directory.CreateDirectory(tempDir);
                            string src = Path.Combine(tempDir, "cell.m"), bin = Path.Combine(tempDir, "cell.exe");
                            File.WriteAllText(src, content, new UTF8Encoding(false));
                            exe = "cmd.exe"; args = "/d /s /c \"\"" + clang + "\" -O2 \"" + src + "\" -o \"" + bin + "\" && \"" + bin + "\"\"";
                            break;
                        }
                    default:
                        {
                            // Rust, Go, C++, Java, C#: the same local toolchains Code mode uses (Runner.CommandFor)
                            tempDir = Path.Combine(Path.GetTempPath(), "MicroCodeCells", id8); Directory.CreateDirectory(tempDir);
                            string key = lang == "C++" ? "cpp" : lang == "C#" ? "csharp" : lang.ToLowerInvariant();
                            string file = Path.Combine(tempDir, (lang == "Java" ? "Main" : "cell") + "." + CellLang.Get(lang).Ext);
                            File.WriteAllText(file, content, new UTF8Encoding(false));
                            if (lang == "C#")
                            {
                                string dotnet = Which("dotnet");
                                if (dotnet == null) { Finish(onDone, "\u274C C# cells need the .NET SDK (dotnet). Install it from https://dot.net and try again.", true, 0); return; }
                                File.WriteAllText(Path.Combine(tempDir, "cell.csproj"), "<Project Sdk=\"Microsoft.NET.Sdk\"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net8.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>disable</Nullable></PropertyGroup></Project>");
                                exe = dotnet; args = "run --project \"" + Path.Combine(tempDir, "cell.csproj") + "\"";
                                break;
                            }
                            if (!Runner.CommandFor(key, file, out exe, out args)) { Finish(onDone, "\u274C No local runtime is configured for " + lang + ".", true, 0); return; }
                            string tool = key == "rust" ? "rustc" : key == "go" ? "go" : key == "cpp" ? "g++" : key == "java" ? "java" : null;
                            if (tool != null && Which(tool) == null)
                            {
                                string hint = key == "rust" ? "Install Rust from https://rustup.rs" : key == "go" ? "Install Go from https://go.dev/dl/" : key == "cpp" ? "Install a C++ compiler (MSYS2 / MinGW-w64 g++) and add it to PATH" : "Install a Java JDK (java on PATH)";
                                Finish(onDone, "\u274C " + lang + " toolchain not found (" + tool + "). " + hint + ".", true, 0);
                                return;
                            }
                            break;
                        }
                }
            }
            catch (Exception ex) { Finish(onDone, "\u274C Error: " + ex.Message, true, 0); return; }

            string cellId = cell.Id, exeF = exe, argsF = args, tempF = tempDir;
            var cleanupF = cleanup;
            Task.Run(() =>
            {
                var sw = Stopwatch.StartNew();
                var res = new Result();
                var live = new StringBuilder();
                DateTime last = DateTime.MinValue;
                try
                {
                    var psi = new ProcessStartInfo(exeF, argsF)
                    {
                        UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true, WorkingDirectory = tempF ?? wd,
                        StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
                    };
                    var p = new Process { StartInfo = psi };
                    DataReceivedEventHandler h = (s, e) =>
                    {
                        if (e.Data == null) return;
                        string snap = null;
                        lock (live)
                        {
                            live.Append(e.Data).Append('\n');
                            if ((DateTime.Now - last).TotalMilliseconds > 60) { last = DateTime.Now; snap = live.ToString(); }
                        }
                        if (snap != null && onStream != null) Dispatch(() => onStream(snap));
                    };
                    p.OutputDataReceived += h; p.ErrorDataReceived += h;
                    p.Start();
                    lock (Running) Running[cellId] = p;
                    p.BeginOutputReadLine(); p.BeginErrorReadLine();
                    if (!p.WaitForExit(600000)) { try { p.Kill(); } catch (Exception kx) { Debug.WriteLine("cell kill: " + kx.Message); } lock (live) live.Append("\n\u23F9 Stopped after 10 minutes.\n"); }
                    p.WaitForExit();
                    res.HadError = p.ExitCode != 0;
                }
                catch (Exception ex) { res.HadError = true; lock (live) live.Append("\u274C Failed to start " + exeF + ": " + ex.Message); }
                finally { lock (Running) Running.Remove(cellId); }
                sw.Stop();
                lock (live) res.Output = live.ToString().TrimEnd('\n');
                res.Ms = sw.Elapsed.TotalMilliseconds;
                // R plots are announced as [IMAGE:path] markers (parseEmbeddedImageMarkers)
                foreach (Match m in Regex.Matches(res.Output, @"\[IMAGE:([^\]]+)\]")) { string f = m.Groups[1].Value.Trim().Replace('/', '\\'); if (File.Exists(f) && !res.Files.Contains(f)) res.Files.Add(f); }
                res.Output = Regex.Replace(res.Output, @"\[IMAGE:[^\]]+\]\r?\n?", "").Trim('\n');
                if (post != null) res = post(res);
                foreach (var f in cleanupF) { try { if (File.Exists(f)) File.Delete(f); } catch (IOException ex) { Debug.WriteLine("cleanup: " + ex.Message); } }
                if (tempF != null) { try { Directory.Delete(tempF, true); } catch (Exception ex) { Debug.WriteLine("cleanup dir: " + ex.Message); } }
                Dispatch(() => onDone(res));
            });
        }

        static void Finish(Action<Result> onDone, string text, bool err, double ms) { var r = new Result { Output = text, HadError = err, Ms = ms }; Dispatch(() => onDone(r)); }
        static void Dispatch(Action a) { var app = Application.Current; if (app != null) app.Dispatcher.BeginInvoke(a); else a(); }
    }
}
