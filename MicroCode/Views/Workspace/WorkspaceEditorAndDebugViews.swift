//
//  WorkspaceEditorAndDebugViews.swift
//  MicroCode
//
//  Created by Tirawat Nantamas
//  Copyright © 2024 Dotmini Company Limited. All rights reserved.
//

import SwiftUI
import AppKit

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
                    appState.showPreviewInspector(tab: "web")
                    IDEBrowserAutomationService.shared.scanActivePorts()
                    if let url = IDEBrowserAutomationService.shared.resolveBestWebAppURL() {
                        DeviceRuntimeService.shared.targetWebURL = url
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
                
                ToolbarButton(icon: "sidebar.right", isActive: appState.agenticContextVisible && appState.selectedInspectorTab == .preview) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        appState.togglePreviewInspector()
                    }
                }
                .help("Toggle Device Preview (⌥⌘P)")
                
                Divider().frame(height: 16).padding(.horizontal, 6)
                
                ToolbarButton(icon: "iphone") {
                    appState.showingSimulatorDialog = true
                }
                .help("Launch Simulator")
                
                Divider().frame(height: 16).padding(.horizontal, 6)
                
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
                
                ToolbarButton(icon: "network", isActive: appState.editorMode == .remoteX, color: appState.editorMode == .remoteX ? .cyan : .primary) {
                    appState.toggleEditorMode(.remoteX)
                }
                .help("Remote X")
                
                Divider().frame(height: 16).padding(.horizontal, 6)
                
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Navigator View (Sidebar)

