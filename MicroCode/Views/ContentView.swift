//
//  ContentView.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2024 AIPRENEUR. All rights reserved.
//

import SwiftUI
import AppKit

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("microCodeWelcomeCompletedV1") private var welcomeCompleted = false

    var body: some View {
        AgenticEditorWorkspace()
            .environmentObject(appState)
            .overlay(autoHealerOverlay)
            .overlay(welcomeOverlay)
            .modifier(PrimarySheetsModifier(appState: appState))
            .modifier(SecondarySheetsModifier(appState: appState))
            .modifier(StudioSheetsModifier(appState: appState))
            .alert("MicroCode", isPresented: .constant(appState.alertMessage != nil)) {
                Button("OK") { appState.alertMessage = nil }
            } message: {
                Text(appState.alertMessage ?? "")
            }
        // Keyboard shortcuts
        .onCommand(#selector(NSResponder.selectAll(_:))) { }
        .background(
            ZStack {
                if appState.appTheme.isGlass {
                    Color.clear
                } else {
                    Color(nsColor: appState.appTheme.workspaceBackground)
                }
            }
        )
        .background(
            Button("") { appState.saveCurrentFile() }
                .keyboardShortcut("s", modifiers: .command)
                .hidden()
        )
        .background(
            Button("") { appState.createNewFile() }
                .keyboardShortcut("n", modifiers: .command)
                .hidden()
        )
        .background(
            Button("") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.aiChatVisible.toggle()
                }
            }
                .keyboardShortcut("l", modifiers: .command)
                .hidden()
        )
        .background(
            Button("") { appState.toggleEditorMode(.browser) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .hidden()
        )
        .overlay(
            Group {
                if (appState.appTheme == .christmas || appState.appTheme == .christmasLight) {
                    SnowEffectView()
                        .allowsHitTesting(false)
                }
                
                FestiveOverlayView()
                    .allowsHitTesting(false)
            }
        )
    }

    @ViewBuilder
    private var welcomeOverlay: some View {
        if !welcomeCompleted {
            FirstLaunchWelcomeView {
                welcomeCompleted = true
            }
            .environmentObject(appState)
            .transition(.opacity)
            .zIndex(200)
        }
    }

    private var legacyWorkspace: some View {
        CompatHSplitView {
            if appState.sidebarVisible {
                NavigatorView()
                    .frame(minWidth: 200, idealWidth: 260, maxWidth: 400)
            }
            EditorArea()
            if appState.gitPanelVisible {
                InspectorView()
                    .frame(minWidth: 260, maxWidth: 350)
            }
            if appState.aiChatVisible {
                LegacyInlineAgentPanel()
                    .frame(minWidth: 340, idealWidth: 400, maxWidth: 520)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    // MARK: - Auto-Healer View

    @ViewBuilder
    private var autoHealerOverlay: some View {
        if let suggestion = AutoHealerService.shared.currentSuggestion {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        AutoHealerService.shared.dismissSuggestion()
                    }

                HealerSuggestionView(
                    suggestion: suggestion,
                    onApply: {
                        AutoHealerService.shared.applyFix(suggestion)
                    },
                    onDismiss: {
                        AutoHealerService.shared.dismissSuggestion()
                    }
                )
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(100)
        }
    }
}

// MARK: - Agentic-first Code Workspace

enum AgenticWorkspaceSurface: String {
    case agent
    case editor
}

struct AgenticEditorWorkspace: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var agent = AgentService.shared
    @State private var surface: AgenticWorkspaceSurface = .agent

    var body: some View {
        Group {
            if (appState.workspaceFolder == nil && appState.openFiles.isEmpty && appState.editorMode == .code) || appState.showingWelcomeHome {
                WelcomeScreen(surface: $surface)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        appState.appTheme.isGlass
                            ? AnyView(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
                            : AnyView(Color(nsColor: appState.appTheme.workspaceBackground))
                    )
            } else {
                CompatHSplitView {
                    if appState.sidebarVisible {
                        if surface == .editor {
                            XcodeEditorSidebar(surface: $surface)
                                .frame(minWidth: 240, idealWidth: 270, maxWidth: 340)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        } else {
                            AgenticWorkspaceSidebar(surface: $surface)
                                .frame(minWidth: 240, idealWidth: 270, maxWidth: 340)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }

                    VStack(spacing: 0) {
                        workspaceHeader
                        Divider()

                        if surface == .agent {
                            AIAgentView(allowsChatSidebar: false)
                                .environmentObject(appState)
                        } else {
                            activeEditorSurface
                        }
                    }
                    .frame(minWidth: 480)

                    if appState.agenticContextVisible {
                        AgenticContextInspector(surface: $surface)
                            .frame(minWidth: 260, idealWidth: 340, maxWidth: 520)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.workspaceBackground))
            }
        }
        .onAppear {
            if let workspace = appState.workspaceFolder {
                agent.setWorkspace(workspace.path)
            }
        }
        .onChange(of: appState.editorMode) { newMode in
            if newMode == .aiAgent {
                surface = .agent
            } else {
                surface = .editor
            }
        }
    }

    @ViewBuilder
    private var activeEditorSurface: some View {
        switch appState.editorMode {
        case .aiAgent:
            AIAgentView(allowsChatSidebar: false)
                .environmentObject(appState)
        case .notebook:
            NotebookView()
                .environmentObject(appState)
        case .science:
            ScienceModeView()
                .environmentObject(appState)
        case .playground:
            PlaygroundView()
                .environmentObject(appState)
        case .browser:
            IDEBrowserView()
                .environmentObject(appState)
        case .remoteX:
            RemoteXView()
                .environmentObject(appState)
        case .embedded:
            EmbeddedStudioView()
                .environmentObject(appState)
        case .apiClient:
            APIClientView()
                .environmentObject(appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            EditorArea()
                .environmentObject(appState)
        }
    }

    private var activeTaskTitle: String {
        if let currentChat = agent.chatSessions.first(where: { $0.id == agent.activeChatId }) {
            return currentChat.name
        }
        return "New Task"
    }

    private var activeProjectName: String {
        if surface == .agent, let currentChat = agent.chatSessions.first(where: { $0.id == agent.activeChatId }), let pName = currentChat.projectName, !pName.isEmpty {
            return pName
        }
        return appState.workspaceFolder?.lastPathComponent ?? "MicroCode"
    }

    private var workspaceHeader: some View {
        HStack(spacing: 8) {
            // Traffic lights clearance when sidebar is collapsed
            if !appState.sidebarVisible {
                Spacer().frame(width: 68)
            }

            // Sidebar Toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    appState.toggleSidebar()
                }
            }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Toggle Sidebar (⌘B)")

            // Breadcrumb (Antigravity-style: project / active task)
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(activeProjectName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("/")
                    .foregroundColor(.secondary.opacity(0.6))
                    .font(.system(size: 11))
                Text(surface == .agent ? activeTaskTitle : (appState.currentFile?.name ?? (appState.editorMode == .code ? "Editor" : appState.editorMode.displayName)))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(1)
            }
            .truncationMode(.middle)
            .frame(maxWidth: 220, alignment: .leading)

            Spacer(minLength: 4)

            // Agent Phase Indicator (only when outside Agent surface and busy)
            if surface != .agent && agent.agentPhase != .idle {
                HStack(spacing: 5) {
                    ProgressView().scaleEffect(0.4).frame(width: 10, height: 10)
                    Text(agent.agentPhase.displayText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(12)
                .fixedSize()
            }

            // In Editor mode (.code only), provide Run, Build, Preview, Console quick action pills
            if surface == .editor && appState.editorMode == .code {
                HStack(spacing: 5) {
                    // Run Code
                    Button(action: { appState.runCode() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("Run")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Run Code (⌘R)")

                    // Build Project
                    Button(action: { appState.buildProject() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 9, weight: .medium))
                            Text("Build")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(.primary.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Build Project (⌘B)")

                    // Preview Menu (Real Device & Simulator Preview)
                    Menu {
                        Button("WebApp Preview (Localhost)") {
                            DeviceRuntimeService.shared.embeddedDockMode = .web
                            DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
                            appState.showingPreviewView = true
                        }
                        Button("iOS Simulator") {
                            DeviceRuntimeService.shared.embeddedDockMode = .ios
                            DeviceRuntimeService.shared.showingEmbeddedAppleDock = true
                            DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
                            appState.showingPreviewView = true
                            Task { await DeviceRuntimeService.shared.startPreferredEmbeddedAppleSimulator() }
                        }
                        Button("Android Emulator") {
                            DeviceRuntimeService.shared.embeddedDockMode = .android
                            DeviceRuntimeService.shared.showingEmbeddedAppleDock = false
                            DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
                            appState.showingPreviewView = true
                            Task { await DeviceRuntimeService.shared.startPreferredEmbeddedAndroid() }
                        }
                        Button("iPhone USB (Hardware)") {
                            PreviewDockService.shared.selectTab(id: "ios-physical")
                            DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
                            appState.showingPreviewView = true
                        }
                        Button("Android USB (Hardware)") {
                            PreviewDockService.shared.selectTab(id: "android-physical")
                            DeviceRuntimeService.shared.showingEmbeddedDeviceDock = true
                            appState.showingPreviewView = true
                        }
                        Divider()
                        Button("Choose Device & Run…") {
                            DeviceRuntimeService.shared.showingDeviceRuntimeSheet = true
                        }
                        Button(appState.showingPreviewView ? "Hide Preview Dock (⌥⌘P)" : "Show Preview Dock (⌥⌘P)") {
                            withAnimation {
                                appState.showingPreviewView.toggle()
                                DeviceRuntimeService.shared.showingEmbeddedDeviceDock = appState.showingPreviewView
                            }
                        }
                        Button("Open Full Web Browser") {
                            appState.editorMode = .browser
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: DeviceRuntimeService.shared.showingEmbeddedAppleDock ? "iphone" : "apps.iphone")
                                .font(.system(size: 9))
                            Text("Preview")
                                .font(.system(size: 11, weight: appState.showingPreviewView ? .semibold : .medium))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7, weight: .semibold))
                        }
                        .foregroundColor(appState.showingPreviewView ? .white : .primary.opacity(0.85))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(appState.showingPreviewView ? Color.white.opacity(0.16) : Color.primary.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(appState.showingPreviewView ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1)
                        )
                        .cornerRadius(6)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Live Real Device Preview (iOS Sim & Android Emu)")

                    // Console Toggle
                    Button(action: { appState.toggleConsole() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "terminal")
                                .font(.system(size: 9))
                            Text("Console")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(appState.consoleVisible ? .accentColor : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(appState.consoleVisible ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Toggle Terminal / Console (⌘J)")
                }
                .fixedSize()
            }

            // Surface Toggle (Agent vs Code Editor vs More Mode)
            HStack(spacing: 2) {
                Button {
                    surface = .agent
                    appState.setEditorMode(.aiAgent)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "brain")
                            .font(.system(size: 10))
                        Text("Agent")
                            .font(.system(size: 11, weight: (surface == .agent || appState.editorMode == .aiAgent) ? .semibold : .medium))
                            .lineLimit(1)
                    }
                }
                .agenticTabStyle(active: surface == .agent || appState.editorMode == .aiAgent)

                Button {
                    surface = .editor
                    appState.setEditorMode(.code)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "curlybraces")
                            .font(.system(size: 10))
                        Text("Code Editor")
                            .font(.system(size: 11, weight: (surface == .editor && appState.editorMode == .code) ? .semibold : .medium))
                            .lineLimit(1)
                    }
                }
                .agenticTabStyle(active: surface == .editor && appState.editorMode == .code)

                Menu {
                    Button("Playground Mode") {
                        appState.showingWelcomeHome = false
                        appState.setEditorMode(.playground)
                        surface = .editor
                    }
                    Button("Cell Mode (Notebook)") {
                        appState.showingWelcomeHome = false
                        appState.setEditorMode(.notebook)
                        surface = .editor
                    }
                    Button("SSH Remote Browser") {
                        appState.showingWelcomeHome = false
                        appState.setEditorMode(.remoteX)
                        surface = .editor
                    }
                    Button("Science Mode") {
                        appState.showingWelcomeHome = false
                        appState.setEditorMode(.science)
                        surface = .editor
                    }
                    Button("IDE Web Browser") {
                        appState.showingWelcomeHome = false
                        appState.setEditorMode(.browser)
                        surface = .editor
                    }
                    Button("Embed & IoT Studio") {
                        appState.showingWelcomeHome = false
                        appState.setEditorMode(.embedded)
                        surface = .editor
                    }
                    Button("API Studio") {
                        appState.openAPIStudio()
                        surface = .editor
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 10))
                        Text(surface == .editor && appState.editorMode != .code ? appState.editorMode.displayName : "More Mode")
                            .font(.system(size: 11, weight: (surface == .editor && appState.editorMode != .code) ? .semibold : .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                }
                .agenticTabStyle(active: surface == .editor && appState.editorMode != .code)
            }
            .padding(2)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(6)
            .fixedSize()

            // Overflow Layout Menu [...]
            AgenticLayoutMenu()
                .environmentObject(appState)
                .fixedSize()

            // Context & Preview Inspector [sidebar.right]
            Button(action: {
                withAnimation(.easeInOut(duration: 0.16)) {
                    appState.toggleAgenticContext()
                }
            }) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12))
                    .foregroundColor(appState.agenticContextVisible ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("i", modifiers: [.command])
            .fixedSize()
            .help("Toggle Preview & Context Inspector (⌘I)")

            // Settings [⚙]
            Button(action: { appState.showingSettingsDialog = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground))
    }
}

struct AgenticLayoutMenu: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Menu {
            Section("Developer Tools") {
                Button { appState.runCode() } label: { Label("Run Code (⌘R)", systemImage: "play.fill") }
                Button { appState.buildProject() } label: { Label("Build Project (⌘B)", systemImage: "hammer.fill") }
                Button { appState.toggleConsole() } label: { Label(appState.consoleVisible ? "Hide Terminal / Console" : "Show Terminal / Console (⌘J)", systemImage: "terminal.fill") }
            }

            Section("Specialized Studios") {
                Button { appState.showingDatabaseStudio = true } label: { Label("Database Studio", systemImage: "server.rack") }
                Button { 
                    appState.openAPIStudio()
                } label: { Label("API Studio", systemImage: "network") }
                Button { appState.showingContainerView = true } label: { Label("Apple Container Studio", systemImage: "shippingbox.fill") }
                Button { appState.showingCICDView = true } label: { Label("CI/CD Pipelines", systemImage: "checklist") }
                Button { appState.showingCollaborationView = true } label: { Label("Realtime Collaboration", systemImage: "person.2.fill") }
            }

            Section("Panels") {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { appState.toggleAgenticContext() }
                } label: {
                    Label(appState.agenticContextVisible ? "Hide Context Inspector" : "Show Context Inspector (⌘I)", systemImage: "sidebar.right")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Tools & Layout")
    }
}

private extension View {
    func agenticTabStyle(active: Bool) -> some View {
        self
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: active ? .semibold : .regular))
            .foregroundColor(active ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(active ? Color.primary.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

struct AgenticWorkspaceSidebar: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var agent = AgentService.shared
    @Binding var surface: AgenticWorkspaceSurface
    @State private var isProjectsExpanded = true
    @State private var isFilesExpanded = true
    @State private var collapsedProjectIds: Set<String> = []
    @State private var searchText: String = ""
    @State private var isSearchVisible: Bool = false
    @State private var renamingChatId: String? = nil
    @State private var renameText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            
            if isSearchVisible {
                sidebarSearchBar
            }
            
            sidebarNewConversationButton
            
            Divider().padding(.horizontal, 10).padding(.bottom, 2)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    projectsSection
                    Divider().padding(.horizontal, 10)
                    workspaceFilesSection
                }
                .padding(.vertical, 6)
            }
            
            Divider()
            sidebarFooter
        }
        .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground))
    }
    
    // MARK: - Header (Codex style: Title dropdown, Search toggle, New Chat icon)
    @ViewBuilder
    private var sidebarHeader: some View {
        HStack(spacing: 6) {
            Menu {
                Button(action: { surface = .agent }) {
                    Label("MicroCode AI Agent", systemImage: "sparkles")
                }
                Button(action: { surface = .editor }) {
                    Label("Editor Navigator", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Divider()
                Button(action: { appState.openFolder() }) {
                    Label("Open Project…", systemImage: "folder")
                }
            } label: {
                HStack(spacing: 4) {
                    Text("MicroCode AI")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isSearchVisible.toggle()
                    if !isSearchVisible { searchText = "" }
                }
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(isSearchVisible ? .primary : .secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Search Conversations")

            Button(action: {
                let ws = appState.workspaceFolder?.path ?? agent.currentWorkspace
                _ = agent.createNewChat(projectPath: ws)
                surface = .agent
            }) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Conversation (⌘N)")
        }
        .padding(.leading, 78)
        .padding(.trailing, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var sidebarSearchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            TextField("Search tasks & conversations...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
    
    @ViewBuilder
    private var sidebarNewConversationButton: some View {
        Button {
            let ws = appState.workspaceFolder?.path ?? agent.currentWorkspace
            _ = agent.createNewChat(projectPath: ws)
            surface = .agent
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("New Conversation")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("⌘N")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
    
    
    // MARK: - Projects & Conversations Section (Codex Styled)
    @ViewBuilder
    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("PROJECTS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { withAnimation { isProjectsExpanded.toggle() } }) {
                    Image(systemName: isProjectsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            if isProjectsExpanded {
                let groups = filteredProjectGroups
                if groups.isEmpty {
                    Text("No matching conversations")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                } else {
                    ForEach(groups) { group in
                        projectGroupRow(group: group)
                    }
                }
            }
        }
    }

    private var filteredProjectGroups: [ProjectChatGroup] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return agent.projectGroups }
        return agent.projectGroups.compactMap { group in
            let matchingChats = group.chats.filter { $0.name.lowercased().contains(q) }
            if group.projectName.lowercased().contains(q) {
                return group
            } else if !matchingChats.isEmpty {
                return ProjectChatGroup(projectName: group.projectName, projectPath: group.projectPath, chats: matchingChats)
            }
            return nil
        }
    }
    
    @ViewBuilder
    private func projectGroupRow(group: ProjectChatGroup) -> some View {
        let isExpanded = isProjectGroupExpanded(group)
        VStack(alignment: .leading, spacing: 2) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if collapsedProjectIds.contains(group.id) {
                        collapsedProjectIds.remove(group.id)
                    } else {
                        collapsedProjectIds.insert(group.id)
                    }
                    if let path = group.projectPath, !path.isEmpty {
                        let folderURL = URL(fileURLWithPath: path)
                        if appState.workspaceFolder?.path != path {
                            Task { @MainActor in
                                await appState.openWorkspace(url: folderURL)
                            }
                        }
                    }
                }
            }) {
                HStack(spacing: 7) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.75))
                        .frame(width: 8)
                    
                    // Codex-style clean outline folder icon
                    Image(systemName: isExpanded ? "folder" : "folder")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Text(group.projectName)
                        .font(.system(size: 12.5, weight: isExpanded ? .semibold : .regular))
                        .foregroundColor(.primary.opacity(0.9))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if !isExpanded && !group.chats.isEmpty {
                        Text("\(group.chats.count)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.75))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(3.5)
                    }
                    
                    Button(action: {
                        if let path = group.projectPath, !path.isEmpty {
                            let folderURL = URL(fileURLWithPath: path)
                            if appState.workspaceFolder?.path != path {
                                Task { @MainActor in
                                    await appState.openWorkspace(url: folderURL)
                                }
                            }
                        }
                        _ = agent.createNewChat(projectPath: group.projectPath)
                        collapsedProjectIds.remove(group.id)
                        surface = .agent
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.75))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("New Conversation in \(group.projectName)")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(group.chats) { chat in
                    projectChatRow(chat: chat, group: group)
                }
            }
        }
        .padding(.bottom, 3)
    }
    
    @ViewBuilder
    private func projectChatRow(chat: ChatSession, group: ProjectChatGroup) -> some View {
        let isActive = agent.activeChatId == chat.id && surface == .agent
        let isBusy = isActive && agent.agentPhase != .idle
        
        Button {
            agent.switchChat(to: chat.id)
            collapsedProjectIds.remove(group.id)
            if let path = chat.projectPath ?? group.projectPath, !path.isEmpty {
                let folderURL = URL(fileURLWithPath: path)
                if appState.workspaceFolder?.path != path {
                    Task { @MainActor in
                        await appState.openWorkspace(url: folderURL)
                    }
                }
            }
            surface = .agent
        } label: {
            HStack(spacing: 8) {
                // Title with enhanced readability and larger font (13pt)
                if renamingChatId == chat.id {
                    TextField("Chat Name", text: $renameText, onCommit: {
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            agent.renameChat(chat.id, to: trimmed)
                        }
                        renamingChatId = nil
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 5)
                    .background(Color.primary.opacity(0.1))
                    .cornerRadius(4)
                } else {
                    Text(chat.name)
                        .font(.system(size: 13, weight: isActive ? .medium : .regular))
                        .foregroundColor(isActive ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                Spacer(minLength: 4)
                
                // Trailing Indicators: Busy spinner, purple git branch icon, or active dot
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 14, height: 14)
                } else if isActive {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.purple.opacity(0.85))
                }
            }
            .padding(.leading, 26)
            .padding(.trailing, 10)
            .frame(height: 30)
            .background(
                isActive
                    ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08))
                    : RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .contextMenu {
            Button("Rename Conversation…") {
                renameText = chat.name
                renamingChatId = chat.id
            }
            Button("Copy Title") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(chat.name, forType: .string)
            }
            Divider()
            Button("Delete Conversation", role: .destructive) {
                agent.deleteChat(chat.id)
            }
        }
    }
    
    @ViewBuilder
    private var workspaceFilesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("WORKSPACE FILES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { withAnimation { isFilesExpanded.toggle() } }) {
                    Image(systemName: isFilesExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)

            if isFilesExpanded {
                NavigatorView(onOpenFile: { surface = .editor })
                    .environmentObject(appState)
                    .frame(minHeight: 220, maxHeight: 480)
                    .onAppear {
                        if appState.fileTree.isEmpty && appState.workspaceFolder != nil {
                            Task { @MainActor in
                                await appState.refreshFileTree()
                            }
                        }
                    }
            }
        }
    }
    
    // MARK: - Footer
    @ViewBuilder
    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            Button(action: { appState.showingSettingsDialog = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11.5))
                    Text("Settings")
                        .font(.system(size: 11.5, weight: .regular))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("MicroCode Settings")

            Spacer()

            Button(action: { appState.showingSettingsDialog = true }) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("MicroCode Help")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.02))
    }

    private func isProjectGroupExpanded(_ group: ProjectChatGroup) -> Bool {
        return !collapsedProjectIds.contains(group.id)
    }
}

// MARK: - Xcode-Style Native Editor Navigator Sidebar

enum XcodeNavigatorTab: Int, CaseIterable {
    case project = 0
    case sourceControl = 1
    case search = 2
    case issues = 3
    case recent = 4

    var icon: String {
        switch self {
        case .project: return "folder"
        case .sourceControl: return "arrow.triangle.branch"
        case .search: return "magnifyingglass"
        case .issues: return "exclamationmark.triangle"
        case .recent: return "clock"
        }
    }

