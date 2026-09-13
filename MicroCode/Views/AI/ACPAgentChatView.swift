//
//  ACPAgentChatView.swift
//  MicroCode
//
//  Chat view for external coding agent conversations.
//  Renders streaming text, tool calls, thinking blocks, and permission requests.
//

import SwiftUI

// MARK: - ACP Chat View

struct ACPAgentChatView: View {
    @StateObject var acpHost = ACPHostService.shared
    @State private var inputText: String = ""
    @State private var acpMessages: [ACPChatMessage] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(acpMessages) { message in
                        ACPChatMessageRow(message: message)
                    }
                }
                .padding()
            }
            .background(Color.black)
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            // Status bar
            HStack {
                if let session = acpHost.activeSession {
                    Text(session.config.name)
                        .foregroundColor(.white)
                    Spacer()
                    Text(session.state.statusLabel)
                        .foregroundColor(session.state.isActive ? .white : Color.white.opacity(0.6))
                    Text(formatTime(session.elapsedSeconds))
                        .foregroundColor(Color.white.opacity(0.6))
                } else {
                    Text("No agent connected")
                        .foregroundColor(Color.white.opacity(0.6))
                    Spacer()
                }
            }
            .font(.caption)
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Color.black)
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            // Input area
            HStack(alignment: .bottom) {
                TextEditor(text: $inputText)
                    .frame(minHeight: 36, maxHeight: 100)
                    .padding(4)
                    .background(Color.black)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                
                Button(action: sendACPMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.black)
                        .padding(10)
                        .background(Color.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(Color.black)
        }
        .frame(minWidth: 400, minHeight: 500)
        .background(Color.black)
    }
    
    private func sendACPMessage() {
        guard !inputText.isEmpty else { return }
        let userMsg = ACPChatMessage(id: UUID(), role: .user, content: inputText, messageType: .text)
        acpMessages.append(userMsg)
        
        // Send to active agent via ACPHostService
        let workspace = FileManager.default.currentDirectoryPath
        acpHost.sendTask(inputText, workspacePath: workspace)
        
        inputText = ""
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - ACP Chat Message Model (View-local, avoids conflict with existing ChatMessage)

enum ACPChatRole {
    case user, agent, system
}

enum ACPChatMessageType {
    case text, thinking, toolCall, toolResult, error, permission
}

struct ACPChatMessage: Identifiable {
    let id: UUID
    let role: ACPChatRole
    let content: String
    let messageType: ACPChatMessageType
    var toolName: String?
    var isSuccess: Bool?
}

// MARK: - ACP Chat Message Row

struct ACPChatMessageRow: View {
    let message: ACPChatMessage
    @State private var isExpanded: Bool = false
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
                Text(message.content)
                    .padding(10)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(12)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    switch message.messageType {
                    case .text:
                        Text(message.content)
                            .padding(10)
                            .foregroundColor(.white)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    case .thinking:
                        DisclosureGroup(isExpanded: $isExpanded) {
                            Text(message.content)
                                .font(.callout)
                                .foregroundColor(Color.white.opacity(0.7))
                        } label: {
                            HStack {
                                Image(systemName: "brain")
                                Text("Thinking...")
                            }
                            .foregroundColor(Color.white.opacity(0.7))
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    case .toolCall:
                        DisclosureGroup(isExpanded: $isExpanded) {
                            Text(message.content)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.85))
                        } label: {
                            HStack {
                                Image(systemName: "wrench.and.screwdriver")
                                Text(message.toolName ?? "Tool Call")
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    case .toolResult:
                        Text(message.content)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.85))
                            .padding(10)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    case .error:
                        Text(message.content)
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    case .permission:
                        Text("Permission requested: \(message.content)")
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
                Spacer()
            }
        }
    }
}
