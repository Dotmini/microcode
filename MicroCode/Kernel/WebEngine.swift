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
        let webView = WKWebView(frame: .zero, configuration: config)
        
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        // Load initial content
        loadContent(in: webView)
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Handle trigger updates
        if refreshTrigger {
            webView.reload()
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
        
        // Handle URL/Content changes if needed (complex logic omitted for brevity)
    }
    
    private func loadContent(in webView: WKWebView) {
        if let url = url {
            webView.load(URLRequest(url: url))
        } else if let html = htmlContent {
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebBrowserView
        
        init(_ parent: WebBrowserView) {
            self.parent = parent
        }
        
        // Navigation Started
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }
        
        // Navigation Finished
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
    }
}
