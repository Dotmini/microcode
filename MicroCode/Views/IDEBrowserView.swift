import SwiftUI
import WebKit
import AppKit

// ==========================================
// IDE Browser & MCP Automation Engine
// Native Apple WebKit + DevTools + AI Agent Bridge
// ==========================================

struct BrowserConsoleEntry: Identifiable, Codable {
    var id = UUID()
    let level: String
    let message: String
    let source: String
    let timestamp: Date
}

struct BrowserNetworkEntry: Identifiable, Codable {
    var id = UUID()
    let method: String
    let url: String
    let status: Int
    let durationMs: Int
    let timestamp: Date
}

struct BrowserPickedElement: Identifiable, Codable, Equatable {
    var id = UUID()
    let selector: String
    let tag: String
    let text: String
    let outerHTML: String
    let styles: String
    let rect: String
    var boundsX: Double = 0
    var boundsY: Double = 0
    var boundsWidth: Double = 0
    var boundsHeight: Double = 0
    var viewportWidth: Double = 800
    var viewportHeight: Double = 600
    let timestamp: Date
}

// MARK: - Feature #6: Active Port & Zombie Process Radar Model

struct ActiveLocalPortProcess: Identifiable, Equatable {
    var id: String { "\(port):\(pid)" }
    let port: Int
    let pid: Int
    let processName: String
    let commandLine: String
}

// MARK: - Promoted Live WebApp Screenshot Model

struct PromotedWebAppCapture: Identifiable, Equatable {
    let id: String
    let filePath: String
    let pageURL: String
    let pageTitle: String
    let resolutionText: String
    let timestamp: Date
    let byteCount: Int
}

private final class WeakScriptMessageTrampoline: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(target: WKScriptMessageHandler) {
        self.target = target
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

@MainActor
final class IDEBrowserAutomationService: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = IDEBrowserAutomationService()
    
    weak var activeBrowserWebView: WKWebView?
    weak var activePreviewWebView: WKWebView?
    private var backgroundWebView: WKWebView?
    
    @Published var consoleLogs: [BrowserConsoleEntry] = []
    @Published var networkLogs: [BrowserNetworkEntry] = []
    @Published var lastEvaluatedResult: String = ""
    @Published var isInspectMode: Bool = false
    @Published var lastPickedElement: BrowserPickedElement? = nil
    @Published var activePortProcesses: [ActiveLocalPortProcess] = []
    @Published var isScanningPorts: Bool = false
    @Published var lastPromotedCapture: PromotedWebAppCapture? = nil
    @Published var isCapturingScreenshot: Bool = false
    
    static let telemetryScriptSource: String = """
    (function() {
        if (window.__mcTelemetryInstalled) return;
        window.__mcTelemetryInstalled = true;
        function send(type, payload) {
            try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mcBrowserBridge) {
                    window.webkit.messageHandlers.mcBrowserBridge.postMessage(Object.assign({ _type: type }, payload));
                }
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
                if (url) {
                    send('console', { level: 'error', message: 'BrokenAsset (<' + tag + '>): Failed to load ' + url });
                }
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

        // Always-On Interactive DOM Inspector: Right-Click (คลิกขวา), Drag-to-Select (ลากคลุม), and Hover-Inspect
        function ensureInspectorDOM() {
            if (!document.body) return null;
            var overlay = document.getElementById('__mc_inspect_overlay');
            var label = document.getElementById('__mc_inspect_label');
            var dragBox = document.getElementById('__mc_drag_box');
            if (!overlay) {
                overlay = document.createElement('div');
                overlay.id = '__mc_inspect_overlay';
                overlay.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483645;border:2px solid #00D2FF;background:rgba(0,210,255,0.14);border-radius:5px;box-shadow:0 0 0 1px rgba(0,210,255,0.3),0 4px 16px rgba(0,210,255,0.18);transition:all 0.04s ease;display:none;';
                document.body.appendChild(overlay);
            }
            if (!label) {
                label = document.createElement('div');
                label.id = '__mc_inspect_label';
                label.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483646;background:#0D1117;color:#00D2FF;font:600 11px -apple-system,BlinkMacSystemFont,monospace;padding:3px 8px;border-radius:4px;border:1px solid #00D2FF;box-shadow:0 4px 12px rgba(0,0,0,0.45);display:none;white-space:nowrap;';
                document.body.appendChild(label);
            }
            if (!dragBox) {
                dragBox = document.createElement('div');
                dragBox.id = '__mc_drag_box';
                dragBox.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483647;border:1.5px dashed #00D2FF;background:rgba(0,210,255,0.10);border-radius:4px;display:none;';
                document.body.appendChild(dragBox);
            }
            return { overlay: overlay, label: label, dragBox: dragBox };
        }

        function isInternalInspectorNode(el) {
            if (!el) return true;
            var id = el.id || '';
            return id === '__mc_inspect_overlay' || id === '__mc_inspect_label' || id === '__mc_drag_box';
        }

        function buildSelectorForElement(el) {
            if (!el || !el.tagName) return 'body';
            var parts = [];
            var cur = el;
            var depth = 0;
            while (cur && cur.tagName && depth < 3) {
                var tag = cur.tagName.toLowerCase();
                var idPart = cur.id ? ('#' + cur.id) : '';
                var clsPart = '';
                if (!idPart && cur.className && typeof cur.className === 'string') {
                    var classes = cur.className.trim().split(/\\s+/).filter(Boolean).slice(0, 2);
                    if (classes.length > 0) clsPart = '.' + classes.join('.');
                }
                parts.unshift(tag + idPart + clsPart);
                if (idPart || tag === 'body' || tag === 'html') break;
                cur = cur.parentElement;
                depth++;
            }
            return parts.join(' > ');
        }

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
            var clsPart = (el.className && typeof el.className === 'string' && el.className.trim()) ? ('.' + el.className.trim().split(/\\s+/).slice(0,2).join('.')) : '';
            ui.label.textContent = '🎯 ' + el.tagName.toLowerCase() + idPart + clsPart + ' (' + Math.round(r.width) + '×' + Math.round(r.height) + ')' + (badgeSuffix ? ' • ' + badgeSuffix : '');
            ui.label.style.display = 'block';
            ui.label.style.left = Math.max(6, Math.min(window.innerWidth - 220, r.left)) + 'px';
            ui.label.style.top = (r.top > 30 ? (r.top - 26) : (r.bottom + 6)) + 'px';
        }

        function pickAndSendElement(el, selectedText, modeLabel) {
            if (!el || isInternalInspectorNode(el)) return;
            if (el.nodeType === 3) el = el.parentElement;
            if (!el || !el.tagName) return;
            highlightElementOnPage(el, modeLabel || 'Selected for AI Edit');
            var r = el.getBoundingClientRect();
            var cs = window.getComputedStyle(el);
            var selector = buildSelectorForElement(el);
            var stylesSummary = 'display:' + cs.display + '; color:' + cs.color + '; bg:' + cs.backgroundColor + '; font:' + cs.fontSize + ' ' + cs.fontFamily + '; padding:' + cs.padding;
            var rawText = (selectedText && selectedText.length > 0) ? ('[Selected: "' + selectedText.slice(0, 240) + '"]') : ((el.innerText || el.value || '').trim().slice(0, 240));
            send('element_picked', {
                selector: selector,
                tag: el.tagName.toLowerCase(),
                text: rawText,
                outerHTML: (el.outerHTML || '').slice(0, 700),
                styles: stylesSummary,
                rect: Math.round(r.left) + ',' + Math.round(r.top) + ' (' + Math.round(r.width) + 'x' + Math.round(r.height) + ')',
                boundsX: r.left,
                boundsY: r.top,
                boundsWidth: r.width,
                boundsHeight: r.height,
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
        };

        // 1. Right-Click (คลิกขวา) anywhere on Preview -> Inspect Element & Open Direct Agent Edit
        window.addEventListener('contextmenu', function(e) {
            var el = document.elementFromPoint(e.clientX, e.clientY) || e.target;
            if (!el || isInternalInspectorNode(el)) return;
            e.preventDefault();
            e.stopPropagation();
            var sel = (window.getSelection && window.getSelection().toString() || '').trim();
            pickAndSendElement(el, sel, 'Right-Click Inspect');
        }, true);

        // 2. Hover + Left-Click when Inspect Mode is active (or Alt/Option + Click anytime)
        window.addEventListener('mousemove', function(e) {
            if (window.__mcInspectActive) {
                var el = document.elementFromPoint(e.clientX, e.clientY);
                if (!el || isInternalInspectorNode(el)) return;
                highlightElementOnPage(el, 'Click to Edit with AI');
            }
        }, true);

        window.addEventListener('click', function(e) {
            if (!window.__mcInspectActive && !e.altKey) return;
            var el = document.elementFromPoint(e.clientX, e.clientY) || e.target;
            if (!el || isInternalInspectorNode(el)) return;
            e.preventDefault();
            e.stopPropagation();
            window.__mcInspectActive = false;
            pickAndSendElement(el, '', 'Picked for AI Edit');
        }, true);

        // 3. Drag-to-Select / Marquee Box (ลากคลุม) -> Draws Cyan Selection Box & Picks Target Element/Text
        var dragStart = null;
        var isMarqueeDragging = false;
        window.addEventListener('mousedown', function(e) {
            if (e.button !== 0 || window.__mcInspectActive) return;
            var tag = (e.target && e.target.tagName) ? e.target.tagName.toLowerCase() : '';
            if (tag === 'input' || tag === 'textarea' || tag === 'select') return;
            dragStart = { x: e.clientX, y: e.clientY, target: e.target };
            isMarqueeDragging = false;
        }, true);

        window.addEventListener('mousemove', function(e) {
            if (!dragStart) return;
            var dx = e.clientX - dragStart.x;
            var dy = e.clientY - dragStart.y;
            var dist = Math.hypot(dx, dy);
            if (dist > 14) {
                isMarqueeDragging = true;
                var ui = ensureInspectorDOM();
                if (ui) {
                    var left = Math.min(dragStart.x, e.clientX);
                    var top = Math.min(dragStart.y, e.clientY);
                    var width = Math.abs(dx);
                    var height = Math.abs(dy);
                    ui.dragBox.style.display = 'block';
                    ui.dragBox.style.left = left + 'px';
                    ui.dragBox.style.top = top + 'px';
                    ui.dragBox.style.width = width + 'px';
                    ui.dragBox.style.height = height + 'px';
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
            var dist = Math.hypot(dx, dy);
            if (!wasDragging && dist < 18) return;

            var selText = '';
            var selEl = null;
            if (window.getSelection) {
                var sel = window.getSelection();
                selText = (sel ? sel.toString() : '').trim();
                if (sel && sel.rangeCount > 0) {
                    var node = sel.getRangeAt(0).commonAncestorContainer;
                    selEl = (node && node.nodeType === 1) ? node : (node ? node.parentElement : null);
                }
            }
            if (!selEl || selEl === document.body || selEl === document.documentElement) {
                var cx = (start.x + e.clientX) / 2;
                var cy = (start.y + e.clientY) / 2;
                selEl = document.elementFromPoint(cx, cy) || start.target || e.target;
            }
            if (selEl && !isInternalInspectorNode(selEl)) {
                pickAndSendElement(selEl, selText, selText ? 'Text Selection' : 'Region Selected');
            }
        }, true);
    })();
    """
    
