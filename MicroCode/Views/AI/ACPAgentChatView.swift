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
    @ObservedObject var acpHost = ACPHostService.shared
    @State private var inputText: String = ""
    @State private var acpMessages: [ACPChatMessage] = []
    @State private var streamConsumerTask: Task<Void, Never>?
    
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
                        
                    if ProjectMemoryService.shared.isLoaded {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .help("Project Memory Loaded")
                    }
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
        .onDisappear {
            streamConsumerTask?.cancel()
        }
    }
    
    private func sendACPMessage() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let userMsg = ACPChatMessage(id: UUID(), role: .user, content: prompt, messageType: .text)
        acpMessages.append(userMsg)
        inputText = ""
        
        // Resolve real workspace path from AppState instead of '/'
        let workspace = AppState.shared?.workspaceFolder?.path
            ?? AppState.shared?.activeTerminalDirectory
            ?? AgentService.shared.currentWorkspace
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        acpHost.sendTask(prompt, workspacePath: workspace)
        
        guard let session = acpHost.activeSession else { return }
        streamConsumerTask?.cancel()
        let stream = session.eventStream
        let responseId = UUID()
        
        streamConsumerTask = Task { @MainActor in
            var accumulatedText = ""
            for await event in stream {
                if Task.isCancelled { break }
                switch event {
                case .text(let chunk):
                    accumulatedText += chunk
                    if let idx = acpMessages.firstIndex(where: { $0.id == responseId }) {
                        acpMessages[idx] = ACPChatMessage(id: responseId, role: .agent, content: accumulatedText, messageType: .text)
                    } else {
                        acpMessages.append(ACPChatMessage(id: responseId, role: .agent, content: accumulatedText, messageType: .text))
                    }
                case .thinking(let thought):
                    acpMessages.append(ACPChatMessage(id: UUID(), role: .agent, content: thought, messageType: .thinking))
                case .toolCall(let tc):
                    acpMessages.append(ACPChatMessage(id: UUID(), role: .agent, content: tc.displaySummary, messageType: .toolCall, toolName: tc.name))
                case .toolResult(let tr):
                    acpMessages.append(ACPChatMessage(id: UUID(), role: .agent, content: tr.content, messageType: .toolResult, toolName: tr.toolName, isSuccess: !tr.isError))
                case .permissionRequest(let perm):
                    acpMessages.append(ACPChatMessage(id: UUID(), role: .agent, content: perm.description, messageType: .permission, permissionRequestId: perm.id))
                case .error(let err):
                    acpMessages.append(ACPChatMessage(id: UUID(), role: .agent, content: err, messageType: .error))
                case .complete(let res):
                    if accumulatedText.isEmpty && !res.result.isEmpty {
                        acpMessages.append(ACPChatMessage(id: responseId, role: .agent, content: res.result, messageType: .text))
                    }
                case .sessionInit, .systemInfo, .progress:
                    break
                }
            }
        }
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
    var permissionRequestId: String?
}

// MARK: - ACP Chat Message Row

struct ACPChatMessageRow: View {
    let message: ACPChatMessage
    @State private var isExpanded: Bool = false
    @State private var permissionDecision: Bool? = nil
    
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Permission requested: \(message.content)")
                                .foregroundColor(.white)
                            if let decision = permissionDecision {
                                Text(decision ? "Approved" : "Rejected")
                                    .font(.caption)
                                    .foregroundColor(decision ? .green : .red)
                            } else if let reqId = message.permissionRequestId {
                                HStack(spacing: 8) {
                                    Button("Approve") {
                                        permissionDecision = true
                                        ACPHostService.shared.respondToPermission(reqId, approved: true)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    Button("Reject") {
                                        permissionDecision = false
                                        ACPHostService.shared.respondToPermission(reqId, approved: false)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.08))
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
