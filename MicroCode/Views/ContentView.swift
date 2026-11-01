//
//  ContentView.swift
//  MicroCode
//
//  Created by Tirawat Nantamas
//  Copyright © 2024 Dotmini Company Limited. All rights reserved.
//

import SwiftUI
import AppKit

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var isWorkspaceMounted: Bool = true
    // File-based flag survives app re-signing / dev rebuilds (unlike @AppStorage)
    @State private var welcomeCompleted: Bool = {
        let flag = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MicroCode/.welcome_done")
        return FileManager.default.fileExists(atPath: flag.path)
    }()

    var body: some View {
        ZStack {
            if isWorkspaceMounted {
                AgenticEditorWorkspace()
                    .environmentObject(appState)
                    .ignoresSafeArea(.all, edges: .top)
                    .overlay(autoHealerOverlay)
                    .overlay(welcomeOverlay)
                    .modifier(PrimarySheetsModifier(appState: appState))
                    .modifier(SecondarySheetsModifier(appState: appState))
                    .modifier(StudioSheetsModifier(appState: appState))
                    .modifier(GlobalKeyboardShortcutsModifier(appState: appState))
            } else {
                Color(nsColor: appState.appTheme.workspaceBackground)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            if !isWorkspaceMounted {
                DispatchQueue.main.async {
                    isWorkspaceMounted = true
                }
            }
        }
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
                appState.aiChatVisible.toggle()
            }
                .keyboardShortcut("l", modifiers: .command)
                .hidden()
        )
        .background(
            Button("") {
                appState.toggleSidebar()
            }
                .keyboardShortcut("b", modifiers: .command)
                .hidden()
        )
        .overlay(
            Group {
                if (appState.appTheme == .christmas || appState.appTheme == .christmasLight) {
                    SnowEffectView()
                        .allowsHitTesting(false)
                }
                
                if (appState.appTheme == .christmas || appState.appTheme == .christmasLight || appState.appTheme == .happyNewYear2026 || appState.appTheme == .happyNewYear2026Light) {
                    FestiveOverlayView()
                        .allowsHitTesting(false)
                }
            }
        )
    }

    @ViewBuilder
    private var welcomeOverlay: some View {
        if !welcomeCompleted || appState.showingFirstLaunchWelcome {
            FirstLaunchWelcomeView {
                // Write file-based flag so it survives app re-signing
                let dir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/MicroCode")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                FileManager.default.createFile(
                    atPath: dir.appendingPathComponent(".welcome_done").path,
                    contents: Data(), attributes: nil
                )
                withAnimation(.easeOut(duration: 0.2)) {
                    welcomeCompleted = true
                    appState.showingFirstLaunchWelcome = false
                }
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

struct SidebarResizeSplitter: View {
    @Binding var width: Double
    var onCollapse: (() -> Void)? = nil

    var body: some View {
        NativePaneResizeSplitter(
            edge: .leadingPane,
            width: $width,
            minWidth: 160,
            maxWidth: 600,
            visualWidth: 6,
            showsGripPill: true,
            collapseThreshold: 95,
            onCollapse: onCollapse,
            onDoubleClick: {
                withAnimation(.easeInOut(duration: 0.16)) {
                    width = 270
                }
            }
        )
        .frame(width: 6)
        .zIndex(30)
    }
}

struct WorkspaceSidebarToggleButton: View {
    @EnvironmentObject var appState: AppState
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.22)) {
                appState.toggleSidebar()
            }
        }) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHovered ? .primary : (appState.sidebarVisible ? .primary.opacity(0.8) : .secondary))
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.primary.opacity(0.1) : (appState.sidebarVisible ? Color.clear : Color.primary.opacity(0.08)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHovered ? Color.primary.opacity(0.18) : (appState.sidebarVisible ? Color.clear : Color.primary.opacity(0.12)), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(appState.sidebarVisible ? "Hide Sidebar (⌘B)" : "Show Sidebar (⌘B)")
    }
}

