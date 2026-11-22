// IDEBrowserAutomationService.scanActivePorts + UniversalAppPreviewBridge.buildAndPreview (macOS) for Windows:
// listening localhost TCP ports with their owning process (GetExtendedTcpTable), and a dev-server runner that starts the
// workspace's own "dev"/"start" script, streams its output and reports the URL it prints.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

namespace MicroCode.Views
{
    public class LocalPort
    {
        public int Port, Pid;
        public string Process, Address;
        public bool LooksLikeDevServer;
    }

    public static class LocalPorts
    {
        [DllImport("iphlpapi.dll", SetLastError = true)]
        static extern uint GetExtendedTcpTable(IntPtr table, ref int size, bool order, int family, int tableClass, uint reserved);
        const int AF_INET = 2, AF_INET6 = 23, TCP_TABLE_OWNER_PID_LISTENER = 3;

        static readonly HashSet<string> SystemProcesses = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "System", "Idle", "svchost", "lsass", "wininit", "services", "spoolsv", "smss", "csrss", "MsMpEng", "NisSrv", "SearchIndexer",
            "MicroCode", "jhi_service", "WmiPrvSE", "mDNSResponder", "OneDrive", "LGHUB", "lghub_agent", "lghub_system_tray", "NVIDIA Web Helper",
            "NVDisplay.Container", "nvcontainer", "Steam", "steamwebhelper", "Discord", "ms-teams", "Teams", "Spotify", "AcerQAAgent", "msedge", "chrome"
        };
        static readonly HashSet<string> DevRuntimes = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "node", "bun", "deno", "python", "python3", "pythonw", "ruby", "php", "dotnet", "go", "hugo", "caddy", "nginx", "httpd", "esbuild", "vite", "flask", "uvicorn", "gunicorn", "iisexpress", "http-server", "live-server"
        };
        static readonly int[] DevPorts = { 3000, 3001, 3002, 4000, 4200, 4321, 5000, 5173, 5174, 5500, 8000, 8080, 8081, 8888, 1313, 9000 };

        /// <summary>User localhost servers (system services and well-known desktop apps filtered out), lowest port first.</summary>
        public static List<LocalPort> Listening()
        {
            var seen = new Dictionary<int, LocalPort>();
            foreach (int family in new[] { AF_INET, AF_INET6 })
            {
                int size = 0;
                GetExtendedTcpTable(IntPtr.Zero, ref size, false, family, TCP_TABLE_OWNER_PID_LISTENER, 0);
                if (size <= 0) continue;
                IntPtr buf = Marshal.AllocHGlobal(size);
                try
                {
                    if (GetExtendedTcpTable(buf, ref size, false, family, TCP_TABLE_OWNER_PID_LISTENER, 0) != 0) continue;
                    int count = Marshal.ReadInt32(buf);
                    int rowSize = family == AF_INET ? 24 : 56;
                    for (int i = 0; i < count; i++)
                    {
                        IntPtr row = buf + 4 + i * rowSize;
                        int rawPort, pid; string addr;
                        if (family == AF_INET)
                        {
                            uint a = (uint)Marshal.ReadInt32(row, 4);
                            addr = (a & 0xFF) + "." + ((a >> 8) & 0xFF) + "." + ((a >> 16) & 0xFF) + "." + ((a >> 24) & 0xFF);
                            rawPort = Marshal.ReadInt32(row, 8);
                            pid = Marshal.ReadInt32(row, 20);
                        }
                        else
                        {
                            var b = new byte[16];
                            Marshal.Copy(row, b, 0, 16);
                            addr = b.All(x => x == 0) ? "::" : (b.Take(15).All(x => x == 0) && b[15] == 1 ? "::1" : "ipv6");
                            rawPort = Marshal.ReadInt32(row, 20);
                            pid = Marshal.ReadInt32(row, 52);
                        }
                        int port = ((rawPort & 0xFF) << 8) | ((rawPort >> 8) & 0xFF);
                        if (port < 1024 || seen.ContainsKey(port)) continue;
                        if (addr != "127.0.0.1" && addr != "0.0.0.0" && addr != "::" && addr != "::1") continue;
                        string name = ProcessName(pid);
                        if (name == null || SystemProcesses.Contains(name)) continue;
                        // user dev servers only: a dev runtime below the ephemeral range, or anything on a usual dev port
                        bool runtime = DevRuntimes.Contains(name) && port < 49152, devPort = DevPorts.Contains(port);
                        if (!runtime && !devPort) continue;
                        seen[port] = new LocalPort { Port = port, Pid = pid, Process = name, Address = addr, LooksLikeDevServer = true };
                    }
                }
                finally { Marshal.FreeHGlobal(buf); }
            }
            return seen.Values.OrderBy(p => p.Port).ToList();
        }

        static string ProcessName(int pid)
        {
            try { using (var p = Process.GetProcessById(pid)) return p.ProcessName; }
            catch (ArgumentException) { return null; }          // exited
            catch (InvalidOperationException) { return null; }
        }

        /// <summary>The port a web preview should open: a dev runtime on a usual dev port first.</summary>
        public static LocalPort Best(List<LocalPort> ports)
        {
            return ports.Where(p => p.LooksLikeDevServer).OrderBy(p => DevRuntimes.Contains(p.Process) ? 0 : 1).ThenBy(p => Array.IndexOf(DevPorts, p.Port) < 0 ? 99 : Array.IndexOf(DevPorts, p.Port)).FirstOrDefault();
        }
    }

    /// <summary>Runs the workspace dev server (package.json "dev"/"start"/"serve") and watches its output for the local URL.</summary>
    public class DevServer
    {
        public static DevServer Current;
        static readonly Regex UrlRe = new Regex(@"https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]):(\d{2,5})(/[^\s'""]*)?", RegexOptions.IgnoreCase);
        static readonly Regex AnsiRe = new Regex(@"\x1B\[[0-9;?]*[A-Za-z]");

        Process _p;
        readonly StringBuilder _log = new StringBuilder();
        public string Workspace, Command, Url;
        public bool Running { get { try { return _p != null && !_p.HasExited; } catch (InvalidOperationException) { return false; } } }
        public string Log { get { lock (_log) return _log.ToString(); } }
        public event Action Changed;      // raised on a worker thread
        public event Action<string> UrlFound;

        /// <summary>"npm run dev" etc. for the workspace, or null when it has no runnable web script.</summary>
        public static string DetectCommand(string ws)
        {
            if (string.IsNullOrEmpty(ws)) return null;
            string pkg = Path.Combine(ws, "package.json");
            if (!File.Exists(pkg)) return null;
            try
            {
                var o = new JavaScriptSerializer().DeserializeObject(File.ReadAllText(pkg)) as Dictionary<string, object>;
                var scripts = o != null && o.ContainsKey("scripts") ? o["scripts"] as Dictionary<string, object> : null;
                if (scripts == null) return null;
                string runner = File.Exists(Path.Combine(ws, "pnpm-lock.yaml")) ? "pnpm" : File.Exists(Path.Combine(ws, "yarn.lock")) ? "yarn" : File.Exists(Path.Combine(ws, "bun.lockb")) || File.Exists(Path.Combine(ws, "bun.lock")) ? "bun" : "npm";
                foreach (var s in new[] { "dev", "start", "serve", "preview" })
                    if (scripts.ContainsKey(s)) return runner == "npm" ? (s == "start" ? "npm start" : "npm run " + s) : runner + " " + (runner == "yarn" ? "" : "run ") + s;
            }
            catch (ArgumentException ex) { Debug.WriteLine("package.json: " + ex.Message); }
            catch (InvalidOperationException ex) { Debug.WriteLine("package.json: " + ex.Message); }
            catch (IOException ex) { Debug.WriteLine("package.json: " + ex.Message); }
            return null;
        }

        public static DevServer Start(string ws, string command)
        {
            if (Current != null) Current.Stop();
            var d = new DevServer { Workspace = ws, Command = command };
            Current = d;
            d.Append("$ " + command + "\n");
            var psi = new ProcessStartInfo("cmd.exe", "/d /s /c \"" + command + "\"")
            {
                WorkingDirectory = ws, UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
            };
            psi.EnvironmentVariables["FORCE_COLOR"] = "0";
            psi.EnvironmentVariables["BROWSER"] = "none"; // create-react-app etc.: don't pop a browser, the preview shows it
            try
            {
                d._p = Process.Start(psi);
                d._p.EnableRaisingEvents = true;
                d._p.OutputDataReceived += (s, e) => { if (e.Data != null) d.Line(e.Data); };
                d._p.ErrorDataReceived += (s, e) => { if (e.Data != null) d.Line(e.Data); };
                d._p.Exited += delegate { d.Append("\n[process exited with code " + SafeExitCode(d._p) + "]\n"); };
                d._p.BeginOutputReadLine();
                d._p.BeginErrorReadLine();
            }
            catch (System.ComponentModel.Win32Exception ex) { d.Append("Could not start: " + ex.Message + "\n"); }
            return d;
        }

        static string SafeExitCode(Process p) { try { return p.ExitCode.ToString(); } catch (InvalidOperationException) { return "?"; } }

        void Line(string raw)
        {
            string line = AnsiRe.Replace(raw, "");
            Append(line + "\n");
            if (Url != null) return;
            var m = UrlRe.Match(line);
            if (!m.Success) return;
            Url = "http://localhost:" + m.Groups[1].Value + (m.Groups[2].Success ? m.Groups[2].Value : "/");
            if (UrlFound != null) UrlFound(Url);
        }

        void Append(string s)
        {
            lock (_log) { _log.Append(s); if (_log.Length > 200000) _log.Remove(0, _log.Length - 150000); }
            if (Changed != null) Changed();
        }

        /// <summary>Stops the whole process tree (npm → node → esbuild …).</summary>
        public void Stop()
        {
            if (_p == null) return;
            try
            {
                if (!_p.HasExited)
                {
                    using (var k = Process.Start(new ProcessStartInfo("taskkill", "/PID " + _p.Id + " /T /F") { UseShellExecute = false, CreateNoWindow = true }))
                        if (k != null) k.WaitForExit(5000);
                }
            }
            catch (InvalidOperationException ex) { Debug.WriteLine("stop dev server: " + ex.Message); }
            catch (System.ComponentModel.Win32Exception ex) { Debug.WriteLine("stop dev server: " + ex.Message); }
            Append("[stopped]\n");
            if (Current == this) Current = null;
        }
    }
}
