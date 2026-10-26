//
//  PhoneCompanionService.swift
//  MicroCode
//
//  Zero-Setup Mobile Companion Server (LAN + Online HTTPS Quick Tunnel)
//  Allows users to scan a QR Code with their iPhone or Android camera to monitor,
//  chat with, and approve AI Agent tasks remotely with zero app installation.
//
//  Created by Dotmini Software
//

import Foundation
import Network
import AppKit
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins
import Darwin

// MARK: - Models

enum PhoneConnectionMode: String, CaseIterable, Identifiable {
    case lan = "lan"
    case online = "online"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .lan: return "Same Wi-Fi / LAN"
        case .online: return "Cellular / Online"
        }
    }
    
    var subtitle: String {
        switch self {
        case .lan: return "Instant (<2ms) • Same Wi-Fi or Personal Hotspot"
        case .online: return "4G / 5G / Any Network • Zero-Setup HTTPS Tunnel"
        }
    }
    
    var icon: String {
        switch self {
        case .lan: return "wifi"
        case .online: return "globe"
        }
    }
}

enum OnlineTunnelState: Equatable {
    case stopped
    case starting(String)
    case connected(url: String, provider: String)
    case failed(String)
}

struct ConnectedPhoneDevice: Identifiable, Equatable {
    let id: String
    var name: String
    var ipAddress: String
    var connectionVia: String // "LAN" or "Online"
    var firstConnectedAt: Date
    var lastSeenAt: Date
}

// MARK: - PhoneCompanionService