    var title: String {
        switch self {
        case .project: return "Project Navigator"
        case .sourceControl: return "Source Control"
        case .search: return "Search in Workspace"
        case .issues: return "Issue Navigator"
        case .recent: return "Recent Projects & Files"
        }
    }
}

struct XcodeEditorSidebar: View {
    @EnvironmentObject var appState: AppState
    @Binding var surface: AgenticWorkspaceSurface
    @State private var selectedTab: XcodeNavigatorTab = .project
    @State private var filterText: String = ""
    @State private var showRecentOnly: Bool = false
    @State private var recentProjects: [URL] = []
    @State private var recentFiles: [URL] = []

    private var displayedFileTree: Binding<[FileNode]> {
        if filterText.isEmpty && !showRecentOnly {
            return $appState.fileTree
        }
        let filtered = filterFileNodes(appState.fileTree, query: filterText, recentOnly: showRecentOnly)
        return Binding(
            get: { filtered },
            set: { _ in }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            navigatorTabBar
            Divider()

            projectHeaderBar
            Divider()

            Group {
                switch selectedTab {
                case .project:
                    projectNavigatorContent
                case .sourceControl:
                    GitPanelView()
                case .search:
                    searchNavigatorContent
                case .issues:
                    issuesNavigatorContent
                case .recent:
                    recentNavigatorContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            bottomFilterBar
        }
        .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground))
        .onAppear {
            refreshRecents()
            if appState.fileTree.isEmpty && appState.workspaceFolder != nil {
                Task { @MainActor in await appState.refreshFileTree() }
            }
        }
        .onChange(of: appState.workspaceFolder) { _ in
            refreshRecents()
        }
    }

    // MARK: - Navigator Tab Bar (Xcode Icon Strip)

    private var navigatorTabBar: some View {
        HStack(spacing: 2) {
            ForEach(XcodeNavigatorTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        selectedTab = tab
                    }
                } label: {
                    Image(systemName: selectedTab == tab ? "\(tab.icon).fill" : tab.icon)
                        .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(selectedTab == tab ? Color.primary.opacity(0.08) : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 7)
        .padding(.bottom, 5)
    }

    // MARK: - Project Header Bar

    private var projectHeaderBar: some View {
        HStack(spacing: 6) {
            Image(systemName: appState.workspaceFolder != nil ? "folder.fill" : "folder")
                .foregroundColor(appState.workspaceFolder != nil ? .accentColor : .secondary)
                .font(.system(size: 11))

            Text(appState.workspaceFolder?.lastPathComponent ?? "No Project")
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(.primary)

            Spacer()

            Menu {
                Button {
                    appState.openFolder()
                } label: {
                    Label("Open Project or Folder…", systemImage: "folder.badge.plus")
                }

                Button {
                    appState.openFile()
                } label: {
                    Label("Open File…", systemImage: "doc.badge.plus")
                }

                if !recentProjects.isEmpty {
                    Divider()
                    Menu("Recent Projects") {
                        ForEach(recentProjects.prefix(8), id: \.self) { url in
                            Button(url.lastPathComponent) {
                                Task { @MainActor in await appState.openWorkspace(url: url) }
                            }
                        }
                    }
                }

                if !recentFiles.isEmpty {
                    Menu("Recent Files") {
                        ForEach(recentFiles.prefix(10), id: \.self) { url in
                            Button(url.lastPathComponent) {
                                Task { @MainActor in await appState.loadFile(url: url) }
                            }
                        }
                    }
                }

                Divider()

                Button {
                    appState.newFile()
                } label: {
                    Label("New File", systemImage: "doc.badge.plus")
                }

                Button {
                    Task { @MainActor in await appState.refreshFileTree() }
                } label: {
                    Label("Refresh File Tree", systemImage: "arrow.clockwise")
                }

                if appState.workspaceFolder != nil {
                    Divider()
                    Button("Close Project", role: .destructive) {
                        appState.closeWorkspace()
                    }
                }

                Divider()
                Button {
                    surface = .agent
                } label: {
                    Label("Switch to AI Agent Mode", systemImage: "brain")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Project Options")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Project Navigator Content

    @ViewBuilder
    private var projectNavigatorContent: some View {
        if appState.workspaceFolder != nil {
            VStack(spacing: 0) {
                AuthenticFileTree(
                    fileTree: displayedFileTree,
                    revision: appState.fileTreeRevision,
                    backgroundColor: appState.appTheme.isGlass ? .clear : appState.appTheme.panelBackground,
                    onAction: { action in
                        handleAction(action)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let warning = appState.fileTreeLimitWarning {
                    Text(warning)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.035))
                }
            }
        } else {
            emptyProjectStateView
        }
    }

    // MARK: - Empty Project Navigator (Xcode Style)

    private var emptyProjectStateView: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 34))
                        .foregroundColor(.accentColor.opacity(0.85))
                        .padding(.top, 24)

                    Text("Xcode Project Navigator")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Open a folder or file to explore and edit your code.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    HStack(spacing: 10) {
                        Button(action: { appState.openFolder() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "folder.badge.plus")
                                Text("Open Folder…")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: { appState.openFile() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "doc")
                                Text("Open File…")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.primary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }

                if !recentProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("RECENT PROJECTS")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)

                        VStack(spacing: 2) {
                            ForEach(recentProjects.prefix(6), id: \.self) { url in
                                Button {
                                    Task { @MainActor in await appState.openWorkspace(url: url) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "folder.fill")
                                            .foregroundColor(.accentColor)
                                            .font(.system(size: 12))
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(url.lastPathComponent)
                                                .font(.system(size: 11.5, weight: .medium))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            Text(url.path)
                                                .font(.system(size: 9.5))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.03))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                }

                if !recentFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("RECENT FILES")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)

                        VStack(spacing: 2) {
                            ForEach(recentFiles.prefix(6), id: \.self) { url in
                                Button {
                                    Task { @MainActor in await appState.loadFile(url: url) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "doc.text.fill")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 12))
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(url.lastPathComponent)
                                                .font(.system(size: 11.5, weight: .medium))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            Text(url.path)
                                                .font(.system(size: 9.5))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.03))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Search Navigator Content

    private var searchNavigatorContent: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Search in Workspace…", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                if !filterText.isEmpty {
                    Button(action: { filterText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(6)
            .padding(.horizontal, 8)
            .padding(.top, 8)

            if appState.workspaceFolder == nil {
                VStack(spacing: 6) {
                    Text("No Workspace Open")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(matchingFileNodes(in: appState.fileTree, query: filterText), id: \.id) { node in
                            Button {
                                Task { @MainActor in
                                    await appState.loadFile(url: URL(fileURLWithPath: node.path))
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: node.isDirectory ? "folder.fill" : "doc.text.fill")
                                        .foregroundColor(node.isDirectory ? .accentColor : .secondary)
                                        .font(.system(size: 11))
                                    Text(node.name)
                                        .font(.system(size: 11))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.03))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    // MARK: - Issues Navigator Content

    private var issuesNavigatorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("ISSUES & DIAGNOSTICS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                if let warning = appState.fileTreeLimitWarning {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 11))
                        Text(warning)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.08))
                    .cornerRadius(6)
                    .padding(.horizontal, 8)
                }

                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green.opacity(0.8))
                    Text("No build or analysis errors detected")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
        }
    }

    // MARK: - Recent Navigator Content

    private var recentNavigatorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !recentProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("RECENT PROJECTS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(recentProjects.count)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                        ForEach(recentProjects, id: \.self) { url in
                            Button {
                                Task { @MainActor in await appState.openWorkspace(url: url) }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.accentColor)
                                        .font(.system(size: 12))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(url.path)
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.03))
                                .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                    }
                }

                if !recentFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "doc")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("RECENT FILES")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(recentFiles.count)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)

                        ForEach(recentFiles, id: \.self) { url in
                            Button {
                                Task { @MainActor in await appState.loadFile(url: url) }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 12))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(url.path)
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.03))
                                .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                    }
                }

                if recentProjects.isEmpty && recentFiles.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No Recent Items")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Bottom Filter Bar (Xcode Style)

    private var bottomFilterBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    appState.newFile()
                } label: {
                    Label("New File…", systemImage: "doc.badge.plus")
                }

                Button {
                    if let ws = appState.workspaceFolder {
                        Task { @MainActor in
                            await appState.createFolder(at: ws.path, name: "New Folder")
                        }
                    } else {
                        appState.openFolder()
                    }
                } label: {
                    Label("New Folder…", systemImage: "folder.badge.plus")
                }

                Divider()

                Button {
                    appState.openFile()
                } label: {
                    Label("Open File…", systemImage: "doc")
                }

                Button {
                    appState.openFolder()
                } label: {
                    Label("Open Folder…", systemImage: "folder")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Add file or folder")

            // Filter
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))
                TextField("Filter", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !filterText.isEmpty {
                    Button(action: { filterText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(4)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showRecentOnly.toggle()
                }
            }) {
                Image(systemName: showRecentOnly ? "clock.fill" : "clock")
                    .font(.system(size: 11))
                    .foregroundColor(showRecentOnly ? .accentColor : .secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Show only recently opened files")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Actions & Helpers

    private func refreshRecents() {
        recentProjects = AppState.getRecentWorkspaces()
        recentFiles = AppState.getRecentFiles()
    }

    private func handleAction(_ action: FileTreeAction) {
        switch action {
        case .openFile(let node):
            Task { @MainActor in
                await appState.loadFile(url: URL(fileURLWithPath: node.path))
            }
        case .loadChildren(let node):
            Task { @MainActor in await appState.loadChildren(for: node.id) }
        case .createFolder(let node, let name):
            Task { @MainActor in await appState.createFolder(at: node.path, name: name) }
        case .rename(let node, let newName):
            Task { @MainActor in await appState.renameFile(at: node.path, to: newName) }
        case .delete(let node):
            try? FileManager.default.trashItem(at: URL(fileURLWithPath: node.path), resultingItemURL: nil)
            Task { @MainActor in await appState.refreshFileTree() }
        }
    }

    private func matchingFileNodes(in nodes: [FileNode], query: String) -> [FileNode] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var matches: [FileNode] = []
        func traverse(_ list: [FileNode]) {
            for item in list {
                if item.name.localizedCaseInsensitiveContains(query) {
                    matches.append(item)
                }
                traverse(item.children)
            }
        }
        traverse(nodes)
        return Array(matches.prefix(50))
    }

    private func filterFileNodes(_ nodes: [FileNode], query: String, recentOnly: Bool) -> [FileNode] {
        var result: [FileNode] = []
        let cleanQuery = query.trimmingCharacters(in: .whitespaces)
        let recentPaths = Set(recentFiles.map { $0.path } + appState.openFiles.map { $0.path })

        for node in nodes {
            if node.isDirectory {
                let filteredChildren = filterFileNodes(node.children, query: query, recentOnly: recentOnly)
                if !filteredChildren.isEmpty {
                    var copy = node
                    copy.children = filteredChildren
                    result.append(copy)
                }
            } else {
                let matchesQuery = cleanQuery.isEmpty || node.name.localizedCaseInsensitiveContains(cleanQuery)
                let matchesRecent = !recentOnly || recentPaths.contains(node.path)
                if matchesQuery && matchesRecent {
                    result.append(node)
                }
            }
        }
        return result
    }
}

enum AgenticInspectorTab: String, CaseIterable {
    case context = "Context"
    case preview = "Preview"
    case tasks = "Tasks & Plan"
}

struct AgenticContextInspector: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var agent = AgentService.shared
    @ObservedObject private var deviceRuntime = DeviceRuntimeService.shared
    @Binding var surface: AgenticWorkspaceSurface
    @State private var selectedTab: AgenticInspectorTab = .context
    @State private var taskMarkdownContent: String = ""
    @State private var walkthroughMarkdownContent: String = ""
    @State private var taskSubTab: Int = 0 // 0 = Task, 1 = Walkthrough

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar with Tab Switcher
            HStack(spacing: 6) {
                ForEach(AgenticInspectorTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedTab = tab
                            if tab == .preview && !deviceRuntime.showingEmbeddedDeviceDock {
                                deviceRuntime.showingEmbeddedDeviceDock = true
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            switch tab {
                            case .context:
                                Image(systemName: "sidebar.right")
                                    .font(.system(size: 9))
                            case .preview:
                                Image(systemName: deviceRuntime.embeddedDockMode == .web ? "globe" : (deviceRuntime.showingEmbeddedAppleDock ? "iphone" : "candybarphone"))
                                    .font(.system(size: 9))
                            case .tasks:
                                Image(systemName: "checklist")
                                    .font(.system(size: 9))
                            }
                            Text(tab.rawValue)
                                .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .foregroundColor(selectedTab == tab ? .primary : .secondary)
                        .background(selectedTab == tab ? Color.primary.opacity(0.1) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if selectedTab == .preview {
                    Menu {
                        Section("Preview Target") {
                            Button("WebApp Preview") {
                                deviceRuntime.embeddedDockMode = .web
                                deviceRuntime.showingEmbeddedDeviceDock = true
                            }
                            Button("iOS Simulator") {
                                deviceRuntime.embeddedDockMode = .ios
                                deviceRuntime.showingEmbeddedDeviceDock = true
                                deviceRuntime.showingEmbeddedAppleDock = true
                                Task { await deviceRuntime.startEmbeddedAppleSimulator() }
                            }
                            Button("Android Emulator") {
                                deviceRuntime.embeddedDockMode = .android
                                deviceRuntime.showingEmbeddedDeviceDock = true
                                deviceRuntime.showingEmbeddedAppleDock = false
                                Task { await deviceRuntime.startEmbeddedAndroid() }
                            }
                        }

                        Divider()

                        Button("Choose Device & Run…") {
                            deviceRuntime.showingDeviceRuntimeSheet = true
                        }
                        Divider()
                        let appleSimulators = deviceRuntime.devices.filter(\.isAppleSimulator)
                        let androidDevices = deviceRuntime.devices.filter { $0.platform == .android }
                        if !appleSimulators.isEmpty {
                            Section("iOS Simulators") {
                                ForEach(appleSimulators.prefix(6)) { device in
                                    Button(device.name) {
                                        Task {
                                            deviceRuntime.selectedDeviceID = device.id
                                            deviceRuntime.stopEmbeddedAndroid()
                                            deviceRuntime.showingEmbeddedDeviceDock = true
                                            deviceRuntime.showingEmbeddedAppleDock = true
                                            await deviceRuntime.startEmbeddedAppleSimulator()
                                        }
                                    }
                                }
                            }
                        }
                        if !androidDevices.isEmpty {
                            Section("Android Emulators") {
                                ForEach(androidDevices.prefix(6)) { device in
                                    Button(device.name) {
                                        Task {
                                            deviceRuntime.selectedDeviceID = device.id
                                            deviceRuntime.showingEmbeddedDeviceDock = true
                                            deviceRuntime.showingEmbeddedAppleDock = false
                                            await deviceRuntime.startEmbeddedAndroid()
                                        }
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("Refresh Devices") {
                            Task { await deviceRuntime.refresh(workspace: appState.workspaceFolder) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 18)
                } else {
                    Text(agent.isLoading ? "Working" : "Ready")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                // Standard macOS HIG Close button [✕] at top-right
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        appState.agenticContextVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close Inspector (⌘I)")
            }
            .padding(.horizontal, 10)
            .frame(height: 38)

            Divider()

            // Tab Content
            switch selectedTab {
            case .context:
                contextTabView
            case .preview:
                previewTabView
            case .tasks:
                tasksAndWalkthroughTabView
            }
        }
        .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground))
        .onAppear {
            reloadTaskAndWalkthrough()
        }
        .onChange(of: deviceRuntime.showingEmbeddedDeviceDock) { showing in
            if !showing && selectedTab == .preview {
                withAnimation(.easeInOut(duration: 0.16)) {
                    selectedTab = .context
                }
            }
        }
    }

    // MARK: - Context Tab View
    private var contextTabView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                inspectorSection("CURRENT FILE") {
                    if let file = appState.currentFile {
                        contextFileRow(path: file.path, status: file.isUnsaved ? "Modified" : file.language)
                    } else {
                        emptyLabel("No file selected")
                    }
                }

                inspectorSection("FILES CHANGED \(changedFiles.count)") {
                    if changedFiles.isEmpty {
                        emptyLabel("No changes in this task")
                    } else {
                        ForEach(changedFiles.prefix(12), id: \.self) { path in
                            contextFileRow(path: path, status: "Changed")
                        }
                    }
                }

                inspectorSection("OPEN FILES \(appState.openFiles.count)") {
                    if appState.openFiles.isEmpty {
                        emptyLabel("No open files")
                    } else {
                        ForEach(appState.openFiles.prefix(10)) { file in
                            contextFileRow(path: file.path, status: file.isUnsaved ? "Unsaved" : nil)
                        }
                    }
                }

                inspectorSection("AGENT ACTIVITY") {
                    if agent.activityLog.isEmpty {
                        emptyLabel("Activity will appear here")
                    } else {
                        ForEach(agent.activityLog.suffix(8).reversed()) { activity in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.message)
                                    .font(.system(size: 10))
                                    .lineLimit(2)
                                if let detail = activity.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Live Preview Tab View
    private var previewTabView: some View {
        VStack(spacing: 0) {
            EmbeddedDeviceDockView()
                .environmentObject(appState)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tasks & Walkthrough Tab View
    private var tasksAndWalkthroughTabView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    withAnimation { taskSubTab = 0 }
                } label: {
                    Text("task.md")
                        .font(.system(size: 10, weight: taskSubTab == 0 ? .semibold : .regular, design: .monospaced))
                        .foregroundColor(taskSubTab == 0 ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(taskSubTab == 0 ? Color.primary.opacity(0.08) : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation { taskSubTab = 1 }
                } label: {
                    Text("walkthrough.md")
                        .font(.system(size: 10, weight: taskSubTab == 1 ? .semibold : .regular, design: .monospaced))
                        .foregroundColor(taskSubTab == 1 ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(taskSubTab == 1 ? Color.primary.opacity(0.08) : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    reloadTaskAndWalkthrough()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reload Task & Walkthrough")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.03))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if taskSubTab == 0 {
                        renderTaskChecklist()
                    } else {
                        renderWalkthrough()
                    }
                }
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private func renderTaskChecklist() -> some View {
        let lines = taskMarkdownContent.components(separatedBy: .newlines)
        let checklistItems = lines.compactMap { line -> (isCompleted: Bool, text: String)? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("* [ ] ") {
                return (false, String(trimmed.dropFirst(6)))
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") || trimmed.hasPrefix("* [x] ") || trimmed.hasPrefix("* [X] ") {
                return (true, String(trimmed.dropFirst(6)))
            }
            return nil
        }

        if checklistItems.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No task steps found")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(taskMarkdownContent.isEmpty ? "No .microcode/task.md file" : taskMarkdownContent)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineLimit(8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else {
            let completedCount = checklistItems.filter { $0.isCompleted }.count
            let totalCount = checklistItems.count

            HStack {
                Text("\(completedCount)/\(totalCount) Tasks Done")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(Int((Double(completedCount) / Double(max(1, totalCount))) * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            ProgressView(value: Double(completedCount), total: Double(totalCount))
                .progressViewStyle(.linear)

            Divider().padding(.vertical, 4)

            ForEach(Array(checklistItems.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundColor(item.isCompleted ? .accentColor : .secondary.opacity(0.6))
                        .padding(.top, 1)

                    Text(item.text)
                        .font(.system(size: 11))
                        .foregroundColor(item.isCompleted ? .secondary : .primary)
                        .strikethrough(item.isCompleted, color: .secondary.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 3)
            }
        }
    }

    @ViewBuilder
    private func renderWalkthrough() -> some View {
        if walkthroughMarkdownContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No walkthrough recorded yet")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("AI Walkthroughs and verification summaries will be displayed here as the task progresses.")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 11))
                    Text("Execution Walkthrough")
                        .font(.system(size: 11, weight: .bold))
                    Spacer()
                }

                Divider().opacity(0.5)

                Text(walkthroughMarkdownContent)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.9))
                    .textSelection(.enabled)
                    .lineSpacing(3)
            }
        }
    }

    private func reloadTaskAndWalkthrough() {
        guard let workspace = appState.workspaceFolder?.path ?? AgentService.shared.currentWorkspace else { return }
        let microcodeDir = (workspace as NSString).appendingPathComponent(".microcode")
        let taskPath = (microcodeDir as NSString).appendingPathComponent("task.md")
        let walkthroughPath = (microcodeDir as NSString).appendingPathComponent("walkthrough.md")

        taskMarkdownContent = (try? String(contentsOfFile: taskPath, encoding: .utf8)) ?? ""
        walkthroughMarkdownContent = (try? String(contentsOfFile: walkthroughPath, encoding: .utf8)) ?? ""
    }

    private var changedFiles: [String] {
        var values = agent.filesModified
        values.append(contentsOf: appState.gitStatus?.files.map(\.path) ?? [])
        return Array(NSOrderedSet(array: values)).compactMap { $0 as? String }
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(.secondary.opacity(0.75))
    }

    private func contextFileRow(path: String, status: String?) -> some View {
        Button {
            let url = resolvedURL(for: path)
            Task { @MainActor in
                await appState.loadFile(url: url)
                surface = .editor
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(relativePath(path))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if let status {
                        Text(status)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }

    private func resolvedURL(for path: String) -> URL {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return appState.workspaceFolder?.appendingPathComponent(path) ?? URL(fileURLWithPath: path)
    }

    private func relativePath(_ path: String) -> String {
        guard let root = appState.workspaceFolder?.path, path.hasPrefix(root) else { return path }
        return String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

struct LegacyInlineAgentPanel: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var modelCatalog = AIModelCatalog.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("AI Agent")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(appState.aiModel.isEmpty ? "Ready" : appState.aiModel)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()

                Menu {
                    ForEach(modelCatalog.providers) { provider in
                        Menu(provider.name) {
                            ForEach(provider.models) { model in
                                Button(model.name) {
                                    appState.aiProvider = provider.id
                                    appState.aiModel = model.id
                                    appState.saveSettings()
                                }
                            }
                        }
                    }
                } label: {
                    Text("Model")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .frame(height: 20)
                }
                .menuStyle(.borderlessButton)

                Button {
                    _ = AgentService.shared.createNewChat(projectPath: appState.workspaceFolder?.path)
                } label: {
                    Text("New").font(.system(size: 10)).foregroundColor(.secondary).frame(height: 20)
                }
                .buttonStyle(.plain)

                Button {
                    appState.aiChatVisible = false
                    appState.toggleEditorMode(.aiAgent)
                } label: {
                    Text("Expand").font(.system(size: 10)).foregroundColor(.secondary).frame(height: 20)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { appState.aiChatVisible = false }
                } label: {
                    Text("Close").font(.system(size: 10)).foregroundColor(.secondary).frame(height: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            AIAgentView().environmentObject(appState)
        }
    }
}

// MARK: - Main Toolbar (VS Code Style)

struct MainToolbar: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 0) {
            // Left: Navigation buttons
            HStack(spacing: 2) {
                ToolbarButton(icon: "sidebar.left", isActive: appState.sidebarVisible) {
                    appState.toggleSidebar()
                }
                .help("Toggle Sidebar (⌘B)")
                
                Divider().frame(height: 16).padding(.horizontal, 6)
                
                ToolbarButton(icon: "folder") {
                    appState.openFolder()
                }
                .help("Open Folder")
                
                ToolbarButton(icon: "doc.badge.plus") {
                    appState.createNewFile()
                }
                .help("New File (⌘N)")
            }
            .padding(.leading, 8)
            
            Spacer()
            
            Spacer()
            
            // Right: Actions
            HStack(spacing: 2) {
                ToolbarButton(icon: "play.fill", color: .green) {
                    appState.runCode()
                }
                .help("Run Code (⌘R)")
                
                ToolbarButton(icon: "stop.fill", color: .red) {
                    appState.stopExecution()
                }
                .help("Stop Execution")
                .disabled(!appState.isExecuting)
                
                ToolbarButton(icon: "hammer.fill", color: .orange) {
                    appState.buildProject()
                }
                .help("Build & Run Project (⌘B)")
                
                ToolbarButton(icon: "safari.fill", color: .cyan) {
                    appState.editorMode = .browser
                    var port = "3000"
                    switch appState.currentProjectType {
                    case .php: port = "8000"
                    case .java, .go: port = "8080"
                    case .dotnet: port = "5000"
                    case .nodejs: port = "5173" // Vite default
                    default: port = "3000"
                    }
                    // Wait a slight moment for the browser view to mount if it wasn't already
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .browserNavigate, object: "http://localhost:\(port)")
                    }
                }
                .help("Live Preview (Web App)")

                Divider().frame(height: 16).padding(.horizontal, 6)

                ToolbarButton(icon: appState.currentProjectType.icon, color: appState.currentProjectType == .nodejs ? .green : appState.currentProjectType == .python ? .blue : appState.currentProjectType == .rust ? .orange : appState.currentProjectType == .dotnet ? .purple : .secondary) {
                    appState.showingProjectRuntime = true
                }
                .help("\(appState.currentProjectType.rawValue) Runtime")
                
                Divider().frame(height: 16).padding(.horizontal, 6)
                
                ToolbarButton(
                    icon: appState.editorMode == .code ? "sidebar.right" : "arrow.triangle.branch",
                    isActive: appState.editorMode == .code ? appState.agenticContextVisible : appState.gitPanelVisible
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        if appState.editorMode == .code {
                            appState.toggleAgenticContext()
                        } else {
                            appState.toggleGitPanel()
                        }
                    }
                }
                .help(appState.editorMode == .code ? "Toggle Context Panel" : "Toggle Git Panel")
                
                ToolbarButton(icon: "terminal", isActive: appState.consoleVisible) {
                    appState.toggleConsole()
                }
                .help("Toggle Console (⌘J)")
                
                ToolbarButton(icon: "sidebar.right", isActive: appState.showingPreviewView) {
                    withAnimation {
                        appState.showingPreviewView.toggle()
                        DeviceRuntimeService.shared.showingEmbeddedDeviceDock = appState.showingPreviewView
                    }
                }
                .help("Toggle Device Preview (⌥⌘P)")
                
                Divider().frame(height: 16).padding(.horizontal, 6)
                
                ToolbarButton(icon: "iphone") {
                    appState.showingSimulatorDialog = true
                }
                .help("Launch Simulator")
                
                Divider().frame(height: 16).padding(.horizontal, 6)
                
                // AI & Code Tools
                ToolbarButton(icon: "wand.and.stars") {
                    appState.showingRefactorProWindow = true
                }
                .help("AI Refactor (⌘R)")
                
                ToolbarButton(icon: "arrow.up.left.and.arrow.down.right") {
                    appState.showingExpandCodeWindow = true
                }
                .help("Expand Code")
                
                ToolbarButton(icon: "text.alignleft") {
                    appState.showingFormatCodeWindow = true
                }
                .help("Format Code (⌘⇧F)")
                
                ToolbarButton(icon: "brain.head.profile", isActive: appState.aiChatVisible || appState.editorMode == .aiAgent, color: (appState.aiChatVisible || appState.editorMode == .aiAgent) ? .purple : .primary) {
                    // Cursor-style: Toggle inline panel instead of switching mode
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if appState.editorMode == .aiAgent {
                            // If already in full agent mode, switch back to code
                            appState.toggleEditorMode(.code)
                        } else {
                            // Toggle the inline agent panel
                            appState.aiChatVisible.toggle()
                        }
                    }
                }
                .help("Toggle Agent Panel (⌘L)")
                
                ToolbarButton(icon: "globe", isActive: appState.editorMode == .browser, color: appState.editorMode == .browser ? .blue : .primary) {
                    appState.toggleEditorMode(.browser)
                }
                .help("IDE Browser (⌘⇧B)")
                
                ToolbarButton(icon: "chart.bar.doc.horizontal") {
                    appState.toggleConsole(tab: 3) // Open Console/Analysis tab
                }
                .help("Code Analysis")
                
                ToolbarButton(icon: "play.rectangle", isActive: appState.editorMode == .playground, color: appState.editorMode == .playground ? .accentColor : .primary) {
                    appState.toggleEditorMode(.playground)
                }
                .help("Playground Mode")
                
                ToolbarButton(icon: "book.pages", isActive: appState.editorMode == .notebook, color: appState.editorMode == .notebook ? .accentColor : .primary) {
                    appState.toggleEditorMode(.notebook)
                }
                .help("Cell Mode")

                ToolbarButton(icon: "atom", isActive: appState.editorMode == .science, color: appState.editorMode == .science ? .teal : .primary) {
                    appState.toggleEditorMode(.science)
                }
                .help("Science Mode")
                
                ToolbarButton(icon: "flowchart", isActive: appState.editorMode == .scenario, color: appState.editorMode == .scenario ? .orange : .primary) {
                    appState.toggleEditorMode(.scenario)
                }
                .help("Scenario Mode")
                
                ToolbarButton(icon: "paintbrush.pointed", isActive: appState.editorMode == .design, color: appState.editorMode == .design ? .pink : .primary) {
                    appState.toggleEditorMode(.design)
                }
                .help("UI Design (Figma-like)")
                
                ToolbarButton(icon: "network", isActive: appState.editorMode == .remoteX, color: appState.editorMode == .remoteX ? .cyan : .primary) {
                    appState.toggleEditorMode(.remoteX)
                }
                .help("Remote X")
                
                Divider().frame(height: 16).padding(.horizontal, 6)
                
                ToolbarButton(icon: "cube.box", color: .blue) {
                    appState.showingDotnetProject = true
                }
                .help(".NET Project")
                
                ToolbarButton(icon: "brain", color: .purple) {
                    appState.showingAITrainer = true
                }
                .help("AI Trainer")
                
                ToolbarButton(icon: "shippingbox.fill", color: .orange) {
                    appState.showingContainerView = true
                }
                .help("Apple Container")
                
                ToolbarButton(icon: "server.rack", color: .indigo) {
                    appState.showingDatabaseStudio = true
                }
                .help("Database Studio")
                
                ToolbarButton(icon: "network", isActive: appState.editorMode == .apiClient, color: appState.editorMode == .apiClient ? .accentColor : .primary) {
                    if appState.editorMode == .apiClient {
                        appState.setEditorMode(.code)
                    } else {
                        appState.openAPIStudio()
                    }
                }
                .help("API Studio")
                
                ToolbarButton(icon: "checklist", color: .green) {
                    appState.showingCICDView = true
                }
                .help("CI/CD Pipeline")
                
                Divider().frame(height: 16).padding(.horizontal, 6)
                
                // Collaboration
                ToolbarButton(icon: "person.2.fill", color: .cyan) {
                    appState.showingCollaborationView = true
                }
                .help("Realtime Collaboration")
                
                // Embedded Studio (Full Window Mode)
                ToolbarButton(icon: "cpu.fill", isActive: appState.editorMode == .embedded, color: .orange) {
                    appState.toggleEditorMode(.embedded)
                }
                .help("Embedded Studio")
                
                Divider().frame(height: 16).padding(.horizontal, 6)
                
                ToolbarButton(icon: "gearshape") {
                    appState.showingSettingsDialog = true
                }
                .help("Settings (⌘,)")
            }
            .padding(.trailing, 8)
        }
        .frame(height: 38)
        .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground))
    }
}

struct ToolbarButton: View {
    let icon: String
    var isActive: Bool = false
    var color: Color = .primary
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(isActive ? .accentColor : color)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovering || isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Navigator View (Sidebar)

struct NavigatorView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    var onOpenFile: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                
                Text(appState.workspaceFolder?.lastPathComponent ?? "No Folder")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: { appState.openFolder() }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Open Folder")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground))
            
            Divider()
            
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.compat(nsColor: .textBackgroundColor).opacity(0.5))
            .cornerRadius(6)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            
            // File Tree
            if appState.workspaceFolder != nil {
                // Performance: Using NSOutlineView wrapper (AuthenticFileTree) for efficiency
                AuthenticFileTree(
                    fileTree: $appState.fileTree,
                    revision: appState.fileTreeRevision,
                    backgroundColor: appState.appTheme.isGlass ? .clear : appState.appTheme.panelBackground,
                    onAction: { action in
                        handleAction(action)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let warning = appState.fileTreeLimitWarning {
                    Text(warning)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.035))
                }
            } else {
                EmptyNavigatorView()
            }
        }
        .background(
            Group {
                if appState.appTheme.isGlass {
                    VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                } else {
                    Color(nsColor: appState.appTheme.panelBackground)
                }
            }
        )
    }
    
    private func handleAction(_ action: FileTreeAction) {
        switch action {
        case .openFile(let node):
            Task { @MainActor in
                await appState.loadFile(url: URL(fileURLWithPath: node.path))
                onOpenFile?()
            }
        case .loadChildren(let node):
            Task { @MainActor in await appState.loadChildren(for: node.id) }
        case .createFolder(let node, let name):
            Task { @MainActor in await appState.createFolder(at: node.path, name: name) }
        case .rename(let node, let newName):
            Task { @MainActor in await appState.renameFile(at: node.path, to: newName) }
        case .delete(let node):
             try? FileManager.default.trashItem(at: URL(fileURLWithPath: node.path), resultingItemURL: nil)
             Task { @MainActor in await appState.refreshFileTree() }
        }
    }
}

// MARK: - Empty Navigator View

struct EmptyNavigatorView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 34, weight: .regular))
                .foregroundColor(.secondary.opacity(0.7))
            Text("No Folder Open")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Button("Open Folder") {
                appState.openFolder()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - File Tree Row

// MARK: - File Tree Row (Optimized)

struct FileTreeRow: View, Equatable {
    let node: FileNode
    let depth: Int
    let onAction: (FileTreeAction) -> Void
    
    @State private var isExpanded = false
    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var newName = ""
    @FocusState private var isTextFieldFocused: Bool
    
    // Equatable conformance: Only update if node or depth changes
    static func == (lhs: FileTreeRow, rhs: FileTreeRow) -> Bool {
        return lhs.node == rhs.node && lhs.depth == rhs.depth
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowContent
            
            // Recursive Children
            if isExpanded && node.isDirectory {
                ForEach(node.children) { child in
                    FileTreeRow(node: child, depth: depth + 1, onAction: onAction)
                }
            }
        }
    }
    
    private var rowContent: some View {
        HStack(spacing: 4) {
            // Expand arrow
            if node.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                    .onTapGesture {
                        toggleExpand()
                    }
            } else {
                Spacer().frame(width: 14)
            }
            
            // Icon & Name
            Image(systemName: node.isDirectory ? "folder.fill" : fileIcon(for: node.name))
                .font(.system(size: 13))
                .foregroundColor(node.isDirectory ? .blue : iconColor(for: node.name))
            
            if isRenaming {
                renameField
            } else {
                Text(node.name)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.leading, CGFloat(depth * 16) + 8)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isDirectory {
                toggleExpand()
            } else {
                onAction(.openFile(node))
            }
        }
        .contextMenu { contextMenuContent }
        .onHover { isHovering = $0 }
    }
    
    private var renameField: some View {
        TextField("", text: $newName)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($isTextFieldFocused)
            .onSubmit { commitRename() }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isTextFieldFocused = true
                }
            }
            .onChange(of: isTextFieldFocused) { focused in
                if !focused && isRenaming {
                    commitRename()
                }
            }
            .background(Color.accentColor.opacity(0.1))
    }
    
    private var contextMenuContent: some View {
        Group {
            if !node.isDirectory {
                Button("Preview in Dock") {
                    let fileURL = URL(fileURLWithPath: node.path)
                    PreviewDockService.shared.openFile(url: fileURL, makeActive: true)
                }
                
                Button("Preview Git Diff") {
                    PreviewDockService.shared.openGitDiff(for: node.path, makeActive: true)
                }
                
                Divider()
            }
            
            if node.isDirectory {
                Button("New Folder") {
                    let alert = NSAlert()
                    alert.messageText = "New Folder"
                    alert.informativeText = "Enter folder name:"
                    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
                    alert.accessoryView = input
                    alert.addButton(withTitle: "Create")
                    alert.addButton(withTitle: "Cancel")
                    
                    if alert.runModal() == .alertFirstButtonReturn {
                        onAction(.createFolder(node, input.stringValue))
                    }
                }
                Divider()
            }
            
            Button("Rename") {
                newName = node.name
                isRenaming = true
            }
            
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
            }
            
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.path, forType: .string)
            }
            
            Divider()
            
            Button(role: .destructive) {
                let alert = NSAlert()
                alert.messageText = "Delete \(node.name)?"
                alert.informativeText = "This action cannot be undone."
                alert.addButton(withTitle: "Delete")
                alert.addButton(withTitle: "Cancel")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    onAction(.delete(node))
                }
            } label: {
                Text("Delete")
                Image(systemName: "trash")
            }
        }
    }
    
    private func toggleExpand() {
        if node.isDirectory {
            if !isExpanded && !node.hasLoadedChildren {
                onAction(.loadChildren(node))
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }
        }
    }
    
    private func commitRename() {
        guard !newName.isEmpty && newName != node.name else {
            isRenaming = false
            return
        }
        isRenaming = false
        onAction(.rename(node, newName))
    }
    
    // MARK: - Helpers
    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "python.fill"
        case "js": return "javascript.fill"
        case "ts": return "typescript.fill"
        case "html": return "html.fill"
        case "css": return "css.fill"
        case "json": return "curlybraces.square.fill"
        case "md": return "doc.richtext.fill"
        case "png", "jpg", "jpeg", "gif": return "photo.fill"
        default: return "doc.text.fill"
        }
    }
    
    private func iconColor(for name: String) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "py": return .blue
        case "js": return .yellow
        case "ts": return .blue
        case "html": return .orange
        case "css": return .blue
        case "json": return .purple
        case "md": return .cyan
        default: return .secondary
        }
    }
}

