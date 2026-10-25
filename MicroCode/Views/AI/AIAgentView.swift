//
//  AIAgentView.swift
//  MicroCode
//
//  Full-featured AI Workstation & Autonomous Agent Interface
//  Integrates ACP Local Agents, Dotmini Cloud, BYOK (Direct API Key), Web Subscriptions, and Local LLMs (Ollama/LM Studio).
//
//  Created & Designed by Dotmini Software
//  Founder & CEO: Tirawat Nantamas
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import SwiftUI
import Combine
import MicroCodeSupport
import AppKit
import WebKit
import UniformTypeIdentifiers
import PDFKit
import AVKit
import AVFoundation

// MARK: - AI Agent View (Professional)

struct AIAgentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var agent = AgentService.shared
    @StateObject private var modelCatalog = AIModelCatalog.shared
    private var tokenOptimizer: TokenOptimizer { TokenOptimizer.shared }
    var allowsChatSidebar: Bool = true
    var sessionScope: AgentSessionScope = .editor
    /// Science Mode supplies an independent research root. Editor Mode retains
    /// the project currently opened in the IDE.
    var scopedWorkspacePath: String?
    var restoresPersistedScopeWorkspace = true
    
    @State private var inputText = ""
    @State private var attachments: [AIAttachment] = []
    @State private var isDropTargeted = false
    @State private var isHoveringInput = false
    @State private var isPaperMode = false  // A4 Paper reading mode
    @State private var isCellMode = false   // Cell Mode (notebook-style)
    @State private var currentPaperPage = 0
    @State private var showModelPicker = false
    @State private var showProjectDropdown = false
    @State private var showSubAgentDropdown = false
    @State private var showingAddServerSheet = false
    @State private var selectedSubAgentType: String = "main"
    @State private var isPlanMode = false
    @State private var isTaskMode = false
    @State private var isWalkthroughMode = false
    @State private var showingTeamTasks = false
    @State private var showingTeamIntegrations = false
    @State private var showingAgentConnections = false
    @State private var showingAgentEcosystem = false
    @State private var agentEcosystemTab: EcosystemTab = .agents
    @State private var activeACPAgent: ACPAgentConfig? = nil
    @StateObject private var acpHost = ACPHostService.shared
    @ObservedObject private var teamIntegrations = TeamIntegrationService.shared
    @ObservedObject private var deviceRuntime = DeviceRuntimeService.shared
    @ObservedObject private var previewDock = PreviewDockService.shared
    @ObservedObject private var voiceCoding = VoiceCodingService.shared
    @State private var collapsedProjectsInChatSidebar: Set<String> = []
    @State private var manuallyExpandedProjectsInChatSidebar: Set<String> = []
    @FocusState private var isInputFocused: Bool
    
    // MARK: - AI Enhancement State
    @StateObject private var slashCommandService = SlashCommandService.shared
    @StateObject private var contextProviderService = ContextProviderService.shared
    @ObservedObject private var toolApprovalManager = ToolApprovalManager.shared
    @ObservedObject private var planManager = ImplementationPlanManager.shared
    @State private var showSlashSuggestions = false
    @State private var slashSelectedIndex: Int = 0
    @State private var showContextSuggestions = false
    @State private var contextSearchPrefix = ""
    @State private var showRawMarkdownPlan = false
    @State private var isPlanFullscreen = false
    @AppStorage("microcode_preview_dock_width") private var previewDockWidth: Double = 520
    @AppStorage("studioAspectRatio") private var studioAspectRatio: String = "16:9"
    @AppStorage("studioResolution") private var studioResolution: String = "1080p"
    @AppStorage("studioDuration") private var studioDuration: String = "5s"
    @ObservedObject private var scopeGuard = WorkspaceScopeGuard.shared
    @ObservedObject private var secretShield = SecretShieldMonitor.shared
    @ObservedObject private var subAgentHarness = SubAgentHarness.shared
    @State private var secretActionToast: String? = nil
    
    private var selectedSubAgentDisplayName: String {
        if selectedSubAgentType.hasPrefix("squad:") {
            let pid = String(selectedSubAgentType.dropFirst("squad:".count))
            if let preset = subAgentHarness.squadPresets.first(where: { $0.id == pid }) {
                return "👑 \(preset.name)"
            }
            return "👑 CEO Squad"
        }
        switch selectedSubAgentType {
        case "main": return "Main Agent"
        case "architect": return "Architect"
        case "frontend_engineer": return "Frontend Specialist"
        case "backend_engineer": return "Backend Engineer"
        case "bug_hunter": return "Bug Hunter"
        case "test_runner": return "Test Runner"
        case "security_auditor": return "Security Auditor"
        default:
            if let def = SubAgentHarness.shared.registeredDefinitions[selectedSubAgentType] {
                return def.role
            }
            return selectedSubAgentType.capitalized
        }
    }
    
    private var currentProjectName: String {
        if let workspace = agent.currentWorkspace, !workspace.isEmpty {
            return URL(fileURLWithPath: workspace).lastPathComponent
        }
        if sessionScope == .editor, let ws = appState.workspaceFolder?.path, !ws.isEmpty {
            return URL(fileURLWithPath: ws).lastPathComponent
        }
        if let activeChat = agent.chatSessions.first(where: { $0.id == agent.activeChatId }),
           let activeChatPath = activeChat.projectPath, !activeChatPath.isEmpty {
            return URL(fileURLWithPath: activeChatPath).lastPathComponent
        }
        return "No Project"
    }
    
    private var currentKeyMode: String {
        if let saved = UserDefaults.standard.string(forKey: "aiKeyMode") {
            return saved
        }
        // Auto-detect only when no mode was ever saved
        if SubscriptionAuthManager.shared.hasAnyConnected {
            return "subscription"
        }
        let hasDirectKeys = appState.apiKeys.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if hasDirectKeys {
            return "direct"
        }
        return "cloud"
    }
    
    private var activeExternalAgentConfig: ACPAgentConfig? {
        if let id = acpHost.activeAgentId {
            return acpHost.registeredConfigs.first(where: { $0.id == id })
        }
        let rawMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? ""
        if rawMode == "subscription" || rawMode == "direct" || rawMode == "cloud" || rawMode == "local" {
            return nil
        }
        if appState.aiProvider == "agy" {
            return acpHost.registeredConfigs.first(where: { $0.type == .agy })
        } else if appState.aiProvider == "codex" {
            return acpHost.registeredConfigs.first(where: { $0.type == .codexEngine })
        } else if appState.aiProvider == "claude_code" {
            return acpHost.registeredConfigs.first(where: { $0.type == .claudeCode })
        } else if appState.aiProvider == "opencode" {
            return acpHost.registeredConfigs.first(where: { $0.type == .openCode })
        } else if appState.aiProvider == "zed" {
            return acpHost.registeredConfigs.first(where: { $0.type == .zedEngine })
        }
        return nil
    }
    
    enum AIExecutionMode: String, CaseIterable {
        case acp = "ACP"
        case cloud = "Dotmini Cloud"
        case byok = "BYOK"
        case subscription = "Subscription"
        case local = "Local LLM"
        
        var badgeTitle: String {
            switch self {
            case .acp: return "ACP"
            case .cloud: return "Dotmini Cloud"
            case .byok: return "BYOK"
            case .subscription: return "Subscription"
            case .local: return "Local LLM"
            }
        }
        
        var icon: String {
            switch self {
            case .acp: return "terminal.fill"
            case .cloud: return "cloud.fill"
            case .byok: return "key.fill"
            case .subscription: return "sparkles.rectangle.stack"
            case .local: return "desktopcomputer"
            }
        }
        
        var badgeColor: Color {
            switch self {
            case .acp: return .teal
            case .cloud: return .purple
            case .byok: return .blue
            case .subscription: return .orange
            case .local: return .mint
            }
        }
    }
    
    private var currentExecutionMode: AIExecutionMode {
        if activeExternalAgentConfig != nil {
            return .acp
        }
        if appState.aiProvider == "local" || currentKeyMode == "local" {
            return .local
        }
        if appState.aiProvider == "omni" || currentKeyMode == "cloud" {
            return .cloud
        }
        if currentKeyMode == "subscription" {
            return .subscription
        }
        return .byok
    }
    
    private func engineColor(for type: ACPAgentType) -> Color {
        switch type {
        case .agy: return .indigo
        case .codexEngine: return .green
        case .claudeCode: return .orange
        case .geminiCLI: return .blue
        case .openCode: return .orange
        case .cursorAgent: return .purple
        case .githubCopilot: return .primary
        case .goose: return .teal
        case .cline: return .cyan
        case .qwenCode: return .indigo
        case .zedEngine: return .cyan
        case .aider: return .green
        case .custom: return .accentColor
        }
    }
    
    private func activeAgentShortName(for config: ACPAgentConfig) -> String {
        switch config.type {
        case .agy: return "Antigravity"
        case .codexEngine: return "Codex"
        case .claudeCode: return "Claude Code"
        case .geminiCLI: return "Gemini CLI"
        case .openCode: return "OpenCode"
        case .cursorAgent: return "Cursor"
        case .githubCopilot: return "Copilot"
        case .goose: return "Goose"
        case .cline: return "Cline"
        case .qwenCode: return "Qwen Code"
        case .zedEngine: return "Zed"
        case .aider: return "Aider"
        case .custom: return config.name
        }
    }
    
    private var activeBrandIconKey: String {
        if let activeAgent = activeExternalAgentConfig {
            return activeAgent.type.brandIconKey
        }
        if currentExecutionMode == .subscription,
           let subStr = UserDefaults.standard.string(forKey: "subscriptionActiveProvider"),
           !subStr.isEmpty {
            return subStr
        }
        return appState.aiProvider.isEmpty ? "microcode" : appState.aiProvider
    }
    
    private var currentModelDisplayName: String {
        if let activeAgent = activeExternalAgentConfig {
            let engineId = activeAgent.type.engineId
            let providerName = activeAgentShortName(for: activeAgent)
            let engineModels = LocalEcosystemDiscovery.shared.models(for: engineId)
            let modelName: String = {
                if let matched = engineModels.first(where: { $0.id == appState.aiModel }) {
                    return matched.name
                }
                if let modelDef = AIModelCatalog.shared.model(id: appState.aiModel) {
                    return modelDef.name
                }
                if let defaultModel = engineModels.first {
                    return defaultModel.name
                }
                return appState.aiModel.isEmpty ? activeAgent.name : AIModelCatalog.formatModelName(appState.aiModel)
            }()
            return "\(providerName) : \(modelName)"
        }
        
        if currentKeyMode == "subscription" {
            let activeSub = UserDefaults.standard.string(forKey: "subscriptionActiveProvider")
            let provType = activeSub.flatMap { SubscriptionProviderType(rawValue: $0) }
            let (provName, modelName): (String, String) = {
                if let info = SubscriptionAuthManager.shared.findModel(id: appState.aiModel, provider: provType) {
                    let pName = provType?.displayName.components(separatedBy: " ").first ?? "Subscription"
                    return (pName, info.name)
                }
                if let info = SubscriptionAuthManager.shared.findModel(id: appState.aiModel) {
                    return (info.provider.displayName.components(separatedBy: " ").first ?? "Subscription", info.name)
                }
                let fallbackModel = appState.aiModel.isEmpty ? "Default Model" : AIModelCatalog.formatModelName(appState.aiModel)
                return ("Subscription", fallbackModel)
            }()
            return "\(provName) : \(modelName)"
        } else if currentExecutionMode == .local || appState.aiProvider == "local" {
            let modelName = LocalLLMService.shared.availableModels.first(where: { $0.id == appState.aiModel })?.displayName ?? (appState.aiModel.isEmpty ? "Local Model" : appState.aiModel)
            return "Local : \(modelName)"
        } else if currentKeyMode == "direct" || currentExecutionMode == .byok {
            let providerName = AIModelCatalog.friendlyProviderName(appState.aiProvider)
            let modelName: String = {
                if let modelDef = AIModelCatalog.shared.model(id: appState.aiModel) {
                    return modelDef.name
                }
                if appState.aiModel.isEmpty {
                    return AIModelCatalog.shared.provider(appState.aiProvider)?.models.first?.name ?? "Select Model"
                }
                return AIModelCatalog.formatModelName(appState.aiModel)
            }()
            return "\(providerName) : \(modelName)"
        } else {
            let modelName: String = {
                if let modelDef = AIModelCatalog.shared.model(id: appState.aiModel) {
                    return modelDef.name
                }
                return appState.aiModel.isEmpty ? "Omni O1X Pro" : AIModelCatalog.formatModelName(appState.aiModel)
            }()
            return "Dotmini Cloud : \(modelName)"
        }
    }
    
    // Aesthetic Constants
    private let borderColor = Color.white.opacity(0.1)
    private var paneColor: Color { Color(nsColor: appState.appTheme.panelBackground) }
    private let accentColor = Color.accentColor
    
    // Theme Harmonization
    private var workspaceBg: Color {
        appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.workspaceBackground)
    }
    private var panelBg: Color {
        appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground)
    }
    private var elevatedBg: Color {
        Color(nsColor: appState.appTheme.elevatedBackground)
    }
    
    var body: some View {
        GeometryReader { rootGeo in
            let hasEmbeddedDock = sessionScope == .editor && (deviceRuntime.showingEmbeddedDeviceDock || previewDock.isDockVisible) && !appState.agenticContextVisible
            let hasRightInspector = appState.agenticContextVisible
            let isPlanActive = isPlanMode || planManager.isPlanVisible
            let sidebarW: CGFloat = (allowsChatSidebar && agent.showChatSidebar) ? 220 : 0
            let maxAllowedDockW: CGFloat = max(420, (rootGeo.size.width - sidebarW) * 0.66)
            let targetDockW: CGFloat = previewDock.isExpandedWidth
                ? max(520, (rootGeo.size.width - sidebarW) * 0.60)
                : min(maxAllowedDockW, max(360, CGFloat(previewDockWidth)))
            let dockW: CGFloat = hasEmbeddedDock ? targetDockW : (hasRightInspector ? 320 : 0)
            let mainColumnAvailWidth = rootGeo.size.width - sidebarW - dockW
            // Auto-promote Plan to full main column when available width cannot comfortably fit Chat (min 420) + Plan (min 400) side-by-side
            let shouldShowPlanFullColumn = isPlanActive && (
                isPlanFullscreen ||
                mainColumnAvailWidth < 820
            )
            
            HStack(spacing: 0) {
                // Chat Sidebar (Collapsible)
                if allowsChatSidebar && agent.showChatSidebar {
                    chatSidebar
                        .frame(width: 220)
                        .clipped()
                    Divider()
                }
                
                // Main Content
                VStack(spacing: 0) {
                    // 1. Toolbar / Header (Solid, Industrial)
                    headerBar
                        .clipped()
                    
                    Divider().background(borderColor)
                    
                    // 2. Main Content Area
                    if isTaskMode {
                        // Task.md / Agent.md Editor
                        taskEditorView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else if isWalkthroughMode {
                        // Antigravity-style Interactive Walkthrough
                        walkthroughView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else if isPaperMode {
                        // A4 Paper Reading Mode
                        A4PaperView(
                            messages: agent.messages,
                            currentPage: $currentPaperPage
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    } else if isCellMode {
                        // Cell Mode (Notebook-style AI Agent)
                        AgentCellModeView()
                            .environmentObject(appState)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .transition(.opacity)
                    } else if shouldShowPlanFullColumn {
                        // Full-Column Implementation Plan (Automatically used when Preview Dock is open in compact window)
                        VStack(spacing: 0) {
                            planView
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()

                            if agent.isLoading {
                                liveTaskActivityBanner
                            }

                            inputArea
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    } else {
                        // Chat & Plan Side-by-Side Split View
                        HStack(spacing: 0) {
                            // Left Pane: Chat Workspace
                            VStack(spacing: 0) {
                                if agent.messages.isEmpty && !agent.isLoading && agent.messageQueue.isEmpty && planManager.currentPlan == nil && !isPlanMode && !planManager.isPlanVisible {
                                    centeredEmptyStateView
                                } else {
                                    VStack(spacing: 0) {
                                        AgentChatStage(
                                            messages: agent.messages,
                                            isLoading: agent.isLoading,
                                            domain: agent.domain,
                                            currentToolExecution: agent.currentToolExecution,
                                            hasEarlierMessages: agent.hasEarlierMessages,
                                            queuedMessages: agent.messageQueue,
                                            activeChatId: agent.activeChatId,
                                            onApplyChange: { change in applyChange(change) },
                                            onRejectChange: { change in rejectChange(change) },
                                            onSuggestionTap: { suggestion in inputText = suggestion; sendMessage() },
                                            onViewPlan: {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    planManager.isPlanVisible.toggle()
                                                    if planManager.isPlanVisible && planManager.currentPlan == nil, let ws = appState.workspaceFolder?.path {
                                                        planManager.loadFromTaskMarkdown(workspacePath: ws)
                                                    }
                                                }
                                            },
                                            onRevertToMessage: { msgId in handleRevertToMessage(msgId) },
                                            onEditAndResendMessage: { msgId, newText in handleEditAndResendMessage(id: msgId, newContent: newText) },
                                            onRetryAssistantMessage: { msgId in handleRetryAssistantMessage(msgId) },
                                            onDeleteMessage: { msgId, revertFiles in handleDeleteMessage(msgId, revertFiles: revertFiles) }
                                        )
                                        .equatable()
                                        .environmentObject(appState)
                                        
                                        if let suggestion = agent.suggestedAction {
                                            suggestedActionBar(suggestion)
                                        }
                                        
                                        if agent.contextLimitReached {
                                            contextLimitBanner
                                        }
                                        
                                        inputArea
                                    }
                                }
                            }
                            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            
                            // Right Pane: Implementation Plan Side Panel (Side-by-Side Split View)
                            if isPlanActive {
                                Divider().background(borderColor)
                                planSidePanelView
                                    .frame(minWidth: 340, idealWidth: 420, maxWidth: 520, maxHeight: .infinity)
                                    .clipped()
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    }
                }
                .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                // Preview is a workspace surface, not a success toast from the
                // capture transport.  Keep it visible while an AVD is connecting
                // (and if a transport needs to retry) so one click always gives
                // the user immediate feedback beside Chat.
                if hasEmbeddedDock {
                    // Draggable Split Divider (matching Antigravity side-by-side Code Preview Pane)
                    Rectangle()
                        .fill(Color.primary.opacity(0.09))
                        .frame(width: 1)
                        .overlay(
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 7)
                                .contentShape(Rectangle())
                                .onHover { hovering in
                                    if hovering {
                                        NSCursor.resizeLeftRight.push()
                                    } else {
                                        NSCursor.pop()
                                    }
                                }
                                .gesture(
                                    DragGesture(minimumDistance: 1)
                                        .onChanged { value in
                                            if previewDock.isExpandedWidth {
                                                previewDock.isExpandedWidth = false
                                            }
                                            let proposed = CGFloat(previewDockWidth) - value.translation.width
                                            previewDockWidth = Double(min(maxAllowedDockW, max(340, proposed)))
                                        }
                                )
                        )
                    embeddedDeviceDock
                        .frame(width: targetDockW)
                        .frame(maxHeight: .infinity)
                        .clipped()
                }
            }
            .frame(width: rootGeo.size.width, height: rootGeo.size.height)
            .clipped()
        }
        .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.workspaceBackground))
        .onAppear {
            let workspace = scopedWorkspacePath ?? (sessionScope == .editor ? appState.workspaceFolder?.path : nil)
            agent.activateScope(
                sessionScope,
                preferredWorkspace: workspace,
                restorePersistedWorkspace: restoresPersistedScopeWorkspace
            )
            if sessionScope == .editor {
                Task { await deviceRuntime.refresh(workspace: appState.workspaceFolder) }
            }
        }
        .onChange(of: appState.workspaceFolder) { newFolder in
            guard sessionScope == .editor, scopedWorkspacePath == nil, let path = newFolder?.path else { return }
            if agent.currentWorkspace != path {
                agent.setWorkspace(path)
            }
            Task { await deviceRuntime.refresh(workspace: newFolder) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodePlanApprovedReturnToChat"))) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isPlanMode = false
                isPlanFullscreen = false
                planManager.isPlanVisible = false
            }
        }
        .sheet(isPresented: $showingTeamTasks) {
            TeamTasksView(
                workspacePath: agent.currentWorkspace ?? (sessionScope == .editor ? appState.workspaceFolder?.path : nil),
                activeChatID: agent.activeChatId,
                onOpenInAgent: {
                    isPlanMode = false
                    isTaskMode = false
                    isPaperMode = false
                    isCellMode = false
                }
            )
        }
        .sheet(isPresented: $showingTeamIntegrations) {
            TeamIntegrationsSettings()
        }
        .sheet(isPresented: $showingAddServerSheet) {
            ServerConfigSheet(mode: .add) { newServer in
                RemoteConnectionManager.shared.addServer(newServer)
                AgentToolBox.shared.executionTarget = .remote(newServer)
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $deviceRuntime.showingDeviceRuntimeSheet) {
            DeviceRuntimeView(onEmbeddedAndroidOpened: {
                deviceRuntime.showingEmbeddedDeviceDock = true
                deviceRuntime.showingEmbeddedAppleDock = false
            }, onEmbeddedAppleSimulatorOpened: {
                deviceRuntime.showingEmbeddedDeviceDock = true
                deviceRuntime.showingEmbeddedAppleDock = true
            })
            .environmentObject(appState)
        }
        .sheet(isPresented: $showingAgentConnections) {
            AgentConnectionsView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showingAgentEcosystem) {
            AgentEcosystemConfigView(initialTab: agentEcosystemTab)
                .environmentObject(appState)
        }
        .sheet(isPresented: $subAgentHarness.showSquadBuilderSheet) {
            AgentSquadBuilderSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCode.OpenAgentConnections"))) { _ in
            showingAgentConnections = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCode.CloseAgentConnections"))) { _ in
            showingAgentConnections = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCode.OpenAgentEcosystem"))) { notification in
            if let tabName = notification.object as? String {
                if tabName == "rules" { agentEcosystemTab = .rules }
                else if tabName == "mcp" { agentEcosystemTab = .mcp }
                else if tabName == "context" { agentEcosystemTab = .context }
                else if tabName == "models" { agentEcosystemTab = .models }
                else { agentEcosystemTab = .agents }
            }
            showingAgentEcosystem = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .voiceCodingInput)) { notification in
            if let text = notification.userInfo?["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if inputText.isEmpty {
                    inputText = text
                } else {
                    inputText += " " + text
                }
                isInputFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentProcessQueueItem)) { notification in
            let targetScope: AgentSessionScope = agent.domain == .science ? .science : .editor
            guard sessionScope == targetScope else { return }
            guard !agent.isLoading else { return }
            if let queued = notification.object as? QueuedMessage {
                executeMessage(queued.text, attachments: queued.attachments)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCode.PreviewDock.RegionComment"))) { notification in
            if let comment = notification.object as? String {
                inputText = inputText.isEmpty ? comment : "\(inputText)\n\(comment)"
                isInputFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeInsertAgentPrompt"))) { notification in
            if let prompt = notification.userInfo?["prompt"] as? String {
                let autoSend = (notification.userInfo?["autoSend"] as? Bool) ?? false
                if autoSend {
                    if agent.isLoading || agent.isProcessingQueue {
                        agent.enqueueMessage(prompt, attachments: [])
                    } else {
                        executeMessage(prompt, attachments: [])
                    }
                } else {
                    inputText = inputText.isEmpty ? prompt : "\(inputText)\n\(prompt)"
                    isInputFocused = true
                }
            }
        }
        .onAppear {
            if sessionScope == .editor {
                scopeGuard.syncWorkspace(agent.currentWorkspace ?? scopedWorkspacePath)
                agent.loadPinnedConstraints(for: agent.currentWorkspace ?? scopedWorkspacePath)
                agent.refreshProjectBriefing()
            }
        }
    }

    // MARK: - Centered Empty State View
    private var centeredEmptyStateView: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(alignment: .leading, spacing: 8) {
                // Project Workspace Pill Selector
                Button(action: {
                    if sessionScope == .editor { showProjectDropdown.toggle() }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(currentProjectName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary.opacity(0.85))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(sessionScope == .science)
                .popover(isPresented: $showProjectDropdown, arrowEdge: .top) {
                    ProjectWorkspaceSelectorMenu(isPresented: $showProjectDropdown)
                        .environmentObject(appState)
                }
                .padding(.leading, 2)

                // Feature #8: "Where Was I?" Instant Project Briefing Card
                if sessionScope == .editor, let briefing = agent.projectBriefing, appState.isCurrentAIConnected {
                    projectBriefingCardView(briefing)
                }
                
                activeAgentStatusHUD

                securityAndFailoverAlertsBar
                
                // Clean Floating Input Box
                inputCardView
            }
            .frame(maxWidth: 880)
            .padding(.horizontal, 28)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Xcode-style device area: the actual Android AVD stays in the right-hand
    /// dock, while the conversation and its context remain visible on the left.
    /// This is deliberately not a design-time canvas or a second emulator UI.
    @ViewBuilder private var embeddedDeviceDock: some View {
        EmbeddedDeviceDockView()
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
                Button(action: {
                    isPlanMode = false
                    planManager.clearPlan()
                    _ = agent.createNewChat(projectPath: agent.currentWorkspace ?? scopedWorkspacePath)
                }) {
                    Text("New")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Chat")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
            
            // Chat List Grouped By Project (Active Project Accordion Focus)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(agent.projectGroups) { group in
                        chatSidebarGroupView(group: group)
                    }
                }
                .padding(8)
            }
        }
        .background(paneColor.opacity(0.5))
    }
    
    @ViewBuilder
    private func chatSidebarGroupView(group: ProjectChatGroup) -> some View {
        let isExpanded = isChatSidebarGroupExpanded(group)
        VStack(alignment: .leading, spacing: 2) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded {
                        collapsedProjectsInChatSidebar.insert(group.id)
                        manuallyExpandedProjectsInChatSidebar.remove(group.id)
                    } else {
                        collapsedProjectsInChatSidebar.remove(group.id)
                        manuallyExpandedProjectsInChatSidebar.insert(group.id)
                    }
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                        .frame(width: 8)
                    
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                        .foregroundColor(isExpanded ? .accentColor : .secondary)
                    
                    Text(group.projectName)
                        .font(.system(size: 10, weight: isExpanded ? .bold : .medium))
                        .foregroundColor(isExpanded ? .primary : .secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if !isExpanded && !group.chats.isEmpty {
                        Text("\(group.chats.count)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(3)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                ForEach(group.chats) { chat in
                    ChatListRow(
                        chat: chat,
                        isActive: agent.activeChatId == chat.id,
                        onSelect: {
                            agent.switchChat(to: chat.id)
                            collapsedProjectsInChatSidebar.remove(group.id)
                        },
                        onDelete: { agent.deleteChat(chat.id) }
                    )
                }
            }
        }
    }
    
    private func isChatSidebarGroupExpanded(_ group: ProjectChatGroup) -> Bool {
        if collapsedProjectsInChatSidebar.contains(group.id) {
            return false
        }
        if manuallyExpandedProjectsInChatSidebar.contains(group.id) {
            return true
        }
        if let ws = appState.workspaceFolder?.path ?? agent.currentWorkspace, !ws.isEmpty, group.projectPath == ws {
            return true
        }
        if let activeId = agent.activeChatId, group.chats.contains(where: { $0.id == activeId }) {
            return true
        }
        return group.id == agent.projectGroups.first?.id
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let isCompact = geo.size.width < 760
                let isVeryCompact = geo.size.width < 520
                
                HStack(spacing: 5) {
                    // Sidebar Toggle
                    if allowsChatSidebar {
                        Button(action: { agent.showChatSidebar.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "sidebar.left")
                                    .font(.system(size: 10))
                                if !isCompact {
                                    Text("History")
                                        .font(.system(size: 11, weight: agent.showChatSidebar ? .semibold : .medium))
                                }
                            }
                            .foregroundColor(agent.showChatSidebar ? .primary : .secondary)
                            .padding(.horizontal, isCompact ? 6 : 7)
                            .frame(height: 24)
                            .background(agent.showChatSidebar ? Color.primary.opacity(0.09) : Color.clear)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .help("Chat History")
                    }
                    
                    // New Chat
                    Button(action: {
                        isPlanMode = false
                        planManager.clearPlan()
                        _ = agent.createNewChat(projectPath: agent.currentWorkspace ?? scopedWorkspacePath)
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 9.5, weight: .bold))
                            if !isCompact {
                                Text("New Chat")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, isCompact ? 6 : 8)
                        .frame(height: 24)
                        .background(Color.primary.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.primary.opacity(0.14), lineWidth: 0.8)
                        )
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("Create New Chat (⌘N)")

                    if sessionScope == .editor { Menu {
                        Button { showingTeamTasks = true } label: {
                            Label(teamIntegrations.teamTasksEnabled ? "Team tasks" : "Team tasks (off)", systemImage: "checklist")
                        }
                        Button { showingTeamIntegrations = true } label: {
                            Label("Configure Team collaboration", systemImage: "slider.horizontal.3")
                        }
                        if teamIntegrations.teamTasksEnabled, let task = TeamTaskService.shared.selectedTask {
                            Divider()
                            Text("Active: \(task.title)")
                            Text("\(task.status.label) · \(task.owner)")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.system(size: 10, weight: .medium))
                            if !isCompact { Text("Team") }
                            if teamIntegrations.teamTasksEnabled, TeamTaskService.shared.selectedTask != nil {
                                Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                            }
                        }
                        .font(.system(size: 10, weight: teamIntegrations.teamTasksEnabled && TeamTaskService.shared.selectedTask != nil ? .semibold : .regular))
                        .foregroundColor(teamIntegrations.teamTasksEnabled && TeamTaskService.shared.selectedTask != nil ? .primary : .secondary)
                        .frame(height: 24)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Configure Team tasks, Agent context, Slack, and Microsoft Teams") }

                    if sessionScope == .editor {
                        Menu {
                            Section("Live Multi-Platform Preview") {
                                Button("WebApp Preview (Localhost)") {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        appState.showPreviewInspector(tab: "web")
                                    }
                                }
                                Button("iOS Simulator Preview") {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        appState.showPreviewInspector(tab: "ios")
                                    }
                                }
                                Button("Android Emulator Preview") {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        appState.showPreviewInspector(tab: "android")
                                    }
                                }
                                Button("iPhone USB (Hardware)") {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        appState.showPreviewInspector(tab: "ios-physical")
                                    }
                                }
                                Button("Android USB (Hardware)") {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        appState.showPreviewInspector(tab: "android-physical")
                                    }
                                }
                                Button(previewDock.isDockVisible || deviceRuntime.showingEmbeddedDeviceDock || (appState.agenticContextVisible && appState.selectedInspectorTab == .preview) ? "Hide Preview Dock" : "Show Preview Dock") {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        let isShowing = previewDock.isDockVisible || deviceRuntime.showingEmbeddedDeviceDock || (appState.agenticContextVisible && appState.selectedInspectorTab == .preview)
                                         if isShowing {
                                             appState.hidePreviewInspector()
                                             previewDock.hideDock()
                                         } else {
                                             appState.showPreviewInspector()
                                         }
                                    }
                                }
                            }

                            Divider()

                            Button("Choose Device & Run…") {
                                deviceRuntime.showingDeviceRuntimeSheet = true
                            }

                            // Only render ready/booted simulators in the quick Menu to avoid allocating 80+ NSMenuItems when closed
                            let appleSimulators = deviceRuntime.devices.filter { $0.isAppleSimulator && $0.isReadyForLaunch }
                            let physicalAppleDevices = deviceRuntime.devices.filter(\.isPhysicalAppleDevice)
                            let androidDevices = deviceRuntime.devices.filter { $0.platform == .android }

                            if !appleSimulators.isEmpty {
                                Divider()
                                ForEach(AppleSimulatorFamily.previewOrder) { family in
                                    let devices = appleSimulators.filter { $0.appleSimulatorFamily == family }
                                    if !devices.isEmpty {
                                        Section(family.menuTitle) {
                                            ForEach(devices) { device in
                                                Button("\(device.name) — \(device.state)") {
                                                    Task { await openRuntimeDestination(device) }
                                                }
                                                .disabled(deviceRuntime.isWorking || !device.isReadyForLaunch)
                                            }
                                        }
                                    }
                                }
                            }

                            if !physicalAppleDevices.isEmpty {
                                Section("iPhone & iPad") {
                                    ForEach(physicalAppleDevices) { device in
                                        Button("\(device.name) — \(device.state)") {
                                            Task { await openRuntimeDestination(device) }
                                        }
                                        .disabled(deviceRuntime.isWorking || !device.isReadyForLaunch)
                                    }
                                }
                            }

                            if !androidDevices.isEmpty {
                                Section("Android Preview") {
                                    ForEach(androidDevices) { device in
                                        Button("\(device.name) — \(device.state)") {
                                            Task { await openRuntimeDestination(device) }
                                        }
                                        .disabled(deviceRuntime.isWorking || !device.isReadyForLaunch)
                                    }
                                }
                            }

                            if appleSimulators.isEmpty && physicalAppleDevices.isEmpty && androidDevices.isEmpty {
                                Text("No runtimes detected")
                            }

                            Divider()
                            Button("Refresh Devices") {
                                Task { await deviceRuntime.refresh(workspace: appState.workspaceFolder) }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "rectangle.portrait")
                                if !isCompact { Text("Preview") }
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7, weight: .semibold))
                            }
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(height: 24)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Choose an iPhone, iPad, Apple Watch, Apple TV, physical Apple device, or Android Preview")
                    }
                    
                    Divider().frame(height: 14).padding(.horizontal, 2)
                    
                    // Mode Tabs — Primary Heroes (Chat, Plan, Task) + Sleek More Dropdown
                    HStack(spacing: 2) {
                        modePill("Chat", icon: "bubble.left.and.bubble.right", isActive: !isPaperMode && !isCellMode && !isTaskMode && !isWalkthroughMode && !isPlanFullscreen, compact: isVeryCompact) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isPaperMode = false
                                isCellMode = false
                                isTaskMode = false
                                isWalkthroughMode = false
                                isPlanFullscreen = false
                                isPlanMode = false
                                planManager.isPlanVisible = false
                            }
                        }
                        modePill("Plan", icon: "list.bullet.clipboard", isActive: isPlanMode || planManager.isPlanVisible, compact: isVeryCompact) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isPlanMode || planManager.isPlanVisible {
                                    isPlanMode = false
                                    planManager.isPlanVisible = false
                                    isPlanFullscreen = false
                                } else {
                                    isPlanMode = true
                                    planManager.isPlanVisible = true
                                    isPaperMode = false
                                    isCellMode = false
                                    isTaskMode = false
                                    isWalkthroughMode = false
                                    if planManager.currentPlan == nil, let ws = appState.workspaceFolder?.path {
                                        planManager.loadFromTaskMarkdown(workspacePath: ws)
                                    }
                                }
                            }
                        }
                        modePill("Task", icon: "checklist", isActive: isTaskMode && activeTaskTab == 0, compact: isVeryCompact) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isTaskMode = true
                                activeTaskTab = 0
                                isPlanMode = false
                                planManager.isPlanVisible = false
                                isPaperMode = false
                                isCellMode = false
                                isWalkthroughMode = false
                                isPlanFullscreen = false
                            }
                        }

                        // Secondary views dropdown: Keeps header clean on all screen sizes & preserves focus on Plan/Task
                        let isSecondaryActive = isPaperMode || isCellMode || isWalkthroughMode || (isTaskMode && activeTaskTab > 0)
                        let secondaryLabel: String = {
                            if isWalkthroughMode { return "Walkthrough" }
                            if isPaperMode { return "Report" }
                            if isCellMode { return "Cells" }
                            if isTaskMode {
                                switch activeTaskTab {
                                case 1: return "Spec"
                                case 2: return "Walkthrough"
                                case 3: return "Logs"
                                case 4: return "Cost"
                                case 5: return "Audit"
                                case 6: return "Verify"
                                default: break
                                }
                            }
                            return "More"
                        }()

                        Menu {
                            Section("Verification & Planning") {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isTaskMode = true; activeTaskTab = 6
                                        isPlanMode = false; planManager.isPlanVisible = false
                                        isPaperMode = false; isCellMode = false; isWalkthroughMode = false; isPlanFullscreen = false
                                    }
                                } label: {
                                    Label("Consensus Engine (Builder vs. Auditor)", systemImage: "shield.checkered")
                                }

                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isWalkthroughMode = true; isPlanMode = false; planManager.isPlanVisible = false
                                        isPaperMode = false; isCellMode = false; isTaskMode = false
                                    }
                                } label: {
                                    Label("Walkthrough Artifact", systemImage: "sparkles")
                                }
                            }

                            Section("Analytics & Governance") {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isTaskMode = true; activeTaskTab = 4
                                        isPlanMode = false; planManager.isPlanVisible = false
                                        isPaperMode = false; isCellMode = false; isWalkthroughMode = false; isPlanFullscreen = false
                                    }
                                } label: {
                                    Label("Cost & Token Usage Dashboard", systemImage: "chart.bar.xaxis")
                                }

                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isTaskMode = true; activeTaskTab = 5
                                        isPlanMode = false; planManager.isPlanVisible = false
                                        isPaperMode = false; isCellMode = false; isWalkthroughMode = false; isPlanFullscreen = false
                                    }
                                } label: {
                                    Label("Sovereign Flight Recorder (Audit Trail)", systemImage: "airplane.circle")
                                }
                            }

                            Section("Diagnostics & Notebook") {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isTaskMode = true; activeTaskTab = 3
                                        isPlanMode = false; planManager.isPlanVisible = false
                                        isPaperMode = false; isCellMode = false; isWalkthroughMode = false; isPlanFullscreen = false
                                    }
                                } label: {
                                    Label("Diagnostic Logs (\(agent.activityLog.count))", systemImage: "terminal")
                                }

                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isCellMode = true; isPaperMode = false; isPlanMode = false; planManager.isPlanVisible = false; isTaskMode = false; isWalkthroughMode = false
                                    }
                                } label: {
                                    Label("Interactive Notebook Cells", systemImage: "square.grid.2x2")
                                }

                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isPaperMode = true; isCellMode = false; isPlanMode = false; planManager.isPlanVisible = false; isTaskMode = false; isWalkthroughMode = false
                                    }
                                } label: {
                                    Label("Research Report & Export", systemImage: "doc.text")
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(secondaryLabel)
                                    .font(.system(size: 10, weight: isSecondaryActive ? .semibold : .regular))
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(isSecondaryActive ? Color.primary.opacity(0.10) : Color.clear)
                            .cornerRadius(3)
                            .foregroundColor(isSecondaryActive ? .primary : .secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .padding(2)
                    
                    Spacer(minLength: 4)
                    
                    // Model Selector + Menu (only render in header when bottom input toolbar is hidden, avoiding duplicate 1,000+ item SwiftUI Menu trees)
                    HStack(spacing: 4) {
                        if !isVeryCompact && (isPlanMode || isTaskMode || isWalkthroughMode || isCellMode || isPaperMode) {
                            modelSelector
                        }

                        if appState.agentMode {
                            if let external = activeExternalAgentConfig,
                               external.type == .codexEngine || external.type == .claudeCode || external.type == .agy {
                                Menu {
                                    ForEach(ACPPermissionMode.allCases, id: \.self) { mode in
                                        Button {
                                            acpHost.setPermissionMode(mode, for: external.id)
                                        } label: {
                                            Text(mode.displayName)
                                            if external.permissionMode == mode { Image(systemName: "checkmark") }
                                        }
                                    }
                                } label: {
                                    Text(external.permissionMode == .fullAuto ? "Full Auto" : "Review")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .disabled(agent.isLoading)
                                .help("Autonomy for \(external.name)")
                            } else if activeExternalAgentConfig == nil {
                                ToolApprovalModePickerView(manager: toolApprovalManager)
                            }
                        }
                        
                        Menu {
                            Button {
                                showingAgentConnections = true
                            } label: {
                                Label("Agent Connections Hub…", systemImage: "link.badge.plus")
                            }
                            Button {
                                agentEcosystemTab = .rules
                                showingAgentEcosystem = true
                            } label: {
                                Label("Platform Rules & Interop", systemImage: "point.3.connected.trianglepath.dotted")
                            }
                            if !acpHost.registeredConfigs.isEmpty {
                                Divider()
                                ForEach(acpHost.registeredConfigs) { config in
                                    Button {
                                        switchToConfig(config)
                                    } label: {
                                        HStack {
                                            Label(config.name, systemImage: config.type.iconName)
                                            if acpHost.activeAgentId == config.id {
                                                Spacer()
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                                Divider()
                                Button {
                                    switchToNativeAgent()
                                } label: {
                                    HStack {
                                        Label("Use Internal AI", systemImage: "brain")
                                        if acpHost.activeAgentId == nil {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                            Divider()
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
                                acpHost.resetAllSessions()
                            } label: { Label("Clear Chat", systemImage: "trash") }
                        } label: {
                            Group {
                                if isCompact {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.system(size: 11))
                                } else {
                                    Text("Actions")
                                        .font(.system(size: 10))
                                }
                            }
                            .foregroundColor(.secondary)
                            .frame(height: 24)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()

                        Button(action: {
                            agentEcosystemTab = .rules
                            showingAgentEcosystem = true
                        }) {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .font(.system(size: 11))
                                .foregroundColor(MultiPlatformRulesEngine.shared.discoveredRules.isEmpty ? .secondary : .accentColor)
                                .frame(width: 20, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help("Platform Rules & Interop (Cursor, Zed, Cline, GLM)")
                        
                        Button(action: {
                            showingAgentConnections = true
                        }) {
                            Image(systemName: "link.badge.plus")
                                .font(.system(size: 11))
                                .foregroundColor(acpHost.registeredConfigs.isEmpty ? .secondary : .green)
                                .frame(width: 20, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help("Agent Connections Hub (Workser-style: Claude, AGY, OpenCode, Codex)")
                        
                        if let activeAgent = activeExternalAgentConfig {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 5, height: 5)
                                Text("ACP: \(currentModelDisplayName)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.primary.opacity(0.85))
                                Button {
                                    switchToNativeAgent()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(4)
                            .help("Running via \(activeAgent.name). Click x to return to Native.")
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(height: 32)
            .background(Color(nsColor: appState.appTheme.panelBackground))
        }
    }

    /// The Preview menu is destination-aware.  Android attaches to the live
    /// in-app dock; Apple destinations launch Apple's actual Simulator or
    /// paired physical device rather than being silently redirected to ADB.
    private func openRuntimeDestination(_ device: RuntimeDevice) async {
        deviceRuntime.selectedDeviceID = device.id
        if device.platform == .android {
            AppleSimulatorCaptureService.shared.stop()
            deviceRuntime.embeddedDockMode = .android
            deviceRuntime.showingEmbeddedDeviceDock = true
            deviceRuntime.showingEmbeddedAppleDock = false
            await MainActor.run {
                appState.showPreviewInspector(tab: "android")
            }
            await deviceRuntime.startEmbeddedAndroid()
            return
        }
        if device.isAppleSimulator {
            deviceRuntime.stopEmbeddedAndroid()
            deviceRuntime.embeddedDockMode = .ios
            deviceRuntime.showingEmbeddedDeviceDock = true
            deviceRuntime.showingEmbeddedAppleDock = true
            await MainActor.run {
                appState.showPreviewInspector(tab: "ios")
            }
            await deviceRuntime.startEmbeddedAppleSimulator()
            return
        }
        await deviceRuntime.startSelectedDevice()
    }
    
    private func modePill(_ label: String, icon: String? = nil, isActive: Bool, compact: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { action() } }) {
            HStack(spacing: 4) {
                if let ic = icon, compact {
                    Image(systemName: ic)
                        .font(.system(size: 10))
                } else {
                    Text(label)
                        .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                        .fixedSize()
                }
                if label == "Plan", planManager.currentPlan?.approvalState == .pending {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                } else if label == "Logs", agent.isLoading {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                } else if label == "Logs", agent.activityLog.contains(where: { $0.type == .error }) {
                    Circle()
                        .fill(Color(red: 0.90, green: 0.44, blue: 0.44))
                        .frame(width: 5, height: 5)
                }
            }
            .foregroundColor(isActive ? .primary : .secondary)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.primary.opacity(0.09) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(label)
    }
    
    // MARK: - Implementation Plan Workspace View
    
    private var planSidePanelView: some View {
        VStack(spacing: 0) {
            planSidePanelHeader
            
            Divider().background(borderColor)
            
            if let plan = planManager.currentPlan {
                if showRawMarkdownPlan {
                    planRawMarkdownView(plan: plan)
                } else {
                    planStructuredView(plan: plan)
                }
            } else {
                planEmptyStateView
            }
        }
        .background(workspaceBg)
    }
    
    private var planView: some View {
        planSidePanelView
    }
    
    private var planSidePanelHeader: some View {
        HStack(spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isPlanMode = false
                    planManager.isPlanVisible = false
                    isPlanFullscreen = false
                }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9.5, weight: .bold))
                    Text("Chat")
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.accentColor.opacity(0.12))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .help("Return to AI Chat")

            HStack(spacing: 6) {
                Image(systemName: "list.bullet.clipboard.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                
                Text("Implementation Plan")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .layoutPriority(1)
                
                if let plan = planManager.currentPlan {
                    approvalBadge(for: plan.approvalState)
                }
            }
            
            Spacer(minLength: 4)
            
            if let plan = planManager.currentPlan {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showRawMarkdownPlan.toggle()
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: showRawMarkdownPlan ? "list.bullet" : "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 9.5))
                        Text(showRawMarkdownPlan ? "Structured" : "Markdown")
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(showRawMarkdownPlan ? "Switch to interactive structured plan" : "Switch to raw markdown")
                
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(plan.rawMarkdown.isEmpty ? plan.summary : plan.rawMarkdown, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Copy full implementation plan")
            }
            
            Button(action: {
                if let ws = appState.workspaceFolder?.path {
                    let loaded = planManager.loadFromTaskMarkdown(workspacePath: ws)
                    if !loaded {
                        agent.messages.append(AgentMessageModel(
                            id: UUID().uuidString, role: .assistant,
                            content: "⚠️ No `.microcode/task.md` found in current workspace. Type `/plan <task>` to generate an Implementation Plan.",
                            toolResults: [], pendingChanges: [], timestamp: Date()
                        ))
                    }
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Reload plan from .microcode/task.md")
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isPlanFullscreen.toggle()
                }
            }) {
                Image(systemName: isPlanFullscreen ? "rectangle.split.2x1" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help(isPlanFullscreen ? "Exit Fullscreen (Restore Split View)" : "Expand Plan to Fullscreen")
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isPlanMode = false
                    planManager.isPlanVisible = false
                    isPlanFullscreen = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Close Plan Side Panel")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(panelBg)
    }
    
    private func approvalBadge(for state: PlanApprovalState) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(state == .approved ? Color.green.opacity(0.85) : (state == .rejected ? Color.red.opacity(0.85) : Color.orange.opacity(0.85)))
                .frame(width: 5, height: 5)
            Text(state.displayName)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
    
    private func planStructuredView(plan: ImplementationPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if plan.approvalState == .pending {
                    approvalActionCard(plan: plan)
                } else if plan.approvalState == .approved {
                    approvedStatusCard(plan: plan)
                } else if plan.approvalState == .rejected {
                    rejectedStatusCard(plan: plan)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if !plan.summary.isEmpty {
                        Text(plan.summary)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineSpacing(3)
                    }
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                            Text(plan.createdAt, style: .date)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .foregroundColor(.secondary)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(plan.createdAt, style: .time)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .foregroundColor(.secondary)
                        
                        if plan.totalSteps > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 10))
                                Text("\(plan.completedSteps)/\(plan.totalSteps) steps completed (\(Int(plan.progress * 100))%)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                            }
                            .foregroundColor(plan.progress >= 1.0 ? .green : .accentColor)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                
                if plan.totalSteps > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 6)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(plan.progress >= 1.0 ? Color.green : Color.accentColor)
                                .frame(width: max(4, geo.size.width * CGFloat(plan.progress)), height: 6)
                        }
                    }
                    .frame(height: 6)
                    .padding(.horizontal, 16)
                }
                
                if !plan.openQuestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.orange)
                            Text("Open Questions & Decisions")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(plan.openQuestions.enumerated()), id: \.offset) { _, question in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 12, weight: .bold))
                                    Text(question)
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.primary.opacity(0.9))
                                }
                            }
                        }
                        .padding(.leading, 6)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.07))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                }
                
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Proposed Changes")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(plan.sections.count) sections • \(plan.totalSteps) steps")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    
                    ForEach(plan.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(section.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(section.steps.count) steps")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.035))
                            .cornerRadius(5)
                            
                            VStack(spacing: 4) {
                                ForEach(section.steps) { step in
                                    planStepRow(sectionId: section.id, step: step)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                
                if !plan.verificationSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.accentColor)
                            Text("Verification Plan")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 16)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(plan.verificationSteps.enumerated()), id: \.offset) { idx, vStep in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(idx + 1).")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 20, alignment: .trailing)
                                    
                                    Text(vStep)
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.primary.opacity(0.9))
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(12)
                        .background(Color.primary.opacity(0.025))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                    }
                }
                
                Spacer().frame(height: 32)
            }
            .padding(.vertical, 16)
        }
        .background(workspaceBg)
    }
    
    private func approvalActionCard(plan: ImplementationPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("Plan Review Required")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange.opacity(0.85))
                        .frame(width: 5, height: 5)
                    Text("Awaiting Review")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }
            }
            
            Text("The AI agent is paused awaiting authorization before making code modifications.")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPlanMode = false
                        isPlanFullscreen = false
                        planManager.reject()
                    }
                }) {
                    Text("Reject")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPlanMode = false
                        isPlanFullscreen = false
                        planManager.approve()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Approve Plan & Proceed")
                            .font(.system(size: 10.5, weight: .medium))
                        Text("⌘↵")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.1))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(elevatedBg)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }
    
    private func approvedStatusCard(plan: ImplementationPlan) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10.5))
                .foregroundColor(.green.opacity(0.85))
            
            Text("Plan Approved & In Execution — Changes authorized")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(elevatedBg)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }
    
    private func rejectedStatusCard(plan: ImplementationPlan) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
            
            Text("Plan Rejected — No files modified")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(elevatedBg)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }
    
    private func planStepRow(sectionId: String, step: PlanStep) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: {
                let nextStatus: PlanStepStatus = (step.status == .completed) ? .pending : .completed
                planManager.updateStepStatus(sectionId: sectionId, stepId: step.id, status: nextStatus)
            }) {
                Image(systemName: step.status.statusIcon)
                    .font(.system(size: 12))
                    .foregroundColor(step.status.statusColor)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Click to mark as \(step.status == .completed ? "pending" : "completed")")
            
            if let action = step.action {
                Text("[\(action)]")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(action == "NEW" ? .green : (action == "DELETE" ? .red : .accentColor))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(
                        (action == "NEW" ? Color.green : (action == "DELETE" ? Color.red : Color.accentColor)).opacity(0.1)
                    )
                    .cornerRadius(3)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(step.description)
                    .font(.system(size: 11.5, weight: step.status == .completed ? .regular : .medium))
                    .foregroundColor(step.status == .completed ? .secondary : .primary)
                    .strikethrough(step.status == .completed)
                
                if let detail = step.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                if let fileLink = step.fileLink, !fileLink.isEmpty {
                    Button(action: {
                        if !PreviewDockService.shared.openFileFromReference(fileLink, workspacePath: appState.workspaceFolder?.path) {
                            let cleanPath = fileLink.replacingOccurrences(of: "file://", with: "")
                            let targetURL: URL
                            if cleanPath.hasPrefix("/") {
                                targetURL = URL(fileURLWithPath: cleanPath)
                            } else if let ws = appState.workspaceFolder {
                                targetURL = ws.appendingPathComponent(cleanPath)
                            } else {
                                targetURL = URL(fileURLWithPath: cleanPath)
                            }
                            PreviewDockService.shared.openFile(url: targetURL, makeActive: true)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 9))
                            Text(fileLink.replacingOccurrences(of: "file://", with: ""))
                                .font(.system(size: 10, design: .monospaced))
                                .underline()
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(step.status == .completed ? Color.primary.opacity(0.02) : Color.clear)
        .cornerRadius(5)
    }
    
    private func planRawMarkdownView(plan: ImplementationPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                RenderedMarkdownDocumentView(markdown: plan.rawMarkdown.isEmpty ? "# \(plan.title)\n\n\(plan.summary)" : plan.rawMarkdown)
                    .padding(16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(workspaceBg)
    }
    
    private var planEmptyStateView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 38))
                .foregroundColor(.secondary.opacity(0.5))
            
            VStack(spacing: 6) {
                Text("No Implementation Plan Active")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("Implementation Plans ensure architectural rigor and prevent accidental codebase changes without user approval.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    planEmptyLoadButton
                    planEmptyDraftButton
                }
                VStack(spacing: 8) {
                    planEmptyLoadButton
                    planEmptyDraftButton
                }
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }
    
    private var planEmptyLoadButton: some View {
        Button(action: {
            if let ws = appState.workspaceFolder?.path {
                let loaded = planManager.loadFromTaskMarkdown(workspacePath: ws)
                if !loaded {
                    inputText = "/plan "
                    isPlanMode = false
                }
            } else {
                inputText = "/plan "
                isPlanMode = false
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "doc.badge.plus")
                Text("Load task.md")
                    .lineLimit(1)
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private var planEmptyDraftButton: some View {
        Button(action: {
            inputText = "/plan Create implementation plan for the current task"
            isPlanMode = false
        }) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Draft Plan (/plan)")
                    .lineLimit(1)
            }
            .font(.system(size: 11.5, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.accentColor)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    // MARK: - Task Editor & Autonomous Task Runner
    
    @State private var taskMdText: String = ""
    @State private var agentMdText: String = ""
    @State private var walkthroughMdText: String = ""
    @State private var activeTaskTab: Int = 0 // 0 = task.md, 1 = agent.md, 2 = walkthrough.md, 3 = logs, 4 = cost, 5 = flight recorder
    @State private var taskViewMode: Int = 0  // 0 = Checklist Dashboard, 1 = Raw Markdown
    
    private struct ParsedTaskStep: Identifiable {
        let id: Int  // Stable identity based on line index — NOT UUID() which regenerates every render
        let lineIndex: Int
        let text: String
        var isCompleted: Bool
    }
    
    private func parseTaskSteps(from text: String) -> [ParsedTaskStep] {
        var steps: [ParsedTaskStep] = []
        let lines = text.components(separatedBy: .newlines)
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("* [ ] ") {
                let stepText = String(trimmed.dropFirst(6))
                steps.append(ParsedTaskStep(id: idx, lineIndex: idx, text: stepText, isCompleted: false))
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") || trimmed.hasPrefix("* [x] ") || trimmed.hasPrefix("* [X] ") {
                let stepText = String(trimmed.dropFirst(6))
                steps.append(ParsedTaskStep(id: idx, lineIndex: idx, text: stepText, isCompleted: true))
            }
        }
        return steps
    }
    
    private func toggleStepCompletion(lineIndex: Int) {
        var lines = taskMdText.components(separatedBy: .newlines)
        guard lineIndex >= 0 && lineIndex < lines.count else { return }
        let line = lines[lineIndex]
        if line.contains("- [ ]") {
            lines[lineIndex] = line.replacingOccurrences(of: "- [ ]", with: "- [x]")
        } else if line.contains("- [x]") {
            lines[lineIndex] = line.replacingOccurrences(of: "- [x]", with: "- [ ]")
        } else if line.contains("- [X]") {
            lines[lineIndex] = line.replacingOccurrences(of: "- [X]", with: "- [ ]")
        } else if line.contains("* [ ]") {
            lines[lineIndex] = line.replacingOccurrences(of: "* [ ]", with: "* [x]")
        } else if line.contains("* [x]") {
            lines[lineIndex] = line.replacingOccurrences(of: "* [x]", with: "* [ ]")
        }
        taskMdText = lines.joined(separator: "\n")
        saveTaskFiles()
    }
    
    private var taskEditorView: some View {
        VStack(spacing: 0) {
            // Task Control Toolbar
            HStack(spacing: 8) {
                // Scrollable Tabs so they never squeeze or overflow
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        taskEditorTab("Checklist", icon: "checklist", idx: 0)
                        taskEditorTab("Spec", icon: "doc.text", idx: 1)
                        taskEditorTab("Walkthrough", icon: "sparkles", idx: 2)
                        taskEditorTab("Logs", icon: "terminal", idx: 3, badge: agent.activityLog.count)
                        
                        if activeTaskTab == 4 {
                            taskEditorTab("Cost", icon: "chart.bar.xaxis", idx: 4)
                        } else if activeTaskTab == 5 {
                            taskEditorTab("Audit", icon: "airplane.circle", idx: 5)
                        } else if activeTaskTab == 6 {
                            taskEditorTab("Consensus", icon: "shield.checkered", idx: 6)
                        }
                    }
                    .padding(.vertical, 2)
                }
                
                Spacer(minLength: 4)
                
                // Trailing Action Controls (Fixed Size so they never collapse or distort)
                HStack(spacing: 6) {
                    if activeTaskTab < 3 {
                        // Compact View Mode Switcher (Rendered Document vs Edit Source)
                        HStack(spacing: 1) {
                            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { taskViewMode = 0 } }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "doc.richtext")
                                        .font(.system(size: 10, weight: taskViewMode == 0 ? .semibold : .regular))
                                    Text("Rendered")
                                        .font(.system(size: 9.5, weight: taskViewMode == 0 ? .semibold : .regular))
                                }
                                .foregroundColor(taskViewMode == 0 ? .primary : .secondary)
                                .padding(.horizontal, 6)
                                .frame(height: 22)
                                .background(taskViewMode == 0 ? Color.primary.opacity(0.12) : Color.clear)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .help("Rendered Document View")
                            
                            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { taskViewMode = 1 } }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 10, weight: taskViewMode == 1 ? .semibold : .regular))
                                    Text("Edit")
                                        .font(.system(size: 9.5, weight: taskViewMode == 1 ? .semibold : .regular))
                                }
                                .foregroundColor(taskViewMode == 1 ? .primary : .secondary)
                                .padding(.horizontal, 6)
                                .frame(height: 22)
                                .background(taskViewMode == 1 ? Color.primary.opacity(0.12) : Color.clear)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .help("Edit Markdown Source")
                        }
                        .padding(2)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(5)
                        
                        Divider().frame(height: 14).opacity(0.3)
                    }
                    
                    if activeTaskTab < 3 {
                        if agent.isLoading {
                            Button(action: { AgentService.shared.stopGeneration() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 8))
                                    Text("Stop")
                                        .font(.system(size: 10, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.red.opacity(0.95))
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(Color.red.opacity(0.12))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                            .help("Stop Task Execution")
                        } else {
                            Button(action: executeCurrentTaskPlan) {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 8))
                                    Text("Run")
                                        .font(.system(size: 10, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(Color.accentColor.opacity(0.2))
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                            .help("Run Task with Agent")
                        }
                        
                        // Save button
                        Button(action: saveTaskFiles) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down.doc")
                                    .font(.system(size: 8.5))
                                Text("Save")
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help("Save Markdown Files")
                    }
                }
                .fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(panelBg)
            .clipped()
            
            Divider().opacity(0.3)
            
            // Content Area
            if activeTaskTab == 0 {
                if taskViewMode == 0 {
                    // Checklist Dashboard View
                    let parsedSteps = parseTaskSteps(from: taskMdText)
                    let completedCount = parsedSteps.filter { $0.isCompleted }.count
                    let totalCount = parsedSteps.count
                    
                    VStack(spacing: 0) {
                        // Progress Bar Header
                        if totalCount > 0 {
                            HStack {
                                Text("\(completedCount) of \(totalCount) steps completed")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("\(Int((Double(completedCount) / Double(totalCount)) * 100))%")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                            
                            ProgressView(value: Double(completedCount), total: Double(totalCount))
                                .progressViewStyle(.linear)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 10)
                            
                            Divider().opacity(0.25)
                        }
                        
                        // Steps List
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                if parsedSteps.isEmpty {
                                    if !taskMdText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        RenderedMarkdownDocumentView(markdown: taskMdText)
                                            .padding(6)
                                    } else {
                                        VStack(spacing: 8) {
                                            Image(systemName: "list.bullet.rectangle")
                                                .font(.system(size: 24))
                                                .foregroundColor(.secondary.opacity(0.5))
                                            Text("No checklist steps found in task.md")
                                                .font(.system(size: 11.5))
                                                .foregroundColor(.secondary)
                                            Text("Add lines starting with `- [ ] Your step description`")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary.opacity(0.7))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.top, 40)
                                    }
                                } else {
                                    ForEach(parsedSteps) { step in
                                        HStack(alignment: .top, spacing: 10) {
                                            Button(action: { toggleStepCompletion(lineIndex: step.lineIndex) }) {
                                                Image(systemName: step.isCompleted ? "checkmark.square.fill" : "square")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(step.isCompleted ? .accentColor : .secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.top, 1)
                                            
                                            MarkdownTextView(text: step.text)
                                                .opacity(step.isCompleted ? 0.65 : 1.0)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            
                                            if !step.isCompleted && !agent.isLoading {
                                                Button(action: { executeSingleStep(step.text) }) {
                                                    HStack(spacing: 3) {
                                                        Image(systemName: "play.fill")
                                                            .font(.system(size: 7))
                                                        Text("Run Step")
                                                            .font(.system(size: 9.5))
                                                    }
                                                    .foregroundColor(.secondary)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(Color.primary.opacity(0.05))
                                                    .cornerRadius(4)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(step.isCompleted ? Color.primary.opacity(0.015) : Color.primary.opacity(0.035))
                                        .cornerRadius(6)
                                    }
                                    
                                    Divider().opacity(0.25).padding(.vertical, 8)
                                    RenderedMarkdownDocumentView(markdown: taskMdText)
                                        .padding(.horizontal, 8)
                                }
                            }
                            .padding(14)
                        }
                    }
                    .background(workspaceBg)
                } else {
                    TextEditor(text: $taskMdText)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(workspaceBg)
                }
            } else if activeTaskTab == 1 {
                if taskViewMode == 0 {
                    ScrollView {
                        RenderedMarkdownDocumentView(markdown: agentMdText)
                            .padding(18)
                    }
                    .background(workspaceBg)
                } else {
                    TextEditor(text: $agentMdText)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(workspaceBg)
                }
            } else if activeTaskTab == 2 {
                if taskViewMode == 0 {
                    ScrollView {
                        RenderedMarkdownDocumentView(markdown: walkthroughMdText)
                            .padding(18)
                    }
                    .background(workspaceBg)
                } else {
                    TextEditor(text: $walkthroughMdText)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(workspaceBg)
                }
            } else if activeTaskTab == 3 {
                TaskLogsView()
                    .environmentObject(appState)
            } else if activeTaskTab == 4 {
                // P5: Cost Dashboard
                CostDashboardView()
            } else if activeTaskTab == 5 {
                // P2: Flight Recorder / Audit Trail
                FlightRecorderView()
            } else if activeTaskTab == 6 {
                // Phase 1: Dual-Agent Consensus Engine
                ConsensusEngineView()
            }
        }
        .onAppear { loadTaskFiles() }
    }
    
    // MARK: - Dedicated Walkthrough View
    private var walkthroughView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Walkthrough Artifact")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Task accomplishments, verification results, and artifacts summary")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        loadTaskFiles()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                        .font(.system(size: 10))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                Divider()

                if walkthroughMdText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 50)
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No walkthrough generated yet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Once the Agent executes steps and produces walkthrough.md, the summary will render here.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        RenderedMarkdownDocumentView(markdown: walkthroughMdText)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(panelBg)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(workspaceBg)
        .onAppear { loadTaskFiles() }
    }
    
    private func executeCurrentTaskPlan() {
        saveTaskFiles()
        let providerString = appState.aiProvider
        let model = appState.aiModel.isEmpty ? "gemini-2.5-flash" : appState.aiModel
        let apiKey = appState.resolveApiKey(for: providerString)
        
        Task {
            await agent.executeTaskPlan(
                provider: providerString,
                model: model,
                apiKey: apiKey
            )
        }
    }
    
    private func executeSingleStep(_ stepText: String) {
        saveTaskFiles()
        let directive = """
        Execute this single task step from .microcode/task.md:
        
        Target Step: \(stepText)
        
        Instructions:
        1. Execute the necessary actions/tools to complete this specific step.
        2. Once completed, update .microcode/task.md to check off this step.
        """
        
        executeMessage(directive, attachments: [])
    }
    
    private func taskEditorTab(_ label: String, icon: String? = nil, idx: Int, badge: Int? = nil) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { activeTaskTab = idx } }) {
            HStack(spacing: 4) {
                if let ic = icon {
                    Image(systemName: ic)
                        .font(.system(size: 9))
                }
                Text(label)
                    .font(.system(size: 10, weight: activeTaskTab == idx ? .semibold : .medium))
                    .lineLimit(1)
                if let b = badge, b > 0 {
                    Text("\(b)")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.12))
                        .cornerRadius(3)
                }
            }
            .foregroundColor(activeTaskTab == idx ? .primary : .secondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(activeTaskTab == idx ? Color.primary.opacity(0.09) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("\(label) Tab")
    }
    
    private func loadTaskFiles() {
        guard let workspace = appState.workspaceFolder?.path else { return }
        let microcodeDir = (workspace as NSString).appendingPathComponent(".microcode")
        
        let taskPath = (microcodeDir as NSString).appendingPathComponent("task.md")
        let agentPath = (microcodeDir as NSString).appendingPathComponent("agent.md")
        let walkthroughPath = (microcodeDir as NSString).appendingPathComponent("walkthrough.md")
        
        taskMdText = (try? String(contentsOfFile: taskPath, encoding: .utf8)) ?? AgentService.defaultTaskMarkdown()
        agentMdText = (try? String(contentsOfFile: agentPath, encoding: .utf8)) ?? AgentService.defaultAgentMarkdown()
        walkthroughMdText = (try? String(contentsOfFile: walkthroughPath, encoding: .utf8)) ?? "# Walkthrough\n\n## Changes\n- Verified implementation\n\n## Verification\n- Tests passing\n\n## Privacy Audit\n- [x] Zero API keys or secrets detected in artifacts\n"
    }
    
    private func saveTaskFiles() {
        guard let workspace = appState.workspaceFolder?.path else { return }
        let microcodeDir = (workspace as NSString).appendingPathComponent(".microcode")
        
        let taskURL = URL(fileURLWithPath: (microcodeDir as NSString).appendingPathComponent("task.md"))
        let agentURL = URL(fileURLWithPath: (microcodeDir as NSString).appendingPathComponent("agent.md"))
        let walkthroughURL = URL(fileURLWithPath: (microcodeDir as NSString).appendingPathComponent("walkthrough.md"))
        
        // Zero-Privacy-Leakage enforcement: automatically redact any detected secrets before saving to disk
        let sanitizedTask = AgentPrivacyGuard.sanitize(taskMdText)
        let sanitizedAgent = AgentPrivacyGuard.sanitize(agentMdText)
        let sanitizedWalkthrough = AgentPrivacyGuard.sanitize(walkthroughMdText)
        
        if sanitizedTask != taskMdText { taskMdText = sanitizedTask }
        if sanitizedAgent != agentMdText { agentMdText = sanitizedAgent }
        if sanitizedWalkthrough != walkthroughMdText { walkthroughMdText = sanitizedWalkthrough }
        
        try? AgentPrivacyGuard.safeWrite(content: sanitizedTask, to: taskURL)
        try? AgentPrivacyGuard.safeWrite(content: sanitizedAgent, to: agentURL)
        try? AgentPrivacyGuard.safeWrite(content: sanitizedWalkthrough, to: walkthroughURL)
        
        // Reload into AgentService
        agent.setWorkspace(workspace)
    }
    
    // MARK: - Input Area
    
    @ViewBuilder
    private var inputCardView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Multiline text input
            if #available(macOS 13.0, *) {
                TextField("Ask anything, @ to mention, / for actions", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...8)
                    .focused($isInputFocused)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .onSubmit {
                        // If slash suggestions are showing and user presses Enter, select the highlighted command
                        if showSlashSuggestions && !slashCommandService.suggestions.isEmpty {
                            let cmd = slashCommandService.suggestions[min(slashSelectedIndex, slashCommandService.suggestions.count - 1)]
                            showSlashSuggestions = false
                            slashSelectedIndex = 0
                            let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            if trimmed == "/\(cmd.rawValue)" && !cmd.requiresArgument {
                                sendMessage()
                                return
                            }
                            inputText = "/\(cmd.rawValue) "
                            return
                        }
                        if !NSEvent.modifierFlags.contains(.shift) && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            sendMessage()
                        }
                    }
                    .onChange(of: inputText) { newValue in
                        // Slash Commands: detect /prefix without redundant @State mutations on normal keystrokes
                        slashCommandService.updateSuggestions(for: newValue)
                        let shouldShowSlash = slashCommandService.isShowingSuggestions
                        if showSlashSuggestions != shouldShowSlash {
                            showSlashSuggestions = shouldShowSlash
                        }
                        if !shouldShowSlash && slashSelectedIndex != 0 {
                            slashSelectedIndex = 0
                        }
                        
                        // @ Context Provider: detect @prefix only when actively typing a short token at the end
                        var nextShowContext = false
                        var nextContextPrefix = contextSearchPrefix
                        if newValue.count <= 2000, let atIdx = newValue.lastIndex(of: "@") {
                            let afterAt = String(newValue[newValue.index(after: atIdx)...])
                            if afterAt.count <= 48 && !afterAt.contains(" ") && !afterAt.contains("\n") && !afterAt.contains("/") && (atIdx == newValue.startIndex || newValue[newValue.index(before: atIdx)] == " " || newValue[newValue.index(before: atIdx)] == "\n") {
                                nextShowContext = true
                                nextContextPrefix = afterAt
                            }
                        }
                        if showContextSuggestions != nextShowContext {
                            showContextSuggestions = nextShowContext
                        }
                        if nextShowContext && contextSearchPrefix != nextContextPrefix {
                            contextSearchPrefix = nextContextPrefix
                        }
                    }
            } else {
                TextField("Ask anything, @ to mention, / for actions", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isInputFocused)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .onSubmit {
                        if !inputText.isEmpty { sendMessage() }
                    }
            }
            
            // Bottom Toolbar inside the Input Box (Single consolidated row)
            inputBottomToolbar
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isDropTargeted ? Color.accentColor : (isInputFocused ? Color.accentColor.opacity(0.4) : Color.clear), lineWidth: isDropTargeted ? 1.5 : 1)
        )
        .onDrop(of: ["public.file-url", "public.image", "public.data"], isTargeted: $isDropTargeted) { providers in
            handleDroppedProviders(providers)
        }
    }
    
    // MARK: - Compact Agent Activity & Queue Indicator
    
    @ViewBuilder
    private var activeAgentStatusHUD: some View {
        if agent.isLoading || agent.isProcessingQueue {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)

                Text(agent.agentPhase == .thinking ? "Thinking..." : agent.agentPhase.displayText)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
    
    @ViewBuilder
    private var queueIndicatorBar: some View {
        if !agent.messageQueue.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                
                Text("\(agent.messageQueue.count) message\(agent.messageQueue.count > 1 ? "s" : "") queued:")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.orange)
                
                if let first = agent.messageQueue.first {
                    Text("\"\(first.text)\"")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Steer Now (Stop current and execute immediately)
                Button(action: {
                    guard !agent.messageQueue.isEmpty else { return }
                    let nextItem = agent.messageQueue.removeFirst()
                    agent.stopGeneration(autoProcessQueue: false)
                    acpHost.stopActiveAgent()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        executeMessage(nextItem.text, attachments: nextItem.attachments)
                    }
                }) {
                    Text("Steer Now")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Interrupt active task and execute this queued message immediately")
                
                // Clear Queue
                Button(action: { agent.clearQueue() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(3)
                }
                .buttonStyle(.plain)
                .help("Clear all queued messages")
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
    
    private var inputArea: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            
            VStack(spacing: 0) {
                // Queue Indicator Bar
                queueIndicatorBar
                
                // Tool Approval Overlay
                if toolApprovalManager.pendingRequest != nil {
                    ToolApprovalView(manager: toolApprovalManager)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 4)
                }
                
                // Attachment Pills
                if !attachments.isEmpty {
                    attachmentsBar
                }
                
                // Attached Context Badges (from @ mentions)
                if !contextProviderService.attachedContexts.isEmpty {
                    attachedContextsBar
                }
                
                // Slash Command Suggestions (above input)
                if showSlashSuggestions && !slashCommandService.suggestions.isEmpty {
                    SlashCommandSuggestionView(
                        suggestions: slashCommandService.suggestions,
                        selectedIndex: slashSelectedIndex,
                        onSelect: { command in
                            showSlashSuggestions = false
                            slashSelectedIndex = 0
                            inputText = "/\(command.rawValue) "
                        }
                    )
                    .environmentObject(appState)
                    .transition(.opacity)
                    .padding(.bottom, 4)
                }
                
                // Context Provider Suggestions (above input when @ typed)
                if showContextSuggestions {
                    ContextProviderSuggestionView(
                        suggestions: contextProviderService.getSuggestions(for: contextSearchPrefix),
                        onSelect: { provider in
                            // Remove the @prefix from input and attach context
                            if let atIdx = inputText.lastIndex(of: "@") {
                                inputText = String(inputText[inputText.startIndex..<atIdx])
                            }
                            showContextSuggestions = false
                            contextSearchPrefix = ""
                            // For file/folder providers, the actual attachment happens via the provider
                            contextProviderService.selectProvider(provider)
                        },
                        selectedIndex: .constant(0)
                    )
                    .transition(.opacity)
                    .padding(.bottom, 4)
                }
                
                // Media Studio Parameter Bar (Image / Video / Music models)
                if AIClient.isAiPassMediaModel(appState.aiModel) {
                    mediaStudioParameterBar
                        .padding(.bottom, 5)
                }

                securityAndFailoverAlertsBar
                
                // Keep the composer visually aligned with the reading column.
                // The two flexible spacers leave a small gutter on narrow splits,
                // then centre the card and cap it at a comfortable desktop width.
                // Therefore opening Preview/Inspector changes its width instantly
                // instead of leaving a fixed, overly-wide input surface behind.
                inputCardView
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 880)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.clear)
    }
    
    private var attachmentsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { file in
                    AttachmentChipView(file: file, onRemove: {
                        attachments.removeAll(where: { $0.id == file.id })
                    })
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
        }
    }
    
    private var attachedContextsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(contextProviderService.attachedContexts) { ctx in
                    HStack(spacing: 4) {
                        Image(systemName: ctx.provider.icon)
                            .font(.system(size: 10))
                        Text(ctx.title)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Button(action: { contextProviderService.removeContext(ctx) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
    }
    
    private var mediaStudioParameterBar: some View {
        let isVideo = AIClient.isAiPassVideoModel(appState.aiModel)
        let isImage = AIClient.isAiPassImageModel(appState.aiModel)
        let isMusic = AIClient.isAiPassMusicModel(appState.aiModel)
        let ratios = ["16:9", "9:16", "1:1", "4:3", "21:9"]
        let resolutions = isVideo ? ["720p", "1080p", "4K"] : ["1K", "2K", "4K"]
        let durations = isMusic ? ["15s", "30s", "60s"] : ["5s", "8s", "10s"]
        
        return HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: isVideo ? "film" : (isMusic ? "waveform" : "photo"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(isVideo ? "VIDEO STUDIO" : (isMusic ? "AUDIO STUDIO" : "IMAGE STUDIO"))
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            if isImage || isVideo {
                Divider().frame(height: 12)
                HStack(spacing: 3) {
                    Text("Ratio")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                    ForEach(ratios, id: \.self) { r in
                        Button(action: { studioAspectRatio = r }) {
                            Text(r)
                                .font(.system(size: 9.5, weight: studioAspectRatio == r ? .semibold : .regular, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(studioAspectRatio == r ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
                                .foregroundColor(studioAspectRatio == r ? .accentColor : .secondary)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Divider().frame(height: 12)
                HStack(spacing: 3) {
                    Text("Res")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                    ForEach(resolutions, id: \.self) { res in
                        Button(action: { studioResolution = res }) {
                            Text(res)
                                .font(.system(size: 9.5, weight: studioResolution == res ? .semibold : .regular, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(studioResolution == res ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
                                .foregroundColor(studioResolution == res ? .accentColor : .secondary)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            if isVideo || isMusic {
                Divider().frame(height: 12)
                HStack(spacing: 3) {
                    Text("Length")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                    ForEach(durations, id: \.self) { dur in
                        Button(action: { studioDuration = dur }) {
                            Text(dur)
                                .font(.system(size: 9.5, weight: studioDuration == dur ? .semibold : .regular, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(studioDuration == dur ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
                                .foregroundColor(studioDuration == dur ? .accentColor : .secondary)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Spacer(minLength: 4)
            
            if isImage || isVideo {
                Button(action: pickFile) {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 9.5))
                        Text(isVideo ? "Image-to-Video Ref" : "Image-to-Image Ref")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundColor(.primary.opacity(0.85))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Attach a reference image for Image-to-Video or Image-to-Image generation")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var inputBottomToolbar: some View {
        HStack(spacing: 6) {
            plusActionMenu
            modelSelectorDropdown
                .layoutPriority(1)

            if sessionScope == .editor {
                scopeLockMenuPill
                AgentTargetEnvironmentMenu(showingAddServer: $showingAddServerSheet)
            }
            
            Spacer(minLength: 4)
            
            // SubAgent Dropdown Pill Button (Consolidated into main input toolbar)
            Button(action: { showSubAgentDropdown.toggle() }) {
                HStack(spacing: 3) {
                    let runningCount = SubAgentHarness.shared.activeSubagents.filter { $0.state == .running }.count
                    if runningCount > 0 {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                    Text(selectedSubAgentType == "main" ? "Agent" : selectedSubAgentDisplayName)
                        .font(.system(size: 10, weight: selectedSubAgentType == "main" ? .regular : .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                }
                .foregroundColor(selectedSubAgentType == "main" ? .secondary.opacity(0.85) : .accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(selectedSubAgentType == "main" ? Color.primary.opacity(0.03) : Color.accentColor.opacity(0.1))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .popover(isPresented: $showSubAgentDropdown, arrowEdge: .bottom) {
                SubAgentSelectorMenu(
                    selectedType: $selectedSubAgentType,
                    isPresented: $showSubAgentDropdown
                )
                .environmentObject(appState)
            }
            
            voiceInputButton
                .fixedSize()
            
            sendOrStopButton
                .fixedSize()
        }
        .padding(.top, 2)
    }

    // MARK: - Feature #4: Scope Lock & Protected Files Menu Pill

    private var scopeLockMenuPill: some View {
        let ws = agent.currentWorkspace ?? scopedWorkspacePath
        let activeFilePath = appState.currentFile?.path
        let isActiveLocked = activeFilePath.map { scopeGuard.isLocked($0, workspaceRoot: ws) } ?? false
        let hasActiveGuard = !scopeGuard.lockedPaths.isEmpty || scopeGuard.strictMentionOnlyScope

        return Menu {
            if let file = appState.currentFile {
                Button {
                    scopeGuard.toggleLock(file.path, workspaceRoot: ws)
                } label: {
                    Label(
                        isActiveLocked ? "Unlock \(file.name)" : "Lock \(file.name) (Protect from AI)",
                        systemImage: isActiveLocked ? "lock.open" : "lock.fill"
                    )
                }
                Divider()
            }

            Button {
                scopeGuard.strictMentionOnlyScope.toggle()
            } label: {
                HStack {
                    Label("Strict Scope (Edit Only @Mentioned Files)", systemImage: "scope")
                    if scopeGuard.strictMentionOnlyScope {
                        Image(systemName: "checkmark")
                    }
                }
            }

            if let root = ws, !root.isEmpty {
                Button {
                    _ = scopeGuard.lockCoreConfigFiles(in: root)
                } label: {
                    Label("Lock Core Configs (.env, package.json, Cargo.toml)", systemImage: "shield.lefthalf.filled")
                }
            }

            if !scopeGuard.lockedPaths.isEmpty {
                Divider()
                Section("Locked Files (\(scopeGuard.lockedPaths.count))") {
                    ForEach(Array(scopeGuard.lockedPaths).sorted(), id: \.self) { lockedPath in
                        let name = URL(fileURLWithPath: lockedPath).lastPathComponent
                        Button {
                            scopeGuard.toggleLock(lockedPath, workspaceRoot: ws)
                        } label: {
                            Label("Unlock \(name)", systemImage: "lock.fill")
                        }
                    }
                    Button(role: .destructive) {
                        scopeGuard.unlockAll(workspaceRoot: ws)
                    } label: {
                        Label("Unlock All Files", systemImage: "lock.open.fill")
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isActiveLocked ? "lock.fill" : (scopeGuard.strictMentionOnlyScope ? "scope" : "lock.shield"))
                    .font(.system(size: 10, weight: .semibold))
                if isActiveLocked {
                    Text("Locked")
                        .font(.system(size: 9.5, weight: .semibold))
                } else if scopeGuard.strictMentionOnlyScope {
                    Text("Strict")
                        .font(.system(size: 9.5, weight: .semibold))
                } else if !scopeGuard.lockedPaths.isEmpty {
                    Text("\(scopeGuard.lockedPaths.count)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                }
            }
            .foregroundColor(hasActiveGuard ? .orange : .secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(hasActiveGuard ? Color.orange.opacity(0.14) : Color.primary.opacity(0.04))
            .cornerRadius(5)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Scope Lock & Protected Files Guard — Lock files from AI edits or enforce Strict @Mention Scope")
    }

    // MARK: - Feature #3 & #7: Auto-Failover & Secret Leak Shield Alerts Bar

    @ViewBuilder
    private var securityAndFailoverAlertsBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let failoverBanner = agent.lastFailoverBanner {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    Text(failoverBanner)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.primary.opacity(0.9))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        agent.lastFailoverBanner = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.09))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.green.opacity(0.25), lineWidth: 0.8)
                )
            }

            if let toast = secretActionToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    Text(toast)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Button {
                        secretActionToast = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.10))
                .cornerRadius(6)
            }

            ForEach(secretShield.activeAlerts.prefix(2)) { alert in
                HStack(spacing: 8) {
                    Image(systemName: "key.radiowaves.forward.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Secret Leak Shield: \(alert.findings.count) credential(s) detected in \(alert.fileName)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.orange)
                        Text(alert.findings.map { "\($0.ruleName) (\($0.maskedSnippet))" }.joined(separator: " · "))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        let summary = secretShield.moveSecretsToEnv(
                            alert: alert,
                            workspaceRoot: agent.currentWorkspace ?? scopedWorkspacePath
                        )
                        secretActionToast = summary
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.doc.fill")
                                .font(.system(size: 9))
                            Text("Move to .env")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.20))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Extract hardcoded secrets to .env, add .env to .gitignore, and replace with env variable lookup")

                    Button {
                        secretShield.dismissAlert(alert)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 0.8)
                )
            }
        }
    }

    // MARK: - Feature #8: "Where Was I?" Instant Project Briefing Card

    private func projectBriefingCardView(_ briefing: ProjectBriefingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text("Project Briefing")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.primary.opacity(0.9))
                }

                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 8.5))
                    Text(briefing.gitBranch)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)

                if !briefing.modifiedFiles.isEmpty {
                    Text("\(briefing.modifiedFiles.count) uncommitted")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(4)
                }

                if briefing.completedTasksCount > 0 || !briefing.pendingTasks.isEmpty {
                    Text("\(briefing.completedTasksCount) done · \(briefing.pendingTasks.count) pending")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    agent.refreshProjectBriefing()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh Git & Task Briefing")

                Button {
                    executeMessage(briefing.suggestedNextPrompt)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8))
                        Text("Resume Next Step")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.16))
                    .foregroundColor(.accentColor)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help(briefing.suggestedNextPrompt)
            }

            if !briefing.lastConversationSummary.isEmpty {
                Text(briefing.lastConversationSummary)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if !briefing.modifiedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(briefing.modifiedFiles.prefix(6), id: \.self) { file in
                            Button {
                                inputText = "@\(file) " + inputText
                                isInputFocused = true
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "doc.badge.gearshape")
                                        .font(.system(size: 8))
                                    Text(URL(fileURLWithPath: file).lastPathComponent)
                                        .font(.system(size: 9.5, design: .monospaced))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.05))
                                .foregroundColor(.primary.opacity(0.8))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .help("Click to @mention \(file)")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
    }
    
    private var voiceInputButton: some View {
        Button(action: {
            Task {
                await voiceCoding.toggleListening()
            }
        }) {
            ZStack {
                Circle()
                    .fill(voiceCoding.state == .listening ? Color.red.opacity(0.18) : Color.primary.opacity(0.05))
                    .frame(width: 26, height: 26)
                
                if voiceCoding.state == .listening {
                    Circle()
                        .stroke(Color.red.opacity(0.6), lineWidth: 1.2)
                        .frame(width: 26, height: 26)
                }
                
                Image(systemName: voiceCoding.state == .listening ? "mic.fill" : "mic")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(voiceCoding.state == .listening ? .red : .secondary)
            }
        }
        .buttonStyle(.plain)
        .help(voiceCoding.state == .listening ? "Stop voice recording" : "Voice Input (Speak to AI)")
    }
    
    private var plusActionMenu: some View {
        Menu {
            Button(action: pickFile) {
                Label("Add Files or Images...", systemImage: "paperclip")
            }
            Button(action: {
                if let file = appState.currentFile {
                    inputText = "@\(file.name) " + inputText
                }
            }) {
                Label("Mention Active File", systemImage: "doc.text")
            }
            Divider()
            Button(action: {
                inputText = "/plan " + inputText
            }) {
                Label("Plan Mode (/plan)", systemImage: "list.bullet.rectangle")
            }
            Button(action: {
                inputText = "/review " + inputText
            }) {
                Label("Code Review (/review)", systemImage: "checkmark.shield")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.04))
                .clipShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24, height: 24)
    }
    
    private var isDotminiSubscribed: Bool {
        BillingService.shared.currentTier == .pro ||
        !(UserDefaults.standard.string(forKey: "dotminiLicenseKey")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    
    private var availableProvidersForDropdown: [AIProviderDefinition] {
        let allProviders = AIModelCatalog.shared.providers
        var result: [AIProviderDefinition] = []
        
        // 1. If user is subscribed to Dotmini Cloud, put Dotmini Cloud on top
        if isDotminiSubscribed {
            if let omni = allProviders.first(where: { $0.id == "omni" }) {
                result.append(omni)
            }
        }
        
        // 2. BYOK Providers (Google Gemini, Claude, OpenAI, DeepSeek, Grok, Qwen, GLM)
        let byokProviders = allProviders.filter { $0.id != "omni" }
        
        // Sort providers that have a configured API key first
        let withKey = byokProviders.filter { hasActiveKey($0.id) }
        let withoutKey = byokProviders.filter { !hasActiveKey($0.id) }
        
        result.append(contentsOf: withKey)
        result.append(contentsOf: withoutKey)
        
        return result
    }
    
    private var modelSelectorDropdown: some View {
        Button(action: {
            if !appState.isCurrentAIConnected {
                showingAgentConnections = true
            } else {
                presentNativeModelMenu()
            }
        }) {
            HStack(spacing: 5) {
                if !appState.isCurrentAIConnected {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Connect AI")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                } else {
                    AIProviderBrandIcon(provider: activeBrandIconKey, size: 13)
                    Text("\(currentExecutionMode.badgeTitle) · \(currentModelDisplayName)")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 235)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var sendOrStopButton: some View {
        Group {
            let hasInput = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
            
            if agent.isLoading {
                HStack(spacing: 5) {
                    if hasInput {
                        // Queue Button (Adds prompt to queue without stopping current task)
                        Button(action: enqueueCurrentInput) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.88))
                                    .frame(width: 24, height: 24)
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Add to Queue (Runs after active task finishes)")

                        // Send Now Button (Stops current loop & sends new message immediately)
                        Button(action: sendMessage) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 26, height: 26)
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Send Immediately (Interrupts active loop and starts new message)")
                    }

                    // Stop Button
                    Button(action: {
                        agent.stopGeneration()
                        acpHost.stopActiveAgent()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.85))
                                .frame(width: 26, height: 26)
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                                .cornerRadius(1.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Stop active AI task")
                }
            } else {
                Button(action: sendMessage) {
                    ZStack {
                        Circle()
                            .fill(hasInput ? Color.accentColor : Color.primary.opacity(0.12))
                            .frame(width: 26, height: 26)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(hasInput ? .white : .secondary.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!hasInput)
                .help("Send Message")
            }
        }
    }
    
    // MARK: - Suggested Action Bar
    
    private func suggestedActionBar(_ suggestion: SuggestedAction) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            
            HStack(spacing: 8) {
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
                    inputText = "Run the project and show me the output"
                    sendMessage()
                    agent.suggestedAction = nil
                }) {
                    Text("Run")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.09))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                
                Button(action: { agent.suggestedAction = nil }) {
                    Text("Dismiss")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.035))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
            .frame(maxWidth: 880)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Live Task Activity Banner
    
    private var liveTaskActivityBanner: some View {
        let latestToolCount = agent.messages.last?.toolResults.count ?? 0
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)
                
                Text(agent.currentToolExecution ?? agent.agentPhase.displayText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                if latestToolCount > 0 {
                    Text("\(latestToolCount) step\(latestToolCount == 1 ? "" : "s")")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
                
                Spacer(minLength: 4)
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if planManager.currentPlan != nil || planManager.isPlanVisible {
                            isPlanMode = true
                            planManager.isPlanVisible = true
                            isTaskMode = false
                        } else {
                            isTaskMode = true
                            activeTaskTab = 0
                            isPlanMode = false
                            planManager.isPlanVisible = false
                        }
                        isPaperMode = false
                        isCellMode = false
                        isWalkthroughMode = false
                        isPlanFullscreen = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 9.5))
                        Text(planManager.currentPlan != nil ? "Plan" : "Tasks")
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTaskMode = true
                        activeTaskTab = 3
                        isPlanMode = false
                        planManager.isPlanVisible = false
                        isPaperMode = false
                        isCellMode = false
                        isWalkthroughMode = false
                        isPlanFullscreen = false
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "terminal")
                            .font(.system(size: 9))
                        Text("\(agent.activityLog.count)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Inspect low-level diagnostic logs & tool executions")
                
                Button(action: {
                    agent.stopGeneration()
                    acpHost.stopActiveAgent()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("Stop")
                            .font(.system(size: 9.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundColor(.red.opacity(0.9))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Stop current agent run")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
            .frame(maxWidth: 880)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Context Limit Banner
    
    private var contextLimitBanner: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 13))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conversation Context Limit Reached")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("The current thread has utilized its full token window. Start a new conversation for optimal reasoning and speed.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    _ = agent.createNewChat(projectPath: agent.currentWorkspace ?? scopedWorkspacePath)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.bubble.fill")
                        Text("New Conversation")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
            )
            .frame(maxWidth: 880)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - File Attachment Logic
    
    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .image,
            .png,
            .jpeg,
            .pdf,
            .plainText,
            .sourceCode,
            .json,
            .data
        ]
        
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
            
            if ["png", "jpg", "jpeg", "webp", "heic", "gif", "bmp", "tiff", "svg"].contains(ext) {
                let fmt = (ext == "jpg" || ext == "jpeg") ? "jpeg" : (ext == "svg" ? "svg+xml" : ext)
                type = .image(format: fmt)
            } else if ext == "pdf" {
                type = .pdf
            } else {
                type = .text // Default to text for code/markdown/data files
            }
            
            let attachment = AIAttachment(name: fileName, data: data, type: type)
            attachments.append(attachment)
        } catch {
            print("Failed to read file: \(error)")
        }
    }
    
    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                    guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                        if let url = item as? URL {
                            DispatchQueue.main.async { self.processFile(url) }
                        }
                        return
                    }
                    DispatchQueue.main.async { self.processFile(url) }
                }
            } else if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, error in
                    guard let data = data else { return }
                    DispatchQueue.main.async {
                        let name = "dropped_image_\(Int(Date().timeIntervalSince1970)).png"
                        let attachment = AIAttachment(name: name, data: data, type: .image(format: "png"))
                        self.attachments.append(attachment)
                    }
                }
            }
        }
        return true
    }
    
    private func pasteClipboardContent() {
        let pb = NSPasteboard.general
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], let firstImg = images.first {
            if let tiff = firstImg.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let pngData = bitmap.representation(using: .png, properties: [:]) {
                let name = "pasted_image_\(Int(Date().timeIntervalSince1970)).png"
                let attachment = AIAttachment(name: name, data: pngData, type: .image(format: "png"))
                attachments.append(attachment)
                return
            }
        }
        
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                processFile(url)
            }
        }
    }
    
    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { return }
        var userText = inputText
        let currentAttachments = attachments
        
        // Dismiss any open suggestions and ensure Chat stage is visible (not hidden behind full-column Plan/Task views)
        showSlashSuggestions = false
        showContextSuggestions = false
        isTaskMode = false
        isWalkthroughMode = false
        isPaperMode = false
        isPlanFullscreen = false
        isPlanMode = false
        planManager.isPlanVisible = false
        
        inputText = ""
        attachments = []
        
        // Handle Slash Commands
        if userText.starts(with: "/") {
            if let parsed = slashCommandService.parseInput(userText) {
                switch parsed.command {
                case .clear:
                    agent.clearCurrentChat()
                    return
                case .compact:
                    // Keep only the last 10 messages to save context
                    if agent.messages.count > 10 {
                        let keep = Array(agent.messages.suffix(10))
                        agent.messages = keep
                    }
                    let compactMsg = AgentMessageModel(
                        id: UUID().uuidString, role: .assistant,
                        content: "💡 Chat compacted — kept last \(min(agent.messages.count, 10)) messages.",
                        toolResults: [], pendingChanges: [], timestamp: Date()
                    )
                    agent.messages.append(compactMsg)
                    return
                case .help:
                    if let helpText = slashCommandService.executeCommand(.help, argument: "") {
                        let helpMsg = AgentMessageModel(
                            id: UUID().uuidString, role: .assistant,
                            content: helpText,
                            toolResults: [], pendingChanges: [], timestamp: Date()
                        )
                        agent.messages.append(helpMsg)
                    }
                    return
                case .model:
                    // Model switching placeholder — show current info
                    let modelMsg = AgentMessageModel(
                        id: UUID().uuidString, role: .assistant,
                        content: "Model selection is available in the settings panel. Use the model picker above the chat input.",
                        toolResults: [], pendingChanges: [], timestamp: Date()
                    )
                    agent.messages.append(modelMsg)
                    return
                case .learn:
                    let ruleText = parsed.argument.trimmingCharacters(in: .whitespacesAndNewlines)
                    let ws = agent.currentWorkspace ?? appState.workspaceFolder?.path ?? FileManager.default.currentDirectoryPath
                    if !ruleText.isEmpty {
                        ProjectMemoryService.shared.appendLearnedRule(ruleText, workspace: ws)
                        let savedMsg = AgentMessageModel(
                            id: UUID().uuidString, role: .assistant,
                            content: "**Saved Project Rule** to `.microcode/rules.md`:\n\n- \(ruleText)",
                            toolResults: [], pendingChanges: [], timestamp: Date()
                        )
                        agent.messages.append(savedMsg)
                    } else {
                        let usageMsg = AgentMessageModel(
                            id: UUID().uuidString, role: .assistant,
                            content: "Usage: `/learn <rule>` — appends a persistent rule to `.microcode/rules.md` and injects it automatically into all future Agent turns.",
                            toolResults: [], pendingChanges: [], timestamp: Date()
                        )
                        agent.messages.append(usageMsg)
                    }
                    return
                case .squad:
                    let arg = parsed.argument.trimmingCharacters(in: .whitespacesAndNewlines)
                    if arg.isEmpty {
                        subAgentHarness.showSquadBuilderSheet = true
                        return
                    }
                    runCEOSquadMessage(arg, attachments: currentAttachments)
                    return
                default:
                    // Transform slash command into a prompt
                    if let promptPrefix = slashCommandService.executeCommand(parsed.command, argument: parsed.argument) {
                        userText = promptPrefix
                    }
                }
            }
        }
        
        // Inject @ Context Provider content
        let contextPrompt = contextProviderService.buildContextPrompt()
        if !contextPrompt.isEmpty {
            userText = userText + "\n\n" + contextPrompt
            contextProviderService.clearAll()
        }
        
        // If AI is busy when the user hits Enter / Send, interrupt the current turn cleanly
        // (preserving its partial output as a permanent message) and start the new request immediately.
        if agent.isLoading {
            agent.stopGeneration(autoProcessQueue: false)
            acpHost.stopActiveAgent()
        }
        
        executeMessage(userText, attachments: currentAttachments)
    }

    private func enqueueCurrentInput() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !attachments.isEmpty else { return }
        var userText = trimmedText
        let currentAttachments = attachments
        inputText = ""
        attachments = []
        let contextPrompt = contextProviderService.buildContextPrompt()
        if !contextPrompt.isEmpty {
            userText = userText + "\n\n" + contextPrompt
            contextProviderService.clearAll()
        }
        agent.enqueueMessage(userText, attachments: currentAttachments)
    }
    
    private func runCEOSquadMessage(_ userText: String, attachments currentAttachments: [AIAttachment] = []) {
        let fullUserContent = userText + (currentAttachments.isEmpty ? "" : "\n[Attached: \(currentAttachments.map(\.name).joined(separator: ", "))]")
        _ = agent.prepareUserTurn(fullUserContent, createStreamingPlaceholder: false)
        
        let responseId = UUID().uuidString
        let preset = subAgentHarness.activeSquadPreset ?? AgentSquadPreset.builtInPresets[0]
        agent.messages.append(AgentMessageModel(
            id: responseId, role: .assistant,
            content: "👔 **CEO & Specialist Squad (`\(preset.name)`)** กำลังเริ่มต้นประชุมแบ่งงานและล็อกขอบเขตไฟล์...",
            toolResults: [], pendingChanges: [], timestamp: Date()
        ))
        agent.isLoading = true
        agent.saveChats()
        let ws = agent.currentWorkspace ?? appState.workspaceFolder?.path
        
        Task { @MainActor in
            let finalReport = await SubAgentHarness.shared.runCEOSquadSession(
                objective: userText,
                workspacePath: ws,
                presetOverride: preset,
                onProgress: { statusText in
                    if let idx = self.agent.messages.firstIndex(where: { $0.id == responseId }) {
                        self.agent.messages[idx] = AgentMessageModel(
                            id: responseId, role: .assistant,
                            content: statusText,
                            toolResults: [], pendingChanges: [], timestamp: Date()
                        )
                    }
                }
            )
            if let idx = self.agent.messages.firstIndex(where: { $0.id == responseId }) {
                self.agent.messages[idx] = AgentMessageModel(
                    id: responseId, role: .assistant,
                    content: finalReport,
                    toolResults: [], pendingChanges: [], timestamp: Date()
                )
            }
            self.agent.isLoading = false
            self.agent.saveChats()
        }
    }
    
    private func runDirectSubAgentMessage(typeName: String, userText: String, attachments currentAttachments: [AIAttachment] = []) {
        let fullUserContent = userText + (currentAttachments.isEmpty ? "" : "\n[Attached: \(currentAttachments.map(\.name).joined(separator: ", "))]")
        _ = agent.prepareUserTurn(fullUserContent, createStreamingPlaceholder: false)
        
        let responseId = UUID().uuidString
        let roleName = SubAgentHarness.shared.registeredDefinitions[typeName]?.role ?? typeName.capitalized
        let ws = agent.currentWorkspace ?? appState.workspaceFolder?.path
        let instance = SubAgentHarness.shared.invokeSubagent(
            typeName: typeName,
            role: roleName,
            prompt: userText,
            workspacePath: ws
        )
        agent.messages.append(AgentMessageModel(
            id: responseId, role: .assistant,
            content: "⚡ **[\(roleName)] (`\(instance.endpointBadge ?? "Active Model")`)** กำลังดำเนินการ...",
            toolResults: [], pendingChanges: [], timestamp: Date()
        ))
        agent.isLoading = true
        agent.saveChats()
        
        Task { @MainActor in
            let outcome = try? await SubAgentHarness.shared.waitForSubagent(id: instance.id)
            let report = outcome?.instance.finalReport ?? outcome?.instance.stateDetail ?? "SubAgent finished."
            let badge = outcome?.instance.endpointBadge ?? roleName
            let formatted = "### ⚡ \(roleName) (`\(badge)`)\n\n\(report)"
            if let idx = self.agent.messages.firstIndex(where: { $0.id == responseId }) {
                self.agent.messages[idx] = AgentMessageModel(
                    id: responseId, role: .assistant,
                    content: formatted,
                    toolResults: [], pendingChanges: [], timestamp: Date()
                )
            }
            self.agent.isLoading = false
            self.agent.saveChats()
        }
    }
    
    private func executeMessage(_ userText: String, attachments currentAttachments: [AIAttachment] = []) {
        if !appState.isCurrentAIConnected {
            showingAgentConnections = true
            return
        }
        
        // Editor state belongs only to the software session. Science uses its
        // own research root, selected artifacts and compact evidence index.
        if sessionScope == .editor, let file = appState.currentFile {
            agent.updateEditorContext(
                activeFile: file.path,
                content: file.content,
                cursorLine: nil,
                selectedText: nil,
                openFiles: appState.openFiles.map { $0.path },
                language: file.language
            )
        }
        
        // Never overwrite the independent Science workspace with the Editor's
        // project when a message is sent.
        if sessionScope == .editor, let workspace = appState.workspaceFolder {
            if agent.currentWorkspace != workspace.path {
                agent.setWorkspace(workspace.path)
            }
        }
        
        // Route to CEO & Specialist Squad Mode when a Squad Preset is selected in SubAgentSelectorMenu
        if selectedSubAgentType.hasPrefix("squad:") {
            let presetId = String(selectedSubAgentType.dropFirst("squad:".count))
            subAgentHarness.activeSquadPresetId = presetId
            runCEOSquadMessage(userText, attachments: currentAttachments)
            return
        }
        
        // Route to a specific Specialized SubAgent when selected in SubAgentSelectorMenu
        if selectedSubAgentType != "main" {
            runDirectSubAgentMessage(typeName: selectedSubAgentType, userText: userText, attachments: currentAttachments)
            return
        }
        
        // Route to External ACP Agent (Claude Code, Antigravity, OpenCode, Aider, Codex Engine, Zed) ONLY when explicitly in ACP mode
        var targetConfig: ACPAgentConfig? = nil
        let isExplicitACPMode = (UserDefaults.standard.string(forKey: "aiKeyMode") == "acp") || (acpHost.activeAgentId != nil)
        if let activeAgentId = acpHost.activeAgentId,
           let cfg = acpHost.registeredConfigs.first(where: { $0.id == activeAgentId }) {
            targetConfig = cfg
        } else if isExplicitACPMode {
            if appState.aiProvider == "agy" {
                targetConfig = acpHost.registeredConfigs.first(where: { $0.type == .agy }) ?? {
                    let bin = LocalEcosystemDiscovery.shared.engines.first(where: { $0.id == "agy" })?.binaryPath ?? ACPAgentType.agy.defaultCommand
                    let cfg = ACPAgentConfig.defaultConfig(for: .agy, command: bin)
                    acpHost.registerAgent(cfg)
                    return cfg
                }()
            } else if appState.aiProvider == "claude_code" {
                targetConfig = acpHost.registeredConfigs.first(where: { $0.type == .claudeCode }) ?? {
                    let bin = LocalEcosystemDiscovery.shared.engines.first(where: { $0.id == "claude_code" })?.binaryPath ?? ACPAgentType.claudeCode.defaultCommand
                    let cfg = ACPAgentConfig.defaultConfig(for: .claudeCode, command: bin)
                    acpHost.registerAgent(cfg)
                    return cfg
                }()
            } else if appState.aiProvider == "opencode" {
                targetConfig = acpHost.registeredConfigs.first(where: { $0.type == .openCode }) ?? {
                    let bin = LocalEcosystemDiscovery.shared.engines.first(where: { $0.id == "opencode" })?.binaryPath ?? ACPAgentType.openCode.defaultCommand
                    let cfg = ACPAgentConfig.defaultConfig(for: .openCode, command: bin)
                    acpHost.registerAgent(cfg)
                    return cfg
                }()
            } else if appState.aiProvider == "codex" {
                targetConfig = acpHost.registeredConfigs.first(where: { $0.type == .codexEngine }) ?? {
                    let bin = LocalEcosystemDiscovery.shared.engines.first(where: { $0.id == "codex" })?.binaryPath ?? ACPAgentType.codexEngine.defaultCommand
                    let cfg = ACPAgentConfig.defaultConfig(for: .codexEngine, command: bin)
                    acpHost.registerAgent(cfg)
                    return cfg
                }()
            } else if appState.aiProvider == "zed" {
                targetConfig = acpHost.registeredConfigs.first(where: { $0.type == .zedEngine }) ?? {
                    let bin = LocalEcosystemDiscovery.shared.engines.first(where: { $0.id == "zed" })?.binaryPath ?? ACPAgentType.zedEngine.defaultCommand
                    let cfg = ACPAgentConfig.defaultConfig(for: .zedEngine, command: bin)
                    acpHost.registerAgent(cfg)
                    return cfg
                }()
            }
        }
        
        // Native ChatGPT Plus / Pro OAuth stream (~/.codex/auth.json -> chatgpt.com/backend-api/codex/responses)
        var useDirectCodexOAuth = false
        let chatgptSubToken = SubscriptionAuthManager.shared.getAccount(.chatgpt)?.sessionToken ?? ""
        let isSubscriptionChatGPT = (currentKeyMode == "subscription" && appState.aiProvider == "openai" && !chatgptSubToken.hasPrefix("sk-"))
        if isSubscriptionChatGPT, AIClient.loadCodexOAuthCredentials(fallbackToken: chatgptSubToken) != nil {
            useDirectCodexOAuth = true
        } else if targetConfig?.type == .codexEngine,
                  let cmd = targetConfig?.command,
                  !FileManager.default.isExecutableFile(atPath: cmd),
                  AIClient.loadCodexOAuthCredentials(fallbackToken: chatgptSubToken) != nil {
            targetConfig = nil
            useDirectCodexOAuth = true
        }
        
        if let activeConfig = targetConfig {
            let fullUserContent = userText + (currentAttachments.isEmpty ? "" : "\n[Attached: \(currentAttachments.map(\.name).joined(separator: ", "))]")
            _ = agent.prepareUserTurn(fullUserContent, createStreamingPlaceholder: false)
            
            let responseId = UUID().uuidString
            agent.messages.append(AgentMessageModel(
                id: responseId, role: .assistant, content: "",
                toolResults: [], pendingChanges: [], timestamp: Date()
            ))
            agent.isLoading = true
            agent.saveChats()
            
            let workspace = appState.workspaceFolder?.path ?? FileManager.default.currentDirectoryPath
            let session = acpHost.getOrCreateSession(for: activeConfig)
            let isBridgedSubscription = (currentKeyMode == "subscription" && acpHost.activeAgentId == nil && !["agy", "claude_code", "opencode", "codex", "zed"].contains(appState.aiProvider))
            let chosenModel: String? = {
                if isBridgedSubscription && !appState.aiModel.isEmpty {
                    return appState.aiModel
                }
                switch activeConfig.type {
                case .agy:
                    let agyModels = LocalEcosystemDiscovery.shared.models(for: "agy").map(\.id)
                    return agyModels.contains(appState.aiModel) ? appState.aiModel : (agyModels.first ?? "gemini-3.8-flash-low")
                case .openCode:
                    let isAuthed = LocalEcosystemDiscovery.shared.engines.first(where: { $0.id == "opencode" })?.isAuthenticated ?? false
                    let openCodeModels = LocalEcosystemDiscovery.shared.models(for: "opencode").map(\.id)
                    let current = appState.aiModel
                    if openCodeModels.contains(current) && !current.contains("nemotron-3.5-lightning-free") {
                        if !isAuthed && !current.contains("free") {
                            return openCodeModels.first(where: { $0.contains("free") && !$0.contains("nemotron-3.5-lightning-free") }) ?? "opencode/glm-5.3-flash-free"
                        }
                        return current
                    }
                    return openCodeModels.first(where: { $0.contains("free") && !$0.contains("nemotron-3.5-lightning-free") }) ?? "opencode/glm-5.3-flash-free"
                case .codexEngine:
                    let codexModels = LocalEcosystemDiscovery.shared.models(for: "codex").map(\.id)
                    return codexModels.contains(appState.aiModel) ? appState.aiModel : codexModels.first
                case .claudeCode:
                    let claudeModels = LocalEcosystemDiscovery.shared.models(for: "claude_code").map(\.id)
                    return claudeModels.contains(appState.aiModel) ? appState.aiModel : (claudeModels.first ?? "sonnet")
                case .zedEngine:
                    let zedModels = LocalEcosystemDiscovery.shared.models(for: "zed").map(\.id)
                    return zedModels.contains(appState.aiModel) ? appState.aiModel : (zedModels.first ?? "deepseek-chat")
                default:
                    return appState.aiModel.isEmpty ? nil : appState.aiModel
                }
            }()
            if !isBridgedSubscription, let model = chosenModel, appState.aiModel != model {
                appState.aiModel = model
            }
            
            Task { @MainActor in
                let stream = session.eventStream
                let mentionContext = await AgentContextProtocolBridge.shared.expandMentions(prompt: userText, workspaceRoot: workspace)
                session.start(task: mentionContext.expandedPrompt, workspacePath: workspace, model: chosenModel)
                
                var accumulatedThinking = ""
                var accumulatedText = ""
                
                agent.agentPhase = .thinking
                agent.currentToolExecution = "\(activeConfig.name) is reasoning..."
                
                for await event in stream {
                    guard let idx = agent.messages.firstIndex(where: { $0.id == responseId }) else { continue }
                    switch event {
                    case .text(let delta):
                        accumulatedText += delta
                        agent.agentPhase = .idle
                        agent.currentToolExecution = nil
                        
                        let formattedContent: String
                        if !accumulatedThinking.isEmpty {
                            formattedContent = "<thought>\(accumulatedThinking)</thought>\n\n\(accumulatedText)"
                        } else {
                            formattedContent = accumulatedText
                        }
                        agent.messages[idx] = AgentMessageModel(
                            id: responseId, role: .assistant,
                            content: formattedContent,
                            toolResults: agent.messages[idx].toolResults,
                            pendingChanges: agent.messages[idx].pendingChanges,
                            timestamp: Date()
                        )
                    case .thinking(let thought):
                        accumulatedThinking += thought
                        agent.agentPhase = .thinking
                        agent.currentToolExecution = "\(activeConfig.name) is reasoning..."
                        
                        let formattedContent: String
                        if !accumulatedText.isEmpty {
                            formattedContent = "<thought>\(accumulatedThinking)</thought>\n\n\(accumulatedText)"
                        } else {
                            // Unclosed tag renders as LIVE streaming thought block
                            formattedContent = "<thought>\(accumulatedThinking)"
                        }
                        agent.messages[idx] = AgentMessageModel(
                            id: responseId, role: .assistant,
                            content: formattedContent,
                            toolResults: agent.messages[idx].toolResults,
                            pendingChanges: agent.messages[idx].pendingChanges,
                            timestamp: Date()
                        )
                    case .toolCall(let call):
                        agent.agentPhase = .executing(call.name)
                        agent.currentToolExecution = "Executing \(call.name)..."
                        
                        var tools = agent.messages[idx].toolResults
                        let t = ToolResultModel(
                            toolCallId: call.id,
                            toolName: call.name,
                            toolParams: nil,
                            success: true,
                            output: call.displaySummary,
                            error: nil
                        )
                        tools.append(t)
                        agent.messages[idx] = AgentMessageModel(
                            id: responseId, role: .assistant,
                            content: agent.messages[idx].content,
                            toolResults: tools,
                            pendingChanges: agent.messages[idx].pendingChanges,
                            timestamp: Date()
                        )
                    case .toolResult(let res):
                        agent.agentPhase = .thinking
                        agent.currentToolExecution = "Analyzing output..."
                        
                        var tools = agent.messages[idx].toolResults
                        if let tIdx = tools.firstIndex(where: { $0.toolCallId == res.toolCallId }) {
                            tools[tIdx] = ToolResultModel(
                                toolCallId: res.toolCallId,
                                toolName: tools[tIdx].toolName,
                                toolParams: nil,
                                success: !res.isError,
                                output: res.content,
                                error: res.isError ? res.content : nil
                            )
                        } else {
                            tools.append(ToolResultModel(
                                toolCallId: res.toolCallId, toolName: res.toolName ?? "Tool",
                                success: !res.isError, output: res.content,
                                error: res.isError ? res.content : nil
                            ))
                        }
                        agent.messages[idx] = AgentMessageModel(
                            id: responseId, role: .assistant,
                            content: agent.messages[idx].content,
                            toolResults: tools,
                            pendingChanges: agent.messages[idx].pendingChanges,
                            timestamp: Date()
                        )
                    case .progress(let prog):
                        agent.agentPhase = .thinking
                        agent.currentToolExecution = prog.message
                    case .sessionInit:
                        agent.agentPhase = .thinking
                        agent.currentToolExecution = "Connecting to \(activeConfig.name)..."
                    case .complete(let res):
                        if accumulatedText.isEmpty && !res.result.isEmpty {
                            accumulatedText = res.result
                        }
                        if !accumulatedThinking.isEmpty && accumulatedText.isEmpty {
                            agent.messages[idx] = AgentMessageModel(
                                id: responseId, role: .assistant,
                                content: "<thought>\(accumulatedThinking)</thought>",
                                toolResults: agent.messages[idx].toolResults,
                                pendingChanges: agent.messages[idx].pendingChanges,
                                timestamp: Date()
                            )
                        } else if !accumulatedThinking.isEmpty && !accumulatedText.isEmpty {
                            agent.messages[idx] = AgentMessageModel(
                                id: responseId, role: .assistant,
                                content: "<thought>\(accumulatedThinking)</thought>\n\n\(accumulatedText)",
                                toolResults: agent.messages[idx].toolResults,
                                pendingChanges: agent.messages[idx].pendingChanges,
                                timestamp: Date()
                            )
                        } else if !accumulatedText.isEmpty {
                            agent.messages[idx] = AgentMessageModel(
                                id: responseId, role: .assistant,
                                content: accumulatedText,
                                toolResults: agent.messages[idx].toolResults,
                                pendingChanges: agent.messages[idx].pendingChanges,
                                timestamp: Date()
                            )
                        }
                        agent.isLoading = false
                        agent.agentPhase = .idle
                        agent.currentToolExecution = nil
                        agent.saveChats()
                        agent.saveArx()
                    case .error(let err):
                        let curr = agent.messages[idx].content
                        agent.messages[idx] = AgentMessageModel(
                            id: responseId, role: .assistant,
                            content: curr + "\n\n⚠️ \(activeConfig.name) Error: \(err)",
                            toolResults: agent.messages[idx].toolResults,
                            pendingChanges: agent.messages[idx].pendingChanges,
                            timestamp: Date()
                        )
                        agent.isLoading = false
                        agent.agentPhase = .idle
                        agent.currentToolExecution = nil
                        agent.saveChats()
                        agent.saveArx()
                    default:
                        break
                    }
                }
                if agent.isLoading {
                    agent.isLoading = false
                    agent.agentPhase = .idle
                    agent.currentToolExecution = nil
                    agent.saveChats()
                    agent.saveArx()
                }
                agent.processQueue()
            }
            return
        }
        
        let providerString = useDirectCodexOAuth ? "openai" : appState.aiProvider
        let model: String = {
            if useDirectCodexOAuth {
                let lower = appState.aiModel.lowercased()
                if !lower.isEmpty && (lower.hasPrefix("gpt") || lower.contains("codex")) {
                    return appState.aiModel
                }
                return AIClient.loadCodexOAuthCredentials(fallbackToken: "")?.defaultModel ?? "gpt-6-luna"
            }
            return appState.aiModel.isEmpty ? (AIModelCatalog.shared.provider(providerString)?.models.first?.id ?? "") : appState.aiModel
        }()
        let apiKey = useDirectCodexOAuth ? "codex_oauth" : appState.resolveApiKey(for: providerString)
        
        if appState.agentMode {
            // Agent Mode: Synchronously append the user message & set isLoading = true on @MainActor
            // before spawning the async tool loop so the UI updates in the exact same frame.
            agent.startOrEnqueueMessage(
                userText,
                provider: providerString,
                model: model,
                apiKey: apiKey,
                attachments: currentAttachments
            )
        } else {
            // Simple Chat Mode: Direct AIClient streaming
            let fullUserContent = userText + (currentAttachments.isEmpty ? "" : "\n[Attached: \(currentAttachments.map(\.name).joined(separator: ", "))]")
            _ = agent.prepareUserTurn(fullUserContent, createStreamingPlaceholder: false)
            
            let responseId = UUID().uuidString
            agent.messages.append(AgentMessageModel(
                id: responseId, role: .assistant, content: "",
                toolResults: [], pendingChanges: [], timestamp: Date()
            ))
            agent.isLoading = true
            agent.saveChats()
            
            let provider: StreamableAIProvider = StreamableAIProvider(rawValue: providerString) ?? .gemini
            let history: [(role: String, content: String)] = agent.messages.dropLast(2)
                .filter { $0.role == .user || $0.role == .assistant }
                .filter { !$0.content.isEmpty }
                .map { (role: $0.role.rawValue, content: $0.content) }

            let simpleChatPrompt: String
            if agent.domain == .science {
                simpleChatPrompt = "You are MicroCode Science Agent. Work only from the current scientific research session and its explicitly attached or indexed artifacts. Separate observations, inferences and hypotheses; state uncertainty; never invent measurements or citations; do not provide autonomous clinical diagnosis or treatment. Respond in the user's language."
            } else {
                simpleChatPrompt = "You are MicroCode AI — a professional software engineering assistant integrated into the MicroCode IDE. Maintain a professional, clear, and authoritative tone. Provide well-structured, accurate responses with precise technical terminology. When the user asks about code, act as a senior software engineer providing production-quality solutions with clear code blocks. When the user writes in Thai, respond in Thai. When in English, respond in English. Be thorough but concise."
            }
            
            let isDirectMediaModel = AIClient.isAiPassMediaModel(model)
            AIClient.shared.sendMessage(
                prompt: userText,
                attachments: currentAttachments,
                systemPrompt: isDirectMediaModel ? nil : simpleChatPrompt,
                conversationHistory: isDirectMediaModel ? [] : history,
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
                onComplete: { _ in
                    self.agent.isLoading = false
                    self.agent.saveChats()
                    self.agent.processQueue()
                },
                onError: { error in
                    if let idx = self.agent.messages.firstIndex(where: { $0.id == responseId }) {
                        self.agent.messages[idx] = AgentMessageModel(
                            id: responseId, role: .assistant, content: "Error: \(error)",
                            toolResults: [], pendingChanges: [], timestamp: Date()
                        )
                    }
                    self.agent.isLoading = false
                    self.agent.saveChats()
                    self.agent.processQueue()
                }
            )
        }
    }
    
    // MARK: - Apply / Reject Pending Changes
    
    private func applyChange(_ change: PendingChangeModel) {
        do {
            let url = URL(fileURLWithPath: change.filePath)
            
            // Ensure parent directory exists
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            if !change.newContent.isEmpty {
                try change.newContent.write(to: url, atomically: true, encoding: .utf8)
            }
            
            // Update status in agent messages
            updateChangeStatus(change, newStatus: .accepted)
            
            // Update status in AgentService pending changes
            agent.applyChange(change.id)
            
            // Immediate reload of the file from disk into open editor tabs
            appState.reloadFileFromDisk(path: change.filePath)
            
            // If file is not open, open it so user sees the change
            let standardizedPath = url.standardizedFileURL.path
            if !appState.openFiles.contains(where: { $0.path == standardizedPath }) {
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
        do {
            if !change.oldContent.isEmpty {
                let url = URL(fileURLWithPath: change.filePath)
                try change.oldContent.write(to: url, atomically: true, encoding: .utf8)
                appState.reloadFileFromDisk(path: change.filePath)
            }
            updateChangeStatus(change, newStatus: .rejected)
            agent.rejectChange(change.id)
            print("❌ Rejected change to \(change.filePath)")
        } catch {
            print("❌ Failed to revert change: \(error)")
        }
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
    
    // MARK: - Per-Message Actions (Revert, Edit & Resend, Retry, Delete)
    
    private func handleRevertToMessage(_ messageId: String) {
        acpHost.stopActiveAgent()
        if let restoredText = agent.revertToMessage(id: messageId, restoreFiles: true) {
            inputText = restoredText
            isInputFocused = true
        }
    }
    
    private func handleEditAndResendMessage(id messageId: String, newContent: String) {
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        acpHost.stopActiveAgent()
        _ = agent.revertToMessage(id: messageId, restoreFiles: true)
        inputText = trimmed
        sendMessage()
    }
    
    private func handleRetryAssistantMessage(_ assistantMessageId: String) {
        acpHost.stopActiveAgent()
        if let (userMsgId, promptText) = agent.precedingUserPrompt(forAssistantMessageId: assistantMessageId) {
            _ = agent.revertToMessage(id: userMsgId, restoreFiles: true)
            inputText = promptText
            sendMessage()
        } else {
            // Fallback if no preceding user message found: just remove this assistant message
            agent.deleteMessage(id: assistantMessageId, revertFiles: true)
        }
    }
    
    private func handleDeleteMessage(_ messageId: String, revertFiles: Bool = false) {
        agent.deleteMessage(id: messageId, revertFiles: revertFiles)
    }
    
    // MARK: - Engine & Agent Switching Helpers
    
    private func switchToConfig(_ config: ACPAgentConfig) {
        UserDefaults.standard.set("acp", forKey: "aiKeyMode")
        activeACPAgent = config
        acpHost.activeAgentId = config.id
        let engineId = config.type.engineId
        appState.aiProvider = engineId
        let engineModels = LocalEcosystemDiscovery.shared.models(for: engineId)
        if !engineModels.contains(where: { $0.id == appState.aiModel }) {
            if let firstModel = engineModels.first?.id {
                appState.aiModel = firstModel
            }
        }
        appState.saveSettings()
    }
    
    private func switchToEngine(_ engineId: String, modelId: String) {
        UserDefaults.standard.set("acp", forKey: "aiKeyMode")
        let type: ACPAgentType
        switch engineId {
        case "agy": type = .agy
        case "codex": type = .codexEngine
        case "claude_code": type = .claudeCode
        case "gemini_cli": type = .geminiCLI
        case "opencode": type = .openCode
        case "cursor": type = .cursorAgent
        case "copilot": type = .githubCopilot
        case "goose": type = .goose
        case "cline": type = .cline
        case "qwen": type = .qwenCode
        case "aider": type = .aider
        case "zed": type = .zedEngine
        default: type = .agy
        }
        
        let discoveredBinary = LocalEcosystemDiscovery.shared.engines.first(where: { $0.id == engineId })?.binaryPath
            ?? ACPHostService.resolveExecutablePath(type.defaultCommand)
            ?? type.defaultCommand
        let config: ACPAgentConfig
        if var existing = acpHost.registeredConfigs.first(where: { $0.type == type }) {
            if !FileManager.default.isExecutableFile(atPath: existing.command) {
                existing.command = discoveredBinary
                acpHost.registerAgent(existing)
            }
            config = existing
        } else {
            config = ACPAgentConfig.defaultConfig(for: type, command: discoveredBinary)
            acpHost.registerAgent(config)
        }
        
        activeACPAgent = config
        acpHost.activeAgentId = config.id
        appState.aiProvider = engineId
        appState.aiModel = modelId
        appState.saveSettings()
    }
    
    private func switchToNativeMode(mode: String) {
        acpHost.stopActiveAgent()
        agent.isLoading = false
        acpHost.activeAgentId = nil
        activeACPAgent = nil
        UserDefaults.standard.set(mode, forKey: "aiKeyMode")
        if mode == "subscription" {
            if let first = SubscriptionAuthManager.shared.connectedModelInfos().first {
                appState.aiProvider = first.aiProviderID
                appState.aiModel = first.modelID
                SubscriptionAuthManager.shared.activeProvider = first.provider
                UserDefaults.standard.set(first.provider.rawValue, forKey: "subscriptionActiveProvider")
            }
        } else if mode == "local" {
            appState.aiProvider = "local"
            if let firstM = LocalLLMService.shared.availableModels.first {
                appState.aiModel = firstM.id
            } else {
                appState.aiModel = "local-model"
            }
        } else if mode == "cloud" {
            if let first = AIModelCatalog.shared.provider("omni")?.models.first {
                appState.aiProvider = "omni"
                appState.aiModel = first.id
            }
        } else {
            // Direct (BYOK)
            let byok = AIModelCatalog.shared.providers.filter { !["omni", "agy", "codex", "claude_code", "zed", "local"].contains($0.id) && hasActiveKey($0.id) }
            if let firstProv = byok.first, let firstM = firstProv.models.first {
                appState.aiProvider = firstProv.id
                appState.aiModel = firstM.id
            } else {
                appState.aiProvider = "deepseek"
                appState.aiModel = "deepseek-chat"
            }
        }
        appState.saveSettings()
    }
    
    private func switchToNativeAgent() {
        switchToNativeMode(mode: UserDefaults.standard.string(forKey: "aiKeyMode") ?? "direct")
    }
    
    // MARK: - Model Selector
    
    private var headerModelDisplayName: String {
        return currentModelDisplayName
    }
    
    private var modelSelector: some View {
        Button(action: {
            if !appState.isCurrentAIConnected {
                showingAgentConnections = true
            } else {
                presentNativeModelMenu()
            }
        }) {
            HStack(spacing: 4) {
                if !appState.isCurrentAIConnected {
                    Image(systemName: "link")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Connect AI")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                } else {
                    AIProviderBrandIcon(provider: activeBrandIconKey, size: 12)
                    Text("\(currentExecutionMode.badgeTitle) · \(headerModelDisplayName)")
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 195)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Select Mode & AI Model (ACP, Dotmini Cloud, BYOK, Subscription)")
    }
    
    @ViewBuilder
    private func providerIcon(for provider: String) -> some View {
        AIProviderBrandIcon(provider: provider, size: 14)
    }
    
    private func hasActiveKey(_ provider: String) -> Bool {
        if provider == "local" {
            return LocalLLMService.shared.activeServer?.isOnline == true
        }
        if provider == "9router" {
            return LocalLLMService.shared.detectedServers.contains(where: { $0.type == .nineRouter && $0.isOnline })
                || ACPHostService.resolveExecutablePath("9router") != nil
                || !appState.resolveApiKey(for: "9router").isEmpty
        }
        return !appState.resolveApiKey(for: provider).isEmpty
    }
    
    // MARK: - On-Demand Native NSMenu Model Picker (Zero Idle AttributeGraph / PropertyList Overhead)
    
    private func makeActionMenuItem(
        _ title: String,
        brandKey: String? = nil,
        systemImage: String? = nil,
        checked: Bool = false,
        enabled: Bool = true,
        action: (() -> Void)? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action != nil ? #selector(ClosureMenuActionHandler.performMenuAction(_:)) : nil,
            keyEquivalent: ""
        )
        if let action {
            item.target = ClosureMenuActionHandler.shared
            item.representedObject = action
        }
        item.isEnabled = enabled
        item.state = checked ? .on : .off
        if let brandKey {
            item.image = AIProviderBrandIcon.menuImage(for: brandKey, size: 15)
        } else if let systemImage, let img = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) {
            item.image = img
        }
        return item
    }
    
    private func makeSubmenuItem(
        _ title: String,
        brandKey: String? = nil,
        systemImage: String? = nil,
        checked: Bool = false,
        submenu: NSMenu
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        item.state = checked ? .on : .off
        if let brandKey {
            item.image = AIProviderBrandIcon.menuImage(for: brandKey, size: 15)
        } else if let systemImage, let img = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) {
            item.image = img
        }
        return item
    }
    
    private func makeSubscriptionModelMenuItem(_ subModel: SubscriptionModelInfo) -> NSMenuItem {
        let title = subModel.badge.isEmpty ? subModel.name : "\(subModel.name) [\(subModel.badge)]"
        let isChecked = (currentExecutionMode == .subscription && appState.aiModel == subModel.modelID)
        return makeActionMenuItem(title, brandKey: subModel.provider.rawValue, checked: isChecked) {
            switchToNativeMode(mode: "subscription")
            appState.aiProvider = subModel.aiProviderID
            appState.aiModel = subModel.modelID
            SubscriptionAuthManager.shared.activeProvider = subModel.provider
            UserDefaults.standard.set(subModel.provider.rawValue, forKey: "subscriptionActiveProvider")
            UserDefaults.standard.set("subscription", forKey: "aiKeyMode")
            appState.saveSettings()
        }
    }
    
    private func presentNativeModelMenu() {
        let rootMenu = NSMenu(title: "Select AI Model")
        rootMenu.autoenablesItems = false
        
        // 1. Subscription (OAuth Accounts)
        let subMenu = NSMenu(title: "Subscription")
        subMenu.autoenablesItems = false
        let connected = SubscriptionAuthManager.shared.connectedProviders()
        let providersToShow = connected.isEmpty ? SubscriptionProviderType.allCases : connected
        for prov in providersToShow {
            let isConnected = SubscriptionAuthManager.shared.isConnected(prov)
            let provMenu = NSMenu(title: prov.displayName)
            provMenu.autoenablesItems = false
            if prov == .aipass {
                let groups = Self.groupedAiPassModels(from: prov.modelInfos)
                let chatSub = NSMenu(title: "Chat")
                groups.chat.forEach { chatSub.addItem(makeSubscriptionModelMenuItem($0)) }
                provMenu.addItem(makeSubmenuItem("Chat, Coding & Reasoning (\(groups.chat.count))", brandKey: "aipass", submenu: chatSub))
                
                let imgSub = NSMenu(title: "Image")
                groups.image.forEach { imgSub.addItem(makeSubscriptionModelMenuItem($0)) }
                provMenu.addItem(makeSubmenuItem("Image Generation (\(groups.image.count))", brandKey: "aipass", submenu: imgSub))
                
                let vidSub = NSMenu(title: "Video")
                groups.video.forEach { vidSub.addItem(makeSubscriptionModelMenuItem($0)) }
                provMenu.addItem(makeSubmenuItem("Video Generation (\(groups.video.count))", brandKey: "aipass", submenu: vidSub))
                
                let musSub = NSMenu(title: "Music")
                groups.music.forEach { musSub.addItem(makeSubscriptionModelMenuItem($0)) }
                provMenu.addItem(makeSubmenuItem("Audio & Music Generation (\(groups.music.count))", brandKey: "aipass", submenu: musSub))
            } else {
                for subModel in prov.modelInfos.prefix(32) {
                    provMenu.addItem(makeSubscriptionModelMenuItem(subModel))
                }
            }
            provMenu.addItem(.separator())
            provMenu.addItem(makeActionMenuItem("Enter Custom Model ID...") {
                promptCustomModel(provider: prov.rawValue, isSubscription: true)
            })
            if isConnected {
                provMenu.addItem(makeActionMenuItem("Fetch Live Models Now") {
                    Task { await SubscriptionAuthManager.shared.fetchLiveModels(for: prov) }
                })
            } else {
                provMenu.addItem(.separator())
                provMenu.addItem(makeActionMenuItem("Connect \(prov.displayName) in Settings...") {
                    appState.showingSettingsDialog = true
                })
            }
            subMenu.addItem(makeSubmenuItem("\(prov.displayName)\(isConnected ? " (Active)" : "")", brandKey: prov.rawValue, submenu: provMenu))
        }
        subMenu.addItem(.separator())
        subMenu.addItem(makeActionMenuItem("Manage Subscriptions in Settings...", systemImage: "gearshape") {
            appState.showingSettingsDialog = true
        })
        rootMenu.addItem(makeSubmenuItem(
            "Subscription (ChatGPT, Claude, Gemini)",
            brandKey: connected.first?.rawValue ?? "claude",
            checked: currentExecutionMode == .subscription,
            submenu: subMenu
        ))
        
        // 2. BYOK & Smart Routers (9Router, OpenRouter, Direct API Key)
        let byokMenu = NSMenu(title: "BYOK")
        byokMenu.autoenablesItems = false
        let acpSet: Set<String> = ["omni", "agy", "codex", "claude_code", "opencode", "zed", "gemini_cli", "cursor", "goose", "cline", "aider", "local"]
        let byokProviders = AIModelCatalog.shared.providers.filter { !acpSet.contains($0.id) }
        for prov in byokProviders {
            let hasKey = hasActiveKey(prov.id)
            let provMenu = NSMenu(title: prov.name)
            provMenu.autoenablesItems = false
            let displayedModels = Array(prov.models.prefix(24))
            for m in displayedModels {
                let label = m.badge.isEmpty ? m.name : "\(m.name) (\(m.badge))"
                let isChecked = (currentExecutionMode == .byok && appState.aiProvider == prov.id && appState.aiModel == m.id)
                provMenu.addItem(makeActionMenuItem(label, brandKey: prov.id, checked: isChecked) {
                    switchToNativeMode(mode: "direct")
                    setModel(prov.id, m.id)
                })
            }
            if prov.models.count > displayedModels.count {
                provMenu.addItem(makeActionMenuItem("Browse All \(prov.models.count) Models in Settings...") {
                    appState.showingSettingsDialog = true
                })
            }
            provMenu.addItem(.separator())
            provMenu.addItem(makeActionMenuItem("Enter Custom Model ID...") {
                promptCustomModel(provider: prov.id, isSubscription: false)
            })
            if hasKey || prov.id == "9router" {
                provMenu.addItem(makeActionMenuItem("Fetch Live Models Now") {
                    Task { await AIModelCatalog.shared.fetchLiveModelsForProvider(prov.id) }
                })
            } else {
                provMenu.addItem(.separator())
                provMenu.addItem(makeActionMenuItem("Set \(prov.name) API Key in Settings...") {
                    appState.showingSettingsDialog = true
                })
            }
            let statusSuffix = prov.id == "9router" ? (hasKey ? " (Ready)" : " (localhost:20128)") : (hasKey ? "" : " (No Key)")
            byokMenu.addItem(makeSubmenuItem("\(prov.name)\(statusSuffix)", brandKey: prov.id, submenu: provMenu))
        }
        byokMenu.addItem(.separator())
        byokMenu.addItem(makeActionMenuItem("Fetch All Provider Models", systemImage: "arrow.clockwise") {
            Task { await AIModelCatalog.shared.refreshLiveProviderModels() }
        })
        rootMenu.addItem(makeSubmenuItem(
            "BYOK & Smart Routers (9Router, OpenRouter, Direct API)",
            brandKey: currentExecutionMode == .byok ? appState.aiProvider : "9router",
            checked: currentExecutionMode == .byok,
            submenu: byokMenu
        ))
        
        // 3. Local LLM (9Router, LiteLLM, Ollama, LM Studio, MLX)
        let localMenu = NSMenu(title: "Local LLM")
        localMenu.autoenablesItems = false
        let onlineServers = LocalLLMService.shared.detectedServers.filter { $0.isOnline }
        if onlineServers.isEmpty {
            localMenu.addItem(makeActionMenuItem("No Running Local LLM Server Found", enabled: false))
            localMenu.addItem(.separator())
            localMenu.addItem(makeActionMenuItem("Scan for Local Engines (9Router, Ollama, LM Studio)", systemImage: "arrow.clockwise") {
                Task {
                    await LocalLLMService.shared.scanForServers()
                    AIModelCatalog.shared.integrateLocalModels()
                }
            })
            localMenu.addItem(makeActionMenuItem("Configure Local LLM in Settings...", systemImage: "gearshape") {
                appState.showingSettingsDialog = true
            })
        } else {
            for srv in onlineServers {
                let srvMenu = NSMenu(title: srv.displayName)
                srvMenu.autoenablesItems = false
                if srv.models.isEmpty {
                    srvMenu.addItem(makeActionMenuItem("No models loaded on this server", enabled: false))
                } else {
                    for m in srv.models {
                        let title = (m.size?.isEmpty == false) ? "\(m.displayName) • \(m.size!)" : m.displayName
                        let isChecked = (currentExecutionMode == .local && appState.aiModel == m.id)
                        srvMenu.addItem(makeActionMenuItem(title, brandKey: srv.type.brandKey, checked: isChecked) {
                            switchToNativeMode(mode: "local")
                            appState.aiProvider = "local"
                            appState.aiModel = m.id
                            LocalLLMService.shared.selectedModelId = m.id
                            LocalLLMService.cachedEndpoint = srv.endpoint
                            LocalLLMService.cachedModel = m.id
                            appState.saveSettings()
                        })
                    }
                }
                localMenu.addItem(makeSubmenuItem("\(srv.displayName) (\(srv.models.count) models)", brandKey: srv.type.brandKey, submenu: srvMenu))
            }
            localMenu.addItem(.separator())
            localMenu.addItem(makeActionMenuItem("Rescan Local Engines", systemImage: "arrow.clockwise") {
                Task {
                    await LocalLLMService.shared.scanForServers()
                    AIModelCatalog.shared.integrateLocalModels()
                }
            })
            localMenu.addItem(makeActionMenuItem("Local LLM Settings...", systemImage: "gearshape") {
                appState.showingSettingsDialog = true
            })
        }
        rootMenu.addItem(makeSubmenuItem(
            "Local LLM (Ollama, LM Studio, MLX)",
            brandKey: "local",
            checked: currentExecutionMode == .local,
            submenu: localMenu
        ))
        
        // 4. ACP (Major CLI Harnesses)
        let acpMenu = NSMenu(title: "ACP")
        acpMenu.autoenablesItems = false
        for engine in LocalEcosystemDiscovery.shared.engines {
            let engMenu = NSMenu(title: engine.name)
            engMenu.autoenablesItems = false
            if engine.models.isEmpty {
                engMenu.addItem(makeActionMenuItem("Connect \(engine.name) in Agent Connections...", brandKey: engine.id) {
                    showingAgentConnections = true
                })
            } else {
                for m in engine.models {
                    let title = m.badge.isEmpty ? m.name : "\(m.name) (\(m.badge))"
                    let isChecked = (currentExecutionMode == .acp && appState.aiProvider == engine.id && appState.aiModel == m.id)
                    engMenu.addItem(makeActionMenuItem(title, brandKey: engine.id, checked: isChecked) {
                        switchToEngine(engine.id, modelId: m.id)
                    })
                }
            }
            acpMenu.addItem(makeSubmenuItem(engine.name + (engine.isInstalled ? "" : " (Not Installed)"), brandKey: engine.id, submenu: engMenu))
        }
        rootMenu.addItem(makeSubmenuItem(
            "ACP Harnesses (Claude Code, AGY, Codex, Gemini CLI, Goose, Cursor...)",
            brandKey: currentExecutionMode == .acp ? activeBrandIconKey : "agy",
            checked: currentExecutionMode == .acp,
            submenu: acpMenu
        ))
        
        // 5. Dotmini Cloud (Sovereign AI)
        let cloudMenu = NSMenu(title: "Dotmini Cloud")
        cloudMenu.autoenablesItems = false
        if let omni = AIModelCatalog.shared.provider("omni") {
            let groups = Self.groupedOmniModels(from: omni.models)
            let sections: [(String, String, [AIModelDefinition])] = [
                ("Flagship & Deep Reasoning", "microcode", groups.reasoning),
                ("Google Gemini", "gemini", groups.gemini),
                ("Anthropic Claude", "claude", groups.claude),
                ("OpenAI", "openai", groups.openAI),
                ("DeepSeek", "deepseek", groups.deepseek),
                ("Thai AI & Open Source", "typhoon", groups.openSource)
            ]
            for (title, secBrand, list) in sections where !list.isEmpty {
                let secMenu = NSMenu(title: title)
                secMenu.autoenablesItems = false
                for m in list {
                    let isChecked = (currentExecutionMode == .cloud && appState.aiModel == m.id)
                    secMenu.addItem(makeActionMenuItem(m.name, brandKey: secBrand, checked: isChecked) {
                        switchToNativeMode(mode: "cloud")
                        setModel("omni", m.id)
                    })
                }
                cloudMenu.addItem(makeSubmenuItem(title, brandKey: secBrand, submenu: secMenu))
            }
        }
        rootMenu.addItem(makeSubmenuItem(
            "Dotmini Cloud (Sovereign AI)",
            brandKey: "microcode",
            checked: currentExecutionMode == .cloud,
            submenu: cloudMenu
        ))
        
        rootMenu.addItem(.separator())
        rootMenu.addItem(makeActionMenuItem("Manage Agent Connections & Setup…", systemImage: "slider.horizontal.2.square") {
            showingAgentConnections = true
        })
        rootMenu.addItem(makeActionMenuItem("Rescan Local Engines & Cloud APIs", systemImage: "arrow.triangle.2.circlepath") {
            Task {
                await AIModelCatalog.shared.refreshLiveProviderModels()
                await LocalEcosystemDiscovery.shared.refresh()
            }
        })
        rootMenu.addItem(makeActionMenuItem("AI Settings...", systemImage: "gearshape") {
            appState.showingSettingsDialog = true
        })
        
        rootMenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    private func setModel(_ provider: String, _ model: String) {
        appState.aiProvider = provider
        appState.aiModel = model
        if provider == "omni" {
            UserDefaults.standard.set("cloud", forKey: "aiKeyMode")
        } else if provider != "local" {
            UserDefaults.standard.set("direct", forKey: "aiKeyMode")
        }
        appState.saveSettings()
    }
    
    private func promptCustomModel(provider: String, isSubscription: Bool) {
        let alert = NSAlert()
        alert.messageText = "Enter Custom Model ID"
        alert.informativeText = "Type the exact model identifier from \(provider) (e.g. gemini-4-argon-medium, claude-opus-5-5-high, gpt-6.1-sol, deepseek-v4-pro):"
        alert.addButton(withTitle: "Use Model")
        alert.addButton(withTitle: "Cancel")
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        inputTextField.placeholderString = "e.g. model-identifier"
        alert.accessoryView = inputTextField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let modelId = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modelId.isEmpty else { return }
            
            if isSubscription {
                if let subType = SubscriptionProviderType(rawValue: provider) {
                    SubscriptionAuthManager.registerCustomSubscriptionModel(provider: subType, modelId: modelId)
                    switchToNativeMode(mode: "subscription")
                    appState.aiProvider = subType.aiProviderID
                    appState.aiModel = modelId
                    SubscriptionAuthManager.shared.activeProvider = subType
                    UserDefaults.standard.set(subType.rawValue, forKey: "subscriptionActiveProvider")
                    UserDefaults.standard.set("subscription", forKey: "aiKeyMode")
                    appState.saveSettings()
                }
            } else {
                AIModelCatalog.shared.registerCustomModel(provider: provider, modelId: modelId)
                switchToNativeMode(mode: "direct")
                setModel(provider, modelId)
            }
        }
    }
    
    private struct OmniModelGroups {
        let count: Int
        let reasoning: [AIModelDefinition]
        let gemini: [AIModelDefinition]
        let claude: [AIModelDefinition]
        let openAI: [AIModelDefinition]
        let deepseek: [AIModelDefinition]
        let openSource: [AIModelDefinition]
    }
    private static var cachedOmniGroups: OmniModelGroups?

    private static func groupedOmniModels(from models: [AIModelDefinition]) -> OmniModelGroups {
        if let cached = cachedOmniGroups, cached.count == models.count {
            return cached
        }
        let reasoning = models.filter {
            let id = $0.id.lowercased()
            return id.contains("argon") || id.contains("astra") || id.contains("opus") || id.contains("sonnet") || id.contains("3.8-flash") || id.contains("reasoner") || id.contains("o3") || id.contains("o1") || id.contains("sol")
        }
        let reasoningIds = Set(reasoning.map(\.id))
        let gemini = models.filter { $0.id.lowercased().contains("gemini") && !reasoningIds.contains($0.id) }
        let claude = models.filter { $0.id.lowercased().contains("claude") && !reasoningIds.contains($0.id) }
        let openAI = models.filter { ($0.id.lowercased().contains("gpt") || $0.id.lowercased().contains("o3") || $0.id.lowercased().contains("o1")) && !reasoningIds.contains($0.id) }
        let deepseek = models.filter { $0.id.lowercased().contains("deepseek") && !reasoningIds.contains($0.id) }
        let openSource = models.filter {
            let id = $0.id.lowercased()
            return id.contains("typhoon") || id.contains("qwen") || id.contains("llama") || id.contains("codegeex") || id.contains("glm")
        }
        let built = OmniModelGroups(
            count: models.count,
            reasoning: reasoning,
            gemini: gemini,
            claude: claude,
            openAI: openAI,
            deepseek: deepseek,
            openSource: openSource
        )
        cachedOmniGroups = built
        return built
    }

    private struct AiPassModelGroups {
        let count: Int
        let chat: [SubscriptionModelInfo]
        let image: [SubscriptionModelInfo]
        let video: [SubscriptionModelInfo]
        let music: [SubscriptionModelInfo]
    }
    private static var cachedAiPassGroups: AiPassModelGroups?

    private static func groupedAiPassModels(from allModels: [SubscriptionModelInfo]) -> AiPassModelGroups {
        if let cached = cachedAiPassGroups, cached.count == allModels.count {
            return cached
        }
        let imageModels = allModels.filter { $0.badge == "IMAGE" || AIClient.isAiPassImageModel($0.modelID) }
        let videoModels = allModels.filter { $0.badge == "VIDEO" || AIClient.isAiPassVideoModel($0.modelID) }
        let musicModels = allModels.filter { $0.badge == "MUSIC" || AIClient.isAiPassMusicModel($0.modelID) }
        let chatModels = allModels.filter { !AIClient.isAiPassMediaModel($0.modelID) && $0.badge != "IMAGE" && $0.badge != "VIDEO" && $0.badge != "MUSIC" }
        let built = AiPassModelGroups(
            count: allModels.count,
            chat: chatModels,
            image: imageModels,
            video: videoModels,
            music: musicModels
        )
        cachedAiPassGroups = built
        return built
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
            
            let stats = tokenOptimizer.stats
            Text("Active: \(stats.activeProvider)/\(stats.activeModel)")
            Text("Input: \(formatTokenCount(stats.inputTokens))")
            Text("Output: \(formatTokenCount(stats.outputTokens))")
            Text("Saved: \(formatTokenCount(stats.savedTokens))")
            
            Divider()
            
            Text("Requests: \(stats.totalRequests)")
            Text("Estimated cost: $\(String(format: "%.4f", stats.totalCost))")
            Text("Compression: \(String(format: "%.0f%%", stats.compressionRatio * 100))")
            Text("Context cache: \(stats.cacheHits) hit / \(stats.cacheMisses) miss")
            Text("Cached: \(formatTokenCount(stats.cachedTokens)) tokens")
            
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
                
                let stats = tokenOptimizer.stats
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
                        if cells.isEmpty {
                            // Empty state
                            VStack(spacing: 12) {
                                Image(systemName: "rectangle.grid.1x2")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary.opacity(0.3))
                                Text("No cells yet")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("Add a Code, Markdown, or AI cell below")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
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
        let provider: StreamableAIProvider = StreamableAIProvider(rawValue: providerString) ?? .gemini
        let model = appState.aiModel.isEmpty ? provider.defaultModel : appState.aiModel
        let apiKey = appState.resolveApiKey(for: providerString)
        
        // Guard: no API key configured
        guard !apiKey.isEmpty || providerString == "local" else {
            if let i = cells.firstIndex(where: { $0.id == cell.id }) {
                cells[i].output = "⚠️ No API key configured for \(providerString). Go to Settings → API Keys."
                cells[i].isRunning = false
            }
            return
        }
        
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
        // Guard: never crash on invalid index
        guard let idx = cells.firstIndex(where: { $0.id == id }) else { return }
        cells.remove(at: idx)
        // Clear focus if deleted cell was focused
        if focusedCellId == id {
            focusedCellId = cells.first?.id
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

enum GeneratedMediaKind: String, Equatable {
    case image
    case video
    case audio
}

enum MessageBlock: Identifiable {
    case thought(String, Int?) // Content, duration in seconds
    case text(String)
    case code(String, String) // Language, Content
    case heading(Int, String) // Level (1-6), Content
    case list([String], Bool) // Items, isOrdered
    case table([String], [[String]]) // Headers, Rows
    case blockquote(String)
    case latex(String, Bool) // Expression, isBlock ($$...$$ vs $...$)
    case html(String)
    case media(GeneratedMediaKind, String, String) // Kind, Title/Alt, URL or Path
    
    var id: String {
        switch self {
        case .thought(let c, let d):
            if d == nil { return "thought-streaming" }
            return "thought-\(c.hashValue)"
        case .text(let c): return "text-\(c.hashValue)"
        case .code(let l, let c): return "code-\(l)-\(c.hashValue)"
        case .heading(let lv, let c): return "h\(lv)-\(c.hashValue)"
        case .list(let items, _): return "list-\(items.hashValue)"
        case .table(let h, let r): return "table-\(h.joined())-\(r.count)"
        case .blockquote(let c): return "quote-\(c.hashValue)"
        case .latex(let e, _): return "latex-\(e.hashValue)"
        case .html(let c): return "html-\(c.hashValue)"
        case .media(let k, let t, let u): return "media-\(k.rawValue)-\(t.hashValue)-\(u.hashValue)"
        }
    }
}

struct MessageContentParser {
    private static var parseCache: [String: [MessageBlock]] = [:]
    private static var parseOrder: [String] = []
    private static let lock = NSLock()
    // Large tool payloads are already retained by the transcript store. Keeping a
    // second copy as a String dictionary key causes avoidable memory growth and
    // makes scrolling a long conversation progressively more expensive.
    private static let maximumCachedContentCharacters = 24_000
    
    // Pre-compiled static regexes to eliminate repeated allocations and compilation on every streamed token
    private static let thoughtRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<thought>([\\s\\S]*?)</thought>|<thinking>([\\s\\S]*?)</thinking>|<think>([\\s\\S]*?)</think>",
        options: [.caseInsensitive]
    )
    private static let latexRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "\\$\\$([\\s\\S]*?)\\$\\$|\\\\\\[([\\s\\S]*?)\\\\\\]",
        options: []
    )
    private static let codeRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "```([a-zA-Z0-9\\+\\-\\_\\#]*)[ \\t]*\\r?\\n([\\s\\S]*?)```",
        options: []
    )
    private static let orderedListRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^\\d+\\.\\s+",
        options: []
    )
    
    static func parse(_ content: String) -> [MessageBlock] {
        let shouldCache = content.count <= maximumCachedContentCharacters
        guard shouldCache else {
            return doParse(content)
        }

        lock.lock()
        if let cached = parseCache[content] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        let blocks = doParse(content)
        
        lock.lock()
        if parseCache.count > 500 {
            if let first = parseOrder.first {
                parseCache.removeValue(forKey: first)
                parseOrder.removeFirst()
            }
        }
        parseCache[content] = blocks
        parseOrder.append(content)
        lock.unlock()
        
        return blocks
    }
    
    private static func findUnclosedThought(in text: String) -> (before: String, thought: String)? {
        let tags: [(open: String, close: String)] = [
            ("<thought>", "</thought>"),
            ("<thinking>", "</thinking>"),
            ("<think>", "</think>")
        ]
        
        for (openTag, closeTag) in tags {
            if let openRange = text.range(of: openTag, options: .caseInsensitive) {
                let afterTag = text[openRange.upperBound...]
                if afterTag.range(of: closeTag, options: .caseInsensitive) != nil {
                    return nil // Full match handled by regex
                }
                let before = String(text[..<openRange.lowerBound])
                let thought = String(afterTag).trimmingCharacters(in: .whitespacesAndNewlines)
                return (before: before, thought: thought)
            }
        }
        return nil
    }
    
    private static func findOrphanClosingThought(in text: String) -> (thought: String, after: String)? {
        let closingTags = ["</thought>", "</thinking>", "</think>"]
        for closeTag in closingTags {
            if let closeRange = text.range(of: closeTag, options: .caseInsensitive) {
                let beforeTag = text[..<closeRange.lowerBound]
                let openTags = ["<thought>", "<thinking>", "<think>"]
                let hasOpen = openTags.contains(where: { beforeTag.range(of: $0, options: .caseInsensitive) != nil })
                if !hasOpen {
                    let thought = String(beforeTag).trimmingCharacters(in: .whitespacesAndNewlines)
                    let after = String(text[closeRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (thought: thought, after: after)
                }
            }
        }
        return nil
    }
    
    private static var thoughtStartTimes: [String: Date] = [:]
    private static var completedThoughtDurations: [Int: Int] = [:]
    private static var activeUnclosedStartTime: Date?
    private static let durationLock = NSLock()

    private static func recordStreamingThought(_ rawThought: String) {
        durationLock.lock()
        defer { durationLock.unlock() }
        let now = Date()
        if activeUnclosedStartTime == nil {
            activeUnclosedStartTime = now
        }
        let clean = rawThought.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count >= 40 {
            let key = String(clean.prefix(40))
            if thoughtStartTimes[key] == nil {
                thoughtStartTimes[key] = activeUnclosedStartTime ?? now
            }
        }
    }

    private static func resolveThoughtDuration(for clean: String) -> Int {
        durationLock.lock()
        defer { durationLock.unlock() }
        let hash = clean.hashValue
        if let cached = completedThoughtDurations[hash] {
            return cached
        }
        let key = String(clean.prefix(40))
        if let start = thoughtStartTimes[key] ?? activeUnclosedStartTime {
            let elapsed = max(1, Int(Date().timeIntervalSince(start).rounded()))
            completedThoughtDurations[hash] = elapsed
            activeUnclosedStartTime = nil
            return elapsed
        }
        // Fallback for historical persisted messages loaded from disk (~850 chars/sec for modern reasoning models)
        let fallback = max(1, min(120, clean.count / 850))
        completedThoughtDurations[hash] = fallback
        return fallback
    }

    private static func doParse(_ content: String) -> [MessageBlock] {
        let remaining = AIStructuredTurnCodec.stripToolCallArtifacts(content)
        let hasClosingThoughtTag =
            remaining.range(of: "</think", options: .caseInsensitive) != nil ||
            remaining.range(of: "</thought", options: .caseInsensitive) != nil
        
        // 0. Extract <thought>...</thought>, <thinking>...</thinking>, or <think>...</think>
        if hasClosingThoughtTag, let thoughtRegex = thoughtRegex {
            let nsContent = remaining as NSString
            let thoughtMatches = thoughtRegex.matches(in: remaining, options: [], range: NSRange(location: 0, length: nsContent.length))
            
            if !thoughtMatches.isEmpty {
                var lastEnd = 0
                var parsedList: [MessageBlock] = []
                
                for match in thoughtMatches {
                    if match.range.location > lastEnd {
                        let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                        let beforeText = nsContent.substring(with: beforeRange)
                        if !beforeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            parsedList.append(contentsOf: parseLatexAndCode(beforeText))
                        }
                    }
                    
                    var thoughtBody = ""
                    if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                        thoughtBody = nsContent.substring(with: match.range(at: 1))
                    } else if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                        thoughtBody = nsContent.substring(with: match.range(at: 2))
                    } else if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound {
                        thoughtBody = nsContent.substring(with: match.range(at: 3))
                    }
                    
                    let clean = thoughtBody.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty {
                        let durationSec = resolveThoughtDuration(for: clean)
                        parsedList.append(.thought(clean, durationSec))
                    }
                    
                    lastEnd = match.range.location + match.range.length
                }
                
                if lastEnd < nsContent.length {
                    let afterText = nsContent.substring(from: lastEnd)
                    if let unclosed = findUnclosedThought(in: afterText) {
                        if !unclosed.before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            parsedList.append(contentsOf: parseLatexAndCode(unclosed.before))
                        }
                        recordStreamingThought(unclosed.thought)
                        parsedList.append(.thought(unclosed.thought, nil))
                    } else if let orphan = findOrphanClosingThought(in: afterText) {
                        if !orphan.thought.isEmpty {
                            parsedList.append(.thought(orphan.thought, resolveThoughtDuration(for: orphan.thought)))
                        }
                        if !orphan.after.isEmpty {
                            parsedList.append(contentsOf: parseLatexAndCode(orphan.after))
                        }
                    } else if !afterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        parsedList.append(contentsOf: parseLatexAndCode(afterText))
                    }
                }
                
                return parsedList
            }
        }
        
        // Check for orphan closing tag without opening tag (e.g. "Let me start.</thought>")
        if hasClosingThoughtTag, let orphan = findOrphanClosingThought(in: remaining) {
            var parsedList: [MessageBlock] = []
            if !orphan.thought.isEmpty {
                parsedList.append(.thought(orphan.thought, resolveThoughtDuration(for: orphan.thought)))
            }
            if !orphan.after.isEmpty {
                parsedList.append(contentsOf: parseLatexAndCode(orphan.after))
            }
            return parsedList
        }
        
        // Check for streaming / unclosed thought without closing tag
        if let unclosed = findUnclosedThought(in: remaining) {
            var parsedList: [MessageBlock] = []
            if !unclosed.before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parsedList.append(contentsOf: parseLatexAndCode(unclosed.before))
            }
            recordStreamingThought(unclosed.thought)
            parsedList.append(.thought(unclosed.thought, nil))
            return parsedList
        }
        
        return parseLatexAndCode(remaining)
    }
    
    private static func parseLatexAndCode(_ content: String) -> [MessageBlock] {
        var remaining = content
        
        // Sanitize any stray/residual reasoning tags to prevent leaking raw XML into prose
        let strayTags = ["</thought>", "</thinking>", "</think>", "<thought>", "<thinking>", "<think>"]
        for tag in strayTags {
            remaining = remaining.replacingOccurrences(of: tag, with: "")
        }
        
        // Extract fenced code blocks FIRST so `$$` or `\[...\]` inside code blocks are never misparsed as LaTeX
        return parseCodeBlocks(remaining)
    }
    
    private static func parseMathAndTextContent(_ text: String) -> [MessageBlock] {
        if let latexRegex = latexRegex {
            let nsContent = text as NSString
            let latexMatches = latexRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsContent.length))
            if !latexMatches.isEmpty {
                var blocks: [MessageBlock] = []
                var lastEnd = 0
                for match in latexMatches {
                    if match.range.location > lastEnd {
                        let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                        let beforeText = nsContent.substring(with: beforeRange)
                        blocks.append(contentsOf: parseTextContent(beforeText))
                    }
                    var latexContent = ""
                    if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                        latexContent = nsContent.substring(with: match.range(at: 1))
                    } else if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                        latexContent = nsContent.substring(with: match.range(at: 2))
                    }
                    blocks.append(.latex(latexContent.trimmingCharacters(in: .whitespacesAndNewlines), true))
                    lastEnd = match.range.location + match.range.length
                }
                if lastEnd < nsContent.length {
                    let afterText = nsContent.substring(from: lastEnd)
                    blocks.append(contentsOf: parseTextContent(afterText))
                }
                return blocks
            }
        }
        return parseTextContent(text)
    }
    
    private static func parseCodeBlocks(_ content: String) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        
        // Extract code blocks, converting latex/math to LaTeX blocks
        if let regex = codeRegex {
            let nsContent = content as NSString
            let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))
            
            var lastEnd = 0
            for match in matches {
                // Text before code block
                if match.range.location > lastEnd {
                    let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                    let beforeText = nsContent.substring(with: beforeRange)
                    blocks.append(contentsOf: parseMathAndTextContent(beforeText))
                }
                
                // Code block
                let langRange = match.range(at: 1)
                let codeRange = match.range(at: 2)
                let lang = langRange.location != NSNotFound ? nsContent.substring(with: langRange) : ""
                let code = codeRange.location != NSNotFound ? nsContent.substring(with: codeRange) : ""
                let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Check if this is a LaTeX/math code block - render as LaTeX
                let lowerLang = lang.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if lowerLang == "latex" || lowerLang == "math" || lowerLang == "tex" {
                    blocks.append(.latex(trimmedCode, true))
                } else if lowerLang == "markdown" || lowerLang == "md" || lowerLang.hasSuffix(".md") {
                    blocks.append(contentsOf: parseMathAndTextContent(trimmedCode))
                } else {
                    blocks.append(.code(lang, trimmedCode))
                }
                
                lastEnd = match.range.location + match.range.length
            }
            
            // Remaining text after last code block
            if lastEnd < nsContent.length {
                let afterText = nsContent.substring(from: lastEnd)
                blocks.append(contentsOf: parseMathAndTextContent(afterText))
            }
        } else {
            // Fallback: simple split
            blocks.append(contentsOf: parseMathAndTextContent(content))
        }
        
        return blocks
    }
    
    private static func parseTextContent(_ text: String) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        let lines = text.components(separatedBy: "\n")
        var currentText: [String] = []
        var listItems: [String] = []
        var isOrderedList = false
        var lineIndex = 0
        
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check for Markdown Table (| col1 | col2 |)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.contains("|") && lineIndex + 1 < lines.count {
                let nextLine = lines[lineIndex + 1].trimmingCharacters(in: .whitespaces)
                if nextLine.hasPrefix("|") && (nextLine.contains("---") || nextLine.contains("-|-") || nextLine.contains(":--") || nextLine.contains("--:")) {
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
                    
                    // Parse headers from current line
                    let headers = trimmed.split(separator: "|", omittingEmptySubsequences: true).map { String($0).trimmingCharacters(in: .whitespaces) }
                    
                    var tableRows: [[String]] = []
                    lineIndex += 2 // Skip header line and separator line
                    
                    while lineIndex < lines.count {
                        let rowLine = lines[lineIndex].trimmingCharacters(in: .whitespaces)
                        if rowLine.hasPrefix("|") && rowLine.hasSuffix("|") {
                            let cells = rowLine.split(separator: "|", omittingEmptySubsequences: true).map { String($0).trimmingCharacters(in: .whitespaces) }
                            if !cells.isEmpty {
                                tableRows.append(cells)
                            }
                            lineIndex += 1
                        } else {
                            break
                        }
                    }
                    
                    if !headers.isEmpty {
                        blocks.append(.table(headers, tableRows))
                    }
                    continue
                }
            }
            
            // Check for headings (# H1, ## H2, etc.)
            if let match = trimmed.range(of: "^#{1,6}\\s+", options: .regularExpression) {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.joined(separator: "\n")))
                    currentText = []
                }
                if !listItems.isEmpty {
                    blocks.append(.list(listItems, isOrderedList))
                    listItems = []
                }
                
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let heading = String(trimmed[match.upperBound...])
                blocks.append(.heading(level, heading))
                lineIndex += 1
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
                lineIndex += 1
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
                lineIndex += 1
                continue
            }
            
            // Check for horizontal divider line (--- or ***)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.joined(separator: "\n")))
                    currentText = []
                }
                if !listItems.isEmpty {
                    blocks.append(.list(listItems, isOrderedList))
                    listItems = []
                }
                blocks.append(.html("<hr/>"))
                lineIndex += 1
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
                lineIndex += 1
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
                lineIndex += 1
                continue
            }
            
            // Flush list if we hit non-list line
            if !listItems.isEmpty && !trimmed.isEmpty {
                blocks.append(.list(listItems, isOrderedList))
                listItems = []
            }
            
            // Skip legacy emoji wrapper lines around media cards
            if trimmed.hasPrefix("🖼️ **Generated") ||
               trimmed.hasPrefix("🎬 **Generated") ||
               trimmed.hasPrefix("🎵 **Generated") ||
               trimmed.hasPrefix("📁 Saved to:") {
                lineIndex += 1
                continue
            }
            
            // Check for Markdown Media ![alt](url_or_path)
            if let mediaMatch = extractMarkdownMedia(from: trimmed) {
                if !currentText.isEmpty {
                    let joined = currentText.joined(separator: "\n")
                    if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        blocks.append(.text(joined))
                    }
                    currentText = []
                }
                blocks.append(.media(mediaMatch.kind, mediaMatch.alt, mediaMatch.target))
                lineIndex += 1
                continue
            }
            
            // Regular text
            currentText.append(line)
            lineIndex += 1
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
    
    private static func extractMarkdownMedia(from line: String) -> (kind: GeneratedMediaKind, alt: String, target: String)? {
        guard let bangIdx = line.range(of: "![") else { return nil }
        let afterBang = line[bangIdx.upperBound...]
        guard let closeBracket = afterBang.range(of: "](") else { return nil }
        let alt = String(afterBang[..<closeBracket.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let afterParen = afterBang[closeBracket.upperBound...]
        guard let closeParen = afterParen.lastIndex(of: ")") else { return nil }
        let rawTarget = String(afterParen[..<closeParen]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTarget.isEmpty else { return nil }
        
        let lowerTarget = rawTarget.lowercased()
        let lowerAlt = alt.lowercased()
        let kind: GeneratedMediaKind
        if lowerTarget.hasSuffix(".mp4") || lowerTarget.hasSuffix(".mov") || lowerTarget.hasSuffix(".webm") || lowerTarget.hasSuffix(".m4v") || lowerTarget.contains("video/") || lowerAlt.contains("video") {
            kind = .video
        } else if lowerTarget.hasSuffix(".mp3") || lowerTarget.hasSuffix(".wav") || lowerTarget.hasSuffix(".m4a") || lowerTarget.hasSuffix(".ogg") || lowerTarget.hasSuffix(".aac") || lowerTarget.hasSuffix(".flac") || lowerTarget.contains("audio/") || lowerAlt.contains("music") || lowerAlt.contains("audio") {
            kind = .audio
        } else {
            kind = .image
        }
        return (kind, alt.isEmpty ? "Generated Media" : alt, rawTarget)
    }
}

// MARK: - Chat Stage

/// Non-reactive reference box so high-frequency 120Hz NSEvent.scrollWheel ticks
/// never trigger SwiftUI @State body re-evaluations on AgentChatStage.
private final class ChatScrollInteractionTracker {
    var lastUserScrollUpTime: Date = .distantPast
    var lastAutoScrollTime: Date = .distantPast
    var monitor: Any? = nil
}

struct AgentChatStage: View, Equatable {
    @EnvironmentObject var appState: AppState
    let messages: [AgentMessageModel]
    let isLoading: Bool
    var domain: AgentDomain = .software
    var currentToolExecution: String? = nil
    var hasEarlierMessages: Bool = false
    var queuedMessages: [QueuedMessage] = []
    var activeChatId: String? = nil
    var onApplyChange: ((PendingChangeModel) -> Void)? = nil
    var onRejectChange: ((PendingChangeModel) -> Void)? = nil
    var onSuggestionTap: ((String) -> Void)? = nil
    var onViewPlan: (() -> Void)? = nil
    var onRevertToMessage: ((String) -> Void)? = nil
    var onEditAndResendMessage: ((String, String) -> Void)? = nil
    var onRetryAssistantMessage: ((String) -> Void)? = nil
    var onDeleteMessage: ((String, Bool) -> Void)? = nil
    
    @ObservedObject private var planManager = ImplementationPlanManager.shared
    @State private var userScrolledUp: Bool = false
    @State private var scrollTracker = ChatScrollInteractionTracker()
    
    static func == (lhs: AgentChatStage, rhs: AgentChatStage) -> Bool {
        lhs.isLoading == rhs.isLoading &&
        lhs.domain == rhs.domain &&
        lhs.currentToolExecution == rhs.currentToolExecution &&
        lhs.hasEarlierMessages == rhs.hasEarlierMessages &&
        lhs.queuedMessages.count == rhs.queuedMessages.count &&
        lhs.activeChatId == rhs.activeChatId &&
        lhs.messages.count == rhs.messages.count &&
        lhs.messages.first?.id == rhs.messages.first?.id &&
        lhs.messages.last?.id == rhs.messages.last?.id &&
        lhs.messages.last?.content == rhs.messages.last?.content &&
        lhs.messages.last?.toolResults.count == rhs.messages.last?.toolResults.count &&
        lhs.messages.last?.pendingChanges == rhs.messages.last?.pendingChanges
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        if messages.isEmpty && !isLoading && queuedMessages.isEmpty {
                            VStack(spacing: 20) {
                                Spacer().frame(height: 40)
                                
                                VStack(spacing: 6) {
                                    Text(domain == .science ? "Science Agent" : "AI Agent")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary.opacity(0.8))
                                    
                                    Text(domain == .science ? "Analyze evidence, structures, data, and scientific literature" : "Ask anything, write code, debug, or explore ideas")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                
                                // Quick suggestions
                                VStack(spacing: 8) {
                                    ForEach(domain == .science ? [
                                        "Analyze the scientific evidence in this project",
                                        "Compare wild-type and mutant structures",
                                        "Validate the AlphaFold workflow and confidence",
                                        "Draft a LaTeX research report from project evidence"
                                    ] : [
                                        "Explain this code",
                                        "Find bugs in my project",
                                        "Refactor for performance",
                                        "Write unit tests"
                                    ], id: \.self) { suggestion in
                                        Button(action: {
                                            onSuggestionTap?(suggestion)
                                        }) {
                                            HStack {
                                                Text(suggestion)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.primary.opacity(0.7))
                                                Spacer()
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(Color.primary.opacity(0.035))
                                            .cornerRadius(5)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 5)
                                                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .frame(maxWidth: 720)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 24)
                                .padding(.top, 8)
                                
                                Spacer()
                            }
                        } else {
                            if hasEarlierMessages {
                                Button("Load earlier messages") {
                                    AgentService.shared.loadEarlierMessages()
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 12)
                            }
                            let lastMessageId = messages.last?.id
                            ForEach(messages) { message in
                                RichMessageRow(
                                    message: message,
                                    isStreaming: isLoading && message.id == lastMessageId,
                                    onApplyChange: onApplyChange,
                                    onRejectChange: onRejectChange,
                                    onRevert: { onRevertToMessage?(message.id) },
                                    onEditAndResend: { editedText in onEditAndResendMessage?(message.id, editedText) },
                                    onRetry: { onRetryAssistantMessage?(message.id) },
                                    onDelete: { revertFiles in onDeleteMessage?(message.id, revertFiles) }
                                )
                                .equatable()
                                .id(message.id)
                            }
                            
                            if messages.isEmpty && isLoading {
                                HStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    HStack(spacing: 10) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text(currentToolExecution ?? "Agent is executing task...")
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    .padding(14)
                                    .background(Color.primary.opacity(0.04))
                                    .cornerRadius(8)
                                    .frame(maxWidth: 880)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                            }
                            
                            // Render any queued user messages directly in the chat stream so they never appear to vanish
                            ForEach(queuedMessages) { queued in
                                HStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    VStack(alignment: .trailing, spacing: 4) {
                                        HStack(spacing: 0) {
                                            Spacer(minLength: 48)
                                            Text(queued.text.count > 500 ? String(queued.text.prefix(500)) + "…" : queued.text)
                                                .font(Font.custom(appState.agentFontName, size: appState.agentFontSize))
                                                .foregroundColor(.primary.opacity(0.9))
                                                .multilineTextAlignment(.leading)
                                                .lineLimit(6)
                                                .padding(12)
                                                .background(Color.orange.opacity(0.14))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                                                )
                                                .cornerRadius(8)
                                                .frame(maxWidth: 600, alignment: .trailing)
                                        }
                                        HStack(spacing: 8) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "clock.fill")
                                                    .font(.system(size: 9))
                                                Text("อยู่ในคิว (จะส่งต่ออัตโนมัติ)")
                                                    .font(.system(size: 10, weight: .medium))
                                            }
                                            .foregroundColor(.orange)
                                            
                                            Button(action: {
                                                AgentService.shared.stopGeneration(autoProcessQueue: true)
                                            }) {
                                                Text("ส่งทันที (Send Now)")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundColor(.accentColor)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.accentColor.opacity(0.12))
                                                    .cornerRadius(4)
                                            }
                                            .buttonStyle(.plain)
                                            
                                            Button(action: {
                                                AgentService.shared.cancelQueuedMessage(id: queued.id)
                                            }) {
                                                Text("ยกเลิก")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .frame(maxWidth: 880, alignment: .trailing)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .id("queued_\(queued.id.uuidString)")
                            }
                            
                            // Inline plan approval card (Persists throughout plan lifecycle)
                            if let _ = planManager.currentPlan, !messages.isEmpty {
                                HStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    PlanApprovalInlineCard(
                                        planManager: planManager,
                                        onViewPlan: onViewPlan
                                    )
                                    .environmentObject(appState)
                                    .frame(maxWidth: 880)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 28)
                                .padding(.vertical, 8)
                            }
                            
                            Color.clear
                                .frame(height: 1)
                                .id("BOTTOM_CHAT_ANCHOR")
                        }
                    }
                    .padding(.bottom, 16)
                }
                
                // Floating "Scroll to latest" button when user scrolls up
                if userScrolledUp && !messages.isEmpty {
                    Button(action: {
                        userScrolledUp = false
                        scrollTracker.lastUserScrollUpTime = .distantPast
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("Latest messages")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: appState.appTheme.elevatedBackground))
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .onChange(of: activeChatId) { _ in
                userScrolledUp = false
                scrollTracker.lastUserScrollUpTime = .distantPast
                DispatchQueue.main.async {
                    proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                }
            }
            .onChange(of: messages.count) { _ in
                let isNewUserTurn = messages.last?.role == .user
                    || (messages.count >= 2 && messages[messages.count - 2].role == .user && messages.last?.id == "streaming" && (messages.last?.content.isEmpty ?? true))
                if isNewUserTurn || !userScrolledUp {
                    userScrolledUp = false
                    scrollTracker.lastUserScrollUpTime = .distantPast
                    DispatchQueue.main.async {
                        proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                    }
                }
            }
            .onChange(of: messages.last?.id) { _ in
                let isNewUserTurn = messages.last?.role == .user
                    || (messages.count >= 2 && messages[messages.count - 2].role == .user && messages.last?.id == "streaming" && (messages.last?.content.isEmpty ?? true))
                if isNewUserTurn || !userScrolledUp {
                    userScrolledUp = false
                    scrollTracker.lastUserScrollUpTime = .distantPast
                    DispatchQueue.main.async {
                        proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                    }
                }
            }
            .onChange(of: queuedMessages.count) { newCount in
                if newCount > 0 {
                    userScrolledUp = false
                    scrollTracker.lastUserScrollUpTime = .distantPast
                    DispatchQueue.main.async {
                        proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                    }
                }
            }
            .onChange(of: messages.last?.toolResults.count) { _ in
                if !userScrolledUp {
                    proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                }
            }
            .onChange(of: isLoading) { loading in
                if loading && !userScrolledUp {
                    proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                }
            }
            .onChange(of: messages.last?.content) { _ in
                if !userScrolledUp {
                    let now = Date()
                    if now.timeIntervalSince(scrollTracker.lastAutoScrollTime) >= 0.07 {
                        scrollTracker.lastAutoScrollTime = now
                        proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                    }
                }
            }
            .onAppear {
                if !messages.isEmpty {
                    proxy.scrollTo("BOTTOM_CHAT_ANCHOR", anchor: .bottom)
                }
                if scrollTracker.monitor == nil {
                    let tracker = scrollTracker
                    scrollTracker.monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
                        // Positive scrollingDeltaY means scrolling upward toward earlier messages
                        if event.scrollingDeltaY > 2.5 {
                            tracker.lastUserScrollUpTime = Date()
                            if !userScrolledUp {
                                userScrolledUp = true
                            }
                        }
                        return event
                    }
                }
            }
            .onDisappear {
                if let monitor = scrollTracker.monitor {
                    NSEvent.removeMonitor(monitor)
                    scrollTracker.monitor = nil
                }
            }
            .clipped()
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
                case .thought:
                    EmptyView()
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
                    
                case .table(let headers, let rows):
                    TableBlockView(headers: headers, rows: rows)
                    
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
                    
                case .media(let kind, let title, let target):
                    ChatMediaBlockView(kind: kind, title: title, target: target)
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
        LaTeXBlockView(expression: expression, isBlock: isBlock)
            .colorScheme(.light)
            .padding(.vertical, 4)
    }
}