@MainActor
final class PhoneCompanionService: ObservableObject {
    static let shared = PhoneCompanionService()
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "microcode.phoneCompanion.enabled")
            if isEnabled {
                startServerIfNeeded()
                if connectionMode == .online {
                    startOnlineTunnel()
                }
            } else {
                stopOnlineTunnel()
                stopServer()
            }
        }
    }
    
    @Published var connectionMode: PhoneConnectionMode = .lan {
        didSet {
            UserDefaults.standard.set(connectionMode.rawValue, forKey: "microcode.phoneCompanion.mode")
            if connectionMode == .online && isEnabled {
                if case .connected = tunnelState {
                    // Already connected
                } else {
                    startOnlineTunnel()
                }
            }
            regenerateQRCode()
        }
    }
    
    @Published private(set) var isServerRunning: Bool = false
    @Published private(set) var listeningPort: UInt16 = 8470
    @Published private(set) var lanIPAddress: String = "127.0.0.1"
    @Published private(set) var allNetworkAddresses: [(interface: String, ip: String)] = []
    @Published private(set) var bonjourHostname: String = ""
    @Published private(set) var pairingToken: String = ""
    @Published private(set) var tunnelState: OnlineTunnelState = .stopped {
        didSet {
            regenerateQRCode()
        }
    }
    @Published private(set) var connectedDevices: [ConnectedPhoneDevice] = []
    @Published private(set) var qrCodeImage: NSImage? = nil
    @Published var selectedLANIP: String = "" {
        didSet {
            regenerateQRCode()
        }
    }
    
    /// Weak reference to AppState for reading active provider/model/workspace
    weak var appState: AppState?
    
    private var listener: NWListener?
    private var secondaryListener: NWListener?
    private let networkQueue = DispatchQueue(label: "com.dotmini.microcode.phone-companion", qos: .userInitiated)
    private var tunnelProcess: Process?
    private var networkRefreshTimer: Timer?
    private var lastGeneratedQRURL: String = ""
    private var cachedStateFingerprint: String = ""
    private var cachedStateData: Data = Data("{}".utf8)
    private var workspaceLanguageCache: [String: (primary: String, label: String, langs: [String])] = [:]
    private lazy var cachedMacName: String = {
        let raw = ProcessInfo.processInfo.hostName
            .replacingOccurrences(of: ".local", with: "")
            .replacingOccurrences(of: "-", with: " ")
        return raw.isEmpty ? "Mac" : raw
    }()
    private static let closedThoughtRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "(?is)<(?:thought|thinking|think)>([\\s\\S]*?)</(?:thought|thinking|think)>",
        options: []
    )
    
    private init() {
        self.isEnabled = false
        if let savedMode = UserDefaults.standard.string(forKey: "microcode.phoneCompanion.mode"),
           let mode = PhoneConnectionMode(rawValue: savedMode) {
            self.connectionMode = mode
        }
        if let savedToken = UserDefaults.standard.string(forKey: "microcode.phoneCompanion.token"), !savedToken.isEmpty {
            self.pairingToken = savedToken
        } else {
            let newToken = Self.generateSecureToken()
            self.pairingToken = newToken
            UserDefaults.standard.set(newToken, forKey: "microcode.phoneCompanion.token")
        }
    }
    
    // MARK: - URLs & QR Generation
    
    var activeLANHost: String {
        if !selectedLANIP.isEmpty {
            return selectedLANIP
        }
        if lanIPAddress != "127.0.0.1" {
            return lanIPAddress
        }
        if !bonjourHostname.isEmpty {
            return bonjourHostname
        }
        return "127.0.0.1"
    }
    
    var lanPairingURL: String {
        "http://\(activeLANHost):\(listeningPort)/?token=\(pairingToken)"
    }
    
    var onlinePairingURL: String? {
        if case .connected(let base, _) = tunnelState {
            let cleanBase = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "\(cleanBase)/?token=\(pairingToken)"
        }
        return nil
    }
    
    var activePairingURL: String {
        switch connectionMode {
        case .lan:
            return lanPairingURL
        case .online:
            return onlinePairingURL ?? lanPairingURL
        }
    }
    
    func rotatePairingToken() {
        let newToken = Self.generateSecureToken()
        pairingToken = newToken
        UserDefaults.standard.set(newToken, forKey: "microcode.phoneCompanion.token")
        connectedDevices.removeAll()
        regenerateQRCode()
    }
    
    private static func generateSecureToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 18)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    func regenerateQRCode() {
        let urlString = activePairingURL
        guard !urlString.isEmpty else {
            lastGeneratedQRURL = ""
            qrCodeImage = nil
            return
        }
        if urlString == lastGeneratedQRURL, qrCodeImage != nil {
            return
        }
        lastGeneratedQRURL = urlString
        
        let context = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false
        ])
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(urlString.utf8)
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage else {
            qrCodeImage = nil
            return
        }
        
        let scaleX: CGFloat = 10.0
        let scaleY: CGFloat = 10.0
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        if let cgImage = context.createCGImage(transformed, from: transformed.extent) {
            let size = NSSize(width: transformed.extent.width, height: transformed.extent.height)
            qrCodeImage = NSImage(cgImage: cgImage, size: size)
        }
    }
    
    // MARK: - Network Interface Discovery (Zero-Setup LAN / Hotspot / Tailscale)
    
    func refreshNetworkAddresses() {
        var found: [(interface: String, ip: String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        
        if getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr {
            var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
            while let current = ptr {
                let flags = Int32(current.pointee.ifa_flags)
                let isUp = (flags & IFF_UP) != 0
                let isLoopback = (flags & IFF_LOOPBACK) != 0
                
                if isUp && !isLoopback, let addr = current.pointee.ifa_addr {
                    if addr.pointee.sa_family == UInt8(AF_INET) {
                        let name = String(cString: current.pointee.ifa_name)
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(
                            addr,
                            socklen_t(addr.pointee.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            0,
                            NI_NUMERICHOST
                        ) == 0 {
                            let ip = String(cString: hostname)
                            if !ip.hasPrefix("169.254.") && !ip.isEmpty {
                                found.append((interface: name, ip: ip))
                            }
                        }
                    }
                }
                ptr = current.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        
        // Sort so en0 (Wi-Fi) and en1 come first, followed by bridge (Hotspot) and utun (Tailscale/VPN)
        found.sort { a, b in
            func rank(_ name: String, _ ip: String) -> Int {
                if name == "en0" { return 0 }
                if name == "en1" { return 1 }
                if name.hasPrefix("en") { return 2 }
                if name.hasPrefix("bridge") { return 3 }
                if ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.") { return 4 }
                return 5
            }
            return rank(a.interface, a.ip) < rank(b.interface, b.ip)
        }
        
        // Deduplicate by IP
        var unique: [(interface: String, ip: String)] = []
        var seenIPs = Set<String>()
        for item in found {
            if !seenIPs.contains(item.ip) {
                seenIPs.insert(item.ip)
                unique.append(item)
            }
        }
        
        let rawHost = ProcessInfo.processInfo.hostName
        let cleanHost = rawHost
            .replacingOccurrences(of: ".local", with: "")
            .replacingOccurrences(of: " ", with: "-")
        let newBonjour = cleanHost.isEmpty ? "" : "\(cleanHost).local"
        
        let newPrimaryIP = unique.first?.ip ?? "127.0.0.1"
        let changed = (newPrimaryIP != self.lanIPAddress) || (unique.map(\.ip) != self.allNetworkAddresses.map(\.ip))
        
        if changed {
            self.allNetworkAddresses = unique
            self.lanIPAddress = newPrimaryIP
        }
        if self.bonjourHostname != newBonjour {
            self.bonjourHostname = newBonjour
        }
        if selectedLANIP.isEmpty || !seenIPs.contains(selectedLANIP) {
            selectedLANIP = newPrimaryIP
        }
        if changed {
            regenerateQRCode()
        }
    }
    
    // MARK: - Embedded HTTP Companion Server (NWListener)
    
    func startServerIfNeeded() {
        guard isEnabled else { return }
        guard !isServerRunning && listener == nil else { return }
        refreshNetworkAddresses()
        startServer(onPort: 8470)
        regenerateQRCode()
    }
    
    private func startServer(onPort candidatePort: UInt16, attempt: Int = 0) {
        stopServer()
        
        guard let nwPort = NWEndpoint.Port(rawValue: candidatePort) else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        
        do {
            let newListener = try NWListener(using: params, on: nwPort)
            newListener.service = NWListener.Service(name: "MicroCode Companion", type: "_microcode-phone._tcp")
            
            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self = self, self.listener === newListener else { return }
                    switch state {
                    case .ready:
                        if let actualPort = newListener.port?.rawValue {
                            self.listeningPort = actualPort
                        }
                        self.isServerRunning = true
                        self.startMirrorListenerIfPossible(primaryPort: self.listeningPort)
                        if self.connectionMode == .online {
                            if case .connected = self.tunnelState {
                                // Already connected
                            } else {
                                self.startOnlineTunnel()
                            }
                        }
                        self.regenerateQRCode()
                    case .failed:
                        self.isServerRunning = false
                        newListener.cancel()
                        self.listener = nil
                        if attempt < 15 {
                            self.startServer(onPort: candidatePort + 1, attempt: attempt + 1)
                        }
                    case .cancelled:
                        self.isServerRunning = false
                    default:
                        break
                    }
                }
            }
            
            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }
            
            self.listener = newListener
            newListener.start(queue: networkQueue)
        } catch {
            if attempt < 15 {
                startServer(onPort: candidatePort + 1, attempt: attempt + 1)
            }
        }
    }
    
    /// Also binds the adjacent companion port (8471 when primary is 8470, or 8470 when primary is 8471)
    /// so existing mobile Safari tabs on either port continue working seamlessly across restarts.
    private func startMirrorListenerIfPossible(primaryPort: UInt16) {
        secondaryListener?.cancel()
        secondaryListener = nil
        let mirrorPort: UInt16 = (primaryPort == 8470) ? 8471 : 8470
        guard let nwPort = NWEndpoint.Port(rawValue: mirrorPort) else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        if let mirror = try? NWListener(using: params, on: nwPort) {
            mirror.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }
            mirror.start(queue: networkQueue)
            self.secondaryListener = mirror
        }
    }
    
    func stopServer() {
        listener?.cancel()
        listener = nil
        secondaryListener?.cancel()
        secondaryListener = nil
        isServerRunning = false
    }
    
    // MARK: - Zero-Setup Online HTTPS Tunnel (Cloudflare Quick Tunnel + SSH Fallback)
    
    func startOnlineTunnel() {
        stopOnlineTunnel()
        tunnelState = .starting("Initializing zero-setup HTTPS tunnel…")
        
        let port = Int(listeningPort)
        
        // Check for cloudflared binary first (fastest, highest reliability)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cloudflaredCandidates = [
            "/opt/homebrew/bin/cloudflared",
            "/usr/local/bin/cloudflared",
            "\(home)/Library/Application Support/MicroCode/bin/cloudflared"
        ]
        
        if let cfBin = cloudflaredCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            launchCloudflaredQuickTunnel(binaryPath: cfBin, port: port)
        } else {
            // Fallback to macOS built-in /usr/bin/ssh with localhost.run (100% zero install)
            launchSSHReverseTunnel(port: port)
        }
    }
    
    func stopOnlineTunnel() {
        if let proc = tunnelProcess, proc.isRunning {
            proc.terminate()
        }
        tunnelProcess = nil
        tunnelState = .stopped
    }
    
    private func launchCloudflaredQuickTunnel(binaryPath: String, port: Int) {
        tunnelState = .starting("Starting Cloudflare Quick Tunnel (HTTPS)…")
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = ["tunnel", "--url", "http://127.0.0.1:\(port)", "--no-autoupdate"]
        
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            
            // Match https://xxx-xxx.trycloudflare.com
            if let range = line.range(of: #"https://[a-zA-Z0-9-]+\.trycloudflare\.com"#, options: .regularExpression) {
                let publicURL = String(line[range])
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if case .connected = self.tunnelState { return }
                    self.tunnelState = .connected(url: publicURL, provider: "Cloudflare Quick Tunnel")
                }
            }
        }
        
        proc.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                guard let self = self, self.tunnelProcess === proc else { return }
                if case .starting = self.tunnelState {
                    // If cloudflared exited before connecting, auto-fallback to SSH tunnel
                    self.launchSSHReverseTunnel(port: port)
                } else if self.connectionMode == .online {
                    self.tunnelState = .stopped
                }
            }
        }
        
        do {
            try proc.run()
            self.tunnelProcess = proc
        } catch {
            launchSSHReverseTunnel(port: port)
        }
    }
    
    private func launchSSHReverseTunnel(port: Int) {
        tunnelState = .starting("Starting macOS Native SSH HTTPS Tunnel…")
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        proc.arguments = [
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ServerAliveInterval=30",
            "-o", "ExitOnForwardFailure=yes",
            "-R", "80:127.0.0.1:\(port)",
            "nokey@localhost.run"
        ]
        
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.standardInput = Pipe()
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            
            if let range = text.range(of: #"https://[a-zA-Z0-9-]+\.lhr\.life"#, options: .regularExpression) {
                let publicURL = String(text[range])
                Task { @MainActor [weak self] in
                    guard let self = self, self.tunnelProcess === proc else { return }
                    if case .connected = self.tunnelState { return }
                    self.tunnelState = .connected(url: publicURL, provider: "SSH Quick Tunnel")
                }
            }
        }
        
        proc.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                guard let self = self, self.tunnelProcess === proc else { return }
                if case .starting = self.tunnelState {
                    self.tunnelState = .failed("Could not establish online tunnel. Check internet connection or use Same Wi-Fi / LAN mode.")
                }
            }
        }
        
        do {
            try proc.run()
            self.tunnelProcess = proc
        } catch {
            tunnelState = .failed("Failed to launch tunnel: \(error.localizedDescription)")
        }
    }
    
    // MARK: - HTTP Connection Handling
    
    nonisolated private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: networkQueue)
        receiveHTTPRequest(on: connection, accumulated: Data())
    }
    
    nonisolated private func receiveHTTPRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }
            var buffer = accumulated
            if let content = content {
                buffer.append(content)
            }
            
            // Check if we have received the complete HTTP headers + body
            if let headerEndRange = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: 0..<headerEndRange.lowerBound)
                let headerString = String(data: headerData, encoding: .utf8) ?? ""
                let bodyStartIndex = headerEndRange.upperBound
                let currentBodyLength = buffer.count - bodyStartIndex
                
                var expectedContentLength = 0
                for line in headerString.components(separatedBy: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        let val = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                        expectedContentLength = Int(val) ?? 0
                    }
                }
                
                if currentBodyLength >= expectedContentLength || isComplete {
                    let bodyData = buffer.subdata(in: bodyStartIndex..<min(buffer.count, bodyStartIndex + expectedContentLength))
                    let remoteIP = Self.extractRemoteIP(from: connection)
                    Task { @MainActor in
                        let responseData = await self.processHTTPRequest(
                            headerString: headerString,
                            bodyData: bodyData,
                            remoteIP: remoteIP
                        )
                        connection.send(content: responseData, completion: .contentProcessed { _ in
                            connection.cancel()
                        })
                    }
                    return
                }
            }
            
            if isComplete || error != nil || buffer.count > 1_048_576 {
                connection.cancel()
                return
            }
            
            self.receiveHTTPRequest(on: connection, accumulated: buffer)
        }
    }
    
    nonisolated private static func extractRemoteIP(from connection: NWConnection) -> String {
        switch connection.endpoint {
        case .hostPort(let host, _):
            let raw = "\(host)"
            return raw.components(separatedBy: "%").first ?? raw
        default:
            return "Mobile Device"
        }
    }
    
    // MARK: - HTTP Router (@MainActor)
    
    private func processHTTPRequest(headerString: String, bodyData: Data, remoteIP: String) async -> Data {
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return makeHTTPResponse(status: "400 Bad Request", contentType: "text/plain", body: Data("Bad Request".utf8))
        }
        
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            return makeHTTPResponse(status: "400 Bad Request", contentType: "text/plain", body: Data("Bad Request".utf8))
        }
        
        let method = parts[0].uppercased()
        let rawTarget = parts[1]
        
        // Parse headers
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        
        let urlComponents = URLComponents(string: "http://localhost\(rawTarget)")
        let path = urlComponents?.path ?? "/"
        let queryItems = urlComponents?.queryItems ?? []
        
        // Extract token from query, X-Companion-Token header, or Cookie
        let queryToken = queryItems.first(where: { $0.name == "token" })?.value
        let headerToken = headers["x-companion-token"]
        let cookieToken: String? = {
            guard let cookieHeader = headers["cookie"] else { return nil }
            for pair in cookieHeader.components(separatedBy: ";") {
                let kv = pair.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
                if kv.count == 2 && kv[0] == "mc_token" {
                    return kv[1]
                }
            }
            return nil
        }()
        
        let suppliedToken = queryToken ?? headerToken ?? cookieToken ?? ""
        let isForwardedTunnel = (headers["cf-connecting-ip"] != nil || headers["x-forwarded-for"] != nil)
        let isDirectPrivateLAN = !isForwardedTunnel && (
            remoteIP == "127.0.0.1" ||
            remoteIP == "::1" ||
            remoteIP.hasPrefix("192.168.") ||
            remoteIP.hasPrefix("10.") ||
            remoteIP.hasPrefix("172.")
        )
        guard suppliedToken == pairingToken || isDirectPrivateLAN else {
            let unauthorizedHTML = """
            <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
            <title>MicroCode Companion — Scan QR Code</title>
            <style>body{background:#0d0f14;color:#f3f4f6;font-family:-apple-system,BlinkMacSystemFont,sans-serif;display:flex;align-items:center;justify-content:center;height:90vh;margin:0;padding:24px;text-align:center}
            .card{max-width:360px;background:#161922;border:1px solid rgba(255,255,255,0.1);border-radius:16px;padding:28px}
            h2{margin:0 0 10px;font-size:18px}p{color:#9ca3af;font-size:14px;line-height:1.5}</style></head>
            <body><div class="card"><h2>🔒 Session Token Expired or Missing</h2>
            <p>Please open <b>MicroCode → Settings → Connect with Phone</b> on your Mac and scan the QR Code again.</p></div></body></html>
            """
            return makeHTTPResponse(status: "401 Unauthorized", contentType: "text/html; charset=utf-8", body: Data(unauthorizedHTML.utf8))
        }
        
        // Record connected mobile device
        recordConnectedDevice(headers: headers, remoteIP: remoteIP)
        

        // Route endpoints
        switch (method, path) {
        case ("GET", "/"):
            let html = buildMobileCompanionHTML(token: pairingToken)
            let extraHeaders = ["Set-Cookie": "mc_token=\(pairingToken); Path=/; SameSite=Lax"]
            return makeHTTPResponse(status: "200 OK", contentType: "text/html; charset=utf-8", extraHeaders: extraHeaders, body: Data(html.utf8))
            
        case ("GET", "/api/state"):
            let statePayload = buildCompanionStateJSON()
            return makeHTTPResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: statePayload)
            
        case ("GET", "/api/models"):
            let models = buildAvailableModelsPayload()
            return makeJSONResponse(["ok": true, "models": models])
            
        case ("GET", "/api/icon/provider"):
            let provId = queryItems.first(where: { $0.name == "id" })?.value ?? "microcode"
            if let png = AIProviderBrandIcon.pngData(for: provId) {
                return makeHTTPResponse(
                    status: "200 OK",
                    contentType: "image/png",
                    extraHeaders: ["Cache-Control": "public, max-age=86400"],
                    body: png
                )
            }
            return makeHTTPResponse(status: "404 Not Found", contentType: "text/plain", body: Data())
            
        case ("POST", "/api/send"):
            if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
               let prompt = (json["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !prompt.isEmpty {
                let enqueueOnly = (json["enqueue"] as? Bool) ?? false
                dispatchRemotePrompt(prompt, enqueueOnly: enqueueOnly)
                return makeJSONResponse(["ok": true])
            }
            return makeJSONResponse(["ok": false, "error": "Empty prompt"], status: "400 Bad Request")
            
        case ("POST", "/api/model/select"):
            if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
               let mode = json["mode"] as? String,
               let provider = json["provider"] as? String,
               let modelId = json["modelId"] as? String {
                selectRemoteModel(mode: mode, provider: provider, modelId: modelId)
                return makeJSONResponse(["ok": true])
            }
            return makeJSONResponse(["ok": false, "error": "Invalid model payload"], status: "400 Bad Request")
            
        case ("POST", "/api/stop"):
            AgentService.shared.stopGeneration()
            ACPHostService.shared.stopActiveAgent()
            return makeJSONResponse(["ok": true])
            
        case ("POST", "/api/plan/approve"):
            ImplementationPlanManager.shared.approve()
            return makeJSONResponse(["ok": true])
            
        case ("POST", "/api/plan/reject"):
            ImplementationPlanManager.shared.reject()
            return makeJSONResponse(["ok": true])
            
        case ("POST", "/api/tool/approve"):
            ToolApprovalManager.shared.approve()
            return makeJSONResponse(["ok": true])
            
        case ("POST", "/api/tool/reject"):
            ToolApprovalManager.shared.reject()
            return makeJSONResponse(["ok": true])
            
        case ("POST", "/api/workspace/switch"):
            if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                let targetPath = (json["path"] as? String) ?? ""
                let sessionId = json["sessionId"] as? String
                switchRemoteWorkspace(path: targetPath, sessionId: sessionId)
                return makeJSONResponse(["ok": true])
            }
            return makeJSONResponse(["ok": false, "error": "Invalid workspace payload"], status: "400 Bad Request")
            
        case ("POST", "/api/session/switch"):
            if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
               let sessionId = json["sessionId"] as? String {
                switchRemoteSession(sessionId: sessionId)
                return makeJSONResponse(["ok": true])
            }
            return makeJSONResponse(["ok": false], status: "400 Bad Request")
            
        case ("POST", "/api/session/new"):
            let requestedPath = (try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any])?["projectPath"] as? String
            createRemoteSession(projectPath: requestedPath)
            return makeJSONResponse(["ok": true])
            
        default:
            return makeJSONResponse(["ok": false, "error": "Not found"], status: "404 Not Found")
        }
    }
    
    private func recordConnectedDevice(headers: [String: String], remoteIP: String) {
        let ua = headers["user-agent"] ?? ""
        let forwardedFor = headers["cf-connecting-ip"] ?? headers["x-forwarded-for"]
        let effectiveIP = forwardedFor?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? remoteIP
        let via = (forwardedFor != nil || effectiveIP == "127.0.0.1") ? "Online Tunnel" : "Same Wi-Fi / LAN"
        
        let deviceName: String = {
            if ua.contains("iPhone") { return "iPhone (iOS)" }
            if ua.contains("iPad") { return "iPad (iPadOS)" }
            if ua.contains("Android") { return "Android Phone" }
            if ua.contains("Macintosh") { return "Mac Browser" }
            return "Mobile Browser"
        }()
        
        let deviceId = "\(deviceName)-\(effectiveIP)"
        let now = Date()
        if let idx = connectedDevices.firstIndex(where: { $0.id == deviceId }) {
            connectedDevices[idx].lastSeenAt = now
            connectedDevices[idx].connectionVia = via
        } else {
            connectedDevices.insert(
                ConnectedPhoneDevice(
                    id: deviceId,
                    name: deviceName,
                    ipAddress: effectiveIP,
                    connectionVia: via,
                    firstConnectedAt: now,
                    lastSeenAt: now
                ),
                at: 0
            )
        }
    }
    
    private func selectRemoteModel(mode: String, provider: String, modelId: String) {
        guard let state = appState ?? AppState.shared else { return }
        switch mode {
        case "subscription":
            if let subType = SubscriptionProviderType(rawValue: provider) {
                SubscriptionAuthManager.shared.activeProvider = subType
                UserDefaults.standard.set(subType.rawValue, forKey: "subscriptionActiveProvider")
                UserDefaults.standard.set("subscription", forKey: "aiKeyMode")
                state.aiProvider = subType.aiProviderID
                state.aiModel = modelId
                state.saveSettings()
            }
        case "local":
            UserDefaults.standard.set("local", forKey: "aiKeyMode")
            state.aiProvider = "local"
            state.aiModel = modelId
            LocalLLMService.shared.selectedModelId = modelId
            state.saveSettings()
        case "cloud":
            UserDefaults.standard.set("cloud", forKey: "aiKeyMode")
            state.aiProvider = "omni"
            state.aiModel = modelId
            state.saveSettings()
        default:
            UserDefaults.standard.set("direct", forKey: "aiKeyMode")
            state.aiProvider = provider
            state.aiModel = modelId
            state.saveSettings()
        }
        cachedStateFingerprint = ""
    }
    
    private func switchRemoteWorkspace(path: String, sessionId: String? = nil) {
        let agent = AgentService.shared
        let state = appState ?? AppState.shared
        let cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let sid = sessionId, !sid.isEmpty, agent.chatSessions.contains(where: { $0.id == sid }) {
            agent.switchChat(to: sid)
        } else if !cleanPath.isEmpty && cleanPath != "__general__" {
            let canonicalTarget = URL(fileURLWithPath: cleanPath).standardizedFileURL.path
            if let existingChat = agent.chatSessions.first(where: {
                guard let p = $0.projectPath, !p.isEmpty else { return false }
                return URL(fileURLWithPath: p).standardizedFileURL.path == canonicalTarget
            }) {
                agent.switchChat(to: existingChat.id)
            } else {
                _ = agent.createNewChat(projectPath: canonicalTarget)
            }
            agent.setWorkspace(canonicalTarget)
        } else {
            if let generalChat = agent.chatSessions.first(where: { ($0.projectPath ?? "").isEmpty }) {
                agent.switchChat(to: generalChat.id)
            }
        }
        
        if !cleanPath.isEmpty && cleanPath != "__general__" {
            let folderURL = URL(fileURLWithPath: cleanPath)
            if state?.workspaceFolder?.standardizedFileURL.path != folderURL.standardizedFileURL.path {
                Task { @MainActor in
                    await state?.openWorkspace(url: folderURL)
                }
            }
        }
        cachedStateFingerprint = ""
    }
    
    private func switchRemoteSession(sessionId: String) {
        let agent = AgentService.shared
        let state = appState ?? AppState.shared
        agent.switchChat(to: sessionId)
        if let chat = agent.chatSessions.first(where: { $0.id == sessionId }),
           let chatPath = chat.projectPath, !chatPath.isEmpty {
            let folderURL = URL(fileURLWithPath: chatPath)
            if state?.workspaceFolder?.standardizedFileURL.path != folderURL.standardizedFileURL.path {
                Task { @MainActor in
                    await state?.openWorkspace(url: folderURL)
                }
            }
        }
        cachedStateFingerprint = ""
    }
    
    private func createRemoteSession(projectPath: String?) {
        let agent = AgentService.shared
        let state = appState ?? AppState.shared
        let resolvedPath: String? = {
            if let p = projectPath?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty, p != "__general__" {
                return URL(fileURLWithPath: p).standardizedFileURL.path
            }
            return agent.currentWorkspace ?? state?.workspaceFolder?.path
        }()
        _ = agent.createNewChat(projectPath: resolvedPath)
        if let path = resolvedPath, !path.isEmpty {
            agent.setWorkspace(path)
            let folderURL = URL(fileURLWithPath: path)
            if state?.workspaceFolder?.standardizedFileURL.path != folderURL.standardizedFileURL.path {
                Task { @MainActor in
                    await state?.openWorkspace(url: folderURL)
                }
            }
        }
        cachedStateFingerprint = ""
    }
    
    private func dispatchRemotePrompt(_ prompt: String, enqueueOnly: Bool = false) {
        let agent = AgentService.shared
        let state = appState ?? AppState.shared
        let provider = state?.aiProvider ?? UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"
        let model = state?.aiModel ?? UserDefaults.standard.string(forKey: "aiModel") ?? "gemini-2.5-flash"
        let apiKey = state?.resolveApiKey(for: provider) ?? ""
        
        if let ws = state?.workspaceFolder?.path, agent.currentWorkspace != ws {
            agent.setWorkspace(ws)
        }
        
        if enqueueOnly && agent.isLoading {
            agent.enqueueMessage(
                prompt,
                attachments: []
            )
        } else {
            agent.startOrEnqueueMessage(
                prompt,
                provider: provider,
                model: model,
                apiKey: apiKey,
                attachments: []
            )
        }
    }
    
    // MARK: - Rich Real-Time Companion State Builder
    
    private func currentModelDisplayLabel() -> String {
        let state = appState ?? AppState.shared
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "subscription"
        let activeModelId = state?.aiModel ?? ""
        let activeProvId = state?.aiProvider ?? "gemini"
        
        if keyMode == "subscription" {
            let activeSub = UserDefaults.standard.string(forKey: "subscriptionActiveProvider")
            let provType = activeSub.flatMap { SubscriptionProviderType(rawValue: $0) }
            if let info = SubscriptionAuthManager.shared.findModel(id: activeModelId, provider: provType) ?? SubscriptionAuthManager.shared.findModel(id: activeModelId) {
                let pName = info.provider.displayName.components(separatedBy: " ").first ?? "Subscription"
                return "Subscription · \(pName) : \(info.name)"
            }
            let pName = provType?.displayName.components(separatedBy: " ").first ?? "Gemini"
            let mName = activeModelId.isEmpty ? "Default" : AIModelCatalog.formatModelName(activeModelId)
            return "Subscription · \(pName) : \(mName)"
        } else if keyMode == "local" || activeProvId == "local" {
            let mName = activeModelId.isEmpty ? "Local Model" : AIModelCatalog.formatModelName(activeModelId)
            return "Local LLM · \(mName)"
        } else if keyMode == "cloud" || activeProvId == "omni" {
            let mName = AIModelCatalog.shared.model(id: activeModelId)?.name ?? AIModelCatalog.formatModelName(activeModelId)
            return "Sovereign AI · \(mName)"
        } else {
            let pName = AIModelCatalog.shared.provider(activeProvId)?.name ?? activeProvId.uppercased()
            let mName = AIModelCatalog.shared.model(id: activeModelId)?.name ?? AIModelCatalog.formatModelName(activeModelId)
            return "BYOK · \(pName) : \(mName)"
        }
    }
    
    private func currentProviderBrandId() -> String {
        let state = appState ?? AppState.shared
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "subscription"
        if keyMode == "subscription" {
            if let sub = UserDefaults.standard.string(forKey: "subscriptionActiveProvider"), !sub.isEmpty {
                return sub
            }
            if let activeModelId = state?.aiModel,
               let info = SubscriptionAuthManager.shared.findModel(id: activeModelId) {
                return info.provider.rawValue
            }
            return "gemini"
        } else if keyMode == "local" {
            return "local"
        } else if keyMode == "cloud" {
            return "omni"
        }
        return state?.aiProvider ?? "gemini"
    }
    
    private func buildAvailableModelsPayload() -> [[String: Any]] {
        let state = appState ?? AppState.shared
        let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "subscription"
        let activeModelId = state?.aiModel ?? ""
        let activeProvId = state?.aiProvider ?? ""
        var list: [[String: Any]] = []
        
        // 1. Subscription Providers
        let connected = Set(SubscriptionAuthManager.shared.connectedProviders())
        let orderedSub = SubscriptionAuthManager.shared.connectedProviders() + SubscriptionProviderType.allCases.filter { !connected.contains($0) }
        for prov in orderedSub {
            let groupTitle = "Subscription · \(prov.displayName)\(connected.contains(prov) ? " (Connected)" : "")"
            for m in prov.modelInfos.prefix(30) {
                let isCurrent = (keyMode == "subscription" && (activeModelId == m.modelID || activeModelId == m.id))
                list.append([
                    "group": groupTitle,
                    "mode": "subscription",
                    "provider": prov.rawValue,
                    "modelId": m.modelID,
                    "name": m.name,
                    "badge": m.badge,
                    "active": isCurrent
                ])
            }
        }
        
        // 2. BYOK Providers
        let acpSet: Set<String> = ["omni", "agy", "codex", "claude_code", "opencode", "zed", "gemini_cli", "cursor", "goose", "cline", "aider", "local"]
        for prov in AIModelCatalog.shared.providers where !acpSet.contains(prov.id) {
            let groupTitle = "BYOK · \(prov.name)"
            for m in prov.models.prefix(20) {
                let isCurrent = (keyMode == "direct" && activeProvId == prov.id && activeModelId == m.id)
                list.append([
                    "group": groupTitle,
                    "mode": "direct",
                    "provider": prov.id,
                    "modelId": m.id,
                    "name": m.name,
                    "badge": m.badge,
                    "active": isCurrent
                ])
            }
        }
        
        // 3. Local LLM Servers
        for srv in LocalLLMService.shared.detectedServers where srv.isOnline {
            let groupTitle = "Local LLM · \(srv.displayName)"
            for m in srv.models.prefix(20) {
                let isCurrent = (keyMode == "local" && activeModelId == m.id)
                list.append([
                    "group": groupTitle,
                    "mode": "local",
                    "provider": "local",
                    "modelId": m.id,
                    "name": m.displayName,
                    "badge": m.size ?? "Local",
                    "active": isCurrent
                ])
            }
        }
        
        // 4. Dotmini Sovereign AI
        if let omni = AIModelCatalog.shared.provider("omni") {
            for m in omni.models where m.id.lowercased().hasPrefix("omni") {
                let isCurrent = (keyMode == "cloud" && activeModelId == m.id)
                list.append([
                    "group": "Dotmini Sovereign AI",
                    "mode": "cloud",
                    "provider": "omni",
                    "modelId": m.id,
                    "name": m.name,
                    "badge": m.badge,
                    "active": isCurrent
                ])
            }
        }
        
        return list
    }
    
    private static func extractThoughtsAndCleanContent(_ raw: String) -> (clean: String, thought: String, isStreamingThought: Bool) {
        var working = AIStructuredTurnCodec.stripToolCallArtifacts(raw)
        var thoughts: [String] = []
        var isStreaming = false
        
        // 1. Extract closed <thought>...</thought>, <thinking>...</thinking>, <think>...</think>
        if let regex = Self.closedThoughtRegex {
            let ns = working as NSString
            let matches = regex.matches(in: working, options: [], range: NSRange(location: 0, length: ns.length))
            for m in matches {
                if m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound {
                    let body = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !body.isEmpty { thoughts.append(body) }
                }
            }
            working = regex.stringByReplacingMatches(in: working, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }
        
        // 2. Check for unclosed streaming <thought>, <thinking>, or <think>
        for openTag in ["<thought>", "<thinking>", "<think>"] {
            if let r = working.range(of: openTag, options: .caseInsensitive) {
                let streamingPart = String(working[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !streamingPart.isEmpty {
                    thoughts.append(streamingPart)
                }
                isStreaming = true
                working = String(working[..<r.lowerBound])
                break
            }
        }
        
        // 3. Strip stray closing tags
        for tag in ["</thought>", "</thinking>", "</think>", "<thought>", "<thinking>", "<think>"] {
            working = working.replacingOccurrences(of: tag, with: "", options: .caseInsensitive)
        }
        
        let finalClean = working.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalThought = thoughts.joined(separator: "\n\n")
        return (finalClean, finalThought, isStreaming)
    }
    
    private static func formatToolActivityItem(_ tr: ToolResultModel) -> [String: Any] {
        let params = AgentToolBox.normalizeToolParams(tr.toolParams ?? [:])
        let preview = tr.outputPreview
        
        var lineInfo = ""
        if let s = params["StartLine"] as? Int, let e = params["EndLine"] as? Int {
            lineInfo = "#L\(s)-\(e)"
        } else if let m = preview.range(of: #"#L\d+(-\d+)?"#, options: .regularExpression) {
            lineInfo = String(preview[m])
        }
        
        let targetPath = (params["path"] as? String)
            ?? (params["TargetFile"] as? String)
            ?? (params["AbsolutePath"] as? String)
            ?? (params["file_path"] as? String)
        let fileName: String = {
            if let p = targetPath, !p.isEmpty {
                return URL(fileURLWithPath: p).lastPathComponent
            }
            if let r = preview.range(of: #"/[^\s\n:{}"']+\.[a-zA-Z0-9]+"#, options: .regularExpression) {
                return URL(fileURLWithPath: String(preview[r])).lastPathComponent
            }
            return ""
        }()
        let fileExt = fileName.contains(".") ? URL(fileURLWithPath: fileName).pathExtension.uppercased() : "FILE"
        
        switch tr.toolName {
        case "file_read", "read_file", "view_file", "multi_file_read":
            let name = fileName.isEmpty ? "source file" : fileName
            let lines = lineInfo.isEmpty && tr.outputLineCount > 1 ? "#L1-\(min(350, tr.outputLineCount))" : lineInfo
            return [
                "id": tr.toolCallId,
                "kind": "analyze",
                "verb": "Analyzed",
                "target": name,
                "ext": fileExt,
                "lineRange": lines,
                "success": tr.success,
                "output": String(tr.output.prefix(1200))
            ]
            
        case "file_write", "replace_in_file", "multi_replace_in_file", "write_to_file", "patch_file", "apply_patch":
            let name = fileName.isEmpty ? "file" : fileName
            let oldStr = (params["old_str"] as? String) ?? (params["Target"] as? String) ?? (params["target"] as? String) ?? (params["search"] as? String) ?? ""
            let newStr = (params["new_str"] as? String) ?? (params["Replacement"] as? String) ?? (params["replacement"] as? String) ?? (params["replace"] as? String) ?? ""
            let fullContent = (params["content"] as? String) ?? (params["Content"] as? String) ?? ""
            
            var added = 0
            var removed = 0
            var diffLines: [String] = []
            
            if !oldStr.isEmpty || !newStr.isEmpty {
                let oldArr = oldStr.isEmpty ? [] : oldStr.components(separatedBy: .newlines)
                let newArr = newStr.isEmpty ? [] : newStr.components(separatedBy: .newlines)
                let oldSet = NSCountedSet(array: oldArr)
                for l in newArr {
                    if oldSet.count(for: l) > 0 {
                        oldSet.remove(l)
                    } else {
                        added += 1
                    }
                }
                for item in oldSet { removed += oldSet.count(for: item) }
                if added == 0 && removed == 0 && oldStr != newStr {
                    added = max(1, newArr.count)
                    removed = max(1, oldArr.count)
                }
                for l in oldArr.prefix(40) { diffLines.append("- " + l) }
                for l in newArr.prefix(40) { diffLines.append("+ " + l) }
            } else if !fullContent.isEmpty {
                let arr = fullContent.components(separatedBy: .newlines)
                added = max(1, arr.count)
                for l in arr.prefix(50) { diffLines.append("+ " + l) }
            } else {
                added = 1
                removed = 1
            }
            
            return [
                "id": tr.toolCallId,
                "kind": "edit",
                "verb": "Edited",
                "target": name,
                "ext": fileExt,
                "added": added,
                "removed": removed,
                "diff": diffLines.joined(separator: "\n"),
                "success": tr.success,
                "output": String(tr.output.prefix(1000))
            ]
            
        case "shell", "run_command":
            let summary: String = {
                if let s = (params["toolSummary"] as? String) ?? (params["description"] as? String), !s.isEmpty {
                    return s
                }
                if let cmd = (params["command"] as? String) ?? (params["CommandLine"] as? String) {
                    return String((cmd.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? cmd).prefix(68))
                }
                return "terminal command"
            }()
            return [
                "id": tr.toolCallId,
                "kind": "command",
                "verb": "Ran",
                "target": summary,
                "exitNote": tr.success ? "" : "Exited with code 1",
                "success": tr.success,
                "output": String((tr.success ? tr.output : (tr.error ?? tr.output)).prefix(1500))
            ]
            
        case "grep_search", "file_search", "find_symbol":
            let q = (params["query"] as? String) ?? (params["pattern"] as? String) ?? (params["symbol"] as? String) ?? "workspace"
            return [
                "id": tr.toolCallId,
                "kind": "generic",
                "verb": "Searched",
                "target": String(q.prefix(48)),
                "success": tr.success,
                "output": String(tr.output.prefix(1000))
            ]
            
        case "list_directory_tree", "list_dir":
            return [
                "id": tr.toolCallId,
                "kind": "generic",
                "verb": "Listed",
                "target": fileName.isEmpty ? "workspace" : fileName,
                "success": tr.success,
                "output": String(tr.output.prefix(1000))
            ]
            
        case "preview_control", "ide_browser":
            let act = (params["action"] as? String) ?? "open"
            let u = (params["url"] as? String) ?? "live preview"
            return [
                "id": tr.toolCallId,
                "kind": "generic",
                "verb": "Previewed",
                "target": "\(u) (\(act))",
                "success": tr.success,
                "output": String(tr.output.prefix(800))
            ]
            
        default:
            return [
                "id": tr.toolCallId,
                "kind": "generic",
                "verb": "Executed",
                "target": tr.toolName.replacingOccurrences(of: "_", with: " "),
                "success": tr.success,
                "output": String(tr.output.prefix(1000))
            ]
        }
    }
    
    private static func languageDisplayLabel(for key: String) -> String {
        switch key {
        case "swift": return "Swift"
        case "rs": return "Rust"
        case "ts": return "TypeScript"
        case "tsx", "jsx", "react": return "React"
        case "js": return "JavaScript"
        case "py": return "Python"
        case "go": return "Go"
        case "dart": return "Flutter"
        case "kt": return "Kotlin"
        case "java": return "Java"
        case "cpp": return "C++"
        case "c": return "C"
        case "cs": return "C#"
        case "ar": return "Ardium"
        case "svelte": return "Svelte"
        case "vue": return "Vue"
        case "html": return "HTML"
        case "css", "scss": return "CSS"
        case "rb": return "Ruby"
        case "php": return "PHP"
        case "sh": return "Shell"
        case "sql": return "SQL"
        case "md": return "Markdown"
        case "json": return "JSON"
        default: return "Code"
        }
    }
    
    func detectWorkspaceLanguageInfo(path: String) -> (primary: String, label: String, langs: [String]) {
        if path.isEmpty || path == "__general__" {
            return ("code", "General", [])
        }
        if let cached = workspaceLanguageCache[path] {
            return cached
        }
        
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: path)
        var detected: [String] = []
        func appendLang(_ k: String) {
            if !k.isEmpty && !detected.contains(k) && detected.count < 3 {
                detected.append(k)
            }
        }
        
        let rootItems = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        let lowerSet = Set(rootItems.map { $0.lowercased() })
        
        if lowerSet.contains("package.swift") || rootItems.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
            appendLang("swift")
        }
        if lowerSet.contains("cargo.toml") || fm.fileExists(atPath: rootURL.appendingPathComponent("backend/Cargo.toml").path) {
            appendLang("rs")
        }
        if lowerSet.contains("svelte.config.js") || lowerSet.contains("svelte.config.ts") {
            appendLang("svelte")
        }
        if lowerSet.contains("vue.config.js") || lowerSet.contains("nuxt.config.ts") || lowerSet.contains("nuxt.config.js") {
            appendLang("vue")
        }
        if lowerSet.contains("next.config.js") || lowerSet.contains("next.config.mjs") || lowerSet.contains("next.config.ts") {
            appendLang("tsx")
        }
        if lowerSet.contains("tsconfig.json") {
            appendLang("ts")
        }
        if lowerSet.contains("pubspec.yaml") {
            appendLang("dart")
        }
        if lowerSet.contains("go.mod") {
            appendLang("go")
        }
        if lowerSet.contains("pyproject.toml") || lowerSet.contains("requirements.txt") || lowerSet.contains("setup.py") || lowerSet.contains("main.py") || lowerSet.contains("app.py") {
            appendLang("py")
        }
        if lowerSet.contains("build.gradle.kts") {
            appendLang("kt")
        } else if lowerSet.contains("build.gradle") || lowerSet.contains("pom.xml") {
            appendLang("java")
        }
        if lowerSet.contains("cmakelists.txt") {
            appendLang("cpp")
        }
        if lowerSet.contains("package.json") && !detected.contains("ts") && !detected.contains("tsx") && !detected.contains("svelte") && !detected.contains("vue") {
            appendLang("js")
        }
        
        // Scan root and common source subdirectories for source file extensions
        let scanDirs: [String] = [path] + ["src", "app", "lib", "MicroCode", "backend/src"].map {
            rootURL.appendingPathComponent($0).path
        }.filter { fm.fileExists(atPath: $0) }
        
        let extOrder: [(ext: String, key: String)] = [
            ("ar", "ar"), ("swift", "swift"), ("rs", "rs"), ("tsx", "tsx"), ("ts", "ts"),
            ("jsx", "tsx"), ("svelte", "svelte"), ("vue", "vue"), ("py", "py"), ("go", "go"),
            ("dart", "dart"), ("kt", "kt"), ("java", "java"), ("cpp", "cpp"), ("cc", "cpp"),
            ("c", "c"), ("cs", "cs"), ("js", "js"), ("rb", "rb"), ("php", "php"),
            ("html", "html"), ("css", "css"), ("sql", "sql"), ("sh", "sh")
        ]
        var extCounts: [String: Int] = [:]
        for dir in scanDirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items.prefix(80) {
                let ext = (item as NSString).pathExtension.lowercased()
                if !ext.isEmpty {
                    extCounts[ext, default: 0] += 1
                }
            }
        }
        for pair in extOrder {
            if (extCounts[pair.ext] ?? 0) > 0 {
                appendLang(pair.key)
            }
        }
        
        // Also infer from workspace name if still empty
        if detected.isEmpty {
            let lowerName = rootURL.lastPathComponent.lowercased()
            if lowerName.contains("ardium") { appendLang("ar") }
            else if lowerName.contains("swift") || lowerName.contains("ios") || lowerName.contains("mac") { appendLang("swift") }
            else if lowerName.contains("rust") { appendLang("rs") }
            else if lowerName.contains("python") || lowerName.contains("omni") || lowerName.contains("ai") { appendLang("py") }
            else if lowerName.contains("flutter") || lowerName.contains("dart") { appendLang("dart") }
            else if lowerName.contains("react") || lowerName.contains("next") { appendLang("tsx") }
            else if lowerName.contains("web") || lowerName.contains("app") { appendLang("ts") }
        }
        
        let primary = detected.first ?? "code"
        let labels = detected.prefix(2).map { Self.languageDisplayLabel(for: $0) }
        let label = labels.isEmpty ? "Workspace" : labels.joined(separator: " · ")
        let info = (primary: primary, label: label, langs: detected.isEmpty ? ["code"] : detected)
        workspaceLanguageCache[path] = info
        return info
    }
    
    private func buildWorkspacesPayload(currentWorkspacePath: String) -> [[String: Any]] {
        let agent = AgentService.shared
        let canonicalCurrent = currentWorkspacePath.isEmpty
            ? ""
            : URL(fileURLWithPath: currentWorkspacePath).standardizedFileURL.path
        
        var result: [[String: Any]] = []
        var seenPaths: Set<String> = []
        
        // 1. All IDE projectGroups in exact IDE order
        for group in agent.projectGroups {
            let rawPath = group.projectPath ?? ""
            let canonicalPath = rawPath.isEmpty ? "__general__" : URL(fileURLWithPath: rawPath).standardizedFileURL.path
            seenPaths.insert(canonicalPath)
            
            let isGroupActive: Bool = {
                if canonicalPath != "__general__" && !canonicalCurrent.isEmpty {
                    return canonicalPath == canonicalCurrent
                }
                return group.chats.contains(where: { $0.id == agent.activeChatId })
            }()
            
            let chatsPayload: [[String: Any]] = group.chats.prefix(40).map { chat in
                [
                    "id": chat.id,
                    "name": chat.name,
                    "active": chat.id == agent.activeChatId,
                    "messageCount": chat.messageCount ?? 0
                ]
            }
            
            let langInfo = detectWorkspaceLanguageInfo(path: canonicalPath)
            result.append([
                "id": group.id,
                "name": group.projectName,
                "path": canonicalPath,
                "active": isGroupActive,
                "lang": langInfo.primary,
                "langLabel": langInfo.label,
                "langs": langInfo.langs,
                "chatCount": group.chats.count,
                "chats": chatsPayload
            ])
        }
        
        // 2. Also include any recent workspaces from AppState.getRecentWorkspaces() not yet in projectGroups
        for url in AppState.getRecentWorkspaces() {
            let canonicalPath = url.standardizedFileURL.path
            guard !canonicalPath.isEmpty, !seenPaths.contains(canonicalPath) else { continue }
            seenPaths.insert(canonicalPath)
            let langInfo = detectWorkspaceLanguageInfo(path: canonicalPath)
            result.append([
                "id": canonicalPath,
                "name": url.lastPathComponent,
                "path": canonicalPath,
                "active": canonicalPath == canonicalCurrent,
                "lang": langInfo.primary,
                "langLabel": langInfo.label,
                "langs": langInfo.langs,
                "chatCount": 0,
                "chats": []
            ])
        }
        
        return result
    }
    
    private func buildCompanionStateJSON() -> Data {
        let agent = AgentService.shared
        let planMgr = ImplementationPlanManager.shared
        let toolMgr = ToolApprovalManager.shared
        
        let currentWsPath: String = {
            if let activeId = agent.activeChatId,
               let activeChat = agent.chatSessions.first(where: { $0.id == activeId }),
               let chatPath = activeChat.projectPath, !chatPath.isEmpty {
                return URL(fileURLWithPath: chatPath).standardizedFileURL.path
            }
            if let ws = agent.currentWorkspace ?? appState?.workspaceFolder?.path, !ws.isEmpty {
                return URL(fileURLWithPath: ws).standardizedFileURL.path
            }
            return ""
        }()
        
        let lastMsg = agent.messages.last
        let activePort = DeviceRuntimeService.shared.targetWebURL?.port
            ?? DeviceRuntimeService.shared.lastDetectedDevServerPort
            ?? IDEBrowserAutomationService.shared.activePortProcesses.first?.port
        let modelLabel = currentModelDisplayLabel()
        
        let fingerprint = [
            currentWsPath,
            agent.activeChatId ?? "",
            "\(agent.chatSessions.count)",
            "\(agent.projectGroups.count)",
            "\(agent.messages.count)",
            lastMsg?.id ?? "",
            "\(lastMsg?.content.hashValue ?? 0)",
            "\(lastMsg?.toolResults.count ?? 0)",
            "\(agent.isLoading)",
            agent.agentPhase.displayText,
            agent.currentToolExecution ?? "",
            "\(agent.messageQueue.count)",
            modelLabel,
            planMgr.currentPlan?.approvalState.rawValue ?? "",
            "\(planMgr.currentPlan?.completedSteps ?? 0)",
            toolMgr.pendingRequest?.id.uuidString ?? "",
            "\(activePort ?? 0)"
        ].joined(separator: "|")
        
        if fingerprint == cachedStateFingerprint, !cachedStateData.isEmpty {
            return cachedStateData
        }
        
        let workspaceName: String = {
            if !currentWsPath.isEmpty {
                return URL(fileURLWithPath: currentWsPath).lastPathComponent
            }
            return "Workspace"
        }()
        
        let activeSessionName: String = {
            if let activeId = agent.activeChatId,
               let match = agent.chatSessions.first(where: { $0.id == activeId }) {
                return match.name
            }
            return "Conversation"
        }()
        
        let recentMessages = agent.messages.suffix(30).map { msg -> [String: Any] in
            let tools = msg.toolResults.suffix(24).map { Self.formatToolActivityItem($0) }
            let parsed = Self.extractThoughtsAndCleanContent(msg.content)
            return [
                "id": msg.id,
                "role": msg.role.rawValue,
                "content": parsed.clean,
                "thought": String(parsed.thought.suffix(3000)),
                "thoughtStreaming": parsed.isStreamingThought,
                "tools": tools
            ]
        }
        
        let workspacesList = buildWorkspacesPayload(currentWorkspacePath: currentWsPath)
        
        let scopedChats: [ChatSession] = {
            if !currentWsPath.isEmpty {
                let matching = agent.chatSessions.filter {
                    guard let p = $0.projectPath, !p.isEmpty else { return false }
                    return URL(fileURLWithPath: p).standardizedFileURL.path == currentWsPath
                }
                if !matching.isEmpty { return matching }
            }
            return agent.chatSessions
        }()
        
        let sessionsList = scopedChats.prefix(35).map { s -> [String: Any] in
            [
                "id": s.id,
                "name": s.name,
                "active": s.id == agent.activeChatId
            ]
        }
        
        var pendingPlanDict: [String: Any]? = nil
        if let plan = planMgr.currentPlan {
            pendingPlanDict = [
                "title": plan.title,
                "summary": plan.summary,
                "state": plan.approvalState.rawValue,
                "totalSteps": plan.totalSteps,
                "completedSteps": plan.completedSteps
            ]
        }
        
        var pendingToolDict: [String: Any]? = nil
        if let req = toolMgr.pendingRequest {
            pendingToolDict = [
                "id": req.id.uuidString,
                "toolName": req.toolName,
                "description": req.description,
                "risk": req.riskLevel.rawValue
            ]
        }
        
        var webPreviewLANURL: String? = nil
        if let port = activePort, activeLANHost != "127.0.0.1" {
            let path = DeviceRuntimeService.shared.targetWebURL?.path ?? "/"
            webPreviewLANURL = "http://\(activeLANHost):\(port)\(path.isEmpty ? "/" : path)"
        }
        
        let latestStepCount = lastMsg?.toolResults.count ?? 0
        let activeWsLang = detectWorkspaceLanguageInfo(path: currentWsPath)
        
        var payload: [String: Any] = [
            "macName": cachedMacName,
            "workspace": workspaceName,
            "workspacePath": currentWsPath.isEmpty ? "__general__" : currentWsPath,
            "workspaceLang": activeWsLang.primary,
            "workspaceLangLabel": activeWsLang.label,
            "workspaceLangs": activeWsLang.langs,
            "sessionTitle": activeSessionName,
            "modelLabel": modelLabel,
            "providerId": currentProviderBrandId(),
            "isLoading": agent.isLoading,
            "phase": agent.agentPhase.displayText,
            "currentTool": agent.currentToolExecution ?? "",
            "stepCount": latestStepCount,
            "queueCount": agent.messageQueue.count,
            "activeChatId": agent.activeChatId ?? "",
            "workspaces": workspacesList,
            "sessions": sessionsList,
            "messages": recentMessages
        ]
        if let pendingPlanDict { payload["plan"] = pendingPlanDict }
        if let pendingToolDict { payload["pendingTool"] = pendingToolDict }
        if let webPreviewLANURL { payload["webPreviewLANURL"] = webPreviewLANURL }
        
        let serialized = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        cachedStateFingerprint = fingerprint
        cachedStateData = serialized
        return serialized
    }
    
    private func makeJSONResponse(_ object: [String: Any], status: String = "200 OK") -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return makeHTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: body)
    }
    
    private func makeHTTPResponse(
        status: String,
        contentType: String,
        extraHeaders: [String: String] = [:],
        body: Data
    ) -> Data {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Cache-Control: no-store, no-cache, must-revalidate\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n"
        for (k, v) in extraHeaders {
            header += "\(k): \(v)\r\n"
        }
        header += "\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }
    
    // MARK: - Embedded Formal MicroCode IDE Mobile Web App
    
    private func buildMobileCompanionHTML(token: String) -> String {
        return #"""
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
        <meta name="apple-mobile-web-app-title" content="MicroCode AI">
        <title>MicroCode AI</title>
        <style>
          :root {
            --bg: #0d0d0f;
            --panel: #141417;
            --surface: #1b1b20;
            --surface-hover: #232329;
            --border: rgba(255,255,255,0.08);
            --border-strong: rgba(255,255,255,0.14);
            --text: #ededf0;
            --secondary: #9898a0;
            --muted: #686870;
            --accent: #3b82f6;
            --green: #22c55e;
            --red: #ef4444;
            --mono: ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace;
            --sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter", sans-serif;
          }
          * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
          body {
            margin: 0; padding: 0;
            background: var(--bg); color: var(--text);
            font-family: var(--sans);
            display: flex; flex-direction: column;
            height: 100dvh; overflow: hidden;
            -webkit-font-smoothing: antialiased;
          }

          /* 1. Top IDE Header */
          header {
            padding: max(10px, env(safe-area-inset-top)) 12px 8px;
            background: var(--panel);
            border-bottom: 1px solid var(--border);
            display: flex; flex-direction: column; gap: 7px;
            z-index: 20;
          }
          .ide-titlebar {
            display: flex; align-items: center; justify-content: space-between; gap: 8px;
            min-height: 24px;
          }
          .ide-brand {
            display: flex; align-items: center; gap: 6px;
            font-size: 13px; font-weight: 600; color: var(--text);
            white-space: nowrap;
          }
          .conn-indicator {
            width: 6px; height: 6px; border-radius: 50%;
            background: var(--green); flex-shrink: 0;
          }
          .ide-breadcrumb {
            display: flex; align-items: center; gap: 5px;
            font-size: 12px; color: var(--secondary);
            min-width: 0; flex: 1; overflow: hidden;
            cursor: pointer; padding: 3px 6px; border-radius: 5px;
          }
          .ide-breadcrumb:active { background: var(--surface-hover); }
          .ide-breadcrumb span {
            overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
          }
          .ide-subbar {
            display: flex; align-items: center; gap: 6px; width: 100%; min-width: 0;
          }
          .ws-select-wrap {
            flex: 0 1 46%; min-width: 112px;
            display: flex; align-items: center; gap: 5px;
            background: var(--surface); color: var(--text);
            border: 1px solid var(--border-strong); border-radius: 6px;
            padding: 0 6px;
          }
          .ws-select {
            flex: 1; min-width: 0;
            background: transparent; color: var(--text);
            border: none;
            padding: 5px 2px; font-size: 12px; font-weight: 600;
            font-family: var(--sans); outline: none;
          }
          .lang-icon-badge {
            display: inline-flex; align-items: center; justify-content: center;
            flex-shrink: 0; vertical-align: middle; line-height: 1;
          }
          .ws-lang-stack {
            display: inline-flex; align-items: center; gap: 3px; flex-shrink: 0;
          }
          .ws-lang-tag {
            font-family: var(--mono); font-size: 9.5px; font-weight: 600;
            color: var(--secondary); padding: 1px 5px; border-radius: 4px;
            background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.06);
            flex-shrink: 0;
          }
          .session-select {
            flex: 1 1 56%; min-width: 0;
            background: var(--surface); color: var(--text);
            border: 1px solid var(--border); border-radius: 6px;
            padding: 5px 7px; font-size: 12px; font-weight: 500;
            font-family: var(--sans); outline: none;
          }
          .tb-btn {
            flex-shrink: 0; white-space: nowrap;
            background: var(--surface); color: var(--text);
            border: 1px solid var(--border); border-radius: 6px;
            padding: 5px 9px; font-size: 11.5px; font-weight: 500;
            display: inline-flex; align-items: center; gap: 4px;
            cursor: pointer; text-decoration: none;
          }
          .tb-btn:active { background: var(--surface-hover); }
          .ws-group-card {
            border: 1px solid var(--border);
            border-radius: 8px;
            background: rgba(255,255,255,0.02);
            margin-bottom: 8px;
            overflow: hidden;
          }
          .ws-group-card.active {
            border-color: var(--border-strong);
            background: rgba(255,255,255,0.04);
          }
          .ws-group-header {
            display: flex; align-items: center; justify-content: space-between;
            padding: 8px 10px; gap: 8px; cursor: pointer;
          }
          .ws-group-header:active { background: var(--surface-hover); }
          .ws-group-left {
            display: flex; align-items: center; gap: 7px; min-width: 0; flex: 1;
          }
          .ws-group-name {
            font-size: 12.5px; font-weight: 600; color: var(--text);
            overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
          }
          .ws-group-count {
            font-family: var(--mono); font-size: 10px; color: var(--secondary);
            padding: 1px 5px; border-radius: 4px; background: rgba(255,255,255,0.05);
            flex-shrink: 0;
          }
          .ws-chat-list {
            border-top: 1px solid var(--border);
            padding: 4px 6px;
            display: flex; flex-direction: column; gap: 2px;
          }
          .ws-chat-row {
            display: flex; align-items: center; justify-content: space-between;
            padding: 6px 8px 6px 22px; border-radius: 5px;
            font-size: 12px; color: var(--secondary); cursor: pointer;
          }
          .ws-chat-row.active {
            background: rgba(255,255,255,0.08);
            color: var(--text); font-weight: 500;
          }
          .ws-chat-row:active { background: var(--surface-hover); }

          /* 2. Approval Banners */
          #banners { padding: 0 12px; display: flex; flex-direction: column; gap: 6px; }
          .approval-card {
            margin-top: 8px; padding: 10px 12px; border-radius: 8px;
            background: var(--surface); border: 1px solid var(--border-strong);
            display: flex; flex-direction: column; gap: 7px;
          }
          .approval-title { font-size: 12px; font-weight: 600; color: var(--text); }
          .approval-desc { font-size: 11.5px; color: var(--secondary); font-family: var(--mono); }
          .approval-actions { display: flex; gap: 6px; }
          .btn-allow {
            flex: 1; background: var(--text); color: var(--bg);
            border: none; padding: 6px 10px; border-radius: 6px;
            font-size: 11.5px; font-weight: 600; cursor: pointer;
          }
          .btn-deny {
            flex: 1; background: transparent; color: var(--secondary);
            border: 1px solid var(--border-strong); padding: 6px 10px;
            border-radius: 6px; font-size: 11.5px; font-weight: 500; cursor: pointer;
          }

          /* 3. Chat Stream */
          #chat {
            flex: 1; overflow-y: auto; padding: 14px 12px 18px;
            display: flex; flex-direction: column; gap: 14px;
          }
          .turn-user {
            align-self: flex-end;
            max-width: 86%;
            background: #232329;
            color: var(--text);
            border: 1px solid var(--border);
            padding: 9px 13px;
            border-radius: 10px;
            font-size: 13.5px; line-height: 1.48;
            white-space: pre-wrap; word-break: break-word;
          }
          .turn-assistant {
            align-self: stretch;
            display: flex; flex-direction: column; gap: 6px;
            min-width: 0;
          }

          /* Collapsible Thought Block (IDE Style) */
          details.thought-block {
            border-radius: 6px;
            background: rgba(255,255,255,0.02);
            border: 1px solid rgba(255,255,255,0.05);
            overflow: hidden;
          }
          details.thought-block summary {
            list-style: none; cursor: pointer;
            padding: 5px 8px;
            font-size: 11.5px; color: var(--secondary);
            display: flex; align-items: center; gap: 6px;
            user-select: none;
          }
          details.thought-block summary::-webkit-details-marker { display: none; }
          .thought-body {
            padding: 6px 10px 8px;
            border-top: 1px solid rgba(255,255,255,0.05);
            font-size: 12px; line-height: 1.48; color: var(--secondary);
            white-space: pre-wrap; word-break: break-word;
          }

          /* IDE Tool Activity Rows (100% matching ToolActivityItemRow) */
          .tool-list {
            display: flex; flex-direction: column; gap: 3px;
            margin: 1px 0 3px;
          }
          details.tool-row {
            border-radius: 5px;
          }
          details.tool-row summary {
            list-style: none; cursor: pointer;
            padding: 2.5px 4px;
            display: flex; align-items: center; gap: 6px;
            font-size: 12.5px; color: var(--secondary);
            user-select: none; min-width: 0;
          }
          details.tool-row summary::-webkit-details-marker { display: none; }
          .tool-verb { color: var(--secondary); flex-shrink: 0; }
          .file-pill {
            display: inline-flex; align-items: center; gap: 5px;
            padding: 1.5px 6px; border-radius: 5px;
            background: rgba(255,255,255,0.04);
            border: 1px solid rgba(255,255,255,0.06);
            color: var(--text); font-size: 12px; font-weight: 500;
            min-width: 0; max-width: 100%; overflow: hidden;
          }
          .ext-badge {
            font-family: var(--mono); font-size: 9px; font-weight: 700;
            padding: 1px 3.5px; border-radius: 3px;
            background: rgba(255,255,255,0.09); color: var(--text);
            flex-shrink: 0;
          }
          .file-name {
            overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
          }
          .line-range {
            font-family: var(--mono); font-size: 11px; color: var(--secondary); flex-shrink: 0;
          }
          .diff-add { color: var(--green); font-family: var(--mono); font-size: 11.5px; font-weight: 600; flex-shrink: 0; }
          .diff-del { color: var(--red); font-family: var(--mono); font-size: 11.5px; font-weight: 600; flex-shrink: 0; }
          .cmd-summary {
            font-family: var(--mono); font-size: 12px; color: var(--secondary);
            overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
          }
          .chev {
            font-size: 10px; color: var(--muted); margin-left: 2px; flex-shrink: 0;
            transition: transform 0.12s ease;
          }
          details[open] > summary .chev { transform: rotate(90deg); }
          .tool-drawer {
            margin: 4px 0 6px 10px;
            background: #09090b;
            border: 1px solid var(--border);
            border-radius: 6px;
            overflow-x: auto;
            font-family: var(--mono); font-size: 11px; line-height: 1.45;
          }
          .tool-output-pre {
            margin: 0; padding: 8px 10px; color: var(--secondary);
            white-space: pre-wrap; word-break: break-word; max-height: 240px; overflow-y: auto;
          }

          /* Markdown & Code Block / Diff Preview Styling */
          .prose {
            font-size: 13.5px; line-height: 1.55; color: var(--text);
            word-break: break-word;
          }
          .prose h1, .prose h2, .prose h3, .prose h4 {
            margin: 12px 0 6px; font-size: 14px; font-weight: 600; color: #fff;
          }
          .prose p { margin: 0 0 8px; }
          .prose p:last-child { margin-bottom: 0; }
          .prose ul, .prose ol { margin: 4px 0 8px 18px; padding: 0; }
          .prose li { margin-bottom: 4px; }
          .prose blockquote {
            margin: 6px 0; padding: 4px 10px;
            border-left: 2px solid var(--border-strong); color: var(--secondary);
          }
          .inline-code {
            font-family: var(--mono); font-size: 12px;
            background: rgba(255,255,255,0.07); color: #e4e4e7;
            padding: 1.5px 5px; border-radius: 4px;
          }

          /* IDE Code Block & Diff Card */
          .code-card {
            margin: 8px 0;
            border-radius: 8px;
            background: #0a0a0c;
            border: 1px solid var(--border);
            overflow: hidden;
          }
          .code-header {
            display: flex; align-items: center; justify-content: space-between;
            padding: 5px 10px;
            background: #141418;
            border-bottom: 1px solid var(--border);
            font-family: var(--mono); font-size: 10.5px; color: var(--secondary);
          }
          .code-lang { font-weight: 600; text-transform: uppercase; color: var(--text); }
          .copy-btn {
            background: rgba(255,255,255,0.06); color: var(--secondary);
            border: 1px solid var(--border); border-radius: 4px;
            padding: 2px 7px; font-size: 10px; font-family: var(--sans); cursor: pointer;
          }
          .code-lines {
            padding: 6px 0; overflow-x: auto;
            font-family: var(--mono); font-size: 11.5px; line-height: 1.48;
          }
          .code-line {
            display: flex; padding: 0 10px; white-space: pre; min-width: max-content;
          }
          .code-line.add { background: rgba(34,197,94,0.13); color: #86efac; }
          .code-line.del { background: rgba(239,68,68,0.13); color: #fca5a5; }
          .code-line.hunk { background: rgba(59,130,246,0.10); color: #93c5fd; }
          .ln {
            width: 28px; flex-shrink: 0; color: var(--muted);
            text-align: right; padding-right: 10px; user-select: none;
          }
          .lc { flex: 1; }

          /* 4. Live Task Activity Bar (matching liveTaskActivityBanner in AIAgentView) */
          .live-activity-bar {
            margin: 0 12px 6px;
            padding: 6px 10px;
            background: var(--panel);
            border: 1px solid var(--border);
            border-radius: 8px;
            display: none; align-items: center; gap: 8px;
          }
          .spinner {
            width: 12px; height: 12px;
            border: 1.6px solid rgba(255,255,255,0.2);
            border-top-color: var(--text);
            border-radius: 50%;
            animation: spin 0.75s linear infinite;
            flex-shrink: 0;
          }
          @keyframes spin { to { transform: rotate(360deg); } }
          .live-activity-text {
            font-family: var(--mono); font-size: 11px; color: var(--text);
            flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
          }
          .step-pill {
            font-family: var(--mono); font-size: 10px; font-weight: 600;
            padding: 1.5px 6px; border-radius: 999px;
            background: rgba(255,255,255,0.07); color: var(--secondary);
            flex-shrink: 0;
          }

          /* 5. IDE Composer Box (100% Matching Mac IDE Bottom Bar) */
          .composer-wrap {
            padding: 4px 10px max(10px, env(safe-area-inset-bottom));
            background: var(--bg);
          }
          .composer-box {
            background: var(--panel);
            border: 1px solid var(--border-strong);
            border-radius: 11px;
            padding: 8px 10px 7px;
            display: flex; flex-direction: column; gap: 6px;
          }
          .composer-input {
            width: 100%; background: transparent; color: var(--text);
            border: none; outline: none; resize: none;
            font-family: var(--sans); font-size: 14px; line-height: 1.42;
            min-height: 22px; max-height: 110px; padding: 0; margin: 0;
          }
          .composer-input::placeholder { color: var(--muted); }
          .composer-toolbar {
            display: flex; align-items: center; justify-content: space-between; gap: 6px;
            min-width: 0;
          }
          .composer-left, .composer-right {
            display: flex; align-items: center; gap: 5px; min-width: 0;
          }
          .composer-left { flex: 1; overflow: hidden; }
          .circle-icon-btn {
            width: 24px; height: 24px; border-radius: 50%;
            background: rgba(255,255,255,0.05); color: var(--secondary);
            border: 1px solid var(--border);
            display: inline-flex; align-items: center; justify-content: center;
            cursor: pointer; flex-shrink: 0; padding: 0;
          }
          .model-pill-btn {
            display: inline-flex; align-items: center; gap: 5px;
            background: rgba(255,255,255,0.05); color: var(--text);
            border: 1px solid var(--border); border-radius: 6px;
            padding: 3.5px 7px; font-size: 11px; font-weight: 500;
            min-width: 0; max-width: 215px; cursor: pointer;
          }
          .model-pill-btn span {
            overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
          }
          .meta-pill {
            display: inline-flex; align-items: center; gap: 4px;
            background: rgba(255,255,255,0.04); color: var(--secondary);
            border: 1px solid var(--border); border-radius: 6px;
            padding: 3px 6px; font-size: 10.5px; font-weight: 500;
            flex-shrink: 0;
          }
          .ide-send-btn {
            width: 26px; height: 26px; border-radius: 50%;
            background: var(--text); color: var(--bg);
            border: none; display: inline-flex; align-items: center; justify-content: center;
            cursor: pointer; flex-shrink: 0; padding: 0;
          }
          .ide-send-btn.disabled {
            background: rgba(255,255,255,0.1); color: var(--muted);
          }
          .ide-stop-btn {
            width: 26px; height: 26px; border-radius: 50%;
            background: rgba(239,68,68,0.88); color: #fff;
            border: none; display: none; align-items: center; justify-content: center;
            cursor: pointer; flex-shrink: 0; padding: 0;
          }
          .ide-queue-btn {
            width: 24px; height: 24px; border-radius: 50%;
            background: rgba(255,255,255,0.14); color: var(--text);
            border: 1px solid var(--border-strong);
            display: none; align-items: center; justify-content: center;
            cursor: pointer; flex-shrink: 0; padding: 0;
          }

          /* 6. Model Picker Modal Sheet */
          .modal-backdrop {
            position: fixed; inset: 0; background: rgba(0,0,0,0.65);
            display: none; align-items: flex-end; justify-content: center;
            z-index: 100;
          }
          .modal-sheet {
            width: 100%; max-width: 520px; max-height: 76dvh;
            background: var(--panel); border-top: 1px solid var(--border-strong);
            border-radius: 14px 14px 0 0;
            display: flex; flex-direction: column;
            padding-bottom: max(12px, env(safe-area-inset-bottom));
          }
          .modal-header {
            padding: 12px 14px; border-bottom: 1px solid var(--border);
            display: flex; align-items: center; justify-content: space-between;
            font-size: 13px; font-weight: 600;
          }
          .modal-search {
            margin: 8px 12px; padding: 7px 10px;
            background: var(--surface); color: var(--text);
            border: 1px solid var(--border); border-radius: 7px;
            font-size: 12.5px; outline: none;
          }
          .modal-list {
            flex: 1; overflow-y: auto; padding: 4px 12px 12px;
          }
          .model-group-title {
            font-family: var(--mono); font-size: 10px; font-weight: 600;
            color: var(--secondary); margin: 10px 0 4px; text-transform: uppercase;
          }
          .model-option {
            display: flex; align-items: center; justify-content: space-between;
            padding: 8px 10px; border-radius: 6px; cursor: pointer;
            font-size: 12.5px; color: var(--text);
          }
          .model-option:active, .model-option.active {
            background: var(--surface-hover);
          }
          .model-badge {
            font-family: var(--mono); font-size: 10px; color: var(--secondary);
            padding: 1px 5px; border-radius: 4px; background: rgba(255,255,255,0.05);
          }
        </style>
        </head>
        <body>
          <header>
            <div class="ide-titlebar">
              <div class="ide-brand">
                <button class="tb-btn" onclick="openWorkspaceModal()" style="padding:4px 7px" title="Projects & Workspaces">
                  <svg width="13" height="13" viewBox="0 0 16 16" fill="none"><path d="M1.5 3.5A1.5 1.5 0 0 1 3 2h3.172a1.5 1.5 0 0 1 1.06.44l.829.828a.5.5 0 0 0 .353.146H13A1.5 1.5 0 0 1 14.5 4.914V12.5A1.5 1.5 0 0 1 13 14H3a1.5 1.5 0 0 1-1.5-1.5v-9Z" stroke="currentColor" stroke-width="1.3"/></svg>
                </button>
                <span class="conn-indicator" id="connDot"></span>
                <span>MicroCode AI</span>
              </div>
              <div class="ide-breadcrumb" onclick="openWorkspaceModal()" title="Switch Workspace">
                <span>/</span>
                <span class="ws-lang-stack" id="wsHeaderLangIcons"></span>
                <span id="wsBreadcrumb">Workspace</span>
                <span style="font-size:10px;color:var(--muted)">▾</span>
              </div>
              <a class="tb-btn" id="previewBtn" href="#" target="_blank" style="display:none">Preview</a>
            </div>
            <div class="ide-subbar">
              <div class="ws-select-wrap">
                <span class="ws-lang-stack" id="subbarWsIcon"></span>
                <select class="ws-select" id="workspaceSelect" onchange="switchWorkspace(this.value)" title="Workspace"></select>
              </div>
              <select class="session-select" id="sessionSelect" onchange="switchSession(this.value)" title="Conversation"></select>
              <button class="tb-btn" onclick="newSession()">+ New</button>
            </div>
          </header>

          <div id="banners"></div>
          <div id="chat"></div>

          <div class="live-activity-bar" id="liveActivityBar">
            <div class="spinner"></div>
            <div class="live-activity-text" id="liveActivityText">Processing…</div>
            <div class="step-pill" id="liveStepPill" style="display:none">0 steps</div>
          </div>

          <div class="composer-wrap">
            <div class="composer-box">
              <textarea class="composer-input" id="promptInput" rows="1" placeholder="Ask anything, @ to mention, / for actions"></textarea>
              <div class="composer-toolbar">
                <div class="composer-left">
                  <button class="circle-icon-btn" onclick="cycleQuickPrefix()" title="Insert /plan or /review">
                    <svg width="11" height="11" viewBox="0 0 12 12" fill="none"><path d="M6 1v10M1 6h10" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>
                  </button>
                  <button class="model-pill-btn" onclick="openModelModal()">
                    <img id="modelPillIcon" src="/api/icon/provider?id=gemini&token=\#(token)" width="13" height="13" style="border-radius:3px;flex-shrink:0;object-fit:contain" alt="">
                    <span id="modelPillText">Subscription · Gemini</span>
                    <svg width="9" height="9" viewBox="0 0 12 12" fill="none"><path d="M3 4.5L6 1.5l3 3M3 7.5l3 3 3-3" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>
                  </button>
                  <div class="meta-pill">Local</div>
                </div>
                <div class="composer-right">
                  <div class="meta-pill" id="modePill" onclick="togglePlanPrefix()" style="cursor:pointer">Agent</div>
                  <button class="ide-queue-btn" id="queueBtn" onclick="sendPrompt(true)" title="Add to Queue">+</button>
                  <button class="ide-stop-btn" id="stopBtn" onclick="stopAgent()" title="Stop">
                    <svg width="8" height="8" viewBox="0 0 8 8"><rect width="8" height="8" rx="1.5" fill="currentColor"/></svg>
                  </button>
                  <button class="ide-send-btn disabled" id="sendBtn" onclick="sendPrompt(false)" title="Send">
                    <svg width="12" height="12" viewBox="0 0 12 12" fill="none"><path d="M6 10V2M6 2L2.5 5.5M6 2l3.5 3.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- Projects & Workspaces Sheet (100% Matching Mac IDE Sidebar) -->
          <div class="modal-backdrop" id="workspaceModal" onclick="if(event.target===this)closeWorkspaceModal()">
            <div class="modal-sheet">
              <div class="modal-header">
                <span style="font-family:var(--mono);font-size:11px;letter-spacing:0.04em;color:var(--secondary)">PROJECTS &amp; WORKSPACES</span>
                <button class="tb-btn" onclick="closeWorkspaceModal()">Close</button>
              </div>
              <input class="modal-search" id="workspaceSearch" type="text" placeholder="Filter workspaces or conversations…" oninput="renderWorkspaceList()">
              <div class="modal-list" id="workspaceList"></div>
            </div>
          </div>

          <!-- Model Picker Sheet -->
          <div class="modal-backdrop" id="modelModal" onclick="if(event.target===this)closeModelModal()">
            <div class="modal-sheet">
              <div class="modal-header">
                <span>Select AI Model</span>
                <button class="tb-btn" onclick="closeModelModal()">Close</button>
              </div>
              <input class="modal-search" id="modelSearch" type="text" placeholder="Filter models (Gemini, Claude, GPT, Local…)" oninput="renderModelList()">
              <div class="modal-list" id="modelList"></div>
            </div>
          </div>

        <script>
          const TOKEN = "\#(token)";
          let lastRenderKey = "";
          let autoScroll = true;
          let isAgentLoading = false;
          let availableModels = [];
          let availableWorkspaces = [];
          let openDrawerIds = new Set();

          const chatEl = document.getElementById("chat");
          const promptInput = document.getElementById("promptInput");

          chatEl.addEventListener("scroll", () => {
            const dist = chatEl.scrollHeight - chatEl.scrollTop - chatEl.clientHeight;
            autoScroll = dist < 90;
          });

          promptInput.addEventListener("input", () => {
            promptInput.style.height = "auto";
            promptInput.style.height = Math.min(110, promptInput.scrollHeight) + "px";
            updateComposerButtons();
          });

          function updateComposerButtons() {
            const hasText = promptInput.value.trim().length > 0;
            const sendBtn = document.getElementById("sendBtn");
            const stopBtn = document.getElementById("stopBtn");
            const queueBtn = document.getElementById("queueBtn");
            if (isAgentLoading) {
              stopBtn.style.display = "inline-flex";
              queueBtn.style.display = hasText ? "inline-flex" : "none";
              sendBtn.style.display = hasText ? "inline-flex" : "none";
              sendBtn.classList.toggle("disabled", !hasText);
            } else {
              stopBtn.style.display = "none";
              queueBtn.style.display = "none";
              sendBtn.style.display = "inline-flex";
              sendBtn.classList.toggle("disabled", !hasText);
            }
          }

          async function api(path, body) {
            const opts = {
              method: body ? "POST" : "GET",
              headers: { "X-Companion-Token": TOKEN, "Content-Type": "application/json" }
            };
            if (body) opts.body = JSON.stringify(body);
            const res = await fetch(path + "?token=" + encodeURIComponent(TOKEN), opts);
            return await res.json();
          }

          function esc(str) {
            return String(str == null ? "" : str)
              .replace(/&/g, "&amp;")
              .replace(/</g, "&lt;")
              .replace(/>/g, "&gt;")
              .replace(/"/g, "&quot;")
              .replace(/'/g, "&#39;");
          }

          function extFromPath(p) {
            const m = (p || "").match(/\.([a-zA-Z0-9]+)(?:#.*)?$/);
            return m ? m[1].toUpperCase().slice(0, 5) : "FILE";
          }

          function resolveLangKey(fileName, langHint) {
            const cleanFile = String(fileName || "").split("#")[0].split("?")[0].trim();
            const base = (cleanFile.split("/").pop() || "").toLowerCase();
            if (base === "dockerfile" || base.startsWith("dockerfile.") || base === "docker-compose.yml" || base === "docker-compose.yaml") return "docker";
            if (base === "cargo.toml" || base === "cargo.lock") return "rs";
            if (base === "package.json" || base === "package-lock.json") return "npm";
            if (base === "go.mod" || base === "go.sum") return "go";
            if (base === "pubspec.yaml") return "dart";
            if (base === "cmakelists.txt") return "cpp";
            if (base.startsWith(".git")) return "git";
            const dotIdx = base.lastIndexOf(".");
            const ext = dotIdx > 0 ? base.slice(dotIdx + 1) : "";
            const raw = (ext || String(langHint || "").trim().toLowerCase());
            switch (raw) {
              case "swift": return "swift";
              case "ts": case "mts": case "cts": case "typescript": return "ts";
              case "js": case "mjs": case "cjs": case "javascript": return "js";
              case "tsx": return "tsx";
              case "jsx": case "react": return "jsx";
              case "py": case "pyw": case "ipynb": case "python": return "py";
              case "rs": case "rust": return "rs";
              case "go": case "golang": return "go";
              case "html": case "htm": case "ejs": case "hbs": return "html";
              case "css": return "css";
              case "scss": case "sass": case "less": return "scss";
              case "svelte": return "svelte";
              case "vue": return "vue";
              case "c": case "h": return "c";
              case "cpp": case "cc": case "cxx": case "hpp": case "c++": return "cpp";
              case "m": case "mm": case "objc": case "objective-c": return "objc";
              case "cs": case "csharp": return "cs";
              case "java": case "jar": case "gradle": return "java";
              case "kt": case "kts": case "kotlin": return "kt";
              case "dart": case "flutter": return "dart";
              case "rb": case "ruby": return "rb";
              case "php": return "php";
              case "ar": case "ardium": return "ar";
              case "json": case "jsonc": case "jsonl": return "json";
              case "nodejs": case "node": return "nodejs";
              case "npm": return "npm";
              case "md": case "mdx": case "markdown": return "md";
              case "toml": return "toml";
              case "plist": case "xml": case "svg": return "xml";
              case "yml": case "yaml": case "ini": case "conf": return "yaml";
              case "sh": case "zsh": case "bash": case "fish": case "env": case "shell": return "sh";
              case "sql": case "db": case "sqlite": case "prisma": return "sql";
              case "docker": case "dockerfile": return "docker";
              case "git": case "diff": case "patch": return "git";
              default: return "code";
            }
          }

          // 100% Official PKief.material-icon-theme SVG Vector Icons (Matching Mac IDE ExtensionManager)
          function renderLangIcon(fileName, langHint, size) {
            const sz = size || 14;
            const key = resolveLangKey(fileName, langHint);
            let vb = "0 0 24 24";
            let inner = "";
            switch (key) {
              case "swift":
                vb = "0 0 24 24";
                inner = `<path fill="#ff6e40" d="M17.087 19.721c-2.36 1.36-5.59 1.5-8.86.1a13.8 13.8 0 0 1-6.23-5.32c.67.55 1.46 1 2.3 1.4 3.37 1.57 6.73 1.46 9.1 0-3.37-2.59-6.24-5.96-8.37-8.71-.45-.45-.78-1.01-1.12-1.51 8.28 6.05 7.92 7.59 2.41-1.01 4.89 4.94 9.43 7.74 9.43 7.74.16.09.25.16.36.22.1-.25.19-.51.26-.78.79-2.85-.11-6.12-2.08-8.81 4.55 2.75 7.25 7.91 6.12 12.24-.03.11-.06.22-.05.39 2.24 2.83 1.64 5.78 1.35 5.22-1.21-2.39-3.48-1.65-4.62-1.17"/>`;
                break;
              case "ts":
                vb = "0 0 16 16";
                inner = `<path fill="#0288d1" d="M2 2v12h12V2zm4 6h3v1H8v4H7V9H6zm5 0h2v1h-2v1h1a1.003 1.003 0 0 1 1 1v1a1.003 1.003 0 0 1-1 1h-2v-1h2v-1h-1a1.003 1.003 0 0 1-1-1V9a1.003 1.003 0 0 1 1-1"/>`;
                break;
              case "js":
                vb = "0 0 16 16";
                inner = `<path fill="#ffca28" d="M2 2v12h12V2zm6 6h1v4a1.003 1.003 0 0 1-1 1H7a1.003 1.003 0 0 1-1-1v-1h1v1h1zm3 0h2v1h-2v1h1a1.003 1.003 0 0 1 1 1v1a1.003 1.003 0 0 1-1 1h-2v-1h2v-1h-1a1.003 1.003 0 0 1-1-1V9a1.003 1.003 0 0 1 1-1"/>`;
                break;
              case "tsx":
                vb = "0 0 32 32";
                inner = `<path fill="#0288d1" d="M16 12c7.444 0 12 2.59 12 4s-4.556 4-12 4-12-2.59-12-4 4.556-4 12-4m0-2c-7.732 0-14 2.686-14 6s6.268 6 14 6 14-2.686 14-6-6.268-6-14-6"/><path fill="#0288d1" d="M16 14a2 2 0 1 0 2 2 2 2 0 0 0-2-2"/><path fill="#0288d1" d="M10.458 5.507c2.017 0 5.937 3.177 9.006 8.493 3.722 6.447 3.757 11.687 2.536 12.392a.9.9 0 0 1-.457.1c-2.017 0-5.938-3.176-9.007-8.492C8.814 11.553 8.779 6.313 10 5.608a.9.9 0 0 1 .458-.1m-.001-2A2.87 2.87 0 0 0 9 3.875C6.13 5.532 6.938 12.304 10.804 19c3.284 5.69 7.72 9.493 10.74 9.493A2.87 2.87 0 0 0 23 28.124c2.87-1.656 2.062-8.428-1.804-15.124-3.284-5.69-7.72-9.493-10.74-9.493Z"/><path fill="#0288d1" d="M21.543 5.507a.9.9 0 0 1 .457.1c1.221.706 1.186 5.946-2.536 12.393-3.07 5.316-6.99 8.493-9.007 8.493a.9.9 0 0 1-.457-.1C8.779 25.686 8.814 20.446 12.536 14c3.07-5.316 6.99-8.493 9.007-8.493m0-2c-3.02 0-7.455 3.804-10.74 9.493C6.939 19.696 6.13 26.468 9 28.124a2.87 2.87 0 0 0 1.457.369c3.02 0 7.455-3.804 10.74-9.493C25.061 12.304 25.87 5.532 23 3.876a2.87 2.87 0 0 0-1.457-.369"/>`;
                break;
              case "jsx":
                vb = "0 0 32 32";
                inner = `<path fill="#00bcd4" d="M16 12c7.444 0 12 2.59 12 4s-4.556 4-12 4-12-2.59-12-4 4.556-4 12-4m0-2c-7.732 0-14 2.686-14 6s6.268 6 14 6 14-2.686 14-6-6.268-6-14-6"/><path fill="#00bcd4" d="M16 14a2 2 0 1 0 2 2 2 2 0 0 0-2-2"/><path fill="#00bcd4" d="M10.458 5.507c2.017 0 5.937 3.177 9.006 8.493 3.722 6.447 3.757 11.687 2.536 12.392a.9.9 0 0 1-.457.1c-2.017 0-5.938-3.176-9.007-8.492C8.814 11.553 8.779 6.313 10 5.608a.9.9 0 0 1 .458-.1m-.001-2A2.87 2.87 0 0 0 9 3.875C6.13 5.532 6.938 12.304 10.804 19c3.284 5.69 7.72 9.493 10.74 9.493A2.87 2.87 0 0 0 23 28.124c2.87-1.656 2.062-8.428-1.804-15.124-3.284-5.69-7.72-9.493-10.74-9.493Z"/><path fill="#00bcd4" d="M21.543 5.507a.9.9 0 0 1 .457.1c1.221.706 1.186 5.946-2.536 12.393-3.07 5.316-6.99 8.493-9.007 8.493a.9.9 0 0 1-.457-.1C8.779 25.686 8.814 20.446 12.536 14c3.07-5.316 6.99-8.493 9.007-8.493m0-2c-3.02 0-7.455 3.804-10.74 9.493C6.939 19.696 6.13 26.468 9 28.124a2.87 2.87 0 0 0 1.457.369c3.02 0 7.455-3.804 10.74-9.493C25.061 12.304 25.87 5.532 23 3.876a2.87 2.87 0 0 0-1.457-.369"/>`;
                break;
              case "py":
                vb = "0 0 24 24";
                inner = `<path fill="#0288d1" d="M9.86 2A2.86 2.86 0 0 0 7 4.86v1.68h4.29c.39 0 .71.57.71.96H4.86A2.86 2.86 0 0 0 2 10.36v3.781a2.86 2.86 0 0 0 2.86 2.86h1.18v-2.68a2.85 2.85 0 0 1 2.85-2.86h5.25c1.58 0 2.86-1.271 2.86-2.851V4.86A2.86 2.86 0 0 0 14.14 2zm-.72 1.61c.4 0 .72.12.72.71s-.32.891-.72.891c-.39 0-.71-.3-.71-.89s.32-.711.71-.711"/><path fill="#fdd835" d="M17.959 7v2.68a2.85 2.85 0 0 1-2.85 2.859H9.86A2.85 2.85 0 0 0 7 15.389v3.75a2.86 2.86 0 0 0 2.86 2.86h4.28A2.86 2.86 0 0 0 17 19.14v-1.68h-4.291c-.39 0-.709-.57-.709-.96h7.14A2.86 2.86 0 0 0 22 13.64V9.86A2.86 2.86 0 0 0 19.14 7zM8.32 11.513l-.004.004.038-.004zm6.54 7.276c.39 0 .71.3.71.89a.71.71 0 0 1-.71.71c-.4 0-.72-.12-.72-.71s.32-.89.72-.89"/>`;
                break;
              case "rs":
                vb = "0 0 32 32";
                inner = `<path fill="#ff7043" d="m30 12-4-2V6h-4l-2-4-4 2-4-2-2 4H6v4l-4 2 2 4-2 4 4 2v4h4l2 4 4-2 4 2 2-4h4v-4l4-2-2-4ZM6 16a9.9 9.9 0 0 1 .842-4H10v8H6.842A9.9 9.9 0 0 1 6 16m10 10a9.98 9.98 0 0 1-7.978-4H16v-2h-2v-2h4c.819.819.297 2.308 1.179 3.37a1.89 1.89 0 0 0 1.46.63h3.34A9.98 9.98 0 0 1 16 26m-2-12v-2h4a1 1 0 0 1 0 2Zm11.158 6H24a2.006 2.006 0 0 1-2-2 2 2 0 0 0-2-2 3 3 0 0 0 3-3q0-.08-.004-.161A3.115 3.115 0 0 0 19.83 10H8.022a9.986 9.986 0 0 1 17.136 10"/>`;
                break;
              case "go":
                vb = "0 0 32 32";
                inner = `<path fill="#00acc1" d="M2 12h4v2H2zm-2 4h6v2H0zm4 4h2v2H4zm16.954-5H14v3h3.239a4.42 4.42 0 0 1-3.531 2 2.65 2.65 0 0 1-2.053-.858 2.86 2.86 0 0 1-.628-2.28A4.515 4.515 0 0 1 15.292 13a2.73 2.73 0 0 1 1.749.584l2.962-1.185A5.6 5.6 0 0 0 15.292 10a7.526 7.526 0 0 0-7.243 6.5 5.614 5.614 0 0 0 5.659 6.5 7.526 7.526 0 0 0 7.243-6.5 6.4 6.4 0 0 0 .003-1.5"/><path fill="#00acc1" d="M26.292 10a7.526 7.526 0 0 0-7.243 6.5 5.614 5.614 0 0 0 5.659 6.5 7.526 7.526 0 0 0 7.243-6.5 5.614 5.614 0 0 0-5.659-6.5m2.681 6.137A4.515 4.515 0 0 1 24.708 20a2.65 2.65 0 0 1-2.053-.858 2.86 2.86 0 0 1-.628-2.28A4.515 4.515 0 0 1 26.292 13a2.65 2.65 0 0 1 2.053.858 2.86 2.86 0 0 1 .628 2.28Z"/>`;
                break;
              case "html":
                vb = "0 0 32 32";
                inner = `<path fill="#e65100" d="m4 4 2 22 10 2 10-2 2-22Zm19.72 7H11.28l.29 3h11.86l-.802 9.335L15.99 25l-6.635-1.646L8.93 19h3.02l.19 2 3.86.77 3.84-.77.29-4H8.84L8 8h16Z"/>`;
                break;
              case "css":
                vb = "0 0 32 32";
                inner = `<path fill="#7e57c2" d="M20 18h-2v-2h-2v2c0 .193 0 .703 1.254 1.033A3.345 3.345 0 0 1 20 22h2v2h2v-2c0-.388-.562-.851-1.254-1.034C20.356 20.34 20 18.84 20 18m-3.254 2.966C14.356 20.34 14 18.84 14 18h-2v-2h-2v8h2v-2h4v2h2v-2c0-.388-.562-.851-1.254-1.034"/><path fill="#7e57c2" d="M24 4H4v20a4 4 0 0 0 4 4h16.16A3.84 3.84 0 0 0 28 24.16V8a4 4 0 0 0-4-4m2 14h-2v-2h-2v2c0 .193 0 .703 1.254 1.033A3.345 3.345 0 0 1 26 22v2a2 2 0 0 1-2 2h-2a2 2 0 0 1-2-2 2 2 0 0 1-2 2h-2a2 2 0 0 1-2-2 2 2 0 0 1-2 2h-2a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2 2 2 0 0 1 2-2h2a2 2 0 0 1 2 2 2 2 0 0 1 2-2h2a2 2 0 0 1 2 2Z"/>`;
                break;
              case "scss":
                vb = "0 0 32 32";
                inner = `<path fill="#ec407a" d="M27.837 5.673a4.33 4.33 0 0 0-2.293-2.701c-2.362-1.261-6.11-1.298-9.548-.092a26.3 26.3 0 0 0-8.76 4.966c-2.752 2.542-3.438 4.925-3.189 6.194.523 2.668 3.274 4.539 5.485 6.042.418.284.822.559 1.175.816-1.429.76-4.261 2.444-5.088 4.248a3.88 3.88 0 0 0-.118 3.332A2.37 2.37 0 0 0 6.869 29.8a5.6 5.6 0 0 0 1.49.2 6.35 6.35 0 0 0 5.19-2.856 6.74 6.74 0 0 0 .864-5.382 7.3 7.3 0 0 1 2.044-.03 3.92 3.92 0 0 1 2.816 1.311 1.82 1.82 0 0 1 .423 1.262 1.55 1.55 0 0 1-.772 1.05c-.234.14-.586.355-.504.803.036.194.198.633.894.512a2.93 2.93 0 0 0 2.145-2.651 4 4 0 0 0-1.197-2.904 5.94 5.94 0 0 0-4.396-1.626 10.6 10.6 0 0 0-2.672.304 20 20 0 0 0-2.203-1.846c-1.712-1.3-3.33-2.529-3.235-4.26.125-2.263 2.468-4.532 6.964-6.744 4.016-1.976 7.254-2.037 8.944-1.438a2 2 0 0 1 1.204.883 2.77 2.77 0 0 1-.36 2.47 9.71 9.71 0 0 1-7.425 4.304 3.86 3.86 0 0 1-3.238-.757c-.278-.302-.593-.645-1.074-.383q-.565.31-.225 1.189a3.9 3.9 0 0 0 2.407 1.92 11.7 11.7 0 0 0 7.128-.671c3.527-1.35 6.681-5.202 5.756-8.787M11.895 24.475a4 4 0 0 1-.192.468 4.5 4.5 0 0 1-.753 1.081 2.83 2.83 0 0 1-2.533 1.107c-.056-.032-.078-.146-.085-.193a3.28 3.28 0 0 1 1.076-2.284 11.3 11.3 0 0 1 2.644-1.933 3.85 3.85 0 0 1-.157 1.754"/>`;
                break;
              case "svelte":
                vb = "0 0 300 300";
                inner = `<path fill="#ff5722" d="M175.94 24.328c-13.037.252-26.009 3.872-37.471 11.174L79.912 72.818a67.13 67.13 0 0 0-30.355 44.906 70.8 70.8 0 0 0 6.959 45.445 67.2 67.2 0 0 0-10.035 25.102 71.54 71.54 0 0 0 12.236 54.156c23.351 33.41 69.468 43.311 102.81 22.07l58.559-37.158a67.36 67.36 0 0 0 30.355-44.906 70.77 70.77 0 0 0-6.982-45.422 67.65 67.65 0 0 0 10.059-25.102 71.63 71.63 0 0 0-12.236-54.156v-.18c-15.324-21.925-40.453-33.727-65.342-33.246zm5.137 28.68a46.5 46.5 0 0 1 36.09 19.969 42.98 42.98 0 0 1 7.365 32.557 45 45 0 0 1-1.393 5.455l-1.123 3.37-2.986-2.247a75.9 75.9 0 0 0-22.902-11.45l-2.244-.651.201-2.246a13.16 13.16 0 0 0-2.379-8.711 13.99 13.99 0 0 0-14.953-5.412 12.8 12.8 0 0 0-3.594 1.572l-58.578 37.25a12.24 12.24 0 0 0-5.502 8.15 13.1 13.1 0 0 0 2.246 9.834 14.03 14.03 0 0 0 14.93 5.569 13.5 13.5 0 0 0 3.594-1.573l22.453-14.234a41.8 41.8 0 0 1 11.898-5.232 46.48 46.48 0 0 1 49.914 18.502 43.02 43.02 0 0 1 7.363 32.557 40.42 40.42 0 0 1-18.254 27.078l-58.58 37.316a43 43 0 0 1-11.898 5.23A46.545 46.545 0 0 1 82.81 227.14a42.98 42.98 0 0 1-7.341-32.557 38 38 0 0 1 1.39-5.41l1.102-3.37 3.008 2.246a75.9 75.9 0 0 0 22.836 11.361l2.244.65-.201 2.247a13.25 13.25 0 0 0 2.447 8.644 14.03 14.03 0 0 0 15.043 5.569 13.1 13.1 0 0 0 3.592-1.573l58.467-37.316a12.17 12.17 0 0 0 5.502-8.173 12.96 12.96 0 0 0-2.246-9.811 14.03 14.03 0 0 0-15.043-5.568 12.8 12.8 0 0 0-3.592 1.57l-22.453 14.258a42.9 42.9 0 0 1-11.877 5.209 46.52 46.52 0 0 1-49.846-18.5 43.02 43.02 0 0 1-7.297-32.557A40.42 40.42 0 0 1 96.798 96.98l58.646-37.316a42.8 42.8 0 0 1 11.811-5.21 46.5 46.5 0 0 1 13.822-1.444z"/>`;
                break;
              case "vue":
                vb = "0 0 24 24";
                inner = `<path fill="#41b883" d="M1.791 3.851 12 21.471 22.209 3.936V3.85H18.24l-6.18 10.616L5.906 3.851z"/><path fill="#35495e" d="m5.907 3.851 6.152 10.617L18.24 3.851h-3.723L12.084 8.03 9.66 3.85z"/>`;
                break;
              case "c":
                vb = "0 0 32 32";
                inner = `<path fill="#0288d1" d="M19.563 22A5.57 5.57 0 0 1 14 16.437v-2.873A5.57 5.57 0 0 1 19.563 8H24V2h-4.437A11.563 11.563 0 0 0 8 13.563v2.873A11.564 11.564 0 0 0 19.563 28H24v-6Z"/>`;
                break;
              case "cpp":
                vb = "0 0 32 32";
                inner = `<path fill="#0288d1" d="M28 14v-4h-2v4h-6v-4h-2v4h-4v2h4v4h2v-4h6v4h2v-4h4v-2z"/><path fill="#0288d1" d="M13.563 22A5.57 5.57 0 0 1 8 16.437v-2.873A5.57 5.57 0 0 1 13.563 8H18V2h-4.437A11.563 11.563 0 0 0 2 13.563v2.873A11.564 11.564 0 0 0 13.563 28H18v-6Z"/>`;
                break;
              case "objc":
                vb = "0 0 32 32";
                inner = `<path fill="#ffab40" d="M19.563 22A5.57 5.57 0 0 1 14 16.437v-2.873A5.57 5.57 0 0 1 19.563 8H24V2h-4.437A11.563 11.563 0 0 0 8 13.563v2.873A11.564 11.564 0 0 0 19.563 28H24v-6Z"/>`;
                break;
              case "cs":
                vb = "0 0 32 32";
                inner = `<path fill="#0288d1" d="M30 14v-2h-2V8h-2v4h-2V8h-2v4h-2v2h2v2h-2v2h2v4h2v-4h2v4h2v-4h2v-2h-2v-2Zm-4 2h-2v-2h2Zm-12.437 6A5.57 5.57 0 0 1 8 16.437v-2.873A5.57 5.57 0 0 1 13.563 8H18V2h-4.437A11.563 11.563 0 0 0 2 13.563v2.873A11.564 11.564 0 0 0 13.563 28H18v-6Z"/>`;
                break;
              case "java":
                vb = "0 0 32 32";
                inner = `<path fill="#f44336" d="M4 26h24v2H4zM28 4H7a1 1 0 0 0-1 1v13a4 4 0 0 0 4 4h10a4 4 0 0 0 4-4v-4h4a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2m0 8h-4V6h4Z"/>`;
                break;
              case "kt":
                vb = "0 0 24 24";
                inner = `<path fill="#b388ff" d="M2.975 2.976v18.048h18.05v-.03l-4.478-4.511-4.48-4.515 4.48-4.515 4.443-4.477z"/><path fill="#ff8a80" d="M2.975 2.976 12.018 12l9.007-9.024H2.975z" opacity=".75"/>`;
                break;
              case "dart":
                vb = "0 0 32 32";
                inner = `<path fill="#4fc3f7" d="M16.83 2a1.3 1.3 0 0 0-.916.377l-.013.01L7.323 7.34l8.556 8.55v.005l10.283 10.277 1.96-3.529-7.068-16.96-3.299-3.297A1.3 1.3 0 0 0 16.828 2Z"/><path fill="#01579b" d="m7.343 7.32-4.955 8.565-.01.013a1.297 1.297 0 0 0 .004 1.835l.005.005 4.106 4.107 16.064 6.314 3.632-2.015-.098-.098-.025.002L15.995 15.97h-.012z"/><path fill="#01579b" d="m7.321 7.324 8.753 8.755h.013L26.16 26.156l3.835-.73L30 14.089l-4.049-3.965a6.5 6.5 0 0 0-3.618-1.612l.002-.043L7.323 7.325Z"/><path fill="#64b5f6" d="m7.332 7.335 8.758 8.75v.013l10.079 10.071L25.436 30H14.09l-3.967-4.048a6.5 6.5 0 0 1-1.611-3.618l-.045.004Z"/>`;
                break;
              case "rb":
                vb = "0 0 24 24";
                inner = `<path fill="#f44336" d="M18.041 3.177c2.24.382 2.879 1.919 2.843 3.527V6.67l-1.013 13.266-13.132.897h.008c-1.093-.044-3.518-.151-3.634-3.545l1.217-2.222 2.462 5.74 2.097-6.77-.045.009.018-.018 6.85 2.186L13.945 9.3l6.53-.409-5.144-4.212 2.71-1.51v.009M3.113 17.252v.017zM6.916 6.874c2.63-2.622 6.033-4.168 7.34-2.844 1.297 1.306-.072 4.523-2.702 7.135-2.666 2.613-6.015 4.248-7.322 2.933-1.306-1.324.036-4.612 2.675-7.224z"/>`;
                break;
              case "php":
                vb = "0 0 24 24";
                inner = `<path fill="#1e88e5" d="M12 18.08c-6.63 0-12-2.72-12-6.08s5.37-6.08 12-6.08S24 8.64 24 12s-5.37 6.08-12 6.08m-5.19-7.95c.54 0 .91.1 1.09.31.18.2.22.56.13 1.03-.1.53-.29.87-.58 1.09q-.42.33-1.29.33h-.87l.53-2.76zm-3.5 5.55h1.44l.34-1.75h1.23c.54 0 .98-.06 1.33-.17.35-.12.67-.31.96-.58.24-.22.43-.46.58-.73.15-.26.26-.56.31-.88.16-.78.05-1.39-.33-1.82-.39-.44-.99-.65-1.82-.65H4.59zm7.25-8.33-1.28 6.58h1.42l.74-3.77h1.14c.36 0 .6.06.71.18s.13.34.07.66l-.57 2.93h1.45l.59-3.07c.13-.62.03-1.07-.27-1.36-.3-.27-.85-.4-1.65-.4h-1.27L12 7.35zM18 10.13c.55 0 .91.1 1.09.31.18.2.22.56.13 1.03-.1.53-.29.87-.57 1.09-.29.22-.72.33-1.3.33h-.85l.5-2.76zm-3.5 5.55h1.44l.34-1.75h1.22c.55 0 1-.06 1.35-.17.35-.12.65-.31.95-.58.24-.22.44-.46.58-.73.15-.26.26-.56.32-.88.15-.78.04-1.39-.34-1.82-.36-.44-.99-.65-1.82-.65h-2.75z"/>`;
                break;
              case "ar":
                vb = "0 0 24 24";
                inner = `<path fill="#7c4dff" d="M12 2L2 19h4.2l2.1-4h7.4l2.1 4H22L12 2zm-1.9 9.5L12 6.8l1.9 4.7h-3.8z"/>`;
                break;
              case "json":
                vb = "0 -960 960 960";
                inner = `<path fill="#f9a825" d="M560-160v-80h120q17 0 28.5-11.5T720-280v-80q0-38 22-69t58-44v-14q-36-13-58-44t-22-69v-80q0-17-11.5-28.5T680-720H560v-80h120q50 0 85 35t35 85v80q0 17 11.5 28.5T840-560h40v160h-40q-17 0-28.5 11.5T800-360v80q0 50-35 85t-85 35zm-280 0q-50 0-85-35t-35-85v-80q0-17-11.5-28.5T120-400H80v-160h40q17 0 28.5-11.5T160-600v-80q0-50 35-85t85-35h120v80H280q-17 0-28.5 11.5T240-680v80q0 38-22 69t-58 44v14q36 13 58 44t22 69v80q0 17 11.5 28.5T280-240h120v80z"/>`;
                break;
              case "nodejs":
                vb = "0 0 32 32";
                inner = `<path fill="#8bc34a" d="M16 20.003v2h4a2 2 0 0 0 2-2v-2a2 2 0 0 0-2-2h-2v-2h4v-2h-4a2 2 0 0 0-2 2v2a2 2 0 0 0 2 2h2v2Z"/><path fill="#8bc34a" d="m16 3.003-12 7v14l4 2h6v-13.5a.5.5 0 0 0-.5-.5h-1a.5.5 0 0 0-.5.5v11.5H8l-2-1.034V11.15l10-5.833 10 5.833v11.703l-10 5.833-1.745-1.022L13 29.253l3 1.75 12-7v-14Z"/>`;
                break;
              case "npm":
                vb = "0 0 32 32";
                inner = `<path fill="#e53935" d="M4 4v24h24V4Zm20 20h-4V12h-4v12H8V8h16Z"/>`;
                break;
              case "md":
                vb = "0 0 32 32";
                inner = `<path fill="#42a5f5" d="m14 10-4 3.5L6 10H4v12h4v-6l2 2 2-2v6h4V10zm12 6v-6h-4v6h-4l6 8 6-8z"/>`;
                break;
              case "toml":
                vb = "0 0 16 16";
                inner = `<path fill="#cfd8dc" d="M4 6V4h8v2H9v7H7V6z"/><path fill="#ef5350" d="M4 1v1H2v12h2v1H1V1zm8 0v1h2v12h-2v1h3V1z"/>`;
                break;
              case "xml":
                vb = "0 0 24 24";
                inner = `<path fill="#8bc34a" d="M13 9h5.5L13 3.5zM6 2h8l6 6v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V4c0-1.11.89-2 2-2m.12 13.5 3.74 3.74 1.42-1.41-2.33-2.33 2.33-2.33-1.42-1.41zm11.16 0-3.74-3.74-1.42 1.41 2.33 2.33-2.33 2.33 1.42 1.41z"/>`;
                break;
              case "yaml":
                vb = "0 0 24 24";
                inner = `<path fill="#ff5252" d="M13 9h5.5L13 3.5zM6 2h8l6 6v12c0 1.1-.9 2-2 2H6c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2m12 16v-2H9v2zm-4-4v-2H6v2z"/>`;
                break;
              case "sh":
                vb = "0 0 16 16";
                inner = `<path fill="#ff7043" d="M2 2a1 1 0 0 0-1 1v10c0 .554.446 1 1 1h12c.554 0 1-.446 1-1V3a1 1 0 0 0-1-1zm0 3h12v8H2zm1 2 2 2-2 2 1 1 3-3-3-3zm5 3.5V12h5v-1.5z"/>`;
                break;
              case "sql":
                vb = "0 0 32 32";
                inner = `<path fill="#ffca28" d="M16 24c-5.525 0-10-.9-10-2v4c0 1.1 4.475 2 10 2s10-.9 10-2v-4c0 1.1-4.475 2-10 2m0-8c-5.525 0-10-.9-10-2v4c0 1.1 4.475 2 10 2s10-.9 10-2v-4c0 1.1-4.475 2-10 2m0-12C10.477 4 6 4.895 6 6v4c0 1.1 4.475 2 10 2s10-.9 10-2V6c0-1.105-4.477-2-10-2"/>`;
                break;
              case "docker":
                vb = "0 0 24 24";
                inner = `<path fill="#0288d1" d="M21.81 10.25c-.06-.04-.56-.43-1.64-.43-.28 0-.56.03-.84.08-.21-1.4-1.38-2.11-1.43-2.14l-.29-.17-.18.27c-.24.36-.43.77-.51 1.19-.2.8-.08 1.56.33 2.21-.49.28-1.29.35-1.46.35H2.62c-.34 0-.62.28-.62.63 0 1.15.18 2.3.58 3.38.45 1.19 1.13 2.07 2 2.61.98.6 2.59.94 4.42.94.79 0 1.61-.07 2.42-.22 1.12-.2 2.2-.59 3.19-1.16A8.3 8.3 0 0 0 16.78 16c1.05-1.17 1.67-2.5 2.12-3.65h.19c1.14 0 1.85-.46 2.24-.85.26-.24.45-.53.59-.87l.08-.24zm-17.96.99h1.76c.08 0 .16-.07.16-.16V9.5c0-.08-.07-.16-.16-.16H3.85c-.09 0-.16.07-.16.16v1.58c.01.09.07.16.16.16m2.43 0h1.76c.08 0 .16-.07.16-.16V9.5c0-.08-.07-.16-.16-.16H6.28c-.09 0-.16.07-.16.16v1.58c.01.09.07.16.16.16m2.47 0h1.75c.1 0 .17-.07.17-.16V9.5c0-.08-.06-.16-.17-.16H8.75c-.08 0-.15.07-.15.16v1.58c0 .09.06.16.15.16m2.44 0h1.77c.08 0 .15-.07.15-.16V9.5c0-.08-.06-.16-.15-.16h-1.77c-.08 0-.15.07-.15.16v1.58c0 .09.07.16.15.16M6.28 9h1.76c.08 0 .16-.09.16-.18V7.25c0-.09-.07-.16-.16-.16H6.28c-.09 0-.16.06-.16.16v1.57c.01.09.07.18.16.18m2.47 0h1.75c.1 0 .17-.09.17-.18V7.25c0-.09-.06-.16-.17-.16H8.75c-.08 0-.15.06-.15.16v1.57c0 .09.06.18.15.18m2.44 0h1.77c.08 0 .15-.09.15-.18V7.25c0-.09-.07-.16-.15-.16h-1.77c-.08 0-.15.06-.15.16v1.57c0 .09.07.18.15.18m0-2.28h1.77c.08 0 .15-.07.15-.16V5c0-.1-.07-.17-.15-.17h-1.77c-.08 0-.15.06-.15.17v1.56c0 .08.07.16.15.16m2.46 4.52h1.76c.09 0 .16-.07.16-.16V9.5c0-.08-.07-.16-.16-.16h-1.76c-.08 0-.15.07-.15.16v1.58c0 .09.07.16.15.16"/>`;
                break;
              case "git":
                vb = "0 0 32 32";
                inner = `<path fill="#e64a19" d="M13.172 2.828 11.78 4.22l1.91 1.91 2 2A2.986 2.986 0 0 1 20 10.81a3.25 3.25 0 0 1-.31 1.31l2.06 2a2.68 2.68 0 0 1 3.37.57 2.86 2.86 0 0 1 .88 2.117 3.02 3.02 0 0 1-.856 2.109A2.9 2.9 0 0 1 23 19.81a2.93 2.93 0 0 1-2.13-.87 2.694 2.694 0 0 1-.56-3.38l-2-2.06a3 3 0 0 1-.31.12V20a3 3 0 0 1 1.44 1.09 2.92 2.92 0 0 1 .56 1.72 2.88 2.88 0 0 1-.878 2.128 2.98 2.98 0 0 1-2.048.871 2.981 2.981 0 0 1-2.514-4.719A3 3 0 0 1 16 20v-6.38a2.96 2.96 0 0 1-1.44-1.09 2.9 2.9 0 0 1-.56-1.72 2.9 2.9 0 0 1 .31-1.31l-3.9-3.9-7.579 7.572a4 4 0 0 0-.001 5.658l10.342 10.342a4 4 0 0 0 5.656 0l10.344-10.344a4 4 0 0 0 0-5.656L18.828 2.828a4 4 0 0 0-5.656 0"/>`;
                break;
              default:
                vb = "0 0 24 24";
                inner = `<path fill="#90a4ae" d="M14.6 16.6 19.2 12l-4.6-4.6L16 6l6 6-6 6-1.4-1.4m-5.2 0L4.8 12l4.6-4.6L8 6l-6 6 6 6 1.4-1.4z"/>`;
                break;
            }
            return `<span class="lang-icon-badge" style="width:${sz}px;height:${sz}px"><svg width="${sz}" height="${sz}" viewBox="${vb}" fill="none">${inner}</svg></span>`;
          }

          function renderCodeCard(lang, rawCode, fileHint) {
            const rawLang = (lang || "").trim();
            const cleanLang = rawLang.toLowerCase() || "code";
            const displayTitle = fileHint || rawLang || "code";
            const lines = (rawCode || "").replace(/\n$/, "").split("\n");
            const isDiff = cleanLang === "diff" || cleanLang === "patch" || lines.some(l => l.startsWith("@@ ") || (l.startsWith("+ ") && lines.some(x => x.startsWith("- "))));
            const encoded = encodeURIComponent(rawCode || "");
            let addedCount = 0;
            let removedCount = 0;
            const rows = lines.map((line, i) => {
              let cls = "code-line";
              if (isDiff) {
                if (line.startsWith("+") && !line.startsWith("+++")) { cls += " add"; addedCount++; }
                else if (line.startsWith("-") && !line.startsWith("---")) { cls += " del"; removedCount++; }
                else if (line.startsWith("@@")) cls += " hunk";
              }
              return `<div class="${cls}"><span class="ln">${i + 1}</span><span class="lc">${esc(line)}</span></div>`;
            }).join("");
            const diffStats = isDiff
              ? `${addedCount > 0 ? `<span class="diff-add" style="margin-left:5px">+${addedCount}</span>` : ""}${removedCount > 0 ? `<span class="diff-del" style="margin-left:4px">-${removedCount}</span>` : ""}`
              : "";
            const iconHTML = renderLangIcon(fileHint || cleanLang, cleanLang, 14);
            return `<div class="code-card">
              <div class="code-header">
                <span style="display:inline-flex;align-items:center;gap:6px;min-width:0">${iconHTML}<span class="code-lang" style="text-transform:${fileHint ? 'none' : 'uppercase'}">${esc(displayTitle)}</span>${diffStats} <span style="color:var(--muted)">· ${lines.length} line${lines.length === 1 ? "" : "s"}</span></span>
                <button class="copy-btn" onclick="copyCode(this, '${encoded}')">Copy</button>
              </div>
              <div class="code-lines">${rows}</div>
            </div>`;
          }

          function copyCode(btn, encoded) {
            try {
              navigator.clipboard.writeText(decodeURIComponent(encoded));
              btn.textContent = "Copied";
              setTimeout(() => { btn.textContent = "Copy"; }, 1400);
            } catch (_) {}
          }

          function formatInline(text) {
            let s = esc(text);
            // File links [label](file:///...) -> formal IDE file badge with authentic Language Icon
            s = s.replace(/\[\s*([^\]]+?)\s*\]\((?:file:\/\/[^)]+)\)/g, (_, label) => {
              return `<span class="file-pill">${renderLangIcon(label, "", 13)}<span class="file-name">${esc(label)}</span></span>`;
            });
            // Web links
            s = s.replace(/\[\s*([^\]]+?)\s*\]\((https?:\/\/[^)]+)\)/g, '<a href="$2" target="_blank" style="color:#93c5fd;text-decoration:underline">$1</a>');
            // Inline code
            s = s.replace(/`([^`\n]+)`/g, '<span class="inline-code">$1</span>');
            // Bold
            s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
            return s;
          }

          function parseProseSegment(segment) {
            const lines = (segment || "").split("\n");
            let out = [];
            let inUL = false;
            let inOL = false;
            const closeLists = () => {
              if (inUL) { out.push("</ul>"); inUL = false; }
              if (inOL) { out.push("</ol>"); inOL = false; }
            };
            for (let rawLine of lines) {
              const t = rawLine.trim();
              if (!t) { closeLists(); continue; }
              if (/^#{1,4}\s+/.test(t)) {
                closeLists();
                out.push(`<h3>${formatInline(t.replace(/^#{1,4}\s+/, ""))}</h3>`);
              } else if (/^[-*]\s+/.test(t)) {
                if (inOL) { out.push("</ol>"); inOL = false; }
                if (!inUL) { out.push("<ul>"); inUL = true; }
                out.push(`<li>${formatInline(t.replace(/^[-*]\s+/, ""))}</li>`);
              } else if (/^\d+\.\s+/.test(t)) {
                if (inUL) { out.push("</ul>"); inUL = false; }
                if (!inOL) { out.push("<ol>"); inOL = true; }
                out.push(`<li>${formatInline(t.replace(/^\d+\.\s+/, ""))}</li>`);
              } else if (t.startsWith("> ")) {
                closeLists();
                out.push(`<blockquote>${formatInline(t.slice(2))}</blockquote>`);
              } else {
                closeLists();
                out.push(`<p>${formatInline(rawLine)}</p>`);
              }
            }
            closeLists();
            return out.join("");
          }

          function parseMessageContent(raw) {
            if (!raw) return "";
            const fenceRegex = /```([^\r\n`]*)\r?\n([\s\S]*?)```/g;
            let lastIdx = 0;
            let parts = [];
            let match;
            while ((match = fenceRegex.exec(raw)) !== null) {
              if (match.index > lastIdx) {
                parts.push(parseProseSegment(raw.slice(lastIdx, match.index)));
              }
              parts.push(renderCodeCard(match[1], match[2]));
              lastIdx = fenceRegex.lastIndex;
            }
            if (lastIdx < raw.length) {
              const rest = raw.slice(lastIdx);
              const openFence = rest.match(/```([^\r\n`]*)\r?\n([\s\S]*)$/);
              if (openFence) {
                const before = rest.slice(0, openFence.index);
                if (before.trim()) parts.push(parseProseSegment(before));
                parts.push(renderCodeCard(openFence[1], openFence[2]));
              } else {
                parts.push(parseProseSegment(rest));
              }
            }
            return `<div class="prose">${parts.join("")}</div>`;
          }

          function renderToolItem(t, msgId, idx) {
            const drawerId = `tool-${msgId}-${idx}`;
            const isOpen = openDrawerIds.has(drawerId) ? "open" : "";
            if (t.kind === "analyze") {
              const lr = t.lineRange ? `<span class="line-range">${esc(t.lineRange)}</span>` : "";
              const body = t.output ? `<div class="tool-drawer"><pre class="tool-output-pre">${esc(t.output)}</pre></div>` : "";
              return `<details class="tool-row" data-did="${drawerId}" ${isOpen} ontoggle="trackDrawer(this)">
                <summary>
                  <span class="tool-verb">Analyzed</span>
                  <span class="file-pill">
                    ${renderLangIcon(t.target, t.ext, 14)}
                    <span class="file-name">${esc(t.target)}</span>
                    ${lr}
                  </span>
                  <span class="chev">›</span>
                </summary>
                ${body}
              </details>`;
            }
            if (t.kind === "edit") {
              const addStr = (t.added > 0 || t.removed === 0) ? `<span class="diff-add">+${t.added || 0}</span>` : "";
              const delStr = (t.removed > 0) ? `<span class="diff-del">-${t.removed}</span>` : "";
              const diffCard = t.diff ? renderCodeCard("diff", t.diff, t.target) : "";
              return `<details class="tool-row" data-did="${drawerId}" ${isOpen} ontoggle="trackDrawer(this)">
                <summary>
                  <span class="tool-verb">Edited</span>
                  <span class="file-pill">
                    ${renderLangIcon(t.target, t.ext, 14)}
                    <span class="file-name">${esc(t.target)}</span>
                    ${addStr} ${delStr}
                  </span>
                  <span class="chev">›</span>
                </summary>
                <div style="margin-left:10px">${diffCard}</div>
              </details>`;
            }
            if (t.kind === "command") {
              const exitNote = t.exitNote ? `<span class="diff-del">· ${esc(t.exitNote)}</span>` : "";
              const body = t.output ? `<div class="tool-drawer"><pre class="tool-output-pre">${esc(t.output)}</pre></div>` : "";
              return `<details class="tool-row" data-did="${drawerId}" ${isOpen} ontoggle="trackDrawer(this)">
                <summary>
                  <span class="tool-verb">Ran</span>
                  <span class="file-pill" style="background:rgba(255,255,255,0.03)">
                    ${renderLangIcon("sh", "sh", 13)}
                    <span class="cmd-summary">${esc(t.target)}</span>
                  </span>
                  ${exitNote}
                  <span class="chev">›</span>
                </summary>
                ${body}
              </details>`;
            }
            const body = t.output ? `<div class="tool-drawer"><pre class="tool-output-pre">${esc(t.output)}</pre></div>` : "";
            return `<details class="tool-row" data-did="${drawerId}" ${isOpen} ontoggle="trackDrawer(this)">
              <summary>
                <span class="tool-verb">${esc(t.verb || "Executed")}</span>
                <span class="cmd-summary">${esc(t.target)}</span>
                <span class="chev">›</span>
              </summary>
              ${body}
            </details>`;
          }

          function trackDrawer(el) {
            const id = el.getAttribute("data-did");
            if (!id) return;
            if (el.open) openDrawerIds.add(id);
            else openDrawerIds.delete(id);
          }

          let pollTimer = null;
          function schedulePoll(delayMs) {
            if (pollTimer) clearTimeout(pollTimer);
            pollTimer = setTimeout(pollLoop, delayMs);
          }

          async function pollLoop() {
            if (!document.hidden) {
              await pollState();
            }
            schedulePoll(isAgentLoading ? 380 : 1500);
          }

          async function pollState() {
            try {
              const s = await api("/api/state");
              document.getElementById("connDot").style.background = "#22c55e";
              document.getElementById("wsBreadcrumb").textContent = (s.workspace || "Workspace") + " / " + (s.sessionTitle || "Chat");
              document.getElementById("modelPillText").textContent = s.modelLabel || "Select Model";
              const provIconEl = document.getElementById("modelPillIcon");
              if (provIconEl && s.providerId && provIconEl.dataset.prov !== s.providerId) {
                provIconEl.dataset.prov = s.providerId;
                provIconEl.src = "/api/icon/provider?id=" + encodeURIComponent(s.providerId) + "&token=" + encodeURIComponent(TOKEN);
              }

              // Active Workspace Language Icon(s) in Header & Subbar
              const wsLangs = (s.workspaceLangs && s.workspaceLangs.length) ? s.workspaceLangs : [s.workspaceLang || "code"];
              const headerIconsHTML = wsLangs.slice(0, 2).map(l => renderLangIcon("", l, 13)).join("");
              const headerIconsEl = document.getElementById("wsHeaderLangIcons");
              if (headerIconsEl && headerIconsEl.dataset.key !== wsLangs.join(",")) {
                headerIconsEl.dataset.key = wsLangs.join(",");
                headerIconsEl.innerHTML = headerIconsHTML;
              }
              const subbarIconEl = document.getElementById("subbarWsIcon");
              if (subbarIconEl && subbarIconEl.dataset.key !== wsLangs[0]) {
                subbarIconEl.dataset.key = wsLangs[0];
                subbarIconEl.innerHTML = renderLangIcon("", wsLangs[0], 14);
              }

              const prevBtn = document.getElementById("previewBtn");
              if (s.webPreviewLANURL) {
                prevBtn.style.display = "inline-flex";
                prevBtn.href = s.webPreviewLANURL;
              } else {
                prevBtn.style.display = "none";
              }

              // Workspaces list (ordered 100% like Mac IDE)
              availableWorkspaces = s.workspaces || [];
              const wsSel = document.getElementById("workspaceSelect");
              const wsKey = JSON.stringify(availableWorkspaces.map(w => ({ p: w.path, n: w.name, a: w.active, c: w.chatCount, l: w.langLabel })));
              if (wsSel.dataset.key !== wsKey) {
                wsSel.dataset.key = wsKey;
                wsSel.innerHTML = availableWorkspaces.map(w => {
                  const countText = w.chatCount > 0 ? ` (${w.chatCount})` : "";
                  const langSuffix = w.langLabel && w.langLabel !== "Workspace" && w.langLabel !== "General" ? ` · ${w.langLabel}` : "";
                  return `<option value="${esc(w.path)}" ${w.active ? "selected" : ""}>${esc(w.name)}${langSuffix}${countText}</option>`;
                }).join("");
              }
              if (document.getElementById("workspaceModal").style.display === "flex") {
                renderWorkspaceList();
              }

              // Sessions dropdown for active workspace
              const sel = document.getElementById("sessionSelect");
              const sessKey = JSON.stringify(s.sessions || []);
              if (sel.dataset.key !== sessKey) {
                sel.dataset.key = sessKey;
                sel.innerHTML = (s.sessions || []).map(item =>
                  `<option value="${esc(item.id)}" ${item.active ? "selected" : ""}>${esc(item.name)}</option>`
                ).join("");
              }

              // Live Task Activity Bar & Composer State
              isAgentLoading = !!s.isLoading;
              updateComposerButtons();
              const activityBar = document.getElementById("liveActivityBar");
              if (isAgentLoading) {
                activityBar.style.display = "flex";
                document.getElementById("liveActivityText").textContent = s.currentTool || s.phase || "Running agent step…";
                const stepPill = document.getElementById("liveStepPill");
                if (s.stepCount > 0) {
                  stepPill.style.display = "inline-block";
                  stepPill.textContent = s.stepCount + (s.stepCount === 1 ? " step" : " steps");
                } else {
                  stepPill.style.display = "none";
                }
              } else {
                activityBar.style.display = "none";
              }

              // Approval Banners
              let bannersHTML = "";
              if (s.plan && s.plan.state === "pending") {
                bannersHTML += `<div class="approval-card">
                  <div class="approval-title">Implementation Plan Approval Required</div>
                  <div class="approval-desc">${esc(s.plan.title)} (${s.plan.totalSteps} steps)</div>
                  <div class="approval-actions">
                    <button class="btn-allow" onclick="api('/api/plan/approve',{})">Proceed</button>
                    <button class="btn-deny" onclick="api('/api/plan/reject',{})">Reject</button>
                  </div>
                </div>`;
              }
              if (s.pendingTool) {
                bannersHTML += `<div class="approval-card">
                  <div class="approval-title">Tool Execution Approval: ${esc(s.pendingTool.toolName)}</div>
                  <div class="approval-desc">${esc(s.pendingTool.description)}</div>
                  <div class="approval-actions">
                    <button class="btn-allow" onclick="api('/api/tool/approve',{})">Approve</button>
                    <button class="btn-deny" onclick="api('/api/tool/reject',{})">Deny</button>
                  </div>
                </div>`;
              }
              const bannersEl = document.getElementById("banners");
              if (bannersEl.innerHTML !== bannersHTML) bannersEl.innerHTML = bannersHTML;

              // Chat Messages
              const msgKey = JSON.stringify(s.messages || []) + "|" + isAgentLoading + "|" + (s.currentTool || "") + "|" + (s.workspacePath || "");
              if (msgKey !== lastRenderKey) {
                lastRenderKey = msgKey;
                const msgs = s.messages || [];
                if (msgs.length === 0) {
                  chatEl.innerHTML = `<div style="text-align:center;color:var(--secondary);margin-top:28vh;font-size:13px">MicroCode AI · ${esc(s.workspace)}<br><span style="color:var(--muted);font-size:12px">Synchronized with ${esc(s.macName)}</span></div>`;
                } else {
                  chatEl.innerHTML = msgs.map((m, mIdx) => {
                    if (m.role === "user") {
                      return `<div class="turn-user">${esc(m.content)}</div>`;
                    }
                    const tId = `thought-${m.id || mIdx}`;
                    const thoughtOpen = (m.thoughtStreaming || openDrawerIds.has(tId)) ? "open" : "";
                    const thoughtLabel = m.thoughtStreaming ? "Thinking…" : "Thought process";
                    const thoughtHTML = m.thought
                      ? `<details class="thought-block" data-did="${tId}" ${thoughtOpen} ontoggle="trackDrawer(this)">
                          <summary><span>${thoughtLabel}</span><span class="chev">›</span></summary>
                          <div class="thought-body">${esc(m.thought)}</div>
                        </details>`
                      : "";

                    const toolsHTML = (m.tools && m.tools.length)
                      ? `<div class="tool-list">` + m.tools.map((t, i) => renderToolItem(t, m.id || mIdx, i)).join("") + `</div>`
                      : "";

                    const bodyHTML = m.content ? parseMessageContent(m.content) : "";
                    return `<div class="turn-assistant">${thoughtHTML}${toolsHTML}${bodyHTML}</div>`;
                  }).join("");
                  if (autoScroll) chatEl.scrollTop = chatEl.scrollHeight;
                }
              }
            } catch (e) {
              document.getElementById("connDot").style.background = "#ef4444";
            }
          }

          async function sendPrompt(enqueueOnly) {
            const text = promptInput.value.trim();
            if (!text) return;
            promptInput.value = "";
            promptInput.style.height = "auto";
            updateComposerButtons();
            autoScroll = true;
            await api("/api/send", { prompt: text, enqueue: !!enqueueOnly });
            pollState();
          }

          async function stopAgent() {
            await api("/api/stop", {});
            pollState();
          }

          async function switchWorkspace(path, sessionId) {
            closeWorkspaceModal();
            await api("/api/workspace/switch", { path: path || "", sessionId: sessionId || "" });
            lastRenderKey = "";
            pollState();
          }

          async function switchSession(id) {
            closeWorkspaceModal();
            await api("/api/session/switch", { sessionId: id });
            lastRenderKey = "";
            pollState();
          }

          async function newSession(projectPath) {
            closeWorkspaceModal();
            await api("/api/session/new", projectPath ? { projectPath } : {});
            lastRenderKey = "";
            pollState();
          }

          function openWorkspaceModal() {
            document.getElementById("workspaceModal").style.display = "flex";
            document.getElementById("workspaceSearch").value = "";
            renderWorkspaceList();
          }

          function closeWorkspaceModal() {
            document.getElementById("workspaceModal").style.display = "none";
          }

          function renderWorkspaceList() {
            const q = (document.getElementById("workspaceSearch").value || "").toLowerCase().trim();
            const listEl = document.getElementById("workspaceList");
            let html = "";
            for (let i = 0; i < availableWorkspaces.length; i++) {
              const w = availableWorkspaces[i];
              const chats = w.chats || [];
              const matchWs = !q || (w.name || "").toLowerCase().includes(q) || (w.path || "").toLowerCase().includes(q) || (w.langLabel || "").toLowerCase().includes(q);
              const matchingChats = matchWs ? chats : chats.filter(c => (c.name || "").toLowerCase().includes(q));
              if (!matchWs && matchingChats.length === 0) continue;

              const wLangs = (w.langs && w.langs.length) ? w.langs : [w.lang || "code"];
              const langIconsHTML = `<span class="ws-lang-stack">` + wLangs.slice(0, 2).map(l => renderLangIcon("", l, 15)).join("") + `</span>`;
              const langTag = (w.langLabel && w.langLabel !== "Workspace") ? `<span class="ws-lang-tag">${esc(w.langLabel)}</span>` : "";
              const activeBadge = w.active ? `<span class="model-badge" style="color:var(--green)">Active</span>` : "";
              const countBadge = `<span class="ws-group-count">${w.chatCount || 0}</span>`;
              const chatsRows = matchingChats.map(c => {
                const check = c.active ? "✓ " : "";
                return `<div class="ws-chat-row ${c.active ? 'active' : ''}" data-widx="${i}" data-cid="${esc(c.id)}" onclick="selectWorkspaceChat(this)">
                  <span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${check}${esc(c.name)}</span>
                </div>`;
              }).join("");

              html += `<div class="ws-group-card ${w.active ? 'active' : ''}">
                <div class="ws-group-header" data-widx="${i}" onclick="selectWorkspaceGroup(this)">
                  <div class="ws-group-left">
                    ${langIconsHTML}
                    <span class="ws-group-name">${esc(w.name)}</span>
                    ${langTag}
                    ${activeBadge}
                  </div>
                  <div style="display:flex;align-items:center;gap:6px;flex-shrink:0">
                    ${countBadge}
                    <button class="tb-btn" style="padding:2px 7px;font-size:11px" data-widx="${i}" onclick="event.stopPropagation();createChatInWorkspace(this)">+ New</button>
                  </div>
                </div>
                ${chatsRows ? `<div class="ws-chat-list">${chatsRows}</div>` : ""}
              </div>`;
            }
            listEl.innerHTML = html || `<div style="padding:14px;color:var(--secondary);font-size:12px">No matching workspaces</div>`;
          }

          function selectWorkspaceGroup(el) {
            const idx = parseInt(el.getAttribute("data-widx"), 10);
            const w = availableWorkspaces[idx];
            if (w) switchWorkspace(w.path, "");
          }

          function selectWorkspaceChat(el) {
            const idx = parseInt(el.getAttribute("data-widx"), 10);
            const cid = el.getAttribute("data-cid") || "";
            const w = availableWorkspaces[idx];
            if (w) switchWorkspace(w.path, cid);
          }

          function createChatInWorkspace(el) {
            const idx = parseInt(el.getAttribute("data-widx"), 10);
            const w = availableWorkspaces[idx];
            if (w) newSession(w.path);
          }

          function togglePlanPrefix() {
            const modePill = document.getElementById("modePill");
            if (promptInput.value.startsWith("/plan ")) {
              promptInput.value = promptInput.value.slice(6);
              modePill.textContent = "Agent";
            } else {
              promptInput.value = "/plan " + promptInput.value;
              modePill.textContent = "Plan";
            }
            updateComposerButtons();
          }

          function cycleQuickPrefix() {
            if (!promptInput.value.startsWith("/")) {
              promptInput.value = "/plan " + promptInput.value;
            } else if (promptInput.value.startsWith("/plan ")) {
              promptInput.value = "/review " + promptInput.value.slice(6);
            } else {
              promptInput.value = promptInput.value.replace(/^\/\w+\s*/, "");
            }
            updateComposerButtons();
            promptInput.focus();
          }

          async function openModelModal() {
            document.getElementById("modelModal").style.display = "flex";
            document.getElementById("modelSearch").value = "";
            if (availableModels.length === 0) {
              document.getElementById("modelList").innerHTML = `<div style="padding:14px;color:var(--secondary);font-size:12px">Loading models…</div>`;
            } else {
              renderModelList();
            }
            try {
              const res = await api("/api/models");
              if (res && res.models) {
                availableModels = res.models;
                renderModelList();
              }
            } catch (e) {}
          }

          function closeModelModal() {
            document.getElementById("modelModal").style.display = "none";
          }

          function renderModelList() {
            const q = (document.getElementById("modelSearch").value || "").toLowerCase().trim();
            const listEl = document.getElementById("modelList");
            let currentGroup = "";
            let html = "";
            for (let i = 0; i < availableModels.length; i++) {
              const m = availableModels[i];
              if (q && !(m.name || "").toLowerCase().includes(q) && !(m.modelId || "").toLowerCase().includes(q) && !(m.group || "").toLowerCase().includes(q)) {
                continue;
              }
              if (m.group !== currentGroup) {
                currentGroup = m.group;
                html += `<div class="model-group-title">${esc(currentGroup)}</div>`;
              }
              const badge = m.badge ? `<span class="model-badge">${esc(m.badge)}</span>` : "";
              const check = m.active ? "✓ " : "";
              const provIcon = `/api/icon/provider?id=${encodeURIComponent(m.provider || "gemini")}&token=${encodeURIComponent(TOKEN)}`;
              html += `<div class="model-option ${m.active ? 'active' : ''}" data-midx="${i}" onclick="selectModelByIndex(this)">
                <span style="display:inline-flex;align-items:center;gap:8px;min-width:0"><img src="${provIcon}" width="15" height="15" style="border-radius:3px;flex-shrink:0;object-fit:contain" alt=""><span>${check}${esc(m.name)}</span></span>
                ${badge}
              </div>`;
            }
            listEl.innerHTML = html || `<div style="padding:14px;color:var(--secondary);font-size:12px">No matching models</div>`;
          }

          async function selectModelByIndex(el) {
            const idx = parseInt(el.getAttribute("data-midx"), 10);
            const m = availableModels[idx];
            if (!m) return;
            closeModelModal();
            await api("/api/model/select", { mode: m.mode, provider: m.provider, modelId: m.modelId });
            availableModels = [];
            pollState();
          }

          promptInput.addEventListener("keydown", (e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              sendPrompt(false);
            }
          });

          document.addEventListener("visibilitychange", () => {
            if (!document.hidden) pollLoop();
          });

          pollLoop();
        </script>
        </body>
        </html>
        """#
    }
}