enum FileTreeAction {
    case openFile(FileNode)
    case loadChildren(FileNode)
    case createFolder(FileNode, String)
    case rename(FileNode, String)
    case delete(FileNode)
}
// MARK: - Editor Area

struct EditorArea: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Group {
            switch appState.editorMode {
            case .science:
                ScienceModeView()
                    .environmentObject(appState)
            case .scenario:
                ScenarioView()
                    .environmentObject(appState)
            case .notebook:
                NotebookView()
                    .environmentObject(appState)
                    .onAppear { CrashReporter.shared.breadcrumb("EditorArea -> NotebookView (Cell mode)") }
            case .playground:
                PlaygroundView()
                    .environmentObject(appState)
                    .onAppear { CrashReporter.shared.breadcrumb("EditorArea -> PlaygroundView") }
            case .remoteX:
                RemoteXView()
            case .design:
                DesignWorkbenchView()
            case .embedded:
                EmbeddedStudioView()
                    .environmentObject(appState)
            case .aiAgent:
                AIAgentView()
                    .environmentObject(appState)
            case .browser:
                IDEBrowserView()
                    .environmentObject(appState)
            case .apiClient:
                APIClientView()
                    .environmentObject(appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .code:
                CompatHSplitView {
                    VStack(spacing: 0) {
                        if !appState.openFiles.isEmpty {
                            EditorTabBar()
                        }
                        
                        if let file = appState.currentFile,
                           appState.currentFileIndex >= 0,
                           appState.currentFileIndex < appState.openFiles.count {
                            let fileURL = URL(fileURLWithPath: file.path)
                            let ext = fileURL.pathExtension.lowercased()
                            let previewExtensions = ["png", "jpg", "jpeg", "pdf", "gif", "bmp", "tiff", "webp", "xlsx", "xls", "csv", "tsv", "numbers", "svg"]
                            
                            if previewExtensions.contains(ext) {
                                let fileType = PreviewFileType.detect(url: fileURL)
                                Group {
                                    switch fileType {
                                    case .image:
                                        InteractiveImagePreviewView(url: fileURL)
                                    case .pdf:
                                        InteractivePDFPreviewView(url: fileURL)
                                    case .spreadsheet:
                                        UniversalSpreadsheetView(url: fileURL)
                                    default:
                                        UniversalFilePreview(url: fileURL)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                CodeEditor(file: file)
                                    .id(file.id) // Force fresh NSTextView per file to prevent stale highlight crash
                            }
                        } else if appState.workspaceFolder != nil {
                            // Empty State (Folder open, no file selected)
                            VStack(spacing: 16) {
                                Spacer()
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary.opacity(0.2))
                                Text("Select a file to view")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            WelcomeScreen()
                        }
                        
                        if appState.consoleVisible {
                            DebugArea()
                        }
                    }
                    .background(
                        Group {
                            if appState.appTheme.isGlass {
                                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                            } else {
                                Color.compat(nsColor: appState.appTheme.editorBackground)
                            }
                        }
                    )
                    
                    // Live iPhone preview canvas on the right (collapsible)
                    if appState.showingPreviewView {
                        RightPreviewPanel()
                    }
                }
            }
        }
        .id(appState.editorMode.rawValue)  // Force re-render when mode changes
    }
}

// MARK: - Xcode-style Editor Breadcrumbs

struct EditorBreadcrumbBar: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 6) {
            if let file = appState.currentFile {
                let segments = getBreadcrumbSegments(file: file)
                
                HStack(spacing: 6) {
                    ForEach(0..<segments.count, id: \.self) { index in
                        let seg = segments[index]
                        
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: seg.icon)
                                .font(.system(size: 11))
                                .foregroundColor(seg.color)
                            
                            Text(seg.name)
                                .font(.system(size: 11, weight: index == segments.count - 1 ? .medium : .regular))
                                .foregroundColor(index == segments.count - 1 ? .primary : .secondary)
                        }
                    }
                }
            } else {
                Text("No File Open")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            appState.appTheme == .extraClear 
            ? Color.clear 
            : Color.compat(nsColor: .windowBackgroundColor).opacity(0.8)
        )
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.15))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    struct Segment {
        let name: String
        let icon: String
        let color: Color
    }
    
    private func getBreadcrumbSegments(file: CodeFile) -> [Segment] {
        var segments: [Segment] = []
        
        if let workspace = appState.workspaceFolder {
            segments.append(Segment(name: workspace.lastPathComponent, icon: "folder.fill", color: .accentColor))
            
            let fileURL = URL(fileURLWithPath: file.path)
            let workspaceURL = workspace
            
            let filePath = fileURL.path
            let workspacePath = workspaceURL.path
            
            if filePath.hasPrefix(workspacePath) {
                let relativePath = String(filePath.dropFirst(workspacePath.count))
                let parts = relativePath.split(separator: "/").map { String($0) }
                
                for i in 0..<parts.count {
                    let part = parts[i]
                    if i == parts.count - 1 {
                        segments.append(Segment(name: part, icon: iconForFile(part), color: colorForFile(part)))
                    } else {
                        let isTarget = i == 0
                        segments.append(Segment(name: part, icon: isTarget ? "square.grid.3x1.below.line.grid.1x2" : "folder.fill", color: isTarget ? .orange : .secondary))
                    }
                }
            } else {
                segments.append(Segment(name: file.name, icon: iconForFile(file.name), color: colorForFile(file.name)))
            }
        } else {
            segments.append(Segment(name: file.name, icon: iconForFile(file.name), color: colorForFile(file.name)))
        }
        
        return segments
    }
    
    private func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "curlybraces.square"
        case "js", "ts": return "curlybraces"
        case "rs": return "gearshape.2"
        case "json": return "curlybraces.square"
        case "md": return "doc.richtext"
        default: return "doc.text"
        }
    }
    
    private func colorForFile(_ name: String) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "py": return .green
        case "js": return .yellow
        case "ts": return .blue
        case "rs": return .orange
        default: return .secondary
        }
    }
}

// MARK: - Right Preview Panel (Genuine Real-Device Simulator & Emulator View)

struct RightPreviewPanel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var deviceRuntime = DeviceRuntimeService.shared

    private var currentDeviceName: String {
        if deviceRuntime.showingEmbeddedAppleDock {
            return deviceRuntime.selectedApplePreviewTitle
        } else {
            if let serial = deviceRuntime.embeddedAndroidSerial, !serial.isEmpty {
                return "Android: \(serial)"
            }
            if let dev = deviceRuntime.selectedDevice, dev.platform == .android {
                return dev.name
            }
            return "Android Emulator"
        }
    }

    var body: some View {
        EmbeddedDeviceDockView()
            .environmentObject(appState)
            .frame(minWidth: 380, idealWidth: 440, maxWidth: 540)
            .background(
                Color(nsColor: appState.appTheme.editorBackground)
            )
        .onAppear {
            autoSelectPlatform()
            Task {
                await deviceRuntime.refresh(workspace: appState.workspaceFolder)
            }
        }
        .onChange(of: appState.currentFile?.path) { _ in
            autoSelectPlatform()
        }
    }

    private func autoSelectPlatform() {
        guard let file = appState.currentFile else { return }
        let ext = (file.name as NSString).pathExtension.lowercased()
        let path = file.path.lowercased()
        if ["kt", "kts", "java", "xml"].contains(ext) || path.contains("/android/") || path.contains("/res/") {
            deviceRuntime.showingEmbeddedAppleDock = false
            deviceRuntime.showingEmbeddedDeviceDock = true
            Task { await deviceRuntime.startPreferredEmbeddedAndroid() }
        } else if ["swift", "storyboard", "xib", "plist"].contains(ext) || path.contains("/ios/") {
            deviceRuntime.showingEmbeddedAppleDock = true
            deviceRuntime.showingEmbeddedDeviceDock = true
            Task { await deviceRuntime.startPreferredEmbeddedAppleSimulator() }
        }
    }
}

// MARK: - Editor Tab Bar

struct EditorTabBar: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(appState.openFiles.enumerated()), id: \.element.id) { index, file in
                    EditorTab(
                        file: file,
                        isSelected: index == appState.currentFileIndex,
                        onSelect: { appState.currentFileIndex = index },
                        onClose: { appState.closeFile(at: index) }
                    )
                }
                Spacer()
            }
        }
        .frame(height: 36)
        .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground))
    }
}

// MARK: - Editor Tab