// MARK: - Rich Message Row

struct RichMessageRow: View, Equatable {
    let message: AgentMessageModel
    var isStreaming: Bool = false
    var onApplyChange: ((PendingChangeModel) -> Void)? = nil
    var onRejectChange: ((PendingChangeModel) -> Void)? = nil
    var onRevert: (() -> Void)? = nil
    var onEditAndResend: ((String) -> Void)? = nil
    var onRetry: (() -> Void)? = nil
    var onDelete: ((Bool) -> Void)? = nil
    @EnvironmentObject var appState: AppState
    
    @State private var isEditing: Bool = false
    @State private var editedText: String = ""
    @State private var isCopied: Bool = false
    @State private var isUserMessageExpanded: Bool = false
    @State private var isHoveringMessage: Bool = false
    
    static func == (lhs: RichMessageRow, rhs: RichMessageRow) -> Bool {
        return lhs.message.id == rhs.message.id &&
               lhs.message.content == rhs.message.content &&
               lhs.message.toolResults.count == rhs.message.toolResults.count &&
               lhs.message.pendingChanges == rhs.message.pendingChanges &&
               lhs.message.role == rhs.message.role &&
               lhs.isStreaming == rhs.isStreaming
    }
    
    private var isUser: Bool { message.role == .user }
    
