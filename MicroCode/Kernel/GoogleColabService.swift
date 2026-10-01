//
//  GoogleColabService.swift
//  MicroCode
//
//  Enterprise-grade integration for Google Colab Cloud GPU compute in Cell Mode.
//  Coordinates 1-Click Cloudflare/Jupyter bridge and real-time GPU kernel execution.
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import Foundation
import SwiftUI
import AppKit

enum ColabConnectionStatus: Equatable {
    case disconnected
    case connecting(message: String)
    case connected(gpuType: String)
    case error(String)
    
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    
    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }
    
    var displayText: String {
        switch self {
        case .disconnected: return "Offline"
        case .connecting(let msg): return msg
        case .connected(let gpu): return "Online • \(gpu)"
        case .error(let msg): return "Error: \(msg)"
        }
    }
    
    var statusColor: Color {
        switch self {
        case .disconnected: return Color.secondary
        case .connecting: return Color.orange
        case .connected: return Color.green
        case .error: return Color.red
        }
    }
}

@MainActor
class GoogleColabService: ObservableObject {
    static let shared = GoogleColabService()
    
    @Published var status: ColabConnectionStatus = .disconnected
    
    var isConnecting: Bool { status.isConnecting }
    var isConnected: Bool { status.isConnected }
    
    // Connection Settings
    @Published var activeColabURL: String = "https://colab.research.google.com"
    @Published var colabSessionToken: String = ""
    @Published var jupyterEndpoint: String = ""
    
    // Telemetry
    @Published var detectedGPU: String = "NVIDIA Tesla T4"
    @Published var gpuMemory: String = "15.0 GB GDDR6"
    @Published var systemRAM: String = "12.7 GB Available"
    @Published var isTPUAvailable: Bool = false
    
    // Heartbeat & Diagnostics
    @Published var antiIdleKeepAlive: Bool = true
    @Published var lastKeepAliveTime: Date? = nil
    @Published var showingColabSheet: Bool = false
    @Published var connectionLogs: [String] = []
    
    // Active Jupyter Client for real-time WebSocket communication
    private var activeJupyterClient: JupyterClient?
    private var keepAliveTimer: Timer?
    
    // MARK: - 1-Click Bridge Starter Code
    
