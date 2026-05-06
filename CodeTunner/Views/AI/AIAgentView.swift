//
//  AIAgentView.swift
//  CodeTunner
//
//  Redesigned by MicroCode AI - Professional Edition + Rich Content
//  Industrial/IDE aesthetic. Markdown & Code Block Support.
//

import SwiftUI
import Combine
import CodeTunnerSupport
import AppKit
import WebKit

// MARK: - AI Agent View (Professional)

struct AIAgentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var agent = AgentService.shared
    
    @State private var inputText = ""
    @State private var attachments: [AIAttachment] = []
    @State private var isHoveringInput = false
    @State private var isPaperMode = false  // A4 Paper reading mode
    @State private var isCellMode = false   // Cell Mode (notebook-style)
    @State private var currentPaperPage = 0
    @State private var showModelPicker = false
    @FocusState private var isInputFocused: Bool
    
    // Aesthetic Constants
    private let borderColor = Color.white.opacity(0.1)
    private let paneColor = Color(nsColor: .controlBackgroundColor)
    private let accentColor = Color.accentColor
    
    var body: some View {
        HStack(spacing: 0) {
            // Chat Sidebar (Collapsible)
            if agent.showChatSidebar {
                chatSidebar
                    .frame(width: 220)
                Divider()
            }
            
            // Main Content
            VStack(spacing: 0) {
                // 1. Toolbar / Header (Solid, Industrial)
                headerBar
                
                Divider().background(borderColor)
                
                // 2. Main Content Area
                if isPaperMode {
                    // A4 Paper Reading Mode
                    A4PaperView(
                        messages: agent.messages,
                        currentPage: $currentPaperPage
                    )
                } else if isCellMode {
                    // Cell Mode (Notebook-style AI Agent)
                    AgentCellModeView()
                        .environmentObject(appState)
                } else {
                    // Normal Chat Mode
                    VStack(spacing: 0) {
                        // Agent Phase Indicator (animated status bar)
                        if agent.agentPhase != .idle {
                            agentPhaseBar
                        }
                        
                        ZStack(alignment: .bottom) {
                            // Chat Scroll
                            AgentChatStage(messages: agent.messages, isLoading: agent.isLoading, currentToolExecution: agent.currentToolExecution, onApplyChange: { change in applyChange(change) }, onRejectChange: { change in rejectChange(change) }, onSuggestionTap: { suggestion in inputText = suggestion; sendMessage() })
                            
                            VStack(spacing: 0) {
                                // Suggested Action (after completion)
                                if let suggestion = agent.suggestedAction {
                                    suggestedActionBar(suggestion)
                                }
                                
                                // Input Container
                                inputArea
                            }
                        }
                        
                        // Activity Log (always visible when active)
                        if !agent.activityLog.isEmpty {
                            activityLogStrip
                        }
                    }
                }
            }
        }
        .background(appState.appTheme == .transparent || appState.appTheme == .extraClear ? Color.clear : Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if let workspace = appState.workspaceFolder {
                agent.setWorkspace(workspace.path)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentProcessQueueItem)) { notification in
            if let queued = notification.object as? QueuedMessage {
                executeMessage(queued.text, attachments: queued.attachments)
            }
        }
    }
    
    // MARK: - Chat Sidebar
    
    private var chatSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("CHATS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { _ = agent.createNewChat() }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("New Chat")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
            
            // Chat List
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(agent.chatSessions) { chat in
                        ChatListRow(
                            chat: chat,
                            isActive: agent.activeChatId == chat.id,
                            onSelect: { agent.switchChat(to: chat.id) },
                            onDelete: { agent.deleteChat(chat.id) }
                        )
                    }
                }
                .padding(8)
            }
        }
        .background(paneColor.opacity(0.5))
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                // Sidebar Toggle
                Button(action: { agent.showChatSidebar.toggle() }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 11))
                        .foregroundColor(agent.showChatSidebar ? .accentColor : .secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Chat History")
                
                // New Chat
                Button(action: { _ = agent.createNewChat() }) {
                    Image(systemName: "plus.message")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("New Chat")
                
                Spacer()
                
                // Mode pills (compact)
                HStack(spacing: 2) {
                    modePill("Chat", icon: "bubble.left.fill", isActive: !isPaperMode && !isCellMode) {
                        isPaperMode = false; isCellMode = false
                    }
                    modePill("Report", icon: "doc.text.fill", isActive: isPaperMode) {
                        isPaperMode = true; isCellMode = false
                    }
                    modePill("Cells", icon: "rectangle.grid.1x2.fill", isActive: isCellMode) {
                        isCellMode = true; isPaperMode = false
                    }
                }
                .padding(2)
                .background(Color.white.opacity(0.04))
                .cornerRadius(6)
                
                Spacer()
                
                // Compact actions
                HStack(spacing: 4) {
                    modelSelector
                    
                    Menu {
                        Button { Task { await appState.microCodeService?.indexProject() } } label: {
                            Label("Index Project", systemImage: "database")
                        }
                        Divider()
                        Button {
                            if agent.messages.count >= 2 {
                                agent.messages.removeLast(2)
                                agent.saveChats()
                            }
                        } label: { Label("Undo Last", systemImage: "arrow.uturn.backward") }
                        Button(role: .destructive) {
                            agent.clearCurrentChat()
                            attachments.removeAll()
                        } label: { Label("Clear Chat", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(4)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(paneColor)
            
            Rectangle()
                .fill(LinearGradient(colors: [.purple.opacity(0.4), .blue.opacity(0.3), .cyan.opacity(0.2)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
    }
    
    private func modePill(_ label: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { action() } }) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(isActive ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor.opacity(0.8) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Input Area
    
    private var inputArea: some View {
        VStack(spacing: 0) {
            // Subtle top separator
            Rectangle()
                .fill(LinearGradient(colors: [.purple.opacity(0.15), .blue.opacity(0.1), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
            
            // Attachment Pills
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(attachments.indices, id: \.self) { index in
                            if index < attachments.count {
                                let file = attachments[index]
                                HStack(spacing: 4) {
                                    Image(systemName: fileIcon(for: file.type))
                                        .font(.system(size: 9))
                                        .foregroundColor(.purple)
                                    Text(file.name)
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                    Button(action: { attachments.remove(at: index) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.08))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }
            }
            
            // Input row
            HStack(alignment: .bottom, spacing: 8) {
                // Attach
                Button(action: pickFile) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                
                // Context file pill
                if let file = appState.currentFile {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 8))
                        Text(file.name)
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(4)
                }
                
                // Text Field — Premium rounded
                if #available(macOS 13.0, *) {
                    TextField("Ask anything or give instructions...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .lineLimit(1...6)
                        .focused($isInputFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    isInputFocused
                                        ? LinearGradient(colors: [.purple.opacity(0.5), .blue.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        : LinearGradient(colors: [borderColor, borderColor], startPoint: .leading, endPoint: .trailing),
                                    lineWidth: 1
                                )
                        )
                        .onSubmit {
                            if !inputText.isEmpty { sendMessage() }
                        }
                } else {
                    TextField("Ask anything...", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($isInputFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isInputFocused ? accentColor : borderColor, lineWidth: 1)
                        )
                        .onSubmit {
                            if !inputText.isEmpty { sendMessage() }
                        }
                }
                
                // Send or Stop Button
                if agent.isLoading {
                    // STOP button
                    Button(action: { agent.stopGeneration() }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .cornerRadius(8)
                            .shadow(color: .red.opacity(0.3), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .help("Stop Generation")
                } else {
                    // SEND button
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .cornerRadius(8)
                            .shadow(color: .purple.opacity(0.3), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
                    .opacity((inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty) ? 0.4 : 1.0)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            // Queue indicator
            Group {
                if !agent.messageQueue.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                        Text("\(agent.messageQueue.count) message\(agent.messageQueue.count > 1 ? "s" : "") queued")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Spacer()
                        Button("Clear Queue") { agent.messageQueue.removeAll() }
                            .font(.system(size: 9))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                }
            }
            .background(paneColor)
        }
    }
    
    // MARK: - Agent Phase Bar (Animated Status)
    
    private var agentPhaseBar: some View {
        HStack(spacing: 8) {
            // Animated indicator
            Circle()
                .fill(agent.agentPhase.color)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(agent.agentPhase.color.opacity(0.5), lineWidth: 2)
                        .scaleEffect(agent.agentPhase == .idle ? 1.0 : 1.5)
                        .opacity(agent.agentPhase == .idle ? 0 : 0.5)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: agent.agentPhase)
                )
            
            Image(systemName: agent.agentPhase.icon)
                .font(.system(size: 10))
                .foregroundColor(agent.agentPhase.color)
            
            Text(agent.agentPhase.displayText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(agent.agentPhase.color)
            
            Spacer()
            
            // Files modified counter
            if !agent.filesModified.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "doc.badge.arrow.up")
                        .font(.system(size: 9))
                    Text("\(agent.filesModified.count) files")
                        .font(.system(size: 9))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(agent.agentPhase.color.opacity(0.05))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    // MARK: - Suggested Action Bar
    
    private func suggestedActionBar(_ suggestion: SuggestedAction) -> some View {
        HStack(spacing: 8) {
            Image(systemName: suggestion.icon)
                .font(.system(size: 14))
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
                Text(suggestion.description)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                // TODO: Run project command
                inputText = "Run the project and show me the output"
                sendMessage()
                agent.suggestedAction = nil
            }) {
                Text("Run")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            
            Button(action: { agent.suggestedAction = nil }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.08))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Activity Log Strip
    
    private var activityLogStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Token savings indicator
                let stats = TokenOptimizer.shared.stats
                if stats.savedTokens > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.green)
                        Text("\(stats.formattedSavings)")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(3)
                }
                
                // Memory count
                let memCount = AgentMemoryService.shared.memories.count
                if memCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "brain")
                            .font(.system(size: 8))
                            .foregroundColor(.purple)
                        Text("\(memCount)")
                            .font(.system(size: 8))
                            .foregroundColor(.purple)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.06))
                    .cornerRadius(3)
                }
                
                ForEach(agent.activityLog.suffix(8)) { activity in
                    HStack(spacing: 3) {
                        Image(systemName: activity.type.icon)
                            .font(.system(size: 8))
                            .foregroundColor(activity.type.color)
                        Text(activity.message)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(activity.type.color.opacity(0.06))
                    .cornerRadius(3)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 22)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - File Attachment Logic
    
    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                processFile(url)
            }
        }
    }
    
    private func processFile(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.lowercased()
            let fileName = url.lastPathComponent
            
            var type: AIAttachment.AttachmentType = .text
            
            if ["png", "jpg", "jpeg", "webp", "heic"].contains(ext) {
                type = .image(format: ext == "jpg" ? "jpeg" : ext)
            } else if ext == "pdf" {
                type = .pdf
            } else {
                type = .text // Default to text for code files
            }
            
            let attachment = AIAttachment(name: fileName, data: data, type: type)
            attachments.append(attachment)
        } catch {
            print("Failed to read file: \(error)")
        }
    }
    
    private func fileIcon(for type: AIAttachment.AttachmentType) -> String {
        switch type {
        case .image: return "photo"
        case .pdf: return "doc.text.fill" // Generic doc
        case .text: return "doc.text"
        }
    }
    
    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { return }
        let userText = inputText
        let currentAttachments = attachments
        
        inputText = ""
        attachments = []
        
        // If AI is busy, queue the message
        if agent.isLoading {
            agent.enqueueMessage(userText, attachments: currentAttachments)
            return
        }
        
        executeMessage(userText, attachments: currentAttachments)
    }
    
    private func executeMessage(_ userText: String, attachments currentAttachments: [AIAttachment] = []) {
        
        // Update editor context
        if let file = appState.currentFile {
            agent.updateEditorContext(
                activeFile: file.path,
                content: file.content,
                cursorLine: nil,
                selectedText: nil,
                openFiles: appState.openFiles.map { $0.path },
                language: file.language
            )
        }
        
        // Set workspace
        if let workspace = appState.workspaceFolder {
            agent.setWorkspace(workspace.path)
        }
        
        let providerString = appState.aiProvider
        let model = appState.aiModel.isEmpty ? (StreamableAIProvider(rawValue: providerString) ?? .gemini).defaultModel : appState.aiModel
        let apiKey = appState.apiKeys[providerString] ?? ""
        
        if appState.agentMode {
            // Agent Mode: Use AgentService pipeline (tool execution + agentic loop)
            Task {
                await agent.sendMessage(
                    userText,
                    provider: providerString,
                    model: model,
                    apiKey: apiKey,
                    attachments: currentAttachments
                )
            }
        } else {
            // Simple Chat Mode: Direct AIClient streaming
            let userMessage = AgentMessageModel(
                id: UUID().uuidString, role: .user,
                content: userText + (currentAttachments.isEmpty ? "" : "\n[Attached: \(currentAttachments.map(\.name).joined(separator: ", "))]"),
                toolResults: [], pendingChanges: [], timestamp: Date()
            )
            agent.messages.append(userMessage)
            
            let responseId = UUID().uuidString
            agent.messages.append(AgentMessageModel(
                id: responseId, role: .assistant, content: "",
                toolResults: [], pendingChanges: [], timestamp: Date()
            ))
            agent.isLoading = true
            
            let provider: StreamableAIProvider = StreamableAIProvider(rawValue: providerString) ?? .gemini
            let history: [(role: String, content: String)] = agent.messages.dropLast(2)
                .filter { $0.role == .user || $0.role == .assistant }
                .filter { !$0.content.isEmpty }
                .map { (role: $0.role.rawValue, content: $0.content) }
            
            AIClient.shared.sendMessage(
                prompt: userText,
                attachments: currentAttachments,
                systemPrompt: "You are MicroCode AI \u{2014} a professional software engineering assistant integrated into the MicroCode IDE. Maintain a professional, clear, and authoritative tone. Provide well-structured, accurate responses with precise technical terminology. When the user asks about code, act as a senior software engineer providing production-quality solutions with clear code blocks. When the user writes in Thai, respond in Thai. When in English, respond in English. Be thorough but concise.",
                conversationHistory: history,
                provider: provider,
                model: model,
                apiKey: apiKey,
                onToken: { token in
                    if let idx = self.agent.messages.firstIndex(where: { $0.id == responseId }) {
                        let current = self.agent.messages[idx].content
                        self.agent.messages[idx] = AgentMessageModel(
                            id: responseId, role: .assistant, content: current + token,
                            toolResults: [], pendingChanges: [], timestamp: Date()
                        )
                    }
                },
                onComplete: { _ in self.agent.isLoading = false },
                onError: { error in
                    if let idx = self.agent.messages.firstIndex(where: { $0.id == responseId }) {
                        self.agent.messages[idx] = AgentMessageModel(
                            id: responseId, role: .assistant, content: "Error: \(error)",
                            toolResults: [], pendingChanges: [], timestamp: Date()
                        )
                    }
                    self.agent.isLoading = false
                }
            )
        }
    }
    
    // MARK: - Apply / Reject Pending Changes
    
    private func applyChange(_ change: PendingChangeModel) {
        // Write the new content to the file
        do {
            let url = URL(fileURLWithPath: change.filePath)
            
            // Ensure parent directory exists
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            try change.newContent.write(to: url, atomically: true, encoding: .utf8)
            
            // Update status in agent messages
            updateChangeStatus(change, newStatus: .accepted)
            
            // Reload file in editor if it's currently open
            if let currentFile = appState.currentFile, currentFile.path == change.filePath {
                Task { @MainActor in
                    await appState.loadFile(url: url)
                }
            }
            
            print("✅ Applied change to \(change.filePath)")
        } catch {
            print("❌ Failed to apply change: \(error)")
        }
    }
    
    private func rejectChange(_ change: PendingChangeModel) {
        updateChangeStatus(change, newStatus: .rejected)
        print("❌ Rejected change to \(change.filePath)")
    }
    
    private func updateChangeStatus(_ change: PendingChangeModel, newStatus: PendingChangeModel.PendingChangeStatus) {
        // Find and update the change in agent messages
        for (msgIdx, msg) in agent.messages.enumerated() {
            if let changeIdx = msg.pendingChanges.firstIndex(where: { $0.id == change.id }) {
                var updatedChanges = msg.pendingChanges
                updatedChanges[changeIdx].status = newStatus
                
                // Rebuild message with updated changes
                let updatedMsg = AgentMessageModel(
                    id: msg.id,
                    role: msg.role,
                    content: msg.content,
                    toolResults: msg.toolResults,
                    pendingChanges: updatedChanges,
                    timestamp: msg.timestamp
                )
                agent.messages[msgIdx] = updatedMsg
                break
            }
        }
    }
    
    // MARK: - Model Selector
    
    private var modelSelector: some View {
        Menu {
            modelMenuContent
        } label: {
            HStack(spacing: 5) {
                // Provider icon with color
                providerIcon(for: appState.aiProvider)
                    .font(.system(size: 10, weight: .semibold))
                
                Text(appState.aiModel.isEmpty ? "Auto" : shortModelName(appState.aiModel))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                
                // Connection status dot
                Circle()
                    .fill(hasActiveKey(appState.aiProvider) ? Color.green : Color.orange)
                    .frame(width: 5, height: 5)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 7))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.05))
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Select AI Model")
    }
    
    @ViewBuilder
    private func providerIcon(for provider: String) -> some View {
        switch provider {
        case "gemini":    Image(systemName: "sparkles").foregroundColor(.purple)
        case "openai":    Image(systemName: "brain.head.profile").foregroundColor(.green)
        case "anthropic": Image(systemName: "bubble.left.and.text.bubble.right").foregroundColor(.orange)
        case "deepseek":  Image(systemName: "water.waves").foregroundColor(.blue)
        case "grok":      Image(systemName: "bolt.fill").foregroundColor(.red)
        case "codex":     Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundColor(.cyan)
        case "local":     Image(systemName: "desktopcomputer").foregroundColor(.mint)
        default:          Image(systemName: "cpu").foregroundColor(.accentColor)
        }
    }
    
    private func hasActiveKey(_ provider: String) -> Bool {
        if provider == "local" {
            return LocalLLMService.shared.activeServer?.isOnline == true
        }
        return !(appState.apiKeys[provider]?.isEmpty ?? true)
    }
    
    @ViewBuilder
    private var modelMenuContent: some View {
        // ── Cloud Providers ──
        Label("Cloud Providers", systemImage: "cloud.fill")
            .font(.caption2).foregroundColor(.secondary)
        
        // Gemini
        Menu {
            ForEach(["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"], id: \.self) { model in
                Button(action: { setModel("gemini", model) }) {
                    HStack {
                        Text(model)
                        if appState.aiModel == model { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Label {
                HStack {
                    Text("Google Gemini")
                    Spacer()
                    if hasActiveKey("gemini") {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 9))
                    }
                }
            } icon: {
                Image(systemName: "sparkles").foregroundColor(.purple)
            }
        }
        
        // Claude (Anthropic)
        Menu {
            ForEach(["claude-sonnet-4-20250514", "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"], id: \.self) { model in
                Button(action: { setModel("anthropic", model) }) {
                    HStack {
                        Text(model)
                        if appState.aiModel == model { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Label {
                HStack {
                    Text("Claude (Anthropic)")
                    Spacer()
                    if hasActiveKey("anthropic") {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 9))
                    }
                }
            } icon: {
                Image(systemName: "bubble.left.and.text.bubble.right").foregroundColor(.orange)
            }
        }
        
        // OpenAI (ChatGPT)
        Menu {
            ForEach(["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini", "o4-mini", "o3-mini"], id: \.self) { model in
                Button(action: { setModel("openai", model) }) {
                    HStack {
                        Text(model)
                        if appState.aiModel == model { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Label {
                HStack {
                    Text("OpenAI / ChatGPT")
                    Spacer()
                    if hasActiveKey("openai") {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 9))
                    }
                }
            } icon: {
                Image(systemName: "brain.head.profile").foregroundColor(.green)
            }
        }
        
        // DeepSeek
        Menu {
            ForEach(["deepseek-chat", "deepseek-reasoner"], id: \.self) { model in
                Button(action: { setModel("deepseek", model) }) {
                    HStack {
                        Text(model)
                        if appState.aiModel == model { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Label {
                HStack {
                    Text("DeepSeek")
                    Spacer()
                    if hasActiveKey("deepseek") {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 9))
                    }
                }
            } icon: {
                Image(systemName: "water.waves").foregroundColor(.blue)
            }
        }
        
        // Grok
        Menu {
            ForEach(["grok-3", "grok-3-mini", "grok-2"], id: \.self) { model in
                Button(action: { setModel("grok", model) }) {
                    HStack {
                        Text(model)
                        if appState.aiModel == model { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Label {
                HStack {
                    Text("Grok (xAI)")
                    Spacer()
                    if hasActiveKey("grok") {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 9))
                    }
                }
            } icon: {
                Image(systemName: "bolt.fill").foregroundColor(.red)
            }
        }
        
        // Codex
        Menu {
            ForEach(["codex-mini-latest", "o4-mini"], id: \.self) { model in
                Button(action: { setModel("openai", model) }) {
                    HStack {
                        Text(model)
                        if appState.aiModel == model { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Label("Codex (OpenAI)", systemImage: "chevron.left.forwardslash.chevron.right")
                .foregroundColor(.cyan)
        }
        
        // Other (Qwen, GLM)
        Menu {
            Button("qwen-max") { setModel("qwen", "qwen-max") }
            Button("glm-4-plus") { setModel("glm", "glm-4-plus") }
        } label: {
            Label("Other Providers", systemImage: "ellipsis.circle")
        }
        
        Divider()
        
        // ── Local LLM ──
        Label("Local Models", systemImage: "desktopcomputer")
            .font(.caption2).foregroundColor(.secondary)
        
        let localModels = LocalLLMService.shared.availableModels
        if localModels.isEmpty {
            Button(action: { Task { await LocalLLMService.shared.scanForServers() } }) {
                Label("Scan for Local Models...", systemImage: "antenna.radiowaves.left.and.right")
            }
        } else {
            ForEach(localModels) { model in
                Button(action: { setModel("local", model.id) }) {
                    HStack {
                        Text(model.displayName)
                        if appState.aiModel == model.id { Image(systemName: "checkmark") }
                    }
                }
            }
            Divider()
            Button(action: { Task { await LocalLLMService.shared.scanForServers() } }) {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
        }
        
        Divider()
        
        // ── MCP Status ──
        let mcp = MCPServer.shared
        Label(
            mcp.isRunning ? "MCP Server: Running (\(mcp.requestCount) reqs)" : "MCP Server: Stopped",
            systemImage: mcp.isRunning ? "server.rack" : "xmark.circle"
        )
        .font(.caption2)
        .foregroundColor(mcp.isRunning ? .green : .secondary)
    }
    
    private func setModel(_ provider: String, _ model: String) {
        appState.aiProvider = provider
        appState.aiModel = model
    }
    
    private func shortModelName(_ model: String) -> String {
        // Shorten long model names for the header
        let parts = model.split(separator: "-")
        if parts.count > 2 {
            return parts.prefix(2).joined(separator: "-")
        }
        return model
    }
    
    // MARK: - Token Stats Badge
    
    private var tokenStatsBadge: some View {
        Menu {
            Text("📊 Token Optimizer Stats").font(.caption)
            Divider()
            
            let stats = TokenOptimizer.shared.stats
            Text("Input: \(formatTokenCount(stats.inputTokens))")
            Text("Output: \(formatTokenCount(stats.outputTokens))")
            Text("Saved: \(formatTokenCount(stats.savedTokens))")
            
            Divider()
            
            Text("Requests: \(stats.totalRequests)")
            Text("Cost: $\(String(format: "%.4f", stats.totalCost))")
            Text("Compression: \(String(format: "%.0f%%", stats.compressionRatio * 100))")
            
            Divider()
            
            // Memory stats
            let memStats = AgentMemoryService.shared
            Text("🧠 Memory: \(memStats.memories.count) entries")
            Text("Topics: \(memStats.topicClusters.count)")
            Text("Summaries: \(memStats.summaries.count)")
            
            Divider()
            
            Button("Reset Stats") {
                TokenOptimizer.shared.resetStats()
            }
            Button("Clear Memory") {
                AgentMemoryService.shared.clearAllMemories()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(tokenSavingsColor)
                
                let stats = TokenOptimizer.shared.stats
                if stats.savedTokens > 0 {
                    Text(stats.formattedSavings)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(tokenSavingsColor)
                } else {
                    Text("Optimizer")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tokenSavingsColor.opacity(0.08))
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Token Optimizer — \(TokenOptimizer.shared.stats.formattedSavings) saved")
    }
    
    private var tokenSavingsColor: Color {
        let ratio = TokenOptimizer.shared.stats.compressionRatio
        if ratio > 0.3 { return .green }
        if ratio > 0.1 { return .cyan }
        return .secondary
    }
    
    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}

// MARK: - Agent Cell Mode View

struct AgentCellModeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var agent = AgentService.shared
    @State private var cells: [AgentCell] = [AgentCell(type: .code)]
    @State private var focusedCellId: UUID? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Context Bar
            cellContextBar
            
            Divider()
            
            // Cells
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($cells) { $cell in
                            AgentCellRow(
                                cell: $cell,
                                isFocused: focusedCellId == cell.id,
                                onFocus: { focusedCellId = cell.id },
                                onRun: { runCell(cell) },
                                onDelete: { deleteCell(cell.id) },
                                onInsertBelow: { insertCell(below: cell.id) },
                                appState: appState
                            )
                            .id(cell.id)
                        }
                        
                        // Add Cell Button
                        addCellButton
                    }
                    .padding(.bottom, 100)
                }
                .onChange(of: cells.count) { _ in
                    if let lastId = cells.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
            }
        }
    }
    
    // MARK: - Context Bar
    
    private var cellContextBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.grid.1x2.fill")
                .font(.system(size: 10))
                .foregroundColor(.purple)
            
            Text("CELL MODE")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.5)
            
            Divider().frame(height: 12)
            
            // Workspace context
            if let workspace = appState.workspaceFolder {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                    Text(workspace.lastPathComponent)
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
            }
            
            // Current file context
            if let file = appState.currentFile {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 9))
                    Text(file.name)
                        .font(.system(size: 10))
                }
                .foregroundColor(.accentColor.opacity(0.8))
            }
            
            Spacer()
            
            // Model indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.aiProvider == "local" ? Color.green : Color.accentColor)
                    .frame(width: 6, height: 6)
                Text(appState.aiModel.isEmpty ? "Auto" : appState.aiModel)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            
            Text("\(cells.count) cells")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.05))
                .cornerRadius(3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }
    
    // MARK: - Add Cell
    
    private var addCellButton: some View {
        HStack {
            Button(action: { cells.append(AgentCell(type: .code)) }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Code")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Button(action: { cells.append(AgentCell(type: .markdown)) }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                    Text("Markdown")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Button(action: { cells.append(AgentCell(type: .ai)) }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                    Text("AI Prompt")
                }
                .font(.system(size: 11))
                .foregroundColor(.purple.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Cell Actions
    
    private func runCell(_ cell: AgentCell) {
        guard let idx = cells.firstIndex(where: { $0.id == cell.id }) else { return }
        
        cells[idx].isRunning = true
        cells[idx].output = ""
        
        let providerString = appState.aiProvider
        let model = appState.aiModel.isEmpty ? (StreamableAIProvider(rawValue: providerString) ?? .gemini).defaultModel : appState.aiModel
        let apiKey = appState.apiKeys[providerString] ?? ""
        let provider: StreamableAIProvider = StreamableAIProvider(rawValue: providerString) ?? .gemini
        
        // Build context from workspace + current file + previous cells
        var context = ""
        if let file = appState.currentFile {
            context += "Current file: \(file.name) (\(file.language))\n```\(file.language)\n\(file.content.prefix(3000))\n```\n\n"
        }
        
        // Gather previous cell outputs as context
        for prevCell in cells where prevCell.id != cell.id {
            if !prevCell.input.isEmpty {
                let label = prevCell.type == .ai ? "AI Prompt" : prevCell.type == .code ? "Code" : "Note"
                context += "[\(label)]: \(prevCell.input.prefix(500))\n"
                if !prevCell.output.isEmpty {
                    context += "[Output]: \(prevCell.output.prefix(500))\n"
                }
            }
        }
        
        let systemPrompt: String
        let userPrompt: String
        
        switch cell.type {
        case .ai:
            systemPrompt = "You are MicroCode AI. You have context from the user's workspace. Respond concisely and accurately. Use code blocks for code."
            userPrompt = context + "\nUser request: " + cell.input
        case .code:
            systemPrompt = "You are a code execution assistant. Analyze the code, explain what it does, and provide the expected output. If there are errors, explain them."
            userPrompt = context + "\nAnalyze and run this code:\n```\n\(cell.input)\n```"
        case .markdown:
            // Markdown cells don't need AI - just render
            cells[idx].isRunning = false
            cells[idx].output = cell.input
            return
        }
        
        let cellId = cell.id
        AIClient.shared.sendMessage(
            prompt: userPrompt,
            systemPrompt: systemPrompt,
            conversationHistory: [],
            provider: provider,
            model: model,
            apiKey: apiKey,
            onToken: { token in
                if let i = self.cells.firstIndex(where: { $0.id == cellId }) {
                    self.cells[i].output += token
                }
            },
            onComplete: { _ in
                if let i = self.cells.firstIndex(where: { $0.id == cellId }) {
                    self.cells[i].isRunning = false
                }
            },
            onError: { error in
                if let i = self.cells.firstIndex(where: { $0.id == cellId }) {
                    self.cells[i].output = "❌ Error: \(error)"
                    self.cells[i].isRunning = false
                }
            }
        )
    }
    
    private func deleteCell(_ id: UUID) {
        if let idx = cells.firstIndex(where: { $0.id == id }) {
            cells.remove(at: idx)
        }
    }
    
    private func insertCell(below id: UUID) {
        if let idx = cells.firstIndex(where: { $0.id == id }) {
            cells.insert(AgentCell(type: .code), at: idx + 1)
        }
    }
}

// MARK: - Agent Cell Model

struct AgentCell: Identifiable {
    let id = UUID()
    var type: CellType
    var input: String = ""
    var output: String = ""
    var isRunning: Bool = false
    var language: String = "swift"
    
    enum CellType: String {
        case code = "code"
        case markdown = "markdown"
        case ai = "ai"
        
        var icon: String {
            switch self {
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .markdown: return "doc.richtext"
            case .ai: return "sparkles"
            }
        }
        
        var color: Color {
            switch self {
            case .code: return .blue
            case .markdown: return .orange
            case .ai: return .purple
            }
        }
        
        var label: String {
            switch self {
            case .code: return "Code"
            case .markdown: return "Markdown"
            case .ai: return "AI"
            }
        }
    }
}

// MARK: - Agent Cell Row

struct AgentCellRow: View {
    @Binding var cell: AgentCell
    let isFocused: Bool
    let onFocus: () -> Void
    let onRun: () -> Void
    let onDelete: () -> Void
    let onInsertBelow: () -> Void
    let appState: AppState
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Cell Header
            cellHeader
            
            // Input Area
            cellInput
            
            // Output Area
            if !cell.output.isEmpty || cell.isRunning {
                cellOutput
            }
            
            // Bottom Divider
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
        }
        .background(isFocused ? Color.accentColor.opacity(0.03) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)
        .onHover { isHovering = $0 }
    }
    
    private var cellHeader: some View {
        HStack(spacing: 6) {
            // Cell Type Badge
            HStack(spacing: 4) {
                Image(systemName: cell.type.icon)
                    .font(.system(size: 9))
                Text(cell.type.label)
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(cell.type.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(cell.type.color.opacity(0.1))
            .cornerRadius(3)
            
            // Language selector for code cells
            if cell.type == .code {
                Menu {
                    ForEach(["swift", "python", "javascript", "typescript", "rust", "go", "bash", "sql"], id: \.self) { lang in
                        Button(lang) { cell.language = lang }
                    }
                } label: {
                    Text(cell.language)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(2)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            
            Spacer()
            
            // Actions (show on hover)
            if isHovering || isFocused {
                HStack(spacing: 2) {
                    // Run Button
                    Button(action: onRun) {
                        Image(systemName: cell.isRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 10))
                            .foregroundColor(cell.isRunning ? .red : .green)
                    }
                    .buttonStyle(.plain)
                    .help("Run Cell")
                    
                    // Insert Below
                    Button(action: onInsertBelow) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Insert Cell Below")
                    
                    // Delete
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete Cell")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }
    
    private var cellInput: some View {
        TextEditor(text: $cell.input)
            .font(.system(size: 12, design: cell.type == .code ? .monospaced : .default))
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .frame(minHeight: 44, maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
    
    @ViewBuilder
    private var cellOutput: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Output Header
            HStack(spacing: 4) {
                Image(systemName: cell.isRunning ? "circle.dotted" : "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(cell.isRunning ? .orange : .green)
                Text(cell.isRunning ? "Running..." : "Output")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.03))
            
            // Output Content
            if cell.isRunning && cell.output.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Processing...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(12)
            } else {
                ScrollView {
                    Text(cell.output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.9))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 300)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.3))
    }
}

// MARK: - Header Button (Reusable)

struct HeaderIconButton: View {
    let icon: String
    let label: String?
    var isActive: Bool = false
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isActive {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                
                if let text = label {
                    Text(text)
                        .font(.system(size: 11))
                }
            }
            .foregroundColor(isHovering || isActive ? .primary : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(isHovering ? Color.white.opacity(0.1) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Rich Message Renderer

enum MessageBlock: Identifiable {
    case text(String)
    case code(String, String) // Language, Content
    case heading(Int, String) // Level (1-6), Content
    case list([String], Bool) // Items, isOrdered
    case blockquote(String)
    case latex(String, Bool) // Expression, isBlock ($$...$$ vs $...$)
    case html(String)
    
    var id: String {
        switch self {
        case .text(let c): return "text-\(c.hashValue)"
        case .code(let l, let c): return "code-\(l)-\(c.hashValue)"
        case .heading(let lv, let c): return "h\(lv)-\(c.hashValue)"
        case .list(let items, _): return "list-\(items.hashValue)"
        case .blockquote(let c): return "quote-\(c.hashValue)"
        case .latex(let e, _): return "latex-\(e.hashValue)"
        case .html(let c): return "html-\(c.hashValue)"
        }
    }
}

struct MessageContentParser {
    static func parse(_ content: String) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        var remaining = content
        
        // First, extract LaTeX blocks ($$...$$) - can be multi-line
        // First, extract LaTeX blocks ($$...$$ or \[...\])
        // Regex captures content INSIDE the delimiters
        let latexPattern = "\\$\\$([\\s\\S]*?)\\$\\$|\\\\\\[([\\s\\S]*?)\\\\\\]"
        if let latexRegex = try? NSRegularExpression(pattern: latexPattern, options: []) {
            let nsContent = remaining as NSString
            let latexMatches = latexRegex.matches(in: remaining, options: [], range: NSRange(location: 0, length: nsContent.length))
            
            var processedRanges: [NSRange] = []
            var lastEnd = 0
            var tempBlocks: [MessageBlock] = []
            
            for match in latexMatches {
                // Text before LaTeX block
                if match.range.location > lastEnd {
                    let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                    let beforeText = nsContent.substring(with: beforeRange)
                    tempBlocks.append(.text(beforeText))
                }
                
                // LaTeX block content (check which group matched)
                var latexContent = ""
                if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                    latexContent = nsContent.substring(with: match.range(at: 1))
                } else if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                    latexContent = nsContent.substring(with: match.range(at: 2))
                }
                
                tempBlocks.append(.latex(latexContent.trimmingCharacters(in: .whitespacesAndNewlines), true))
                
                lastEnd = match.range.location + match.range.length
                processedRanges.append(match.range)
            }
            
            // Remaining text
            if lastEnd < nsContent.length {
                let afterText = nsContent.substring(from: lastEnd)
                tempBlocks.append(.text(afterText))
            }
            
            // If we found LaTeX blocks, process the text portions for code blocks
            if !processedRanges.isEmpty {
                for block in tempBlocks {
                    switch block {
                    case .text(let text):
                        blocks.append(contentsOf: parseCodeBlocks(text))
                    default:
                        blocks.append(block)
                    }
                }
                return blocks
            }
        }
        
        // No LaTeX blocks found, process code blocks
        blocks.append(contentsOf: parseCodeBlocks(remaining))
        return blocks
    }
    
    private static func parseCodeBlocks(_ content: String) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        
        // Extract code blocks, converting latex/math to LaTeX blocks
        let codePattern = "```([a-zA-Z0-9]*)\\n([\\s\\S]*?)```"
        if let regex = try? NSRegularExpression(pattern: codePattern, options: []) {
            let nsContent = content as NSString
            let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))
            
            var lastEnd = 0
            for match in matches {
                // Text before code block
                if match.range.location > lastEnd {
                    let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                    let beforeText = nsContent.substring(with: beforeRange)
                    blocks.append(contentsOf: parseTextContent(beforeText))
                }
                
                // Code block
                let langRange = match.range(at: 1)
                let codeRange = match.range(at: 2)
                let lang = langRange.location != NSNotFound ? nsContent.substring(with: langRange) : ""
                let code = codeRange.location != NSNotFound ? nsContent.substring(with: codeRange) : ""
                let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Check if this is a LaTeX/math code block - render as LaTeX
                if lang.lowercased() == "latex" || lang.lowercased() == "math" || lang.lowercased() == "tex" {
                    blocks.append(.latex(trimmedCode, true))
                } else {
                    blocks.append(.code(lang, trimmedCode))
                }
                
                lastEnd = match.range.location + match.range.length
            }
            
            // Remaining text after last code block
            if lastEnd < nsContent.length {
                let afterText = nsContent.substring(from: lastEnd)
                blocks.append(contentsOf: parseTextContent(afterText))
            }
        } else {
            // Fallback: simple split
            blocks.append(contentsOf: parseTextContent(content))
        }
        
        return blocks
    }
    
    private static func parseTextContent(_ text: String) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        let lines = text.components(separatedBy: "\n")
        var currentText: [String] = []
        var listItems: [String] = []
        var isOrderedList = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check for headings (# H1, ## H2, etc.)
            if let match = trimmed.range(of: "^#{1,6}\\s+", options: .regularExpression) {
                // Flush current text
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.joined(separator: "\n")))
                    currentText = []
                }
                // Flush list
                if !listItems.isEmpty {
                    blocks.append(.list(listItems, isOrderedList))
                    listItems = []
                }
                
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let heading = String(trimmed[match.upperBound...])
                blocks.append(.heading(level, heading))
                continue
            }
            
            // Check for block LaTeX ($$...$$)
            if trimmed.hasPrefix("$$") && trimmed.hasSuffix("$$") && trimmed.count > 4 {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.joined(separator: "\n")))
                    currentText = []
                }
                let latex = String(trimmed.dropFirst(2).dropLast(2))
                blocks.append(.latex(latex, true))
                continue
            }
            
            // Check for blockquote (> ...)
            if trimmed.hasPrefix("> ") {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.joined(separator: "\n")))
                    currentText = []
                }
                if !listItems.isEmpty {
                    blocks.append(.list(listItems, isOrderedList))
                    listItems = []
                }
                blocks.append(.blockquote(String(trimmed.dropFirst(2))))
                continue
            }
            
            // Check for unordered list (- or * item)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.joined(separator: "\n")))
                    currentText = []
                }
                isOrderedList = false
                listItems.append(String(trimmed.dropFirst(2)))
                continue
            }
            
            // Check for ordered list (1. item)
            if let _ = trimmed.range(of: "^\\d+\\.\\s+", options: .regularExpression) {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.joined(separator: "\n")))
                    currentText = []
                }
                isOrderedList = true
                listItems.append(String(trimmed.drop(while: { $0.isNumber || $0 == "." || $0 == " " })))
                continue
            }
            
            // Flush list if we hit non-list line
            if !listItems.isEmpty && !trimmed.isEmpty {
                blocks.append(.list(listItems, isOrderedList))
                listItems = []
            }
            
            // Regular text
            currentText.append(line)
        }
        
        // Flush remaining
        if !listItems.isEmpty {
            blocks.append(.list(listItems, isOrderedList))
        }
        if !currentText.isEmpty {
            let joined = currentText.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.text(joined))
            }
        }
        
        return blocks
    }
}

