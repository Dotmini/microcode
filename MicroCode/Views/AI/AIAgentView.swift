//
//  AIAgentView.swift
//  MicroCode
//
//  Redesigned by MicroCode AI - Professional Edition + Rich Content
//  Industrial/IDE aesthetic. Markdown & Code Block Support.
//

import SwiftUI
import Combine
import MicroCodeSupport
import AppKit
import WebKit
import UniformTypeIdentifiers
import PDFKit

// MARK: - AI Agent View (Professional)

struct AIAgentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var agent = AgentService.shared
    @StateObject private var modelCatalog = AIModelCatalog.shared
    @StateObject private var tokenOptimizer = TokenOptimizer.shared
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
    @State private var collapsedProjectsInChatSidebar: Set<String> = []
    @FocusState private var isInputFocused: Bool
    
    private var selectedSubAgentDisplayName: String {
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
        
        var badgeTitle: String {
            switch self {
            case .acp: return "ACP"
            case .cloud: return "Dotmini Cloud"
            case .byok: return "BYOK"
            case .subscription: return "Subscription"
            }
        }
        
        var icon: String {
            switch self {
            case .acp: return "terminal.fill"
            case .cloud: return "cloud.fill"
            case .byok: return "key.fill"
            case .subscription: return "sparkles.rectangle.stack"
            }
        }
        
        var badgeColor: Color {
            switch self {
            case .acp: return .teal
            case .cloud: return .purple
            case .byok: return .blue
            case .subscription: return .orange
            }
        }
    }
    
    private var currentExecutionMode: AIExecutionMode {
        if activeExternalAgentConfig != nil {
            return .acp
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
        case .claudeCode: return .blue
        case .openCode: return .orange
        case .zedEngine: return .cyan
        case .aider: return .yellow
        case .custom: return .accentColor
        }
    }
    
    private func activeAgentShortName(for config: ACPAgentConfig) -> String {
        switch config.type {
        case .agy: return "Antigravity"
        case .codexEngine: return "Codex"
        case .claudeCode: return "Claude Code"
        case .openCode: return "OpenCode"
        case .zedEngine: return "Zed"
        case .aider: return "Aider"
        case .custom: return config.name
        }
    }
    
    private var currentModelDisplayName: String {
        if let activeAgent = activeExternalAgentConfig {
            let engineId: String
            switch activeAgent.type {
            case .agy: engineId = "agy"
            case .codexEngine: engineId = "codex"
            case .claudeCode: engineId = "claude_code"
            case .openCode: engineId = "opencode"
            case .zedEngine: engineId = "zed"
            case .aider: engineId = "aider"
            case .custom: engineId = "custom"
            }
            let engineModels = LocalEcosystemDiscovery.shared.models(for: engineId)
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
        }
        
        if currentKeyMode == "subscription" {
            let activeSub = UserDefaults.standard.string(forKey: "subscriptionActiveProvider")
            let provType = activeSub.flatMap { SubscriptionProviderType(rawValue: $0) }
            if let info = SubscriptionAuthManager.shared.findModel(id: appState.aiModel, provider: provType) {
                return info.name
            }
            if let info = SubscriptionAuthManager.shared.findModel(id: appState.aiModel) {
                return info.name
            }
            return appState.aiModel.isEmpty ? "Select Model" : AIModelCatalog.formatModelName(appState.aiModel)
        } else if currentKeyMode == "direct" || currentExecutionMode == .byok {
            if let modelDef = AIModelCatalog.shared.model(id: appState.aiModel) {
                return modelDef.name
            }
            return appState.aiModel.isEmpty ? "Gemini 3.7 Flash" : AIModelCatalog.formatModelName(appState.aiModel)
        } else {
            if let modelDef = AIModelCatalog.shared.model(id: appState.aiModel) {
                return modelDef.name
            }
            return appState.aiModel.isEmpty ? "Omni O1X Pro" : AIModelCatalog.formatModelName(appState.aiModel)
        }
    }
    
    // Aesthetic Constants
    private let borderColor = Color.white.opacity(0.1)
    private var paneColor: Color { Color(nsColor: appState.appTheme.panelBackground) }
    private let accentColor = Color.accentColor
    
    var body: some View {
        HStack(spacing: 0) {
            // Chat Sidebar (Collapsible)
            if allowsChatSidebar && agent.showChatSidebar {
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
                if isPlanMode {
                    // Implementation Plan View
                    planView
                } else if isTaskMode {
                    // Task.md / Agent.md Editor
                    taskEditorView
                } else if isWalkthroughMode {
                    // Antigravity-style Interactive Walkthrough
                    walkthroughView
                } else if isPaperMode {
                    // A4 Paper Reading Mode
                    A4PaperView(
                        messages: agent.messages,
                        currentPage: $currentPaperPage
                    )
                } else if isCellMode {
                    // Cell Mode (Notebook-style AI Agent)
                    AgentCellModeView()
                        .environmentObject(appState)
                        .transition(.opacity)
                } else {
                    // Normal Chat Mode
                    if agent.messages.isEmpty && !agent.isLoading {
                        // Centered Empty State (Matching media_1787685889495.png)
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
                                
                                // Clean Floating Input Box
                                inputCardView
                            }
                            // The composer is deliberately wider than a
                            // single response, but it must remain a fluid
                            // surface: grow on a roomy window and shrink with
                            // the active split (preview / inspector) without
                            // ever overflowing it.
                            .frame(maxWidth: 880)
                            .padding(.horizontal, 20)
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Active Chat Mode (Messages on top, Input docked cleanly at bottom)
                        VStack(spacing: 0) {
                            // Chat Scroll
                            AgentChatStage(
                                messages: agent.messages,
                                isLoading: agent.isLoading,
                                domain: agent.domain,
                                currentToolExecution: agent.currentToolExecution,
                                onApplyChange: { change in applyChange(change) },
                                onRejectChange: { change in rejectChange(change) },
                                onSuggestionTap: { suggestion in inputText = suggestion; sendMessage() }
                            )
                            
                            // Suggested Action (after completion)
                            if let suggestion = agent.suggestedAction {
                                suggestedActionBar(suggestion)
                            }
                            
                            // Context Limit Banner (warn user and prompt for new conversation)
                            if agent.contextLimitReached {
                                contextLimitBanner
                            }
                            
                            // Input Container (Docked at bottom)
                            inputArea
                        }
                    }
                }
            }

            // Preview is a workspace surface, not a success toast from the
            // capture transport.  Keep it visible while an AVD is connecting
            // (and if a transport needs to retry) so one click always gives
            // the user immediate feedback beside Chat.
            if sessionScope == .editor && (deviceRuntime.showingEmbeddedDeviceDock || previewDock.isDockVisible) && !appState.agenticContextVisible {
                Divider()
                embeddedDeviceDock
                    .frame(minWidth: 380, idealWidth: 460, maxWidth: 560)
            }
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
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCode.OpenAgentConnections"))) { _ in
            showingAgentConnections = true
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
                Button(action: { _ = agent.createNewChat(projectPath: agent.currentWorkspace ?? scopedWorkspacePath) }) {
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
                    if collapsedProjectsInChatSidebar.contains(group.id) {
                        collapsedProjectsInChatSidebar.remove(group.id)
                    } else {
                        collapsedProjectsInChatSidebar.insert(group.id)
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
        return !collapsedProjectsInChatSidebar.contains(group.id)
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let isCompact = geo.size.width < 320
                
                HStack(spacing: 10) {
                    // Sidebar Toggle
                    if allowsChatSidebar {
                        Button(action: { agent.showChatSidebar.toggle() }) {
                            Text("History")
                                .font(.system(size: 10, weight: agent.showChatSidebar ? .semibold : .regular))
                                .foregroundColor(agent.showChatSidebar ? .primary : .secondary)
                                .frame(height: 26)
                        }
                        .buttonStyle(.plain)
                        .help("Chat History")
                    }
                    
                    // New Chat
                    Button(action: { _ = agent.createNewChat(projectPath: agent.currentWorkspace ?? scopedWorkspacePath) }) {
                        Text("New")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(height: 26)
                    }
                    .buttonStyle(.plain)
                    .help("New Chat")

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
                        .frame(height: 26)
                    }
                    .menuStyle(.borderlessButton)
                    .help("Configure Team tasks, Agent context, Slack, and Microsoft Teams") }

                    if sessionScope == .editor {
                        Button { deviceRuntime.showingDeviceRuntimeSheet = true } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(height: 26)
                        }
                        .buttonStyle(.plain)
                        .help("Select a real Simulator / Emulator")

                        Menu {
                            Section("Live Multi-Platform Preview") {
                                Button("WebApp Preview (Localhost)") {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        previewDock.selectTab(id: "web")
                                    }
                                }
                                Button("iOS Simulator Preview") {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        previewDock.selectTab(id: "ios")
                                        Task { await deviceRuntime.startEmbeddedAppleSimulator() }
                                    }
                                }
                                Button("Android Emulator Preview") {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        previewDock.selectTab(id: "android")
                                        Task { await deviceRuntime.startEmbeddedAndroid() }
                                    }
                                }
                                Button("iPhone USB (Hardware)") {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        previewDock.selectTab(id: "ios-physical")
                                    }
                                }
                                Button("Android USB (Hardware)") {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        previewDock.selectTab(id: "android-physical")
                                    }
                                }
                                Button(previewDock.isDockVisible || deviceRuntime.showingEmbeddedDeviceDock ? "Hide Preview Dock" : "Show Preview Dock") {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        let newState = !(previewDock.isDockVisible || deviceRuntime.showingEmbeddedDeviceDock)
                                        previewDock.isDockVisible = newState
                                        deviceRuntime.showingEmbeddedDeviceDock = newState
                                    }
                                }
                            }

                            Divider()

                            Button("Choose Device & Run…") {
                                deviceRuntime.showingDeviceRuntimeSheet = true
                            }

                            let appleSimulators = deviceRuntime.devices.filter(\.isAppleSimulator)
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
                            HStack(spacing: 4) {
                                Image(systemName: "rectangle.portrait")
                                if !isCompact { Text("Preview") }
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(height: 26)
                        }
                        .menuStyle(.borderlessButton)
                        .help("Choose an iPhone, iPad, Apple Watch, Apple TV, physical Apple device, or Android Preview")
                    }
                    
                    Divider().frame(height: 16).padding(.horizontal, 2)
                    
                    // Mode Tabs — responsive: icon-only when compact
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 1) {
                            modePill("Chat", isActive: !isPaperMode && !isCellMode && !isPlanMode && !isTaskMode && !isWalkthroughMode, compact: isCompact) {
                                isPaperMode = false; isCellMode = false; isPlanMode = false; isTaskMode = false; isWalkthroughMode = false
                            }
                            modePill("Plan", isActive: isPlanMode, compact: isCompact) {
                                isPlanMode = true; isPaperMode = false; isCellMode = false; isTaskMode = false; isWalkthroughMode = false
                            }
                            modePill("Task", isActive: isTaskMode, compact: isCompact) {
                                isTaskMode = true; isPlanMode = false; isPaperMode = false; isCellMode = false; isWalkthroughMode = false
                            }
                            modePill("Walkthrough", isActive: isWalkthroughMode, compact: isCompact) {
                                isWalkthroughMode = true; isPlanMode = false; isPaperMode = false; isCellMode = false; isTaskMode = false
                            }
                            modePill("Report", isActive: isPaperMode, compact: isCompact) {
                                isPaperMode = true; isCellMode = false; isPlanMode = false; isTaskMode = false; isWalkthroughMode = false
                            }
                            modePill("Cells", isActive: isCellMode, compact: isCompact) {
                                isCellMode = true; isPaperMode = false; isPlanMode = false; isTaskMode = false; isWalkthroughMode = false
                            }
                        }
                        .padding(2)
                    }
                    
                    Spacer(minLength: 4)
                    
                    // Model Selector + Menu
                    HStack(spacing: 2) {
                        modelSelector
                        
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
                            } label: { Label("Clear Chat", systemImage: "trash") }
                        } label: {
                            Text("More")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(height: 24)
                        }
                        .menuStyle(.borderlessButton)

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
                .padding(.vertical, 5)
            }
            .frame(height: 36)
            .background(paneColor)
            
            Divider()
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
            await deviceRuntime.startEmbeddedAndroid()
            return
        }
        if device.isAppleSimulator {
            deviceRuntime.stopEmbeddedAndroid()
            deviceRuntime.embeddedDockMode = .ios
            deviceRuntime.showingEmbeddedDeviceDock = true
            deviceRuntime.showingEmbeddedAppleDock = true
            await deviceRuntime.startEmbeddedAppleSimulator()
            return
        }
        await deviceRuntime.startSelectedDevice()
    }
    
    private func modePill(_ label: String, isActive: Bool, compact: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { action() } }) {
            Text(compact ? String(label.prefix(1)) : label)
                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
            .foregroundColor(isActive ? .primary : .secondary)
            .padding(.horizontal, compact ? 7 : 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.primary.opacity(0.09) : Color.clear)
            .cornerRadius(3)
        }
        .buttonStyle(.plain)
        .help(label)
    }
    
    // MARK: - Implementation Plan View
    
    private var planView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Implementation Plan")
                            .font(.system(size: 16, weight: .semibold))
                        Text("AI-generated execution steps for the current task")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // Plan steps (extracted from agent activity log)
                let planSteps = extractPlanSteps()
                if planSteps.isEmpty {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 60)
                        Text("No plan generated yet")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Text("Ask the AI to create a plan or start a task")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(planSteps) { step in
                            HStack(alignment: .top, spacing: 10) {
                                Text(String(format: "%02d", step.id + 1))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, alignment: .leading)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(step.isDone ? .secondary : .primary)
                                        .strikethrough(step.isDone)
                                    if !step.detail.isEmpty {
                                        Text(step.detail)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(step.isDone ? Color.primary.opacity(0.025) : Color.clear)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }
    
    private struct PlanStep: Identifiable {
        let id: Int  // Stable identity based on insertion order
        let title: String
        let detail: String
        let isDone: Bool
    }
    
    private func extractPlanSteps() -> [PlanStep] {
        // Extract plan steps from agent activity log
        var steps: [PlanStep] = []
        for (i, activity) in agent.activityLog.enumerated() {
            switch activity.type {
            case .fileChange:
                steps.append(PlanStep(id: i, title: "File Change", detail: activity.message, isDone: true))
            case .tool:
                steps.append(PlanStep(id: i, title: "Tool Execution", detail: activity.message, isDone: true))
            case .thinking:
                steps.append(PlanStep(id: i, title: "Analysis", detail: activity.message, isDone: true))
            case .success:
                steps.append(PlanStep(id: i, title: "Completed", detail: activity.message, isDone: true))
            case .error:
                steps.append(PlanStep(id: i, title: "Error", detail: activity.message, isDone: false))
            default:
                break
            }
        }
        return steps
    }
    
    // MARK: - Task Editor & Autonomous Task Runner
    
    @State private var taskMdText: String = ""
    @State private var agentMdText: String = ""
    @State private var walkthroughMdText: String = ""
    @State private var activeTaskTab: Int = 0 // 0 = task.md, 1 = agent.md, 2 = walkthrough.md
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
            HStack(spacing: 6) {
                taskEditorTab("task.md", idx: 0)
                taskEditorTab("agent.md", idx: 1)
                taskEditorTab("walkthrough.md", idx: 2)
                
                if activeTaskTab == 0 {
                    Divider().frame(height: 14).padding(.horizontal, 4).opacity(0.3)
                    
                    // View Mode Switcher
                    Button(action: { withAnimation { taskViewMode = 0 } }) {
                        HStack(spacing: 3) {
                            Image(systemName: "checklist")
                            Text("Checklist")
                        }
                        .font(.system(size: 10, weight: taskViewMode == 0 ? .semibold : .regular))
                        .foregroundColor(taskViewMode == 0 ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(taskViewMode == 0 ? Color.primary.opacity(0.08) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { withAnimation { taskViewMode = 1 } }) {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.plaintext")
                            Text("Raw Markdown")
                        }
                        .font(.system(size: 10, weight: taskViewMode == 1 ? .semibold : .regular))
                        .foregroundColor(taskViewMode == 1 ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(taskViewMode == 1 ? Color.primary.opacity(0.08) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // Autonomous Execution Action
                if agent.isLoading {
                    Button(action: { AgentService.shared.stopGeneration() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 8))
                            Text("Stop Task")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.red.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.12))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: executeCurrentTaskPlan) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                            Text("Run Task with Agent")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                // Save button
                Button(action: saveTaskFiles) {
                    Text("Save")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            
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
                                            
                                            Text(step.text)
                                                .font(.system(size: 12))
                                                .foregroundColor(step.isCompleted ? .secondary : .primary)
                                                .strikethrough(step.isCompleted, color: .secondary.opacity(0.6))
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
                                }
                            }
                            .padding(14)
                        }
                    }
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.15))
                } else {
                    TextEditor(text: $taskMdText)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.3))
                }
            } else if activeTaskTab == 1 {
                TextEditor(text: $agentMdText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.3))
            } else {
                TextEditor(text: $walkthroughMdText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.3))
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
                        Text(walkthroughMdText)
                            .font(.system(size: 12, design: .monospaced))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
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
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.2))
        .onAppear { loadTaskFiles() }
    }
    
    private func executeCurrentTaskPlan() {
        saveTaskFiles()
        let providerString = appState.aiProvider
        let model = appState.aiModel.isEmpty ? "gemini-2.5-flash" : appState.aiModel
        let apiKey = appState.apiKeys[providerString] ?? ""
        
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
        let providerString = appState.aiProvider
        let model = appState.aiModel.isEmpty ? "gemini-2.5-flash" : appState.aiModel
        let apiKey = appState.apiKeys[providerString] ?? ""
        
        let directive = """
        Execute this single task step from .microcode/task.md:
        
        Target Step: \(stepText)
        
        Instructions:
        1. Execute the necessary actions/tools to complete this specific step.
        2. Once completed, update .microcode/task.md to check off this step.
        """
        
        Task {
            await agent.sendMessage(
                directive,
                provider: providerString,
                model: model,
                apiKey: apiKey
            )
        }
    }
    
    private func taskEditorTab(_ label: String, idx: Int) -> some View {
        Button(action: { withAnimation { activeTaskTab = idx } }) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(activeTaskTab == idx ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(activeTaskTab == idx ? Color.primary.opacity(0.09) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
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
                        if !NSEvent.modifierFlags.contains(.shift) && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            sendMessage()
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
            
            // Bottom Toolbar inside the Input Box
            inputBottomToolbar
            
            // Sub-bar (Local/Remote SSH on left, Main Agent on right)
            HStack {
                AgentTargetEnvironmentMenu(showingAddServer: $showingAddServerSheet)
                
                Spacer()
                
                // SubAgent Dropdown Pill Button
                Button(action: { showSubAgentDropdown.toggle() }) {
                    HStack(spacing: 4) {
                        let runningCount = SubAgentHarness.shared.activeSubagents.filter { $0.state == .running }.count
                        if runningCount > 0 {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        }
                        Text(selectedSubAgentDisplayName)
                            .font(.system(size: 10, weight: selectedSubAgentType == "main" ? .regular : .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7))
                    }
                    .foregroundColor(selectedSubAgentType == "main" ? .secondary.opacity(0.85) : .accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(selectedSubAgentType == "main" ? Color.clear : Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSubAgentDropdown, arrowEdge: .bottom) {
                    SubAgentSelectorMenu(
                        selectedType: $selectedSubAgentType,
                        isPresented: $showSubAgentDropdown
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
        .padding(10)
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
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)

                Text(agent.agentPhase.displayText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button(action: {
                    agent.stopGeneration()
                    acpHost.stopActiveAgent()
                }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.red.opacity(0.9))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Stop active AI task")
            }
            .padding(.horizontal, 16)
            .padding(.top, 5)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .padding(.top, 4)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
    
    private var inputArea: some View {
        VStack(spacing: 0) {
            // One unobtrusive activity line; execution details stay in the
            // transcript and continue running in the background.
            activeAgentStatusHUD
            
            // Queue Indicator Bar
            queueIndicatorBar
            
            // Attachment Pills
            if !attachments.isEmpty {
                attachmentsBar
            }
            
            // Keep the composer visually aligned with the reading column.
            // The two flexible spacers leave a small gutter on narrow splits,
            // then centre the card and cap it at a comfortable desktop width.
            // Therefore opening Preview/Inspector changes its width instantly
            // instead of leaving a fixed, overly-wide input surface behind.
            HStack(spacing: 0) {
                Spacer(minLength: 14)
                inputCardView
                    .frame(maxWidth: 880, alignment: .leading)
                Spacer(minLength: 14)
            }
            .padding(.vertical, 8)
        }
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
            .padding(.horizontal, 14)
            .padding(.top, 6)
        }
    }
    
    private var inputBottomToolbar: some View {
        HStack(spacing: 8) {
            plusActionMenu
            modelSelectorDropdown
            
            if let file = appState.currentFile {
                HStack(spacing: 3) {
                    Circle().fill(Color.blue.opacity(0.7)).frame(width: 5, height: 5)
                    Text(file.name)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(4)
            }
            
            Spacer()
            
            sendOrStopButton
        }
        .padding(.top, 2)
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
        let withKey = byokProviders.filter { !(appState.apiKeys[$0.id]?.isEmpty ?? true) }
        let withoutKey = byokProviders.filter { appState.apiKeys[$0.id]?.isEmpty ?? true }
        
        result.append(contentsOf: withKey)
        result.append(contentsOf: withoutKey)
        
        return result
    }
    
    private var modelSelectorDropdown: some View {
        Menu {
            modelMenuContent
        } label: {
            HStack(spacing: 5) {
                // Mode Badge: [ACP] / [Dotmini Cloud] / [BYOK] / [Subscription]
                Text(currentExecutionMode.badgeTitle)
                    .font(.system(size: 8.5, weight: .bold))
                    .padding(.horizontal, 4.5)
                    .padding(.vertical, 1.5)
                    .background(currentExecutionMode.badgeColor.opacity(0.12))
                    .foregroundColor(currentExecutionMode.badgeColor)
                    .cornerRadius(3.5)
                
                // Just Model Name
                Text(currentModelDisplayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.9))
                    .lineLimit(1)
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
    }
    
    private var sendOrStopButton: some View {
        Group {
            let hasInput = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
            
            if agent.isLoading {
                if hasInput {
                    // Queue Button (Adds prompt to queue without stopping current task)
                    Button(action: sendMessage) {
                        ZStack {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 26, height: 26)
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Add to Queue (Runs automatically after active task finishes)")
                } else {
                    // Stop Button (Only when input is empty)
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
                // TODO: Run project command
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
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Context Limit Banner
    
    private var contextLimitBanner: some View {
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
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.orange.opacity(0.25)),
            alignment: .top
        )
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
        let userText = inputText
        let currentAttachments = attachments
        
        inputText = ""
        attachments = []
        
        // If AI is busy, queue the message
        if agent.isLoading || agent.isProcessingQueue {
            agent.enqueueMessage(userText, attachments: currentAttachments)
            return
        }
        
        executeMessage(userText, attachments: currentAttachments)
    }
    
    private func executeMessage(_ userText: String, attachments currentAttachments: [AIAttachment] = []) {
        
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
            agent.setWorkspace(workspace.path)
        }
        
        // Route to External ACP Agent (Claude Code, Antigravity, OpenCode, Aider, Codex Engine, Zed) if active or if engine selected
        var targetConfig: ACPAgentConfig? = nil
        if let activeAgentId = acpHost.activeAgentId,
           let cfg = acpHost.registeredConfigs.first(where: { $0.id == activeAgentId }) {
            targetConfig = cfg
        } else if appState.aiProvider == "agy" {
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
        
        if let activeConfig = targetConfig {
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
            
            let workspace = appState.workspaceFolder?.path ?? FileManager.default.currentDirectoryPath
            let session = acpHost.getOrCreateSession(for: activeConfig)
            let chosenModel: String? = {
                switch activeConfig.type {
                case .agy:
                    let agyModels = LocalEcosystemDiscovery.shared.models(for: "agy").map(\.id)
                    return agyModels.contains(appState.aiModel) ? appState.aiModel : (agyModels.first ?? "gemini-3.8-flash-high")
                case .openCode:
                    let isAuthed = LocalEcosystemDiscovery.shared.engines.first(where: { $0.id == "opencode" })?.isAuthenticated ?? false
                    let openCodeModels = LocalEcosystemDiscovery.shared.models(for: "opencode").map(\.id)
                    let current = appState.aiModel
                    if openCodeModels.contains(current) {
                        if !isAuthed && !current.contains("free") {
                            return openCodeModels.first(where: { $0.contains("free") }) ?? "opencode/nemotron-3.5-lightning-free"
                        }
                        return current
                    }
                    return openCodeModels.first(where: { $0.contains("free") }) ?? "opencode/nemotron-3.5-lightning-free"
                case .codexEngine:
                    let codexModels = LocalEcosystemDiscovery.shared.models(for: "codex").map(\.id)
                    return codexModels.contains(appState.aiModel) ? appState.aiModel : (codexModels.first ?? "gpt-6-astra")
                case .claudeCode:
                    let claudeModels = LocalEcosystemDiscovery.shared.models(for: "claude_code").map(\.id)
                    return claudeModels.contains(appState.aiModel) ? appState.aiModel : (claudeModels.first ?? "haiku")
                case .zedEngine:
                    let zedModels = LocalEcosystemDiscovery.shared.models(for: "zed").map(\.id)
                    return zedModels.contains(appState.aiModel) ? appState.aiModel : (zedModels.first ?? "deepseek-v4-flash")
                default:
                    return appState.aiModel.isEmpty ? nil : appState.aiModel
                }
            }()
            if let model = chosenModel, appState.aiModel != model {
                appState.aiModel = model
            }
            
            Task { @MainActor in
                let stream = session.eventStream
                session.start(task: userText, workspacePath: workspace, model: chosenModel)
                
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
                    case .complete:
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
                        }
                        agent.isLoading = false
                        agent.agentPhase = .idle
                        agent.currentToolExecution = nil
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
                    default:
                        break
                    }
                }
            }
            return
        }
        
        let providerString = appState.aiProvider
        let model = appState.aiModel.isEmpty ? "gemini-2.5-flash" : appState.aiModel
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

            let simpleChatPrompt: String
            if agent.domain == .science {
                simpleChatPrompt = "You are MicroCode Science Agent. Work only from the current scientific research session and its explicitly attached or indexed artifacts. Separate observations, inferences and hypotheses; state uncertainty; never invent measurements or citations; do not provide autonomous clinical diagnosis or treatment. Respond in the user's language."
            } else {
                simpleChatPrompt = "You are MicroCode AI — a professional software engineering assistant integrated into the MicroCode IDE. Maintain a professional, clear, and authoritative tone. Provide well-structured, accurate responses with precise technical terminology. When the user asks about code, act as a senior software engineer providing production-quality solutions with clear code blocks. When the user writes in Thai, respond in Thai. When in English, respond in English. Be thorough but concise."
            }
            
            AIClient.shared.sendMessage(
                prompt: userText,
                attachments: currentAttachments,
                systemPrompt: simpleChatPrompt,
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
                onComplete: { _ in
                    self.agent.isLoading = false
                    self.agent.saveChats()
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
    
    // MARK: - Engine & Agent Switching Helpers
    
    private func switchToConfig(_ config: ACPAgentConfig) {
        activeACPAgent = config
        acpHost.activeAgentId = config.id
        let engineId: String
        switch config.type {
        case .agy: engineId = "agy"
        case .codexEngine: engineId = "codex"
        case .claudeCode: engineId = "claude_code"
        case .openCode: engineId = "opencode"
        case .zedEngine: engineId = "zed"
        case .aider: engineId = "aider"
        case .custom: engineId = "custom"
        }
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
        let type: ACPAgentType
        switch engineId {
        case "agy": type = .agy
        case "codex": type = .codexEngine
        case "claude_code": type = .claudeCode
        case "opencode": type = .openCode
        case "zed": type = .zedEngine
        default: type = .agy
        }
        
        let config: ACPAgentConfig
        if let existing = acpHost.registeredConfigs.first(where: { $0.type == type }) {
            config = existing
        } else {
            let binaryPath = LocalEcosystemDiscovery.shared.engines.first(where: { $0.id == engineId })?.binaryPath ?? type.defaultCommand
            config = ACPAgentConfig.defaultConfig(for: type, command: binaryPath)
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
        } else if mode == "cloud" {
            if let first = AIModelCatalog.shared.provider("omni")?.models.first {
                appState.aiProvider = "omni"
                appState.aiModel = first.id
            }
        } else {
            // Direct (BYOK)
            let byok = AIModelCatalog.shared.providers.filter { !["omni", "agy", "codex", "claude_code", "zed"].contains($0.id) && !(appState.apiKeys[$0.id]?.isEmpty ?? true) }
            if let firstProv = byok.first, let firstM = firstProv.models.first {
                appState.aiProvider = firstProv.id
                appState.aiModel = firstM.id
            } else {
                appState.aiProvider = "deepseek"
                appState.aiModel = "deepseek-flash"
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
        Menu {
            modelMenuContent
        } label: {
            HStack(spacing: 4) {
                // Mode badge: [ACP] / [Dotmini Cloud] / [BYOK] / [Subscription]
                Text(currentExecutionMode.badgeTitle)
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(currentExecutionMode.badgeColor.opacity(0.12))
                    .foregroundColor(currentExecutionMode.badgeColor)
                    .cornerRadius(3)
                
                // Model name only
                Text(headerModelDisplayName)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.primary.opacity(0.9))
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 220)
        .help("Select Mode & AI Model (ACP, Dotmini Cloud, BYOK, Subscription)")
    }
    
    @ViewBuilder
    private func providerIcon(for provider: String) -> some View {
        switch provider {
        case "gemini":      Image(systemName: "sparkles").foregroundColor(.purple)
        case "agy":         Image(systemName: "sparkles").foregroundColor(.purple)
        case "openai":      Image(systemName: "brain.head.profile").foregroundColor(.green)
        case "codex":       Image(systemName: "terminal.fill").foregroundColor(.green)
        case "anthropic":   Image(systemName: "bubble.left.and.text.bubble.right").foregroundColor(.orange)
        case "claude_code": Image(systemName: "command.square.fill").foregroundColor(.orange)
        case "opencode":    Image(systemName: "laptopcomputer").foregroundColor(Color(red: 0.88, green: 0.35, blue: 0.28))
        case "deepseek":    Image(systemName: "water.waves").foregroundColor(.blue)
        case "zed":         Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundColor(.blue)
        case "grok":        Image(systemName: "bolt.fill").foregroundColor(.red)
        case "local":       Image(systemName: "desktopcomputer").foregroundColor(.mint)
        default:            Image(systemName: "cpu").foregroundColor(.accentColor)
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
        // Section 1: 🔌 ACP (Agent Client Protocol - Local CLI)
        Section("🔌 ACP (Local CLI Agent)") {
            ForEach(LocalEcosystemDiscovery.shared.engines) { engine in
                Menu(engine.name) {
                    ForEach(engine.models) { m in
                        Button(action: {
                            switchToEngine(engine.id, modelId: m.id)
                        }) {
                            HStack {
                                Text(m.name)
                                if !m.badge.isEmpty { Text("(\(m.badge))") }
                                if currentExecutionMode == .acp && appState.aiProvider == engine.id && appState.aiModel == m.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        }
        
        Divider()
        
        // Section 2: ☁️ Dotmini Cloud (Sovereign AI)
        Section("☁️ Dotmini Cloud (Sovereign AI)") {
            if let omni = AIModelCatalog.shared.provider("omni") {
                ForEach(omni.models) { m in
                    Button(action: {
                        switchToNativeMode(mode: "cloud")
                        setModel("omni", m.id)
                    }) {
                        HStack {
                            Text(m.name)
                            if currentExecutionMode == .cloud && appState.aiModel == m.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }
        
        Divider()
        
        // Section 3: 🔑 BYOK (Bring Your Own Key)
        Section("🔑 BYOK (Bring Your Own Key)") {
            let byokProviders = AIModelCatalog.shared.providers.filter { !["omni", "agy", "codex", "claude_code", "zed"].contains($0.id) }
            ForEach(byokProviders) { prov in
                let hasKey = hasActiveKey(prov.id)
                Menu("\(prov.name)\(hasKey ? "" : " (No Key)")") {
                    ForEach(prov.models) { m in
                        Button(action: {
                            switchToNativeMode(mode: "direct")
                            setModel(prov.id, m.id)
                        }) {
                            HStack {
                                Text(m.name)
                                if currentExecutionMode == .byok && appState.aiProvider == prov.id && appState.aiModel == m.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        }
        
        Divider()
        
        // Section 4: ✨ Subscription (OAuth Accounts)
        Section("✨ Subscription (ChatGPT / Claude / Gemini / Copilot)") {
            if SubscriptionAuthManager.shared.hasAnyConnected {
                ForEach(SubscriptionAuthManager.shared.connectedProviders()) { prov in
                    Menu(prov.displayName) {
                        ForEach(prov.modelInfos) { subModel in
                            Button(action: {
                                switchToNativeMode(mode: "subscription")
                                appState.aiProvider = subModel.aiProviderID
                                appState.aiModel = subModel.modelID
                                SubscriptionAuthManager.shared.activeProvider = subModel.provider
                                UserDefaults.standard.set(subModel.provider.rawValue, forKey: "subscriptionActiveProvider")
                                UserDefaults.standard.set("subscription", forKey: "aiKeyMode")
                                appState.saveSettings()
                            }) {
                                HStack {
                                    Text(subModel.name)
                                    if currentExecutionMode == .subscription && appState.aiModel == subModel.modelID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                Button(action: { appState.showingSettingsDialog = true }) {
                    Label("Connect Subscription in Settings...", systemImage: "plus.circle")
                }
            }
        }
        
        Divider()
        
        Button {
            showingAgentConnections = true
        } label: {
            Label("Manage Agent Connections & Setup…", systemImage: "slider.horizontal.2.square")
        }
        
        Button(action: {
            Task {
                await AIModelCatalog.shared.refreshLiveProviderModels()
                await LocalEcosystemDiscovery.shared.refresh()
            }
        }) {
            Label("Rescan Local Engines & Cloud APIs", systemImage: "arrow.triangle.2.circlepath")
        }
        
        Button(action: {
            appState.showingSettingsDialog = true
        }) {
            Label("AI Settings...", systemImage: "gearshape")
        }
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
        let apiKey = appState.apiKeys[providerString] ?? ""
        
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
        pattern: "<thought>([\\s\\S]*?)</thought>|<thinking>([\\s\\S]*?)</thinking>",
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
        let lower = text.lowercased()
        var openRange: Range<String.Index>? = nil
        var tagLength = 0
        if let r = lower.range(of: "<thought>") {
            openRange = r
            tagLength = "<thought>".count
        } else if let r = lower.range(of: "<thinking>") {
            openRange = r
            tagLength = "<thinking>".count
        }
        
        guard let r = openRange else { return nil }
        let afterTag = text[r.upperBound...]
        let lowerAfter = String(afterTag).lowercased()
        if lowerAfter.contains("</thought>") || lowerAfter.contains("</thinking>") {
            return nil // Full match handled by regex
        }
        
        let before = String(text[..<r.lowerBound])
        let thought = String(afterTag).trimmingCharacters(in: .whitespacesAndNewlines)
        return (before: before, thought: thought)
    }
    
    private static func doParse(_ content: String) -> [MessageBlock] {
        let remaining = content
        
        // 0. Extract <thought>...</thought> or <thinking>...</thinking>
        if let thoughtRegex = thoughtRegex {
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
                    }
                    
                    let clean = thoughtBody.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty {
                        let estimatedSec = max(1, clean.count / 120)
                        parsedList.append(.thought(clean, estimatedSec))
                    }
                    
                    lastEnd = match.range.location + match.range.length
                }
                
                if lastEnd < nsContent.length {
                    let afterText = nsContent.substring(from: lastEnd)
                    if let unclosed = findUnclosedThought(in: afterText) {
                        if !unclosed.before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            parsedList.append(contentsOf: parseLatexAndCode(unclosed.before))
                        }
                        parsedList.append(.thought(unclosed.thought, nil))
                    } else if !afterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        parsedList.append(contentsOf: parseLatexAndCode(afterText))
                    }
                }
                
                return parsedList
            }
        }
        
        // Check for streaming / unclosed thought without closing tag
        if let unclosed = findUnclosedThought(in: remaining) {
            var parsedList: [MessageBlock] = []
            if !unclosed.before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parsedList.append(contentsOf: parseLatexAndCode(unclosed.before))
            }
            parsedList.append(.thought(unclosed.thought, nil))
            return parsedList
        }
        
        return parseLatexAndCode(remaining)
    }
    
    private static func parseLatexAndCode(_ content: String) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        let remaining = content
        
        // Extract LaTeX blocks ($$...$$ or \[...\])
        if let latexRegex = latexRegex {
            let nsContent = remaining as NSString
            let latexMatches = latexRegex.matches(in: remaining, options: [], range: NSRange(location: 0, length: nsContent.length))
            
            var processedRanges: [NSRange] = []
            var lastEnd = 0
            var tempBlocks: [MessageBlock] = []
            
            for match in latexMatches {
                if match.range.location > lastEnd {
                    let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                    let beforeText = nsContent.substring(with: beforeRange)
                    tempBlocks.append(.text(beforeText))
                }
                
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
            
            if lastEnd < nsContent.length {
                let afterText = nsContent.substring(from: lastEnd)
                tempBlocks.append(.text(afterText))
            }
            
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
        if let regex = codeRegex {
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
}

// MARK: - Chat Stage

struct AgentChatStage: View {
    let messages: [AgentMessageModel]
    let isLoading: Bool
    var domain: AgentDomain = .software
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
                            // Keep the first-turn actions in the same compact
                            // reading column as a real conversation instead of
                            // stretching controls from edge to edge.
                            .frame(maxWidth: 720)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                            
                            Spacer()
                        }
                    } else {
                        if AgentService.shared.hasEarlierMessages {
                            Button("Load earlier messages") {
                                AgentService.shared.loadEarlierMessages()
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 12)
                        }
                        ForEach(messages) { message in
                            RichMessageRow(message: message, onApplyChange: onApplyChange, onRejectChange: onRejectChange)
                                .equatable()
                                .id(message.id)
                        }
                    }
                    
                }
                .padding(.bottom, 16)
            }
            // Loading an older page increases the count but keeps the final ID
            // unchanged. Tracking that ID prevents a history load from jumping
            // the viewport back to the newest message.
            .onChange(of: messages.last?.id) { lastId in
                if let lastId {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
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

struct RichMessageRow: View, Equatable {
    let message: AgentMessageModel
    var onApplyChange: ((PendingChangeModel) -> Void)? = nil
    var onRejectChange: ((PendingChangeModel) -> Void)? = nil
    @EnvironmentObject var appState: AppState
    
    static func == (lhs: RichMessageRow, rhs: RichMessageRow) -> Bool {
        return lhs.message.id == rhs.message.id &&
               lhs.message.content == rhs.message.content &&
               lhs.message.toolResults.count == rhs.message.toolResults.count &&
               lhs.message.pendingChanges.count == rhs.message.pendingChanges.count &&
               lhs.message.role == rhs.message.role
    }
    
    private var isUser: Bool { message.role == .user }
    
    var body: some View {
        if isUser {
            // User bubbles should use their natural content width.  A short
            // sentence must never become a full-row rectangle; ViewThatFits
            // keeps that intrinsic shape and only switches to wrapping when a
            // longer message reaches the readable-width cap.
            HStack {
                Spacer(minLength: 40)

                ViewThatFits(in: .horizontal) {
                    userBubbleText
                        .fixedSize(horizontal: true, vertical: false)

                    userBubbleText
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 600, alignment: .trailing)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 6)
        } else {
            // A readable editorial column, inspired by the comfortable line
            // lengths used in Codex and AGY. It stays fluid in narrow splits,
            // but never turns a wide editor into one long line of prose.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 8) {
                    aiCellContent
                }
                .frame(maxWidth: 880, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
        }
    }

    private var userBubbleText: some View {
        Text(message.content)
            .font(Font.custom(appState.agentFontName, size: appState.agentFontSize))
            .foregroundColor(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .padding(12)
            .background(Color.primary.opacity(0.09))
            .cornerRadius(8, corners: [.topLeft, .topRight, .bottomLeft])
    }
    
    private var aiCellContent: some View {
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
    }
    
    @ViewBuilder
    private func aiBlockView(_ block: MessageBlock) -> some View {
        switch block {
        case .thought(let content, let duration):
            AntigravityThoughtBlockView(content: content, durationSeconds: duration)
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
    @State private var showDiff = true  // Auto-expand diff
    
    static func == (lhs: PendingChangeCard, rhs: PendingChangeCard) -> Bool {
        return lhs.change.id == rhs.change.id &&
               lhs.change.status == rhs.change.status &&
               lhs.change.additions == rhs.change.additions &&
               lhs.change.deletions == rhs.change.deletions &&
               lhs.change.oldContent == rhs.change.oldContent &&
               lhs.change.newContent == rhs.change.newContent
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            changeCardHeader
            
            if showDiff {
                codeDiffSection
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
            Image(systemName: change.status == .accepted ? "checkmark.circle.fill" : change.status == .rejected ? "xmark.circle.fill" : "doc.text.fill")
                .foregroundColor(change.status == .accepted ? .green : change.status == .rejected ? .red : .blue)
                .font(.system(size: 13))
            
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
            
            Spacer()
            
            // Toggle diff
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { showDiff.toggle() } }) {
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
            Image(systemName: "doc.text").font(.system(size: 10)).foregroundColor(.secondary)
            Text(change.description).font(.system(size: 10)).foregroundColor(.secondary)
            Spacer()
        }
        .padding(8)
    }
    
    // MARK: - Code Diff (Modern High-Contrast Unified Code Diff with Memoization)
    
    private var codeDiffSection: some View {
        let lines: [UnifiedDiffLine] = DiffCacheManager.getOrComputeDiff(
            id: change.id,
            old: change.oldContent,
            new: change.newContent
        )
        
        return VStack(spacing: 0) {
            Divider().opacity(0.4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { (diffLine: UnifiedDiffLine) in
                        HStack(spacing: 0) {
                            // Status accent strip (2.5pt)
                            Rectangle()
                                .fill(diffLine.accentColor)
                                .frame(width: 2.5)
                            
                            // Gutter: Old line number
                            Text(diffLine.oldNum)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.4))
                                .frame(width: 32, alignment: .trailing)
                                .padding(.trailing, 4)
                            
                            // Gutter: New line number
                            Text(diffLine.newNum)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.4))
                                .frame(width: 32, alignment: .trailing)
                                .padding(.trailing, 6)
                            
                            // Gutter divider line
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(width: 1)
                            
                            // Prefix (+/-)
                            Text(diffLine.prefix)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(diffLine.prefixColor)
                                .frame(width: 18, alignment: .center)
                            
                            // Code text
                            Text(diffLine.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(diffLine.textColor)
                                .lineLimit(1)
                            
                            Spacer(minLength: 24)
                        }
                        .frame(height: 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(diffLine.bgColor)
                    }
                }
                .padding(.vertical, 2)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
        }
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
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.02))
    }
}

// MARK: - Memoized Diff Cache Manager

public struct UnifiedDiffLine: Identifiable, Equatable {
    public let id: String
    public let oldNum: String
    public let newNum: String
    public let prefix: String
    public let text: String
    public let type: DiffLineType
    
    public enum DiffLineType {
        case context, addition, deletion, hunkHeader
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
        case .hunkHeader: return Color.cyan
        case .context: return Color.primary.opacity(0.85)
        }
    }
    
    var bgColor: Color {
        switch type {
        case .addition: return Color.green.opacity(0.12)
        case .deletion: return Color.red.opacity(0.10)
        case .hunkHeader: return Color.cyan.opacity(0.06)
        case .context: return Color.clear
        }
    }
}

public final class DiffCacheManager {
    private static var cache: [String: [UnifiedDiffLine]] = [:]
    private static let lock = NSLock()
    
    public static func getOrComputeDiff(id: String, old: String, new: String) -> [UnifiedDiffLine] {
        let key = "\(id)-\(old.hashValue)-\(new.hashValue)"
        lock.lock()
        if let found = cache[key] {
            lock.unlock()
            return found
        }
        lock.unlock()
        
        let computed = computeDiff(old: old, new: new)
        
        lock.lock()
        if cache.count > 250 { cache.removeAll(keepingCapacity: true) }
        cache[key] = computed
        lock.unlock()
        
        return computed
    }
    
    private static func computeDiff(old: String, new: String) -> [UnifiedDiffLine] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")
        
        // Fast path for identical content
        if old == new {
            return oldLines.prefix(100).enumerated().map { idx, line in
                UnifiedDiffLine(id: "ctx-\(idx)", oldNum: "\(idx + 1)", newNum: "\(idx + 1)", prefix: " ", text: line, type: .context)
            }
        }
        
        // Capped DP matrix to guarantee sub-millisecond execution
        let m = min(oldLines.count, 150)
        let n = min(newLines.count, 150)
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 1...max(1, m) {
            for j in 1...max(1, n) {
                if i <= m && j <= n && oldLines[i-1] == newLines[j-1] {
                    dp[i][j] = dp[i-1][j-1] + 1
                } else {
                    dp[i][j] = max(dp[i-1][j], dp[i][j-1])
                }
            }
        }
        
        enum DiffOp { case equal(String), delete(String), insert(String) }
        var ops: [DiffOp] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && oldLines[i-1] == newLines[j-1] {
                ops.append(.equal(oldLines[i-1]))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                ops.append(.insert(newLines[j-1]))
                j -= 1
            } else if i > 0 {
                ops.append(.delete(oldLines[i-1]))
                i -= 1
            }
        }
        ops.reverse()
        
        var result: [UnifiedDiffLine] = []
        var oldLineNum = 1
        var newLineNum = 1
        var lineIdx = 0
        
        for op in ops {
            lineIdx += 1
            switch op {
            case .equal(let text):
                result.append(UnifiedDiffLine(
                    id: "eq-\(lineIdx)",
                    oldNum: "\(oldLineNum)", newNum: "\(newLineNum)",
                    prefix: " ", text: text, type: .context
                ))
                oldLineNum += 1; newLineNum += 1
            case .delete(let text):
                result.append(UnifiedDiffLine(
                    id: "del-\(lineIdx)",
                    oldNum: "\(oldLineNum)", newNum: "",
                    prefix: "-", text: text, type: .deletion
                ))
                oldLineNum += 1
            case .insert(let text):
                result.append(UnifiedDiffLine(
                    id: "ins-\(lineIdx)",
                    oldNum: "", newNum: "\(newLineNum)",
                    prefix: "+", text: text, type: .addition
                ))
                newLineNum += 1
            }
            if result.count > 150 { break }
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
    
    static func getOrParse(_ text: String) -> AttributedString {
        lock.lock()
        if let found = cache[text] {
            lock.unlock()
            return found
        }
        lock.unlock()
        
        let parsed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        
        lock.lock()
        if cache.count > 500 { cache.removeAll(keepingCapacity: true) }
        cache[text] = parsed
        lock.unlock()
        return parsed
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
            .textSelection(.enabled)
    }
}

/// Renders heading with proper font size
struct HeadingView: View {
    let level: Int
    let content: String
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Text(content)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundColor(.primary)
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

/// Renders ordered/unordered list
struct ListView: View {
    let items: [String]
    let isOrdered: Bool
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    Text(isOrdered ? "\(index + 1)." : "•")
                        .font(.system(size: appState.agentFontSize, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: isOrdered ? 24 : 14, alignment: .trailing)
                    
                    MarkdownTextView(text: items[index])
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
            
            Text(content)
                .font(.system(size: appState.agentFontSize))
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
                            Text(headers[idx])
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

struct NativeCodeBlockView: View, Equatable {
    let language: String
    let code: String
    
    static func == (lhs: NativeCodeBlockView, rhs: NativeCodeBlockView) -> Bool {
        return lhs.language == rhs.language && lhs.code == rhs.code
    }
    
    @State private var isCopied = false
    @State private var isHovering = false
    @State private var isExpanded = false
    
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
                // Left Gutter (Single Unified Text Block)
                gutterView
                
                // Main Cell Content (Single Unified Text Block)
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
        .padding(.vertical, 8)
        .onHover { isHovering = $0 }
    }
    
    // MARK: - Subviews
    
    private var lineCount: Int {
        code.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
    }
    
    private var isLongCode: Bool {
        lineCount > 15 || code.count > 1_200
    }

    private var isWideSingleLinePayload: Bool {
        code.count > 1_200 && lineCount <= 2
    }
    
    private var gutterView: some View {
        let maxLines = min(lineCount, isExpanded ? lineCount : 15)
        let gutterText = (1...max(1, maxLines)).map { "\($0)" }.joined(separator: "\n") + (isLongCode && !isExpanded ? "\n..." : "")
        
        return Text(gutterText)
            .font(.system(size: 11, design: .monospaced))
            .lineSpacing(4)
            .foregroundColor(.secondary.opacity(0.55))
            .multilineTextAlignment(.trailing)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(minWidth: 32, alignment: .trailing)
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
            if !isWideSingleLinePayload && !dynamicTag.isEmpty {
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        NotificationCenter.default.post(
            name: Notification.Name("OpenInPlayground"), 
            object: nil, 
            userInfo: ["code": code, "language": language]
        )
    }
    
    private func runInCellMode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        NotificationCenter.default.post(
            name: Notification.Name("OpenInCellMode"), 
            object: nil, 
            userInfo: ["code": code, "language": language]
        )
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
    
    private var codeContentView: some View {
        let displayCode: String
        if isExpanded || !isLongCode {
            displayCode = code
        } else if isWideSingleLinePayload {
            displayCode = String(code.prefix(1_200)) + "\n…"
        } else {
            displayCode = code.components(separatedBy: "\n").prefix(15).joined(separator: "\n")
        }
        
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(displayCode)
                    .font(.custom("Menlo", size: 12))
                    .lineSpacing(4)
                    .foregroundColor(Color(nsColor: .textColor))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .textSelection(.enabled)
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
                            Text(isWideSingleLinePayload
                                 ? "Show \(max(0, code.count - 1_200)) more characters"
                                 : "Show \(max(0, lineCount - 15)) more lines")
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
    
    @State private var isExpanded: Bool = true
    @State private var userToggled: Bool = false
    @State private var isPulsing: Bool = false
    @State private var liveElapsedSeconds: Int = 1
    @State private var liveTimer: Timer? = nil
    
    private var isStreaming: Bool {
        durationSeconds == nil
    }
    
    private var durationText: String {
        if isStreaming {
            return "Thinking in real-time • \(liveElapsedSeconds)s"
        }
        if let d = durationSeconds, d > 0 {
            return isExpanded ? "Thinking for \(d)s" : "Thought for \(d)s"
        }
        return isExpanded ? "Thinking" : "Thought process"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Collapsible Header
            Button(action: {
                userToggled = true
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    if isStreaming {
                        // Pulsing sparkle icon during live streaming
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .opacity(isPulsing ? 1.0 : 0.4)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                    } else {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    
                    Text(durationText)
                        .font(.system(size: 11.5, weight: isStreaming ? .medium : .regular))
                        .foregroundColor(isStreaming ? .primary : .secondary)
                    
                    if isStreaming {
                        // LIVE badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 5, height: 5)
                                .opacity(isPulsing ? 1.0 : 0.3)
                                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
                            
                            Text("LIVE")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(.accentColor)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.7))
                    
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
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Formulating reasoning steps…")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        let sections = parseThoughtSections(cleanContent)
                        ForEach(sections) { sec in
                            VStack(alignment: .leading, spacing: 4) {
                                if let title = sec.title, !title.isEmpty {
                                    Text(title)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundColor(.primary.opacity(0.9))
                                }
                                
                                Text(sec.body)
                                    .font(.system(size: 11, design: .default))
                                    .foregroundColor(.secondary.opacity(0.85))
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    HStack {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.35))
                            .frame(width: 2.5)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                )
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            if isStreaming {
                isPulsing = true
                if !userToggled { isExpanded = true }
                startLiveTimer()
            } else {
                if !userToggled { isExpanded = false }
            }
        }
        .onChange(of: durationSeconds) { newDuration in
            if newDuration != nil {
                liveTimer?.invalidate()
                liveTimer = nil
                isPulsing = false
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

// MARK: - Antigravity-Style Activity Summary & Tool Tree

struct ToolExecutionStepsView: View {
    let results: [ToolResultModel]
    // Keep historical tool output cheap while scrolling. Users can still expand
    // a completed step on demand.
    @State private var isExpanded: Bool = false
    
    private var headerTitle: String {
        let fileCount = results.filter { $0.toolName.contains("file") || $0.toolName.contains("read") || $0.toolName.contains("write") }.count
        if fileCount > 0 {
            return "Exploring \(fileCount) file\(fileCount > 1 ? "s" : "")"
        }
        return "Executed \(results.count) step\(results.count > 1 ? "s" : "")"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Text(headerTitle)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundColor(.secondary)
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.7))
                    
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(results.enumerated()), id: \.element.toolCallId) { index, result in
                        ToolActivityItemRow(result: result)
                    }
                }
                .padding(.leading, 8)
                .padding(.top, 3)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ToolActivityItemRow: View {
    let result: ToolResultModel
    @State private var showDetails: Bool = false
    
    private var displayItem: (verb: String, detail: String, lineInfo: String?) {
        let output = result.output
        let params = result.toolParams ?? [:]
        var lineInfo: String? = nil
        
        if let startLine = params["StartLine"] as? Int, let endLine = params["EndLine"] as? Int {
            lineInfo = "#L\(startLine)-\(endLine)"
        } else if let lineMatch = output.range(of: #"#L\d+(-\d+)?"#, options: .regularExpression) {
            lineInfo = String(output[lineMatch])
        }
        
        let targetFile = (params["path"] as? String) ?? (params["TargetFile"] as? String) ?? (params["AbsolutePath"] as? String) ?? (params["file_path"] as? String)
        let resolvedFileName = targetFile != nil ? URL(fileURLWithPath: targetFile!).lastPathComponent : extractFileName(output)
        
        switch result.toolName {
        case "file_read", "read_file", "view_file":
            let name = resolvedFileName ?? "source file"
            let lines = lineInfo ?? (output.contains("\n") ? "#L1-\(min(350, output.components(separatedBy: .newlines).count))" : nil)
            return ("Analyzed", name, lines)
            
        case "multi_file_read":
            if let paths = params["paths"] as? [String], let first = paths.first {
                let name = URL(fileURLWithPath: first).lastPathComponent
                let countStr = paths.count > 1 ? " (+\(paths.count - 1) more)" : ""
                return ("Analyzed", "\(name)\(countStr)", nil)
            }
            return ("Analyzed", "project files", nil)
            
        case "file_write", "replace_in_file", "write_to_file", "patch_file":
            let name = resolvedFileName ?? "file"
            return ("Edited", name, nil)
            
        case "shell", "run_command":
            if let cmd = params["command"] as? String ?? params["CommandLine"] as? String {
                let cleanCmd = cmd.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? cmd
                return ("Executed", String(cleanCmd.prefix(40)), nil)
            }
            return ("Executed", "terminal task", nil)
            
        case "grep_search", "file_search", "find_symbol":
            let query = (params["query"] as? String) ?? (params["symbol"] as? String) ?? extractQuery(output)
            return ("Searched", "\"\(query.prefix(30))\"", nil)
            
        case "list_directory_tree", "list_dir":
            return ("Scanned directory", "project structure", nil)
            
        case "git_status":
            return ("Inspected", "Git repository state", nil)
            
        case "git_diff":
            return ("Inspected", "Git diff changes", nil)
            
        default:
            let cleanName = result.toolName.replacingOccurrences(of: "_", with: " ")
            return ("Applied", cleanName, nil)
        }
    }
    
    private func extractFileName(_ text: String) -> String? {
        if let range = text.range(of: #"/[^\s\n:]+\.[a-zA-Z0-9]+"#, options: .regularExpression) {
            let path = String(text[range])
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return nil
    }
    
    private func extractQuery(_ text: String) -> String {
        if let firstLine = text.components(separatedBy: .newlines).first, !firstLine.isEmpty {
            return String(firstLine.prefix(40))
        }
        return "codebase"
    }
    
    private func extractCommand(_ id: String, output: String) -> String {
        if let firstLine = output.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return String(firstLine.prefix(45))
        }
        return "command"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showDetails.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Text(displayItem.verb)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                    
                    Text(displayItem.detail)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(nsColor: .labelColor).opacity(0.9))
                    
                    if let lines = displayItem.lineInfo {
                        Text(lines)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if showDetails {
                Text(result.success ? result.output : (result.error ?? "Failed"))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(result.success ? .secondary : .red.opacity(0.8))
                    .lineLimit(15)
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
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
                
                Button(action: { isPresented = false }) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("Quick Start")
                            .font(.system(size: 11.5))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                
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
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func selectProject(_ path: String) {
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        Task { @MainActor in
            await appState.openWorkspace(url: url)
            agent.setWorkspace(path)
            _ = agent.createNewChat(projectPath: path)
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
            .frame(maxHeight: 270)
            
            Divider()
                .opacity(0.4)
            
            // Bottom Action Controls
            HStack {
                Button(action: {
                    isPresented = false
                    harness.showSubAgentMonitor = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10))
                        Text("Open Monitor HUD")
                            .font(.system(size: 11, weight: .regular))
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
        .background(Color(nsColor: .windowBackgroundColor))
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