    func attachTelemetry(to config: WKWebViewConfiguration) {
        config.userContentController.removeAllUserScripts()
        let startScript = WKUserScript(source: Self.telemetryScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        let endScript = WKUserScript(source: Self.telemetryScriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(startScript)
        config.userContentController.addUserScript(endScript)
        config.userContentController.removeScriptMessageHandler(forName: "mcBrowserBridge")
        config.userContentController.add(WeakScriptMessageTrampoline(target: self), name: "mcBrowserBridge")
    }
    
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["_type"] as? String else { return }
        if type == "console" {
            let level = body["level"] as? String ?? "log"
            let msg = body["message"] as? String ?? ""
            Task { @MainActor in
                self.consoleLogs.append(BrowserConsoleEntry(level: level, message: msg, source: "webview", timestamp: Date()))
                if self.consoleLogs.count > 300 {
                    self.consoleLogs.removeFirst(self.consoleLogs.count - 300)
                }
            }
        } else if type == "network" {
            let method = body["method"] as? String ?? "GET"
            let url = body["url"] as? String ?? ""
            let status = (body["status"] as? NSNumber)?.intValue ?? 0
            let dur = (body["durationMs"] as? NSNumber)?.intValue ?? 0
            Task { @MainActor in
                self.networkLogs.append(BrowserNetworkEntry(method: method, url: url, status: status, durationMs: dur, timestamp: Date()))
                if self.networkLogs.count > 300 {
                    self.networkLogs.removeFirst(self.networkLogs.count - 300)
                }
            }
        } else if type == "element_picked" {
            let selector = body["selector"] as? String ?? ""
            let tag = body["tag"] as? String ?? ""
            let text = body["text"] as? String ?? ""
            let outerHTML = body["outerHTML"] as? String ?? ""
            let styles = body["styles"] as? String ?? ""
            let rect = body["rect"] as? String ?? ""
            let boundsX = (body["boundsX"] as? NSNumber)?.doubleValue ?? 0
            let boundsY = (body["boundsY"] as? NSNumber)?.doubleValue ?? 0
            let boundsW = (body["boundsWidth"] as? NSNumber)?.doubleValue ?? 0
            let boundsH = (body["boundsHeight"] as? NSNumber)?.doubleValue ?? 0
            let vpW = (body["viewportWidth"] as? NSNumber)?.doubleValue ?? 800
            let vpH = (body["viewportHeight"] as? NSNumber)?.doubleValue ?? 600
            Task { @MainActor in
                self.isInspectMode = false
                self.lastPickedElement = BrowserPickedElement(
                    selector: selector,
                    tag: tag,
                    text: text,
                    outerHTML: outerHTML,
                    styles: styles,
                    rect: rect,
                    boundsX: boundsX,
                    boundsY: boundsY,
                    boundsWidth: boundsW,
                    boundsHeight: boundsH,
                    viewportWidth: vpW,
                    viewportHeight: vpH,
                    timestamp: Date()
                )
            }
        }
    }
    
    func clearPickedElement(target: String = "preview") {
        lastPickedElement = nil
        isInspectMode = false
        let wv = resolveWebView(target: target)
        wv.evaluateJavaScript("if (window.__mcClearInspectorHighlight) window.__mcClearInspectorHighlight(); window.__mcInspectActive = false;", completionHandler: nil)
    }

    func toggleInspectMode(_ enabled: Bool? = nil, target: String = "auto") {
        let nextState = enabled ?? !isInspectMode
        isInspectMode = nextState
        let wv = resolveWebView(target: target)
        let js = """
        (function() {
            window.__mcInspectActive = \(nextState ? "true" : "false");
            if (!window.__mcInspectActive && window.__mcClearInspectorHighlight) {
                window.__mcClearInspectorHighlight();
                return 'Inspect Mode Disabled';
            }
            return 'Inspect Mode Enabled';
        })();
        """
        wv.evaluateJavaScript(js, completionHandler: nil)
    }
    
    func sendPickedElementToAgent(_ el: BrowserPickedElement, instruction: String = "", pageURL: String? = nil, autoSend: Bool? = nil) {
        let resolvedURL = pageURL ?? AppState.shared?.browserURL ?? "http://localhost:3000"
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldAutoSend = autoSend ?? !trimmedInstruction.isEmpty
        var contextPrompt = """
        [Inspect Element Target]
        - Page URL: \(resolvedURL)
        - Selector: `\(el.selector)` (`<\(el.tag)>` at \(el.rect))
        """
        if !el.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contextPrompt += "\n- Element / Selected Text: `\(el.text)`"
        }
        contextPrompt += """
        \n- Computed Styles: `\(el.styles)`
        - HTML Snippet:
        ```html
        \(el.outerHTML)
        ```
        """
        if !trimmedInstruction.isEmpty {
            contextPrompt += "\n\nInstruction: \(trimmedInstruction)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contextPrompt, forType: .string)
        AppState.shared?.aiChatVisible = true
        clearPickedElement(target: "preview")
        NotificationCenter.default.post(
            name: NSNotification.Name("MicroCodeInsertAgentPrompt"),
            object: nil,
            userInfo: [
                "prompt": contextPrompt,
                "autoSend": shouldAutoSend
            ]
        )
    }

    // MARK: - Feature #2: Live DOM & Console Auto-Healer Helpers

    var runtimeErrorEntries: [BrowserConsoleEntry] {
        consoleLogs.filter { entry in
            guard entry.level == "error" else { return false }
            let lower = entry.message.lowercased()
            if lower.contains("[vite] failed to connect to websocket") || lower.contains("[vite] server connection lost") {
                return false
            }
            return true
        }
    }

    var failedNetworkEntries: [BrowserNetworkEntry] {
        networkLogs.filter { $0.status >= 400 || $0.status == 0 }
    }

    var totalRuntimeIssueCount: Int {
        runtimeErrorEntries.count + failedNetworkEntries.count
    }

    func clearRuntimeIssues() {
        consoleLogs.removeAll { $0.level == "error" }
        networkLogs.removeAll { $0.status >= 400 || $0.status == 0 }
    }

    func dispatchAutoHealToAgent(pageURL: String) {
        let errors = runtimeErrorEntries.suffix(12)
        let failedNet = failedNetworkEntries.suffix(8)
        guard !errors.isEmpty || !failedNet.isEmpty else { return }

        var report = """
        [Live DOM & Console Auto-Healer Report]
        Page URL: \(pageURL)
        Please diagnose and fix the following runtime/DOM/asset errors detected in the live preview:
        """
        if !errors.isEmpty {
            report += "\n\n### Console & DOM Asset Errors (\(errors.count)):\n"
            for (idx, err) in errors.enumerated() {
                report += "\(idx + 1). `\(err.message.prefix(350))`\n"
            }
        }
        if !failedNet.isEmpty {
            report += "\n### Failed Network Requests (\(failedNet.count)):\n"
            for (idx, req) in failedNet.enumerated() {
                let statusLabel = req.status == 0 ? "NETWORK_ERR / CORS" : "HTTP \(req.status)"
                report += "\(idx + 1). `\(req.method) \(req.url)` → **\(statusLabel)** (\(req.durationMs)ms)\n"
            }
        }
        AppState.shared?.aiChatVisible = true
        NotificationCenter.default.post(
            name: NSNotification.Name("MicroCode.PreviewDock.RegionComment"),
            object: report
        )
    }

    // MARK: - Feature #6: Active Port & Zombie Process Radar

    func scanActivePorts() {
        guard !isScanningPorts else { return }
        isScanningPorts = true
        let selfPid = ProcessInfo.processInfo.processIdentifier
        Task.detached(priority: .utility) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            proc.arguments = ["-iTCP", "-sTCP:LISTEN", "-P", "-n"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            var discovered: [ActiveLocalPortProcess] = []
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let out = String(data: data, encoding: .utf8) {
                    var seenPorts = Set<Int>()
                    for line in out.components(separatedBy: .newlines).dropFirst() {
                        let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                        guard parts.count >= 9 else { continue }
                        let cmdName = parts[0]
                        guard let pid = Int(parts[1]), pid != Int(selfPid) else { continue }
                        let addrField = parts[parts.count - 2] // e.g. *:3000 or 127.0.0.1:8080
                        if let colonIdx = addrField.lastIndex(of: ":"),
                           let port = Int(addrField[addrField.index(after: colonIdx)...]),
                           port >= 1024 && port <= 65535 {
                            // Filter out common macOS system/background processes
                            let lowerCmd = cmdName.lowercased()
                            let ignored = ["rapportd", "controlce", "airplayxp", "sharingd", "homed", " identitys", "onedrive", "dropbox", "spotify", "figma", "slack", "discord", "chrome", "safari", "webkit"]
                            if ignored.contains(where: { lowerCmd.contains($0) }) { continue }
                            if !seenPorts.contains(port) {
                                seenPorts.insert(port)
                                discovered.append(ActiveLocalPortProcess(
                                    port: port,
                                    pid: pid,
                                    processName: cmdName,
                                    commandLine: "\(cmdName) (PID \(pid))"
                                ))
                            }
                        }
                    }
                }
            } catch {}
            discovered.sort { $0.port < $1.port }
            let finalDiscovered = discovered
            await MainActor.run {
                self.activePortProcesses = finalDiscovered
                self.isScanningPorts = false
            }
        }
    }

