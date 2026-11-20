// EmbeddedWebAppPreviewView.swift for Windows: the WebApp preview tab of the Preview dock. One slim 30pt control bar
// (‹ › ↻ · viewport & frame menu · URL bar with detected dev-server port · Inspect · port radar · Build · Hot Reload ·
// options), a build-log drawer, a runtime-error banner with "Fix in Agent", and the canvas with the page inside a device
// frame. The browser is Edge WebView2 (src/Preview/WebView2.cs); one instance lives for the whole session so the page keeps
// its state when the pane is hidden or another tab is selected.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public class WebAppPreview : Border
    {
        static WebAppPreview _shared;
        /// <summary>The one live preview (created on first use, kept for the session).</summary>
        public static WebAppPreview Shared { get { if (_shared == null) _shared = new WebAppPreview(AppState.Shared); return _shared; } }
        public static bool Created { get { return _shared != null; } }

        readonly AppState _app;
        WebView2Host _web;
        DeviceFrameView _frame;
        readonly Border _bar = new Border(), _drawer = new Border(), _banner = new Border(), _inspect = new Border(), _canvas = new Border(), _sizeLabel = new Border();
        TextBox _url;
        string _current, _title, _status;
        bool _loading, _liveReload, _inspecting, _hasHmr;
        WebViewport _viewport;
        bool _landscape, _bezel, _actual;
        double _respW;
        readonly List<Dictionary<string, object>> _picks = new List<Dictionary<string, object>>();
        readonly List<string> _errors = new List<string>();
        List<LocalPort> _ports = new List<LocalPort>();
        FileSystemWatcher _watch;
        readonly DispatcherTimer _reloadDebounce, _emulateDebounce, _logPump;
        bool _showLogs, _narrow;

        const string ErrorHookJs = @"(function(){if(window.__mcHooks)return;window.__mcHooks=1;var post=function(m){try{window.chrome.webview.postMessage(m)}catch(e){}};
window.addEventListener('error',function(e){var t=e.target;if(t&&t!==window&&(t.src||t.href)){post({type:'error',message:'Failed to load '+(t.tagName||'').toLowerCase()+': '+(t.src||t.href)});return;}
post({type:'error',message:String(e.message||e),source:(e.filename||'')+(e.lineno?':'+e.lineno:'')});},true);
window.addEventListener('unhandledrejection',function(e){var r=e.reason;post({type:'error',message:'Unhandled promise rejection: '+(r&&(r.stack||r.message)||String(r))});});
var ce=console.error;console.error=function(){try{post({type:'error',message:Array.prototype.map.call(arguments,function(a){return a&&a.stack?a.stack:(typeof a==='object'?JSON.stringify(a):String(a))}).join(' ')})}catch(x){}return ce.apply(console,arguments)};})();";

        const string InspectJs = @"(function(){if(window.__mcInspect){window.__mcInspect.toggle();return;}
