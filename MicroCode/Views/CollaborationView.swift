//
//  CollaborationView.swift
//  MicroCode
//
//  Realtime Collaboration UI
//  User presence, cursor indicators, chat
//
//  SPU AI CLUB - Dotmini Software
//

import SwiftUI

struct CollaborationView: View {
    @StateObject private var collab = CollaborationService.shared
    @StateObject private var auth = AuthService.shared
    @State private var shareCode = ""
    @State private var showJoinDialog = false
    @State private var chatMessage = ""
    @State private var showChat = false
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            if collab.currentSession != nil {
                // Active Session View
                activeSessionView
            } else {
                // Start/Join View
                startSessionView
            }
        }
        .frame(width: 400, height: 500)
        .background(Color.compat(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showJoinDialog) {
            joinSessionSheet
        }
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "person.3.fill")
                .foregroundColor(.accentColor)
            Text("Realtime Collaboration")
                .font(.headline)
            
            Spacer()
            
            // Connection Status
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    private var startSessionView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon
            Image(systemName: "link.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Start Collaborating")
                .font(.title2.bold())
            
            Text("Work together in real-time with your team")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                // Start Session
                Button {
                    Task { await startSession() }
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Start New Session")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                
                // Join Session
                Button {
                    showJoinDialog = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Join Session")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
    }
    
    private var activeSessionView: some View {
        VStack(spacing: 0) {
            // Share Link Section
            if let link = collab.getShareLink() {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.accentColor)
                        Text("Share this link to invite others:")
                            .font(.subheadline)
                        Spacer()
                    }
                    
                    HStack {
                        Text(link)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(Color.compat(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                        
                        Button {
                            collab.copyShareLinkToClipboard()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color.accentColor.opacity(0.1))
            }
            
            Divider()
            
            // Participants
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Participants")
                        .font(.headline)
                    Spacer()
                    Text("\(collab.participants.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(8)
                }
                
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(collab.participants) { participant in
                            ParticipantRow(participant: participant)
                        }
                    }
                }
            }
            .padding()
            
            Divider()
            
            // Chat Toggle
            if showChat {
                chatView
            }
            
            // Footer Actions
            HStack {
                Button {
                    showChat.toggle()
                } label: {
                    Image(systemName: showChat ? "bubble.left.fill" : "bubble.left")
                    Text("Chat")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button {
                    Task { await collab.leaveSession() }
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("Leave Session")
                    }
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding()
        }
    }
    
    private var chatView: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(collab.chatMessages) { msg in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(msg.displayName)
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)
                            Text(msg.message)
                                .font(.callout)
                        }
                        .padding(8)
                        .background(Color.compat(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            .frame(height: 120)
            
            // Input
            HStack {
                TextField("Message...", text: $chatMessage)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendChat() }
                
                Button {
                    sendChat()
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(chatMessage.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.compat(nsColor: .controlBackgroundColor))
    }
    
    private var joinSessionSheet: some View {
        VStack(spacing: 24) {
            Text("Join Session")
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter share code:")
                    .font(.subheadline)
                TextField("ABCD1234", text: $shareCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            
            HStack {
                Button("Cancel") {
                    showJoinDialog = false
                }
                .buttonStyle(.bordered)
                
                Button("Join") {
                    Task { await joinSession() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(shareCode.count < 4)
            }
        }
        .padding(32)
        .frame(width: 300)
    }
    
    // MARK: - Helpers
    
    private var statusColor: Color {
        switch collab.connectionStatus {
        case .connected: return .green
        case .connecting, .reconnecting: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }
    
    private var statusText: String {
        switch collab.connectionStatus {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .reconnecting: return "Reconnecting..."
        case .disconnected: return "Disconnected"
        case .error(let msg): return msg
        }
    }
    
    private func startSession() async {
        guard auth.currentUser != nil else { return }
        _ = try? await collab.createSession(projectId: "current-project")
    }
    
    private func joinSession() async {
        _ = try? await collab.joinSession(shareCode: shareCode)
        showJoinDialog = false
    }
    
    private func sendChat() {
        guard !chatMessage.isEmpty else { return }
        Task {
            await collab.sendChatMessage(chatMessage)
            chatMessage = ""
        }
    }
}

// MARK: - Participant Row

struct ParticipantRow: View {
    let participant: CollaborationSession.Participant
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color(hex: participant.color) ?? .blue)
                .frame(width: 32, height: 32)
                .overlay(
                    Text(participant.displayName.prefix(1).uppercased())
                        .font(.caption.bold())
                        .foregroundColor(.white)
                )
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(participant.displayName)
                    .font(.subheadline.bold())
                
                if let cursor = participant.cursorPosition {
                    Text("Editing: \((cursor.filePath as NSString).lastPathComponent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Status
            Circle()
                .fill(participant.isOnline ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
        }
        .padding(8)
        .background(Color.compat(nsColor: .textBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Color Extension (Moved to ColorExtensions.swift)
