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
    @AppStorage("microcode_preview_dock_width") private var previewDockWidth: Double = 460
    @AppStorage("microcode_plan_panel_width") private var planPanelWidth: Double = 400
    @AppStorage("agentChatSidebarWidth") private var chatSidebarWidth: Double = 210
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
                return preset.name.replacingOccurrences(of: "CEO ", with: "")
            }
            return "Agent Team"
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
        if currentKeyMode == "subscription" {
            return .subscription
        }
        if appState.aiProvider == "omni" && appState.aiModel.lowercased().hasPrefix("omni") {
            return .cloud
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
        let detected = StreamableAIProvider.detect(from: appState.aiModel).rawValue
        if appState.aiProvider.isEmpty || appState.aiProvider == "omni" {
            return detected != "omni" ? detected : "microcode"
        }
        return appState.aiProvider
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
        } else {
            let modelDef = AIModelCatalog.shared.model(id: appState.aiModel)
            let fallbackName = AIModelCatalog.shared.provider(appState.aiProvider)?.models.first?.name
            let resolvedModelName = modelDef?.name ?? (appState.aiModel.isEmpty ? fallbackName : nil)
            return AIModelCatalog.formatFullDisplayName(
                provider: appState.aiProvider,
                modelId: appState.aiModel,
                modelName: resolvedModelName
            )
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
            let sidebarW: CGFloat = (allowsChatSidebar && agent.showChatSidebar) ? min(380, max(160, CGFloat(chatSidebarWidth))) : 0
            let minDockW: CGFloat = 220
            let availAfterSidebar: CGFloat = max(480, rootGeo.size.width - sidebarW)
            let maxAllowedDockW: CGFloat = max(minDockW + 40, availAfterSidebar - 220)
            let normalDockW: CGFloat = min(maxAllowedDockW, max(minDockW, CGFloat(previewDockWidth)))
            let targetDockW: CGFloat = {
                guard previewDock.isExpandedWidth else { return normalDockW }
                if normalDockW < maxAllowedDockW * 0.78 {
                    return min(maxAllowedDockW, max(normalDockW + 160, availAfterSidebar * 0.68))
                } else {
                    return min(maxAllowedDockW, max(minDockW, availAfterSidebar * 0.38))
                }
            }()
            let dockW: CGFloat = hasEmbeddedDock ? (targetDockW + 6) : (hasRightInspector ? 320 : 0)
            let mainColumnAvailWidth = rootGeo.size.width - sidebarW - dockW
            // Auto-promote Plan to full main column when available width cannot comfortably fit Chat (min 420) + Plan (min 400) side-by-side
            let shouldShowPlanFullColumn = isPlanActive && (
                isPlanFullscreen ||
                mainColumnAvailWidth < 820
            )
            
            HStack(spacing: 0) {
                // Chat Sidebar (Collapsible & Resizable)
                if allowsChatSidebar && agent.showChatSidebar {
                    chatSidebar
                        .frame(width: sidebarW)
                        .clipped()
                    
                    NativePaneResizeSplitter(
                        edge: .leadingPane,
                        width: $chatSidebarWidth,
                        currentEffectiveWidth: Double(sidebarW),
                        minWidth: 160,
                        maxWidth: 380,
                        visualWidth: 6,
                        showsGripPill: true,
                        collapseThreshold: 95,
                        onCollapse: {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                agent.showChatSidebar = false
                            }
                        },
                        onDoubleClick: {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                chatSidebarWidth = 210
                            }
                        }
                    )
                    .frame(width: 6)
                    .zIndex(25)
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
                            .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            
                            // Right Pane: Implementation Plan Side Panel (Side-by-Side Resizable Split View)
                            if isPlanActive {
                                let maxPlanW = max(280, min(680, mainColumnAvailWidth - 260))
                                let targetPlanW = min(maxPlanW, max(260, CGFloat(planPanelWidth)))
                                NativePaneResizeSplitter(
                                    edge: .trailingPane,
                                    width: $planPanelWidth,
                                    currentEffectiveWidth: Double(targetPlanW),
                                    minWidth: 260,
                                    maxWidth: Double(maxPlanW),
                                    visualWidth: 6,
                                    showsGripPill: true,
                                    onDoubleClick: {
                                        withAnimation(.easeInOut(duration: 0.16)) {
                                            planPanelWidth = 400
                                        }
                                    }
                                )
                                .frame(width: 6)
                                .zIndex(28)

                                planSidePanelView
                                    .frame(width: targetPlanW)
                                    .frame(maxHeight: .infinity)
                                    .clipped()
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    }
                }
                .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                // Preview is a workspace surface, not a success toast from the
                // capture transport.  Keep it visible while an AVD is connecting
                // (and if a transport needs to retry) so one click always gives
                // the user immediate feedback beside Chat.
                if hasEmbeddedDock {
                    // Native AppKit 120Hz Draggable Split Divider (side-by-side Code & Device Preview Pane)
                    NativePaneResizeSplitter(
                        edge: .trailingPane,
                        width: $previewDockWidth,
                        currentEffectiveWidth: Double(targetDockW),
                        minWidth: Double(minDockW),
                        maxWidth: Double(maxAllowedDockW),
                        visualWidth: 6,
                        showsGripPill: true,
                        collapseThreshold: 120,
                        onDragStarted: {
                            if previewDock.isExpandedWidth {
                                previewDockWidth = Double(targetDockW)
                                previewDock.isExpandedWidth = false
                            }
                        },
                        onCollapse: {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                appState.hidePreviewInspector()
                                previewDock.hideDock()
                            }
                        },
                        onDoubleClick: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                previewDock.isExpandedWidth.toggle()
                            }
                        }
                    )
                    .frame(width: 6)
                    .zIndex(30)

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
            DispatchQueue.main.async {
                agent.activateScope(
                    sessionScope,
                    preferredWorkspace: workspace,
                    restorePersistedWorkspace: restoresPersistedScopeWorkspace
                )
            }
            if sessionScope == .editor {
                Task.detached(priority: .background) {
                    try? await Task.sleep(nanoseconds: 4_500_000_000)
                    await deviceRuntime.refresh(workspace: await MainActor.run { appState.workspaceFolder })
                }
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
            .frame(height: 30)
            
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
                                case 7: return "PNS 24/7"
                                default: break
                                }
                            }
                            return "More"
                        }()

                        Menu {
                            Section("PNS 24/7 Autonomous Nervous System") {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isTaskMode = true; activeTaskTab = 7
                                        isPlanMode = false; planManager.isPlanVisible = false
                                        isPaperMode = false; isCellMode = false; isWalkthroughMode = false; isPlanFullscreen = false
                                    }
                                } label: {
                                    Label("PNS 24/7 Neural System Console (pnsd)", systemImage: "point.3.connected.trianglepath.dotted")
                                }
                            }

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
                                .foregroundColor(MultiPlatformRulesEngine.shared.discoveredRules.isEmpty ? .secondary : .primary.opacity(0.8))
                                .frame(width: 20, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help("Platform Rules & Interop (Cursor, Zed, Cline, GLM)")
                        
                        Button(action: {
                            showingAgentConnections = true
                        }) {
                            Image(systemName: "link.badge.plus")
                                .font(.system(size: 11))
                                .foregroundColor(acpHost.registeredConfigs.isEmpty ? .secondary : .primary.opacity(0.8))
                                .frame(width: 20, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help("Agent Connections Hub (Workser-style: Claude, AGY, OpenCode, Codex)")
                        
                        if let activeAgent = activeExternalAgentConfig {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.primary.opacity(0.75))
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
                .frame(height: 30)
            }
            .frame(height: 30)
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
        .frame(height: 30)
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
                        } else if activeTaskTab == 7 {
                            taskEditorTab("PNS 24/7", icon: "point.3.connected.trianglepath.dotted", idx: 7)
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
            } else if activeTaskTab == 7 {
                // PNS — Pseudo Neural System 24/7 Console
                PNSNeuralDashboardView()
                    .environmentObject(appState)
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
        let taskURL = WorkspaceStoragePaths.readableWorkspaceOrStateFile(named: "task.md", workspacePath: workspace)
        let agentURL = WorkspaceStoragePaths.readableWorkspaceOrStateFile(named: "agent.md", workspacePath: workspace)
        let walkthroughURL = WorkspaceStoragePaths.readableWorkspaceOrStateFile(named: "walkthrough.md", workspacePath: workspace)
        
        taskMdText = (try? String(contentsOf: taskURL, encoding: .utf8)) ?? AgentService.defaultTaskMarkdown()
        agentMdText = (try? String(contentsOf: agentURL, encoding: .utf8)) ?? AgentService.defaultAgentMarkdown()
        walkthroughMdText = (try? String(contentsOf: walkthroughURL, encoding: .utf8)) ?? "# Walkthrough\n\n## Changes\n- Verified implementation\n\n## Verification\n- Tests passing\n\n## Privacy Audit\n- [x] Zero API keys or secrets detected in artifacts\n"
    }
    
    private func saveTaskFiles() {
        guard let workspace = appState.workspaceFolder?.path else { return }
        let taskURL = WorkspaceStoragePaths.managedStateFile(named: "task.md", workspacePath: workspace)
        let agentURL = WorkspaceStoragePaths.managedStateFile(named: "agent.md", workspacePath: workspace)
        let walkthroughURL = WorkspaceStoragePaths.managedStateFile(named: "walkthrough.md", workspacePath: workspace)
        
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
            .foregroundColor(hasActiveGuard ? .primary : .secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(hasActiveGuard ? Color.primary.opacity(0.09) : Color.primary.opacity(0.04))
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
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
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
                .background(Color.primary.opacity(0.04))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.8)
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
                case .pns:
                    let arg = parsed.argument.trimmingCharacters(in: .whitespacesAndNewlines)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTaskMode = true
                        activeTaskTab = 7
                        isPlanMode = false
                        planManager.isPlanVisible = false
                        isPaperMode = false
                        isCellMode = false
                        isWalkthroughMode = false
                    }
                    if !arg.isEmpty {
                        let ws = appState.workspaceFolder?.path ?? agent.currentWorkspace ?? FileManager.default.currentDirectoryPath
                        Task { @MainActor in
                            _ = await PNSOrchestrator.shared.dispatchMarathonMission(
                                objective: arg,
                                workspacePath: ws,
                                branchPolicy: .isolatedWorktreeBranch,
                                verificationCommand: nil,
                                preferOutOfProcessDaemon: true
                            )
                        }
                    }
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
            content: "**Agent Team (`\(preset.name)`)** — Decomposing objective and assigning file-scoped contracts...",
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
            targetConfig = CellAISelection.resolveACPConfig(forEngineId: appState.aiProvider)
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
                    if agyModels.contains(appState.aiModel) {
                        return appState.aiModel
                    }
                    if !appState.aiModel.isEmpty {
                        return ACPAgentSession.normalizeAGYModel(appState.aiModel)
                    }
                    return agyModels.first ?? "gemini-4-argon-high"
                case .openCode:
                    let isAuthed = LocalEcosystemDiscovery.shared.engines.first(where: { $0.id == "opencode" })?.isAuthenticated ?? false
                    let openCodeModels = LocalEcosystemDiscovery.shared.models(for: "opencode").map(\.id)
                    return ACPAgentSession.resolveOpenCodeModel(
                        appState.aiModel,
                        discoveredModels: openCodeModels,
                        isAuthenticated: isAuthed
                    )
                case .codexEngine:
                    let codexModels = LocalEcosystemDiscovery.shared.models(for: "codex").map(\.id)
                    return codexModels.contains(appState.aiModel) ? appState.aiModel : codexModels.first
                case .claudeCode:
                    let claudeModels = LocalEcosystemDiscovery.shared.models(for: "claude_code").map(\.id)
                    return claudeModels.contains(appState.aiModel) ? appState.aiModel : (claudeModels.first ?? "sonnet")
                case .geminiCLI:
                    let current = appState.aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
                    let lower = current.lowercased()
                    if !current.isEmpty && (lower.hasPrefix("gemini") || lower.hasPrefix("gemma")) {
                        return current
                    }
                    return LocalEcosystemDiscovery.shared.models(for: "gemini_cli").first?.id ?? "gemini-2.5-pro"
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
            appState.reloadFileFromDisk(path: change.filePath, forceOverwriteUnsaved: true)
            
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
                appState.reloadFileFromDisk(path: change.filePath, forceOverwriteUnsaved: true)
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
        Task { await AIModelCatalog.shared.refreshIfNeeded(force: false) }
        let rootMenu = NSMenu(title: "Select AI Model")
        rootMenu.autoenablesItems = false
        
        // 1. Subscription (OAuth Accounts)
        let subMenu = NSMenu(title: "Subscription")
        subMenu.autoenablesItems = false
        let connected = SubscriptionAuthManager.shared.connectedProviders()
        let connectedSet = Set(connected)
        let unconnected = SubscriptionProviderType.allCases.filter { !connectedSet.contains($0) }
        let orderedProviders = connected + unconnected
        var addedSeparatorForUnconnected = false
        for prov in orderedProviders {
            let isConnected = connectedSet.contains(prov)
            if !isConnected && !connected.isEmpty && !addedSeparatorForUnconnected {
                subMenu.addItem(.separator())
                addedSeparatorForUnconnected = true
            }
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
                for subModel in prov.modelInfos.prefix(100) {
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
                    UserDefaults.standard.set("subscription", forKey: "aiKeyMode")
                    appState.settingsSelectedTab = 2
                    appState.showingSettingsDialog = true
                })
            }
            subMenu.addItem(makeSubmenuItem("\(prov.displayName)\(isConnected ? " (Active)" : "")", brandKey: prov.rawValue, submenu: provMenu))
        }
        subMenu.addItem(.separator())
        subMenu.addItem(makeActionMenuItem("Manage Subscriptions in Settings...", systemImage: "gearshape") {
            UserDefaults.standard.set("subscription", forKey: "aiKeyMode")
            appState.settingsSelectedTab = 2
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
            let displayedModels = Array(prov.models.prefix(100))
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
        for engine in LocalEcosystemDiscovery.shared.engines where engine.id != "zed" || engine.isInstalled {
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
        
        // 5. Dotmini Sovereign AI (Strictly Dotmini's own Omni O1X models — never claim third-party models)
        let cloudMenu = NSMenu(title: "Dotmini Sovereign AI")
        cloudMenu.autoenablesItems = false
        if let omni = AIModelCatalog.shared.provider("omni") {
            let omniModels = omni.models.filter { $0.id.lowercased().hasPrefix("omni") }
            for m in omniModels {
                let isChecked = (currentExecutionMode == .cloud && appState.aiModel == m.id)
                cloudMenu.addItem(makeActionMenuItem(m.name, brandKey: "microcode", checked: isChecked) {
                    switchToNativeMode(mode: "cloud")
                    setModel("omni", m.id)
                })
            }
        }
        rootMenu.addItem(makeSubmenuItem(
            "Dotmini Sovereign AI (Omni O1X)",
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
                await LocalEcosystemDiscovery.shared.refresh(force: true)
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
            return id.contains("typhoon") || id.contains("qwen") || id.contains("unsloth") || id.contains("nvfp4") || id.contains("llama") || id.contains("codegeex") || id.contains("glm")
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
    
    // MARK: - TokenMem v3 Telemetry & Mode Menu
    
    private var tokenStatsBadge: some View {
        Menu {
            let stats = tokenOptimizer.stats
            Text("TOKENMEM V3 ENGINE — \(stats.formattedSavings.uppercased())")
            if !stats.activeModel.isEmpty {
                Text("Active Model: \(stats.activeProvider)/\(stats.activeModel)")
            }
            Divider()
            
            Section("Optimization Mode") {
                ForEach(TokenMemMode.allCases) { modeItem in
                    Button {
                        tokenOptimizer.mode = modeItem
                    } label: {
                        HStack {
                            Text("\(modeItem.rawValue) — \(modeItem.subtitle)")
                            if tokenOptimizer.mode == modeItem {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            Section("Session Token Telemetry") {
                Text("Net Input: \(formatTokenCount(stats.inputTokens)) tokens")
                Text("Output: \(formatTokenCount(stats.outputTokens)) tokens")
                Text("Saved (Pruned/Folded): \(formatTokenCount(stats.savedTokens)) tokens")
                Text("KV-Prefix Cached: \(formatTokenCount(stats.cachedTokens)) tokens (\(stats.cacheHits) hits / \(stats.cacheMisses) misses)")
                Text("Requests: \(stats.totalRequests) · Est. Cost: $\(String(format: "%.4f", stats.totalCost))")
            }
            
            Divider()
            
            Section("6-Layer TokenMem Breakdown") {
                Text("L1 Tool Schema Dedup: \(formatTokenCount(stats.savedBySchemaDedup)) saved")
                Text("L2 KV-Prefix Cache Hits: \(formatTokenCount(stats.cachedTokens)) cached")
                Text("L3 Epoch History Compaction: \(formatTokenCount(stats.savedByEpochCompaction)) saved")
                Text("L4 File-Read Dedup: \(formatTokenCount(stats.savedByFileReadDedup)) saved")
                Text("L5 AST & Tool Folding: \(formatTokenCount(stats.savedByToolFolding)) saved")
                let memStats = AgentMemoryService.shared
                Text("L6 Semantic Memory: \(memStats.memories.count) entries · \(memStats.topicClusters.count) topics · \(memStats.summaries.count) summaries")
            }
            
            Divider()
            
            Button("Reset TokenMem Telemetry") {
                TokenOptimizer.shared.resetStats()
            }
            Button("Clear Semantic Memory") {
                AgentMemoryService.shared.clearAllMemories()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "memorychip")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.primary.opacity(0.8))
                
                let stats = tokenOptimizer.stats
                if stats.savedTokens > 0 || stats.cachedTokens > 0 {
                    Text("TokenMem \(stats.formattedSavings)")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.85))
                } else {
                    Text("TokenMem · \(tokenOptimizer.mode.rawValue)")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            )
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("TokenMem v3 Engine — \(TokenOptimizer.shared.stats.formattedSavings)")
    }
    
    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}