// MARK: - Chat Stage

struct AgentChatStage: View {
    let messages: [AgentMessageModel]
    let isLoading: Bool
    var currentToolExecution: String? = nil
    var onApplyChange: ((PendingChangeModel) -> Void)? = nil
    var onRejectChange: ((PendingChangeModel) -> Void)? = nil
    var onSuggestionTap: ((String) -> Void)? = nil
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if messages.isEmpty && !isLoading {
                        VStack(spacing: 20) {
                            Spacer().frame(height: 40)
                            
                            // Animated sparkle icon
                            ZStack {
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [.purple.opacity(0.15), .blue.opacity(0.05), .clear],
                                            center: .center,
                                            startRadius: 10,
                                            endRadius: 60
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                
                                Image(systemName: "sparkles")
                                    .font(.system(size: 36, weight: .light))
                                    .foregroundStyle(
                                        LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                            }
                            
                            VStack(spacing: 6) {
                                Text("MicroCode AI")
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary.opacity(0.8))
                                
                                Text("Ask anything, write code, debug, or explore ideas")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            
                            // Quick suggestions
                            VStack(spacing: 8) {
                                ForEach([
                                    ("Explain this code", "doc.text.magnifyingglass"),
                                    ("Find bugs in my project", "ladybug"),
                                    ("Refactor for performance", "gauge.with.dots.needle.67percent"),
                                    ("Write unit tests", "checkmark.shield")
                                ], id: \.0) { suggestion, icon in
                                    Button(action: {
                                        onSuggestionTap?(suggestion)
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: icon)
                                                .font(.system(size: 10))
                                                .foregroundColor(.purple)
                                                .frame(width: 16)
                                            Text(suggestion)
                                                .font(.system(size: 11))
                                                .foregroundColor(.primary.opacity(0.7))
                                            Spacer()
                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 8))
                                                .foregroundColor(.secondary.opacity(0.4))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Color.white.opacity(0.03))
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                            
                            Spacer()
                        }
                    } else {
                        ForEach(messages) { message in
                            RichMessageRow(message: message, onApplyChange: onApplyChange, onRejectChange: onRejectChange)
                                .id(message.id)
                        }
                    }
                    
                    if isLoading {
                        AgentThinkingView(currentTool: currentToolExecution)
                            .id("thinking-indicator")
                    }
                }
                .padding(.bottom, 120)
            }
            .onChange(of: messages.count) { _ in
                if let lastId = messages.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
            .onChange(of: currentToolExecution) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo("thinking-indicator", anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - A4 Paper Reading Mode

struct A4PaperView: View {
    let messages: [AgentMessageModel]
    @Binding var currentPage: Int
    
    // A4 Paper dimensions at 72dpi (scaled for display)
    private let paperWidth: CGFloat = 595 * 0.9
    private let paperHeight: CGFloat = 842 * 0.9
    private let paperMargin: CGFloat = 48
    
    // Combine all message content into pages
    private var allContent: String {
        messages.map { $0.content }.joined(separator: "\n\n---\n\n")
    }
    
    // Rough estimate: ~60 chars per line, ~45 lines per page
    private var totalPages: Int {
        max(1, (allContent.count / 2700) + 1)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Paper Container
            ScrollView {
                VStack(spacing: 24) {
                    // The Paper
                    ZStack {
                        // Paper Shadow
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.3))
                            .offset(x: 4, y: 4)
                            .blur(radius: 8)
                        
                        // Paper Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                        
                        // Paper Content
                        VStack(alignment: .leading, spacing: 16) {
                            // Header
                            if currentPage == 0 {
                                VStack(alignment: .center, spacing: 8) {
                                    Text("MicroCode Agent")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.black)
                                    Text("Generated Report")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                    Text(Date().formatted(date: .long, time: .shortened))
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 16)
                                
                                Divider().background(Color.gray.opacity(0.3))
                            }
                            
                            // Content
                            PaperContentView(content: allContent, page: currentPage)
                            
                            Spacer()
                            
                            // Footer
                            HStack {
                                Spacer()
                                Text("Page \(currentPage + 1) of \(totalPages)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(paperMargin)
                    }
                    .frame(width: paperWidth, height: paperHeight)
                }
                .padding(32)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            
            // Page Navigation Bar
            HStack(spacing: 16) {
                Button(action: { if currentPage > 0 { currentPage -= 1 }}) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(currentPage == 0)
                .foregroundColor(currentPage > 0 ? .accentColor : .secondary.opacity(0.5))
                
                // Page Dots
                HStack(spacing: 6) {
                    ForEach(0..<min(totalPages, 10), id: \.self) { page in
                        Circle()
                            .fill(page == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .onTapGesture { currentPage = page }
                    }
                    if totalPages > 10 {
                        Text("...")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: { if currentPage < totalPages - 1 { currentPage += 1 }}) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(currentPage >= totalPages - 1)
                .foregroundColor(currentPage < totalPages - 1 ? .accentColor : .secondary.opacity(0.5))
                
                Spacer()
                
                // Export Button
                Button(action: {
                    // TODO: Export to PDF
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 10))
                        Text("Export PDF")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

// MARK: - Paper Content Renderer

struct PaperContentView: View {
    let content: String
    let page: Int
    
    private let charsPerPage = 2700
    
    private var pageContent: String {
        let startIndex = page * charsPerPage
        guard startIndex < content.count else { return "" }
        
        let start = content.index(content.startIndex, offsetBy: startIndex)
        let endOffset = min(startIndex + charsPerPage, content.count)
        let end = content.index(content.startIndex, offsetBy: endOffset)
        
        return String(content[start..<end])
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Parse and render content blocks
            let blocks = MessageContentParser.parse(pageContent)
            
            ForEach(blocks) { block in
                switch block {
                case .text(let text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        PaperTextView(text: text)
                    }
                    
                case .code(let lang, let code):
                    PaperCodeBlockView(language: lang, code: code)
                    
                case .heading(let level, let heading):
                    Text(heading)
                        .font(.system(size: paperHeadingSize(level), weight: .bold))
                        .foregroundColor(.black)
                        .padding(.top, level <= 2 ? 12 : 6)
                    
                case .list(let items, let isOrdered):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(items.indices, id: \.self) { i in
                            HStack(alignment: .top, spacing: 8) {
                                Text(isOrdered ? "\(i + 1)." : "•")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                                Text(items[i])
                                    .font(.system(size: 11))
                                    .foregroundColor(.black)
                            }
                        }
                    }
                    
                case .blockquote(let quote):
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: 2)
                        Text(quote)
                            .font(.system(size: 11))
                            .italic()
                            .foregroundColor(.gray)
                            .padding(.leading, 8)
                    }
                    
                case .latex(let expr, let isBlock):
                    // Show LaTeX as styled text with formula indicators
                    PaperLaTeXView(expression: expr, isBlock: isBlock)
                    
                case .html(let html):
                    Text(html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                        .font(.system(size: 11))
                        .foregroundColor(.black)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func paperHeadingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 18
        case 2: return 15
        case 3: return 13
        default: return 11
        }
    }
}

// MARK: - Paper Text View (Print-friendly)

struct PaperTextView: View {
    let text: String
    
    var body: some View {
        Text(parsedText)
            .font(.system(size: 11))
            .foregroundColor(.black)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var parsedText: AttributedString {
        var str = AttributedString(text)
        let nsText = text as NSString
        
        // Bold
        if let regex = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: []) {
            for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
                let matched = nsText.substring(with: match.range)
                if let range = str.range(of: matched) {
                    str[range].font = .system(size: 11, weight: .bold)
                }
            }
        }
        
        // Italic
        if let regex = try? NSRegularExpression(pattern: "(?<![*])\\*([^*]+)\\*(?![*])", options: []) {
            for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
                let matched = nsText.substring(with: match.range)
                if let range = str.range(of: matched) {
                    str[range].font = .system(size: 11).italic()
                }
            }
        }
        
        // Inline code
        if let regex = try? NSRegularExpression(pattern: "`([^`]+)`", options: []) {
            for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
                let matched = nsText.substring(with: match.range)
                if let range = str.range(of: matched) {
                    str[range].font = .system(size: 10, design: .monospaced)
                    str[range].backgroundColor = Color.gray.opacity(0.15)
                }
            }
        }
        
        // Inline LaTeX ($...$)
        if let regex = try? NSRegularExpression(pattern: "\\$([^$]+)\\$", options: []) {
            for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
                let matched = nsText.substring(with: match.range)
                if let range = str.range(of: matched) {
                    str[range].font = .system(size: 11).italic()
                    str[range].foregroundColor = .blue
                }
            }
        }
        
        return str
    }
}

// MARK: - Paper Code Block View

struct PaperCodeBlockView: View {
    let language: String
    let code: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Re-use the native code block view but force light mode for paper aesthetic
            NativeCodeBlockView(language: language, code: code)
                .colorScheme(.light) // Force light mode for "Print/Paper" look
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

// MARK: - Paper LaTeX View

struct PaperLaTeXView: View {
    let expression: String
    let isBlock: Bool
    
    var body: some View {
        HStack {
            if isBlock { Spacer() }
            
            LatexBlockWebView(latex: expression, isBlock: isBlock)
                .frame(minHeight: isBlock ? 100 : 40) // Minimum height
                .fixedSize(horizontal: false, vertical: true) // Allow expansion if possible, or scroll
                .frame(maxWidth: isBlock ? .infinity : 300)
                .background(Color.clear)
            
            if isBlock { Spacer() }
        }
        .padding(.vertical, 4)
    }
}

struct LatexBlockWebView: NSViewRepresentable {
    let latex: String
    let isBlock: Bool
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // Transparent
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Prepare HTML for Light/Paper Mode
        let displayMode = isBlock ? "true" : "false"
        let fontSize = isBlock ? "1.2em" : "1.0em"
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
            <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
            <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/auto-render.min.js"></script>
            <style>
                body {
                    margin: 0;
                    padding: 4px;
                    background: transparent;
                    color: black;
                    font-family: 'Times New Roman', serif;
                    display: flex;
                    justify-content: \(isBlock ? "center" : "flex-start");
                    align-items: center;
                    height: 100vh;
                }
                .katex { font-size: \(fontSize); }
            </style>
        </head>
        <body>
            <div id="content"></div>
            <script>
                document.addEventListener("DOMContentLoaded", function() {
                    katex.render(String.raw`\(latex)`, document.getElementById('content'), {
                        throwOnError: false,
                        displayMode: \(displayMode)
                    });
                });
            </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - Rich Message Row

struct RichMessageRow: View {
    let message: AgentMessageModel
    var onApplyChange: ((PendingChangeModel) -> Void)? = nil
    var onRejectChange: ((PendingChangeModel) -> Void)? = nil
    
    private var isUser: Bool { message.role == .user }
    
    private var aiGradient: LinearGradient {
        LinearGradient(
            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        if isUser {
            userBubble
        } else {
            aiBubble
        }
    }
    
    // MARK: - User Bubble
    
    private var userBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Spacer(minLength: 40)
            
            VStack(alignment: .trailing, spacing: 4) {
                userBubbleContent
                    .padding(12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12, corners: [.topLeft, .topRight, .bottomLeft])
                
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Circle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var userBubbleContent: some View {
        let blocks = MessageContentParser.parse(message.content)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                userBlockView(block)
            }
        }
    }
    
    @ViewBuilder
    private func userBlockView(_ block: MessageBlock) -> some View {
        switch block {
        case .text(let text):
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white)
        case .code(let lang, let code):
            NativeCodeBlockView(language: lang, code: code)
        case .latex(let expression, _):
            Text(LocalizedStringKey(expression))
                .foregroundColor(.white.opacity(0.9))
        default:
            EmptyView()
        }
    }
    
    // MARK: - AI Bubble
    
    private var aiBubble: some View {
        HStack(alignment: .top, spacing: 12) {
            aiAvatar
            
            VStack(alignment: .leading, spacing: 6) {
                aiHeader
                aiBubbleContent
            }
            
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private var aiAvatar: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(aiGradient)
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: "command")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            )
            .shadow(color: Color.accentColor.opacity(0.2), radius: 4, y: 2)
            .padding(.top, 4)
    }
    
    private var aiHeader: some View {
        HStack {
            Text("MicroCode")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
            Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var aiBubbleContent: some View {
        let blocks = MessageContentParser.parse(message.content)
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks) { block in
                aiBlockView(block)
            }
            
            if !message.toolResults.isEmpty {
                ToolExecutionStepsView(results: message.toolResults)
            }
            
            if !message.pendingChanges.isEmpty {
                pendingChangesSection
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        .cornerRadius(12, corners: [.topRight, .bottomRight, .bottomLeft])
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                .mask(RoundedCornerShape(radius: 12, corners: [.topRight, .bottomRight, .bottomLeft]))
        )
    }
    
    @ViewBuilder
    private func aiBlockView(_ block: MessageBlock) -> some View {
        switch block {
        case .text(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MarkdownTextView(text: text)
            }
        case .code(let lang, let code):
            NativeCodeBlockView(language: lang, code: code)
        case .heading(let level, let content):
            HeadingView(level: level, content: content)
        case .list(let items, let isOrdered):
            ListView(items: items, isOrdered: isOrdered)
        case .blockquote(let content):
            BlockquoteView(content: content)
        case .latex(let expression, let isBlock):
            LaTeXBlockView(expression: expression, isBlock: isBlock)
        case .html(let content):
            HTMLBlockView(content: content)
        }
    }
    
    // MARK: - Pending Changes
    
    private var pendingChangesSection: some View {
        VStack(spacing: 8) {
            Text("Proposed Changes")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(message.pendingChanges) { change in
                PendingChangeCard(change: change, onApply: onApplyChange, onReject: onRejectChange)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Pending Change Card (Extracted for type-checker)

private struct PendingChangeCard: View {
    let change: PendingChangeModel
    var onApply: ((PendingChangeModel) -> Void)?
    var onReject: ((PendingChangeModel) -> Void)?
    @State private var showDiff = true  // Auto-expand diff
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            changeCardHeader
            
            // Always show diff stats bar
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("+\(change.additions) additions")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.green)
                }
                HStack(spacing: 3) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("-\(change.deletions) deletions")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.red)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.02))
            
            if showDiff {
                codeDiffSection
            } else {
                changeSummaryRow
            }
            
            if change.status == .pending {
                changeCardActions
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    change.status == .accepted ? Color.green.opacity(0.3) :
                    change.status == .rejected ? Color.red.opacity(0.3) :
                    Color.blue.opacity(0.2),
                    lineWidth: 1
                )
        )
    }
    
    private var changeCardHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: change.status == .accepted ? "checkmark.circle.fill" : change.status == .rejected ? "xmark.circle.fill" : "doc.badge.gearshape.fill")
                .foregroundColor(change.status == .accepted ? .green : change.status == .rejected ? .red : .blue)
                .font(.system(size: 13))
            
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: change.filePath).lastPathComponent)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text(change.description)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Toggle diff
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showDiff.toggle() } }) {
                Image(systemName: showDiff ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            
            changeCardStatusLabel
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [
                    change.status == .accepted ? Color.green.opacity(0.05) :
                    change.status == .rejected ? Color.red.opacity(0.05) :
                    Color.blue.opacity(0.03),
                    Color.clear
                ],
                startPoint: .leading, endPoint: .trailing
            )
        )
    }
    
    @ViewBuilder
    private var changeCardStatusLabel: some View {
        if change.status == .accepted {
            Text("Applied ✓").font(.caption2).foregroundColor(.green)
        } else if change.status == .rejected {
            Text("Rejected").font(.caption2).foregroundColor(.red)
        }
    }
    
    private var changeSummaryRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text").font(.system(size: 10)).foregroundColor(.secondary)
            Text(change.description).font(.system(size: 10)).foregroundColor(.secondary)
            Spacer()
        }
        .padding(8)
    }
    
    // MARK: - Code Diff
    
    private var codeDiffSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                let lines = buildDiffLines()
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 0) {
                        Text(line.num)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.4))
                            .frame(width: 28, alignment: .trailing)
                            .padding(.trailing, 4)
                        Text(line.prefix)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(line.clr)
                            .frame(width: 14, alignment: .center)
                        Text(line.text)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(line.clr.opacity(0.9))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(line.bg)
                }
            }
        }
        .frame(maxHeight: 250)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }
    
    private struct DiffRow {
        let num: String; let prefix: String; let text: String; let clr: Color; let bg: Color
    }
    
    private func buildDiffLines() -> [DiffRow] {
        let oldL = change.oldContent.components(separatedBy: "\n")
        let newL = change.newContent.components(separatedBy: "\n")
        var res: [DiffRow] = []
        var oi = 0; var ni = 0
        while oi < oldL.count || ni < newL.count {
            if oi < oldL.count && ni < newL.count {
                if oldL[oi] == newL[ni] {
                    res.append(DiffRow(num: "\(ni+1)", prefix: " ", text: newL[ni], clr: .primary.opacity(0.6), bg: .clear))
                    oi += 1; ni += 1
                } else {
                    res.append(DiffRow(num: "-", prefix: "-", text: oldL[oi], clr: .red, bg: Color.red.opacity(0.08)))
                    oi += 1
                    res.append(DiffRow(num: "\(ni+1)", prefix: "+", text: newL[ni], clr: .green, bg: Color.green.opacity(0.08)))
                    ni += 1
                }
            } else if oi < oldL.count {
                res.append(DiffRow(num: "-", prefix: "-", text: oldL[oi], clr: .red, bg: Color.red.opacity(0.08)))
                oi += 1
            } else {
                res.append(DiffRow(num: "\(ni+1)", prefix: "+", text: newL[ni], clr: .green, bg: Color.green.opacity(0.08)))
                ni += 1
            }
            if res.count > 100 { break }
        }
        return res
    }
    
    private var changeCardActions: some View {
        HStack(spacing: 8) {
            Button(action: { onApply?(change) }) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Apply Change")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            Button(action: { onReject?(change) }) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                    Text("Reject")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.08))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.2)))
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

// MARK: - Shape Extension
struct RoundedCornerShape: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let w = rect.size.width
        let h = rect.size.height
        let r = min(min(self.radius, h/2), w/2)
        
        let tr = corners.contains(.topRight) ? r : 0
        let tl = corners.contains(.topLeft) ? r : 0
        let bl = corners.contains(.bottomLeft) ? r : 0
        let br = corners.contains(.bottomRight) ? r : 0
        
        path.move(to: CGPoint(x: w / 2.0, y: 0))
        path.addLine(to: CGPoint(x: w - tr, y: 0))
        path.addArc(center: CGPoint(x: w - tr, y: tr), radius: tr,
                    startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        
        path.addLine(to: CGPoint(x: w, y: h - br))
        path.addArc(center: CGPoint(x: w - br, y: h - br), radius: br,
                    startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        
        path.addLine(to: CGPoint(x: bl, y: h))
        path.addArc(center: CGPoint(x: bl, y: h - bl), radius: bl,
                    startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addArc(center: CGPoint(x: tl, y: tl), radius: tl,
                    startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        
        path.closeSubpath()
        return path
    }
}

// Custom OptionSet for Corners (Cross-platform)
struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape( RoundedCornerShape(radius: radius, corners: corners) )
    }
}

// MARK: - Rich Text Components

/// Renders inline markdown (bold, italic, links)
struct MarkdownTextView: View {
    let text: String
    
    var body: some View {
        Text(attributedText)
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(.primary)
            .lineSpacing(5)
            .textSelection(.enabled)
    }
    
    private var attributedText: AttributedString {
        var str = AttributedString(text)
        let nsText = text as NSString
        
        // Apply bold (**text** or __text__)
        if let boldRegex = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*|__(.+?)__", options: []) {
            let matches = boldRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let matchedString = nsText.substring(with: match.range)
                if let range = str.range(of: matchedString) {
                    str[range].font = .system(size: 13, weight: .bold)
                }
            }
        }
        
        // Apply italic (*text* or _text_)
        if let italicRegex = try? NSRegularExpression(pattern: "(?<![*_])\\*([^*]+)\\*(?![*_])|(?<![*_])_([^_]+)_(?![*_])", options: []) {
            let matches = italicRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let matchedString = nsText.substring(with: match.range)
                if let range = str.range(of: matchedString) {
                    str[range].font = .system(size: 13).italic()
                }
            }
        }
        
        // Apply inline code (`code`)
        if let codeRegex = try? NSRegularExpression(pattern: "`([^`]+)`", options: []) {
            let matches = codeRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let matchedString = nsText.substring(with: match.range)
                if let range = str.range(of: matchedString) {
                    str[range].font = .system(size: 12, design: .monospaced)
                    str[range].backgroundColor = Color(nsColor: .controlBackgroundColor)
                }
            }
        }
        
        // Apply inline LaTeX ($formula$) - styled as italic blue
        if let latexRegex = try? NSRegularExpression(pattern: "\\$([^$]+)\\$", options: []) {
            let matches = latexRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let matchedString = nsText.substring(with: match.range)
                if let range = str.range(of: matchedString) {
                    str[range].font = .system(size: 13, design: .serif).italic()
                    str[range].foregroundColor = Color.accentColor
                }
            }
        }
        
        return str
    }
}