    var body: some View {
        if isUser {
            // AGY-style editorial prompt card: clean full-width rounded container
            // with hover-only action toolbar so the canvas stays minimal.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    if isEditing {
                        userInlineEditCard
                    } else {
                        userBubbleText
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contextMenu {
                                userMessageContextMenu
                            }
                        userActionToolbar
                            .opacity((isHoveringMessage || isCopied) ? 0.92 : 0)
                            .allowsHitTesting(isHoveringMessage || isCopied)
                    }
                }
                .frame(maxWidth: 880, alignment: .leading)
                .onHover { hovering in
                    if isHoveringMessage != hovering {
                        isHoveringMessage = hovering
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        } else {
            // A readable editorial column, inspired by the comfortable line
            // lengths used in Codex and AGY. It stays fluid in narrow splits,
            // but never turns a wide editor into one long line of prose.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    AICellContentHost(
                        message: message,
                        isStreaming: isStreaming,
                        onApplyChange: onApplyChange,
                        onRejectChange: onRejectChange
                    )
                    .equatable()
                    .textSelection(.enabled)
                    .contextMenu {
                        assistantMessageContextMenu
                    }
                    if !isStreaming && (!message.content.isEmpty || !message.toolResults.isEmpty) {
                        assistantActionToolbar
                            .opacity((isHoveringMessage || isCopied) ? 0.92 : 0)
                            .allowsHitTesting(isHoveringMessage || isCopied)
                    }
                }
                .frame(maxWidth: 880, alignment: .leading)
                .onHover { hovering in
                    if isHoveringMessage != hovering {
                        isHoveringMessage = hovering
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var isLongUserMessage: Bool {
        guard message.content.count > 750 else {
            var newlineCount = 0
            for ch in message.content where ch == "\n" {
                newlineCount += 1
                if newlineCount > 14 { return true }
            }
            return false
        }
        return true
    }

    private var collapsedUserPreviewText: String {
        let lines = message.content.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 14 {
            let joined = lines.prefix(12).joined(separator: "\n")
            return (joined.count > 750 ? String(joined.prefix(750)) : joined) + "\n…"
        }
        if message.content.count > 750 {
            return String(message.content.prefix(750)) + "…"
        }
        return message.content
    }

    private var userBubbleText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isLongUserMessage && !isUserMessageExpanded ? collapsedUserPreviewText : message.content)
                .font(Font.custom(appState.agentFontName, size: appState.agentFontSize))
                .foregroundColor(.primary.opacity(0.92))
                .multilineTextAlignment(.leading)
                .lineLimit(isLongUserMessage && !isUserMessageExpanded ? 14 : nil)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            
            if isLongUserMessage {
                Divider()
                    .opacity(0.25)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isUserMessageExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: isUserMessageExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9.5, weight: .bold))
                        Text(isUserMessageExpanded ? "ย่อข้อความ (Collapse)" : "แสดงข้อความทั้งหมด (\(message.content.count.formatted()) ตัวอักษร)")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(.accentColor)
                    .padding(.top, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
    
    private var userInlineEditCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("แก้ไขข้อความ (จะย้อนกลับข้อความหลังจากจุดนี้และส่งใหม่)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            if #available(macOS 13.0, *) {
                TextField("แก้ไขข้อความของคุณ...", text: $editedText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Font.custom(appState.agentFontName, size: appState.agentFontSize))
                    .lineLimit(2...10)
                    .padding(10)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                    )
            } else {
                TextEditor(text: $editedText)
                    .font(Font.custom(appState.agentFontName, size: appState.agentFontSize))
                    .frame(minHeight: 60, maxHeight: 160)
                    .padding(6)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                    )
            }
            
            HStack(spacing: 8) {
                Spacer()
                
                Button(action: {
                    isEditing = false
                }) {
                    Text("ยกเลิก (Cancel)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    isEditing = false
                    onEditAndResend?(trimmed)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 10))
                        Text("บันทึกและส่งใหม่ (Resend)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.4) : Color.accentColor)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(maxWidth: 620)
        .background(Color(nsColor: appState.appTheme.elevatedBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
        )
    }
    
    private var userActionToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                messageActionButton(
                    icon: "arrow.uturn.backward",
                    label: "ย้อนกลับ",
                    tooltip: "Restore Checkpoint — ย้อนกลับข้อความและการแก้ไขไฟล์มาที่จุดนี้ (Revert to this checkpoint)"
                ) {
                    onRevert?()
                }
                
                messageActionButton(
                    icon: "pencil",
                    label: "แก้ไข",
                    tooltip: "แก้ไขข้อความและส่งใหม่ (Edit & Resend)"
                ) {
                    editedText = AgentService.cleanUserPromptText(message.content)
                    isEditing = true
                }
                
                messageActionButton(
                    icon: "bookmark",
                    label: "บันทึกกฎ",
                    tooltip: "บันทึกคำสั่งนี้เป็นกฎของโปรเจกต์ใน .microcode/rules.md (Save as Project Rule)"
                ) {
                    let clean = AgentService.cleanUserPromptText(message.content)
                    let ws = AgentService.shared.currentWorkspace ?? appState.workspaceFolder?.path ?? FileManager.default.currentDirectoryPath
                    ProjectMemoryService.shared.appendLearnedRule(clean, workspace: ws)
                }
                
                messageActionButton(
                    icon: isCopied ? "checkmark" : "doc.on.doc",
                    label: isCopied ? "คัดลอกแล้ว" : "คัดลอก",
                    tooltip: "คัดลอกข้อความ (Copy message)",
                    tint: isCopied ? .green : nil
                ) {
                    copyTextToClipboard(AgentService.cleanUserPromptText(message.content))
                }
                
                messageActionButton(
                    icon: "trash",
                    label: "ลบ",
                    tooltip: "ลบข้อความนี้ (Delete message)",
                    isDestructive: true
                ) {
                    onDelete?(false)
                }
            }
        }
        .opacity(0.85)
    }
    
    private var assistantActionToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                messageActionButton(
                    icon: isCopied ? "checkmark" : "doc.on.doc",
                    label: isCopied ? "คัดลอกแล้ว" : "คัดลอก",
                    tooltip: "คัดลอกคำตอบ (Copy response)",
                    tint: isCopied ? .green : nil
                ) {
                    let clean = AIStructuredTurnCodec.stripThoughtTags(message.content)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    copyTextToClipboard(clean.isEmpty ? message.content : clean)
                }
                
                messageActionButton(
                    icon: "arrow.clockwise",
                    label: "ลองใหม่",
                    tooltip: "สร้างคำตอบใหม่อีกครั้ง (Regenerate response)"
                ) {
                    onRetry?()
                }
                
                messageActionButton(
                    icon: "arrow.uturn.backward",
                    label: message.pendingChanges.isEmpty ? "ย้อนกลับ" : "ย้อนกลับ (\(message.pendingChanges.count) ไฟล์)",
                    tooltip: "Restore Checkpoint — ย้อนกลับคำตอบนี้และคืนค่าไฟล์ที่ถูกแก้ไข (Revert turn & restore files)"
                ) {
                    onRevert?()
                }
                
                messageActionButton(
                    icon: "trash",
                    label: "ลบ",
                    tooltip: "ลบข้อความนี้ (Delete message)",
                    isDestructive: true
                ) {
                    onDelete?(true)
                }
                
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 2)
        .opacity(0.85)
    }
    
    @ViewBuilder
    private var userMessageContextMenu: some View {
        Button {
            editedText = AgentService.cleanUserPromptText(message.content)
            isEditing = true
        } label: {
            Label("แก้ไขข้อความและส่งใหม่ (Edit & Resend)", systemImage: "pencil")
        }
        
        Button {
            onRevert?()
        } label: {
            Label("ย้อนกลับข้อความและไฟล์มาที่จุดนี้ (Revert to Here)", systemImage: "arrow.uturn.backward")
        }
        
        Button {
            copyTextToClipboard(AgentService.cleanUserPromptText(message.content))
        } label: {
            Label("คัดลอกข้อความ (Copy)", systemImage: "doc.on.doc")
        }
        
        Divider()
        
        Button(role: .destructive) {
            onDelete?(false)
        } label: {
            Label("ลบข้อความนี้ (Delete Message)", systemImage: "trash")
        }
    }
    
    @ViewBuilder
    private var assistantMessageContextMenu: some View {
        Button {
            let clean = AIStructuredTurnCodec.stripThoughtTags(message.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            copyTextToClipboard(clean.isEmpty ? message.content : clean)
        } label: {
            Label("คัดลอกคำตอบ (Copy Response)", systemImage: "doc.on.doc")
        }
        
        Button {
            onRetry?()
        } label: {
            Label("ลองใหม่ / สร้างคำตอบใหม่ (Regenerate)", systemImage: "arrow.clockwise")
        }
        
        Button {
            onRevert?()
        } label: {
            Label("ย้อนกลับคำตอบนี้และคืนค่าไฟล์ (Revert Turn & Files)", systemImage: "arrow.uturn.backward")
        }
        
        Divider()
        
        Button(role: .destructive) {
            onDelete?(true)
        } label: {
            Label("ลบข้อความนี้ (Delete Message)", systemImage: "trash")
        }
    }
    
    private func messageActionButton(
        icon: String,
        label: String,
        tooltip: String,
        tint: Color? = nil,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3.5) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(tint ?? (isDestructive ? .red.opacity(0.85) : .secondary))
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color.primary.opacity(0.045))
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
    
    private func copyTextToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            isCopied = false
        }
    }
}