struct NavigatorView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    var showsToolbar: Bool = true
    var onOpenFile: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            if showsToolbar {
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
                .padding(.vertical, 8)
            }
            
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.055))
            .cornerRadius(6)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            
            // File Tree
            if appState.workspaceFolder != nil {
                // Performance: Using NSOutlineView wrapper (AuthenticFileTree) for efficiency
                AuthenticFileTree(
                    fileTree: $appState.fileTree,
                    revision: appState.fileTreeRevision,
                    searchQuery: searchText,
                    backgroundColor: (appState.appTheme.isGlass || appState.appTheme.usesDarkGlassSidebar) ? .clear : appState.appTheme.panelBackground,
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
        .background {
            if showsToolbar {
                SidebarAdaptiveBackground()
            } else {
                Color.clear
            }
        }
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
             CollaborationService.shared.notifyLocalFileSystemEvent(op: "delete", path: node.path)
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
            if let extIcon = ExtensionManager.shared.iconImage(for: node.name, isDirectory: node.isDirectory, isExpanded: isExpanded) {
                Image(nsImage: extIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: node.isDirectory ? "folder.fill" : fileIcon(for: node.name))
                    .font(.system(size: 13))
                    .foregroundColor(node.isDirectory ? .blue : iconColor(for: node.name))
            }
            
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
            case .extensions:
                ExtensionStudioView()
                    .environmentObject(appState)
            case .code:
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        if !appState.openFiles.isEmpty {
                            EditorTabBar()
                        }
                        
                        if let file = appState.currentFile,
                           appState.currentFileIndex >= 0,
                           appState.currentFileIndex < appState.openFiles.count {
                            let fileURL = URL(fileURLWithPath: file.path)
                            let ext = fileURL.pathExtension.lowercased()
                            
                            // Convert-to banner for .ipynb files
                            if ext == "ipynb" {
                                fileConvertBanner(file: file, ext: ext)
                            }
                            
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        Group {
                            if appState.appTheme.isGlass {
                                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                            } else {
                                Color.compat(nsColor: appState.appTheme.editorBackground)
                            }
                        }
                    )
                    
                    // Live preview canvas on the right (only when AgenticContextInspector is not already visible, preventing duplicate side-by-side Preview docks)
                    if appState.showingPreviewView && !appState.agenticContextVisible {
                        RightPreviewPanel()
                    }
                }
            }
        }
        .id(appState.editorMode.rawValue)
    }
    
    // MARK: - File Convert Banner
    
    @ViewBuilder
    private func fileConvertBanner(file: CodeFile, ext: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 10))
                .foregroundColor(.accentColor)
            
            Text("Jupyter Notebook detected")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(0.8))
            
            Spacer()
            
            // ipynb → Open in Cell Mode (primary action)
            Button(action: {
                convertIpynbToCellMode(file: file)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.2x2.fill")
                    Text("Open in Cell Mode")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            
            // ipynb → Open in Playground (single editor)
            Button(action: {
                convertToPlayground(file: file, ext: ext)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "play.rectangle.fill")
                    Text("Open in Playground")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.06))
    }
    
    private func convertIpynbToCellMode(file: CodeFile) {
        let url = URL(fileURLWithPath: file.path)
        appState.pendingNotebookURL = url
        
        // Switch mode to Cell Mode (.notebook)
        appState.setEditorMode(.notebook)
        
        // Post notification as well in case NotebookView is already mounted
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(
                name: NSNotification.Name("ImportNotebookFile"),
                object: nil,
                userInfo: ["path": file.path]
            )
        }
    }
    
    private func convertToPlayground(file: CodeFile, ext: String) {
        let url = URL(fileURLWithPath: file.path)
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            let langMap: [String: String] = [
                "py": "Python", "r": "R", "jl": "Julia", "sql": "SQL",
                "rb": "Ruby", "js": "JavaScript", "ts": "TypeScript",
                "go": "Go", "rs": "Rust", "cpp": "C++", "c": "C",
                "swift": "Swift", "ipynb": "Python"
            ]
            let lang = langMap[ext] ?? "Python"
            
            let code: String
            if ext == "ipynb" {
                code = extractCodeFromIpynb(content)
            } else {
                code = content
            }
            
            // Switch mode FIRST
            appState.setEditorMode(.playground)
            
            // Post notification AFTER PlaygroundView has mounted
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("LoadPlaygroundCode"),
                    object: nil,
                    userInfo: ["code": code, "language": lang]
                )
            }
        }
    }
    
    private func extractCodeFromIpynb(_ jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cells = json["cells"] as? [[String: Any]] else {
            return jsonString
        }
        
        var codeBlocks: [String] = []
        for cell in cells {
            guard let cellType = cell["cell_type"] as? String,
                  cellType == "code",
                  let source = cell["source"] as? [String] else { continue }
            let code = source.joined()
            if !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                codeBlocks.append(code)
            }
        }
        return codeBlocks.joined(separator: "\n\n# ---\n\n")
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
                            if let extIcon = ExtensionManager.shared.iconImage(for: seg.name, isDirectory: seg.icon.contains("folder")) {
                                Image(nsImage: extIcon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: seg.icon)
                                    .font(.system(size: 11))
                                    .foregroundColor(seg.color)
                            }
                            
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
    @ObservedObject private var previewDock = PreviewDockService.shared
    @AppStorage("rightPreviewPanelWidth") private var previewWidth: Double = 460

    private var effectivePreviewWidth: CGFloat {
        let base = max(220, min(960, CGFloat(previewWidth)))
        if previewDock.isExpandedWidth {
            return min(960, max(base + 180, 640))
        }
        return base
    }

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
        HStack(spacing: 0) {
            NativePaneResizeSplitter(
                edge: .trailingPane,
                width: $previewWidth,
                currentEffectiveWidth: Double(effectivePreviewWidth),
                minWidth: 220,
                maxWidth: 960,
                visualWidth: 6,
                showsGripPill: true,
                collapseThreshold: 120,
                onDragStarted: {
                    if previewDock.isExpandedWidth {
                        previewWidth = Double(effectivePreviewWidth)
                        previewDock.isExpandedWidth = false
                    }
                },
                onCollapse: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        appState.hidePreviewInspector()
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

            EmbeddedDeviceDockView()
                .environmentObject(appState)
                .frame(width: effectivePreviewWidth)
                .clipped()
                .background(
                    Color(nsColor: appState.appTheme.editorBackground)
                )
        }
        .onAppear {
            Task {
                await deviceRuntime.refresh(workspace: appState.workspaceFolder)
            }
        }
    }

    private func autoSelectPlatform() {
        // Intentionally do not auto-boot iOS Simulator or Android Emulator
        // simply because a .swift or .kt file is open in the editor.
        // Runtimes should only start when explicitly requested by the user.
    }
}

// MARK: - Editor Tab Bar