/// Renders heading with proper font size
struct HeadingView: View {
    let level: Int
    let content: String
    
    var body: some View {
        Text(content)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, topPadding)
            .padding(.bottom, 4)
    }
    
    private var fontSize: CGFloat {
        switch level {
        case 1: return 24
        case 2: return 20
        case 3: return 17
        case 4: return 15
        case 5: return 14
        default: return 13
        }
    }
    
    private var topPadding: CGFloat {
        level <= 2 ? 8 : 4
    }
}

/// Renders ordered/unordered list
struct ListView: View {
    let items: [String]
    let isOrdered: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    Text(isOrdered ? "\(index + 1)." : "•")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(width: 20, alignment: isOrdered ? .trailing : .center)
                    
                    Text(items[index])
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.leading, 8)
    }
}

/// Renders blockquote
struct BlockquoteView: View {
    let content: String
    
    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: 3)
            
            Text(content)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .italic()
                .padding(.leading, 12)
                .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renders LaTeX equation via MathJax WebView
struct LaTeXBlockView: View {
    let expression: String
    let isBlock: Bool
    
    var body: some View {
        VStack(alignment: isBlock ? .center : .leading, spacing: 0) {
            LaTeXWebView(expression: expression, isBlock: isBlock)
                .frame(height: isBlock ? 120 : 50)
                .frame(maxWidth: .infinity)
        }
        .background(Color(white: 0.12))
        .cornerRadius(8)
    }
}

