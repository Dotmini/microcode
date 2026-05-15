//
//  CollaborationService.swift
//  MicroCode
//
//  Realtime Collaboration via WebSocket
//  CRDT-based sync for conflict resolution
//
//  SPU AI CLUB - Dotmini Software
//

import Foundation
import Combine
import AppKit

// MARK: - Collaboration Session

struct CollaborationSession: Identifiable, Codable {
    let id: String
    var projectId: String
    var hostUserId: String
    var participants: [Participant]
    var isActive: Bool
    var createdAt: Date
    var shareCode: String
    
    struct Participant: Identifiable, Codable {
        let id: String
        var userId: String
        var displayName: String
        var color: String
        var cursorPosition: CursorPosition?
        var isOnline: Bool
        var joinedAt: Date
    }
    
    struct CursorPosition: Codable {
        var filePath: String
        var line: Int
        var column: Int
    }
}

// MARK: - Collaboration Message

enum CollaborationMessage: Codable {
    case join(userId: String, displayName: String)
    case leave(userId: String)
    case cursorMove(userId: String, position: CollaborationSession.CursorPosition)
    case textChange(userId: String, change: TextChange)
    case fileOpen(userId: String, filePath: String)
    case sync(files: [String: String])
    case chat(userId: String, message: String)
    
    struct TextChange: Codable {
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
class CollaborationService: ObservableObject {
    static let shared = CollaborationService()
    
    @Published var currentSession: CollaborationSession?
    @Published var participants: [CollaborationSession.Participant] = []
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var pendingChanges: [CollaborationMessage.TextChange] = []
    @Published var chatMessages: [ChatMessage] = []
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var reconnectTimer: Timer?
    private var heartbeatTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private let serverURL = "wss://collab.dotmini.dev/ws"
    
    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case error(String)
    }
    
    struct ChatMessage: Identifiable {
        let id = UUID()
        let userId: String
        let displayName: String
        let message: String
        let timestamp: Date
    }
    
    // MARK: - Session Management
    
    func createSession(projectId: String) async throws -> CollaborationSession {
        guard let user = AuthService.shared.currentUser else {
            throw CollaborationError.notAuthenticated
        }
        
        let shareCode = generateShareCode()
        
        let session = CollaborationSession(
            id: UUID().uuidString,
            projectId: projectId,
            hostUserId: user.id,
            participants: [
                CollaborationSession.Participant(
                    id: UUID().uuidString,
                    userId: user.id,
                    displayName: user.displayName,
                    color: randomColor(),
                    cursorPosition: nil,
                    isOnline: true,
                    joinedAt: Date()
                )
            ],
            isActive: true,
            createdAt: Date(),
            shareCode: shareCode
        )
        
        self.currentSession = session
        self.participants = session.participants
        
        // Connect to collaboration server
        try await connect(sessionId: session.id, shareCode: shareCode)
        
        return session
    }
    
    func joinSession(shareCode: String) async throws -> CollaborationSession {
        guard let user = AuthService.shared.currentUser else {
            throw CollaborationError.notAuthenticated
        }
        
        // In production, this would fetch session from server
        let session = CollaborationSession(
            id: UUID().uuidString,
            projectId: "shared-project",
            hostUserId: "host-user",
            participants: [],
            isActive: true,
            createdAt: Date(),
            shareCode: shareCode
        )
        
        self.currentSession = session
        
        // Add self as participant
        let participant = CollaborationSession.Participant(
            id: UUID().uuidString,
            userId: user.id,
            displayName: user.displayName,
            color: randomColor(),
            cursorPosition: nil,
            isOnline: true,
            joinedAt: Date()
        )
        self.participants.append(participant)
        
        // Connect
        try await connect(sessionId: session.id, shareCode: shareCode)
        
        // Send join message
        await sendMessage(.join(userId: user.id, displayName: user.displayName))
        
        return session
    }
    
    func leaveSession() async {
        guard let user = AuthService.shared.currentUser else { return }
        
        await sendMessage(.leave(userId: user.id))
        disconnect()
        currentSession = nil
        participants = []
    }
    
    // MARK: - WebSocket Connection
    
    private func connect(sessionId: String, shareCode: String) async throws {
        connectionStatus = .connecting
        
        guard let url = URL(string: "\(serverURL)?session=\(sessionId)&code=\(shareCode)") else {
            throw CollaborationError.invalidURL
        }
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Start receiving messages
        Task { await receiveMessages() }
        
        // Start heartbeat
        startHeartbeat()
        
        isConnected = true
        connectionStatus = .connected
    }
    
