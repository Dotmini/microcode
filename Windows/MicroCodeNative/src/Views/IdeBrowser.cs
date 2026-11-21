// Port of IDEBrowserView.swift (More Mode → Web Browser): tabs, ‹ › ↻/✕, URL bar with lock/globe, bookmarks, history,
// the multi-point visual element picker ("Click-to-Prompt") that sends selected elements to the AI Agent, and Developer Tools
// (Console + JS REPL, Network fetch/XHR, DOM Source). Runs on Edge WebView2 (WebView2Host) with the Mac's telemetry script.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public class BrowserTabInfo { public string Id = Guid.NewGuid().ToString(), Url = "", Title = ""; public bool IsLoading, CanGoBack, CanGoForward; }
    public class BrowserHistoryItem { public string Url = "", Title = ""; public DateTime VisitedAt = DateTime.Now; }
    public class BrowserBookmarkItem { public string Id = Guid.NewGuid().ToString(), Url = "", Title = ""; }
    public class BrowserConsoleItem { public string Level = "log", Message = "", Source = "webview"; public DateTime Timestamp = DateTime.Now; }
    public class BrowserNetworkItem { public string Method = "GET", Url = ""; public int Status, DurationMs; public DateTime Timestamp = DateTime.Now; }
    public class BrowserPicked { public string Id = Guid.NewGuid().ToString(), Selector = "", Tag = "", Text = "", OuterHtml = "", Styles = "", Rect = "", Note = ""; }

    /// <summary>The browser half of AppState (browserTabs / History / Bookmarks) and IDEBrowserAutomationService
    /// (console / network logs, picked elements). Kept for the app session like the Mac's in-memory state.</summary>
    public class BrowserSession
    {
        public static readonly BrowserSession Shared = new BrowserSession();
        public const string HomeUrl = "https://www.google.com";
        const int MaxHistory = 200, MaxLogs = 300, MaxPicks = 20;

        public readonly List<BrowserTabInfo> Tabs = new List<BrowserTabInfo> { new BrowserTabInfo { Url = HomeUrl, Title = "New Tab" } };
        public int Active;
        public readonly List<BrowserHistoryItem> History = new List<BrowserHistoryItem>();
        public readonly List<BrowserBookmarkItem> Bookmarks = new List<BrowserBookmarkItem>();
        public readonly List<BrowserConsoleItem> Console = new List<BrowserConsoleItem>();
        public readonly List<BrowserNetworkItem> Network = new List<BrowserNetworkItem>();
        public readonly List<BrowserPicked> Picked = new List<BrowserPicked>();
        public bool InspectMode;

        public BrowserTabInfo Current { get { return Active >= 0 && Active < Tabs.Count ? Tabs[Active] : null; } }
        public string CurrentUrl { get { var c = Current; return c != null ? c.Url : HomeUrl; } }

        /// <summary>navigateTo: a URL as typed, a bare host gets https://, anything else becomes a Google search.
        /// localhost / 127.0.0.1 addresses open over http (the Mac sends "localhost:5173" to Google search).</summary>
        public static string Normalize(string input)
        {
            string s = (input ?? "").Trim();
            if (s.Length == 0) return null;
            if (s.Contains("://") || s.StartsWith("about:", StringComparison.OrdinalIgnoreCase)) return s;
            if (Regex.IsMatch(s, @"^(localhost|127\.0\.0\.1|\[::1\])(:\d{1,5})?(/.*)?$", RegexOptions.IgnoreCase)) return "http://" + s;
            if (s.Contains(".") && !s.Contains(" ")) return "https://" + s;
            return "https://www.google.com/search?q=" + Uri.EscapeDataString(s);
        }

        public BrowserTabInfo AddTab()
        {
            var tab = new BrowserTabInfo { Url = HomeUrl, Title = "New Tab" };
            Tabs.Add(tab);
            Active = Tabs.Count - 1;
            return tab;
        }

        /// <summary>closeTab: the last tab stays; the active index is clamped to the remaining tabs.</summary>
        public bool CloseTab(string id)
        {
            if (Tabs.Count <= 1) return false;
            int i = Tabs.FindIndex(x => x.Id == id);
            if (i < 0) return false;
            Tabs.RemoveAt(i);
            if (Active >= Tabs.Count) Active = Math.Max(0, Tabs.Count - 1);
            return true;
        }

        public bool SwitchTab(string id)
        {
            int i = Tabs.FindIndex(x => x.Id == id);
            if (i < 0) return false;
            Active = i;
            return true;
        }

        public void RecordVisit(string url, string title)
        {
            if (string.IsNullOrEmpty(url)) return;
            History.Insert(0, new BrowserHistoryItem { Url = url, Title = title ?? "" });
            if (History.Count > MaxHistory) History.RemoveRange(MaxHistory, History.Count - MaxHistory);
        }

        public bool IsBookmarked(string url) { return Bookmarks.Any(b => b.Url == url); }

        /// <summary>The star button: adds the page, or removes it when it is already bookmarked. Returns the new state.</summary>
        public bool ToggleBookmark(string url, string title)
        {
            if (IsBookmarked(url)) { Bookmarks.RemoveAll(b => b.Url == url); return false; }
            Bookmarks.Add(new BrowserBookmarkItem { Url = url, Title = title ?? "" });
            return true;
        }

        static string S(Dictionary<string, object> m, string k) { object v; return m.TryGetValue(k, out v) && v != null ? Convert.ToString(v, CultureInfo.InvariantCulture) : null; }
        static int I(Dictionary<string, object> m, string k) { object v; if (!m.TryGetValue(k, out v) || v == null) return 0; try { return (int)Math.Round(Convert.ToDouble(v, CultureInfo.InvariantCulture)); } catch (FormatException) { return 0; } catch (InvalidCastException) { return 0; } catch (OverflowException) { return 0; } }

        /// <summary>userContentController(didReceive:): console / network / element_picked / element_unpicked messages
        /// posted by the telemetry script. Returns the message type it applied (null when the message is not one of them).</summary>
        public string Handle(string json)
        {
            Dictionary<string, object> m;
            try { m = new JavaScriptSerializer().DeserializeObject(json ?? "") as Dictionary<string, object>; }
            catch (ArgumentException) { return null; }
            catch (InvalidOperationException) { return null; }
            if (m == null) return null;
            string type = S(m, "_type");
            switch (type)
            {
                case "console":
                    Console.Add(new BrowserConsoleItem { Level = S(m, "level") ?? "log", Message = S(m, "message") ?? "" });
                    if (Console.Count > MaxLogs) Console.RemoveRange(0, Console.Count - MaxLogs);
                    return type;
                case "network":
                    Network.Add(new BrowserNetworkItem { Method = S(m, "method") ?? "GET", Url = S(m, "url") ?? "", Status = I(m, "status"), DurationMs = I(m, "durationMs") });
                    if (Network.Count > MaxLogs) Network.RemoveRange(0, Network.Count - MaxLogs);
                    return type;
                case "element_picked":
                {
                    var el = new BrowserPicked { Selector = S(m, "selector") ?? "", Tag = S(m, "tag") ?? "", Text = S(m, "text") ?? "", OuterHtml = S(m, "outerHTML") ?? "", Styles = S(m, "styles") ?? "", Rect = S(m, "rect") ?? "" };
                    int existing = Picked.FindIndex(p => p.Selector == el.Selector);
                    if (existing >= 0) { el.Id = Picked[existing].Id; el.Note = Picked[existing].Note; Picked[existing] = el; }
                    else
                    {
                        Picked.Add(el);
                        if (Picked.Count > MaxPicks) Picked.RemoveRange(0, Picked.Count - MaxPicks);
                    }
                    return type;
                }
                case "element_unpicked":
                {
                    string sel = S(m, "selector") ?? "";
                    Picked.RemoveAll(p => p.Selector == sel);
                    return type;
                }
                default: return null;
            }
        }

        /// <summary>sendPickedElementsToAgent: the prompt the Mac inserts into the Agent for one or several picked elements.</summary>
        public static string AgentPrompt(List<BrowserPicked> targets, string pageUrl, string instruction)
        {
            if (targets == null || targets.Count == 0) return null;
            string url = pageUrl ?? "http://localhost:3000";
            string ins = (instruction ?? "").Trim();
            bool perNotes = targets.Any(x => x.Note.Trim().Length > 0);
            var sb = new StringBuilder();
            if (targets.Count == 1)
            {
                var el = targets[0];
                sb.Append("[Inspect Element Target]\n- Page URL: ").Append(url).Append("\n- Selector: `").Append(el.Selector).Append("` (`<").Append(el.Tag).Append(">` at ").Append(el.Rect).Append(")");
                if (el.Text.Trim().Length > 0) sb.Append("\n- Element / Selected Text: `").Append(el.Text).Append("`");
                sb.Append("\n- Computed Styles: `").Append(el.Styles).Append("`\n- HTML Snippet:\n```html\n").Append(el.OuterHtml).Append("\n```");
                string note = string.Join(" — ", new[] { el.Note.Trim(), ins }.Where(x => x.Length > 0));
                if (note.Length > 0) sb.Append("\n\nInstruction: ").Append(note);
                return sb.ToString();
            }
            sb.Append("[Multi-Point Inspect Targets (").Append(targets.Count).Append(" Elements Selected)]\n- Page URL: ").Append(url);
            for (int i = 0; i < targets.Count; i++)
            {
                var el = targets[i]; int n = i + 1;
                sb.Append("\n\n### Target #").Append(n).Append(": `").Append(el.Selector).Append("` (`<").Append(el.Tag).Append(">` at ").Append(el.Rect).Append(")");
                if (el.Note.Trim().Length > 0) sb.Append("\n- **Specific Edit for #").Append(n).Append("**: ").Append(el.Note.Trim());
                if (el.Text.Trim().Length > 0) sb.Append("\n- Text Content: `").Append(el.Text).Append("`");
                sb.Append("\n- Computed Styles: `").Append(el.Styles).Append("`");
                sb.Append("\n- HTML Snippet:\n```html\n").Append(el.OuterHtml).Append("\n```");
            }
            if (ins.Length > 0) sb.Append("\n\n### Overall Instruction for Selected Targets:\n").Append(ins);
            else if (!perNotes) sb.Append("\n\n### Overall Instruction for Selected Targets:\nปรับปรุงและแก้ไของค์ประกอบทั้ง ").Append(targets.Count).Append(" จุดที่เลือกให้สมบูรณ์และสอดคล้องกัน");
            return sb.ToString();
        }

        /// <summary>evalJS result text: strings as they are, objects/arrays as pretty JSON, undefined as "null".</summary>
        public static string FormatEvalResult(string executeScriptJson)
        {
            if (executeScriptJson == null) return "Error evaluating JS";
            object o;
            try { o = new JavaScriptSerializer().DeserializeObject(executeScriptJson); }
            catch (ArgumentException) { return executeScriptJson; }
            catch (InvalidOperationException) { return executeScriptJson; }
            var m = o as Dictionary<string, object>;
            if (m == null || !m.ContainsKey("ok")) return executeScriptJson;
            if (!(m["ok"] is bool) || !(bool)m["ok"]) return "Error evaluating JS";
            object v;
            if (!m.TryGetValue("v", out v) || v == null) return "null";
            if (v is string) return (string)v;
            if (v is bool) return (bool)v ? "true" : "false";
            if (v is Dictionary<string, object> || v is object[] || v is System.Collections.ArrayList)
            {
                string raw = new JavaScriptSerializer().Serialize(v);
                return ApiService.PrettyJson(raw) ?? raw;
            }
            return Convert.ToString(v, CultureInfo.InvariantCulture);
        }

        /// <summary>The script the REPL runs: global-scope eval, the value wrapped so a thrown error is told apart from null.</summary>
        public static string EvalWrapper(string script)
        {
            return "(function(){try{var r=(0,eval)(" + new JavaScriptSerializer().Serialize(script) + ");return {ok:true,v:(r===undefined?null:r)};}catch(e){return {ok:false};}})()";
        }

        // IDEBrowserAutomationService.telemetryScriptSource with WKScriptMessageHandler swapped for chrome.webview.postMessage,
        // plus the Mac browser's navigator shims (webdriver / languages / plugins).
        public const string TelemetryJs = @"(function(){try{Object.defineProperty(navigator,'webdriver',{get:function(){return false;}});
Object.defineProperty(navigator,'languages',{get:function(){return ['en-US','en','th'];}});
Object.defineProperty(navigator,'plugins',{get:function(){return [1,2,3];}});}catch(e){}})();
(function() {
    if (window.__mcTelemetryInstalled) return;
    window.__mcTelemetryInstalled = true;
    function send(type, payload) {
        try {
            if (window.chrome && window.chrome.webview) window.chrome.webview.postMessage(Object.assign({ _type: type }, payload));
        } catch (e) {}
    }
    ['log', 'info', 'warn', 'error'].forEach(function(level) {
        var orig = console[level];
        console[level] = function() {
            var args = Array.prototype.slice.call(arguments).map(function(a) {
                try { return typeof a === 'object' ? JSON.stringify(a) : String(a); }
                catch (e) { return String(a); }
            }).join(' ');
            send('console', { level: level, message: args });
            if (orig) orig.apply(console, arguments);
        };
    });
    window.addEventListener('error', function(e) {
        if (e && e.target && e.target !== window && e.target.tagName) {
            var tag = String(e.target.tagName).toLowerCase();
            var url = e.target.src || e.target.href || '';
            if (url) send('console', { level: 'error', message: 'BrokenAsset (<' + tag + '>): Failed to load ' + url });
            return;
        }
        send('console', { level: 'error', message: 'UncaughtError: ' + (e.message || '') + ' at ' + (e.filename || '') + ':' + (e.lineno || 0) });
    }, true);
    window.addEventListener('unhandledrejection', function(e) {
        send('console', { level: 'error', message: 'UnhandledRejection: ' + String(e.reason || '') });
    });
    if (window.fetch) {
        var origFetch = window.fetch;
        window.fetch = function(input, init) {
            var url = typeof input === 'string' ? input : (input && input.url ? input.url : String(input));
            var method = (init && init.method) ? init.method : 'GET';
            var t0 = Date.now();
            return origFetch.apply(this, arguments).then(function(resp) {
                send('network', { method: method.toUpperCase(), url: url, status: resp.status, durationMs: Date.now() - t0 });
                return resp;
            }).catch(function(err) {
                send('network', { method: method.toUpperCase(), url: url, status: 0, durationMs: Date.now() - t0 });
                throw err;
            });
        };
    }
    if (window.XMLHttpRequest) {
        var origOpen = XMLHttpRequest.prototype.open;
        var origSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function(method, url) {
            this.__mcMethod = method ? String(method).toUpperCase() : 'GET';
            this.__mcUrl = String(url || '');
            return origOpen.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function() {
            var xhr = this;
            var t0 = Date.now();
            xhr.addEventListener('loadend', function() {
                send('network', { method: xhr.__mcMethod || 'GET', url: xhr.__mcUrl || '', status: xhr.status || 0, durationMs: Date.now() - t0 });
            });
            return origSend.apply(this, arguments);
        };
    }
    window.__mcPinnedSelectors = window.__mcPinnedSelectors || [];
    function ensureInspectorDOM() {
        if (!document.body) return null;
        var overlay = document.getElementById('__mc_inspect_overlay');
        var label = document.getElementById('__mc_inspect_label');
        var dragBox = document.getElementById('__mc_drag_box');
        var pinnedRoot = document.getElementById('__mc_pinned_container');
        if (!overlay) {
            overlay = document.createElement('div');
            overlay.id = '__mc_inspect_overlay';
            overlay.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483645;border:1.5px dashed rgba(255,255,255,0.88);background:rgba(255,255,255,0.06);border-radius:4px;box-shadow:0 0 0 1px rgba(0,0,0,0.65),0 4px 14px rgba(0,0,0,0.28);transition:all 0.04s ease;display:none;';
            document.body.appendChild(overlay);
        }
        if (!label) {
            label = document.createElement('div');
            label.id = '__mc_inspect_label';
            label.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483646;background:#18181B;color:#FAFAFA;font:600 10.5px -apple-system,BlinkMacSystemFont,""Segoe UI"",monospace;padding:3px 7px;border-radius:4px;border:1px solid rgba(255,255,255,0.24);box-shadow:0 4px 12px rgba(0,0,0,0.5);display:none;white-space:nowrap;';
            document.body.appendChild(label);
        }
        if (!dragBox) {
            dragBox = document.createElement('div');
            dragBox.id = '__mc_drag_box';
            dragBox.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483647;border:1.5px dashed rgba(255,255,255,0.85);background:rgba(255,255,255,0.08);box-shadow:0 0 0 1px rgba(0,0,0,0.5);border-radius:4px;display:none;';
            document.body.appendChild(dragBox);
        }
        if (!pinnedRoot) {
            pinnedRoot = document.createElement('div');
            pinnedRoot.id = '__mc_pinned_container';
            pinnedRoot.style.cssText = 'position:fixed;left:0;top:0;width:0;height:0;pointer-events:none;z-index:2147483644;';
            document.body.appendChild(pinnedRoot);
        }
        return { overlay: overlay, label: label, dragBox: dragBox, pinnedRoot: pinnedRoot };
    }
    function isInternalInspectorNode(el) {
        if (!el) return true;
        var cur = el;
        while (cur) {
            var id = cur.id || '';
            if (id === '__mc_inspect_overlay' || id === '__mc_inspect_label' || id === '__mc_drag_box' || id === '__mc_pinned_container') return true;
            cur = cur.parentElement;
        }
        return false;
    }
    function buildSelectorForElement(el) {
        if (!el || !el.tagName) return 'body';
        var parts = [];
        var cur = el;
        var depth = 0;
        while (cur && cur.tagName && depth < 4) {
            var tag = cur.tagName.toLowerCase();
            var idPart = cur.id ? ('#' + cur.id) : '';
            var clsPart = '';
            if (!idPart && cur.className && typeof cur.className === 'string') {
                var classes = cur.className.trim().split(/\s+/).filter(Boolean).slice(0, 2);
                if (classes.length > 0) clsPart = '.' + classes.join('.');
            }
            var nthPart = '';
            if (!idPart && cur.parentElement) {
                var siblings = Array.prototype.filter.call(cur.parentElement.children, function(c) { return c.tagName === cur.tagName; });
                if (siblings.length > 1) {
                    var idx = siblings.indexOf(cur) + 1;
                    if (idx > 0) nthPart = ':nth-of-type(' + idx + ')';
                }
            }
            parts.unshift(tag + idPart + clsPart + nthPart);
            if (idPart || tag === 'body' || tag === 'html') break;
            cur = cur.parentElement;
            depth++;
        }
        return parts.join(' > ');
    }
    window.__mcRenderPinnedOverlays = function() {
        var ui = ensureInspectorDOM();
        if (!ui || !ui.pinnedRoot) return;
        ui.pinnedRoot.innerHTML = '';
        var list = window.__mcPinnedSelectors || [];
        list.forEach(function(sel, idx) {
            var target = null;
            try { target = document.querySelector(sel); } catch (e) {}
            if (!target || !target.getBoundingClientRect) return;
            var r = target.getBoundingClientRect();
            if (r.width <= 0 && r.height <= 0) return;
            var box = document.createElement('div');
            box.style.cssText = 'position:fixed;pointer-events:none;border:1.5px solid #FAFAFA;background:rgba(24,24,27,0.12);box-shadow:0 0 0 1px rgba(0,0,0,0.75),0 2px 8px rgba(0,0,0,0.3);border-radius:4px;';
            box.style.left = r.left + 'px';
            box.style.top = r.top + 'px';
            box.style.width = Math.max(4, r.width) + 'px';
            box.style.height = Math.max(4, r.height) + 'px';
            var badge = document.createElement('div');
            badge.style.cssText = 'position:fixed;pointer-events:none;background:#18181B;color:#FAFAFA;font:700 10px -apple-system,BlinkMacSystemFont,""Segoe UI"",monospace;padding:2px 6px;border-radius:3px;border:1px solid rgba(255,255,255,0.32);box-shadow:0 2px 6px rgba(0,0,0,0.45);white-space:nowrap;';
            var tag = target.tagName ? target.tagName.toLowerCase() : 'el';
            var shortCls = (target.className && typeof target.className === 'string' && target.className.trim()) ? ('.' + target.className.trim().split(/\s+/)[0]) : (target.id ? ('#' + target.id) : '');
            badge.textContent = '#' + (idx + 1) + ' ' + tag + shortCls;
            badge.style.left = Math.max(4, Math.min(window.innerWidth - 140, r.left)) + 'px';
            badge.style.top = (r.top > 22 ? (r.top - 20) : (r.top + 4)) + 'px';
            ui.pinnedRoot.appendChild(box);
            ui.pinnedRoot.appendChild(badge);
        });
    };
    window.__mcSyncPinnedSelectors = function(selectorsArray) {
        window.__mcPinnedSelectors = Array.isArray(selectorsArray) ? selectorsArray : [];
        window.__mcRenderPinnedOverlays();
    };
    window.addEventListener('scroll', function() { if (window.__mcPinnedSelectors && window.__mcPinnedSelectors.length > 0) window.__mcRenderPinnedOverlays(); }, true);
    window.addEventListener('resize', function() { if (window.__mcPinnedSelectors && window.__mcPinnedSelectors.length > 0) window.__mcRenderPinnedOverlays(); }, true);
    function highlightElementOnPage(el, badgeSuffix) {
        var ui = ensureInspectorDOM();
        if (!ui || !el || !el.getBoundingClientRect) return;
        var r = el.getBoundingClientRect();
        ui.overlay.style.display = 'block';
        ui.overlay.style.left = r.left + 'px';
        ui.overlay.style.top = r.top + 'px';
        ui.overlay.style.width = Math.max(4, r.width) + 'px';
        ui.overlay.style.height = Math.max(4, r.height) + 'px';
        var idPart = el.id ? ('#' + el.id) : '';
        var clsPart = (el.className && typeof el.className === 'string' && el.className.trim()) ? ('.' + el.className.trim().split(/\s+/).slice(0,2).join('.')) : '';
        ui.label.textContent = el.tagName.toLowerCase() + idPart + clsPart + ' (' + Math.round(r.width) + '×' + Math.round(r.height) + ')' + (badgeSuffix ? ' · ' + badgeSuffix : '');
        ui.label.style.display = 'block';
        ui.label.style.left = Math.max(6, Math.min(window.innerWidth - 220, r.left)) + 'px';
        ui.label.style.top = (r.top > 30 ? (r.top - 26) : (r.bottom + 6)) + 'px';
    }
    function pickAndSendElement(el, selectedText, modeLabel, allowToggle) {
        if (!el || isInternalInspectorNode(el)) return;
        if (el.nodeType === 3) el = el.parentElement;
        if (!el || !el.tagName) return;
        var selector = buildSelectorForElement(el);
        var existingIdx = (window.__mcPinnedSelectors || []).indexOf(selector);
        if (allowToggle && existingIdx !== -1) {
            window.__mcPinnedSelectors.splice(existingIdx, 1);
            window.__mcRenderPinnedOverlays();
            send('element_unpicked', { selector: selector });
            return;
        }
        if (existingIdx === -1) window.__mcPinnedSelectors.push(selector);
        window.__mcRenderPinnedOverlays();
        highlightElementOnPage(el, '#' + window.__mcPinnedSelectors.length + ' Selected');
        var r = el.getBoundingClientRect();
        var cs = window.getComputedStyle(el);
        var stylesSummary = 'display:' + cs.display + '; color:' + cs.color + '; bg:' + cs.backgroundColor + '; font:' + cs.fontSize + ' ' + cs.fontFamily + '; padding:' + cs.padding;
        var rawText = (selectedText && selectedText.length > 0) ? ('[Selected: ""' + selectedText.slice(0, 240) + '""]') : ((el.innerText || el.value || '').trim().slice(0, 240));
        send('element_picked', {
            selector: selector, tag: el.tagName.toLowerCase(), text: rawText, outerHTML: (el.outerHTML || '').slice(0, 700), styles: stylesSummary,
            rect: Math.round(r.left) + ',' + Math.round(r.top) + ' (' + Math.round(r.width) + 'x' + Math.round(r.height) + ')',
            boundsX: r.left, boundsY: r.top, boundsWidth: r.width, boundsHeight: r.height,
            viewportWidth: window.innerWidth || document.documentElement.clientWidth || 800,
            viewportHeight: window.innerHeight || document.documentElement.clientHeight || 600
        });
    }
    window.__mcClearInspectorHighlight = function() {
        var ui = ensureInspectorDOM();
        if (!ui) return;
        ui.overlay.style.display = 'none';
        ui.label.style.display = 'none';
        ui.dragBox.style.display = 'none';
        window.__mcPinnedSelectors = [];
        if (ui.pinnedRoot) ui.pinnedRoot.innerHTML = '';
    };
    window.__mcHideHoverHighlightOnly = function() {
        var ui = ensureInspectorDOM();
        if (!ui) return;
        ui.overlay.style.display = 'none';
        ui.label.style.display = 'none';
        ui.dragBox.style.display = 'none';
    };
    window.addEventListener('contextmenu', function(e) {
        var el = document.elementFromPoint(e.clientX, e.clientY) || e.target;
        if (!el || isInternalInspectorNode(el)) return;
        e.preventDefault();
        e.stopPropagation();
        var sel = (window.getSelection && window.getSelection().toString() || '').trim();
        pickAndSendElement(el, sel, 'Right-Click Inspect', false);
    }, true);
    window.addEventListener('mousemove', function(e) {
        if (window.__mcInspectActive) {
            var el = document.elementFromPoint(e.clientX, e.clientY);
            if (!el || isInternalInspectorNode(el)) return;
            var sel = buildSelectorForElement(el);
            var idx = (window.__mcPinnedSelectors || []).indexOf(sel);
            highlightElementOnPage(el, idx !== -1 ? ('#' + (idx + 1) + ' (Click to Remove)') : 'Click to Add Point');
        }
    }, true);
    window.addEventListener('click', function(e) {
        if (!window.__mcInspectActive && !e.altKey) return;
        var el = document.elementFromPoint(e.clientX, e.clientY) || e.target;
        if (!el || isInternalInspectorNode(el)) return;
        e.preventDefault();
        e.stopPropagation();
        pickAndSendElement(el, '', 'Selected', true);
    }, true);
    var dragStart = null;
    var isMarqueeDragging = false;
    window.addEventListener('mousedown', function(e) {
        if (e.button !== 0) return;
        var tag = (e.target && e.target.tagName) ? e.target.tagName.toLowerCase() : '';
        if (!window.__mcInspectActive && (tag === 'input' || tag === 'textarea' || tag === 'select')) return;
        dragStart = { x: e.clientX, y: e.clientY, target: e.target };
        isMarqueeDragging = false;
    }, true);
    window.addEventListener('mousemove', function(e) {
        if (!dragStart) return;
        var dx = e.clientX - dragStart.x;
        var dy = e.clientY - dragStart.y;
        if (Math.hypot(dx, dy) > 14) {
            isMarqueeDragging = true;
            var ui = ensureInspectorDOM();
            if (ui) {
                ui.dragBox.style.display = 'block';
                ui.dragBox.style.left = Math.min(dragStart.x, e.clientX) + 'px';
                ui.dragBox.style.top = Math.min(dragStart.y, e.clientY) + 'px';
                ui.dragBox.style.width = Math.abs(dx) + 'px';
                ui.dragBox.style.height = Math.abs(dy) + 'px';
            }
        }
    }, true);
    window.addEventListener('mouseup', function(e) {
        if (!dragStart) return;
        var start = dragStart;
        var wasDragging = isMarqueeDragging;
        dragStart = null;
        isMarqueeDragging = false;
        var ui = ensureInspectorDOM();
        if (ui) ui.dragBox.style.display = 'none';
        var dx = e.clientX - start.x;
        var dy = e.clientY - start.y;
        if (!wasDragging && Math.hypot(dx, dy) < 18) return;
        var boxLeft = Math.min(start.x, e.clientX), boxRight = Math.max(start.x, e.clientX);
        var boxTop = Math.min(start.y, e.clientY), boxBottom = Math.max(start.y, e.clientY);
        if (window.__mcInspectActive || e.shiftKey) {
            var candidates = Array.from(document.querySelectorAll('button, a, input, select, textarea, h1, h2, h3, h4, p, li, img, section, article, [role=""button""]'));
            var matched = candidates.filter(function(node) {
                if (isInternalInspectorNode(node)) return false;
                var r = node.getBoundingClientRect();
                if (r.width < 8 || r.height < 8) return false;
                var cx = r.left + r.width / 2, cy = r.top + r.height / 2;
                return cx >= boxLeft && cx <= boxRight && cy >= boxTop && cy <= boxBottom;
            });
            var leafMatched = matched.filter(function(node) { return !matched.some(function(other) { return other !== node && node.contains(other); }); }).slice(0, 8);
            if (leafMatched.length > 0) { leafMatched.forEach(function(node) { pickAndSendElement(node, '', 'Marquee Selected', false); }); return; }
        }
        var selText = '', selEl = null;
        if (window.getSelection) {
            var sel = window.getSelection();
            selText = (sel ? sel.toString() : '').trim();
            if (sel && sel.rangeCount > 0) {
                var node = sel.getRangeAt(0).commonAncestorContainer;
                selEl = (node && node.nodeType === 1) ? node : (node ? node.parentElement : null);
            }
        }
        if (!selEl || selEl === document.body || selEl === document.documentElement) {
            selEl = document.elementFromPoint((start.x + e.clientX) / 2, (start.y + e.clientY) / 2) || start.target || e.target;
        }
        if (selEl && !isInternalInspectorNode(selEl)) pickAndSendElement(selEl, selText, selText ? 'Text Selection' : 'Region Selected', false);
    }, true);
})();";
    }

    /// <summary>IDEBrowserView.</summary>
    public class IdeBrowserView : Grid
    {
        public static IdeBrowserView Current;
        /// <summary>Snapshot/test hooks (--browser-url, --browser-devtools, --browser-pick, --browser-eval).</summary>
        public static string InitialUrl, InitialDevTools, InitialEval;
        public static List<string> InitialPicks = new List<string>();

        readonly AppState _app;
        readonly BrowserSession _s = BrowserSession.Shared;
        readonly Border _tabBar = new Border(), _navBar = new Border(), _picks = new Border(), _devTools = new Border(), _webHost = new Border();
        readonly Grid _content = new Grid();
        WebView2Host _web;
        TextBox _url, _repl;
        bool _showDevTools, _devDirty, _hooksRun;
        string _devTab = "console", _pageSource = "", _status;
        readonly DispatcherTimer _devPump;

        public IdeBrowserView(AppState app)
        {
            _app = app;
            Current = this;
            var t = Theme.Current;
            Background = t.EditorBackground;
            foreach (var h in new[] { GridLength.Auto, new GridLength(1), GridLength.Auto, GridLength.Auto, new GridLength(1), new GridLength(1, GridUnitType.Star) }) RowDefinitions.Add(new RowDefinition { Height = h });
            Add(_tabBar, 0); Add(V.Line(t.Separator, true), 1); Add(_navBar, 2); Add(_picks, 3); Add(V.Line(t.Separator, true), 4); Add(_content, 5);
            _content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = 200 });
            _content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0) });
            _content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0) });
            _content.Children.Add(_webHost);
            var split = new GridSplitter { Width = 1, HorizontalAlignment = HorizontalAlignment.Stretch, Background = t.Separator, ResizeBehavior = GridResizeBehavior.PreviousAndNext };
            Grid.SetColumn(split, 1); _content.Children.Add(split);
            Grid.SetColumn(_devTools, 2); _content.Children.Add(_devTools);
            if (InitialDevTools != null) { _showDevTools = true; _devTab = InitialDevTools; }
            if (InitialUrl != null) { string u = BrowserSession.Normalize(InitialUrl); if (u != null && _s.Current != null) _s.Current.Url = u; }
            _devPump = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) };
            _devPump.Tick += delegate { if (_devDirty) { _devDirty = false; RenderDevTools(); RenderNav(); } };
            _devPump.Start();
            EnsureBrowser();
            RenderAll();
        }

        void Add(UIElement e, int row) { SetRow(e, row); Children.Add(e); }

        // ── browser ──

        void EnsureBrowser()
        {
            if (_web != null) return;
            var bg = Theme.Current.EditorBackground as SolidColorBrush;
            _web = new WebView2Host(bg != null ? bg.Color : Color.FromRgb(30, 30, 30));
            _web.DocumentStartScript = BrowserSession.TelemetryJs;
            _web.TitleChanged += title => { var c = _s.Current; if (c != null) c.Title = title ?? ""; RenderTabs(); };
            _web.SourceChanged += src =>
            {
                var c = _s.Current;
                if (c != null && !string.IsNullOrEmpty(src)) c.Url = src;
                if (_url != null && !_url.IsKeyboardFocused) _url.Text = src;
                _s.RecordVisit(src, _web.Title);
                UpdateNavState(); RenderNav();
            };
            _web.NavigationStarting += () => { SetLoading(true); _status = null; };
            _web.NavigationCompleted += (ok, status) =>
            {
                SetLoading(false);
                UpdateNavState();
                _status = ok ? null : "Could not load the page (error " + status + ")";
                RenderNav();
                if (!ok) return;
                // fetch the page source for Developer Tools → DOM Source
                _web.ExecuteScript("document.documentElement.outerHTML", json => { _pageSource = DecodeString(json) ?? ""; if (_devTab == "dom") _devDirty = true; });
                // pinned picks survive a reload of the same page
                SyncPinned();
                RunInitialHooks();
            };
            _web.HistoryChanged += () => { UpdateNavState(); RenderNav(); };
            _web.WebMessageReceived += json =>
            {
                string type = _s.Handle(json);
                if (type == null) return;
                if (type == "element_picked" || type == "element_unpicked") { SyncPinned(); RenderPicks(); RenderNav(); }
                else _devDirty = true;
            };
            _web.Failed += msg => { _status = msg; RenderWeb(); };
            _web.ProcessFailed += () => { _status = "The page's browser process stopped — press Reload."; RenderNav(); };
            _web.Navigate(_s.CurrentUrl);
        }

        void SetLoading(bool loading) { var c = _s.Current; if (c != null) c.IsLoading = loading; RenderTabs(); RenderNav(); }

        void UpdateNavState()
        {
            var c = _s.Current;
            if (c == null || _web == null) return;
            c.CanGoBack = _web.CanGoBack; c.CanGoForward = _web.CanGoForward;
        }

        static string DecodeString(string json)
        {
            if (json == null) return null;
            try { return new JavaScriptSerializer().Deserialize<string>(json); }
            catch (ArgumentException) { return null; }
            catch (InvalidOperationException) { return null; }
        }

        void Navigate(string input)
        {
            string url = BrowserSession.Normalize(input);
            if (url == null) return;
            var c = _s.Current;
            if (c != null) c.Url = url;
            if (_url != null) _url.Text = url;
            EnsureBrowser();
            if (!_web.Navigate(url)) { _status = "Not a valid address: " + url; RenderNav(); }
        }

        void AddTab() { var tab = _s.AddTab(); RenderAll(); Navigate(tab.Url); }
        void CloseTab(string id) { if (!_s.CloseTab(id)) return; RenderAll(); Navigate(_s.CurrentUrl); }
        void SwitchTab(string id) { if (!_s.SwitchTab(id)) return; RenderAll(); Navigate(_s.CurrentUrl); }

        void SyncPinned()
        {
            if (_web == null) return;
            string json = new JavaScriptSerializer().Serialize(_s.Picked.Select(p => p.Selector).ToList());
            _web.ExecuteScript("if (window.__mcSyncPinnedSelectors) window.__mcSyncPinnedSelectors(" + json + ");", null);
        }

        void ToggleInspect()
        {
            _s.InspectMode = !_s.InspectMode;
            if (_web != null) _web.ExecuteScript("(function(){window.__mcInspectActive=" + (_s.InspectMode ? "true" : "false") + ";if(!window.__mcInspectActive&&window.__mcHideHoverHighlightOnly){window.__mcHideHoverHighlightOnly();}})();", null);
            RenderNav();
        }

        void RemovePick(string id)
        {
            _s.Picked.RemoveAll(p => p.Id == id);
            SyncPinned();
            if (_s.Picked.Count == 0 && _web != null) _web.ExecuteScript("if (window.__mcHideHoverHighlightOnly) window.__mcHideHoverHighlightOnly();", null);
            RenderPicks(); RenderNav();
        }

        void ClearPicks()
        {
            _s.Picked.Clear(); _s.InspectMode = false;
            if (_web != null) _web.ExecuteScript("if (window.__mcClearInspectorHighlight) window.__mcClearInspectorHighlight(); window.__mcInspectActive = false;", null);
            RenderPicks(); RenderNav();
        }

        void SendAllToAgent()
        {
            string prompt = BrowserSession.AgentPrompt(_s.Picked.ToList(), _s.CurrentUrl, "");
            if (prompt == null) return;
            try { Clipboard.SetText(prompt); }
            catch (System.Runtime.InteropServices.COMException ex) { System.Diagnostics.Debug.WriteLine("clipboard: " + ex.Message); }
            ClearPicks();
            _app.SwitchToMode(EditorMode.AIAgent);
            _app.Notify("agent:send:" + prompt);
        }

        void RunRepl(string script)
        {
            script = (script ?? "").Trim();
            if (script.Length == 0 || _web == null) return;
            _web.ExecuteScript(BrowserSession.EvalWrapper(script), json =>
            {
                _s.Console.Add(new BrowserConsoleItem { Level = "info", Message = "> " + script + "\n← " + BrowserSession.FormatEvalResult(json), Source = "repl" });
                _devDirty = true;
            });
        }

        /// <summary>Snapshot hooks: alt-click each --browser-pick selector through the page's own picker, then run --browser-eval.</summary>
        void RunInitialHooks()
        {
            if (_hooksRun) return;
            _hooksRun = true;
            foreach (var sel in InitialPicks)
            {
                string js = "(function(){var el=document.querySelector(" + new JavaScriptSerializer().Serialize(sel) + ");if(!el)return false;el.scrollIntoView({block:'center'});var r=el.getBoundingClientRect();" +
                    "el.dispatchEvent(new MouseEvent('click',{bubbles:true,cancelable:true,altKey:true,clientX:r.left+r.width/2,clientY:r.top+r.height/2}));return true;})()";
                _web.ExecuteScript(js, null);
            }
            if (InitialEval != null) RunRepl(InitialEval);
        }

        // ── rendering ──

        void RenderAll() { RenderTabs(); RenderNav(); RenderPicks(); RenderWeb(); RenderDevTools(); }

        static FrameworkElement Spinner(double size, Brush brush)
        {
            var e = new Ellipse { Width = size, Height = size, Stroke = brush, StrokeThickness = 1.4, StrokeDashArray = new DoubleCollection { 2.4, 1.6 }, RenderTransformOrigin = new Point(0.5, 0.5), VerticalAlignment = VerticalAlignment.Center };
            var rt = new RotateTransform();
            e.RenderTransform = rt;
            rt.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360, TimeSpan.FromSeconds(1)) { RepeatBehavior = RepeatBehavior.Forever });
            return e;
        }

        void RenderTabs()
        {
            var t = Theme.Current;
            var row = V.H(0);
            foreach (var tab in _s.Tabs)
            {
                var tb = tab;
                bool active = _s.Current != null && _s.Current.Id == tb.Id;
                var title = V.T(tb.Title.Length == 0 ? "New Tab" : tb.Title, 10, FontWeights.Normal, t.Primary); title.MaxWidth = 120;
                var item = V.H(6, tb.IsLoading ? Spinner(10, t.Secondary) : (UIElement)Sym.Icon("globe", 9, t.Secondary), title);
                if (_s.Tabs.Count > 1)
                {
                    var close = V.Button(V.Box(Sym.Icon("xmark", 7, t.P(0.85)), V.P(3), Brushes.Transparent, 0), () => CloseTab(tb.Id));
                    close.ToolTip = "Close Tab";
                    item.Children.Add(close);
                }
                var cell = new Grid { Background = active ? t.A(0.12) : Brushes.Transparent };
                cell.Children.Add(V.Box(item, V.P(10, 6), Brushes.Transparent, 0));
                if (active) cell.Children.Add(new Border { Height = 2, Background = t.Accent, VerticalAlignment = VerticalAlignment.Bottom });
                var b = V.Button(cell, () => SwitchTab(tb.Id));
                b.PressedOpacity = 1;
                row.Children.Add(b);
            }
            var plus = V.Button(V.Box(Sym.Icon("plus", 10, t.P(0.85)), V.P(8, 0), Brushes.Transparent, 0), AddTab);
            plus.ToolTip = "New Tab";
            plus.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(plus);
            var sv = new ScrollViewer { HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, Content = row };
            _tabBar.Child = sv;
            _tabBar.Height = 30;
            _tabBar.Background = t.ControlBackground;
        }

        Btn NavIcon(string icon, string tip, Action a, bool enabled, Brush fg, double size)
        {
            var t = Theme.Current;
            var b = V.Button(V.Size(V.Box(Sym.Icon(icon, size, enabled ? (fg ?? t.P(0.85)) : t.S(0.45)), V.P(0), Brushes.Transparent, 4), 20, 20), enabled ? a : null);
            if (tip != null) b.ToolTip = tip;
            if (enabled) b.OnState = x => ((Border)x.Child).Background = x.IsHover ? t.P(0.08) : Brushes.Transparent;
            return b;
        }

        void RenderNav()
        {
            var t = Theme.Current;
            var c = _s.Current;
            bool loading = c != null && c.IsLoading;
            var row = V.H(6);
            row.Children.Add(NavIcon("chevron.left", "Back", () => _web.GoBack(), c != null && c.CanGoBack, null, 11));
            row.Children.Add(NavIcon("chevron.right", "Forward", () => _web.GoForward(), c != null && c.CanGoForward, null, 11));
            row.Children.Add(loading ? NavIcon("xmark", "Stop", () => _web.Stop(), true, null, 11) : NavIcon("arrow.clockwise", "Reload", () => _web.Reload(), true, null, 11));

            // URL bar
            if (_url == null)
            {
                Grid field;
                field = Styles.Field("Search or enter URL", 12, t.Primary, t.Secondary, out _url);
                _url.FontFamily = UIFonts.Mono;
                _url.Text = _s.CurrentUrl;
                _url.KeyDown += (s, e) => { if (e.Key == System.Windows.Input.Key.Enter) { Navigate(_url.Text); e.Handled = true; } };
                _url.TextChanged += delegate { RenderUrlAdornments(); };
                _url.Tag = field;
            }
            var fieldGrid = (Grid)_url.Tag;
            if (fieldGrid.Parent is Panel) ((Panel)fieldGrid.Parent).Children.Remove(fieldGrid);
            _urlLock = new Border(); _urlClear = new Border();
            var urlRow = V.H(6, _urlLock, V.Flex(fieldGrid), _urlClear);
            var urlBox = V.Box(urlRow, V.P(8, 5), t.TextBackground, 6, t.S(0.2), 1);
            row.Children.Add(V.Flex(urlBox));
            RenderUrlAdornments();

            // bookmark star
            bool marked = _s.IsBookmarked(_s.CurrentUrl);
            row.Children.Add(NavIcon(marked ? "star.fill" : "star", marked ? "Remove Bookmark" : "Bookmark This Page", () => { _s.ToggleBookmark(_s.CurrentUrl, c != null ? c.Title : ""); RenderNav(); }, true, marked ? t.SysYellow : t.Secondary, 11));
            // bookmarks list
            var books = NavIcon("book", "Bookmarks", null, true, null, 11);
            books.MenuItems = () =>
            {
                if (_s.Bookmarks.Count == 0) return new List<MenuItemSpec> { new MenuItemSpec { Title = "No bookmarks", Disabled = true } };
                return _s.Bookmarks.Select(bm => { var u = bm.Url; return MenuItemSpec.Item(bm.Title.Length == 0 ? bm.Url : bm.Title, null, () => Navigate(u)); }).ToList();
            };
            row.Children.Add(books);
            // history
            var hist = NavIcon("clock.arrow.circlepath", "History", null, true, null, 11);
            hist.MenuItems = () =>
            {
                var items = _s.History.Take(20).Select(h => { var u = h.Url; return MenuItemSpec.Item(h.Title.Length == 0 ? h.Url : h.Title, null, () => Navigate(u)); }).ToList();
                if (items.Count == 0) items.Add(new MenuItemSpec { Title = "No history", Disabled = true });
                return items;
            };
            row.Children.Add(hist);
            // visual element picker
            var pickContent = V.H(3, Sym.Icon("viewfinder", 11, _s.InspectMode ? t.Primary : t.Secondary, _s.InspectMode ? FontWeights.Bold : FontWeights.Normal));
            if (_s.Picked.Count > 0) pickContent.Children.Add(V.Mono(_s.Picked.Count.ToString(CultureInfo.InvariantCulture), 9.5, FontWeights.Bold, _s.InspectMode ? t.Primary : t.Secondary));
            var picker = V.Button(V.Size(V.Box(pickContent, V.P(3, 0), Brushes.Transparent, 4), double.NaN, 20), ToggleInspect);
            picker.ToolTip = "Multi-Point Visual Element Picker (Click multiple elements in page to inspect & send to AI Agent)";
            picker.OnState = x => ((Border)x.Child).Background = x.IsHover ? t.P(0.08) : Brushes.Transparent;
            row.Children.Add(picker);
            // developer tools
            row.Children.Add(NavIcon("hammer", "Developer Tools", () => { _showDevTools = !_showDevTools; RenderWeb(); RenderDevTools(); RenderNav(); }, true, _showDevTools ? t.Accent : t.Secondary, 11));
            // external browser
            row.Children.Add(NavIcon("arrow.up.right.square", "Open in External Browser", OpenExternal, true, null, 11));
            var col = V.VLead(0, row);
            col.Align = Cross.Stretch;
            if (_status != null)
            {
                var st = V.T(_status, 10.5, FontWeights.Normal, t.SysOrange);
                st.Margin = new Thickness(2, 5, 0, 0);
                col.Children.Add(st);
            }
            _navBar.Child = V.Box(col, V.P(8, 6), t.ControlBackground, 0);
        }

        Border _urlLock, _urlClear;

        void RenderUrlAdornments()
        {
            if (_url == null || _urlLock == null) return;
            var t = Theme.Current;
            bool https = _url.Text.StartsWith("https", StringComparison.OrdinalIgnoreCase);
            _urlLock.Child = Sym.Icon(https ? "lock.fill" : "globe", 9, https ? t.SysGreen : t.Secondary);
            _urlClear.Child = _url.Text.Length == 0 ? null : V.Button(Sym.Icon("xmark.circle.fill", 9, t.Secondary), () => { _url.Text = ""; _url.Focus(); });
        }

        void OpenExternal()
        {
            Uri u;
            if (!Uri.TryCreate(_s.CurrentUrl, UriKind.Absolute, out u) || (u.Scheme != "http" && u.Scheme != "https")) return;
            try { System.Diagnostics.Process.Start(u.AbsoluteUri); }
            catch (System.ComponentModel.Win32Exception ex) { _status = "Could not open the system browser: " + ex.Message; RenderNav(); }
        }

        void RenderPicks()
        {
            var t = Theme.Current;
            if (_s.Picked.Count == 0) { _picks.Child = null; _picks.Visibility = Visibility.Collapsed; return; }
            _picks.Visibility = Visibility.Visible;
            int n = _s.Picked.Count;
            var row = V.H(8, Sym.Icon("viewfinder", 11, t.Primary, FontWeights.Bold), V.Box(V.Mono(n + " TARGET" + (n == 1 ? "" : "S"), 9.5, FontWeights.Bold, t.Primary), V.P(6, 2), t.P(0.1), 4));
            var chips = V.H(6);
            for (int i = 0; i < n; i++)
            {
                var item = _s.Picked[i];
                var sel = V.Mono(item.Selector, 10.5, FontWeights.Medium, t.Primary); sel.MaxWidth = 280;
                var x = V.Button(Sym.Icon("xmark", 8, t.Secondary, FontWeights.Bold), () => RemovePick(item.Id));
                chips.Children.Add(V.Box(V.H(4, V.Mono("#" + (i + 1), 9.5, FontWeights.Bold, t.Secondary), sel, x), V.P(6, 2), t.P(0.06), 4));
            }
            var sv = new ScrollViewer { HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, Content = chips };
            row.Children.Add(V.Shrink(V.Flex(sv)));
            var winBg = t.WindowBackground;
            var send = V.Button(V.Box(V.H(4, Sym.Icon("arrow.up.circle.fill", 10, winBg), V.T("Send All (" + n + ")", 10, FontWeights.SemiBold, winBg)), V.P(8, 3.5), t.Primary, 5), SendAllToAgent);
            row.Children.Add(send);
            row.Children.Add(V.Button(Sym.Icon("xmark", 9, t.Secondary), ClearPicks));
            _picks.Child = V.Box(row, V.P(10, 5), t.ControlBackground, 0);
        }

        void RenderWeb()
        {
            var t = Theme.Current;
            if (_web != null && _web.Error == null)
            {
                if (_web.Parent is Decorator && _web.Parent != _webHost) ((Decorator)_web.Parent).Child = null;
                _webHost.Child = _web;
            }
            else
            {
                string why = _web != null && _web.Error != null ? _web.Error : "Microsoft Edge WebView2 Runtime is not installed.";
                _webHost.Child = V.Vs(8, V.Sp(), Sym.Icon("globe", 30, t.S(0.6)), V.T("The browser could not start", 14, FontWeights.SemiBold, t.Primary), V.Wrap(V.T(why, 11.5, FontWeights.Normal, t.Secondary), TextAlignment.Center), V.Sp());
            }
            _content.ColumnDefinitions[1].Width = new GridLength(_showDevTools ? 1 : 0);
            _content.ColumnDefinitions[2].Width = _showDevTools ? new GridLength(380) : new GridLength(0);
            _content.ColumnDefinitions[2].MinWidth = _showDevTools ? 320 : 0;
            _devTools.Visibility = _showDevTools ? Visibility.Visible : Visibility.Collapsed;
        }

        static TextBox Selectable(string text, double size, Brush fg, bool mono)
        {
            var tb = new TextBox
            {
                Style = (Style)Application.Current.FindResource("PlainTextBox"), Text = text, IsReadOnly = true, TextWrapping = TextWrapping.Wrap,
                FontFamily = mono ? UIFonts.Mono : UIFonts.UI, FontSize = size, Foreground = fg, CaretBrush = Brushes.Transparent, VerticalAlignment = VerticalAlignment.Top
            };
            return tb;
        }

        static string MiddleTruncate(string s, int max)
        {
            if (s == null || s.Length <= max) return s;
            int head = (max - 1) / 2, tail = max - 1 - head;
            return s.Substring(0, head) + "…" + s.Substring(s.Length - tail);
        }

        void RenderDevTools()
        {
            if (!_showDevTools) { _devTools.Child = null; return; }
            var t = Theme.Current;
            var head = V.H(8, Sym.Icon("hammer.fill", 10, t.SysOrange));
            foreach (var tab in new[] { Tuple.Create("console", "Console (" + _s.Console.Count + ")"), Tuple.Create("network", "Network (" + _s.Network.Count + ")"), Tuple.Create("dom", "DOM Source") })
            {
                string id = tab.Item1; bool on = _devTab == id;
                head.Children.Add(V.Button(V.Box(V.T(tab.Item2, 10, on ? FontWeights.SemiBold : FontWeights.Normal, on ? t.Accent : t.Secondary), V.P(7, 3), on ? t.A(0.16) : Brushes.Transparent, 4), () => { _devTab = id; RenderDevTools(); }));
            }
            head.Children.Add(V.Sp());
            var trash = NavIcon("trash", "Clear Console & Network Logs", () => { _s.Console.Clear(); _s.Network.Clear(); RenderDevTools(); }, true, t.Secondary, 10);
            head.Children.Add(trash);
            head.Children.Add(NavIcon("xmark", "Close Developer Tools", () => { _showDevTools = false; RenderWeb(); RenderDevTools(); RenderNav(); }, true, null, 10));
            var panel = new DockPanel { LastChildFill = true };
            var headBox = V.Box(head, V.P(8), Brushes.Transparent, 0);
            DockPanel.SetDock(headBox, Dock.Top); panel.Children.Add(headBox);
            var div = V.Line(t.Separator, true); DockPanel.SetDock(div, Dock.Top); panel.Children.Add(div);

            if (_devTab == "console")
            {
                // REPL row
                if (_repl == null)
                {
                    Grid replField = Styles.Field("Evaluate JavaScript in page...", 11, t.Primary, t.Secondary, out _repl);
                    _repl.FontFamily = UIFonts.Mono;
                    _repl.KeyDown += (s, e) => { if (e.Key == System.Windows.Input.Key.Enter) { string sc = _repl.Text; _repl.Text = ""; RunRepl(sc); e.Handled = true; } };
                    _repl.Tag = replField;
                }
                var rf = (Grid)_repl.Tag;
                if (rf.Parent is Panel) ((Panel)rf.Parent).Children.Remove(rf);
                var repl = V.Box(V.H(6, V.Mono(">", 11, FontWeights.Bold, t.Accent), V.Flex(rf)), V.P(8, 6), t.ControlBackground, 0);
                DockPanel.SetDock(repl, Dock.Bottom); panel.Children.Add(repl);
                var div2 = V.Line(t.Separator, true); DockPanel.SetDock(div2, Dock.Bottom); panel.Children.Add(div2);
                var list = new StackPanel { Margin = new Thickness(0, 4, 0, 4) };
                if (_s.Console.Count == 0) list.Children.Add(new Border { Padding = V.P(8), Child = V.Mono("No console output yet.", 10, FontWeights.Normal, t.Secondary) });
                foreach (var e in _s.Console)
                {
                    var lvColor = e.Level == "error" ? t.SysRed : e.Level == "warn" ? t.SysOrange : t.SysBlue;
                    var lv = V.Mono(e.Level.ToUpperInvariant(), 9, FontWeights.Bold, lvColor); lv.Width = 44; lv.VerticalAlignment = VerticalAlignment.Top;
                    var line = new DockPanel { Margin = new Thickness(8, 2, 8, 2) };
                    DockPanel.SetDock(lv, Dock.Left); line.Children.Add(lv);
                    var msg = Selectable(e.Message, 10, e.Level == "error" ? t.SysRed : t.Primary, true); msg.Margin = new Thickness(6, 0, 0, 0);
                    line.Children.Add(msg);
                    list.Children.Add(line);
                }
                var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = list, Background = t.TextBackground };
                sv.Loaded += delegate { sv.ScrollToEnd(); };
                panel.Children.Add(sv);
            }
            else if (_devTab == "network")
            {
                var list = new StackPanel { Margin = new Thickness(0, 4, 0, 4) };
                if (_s.Network.Count == 0) list.Children.Add(new Border { Padding = V.P(8), Child = V.Mono("No fetch/XHR network requests recorded yet.", 10, FontWeights.Normal, t.Secondary) });
                foreach (var r in _s.Network)
                {
                    var m = V.Mono(r.Method, 9, FontWeights.Bold, t.Accent); m.Width = 38;
                    var st = V.Mono(r.Status.ToString(CultureInfo.InvariantCulture), 9, FontWeights.SemiBold, r.Status >= 400 || r.Status == 0 ? t.SysRed : t.SysGreen); st.Width = 30;
                    var d = V.Mono(r.DurationMs + "ms", 9, FontWeights.Normal, t.Secondary); d.Width = 48; d.TextAlignment = TextAlignment.Right;
                    var u = V.Mono(MiddleTruncate(r.Url, 96), 10, FontWeights.Normal, t.Primary); u.ToolTip = r.Url;
                    var line = V.H(6, m, st, d, V.Shrink(u));
                    line.Margin = new Thickness(8, 2, 8, 2);
                    list.Children.Add(line);
                }
                panel.Children.Add(new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = list, Background = t.TextBackground });
            }
            else
            {
                var src = Selectable(_pageSource.Length == 0 ? "Loading..." : (_pageSource.Length > 400000 ? _pageSource.Substring(0, 400000) + "\n…" : _pageSource), 10, t.Primary, true);
                src.Margin = new Thickness(8);
                panel.Children.Add(new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = src, Background = t.TextBackground });
            }
            _devTools.Child = panel;
            _devTools.Background = t.EditorBackground;
        }

        // ── snapshots ──

        public bool HasPage { get { return _web != null; } }

        /// <summary>For snapshots: once the page has loaded (and hooks ran), its PNG and where the browser sits inside <paramref name="root"/>.</summary>
        public void SnapshotLayer(FrameworkElement root, Action<byte[], Rect> done)
        {
            var started = DateTime.Now;
            var poll = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
            poll.Tick += delegate
            {
                var c = _s.Current;
                if ((_web == null || !_web.IsReady || (c != null && c.IsLoading)) && (DateTime.Now - started).TotalSeconds < 15) return;
                poll.Stop();
                if (_web == null || !_web.IsReady || _web.Parent == null) { done(null, Rect.Empty); return; }
                RenderDevTools(); RenderNav();
                UpdateLayout();
                var rect = Rect.Empty;
                try { rect = _web.TransformToAncestor(root).TransformBounds(new Rect(0, 0, _web.ActualWidth, _web.ActualHeight)); }
                catch (InvalidOperationException ex) { System.Diagnostics.Debug.WriteLine("browser snapshot layer: " + ex.Message); }
                _web.CapturePng(png => done(png, rect));
            };
            poll.Start();
        }
    }
}