    func killPortProcess(_ item: ActiveLocalPortProcess) {
        kill(pid_t(item.pid), SIGKILL)
        activePortProcesses.removeAll { $0.id == item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.scanActivePorts()
        }
    }

    func killAllDevPortProcesses() {
        for item in activePortProcesses {
            kill(pid_t(item.pid), SIGKILL)
        }
        activePortProcesses.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.scanActivePorts()
        }
    }
    
    func resolveWebView(target: String = "auto") -> WKWebView {
        let t = target.lowercased()
        if t == "preview", let pv = activePreviewWebView {
            return pv
        }
        if t == "browser", let bv = activeBrowserWebView {
            return bv
        }
        if let bv = activeBrowserWebView { return bv }
        if let pv = activePreviewWebView { return pv }
        if let bg = backgroundWebView { return bg }
        
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = WKWebsiteDataStore.default()
        attachTelemetry(to: config)
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)
        wv.navigationDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        backgroundWebView = wv
        return wv
    }
    
    func evalJS(_ script: String, target: String = "auto") async throws -> String {
        let wv = resolveWebView(target: target)
        return try await withCheckedThrowingContinuation { continuation in
            wv.evaluateJavaScript(script) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let res = result {
                    if JSONSerialization.isValidJSONObject(res),
                       let data = try? JSONSerialization.data(withJSONObject: res, options: [.prettyPrinted]),
                       let str = String(data: data, encoding: .utf8) {
                        continuation.resume(returning: str)
                    } else {
                        continuation.resume(returning: "\(res)")
                    }
                } else {
                    continuation.resume(returning: "null")
                }
            }
        }
    }
    
    func resolveBestWebAppURL(preferredURL: String? = nil) -> URL? {
        if let raw = preferredURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if raw.hasPrefix("/") { return URL(fileURLWithPath: raw) }
            if raw.contains("://") { return URL(string: raw) }
            return URL(string: "http://\(raw)")
        }
        if let pvURL = activePreviewWebView?.url, pvURL.absoluteString != "about:blank" {
            return pvURL
        }
        if let targetURL = DeviceRuntimeService.shared.targetWebURL, targetURL.absoluteString != "about:blank" {
            return targetURL
        }
        if let port = DeviceRuntimeService.shared.lastDetectedDevServerPort {
            return URL(string: "http://localhost:\(port)")
        }
        if !activePortProcesses.isEmpty {
            let preferredPorts = [5173, 5174, 3000, 8080, 4200, 4321, 8000]
            let openPorts = Set(activePortProcesses.map(\.port))
            let chosen = preferredPorts.first(where: { openPorts.contains($0) }) ?? activePortProcesses[0].port
            return URL(string: "http://localhost:\(chosen)")
        }
        if let ws = AgentToolBox.shared.workspaceRoot ?? AppState.shared?.workspaceFolder?.path {
            let wsURL = URL(fileURLWithPath: ws)
            for rel in ["index.html", "public/index.html", "dist/index.html", "src/index.html"] {
                let candidate = wsURL.appendingPathComponent(rel)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }

    func captureLiveWebAppScreenshot(
        target: String = "preview",
        outputPath: String? = nil,
        preferredURL: String? = nil
    ) async throws -> PromotedWebAppCapture {
        isCapturingScreenshot = true
        defer { isCapturingScreenshot = false }

        let wv = resolveWebView(target: target)
        if wv.bounds.width < 240 || wv.bounds.height < 180 {
            wv.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        }

        // Auto-load active WebApp URL if the WebView hasn't loaded a real page yet
        let currentURLStr = wv.url?.absoluteString ?? ""
        let needsLoad = currentURLStr.isEmpty
            || currentURLStr == "about:blank"
            || (preferredURL != nil && !preferredURL!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || (currentURLStr == "http://localhost:3000" && DeviceRuntimeService.shared.lastDetectedDevServerPort != nil && DeviceRuntimeService.shared.lastDetectedDevServerPort != 3000)

        if needsLoad, let bestURL = resolveBestWebAppURL(preferredURL: preferredURL) {
            if bestURL.isFileURL {
                wv.loadFileURL(bestURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
            } else if wv.url?.absoluteString != bestURL.absoluteString {
                wv.load(URLRequest(url: bestURL))
            }
            for _ in 0..<28 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if !wv.isLoading && wv.url != nil { break }
            }
            // Brief settle for client-side Hydration (SvelteKit / React / Vue / Vite)
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        // Hide temporary inspector highlight box before taking the screenshot
        _ = try? await evalJS("if (window.__mcClearInspectorHighlight) window.__mcClearInspectorHighlight();", target: target)

        let wsRoot = AgentToolBox.shared.workspaceRoot ?? AppState.shared?.workspaceFolder?.path
        let resolvedPath: String = {
            if let raw = outputPath?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                if raw.hasPrefix("/") { return raw }
                if raw.hasPrefix("~") { return (raw as NSString).expandingTildeInPath }
                if let ws = wsRoot, !ws.isEmpty {
                    return (ws as NSString).appendingPathComponent(raw)
                }
                return (NSTemporaryDirectory() as NSString).appendingPathComponent(raw)
            }
            if let ws = wsRoot, !ws.isEmpty, FileManager.default.isWritableFile(atPath: ws) {
                return (ws as NSString).appendingPathComponent("preview_screenshot.png")
            }
            return "/tmp/microcode_webapp_snapshot_\(Int(Date().timeIntervalSince1970)).png"
        }()

        let config = WKSnapshotConfiguration()
        let (pngData, imgSize): (Data, NSSize) = try await withCheckedThrowingContinuation { continuation in
            wv.takeSnapshot(with: config) { image, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let image = image,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    continuation.resume(throwing: NSError(
                        domain: "IDEBrowser",
                        code: -6,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG snapshot"]
                    ))
                    return
                }
                continuation.resume(returning: (png, NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)))
            }
        }

        let fileURL = URL(fileURLWithPath: resolvedPath)
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try pngData.write(to: fileURL, options: .atomic)

        // Also write a timestamped copy in /tmp so historical chat messages remain distinct if preview_screenshot.png is overwritten later
        let timestampedCopyPath = "/tmp/microcode_webapp_cap_\(Int(Date().timeIntervalSince1970 * 1000)).png"
        try? pngData.write(to: URL(fileURLWithPath: timestampedCopyPath), options: .atomic)

        let pageURL = wv.url?.absoluteString ?? resolveBestWebAppURL(preferredURL: preferredURL)?.absoluteString ?? "http://localhost"
        let pageTitle = (wv.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resText = "\(Int(max(1, imgSize.width))) × \(Int(max(1, imgSize.height))) px"

        let capture = PromotedWebAppCapture(
            id: UUID().uuidString,
            filePath: resolvedPath,
            pageURL: pageURL,
            pageTitle: pageTitle.isEmpty ? "Live WebApp Preview" : pageTitle,
            resolutionText: resText,
            timestamp: Date(),
            byteCount: pngData.count
        )
        self.lastPromotedCapture = capture
        return capture
    }

    func promoteCaptureToAgentChat(_ capture: PromotedWebAppCapture, promptText: String? = nil, autoSend: Bool = false) {
        let userInstruction = (promptText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultMessage = userInstruction.isEmpty
            ? "นี่คือภาพ Screenshot จากการทดสอบใช้งานจริงบน WebApp Preview (`\(capture.pageURL)` — \(capture.resolutionText)) ช่วยตรวจสอบ UI/การทำงานจากภาพนี้:"
            : userInstruction
        let payload = """
        \(defaultMessage)

        ![Live WebApp Screenshot — \(capture.pageTitle)](file://\(capture.filePath))
        """
        AppState.shared?.aiChatVisible = true
        NotificationCenter.default.post(
            name: NSNotification.Name("MicroCodeInsertAgentPrompt"),
            object: nil,
            userInfo: [
                "prompt": payload,
                "autoSend": autoSend
            ]
        )
    }

    func executeAction(params: [String: Any]) async throws -> String {
        let action = (params["action"] as? String ?? "status").lowercased()
        let target = (params["target"] as? String ?? "auto").lowercased()
        let wv = resolveWebView(target: target)
        
        switch action {
        case "navigate", "open", "goto":
            guard var urlStr = params["url"] as? String, !urlStr.isEmpty else {
                throw NSError(domain: "IDEBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing 'url' parameter"])
            }
            if !urlStr.contains("://") && !urlStr.hasPrefix("/") {
                urlStr = "https://\(urlStr)"
            }
            let targetURL: URL? = urlStr.hasPrefix("/") ? URL(fileURLWithPath: urlStr) : URL(string: urlStr)
            guard let url = targetURL else {
                throw NSError(domain: "IDEBrowser", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(urlStr)"])
            }
            if target == "preview" {
                DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
                DeviceRuntimeService.shared.embeddedDockMode = .web
                DeviceRuntimeService.shared.targetWebURL = url
            } else {
                AppState.shared?.browserURL = url.absoluteString
                NotificationCenter.default.post(name: .browserNavigate, object: url.absoluteString)
            }
            if url.isFileURL {
                wv.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
            } else {
                wv.load(URLRequest(url: url))
            }
            // Wait up to 3.5s for page load to settle
            for _ in 0..<35 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if !wv.isLoading && (wv.url != nil) { break }
            }
            let title = (try? await evalJS("document.title", target: target)) ?? (wv.title ?? "")
            return "✅ Navigated (\(target)) to \(wv.url?.absoluteString ?? url.absoluteString) | Title: \(title)"
            
        case "inspect_elements", "elements", "interactive":
            let js = """
            (function() {
                var nodes = Array.from(document.querySelectorAll('a, button, input, select, textarea, [role="button"], [onclick], h1, h2, h3'));
                return JSON.stringify(nodes.slice(0, 80).map(function(el, idx) {
                    var r = el.getBoundingClientRect();
                    var idPart = el.id ? ('#' + el.id) : '';
                    var clsPart = (el.className && typeof el.className === 'string') ? ('.' + el.className.trim().split(/\\s+/).slice(0,2).join('.')) : '';
                    var selector = el.tagName.toLowerCase() + idPart + (idPart ? '' : clsPart);
                    return {
                        index: idx,
                        tag: el.tagName.toLowerCase(),
                        selector: selector,
                        text: (el.innerText || el.value || el.placeholder || el.getAttribute('aria-label') || '').trim().slice(0, 80),
                        type: el.getAttribute('type') || '',
                        href: el.getAttribute('href') || '',
                        rect: { x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) }
                    };
                }));
            })()
            """
            return try await evalJS(js, target: target)
            
        case "get_dom", "dom", "html", "read_page":
            let selector = params["selector"] as? String ?? "body"
            let escapedSel = selector.replacingOccurrences(of: "'", with: "\\'")
            let format = (params["format"] as? String ?? "text").lowercased()
            let js = format == "html"
                ? "(function(){ var el = document.querySelector('\(escapedSel)'); return el ? el.outerHTML.slice(0, 25000) : 'Selector not found'; })()"
                : "(function(){ var el = document.querySelector('\(escapedSel)'); return el ? ('Title: ' + document.title + '\\nURL: ' + location.href + '\\n\\n' + el.innerText.slice(0, 25000)) : 'Selector not found'; })()"
            return try await evalJS(js, target: target)
            
        case "click":
            if let selector = params["selector"] as? String, !selector.isEmpty {
                let esc = selector.replacingOccurrences(of: "'", with: "\\'")
                let js = """
                (function() {
                    var el = document.querySelector('\(esc)');
                    if (!el) {
                        var all = Array.from(document.querySelectorAll('button, a, input[type="submit"], [role="button"]'));
                        el = all.find(function(n) { return (n.innerText || n.value || '').trim().toLowerCase().includes('\(esc.lowercased())'); });
                    }
                    if (!el) return 'ERROR: Element not found for selector/text: \(esc)';
                    el.scrollIntoView({ block: 'center', inline: 'center' });
                    el.click();
                    return 'Clicked <' + el.tagName.toLowerCase() + '> (' + (el.innerText || el.value || el.id || '').trim().slice(0, 50) + ')';
                })()
                """
                return try await evalJS(js, target: target)
            } else if let x = (params["x"] as? NSNumber)?.doubleValue,
                      let y = (params["y"] as? NSNumber)?.doubleValue {
                let js = """
                (function() {
                    var el = document.elementFromPoint(\(x), \(y));
                    if (!el) return 'ERROR: No element at (\(x), \(y))';
                    el.click();
                    return 'Clicked <' + el.tagName.toLowerCase() + '> at (\(x), \(y))';
                })()
                """
                return try await evalJS(js, target: target)
            }
            throw NSError(domain: "IDEBrowser", code: -3, userInfo: [NSLocalizedDescriptionKey: "click requires 'selector' or ('x', 'y')"])
            
        case "type", "fill", "input":
            guard let selector = params["selector"] as? String, !selector.isEmpty else {
                throw NSError(domain: "IDEBrowser", code: -4, userInfo: [NSLocalizedDescriptionKey: "type requires 'selector'"])
            }
            let text = params["text"] as? String ?? ""
            let submit = params["submit"] as? Bool ?? false
            let escSel = selector.replacingOccurrences(of: "'", with: "\\'")
            let escTxt = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\n", with: "\\n")
            let js = """
            (function() {
                var el = document.querySelector('\(escSel)');
                if (!el) return 'ERROR: Input element not found: \(escSel)';
                el.focus();
                var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set
                    || Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value')?.set;
                if (nativeSetter) { nativeSetter.call(el, '\(escTxt)'); } else { el.value = '\(escTxt)'; }
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
                if (\(submit ? "true" : "false") && el.form) { el.form.requestSubmit ? el.form.requestSubmit() : el.form.submit(); }
                return 'Typed ' + '\(escTxt)'.length + ' chars into ' + '\(escSel)';
            })()
            """
            return try await evalJS(js, target: target)
            
        case "eval_js", "evaluate", "js":
            guard let script = (params["script"] as? String) ?? (params["code"] as? String), !script.isEmpty else {
                throw NSError(domain: "IDEBrowser", code: -5, userInfo: [NSLocalizedDescriptionKey: "eval_js requires 'script'"])
            }
            let res = try await evalJS(script, target: target)
            lastEvaluatedResult = res
            return res
            
        case "console_logs", "console":
            let levelFilter = (params["level"] as? String)?.lowercased()
            let clear = params["clear"] as? Bool ?? false
            let filtered = consoleLogs.filter { levelFilter == nil || levelFilter!.isEmpty || $0.level.lowercased() == levelFilter! }
            if clear { consoleLogs.removeAll() }
            if filtered.isEmpty { return "No console logs recorded." }
            return filtered.suffix(100).map { "[\($0.level.uppercased())] \($0.message)" }.joined(separator: "\n")
            
        case "network_logs", "network":
            let clear = params["clear"] as? Bool ?? false
            let snapshot = networkLogs
            if clear { networkLogs.removeAll() }
            if snapshot.isEmpty { return "No network requests recorded." }
            return snapshot.suffix(100).map { "[\($0.method)] \($0.status) (\($0.durationMs)ms) \($0.url)" }.joined(separator: "\n")
            
        case "screenshot", "snapshot":
            let rawOutPath = (params["output_path"] as? String) ?? (params["path"] as? String)
            let preferredURL = params["url"] as? String
            let capture = try await captureLiveWebAppScreenshot(
                target: target,
                outputPath: rawOutPath,
                preferredURL: preferredURL
            )
            return "✅ Live WebApp snapshot saved to \(capture.filePath) (\(capture.resolutionText), \(capture.byteCount) bytes)"
            
        case "status", "info":
            let url = wv.url?.absoluteString ?? (AppState.shared?.browserURL ?? "about:blank")
            let title = wv.title ?? (AppState.shared?.browserTitle ?? "")
            let tabsCount = AppState.shared?.browserTabs.count ?? 1
            return """
            IDE Browser & WebEngine Status:
            - Active URL: \(url)
            - Title: \(title)
            - Open Tabs: \(tabsCount)
            - Console Logs Buffered: \(consoleLogs.count)
            - Network Requests Buffered: \(networkLogs.count)
            - Inspect Mode Active: \(isInspectMode)
            - Last Picked Element: \(lastPickedElement?.selector ?? "None")
            - Browser WebView Attached: \(activeBrowserWebView != nil)
            - Preview WebView Attached: \(activePreviewWebView != nil)
            """
            
        case "pick_element", "highlight_element", "inspect_mode":
            if let selector = params["selector"] as? String, !selector.isEmpty {
                let escaped = selector.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                let js = """
                (function() {
                    var el = document.querySelector('\(escaped)');
                    if (!el) return 'ERROR: Element not found for ' + '\(escaped)';
                    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
                    var r = el.getBoundingClientRect();
                    var cs = window.getComputedStyle(el);
                    var hl = document.getElementById('__mc_highlight_box');
                    if (!hl) {
                        hl = document.createElement('div');
                        hl.id = '__mc_highlight_box';
                        hl.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483646;border:2px solid #00E5FF;background:rgba(0,229,255,0.16);border-radius:4px;box-shadow:0 0 12px rgba(0,229,255,0.5);transition:all 0.15s ease;';
                        document.body.appendChild(hl);
                    }
                    hl.style.display = 'block';
                    hl.style.left = r.left + 'px';
                    hl.style.top = r.top + 'px';
                    hl.style.width = r.width + 'px';
                    hl.style.height = r.height + 'px';
                    setTimeout(function() { if (hl) hl.style.display = 'none'; }, 3500);
                    return JSON.stringify({
                        selector: '\(escaped)',
                        tag: el.tagName.toLowerCase(),
                        rect: { x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) },
                        styles: { display: cs.display, color: cs.color, backgroundColor: cs.backgroundColor, fontSize: cs.fontSize, padding: cs.padding },
                        outerHTML: (el.outerHTML || '').slice(0, 500)
                    }, null, 2);
                })();
                """
                return try await evalJS(js, target: target)
            }
            if let enable = params["enable"] as? Bool {
                toggleInspectMode(enable, target: target)
                return enable ? "✅ Visual Element Picker enabled in IDE Browser. Hover and click any element." : "✅ Visual Element Picker disabled."
            }
            if let picked = lastPickedElement {
                return """
                Last Picked Element:
                - Selector: \(picked.selector)
                - Tag: <\(picked.tag)>
                - Rect: \(picked.rect)
                - Computed Styles: \(picked.styles)
                - HTML: \(picked.outerHTML)
                """
            }
            toggleInspectMode(true, target: target)
            return "✅ Enabled Visual Element Picker in IDE Browser (no element picked yet)."
            
        case "verify_ui", "health_check", "audit":
            if let urlStr = params["url"] as? String, !urlStr.isEmpty {
                _ = try await executeAction(params: ["action": "navigate", "url": urlStr, "target": target])
            }
            let healthJS = """
            (function() {
                var bodyText = (document.body && document.body.innerText) ? document.body.innerText.trim() : '';
                var hasMedia = document.querySelectorAll('canvas, svg, img, video, iframe').length > 0;
                var errorOverlay = document.querySelector('nextjs-portal, vite-error-overlay, #webpack-dev-server-client-overlay');
                var interactiveCount = document.querySelectorAll('a, button, input, select, textarea, [role="button"]').length;
                return JSON.stringify({
                    title: document.title || '',
                    url: location.href,
                    readyState: document.readyState,
                    bodyTextLength: bodyText.length,
                    hasVisualContent: (bodyText.length > 0 || hasMedia),
                    hasFrameworkErrorOverlay: !!errorOverlay,
                    interactiveElements: interactiveCount
                });
            })();
            """
            let domHealthRaw = (try? await evalJS(healthJS, target: target)) ?? "{}"
            let consoleErrors = consoleLogs.filter { $0.level == "error" }
            let consoleWarnings = consoleLogs.filter { $0.level == "warn" }
            let failedNetwork = networkLogs.filter { $0.status >= 400 || $0.status == 0 }
            
            let passed = consoleErrors.isEmpty && failedNetwork.isEmpty && !domHealthRaw.contains("\"hasFrameworkErrorOverlay\":true") && !domHealthRaw.contains("\"hasVisualContent\":false")
            let verdict = passed ? "✅ PASS (UI Healthy)" : "❌ FAIL (UI Issues Detected)"
            let errLines = consoleErrors.prefix(10).map { "  - [CONSOLE ERROR] \($0.message)" }.joined(separator: "\n")
            let netLines = failedNetwork.prefix(10).map { "  - [NETWORK \($0.status)] \($0.method) \($0.url)" }.joined(separator: "\n")
            return """
            === MicroCode Autonomous Frontend Verification Report ===
            Verdict: \(verdict)
            DOM Health: \(domHealthRaw)
            Console Errors (\(consoleErrors.count)):
            \(errLines.isEmpty ? "  (None)" : errLines)
            Console Warnings (\(consoleWarnings.count))
            Failed Network Requests (\(failedNetwork.count)):
            \(netLines.isEmpty ? "  (None)" : netLines)
            """
            
        default:
            throw NSError(domain: "IDEBrowser", code: -99, userInfo: [NSLocalizedDescriptionKey: "Unknown action '\(action)'. Supported: navigate, inspect_elements, get_dom, click, type, eval_js, console_logs, network_logs, screenshot, pick_element, highlight_element, verify_ui, status"])
        }
    }
}

