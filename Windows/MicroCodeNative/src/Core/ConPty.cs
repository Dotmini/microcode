// Real Win32 ConPTY pseudo-console terminal + graceful redirected Process fallback for older Windows (<1809) and Mono.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace MicroCode.Core
{
    public static class ConPty
    {
        static readonly Regex RxOsc = new Regex(@"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)", RegexOptions.Compiled);
        static readonly Regex RxDcs = new Regex(@"\x1B[PX^_][\s\S]*?\x1B\\", RegexOptions.Compiled);
        static readonly Regex RxCsi = new Regex(@"(?:\x1B\[|\x9B)[0-9;?]*[ -/]*[@-~]", RegexOptions.Compiled);
        static readonly Regex RxCharset = new Regex(@"\x1B[\(\)\*\+\-\./][0-9A-Za-z]", RegexOptions.Compiled);
        static readonly Regex RxEsc2 = new Regex(@"\x1B[@-Z\\\-_]", RegexOptions.Compiled);

        public static bool IsWindows
        {
            get { return Environment.OSVersion.Platform == PlatformID.Win32NT; }
        }

        static bool IsMonoRuntime
        {
            get { return Type.GetType("Mono.Runtime") != null; }
        }

        public static bool SupportsConPty
        {
            get
            {
                if (!IsWindows || IsMonoRuntime) return false;
                try
                {
                    IntPtr mod = NativeMethods.GetModuleHandle("kernel32.dll");
                    if (mod == IntPtr.Zero) return false;
                    return NativeMethods.GetProcAddress(mod, "CreatePseudoConsole") != IntPtr.Zero;
                }
                catch
                {
                    return false;
                }
            }
        }

        /// <summary>Strips ANSI/VT100/xterm CSI, OSC, DCS, charset, and BEL control sequences from terminal output.</summary>
        public static string StripAnsi(string text)
        {
            if (string.IsNullOrEmpty(text)) return text ?? "";
            string s = RxOsc.Replace(text, "");
            s = RxDcs.Replace(s, "");
            s = RxCsi.Replace(s, "");
            s = RxCharset.Replace(s, "");
            s = RxEsc2.Replace(s, "");
            s = s.Replace("\x1B", "").Replace("\x07", "");
            return s;
        }

        internal static class NativeMethods
        {
            public const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
            public const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
            public const int STARTF_USESTDHANDLES = 0x00000100;
            public const uint INFINITE = 0xFFFFFFFF;
            public static readonly IntPtr PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = new IntPtr(0x00020016);

            [StructLayout(LayoutKind.Sequential)]
            public struct COORD
            {
                public short X;
                public short Y;
                public COORD(short x, short y) { X = x; Y = y; }
            }

            [StructLayout(LayoutKind.Sequential)]
            public struct SECURITY_ATTRIBUTES
            {
                public int nLength;
                public IntPtr lpSecurityDescriptor;
                [MarshalAs(UnmanagedType.Bool)]
                public bool bInheritHandle;
            }

            [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
            public struct STARTUPINFO
            {
                public int cb;
                public IntPtr lpReserved;
                public IntPtr lpDesktop;
                public IntPtr lpTitle;
                public int dwX;
                public int dwY;
                public int dwXSize;
                public int dwYSize;
                public int dwXCountChars;
                public int dwYCountChars;
                public int dwFillAttribute;
                public int dwFlags;
                public short wShowWindow;
                public short cbReserved2;
                public IntPtr lpReserved2;
                public IntPtr hStdInput;
                public IntPtr hStdOutput;
                public IntPtr hStdError;
            }

            [StructLayout(LayoutKind.Sequential)]
            public struct STARTUPINFOEX
            {
                public STARTUPINFO StartupInfo;
                public IntPtr lpAttributeList;
            }

            [StructLayout(LayoutKind.Sequential)]
            public struct PROCESS_INFORMATION
            {
                public IntPtr hProcess;
                public IntPtr hThread;
                public int dwProcessId;
                public int dwThreadId;
            }

            [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            public static extern IntPtr GetModuleHandle(string lpModuleName);

            [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true, ExactSpelling = true)]
            public static extern IntPtr GetProcAddress(IntPtr hModule, string procName);

            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern int CreatePseudoConsole(COORD size, IntPtr hInput, IntPtr hOutput, uint dwFlags, out IntPtr phPC);

            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern int ResizePseudoConsole(IntPtr hPC, COORD size);

            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern void ClosePseudoConsole(IntPtr hPC);

            [DllImport("kernel32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool CreatePipe(out IntPtr hReadPipe, out IntPtr hWritePipe, ref SECURITY_ATTRIBUTES lpPipeAttributes, uint nSize);

            [DllImport("kernel32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool InitializeProcThreadAttributeList(IntPtr lpAttributeList, int dwAttributeCount, int dwFlags, ref IntPtr lpSize);

            [DllImport("kernel32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool UpdateProcThreadAttribute(
                IntPtr lpAttributeList,
                uint dwFlags,
                IntPtr Attribute,
                IntPtr lpValue,
                IntPtr cbSize,
                IntPtr lpPreviousValue,
                IntPtr lpReturnSize);

            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern void DeleteProcThreadAttributeList(IntPtr lpAttributeList);

            [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool CreateProcess(
                string lpApplicationName,
                StringBuilder lpCommandLine,
                IntPtr lpProcessAttributes,
                IntPtr lpThreadAttributes,
                [MarshalAs(UnmanagedType.Bool)] bool bInheritHandles,
                uint dwCreationFlags,
                IntPtr lpEnvironment,
                string lpCurrentDirectory,
                ref STARTUPINFOEX lpStartupInfo,
                out PROCESS_INFORMATION lpProcessInformation);

            [DllImport("kernel32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool ReadFile(IntPtr hFile, byte[] lpBuffer, int nNumberOfBytesToRead, out int lpNumberOfBytesRead, IntPtr lpOverlapped);

            [DllImport("kernel32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool WriteFile(IntPtr hFile, byte[] lpBuffer, int nNumberOfBytesToWrite, out int lpNumberOfBytesWritten, IntPtr lpOverlapped);

            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);

            [DllImport("kernel32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool GetExitCodeProcess(IntPtr hProcess, out uint lpExitCode);

            [DllImport("kernel32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool TerminateProcess(IntPtr hProcess, uint uExitCode);

            [DllImport("kernel32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool CloseHandle(IntPtr hObject);
        }
    }

    public class TerminalSession : IDisposable
    {
        readonly object _gate = new object();
        readonly object _writeGate = new object();
        IntPtr _hPC = IntPtr.Zero;
        IntPtr _hPipeInWrite = IntPtr.Zero;
        IntPtr _hPipeOutRead = IntPtr.Zero;
        IntPtr _hProcess = IntPtr.Zero;
        IntPtr _hThread = IntPtr.Zero;
        Process _fallbackProc;
        int _exitedRaised;
        volatile bool _running;

        public bool UsingConPty { get; private set; }
        public bool IsRunning { get { return _running; } }
        public int ExitCode { get; private set; }
        public int ProcessId { get; private set; }
        public int Cols { get; private set; }
        public int Rows { get; private set; }

        public event Action<string> OutputReceived;
        public event Action<int> Exited;

        public bool Start(string shell, string cwd)
        {
            return Start(shell, cwd, 120, 30);
        }

        public bool Start(string shell, string cwd, int cols, int rows)
        {
            Stop();
            Cols = cols > 0 ? cols : 120;
            Rows = rows > 0 ? rows : 30;
            ExitCode = 0;
            ProcessId = 0;
            _exitedRaised = 0;

            string cmd = ResolveShell(shell);
            string dir = !string.IsNullOrEmpty(cwd) && Directory.Exists(cwd) ? cwd : Environment.CurrentDirectory;

            if (ConPty.SupportsConPty)
            {
                if (TryStartConPty(cmd, dir, (short)Cols, (short)Rows))
                {
                    UsingConPty = true;
                    _running = true;
                    return true;
                }
            }

            UsingConPty = false;
            return StartFallback(cmd, dir);
        }

        static string ResolveShell(string shell)
        {
            if (!string.IsNullOrWhiteSpace(shell)) return shell.Trim();
            if (ConPty.IsWindows) return "cmd.exe";
            if (File.Exists("/bin/zsh")) return "/bin/zsh";
            if (File.Exists("/bin/bash")) return "/bin/bash";
            return "/bin/sh";
        }

        bool TryStartConPty(string commandLine, string cwd, short cols, short rows)
        {
            IntPtr hInRead = IntPtr.Zero, hInWrite = IntPtr.Zero;
            IntPtr hOutRead = IntPtr.Zero, hOutWrite = IntPtr.Zero;
            IntPtr hPC = IntPtr.Zero;
            IntPtr attrList = IntPtr.Zero;

            try
            {
                var sa = new ConPty.NativeMethods.SECURITY_ATTRIBUTES();
                sa.nLength = Marshal.SizeOf(typeof(ConPty.NativeMethods.SECURITY_ATTRIBUTES));
                sa.bInheritHandle = true;
                sa.lpSecurityDescriptor = IntPtr.Zero;

                if (!ConPty.NativeMethods.CreatePipe(out hInRead, out hInWrite, ref sa, 0)) return false;
                if (!ConPty.NativeMethods.CreatePipe(out hOutRead, out hOutWrite, ref sa, 0)) return false;

                var size = new ConPty.NativeMethods.COORD(cols, rows);
                int hr = ConPty.NativeMethods.CreatePseudoConsole(size, hInRead, hOutWrite, 0, out hPC);
                if (hr != 0 || hPC == IntPtr.Zero) return false;

                IntPtr listSize = IntPtr.Zero;
                ConPty.NativeMethods.InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref listSize);
                if (listSize == IntPtr.Zero) return false;

                attrList = Marshal.AllocHGlobal(listSize);
                if (!ConPty.NativeMethods.InitializeProcThreadAttributeList(attrList, 1, 0, ref listSize)) return false;

                if (!ConPty.NativeMethods.UpdateProcThreadAttribute(
                    attrList,
                    0,
                    ConPty.NativeMethods.PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                    hPC,
                    new IntPtr(IntPtr.Size),
                    IntPtr.Zero,
                    IntPtr.Zero))
                {
                    return false;
                }

                var si = new ConPty.NativeMethods.STARTUPINFOEX();
                si.StartupInfo.cb = Marshal.SizeOf(typeof(ConPty.NativeMethods.STARTUPINFOEX));
                si.lpAttributeList = attrList;

                var pi = new ConPty.NativeMethods.PROCESS_INFORMATION();
                var cmdBuf = new StringBuilder(commandLine, Math.Max(commandLine.Length + 1, 260));
                uint flags = ConPty.NativeMethods.EXTENDED_STARTUPINFO_PRESENT | ConPty.NativeMethods.CREATE_UNICODE_ENVIRONMENT;

                bool ok = ConPty.NativeMethods.CreateProcess(
                    null,
                    cmdBuf,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    false,
                    flags,
                    IntPtr.Zero,
                    cwd,
                    ref si,
                    out pi);

                if (!ok) return false;

                // Parent closes child-side pipe handles so EOF propagates when pseudo-console closes.
                SafeCloseHandle(ref hInRead);
                SafeCloseHandle(ref hOutWrite);

                ConPty.NativeMethods.DeleteProcThreadAttributeList(attrList);
                Marshal.FreeHGlobal(attrList);
                attrList = IntPtr.Zero;

                lock (_gate)
                {
                    _hPC = hPC;
                    _hPipeInWrite = hInWrite;
                    _hPipeOutRead = hOutRead;
                    _hProcess = pi.hProcess;
                    _hThread = pi.hThread;
                    ProcessId = pi.dwProcessId;
                }

                // Ownership transferred to fields.
                hPC = IntPtr.Zero;
                hInWrite = IntPtr.Zero;
                hOutRead = IntPtr.Zero;

                StartConPtyLoops();
                return true;
            }
            catch
            {
                return false;
            }
            finally
            {
                if (attrList != IntPtr.Zero)
                {
                    try { ConPty.NativeMethods.DeleteProcThreadAttributeList(attrList); } catch { }
                    Marshal.FreeHGlobal(attrList);
                }
                if (hPC != IntPtr.Zero) try { ConPty.NativeMethods.ClosePseudoConsole(hPC); } catch { }
                SafeCloseHandle(ref hInRead);
                SafeCloseHandle(ref hInWrite);
                SafeCloseHandle(ref hOutRead);
                SafeCloseHandle(ref hOutWrite);
            }
        }

        void StartConPtyLoops()
        {
            var reader = new Thread(ReadConPtyLoop);
            reader.IsBackground = true;
            reader.Name = "ConPtyReader";
            reader.Start();

            var waiter = new Thread(WaitConPtyLoop);
            waiter.IsBackground = true;
            waiter.Name = "ConPtyWaiter";
            waiter.Start();
        }

        void ReadConPtyLoop()
        {
            byte[] buf = new byte[4096];
            Decoder dec = Encoding.UTF8.GetDecoder();
            char[] chars = new char[4096];

            while (true)
            {
                IntPtr pipe;
                lock (_gate) { pipe = _hPipeOutRead; }
                if (pipe == IntPtr.Zero) break;

                int read = 0;
                bool ok = false;
                try { ok = ConPty.NativeMethods.ReadFile(pipe, buf, buf.Length, out read, IntPtr.Zero); }
                catch { ok = false; }

                if (!ok || read <= 0) break;
                int charCount = dec.GetChars(buf, 0, read, chars, 0);
                if (charCount > 0)
                {
                    EmitOutput(new string(chars, 0, charCount));
                }
            }
        }

        void WaitConPtyLoop()
        {
            IntPtr hProc;
            lock (_gate) { hProc = _hProcess; }
            if (hProc == IntPtr.Zero) return;

            try { ConPty.NativeMethods.WaitForSingleObject(hProc, ConPty.NativeMethods.INFINITE); } catch { }

            uint code = 0;
            try { ConPty.NativeMethods.GetExitCodeProcess(hProc, out code); } catch { }
            ExitCode = unchecked((int)code);
            _running = false;
            RaiseExited(ExitCode);
        }

        bool StartFallback(string commandLine, string cwd)
        {
            string exe;
            string args;
            SplitCommand(commandLine, out exe, out args);

            var psi = new ProcessStartInfo();
            psi.FileName = exe;
            psi.Arguments = args;
            psi.WorkingDirectory = cwd;
            psi.UseShellExecute = false;
            psi.RedirectStandardInput = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.CreateNoWindow = true;
            psi.StandardOutputEncoding = Encoding.UTF8;
            psi.StandardErrorEncoding = Encoding.UTF8;
            if (!ConPty.IsWindows)
            {
                psi.EnvironmentVariables["TERM"] = "xterm-256color";
            }

            var proc = new Process();
            proc.StartInfo = psi;
            proc.EnableRaisingEvents = true;
            proc.Exited += delegate
            {
                int code = 0;
                try { code = proc.ExitCode; } catch { }
                ExitCode = code;
                _running = false;
                RaiseExited(code);
            };

            if (!proc.Start()) return false;
            lock (_gate)
            {
                _fallbackProc = proc;
                ProcessId = proc.Id;
                _running = true;
            }

            StartStreamPump(proc.StandardOutput.BaseStream, "TerminalStdout");
            StartStreamPump(proc.StandardError.BaseStream, "TerminalStderr");
            return true;
        }

        void StartStreamPump(Stream stream, string threadName)
        {
            var t = new Thread(delegate()
            {
                byte[] buf = new byte[4096];
                Decoder dec = Encoding.UTF8.GetDecoder();
                char[] chars = new char[4096];
                try
                {
                    while (true)
                    {
                        int n = stream.Read(buf, 0, buf.Length);
                        if (n <= 0) break;
                        int c = dec.GetChars(buf, 0, n, chars, 0);
                        if (c > 0) EmitOutput(new string(chars, 0, c));
                    }
                }
                catch { }
            });
            t.IsBackground = true;
            t.Name = threadName;
            t.Start();
        }

        static void SplitCommand(string commandLine, out string exe, out string args)
        {
            string s = (commandLine ?? "").Trim();
            if (s.Length == 0) { exe = ConPty.IsWindows ? "cmd.exe" : "/bin/sh"; args = ""; return; }
            if (s[0] == '"')
            {
                int end = s.IndexOf('"', 1);
                if (end > 0)
                {
                    exe = s.Substring(1, end - 1);
                    args = s.Substring(end + 1).TrimStart();
                    return;
                }
            }
            int sp = s.IndexOf(' ');
            if (sp < 0) { exe = s; args = ""; return; }
            exe = s.Substring(0, sp);
            args = s.Substring(sp + 1).TrimStart();
        }

        public void WriteInput(string text)
        {
            if (string.IsNullOrEmpty(text) || !_running) return;
            byte[] bytes = Encoding.UTF8.GetBytes(text);
            lock (_writeGate)
            {
                if (UsingConPty)
                {
                    IntPtr pipe;
                    lock (_gate) { pipe = _hPipeInWrite; }
                    if (pipe == IntPtr.Zero) return;
                    int written;
                    ConPty.NativeMethods.WriteFile(pipe, bytes, bytes.Length, out written, IntPtr.Zero);
                }
                else
                {
                    Process p;
                    lock (_gate) { p = _fallbackProc; }
                    if (p == null) return;
                    try
                    {
                        Stream s = p.StandardInput.BaseStream;
                        s.Write(bytes, 0, bytes.Length);
                        s.Flush();
                    }
                    catch { }
                }
            }
        }

        public void Resize(int cols, int rows)
        {
            int c = cols > 0 ? cols : 1;
            int r = rows > 0 ? rows : 1;
            Cols = c;
            Rows = r;
            if (!UsingConPty) return;
            IntPtr hpc;
            lock (_gate) { hpc = _hPC; }
            if (hpc != IntPtr.Zero)
            {
                try { ConPty.NativeMethods.ResizePseudoConsole(hpc, new ConPty.NativeMethods.COORD((short)c, (short)r)); } catch { }
            }
        }

        public void Stop()
        {
            _running = false;
            IntPtr hpc, hIn, hOut, hProc, hThr;
            Process fp;
            lock (_gate)
            {
                hpc = _hPC; _hPC = IntPtr.Zero;
                hIn = _hPipeInWrite; _hPipeInWrite = IntPtr.Zero;
                hOut = _hPipeOutRead; _hPipeOutRead = IntPtr.Zero;
                hProc = _hProcess; _hProcess = IntPtr.Zero;
                hThr = _hThread; _hThread = IntPtr.Zero;
                fp = _fallbackProc; _fallbackProc = null;
            }

            if (hpc != IntPtr.Zero)
            {
                try { ConPty.NativeMethods.ClosePseudoConsole(hpc); } catch { }
            }
            SafeCloseHandle(ref hIn);
            SafeCloseHandle(ref hOut);
            if (hProc != IntPtr.Zero)
            {
                try
                {
                    uint code;
                    if (ConPty.NativeMethods.GetExitCodeProcess(hProc, out code) && code == 259) // STILL_ACTIVE
                    {
                        ConPty.NativeMethods.TerminateProcess(hProc, 1);
                    }
                }
                catch { }
                SafeCloseHandle(ref hProc);
            }
            SafeCloseHandle(ref hThr);

            if (fp != null)
            {
                try { if (!fp.HasExited) fp.Kill(); } catch { }
                try { fp.Dispose(); } catch { }
            }
        }

        public void Dispose()
        {
            Stop();
        }

        void EmitOutput(string chunk)
        {
            var ev = OutputReceived;
            if (ev != null)
            {
                try { ev(chunk); } catch { }
            }
        }

        void RaiseExited(int code)
        {
            if (Interlocked.Exchange(ref _exitedRaised, 1) != 0) return;
            var ev = Exited;
            if (ev != null)
            {
                try { ev(code); } catch { }
            }
        }

        static void SafeCloseHandle(ref IntPtr h)
        {
            if (h != IntPtr.Zero)
            {
                try { ConPty.NativeMethods.CloseHandle(h); } catch { }
                h = IntPtr.Zero;
            }
        }
    }
}
