//
//  Kernel/WebEngine.swift
//  MicroCode
//
//  User Space: Web Engine
//  High-performance web rendering engine based on WebKit (Safari Core).
//  Provides in-app browsing capabilities and HTML previewing.
//

import SwiftUI
import WebKit

/// Core Web Engine Kernel Module
class WebEngine: ObservableObject {
    static let shared = WebEngine()
    
    // Shared process pool for efficiency (cookie sharing, caching across views)
    let processPool = WKProcessPool()
    
    // Security: Default Content Security Policy
    // Enforce safe practices for previews
    let defaultCSP = "default-src 'self' 'unsafe-inline' https:; img-src 'self' https: data:;"
    
    /// Create a configured WKWebViewConfiguration
    func createConfiguration(enableJavaScript: Bool = true) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.processPool = processPool
        
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = enableJavaScript
        config.defaultWebpagePreferences = prefs
        
        // Developer extras for inspection (like Inspect Element)
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        return config
    }
    
    /// Clear all browser cache and cookies
    func clearCache() {
        let websiteDataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: websiteDataTypes, modifiedSince: Date(timeIntervalSince1970: 0)) {
            print("🧹 WebEngine Kernel: Cache & Cookies Cleared")
        }
    }
    
    /// Pre-warm the engine
    func warmUp() {
        // Create a dummy webview to initialize WebKit sub-processes
        DispatchQueue.main.async {
            let _ = WKWebView(frame: .zero, configuration: self.createConfiguration())
        }
    }
}

// MARK: - SwiftUI Bridge

/// A production-grade Web Browser View powered by the WebEngine Kernel
struct WebBrowserView: NSViewRepresentable {
    let url: URL?
    let htmlContent: String?
    
    // Observable state bindings
    @Binding var title: String
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    
    // Explicit action to trigger from outside (hacky via binding or closure)
    // For cleaner architecture, we'd use a ViewModel/Coordinator pattern observed by updateNSView
    @Binding var refreshTrigger: Bool
    @Binding var goBackTrigger: Bool
    @Binding var goForwardTrigger: Bool
    
    init(url: URL? = nil, 
         htmlContent: String? = nil,
         title: Binding<String> = .constant(""),
         isLoading: Binding<Bool> = .constant(false),
         canGoBack: Binding<Bool> = .constant(false),
         canGoForward: Binding<Bool> = .constant(false),
         refreshTrigger: Binding<Bool> = .constant(false),
         goBackTrigger: Binding<Bool> = .constant(false),
         goForwardTrigger: Binding<Bool> = .constant(false)) {
        self.url = url
        self.htmlContent = htmlContent
        self._title = title
        self._isLoading = isLoading
        self._canGoBack = canGoBack
        self._canGoForward = canGoForward
        self._refreshTrigger = refreshTrigger
        self._goBackTrigger = goBackTrigger
        self._goForwardTrigger = goForwardTrigger
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WebEngine.shared.createConfiguration()
        IDEBrowserAutomationService.shared.attachTelemetry(to: config)
        let webView = WKWebView(frame: .zero, configuration: config)
        
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        IDEBrowserAutomationService.shared.activePreviewWebView = webView
        
        // Load initial content
        loadContent(in: webView)
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Handle trigger updates
        if refreshTrigger {
            PreviewHotReloadEngine.shared.reloadWebViewPreservingScroll(webView)
            DispatchQueue.main.async { refreshTrigger = false }
        }
        
        if goBackTrigger {
            if webView.canGoBack { webView.goBack() }
            DispatchQueue.main.async { goBackTrigger = false }
        }
        
        if goForwardTrigger {
            if webView.canGoForward { webView.goForward() }
            DispatchQueue.main.async { goForwardTrigger = false }
        }
        
        // Handle URL changes dynamically
        if let targetURL = url, targetURL != context.coordinator.lastLoadedURL {
            context.coordinator.lastLoadedURL = targetURL
            loadURL(targetURL, in: webView)
        }
    }
    
