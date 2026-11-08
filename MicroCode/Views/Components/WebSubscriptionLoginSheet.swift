//
//  WebSubscriptionLoginSheet.swift
//  MicroCode
//
//  In-app interactive web authentication sheet for non-technical users.
//  Loads the official web portal (chatgpt.com, claude.ai, gemini.google.com, etc.),
//  automatically intercepts session cookies and local storage tokens via WKHTTPCookieStore,
//  and auto-connects the subscription account into SubscriptionAuthManager with 0 manual steps.
//

import SwiftUI
import WebKit

struct WebSubscriptionLoginSheet: View {
    let provider: SubscriptionProviderType
    var onConnected: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    
    @State private var webView: WKWebView?
    @State private var isLoading: Bool = true
    @State private var isScanning: Bool = false
    @State private var pageTitle: String = ""
    @State private var currentURL: URL?
    @State private var canGoBack: Bool = false
    @State private var statusMessage: String = "Please sign in to your account..."
    @State private var detectedUser: String? = nil
    @State private var isSuccess: Bool = false
    @State private var autoDismissCountdown: Int = 2
    @State private var forceScanTrigger: (() -> Void)? = nil
    @State private var copilotUserCode: String? = nil
    @State private var copilotErrorMessage: String? = nil
    @State private var manualKeyInput: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                AIProviderBrandIcon(provider: provider.providerIcon, size: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Connect \(provider.displayName)")
                            .font(.system(size: 13, weight: .semibold))
                        
                        if isSuccess {
                            Text("AUTHENTICATED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(4)
                        } else if isScanning || isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    
                    Text(statusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(isSuccess ? .green : .secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Back Button
                if canGoBack && !isSuccess {
                    Button(action: { webView?.goBack() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                // Reload Button
                Button(action: { webView?.reload() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSuccess)
                
                // Cancel Button (Secondary, neutral style)
                if !isSuccess {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                // Primary Action Button: "Connect Account" / "✓ Done"
                if isSuccess {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Done")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                } else {
                    Button(action: {
                        if provider == .copilot {
                            startCopilotFlow()
                        } else {
                            if tryConnectManualOrClipboardKey(allowClipboardFallback: true) {
                                return
                            }
                            isScanning = true
                            statusMessage = "Scanning session & connecting..."
                            forceScanTrigger?()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if !isSuccess {
                                    isScanning = false
                                    if provider == .tokenme {
                                        statusMessage = "Copy your tm_... key from TokenMe Console → API keys, or paste it in the bar below."
                                    } else if provider.isAPIKeyBackedPortal {
                                        statusMessage = "Copy your API key from the console below (or open in Safari/Chrome), then click Paste & Connect."
                                    } else {
                                        statusMessage = "No active session cookie detected yet. Sign in below, then click Connect Account."
                                    }
                                }
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            if isScanning {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "link.badge.plus")
                                    .font(.system(size: 11))
                            }
                            Text(provider == .copilot ? "Request Code" : "Connect Account")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Quick API Key / Safari OAuth Bypass Bar for API-Key-Backed Portals (e.g. TokenMe Google/Discord Sign-In)
            if provider.isAPIKeyBackedPortal && !isSuccess {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "key.horizontal.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.cyan)
                        Text(provider == .tokenme
                             ? "TokenMe uses Google/Discord OAuth & Bearer Keys (tm_...). Open Console in your browser to copy a key, or paste directly:"
                             : "Google OAuth blocked in WebView? Open Console in your default browser, copy your API key, and paste below:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button(action: {
                            let url = provider == .tokenme
                                ? URL(string: "https://www.tokenme.limited")!
                                : provider.webLoginURL
                            NSWorkspace.shared.open(url)
                            statusMessage = "Opened \(provider.shortLabel) in browser — copy your API key, then click Paste & Connect."
                        }) {
                            Label("Open in Browser", systemImage: "safari")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    HStack(spacing: 8) {
                        SecureField(
                            provider == .tokenme
                                ? "Paste TokenMe API key (tm_...) or cURL command..."
                                : "Paste \(provider.shortLabel) API key or Bearer token...",
                            text: $manualKeyInput
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5, design: .monospaced))
                        .onSubmit {
                            _ = tryConnectManualOrClipboardKey(allowClipboardFallback: false)
                        }
                        
                        Button(action: {
                            _ = tryConnectManualOrClipboardKey(allowClipboardFallback: true)
                        }) {
                            Label(manualKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Paste & Connect" : "Connect Key", systemImage: "doc.on.clipboard.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        
                        let savedByok = (UserDefaults.standard.string(forKey: "\(provider.aiProviderID)_api_key") ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !savedByok.isEmpty && !SubscriptionAuthManager.isCorruptedToken(savedByok) {
                            Button(action: {
                                handleTokenDetected(token: savedByok, user: "\(provider.shortLabel) Subscription")
                            }) {
                                Label("Use Saved API Key", systemImage: "checkmark.seal.fill")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color.accentColor.opacity(0.06))
                
                Divider()
            }
            
            // Copilot Device Code Prompt Banner
            if provider == .copilot, let code = copilotUserCode, !code.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GITHUB COPILOT VERIFICATION CODE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Text(code)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                        statusMessage = "Code \(code) copied! Paste into GitHub below."
                    }) {
                        Label("Copy Code", systemImage: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Text("Paste code into GitHub below & Click 'Continue'")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.08))
                
                Divider()
            }
            
            // WebKit WebView Container
            ZStack {
                SubscriptionWKWebViewRepresentable(
                    provider: provider,
                    webView: $webView,
                    isLoading: $isLoading,
                    pageTitle: $pageTitle,
                    currentURL: $currentURL,
                    canGoBack: $canGoBack,
                    copilotUserCode: $copilotUserCode,
                    onTokenDetected: { token, user in
                        handleTokenDetected(token: token, user: user)
                    },
                    bindScanTrigger: { trigger in
                        self.forceScanTrigger = trigger
                    }
                )
                
                if isSuccess {
                    Color.black.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)
                        .transition(.opacity)
                    
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.green)
                        
                        Text("Connected Successfully!")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        
                        if let user = detectedUser, !user.isEmpty {
                            Text("Logged in as \(user)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.green.opacity(0.9))
                        }
                        
                        Text(
                            provider == .copilot
                                ? "Copilot access verified. Your credential is saved in Keychain."
                                : (SubscriptionAuthManager.shared.cliBridgeBinaryPath(for: provider) != nil
                                    ? "Credential saved in Keychain & linked to your local \(provider.shortLabel) CLI Bridge (Zero API Charges)."
                                    : "Credential saved in Keychain and added to your Unified Subscription Pool.")
                        )
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)
                        
                        Text("Closing in \(autoDismissCountdown)s...")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(24)
                    .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
                    .cornerRadius(14)
                    .shadow(radius: 20)
                }
            }
            
            // Bottom Info Footer
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                Text("MicroCode stores session authentication securely in macOS Keychain / Local Storage. Zero API per-token charges.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                Spacer()
                
                if let user = detectedUser, !user.isEmpty {
                    Text(user)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green)
                    Text("•")
                        .foregroundColor(.secondary)
                }
                
                if let url = currentURL {
                    Text(url.host ?? "")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
        }
        .frame(minWidth: 720, idealWidth: 840, maxWidth: 960, minHeight: 640, idealHeight: 740, maxHeight: 860)
        .onAppear {
            if provider == .copilot {
                startCopilotFlow()
            } else if provider == .tokenme {
                statusMessage = "Copy your tm_... key from TokenMe Console (or click Paste & Connect / Use Saved API Key)."
            }
        }
    }
    
    @discardableResult
    private func tryConnectManualOrClipboardKey(allowClipboardFallback: Bool) -> Bool {
        let typed = manualKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            let normalized = provider.isAPIKeyBackedPortal
                ? SubscriptionAuthManager.normalizeBearerOrCurlToken(typed)
                : typed
            if normalized.count >= 16 && !normalized.contains(" ") && !SubscriptionAuthManager.isCorruptedToken(normalized) {
                handleTokenDetected(token: normalized, user: "\(provider.shortLabel) Subscription")
                return true
            } else {
                statusMessage = "Invalid token format — paste your real API key (e.g. tm_...)."
                return false
            }
        }
        guard allowClipboardFallback, provider.isAPIKeyBackedPortal,
              let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clip.isEmpty else {
            return false
        }
        let normalized = SubscriptionAuthManager.normalizeBearerOrCurlToken(clip)
        guard !normalized.isEmpty,
              !normalized.contains(" "),
              !normalized.contains("\n"),
              !normalized.hasPrefix("http"),
              !SubscriptionAuthManager.isCorruptedToken(normalized) else {
            return false
        }
        let knownPrefixes = ["tm_", "tkm_", "tk_", "tokenme_", "perch-", "sk-or-v1-", "gsk_", "pplx-", "xai-", "csk-", "fw_", "nvapi-", "sk-"]
        let matchesPrefix = knownPrefixes.contains { normalized.hasPrefix($0) }
        let looksLikeCurlExtraction = clip.contains("curl ") && clip.lowercased().contains("authorization:")
        if matchesPrefix || looksLikeCurlExtraction {
            handleTokenDetected(token: normalized, user: "\(provider.shortLabel) Subscription")
            return true
        }
        return false
    }
    
    private func startCopilotFlow() {
        guard !isSuccess else { return }
        isScanning = true
        statusMessage = "Requesting device code from GitHub..."
        SubscriptionAuthManager.shared.startCopilotDeviceFlow(
            onUserCode: { code, verifyUrl in
                self.copilotUserCode = code
                self.statusMessage = "Code \(code) copied to clipboard! Authorize below."
                self.isScanning = false
                if let wv = self.webView {
                    wv.load(URLRequest(url: verifyUrl))
                }
            },
            onSuccess: { account in
                handleTokenDetected(token: account.sessionToken, user: account.emailOrUser)
            },
            onError: { err in
                self.isScanning = false
                self.copilotErrorMessage = err
                self.statusMessage = "GitHub Copilot: \(err)"
            }
        )
    }
    
    private func handleTokenDetected(token: String, user: String?) {
        guard !isSuccess else { return }
        
        let accountUser = user ?? detectedUser ?? "\(provider.shortLabel) User"
        self.detectedUser = accountUser
        
        SubscriptionAuthManager.shared.saveAccount(
            provider: provider,
            emailOrUser: accountUser,
            sessionToken: token,
            source: "Web Sign-In (1-Click)"
        )
        SubscriptionAuthManager.shared.activeProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: "subscriptionActiveProvider")
        UserDefaults.standard.set("subscription", forKey: "aiKeyMode")
        UserDefaults.standard.set(provider.aiProviderID, forKey: "aiProvider")
        if let firstModel = provider.modelInfos.first?.modelID {
            UserDefaults.standard.set(firstModel, forKey: "aiModel")
        }
        
        isSuccess = true
        isScanning = false
        statusMessage = "Authenticated as \(accountUser)! Closing..."
        onConnected?()
        
        // Auto-dismiss countdown
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if autoDismissCountdown > 1 {
                autoDismissCountdown -= 1
            } else {
                timer.invalidate()
                dismiss()
            }
        }
    }
}

// MARK: - NSViewRepresentable for WKWebView

private struct SubscriptionWKWebViewRepresentable: NSViewRepresentable {
    let provider: SubscriptionProviderType
    @Binding var webView: WKWebView?
    @Binding var isLoading: Bool
    @Binding var pageTitle: String
    @Binding var currentURL: URL?
    @Binding var canGoBack: Bool
    @Binding var copilotUserCode: String?
    let onTokenDetected: (String, String?) -> Void
    let bindScanTrigger: (@escaping () -> Void) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        // Modern Safari User Agent for maximum compatibility with Google / Cloudflare / Anthropic logins
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15 MicroCode/2.0"
        
        // Hook navigator.clipboard.writeText & copy events on API-key portals (e.g. playground.opentyphoon.ai)
        // so clicking "Copy Key" in a Next.js modal immediately triggers 1-Click Auto-Connect.
        switch provider {
        case .openrouter, .groq, .mistral, .kimi, .perplexity, .perch, .tokenme, .typhoon,
             .qwen, .grok, .cerebras, .together, .fireworks, .minimax, .nvidia:
            let clipboardHookJS = """
            (() => {
                try {
                    if (navigator.clipboard && navigator.clipboard.writeText) {
                        const origWrite = navigator.clipboard.writeText.bind(navigator.clipboard);
                        navigator.clipboard.writeText = function(text) {
                            if (typeof text === 'string' && text.trim().length >= 20) {
                                window.__mcCopiedToken = text.trim();
                            }
                            return origWrite(text);
                        };
                    }
                    document.addEventListener('copy', () => {
                        const sel = String(window.getSelection ? window.getSelection() : '').trim();
                        if (sel.length >= 20) { window.__mcCopiedToken = sel; }
                    }, true);
                } catch (e) {}
            })();
            """
            let script = WKUserScript(source: clipboardHookJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            config.userContentController.addUserScript(script)
        default:
            break
        }
        
        let wv = WKWebView(frame: .zero, configuration: config)
        if provider == .aipass {
            wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        } else {
            wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        }
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        
        // Listen to real-time cookie changes
        config.websiteDataStore.httpCookieStore.add(context.coordinator)
        
        DispatchQueue.main.async {
            self.webView = wv
            self.bindScanTrigger {
                context.coordinator.scanAll(webView: wv)
            }
        }
        
        // Load target portal
        let request = URLRequest(url: provider.webLoginURL)
        wv.load(request)
        
        // Start polling scanner on main RunLoop (.common modes)
        context.coordinator.startPolling(webView: wv)
        
        // Trigger initial scan in case cookies already exist
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            context.coordinator.scanAll(webView: wv)
        }
        
        return wv
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Handled via bindings
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        let parent: SubscriptionWKWebViewRepresentable
        private var pollTimer: Timer?
        private var isFound = false
        
        init(_ parent: SubscriptionWKWebViewRepresentable) {
            self.parent = parent
            super.init()
        }
        
        deinit {
            pollTimer?.invalidate()
        }
        
        func startPolling(webView: WKWebView) {
            let timer = Timer(timeInterval: 1.2, repeats: true) { [weak self, weak webView] _ in
                guard let self = self, let wv = webView, !self.isFound else { return }
                self.scanAll(webView: wv)
            }
            RunLoop.main.add(timer, forMode: .common)
            self.pollTimer = timer
        }
        
        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            guard !isFound else { return }
            if let wv = parent.webView {
                scanAll(webView: wv)
            } else {
                checkCookies(in: cookieStore, webView: nil)
            }
        }
        
        func scanAll(webView: WKWebView) {
            guard !isFound else { return }
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            checkCookies(in: cookieStore, webView: webView)
            checkJavaScript(in: webView)
        }
        
        func checkCookies(in cookieStore: WKHTTPCookieStore, webView: WKWebView?) {
            guard !isFound else { return }
            
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self = self, !self.isFound else { return }
                
                switch self.parent.provider {
                case .chatgpt:
                    // Only accept a direct JWT cookie (eyJ...); encrypted NextAuth JWE cookies (__Secure-next-auth.session-token)
                    // are exchanged via fetch('/api/auth/session') in checkJavaScript for the real accessToken JWT.
                    var sessionToken: String? = nil
                    if let single = cookies.first(where: { $0.name == "oai-client-auth-token" && $0.value.hasPrefix("eyJ") }) {
                        sessionToken = single.value
                    }
                    
                    // Extract user email or name from oai-client-auth-info cookie
                    var userNameOrEmail: String? = nil
                    if let infoCookie = cookies.first(where: { $0.name == "oai-client-auth-info" }) {
                        let raw = infoCookie.value.removingPercentEncoding ?? infoCookie.value
                        if let data = raw.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let userObj = json["user"] as? [String: Any] {
                            let email = userObj["email"] as? String
                            let name = userObj["name"] as? String
                            if let email = email, !email.isEmpty {
                                userNameOrEmail = email
                            } else if let name = name, !name.isEmpty {
                                userNameOrEmail = name
                            }
                        }
                    }
                    
                    if let token = sessionToken, !token.isEmpty {
                        self.isFound = true
                        DispatchQueue.main.async {
                            self.parent.onTokenDetected(token, userNameOrEmail ?? "ChatGPT Plus User")
                        }
                        return
                    }
                    if let webView = webView {
                        DispatchQueue.main.async {
                            self.checkJavaScript(in: webView)
                        }
                    }
                    
                case .claude:
                    let claudeChunks = cookies
                        .filter { $0.name.hasPrefix("sessionKey") }
                        .sorted { $0.name < $1.name }
                    if !claudeChunks.isEmpty {
                        let token = claudeChunks.map(\.value).joined()
                        if !token.isEmpty {
                            self.isFound = true
                            DispatchQueue.main.async {
                                self.parent.onTokenDetected(token, "Claude Pro Account")
                            }
                            return
                        }
                    }
                    
                case .gemini:
                    if let cookie = cookies.first(where: { ($0.name == "__Secure-1PSID" || $0.name == "__Secure-3PSID" || $0.name == "SID") && !$0.value.isEmpty }) {
                        self.isFound = true
                        DispatchQueue.main.async {
                            self.parent.onTokenDetected(cookie.value, "Google One Subscriber")
                        }
                        return
                    }
                    
                case .deepseek:
                    if let cookie = cookies.first(where: { ($0.name == "userToken" || $0.name == "auth_token") && !SubscriptionAuthManager.isCorruptedToken($0.value) }) {
                        self.isFound = true
                        DispatchQueue.main.async {
                            self.parent.onTokenDetected(cookie.value, "DeepSeek Web User")
                        }
                        return
                    }
                    
                case .copilot:
                    // Handled exclusively by GitHub Device Flow to obtain official OAuth token (client 01ab8ac9400c4e429b23)
                    break
                    
                case .glm:
                    if let cookie = cookies.first(where: { $0.name == "token" && !SubscriptionAuthManager.isCorruptedToken($0.value) }) {
                        self.isFound = true
                        DispatchQueue.main.async {
                            self.parent.onTokenDetected(cookie.value, "GLM BigModel User")
                        }
                        return
                    }
                    
                case .aipass:
                    let aipassCookies = cookies.filter { $0.domain.contains("aipass.net") }
                    if let sessionCookie = aipassCookies.first(where: { $0.name == "__Secure-ai_passport_auth.session_token" && !$0.value.isEmpty }) {
                        self.isFound = true
                        let cookieHeader = aipassCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                        let finalToken = cookieHeader.isEmpty ? "__Secure-ai_passport_auth.session_token=\(sessionCookie.value)" : cookieHeader
                        DispatchQueue.main.async {
                            self.parent.onTokenDetected(finalToken, "TH-AI Passport Member")
                        }
                        return
                    }
                    
                case .openrouter, .groq, .mistral, .kimi, .perplexity, .perch, .tokenme, .typhoon,
                     .qwen, .grok, .cerebras, .together, .fireworks, .minimax, .nvidia:
                    if let webView = webView {
                        DispatchQueue.main.async {
                            self.checkJavaScript(in: webView)
                        }
                    }
                }
            }
        }
        
        func checkJavaScript(in webView: WKWebView) {
            guard !isFound else { return }
            
            let jsScript: String
            switch parent.provider {
            case .chatgpt:
                jsScript = """
                (async () => {
                    try {
                        const res = await fetch('/api/auth/session');
                        if (res.ok) {
                            const data = await res.json();
                            if (data && typeof data.accessToken === 'string' && data.accessToken.length > 20) {
                                return JSON.stringify({
                                    token: data.accessToken,
                                    user: data.user?.email || data.user?.name || 'ChatGPT Plus User'
                                });
                            }
                        }
                    } catch(e) {}
                    try {
                        const at = localStorage.getItem('accessToken');
                        if (at && at.length > 20 && !at.startsWith('{')) {
                            return JSON.stringify({ token: at, user: 'ChatGPT User' });
                        }
                    } catch(e) {}
                    return null;
                })()
                """
                
            case .claude:
                jsScript = """
                (() => {
                    try {
                        const m = document.cookie.match(/sessionKey=([^;]+)/);
                        if (m && m[1]) return JSON.stringify({ token: m[1], user: 'Claude Pro' });
                    } catch(e) {}
                    return null;
                })()
                """
                
            case .deepseek:
                jsScript = """
                (() => {
                    try {
                        for (const key of ['userToken', 'user_token', 'auth_token', 'token', 'd_token']) {
                            const raw = localStorage.getItem(key) || sessionStorage.getItem(key);
                            if (!raw || raw === 'null' || raw === 'undefined') continue;
                            try {
                                const parsed = JSON.parse(raw);
                                if (parsed && typeof parsed === 'object') {
                                    const val = parsed.value || parsed.token || parsed.access_token;
                                    if (typeof val === 'string' && val.length > 16 && val !== 'null') {
                                        return JSON.stringify({ token: val, user: 'DeepSeek User' });
                                    }
                                    continue;
                                }
                            } catch(e) {}
                            const trimmed = String(raw).trim();
                            if (!trimmed.startsWith('{') && trimmed.length > 16 && !trimmed.includes('"value":null')) {
                                return JSON.stringify({ token: trimmed, user: 'DeepSeek User' });
                            }
                        }
                    } catch(e) {}
                    return null;
                })()
                """
                
            case .gemini:
                jsScript = """
                (() => {
                    try {
                        const m1 = document.cookie.match(/__Secure-1PSID=([^;]+)/);
                        if (m1 && m1[1]) return JSON.stringify({ token: m1[1], user: 'Gemini Advanced' });
                        const m3 = document.cookie.match(/__Secure-3PSID=([^;]+)/);
                        if (m3 && m3[1]) return JSON.stringify({ token: m3[1], user: 'Gemini Advanced' });
                        const ms = document.cookie.match(/(?:^|;\\s*)SID=([^;]+)/);
                        if (ms && ms[1]) return JSON.stringify({ token: ms[1], user: 'Google Account' });
                    } catch(e) {}
                    return null;
                })()
                """
                
            case .glm:
                jsScript = """
                (() => {
                    try {
                        const tok = localStorage.getItem('token');
                        if (tok && tok !== 'null' && !tok.startsWith('{')) return JSON.stringify({ token: tok, user: 'GLM User' });
                    } catch(e) {}
                    return null;
                })()
                """
                
            case .openrouter, .groq, .mistral, .kimi, .perplexity, .perch, .tokenme, .typhoon,
                 .qwen, .grok, .cerebras, .together, .fireworks, .minimax, .nvidia:
                let userLabel = parent.provider.shortLabel
                let isTokenMe = parent.provider == .tokenme ? "true" : "false"
                jsScript = """
                (() => {
                    try {
                        const isTokenMe = \(isTokenMe);
                        const patterns = [
                            /perch-[A-Za-z0-9_-]{20,}/,
                            /tokenme_[A-Za-z0-9_-]{16,}/,
                            /tkm_[A-Za-z0-9_-]{20,}/,
                            /tm_[A-Za-z0-9_-]{20,}/,
                            /tk_[A-Za-z0-9_-]{20,}/,
                            /sk-or-v1-[A-Za-z0-9]{32,}/,
                            /gsk_[A-Za-z0-9]{32,}/,
                            /pplx-[A-Za-z0-9]{24,}/,
                            /xai-[A-Za-z0-9]{24,}/,
                            /csk-[A-Za-z0-9]{24,}/,
                            /fw_[A-Za-z0-9]{20,}/,
                            /nvapi-[A-Za-z0-9_-]{24,}/,
                            /sk-[A-Za-z0-9_-]{28,}/
                        ];
                        if (typeof window.__mcCopiedToken === 'string' && window.__mcCopiedToken.length >= 20) {
                            const copied = window.__mcCopiedToken.trim();
                            if (!copied.includes('...') && !copied.includes('•••') && !copied.includes('***') && !copied.includes('$TOKENME_API_KEY')) {
                                for (const pat of patterns) {
                                    const m = copied.match(pat);
                                    if (m && m[0]) {
                                        return JSON.stringify({ token: m[0], user: '\(userLabel) Member' });
                                    }
                                }
                                if (isTokenMe && !copied.startsWith('http') && /^[A-Za-z0-9._-]{24,200}$/.test(copied)) {
                                    return JSON.stringify({ token: copied, user: '\(userLabel) Member' });
                                }
                            }
                        }
                        const inputs = Array.from(document.querySelectorAll('input, textarea, code, pre, span, p, td, div'));
                        for (const el of inputs) {
                            if (el.tagName === 'DIV' && el.children && el.children.length > 0) continue;
                            const val = (el.value || el.textContent || '').trim();
                            if (!val || val.length > 220 || val.includes('...') || val.includes('•••') || val.includes('***')) continue;
                            for (const pat of patterns) {
                                const m = val.match(pat);
                                if (m && m[0]) {
                                    return JSON.stringify({ token: m[0], user: '\(userLabel) Member' });
                                }
                            }
                        }
                    } catch(e) {}
                    return null;
                })()
                """
                
            case .copilot, .aipass:
                jsScript = ""
            }
            
            guard !jsScript.isEmpty else { return }
            
            webView.evaluateJavaScript(jsScript) { [weak self] result, error in
                guard let self = self, !self.isFound else { return }
                guard let jsonStr = result as? String, !jsonStr.isEmpty, jsonStr != "null" else { return }
                
                if let data = jsonStr.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let token = dict["token"] as? String,
                   !SubscriptionAuthManager.isCorruptedToken(token) {
                    self.isFound = true
                    let user = dict["user"] as? String
                    DispatchQueue.main.async {
                        self.parent.onTokenDetected(token, user)
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
                self.parent.currentURL = webView.url
                self.parent.canGoBack = webView.canGoBack
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.pageTitle = webView.title ?? ""
                self.parent.currentURL = webView.url
                self.parent.canGoBack = webView.canGoBack
            }
            if self.parent.provider == .copilot,
               let code = self.parent.copilotUserCode, !code.isEmpty,
               let url = webView.url, url.absoluteString.contains("github.com/login/device") {
                let js = """
                (function() {
                    const input = document.getElementById('user_code') || document.querySelector('input[name="user_code"]');
                    if (input && !input.value) {
                        input.value = '\(code)';
                        input.dispatchEvent(new Event('input', { bubbles: true }));
                        input.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                })();
                """
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
            scanAll(webView: webView)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
        
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