// MARK: - Equatable AI Cell Content Host (Isolates Hover State from Markdown/Tool Tree)

private struct AICellContentHost: View, Equatable {
    let message: AgentMessageModel
    let isStreaming: Bool
    var onApplyChange: ((PendingChangeModel) -> Void)?
    var onRejectChange: ((PendingChangeModel) -> Void)?

    static func == (lhs: AICellContentHost, rhs: AICellContentHost) -> Bool {
        lhs.message.id == rhs.message.id &&
        lhs.message.content == rhs.message.content &&
        lhs.message.toolResults.count == rhs.message.toolResults.count &&
        lhs.message.pendingChanges == rhs.message.pendingChanges &&
        lhs.isStreaming == rhs.isStreaming
    }

    var body: some View {
        let blocks = MessageContentParser.parse(message.content)
        let lastThoughtIdx = blocks.lastIndex(where: {
            if case .thought = $0 { return true }
            return false
        })
        let preToolBlocks: [MessageBlock] = {
            guard !message.toolResults.isEmpty else { return blocks }
            guard let idx = lastThoughtIdx else { return [] }
            return Array(blocks[0...idx])
        }()
        let postToolBlocks: [MessageBlock] = {
            guard !message.toolResults.isEmpty else { return [] }
            guard let idx = lastThoughtIdx else { return blocks }
            guard idx + 1 < blocks.count else { return [] }
            return Array(blocks[(idx + 1)...])
        }()
        let harness = SubAgentHarness.shared
        let isLatestStreaming = isStreaming || (AgentService.shared.isLoading && AgentService.shared.messages.last?.id == message.id)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(preToolBlocks) { block in
                aiBlockView(block, isLatestStreaming: isLatestStreaming)
            }
            
            if !message.toolResults.isEmpty {
                ToolExecutionStepsView(results: message.toolResults, isStreaming: isLatestStreaming)
            }
            
            ForEach(postToolBlocks) { block in
                aiBlockView(block, isLatestStreaming: isLatestStreaming)
            }
            
            // Immediate active progress indicator while agent is connecting/thinking and no content yet
            if blocks.isEmpty && message.toolResults.isEmpty && isLatestStreaming {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(AgentService.shared.currentToolExecution ?? "Agent is preparing response...")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
            }
            
            // CEO & Specialist Squad Live Boardroom + SubAgent activity cluster (shown on the latest assistant message only)
            if AgentService.shared.messages.last?.id == message.id {
                if !harness.interAgentDialogue.isEmpty || !harness.activeContracts.isEmpty {
                    CEOSquadBoardroomInlineView()
                }
                if !harness.activeSubagents.isEmpty {
                    SubAgentClusterView(subagents: harness.activeSubagents)
                }
            }
            
            if !message.pendingChanges.isEmpty {
                pendingChangesSection
            }
            
            if message.content.contains("Reached maximum tool iteration safety limit") {
                Button(action: {
                    AgentService.shared.enqueueMessage("Continue executing the task from where you left off. Continue immediately with the next necessary step.")
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.orange)
                        Text("Continue Task (ทำงานต่อ)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.35), lineWidth: 1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            
            if !AgentService.shared.isLoading && (message.content.contains("⚠️ Rate limit reached") || message.content.contains("⚠️ Error: Rate limited")) {
                Button(action: {
                    AgentService.shared.enqueueMessage("Retry the previous step with pruned context. Proceed with the necessary action.")
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.yellow)
                        Text("Retry Now (ลองใหม่อีกครั้ง)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.yellow.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow.opacity(0.35), lineWidth: 1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }
    
    @ViewBuilder
    private func aiBlockView(_ block: MessageBlock, isLatestStreaming: Bool) -> some View {
        switch block {
        case .thought(let content, let duration):
            AntigravityThoughtBlockView(
                content: content,
                durationSeconds: duration,
                isActivelyStreaming: isLatestStreaming && duration == nil
            )
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
        case .table(let headers, let rows):
            TableBlockView(headers: headers, rows: rows)
        case .blockquote(let content):
            BlockquoteView(content: content)
        case .latex(let expression, let isBlock):
            LaTeXBlockView(expression: expression, isBlock: isBlock)
        case .html(let content):
            HTMLBlockView(content: content)
        case .media(let kind, let title, let target):
            ChatMediaBlockView(kind: kind, title: title, target: target)
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
                PendingChangeCard(
                    change: change,
                    onApply: onApplyChange,
                    onReject: onRejectChange,
                    onPartialApply: { change, reconstructedContent in
                        // P4: Write reconstructed file (with only accepted hunks) to disk
                        let url = URL(fileURLWithPath: change.filePath)
                        try? reconstructedContent.write(to: url, atomically: true, encoding: .utf8)
                        onApplyChange?(change)
                    }
                )
                    .equatable()
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Pending Change Card (Modern Antigravity / Cursor Diff View)

private struct PendingChangeCard: View, Equatable {
    let change: PendingChangeModel
    var onApply: ((PendingChangeModel) -> Void)?
    var onReject: ((PendingChangeModel) -> Void)?
    var onPartialApply: ((PendingChangeModel, String) -> Void)?  // P4: partial hunk apply
    @State private var showDiffOverride: Bool? = nil
    @State private var showAllDiffLines = false
    @State private var showHunkReview = false  // P4: hunk-level review mode
    @State private var hunkDiffResult = DiffResult(oldContent: "", newContent: "", hunks: [], additions: 0, deletions: 0)
    
    private let initialVisibleLineLimit = 64
    
    private var showDiff: Bool {
        showDiffOverride ?? (change.status == .pending)
    }
    
    static func == (lhs: PendingChangeCard, rhs: PendingChangeCard) -> Bool {
        return lhs.change == rhs.change
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            changeCardHeader
            
            if showHunkReview && change.status == .pending {
                // P4: Hunk-level review using InlineDiffView
                InlineDiffView(diffResult: $hunkDiffResult, filePath: change.filePath, onClose: {
                    withAnimation(.easeInOut(duration: 0.15)) { showHunkReview = false }
                })
                .frame(maxHeight: 400)
            } else if showDiff {
                if change.filePath.lowercased().hasSuffix(".md") {
                    ScrollView {
                        RenderedMarkdownDocumentView(markdown: change.newContent.isEmpty ? change.oldContent : change.newContent)
                            .padding(14)
                    }
                    .frame(maxHeight: 360)
                    .background(Color.primary.opacity(0.02))
                } else {
                    codeDiffSection
                }
            } else {
                changeSummaryRow
            }
            
            if change.status == .pending {
                changeCardActions
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    change.status == .accepted ? Color.green.opacity(0.35) :
                    change.status == .rejected ? Color.red.opacity(0.35) :
                    Color.primary.opacity(0.12),
                    lineWidth: 1
                )
        )
    }
    
    private var changeCardHeader: some View {
        HStack(spacing: 8) {
            Button(action: {
                let targetURL = URL(fileURLWithPath: change.filePath)
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    PreviewDockService.shared.openFile(url: targetURL, makeActive: true)
                } else {
                    PreviewDockService.shared.openFileFromReference(change.filePath)
                }
            }) {
                HStack(spacing: 8) {
                    ProgrammingLanguageIconView(
                        fileName: URL(fileURLWithPath: change.filePath).lastPathComponent,
                        size: 16
                    )
                    
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(URL(fileURLWithPath: change.filePath).lastPathComponent)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                            
                            // Additions / Deletions pills
                            HStack(spacing: 4) {
                                if change.additions > 0 {
                                    Text("+\(change.additions)")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.12))
                                        .cornerRadius(3)
                                }
                                if change.deletions > 0 {
                                    Text("-\(change.deletions)")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.red.opacity(0.12))
                                        .cornerRadius(3)
                                }
                            }
                        }
                        
                        Text(change.description)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to preview file in Right Split Pane")
            
            Spacer()
            
            // Toggle diff
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { showDiffOverride = !showDiff } }) {
                HStack(spacing: 3) {
                    Text(showDiff ? "Hide Diff" : "Show Diff")
                        .font(.system(size: 10, weight: .medium))
                    Image(systemName: showDiff ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            
            changeCardStatusLabel
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.02))
    }
    
    @ViewBuilder
    private var changeCardStatusLabel: some View {
        if change.status == .accepted {
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                Text("Applied")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.green)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.12))
            .cornerRadius(4)
        } else if change.status == .rejected {
            Text("Rejected")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.12))
                .cornerRadius(4)
        }
    }
    
    private var changeSummaryRow: some View {
        HStack(spacing: 6) {
            ProgrammingLanguageIconView(
                fileName: URL(fileURLWithPath: change.filePath).lastPathComponent,
                size: 12
            )
            Text(change.description).font(.system(size: 10)).foregroundColor(.secondary)
            Spacer()
        }
        .padding(8)
    }
    
    // MARK: - Code Diff (Modern High-Contrast Unified Code Diff with Memoization & Metal Rasterization)
    
    private var codeDiffSection: some View {
        let cached = DiffCacheManager.getOrComputeDiffEntry(
            id: change.id,
            old: change.oldContent,
            new: change.newContent
        )
        let allLines = cached.lines
        let isTruncated = !showAllDiffLines && allLines.count > initialVisibleLineLimit
        let visibleLines: ArraySlice<UnifiedDiffLine> = isTruncated
            ? allLines.prefix(initialVisibleLineLimit)
            : allLines[...]
        
        return VStack(spacing: 0) {
            Divider().opacity(0.4)
            
            VStack(alignment: .leading, spacing: 0) {
                ForEach(visibleLines) { (diffLine: UnifiedDiffLine) in
                    HStack(spacing: 0) {
                        // Status accent strip (2.5pt)
                        Rectangle()
                            .fill(diffLine.accentColor)
                            .frame(width: 2.5)
                        
                        // Pre-formatted monospaced gutter (oldNum + newNum)
                        Text(diffLine.gutterNumbers)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(diffLine.type == .hunkHeader ? .cyan.opacity(0.7) : .secondary.opacity(0.4))
                            .frame(width: 64, alignment: .trailing)
                            .padding(.trailing, 6)
                        
                        // Gutter divider line
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 1)
                        
                        // Prefix (+/-) and code text
                        Text(diffLine.prefix)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(diffLine.prefixColor)
                            .frame(width: 18, alignment: .center)
                        
                        Text(diffLine.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(diffLine.textColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        Spacer(minLength: 0)
                    }
                    .frame(height: 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(diffLine.bgColor)
                }
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            
            if allLines.count > initialVisibleLineLimit {
                Divider().opacity(0.3)
                Button(action: {
                    showAllDiffLines.toggle()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: showAllDiffLines ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                        Text(showAllDiffLines
                             ? "Collapse diff (\(initialVisibleLineLimit) of \(allLines.count) lines)"
                             : "Show all \(allLines.count) diff lines (+\(allLines.count - initialVisibleLineLimit) more)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.03))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var changeCardActions: some View {
        VStack(spacing: 0) {
            if showHunkReview {
                // Hunk-level review actions
                HStack(spacing: 8) {
                    let accepted = hunkDiffResult.hunks.filter { $0.status == .accepted }.count
                    let rejected = hunkDiffResult.hunks.filter { $0.status == .rejected }.count
                    let total = hunkDiffResult.hunks.count
                    let pending = total - accepted - rejected
                    
                    // Status
                    HStack(spacing: 4) {
                        if accepted > 0 {
                            Text("\(accepted)✓")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.green)
                        }
                        if rejected > 0 {
                            Text("\(rejected)✗")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.red)
                        }
                        if pending > 0 {
                            Text("\(pending) pending")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Apply Selected Hunks
                    if accepted > 0 || pending == 0 {
                        Button(action: {
                            let reconstructed = reconstructFileFromHunks(
                                oldContent: change.oldContent,
                                diff: hunkDiffResult
                            )
                            onPartialApply?(change, reconstructed)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text(accepted == total ? "Apply All" : "Apply \(accepted) Hunks")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Back to simple view
                    Button(action: { withAnimation(.easeInOut(duration: 0.15)) { showHunkReview = false } }) {
                        Text("Simple View")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.02))
            } else {
                // Standard file-level actions
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
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Hunk review toggle — the P4 feature
                    Button(action: {
                        // Compute hunk diff if not already done
                        if hunkDiffResult.hunks.isEmpty {
                            hunkDiffResult = DiffEngine.shared.computeDiff(
                                old: change.oldContent,
                                new: change.newContent
                            )
                        }
                        withAnimation(.easeInOut(duration: 0.15)) { showHunkReview = true }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "rectangle.split.3x1")
                            Text("Review Hunks")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.02))
            }
        }
    }
    
    // MARK: - P4: Reconstruct File from Accepted/Rejected Hunks
    
    /// Builds the final file by applying only accepted hunks.
    /// Rejected hunks keep the original lines. Pending hunks are treated as rejected.
    private func reconstructFileFromHunks(oldContent: String, diff: DiffResult) -> String {
        let oldLines = oldContent.components(separatedBy: "\n")
        var result: [String] = []
        var oldIndex = 0
        
        // Sort hunks by their position in the old file
        let sortedHunks = diff.hunks.sorted { $0.oldRange.lowerBound < $1.oldRange.lowerBound }
        
        for hunk in sortedHunks {
            let hunkStart = max(0, hunk.oldRange.lowerBound)
            
            // Copy unchanged lines before this hunk
            while oldIndex < hunkStart && oldIndex < oldLines.count {
                result.append(oldLines[oldIndex])
                oldIndex += 1
            }
            
            if hunk.status == .accepted {
                // Apply new lines
                result.append(contentsOf: hunk.newLines)
            } else {
                // Keep old lines (rejected or pending)
                result.append(contentsOf: hunk.oldLines)
            }
            
            // Skip past old lines covered by this hunk
            oldIndex = min(oldLines.count, hunk.oldRange.upperBound)
        }
        
        // Copy remaining lines after last hunk
        while oldIndex < oldLines.count {
            result.append(oldLines[oldIndex])
            oldIndex += 1
        }
        
        return result.joined(separator: "\n")
    }
}

// MARK: - Memoized Diff Cache Manager

public struct UnifiedDiffLine: Identifiable, Equatable {
    public let id: String
    public let oldNum: String
    public let newNum: String
    public let gutterNumbers: String
    public let prefix: String
    public let text: String
    public let type: DiffLineType
    
    public enum DiffLineType {
        case context, addition, deletion, hunkHeader
    }
    
    public init(id: String, oldNum: String, newNum: String, prefix: String, text: String, type: DiffLineType) {
        self.id = id
        self.oldNum = oldNum
        self.newNum = newNum
        let paddedOld = oldNum.count < 4 ? String(repeating: " ", count: 4 - oldNum.count) + oldNum : oldNum
        let paddedNew = newNum.count < 4 ? String(repeating: " ", count: 4 - newNum.count) + newNum : newNum
        self.gutterNumbers = "\(paddedOld) \(paddedNew)"
        self.prefix = prefix
        self.text = text
        self.type = type
    }
    
    var accentColor: Color {
        switch type {
        case .addition: return .green
        case .deletion: return .red
        case .hunkHeader: return .cyan
        case .context: return .clear
        }
    }
    
    var prefixColor: Color {
        switch type {
        case .addition: return .green
        case .deletion: return .red
        case .hunkHeader: return .cyan
        case .context: return .secondary.opacity(0.25)
        }
    }
    
    var textColor: Color {
        switch type {
        case .addition: return Color.primary
        case .deletion: return Color.primary.opacity(0.7)
        case .hunkHeader: return Color.cyan.opacity(0.85)
        case .context: return Color.primary.opacity(0.85)
        }
    }
    
    var bgColor: Color {
        switch type {
        case .addition: return Color.green.opacity(0.12)
        case .deletion: return Color.red.opacity(0.10)
        case .hunkHeader: return Color.cyan.opacity(0.07)
        case .context: return Color.clear
        }
    }
}

public struct CachedDiffEntry {
    public let lines: [UnifiedDiffLine]
    public let minContentWidth: CGFloat
}

public final class DiffCacheManager {
    private static var cache: [String: CachedDiffEntry] = [:]
    private static let lock = NSLock()
    
    public static func getOrComputeDiff(id: String, old: @autoclosure () -> String, new: @autoclosure () -> String) -> [UnifiedDiffLine] {
        return getOrComputeDiffEntry(id: id, old: old(), new: new()).lines
    }
    
    public static func getOrComputeDiffEntry(id: String, old: @autoclosure () -> String, new: @autoclosure () -> String) -> CachedDiffEntry {
        lock.lock()
        if let found = cache[id] {
            lock.unlock()
            return found
        }
        lock.unlock()
        
        let oldStr = old()
        let newStr = new()
        let lines = computeDiff(old: oldStr, new: newStr)
        let maxChars = lines.reduce(0) { max($0, min($1.text.count, 240)) }
        // Fast O(1) monospaced width calculation (11pt monospaced ≈ 6.65pt/char + 128pt gutter/padding)
        let minContentWidth = CGFloat(maxChars) * 6.65 + 128.0
        let entry = CachedDiffEntry(lines: lines, minContentWidth: minContentWidth)
        
        lock.lock()
        if cache.count > 64 { cache.removeAll(keepingCapacity: true) }
        cache[id] = entry
        lock.unlock()
        
        return entry
    }
    
    public static func clearAll() {
        lock.lock()
        cache.removeAll(keepingCapacity: false)
        lock.unlock()
    }
    
    private static func computeDiff(old: String, new: String) -> [UnifiedDiffLine] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")
        
        // Fast path for identical content
        if old == new {
            let previewCount = min(oldLines.count, 12)
            var lines = oldLines.prefix(previewCount).enumerated().map { idx, line in
                UnifiedDiffLine(id: "ctx-\(idx)", oldNum: "\(idx + 1)", newNum: "\(idx + 1)", prefix: " ", text: line, type: .context)
            }
            if oldLines.count > previewCount {
                lines.append(UnifiedDiffLine(
                    id: "ctx-more",
                    oldNum: "⋯",
                    newNum: "⋯",
                    prefix: "@@",
                    text: "\(oldLines.count - previewCount) more unchanged lines",
                    type: .hunkHeader
                ))
            }
            return lines
        }
        
        // 1. Trim common unchanged prefix and suffix in O(N) so edits deep inside large files
        // are never cut off by DP matrix limits and LCS only runs on the changed middle region.
        var prefixCount = 0
        let minTotal = min(oldLines.count, newLines.count)
        while prefixCount < minTotal && oldLines[prefixCount] == newLines[prefixCount] {
            prefixCount += 1
        }
        
        var suffixCount = 0
        while suffixCount < (minTotal - prefixCount) &&
              oldLines[oldLines.count - 1 - suffixCount] == newLines[newLines.count - 1 - suffixCount] {
            suffixCount += 1
        }
        
        let midOld = Array(oldLines[prefixCount..<(oldLines.count - suffixCount)])
        let midNew = Array(newLines[prefixCount..<(newLines.count - suffixCount)])
        
        enum RawOp {
            case equal(String, Int, Int)
            case delete(String, Int)
            case insert(String, Int)
            
            var isChange: Bool {
                switch self {
                case .equal: return false
                case .delete, .insert: return true
                }
            }
        }
        
        var midOps: [RawOp] = []
        let dpCap = 350
        let m = min(midOld.count, dpCap)
        let n = min(midNew.count, dpCap)
        
        if m > 0 && n > 0 {
            var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
            for i in 1...m {
                for j in 1...n {
                    if midOld[i - 1] == midNew[j - 1] {
                        dp[i][j] = dp[i - 1][j - 1] + 1
                    } else {
                        dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                    }
                }
            }
            
            enum StepOp { case equal(String), delete(String), insert(String) }
            var steps: [StepOp] = []
            var i = m, j = n
            while i > 0 || j > 0 {
                if i > 0 && j > 0 && midOld[i - 1] == midNew[j - 1] {
                    steps.append(.equal(midOld[i - 1]))
                    i -= 1; j -= 1
                } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                    steps.append(.insert(midNew[j - 1]))
                    j -= 1
                } else if i > 0 {
                    steps.append(.delete(midOld[i - 1]))
                    i -= 1
                }
            }
            steps.reverse()
            
            var curOld = prefixCount + 1
            var curNew = prefixCount + 1
            for step in steps {
                switch step {
                case .equal(let t):
                    midOps.append(.equal(t, curOld, curNew))
                    curOld += 1; curNew += 1
                case .delete(let t):
                    midOps.append(.delete(t, curOld))
                    curOld += 1
                case .insert(let t):
                    midOps.append(.insert(t, curNew))
                    curNew += 1
                }
            }
            // Append any overflow beyond dpCap
            if midOld.count > m {
                for idx in m..<midOld.count {
                    midOps.append(.delete(midOld[idx], curOld))
                    curOld += 1
                }
            }
            if midNew.count > n {
                for idx in n..<midNew.count {
                    midOps.append(.insert(midNew[idx], curNew))
                    curNew += 1
                }
            }
        } else {
            var curOld = prefixCount + 1
            for line in midOld {
                midOps.append(.delete(line, curOld))
                curOld += 1
            }
            var curNew = prefixCount + 1
            for line in midNew {
                midOps.append(.insert(line, curNew))
                curNew += 1
            }
        }
        
        // 2. Build UnifiedDiffLines with ±3 context lines around changes and collapsed hunk headers
        let contextRadius = 3
        var result: [UnifiedDiffLine] = []
        var lineCounter = 0
        
        // Leading unchanged prefix: collapse if > contextRadius
        if prefixCount > 0 {
            let keepStart = max(0, prefixCount - contextRadius)
            if keepStart > 0 {
                result.append(UnifiedDiffLine(
                    id: "hunk-pre",
                    oldNum: "⋯",
                    newNum: "⋯",
                    prefix: "@@",
                    text: "@@ -1,\(keepStart) +1,\(keepStart) @@  •  \(keepStart) unchanged lines",
                    type: .hunkHeader
                ))
            }
            for idx in keepStart..<prefixCount {
                lineCounter += 1
                result.append(UnifiedDiffLine(
                    id: "pre-\(lineCounter)",
                    oldNum: "\(idx + 1)",
                    newNum: "\(idx + 1)",
                    prefix: " ",
                    text: oldLines[idx],
                    type: .context
                ))
            }
        }
        
        // Middle ops: collapse any unchanged run longer than 2 * contextRadius + 1
        var keepMid = Array(repeating: false, count: midOps.count)
        for idx in midOps.indices where midOps[idx].isChange {
            let lo = max(0, idx - contextRadius)
            let hi = min(midOps.count - 1, idx + contextRadius)
            for k in lo...hi {
                keepMid[k] = true
            }
        }
        
        var idx = 0
        while idx < midOps.count {
            if keepMid[idx] {
                lineCounter += 1
                switch midOps[idx] {
                case .equal(let text, let oNum, let nNum):
                    result.append(UnifiedDiffLine(
                        id: "eq-\(lineCounter)",
                        oldNum: "\(oNum)",
                        newNum: "\(nNum)",
                        prefix: " ",
                        text: text,
                        type: .context
                    ))
                case .delete(let text, let oNum):
                    result.append(UnifiedDiffLine(
                        id: "del-\(lineCounter)",
                        oldNum: "\(oNum)",
                        newNum: "",
                        prefix: "-",
                        text: text,
                        type: .deletion
                    ))
                case .insert(let text, let nNum):
                    result.append(UnifiedDiffLine(
                        id: "ins-\(lineCounter)",
                        oldNum: "",
                        newNum: "\(nNum)",
                        prefix: "+",
                        text: text,
                        type: .addition
                    ))
                }
                idx += 1
            } else {
                let runStart = idx
                while idx < midOps.count && !keepMid[idx] {
                    idx += 1
                }
                let skipped = idx - runStart
                if skipped == 1, case .equal(let text, let oNum, let nNum) = midOps[runStart] {
                    lineCounter += 1
                    result.append(UnifiedDiffLine(
                        id: "eq-\(lineCounter)",
                        oldNum: "\(oNum)",
                        newNum: "\(nNum)",
                        prefix: " ",
                        text: text,
                        type: .context
                    ))
                } else if case .equal(_, let firstOld, let firstNew) = midOps[runStart] {
                    result.append(UnifiedDiffLine(
                        id: "hunk-\(runStart)",
                        oldNum: "⋯",
                        newNum: "⋯",
                        prefix: "@@",
                        text: "@@ -\(firstOld),\(skipped) +\(firstNew),\(skipped) @@  •  \(skipped) unchanged lines",
                        type: .hunkHeader
                    ))
                }
            }
            if result.count >= 400 { break }
        }
        
        // Trailing unchanged suffix: keep up to contextRadius lines, collapse the rest
        if suffixCount > 0 && result.count < 400 {
            let keepCount = min(suffixCount, contextRadius)
            let oldSuffixStart = oldLines.count - suffixCount
            let newSuffixStart = newLines.count - suffixCount
            for k in 0..<keepCount {
                lineCounter += 1
                result.append(UnifiedDiffLine(
                    id: "suf-\(lineCounter)",
                    oldNum: "\(oldSuffixStart + k + 1)",
                    newNum: "\(newSuffixStart + k + 1)",
                    prefix: " ",
                    text: oldLines[oldSuffixStart + k],
                    type: .context
                ))
            }
            let remainingSuffix = suffixCount - keepCount
            if remainingSuffix > 0 {
                let startOld = oldSuffixStart + keepCount + 1
                let startNew = newSuffixStart + keepCount + 1
                result.append(UnifiedDiffLine(
                    id: "hunk-suf",
                    oldNum: "⋯",
                    newNum: "⋯",
                    prefix: "@@",
                    text: "@@ -\(startOld),\(remainingSuffix) +\(startNew),\(remainingSuffix) @@  •  \(remainingSuffix) unchanged lines",
                    type: .hunkHeader
                ))
            }
        }
        
        return result
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

final class MarkdownAttrCache {
    private static var cache: [String: AttributedString] = [:]
    private static let lock = NSLock()
    
    private static let inlineCodeFileRegex = try? NSRegularExpression(
        pattern: #"(?<!\[)`([^`\n]+?\.(?:swift|ts|tsx|js|jsx|svelte|vue|astro|py|rs|go|java|kt|kts|c|cpp|cc|h|hpp|m|mm|html|css|scss|json|yaml|yml|toml|sql|sh|md|ar|dart|rb|php|cs|proto|graphql)(?:#L\d+(?:-L?\d+)?)?)`(?!\])"#,
        options: [.caseInsensitive]
    )

    private static func sanitizeStreamingMarkdown(_ text: String) -> String {
        var working = text
        // During streaming, if the text ends with an unclosed markdown link `[label](url_fragment`,
        // strip the incomplete `(url_fragment` so AttributedString(markdown:) still parses earlier links.
        if let lastOpenBracket = working.lastIndex(of: "["),
           let midParen = working[lastOpenBracket...].range(of: "]("),
           !working[midParen.upperBound...].contains(")") {
            let label = working[working.index(after: lastOpenBracket)..<midParen.lowerBound]
            working.replaceSubrange(lastOpenBracket..<working.endIndex, with: "`\(label)`")
        }
        // Auto-convert standalone backticked code file names (e.g. `+page.svelte`, `AIUsageTracker.swift#L10-20`)
        // into clickable `microcode-file://` links so clicking them opens the AGY-style Right Code Preview Split Pane.
        if let regex = inlineCodeFileRegex {
            let ns = working as NSString
            let matches = regex.matches(in: working, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() where match.numberOfRanges >= 2 {
                let rawFile = ns.substring(with: match.range(at: 1))
                if let encoded = rawFile.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.union(.init(charactersIn: "#-:"))) {
                    let replacement = "[`\(rawFile)`](microcode-file://\(encoded))"
                    working = (working as NSString).replacingCharacters(in: match.range, with: replacement)
                }
            }
        }
        return working
    }
    
    static func getOrParse(_ text: String) -> AttributedString {
        lock.lock()
        if let found = cache[text] {
            lock.unlock()
            return found
        }
        lock.unlock()
        
        let sanitized = sanitizeStreamingMarkdown(text)
        let parsed = (try? AttributedString(markdown: sanitized, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(sanitized)
        
        lock.lock()
        if cache.count > 1024 { cache.removeAll(keepingCapacity: true) }
        cache[text] = parsed
        lock.unlock()
        return parsed
    }
    
    static func clearAll() {
        lock.lock()
        cache.removeAll(keepingCapacity: false)
        lock.unlock()
    }
}

/// Renders inline markdown (bold, italic, code, links)
struct MarkdownTextView: View, Equatable {
    let text: String
    @EnvironmentObject var appState: AppState
    
    static func == (lhs: MarkdownTextView, rhs: MarkdownTextView) -> Bool {
        return lhs.text == rhs.text
    }
    
    private var fontSize: CGFloat {
        appState.agentFontSize
    }
    
    var body: some View {
        let font = Font.custom(appState.agentFontName, size: fontSize)
        let attr = MarkdownAttrCache.getOrParse(text)
        Text(attr)
            .font(font)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(.primary)
            .lineSpacing(5)
            .environment(\.openURL, OpenURLAction { url in
                if url.isFileURL || url.scheme == "file" || url.scheme == "microcode-file" {
                    if PreviewDockService.shared.openFileFromReference(url.absoluteString, workspacePath: appState.workspaceFolder?.path) {
                        return .handled
                    }
                    let cleanPath = url.path.isEmpty
                        ? url.absoluteString.replacingOccurrences(of: "file://", with: "").replacingOccurrences(of: "microcode-file://", with: "").removingPercentEncoding ?? ""
                        : url.path
                    if !cleanPath.isEmpty {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MicroCodeOpenFileURL"),
                            object: URL(fileURLWithPath: cleanPath)
                        )
                        return .handled
                    }
                }
                return .systemAction
            })
    }
}

/// Renders heading with proper font size
struct HeadingView: View {
    let level: Int
    let content: String
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Text(MarkdownAttrCache.getOrParse(content))
            .font(.system(size: fontSize, weight: .bold))
            .foregroundColor(.primary)
            .tint(.accentColor)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "file" {
                    let path = url.path
                    if !path.isEmpty {
                        NotificationCenter.default.post(
                            name: Notification.Name("MicroCodeOpenFileURL"),
                            object: URL(fileURLWithPath: path)
                        )
                        return .handled
                    }
                }
                return .systemAction
            })
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, topPadding)
            .padding(.bottom, 4)
    }
    
    private var fontSize: CGFloat {
        let base = appState.agentFontSize
        switch level {
        case 1: return base * 1.5
        case 2: return base * 1.3
        case 3: return base * 1.15
        case 4: return base * 1.05
        default: return base
        }
    }
    
    private var topPadding: CGFloat {
        level <= 2 ? 12 : 6
    }
}

/// Renders a full multi-block Markdown document (.md files like task.md, implement.md, walkthrough.md, README.md) as formatted rich text
struct RenderedMarkdownDocumentView: View, Equatable {
    let markdown: String
    @EnvironmentObject var appState: AppState
    
    static func == (lhs: RenderedMarkdownDocumentView, rhs: RenderedMarkdownDocumentView) -> Bool {
        lhs.markdown == rhs.markdown
    }
    
    var body: some View {
        let blocks = MessageContentParser.parse(markdown)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .thought(let content, let duration):
                    AntigravityThoughtBlockView(content: content, durationSeconds: duration)
                case .text(let text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        MarkdownTextView(text: text)
                    }
                case .code(let lang, let code):
                    let lower = lang.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    if lower == "markdown" || lower == "md" || lower.hasSuffix(".md") {
                        MarkdownTextView(text: code)
                    } else {
                        NativeCodeBlockView(language: lang, code: code)
                    }
                case .heading(let level, let content):
                    HeadingView(level: level, content: content)
                case .list(let items, let isOrdered):
                    ListView(items: items, isOrdered: isOrdered)
                case .table(let headers, let rows):
                    TableBlockView(headers: headers, rows: rows)
                case .blockquote(let content):
                    BlockquoteView(content: content)
                case .latex(let expression, let isBlock):
                    LaTeXBlockView(expression: expression, isBlock: isBlock)
                case .html(let content):
                    HTMLBlockView(content: content)
                case .media(let kind, let title, let target):
                    ChatMediaBlockView(kind: kind, title: title, target: target)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renders ordered/unordered list (with native checkbox support for [ ] and [x])
struct ListView: View {
    let items: [String]
    let isOrdered: Bool
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                let rawItem = items[index]
                let trimmedItem = rawItem.trimmingCharacters(in: .whitespaces)
                if trimmedItem.hasPrefix("[x] ") || trimmedItem.hasPrefix("[X] ") {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.square.fill")
                            .font(.system(size: appState.agentFontSize, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .padding(.top, 2)
                        MarkdownTextView(text: String(trimmedItem.dropFirst(4)))
                    }
                } else if trimmedItem.hasPrefix("[ ] ") {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "square")
                            .font(.system(size: appState.agentFontSize, weight: .regular))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                        MarkdownTextView(text: String(trimmedItem.dropFirst(4)))
                    }
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        Text(isOrdered ? "\(index + 1)." : "•")
                            .font(.system(size: appState.agentFontSize, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: isOrdered ? 24 : 14, alignment: .trailing)
                        
                        MarkdownTextView(text: rawItem)
                    }
                }
            }
        }
        .padding(.leading, 6)
        .padding(.vertical, 2)
    }
}

/// Renders blockquote
struct BlockquoteView: View {
    let content: String
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: 3)
            
            Text(MarkdownAttrCache.getOrParse(content))
                .font(.system(size: appState.agentFontSize))
                .foregroundColor(.secondary)
                .tint(.accentColor)
                .italic()
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "file" {
                        let path = url.path
                        if !path.isEmpty {
                            NotificationCenter.default.post(
                                name: Notification.Name("MicroCodeOpenFileURL"),
                                object: URL(fileURLWithPath: path)
                            )
                            return .handled
                        }
                    }
                    return .systemAction
                })
                .padding(.leading, 12)
                .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renders LaTeX equation natively in SwiftUI without spawning heavy WKWebView child processes (~50MB RAM each)
struct LaTeXBlockView: View {
    let expression: String
    let isBlock: Bool
    @State private var copied = false
    
    private var formattedMath: String {
        Self.prettyFormatLaTeX(expression)
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if isBlock { Spacer(minLength: 8) }
            Text(formattedMath)
                .font(.system(size: isBlock ? 15 : 13.5, weight: .regular, design: .serif))
                .foregroundColor(.primary.opacity(0.92))
                .multilineTextAlignment(isBlock ? .center : .leading)
                .textSelection(.enabled)
                .padding(.vertical, isBlock ? 12 : 6)
                .padding(.horizontal, 14)
            if isBlock { Spacer(minLength: 8) }
        }
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(expression, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .help("Copy LaTeX")
        }
        .cornerRadius(8)
    }
    
    static func prettyFormatLaTeX(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacements: [(String, String)] = [
            ("\\alpha", "α"), ("\\beta", "β"), ("\\gamma", "γ"), ("\\delta", "δ"),
            ("\\epsilon", "ε"), ("\\varepsilon", "ε"), ("\\zeta", "ζ"), ("\\eta", "η"),
            ("\\theta", "θ"), ("\\iota", "ι"), ("\\kappa", "κ"), ("\\lambda", "λ"),
            ("\\mu", "μ"), ("\\nu", "ν"), ("\\xi", "ξ"), ("\\pi", "π"),
            ("\\rho", "ρ"), ("\\sigma", "σ"), ("\\tau", "τ"), ("\\phi", "φ"),
            ("\\varphi", "φ"), ("\\chi", "χ"), ("\\psi", "ψ"), ("\\omega", "ω"),
            ("\\Gamma", "Γ"), ("\\Delta", "Δ"), ("\\Theta", "Θ"), ("\\Lambda", "Λ"),
            ("\\Xi", "Ξ"), ("\\Pi", "Π"), ("\\Sigma", "Σ"), ("\\Phi", "Φ"),
            ("\\Psi", "Ψ"), ("\\Omega", "Ω"),
            ("\\sum", "∑"), ("\\prod", "∏"), ("\\int", "∫"), ("\\partial", "∂"),
            ("\\nabla", "∇"), ("\\infty", "∞"), ("\\approx", "≈"), ("\\neq", "≠"),
            ("\\ne", "≠"), ("\\leq", "≤"), ("\\le", "≤"), ("\\geq", "≥"), ("\\ge", "≥"),
            ("\\times", "×"), ("\\cdot", "·"), ("\\pm", "±"), ("\\mp", "∓"),
            ("\\rightarrow", "→"), ("\\to", "→"), ("\\leftarrow", "←"),
            ("\\Rightarrow", "⇒"), ("\\Leftarrow", "⇐"), ("\\leftrightarrow", "↔"),
            ("\\Leftrightarrow", "⇔"), ("\\forall", "∀"), ("\\exists", "∃"),
            ("\\in", "∈"), ("\\notin", "∉"), ("\\subset", "⊂"), ("\\subseteq", "⊆"),
            ("\\cup", "∪"), ("\\cap", "∩"), ("\\emptyset", "∅"), ("\\sqrt", "√"),
            ("\\left", ""), ("\\right", ""), ("\\,", " "), ("\\;", " "), ("\\quad", "  ")
        ]
        for (k, v) in replacements {
            s = s.replacingOccurrences(of: k, with: v)
        }
        return s
    }
}

/// Renders HTML content or divider
struct HTMLBlockView: View {
    let content: String
    
    var body: some View {
        if content == "<hr/>" || content == "<hr>" || content == "<hr />" {
            Divider()
                .padding(.vertical, 8)
        } else {
            HTMLWebView(content: content)
                .frame(minHeight: 100)
                .frame(maxWidth: .infinity)
                .cornerRadius(6)
        }
    }
}

/// Renders Markdown Table with sleek macOS typography
struct TableBlockView: View {
    let headers: [String]
    let rows: [[String]]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Header Row
                HStack(spacing: 0) {
                    ForEach(headers.indices, id: \.self) { idx in
                        HStack {
                            Text(MarkdownAttrCache.getOrParse(headers[idx]))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minWidth: 110, alignment: .leading)
                        
                        if idx < headers.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(Color.primary.opacity(0.06))
                
                Divider()
                
                // Data Rows
                ForEach(rows.indices, id: \.self) { rowIdx in
                    let row = rows[rowIdx]
                    HStack(spacing: 0) {
                        ForEach(headers.indices, id: \.self) { colIdx in
                            let cellText = colIdx < row.count ? row[colIdx] : ""
                            HStack {
                                MarkdownTextView(text: cellText)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .frame(minWidth: 110, alignment: .leading)
                            
                            if colIdx < headers.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(rowIdx % 2 == 1 ? Color.primary.opacity(0.02) : Color.clear)
                    
                    if rowIdx < rows.count - 1 {
                        Divider().opacity(0.5)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .cornerRadius(6)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - HTML WebView

struct HTMLWebView: NSViewRepresentable {
    let content: String
    
    final class Coordinator {
        var lastContent: String?
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WebEngine.shared.createConfiguration(enableJavaScript: false)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastContent != content else { return }
        context.coordinator.lastContent = content
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
    private static let cacheLock = NSLock()
    private static var tagCache: [Int: String] = [:]
    private static var compiledRegexCache: [String: NSRegularExpression] = [:]
    
    static func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let existing = compiledRegexCache[pattern] {
            return existing
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        compiledRegexCache[pattern] = regex
        return regex
    }
    
    /// Generate a smart tag from code analysis (memoized)
    static func generateTag(from code: String, language: String) -> String {
        var hasher = Hasher()
        hasher.combine(code.count)
        hasher.combine(code.prefix(512))
        hasher.combine(language.lowercased())
        let key = hasher.finalize()
        
        cacheLock.lock()
        if let cached = tagCache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        
        let sample = code.count > 2_000 ? String(code.prefix(2_000)) : code
        let result: String
        // 1. Try to extract function/method name
        if let funcName = extractFunctionName(from: sample, language: language) {
            result = "#\(funcName)"
        } else if let className = extractClassName(from: sample, language: language) {
            // 2. Try to extract class/struct name
            result = "#\(className)"
        } else if let purpose = detectPurpose(from: sample) {
            // 3. Try to detect purpose from comments
            result = "#\(purpose)"
        } else {
            // 4. Fallback to language + line count
            let lineCount = code.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
            let lang = language.isEmpty ? "Code" : language.capitalized
            result = "#\(lang)\(lineCount)L"
        }
        
        cacheLock.lock()
        if tagCache.count > 512 {
            tagCache.removeAll(keepingCapacity: true)
        }
        tagCache[key] = result
        cacheLock.unlock()
        return result
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
        guard let regex = CodeTagGenerator.cachedRegex(pattern) else {
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

// MARK: - Purpose-Built Agent Mode Diff & Code Block (120fps Metal Rasterized, Zero Nested ScrollView)

fileprivate struct AgentParsedDiffBlock {
    struct Line: Identifiable {
        enum Kind {
            case addition
            case deletion
            case hunk
            case fileComment
            case context
        }
        let id: Int
        let lineNum: String
        let symbol: String
        let text: String
        let kind: Kind
    }
    
    let isDiff: Bool
    let title: String
    let additions: Int
    let deletions: Int
    let totalLines: Int
    let lines: [Line]
}

fileprivate final class AgentCodeAndDiffCache {
    private static var diffCache: [Int: AgentParsedDiffBlock] = [:]
    private static let lock = NSLock()
    
    static func parse(language: String, code: String) -> AgentParsedDiffBlock {
        var hasher = Hasher()
        hasher.combine(language.lowercased())
        hasher.combine(code)
        let key = hasher.finalize()
        
        lock.lock()
        if let cached = diffCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        let rawLines = code.components(separatedBy: "\n")
        let lowerLang = language.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        var extractedFile: String? = nil
        var addCount = 0
        var delCount = 0
        var parsedLines: [AgentParsedDiffBlock.Line] = []
        parsedLines.reserveCapacity(min(rawLines.count, 500))
        
        var displayLineNum = 1
        for (idx, rawLine) in rawLines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            
            // Detect leading file comment on line 0/1: e.g. "// index.html", "# app.py", "--- a/index.html", "+++ b/index.html"
            if idx <= 2 && extractedFile == nil {
                if trimmed.hasPrefix("// ") || trimmed.hasPrefix("# ") || trimmed.hasPrefix("/* ") {
                    let candidate = trimmed
                        .replacingOccurrences(of: "//", with: "")
                        .replacingOccurrences(of: "/*", with: "")
                        .replacingOccurrences(of: "*/", with: "")
                        .replacingOccurrences(of: "#", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if candidate.contains(".") && !candidate.contains(" ") && candidate.count <= 80 {
                        extractedFile = candidate
                    }
                } else if trimmed.hasPrefix("+++ b/") || trimmed.hasPrefix("--- a/") {
                    let candidate = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    if !candidate.isEmpty && candidate != "/dev/null" {
                        extractedFile = URL(fileURLWithPath: candidate).lastPathComponent
                    }
                }
            }
            
            if (trimmed.hasPrefix("+++ ") || trimmed.hasPrefix("--- ")) && (trimmed.contains("a/") || trimmed.contains("b/") || trimmed.contains("/dev/null")) {
                continue
            }
            
            if trimmed.hasPrefix("@@") {
                parsedLines.append(.init(id: idx, lineNum: "⋯", symbol: "@@", text: trimmed, kind: .hunk))
            } else if trimmed == "..." || trimmed == "…" {
                parsedLines.append(.init(id: idx, lineNum: "⋯", symbol: "·", text: "⋯", kind: .hunk))
            } else if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                addCount += 1
                let body = String(rawLine.dropFirst())
                parsedLines.append(.init(id: idx, lineNum: "\(displayLineNum)", symbol: "+", text: body, kind: .addition))
                displayLineNum += 1
            } else if rawLine.hasPrefix("-") && !rawLine.hasPrefix("---") {
                delCount += 1
                let body = String(rawLine.dropFirst())
                parsedLines.append(.init(id: idx, lineNum: "\(displayLineNum)", symbol: "−", text: body, kind: .deletion))
            } else if trimmed.hasPrefix("+ ") || (trimmed.hasPrefix("+\t")) {
                addCount += 1
                let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                parsedLines.append(.init(id: idx, lineNum: "\(displayLineNum)", symbol: "+", text: "    " + body, kind: .addition))
                displayLineNum += 1
            } else if trimmed.hasPrefix("- ") || (trimmed.hasPrefix("-\t")) {
                delCount += 1
                let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                parsedLines.append(.init(id: idx, lineNum: "\(displayLineNum)", symbol: "−", text: "    " + body, kind: .deletion))
            } else if idx == 0 && extractedFile != nil && (trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("/*")) {
                parsedLines.append(.init(id: idx, lineNum: "\(displayLineNum)", symbol: " ", text: rawLine, kind: .fileComment))
                displayLineNum += 1
            } else {
                parsedLines.append(.init(id: idx, lineNum: "\(displayLineNum)", symbol: " ", text: rawLine, kind: .context))
                displayLineNum += 1
            }
        }
        
        let isDiffBlock = lowerLang == "diff" || lowerLang == "patch" || (addCount + delCount >= 2 && (addCount > 0 && delCount > 0))
        let resolvedTitle: String = {
            if let file = extractedFile, !file.isEmpty {
                return file
            }
            if isDiffBlock {
                return "Diff Patch"
            }
            return lowerLang.isEmpty ? "Code" : language.uppercased()
        }()
        
        let parsed = AgentParsedDiffBlock(
            isDiff: isDiffBlock,
            title: resolvedTitle,
            additions: addCount,
            deletions: delCount,
            totalLines: rawLines.count,
            lines: parsedLines
        )
        
        lock.lock()
        if diffCache.count > 256 {
            diffCache.removeAll(keepingCapacity: true)
        }
        diffCache[key] = parsed
        lock.unlock()
        return parsed
    }
    
    static func clearAll() {
        lock.lock()
        diffCache.removeAll(keepingCapacity: false)
        lock.unlock()
    }
}

struct NativeCodeBlockView: View, Equatable {
    let language: String
    let code: String
    
    static func == (lhs: NativeCodeBlockView, rhs: NativeCodeBlockView) -> Bool {
        return lhs.language == rhs.language && lhs.code == rhs.code
    }
    
    @State private var isCopied = false
    @State private var isExpanded = false
    
    private let collapsedLineLimit = 22
    
    var body: some View {
        let parsed = AgentCodeAndDiffCache.parse(language: language, code: code)
        VStack(alignment: .leading, spacing: 0) {
            agentHeaderView(parsed: parsed)
            Divider().opacity(0.28)
            if parsed.isDiff {
                agentDiffContentView(parsed: parsed)
            } else {
                agentCodeContentView(parsed: parsed)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.11), lineWidth: 1)
        )
        .padding(.vertical, 6)
    }
    
    // MARK: - Agent Mode Header (No Cell Mode tags or Play buttons)
    
    private func agentHeaderView(parsed: AgentParsedDiffBlock) -> some View {
        let isLong = parsed.totalLines > collapsedLineLimit || code.count > 1_600
        return HStack(spacing: 8) {
            ProgrammingLanguageIconView(
                fileName: parsed.title,
                languageHint: language,
                size: 15
            )
            
            Text(parsed.title)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            if parsed.isDiff {
                HStack(spacing: 4) {
                    if parsed.additions > 0 {
                        Text("+\(parsed.additions)")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.green.opacity(0.14))
                            .cornerRadius(3.5)
                    }
                    if parsed.deletions > 0 {
                        Text("-\(parsed.deletions)")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.red.opacity(0.14))
                            .cornerRadius(3.5)
                    }
                }
            } else if !language.isEmpty && parsed.title.lowercased() != language.lowercased() {
                Text(language.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(3.5)
            }
            
            Text("\(parsed.totalLines) lines")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.75))
            
            Spacer(minLength: 8)
            
            HStack(spacing: 6) {
                if !parsed.isDiff {
                    Button(action: openInEditor) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 9.5))
                            Text("Editor")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Open snippet in Code Editor")
                }
                
                if isLong {
                    Button(action: {
                        isExpanded.toggle()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                            Text(isExpanded ? "Collapse" : "Expand")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: copyCode) {
                    HStack(spacing: 3.5) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5, weight: .medium))
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundColor(isCopied ? .green : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.035))
    }
    
    // MARK: - 120fps Agent Mode Diff Body (Zero Nested ScrollView, Metal Rasterized)
    
    private func agentDiffContentView(parsed: AgentParsedDiffBlock) -> some View {
        let isTruncated = !isExpanded && parsed.lines.count > collapsedLineLimit
        let visibleLines = isTruncated ? Array(parsed.lines.prefix(collapsedLineLimit)) : parsed.lines
        
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(visibleLines) { line in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(diffBarColor(line.kind))
                            .frame(width: 3)
                        
                        Text(line.lineNum)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.45))
                            .frame(width: 32, alignment: .trailing)
                            .padding(.trailing, 6)
                        
                        Text(line.symbol)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(diffSymbolColor(line.kind))
                            .frame(width: 16, alignment: .center)
                        
                        Text(line.text)
                            .font(.custom("Menlo", size: 11.5))
                            .foregroundColor(diffTextColor(line.kind))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.trailing, 10)
                        
                        Spacer(minLength: 0)
                    }
                    .frame(height: 19)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(diffRowBackground(line.kind))
                }
            }
            .padding(.vertical, 4)
            
            if isTruncated {
                Divider().opacity(0.25)
                Button(action: {
                    isExpanded = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Show \(parsed.lines.count - collapsedLineLimit) more diff lines")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.025))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func diffBarColor(_ kind: AgentParsedDiffBlock.Line.Kind) -> Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        case .hunk: return .cyan.opacity(0.7)
        case .fileComment, .context: return .clear
        }
    }
    
    private func diffSymbolColor(_ kind: AgentParsedDiffBlock.Line.Kind) -> Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        case .hunk: return .cyan
        case .fileComment, .context: return .secondary.opacity(0.3)
        }
    }
    
    private func diffTextColor(_ kind: AgentParsedDiffBlock.Line.Kind) -> Color {
        switch kind {
        case .addition: return .primary
        case .deletion: return .primary.opacity(0.78)
        case .hunk: return .secondary
        case .fileComment: return .secondary.opacity(0.85)
        case .context: return .primary.opacity(0.88)
        }
    }
    
    private func diffRowBackground(_ kind: AgentParsedDiffBlock.Line.Kind) -> Color {
        switch kind {
        case .addition: return Color.green.opacity(0.11)
        case .deletion: return Color.red.opacity(0.11)
        case .hunk: return Color.primary.opacity(0.03)
        case .fileComment, .context: return Color.clear
        }
    }
    
    // MARK: - 120fps Agent Mode Standard Code Body (Zero Nested ScrollView)
    
    private func agentCodeContentView(parsed: AgentParsedDiffBlock) -> some View {
        let isLong = parsed.totalLines > collapsedLineLimit || code.count > 1_600
        let isWideSingleLinePayload = code.count > 1_200 && parsed.totalLines <= 2
        
        let displayCode: String = {
            if isExpanded || !isLong {
                return code
            } else if isWideSingleLinePayload {
                return String(code.prefix(1_200)) + "\n…"
            } else {
                return code.components(separatedBy: "\n").prefix(collapsedLineLimit).joined(separator: "\n")
            }
        }()
        
        let highlightedCode: AttributedString = displayCode.count <= 8_000
            ? SyntaxHighlightingEngine.cachedSwiftUIAttributedString(
                displayCode,
                language: language.isEmpty ? "swift" : language,
                fontSize: 11.5,
                isDark: true
            )
            : AttributedString(displayCode)
        
        return VStack(alignment: .leading, spacing: 0) {
            Text(highlightedCode)
                .font(.custom("Menlo", size: 11.5))
                .lineSpacing(3.5)
                .foregroundColor(Color(nsColor: .textColor))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
            
            if isLong && !isExpanded {
                Divider().opacity(0.25)
                Button(action: {
                    isExpanded = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                        Text(isWideSingleLinePayload
                             ? "Show \(max(0, code.count - 1_200)) more characters"
                             : "Show \(max(0, parsed.totalLines - collapsedLineLimit)) more lines")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.025))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func openInEditor() {
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
    
    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            isCopied = false
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.name)
                        .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? .primary : .secondary)
                        .lineLimit(1)
                    
                    Text((chat.messageCount ?? chat.messages.count) == 0 ? "Empty" : "\(chat.messageCount ?? chat.messages.count) messages")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                
                Spacer()
                
                if isHovering {
                    Button(action: onDelete) {
                        Text("Delete")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Color.primary.opacity(0.09) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
            .cornerRadius(4)
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

// MARK: - Antigravity-Style Thinking & Reasoning Block

struct AntigravityThoughtBlockView: View {
    let content: String
    let durationSeconds: Int?
    var isActivelyStreaming: Bool = false
    
    @State private var isExpanded: Bool = false
    @State private var userToggled: Bool = false
    @State private var liveElapsedSeconds: Int = 1
    @State private var liveTimer: Timer? = nil
    
    private var isStreaming: Bool {
        isActivelyStreaming && durationSeconds == nil
    }
    
    private var durationText: String {
        if isStreaming {
            return "Thinking for \(liveElapsedSeconds)s"
        }
        if let d = durationSeconds, d > 0 {
            return "Thought for \(d)s"
        }
        return "Thought for \(max(1, liveElapsedSeconds))s"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // AGY-Style Minimalist Collapsible Thought Header ("Thought for 5s ›")
            Button(action: {
                userToggled = true
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    Text(durationText)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(.secondary.opacity(isStreaming ? 0.88 : 0.78))
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                    
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expanded Thought Body
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanContent.isEmpty && isStreaming {
                        Text("Formulating reasoning steps…")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.75))
                            .padding(.vertical, 2)
                    } else {
                        let visibleContent: String = {
                            guard isStreaming, cleanContent.count > 2200 else { return cleanContent }
                            let tail = String(cleanContent.suffix(2200))
                            if let nl = tail.firstIndex(of: "\n") {
                                return "…\n" + String(tail[tail.index(after: nl)...])
                            }
                            return "…" + tail
                        }()
                        let sections = parseThoughtSections(visibleContent)
                        ForEach(sections) { sec in
                            VStack(alignment: .leading, spacing: 4) {
                                if let title = sec.title, !title.isEmpty {
                                    Text(title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.primary.opacity(0.88))
                                }
                                
                                Text(sec.body)
                                    .font(.system(size: 12, design: .default))
                                    .foregroundColor(.secondary.opacity(0.82))
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 4)
                .overlay(
                    HStack {
                        Rectangle()
                            .fill(Color.primary.opacity(0.14))
                            .frame(width: 1.5)
                        Spacer()
                    }
                )
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
        .onAppear {
            if isStreaming {
                startLiveTimer()
            } else {
                if !userToggled { isExpanded = false }
            }
        }
        .onChange(of: isStreaming) { streaming in
            if streaming {
                startLiveTimer()
            } else {
                liveTimer?.invalidate()
                liveTimer = nil
                if !userToggled {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isExpanded = false
                    }
                }
            }
        }
        .onDisappear {
            liveTimer?.invalidate()
            liveTimer = nil
        }
    }
    
    private func startLiveTimer() {
        liveTimer?.invalidate()
        liveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                self.liveElapsedSeconds += 1
            }
        }
    }
    
    private struct ThoughtSection: Identifiable {
        let id: Int
        let title: String?
        let body: String
    }
    
    private func parseThoughtSections(_ text: String) -> [ThoughtSection] {
        let paragraphs = text.components(separatedBy: "\n\n")
        var result: [ThoughtSection] = []
        var sectionIndex = 0
        
        for para in paragraphs {
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            // Check for markdown bold heading at start: **Title**\nBody or **Title** Body
            if trimmed.hasPrefix("**") {
                let parts = trimmed.components(separatedBy: "**")
                if parts.count >= 3 {
                    let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    let remainingBody = parts.dropFirst(2).joined(separator: "**").trimmingCharacters(in: .whitespacesAndNewlines)
                    result.append(ThoughtSection(id: sectionIndex, title: title, body: remainingBody.isEmpty ? trimmed : remainingBody))
                    sectionIndex += 1
                    continue
                }
            } else if trimmed.hasPrefix("### ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("# ") {
                let lines = trimmed.components(separatedBy: .newlines)
                let title = lines.first?.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
                let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(ThoughtSection(id: sectionIndex, title: title, body: body.isEmpty ? trimmed : body))
                sectionIndex += 1
                continue
            }
            
            result.append(ThoughtSection(id: sectionIndex, title: nil, body: trimmed))
            sectionIndex += 1
        }
        
        return result.isEmpty ? [ThoughtSection(id: 0, title: nil, body: text)] : result
    }
}

// MARK: - Antigravity-Style Live Agent Thinking & Activity Tree

struct AgentThinkingView: View {
    let currentTool: String?
    let phase: AgentPhase
    
    @State private var elapsedSeconds: Int = 1
    @State private var isExpanded: Bool = true
    @State private var dotCount: Int = 1
    @State private var isPulsing: Bool = false
    @State private var rotationAngle: Double = 0
    @State private var elapsedTimer: Timer? = nil
    @State private var dotAnimTimer: Timer? = nil
    
    private var workingText: String {
        let dots = String(repeating: ".", count: dotCount)
        if let tool = currentTool, !tool.isEmpty {
            return "\(tool)\(dots)"
        }
        return "Autonomous agent executing\(dots)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Spinning active gear/ring indicator
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .rotationEffect(.degrees(rotationAngle))
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: rotationAngle)
                
                Text(elapsedSeconds > 0 ? "Agent Working • \(elapsedSeconds)s" : "Agent Working")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary)
                
                // Pulsing live badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                        .opacity(isPulsing ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
                    
                    Text("LIVE")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .cornerRadius(4)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if isExpanded {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                    
                    Text(workingText)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(.leading, 4)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .onAppear {
            isPulsing = true
            rotationAngle = 360
            // Start timers ONLY when this view is actually on screen
            elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in elapsedSeconds += 1 }
            }
            dotAnimTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { _ in
                Task { @MainActor in dotCount = (dotCount % 3) + 1 }
            }
        }
        .onDisappear {
            // Kill timers immediately when view leaves the hierarchy
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            dotAnimTimer?.invalidate()
            dotAnimTimer = nil
        }
    }
}

// MARK: - Antigravity (AGY) Minimalist Agent Action Timeline

struct ToolExecutionStepsView: View {
    let results: [ToolResultModel]
    var isStreaming: Bool = false
    @State private var isExpandedOverride: Bool? = nil
    
    private var isExpanded: Bool {
        isExpandedOverride ?? (isStreaming || results.count <= 4)
    }
    
    private var headerTitle: String {
        if let last = results.last {
            return ToolActivityItemRow.summaryHeadline(for: last)
        }
        return isStreaming ? "Working…" : "Completed \(results.count) step\(results.count == 1 ? "" : "s")"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // AGY-Style Clean Borderless Collapsible Header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpandedOverride = !isExpanded
                }
            }) {
                HStack(spacing: 5) {
                    Text(headerTitle)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.88))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.65))
                    
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(results.enumerated()), id: \.element.toolCallId) { _, result in
                        ToolActivityItemRow(result: result)
                    }
                    
                    if isStreaming {
                        Text("Working…")
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundColor(.secondary.opacity(0.75))
                            .padding(.top, 2)
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ToolActivityItemRow: View {
    let result: ToolResultModel
    @State private var showDetails: Bool = false
    @State private var isHoveringFilePill: Bool = false
    
    enum RowStyle {
        case fileAnalyze(fileName: String, lineRange: String?)
        case fileEdit(verb: String, fileName: String, added: Int, removed: Int)
        case commandRun(summary: String, exitNote: String?)
        case generic(verb: String, detail: String)
    }

    @discardableResult
    private func openTargetFileInPreviewDock(fallbackFileName: String? = nil, lineRangeString: String? = nil) -> Bool {
        let params = AgentToolBox.normalizeToolParams(result.toolParams ?? [:])
        var startLine = (params["StartLine"] as? Int) ?? (params["start_line"] as? Int) ?? (params["startLine"] as? Int)
        var endLine = (params["EndLine"] as? Int) ?? (params["end_line"] as? Int) ?? (params["endLine"] as? Int)
        if startLine == nil, let lr = lineRangeString, let parsed = PreviewDockService.parseLineFragment(lr) {
            startLine = parsed.start
            endLine = parsed.end
        }

        let explicitPath = (params["path"] as? String)
            ?? (params["TargetFile"] as? String)
            ?? (params["AbsolutePath"] as? String)
            ?? (params["file_path"] as? String)
            ?? (params["Path"] as? String)
            ?? ((params["paths"] as? [String])?.first)

        if let explicitPath, !explicitPath.isEmpty {
            if PreviewDockService.shared.openFileFromReference(
                explicitPath,
                defaultStartLine: startLine,
                defaultEndLine: endLine
            ) {
                return true
            }
        }

        // Fallback: try extracting full path from output or resolving fallbackFileName in workspace
        if let range = result.output.range(of: #"/[^\s\n:"']+\.[a-zA-Z0-9]+"#, options: .regularExpression) {
            let candidate = String(result.output[range])
            if PreviewDockService.shared.openFileFromReference(
                candidate,
                defaultStartLine: startLine,
                defaultEndLine: endLine
            ) {
                return true
            }
        }

        if let fallbackFileName, !fallbackFileName.isEmpty {
            return PreviewDockService.shared.openFileFromReference(
                fallbackFileName,
                defaultStartLine: startLine,
                defaultEndLine: endLine
            )
        }
        return false
    }
    
    static func summaryHeadline(for result: ToolResultModel) -> String {
        let params = AgentToolBox.normalizeToolParams(result.toolParams ?? [:])
        let targetFile = (params["path"] as? String) ?? (params["TargetFile"] as? String) ?? (params["AbsolutePath"] as? String) ?? (params["file_path"] as? String)
        let fileName = targetFile.map {
            URL(fileURLWithPath: $0).lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: "{}\"'"))
        }
        
        if let summary = (params["toolSummary"] as? String) ?? (params["description"] as? String), !summary.isEmpty {
            return summary
        }
        switch result.toolName {
        case "file_read", "read_file", "view_file", "multi_file_read":
            return "Analyzed \(fileName ?? "source file")"
        case "file_write", "replace_in_file", "multi_replace_in_file", "write_to_file", "patch_file", "apply_patch":
            return "Edited \(fileName ?? "file")"
        case "shell", "run_command":
            if let cmd = (params["command"] as? String) ?? (params["CommandLine"] as? String) {
                let firstLine = cmd.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? cmd
                return "Ran \(String(firstLine.prefix(64)))"
            }
            return "Ran terminal command"
        case "grep_search", "file_search", "find_symbol":
            let q = (params["query"] as? String) ?? (params["pattern"] as? String) ?? (params["symbol"] as? String) ?? "codebase"
            return "Searched \(String(q.prefix(44)))"
        case "list_directory_tree", "list_dir":
            return "Listed \(fileName ?? "workspace")"
        case "preview_control", "ide_browser":
            let action = (params["action"] as? String) ?? "preview"
            return "Previewed \(action)"
        default:
            return "Executed \(result.toolName.replacingOccurrences(of: "_", with: " "))"
        }
    }
    
    private var rowStyle: RowStyle {
        let preview = result.outputPreview
        let params = AgentToolBox.normalizeToolParams(result.toolParams ?? [:])
        var lineInfo: String? = nil
        
        if let startLine = params["StartLine"] as? Int, let endLine = params["EndLine"] as? Int {
            lineInfo = "#L\(startLine)-\(endLine)"
        } else if let lineMatch = preview.range(of: #"#L\d+(-\d+)?"#, options: .regularExpression) {
            lineInfo = String(preview[lineMatch])
        }
        
        let targetFile = (params["path"] as? String) ?? (params["TargetFile"] as? String) ?? (params["AbsolutePath"] as? String) ?? (params["file_path"] as? String)
        let resolvedFileName = (targetFile != nil ? URL(fileURLWithPath: targetFile!).lastPathComponent : extractFileName(preview))?
            .trimmingCharacters(in: CharacterSet(charactersIn: "{}\"'"))
        
        switch result.toolName {
        case "file_read", "read_file", "view_file":
            let name = resolvedFileName ?? "source file"
            let lines = lineInfo ?? (result.outputLineCount > 1 ? "#L1-\(min(350, result.outputLineCount))" : nil)
            return .fileAnalyze(fileName: name, lineRange: lines)
            
        case "multi_file_read":
            if let paths = params["paths"] as? [String], let first = paths.first {
                let name = URL(fileURLWithPath: first).lastPathComponent
                let countStr = paths.count > 1 ? " (+\(paths.count - 1) more)" : ""
                return .fileAnalyze(fileName: "\(name)\(countStr)", lineRange: nil)
            }
            return .fileAnalyze(fileName: "project files", lineRange: nil)
            
        case "file_write", "replace_in_file", "multi_replace_in_file", "write_to_file", "patch_file", "apply_patch":
            let name = resolvedFileName ?? "file"
            let stats = computeDiffLineStats(params: params, output: preview)
            return .fileEdit(verb: "Edited", fileName: name, added: stats.added, removed: stats.removed)
            
        case "shell", "run_command":
            let summaryText: String = {
                if let summary = (params["toolSummary"] as? String) ?? (params["description"] as? String), !summary.isEmpty {
                    return summary.lowercased()
                }
                if let cmd = (params["command"] as? String) ?? (params["CommandLine"] as? String) {
                    let cleanCmd = cmd.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? cmd
                    return String(cleanCmd.prefix(68))
                }
                return "terminal command"
            }()
            let exitNote: String? = result.success ? nil : "Exited with code 1"
            return .commandRun(summary: summaryText, exitNote: exitNote)
            
        case "preview_control", "ide_browser":
            let action = (params["action"] as? String) ?? "open"
            let target = (params["url"] as? String) ?? (params["path"] as? String) ?? "live preview"
            return .generic(verb: "Previewed", detail: "\(target) (\(action))")
            
        case "device_runtime":
            let action = (params["action"] as? String) ?? "run"
            return .generic(verb: "Device", detail: action)
            
        case "grep_search", "file_search", "find_symbol":
            let query = (params["query"] as? String) ?? (params["pattern"] as? String) ?? (params["symbol"] as? String) ?? extractQuery(preview)
            return .generic(verb: "Searched", detail: String(query.prefix(48)))
            
        case "list_directory_tree", "list_dir":
            let dirName = resolvedFileName ?? "workspace"
            return .generic(verb: "Listed", detail: dirName)
            
        case "create_directory":
            let dirName = resolvedFileName ?? "directory"
            return .generic(verb: "Created", detail: dirName)
            
        case "rename_file":
            let oldName = (params["old_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? resolvedFileName ?? "file"
            let newName = (params["new_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
            let detail = newName != nil ? "\(oldName) → \(newName!)" : oldName
            return .generic(verb: "Renamed", detail: detail)
            
        case "delete_file":
            let name = resolvedFileName ?? "file"
            return .generic(verb: "Deleted", detail: name)
            
        case "git_status":
            return .generic(verb: "Inspected", detail: "git status")
            
        case "git_diff":
            return .generic(verb: "Inspected", detail: "git diff")
            
        default:
            let cleanName = result.toolName.replacingOccurrences(of: "_", with: " ")
            return .generic(verb: "Ran", detail: cleanName)
        }
    }
    
    private func computeDiffLineStats(params: [String: Any], output: String) -> (added: Int, removed: Int) {
        let oldStr = (params["old_str"] as? String)
            ?? (params["Target"] as? String)
            ?? (params["target"] as? String)
            ?? (params["search"] as? String)
            ?? (params["TargetContent"] as? String)
        let newStr = (params["new_str"] as? String)
            ?? (params["Replacement"] as? String)
            ?? (params["replacement"] as? String)
            ?? (params["replace"] as? String)
            ?? (params["ReplacementContent"] as? String)
        
        if let oldStr = oldStr, let newStr = newStr {
            let oldLines = oldStr.isEmpty ? [] : oldStr.components(separatedBy: .newlines)
            let newLines = newStr.isEmpty ? [] : newStr.components(separatedBy: .newlines)
            let oldSet = NSCountedSet(array: oldLines)
            var added = 0
            for line in newLines {
                if oldSet.count(for: line) > 0 {
                    oldSet.remove(line)
                } else {
                    added += 1
                }
            }
            var removed = 0
            for item in oldSet {
                removed += oldSet.count(for: item)
            }
            if added == 0 && removed == 0 && oldStr != newStr {
                return (max(1, newLines.count), max(1, oldLines.count))
            }
            return (added, removed)
        }
        
        if let content = (params["content"] as? String) ?? (params["CodeContent"] as? String) ?? (params["Content"] as? String) {
            let count = max(1, content.components(separatedBy: .newlines).count)
            return (count, 0)
        }
        
        if let match = output.range(of: #"\+(\d+)\s+-(\d+)"#, options: .regularExpression) {
            let sub = String(output[match])
            let nums = sub.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            if nums.count >= 2 {
                return (nums[0], nums[1])
            }
        }
        return (1, 1)
    }
    
    @ViewBuilder
    private func fileTypeBadge(for fileName: String) -> some View {
        ProgrammingLanguageIconView(fileName: fileName, size: 14)
    }
    
    private func extractFileName(_ text: String) -> String? {
        if let range = text.range(of: #"/[^\s\n:{}"']+\.[a-zA-Z0-9]+"#, options: .regularExpression) {
            let path = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)'\"{}"))
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let range = text.range(of: #"/[^\s\n:{}"']+"#, options: .regularExpression) {
            let path = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)'\"{}"))
            let last = URL(fileURLWithPath: path).lastPathComponent
            if !last.isEmpty && last != "/" {
                return last
            }
        }
        return nil
    }
    
    private func extractQuery(_ text: String) -> String {
        if let firstLine = text.components(separatedBy: .newlines).first, !firstLine.isEmpty {
            return String(firstLine.prefix(40))
        }
        return "codebase"
    }
    
    static func extractedScreenshotPaths(from result: ToolResultModel) -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        let output = result.output
        let params = result.toolParams ?? [:]
        let wsRoot = AgentToolBox.shared.workspaceRoot ?? AppState.shared?.workspaceFolder?.path
        
        func recordIfValid(_ rawCandidate: String) {
            var cleaned = rawCandidate.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"'()[]<>.,;"))
            if cleaned.hasPrefix("file://") {
                cleaned = String(cleaned.dropFirst("file://".count))
                cleaned = cleaned.removingPercentEncoding ?? cleaned
            }
            guard !cleaned.isEmpty else { return }
            let lower = cleaned.lowercased()
            guard lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".webp") else { return }
            let resolved: String
            if cleaned.hasPrefix("/") {
                resolved = cleaned
            } else if cleaned.hasPrefix("~") {
                resolved = (cleaned as NSString).expandingTildeInPath
            } else if let ws = wsRoot, !ws.isEmpty {
                resolved = (ws as NSString).appendingPathComponent(cleaned)
            } else {
                return
            }
            guard !seen.contains(resolved), FileManager.default.fileExists(atPath: resolved) else { return }
            seen.insert(resolved)
            found.append(resolved)
        }
        
        // 1. Check explicit [SCREENSHOT_PATH: ...] marker
        if let range = output.range(of: #"\[SCREENSHOT_PATH:\s*([^\]]+)\]"#, options: .regularExpression) {
            let sub = String(output[range])
                .replacingOccurrences(of: "[SCREENSHOT_PATH:", with: "")
                .replacingOccurrences(of: "]", with: "")
            recordIfValid(sub)
        }
        
        // 2. Check snapshot saved to ...
        if let range = output.range(of: #"saved to\s+(/[^\s\(\)\n]+\.(?:png|jpg|jpeg|webp))"#, options: .regularExpression) {
            let sub = String(output[range]).replacingOccurrences(of: "saved to", with: "")
            recordIfValid(sub)
        }
        
        // 3. Check tool parameters (output_path / filePath / path for screenshot actions)
        let actionStr = ((params["action"] as? String) ?? (params["operation"] as? String) ?? "").lowercased()
        if actionStr == "screenshot" || actionStr == "snapshot" || result.toolName == "preview_control" || result.toolName == "ide_browser" {
            if let outParam = (params["output_path"] as? String) ?? (params["filePath"] as? String) ?? (params["path"] as? String) {
                recordIfValid(outParam)
            }
        }
        
        // 4. Check shell commands that generated preview_screenshot.png or similar
        if result.toolName == "shell" || result.toolName == "run_command" {
            let cmd = (params["command"] as? String) ?? (params["CommandLine"] as? String) ?? ""
            let combined = cmd + "\n" + output
            if let regex = try? NSRegularExpression(pattern: #"([/\w\-\._~]*(?:screenshot|snapshot|preview_cap|webapp_cap)[/\w\-\._]*\.(?:png|jpg|jpeg|webp))"#, options: [.caseInsensitive]) {
                let ns = combined as NSString
                for match in regex.matches(in: combined, options: [], range: NSRange(location: 0, length: ns.length)) {
                    recordIfValid(ns.substring(with: match.range))
                }
            }
        }
        
        return found
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                switch rowStyle {
                case .fileAnalyze(let fileName, let lineRange):
                    Text("Analyzed")
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.82))
                    
