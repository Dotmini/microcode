//
//  LocalLLMGatewayService.swift
//  MicroCode
//
//  Zero-Setup Worldwide & LAN QR Gateway for Local LLM.
//  Works just like "Connect with Phone": scan a QR code from any iPhone, Android,
//  or remote MicroCode IDE anywhere in the world to chat with or route OpenAI-compatible
//  `/v1` API traffic directly to this Mac's Local LLM (Ollama, LM Studio, MLX, vLLM, etc.).
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

enum LocalLLMShareTransportMode: String, CaseIterable, Identifiable {
    case lan = "lan"
    case worldwide = "worldwide"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lan: return "Same Wi-Fi / LAN"
        case .worldwide: return "Worldwide HTTPS"
        }
    }

    var subtitle: String {
        switch self {
        case .lan: return "Instant (<2ms) • Same Wi-Fi, Hotspot, or Tailscale"
        case .worldwide: return "4G / 5G / Anywhere in the World • Zero-Setup HTTPS Tunnel"
        }
    }

    var icon: String {
        switch self {
        case .lan: return "wifi"
        case .worldwide: return "globe"
        }
    }
}

struct ConnectedLLMClient: Identifiable, Equatable {
    let id: String
    var ipAddress: String
    var via: String
    var requestCount: Int
    var lastSeenAt: Date
}

