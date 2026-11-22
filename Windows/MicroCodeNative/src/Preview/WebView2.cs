// Edge WebView2 hosted natively, without the WebView2 SDK or NuGet: the loader step (find the Evergreen runtime that
// ships with Windows 11, load its EmbeddedBrowserWebView.dll, call CreateWebViewEnvironmentWithOptionsInternal) plus the
// COM interfaces this app uses, declared from the WebView2 ABI (WebView2.h, slot order verified against
// Microsoft.Web.WebView2.Core 1.0.2365). The macOS app renders previews with WKWebView; this is the Windows equivalent.
// Only page content runs in the browser engine — the IDE itself stays native WPF.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Microsoft.Win32;
using MicroCode.Core;

namespace MicroCode.Views
{
    [StructLayout(LayoutKind.Sequential)] public struct WvRect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct WvToken { public long Value; }
    [StructLayout(LayoutKind.Sequential)] public struct WvColor { public byte A, R, G, B; }

    [ComImport, Guid("4E8A3389-C9D8-4BD2-B6B5-124FEE6CC14D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvEnvironmentCompleted { void Invoke(int errorCode, IWvEnvironment environment); }

    [ComImport, Guid("6C4819F3-C9B7-4260-8127-C9F5BDE7F68C"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvControllerCompleted { void Invoke(int errorCode, IWvController controller); }

    [ComImport, Guid("B96D755E-0319-4E92-A296-23436F46A1FC"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvEnvironment
    {
        void CreateCoreWebView2Controller(IntPtr parentWindow, IWvControllerCompleted handler);
        IntPtr CreateWebResourceResponse(IntPtr content, int statusCode, [MarshalAs(UnmanagedType.LPWStr)] string reason, [MarshalAs(UnmanagedType.LPWStr)] string headers);
        [return: MarshalAs(UnmanagedType.LPWStr)] string get_BrowserVersionString();
    }

    [ComImport, Guid("4D00C0D1-9434-4EB6-8078-8697A560334F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvController
    {
        int get_IsVisible();
        void set_IsVisible(int visible);
        WvRect get_Bounds();
        void set_Bounds(WvRect bounds);
        double get_ZoomFactor();
        void set_ZoomFactor(double zoom);
        void add_ZoomFactorChanged(IntPtr handler, out WvToken token);
        void remove_ZoomFactorChanged(WvToken token);
        void SetBoundsAndZoomFactor(WvRect bounds, double zoom);
        void MoveFocus(int reason);
        void add_MoveFocusRequested(IntPtr handler, out WvToken token);
        void remove_MoveFocusRequested(WvToken token);
        void add_GotFocus(IntPtr handler, out WvToken token);
        void remove_GotFocus(WvToken token);
        void add_LostFocus(IntPtr handler, out WvToken token);
        void remove_LostFocus(WvToken token);
        void add_AcceleratorKeyPressed(IntPtr handler, out WvToken token);
        void remove_AcceleratorKeyPressed(WvToken token);
        IntPtr get_ParentWindow();
        void set_ParentWindow(IntPtr parent);
        void NotifyParentWindowPositionChanged();
        void Close();
        IWvWebView get_CoreWebView2();
    }

    /// <summary>ICoreWebView2Controller2 (base slots repeated, then the background colour).</summary>
    [ComImport, Guid("C979903E-D4CA-4228-92EB-47EE3FA96EAB"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvController2
    {
        int get_IsVisible(); void set_IsVisible(int visible); WvRect get_Bounds(); void set_Bounds(WvRect bounds);
        double get_ZoomFactor(); void set_ZoomFactor(double zoom); void add_ZoomFactorChanged(IntPtr handler, out WvToken token); void remove_ZoomFactorChanged(WvToken token);
        void SetBoundsAndZoomFactor(WvRect bounds, double zoom); void MoveFocus(int reason); void add_MoveFocusRequested(IntPtr handler, out WvToken token); void remove_MoveFocusRequested(WvToken token);
        void add_GotFocus(IntPtr handler, out WvToken token); void remove_GotFocus(WvToken token); void add_LostFocus(IntPtr handler, out WvToken token); void remove_LostFocus(WvToken token);
        void add_AcceleratorKeyPressed(IntPtr handler, out WvToken token); void remove_AcceleratorKeyPressed(WvToken token); IntPtr get_ParentWindow(); void set_ParentWindow(IntPtr parent);
        void NotifyParentWindowPositionChanged(); void Close(); IWvWebView get_CoreWebView2();
        WvColor get_DefaultBackgroundColor();
        void set_DefaultBackgroundColor(WvColor color);
    }

    [ComImport, Guid("E562E4F0-D7FA-43AC-8D71-C05150499F00"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvSettings
    {
        int get_IsScriptEnabled(); void set_IsScriptEnabled(int v);
        int get_IsWebMessageEnabled(); void set_IsWebMessageEnabled(int v);
        int get_AreDefaultScriptDialogsEnabled(); void set_AreDefaultScriptDialogsEnabled(int v);
        int get_IsStatusBarEnabled(); void set_IsStatusBarEnabled(int v);
        int get_AreDevToolsEnabled(); void set_AreDevToolsEnabled(int v);
        int get_AreDefaultContextMenusEnabled(); void set_AreDefaultContextMenusEnabled(int v);
        int get_AreHostObjectsAllowed(); void set_AreHostObjectsAllowed(int v);
        int get_IsZoomControlEnabled(); void set_IsZoomControlEnabled(int v);
        int get_IsBuiltInErrorPageEnabled(); void set_IsBuiltInErrorPageEnabled(int v);
    }

    /// <summary>ICoreWebView2Settings2: base slots, then UserAgent.</summary>
    [ComImport, Guid("EE9A0F68-F46C-4E32-AC23-EF8CAC224D2A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvSettings2
    {
        int get_IsScriptEnabled(); void set_IsScriptEnabled(int v); int get_IsWebMessageEnabled(); void set_IsWebMessageEnabled(int v);
        int get_AreDefaultScriptDialogsEnabled(); void set_AreDefaultScriptDialogsEnabled(int v); int get_IsStatusBarEnabled(); void set_IsStatusBarEnabled(int v);
        int get_AreDevToolsEnabled(); void set_AreDevToolsEnabled(int v); int get_AreDefaultContextMenusEnabled(); void set_AreDefaultContextMenusEnabled(int v);
        int get_AreHostObjectsAllowed(); void set_AreHostObjectsAllowed(int v); int get_IsZoomControlEnabled(); void set_IsZoomControlEnabled(int v);
        int get_IsBuiltInErrorPageEnabled(); void set_IsBuiltInErrorPageEnabled(int v);
        [return: MarshalAs(UnmanagedType.LPWStr)] string get_UserAgent();
        void set_UserAgent([MarshalAs(UnmanagedType.LPWStr)] string userAgent);
    }

    [ComImport, Guid("76ECEACB-0462-4D94-AC83-423A6793775E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvWebView
    {
        IWvSettings get_Settings();
        [return: MarshalAs(UnmanagedType.LPWStr)] string get_Source();
        void Navigate([MarshalAs(UnmanagedType.LPWStr)] string uri);
        void NavigateToString([MarshalAs(UnmanagedType.LPWStr)] string html);
        void add_NavigationStarting(IWvNavigationStarting handler, out WvToken token);
        void remove_NavigationStarting(WvToken token);
        void add_ContentLoading(IntPtr handler, out WvToken token);
        void remove_ContentLoading(WvToken token);
        void add_SourceChanged(IWvSourceChanged handler, out WvToken token);
        void remove_SourceChanged(WvToken token);
        void add_HistoryChanged(IWvHistoryChanged handler, out WvToken token);
        void remove_HistoryChanged(WvToken token);
        void add_NavigationCompleted(IWvNavigationCompleted handler, out WvToken token);
        void remove_NavigationCompleted(WvToken token);
        void add_FrameNavigationStarting(IntPtr handler, out WvToken token);
        void remove_FrameNavigationStarting(WvToken token);
        void add_FrameNavigationCompleted(IntPtr handler, out WvToken token);
        void remove_FrameNavigationCompleted(WvToken token);
        void add_ScriptDialogOpening(IntPtr handler, out WvToken token);
        void remove_ScriptDialogOpening(WvToken token);
        void add_PermissionRequested(IntPtr handler, out WvToken token);
        void remove_PermissionRequested(WvToken token);
        void add_ProcessFailed(IWvProcessFailed handler, out WvToken token);
        void remove_ProcessFailed(WvToken token);
        void AddScriptToExecuteOnDocumentCreated([MarshalAs(UnmanagedType.LPWStr)] string javaScript, IWvAddScriptCompleted handler);
        void RemoveScriptToExecuteOnDocumentCreated([MarshalAs(UnmanagedType.LPWStr)] string id);
        void ExecuteScript([MarshalAs(UnmanagedType.LPWStr)] string javaScript, IWvExecuteScriptCompleted handler);
        void CapturePreview(int imageFormat, System.Runtime.InteropServices.ComTypes.IStream imageStream, IWvCapturePreviewCompleted handler);
        void Reload();
        void PostWebMessageAsJson([MarshalAs(UnmanagedType.LPWStr)] string json);
        void PostWebMessageAsString([MarshalAs(UnmanagedType.LPWStr)] string message);
        void add_WebMessageReceived(IWvWebMessageReceived handler, out WvToken token);
        void remove_WebMessageReceived(WvToken token);
        void CallDevToolsProtocolMethod([MarshalAs(UnmanagedType.LPWStr)] string method, [MarshalAs(UnmanagedType.LPWStr)] string parametersAsJson, IWvDevToolsCompleted handler);
        uint get_BrowserProcessId();
        int get_CanGoBack();
        int get_CanGoForward();
        void GoBack();
        void GoForward();
        IntPtr GetDevToolsProtocolEventReceiver([MarshalAs(UnmanagedType.LPWStr)] string eventName);
        void Stop();
        void add_NewWindowRequested(IWvNewWindowRequested handler, out WvToken token);
        void remove_NewWindowRequested(WvToken token);
        void add_DocumentTitleChanged(IWvDocumentTitleChanged handler, out WvToken token);
        void remove_DocumentTitleChanged(WvToken token);
        [return: MarshalAs(UnmanagedType.LPWStr)] string get_DocumentTitle();
        void AddHostObjectToScript([MarshalAs(UnmanagedType.LPWStr)] string name, IntPtr obj);
        void RemoveHostObjectFromScript([MarshalAs(UnmanagedType.LPWStr)] string name);
        void OpenDevToolsWindow();
    }

    [ComImport, Guid("9ADBE429-F36D-432B-9DDC-F8881FBD76E3"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvNavigationStarting { void Invoke(IntPtr sender, IntPtr args); }
    [ComImport, Guid("3C067F9F-5388-4772-8B48-79F7EF1AB37C"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvSourceChanged { void Invoke(IntPtr sender, IntPtr args); }
    [ComImport, Guid("C79A420C-EFD9-4058-9295-3E8B4BCAB645"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvHistoryChanged { void Invoke(IntPtr sender, IntPtr args); }
    [ComImport, Guid("F5F2B923-953E-4042-9F95-F3A118E1AFD4"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvDocumentTitleChanged { void Invoke(IntPtr sender, IntPtr args); }
    [ComImport, Guid("79E0AEA4-990B-42D9-AA1D-0FCC2E5BC7F1"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvProcessFailed { void Invoke(IntPtr sender, IntPtr args); }

    [ComImport, Guid("D33A35BF-1C49-4F98-93AB-006E0533FE1C"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvNavigationCompleted { void Invoke(IntPtr sender, IWvNavigationCompletedArgs args); }
    [ComImport, Guid("30D68B7D-20D9-4752-A9CA-EC8448FBB5C1"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvNavigationCompletedArgs { int get_IsSuccess(); int get_WebErrorStatus(); ulong get_NavigationId(); }

    [ComImport, Guid("D4C185FE-C81C-4989-97AF-2D3FA7AB5651"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvNewWindowRequested { void Invoke(IntPtr sender, IWvNewWindowRequestedArgs args); }
    [ComImport, Guid("34ACB11C-FC37-4418-9132-F9C21D1EAFB9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvNewWindowRequestedArgs
    {
        [return: MarshalAs(UnmanagedType.LPWStr)] string get_uri();
        void set_NewWindow(IntPtr newWindow);
        IntPtr get_NewWindow();
        void set_Handled(int handled);
    }

    [ComImport, Guid("57213F19-00E6-49FA-8E07-898EA01ECBD2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvWebMessageReceived { void Invoke(IntPtr sender, IWvWebMessageArgs args); }
    [ComImport, Guid("0F99A40C-E962-4207-9E92-E3D542EFF849"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvWebMessageArgs
    {
        [return: MarshalAs(UnmanagedType.LPWStr)] string get_Source();
        [return: MarshalAs(UnmanagedType.LPWStr)] string get_webMessageAsJson();
        [return: MarshalAs(UnmanagedType.LPWStr)] string TryGetWebMessageAsString();
    }

    [ComImport, Guid("B99369F3-9B11-47B5-BC6F-8E7895FCEA17"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvAddScriptCompleted { void Invoke(int errorCode, [MarshalAs(UnmanagedType.LPWStr)] string id); }
    [ComImport, Guid("49511172-CC67-4BCA-9923-137112F4C4CC"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvExecuteScriptCompleted { void Invoke(int errorCode, [MarshalAs(UnmanagedType.LPWStr)] string resultAsJson); }
    [ComImport, Guid("5C4889F0-5EF6-4C5A-952C-D8F1B92D0574"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvDevToolsCompleted { void Invoke(int errorCode, [MarshalAs(UnmanagedType.LPWStr)] string resultAsJson); }
    [ComImport, Guid("697E05E9-3D8F-45FA-96F4-8FFE1EDEDAF5"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWvCapturePreviewCompleted { void Invoke(int errorCode); }

    // ── handler objects (COM-callable wrappers around delegates) ──
    [ComVisible(true)] public sealed class WvEnvironmentCompleted : IWvEnvironmentCompleted { readonly Action<int, IWvEnvironment> _a; public WvEnvironmentCompleted(Action<int, IWvEnvironment> a) { _a = a; } public void Invoke(int hr, IWvEnvironment env) { _a(hr, env); } }
    [ComVisible(true)] public sealed class WvControllerCompleted : IWvControllerCompleted { readonly Action<int, IWvController> _a; public WvControllerCompleted(Action<int, IWvController> a) { _a = a; } public void Invoke(int hr, IWvController c) { _a(hr, c); } }
    [ComVisible(true)] public sealed class WvSimpleHandler : IWvNavigationStarting, IWvSourceChanged, IWvHistoryChanged, IWvDocumentTitleChanged, IWvProcessFailed
    {
        readonly Action _a;
        public WvSimpleHandler(Action a) { _a = a; }
        void IWvNavigationStarting.Invoke(IntPtr s, IntPtr e) { _a(); }
        void IWvSourceChanged.Invoke(IntPtr s, IntPtr e) { _a(); }
        void IWvHistoryChanged.Invoke(IntPtr s, IntPtr e) { _a(); }
        void IWvDocumentTitleChanged.Invoke(IntPtr s, IntPtr e) { _a(); }
        void IWvProcessFailed.Invoke(IntPtr s, IntPtr e) { _a(); }
    }
    [ComVisible(true)] public sealed class WvNavigationCompleted : IWvNavigationCompleted { readonly Action<bool, int> _a; public WvNavigationCompleted(Action<bool, int> a) { _a = a; } public void Invoke(IntPtr s, IWvNavigationCompletedArgs e) { _a(e.get_IsSuccess() != 0, e.get_WebErrorStatus()); } }
    [ComVisible(true)] public sealed class WvNewWindowRequested : IWvNewWindowRequested { readonly Action<string> _a; public WvNewWindowRequested(Action<string> a) { _a = a; } public void Invoke(IntPtr s, IWvNewWindowRequestedArgs e) { string uri = e.get_uri(); e.set_Handled(1); _a(uri); } }
    [ComVisible(true)] public sealed class WvWebMessageReceived : IWvWebMessageReceived { readonly Action<string> _a; public WvWebMessageReceived(Action<string> a) { _a = a; } public void Invoke(IntPtr s, IWvWebMessageArgs e) { _a(e.get_webMessageAsJson()); } }
    [ComVisible(true)] public sealed class WvScriptCompleted : IWvExecuteScriptCompleted, IWvDevToolsCompleted
    {
        readonly Action<int, string> _a;
        public WvScriptCompleted(Action<int, string> a) { _a = a; }
        void IWvExecuteScriptCompleted.Invoke(int hr, string json) { _a(hr, json); }
        void IWvDevToolsCompleted.Invoke(int hr, string json) { _a(hr, json); }
    }
    [ComVisible(true)] public sealed class WvAddScriptCompleted : IWvAddScriptCompleted { readonly Action<int, string> _a; public WvAddScriptCompleted(Action<int, string> a) { _a = a; } public void Invoke(int hr, string id) { _a(hr, id); } }
    [ComVisible(true)] public sealed class WvCaptureCompleted : IWvCapturePreviewCompleted { readonly Action<int> _a; public WvCaptureCompleted(Action<int> a) { _a = a; } public void Invoke(int hr) { _a(hr); } }

    /// <summary>Finds the Evergreen WebView2 Runtime and creates one shared environment (one browser process per user data folder).</summary>
    public static class WebView2Runtime
    {
        const string ClientKey = @"SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}";
        const int RuntimeInstalled = 0;

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int CreateEnvironmentInternal([MarshalAs(UnmanagedType.U1)] bool checkRunningInstance, int runtimeType,
            [MarshalAs(UnmanagedType.LPWStr)] string userDataFolder, IntPtr environmentOptions, IWvEnvironmentCompleted handler);

        [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr LoadLibraryW(string path);
        [DllImport("kernel32", CharSet = CharSet.Ansi, SetLastError = true)] static extern IntPtr GetProcAddress(IntPtr module, string name);

        static IWvEnvironment _env;
        static bool _creating;
        static object _keepHandler;
        static readonly List<Action<IWvEnvironment>> Waiting = new List<Action<IWvEnvironment>>();
        static readonly List<Action<string>> Failing = new List<Action<string>>();
        public static string Version, LastError;

        static string Arch()
        {
            string a = (System.Environment.GetEnvironmentVariable("PROCESSOR_ARCHITECTURE") ?? "").ToUpperInvariant();
            if (a == "ARM64") return "arm64";
            return System.Environment.Is64BitProcess ? "x64" : "x86";
        }

        /// <summary>EmbeddedBrowserWebView.dll of the newest installed runtime (machine-wide, then per-user).</summary>
        public static string FindClientDll()
        {
            var roots = new List<KeyValuePair<string, string>>();
            foreach (var hive in new[] { RegistryHive.LocalMachine, RegistryHive.CurrentUser })
                foreach (var view in new[] { RegistryView.Registry32, RegistryView.Registry64 })
                {
                    try
                    {
                        using (var b = RegistryKey.OpenBaseKey(hive, view))
                        using (var k = b.OpenSubKey(ClientKey))
                        {
                            if (k == null) continue;
                            string pv = k.GetValue("pv") as string;
                            if (string.IsNullOrEmpty(pv) || pv == "0.0.0.0") continue;
                            string baseDir = hive == RegistryHive.LocalMachine
                                ? Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.ProgramFilesX86), @"Microsoft\EdgeWebView\Application")
                                : Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.LocalApplicationData), @"Microsoft\EdgeWebView\Application");
                            roots.Add(new KeyValuePair<string, string>(pv, Path.Combine(baseDir, pv)));
                        }
                    }
                    catch (System.Security.SecurityException ex) { System.Diagnostics.Debug.WriteLine("webview2 registry: " + ex.Message); }
                    catch (UnauthorizedAccessException ex) { System.Diagnostics.Debug.WriteLine("webview2 registry: " + ex.Message); }
                }
            foreach (var r in roots)
            {
                string dll = Path.Combine(r.Value, "EBWebView", Arch(), "EmbeddedBrowserWebView.dll");
                if (File.Exists(dll)) { Version = r.Key; return dll; }
            }
            return null;
        }

        /// <summary>Per-user browser data: kept next to the settings when the app runs on an isolated data folder.</summary>
        static string UserDataFolder()
        {
            string roaming = Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.ApplicationData), "MicroCode");
            bool isolated = !string.Equals(Path.GetFullPath(Defaults.Dir).TrimEnd('\\'), roaming.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
            return isolated ? Path.Combine(Defaults.Dir, "WebView2")
                : Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.LocalApplicationData), "MicroCode", "WebView2");
        }

        public static bool Available { get { return FindClientDll() != null; } }

        /// <summary>Calls back on the UI thread with the shared environment, or with an error message.</summary>
        public static void GetEnvironment(Action<IWvEnvironment> ok, Action<string> fail)
        {
            if (_env != null) { ok(_env); return; }
            Waiting.Add(ok); Failing.Add(fail);
            if (_creating) return;
            _creating = true;
            try
            {
                string dll = FindClientDll();
                if (dll == null) throw new InvalidOperationException("Microsoft Edge WebView2 Runtime is not installed on this PC.");
                IntPtr module = LoadLibraryW(dll);
                if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not load " + dll);
                IntPtr proc = GetProcAddress(module, "CreateWebViewEnvironmentWithOptionsInternal");
                if (proc == IntPtr.Zero) throw new InvalidOperationException("This WebView2 Runtime has no CreateWebViewEnvironmentWithOptionsInternal export.");
                var create = (CreateEnvironmentInternal)Marshal.GetDelegateForFunctionPointer(proc, typeof(CreateEnvironmentInternal));
                string udf = UserDataFolder();
                Directory.CreateDirectory(udf);
                var handler = new WvEnvironmentCompleted((hr, env) =>
                {
                    _creating = false;
                    if (hr < 0 || env == null) { Finish(null, "WebView2 environment failed (0x" + hr.ToString("X8") + ")"); return; }
                    _env = env;
                    Finish(env, null);
                });
                _keepHandler = handler;
                int hr0 = create(true, RuntimeInstalled, udf, IntPtr.Zero, handler);
                if (hr0 < 0) throw Marshal.GetExceptionForHR(hr0);
            }
            catch (Exception ex)
            {
                _creating = false;
                Finish(null, ex.Message);
            }
        }

        static void Finish(IWvEnvironment env, string error)
        {
            LastError = error;
            var ok = Waiting.ToArray(); var bad = Failing.ToArray();
            Waiting.Clear(); Failing.Clear();
            if (env != null) foreach (var a in ok) a(env);
            else foreach (var a in bad) a(error);
        }
    }

    /// <summary>
    /// A WebView2 browser hosted as a child HWND (like Microsoft's own WPF control): navigation, history, title, zoom,
    /// script, DevTools protocol, page capture and web messages. The page keeps running while the control is hidden.
    /// </summary>
    public class WebView2Host : HwndHost
    {
        const int WS_CHILD = 0x40000000, WS_VISIBLE = 0x10000000, WS_CLIPCHILDREN = 0x02000000, WS_CLIPSIBLINGS = 0x04000000;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct WNDCLASSEX { public int cbSize; public int style; public IntPtr lpfnWndProc; public int cbClsExtra, cbWndExtra; public IntPtr hInstance, hIcon, hCursor, hbrBackground; public string lpszMenuName, lpszClassName; public IntPtr hIconSm; }
        delegate IntPtr HostWndProc(IntPtr hwnd, int msg, IntPtr w, IntPtr l);
        [DllImport("user32", CharSet = CharSet.Unicode, SetLastError = true)] static extern ushort RegisterClassExW(ref WNDCLASSEX wc);
        [DllImport("user32", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateWindowExW(int ex, string cls, string name, int style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);
        [DllImport("user32")] static extern bool DestroyWindow(IntPtr hwnd);
        [DllImport("user32", CharSet = CharSet.Unicode)] static extern IntPtr DefWindowProcW(IntPtr hwnd, int msg, IntPtr w, IntPtr l);
        [DllImport("gdi32")] static extern IntPtr CreateSolidBrush(int colorref);
        [DllImport("kernel32", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandleW(string name);
        [DllImport("ole32")] static extern int CreateStreamOnHGlobal(IntPtr hGlobal, bool deleteOnRelease, out System.Runtime.InteropServices.ComTypes.IStream stream);
        [DllImport("gdi32")] static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int w, int h);
        [DllImport("gdi32")] static extern int CombineRgn(IntPtr dest, IntPtr src1, IntPtr src2, int mode);
        [DllImport("gdi32")] static extern bool DeleteObject(IntPtr obj);
        [DllImport("user32")] static extern int SetWindowRgn(IntPtr hwnd, IntPtr rgn, bool redraw);
        const int RGN_DIFF = 4;

        double _clipRadius, _cutoutRadius;
        Rect _cutout = Rect.Empty;

        /// <summary>Rounded screen corners and an optional cut-out (camera island), in DIPs, applied as the host window's
        /// region — WPF cannot draw over a child HWND, so the bezel art shows through the cut-out instead.</summary>
        public void SetScreenShape(double cornerRadius, Rect cutout, double cutoutRadius)
        {
            _clipRadius = cornerRadius; _cutout = cutout; _cutoutRadius = cutoutRadius;
            ApplyRegion();
        }

        void ApplyRegion()
        {
            if (_hwnd == IntPtr.Zero) return;
            var src = PresentationSource.FromVisual(this);
            double sx = 1, sy = 1;
            if (src != null && src.CompositionTarget != null) { sx = src.CompositionTarget.TransformToDevice.M11; sy = src.CompositionTarget.TransformToDevice.M22; }
            if (_clipRadius <= 0 && _cutout.IsEmpty) { SetWindowRgn(_hwnd, IntPtr.Zero, true); return; }
            int w = Math.Max(1, (int)Math.Round(ActualWidth * sx)), h = Math.Max(1, (int)Math.Round(ActualHeight * sy));
            IntPtr rgn = CreateRoundRectRgn(0, 0, w + 1, h + 1, (int)Math.Round(2 * _clipRadius * sx), (int)Math.Round(2 * _clipRadius * sy));
            if (!_cutout.IsEmpty)
            {
                IntPtr cut = CreateRoundRectRgn((int)Math.Round(_cutout.Left * sx), (int)Math.Round(_cutout.Top * sy), (int)Math.Round(_cutout.Right * sx) + 1, (int)Math.Round(_cutout.Bottom * sy) + 1,
                    (int)Math.Round(2 * _cutoutRadius * sx), (int)Math.Round(2 * _cutoutRadius * sy));
                CombineRgn(rgn, rgn, cut, RGN_DIFF);
                DeleteObject(cut);
            }
            if (SetWindowRgn(_hwnd, rgn, true) == 0) DeleteObject(rgn); // on success the system owns the region
        }

        static HostWndProc _proc;
        static string _class;

        IntPtr _hwnd;
        IWvController _controller;
        IWvWebView _web;
        string _pending;
        double _zoom = 1;
        bool _closed;
        string _userAgent;
        readonly List<object> _keep = new List<object>();
        readonly Color _bg;

        public event Action Ready;
        public event Action<string> Failed;
        public event Action<string> SourceChanged;
        public event Action<string> TitleChanged;
        public event Action<bool, int> NavigationCompleted;
        public event Action NavigationStarting;
        public event Action HistoryChanged;
        public event Action<string> WebMessageReceived;
        public event Action ProcessFailed;

        public bool IsReady { get { return _web != null; } }
        /// <summary>Script run at the start of every document (set before the browser starts).</summary>
        public string DocumentStartScript;
        public string Error { get; private set; }

        public WebView2Host(Color background) { _bg = background; }

        static string WindowClass(Color bg)
        {
            if (_class != null) return _class;
            _proc = (h, m, w, l) => DefWindowProcW(h, m, w, l);
            var wc = new WNDCLASSEX
            {
                cbSize = Marshal.SizeOf(typeof(WNDCLASSEX)), lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_proc),
                hInstance = GetModuleHandleW(null), hbrBackground = CreateSolidBrush(bg.R | (bg.G << 8) | (bg.B << 16)), lpszClassName = "MicroCodeWebHost"
            };
            if (RegisterClassExW(ref wc) == 0) { int err = Marshal.GetLastWin32Error(); if (err != 1410 /* class already exists */) throw new Win32Exception(err); }
            _class = "MicroCodeWebHost";
            return _class;
        }

        protected override HandleRef BuildWindowCore(HandleRef parent)
        {
            _hwnd = CreateWindowExW(0, WindowClass(_bg), "", WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_CLIPSIBLINGS, 0, 0, 1, 1, parent.Handle, IntPtr.Zero, GetModuleHandleW(null), IntPtr.Zero);
            if (_hwnd == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            IntPtr host = _hwnd;
            WebView2Runtime.GetEnvironment(env =>
            {
                if (_closed) return;
                try
                {
                    var h = new WvControllerCompleted(OnController);
                    _keep.Add(h);
                    env.CreateCoreWebView2Controller(host, h);
                }
                catch (Exception ex) { Fail(ex.Message); }
            }, Fail);
            return new HandleRef(this, _hwnd);
        }

        void Fail(string message)
        {
            Error = message;
            if (Failed != null) Failed(message);
        }

        void OnController(int hr, IWvController c)
        {
            if (hr < 0 || c == null) { Fail("WebView2 could not start (0x" + hr.ToString("X8") + ")"); return; }
            if (_closed) { try { c.Close(); } catch (COMException) { } return; }
            _controller = c;
            try
            {
                var c2 = c as IWvController2;
                if (c2 != null) c2.set_DefaultBackgroundColor(new WvColor { A = 255, R = _bg.R, G = _bg.G, B = _bg.B });
                _web = c.get_CoreWebView2();
                var s = _web.get_Settings();
                s.set_IsStatusBarEnabled(0);
                s.set_AreDevToolsEnabled(1);
                s.set_IsWebMessageEnabled(1);
                if (_userAgent != null) ApplyUserAgent();
                WvToken tok;
                var src = new WvSimpleHandler(() => { if (SourceChanged != null) SourceChanged(Source); }); _keep.Add(src); _web.add_SourceChanged(src, out tok);
                var title = new WvSimpleHandler(() => { if (TitleChanged != null) TitleChanged(Title); }); _keep.Add(title); _web.add_DocumentTitleChanged(title, out tok);
                var hist = new WvSimpleHandler(() => { if (HistoryChanged != null) HistoryChanged(); }); _keep.Add(hist); _web.add_HistoryChanged(hist, out tok);
                var start = new WvSimpleHandler(() => { if (NavigationStarting != null) NavigationStarting(); }); _keep.Add(start); _web.add_NavigationStarting(start, out tok);
                var crash = new WvSimpleHandler(() => { if (ProcessFailed != null) ProcessFailed(); }); _keep.Add(crash); _web.add_ProcessFailed(crash, out tok);
                var done = new WvNavigationCompleted((ok, status) => { if (NavigationCompleted != null) NavigationCompleted(ok, status); }); _keep.Add(done); _web.add_NavigationCompleted(done, out tok);
                // target=_blank / window.open stay inside the preview
                var popup = new WvNewWindowRequested(uri => { if (!string.IsNullOrEmpty(uri)) Navigate(uri); }); _keep.Add(popup); _web.add_NewWindowRequested(popup, out tok);
                var msg = new WvWebMessageReceived(json => { if (WebMessageReceived != null) WebMessageReceived(json); }); _keep.Add(msg); _web.add_WebMessageReceived(msg, out tok);
                UpdateBounds();
                c.set_ZoomFactor(_zoom);
                c.set_IsVisible(IsVisible ? 1 : 0);
                if (Ready != null) Ready();
                Action go = () => { if (_pending != null) { string u = _pending; _pending = null; Navigate(u); } };
                // the document-start script must be registered before the first page loads, so navigate once it is in
                if (DocumentStartScript != null)
                {
                    var added = new WvAddScriptCompleted((hr2, id) => go());
                    _keep.Add(added);
                    _web.AddScriptToExecuteOnDocumentCreated(DocumentStartScript, added);
                }
                else go();
            }
            catch (Exception ex) { Fail(ex.Message); }
        }

        public string Source { get { try { return _web != null ? _web.get_Source() : _pending; } catch (COMException) { return null; } } }
        public string Title { get { try { return _web != null ? _web.get_DocumentTitle() : null; } catch (COMException) { return null; } } }
        public bool CanGoBack { get { try { return _web != null && _web.get_CanGoBack() != 0; } catch (COMException) { return false; } } }
        public bool CanGoForward { get { try { return _web != null && _web.get_CanGoForward() != 0; } catch (COMException) { return false; } } }

        /// <summary>Navigates now, or as soon as the browser is ready. Returns false for a URI WebView2 rejects.</summary>
        public bool Navigate(string url)
        {
            if (string.IsNullOrWhiteSpace(url)) return false;
            if (_web == null) { _pending = url; return true; }
            try { _web.Navigate(url); return true; }
            catch (ArgumentException ex) { System.Diagnostics.Debug.WriteLine("navigate: " + ex.Message); return false; }
            catch (COMException ex) { System.Diagnostics.Debug.WriteLine("navigate: " + ex.Message); return false; }
        }

        public void NavigateToString(string html) { if (_web != null) _web.NavigateToString(html); }
        public void Reload() { if (_web != null) _web.Reload(); }
        public void Stop() { if (_web != null) _web.Stop(); }
        public void GoBack() { if (CanGoBack) _web.GoBack(); }
        public void GoForward() { if (CanGoForward) _web.GoForward(); }
        public void OpenDevTools() { if (_web != null) _web.OpenDevToolsWindow(); }

        public double Zoom
        {
            get { return _zoom; }
            set
            {
                _zoom = Math.Max(0.1, Math.Min(5, value));
                if (_controller != null) try { _controller.set_ZoomFactor(_zoom); } catch (COMException ex) { System.Diagnostics.Debug.WriteLine("zoom: " + ex.Message); }
            }
        }

        /// <summary>null restores the browser's own user agent.</summary>
        public string UserAgent { set { _userAgent = value; ApplyUserAgent(); } }

        string _defaultUA;
        void ApplyUserAgent()
        {
            if (_web == null) return;
            var s2 = _web.get_Settings() as IWvSettings2;
            if (s2 == null) return;
            if (_defaultUA == null) _defaultUA = s2.get_UserAgent();
            s2.set_UserAgent(_userAgent ?? _defaultUA);
        }

        public void ExecuteScript(string js, Action<string> done)
        {
            if (_web == null) { if (done != null) done(null); return; }
            WvScriptCompleted h = null;
            h = new WvScriptCompleted((hr, json) => { _keep.Remove(h); if (done != null) done(hr < 0 ? null : json); });
            _keep.Add(h);
            _web.ExecuteScript(js, h);
        }

        public void CallDevTools(string method, string json, Action<string> done)
        {
            if (_web == null) { if (done != null) done(null); return; }
            WvScriptCompleted h = null;
            h = new WvScriptCompleted((hr, result) => { _keep.Remove(h); if (done != null) done(hr < 0 ? null : result); });
            _keep.Add(h);
            _web.CallDevToolsProtocolMethod(method, json ?? "{}", h);
        }

        public void PostMessage(string json) { if (_web != null) _web.PostWebMessageAsJson(json); }

        /// <summary>PNG of what the page shows right now (null when not ready or on failure).</summary>
        public void CapturePng(Action<byte[]> done)
        {
            if (_web == null) { done(null); return; }
            System.Runtime.InteropServices.ComTypes.IStream stream;
            if (CreateStreamOnHGlobal(IntPtr.Zero, true, out stream) < 0) { done(null); return; }
            WvCaptureCompleted h = null;
            h = new WvCaptureCompleted(hr =>
            {
                _keep.Remove(h);
                if (hr < 0) { done(null); return; }
                System.Runtime.InteropServices.ComTypes.STATSTG st;
                stream.Stat(out st, 1);
                var bytes = new byte[st.cbSize];
                stream.Seek(0, 0, IntPtr.Zero);
                stream.Read(bytes, bytes.Length, IntPtr.Zero);
                done(bytes);
            });
            _keep.Add(h);
            _web.CapturePreview(0 /* PNG */, stream, h);
        }

        void UpdateBounds()
        {
            if (_controller == null) return;
            var src = PresentationSource.FromVisual(this);
            double sx = 1, sy = 1;
            if (src != null && src.CompositionTarget != null) { sx = src.CompositionTarget.TransformToDevice.M11; sy = src.CompositionTarget.TransformToDevice.M22; }
            int w = Math.Max(1, (int)Math.Round(ActualWidth * sx)), h = Math.Max(1, (int)Math.Round(ActualHeight * sy));
            try { _controller.set_Bounds(new WvRect { Left = 0, Top = 0, Right = w, Bottom = h }); }
            catch (COMException ex) { System.Diagnostics.Debug.WriteLine("bounds: " + ex.Message); }
            ApplyRegion();
        }

        protected override void OnRenderSizeChanged(SizeChangedInfo info)
        {
            base.OnRenderSizeChanged(info);
            UpdateBounds();
        }

        protected override void OnWindowPositionChanged(Rect rcBoundingBox)
        {
            base.OnWindowPositionChanged(rcBoundingBox);
            UpdateBounds();
            if (_controller != null) try { _controller.NotifyParentWindowPositionChanged(); } catch (COMException) { }
        }

        public WebView2Host() : this(Color.FromRgb(30, 30, 30)) { }

        protected override void OnVisualParentChanged(DependencyObject oldParent)
        {
            base.OnVisualParentChanged(oldParent);
            IsVisibleChanged -= OnVisibleChanged;
            IsVisibleChanged += OnVisibleChanged;
        }

        void OnVisibleChanged(object s, DependencyPropertyChangedEventArgs e)
        {
            if (_controller != null) try { _controller.set_IsVisible(IsVisible ? 1 : 0); } catch (COMException ex) { System.Diagnostics.Debug.WriteLine("visible: " + ex.Message); }
        }

        protected override void DestroyWindowCore(HandleRef hwnd)
        {
            _closed = true;
            if (_controller != null)
            {
                try { _controller.Close(); } catch (COMException ex) { System.Diagnostics.Debug.WriteLine("close: " + ex.Message); }
                Marshal.ReleaseComObject(_controller);
                _controller = null;
            }
            _web = null;
            _keep.Clear();
            DestroyWindow(hwnd.Handle);
        }
    }
}