                    Button(action: {
                        if !openTargetFileInPreviewDock(fallbackFileName: fileName, lineRangeString: lineRange) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showDetails.toggle()
                            }
                        }
                    }) {
                        HStack(spacing: 5) {
                            fileTypeBadge(for: fileName)
                            
                            Text(fileName)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(isHoveringFilePill ? .accentColor : .primary.opacity(0.95))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            if let lines = lineRange {
                                Text(lines)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.secondary.opacity(0.72))
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isHoveringFilePill ? Color.primary.opacity(0.09) : Color.primary.opacity(0.035))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringFilePill = hovering
                    }
                    .help("Click to preview \(fileName) in Right Split Pane")
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDetails.toggle()
                        }
                    }) {
                        Image(systemName: showDetails ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.55))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(showDetails ? "Hide inline snippet" : "Show inline snippet")
                    
                case .fileEdit(let verb, let fileName, let added, let removed):
                    Text(verb)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.82))
                    
                    Button(action: {
                        if !openTargetFileInPreviewDock(fallbackFileName: fileName, lineRangeString: nil) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showDetails.toggle()
                            }
                        }
                    }) {
                        HStack(spacing: 5) {
                            fileTypeBadge(for: fileName)
                            
                            Text(fileName)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(isHoveringFilePill ? .accentColor : .primary.opacity(0.95))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            HStack(spacing: 4) {
                                if added > 0 || removed == 0 {
                                    Text("+\(added)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color(red: 0.25, green: 0.78, blue: 0.38))
                                }
                                if removed > 0 {
                                    Text("-\(removed)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color(red: 0.96, green: 0.33, blue: 0.31))
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isHoveringFilePill ? Color.primary.opacity(0.09) : Color.primary.opacity(0.035))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringFilePill = hovering
                    }
                    .help("Click to preview \(fileName) in Right Split Pane")
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDetails.toggle()
                        }
                    }) {
                        Image(systemName: showDetails ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.55))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(showDetails ? "Hide inline details" : "Show inline details")
                    
                case .commandRun(let summary, let exitNote):
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDetails.toggle()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text("Ran \(summary)")
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundColor(.secondary.opacity(0.82))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            if let exitNote = exitNote {
                                Text("· \(exitNote)")
                                    .font(.system(size: 12.5, weight: .regular))
                                    .foregroundColor(.secondary.opacity(0.75))
                            }
                            
                            Image(systemName: showDetails ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                case .generic(let verb, let detail):
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDetails.toggle()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text("\(verb) \(detail)")
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundColor(.secondary.opacity(0.82))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            Image(systemName: showDetails ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer(minLength: 0)
            }
            
            if showDetails {
                let rawOutput = result.success ? result.output : (result.error ?? result.output)
                let trimmedOutput = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                Text(trimmedOutput.isEmpty ? "(Completed)" : String(trimmedOutput.prefix(1500)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(result.success ? .secondary : .red.opacity(0.85))
                    .lineLimit(16)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.black.opacity(0.22))
                    .cornerRadius(6)
                    .padding(.leading, 12)
            }
        }
    }
}

