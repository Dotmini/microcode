import SwiftUI
import WebKit

// ==========================================
// IDE Browser — Native Apple WebKit
// Full-featured browser inside MicroCode IDE
// ==========================================

struct IDEBrowserView: View {
    @EnvironmentObject var appState: AppState
    @State private var urlInput: String = "https://microcode.dotmini.net"
    @State private var showBookmarks = false
    @State private var showHistory = false
    @State private var showDevTools = false
    @State private var pageSource = ""
    @State private var newTabURL = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            browserTabBar
            
            Divider()
            
            // Navigation bar
            navigationBar
            
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
                ForEach(Array(appState.browserTabs.enumerated()), id: \.element.id) { idx, tab in
                    HStack(spacing: 6) {
                        if tab.isLoading {
                            ProgressView().scaleEffect(0.4).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "globe").font(.system(size: 9)).foregroundColor(.secondary)
                        }
                        Text(tab.title.isEmpty ? "New Tab" : tab.title)
                            .font(.system(size: 10)).lineLimit(1).frame(maxWidth: 120)
                        
                        if appState.browserTabs.count > 1 {
                            Button { closeTab(idx) } label: {
                                Image(systemName: "xmark").font(.system(size: 7))
                            }.buttonStyle(.borderless)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(idx == appState.browserActiveTab ? Color.accentColor.opacity(0.12) : Color.clear)
                    .overlay(alignment: .bottom) {
                        if idx == appState.browserActiveTab {
                            Rectangle().fill(Color.accentColor).frame(height: 2)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { switchTab(idx) }
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
    
    // MARK: - Dev Tools Panel
    private var devToolsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "hammer").foregroundColor(.orange)
                Text("Page Source").font(.system(size: 11, weight: .medium))
                Spacer()
                Button { showDevTools = false } label: {
                    Image(systemName: "xmark").font(.system(size: 10))
                }.buttonStyle(.borderless)
            }.padding(8)
            
            Divider()
            
            ScrollView {
                Text(pageSource.isEmpty ? "Loading..." : pageSource)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }.background(Color(nsColor: .textBackgroundColor))
        }.frame(minWidth: 300)
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
    
    private func closeTab(_ index: Int) {
        guard appState.browserTabs.count > 1 else { return }
        appState.browserTabs.remove(at: index)
        if appState.browserActiveTab >= appState.browserTabs.count {
            appState.browserActiveTab = appState.browserTabs.count - 1
        }
        urlInput = currentTabURL
        NotificationCenter.default.post(name: .browserNavigate, object: currentTabURL)
    }
    
    private func switchTab(_ index: Int) {
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
        
        // 3. Bypass Bot/Captcha checking
        let antiBotScript = WKUserScript(source: """
            Object.defineProperty(navigator, 'webdriver', { get: () => false });
            Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en', 'th'] });
            Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3] });
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(antiBotScript)
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        
        // Custom user agent to look like a standard Mac Safari
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        
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