struct EditorTab: View {
    @EnvironmentObject var appState: AppState
    let file: CodeFile
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 6) {
            // File icon
            Image(systemName: iconForFile(file.name))
                .font(.system(size: 11))
                .foregroundColor(colorForFile(file.name))
            
            // File name
            Text(file.name)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? .primary : .secondary)
            
            // Modified indicator
            if file.isUnsaved {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }
            
            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isHovering || isSelected ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isSelected 
                ? (appState.appTheme == .extraClear ? Color.white.opacity(0.1) : Color.compat(nsColor: .textBackgroundColor))
                : (isHovering ? Color.secondary.opacity(0.1) : Color.clear)
        )
        .overlay(
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(height: 2),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
    
    private func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "js", "ts": return "curlybraces"
        case "rs": return "gearshape.2"
        case "json": return "curlybraces.square"
        case "md": return "doc.richtext"
        default: return "doc.text"
        }
    }
    
    private func colorForFile(_ name: String) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "py": return .green
        case "js": return .yellow
        case "ts": return .blue
        case "rs": return .orange
        default: return .secondary
        }
    }
}

// MARK: - Code Editor

struct CodeEditor: View {
    let file: CodeFile
    @EnvironmentObject var appState: AppState
    @State private var text: String = ""
    @State private var updateTask: Task<Void, Never>? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb bar
            HStack(spacing: 6) {
                ForEach(breadcrumbComponents(), id: \.self) { component in
                    HStack(spacing: 4) {
                        Text(component)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        if component != breadcrumbComponents().last {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }
                Spacer()
                
                // Language selection menu
                Menu {
                    Button("Auto Detect") { appState.updateFileLanguage(appState.detectLanguage(from: URL(fileURLWithPath: file.path)), for: file.id) }
                    Divider()
                    Button("Swift") { appState.updateFileLanguage("swift", for: file.id) }
                    Button("Python") { appState.updateFileLanguage("python", for: file.id) }
                    Button("JavaScript") { appState.updateFileLanguage("typescript", for: file.id) } // JS/TS handled as TS
                    Button("TypeScript") { appState.updateFileLanguage("typescript", for: file.id) }
                    Button("Rust") { appState.updateFileLanguage("rust", for: file.id) }
                    Button("Go") { appState.updateFileLanguage("go", for: file.id) }
                    Button("HTML") { appState.updateFileLanguage("html", for: file.id) }
                    Button("CSS") { appState.updateFileLanguage("css", for: file.id) }
                    Button("JSON") { appState.updateFileLanguage("json", for: file.id) }
                    Button("Markdown") { appState.updateFileLanguage("markdown", for: file.id) }
                } label: {
                    Text(file.language.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(languageColor(file.language))
                        .cornerRadius(3)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.compat(nsColor: .windowBackgroundColor).opacity(0.5))
            
            Divider()

            if file.isReadOnly || file.usesPlainTextMode {
                HStack(spacing: 8) {
                    Text(file.isTruncated ? "Large-file preview" : "Performance mode")
                        .font(.system(size: 10, weight: .semibold))
                    Text(file.isTruncated
                         ? "Showing a read-only preview of \(formattedByteCount(file.originalByteSize))."
                         : "Syntax highlighting and LSP are disabled for this file.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.04))

                Divider()
            }
            
            // Code Editor with Syntax Highlighting Engine
            ZStack(alignment: .topLeading) {
                SyntaxHighlightedCodeView(
                    text: $text,
                    language: file.language,
                    fontSize: appState.fontSize,
                    isDark: appState.appTheme.isDark,
                    themeName: appState.appTheme.rawValue,
                    fileURL: URL(fileURLWithPath: file.path),
                    isEditable: !file.isReadOnly,
                    enableHighlighting: !file.usesPlainTextMode,
                    showLineNumbers: appState.showLineNumbers && !file.usesPlainTextMode,
                    editorID: "file-\(file.id.uuidString)"
                )
                
                if appState.showingCompletions {
                    AutocompletePopupView(appState: appState) { item in
                        NotificationCenter.default.post(
                            name: Notification.Name("InsertLSPCompletionItem"),
                            object: nil,
                            userInfo: ["item": item]
                        )
                    }
                    .offset(x: appState.autocompleteRect.origin.x, y: appState.autocompleteRect.origin.y + 15) // offset below the cursor line
                    .zIndex(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { text = file.content }
        .onChange(of: file.id) { _ in text = file.content }
        .onChange(of: file.content) { newContent in
            if !file.isUnsaved { text = newContent }
        }
        .onChange(of: text) { newValue in
            guard !file.isReadOnly else { return }
            // Debounce state updates to prevent re-render loops and high CPU
            updateTask?.cancel()
            updateTask = Task {
                // Wait for 500ms of inactivity before syncing to AppState
                try? await Task.sleep(nanoseconds: 500_000_000)
                
                guard !Task.isCancelled else { return }
                
                if newValue != file.content {
                    await MainActor.run {
                        appState.updateFileContent(newValue, for: file.id)
                    }
                }
            }
        }
    }

    private func formattedByteCount(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
    
    private func breadcrumbComponents() -> [String] {
        if file.path.isEmpty { return [file.name] }
        let components = file.path.split(separator: "/").map(String.init)
        return Array(components.suffix(3))
    }
    
    private func languageColor(_ lang: String) -> Color {
        switch lang {
        case "swift": return .orange
        case "python": return Color(red: 0.2, green: 0.5, blue: 0.8)
        case "javascript": return .yellow
        case "typescript": return .blue
        case "rust": return Color(red: 0.8, green: 0.3, blue: 0.1)
        case "go": return .cyan
        default: return .gray
        }
    }
}



// MARK: - Line Numbers View (SwiftUI)

struct LineNumbersView: View {
    let text: String
    let fontSize: CGFloat
    
    private var lineCount: Int {
        max(1, text.components(separatedBy: "\n").count)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(1...lineCount, id: \.self) { lineNumber in
                    Text("\(lineNumber)")
                        .font(.system(size: fontSize - 1, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(height: fontSize * 1.4)
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))
    }
}

// MARK: - Syntax Highlighted Editor View (NSTextView with Rich Text)

struct SyntaxHighlightedEditorView: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let language: String
    let theme: AppTheme
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        textView.delegate = context.coordinator
        
        // Enable rich text for syntax highlighting
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        
        // Disable smart substitutions
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        
        // Appearance
        textView.backgroundColor = theme.editorBackground
        textView.insertionPointColor = theme.editorText
        textView.textContainerInset = NSSize(width: 5, height: 8)
        
        // ScrollView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.editorBackground
        
        // Line Numbers
        // Line Numbers (Disabled temporarily)
        // scrollView.rulersVisible = true
        // let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        // scrollView.verticalRulerView = ruler
        
        // Apply syntax highlighted text with guaranteed visible colors
        let highlighted = createHighlightedText(text, language: language, fontSize: fontSize, theme: theme)
        textView.textStorage?.setAttributedString(highlighted)
        
        return scrollView
    }
    
    // Custom highlighting with explicit colors
    private func createHighlightedText(_ code: String, language: String, fontSize: CGFloat, theme: AppTheme) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: code)
        let fullRange = NSRange(location: 0, length: code.utf16.count)
        
        // Use explicit contrasting colors based on background
        let isDark = theme.isDark
        let textColor = isDark ? NSColor.white : NSColor.black
        let keywordColor = isDark ? NSColor.systemPink : NSColor.systemPurple
        let stringColor = isDark ? NSColor.systemOrange : NSColor.systemRed
        let commentColor = isDark ? NSColor.systemGreen : NSColor.systemGray
        let numberColor = isDark ? NSColor.systemYellow : NSColor.systemBrown
        let typeColor = isDark ? NSColor.systemCyan : NSColor.systemBlue
        
        // Set base attributes
        attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), range: fullRange)
        attributedString.addAttribute(.foregroundColor, value: textColor, range: fullRange)
        
        // Highlight patterns
        let patterns: [(String, NSColor)] = [
            ("//[^\\n]*", commentColor),                              // Single-line comments
            ("#[^\\n]*", commentColor),                               // Python comments
            ("/\\*[\\s\\S]*?\\*/", commentColor),                     // Multi-line comments
            ("\"[^\"\\\\]*(\\\\.[^\"\\\\]*)*\"", stringColor),         // Double-quoted strings
            ("'[^'\\\\]*(\\\\.[^'\\\\]*)*'", stringColor),            // Single-quoted strings
            ("`[^`]*`", stringColor),                                 // Template strings
            ("\\b\\d+(\\.\\d+)?\\b", numberColor),                    // Numbers
            ("\\b0x[0-9a-fA-F]+\\b", numberColor),                    // Hex numbers
            ("\\b[A-Z][a-zA-Z0-9_]*\\b", typeColor),                  // Types
        ]
        
        for (pattern, color) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                regex.enumerateMatches(in: code, options: [], range: fullRange) { match, _, _ in
                    if let matchRange = match?.range {
                        attributedString.addAttribute(.foregroundColor, value: color, range: matchRange)
                    }
                }
            }
        }
        
        // Highlight keywords
        let keywords: [String] = ["func", "class", "struct", "enum", "if", "else", "for", "while", "return", "let", "var", "import", "def", "from", "async", "await", "try", "catch", "throw", "const", "function", "fn", "pub", "use", "mod", "impl", "trait", "where", "true", "false", "nil", "None", "null", "self", "super"]
        
        for keyword in keywords {
            let pattern = "\\b\(keyword)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                regex.enumerateMatches(in: code, options: [], range: fullRange) { match, _, _ in
                    if let matchRange = match?.range {
                        attributedString.addAttribute(.foregroundColor, value: keywordColor, range: matchRange)
                    }
                }
            }
        }
        
        return attributedString
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              let textStorage = textView.textStorage else { return }
        
        // Update appearance
        textView.backgroundColor = theme.editorBackground
        textView.insertionPointColor = theme.isDark ? NSColor.white : NSColor.black
        scrollView.backgroundColor = theme.editorBackground
        
        // Check if text changed externally
        if textView.string != text {
            let selection = textView.selectedRange()
            let highlighted = createHighlightedText(text, language: language, fontSize: fontSize, theme: theme)
            textStorage.setAttributedString(highlighted)
            
            // Restore selection
            let maxLen = (text as NSString).length
            let safeLoc = min(selection.location, maxLen)
            textView.setSelectedRange(NSRange(location: safeLoc, length: 0))
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxHighlightedEditorView
        var isUpdating = false
        var highlightTimer: Timer?
        
        init(_ parent: SyntaxHighlightedEditorView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isUpdating else { return }
            
            // Update binding
            parent.text = textView.string
            
            // Debounce syntax highlighting
            highlightTimer?.invalidate()
            highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                self?.applyHighlighting(to: textView)
            }
        }
        
        private func applyHighlighting(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            isUpdating = true
            
            let selection = textView.selectedRange()
            let highlighted = parent.createHighlightedText(
                textView.string,
                language: parent.language,
                fontSize: parent.fontSize,
                theme: parent.theme
            )
            textStorage.setAttributedString(highlighted)
            
            // Restore selection
            let maxLen = (textView.string as NSString).length
            let safeLoc = min(selection.location, maxLen)
            let safeLen = min(selection.length, maxLen - safeLoc)
            textView.setSelectedRange(NSRange(location: safeLoc, length: safeLen))
            
            isUpdating = false
        }
    }
}

// MARK: - Text Editor View (NSTextView)

// MARK: - Code Text View (Subclass for Context Menu)

class CodeTextView: NSTextView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        
        // Ensure we have standard items if they are missing
        if menu.items.isEmpty {
            menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        }
        
        // Add custom items if needed
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Format Document", action: #selector(formatDocument), keyEquivalent: "i")
        
        return menu
    }
    
    @objc func formatDocument() {
        // Trigger formatting via responder chain or notification
        // For now, we rely on the main menu or button, this is just a placeholder action
        // In a real app, we'd route this to the AppState
        NSApp.sendAction(#selector(validateMenuItem(_:)), to: nil, from: self)
    }
}

struct TextEditorView: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let language: String
    let theme: AppTheme
    
    func makeNSView(context: Context) -> NSScrollView {
        // Use Apple's standard factory method - guaranteed to work
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        // Store reference for delegate
        textView.delegate = context.coordinator
        
        // Basic text view settings
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isRichText = false  // Plain text mode
        textView.importsGraphics = false
        textView.usesFontPanel = false
        
        // Disable smart substitutions for code editing
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        
        // Appearance
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = theme.editorText
        textView.backgroundColor = theme.editorBackground
        textView.insertionPointColor = theme.editorText
        textView.textContainerInset = NSSize(width: 5, height: 8)
        
        // ScrollView appearance
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.editorBackground
        
        // Setup Line Numbers (Disabled temporarily)
        // scrollView.rulersVisible = true
        // let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        // scrollView.verticalRulerView = ruler
        
        // Set the text content
        textView.string = text
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        // Update colors for theme change
        textView.backgroundColor = theme.editorBackground
        textView.textColor = theme.editorText
        textView.insertionPointColor = theme.editorText
        scrollView.backgroundColor = theme.editorBackground
        
        // Sync text if changed externally
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            
            // Restore selection safely
            let maxLocation = (text as NSString).length
            let safeLocation = min(selection.location, maxLocation)
            let safeLength = min(selection.length, maxLocation - safeLocation)
            textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
        }
        
        // Update font if changed
        if textView.font?.pointSize != fontSize {
            textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextEditorView
        var isUpdating = false
        var highlightTimer: Timer?
        var currentTheme: AppTheme
        
        init(_ parent: TextEditorView) { 
            self.parent = parent
            self.currentTheme = parent.theme
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isUpdating else { return }
            
            parent.text = textView.string
            
            // Debounce syntax highlighting for performance
            highlightTimer?.invalidate()
            highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                self?.applyHighlighting(to: textView)
            }
        }
        
        private func applyHighlighting(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            isUpdating = true
            
            let selection = textView.selectedRange()
            let highlightedText = SyntaxHighlighter.shared.highlight(
                textView.string,
                language: parent.language,
                fontSize: parent.fontSize,
                theme: parent.theme
            )
            textStorage.setAttributedString(highlightedText)
            
            // Restore selection
            let safeLocation = min(selection.location, textView.string.utf16.count)
            let safeLength = min(selection.length, textView.string.utf16.count - safeLocation)
            textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
            
            isUpdating = false
        }
    }
}

// MARK: - Debug Area (Interactive Terminal)

