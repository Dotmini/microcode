//
//  ContentView.swift
//  CodeTunner
//
//  Created by SPU AI CLUB
//  Copyright © 2024 AIPRENEUR. All rights reserved.
//

import SwiftUI
import AppKit

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // VS Code-style Top Toolbar
            MainToolbar()
            
            // .NET Project Toolbar (shows when .NET project detected)
            DotnetToolbar()
                .environmentObject(appState)
            
            Divider()
            
            // Main Content
            CompatHSplitView {
                // Sidebar (toggleable)
                if appState.sidebarVisible {
                    NavigatorView()
                        .frame(minWidth: 200, idealWidth: 260, maxWidth: 400)
                }
                
                // Editor Area
                EditorArea()
                
                // Inspector Panel (optional)
                if appState.gitPanelVisible {
                    InspectorView()
                        .frame(minWidth: 260, maxWidth: 350)
                }
                
                // AI Agent Panel (Cursor-style inline agent — Premium)
                if appState.aiChatVisible {
                    VStack(spacing: 0) {
                        // Premium gradient header
                        HStack(spacing: 8) {
                            // AI Icon with glow
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.purple.opacity(0.3), .blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 24, height: 24)
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                            }
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text("MicroCode AI")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                
                                // Model name
                                Text(AgentService.shared.selectedModel.isEmpty ? "Ready" : AgentService.shared.selectedModel)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            // Quick model picker
                            Menu {
                                ForEach(["deepseek-coder", "gpt-4o", "claude-sonnet", "gemini-pro", "local"], id: \.self) { m in
                                    Button(m) { AgentService.shared.selectedModel = m }
                                }
                            } label: {
                                Image(systemName: "cpu")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .frame(width: 20, height: 20)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(4)
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 20)
                            .help("Switch Model")
                            
                            // New chat
                            Button {
                                _ = AgentService.shared.createNewChat()
                            } label: {
                                Image(systemName: "plus.message")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .help("New Chat")
                            
                            // Expand to full screen
                            Button {
                                appState.aiChatVisible = false
                                appState.toggleEditorMode(.aiAgent)
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .help("Full Screen Mode")
                            
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    appState.aiChatVisible = false
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .help("Close (⌘L)")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(nsColor: .windowBackgroundColor),
                                    Color.purple.opacity(0.03)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        
                        // Subtle accent line
                        Rectangle()
                            .fill(LinearGradient(colors: [.purple.opacity(0.4), .cyan.opacity(0.3), .purple.opacity(0.1)], startPoint: .leading, endPoint: .trailing))
                            .frame(height: 1)
                        
                        AIAgentView()
                            .environmentObject(appState)
                    }
                    .frame(minWidth: 340, idealWidth: 400, maxWidth: 520)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .overlay(autoHealerOverlay)
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

        .sheet(isPresented: $appState.showingExportWindow) {
            ExportWindow()
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


        .sheet(isPresented: $appState.showingCollaborationView) {
            CollaborationView()
        }
        .sheet(isPresented: $appState.showingContainerView) {
            ContainerView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showingPreviewView) {
            PreviewView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showingDatabaseStudio) {
            DatabaseStudioView()
        }
        .sheet(isPresented: $appState.showingAPIClient) {
            APIClientView()
        }
        .sheet(isPresented: $appState.showingCICDView) {
            CICDPipelineView()
                .frame(minWidth: 900, idealWidth: 1100, minHeight: 650, idealHeight: 800)
        }
        .sheet(isPresented: $appState.showingProjectRuntime) {
            ProjectRuntimeView()
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
                if appState.appTheme != .extraClear && appState.appTheme != .transparent {
                    CyberBackgroundView()
                    Color.compat(nsColor: .windowBackgroundColor).opacity(0.4) // Glassmorphism effect
                } else {
                    Color.clear
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

                Divider().frame(height: 16).padding(.horizontal, 6)

                ToolbarButton(icon: appState.currentProjectType.icon, color: appState.currentProjectType == .nodejs ? .green : appState.currentProjectType == .python ? .blue : appState.currentProjectType == .rust ? .orange : appState.currentProjectType == .dotnet ? .purple : .secondary) {
                    appState.showingProjectRuntime = true
                }
                .help("\(appState.currentProjectType.rawValue) Runtime")
                
                Divider().frame(height: 16).padding(.horizontal, 6)
                
                ToolbarButton(icon: "arrow.triangle.branch", isActive: appState.gitPanelVisible) {
                    appState.toggleGitPanel()
                }
                .help("Toggle Git Panel")
                
                ToolbarButton(icon: "terminal", isActive: appState.consoleVisible) {
                    appState.toggleConsole()
                }
                .help("Toggle Console (⌘J)")
                
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
                
                ToolbarButton(icon: "square.and.arrow.up") {
                    appState.showingExportWindow = true
                }
                .help("Export Code")
                
                ToolbarButton(icon: "play.rectangle", isActive: appState.editorMode == .playground, color: appState.editorMode == .playground ? .accentColor : .primary) {
                    appState.toggleEditorMode(.playground)
                }
                .help("Playground Mode")
                
                ToolbarButton(icon: "book.pages", isActive: appState.editorMode == .notebook, color: appState.editorMode == .notebook ? .accentColor : .primary) {
                    appState.toggleEditorMode(.notebook)
                }
                .help("Notebook Mode")
                
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
                
                ToolbarButton(icon: "macwindow", color: .purple) {
                    appState.showingPreviewView = true
                }
                .help("GUI Preview")
                
                ToolbarButton(icon: "server.rack", color: .indigo) {
                    appState.showingDatabaseStudio = true
                }
                .help("Database Studio")
                
                ToolbarButton(icon: "network", color: .purple) {
                    appState.showingAPIClient = true
                }
                .help("API Client")
                
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
        .background(appState.appTheme == .extraClear ? Color.clear : Color.compat(nsColor: .windowBackgroundColor))
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)
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
            .background(appState.appTheme == .extraClear ? Color.clear : Color.compat(nsColor: .windowBackgroundColor))
            
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
                    onAction: { action in
                        handleAction(action)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyNavigatorView()
            }
        }
        .background(appState.appTheme == .extraClear ? Color.clear : Color.compat(nsColor: .controlBackgroundColor))
    }
    
    private func handleAction(_ action: FileTreeAction) {
        switch action {
        case .openFile(let node):
            Task { @MainActor in await appState.loadFile(url: URL(fileURLWithPath: node.path)) }
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
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .controlBackgroundColor)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.2), Color.clear], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    .frame(width: 64, height: 64)
                
                // MicroCode 'M' interlocking logo using native SF symbols stacked
                ZStack {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                        .offset(x: -8)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                        .offset(x: 8)
                }
            }
            Text("No Folder Open")
                .font(.system(size: 14, weight: .medium, design: .rounded))
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
            case .scenario:
                ScenarioView()
                    .environmentObject(appState)
            case .notebook:
                NotebookView()
                    .environmentObject(appState)
            case .playground:
                PlaygroundView()
                    .environmentObject(appState)
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
            case .code:
                VStack(spacing: 0) {
                    if !appState.openFiles.isEmpty {
                        EditorTabBar()
                    }
                    
                    if let file = appState.currentFile,
                       appState.currentFileIndex >= 0,
                       appState.currentFileIndex < appState.openFiles.count {
                        let fileURL = URL(fileURLWithPath: file.path)
                        let ext = fileURL.pathExtension.lowercased()
                        let previewExtensions = ["png", "jpg", "jpeg", "pdf", "gif", "bmp", "tiff", "webp"]
                        
                        if previewExtensions.contains(ext) {
                            UniversalFilePreview(url: fileURL)
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
                        if appState.appTheme == .transparent {
                            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                        } else if appState.appTheme == .extraClear {
                            Color.clear
                        } else {
                            Color.compat(nsColor: appState.appTheme.editorBackground)
                        }
                    }
                )
            }
        }
        .id(appState.editorMode.rawValue)  // Force re-render when mode changes
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
        .background(appState.appTheme == .extraClear ? Color.clear : Color.compat(nsColor: .windowBackgroundColor))
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
            
            // Code Editor with Syntax Highlighting Engine
            SyntaxHighlightedCodeView(
                text: $text,
                language: file.language,
                fontSize: appState.fontSize,
                isDark: appState.appTheme.isDark,
                themeName: appState.appTheme.rawValue,
                fileURL: URL(fileURLWithPath: file.path)
            )
        }
        .onAppear { text = file.content }
        .onChange(of: file.id) { _ in text = file.content }
        .onChange(of: file.content) { newContent in
            if !file.isUnsaved { text = newContent }
        }
        .onChange(of: text) { newValue in
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
    @State private var commandInput: String = ""
    
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
                VStack(spacing: 0) {
                    TerminalTextView(
                        text: $appState.terminalService.output,
                        font: .monospacedSystemFont(ofSize: 12, weight: .regular),
                        textColor: appState.appTheme.editorText,
                        backgroundColor: appState.appTheme.editorBackground
                    )
                    .frame(minHeight: 80)
                    
                    Divider()
                    
                    // Command input
                    HStack(spacing: 8) {
                        Text("$")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                        
                        TextField("Type command...", text: $commandInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Color(nsColor: appState.appTheme.editorText))
                            .onSubmit {
                                executeCommand()
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(appState.appTheme == .extraClear ? Color.clear : Color(nsColor: .controlBackgroundColor))
                }
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
    
    private func executeCommand() {
        guard !commandInput.isEmpty else { return }
        let cmd = commandInput
        commandInput = ""
        appState.terminalService.sendCommand(cmd)
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

struct WelcomeScreen: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        if appState.openFiles.isEmpty && appState.workspaceFolder == nil {
            // MARK: - Welcome / Empty State
            GeometryReader { geometry in
                ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(nsColor: .textBackgroundColor),
                    Color(nsColor: .textBackgroundColor).opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            VStack(spacing: 32) {
                Spacer()
                
                // App Icon from icns
                // MicroCode Studio Icon Render (Direct SwiftUI equivalent of the new SVG)
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.1, green: 0.11, blue: 0.15), Color(red: 0.05, green: 0.06, blue: 0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 120, height: 120)
                        
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color(red: 0.17, green: 0.18, blue: 0.25), lineWidth: 4)
                        .frame(width: 112, height: 112)
                    
                    HStack(spacing: -6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(Color(red: 0.48, green: 0.64, blue: 0.97)) // Tokyo Night Blue
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(Color(red: 0.97, green: 0.46, blue: 0.56)) // Tokyo Night Pink
                    }
                    .shadow(color: Color(red: 0.73, green: 0.6, blue: 0.97).opacity(0.8), radius: 12, x: 0, y: 0) // Purple glow
                }
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                
                // App Title with colored text
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Text("MicroCode")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.primary)
                        Text(" | ")
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(.secondary)
                        Text("Dotmini Software")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.pink)
                    }
                    
                    Text("AI-Powered Code Editor")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                    .frame(height: 20)
                
                // Quick Actions
                VStack(spacing: 12) {
                    QuickAction(icon: "doc.badge.plus", title: "New File", shortcut: "⌘N") {
                        appState.createNewFile()
                    }
                    QuickAction(icon: "doc", title: "Open File", shortcut: "⌘O") {
                        appState.openFile()
                    }
                    QuickAction(icon: "folder", title: "Open Folder", shortcut: "⌘⇧O") {
                        appState.openFolder()
                    }
                }
                .frame(width: 280)
                
                Spacer()
                
                // Footer
                HStack(spacing: 0) {
                    Text("© 2025 ")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Dotmini Software")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.pink)
                    Text(" · All Rights Reserved")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 20)
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .transition(.opacity.animation(.easeInOut(duration: 0.4)))
}
    }
}