struct AgenticEditorWorkspace: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var agent = AgentService.shared
    @State private var surface: AgenticWorkspaceSurface = .agent
    @State private var shortcutMonitor: Any? = nil
    @ObservedObject private var previewDock = PreviewDockService.shared
    @ObservedObject private var deviceRuntime = DeviceRuntimeService.shared
    @AppStorage("microcode_agentic_sidebar_width") private var sidebarWidth: Double = 270

    private var targetSidebarWidth: CGFloat {
        CGFloat(max(160, min(600, sidebarWidth)))
    }

    private var effectiveSidebarWidth: CGFloat {
        appState.sidebarVisible ? targetSidebarWidth : 0
    }

    /// Modes that manage their own left sidebar and don't need the global file browser.
    /// These modes (Embedded Studio, Browser, API Client, Remote Explorer) have
    /// specialized sidebars with mode-specific navigation.
    private var modeHasOwnSidebar: Bool {
        [.embedded, .browser, .apiClient, .remoteX, .notebook, .playground].contains(appState.editorMode)
    }

    private var shouldShowWelcome: Bool {
        (appState.workspaceFolder == nil && appState.openFiles.isEmpty && appState.editorMode == .code) || appState.showingWelcomeHome
    }

    var body: some View {
        Group {
            if shouldShowWelcome {
                WelcomeScreen(surface: $surface)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        appState.appTheme.isGlass
                            ? AnyView(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
                            : AnyView(Color(nsColor: appState.appTheme.workspaceBackground))
                    )
            } else {
                HStack(spacing: 0) {
                    // Collapsible Left Sidebar & Splitter Container
                    // Hidden for modes that manage their own sidebar (Embedded Studio, etc.)
                    if !modeHasOwnSidebar {
                        Group {
                            if surface == .editor {
                                XcodeEditorSidebar(surface: $surface)
                            } else {
                                AgenticWorkspaceSidebar(surface: $surface)
                            }
                        }
                        .frame(width: effectiveSidebarWidth, alignment: .leading)
                        .clipped()
                        .layoutPriority(2)
                        .opacity(appState.sidebarVisible ? 1 : 0)
                        .allowsHitTesting(appState.sidebarVisible)
                        .accessibilityHidden(!appState.sidebarVisible)
                        .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground))

                        if appState.sidebarVisible {
                            SidebarResizeSplitter(
                                width: $sidebarWidth,
                                onCollapse: {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        appState.toggleSidebar()
                                    }
                                }
                            )
                        }
                    }

                    VStack(spacing: 0) {
                        workspaceHeader
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 1)

                        if surface == .agent {
                            AIAgentView(allowsChatSidebar: false)
                                .environmentObject(appState)
                        } else {
                            activeEditorSurface
                        }
                    }
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .layoutPriority(0)

                    if appState.agenticContextVisible {
                        AgenticContextInspector(surface: $surface)
                            .layoutPriority(1)
                    }
                }
                .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.workspaceBackground))
            }
        }
        .onAppear {
            PhoneCompanionService.shared.appState = appState
            if PhoneCompanionService.shared.isEnabled {
                PhoneCompanionService.shared.startServerIfNeeded()
            }
            if let workspace = appState.workspaceFolder {
                agent.setWorkspace(workspace.path)
            }
            surface = (appState.editorMode == .aiAgent) ? .agent : .editor
            installFastShortcutMonitorIfNeeded()
        }
        .onDisappear {
            if let monitor = shortcutMonitor {
                NSEvent.removeMonitor(monitor)
                shortcutMonitor = nil
            }
        }
        .onChange(of: appState.editorMode) { newMode in
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                let targetSurface: AgenticWorkspaceSurface = (newMode == .aiAgent) ? .agent : .editor
                if surface != targetSurface {
                    surface = targetSurface
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeWorkspaceChanged"))) { notif in
            if let path = notif.object as? String, !path.isEmpty {
                let normalizedNew = URL(fileURLWithPath: path).standardizedFileURL.path
                let normalizedCurrent = appState.workspaceFolder?.standardizedFileURL.path
                if normalizedCurrent != normalizedNew {
                    Task { @MainActor in
                        await appState.openWorkspace(url: URL(fileURLWithPath: normalizedNew))
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeOpenFileURL"))) { notif in
            if let url = notif.object as? URL {
                Task { @MainActor in
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                        if isDir.boolValue {
                            await appState.openWorkspace(url: url)
                            AgentService.shared.setWorkspace(url.path)
                        } else if surface == .agent || appState.editorMode == .aiAgent {
                            PreviewDockService.shared.openFile(url: url, makeActive: true)
                        } else {
                            await appState.loadFile(url: url)
                            surface = .editor
                        }
                    } else if surface == .agent || appState.editorMode == .aiAgent {
                        PreviewDockService.shared.openFileFromReference(url.absoluteString, workspacePath: appState.workspaceFolder?.path)
                    }
                }
            }
        }
    }

    private func installFastShortcutMonitorIfNeeded() {
        guard shortcutMonitor == nil else { return }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else {
                return event
            }
            if flags == [.control] || flags == [.command, .option] {
                switch chars {
                case "0" where flags == [.control]:
                    var tx = Transaction()
                    tx.disablesAnimations = true
                    withTransaction(tx) {
                        appState.showingWelcomeHome.toggle()
                    }
                    return nil
                case "1":
                    appState.switchToMode(.code)
                    return nil
                case "2":
                    appState.switchToMode(.aiAgent)
                    return nil
                case "3":
                    appState.switchToMode(.notebook)
                    return nil
                case "4":
                    appState.switchToMode(.playground)
                    return nil
                case "5":
                    appState.switchToMode(.science)
                    return nil
                case "6":
                    appState.switchToMode(.browser)
                    return nil
                case "7":
                    appState.switchToMode(.remoteX)
                    return nil
                case "8":
                    appState.switchToMode(.embedded)
                    return nil
                case "9":
                    appState.openAPIStudio()
                    return nil
                default:
                    break
                }
            }
            return event
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
        case .extensions:
            ExtensionStudioView()
                .environmentObject(appState)
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
            // Sidebar Toggle (only for modes that use the global file browser)
            if !modeHasOwnSidebar {
                WorkspaceSidebarToggleButton()
            }

            // Breadcrumb (Antigravity-style: project / active task) - only for global modes
            if !modeHasOwnSidebar {
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
            }

            WindowDragSpacerView()
                .frame(minWidth: 8, maxWidth: .infinity, maxHeight: .infinity)

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
                    .help("Build Project (⌘⇧B)")

                    // Preview Menu (Real Device & Simulator Preview)
                    let isPreviewActive = appState.agenticContextVisible && appState.selectedInspectorTab == .preview
                    Menu {
                        Button("WebApp Preview (Localhost)") {
                            DeviceRuntimeService.shared.embeddedDockMode = .web
                            appState.showPreviewInspector(tab: "web")
                        }
                        Button("iOS Simulator") {
                            DeviceRuntimeService.shared.embeddedDockMode = .ios
                            DeviceRuntimeService.shared.showingEmbeddedAppleDock = true
                            appState.showPreviewInspector(tab: "ios")
                        }
                        Button("Android Emulator") {
                            DeviceRuntimeService.shared.embeddedDockMode = .android
                            DeviceRuntimeService.shared.showingEmbeddedAppleDock = false
                            appState.showPreviewInspector(tab: "android")
                        }
                        Button("iPhone USB (Hardware)") {
                            appState.showPreviewInspector(tab: "ios-physical")
                        }
                        Button("Android USB (Hardware)") {
                            appState.showPreviewInspector(tab: "android-physical")
                        }
                        Divider()
                        Button("Choose Device & Run…") {
                            DeviceRuntimeService.shared.showingDeviceRuntimeSheet = true
                        }
                        Button(isPreviewActive ? "Hide Preview Dock (⌥⌘P)" : "Show Preview Dock (⌥⌘P)") {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                appState.togglePreviewInspector()
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
                                .font(.system(size: 11, weight: isPreviewActive ? .semibold : .medium))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7, weight: .semibold))
                        }
                        .foregroundColor(isPreviewActive ? .white : .primary.opacity(0.85))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(isPreviewActive ? Color.white.opacity(0.16) : Color.primary.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isPreviewActive ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1)
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
                    appState.switchToMode(.aiAgent)
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
                    appState.switchToMode(.code)
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
                        appState.switchToMode(.playground)
                    }
                    Button("Cell Mode (Notebook)") {
                        appState.switchToMode(.notebook)
                    }
                    Button("SSH Remote Browser") {
                        appState.switchToMode(.remoteX)
                    }
                    Button("Science Mode") {
                        appState.switchToMode(.science)
                    }
                    Button("IDE Web Browser") {
                        appState.switchToMode(.browser)
                    }
                    Button("Embed & IoT Studio") {
                        appState.switchToMode(.embedded)
                    }
                    Button("API Studio") {
                        appState.openAPIStudio()
                    }
                    Button("Extension Studio") {
                        appState.openExtensionStudio()
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
            let isRightPaneOpen = appState.agenticContextVisible || previewDock.isDockVisible || deviceRuntime.showingEmbeddedDeviceDock || appState.showingPreviewView
            Button(action: {
                withAnimation(.easeInOut(duration: 0.16)) {
                    appState.toggleAgenticContext()
                }
            }) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12))
                    .foregroundColor(isRightPaneOpen ? .accentColor : .secondary)
                    .frame(width: 28, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isRightPaneOpen ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("i", modifiers: [.command])
            .fixedSize()
            .help("Toggle Preview & Context Inspector (⌘I)")

            // Connect with Phone [📱]
            Button(action: {
                appState.settingsSelectedTab = 11
                appState.showingSettingsDialog = true
            }) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Connect with Phone via QR Code")

            // Settings [⚙]
            Button(action: { appState.showingSettingsDialog = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Settings (⌘,)")
        }
        .padding(.leading, (modeHasOwnSidebar || !appState.sidebarVisible) ? 78 : 10)
        .padding(.trailing, 10)
        .frame(height: 36)
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

extension View {
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
    @State private var manuallyExpandedProjectIds: Set<String> = []
    @State private var searchText: String = ""
    @State private var isSearchVisible: Bool = false
    @State private var renamingChatId: String? = nil
    @State private var renameText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
            
            if isSearchVisible {
                sidebarSearchBar
            }
            
            sidebarNewConversationButton
            
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
            
            projectsSection
                .padding(.top, 6)
                .padding(.bottom, 8)
            
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 10)
            
            workspaceFilesSection
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: isFilesExpanded ? .infinity : nil, alignment: .top)
            
            if !isFilesExpanded {
                Spacer(minLength: 0)
            }
            
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
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
        .padding(.trailing, 10)
        .frame(height: 36)
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
            ImplementationPlanManager.shared.clearPlan()
            let ws = appState.workspaceFolder?.path ?? agent.currentWorkspace
            _ = agent.createNewChat(projectPath: ws)
            surface = .agent
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text("New Conversation")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("⌘N")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .frame(height: 30)
    }
    
    
    // MARK: - Projects & Conversations Section (Codex Styled)
    private var estimatedProjectsListHeight: CGFloat {
        let groups = filteredProjectGroups
        if groups.isEmpty { return 30 }
        var total: CGFloat = 6
        for group in groups {
            total += 32
            if isProjectGroupExpanded(group) {
                total += CGFloat(group.chats.count) * 32
            }
        }
        return total
    }

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
            .padding(.top, 4)

            if isProjectsExpanded {
                let groups = filteredProjectGroups
                if groups.isEmpty {
                    Text("No matching conversations")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                } else if isFilesExpanded {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(groups) { group in
                                projectGroupRow(group: group)
                            }
                        }
                    }
                    .frame(height: min(estimatedProjectsListHeight, 220))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(groups) { group in
                                projectGroupRow(group: group)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    if isExpanded {
                        collapsedProjectIds.insert(group.id)
                        manuallyExpandedProjectIds.remove(group.id)
                    } else {
                        collapsedProjectIds.remove(group.id)
                        manuallyExpandedProjectIds.insert(group.id)
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
                        ImplementationPlanManager.shared.clearPlan()
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        HStack(spacing: 10) {
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

            Button(action: {
                appState.settingsSelectedTab = 11
                appState.showingSettingsDialog = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 11))
                    Text("Phone")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Connect with Phone via QR Code")

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

    private func isActiveProjectGroup(_ group: ProjectChatGroup) -> Bool {
        if let ws = appState.workspaceFolder?.path ?? agent.currentWorkspace, !ws.isEmpty, group.projectPath == ws {
            return true
        }
        if let activeId = agent.activeChatId, group.chats.contains(where: { $0.id == activeId }) {
            return true
        }
        return group.id == agent.projectGroups.first?.id
    }

    private func isProjectGroupExpanded(_ group: ProjectChatGroup) -> Bool {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if collapsedProjectIds.contains(group.id) {
            return false
        }
        if manuallyExpandedProjectIds.contains(group.id) {
            return true
        }
        return isActiveProjectGroup(group)
    }
}