/// Renders HTML content
struct HTMLBlockView: View {
    let content: String
    
    var body: some View {
        HTMLWebView(content: content)
            .frame(minHeight: 100)
            .frame(maxWidth: .infinity)
            .cornerRadius(6)
    }
}

// MARK: - LaTeX WebView (MathJax)

struct LaTeXWebView: NSViewRepresentable {
    let expression: String
    let isBlock: Bool
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Escape backslashes for JavaScript
        let escapedExpr = expression
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <script>
                MathJax = {
                    tex: {
                        inlineMath: [['$', '$'], ['\\\\(', '\\\\)']],
                        displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']],
                        processEscapes: true
                    },
                    svg: {
                        fontCache: 'global'
                    },
                    startup: {
                        ready: function() {
                            MathJax.startup.defaultReady();
                            MathJax.startup.promise.then(function() {
                                document.body.style.opacity = '1';
                            });
                        }
                    }
                };
            </script>
            <script id="MathJax-script" async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js"></script>
            <style>
                body {
                    margin: 0;
                    padding: \(isBlock ? "16px" : "8px");
                    background: #1e1e1e;
                    display: flex;
                    align-items: center;
                    justify-content: \(isBlock ? "center" : "flex-start");
                    min-height: 100%;
                    opacity: 0;
                    transition: opacity 0.2s ease;
                }
                mjx-container {
                    color: #e0e0e0 !important;
                }
                mjx-container svg {
                    fill: #e0e0e0 !important;
                }
            </style>
        </head>
        <body>
            \(isBlock ? "$$\(expression)$$" : "$\(expression)$")
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - HTML WebView

struct HTMLWebView: NSViewRepresentable {
    let content: String
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    font-size: 13px;
                    color: #e0e0e0;
                    background: #1e1e1e;
                    padding: 12px;
                    margin: 0;
                }
                table { border-collapse: collapse; width: 100%; }
                th, td { border: 1px solid #444; padding: 8px; text-align: left; }
                th { background: #2d2d2d; }
                a { color: #58a6ff; }
            </style>
        </head>
        <body>
            \(content)
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - Dynamic Code Tag Generator

/// Generates meaningful tags from code content in real-time
struct CodeTagGenerator {
    
    /// Generate a smart tag from code analysis
    static func generateTag(from code: String, language: String) -> String {
        // 1. Try to extract function/method name
        if let funcName = extractFunctionName(from: code, language: language) {
            return "#\(funcName)"
        }
        
        // 2. Try to extract class/struct name
        if let className = extractClassName(from: code, language: language) {
            return "#\(className)"
        }
        
        // 3. Try to detect purpose from comments
        if let purpose = detectPurpose(from: code) {
            return "#\(purpose)"
        }
        
        // 4. Fallback to language + line count
        let lineCount = code.components(separatedBy: "\n").count
        let lang = language.isEmpty ? "Code" : language.capitalized
        return "#\(lang)\(lineCount)L"
    }
    
    /// Extract function/method name
    private static func extractFunctionName(from code: String, language: String) -> String? {
        let patterns: [String]
        
        switch language.lowercased() {
        case "swift":
            patterns = [
                #"func\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"private\s+func\s+([a-zA-Z_][a-zA-Z0-9_]*)"#
            ]
        case "python":
            patterns = [#"def\s+([a-zA-Z_][a-zA-Z0-9_]*)"#]
        case "javascript", "typescript", "js", "ts":
            patterns = [
                #"function\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"const\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*\("#,
                #"([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*async"#
            ]
        case "rust":
            patterns = [#"fn\s+([a-zA-Z_][a-zA-Z0-9_]*)"#]
        case "go", "golang":
            patterns = [#"func\s+([a-zA-Z_][a-zA-Z0-9_]*)"#]
        case "java", "kotlin":
            patterns = [
                #"public\s+\w+\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\("#,
                #"private\s+\w+\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\("#,
                #"fun\s+([a-zA-Z_][a-zA-Z0-9_]*)"#
            ]
        default:
            patterns = [#"func\s+([a-zA-Z_][a-zA-Z0-9_]*)"#, #"function\s+([a-zA-Z_][a-zA-Z0-9_]*)"#]
        }
        
        for pattern in patterns {
            if let match = code.firstMatch(pattern: pattern) {
                return match
            }
        }
        return nil
    }
    
    /// Extract class/struct/type name
    private static func extractClassName(from code: String, language: String) -> String? {
        let patterns: [String]
        
        switch language.lowercased() {
        case "swift":
            patterns = [
                #"class\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"struct\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"enum\s+([a-zA-Z_][a-zA-Z0-9_]*)"#
            ]
        case "python":
            patterns = [#"class\s+([a-zA-Z_][a-zA-Z0-9_]*)"#]
        case "javascript", "typescript", "js", "ts":
            patterns = [
                #"class\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"interface\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"type\s+([a-zA-Z_][a-zA-Z0-9_]*)"#
            ]
        case "rust":
            patterns = [
                #"struct\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"enum\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"impl\s+([a-zA-Z_][a-zA-Z0-9_]*)"#
            ]
        case "java", "kotlin":
            patterns = [
                #"class\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"interface\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"data\s+class\s+([a-zA-Z_][a-zA-Z0-9_]*)"#
            ]
        default:
            patterns = [#"class\s+([a-zA-Z_][a-zA-Z0-9_]*)"#]
        }
        
        for pattern in patterns {
            if let match = code.firstMatch(pattern: pattern) {
                return match
            }
        }
        return nil
    }
    
    /// Detect purpose from comments
    private static func detectPurpose(from code: String) -> String? {
        let lower = code.lowercased()
        
        if lower.contains("fix:") || lower.contains("// fix") || lower.contains("bugfix") {
            return "Fix"
        }
        if lower.contains("todo:") || lower.contains("// todo") {
            return "TODO"
        }
        if lower.contains("feature:") || lower.contains("new feature") {
            return "Feature"
        }
        if lower.contains("refactor") {
            return "Refactor"
        }
        if lower.contains("test") || lower.contains("spec") {
            return "Test"
        }
        if lower.contains("example") || lower.contains("demo") || lower.contains("sample") {
            return "Example"
        }
        if lower.contains("api") || lower.contains("endpoint") {
            return "API"
        }
        if lower.contains("model") || lower.contains("entity") {
            return "Model"
        }
        if lower.contains("view") || lower.contains("component") || lower.contains("ui") {
            return "View"
        }
        if lower.contains("service") || lower.contains("manager") {
            return "Service"
        }
        
        return nil
    }
}

// String extension for regex matching
extension String {
    func firstMatch(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(self.startIndex..., in: self)
        if let match = regex.firstMatch(in: self, options: [], range: range),
           match.numberOfRanges > 1,
           let captureRange = Range(match.range(at: 1), in: self) {
            return String(self[captureRange])
        }
        return nil
    }
}

/// Dynamic tag with auto-generated name
struct DynamicTag: Equatable {
    let name: String
    let color: Color
    
    static let none = DynamicTag(name: "", color: .gray)
    
    var isEmpty: Bool { name.isEmpty }
    
    init(name: String, color: Color = .accentColor) {
        self.name = name
        self.color = DynamicTag.colorFor(name: name)
    }
    
    private static func colorFor(name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("fix") || lower.contains("bug") { return .orange }
        if lower.contains("feature") || lower.contains("new") { return .green }
        if lower.contains("refactor") { return .purple }
        if lower.contains("test") { return .yellow }
        if lower.contains("api") || lower.contains("service") { return .cyan }
        if lower.contains("view") || lower.contains("ui") { return .pink }
        if lower.contains("model") { return .teal }
        // Hash-based color for unique names
        let hash = abs(name.hashValue)
        let colors: [Color] = [.blue, .indigo, .mint, .orange, .pink, .purple, .teal, .cyan]
        return colors[hash % colors.count]
    }
}

struct NativeCodeBlockView: View {
    let language: String
    let code: String
    
    @State private var isCopied = false
    @State private var isHovering = false
    
    // Auto-color based on language
    private var autoColorTheme: CellColorTheme {
        switch language.lowercased() {
        case "swift": return .orange
        case "python": return .blue
        case "javascript", "js", "typescript", "ts": return .yellow
        case "html": return .red
        case "css", "scss", "sass": return .purple
        case "rust": return .brown
        case "go", "golang": return .cyan
        case "java", "kotlin": return .teal
        case "ruby": return .red
        case "php": return .indigo
        case "c", "cpp", "c++", "objc", "objective-c": return .gray
        case "shell", "bash", "zsh": return .green
        case "sql": return .mint
        case "json", "yaml", "xml": return .pink
        default: return .blue
        }
    }
    
    private var blockBackground: Color {
        autoColorTheme.color
    }
    
    private var blockBorder: Color {
        autoColorTheme.borderColor.opacity(0.4)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                // Left Gutter
                gutterView
                
                // Main Cell Content
                VStack(spacing: 0) {
                    headerView
                    codeContentView
                }
            }
        }
        .background(blockBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(blockBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        .padding(.vertical, 8)
        .onHover { isHovering = $0 }
    }
    
    // MARK: - Subviews
    
    // MARK: - Computed Properties
    
    private var lineCount: Int {
        code.components(separatedBy: "\n").count
    }
    
    private var isLongCode: Bool {
        lineCount > 15
    }
    
    private var gutterView: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(1...min(lineCount, isExpanded ? lineCount : 15), id: \.self) { lineNum in
                Text("\(lineNum)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(height: 18)
            }
            
            if isLongCode && !isExpanded {
                Text("...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.4))
                    .frame(height: 18)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(width: 36)
        .background(autoColorTheme.color.opacity(0.3))
    }
    
    private var headerView: some View {
        HStack(spacing: 8) {
            // Language Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(autoColorTheme.iconColor)
                    .frame(width: 8, height: 8)
                
                Text(language.isEmpty ? "Plain Text" : language.capitalized)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.2))
            .cornerRadius(4)
            
            // Auto-Generated Tag
            if !dynamicTag.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 8))
                    Text(dynamicTag.name)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(dynamicTag.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(dynamicTag.color.opacity(0.15))
                .cornerRadius(3)
            }
            
            // Line Count Badge
            Text("\(lineCount) lines")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.05))
                .cornerRadius(3)
            
            Spacer()
            
            // Tools (Always visible but subtle, brighter on hover)
            HStack(spacing: 4) {
                // Run Menu (NEW!)
                Menu {
                    Button(action: runInPlayground) {
                        Label("Run in Playground", systemImage: "play.rectangle")
                    }
                    Button(action: runInCellMode) {
                        Label("Run in Cell Mode", systemImage: "square.grid.2x2")
                    }
                    Divider()
                    Button(action: openInEditor) {
                        Label("Open in Editor", systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green.opacity(isHovering ? 1 : 0.6))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
                .help("Run Code")
                
                // Expand/Collapse (for long code)
                if isLongCode {
                    Button(action: { 
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle() 
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(isHovering ? 1 : 0.5))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20)
                }
                
                // Copy Button
                Button(action: copyCode) {
                    HStack(spacing: 3) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        if isHovering {
                            Text(isCopied ? "Copied" : "Copy")
                                .font(.system(size: 9))
                        }
                    }
                    .foregroundColor(isCopied ? .green : .secondary.opacity(isHovering ? 1 : 0.6))
                    .padding(.horizontal, isHovering ? 6 : 4)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(isHovering ? 0.08 : 0.03))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }
    
    // MARK: - Dynamic Tag
    
    private var dynamicTag: DynamicTag {
        DynamicTag(name: CodeTagGenerator.generateTag(from: code, language: language))
    }
    
    // MARK: - Run Actions
    
    private func runInPlayground() {
        // Copy code to clipboard and switch to playground mode
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        
        // Get appState from environment and switch mode
        NotificationCenter.default.post(
            name: Notification.Name("OpenInPlayground"), 
            object: nil, 
            userInfo: ["code": code, "language": language]
        )
    }
    
    private func runInCellMode() {
        // Copy code and switch to cell mode
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        
        NotificationCenter.default.post(
            name: Notification.Name("OpenInCellMode"), 
            object: nil, 
            userInfo: ["code": code, "language": language]
        )
    }
    
    private func openInEditor() {
        // Create a new temp file and open it
        let ext = languageExtension(for: language)
        let fileName = "ai_code_\(Int(Date().timeIntervalSince1970)).\(ext)"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try code.write(to: tempURL, atomically: true, encoding: .utf8)
            NotificationCenter.default.post(
                name: Notification.Name("OpenFileInEditor"), 
                object: nil, 
                userInfo: ["url": tempURL]
            )
        } catch {
            print("Failed to create temp file: \(error)")
        }
    }
    
    private func languageExtension(for lang: String) -> String {
        switch lang.lowercased() {
        case "swift": return "swift"
        case "python": return "py"
        case "javascript", "js": return "js"
        case "typescript", "ts": return "ts"
        case "rust": return "rs"
        case "go", "golang": return "go"
        case "java": return "java"
        case "kotlin": return "kt"
        case "ruby": return "rb"
        case "c": return "c"
        case "cpp", "c++": return "cpp"
        case "html": return "html"
        case "css": return "css"
        case "sql": return "sql"
        case "shell", "bash": return "sh"
        default: return "txt"
        }
    }
    
    @State private var isExpanded = false
    
    private var codeContentView: some View {
        let lines = code.components(separatedBy: "\n")
        let displayLines = isExpanded || !isLongCode ? lines : Array(lines.prefix(15))
        
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(displayLines.indices, id: \.self) { idx in
                        Text(displayLines[idx].isEmpty ? " " : displayLines[idx])
                            .font(.custom("Menlo", size: 12))
                            .foregroundColor(Color(nsColor: .textColor))
                            .frame(height: 18, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            
            // Expand indicator
            if isLongCode && !isExpanded {
                HStack {
                    Spacer()
                    Button(action: { 
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded = true 
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text("Show \(lineCount - 15) more lines")
                                .font(.system(size: 10))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .background(
                    LinearGradient(
                        colors: [autoColorTheme.color.opacity(0), autoColorTheme.color.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.15))
    }
    
    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        withAnimation(.easeInOut(duration: 0.2)) {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }
}

// MARK: - Chat List Row

struct ChatListRow: View {
    let chat: ChatSession
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 10))
                    .foregroundColor(isActive ? .accentColor : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.name)
                        .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? .primary : .secondary)
                        .lineLimit(1)
                    
                    Text(chat.messages.isEmpty ? "Empty" : "\(chat.messages.count) messages")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                
                Spacer()
                
                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Color.accentColor.opacity(0.15) : (isHovering ? Color.white.opacity(0.05) : Color.clear))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Delete Chat", role: .destructive) {
                onDelete()
            }
        }
    }
}

// MARK: - Agent Thinking View (Live Tool Execution)

struct AgentThinkingView: View {
    let currentTool: String?
    
    @State private var pulsePhase = false
    @State private var dotCount = 0
    
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    private var toolIcon: String {
        guard let tool = currentTool?.lowercased() else { return "brain" }
        if tool.contains("file_read") || tool.contains("reading") { return "doc.text.magnifyingglass" }
        if tool.contains("file_write") || tool.contains("writing") { return "doc.text.fill" }
        if tool.contains("replace") || tool.contains("editing") { return "pencil.line" }
        if tool.contains("shell") || tool.contains("running") { return "terminal.fill" }
        if tool.contains("grep") || tool.contains("search") { return "magnifyingglass" }
        if tool.contains("list_dir") || tool.contains("tree") { return "folder.fill" }
        if tool.contains("git") { return "arrow.triangle.branch" }
        if tool.contains("web") || tool.contains("fetch") { return "globe" }
        return "gearshape.fill"
    }
    
    private var toolColor: Color {
        guard let tool = currentTool?.lowercased() else { return .accentColor }
        if tool.contains("file_read") || tool.contains("reading") { return .cyan }
        if tool.contains("file_write") || tool.contains("writing") { return .green }
        if tool.contains("replace") || tool.contains("editing") { return .orange }
        if tool.contains("shell") || tool.contains("running") { return .purple }
        if tool.contains("grep") || tool.contains("search") { return .yellow }
        if tool.contains("git") { return .pink }
        return .accentColor
    }
    
    private var statusText: String {
        guard let tool = currentTool else {
            let dots = String(repeating: ".", count: (dotCount % 3) + 1)
            return "Thinking\(dots)"
        }
        return tool
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // AI Avatar
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(
                    colors: [toolColor, toolColor.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: toolIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .scaleEffect(pulsePhase ? 1.15 : 0.85)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulsePhase)
                )
                .shadow(color: toolColor.opacity(0.3), radius: 6, y: 2)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.45)
                        .frame(width: 14, height: 14)
                    
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(toolColor)
                    
                    Spacer()
                }
                
                // Animated progress bar
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(toolColor.opacity(0.12))
                        .frame(height: 3)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(toolColor.opacity(0.6))
                                .frame(width: geo.size.width * 0.3, height: 3)
                                .offset(x: pulsePhase ? geo.size.width * 0.7 : 0)
                                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulsePhase)
                        }
                }
                .frame(height: 3)
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear { pulsePhase = true }
        .onReceive(timer) { _ in dotCount += 1 }
    }
}

// MARK: - Tool Execution Steps View (Completed Results)

struct ToolExecutionStepsView: View {
    let results: [ToolResultModel]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.toolCallId) { index, result in
                ToolStepRow(result: result, stepNumber: index + 1, isLast: index == results.count - 1)
            }
        }
        .padding(1)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct ToolStepRow: View {
    let result: ToolResultModel
    let stepNumber: Int
    let isLast: Bool
    
    @State private var isExpanded = false
    
    private var icon: String {
        let name = result.toolName.lowercased()
        if name.contains("file_read") { return "doc.text.magnifyingglass" }
        if name.contains("file_write") { return "doc.text.fill" }
        if name.contains("replace_in_file") { return "pencil.line" }
        if name.contains("shell") { return "terminal.fill" }
        if name.contains("grep") || name.contains("search") { return "magnifyingglass" }
        if name.contains("file_search") { return "doc.text.magnifyingglass" }
        if name.contains("list_dir") || name.contains("tree") { return "folder.fill" }
        if name.contains("git") { return "arrow.triangle.branch" }
        if name.contains("web") || name.contains("fetch") { return "globe" }
        return "gearshape"
    }
    
    private var iconColor: Color {
        guard result.success else { return .red }
        let name = result.toolName.lowercased()
        if name.contains("file_read") || name.contains("file_search") { return .cyan }
        if name.contains("file_write") { return .green }
        if name.contains("replace") { return .orange }
        if name.contains("shell") { return .purple }
        if name.contains("grep") || name.contains("search") { return .yellow }
        if name.contains("git") { return .pink }
        return .accentColor
    }
    
    private var label: String {
        switch result.toolName {
        case "file_read": return "FILE_READ"
        case "file_write": return "FILE_WRITE"
        case "replace_in_file": return "EDIT_FILE"
        case "shell": return "RUN_COMMAND"
        case "grep_search": return "GREP_SEARCH"
        case "file_search": return "FILE_SEARCH"
        case "list_directory_tree": return "LIST_DIR"
        case "git_status": return "GIT_STATUS"
        case "web_fetch": return "WEB_FETCH"
        default: return result.toolName.uppercased()
        }
    }
    
    // Extract filepath from output for display
    private var filePath: String? {
        let output = result.output
        // Look for common patterns
        if let range = output.range(of: #"/[^\s\n]+"#, options: .regularExpression) {
            let path = String(output[range])
            if path.contains("/") {
                let url = URL(fileURLWithPath: path)
                return url.lastPathComponent
            }
        }
        return nil
    }
    
    private var outputPreview: String {
        let output = result.success ? result.output : (result.error ?? "Unknown error")
        if output.count > 500 {
            return String(output.prefix(500)) + "\n..."
        }
        return output
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Step Header (always visible, clickable)
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    // Timeline dot + line
                    VStack(spacing: 0) {
                        Circle()
                            .fill(iconColor)
                            .frame(width: 8, height: 8)
                        if !isLast {
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(width: 1)
                        }
                    }
                    .frame(width: 8)
                    
                    // Status icon
                    Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(result.success ? .green : .red)
                    
                    // Tool icon
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(iconColor)
                        .frame(width: 14)
                    
                    // Label
                    Text(label)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    // File name (if detected)
                    if let file = filePath {
                        Text(file)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(iconColor.opacity(0.8))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Expand chevron
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expanded Output
            if isExpanded && !outputPreview.isEmpty {
                Text(outputPreview)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(result.success ? .secondary : .red.opacity(0.8))
                    .lineLimit(20)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.leading, 16) // Align with content after timeline dot
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.08))
            }
            
            if !isLast {
                Divider().opacity(0.3)
            }
        }
    }
}

