//
//  CollaborationService.swift
//  MicroCode
//
//  Zero-Setup Multi-User Team Collaboration Engine
//  Supports Embedded LAN Host (NWListener + Bonjour mDNS), Online HTTPS Tunnel,
//  CRDT Real-Time Co-Editing, Follow Mode, AI File Lock Guard, Team Task Sync,
//  and Zero-Install Web Collaboration Portal.
//
//  Dotmini Company Limited
//

import Foundation
import Combine
import AppKit
import Network
import CoreImage.CIFilterBuiltins

// MARK: - Collaboration Session & Models

struct CollaborationSession: Identifiable, Codable, Equatable {
    let id: String
    var projectId: String
    var workspaceName: String = "Workspace"
    var workspaceLang: String = "code"
    var hostUserId: String
    var hostDisplayName: String = "Host"
    var participants: [Participant]
    var isActive: Bool
    var createdAt: Date
    var shareCode: String
    var isHostingLocally: Bool = true
    var remoteEndpoint: String = ""
    
    struct Participant: Identifiable, Codable, Equatable {
        var id: String
        var userId: String
        var displayName: String
        var role: String = "Editor" // Host, Editor, Reviewer, Web
        var color: String
        var cursorPosition: CursorPosition?
        var activeTaskTitle: String? = nil
        var isAIActive: Bool = false
        var aiStatusText: String? = nil
        var isOnline: Bool
        var joinedAt: Date
        var lastSeenAt: Date = Date()
    }
    
    struct CursorPosition: Codable, Equatable {
        var filePath: String
        var line: Int
        var column: Int
    }
}

struct SharedWorkspaceFile: Identifiable, Codable, Equatable {
    var id: String { relativePath }
    var relativePath: String
    var name: String
    var language: String
    var isOpenOnHost: Bool
    var activeEditorName: String?
    var activeEditorColor: String?
}

struct DiscoveredCollabSession: Identifiable, Equatable {
    let id: String
    let serviceName: String
    let hostName: String
    let workspaceName: String
    let workspaceLang: String
    let shareCode: String
    let hostAddress: String
    let port: UInt16
    var endpointURL: String {
        "http://\(hostAddress):\(port)/?code=\(shareCode)"
    }
}

// MARK: - Collaboration Message (Legacy + Extended Wire Protocol)

enum CollaborationMessage: Codable {
    case join(userId: String, displayName: String)
    case leave(userId: String)
    case cursorMove(userId: String, position: CollaborationSession.CursorPosition)
    case textChange(userId: String, change: TextChange)
    case fileOpen(userId: String, filePath: String)
    case sync(files: [String: String])
    case chat(userId: String, message: String)
    
    struct TextChange: Codable, Equatable {
        var filePath: String
        var startLine: Int
        var startColumn: Int
        var endLine: Int
        var endColumn: Int
        var text: String
        var timestamp: Date
    }
}

// MARK: - Collaboration Service

@MainActor
final class CollaborationService: ObservableObject {
    static let shared = CollaborationService()
    
    // MARK: - Published State
    
    @Published var currentSession: CollaborationSession?
    @Published var participants: [CollaborationSession.Participant] = []
    @Published var isConnected: Bool = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var pendingChanges: [CollaborationMessage.TextChange] = []
    @Published var chatMessages: [ChatMessage] = []
    @Published var activityLog: [ActivityItem] = []
    
    // Shared Workspace Files & Locks
    @Published var sharedFiles: [SharedWorkspaceFile] = []
    @Published var fileContents: [String: String] = [:] // relativePath -> latest merged content
    @Published var fileRevisions: [String: Int] = [:]   // relativePath -> revision counter
    @Published var activeFileLocks: [String: (userId: String, name: String, color: String)] = [:]
    
    // Follow Mode
    @Published var followingUserId: String? = nil
    
    // Local User Profile (Zero-Setup: No Sign-In Required)
    @Published var localUserId: String
    @Published var localDisplayName: String {
        didSet {
            UserDefaults.standard.set(localDisplayName, forKey: "collabDisplayName")
            updateSelfInParticipants()
        }
    }
    @Published var localRole: String {
        didSet {
            UserDefaults.standard.set(localRole, forKey: "collabUserRole")
            updateSelfInParticipants()
        }
    }
    @Published var localColor: String
    
    // Transport & Tunnel State
    @Published var listeningPort: UInt16 = 8472
    @Published var isServerRunning: Bool = false
    @Published var lanAddresses: [String] = []
    @Published var selectedLANAddress: String = "127.0.0.1"
    @Published var transportMode: TransportMode = .lan
    @Published var tunnelStatus: TunnelStatus = .idle
    @Published var publicTunnelURL: String? = nil
    @Published var qrCodeImage: NSImage? = nil
    
    // Bonjour / LAN Auto-Discovery
    @Published var discoveredSessions: [DiscoveredCollabSession] = []
    
    enum TransportMode: String, CaseIterable, Identifiable {
        case lan = "LAN / P2P"
        case online = "Online Tunnel"
        var id: String { rawValue }
    }
    