struct DebugArea: View {
    @EnvironmentObject var appState: AppState

    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with tabs
            HStack(spacing: 0) {
                // Tabs
                HStack(spacing: 0) {
                    ConsoleTabButton(title: "OUTPUT", isSelected: appState.selectedConsoleTab == 0) { appState.selectedConsoleTab = 0 }
                    ConsoleTabButton(title: "TERMINAL", isSelected: appState.selectedConsoleTab == 1) { appState.selectedConsoleTab = 1 }
                    ConsoleTabButton(title: "PROBLEMS", isSelected: appState.selectedConsoleTab == 2) { appState.selectedConsoleTab = 2 }
                    ConsoleTabButton(title: "ANALYSIS", isSelected: appState.selectedConsoleTab == 3) { appState.selectedConsoleTab = 3 }
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Button(action: { appState.consoleOutput = "" }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Clear")
                    
                    Button(action: { appState.toggleConsole() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Close")
                }
                .padding(.trailing, 8)
            }
            .frame(height: 28)
            .background(appState.appTheme == .extraClear ? Color.clear : Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content based on tab
            switch appState.selectedConsoleTab {
            case 0: // Output
                ScrollViewReader { proxy in
                     ScrollView {
                        Text(appState.consoleOutput.isEmpty ? "No output yet. Run code with ⌘R" : appState.consoleOutput)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(appState.consoleOutput.isEmpty ? Color(nsColor: appState.appTheme.commentColor) : Color(nsColor: appState.appTheme.editorText))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .id("bottom")
                            .compatTextSelection()
                    }
                    .onChange(of: appState.consoleOutput) { _ in
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .frame(minHeight: 100, maxHeight: 300)
                .background(appState.appTheme == .extraClear ? Color.clear : Color(nsColor: appState.appTheme.editorBackground))
                
            case 1: // Terminal
                AuthenticTerminal(
                    shell: "/bin/zsh",
                    fontName: appState.playgroundFontName,
                    fontSize: 13,
                    textColor: appState.appTheme.editorText,
                    backgroundColor: appState.appTheme.editorBackground,
                    isTransparent: appState.appTheme == .extraClear
                )
                .frame(minHeight: 120, maxHeight: 350)
                .background(appState.appTheme == .extraClear ? Color.clear : Color(nsColor: appState.appTheme.editorBackground))
                
            case 2: // Problems
                VStack {
                    Text("No problems detected")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minHeight: 100, maxHeight: 300)
                .background(appState.appTheme == .extraClear ? Color.clear : Color(nsColor: .textBackgroundColor))
                
            case 3: // Analysis
                CodeAnalysisPanel()
                    .environmentObject(appState)
                    .frame(minHeight: 200, maxHeight: 400)
                
            default:
                EmptyView()
            }
        }
    }

}

struct ConsoleTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isSelected ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Welcome Screen

enum WelcomeTab {
    case projects
    case templates
    case aiArchitect
    case settings
}

struct WelcomeScreen: View {
    @EnvironmentObject var appState: AppState
    var surface: Binding<AgenticWorkspaceSurface>? = nil
    
    @State private var recentProjects: [URL] = []
    @State private var selectedTab: WelcomeTab = .projects
    @State private var aiPrompt: String = ""
    @State private var isHoveringAI: Bool = false
    
    // For Clone Repository
    @State private var showCloneSheet: Bool = false
    @State private var gitCloneUrl: String = ""
    @State private var isCloning: Bool = false
    @State private var cloneError: String? = nil
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left Sidebar Panel
                leftSidebarView
                
                Divider()
                    .background(Color.primary.opacity(0.1))
                
                // Right Main Panel
                rightMainView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                appState.appTheme.isGlass
                    ? AnyView(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
                    : AnyView(Color(nsColor: appState.appTheme.workspaceBackground))
            )
        }
        .onAppear {
            loadRecentProjects()
            appState.checkDerivedDataSize()
        }
        .sheet(isPresented: $showCloneSheet) {
            cloneSheetView
        }
    }
    
    private func loadRecentProjects() {
        recentProjects = AppState.getRecentWorkspaces()
    }
    
    private func createProject(_ type: String) {
        let prompt: String
        switch type {
        case "nextjs":
            prompt = "Please scaffold a new Next.js 14 App (TypeScript, Tailwind CSS, App Router) in this workspace. Initialize standard project structure and packages."
        case "vite":
            prompt = "Please scaffold a new Vite + React + TypeScript web app in this workspace with Tailwind CSS and standard config."
        case "fastapi":
            prompt = "Please scaffold a modern Python 3.12 FastAPI project in this workspace with main.py, requirements.txt, Pydantic models, and sample endpoints."
        case "rust-axum":
            prompt = "Please initialize a new Rust Axum asynchronous web microservice in this workspace with Cargo.toml and src/main.rs."
        case "swift":
            prompt = "Please create a new native Apple macOS/iOS SwiftUI application in this workspace with Package.swift or Xcode structure."
        case "ardium":
            prompt = "Please create a new Ardium v2.3 project with CoreUI in this workspace."
        case "express":
            prompt = "Please scaffold a TypeScript Express.js REST API in this workspace with package.json, src/index.ts, and routing."
        case "go":
            prompt = "Please initialize a new Go microservice with Gin in this workspace with go.mod and main.go."
        case "flutter":
            prompt = "Please scaffold a cross-platform Flutter app in this workspace with pubspec.yaml and lib/main.dart."
        case "spring":
            prompt = "Please scaffold a Java 21 Spring Boot 3 microservice in this workspace with pom.xml and Application.java."
        case "pytorch":
            prompt = "Please scaffold a Python PyTorch machine learning pipeline in this workspace with model definition, train.py, and requirements.txt."
        case "docker":
            prompt = "Please generate a Dockerized multi-service development stack with docker-compose.yml, PostgreSQL, Redis, and sample API."
        case "vue":
            prompt = "Please scaffold a Vue 3 + Vite + TypeScript application in this workspace with App.vue and main.ts."
        case "nestjs":
            prompt = "Please scaffold a NestJS enterprise TypeScript API in this workspace with nest-cli config, modules, and controllers."
        default:
            prompt = "Please initialize a new \(type) project in this workspace."
        }
        selectFolderAndRunAI(prompt: prompt)
    }
    
    private func selectFolderAndRunAI(prompt: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.title = "Select a folder for the new project"
        panel.prompt = "Select Workspace"
        
        if panel.runModal() == .OK, let url = panel.url {
            AppState.recordRecentWorkspace(url: url)
            loadRecentProjects()
            appState.showingWelcomeHome = false
            Task { @MainActor in
                await appState.openWorkspace(url: url)
            }
            surface?.wrappedValue = .agent
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                appState.aiChatVisible = true
                Task {
                    await AgentService.shared.sendMessage(prompt)
                }
            }
        }
    }
    
    private func openFolder() {
        appState.openFolder()
    }

    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.3.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) · Build \(build)"
    }
    
    // MARK: - Left Sidebar View
    
    private var leftSidebarView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MicroCode")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(appVersionString)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal)
            .padding(.top, 30)
            
            // Sidebar Menu
            VStack(spacing: 6) {
                sidebarButton(title: "Projects", icon: "folder", tab: .projects)
                sidebarButton(title: "Templates", icon: "square.grid.2x2", tab: .templates)
                sidebarButton(title: "AI Architect", icon: "sparkles", tab: .aiArchitect)
                sidebarButton(title: "Settings", icon: "gearshape", tab: .settings)
            }
            .padding(.horizontal, 10)
            
            Spacer()
            
            // Footer Info
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Silicon Native")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.primary.opacity(0.6))
                        .frame(width: 6, height: 6)
                    Text("LSP Services Active")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 25)
        }
        .frame(width: 210)
        .background(
            appState.appTheme.isGlass
                ? AnyView(VisualEffectView(material: .sidebar, blendingMode: .behindWindow).opacity(0.5))
                : AnyView(Color(nsColor: appState.appTheme.panelBackground))
        )
    }
    
    private func sidebarButton(title: String, icon: String, tab: WelcomeTab) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                selectedTab == tab
                ? Color.primary.opacity(0.1)
                : Color.clear
            )
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Right Main View
    
    private var rightMainView: some View {
        ZStack {
            if selectedTab == .aiArchitect {
                AIAgentView(allowsChatSidebar: true)
                    .environmentObject(appState)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        switch selectedTab {
                        case .projects:
                            projectsTabContent
                        case .templates:
                            templatesTabContent
                        case .settings:
                            settingsTabContent
                        case .aiArchitect:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 35)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            appState.appTheme.isGlass
                ? AnyView(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
                : AnyView(Color(nsColor: appState.appTheme.workspaceBackground))
        )
    }
    
    // MARK: - Projects Tab
    
    private var projectsTabContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to MicroCode")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("Start a new project, run interactive scratchpads, or connect remote cloud instances.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 6)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ], spacing: 14) {
                QuickActionCard(
                    title: "New Project",
                    subtitle: "Choose from 14+ boilerplates",
                    icon: "plus.square"
                ) {
                    selectedTab = .templates
                }
                
                QuickActionCard(
                    title: "Open Folder",
                    subtitle: "Open an existing workspace",
                    icon: "folder"
                ) {
                    openFolder()
                }
                
                QuickActionCard(
                    title: "Clone Repo",
                    subtitle: "Checkout from Git remote",
                    icon: "arrow.down.circle"
                ) {
                    showCloneSheet = true
                }
                
                QuickActionCard(
                    title: "New Playground Mode",
                    subtitle: "Scratchpad & live code execution",
                    icon: "play.laptopcomputer",
                    badge: "Instant"
                ) {
                    surface?.wrappedValue = .editor
                    appState.showingWelcomeHome = false
                    appState.setEditorMode(.playground)
                }
                
                QuickActionCard(
                    title: "New Cell Mode",
                    subtitle: "Multi-language interactive notebook",
                    icon: "square.split.1x2.fill",
                    badge: "Cells"
                ) {
                    surface?.wrappedValue = .editor
                    appState.showingWelcomeHome = false
                    appState.setEditorMode(.notebook)
                }
                
                QuickActionCard(
                    title: "SSH Remote Browser",
                    subtitle: "Cloud instances & remote shell",
                    icon: "terminal.fill",
                    badge: "Remote"
                ) {
                    surface?.wrappedValue = .editor
                    appState.showingWelcomeHome = false
                    appState.setEditorMode(.remoteX)
                }
                
                QuickActionCard(
                    title: "Embed & IoT Studio",
                    subtitle: "Hardware flashing, serial & GPIO monitor",
                    icon: "cpu.fill",
                    badge: "IoT"
                ) {
                    surface?.wrappedValue = .editor
                    appState.showingWelcomeHome = false
                    appState.setEditorMode(.embedded)
                }
                
                QuickActionCard(
                    title: "AI Architect",
                    subtitle: "Chat & autonomous scaffolding",
                    icon: "sparkles",
                    badge: "Agent"
                ) {
                    selectedTab = .aiArchitect
                }
                
                QuickActionCard(
                    title: "IDE Web Browser",
                    subtitle: "Built-in live browser & previews",
                    icon: "globe"
                ) {
                    surface?.wrappedValue = .editor
                    appState.showingWelcomeHome = false
                    appState.setEditorMode(.browser)
                }
                
                QuickActionCard(
                    title: "Settings & Cache",
                    subtitle: "Manage DerivedData & disk quotas",
                    icon: "gearshape"
                ) {
                    selectedTab = .settings
                }
            }
            
            VStack(alignment: .leading, spacing: 14) {
                Text("Recent Workspaces")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                
                if recentProjects.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.7))
                        Text("No recent projects found")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(recentProjects.prefix(8), id: \.self) { url in
                            RecentProjectRow(url: url) {
                                surface?.wrappedValue = .editor
                                appState.showingWelcomeHome = false
                                Task { @MainActor in
                                    await appState.openWorkspace(url: url)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, 10)
        }
    }
    
    // MARK: - Templates Tab
    
    private var templatesTabContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Select a Template")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("Bootstrap projects instantly with built-in presets. Conforms strictly to your active theme.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                TemplateDetailCard(title: "Next.js 14 App", subtitle: "Fullstack React framework with App Router, TypeScript, and Server Components.", icon: "n.square.fill", tag: "Fullstack") { createProject("nextjs") }
                TemplateDetailCard(title: "Vite + React", subtitle: "Blazing fast frontend SPA with TypeScript and Hot Module Replacement.", icon: "atom", tag: "Frontend") { createProject("vite") }
                TemplateDetailCard(title: "FastAPI Backend", subtitle: "High-performance async Python API with Pydantic v2 and OpenAPI docs.", icon: "bolt.fill", tag: "Python") { createProject("fastapi") }
                TemplateDetailCard(title: "Rust Axum Service", subtitle: "Ultra-fast asynchronous microservice powered by Tokio runtime.", icon: "gearshape.2.fill", tag: "Rust") { createProject("rust-axum") }
                TemplateDetailCard(title: "SwiftUI App", subtitle: "Native Apple platforms application using SwiftUI declarative framework.", icon: "swift", tag: "Apple Native") { createProject("swift") }
                TemplateDetailCard(title: "Ardium CoreUI", subtitle: "High-performance native GUI using Dotmini's Ardium v2.3 language.", icon: "cpu.fill", tag: "Ardium") { createProject("ardium") }
                TemplateDetailCard(title: "Express.js API", subtitle: "Lightweight, scalable Node.js microservice API with TypeScript.", icon: "server.rack", tag: "Node.js") { createProject("express") }
                TemplateDetailCard(title: "Go Gin Microservice", subtitle: "High-throughput compiled HTTP web API with minimal footprint.", icon: "speedometer", tag: "Go") { createProject("go") }
                TemplateDetailCard(title: "Flutter Multiplatform", subtitle: "Cross-platform mobile, desktop, and web application with Dart.", icon: "apps.iphone", tag: "Dart") { createProject("flutter") }
                TemplateDetailCard(title: "Spring Boot 3", subtitle: "Enterprise-grade Java service with Spring MVC and Virtual Threads.", icon: "leaf.fill", tag: "Java") { createProject("spring") }
                TemplateDetailCard(title: "PyTorch / ML Pipeline", subtitle: "Machine learning training and inference pipeline with Apple MPS.", icon: "brain.head.profile", tag: "AI / ML") { createProject("pytorch") }
                TemplateDetailCard(title: "Docker Microservices", subtitle: "Production Docker compose stack with PostgreSQL and Redis.", icon: "shippingbox.fill", tag: "DevOps") { createProject("docker") }
                TemplateDetailCard(title: "Vue 3 + Vite", subtitle: "Lightweight reactive frontend with Pinia and Vue Router.", icon: "v.circle.fill", tag: "Frontend") { createProject("vue") }
                TemplateDetailCard(title: "NestJS Enterprise", subtitle: "Structured TypeScript enterprise architecture with dependency injection.", icon: "shield.fill", tag: "TypeScript") { createProject("nestjs") }
            }
        }
    }
    
    // MARK: - Settings Tab
    
    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Workspace & Cache Settings")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
            
            Text("Manage temporary data, purge build caches, and configure disk quotas.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }
    
    private var settingsCacheSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Derived Data Cache Size")
                    .font(.system(size: 14, weight: .semibold))
                if let info = appState.derivedDataInfo {
                    Text("\(String(format: "%.2f", Double(info.size_bytes) / (1024*1024*1024))) GB (\(info.folder_count) projects)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    Text("Calculating size...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: { appState.clearDerivedData() }) {
                Text("Purge Cache")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            Button(action: { appState.checkDerivedDataSize() }) {
                Image(systemName: "arrow.clockwise")
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var settingsQuotaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disk Quota Limits")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            
            HStack {
                Text("DerivedData Quota:")
                Spacer()
                Slider(value: $appState.derivedDataQuotaLimitGB, in: 1...50, step: 1)
                    .frame(width: 200)
                Text("\(Int(appState.derivedDataQuotaLimitGB)) GB")
                    .frame(width: 50, alignment: .trailing)
            }
            
            Toggle("Enable Auto-Purge when quota is exceeded", isOn: $appState.enableDerivedDataAutoPurge)
                .toggleStyle(.checkbox)
            
            Toggle("Show warning notification when quota is exceeded", isOn: $appState.enableDerivedDataAlert)
                .toggleStyle(.checkbox)
        }
    }
    
    private var settingsTabContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsHeader
            
            VStack(alignment: .leading, spacing: 16) {
                settingsCacheSection
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                settingsQuotaSection
            }
            .padding(18)
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Git Clone Modal Sheet View
    
    private var cloneSheetView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Clone Repository")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Git Repository URL")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                TextField("https://github.com/username/project.git", text: $gitCloneUrl)
                    .textFieldStyle(.roundedBorder)
            }
            
            if let error = cloneError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.system(size: 12))
            }
            
            HStack {
                Button("Cancel") {
                    showCloneSheet = false
                    gitCloneUrl = ""
                    cloneError = nil
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(action: performClone) {
                    if isCloning {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                    } else {
                        Text("Clone")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(gitCloneUrl.isEmpty || isCloning)
            }
        }
        .padding()
        .frame(width: 450)
    }
    
    private func performClone() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.title = "Select parent directory for cloned repository"
        panel.prompt = "Clone Here"
        
        if panel.runModal() == .OK, let parentUrl = panel.url {
            isCloning = true
            cloneError = nil
            
            let repoUrlStr = gitCloneUrl
            Task {
                do {
                    let repoName = repoUrlStr.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? "cloned_repo"
                    let destUrl = parentUrl.appendingPathComponent(repoName)
                    
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                    process.arguments = ["clone", repoUrlStr, destUrl.path]
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        DispatchQueue.main.async {
                            self.appState.workspaceFolder = destUrl
                            self.showCloneSheet = false
                            self.isCloning = false
                            self.gitCloneUrl = ""
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.cloneError = "Git clone failed with status \(process.terminationStatus)"
                            self.isCloning = false
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.cloneError = error.localizedDescription
                        self.isCloning = false
                    }
                }
            }
        }
    }
}

struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    var badge: String? = nil
    var gradient: Gradient? = nil
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(isHovering ? 0.12 : 0.06))
                            .frame(width: 38, height: 38)
                        
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    
                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(4)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(
                Color.primary.opacity(isHovering ? 0.06 : 0.025)
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        Color.primary.opacity(isHovering ? 0.25 : 0.08),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isHovering ? 1.015 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct TemplateDetailCard: View {
    let title: String
    let subtitle: String
    let icon: String
    var tag: String? = nil
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(isHovering ? 0.08 : 0.04))
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if let tag = tag {
                            Text(tag)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.primary.opacity(isHovering ? 0.06 : 0.025))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(isHovering ? 0.22 : 0.06), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct RecentProjectRow: View {
    let url: URL
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .foregroundColor(.primary.opacity(0.8))
                    .font(.system(size: 15))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text(url.deletingLastPathComponent().path)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(isHovering ? 0.06 : 0.02))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Inspector View

struct InspectorView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("GIT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { appState.gitRefresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            if let status = appState.gitStatus {
                GitStatusView(status: status)
            } else {
                VStack {
                    Spacer()
                    Text("Not a repository")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct GitStatusView: View {
    let status: GitStatus
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Branch
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundColor(.accentColor)
                    Text(status.branch)
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                
                // Changes
                if !status.files.isEmpty {
                    ForEach(status.files, id: \.path) { file in
                        HStack(spacing: 8) {
                            statusBadge(file.status)
                            Text(file.path)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                    }
                }
                
                // Actions
                HStack(spacing: 8) {
                    Button("Commit") { appState.showCommitDialog() }
                        .disabled(status.files.isEmpty)
                    Button("Push") { appState.gitPush() }
                    Button("Pull") { appState.gitPull() }
                }
                .padding(12)
            }
        }
    }
    
    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        let (color, letter): (Color, String) = {
            switch status {
            case "modified": return (.orange, "M")
            case "added": return (.green, "A")
            case "deleted": return (.red, "D")
            default: return (.gray, "?")
            }
        }()
        
        Text(letter)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .frame(width: 16, height: 16)
            .background(color)
            .cornerRadius(3)
    }
}

// MARK: - Sheets

struct RefactorSheet: View {
    @EnvironmentObject var appState: AppState
    @State private var instructions = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Refactor with AI")
                .font(.headline)
            