// MARK: - Sleek Project Workspace Dropdown (Matching media_1787685893773.png)

struct ProjectWorkspaceSelectorMenu: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var agent = AgentService.shared
    @Binding var isPresented: Bool
    @State private var searchText = ""
    
    private var availableProjects: [(name: String, path: String)] {
        var list: [(name: String, path: String)] = []
        var seen = Set<String>()
        
        if let current = appState.workspaceFolder?.path, !current.isEmpty {
            list.append((URL(fileURLWithPath: current).lastPathComponent, current))
            seen.insert(current)
        }
        
        for g in agent.projectGroups {
            if let p = g.projectPath, !p.isEmpty, !seen.contains(p) {
                list.append((g.projectName, p))
                seen.insert(p)
            }
        }
        
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return list
        } else {
            let q = searchText.lowercased()
            return list.filter { $0.name.lowercased().contains(q) || $0.path.lowercased().contains(q) }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 8)
            .padding(.top, 8)
            
            // Projects List
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(availableProjects, id: \.path) { proj in
                        let isSelected = (appState.workspaceFolder?.path == proj.path)
                        Button(action: {
                            selectProject(proj.path)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text(proj.name)
                                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(.primary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isSelected ? Color.primary.opacity(0.08) : Color.clear)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
            }
            .frame(maxHeight: 180)
            
            Divider().padding(.horizontal, 4)
            
            // Actions matching user's screenshot
            VStack(alignment: .leading, spacing: 2) {
                Button(action: openNewProjectPicker) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("New Project")
                            .font(.system(size: 11.5))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                
                Button(action: quickStartAction) {
                    let generated = nextQuickStartFolderInfo()
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                        Text("Quick Start")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(generated.name)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(4)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Auto-generate a new project folder (\(nextQuickStartFolderInfo().name)) and start immediately")
                
                Button(action: noProjectAction) {
                    HStack(spacing: 8) {
                        Image(systemName: "slash.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("No Project")
                            .font(.system(size: 11.5))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .frame(width: 250)
        .background(Color(nsColor: appState.appTheme.panelBackground))
    }
    
    private func quickStartParentDirectory() -> URL {
        let fm = FileManager.default
        let candidatePaths: [String] = [
            appState.workspaceFolder?.path,
            agent.currentWorkspace,
            agent.projectGroups.compactMap(\.projectPath).first
        ].compactMap { $0 }.filter { !$0.isEmpty }
        
        for path in candidatePaths {
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
            let parentPath = parent.path
            if parentPath != "/" && parentPath != "/Volumes" && parentPath != "/Users" && fm.isWritableFile(atPath: parentPath) {
                return parent
            }
        }
        
        let defaultRoot = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("MicroCodeProjects", isDirectory: true)
        try? fm.createDirectory(at: defaultRoot, withIntermediateDirectories: true)
        return defaultRoot
    }
    
    private func nextQuickStartFolderInfo() -> (name: String, url: URL) {
        let parent = quickStartParentDirectory()
        let fm = FileManager.default
        let existingNames = Set(agent.projectGroups.map { $0.projectName.lowercased() })
        
        var index = 1
        while index < 1000 {
            let candidateName = String(format: "QuickStart-%02d", index)
            let candidateURL = parent.appendingPathComponent(candidateName, isDirectory: true)
            if !fm.fileExists(atPath: candidateURL.path) && !existingNames.contains(candidateName.lowercased()) {
                return (candidateName, candidateURL)
            }
            index += 1
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd-HHmmss"
        let fallbackName = "QuickStart-\(formatter.string(from: Date()))"
        return (fallbackName, parent.appendingPathComponent(fallbackName, isDirectory: true))
    }
    
    private func quickStartAction() {
        let info = nextQuickStartFolderInfo()
        do {
            try FileManager.default.createDirectory(at: info.url, withIntermediateDirectories: true)
        } catch {
            print("[QuickStart] Failed to create directory at \(info.url.path): \(error)")
        }
        AppState.recordRecentWorkspace(url: info.url)
        selectProject(info.url.path)
    }
    
    private func selectProject(_ path: String) {
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        Task { @MainActor in
            await appState.openWorkspace(url: url)
            agent.setWorkspace(path)
        }
        isPresented = false
    }
    
    private func openNewProjectPicker() {
        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Project Folder"
            panel.message = "Select an existing folder or create a new project directory"
            
            if panel.runModal() == .OK, let url = panel.url {
                selectProject(url.path)
            }
        }
    }
    
    private func noProjectAction() {
        appState.workspaceFolder = nil
        agent.setWorkspace("")
        isPresented = false
    }
}

// MARK: - SubAgent Selector & Deployment Dropdown Menu

struct SubAgentSelectorMenu: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedType: String
    @Binding var isPresented: Bool
    @ObservedObject private var harness = SubAgentHarness.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Select Agent Mode")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                let activeCount = harness.activeSubagents.filter { $0.state == .running }.count
                if activeCount > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                        Text("\(activeCount) Running")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
                .opacity(0.4)
            
            ScrollView {
                VStack(spacing: 2) {
                    // Main Agent
                    agentOptionRow(
                        type: "main",
                        icon: "bolt.fill",
                        title: "Main Agent",
                        subtitle: "Autonomous orchestrator with multi-agent delegation"
                    )
                    
                    Divider()
                        .opacity(0.3)
                        .padding(.vertical, 4)
                    
                    HStack {
                        Text("👑 CEO & SPECIALIST SQUADS")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.orange.opacity(0.9))
                        Spacer()
                        Button {
                            isPresented = false
                            harness.showSquadBuilderSheet = true
                        } label: {
                            Text("+ Custom Squad")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 2)
                    
                    ForEach(harness.squadPresets) { preset in
                        agentOptionRow(
                            type: "squad:\(preset.id)",
                            icon: preset.icon,
                            title: preset.name,
                            subtitle: preset.subtitle
                        )
                    }
                    
                    Divider()
                        .opacity(0.3)
                        .padding(.vertical, 4)
                    
                    Text("SPECIALIZED SUBAGENTS")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.top, 2)
                        .padding(.bottom, 2)
                    
                    // Built-in & Registered SubAgents
                    ForEach(Array(harness.registeredDefinitions.values.sorted(by: { $0.name < $1.name }))) { def in
                        agentOptionRow(
                            type: def.name,
                            icon: subagentIcon(def.name),
                            title: def.role,
                            subtitle: def.description
                        )
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 330)
            
            Divider()
                .opacity(0.4)
            
            // Bottom Action Controls
            HStack {
                Button(action: {
                    isPresented = false
                    harness.showSquadBuilderSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10))
                        Text("Customize Squad")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                
                Text("•")
                    .foregroundColor(.secondary.opacity(0.4))
                
                Button(action: {
                    isPresented = false
                    harness.showSubAgentMonitor = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10))
                        Text("Monitor HUD")
                            .font(.system(size: 10.5, weight: .regular))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                if !harness.activeSubagents.filter({ $0.state == .running }).isEmpty {
                    Button(action: {
                        harness.killAllSubagents()
                        isPresented = false
                    }) {
                        Text("Kill All")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.red.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.02))
        }
        .frame(width: 300)
        .background(Color(nsColor: appState.appTheme.panelBackground))
    }
    
    @ViewBuilder
    private func agentOptionRow(type: String, icon: String, title: String, subtitle: String) -> some View {
        let isSelected = selectedType == type
        Button(action: {
            selectedType = type
            isPresented = false
        }) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .primary : .secondary.opacity(0.8))
                    .frame(width: 16, height: 16)
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.primary)
                        }
                    }
                    
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary.opacity(0.85))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.primary.opacity(0.07) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func subagentIcon(_ name: String) -> String {
        switch name {
        case "architect": return "square.stack.3d.up"
        case "frontend_engineer": return "macwindow"
        case "backend_engineer": return "server.rack"
        case "bug_hunter": return "wrench.and.screwdriver"
        case "test_runner": return "checkmark.seal"
        case "security_auditor": return "shield"
        default: return "cube"
        }
    }
}