    enum TunnelStatus: Equatable {
        case idle
        case starting
        case active(String)
        case failed(String)
    }
    
    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case error(String)
    }
    
    struct ChatMessage: Identifiable, Codable, Equatable {
        var id: String = UUID().uuidString
        let userId: String
        let displayName: String
        let userColor: String
        let message: String
        let timestamp: Date
        
        init(id: String = UUID().uuidString, userId: String, displayName: String, userColor: String = "#3B82F6", message: String, timestamp: Date = Date()) {
            self.id = id
            self.userId = userId
            self.displayName = displayName
            self.userColor = userColor
            self.message = message
            self.timestamp = timestamp
        }
    }
    
    struct ActivityItem: Identifiable, Codable, Equatable {
        var id: String = UUID().uuidString
        let actorName: String
        let actorColor: String
        let action: String
        let target: String
        let timestamp: Date
    }
    
    // MARK: - Internal Properties
    
    let crdtEngine = CRDTEngine.shared
    private var crdtDocuments: [String: CRDTDocument] = [:]
    
    private var listener: NWListener?
    private var netService: NetService?
    private var browser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []
    private let networkQueue = DispatchQueue(label: "com.dotmini.microcode.collab.net", qos: .userInteractive)
    
    private var peerSyncTimer: Timer?
    private var hostMaintenanceTimer: Timer?
    private var tunnelProcess: Process?
    private var tunnelOutputPipe: Pipe?
    private var isApplyingRemoteEdit: Bool = false
    private var lastSyncedLocalFileHashes: [String: Int] = [:]
    
    private static let formalPalette = [
        "#64748B", // Muted Slate
        "#52525B", // Zinc Graphite
        "#475569", // Steel Gray
        "#71717A", // Neutral Zinc
        "#57534E", // Warm Stone
        "#4B5563"  // Cool Gray
    ]
    
    // MARK: - Init
    
    private init() {
        let savedId = UserDefaults.standard.string(forKey: "collabUserId") ?? {
            let newId = "usr-" + UUID().uuidString.prefix(8).lowercased()
            UserDefaults.standard.set(newId, forKey: "collabUserId")
            return newId
        }()
        self.localUserId = savedId
        
        let existingColor = UserDefaults.standard.string(forKey: "collabUserColor")
        let savedColor: String
        if let existing = existingColor, Self.formalPalette.contains(existing) {
            savedColor = existing
        } else {
            let c = Self.formalPalette.first ?? "#64748B"
            UserDefaults.standard.set(c, forKey: "collabUserColor")
            savedColor = c
        }
        self.localColor = savedColor
        self.localRole = UserDefaults.standard.string(forKey: "collabUserRole") ?? "Editor"
        
        if let savedName = UserDefaults.standard.string(forKey: "collabDisplayName"), !savedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.localDisplayName = savedName
        } else if let authName = AuthService.shared.currentUser?.displayName, !authName.isEmpty {
            self.localDisplayName = authName
        } else {
            let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
            self.localDisplayName = full.isEmpty ? (Host.current().localizedName ?? "Developer") : full
        }
        
        refreshNetworkAddresses()
        startBonjourDiscovery()
    }
    
    // MARK: - Network & Bonjour Discovery
    
    func refreshNetworkAddresses() {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr {
            for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
                let flags = Int32(ptr.pointee.ifa_flags)
                let addr = ptr.pointee.ifa_addr.pointee
                if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING),
                   addr.sa_family == UInt8(AF_INET) {
                    let name = String(cString: ptr.pointee.ifa_name)
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        if !ip.hasPrefix("169.254.") && !ip.hasPrefix("127.") {
                            if name == "en0" || name == "en1" {
                                addresses.insert(ip, at: 0)
                            } else {
                                addresses.append(ip)
                            }
                        }
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        var unique: [String] = []
        for a in addresses where !unique.contains(a) { unique.append(a) }
        if unique.isEmpty { unique = ["127.0.0.1"] }
        self.lanAddresses = unique
        if !unique.contains(selectedLANAddress) {
            self.selectedLANAddress = unique.first ?? "127.0.0.1"
        }
        regenerateQRCode()
    }
    
    func startBonjourDiscovery() {
        browser?.stop()
        let netBrowser = NetServiceBrowser()
        netBrowser.delegate = BonjourBrowserDelegate.shared
        netBrowser.searchForServices(ofType: "_microcode-collab._tcp.", inDomain: "local.")
        self.browser = netBrowser
    }
    
    fileprivate func handleDiscoveredService(_ service: NetService, moreComing: Bool) {
        if !resolvingServices.contains(service) {
            resolvingServices.append(service)
            service.delegate = BonjourBrowserDelegate.shared
            service.resolve(withTimeout: 5.0)
        }
    }
    
    fileprivate func handleRemovedService(_ service: NetService) {
        resolvingServices.removeAll { $0 == service }
        discoveredSessions.removeAll { $0.serviceName == service.name }
    }
    
    fileprivate func handleResolvedService(_ service: NetService) {
        guard service.port > 0 else { return }
        var txtDict: [String: String] = [:]
        if let data = service.txtRecordData() {
            let raw = NetService.dictionary(fromTXTRecord: data)
            for (k, v) in raw {
                if let str = String(data: v, encoding: .utf8) {
                    txtDict[k] = str
                }
            }
        }
        let code = txtDict["code"] ?? ""
        guard !code.isEmpty else { return }
        // Don't show our own hosted session in discovered list
        if currentSession?.shareCode == code && currentSession?.isHostingLocally == true {
            return
        }
        let hostIP = extractIPv4(from: service.addresses) ?? service.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? "127.0.0.1"
        let wsName = txtDict["ws"] ?? "Workspace"
        let wsLang = txtDict["lang"] ?? "code"
        let hostUser = txtDict["host"] ?? service.name
        
        let item = DiscoveredCollabSession(
            id: "\(hostIP):\(service.port)#\(code)",
            serviceName: service.name,
            hostName: hostUser,
            workspaceName: wsName,
            workspaceLang: wsLang,
            shareCode: code,
            hostAddress: hostIP,
            port: UInt16(service.port)
        )
        if let idx = discoveredSessions.firstIndex(where: { $0.shareCode == code }) {
            discoveredSessions[idx] = item
        } else {
            discoveredSessions.append(item)
        }
    }
    
    private func extractIPv4(from addresses: [Data]?) -> String? {
        guard let addresses else { return nil }
        for data in addresses {
            var storage = sockaddr_storage()
            (data as NSData).getBytes(&storage, length: min(data.count, MemoryLayout<sockaddr_storage>.size))
            if Int32(storage.ss_family) == AF_INET {
                var addr = withUnsafePointer(to: &storage) {
                    $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                let ip = String(cString: buffer)
                if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") {
                    return ip
                }
            }
        }
        return nil
    }
    
    // MARK: - Session Management (Host & Join)
    
    @discardableResult
    func createSession(projectId: String = "") async throws -> CollaborationSession {
        refreshNetworkAddresses()
        let shareCode = generateShareCode()
        let wsInfo = currentWorkspaceMetadata()
        
        // Start Embedded Host Server
        startEmbeddedHostServer(shareCode: shareCode, workspaceName: wsInfo.name, workspaceLang: wsInfo.lang)
        
        let hostParticipant = CollaborationSession.Participant(
            id: localUserId,
            userId: localUserId,
            displayName: localDisplayName,
            role: "Host",
            color: localColor,
            cursorPosition: currentLocalCursorPosition(),
            activeTaskTitle: TeamTaskService.shared.selectedTask?.title,
            isAIActive: AgentService.shared.isLoading,
            aiStatusText: AgentService.shared.currentToolExecution ?? AgentService.shared.agentPhase.displayText,
            isOnline: true,
            joinedAt: Date(),
            lastSeenAt: Date()
        )
        
        let session = CollaborationSession(
            id: shareCode,
            projectId: projectId.isEmpty ? wsInfo.name : projectId,
            workspaceName: wsInfo.name,
            workspaceLang: wsInfo.lang,
            hostUserId: localUserId,
            hostDisplayName: localDisplayName,
            participants: [hostParticipant],
            isActive: true,
            createdAt: Date(),
            shareCode: shareCode,
            isHostingLocally: true,
            remoteEndpoint: "http://\(selectedLANAddress):\(listeningPort)"
        )
        
        self.currentSession = session
        self.participants = [hostParticipant]
        self.isConnected = true
        self.connectionStatus = .connected
        
        crdtEngine.startSession(siteId: localUserId)
        crdtEngine.updatePeerCount(1)
        
        // Index current workspace files & open buffers
        indexLocalWorkspaceFiles()
        
        // Ensure TeamTasks is loaded for current workspace
        if let wsPath = AppState.shared?.workspaceFolder?.path {
            TeamIntegrationService.shared.setTeamTasksEnabled(true)
            TeamTaskService.shared.load(workspacePath: wsPath)
        }
        
        recordActivity(actorName: localDisplayName, actorColor: localColor, action: "started host session", target: wsInfo.name)
        regenerateQRCode()
        startHostMaintenanceTimer()
        
        return session
    }
    
    @discardableResult
    func joinSession(shareCode rawInput: String) async throws -> CollaborationSession {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CollaborationError.invalidURL }
        
        connectionStatus = .connecting
        
        // Parse input: can be:
        // 1. Full URL: "http://<lan-host>:8472/?code=ABCD12" or "https://xxx.trycloudflare.com/?code=ABCD12"
        // 2. Compact token: "<lan-host>:8472#ABCD12"
        // 3. Just room code: "ABCD12" (matches discovered LAN session or local loopback)
        var baseEndpoint = ""
        var code = ""
        
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            if let comps = URLComponents(string: trimmed) {
                let scheme = comps.scheme ?? "http"
                let host = comps.host ?? "127.0.0.1"
                let portPart = comps.port.map { ":\($0)" } ?? ""
                baseEndpoint = "\(scheme)://\(host)\(portPart)"
                code = comps.queryItems?.first(where: { $0.name == "code" })?.value?.uppercased() ?? ""
            }
        } else if trimmed.contains("#") {
            let parts = trimmed.components(separatedBy: "#")
            let hostPart = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            code = (parts.count > 1 ? parts[1] : "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            baseEndpoint = hostPart.hasPrefix("http") ? hostPart : "http://\(hostPart)"
        } else if trimmed.contains(":") && !trimmed.contains(" ") {
            baseEndpoint = "http://\(trimmed)"
        } else {
            code = trimmed.uppercased()
            if let match = discoveredSessions.first(where: { $0.shareCode.uppercased() == code }) {
                baseEndpoint = "http://\(match.hostAddress):\(match.port)"
            } else {
                baseEndpoint = "http://\(selectedLANAddress):\(listeningPort)"
            }
        }
        
        // Perform initial handshake with Host
        let joinURLString = "\(baseEndpoint)/api/collab/join"
        guard let joinURL = URL(string: joinURLString) else {
            connectionStatus = .error("Invalid address")
            throw CollaborationError.invalidURL
        }
        
        var req = URLRequest(url: joinURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let joinBody: [String: Any] = [
            "code": code,
            "userId": localUserId,
            "displayName": localDisplayName,
            "role": localRole,
            "color": localColor
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: joinBody)
        
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                connectionStatus = .error("Session not found or rejected")
                throw CollaborationError.sessionNotFound
            }
            
            let resolvedCode = (json["shareCode"] as? String) ?? code
            let wsName = (json["workspaceName"] as? String) ?? "Shared Workspace"
            let wsLang = (json["workspaceLang"] as? String) ?? "code"
            let hostId = (json["hostUserId"] as? String) ?? "host"
            let hostName = (json["hostDisplayName"] as? String) ?? "Host"
            
            let session = CollaborationSession(
                id: resolvedCode,
                projectId: wsName,
                workspaceName: wsName,
                workspaceLang: wsLang,
                hostUserId: hostId,
                hostDisplayName: hostName,
                participants: [],
                isActive: true,
                createdAt: Date(),
                shareCode: resolvedCode,
                isHostingLocally: false,
                remoteEndpoint: baseEndpoint
            )
            
            self.currentSession = session
            self.isConnected = true
            self.connectionStatus = .connected
            crdtEngine.startSession(siteId: localUserId)
            
            applySyncPayload(json)
            startPeerSyncLoop()
            regenerateQRCode()
            return session
        } catch {
            connectionStatus = .error("Cannot reach host (\(baseEndpoint))")
            throw error
        }
    }
    
    func joinDiscoveredSession(_ discovered: DiscoveredCollabSession) async {
        _ = try? await joinSession(shareCode: "\(discovered.hostAddress):\(discovered.port)#\(discovered.shareCode)")
    }
    
    func leaveSession() async {
        if let session = currentSession {
            if session.isHostingLocally {
                stopEmbeddedHostServer()
                stopOnlineTunnel()
            } else if !session.remoteEndpoint.isEmpty,
                      let url = URL(string: "\(session.remoteEndpoint)/api/collab/leave") {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: ["userId": localUserId])
                _ = try? await URLSession.shared.data(for: req)
            }
        }
        peerSyncTimer?.invalidate()
        peerSyncTimer = nil
        hostMaintenanceTimer?.invalidate()
        hostMaintenanceTimer = nil
        followingUserId = nil
        crdtEngine.stopSession()
        crdtDocuments.removeAll()
        currentSession = nil
        participants = []
        sharedFiles = []
        activeFileLocks = [:]
        isConnected = false
        connectionStatus = .disconnected
    }
    
    // MARK: - Embedded Host HTTP / Sync Server
    
    private func startEmbeddedHostServer(shareCode: String, workspaceName: String, workspaceLang: String) {
        stopEmbeddedHostServer()
        
        for candidatePort in UInt16(8472)...UInt16(8485) {
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                guard let nwPort = NWEndpoint.Port(rawValue: candidatePort) else { continue }
                let newListener = try NWListener(using: params, on: nwPort)
                
                newListener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard let self else { return }
                        switch state {
                        case .ready:
                            self.isServerRunning = true
                            self.listeningPort = candidatePort
                            self.publishBonjourService(port: candidatePort, shareCode: shareCode, workspaceName: workspaceName, workspaceLang: workspaceLang)
                            self.regenerateQRCode()
                        case .failed, .cancelled:
                            self.isServerRunning = false
                        default:
                            break
                        }
                    }
                }
                
                newListener.newConnectionHandler = { [weak self] connection in
                    self?.acceptHostConnection(connection)
                }
                
                newListener.start(queue: networkQueue)
                self.listener = newListener
                self.listeningPort = candidatePort
                self.isServerRunning = true
                break
            } catch {
                continue
            }
        }
    }
    
    private func stopEmbeddedHostServer() {
        netService?.stop()
        netService = nil
        listener?.cancel()
        listener = nil
        isServerRunning = false
    }
    
    private func publishBonjourService(port: UInt16, shareCode: String, workspaceName: String, workspaceLang: String) {
        netService?.stop()
        let serviceName = "MicroCode-\(localDisplayName)-\(shareCode.prefix(4))"
        let svc = NetService(domain: "local.", type: "_microcode-collab._tcp.", name: serviceName, port: Int32(port))
        let txt: [String: Data] = [
            "code": Data(shareCode.utf8),
            "ws": Data(workspaceName.utf8),
            "lang": Data(workspaceLang.utf8),
            "host": Data(localDisplayName.utf8)
        ]
        svc.setTXTRecord(NetService.data(fromTXTRecord: txt))
        svc.publish()
        self.netService = svc
    }
    
    nonisolated private func acceptHostConnection(_ connection: NWConnection) {
        connection.start(queue: networkQueue)
        receiveHTTPRequest(on: connection, accumulated: Data())
    }
    
    nonisolated private func receiveHTTPRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = accumulated
            if let content, !content.isEmpty {
                buffer.append(content)
            }
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
                let headerStr = String(data: headerData, encoding: .utf8) ?? ""
                let contentLength = Self.parseContentLength(from: headerStr)
                let bodyStart = headerEnd.upperBound
                let receivedBodyBytes = buffer.count - bodyStart
                if receivedBodyBytes < contentLength && !isComplete && error == nil {
                    self.receiveHTTPRequest(on: connection, accumulated: buffer)
                    return
                }
                let bodyData = buffer.subdata(in: bodyStart..<min(buffer.count, bodyStart + contentLength))
                Task { @MainActor in
                    self.handleHostHTTPRequest(headerStr: headerStr, bodyData: bodyData, connection: connection)
                }
            } else if !isComplete && error == nil && buffer.count < 524_288 {
                self.receiveHTTPRequest(on: connection, accumulated: buffer)
            } else {
                connection.cancel()
            }
        }
    }
    
    nonisolated private static func parseContentLength(from headerStr: String) -> Int {
        for line in headerStr.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let val = lower.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(val) ?? 0
            }
        }
        return 0
    }
    
    private func handleHostHTTPRequest(headerStr: String, bodyData: Data, connection: NWConnection) {
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            connection.cancel()
            return
        }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }
        let method = parts[0].uppercased()
        let rawTarget = parts[1]
        let urlComps = URLComponents(string: "http://localhost\(rawTarget)")
        let path = urlComps?.path ?? "/"
        
        if method == "OPTIONS" {
            sendHTTPResponse(connection: connection, status: "204 No Content", contentType: "text/plain", body: Data())
            return
        }
        
        switch (method, path) {
        case ("GET", "/"), ("GET", "/index.html"):
            let html = buildWebCollabPortalHTML()
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(html.utf8))
            
        case ("POST", "/api/collab/join"):
            let body = (try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]) ?? [:]
            let reqCode = (body["code"] as? String)?.uppercased() ?? ""
            if let session = currentSession, (!reqCode.isEmpty && reqCode != session.shareCode) {
                let err = try? JSONSerialization.data(withJSONObject: ["error": "Invalid room code"])
                sendHTTPResponse(connection: connection, status: "403 Forbidden", contentType: "application/json", body: err ?? Data())
                return
            }
            let uid = (body["userId"] as? String) ?? ("web-" + UUID().uuidString.prefix(6))
            let name = (body["displayName"] as? String) ?? "Collaborator"
            let role = (body["role"] as? String) ?? "Editor"
            let color = (body["color"] as? String) ?? Self.formalPalette[participants.count % Self.formalPalette.count]
            
            upsertParticipant(userId: uid, displayName: name, role: role, color: color, cursor: nil)
            recordActivity(actorName: name, actorColor: color, action: "joined session", target: role)
            
            let respData = buildHostSyncPayloadData()
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json; charset=utf-8", body: respData)
            
        case ("POST", "/api/collab/sync"), ("GET", "/api/collab/sync"):
            if method == "POST", let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                processIncomingPeerSync(body)
            }
            let respData = buildHostSyncPayloadData()
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json; charset=utf-8", body: respData)
            
        case ("GET", "/api/collab/file"):
            let relPath = urlComps?.queryItems?.first(where: { $0.name == "path" })?.value ?? ""
            let content = resolveFileContent(relativePath: relPath)
            let payload: [String: Any] = [
                "path": relPath,
                "content": content,
                "revision": fileRevisions[relPath] ?? 1
            ]
            let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json; charset=utf-8", body: data)
            
        case ("POST", "/api/collab/edit"):
            if let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
               let relPath = body["path"] as? String,
               let newContent = body["content"] as? String {
                let uid = (body["userId"] as? String) ?? "peer"
                let name = (body["displayName"] as? String) ?? "Collaborator"
                let color = (body["color"] as? String) ?? "#3B82F6"
                applyIncomingFileContent(relativePath: relPath, content: newContent, authorId: uid, authorName: name, authorColor: color)
            }
            let data = (try? JSONSerialization.data(withJSONObject: ["ok": true])) ?? Data()
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json", body: data)
            
        case ("POST", "/api/collab/chat"):
            if let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
               let text = body["message"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let uid = (body["userId"] as? String) ?? "peer"
                let name = (body["displayName"] as? String) ?? "Collaborator"
                let color = (body["color"] as? String) ?? "#3B82F6"
                let msg = ChatMessage(userId: uid, displayName: name, userColor: color, message: text, timestamp: Date())
                chatMessages.append(msg)
                recordActivity(actorName: name, actorColor: color, action: "posted message", target: String(text.prefix(40)))
            }
            let data = (try? JSONSerialization.data(withJSONObject: ["ok": true])) ?? Data()
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json", body: data)
            
        case ("POST", "/api/collab/task"):
            if let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                handleRemoteTaskAction(body)
            }
            let respData = buildHostSyncPayloadData()
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json", body: respData)
            
        case ("POST", "/api/collab/leave"):
            if let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
               let uid = body["userId"] as? String {
                if let p = participants.first(where: { $0.userId == uid }) {
                    recordActivity(actorName: p.displayName, actorColor: p.color, action: "left session", target: "")
                }
                participants.removeAll { $0.userId == uid }
                crdtEngine.updatePeerCount(participants.count)
            }
            let data = (try? JSONSerialization.data(withJSONObject: ["ok": true])) ?? Data()
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json", body: data)
            
        default:
            sendHTTPResponse(connection: connection, status: "404 Not Found", contentType: "application/json", body: Data("{\"error\":\"Not found\"}".utf8))
        }
    }
    
    private func sendHTTPResponse(connection: NWConnection, status: String, contentType: String, body: Data) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Access-Control-Allow-Headers: Content-Type\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "Connection: close\r\n\r\n"
        var payload = Data(header.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    // MARK: - Sync State Assembly & Processing
    
    private func upsertParticipant(
        userId: String,
        displayName: String,
        role: String,
        color: String,
        cursor: CollaborationSession.CursorPosition?,
        activeTaskTitle: String? = nil,
        isAIActive: Bool = false,
        aiStatusText: String? = nil
    ) {
        if let idx = participants.firstIndex(where: { $0.userId == userId }) {
            participants[idx].displayName = displayName
            participants[idx].role = role
            participants[idx].color = color
            if let cursor {
                participants[idx].cursorPosition = cursor
            }
            participants[idx].activeTaskTitle = activeTaskTitle
            participants[idx].isAIActive = isAIActive
            participants[idx].aiStatusText = aiStatusText
            participants[idx].isOnline = true
            participants[idx].lastSeenAt = Date()
        } else {
            let newP = CollaborationSession.Participant(
                id: userId,
                userId: userId,
                displayName: displayName,
                role: role,
                color: color,
                cursorPosition: cursor,
                activeTaskTitle: activeTaskTitle,
                isAIActive: isAIActive,
                aiStatusText: aiStatusText,
                isOnline: true,
                joinedAt: Date(),
                lastSeenAt: Date()
            )
            participants.append(newP)
        }
        crdtEngine.updatePeerCount(participants.count)
        rebuildActiveFileLocks()
        applyFollowModeIfNeeded()
    }
    
    private func updateSelfInParticipants() {
        guard currentSession != nil else { return }
        let role = (currentSession?.isHostingLocally == true) ? "Host" : localRole
        upsertParticipant(
            userId: localUserId,
            displayName: localDisplayName,
            role: role,
            color: localColor,
            cursor: currentLocalCursorPosition(),
            activeTaskTitle: TeamTaskService.shared.selectedTask?.title,
            isAIActive: AgentService.shared.isLoading,
            aiStatusText: AgentService.shared.currentToolExecution ?? AgentService.shared.agentPhase.displayText
        )
    }
    
    private func rebuildActiveFileLocks() {
        var locks: [String: (userId: String, name: String, color: String)] = [:]
        for p in participants where p.isOnline {
            if let cur = p.cursorPosition, !cur.filePath.isEmpty {
                let rel = normalizeRelativePath(cur.filePath)
                locks[rel] = (p.userId, p.displayName, p.color)
            }
        }
        self.activeFileLocks = locks
        for i in 0..<sharedFiles.count {
            let rel = sharedFiles[i].relativePath
            if let lock = locks[rel] {
                sharedFiles[i].activeEditorName = lock.name
                sharedFiles[i].activeEditorColor = lock.color
            } else {
                sharedFiles[i].activeEditorName = nil
                sharedFiles[i].activeEditorColor = nil
            }
        }
    }
    
    private func processIncomingPeerSync(_ body: [String: Any]) {
        guard let uid = body["userId"] as? String else { return }
        let name = (body["displayName"] as? String) ?? "Collaborator"
        let role = (body["role"] as? String) ?? "Editor"
        let color = (body["color"] as? String) ?? "#3B82F6"
        var cursor: CollaborationSession.CursorPosition? = nil
        if let curDict = body["cursor"] as? [String: Any],
           let fp = curDict["filePath"] as? String {
            cursor = CollaborationSession.CursorPosition(
                filePath: normalizeRelativePath(fp),
                line: (curDict["line"] as? Int) ?? 1,
                column: (curDict["column"] as? Int) ?? 1
            )
        }
        let taskTitle = body["activeTaskTitle"] as? String
        let aiActive = (body["isAIActive"] as? Bool) ?? false
        let aiText = body["aiStatusText"] as? String
        
        upsertParticipant(
            userId: uid,
            displayName: name,
            role: role,
            color: color,
            cursor: cursor,
            activeTaskTitle: taskTitle,
            isAIActive: aiActive,
            aiStatusText: aiText
        )
        
        // Apply any modified file buffer pushed by peer
        if let edits = body["fileEdits"] as? [[String: Any]] {
            for edit in edits {
                if let path = edit["path"] as? String,
                   let content = edit["content"] as? String {
                    applyIncomingFileContent(relativePath: path, content: content, authorId: uid, authorName: name, authorColor: color)
                }
            }
        }
        
        // Merge TeamTasks if pushed by peer
        if let tasksData = body["teamTasksJSON"] as? String,
           let raw = tasksData.data(using: .utf8) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let incomingTasks = try? decoder.decode([TeamTask].self, from: raw) {
                TeamTaskService.shared.applyRemoteTasks(incomingTasks)
            }
        }
    }
    
    private func buildHostSyncPayloadData() -> Data {
        updateSelfInParticipants()
        indexLocalWorkspaceFiles()
        
        let participantsArr: [[String: Any]] = participants.map { p in
            var dict: [String: Any] = [
                "id": p.id,
                "userId": p.userId,
                "displayName": p.displayName,
                "role": p.role,
                "color": p.color,
                "isOnline": p.isOnline,
                "isAIActive": p.isAIActive,
                "aiStatusText": p.aiStatusText ?? "",
                "activeTaskTitle": p.activeTaskTitle ?? ""
            ]
            if let c = p.cursorPosition {
                dict["cursor"] = [
                    "filePath": c.filePath,
                    "line": c.line,
                    "column": c.column
                ]
            }
            return dict
        }
        
        let filesArr: [[String: Any]] = sharedFiles.map { f in
            [
                "relativePath": f.relativePath,
                "name": f.name,
                "language": f.language,
                "isOpenOnHost": f.isOpenOnHost,
                "activeEditorName": f.activeEditorName ?? "",
                "activeEditorColor": f.activeEditorColor ?? "",
                "revision": fileRevisions[f.relativePath] ?? 1
            ]
        }
        
        // Include open/recently edited file contents for instant sync
        var openBuffers: [String: String] = [:]
        for (relPath, content) in fileContents.prefix(20) {
            openBuffers[relPath] = content
        }
        
        let chatArr: [[String: Any]] = chatMessages.suffix(50).map { m in
            [
                "id": m.id,
                "userId": m.userId,
                "displayName": m.displayName,
                "userColor": m.userColor,
                "message": m.message,
                "timestamp": ISO8601DateFormatter().string(from: m.timestamp)
            ]
        }
        
        let activityArr: [[String: Any]] = activityLog.suffix(30).map { a in
            [
                "id": a.id,
                "actorName": a.actorName,
                "actorColor": a.actorColor,
                "action": a.action,
                "target": a.target,
                "timestamp": ISO8601DateFormatter().string(from: a.timestamp)
            ]
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let tasksJSONString: String = {
            if let data = try? encoder.encode(TeamTaskService.shared.tasks),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "[]"
        }()
        
        let payload: [String: Any] = [
            "shareCode": currentSession?.shareCode ?? "",
            "workspaceName": currentSession?.workspaceName ?? "Workspace",
            "workspaceLang": currentSession?.workspaceLang ?? "code",
            "hostUserId": currentSession?.hostUserId ?? localUserId,
            "hostDisplayName": currentSession?.hostDisplayName ?? localDisplayName,
            "participants": participantsArr,
            "sharedFiles": filesArr,
            "openBuffers": openBuffers,
            "chatMessages": chatArr,
            "activityLog": activityArr,
            "teamTasksJSON": tasksJSONString
        ]
        
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
    }
    
    private func applySyncPayload(_ json: [String: Any]) {
        if let wsName = json["workspaceName"] as? String {
            currentSession?.workspaceName = wsName
        }
        if let wsLang = json["workspaceLang"] as? String {
            currentSession?.workspaceLang = wsLang
        }
        
        if let pArr = json["participants"] as? [[String: Any]] {
            var newList: [CollaborationSession.Participant] = []
            for item in pArr {
                let uid = (item["userId"] as? String) ?? UUID().uuidString
                let name = (item["displayName"] as? String) ?? "Collaborator"
                let role = (item["role"] as? String) ?? "Editor"
                let color = (item["color"] as? String) ?? "#3B82F6"
                let isOnline = (item["isOnline"] as? Bool) ?? true
                let isAIActive = (item["isAIActive"] as? Bool) ?? false
                let aiStatusText = item["aiStatusText"] as? String
                let activeTaskTitle = item["activeTaskTitle"] as? String
                var cursor: CollaborationSession.CursorPosition? = nil
                if let cDict = item["cursor"] as? [String: Any],
                   let fp = cDict["filePath"] as? String {
                    cursor = CollaborationSession.CursorPosition(
                        filePath: fp,
                        line: (cDict["line"] as? Int) ?? 1,
                        column: (cDict["column"] as? Int) ?? 1
                    )
                }
                newList.append(CollaborationSession.Participant(
                    id: uid,
                    userId: uid,
                    displayName: name,
                    role: role,
                    color: color,
                    cursorPosition: cursor,
                    activeTaskTitle: activeTaskTitle,
                    isAIActive: isAIActive,
                    aiStatusText: aiStatusText,
                    isOnline: isOnline,
                    joinedAt: Date(),
                    lastSeenAt: Date()
                ))
            }
            self.participants = newList
            crdtEngine.updatePeerCount(newList.count)
            rebuildActiveFileLocks()
        }
        
        if let fArr = json["sharedFiles"] as? [[String: Any]] {
            self.sharedFiles = fArr.compactMap { item in
                guard let rel = item["relativePath"] as? String,
                      let name = item["name"] as? String else { return nil }
                return SharedWorkspaceFile(
                    relativePath: rel,
                    name: name,
                    language: (item["language"] as? String) ?? "code",
                    isOpenOnHost: (item["isOpenOnHost"] as? Bool) ?? false,
                    activeEditorName: (item["activeEditorName"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                    activeEditorColor: (item["activeEditorColor"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                )
            }
        }
        
        if let buffers = json["openBuffers"] as? [String: String] {
            for (relPath, content) in buffers {
                if fileContents[relPath] != content {
                    fileContents[relPath] = content
                    syncBufferToOpenEditorTabIfNeeded(relativePath: relPath, content: content)
                }
            }
        }
        
        if let cArr = json["chatMessages"] as? [[String: Any]] {
            let iso = ISO8601DateFormatter()
            self.chatMessages = cArr.compactMap { item in
                guard let msg = item["message"] as? String else { return nil }
                return ChatMessage(
                    id: (item["id"] as? String) ?? UUID().uuidString,
                    userId: (item["userId"] as? String) ?? "",
                    displayName: (item["displayName"] as? String) ?? "Collaborator",
                    userColor: (item["userColor"] as? String) ?? "#3B82F6",
                    message: msg,
                    timestamp: (item["timestamp"] as? String).flatMap { iso.date(from: $0) } ?? Date()
                )
            }
        }
        
        if let aArr = json["activityLog"] as? [[String: Any]] {
            let iso = ISO8601DateFormatter()
            self.activityLog = aArr.compactMap { item in
                guard let act = item["action"] as? String else { return nil }
                return ActivityItem(
                    id: (item["id"] as? String) ?? UUID().uuidString,
                    actorName: (item["actorName"] as? String) ?? "Team",
                    actorColor: (item["actorColor"] as? String) ?? "#3B82F6",
                    action: act,
                    target: (item["target"] as? String) ?? "",
                    timestamp: (item["timestamp"] as? String).flatMap { iso.date(from: $0) } ?? Date()
                )
            }
        }
        
        if let tasksJSON = json["teamTasksJSON"] as? String,
           let raw = tasksJSON.data(using: .utf8) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let remoteTasks = try? decoder.decode([TeamTask].self, from: raw) {
                TeamTaskService.shared.applyRemoteTasks(remoteTasks)
            }
        }
        
        applyFollowModeIfNeeded()
    }
    
    // MARK: - Workspace File Indexing & Live Buffer Sync
    
    func indexLocalWorkspaceFiles() {
        guard let state = AppState.shared else { return }
        let wsRoot = state.workspaceFolder?.standardizedFileURL.path ?? ""
        var discovered: [SharedWorkspaceFile] = []
        var seen = Set<String>()
        
        // 1. Open files in Editor
        for openFile in state.openFiles {
            let rel = normalizeRelativePath(openFile.path)
            guard !rel.isEmpty, !seen.contains(rel) else { continue }
            seen.insert(rel)
            fileContents[rel] = openFile.content
            if fileRevisions[rel] == nil { fileRevisions[rel] = 1 }
            let lock = activeFileLocks[rel]
            discovered.append(SharedWorkspaceFile(
                relativePath: rel,
                name: openFile.name,
                language: openFile.language,
                isOpenOnHost: true,
                activeEditorName: lock?.name,
                activeEditorColor: lock?.color
            ))
        }
        
        // 2. Top workspace files from fileTree
        func walk(_ nodes: [FileNode], depth: Int) {
            guard depth <= 3 && discovered.count < 80 else { return }
            for node in nodes {
                if discovered.count >= 80 { break }
                if node.isDirectory {
                    let dirName = node.name.lowercased()
                    if dirName == ".git" || dirName == "node_modules" || dirName == ".build" || dirName == "target" || dirName == "dist" {
                        continue
                    }
                    if !node.children.isEmpty {
                        walk(node.children, depth: depth + 1)
                    }
                } else {
                    let rel = normalizeRelativePath(node.path)
                    guard !rel.isEmpty, !seen.contains(rel) else { continue }
                    seen.insert(rel)
                    let ext = (node.path as NSString).pathExtension.lowercased()
                    let lock = activeFileLocks[rel]
                    discovered.append(SharedWorkspaceFile(
                        relativePath: rel,
                        name: node.name,
                        language: ext.isEmpty ? "code" : ext,
                        isOpenOnHost: false,
                        activeEditorName: lock?.name,
                        activeEditorColor: lock?.color
                    ))
                }
            }
        }
        if !wsRoot.isEmpty {
            walk(state.fileTree, depth: 0)
        }
        self.sharedFiles = discovered
    }
    
    func normalizeRelativePath(_ rawPath: String) -> String {
        guard !rawPath.isEmpty else { return "" }
        if let wsRoot = AppState.shared?.workspaceFolder?.standardizedFileURL.path, !wsRoot.isEmpty {
            let std = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            if std.hasPrefix(wsRoot + "/") {
                return String(std.dropFirst(wsRoot.count + 1))
            }
        }
        return (rawPath as NSString).lastPathComponent
    }
    
    private func resolveFileContent(relativePath: String) -> String {
        if let cached = fileContents[relativePath] {
            return cached
        }
        if let state = AppState.shared {
            if let openMatch = state.openFiles.first(where: { normalizeRelativePath($0.path) == relativePath || $0.name == relativePath }) {
                fileContents[relativePath] = openMatch.content
                return openMatch.content
            }
            if let wsRoot = state.workspaceFolder?.path {
                let fullURL = URL(fileURLWithPath: wsRoot).appendingPathComponent(relativePath)
                if let str = try? String(contentsOf: fullURL, encoding: .utf8) {
                    fileContents[relativePath] = str
                    return str
                }
            }
        }
        return ""
    }
    
    private func applyIncomingFileContent(relativePath: String, content: String, authorId: String, authorName: String, authorColor: String) {
        let rel = normalizeRelativePath(relativePath)
        guard !rel.isEmpty else { return }
        guard fileContents[rel] != content else { return }
        
        // Update CRDT document
        let doc = crdtEngine.createDocument(content: content, filePath: rel, id: rel)
        crdtDocuments[rel] = doc
        fileContents[rel] = content
        fileRevisions[rel] = (fileRevisions[rel] ?? 1) + 1
        
        syncBufferToOpenEditorTabIfNeeded(relativePath: rel, content: content)
        
        // Also write to disk on Host if inside workspace
        if currentSession?.isHostingLocally == true,
           let wsRoot = AppState.shared?.workspaceFolder?.path {
            let fullURL = URL(fileURLWithPath: wsRoot).appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: fullURL.path) {
                try? content.write(to: fullURL, atomically: true, encoding: .utf8)
            }
        }
        
        recordActivity(actorName: authorName, actorColor: authorColor, action: "edited", target: (rel as NSString).lastPathComponent)
    }
    
    private func syncBufferToOpenEditorTabIfNeeded(relativePath: String, content: String) {
        guard let state = AppState.shared else { return }
        if let idx = state.openFiles.firstIndex(where: { normalizeRelativePath($0.path) == relativePath || $0.name == (relativePath as NSString).lastPathComponent }) {
            guard state.openFiles[idx].content != content else { return }
            isApplyingRemoteEdit = true
            state.openFiles[idx].content = content
            if state.currentFile?.id == state.openFiles[idx].id {
                state.currentFile?.content = content
            }
            lastSyncedLocalFileHashes[relativePath] = content.hashValue
            isApplyingRemoteEdit = false
        }
    }
    
    func openSharedFileInEditor(_ file: SharedWorkspaceFile) async {
        guard let state = AppState.shared else { return }
        let rel = file.relativePath
        
        // 1. If file exists locally in workspace, open it directly
        if let wsRoot = state.workspaceFolder?.path {
            let localURL = URL(fileURLWithPath: wsRoot).appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: localURL.path) {
                await state.loadFile(url: localURL)
                await updateCursor(filePath: rel, line: 1, column: 1)
                return
            }
        }
        
        // 2. Otherwise fetch from Host and open as virtual collaborative tab
        var content = fileContents[rel] ?? ""
        if content.isEmpty,
           let session = currentSession,
           !session.isHostingLocally,
           let encoded = rel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "\(session.remoteEndpoint)/api/collab/file?path=\(encoded)") {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let remoteContent = json["content"] as? String {
                content = remoteContent
                fileContents[rel] = remoteContent
            }
        }
        
        if let existingIdx = state.openFiles.firstIndex(where: { normalizeRelativePath($0.path) == rel || $0.name == file.name }) {
            state.openFiles[existingIdx].content = content
            state.selectFile(state.openFiles[existingIdx])
        } else {
            let newFile = CodeFile(
                name: file.name,
                path: rel,
                content: content,
                language: file.language,
                isUnsaved: false
            )
            state.openFiles.append(newFile)
            state.selectFile(newFile)
        }
        await updateCursor(filePath: rel, line: 1, column: 1)
    }
    
    // MARK: - Follow Mode
    
    func toggleFollow(userId: String) {
        if followingUserId == userId {
            followingUserId = nil
        } else {
            followingUserId = userId
            applyFollowModeIfNeeded()
        }
    }
    
    private func applyFollowModeIfNeeded() {
        guard let targetId = followingUserId,
              let target = participants.first(where: { $0.userId == targetId }),
              let cursor = target.cursorPosition,
              !cursor.filePath.isEmpty else { return }
        
        let rel = normalizeRelativePath(cursor.filePath)
        guard let state = AppState.shared else { return }
        let currentRel = state.currentFile.map { normalizeRelativePath($0.path) } ?? ""
        if currentRel != rel {
            if let match = sharedFiles.first(where: { $0.relativePath == rel }) {
                Task { await openSharedFileInEditor(match) }
            }
        }
    }
    
    // MARK: - Hooks Called by AppState / Editor / TeamTaskService
    
    func notifyLocalFileEdited(path: String, content: String) {
        guard currentSession != nil, !isApplyingRemoteEdit else { return }
        let rel = normalizeRelativePath(path)
        guard !rel.isEmpty else { return }
        let hash = content.hashValue
        guard lastSyncedLocalFileHashes[rel] != hash else { return }
        lastSyncedLocalFileHashes[rel] = hash
        
        fileContents[rel] = content
        fileRevisions[rel] = (fileRevisions[rel] ?? 1) + 1
        
        if currentSession?.isHostingLocally == false,
           let endpoint = currentSession?.remoteEndpoint,
           let url = URL(string: "\(endpoint)/api/collab/edit") {
            Task {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = [
                    "path": rel,
                    "content": content,
                    "userId": localUserId,
                    "displayName": localDisplayName,
                    "color": localColor
                ]
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                _ = try? await URLSession.shared.data(for: req)
            }
        }
    }
    
    func broadcastTeamTasksIfActive(_ tasks: [TeamTask]) {
        guard let session = currentSession, !session.isHostingLocally else { return }
        guard let url = URL(string: "\(session.remoteEndpoint)/api/collab/sync") else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(tasks),
              let jsonStr = String(data: data, encoding: .utf8) else { return }
        Task {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "userId": localUserId,
                "displayName": localDisplayName,
                "role": localRole,
                "color": localColor,
                "teamTasksJSON": jsonStr
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: req)
        }
    }
    
    private func handleRemoteTaskAction(_ body: [String: Any]) {
        let action = (body["action"] as? String) ?? ""
        let store = TeamTaskService.shared
        TeamIntegrationService.shared.setTeamTasksEnabled(true)
        if store.workspacePath == nil, let wsPath = AppState.shared?.workspaceFolder?.path {
            store.load(workspacePath: wsPath)
        }
        switch action {
        case "create":
            let title = (body["title"] as? String) ?? ""
            let objective = (body["objective"] as? String) ?? ""
            let scope = (body["scope"] as? String) ?? ""
            if let task = store.createTask(title: title, objective: objective, scope: scope) {
                recordActivity(actorName: (body["author"] as? String) ?? "Team", actorColor: "#10B981", action: "created task", target: task.title)
            }
        case "status":
            if let taskId = body["taskId"] as? String,
               let statusRaw = body["status"] as? String,
               let st = TeamTaskStatus(rawValue: statusRaw) {
                store.updateStatus(st, taskID: taskId)
            }
        case "claim":
            if let taskId = body["taskId"] as? String,
               let owner = body["author"] as? String, !owner.isEmpty {
                store.handoff(taskID: taskId, to: owner)
                store.updateStatus(.active, taskID: taskId)
            }
        case "decision":
            if let taskId = body["taskId"] as? String,
               let text = body["text"] as? String {
                store.addDecision(text, taskID: taskId)
            }
        default:
            break
        }
    }
    
    // MARK: - Periodic Sync Loops
    
    private func startHostMaintenanceTimer() {
        hostMaintenanceTimer?.invalidate()
        hostMaintenanceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.currentSession?.isHostingLocally == true else { return }
                self.updateSelfInParticipants()
                let cutoff = Date().addingTimeInterval(-15)
                for i in 0..<self.participants.count {
                    if self.participants[i].userId != self.localUserId && self.participants[i].lastSeenAt < cutoff {
                        self.participants[i].isOnline = false
                    }
                }
            }
        }
    }
    
    private func startPeerSyncLoop() {
        peerSyncTimer?.invalidate()
        peerSyncTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performPeerSyncTick()
            }
        }
    }
    
    private func performPeerSyncTick() async {
        guard let session = currentSession, !session.isHostingLocally,
              let url = URL(string: "\(session.remoteEndpoint)/api/collab/sync") else { return }
        
        var body: [String: Any] = [
            "userId": localUserId,
            "displayName": localDisplayName,
            "role": localRole,
            "color": localColor,
            "isAIActive": AgentService.shared.isLoading,
            "aiStatusText": AgentService.shared.currentToolExecution ?? AgentService.shared.agentPhase.displayText,
            "activeTaskTitle": TeamTaskService.shared.selectedTask?.title ?? ""
        ]
        if let cur = currentLocalCursorPosition() {
            body["cursor"] = [
                "filePath": cur.filePath,
                "line": cur.line,
                "column": cur.column
            ]
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 4
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if connectionStatus != .connected {
                    connectionStatus = .connected
                    isConnected = true
                }
                applySyncPayload(json)
            }
        } catch {
            connectionStatus = .reconnecting
        }
    }
    
    // MARK: - Public Cursor, TextChange & Chat API
    
    func updateCursor(filePath: String, line: Int, column: Int) async {
        let rel = normalizeRelativePath(filePath)
        let pos = CollaborationSession.CursorPosition(filePath: rel, line: line, column: column)
        upsertParticipant(
            userId: localUserId,
            displayName: localDisplayName,
            role: (currentSession?.isHostingLocally == true) ? "Host" : localRole,
            color: localColor,
            cursor: pos,
            activeTaskTitle: TeamTaskService.shared.selectedTask?.title,
            isAIActive: AgentService.shared.isLoading,
            aiStatusText: AgentService.shared.currentToolExecution
        )
    }
    
    func sendTextChange(_ change: CollaborationMessage.TextChange) async {
        let rel = normalizeRelativePath(change.filePath)
        if let state = AppState.shared,
           let file = state.openFiles.first(where: { normalizeRelativePath($0.path) == rel }) {
            notifyLocalFileEdited(path: rel, content: file.content)
        }
    }
    
    func sendChatMessage(_ message: String) async {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        
        if currentSession?.isHostingLocally == true {
            let msg = ChatMessage(userId: localUserId, displayName: localDisplayName, userColor: localColor, message: clean, timestamp: Date())
            chatMessages.append(msg)
            recordActivity(actorName: localDisplayName, actorColor: localColor, action: "posted message", target: String(clean.prefix(40)))
        } else if let endpoint = currentSession?.remoteEndpoint,
                  let url = URL(string: "\(endpoint)/api/collab/chat") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "userId": localUserId,
                "displayName": localDisplayName,
                "color": localColor,
                "message": clean
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: req)
            await performPeerSyncTick()
        }
    }
    
    // MARK: - Online Tunnel (Cloudflare / SSH Relay)
    
    func setTransportMode(_ mode: TransportMode) {
        transportMode = mode
        if mode == .online {
            startOnlineTunnel()
        } else {
            stopOnlineTunnel()
        }
        regenerateQRCode()
    }
    
    func startOnlineTunnel() {
        stopOnlineTunnel()
        tunnelStatus = .starting
        let port = Int(listeningPort)
        
        let cloudflaredPaths = ["/opt/homebrew/bin/cloudflared", "/usr/local/bin/cloudflared", "/usr/bin/cloudflared"]
        if let cfPath = cloudflaredPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            launchTunnelProcess(executable: cfPath, arguments: ["tunnel", "--url", "http://127.0.0.1:\(port)", "--no-autoupdate"])
        } else {
            launchTunnelProcess(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-o", "StrictHostKeyChecking=no",
                    "-o", "UserKnownHostsFile=/dev/null",
                    "-o", "ServerAliveInterval=30",
                    "-R", "80:127.0.0.1:\(port)",
                    "nokey@localhost.run"
                ]
            )
        }
    }
    
    func stopOnlineTunnel() {
        tunnelOutputPipe?.fileHandleForReading.readabilityHandler = nil
        tunnelOutputPipe = nil
        if let proc = tunnelProcess, proc.isRunning {
            proc.terminate()
        }
        tunnelProcess = nil
        publicTunnelURL = nil
        tunnelStatus = .idle
        regenerateQRCode()
    }
    
    private func launchTunnelProcess(executable: String, arguments: [String]) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.tunnelOutputPipe = pipe
        self.tunnelProcess = proc
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            let pattern = #"https://[a-zA-Z0-9.-]+\.(?:trycloudflare\.com|lhr\.life)"#
            if let range = line.range(of: pattern, options: .regularExpression) {
                let matched = String(line[range])
                Task { @MainActor in
                    guard let self else { return }
                    if self.publicTunnelURL != matched {
                        self.publicTunnelURL = matched
                        self.tunnelStatus = .active(matched)
                        self.regenerateQRCode()
                    }
                }
            }
        }
        do {
            try proc.run()
        } catch {
            tunnelStatus = .failed(error.localizedDescription)
        }
    }
    
    // MARK: - Share Links & QR Code
    
    func getShareLink() -> String? {
        guard let session = currentSession else { return nil }
        if transportMode == .online, let pub = publicTunnelURL, !pub.isEmpty {
            return "\(pub)/?code=\(session.shareCode)"
        }
        if session.isHostingLocally {
            return "http://\(selectedLANAddress):\(listeningPort)/?code=\(session.shareCode)"
        }
        return "\(session.remoteEndpoint)/?code=\(session.shareCode)"
    }
    
    func getJoinToken() -> String {
        guard let session = currentSession else { return "" }
        if transportMode == .online, let pub = publicTunnelURL, !pub.isEmpty {
            return "\(pub)/?code=\(session.shareCode)"
        }
        if session.isHostingLocally {
            return "\(selectedLANAddress):\(listeningPort)#\(session.shareCode)"
        }
        return "\(session.remoteEndpoint)#\(session.shareCode)"
    }
    
    func copyShareLinkToClipboard() {
        guard let link = getShareLink() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }
    
    func copyJoinTokenToClipboard() {
        let token = getJoinToken()
        guard !token.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
    }
    
    func regenerateQRCode() {
        guard let urlStr = getShareLink(), !urlStr.isEmpty else {
            qrCodeImage = nil
            return
        }
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(urlStr.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        if let cgImg = context.createCGImage(scaled, from: scaled.extent) {
            qrCodeImage = NSImage(cgImage: cgImg, size: NSSize(width: 160, height: 160))
        }
    }
    
    // MARK: - Helpers
    
    private func currentLocalCursorPosition() -> CollaborationSession.CursorPosition? {
        guard let file = AppState.shared?.currentFile else { return nil }
        return CollaborationSession.CursorPosition(
            filePath: normalizeRelativePath(file.path),
            line: 1,
            column: 1
        )
    }
    
    private func currentWorkspaceMetadata() -> (name: String, lang: String) {
        if let folder = AppState.shared?.workspaceFolder {
            let info = PhoneCompanionService.shared.detectWorkspaceLanguageInfo(path: folder.path)
            return (folder.lastPathComponent, info.primary)
        }
        return ("Workspace", "code")
    }
    
    private func recordActivity(actorName: String, actorColor: String, action: String, target: String) {
        let item = ActivityItem(actorName: actorName, actorColor: actorColor, action: action, target: target, timestamp: Date())
        activityLog.append(item)
        if activityLog.count > 60 {
            activityLog.removeFirst(activityLog.count - 60)
        }
    }
    
    private func generateShareCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }
    
    // MARK: - Zero-Install Web Collaboration Portal HTML
    
    private func buildWebCollabPortalHTML() -> String {
        let code = currentSession?.shareCode ?? ""
        let wsName = currentSession?.workspaceName ?? "Workspace"
        return #"""
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>MicroCode Collaboration · \#(wsName)</title>
          <style>
            :root {
              --bg: #111214;
              --panel: #16181b;
              --card: #1b1d21;
              --border: rgba(255,255,255,0.08);
              --text: #ececef;
              --secondary: #9ca3af;
              --muted: #6b7280;
              --accent: #3b82f6;
              --green: #10b981;
              --mono: ui-monospace, "SF Mono", Menlo, monospace;
              --sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, sans-serif;
            }
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body {
              background: var(--bg);
              color: var(--text);
              font-family: var(--sans);
              height: 100vh;
              display: flex;
              flex-direction: column;
              overflow: hidden;
            }
            .topbar {
              height: 46px;
              background: var(--panel);
              border-bottom: 1px solid var(--border);
              display: flex;
              align-items: center;
              justify-content: space-between;
              padding: 0 16px;
              flex-shrink: 0;
            }
            .brand { display: flex; align-items: center; gap: 10px; font-size: 13px; font-weight: 600; }
            .badge {
              font-family: var(--mono);
              font-size: 11px;
              padding: 2px 8px;
              border-radius: 4px;
              background: rgba(255,255,255,0.06);
              border: 1px solid var(--border);
              color: var(--secondary);
            }
            .layout {
              flex: 1;
              display: grid;
              grid-template-columns: 250px 1fr 300px;
              min-height: 0;
            }
            @media (max-width: 900px) {
              .layout { grid-template-columns: 1fr; }
              .sidebar-left, .sidebar-right { display: none; }
            }
            .sidebar-left {
              background: var(--panel);
              border-right: 1px solid var(--border);
              display: flex;
              flex-direction: column;
              min-height: 0;
            }
            .sidebar-right {
              background: var(--panel);
              border-left: 1px solid var(--border);
              display: flex;
              flex-direction: column;
              min-height: 0;
            }
            .section-hdr {
              padding: 10px 12px;
              font-family: var(--mono);
              font-size: 10px;
              font-weight: 600;
              letter-spacing: 0.05em;
              color: var(--secondary);
              border-bottom: 1px solid var(--border);
              display: flex;
              justify-content: space-between;
              align-items: center;
            }
            .file-list, .peer-list, .task-list {
              overflow-y: auto;
              padding: 6px;
              display: flex;
              flex-direction: column;
              gap: 3px;
            }
            .file-row {
              padding: 6px 8px;
              border-radius: 5px;
              font-size: 12px;
              cursor: pointer;
              display: flex;
              align-items: center;
              justify-content: space-between;
              color: var(--secondary);
            }
            .file-row:hover, .file-row.active {
              background: rgba(255,255,255,0.06);
              color: var(--text);
            }
            .editor-pane {
              display: flex;
              flex-direction: column;
              min-height: 0;
              background: var(--bg);
            }
            .editor-bar {
              height: 36px;
              padding: 0 14px;
              border-bottom: 1px solid var(--border);
              display: flex;
              align-items: center;
              justify-content: space-between;
              font-family: var(--mono);
              font-size: 11.5px;
              color: var(--secondary);
            }
            textarea#codeArea {
              flex: 1;
              width: 100%;
              background: var(--bg);
              color: var(--text);
              border: none;
              outline: none;
              padding: 14px 16px;
              font-family: var(--mono);
              font-size: 12.5px;
              line-height: 1.55;
              resize: none;
            }
            .btn {
              background: rgba(255,255,255,0.07);
              color: var(--text);
              border: 1px solid var(--border);
              border-radius: 5px;
              padding: 4px 10px;
              font-size: 11.5px;
              cursor: pointer;
            }
            .btn-primary {
              background: #2563eb;
              border-color: #3b82f6;
              color: #fff;
            }
            .peer-row {
              padding: 6px 8px;
              border-radius: 5px;
              background: rgba(255,255,255,0.025);
              display: flex;
              align-items: center;
              gap: 8px;
              font-size: 12px;
            }
            .dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
            .chat-box {
              flex: 1;
              display: flex;
              flex-direction: column;
              min-height: 0;
              border-top: 1px solid var(--border);
            }
            .chat-msgs {
              flex: 1;
              overflow-y: auto;
              padding: 8px 10px;
              display: flex;
              flex-direction: column;
              gap: 6px;
              font-size: 12px;
            }
            .chat-input-row {
              padding: 8px;
              border-top: 1px solid var(--border);
              display: flex;
              gap: 6px;
            }
            input.txt {
              flex: 1;
              background: var(--card);
              border: 1px solid var(--border);
              color: var(--text);
              border-radius: 5px;
              padding: 5px 8px;
              font-size: 12px;
              outline: none;
            }
          </style>
        </head>
        <body>
          <div class="topbar">
            <div class="brand">
              <span class="dot" style="background:var(--green)"></span>
              <span id="wsTitle">MicroCode Team Collaboration</span>
              <span class="badge" id="roomBadge">ROOM \#(code)</span>
            </div>
            <div style="display:flex;align-items:center;gap:8px">
              <input class="txt" id="nameInput" style="width:140px" placeholder="Your name" onchange="saveName()">
              <span class="badge" id="peerCountBadge">1 online</span>
            </div>
          </div>
          <div class="layout">
            <div class="sidebar-left">
              <div class="section-hdr"><span>WORKSPACE FILES</span></div>
              <div class="file-list" id="fileList"></div>
              <div class="section-hdr" style="border-top:1px solid var(--border)">
                <span>SHARED TEAM TASKS</span>
                <button class="btn" onclick="promptNewTask()">+ Task</button>
              </div>
              <div class="task-list" id="taskList" style="max-height:42%"></div>
            </div>
            <div class="editor-pane">
              <div class="editor-bar">
                <span id="activeFileName">Select a workspace file to view or co-edit</span>
                <button class="btn btn-primary" onclick="pushEdit()">Sync Buffer</button>
              </div>
              <textarea id="codeArea" spellcheck="false" placeholder="Select a file from the left panel..."></textarea>
            </div>
            <div class="sidebar-right">
              <div class="section-hdr"><span>PARTICIPANTS</span></div>
              <div class="peer-list" id="peerList" style="max-height:190px"></div>
              <div class="chat-box">
                <div class="section-hdr"><span>SESSION CHAT</span></div>
                <div class="chat-msgs" id="chatMsgs"></div>
                <div class="chat-input-row">
                  <input class="txt" id="chatInput" placeholder="Message team..." onkeydown="if(event.key==='Enter')sendChat()">
                  <button class="btn btn-primary" onclick="sendChat()">Send</button>
                </div>
              </div>
            </div>
          </div>
          <script>
            const ROOM_CODE = "\#(code)";
            let userId = localStorage.getItem("mc_collab_uid") || ("web-" + Math.random().toString(36).slice(2, 8));
            localStorage.setItem("mc_collab_uid", userId);
            let displayName = localStorage.getItem("mc_collab_name") || ("Guest-" + userId.slice(-4));
            document.getElementById("nameInput").value = displayName;
            let activeFile = "";
            let isTyping = false;

            function saveName() {
              displayName = document.getElementById("nameInput").value.trim() || displayName;
              localStorage.setItem("mc_collab_name", displayName);
              syncState();
            }

            async function joinRoom() {
              await fetch("/api/collab/join", {
                method: "POST",
                headers: {"Content-Type": "application/json"},
                body: JSON.stringify({ code: ROOM_CODE, userId, displayName, role: "Web" })
              });
              syncState();
            }

            async function openFile(path) {
              activeFile = path;
              document.getElementById("activeFileName").textContent = path;
              const res = await fetch("/api/collab/file?path=" + encodeURIComponent(path));
              const d = await res.json();
              document.getElementById("codeArea").value = d.content || "";
              syncState();
            }

            async function pushEdit() {
              if (!activeFile) return;
              const content = document.getElementById("codeArea").value;
              await fetch("/api/collab/edit", {
                method: "POST",
                headers: {"Content-Type": "application/json"},
                body: JSON.stringify({ path: activeFile, content, userId, displayName })
              });
            }

            document.getElementById("codeArea").addEventListener("input", () => {
              isTyping = true;
              clearTimeout(window._editTimer);
              window._editTimer = setTimeout(() => { isTyping = false; pushEdit(); }, 450);
            });

            async function sendChat() {
              const inp = document.getElementById("chatInput");
              const text = inp.value.trim();
              if (!text) return;
              inp.value = "";
              await fetch("/api/collab/chat", {
                method: "POST",
                headers: {"Content-Type": "application/json"},
                body: JSON.stringify({ userId, displayName, message: text })
              });
              syncState();
            }

            async function promptNewTask() {
              const title = prompt("Shared Task Title:");
              if (!title) return;
              const objective = prompt("Task Objective / Scope:") || "";
              await fetch("/api/collab/task", {
                method: "POST",
                headers: {"Content-Type": "application/json"},
                body: JSON.stringify({ action: "create", title, objective, scope: activeFile, author: displayName })
              });
              syncState();
            }

            async function syncState() {
              try {
                const res = await fetch("/api/collab/sync", {
                  method: "POST",
                  headers: {"Content-Type": "application/json"},
                  body: JSON.stringify({
                    userId,
                    displayName,
                    role: "Web",
                    cursor: activeFile ? { filePath: activeFile, line: 1, column: 1 } : null
                  })
                });
                const s = await res.json();
                document.getElementById("wsTitle").textContent = "MicroCode · " + (s.workspaceName || "Workspace");
                const peers = s.participants || [];
                document.getElementById("peerCountBadge").textContent = peers.length + " online";
                document.getElementById("peerList").innerHTML = peers.map(p =>
                  `<div class="peer-row">
                    <span class="dot" style="background:${p.color || '#3b82f6'}"></span>
                    <div style="min-width:0;flex:1">
                      <div style="font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${p.displayName} <span style="color:var(--muted);font-weight:400">(${p.role})</span></div>
                      <div style="font-size:10.5px;color:var(--secondary)">${p.cursor ? p.cursor.filePath : 'Idle'}</div>
                    </div>
                  </div>`
                ).join("");

                const files = s.sharedFiles || [];
                document.getElementById("fileList").innerHTML = files.map(f =>
                  `<div class="file-row ${f.relativePath === activeFile ? 'active' : ''}" onclick="openFile('${f.relativePath.replace(/'/g, "\\'")}')">
                    <span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${f.relativePath}</span>
                    ${f.activeEditorName ? `<span class="badge" style="font-size:9.5px">${f.activeEditorName}</span>` : ''}
                  </div>`
                ).join("");

                if (activeFile && !isTyping && s.openBuffers && s.openBuffers[activeFile] != null) {
                  const area = document.getElementById("codeArea");
                  if (area.value !== s.openBuffers[activeFile]) area.value = s.openBuffers[activeFile];
                }

                const tasks = JSON.parse(s.teamTasksJSON || "[]");
                document.getElementById("taskList").innerHTML = tasks.map(t =>
                  `<div class="peer-row" style="flex-direction:column;align-items:flex-start;gap:3px">
                    <div style="font-weight:600;color:var(--text)">${t.title}</div>
                    <div style="font-size:10.5px;color:var(--secondary)">${t.status} · Owner: ${t.owner}</div>
                  </div>`
                ).join("") || `<div style="padding:8px;font-size:11px;color:var(--muted)">No shared tasks</div>`;

                const chats = s.chatMessages || [];
                document.getElementById("chatMsgs").innerHTML = chats.map(c =>
                  `<div><strong style="color:${c.userColor || '#60a5fa'}">${c.displayName}:</strong> <span>${c.message}</span></div>`
                ).join("");
              } catch (e) {}
            }

            joinRoom();
            setInterval(syncState, 1000);
          </script>
        </body>
        </html>
        """#
    }
}

// MARK: - Bonjour Delegate Helper

private final class BonjourBrowserDelegate: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    static let shared = BonjourBrowserDelegate()
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        Task { @MainActor in
            CollaborationService.shared.handleDiscoveredService(service, moreComing: moreComing)
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        Task { @MainActor in
            CollaborationService.shared.handleRemovedService(service)
        }
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        Task { @MainActor in
            CollaborationService.shared.handleResolvedService(sender)
        }
    }
}

// MARK: - Errors

enum CollaborationError: LocalizedError {
    case notAuthenticated
    case sessionNotFound
    case connectionFailed
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Please configure your display name"
        case .sessionNotFound: return "Collaboration session not found or unreachable"
        case .connectionFailed: return "Failed to connect to collaboration host"
        case .invalidURL: return "Invalid collaboration address or room code"
        }
    }
}