struct IDEBrowserView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var automation = IDEBrowserAutomationService.shared
    @State private var urlInput: String = "https://microcode.dotmini.net"
    @State private var showBookmarks = false
    @State private var showHistory = false
    @State private var showDevTools = false
    @State private var devToolsTab: String = "console" // "console", "network", "dom"
    @State private var jsReplInput: String = ""
    @State private var pageSource = ""
    @State private var newTabURL = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            browserTabBar
            
            Divider()
            
            // Navigation bar
            navigationBar
            
            if let picked = automation.lastPickedElement {
                HStack(spacing: 8) {
                    Image(systemName: "scope")
                        .foregroundColor(.cyan)
                        .font(.system(size: 11, weight: .bold))
                    Text(picked.selector)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                    Text(picked.rect)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(picked.styles)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        automation.sendPickedElementToAgent(picked)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("Send to AI Agent")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    Button {
                        automation.lastPickedElement = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.cyan.opacity(0.08))
            }
            
            Divider()
            
            // WebView content
            HSplitView {
                WebViewContainer(
                    urlString: currentTabURL,
                    onTitleChange: { title in
                        updateTab { $0.title = title }
                        appState.browserTitle = title
                    },
                    onURLChange: { url in
                        urlInput = url
                        updateTab { $0.url = url }
                        appState.browserURL = url
                        // Add to history
                        appState.browserHistory.insert(
                            BrowserHistoryEntry(url: url, title: appState.browserTitle, visitedAt: Date()), at: 0
                        )
                        if appState.browserHistory.count > 200 {
                            appState.browserHistory = Array(appState.browserHistory.prefix(200))
                        }
                    },
                    onLoadingChange: { loading in
                        updateTab { $0.isLoading = loading }
                        appState.browserIsLoading = loading
                    },
                    onNavChange: { canBack, canForward in
                        updateTab { $0.canGoBack = canBack; $0.canGoForward = canForward }
                        appState.browserCanGoBack = canBack
                        appState.browserCanGoForward = canForward
                    },
                    onSourceFetched: { src in
                        pageSource = src
                    }
                )
                
                if showDevTools {
                    devToolsPanel
                }
            }
        }
        .onAppear {
            urlInput = currentTabURL
        }
    }
    
    private var currentTabURL: String {
        guard appState.browserActiveTab < appState.browserTabs.count else { return "https://www.google.com" }
        return appState.browserTabs[appState.browserActiveTab].url
    }
    
    private func updateTab(_ update: (inout BrowserTab) -> Void) {
        guard appState.browserActiveTab < appState.browserTabs.count else { return }
        update(&appState.browserTabs[appState.browserActiveTab])
    }
    
    // MARK: - Tab Bar
    private var browserTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(appState.browserTabs) { tab in
                    let isActive = (appState.browserActiveTab < appState.browserTabs.count && appState.browserTabs[appState.browserActiveTab].id == tab.id)
                    HStack(spacing: 6) {
                        if tab.isLoading {
                            ProgressView().scaleEffect(0.4).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "globe").font(.system(size: 9)).foregroundColor(.secondary)
                        }
                        Text(tab.title.isEmpty ? "New Tab" : tab.title)
                            .font(.system(size: 10)).lineLimit(1).frame(maxWidth: 120)
                        
                        if appState.browserTabs.count > 1 {
                            Button { closeTab(id: tab.id) } label: {
                                Image(systemName: "xmark").font(.system(size: 7))
                                    .padding(3)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Close Tab")
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
                    .overlay(alignment: .bottom) {
                        if isActive {
                            Rectangle().fill(Color.accentColor).frame(height: 2)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { switchTab(id: tab.id) }
                }
                
                // New tab button
                Button { addNewTab() } label: {
                    Image(systemName: "plus").font(.system(size: 10))
                }
                .buttonStyle(.borderless).padding(.horizontal, 8)
            }
        }
        .frame(height: 30)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Navigation Bar
    private var navigationBar: some View {
        HStack(spacing: 6) {
            // Back
            Button { NotificationCenter.default.post(name: .browserGoBack, object: nil) } label: {
                Image(systemName: "chevron.left").font(.system(size: 11))
            }.buttonStyle(.borderless).disabled(!appState.browserCanGoBack)
            
            // Forward
            Button { NotificationCenter.default.post(name: .browserGoForward, object: nil) } label: {
                Image(systemName: "chevron.right").font(.system(size: 11))
            }.buttonStyle(.borderless).disabled(!appState.browserCanGoForward)
            
            // Reload / Stop
            if appState.browserIsLoading {
                Button { NotificationCenter.default.post(name: .browserStop, object: nil) } label: {
                    Image(systemName: "xmark").font(.system(size: 11))
                }.buttonStyle(.borderless)
            } else {
                Button { NotificationCenter.default.post(name: .browserReload, object: nil) } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                }.buttonStyle(.borderless)
            }
            
            // URL bar
            HStack(spacing: 6) {
                Image(systemName: urlInput.hasPrefix("https") ? "lock.fill" : "globe")
                    .font(.system(size: 9))
                    .foregroundColor(urlInput.hasPrefix("https") ? .green : .secondary)
                
                TextField("Search or enter URL", text: $urlInput, onCommit: {
                    navigateTo(urlInput)
                })
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                
                if !urlInput.isEmpty {
                    Button { urlInput = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 9)).foregroundColor(.secondary)
                    }.buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
            
            // Bookmark
            Button {
                let url = currentTabURL
                let title = appState.browserTitle
                if appState.browserBookmarks.contains(where: { $0.url == url }) {
                    appState.browserBookmarks.removeAll { $0.url == url }
                } else {
                    appState.browserBookmarks.append(BrowserBookmark(url: url, title: title))
                }
            } label: {
                Image(systemName: appState.browserBookmarks.contains(where: { $0.url == currentTabURL }) ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundColor(appState.browserBookmarks.contains(where: { $0.url == currentTabURL }) ? .yellow : .secondary)
            }.buttonStyle(.borderless)
            
            // Bookmarks list
            Menu {
                if appState.browserBookmarks.isEmpty {
                    Text("No bookmarks")
                } else {
                    ForEach(appState.browserBookmarks) { bm in
                        Button(bm.title.isEmpty ? bm.url : bm.title) { navigateTo(bm.url) }
                    }
                }
            } label: {
                Image(systemName: "book").font(.system(size: 11))
            }.menuStyle(.borderlessButton).frame(width: 20)
            
            // History
            Menu {
                ForEach(appState.browserHistory.prefix(20)) { entry in
                    Button(entry.title.isEmpty ? entry.url : entry.title) { navigateTo(entry.url) }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 11))
            }.menuStyle(.borderlessButton).frame(width: 20)
            
            // Visual Element Picker ("Click-to-Prompt")
            Button {
                automation.toggleInspectMode()
            } label: {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 11))
                    .foregroundColor(automation.isInspectMode ? .cyan : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Visual Element Picker (Click element in page to inspect & send to AI Agent)")
            
            // Dev Tools toggle
            Button { showDevTools.toggle() } label: {
                Image(systemName: "hammer").font(.system(size: 11))
                    .foregroundColor(showDevTools ? .accentColor : .secondary)
            }.buttonStyle(.borderless).help("Developer Tools")
            
            // Open in external browser
            Button {
                if let url = URL(string: currentTabURL) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "arrow.up.right.square").font(.system(size: 11))
            }.buttonStyle(.borderless).help("Open in External Browser")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Dev Tools Panel (Console + JS REPL, Network, DOM Source)
    private var devToolsPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "hammer.fill").foregroundColor(.orange).font(.system(size: 10))
                ForEach([("console", "Console (\(automation.consoleLogs.count))"), ("network", "Network (\(automation.networkLogs.count))"), ("dom", "DOM Source")], id: \.0) { id, label in
                    Button {
                        devToolsTab = id
                    } label: {
                        Text(label)
                            .font(.system(size: 10, weight: devToolsTab == id ? .semibold : .regular))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(devToolsTab == id ? Color.accentColor.opacity(0.16) : Color.clear)
                            .foregroundColor(devToolsTab == id ? .accentColor : .secondary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    automation.consoleLogs.removeAll()
                    automation.networkLogs.removeAll()
                } label: {
                    Image(systemName: "trash").font(.system(size: 10)).foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear Console & Network Logs")
                
                Button { showDevTools = false } label: {
                    Image(systemName: "xmark").font(.system(size: 10))
                }.buttonStyle(.borderless)
            }.padding(8)
            
            Divider()
            
            if devToolsTab == "console" {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if automation.consoleLogs.isEmpty {
                                Text("No console output yet.")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(8)
                            } else {
                                ForEach(automation.consoleLogs) { entry in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text(entry.level.uppercased())
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(entry.level == "error" ? .red : (entry.level == "warn" ? .orange : .blue))
                                            .frame(width: 44, alignment: .leading)
                                        Text(entry.message)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(entry.level == "error" ? .red : .primary)
                                            .textSelection(.enabled)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    
                    Divider()
                    
                    HStack(spacing: 6) {
                        Text(">")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentColor)
                        TextField("Evaluate JavaScript in page...", text: $jsReplInput, onCommit: {
                            let script = jsReplInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !script.isEmpty else { return }
                            jsReplInput = ""
                            Task {
                                let res = (try? await automation.evalJS(script, target: "browser")) ?? "Error evaluating JS"
                                automation.consoleLogs.append(BrowserConsoleEntry(level: "info", message: "> \(script)\n← \(res)", source: "repl", timestamp: Date()))
                            }
                        })
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                }
            } else if devToolsTab == "network" {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if automation.networkLogs.isEmpty {
                            Text("No fetch/XHR network requests recorded yet.")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(8)
                        } else {
                            ForEach(automation.networkLogs) { req in
                                HStack(spacing: 6) {
                                    Text(req.method)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 38, alignment: .leading)
                                    Text("\(req.status)")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundColor(req.status >= 400 || req.status == 0 ? .red : .green)
                                        .frame(width: 30, alignment: .leading)
                                    Text("\(req.durationMs)ms")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 48, alignment: .trailing)
                                    Text(req.url)
                                        .font(.system(size: 10, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                ScrollView {
                    Text(pageSource.isEmpty ? "Loading..." : pageSource)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                }.background(Color(nsColor: .textBackgroundColor))
            }
        }.frame(minWidth: 320)
    }
    
    // MARK: - Actions
    private func navigateTo(_ input: String) {
        var urlString = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.contains("://") {
            if urlString.contains(".") && !urlString.contains(" ") {
                urlString = "https://\(urlString)"
            } else {
                urlString = "https://www.google.com/search?q=\(urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)"
            }
        }
        updateTab { $0.url = urlString }
        urlInput = urlString
        appState.browserURL = urlString
        NotificationCenter.default.post(name: .browserNavigate, object: urlString)
    }
    
    private func addNewTab() {
        let tab = BrowserTab(url: "https://www.google.com", title: "New Tab")
        appState.browserTabs.append(tab)
        appState.browserActiveTab = appState.browserTabs.count - 1
        urlInput = tab.url
        NotificationCenter.default.post(name: .browserNavigate, object: tab.url)
    }
    
    private func closeTab(id: UUID) {
        guard appState.browserTabs.count > 1 else { return }
        guard let index = appState.browserTabs.firstIndex(where: { $0.id == id }) else { return }
        appState.browserTabs.remove(at: index)
        if appState.browserActiveTab >= appState.browserTabs.count {
            appState.browserActiveTab = max(0, appState.browserTabs.count - 1)
        }
        urlInput = currentTabURL
        NotificationCenter.default.post(name: .browserNavigate, object: currentTabURL)
    }
    
    private func switchTab(id: UUID) {
        guard let index = appState.browserTabs.firstIndex(where: { $0.id == id }) else { return }
        appState.browserActiveTab = index
        urlInput = currentTabURL
        NotificationCenter.default.post(name: .browserNavigate, object: currentTabURL)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let browserNavigate = Notification.Name("browserNavigate")
    static let browserGoBack = Notification.Name("browserGoBack")
    static let browserGoForward = Notification.Name("browserGoForward")
    static let browserReload = Notification.Name("browserReload")
    static let browserStop = Notification.Name("browserStop")
}

// MARK: - WKWebView Container (NSViewRepresentable)

struct WebViewContainer: NSViewRepresentable {
    let urlString: String
    var onTitleChange: (String) -> Void = { _ in }
    var onURLChange: (String) -> Void = { _ in }
    var onLoadingChange: (Bool) -> Void = { _ in }
    var onNavChange: (Bool, Bool) -> Void = { _, _ in }
    var onSourceFetched: (String) -> Void = { _ in }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // 1. Persist Session (Cookies, Local Storage, Logins)
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        // 2. Allow media/video playback automatically
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        
        // 3. Bypass Bot/Captcha checking + Attach MCP Telemetry Interceptor
        let antiBotScript = WKUserScript(source: """
            Object.defineProperty(navigator, 'webdriver', { get: () => false });
            Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en', 'th'] });
            Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3] });
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(antiBotScript)
        IDEBrowserAutomationService.shared.attachTelemetry(to: config)
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        
        // Custom user agent to look like a standard Mac Safari
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        
        IDEBrowserAutomationService.shared.activeBrowserWebView = webView
        context.coordinator.webView = webView
        context.coordinator.setupObservers()
        context.coordinator.setupNotifications()
        
        // Load initial URL
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Navigation is handled via NotificationCenter
    }
    
    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mcBrowserBridge")
        webView.configuration.userContentController.removeAllUserScripts()
        if IDEBrowserAutomationService.shared.activeBrowserWebView === webView {
            IDEBrowserAutomationService.shared.activeBrowserWebView = nil
        }
        webView.loadHTMLString("", baseURL: nil)
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebViewContainer
        weak var webView: WKWebView?
        private var titleObserver: NSKeyValueObservation?
        private var urlObserver: NSKeyValueObservation?
        private var loadingObserver: NSKeyValueObservation?
        
        init(_ parent: WebViewContainer) {
            self.parent = parent
        }
        
        func setupObservers() {
            guard let webView = webView else { return }
            
            titleObserver = webView.observe(\.title) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.parent.onTitleChange(wv.title ?? "")
                }
            }
            
            urlObserver = webView.observe(\.url) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.parent.onURLChange(wv.url?.absoluteString ?? "")
                    self?.parent.onNavChange(wv.canGoBack, wv.canGoForward)
                }
            }
            
            loadingObserver = webView.observe(\.isLoading) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.parent.onLoadingChange(wv.isLoading)
                }
            }
        }
        
        func setupNotifications() {
            NotificationCenter.default.addObserver(self, selector: #selector(handleNavigate(_:)), name: .browserNavigate, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleGoBack), name: .browserGoBack, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleGoForward), name: .browserGoForward, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleReload), name: .browserReload, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleStop), name: .browserStop, object: nil)
        }
        
        @objc func handleNavigate(_ notification: Notification) {
            guard let urlString = notification.object as? String,
                  let url = URL(string: urlString) else { return }
            webView?.load(URLRequest(url: url))
        }
        
        @objc func handleGoBack() { webView?.goBack() }
        @objc func handleGoForward() { webView?.goForward() }
        @objc func handleReload() { webView?.reload() }
        @objc func handleStop() { webView?.stopLoading() }
        
        // WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onNavChange(webView.canGoBack, webView.canGoForward)
            // Fetch page source for dev tools
            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
                if let html = result as? String {
                    DispatchQueue.main.async {
                        self?.parent.onSourceFetched(html)
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Open target=_blank in same webview
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
        
        // WKUIDelegate — handle window.open / new window
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