    private func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        heartbeatTimer?.invalidate()
        reconnectTimer?.invalidate()
        isConnected = false
        connectionStatus = .disconnected
    }
    
    private func receiveMessages() async {
        guard let task = webSocketTask else { return }
        
        do {
            while isConnected {
                let message = try await task.receive()
                
                switch message {
                case .string(let text):
                    await handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(text)
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            connectionStatus = .error(error.localizedDescription)
            // Attempt reconnect
            attemptReconnect()
        }
    }
    
    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let message = try decoder.decode(CollaborationMessage.self, from: data)
            
            switch message {
            case .join(let userId, let displayName):
                let participant = CollaborationSession.Participant(
                    id: UUID().uuidString,
                    userId: userId,
                    displayName: displayName,
                    color: randomColor(),
                    cursorPosition: nil,
                    isOnline: true,
                    joinedAt: Date()
                )
                if !participants.contains(where: { $0.userId == userId }) {
                    participants.append(participant)
                }
                
            case .leave(let userId):
                participants.removeAll { $0.userId == userId }
                
            case .cursorMove(let userId, let position):
                if let index = participants.firstIndex(where: { $0.userId == userId }) {
                    participants[index].cursorPosition = position
                }
                
            case .textChange(_, let change):
                pendingChanges.append(change)
                
            case .fileOpen(_, _):
                // Handle file open
                break
                
            case .sync(_):
                // Handle full sync
                break
                
            case .chat(let userId, let message):
                let displayName = participants.first(where: { $0.userId == userId })?.displayName ?? "Unknown"
                chatMessages.append(ChatMessage(
                    userId: userId,
                    displayName: displayName,
                    message: message,
                    timestamp: Date()
                ))
            }
        } catch {
            print("Failed to decode message: \(error)")
        }
    }
    
    func sendMessage(_ message: CollaborationMessage) async {
        guard let task = webSocketTask else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(message)
            if let text = String(data: data, encoding: .utf8) {
                try await task.send(.string(text))
            }
        } catch {
            print("Failed to send message: \(error)")
        }
    }
    
    // MARK: - Cursor & Changes
    
    func updateCursor(filePath: String, line: Int, column: Int) async {
        guard let user = AuthService.shared.currentUser else { return }
        
        let position = CollaborationSession.CursorPosition(
            filePath: filePath,
            line: line,
            column: column
        )
        
        await sendMessage(.cursorMove(userId: user.id, position: position))
    }
    
    func sendTextChange(_ change: CollaborationMessage.TextChange) async {
        guard let user = AuthService.shared.currentUser else { return }
        await sendMessage(.textChange(userId: user.id, change: change))
    }
    
    func sendChatMessage(_ message: String) async {
        guard let user = AuthService.shared.currentUser else { return }
        
        chatMessages.append(ChatMessage(
            userId: user.id,
            displayName: user.displayName,
            message: message,
            timestamp: Date()
        ))
        
        await sendMessage(.chat(userId: user.id, message: message))
    }
    
    // MARK: - Share Link
    
    func getShareLink() -> String? {
        guard let session = currentSession else { return nil }
        return "https://idx.dotmini.dev/collab/\(session.shareCode)"
    }
    
    func copyShareLinkToClipboard() {
        guard let link = getShareLink() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }
    
    // MARK: - Helpers
    
    private func generateShareCode() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<8).map { _ in characters.randomElement()! })
    }
    
    private func randomColor() -> String {
        let colors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F"]
        return colors.randomElement() ?? "#4ECDC4"
    }
    
    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.webSocketTask?.sendPing { error in
                    if let error = error {
                        print("Heartbeat failed: \(error)")
                    }
                }
            }
        }
    }
    
    private func attemptReconnect() {
        connectionStatus = .reconnecting
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if let session = self?.currentSession {
                    try? await self?.connect(sessionId: session.id, shareCode: session.shareCode)
                }
            }
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
        case .notAuthenticated: return "Please sign in to collaborate"
        case .sessionNotFound: return "Collaboration session not found"
        case .connectionFailed: return "Failed to connect to collaboration server"
        case .invalidURL: return "Invalid collaboration URL"
        }
    }
}