@MainActor
final class LocalLLMGatewayService: ObservableObject {
    static let shared = LocalLLMGatewayService()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "microcode.localLLMGateway.enabled")
            if isEnabled {
                startServerIfNeeded()
                if transportMode == .worldwide {
                    startWorldwideTunnel()
                }
            } else {
                stopWorldwideTunnel()
                stopServer()
            }
        }
    }

    @Published var transportMode: LocalLLMShareTransportMode = .worldwide {
        didSet {
            UserDefaults.standard.set(transportMode.rawValue, forKey: "microcode.localLLMGateway.mode")
            if transportMode == .worldwide && isEnabled {
                if case .connected = tunnelState {
                    // Already connected
                } else {
                    startWorldwideTunnel()
                }
            } else if transportMode == .lan {
                stopWorldwideTunnel()
            }
            regenerateQRCode()
        }
    }

    @Published private(set) var isServerRunning: Bool = false
    @Published private(set) var listeningPort: UInt16 = 8475
    @Published private(set) var lanIPAddress: String = "127.0.0.1"
    @Published private(set) var allNetworkAddresses: [(interface: String, ip: String)] = []
    @Published var selectedLANIP: String = "" {
        didSet { regenerateQRCode() }
    }
    @Published private(set) var apiToken: String = ""
    @Published private(set) var tunnelState: OnlineTunnelState = .stopped {
        didSet { regenerateQRCode() }
    }
    @Published private(set) var qrCodeImage: NSImage? = nil
    @Published private(set) var connectedClients: [ConnectedLLMClient] = []

    private var listener: NWListener?
    private let networkQueue = DispatchQueue(label: "com.dotmini.microcode.localllm-gateway", qos: .userInitiated)
    private var tunnelProcess: Process?
    private var lastGeneratedQRURL: String = ""

    private lazy var macNodeName: String = {
        let raw = ProcessInfo.processInfo.hostName
            .replacingOccurrences(of: ".local", with: "")
            .replacingOccurrences(of: "-", with: " ")
        return raw.isEmpty ? "Mac LLM" : raw
    }()

    private init() {
        self.isEnabled = (UserDefaults.standard.object(forKey: "microcode.localLLMGateway.enabled") as? Bool) ?? false
        if let savedMode = UserDefaults.standard.string(forKey: "microcode.localLLMGateway.mode"),
           let mode = LocalLLMShareTransportMode(rawValue: savedMode) {
            self.transportMode = mode
        }
        if let savedToken = UserDefaults.standard.string(forKey: "microcode.localLLMGateway.token"), !savedToken.isEmpty {
            self.apiToken = savedToken
        } else {
            let fresh = Self.generateAPIToken()
            self.apiToken = fresh
            UserDefaults.standard.set(fresh, forKey: "microcode.localLLMGateway.token")
        }
        refreshNetworkAddresses()
        if isEnabled {
            startServerIfNeeded()
        }
    }

    // MARK: - URLs, Deep Links & QR Code

    var activeLANHost: String {
        if !selectedLANIP.isEmpty { return selectedLANIP }
        if lanIPAddress != "127.0.0.1" { return lanIPAddress }
        return "127.0.0.1"
    }

    var lanOrigin: String {
        "http://\(activeLANHost):\(listeningPort)"
    }

    var worldwideOrigin: String? {
        if case .connected(let url, _) = tunnelState {
            return url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return nil
    }

    var activeOrigin: String {
        switch transportMode {
        case .lan:
            return lanOrigin
        case .worldwide:
            return worldwideOrigin ?? lanOrigin
        }
    }

    /// Scannable URL that opens the Mobile/Web Chat Console directly AND carries `?token=` for 1-click MicroCode pairing
    var activePairingURL: String {
        "\(activeOrigin)/?token=\(apiToken)"
    }

    /// Standard OpenAI-compatible Base URL (`.../v1`) for MicroCode, Cursor, Chatbox, OpenWebUI, Python/JS SDKs
    var activeOpenAIBaseURL: String {
        "\(activeOrigin)/v1"
    }

    var activeMicroCodeDeepLink: String {
        var comps = URLComponents()
        comps.scheme = "microcode"
        comps.host = "llm-connect"
        comps.queryItems = [
            URLQueryItem(name: "endpoint", value: activeOpenAIBaseURL),
            URLQueryItem(name: "token", value: apiToken),
            URLQueryItem(name: "name", value: macNodeName)
        ]
        return comps.string ?? activePairingURL
    }

    func rotateToken() {
        let fresh = Self.generateAPIToken()
        apiToken = fresh
        UserDefaults.standard.set(fresh, forKey: "microcode.localLLMGateway.token")
        connectedClients.removeAll()
        regenerateQRCode()
    }

    private static func generateAPIToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 18)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let body = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "sk-mc-\(body)"
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

        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(urlString.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else {
            qrCodeImage = nil
            return
        }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: 10.0, y: 10.0))
        if let cgImage = context.createCGImage(transformed, from: transformed.extent) {
            qrCodeImage = NSImage(
                cgImage: cgImage,
                size: NSSize(width: transformed.extent.width, height: transformed.extent.height)
            )
        }
    }

    // MARK: - Network Interfaces

    func refreshNetworkAddresses() {
        var found: [(interface: String, ip: String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        if getifaddrs(&ifaddr) == 0, let first = ifaddr {
            var ptr: UnsafeMutablePointer<ifaddrs>? = first
            while let current = ptr {
                let flags = Int32(current.pointee.ifa_flags)
                let isUp = (flags & IFF_UP) != 0
                let isLoopback = (flags & IFF_LOOPBACK) != 0
                if isUp && !isLoopback, let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                    let name = String(cString: current.pointee.ifa_name)
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        if !ip.hasPrefix("169.254.") && !ip.isEmpty {
                            found.append((interface: name, ip: ip))
                        }
                    }
                }
                ptr = current.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }

        found.sort { a, b in
            func rank(_ name: String) -> Int {
                if name == "en0" { return 0 }
                if name == "en1" { return 1 }
                if name.hasPrefix("en") { return 2 }
                if name.hasPrefix("bridge") { return 3 }
                return 4
            }
            return rank(a.interface) < rank(b.interface)
        }

        var unique: [(interface: String, ip: String)] = []
        var seen = Set<String>()
        for item in found where seen.insert(item.ip).inserted {
            unique.append(item)
        }

        allNetworkAddresses = unique
        lanIPAddress = unique.first?.ip ?? "127.0.0.1"
        if selectedLANIP.isEmpty || !seen.contains(selectedLANIP) {
            selectedLANIP = lanIPAddress
        }
        regenerateQRCode()
    }

    // MARK: - Embedded NWListener Server

    func startServerIfNeeded() {
        guard isEnabled else { return }
        guard !isServerRunning && listener == nil else { return }
        refreshNetworkAddresses()
        startServer(onPort: 8475)
    }

    private func startServer(onPort candidatePort: UInt16, attempt: Int = 0) {
        stopServer()
        guard let nwPort = NWEndpoint.Port(rawValue: candidatePort) else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        do {
            let newListener = try NWListener(using: params, on: nwPort)
            newListener.service = NWListener.Service(name: "MicroCode LLM (\(macNodeName))", type: "_microcode-llm._tcp")
            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self = self, self.listener === newListener else { return }
                    switch state {
                    case .ready:
                        if let actual = newListener.port?.rawValue {
                            self.listeningPort = actual
                        }
                        self.isServerRunning = true
                        if self.transportMode == .worldwide {
                            if case .connected = self.tunnelState {} else {
                                self.startWorldwideTunnel()
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
            newListener.newConnectionHandler = { [weak self] conn in
                self?.handleIncomingConnection(conn)
            }
            self.listener = newListener
            newListener.start(queue: networkQueue)
        } catch {
            if attempt < 15 {
                startServer(onPort: candidatePort + 1, attempt: attempt + 1)
            }
        }
    }

    func stopServer() {
        listener?.cancel()
        listener = nil
        isServerRunning = false
    }

    // MARK: - Zero-Setup Worldwide HTTPS Tunnel (Cloudflare Quick Tunnel + SSH Fallback)

    func startWorldwideTunnel() {
        stopWorldwideTunnel()
        tunnelState = .starting("Initializing Worldwide HTTPS Tunnel…")
        let port = Int(listeningPort)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/cloudflared",
            "/usr/local/bin/cloudflared",
            "\(home)/Library/Application Support/MicroCode/bin/cloudflared"
        ]
        if let cfBin = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            launchCloudflaredTunnel(binaryPath: cfBin, port: port)
        } else {
            launchSSHTunnel(port: port)
        }
    }

    func stopWorldwideTunnel() {
        if let proc = tunnelProcess, proc.isRunning {
            proc.terminate()
        }
        tunnelProcess = nil
        tunnelState = .stopped
    }

    private func launchCloudflaredTunnel(binaryPath: String, port: Int) {
        tunnelState = .starting("Starting Cloudflare Worldwide HTTPS Tunnel…")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = ["tunnel", "--url", "http://127.0.0.1:\(port)", "--no-autoupdate"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            if let range = text.range(of: #"https://[a-zA-Z0-9-]+\.trycloudflare\.com"#, options: .regularExpression) {
                let publicURL = String(text[range])
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if case .connected = self.tunnelState { return }
                    self.tunnelState = .connected(url: publicURL, provider: "Cloudflare Worldwide Edge")
                }
            }
        }

        proc.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                guard let self = self, self.tunnelProcess === proc else { return }
                if case .starting = self.tunnelState {
                    self.launchSSHTunnel(port: port)
                } else if self.transportMode == .worldwide && self.isEnabled {
                    self.tunnelState = .stopped
                }
            }
        }

        do {
            try proc.run()
            self.tunnelProcess = proc
        } catch {
            launchSSHTunnel(port: port)
        }
    }

    private func launchSSHTunnel(port: Int) {
        tunnelState = .starting("Starting macOS SSH Worldwide HTTPS Tunnel…")
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
                    self.tunnelState = .connected(url: publicURL, provider: "SSH Worldwide Tunnel")
                }
            }
        }

        proc.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                guard let self = self, self.tunnelProcess === proc else { return }
                if case .starting = self.tunnelState {
                    self.tunnelState = .failed("Could not establish worldwide HTTPS tunnel. Check internet connection or switch to Same Wi-Fi / LAN.")
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

    // MARK: - HTTP & Streaming SSE Reverse Proxy

    private func resolveUpstreamServer() -> DetectedLLMServer? {
        let ownPort = Int(listeningPort)
        let ownIPs = Set(allNetworkAddresses.map(\.ip) + ["127.0.0.1", "localhost"])
        if let active = LocalLLMService.shared.activeServer,
           active.isOnline,
           !active.requiresAuthToUnlock,
           !(ownIPs.contains(active.host) && active.port == ownPort) {
            return active
        }
        return LocalLLMService.shared.detectedServers.first { srv in
            srv.isOnline && !srv.requiresAuthToUnlock && !(ownIPs.contains(srv.host) && srv.port == ownPort)
        }
    }

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

            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
                let headerString = String(data: headerData, encoding: .utf8) ?? ""
                let bodyStart = headerEnd.upperBound
                let currentBodyLen = buffer.count - bodyStart

                var expectedLen = 0
                for line in headerString.components(separatedBy: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        let v = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                        expectedLen = Int(v) ?? 0
                    }
                }

                if currentBodyLen >= expectedLen || isComplete {
                    let bodyData = buffer.subdata(in: bodyStart..<min(buffer.count, bodyStart + expectedLen))
                    let remoteIP = Self.extractRemoteIP(from: connection)
                    Task { @MainActor in
                        await self.dispatchHTTPRequest(
                            headerString: headerString,
                            bodyData: bodyData,
                            remoteIP: remoteIP,
                            connection: connection
                        )
                    }
                    return
                }
            }

            if isComplete || error != nil || buffer.count > 4_194_304 {
                connection.cancel()
                return
            }
            self.receiveHTTPRequest(on: connection, accumulated: buffer)
        }
    }

    nonisolated private static func extractRemoteIP(from connection: NWConnection) -> String {
        if case .hostPort(let host, _) = connection.endpoint {
            return "\(host)".components(separatedBy: "%").first ?? "client"
        }
        return "client"
    }

    private func dispatchHTTPRequest(
        headerString: String,
        bodyData: Data,
        remoteIP: String,
        connection: NWConnection
    ) async {
        let lines = headerString.components(separatedBy: "\r\n")
        guard let reqLine = lines.first else {
            connection.cancel()
            return
        }
        let reqParts = reqLine.split(separator: " ")
        guard reqParts.count >= 2 else {
            connection.cancel()
            return
        }
        let method = String(reqParts[0]).uppercased()
        let rawTarget = String(reqParts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                let k = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                let v = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                headers[k] = v
            }
        }

        // CORS preflight
        if method == "OPTIONS" {
            sendSimpleResponse(on: connection, status: "204 No Content", contentType: "text/plain", body: Data())
            return
        }

        let comps = URLComponents(string: "http://localhost\(rawTarget)")
        let path = comps?.path ?? "/"
        let queryToken = comps?.queryItems?.first(where: { ["token", "key", "api_key"].contains($0.name.lowercased()) })?.value

        // Public lightweight metadata discovery ping for LAN MicroCode scanners (does NOT expose model inference)
        if method == "GET" && path == "/v1/gateway-info" {
            let upstream = resolveUpstreamServer()
            let info: [String: Any] = [
                "ok": true,
                "node": macNodeName,
                "engine": upstream?.type.rawValue ?? "Offline",
                "modelCount": upstream?.models.count ?? 0,
                "requiresAuth": true
            ]
            let data = (try? JSONSerialization.data(withJSONObject: info)) ?? Data("{}".utf8)
            sendSimpleResponse(on: connection, status: "200 OK", contentType: "application/json", body: data)
            return
        }

        // Authenticate via Bearer header, x-api-key, query `?token=`, or HttpOnly cookie
        let providedToken = Self.extractAuthToken(headers: headers, queryToken: queryToken)
        guard Self.constantTimeEquals(providedToken ?? "", apiToken) else {
            if method == "GET" && (path == "/" || path.isEmpty) {
                let html = Self.unauthorizedHTML(nodeName: macNodeName)
                sendSimpleResponse(on: connection, status: "401 Unauthorized", contentType: "text/html; charset=utf-8", body: Data(html.utf8))
            } else {
                let err = #"{"error":{"message":"Invalid or missing MicroCode Local LLM token. Scan the QR code in MicroCode -> Settings -> AI & Agent -> Local LLM.","type":"authentication_error"}}"#
                sendSimpleResponse(on: connection, status: "401 Unauthorized", contentType: "application/json", body: Data(err.utf8))
            }
            return
        }

        // Record authenticated client session
        let isProxiedTunnel = headers["cf-connecting-ip"] != nil || headers["x-forwarded-for"] != nil
        let effectiveClientIP = headers["cf-connecting-ip"] ?? headers["x-forwarded-for"]?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? remoteIP
        recordClientVisit(ip: effectiveClientIP, via: isProxiedTunnel ? "Worldwide" : "LAN")

        // 1. Mobile & Web Streaming Console (`GET /`)
        if method == "GET" && (path == "/" || path.isEmpty) {
            let upstream = resolveUpstreamServer()
            let html = Self.mobileWebConsoleHTML(
                nodeName: macNodeName,
                engineName: upstream?.displayName ?? "No Local LLM Running on Mac",
                apiToken: apiToken
            )
            let setCookie = "mc_llm_token=\(apiToken); Path=/; HttpOnly; SameSite=Lax"
            sendSimpleResponse(
                on: connection,
                status: "200 OK",
                contentType: "text/html; charset=utf-8",
                extraHeaders: ["Set-Cookie: \(setCookie)"],
                body: Data(html.utf8)
            )
            return
        }

        guard let upstream = resolveUpstreamServer() else {
            let err = #"{"error":{"message":"No Local LLM server (Ollama / LM Studio / MLX) is currently running on the host Mac.","type":"service_unavailable"}}"#
            sendSimpleResponse(on: connection, status: "503 Service Unavailable", contentType: "application/json", body: Data(err.utf8))
            return
        }

        // 2. OpenAI `/v1/models` & Ollama `/api/tags`
        if method == "GET" && (path == "/v1/models" || path == "/models") {
            let modelsList: [[String: Any]] = upstream.models.map { m in
                [
                    "id": m.id,
                    "object": "model",
                    "created": 1_740_000_000,
                    "owned_by": upstream.type.rawValue
                ]
            }
            let payload: [String: Any] = ["object": "list", "data": modelsList]
            let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data(#"{"object":"list","data":[]}"#.utf8)
            sendSimpleResponse(on: connection, status: "200 OK", contentType: "application/json", body: data)
            return
        }

        if method == "GET" && path == "/api/tags" {
            let modelsList: [[String: Any]] = upstream.models.map { m in
                ["name": m.id, "model": m.id]
            }
            let data = (try? JSONSerialization.data(withJSONObject: ["models": modelsList])) ?? Data(#"{"models":[]}"#.utf8)
            sendSimpleResponse(on: connection, status: "200 OK", contentType: "application/json", body: data)
            return
        }

        // 3. OpenAI `/v1/chat/completions` & `/v1/completions` (Streaming & Non-Streaming)
        if method == "POST" && (path.hasSuffix("/chat/completions") || path.hasSuffix("/completions")) {
            let suffix = path.hasSuffix("/chat/completions") ? "/chat/completions" : "/completions"
            guard let targetURL = URL(string: "\(upstream.endpoint)\(suffix)") else {
                sendSimpleResponse(on: connection, status: "502 Bad Gateway", contentType: "application/json", body: Data(#"{"error":{"message":"Invalid upstream URL"}}"#.utf8))
                return
            }

            var isStream = false
            if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                isStream = (json["stream"] as? Bool) == true
            }

            var upstreamReq = URLRequest(url: targetURL)
            upstreamReq.httpMethod = "POST"
            upstreamReq.timeoutInterval = 300
            upstreamReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let upKey = upstream.apiKey, !upKey.isEmpty {
                upstreamReq.setValue("Bearer \(upKey)", forHTTPHeaderField: "Authorization")
            }
            upstreamReq.httpBody = bodyData

            if isStream {
                await streamUpstreamSSE(request: upstreamReq, on: connection)
            } else {
                do {
                    let (respData, resp) = try await URLSession.shared.data(for: upstreamReq)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
                    sendSimpleResponse(on: connection, status: "\(code) OK", contentType: "application/json", body: respData)
                } catch {
                    let msg = #"{"error":{"message":"Upstream Local LLM request failed: \#(error.localizedDescription.replacingOccurrences(of: "\"", with: "'"))"}}"#
                    sendSimpleResponse(on: connection, status: "502 Bad Gateway", contentType: "application/json", body: Data(msg.utf8))
                }
            }
            return
        }

        sendSimpleResponse(on: connection, status: "404 Not Found", contentType: "application/json", body: Data(#"{"error":{"message":"Endpoint not found"}}"#.utf8))
    }

    private func streamUpstreamSSE(request: URLRequest, on connection: NWConnection) async {
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard (200...299).contains(statusCode) else {
                var errData = Data()
                for try await b in bytes {
                    errData.append(b)
                    if errData.count > 16384 { break }
                }
                sendSimpleResponse(on: connection, status: "\(statusCode) Error", contentType: "application/json", body: errData)
                return
            }

            let sseHeader = [
                "HTTP/1.1 200 OK",
                "Content-Type: text/event-stream; charset=utf-8",
                "Cache-Control: no-cache, no-transform",
                "Connection: close",
                "X-Accel-Buffering: no",
                "Access-Control-Allow-Origin: *",
                "X-MicroCode-LLM: 1",
                "X-MicroCode-Node: \(macNodeName)",
                "\r\n"
            ].joined(separator: "\r\n")

            try await sendChunk(Data(sseHeader.utf8), on: connection)

            for try await line in bytes.lines {
                let payload = "\(line)\n\n"
                try await sendChunk(Data(payload.utf8), on: connection)
            }
            connection.cancel()
        } catch {
            connection.cancel()
        }
    }

    private nonisolated func sendChunk(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { err in
                if let err {
                    cont.resume(throwing: err)
                } else {
                    cont.resume(returning: ())
                }
            })
        }
    }

    private func sendSimpleResponse(
        on connection: NWConnection,
        status: String,
        contentType: String,
        extraHeaders: [String] = [],
        body: Data
    ) {
        var headerLines = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Headers: Authorization, Content-Type, X-API-Key",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "X-MicroCode-LLM: 1",
            "X-MicroCode-Node: \(macNodeName)"
        ]
        headerLines.append(contentsOf: extraHeaders)
        let rawHeader = headerLines.joined(separator: "\r\n") + "\r\n\r\n"
        var packet = Data(rawHeader.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func recordClientVisit(ip: String, via: String) {
        let key = "\(ip)-\(via)"
        if let idx = connectedClients.firstIndex(where: { $0.id == key }) {
            connectedClients[idx].requestCount += 1
            connectedClients[idx].lastSeenAt = Date()
        } else {
            connectedClients.insert(
                ConnectedLLMClient(id: key, ipAddress: ip, via: via, requestCount: 1, lastSeenAt: Date()),
                at: 0
            )
            if connectedClients.count > 20 {
                connectedClients.removeLast()
            }
        }
    }

    private static func extractAuthToken(headers: [String: String], queryToken: String?) -> String? {
        if let auth = headers["authorization"] {
            if auth.lowercased().hasPrefix("bearer ") {
                return String(auth.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return auth.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let apiKey = headers["x-api-key"], !apiKey.isEmpty {
            return apiKey
        }
        if let q = queryToken, !q.isEmpty {
            return q
        }
        if let cookie = headers["cookie"] {
            for part in cookie.components(separatedBy: ";") {
                let kv = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
                if kv.count == 2 && kv[0] == "mc_llm_token" {
                    return String(kv[1])
                }
            }
        }
        return nil
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard !bBytes.isEmpty, aBytes.count == bBytes.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<aBytes.count {
            diff |= aBytes[i] ^ bBytes[i]
        }
        return diff == 0
    }

    // MARK: - Embedded Mobile & Web Console HTML (Scan QR Worldwide -> Instant Chat + API Config)

    private static func unauthorizedHTML(nodeName: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>MicroCode Local LLM</title>
        <style>body{background:#0b0c0e;color:#e5e7eb;font-family:-apple-system,BlinkMacSystemFont,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:20px}
        .card{max-width:380px;background:#14161a;border:1px solid rgba(255,255,255,.1);border-radius:14px;padding:24px;text-align:center}
        h2{margin:0 0 8px;font-size:17px}p{margin:0;color:#9ca3af;font-size:13px;line-height:1.5}</style></head>
        <body><div class="card"><h2>🔒 \(nodeName) · Protected Local LLM</h2>
        <p>Open <b>MicroCode → Settings → AI &amp; Agent → Local LLM</b> on your Mac and scan the Worldwide QR Code again.</p></div></body></html>
        """
    }

    private static func mobileWebConsoleHTML(nodeName: String, engineName: String, apiToken: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover">
        <title>\(nodeName) · MicroCode Local LLM</title>
        <style>
          :root { color-scheme: dark; }
          * { box-sizing: border-box; }
          body {
            margin: 0; background: #090a0c; color: #f3f4f6;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
            display: flex; flex-direction: column; height: 100dvh; overflow: hidden;
          }
          header {
            padding: 12px 14px; background: #111317;
            border-bottom: 1px solid rgba(255,255,255,0.08);
            display: flex; flex-direction: column; gap: 8px;
          }
          .toprow { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
          .brand { display: flex; align-items: center; gap: 8px; font-weight: 600; font-size: 14px; }
          .dot { width: 8px; height: 8px; border-radius: 50%; background: #22c55e; box-shadow: 0 0 8px #22c55e; }
          .sub { font-size: 11px; color: #9ca3af; }
          .controls { display: flex; gap: 6px; align-items: center; }
          select, button, input {
            background: #1a1d24; color: #f3f4f6; border: 1px solid rgba(255,255,255,0.12);
            border-radius: 8px; padding: 6px 10px; font-size: 12px; outline: none;
          }
          select { flex: 1; min-width: 0; }
          button { cursor: pointer; font-weight: 500; white-space: nowrap; }
          button.primary { background: #2563eb; border-color: #3b82f6; color: #fff; }
          #apiDrawer {
            display: none; background: #14171f; border-bottom: 1px solid rgba(255,255,255,0.08);
            padding: 12px 14px; font-size: 12px;
          }
          .kv { display: flex; gap: 6px; align-items: center; margin-top: 6px; }
          .kv code {
            flex: 1; background: #0b0d11; padding: 6px 8px; border-radius: 6px;
            border: 1px solid rgba(255,255,255,0.08); overflow-x: auto; white-space: nowrap; font-size: 11px;
          }
          #chat {
            flex: 1; overflow-y: auto; padding: 14px; display: flex; flex-direction: column; gap: 10px;
          }
          .msg {
            max-width: 88%; padding: 10px 12px; border-radius: 12px; font-size: 13.5px;
            line-height: 1.48; white-space: pre-wrap; word-break: break-word;
          }
          .msg.user { align-self: flex-end; background: #2563eb; color: #fff; border-bottom-right-radius: 4px; }
          .msg.assistant {
            align-self: flex-start; background: #151821; border: 1px solid rgba(255,255,255,0.08);
            border-bottom-left-radius: 4px;
          }
          .meta { font-size: 10.5px; color: #9ca3af; margin-top: 5px; font-family: ui-monospace, SFMono-Regular, monospace; }
          footer {
            padding: 10px 12px calc(10px + env(safe-area-inset-bottom));
            background: #111317; border-top: 1px solid rgba(255,255,255,0.08);
            display: flex; gap: 8px;
          }
          #prompt { flex: 1; font-size: 14px; padding: 9px 12px; border-radius: 10px; }
        </style>
        </head>
        <body>
        <header>
          <div class="toprow">
            <div>
              <div class="brand"><span class="dot"></span><span>\(nodeName)</span></div>
              <div class="sub" id="engineLabel">\(engineName)</div>
            </div>
            <div style="display:flex;gap:6px">
              <button onclick="toggleDrawer()">API / IDE</button>
              <button onclick="clearChat()">Clear</button>
            </div>
          </div>
          <div class="controls">
            <select id="modelSelect"><option value="">Loading models…</option></select>
          </div>
        </header>
        <div id="apiDrawer">
          <div style="font-weight:600;margin-bottom:4px">Use Worldwide in MicroCode or Any OpenAI App</div>
          <div class="kv">
            <code id="baseUrlBox"></code>
            <button onclick="copyText(document.getElementById('baseUrlBox').textContent)">Copy /v1</button>
          </div>
          <div class="kv">
            <code id="tokenBox">\(apiToken)</code>
            <button onclick="copyText('\(apiToken)')">Copy Key</button>
          </div>
          <div style="margin-top:8px;display:flex;gap:8px">
            <button class="primary" onclick="openInMicroCode()" style="width:100%">⚡ Connect Remote MicroCode IDE</button>
          </div>
        </div>
        <div id="chat">
          <div class="msg assistant">Connected directly to <b>\(nodeName)</b> Local LLM. Ask anything or tap <b>API / IDE</b> above to pair another device worldwide.</div>
        </div>
        <footer>
          <input id="prompt" type="text" placeholder="Message your Local LLM…" autocomplete="off" onkeydown="if(event.key==='Enter'){sendMsg()}">
          <button class="primary" id="sendBtn" onclick="sendMsg()">Send</button>
        </footer>
        <script>
          const TOKEN = \(Self.jsStringLiteral(apiToken));
          const NODE_NAME = \(Self.jsStringLiteral(nodeName));
          const baseV1 = window.location.origin + "/v1";
          document.getElementById("baseUrlBox").textContent = baseV1;
          let messages = [];
          let aborter = null;

          function toggleDrawer() {
            const el = document.getElementById("apiDrawer");
            el.style.display = el.style.display === "block" ? "none" : "block";
          }
          function copyText(t) { navigator.clipboard && navigator.clipboard.writeText(t); }
          function openInMicroCode() {
            const u = "microcode://llm-connect?endpoint=" + encodeURIComponent(baseV1) + "&token=" + encodeURIComponent(TOKEN) + "&name=" + encodeURIComponent(NODE_NAME);
            window.location.href = u;
          }
          function clearChat() {
            messages = [];
            document.getElementById("chat").innerHTML = "";
          }
          async function loadModels() {
            try {
              const r = await fetch("/v1/models", { headers: { "Authorization": "Bearer " + TOKEN } });
              const j = await r.json();
              const sel = document.getElementById("modelSelect");
              sel.innerHTML = "";
              (j.data || []).forEach(m => {
                const o = document.createElement("option");
                o.value = m.id; o.textContent = m.id;
                sel.appendChild(o);
              });
              if (!sel.options.length) {
                sel.innerHTML = '<option value="local-model">No models loaded on Mac</option>';
              }
            } catch (e) {}
          }
          loadModels();

          async function sendMsg() {
            if (aborter) { aborter.abort(); aborter = null; return; }
            const input = document.getElementById("prompt");
            const text = input.value.trim();
            if (!text) return;
            input.value = "";
            const chat = document.getElementById("chat");

            const uDiv = document.createElement("div");
            uDiv.className = "msg user";
            uDiv.textContent = text;
            chat.appendChild(uDiv);

            const aDiv = document.createElement("div");
            aDiv.className = "msg assistant";
            const bodySpan = document.createElement("div");
            bodySpan.textContent = "…";
            const metaDiv = document.createElement("div");
            metaDiv.className = "meta";
            aDiv.appendChild(bodySpan);
            aDiv.appendChild(metaDiv);
            chat.appendChild(aDiv);
            chat.scrollTop = chat.scrollHeight;

            messages.push({ role: "user", content: text });
            const model = document.getElementById("modelSelect").value || "local-model";
            const btn = document.getElementById("sendBtn");
            btn.textContent = "Stop";
            aborter = new AbortController();

            const t0 = performance.now();
            let tFirst = null;
            let chunks = 0;
            let full = "";

            try {
              const res = await fetch("/v1/chat/completions", {
                method: "POST",
                headers: { "Content-Type": "application/json", "Authorization": "Bearer " + TOKEN },
                body: JSON.stringify({ model, messages, stream: true }),
                signal: aborter.signal
              });
              const reader = res.body.getReader();
              const dec = new TextDecoder();
              let buf = "";
              while (true) {
                const { value, done } = await reader.read();
                if (done) break;
                buf += dec.decode(value, { stream: true });
                const lines = buf.split("\\n");
                buf = lines.pop() || "";
                for (const raw of lines) {
                  const line = raw.trim();
                  if (!line.startsWith("data:")) continue;
                  const payload = line.slice(5).trim();
                  if (payload === "[DONE]") break;
                  try {
                    const obj = JSON.parse(payload);
                    const delta = (obj.choices && obj.choices[0] && obj.choices[0].delta) || {};
                    const piece = delta.content || delta.reasoning_content || "";
                    if (piece) {
                      if (tFirst === null) tFirst = performance.now();
                      chunks++;
                      full += piece;
                      bodySpan.textContent = full;
                      const elapsed = Math.max(0.02, (performance.now() - tFirst) / 1000);
                      const approxTok = Math.max(chunks, full.length / 3.8);
                      metaDiv.textContent = "⚡ " + (approxTok / elapsed).toFixed(1) + " tok/s · TTFT " + Math.round(tFirst - t0) + " ms";
                      chat.scrollTop = chat.scrollHeight;
                    }
                  } catch (_) {}
                }
              }
              if (full) messages.push({ role: "assistant", content: full });
            } catch (err) {
              if (!full) bodySpan.textContent = "Error: " + err.message;
            } finally {
              aborter = null;
              btn.textContent = "Send";
            }
          }
        </script>
        </body>
        </html>
        """
    }

    private static func jsStringLiteral(_ s: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [s]),
           let arr = String(data: data, encoding: .utf8),
           arr.count >= 2 {
            return String(arr.dropFirst().dropLast())
        }
        return "\"\""
    }
}