            TextEditor(text: $instructions)
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Refactor") {
                    Task {
                        await appState.refactorCode(instructions: instructions)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(instructions.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

struct CommitSheet: View {
    @EnvironmentObject var appState: AppState
    @State private var message = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Commit Changes")
                .font(.headline)
            
            TextField("Commit message", text: $message)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Commit") {
                    Task {
                        await appState.commitChanges(message: message)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(message.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

// MARK: - New File Sheet

enum LanguageCategory: String, CaseIterable {
    case popular = "Popular"
    case web = "Web"
    case systems = "Systems"
    case data = "Data"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .popular: return "star.fill"
        case .web: return "globe"
        case .systems: return "cpu"
        case .data: return "chart.bar.doc.horizontal"
        case .other: return "ellipsis.circle"
        }
    }
}

struct LanguageInfo: Identifiable {
    let id: String
    let name: String
    let icon: String
    let ext: String
    let category: LanguageCategory
    let color: Color
}

struct NewFileSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var filename: String = ""
    @State private var selectedLanguage: String = "swift"
    @State private var selectedCategory: LanguageCategory = .popular
    @State private var saveLocation: SaveLocation = .workspaceRoot
    
    enum SaveLocation: String, CaseIterable {
        case workspaceRoot = "Workspace Root"
        case currentFolder = "Current Folder"
        case custom = "Choose Location..."
        
        var icon: String {
            switch self {
            case .workspaceRoot: return "folder.badge.gearshape"
            case .currentFolder: return "folder"
            case .custom: return "folder.badge.questionmark"
            }
        }
    }
    
    private let languages: [LanguageInfo] = [
        // Popular
        LanguageInfo(id: "swift", name: "Swift", icon: "swift", ext: "swift", category: .popular, color: .orange),
        LanguageInfo(id: "python", name: "Python", icon: "ladybug", ext: "py", category: .popular, color: .blue),
        LanguageInfo(id: "javascript", name: "JavaScript", icon: "j.square", ext: "js", category: .popular, color: .yellow),
        LanguageInfo(id: "typescript", name: "TypeScript", icon: "t.square.fill", ext: "ts", category: .popular, color: .blue),
        LanguageInfo(id: "rust", name: "Rust", icon: "gearshape.2", ext: "rs", category: .popular, color: .orange),
        LanguageInfo(id: "go", name: "Go", icon: "g.square", ext: "go", category: .popular, color: .cyan),
        
        // Web
        LanguageInfo(id: "html", name: "HTML", icon: "chevron.left.forwardslash.chevron.right", ext: "html", category: .web, color: .orange),
        LanguageInfo(id: "css", name: "CSS", icon: "paintbrush", ext: "css", category: .web, color: .blue),
        LanguageInfo(id: "javascript", name: "JavaScript", icon: "j.square", ext: "js", category: .web, color: .yellow),
        LanguageInfo(id: "typescript", name: "TypeScript", icon: "t.square.fill", ext: "ts", category: .web, color: .blue),
        LanguageInfo(id: "jsx", name: "React JSX", icon: "atom", ext: "jsx", category: .web, color: .cyan),
        LanguageInfo(id: "vue", name: "Vue", icon: "v.square", ext: "vue", category: .web, color: .green),
        LanguageInfo(id: "svelte", name: "Svelte", icon: "v.square.fill", ext: "svelte", category: .web, color: .orange),
        LanguageInfo(id: "php", name: "PHP", icon: "elephant.fill", ext: "php", category: .web, color: .indigo),
        
        // Systems
        LanguageInfo(id: "c", name: "C", icon: "c.square", ext: "c", category: .systems, color: .gray),
        LanguageInfo(id: "cpp", name: "C++", icon: "c.square.fill", ext: "cpp", category: .systems, color: .blue),
        LanguageInfo(id: "objective-c", name: "Objective-C", icon: "m.square", ext: "m", category: .systems, color: .blue),
        LanguageInfo(id: "objective-cpp", name: "Objective-C++", icon: "m.square.fill", ext: "mm", category: .systems, color: .indigo),
        LanguageInfo(id: "rust", name: "Rust", icon: "gearshape.2", ext: "rs", category: .systems, color: .orange),
        LanguageInfo(id: "go", name: "Go", icon: "g.square", ext: "go", category: .systems, color: .cyan),
        LanguageInfo(id: "swift", name: "Swift", icon: "swift", ext: "swift", category: .systems, color: .orange),
        LanguageInfo(id: "zig", name: "Zig", icon: "z.square", ext: "zig", category: .systems, color: .orange),
        LanguageInfo(id: "wasm", name: "WebAssembly", icon: "square.fill", ext: "wasm", category: .systems, color: .purple),
        LanguageInfo(id: "metal", name: "Metal", icon: "cube.fill", ext: "metal", category: .systems, color: .purple),
        LanguageInfo(id: "assembly", name: "Assembly", icon: "memorychip", ext: "s", category: .systems, color: .gray),
        
        // Data & Scripting
        LanguageInfo(id: "python", name: "Python", icon: "ladybug", ext: "py", category: .data, color: .blue), // Re-categorized or duplicated if needed, but keeping primarily in popular
        LanguageInfo(id: "r", name: "R", icon: "r.square", ext: "r", category: .data, color: .blue),
        LanguageInfo(id: "matlab", name: "Matlab", icon: "function", ext: "m", category: .data, color: .orange),
        LanguageInfo(id: "julia", name: "Julia", icon: "circle.grid.hex", ext: "jl", category: .data, color: .purple),
        LanguageInfo(id: "lua", name: "Lua", icon: "moon.fill", ext: "lua", category: .data, color: .blue),
        LanguageInfo(id: "ruby", name: "Ruby", icon: "diamond.fill", ext: "rb", category: .data, color: .red),
        LanguageInfo(id: "prolog", name: "Prolog", icon: "brain.head.profile", ext: "pl", category: .data, color: .orange),

        // Enterprise / App
        LanguageInfo(id: "csharp", name: "C#", icon: "c.circle.fill", ext: "cs", category: .popular, color: .purple),
        LanguageInfo(id: "java", name: "Java", icon: "cup.and.saucer.fill", ext: "java", category: .popular, color: .orange),
        LanguageInfo(id: "kotlin", name: "Kotlin", icon: "k.square.fill", ext: "kt", category: .popular, color: .purple),
        LanguageInfo(id: "dart", name: "Dart", icon: "paperplane.fill", ext: "dart", category: .popular, color: .cyan),
        LanguageInfo(id: "scala", name: "Scala", icon: "s.circle.fill", ext: "scala", category: .popular, color: .red),
        LanguageInfo(id: "fsharp", name: "F#", icon: "f.cursive", ext: "fs", category: .popular, color: .cyan),
        LanguageInfo(id: "vala", name: "Vala", icon: "v.circle", ext: "vala", category: .systems, color: .purple),
        
        // Functional / Other
        LanguageInfo(id: "ocaml", name: "OCaml", icon: "camell", ext: "ml", category: .other, color: .orange),
        LanguageInfo(id: "solidity", name: "Solidity", icon: "bitcoinsign.circle.fill", ext: "sol", category: .web, color: .gray),

        // Data Formats
        LanguageInfo(id: "json", name: "JSON", icon: "curlybraces", ext: "json", category: .data, color: .gray),
        LanguageInfo(id: "yaml", name: "YAML", icon: "list.bullet.indent", ext: "yaml", category: .data, color: .red),
        LanguageInfo(id: "xml", name: "XML", icon: "chevron.left.forwardslash.chevron.right", ext: "xml", category: .data, color: .green),
        LanguageInfo(id: "toml", name: "TOML", icon: "doc.plaintext", ext: "toml", category: .data, color: .gray),
        LanguageInfo(id: "sql", name: "SQL", icon: "cylinder", ext: "sql", category: .data, color: .blue),
        LanguageInfo(id: "graphql", name: "GraphQL", icon: "diamond", ext: "graphql", category: .data, color: .pink),
        
        // Text
        LanguageInfo(id: "markdown", name: "Markdown", icon: "doc.richtext", ext: "md", category: .other, color: .gray),
        LanguageInfo(id: "text", name: "Plain Text", icon: "doc.text", ext: "txt", category: .other, color: .gray),
        LanguageInfo(id: "shell", name: "Shell Script", icon: "terminal", ext: "sh", category: .other, color: .green),
        LanguageInfo(id: "dockerfile", name: "Dockerfile", icon: "shippingbox", ext: "dockerfile", category: .other, color: .blue),
        LanguageInfo(id: "java", name: "Java", icon: "cup.and.saucer", ext: "java", category: .other, color: .red),
        LanguageInfo(id: "kotlin", name: "Kotlin", icon: "k.square", ext: "kt", category: .other, color: .purple)
    ]
    
    private var filteredLanguages: [LanguageInfo] {
        languages.filter { $0.category == selectedCategory }
    }
    
    private var selectedLangInfo: LanguageInfo? {
        languages.first { $0.id == selectedLanguage }
    }
    
    private var fileExtension: String {
        selectedLangInfo?.ext ?? "txt"
    }
    
    private var previewFilename: String {
        let name = filename.isEmpty ? "Untitled" : filename
        if name.contains(".") { return name }
        return "\(name).\(fileExtension)"
    }
    
    var body: some View {
        ToolWindowWrapper(
            title: "New File",
            subtitle: "Create a new source file",
            icon: "doc.badge.plus",
            iconColor: .blue
        ) {
            HStack(spacing: 0) {
                // Left: Language Selection
                VStack(alignment: .leading, spacing: 0) {
                    // Category Tabs
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(LanguageCategory.allCases, id: \.self) { category in
                                CategoryTab(
                                    category: category,
                                    isSelected: selectedCategory == category
                                ) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedCategory = category
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    
                    Divider()
                    
                    // Language Grid
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 10) {
                            ForEach(filteredLanguages) { lang in
                                NewFileLanguageCard(
                                    language: lang,
                                    isSelected: selectedLanguage == lang.id
                                ) {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedLanguage = lang.id
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
                .frame(width: 340)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                
                Divider()
                
                // Right: File Details & Preview
                VStack(alignment: .leading, spacing: 20) {
                    // Filename Input
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Filename", systemImage: "doc")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        HStack {
                            TextField("Untitled", text: $filename)
                                .textFieldStyle(.roundedBorder)
                            
                            Text(".\(fileExtension)")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                        }
                        
                        Text(previewFilename)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }
                    
                    Divider()
                    
                    // Save Location
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Location", systemImage: "folder")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: $saveLocation) {
                            ForEach(SaveLocation.allCases, id: \.self) { loc in
                                Label(loc.rawValue, systemImage: loc.icon).tag(loc)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        
                        if let workspace = appState.workspaceFolder {
                            Text(workspace.lastPathComponent)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            Text("No workspace open")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Divider()
                    
                    // Template Preview
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Template Preview", systemImage: "doc.text")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if let lang = selectedLangInfo {
                                HStack(spacing: 4) {
                                    Image(systemName: lang.icon)
                                        .font(.system(size: 10))
                                    Text(lang.name)
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(lang.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(lang.color.opacity(0.1))
                                .cornerRadius(4)
                            }
                        }
                        
                        ScrollView {
                            Text(templatePreview)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .frame(maxHeight: .infinity)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    
                    Spacer(minLength: 0)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        } footer: {
            HStack {
                if let lang = selectedLangInfo {
                    HStack(spacing: 6) {
                        Image(systemName: lang.icon)
                            .foregroundColor(lang.color)
                        Text("\(lang.name) file")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Create File") {
                    appState.createNewFileWithLanguage(name: filename, language: selectedLanguage)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
    
    private var templatePreview: String {
        switch selectedLanguage {
        case "swift":
            return "import Foundation\n\n// MARK: - Main\n\nfunc main() {\n    print(\"Hello, World!\")\n}\n\nmain()"
        case "python":
            return "#!/usr/bin/env python3\n\"\"\"Module description.\"\"\"\n\ndef main():\n    \"\"\"Main entry point.\"\"\"\n    print(\"Hello, World!\")\n\nif __name__ == \"__main__\":\n    main()"
        case "javascript":
            return "// @ts-check\n\"use strict\";\n\n/**\n * Main function\n */\nfunction main() {\n    console.log(\"Hello, World!\");\n}\n\nmain();"
        case "typescript":
            return "/**\n * Main function\n */\nfunction main(): void {\n    console.log(\"Hello, World!\");\n}\n\nmain();"
        case "rust":
            return "//! Module documentation\n\nfn main() {\n    println!(\"Hello, World!\");\n}"
        case "go":
            return "package main\n\nimport \"fmt\"\n\nfunc main() {\n    fmt.Println(\"Hello, World!\")\n}"
        case "html":
            return "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n    <meta charset=\"UTF-8\">\n    <title>Document</title>\n</head>\n<body>\n    <h1>Hello, World!</h1>\n</body>\n</html>"
        case "css":
            return "/* Styles */\n\n:root {\n    --primary: #007AFF;\n}\n\nbody {\n    font-family: system-ui;\n    margin: 0;\n    padding: 0;\n}"
        case "json":
            return "{\n    \"name\": \"project\",\n    \"version\": \"1.0.0\"\n}"
        case "markdown":
            return "# Title\n\nDescription of the document.\n\n## Section\n\nContent here."
        case "shell":
            return "#!/bin/bash\n\n# Script description\n\necho \"Hello, World!\""
        case "c":
            return "#include <stdio.h>\n\nint main() {\n    printf(\"Hello, World!\\n\");\n    return 0;\n}"
        case "cpp":
            return "#include <iostream>\n\nint main() {\n    std::cout << \"Hello, World!\" << std::endl;\n    return 0;\n}"
        case "java":
            return "public class Main {\n    public static void main(String[] args) {\n        System.out.println(\"Hello, World!\");\n    }\n}"
        case "kotlin":
            return "fun main() {\n    println(\"Hello, World!\")\n}"
        case "sql":
            return "-- SQL Query\n\nSELECT * FROM table_name\nWHERE condition = true;"
        case "yaml":
            return "# Configuration\n\nname: project\nversion: 1.0.0\n\nsettings:\n  debug: true"
        default:
            return "// New file"
        }
    }
}

// MARK: - Category Tab

struct CategoryTab: View {
    let category: LanguageCategory
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 11))
                Text(category.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : (isHovering ? Color.secondary.opacity(0.1) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Language Card

struct NewFileLanguageCard: View {
    let language: LanguageInfo
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(language.color.opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: language.icon)
                        .font(.system(size: 16))
                        .foregroundColor(language.color)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text(".\(language.ext)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovering ? Color.secondary.opacity(0.08) : Color(nsColor: .controlBackgroundColor)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.1), value: isHovering)
    }
}

// MARK: - AI Chat Panel

struct AIChatPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var inputMessage: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("AI Assistant")
                        .font(.system(size: 13, weight: .semibold))
                }
                
                Spacer()
                
                // Agent Mode Toggle
                Toggle(isOn: $appState.agentMode) {
                    Text(appState.agentMode ? "Agent Active" : "Agent Mode")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(appState.agentMode ? .primary : .secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Enable Agent Mode for autonomous coding assistance")
                
                // Divider
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1, height: 16)
                
                // Model Selector Pill
                Menu {
                    let activeProviders = AIModelCatalog.shared.providers.filter { $0.id != "omni" && !(appState.apiKeys[$0.id]?.isEmpty ?? true) }
                    let providersToDisplay = activeProviders.isEmpty ? AIModelCatalog.shared.providers.filter { $0.id != "omni" } : activeProviders
                    ForEach(providersToDisplay) { prov in
                        Section(prov.name) {
                            ForEach(prov.models) { m in
                                Button(m.name) {
                                    setModel(m.id, provider: prov.id)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(modelDisplayName)
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .frame(width: 140, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(nsColor: .separatorColor).opacity(0.1)),
                alignment: .bottom
            )
            
            Divider()
            
            // Pending Actions
            if !appState.pendingActions.filter({ !$0.isApproved && !$0.isRejected }).isEmpty {
                VStack(spacing: 4) {
                    Text("PENDING ACTIONS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    ForEach(appState.pendingActions.filter({ !$0.isApproved && !$0.isRejected })) { action in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.description)
                                    .font(.system(size: 11, weight: .medium))
                                Text(action.filePath)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button {
                                appState.approveAction(action)
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                            .help("Apply changes")
                            
                            Button {
                                appState.rejectAction(action)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Reject changes")
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                
                Divider()
            }
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(appState.aiChatMessages) { message in
                            ChatMessageView(message: message)
                                .id(message.id)
                        }
                        
                        // Floating Thinking Indicator (New)
                        if appState.isLoading && appState.aiChatMessages.last?.role == .user {
                            ThinkingIndicatorView()
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: appState.aiChatMessages.count) { _ in
                    if let lastMessage = appState.aiChatMessages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: appState.aiChatMessages.last?.content) { _ in
                    if let lastMessage = appState.aiChatMessages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // Input
            HStack(spacing: 8) {
                TextField("Ask AI anything...", text: $inputMessage)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    .onSubmit {
                        sendMessage()
                    }
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(inputMessage.isEmpty ? .secondary.opacity(0.5) : .accentColor)
                        .shadow(color: inputMessage.isEmpty ? .clear : .accentColor.opacity(0.3), radius: 2)
                }
                .buttonStyle(.plain)
                .disabled(inputMessage.isEmpty || appState.isLoading)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    private var modelDisplayName: String {
        if let m = AIModelCatalog.shared.model(id: appState.aiModel) {
            return m.name
        }
        return AIModelCatalog.formatModelName(appState.aiModel)
    }
    
    private func setModel(_ model: String, provider: String) {
        appState.aiModel = model
        appState.aiProvider = provider
        UserDefaults.standard.set(model, forKey: "aiModel")
        UserDefaults.standard.set(provider, forKey: "aiProvider")
    }
    
    private func sendMessage() {
        guard !inputMessage.isEmpty else { return }
        let message = inputMessage
        inputMessage = ""
        appState.sendChatMessage(message)
    }
}

struct ChatMessageView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer()
            } else {
                // Avatar for AI
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .padding(.top, 4)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Thinking indicator (inline for assistant)
                if message.isThinking {
                    HStack(spacing: 5) {
                        Text("Thinking...")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }

                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 13))
                        .compatTextSelection()
                        .padding(10)
                        .background(backgroundColor)
                        .foregroundColor(foregroundColor)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
                }
                
                // Enhanced Tool Calls display
                if !message.toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(message.toolCalls, id: \.id) { tool in
                            HStack {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                
                                Text("\(tool.name)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                
                                Spacer()
                                
                                if let result = message.toolResults.first(where: { $0.tool_call_id == tool.id }) {
                                    if result.success {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.system(size: 10))
                                    } else {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.system(size: 10))
                                    }
                                } else if !message.isThinking {
                                     ProgressView().scaleEffect(0.4)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                                    )
                            )
                        }
                    }
                }

                Text(timeString)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role != .user {
                Spacer()
            }
        }
    }
    
    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor
        case .assistant:
            return Color(nsColor: .controlBackgroundColor)
        case .system:
            return Color.orange.opacity(0.1)
        }
    }
    
    private var foregroundColor: Color {
        message.role == .user ? .white : .primary
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.timestamp)
    }
}

// MARK: - New Components

// AgentBrainDashboard and DashboardTabBtn removed — Task Windows deprecated

struct ThinkingIndicatorView: View {
    @State private var pulseAlpha: Double = 0.4
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 6) {
            Text("Working.")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundColor(.secondary.opacity(pulseAlpha))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1))
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseAlpha = 0.95
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @StateObject private var modelCatalog = AIModelCatalog.shared
    
    // Local state for editing
    @State private var selectedProvider: String = ""
    @State private var selectedModel: String = ""
    @State private var apiKey: String = ""
    @State private var fontSize: CGFloat = 16
    @State private var fontFamily: String = "SF Mono"
    @State private var agentFontName: String = "SF Pro"
    @State private var agentFontSize: CGFloat = 16.0
    @State private var showLineNumbers: Bool = false
    @State private var showSidebar: Bool = true
    @State private var showConsole: Bool = true
    @State private var selectedTheme: AppTheme = .system
    @State private var playgroundFontName: String = "SF Mono"
    @State private var playgroundFontSize: CGFloat = 16.0
    @State private var playgroundFontWeight: Int = 2
    @State private var cellFontName: String = "SF Mono"
    @State private var cellFontSize: CGFloat = 16.0
    @State private var cellFontWeight: Int = 2
    @State private var agentMode: Bool = true
    @State private var agentAutoApproveTools: Bool = false
    @State private var agentCustomInstructions: String = ""
    @State private var agentMaxIterations: Int = 0
    @State private var selectedTab: Int = 2
    @State private var hasChanges: Bool = false
    @State private var microRentToken: String = ""
    @State private var authEmail = ""
    @State private var authPassword = ""
    @State private var isAuthenticating = false
    @State private var authError = ""
    @State private var currentPlan: String = "free"
    
    static let sidebarItems: [(tab: Int, title: String, icon: String)] = [
        (0, "General", "gearshape"),
        (1, "Editor", "text.cursor"),
        (2, "AI & Agent", "sparkles"),
        (9, "Cloud GPU", "cpu"),
        (10, "Skills", "sparkles.rectangle.stack"),
        (8, "MCP Servers", "server.rack"),
        (3, "Tools", "wrench.and.screwdriver"),
        (5, "Extensions", "puzzlepiece.extension"),
        (6, "Account & License", "person.badge.key"),
        (4, "About", "info.circle")
    ]

    var body: some View {
        HStack(spacing: 0) {
            // ── Sidebar (Codex-style) ──────────────────────────────────
            VStack(alignment: .leading, spacing: 2) {
                Button(action: { closeSettings() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back to app")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .padding(.bottom, 16)

                ForEach(Self.sidebarItems, id: \.tab) { item in
                    CodexSidebarRow(title: item.title, icon: item.icon,
                                    selected: selectedTab == item.tab) {
                        selectedTab = item.tab
                    }
                }

                Spacer()

                Text("© 2025 MicroCode · Dotmini Software")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.65))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
            .frame(width: 236, alignment: .leading)
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))

            Divider()

            // ── Content ────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        Text(Self.sidebarItems.first { $0.tab == selectedTab }?.title ?? "Settings")
                            .font(.system(size: 20, weight: .bold))
                        Spacer()
                        HStack(spacing: 8) {
                            Button("Cancel") { closeSettings() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .keyboardShortcut(.cancelAction)
                            Button("Save Changes") { saveAllSettings(); closeSettings() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                    Divider().opacity(0.5)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if selectedTab == 0 { generalSettingsContent }
                        else if selectedTab == 1 { editorSettingsContent }
                        else if selectedTab == 2 { aiSettingsContent }
                        else if selectedTab == 9 { CloudGPUView() }
                        else if selectedTab == 10 { AgentSkillsView() }
                        else if selectedTab == 8 { mcpSettingsPanel }
                        else if selectedTab == 3 { toolsSettingsContent }
                        else if selectedTab == 5 { ExtensionSettingsView() }
                        else if selectedTab == 6 { subscriptionSettingsContent }
                        else { aboutContent }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 880, idealWidth: 1000, maxWidth: 1240,
               minHeight: 600, idealHeight: 700, maxHeight: 920)
        .onAppear {
            selectedTab = appState.settingsSelectedTab
            loadCurrentSettings()
        }
        .onChange(of: selectedTab) { newTab in
            appState.settingsSelectedTab = newTab
        }
        .sheet(item: $webLoginProvider) { prov in
            WebSubscriptionLoginSheet(provider: prov) {
                hasChanges = true
            }
        }
        .onDisappear {
            appState.showingSettingsDialog = false
        }
    }
    
    private func closeSettings() {
        appState.showingSettingsDialog = false
        dismiss()
    }
    
    // MARK: - Subscription Content
    
    private var subscriptionSettingsContent: some View {
        MicroCodeLicenseSettingsView()
    }
    
    // MARK: - Firebase Authentication
    private func authenticateWithFirebase() {
        guard !authEmail.isEmpty, !authPassword.isEmpty else { return }
        isAuthenticating = true
        authError = ""
        
        // API key must be configured via Settings → MicroRent, never hardcoded
        let apiKey = UserDefaults.standard.string(forKey: "firebaseApiKey") ?? ProcessInfo.processInfo.environment["FIREBASE_API_KEY"] ?? ""
        guard !apiKey.isEmpty else {
            authError = "Firebase API Key not configured. Set it in Settings → MicroRent."
            isAuthenticating = false
            return
        }
        let urlString = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            authError = "Invalid Configuration"
            isAuthenticating = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "email": authEmail,
            "password": authPassword,
            "returnSecureToken": true
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            authError = "Payload Error"
            isAuthenticating = false
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isAuthenticating = false
                
                if let error = error {
                    self.authError = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.authError = "No data received"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorObj = json["error"] as? [String: Any],
                       let message = errorObj["message"] as? String {
                        self.authError = message
                        if message == "INVALID_LOGIN_CREDENTIALS" {
                            self.authError = "Invalid Email or Password"
                        }
                    } else {
                        self.authError = "Server Error: \(httpResponse.statusCode)"
                    }
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let localId = json["localId"] as? String {
                        self.microRentToken = localId
                        self.hasChanges = true
                        self.authEmail = ""
                        self.authPassword = ""
                    } else {
                        self.authError = "Could not parse UID from response"
                    }
                } catch {
                    self.authError = "Invalid response format"
                }
            }
        }.resume()
    }
    
    private func checkSubscriptionStatus() {
        guard !microRentToken.isEmpty else { return }
        
        let baseURL = UserDefaults.standard.string(forKey: "firebaseRTDBUrl") ?? ProcessInfo.processInfo.environment["FIREBASE_RTDB_URL"] ?? ""
        guard !baseURL.isEmpty else { return }
        let urlString = "\(baseURL)/users/\(microRentToken)/subscriptionPlan.json"
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data, let planString = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    let unquoted = planString.replacingOccurrences(of: "\"", with: "")
                    if unquoted != "null" && !unquoted.isEmpty {
                        self.currentPlan = unquoted
                    } else {
                        self.currentPlan = "free"
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - About Content
    
    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    private var aboutContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            // Real app icon (Apple-style)
            Group {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .resizable().scaledToFit().padding(28)
                        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.thinMaterial))
                }
            }
            .frame(width: 116, height: 116)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
            .padding(.bottom, 18)

            Text("MicroCode")
                .font(.system(size: 30, weight: .semibold))
            Text(appVersionString)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.top, 2)

            Text("The native AI-powered IDE for macOS")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.top, 10)

            HStack(spacing: 18) {
                Link(destination: URL(string: "https://github.com/Dotmini/microcode")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://dotmini.net")!) {
                    Label("dotmini.net", systemImage: "globe")
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.top, 20)

            Spacer(minLength: 24)

            VStack(spacing: 3) {
                Text("Dotmini Software")
                    .font(.system(size: 12, weight: .semibold))
                Text("© 2025 Dotmini Software. All rights reserved.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - General Settings
    
    private var generalSettingsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Agent Settings on Page 1 (หน้าแรก)
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeader(title: "AI Agent & Automation")
                
                Toggle("Autonomous Agent Mode (Multi-turn tool loop & file edits)", isOn: $agentMode)
                    .onChange(of: agentMode) { _ in hasChanges = true }
                
                Toggle("Auto-Approve Tool Execution (Files, Shell, Refactor)", isOn: $agentAutoApproveTools)
                    .onChange(of: agentAutoApproveTools) { _ in hasChanges = true }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Max Tool Loop Iterations:")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Stepper(agentMaxIterations <= 0 ? "Unlimited (∞)" : "\(agentMaxIterations) steps", value: $agentMaxIterations, in: 0...200, step: 5)
                            .onChange(of: agentMaxIterations) { _ in hasChanges = true }
                    }
                    if agentMaxIterations <= 0 {
                        Text("No limit — Agent will continue multi-turn thinking & tool loops until the task is complete.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                
                HStack {
                    Text("Agent Font:")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker("", selection: $agentFontName) {
                        Text("SF Pro").tag("SF Pro")
                        Text("SF Mono").tag("SF Mono")
                        Text("Menlo").tag("Menlo")
                        Text("Fira Code").tag("Fira Code")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .onChange(of: agentFontName) { _ in hasChanges = true }
                }
                
                HStack {
                    Text("Agent Size: \(Int(agentFontSize)) pt")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 120, alignment: .leading)
                    Slider(value: $agentFontSize, in: 12...26, step: 1)
                        .onChange(of: agentFontSize) { _ in hasChanges = true }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom System Instructions / Rules:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $agentCustomInstructions)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 70)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                        .onChange(of: agentCustomInstructions) { _ in hasChanges = true }
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            
            Divider()
            
            SettingsSectionHeader(title: "Appearance")
            
            Toggle("Show sidebar on startup", isOn: $showSidebar)
                .onChange(of: showSidebar) { _ in hasChanges = true }
            
            Toggle("Show console on startup", isOn: $showConsole)
                .onChange(of: showConsole) { _ in hasChanges = true }
                
            Divider()
            
            SettingsSectionHeader(title: "Theme")
            
            ThemePickerView(selectedTheme: $selectedTheme)
                .onChange(of: selectedTheme) { _ in hasChanges = true }
            
            // Theme Preview
            HStack {
                Text("Preview:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: selectedTheme.editorBackground))
                    .frame(width: 100, height: 60)
                    .overlay(
                        VStack(alignment: .leading, spacing: 2) {
                            Text("func main() {")
                                .foregroundColor(Color(nsColor: selectedTheme.keywordColor))
                            Text("  print(\"Hello\")")
                                .foregroundColor(Color(nsColor: selectedTheme.editorText))
                            Text("}")
                                .foregroundColor(Color(nsColor: selectedTheme.keywordColor))
                        }
                        .font(.system(size: 8, design: .monospaced))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
        }
    }
    
    // MARK: - Editor Settings
    
    private var editorSettingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // AI Agent & Chat Font
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: "AI Agent & Chat Font")
                    
                    Picker("Font Family", selection: $agentFontName) {
                        Text("SF Pro").tag("SF Pro")
                        Text("SF Mono").tag("SF Mono")
                        Text("Menlo").tag("Menlo")
                        Text("Fira Code").tag("Fira Code")
                        Text("Monaco").tag("Monaco")
                        Text("Helvetica Neue").tag("Helvetica Neue")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                    .onChange(of: agentFontName) { _ in hasChanges = true }
                    
                    HStack {
                        Text("Size: \(Int(agentFontSize))")
                            .frame(width: 60, alignment: .leading)
                        Slider(value: $agentFontSize, in: 12...26, step: 1)
                            .onChange(of: agentFontSize) { _ in hasChanges = true }
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // Main Editor Font
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: "Main Editor Font")
                    
                    Picker("Font Family", selection: $fontFamily) {
                        Text("SF Pro").tag("SF Pro")
                        Text("SF Mono").tag("SF Mono")
                        Text("Menlo").tag("Menlo")
                        Text("Fira Code").tag("Fira Code")
                        Text("Monaco").tag("Monaco")
                        Text("Courier New").tag("Courier New")
                        Text("Helvetica Neue").tag("Helvetica Neue")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                    .onChange(of: fontFamily) { _ in hasChanges = true }
                    
                    HStack {
                        Text("Size: \(Int(fontSize))")
                            .frame(width: 60, alignment: .leading)
                        Slider(value: $fontSize, in: 10...24, step: 1)
                            .onChange(of: fontSize) { _ in hasChanges = true }
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // Playground Font
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: "Playground Font")
                    
                    Picker("Font Family", selection: $playgroundFontName) {
                        Text("SF Pro").tag("SF Pro")
                        Text("SF Mono").tag("SF Mono")
                        Text("Menlo").tag("Menlo")
                        Text("Fira Code").tag("Fira Code")
                        Text("Monaco").tag("Monaco")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                    .onChange(of: playgroundFontName) { _ in hasChanges = true }
                    
                    HStack {
                        Text("Size: \(Int(playgroundFontSize))")
                            .frame(width: 60, alignment: .leading)
                        Slider(value: $playgroundFontSize, in: 10...24, step: 1)
                            .onChange(of: playgroundFontSize) { _ in hasChanges = true }
                    }
                    
                    Picker("Font Weight", selection: $playgroundFontWeight) {
                        Text("Thin").tag(0)
                        Text("Light").tag(1)
                        Text("Regular").tag(2)
                        Text("Medium").tag(3)
                        Text("Semibold").tag(4)
                        Text("Bold").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: playgroundFontWeight) { _ in hasChanges = true }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // Cell Mode Font
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: "Cell Mode Font")
                    
                    Picker("Font Family", selection: $cellFontName) {
                        Text("SF Pro").tag("SF Pro")
                        Text("SF Mono").tag("SF Mono")
                        Text("Menlo").tag("Menlo")
                        Text("Fira Code").tag("Fira Code")
                        Text("Monaco").tag("Monaco")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                    .onChange(of: cellFontName) { _ in hasChanges = true }
                    
                    HStack {
                        Text("Size: \(Int(cellFontSize))")
                            .frame(width: 60, alignment: .leading)
                        Slider(value: $cellFontSize, in: 10...24, step: 1)
                            .onChange(of: cellFontSize) { _ in hasChanges = true }
                    }
                    
                    Picker("Font Weight", selection: $cellFontWeight) {
                        Text("Thin").tag(0)
                        Text("Light").tag(1)
                        Text("Regular").tag(2)
                        Text("Medium").tag(3)
                        Text("Semibold").tag(4)
                        Text("Bold").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: cellFontWeight) { _ in hasChanges = true }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // Editing
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: "Editing Preferences")
                    Toggle("Show line numbers", isOn: $showLineNumbers)
                        .onChange(of: showLineNumbers) { _ in hasChanges = true }
                    Text("Off by default. Large files in Performance mode hide line numbers automatically for stability.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Toggle("Word wrap", isOn: .constant(false))
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            }
            .padding()
        }
    }
    
    // MARK: - AI Settings
    
    // MARK: - AI Provider Registry
    
    private struct AIProviderInfo {
        let id: String
        let name: String
        let icon: String
        let color: Color
        let endpoint: String
        let models: [(name: String, id: String, badge: String)]
    }
    
    private var aiProviders: [AIProviderInfo] {
        modelCatalog.providers.map { provider in
            AIProviderInfo(
                id: provider.id,
                name: provider.name,
                icon: provider.icon,
                color: providerColor(provider.id),
                endpoint: provider.endpoint,
                models: provider.models.map { ($0.name, $0.id, $0.badge) }
            )
        } + [
            AIProviderInfo(id: "local", name: "Local LLM", icon: "desktopcomputer", color: .mint,
                          endpoint: LocalLLMService.shared.activeEndpoint,
                          models: LocalLLMService.shared.availableModels.map {
                              (name: $0.displayName, id: $0.id, badge: $0.size ?? "")
                          } + [("Auto-detect", "local-model", "SCAN")]),
        ]
    }

    private func providerColor(_ provider: String) -> Color {
        switch provider {
        case "omni": return .orange
        case "gemini": return .blue
        case "openai": return .green
        case "anthropic": return .pink
        case "deepseek": return .cyan
        case "grok": return .purple
        case "qwen": return .indigo
        case "glm": return .red
        default: return .secondary
        }
    }
    
    @State private var providerKeys: [String: String] = [:]
    @State private var showAPIKey: [String: Bool] = [:]
    @State private var aiKeyMode: String = "direct"  // "cloud" = Dotmini proxy, "direct" = user's own key, "subscription" = ChatGPT/Claude/Gemini/DeepSeek subscription, "local" = local LLM
    @State private var dotminiLicenseKey: String = ""
    @ObservedObject private var subscriptionAuth = SubscriptionAuthManager.shared
    
    private var aiSettingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // ── 1. Formal Mode Switcher (Dotmini Cloud vs Subscription vs BYOK vs Local) ──
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("AI Mode & Provider")
                        .font(.system(size: 13, weight: .semibold))
                }
                
                HStack(spacing: 8) {
                    // Mode Button: Cloud
                    Button {
                        aiKeyMode = "cloud"
                        selectedProvider = "omni"
                        if let first = modelCatalog.provider("omni")?.models.first {
                            selectedModel = first.id
                        }
                        hasChanges = true
                    } label: {
                        HStack(spacing: 6) {
                            AIProviderBrandIcon(provider: "omni", size: 15)
                            Text("Dotmini Cloud")
                                .font(.system(size: 11.5, weight: aiKeyMode == "cloud" ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(aiKeyMode == "cloud" ? Color.primary.opacity(0.12) : Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(aiKeyMode == "cloud" ? Color.primary.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)

                    // Mode Button: Web Subscription (No API)
                    Button {
                        aiKeyMode = "subscription"
                        hasChanges = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles.rectangle.stack")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            Text("Web Subscription")
                                .font(.system(size: 11.5, weight: aiKeyMode == "subscription" ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(aiKeyMode == "subscription" ? Color.primary.opacity(0.12) : Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(aiKeyMode == "subscription" ? Color.primary.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    
                    // Mode Button: BYOK
                    Button {
                        aiKeyMode = "direct"
                        if selectedProvider == "omni" || selectedProvider == "local" {
                            selectedProvider = "gemini"
                            if let first = modelCatalog.provider("gemini")?.models.first {
                                selectedModel = first.id
                            }
                        }
                        hasChanges = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "key")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text("Direct API Key")
                                .font(.system(size: 11.5, weight: aiKeyMode == "direct" ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(aiKeyMode == "direct" ? Color.primary.opacity(0.12) : Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(aiKeyMode == "direct" ? Color.primary.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    
                    // Mode Button: Local
                    Button {
                        aiKeyMode = "local"
                        selectedProvider = "local"
                        selectedModel = "local-model"
                        hasChanges = true
                    } label: {
                        HStack(spacing: 6) {
                            AIProviderBrandIcon(provider: "local", size: 15)
                            Text("Local LLM")
                                .font(.system(size: 11.5, weight: aiKeyMode == "local" ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(aiKeyMode == "local" ? Color.primary.opacity(0.12) : Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(aiKeyMode == "local" ? Color.primary.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            )
            
            // ── 2. Mode-Specific Configuration ──
            if aiKeyMode == "cloud" {
                // Dotmini Cloud Dedicated Panel
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        AIProviderBrandIcon(provider: "omni", size: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Dotmini Cloud Models")
                                .font(.system(size: 13, weight: .semibold))
                            Text("api.dotmini.net/v1")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(modelCatalog.source)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Button(modelCatalog.isRefreshing ? "Refreshing…" : "Refresh Catalog") {
                            Task {
                                await modelCatalog.refreshIfNeeded(force: true)
                                let normalized = modelCatalog.normalizedSelection(provider: "omni", model: selectedModel)
                                selectedProvider = "omni"
                                selectedModel = normalized.model
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(modelCatalog.isRefreshing)
                    }
                    
                    Divider().opacity(0.6)
                    
                    HStack(spacing: 12) {
                        Text("Active Model:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 110, alignment: .leading)
                        
                        Picker("", selection: $selectedModel) {
                            if let omniProvider = modelCatalog.provider("omni") {
                                ForEach(omniProvider.models, id: \.id) { m in
                                    HStack {
                                        Text(m.name)
                                        if !m.badge.isEmpty {
                                            Text("[\(m.badge)]")
                                        }
                                    }.tag(m.id)
                                }
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .onChange(of: selectedModel) { _ in
                            selectedProvider = "omni"
                            hasChanges = true
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Text("License / Token:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 110, alignment: .leading)
                        
                        SecureField("Optional Dotmini Cloud License / Bearer Token", text: $dotminiLicenseKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: dotminiLicenseKey) { _ in
                                hasChanges = true
                            }
                    }
                    
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text(dotminiLicenseKey.isEmpty ? "Dotmini Cloud Active (Tier: Pro / Master Admin)" : "Dotmini Cloud Authenticated")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                )
            } else if aiKeyMode == "direct" {
                // BYOK Dedicated Panel
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "key")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Bring Your Own Key (BYOK)")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    
                    Text("Connect directly to official AI providers using your own API credentials.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 20) {
                        // Provider Picker
                        HStack(spacing: 8) {
                            Text("Active Provider:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .fixedSize()
                            
                            Picker("", selection: $selectedProvider) {
                                ForEach(aiProviders.filter { $0.id != "omni" && $0.id != "local" }, id: \.id) { p in
                                    Text(p.name).tag(p.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                            .onChange(of: selectedProvider) { newValue in
                                hasChanges = true
                                if let provider = aiProviders.first(where: { $0.id == newValue }),
                                   let first = provider.models.first {
                                    selectedModel = first.id
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Model Picker
                        HStack(spacing: 8) {
                            Text("Model:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .fixedSize()
                            
                            Picker("", selection: $selectedModel) {
                                if let provider = aiProviders.first(where: { $0.id == selectedProvider }) {
                                    ForEach(provider.models, id: \.id) { m in
                                        HStack {
                                            Text(m.name)
                                            if !m.badge.isEmpty {
                                                Text("[\(m.badge)]")
                                            }
                                        }.tag(m.id)
                                    }
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                            .onChange(of: selectedModel) { _ in hasChanges = true }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Divider().opacity(0.6)
                    
                    Text("Provider API Keys")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 6) {
                        ForEach(aiProviders.filter { $0.id != "omni" && $0.id != "local" }, id: \.id) { provider in
                            aiProviderKeyCard(provider)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                )
            } else if aiKeyMode == "subscription" {
                // Web Subscription Panel (ChatGPT Plus/Team, Claude Pro, Zhipu GLM)
                subscriptionAISettingsPanel
            } else {
                // Local LLM Panel
                localLLMSettingsPanel
            }
        }
    }
    
    @ObservedObject private var mcpServer = MCPServer.shared
    
    private var mcpSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("MCP Protocol Server")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                
                HStack(spacing: 4) {
                    Circle().fill(mcpServer.isRunning ? .green : .secondary.opacity(0.3)).frame(width: 6, height: 6)
                    Text(mcpServer.isRunning ? "Running" : "Stopped")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(mcpServer.isRunning ? .green : .secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(0.04)).cornerRadius(6)
                
                Button(mcpServer.isRunning ? "Stop" : "Start") {
                    if mcpServer.isRunning {
                        mcpServer.stop()
                    } else if let ws = appState.workspaceFolder?.path {
                        mcpServer.start(workspace: ws)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Text("Model Context Protocol server exposes workspace tools (read, write, search, terminal, git) to external AI clients like Claude Desktop, Cursor, and ChatGPT plugins.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            // Stats
            if mcpServer.isRunning {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Requests").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                        Text("\(mcpServer.requestCount)").font(.system(size: 16, weight: .bold, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clients").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                        Text("\(mcpServer.connectedClients)").font(.system(size: 16, weight: .bold, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tools").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                        Text("8").font(.system(size: 16, weight: .bold, design: .monospaced))
                    }
                    Spacer()
                    
                    if let last = mcpServer.lastActivity {
                        Text("Last: \(last, style: .relative) ago")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.03))
                .cornerRadius(8)
            }
            
            // Available Tools
            VStack(alignment: .leading, spacing: 6) {
                Text("Available Tools")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 4) {
                    mcpToolBadge("read_file", icon: "doc.text")
                    mcpToolBadge("write_file", icon: "pencil.and.outline")
                    mcpToolBadge("edit_file", icon: "doc.text.fill")
                    mcpToolBadge("search_files", icon: "magnifyingglass")
                    mcpToolBadge("list_files", icon: "folder")
                    mcpToolBadge("run_terminal", icon: "terminal.fill")
                    mcpToolBadge("git_status", icon: "point.3.filled.connected.trianglepath.dotted")
                    mcpToolBadge("get_diagnostics", icon: "exclamationmark.triangle")
                }
            }
            
            // Recent Logs
            if !mcpServer.logs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Activity")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    ForEach(mcpServer.logs.suffix(5)) { log in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(log.status == .success ? .green : log.status == .error ? .red : .blue)
                                .frame(width: 5, height: 5)
                            Text(log.method)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                            Text(log.detail)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(log.timestamp, style: .time)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }
                .padding(10)
                .background(Color.black.opacity(0.15))
                .cornerRadius(6)
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
    
    @ViewBuilder
    private func mcpToolBadge(_ name: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9)).foregroundColor(.secondary)
            Text(name).font(.system(size: 9, design: .monospaced)).foregroundColor(.primary.opacity(0.7))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(4)
    }
    
    @State private var subscriptionTokenInputs: [String: String] = [:]
    @State private var subscriptionEmailInputs: [String: String] = [:]
    @State private var expandedProviderGuide: [String: Bool] = [:]
    @State private var copiedSnippetProvider: String? = nil
    @State private var webLoginProvider: SubscriptionProviderType? = nil

    private var subscriptionAISettingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Web Subscription Mode (No API Billing)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Connect your active ChatGPT, Claude, Gemini, DeepSeek, or GitHub Copilot accounts without API usage fees.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    if subscriptionAuth.hasAnyConnected {
                        Button(role: .destructive) {
                            subscriptionAuth.clearAllAccounts()
                        } label: {
                            Text("Disconnect All")
                                .font(.system(size: 11))
                        }
                        .controlSize(.small)
                    }

                    Button {
                        Task {
                            await subscriptionAuth.detectLocalCLISessions()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 10))
                            Text("Auto-detect & Verify CLI Auth")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.bottom, 2)

            if !subscriptionAuth.lastDetectionMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: subscriptionAuth.detectedSessionCount > 0 ? "checkmark.circle.fill" : "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(subscriptionAuth.detectedSessionCount > 0 ? .green : .secondary)
                    Text(subscriptionAuth.lastDetectionMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
            }

            Divider().opacity(0.6)

            // Active Subscription Model Selection Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "cpu")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.blue)
                    Text("Active Subscription Model")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if subscriptionAuth.hasAnyConnected {
                        Text("\(subscriptionAuth.connectedModelInfos().count) Models Available")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(4)
                    }
                }
                
                if subscriptionAuth.hasAnyConnected {
                    let connectedModels = subscriptionAuth.connectedModelInfos()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: Binding(
                            get: {
                                if connectedModels.contains(where: { $0.modelID == selectedModel }) {
                                    return selectedModel
                                }
                                return connectedModels.first?.modelID ?? ""
                            },
                            set: { newModelID in
                                selectedModel = newModelID
                                if let info = connectedModels.first(where: { $0.modelID == newModelID }) {
                                    selectedProvider = info.aiProviderID
                                    appState.aiModel = info.modelID
                                    appState.aiProvider = info.aiProviderID
                                    subscriptionAuth.activeProvider = info.provider
                                    UserDefaults.standard.set(info.provider.rawValue, forKey: "subscriptionActiveProvider")
                                    UserDefaults.standard.set("subscription", forKey: "aiKeyMode")
                                    hasChanges = true
                                }
                            }
                        )) {
                            ForEach(subscriptionAuth.connectedProviders()) { prov in
                                Section(prov.displayName) {
                                    ForEach(prov.modelInfos) { m in
                                        HStack {
                                            Text(m.name)
                                            if !m.badge.isEmpty {
                                                Text("[\(m.badge)]")
                                            }
                                        }
                                        .tag(m.modelID)
                                    }
                                }
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        
                        // Active Model Detail Banner
                        if let activeInfo = subscriptionAuth.findModel(id: selectedModel) {
                            let account = subscriptionAuth.getAccount(activeInfo.provider)
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(activeInfo.name)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text("[\(activeInfo.badge)]")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(.blue)
                                        Text("via \(activeInfo.provider.displayName)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    Text(activeInfo.description)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if let account = account {
                                    Text(account.emailOrUser)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.04))
                                        .cornerRadius(4)
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.2), lineWidth: 1))
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("No active web subscriptions connected. Sign in or connect at least one account below to enable subscription models.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.2), lineWidth: 1))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))

            Divider().opacity(0.6)

            // Provider Cards
            VStack(spacing: 12) {
                ForEach(SubscriptionProviderType.allCases) { provider in
                    let isConn = subscriptionAuth.isConnected(provider)
                    let account = subscriptionAuth.getAccount(provider)
                    let isGuideExpanded = expandedProviderGuide[provider.rawValue] ?? false
                    
                    VStack(alignment: .leading, spacing: 10) {
                        // Top Bar: Brand, Info, and Status
                        HStack(spacing: 10) {
                            AIProviderBrandIcon(provider: provider.providerIcon, size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(provider.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                    if isConn {
                                        Text("ACTIVE")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.green.opacity(0.12))
                                            .cornerRadius(3)
                                        
                                        if let src = account?.source, !src.isEmpty {
                                            Text(src)
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundColor(.secondary)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.primary.opacity(0.05))
                                                .cornerRadius(3)
                                        }
                                    }
                                }
                                Text(account?.emailOrUser ?? provider.helpInstruction)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                            
                        // Action Row
                        HStack(spacing: 8) {
                            if isConn {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.shield.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 13))
                                    Text("Auto-Synced & Ready")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundColor(.green)
                                }
                                
                                Spacer()
                                
                                Button("Disconnect") {
                                    subscriptionAuth.disconnect(provider: provider)
                                    hasChanges = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                // 🌟 Primary 1-Click Sign In & Auto-Sync
                                Button {
                                    webLoginProvider = provider
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.crop.circle.badge.checkmark")
                                            .font(.system(size: 12))
                                        Text("1-Click Sign In (Auto-Detect)")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.accentColor)
                                .controlSize(.regular)
                                
                                Spacer()
                                
                                // Advanced manual toggle (Hidden by default for non-technical users)
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        expandedProviderGuide[provider.rawValue] = !isGuideExpanded
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: isGuideExpanded ? "chevron.up" : "gearshape")
                                            .font(.system(size: 9.5))
                                        Text(isGuideExpanded ? "Close Manual" : "Manual / Dev Mode")
                                            .font(.system(size: 10))
                                    }
                                    .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 2)

                        // Advanced Manual Token Entry (Only when user explicitly clicks "Manual / Dev Mode")
                        if !isConn && isGuideExpanded {
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    SecureField("Paste Token / Cookie manually (optional)", text: Binding(
                                        get: { subscriptionTokenInputs[provider.rawValue] ?? "" },
                                        set: { subscriptionTokenInputs[provider.rawValue] = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11))
                                    
                                    Button("Connect") {
                                        let token = subscriptionTokenInputs[provider.rawValue] ?? ""
                                        let email = subscriptionEmailInputs[provider.rawValue] ?? ""
                                        if !token.isEmpty {
                                            subscriptionAuth.saveAccount(provider: provider, emailOrUser: email, sessionToken: token, source: "Manual Input")
                                            subscriptionTokenInputs[provider.rawValue] = ""
                                            hasChanges = true
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled((subscriptionTokenInputs[provider.rawValue] ?? "").isEmpty)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isConn ? Color.green.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        )
    }

    @ObservedObject private var localLLM = LocalLLMService.shared
    
    @State private var showModelBrowser = false
    
    private var localLLMSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Text("Local LLM")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                
                Button(action: { showModelBrowser = true }) {
                    Label("Model Browser", systemImage: "square.grid.2x2")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                
                Button(action: { Task { await localLLM.scanForServers() } }) {
                    HStack(spacing: 4) {
                        if localLLM.isScanning {
                            ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 11))
                        }
                        Text(localLLM.isScanning ? "Scanning..." : "Scan")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(localLLM.isScanning)
            }
            
            // Detected servers
            if localLLM.detectedServers.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundColor(.secondary.opacity(0.4))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No servers detected").font(.system(size: 12, weight: .medium))
                        Text("Start LM Studio or Ollama, then click Scan.").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.03)).cornerRadius(8)
            } else {
                ForEach(Array(localLLM.detectedServers.enumerated()), id: \.element.id) { index, server in
                    localServerRow(server: server, index: index)
                }
            }
            
            // Installed models
            if let server = localLLM.activeServer, !server.models.isEmpty {
                Divider()
                Text("Installed Models").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary)
                
                ForEach(server.models) { model in
                    installedModelRow(model: model)
                }
            }
            
            // Custom endpoint
            Divider()
            HStack(spacing: 8) {
                Text("Custom:").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                TextField("Host", text: $localLLM.customHost).textFieldStyle(.roundedBorder).frame(width: 120).font(.system(size: 11, design: .monospaced))
                Text(":").foregroundColor(.secondary)
                TextField("Port", text: $localLLM.customPort).textFieldStyle(.roundedBorder).frame(width: 60).font(.system(size: 11, design: .monospaced))
                Spacer()
                if let t = localLLM.lastScanTime { Text("Last: \(t, style: .relative) ago").font(.system(size: 10)).foregroundColor(.secondary) }
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .sheet(isPresented: $showModelBrowser) {
            ModelBrowserSheet(isPresented: $showModelBrowser)
        }
    }
    
    private func localServerRow(server: DetectedLLMServer, index: Int) -> some View {
        let isActive = localLLM.selectedServerIndex == index
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)).frame(width: 28, height: 28)
                Image(systemName: "server.rack").font(.system(size: 13)).foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.type.rawValue).font(.system(size: 12, weight: .semibold))
                    if server.isOnline { Text("ONLINE").font(.system(size: 8, weight: .bold)).foregroundColor(.green).padding(.horizontal, 5).padding(.vertical, 2).background(Color.green.opacity(0.12)).cornerRadius(3) }
                    if isActive { Text("ACTIVE").font(.system(size: 8, weight: .bold)).foregroundColor(.accentColor).padding(.horizontal, 5).padding(.vertical, 2).background(Color.accentColor.opacity(0.12)).cornerRadius(3) }
                }
                Text("\(server.host):\(server.port) — \(server.models.count) model(s)").font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
            if !server.models.isEmpty && isActive {
                Picker("", selection: $localLLM.selectedModelId) {
                    ForEach(server.models) { m in Text(m.displayName).tag(m.id) }
                }.labelsHidden().frame(width: 180)
            }
            if !isActive {
                Button("Use") { localLLM.selectedServerIndex = index; if let f = server.models.first { localLLM.selectedModelId = f.id }; selectedProvider = "local"; hasChanges = true }
                    .font(.system(size: 10, weight: .semibold)).buttonStyle(.bordered)
            }
        }
        .padding(8)
        .background(isActive ? Color.accentColor.opacity(0.04) : Color.clear)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isActive ? Color.accentColor.opacity(0.2) : Color.clear, lineWidth: 1))
    }
    
    private func installedModelRow(model: LocalLLMModel) -> some View {
        let isSelected = localLLM.selectedModelId == model.id
        return HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)).frame(width: 28, height: 28)
                Image(systemName: "cpu").font(.system(size: 12)).foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                HStack(spacing: 4) {
                    if let s = model.size { Text(s).font(.system(size: 9)).foregroundColor(.secondary).padding(.horizontal, 4).padding(.vertical, 1).background(Color.primary.opacity(0.04)).cornerRadius(3) }
                    if let q = model.quantization { Text(q).font(.system(size: 9)).foregroundColor(.secondary).padding(.horizontal, 4).padding(.vertical, 1).background(Color.primary.opacity(0.04)).cornerRadius(3) }
                    if let p = model.parameterSize { Text(p).font(.system(size: 9)).foregroundColor(.secondary).padding(.horizontal, 4).padding(.vertical, 1).background(Color.primary.opacity(0.04)).cornerRadius(3) }
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 14))
            } else {
                Button("Select") { localLLM.selectedModelId = model.id; hasChanges = true }
                    .font(.system(size: 10)).buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.04) : Color.clear)
        .cornerRadius(6)
    }
    
    private func aiProviderKeyCard(_ provider: AIProviderInfo) -> some View {
        let key = Binding<String>(
            get: { providerKeys[provider.id] ?? "" },
            set: { providerKeys[provider.id] = $0; hasChanges = true }
        )
        let isVisible = showAPIKey[provider.id] ?? false
        let hasKey = !(providerKeys[provider.id] ?? "").isEmpty
        let isDefault = selectedProvider == provider.id
        
        return HStack(spacing: 12) {
            // Col 1: Provider Info (Fixed 195pt) with authentic brand icon
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .frame(width: 28, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                    AIProviderBrandIcon(provider: provider.id, size: 18)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(provider.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        if isDefault {
                            Text("ACTIVE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 4).padding(.vertical, 1.5)
                                .background(Color.primary.opacity(0.1))
                                .cornerRadius(3)
                        }
                    }
                    Text(provider.endpoint)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(width: 195, alignment: .leading)
            
            // Col 2: Key Input Field (Flexible)
            HStack(spacing: 8) {
                if isVisible {
                    TextField("API Key...", text: key)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                } else {
                    SecureField("Paste API key here", text: key)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                
                Button {
                    showAPIKey[provider.id] = !isVisible
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(isVisible ? "Hide Key" : "Show Key")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            )
            
            // Col 3: Status / Action (Fixed 72pt, perfectly aligned)
            HStack(spacing: 6) {
                if isDefault {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                        Text("Active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.green)
                    }
                } else if hasKey {
                    Button {
                        selectedProvider = provider.id
                        if let first = provider.models.first { selectedModel = first.id }
                        hasChanges = true
                    } label: {
                        Text("Select")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10).padding(.vertical, 3.5)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "circle.dashed")
                        .foregroundColor(.secondary.opacity(0.35))
                        .font(.system(size: 12))
                }
            }
            .frame(width: 72, alignment: .trailing)
        }
        .frame(minHeight: 38, maxHeight: 38)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isDefault ? Color.primary.opacity(0.05) : Color.clear)
        )
    }
    
    // MARK: - Tools Settings
    
    private var toolsSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionHeader(title: "Code Execution")
            
            Toggle("Auto-run on save", isOn: .constant(false))
            Toggle("Clear console before run", isOn: .constant(true))
            
            SettingsSectionHeader(title: "Git")
            
            Toggle("Auto-fetch on open", isOn: .constant(true))
            Toggle("Show commit message suggestions", isOn: .constant(true))
            
            SettingsSectionHeader(title: "Refactoring")
            
            Toggle("Use AI for refactoring", isOn: .constant(true))
        }
    }
    
    // MARK: - Helpers
    
    private func loadCurrentSettings() {
        selectedProvider = appState.aiProvider
        selectedModel = appState.aiModel
        fontSize = appState.fontSize
        fontFamily = appState.fontFamily
        showLineNumbers = appState.showLineNumbers
        showSidebar = appState.sidebarVisible
        showConsole = appState.consoleVisible
        selectedTheme = appState.appTheme
        
        playgroundFontName = appState.playgroundFontName
        playgroundFontSize = appState.playgroundFontSize
        playgroundFontWeight = appState.playgroundFontWeight
        
        cellFontName = appState.cellFontName
        cellFontSize = appState.cellFontSize
        cellFontWeight = appState.cellFontWeight
        
        agentFontName = appState.agentFontName
        agentFontSize = appState.agentFontSize
        
        agentMode = appState.agentMode
        agentAutoApproveTools = appState.agentAutoApproveTools
        agentCustomInstructions = appState.agentCustomInstructions
        agentMaxIterations = appState.agentMaxIterations
        
        // Load ALL provider keys
        let providers = ["gemini", "openai", "anthropic", "deepseek", "grok", "qwen", "glm"]
        for p in providers {
            providerKeys[p] = appState.apiKeys[p] ?? UserDefaults.standard.string(forKey: "\(p)_api_key") ?? ""
        }
        let legacyKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        if (providerKeys["openai"] ?? "").isEmpty && !legacyKey.isEmpty {
            providerKeys["openai"] = legacyKey
        }
        apiKey = providerKeys[selectedProvider] ?? ""
        let savedKeyMode = UserDefaults.standard.string(forKey: "aiKeyMode")
        aiKeyMode = savedKeyMode ?? "direct"
        microRentToken = UserDefaults.standard.string(forKey: "microRentToken") ?? ""
        dotminiLicenseKey = UserDefaults.standard.string(forKey: "dotminiLicenseKey") ?? ""
    }
    
    private func saveAllSettings() {
        appState.aiProvider = selectedProvider
        appState.aiModel = selectedModel
        appState.fontSize = fontSize
        appState.fontFamily = fontFamily
        appState.showLineNumbers = showLineNumbers
        appState.sidebarVisible = showSidebar
        appState.consoleVisible = showConsole
        appState.appTheme = selectedTheme
        
        appState.playgroundFontName = playgroundFontName
        appState.playgroundFontSize = playgroundFontSize
        appState.playgroundFontWeight = playgroundFontWeight
        
        appState.cellFontName = cellFontName
        appState.cellFontSize = cellFontSize
        appState.cellFontWeight = cellFontWeight
        
        appState.agentFontName = agentFontName
        appState.agentFontSize = agentFontSize
        
        appState.agentMode = agentMode
        appState.agentAutoApproveTools = agentAutoApproveTools
        appState.agentCustomInstructions = agentCustomInstructions
        appState.agentMaxIterations = agentMaxIterations
        
        // Save ALL provider keys
        let defaults = UserDefaults.standard
        defaults.set(aiKeyMode, forKey: "aiKeyMode")
        defaults.set(dotminiLicenseKey, forKey: "dotminiLicenseKey")
        defaults.set(agentFontName, forKey: "agentFontName")
        defaults.set(Double(agentFontSize), forKey: "agentFontSize")
        defaults.set(Double(fontSize), forKey: "fontSize")
        defaults.set(fontFamily, forKey: "fontFamily")
        defaults.set(playgroundFontName, forKey: "playgroundFontName")
        defaults.set(Double(playgroundFontSize), forKey: "playgroundFontSize")
        defaults.set(playgroundFontWeight, forKey: "playgroundFontWeight")
        defaults.set(cellFontName, forKey: "cellFontName")
        defaults.set(Double(cellFontSize), forKey: "cellFontSize")
        defaults.set(cellFontWeight, forKey: "cellFontWeight")
        defaults.set(agentMode, forKey: "agentMode")
        defaults.set(agentAutoApproveTools, forKey: "agentAutoApproveTools")
        defaults.set(agentCustomInstructions, forKey: "agentCustomInstructions")
        defaults.set(agentMaxIterations, forKey: "agentMaxIterations")
        for (provider, key) in providerKeys {
            if !key.isEmpty {
                appState.apiKeys[provider] = key
                defaults.set(key, forKey: "\(provider)_api_key")
            }
        }
        if let openai = providerKeys["openai"], !openai.isEmpty {
            defaults.set(openai, forKey: "apiKey")
        }
        
        defaults.set(selectedProvider, forKey: "aiProvider")
        defaults.set(selectedModel, forKey: "aiModel")
        defaults.set(fontSize, forKey: "fontSize")
        defaults.set(fontFamily, forKey: "fontFamily")
        defaults.set(showLineNumbers, forKey: "showLineNumbers")
        defaults.set(showSidebar, forKey: "sidebarVisible")
        defaults.set(showConsole, forKey: "consoleVisible")
        defaults.set(selectedTheme.rawValue, forKey: "appTheme")
        
        defaults.set(playgroundFontName, forKey: "playgroundFontName")
        defaults.set(playgroundFontSize, forKey: "playgroundFontSize")
        defaults.set(playgroundFontWeight, forKey: "playgroundFontWeight")
        
        defaults.set(cellFontName, forKey: "cellFontName")
        defaults.set(cellFontSize, forKey: "cellFontSize")
        defaults.set(cellFontWeight, forKey: "cellFontWeight")
        
        defaults.set(microRentToken, forKey: "microRentToken")
        if !microRentToken.isEmpty {
            setenv("MICRORENT_TOKEN", microRentToken, 1)
            setenv("USE_MICRORENT_PROXY", "1", 1)
        } else {
            unsetenv("MICRORENT_TOKEN")
            setenv("USE_MICRORENT_PROXY", "0", 1)
        }
        
        defaults.synchronize()
    }
    
    private func envVarName(for provider: String) -> String {
        switch provider {
        case "gemini": return "GEMINI_API_KEY"
        case "openai": return "OPENAI_API_KEY"
        case "anthropic": return "ANTHROPIC_API_KEY"
        case "glm": return "GLM_API_KEY"
        case "deepseek": return "DEEPSEEK_API_KEY"
        case "grok": return "GROK_API_KEY"
        case "qwen": return "QWEN_API_KEY"
        default: return "API_KEY"
        }
    }
}

struct SettingsTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct CodexSidebarRow: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .frame(width: 18)
                    .foregroundColor(selected ? .primary : .secondary)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? .primary : .secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.09)
                          : (hovering ? Color.primary.opacity(0.045) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.top, 8)
    }
}

// MARK: - Simulator Sheet

struct SimulatorSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var platform: String = "ios"
    @State private var iosDevices: [SimulatorDevice] = []
    @State private var androidDevices: [(name: String, id: String)] = []
    @State private var flutterEmulators: [(name: String, id: String)] = []
    @State private var selectedDevice: String = ""
    @State private var selectedName: String = ""
    @State private var isLoading: Bool = false
    @State private var statusMessage: String = ""
    @State private var showingCreateSheet: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "iphone")
                    .foregroundColor(.accentColor)
                Text("Launch Simulator")
                    .font(.system(size: 13, weight: .semibold))
                
                Spacer()
                
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Button("Launch") {
                    launchSimulator()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDevice.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Platform picker
                Picker("Platform", selection: $platform) {
                    HStack {
                        Image(systemName: "apple.logo")
                        Text("iOS Simulator")
                    }.tag("ios")
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Android Emulator")
                    }.tag("android")
                    HStack {
                        Image(systemName: "bird.fill")
                        Text("Flutter")
                    }.tag("flutter")
                }
                .pickerStyle(.segmented)
                .onChange(of: platform) { _ in loadDevices() }
                
                HStack {
                    Text("SELECT DEVICE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: { showingCreateSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                            Text("Create")
                        }
                        .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                
                Divider()
                
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading devices...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            if platform == "ios" {
                                ForEach(iosDevices, id: \.udid) { device in
                                    DeviceRow(
                                        name: device.name,
                                        detail: device.runtime,
                                        isSelected: selectedDevice == device.udid,
                                        isBooted: device.state == "Booted"
                                    ) {
                                        selectedDevice = device.udid
                                        selectedName = device.name
                                    }
                                }
                                if iosDevices.isEmpty {
                                    EmptyDeviceView(message: "No iOS simulators found.")
                                }
                            } else if platform == "android" {
                                ForEach(androidDevices, id: \.id) { device in
                                    DeviceRow(
                                        name: device.name,
                                        detail: "Android",
                                        isSelected: selectedDevice == device.id,
                                        isBooted: false
                                    ) {
                                        selectedDevice = device.id
                                        selectedName = device.name
                                    }
                                }
                                if androidDevices.isEmpty {
                                    EmptyDeviceView(message: "No Android emulators found.")
                                }
                            } else {
                                ForEach(flutterEmulators, id: \.id) { emulator in
                                    DeviceRow(
                                        name: emulator.name,
                                        detail: "Flutter Emulator",
                                        isSelected: selectedDevice == emulator.id,
                                        isBooted: false
                                    ) {
                                        selectedDevice = emulator.id
                                        selectedName = emulator.name
                                    }
                                }
                                if flutterEmulators.isEmpty {
                                    EmptyDeviceView(message: "No Flutter emulators found.")
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
            }
            .padding(20)
        }
        .frame(width: 400, height: 400)
        .onAppear { loadDevices() }
        .sheet(isPresented: $showingCreateSheet) {
            CreateDeviceSheet(platform: platform) {
                loadDevices()
            }
        }
    }
    
    private func loadDevices() {
        isLoading = true
        selectedDevice = ""
        selectedName = ""
        
        Task {
            do {
                if platform == "ios" {
                    let devices = try await SimulatorManager.shared.listIOSSimulators()
                    await MainActor.run {
                        iosDevices = devices.sorted { $0.name < $1.name }
                        if iosDevices.isEmpty {
                            statusMessage = "No iOS simulators found. Create one above."
                        } else {
                            statusMessage = ""
                        }
                    }
                } else if platform == "android" {
                    let devices = try await SimulatorManager.shared.listAndroidEmulators()
                    await MainActor.run {
                        androidDevices = devices
                        if androidDevices.isEmpty {
                            statusMessage = "No Android devices found. Create one above."
                        } else {
                            statusMessage = ""
                        }
                    }
                } else {
                    let emulators = try await SimulatorManager.shared.listFlutterEmulators()
                    await MainActor.run {
                        flutterEmulators = emulators
                        if flutterEmulators.isEmpty {
                            statusMessage = "No Flutter emulators found. Create one above."
                        } else {
                            statusMessage = ""
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Error loading devices: \(error.localizedDescription)"
                }
            }
            isLoading = false
        }
    }
    
    private func launchSimulator() {
        statusMessage = "Launching \(selectedName)..."
        
        Task {
            do {
                if platform == "ios" {
                    try await SimulatorManager.shared.bootSimulator(udid: selectedDevice)
                    // Open Simulator app
                    let openSim = Process()
                    openSim.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    openSim.arguments = ["-a", "Simulator"]
                    try? openSim.run()
                    
                    await MainActor.run {
                        appState.consoleOutput += "📱 Launched iOS Simulator: \(selectedName)\n"
                        dismiss()
                    }
                } else if platform == "android" {
                    try await SimulatorManager.shared.launchAndroidEmulator(avdName: selectedDevice)
                    await MainActor.run {
                        appState.consoleOutput += "📱 Launched Android Emulator: \(selectedName)\n"
                        dismiss()
                    }
                } else {
                    // Flutter launch logic
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/local/bin/flutter")
                    process.arguments = ["emulators", "--launch", selectedDevice]
                    try? process.run()
                    
                    await MainActor.run {
                        appState.consoleOutput += "📱 Launched Flutter Emulator: \(selectedName)\n"
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Launch failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct EmptyDeviceView: View {
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

struct CreateDeviceSheet: View {
    let platform: String
    let onCreated: () -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String = ""
    @State private var selectedDeviceType: String = ""
    @State private var selectedRuntime: String = ""
    @State private var androidPackage: String = "system-images;android-33;google_apis;arm64-v8a"
    
    @State private var deviceTypes: [(name: String, id: String)] = []
    @State private var runtimes: [String] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Create \(platform == "ios" ? "Simulator" : "Emulator")")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            
            Divider()
            
            Form {
                Section("Device Info") {
                    TextField("Name", text: $name)
                    
                    if platform == "ios" {
                        Picker("Device Type", selection: $selectedDeviceType) {
                            Text("Select Type").tag("")
                            ForEach(deviceTypes, id: \.id) { type in
                                Text(type.name).tag(type.id)
                            }
                        }
                        
                        Picker("Runtime", selection: $selectedRuntime) {
                            Text("Select Runtime").tag("")
                            ForEach(runtimes, id: \.self) { runtime in
                                Text(runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")).tag(runtime)
                            }
                        }
                    } else {
                        TextField("System Image Package", text: $androidPackage)
                        Text("Example: system-images;android-33;google_apis;arm64-v8a")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
            }
            
            Spacer()
            
            Divider()
            
            HStack {
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.5).padding(.trailing, 8)
                }
                Button("Create") {
                    createDevice()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || (platform == "ios" && (selectedDeviceType.isEmpty || selectedRuntime.isEmpty)) || isLoading)
            }
            .padding()
        }
        .frame(width: 400, height: platform == "ios" ? 400 : 350)
        .onAppear {
            if platform == "ios" {
                fetchIOSOptions()
            }
        }
    }
    
    private func fetchIOSOptions() {
        isLoading = true
        Task {
            do {
                let types = try await SimulatorManager.shared.listAvailableDeviceTypes()
                let runs = try await SimulatorManager.shared.listAvailableRuntimes()
                await MainActor.run {
                    deviceTypes = types.sorted { $0.name < $1.name }
                    runtimes = runs.sorted()
                    if let firstType = deviceTypes.first(where: { $0.name.contains("iPhone 15") }) {
                        selectedDeviceType = firstType.id
                    }
                    if let lastRun = runtimes.last {
                        selectedRuntime = lastRun
                    }
                }
            } catch {
                errorMessage = "Failed to fetch options: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
    
    private func createDevice() {
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                if platform == "ios" {
                    try await SimulatorManager.shared.createIOSSimulator(name: name, deviceTypeId: selectedDeviceType, runtimeId: selectedRuntime)
                } else {
                    try await SimulatorManager.shared.createAndroidEmulator(name: name, package: androidPackage)
                }
                await MainActor.run {
                    onCreated()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
        }
    }
}


struct SimulatorDevice {
    let name: String
    let udid: String
    let state: String
    let runtime: String
}

struct DeviceRow: View {
    let name: String
    let detail: String
    let isSelected: Bool
    let isBooted: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "iphone")
                    .foregroundColor(isBooted ? .green : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isBooted {
                    Text("Running")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                }
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Syntax Highlighter

class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()
    
    private let keywords: [String: [String]] = [
        "swift": ["func", "var", "let", "class", "struct", "enum", "protocol", "extension", "import", "return", "if", "else", "for", "while", "switch", "case", "default", "guard", "throw", "try", "catch", "async", "await", "private", "public", "internal", "fileprivate", "static", "override", "init", "deinit", "self", "super", "nil", "true", "false", "in", "where", "typealias", "associatedtype", "some", "any", "@Published", "@State", "@Binding", "@ObservableObject", "@MainActor"],
        "python": ["def", "class", "import", "from", "return", "if", "elif", "else", "for", "while", "try", "except", "finally", "with", "as", "is", "not", "and", "or", "in", "True", "False", "None", "pass", "break", "continue", "raise", "yield", "lambda", "global", "nonlocal", "assert", "del", "async", "await", "self"],
        "javascript": ["function", "const", "let", "var", "class", "extends", "import", "export", "return", "if", "else", "for", "while", "switch", "case", "default", "try", "catch", "finally", "throw", "async", "await", "new", "this", "super", "true", "false", "null", "undefined", "typeof", "instanceof", "of", "in", "=>"],
        "typescript": ["function", "const", "let", "var", "class", "extends", "import", "export", "return", "if", "else", "for", "while", "switch", "case", "default", "try", "catch", "finally", "throw", "async", "await", "new", "this", "super", "true", "false", "null", "undefined", "typeof", "instanceof", "of", "in", "interface", "type", "enum", "implements", "readonly", "private", "public", "protected", "=>"],
        "rust": ["fn", "let", "mut", "const", "struct", "enum", "impl", "trait", "use", "mod", "pub", "crate", "self", "super", "return", "if", "else", "for", "while", "loop", "match", "async", "await", "move", "ref", "where", "type", "dyn", "static", "unsafe", "extern", "true", "false", "Some", "None", "Ok", "Err"],
        "go": ["func", "var", "const", "type", "struct", "interface", "package", "import", "return", "if", "else", "for", "switch", "case", "default", "go", "select", "chan", "defer", "range", "map", "make", "new", "nil", "true", "false"],
        "java": ["class", "interface", "enum", "extends", "implements", "import", "package", "public", "private", "protected", "static", "final", "abstract", "return", "if", "else", "for", "while", "switch", "case", "default", "try", "catch", "finally", "throw", "throws", "new", "this", "super", "null", "true", "false", "void", "int", "boolean", "String", "@Override"],
        "c": ["int", "char", "float", "double", "void", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "struct", "union", "enum", "typedef", "const", "static", "extern", "sizeof", "NULL", "true", "false", "#include", "#define", "#ifdef", "#ifndef", "#endif"],
        "cpp": ["int", "char", "float", "double", "void", "bool", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "class", "struct", "union", "enum", "typedef", "const", "static", "extern", "virtual", "override", "public", "private", "protected", "namespace", "using", "template", "typename", "new", "delete", "nullptr", "true", "false", "#include", "#define"],
        "html": ["html", "head", "body", "div", "span", "p", "a", "img", "ul", "ol", "li", "table", "tr", "td", "th", "form", "input", "button", "script", "style", "link", "meta", "title", "class", "id", "href", "src"],
        "css": ["color", "background", "margin", "padding", "border", "font", "display", "position", "top", "left", "right", "bottom", "width", "height", "flex", "grid", "justify", "align", "transform", "transition", "animation", "@media", "@keyframes", "hover", "active", "focus"]
    ]
    
    func highlight(_ code: String, language: String, fontSize: CGFloat, theme: AppTheme) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: code)
        let fullRange = NSRange(location: 0, length: code.utf16.count)
        
        // Base attributes from theme
        attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), range: fullRange)
        attributedString.addAttribute(.foregroundColor, value: theme.editorText, range: fullRange)
        
        // Get language keywords
        let lang = language.lowercased()
        let langKeywords = keywords[lang] ?? keywords["javascript"] ?? []
        
        // Highlight comments first (so they override everything else)
        highlightPattern(in: attributedString, pattern: "//[^\n]*", color: theme.commentColor)
        highlightPattern(in: attributedString, pattern: "#[^\n]*", color: theme.commentColor)
        highlightPattern(in: attributedString, pattern: "/\\*[\\s\\S]*?\\*/", color: theme.commentColor)
        
        // Highlight strings
        highlightPattern(in: attributedString, pattern: "\"[^\"\\\\]*(\\\\.[^\"\\\\]*)*\"", color: theme.stringColor)
        highlightPattern(in: attributedString, pattern: "'[^'\\\\]*(\\\\.[^'\\\\]*)*'", color: theme.stringColor)
        highlightPattern(in: attributedString, pattern: "`[^`]*`", color: theme.stringColor)
        
        // Highlight numbers
        highlightPattern(in: attributedString, pattern: "\\b\\d+(\\.\\d+)?\\b", color: theme.numberColor)
        highlightPattern(in: attributedString, pattern: "\\b0x[0-9a-fA-F]+\\b", color: theme.numberColor)
        
        // Highlight keywords
        for keyword in langKeywords {
            // Escape special regex characters in keyword
            let escapedKeyword = NSRegularExpression.escapedPattern(for: keyword)
            highlightPattern(in: attributedString, pattern: "\\b\(escapedKeyword)\\b", color: theme.keywordColor)
        }
        
        // Highlight types (capitalized words - classes, structs, etc.)
        highlightPattern(in: attributedString, pattern: "\\b[A-Z][a-zA-Z0-9_]*\\b", color: theme.typeColor)
        
        // Highlight function calls
        highlightPattern(in: attributedString, pattern: "\\b[a-z_][a-zA-Z0-9_]*(?=\\()", color: theme.functionColor)
        
        // Highlight decorators/attributes (Swift, Python, Java)
        highlightPattern(in: attributedString, pattern: "@[a-zA-Z_][a-zA-Z0-9_]*", color: theme.keywordColor)
        
        return attributedString
    }
    
    private func highlightPattern(in attributedString: NSMutableAttributedString, pattern: String, color: NSColor) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let string = attributedString.string
        let range = NSRange(location: 0, length: string.utf16.count)
        
        regex.enumerateMatches(in: string, options: [], range: range) { match, _, _ in
            if let matchRange = match?.range {
                attributedString.addAttribute(.foregroundColor, value: color, range: matchRange)
            }
        }
    }
}

// MARK: - Modular Sheet Modifiers for Fast Type-Checking

struct PrimarySheetsModifier: ViewModifier {
    @ObservedObject var appState: AppState

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $appState.showingRefactorProWindow) {
                RefactorProWindow()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showingExpandCodeWindow) {
                ExpandCodeWindow()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showingFormatCodeWindow) {
                FormatCodeWindow()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showingDotnetProject) {
                DotnetProjectView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showingAITrainer) {
                AITrainerView()
            }
            .sheet(isPresented: $appState.showingPythonEnv) {
                PythonEnvSheet()
            }
            .sheet(isPresented: $appState.showingRuntimeManager) {
                RuntimeManagerView()
            }
    }
}

struct SecondarySheetsModifier: ViewModifier {
    @ObservedObject var appState: AppState

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $appState.showingGitSettings) {
                GitSettingsView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showingCodeAnalysis) {
                CodeAnalysisView()
                    .environmentObject(appState)
                    .frame(minWidth: 900, minHeight: 600)
            }
            .sheet(isPresented: $appState.showingCommitDialog) {
                CommitSheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showingSettingsDialog) {
                SettingsView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showingSimulatorDialog) {
                SimulatorSheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showingNewFileDialog) {
                NewFileSheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showingSubAgentMonitor) {
                SubAgentMonitorView()
                    .environmentObject(appState)
            }
    }
}

struct StudioSheetsModifier: ViewModifier {
    @ObservedObject var appState: AppState

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $appState.showingCollaborationView) {
                CollaborationView()
                    .environmentObject(appState)
                    .frame(minWidth: 700, minHeight: 500)
            }
            .sheet(isPresented: $appState.showingCICDView) {
                CICDPipelineView()
                    .environmentObject(appState)
                    .frame(minWidth: 950, minHeight: 650)
            }
            .sheet(isPresented: $appState.showingDatabaseStudio) {
                DatabaseStudioView()
                    .environmentObject(appState)
                    .frame(minWidth: 1000, minHeight: 700)
            }
            .sheet(isPresented: $appState.showingContainerView) {
                ContainerView()
                    .environmentObject(appState)
                    .frame(minWidth: 950, minHeight: 650)
            }
            .sheet(isPresented: $appState.showingProjectRuntime) {
                ProjectRuntimeView()
            }
    }
}