var on=false,box=document.createElement('div'),tag=document.createElement('div');
box.style.cssText='position:fixed;pointer-events:none;z-index:2147483646;border:1.5px solid #0a84ff;background:rgba(10,132,255,.12);border-radius:3px;display:none';
tag.style.cssText='position:fixed;pointer-events:none;z-index:2147483647;font:600 11px -apple-system,Segoe UI,sans-serif;color:#fff;background:#0a84ff;padding:2px 6px;border-radius:4px;display:none';
document.documentElement.appendChild(box);document.documentElement.appendChild(tag);
function sel(el){if(el.id)return '#'+el.id;var p=[];while(el&&el.nodeType===1&&p.length<5){var s=el.tagName.toLowerCase();if(el.classList.length)s+='.'+Array.prototype.slice.call(el.classList,0,2).join('.');var par=el.parentElement;if(par){var sib=Array.prototype.filter.call(par.children,function(c){return c.tagName===el.tagName});if(sib.length>1)s+=':nth-of-type('+(sib.indexOf(el)+1)+')';}p.unshift(s);if(el.id)break;el=par;}return p.join(' > ');}
function move(e){if(!on)return;var r=e.target.getBoundingClientRect();box.style.display='block';box.style.left=r.left+'px';box.style.top=r.top+'px';box.style.width=r.width+'px';box.style.height=r.height+'px';
tag.style.display='block';tag.textContent=e.target.tagName.toLowerCase()+' '+Math.round(r.width)+'×'+Math.round(r.height);tag.style.left=r.left+'px';tag.style.top=Math.max(0,r.top-20)+'px';}
function click(e){if(!on)return;e.preventDefault();e.stopPropagation();var t=e.target,r=t.getBoundingClientRect();
window.chrome.webview.postMessage({type:'pick',selector:sel(t),tag:t.tagName.toLowerCase(),text:(t.innerText||t.value||t.alt||'').trim().slice(0,160),html:t.outerHTML.slice(0,400),rect:[Math.round(r.left),Math.round(r.top),Math.round(r.width),Math.round(r.height)]});}
document.addEventListener('mousemove',move,true);document.addEventListener('click',click,true);
window.__mcInspect={toggle:function(){on=!on;if(!on){box.style.display='none';tag.style.display='none';}document.documentElement.style.cursor=on?'crosshair':'';}};window.__mcInspect.toggle();})();";

        public WebAppPreview(AppState app)
        {
            _app = app;
            _viewport = WebViewport.Find(Defaults.Str("webPreviewViewport", "responsive"));
            _landscape = Defaults.Bool("webPreviewLandscape", false);
            _bezel = Defaults.Bool("webPreviewBezel", true);
            _actual = Defaults.Bool("webPreviewActual", false);
            _respW = Defaults.Num("webPreviewWidth", 0);
            _liveReload = Defaults.Bool("webPreviewLiveReload", true);
            _reloadDebounce = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(350) };
            _reloadDebounce.Tick += delegate { _reloadDebounce.Stop(); if (_web != null && _current != null) _web.Reload(); };
            _emulateDebounce = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(120) };
            _emulateDebounce.Tick += delegate { _emulateDebounce.Stop(); ApplyEmulation(); };
            _logPump = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) };
            _logPump.Tick += delegate { RenderDrawer(); RenderBar(); };
            var col = new DockPanel { LastChildFill = true };
            foreach (var b in new[] { _bar, _drawer, _banner }) { DockPanel.SetDock(b, Dock.Top); col.Children.Add(b); }
            DockPanel.SetDock(_inspect, Dock.Bottom); col.Children.Add(_inspect);
            DockPanel.SetDock(_sizeLabel, Dock.Bottom); col.Children.Add(_sizeLabel);
            col.Children.Add(_canvas);
            Child = col;
            Background = Theme.Current.EditorBackground;
            _app.Changed += what => { if (what == "workspace") Dispatcher.BeginInvoke(new Action(OnWorkspaceChanged)); };
            Loaded += delegate { if (_current == null && _web == null) ResolveInitialUrl(); RenderAll(); };
            // compact control bar in a narrow pane: the URL field keeps the room
            SizeChanged += (s, e) => { bool narrow = e.NewSize.Width < 470; if (narrow != _narrow) { _narrow = narrow; RenderBar(); } };
            RenderAll();
        }

        string StoreKey { get { return "webPreviewUrl:" + (_app.WorkspaceFolder ?? "").ToLowerInvariant(); } }

        void OnWorkspaceChanged()
        {
            _current = null; _errors.Clear(); _picks.Clear();
            Watch();
            ResolveInitialUrl();
            RenderAll();
        }

        /// <summary>resolveInitialURL: the last URL of this workspace, a running dev server, then the workspace index.html.</summary>
        void ResolveInitialUrl()
        {
            string saved = Defaults.Str(StoreKey, null);
            _ports = LocalPorts.Listening();
            var best = LocalPorts.Best(_ports);
            if (!string.IsNullOrEmpty(saved) && (!IsLocalHttp(saved) || _ports.Any(p => p.Port == PortOf(saved)))) { Navigate(saved); return; }
            if (best != null) { Navigate("http://localhost:" + best.Port + "/"); return; }
            string index = WorkspaceIndex();
            if (index != null) Navigate(new Uri(index).AbsoluteUri);
        }

        string WorkspaceIndex()
        {
            string ws = _app.WorkspaceFolder;
            if (ws == null) return null;
            foreach (var rel in new[] { "index.html", "public\\index.html", "src\\index.html", "www\\index.html", "docs\\index.html" })
            {
                string p = Path.Combine(ws, rel);
                if (File.Exists(p)) return p;
            }
            return null;
        }

        static bool IsLocalHttp(string url) { return url.StartsWith("http://localhost", StringComparison.OrdinalIgnoreCase) || url.StartsWith("http://127.0.0.1", StringComparison.OrdinalIgnoreCase); }
        static int PortOf(string url) { Uri u; return Uri.TryCreate(url, UriKind.Absolute, out u) ? u.Port : -1; }

        // ── browser ──

        void EnsureBrowser()
        {
            if (_web != null) return;
            var bg = Theme.Current.EditorBackground as SolidColorBrush;
            _web = new WebView2Host(bg != null ? bg.Color : Color.FromRgb(30, 30, 30));
            _web.SourceChanged += src => { _current = src; if (!string.IsNullOrEmpty(src) && !src.StartsWith("data:") && src != "about:blank") Defaults.Set(StoreKey, src); if (_url != null && !_url.IsKeyboardFocused) _url.Text = src; };
            _web.TitleChanged += t => { _title = t; };
            _web.NavigationStarting += () => { _loading = true; _picks.Clear(); _inspecting = false; RenderBar(); RenderInspect(); };
            _web.NavigationCompleted += (ok, status) =>
            {
                _loading = false;
                _status = ok ? null : "Could not load the page (" + WebError(status) + ")";
                RenderBar(); RenderBanner();
                if (ok) _web.ExecuteScript("!!(document.querySelector('script[src*=\"/@vite/client\"]')||window.webpackHotUpdate||window.__NEXT_DATA__||window.__webpack_require__||window.__parcel__require__)", r => { _hasHmr = r == "true"; });
            };
            _web.HistoryChanged += RenderBar;
            _web.DocumentStartScript = ErrorHookJs;
            _web.Ready += ApplyEmulation;
            _web.Failed += msg => { _status = msg; RenderCanvas(); };
            _web.ProcessFailed += () => { _status = "The page's browser process stopped — press Reload."; RenderBanner(); };
            _web.WebMessageReceived += OnWebMessage;
            _frame = new DeviceFrameView(_web);
            _frame.ResponsiveWidthChanged += w => { _respW = w; Defaults.Set("webPreviewWidth", w); RenderSizeLabel(); };
            _frame.SizeChanged += delegate { ApplyShapeAndEmulationSoon(); RenderSizeLabel(); };
            Watch();
        }

        static string WebError(int status)
        {
            switch (status)
            {
                case 12: return "connection refused — is the dev server running?";
                case 13: return "server not found";
                case 7: return "timed out";
                case 9: return "connection lost";
                case 5: return "certificate error";
                case 15: return "connection aborted";
                default: return "error " + status;
            }
        }

        public void Navigate(string url)
        {
            if (string.IsNullOrWhiteSpace(url)) return;
            url = url.Trim();
            if (!url.Contains("://") && !url.StartsWith("about:") && !url.StartsWith("data:"))
            {
                if (File.Exists(url)) url = new Uri(Path.GetFullPath(url)).AbsoluteUri;
                else if (System.Text.RegularExpressions.Regex.IsMatch(url, @"^:?\d{2,5}(/.*)?$")) url = "http://localhost:" + url.TrimStart(':');
                else url = (url.StartsWith("localhost") || url.StartsWith("127.") ? "http://" : "https://") + url;
            }
            EnsureBrowser();
            _current = url; _status = null; _errors.Clear();
            if (!_web.Navigate(url)) _status = "Not a valid address: " + url;
            if (_url != null) _url.Text = url;
            RenderAll();
        }

        void Reload(bool hard)
        {
            if (_web == null || _current == null) { ResolveInitialUrl(); return; }
            _errors.Clear(); RenderBanner();
            if (hard) _web.CallDevTools("Network.clearBrowserCache", "{}", r => _web.Reload());
            else _web.Reload();
        }

        /// <summary>Device emulation (DevTools protocol, like Chrome's device mode): CSS viewport of the device, mobile
        /// viewport rules, touch and user agent; the page is rendered at the frame's scale so it fits the pane.</summary>
        void ApplyEmulation()
        {
            if (_web == null || !_web.IsReady || _frame == null) return;
            if (_viewport.IsResponsive)
            {
                _web.CallDevTools("Emulation.clearDeviceMetricsOverride", "{}", null);
                _web.CallDevTools("Emulation.setTouchEmulationEnabled", "{\"enabled\":false}", null);
                _web.CallDevTools("Emulation.setEmitTouchEventsForMouse", "{\"enabled\":false}", null);
                _web.UserAgent = null;
                return;
            }
            double w = _frame.ScreenCssW, h = _frame.ScreenCssH, s = Math.Max(0.05, _frame.Scale);
            string metrics = string.Format(System.Globalization.CultureInfo.InvariantCulture,
                "{{\"width\":{0},\"height\":{1},\"deviceScaleFactor\":0,\"mobile\":{2},\"screenWidth\":{0},\"screenHeight\":{1},\"screenOrientation\":{{\"type\":\"{4}\",\"angle\":{5}}}}}",
                (int)w, (int)h, _viewport.Mobile ? "true" : "false", s, _landscape ? "landscapePrimary" : "portraitPrimary", _landscape ? 90 : 0);
            _web.CallDevTools("Emulation.setDeviceMetricsOverride", metrics, null);
            _web.CallDevTools("Emulation.setTouchEmulationEnabled", _viewport.Mobile ? "{\"enabled\":true,\"maxTouchPoints\":5}" : "{\"enabled\":false}", null);
            _web.CallDevTools("Emulation.setEmitTouchEventsForMouse", _viewport.Mobile ? "{\"enabled\":true,\"configuration\":\"mobile\"}" : "{\"enabled\":false}", null);
            _web.UserAgent = _viewport.UserAgent;
        }

        void ApplyShapeAndEmulationSoon()
        {
            if (_web == null || _frame == null) return;
            double r; Rect island; double ir;
            _frame.ScreenShape(out r, out island, out ir);
            _web.SetScreenShape(r, island, ir);
            _emulateDebounce.Stop(); _emulateDebounce.Start();
        }

        void SetViewport(WebViewport v)
        {
            bool uaChanged = (v.UserAgent ?? "") != (_viewport.UserAgent ?? "");
            _viewport = v;
            if (!v.IsResponsive) _bezel = true;
            if (!v.CanRotate) _landscape = false;
            Defaults.Set("webPreviewViewport", v.Id);
            RenderCanvas(); RenderBar(); RenderSizeLabel();
            ApplyShapeAndEmulationSoon();
            if (uaChanged && _web != null && _current != null) Dispatcher.BeginInvoke(new Action(() => _web.Reload()), DispatcherPriority.Background);
        }

        // ── live reload ──

        void Watch()
        {
            if (_watch != null) { _watch.EnableRaisingEvents = false; _watch.Dispose(); _watch = null; }
            string ws = _app.WorkspaceFolder;
            if (ws == null || !Directory.Exists(ws)) return;
            try
            {
                _watch = new FileSystemWatcher(ws) { IncludeSubdirectories = true, NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName };
                FileSystemEventHandler h = (s, e) => Dispatcher.BeginInvoke(new Action(() => OnFileChanged(e.FullPath)));
                _watch.Changed += h; _watch.Created += h; _watch.Renamed += (s, e) => Dispatcher.BeginInvoke(new Action(() => OnFileChanged(e.FullPath)));
                _watch.EnableRaisingEvents = true;
            }
            catch (ArgumentException ex) { System.Diagnostics.Debug.WriteLine("preview watcher: " + ex.Message); }
            catch (IOException ex) { System.Diagnostics.Debug.WriteLine("preview watcher: " + ex.Message); }
        }

        static readonly string[] WebExt = { ".html", ".htm", ".css", ".scss", ".js", ".mjs", ".jsx", ".ts", ".tsx", ".vue", ".svelte", ".astro", ".json", ".svg", ".png", ".jpg", ".md" };
        static readonly string[] SkipDirs = { "\\node_modules\\", "\\.git\\", "\\dist\\", "\\build\\", "\\.next\\", "\\.vite\\", "\\.svelte-kit\\", "\\out\\", "\\.microcode\\", "\\target\\" };

        void OnFileChanged(string path)
        {
            if (!_liveReload || _web == null || _current == null) return;
            if (!WebExt.Contains(Path.GetExtension(path).ToLowerInvariant())) return;
            if (SkipDirs.Any(d => path.IndexOf(d, StringComparison.OrdinalIgnoreCase) >= 0)) return;
            // dev servers with hot module replacement update the page themselves
            if (_current.StartsWith("file:", StringComparison.OrdinalIgnoreCase) || !_hasHmr) { _reloadDebounce.Stop(); _reloadDebounce.Start(); }
        }

        // ── messages from the page ──

        void OnWebMessage(string json)
        {
            Dictionary<string, object> m;
            try { m = new JavaScriptSerializer().DeserializeObject(json) as Dictionary<string, object>; }
            catch (ArgumentException) { return; }
            if (m == null || !m.ContainsKey("type")) return;
            string type = m["type"] as string;
            if (type == "error")
            {
                string msg = (m.ContainsKey("message") ? Convert.ToString(m["message"]) : "") + (m.ContainsKey("source") && Convert.ToString(m["source"]).Length > 0 ? "  (" + m["source"] + ")" : "");
                if (_errors.Count < 50 && !_errors.Contains(msg)) _errors.Add(msg);
                RenderBanner(); RenderBar();
            }
            else if (type == "pick")
            {
                _picks.Add(m);
                RenderInspect(); RenderBar();
            }
        }

        static string Json(string s) { return new JavaScriptSerializer().Serialize(s); }

        void SendToAgent(string prompt)
        {
            _app.SwitchToMode(EditorMode.AIAgent);
            _app.Notify("agent:send:" + prompt);
        }

        // ── rendering ──

        void RenderAll() { RenderBar(); RenderDrawer(); RenderBanner(); RenderCanvas(); RenderInspect(); RenderSizeLabel(); }

        Btn Icon(string icon, string tip, Action a, bool enabled, bool active)
        {
            var t = Theme.Current;
            var b = V.Button(V.Size(V.Box(Sym.Icon(icon, 10, enabled ? (active ? t.Primary : t.P(0.82)) : t.S(0.45), FontWeights.Medium), V.P(0), active ? t.P(0.12) : Brushes.Transparent, 4), 20, 20), enabled ? a : null);
            b.ToolTip = tip;
            if (enabled) b.OnState = x => ((Border)((FrameworkElement)x.Child)).Background = x.IsHover ? t.P(0.09) : (active ? t.P(0.12) : Brushes.Transparent);
            return b;
        }

        void RenderBar()
        {
            var t = Theme.Current;
            var row = V.H(5);
            // 1. ‹ › ↻
            row.Children.Add(V.H(1, Icon("chevron.left", "Back", () => _web.GoBack(), _web != null && _web.CanGoBack, false),
                Icon("chevron.right", "Forward", () => _web.GoForward(), _web != null && _web.CanGoForward, false),
                Icon(_loading ? "xmark" : "arrow.clockwise", _loading ? "Stop loading" : "Reload Page (Ctrl+R)", () => { if (_loading && _web != null) _web.Stop(); else Reload(false); }, true, false)));
            // 2. viewport & frame menu
            var vpLabel = V.H(3, Sym.Icon(_viewport.Icon, 9.5, t.Primary, FontWeights.Medium),
                V.T(_viewport.IsResponsive ? (_respW > 0 ? (int)_respW + "px" : "Responsive") : _viewport.Name, 10, FontWeights.Medium, t.Primary),
                Sym.Icon("chevron.down", 7, t.Secondary, FontWeights.SemiBold));
            var vp = V.Button(V.Size(V.Box(vpLabel, V.P(6, 0), t.P(0.06), 4), double.NaN, 22), null);
            vp.ToolTip = "Viewport Preset, Breakpoints & Device Frame";
            vp.MenuItems = ViewportMenu;
            row.Children.Add(vp);
            // 3. URL bar
            TextBox box;
            var field = Styles.Field("http://localhost:3000", 10.5, t.Primary, t.S(0.6), out box);
            box.FontFamily = UIFonts.Mono;
            box.Text = _current ?? "";
            box.KeyDown += (s, e) => { if (e.Key == Key.Enter) { Navigate(box.Text); e.Handled = true; } if (e.Key == Key.Escape) { box.Text = _current ?? ""; Keyboard.ClearFocus(); } };
            _url = box;
            string icon = _current != null && _current.StartsWith("file:") ? "doc.fill" : (_current != null && _current.StartsWith("https") ? "lock.fill" : "globe");
            var urlRow = V.H(4, Sym.Icon(icon, 8.5, t.Secondary), V.Flex(field));
            var best = LocalPorts.Best(_ports);
            if (best != null && (_current == null || PortOf(_current) != best.Port))
            {
                var chip = V.Button(V.Box(V.Mono(":" + best.Port, 9, FontWeights.SemiBold, t.Primary), V.P(4, 1), t.P(0.08), 3), () => Navigate("http://localhost:" + best.Port + "/"));
                chip.ToolTip = "Switch to detected local dev server on port " + best.Port + " (" + best.Process + ")";
                urlRow.Children.Add(chip);
            }
            row.Children.Add(V.Flex(V.Size(V.Box(urlRow, V.P(7, 0), t.P(0.05), 5, t.P(0.08), 0.6), double.NaN, 22)));
            // 4. Inspect
            var insp = V.H(3.5, Sym.Icon("viewfinder", 10, _inspecting ? t.Primary : t.Secondary));
            if (_picks.Count > 0) insp.Children.Add(V.T(_picks.Count.ToString(), 9.5, FontWeights.SemiBold, t.Primary));
            var inspBtn = V.Button(V.Size(V.Box(insp, V.P(5, 0), _inspecting ? t.P(0.16) : t.P(0.06), 4), double.NaN, 22), ToggleInspect);
            inspBtn.ToolTip = "Multi-Point Inspect in Preview — click elements on the page to send them to the AI Agent";
            row.Children.Add(inspBtn);
            // 5. port radar
            var radar = V.H(3, Sym.Icon("antenna.radiowaves.left.and.right", 10, t.Secondary));
            if (_ports.Count > 0) radar.Children.Add(V.T(_ports.Count.ToString(), 9.5, FontWeights.SemiBold, t.Secondary));
            var radarBtn = V.Button(V.Size(V.Box(radar, V.P(5, 0), t.P(0.06), 4), double.NaN, 22), null);
            radarBtn.ToolTip = "Active Localhost Ports";
            radarBtn.MenuItems = PortsMenu;
            radarBtn.MenuAlignRight = true;
            row.Children.Add(radarBtn);
            // 6. Build / hot reload / stop
            var dev = DevServer.Current;
            bool running = dev != null && dev.Running;
            var buildRow = V.H(3, Sym.Icon(running ? "arrow.clockwise" : "play.fill", 9, t.Primary));
            if (!_narrow) buildRow.Children.Add(V.T(running ? "Running" : "Build", 10, FontWeights.Medium, t.Primary));
            var build = V.Button(V.Size(V.Box(buildRow, V.P(6, 0), t.P(0.06), 4), double.NaN, 22), BuildAndPreview);
            build.ToolTip = running ? "Dev server running: " + dev.Command : "Build & Preview (runs the workspace dev script or opens index.html)";
            row.Children.Add(build);
            if (!_narrow) row.Children.Add(Icon("bolt.fill", "Instant Hot Reload", () => Reload(false), true, false));
            if (running) row.Children.Add(Icon("stop.fill", "Stop running app preview process", () => { dev.Stop(); _logPump.Stop(); RenderAll(); }, true, false));
            // 7. options
            var more = V.Button(V.Size(V.Box(Sym.Icon("ellipsis", 10, t.Secondary), V.P(0), Brushes.Transparent, 4), 20, 20), null);
            more.ToolTip = "Preview Options & Logs";
            more.MenuItems = OptionsMenu;
            more.MenuAlignRight = true;
            row.Children.Add(more);
            _bar.Child = V.Box(row, V.P(8, 4), t.PanelBackground, 0);
            _bar.BorderBrush = t.Separator; _bar.BorderThickness = new Thickness(0, 0, 0, 1);
        }

        List<MenuItemSpec> ViewportMenu()
        {
            var items = new List<MenuItemSpec> { MenuItemSpec.Header("Device Viewport") };
            foreach (var v in WebViewport.All)
            {
                var vv = v;
                items.Add(new MenuItemSpec { Title = v.Name, Icon = v.Icon, Checked = _viewport == v, Action = () => SetViewport(vv) });
            }
            items.Add(MenuItemSpec.Sep());
            if (_viewport.IsResponsive)
            {
                items.Add(MenuItemSpec.Header("Responsive Breakpoints"));
                foreach (int w in WebViewport.Breakpoints)
                {
                    int ww = w;
                    items.Add(new MenuItemSpec { Title = WebViewport.BreakpointName(w), Checked = (int)_respW == w, Action = () => { _respW = ww; Defaults.Set("webPreviewWidth", (double)ww); RenderCanvas(); RenderBar(); RenderSizeLabel(); } });
                }
            }
            else
            {
                items.Add(MenuItemSpec.Item(_bezel ? "Hide Hardware Frame" : "Show Hardware Frame", "iphone", () => { _bezel = !_bezel; Defaults.Set("webPreviewBezel", _bezel); RenderCanvas(); ApplyShapeAndEmulationSoon(); }));
                if (_viewport.Id == "iphoneDuoOuter" || _viewport.Id == "iphoneDuoInner")
                    items.Add(MenuItemSpec.Item(_viewport.Id == "iphoneDuoOuter" ? "Unfold to Inner Screen (จอใน · 951×669)" : "Fold to Outer Screen (จอนอก · 466×678)", "book.pages", () => SetViewport(WebViewport.Find(_viewport.Id == "iphoneDuoOuter" ? "iphoneDuoInner" : "iphoneDuoOuter"))));
                if (_viewport.CanRotate)
                    items.Add(MenuItemSpec.Item(_landscape ? "Switch to Portrait" : "Switch to Landscape", "rotate.right", () => { _landscape = !_landscape; Defaults.Set("webPreviewLandscape", _landscape); RenderCanvas(); RenderSizeLabel(); ApplyShapeAndEmulationSoon(); }));
                items.Add(MenuItemSpec.Sub("Zoom (" + (_actual ? "100%" : "Fit Window") + ")", "magnifyingglass", new List<MenuItemSpec>
                {
                    new MenuItemSpec { Title = "Fit Window", Checked = !_actual, Action = () => { _actual = false; Defaults.Set("webPreviewActual", false); RenderCanvas(); ApplyShapeAndEmulationSoon(); } },
                    new MenuItemSpec { Title = "Actual Size (100%)", Checked = _actual, Action = () => { _actual = true; Defaults.Set("webPreviewActual", true); RenderCanvas(); ApplyShapeAndEmulationSoon(); } }
                }));
            }
            items.Add(MenuItemSpec.Sep());
            items.Add(MenuItemSpec.Item(_liveReload ? "Pause Live Reload on Save" : "Enable Live Reload on Save", "bolt.fill", () => { _liveReload = !_liveReload; Defaults.Set("webPreviewLiveReload", _liveReload); }));
            return items;
        }

        List<MenuItemSpec> PortsMenu()
        {
            _ports = LocalPorts.Listening();
            var items = new List<MenuItemSpec> { MenuItemSpec.Header("Active Localhost Ports") };
            if (_ports.Count == 0) items.Add(new MenuItemSpec { Title = "No active user localhost servers detected.", Disabled = true });
            foreach (var p in _ports)
            {
                var pp = p;
                items.Add(MenuItemSpec.Sub(":" + p.Port + "  " + p.Process + "  ·  PID " + p.Pid, p.LooksLikeDevServer ? "globe" : "network", new List<MenuItemSpec>
                {
                    MenuItemSpec.Item("Preview", "eye", () => Navigate("http://localhost:" + pp.Port + "/")),
                    MenuItemSpec.Item("Open in External Browser", "safari", () => FilePreview.Shell("http://localhost:" + pp.Port + "/", null)),
                    MenuItemSpec.Item("Copy URL", "doc.on.doc", () => CopyText("http://localhost:" + pp.Port + "/")),
                    MenuItemSpec.Sep(),
                    new MenuItemSpec { Title = "Kill " + pp.Process + " (PID " + pp.Pid + ")", Icon = "xmark", Destructive = true, Action = () => KillPort(pp) }
                }));
            }
            items.Add(MenuItemSpec.Sep());
            items.Add(MenuItemSpec.Item("Rescan Listening Ports", "arrow.clockwise", () => { _ports = LocalPorts.Listening(); RenderBar(); RenderCanvas(); }));
            return items;
        }

        void KillPort(LocalPort p)
        {
            if (MessageBox.Show("Stop " + p.Process + " (PID " + p.Pid + ") listening on port " + p.Port + "?", "MicroCode", MessageBoxButton.OKCancel, MessageBoxImage.Warning) != MessageBoxResult.OK) return;
            try { using (var proc = System.Diagnostics.Process.GetProcessById(p.Pid)) proc.Kill(); }
            catch (ArgumentException ex) { System.Diagnostics.Debug.WriteLine("kill: " + ex.Message); }
            catch (System.ComponentModel.Win32Exception ex) { MessageBox.Show("Could not stop the process: " + ex.Message, "MicroCode"); }
            catch (InvalidOperationException ex) { System.Diagnostics.Debug.WriteLine("kill: " + ex.Message); }
            _ports = LocalPorts.Listening();
            RenderBar();
        }

        List<MenuItemSpec> OptionsMenu()
        {
            var items = new List<MenuItemSpec>();
            string index = WorkspaceIndex();
            if (index != null) items.Add(MenuItemSpec.Item("Preview Workspace index.html", "doc.richtext", () => Navigate(new Uri(index).AbsoluteUri)));
            if (_current != null)
            {
                items.Add(MenuItemSpec.Item("Copy Preview URL", "doc.on.doc", () => CopyText(_current)));
                items.Add(MenuItemSpec.Item("Open in External Browser", "safari", () => FilePreview.Shell(_current, null)));
                items.Add(MenuItemSpec.Item("Hard Reload & Clear Cache", "arrow.clockwise", () => Reload(true)));
                items.Add(MenuItemSpec.Item("Open DevTools", "wrench.and.screwdriver", () => { if (_web != null) _web.OpenDevTools(); }));
            }
            items.Add(MenuItemSpec.Sep());
            items.Add(MenuItemSpec.Item(_showLogs ? "Hide Build & Hot-Reload Logs" : "Show Build & Hot-Reload Logs", "doc.text", () => { _showLogs = !_showLogs; RenderDrawer(); }));
            items.Add(new MenuItemSpec { Title = "Live Reload on Save", Checked = _liveReload, Action = () => { _liveReload = !_liveReload; Defaults.Set("webPreviewLiveReload", _liveReload); } });
            return items;
        }

        static void CopyText(string s) { try { Clipboard.SetText(s); } catch (System.Runtime.InteropServices.ExternalException ex) { System.Diagnostics.Debug.WriteLine("clipboard: " + ex.Message); } }

        void BuildAndPreview()
        {
            var cur = DevServer.Current;
            if (cur != null && cur.Running) { _showLogs = !_showLogs; RenderDrawer(); return; }
            string ws = _app.WorkspaceFolder;
            string cmd = DevServer.DetectCommand(ws);
            if (cmd == null)
            {
                string index = WorkspaceIndex();
                if (index != null) { Navigate(new Uri(index).AbsoluteUri); return; }
                _status = ws == null ? "Open a project folder to build and preview it." : "No dev script in package.json and no index.html in this folder — type a URL above.";
                RenderCanvas();
                return;
            }
            var d = DevServer.Start(ws, cmd);
            _showLogs = true;
            d.UrlFound += url => Dispatcher.BeginInvoke(new Action(() => { _showLogs = false; Navigate(url); RenderDrawer(); }));
            _logPump.Start();
            RenderAll();
        }

        void RenderDrawer()
        {
            var t = Theme.Current;
            var dev = DevServer.Current;
            if (!_showLogs || dev == null) { _drawer.Child = null; if (dev == null || !dev.Running) _logPump.Stop(); return; }
            var head = V.H(6, V.T("UNIVERSAL BUILD & HOT-RELOAD OUTPUT", 9.5, FontWeights.Bold, t.Secondary), V.Sp(),
                PanelUI.Small("doc.on.doc", "Copy", () => CopyText(dev.Log)), PanelUI.Small("xmark", null, () => { _showLogs = false; RenderDrawer(); }));
            var log = new TextBox { Text = dev.Log, IsReadOnly = true, FontFamily = UIFonts.Mono, FontSize = 10.5, Foreground = t.S(0.95), Background = Brushes.Transparent, BorderThickness = new Thickness(0), TextWrapping = TextWrapping.Wrap, Height = 140, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            log.ScrollToEnd();
            var col = V.VLead(4, V.Self(head, Cross.Stretch), V.Self(log, Cross.Stretch)); col.Align = Cross.Stretch;
            _drawer.Child = V.Box(col, V.P(10, 6), t.P(0.04), 0);
            _drawer.BorderBrush = t.Separator; _drawer.BorderThickness = new Thickness(0, 0, 0, 1);
        }

        void RenderBanner()
        {
            var t = Theme.Current;
            if (_errors.Count == 0 && _status == null) { _banner.Child = null; return; }
            var row = V.H(6);
            if (_errors.Count > 0)
            {
                row.Children.Add(Sym.Icon("exclamationmark.triangle.fill", 10, t.SysOrange));
                var first = V.T(_errors.Count + " Error(s) — " + _errors[0].Split('\n')[0], 10.5, FontWeights.Medium, t.Primary); first.TextTrimming = TextTrimming.CharacterEllipsis;
                row.Children.Add(V.Shrink(first));
                row.Children.Add(V.Sp());
                var fix = V.Button(V.Box(V.H(3, Sym.Icon("wand.and.stars", 9, Brushes.White), V.T("Fix in Agent", 10, FontWeights.SemiBold, Brushes.White)), V.P(7, 3), t.Accent, 4), () =>
                    SendToAgent("The web preview at " + _current + " reports these runtime errors. Find the cause in the workspace and fix it:\n\n" + string.Join("\n", _errors.Take(20).Select(e => "- " + e))));
                fix.ToolTip = "Send all console errors, stack traces, and broken asset URLs to AI Agent to fix";
                row.Children.Add(fix);
                row.Children.Add(PanelUI.Small("xmark", null, () => { _errors.Clear(); RenderBanner(); }));
            }
            else
            {
                row.Children.Add(Sym.Icon("info.circle", 10, t.Secondary));
                var msg = V.T(_status, 10.5, FontWeights.Normal, t.Secondary); msg.TextTrimming = TextTrimming.CharacterEllipsis;
                row.Children.Add(V.Shrink(msg));
            }
            _banner.Child = V.Box(row, V.P(10, 5), _errors.Count > 0 ? (Brush)new SolidColorBrush(Color.FromArgb(28, 255, 159, 10)) : t.P(0.03), 0);
        }

        void RenderCanvas()
        {
            var t = Theme.Current;
            if (!WebView2Runtime.Available)
            {
                _canvas.Child = PanelUI.Empty("exclamationmark.triangle", "Microsoft Edge WebView2 Runtime is missing", "The WebApp preview renders pages with WebView2, which ships with Windows 11. Install it from Microsoft (Evergreen Runtime), or open the page in your browser from the ⋯ menu.");
                return;
            }
            if (_web == null || _current == null)
            {
                var col = V.Vs(10, Sym.Icon("globe", 26, t.S(0.5)), V.T("WebApp Preview", 13, FontWeights.SemiBold, t.Primary));
                var tip = V.Wrap(V.T(_status ?? "Start your dev server or open an HTML file — localhost servers are detected automatically.", 11, FontWeights.Normal, t.Secondary), TextAlignment.Center);
                tip.MaxWidth = 320;
                col.Children.Add(tip);
                var actions = V.H(8);
                string cmd = DevServer.DetectCommand(_app.WorkspaceFolder);
                actions.Children.Add(V.Button(V.Box(V.H(4, Sym.Icon("play.fill", 9.5, Brushes.White), V.T(cmd != null ? "Run " + cmd : "Build & Preview", 11, FontWeights.SemiBold, Brushes.White)), V.P(10, 6), t.Accent, 6), BuildAndPreview));
                string index = WorkspaceIndex();
                if (index != null) actions.Children.Add(PanelUI.Small("doc.richtext", "Preview index.html", () => Navigate(new Uri(index).AbsoluteUri)));
                col.Children.Add(actions);
                _ports = LocalPorts.Listening();
                if (_ports.Count > 0)
                {
                    var chips = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Center, MaxWidth = 340 };
                    foreach (var p in _ports.Take(8))
                    {
                        var pp = p;
                        var c = V.Button(V.Box(V.H(4, Sym.Icon("globe", 9, t.Secondary), V.Mono(":" + p.Port, 10, FontWeights.SemiBold, t.Primary), V.T(p.Process, 10, FontWeights.Normal, t.Secondary)), V.P(7, 3), t.P(0.06), 5), () => Navigate("http://localhost:" + pp.Port + "/"));
                        c.Margin = new Thickness(3);
                        chips.Children.Add(c);
                    }
                    col.Children.Add(chips);
                }
                col.Margin = new Thickness(16, 40, 16, 20);
                _canvas.Child = new ScrollViewer { Content = col, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
                return;
            }
            _frame.Viewport = _viewport;
            _frame.Landscape = _landscape;
            _frame.ShowBezel = _bezel;
            _frame.ActualSize = _actual;
            _frame.ResponsiveWidth = _viewport.IsResponsive ? _respW : 0;
            _frame.InvalidateArrange(); _frame.InvalidateVisual();
            if (_frame.Parent is Decorator && _frame.Parent != _canvas) ((Decorator)_frame.Parent).Child = null;
            if (_canvas.Child != _frame) _canvas.Child = _frame;
            _canvas.Background = _viewport.IsResponsive && _respW <= 0 ? t.EditorBackground : t.P(0.03);
            ApplyShapeAndEmulationSoon();
        }

        void RenderSizeLabel()
        {
            var t = Theme.Current;
            if (_frame == null || _current == null || (_viewport.IsResponsive && _respW <= 0)) { _sizeLabel.Child = null; return; }
            string text = _viewport.IsResponsive ? "↔ " + (int)_respW + " px • Responsive" : "↔ " + (int)_frame.ScreenCssW + " × " + (int)_frame.ScreenCssH + " px • " + _viewport.Subtitle.Split('•')[0].Trim() + (_frame.Scale < 0.995 ? " • " + Math.Round(_frame.Scale * 100) + "%" : "");
            var row = V.H(6, V.Mono(text, 10, FontWeights.Medium, t.Secondary));
            var reset = PanelUI.Small("arrow.counterclockwise", null, () => SetViewport(WebViewport.Responsive));
            reset.ToolTip = "Reset to Fluid Full Width";
            if (_viewport.IsResponsive) reset = PanelUI.Small("arrow.counterclockwise", null, () => { _respW = 0; Defaults.Set("webPreviewWidth", 0.0); RenderCanvas(); RenderBar(); RenderSizeLabel(); });
            row.Children.Add(reset);
            row.HorizontalAlignment = HorizontalAlignment.Center;
            _sizeLabel.Child = V.Box(row, V.P(8, 3, 8, 6), null, 0);
        }

        void ToggleInspect()
        {
            if (_web == null || !_web.IsReady || _current == null) return;
            _inspecting = !_inspecting;
            _web.ExecuteScript(InspectJs, null);
            RenderBar(); RenderInspect();
        }

        TextBox _instruction;
        void RenderInspect()
        {
            var t = Theme.Current;
            if (_picks.Count == 0 && !_inspecting) { _inspect.Child = null; return; }
            var col = V.VLead(6); col.Align = Cross.Stretch;
            var head = V.H(6, Sym.Icon("viewfinder", 10, t.Primary, FontWeights.SemiBold), V.T("INSPECT SELECTION", 9.5, FontWeights.Bold, t.Primary),
                V.Box(V.T(_picks.Count + " POINT" + (_picks.Count == 1 ? "" : "S"), 9, FontWeights.Bold, t.Secondary), V.P(5, 1), t.P(0.08), 4), V.Sp());
            if (_picks.Count > 0) head.Children.Add(PanelUI.Small(null, "Clear All", () => { _picks.Clear(); RenderInspect(); RenderBar(); }));
            head.Children.Add(PanelUI.Small("xmark", null, () => { if (_inspecting) ToggleInspect(); _picks.Clear(); RenderInspect(); RenderBar(); }));
            col.Children.Add(V.Self(head, Cross.Stretch));
            if (_picks.Count == 0) col.Children.Add(V.T(_inspecting ? "Click elements on the page — each click adds a point." : "Inspect is off.", 10.5, FontWeights.Normal, t.Secondary));
            for (int i = 0; i < _picks.Count && i < 12; i++)
            {
                var p = _picks[i]; int idx = i;
                string text = Convert.ToString(p.ContainsKey("text") ? p["text"] : "");
                var line = V.H(5, V.Mono("#" + (i + 1), 9.5, FontWeights.Bold, t.Primary), V.Shrink(V.Mono(Convert.ToString(p["selector"]), 10, FontWeights.Normal, t.P(0.9))));
                if (text.Length > 0) { var tx = V.T("· " + text, 10, FontWeights.Normal, t.Secondary); tx.TextTrimming = TextTrimming.CharacterEllipsis; line.Children.Add(V.Shrink(tx)); }
                line.Children.Add(V.Sp());
                line.Children.Add(PanelUI.Small("xmark", null, () => { _picks.RemoveAt(idx); RenderInspect(); RenderBar(); }));
                col.Children.Add(V.Self(line, Cross.Stretch));
            }
            if (_picks.Count > 0)
            {
                TextBox box;
                var field = Styles.Field("Describe what to change for the selected element(s)…", 11, t.Primary, t.S(0.6), out box);
                _instruction = box;
                Action send = () =>
                {
                    var sb = new StringBuilder("In the web preview (" + _current + "), change these elements:\n");
                    for (int i = 0; i < _picks.Count; i++)
                    {
                        var p = _picks[i];
                        sb.Append("#").Append(i + 1).Append(" `").Append(p["selector"]).Append("`");
                        string tx = Convert.ToString(p.ContainsKey("text") ? p["text"] : "");
                        if (tx.Length > 0) sb.Append(" — \"").Append(tx.Replace("\n", " ")).Append("\"");
                        sb.Append("\n   ").Append(Convert.ToString(p.ContainsKey("html") ? p["html"] : "").Replace("\n", " ")).Append("\n");
                    }
                    sb.Append("\nInstruction: ").Append(string.IsNullOrWhiteSpace(box.Text) ? "Improve these elements." : box.Text.Trim());
                    _picks.Clear(); if (_inspecting) ToggleInspect();
                    RenderInspect(); RenderBar();
                    SendToAgent(sb.ToString());
                };
                box.KeyDown += (s, e) => { if (e.Key == Key.Enter) { send(); e.Handled = true; } };
                var sendBtn = V.Button(V.Box(V.H(4, Sym.Icon("arrow.up.circle.fill", 9.5, Brushes.White), V.T("Send (" + _picks.Count + ")", 10, FontWeights.SemiBold, Brushes.White)), V.P(8, 5), t.Accent, 4), send);
                sendBtn.ToolTip = "Send all selected points to AI Agent and edit code immediately";
                col.Children.Add(V.Self(V.H(6, V.Flex(V.Box(field, V.P(7, 4), t.P(0.06), 4)), sendBtn), Cross.Stretch));
            }
            _inspect.Child = V.Box(col, V.P(10, 8), t.PanelBackground, 0);
            _inspect.BorderBrush = t.Separator; _inspect.BorderThickness = new Thickness(0, 1, 0, 0);
        }

        /// <summary>Shows a URL or local HTML/SVG file in the Preview dock's WebApp tab (Cell Mode HTML / Plotly outputs).</summary>
        public static void OpenInDock(string urlOrPath)
        {
            PreviewDock.SelectStandard("web");
            Shared.Open(urlOrPath, null);
        }

        /// <summary>Opens a URL or file from elsewhere (header menu, Live Preview of an HTML file).</summary>
        public void Open(string urlOrPath, string viewportId)
        {
            if (viewportId != null) SetViewport(WebViewport.Find(viewportId));
            if (urlOrPath != null) Navigate(urlOrPath);
        }

        public string CurrentUrl { get { return _current; } }
        public bool HasPage { get { return _current != null; } }

        /// <summary>For tests and snapshots: a PNG of the page as rendered.</summary>
        public void Capture(Action<byte[]> done) { if (_web == null) done(null); else _web.CapturePng(done); }
        public void Eval(string js, Action<string> done) { if (_web == null) done(null); else _web.ExecuteScript(js, done); }

        /// <summary>For snapshots: once the page has loaded, its PNG, where the browser sits inside <paramref name="root"/>,
        /// and what the live page reports (viewport, user agent, touch points, layout text). Waits up to 15 s for loading.</summary>
        public void SnapshotLayer(FrameworkElement root, Action<byte[], Rect, string> done)
        {
            var started = DateTime.Now;
            var poll = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
            poll.Tick += delegate
            {
                if ((_web == null || !_web.IsReady || _loading) && (DateTime.Now - started).TotalSeconds < 15) return;
                poll.Stop();
                if (_web == null || !_web.IsReady) { done(null, Rect.Empty, null); return; }
                var rect = Rect.Empty;
                try { rect = _web.TransformToAncestor(root).TransformBounds(new Rect(0, 0, _web.ActualWidth, _web.ActualHeight)); }
                catch (InvalidOperationException ex) { System.Diagnostics.Debug.WriteLine("snapshot layer: " + ex.Message); }
                _web.ExecuteScript("JSON.stringify({url:location.href,title:document.title,innerWidth:innerWidth,innerHeight:innerHeight,devicePixelRatio:devicePixelRatio,maxTouchPoints:navigator.maxTouchPoints,userAgent:navigator.userAgent,layout:(document.getElementById('layout')||{}).textContent||null,hooks:!!window.__mcHooks,errorsShown:" + _errors.Count + "})", info =>
                {
                    string text = info;
                    try { text = new JavaScriptSerializer().Deserialize<string>(info); } catch (ArgumentException) { } catch (InvalidOperationException) { }
                    _web.CapturePng(png => done(png, rect, text));
                });
            };
            poll.Start();
        }
    }
}