struct QuickAction: View {
    let icon: String
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 13))
                
                Spacer()
                
                Text(shortcut)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(width: 260)
            .background(isHovering ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
            .cornerRadius(8)
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
                    Section("Google Gemini") {
                        Button("Gemini 3.1 Pro ✨") { setModel("gemini-3.1-pro", provider: "gemini") }
                        Button("Gemini 2.5 Pro") { setModel("gemini-2.5-pro-preview-05-06", provider: "gemini") }
                        Button("Gemini 2.5 Flash") { setModel("gemini-2.5-flash", provider: "gemini") }
                    }
                    Section("OpenAI") {
                        Button("GPT‑5 ✨") { setModel("gpt-5", provider: "openai") }
                        Button("GPT‑4o") { setModel("gpt-4o", provider: "openai") }
                        Button("o3") { setModel("o3", provider: "openai") }
                        Button("o4‑mini") { setModel("o4-mini", provider: "openai") }
                    }
                    Section("Anthropic Claude") {
                        Button("Claude 4.7 Opus ✨") { setModel("claude-4.7-opus-20260501", provider: "anthropic") }
                        Button("Claude Sonnet 4") { setModel("claude-sonnet-4-20250514", provider: "anthropic") }
                        Button("Claude 3.5 Haiku") { setModel("claude-3-5-haiku-20241022", provider: "anthropic") }
                    }
                    Section("DeepSeek") {
                        Button("DeepSeek V4 ✨") { setModel("deepseek-chat-v4", provider: "deepseek") }
                        Button("DeepSeek Chat") { setModel("deepseek-chat", provider: "deepseek") }
                        Button("DeepSeek Coder") { setModel("deepseek-coder", provider: "deepseek") }
                    }
                    Section("Others") {
                        Button("Grok 3") { setModel("grok-3", provider: "grok") }
                        Button("Qwen3 235B") { setModel("qwen3-235b-a22b", provider: "qwen") }
                        Button("GLM‑4.6") { setModel("glm-4.6", provider: "glm") }
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
        switch appState.aiModel {
        case let m where m.contains("gemini-3.1"): return "Gemini 3.1"
        case "gemini-2.5-flash": return "Gemini 2.5"
        case let m where m.contains("gemini-2.5-pro"): return "Gemini Pro"
        case "gpt-5": return "GPT‑5"
        case "gpt-4o": return "GPT‑4o"
        case "gpt-4o-mini": return "GPT‑4o Mini"
        case "o3": return "o3"
        case "o4-mini": return "o4‑mini"
        case let m where m.contains("claude-4.7"): return "Claude Opus"
        case let m where m.contains("claude-sonnet-4"): return "Sonnet 4"
        case let m where m.contains("claude-3-5-sonnet"): return "Sonnet 3.5"
        case let m where m.contains("claude-3-5-haiku"): return "Haiku 3.5"
        case "deepseek-chat-v4": return "DS V4"
        case "deepseek-chat": return "DeepSeek"
        case "deepseek-coder": return "DS Coder"
        case "deepseek-reasoner": return "DS Reason"
        case let m where m.contains("grok"): return "Grok 3"
        case let m where m.contains("qwen"): return "Qwen3"
        case let m where m.contains("glm"): return "GLM‑4"
        default: return String(appState.aiModel.prefix(12))
        }
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
                     HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.5)
                        Text("Thinking...")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
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
            .frame(maxWidth: 320, alignment: message.role == .user ? .trailing : .leading)
            
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
    @State private var isAnimating = false
    @EnvironmentObject var appState: AppState // Bind to use agentStatus
    
    var body: some View {
        HStack(spacing: 8) {
            // Pulsating Orb
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 20, height: 20)
                    .scaleEffect(isAnimating ? 1.2 : 0.8)
                    .opacity(isAnimating ? 0.0 : 0.5)
                
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
            
            // Dynamic Status Text
            Text(appState.agentStatus)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    // Local state for editing
    @State private var selectedProvider: String = ""
    @State private var selectedModel: String = ""
    @State private var apiKey: String = ""
    @State private var fontSize: CGFloat = 13
    @State private var fontFamily: String = "Menlo"
    @State private var showSidebar: Bool = true
    @State private var showConsole: Bool = true
    @State private var selectedTheme: AppTheme = .system
    @State private var playgroundFontName: String = "Menlo"
    @State private var playgroundFontSize: CGFloat = 12.0
    @State private var playgroundFontWeight: Int = 4
    @State private var cellFontName: String = "Menlo"
    @State private var cellFontSize: CGFloat = 13.0
    @State private var cellFontWeight: Int = 2
    @State private var selectedTab: Int = 0
    @State private var hasChanges: Bool = false
    @State private var microRentToken: String = ""
    @State private var authEmail = ""
    @State private var authPassword = ""
    @State private var isAuthenticating = false
    @State private var authError = ""
    @State private var currentPlan: String = "free"
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar Header
            HStack {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.accentColor)
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save Settings") {
                    saveAllSettings()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Tab Bar
            HStack(spacing: 0) {
                SettingsTabButton(title: "General", icon: "gearshape", isSelected: selectedTab == 0) { selectedTab = 0 }
                SettingsTabButton(title: "Editor", icon: "text.cursor", isSelected: selectedTab == 1) { selectedTab = 1 }
                SettingsTabButton(title: "AI", icon: "brain", isSelected: selectedTab == 2) { selectedTab = 2 }
                SettingsTabButton(title: "Tools", icon: "wrench.and.screwdriver", isSelected: selectedTab == 3) { selectedTab = 3 }
                SettingsTabButton(title: "Extensions", icon: "puzzlepiece.extension", isSelected: selectedTab == 5) { selectedTab = 5 }
                SettingsTabButton(title: "Subscription", icon: "crown", isSelected: selectedTab == 6) { selectedTab = 6 }
                SettingsTabButton(title: "About", icon: "info.circle", isSelected: selectedTab == 4) { selectedTab = 4 }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if selectedTab == 0 {
                        generalSettingsContent
                    } else if selectedTab == 1 {
                        editorSettingsContent
                    } else if selectedTab == 2 {
                        aiSettingsContent
                    } else if selectedTab == 3 {
                        toolsSettingsContent
                    } else if selectedTab == 5 {
                        ExtensionSettingsView()
                    } else if selectedTab == 6 {
                        subscriptionSettingsContent
                    } else {
                        aboutContent
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            
            // Footer with copyright
            Divider()
            HStack {
                Text("© 2025 MicroCode | Dotmini Software 2.0. All Rights Reserved.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 600, idealWidth: 700, maxWidth: 900, minHeight: 500, idealHeight: 600, maxHeight: 800)
        .onAppear {
            loadCurrentSettings()
        }
    }
    
    // MARK: - Subscription Content
    
    private var subscriptionSettingsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(title: "MicroRent Plan")
            
            Text("Unlock advanced AI features, unlimited cloud agents, and more with MicroRent.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                // Free Plan
                VStack(alignment: .leading, spacing: 12) {
                    Text("Community Plan")
                        .font(.system(size: 16, weight: .bold))
                    Text("Local IDE & Standard Tools")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    if currentPlan == "free" || currentPlan == "starter" {
                        Text("Active")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke((currentPlan == "free" || currentPlan == "starter") ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1))
                
                // Pro Plan
                VStack(alignment: .leading, spacing: 12) {
                    Text("Professional Plan")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                    Text("Unlimited Cloud Copilot + Advanced Builds")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    if currentPlan == "professional" || currentPlan == "enterprise" {
                        Text("Active")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    } else {
                        Button("Start 30-day Free Trial") {
                            NSWorkspace.shared.open(URL(string: "https://microrentofficial.web.app/auth.html?mode=register&intent=upgrade")!)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.04, green: 0.52, blue: 1.0))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke((currentPlan == "professional" || currentPlan == "enterprise") ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1))
                
                // Enterprise Plan
                VStack(alignment: .leading, spacing: 12) {
                    Text("Enterprise")
                        .font(.system(size: 16, weight: .bold))
                    Text("Custom Tokens + Priority Support")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Button("Contact Sales") {
                        NSWorkspace.shared.open(URL(string: "https://microrentofficial.web.app/enterprise")!)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }
            .padding(.top, 8)
            
            Divider().padding(.vertical, 16)
            
            SettingsSectionHeader(title: "MicroCode Link")
            
            if !microRentToken.isEmpty {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading) {
                        Text("MicroCode Linked Successfully")
                            .font(.system(size: 13, weight: .bold))
                        HStack(spacing: 8) {
                            Text("UID: \(microRentToken)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            
                            Button(action: { checkSubscriptionStatus() }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11))
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("Refresh Status")
                        }
                    }
                    Spacer()
                    Button("Unlink Account") {
                        microRentToken = ""
                        hasChanges = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color.green.opacity(0.05))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.3), lineWidth: 1))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sign In to automatically link your subscription")
                        .font(.system(size: 13, weight: .semibold))
                    
                    TextField("Email Address", text: $authEmail)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                    
                    SecureField("Password", text: $authPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                    
                    if !authError.isEmpty {
                        Text(authError)
                            .foregroundColor(.red)
                            .font(.system(size: 11))
                    }
                    
                    HStack {
                        Button(isAuthenticating ? "Signing In..." : "Sign In via MicroRent") {
                            authenticateWithFirebase()
                        }
                        .disabled(isAuthenticating || authEmail.isEmpty || authPassword.isEmpty)
                        .buttonStyle(.borderedProminent)
                        
                        if isAuthenticating {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.leading, 8)
                        }
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                
                Text("Signed up with Google? Paste your token below instead:")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                
                HStack {
                    SecureField("Manual Access Token", text: $microRentToken)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                        .frame(maxWidth: 400)
                        .onChange(of: microRentToken) { _ in hasChanges = true }
                    
                    Button("Verify") {
                        hasChanges = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(microRentToken.isEmpty)
                }
            }
        }
        .onAppear {
            checkSubscriptionStatus()
        }
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
    
    private var aboutContent: some View {
        VStack(alignment: .center, spacing: 20) {
            Spacer()
            
            // App Icon Graphic
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.05, green: 0.08, blue: 0.15), Color(red: 0.01, green: 0.02, blue: 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 140, height: 140)
                    .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.15), Color.clear], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                    .frame(width: 140, height: 140)
                
                // MicroCode 'M' interlocking logo
                ZStack {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                        .offset(x: -16)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                        .offset(x: 16)
                }
            }
            .padding(.bottom, 8)
            
            // App Name with colored text
            HStack(spacing: 0) {
                Text("MicroCode ")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                Text("PRO")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
            }
            
            Text("Version 2.0")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
            
            Text("Version 2.0.0 (Build 2025.1)")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            Divider()
                .frame(width: 200)
            
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Text("Created by Arsenal @ ")
                        .font(.system(size: 14, weight: .medium))
                    Text("SPU AI")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.pink)
                    Text(" CLUB")
                        .font(.system(size: 14, weight: .medium))
                }
                
                HStack(spacing: 0) {
                    Text("Property of ")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Dotmini Software")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)
                    Text(" 2.0")
                        .font(.system(size: 12, weight: .semibold))
                    Text(" 2025")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Text("ALL RIGHTS RESERVED")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Link("Visit SPU AI CLUB", destination: URL(string: "https://spuaiclub.com")!)
                .font(.system(size: 12))
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - General Settings
    
    private var generalSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                
                // Notebook Cell Font
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: "Notebook Cell Font")
                    
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
                    Toggle("Show line numbers", isOn: .constant(true))
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
        [
            AIProviderInfo(id: "gemini", name: "Google Gemini", icon: "sparkle", color: .blue,
                          endpoint: "generativelanguage.googleapis.com",
                          models: [
                              ("Gemini 3.1 Pro", "gemini-3.1-pro", "NEW"),
                              ("Gemini 2.5 Pro", "gemini-2.5-pro-preview-05-06", ""),
                              ("Gemini 2.5 Flash", "gemini-2.5-flash", "FAST"),
                              ("Gemini 2.5 Flash‑Lite", "gemini-2.5-flash-lite", ""),
                              ("Gemma 3n", "gemma-3n-e4", "OPEN"),
                          ]),
            AIProviderInfo(id: "openai", name: "OpenAI", icon: "brain.head.profile", color: .green,
                          endpoint: "api.openai.com",
                          models: [
                              ("GPT‑5", "gpt-5", "NEW"),
                              ("GPT‑4o", "gpt-4o", ""),
                              ("GPT‑4o Mini", "gpt-4o-mini", "FAST"),
                              ("o3", "o3", "REASON"),
                              ("o4‑mini", "o4-mini", "REASON"),
                          ]),
            AIProviderInfo(id: "anthropic", name: "Anthropic Claude", icon: "aqi.medium", color: .orange,
                          endpoint: "api.anthropic.com",
                          models: [
                              ("Claude 4.7 Opus", "claude-4.7-opus-20260501", "NEW"),
                              ("Claude Sonnet 4", "claude-sonnet-4-20250514", ""),
                              ("Claude 3.5 Sonnet", "claude-3-5-sonnet-20241022", ""),
                              ("Claude 3.5 Haiku", "claude-3-5-haiku-20241022", "FAST"),
                          ]),
            AIProviderInfo(id: "deepseek", name: "DeepSeek", icon: "water.waves", color: .cyan,
                          endpoint: "api.deepseek.com",
                          models: [
                              ("DeepSeek V4", "deepseek-chat-v4", "NEW"),
                              ("DeepSeek Chat", "deepseek-chat", ""),
                              ("DeepSeek Coder", "deepseek-coder", "CODE"),
                              ("DeepSeek Reasoner", "deepseek-reasoner", "REASON"),
                          ]),
            AIProviderInfo(id: "grok", name: "Grok (xAI)", icon: "bolt.fill", color: .purple,
                          endpoint: "api.x.ai",
                          models: [
                              ("Grok 3", "grok-3", "NEW"),
                              ("Grok 3 Mini", "grok-3-mini", "FAST"),
                          ]),
            AIProviderInfo(id: "qwen", name: "Qwen (Alibaba)", icon: "cloud.fill", color: .indigo,
                          endpoint: "dashscope.aliyuncs.com",
                          models: [
                              ("Qwen3 235B‑A22B", "qwen3-235b-a22b", "NEW"),
                              ("Qwen Max", "qwen-max", ""),
                              ("Qwen Plus", "qwen-plus", "FAST"),
                          ]),
            AIProviderInfo(id: "glm", name: "GLM (Zhipu AI)", icon: "globe.asia.australia", color: .red,
                          endpoint: "open.bigmodel.cn",
                          models: [
                              ("GLM‑4.6", "glm-4.6", "NEW"),
                              ("GLM‑4 Plus", "glm-4-plus", ""),
                              ("GLM‑4 Flash", "glm-4-flash", "FAST"),
                          ]),
            AIProviderInfo(id: "local", name: "Local LLM", icon: "desktopcomputer", color: .mint,
                          endpoint: LocalLLMService.shared.activeEndpoint,
                          models: LocalLLMService.shared.availableModels.map {
                              (name: $0.displayName, id: $0.id, badge: $0.size ?? "")
                          } + [("Auto-detect", "local-model", "SCAN")]),
        ]
    }
    
    @State private var providerKeys: [String: String] = [:]
    @State private var showAPIKey: [String: Bool] = [:]
    
    private var aiSettingsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // ── Default Provider & Model ──
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                    Text("Default Provider & Model")
                        .font(.system(size: 13, weight: .bold))
                }
                
                Text("Choose which AI provider and model to use by default in the Agent and Chat.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    // Provider picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Provider")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Picker("", selection: $selectedProvider) {
                            ForEach(aiProviders, id: \.id) { p in
                                Label(p.name, systemImage: p.icon).tag(p.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .onChange(of: selectedProvider) { newValue in
                            hasChanges = true
                            if let provider = aiProviders.first(where: { $0.id == newValue }),
                               let first = provider.models.first {
                                selectedModel = first.id
                            }
                        }
                    }
                    
                    // Model picker (filtered by selected provider)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Picker("", selection: $selectedModel) {
                            if let provider = aiProviders.first(where: { $0.id == selectedProvider }) {
                                ForEach(provider.models, id: \.id) { m in
                                    HStack {
                                        Text(m.name)
                                        if !m.badge.isEmpty {
                                            Text(m.badge)
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }.tag(m.id)
                                }
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                        .onChange(of: selectedModel) { _ in hasChanges = true }
                    }
                }
                
                // Status pill
                if selectedProvider == "local" {
                    if let server = LocalLLMService.shared.activeServer, server.isOnline {
                        HStack(spacing: 6) {
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                            Text("Connected to \(server.type.rawValue)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.green.opacity(0.08))
                        .cornerRadius(6)
                    } else {
                        HStack(spacing: 6) {
                            Circle().fill(Color.orange).frame(width: 7, height: 7)
                            Text("No local server detected — click Scan below")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(6)
                    }
                } else if let key = providerKeys[selectedProvider], !key.isEmpty {
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                        Text("API key configured")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(6)
                } else {
                    HStack(spacing: 6) {
                        Circle().fill(Color.orange).frame(width: 7, height: 7)
                        Text("No API key — set one below")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(6)
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
            
            // ── Provider API Keys ──
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                    Text("API Keys")
                        .font(.system(size: 13, weight: .bold))
                    
                    Spacer()
                    
                    Text("Configure one or more providers. Keys are stored locally.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                // Provider cards grid (exclude local — it has its own panel)
                ForEach(aiProviders.filter { $0.id != "local" }, id: \.id) { provider in
                    aiProviderKeyCard(provider)
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            
            // ── Local LLM Section ──
            localLLMSettingsPanel
            
            // ── MCP Server ──
            mcpSettingsPanel
        }
    }
    
    @ObservedObject private var mcpServer = MCPServer.shared
    
    private var mcpSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 14))
                    .foregroundStyle(LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("MCP Protocol Server")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                
                HStack(spacing: 4) {
                    Circle().fill(mcpServer.isRunning ? .green : .secondary.opacity(0.3)).frame(width: 7, height: 7)
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
                    mcpToolBadge("read_file", icon: "doc.text", color: .blue)
                    mcpToolBadge("write_file", icon: "pencil.and.outline", color: .green)
                    mcpToolBadge("edit_file", icon: "doc.text.fill", color: .orange)
                    mcpToolBadge("search_files", icon: "magnifyingglass", color: .purple)
                    mcpToolBadge("list_files", icon: "folder", color: .cyan)
                    mcpToolBadge("run_terminal", icon: "terminal.fill", color: .mint)
                    mcpToolBadge("git_status", icon: "point.3.filled.connected.trianglepath.dotted", color: .red)
                    mcpToolBadge("get_diagnostics", icon: "exclamationmark.triangle", color: .yellow)
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
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.15), lineWidth: 1))
    }
    
    @ViewBuilder
    private func mcpToolBadge(_ name: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9)).foregroundColor(color)
            Text(name).font(.system(size: 9, design: .monospaced)).foregroundColor(.primary.opacity(0.7))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.06))
        .cornerRadius(4)
    }
    
    @ObservedObject private var localLLM = LocalLLMService.shared
    
    @State private var showModelBrowser = false
    
    private var localLLMSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 14))
                    .foregroundColor(.mint)
                Text("Local LLM")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                
                Button(action: { showModelBrowser = true }) {
                    Label("Model Browser", systemImage: "square.grid.2x2")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.purple)
                
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
                .tint(.mint)
                .disabled(localLLM.isScanning)
            }
            
            // Detected servers
            if localLLM.detectedServers.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 24)).foregroundColor(.secondary.opacity(0.4))
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
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.mint.opacity(0.2), lineWidth: 1))
        .sheet(isPresented: $showModelBrowser) {
            ModelBrowserSheet(isPresented: $showModelBrowser)
        }
    }
    
    private func localServerRow(server: DetectedLLMServer, index: Int) -> some View {
        let isActive = localLLM.selectedServerIndex == index
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(server.isOnline ? Color.green.opacity(0.12) : Color.red.opacity(0.12)).frame(width: 28, height: 28)
                Image(systemName: server.type.icon).font(.system(size: 13)).foregroundColor(server.isOnline ? .green : .red)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.type.rawValue).font(.system(size: 12, weight: .semibold))
                    if server.isOnline { Text("ONLINE").font(.system(size: 8, weight: .bold)).foregroundColor(.white).padding(.horizontal, 5).padding(.vertical, 2).background(Color.green).cornerRadius(3) }
                    if isActive { Text("ACTIVE").font(.system(size: 8, weight: .bold)).foregroundColor(.white).padding(.horizontal, 5).padding(.vertical, 2).background(Color.accentColor).cornerRadius(3) }
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
        .background(isActive ? Color.mint.opacity(0.06) : Color.clear)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isActive ? Color.mint.opacity(0.3) : Color.clear, lineWidth: 1))
    }
    
    private func installedModelRow(model: LocalLLMModel) -> some View {
        let isSelected = localLLM.selectedModelId == model.id
        return HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.purple.opacity(0.1)).frame(width: 28, height: 28)
                Text(String(model.name.prefix(2)).uppercased()).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundColor(.purple)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                HStack(spacing: 4) {
                    if let s = model.size { Text(s).font(.system(size: 9)).foregroundColor(.secondary).padding(.horizontal, 4).padding(.vertical, 1).background(Color.secondary.opacity(0.1)).cornerRadius(3) }
                    if let q = model.quantization { Text(q).font(.system(size: 9)).foregroundColor(.blue).padding(.horizontal, 4).padding(.vertical, 1).background(Color.blue.opacity(0.1)).cornerRadius(3) }
                    if let p = model.parameterSize { Text(p).font(.system(size: 9)).foregroundColor(.orange).padding(.horizontal, 4).padding(.vertical, 1).background(Color.orange.opacity(0.1)).cornerRadius(3) }
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
        .background(isSelected ? Color.purple.opacity(0.04) : Color.clear)
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
            // Provider icon + name
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(provider.color.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: provider.icon)
                        .font(.system(size: 13))
                        .foregroundColor(provider.color)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(.system(size: 12, weight: .semibold))
                        if isDefault {
                            Text("DEFAULT")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.accentColor)
                                .cornerRadius(3)
                        }
                    }
                    Text(provider.endpoint)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 180, alignment: .leading)
            
            // Key field
            HStack(spacing: 6) {
                if isVisible {
                    TextField("sk-...", text: key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                } else {
                    SecureField("Paste API key here", text: key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }
                
                // Toggle visibility
                Button(action: { showAPIKey[provider.id] = !isVisible }) {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(isVisible ? "Hide key" : "Show key")
            }
            
            // Status
            if hasKey {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                    .help("Key configured")
            } else {
                Image(systemName: "circle.dashed")
                    .foregroundColor(.secondary.opacity(0.4))
                    .font(.system(size: 14))
                    .help("No key set")
            }
            
            // Set as default
            if hasKey && !isDefault {
                Button(action: {
                    selectedProvider = provider.id
                    if let first = provider.models.first { selectedModel = first.id }
                    hasChanges = true
                }) {
                    Text("Use")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Set as default provider")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isDefault ? Color.accentColor.opacity(0.04) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDefault ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08), lineWidth: 1)
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
        showSidebar = appState.sidebarVisible
        showConsole = appState.consoleVisible
        selectedTheme = appState.appTheme
        
        playgroundFontName = appState.playgroundFontName
        playgroundFontSize = appState.playgroundFontSize
        playgroundFontWeight = appState.playgroundFontWeight
        
        cellFontName = appState.cellFontName
        cellFontSize = appState.cellFontSize
        cellFontWeight = appState.cellFontWeight
        
        // Load ALL provider keys
        let providers = ["gemini", "openai", "anthropic", "deepseek", "grok", "qwen", "glm"]
        for p in providers {
            providerKeys[p] = appState.apiKeys[p] ?? UserDefaults.standard.string(forKey: "\(p)_api_key") ?? ""
        }
        apiKey = providerKeys[selectedProvider] ?? ""
        microRentToken = UserDefaults.standard.string(forKey: "microRentToken") ?? ""
    }
    
    private func saveAllSettings() {
        appState.aiProvider = selectedProvider
        appState.aiModel = selectedModel
        appState.fontSize = fontSize
        appState.fontFamily = fontFamily
        appState.sidebarVisible = showSidebar
        appState.consoleVisible = showConsole
        appState.appTheme = selectedTheme
        
        appState.playgroundFontName = playgroundFontName
        appState.playgroundFontSize = playgroundFontSize
        appState.playgroundFontWeight = playgroundFontWeight
        
        appState.cellFontName = cellFontName
        appState.cellFontSize = cellFontSize
        appState.cellFontWeight = cellFontWeight
        
        // Save ALL provider keys
        let defaults = UserDefaults.standard
        for (provider, key) in providerKeys {
            if !key.isEmpty {
                appState.apiKeys[provider] = key
                defaults.set(key, forKey: "\(provider)_api_key")
            }
        }
        
        defaults.set(selectedProvider, forKey: "aiProvider")
        defaults.set(selectedModel, forKey: "aiModel")
        defaults.set(fontSize, forKey: "fontSize")
        defaults.set(fontFamily, forKey: "fontFamily")
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