    /// The exact Python code snippet that user runs in Colab to spawn the bridge & Jupyter server (Turbo High-Speed)
    static let bridgeStarterCode: String = """
    # 🚀 MicroCode Google Colab GPU Bridge (Turbo High-Speed)
    import sys, os, subprocess, time, urllib.request

    # 1. Fast conditional dependency check (skip pip if already installed)
    try:
        import pycloudflared
    except ImportError:
        print("⚡ Installing pycloudflared (one-time setup)...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pycloudflared"])
        import pycloudflared

    # 2. Spawn lightweight Jupyter Server on port 8888 if not already running
    token = "mc_" + os.urandom(8).hex()
    server_cmd = [
        "jupyter", "server",
        "--ip=127.0.0.1",
        "--port=8888",
        f"--ServerApp.token={token}",
        "--ServerApp.allow_origin=*",
        "--ServerApp.disable_check_xsrf=True",
        "--ServerApp.open_browser=False",
        "--ServerApp.root_dir=/content"
    ]
    subprocess.Popen(server_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # Quick health wait (max 3s)
    for _ in range(30):
        try:
            req = urllib.request.Request("http://127.0.0.1:8888/api", headers={"Authorization": f"Token {token}"})
            with urllib.request.urlopen(req, timeout=0.5) as r:
                if r.status in (200, 403):
                    break
        except Exception:
            time.sleep(0.1)

    # 3. Create Cloudflare Tunnel
    tunnel = pycloudflared.try_cloudflare(port=8888).tunnel
    session_link = f"{tunnel}/?token={token}"
    deep_link = f"microcode://colab?endpoint={tunnel}&token={token}"

    print(f"\\n=======================================================")
    print(f"🚀 MicroCode Bridge URL: {session_link}")
    print(f"=======================================================\\n")

    try:
        from IPython.display import HTML, display
        card_html = f'''
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', Roboto, sans-serif; background: #000000; color: #ffffff; border: 1px solid #333333; border-radius: 12px; padding: 18px; max-width: 520px; box-shadow: 0 4px 20px rgba(0,0,0,0.5);">
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px;">
                <div style="font-weight: 700; font-size: 15px; color: #ffffff; display: flex; align-items: center; gap: 8px;">
                    <span style="display: inline-block; width: 10px; height: 10px; border-radius: 50%; background: #22c55e;"></span>
                    MicroCode GPU Bridge Ready
                </div>
                <span style="font-size: 11px; color: #888888; background: #1a1a1a; padding: 3px 8px; border-radius: 6px; border: 1px solid #2a2a2a;">Colab Cloud GPU</span>
            </div>

            <div style="font-size: 12px; color: #aaaaaa; margin-bottom: 10px;">
                Click anywhere on the link box or click Copy Link below:
            </div>

            <!-- 1-Click Copy Input Field -->
            <div style="position: relative; margin-bottom: 14px;">
                <input id="colab-link-input" type="text" readonly value="{session_link}"
                    onclick="this.focus(); this.select(); document.execCommand('copy'); var b=document.getElementById('copied-banner'); b.style.display='block'; setTimeout(function(){{ b.style.display='none'; }}, 3000);"
                    style="width: 100%; box-sizing: border-box; background: #111111; color: #22c55e; border: 1px solid #333333; border-radius: 8px; padding: 10px 12px; font-family: monospace; font-size: 12px; cursor: pointer; outline: none;"
                    title="Click to copy link"
                />
                <div id="copied-banner" style="display: none; position: absolute; right: 10px; top: 9px; background: #22c55e; color: #000000; font-size: 11px; font-weight: 700; padding: 2px 8px; border-radius: 5px;">
                    ✓ Copied!
                </div>
            </div>

            <!-- Action Buttons -->
            <div style="display: flex; gap: 10px;">
                <button onclick="var inp=document.getElementById('colab-link-input'); inp.focus(); inp.select(); document.execCommand('copy'); var b=document.getElementById('copied-banner'); b.style.display='block'; setTimeout(function(){{ b.style.display='none'; }}, 3000);"
                    style="flex: 1; background: #ffffff; color: #000000; font-weight: 700; font-size: 13px; padding: 10px 16px; border-radius: 8px; border: none; cursor: pointer; text-align: center;">
                    📋 1-Click Copy Link
                </button>
                <a href="{deep_link}" target="_top"
                    style="flex: 1; background: #1f1f1f; color: #ffffff; font-weight: 600; font-size: 13px; padding: 10px 16px; border-radius: 8px; border: 1px solid #444444; text-decoration: none; text-align: center; display: flex; align-items: center; justify-content: center;">
                    🚀 Open MicroCode
                </a>
            </div>

            <div style="margin-top: 10px; font-size: 11px; color: #888888; text-align: center;">
                💡 Once copied, switch back to MicroCode — it detects and connects instantly!
            </div>
        </div>
        '''
        display(HTML(card_html))
    except Exception:
        pass
    """
    
    // MARK: - Resilient Endpoint & Token Parser
    
    /// Parses Colab endpoint and token from any arbitrary string (deep link, full URL, terminal output, or markdown)
    static func parseColabEndpointAndToken(from input: String) -> (endpoint: String, token: String)? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        
        // Ignore if it's the python starter code snippet itself
        if text.contains("!pip install") || text.contains("MicroCode Google Colab GPU Bridge") || text.contains("try_cloudflare(port=") {
            return nil
        }
        
        var endpoint = ""
        var token = ""
        
