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
import SwiftUI
import Network
import CryptoKit
import CoreImage.CIFilterBuiltins

// MARK: - Collaborator Color Helpers

enum CollaborationColorHelper {
    static func rgbComponents(fromHex hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        if cleaned.count == 6, let val = UInt64(cleaned, radix: 16) {
            let r = CGFloat((val >> 16) & 0xFF) / 255.0
            let g = CGFloat((val >> 8) & 0xFF) / 255.0
            let b = CGFloat(val & 0xFF) / 255.0
            return (r, g, b)
        }
        return (0.23, 0.51, 0.96)
    }

    static func nsColor(fromHex hex: String, alpha: CGFloat = 1.0) -> NSColor {
        let c = rgbComponents(fromHex: hex)
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
    }

    static func swiftUIColor(fromHex hex: String) -> Color {
        let c = rgbComponents(fromHex: hex)
        return Color(.sRGB, red: Double(c.r), green: Double(c.g), blue: Double(c.b), opacity: 1.0)
    }
}

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
        var mousePresence: MousePresence? = nil
        var activeTaskTitle: String? = nil
        var isAIActive: Bool = false
        var aiStatusText: String? = nil
        var isOnline: Bool
        var joinedAt: Date
        var lastSeenAt: Date = Date()

        var liveActivitySummary: String {
            if let cur = cursorPosition, !cur.filePath.isEmpty {
                let shortFile = (cur.filePath as NSString).lastPathComponent
                if cur.isTyping == true {
                    return "กำลังแก้ \(shortFile):\(cur.line)"
                }
                if let endL = cur.endLine, let endC = cur.endColumn,
                   (endL != cur.line || endC != cur.column) {
                    return "เลือกโค้ด \(shortFile):\(cur.line)-\(endL)"
                }
                return "\(shortFile):Ln \(cur.line)"
            }
            if isAIActive, let ai = aiStatusText, !ai.isEmpty {
                return "AI: \(ai)"
            }
            if let m = mousePresence {
                if let af = m.activeFile, !af.isEmpty {
                    return (af as NSString).lastPathComponent
                }
                return m.surface == "agent" ? "หน้า AI Agent" : "กำลังดู Workspace"
            }
            return "กำลังดู Workspace"
        }
    }
    
    struct CursorPosition: Codable, Equatable {
        var filePath: String
        var line: Int
        var column: Int
        var endLine: Int? = nil
        var endColumn: Int? = nil
        var isTyping: Bool? = nil
    }

    struct MousePresence: Codable, Equatable {
        var normalizedX: Double
        var normalizedY: Double
        var surface: String
        var activeFile: String? = nil
        var activeLine: Int? = nil
        var isPressing: Bool = false
        var updatedAt: Date = Date()
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

// MARK: - Conflict-Free 3-Way Line Merger (Diff3 / LCS Anchor Hunks)

enum CollaborativeThreeWayMerger {
    struct EditHunk: Equatable {
        let baseStart: Int // inclusive index in baseLines
        let baseEnd: Int   // exclusive index in baseLines
        let replacement: [String]

        var isPureInsertion: Bool { baseStart == baseEnd }
    }

    struct MergeResult: Equatable {
        let merged: String
        let didAutoMerge: Bool
    }

    /// Performs a deterministic, syntax-safe 3-way merge of `current` (Host) and `incoming` (Peer)
    /// relative to `base` (`baseRevision` snapshot). Preserves all non-overlapping concurrent edits,
    /// deduplicates identical edits, preserves dual pure insertions, and resolves overlapping line
    /// edits in favor of `incoming` without injecting broken `<<<<<<<` markers into live source code.
    static func merge(base: String, current: String, incoming: String) -> MergeResult {
        if incoming == current {
            return MergeResult(merged: current, didAutoMerge: false)
        }
        if base == current {
            return MergeResult(merged: incoming, didAutoMerge: false)
        }
        if base == incoming {
            return MergeResult(merged: current, didAutoMerge: true)
        }

        let baseLines = base.components(separatedBy: "\n")
        let currentLines = current.components(separatedBy: "\n")
        let incomingLines = incoming.components(separatedBy: "\n")

        // Guard against pathological Myers O(N*D) diff cost on very large generated files
        if baseLines.count + currentLines.count + incomingLines.count > 12_000 {
            return MergeResult(merged: incoming, didAutoMerge: false)
        }

        let hunksA = computeHunks(base: baseLines, target: currentLines)
        let hunksB = computeHunks(base: baseLines, target: incomingLines)

        var output: [String] = []
        output.reserveCapacity(max(currentLines.count, incomingLines.count))

        var cursor = 0
        var i = 0
        var j = 0

        while i < hunksA.count || j < hunksB.count {
            if i < hunksA.count && j < hunksB.count {
                let a = hunksA[i]
                let b = hunksB[j]

                if comesStrictlyBefore(a, b) {
                    if cursor < a.baseStart {
                        output.append(contentsOf: baseLines[cursor..<a.baseStart])
                    }
                    output.append(contentsOf: a.replacement)
                    cursor = a.baseEnd
                    i += 1
                } else if comesStrictlyBefore(b, a) {
                    if cursor < b.baseStart {
                        output.append(contentsOf: baseLines[cursor..<b.baseStart])
                    }
                    output.append(contentsOf: b.replacement)
                    cursor = b.baseEnd
                    j += 1
                } else if a.isPureInsertion && b.isPureInsertion && a.baseStart == b.baseStart {
                    if cursor < a.baseStart {
                        output.append(contentsOf: baseLines[cursor..<a.baseStart])
                    }
                    if a.replacement == b.replacement {
                        output.append(contentsOf: a.replacement)
                    } else {
                        output.append(contentsOf: a.replacement)
                        output.append(contentsOf: b.replacement)
                    }
                    cursor = a.baseEnd
                    i += 1
                    j += 1
                } else {
                    // Transitive overlapping hunk cluster [spanStart, spanEnd)
                    let spanStart = min(a.baseStart, b.baseStart)
                    var spanEnd = max(a.baseEnd, b.baseEnd)
                    var endI = i + 1
                    var endJ = j + 1

                    var expanded = true
                    while expanded {
                        expanded = false
                        while endI < hunksA.count && hunksA[endI].baseStart < spanEnd {
                            spanEnd = max(spanEnd, hunksA[endI].baseEnd)
                            endI += 1
                            expanded = true
                        }
                        while endJ < hunksB.count && hunksB[endJ].baseStart < spanEnd {
                            spanEnd = max(spanEnd, hunksB[endJ].baseEnd)
                            endJ += 1
                            expanded = true
                        }
                    }

                    if cursor < spanStart {
                        output.append(contentsOf: baseLines[cursor..<spanStart])
                    }

                    let sliceB = renderSpan(
                        baseLines: baseLines,
                        spanStart: spanStart,
                        spanEnd: spanEnd,
                        hunks: Array(hunksB[j..<endJ])
                    )
                    output.append(contentsOf: sliceB)
                    cursor = spanEnd
                    i = endI
                    j = endJ
                }
            } else if i < hunksA.count {
                let a = hunksA[i]
                if cursor < a.baseStart {
                    output.append(contentsOf: baseLines[cursor..<a.baseStart])
                }
                output.append(contentsOf: a.replacement)
                cursor = a.baseEnd
                i += 1
            } else if j < hunksB.count {
                let b = hunksB[j]
                if cursor < b.baseStart {
                    output.append(contentsOf: baseLines[cursor..<b.baseStart])
                }
                output.append(contentsOf: b.replacement)
                cursor = b.baseEnd
                j += 1
            }
        }

        if cursor < baseLines.count {
            output.append(contentsOf: baseLines[cursor..<baseLines.count])
        }

        let mergedText = output.joined(separator: "\n")
        return MergeResult(merged: mergedText, didAutoMerge: mergedText != incoming)
    }

    private static func comesStrictlyBefore(_ first: EditHunk, _ second: EditHunk) -> Bool {
        if first.baseEnd < second.baseStart {
            return true
        }
        if first.baseEnd == second.baseStart {
            // Disjoint unless both are pure insertions at the exact same offset
            return !(first.isPureInsertion && second.isPureInsertion)
        }
        return false
    }

    private static func renderSpan(
        baseLines: [String],
        spanStart: Int,
        spanEnd: Int,
        hunks: [EditHunk]
    ) -> [String] {
        var result: [String] = []
        var pos = spanStart
        for h in hunks {
            if pos < h.baseStart {
                result.append(contentsOf: baseLines[pos..<h.baseStart])
            }
            result.append(contentsOf: h.replacement)
            pos = h.baseEnd
        }
        if pos < spanEnd {
            result.append(contentsOf: baseLines[pos..<spanEnd])
        }
        return result
    }

    private static func computeHunks(base: [String], target: [String]) -> [EditHunk] {
        let diff = target.difference(from: base)
        var removedBase = Set<Int>()
        removedBase.reserveCapacity(diff.removals.count)
        for change in diff.removals {
            if case let .remove(offset, _, _) = change {
                removedBase.insert(offset)
            }
        }

        var insertedTarget = Set<Int>()
        insertedTarget.reserveCapacity(diff.insertions.count)
        for change in diff.insertions {
            if case let .insert(offset, _, _) = change {
                insertedTarget.insert(offset)
            }
        }

        var keptBase: [Int] = []
        keptBase.reserveCapacity(max(0, base.count - removedBase.count))
        for idx in 0..<base.count where !removedBase.contains(idx) {
            keptBase.append(idx)
        }

        var keptTarget: [Int] = []
        keptTarget.reserveCapacity(max(0, target.count - insertedTarget.count))
        for idx in 0..<target.count where !insertedTarget.contains(idx) {
            keptTarget.append(idx)
        }

        var hunks: [EditHunk] = []
        var prevB = -1
        var prevT = -1
        let anchorCount = min(keptBase.count, keptTarget.count)

        func appendHunk(bStart: Int, bEnd: Int, tStart: Int, tEnd: Int) {
            let bLen = bEnd - bStart
            let tLen = tEnd - tStart
            if bLen > 1 && bLen == tLen {
                for offset in 0..<bLen {
                    hunks.append(EditHunk(
                        baseStart: bStart + offset,
                        baseEnd: bStart + offset + 1,
                        replacement: [target[tStart + offset]]
                    ))
                }
            } else {
                hunks.append(EditHunk(
                    baseStart: bStart,
                    baseEnd: bEnd,
                    replacement: Array(target[tStart..<tEnd])
                ))
            }
        }

        if anchorCount > 0 {
            for k in 0..<anchorCount {
                let currB = keptBase[k]
                let currT = keptTarget[k]
                let bStart = prevB + 1
                let tStart = prevT + 1
                if bStart < currB || tStart < currT {
                    appendHunk(bStart: bStart, bEnd: currB, tStart: tStart, tEnd: currT)
                }
                prevB = currB
                prevT = currT
            }
        }

        let finalBStart = prevB + 1
        let finalTStart = prevT + 1
        if finalBStart < base.count || finalTStart < target.count {
            appendHunk(bStart: finalBStart, bEnd: base.count, tStart: finalTStart, tEnd: target.count)
        }

        return hunks
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
    @Published var sharedWorkspaceRootPath: String? = nil
    @Published var sharedDirectories: [String] = []
    @Published var sharedFiles: [SharedWorkspaceFile] = []
    @Published var fileContents: [String: String] = [:] // relativePath -> latest merged content
    @Published var fileRevisions: [String: Int] = [:]   // relativePath -> revision counter
    @Published var activeFileLocks: [String: (userId: String, name: String, color: String)] = [:]
    
    // Real-Time Multiplayer Mouse & Cursor State
    nonisolated static let remotePresenceDidChangeNotification = Notification.Name("MicroCodeCollabRemotePresenceDidChange")
    @Published var localMousePresence: CollaborationSession.MousePresence? = nil
    @Published var localEditorCursor: CollaborationSession.CursorPosition? = nil
    @Published var showLocalCursorTag: Bool = true
    @Published var isWebSocketRealtimeActive: Bool = false

    // Follow Mode
    @Published var followingUserId: String? = nil
    private var lastFollowedFileRel: String = ""
    private var lastFollowedLine: Int = 0
    
    // AI Agent as a Live Collaborator Teammate (ONLY active when currentSession != nil)
    nonisolated static let aiTeammateUserId = "ai-agent-teammate"
    nonisolated static let aiTeammateDisplayName = "MicroCode AI"
    nonisolated static let aiTeammateColor = "#A855F7"
    @Published var isAITeammateEnabled: Bool = true {
        didSet {
            guard currentSession != nil else { return }
            if isAITeammateEnabled {
                ensureAITeammateInParticipants()
                broadcastHostParticipantsOverWS()
            } else {
                if followingUserId == Self.aiTeammateUserId {
                    followingUserId = nil
                }
                participants.removeAll { $0.userId == Self.aiTeammateUserId }
                rebuildActiveFileLocks()
                broadcastHostParticipantsOverWS()
                NotificationCenter.default.post(name: Self.remotePresenceDidChangeNotification, object: nil)
            }
        }
    }
    private var aiTeammateCursor: CollaborationSession.CursorPosition? = nil
    private var aiTeammateMouse: CollaborationSession.MousePresence? = nil
    private var aiTeammateStatusText: String = "Ready in Collab"
    private var aiTeammateIsWorking: Bool = false
    private var aiTypingResetTask: Task<Void, Never>? = nil
    
    /// Strict boundary check: returns true ONLY when a Collaboration Session is actively connected.
    var isCollabSessionActive: Bool {
        currentSession != nil && isConnected
    }
    
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
    private var fileRevisionSnapshots: [String: [Int: String]] = [:] // relativePath -> (revision -> content snapshot, bounded to 32)
    private var peerBaseRevisions: [String: Int] = [:]               // relativePath -> last confirmed host revision on peer
    
    // WebSocket Low-Latency Transport & Disk Indexing Cache
    private final class HostWSClient: @unchecked Sendable {
        let id: UUID
        let connection: NWConnection
        var userId: String? = nil
        init(id: UUID = UUID(), connection: NWConnection) {
            self.id = id
            self.connection = connection
        }
    }
    private var hostWSClients: [UUID: HostWSClient] = [:]
    private var peerWebSocketTask: URLSessionWebSocketTask? = nil
    private var peerWSReconnectTask: Task<Void, Never>? = nil
    private var lastDiskScanAt: Date = .distantPast
    private var hostDiskModDates: [String: Date] = [:]
    private var lastMouseSentAt: TimeInterval = 0
    private var lastCursorSentAt: TimeInterval = 0
    private var typingResetTask: Task<Void, Never>? = nil

    static let collaboratorPalette = [
        "#3B82F6", // Electric Blue
        "#10B981", // Emerald Green
        "#F59E0B", // Vivid Amber
        "#EC4899", // Hot Pink
        "#8B5CF6", // Vivid Violet
        "#06B6D4", // Bright Cyan
        "#EF4444", // Coral Red
        "#84CC16"  // Lime Green
    ]
    
    private static let formalPalette = collaboratorPalette
    
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
        if let existing = existingColor, Self.collaboratorPalette.contains(existing) {
            savedColor = existing
        } else {
            let idx = abs(savedId.hashValue) % Self.collaboratorPalette.count
            let c = Self.collaboratorPalette[idx]
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
        self.sharedWorkspaceRootPath = AppState.shared?.workspaceFolder?.standardizedFileURL.path
        
        // Start Embedded Host Server
        startEmbeddedHostServer(shareCode: shareCode, workspaceName: wsInfo.name, workspaceLang: wsInfo.lang)
        
        let hostParticipant = CollaborationSession.Participant(
            id: localUserId,
            userId: localUserId,
            displayName: localDisplayName,
            role: "Host",
            color: localColor,
            cursorPosition: currentLocalCursorPosition(),
            mousePresence: localMousePresence,
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
        self.isWebSocketRealtimeActive = true
        
        // Index full recursive workspace directory & open buffers
        indexLocalWorkspaceFiles(forceDiskScan: true)
        
        // Register AI Agent as a live teammate in the active Collaboration session
        if isAITeammateEnabled {
            if aiTeammateCursor == nil {
                if let cur = currentLocalCursorPosition() {
                    aiTeammateCursor = cur
                } else if let firstFile = sharedFiles.first {
                    aiTeammateCursor = CollaborationSession.CursorPosition(filePath: firstFile.relativePath, line: 1, column: 1)
                }
            }
            ensureAITeammateInParticipants()
        }
        
        crdtEngine.startSession(siteId: localUserId)
        crdtEngine.updatePeerCount(participants.count)
        
        // Ensure TeamTasks is loaded for current workspace
        if let wsPath = AppState.shared?.workspaceFolder?.path {
            TeamIntegrationService.shared.setTeamTasksEnabled(true)
            TeamTaskService.shared.load(workspacePath: wsPath)
        }
        
        recordActivity(actorName: localDisplayName, actorColor: localColor, action: "started host session", target: wsInfo.name)
        regenerateQRCode()
        startHostMaintenanceTimer()
        NotificationCenter.default.post(name: Self.remotePresenceDidChangeNotification, object: nil)
        
        return session
    }
    
    @discardableResult
    func joinSession(shareCode rawInput: String, mountWorkspace: Bool = true) async throws -> CollaborationSession {
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
            if let assignedColor = json["assignedColor"] as? String, !assignedColor.isEmpty {
                self.localColor = assignedColor
            }
            
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
            
            // Materialize & open the exact same Workspace, Folder Tree, and Code files as Host
            await fetchAndMountSharedWorkspaceBundle(
                baseEndpoint: baseEndpoint,
                shareCode: resolvedCode,
                workspaceName: wsName,
                mountInIDE: mountWorkspace
            )
            
            applySyncPayload(json)
            connectPeerWebSocket(baseEndpoint: baseEndpoint, shareCode: resolvedCode)
            startPeerSyncLoop()
            regenerateQRCode()
            NotificationCenter.default.post(name: Self.remotePresenceDidChangeNotification, object: nil)
            return session
        } catch {
            connectionStatus = .error("Cannot reach host (\(baseEndpoint))")
            throw error
        }
    }

    /// Downloads the Host's complete recursive folder hierarchy & source files and mounts it as the active Workspace in MicroCode.
    private func fetchAndMountSharedWorkspaceBundle(
        baseEndpoint: String,
        shareCode: String,
        workspaceName: String,
        mountInIDE: Bool
    ) async {
        let safeFolderName: String = {
            let cleaned = workspaceName
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "SharedWorkspace" : cleaned
        }()

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let mirrorRootURL = appSupport
            .appendingPathComponent("MicroCode", isDirectory: true)
            .appendingPathComponent("CollabWorkspaces", isDirectory: true)
            .appendingPathComponent(shareCode, isDirectory: true)
            .appendingPathComponent(safeFolderName, isDirectory: true)

        try? FileManager.default.createDirectory(at: mirrorRootURL, withIntermediateDirectories: true)
        self.sharedWorkspaceRootPath = mirrorRootURL.standardizedFileURL.path

        var hostActiveFile: String = ""
        var missingLazyPaths: [String] = []

        if let bundleURL = URL(string: "\(baseEndpoint)/api/collab/workspace-bundle") {
            var req = URLRequest(url: bundleURL)
            req.timeoutInterval = 15
            if let (bundleData, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let bundle = try? JSONSerialization.jsonObject(with: bundleData) as? [String: Any] {
                hostActiveFile = (bundle["hostActiveFile"] as? String) ?? ""

                if let dirs = bundle["directories"] as? [String] {
                    self.sharedDirectories = dirs
                    for relDir in dirs {
                        let cleanDir = sanitizeRelativePath(relDir)
                        guard !cleanDir.isEmpty else { continue }
                        let dirURL = mirrorRootURL.appendingPathComponent(cleanDir, isDirectory: true)
                        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                    }
                }

                if let files = bundle["files"] as? [[String: Any]] {
                    for f in files {
                        guard let rawRel = f["path"] as? String else { continue }
                        let rel = sanitizeRelativePath(rawRel)
                        guard !rel.isEmpty else { continue }
                        let rev = (f["revision"] as? Int) ?? 1
                        let hasInline = (f["hasInlineContent"] as? Bool) ?? (f["content"] != nil)
                        let fileURL = mirrorRootURL.appendingPathComponent(rel)
                        try? FileManager.default.createDirectory(
                            at: fileURL.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        if hasInline, let content = f["content"] as? String {
                            try? content.write(to: fileURL, atomically: true, encoding: .utf8)
                            self.fileContents[rel] = content
                            self.fileRevisions[rel] = rev
                            self.peerBaseRevisions[rel] = rev
                            self.lastSyncedLocalFileHashes[rel] = content.hashValue
                            self.recordRevisionSnapshot(relativePath: rel, revision: rev, content: content)
                        } else {
                            if !FileManager.default.fileExists(atPath: fileURL.path) {
                                try? "".write(to: fileURL, atomically: true, encoding: .utf8)
                            }
                            missingLazyPaths.append(rel)
                        }
                    }
                }
            }
        }

        if mountInIDE, let appState = AppState.shared {
            appState.showingWelcomeHome = false
            appState.showingSettingsDialog = false
            appState.showingCollaborationView = false
            appState.sidebarVisible = true
            SidebarStateController.shared.setVisible(true)

            await appState.openWorkspace(url: mirrorRootURL, autoOpenEntryFile: false)
            AgentService.shared.setWorkspace(mirrorRootURL.path)
            TeamIntegrationService.shared.setTeamTasksEnabled(true)
            TeamTaskService.shared.load(workspacePath: mirrorRootURL.path)

            let cleanHostActive = sanitizeRelativePath(hostActiveFile)
            if !cleanHostActive.isEmpty {
                let activeURL = mirrorRootURL.appendingPathComponent(cleanHostActive)
                if FileManager.default.fileExists(atPath: activeURL.path) {
                    await appState.loadFile(url: activeURL, preserveEditorMode: false)
                    appState.switchToMode(.code)
                }
            } else {
                await appState.openWorkspace(url: mirrorRootURL, autoOpenEntryFile: true)
            }
        }

        // Background-hydrate any large text files that were deferred from the initial bundle
        if !missingLazyPaths.isEmpty {
            let pathsToHydrate = Array(missingLazyPaths.prefix(120))
            Task { @MainActor [weak self] in
                guard let self else { return }
                for rel in pathsToHydrate {
                    guard self.currentSession?.shareCode == shareCode,
                          let encoded = rel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                          let url = URL(string: "\(baseEndpoint)/api/collab/file?path=\(encoded)"),
                          let (d, _) = try? await URLSession.shared.data(from: url),
                          let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                          let remoteContent = j["content"] as? String else { continue }
                    let rev = (j["revision"] as? Int) ?? 1
                    self.fileContents[rel] = remoteContent
                    self.fileRevisions[rel] = rev
                    self.peerBaseRevisions[rel] = rev
                    self.lastSyncedLocalFileHashes[rel] = remoteContent.hashValue
                    self.recordRevisionSnapshot(relativePath: rel, revision: rev, content: remoteContent)
                    let fileURL = mirrorRootURL.appendingPathComponent(rel)
                    try? remoteContent.write(to: fileURL, atomically: true, encoding: .utf8)
                    self.syncBufferToOpenEditorTabIfNeeded(relativePath: rel, content: remoteContent)
                }
            }
        }
    }
    
    func joinDiscoveredSession(_ discovered: DiscoveredCollabSession) async {
        _ = try? await joinSession(shareCode: "\(discovered.hostAddress):\(discovered.port)#\(discovered.shareCode)")
    }
    
    func leaveSession() async {
        peerWSReconnectTask?.cancel()
        peerWSReconnectTask = nil
        peerWebSocketTask?.cancel(with: .goingAway, reason: nil)
        peerWebSocketTask = nil
        typingResetTask?.cancel()
        typingResetTask = nil

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
        aiTypingResetTask?.cancel()
        aiTypingResetTask = nil
        followingUserId = nil
        lastFollowedFileRel = ""
        lastFollowedLine = 0
        aiTeammateCursor = nil
        aiTeammateMouse = nil
        aiTeammateIsWorking = false
        aiTeammateStatusText = "Ready in Collab"
        isWebSocketRealtimeActive = false
        localMousePresence = nil
        localEditorCursor = nil
        sharedWorkspaceRootPath = nil
        sharedDirectories = []
        hostDiskModDates.removeAll()
        crdtEngine.stopSession()
        crdtDocuments.removeAll()
        fileRevisionSnapshots.removeAll()
        peerBaseRevisions.removeAll()
        lastSyncedLocalFileHashes.removeAll()
        currentSession = nil
        participants = []
        sharedFiles = []
        activeFileLocks = [:]
        isConnected = false
        connectionStatus = .disconnected
        NotificationCenter.default.post(name: Self.remotePresenceDidChangeNotification, object: nil)
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
        for (_, client) in hostWSClients {
            client.connection.cancel()
        }
        hostWSClients.removeAll()
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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 524_288) { [weak self] content, _, isComplete, error in
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
                if receivedBodyBytes < contentLength && !isComplete && error == nil && buffer.count < 16_777_216 {
                    self.receiveHTTPRequest(on: connection, accumulated: buffer)
                    return
                }
                let bodyData = buffer.subdata(in: bodyStart..<min(buffer.count, bodyStart + contentLength))
                Task { @MainActor in
                    self.handleHostHTTPRequest(headerStr: headerStr, bodyData: bodyData, connection: connection)
                }
            } else if !isComplete && error == nil && buffer.count < 16_777_216 {
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

    nonisolated private static func parseHeaderValue(_ name: String, from headerStr: String) -> String? {
        let prefix = name.lowercased() + ":"
        for line in headerStr.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func assignDistinctColor(preferred: String?, forUserId userId: String) -> String {
        if let existing = participants.first(where: { $0.userId == userId }) {
            return existing.color
        }
        let usedColors = Set(participants.filter { $0.isOnline && $0.userId != userId }.map { $0.color.uppercased() })
        if let pref = preferred?.uppercased(),
           Self.collaboratorPalette.map({ $0.uppercased() }).contains(pref),
           !usedColors.contains(pref) {
            return pref
        }
        for candidate in Self.collaboratorPalette {
            if !usedColors.contains(candidate.uppercased()) {
                return candidate
            }
        }
        return Self.collaboratorPalette[participants.count % Self.collaboratorPalette.count]
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

        // RFC 6455 WebSocket Upgrade for Real-Time Multiplayer Mouse, Carets & Buffer Sync
        if method == "GET", path == "/ws/collab",
           let upgradeVal = Self.parseHeaderValue("Upgrade", from: headerStr),
           upgradeVal.lowercased().contains("websocket"),
           let wsKey = Self.parseHeaderValue("Sec-WebSocket-Key", from: headerStr) {
            let queryCode = urlComps?.queryItems?.first(where: { $0.name == "code" })?.value?.uppercased() ?? ""
            if let session = currentSession, !queryCode.isEmpty, queryCode != session.shareCode {
                sendHTTPResponse(connection: connection, status: "403 Forbidden", contentType: "text/plain", body: Data("Invalid code".utf8))
                return
            }
            upgradeConnectionToWebSocket(connection: connection, secWebSocketKey: wsKey)
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
            let color = assignDistinctColor(preferred: body["color"] as? String, forUserId: uid)
            
            upsertParticipant(userId: uid, displayName: name, role: role, color: color, cursor: nil)
            recordActivity(actorName: name, actorColor: color, action: "joined session", target: role)
            broadcastHostParticipantsOverWS()
            
            let respData = buildHostSyncPayloadData(assignedColorForJoiner: color)
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json; charset=utf-8", body: respData)

        case ("GET", "/api/collab/workspace-bundle"):
            let bundleData = buildHostWorkspaceBundleData()
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json; charset=utf-8", body: bundleData)
            
        case ("POST", "/api/collab/sync"), ("GET", "/api/collab/sync"):
            if method == "POST", let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                processIncomingPeerSync(body)
            }
            let respData = buildHostSyncPayloadData()
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json; charset=utf-8", body: respData)
            
        case ("GET", "/api/collab/file"):
            let relPath = sanitizeRelativePath(urlComps?.queryItems?.first(where: { $0.name == "path" })?.value ?? "")
            let content = resolveFileContent(relativePath: relPath)
            let payload: [String: Any] = [
                "path": relPath,
                "content": content,
                "revision": fileRevisions[relPath] ?? 1
            ]
            let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json; charset=utf-8", body: data)
            
        case ("POST", "/api/collab/edit"):
            var responseObj: [String: Any] = ["ok": true]
            if let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
               let relPath = body["path"] as? String,
               let newContent = body["content"] as? String {
                let uid = (body["userId"] as? String) ?? "peer"
                let name = (body["displayName"] as? String) ?? "Collaborator"
                let color = (body["color"] as? String) ?? "#3B82F6"
                let baseRevision = body["baseRevision"] as? Int
                let outcome = applyIncomingFileContent(
                    relativePath: relPath,
                    content: newContent,
                    baseRevision: baseRevision,
                    authorId: uid,
                    authorName: name,
                    authorColor: color
                )
                responseObj["revision"] = outcome.revision
                responseObj["merged"] = outcome.didAutoMerge
                if outcome.didAutoMerge {
                    responseObj["content"] = outcome.content
                }
                let cleanRel = normalizeRelativePath(relPath)
                broadcastHostWSMessage([
                    "type": "fileBuffer",
                    "path": cleanRel,
                    "content": outcome.content,
                    "revision": outcome.revision,
                    "authorId": uid,
                    "authorName": name,
                    "authorColor": color
                ], excludingUserId: outcome.didAutoMerge ? nil : uid)
            }
            let data = (try? JSONSerialization.data(withJSONObject: responseObj)) ?? Data()
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/json; charset=utf-8", body: data)

        case ("POST", "/api/collab/fs-event"):
            if let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                applyIncomingFileSystemEvent(body, broadcastToOtherPeers: true)
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
                broadcastHostWSMessage([
                    "type": "chat",
                    "id": msg.id,
                    "userId": uid,
                    "displayName": name,
                    "userColor": color,
                    "message": text
                ])
                handleCollabChatAIMentionIfApplicable(senderId: uid, senderName: name, message: text)
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
                rebuildActiveFileLocks()
                broadcastHostParticipantsOverWS()
                NotificationCenter.default.post(name: Self.remotePresenceDidChangeNotification, object: nil)
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

    // MARK: - RFC 6455 WebSocket Server & Peer Real-Time Transport

    private func upgradeConnectionToWebSocket(connection: NWConnection, secWebSocketKey: String) {
        let magic = secWebSocketKey.trimmingCharacters(in: .whitespacesAndNewlines) + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data(magic.utf8))
        let acceptKey = Data(digest).base64EncodedString()

        let handshake = "HTTP/1.1 101 Switching Protocols\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            "Sec-WebSocket-Accept: \(acceptKey)\r\n\r\n"

        let client = HostWSClient(connection: connection)
        hostWSClients[client.id] = client

        connection.send(content: Data(handshake.utf8), completion: .contentProcessed { [weak self] err in
            guard let self else { return }
            if err != nil {
                Task { @MainActor in
                    self.hostWSClients.removeValue(forKey: client.id)
                }
                connection.cancel()
                return
            }
            Task { @MainActor in
                self.sendHostWSMessage(to: client, object: [
                    "type": "welcome",
                    "shareCode": self.currentSession?.shareCode ?? "",
                    "workspaceName": self.currentSession?.workspaceName ?? "Workspace",
                    "participants": self.serializeParticipantsArray()
                ])
            }
            self.receiveWebSocketFrames(clientId: client.id, connection: connection, buffer: Data())
        })
    }

    nonisolated private func receiveWebSocketFrames(clientId: UUID, connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 262_144) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                _ = error
                self.cleanupDisconnectedWSClient(clientId: clientId, connection: connection)
                return
            }
            var stream = buffer
            if let data, !data.isEmpty {
                stream.append(data)
            }

            while stream.count >= 2 {
                let b0 = stream[stream.startIndex]
                let b1 = stream[stream.startIndex + 1]
                let opcode = b0 & 0x0F
                let isMasked = (b1 & 0x80) != 0
                let len7 = Int(b1 & 0x7F)
                var headerOffset = 2
                var payloadLen = len7

                if len7 == 126 {
                    guard stream.count >= 4 else { break }
                    let hi = Int(stream[stream.startIndex + 2])
                    let lo = Int(stream[stream.startIndex + 3])
                    payloadLen = (hi << 8) | lo
                    headerOffset = 4
                } else if len7 == 127 {
                    guard stream.count >= 10 else { break }
                    var len64: UInt64 = 0
                    for k in 0..<8 {
                        len64 = (len64 << 8) | UInt64(stream[stream.startIndex + 2 + k])
                    }
                    if len64 > 16_777_216 {
                        self.cleanupDisconnectedWSClient(clientId: clientId, connection: connection)
                        return
                    }
                    payloadLen = Int(len64)
                    headerOffset = 10
                }

                var maskKey: [UInt8] = [0, 0, 0, 0]
                if isMasked {
                    guard stream.count >= headerOffset + 4 else { break }
                    for k in 0..<4 {
                        maskKey[k] = stream[stream.startIndex + headerOffset + k]
                    }
                    headerOffset += 4
                }

                let totalFrameLen = headerOffset + payloadLen
                guard stream.count >= totalFrameLen else { break }

                var payload = [UInt8](repeating: 0, count: payloadLen)
                if payloadLen > 0 {
                    for i in 0..<payloadLen {
                        let rawByte = stream[stream.startIndex + headerOffset + i]
                        payload[i] = isMasked ? (rawByte ^ maskKey[i & 3]) : rawByte
                    }
                }
                stream.removeFirst(totalFrameLen)

                switch opcode {
                case 0x1: // Text frame
                    if let text = String(bytes: payload, encoding: .utf8) {
                        Task { @MainActor in
                            self.handleIncomingHostWSText(clientId: clientId, text: text)
                        }
                    }
                case 0x8: // Close
                    let closeFrame = Self.encodeWebSocketFrame(opcode: 0x8, payload: Data())
                    connection.send(content: closeFrame, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    self.cleanupDisconnectedWSClient(clientId: clientId, connection: connection)
                    return
                case 0x9: // Ping -> Pong
                    let pongFrame = Self.encodeWebSocketFrame(opcode: 0xA, payload: Data(payload))
                    connection.send(content: pongFrame, completion: .contentProcessed { _ in })
                default:
                    break
                }
            }

            if isComplete {
                self.cleanupDisconnectedWSClient(clientId: clientId, connection: connection)
                return
            }
            self.receiveWebSocketFrames(clientId: clientId, connection: connection, buffer: stream)
        }
    }

    nonisolated private func cleanupDisconnectedWSClient(clientId: UUID, connection: NWConnection) {
        connection.cancel()
        Task { @MainActor in
            self.hostWSClients.removeValue(forKey: clientId)
        }
    }

    nonisolated private static func encodeWebSocketFrame(opcode: UInt8, payload: Data) -> Data {
        var frame = Data()
        frame.append(0x80 | (opcode & 0x0F))
        let count = payload.count
        if count < 126 {
            frame.append(UInt8(count))
        } else if count <= 65_535 {
            frame.append(126)
            frame.append(UInt8((count >> 8) & 0xFF))
            frame.append(UInt8(count & 0xFF))
        } else {
            frame.append(127)
            let count64 = UInt64(count)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((count64 >> shift) & 0xFF))
            }
        }
        frame.append(payload)
        return frame
    }

    private func sendHostWSMessage(to client: HostWSClient, object: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: object) else { return }
        let frame = Self.encodeWebSocketFrame(opcode: 0x1, payload: jsonData)
        client.connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func broadcastHostWSMessage(_ object: [String: Any], excludingUserId: String? = nil) {
        guard !hostWSClients.isEmpty,
              let jsonData = try? JSONSerialization.data(withJSONObject: object) else { return }
        let frame = Self.encodeWebSocketFrame(opcode: 0x1, payload: jsonData)
        for (_, client) in hostWSClients {
            if let excluded = excludingUserId, client.userId == excluded {
                continue
            }
            client.connection.send(content: frame, completion: .contentProcessed { _ in })
        }
    }

    private func broadcastHostParticipantsOverWS() {
        guard currentSession?.isHostingLocally == true else { return }
        broadcastHostWSMessage([
            "type": "participants",
            "participants": serializeParticipantsArray()
        ])
    }

    private func handleIncomingHostWSText(clientId: UUID, text: String) {
        guard let data = text.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = msg["type"] as? String else { return }

        let uid = (msg["userId"] as? String) ?? hostWSClients[clientId]?.userId ?? ""
        if !uid.isEmpty {
            hostWSClients[clientId]?.userId = uid
        }

        switch type {
        case "hello":
            let name = (msg["displayName"] as? String) ?? "Collaborator"
            let role = (msg["role"] as? String) ?? "Editor"
            let assigned = assignDistinctColor(preferred: msg["color"] as? String, forUserId: uid)
            if !uid.isEmpty {
                upsertParticipant(userId: uid, displayName: name, role: role, color: assigned, cursor: nil)
                if let client = hostWSClients[clientId] {
                    sendHostWSMessage(to: client, object: [
                        "type": "assignedIdentity",
                        "userId": uid,
                        "color": assigned
                    ])
                }
                broadcastHostParticipantsOverWS()
            }

        case "mouse":
            guard !uid.isEmpty else { return }
            let nx = (msg["x"] as? Double) ?? 0.5
            let ny = (msg["y"] as? Double) ?? 0.5
            let surf = (msg["surface"] as? String) ?? "editor"
            let activeFile = (msg["activeFile"] as? String).map { normalizeRelativePath($0) }
            let activeLine = msg["activeLine"] as? Int
            let pressing = (msg["isPressing"] as? Bool) ?? false
            let presence = CollaborationSession.MousePresence(
                normalizedX: max(0, min(1, nx)),
                normalizedY: max(0, min(1, ny)),
                surface: surf,
                activeFile: activeFile,
                activeLine: activeLine,
                isPressing: pressing,
                updatedAt: Date()
            )
            let name = (msg["displayName"] as? String) ?? participants.first(where: { $0.userId == uid })?.displayName ?? "Collaborator"
            let role = (msg["role"] as? String) ?? participants.first(where: { $0.userId == uid })?.role ?? "Editor"
            let color = participants.first(where: { $0.userId == uid })?.color ?? assignDistinctColor(preferred: msg["color"] as? String, forUserId: uid)
            upsertParticipant(userId: uid, displayName: name, role: role, color: color, cursor: nil, mouse: presence)
            broadcastHostWSMessage([
                "type": "mouse",
                "userId": uid,
                "displayName": name,
                "role": role,
                "color": color,
                "x": presence.normalizedX,
                "y": presence.normalizedY,
                "surface": surf,
                "activeFile": activeFile ?? "",
                "activeLine": activeLine ?? 0,
                "isPressing": pressing
            ], excludingUserId: uid)

        case "cursor":
            guard !uid.isEmpty else { return }
            let fp = normalizeRelativePath((msg["filePath"] as? String) ?? "")
            let line = max(1, (msg["line"] as? Int) ?? 1)
            let col = max(1, (msg["column"] as? Int) ?? 1)
            let endLine = msg["endLine"] as? Int
            let endCol = msg["endColumn"] as? Int
            let typing = msg["isTyping"] as? Bool
            let cur = CollaborationSession.CursorPosition(
                filePath: fp,
                line: line,
                column: col,
                endLine: endLine,
                endColumn: endCol,
                isTyping: typing
            )
            let name = (msg["displayName"] as? String) ?? participants.first(where: { $0.userId == uid })?.displayName ?? "Collaborator"
            let role = (msg["role"] as? String) ?? participants.first(where: { $0.userId == uid })?.role ?? "Editor"
            let color = participants.first(where: { $0.userId == uid })?.color ?? assignDistinctColor(preferred: msg["color"] as? String, forUserId: uid)
            upsertParticipant(userId: uid, displayName: name, role: role, color: color, cursor: cur)
            broadcastHostWSMessage([
                "type": "cursor",
                "userId": uid,
                "displayName": name,
                "role": role,
                "color": color,
                "filePath": fp,
                "line": line,
                "column": col,
                "endLine": endLine ?? line,
                "endColumn": endCol ?? col,
                "isTyping": typing ?? false
            ], excludingUserId: uid)

        case "edit":
            guard let relPath = msg["path"] as? String,
                  let content = msg["content"] as? String else { return }
            let name = (msg["displayName"] as? String) ?? "Collaborator"
            let color = participants.first(where: { $0.userId == uid })?.color ?? (msg["color"] as? String) ?? "#3B82F6"
            let baseRev = msg["baseRevision"] as? Int
            let outcome = applyIncomingFileContent(
                relativePath: relPath,
                content: content,
                baseRevision: baseRev,
                authorId: uid,
                authorName: name,
                authorColor: color
            )
            let cleanRel = normalizeRelativePath(relPath)
            if let client = hostWSClients[clientId] {
                var ack: [String: Any] = [
                    "type": "editAck",
                    "path": cleanRel,
                    "revision": outcome.revision,
                    "merged": outcome.didAutoMerge
                ]
                if outcome.didAutoMerge {
                    ack["content"] = outcome.content
                }
                sendHostWSMessage(to: client, object: ack)
            }
            broadcastHostWSMessage([
                "type": "fileBuffer",
                "path": cleanRel,
                "content": outcome.content,
                "revision": outcome.revision,
                "authorId": uid,
                "authorName": name,
                "authorColor": color
            ], excludingUserId: outcome.didAutoMerge ? nil : uid)

        case "fsEvent":
            applyIncomingFileSystemEvent(msg, broadcastToOtherPeers: true, senderUserId: uid)

        case "chat":
            if let textMsg = msg["message"] as? String, !textMsg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let name = (msg["displayName"] as? String) ?? "Collaborator"
                let color = participants.first(where: { $0.userId == uid })?.color ?? (msg["color"] as? String) ?? "#3B82F6"
                let chat = ChatMessage(userId: uid, displayName: name, userColor: color, message: textMsg, timestamp: Date())
                chatMessages.append(chat)
                recordActivity(actorName: name, actorColor: color, action: "posted message", target: String(textMsg.prefix(40)))
                broadcastHostWSMessage([
                    "type": "chat",
                    "id": chat.id,
                    "userId": uid,
                    "displayName": name,
                    "userColor": color,
                    "message": textMsg
                ])
                handleCollabChatAIMentionIfApplicable(senderId: uid, senderName: name, message: textMsg)
            }

        default:
            break
        }
    }

    // MARK: - Peer WebSocket Client Connection

    private func connectPeerWebSocket(baseEndpoint: String, shareCode: String) {
        peerWSReconnectTask?.cancel()
        peerWebSocketTask?.cancel(with: .goingAway, reason: nil)
        peerWebSocketTask = nil
        isWebSocketRealtimeActive = false

        var wsEndpoint = baseEndpoint
        if wsEndpoint.hasPrefix("https://") {
            wsEndpoint = "wss://" + wsEndpoint.dropFirst("https://".count)
        } else if wsEndpoint.hasPrefix("http://") {
            wsEndpoint = "ws://" + wsEndpoint.dropFirst("http://".count)
        } else {
            wsEndpoint = "ws://" + wsEndpoint
        }
        let encodedCode = shareCode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? shareCode
        guard let wsURL = URL(string: "\(wsEndpoint)/ws/collab?code=\(encodedCode)") else { return }

        let task = URLSession.shared.webSocketTask(with: wsURL)
        self.peerWebSocketTask = task
        task.resume()
        self.isWebSocketRealtimeActive = true

        sendPeerWSMessage([
            "type": "hello",
            "userId": localUserId,
            "displayName": localDisplayName,
            "role": localRole,
            "color": localColor
        ])
        listenPeerWebSocket(task: task, baseEndpoint: baseEndpoint, shareCode: shareCode)
    }

    private func sendPeerWSMessage(_ object: [String: Any]) {
        guard let task = peerWebSocketTask,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let str = String(data: data, encoding: .utf8) else { return }
        task.send(.string(str)) { [weak self] err in
            if err != nil {
                Task { @MainActor in
                    self?.isWebSocketRealtimeActive = false
                }
            }
        }
    }

    private func listenPeerWebSocket(task: URLSessionWebSocketTask, baseEndpoint: String, shareCode: String) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.peerWebSocketTask === task else { return }
                switch result {
                case .success(let message):
                    self.isWebSocketRealtimeActive = true
                    switch message {
                    case .string(let str):
                        self.handleIncomingPeerWSText(str)
                    case .data(let data):
                        if let str = String(data: data, encoding: .utf8) {
                            self.handleIncomingPeerWSText(str)
                        }
                    @unknown default:
                        break
                    }
                    self.listenPeerWebSocket(task: task, baseEndpoint: baseEndpoint, shareCode: shareCode)

                case .failure:
                    self.isWebSocketRealtimeActive = false
                    guard self.currentSession?.isHostingLocally == false,
                          self.currentSession?.shareCode == shareCode else { return }
                    self.peerWSReconnectTask?.cancel()
                    self.peerWSReconnectTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        guard !Task.isCancelled, let self,
                              self.currentSession?.isHostingLocally == false,
                              self.currentSession?.shareCode == shareCode else { return }
                        self.connectPeerWebSocket(baseEndpoint: baseEndpoint, shareCode: shareCode)
                    }
                }
            }
        }
    }

    private func handleIncomingPeerWSText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = msg["type"] as? String else { return }

        switch type {
        case "welcome", "participants":
            if let pArr = msg["participants"] as? [[String: Any]] {
                applyParticipantsArray(pArr)
            }

        case "assignedIdentity":
            if let assigned = msg["color"] as? String, !assigned.isEmpty {
                self.localColor = assigned
                updateSelfInParticipants()
            }

        case "mouse":
            guard let uid = msg["userId"] as? String, uid != localUserId else { return }
            let nx = (msg["x"] as? Double) ?? 0.5
            let ny = (msg["y"] as? Double) ?? 0.5
            let surf = (msg["surface"] as? String) ?? "editor"
            let activeFile = (msg["activeFile"] as? String).flatMap { $0.isEmpty ? nil : normalizeRelativePath($0) }
            let activeLine = (msg["activeLine"] as? Int).flatMap { $0 > 0 ? $0 : nil }
            let pressing = (msg["isPressing"] as? Bool) ?? false
            let presence = CollaborationSession.MousePresence(
                normalizedX: max(0, min(1, nx)),
                normalizedY: max(0, min(1, ny)),
                surface: surf,
                activeFile: activeFile,
                activeLine: activeLine,
                isPressing: pressing,
                updatedAt: Date()
            )
            let name = (msg["displayName"] as? String) ?? "Collaborator"
            let role = (msg["role"] as? String) ?? "Editor"
            let color = (msg["color"] as? String) ?? "#3B82F6"
            upsertParticipant(userId: uid, displayName: name, role: role, color: color, cursor: nil, mouse: presence)

        case "cursor":
            guard let uid = msg["userId"] as? String, uid != localUserId else { return }
            let fp = normalizeRelativePath((msg["filePath"] as? String) ?? "")
            let line = max(1, (msg["line"] as? Int) ?? 1)
            let col = max(1, (msg["column"] as? Int) ?? 1)
            let endLine = msg["endLine"] as? Int
            let endCol = msg["endColumn"] as? Int
            let typing = msg["isTyping"] as? Bool
            let cur = CollaborationSession.CursorPosition(
                filePath: fp,
                line: line,
                column: col,
                endLine: endLine,
                endColumn: endCol,
                isTyping: typing
            )
            let name = (msg["displayName"] as? String) ?? "Collaborator"
            let role = (msg["role"] as? String) ?? "Editor"
            let color = (msg["color"] as? String) ?? "#3B82F6"
            upsertParticipant(userId: uid, displayName: name, role: role, color: color, cursor: cur)

        case "editAck":
            guard let relPath = msg["path"] as? String else { return }
            let rel = normalizeRelativePath(relPath)
            if let newRev = msg["revision"] as? Int {
                let authContent = (msg["content"] as? String) ?? fileContents[rel] ?? ""
                recordRevisionSnapshot(relativePath: rel, revision: newRev, content: authContent)
                peerBaseRevisions[rel] = newRev
                fileRevisions[rel] = newRev
            }
            if let didMerge = msg["merged"] as? Bool, didMerge,
               let mergedContent = msg["content"] as? String {
                fileContents[rel] = mergedContent
                writeRelativeFileToSharedRootIfPossible(relativePath: rel, content: mergedContent)
                syncBufferToOpenEditorTabIfNeeded(relativePath: rel, content: mergedContent)
            }

        case "fileBuffer":
            guard let rawPath = msg["path"] as? String,
                  let remoteContent = msg["content"] as? String else { return }
            let authorId = (msg["authorId"] as? String) ?? ""
            if authorId == localUserId && (msg["merged"] as? Bool) != true {
                return
            }
            let rel = normalizeRelativePath(rawPath)
            let remoteRev = (msg["revision"] as? Int) ?? ((fileRevisions[rel] ?? 1) + 1)
            let knownBaseRev = peerBaseRevisions[rel] ?? 0
            let resolvedContent: String
            if let localContent = fileContents[rel],
               localContent != remoteContent,
               knownBaseRev > 0,
               let baseSnapshot = fileRevisionSnapshots[rel]?[knownBaseRev],
               localContent != baseSnapshot {
                resolvedContent = CollaborativeThreeWayMerger.merge(
                    base: baseSnapshot,
                    current: remoteContent,
                    incoming: localContent
                ).merged
            } else {
                resolvedContent = remoteContent
            }
            recordRevisionSnapshot(relativePath: rel, revision: remoteRev, content: remoteContent)
            peerBaseRevisions[rel] = remoteRev
            fileRevisions[rel] = remoteRev
            fileContents[rel] = resolvedContent
            writeRelativeFileToSharedRootIfPossible(relativePath: rel, content: resolvedContent)
            syncBufferToOpenEditorTabIfNeeded(relativePath: rel, content: resolvedContent)

        case "fsEvent":
            applyIncomingFileSystemEvent(msg, broadcastToOtherPeers: false)

        case "chat":
            if let textMsg = msg["message"] as? String {
                let id = (msg["id"] as? String) ?? UUID().uuidString
                if !chatMessages.contains(where: { $0.id == id }) {
                    chatMessages.append(ChatMessage(
                        id: id,
                        userId: (msg["userId"] as? String) ?? "",
                        displayName: (msg["displayName"] as? String) ?? "Collaborator",
                        userColor: (msg["userColor"] as? String) ?? "#3B82F6",
                        message: textMsg,
                        timestamp: Date()
                    ))
                }
            }

        default:
            break
        }
    }
    
    // MARK: - Sync State Assembly & Processing
    
    private func upsertParticipant(
        userId: String,
        displayName: String,
        role: String,
        color: String,
        cursor: CollaborationSession.CursorPosition?,
        mouse: CollaborationSession.MousePresence? = nil,
        activeTaskTitle: String? = nil,
        isAIActive: Bool? = nil,
        aiStatusText: String? = nil
    ) {
        if let idx = participants.firstIndex(where: { $0.userId == userId }) {
            participants[idx].displayName = displayName
            participants[idx].role = role
            participants[idx].color = color
            if let cursor {
                participants[idx].cursorPosition = cursor
            }
            if let mouse {
                participants[idx].mousePresence = mouse
            }
            if let activeTaskTitle {
                participants[idx].activeTaskTitle = activeTaskTitle
            }
            if let isAIActive {
                participants[idx].isAIActive = isAIActive
            }
            if let aiStatusText {
                participants[idx].aiStatusText = aiStatusText
            }
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
                mousePresence: mouse,
                activeTaskTitle: activeTaskTitle,
                isAIActive: isAIActive ?? false,
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
        NotificationCenter.default.post(name: Self.remotePresenceDidChangeNotification, object: nil)
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
            mouse: localMousePresence,
            activeTaskTitle: TeamTaskService.shared.selectedTask?.title,
            isAIActive: AgentService.shared.isLoading,
            aiStatusText: AgentService.shared.currentToolExecution ?? AgentService.shared.agentPhase.displayText
        )
        if currentSession?.isHostingLocally == true && isAITeammateEnabled {
            ensureAITeammateInParticipants()
        }
    }
    
    private func rebuildActiveFileLocks() {
        var locks: [String: (userId: String, name: String, color: String)] = [:]
        // Prefer remote collaborators over local user when badging shared files so you see teammates first
        for p in participants where p.isOnline && p.userId != localUserId {
            if let cur = p.cursorPosition, !cur.filePath.isEmpty {
                let rel = normalizeRelativePath(cur.filePath)
                locks[rel] = (p.userId, p.displayName, p.color)
            }
        }
        for p in participants where p.isOnline && p.userId == localUserId {
            if let cur = p.cursorPosition, !cur.filePath.isEmpty {
                let rel = normalizeRelativePath(cur.filePath)
                if locks[rel] == nil {
                    locks[rel] = (p.userId, p.displayName, p.color)
                }
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

    private func serializeParticipantsArray() -> [[String: Any]] {
        participants.map { p in
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
                    "column": c.column,
                    "endLine": c.endLine ?? c.line,
                    "endColumn": c.endColumn ?? c.column,
                    "isTyping": c.isTyping ?? false
                ]
            }
            if let m = p.mousePresence, Date().timeIntervalSince(m.updatedAt) < 20 {
                dict["mouse"] = [
                    "x": m.normalizedX,
                    "y": m.normalizedY,
                    "surface": m.surface,
                    "activeFile": m.activeFile ?? "",
                    "activeLine": m.activeLine ?? 0,
                    "isPressing": m.isPressing
                ]
            }
            return dict
        }
    }

    private func applyParticipantsArray(_ pArr: [[String: Any]]) {
        let existingByUser = Dictionary(uniqueKeysWithValues: participants.map { ($0.userId, $0) })
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

            if uid == localUserId, !color.isEmpty, self.localColor != color {
                self.localColor = color
            }

            var cursor: CollaborationSession.CursorPosition? = nil
            if let cDict = item["cursor"] as? [String: Any],
               let fp = cDict["filePath"] as? String {
                cursor = CollaborationSession.CursorPosition(
                    filePath: normalizeRelativePath(fp),
                    line: max(1, (cDict["line"] as? Int) ?? 1),
                    column: max(1, (cDict["column"] as? Int) ?? 1),
                    endLine: cDict["endLine"] as? Int,
                    endColumn: cDict["endColumn"] as? Int,
                    isTyping: cDict["isTyping"] as? Bool
                )
            } else if uid == localUserId {
                cursor = localEditorCursor ?? currentLocalCursorPosition()
            } else if let prev = existingByUser[uid], isWebSocketRealtimeActive {
                cursor = prev.cursorPosition
            }

            var mouse: CollaborationSession.MousePresence? = nil
            if uid == localUserId {
                mouse = localMousePresence
            } else if let prev = existingByUser[uid]?.mousePresence,
                      isWebSocketRealtimeActive,
                      Date().timeIntervalSince(prev.updatedAt) < 3.0 {
                mouse = prev
            } else if let mDict = item["mouse"] as? [String: Any],
                      let mx = mDict["x"] as? Double,
                      let my = mDict["y"] as? Double {
                mouse = CollaborationSession.MousePresence(
                    normalizedX: max(0, min(1, mx)),
                    normalizedY: max(0, min(1, my)),
                    surface: (mDict["surface"] as? String) ?? "editor",
                    activeFile: (mDict["activeFile"] as? String).flatMap { $0.isEmpty ? nil : normalizeRelativePath($0) },
                    activeLine: (mDict["activeLine"] as? Int).flatMap { $0 > 0 ? $0 : nil },
                    isPressing: (mDict["isPressing"] as? Bool) ?? false,
                    updatedAt: existingByUser[uid]?.mousePresence?.updatedAt ?? Date()
                )
            }

            newList.append(CollaborationSession.Participant(
                id: uid,
                userId: uid,
                displayName: name,
                role: role,
                color: color,
                cursorPosition: cursor,
                mousePresence: mouse,
                activeTaskTitle: activeTaskTitle,
                isAIActive: isAIActive,
                aiStatusText: aiStatusText,
                isOnline: isOnline,
                joinedAt: existingByUser[uid]?.joinedAt ?? Date(),
                lastSeenAt: Date()
            ))
        }
        self.participants = newList
        crdtEngine.updatePeerCount(newList.count)
        rebuildActiveFileLocks()
        NotificationCenter.default.post(name: Self.remotePresenceDidChangeNotification, object: nil)
    }
    
    private func processIncomingPeerSync(_ body: [String: Any]) {
        guard let uid = body["userId"] as? String else { return }
        let name = (body["displayName"] as? String) ?? "Collaborator"
        let role = (body["role"] as? String) ?? "Editor"
        let color = assignDistinctColor(preferred: body["color"] as? String, forUserId: uid)
        var cursor: CollaborationSession.CursorPosition? = nil
        if let curDict = body["cursor"] as? [String: Any],
           let fp = curDict["filePath"] as? String {
            cursor = CollaborationSession.CursorPosition(
                filePath: normalizeRelativePath(fp),
                line: max(1, (curDict["line"] as? Int) ?? 1),
                column: max(1, (curDict["column"] as? Int) ?? 1),
                endLine: curDict["endLine"] as? Int,
                endColumn: curDict["endColumn"] as? Int,
                isTyping: curDict["isTyping"] as? Bool
            )
        }
        var mouse: CollaborationSession.MousePresence? = nil
        if let mDict = body["mouse"] as? [String: Any],
           let mx = mDict["x"] as? Double,
           let my = mDict["y"] as? Double {
            mouse = CollaborationSession.MousePresence(
                normalizedX: max(0, min(1, mx)),
                normalizedY: max(0, min(1, my)),
                surface: (mDict["surface"] as? String) ?? "editor",
                activeFile: (mDict["activeFile"] as? String).flatMap { $0.isEmpty ? nil : normalizeRelativePath($0) },
                activeLine: (mDict["activeLine"] as? Int).flatMap { $0 > 0 ? $0 : nil },
                isPressing: (mDict["isPressing"] as? Bool) ?? false,
                updatedAt: Date()
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
            mouse: mouse,
            activeTaskTitle: taskTitle,
            isAIActive: aiActive,
            aiStatusText: aiText
        )
        
        // Apply any modified file buffer pushed by peer
        if let edits = body["fileEdits"] as? [[String: Any]] {
            for edit in edits {
                if let path = edit["path"] as? String,
                   let content = edit["content"] as? String {
                    let baseRev = edit["baseRevision"] as? Int
                    let outcome = applyIncomingFileContent(
                        relativePath: path,
                        content: content,
                        baseRevision: baseRev,
                        authorId: uid,
                        authorName: name,
                        authorColor: color
                    )
                    let cleanRel = normalizeRelativePath(path)
                    broadcastHostWSMessage([
                        "type": "fileBuffer",
                        "path": cleanRel,
                        "content": outcome.content,
                        "revision": outcome.revision,
                        "authorId": uid,
                        "authorName": name,
                        "authorColor": color
                    ], excludingUserId: outcome.didAutoMerge ? nil : uid)
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

    private func buildHostWorkspaceBundleData() -> Data {
        indexLocalWorkspaceFiles(forceDiskScan: true)
        let wsRoot = sharedWorkspaceRootPath ?? AppState.shared?.workspaceFolder?.standardizedFileURL.path ?? ""
        let hostActive = AppState.shared?.currentFile.map { normalizeRelativePath($0.path) } ?? ""

        var filesPayload: [[String: Any]] = []
        var inlineBudgetRemaining = 12 * 1024 * 1024 // 12 MB fast initial inline budget

        for file in sharedFiles {
            let rel = file.relativePath
            var item: [String: Any] = [
                "path": rel,
                "name": file.name,
                "language": file.language,
                "revision": fileRevisions[rel] ?? 1
            ]

            if let memContent = fileContents[rel], memContent.utf8.count <= 262_144, memContent.utf8.count <= inlineBudgetRemaining {
                item["hasInlineContent"] = true
                item["content"] = memContent
                inlineBudgetRemaining -= memContent.utf8.count
            } else if !wsRoot.isEmpty {
                let fullURL = URL(fileURLWithPath: wsRoot).appendingPathComponent(rel)
                if let vals = try? fullURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                   vals.isRegularFile != false {
                    let size = vals.fileSize ?? 0
                    item["size"] = size
                    if size <= 262_144, size <= inlineBudgetRemaining,
                       let data = try? Data(contentsOf: fullURL, options: [.mappedIfSafe]),
                       !data.prefix(4096).contains(0),
                       let text = String(data: data, encoding: .utf8) {
                        item["hasInlineContent"] = true
                        item["content"] = text
                        inlineBudgetRemaining -= data.count
                        fileContents[rel] = text
                        let rev = fileRevisions[rel] ?? 1
                        fileRevisions[rel] = rev
                        if fileRevisionSnapshots[rel]?[rev] == nil {
                            recordRevisionSnapshot(relativePath: rel, revision: rev, content: text)
                        }
                    } else {
                        item["hasInlineContent"] = false
                    }
                } else {
                    item["hasInlineContent"] = false
                }
            } else {
                item["hasInlineContent"] = false
            }
            filesPayload.append(item)
        }

        let bundle: [String: Any] = [
            "shareCode": currentSession?.shareCode ?? "",
            "workspaceName": currentSession?.workspaceName ?? "Workspace",
            "workspaceLang": currentSession?.workspaceLang ?? "code",
            "hostUserId": currentSession?.hostUserId ?? localUserId,
            "hostDisplayName": currentSession?.hostDisplayName ?? localDisplayName,
            "hostActiveFile": hostActive,
            "directories": sharedDirectories,
            "files": filesPayload
        ]
        return (try? JSONSerialization.data(withJSONObject: bundle)) ?? Data("{}".utf8)
    }
    
    private func buildHostSyncPayloadData(assignedColorForJoiner: String? = nil) -> Data {
        updateSelfInParticipants()
        indexLocalWorkspaceFiles(forceDiskScan: false)
        
        let participantsArr = serializeParticipantsArray()
        
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
        
        // Include open/recently edited file contents & their authoritative revisions for conflict-free sync
        var openBuffers: [String: String] = [:]
        var openBufferRevisions: [String: Int] = [:]
        if let state = AppState.shared {
            for open in state.openFiles.prefix(24) {
                let rel = normalizeRelativePath(open.path)
                guard !rel.isEmpty, open.content.utf8.count <= 262_144 else { continue }
                openBuffers[rel] = open.content
                let rev = fileRevisions[rel] ?? 1
                openBufferRevisions[rel] = rev
                if fileRevisionSnapshots[rel]?[rev] == nil {
                    recordRevisionSnapshot(relativePath: rel, revision: rev, content: open.content)
                }
            }
        }
        for (relPath, content) in fileContents where openBuffers.count < 32 && openBuffers[relPath] == nil && content.utf8.count <= 262_144 {
            openBuffers[relPath] = content
            let rev = fileRevisions[relPath] ?? 1
            openBufferRevisions[relPath] = rev
            if fileRevisionSnapshots[relPath]?[rev] == nil {
                recordRevisionSnapshot(relativePath: relPath, revision: rev, content: content)
            }
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
        
        var payload: [String: Any] = [
            "shareCode": currentSession?.shareCode ?? "",
            "workspaceName": currentSession?.workspaceName ?? "Workspace",
            "workspaceLang": currentSession?.workspaceLang ?? "code",
            "hostUserId": currentSession?.hostUserId ?? localUserId,
            "hostDisplayName": currentSession?.hostDisplayName ?? localDisplayName,
            "participants": participantsArr,
            "sharedDirectories": sharedDirectories,
            "sharedFiles": filesArr,
            "openBuffers": openBuffers,
            "fileRevisions": openBufferRevisions,
            "chatMessages": chatArr,
            "activityLog": activityArr,
            "teamTasksJSON": tasksJSONString
        ]
        if let assigned = assignedColorForJoiner {
            payload["assignedColor"] = assigned
        }
        
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
            applyParticipantsArray(pArr)
        }

        var didChangeTreeStructure = false
        if let dirs = json["sharedDirectories"] as? [String], dirs != self.sharedDirectories {
            self.sharedDirectories = dirs
            if let root = sharedWorkspaceRootPath, !root.isEmpty {
                let rootURL = URL(fileURLWithPath: root, isDirectory: true)
                for d in dirs {
                    let clean = sanitizeRelativePath(d)
                    guard !clean.isEmpty else { continue }
                    let dirURL = rootURL.appendingPathComponent(clean, isDirectory: true)
                    if !FileManager.default.fileExists(atPath: dirURL.path) {
                        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                        didChangeTreeStructure = true
                    }
                }
            }
        }
        
        if let fArr = json["sharedFiles"] as? [[String: Any]] {
            let oldPaths = Set(self.sharedFiles.map(\.relativePath))
            let parsedFiles: [SharedWorkspaceFile] = fArr.compactMap { item in
                guard let rawRel = item["relativePath"] as? String,
                      let name = item["name"] as? String else { return nil }
                let rel = sanitizeRelativePath(rawRel)
                guard !rel.isEmpty else { return nil }
                return SharedWorkspaceFile(
                    relativePath: rel,
                    name: name,
                    language: (item["language"] as? String) ?? "code",
                    isOpenOnHost: (item["isOpenOnHost"] as? Bool) ?? false,
                    activeEditorName: (item["activeEditorName"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                    activeEditorColor: (item["activeEditorColor"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                )
            }
            self.sharedFiles = parsedFiles
            let newPaths = Set(parsedFiles.map(\.relativePath))
            if newPaths != oldPaths {
                didChangeTreeStructure = true
                // Fetch any brand-new files created on Host so Peer's mirrored workspace stays 100% synced
                if currentSession?.isHostingLocally == false,
                   let root = sharedWorkspaceRootPath, !root.isEmpty,
                   let endpoint = currentSession?.remoteEndpoint {
                    let addedPaths = Array(newPaths.subtracting(oldPaths))
                    if !addedPaths.isEmpty {
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            for rel in addedPaths {
                                guard let encoded = rel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                                      let url = URL(string: "\(endpoint)/api/collab/file?path=\(encoded)"),
                                      let (d, _) = try? await URLSession.shared.data(from: url),
                                      let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                                      let content = j["content"] as? String else { continue }
                                let rev = (j["revision"] as? Int) ?? 1
                                self.fileContents[rel] = content
                                self.fileRevisions[rel] = rev
                                self.peerBaseRevisions[rel] = rev
                                self.recordRevisionSnapshot(relativePath: rel, revision: rev, content: content)
                                self.writeRelativeFileToSharedRootIfPossible(relativePath: rel, content: content)
                            }
                            await AppState.shared?.refreshFileTree()
                        }
                    }
                }
            }
        }
        
        let incomingRevisions = (json["fileRevisions"] as? [String: Int]) ?? [:]
        if let buffers = json["openBuffers"] as? [String: String] {
            for (rawRelPath, remoteContent) in buffers {
                let relPath = sanitizeRelativePath(rawRelPath)
                guard !relPath.isEmpty else { continue }
                let remoteRev = incomingRevisions[rawRelPath] ?? incomingRevisions[relPath] ?? fileRevisions[relPath] ?? 1
                let knownBaseRev = peerBaseRevisions[relPath] ?? 0
                if knownBaseRev > 0 && remoteRev <= knownBaseRev {
                    continue
                }
                let resolvedContent: String
                if let localContent = fileContents[relPath],
                   localContent != remoteContent,
                   knownBaseRev > 0,
                   let baseSnapshot = fileRevisionSnapshots[relPath]?[knownBaseRev],
                   localContent != baseSnapshot {
                    resolvedContent = CollaborativeThreeWayMerger.merge(
                        base: baseSnapshot,
                        current: remoteContent,
                        incoming: localContent
                    ).merged
                } else {
                    resolvedContent = remoteContent
                }
                recordRevisionSnapshot(relativePath: relPath, revision: remoteRev, content: remoteContent)
                peerBaseRevisions[relPath] = remoteRev
                fileRevisions[relPath] = remoteRev
                if fileContents[relPath] != resolvedContent {
                    fileContents[relPath] = resolvedContent
                    writeRelativeFileToSharedRootIfPossible(relativePath: relPath, content: resolvedContent)
                    syncBufferToOpenEditorTabIfNeeded(relativePath: relPath, content: resolvedContent)
                }
            }
        }

        if didChangeTreeStructure, currentSession?.isHostingLocally == false {
            Task { @MainActor in
                await AppState.shared?.refreshFileTree()
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
    
    // MARK: - Full Recursive Workspace File Indexing & Bidirectional Disk Sync

    private static let ignoredDirectoryNames: Set<String> = [
        ".git", "node_modules", ".build", "target", "dist", "build",
        ".next", ".nuxt", ".cache", ".turbo", "pods", "deriveddata",
        ".codetuner-build", "__pycache__", ".venv", "venv", ".gradle", ".idea"
    ]

    private static let ignoredFileNames: Set<String> = [
        ".ds_store", "thumbs.db"
    ]
    
    func indexLocalWorkspaceFiles(forceDiskScan: Bool = true) {
        if let session = currentSession, !session.isHostingLocally {
            return
        }
        guard let state = AppState.shared else { return }
        let wsRoot = state.workspaceFolder?.standardizedFileURL.path ?? sharedWorkspaceRootPath ?? ""
        if !wsRoot.isEmpty && sharedWorkspaceRootPath != wsRoot {
            sharedWorkspaceRootPath = wsRoot
        }

        var openRelativeSet = Set<String>()
        for openFile in state.openFiles {
            let rel = normalizeRelativePath(openFile.path)
            guard !rel.isEmpty else { continue }
            openRelativeSet.insert(rel)
            let previousContent = fileContents[rel]
            fileContents[rel] = openFile.content
            if let existingRev = fileRevisions[rel] {
                if let prev = previousContent, prev != openFile.content {
                    let nextRev = existingRev + 1
                    fileRevisions[rel] = nextRev
                    recordRevisionSnapshot(relativePath: rel, revision: nextRev, content: openFile.content)
                } else if fileRevisionSnapshots[rel]?[existingRev] == nil {
                    recordRevisionSnapshot(relativePath: rel, revision: existingRev, content: openFile.content)
                }
            } else {
                fileRevisions[rel] = 1
                recordRevisionSnapshot(relativePath: rel, revision: 1, content: openFile.content)
            }
        }

        let now = Date()
        if !forceDiskScan && !sharedFiles.isEmpty && now.timeIntervalSince(lastDiskScanAt) < 2.5 {
            for i in 0..<sharedFiles.count {
                let rel = sharedFiles[i].relativePath
                sharedFiles[i].isOpenOnHost = openRelativeSet.contains(rel)
                if let lock = activeFileLocks[rel] {
                    sharedFiles[i].activeEditorName = lock.name
                    sharedFiles[i].activeEditorColor = lock.color
                } else {
                    sharedFiles[i].activeEditorName = nil
                    sharedFiles[i].activeEditorColor = nil
                }
            }
            return
        }
        lastDiskScanAt = now

        var discoveredFiles: [SharedWorkspaceFile] = []
        var discoveredDirs: [String] = []
        var seenFiles = Set<String>()

        // 1. Always include open files first
        for openFile in state.openFiles {
            let rel = normalizeRelativePath(openFile.path)
            guard !rel.isEmpty, !seenFiles.contains(rel) else { continue }
            seenFiles.insert(rel)
            let lock = activeFileLocks[rel]
            discoveredFiles.append(SharedWorkspaceFile(
                relativePath: rel,
                name: openFile.name,
                language: openFile.language,
                isOpenOnHost: true,
                activeEditorName: lock?.name,
                activeEditorColor: lock?.color
            ))
        }

        // 2. Full recursive walk of the real filesystem directory (not lazy UI nodes!)
        let fm = FileManager.default
        func scanDirectory(at dirURL: URL, relativePrefix: String, depth: Int) {
            guard depth <= 8, discoveredFiles.count < 800, discoveredDirs.count < 600 else { return }
            guard let items = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey],
                options: []
            ) else { return }

            let sorted = items.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }

            for itemURL in sorted {
                let name = itemURL.lastPathComponent
                let lower = name.lowercased()
                if Self.ignoredFileNames.contains(lower) { continue }
                guard let vals = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]) else {
                    continue
                }
                if vals.isSymbolicLink == true { continue }

                let rel = relativePrefix.isEmpty ? name : "\(relativePrefix)/\(name)"
                if vals.isDirectory == true {
                    if Self.ignoredDirectoryNames.contains(lower) { continue }
                    if discoveredDirs.count < 600 {
                        discoveredDirs.append(rel)
                    }
                    scanDirectory(at: itemURL, relativePrefix: rel, depth: depth + 1)
                } else if vals.isRegularFile != false {
                    guard discoveredFiles.count < 800 else { break }
                    let size = vals.fileSize ?? 0
                    if size > 2 * 1024 * 1024 { continue } // Skip multi-MB binaries

                    if let modDate = vals.contentModificationDate {
                        if let prevDate = hostDiskModDates[rel], modDate > prevDate, !openRelativeSet.contains(rel) {
                            // External/Agent edit occurred on disk! Read & broadcast
                            if size <= 262_144,
                               let data = try? Data(contentsOf: itemURL),
                               !data.prefix(4096).contains(0),
                               let updatedText = String(data: data, encoding: .utf8),
                               fileContents[rel] != updatedText {
                                let nextRev = (fileRevisions[rel] ?? 1) + 1
                                fileContents[rel] = updatedText
                                fileRevisions[rel] = nextRev
                                recordRevisionSnapshot(relativePath: rel, revision: nextRev, content: updatedText)
                                broadcastHostWSMessage([
                                    "type": "fileBuffer",
                                    "path": rel,
                                    "content": updatedText,
                                    "revision": nextRev,
                                    "authorId": localUserId,
                                    "authorName": localDisplayName,
                                    "authorColor": localColor
                                ])
                            }
                        }
                        hostDiskModDates[rel] = modDate
                    }

                    guard !seenFiles.contains(rel) else { continue }
                    seenFiles.insert(rel)
                    let ext = (name as NSString).pathExtension.lowercased()
                    let lock = activeFileLocks[rel]
                    discoveredFiles.append(SharedWorkspaceFile(
                        relativePath: rel,
                        name: name,
                        language: ext.isEmpty ? "code" : ext,
                        isOpenOnHost: openRelativeSet.contains(rel),
                        activeEditorName: lock?.name,
                        activeEditorColor: lock?.color
                    ))
                }
            }
        }

        if !wsRoot.isEmpty {
            scanDirectory(at: URL(fileURLWithPath: wsRoot, isDirectory: true), relativePrefix: "", depth: 0)
        }

        self.sharedDirectories = discoveredDirs
        self.sharedFiles = discoveredFiles
    }

    func sanitizeRelativePath(_ raw: String) -> String {
        let unified = raw.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unified.isEmpty else { return "" }
        let parts = unified.split(separator: "/").map(String.init).filter {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
        return parts.joined(separator: "/")
    }
    
    func normalizeRelativePath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if trimmed.hasPrefix("/") {
            let std = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            if let sharedRoot = sharedWorkspaceRootPath, !sharedRoot.isEmpty {
                let normRoot = URL(fileURLWithPath: sharedRoot).standardizedFileURL.path
                if std.hasPrefix(normRoot + "/") {
                    return sanitizeRelativePath(String(std.dropFirst(normRoot.count + 1)))
                }
            }
            if let wsRoot = AppState.shared?.workspaceFolder?.standardizedFileURL.path, !wsRoot.isEmpty {
                if std.hasPrefix(wsRoot + "/") {
                    return sanitizeRelativePath(String(std.dropFirst(wsRoot.count + 1)))
                }
            }
            return (std as NSString).lastPathComponent
        }

        // Already a relative path (e.g. "src/components/App.tsx") — preserve full folder structure!
        return sanitizeRelativePath(trimmed)
    }

    private func writeRelativeFileToSharedRootIfPossible(relativePath: String, content: String) {
        let rel = sanitizeRelativePath(relativePath)
        guard !rel.isEmpty else { return }
        let rootPath = sharedWorkspaceRootPath ?? AppState.shared?.workspaceFolder?.standardizedFileURL.path ?? ""
        guard !rootPath.isEmpty else { return }
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let fileURL = rootURL.appendingPathComponent(rel).standardizedFileURL
        guard fileURL.path.hasPrefix(rootURL.path + "/") else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        if let mod = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
            hostDiskModDates[rel] = mod
        }
    }
    
    private func recordRevisionSnapshot(relativePath: String, revision: Int, content: String) {
        var revMap = fileRevisionSnapshots[relativePath] ?? [:]
        revMap[revision] = content
        if revMap.count > 32 {
            let sortedKeys = revMap.keys.sorted()
            for oldKey in sortedKeys.prefix(revMap.count - 32) {
                revMap.removeValue(forKey: oldKey)
            }
        }
        fileRevisionSnapshots[relativePath] = revMap
    }

    private func resolveFileContent(relativePath: String) -> String {
        let rel = normalizeRelativePath(relativePath)
        guard !rel.isEmpty else { return "" }
        if let cached = fileContents[rel] {
            let rev = fileRevisions[rel] ?? 1
            fileRevisions[rel] = rev
            if fileRevisionSnapshots[rel]?[rev] == nil {
                recordRevisionSnapshot(relativePath: rel, revision: rev, content: cached)
            }
            return cached
        }
        if let state = AppState.shared {
            if let openMatch = state.openFiles.first(where: { normalizeRelativePath($0.path) == rel }) {
                fileContents[rel] = openMatch.content
                let rev = fileRevisions[rel] ?? 1
                fileRevisions[rel] = rev
                recordRevisionSnapshot(relativePath: rel, revision: rev, content: openMatch.content)
                return openMatch.content
            }
            let rootPath = sharedWorkspaceRootPath ?? state.workspaceFolder?.path
            if let wsRoot = rootPath {
                let fullURL = URL(fileURLWithPath: wsRoot).appendingPathComponent(rel)
                if let str = try? String(contentsOf: fullURL, encoding: .utf8) {
                    fileContents[rel] = str
                    let rev = fileRevisions[rel] ?? 1
                    fileRevisions[rel] = rev
                    recordRevisionSnapshot(relativePath: rel, revision: rev, content: str)
                    return str
                }
            }
        }
        return ""
    }
    
    @discardableResult
    private func applyIncomingFileContent(
        relativePath: String,
        content: String,
        baseRevision: Int? = nil,
        authorId: String,
        authorName: String,
        authorColor: String
    ) -> (content: String, revision: Int, didAutoMerge: Bool) {
        let rel = normalizeRelativePath(relativePath)
        guard !rel.isEmpty else {
            return (content: content, revision: 1, didAutoMerge: false)
        }

        let currentContent = resolveFileContent(relativePath: rel)
        let currentRev = fileRevisions[rel] ?? 1
        if currentContent == content {
            return (content: currentContent, revision: currentRev, didAutoMerge: false)
        }

        var mergedContent = content
        var didAutoMerge = false

        if let baseRev = baseRevision,
           baseRev < currentRev,
           let baseSnapshot = fileRevisionSnapshots[rel]?[baseRev] {
            let mergeOutcome = CollaborativeThreeWayMerger.merge(
                base: baseSnapshot,
                current: currentContent,
                incoming: content
            )
            mergedContent = mergeOutcome.merged
            didAutoMerge = mergeOutcome.didAutoMerge
        }

        guard mergedContent != currentContent else {
            return (content: currentContent, revision: currentRev, didAutoMerge: didAutoMerge)
        }

        let doc = crdtEngine.createDocument(content: mergedContent, filePath: rel, id: rel)
        crdtDocuments[rel] = doc
        fileContents[rel] = mergedContent
        let nextRev = currentRev + 1
        fileRevisions[rel] = nextRev
        recordRevisionSnapshot(relativePath: rel, revision: nextRev, content: mergedContent)
        
        writeRelativeFileToSharedRootIfPossible(relativePath: rel, content: mergedContent)
        syncBufferToOpenEditorTabIfNeeded(relativePath: rel, content: mergedContent)

        if !sharedFiles.contains(where: { $0.relativePath == rel }) {
            indexLocalWorkspaceFiles(forceDiskScan: true)
            Task { @MainActor in await AppState.shared?.refreshFileTree() }
        }
        
        let actionLabel = didAutoMerge ? "merged edit" : "edited"
        recordActivity(actorName: authorName, actorColor: authorColor, action: actionLabel, target: rel)
        return (content: mergedContent, revision: nextRev, didAutoMerge: didAutoMerge)
    }

    private func applyIncomingFileSystemEvent(_ event: [String: Any], broadcastToOtherPeers: Bool, senderUserId: String? = nil) {
        guard let op = event["op"] as? String,
              let rawPath = event["path"] as? String else { return }
        let rel = sanitizeRelativePath(rawPath)
        guard !rel.isEmpty else { return }

        let rootPath = sharedWorkspaceRootPath ?? AppState.shared?.workspaceFolder?.standardizedFileURL.path ?? ""
        guard !rootPath.isEmpty else { return }
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let targetURL = rootURL.appendingPathComponent(rel).standardizedFileURL
        guard targetURL.path.hasPrefix(rootURL.path + "/") else { return }

        switch op {
        case "mkdir":
            try? FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
            if !sharedDirectories.contains(rel) {
                sharedDirectories.append(rel)
            }
        case "write":
            let content = (event["content"] as? String) ?? ""
            try? FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? content.write(to: targetURL, atomically: true, encoding: .utf8)
            let nextRev = (fileRevisions[rel] ?? 0) + 1
            fileContents[rel] = content
            fileRevisions[rel] = nextRev
            peerBaseRevisions[rel] = nextRev
            recordRevisionSnapshot(relativePath: rel, revision: nextRev, content: content)
            syncBufferToOpenEditorTabIfNeeded(relativePath: rel, content: content)
        case "rename":
            if let rawNew = event["newPath"] as? String {
                let newRel = sanitizeRelativePath(rawNew)
                let newURL = rootURL.appendingPathComponent(newRel).standardizedFileURL
                if !newRel.isEmpty, newURL.path.hasPrefix(rootURL.path + "/") {
                    try? FileManager.default.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? FileManager.default.moveItem(at: targetURL, to: newURL)
                    if let oldVal = fileContents.removeValue(forKey: rel) {
                        fileContents[newRel] = oldVal
                    }
                    if let oldRev = fileRevisions.removeValue(forKey: rel) {
                        fileRevisions[newRel] = oldRev
                    }
                }
            }
        case "delete":
            try? FileManager.default.removeItem(at: targetURL)
            fileContents.removeValue(forKey: rel)
            fileRevisions.removeValue(forKey: rel)
            sharedDirectories.removeAll { $0 == rel || $0.hasPrefix(rel + "/") }
            sharedFiles.removeAll { $0.relativePath == rel || $0.relativePath.hasPrefix(rel + "/") }
        default:
            break
        }

        if currentSession?.isHostingLocally == true {
            indexLocalWorkspaceFiles(forceDiskScan: true)
            if broadcastToOtherPeers {
                var relay = event
                relay["type"] = "fsEvent"
                relay["path"] = rel
                broadcastHostWSMessage(relay, excludingUserId: senderUserId)
            }
        }

        Task { @MainActor in
            await AppState.shared?.refreshFileTree()
        }
    }
    
    private func syncBufferToOpenEditorTabIfNeeded(relativePath: String, content: String) {
        guard let state = AppState.shared else { return }
        let idx = state.openFiles.firstIndex(where: { normalizeRelativePath($0.path) == relativePath })
        guard let matchedIdx = idx else { return }
        guard state.openFiles[matchedIdx].content != content else { return }
        isApplyingRemoteEdit = true
        state.openFiles[matchedIdx].decompress()
        state.openFiles[matchedIdx].content = content
        state.openFiles[matchedIdx].isUnsaved = false
        if state.currentFile?.id == state.openFiles[matchedIdx].id {
            state.currentFile?.content = content
            state.currentFile?.isUnsaved = false
        }
        lastSyncedLocalFileHashes[relativePath] = content.hashValue
        isApplyingRemoteEdit = false
    }
    
    func openSharedFileInEditor(_ file: SharedWorkspaceFile) async {
        guard let state = AppState.shared else { return }
        let rel = sanitizeRelativePath(file.relativePath)
        guard !rel.isEmpty else { return }
        
        // 1. If file exists locally in shared/active workspace, open it directly
        let rootPath = sharedWorkspaceRootPath ?? state.workspaceFolder?.path
        if let wsRoot = rootPath {
            let localURL = URL(fileURLWithPath: wsRoot).appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: localURL.path) {
                await state.loadFile(url: localURL, preserveEditorMode: false)
                state.switchToMode(.code)
                await updateCursor(filePath: rel, line: 1, column: 1)
                return
            }
        }
        
        // 2. Otherwise fetch from Host, materialize into sharedWorkspaceRootPath if available, and open
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
                let rev = (json["revision"] as? Int) ?? 1
                fileRevisions[rel] = rev
                peerBaseRevisions[rel] = rev
                recordRevisionSnapshot(relativePath: rel, revision: rev, content: remoteContent)
                writeRelativeFileToSharedRootIfPossible(relativePath: rel, content: remoteContent)
            }
        }

        if let wsRoot = rootPath {
            let localURL = URL(fileURLWithPath: wsRoot).appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: localURL.path) {
                await state.loadFile(url: localURL, preserveEditorMode: false)
                state.switchToMode(.code)
                await updateCursor(filePath: rel, line: 1, column: 1)
                return
            }
        }
        
        if let existingIdx = state.openFiles.firstIndex(where: { normalizeRelativePath($0.path) == rel }) {
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
        state.switchToMode(.code)
        await updateCursor(filePath: rel, line: 1, column: 1)
    }

    func jumpToParticipant(_ participant: CollaborationSession.Participant) async {
        guard let cur = participant.cursorPosition, !cur.filePath.isEmpty else { return }
        let rel = normalizeRelativePath(cur.filePath)
        guard !rel.isEmpty else { return }
        let keepSplitAIChat = (participant.userId == Self.aiTeammateUserId && AppState.shared?.editorMode == .aiAgent)
        if let match = sharedFiles.first(where: { $0.relativePath == rel }) {
            await openSharedFileInEditor(match)
        } else {
            let dummy = SharedWorkspaceFile(
                relativePath: rel,
                name: (rel as NSString).lastPathComponent,
                language: (rel as NSString).pathExtension,
                isOpenOnHost: true
            )
            await openSharedFileInEditor(dummy)
        }
        if keepSplitAIChat {
            AppState.shared?.aiChatVisible = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        NotificationCenter.default.post(
            name: Notification.Name("JumpToLineNotification"),
            object: nil,
            userInfo: ["line": cur.line, "column": cur.column, "scrollOnly": true]
        )
    }
    
    // MARK: - Follow Mode & AI Agent Teammate (Active ONLY in Collab Mode)
    
    func toggleFollow(userId: String) {
        guard currentSession != nil else { return }
        if followingUserId == userId {
            followingUserId = nil
            lastFollowedFileRel = ""
            lastFollowedLine = 0
        } else {
            followingUserId = userId
            lastFollowedFileRel = ""
            lastFollowedLine = 0
            if let p = participants.first(where: { $0.userId == userId }) {
                Task { await jumpToParticipant(p) }
            }
        }
    }
    
    private func applyFollowModeIfNeeded() {
        guard currentSession != nil,
              let targetId = followingUserId,
              let target = participants.first(where: { $0.userId == targetId }),
              let cursor = target.cursorPosition,
              !cursor.filePath.isEmpty else { return }
        
        let rel = normalizeRelativePath(cursor.filePath)
        guard !rel.isEmpty, let state = AppState.shared else { return }
        let currentRel = state.currentFile.map { normalizeRelativePath($0.path) } ?? ""
        if currentRel != rel || state.editorMode != .code {
            lastFollowedFileRel = rel
            lastFollowedLine = cursor.line
            Task { await jumpToParticipant(target) }
        } else if lastFollowedLine != cursor.line || lastFollowedFileRel != rel {
            lastFollowedFileRel = rel
            lastFollowedLine = cursor.line
            NotificationCenter.default.post(
                name: Notification.Name("JumpToLineNotification"),
                object: nil,
                userInfo: ["line": cursor.line, "column": cursor.column, "scrollOnly": true]
            )
        }
    }
    
    func setAITeammateEnabled(_ enabled: Bool) {
        isAITeammateEnabled = enabled
        guard currentSession != nil else { return }
        if enabled {
            ensureAITeammateInParticipants()
        } else {
            participants.removeAll { $0.userId == Self.aiTeammateUserId }
            if followingUserId == Self.aiTeammateUserId {
                followingUserId = nil
            }
        }
        if currentSession?.isHostingLocally == true {
            broadcastHostParticipantsOverWS()
        }
    }

    func ensureAITeammateInParticipants() {
        guard currentSession != nil, isAITeammateEnabled else { return }
        let liveStatus: String = {
            if let tool = AgentService.shared.currentToolExecution, !tool.isEmpty {
                return tool
            }
            if AgentService.shared.isLoading {
                return AgentService.shared.agentPhase.displayText
            }
            return aiTeammateStatusText
        }()
        let fallbackCursor = aiTeammateCursor ?? currentLocalCursorPosition() ?? sharedFiles.first.map {
            CollaborationSession.CursorPosition(filePath: $0.relativePath, line: 1, column: 1)
        }
        aiTeammateCursor = fallbackCursor
        upsertParticipant(
            userId: Self.aiTeammateUserId,
            displayName: Self.aiTeammateDisplayName,
            role: "AI Agent",
            color: Self.aiTeammateColor,
            cursor: fallbackCursor,
            mouse: aiTeammateMouse,
            activeTaskTitle: TeamTaskService.shared.selectedTask?.title,
            isAIActive: aiTeammateIsWorking || AgentService.shared.isLoading,
            aiStatusText: liveStatus
        )
    }
    
    func notifyAIAgentTurnState(isActive: Bool, statusText: String? = nil) {
        // STRICT BOUNDARY: Only active when in a Collaboration session!
        guard let session = currentSession, isConnected, isAITeammateEnabled else { return }
        aiTeammateIsWorking = isActive
        if let statusText, !statusText.isEmpty {
            aiTeammateStatusText = statusText
        } else if !isActive {
            aiTeammateStatusText = "Ready in Collab"
        }
        if !isActive, var cur = aiTeammateCursor {
            cur.isTyping = false
            aiTeammateCursor = cur
        }
        ensureAITeammateInParticipants()
        if session.isHostingLocally {
            broadcastHostParticipantsOverWS()
        }
    }
    
    func notifyAIAgentActivity(
        filePath: String?,
        line: Int = 1,
        column: Int = 1,
        endLine: Int? = nil,
        isEditing: Bool = false,
        statusText: String? = nil,
        updatedContent: String? = nil
    ) {
        // STRICT BOUNDARY: Only active when in a Collaboration session!
        guard let session = currentSession, isConnected, isAITeammateEnabled else { return }
        
        var targetRel = ""
        if let filePath, !filePath.isEmpty {
            let candidate = normalizeRelativePath(filePath)
            if !candidate.hasPrefix(".microcode") && !candidate.hasPrefix(".gemini") {
                targetRel = candidate
            }
        }
        if targetRel.isEmpty, let existingRel = aiTeammateCursor?.filePath {
            targetRel = existingRel
        }
        
        let safeLine = max(1, line)
        let safeCol = max(1, column)
        let safeEndLine = endLine.map { max(safeLine, $0) }
        
        if !targetRel.isEmpty {
            let pos = CollaborationSession.CursorPosition(
                filePath: targetRel,
                line: safeLine,
                column: safeCol,
                endLine: safeEndLine,
                endColumn: safeEndLine != nil ? 80 : nil,
                isTyping: isEditing
            )
            self.aiTeammateCursor = pos
            
            let normY = min(0.86, max(0.14, 0.16 + Double((safeLine - 1) % 38) * 0.018))
            let normX = min(0.76, max(0.36, 0.42 + Double((safeLine * 7) % 25) * 0.012))
            self.aiTeammateMouse = CollaborationSession.MousePresence(
                normalizedX: normX,
                normalizedY: normY,
                surface: "editor",
                activeFile: targetRel,
                activeLine: safeLine,
                isPressing: isEditing,
                updatedAt: Date()
            )
        }
        
        self.aiTeammateIsWorking = isEditing || AgentService.shared.isLoading
        if let statusText, !statusText.isEmpty {
            self.aiTeammateStatusText = statusText
        }
        
        if isEditing {
            aiTypingResetTask?.cancel()
            aiTypingResetTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                guard !Task.isCancelled, let self,
                      self.currentSession != nil,
                      var cur = self.aiTeammateCursor,
                      cur.isTyping == true else { return }
                cur.isTyping = false
                self.aiTeammateCursor = cur
                self.ensureAITeammateInParticipants()
                if self.currentSession?.isHostingLocally == true {
                    self.broadcastHostWSMessage([
                        "type": "cursor",
                        "userId": Self.aiTeammateUserId,
                        "displayName": Self.aiTeammateDisplayName,
                        "role": "AI Agent",
                        "color": Self.aiTeammateColor,
                        "filePath": cur.filePath,
                        "line": cur.line,
                        "column": cur.column,
                        "endLine": cur.endLine ?? cur.line,
                        "endColumn": cur.endColumn ?? cur.column,
                        "isTyping": false,
                        "isAIActive": self.aiTeammateIsWorking,
                        "aiStatusText": self.aiTeammateStatusText
                    ])
                }
            }
        }
        
        upsertParticipant(
            userId: Self.aiTeammateUserId,
            displayName: Self.aiTeammateDisplayName,
            role: "AI Agent",
            color: Self.aiTeammateColor,
            cursor: self.aiTeammateCursor,
            mouse: self.aiTeammateMouse,
            activeTaskTitle: TeamTaskService.shared.selectedTask?.title,
            isAIActive: self.aiTeammateIsWorking,
            aiStatusText: self.aiTeammateStatusText
        )
        
        if let cur = self.aiTeammateCursor {
            let cursorPayload: [String: Any] = [
                "type": "cursor",
                "userId": Self.aiTeammateUserId,
                "displayName": Self.aiTeammateDisplayName,
                "role": "AI Agent",
                "color": Self.aiTeammateColor,
                "filePath": cur.filePath,
                "line": cur.line,
                "column": cur.column,
                "endLine": cur.endLine ?? cur.line,
                "endColumn": cur.endColumn ?? cur.column,
                "isTyping": cur.isTyping ?? false,
                "isAIActive": self.aiTeammateIsWorking,
                "aiStatusText": self.aiTeammateStatusText
            ]
            if session.isHostingLocally {
                broadcastHostWSMessage(cursorPayload)
            } else if isWebSocketRealtimeActive {
                sendPeerWSMessage(cursorPayload)
            }
        }
        
        if let m = self.aiTeammateMouse {
            let mousePayload: [String: Any] = [
                "type": "mouse",
                "userId": Self.aiTeammateUserId,
                "displayName": Self.aiTeammateDisplayName,
                "role": "AI Agent",
                "color": Self.aiTeammateColor,
                "x": m.normalizedX,
                "y": m.normalizedY,
                "surface": m.surface,
                "activeFile": m.activeFile ?? "",
                "activeLine": m.activeLine ?? 0,
                "isPressing": m.isPressing
            ]
            if session.isHostingLocally {
                broadcastHostWSMessage(mousePayload)
            } else if isWebSocketRealtimeActive {
                sendPeerWSMessage(mousePayload)
            }
        }
        
        if let updatedContent, !targetRel.isEmpty {
            let nextRev = (fileRevisions[targetRel] ?? 1) + 1
            fileContents[targetRel] = updatedContent
            fileRevisions[targetRel] = nextRev
            lastSyncedLocalFileHashes[targetRel] = updatedContent.hashValue
            recordRevisionSnapshot(relativePath: targetRel, revision: nextRev, content: updatedContent)
            syncBufferToOpenEditorTabIfNeeded(relativePath: targetRel, content: updatedContent)
            recordActivity(
                actorName: Self.aiTeammateDisplayName,
                actorColor: Self.aiTeammateColor,
                action: "AI edited",
                target: "\(targetRel):\(safeLine)"
            )
            if session.isHostingLocally {
                broadcastHostWSMessage([
                    "type": "fileBuffer",
                    "path": targetRel,
                    "content": updatedContent,
                    "revision": nextRev,
                    "authorId": Self.aiTeammateUserId,
                    "authorName": Self.aiTeammateDisplayName,
                    "authorColor": Self.aiTeammateColor
                ])
            } else if isWebSocketRealtimeActive {
                sendPeerWSMessage([
                    "type": "edit",
                    "path": targetRel,
                    "content": updatedContent,
                    "baseRevision": max(1, nextRev - 1),
                    "userId": Self.aiTeammateUserId,
                    "displayName": Self.aiTeammateDisplayName,
                    "color": Self.aiTeammateColor
                ])
            }
        }
        
        if session.isHostingLocally {
            broadcastHostParticipantsOverWS()
        }
    }
    
    func handleCollabChatAIMentionIfApplicable(senderId: String, senderName: String, message: String) {
        guard let session = currentSession,
              session.isHostingLocally,
              isConnected,
              isAITeammateEnabled,
              senderId != Self.aiTeammateUserId else { return }
        
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let isAIMention = lower.hasPrefix("@ai")
            || lower.hasPrefix("@agent")
            || lower.hasPrefix("/ai")
            || lower.contains("@ai ")
            || lower.contains("@agent ")
        guard isAIMention else { return }
        
        var cleanPrompt = trimmed
        for prefix in ["@agent", "@ai", "/ai"] {
            if cleanPrompt.lowercased().hasPrefix(prefix) {
                cleanPrompt = String(cleanPrompt.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: " :,-"))
                break
            }
        }
        guard !cleanPrompt.isEmpty else { return }
        
        notifyAIAgentTurnState(isActive: true, statusText: "Working on \(senderName)'s request…")
        recordActivity(
            actorName: Self.aiTeammateDisplayName,
            actorColor: Self.aiTeammateColor,
            action: "started task for \(senderName)",
            target: String(cleanPrompt.prefix(40))
        )
        
        Task { @MainActor [weak self] in
            guard let self, self.currentSession != nil else { return }
            let openFileHint = AppState.shared?.currentFile.map { " (Current file: \(self.normalizeRelativePath($0.path)))" } ?? ""
            let fullPrompt = "[Collab Session Request from teammate '\(senderName)'\(openFileHint)]: \(cleanPrompt)"
            let baselineMsgCount = AgentService.shared.messages.count
            
            await AgentService.shared.sendMessage(fullPrompt)
            
            // Wait briefly for AgentService to enter loading state
            try? await Task.sleep(nanoseconds: 250_000_000)
            while AgentService.shared.isLoading && self.currentSession != nil {
                if let toolExec = AgentService.shared.currentToolExecution, !toolExec.isEmpty {
                    self.notifyAIAgentTurnState(isActive: true, statusText: toolExec)
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            
            guard self.currentSession != nil else { return }
            let newMessages = AgentService.shared.messages.dropFirst(min(baselineMsgCount, AgentService.shared.messages.count))
            if let lastAssistant = newMessages.last(where: { $0.role == .assistant }) ?? AgentService.shared.messages.last(where: { $0.role == .assistant }) {
                let rawReply = lastAssistant.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !rawReply.isEmpty {
                    let conciseReply = rawReply.count > 700 ? (String(rawReply.prefix(700)) + "…") : rawReply
                    let aiChat = ChatMessage(
                        userId: Self.aiTeammateUserId,
                        displayName: Self.aiTeammateDisplayName,
                        userColor: Self.aiTeammateColor,
                        message: conciseReply,
                        timestamp: Date()
                    )
                    self.chatMessages.append(aiChat)
                    self.broadcastHostWSMessage([
                        "type": "chat",
                        "id": aiChat.id,
                        "userId": Self.aiTeammateUserId,
                        "displayName": Self.aiTeammateDisplayName,
                        "userColor": Self.aiTeammateColor,
                        "message": conciseReply
                    ])
                }
            }
            self.notifyAIAgentTurnState(isActive: false, statusText: "Ready in Collab")
        }
    }
    
    // MARK: - Hooks Called by AppState / Editor / Mouse Tracker / TeamTaskService

    func updateLocalMouse(
        normalizedX: Double,
        normalizedY: Double,
        surface: String,
        isPressing: Bool = false
    ) {
        guard let session = currentSession else { return }
        let clampedX = max(0, min(1, normalizedX))
        let clampedY = max(0, min(1, normalizedY))
        let activeFile = AppState.shared?.currentFile.map { normalizeRelativePath($0.path) }
        let activeLine = localEditorCursor?.line

        let presence = CollaborationSession.MousePresence(
            normalizedX: clampedX,
            normalizedY: clampedY,
            surface: surface,
            activeFile: activeFile,
            activeLine: activeLine,
            isPressing: isPressing,
            updatedAt: Date()
        )
        self.localMousePresence = presence

        let now = ProcessInfo.processInfo.systemUptime
        if !isPressing && (now - lastMouseSentAt) < 0.034 {
            return
        }
        lastMouseSentAt = now

        if let idx = participants.firstIndex(where: { $0.userId == localUserId }) {
            participants[idx].mousePresence = presence
            participants[idx].lastSeenAt = Date()
        }

        let payload: [String: Any] = [
            "type": "mouse",
            "userId": localUserId,
            "displayName": localDisplayName,
            "role": session.isHostingLocally ? "Host" : localRole,
            "color": localColor,
            "x": clampedX,
            "y": clampedY,
            "surface": surface,
            "activeFile": activeFile ?? "",
            "activeLine": activeLine ?? 0,
            "isPressing": isPressing
        ]

        if session.isHostingLocally {
            broadcastHostWSMessage(payload, excludingUserId: localUserId)
        } else if isWebSocketRealtimeActive {
            sendPeerWSMessage(payload)
        }
    }

    func updateLocalEditorSelection(
        filePath: String,
        line: Int,
        column: Int,
        endLine: Int? = nil,
        endColumn: Int? = nil,
        isTyping: Bool = false
    ) {
        guard let session = currentSession else { return }
        let rel = normalizeRelativePath(filePath)
        guard !rel.isEmpty else { return }

        let pos = CollaborationSession.CursorPosition(
            filePath: rel,
            line: max(1, line),
            column: max(1, column),
            endLine: endLine.map { max(1, $0) },
            endColumn: endColumn.map { max(1, $0) },
            isTyping: isTyping
        )
        self.localEditorCursor = pos

        if isTyping {
            typingResetTask?.cancel()
            typingResetTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled, let self,
                      var cur = self.localEditorCursor, cur.isTyping == true else { return }
                cur.isTyping = false
                self.localEditorCursor = cur
                self.updateLocalEditorSelection(
                    filePath: cur.filePath,
                    line: cur.line,
                    column: cur.column,
                    endLine: cur.endLine,
                    endColumn: cur.endColumn,
                    isTyping: false
                )
            }
        }

        upsertParticipant(
            userId: localUserId,
            displayName: localDisplayName,
            role: session.isHostingLocally ? "Host" : localRole,
            color: localColor,
            cursor: pos
        )

        let now = ProcessInfo.processInfo.systemUptime
        if !isTyping && (now - lastCursorSentAt) < 0.030 {
            return
        }
        lastCursorSentAt = now

        let payload: [String: Any] = [
            "type": "cursor",
            "userId": localUserId,
            "displayName": localDisplayName,
            "role": session.isHostingLocally ? "Host" : localRole,
            "color": localColor,
            "filePath": rel,
            "line": pos.line,
            "column": pos.column,
            "endLine": pos.endLine ?? pos.line,
            "endColumn": pos.endColumn ?? pos.column,
            "isTyping": isTyping
        ]

        if session.isHostingLocally {
            broadcastHostWSMessage(payload, excludingUserId: localUserId)
        } else if isWebSocketRealtimeActive {
            sendPeerWSMessage(payload)
        }
    }

    func notifyLocalFileSystemEvent(op: String, path: String, newPath: String? = nil, content: String? = nil) {
        guard let session = currentSession, !isApplyingRemoteEdit else { return }
        let rel = normalizeRelativePath(path)
        guard !rel.isEmpty else { return }

        var payload: [String: Any] = [
            "type": "fsEvent",
            "op": op,
            "path": rel,
            "userId": localUserId,
            "displayName": localDisplayName
        ]
        if let newPath {
            payload["newPath"] = normalizeRelativePath(newPath)
        }
        if let content {
            payload["content"] = content
        }

        if session.isHostingLocally {
            indexLocalWorkspaceFiles(forceDiskScan: true)
            broadcastHostWSMessage(payload, excludingUserId: localUserId)
        } else {
            if isWebSocketRealtimeActive {
                sendPeerWSMessage(payload)
            } else if let url = URL(string: "\(session.remoteEndpoint)/api/collab/fs-event") {
                Task {
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
                    _ = try? await URLSession.shared.data(for: req)
                }
            }
        }
    }
    
    func notifyLocalFileEdited(path: String, content: String) {
        guard let session = currentSession, !isApplyingRemoteEdit else { return }
        let rel = normalizeRelativePath(path)
        guard !rel.isEmpty else { return }
        let hash = content.hashValue
        guard lastSyncedLocalFileHashes[rel] != hash else { return }
        lastSyncedLocalFileHashes[rel] = hash
        
        if session.isHostingLocally {
            if let prev = fileContents[rel], fileRevisionSnapshots[rel] == nil {
                let initialRev = fileRevisions[rel] ?? 1
                fileRevisions[rel] = initialRev
                recordRevisionSnapshot(relativePath: rel, revision: initialRev, content: prev)
            }
            let nextRev = (fileRevisions[rel] ?? 1) + 1
            fileContents[rel] = content
            fileRevisions[rel] = nextRev
            recordRevisionSnapshot(relativePath: rel, revision: nextRev, content: content)
            writeRelativeFileToSharedRootIfPossible(relativePath: rel, content: content)
            broadcastHostWSMessage([
                "type": "fileBuffer",
                "path": rel,
                "content": content,
                "revision": nextRev,
                "authorId": localUserId,
                "authorName": localDisplayName,
                "authorColor": localColor
            ], excludingUserId: localUserId)
            return
        }

        let baseRev = peerBaseRevisions[rel] ?? fileRevisions[rel] ?? 1
        fileContents[rel] = content
        writeRelativeFileToSharedRootIfPossible(relativePath: rel, content: content)

        if isWebSocketRealtimeActive {
            sendPeerWSMessage([
                "type": "edit",
                "path": rel,
                "content": content,
                "baseRevision": baseRev,
                "userId": localUserId,
                "displayName": localDisplayName,
                "color": localColor
            ])
            return
        }
        
        if let url = URL(string: "\(session.remoteEndpoint)/api/collab/edit") {
            Task { @MainActor in
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = [
                    "path": rel,
                    "content": content,
                    "baseRevision": baseRev,
                    "userId": localUserId,
                    "displayName": localDisplayName,
                    "color": localColor
                ]
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                if let (respData, _) = try? await URLSession.shared.data(for: req),
                   let respJSON = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] {
                    if let newRev = respJSON["revision"] as? Int {
                        let authoritativeContent = (respJSON["content"] as? String) ?? content
                        self.recordRevisionSnapshot(relativePath: rel, revision: newRev, content: authoritativeContent)
                        self.peerBaseRevisions[rel] = newRev
                        self.fileRevisions[rel] = newRev
                    }
                    if let didMerge = respJSON["merged"] as? Bool,
                       didMerge,
                       let mergedContent = respJSON["content"] as? String,
                       self.fileContents[rel] == content {
                        self.fileContents[rel] = mergedContent
                        self.writeRelativeFileToSharedRootIfPossible(relativePath: rel, content: mergedContent)
                        self.syncBufferToOpenEditorTabIfNeeded(relativePath: rel, content: mergedContent)
                    }
                }
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
                self.indexLocalWorkspaceFiles(forceDiskScan: true)
                let cutoff = Date().addingTimeInterval(-15)
                var didChangeOnline = false
                for i in 0..<self.participants.count {
                    if self.participants[i].userId != self.localUserId
                        && self.participants[i].userId != Self.aiTeammateUserId
                        && self.participants[i].lastSeenAt < cutoff
                        && self.participants[i].isOnline {
                        self.participants[i].isOnline = false
                        didChangeOnline = true
                    }
                }
                if didChangeOnline {
                    self.broadcastHostParticipantsOverWS()
                    NotificationCenter.default.post(name: Self.remotePresenceDidChangeNotification, object: nil)
                }
            }
        }
    }
    
    private func startPeerSyncLoop() {
        peerSyncTimer?.invalidate()
        peerSyncTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
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
                "column": cur.column,
                "endLine": cur.endLine ?? cur.line,
                "endColumn": cur.endColumn ?? cur.column,
                "isTyping": cur.isTyping ?? false
            ]
        }
        if let m = localMousePresence {
            body["mouse"] = [
                "x": m.normalizedX,
                "y": m.normalizedY,
                "surface": m.surface,
                "activeFile": m.activeFile ?? "",
                "activeLine": m.activeLine ?? 0,
                "isPressing": m.isPressing
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
            if !isWebSocketRealtimeActive {
                connectionStatus = .reconnecting
            }
        }
    }
    
    // MARK: - Public Cursor, TextChange & Chat API
    
    func updateCursor(filePath: String, line: Int, column: Int) async {
        let rel = normalizeRelativePath(filePath)
        if let existing = localEditorCursor,
           existing.filePath == rel,
           line == 1 && column == 1 && (existing.line != 1 || existing.column != 1) {
            updateLocalEditorSelection(
                filePath: rel,
                line: existing.line,
                column: existing.column,
                endLine: existing.endLine,
                endColumn: existing.endColumn,
                isTyping: false
            )
            return
        }
        updateLocalEditorSelection(filePath: rel, line: line, column: column, isTyping: false)
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
            broadcastHostWSMessage([
                "type": "chat",
                "id": msg.id,
                "userId": localUserId,
                "displayName": localDisplayName,
                "userColor": localColor,
                "message": clean
            ])
            handleCollabChatAIMentionIfApplicable(senderId: localUserId, senderName: localDisplayName, message: clean)
        } else if isWebSocketRealtimeActive {
            sendPeerWSMessage([
                "type": "chat",
                "userId": localUserId,
                "displayName": localDisplayName,
                "color": localColor,
                "message": clean
            ])
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
        
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cloudflaredPaths = [
            "/opt/homebrew/bin/cloudflared",
            "/usr/local/bin/cloudflared",
            "/usr/bin/cloudflared",
            "\(home)/Library/Application Support/MicroCode/bin/cloudflared"
        ]
        if let cfPath = cloudflaredPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let reap = Process()
            reap.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            reap.arguments = ["-f", "cloudflared tunnel --url http://127\\.0\\.0\\.1:\(port)($| )"]
            reap.standardOutput = FileHandle.nullDevice
            reap.standardError = FileHandle.nullDevice
            try? reap.run()
            reap.waitUntilExit()

            launchTunnelProcess(
                executable: cfPath,
                arguments: ["tunnel", "--url", "http://127.0.0.1:\(port)", "--no-autoupdate"],
                fallbackPortOnEarlyExit: port
            )
        } else {
            launchSSHTunnelFallback(port: port)
        }
    }
    
    func stopOnlineTunnel() {
        tunnelOutputPipe?.fileHandleForReading.readabilityHandler = nil
        tunnelOutputPipe = nil
        let proc = tunnelProcess
        tunnelProcess = nil
        if let proc, proc.isRunning {
            proc.terminate()
        }
        publicTunnelURL = nil
        tunnelStatus = .idle
        regenerateQRCode()
    }

    private func launchSSHTunnelFallback(port: Int) {
        let knownHostsURL = PhoneCompanionService.ensurePinnedKnownHostsFile()
        launchTunnelProcess(
            executable: "/usr/bin/ssh",
            arguments: [
                "-o", "StrictHostKeyChecking=yes",
                "-o", "UserKnownHostsFile=\(knownHostsURL.path)",
                "-o", "ServerAliveInterval=30",
                "-o", "ExitOnForwardFailure=yes",
                "-R", "80:127.0.0.1:\(port)",
                "nokey@localhost.run"
            ],
            fallbackPortOnEarlyExit: nil,
            isSSHFallback: true
        )
    }
    
    private func launchTunnelProcess(
        executable: String,
        arguments: [String],
        fallbackPortOnEarlyExit: Int? = nil,
        isSSHFallback: Bool = false
    ) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        if isSSHFallback {
            proc.standardInput = Pipe()
        }
        self.tunnelOutputPipe = pipe
        self.tunnelProcess = proc
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let line = String(decoding: data, as: UTF8.self)
            guard !line.isEmpty else { return }
            let pattern = #"https://[a-zA-Z0-9.-]+\.(?:trycloudflare\.com|lhr\.life)"#
            if let range = line.range(of: pattern, options: .regularExpression) {
                let matched = String(line[range])
                Task { @MainActor [weak self] in
                    guard let self, self.tunnelProcess === proc else { return }
                    if self.publicTunnelURL != matched {
                        self.publicTunnelURL = matched
                        self.tunnelStatus = .active(matched)
                        self.regenerateQRCode()
                    }
                }
            }
        }

        proc.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                guard let self, self.tunnelProcess === proc else { return }
                self.tunnelOutputPipe = nil
                self.tunnelProcess = nil

                if self.tunnelStatus == .starting {
                    if let fallbackPort = fallbackPortOnEarlyExit {
                        self.launchSSHTunnelFallback(port: fallbackPort)
                    } else {
                        self.tunnelStatus = .failed("Could not establish online collaboration tunnel. Check your internet connection or use LAN / P2P mode.")
                    }
                } else if self.transportMode == .online {
                    self.publicTunnelURL = nil
                    self.tunnelStatus = .idle
                    self.regenerateQRCode()
                }
            }
        }

        do {
            try proc.run()
        } catch {
            self.tunnelOutputPipe = nil
            self.tunnelProcess = nil
            if let fallbackPort = fallbackPortOnEarlyExit {
                launchSSHTunnelFallback(port: fallbackPort)
            } else {
                tunnelStatus = .failed(error.localizedDescription)
            }
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
    
    // MARK: - Collaborator Lookup Helpers
    
    func onlineParticipants() -> [CollaborationSession.Participant] {
        guard currentSession != nil else { return [] }
        return participants.filter(\.isOnline)
    }
    
    func remoteOnlineParticipants() -> [CollaborationSession.Participant] {
        let myId = localUserId
        return onlineParticipants().filter { $0.userId != myId }
    }
    
    func remoteCollaborators(inFilePath rawPath: String) -> [CollaborationSession.Participant] {
        let targetRel = normalizeRelativePath(rawPath)
        guard !targetRel.isEmpty else { return [] }
        return remoteOnlineParticipants().filter { peer in
            guard let peerPath = peer.cursorPosition?.filePath, !peerPath.isEmpty else {
                if let mouseFile = peer.mousePresence?.activeFile, !mouseFile.isEmpty {
                    return normalizeRelativePath(mouseFile) == targetRel
                }
                return false
            }
            return normalizeRelativePath(peerPath) == targetRel
        }
    }
    
    func remoteCollaborators(underDirectoryPath rawDirPath: String) -> [CollaborationSession.Participant] {
        let dirRel = normalizeRelativePath(rawDirPath).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !dirRel.isEmpty else { return [] }
        let prefix = dirRel + "/"
        return remoteOnlineParticipants().filter { peer in
            if let peerPath = peer.cursorPosition?.filePath, normalizeRelativePath(peerPath).hasPrefix(prefix) {
                return true
            }
            if let mouseFile = peer.mousePresence?.activeFile, normalizeRelativePath(mouseFile).hasPrefix(prefix) {
                return true
            }
            return false
        }
    }
    
    // MARK: - Helpers
    
    private func currentLocalCursorPosition() -> CollaborationSession.CursorPosition? {
        guard let file = AppState.shared?.currentFile else { return localEditorCursor }
        let rel = normalizeRelativePath(file.path)
        if let tracked = localEditorCursor, tracked.filePath == rel {
            return tracked
        }
        return CollaborationSession.CursorPosition(
            filePath: rel,
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
              --bg: #0d0f14;
              --panel: #13161d;
              --card: #1a1e28;
              --border: rgba(255,255,255,0.08);
              --text: #e5e7eb;
              --secondary: #9ca3af;
              --muted: #6b7280;
              --accent: #3b82f6;
              --ai: #a855f7;
              --green: #10b981;
              --mono: ui-monospace, "SF Mono", "JetBrains Mono", Menlo, Monaco, Consolas, monospace;
              --sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, sans-serif;
              --line-h: 20px;
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
              position: relative;
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
              z-index: 20;
            }
            .brand { display: flex; align-items: center; gap: 10px; font-size: 13px; font-weight: 600; }
            .badge {
              font-family: var(--mono);
              font-size: 10.5px;
              padding: 2px 7px;
              border-radius: 4px;
              background: rgba(255,255,255,0.06);
              border: 1px solid var(--border);
              color: var(--secondary);
            }
            .layout {
              flex: 1;
              display: grid;
              grid-template-columns: 276px 1fr 315px;
              min-height: 0;
              position: relative;
            }
            @media (max-width: 960px) {
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
              padding: 9px 12px;
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
              gap: 2px;
            }
            .file-list { flex: 1; }
            .folder-row {
              padding: 5px 8px;
              border-radius: 5px;
              font-size: 12px;
              font-weight: 600;
              cursor: pointer;
              display: flex;
              align-items: center;
              gap: 7px;
              color: #d1d5db;
              user-select: none;
            }
            .folder-row:hover { background: rgba(255,255,255,0.045); }
            .file-row {
              padding: 5px 8px;
              border-radius: 5px;
              font-size: 12px;
              cursor: pointer;
              display: flex;
              align-items: center;
              justify-content: space-between;
              gap: 7px;
              color: var(--secondary);
            }
            .file-row:hover {
              background: rgba(255,255,255,0.04);
              color: var(--text);
            }
            .file-row.active {
              background: rgba(59,130,246,0.16);
              color: #fff;
              font-weight: 500;
            }
            .file-item-left {
              display: flex;
              align-items: center;
              gap: 7px;
              min-width: 0;
              flex: 1;
            }
            .file-icon-wrap {
              width: 15px;
              height: 15px;
              display: inline-flex;
              align-items: center;
              justify-content: center;
              flex-shrink: 0;
            }
            .editor-pane {
              display: flex;
              flex-direction: column;
              min-height: 0;
              background: var(--bg);
              position: relative;
              overflow: hidden;
            }
            .editor-bar {
              height: 38px;
              padding: 0 14px;
              border-bottom: 1px solid var(--border);
              display: flex;
              align-items: center;
              justify-content: space-between;
              font-family: var(--mono);
              font-size: 11.5px;
              color: var(--secondary);
              gap: 10px;
              background: #11141b;
              flex-shrink: 0;
            }
            .editor-workspace {
              flex: 1;
              display: flex;
              min-height: 0;
              position: relative;
              overflow: hidden;
              background: var(--bg);
            }
            .line-gutter {
              width: 52px;
              padding: 14px 8px 14px 0;
              background: #10131a;
              border-right: 1px solid rgba(255,255,255,0.06);
              font-family: var(--mono);
              font-size: 11.5px;
              line-height: var(--line-h);
              color: #4b5563;
              text-align: right;
              user-select: none;
              overflow: hidden;
              flex-shrink: 0;
            }
            .gutter-line {
              height: var(--line-h);
              padding-right: 4px;
              display: flex;
              align-items: center;
              justify-content: flex-end;
              gap: 4px;
            }
            .code-stack {
              flex: 1;
              position: relative;
              min-width: 0;
              min-height: 0;
              overflow: hidden;
            }
            #codeBackdrop {
              position: absolute;
              inset: 0;
              overflow: hidden;
              pointer-events: none;
              z-index: 1;
            }
            #editorCollabOverlay {
              position: absolute;
              top: 0;
              left: 0;
              right: 0;
              pointer-events: none;
              z-index: 2;
            }
            .collab-line-band {
              position: absolute;
              left: 0;
              right: 0;
              pointer-events: none;
              border-left: 2.5px solid #3b82f6;
              transition: top 80ms linear, height 80ms linear;
            }
            .collab-line-tag {
              position: absolute;
              right: 14px;
              top: 1px;
              padding: 1px 7px;
              border-radius: 4px;
              font-family: var(--mono);
              font-size: 10px;
              font-weight: 600;
              color: #fff;
              white-space: nowrap;
              box-shadow: 0 2px 6px rgba(0,0,0,0.45);
            }
            pre#codeHighlight {
              margin: 0;
              padding: 14px 16px;
              font-family: var(--mono);
              font-size: 12.5px;
              line-height: var(--line-h);
              tab-size: 2;
              white-space: pre;
              word-wrap: normal;
              color: var(--text);
              min-height: 100%;
              position: relative;
              z-index: 3;
            }
            textarea#codeArea {
              position: absolute;
              inset: 0;
              width: 100%;
              height: 100%;
              background: transparent;
              color: transparent;
              caret-color: #f8fafc;
              border: none;
              outline: none;
              padding: 14px 16px;
              font-family: var(--mono);
              font-size: 12.5px;
              line-height: var(--line-h);
              tab-size: 2;
              white-space: pre;
              word-wrap: normal;
              resize: none;
              overflow: auto;
              z-index: 4;
            }
            textarea#codeArea::selection {
              background: rgba(59,130,246,0.32);
              color: transparent;
            }
            /* Syntax Color Highlighting Palette (Xcode / VS Code Dark) */
            .tok-comment { color: #6b7280; font-style: italic; }
            .tok-string  { color: #fcd34d; }
            .tok-kw      { color: #c084fc; font-weight: 500; }
            .tok-type    { color: #2dd4bf; }
            .tok-comp    { color: #34d399; font-weight: 500; }
            .tok-tag     { color: #38bdf8; }
            .tok-attr    { color: #93c5fd; }
            .tok-fn      { color: #60a5fa; }
            .tok-num     { color: #fb923c; }
            .tok-op      { color: #f472b6; }
            .btn {
              background: rgba(255,255,255,0.07);
              color: var(--text);
              border: 1px solid var(--border);
              border-radius: 5px;
              padding: 4px 10px;
              font-size: 11.5px;
              cursor: pointer;
              display: inline-flex;
              align-items: center;
              gap: 4px;
            }
            .btn:hover { background: rgba(255,255,255,0.12); }
            .btn-primary {
              background: #2563eb;
              border-color: #3b82f6;
              color: #fff;
            }
            .btn-ai {
              background: rgba(168,85,247,0.18);
              border-color: rgba(168,85,247,0.45);
              color: #e9d5ff;
              font-weight: 600;
            }
            .btn-ai:hover { background: rgba(168,85,247,0.28); }
            .peer-row {
              padding: 7px 9px;
              border-radius: 6px;
              background: rgba(255,255,255,0.025);
              border: 1px solid rgba(255,255,255,0.05);
              display: flex;
              align-items: center;
              gap: 8px;
              font-size: 12px;
              cursor: pointer;
            }
            .peer-row:hover { background: rgba(255,255,255,0.06); }
            .peer-row.ai-peer {
              background: rgba(168,85,247,0.09);
              border-color: rgba(168,85,247,0.28);
            }
            .peer-row.following {
              border-color: rgba(168,85,247,0.7);
              box-shadow: 0 0 0 1px rgba(168,85,247,0.28);
            }
            .follow-btn {
              font-size: 10px;
              font-weight: 600;
              padding: 3px 7px;
              border-radius: 4px;
              border: 1px solid rgba(255,255,255,0.14);
              background: rgba(255,255,255,0.06);
              color: #e5e7eb;
              cursor: pointer;
              flex-shrink: 0;
            }
            .follow-btn.active {
              background: #a855f7;
              border-color: #c084fc;
              color: #fff;
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
              gap: 7px;
              font-size: 12px;
            }
            .chat-msg-card {
              padding: 6px 8px;
              border-radius: 6px;
              background: rgba(255,255,255,0.025);
              line-height: 1.42;
              word-break: break-word;
            }
            .chat-msg-card.ai-msg {
              background: rgba(168,85,247,0.11);
              border: 1px solid rgba(168,85,247,0.26);
            }
            .chat-input-row {
              padding: 8px;
              border-top: 1px solid var(--border);
              display: flex;
              gap: 5px;
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
            #cursorLayer {
              position: fixed;
              inset: 0;
              pointer-events: none;
              z-index: 9999;
              overflow: hidden;
            }
            .remote-cursor {
              position: absolute;
              left: 0;
              top: 0;
              transition: transform 65ms linear;
              will-change: transform;
              display: flex;
              flex-direction: column;
              align-items: flex-start;
              filter: drop-shadow(0 2px 6px rgba(0,0,0,0.55));
            }
            .cursor-pill {
              margin-left: 11px;
              margin-top: -2px;
              padding: 2px 7px;
              border-radius: 999px;
              font-size: 10.5px;
              font-weight: 600;
              color: #fff;
              white-space: nowrap;
              display: flex;
              align-items: center;
              gap: 5px;
            }
          </style>
        </head>
        <body>
          <div class="topbar">
            <div class="brand">
              <span class="dot" id="rtDot" style="background:var(--green)"></span>
              <span id="wsTitle">MicroCode · \#(wsName)</span>
              <span class="badge" id="roomBadge">ROOM \#(code)</span>
              <span class="badge" id="wsStatusBadge">LIVE</span>
            </div>
            <div style="display:flex;align-items:center;gap:8px">
              <span id="followBanner" style="display:none;align-items:center;gap:6px;padding:3px 9px;border-radius:999px;background:rgba(168,85,247,0.18);border:1px solid rgba(168,85,247,0.45);font-size:11px;color:#e9d5ff"></span>
              <input class="txt" id="nameInput" style="width:140px" placeholder="Your name" onchange="saveName()">
              <span class="badge" id="peerCountBadge">1 online</span>
            </div>
          </div>
          <div class="layout" id="workspaceArea">
            <div class="sidebar-left">
              <div class="section-hdr">
                <span>WORKSPACE FOLDERS & FILES</span>
                <span id="fileCountLabel">0</span>
              </div>
              <div class="file-list" id="fileList"></div>
              <div class="section-hdr" style="border-top:1px solid var(--border)">
                <span>SHARED TEAM TASKS</span>
                <button class="btn" onclick="promptNewTask()">+ Task</button>
              </div>
              <div class="task-list" id="taskList" style="max-height:34%"></div>
            </div>
            <div class="editor-pane">
              <div class="editor-bar">
                <div style="display:flex;align-items:center;gap:7px;min-width:0;flex:1">
                  <span id="activeFileIcon" class="file-icon-wrap"></span>
                  <span id="activeFileName" style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--text);font-weight:500">Select a workspace file to view or co-edit</span>
                </div>
                <div style="display:flex;align-items:center;gap:8px;flex-shrink:0">
                  <span id="activeEditorsIndicator" style="font-size:10.5px"></span>
                  <button class="btn btn-primary" onclick="pushEdit()">Sync</button>
                </div>
              </div>
              <div class="editor-workspace">
                <div class="line-gutter" id="lineGutter">1</div>
                <div class="code-stack">
                  <div id="codeBackdrop">
                    <div id="editorCollabOverlay"></div>
                    <pre id="codeHighlight"><code id="codeHighlightContent"></code></pre>
                  </div>
                  <textarea id="codeArea" spellcheck="false" autocomplete="off" autocapitalize="off" placeholder="Select a file from the left folder tree..."></textarea>
                </div>
              </div>
            </div>
            <div class="sidebar-right">
              <div class="section-hdr">
                <span>LIVE COLLABORATORS</span>
                <button class="btn btn-ai" style="padding:2px 7px;font-size:10px" onclick="followAITeammate()">✦ Follow AI</button>
              </div>
              <div class="peer-list" id="peerList" style="max-height:245px"></div>
              <div class="chat-box">
                <div class="section-hdr">
                  <span>SESSION CHAT</span>
                  <button class="btn btn-ai" style="padding:1px 6px;font-size:9.5px" onclick="prefillAIChat()">Ask @ai</button>
                </div>
                <div class="chat-msgs" id="chatMsgs"></div>
                <div class="chat-input-row">
                  <input class="txt" id="chatInput" placeholder="Message team or @ai to code..." onkeydown="if(event.key==='Enter')sendChat()">
                  <button class="btn btn-primary" onclick="sendChat()">Send</button>
                </div>
              </div>
            </div>
          </div>
          <div id="cursorLayer"></div>
          <script>
            const ROOM_CODE = "\#(code)";
            const AI_USER_ID = "ai-agent-teammate";
            let userId = localStorage.getItem("mc_collab_uid") || ("web-" + Math.random().toString(36).slice(2, 8));
            localStorage.setItem("mc_collab_uid", userId);
            let displayName = localStorage.getItem("mc_collab_name") || ("Teammate-" + userId.slice(-4));
            let myColor = localStorage.getItem("mc_collab_color") || "#10B981";
            document.getElementById("nameInput").value = displayName;

            let activeFile = "";
            let isTyping = false;
            let followingPeerId = null;
            let lastFollowedState = "";
            const fileRevisions = {};
            const collapsedFolders = new Set();
            let cachedFiles = [];
            let cachedDirs = [];
            let cachedPeers = [];
            let cachedChats = [];
            let ws = null;
            let lastMouseSent = 0;
            let localMouse = { x: -100, y: -100, visible: false };

            function escapeHtml(s) {
              return String(s || "").replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
            }

            // Authentic Vector SVG Icons for Folders & Programming Languages
            function getFolderIconSVG(name, isClosed) {
              const lower = String(name || "").toLowerCase();
              let color = "#60a5fa";
              if (lower === "src" || lower === "app" || lower === "lib") color = "#38bdf8";
              else if (lower.includes("component") || lower === "views" || lower === "ui") color = "#a855f7";
              else if (lower === "public" || lower === "assets" || lower === "uploads" || lower === "media") color = "#10b981";
              else if (lower === "services" || lower === "api" || lower === "server" || lower === "backend") color = "#f59e0b";
              if (isClosed) {
                return `<svg width="15" height="15" viewBox="0 0 16 16" fill="none"><path d="M1.5 3.5C1.5 2.67 2.17 2 3 2H6.2L7.7 3.5H13C13.83 3.5 14.5 4.17 14.5 5V12.5C14.5 13.33 13.83 14 13 14H3C2.17 14 1.5 13.33 1.5 12.5V3.5Z" fill="${color}" fill-opacity="0.88"/></svg>`;
              }
              return `<svg width="15" height="15" viewBox="0 0 16 16" fill="none"><path d="M1.5 3.5C1.5 2.67 2.17 2 3 2H6.2L7.7 3.5H13C13.83 3.5 14.5 4.17 14.5 5V6H2.6L1.5 12.2V3.5Z" fill="${color}"/><path d="M2.3 6.5H14.8L13.6 13.2C13.5 13.68 13.08 14 12.6 14H2.4C1.78 14 1.32 13.42 1.45 12.82L2.3 6.5Z" fill="${color}" fill-opacity="0.72"/></svg>`;
            }

            function getFileIconSVG(fileName) {
              const lower = String(fileName || "").toLowerCase();
              const ext = lower.includes(".") ? lower.split(".").pop() : "";
              if (ext === "tsx" || ext === "jsx") {
                return `<svg width="15" height="15" viewBox="0 0 16 16" fill="none"><circle cx="8" cy="8" r="1.5" fill="#61DAFB"/><ellipse cx="8" cy="8" rx="6.5" ry="2.5" stroke="#61DAFB" stroke-width="1.2"/><ellipse cx="8" cy="8" rx="6.5" ry="2.5" transform="rotate(60 8 8)" stroke="#61DAFB" stroke-width="1.2"/><ellipse cx="8" cy="8" rx="6.5" ry="2.5" transform="rotate(120 8 8)" stroke="#61DAFB" stroke-width="1.2"/></svg>`;
              }
              if (ext === "ts") {
                return `<svg width="15" height="15" viewBox="0 0 16 16" fill="none"><rect x="1.5" y="1.5" width="13" height="13" rx="2.5" fill="#3178C6"/><text x="8" y="11.2" text-anchor="middle" fill="#fff" font-size="7.5" font-weight="800" font-family="sans-serif">TS</text></svg>`;
              }
              if (ext === "js" || ext === "mjs" || ext === "cjs") {
                return `<svg width="15" height="15" viewBox="0 0 16 16" fill="none"><rect x="1.5" y="1.5" width="13" height="13" rx="2.5" fill="#F7DF1E"/><text x="8" y="11.3" text-anchor="middle" fill="#111" font-size="7.5" font-weight="800" font-family="sans-serif">JS</text></svg>`;
              }
              if (ext === "css" || ext === "scss" || ext === "less") {
                return `<svg width="15" height="15" viewBox="0 0 16 16" fill="none"><rect x="1.5" y="1.5" width="13" height="13" rx="2.5" fill="#38BDF8"/><text x="8" y="11" text-anchor="middle" fill="#0f172a" font-size="7.2" font-weight="800" font-family="sans-serif">#</text></svg>`;
              }
              if (ext === "html" || ext === "htm") {
                return `<svg width="15" height="15" viewBox="0 0 16 16" fill="none"><path d="M2.5 1.5H13.5L12.5 12.2L8 14.2L3.5 12.2L2.5 1.5Z" fill="#E34F26"/><path d="M5.2 5.2H10.8L10.4 9.8L8 10.6L5.6 9.8" stroke="#fff" stroke-width="1.2" stroke-linecap="round"/></svg>`;
              }
              if (ext === "json") {
                return `<svg width="15" height="15" viewBox="0 0 16 16" fill="none"><rect x="1.5" y="1.5" width="13" height="13" rx="2.5" fill="#F59E0B" fill-opacity="0.18" stroke="#F59E0B" stroke-width="1.2"/><text x="8" y="10.8" text-anchor="middle" fill="#FBBF24" font-size="8" font-weight="700" font-family="monospace">{}</text></svg>`;
              }
              if (ext === "swift") {
                return `<svg width="15" height="15" viewBox="0 0 16 16" fill="none"><rect x="1.5" y="1.5" width="13" height="13" rx="3" fill="#F05138"/><path d="M11.2 4.3C9.6 5.6 7.4 7.1 5 5.2C6.2 6.8 7.6 7.8 6.4 8.2C5.2 7.4 4.1 6.4 3.5 5.6C4.3 7.5 6.1 9.2 8.1 9.6C6.9 10.3 5.2 10.2 3.8 9.5C5.4 11.2 8.4 11.7 10.5 10.4C11.6 9.7 12.3 8.1 11.2 4.3Z" fill="#fff"/></svg>`;
              }
              if (ext === "py") {
                return `<svg width="15" height="15" viewBox="0 0 16 16" fill="none"><rect x="2" y="2" width="12" height="6" rx="2" fill="#3776AB"/><rect x="2" y="8" width="12" height="6" rx="2" fill="#FFD43B"/></svg>`;
              }
              if (ext === "rs") {
                return `<svg width="15" height="15" viewBox="0 0 16 16" fill="none"><circle cx="8" cy="8" r="5.5" stroke="#FB923C" stroke-width="1.6" stroke-dasharray="2 1.2"/><text x="8" y="10.5" text-anchor="middle" fill="#FDBA74" font-size="6.8" font-weight="800" font-family="sans-serif">RS</text></svg>`;
              }
              if (ext === "md" || ext === "markdown") {
                return `<svg width="15" height="15" viewBox="0 0 16 16" fill="none"><rect x="1.5" y="2.5" width="13" height="11" rx="2" stroke="#60A5FA" stroke-width="1.2"/><text x="8" y="10.4" text-anchor="middle" fill="#60A5FA" font-size="7" font-weight="800" font-family="sans-serif">M↓</text></svg>`;
              }
              if (["png","jpg","jpeg","gif","svg","webp","ico"].includes(ext)) {
                return `<svg width="15" height="15" viewBox="0 0 16 16" fill="none"><rect x="2" y="2.5" width="12" height="11" rx="2" stroke="#34D399" stroke-width="1.2"/><circle cx="5.5" cy="6" r="1.2" fill="#34D399"/><path d="M3 12L6.5 8.5L9 11L11 9L13 12H3Z" fill="#34D399" fill-opacity="0.7"/></svg>`;
              }
              if (["mp3","wav","ogg","m4a"].includes(ext)) {
                return `<svg width="15" height="15" viewBox="0 0 16 16" fill="none"><path d="M6 11.5V3.5L12.5 2.5V10.5" stroke="#C084FC" stroke-width="1.3"/><circle cx="4.5" cy="11.5" r="1.7" fill="#C084FC"/><circle cx="11" cy="10.5" r="1.7" fill="#C084FC"/></svg>`;
              }
              return `<svg width="15" height="15" viewBox="0 0 16 16" fill="none"><path d="M5.5 5L2.5 8L5.5 11M10.5 5L13.5 8L10.5 11" stroke="#94A3B8" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
            }

            // Single-Pass Fast Syntax Color Highlighter (Zero HTML Corruption, Exact Textarea Alignment)
            const SYNTAX_TOKEN_RE = /(\/\/[^\n]*|\/\*[\s\S]*?\*\/|<!--[\s\S]*?-->)|("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`)|(<\/?[A-Z][A-Za-z0-9_.]*)|(<\/?[a-z][A-Za-z0-9_-]*|\/?>)|\b(import|export|from|default|const|let|var|function|return|async|await|if|else|for|while|do|switch|case|break|continue|try|catch|finally|throw|new|typeof|instanceof|in|of|interface|type|class|extends|implements|struct|enum|protocol|extension|func|def|pub|fn|impl|use|mod|match|where|guard|defer|init|self|super|this|true|false|null|undefined|nil|void)\b|\b(useState|useEffect|useMemo|useCallback|useRef|useContext|React|String|Int|Double|Float|Bool|Array|Dictionary|Set|Promise|Record|Partial|Optional|Any|Error|URL|Data|Date|View|State|Published|ObservedObject|StateObject)\b|\b([a-zA-Z_$][a-zA-Z0-9_$]*)(?=\s*=)|\b([a-zA-Z_$][a-zA-Z0-9_$]*)(?=\s*\()|\b(0x[0-9a-fA-F]+|\d+(?:\.\d+)?)\b|(=>|===|!==|==|!=|<=|>=|&&|\|\||\?\?)/g;

            function highlightCode(rawCode) {
              const text = String(rawCode || "");
              if (!text) return "";
              let out = "";
              let lastIdx = 0;
              SYNTAX_TOKEN_RE.lastIndex = 0;
              let m;
              while ((m = SYNTAX_TOKEN_RE.exec(text)) !== null) {
                if (m.index > lastIdx) {
                  out += escapeHtml(text.slice(lastIdx, m.index));
                }
                const tok = m[0];
                let cls = "";
                if (m[1] !== undefined) cls = "tok-comment";
                else if (m[2] !== undefined) cls = "tok-string";
                else if (m[3] !== undefined) cls = "tok-comp";
                else if (m[4] !== undefined) cls = "tok-tag";
                else if (m[5] !== undefined) cls = "tok-kw";
                else if (m[6] !== undefined) cls = "tok-type";
                else if (m[7] !== undefined) cls = "tok-attr";
                else if (m[8] !== undefined) cls = "tok-fn";
                else if (m[9] !== undefined) cls = "tok-num";
                else if (m[10] !== undefined) cls = "tok-op";
                out += cls ? `<span class="${cls}">${escapeHtml(tok)}</span>` : escapeHtml(tok);
                lastIdx = SYNTAX_TOKEN_RE.lastIndex;
              }
              if (lastIdx < text.length) {
                out += escapeHtml(text.slice(lastIdx));
              }
              if (text.endsWith("\n")) out += " ";
              return out;
            }

            function updateSyntaxAndGutter() {
              const area = document.getElementById("codeArea");
              const hl = document.getElementById("codeHighlightContent");
              const gutter = document.getElementById("lineGutter");
              if (!area || !hl || !gutter) return;
              const val = area.value || "";
              hl.innerHTML = highlightCode(val);

              const lineCount = Math.max(1, val.split("\n").length);
              const peerLines = {};
              for (const p of (cachedPeers || [])) {
                if (p.cursor && p.cursor.filePath === activeFile && p.cursor.line) {
                  peerLines[p.cursor.line] = p.color || "#3b82f6";
                }
              }
              const gHtml = [];
              for (let i = 1; i <= lineCount; i++) {
                const dotCol = peerLines[i];
                const dot = dotCol ? `<span style="width:5px;height:5px;border-radius:50%;background:${escapeHtml(dotCol)};display:inline-block"></span>` : "";
                gHtml.push(`<div class="gutter-line">${dot}<span>${i}</span></div>`);
              }
              gutter.innerHTML = gHtml.join("");
              renderInEditorCollaboratorBands();
            }

            function renderInEditorCollaboratorBands() {
              const overlay = document.getElementById("editorCollabOverlay");
              if (!overlay) return;
              const lineH = 20;
              const topPad = 14;
              const bands = [];

              const allActive = (cachedPeers || []).filter(p => p.cursor && p.cursor.filePath === activeFile);
              for (const p of allActive) {
                const pid = p.userId || p.id;
                const isAI = pid === AI_USER_ID || p.role === "AI Agent";
                const c = p.cursor;
                const startLn = Math.max(1, c.line || 1);
                const endLn = Math.max(startLn, c.endLine || startLn);
                const topPx = topPad + (startLn - 1) * lineH;
                const heightPx = Math.max(lineH, (endLn - startLn + 1) * lineH);
                const col = escapeHtml(p.color || (isAI ? "#A855F7" : "#3B82F6"));
                const bgAlpha = isAI ? "26" : (pid === userId ? "16" : "20");
                const statusSuffix = isAI
                  ? (c.isTyping ? ` · กำลังแก้ Ln ${startLn}` : (p.aiStatusText ? ` · ${p.aiStatusText}` : ` · Ln ${startLn}`))
                  : (pid === userId ? " (You)" : (c.isTyping ? ` · กำลังแก้ Ln ${startLn}` : ` · Ln ${startLn}`));
                const prefixIcon = isAI ? "✦ " : "● ";
                bands.push(`<div class="collab-line-band" style="top:${topPx}px;height:${heightPx}px;background:${col}${bgAlpha};border-left-color:${col}">
                  <div class="collab-line-tag" style="background:${col}">${prefixIcon}${escapeHtml(p.displayName)}${escapeHtml(statusSuffix)}</div>
                </div>`);
              }
              overlay.innerHTML = bands.join("");
            }

            function syncEditorScroll() {
              const area = document.getElementById("codeArea");
              const backdrop = document.getElementById("codeBackdrop");
              const gutter = document.getElementById("lineGutter");
              if (!area || !backdrop || !gutter) return;
              backdrop.scrollTop = area.scrollTop;
              backdrop.scrollLeft = area.scrollLeft;
              gutter.scrollTop = area.scrollTop;
            }

            function scrollToLine(lineNum) {
              const area = document.getElementById("codeArea");
              if (!area) return;
              const lineH = 20;
              const targetY = Math.max(0, (Math.max(1, lineNum) - 1) * lineH - (area.clientHeight * 0.35));
              area.scrollTo({ top: targetY, behavior: "smooth" });
              setTimeout(syncEditorScroll, 60);
            }

            function computeCursorPos() {
              const area = document.getElementById("codeArea");
              if (!activeFile || !area) return null;
              const val = area.value || "";
              const start = area.selectionStart || 0;
              const end = area.selectionEnd || start;
              const beforeStart = val.slice(0, start).split("\n");
              const line = beforeStart.length;
              const column = beforeStart[beforeStart.length - 1].length + 1;
              let endLine = null, endColumn = null;
              if (end > start) {
                const beforeEnd = val.slice(0, end).split("\n");
                endLine = beforeEnd.length;
                endColumn = beforeEnd[beforeEnd.length - 1].length + 1;
              }
              return { filePath: activeFile, line, column, endLine, endColumn, isTyping };
            }

            function applyRemoteText(area, nextValue) {
              if (area.value === nextValue) return;
              const oldVal = area.value;
              const selStart = area.selectionStart || 0;
              const selEnd = area.selectionEnd || 0;
              const scrollTop = area.scrollTop;
              let prefixLen = 0;
              const maxPrefix = Math.min(oldVal.length, nextValue.length, selStart);
              while (prefixLen < maxPrefix && oldVal.charCodeAt(prefixLen) === nextValue.charCodeAt(prefixLen)) {
                prefixLen++;
              }
              const delta = nextValue.length - oldVal.length;
              const newStart = selStart <= prefixLen ? selStart : Math.max(prefixLen, Math.min(nextValue.length, selStart + delta));
              const newEnd = selEnd <= prefixLen ? selEnd : Math.max(newStart, Math.min(nextValue.length, selEnd + delta));
              area.value = nextValue;
              area.setSelectionRange(newStart, newEnd);
              area.scrollTop = scrollTop;
              updateSyntaxAndGutter();
              syncEditorScroll();
            }

            function toggleFollowPeer(pid, ev) {
              if (ev) ev.stopPropagation();
              if (followingPeerId === pid) {
                followingPeerId = null;
                lastFollowedState = "";
              } else {
                followingPeerId = pid;
                lastFollowedState = "";
                applyWebFollowIfNeeded(true);
              }
              renderPeersAndCursors();
            }

            function followAITeammate() {
              const aiPeer = (cachedPeers || []).find(p => (p.userId || p.id) === AI_USER_ID || p.role === "AI Agent");
              const targetId = aiPeer ? (aiPeer.userId || aiPeer.id) : AI_USER_ID;
              toggleFollowPeer(targetId, null);
            }

            function applyWebFollowIfNeeded(forceJump) {
              const banner = document.getElementById("followBanner");
              if (!followingPeerId) {
                if (banner) banner.style.display = "none";
                return;
              }
              const target = (cachedPeers || []).find(p => (p.userId || p.id) === followingPeerId);
              if (!target) {
                if (banner) banner.style.display = "none";
                return;
              }
              const c = target.cursor;
              const fileLabel = c && c.filePath ? `${c.filePath.split('/').pop()}:${c.line || 1}` : (target.aiStatusText || "In workspace");
              if (banner) {
                banner.style.display = "inline-flex";
                banner.innerHTML = `<span>👁 Following <strong>${escapeHtml(target.displayName)}</strong> · ${escapeHtml(fileLabel)}</span> <button class="btn" style="padding:1px 6px;font-size:10px" onclick="toggleFollowPeer('${escapeHtml(followingPeerId)}', event)">Unfollow</button>`;
              }
              if (c && c.filePath) {
                const stateKey = `${c.filePath}:${c.line || 1}`;
                if (forceJump || stateKey !== lastFollowedState) {
                  lastFollowedState = stateKey;
                  if (c.filePath !== activeFile) {
                    openFile(c.filePath, c.line || 1);
                  } else {
                    scrollToLine(c.line || 1);
                  }
                }
              }
            }

            function connectWS() {
              try {
                const proto = location.protocol === "https:" ? "wss:" : "ws:";
                ws = new WebSocket(`${proto}//${location.host}/ws/collab?code=${encodeURIComponent(ROOM_CODE)}`);
                ws.onopen = () => {
                  document.getElementById("wsStatusBadge").textContent = "WS REALTIME";
                  ws.send(JSON.stringify({
                    type: "hello",
                    code: ROOM_CODE,
                    userId,
                    displayName,
                    color: myColor,
                    role: "Web"
                  }));
                  sendPresenceWS();
                };
                ws.onmessage = (ev) => {
                  try {
                    const msg = JSON.parse(ev.data);
                    if ((msg.type === "assignedIdentity" || msg.type === "welcome") && (msg.color || msg.assignedColor)) {
                      myColor = msg.color || msg.assignedColor;
                      localStorage.setItem("mc_collab_color", myColor);
                      renderPeersAndCursors();
                    } else if (msg.type === "participants" && Array.isArray(msg.participants)) {
                      cachedPeers = msg.participants;
                      renderPeersAndCursors();
                      renderFileTree();
                      applyWebFollowIfNeeded(false);
                    } else if (msg.type === "mouse" && msg.userId && msg.userId !== userId) {
                      let idx = cachedPeers.findIndex(p => (p.userId || p.id) === msg.userId);
                      if (idx < 0) {
                        cachedPeers.push({ userId: msg.userId, displayName: msg.displayName || "Teammate", color: msg.color || "#3B82F6", role: msg.role || "Editor", isOnline: true });
                        idx = cachedPeers.length - 1;
                      }
                      cachedPeers[idx].mouse = { x: msg.x, y: msg.y, surface: msg.surface || "editor", activeFile: msg.activeFile || "", activeLine: msg.activeLine || 0 };
                      renderPeersAndCursors();
                    } else if (msg.type === "cursor" && msg.userId && msg.userId !== userId) {
                      let idx = cachedPeers.findIndex(p => (p.userId || p.id) === msg.userId);
                      if (idx < 0) {
                        cachedPeers.push({ userId: msg.userId, displayName: msg.displayName || "Teammate", color: msg.color || "#3B82F6", role: msg.role || "Editor", isOnline: true });
                        idx = cachedPeers.length - 1;
                      }
                      cachedPeers[idx].cursor = { filePath: msg.filePath, line: msg.line, column: msg.column, endLine: msg.endLine, endColumn: msg.endColumn, isTyping: msg.isTyping };
                      if (msg.aiStatusText !== undefined) cachedPeers[idx].aiStatusText = msg.aiStatusText;
                      if (msg.isAIActive !== undefined) cachedPeers[idx].isAIActive = msg.isAIActive;
                      renderPeersAndCursors();
                      renderFileTree();
                      applyWebFollowIfNeeded(false);
                    } else if (msg.type === "fileBuffer" && msg.path) {
                      fileRevisions[msg.path] = msg.revision || 1;
                      if (msg.path === activeFile && (msg.authorId || msg.senderId) !== userId && !isTyping && msg.content != null) {
                        applyRemoteText(document.getElementById("codeArea"), msg.content);
                      }
                      if (!cachedFiles.some(f => f.relativePath === msg.path)) syncState();
                    } else if (msg.type === "chat" && msg.message) {
                      if (!cachedChats.some(c => c.id === msg.id)) {
                        cachedChats.push({ id: msg.id || String(Date.now()), userId: msg.userId, displayName: msg.displayName || "Teammate", userColor: msg.userColor || "#60a5fa", message: msg.message });
                        renderChatMessages();
                      }
                    } else if (msg.type === "fsEvent") {
                      syncState();
                    }
                  } catch (e) {}
                };
                ws.onclose = () => {
                  document.getElementById("wsStatusBadge").textContent = "SYNCING";
                  setTimeout(connectWS, 1800);
                };
              } catch (e) {}
            }

            function sendPresenceWS() {
              if (!ws || ws.readyState !== 1) return;
              const rect = document.getElementById("workspaceArea").getBoundingClientRect();
              const x = rect.width > 0 ? Math.max(0, Math.min(1, (localMouse.x - rect.left) / rect.width)) : 0.5;
              const y = rect.height > 0 ? Math.max(0, Math.min(1, (localMouse.y - rect.top) / rect.height)) : 0.5;
              const cur = computeCursorPos();
              if (localMouse.visible) {
                ws.send(JSON.stringify({
                  type: "mouse",
                  userId,
                  displayName,
                  color: myColor,
                  role: "Web",
                  x,
                  y,
                  surface: "web",
                  activeFile: activeFile || "",
                  activeLine: cur ? cur.line : 0,
                  isPressing: false
                }));
              }
              if (cur) {
                ws.send(JSON.stringify({
                  type: "cursor",
                  userId,
                  displayName,
                  color: myColor,
                  role: "Web",
                  filePath: cur.filePath,
                  line: cur.line,
                  column: cur.column,
                  endLine: cur.endLine,
                  endColumn: cur.endColumn,
                  isTyping: !!cur.isTyping
                }));
              }
            }

            window.addEventListener("mousemove", (e) => {
              localMouse = { x: e.clientX, y: e.clientY, visible: true };
              renderPeersAndCursors();
              const now = performance.now();
              if (now - lastMouseSent > 35) {
                lastMouseSent = now;
                sendPresenceWS();
              }
            });

            function saveName() {
              displayName = document.getElementById("nameInput").value.trim() || displayName;
              localStorage.setItem("mc_collab_name", displayName);
              sendPresenceWS();
              syncState();
            }

            async function joinRoom() {
              try {
                const res = await fetch("/api/collab/join", {
                  method: "POST",
                  headers: {"Content-Type": "application/json"},
                  body: JSON.stringify({ code: ROOM_CODE, userId, displayName, color: myColor, role: "Web" })
                });
                const d = await res.json();
                if (d.assignedColor) {
                  myColor = d.assignedColor;
                  localStorage.setItem("mc_collab_color", myColor);
                }
              } catch (e) {}
              await syncState();
              connectWS();
            }

            async function openFile(path, jumpLine) {
              activeFile = path;
              const shortName = path.split("/").pop();
              document.getElementById("activeFileIcon").innerHTML = getFileIconSVG(shortName);
              document.getElementById("activeFileName").textContent = path;
              renderFileTree();
              const res = await fetch("/api/collab/file?path=" + encodeURIComponent(path));
              const d = await res.json();
              fileRevisions[path] = d.revision || 1;
              const area = document.getElementById("codeArea");
              area.value = d.content || "";
              updateSyntaxAndGutter();
              syncEditorScroll();
              if (jumpLine && jumpLine > 1) {
                scrollToLine(jumpLine);
              }
              sendPresenceWS();
            }

            async function pushEdit() {
              if (!activeFile) return;
              const targetFile = activeFile;
              const area = document.getElementById("codeArea");
              const content = area.value;
              const baseRevision = fileRevisions[targetFile] || 1;
              if (ws && ws.readyState === 1) {
                ws.send(JSON.stringify({
                  type: "edit",
                  userId,
                  displayName,
                  path: targetFile,
                  content,
                  baseRevision
                }));
              }
              const res = await fetch("/api/collab/edit", {
                method: "POST",
                headers: {"Content-Type": "application/json"},
                body: JSON.stringify({ path: targetFile, content, baseRevision, userId, displayName })
              });
              try {
                const resp = await res.json();
                if (resp.revision) fileRevisions[targetFile] = resp.revision;
                if (resp.merged && resp.content != null && activeFile === targetFile && !isTyping) {
                  applyRemoteText(area, resp.content);
                }
              } catch (e) {}
            }

            const codeAreaEl = document.getElementById("codeArea");
            codeAreaEl.addEventListener("scroll", syncEditorScroll);
            codeAreaEl.addEventListener("input", () => {
              isTyping = true;
              updateSyntaxAndGutter();
              syncEditorScroll();
              sendPresenceWS();
              clearTimeout(window._editTimer);
              window._editTimer = setTimeout(() => { isTyping = false; pushEdit(); sendPresenceWS(); }, 180);
            });
            ["keyup", "mouseup", "click", "select"].forEach(evName => {
              codeAreaEl.addEventListener(evName, () => {
                sendPresenceWS();
                renderInEditorCollaboratorBands();
              });
            });

            function toggleFolder(dir) {
              if (collapsedFolders.has(dir)) collapsedFolders.delete(dir);
              else collapsedFolders.add(dir);
              renderFileTree();
            }

            function renderFileTree() {
              const folderSet = new Set(cachedDirs || []);
              for (const f of cachedFiles) {
                const parts = (f.relativePath || "").split("/");
                for (let i = 1; i < parts.length; i++) {
                  folderSet.add(parts.slice(0, i).join("/"));
                }
              }
              const entries = [];
              for (const d of folderSet) entries.push({ type: "dir", path: d });
              for (const f of cachedFiles) entries.push({ type: "file", path: f.relativePath, file: f });
              entries.sort((a, b) => a.path.localeCompare(b.path));

              document.getElementById("fileCountLabel").textContent = cachedFiles.length + " files";
              const html = [];
              for (const item of entries) {
                const parts = item.path.split("/");
                let hidden = false;
                for (let i = 1; i < parts.length; i++) {
                  if (collapsedFolders.has(parts.slice(0, i).join("/"))) { hidden = true; break; }
                }
                if (hidden) continue;
                const depth = parts.length - 1;
                const pad = 8 + depth * 14;
                const name = parts[parts.length - 1];
                if (item.type === "dir") {
                  const isClosed = collapsedFolders.has(item.path);
                  const dirPeers = cachedPeers.filter(p => (p.userId || p.id) !== userId && p.cursor && p.cursor.filePath && p.cursor.filePath.startsWith(item.path + "/"));
                  const dots = dirPeers.slice(0, 3).map(p => `<span class="dot" style="width:6px;height:6px;background:${escapeHtml(p.color)}"></span>`).join("");
                  html.push(`<div class="folder-row" style="padding-left:${pad}px" onclick="toggleFolder('${item.path.replace(/'/g, "\\'")}')">
                    <span style="font-size:9px;width:10px;color:var(--muted)">${isClosed ? '▶' : '▼'}</span>
                    <span class="file-icon-wrap">${getFolderIconSVG(name, isClosed)}</span>
                    <span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${escapeHtml(name)}</span>
                    <span style="margin-left:auto;display:flex;gap:3px">${dots}</span>
                  </div>`);
                } else {
                  const filePeers = cachedPeers.filter(p => (p.userId || p.id) !== userId && p.cursor && p.cursor.filePath === item.path);
                  const topPeer = filePeers[0];
                  const isAIPeer = topPeer && ((topPeer.userId || topPeer.id) === AI_USER_ID || topPeer.role === "AI Agent");
                  const badge = topPeer
                    ? `<span class="badge" style="font-size:9.5px;padding:1px 5px;border-color:${escapeHtml(topPeer.color)};color:${escapeHtml(topPeer.color)};background:${escapeHtml(topPeer.color)}18">${isAIPeer ? '✦ ' : ''}${escapeHtml(topPeer.displayName)}:${topPeer.cursor.line || 1}</span>`
                    : "";
                  html.push(`<div class="file-row ${item.path === activeFile ? 'active' : ''}" style="padding-left:${pad + 14}px" onclick="openFile('${item.path.replace(/'/g, "\\'")}')">
                    <div class="file-item-left">
                      <span class="file-icon-wrap">${getFileIconSVG(name)}</span>
                      <span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${escapeHtml(name)}</span>
                    </div>
                    ${badge}
                  </div>`);
                }
              }
              document.getElementById("fileList").innerHTML = html.join("");
            }

            function renderPeersAndCursors() {
              const peers = cachedPeers || [];
              document.getElementById("peerCountBadge").textContent = Math.max(1, peers.length) + " online";
              document.getElementById("peerList").innerHTML = peers.map(p => {
                const pid = p.userId || p.id;
                const isAI = pid === AI_USER_ID || p.role === "AI Agent";
                const isFollow = followingPeerId === pid;
                const c = p.cursor;
                let act = c && c.filePath
                  ? `${c.isTyping ? 'กำลังแก้ ' : ''}${c.filePath.split('/').pop()}:${c.line || 1}`
                  : (p.mouse && p.mouse.activeFile ? p.mouse.activeFile.split('/').pop() : 'Browsing workspace');
                if (isAI && p.aiStatusText) {
                  act = c && c.filePath ? `${p.aiStatusText} · ${c.filePath.split('/').pop()}:${c.line || 1}` : p.aiStatusText;
                }
                const clickAttr = c && c.filePath ? `onclick="openFile('${c.filePath.replace(/'/g, "\\'")}', ${c.line || 1})"` : "";
                const followBtn = pid !== userId
                  ? `<button class="follow-btn ${isFollow ? 'active' : ''}" onclick="toggleFollowPeer('${escapeHtml(pid)}', event)">${isFollow ? 'Following' : 'Follow'}</button>`
                  : "";
                const roleBadge = isAI
                  ? `<span class="badge" style="font-size:9px;padding:1px 5px;background:rgba(168,85,247,0.22);border-color:rgba(168,85,247,0.5);color:#e9d5ff">✦ AI AGENT</span>`
                  : `<span style="color:var(--muted);font-weight:400">(${escapeHtml(p.role)})</span>`;
                return `<div class="peer-row ${isAI ? 'ai-peer' : ''} ${isFollow ? 'following' : ''}" ${clickAttr}>
                  <span class="dot" style="background:${escapeHtml(p.color || '#3b82f6')}"></span>
                  <div style="min-width:0;flex:1">
                    <div style="font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;display:flex;align-items:center;gap:5px">
                      <span>${escapeHtml(p.displayName)}${pid === userId ? ' (You)' : ''}</span>
                      ${roleBadge}
                    </div>
                    <div style="font-size:10.5px;color:${isAI && p.isAIActive ? '#d8b4fe' : 'var(--secondary)'};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${escapeHtml(act)}</div>
                  </div>
                  ${followBtn}
                </div>`;
              }).join("");

              const sameFilePeers = peers.filter(p => (p.userId || p.id) !== userId && p.cursor && p.cursor.filePath === activeFile);
              document.getElementById("activeEditorsIndicator").innerHTML = sameFilePeers.map(p => {
                const isAI = (p.userId || p.id) === AI_USER_ID || p.role === "AI Agent";
                return `<span style="color:${escapeHtml(p.color)};font-weight:600">${isAI ? '✦' : '●'} ${escapeHtml(p.displayName)} (Ln ${p.cursor.line || 1})</span>`;
              }).join(" &nbsp; ");

              updateSyntaxAndGutter();

              const rect = document.getElementById("workspaceArea").getBoundingClientRect();
              const cursorsHtml = [];
              for (const p of peers) {
                const pid = p.userId || p.id;
                if (pid === userId || !p.mouse) continue;
                const isAI = pid === AI_USER_ID || p.role === "AI Agent";
                const mx = p.mouse.x !== undefined ? p.mouse.x : (p.mouse.normX !== undefined ? p.mouse.normX : 0.5);
                const my = p.mouse.y !== undefined ? p.mouse.y : (p.mouse.normY !== undefined ? p.mouse.normY : 0.5);
                const px = rect.left + mx * rect.width;
                const py = rect.top + my * rect.height;
                const col = escapeHtml(p.color || "#3b82f6");
                const sub = p.cursor && p.cursor.filePath ? ` · ${p.cursor.filePath.split('/').pop()}:${p.cursor.line || 1}` : "";
                cursorsHtml.push(`<div class="remote-cursor" style="transform:translate(${px.toFixed(1)}px, ${py.toFixed(1)}px)">
                  <svg width="16" height="18" viewBox="0 0 16 18" fill="none"><path d="M1 1L6.2 15.5L8.7 9.6L14.8 7.5L1 1Z" fill="${col}" stroke="#fff" stroke-width="1.3"/></svg>
                  <div class="cursor-pill" style="background:${col}">${isAI ? '✦ ' : ''}${escapeHtml(p.displayName)}${escapeHtml(sub)}</div>
                </div>`);
              }
              if (localMouse.visible && localMouse.x > 0) {
                cursorsHtml.push(`<div class="remote-cursor" style="transform:translate(${(localMouse.x + 14).toFixed(1)}px, ${(localMouse.y + 16).toFixed(1)}px);transition:none;opacity:0.88">
                  <div class="cursor-pill" style="background:${escapeHtml(myColor)};margin:0;font-size:10px">● ${escapeHtml(displayName)} (You)</div>
                </div>`);
              }
              document.getElementById("cursorLayer").innerHTML = cursorsHtml.join("");
            }

            function renderChatMessages() {
              const box = document.getElementById("chatMsgs");
              if (!box) return;
              box.innerHTML = (cachedChats || []).map(c => {
                const isAI = c.userId === AI_USER_ID || c.displayName === "MicroCode AI";
                return `<div class="chat-msg-card ${isAI ? 'ai-msg' : ''}">
                  <strong style="color:${escapeHtml(c.userColor || (isAI ? '#c084fc' : '#60a5fa'))}">${isAI ? '✦ ' : ''}${escapeHtml(c.displayName)}:</strong>
                  <span>${escapeHtml(c.message)}</span>
                </div>`;
              }).join("");
              box.scrollTop = box.scrollHeight;
            }

            function prefillAIChat() {
              const inp = document.getElementById("chatInput");
              if (!inp) return;
              if (!inp.value.trim().toLowerCase().startsWith("@ai")) {
                inp.value = "@ai " + inp.value;
              }
              inp.focus();
            }

            async function sendChat() {
              const inp = document.getElementById("chatInput");
              const text = inp.value.trim();
              if (!text) return;
              inp.value = "";
              await fetch("/api/collab/chat", {
                method: "POST",
                headers: {"Content-Type": "application/json"},
                body: JSON.stringify({ userId, displayName, color: myColor, message: text })
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
                    color: myColor,
                    role: "Web",
                    cursor: computeCursorPos()
                  })
                });
                const s = await res.json();
                document.getElementById("wsTitle").textContent = "MicroCode · " + (s.workspaceName || "Workspace");
                cachedPeers = s.participants || [];
                cachedFiles = s.sharedFiles || [];
                cachedDirs = s.sharedDirectories || [];
                renderFileTree();
                renderPeersAndCursors();
                applyWebFollowIfNeeded(false);

                if (!activeFile && cachedFiles.length > 0) {
                  openFile(cachedFiles[0].relativePath);
                } else if (activeFile && !isTyping && s.openBuffers && s.openBuffers[activeFile] != null) {
                  const remoteRev = (s.fileRevisions && s.fileRevisions[activeFile]) || 1;
                  const localRev = fileRevisions[activeFile] || 0;
                  if (remoteRev >= localRev) {
                    applyRemoteText(document.getElementById("codeArea"), s.openBuffers[activeFile]);
                    fileRevisions[activeFile] = remoteRev;
                  }
                }

                const tasks = JSON.parse(s.teamTasksJSON || "[]");
                document.getElementById("taskList").innerHTML = tasks.map(t =>
                  `<div class="peer-row" style="flex-direction:column;align-items:flex-start;gap:3px">
                    <div style="font-weight:600;color:var(--text)">${escapeHtml(t.title)}</div>
                    <div style="font-size:10.5px;color:var(--secondary)">${escapeHtml(t.status)} · Owner: ${escapeHtml(t.owner)}</div>
                  </div>`
                ).join("") || `<div style="padding:8px;font-size:11px;color:var(--muted)">No shared tasks</div>`;

                cachedChats = s.chatMessages || [];
                renderChatMessages();
              } catch (e) {}
            }

            joinRoom();
            setInterval(syncState, 2200);
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