// MARK: - Agent Target Environment Menu (Local vs Remote SSH / Cloud)

struct AgentTargetEnvironmentMenu: View {
    @ObservedObject private var toolBox = AgentToolBox.shared
    @ObservedObject private var remoteManager = RemoteConnectionManager.shared
    @Binding var showingAddServer: Bool
    
    var body: some View {
        Menu {
            // Local Mac
            Button {
                toolBox.executionTarget = .local
            } label: {
                HStack {
                    Label("Local Mac (Native)", systemImage: "desktopcomputer")
                    if toolBox.executionTarget.isLocal {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            Divider()
            
            // Remote Servers Header
            Text("REMOTE SERVERS / CLOUD")
            
            let servers = remoteManager.servers
            if servers.isEmpty {
                Text("No SSH servers configured")
            } else {
                ForEach(servers) { server in
                    Button {
                        toolBox.executionTarget = .remote(server)
                    } label: {
                        HStack {
                            let labelText = "\(server.name) (\(server.username)@\(server.host))"
                            Label(labelText, systemImage: server.provider.icon)
                            if toolBox.executionTarget.remoteServer?.id == server.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // Add/Manage Server
            Button {
                showingAddServer = true
            } label: {
                Label("Add Remote Server...", systemImage: "plus.circle")
            }
        } label: {
            HStack(spacing: 4) {
                if let remote = toolBox.executionTarget.remoteServer {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Image(systemName: remote.provider.icon)
                        .font(.system(size: 9))
                    Text(remote.name)
                        .font(.system(size: 10, weight: .medium))
                } else {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 9))
                    Text("Local")
                        .font(.system(size: 10))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 7))
            }
            .foregroundColor(toolBox.executionTarget.isLocal ? .secondary.opacity(0.85) : .accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(toolBox.executionTarget.isLocal ? Color.clear : Color.accentColor.opacity(0.1))
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Rich Attachment Chip View

struct AttachmentChipView: View {
    let file: AIAttachment
    var onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            // Real Image thumbnail or category icon
            if let image = file.nsImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 24, height: 24)
                    .cornerRadius(4)
                    .clipped()
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 12))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(3)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Remove attachment")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
    
    private var iconName: String {
        switch file.type {
        case .image: return "photo"
        case .pdf: return "doc.text.fill"
        case .text: return "doc.plaintext"
        }
    }
    
    private var iconColor: Color {
        switch file.type {
        case .image: return .cyan
        case .pdf: return .red.opacity(0.85)
        case .text: return .accentColor
        }
    }
    
    private var subtitle: String {
        switch file.type {
        case .image:
            return "Image • \(file.formattedSize)"
        case .pdf:
            let pages = file.pdfPageCount
            return "PDF • \(pages > 0 ? "\(pages) p • " : "")\(file.formattedSize)"
        case .text:
            return "File • \(file.formattedSize)"
        }
    }
}

// MARK: - Inline Generated Media Renderer (Image, Video, Music/Audio)

@MainActor
final class ChatAudioPlayerController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var loadedURL: URL?
    
    func loadIfNeeded(url: URL) {
        guard loadedURL != url else { return }
        stop()
        loadedURL = url
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.delegate = self
            player.prepareToPlay()
            audioPlayer = player
            duration = max(player.duration, 0.1)
        }
    }
    
    func togglePlay(url: URL) {
        loadIfNeeded(url: url)
        guard let player = audioPlayer else {
            NSWorkspace.shared.open(url)
            return
        }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            player.play()
            isPlaying = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, let p = self.audioPlayer else { return }
                    self.currentTime = p.currentTime
                    if !p.isPlaying {
                        self.isPlaying = false
                        self.timer?.invalidate()
                    }
                }
            }
        }
    }
    
