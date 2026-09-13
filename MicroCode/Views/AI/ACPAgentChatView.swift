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
            
            Divider()
            
            // Status bar
            HStack {
                if let session = acpHost.activeSession {
                    Text(session.config.name)
                    Spacer()
                    Text(session.state.statusLabel)
                        .foregroundColor(session.state.isActive ? .green : .secondary)
                    Text(formatTime(session.elapsedSeconds))
                } else {
                    Text("No agent connected")
                    Spacer()
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Input area
            HStack(alignment: .bottom) {
                TextEditor(text: $inputText)
                    .frame(minHeight: 36, maxHeight: 100)
                    .padding(4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                
                Button(action: sendACPMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 500)
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
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    switch message.messageType {
                    case .text:
                        Text(message.content)
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(12)
                    case .thinking:
                        DisclosureGroup(isExpanded: $isExpanded) {
                            Text(message.content)
                                .font(.callout)
                                .foregroundColor(.secondary)
                        } label: {
                            HStack {
                                Image(systemName: "brain")
                                Text("Thinking...")
                            }
                            .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(12)
                    case .toolCall:
                        DisclosureGroup(isExpanded: $isExpanded) {
                            Text(message.content)
                                .font(.system(.caption, design: .monospaced))
                        } label: {
                            HStack {
                                Image(systemName: "wrench.and.screwdriver")
                                Text(message.toolName ?? "Tool Call")
                                    .fontWeight(.medium)
                            }
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                        )
                    case .toolResult:
                        Text(message.content)
                            .font(.system(.caption, design: .monospaced))
                            .padding(10)
                            .background(message.isSuccess == true ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(message.isSuccess == true ? Color.green : Color.red, lineWidth: 1)
                            )
                    case .error:
                        Text(message.content)
                            .padding(10)
                            .background(Color.red.opacity(0.2))
                            .foregroundColor(.red)
                            .cornerRadius(12)
                    case .permission:
                        Text("Permission requested: \(message.content)")
                            .padding(10)
                            .background(Color.yellow.opacity(0.2))
                            .cornerRadius(12)
                    }
                }
                Spacer()
            }
        }
    }
}
