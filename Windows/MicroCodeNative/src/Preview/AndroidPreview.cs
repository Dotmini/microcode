// EmbeddedAndroidDeviceView + AndroidStreamService (macOS) for Windows: the "Android Emu" tab of the Preview dock.
// Lists AVDs and USB/ADB devices, boots an AVD headless (-no-window), streams its screen with `adb exec-out screencap`
// into a phone frame, and turns clicks, drags, the wheel and the Back / Home / Recents / Text controls into
// `adb shell input` commands. Uses the Android SDK the user already has (ANDROID_HOME, Android Studio's default, or a
// folder picked once); nothing is downloaded.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public class AndroidDevice
    {
        public string Serial, State, Model;
        public bool IsEmulator { get { return Serial.StartsWith("emulator-"); } }
        public string Title { get { return (string.IsNullOrEmpty(Model) ? Serial : Model.Replace('_', ' ')) + (IsEmulator ? " (Emulator)" : " (USB)"); } }
    }

    public static class AndroidSdk
    {
        public static string Root, Adb, Emulator, AvdManager, AvdHome, JavaHome;

        static IEnumerable<string> Candidates()
        {
            yield return Defaults.Str("androidSdkPath", null);
            yield return Environment.GetEnvironmentVariable("ANDROID_HOME");
            yield return Environment.GetEnvironmentVariable("ANDROID_SDK_ROOT");
            yield return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Android", "Sdk");
            yield return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Android", "Sdk");
            yield return @"C:\Android\Sdk";
        }

        /// <summary>Finds an SDK with platform-tools\adb.exe, plus the AVD folder and a Java runtime for avdmanager.</summary>
        public static bool Resolve()
        {
            Root = null;
            foreach (var c in Candidates())
            {
                if (string.IsNullOrWhiteSpace(c)) continue;
                if (File.Exists(Path.Combine(c, "platform-tools", "adb.exe"))) { Root = c; break; }
            }
            if (Root == null) return false;
            Adb = Path.Combine(Root, "platform-tools", "adb.exe");
            Emulator = Path.Combine(Root, "emulator", "emulator.exe");
            if (!File.Exists(Emulator)) Emulator = null;
            AvdManager = Path.Combine(Root, "cmdline-tools", "latest", "bin", "avdmanager.bat");
            if (!File.Exists(AvdManager)) AvdManager = null;
            string parent = Path.GetDirectoryName(Root.TrimEnd('\\'));
            AvdHome = Environment.GetEnvironmentVariable("ANDROID_AVD_HOME");
            if (string.IsNullOrEmpty(AvdHome) && parent != null && Directory.Exists(Path.Combine(parent, "avd")) && Directory.GetFiles(Path.Combine(parent, "avd"), "*.ini").Length > 0) AvdHome = Path.Combine(parent, "avd");
            if (string.IsNullOrEmpty(AvdHome)) AvdHome = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".android", "avd");
            JavaHome = Environment.GetEnvironmentVariable("JAVA_HOME");
            if ((string.IsNullOrEmpty(JavaHome) || !File.Exists(Path.Combine(JavaHome, "bin", "java.exe"))) && parent != null && Directory.Exists(Path.Combine(parent, "jdk")))
                JavaHome = Directory.GetDirectories(Path.Combine(parent, "jdk")).FirstOrDefault(d => File.Exists(Path.Combine(d, "bin", "java.exe")));
            string studioJbr = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Android", "Android Studio", "jbr");
            if (string.IsNullOrEmpty(JavaHome) && File.Exists(Path.Combine(studioJbr, "bin", "java.exe"))) JavaHome = studioJbr;
            return true;
        }

        public static ProcessStartInfo Start(string exe, string args)
        {
            var psi = new ProcessStartInfo(exe, args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
            psi.EnvironmentVariables["ANDROID_HOME"] = Root;
            psi.EnvironmentVariables["ANDROID_SDK_ROOT"] = Root;
            if (AvdHome != null) psi.EnvironmentVariables["ANDROID_AVD_HOME"] = AvdHome;
            if (JavaHome != null) psi.EnvironmentVariables["JAVA_HOME"] = JavaHome;
            return psi;
        }

        /// <summary>Runs a tool to completion and returns its standard output (binary-safe), or null on failure/timeout.</summary>
        public static byte[] RunBytes(string exe, string args, int timeoutMs, string stdin)
        {
            try
            {
                var psi = Start(exe, args);
                psi.RedirectStandardInput = stdin != null;
                using (var p = Process.Start(psi))
                {
                    if (p == null) return null;
                    if (stdin != null) { p.StandardInput.Write(stdin); p.StandardInput.Close(); }
                    var err = p.StandardError.ReadToEndAsync();
                    var ms = new MemoryStream();
                    var copy = p.StandardOutput.BaseStream.CopyToAsync(ms);
                    if (!copy.Wait(timeoutMs)) { try { p.Kill(); } catch (InvalidOperationException) { } return null; }
                    p.WaitForExit(2000);
                    var bytes = ms.ToArray();
                    if (bytes.Length == 0 && err.Wait(500) && !string.IsNullOrEmpty(err.Result)) LastError = err.Result.Trim();
                    return bytes;
                }
            }
            catch (System.ComponentModel.Win32Exception ex) { LastError = ex.Message; return null; }
            catch (InvalidOperationException ex) { LastError = ex.Message; return null; }
            catch (AggregateException ex) { LastError = ex.GetBaseException().Message; return null; }
        }

        public static string LastError;

        public static string Run(string exe, string args, int timeoutMs) { var b = RunBytes(exe, args, timeoutMs, null); return b == null ? null : Encoding.UTF8.GetString(b); }

        public static List<AndroidDevice> Devices()
        {
            var list = new List<AndroidDevice>();
            string o = Run(Adb, "devices -l", 8000);
            if (o == null) return list;
            foreach (var line in o.Split('\n').Skip(1))
            {
                var parts = line.Trim().Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                if (parts.Length < 2) continue;
                var m = Regex.Match(line, @"model:(\S+)");
                list.Add(new AndroidDevice { Serial = parts[0], State = parts[1], Model = m.Success ? m.Groups[1].Value : null });
            }
            return list;
        }

        public static List<string> Avds()
        {
            if (Emulator == null) return new List<string>();
            string o = Run(Emulator, "-list-avds", 15000);
            return o == null ? new List<string>() : o.Split('\n').Select(s => s.Trim()).Where(s => s.Length > 0 && !s.StartsWith("INFO") && !s.Contains(" ")).ToList();
        }

        /// <summary>Installed system images as package ids ("system-images;android-34;google_apis;x86_64").</summary>
        public static List<string> SystemImages()
        {
            var list = new List<string>();
            string root = Path.Combine(Root ?? "", "system-images");
            if (!Directory.Exists(root)) return list;
            foreach (var api in Directory.GetDirectories(root))
                foreach (var tag in Directory.GetDirectories(api))
                    foreach (var abi in Directory.GetDirectories(tag))
                        if (File.Exists(Path.Combine(abi, "system.img")) || File.Exists(Path.Combine(abi, "source.properties")))
                            list.Add("system-images;" + Path.GetFileName(api) + ";" + Path.GetFileName(tag) + ";" + Path.GetFileName(abi));
            return list.OrderByDescending(s => s).ToList();
        }
    }

    public class AndroidPreview : Border
    {
        static AndroidPreview _shared;
        public static AndroidPreview Shared { get { if (_shared == null) _shared = new AndroidPreview(); return _shared; } }
        public static bool Created { get { return _shared != null; } }
        public static bool IsActive { get { return _shared != null && _shared._serial != null; } }

        readonly Border _bar = new Border(), _canvas = new Border();
        readonly Image _screen = new Image { Stretch = Stretch.Fill };
        DeviceFrameView _frame;
        List<AndroidDevice> _devices = new List<AndroidDevice>();
        List<string> _avds = new List<string>();
        string _serial, _bootingAvd, _status;
        bool _visible, _streaming, _scanning;
        Process _emulator;
        int _devW, _devH;
        DateTime _bootStarted;
        Point _down; DateTime _downAt; bool _pressed;
        readonly System.Windows.Threading.DispatcherTimer _clock;

        public AndroidPreview()
        {
            Background = Theme.Current.EditorBackground;
            var col = new DockPanel();
            DockPanel.SetDock(_bar, Dock.Top);
            col.Children.Add(_bar);
            col.Children.Add(_canvas);
            Child = col;
            RenderOptions.SetBitmapScalingMode(_screen, BitmapScalingMode.HighQuality);
            _screen.MouseLeftButtonDown += (s, e) => { _down = e.GetPosition(_screen); _downAt = DateTime.Now; _pressed = true; _screen.CaptureMouse(); e.Handled = true; };
            _screen.MouseLeftButtonUp += (s, e) => { if (!_pressed) return; _pressed = false; _screen.ReleaseMouseCapture(); Gesture(_down, e.GetPosition(_screen)); e.Handled = true; };
            _screen.MouseWheel += (s, e) =>
            {
                var p = e.GetPosition(_screen);
                double dy = Math.Sign(e.Delta) * _screen.ActualHeight * 0.25;
                Swipe(p, new Point(p.X, p.Y + dy), 180);
                e.Handled = true;
            };
            _screen.Cursor = Cursors.Hand;
            _clock = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            _clock.Tick += delegate { if (_bootingAvd != null) RenderCanvas(); else _clock.Stop(); };
            _frame = new DeviceFrameView(_screen);
            _frame.SizeChanged += delegate { ClipScreen(); };
            Render();
        }

        /// <summary>The dock shows/hides the tab: stream only while visible (screencap costs CPU on the device).</summary>
        public void SetVisible(bool visible)
        {
            _visible = visible;
            if (visible)
            {
                if (!_scanning && _devices.Count == 0 && _avds.Count == 0) Rescan();
                if (_serial != null) StartStream();
            }
        }

        void Rescan()
        {
            if (!AndroidSdk.Resolve()) { _status = null; Render(); return; }
            _scanning = true; Render();
            ThreadPool.QueueUserWorkItem(_ =>
            {
                var devs = AndroidSdk.Devices();
                var avds = AndroidSdk.Avds();
                Dispatcher.BeginInvoke(new Action(() =>
                {
                    _scanning = false; _devices = devs; _avds = avds;
                    if (_serial != null && !_devices.Any(d => d.Serial == _serial && d.State == "device")) _serial = null;
                    if (_serial == null && _bootingAvd == null)
                    {
                        var ready = _devices.FirstOrDefault(d => d.State == "device");
                        if (ready != null) Select(ready.Serial);
                    }
                    Render();
                }));
            });
        }

        void Select(string serial)
        {
            _serial = serial; _status = null; _devW = _devH = 0;
            Render();
            if (_visible) StartStream();
        }

        // ── emulator lifecycle ──

        void StartAvd(string avd)
        {
            if (AndroidSdk.Emulator == null) { _status = "The Android SDK has no emulator package installed."; Render(); return; }
            _bootingAvd = avd; _bootStarted = DateTime.Now; _status = null; _serial = null;
            var before = new HashSet<string>(_devices.Select(d => d.Serial));
            try
            {
                var psi = AndroidSdk.Start(AndroidSdk.Emulator, "-avd " + avd + " -no-window -no-audio -no-boot-anim -no-snapshot-save");
                _emulator = Process.Start(psi);
                var log = new StringBuilder();
                _emulator.OutputDataReceived += (s, e) => { if (e.Data != null) lock (log) log.AppendLine(e.Data); };
                _emulator.ErrorDataReceived += (s, e) => { if (e.Data != null) lock (log) log.AppendLine(e.Data); };
                _emulator.BeginOutputReadLine(); _emulator.BeginErrorReadLine();
                _clock.Start();
                var proc = _emulator;
                ThreadPool.QueueUserWorkItem(_ =>
                {
                    string serial = null;
                    for (int i = 0; i < 240 && serial == null; i++)
                    {
                        Thread.Sleep(1000);
                        if (proc.HasExited) break;
                        var devs = AndroidSdk.Devices();
                        var d = devs.FirstOrDefault(x => x.IsEmulator && !before.Contains(x.Serial) && x.State == "device") ?? devs.FirstOrDefault(x => x.IsEmulator && x.State == "device");
                        if (d == null) continue;
                        string booted = AndroidSdk.Run(AndroidSdk.Adb, "-s " + d.Serial + " shell getprop sys.boot_completed", 5000);
                        if (booted != null && booted.Trim() == "1") serial = d.Serial;
                    }
                    string tail; lock (log) tail = log.ToString();
                    string logPath = Path.Combine(Defaults.Dir, "emulator.log");
                    try { File.WriteAllText(logPath, "$ emulator " + psi.Arguments + "\n" + (proc.HasExited ? "[exited with code " + proc.ExitCode + "]\n" : "") + tail); }
                    catch (IOException ex) { Debug.WriteLine("emulator log: " + ex.Message); }
                    Dispatcher.BeginInvoke(new Action(() =>
                    {
                        _bootingAvd = null;
                        if (serial == null)
                        {
                            var lines = tail.Split('\n').Select(s => s.Trim()).Where(s => s.Length > 0).ToList();
                            var last = lines.LastOrDefault(s => s.Contains("ERROR") || s.Contains("FATAL") || s.Contains("PANIC")) ?? lines.LastOrDefault(s => !s.StartsWith("INFO"));
                            _status = "The emulator did not finish booting" + (proc.HasExited ? " (exit code " + proc.ExitCode + ")" : "") + (last != null ? ": " + last : ".") + "  Full log: " + logPath;
                            Render();
                            return;
                        }
                        Rescan();
                        Select(serial);
                    }));
                });
            }
            catch (System.ComponentModel.Win32Exception ex) { _bootingAvd = null; _status = "Could not start the emulator: " + ex.Message; }
            Render();
        }

        /// <summary>Boots an AVD by name (header menu, test hook).</summary>
        public void StartEmulator(string avd)
        {
            if (!AndroidSdk.Resolve()) { _status = "Android SDK not found."; Render(); return; }
            StartAvd(avd);
        }

        void StopEmulator()
        {
            string serial = _serial;
            _streaming = false; _serial = null; _screen.Source = null;
            var mine = _emulator;
            if (serial != null && serial.StartsWith("emulator-")) ThreadPool.QueueUserWorkItem(_ =>
            {
                // `adb emu kill` can hang on headless emulators: give it 10 s, then end the emulator this app started
                AndroidSdk.Run(AndroidSdk.Adb, "-s " + serial + " emu kill", 10000);
                try
                {
                    if (mine != null && !mine.WaitForExit(8000))
                        using (var k = Process.Start(new ProcessStartInfo("taskkill", "/PID " + mine.Id + " /T /F") { UseShellExecute = false, CreateNoWindow = true })) if (k != null) k.WaitForExit(8000);
                }
                catch (InvalidOperationException ex) { Debug.WriteLine("stop emulator: " + ex.Message); }
                catch (System.ComponentModel.Win32Exception ex) { Debug.WriteLine("stop emulator: " + ex.Message); }
            });
            Render();
        }

        void CreateAvd()
        {
            var image = AndroidSdk.SystemImages().FirstOrDefault(i => i.EndsWith(";x86_64") || i.EndsWith(";arm64-v8a"));
            if (AndroidSdk.AvdManager == null || image == null) { _status = "Install a system image and the command-line tools with the SDK Manager first."; Render(); return; }
            if (AndroidSdk.JavaHome == null) { _status = "avdmanager needs Java — set JAVA_HOME or install Android Studio."; Render(); return; }
            if (MessageBox.Show("Create an Android emulator \"MicroCode_Pixel\" from " + image + "?\n\nThe AVD is stored in " + AndroidSdk.AvdHome + ".", "MicroCode", MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
            _status = "Creating MicroCode_Pixel…"; Render();
            ThreadPool.QueueUserWorkItem(_ =>
            {
                var o = AndroidSdk.RunBytes("cmd.exe", "/d /c \"\"" + AndroidSdk.AvdManager + "\" create avd -n MicroCode_Pixel -k \"" + image + "\" -d pixel_7 --force\"", 120000, "no\n");
                Dispatcher.BeginInvoke(new Action(() => { _status = o == null ? "avdmanager failed: " + AndroidSdk.LastError : null; Rescan(); }));
            });
        }

        // ── screen streaming ──

        void StartStream()
        {
            if (_streaming || _serial == null) return;
            _streaming = true;
            string serial = _serial;
            var t = new Thread(() =>
            {
                int failures = 0;
                while (_streaming && _visible && _serial == serial)
                {
                    var started = DateTime.Now;
                    var frame = Capture(serial);
                    if (frame == null) { if (++failures > 5) { Dispatcher.BeginInvoke(new Action(() => { _status = "Lost the device screen: " + (AndroidSdk.LastError ?? "adb returned nothing"); _streaming = false; Rescan(); })); break; } Thread.Sleep(500); continue; }
                    failures = 0;
                    Dispatcher.BeginInvoke(new Action(() =>
                    {
                        bool sizeChanged = frame.PixelWidth != _devW || frame.PixelHeight != _devH;
                        _devW = frame.PixelWidth; _devH = frame.PixelHeight;
                        _screen.Source = frame;
                        if (sizeChanged) RenderCanvas();
                    }));
                    int spent = (int)(DateTime.Now - started).TotalMilliseconds;
                    if (spent < 120) Thread.Sleep(120 - spent);
                }
                _streaming = false;
            }) { IsBackground = true, Name = "android-screen" };
            t.Start();
        }

        /// <summary>One frame: raw RGBA from screencap (no PNG encoding on the device), halved and frozen for the UI.</summary>
        static BitmapSource Capture(string serial)
        {
            var raw = AndroidSdk.RunBytes(AndroidSdk.Adb, "-s " + serial + " exec-out screencap", 8000, null);
            if (raw == null || raw.Length < 16) return null;
            int w = BitConverter.ToInt32(raw, 0), h = BitConverter.ToInt32(raw, 4);
            if (w <= 0 || h <= 0 || w > 8000 || h > 8000) return null;
            int header = raw.Length - w * h * 4;
            if (header != 12 && header != 16) return null;
            int ow = w / 2, oh = h / 2;
            var px = new byte[ow * oh * 4];
            for (int y = 0; y < oh; y++)
            {
                int src = header + (y * 2) * w * 4, dst = y * ow * 4;
                for (int x = 0; x < ow; x++, src += 8, dst += 4)
                {
                    px[dst] = raw[src + 2]; px[dst + 1] = raw[src + 1]; px[dst + 2] = raw[src]; px[dst + 3] = 255;
                }
            }
            var bmp = BitmapSource.Create(ow, oh, 96, 96, PixelFormats.Bgra32, null, px, ow * 4);
            bmp.Freeze();
            return bmp;
        }

        // ── input ──

        Point ToDevice(Point p)
        {
            double sx = _devW * 2 / Math.Max(1, _screen.ActualWidth), sy = _devH * 2 / Math.Max(1, _screen.ActualHeight);
            return new Point(Math.Round(Math.Max(0, p.X * sx)), Math.Round(Math.Max(0, p.Y * sy)));
        }

        void Shell(string cmd)
        {
            string serial = _serial;
            if (serial == null) return;
            ThreadPool.QueueUserWorkItem(_ => AndroidSdk.Run(AndroidSdk.Adb, "-s " + serial + " shell " + cmd, 8000));
        }

        void Gesture(Point a, Point b)
        {
            double dist = (b - a).Length;
            int ms = (int)Math.Max(80, Math.Min(1500, (DateTime.Now - _downAt).TotalMilliseconds));
            if (dist < 8) { var d = ToDevice(b); Shell("input tap " + d.X + " " + d.Y); }
            else Swipe(a, b, ms);
        }

        void Swipe(Point a, Point b, int ms)
        {
            var d1 = ToDevice(a); var d2 = ToDevice(b);
            Shell("input swipe " + d1.X + " " + d1.Y + " " + d2.X + " " + d2.Y + " " + ms);
        }

        void Key(int code) { Shell("input keyevent " + code); }

        void SendText(string text)
        {
            if (string.IsNullOrEmpty(text)) return;
            var sb = new StringBuilder();
            foreach (char c in text)
            {
                if (c == ' ') sb.Append("%s");
                else if ("\\'\"`$&|;<>()[]{}*?!#~".IndexOf(c) >= 0) sb.Append('\\').Append(c);
                else if (c >= 32 && c < 127) sb.Append(c);
            }
            Shell("input text " + sb);
        }

        void ClipScreen()
        {
            double r = (_frame.Viewport.ScreenRadius) * _frame.Scale;
            if (_screen.ActualWidth > 0) _screen.Clip = new RectangleGeometry(new Rect(0, 0, _screen.ActualWidth, _screen.ActualHeight), r, r);
        }

        // ── UI ──

        void Render() { RenderBar(); RenderCanvas(); }

        Btn Tool(string icon, string tip, Action a)
        {
            var t = Theme.Current;
            var b = V.Button(V.Size(V.Box(Sym.Icon(icon, 10.5, a != null ? t.P(0.85) : t.S(0.45)), V.P(0), Brushes.Transparent, 4), 22, 22), a);
            b.ToolTip = tip;
            if (a != null) b.OnState = x => ((Border)((FrameworkElement)x.Child)).Background = x.IsHover ? t.P(0.09) : Brushes.Transparent;
            return b;
        }

        void RenderBar()
        {
            var t = Theme.Current;
            var row = V.H(4);
            var cur = _devices.FirstOrDefault(d => d.Serial == _serial);
            string title = cur != null ? cur.Title : _bootingAvd != null ? _bootingAvd.Replace('_', ' ') + " (booting)" : (_devices.Count + _avds.Count > 0 ? "Choose device" : "No devices");
            var picker = V.Button(V.Size(V.Box(V.H(3, Sym.Icon("candybarphone", 10, t.Primary), V.T(title, 10, FontWeights.Medium, t.Primary), Sym.Icon("chevron.down", 7, t.Secondary, FontWeights.Bold)), V.P(6, 0), t.P(0.08), 5), double.NaN, 22), null);
            picker.ToolTip = "เลือกรุ่น Android Emulator / อุปกรณ์ Android ที่ตรวจพบในเครื่อง";
            picker.MenuItems = DeviceMenu;
            row.Children.Add(picker);
            bool live = _serial != null;
            row.Children.Add(Tool("chevron.left", "Android Back", live ? (Action)(() => Key(4)) : null));
            row.Children.Add(Tool("circle", "Android Home", live ? (Action)(() => Key(3)) : null));
            row.Children.Add(Tool("square.on.square", "Recent apps", live ? (Action)(() => Key(187)) : null));
            row.Children.Add(Tool("keyboard", "Send text to Android", live ? (Action)(() => SendText(Microsoft.VisualBasic.Interaction.InputBox("Text to type on the device:", "Send text to Android", ""))) : null));
            row.Children.Add(V.Sp());
            if (live && cur != null && cur.IsEmulator)
            {
                var stop = V.Button(V.Size(V.Box(Sym.Icon("stop.circle.fill", 12, t.SysRed), V.P(0), Brushes.Transparent, 4), 22, 22), StopEmulator);
                stop.ToolTip = "Stop Android Emulator & free CPU";
                row.Children.Add(stop);
            }
            row.Children.Add(Tool("arrow.clockwise", "Rescan for emulators and USB devices", Rescan));
            _bar.Child = V.Box(row, V.P(8, 4), t.PanelBackground, 0);
            _bar.BorderBrush = t.Separator; _bar.BorderThickness = new Thickness(0, 0, 0, 1);
        }

        List<MenuItemSpec> DeviceMenu()
        {
            var items = new List<MenuItemSpec>();
            if (AndroidSdk.Root == null)
            {
                items.Add(MenuItemSpec.Item("Locate Android SDK (adb.exe)…", "folder", LocateSdk));
                return items;
            }
            var ready = _devices.Where(d => d.State == "device").ToList();
            if (ready.Count > 0)
            {
                items.Add(MenuItemSpec.Header("Running & USB Devices"));
                foreach (var d in ready) { var dd = d; items.Add(new MenuItemSpec { Title = d.Title, Icon = d.IsEmulator ? "candybarphone" : "cable.connector", Checked = d.Serial == _serial, Action = () => Select(dd.Serial) }); }
            }
            foreach (var d in _devices.Where(x => x.State != "device"))
                items.Add(new MenuItemSpec { Title = d.Serial + " — " + d.State + (d.State == "unauthorized" ? " (allow USB debugging on the phone)" : ""), Disabled = true });
            if (_avds.Count > 0)
            {
                items.Add(MenuItemSpec.Header("Emulators (AVD)"));
                foreach (var a in _avds) { var aa = a; items.Add(MenuItemSpec.Item(a.Replace('_', ' '), "play.fill", () => StartAvd(aa))); }
            }
            items.Add(MenuItemSpec.Sep());
            items.Add(MenuItemSpec.Item("Create Emulator (Pixel)…", "plus", CreateAvd));
            items.Add(MenuItemSpec.Item("Refresh Devices", "arrow.clockwise", Rescan));
            items.Add(MenuItemSpec.Item("Locate Android SDK (adb.exe)…", "folder", LocateSdk));
            return items;
        }

        void LocateSdk()
        {
            var dlg = new Microsoft.Win32.OpenFileDialog { Title = "Locate adb.exe in your Android SDK (platform-tools)", Filter = "adb.exe|adb.exe", CheckFileExists = true };
            if (dlg.ShowDialog() != true) return;
            string platformTools = Path.GetDirectoryName(dlg.FileName);
            string root = Path.GetDirectoryName(platformTools);
            if (!string.Equals(Path.GetFileName(platformTools), "platform-tools", StringComparison.OrdinalIgnoreCase) || root == null) { MessageBox.Show("Pick the adb.exe inside the SDK's platform-tools folder.", "MicroCode"); return; }
            Defaults.Set("androidSdkPath", root);
            Rescan();
        }

        void RenderCanvas()
        {
            var t = Theme.Current;
            if (AndroidSdk.Root == null && !AndroidSdk.Resolve())
            {
                var col = V.Vs(10, Sym.Icon("candybarphone", 26, t.S(0.5)), V.T("Android SDK not found", 13, FontWeights.SemiBold, t.Primary),
                    MaxW(V.Wrap(V.T("Install Android Studio, or point MicroCode at an existing SDK. Emulators and USB devices then appear here.", 11, FontWeights.Normal, t.Secondary), TextAlignment.Center)),
                    PanelUI.Small("folder", "Locate Android SDK (adb.exe)…", LocateSdk));
                col.Margin = new Thickness(16, 50, 16, 20);
                _canvas.Child = col;
                return;
            }
            if (_bootingAvd != null)
            {
                int secs = (int)(DateTime.Now - _bootStarted).TotalSeconds;
                var col = V.Vs(10, Sym.Icon("candybarphone", 26, t.S(0.5)), V.T("Booting " + _bootingAvd.Replace('_', ' ') + "…", 13, FontWeights.SemiBold, t.Primary),
                    V.T(secs + " s · headless emulator (WHPX)", 11, FontWeights.Normal, t.Secondary));
                col.Margin = new Thickness(16, 50, 16, 20);
                _canvas.Child = col;
                return;
            }
            if (_serial == null)
            {
                var col = V.Vs(10, Sym.Icon("candybarphone", 26, t.S(0.5)), V.T(_scanning ? "Looking for Android devices…" : "Android Emulator", 13, FontWeights.SemiBold, t.Primary));
                if (_status != null) col.Children.Add(MaxW(V.Wrap(V.T(_status, 11, FontWeights.Normal, t.SysOrange), TextAlignment.Center)));
                if (!_scanning)
                {
                    if (_avds.Count == 0 && _devices.Count == 0)
                        col.Children.Add(MaxW(V.Wrap(V.T("No emulators or USB devices. Connect a phone with USB debugging on, or create an emulator.", 11, FontWeights.Normal, t.Secondary), TextAlignment.Center)));
                    var actions = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Center, MaxWidth = 340 };
                    foreach (var a in _avds)
                    {
                        var aa = a;
                        var b = V.Button(V.Box(V.H(4, Sym.Icon("play.fill", 9, Brushes.White), V.T("Start " + a.Replace('_', ' '), 11, FontWeights.SemiBold, Brushes.White)), V.P(10, 6), t.Accent, 6), () => StartAvd(aa));
                        b.Margin = new Thickness(3); actions.Children.Add(b);
                    }
                    foreach (var d in _devices.Where(x => x.State == "device"))
                    {
                        var dd = d;
                        var b = PanelUI.Small("cable.connector", d.Title, () => Select(dd.Serial)); b.Margin = new Thickness(3); actions.Children.Add(b);
                    }
                    if (_avds.Count == 0) { var c = PanelUI.Small("plus", "Create Emulator (Pixel)…", CreateAvd); c.Margin = new Thickness(3); actions.Children.Add(c); }
                    col.Children.Add(actions);
                }
                col.Margin = new Thickness(16, 50, 16, 20);
                _canvas.Child = col;
                return;
            }
            // live device in a phone frame sized to the device's aspect ratio
            double aspect = _devW > 0 ? (double)_devH / _devW : 2.2;
            _frame.Viewport = new WebViewport { Id = "android", Name = "Android", ScreenW = 412, ScreenH = Math.Round(412 * aspect), Bezel = 11, ScreenRadius = 34 };
            _frame.ShowBezel = true;
            _frame.InvalidateArrange(); _frame.InvalidateVisual();
            if (_canvas.Child != _frame) _canvas.Child = _frame;
            _canvas.Background = t.P(0.03);
            Dispatcher.BeginInvoke(new Action(ClipScreen), System.Windows.Threading.DispatcherPriority.Loaded);
        }

        static FrameworkElement MaxW(FrameworkElement e) { e.MaxWidth = 320; return e; }
    }
}