    private func loadContent(in webView: WKWebView) {
        if let url = url {
            loadURL(url, in: webView)
        } else if let html = htmlContent {
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
    
    private func loadURL(_ targetURL: URL, in webView: WKWebView) {
        if targetURL.isFileURL {
            // Allow read access to root so all parent/sibling workspace assets (CSS, JS, images, fonts) load cleanly
            let readAccessDir = URL(fileURLWithPath: "/")
            webView.loadFileURL(targetURL, allowingReadAccessTo: readAccessDir)
        } else {
            webView.load(URLRequest(url: targetURL))
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mcBrowserBridge")
        webView.configuration.userContentController.removeAllUserScripts()
        if IDEBrowserAutomationService.shared.activePreviewWebView === webView {
            IDEBrowserAutomationService.shared.activePreviewWebView = nil
        }
        webView.loadHTMLString("", baseURL: nil)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebBrowserView
        var lastLoadedURL: URL?
        
        init(_ parent: WebBrowserView) {
            self.parent = parent
            self.lastLoadedURL = parent.url
        }
        
        // Navigation Started
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
                IDEBrowserAutomationService.shared.clearRuntimeIssues()
            }
        }
        
        // Navigation Finished
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Restore scroll position after hot reload if preserved in sessionStorage
            let restoreScrollJS = """
            (function() {
                try {
                    var sx = sessionStorage.getItem('__mc_scroll_x');
                    var sy = sessionStorage.getItem('__mc_scroll_y');
                    if (sy !== null) {
                        window.scrollTo(parseInt(sx || '0', 10), parseInt(sy, 10));
                        sessionStorage.removeItem('__mc_scroll_x');
                        sessionStorage.removeItem('__mc_scroll_y');
                    }
                } catch (e) {}
            })();
            """
            webView.evaluateJavaScript(restoreScrollJS, completionHandler: nil)

            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.title = webView.title ?? "Untitled"
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
            }
        }
        
        // Navigation Failed
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
            print("WebEngine Error: \(error.localizedDescription)")
        }
        
        // Provisional Navigation Failed (e.g. server down or connection refused)
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsErr = error as NSError
            guard nsErr.code != NSURLErrorCancelled else { return }
            let targetStr = (nsErr.userInfo[NSURLErrorFailingURLStringErrorKey] as? String) ?? lastLoadedURL?.absoluteString ?? "http://localhost:5173"
            DispatchQueue.main.async {
                self.parent.isLoading = false
                IDEBrowserAutomationService.shared.scanActivePorts()
            }
            print("WebEngine Provisional Navigation Error: \(error.localizedDescription)")
            let safeURL = targetStr.replacingOccurrences(of: "\"", with: "")
            let standbyHTML = """
            <!doctype html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <style>
            body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:#0d1016;color:#e4e8f0;font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:24px;box-sizing:border-box}
            .card{max-width:380px;width:100%;background:#151a24;border:1px solid rgba(255,255,255,0.09);border-radius:14px;padding:24px;text-align:center;box-shadow:0 16px 40px rgba(0,0,0,0.45)}
            .pulse{width:10px;height:10px;border-radius:50%;background:#38bdf8;display:inline-block;margin-right:8px;box-shadow:0 0 12px #38bdf8;animation:p 1.4s infinite ease-in-out}
            @keyframes p{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.35;transform:scale(.85)}}
            h3{margin:0 0 8px;font-size:15px;font-weight:600;display:flex;align-items:center;justify-content:center}
            p{margin:0 0 14px;font-size:12px;color:#8e98ac;line-height:1.5}
            code{background:rgba(56,189,248,0.12);color:#38bdf8;padding:3px 7px;border-radius:5px;font-family:ui-monospace,SFMono-Regular,monospace;font-size:11.5px}
            button{background:#2563eb;color:#fff;border:none;border-radius:8px;padding:8px 16px;font-size:12px;font-weight:600;cursor:pointer}
            button:hover{background:#1d4ed8}
            </style>
            </head>
            <body>
            <div class="card">
              <h3><span class="pulse"></span>Waiting for Local Dev Server</h3>
              <p>Auto-connecting to <code>\(safeURL)</code> as soon as your dev server starts listening…</p>
              <button onclick="window.location.replace('\(safeURL)')">Retry Now</button>
            </div>
            <script>
            const target = "\(safeURL)";
            if (target.startsWith("http")) {
              setInterval(async () => {
                try {
                  await fetch(target, { mode: "no-cors", cache: "no-store" });
                  window.location.replace(target);
                } catch (_) {}
              }, 1500);
            }
            </script>
            </body>
            </html>
            """
            webView.loadHTMLString(standbyHTML, baseURL: nil)
        }
    }
}