struct EditorTabBar: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(appState.openFiles) { file in
                    let isSelected = file.id == appState.currentFile?.id
                    EditorTab(
                        file: file,
                        isSelected: isSelected,
                        onSelect: { appState.selectFile(file) },
                        onClose: { appState.closeFile(file) }
                    )
                }
                Spacer()
            }
        }
        .frame(height: 30)
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
            if let extIcon = ExtensionManager.shared.iconImage(for: file.name, isDirectory: false) {
                Image(nsImage: extIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
            } else {
                Image(systemName: iconForFile(file.name))
                    .font(.system(size: 11))
                    .foregroundColor(colorForFile(file.name))
            }
            
            // File name
            Text(file.name)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? .primary : .secondary)
                .lineLimit(1)
            
            // Modified indicator
            if file.isUnsaved {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }
            
            // Close button (independent click target)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering || isSelected ? 1 : 0)
            .help("Close Tab (⌘W)")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
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
    @ObservedObject private var collab = CollaborationService.shared
    @State private var text: String
    @State private var loadedFileID: UUID
    @State private var updateTask: Task<Void, Never>? = nil
    @State private var markdownRenderMode: Bool = true
    @State private var showInlineCmdK: Bool = false
    @State private var inlineCmdKPrompt: String = ""
    @State private var isRunningInlineCmdK: Bool = false
    @State private var inlinePreEditSnapshot: String? = nil
    @State private var activeLineBlameSummary: String = ""

    private var isMarkdownFile: Bool {
        let lowerName = file.name.lowercased()
        let lowerLang = file.language.lowercased()
        return lowerLang == "markdown" || lowerName.hasSuffix(".md") || lowerName.hasSuffix(".markdown")
    }

    /// Prevents SwiftUI's first render pass on tab switches from feeding the previous tab's
    /// `@State text` buffer into `SyntaxHighlightedCodeView` paired with the new tab's `fileURL`
    /// and `enableHighlighting` flags before `.onChange(of: file.id)` fires.
    private var effectiveTextBinding: Binding<String> {
        Binding(
            get: { loadedFileID == file.id ? text : file.content },
            set: { newValue in
                loadedFileID = file.id
                text = newValue
            }
        )
    }

    init(file: CodeFile) {
        self.file = file
        self._text = State(initialValue: file.content)
        self._loadedFileID = State(initialValue: file.id)
    }
    
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
                
                if collab.currentSession != nil {
                    let filePeers = collab.remoteCollaborators(inFilePath: file.path)
                    if !filePeers.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(Array(filePeers.prefix(3))) { peer in
                                let peerColor = CollaborationColorHelper.swiftUIColor(fromHex: peer.color)
                                Button {
                                    Task { await collab.jumpToParticipant(peer) }
                                } label: {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(peerColor)
                                            .frame(width: 6, height: 6)
                                        Text("\(peer.displayName) · \(peer.cursorPosition?.isTyping == true ? "กำลังแก้ " : "")Ln \(peer.cursorPosition?.line ?? 1)")
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                            .foregroundColor(peerColor)
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(peerColor.opacity(0.14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(peerColor.opacity(0.45), lineWidth: 1)
                                    )
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .help("คลิกเพื่อกระโดดไปยังบรรทัดที่ \(peer.displayName) กำลังแก้")
                            }
                        }
                    } else {
                        Button(action: { appState.showingCollaborationView = true }) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color.green.opacity(0.85))
                                    .frame(width: 5.5, height: 5.5)
                                Text("Session · \(collab.onlineParticipants().count) online")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Active Team Collaboration Session")
                    }
                }
                
                if !activeLineBlameSummary.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondary.opacity(0.75))
                        Text(activeLineBlameSummary)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.82))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.035))
                    .cornerRadius(4)
                    .help("Live Git Blame for active cursor line")
                }
                
                // Inline Cmd+K AI Edit button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showInlineCmdK.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("Inline Edit (⌘K)")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(showInlineCmdK ? .accentColor : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(showInlineCmdK ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("k", modifiers: [.command])
                
                if isMarkdownFile {
                    HStack(spacing: 1) {
                        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { markdownRenderMode = true } }) {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.richtext")
                                    .font(.system(size: 9.5))
                                Text("Rendered")
                                    .font(.system(size: 9.5, weight: markdownRenderMode ? .semibold : .regular))
                            }
                            .foregroundColor(markdownRenderMode ? .primary : .secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(markdownRenderMode ? Color.primary.opacity(0.12) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { markdownRenderMode = false } }) {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.system(size: 9.5))
                                Text("Source")
                                    .font(.system(size: 9.5, weight: !markdownRenderMode ? .semibold : .regular))
                            }
                            .foregroundColor(!markdownRenderMode ? .primary : .secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(!markdownRenderMode ? Color.primary.opacity(0.12) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(2)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(5)
                }
                
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
            .frame(height: 28)
            .background(Color.compat(nsColor: .windowBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Inline Cmd+K Prompt & Review Bar
            if showInlineCmdK || inlinePreEditSnapshot != nil {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                    
                    TextField("Describe how to edit \(file.name) (e.g., refactor function, add error handling)...", text: $inlineCmdKPrompt)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .onSubmit {
                            runInlineCmdKEdit()
                        }
                    
                    if isRunningInlineCmdK {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Button(action: runInlineCmdKEdit) {
                            Text("Generate")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.accentColor)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .disabled(inlineCmdKPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    if let snapshot = inlinePreEditSnapshot {
                        Button(action: {
                            inlinePreEditSnapshot = nil
                            showInlineCmdK = false
                            try? text.write(toFile: file.path, atomically: true, encoding: .utf8)
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Accept (⌘↩)")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.14))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: [.command])
                        
                        Button(action: {
                            text = snapshot
                            appState.updateFileContent(snapshot, for: file.id)
                            inlinePreEditSnapshot = nil
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Reject (⎋)")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.14))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.escape, modifiers: [])
                    }
                    
                    Button(action: { showInlineCmdK = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.06))
                Divider()
            }

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
            
            // Rendered Markdown Document View (Default for .md files like implement.md, task.md, walkthrough.md) vs Code Editor
            if isMarkdownFile && markdownRenderMode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        RenderedMarkdownDocumentView(markdown: effectiveTextBinding.wrappedValue)
                            .padding(24)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.compat(nsColor: .textBackgroundColor))
            } else {
                ZStack(alignment: .topLeading) {
                    SyntaxHighlightedCodeView(
                        text: effectiveTextBinding,
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
                        .offset(x: appState.autocompleteRect.origin.x, y: appState.autocompleteRect.origin.y)
                        .zIndex(10)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadedFileID = file.id
            text = file.content
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorLineNumberGutterView.activeLineGitBlameNotification)) { notif in
            guard let info = notif.userInfo,
                  let blamedFile = info["file"] as? String,
                  URL(fileURLWithPath: file.path).standardizedFileURL.path == blamedFile,
                  let summary = info["summary"] as? String else { return }
            activeLineBlameSummary = summary
        }
        .onChange(of: file.id) { _ in
            updateTask?.cancel()
            loadedFileID = file.id
            text = file.content
            activeLineBlameSummary = ""
            appState.dismissCompletions()
        }
        .onChange(of: file.content) { newContent in
            if loadedFileID != file.id || newContent != text {
                loadedFileID = file.id
                text = newContent
            }
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
    
    private func runInlineCmdKEdit() {
        let instruction = inlineCmdKPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, !isRunningInlineCmdK else { return }
        if inlinePreEditSnapshot == nil {
            inlinePreEditSnapshot = text
        }
        isRunningInlineCmdK = true
        let currentCode = text
        let provider = StreamableAIProvider(rawValue: appState.aiProvider) ?? StreamableAIProvider.detect(from: appState.aiModel)
        let model = appState.aiModel.isEmpty ? "gemini-2.5-flash" : appState.aiModel
        let apiKey = appState.resolveApiKey(for: appState.aiProvider)
        
        let sysPrompt = "You are an inline code transformation engine inside MicroCode IDE. Return ONLY the complete updated file content without surrounding markdown code fences or explanations."
        let userPrompt = "File: \(file.name)\nInstruction: \(instruction)\n\nCurrent File Content:\n\(currentCode)"
        
        AIClient.shared.sendMessage(
            prompt: userPrompt,
            systemPrompt: sysPrompt,
            conversationHistory: [],
            provider: provider,
            model: model,
            apiKey: apiKey,
            onToken: { _ in },
            onComplete: { fullResponse in
                DispatchQueue.main.async {
                    self.isRunningInlineCmdK = false
                    var cleaned = fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleaned.hasPrefix("```") {
                        let lines = cleaned.components(separatedBy: .newlines)
                        if lines.count >= 2 {
                            cleaned = lines.dropFirst().dropLast(lines.last?.trimmingCharacters(in: .whitespaces) == "```" ? 1 : 0).joined(separator: "\n")
                        }
                    }
                    if !cleaned.isEmpty {
                        self.text = cleaned
                        self.appState.updateFileContent(cleaned, for: self.file.id)
                    }
                }
            },
            onError: { _ in
                DispatchQueue.main.async {
                    self.isRunningInlineCmdK = false
                }
            }
        )
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

// MARK: - Debug Area (Interactive Terminal & Console Dock)

struct DebugArea: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var terminalManager = TerminalSessionManager.shared
    @ObservedObject private var lspManager = LSPManager.shared
    @AppStorage("mc_debug_area_height") private var panelHeight: Double = 240
    @State private var isMaximized: Bool = false
    @State private var dragStartHeight: Double? = nil

    private var resolvedWorkingDirectory: String {
        if let ws = appState.workspaceFolder?.path, !ws.isEmpty {
            return ws
        }
        return appState.activeTerminalDirectory
    }

    private var allDiagnostics: [(filePath: String, fileName: String, diagnostic: LSPDiagnostic)] {
        var items: [(String, String, LSPDiagnostic)] = []
        for (uri, diags) in lspManager.fileDiagnostics {
            let path = URL(string: uri)?.path ?? uri
            let name = URL(fileURLWithPath: path).lastPathComponent
            for d in diags {
                items.append((path, name, d))
            }
        }
        return items.sorted { lhs, rhs in
            let lSev = lhs.2.severity ?? 9
            let rSev = rhs.2.severity ?? 9
            if lSev != rSev { return lSev < rSev }
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.2.range.start.line < rhs.2.range.start.line
        }
    }

    var body: some View {
        let effectiveHeight: CGFloat = isMaximized ? 520 : CGFloat(max(130, min(520, panelHeight)))

        VStack(spacing: 0) {
            // Drag Resizer Handle
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 4)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragStartHeight == nil {
                                dragStartHeight = isMaximized ? 520 : panelHeight
                                isMaximized = false
                            }
                            if let base = dragStartHeight {
                                panelHeight = max(130, min(520, base - Double(value.translation.height)))
                            }
                        }
                        .onEnded { _ in
                            dragStartHeight = nil
                        }
                )

            // Toolbar with tabs + context actions
            HStack(spacing: 6) {
                HStack(spacing: 0) {
                    ConsoleTabButton(title: "OUTPUT", isSelected: appState.selectedConsoleTab == 0) {
                        appState.selectedConsoleTab = 0
                    }
                    ConsoleTabButton(title: "TERMINAL", isSelected: appState.selectedConsoleTab == 1) {
                        appState.selectedConsoleTab = 1
                    }
                    ConsoleTabButton(
                        title: "PROBLEMS",
                        badgeCount: allDiagnostics.count,
                        isSelected: appState.selectedConsoleTab == 2
                    ) {
                        appState.selectedConsoleTab = 2
                    }
                    ConsoleTabButton(title: "ANALYSIS", isSelected: appState.selectedConsoleTab == 3) {
                        appState.selectedConsoleTab = 3
                    }
                }
                .layoutPriority(2)

                // Multi-Tab Terminal Session Selector (when Terminal tab is active)
                if appState.selectedConsoleTab == 1 {
                    Divider()
                        .frame(height: 14)
                        .padding(.horizontal, 2)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(terminalManager.sessions) { session in
                                let isActive = terminalManager.activeSession?.id == session.id
                                let isSplit = terminalManager.splitSession?.id == session.id
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(session.isRunning ? Color.green : Color.secondary.opacity(0.5))
                                        .frame(width: 6, height: 6)
                                    Text(session.title)
                                        .font(.system(size: 10.5, weight: (isActive || isSplit) ? .semibold : .regular, design: .monospaced))
                                        .lineLimit(1)
                                    if terminalManager.sessions.count > 1 {
                                        Button {
                                            terminalManager.closeSession(session.id)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(isActive ? Color.accentColor.opacity(0.18) : (isSplit ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.05)))
                                )
                                .onTapGesture {
                                    terminalManager.activeSessionID = session.id
                                }
                            }
                        }
                    }

                    if let cwd = terminalManager.activeSession?.workingDirectory, !cwd.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "folder")
                                .font(.system(size: 9))
                            Text(URL(fileURLWithPath: cwd).lastPathComponent)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .layoutPriority(-1)
                        .help(cwd)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    if appState.selectedConsoleTab == 1 {
                        Button {
                            if let session = terminalManager.activeSession {
                                session.dispatchFixWithAIToAgent(fallbackWorkingDir: resolvedWorkingDirectory)
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 9.5))
                                Text("Fix with AI")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Send recent terminal output/error to AI Agent")

                        Button {
                            terminalManager.createSession(
                                workingDirectory: resolvedWorkingDirectory,
                                fontName: appState.playgroundFontName,
                                fontSize: 13,
                                textColor: appState.appTheme.editorText,
                                backgroundColor: appState.appTheme.editorBackground,
                                isTransparent: appState.appTheme == .extraClear
                            )
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .help("New Terminal Tab")

                        Button {
                            terminalManager.toggleSplit(
                                workingDirectory: resolvedWorkingDirectory,
                                fontName: appState.playgroundFontName,
                                fontSize: 13,
                                textColor: appState.appTheme.editorText,
                                backgroundColor: appState.appTheme.editorBackground,
                                isTransparent: appState.appTheme == .extraClear
                            )
                        } label: {
                            Image(systemName: "rectangle.split.2x1")
                                .font(.system(size: 11))
                                .foregroundColor(terminalManager.splitSession != nil ? .accentColor : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Split Terminal Pane")

                        Button {
                            terminalManager.restartActiveSession()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10.5))
                        }
                        .buttonStyle(.borderless)
                        .help("Restart Active Shell")
                    }

                    Button {
                        if appState.selectedConsoleTab == 1 {
                            terminalManager.clearActiveSession()
                        } else if appState.selectedConsoleTab == 2 {
                            lspManager.fileDiagnostics.removeAll()
                        } else {
                            appState.consoleOutput = ""
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help(appState.selectedConsoleTab == 1 ? "Clear Terminal (⌘K)" : "Clear")

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isMaximized.toggle()
                        }
                    } label: {
                        Image(systemName: isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help(isMaximized ? "Restore Panel Size" : "Maximize Panel")

                    Button(action: { appState.toggleConsole() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Close Panel")
                }
                .padding(.trailing, 8)
            }
            .frame(height: 28)
            .background(appState.appTheme == .extraClear ? Color.clear : Color(nsColor: .windowBackgroundColor))

            Divider()

            // Unified-Height Content Stage (keeps Terminal mounted so tab switches never reset PTY)
            ZStack {
                // Tab 1: Persistent Authentic Terminal
                AuthenticTerminal(
                    shell: "/bin/zsh",
                    workingDirectory: resolvedWorkingDirectory,
                    fontName: appState.playgroundFontName,
                    fontSize: 13,
                    textColor: appState.appTheme.editorText,
                    backgroundColor: appState.appTheme.editorBackground,
                    isTransparent: appState.appTheme == .extraClear
                )
                .opacity(appState.selectedConsoleTab == 1 ? 1 : 0)
                .allowsHitTesting(appState.selectedConsoleTab == 1)

                if appState.selectedConsoleTab == 0 {
                    // Tab 0: Output
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
                    .background(appState.appTheme == .extraClear ? Color.clear : Color(nsColor: appState.appTheme.editorBackground))
                } else if appState.selectedConsoleTab == 2 {
                    // Tab 2: Live LSP & Syntax Problems
                    problemsTabView
                        .background(appState.appTheme == .extraClear ? Color.clear : Color(nsColor: appState.appTheme.editorBackground))
                } else if appState.selectedConsoleTab == 3 {
                    // Tab 3: Static Code Analysis
                    CodeAnalysisPanel()
                        .environmentObject(appState)
                }
            }
            .frame(height: effectiveHeight)
            .background(appState.appTheme == .extraClear ? Color.clear : Color(nsColor: appState.appTheme.editorBackground))
        }
    }

    @ViewBuilder
    private var problemsTabView: some View {
        let items = allDiagnostics
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.green.opacity(0.75))
                Text("No problems detected in workspace")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, entry in
                        let isError = (entry.diagnostic.severity ?? 1) == 1
                        let line = entry.diagnostic.range.start.line + 1
                        let col = entry.diagnostic.range.start.character + 1
                        HStack(spacing: 8) {
                            Image(systemName: isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(isError ? .red : .orange)
                                .font(.system(size: 11))
                            Text(entry.diagnostic.message)
                                .font(.system(size: 11.5))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                            Spacer()
                            Text("\(entry.fileName):\(line):\(col)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { @MainActor in
                                await appState.loadFile(url: URL(fileURLWithPath: entry.filePath))
                            }
                        }
                        Divider().opacity(0.3)
                    }
                }
            }
        }
    }
}

struct ConsoleTabButton: View {
    let title: String
    var badgeCount: Int = 0
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    // Never truncate the tab label ("OUT…", "TERM…"); lower-priority
                    // siblings (cwd chip, session list) must give up space instead.
                    .fixedSize(horizontal: true, vertical: false)
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.red.opacity(0.85)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

