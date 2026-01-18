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
                
                // AI Chat Panel
                if appState.aiChatVisible {
                    AIChatPanel()
                        .environmentObject(appState)
                        .frame(minWidth: 320, idealWidth: 380, maxWidth: 500)
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


        .sheet(isPresented: $appState.showingProjectManager) {
            TaskDashboardView()
                .frame(minWidth: 900, minHeight: 600)
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
                .frame(width: 800, height: 600)
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
                
                ToolbarButton(icon: "bubble.left.and.bubble.right.fill", isActive: appState.aiChatVisible, color: appState.aiChatVisible ? .accentColor : .primary) {
                    appState.toggleAIChat()
                }
                .help("AI Chat")
                
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
                
                // Collaboration & Task Manager
                ToolbarButton(icon: "person.2.fill", color: .cyan) {
                    appState.showingCollaborationView = true
                }
                .help("Realtime Collaboration")
                
                ToolbarButton(icon: "checklist.unchecked", color: .blue) { // New Icon
                    appState.showingProjectManager = true
                }
                .help("Project & Task Manager")
                
                // Embedded Tools (Replaces IDX Cloud Login)
                ToolbarButton(icon: "cpu.fill", color: .orange) {
                    appState.showingEmbeddedTools = true
                }
                .help("Embedded Project Tools")
                .popover(isPresented: $appState.showingEmbeddedTools) {
                    EmbeddedStudioView()
                        .frame(minWidth: 900, minHeight: 600)
                }
                
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
            Image(systemName: "folder")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
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
            case .code:
                VStack(spacing: 0) {
                    if !appState.openFiles.isEmpty {
                        EditorTabBar()
                    }
                    
                    if let file = appState.currentFile {
                        let fileURL = URL(fileURLWithPath: file.path)
                        let ext = fileURL.pathExtension.lowercased()
                        let previewExtensions = ["png", "jpg", "jpeg", "pdf", "gif", "bmp", "tiff", "webp"]
                        
                        if previewExtensions.contains(ext) {
                            UniversalFilePreview(url: fileURL)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            CodeEditor(file: file)
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
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .shadow(color: .pink.opacity(0.3), radius: 20, x: 0, y: 10)
                } else {
                    // Fallback icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(LinearGradient(
                                colors: [Color.pink, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .shadow(color: .pink.opacity(0.3), radius: 20, x: 0, y: 10)
                }
                
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
    @State private var showTaskDashboard: Bool = true // Default to showing tasks
    
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
                
                // Task Dashboard Toggle
                Button(action: { withAnimation { showTaskDashboard.toggle() } }) {
                    Image(systemName: "list.bullet.clipboard")
                        .foregroundColor(showTaskDashboard ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle Task Dashboard")
                
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
                    Section("Gemini") {
                        Button("Gemini 2.5 Pro Preview") { appState.aiModel = "gemini-2.5-pro-preview" }
                        Button("Gemini 2.5 Flash") { appState.aiModel = "gemini-2.5-flash" }
                        Button("Gemini 2.5 Flash Lite") { appState.aiModel = "gemini-2.5-flash-lite" }
                    }
                    Section("OpenAI") {
                        Button("GPT-4o") { appState.aiModel = "gpt-4o" }
                        Button("GPT-4o Mini") { appState.aiModel = "gpt-4o-mini" }
                    }
                    Section("Claude") {
                        Button("Claude 3 Opus") { appState.aiModel = "claude-3-opus-20240229" }
                        Button("Claude 3 Sonnet") { appState.aiModel = "claude-3-sonnet-20240229" }
                    }
                    Section("DeepSeek") {
                        Button("DeepSeek Chat") { appState.aiModel = "deepseek-chat" }
                        Button("DeepSeek Coder") { appState.aiModel = "deepseek-coder" }
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
            
            // Agent Brain Dashboard (Replaces TaskDashboard)
            if showTaskDashboard {
                AgentBrainDashboard()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
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
        case "gemini-2.5-flash": return "Gemini 2.5"
        case "gemini-2.5-pro-preview-05-06": return "Gemini Pro"
        case "gemini-1.5-flash": return "Gemini 1.5"
        case "gpt-4o": return "GPT-4o"
        case "gpt-4o-mini": return "GPT-4o Mini"
        case "claude-3-opus-20240229": return "Claude Opus"
        case "claude-3-sonnet-20240229": return "Claude Sonnet"
        case "deepseek-chat": return "DeepSeek"
        case "deepseek-coder": return "DS Coder"
        case "glm-4": return "GLM-4"
        case "glm-4-flash": return "GLM Flash"
        case "grok-beta": return "Grok Beta"
        case "qwen-max": return "Qwen Max"
        case "qwen-plus": return "Qwen Plus"
        default: return appState.aiModel
        }
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

struct AgentBrainDashboard: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Header
            HStack(spacing: 0) {
                DashboardTabBtn(title: "Plan", icon: "list.clipboard", index: 0, selection: $appState.selectedDashboardTab)
                DashboardTabBtn(title: "Todo", icon: "checklist", index: 1, selection: $appState.selectedDashboardTab)
                DashboardTabBtn(title: "Report", icon: "doc.text", index: 2, selection: $appState.selectedDashboardTab)
                
                Spacer()
                
                Button(action: { appState.refreshArtifacts() }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Refresh Artifacts")
                .padding(.trailing, 8)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if activeContent.isEmpty {
                        Text("No content found.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Text(activeContent)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(12)
                    }
                }
            }
            .frame(maxHeight: 200)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            Rectangle()
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            appState.refreshArtifacts()
        }
    }
    
    var activeContent: String {
        switch appState.selectedDashboardTab {
        case 0: return appState.taskContent
        case 1: return appState.todoContent
        case 2: return appState.walkthroughContent
        default: return ""
        }
    }
}

struct DashboardTabBtn: View {
    let title: String
    let icon: String
    let index: Int
    @Binding var selection: Int
    
    var body: some View {
        Button(action: { selection = index }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: selection == index ? .semibold : .regular))
            }
            .foregroundColor(selection == index ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(selection == index ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

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
    
    // MARK: - About Content
    
    private var aboutContent: some View {
        VStack(alignment: .center, spacing: 20) {
            Spacer()
            
            // App Icon
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.pink, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // App Name with colored text
            HStack(spacing: 0) {
                Text("MicroCode | ")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                Text("Dotmini Software")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                Text(" 2.0")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
            }
            
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
    
    private var aiSettingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Provider Selection Card
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: "AI Provider")
                    
                    Picker("Provider", selection: $selectedProvider) {
                        Text("Google Gemini").tag("gemini")
                        Text("OpenAI").tag("openai")
                        Text("Anthropic Claude").tag("anthropic")
                        Text("GLM (Zhipu AI)").tag("glm")
                        Text("DeepSeek").tag("deepseek")
                        Text("Grok (xAI)").tag("grok")
                        Text("Qwen (Alibaba)").tag("qwen")
                    }
                    .pickerStyle(.menu) // Changed to menu for cleaner look
                    .frame(maxWidth: 300)
                    .onChange(of: selectedProvider) { newValue in
                        hasChanges = true
                        // Set default model logic...
                        switch newValue {
                        case "gemini": selectedModel = "gemini-2.5-flash"
                        case "openai": selectedModel = "gpt-4o"
                        case "anthropic": selectedModel = "claude-3-sonnet"
                        case "glm": selectedModel = "glm-4"
                        case "deepseek": selectedModel = "deepseek-coder"
                        default: break
                        }
                        // Load saved API key
                        apiKey = appState.apiKeys[newValue] ?? UserDefaults.standard.string(forKey: "\(newValue)_api_key") ?? ""
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // Model Selection Card
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: "Model Configuration")
                    
                    Picker("Model", selection: $selectedModel) {
                        if selectedProvider == "gemini" {
                            Section("Gemini 2.5 (Latest)") {
                                Text("Gemini 2.5 Pro Preview").tag("gemini-2.5-pro-preview")
                                Text("Gemini 2.5 Flash").tag("gemini-2.5-flash")
                                Text("Gemini 2.5 Flash Lite").tag("gemini-2.5-flash-lite")
                            }
                            Section("Gemini 1.5") {
                                Text("Gemini 1.5 Pro").tag("gemini-1.5-pro")
                                Text("Gemini 1.5 Flash").tag("gemini-1.5-flash")
                            }
                        } else if selectedProvider == "openai" {
                            Text("GPT-4o").tag("gpt-4o")
                            Text("GPT-4 Turbo").tag("gpt-4-turbo")
                            Text("GPT-3.5 Turbo").tag("gpt-3.5-turbo")
                        } else if selectedProvider == "anthropic" {
                            Text("Claude 3 Opus").tag("claude-3-opus")
                            Text("Claude 3 Sonnet").tag("claude-3-sonnet")
                            Text("Claude 3 Haiku").tag("claude-3-haiku")
                        } else if selectedProvider == "glm" {
                            Text("GLM-4.6").tag("glm-4.6")
                            Text("GLM-4 Plus").tag("glm-4-plus")
                            Text("GLM-4").tag("glm-4")
                            Text("GLM-4 Flash").tag("glm-4-flash")
                        } else if selectedProvider == "deepseek" {
                            Text("DeepSeek Chat").tag("deepseek-chat")
                            Text("DeepSeek Coder").tag("deepseek-coder")
                        } else if selectedProvider == "grok" {
                            Text("Grok Beta").tag("grok-beta")
                        } else if selectedProvider == "qwen" {
                            Text("Qwen Max").tag("qwen-max")
                            Text("Qwen Plus").tag("qwen-plus")
                        }
                    }
                    .frame(maxWidth: 300)
                    .onChange(of: selectedModel) { _ in hasChanges = true }
                    
                    Text("Select the model optimized for your task. Flash models are faster, Pro/Opus models are smarter.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // API Key Card
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: "Authentication")
                    
                    HStack {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: apiKey) { _ in hasChanges = true }
                        
                        if !apiKey.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Your API key is stored securely in the system keychain.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if selectedProvider == "glm" {
                        Divider()
                        Text("Endpoint: https://api.z.ai/api/paas/v4/chat/completions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            }
            .padding(.trailing, 20) // Scroller padding
        }
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
        apiKey = appState.apiKeys[appState.aiProvider] ?? UserDefaults.standard.string(forKey: "\(appState.aiProvider)_api_key") ?? ""
    }
    
    private func saveAllSettings() {
        // Save to AppState
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
        
        // Update API Key in AppState
        if !apiKey.isEmpty {
            appState.apiKeys[selectedProvider] = apiKey
        }
        
        // Save to UserDefaults
        let defaults = UserDefaults.standard
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
        
        if !apiKey.isEmpty {
            defaults.set(apiKey, forKey: "\(selectedProvider)_api_key")
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