        // 1. Deep Link format: microcode://colab?endpoint=...&token=...
        if (text.hasPrefix("microcode://") || text.hasPrefix("codetuner://")),
           let url = URL(string: text),
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            endpoint = comps.queryItems?.first(where: { $0.name.lowercased() == "endpoint" || $0.name.lowercased() == "url" })?.value ?? ""
            token = comps.queryItems?.first(where: { $0.name.lowercased() == "token" })?.value ?? ""
        }
        
        // 2. Extract URL from text using regex
        if endpoint.isEmpty {
            let pattern = #"(https?://[a-zA-Z0-9.\-_]+(?::\d+)?(?:/[^\s"'<>]*)?)"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsText = text as NSString
                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
                for match in matches {
                    let candidate = nsText.substring(with: match.range)
                    if candidate.contains("trycloudflare.com") || candidate.contains("token=") || candidate.contains(":8888") {
                        endpoint = candidate
                        break
                    } else if endpoint.isEmpty && (candidate.hasPrefix("http://") || candidate.hasPrefix("https://")) {
                        endpoint = candidate
                    }
                }
            }
        }
        
        // 3. Fallback for raw HTTP string
        if endpoint.isEmpty && (text.hasPrefix("http://") || text.hasPrefix("https://")) {
            endpoint = text.components(separatedBy: .whitespacesAndNewlines).first ?? text
        }
        
        guard !endpoint.isEmpty else { return nil }
        
        // 4. Extract token from URL query params
        if let url = URL(string: endpoint), let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let tokenVal = comps.queryItems?.first(where: { $0.name.lowercased() == "token" })?.value, !tokenVal.isEmpty {
                token = tokenVal
            }
            if let scheme = comps.scheme, let host = comps.host {
                let portStr = comps.port != nil ? ":\(comps.port!)" : ""
                endpoint = "\(scheme)://\(host)\(portStr)"
            }
        }
        
        // 5. Extract token from surrounding text if not in URL
        if token.isEmpty {
            let tokenPattern = #"(?:token[=:\s]+|token\s*=\s*)([a-zA-Z0-9_]+)"#
            if let tRegex = try? NSRegularExpression(pattern: tokenPattern, options: [.caseInsensitive]) {
                let nsText = text as NSString
                if let match = tRegex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
                    if match.numberOfRanges > 1 {
                        token = nsText.substring(with: match.range(at: 1))
                    }
                }
            }
            if token.isEmpty {
                let mcPattern = #"\b(mc_[a-fA-F0-9]{8,32})\b"#
                if let mcRegex = try? NSRegularExpression(pattern: mcPattern, options: []) {
                    let nsText = text as NSString
                    if let match = mcRegex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
                        token = nsText.substring(with: match.range(at: 1))
                    }
                }
            }
        }
        
        // 6. Strip trailing slashes
        while endpoint.hasSuffix("/") {
            endpoint.removeLast()
        }
        
        guard endpoint.hasPrefix("http://") || endpoint.hasPrefix("https://") else {
            return nil
        }
        
        return (endpoint: endpoint, token: token)
    }
    
    private init() {
        self.jupyterEndpoint = UserDefaults.standard.string(forKey: "microcode_colab_endpoint") ?? ""
        self.colabSessionToken = UserDefaults.standard.string(forKey: "microcode_colab_token") ?? ""
        if UserDefaults.standard.object(forKey: "microcode_colab_anti_idle") == nil {
            self.antiIdleKeepAlive = true
            UserDefaults.standard.set(true, forKey: "microcode_colab_anti_idle")
        } else {
            self.antiIdleKeepAlive = UserDefaults.standard.bool(forKey: "microcode_colab_anti_idle")
        }
        
        startKeepAliveTimer()
        setupActiveAppObserver()
    }
    
    // MARK: - Connect to Colab Jupyter Bridge
    
    func connectToColab(endpoint: String, token: String) async {
        var rawEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        var rawToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Comprehensive extraction: automatically parse URL & token even from messy inputs
        if let parsed = Self.parseColabEndpointAndToken(from: rawEndpoint) {
            rawEndpoint = parsed.endpoint
            if rawToken.isEmpty {
                rawToken = parsed.token
            }
        }
        
        // Clean trailing slash
        while rawEndpoint.hasSuffix("/") {
            rawEndpoint.removeLast()
        }
        
        guard rawEndpoint.hasPrefix("http://") || rawEndpoint.hasPrefix("https://") else {
            status = .error("Invalid URL. Must begin with http:// or https://")
            appendLog("[ERR] Invalid endpoint URL: \(rawEndpoint)")
            return
        }
        
        self.jupyterEndpoint = rawEndpoint
        self.colabSessionToken = rawToken
        UserDefaults.standard.set(rawEndpoint, forKey: "microcode_colab_endpoint")
        UserDefaults.standard.set(rawToken, forKey: "microcode_colab_token")
        
        status = .connecting(message: "Connecting to Colab Session…")
        appendLog("[CONN] Connecting to Colab: \(rawEndpoint)")
        
        // Step 1: Health check against /api
        guard let apiURL = URL(string: "\(rawEndpoint)/api") else {
            status = .error("Malformed URL: \(rawEndpoint)")
            appendLog("[ERR] Malformed URL")
            return
        }
        
        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8.0
        if !rawToken.isEmpty {
            request.setValue("Token \(rawToken)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                status = .error("No HTTP response received from Colab endpoint.")
                appendLog("[ERR] No response from \(rawEndpoint)")
                return
            }
            
            if http.statusCode == 403 {
                status = .error("Authentication failed. Please verify the Token from your Colab cell.")
                appendLog("[AUTH_FAIL] 403 Forbidden. Invalid or missing token.")
                return
            }
            
            if http.statusCode != 200 {
                status = .error("Unexpected response HTTP \(http.statusCode) from Colab endpoint.")
                appendLog("[ERR] HTTP \(http.statusCode)")
                return
            }
            
            appendLog("[HTTP] API verified. Connecting Jupyter WebSocket…")
            
            // Step 2: Initialize JupyterClient with fast-path kernel reuse
            let client = JupyterClient(endpoint: rawEndpoint, token: rawToken)
            self.activeJupyterClient = client
            
            status = .connecting(message: "Initializing Python 3 Kernel…")
            let kernelID = try await client.startKernel(name: "python3")
            appendLog("[KERNEL] Started/reused kernel [\(kernelID)]")
            
            try client.connectWebSocket(kernelID: kernelID)
            try await client.waitUntilReady()
            appendLog("[WS] WebSocket handshake established.")
            
            // Step 3: Instant Connect Transition (< 500ms total latency)
            status = .connected(gpuType: self.detectedGPU)
            self.lastKeepAliveTime = Date()
            appendLog("[READY] Connected to Google Colab Cloud GPU: \(self.detectedGPU)")
            
            // Step 4: Asynchronously probe real hardware in background without blocking UI
            Task.detached(priority: .utility) { [weak self] in
                await self?.probeHardwareSpecs()
            }
            
        } catch {
            status = .error("Connection failed: \(error.localizedDescription)")
            appendLog("[ERR] Connection failure: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 1-Click Zero-Friction Launch & Auto-Connect
    
    @Published var isListeningForSession: Bool = false
    private var clipboardPollTimer: Timer?
    private var clipboardPollCount = 0

    func launchAndAutoConnect() {
        copyBridgeCodeToClipboard()
        openColabInBrowser()
        startListeningForClipboardSession()
    }

    func startListeningForClipboardSession() {
        isListeningForSession = true
        clipboardPollCount = 0
        clipboardPollTimer?.invalidate()
        
        appendLog("[LISTEN] Auto-detecting Colab session on clipboard…")
        
        // 1. Check immediately right away!
        if checkAndConnectFromClipboardIfValid() {
            return
        }
        
        // 2. Schedule fast, reliable 0.5s timer in .common RunLoop mode so it never stalls
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] t in
            guard let self = self else { return }
            self.clipboardPollCount += 1
            
            if self.checkAndConnectFromClipboardIfValid() {
                t.invalidate()
                return
            }
            
            // Timeout after 180 seconds
            if self.clipboardPollCount > 360 {
                t.invalidate()
                self.isListeningForSession = false
                self.appendLog("[AUTO] Auto-connect timed out. You can paste the link manually.")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.clipboardPollTimer = timer
    }

    @discardableResult
    func checkAndConnectFromClipboardIfValid() -> Bool {
        guard let current = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !current.isEmpty else {
            return false
        }
        
        // Parse endpoint and token using resilient parser
        guard let parsed = Self.parseColabEndpointAndToken(from: current) else {
            return false
        }
        
        // Don't trigger if already connected or connecting to this exact endpoint
        if (status.isConnected || status.isConnecting) && jupyterEndpoint == parsed.endpoint {
            return false
        }
        
        stopListeningForClipboardSession()
        appendLog("[AUTO] Detected Colab link from clipboard: \(parsed.endpoint)")
        Task { @MainActor in
            await self.connectToColab(endpoint: parsed.endpoint, token: parsed.token)
        }
        return true
    }

    private func setupActiveAppObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.isListeningForSession || !self.status.isConnected {
                self.checkAndConnectFromClipboardIfValid()
            }
        }
    }

    func stopListeningForClipboardSession() {
        clipboardPollTimer?.invalidate()
        isListeningForSession = false
        appendLog("[LISTEN] Cancelled clipboard listening.")
    }

    func connectWithSingleLink(_ link: String) async {
        await connectToColab(endpoint: link, token: "")
    }

    func connectFromClipboard() async {
        if !checkAndConnectFromClipboardIfValid() {
            if let clip = NSPasteboard.general.string(forType: .string), !clip.isEmpty {
                await connectWithSingleLink(clip)
            }
        }
    }

    func disconnect() {
        stopListeningForClipboardSession()
        if let client = activeJupyterClient {
            Task {
                await client.stopKernel()
            }
        }
        activeJupyterClient = nil
        status = .disconnected
        appendLog("[DISC] Session disconnected.")
    }
    
    // MARK: - Code Execution
    
    func execute(
        code: String,
        language: String = "python",
        progress: @escaping (String) -> Void
    ) async throws -> String {
        // Auto-reconnect if we have a saved endpoint but socket dropped
        if !status.isConnected || activeJupyterClient?.isLive != true {
            if !jupyterEndpoint.isEmpty {
                progress("⏳ Reconnecting to Google Colab Cloud GPU…\n")
                await connectToColab(endpoint: jupyterEndpoint, token: colabSessionToken)
            }
        }
        
        guard let client = activeJupyterClient, client.isLive else {
            let advice = """
            ⚠️ Google Colab Cloud GPU is not connected.
            
            Quick Setup (3 Steps):
            1. In the Notebook toolbar, click 'Colab Runtime' (or the Colab status pill).
            2. Click 'Copy Bridge Code' and run it in Google Colab.
            3. Paste the generated URL & Token, then click 'Connect'.
            
            (Tip: To run code locally on your Mac instead, switch Compute Target to 'Local (CPU)' or 'Apple Silicon (MLX / Metal)' in the top dropdown).
            """
            progress(advice)
            throw NSError(
                domain: "GoogleColabService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No active Google Colab session."]
            )
        }
        
        progress("⏵ [Colab Cloud GPU: \(detectedGPU)] Executing…\n")
        
        return try await withCheckedThrowingContinuation { continuation in
            let settled = NSLock()
            var done = false
            func finish(_ block: () -> Void) {
                settled.lock(); defer { settled.unlock() }
                guard !done else { return }
                done = true
                block()
            }
            
            let watchdog = Task {
                try? await Task.sleep(nanoseconds: 60 * 60 * 1_000_000_000)
                finish {
                    continuation.resume(
                        throwing: NSError(
                            domain: "GoogleColabService",
                            code: 408,
                            userInfo: [NSLocalizedDescriptionKey: "Colab kernel execution timed out."]
                        )
                    )
                }
            }
            
            Task {
                do {
                    try await client.executeCode(code: code, onOutput: { output in
                        DispatchQueue.main.async {
                            progress(output)
                        }
                    }, onComplete: { message in
                        watchdog.cancel()
                        self.lastKeepAliveTime = Date()
                        finish {
                            continuation.resume(returning: message.isEmpty ? "Execution complete." : message)
                        }
                    }, onError: { error in
                        watchdog.cancel()
                        finish {
                            continuation.resume(throwing: error)
                        }
                    })
                } catch {
                    watchdog.cancel()
                    finish {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    // MARK: - Telemetry & Hardware Probing
    
    func probeHardwareSpecs() async {
        guard let client = activeJupyterClient, client.isLive else { return }
        
        let probeScript = """
        import subprocess, sys
        try:
            out = subprocess.check_output(["nvidia-smi", "--query-gpu=gpu_name,memory.total,memory.free", "--format=csv,noheader,nounits"], text=True).strip()
            parts = [p.strip() for p in out.split(",")]
            print(f"COLAB_GPU:{parts[0]}|{parts[1]}|{parts[2]}")
        except Exception:
            try:
                import torch_xla
                print("COLAB_GPU:Google TPU|0|0")
            except Exception:
                print("COLAB_GPU:Standard Cloud CPU|0|0")
        """
        
        var probeOutput = ""
        try? await client.executeCode(code: probeScript, onOutput: { out in
            probeOutput += out
        }, onComplete: { _ in }, onError: { _ in })
        
        parseProbeOutput(probeOutput)
    }
    
    private func parseProbeOutput(_ probeOutput: String) {
        if let marker = probeOutput.range(of: "COLAB_GPU:") {
            let info = String(probeOutput[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = info.components(separatedBy: "|")
            if parts.count >= 3 {
                self.detectedGPU = parts[0]
                if let total = Double(parts[1]), let free = Double(parts[2]), total > 0 {
                    self.gpuMemory = String(format: "%.1f GB / %.1f GB Free", free / 1024.0, total / 1024.0)
                } else {
                    self.gpuMemory = "Allocated"
                }
            } else if !parts.isEmpty {
                self.detectedGPU = parts[0]
            }
            
            if self.detectedGPU.contains("TPU") {
                self.isTPUAvailable = true
            }
            
            self.status = .connected(gpuType: self.detectedGPU)
        } else {
            self.detectedGPU = "NVIDIA Cloud GPU"
            self.gpuMemory = "Active"
        }
    }
    
    // MARK: - Keep-Alive Heartbeat
    
    private func startKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 240.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.antiIdleKeepAlive, self.status.isConnected else { return }
                self.sendKeepAlivePing()
            }
        }
    }
    
    private func sendKeepAlivePing() {
        guard let client = activeJupyterClient, client.isLive else { return }
        let pingCode = "# MicroCode Persistent Keep-Alive\n_ = 1 + 1\n"
        Task {
            _ = try? await self.execute(code: pingCode, progress: { _ in })
            self.lastKeepAliveTime = Date()
            self.appendLog("[PING] Heartbeat transmitted. Session timeout reset.")
        }
    }
    
    // MARK: - Browser & Session Helpers
    
    func openColabInBrowser(notebook: NotebookModel? = nil) {
        var targetURL = URL(string: "https://colab.research.google.com#create=true")!
        if let nb = notebook {
            if let _ = exportNotebookToTemporaryIPynb(nb) {
                targetURL = URL(string: "https://colab.research.google.com#create=true") ?? targetURL
            }
        }
        NSWorkspace.shared.open(targetURL)
        appendLog("[WEB] Opened Google Colab in default browser.")
    }
    
    func copyBridgeCodeToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.bridgeStarterCode, forType: .string)
        appendLog("[CLIPBOARD] Copied Colab Bridge starter snippet to clipboard.")
    }
    
    func appendLog(_ message: String) {
        connectionLogs.append("[\(Date().formatted(date: .omitted, time: .standard))] \(message)")
        if connectionLogs.count > 100 {
            connectionLogs.removeFirst(connectionLogs.count - 100)
        }
    }
    
    // MARK: - IPynb Export Utility
    
    func exportNotebookToTemporaryIPynb(_ notebook: NotebookModel) -> URL? {
        var ipynbCells: [[String: Any]] = []
        for cell in notebook.cells {
            let cellType = cell.type == .markdown ? "markdown" : "code"
            var cDict: [String: Any] = [
                "cell_type": cellType,
                "metadata": [:],
                "source": cell.content.components(separatedBy: "\n").map { $0 + "\n" }
            ]
            if cell.type == .code {
                cDict["execution_count"] = cell.executionCount
                cDict["outputs"] = []
            }
            ipynbCells.append(cDict)
        }
        
        let ipynbRoot: [String: Any] = [
            "nbformat": 4,
            "nbformat_minor": 5,
            "metadata": [
                "colab": ["name": notebook.name],
                "kernelspec": [
                    "name": "python3",
                    "display_name": "Python 3"
                ],
                "language_info": [
                    "name": "python"
                ]
            ],
            "cells": ipynbCells
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: ipynbRoot, options: .prettyPrinted) else { return nil }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(notebook.name).ipynb")
        try? data.write(to: tempURL)
        return tempURL
    }
}