    func seek(to time: Double) {
        audioPlayer?.currentTime = time
        currentTime = time
    }
    
    func stop() {
        audioPlayer?.stop()
        isPlaying = false
        currentTime = 0
        timer?.invalidate()
        timer = nil
    }
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.timer?.invalidate()
        }
    }
}

/// Native AppKit `AVPlayerView` wrapper so `.mp4` / `.mov` videos always render their frames and playback controls reliably inside macOS `ScrollView`.
struct NativeAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

struct ChatMediaBlockView: View {
    let kind: GeneratedMediaKind
    let title: String
    let target: String
    
    @StateObject private var audioController = ChatAudioPlayerController()
    @State private var videoPlayer: AVPlayer? = nil
    @State private var copiedFeedback: Bool = false
    
    private var resolvedFileURL: URL? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("file://") {
            let rawPath = String(trimmed.dropFirst("file://".count))
            let decoded = rawPath.removingPercentEncoding ?? rawPath
            return URL(fileURLWithPath: decoded)
        } else if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        } else if let u = URL(string: trimmed), u.isFileURL {
            return u
        }
        return nil
    }
    
    private var loadedNSImage: NSImage? {
        if let fileURL = resolvedFileURL, let img = NSImage(contentsOf: fileURL) {
            return img
        }
        if target.hasPrefix("data:image/"),
           let commaIdx = target.firstIndex(of: ",") {
            let b64 = String(target[target.index(after: commaIdx)...])
            if let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
               let img = NSImage(data: data) {
                return img
            }
        }
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Formal Monochrome Header Bar
            HStack(spacing: 8) {
                Image(systemName: headerIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(badgeLabel)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07))
                    .foregroundColor(.secondary)
                    .cornerRadius(3)
                
                Text(displaySubtitle)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.82))
                    .lineLimit(1)
                
                Spacer(minLength: 12)
                
                HStack(spacing: 10) {
                    if kind == .image, let img = loadedNSImage {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([img])
                            copiedFeedback = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copiedFeedback = false
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                                Text(copiedFeedback ? "Copied" : "Copy")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if let fileURL = resolvedFileURL {
                        Button {
                            saveMediaAs(from: fileURL)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "square.and.arrow.down")
                                Text("Save As")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "folder")
                                Text("Finder")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            NSWorkspace.shared.open(fileURL)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Open")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.primary.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))
            
            Divider().opacity(0.25)
            
            // Media Content Body
            Group {
                switch kind {
                case .image:
                    imageBody
                case .video:
                    videoBody
                case .audio:
                    audioBody
                }
            }
            .padding(10)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .padding(.vertical, 4)
        .onDisappear {
            audioController.stop()
            videoPlayer?.pause()
        }
    }
    
    @ViewBuilder
    private var imageBody: some View {
        if let nsImage = loadedNSImage {
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 500, maxHeight: 400)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .onTapGesture {
                        if let fileURL = resolvedFileURL {
                            NSWorkspace.shared.open(fileURL)
                        }
                    }
                
                HStack(spacing: 8) {
                    Text("\(Int(nsImage.size.width)) × \(Int(nsImage.size.height)) px")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    if let fileURL = resolvedFileURL {
                        Text("· \(fileURL.lastPathComponent)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
                Text(resolvedFileURL?.lastPathComponent ?? target)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }
    
    @ViewBuilder
    private var videoBody: some View {
        if let fileURL = resolvedFileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            VStack(alignment: .leading, spacing: 8) {
                if let player = videoPlayer {
                    NativeAVPlayerView(player: player)
                        .frame(width: 500, height: 282)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 500, height: 282)
                        .overlay(
                            ProgressView()
                                .controlSize(.small)
                        )
                }
                
                HStack(spacing: 12) {
                    Button {
                        if let player = videoPlayer {
                            if player.rate == 0 {
                                player.seek(to: .zero)
                                player.play()
                            } else {
                                player.pause()
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9.5))
                            Text("Play / Replay")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundColor(.primary.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Color.primary.opacity(0.07))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    Text("1280 × 720 px · H.264 MP4 · \(fileURL.lastPathComponent)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .onAppear {
                if videoPlayer == nil {
                    let player = AVPlayer(url: fileURL)
                    videoPlayer = player
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "film")
                    .foregroundColor(.secondary)
                Text(resolvedFileURL?.lastPathComponent ?? target)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }
    
    @ViewBuilder
    private var audioBody: some View {
        if let fileURL = resolvedFileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button {
                        audioController.togglePlay(url: fileURL)
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.08))
                                .frame(width: 34, height: 34)
                            Image(systemName: audioController.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fileURL.lastPathComponent)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.9))
                            .lineLimit(1)
                        
                        Slider(
                            value: Binding(
                                get: { audioController.currentTime },
                                set: { audioController.seek(to: $0) }
                            ),
                            in: 0...max(audioController.duration, 1.0)
                        )
                        .tint(.primary)
                        
                        HStack {
                            Text(formatTime(audioController.currentTime))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatTime(audioController.duration))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onAppear {
                    audioController.loadIfNeeded(url: fileURL)
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundColor(.secondary)
                Text(resolvedFileURL?.lastPathComponent ?? target)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }
    
    private var headerIcon: String {
        switch kind {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        }
    }
    
    private var badgeLabel: String {
        switch kind {
        case .image: return "IMAGE"
        case .video: return "VIDEO"
        case .audio: return "AUDIO"
        }
    }
    
    private var displaySubtitle: String {
        if title.contains("·") {
            let parts = title.components(separatedBy: "·")
            if let modelPart = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines), !modelPart.isEmpty {
                return modelPart
            }
        }
        if let fileURL = resolvedFileURL {
            return fileURL.lastPathComponent
        }
        return title
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func saveMediaAs(from sourceURL: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let destURL = panel.url {
            try? FileManager.default.removeItem(at: destURL)
            try? FileManager.default.copyItem(at: sourceURL, to: destURL)
        }
    }
}

private final class ClosureMenuActionHandler: NSObject {
    static let shared = ClosureMenuActionHandler()
    @objc func performMenuAction(_ sender: NSMenuItem) {
        if let action = sender.representedObject as? () -> Void {
            action()
        }
    }
}
